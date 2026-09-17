import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {planSaleTenderRecord, saleTenderAuditId} from "./saleTender";

/**
 * The decisions behind `setSaleTender`, as units.
 *
 * **What changed, and why this file exists.** The till stopped preselecting a
 * payment method, so a cashier who was never told how the customer paid now
 * saves a sale that names none. That is honest and useless unless the question
 * can be answered afterwards, and this is the only path that answers it. It is
 * also the only write a sale ever accepts after it is created, which is why the
 * direction and the caller are both pinned down here rather than left to the
 * surface that calls it.
 */

const TENANT = "tenant-a";
const SALE = "co-1754000000000-abcdabcdabcdabcd";
const ACTOR = "user-cashier";
const REQUEST = "tender-request-1";

function plan(overrides: {
  actorUid?: string;
  sale?: {soldById?: unknown; tender?: unknown; businessDate?: unknown};
  shiftClosed?: boolean;
} = {}) {
  return planSaleTenderRecord({
    tenantId: TENANT,
    saleId: SALE,
    actorUid: overrides.actorUid ?? ACTOR,
    requestId: REQUEST,
    tender: "mpesa",
    sale: overrides.sale ?? {soldById: ACTOR, businessDate: "2026-07-30"},
    shiftClosed: overrides.shiftClosed ?? false,
  });
}

function refusalCode(run: () => unknown): string {
  try {
    run();
  } catch (error) {
    assert.ok(error instanceof HttpsError);
    return error.code;
  }
  return "no-error";
}

test("recording a tender writes the sale, the audit entry, and the dirty day", () => {
  const recorded = plan();

  assert.equal(recorded.auditId, saleTenderAuditId(REQUEST));
  assert.equal(recorded.businessDate, "2026-07-30");
  assert.equal(recorded.replaces, false);
  // No `payloadHash` anywhere in this: the hash attests to what the till
  // committed, and this answer arrived afterwards. `tenderSetBy` is what says
  // so, and is the reason a reader never has to guess which it is holding.
  assert.deepEqual(recorded.saleData, {tender: "mpesa", tenderSetBy: ACTOR});
  assert.deepEqual(recorded.auditData, {
    eventType: "sale_tender_recorded",
    tenantId: TENANT,
    saleId: SALE,
    tender: "mpesa",
    businessDate: "2026-07-30",
    actorUid: ACTOR,
    requestId: REQUEST,
  });
  // The day the sale was filed under, which across midnight is the shift's day
  // rather than the calendar's - so a night's correction re-runs the night.
  assert.deepEqual(recorded.dirtyData, {
    tenantId: TENANT,
    businessDate: "2026-07-30",
    status: "dirty",
    revision: 1,
    dirtyReason: "tender_recorded",
  });
});

test("an explicit null is still a silence that can be answered", () => {
  // `saleTenderBucket` reads a stored null and a missing key as the same
  // `unrecorded`, so refusing one and not the other would be a distinction no
  // reader of the sale makes.
  const recorded = plan({
    sale: {soldById: ACTOR, tender: null, businessDate: "2026-07-30"},
  });

  assert.equal(recorded.saleData.tender, "mpesa");
});

test("a mis-tap can be corrected while the shift is still open", () => {
  // **The drawer has not been counted yet.** A cashier who taps Cash for an
  // M-Pesa customer notices at the counter, inside the shift the drawer is
  // still being filled for - and with no way back the split stays wrong for
  // ever, silently, because reconciliation agrees on the total alone.
  const corrected = plan({
    sale: {soldById: ACTOR, tender: "cash", businessDate: "2026-07-30"},
  });

  assert.equal(corrected.replaces, true);
  assert.equal(corrected.saleData.tender, "mpesa");
  assert.equal(corrected.auditData.eventType, "sale_tender_changed");
  // What it was, so the audit answers the only question anybody asks of a
  // corrected figure.
  assert.equal(corrected.auditData.previousTender, "cash");
});

test("a recorded tender is fixed once its shift is counted off", () => {
  // **Past the close it stops being a typo fix.** The drawer was counted
  // against this split, so moving it reaches back into settled books -
  // `tenderFiguresMoved` would reopen a difference the owner already dismissed.
  assert.equal(
    refusalCode(() => plan({
      sale: {soldById: ACTOR, tender: "cash", businessDate: "2026-07-30"},
      shiftClosed: true,
    })),
    "failed-precondition"
  );
});

test("a blank is still fillable after the shift is counted off", () => {
  // Filling a blank adds a figure where the count had none, rather than moving
  // one it was measured against, so the close does not bound it.
  const filled = plan({
    sale: {soldById: ACTOR, businessDate: "2026-07-30"},
    shiftClosed: true,
  });

  assert.equal(filled.replaces, false);
  assert.equal(filled.saleData.tender, "mpesa");
});

test("recording the method it already names is refused", () => {
  assert.equal(
    refusalCode(() => plan({
      sale: {soldById: ACTOR, tender: "mpesa", businessDate: "2026-07-30"},
    })),
    "failed-precondition"
  );
});

test("only the cashier who sold it may answer for it", () => {
  // A manager completing somebody else's sale would be guessing, and would be
  // the after-the-fact edit the one-way rule exists to refuse.
  assert.equal(
    refusalCode(() => plan({actorUid: "user-manager"})),
    "permission-denied"
  );
});

test("a sale with no usable business date has nothing to re-run", () => {
  for (const businessDate of [undefined, "", 20260730]) {
    assert.equal(
      refusalCode(() => plan({sale: {soldById: ACTOR, businessDate}})),
      "failed-precondition",
      `businessDate: ${String(businessDate)}`
    );
  }
});
