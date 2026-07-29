import assert from "node:assert/strict";
import test from "node:test";
import {EmailProviderError} from "./contracts";
import {
  PasswordResetProcessingDependencies,
  preparePasswordResetRequest,
  processPasswordResetTask,
} from "./passwordReset";
import {parseRecipientHmacKeyring, RecipientHash} from "./recipientHash";

const KEYRING = parseRecipientHmacKeyring(JSON.stringify({
  currentVersion: "v1",
  keys: {
    v1: "password-reset-recipient-test-key-longer-than-thirty-two-bytes",
  },
}));

function harness(options: {
  identity?: {uid: string; email: string; disabled: boolean};
  suppressed?: boolean;
  providerError?: Error;
  rootEligible?: boolean;
} = {}): {
  dependencies: PasswordResetProcessingDependencies;
  calls: string[];
} {
  const calls: string[] = [];
  const dependencies: PasswordResetProcessingDependencies = {
    keyring: KEYRING,
    async isRootEligible(uid) {
      calls.push(`root:${uid}`);
      return options.rootEligible ?? true;
    },
    identities: {
      async findByEmail(email) {
        calls.push(`identity:${email}`);
        return options.identity;
      },
      async createActionLink(email) {
        calls.push(`link:${email}`);
        return "https://auth.example.test/reset?oobCode=secret";
      },
    },
    provider: {
      async send(message) {
        calls.push(`provider:${message.recipient}`);
        if (options.providerError) throw options.providerError;
        return {provider: "fake", providerMessageId: "message-1"};
      },
    },
    async isSuppressed(hashes: readonly RecipientHash[]) {
      calls.push(`suppressions:${hashes.length}`);
      return options.suppressed ?? false;
    },
    async recordSuppressed(_task, identity) {
      calls.push(`record-suppressed:${identity.uid}`);
    },
    async beginDelivery(_task, identity) {
      calls.push(`begin:${identity.uid}`);
      return {leaseId: "lease-1", attemptNumber: 1};
    },
    async markSent(_task, _attempt, provider, messageId) {
      calls.push(`sent:${provider}:${messageId}`);
    },
    async markFailure(_task, _attempt, code, retryable) {
      calls.push(`failure:${code}:${retryable}`);
    },
  };
  return {dependencies, calls};
}

function task(): NonNullable<ReturnType<typeof preparePasswordResetRequest>["task"]> {
  const prepared = preparePasswordResetRequest({
    email: "Person@Example.com",
    requestId: "request-12345",
  }, KEYRING);
  assert.ok(prepared.task);
  return prepared.task;
}

test("public request preparation is enumeration resistant for malformed email", () => {
  const prepared = preparePasswordResetRequest({
    email: "not-an-address",
    requestId: "request-12345",
  }, KEYRING);
  assert.deepEqual(prepared, {response: {accepted: true}});
});

test("worker does not create a delivery or call provider for an unknown identity", async () => {
  const {dependencies, calls} = harness();
  assert.equal(await processPasswordResetTask(task(), dependencies), "ignored");
  assert.deepEqual(calls, ["identity:person@example.com"]);
});

test("worker rechecks current Auth email HMAC before any delivery", async () => {
  const {dependencies, calls} = harness({
    identity: {uid: "user-1", email: "changed@example.com", disabled: false},
  });
  assert.equal(await processPasswordResetTask(task(), dependencies), "ignored");
  assert.equal(calls.some((call) => call.startsWith("provider:")), false);
  assert.equal(calls.some((call) => call.startsWith("begin:")), false);
});

test("active suppression records generic unavailability without creating a link", async () => {
  const {dependencies, calls} = harness({
    identity: {uid: "user-1", email: "person@example.com", disabled: false},
    suppressed: true,
  });
  assert.equal(await processPasswordResetTask(task(), dependencies), "suppressed");
  assert.deepEqual(calls, [
    "identity:person@example.com",
    "root:user-1",
    "suppressions:1",
    "record-suppressed:user-1",
  ]);
});

test("eligible reset generates and sends the action link only in memory", async () => {
  const {dependencies, calls} = harness({
    identity: {uid: "user-1", email: "person@example.com", disabled: false},
  });
  assert.equal(await processPasswordResetTask(task(), dependencies), "sent");
  assert.deepEqual(calls, [
    "identity:person@example.com",
    "root:user-1",
    "suppressions:1",
    "begin:user-1",
    "link:person@example.com",
    "provider:person@example.com",
    "sent:fake:message-1",
  ]);
});

test("retryable provider errors update durable state and fail the task", async () => {
  const {dependencies, calls} = harness({
    identity: {uid: "user-1", email: "person@example.com", disabled: false},
    providerError: new EmailProviderError("provider_http_429", true),
  });
  await assert.rejects(processPasswordResetTask(task(), dependencies));
  assert.equal(calls.includes("failure:provider_http_429:true"), true);
});

test("missing or globally disabled canonical root prevents link and send", async () => {
  const {dependencies, calls} = harness({
    identity: {uid: "user-1", email: "person@example.com", disabled: false},
    rootEligible: false,
  });
  assert.equal(await processPasswordResetTask(task(), dependencies), "ignored");
  assert.deepEqual(calls, ["identity:person@example.com", "root:user-1"]);
});
