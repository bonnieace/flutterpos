import assert from "node:assert/strict";
import test from "node:test";
import {
  emptyRepairSummary,
  executeMembershipRepairTask,
  membershipRepairRunId,
  membershipRepairTaskId,
  mergeRepairSummaries,
  parseCanonicalStaffPath,
  parseMembershipMirrorPath,
  recordMirrorDecision,
  RepairTaskRuntime,
} from "./repairRun";

test("repair IDs and task IDs are deterministic and bounded", () => {
  const first = membershipRepairRunId("target_user", "source/user-a");
  const second = membershipRepairRunId("target_user", "source/user-a");
  const different = membershipRepairRunId("target_tenant", "source/user-a");
  assert.equal(first, second);
  assert.notEqual(first, different);
  assert.match(first, /^mr_[a-f0-9]{40}$/);
  assert.match(membershipRepairTaskId({runId: first, revision: 17}), /^mrt_[a-f0-9]{40}$/);
});
test("canonical and advisory paths are accepted only in their exact hierarchy", () => {
  assert.deepEqual(parseCanonicalStaffPath("tenants/tenant-a/staff/user-a"), {
    tenantId: "tenant-a",
    uid: "user-a",
  });
  assert.equal(
    parseCanonicalStaffPath("archives/tenant-a/staff/user-a"),
    undefined
  );
  assert.equal(
    parseCanonicalStaffPath("tenants/tenant-a/archive/x/staff/user-a"),
    undefined
  );
  assert.deepEqual(
    parseMembershipMirrorPath("users/user-a/tenant_memberships/tenant-a"),
    {uid: "user-a", tenantId: "tenant-a"}
  );
  assert.equal(
    parseMembershipMirrorPath("tenants/user-a/tenant_memberships/tenant-a"),
    undefined
  );
});

test("repair summaries distinguish create, update, delete, and invalid canonical data", () => {
  const page = emptyRepairSummary();
  recordMirrorDecision(page, {
    action: "upsert",
    tenantId: "tenant-a",
    issues: ["mirror_missing"],
    value: {
      tenantId: "tenant-a",
      tenantName: "Shop",
      tenantSlug: "shop",
      role: "admin",
      membershipStatus: "active",
      tenantStatus: "active",
      isOwner: false,
      mirrorVersion: 1,
    },
  }, false);
  recordMirrorDecision(page, {
    action: "delete",
    tenantId: "tenant-b",
    issues: ["invalid_owner_invariant"],
  }, true);

  const total = mergeRepairSummaries(emptyRepairSummary(), page);
  assert.equal(total.mirrorsCreated, 1);
  assert.equal(total.mirrorsDeleted, 1);
  assert.equal(total.invalidCanonicalDocuments, 1);
  assert.deepEqual(total.issueCounts, {
    mirror_missing: 1,
    invalid_owner_invariant: 1,
  });
});

test("the queue core enqueues continuations and records failures", async () => {
  const runId = membershipRepairRunId("target_user", "user-a");
  const enqueued: number[] = [];
  const failures: string[] = [];
  const runtime: RepairTaskRuntime = {
    async process(payload) {
      return {tasks: [{...payload, revision: payload.revision + 1}]};
    },
    async enqueue(payload) {
      enqueued.push(payload.revision);
    },
    async recordFailure(_payload, error) {
      failures.push((error as Error).message);
    },
  };
  await executeMembershipRepairTask(runtime, {runId, revision: 2});
  assert.deepEqual(enqueued, [3]);
  assert.deepEqual(failures, []);

  runtime.process = async () => {
    throw new Error("page failed");
  };
  await assert.rejects(
    executeMembershipRepairTask(runtime, {runId, revision: 3}),
    /page failed/
  );
  assert.deepEqual(failures, ["page failed"]);
});
