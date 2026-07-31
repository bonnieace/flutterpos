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

const DEVICE_A = "dev-0123456789abcdef0123456789abcdef";
const BUSINESS_DATE = "2026-07-31";

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

/** Two canonical cashiers plus a second business the same identity works in. */
async function seedShiftTenant() {
  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({ uid: "cashier-a", role: "cashier" }),
    "users/cashier-b": {
      accountType: "tenant_user",
      globalStatus: "active",
      membershipCount: 1,
    },
    "tenants/tenant-a/staff/cashier-b": {
      uid: "cashier-b",
      role: "cashier",
      status: "active",
    },
    "tenants/tenant-b": {
      name: "tenant-b",
      ownerUid: "owner-b",
      status: "active",
    },
  });
}

/** The exact document the shift controller creates when a shift opens. */
function openShiftDocument({
  shiftId = "shift-a",
  tenantId = "tenant-a",
  staffId = "cashier-a",
  overrides = {},
} = {}) {
  return {
    shiftId,
    tenantId,
    staffId,
    deviceId: DEVICE_A,
    businessDate: BUSINESS_DATE,
    status: "open",
    startTime: serverTimestamp(),
    ...overrides,
  };
}

function openShift(firestore, options = {}) {
  const shiftId = options.shiftId ?? "shift-a";
  const tenantId = options.tenantId ?? "tenant-a";
  return setDoc(
    doc(firestore, `tenants/${tenantId}/shifts/${shiftId}`),
    openShiftDocument({ ...options, shiftId, tenantId }),
  );
}

/** The exact update the shift controller writes when a shift closes. */
function closeShift(firestore, { shiftId = "shift-a", overrides = {} } = {}) {
  return updateDoc(doc(firestore, `tenants/tenant-a/shifts/${shiftId}`), {
    status: "closed",
    closingCashMinor: 125000,
    closingCash: 1250,
    endTime: serverTimestamp(),
    ...overrides,
  });
}

async function storedShift(shiftId, tenantId = "tenant-a") {
  let data;
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const snapshot = await getDoc(
      doc(context.firestore(), `tenants/${tenantId}/shifts/${shiftId}`),
    );
    data = snapshot.exists() ? snapshot.data() : undefined;
  });
  return data;
}

test("a cashier opens and closes exactly one server-timed shift", async () => {
  await seedShiftTenant();
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");

  await assertSucceeds(openShift(firestore));
  const opened = await storedShift("shift-a");
  if (opened.status !== "open" || !(opened.startTime instanceof Timestamp)) {
    throw new Error("The opened shift is not server-timed.");
  }

  await assertSucceeds(closeShift(firestore));
  const closed = await storedShift("shift-a");
  if (closed.status !== "closed" || !(closed.endTime instanceof Timestamp)) {
    throw new Error("The closed shift is not server-timed.");
  }
  if (closed.startTime.toMillis() !== opened.startTime.toMillis()) {
    throw new Error("Closing rewrote the immutable start time.");
  }
  if (closed.closingCashMinor !== 125000) {
    throw new Error("The counted cash was not recorded.");
  }
});

test("a shift must repeat its own identity and device", async () => {
  await seedShiftTenant();
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");
  const denied = [
    ["other-shift-id", { overrides: { shiftId: "shift-other" } }],
    ["other-tenant-id", { overrides: { tenantId: "tenant-b" } }],
    ["missing-device", { overrides: { deviceId: null } }],
    ["empty-device", { overrides: { deviceId: "" } }],
    ["numeric-device", { overrides: { deviceId: 7 } }],
    ["free-text-date", { overrides: { businessDate: "31 July 2026" } }],
    ["missing-date", { overrides: { businessDate: null } }],
  ];

  for (const [name, options] of denied) {
    await assertFails(openShift(firestore, { shiftId: `shift-${name}`, ...options }));
    if (await storedShift(`shift-${name}`)) {
      throw new Error(`A denied ${name} shift was still created.`);
    }
  }
});

test("a client cannot choose when a shift began or pre-close it", async () => {
  await seedShiftTenant();
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");
  const denied = [
    [
      "client-start",
      { startTime: Timestamp.fromDate(new Date("2020-01-01T00:00:00Z")) },
    ],
    ["missing-start", { startTime: null }],
    ["pre-closed", { status: "closed" }],
    ["already-ended", { endTime: serverTimestamp() }],
  ];

  for (const [name, overrides] of denied) {
    await assertFails(
      openShift(firestore, { shiftId: `shift-${name}`, overrides }),
    );
    if (await storedShift(`shift-${name}`)) {
      throw new Error(`A denied ${name} shift was still created.`);
    }
  }
});

test("a shift is always opened by its own cashier", async () => {
  await seedShiftTenant();

  await assertFails(
    openShift(authenticatedFirestore(testEnvironment, "cashier-a"), {
      shiftId: "shift-foreign",
      overrides: { staffId: "cashier-b" },
    }),
  );
  // The second business has no canonical staff record for this identity.
  await assertFails(
    openShift(authenticatedFirestore(testEnvironment, "cashier-a"), {
      shiftId: "shift-cross",
      tenantId: "tenant-b",
    }),
  );
  if (await storedShift("shift-cross", "tenant-b")) {
    throw new Error("A cross-business shift was created.");
  }
});

test("an inactive or unknown identity cannot open or read a shift", async () => {
  await seedShiftTenant();
  await assertSucceeds(
    openShift(authenticatedFirestore(testEnvironment, "cashier-a")),
  );
  await seedDocuments(testEnvironment, {
    "tenants/tenant-a/staff/cashier-a": {
      uid: "cashier-a",
      role: "cashier",
      status: "inactive",
    },
  });

  const inactive = authenticatedFirestore(testEnvironment, "cashier-a");
  await assertFails(
    openShift(inactive, { shiftId: "shift-after-deactivation" }),
  );
  await assertFails(closeShift(inactive));
  await assertFails(getDoc(doc(inactive, "tenants/tenant-a/shifts/shift-a")));

  const outsider = authenticatedFirestore(testEnvironment, "cashier-b");
  await assertSucceeds(getDoc(doc(outsider, "tenants/tenant-a/shifts/shift-a")));
});

test("only the shift's own cashier may close it, exactly once", async () => {
  await seedShiftTenant();
  const owner = authenticatedFirestore(testEnvironment, "cashier-a");
  await assertSucceeds(openShift(owner));

  const colleague = authenticatedFirestore(testEnvironment, "cashier-b");
  await assertFails(closeShift(colleague));

  await assertSucceeds(closeShift(owner));
  // A closed shift is terminal: it cannot be closed again or reopened.
  await assertFails(closeShift(owner));
  await assertFails(
    updateDoc(doc(owner, "tenants/tenant-a/shifts/shift-a"), {
      status: "open",
      endTime: serverTimestamp(),
      closingCashMinor: 0,
      closingCash: 0,
    }),
  );
  await assertFails(deleteDoc(doc(owner, "tenants/tenant-a/shifts/shift-a")));

  if ((await storedShift("shift-a")).status !== "closed") {
    throw new Error("A terminal shift was reopened or removed.");
  }
});

test("closing may not rewrite the shift envelope or skip the count", async () => {
  await seedShiftTenant();
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");
  const denied = [
    ["other-staff", { staffId: "cashier-b" }],
    ["other-date", { businessDate: "2026-07-30" }],
    ["other-device", { deviceId: "dev-ffffffffffffffffffffffffffffffff" }],
    ["other-tenant", { tenantId: "tenant-b" }],
    ["rewritten-start", { startTime: serverTimestamp() }],
    ["client-end", { endTime: Timestamp.fromDate(new Date("2020-01-01Z")) }],
    ["missing-cash", { closingCashMinor: null }],
    ["negative-cash", { closingCashMinor: -1 }],
    ["string-cash", { closingCashMinor: "125000" }],
    ["extra-field", { totalSales: 999999 }],
  ];

  for (const [name, overrides] of denied) {
    await seedDocuments(testEnvironment, {
      [`tenants/tenant-a/shifts/shift-${name}`]: {
        shiftId: `shift-${name}`,
        tenantId: "tenant-a",
        staffId: "cashier-a",
        deviceId: DEVICE_A,
        businessDate: BUSINESS_DATE,
        status: "open",
        startTime: Timestamp.fromMillis(1785484800000),
      },
    });

    await assertFails(closeShift(firestore, { shiftId: `shift-${name}`, overrides }));
    if ((await storedShift(`shift-${name}`)).status !== "open") {
      throw new Error(`A denied ${name} close still changed the shift.`);
    }
  }
});
