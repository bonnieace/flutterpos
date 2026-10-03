import { after, afterEach, before, test } from "node:test";

import { assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import {
  Timestamp,
  deleteDoc,
  doc,
  getDoc,
  setDoc,
  updateDoc,
} from "firebase/firestore";

import {
  activeTenantDocuments,
  authenticatedFirestore,
  createRulesTestEnvironment,
  seedDocuments,
} from "./support.js";

const ROOT = "tenants/tenant-a";
const CUSTOMER = `${ROOT}/customers/cu_jane`;

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

async function asRole(role, uid = `${role}-a`, tenantId = "tenant-a") {
  await seedDocuments(testEnvironment, activeTenantDocuments({ uid, role, tenantId }));
  return authenticatedFirestore(testEnvironment, uid);
}

async function seedRecords() {
  await seedDocuments(testEnvironment, {
    [CUSTOMER]: {
      name: "Jane Wanjiku",
      phone: "+254712345678",
      active: true,
      points: 12,
    },
    [`${CUSTOMER}/activity/sale-a`]: {
      kind: "sale",
      saleId: "sale-a",
      points: 12,
      createdAt: Timestamp.fromMillis(1785574800000),
    },
    [`${ROOT}/receipt_deliveries/rd_one`]: {
      saleId: "sale-a",
      status: "sent",
      phoneMasked: "+25•••678",
    },
    [`${ROOT}/email_receipt_deliveries/ed_one`]: {
      saleId: "sale-a",
      status: "delivered",
      emailMasked: "j•••@example.com",
    },
  });
}

// **Every member reads customers**, because the till is where one is chosen and
// a cashier is who chooses.
test("every active role reads customers", async () => {
  await seedRecords();
  for (const role of ["owner", "admin", "manager", "cashier"]) {
    const db = await asRole(role);
    await assertSucceeds(getDoc(doc(db, CUSTOMER)));
  }
});

// Writing is the callables' alone: one number per customer is a statement about
// every other customer, and the points on one are the server's to award.
test("no role writes a customer directly", async () => {
  await seedRecords();
  for (const role of ["owner", "admin", "manager", "cashier"]) {
    const db = await asRole(role);
    await assertFails(setDoc(doc(db, `${ROOT}/customers/cu_new`), {
      name: "New",
      active: true,
    }));
    await assertFails(updateDoc(doc(db, CUSTOMER), { points: 1000 }));
    await assertFails(deleteDoc(doc(db, CUSTOMER)));
  }
});

test("the points ledger and receipt deliveries are management's to read", async () => {
  await seedRecords();
  for (const role of ["owner", "admin", "manager"]) {
    const db = await asRole(role);
    await assertSucceeds(getDoc(doc(db, `${CUSTOMER}/activity/sale-a`)));
    await assertSucceeds(getDoc(doc(db, `${ROOT}/receipt_deliveries/rd_one`)));
    await assertSucceeds(getDoc(doc(db, `${ROOT}/email_receipt_deliveries/ed_one`)));
  }
  const cashier = await asRole("cashier");
  await assertFails(getDoc(doc(cashier, `${CUSTOMER}/activity/sale-a`)));
  await assertFails(getDoc(doc(cashier, `${ROOT}/receipt_deliveries/rd_one`)));
  await assertFails(getDoc(doc(cashier, `${ROOT}/email_receipt_deliveries/ed_one`)));
});

test("nobody writes the points ledger or a delivery record", async () => {
  await seedRecords();
  const owner = await asRole("owner");
  await assertFails(setDoc(doc(owner, `${CUSTOMER}/activity/forged`), { points: 500 }));
  await assertFails(
    updateDoc(doc(owner, `${ROOT}/receipt_deliveries/rd_one`), { status: "read" }),
  );
  await assertFails(
    updateDoc(doc(owner, `${ROOT}/email_receipt_deliveries/ed_one`), { status: "sent" }),
  );
});

test("another business's customers are not readable", async () => {
  await seedRecords();
  const outsider = await asRole("owner", "owner-b", "tenant-b");
  await assertFails(getDoc(doc(outsider, CUSTOMER)));
});

test("the WhatsApp and email receipt bookkeeping is server-only", async () => {
  await seedDocuments(testEnvironment, {
    "whatsapp_messages/wamid.one": { tenantId: "tenant-a", deliveryId: "rd_one" },
    "whatsapp_suppressions/hash": { at: Timestamp.fromMillis(0) },
    "whatsapp_auto_replies/hash": { at: Timestamp.fromMillis(0) },
    "email_receipt_messages/hash": { tenantId: "tenant-a", deliveryId: "ed_one" },
    "email_receipt_suppressions/hash": { at: Timestamp.fromMillis(0) },
  });
  const owner = await asRole("owner");
  for (const path of [
    "whatsapp_messages/wamid.one",
    "whatsapp_suppressions/hash",
    "whatsapp_auto_replies/hash",
    "email_receipt_messages/hash",
    "email_receipt_suppressions/hash",
  ]) {
    await assertFails(getDoc(doc(owner, path)));
    await assertFails(setDoc(doc(owner, path), { forged: true }));
  }
});

test("a cashier reads the repayments they took, and management reads all", async () => {
  await seedDocuments(testEnvironment, {
    [`${ROOT}/customer_payments/cp_mine`]: {
      customerId: "cu_jane",
      amountMinor: 50000,
      tender: "cash",
      recordedBy: "cashier-a",
    },
    [`${ROOT}/customer_payments/cp_theirs`]: {
      customerId: "cu_jane",
      amountMinor: 50000,
      tender: "cash",
      recordedBy: "cashier-b",
    },
  });
  const cashier = await asRole("cashier");
  await assertSucceeds(getDoc(doc(cashier, `${ROOT}/customer_payments/cp_mine`)));
  await assertFails(getDoc(doc(cashier, `${ROOT}/customer_payments/cp_theirs`)));
  await assertFails(setDoc(doc(cashier, `${ROOT}/customer_payments/cp_new`), {
    customerId: "cu_jane",
    amountMinor: 1,
    tender: "cash",
    recordedBy: "cashier-a",
  }));
  const manager = await asRole("manager");
  await assertSucceeds(getDoc(doc(manager, `${ROOT}/customer_payments/cp_theirs`)));
  await assertFails(updateDoc(doc(manager, `${ROOT}/customer_payments/cp_theirs`), {
    amountMinor: 1,
  }));
});
