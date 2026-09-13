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

const TRAIL_PATH = "tenants/tenant-a/audit_logs";

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

/** The envelope every tenant `audit_logs` writer records. */
function auditRecord(overrides = {}) {
  return {
    tenantId: "tenant-a",
    eventType: "staff_invited",
    actorUid: "admin-a",
    targetUid: "cashier-a",
    requestId: "invite-staff-abcdefgh",
    createdAt: Timestamp.fromMillis(1785574800000),
    ...overrides,
  };
}

/**
 * `lifecycle/tenantLifecycle.ts` records the tenant-readable lifecycle event
 * with an `actorType` and no `actorUid`: the platform is not a member of the
 * business it acted on.
 */
function platformRecord(overrides = {}) {
  return {
    tenantId: "tenant-a",
    eventType: "tenant_lifecycle_changed",
    fromStatus: "suspended",
    toStatus: "active",
    actorType: "platform_admin",
    fanoutOperationId: "op-1",
    createdAt: Timestamp.fromMillis(1785574800000),
    ...overrides,
  };
}

async function seedTrail() {
  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({ uid: "cashier-a", role: "cashier" }),
    ...Object.fromEntries(
      [
        ["admin-a", "admin"],
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
    [`${TRAIL_PATH}/aud_001`]: auditRecord(),
    [`${TRAIL_PATH}/aud_002`]: platformRecord(),
  });
}

/** The exact business-wide page the client issues. */
function trailPage(firestore, path = TRAIL_PATH) {
  return query(collection(firestore, path), orderBy("__name__"), limit(21));
}

/** The exact event-narrowed page the client issues. */
function eventPage(firestore, eventType, path = TRAIL_PATH) {
  return query(
    collection(firestore, path),
    where("eventType", "==", eventType),
    orderBy("__name__"),
    limit(21),
  );
}

test("an owner and an admin page the business's whole trail", async () => {
  await seedTrail();

  for (const uid of ["owner-a", "admin-a"]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    const record = await assertSucceeds(
      getDoc(doc(firestore, `${TRAIL_PATH}/aud_001`)),
    );
    if (record.data().eventType !== "staff_invited") {
      throw new Error(`Unexpected audit record for ${uid}.`);
    }

    // Ascending document ID with no filter, one more document than the page
    // size. An audit ID is the operation, request, or delivery ID the event
    // belongs to, so document order carries no time information and a
    // descending page would be neither newest first nor servable without a
    // composite index.
    const page = await assertSucceeds(getDocs(trailPage(firestore)));
    if (page.docs.map((entry) => entry.id).join(",") !== "aud_001,aud_002") {
      throw new Error(`Unexpected trail order for ${uid}.`);
    }

    // The same order narrowed by one equality filter, which Firestore's
    // automatic single-field index serves without a composite index. If that
    // ever stops being true the emulator rejects the query here rather than the
    // client failing in production.
    const narrowed = await assertSucceeds(
      getDocs(eventPage(firestore, "tenant_lifecycle_changed")),
    );
    if (narrowed.docs.map((entry) => entry.id).join(",") !== "aud_002") {
      throw new Error(`Unexpected event page for ${uid}.`);
    }
  }
});

test("a business whose trail has not started still answers", async () => {
  await seedTrail();
  const firestore = authenticatedFirestore(testEnvironment, "owner-a");

  // An unwritten record discloses nothing, and an event a business has never
  // caused is the normal state, so both must answer rather than deny.
  const missing = await assertSucceeds(
    getDoc(doc(firestore, `${TRAIL_PATH}/aud_never`)),
  );
  if (missing.exists()) {
    throw new Error("An unwritten audit record unexpectedly existed.");
  }
  const emptyEvent = await assertSucceeds(
    getDocs(eventPage(firestore, "owner_recovered")),
  );
  if (!emptyEvent.empty) {
    throw new Error("An uncaused event unexpectedly returned records.");
  }

  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({
      uid: "owner-c",
      tenantId: "tenant-c",
      role: "owner",
    }),
  });
  const fresh = authenticatedFirestore(testEnvironment, "owner-c");
  const emptyTrail = await assertSucceeds(
    getDocs(trailPage(fresh, "tenants/tenant-c/audit_logs")),
  );
  if (!emptyTrail.empty) {
    throw new Error("An empty trail unexpectedly returned documents.");
  }
});

test("a manager reads the corrections but never the whole trail", async () => {
  await seedTrail();
  const firestore = authenticatedFirestore(testEnvironment, "manager-a");

  // This is the boundary that makes the trail narrower than the stock
  // surfaces on purpose: a manager records and answers for stock corrections,
  // but the trail also names who was invited, deactivated, and recovered.
  await assertSucceeds(
    getDocs(
      query(
        collection(firestore, "tenants/tenant-a/stock_adjustments"),
        orderBy("__name__"),
        limit(21),
      ),
    ),
  );
  await assertFails(getDoc(doc(firestore, `${TRAIL_PATH}/aud_001`)));
  await assertFails(getDoc(doc(firestore, `${TRAIL_PATH}/aud_never`)));
  await assertFails(getDocs(trailPage(firestore)));
  await assertFails(getDocs(eventPage(firestore, "staff_invited")));
});

test("a cashier reads nothing at all from the trail", async () => {
  await seedTrail();
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");

  await assertFails(getDoc(doc(firestore, `${TRAIL_PATH}/aud_001`)));
  await assertFails(getDocs(trailPage(firestore)));
  await assertFails(getDocs(eventPage(firestore, "staff_invited")));
});

test("a platform admin reads the trail it is the actor on", async () => {
  await seedTrail();
  await seedDocuments(testEnvironment, {
    "users/platform-a": {
      accountType: "platform_admin",
      globalStatus: "active",
    },
  });

  // The platform causes the lifecycle and alert records here, so it must be
  // able to see what it did without being a member of the business.
  const platform = authenticatedFirestore(testEnvironment, "platform-a", {
    platformRole: "superAdmin",
  });
  await assertSucceeds(getDoc(doc(platform, `${TRAIL_PATH}/aud_002`)));
  await assertSucceeds(getDocs(trailPage(platform)));

  // A platform identity without the claim is not a platform admin.
  const unclaimed = authenticatedFirestore(testEnvironment, "platform-a");
  await assertFails(getDoc(doc(unclaimed, `${TRAIL_PATH}/aud_002`)));
});

test("no client may record, rewrite, or delete an event", async () => {
  await seedTrail();
  await seedDocuments(testEnvironment, {
    "users/platform-a": {
      accountType: "platform_admin",
      globalStatus: "active",
    },
  });

  for (const firestore of [
    authenticatedFirestore(testEnvironment, "owner-a"),
    authenticatedFirestore(testEnvironment, "admin-a"),
    authenticatedFirestore(testEnvironment, "cashier-a"),
    authenticatedFirestore(testEnvironment, "platform-a", {
      platformRole: "superAdmin",
    }),
  ]) {
    // A client that could create here could fabricate evidence of an event
    // that never happened; one that could update or delete could erase the
    // only record of one that did.
    await assertFails(
      setDoc(doc(firestore, `${TRAIL_PATH}/aud_forged`), auditRecord()),
    );
    await assertFails(
      setDoc(
        doc(firestore, `${TRAIL_PATH}/aud_001`),
        auditRecord({ actorUid: "cashier-a" }),
      ),
    );
    await assertFails(deleteDoc(doc(firestore, `${TRAIL_PATH}/aud_001`)));
  }
});

test("another business's trail is never reached", async () => {
  await seedTrail();
  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({
      uid: "owner-b",
      tenantId: "tenant-b",
      role: "owner",
    }),
    "tenants/tenant-b/audit_logs/aud_001": auditRecord({
      tenantId: "tenant-b",
    }),
  });

  const foreign = authenticatedFirestore(testEnvironment, "owner-b");
  await assertFails(getDoc(doc(foreign, `${TRAIL_PATH}/aud_001`)));
  await assertFails(getDocs(trailPage(foreign)));
  await assertFails(getDocs(eventPage(foreign, "staff_invited")));
  // Its own business still answers, so the denial is the boundary and not a
  // broken rule.
  await assertSucceeds(
    getDoc(doc(foreign, "tenants/tenant-b/audit_logs/aud_001")),
  );
  await assertSucceeds(
    getDocs(trailPage(foreign, "tenants/tenant-b/audit_logs")),
  );
});

test("a deactivated or non-member identity reads no events", async () => {
  await seedTrail();
  await seedDocuments(testEnvironment, {
    "users/outsider": {
      accountType: "tenant_user",
      globalStatus: "active",
      membershipCount: 0,
    },
  });

  const outsider = authenticatedFirestore(testEnvironment, "outsider");
  await assertFails(getDoc(doc(outsider, `${TRAIL_PATH}/aud_001`)));
  await assertFails(getDocs(trailPage(outsider)));

  await seedDocuments(testEnvironment, {
    "tenants/tenant-a/staff/admin-a": {
      uid: "admin-a",
      role: "admin",
      status: "inactive",
    },
  });
  const deactivated = authenticatedFirestore(testEnvironment, "admin-a");
  await assertFails(getDoc(doc(deactivated, `${TRAIL_PATH}/aud_001`)));
  await assertFails(getDocs(trailPage(deactivated)));
});
