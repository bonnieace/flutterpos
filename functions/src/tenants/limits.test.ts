import assert from "node:assert/strict";
import test from "node:test";
import {
  DEFAULT_TENANT_LIMITS,
  findTenantLimitViolation,
  resolveTenantLimits,
} from "./limits";

test("tenant limits use frozen defaults when configuration is absent or invalid", () => {
  assert.deepEqual(resolveTenantLimits(undefined), DEFAULT_TENANT_LIMITS);
  assert.deepEqual(resolveTenantLimits({
    maxPendingTenantsPerUser: -1,
    maxTenantRequestsPer24Hours: "10",
    maxOwnedActiveTenantsPerUser: 10001,
  }), DEFAULT_TENANT_LIMITS);
});

test("tenant limits accept explicit non-negative platform configuration", () => {
  assert.deepEqual(resolveTenantLimits({
    maxPendingTenantsPerUser: 4,
    maxTenantRequestsPer24Hours: 8,
    maxOwnedActiveTenantsPerUser: 30,
  }), {
    maxPendingTenantsPerUser: 4,
    maxTenantRequestsPer24Hours: 8,
    maxOwnedActiveTenantsPerUser: 30,
  });
});

test("tenant request limits reject counts at each authoritative threshold", () => {
  assert.equal(findTenantLimitViolation({
    pendingTenants: 3,
    requestsInLast24Hours: 0,
    ownedActiveTenants: 0,
  }, {...DEFAULT_TENANT_LIMITS}), "max_pending_tenants");
  assert.equal(findTenantLimitViolation({
    pendingTenants: 0,
    requestsInLast24Hours: 5,
    ownedActiveTenants: 0,
  }, {...DEFAULT_TENANT_LIMITS}), "max_requests_per_24_hours");
  assert.equal(findTenantLimitViolation({
    pendingTenants: 0,
    requestsInLast24Hours: 0,
    ownedActiveTenants: 25,
  }, {...DEFAULT_TENANT_LIMITS}), "max_owned_active_tenants");
  assert.equal(findTenantLimitViolation({
    pendingTenants: 2,
    requestsInLast24Hours: 4,
    ownedActiveTenants: 24,
  }, {...DEFAULT_TENANT_LIMITS}), undefined);
});
