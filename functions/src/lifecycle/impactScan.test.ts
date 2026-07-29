import assert from "node:assert/strict";
import test from "node:test";
import {buildTenantSafeGlobalStatusAudit} from "./impactScan";

test("tenant-readable global-status audit omits operator and subject details", () => {
  const audit = buildTenantSafeGlobalStatusAudit({
    tenantId: "tenant-a",
    type: "tenant_owner_unavailable",
  }, "opaque-correlation");

  assert.equal(audit.eventType, "tenant_owner_unavailable");
  assert.equal(audit.actorType, "platform");
  assert.equal(audit.operationReference, "opaque-correlation");
  assert.equal("uid" in audit, false);
  assert.equal("requestedBy" in audit, false);
  assert.equal("reason" in audit, false);
  assert.equal("requestId" in audit, false);
});
