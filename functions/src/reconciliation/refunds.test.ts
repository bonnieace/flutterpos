import assert from "node:assert/strict";
import test from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import {FakeFirestore} from "../testing/fakeFirestore";
import {registerReturnRefundReceipt} from "./jobs";
import {SaleLike} from "../operations/domain";
import {aggregateDailySales, readReturnRefund, ReturnRefund} from "./model";

/**
 * Money handed back over the counter for a return, and the drawer it left.
 *
 * A return is valued against its sale and nets the sale's day, whatever shift
 * it lands on. The refund is a different fact: cash, M-Pesa or card that left
 * one particular drawer, on the day that drawer was trading. These pin that it
 * comes off the shift that paid it, in the method it was paid by, and nowhere
 * else.
 */

const REFUND = {
  refundMinor: 100000,
  refundTender: "cash",
  refundShiftId: "shift-b",
  refundBusinessDate: "2026-10-09",
};

test("a return names its refund only when all four fields add up", () => {
  assert.deepEqual(readReturnRefund(REFUND), {
    amountMinor: 100000,
    tender: "cash",
    shiftId: "shift-b",
    businessDate: "2026-10-09",
  });
  // Every return written before refunds existed has none, and is no refund.
  assert.equal(readReturnRefund({saleId: "co-1"}), null);
  for (const [name, broken] of [
    ["no amount", {...REFUND, refundMinor: undefined}],
    ["nothing handed back", {...REFUND, refundMinor: 0}],
    ["a fraction", {...REFUND, refundMinor: 10.5}],
    ["a method nobody models", {...REFUND, refundTender: "credit"}],
    ["no shift", {...REFUND, refundShiftId: ""}],
    ["no day", {...REFUND, refundBusinessDate: "yesterday"}],
  ] as const) {
    assert.equal(readReturnRefund(broken), null, name);
  }
});

test("a refund comes out of the shift that paid it, in its method", () => {
  // The device run of 2026-10-08: KES 4000 cash, a credit sale paid 400 by
  // M-Pesa, and KES 1000 handed back in cash for a returned bottle.
  const result = aggregateDailySales(
    "2026-10-08",
    [
      {shiftId: "shift-a", total: 4000, totalMinor: 400000, tender: "cash"},
      {
        shiftId: "shift-a",
        total: 1000,
        totalMinor: 100000,
        tender: "credit",
        customerId: `cu_${"0123456789abcdef".repeat(2)}01234567`,
        creditOwedMinor: 60000,
        creditPaidTender: "mpesa",
      },
      {shiftId: "shift-a", total: 1000, totalMinor: 100000, tender: "card"},
    ] as SaleLike[],
    200,
    undefined,
    0,
    [],
    [{amountMinor: 100000, tender: "cash", shiftId: "shift-a", businessDate: "2026-10-08"}]
  );

  const [shift] = result.shifts;
  // Sales stay gross: the close states them so, and the verifier compares them.
  assert.equal(shift.sales, 6000);
  assert.equal(shift.transactions, 3);
  // Cash: 4000 sold less 1000 handed back. The 600 still owed is in no drawer.
  assert.deepEqual(shift.tenders, {
    cashMinor: 300000,
    mpesaMinor: 40000,
    cardMinor: 100000,
    unattributedMinor: 0,
  });
});

test("a refund paid on another shift leaves the sale's shift alone", () => {
  const result = aggregateDailySales(
    "2026-10-09",
    [{shiftId: "shift-a", total: 1000, totalMinor: 100000, tender: "mpesa"}],
    200,
    undefined,
    0,
    [],
    [{amountMinor: 50000, tender: "cash", shiftId: "shift-b", businessDate: "2026-10-09"}]
  );

  const [sold, refunded] = result.shifts;
  assert.equal(sold.shiftId, "shift-a");
  assert.equal(sold.tenders.mpesaMinor, 100000);
  assert.equal(sold.tenders.cashMinor, 0);
  // A shift that only paid a refund is still expected to be down by it - out
  // of its float, which the verifier adds back.
  assert.equal(refunded.shiftId, "shift-b");
  assert.equal(refunded.sales, 0);
  assert.equal(refunded.transactions, 0);
  assert.equal(refunded.tenders.cashMinor, -50000);
});

test("refunds dated for another day, or malformed, move nothing", () => {
  const result = aggregateDailySales(
    "2026-10-09",
    [{shiftId: "shift-a", total: 10, totalMinor: 1000, tender: "cash"}],
    200,
    undefined,
    0,
    [],
    [
      {amountMinor: 500, tender: "cash", shiftId: "shift-a", businessDate: "2026-10-08"},
      {amountMinor: -500, tender: "cash", shiftId: "shift-a", businessDate: "2026-10-09"},
      // What a stored document could hold, whatever the type says.
      {amountMinor: 500, tender: "cheque", shiftId: "shift-a", businessDate: "2026-10-09"},
    ] as unknown as ReturnRefund[]
  );
  assert.equal(result.shifts.length, 1);
  assert.equal(result.shifts[0].tenders.cashMinor, 1000);
});

test("a refund marks the day it was paid on, once", async () => {
  const fake = new FakeFirestore();
  const input = {
    tenantId: "shop",
    returnId: "rt-1",
    businessDate: "2026-10-09",
    receivedAt: Timestamp.now(),
    deferReconciliation: true,
  };
  await registerReturnRefundReceipt(fake.asFirestore(), input);
  await registerReturnRefundReceipt(fake.asFirestore(), input);

  const dirty = await fake.asFirestore()
    .doc("tenants/shop/reconciliation_dirty_days/2026-10-09").get();
  assert.equal(dirty.get("status"), "dirty");
  assert.equal(dirty.get("revision"), 1);
  assert.equal(dirty.get("dirtyReason"), "return_refund");
});
