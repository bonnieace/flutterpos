import { after, afterEach, before, test } from "node:test";

import { assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import {
  Timestamp,
  doc,
  getDoc,
  getDocs,
  collection,
  setDoc,
} from "firebase/firestore";

import {
  activeTenantDocuments,
  authenticatedFirestore,
  createRulesTestEnvironment,
  seedDocuments,
} from "./support.js";

/**
 * The provisional trading window a self-serve request opens.
 *
 * Three states, and the difference between them is the whole subject:
 *
 * - **pending, window open** - trades exactly like an approved business.
 * - **pending, window shut** - reads its own records, writes nothing.
 * - **rejected** - dark, because a rejection is a decision rather than a
 *   deadline that was missed.
 */

const HOUR_MILLISECONDS = 60 * 60 * 1000;

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

function openWindow() {
  return Timestamp.fromMillis(Date.now() + HOUR_MILLISECONDS);
}

function shutWindow() {
  return Timestamp.fromMillis(Date.now() - HOUR_MILLISECONDS);
}

/** Seeds one manager plus a category to read and a category path to write. */
async function seedTenant({ tenantStatus, provisionalUntil }) {
  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({
      uid: "manager-a",
      role: "manager",
      tenantStatus,
      provisionalUntil,
    }),
    "tenants/tenant-a/categories/category-a": {
      tenantId: "tenant-a",
      name: "Drinks",
    },
  });
  return authenticatedFirestore(testEnvironment, "manager-a");
}

test("a request inside its window trades like an approved business", async () => {
  const firestore = await seedTenant({
    tenantStatus: "pending",
    provisionalUntil: openWindow(),
  });

  await assertSucceeds(
    getDoc(doc(firestore, "tenants/tenant-a/categories/category-a")),
  );
  await assertSucceeds(
    setDoc(doc(firestore, "tenants/tenant-a/categories/category-b"), {
      tenantId: "tenant-a",
      name: "Snacks",
    }),
  );
});

test("a request whose window has shut reads its own records", async () => {
  // The read-only tail. A provisional week is real trading - real cash counted
  // at close, receipts customers are holding - and taking the records away at
  // the stroke of the deadline would leave nobody able to reconcile against
  // paper the shop printed itself.
  const firestore = await seedTenant({
    tenantStatus: "pending",
    provisionalUntil: shutWindow(),
  });

  await assertSucceeds(
    getDoc(doc(firestore, "tenants/tenant-a/categories/category-a")),
  );
  await assertSucceeds(
    getDocs(collection(firestore, "tenants/tenant-a/categories")),
  );
  // The tenant document itself, which is where the app reads `provisionalUntil`
  // to tell the shopkeeper which state they are in.
  await assertSucceeds(getDoc(doc(firestore, "tenants/tenant-a")));
});

test("a request whose window has shut writes nothing", async () => {
  const firestore = await seedTenant({
    tenantStatus: "pending",
    provisionalUntil: shutWindow(),
  });

  await assertFails(
    setDoc(doc(firestore, "tenants/tenant-a/categories/category-b"), {
      tenantId: "tenant-a",
      name: "Snacks",
    }),
  );
});

test("a lapsed request cannot record a sale", async () => {
  // The write that matters most: trading is exactly what the deadline stops.
  const firestore = await seedTenant({
    tenantStatus: "pending",
    provisionalUntil: shutWindow(),
  });

  await assertFails(
    setDoc(doc(firestore, "tenants/tenant-a/sales/checkout-a"), {
      tenantId: "tenant-a",
      checkoutId: "checkout-a",
      soldById: "manager-a",
      payloadHash: "a".repeat(64),
      items: [{ productId: "product-a", quantity: 1 }],
    }),
  );
});

test("a pending tenant with no window may read but never write", async () => {
  // Every tenant requested before the field existed, and every tenant seeded by
  // hand. `provisionalUntil is timestamp` is what makes an absent field read as
  // lapsed rather than as a window that never closes.
  const firestore = await seedTenant({ tenantStatus: "pending" });

  await assertSucceeds(
    getDoc(doc(firestore, "tenants/tenant-a/categories/category-a")),
  );
  await assertFails(
    setDoc(doc(firestore, "tenants/tenant-a/categories/category-b"), {
      tenantId: "tenant-a",
      name: "Snacks",
    }),
  );
});

test("a rejected business is dark, window or no window", async () => {
  // `setTenantLifecycle` moves pending -> rejected without clearing the field,
  // so a stale open window must not survive the rejection.
  for (const provisionalUntil of [openWindow(), shutWindow(), undefined]) {
    await testEnvironment.clearFirestore();
    const firestore = await seedTenant({
      tenantStatus: "rejected",
      provisionalUntil,
    });

    await assertFails(
      getDoc(doc(firestore, "tenants/tenant-a/categories/category-a")),
    );
    await assertFails(
      setDoc(doc(firestore, "tenants/tenant-a/categories/category-b"), {
        tenantId: "tenant-a",
        name: "Snacks",
      }),
    );
  }
});

test("suspension and archival keep going dark, unchanged", async () => {
  // The statuses that already locked a trading business out. Widening `pending`
  // must not have widened these with it.
  for (const tenantStatus of ["suspended", "archived"]) {
    await testEnvironment.clearFirestore();
    const firestore = await seedTenant({
      tenantStatus,
      provisionalUntil: openWindow(),
    });

    await assertFails(
      getDoc(doc(firestore, "tenants/tenant-a/categories/category-a")),
    );
    await assertFails(
      setDoc(doc(firestore, "tenants/tenant-a/categories/category-b"), {
        tenantId: "tenant-a",
        name: "Snacks",
      }),
    );
  }
});

test("an approved business is unaffected by a stale window", async () => {
  // Approval replaces the question rather than answering it: `status` is
  // checked first, so a leftover `provisionalUntil` decides nothing.
  const firestore = await seedTenant({
    tenantStatus: "active",
    provisionalUntil: shutWindow(),
  });

  await assertSucceeds(
    getDoc(doc(firestore, "tenants/tenant-a/categories/category-a")),
  );
  await assertSucceeds(
    setDoc(doc(firestore, "tenants/tenant-a/categories/category-b"), {
      tenantId: "tenant-a",
      name: "Snacks",
    }),
  );
});

test("a provisional window grants nothing to a stranger", async () => {
  // The window widens which tenant statuses a *member* may act on. It must not
  // touch membership itself.
  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({
      uid: "manager-a",
      role: "manager",
      tenantStatus: "pending",
      provisionalUntil: openWindow(),
    }),
    "users/outsider": {
      accountType: "tenant_user",
      globalStatus: "active",
      membershipCount: 0,
    },
    "tenants/tenant-a/categories/category-a": {
      tenantId: "tenant-a",
      name: "Drinks",
    },
  });
  const firestore = authenticatedFirestore(testEnvironment, "outsider");

  await assertFails(
    getDoc(doc(firestore, "tenants/tenant-a/categories/category-a")),
  );
  await assertFails(
    setDoc(doc(firestore, "tenants/tenant-a/categories/category-b"), {
      tenantId: "tenant-a",
      name: "Snacks",
    }),
  );
});

test("a deactivated member gains nothing from an open window", async () => {
  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({
      uid: "manager-a",
      role: "manager",
      tenantStatus: "pending",
      staffStatus: "inactive",
      provisionalUntil: openWindow(),
    }),
    "tenants/tenant-a/categories/category-a": {
      tenantId: "tenant-a",
      name: "Drinks",
    },
  });
  const firestore = authenticatedFirestore(testEnvironment, "manager-a");

  await assertFails(
    getDoc(doc(firestore, "tenants/tenant-a/categories/category-a")),
  );
});
