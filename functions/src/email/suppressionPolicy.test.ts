import assert from "node:assert/strict";
import test from "node:test";
import {assertSuppressionClearAllowed} from "./suppressionPolicy";

test("complaint clearing requires its exact confirmation and evidence", () => {
  const complaint = [{category: "spam_complaint" as const, status: "active" as const}];
  assert.throws(() => assertSuppressionClearAllowed(
    complaint,
    "address_independently_verified",
    "SUPPORT-123"
  ));
  assert.throws(() => assertSuppressionClearAllowed(
    complaint,
    "clear_spam_complaint",
    undefined
  ));
  assert.doesNotThrow(() => assertSuppressionClearAllowed(
    complaint,
    "clear_spam_complaint",
    "SUPPORT-123"
  ));
});

test("bounce clearing requires correction or independent verification", () => {
  const bounce = [{category: "hard_bounce" as const, status: "active" as const}];
  assert.throws(() => assertSuppressionClearAllowed(bounce, undefined, undefined));
  assert.doesNotThrow(() => assertSuppressionClearAllowed(
    bounce,
    "address_corrected",
    undefined
  ));
  assert.doesNotThrow(() => assertSuppressionClearAllowed([], undefined, undefined));
});
