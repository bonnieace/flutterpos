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

// **This suite cannot see the document budget.** Cross-service Rules allow at
// most two unique Firestore documents per evaluation, and a third denies every
// request in production - but the emulator enforces no such limit. Verified
// 2026-09-03 by running both versions through this harness under identical seed
// data: the 3-document `memberStanding()` that this file was green against had
// product image upload and display broken for every user in every tenant.
//
// `storage.rules` now sits at exactly two, `tenants/{id}` and its `staff/{uid}`.
// Adding any lookup to it breaks the feature outright with this file still
// passing, so count the unique paths by hand after editing it:
//
//   grep -o "firestore\.\(get\|exists\)([a-zA-Z]*Path" storage.rules | sort -u
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

  test("type and size are enforced", async () => {
    await seedDocuments(
      testEnvironment,
      activeTenantDocuments({ uid: "manager-a", role: "manager" }),
    );
    const storage = authenticatedStorage(testEnvironment, "manager-a");

    await assertFails(upload(storage, imagePath, { contentType: "image/gif" }));
    // **Custom metadata is no longer a condition of the write**, so an object
    // whose metadata names another tenant is accepted - under this tenant's own
    // path, which is the only thing that ever authorised it. See `storage.rules`
    // for why the two clauses that compared them went.
    await assertSucceeds(
      upload(storage, imagePath, {
        customMetadata: { tenantId: "tenant-b", productId: "product-a" },
      }),
    );
    await assertFails(
      upload(storage, imagePath, { bytes: new Uint8Array(5 * 1024 * 1024 + 1) }),
    );
  });

  test("a business that has stopped trading is dark", async () => {
    await seedDocuments(
      testEnvironment,
      activeTenantDocuments({ uid: "manager-a", role: "manager" }),
    );
    await assertSucceeds(upload(authenticatedStorage(testEnvironment, "manager-a")));

    for (const tenantStatus of ["suspended", "archived"]) {
      await seedDocuments(
        testEnvironment,
        activeTenantDocuments({
          uid: "manager-a",
          role: "manager",
          tenantStatus,
        }),
      );
      const storage = authenticatedStorage(testEnvironment, "manager-a");
      await assertFails(getBytes(ref(storage, imagePath)));
      await assertFails(upload(storage, imagePath.replace("0001", "0003")));
    }
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
