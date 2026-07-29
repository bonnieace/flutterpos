import assert from "node:assert/strict";
import test from "node:test";
import {
  AccountVerificationDependencies,
  isRecentAuthTime,
  processAccountVerificationTask,
} from "./accountVerification";
import {hashRecipient, parseRecipientHmacKeyring} from "./recipientHash";

const KEYRING = parseRecipientHmacKeyring(JSON.stringify({
  currentVersion: "v1",
  keys: {v1: "account-verification-test-key-longer-than-thirty-two-bytes"},
}));
const RECIPIENT = hashRecipient("person@example.com", KEYRING);
const TASK = {
  deliveryId: "a".repeat(64),
  targetUid: "user-1",
  normalizedEmail: "person@example.com",
  recipientHash: RECIPIENT.recipientHash,
  recipientHashKeyVersion: RECIPIENT.keyVersion,
  requestAuthTime: 1_000,
};

function dependencies(identity: {
  uid: string;
  email: string;
  disabled: boolean;
  emailVerified: boolean;
} | undefined, rootEligible = true): {
  dependencies: AccountVerificationDependencies;
  calls: string[];
} {
  const calls: string[] = [];
  return {
    calls,
    dependencies: {
      keyring: KEYRING,
      provider: {
        async send(message) {
          calls.push(`send:${message.template}:${message.recipient}`);
          return {provider: "fake", providerMessageId: "message-1"};
        },
      },
      async findIdentity(uid) {
        calls.push(`identity:${uid}`);
        return identity;
      },
      async isRootEligible(uid, authTime) {
        calls.push(`root:${uid}:${authTime}`);
        return rootEligible;
      },
      async createActionLink(email) {
        calls.push(`link:${email}`);
        return "https://example.test/verify?oobCode=secret";
      },
      async isSuppressed() {
        calls.push("suppression");
        return false;
      },
      async recordSuppressed() {
        calls.push("record-suppressed");
      },
      async begin() {
        calls.push("begin");
        return {leaseId: "lease-1", attemptNumber: 1};
      },
      async sent() {
        calls.push("sent");
      },
      async failed() {
        calls.push("failed");
      },
    },
  };
}

test("account verification requires authentication no older than five minutes", () => {
  const now = Date.UTC(2026, 6, 29, 12, 0, 0);
  const seconds = Math.floor(now / 1000);
  assert.equal(isRecentAuthTime(seconds - 300, now), true);
  assert.equal(isRecentAuthTime(seconds - 301, now), false);
  assert.equal(isRecentAuthTime(seconds + 1, now), false);
});

test("verification worker rechecks the current Auth email and verification state", async () => {
  const changed = dependencies({
    uid: "user-1",
    email: "changed@example.com",
    disabled: false,
    emailVerified: false,
  });
  assert.equal(await processAccountVerificationTask(
    TASK,
    changed.dependencies
  ), "ignored");
  assert.deepEqual(changed.calls, ["identity:user-1"]);

  const verified = dependencies({
    uid: "user-1",
    email: "person@example.com",
    disabled: false,
    emailVerified: true,
  });
  assert.equal(await processAccountVerificationTask(
    TASK,
    verified.dependencies
  ), "ignored");
  assert.equal(verified.calls.includes("send:account_verification:person@example.com"), false);
});

test("eligible verification keeps its link transient and uses the shared outbox seam", async () => {
  const harness = dependencies({
    uid: "user-1",
    email: "person@example.com",
    disabled: false,
    emailVerified: false,
  });
  assert.equal(await processAccountVerificationTask(
    TASK,
    harness.dependencies
  ), "sent");
  assert.deepEqual(harness.calls, [
    "identity:user-1",
    "root:user-1:1000",
    "suppression",
    "begin",
    "link:person@example.com",
    "send:account_verification:person@example.com",
    "sent",
  ]);
});

test("verification worker sends nothing for a missing or disabled canonical root", async () => {
  const harness = dependencies({
    uid: "user-1",
    email: "person@example.com",
    disabled: false,
    emailVerified: false,
  }, false);
  assert.equal(await processAccountVerificationTask(
    TASK,
    harness.dependencies
  ), "ignored");
  assert.deepEqual(harness.calls, ["identity:user-1", "root:user-1:1000"]);
});
