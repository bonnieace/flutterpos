import assert from "node:assert/strict";
import test from "node:test";
import {
  isEligiblePlatformNotificationRecipient,
  redactedPlatformAlert,
} from "./platformAlert";

test("platform alert projection excludes sensitive lifecycle subject and reason", () => {
  const redacted = redactedPlatformAlert("alert-1", {
    severity: "critical",
    type: "tenant_owner_unavailable",
    uid: "sensitive-target-uid",
    reason: "sensitive operator reason",
    tenantId: "tenant-1",
  });
  assert.deepEqual(redacted, {
    alertId: "alert-1",
    alertType: "tenant_owner_unavailable",
    severity: "critical",
  });
  assert.equal(JSON.stringify(redacted).includes("sensitive-target-uid"), false);
  assert.equal(JSON.stringify(redacted).includes("sensitive operator reason"), false);
});

test("operator notification eligibility requires canonical root and Auth claim", () => {
  const root = {accountType: "platform_admin" as const, globalStatus: "active" as const};
  const auth = {
    disabled: false,
    customClaims: {platformRole: "superAdmin"},
    email: "operator@example.com",
  };
  assert.equal(isEligiblePlatformNotificationRecipient(root, auth), true);
  assert.equal(isEligiblePlatformNotificationRecipient(
    {...root, globalStatus: "disabled"}, auth
  ), false);
  assert.equal(isEligiblePlatformNotificationRecipient(
    root, {...auth, customClaims: {}}
  ), false);
  assert.equal(isEligiblePlatformNotificationRecipient(
    {...root, identityTransition: "cleanup_pending"}, auth
  ), false);
});

test("unknown alert types fail closed", () => {
  assert.equal(redactedPlatformAlert("alert-1", {
    severity: "critical",
    type: "raw_unreviewed_alert",
  }), undefined);
});
