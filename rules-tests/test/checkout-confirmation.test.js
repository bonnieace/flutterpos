import { after, afterEach, before, test } from "node:test";

import { assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import { doc, getDoc } from "firebase/firestore";

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

test("checkout confirmation reads the exact deterministic sale or proves it missing", async () => {
  const matchingHash = "a".repeat(64);
  const mismatchingHash = "b".repeat(64);
  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({ uid: "cashier", role: "cashier" }),
    "tenants/tenant-a/sales/checkout-matching": {
      checkoutId: "checkout-matching",
      tenantId: "tenant-a",
      payloadHash: matchingHash,
    },
    "tenants/tenant-a/sales/checkout-mismatching": {
      checkoutId: "checkout-mismatching",
      tenantId: "tenant-a",
      payloadHash: mismatchingHash,
    },
  });
  const firestore = authenticatedFirestore(testEnvironment, "cashier");

  const matching = await assertSucceeds(
    getDoc(doc(firestore, "tenants/tenant-a/sales/checkout-matching")),
  );
  const mismatching = await assertSucceeds(
    getDoc(doc(firestore, "tenants/tenant-a/sales/checkout-mismatching")),
  );
  const missing = await assertSucceeds(
    getDoc(doc(firestore, "tenants/tenant-a/sales/checkout-missing")),
  );

  if (matching.data().payloadHash !== matchingHash) {
    throw new Error("Matching confirmation hash was not returned exactly.");
  }
  if (mismatching.data().payloadHash !== mismatchingHash) {
    throw new Error("Mismatching confirmation hash was not returned exactly.");
  }
  if (missing.exists()) {
    throw new Error("A missing deterministic sale unexpectedly existed.");
  }
});

test("malformed canonical sale evidence remains readable for fail-closed classification", async () => {
  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({ uid: "cashier", role: "cashier" }),
    "tenants/tenant-a/sales/checkout-malformed": {
      checkoutId: "different-checkout",
      tenantId: "tenant-a",
      payloadHash: "not-a-sha256",
    },
  });
  const firestore = authenticatedFirestore(testEnvironment, "cashier");
  const snapshot = await assertSucceeds(
    getDoc(doc(firestore, "tenants/tenant-a/sales/checkout-malformed")),
  );

  if (snapshot.data().checkoutId === "checkout-malformed") {
    throw new Error("Malformed seeded identity unexpectedly appeared valid.");
  }
});

test("confirmation cannot read another tenant or bypass global disablement", async () => {
  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({ uid: "cashier", role: "cashier" }),
    "tenants/tenant-b": {
      name: "tenant-b",
      ownerUid: "owner-b",
      status: "active",
    },
    "tenants/tenant-b/sales/checkout-b": {
      checkoutId: "checkout-b",
      tenantId: "tenant-b",
      payloadHash: "a".repeat(64),
    },
  });
  const firestore = authenticatedFirestore(testEnvironment, "cashier");
  await assertFails(
    getDoc(doc(firestore, "tenants/tenant-b/sales/checkout-b")),
  );

  await seedDocuments(testEnvironment, {
    "users/cashier": { accountType: "tenant_user", globalStatus: "disabled" },
  });
  await assertFails(
    getDoc(doc(firestore, "tenants/tenant-a/sales/checkout-missing")),
  );
});
