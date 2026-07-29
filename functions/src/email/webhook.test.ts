import assert from "node:assert/strict";
import test from "node:test";
import {
  authenticateEmailWebhook,
  EMAIL_WEBHOOK_PAYLOAD_SCHEMA_VERSION,
  normalizeBrevoWebhook,
  providerEventDecision,
  shouldApplySuppressionEvent,
} from "./webhook";
import {parseRecipientHmacKeyring} from "./recipientHash";

const KEYRING = parseRecipientHmacKeyring(JSON.stringify({
  currentVersion: "v2",
  keys: {
    v2: "webhook-current-secret-that-is-longer-than-thirty-two-bytes",
    v1: "webhook-previous-secret-that-is-longer-than-thirty-two-bytes",
  },
}));

test("authenticated webhook accepts bearer or dedicated secret headers", () => {
  const secret = "webhook-authentication-secret-at-least-thirty-two-bytes";
  assert.equal(authenticateEmailWebhook(`Bearer ${secret}`, undefined, secret), true);
  assert.equal(authenticateEmailWebhook(undefined, secret, secret), true);
  assert.equal(authenticateEmailWebhook("Bearer wrong", undefined, secret), false);
  assert.equal(authenticateEmailWebhook(undefined, undefined, secret), false);
});

test("webhook normalization emits only the finite privacy schema", () => {
  const now = Date.UTC(2026, 6, 29, 12, 0, 0);
  const normalized = normalizeBrevoWebhook({
    event: "blocked",
    email: " Person@Example.com ",
    "message-id": "message-123",
    ts: now / 1000,
    reason: "Customer Person is definitely blocked forever",
    rawDebug: {password: "must-never-survive"},
  }, KEYRING, now);

  assert.ok(normalized);
  assert.equal(normalized.eventType, "blocked");
  assert.equal(normalized.normalizedReasonCode, "unknown");
  assert.equal(normalized.classification.disposition, "temporary_failure");
  assert.equal(normalized.payloadSchemaVersion, EMAIL_WEBHOOK_PAYLOAD_SCHEMA_VERSION);
  assert.equal(JSON.stringify(normalized).includes("Person@Example.com"), false);
  assert.equal(JSON.stringify(normalized).includes("must-never-survive"), false);
  assert.deepEqual(Object.keys(normalized).sort(), [
    "classification",
    "documentId",
    "eventType",
    "normalizedReasonCode",
    "payloadSchemaVersion",
    "providerMessageId",
    "providerTimestampMilliseconds",
    "reasonMappingVersion",
    "recipientHash",
    "recipientHashKeyVersion",
  ]);
});

test("unparseable webhook input is rejected without a quarantine payload", () => {
  assert.equal(normalizeBrevoWebhook({
    event: "hard_bounce",
    email: "not-an-email",
    id: "message-1",
    ts: Date.now() / 1000,
  }, KEYRING), undefined);
});

test("provider events cannot regress terminal delivery state", () => {
  assert.deepEqual(providerEventDecision(
    "delivered",
    200,
    "temporary_failure",
    300
  ), {applyDisposition: false, updateLatestEvent: true});
  assert.deepEqual(providerEventDecision(
    "temporary_failure",
    300,
    "success",
    200
  ), {applyDisposition: true, updateLatestEvent: false});
  assert.equal(providerEventDecision(
    "delivered",
    300,
    "permanent_failure",
    200
  ).applyDisposition, true);
  assert.equal(providerEventDecision(
    "suppressed",
    100,
    "success",
    400
  ).applyDisposition, false);
});

test("cleared suppression ignores stale events and complaints remain strongest", () => {
  assert.equal(shouldApplySuppressionEvent(
    "cleared",
    "hard_bounce",
    100,
    300,
    "hard_bounce",
    200
  ), false);
  assert.equal(shouldApplySuppressionEvent(
    "cleared",
    "hard_bounce",
    100,
    300,
    "hard_bounce",
    400
  ), true);
  assert.equal(shouldApplySuppressionEvent(
    "active",
    "spam_complaint",
    100,
    undefined,
    "hard_bounce",
    400
  ), false);
});
