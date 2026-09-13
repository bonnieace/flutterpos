import assert from "node:assert/strict";
import test from "node:test";
import {
  AccountVerificationDependencies,
  processAccountVerificationTask,
  resendThrottleVerdict,
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

test("the resend allowance bounds volume, and a replay costs nothing", () => {
  // **What replaced the five-minute recency rule.** That rule refused the call
  // once the sign-in aged out, which cost a person mid-signup a round trip
  // through the sign-in screen - while being the only brake on the button,
  // because this host mints a fresh requestId per press and the Cloud Tasks
  // deduplication that stops a retried *intent* does nothing about a repeat.
  // A cooldown plus a ceiling bounds the abuse by what it actually is.
  const now = Date.UTC(2026, 8, 11, 9, 0, 0);
  const event = (id: string, agoMilliseconds: number) => ({
    requestId: id,
    requestedAtMilliseconds: now - agoMilliseconds,
  });
  const verdict = (
    events: ReadonlyArray<{requestId: unknown; requestedAtMilliseconds: number | undefined}>,
    requestId = "verify-new"
  ) => resendThrottleVerdict({requestId, events, nowMilliseconds: now});

  // The first press of an account's life.
  assert.equal(verdict([]), "allowed");

  // The same intent arriving twice - what the client does after refreshing a
  // token left behind by an address change. Neither refused nor charged.
  assert.equal(
    verdict([event("verify-new", 1_000)], "verify-new"),
    "replay"
  );

  // A different intent, inside the minute and just outside it.
  assert.equal(verdict([event("verify-first", 59_999)]), "too_soon");
  assert.equal(verdict([event("verify-first", 60_000)]), "allowed");

  // The day's ceiling, which the cooldown alone would never reach.
  const spent = Array.from({length: 10}, (_, index) =>
    event(`verify-${index}`, 3_600_000 + index));
  assert.equal(verdict(spent), "exhausted");
  assert.equal(verdict(spent.slice(0, 9)), "allowed");

  // A replay is recognised even once the ceiling is reached, so a retry of an
  // already-charged intent is never refused by the ceiling it paid for.
  assert.equal(verdict(spent, "verify-3"), "replay");

  // A record stamped in the future is a clock disagreeing with itself; refusing
  // on one would wedge the button until it caught up.
  assert.equal(verdict([event("verify-first", -5_000)]), "allowed");

  // A row whose timestamp did not survive its round trip must not be read as
  // "just now" - it still counts toward the ceiling, but cannot start a
  // cooldown it has no time for.
  assert.equal(
    verdict([{requestId: "verify-first", requestedAtMilliseconds: undefined}]),
    "allowed"
  );
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
