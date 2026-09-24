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

const ROOT = "tenants/tenant-a";

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
    [`${ROOT}/suppliers/sp_abc`]: { name: "ABC Distributors", active: true },
    [`${ROOT}/supplier_deliveries/sd_one`]: {
      tenantId: "tenant-a",
      supplierId: "sp_abc",
      lineCount: 1,
      valueMinor: 100000,
      createdAt: Timestamp.fromMillis(1785574800000),
    },
    [`${ROOT}/production_batches/pb_one`]: {
      tenantId: "tenant-a",
      productId: "pd_bread",
      quantity: 100,
      unitCostMinor: 3000,
      createdAt: Timestamp.fromMillis(1785574800000),
    },
  });
}

test("the roles that receive and produce stock read all three collections", async () => {
  await seedRecords();
  for (const role of ["owner", "admin", "manager"]) {
    const db = await asRole(role);
    await assertSucceeds(getDoc(doc(db, `${ROOT}/suppliers/sp_abc`)));
    await assertSucceeds(getDoc(doc(db, `${ROOT}/supplier_deliveries/sd_one`)));
    await assertSucceeds(getDoc(doc(db, `${ROOT}/production_batches/pb_one`)));
  }
});

test("a cashier reads none of them", async () => {
  await seedRecords();
  const db = await asRole("cashier");

  await assertFails(getDoc(doc(db, `${ROOT}/suppliers/sp_abc`)));
  await assertFails(getDocs(collection(db, `${ROOT}/supplier_deliveries`)));
  await assertFails(getDocs(collection(db, `${ROOT}/production_batches`)));
});

test("a record the server has not written yet still answers a manager", async () => {
  // The outbox confirms a queued delivery or batch by reading its own path
  // before re-sending it. A rule that touched a document field would raise on a
  // document that does not exist, and the record would never be re-sent.
  const db = await asRole("manager");

  await assertSucceeds(getDoc(doc(db, `${ROOT}/supplier_deliveries/sd_not_yet`)));
  await assertSucceeds(getDoc(doc(db, `${ROOT}/production_batches/pb_not_yet`)));
  await assertSucceeds(getDoc(doc(db, `${ROOT}/suppliers/sp_not_yet`)));
});

test("a supplier's history and a product's last batch are readable as queried", async () => {
  await seedRecords();
  const db = await asRole("manager");

  await assertSucceeds(getDocs(query(
    collection(db, `${ROOT}/supplier_deliveries`),
    where("supplierId", "==", "sp_abc"),
    orderBy("createdAt", "desc"),
    limit(20),
  )));
  await assertSucceeds(getDocs(query(
    collection(db, `${ROOT}/production_batches`),
    where("productId", "==", "pd_bread"),
    orderBy("createdAt", "desc"),
    limit(1),
  )));
});

test("no client writes a supplier, a delivery or a batch", async () => {
  await seedRecords();
  const db = await asRole("owner");

  await assertFails(setDoc(doc(db, `${ROOT}/suppliers/sp_new`), { name: "New", active: true }));
  await assertFails(updateDoc(doc(db, `${ROOT}/suppliers/sp_abc`), { active: false }));
  await assertFails(deleteDoc(doc(db, `${ROOT}/suppliers/sp_abc`)));
  await assertFails(setDoc(doc(db, `${ROOT}/supplier_deliveries/sd_new`), { lineCount: 1 }));
  await assertFails(updateDoc(doc(db, `${ROOT}/supplier_deliveries/sd_one`), { valueMinor: 1 }));
  await assertFails(setDoc(doc(db, `${ROOT}/production_batches/pb_new`), { quantity: 1 }));
  await assertFails(deleteDoc(doc(db, `${ROOT}/production_batches/pb_one`)));
});

test("another business's manager reads none of them", async () => {
  await seedRecords();
  const db = await asRole("manager", "manager-b", "tenant-b");

  await assertFails(getDoc(doc(db, `${ROOT}/suppliers/sp_abc`)));
  await assertFails(getDoc(doc(db, `${ROOT}/supplier_deliveries/sd_one`)));
  await assertFails(getDoc(doc(db, `${ROOT}/production_batches/pb_one`)));
});
