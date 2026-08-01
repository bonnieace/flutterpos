import { after, afterEach, before, test } from "node:test";

import { assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import {
  Timestamp,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  limit,
  orderBy,
  query,
  setDoc,
  where,
} from "firebase/firestore";

import {
  activeTenantDocuments,
  authenticatedFirestore,
  createRulesTestEnvironment,
  seedDocuments,
} from "./support.js";

const FEED_PATH = "tenants/tenant-a/stock_adjustments";
const PRODUCT_PATH = "tenants/tenant-a/products/product-1";

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

/** The exact immutable record `adjustStock` writes for the business. */
function adjustment(overrides = {}) {
  return {
    tenantId: "tenant-a",
    productId: "product-1",
    sourceType: "manual_adjustment",
    adjustmentType: "damage",
    quantityDelta: -3,
    previousQuantity: 10,
    quantityAfter: 7,
    reason: "Broken in transit",
    actorUid: "manager-a",
    requestId: "adjust-stock-abcdefgh",
    createdAt: Timestamp.fromMillis(1785574800000),
    ...overrides,
  };
}

async function seedAdjustments() {
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
    [PRODUCT_PATH]: {
      name: "Cold lager",
      SKU: "LAGER-001",
      price: 120.5,
      quantity: 7,
      categoryId: "drinks",
    },
    [`${FEED_PATH}/sa_abc`]: adjustment(),
    [`${FEED_PATH}/sa_def`]: adjustment({
      productId: "product-9",
      adjustmentType: "restock",
      quantityDelta: 6,
      previousQuantity: 4,
      quantityAfter: 10,
      reason: "Delivery received",
      actorUid: "owner-a",
    }),
  });
}

/** The exact business-wide page the client issues. */
function feedPage(firestore, path = FEED_PATH) {
  return query(collection(firestore, path), orderBy("__name__"), limit(21));
}

/** The exact product-narrowed page the client issues. */
function productPage(firestore, productId, path = FEED_PATH) {
  return query(
    collection(firestore, path),
    where("productId", "==", productId),
    orderBy("__name__"),
    limit(21),
  );
}

test("management pages the business-wide adjustment record", async () => {
  await seedAdjustments();

  for (const uid of ["manager-a", "owner-a"]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    const snapshot = await assertSucceeds(
      getDoc(doc(firestore, `${FEED_PATH}/sa_abc`)),
    );
    if (snapshot.data().quantityAfter !== 7) {
      throw new Error(`Unexpected adjustment for ${uid}.`);
    }

    // Ascending document ID with no filter, one more document than the page
    // size. An adjustment ID is `sa_` plus a digest, so document order carries
    // no time information and a descending page would be neither newest first
    // nor servable without a composite index.
    const page = await assertSucceeds(getDocs(feedPage(firestore)));
    if (page.docs.map((entry) => entry.id).join(",") !== "sa_abc,sa_def") {
      throw new Error(`Unexpected feed order for ${uid}.`);
    }

    // The same order narrowed by one equality filter, which Firestore's
    // automatic single-field index serves without a composite index. If that
    // ever stops being true the emulator rejects the query here rather than the
    // client failing in production.
    const narrowed = await assertSucceeds(
      getDocs(productPage(firestore, "product-1")),
    );
    if (narrowed.docs.map((entry) => entry.id).join(",") !== "sa_abc") {
      throw new Error(`Unexpected product page for ${uid}.`);
    }
  }
});

test("a business that has never corrected stock still answers", async () => {
  await seedAdjustments();
  const firestore = authenticatedFirestore(testEnvironment, "manager-a");

  // An unwritten adjustment discloses nothing, and a product that was never
  // corrected is the normal state, so both must answer rather than deny.
  const missing = await assertSucceeds(
    getDoc(doc(firestore, `${FEED_PATH}/sa_never`)),
  );
  if (missing.exists()) {
    throw new Error("An unwritten adjustment unexpectedly existed.");
  }
  const emptyProduct = await assertSucceeds(
    getDocs(productPage(firestore, "product-404")),
  );
  if (!emptyProduct.empty) {
    throw new Error("An uncorrected product unexpectedly returned records.");
  }

  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({
      uid: "manager-c",
      tenantId: "tenant-c",
      role: "manager",
    }),
  });
  const fresh = authenticatedFirestore(testEnvironment, "manager-c");
  const emptyFeed = await assertSucceeds(
    getDocs(feedPage(fresh, "tenants/tenant-c/stock_adjustments")),
  );
  if (!emptyFeed.empty) {
    throw new Error("An empty feed unexpectedly returned documents.");
  }
});

test("a cashier reads the product but never its corrections", async () => {
  await seedAdjustments();
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");

  // The current quantity is operational information every member needs at the
  // till; the record of who corrected it, why, and by how much is management
  // information in exactly the way the per-product ledger is.
  await assertSucceeds(getDoc(doc(firestore, PRODUCT_PATH)));
  await assertFails(getDoc(doc(firestore, `${FEED_PATH}/sa_abc`)));
  await assertFails(getDoc(doc(firestore, `${FEED_PATH}/sa_never`)));
  await assertFails(getDocs(feedPage(firestore)));
  await assertFails(getDocs(productPage(firestore, "product-1")));
});

test("no client may record, rewrite, or delete an adjustment", async () => {
  await seedAdjustments();

  for (const uid of ["owner-a", "manager-a", "cashier-a"]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    // A client that could create here could claim a correction that never
    // moved any stock; one that could update or delete could erase the only
    // record of one that did. Every real record is written by `adjustStock`
    // inside the transaction that changes the quantity.
    await assertFails(
      setDoc(doc(firestore, `${FEED_PATH}/sa_forged`), adjustment()),
    );
    await assertFails(
      setDoc(
        doc(firestore, `${FEED_PATH}/sa_abc`),
        adjustment({ quantityAfter: 99 }),
      ),
    );
    await assertFails(deleteDoc(doc(firestore, `${FEED_PATH}/sa_abc`)));
  }
});

test("another business's adjustment record is never reached", async () => {
  await seedAdjustments();
  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({
      uid: "manager-b",
      tenantId: "tenant-b",
      role: "manager",
    }),
    "tenants/tenant-b/stock_adjustments/sa_abc": adjustment({
      tenantId: "tenant-b",
    }),
  });

  const foreign = authenticatedFirestore(testEnvironment, "manager-b");
  await assertFails(getDoc(doc(foreign, `${FEED_PATH}/sa_abc`)));
  await assertFails(getDocs(feedPage(foreign)));
  await assertFails(getDocs(productPage(foreign, "product-1")));
  // Its own business still answers, so the denial is the boundary and not a
  // broken rule.
  await assertSucceeds(
    getDoc(doc(foreign, "tenants/tenant-b/stock_adjustments/sa_abc")),
  );
  await assertSucceeds(
    getDocs(feedPage(foreign, "tenants/tenant-b/stock_adjustments")),
  );
});

test("a deactivated or non-member identity reads no corrections", async () => {
  await seedAdjustments();
  await seedDocuments(testEnvironment, {
    "users/outsider": {
      accountType: "tenant_user",
      globalStatus: "active",
      membershipCount: 0,
    },
  });

  const outsider = authenticatedFirestore(testEnvironment, "outsider");
  await assertFails(getDoc(doc(outsider, `${FEED_PATH}/sa_abc`)));
  await assertFails(getDocs(feedPage(outsider)));

  await seedDocuments(testEnvironment, {
    "tenants/tenant-a/staff/manager-a": {
      uid: "manager-a",
      role: "manager",
      status: "inactive",
    },
  });
  const deactivated = authenticatedFirestore(testEnvironment, "manager-a");
  await assertFails(getDoc(doc(deactivated, `${FEED_PATH}/sa_abc`)));
  await assertFails(getDocs(feedPage(deactivated)));
});
