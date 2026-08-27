import { after, afterEach, before, test } from "node:test";

import { assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import {
  Timestamp,
  deleteDoc,
  doc,
  getDoc,
  serverTimestamp,
  setDoc,
  updateDoc,
} from "firebase/firestore";

import {
  activeTenantDocuments,
  authenticatedFirestore,
  createRulesTestEnvironment,
  seedDocuments,
} from "./support.js";

const BUSINESS_DATE = "2026-08-27";
const EXPENSE_ID = `${BUSINESS_DATE}-Ab3xK9pQ`;

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

/** Every field the create rule allows, and no other. */
function expense(overrides = {}) {
  return {
    expenseId: EXPENSE_ID,
    tenantId: "tenant-a",
    businessDate: BUSINESS_DATE,
    category: "rent",
    description: "August rent for the shop",
    amountMinor: 30000,
    amount: 300,
    recordedBy: "user-a",
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

/** The same record as stored state, with a resolved timestamp. */
function storedExpense(overrides = {}) {
  return {
    ...expense(),
    createdAt: Timestamp.fromDate(new Date("2026-08-27T09:00:00Z")),
    ...overrides,
  };
}

function expensePath(expenseId = EXPENSE_ID) {
  return `tenants/tenant-a/expenses/${expenseId}`;
}

async function asRole(role, uid = "user-a") {
  await seedDocuments(testEnvironment, activeTenantDocuments({ uid, role }));
  return authenticatedFirestore(testEnvironment, uid);
}

// ---------------------------------------------------------------- create ----

test("an owner records an expense", async () => {
  const db = await asRole("owner");
  await assertSucceeds(setDoc(doc(db, expensePath()), expense()));
});

test("an administrator records an expense", async () => {
  const db = await asRole("admin");
  await assertSucceeds(setDoc(doc(db, expensePath()), expense()));
});

test("a manager cannot record an expense", async () => {
  // An expense is cost, and cost sits behind owner and administrator
  // everywhere else in this system. A manager is never shown the margin, so a
  // manager does not write into it either.
  const db = await asRole("manager");
  await assertFails(setDoc(doc(db, expensePath()), expense()));
});

test("a cashier cannot record an expense", async () => {
  const db = await asRole("cashier");
  await assertFails(setDoc(doc(db, expensePath()), expense()));
});

test("a manager cannot read an expense", async () => {
  await seedDocuments(testEnvironment, {
    [expensePath()]: storedExpense(),
  });
  const db = await asRole("manager");
  await assertFails(getDoc(doc(db, expensePath())));
});

test("an owner reads an expense", async () => {
  await seedDocuments(testEnvironment, {
    [expensePath()]: storedExpense(),
  });
  const db = await asRole("owner");
  await assertSucceeds(getDoc(doc(db, expensePath())));
});

// --------------------------------------------------------- the key rule ----

test("the key must begin with the business date it records", async () => {
  // **The convention the whole range read rests on.** A client repository
  // orders only by document ID, so the date has to lead the key; a record
  // whose key disagreed with its own field would be counted into a period it
  // does not belong to.
  const db = await asRole("owner");
  await assertFails(
    setDoc(doc(db, expensePath("2026-08-26-Ab3xK9pQ")), expense({
      expenseId: "2026-08-26-Ab3xK9pQ",
    })),
  );
});

test("a key with no date at all is refused", async () => {
  const db = await asRole("owner");
  await assertFails(
    setDoc(doc(db, expensePath("expense-1")), expense({
      expenseId: "expense-1",
    })),
  );
});

test("a business date that is not a date is refused", async () => {
  // It is checked against its own pattern before it is spliced into the key
  // pattern, so it cannot smuggle a wildcard into that one.
  const db = await asRole("owner");
  await assertFails(
    setDoc(doc(db, expensePath(".*-Ab3xK9pQ")), expense({
      expenseId: ".*-Ab3xK9pQ",
      businessDate: ".*",
    })),
  );
});

test("the document must echo its own id", async () => {
  const db = await asRole("owner");
  await assertFails(
    setDoc(doc(db, expensePath()), expense({ expenseId: "something-else" })),
  );
});

test("a record cannot be filed under another business", async () => {
  const db = await asRole("owner");
  await assertFails(
    setDoc(doc(db, expensePath()), expense({ tenantId: "tenant-b" })),
  );
});

test("the author is pinned to the signed-in member", async () => {
  const db = await asRole("owner");
  await assertFails(
    setDoc(doc(db, expensePath()), expense({ recordedBy: "user-b" })),
  );
});

// ------------------------------------------------------------- the data ----

test("a client clock cannot decide when money left", async () => {
  const db = await asRole("owner");
  await assertFails(
    setDoc(
      doc(db, expensePath()),
      expense({
        createdAt: Timestamp.fromDate(new Date("2020-01-01T00:00:00Z")),
      }),
    ),
  );
});

test("a category this system does not model is refused", async () => {
  const db = await asRole("owner");
  await assertFails(
    setDoc(doc(db, expensePath()), expense({ category: "kickbacks" })),
  );
});

test("an expense of nothing is refused", async () => {
  const db = await asRole("owner");
  await assertFails(
    setDoc(doc(db, expensePath()), expense({ amountMinor: 0, amount: 0 })),
  );
});

test("a negative expense is refused", async () => {
  const db = await asRole("owner");
  await assertFails(
    setDoc(doc(db, expensePath()), expense({ amountMinor: -1, amount: -0.01 })),
  );
});

test("a description too short to mean anything is refused", async () => {
  const db = await asRole("owner");
  await assertFails(
    setDoc(doc(db, expensePath()), expense({ description: "x" })),
  );
});

test("a key the document does not declare is refused", async () => {
  const db = await asRole("owner");
  await assertFails(
    setDoc(doc(db, expensePath()), expense({ voidedAt: serverTimestamp() })),
  );
});

// ----------------------------------------------------------- the void ------

test("an owner voids a record", async () => {
  await seedDocuments(testEnvironment, {
    [expensePath()]: storedExpense(),
  });
  const db = await asRole("owner");
  await assertSucceeds(
    updateDoc(doc(db, expensePath()), {
      voidedAt: serverTimestamp(),
      voidedBy: "user-a",
      voidReason: "Recorded twice by mistake",
    }),
  );
});

test("a void cannot change the amount it withdraws", async () => {
  // The whole point of a void rather than an edit: the original stands.
  await seedDocuments(testEnvironment, {
    [expensePath()]: storedExpense(),
  });
  const db = await asRole("owner");
  await assertFails(
    updateDoc(doc(db, expensePath()), {
      voidedAt: serverTimestamp(),
      voidedBy: "user-a",
      voidReason: "Recorded twice by mistake",
      amountMinor: 1,
    }),
  );
});

test("an already voided record cannot be voided again", async () => {
  await seedDocuments(testEnvironment, {
    [expensePath()]: storedExpense({
      voidedAt: Timestamp.fromDate(new Date("2026-08-27T10:00:00Z")),
      voidedBy: "user-a",
      voidReason: "Recorded twice by mistake",
    }),
  });
  const db = await asRole("owner");
  await assertFails(
    updateDoc(doc(db, expensePath()), {
      voidedAt: serverTimestamp(),
      voidedBy: "user-a",
      voidReason: "Actually it was fine",
    }),
  );
});

test("a manager cannot void a record", async () => {
  await seedDocuments(testEnvironment, {
    [expensePath()]: storedExpense(),
  });
  const db = await asRole("manager");
  await assertFails(
    updateDoc(doc(db, expensePath()), {
      voidedAt: serverTimestamp(),
      voidedBy: "user-a",
      voidReason: "Recorded twice by mistake",
    }),
  );
});

test("an ordinary edit is refused", async () => {
  await seedDocuments(testEnvironment, {
    [expensePath()]: storedExpense(),
  });
  const db = await asRole("owner");
  await assertFails(
    updateDoc(doc(db, expensePath()), { description: "Something else" }),
  );
});

// ----------------------------------------------------------- the delete ----

test("nobody deletes an expense", async () => {
  await seedDocuments(testEnvironment, {
    [expensePath()]: storedExpense(),
  });
  const db = await asRole("owner");
  await assertFails(deleteDoc(doc(db, expensePath())));
});
