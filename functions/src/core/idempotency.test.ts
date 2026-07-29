import assert from "node:assert/strict";
import test from "node:test";
import {buildIdempotencyIdentity, fingerprintPayload} from "./idempotency";

test("payload fingerprints are stable across object key ordering", () => {
  assert.equal(
    fingerprintPayload({tenantId: "tenant-1", data: {b: 2, a: 1}}),
    fingerprintPayload({data: {a: 1, b: 2}, tenantId: "tenant-1"})
  );
});
test("idempotency identity is scoped to actor, operation, tenant, and request", () => {
  const baseline = buildIdempotencyIdentity("user-1", "inviteStaff", "tenant-1", "request-1");
  const variants = [
    buildIdempotencyIdentity("user-2", "inviteStaff", "tenant-1", "request-1"),
    buildIdempotencyIdentity("user-1", "setStaffStatus", "tenant-1", "request-1"),
    buildIdempotencyIdentity("user-1", "inviteStaff", "tenant-2", "request-1"),
    buildIdempotencyIdentity("user-1", "inviteStaff", "tenant-1", "request-2"),
    buildIdempotencyIdentity("user-1", "inviteStaff", undefined, "request-1"),
  ];

  for (const variant of variants) {
    assert.notEqual(variant.documentId, baseline.documentId);
  }
  assert.equal(baseline.scope, "tenant:tenant-1");
});
