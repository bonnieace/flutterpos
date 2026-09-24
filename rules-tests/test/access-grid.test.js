/**
 * The access grid.
 *
 * Every other suite in this directory tests a path the author thought to test.
 * This one tests the *cross-product*: each tenant-scoped collection, against
 * each of the five operations, against each kind of caller the rules can see.
 * A cell nobody thought about is the cell that leaks, and `list` is the usual
 * one — a role-gated `get` is easy to remember and the collection query behind
 * it is easy to forget.
 *
 * **The expectation table is the point.** It is written from the rules rather
 * than derived from them, so it states what the rules are *meant* to say. A
 * rules edit that changes who may reach a collection fails here even when the
 * dedicated suite for that collection still passes, because the dedicated
 * suite only asks about the callers it already knew about.
 *
 * **What this suite deliberately does not test.** Payload validation. A denial
 * caused by a malformed sale is not a denial caused by a role, and asserting
 * the two together would let a validation change silently satisfy an
 * authorisation assertion. Where a create or update is guarded by heavy field
 * validation the allow-cells are skipped and named, and the deny-cells — which
 * hold whatever the payload is — are still asserted.
 */

import { after, before, test } from "node:test";

import { assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  serverTimestamp,
  setDoc,
  updateDoc,
} from "firebase/firestore";

import {
  authenticatedFirestore,
  createRulesTestEnvironment,
  seedDocuments,
} from "./support.js";

const ACTIVE_TENANT = "tenant-a";
const DARK_TENANT = "tenant-s";
const FOREIGN_TENANT = "tenant-b";

/**
 * The callers.
 *
 * `darkManager` and `darkCashier` are the reason this list is not just the four
 * roles. Their membership is impeccable and their business is suspended, so
 * every cell they appear in proves the rule asked `tradingTenant` rather than
 * membership alone. A gate that was widened by accident shows up here as a
 * member of a dark business who can suddenly read or write.
 */
const PRINCIPALS = [
  { name: "owner", uid: "grid-owner", role: "owner", tenant: ACTIVE_TENANT },
  { name: "admin", uid: "grid-admin", role: "admin", tenant: ACTIVE_TENANT },
  { name: "manager", uid: "grid-manager", role: "manager", tenant: ACTIVE_TENANT },
  { name: "cashier", uid: "grid-cashier", role: "cashier", tenant: ACTIVE_TENANT },
  { name: "darkManager", uid: "grid-dark-manager", role: "manager", tenant: DARK_TENANT },
  { name: "darkCashier", uid: "grid-dark-cashier", role: "cashier", tenant: DARK_TENANT },
  { name: "suspendedCashier", uid: "grid-suspended", role: "cashier", tenant: ACTIVE_TENANT },
  { name: "outsider", uid: "grid-outsider", role: "owner", tenant: ACTIVE_TENANT },
  { name: "anonymous", uid: null, role: null, tenant: ACTIVE_TENANT },
  { name: "platformAdmin", uid: "grid-platform", role: null, tenant: ACTIVE_TENANT },
];

const BY_NAME = new Map(PRINCIPALS.map((principal) => [principal.name, principal]));

/** Members whose standing survives `activeStaff` — active staff of an active tenant. */
const MEMBERS = ["owner", "admin", "manager", "cashier"];

const NONE = [];
const PLATFORM = ["platformAdmin"];

function roleOf(name) {
  return BY_NAME.get(name).role;
}

/** Mirrors `hasTenantRole(tenantId, roles)`. */
function memberRoles(roles) {
  return MEMBERS.filter((name) => roles.includes(roleOf(name)));
}

const SERVER_WRITTEN = {
  create: { allow: NONE },
  update: { allow: NONE },
  delete: { allow: NONE },
};

function slug(principal) {
  return `grid-${principal.name.toLowerCase()}`;
}

/** Date-keyed collections keep date-shaped ids, one per caller. */
function dateId(principal) {
  const index = PRINCIPALS.indexOf(principal) + 1;
  return `2026-08-${String(index).padStart(2, "0")}`;
}

/**
 * The table.
 *
 * `allow` names every caller the rules should admit. Everyone else must be
 * refused — the grid asserts the refusals as loudly as the admissions, because
 * a rule that admits nobody and a rule that admits everybody both pass a suite
 * that only checks the happy path. `skip` names cells this suite declines to
 * judge, always with the reason and always pointing at the suite that does.
 */
const COLLECTIONS = [
  {
    name: "tenants/{tenantId}",
    // The business document itself rather than a document beneath it, so it is
    // seeded by `world()` with the rest of the fixture and takes no per-caller
    // target of its own.
    self: true,
    segment: "",
    docId: () => "",
    seed: {},
    ops: {
      get: { allow: [...MEMBERS, ...PLATFORM] },
      list: {
        allow: NONE,
        skip: PRINCIPALS.map((principal) => principal.name),
        reason: "a query over /tenants spans businesses; tenant-isolation covers it",
      },
      ...SERVER_WRITTEN,
    },
  },
  {
    name: "staff",
    segment: "staff",
    // A colleague's record, never the caller's own, so the `uid ==
    // request.auth.uid` limb is off and only the role limb can admit.
    docId: () => "grid-colleague",
    seed: { uid: "grid-colleague", role: "cashier", status: "active" },
    ops: {
      get: { allow: [...memberRoles(["owner", "admin", "manager"]), ...PLATFORM] },
      list: { allow: [...memberRoles(["owner", "admin", "manager"]), ...PLATFORM] },
      ...SERVER_WRITTEN,
    },
  },
  {
    name: "staff_invitations",
    segment: "staff_invitations",
    docId: (principal) => slug(principal),
    seed: { email: "grid@example.test", role: "cashier", status: "pending" },
    ops: {
      get: { allow: NONE },
      list: { allow: NONE },
      ...SERVER_WRITTEN,
    },
  },
  {
    name: "products",
    segment: "products",
    docId: (principal) => slug(principal),
    seed: { productId: "grid", name: "Grid product", quantity: 10, price: 250 },
    createPayload: () => ({ productId: "grid-new", name: "New", quantity: 4, price: 100 }),
    updatePayload: () => ({ quantity: 9, updatedAt: serverTimestamp() }),
    ops: {
      get: { allow: MEMBERS },
      list: { allow: MEMBERS },
      // Nobody, since 2026-09-13. A create may carry an opening quantity and
      // the ledger entry accounting for it is server-written, so the two have to
      // be one transaction; `createProduct` is it. Update stays wide because the
      // checkout decrement is a client write a cashier makes with no connection.
      create: { allow: NONE },
      update: { allow: MEMBERS },
      // Nobody, since 2026-09-13. "Retire" was this delete, and it took the
      // quantity with it: no movement recorded the stock leaving, past sale
      // lines named an ID nothing answered to, and the ledger below the product
      // was orphaned rather than removed. `setProductRetired` sets a flag and
      // clears the stock through the ledger in one transaction instead.
      delete: { allow: NONE },
    },
  },
  {
    name: "products/{productId}/stock_movements",
    segment: "products/grid-ledger/stock_movements",
    docId: (principal) => slug(principal),
    seed: { movementId: "grid", delta: -1, reason: "sale" },
    ops: {
      get: { allow: memberRoles(["owner", "admin", "manager"]) },
      list: { allow: memberRoles(["owner", "admin", "manager"]) },
      ...SERVER_WRITTEN,
    },
  },
  {
    name: "categories",
    segment: "categories",
    docId: (principal) => slug(principal),
    seed: { name: "Grid category" },
    createPayload: () => ({ name: "New category" }),
    updatePayload: () => ({ name: "Renamed" }),
    ops: {
      get: { allow: MEMBERS },
      list: { allow: MEMBERS },
      // Server-written since 2026-09-14, and unusually it is not about a
      // ledger: two categories folding to one name cannot be told apart when a
      // spreadsheet names that category, and refusing the second one means
      // reading every other category in the collection - which a rule cannot
      // do. `createCategory` and `renameCategory` decide it in the transaction
      // that writes.
      create: { allow: NONE },
      update: { allow: NONE },
      // Still a client delete, and still with no surface that issues one.
      delete: { allow: memberRoles(["owner", "admin", "manager"]) },
    },
  },
  {
    name: "sales",
    segment: "sales",
    docId: (principal) => slug(principal),
    seed: { saleId: "grid", staffId: "grid-colleague", total: 100 },
    ops: {
      get: { allow: MEMBERS },
      list: {
        allow: memberRoles(["owner", "admin", "manager"]),
        skip: ["cashier"],
        reason:
          "a cashier's list is admitted only when scoped to its own uid; sale-history covers the scoped query",
      },
      create: {
        allow: NONE,
        skip: MEMBERS,
        reason:
          "the sale envelope is validated field by field; checkout-submission covers a valid create",
      },
      update: { allow: NONE },
      delete: { allow: NONE },
    },
  },
  {
    name: "shifts",
    segment: "shifts",
    docId: (principal) => slug(principal),
    // Attributed to a colleague, so the `resource.data.staffId ==
    // request.auth.uid` limb is off and only the role limb can admit.
    seed: {
      shiftId: "grid",
      staffId: "grid-colleague",
      status: "open",
      businessDate: "2026-08-27",
    },
    ops: {
      get: { allow: memberRoles(["owner", "admin", "manager"]) },
      list: { allow: memberRoles(["owner", "admin", "manager"]) },
      create: {
        allow: NONE,
        skip: MEMBERS,
        reason:
          "shift opening is validated against device and business date; shift-lifecycle covers a valid create",
      },
      update: {
        allow: NONE,
        skip: MEMBERS,
        reason:
          "shift closing is validated against counted cash; shift-lifecycle covers a valid update",
      },
      delete: { allow: NONE },
    },
  },
  {
    name: "returns",
    segment: "returns",
    docId: (principal) => slug(principal),
    seed: { returnId: "grid", saleId: "grid", status: "pending" },
    ops: {
      get: { allow: MEMBERS },
      list: { allow: MEMBERS },
      create: {
        allow: NONE,
        skip: MEMBERS,
        reason:
          "a return is validated against the sale it refunds; tenant-returns covers a valid create",
      },
      update: { allow: NONE },
      delete: { allow: NONE },
    },
  },
  {
    name: "expenses",
    segment: "expenses",
    docId: (principal) => `2026-08-27-${slug(principal)}`,
    seed: { expenseId: "grid", businessDate: "2026-08-27", category: "rent", amountMinor: 1000 },
    ops: {
      get: { allow: memberRoles(["owner", "admin"]) },
      list: { allow: memberRoles(["owner", "admin"]) },
      create: {
        allow: NONE,
        skip: memberRoles(["owner", "admin"]),
        reason:
          "the expense envelope is validated field by field; tenant-expenses covers a valid create",
      },
      update: {
        allow: NONE,
        skip: memberRoles(["owner", "admin"]),
        reason:
          "an expense correction is validated field by field; tenant-expenses covers a valid update",
      },
      delete: { allow: NONE },
    },
  },
  {
    name: "configuration",
    segment: "configuration",
    docId: (principal) => slug(principal),
    seed: { value: 1 },
    createPayload: () => ({ value: 2 }),
    updatePayload: () => ({ value: 3 }),
    ops: {
      get: { allow: MEMBERS },
      list: { allow: MEMBERS },
      create: { allow: memberRoles(["owner", "admin"]) },
      update: { allow: memberRoles(["owner", "admin"]) },
      delete: { allow: memberRoles(["owner", "admin"]) },
    },
  },
  {
    name: "subscription",
    segment: "subscription",
    docId: (principal) => slug(principal),
    seed: { plan: "grid", status: "active" },
    ops: {
      get: { allow: [...MEMBERS, ...PLATFORM] },
      list: { allow: [...MEMBERS, ...PLATFORM] },
      ...SERVER_WRITTEN,
    },
  },
  {
    name: "daily_metrics",
    segment: "daily_metrics",
    docId: dateId,
    seed: { revenueMinor: 12345, saleCount: 7 },
    ops: {
      get: { allow: memberRoles(["owner", "admin", "manager"]) },
      list: { allow: memberRoles(["owner", "admin", "manager"]) },
      ...SERVER_WRITTEN,
    },
  },
  {
    name: "stock_adjustments",
    segment: "stock_adjustments",
    docId: (principal) => slug(principal),
    seed: { adjustmentId: "grid", delta: -2, reason: "damage" },
    ops: {
      get: { allow: memberRoles(["owner", "admin", "manager"]) },
      list: { allow: memberRoles(["owner", "admin", "manager"]) },
      ...SERVER_WRITTEN,
    },
  },
  {
    name: "suppliers",
    segment: "suppliers",
    docId: (principal) => slug(principal),
    seed: { name: "Grid supplier", active: true },
    ops: {
      get: { allow: memberRoles(["owner", "admin", "manager"]) },
      list: { allow: memberRoles(["owner", "admin", "manager"]) },
      ...SERVER_WRITTEN,
    },
  },
  {
    name: "supplier_deliveries",
    segment: "supplier_deliveries",
    docId: (principal) => slug(principal),
    seed: { supplierId: "grid", lineCount: 1, valueMinor: 5000 },
    ops: {
      get: { allow: memberRoles(["owner", "admin", "manager"]) },
      list: { allow: memberRoles(["owner", "admin", "manager"]) },
      ...SERVER_WRITTEN,
    },
  },
  {
    name: "production_batches",
    segment: "production_batches",
    docId: (principal) => slug(principal),
    seed: { productId: "grid", quantity: 100, unitCostMinor: 3000 },
    ops: {
      get: { allow: memberRoles(["owner", "admin", "manager"]) },
      list: { allow: memberRoles(["owner", "admin", "manager"]) },
      ...SERVER_WRITTEN,
    },
  },
  {
    name: "reconciliation_jobs",
    segment: "reconciliation_jobs",
    docId: (principal) => slug(principal),
    seed: { jobId: "grid", status: "complete" },
    ops: {
      get: { allow: memberRoles(["owner", "admin", "manager"]) },
      list: { allow: memberRoles(["owner", "admin", "manager"]) },
      ...SERVER_WRITTEN,
    },
  },
  {
    name: "reconciliation_dirty_days",
    segment: "reconciliation_dirty_days",
    docId: dateId,
    seed: { businessDate: "2026-08-27", dirty: true },
    ops: {
      get: { allow: memberRoles(["owner", "admin", "manager"]) },
      list: { allow: memberRoles(["owner", "admin", "manager"]) },
      ...SERVER_WRITTEN,
    },
  },
  {
    name: "reconciliation_anomalies",
    segment: "reconciliation_anomalies",
    docId: (principal) => slug(principal),
    seed: { anomalyId: "grid", kind: "missing_sale" },
    ops: {
      get: { allow: memberRoles(["owner", "admin", "manager"]) },
      list: { allow: memberRoles(["owner", "admin", "manager"]) },
      ...SERVER_WRITTEN,
    },
  },
  {
    name: "shift_amendments",
    segment: "shift_amendments",
    docId: (principal) => slug(principal),
    seed: { amendmentId: "grid", shiftId: "grid" },
    ops: {
      get: { allow: memberRoles(["owner", "admin", "manager"]) },
      list: { allow: memberRoles(["owner", "admin", "manager"]) },
      ...SERVER_WRITTEN,
    },
  },
  {
    name: "audit_logs",
    segment: "audit_logs",
    docId: (principal) => slug(principal),
    seed: { action: "grid", actorUid: "grid-colleague" },
    ops: {
      get: { allow: [...memberRoles(["owner", "admin"]), ...PLATFORM] },
      list: { allow: [...memberRoles(["owner", "admin"]), ...PLATFORM] },
      ...SERVER_WRITTEN,
    },
  },
  {
    name: "lifecycle_history",
    segment: "lifecycle_history",
    docId: (principal) => slug(principal),
    seed: { from: "pending", to: "active" },
    ops: {
      get: { allow: PLATFORM },
      list: { allow: PLATFORM },
      ...SERVER_WRITTEN,
    },
  },
];

/**
 * Each caller reads, updates and deletes a document of its own.
 *
 * A shared target would let one caller's successful delete decide the next
 * caller's result, and the grid would report an authorisation finding for what
 * was really an ordering accident.
 */
function targetPath(entry, principal) {
  return `tenants/${principal.tenant}/${entry.segment}/${entry.docId(principal)}`;
}

/** The sibling a delete attempt consumes, so the read cells keep their target. */
function sparePath(entry, principal) {
  return `tenants/${principal.tenant}/${entry.segment}/${slug(principal)}-spare`;
}

function collectionPath(entry, principal) {
  return `tenants/${principal.tenant}/${entry.segment}`;
}

/**
 * The world every cell is evaluated against.
 *
 * Three businesses, because the dark callers need a tenant whose status is
 * `suspended` at the same moment the active callers need one that is `active`,
 * and a caller cannot be a member of a business that is both.
 */
function world() {
  const documents = {
    "users/grid-owner": { accountType: "tenant_user", globalStatus: "active", membershipCount: 1 },
    "users/grid-admin": { accountType: "tenant_user", globalStatus: "active", membershipCount: 1 },
    "users/grid-manager": { accountType: "tenant_user", globalStatus: "active", membershipCount: 1 },
    "users/grid-cashier": { accountType: "tenant_user", globalStatus: "active", membershipCount: 1 },
    "users/grid-dark-manager": { accountType: "tenant_user", globalStatus: "active", membershipCount: 1 },
    "users/grid-dark-cashier": { accountType: "tenant_user", globalStatus: "active", membershipCount: 1 },
    "users/grid-suspended": { accountType: "tenant_user", globalStatus: "active", membershipCount: 1 },
    "users/grid-outsider": { accountType: "tenant_user", globalStatus: "active", membershipCount: 1 },
    "users/grid-platform": { accountType: "platform_admin", globalStatus: "active" },

    [`tenants/${ACTIVE_TENANT}`]: { name: ACTIVE_TENANT, ownerUid: "grid-owner", status: "active" },
    [`tenants/${DARK_TENANT}`]: { name: DARK_TENANT, ownerUid: "grid-dark-owner", status: "suspended" },
    [`tenants/${FOREIGN_TENANT}`]: { name: FOREIGN_TENANT, ownerUid: "grid-outsider", status: "active" },

    [`tenants/${ACTIVE_TENANT}/staff/grid-owner`]: { uid: "grid-owner", role: "owner", status: "active" },
    [`tenants/${ACTIVE_TENANT}/staff/grid-admin`]: { uid: "grid-admin", role: "admin", status: "active" },
    [`tenants/${ACTIVE_TENANT}/staff/grid-manager`]: { uid: "grid-manager", role: "manager", status: "active" },
    [`tenants/${ACTIVE_TENANT}/staff/grid-cashier`]: { uid: "grid-cashier", role: "cashier", status: "active" },
    [`tenants/${ACTIVE_TENANT}/staff/grid-suspended`]: { uid: "grid-suspended", role: "cashier", status: "suspended" },
    [`tenants/${DARK_TENANT}/staff/grid-dark-manager`]: { uid: "grid-dark-manager", role: "manager", status: "active" },
    [`tenants/${DARK_TENANT}/staff/grid-dark-cashier`]: { uid: "grid-dark-cashier", role: "cashier", status: "active" },
    [`tenants/${FOREIGN_TENANT}/staff/grid-outsider`]: { uid: "grid-outsider", role: "owner", status: "active" },
  };

  for (const entry of COLLECTIONS) {
    if (entry.self) continue;
    for (const principal of PRINCIPALS) {
      documents[targetPath(entry, principal)] = { ...entry.seed };
      documents[sparePath(entry, principal)] = { ...entry.seed };
    }
  }

  return documents;
}

let testEnvironment;
const handles = new Map();

before(async () => {
  testEnvironment = await createRulesTestEnvironment();
  await seedDocuments(testEnvironment, world());

  for (const principal of PRINCIPALS) {
    if (principal.name === "anonymous") {
      handles.set(principal.name, testEnvironment.unauthenticatedContext().firestore());
    } else if (principal.name === "platformAdmin") {
      handles.set(
        principal.name,
        authenticatedFirestore(testEnvironment, principal.uid, { platformRole: "superAdmin" }),
      );
    } else {
      handles.set(principal.name, authenticatedFirestore(testEnvironment, principal.uid));
    }
  }
});

after(async () => {
  if (testEnvironment) await testEnvironment.cleanup();
});

/**
 * The five operations, each as the narrowest request that reaches its rule.
 *
 * `create` and `delete` never touch the caller's seeded target: a create would
 * collide with it and a delete would remove the document the read cells still
 * need, so each acts on an id reserved for the attempt.
 */
function attempt(entry, principal, operation) {
  const database = handles.get(principal.name);
  const path = entry.self ? `tenants/${principal.tenant}` : targetPath(entry, principal);

  switch (operation) {
    case "get":
      return getDoc(doc(database, path));
    case "list":
      return getDocs(collection(database, collectionPath(entry, principal)));
    case "create":
      return setDoc(
        doc(database, `tenants/${principal.tenant}/${entry.segment}/created-${slug(principal)}`),
        entry.createPayload ? entry.createPayload(principal) : { probe: true },
      );
    case "update":
      return updateDoc(
        doc(database, path),
        entry.updatePayload ? entry.updatePayload(principal) : { probe: true },
      );
    case "delete":
      return deleteDoc(doc(database, sparePath(entry, principal)));
    default:
      throw new Error(`Unknown operation ${operation}`);
  }
}

for (const entry of COLLECTIONS) {
  for (const [operation, expectation] of Object.entries(entry.ops)) {
    const skipped = new Set(expectation.skip ?? []);
    const allowed = new Set(expectation.allow ?? []);

    for (const principal of PRINCIPALS) {
      if (skipped.has(principal.name)) continue;

      // The business document has no collection of its own to create into or
      // delete from; its `write: if false` is asserted through `update` alone.
      if (entry.self && (operation === "create" || operation === "delete")) continue;

      const shouldAllow = allowed.has(principal.name);
      const verdict = shouldAllow ? "may" : "may not";

      test(`${principal.name} ${verdict} ${operation} ${entry.name}`, async () => {
        const request = attempt(entry, principal, operation);
        if (shouldAllow) {
          await assertSucceeds(request);
        } else {
          await assertFails(request);
        }
      });
    }
  }
}
