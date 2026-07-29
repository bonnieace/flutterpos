import assert from "node:assert/strict";
import test from "node:test";
import {
  GlobalUserStatusInput,
  GlobalUserStatusOperation,
} from "./globalStatusCore";
import {
  parseRetryableGlobalStatusOperation,
  retryGlobalUserStatusOperationsCore,
  RetryableGlobalStatusWork,
} from "./retryWorker";

function operation(
  input: GlobalUserStatusInput,
  status: "completed" | "partially_failed"
): GlobalUserStatusOperation {
  return {
    ...input,
    firestoreStatus: "completed",
    impactStatus: input.targetStatus === "disabled" ? "completed" : "not_applicable",
    authStatus: "completed",
    claimStatus: input.targetStatus === "disabled" ? "completed" : "not_restored",
    tokenStatus: "completed",
    status,
    attemptCount: 2,
    affectedTenantIds: [],
    scannedTenantIds: [],
  };
}

test("private retry core resumes bounded operations and reports outcomes", async () => {
  const inputs: RetryableGlobalStatusWork[] = [
    {
      input: {
        uid: "user-a",
        targetStatus: "disabled",
        requestedBy: "platform-a",
        reason: "security",
        requestId: "request-aaaa",
      },
      retryLeaseOwner: "lease-a",
    },
    {
      input: {
        uid: "user-b",
        targetStatus: "active",
        requestedBy: "platform-a",
        reason: "appeal approved",
        requestId: "request-bbbb",
      },
      retryLeaseOwner: "lease-b",
    },
  ];
  const limits: number[] = [];
  const summary = await retryGlobalUserStatusOperationsCore({
    async listRetryable(limit) {
      limits.push(limit);
      return inputs;
    },
    async resume(work) {
      return operation(
        work.input,
        work.input.uid === "user-a" ? "completed" : "partially_failed"
      );
    },
  }, 10);

  assert.deepEqual(limits, [10]);
  assert.deepEqual(summary, {attempted: 2, completed: 1, partiallyFailed: 1});
});

function storedOperation(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    uid: "target-user",
    targetStatus: "disabled",
    requestedBy: "platform-user",
    reason: "security incident",
    requestId: "request-1234",
    status: "partially_failed",
    attemptCount: 2,
    firestoreStatus: "completed",
    impactStatus: "completed",
    authStatus: "completed",
    claimStatus: "pending",
    tokenStatus: "pending",
    ...overrides,
  };
}

test("retry parser accepts only a phase-consistent stored operation", () => {
  assert.deepEqual(
    parseRetryableGlobalStatusOperation("request-1234", storedOperation()),
    {
      uid: "target-user",
      targetStatus: "disabled",
      requestedBy: "platform-user",
      reason: "security incident",
      requestId: "request-1234",
    }
  );
  assert.throws(
    () => parseRetryableGlobalStatusOperation(
      "request-1234",
      storedOperation({targetStatus: "enable_everything"})
    ),
    /invalid_targetStatus/
  );
  assert.throws(
    () => parseRetryableGlobalStatusOperation(
      "request-1234",
      storedOperation({requestId: "different-request"})
    ),
    /request_id_mismatch/
  );
});

test("retry parser rejects activation records with disable-only phases", () => {
  assert.throws(
    () => parseRetryableGlobalStatusOperation("request-1234", storedOperation({
      targetStatus: "active",
      impactStatus: "completed",
      claimStatus: "completed",
    })),
    /invalid_activation_phases/
  );
  assert.doesNotThrow(() => parseRetryableGlobalStatusOperation(
    "request-1234",
    storedOperation({
      targetStatus: "active",
      firestoreStatus: "pending",
      impactStatus: "not_applicable",
      claimStatus: "not_restored",
    })
  ));
});
