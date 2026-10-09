import { after, afterEach, before, test } from "node:test";

import { assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import {
  Timestamp,
  deleteDoc,
  deleteField,
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
    // The device's clock when the cashier opened it. In the past, as it is for
    // every shift opened offline.
    openedAt: Timestamp.fromMillis(Date.now() - 60 * 60 * 1000),
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
    // The sale-derived summary nightly reconciliation verifies.
    totalSalesMinor: 98750,
    totalSales: 987.5,
    transactionCount: 3,
    // The blind tender declaration, all three or none. `declaredCashMinor`
    // restates `closingCashMinor` rather than replacing it, so no reader can be
    // shown two cash figures for one drawer that disagree.
    declaredCashMinor: 125000,
    declaredMpesaMinor: 34050,
    declaredCardMinor: 0,
    endTime: serverTimestamp(),
    closedAt: Timestamp.fromMillis(Date.now() - 60 * 1000),
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
  // The device's own times travel beside the server's, and are not the server's.
  if (
    !(closed.openedAt instanceof Timestamp) ||
    !(closed.closedAt instanceof Timestamp) ||
    closed.openedAt.toMillis() >= closed.startTime.toMillis()
  ) {
    throw new Error("The device's open and close times were not kept.");
  }
  if (closed.closingCashMinor !== 125000) {
    throw new Error("The counted cash was not recorded.");
  }
  if (closed.totalSales !== 987.5 || closed.transactionCount !== 3) {
    throw new Error("The closed shift carries no sale-derived summary.");
  }
  if (closed.declaredMpesaMinor !== 34050 || closed.declaredCardMinor !== 0) {
    throw new Error("The closed shift carries no tender declaration.");
  }
  if (closed.declaredCashMinor !== closed.closingCashMinor) {
    throw new Error("One drawer was recorded as two disagreeing cash figures.");
  }
});

test("an ordinary close must declare its tender", async () => {
  // #107: the declaration was optional for one release so that a device still
  // running the previous build could close - including the replay of a close it
  // recorded offline, which the controller would otherwise retry forever with
  // no way out. SIT clears local shift state instead, so the close that cannot
  // say how the drawer was made up is now refused at the rule.
  await seedShiftTenant();
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");
  await assertSucceeds(openShift(firestore));

  await assertFails(
    closeShift(firestore, {
      overrides: {
        declaredCashMinor: deleteField(),
        declaredMpesaMinor: deleteField(),
        declaredCardMinor: deleteField(),
      },
    }),
  );

  const closed = await storedShift("shift-a");
  if (closed.status === "closed") {
    throw new Error("A close with no declaration was accepted.");
  }
});

test("a recovery close may omit the declaration when another drawer holds it", async () => {
  // #107: the one close that still carries no declaration. Two open shifts for
  // one cashier mean one till and one count, so the drawer is declared onto the
  // shift that was counted and this one records none - asking twice would put
  // the same money against both. Reconciliation reads it as unverifiable rather
  // than as a missing declaration.
  await seedShiftTenant();
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");
  await assertSucceeds(openShift(firestore));

  await assertSucceeds(
    closeShift(firestore, {
      overrides: {
        closedWithoutEvidence: true,
        totalSalesMinor: 0,
        totalSales: 0,
        transactionCount: 0,
        declaredCashMinor: deleteField(),
        declaredMpesaMinor: deleteField(),
        declaredCardMinor: deleteField(),
      },
    }),
  );

  const closed = await storedShift("shift-a");
  if (closed.status !== "closed" || closed.declaredCashMinor !== undefined) {
    throw new Error("A recovery close with no declaration was refused.");
  }
});

test("a device holding none of a shift's sales may still close it", async () => {
  // The way out of a shift left open by an installation that no longer exists.
  // The summary is zero because it is unknown, and `closedWithoutEvidence` is
  // what stops the zeros being read as a shift that took nothing: the verifier
  // refuses the figures outright rather than reporting a variance against them.
  await seedShiftTenant();
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");
  await assertSucceeds(openShift(firestore));

  await assertSucceeds(
    closeShift(firestore, {
      overrides: {
        closedWithoutEvidence: true,
        totalSalesMinor: 0,
        totalSales: 0,
        transactionCount: 0,
      },
    }),
  );

  const closed = await storedShift("shift-a");
  if (closed.closedWithoutEvidence !== true || closed.transactionCount !== 0) {
    throw new Error("A recovery close was not recorded as unverifiable.");
  }
  // The declaration is still taken: it needs no sale evidence, and the server
  // derives the other side of the comparison itself.
  if (closed.declaredMpesaMinor !== 34050) {
    throw new Error("A recovery close dropped the declaration.");
  }
});

test("a close may name the drawer count that settled it", async () => {
  // One cashier holds one register and counts it once, so a close that sweeps
  // up a shift left open elsewhere settles both from that single count. The
  // verifier adds up the shifts sharing this name and measures the total
  // against the one declaration among them; without it, the counted shift was
  // reported as over by exactly what the other took.
  await seedShiftTenant();
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");
  await assertSucceeds(openShift(firestore));

  await assertSucceeds(
    closeShift(firestore, {
      overrides: { settlementId: "st-1789630427-a3f90c1d2e4b6789" },
    }),
  );

  const closed = await storedShift("shift-a");
  if (closed.settlementId !== "st-1789630427-a3f90c1d2e4b6789") {
    throw new Error("The close did not record the settlement it belongs to.");
  }
});

test("a close may say what the drawer handed back, and never a negative", async () => {
  // Refunds paid out of this drawer for returns, so the shift's own history
  // row can tell a drawer that is short from one that paid a customer back.
  // Reconciliation counts them again from the returns themselves.
  await seedShiftTenant();
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");
  await assertSucceeds(openShift(firestore));
  for (const refundedMinor of [-1, 100.5, "100"]) {
    await assertFails(closeShift(firestore, { overrides: { refundedMinor } }));
  }

  await assertSucceeds(closeShift(firestore, { overrides: { refundedMinor: 100000 } }));

  const closed = await storedShift("shift-a");
  if (closed.refundedMinor !== 100000) {
    throw new Error("The close did not record what the drawer handed back.");
  }
});

test("an empty shift may close with a zero summary", async () => {
  await seedShiftTenant();
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");
  await assertSucceeds(openShift(firestore));

  await assertSucceeds(
    closeShift(firestore, {
      overrides: {
        totalSalesMinor: 0,
        totalSales: 0,
        transactionCount: 0,
        closingCashMinor: 0,
        closingCash: 0,
        // A declaration of nothing is a real answer a till may give, and the
        // cash it declares still has to be the cash it records.
        declaredCashMinor: 0,
        declaredMpesaMinor: 0,
        declaredCardMinor: 0,
      },
    }),
  );

  const closed = await storedShift("shift-a");
  if (closed.transactionCount !== 0 || closed.status !== "closed") {
    throw new Error("A shift with no sales could not be closed.");
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
    ["missing-opened", { openedAt: null }],
    ["string-opened", { openedAt: "2026-09-24T18:02:00Z" }],
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

test("an opening float is optional, bounded, and never negative", async () => {
  await seedShiftTenant();
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");

  // The change in the drawer before the first sale. Nightly verification adds
  // it to the cash it expects of that drawer, so what is written here is what
  // the cashier is judged against - which is why a negative is refused rather
  // than clamped: it would lower what they have to account for.
  await assertSucceeds(
    openShift(firestore, {
      shiftId: "shift-float",
      overrides: { openingFloatMinor: 200000 },
    }),
  );
  // A shop that keeps no change writes no field, and reconciliation reads an
  // absent one as zero - which is what every shift opened before this meant.
  await assertSucceeds(openShift(firestore, { shiftId: "shift-no-float" }));

  const denied = [
    ["negative-float", { openingFloatMinor: -1 }],
    ["fractional-float", { openingFloatMinor: 1500.5 }],
    ["text-float", { openingFloatMinor: "2000" }],
    ["absurd-float", { openingFloatMinor: 1000000000001 }],
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

test("a close cannot rewrite the float the shift was opened on", async () => {
  // **The figure is fixed at open**, because it is half of the comparison the
  // close is marked against. A cashier who could raise it at close could raise
  // the cash expected of a drawer they had already counted, and settle any
  // shortfall by declaring the drawer had started fuller than it did.
  await seedShiftTenant();
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");
  await assertSucceeds(
    openShift(firestore, {
      shiftId: "shift-fixed-float",
      overrides: { openingFloatMinor: 200000 },
    }),
  );

  await assertFails(
    closeShift(firestore, {
      shiftId: "shift-fixed-float",
      overrides: { openingFloatMinor: 500000 },
    }),
  );
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

  // A colleague is active in the business but the shift is not theirs. The
  // read boundary was deliberately narrowed to match the client, which already
  // refuses a foreign shift; the role boundary is proved in shift-history.
  const colleague = authenticatedFirestore(testEnvironment, "cashier-b");
  await assertFails(getDoc(doc(colleague, "tenants/tenant-a/shifts/shift-a")));
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
    ["missing-closed", { closedAt: null }],
    ["string-closed", { closedAt: "2026-09-24T18:02:00Z" }],
    ["rewritten-opened", { openedAt: Timestamp.fromDate(new Date("2020-01-01Z")) }],
    ["missing-cash", { closingCashMinor: null }],
    ["negative-cash", { closingCashMinor: -1 }],
    ["string-cash", { closingCashMinor: "125000" }],
    ["extra-field", { cashierNote: "counted twice" }],
    // The closing summary is mandatory and must be internally coherent.
    ["missing-total", { totalSalesMinor: null, totalSales: null }],
    ["missing-count", { transactionCount: null }],
    ["negative-total", { totalSalesMinor: -1, totalSales: -0.01 }],
    ["negative-count", { transactionCount: -1 }],
    ["fractional-count", { transactionCount: 2.5 }],
    ["string-total", { totalSalesMinor: "98750" }],
    [
      "sales-without-transactions",
      { transactionCount: 0, totalSalesMinor: 500, totalSales: 5 },
    ],
    // The declaration is all three or none: two methods declared and one absent
    // would present the missing one as zero to every reader downstream.
    ["partial-declaration", { declaredMpesaMinor: null, declaredCardMinor: null }],
    ["one-missing-method", { declaredCardMinor: null }],
    // The same money under two names must never disagree.
    ["declared-cash-disagrees", { declaredCashMinor: 120000 }],
    ["negative-declared-mpesa", { declaredMpesaMinor: -1 }],
    ["string-declared-card", { declaredCardMinor: "0" }],
    ["fractional-declared-cash", { declaredCashMinor: 125000.5, closingCashMinor: 125000.5 }],
    ["oversize-declared-mpesa", { declaredMpesaMinor: 1000000000001 }],
    ["oversize-cash", { closingCashMinor: 1000000000001, declaredCashMinor: 1000000000001 }],
    // The recovery marker is never written false, and it forces the summary to
    // zero - which reconciliation is told not to believe rather than reading as
    // a shift that took nothing.
    ["evidence-flag-false", { closedWithoutEvidence: false }],
    ["evidence-flag-with-sales", { closedWithoutEvidence: true }],
    // The settlement is a label for grouping, not free text. An unbounded
    // string on a money document is a place to hide things, and a shape the
    // reconciliation grouping cannot parse is worse than no grouping at all.
    ["settlement-not-a-string", { settlementId: 12345 }],
    ["settlement-wrong-shape", { settlementId: "settlement-1" }],
    ["settlement-empty", { settlementId: "" }],
    ["settlement-short-suffix", { settlementId: "st-1789630427-abc" }],
    ["settlement-uppercase-suffix", { settlementId: "st-1789630427-ABCDEF0123456789" }],
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
