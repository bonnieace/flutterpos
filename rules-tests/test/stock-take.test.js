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
  updateDoc,
  where,
} from "firebase/firestore";

import {
  activeTenantDocuments,
  authenticatedFirestore,
  createRulesTestEnvironment,
  seedDocuments,
} from "./support.js";

/**
 * Who may see a stock take, and who may write one.
 *
 * **Nobody may write one.** `submitStockTake` is the only thing that writes here,
 * for the reason `stock_adjustments` is server-only: a count is read against the
 * stock it will later correct, so a client that could write one could write the
 * shortage it caused out of existence.
 *
 * **A cashier reads their own count and not the lines under it**, and that pair
 * is the whole point of the split. The take says they counted; the lines carry
 * `expected`, which is the figure the count was deliberately taken blind to.
 */

const TAKES_PATH = "tenants/tenant-a/stock_takes";
const OWN_TAKE = `${TAKES_PATH}/st_own`;
const FOREIGN_TAKE = `${TAKES_PATH}/st_foreign`;

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

/** The header `submitStockTake` merges onto a take. */
function take(overrides = {}) {
  return {
    tenantId: "tenant-a",
    counterUid: "cashier-a",
    businessDate: "2026-09-13",
    scope: { kind: "all" },
    productsInScope: 40,
    status: "submitted",
    countedLineCount: 2,
    varianceLineCount: 1,
    absoluteVarianceUnits: 2,
    unmatchedLineCount: 0,
    createdAt: Timestamp.fromMillis(1789000000000),
    submittedAt: Timestamp.fromMillis(1789000600000),
    ...overrides,
  };
}

/** One counted line, as the server records it. */
function line(overrides = {}) {
  return {
    tenantId: "tenant-a",
    takeId: "st_own",
    productId: "product-1",
    counted: 10,
    seenQuantity: 12,
    countedAt: "2026-09-13T07:30:00.000Z",
    expected: 12,
    variance: -2,
    matched: true,
    counterUid: "cashier-a",
    page: 0,
    recordedAt: Timestamp.fromMillis(1789000600000),
    ...overrides,
  };
}

async function seedTakes() {
  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({ uid: "cashier-a", role: "cashier" }),
    ...Object.fromEntries(
      [
        ["cashier-b", "cashier"],
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
    [OWN_TAKE]: take(),
    [`${OWN_TAKE}/lines/product-1`]: line(),
    [`${OWN_TAKE}/lines/product-2`]: line({
      productId: "product-2",
      counted: 4,
      seenQuantity: 4,
      expected: 4,
      variance: 0,
    }),
    [FOREIGN_TAKE]: take({ counterUid: "cashier-b" }),
    [`${FOREIGN_TAKE}/lines/product-1`]: line({ takeId: "st_foreign", counterUid: "cashier-b" }),
  });
}

/** The page management's review list issues. */
function takePage(firestore) {
  return query(collection(firestore, TAKES_PATH), orderBy("__name__"), limit(21));
}

test("management reads every count and the lines under it", async () => {
  await seedTakes();

  for (const uid of ["manager-a", "owner-a"]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    const snapshot = await assertSucceeds(getDoc(doc(firestore, OWN_TAKE)));
    if (snapshot.data().varianceLineCount !== 1) {
      throw new Error(`Unexpected take summary for ${uid}.`);
    }

    const page = await assertSucceeds(getDocs(takePage(firestore)));
    if (page.size !== 2) {
      throw new Error(`Expected both counts for ${uid}, saw ${page.size}.`);
    }

    // The lines are what a review is: the variance per product.
    const lines = await assertSucceeds(
      getDocs(collection(firestore, `${OWN_TAKE}/lines`)),
    );
    if (lines.size !== 2) {
      throw new Error(`Expected both lines for ${uid}, saw ${lines.size}.`);
    }
  }
});

test("a cashier reads the count they took, and no colleague's", async () => {
  await seedTakes();
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");

  await assertSucceeds(getDoc(doc(firestore, OWN_TAKE)));
  await assertFails(getDoc(doc(firestore, FOREIGN_TAKE)));

  // An unfiltered page spans both, so it must fail outright rather than quietly
  // return the half this cashier is allowed - the same shape the shift history
  // rules take.
  await assertFails(getDocs(takePage(firestore)));

  const own = await assertSucceeds(
    getDocs(
      query(
        collection(firestore, TAKES_PATH),
        where("counterUid", "==", "cashier-a"),
        orderBy("__name__"),
        limit(21),
      ),
    ),
  );
  if (own.size !== 1) {
    throw new Error(`Expected only this cashier's count, saw ${own.size}.`);
  }
});

test("the counter cannot read back the figure they were counting blind to", async () => {
  // **This is the control, not an oversight.** A line carries `expected`.
  // Handing it to the person who counted would give them the number the count
  // deliberately withheld, which is most of what a blind count is for.
  await seedTakes();
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");

  await assertFails(getDoc(doc(firestore, `${OWN_TAKE}/lines/product-1`)));
  await assertFails(getDocs(collection(firestore, `${OWN_TAKE}/lines`)));
});

test("no client writes a count, at any role", async () => {
  await seedTakes();

  for (const uid of ["cashier-a", "manager-a", "owner-a"]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);

    await assertFails(setDoc(doc(firestore, `${TAKES_PATH}/st_new`), take()));
    await assertFails(updateDoc(doc(firestore, OWN_TAKE), { countedLineCount: 99 }));
    await assertFails(deleteDoc(doc(firestore, OWN_TAKE)));

    await assertFails(
      setDoc(doc(firestore, `${OWN_TAKE}/lines/product-9`), line({ productId: "product-9" })),
    );
    await assertFails(
      updateDoc(doc(firestore, `${OWN_TAKE}/lines/product-1`), { counted: 999 }),
    );
    await assertFails(deleteDoc(doc(firestore, `${OWN_TAKE}/lines/product-1`)));
  }
});

test("a signed-out device reaches nothing", async () => {
  await seedTakes();
  const firestore = testEnvironment.unauthenticatedContext().firestore();

  await assertFails(getDoc(doc(firestore, OWN_TAKE)));
  await assertFails(getDocs(collection(firestore, `${OWN_TAKE}/lines`)));
  await assertFails(setDoc(doc(firestore, `${TAKES_PATH}/st_new`), take()));
});

test("a member of another business reaches nothing here", async () => {
  await seedTakes();
  await seedDocuments(testEnvironment, {
    "users/owner-b": {
      accountType: "tenant_user",
      globalStatus: "active",
      membershipCount: 1,
    },
    "tenants/tenant-b": {
      status: "active",
      ownerUid: "owner-b",
    },
    "tenants/tenant-b/staff/owner-b": {
      uid: "owner-b",
      role: "owner",
      status: "active",
    },
  });
  const firestore = authenticatedFirestore(testEnvironment, "owner-b");

  await assertFails(getDoc(doc(firestore, OWN_TAKE)));
  await assertFails(getDocs(takePage(firestore)));
  await assertFails(getDocs(collection(firestore, `${OWN_TAKE}/lines`)));
});
