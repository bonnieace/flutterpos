import assert from "node:assert/strict";
import test from "node:test";
import {
  evaluateTenantAdministrativeImpact,
  globalStatusRetryDelayMilliseconds,
  GlobalUserStatusImpact,
  GlobalUserStatusInput,
  GlobalUserStatusOperation,
  GlobalUserStatusSagaAdapter,
  isSameGlobalStatusRequest,
  runGlobalUserStatusSaga,
  withoutPlatformRole,
} from "./globalStatusCore";

class FakeSagaAdapter implements GlobalUserStatusSagaAdapter {
  readonly actions: string[] = [];
  failAction?: string;
  impact: GlobalUserStatusImpact = {scannedTenantIds: [], alerts: []};
  operation?: GlobalUserStatusOperation;

  async prepare(input: GlobalUserStatusInput): Promise<GlobalUserStatusOperation> {
    if (!this.operation) {
      this.actions.push(input.targetStatus === "disabled" ? "root:disable" : "operation:prepare");
      this.operation = {
        ...input,
        firestoreStatus: input.targetStatus === "disabled" ? "completed" : "pending",
        impactStatus: input.targetStatus === "disabled" ? "pending" : "not_applicable",
        authStatus: "pending",
        claimStatus: input.targetStatus === "disabled" ? "pending" : "not_restored",
        tokenStatus: "pending",
        status: "pending",
        attemptCount: 1,
        affectedTenantIds: [],
        scannedTenantIds: [],
      };
    } else {
      this.actions.push("operation:resume");
      this.operation.status = "pending";
      this.operation.attemptCount += 1;
    }
    return this.operation;
  }

  async processDisableImpact(): Promise<GlobalUserStatusImpact> {
    await this.action("impact:scan");
    await this.action("alerts:write");
    return this.impact;
  }

  async setAuthDisabled(_uid: string, disabled: boolean): Promise<void> {
    await this.action(disabled ? "auth:disable" : "auth:enable");
  }

  async removePlatformClaim(): Promise<void> {
    await this.action("claims:remove");
  }

  async revokeRefreshTokens(): Promise<number> {
    await this.action("tokens:revoke");
    return 1_000;
  }

  async activateRoot(
    _uid: string,
    _requestId: string,
    authValidAfterSeconds: number
  ): Promise<void> {
    assert.equal(authValidAfterSeconds, 1_000);
    await this.action("root:activate");
  }

  async recordSteps(
    _requestId: string,
    steps: Partial<GlobalUserStatusOperation>
  ): Promise<void> {
    if (!this.operation) throw new Error("missing operation");
    Object.assign(this.operation, steps);
  }

  async complete(operation: GlobalUserStatusOperation): Promise<GlobalUserStatusOperation> {
    await this.action("audit:complete");
    operation.status = "completed";
    return operation;
  }

  async recordFailure(
    operation: GlobalUserStatusOperation,
    errorCode: string
  ): Promise<GlobalUserStatusOperation> {
    this.actions.push(`failure:${errorCode}`);
    operation.status = "partially_failed";
    operation.lastErrorCode = errorCode;
    return operation;
  }

  private async action(name: string): Promise<void> {
    this.actions.push(name);
    if (this.failAction === name) {
      this.failAction = undefined;
      throw Object.assign(new Error(name), {code: `test/${name}`});
    }
  }
}

function input(targetStatus: "active" | "disabled"): GlobalUserStatusInput {
  return {
    uid: "target-user",
    targetStatus,
    requestedBy: "platform-user",
    reason: "security review",
    requestId: "request-1234",
  };
}

test("disable saga commits root first, alerts before Auth, then removes claims and tokens", async () => {
  const adapter = new FakeSagaAdapter();
  adapter.impact = {
    scannedTenantIds: ["tenant-a"],
    alerts: [{tenantId: "tenant-a", type: "tenant_owner_unavailable"}],
  };

  const result = await runGlobalUserStatusSaga(adapter, input("disabled"));

  assert.equal(result.status, "completed");
  assert.deepEqual(adapter.actions, [
    "root:disable",
    "impact:scan",
    "alerts:write",
    "auth:disable",
    "claims:remove",
    "tokens:revoke",
    "audit:complete",
  ]);
  assert.deepEqual(result.affectedTenantIds, ["tenant-a"]);
});

test("partially failed disable resumes after durable completed phases", async () => {
  const adapter = new FakeSagaAdapter();
  adapter.failAction = "claims:remove";

  const failed = await runGlobalUserStatusSaga(adapter, input("disabled"));
  assert.equal(failed.status, "partially_failed");
  assert.equal(failed.authStatus, "completed");
  assert.equal(failed.claimStatus, "pending");

  adapter.actions.length = 0;
  const resumed = await runGlobalUserStatusSaga(adapter, input("disabled"));
  assert.equal(resumed.status, "completed");
  assert.deepEqual(adapter.actions, [
    "operation:resume",
    "claims:remove",
    "tokens:revoke",
    "audit:complete",
  ]);
  assert.equal(resumed.attemptCount, 2);
});

test("a disable scan failure remains partial before any Auth mutation", async () => {
  const adapter = new FakeSagaAdapter();
  adapter.failAction = "impact:scan";

  const failed = await runGlobalUserStatusSaga(adapter, input("disabled"));

  assert.equal(failed.status, "partially_failed");
  assert.equal(failed.authStatus, "pending");
  assert.deepEqual(adapter.actions, [
    "root:disable",
    "impact:scan",
    "failure:test/impact:scan",
  ]);
});

test("reactivation revokes sessions before root activation and never restores claims", async () => {
  const adapter = new FakeSagaAdapter();
  const result = await runGlobalUserStatusSaga(adapter, input("active"));

  assert.equal(result.status, "completed");
  assert.equal(result.claimStatus, "not_restored");
  assert.deepEqual(adapter.actions, [
    "operation:prepare",
    "auth:enable",
    "tokens:revoke",
    "root:activate",
    "audit:complete",
  ]);
  assert.equal(result.authValidAfterSeconds, 1_000);
  assert.equal(adapter.actions.includes("claims:restore"), false);
});

test("impact evaluation distinguishes owner loss from last-admin loss", () => {
  assert.deepEqual(evaluateTenantAdministrativeImpact({
    tenantId: "tenant-owner",
    tenantStatus: "active",
    ownerUid: "target-user",
    targetUid: "target-user",
    remainingPrincipals: [],
  }), {
    tenantId: "tenant-owner",
    type: "tenant_owner_unavailable",
  });

  assert.deepEqual(evaluateTenantAdministrativeImpact({
    tenantId: "tenant-admin",
    tenantStatus: "suspended",
    ownerUid: "missing-owner",
    targetUid: "target-user",
    targetStaffStatus: "active",
    targetStaffRole: "admin",
    remainingPrincipals: [{
      uid: "inactive-admin",
      staffUid: "inactive-admin",
      role: "admin",
      staffStatus: "active",
      globalStatus: "disabled",
      accountType: "tenant_user",
    }],
  }), {
    tenantId: "tenant-admin",
    type: "no_active_administrator",
  });
});

test("an active canonical administrator prevents the no-admin alert", () => {
  const alert = evaluateTenantAdministrativeImpact({
    tenantId: "tenant-a",
    tenantStatus: "active",
    ownerUid: "owner-user",
    targetUid: "target-user",
    targetStaffStatus: "active",
    targetStaffRole: "admin",
    remainingPrincipals: [{
      uid: "owner-user",
      staffUid: "owner-user",
      role: "owner",
      staffStatus: "active",
      globalStatus: "active",
      accountType: "tenant_user",
    }],
  });
  assert.equal(alert, undefined);
});

test("claim removal preserves unrelated custom claims", () => {
  assert.deepEqual(withoutPlatformRole({
    platformRole: "superAdmin",
    supportTier: "senior",
    canImpersonate: false,
  }), {
    supportTier: "senior",
    canImpersonate: false,
  });
});

test("global request idempotency requires the entire original identity and payload", () => {
  const baseline = input("disabled");
  assert.equal(isSameGlobalStatusRequest(baseline, {...baseline}), true);
  assert.equal(isSameGlobalStatusRequest(baseline, {
    ...baseline,
    reason: "different reason",
  }), false);
  assert.equal(isSameGlobalStatusRequest(baseline, {
    ...baseline,
    targetStatus: "active",
  }), false);
  assert.equal(isSameGlobalStatusRequest(baseline, {
    ...baseline,
    requestedBy: "different-platform-user",
  }), false);
});

test("archived and already-inactive memberships do not create new alerts", () => {
  assert.equal(evaluateTenantAdministrativeImpact({
    tenantId: "archived-tenant",
    tenantStatus: "archived",
    ownerUid: "target-user",
    targetUid: "target-user",
    remainingPrincipals: [],
  }), undefined);
  assert.equal(evaluateTenantAdministrativeImpact({
    tenantId: "inactive-membership",
    tenantStatus: "active",
    ownerUid: "other-owner",
    targetUid: "target-user",
    targetStaffStatus: "inactive",
    targetStaffRole: "admin",
    remainingPrincipals: [],
  }), undefined);
});

test("retry delay backs off exponentially and caps at six hours", () => {
  assert.equal(globalStatusRetryDelayMilliseconds(1), 5 * 60 * 1000);
  assert.equal(globalStatusRetryDelayMilliseconds(2), 10 * 60 * 1000);
  assert.equal(globalStatusRetryDelayMilliseconds(8), 6 * 60 * 60 * 1000);
  assert.equal(globalStatusRetryDelayMilliseconds(100), 6 * 60 * 60 * 1000);
  assert.equal(globalStatusRetryDelayMilliseconds(Number.NaN), 5 * 60 * 1000);
});
