import { after, before, beforeEach, describe, test } from "node:test";

import { assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import { Timestamp } from "firebase/firestore";
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

const HOUR_MILLISECONDS = 60 * 60 * 1000;

/** The provisional trading window `requestTenant` opens, still open. */
function openWindow() {
  return Timestamp.fromMillis(Date.now() + HOUR_MILLISECONDS);
}

/** The same window, shut. */
function shutWindow() {
  return Timestamp.fromMillis(Date.now() - HOUR_MILLISECONDS);
}

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

  test("a pending business inside its window uploads like an approved one", async () => {
    // The gap this closes: Firestore let a self-serve business sell from the
    // hour it was created and Storage made it wait for a platform approval, so
    // the first thing a new shopkeeper tried to do - photograph their stock -
    // was the one thing refused.
    await seedDocuments(
      testEnvironment,
      activeTenantDocuments({
        uid: "manager-a",
        role: "manager",
        tenantStatus: "pending",
        provisionalUntil: openWindow(),
      }),
    );
    const storage = authenticatedStorage(testEnvironment, "manager-a");
    await assertSucceeds(upload(storage));
    await assertSucceeds(getBytes(ref(storage, imagePath)));
    await assertSucceeds(deleteObject(ref(storage, imagePath)));
  });

  test("a shut window keeps the pictures visible and refuses new ones", async () => {
    await seedDocuments(
      testEnvironment,
      activeTenantDocuments({
        uid: "manager-a",
        role: "manager",
        tenantStatus: "pending",
        provisionalUntil: openWindow(),
      }),
    );
    await assertSucceeds(upload(authenticatedStorage(testEnvironment, "manager-a")));

    await seedDocuments(
      testEnvironment,
      activeTenantDocuments({
        uid: "manager-a",
        role: "manager",
        tenantStatus: "pending",
        provisionalUntil: shutWindow(),
      }),
    );
    const lapsed = authenticatedStorage(testEnvironment, "manager-a");
    await assertSucceeds(getBytes(ref(lapsed, imagePath)));
    await assertFails(upload(lapsed, imagePath.replace("0001", "0002")));
    await assertFails(deleteObject(ref(lapsed, imagePath)));
  });

  test("a pending business with no window at all never traded", async () => {
    // Written before `provisionalUntil` existed. It must read as lapsed rather
    // than as permanently provisional, which is what an untyped read would
    // give.
    await seedDocuments(
      testEnvironment,
      activeTenantDocuments({
        uid: "manager-a",
        role: "manager",
        tenantStatus: "pending",
      }),
    );
    await assertFails(upload(authenticatedStorage(testEnvironment, "manager-a")));
  });

  test("a rejected business is dark", async () => {
    await seedDocuments(
      testEnvironment,
      activeTenantDocuments({ uid: "manager-a", role: "manager" }),
    );
    await assertSucceeds(upload(authenticatedStorage(testEnvironment, "manager-a")));

    for (const tenantStatus of ["rejected", "suspended", "archived"]) {
      await seedDocuments(
        testEnvironment,
        activeTenantDocuments({
          uid: "manager-a",
          role: "manager",
          tenantStatus,
          provisionalUntil: openWindow(),
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
