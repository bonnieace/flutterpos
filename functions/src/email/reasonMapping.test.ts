import assert from "node:assert/strict";
import test from "node:test";
import {
  BREVO_REASON_MAPPING_VERSION,
  classifyBrevoEvent,
} from "./reasonMapping";

test("permanent Brevo events always create the expected suppression class", () => {
  assert.deepEqual(classifyBrevoEvent("hard_bounce", "opaque provider prose"), {
    mappingVersion: BREVO_REASON_MAPPING_VERSION,
    eventType: "hard_bounce",
    normalizedReasonCode: "unknown",
    reasonClass: "hard_bounce",
    disposition: "permanent_failure",
    suppressionCategory: "hard_bounce",
  });
  assert.equal(
    classifyBrevoEvent("invalid_email", "recipient not found")?.suppressionCategory,
    "invalid_recipient"
  );
  assert.equal(
    classifyBrevoEvent("spam", "complaint")?.suppressionCategory,
    "spam_complaint"
  );
});

test("blocked events are permanent only for an exact versioned reason mapping", () => {
  assert.equal(
    classifyBrevoEvent("blocked", "prior hard bounce")?.disposition,
    "permanent_failure"
  );
  assert.equal(
    classifyBrevoEvent("blocked", "recipient not found")?.suppressionCategory,
    "invalid_recipient"
  );
  assert.equal(
    classifyBrevoEvent("blocked", "mailbox full")?.disposition,
    "temporary_failure"
  );
  assert.equal(
    classifyBrevoEvent("blocked", "looks permanent to a human")?.disposition,
    "temporary_failure"
  );
  assert.equal(
    classifyBrevoEvent("blocked", undefined)?.reasonClass,
    "unknown_temporary"
  );
});

test("temporary delivery reasons remain finite and do not retain provider prose", () => {
  assert.equal(
    classifyBrevoEvent("soft_bounce", "mailbox full")?.reasonClass,
    "temporary_mailbox"
  );
  assert.equal(
    classifyBrevoEvent("deferred", "rate limit")?.reasonClass,
    "temporary_rate_limit"
  );
  assert.equal(
    classifyBrevoEvent("soft_bounce", "Customer Name was unavailable")
      ?.normalizedReasonCode,
    "unknown"
  );
  assert.equal(
    classifyBrevoEvent("error", "connection failure")?.disposition,
    "temporary_failure"
  );
});
