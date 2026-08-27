import { after, before, beforeEach, describe, test } from "node:test";

import { assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import { deleteObject, getBytes, ref, uploadBytes } from "firebase/storage";

import {
  activeTenantDocuments,
  authenticatedStorage,
  createStorageRulesTestEnvironment,
  seedDocuments,
} from "./support.js";

let testEnvironment;

const imagePath =
  "tenantProductImages/tenant-a/product-a/00000000-0000-4000-8000-000000000001.png";
const png = Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

function upload(storage, path = imagePath, options = {}) {
  return uploadBytes(ref(storage, path), options.bytes ?? png, {
    contentType: options.contentType ?? "image/png",
    customMetadata: options.customMetadata ?? {
      tenantId: "tenant-a",
      productId: "product-a",
    },
  });
}

describe("tenant product image storage rules", () => {
  before(async () => {
    testEnvironment = await createStorageRulesTestEnvironment();
  });

  beforeEach(async () => {
    await testEnvironment.clearFirestore();
    await testEnvironment.clearStorage();
  });

  after(async () => {
    await testEnvironment?.cleanup();
  });

  test("owner, admin, and manager may upload a valid owned image", async () => {
    for (const role of ["owner", "admin", "manager"]) {
      const uid = `${role}-a`;
      await seedDocuments(
        testEnvironment,
        activeTenantDocuments({ uid, role }),
      );
      const path = imagePath.replace("000000000001", `00000000000${role.length}`);
      await assertSucceeds(upload(authenticatedStorage(testEnvironment, uid), path));
    }
  });

  test("cashiers may read but cannot write", async () => {
    await seedDocuments(
      testEnvironment,
      activeTenantDocuments({ uid: "manager-a", role: "manager" }),
    );
    await assertSucceeds(upload(authenticatedStorage(testEnvironment, "manager-a")));

    await seedDocuments(
      testEnvironment,
      activeTenantDocuments({ uid: "cashier-a", role: "cashier" }),
    );
    const cashier = authenticatedStorage(testEnvironment, "cashier-a");
    await assertSucceeds(getBytes(ref(cashier, imagePath)));
    await assertFails(upload(cashier, imagePath.replace("0001", "0002")));
  });

  test("inactive and cross-tenant members cannot read", async () => {
    await seedDocuments(
      testEnvironment,
      activeTenantDocuments({ uid: "manager-a", role: "manager" }),
    );
    await assertSucceeds(upload(authenticatedStorage(testEnvironment, "manager-a")));

    await seedDocuments(
      testEnvironment,
      activeTenantDocuments({ uid: "inactive-a", staffStatus: "disabled" }),
    );
    await assertFails(
      getBytes(ref(authenticatedStorage(testEnvironment, "inactive-a"), imagePath)),
    );

    await seedDocuments(
      testEnvironment,
      activeTenantDocuments({ uid: "tenant-b-user", tenantId: "tenant-b" }),
    );
    await assertFails(
      getBytes(
        ref(authenticatedStorage(testEnvironment, "tenant-b-user"), imagePath),
      ),
    );
  });

  test("type, size, and ownership metadata are enforced", async () => {
    await seedDocuments(
      testEnvironment,
      activeTenantDocuments({ uid: "manager-a", role: "manager" }),
    );
    const storage = authenticatedStorage(testEnvironment, "manager-a");

    await assertFails(upload(storage, imagePath, { contentType: "image/gif" }));
    await assertFails(
      upload(storage, imagePath, {
        customMetadata: { tenantId: "tenant-b", productId: "product-a" },
      }),
    );
    await assertFails(
      upload(storage, imagePath, { bytes: new Uint8Array(5 * 1024 * 1024 + 1) }),
    );
  });

  test("managers can delete an owned image", async () => {
    await seedDocuments(
      testEnvironment,
      activeTenantDocuments({ uid: "manager-a", role: "manager" }),
    );
    const storage = authenticatedStorage(testEnvironment, "manager-a");
    await assertSucceeds(upload(storage));
    await assertSucceeds(deleteObject(ref(storage, imagePath)));
  });
});
