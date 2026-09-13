import assert from "node:assert/strict";
import {test} from "node:test";
import {RECEIPT_NUMBER} from "./receipts";

/**
 * The receipt shape this callable will accept.
 *
 * **This file exists because the first version of that pattern was guessed.**
 * It expected a hyphenated date - `CT-1E6-2026-09-05-0004` - where
 * `formatCheckoutReceiptNumber` packs the day as `20260905`, so no receipt any
 * till has ever printed matched it. Every reprint answered `invalid-argument`,
 * and the screen turned that into "that sale is not in this business" about a
 * sale the operator was looking at.
 *
 * The authority is `checkoutReceiptNumberPattern` in `lib/checkout/
 * checkout_receipt.dart`; these cases are the ones that tell the two apart.
 */
test("accepts the receipts a till actually prints", () => {
  for (const receipt of [
    "CT-1E6-20260905-0004",
    "CT-000-20260101-0001",
    "CT-FFF-20261231-123456",
  ]) {
    assert.equal(RECEIPT_NUMBER.test(receipt), true, receipt);
  }
});

test("refuses the shapes that are not receipt numbers", () => {
  for (const receipt of [
    // The guess that caused the defect: the day is packed, never hyphenated.
    "CT-1E6-2026-09-05-0004",
    // The device code is upper-case hex, three characters, after `CT-`.
    "CT-1e6-20260905-0004",
    "CT-1E6G-20260905-0004",
    "XX-1E6-20260905-0004",
    // The sequence is four to six digits.
    "CT-1E6-20260905-004",
    "CT-1E6-20260905-1234567",
    // A document ID is not a receipt.
    "co-1788637383703-3358bf",
    "",
  ]) {
    assert.equal(RECEIPT_NUMBER.test(receipt), false, receipt);
  }
});
