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
} from "firebase/firestore";

import {
  activeTenantDocuments,
  authenticatedFirestore,
  createRulesTestEnvironment,
  seedDocuments,
} from "./support.js";

const PRODUCT_PATH = "tenants/tenant-a/products/product-1";
const LEDGER_PATH = `${PRODUCT_PATH}/stock_movements`;

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

/** The exact record `adjustStock` writes below the product. */
function adjustmentMovement(movementId = "sa_abc") {
  return {
    movementId,
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
    occurredAt: Timestamp.fromMillis(1785574800000),
    recordedAt: Timestamp.fromMillis(1785574800000),
    createdAt: Timestamp.fromMillis(1785574800000),
  };
}

/** The record nightly reconciliation writes for a confirmed sale. */
function saleMovement(movementId = "sale_co-1") {
  return {
    movementId,
    tenantId: "tenant-a",
    productId: "product-1",
    sourceType: "sale",
    sourceId: "co-1",
    quantityDelta: -2,
    lineCount: 1,
    occurredAt: Timestamp.fromMillis(1785574000000),
    recordedAt: Timestamp.fromMillis(1785574000000),
    createdAt: Timestamp.fromMillis(1785574000000),
  };
}

async function seedLedger() {
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
    [`${LEDGER_PATH}/sa_abc`]: adjustmentMovement(),
    [`${LEDGER_PATH}/sale_co-1`]: saleMovement(),
  });
}

test("management pages a product's stock ledger", async () => {
  await seedLedger();

  for (const uid of ["manager-a", "owner-a"]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    const snapshot = await assertSucceeds(
      getDoc(doc(firestore, `${LEDGER_PATH}/sa_abc`)),
    );
    if (snapshot.data().quantityAfter !== 7) {
      throw new Error(`Unexpected movement for ${uid}.`);
    }

    // The exact page the client issues: ascending document ID, no filter, one
    // more document than the page size. Movement IDs are digests and
    // `sale_{saleId}` values, so a descending page would be neither newest
    // first nor servable without a composite index.
    const page = await assertSucceeds(
      getDocs(
        query(
          collection(firestore, LEDGER_PATH),
          orderBy("__name__"),
          limit(21),
        ),
      ),
    );
    if (page.docs.map((entry) => entry.id).join(",") !== "sa_abc,sale_co-1") {
      throw new Error(`Unexpected ledger order for ${uid}.`);
    }
  }
});

test("a product with no movements still answers", async () => {
  await seedLedger();
  const firestore = authenticatedFirestore(testEnvironment, "manager-a");

  // A product that has never moved is the normal state for a new item, and an
  // absent movement discloses nothing, so both must answer rather than deny.
  const missing = await assertSucceeds(
    getDoc(doc(firestore, `${LEDGER_PATH}/sa_never`)),
  );
  if (missing.exists()) {
    throw new Error("An unwritten movement unexpectedly existed.");
  }
  const empty = await assertSucceeds(
    getDocs(
      query(
        collection(
          firestore,
          "tenants/tenant-a/products/product-9/stock_movements",
        ),
        orderBy("__name__"),
        limit(21),
      ),
    ),
  );
  if (!empty.empty) {
    throw new Error("An empty ledger unexpectedly returned documents.");
  }
});

test("a cashier reads the product but never its ledger", async () => {
  await seedLedger();
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");

  // The current quantity is operational information every member needs at the
  // till; the ledger names damage, waste, corrections, and who recorded them.
  await assertSucceeds(getDoc(doc(firestore, PRODUCT_PATH)));
  await assertFails(getDoc(doc(firestore, `${LEDGER_PATH}/sa_abc`)));
  await assertFails(getDoc(doc(firestore, `${LEDGER_PATH}/sa_never`)));
  await assertFails(
    getDocs(
      query(collection(firestore, LEDGER_PATH), orderBy("__name__"), limit(21)),
    ),
  );
});

test("no client may append, rewrite, or delete a movement", async () => {
  await seedLedger();

  for (const uid of ["owner-a", "manager-a", "cashier-a"]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    // A client that could append here could claim a movement that never
    // happened; every real entry is written inside the same transaction that
    // changes the quantity.
    await assertFails(
      setDoc(doc(firestore, `${LEDGER_PATH}/sa_forged`), adjustmentMovement()),
    );
    await assertFails(
      setDoc(doc(firestore, `${LEDGER_PATH}/sa_abc`), {
        ...adjustmentMovement(),
        quantityAfter: 99,
      }),
    );
    await assertFails(deleteDoc(doc(firestore, `${LEDGER_PATH}/sa_abc`)));
  }
});

test("the ledger of another business is never reached", async () => {
  await seedLedger();
  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({
      uid: "manager-b",
      tenantId: "tenant-b",
      role: "manager",
    }),
    "tenants/tenant-b/products/product-1/stock_movements/sa_abc": {
      ...adjustmentMovement(),
      tenantId: "tenant-b",
    },
  });

  const foreign = authenticatedFirestore(testEnvironment, "manager-b");
  await assertFails(getDoc(doc(foreign, `${LEDGER_PATH}/sa_abc`)));
  await assertFails(
    getDocs(
      query(collection(foreign, LEDGER_PATH), orderBy("__name__"), limit(21)),
    ),
  );
  // Its own business still answers, so the denial is the boundary and not a
  // broken rule.
  await assertSucceeds(
    getDoc(
      doc(foreign, "tenants/tenant-b/products/product-1/stock_movements/sa_abc"),
    ),
  );
});

test("a deactivated or non-member identity reads no ledger", async () => {
  await seedLedger();
  await seedDocuments(testEnvironment, {
    "users/outsider": {
      accountType: "tenant_user",
      globalStatus: "active",
      membershipCount: 0,
    },
  });

  const outsider = authenticatedFirestore(testEnvironment, "outsider");
  await assertFails(getDoc(doc(outsider, `${LEDGER_PATH}/sa_abc`)));

  await seedDocuments(testEnvironment, {
    "tenants/tenant-a/staff/manager-a": {
      uid: "manager-a",
      role: "manager",
      status: "inactive",
    },
  });
  const deactivated = authenticatedFirestore(testEnvironment, "manager-a");
  await assertFails(getDoc(doc(deactivated, `${LEDGER_PATH}/sa_abc`)));
});
