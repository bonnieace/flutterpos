import { after, afterEach, before, test } from "node:test";

import { assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import {
  Timestamp,
  collectionGroup,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  limit,
  orderBy,
  query,
  setDoc,
  startAfter,
  where,
} from "firebase/firestore";

import {
  activeTenantDocuments,
  authenticatedFirestore,
  createRulesTestEnvironment,
  seedDocuments,
} from "./support.js";

let testEnvironment;

before(async () => {
  testEnvironment = await createRulesTestEnvironment();
});

afterEach(async () => {
  if (testEnvironment) await testEnvironment.clearFirestore();
});

after(async () => {
  if (testEnvironment) await testEnvironment.cleanup();
});

function ledgerPath(tenantId, productId, movementId) {
  return `tenants/${tenantId}/products/${productId}/stock_movements/${movementId}`;
}

/** The exact record `adjustStock` writes below the product. */
function adjustmentMovement({
  tenantId = "tenant-a",
  productId = "product-1",
  movementId = "sa_abc",
} = {}) {
  return {
    movementId,
    tenantId,
    productId,
    sourceType: "manual_adjustment",
    adjustmentType: "damage",
    quantityDelta: -3,
    previousQuantity: 10,
    quantityAfter: 7,
    reason: "Broken in transit",
    actorUid: "manager-a",
    requestId: "adjust-stock-abcdefgh",
    occurredAt: Timestamp.fromMillis(1785574800000),
    recordedAt: Timestamp.fromMillis(1785574800000),
    createdAt: Timestamp.fromMillis(1785574800000),
  };
}

/** The record nightly reconciliation writes for a confirmed sale. */
function saleMovement({
  tenantId = "tenant-a",
  productId = "product-1",
  movementId = "sale_co-1",
} = {}) {
  return {
    movementId,
    tenantId,
    productId,
    sourceType: "sale",
    sourceId: "co-1",
    quantityDelta: -2,
    lineCount: 1,
    occurredAt: Timestamp.fromMillis(1785574000000),
    recordedAt: Timestamp.fromMillis(1785574000000),
    createdAt: Timestamp.fromMillis(1785574000000),
  };
}

/**
 * Two products in one business, each with a ledger, plus a second business
 * whose ledger the group query must never reach.
 */
async function seedBusinesses() {
  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({ uid: "cashier-a", role: "cashier" }),
    ...Object.fromEntries(
      [
        ["manager-a", "manager"],
        ["owner-a", "owner"],
      ].flatMap(([uid, role]) => [
        [
          `users/${uid}`,
          {
            accountType: "tenant_user",
            globalStatus: "active",
            membershipCount: 1,
          },
        ],
        [`tenants/tenant-a/staff/${uid}`, { uid, role, status: "active" }],
      ]),
    ),
    ...activeTenantDocuments({
      uid: "manager-b",
      tenantId: "tenant-b",
      role: "manager",
    }),
    [ledgerPath("tenant-a", "product-1", "sa_abc")]: adjustmentMovement(),
    [ledgerPath("tenant-a", "product-1", "sale_co-1")]: saleMovement(),
    [ledgerPath("tenant-a", "product-2", "sale_co-1")]: saleMovement({
      productId: "product-2",
    }),
    [ledgerPath("tenant-b", "product-1", "sa_abc")]: adjustmentMovement({
      tenantId: "tenant-b",
    }),
  });
}

/** The exact page the client issues: the tenant binding is never optional. */
function businessPage(firestore, tenantId, extra = []) {
  return query(
    collectionGroup(firestore, "stock_movements"),
    where("tenantId", "==", tenantId),
    ...extra,
    orderBy("__name__"),
    limit(21),
  );
}

test("management pages every product's ledger at once", async () => {
  await seedBusinesses();

  for (const uid of ["manager-a", "owner-a"]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    const page = await assertSucceeds(
      getDocs(businessPage(firestore, "tenant-a")),
    );
    // Ordered by whole resource path: product first, then record.
    const paths = page.docs.map((entry) => entry.ref.path).join(",");
    const expected = [
      ledgerPath("tenant-a", "product-1", "sa_abc"),
      ledgerPath("tenant-a", "product-1", "sale_co-1"),
      ledgerPath("tenant-a", "product-2", "sale_co-1"),
    ].join(",");
    if (paths !== expected) {
      throw new Error(`Unexpected group page for ${uid}: ${paths}`);
    }
  }
});

test("the page narrowed to one source is valid and permitted", async () => {
  await seedBusinesses();
  const firestore = authenticatedFirestore(testEnvironment, "manager-a");

  const page = await assertSucceeds(
    getDocs(
      businessPage(firestore, "tenant-a", [where("sourceType", "==", "sale")]),
    ),
  );
  const ids = page.docs.map((entry) => entry.ref.path).join(",");
  const expected = [
    ledgerPath("tenant-a", "product-1", "sale_co-1"),
    ledgerPath("tenant-a", "product-2", "sale_co-1"),
  ].join(",");
  if (ids !== expected) {
    throw new Error(`Unexpected narrowed group page: ${ids}`);
  }
});

test("the group page resumes from a whole document path", async () => {
  await seedBusinesses();
  const firestore = authenticatedFirestore(testEnvironment, "manager-a");

  const first = await assertSucceeds(
    getDocs(
      query(
        collectionGroup(firestore, "stock_movements"),
        where("tenantId", "==", "tenant-a"),
        orderBy("__name__"),
        limit(2),
      ),
    ),
  );
  if (first.docs.length !== 2) {
    throw new Error("Expected a bounded first page of two records.");
  }

  // A movement ID is unique only below its own product - `sale_co-1` exists
  // under both - so only a whole path can say where the next page resumes.
  // Firestore refuses a bare document ID here; it accepts one only for a page
  // whose collection path is already known.
  const rest = await assertSucceeds(
    getDocs(
      query(
        collectionGroup(firestore, "stock_movements"),
        where("tenantId", "==", "tenant-a"),
        orderBy("__name__"),
        startAfter(first.docs[1].ref.path),
        limit(2),
      ),
    ),
  );
  const paths = rest.docs.map((entry) => entry.ref.path).join(",");
  if (paths !== ledgerPath("tenant-a", "product-2", "sale_co-1")) {
    throw new Error(`Unexpected second group page: ${paths}`);
  }
});

test("an unfiltered group page is refused outright", async () => {
  await seedBusinesses();
  const firestore = authenticatedFirestore(testEnvironment, "manager-a");

  // The rule authorizes the page by `resource.data.tenantId`, which Firestore
  // can only resolve from an equality filter the query itself carries. Without
  // it the page would span every business in the database, so it is denied.
  await assertFails(
    getDocs(
      query(
        collectionGroup(firestore, "stock_movements"),
        orderBy("__name__"),
        limit(21),
      ),
    ),
  );
  await assertFails(
    getDocs(
      query(
        collectionGroup(firestore, "stock_movements"),
        where("sourceType", "==", "sale"),
        orderBy("__name__"),
        limit(21),
      ),
    ),
  );
});

test("a cashier never reaches the business-wide ledger", async () => {
  await seedBusinesses();
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");

  // The current quantity is operational information every member needs at the
  // till; what moved it, and who recorded the damage and waste, is not.
  await assertSucceeds(getDoc(doc(firestore, "tenants/tenant-a/products/product-1")));
  await assertFails(getDocs(businessPage(firestore, "tenant-a")));
  await assertFails(
    getDocs(
      businessPage(firestore, "tenant-a", [where("sourceType", "==", "sale")]),
    ),
  );
});

test("another business's ledger is never reached by a group page", async () => {
  await seedBusinesses();
  const foreign = authenticatedFirestore(testEnvironment, "manager-b");

  await assertFails(getDocs(businessPage(foreign, "tenant-a")));
  // Its own business still answers, so the denial is the boundary and not a
  // broken rule.
  const own = await assertSucceeds(getDocs(businessPage(foreign, "tenant-b")));
  const paths = own.docs.map((entry) => entry.ref.path).join(",");
  if (paths !== ledgerPath("tenant-b", "product-1", "sa_abc")) {
    throw new Error(`Unexpected own-business group page: ${paths}`);
  }
});

test("the group rule authorizes queries only, never a document", async () => {
  await seedBusinesses();
  const firestore = authenticatedFirestore(testEnvironment, "manager-a");

  // The per-product rule still answers a single record and an absent one,
  // which the group rule must not have disturbed: it compares a document field
  // and would raise an evaluation error on a document that does not exist.
  await assertSucceeds(
    getDoc(doc(firestore, ledgerPath("tenant-a", "product-1", "sa_abc"))),
  );
  const missing = await assertSucceeds(
    getDoc(doc(firestore, ledgerPath("tenant-a", "product-9", "sa_never"))),
  );
  if (missing.exists()) {
    throw new Error("An unwritten movement unexpectedly existed.");
  }

  // Writing stays server-only: a client that could append here could claim a
  // movement that never happened.
  for (const uid of ["owner-a", "manager-a", "cashier-a"]) {
    const client = authenticatedFirestore(testEnvironment, uid);
    await assertFails(
      setDoc(
        doc(client, ledgerPath("tenant-a", "product-1", "sa_forged")),
        adjustmentMovement({ movementId: "sa_forged" }),
      ),
    );
    await assertFails(
      deleteDoc(doc(client, ledgerPath("tenant-a", "product-1", "sa_abc"))),
    );
  }
});

test("a deactivated or non-member identity pages nothing", async () => {
  await seedBusinesses();
  await seedDocuments(testEnvironment, {
    "users/outsider": {
      accountType: "tenant_user",
      globalStatus: "active",
      membershipCount: 0,
    },
  });

  const outsider = authenticatedFirestore(testEnvironment, "outsider");
  await assertFails(getDocs(businessPage(outsider, "tenant-a")));

  await seedDocuments(testEnvironment, {
    "tenants/tenant-a/staff/manager-a": {
      uid: "manager-a",
      role: "manager",
      status: "inactive",
    },
  });
  const deactivated = authenticatedFirestore(testEnvironment, "manager-a");
  await assertFails(getDocs(businessPage(deactivated, "tenant-a")));
});
