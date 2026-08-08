/**
 * Drives the password-reset delivery worker against real Auth and real
 * Firestore.
 *
 * `functions/src/email/passwordReset.test.ts` already covers the worker's
 * *logic* — unknown identity, the current-email HMAC recheck, suppression, an
 * eligible send, a retryable provider error, a disabled canonical root, and a
 * malformed address — but it substitutes every dependency. So until this file
 * existed, nothing had ever run `generatePasswordResetLink` against a real Auth
 * record, nor the lease and outcome transactions against real Firestore, where a
 * `FieldValue.delete()` in the wrong kind of write throws at serialization time
 * and no pure test can see it. That is the defect class
 * `run-reconciliation-emulator-tests.js` was built for.
 *
 * What is dispatched is `processPasswordResetTask` wired through the real
 * `firestorePasswordResetDependencies`, which is `deliverPasswordReset`'s body
 * minus three lines: parsing the keyring out of its secret, constructing the
 * Brevo provider out of its secrets, and the `getFirestore()`/`getAuth()`
 * defaults. Those three are deliberately not exercised here — reaching them
 * needs the Functions fixture to export an email function, and every parameter
 * in `email/config.ts` would then have to be answered at emulator startup or the
 * run hangs after "Serving at port ...". The invitation fixture's seven exports
 * reach `firebase-functions/params` not at all, and this suite does not spend
 * that invariant on three lines whose parts are unit-tested elsewhere.
 *
 * The Brevo seam stays a seam. The provider is the **real** `BrevoEmailProvider`
 * over a stub `fetch`, so the request it builds — recipient, idempotency header,
 * and the action link it carries — is asserted rather than imagined, and the
 * network is never touched. No live provider credential is involved.
 */
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { after, before, test } from "node:test";

import {
  firestorePasswordResetDependencies,
  preparePasswordResetRequest,
  processPasswordResetTask,
} from "../../functions/lib/email/passwordReset.js";
import { BrevoEmailProvider } from "../../functions/lib/email/brevoProvider.js";
import {
  hashRecipient,
  parseRecipientHmacKeyring,
} from "../../functions/lib/email/recipientHash.js";

const PROJECT_ID = "demo-multitenant-invitation-integration";
const CONTINUE_URL = "https://reset.integration.example.test/finish";

/**
 * Two versions, so a suppression recorded under the previous key is still found
 * after a rotation — the branch `allRecipientHashes` exists for, and one that a
 * single-key fixture cannot reach.
 */
const KEYRING_JSON = JSON.stringify({
  currentVersion: "v2",
  keys: {
    v2: "local-emulator-recipient-hmac-key-version-two-32+",
    v1: "local-emulator-recipient-hmac-key-version-one-32+",
  },
});

const PROVIDER_CONFIGURATION = {
  apiKey: "local-emulator-brevo-key-never-sent-anywhere",
  senderAddress: "no-reply@integration.example.test",
  senderName: "ChillTent Integration",
};

/**
 * Every string that must never reach Firestore: each address, each address's
 * local part, and each action link the real Auth emulator minted. The final test
 * sweeps the three collections for all of them, which is why UIDs here are
 * deliberately unrelated to the local parts they belong to — a UID echoing a
 * local part would make that sweep pass for the wrong reason.
 */
const plaintextThatMustNotBeStored = [];

const requireFunctionsAdmin = createRequire(new URL(
  "../../functions/package.json",
  import.meta.url,
));
const functionsAdminApp = requireFunctionsAdmin("firebase-admin/app");
const functionsAdminAuth = requireFunctionsAdmin("firebase-admin/auth");
const functionsAdminFirestore = requireFunctionsAdmin("firebase-admin/firestore");
const { Timestamp } = functionsAdminFirestore;

let keyring;
let app;
let auth;
let firestore;

before(async () => {
  requireEmulator("FIREBASE_AUTH_EMULATOR_HOST");
  requireEmulator("FIRESTORE_EMULATOR_HOST");
  assert.equal(process.env.GCLOUD_PROJECT, PROJECT_ID);
  // The gateway reads this through `defineString(...).value()`, which resolves to
  // `process.env` outside a deployed function.
  assert.equal(process.env.PASSWORD_RESET_CONTINUE_URL, CONTINUE_URL);
  keyring = parseRecipientHmacKeyring(KEYRING_JSON);
  // The worker's own copy of firebase-admin, not this package's: the adapters
  // compare against `Timestamp` and write `FieldValue` sentinels from
  // `functions/node_modules`, and a handle built from a second copy of the SDK
  // would fail those identity checks in ways no assertion here would explain.
  app = functionsAdminApp.initializeApp(
    { projectId: PROJECT_ID },
    "password-reset-integration",
  );
  auth = functionsAdminAuth.getAuth(app);
  firestore = functionsAdminFirestore.getFirestore(app);
});

after(async () => {
  if (app) await functionsAdminApp.deleteApp(app);
});

test("an eligible reset sends a real Auth link and stores only hashes", async () => {
  const fixture = await seedEligibleIdentity({
    uid: "pwreset-eligible",
    localPart: "delivery-eligible",
  });
  const { provider, calls } = recordingBrevoProvider([accepted("brevo-message-1")]);
  const task = prepareTask(fixture.typedEmail, "password-reset-integration-eligible-1");

  const outcome = await processPasswordResetTask(
    task,
    firestorePasswordResetDependencies(firestore, auth, provider, keyring),
  );

  assert.equal(outcome, "sent");
  assert.equal(calls.length, 1);
  const [call] = calls;
  assert.equal(call.url, "https://api.brevo.com/v3/smtp/email");
  assert.deepEqual(call.body.to, [{ email: fixture.email }]);
  assert.equal(call.body.headers["Idempotency-Key"], task.deliveryId);
  assert.equal(call.body.sender.email, PROVIDER_CONFIGURATION.senderAddress);
  // The link is not a fixture: the real Auth emulator minted it for a real
  // record, and it carries the one-time code that record's reset depends on.
  const actionUrl = extractActionUrl(call.body.textContent);
  assert.match(actionUrl, /[?&]oobCode=[^&]+/);
  assert.match(actionUrl, /[?&]mode=resetPassword\b/);
  assert.ok(
    actionUrl.includes(encodeURIComponent(CONTINUE_URL)) ||
      actionUrl.includes(CONTINUE_URL),
    `the configured continue URL is absent from ${actionUrl}`,
  );
  plaintextThatMustNotBeStored.push(actionUrl);

  const delivery = await firestore.doc(`email_deliveries/${task.deliveryId}`).get();
  assert.equal(delivery.get("status"), "sent");
  assert.equal(delivery.get("deliveryType"), "password_reset");
  assert.equal(delivery.get("targetUid"), fixture.uid);
  assert.equal(delivery.get("provider"), "brevo");
  assert.equal(delivery.get("providerMessageId"), "brevo-message-1");
  assert.equal(delivery.get("attemptCount"), 1);
  assert.equal(delivery.get("retryable"), false);
  assert.equal(delivery.get("recipientHash"), task.recipientHash);
  assert.equal(delivery.get("recipientHashKeyVersion"), "v2");
  assert.ok(delivery.get("sentAt") instanceof Timestamp);
  assert.ok(delivery.get("createdAt") instanceof Timestamp);
  // The lease is surrendered rather than left behind, which is what lets a later
  // dispatch read a terminal state instead of waiting five minutes for it.
  assert.equal(delivery.get("leaseId"), undefined);
  assert.equal(delivery.get("leaseExpiresAt"), undefined);
  assert.equal(delivery.get("nextAttemptAt"), undefined);

  const status = await firestore.doc(`email_delivery_status/${fixture.uid}`).get();
  assert.equal(status.get("availability"), "available");
  assert.equal(status.get("recipientHash"), task.recipientHash);
  assert.equal(status.get("recipientHashKeyVersion"), "v2");
});

test("an address changed in real Auth after the request writes nothing", async () => {
  const fixture = await seedEligibleIdentity({
    uid: "pwreset-moved",
    localPart: "delivery-moved",
  });
  const task = prepareTask(fixture.typedEmail, "password-reset-integration-moved-1");
  const movedTo = "delivery-moved-elsewhere@integration.example.test";
  plaintextThatMustNotBeStored.push(movedTo, "delivery-moved-elsewhere");
  await auth.updateUser(fixture.uid, { email: movedTo });
  const { provider, calls } = recordingBrevoProvider([]);

  const outcome = await processPasswordResetTask(
    task,
    firestorePasswordResetDependencies(firestore, auth, provider, keyring),
  );

  assert.equal(outcome, "ignored");
  assert.equal(calls.length, 0);
  await assertNothingRecorded(task, fixture.uid);
});

test("a disabled real Auth identity writes nothing", async () => {
  const fixture = await seedEligibleIdentity({
    uid: "pwreset-disabled",
    localPart: "delivery-disabled",
  });
  await auth.updateUser(fixture.uid, { disabled: true });
  const task = prepareTask(fixture.typedEmail, "password-reset-integration-disabled-1");
  const { provider, calls } = recordingBrevoProvider([]);

  const outcome = await processPasswordResetTask(
    task,
    firestorePasswordResetDependencies(firestore, auth, provider, keyring),
  );

  assert.equal(outcome, "ignored");
  assert.equal(calls.length, 0);
  await assertNothingRecorded(task, fixture.uid);
});

test("an address real Auth does not know writes nothing", async () => {
  // The gateway swallows exactly one Auth error code and rethrows every other.
  // Only real Auth can say which code an unknown address actually produces.
  const email = "delivery-absent@integration.example.test";
  plaintextThatMustNotBeStored.push(email, "delivery-absent");
  const task = prepareTask(email, "password-reset-integration-absent-1");
  const { provider, calls } = recordingBrevoProvider([]);

  const outcome = await processPasswordResetTask(
    task,
    firestorePasswordResetDependencies(firestore, auth, provider, keyring),
  );

  assert.equal(outcome, "ignored");
  assert.equal(calls.length, 0);
  const delivery = await firestore.doc(`email_deliveries/${task.deliveryId}`).get();
  assert.equal(delivery.exists, false);
});

test("a canonical root that is absent or not eligible writes nothing", async () => {
  const fixture = await seedEligibleIdentity({
    uid: "pwreset-root",
    localPart: "delivery-root",
    root: false,
  });
  const task = prepareTask(fixture.typedEmail, "password-reset-integration-root-1");
  const { provider, calls } = recordingBrevoProvider([]);
  const dependencies = () =>
    firestorePasswordResetDependencies(firestore, auth, provider, keyring);

  assert.equal(await processPasswordResetTask(task, dependencies()), "ignored");
  await assertNothingRecorded(task, fixture.uid);

  await firestore.doc(`users/${fixture.uid}`).set(rootRecord(fixture.email, {
    globalStatus: "disabled",
  }));
  assert.equal(await processPasswordResetTask(task, dependencies()), "ignored");
  assert.equal(calls.length, 0);
  await assertNothingRecorded(task, fixture.uid);
});

test("a suppression under the previous key version is still found", async () => {
  const fixture = await seedEligibleIdentity({
    uid: "pwreset-suppressed",
    localPart: "delivery-suppressed",
  });
  const previous = hashRecipient(fixture.email, keyring, "v1");
  await firestore.doc(`email_suppressions/${previous.documentId}`).set({
    recipientHash: previous.recipientHash,
    recipientHashKeyVersion: previous.keyVersion,
    status: "active",
    reason: "hard_bounce",
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
  });
  const task = prepareTask(fixture.typedEmail, "password-reset-integration-suppressed-1");
  const { provider, calls } = recordingBrevoProvider([]);

  const outcome = await processPasswordResetTask(
    task,
    firestorePasswordResetDependencies(firestore, auth, provider, keyring),
  );

  assert.equal(outcome, "suppressed");
  assert.equal(calls.length, 0);
  const delivery = await firestore.doc(`email_deliveries/${task.deliveryId}`).get();
  assert.equal(delivery.get("status"), "suppressed");
  assert.equal(delivery.get("sendable"), false);
  assert.equal(delivery.get("retryable"), false);
  assert.equal(delivery.get("attemptCount"), 0);
  assert.equal(delivery.get("targetUid"), fixture.uid);
  // The delivery is recorded under the *current* version even though the
  // suppression that stopped it was written under the previous one.
  assert.equal(delivery.get("recipientHashKeyVersion"), "v2");
  const status = await firestore.doc(`email_delivery_status/${fixture.uid}`).get();
  assert.equal(status.get("availability"), "unavailable");
});

test("a retryable provider failure leaves a retry the next attempt completes", async () => {
  const fixture = await seedEligibleIdentity({
    uid: "pwreset-retry",
    localPart: "delivery-retry",
  });
  const task = prepareTask(fixture.typedEmail, "password-reset-integration-retry-1");
  const { provider, calls } = recordingBrevoProvider([
    rejected(503),
    accepted("brevo-message-retry"),
  ]);
  const dependencies = firestorePasswordResetDependencies(
    firestore,
    auth,
    provider,
    keyring,
  );

  await assert.rejects(
    processPasswordResetTask(task, dependencies),
    /Password reset delivery will be retried\./,
  );
  let delivery = await firestore.doc(`email_deliveries/${task.deliveryId}`).get();
  assert.equal(delivery.get("status"), "retry_pending");
  assert.equal(delivery.get("retryable"), true);
  assert.equal(delivery.get("attemptCount"), 1);
  assert.equal(delivery.get("lastErrorCode"), "provider_http_503");
  assert.equal(delivery.get("leaseId"), undefined);
  assert.equal(delivery.get("leaseExpiresAt"), undefined);
  const nextAttemptAt = delivery.get("nextAttemptAt");
  assert.ok(nextAttemptAt instanceof Timestamp);
  assert.ok(nextAttemptAt.toMillis() > Timestamp.now().toMillis());

  assert.equal(await processPasswordResetTask(task, dependencies), "sent");
  assert.equal(calls.length, 2);
  plaintextThatMustNotBeStored.push(extractActionUrl(calls[1].body.textContent));
  delivery = await firestore.doc(`email_deliveries/${task.deliveryId}`).get();
  assert.equal(delivery.get("status"), "sent");
  assert.equal(delivery.get("attemptCount"), 2);
  assert.equal(delivery.get("providerMessageId"), "brevo-message-retry");
  // Both sentinels are deletions against a document that already holds the
  // fields, which is the write shape a pure test cannot serialize.
  assert.equal(delivery.get("nextAttemptAt"), undefined);
  assert.equal(delivery.get("lastErrorCode"), undefined);
});

test("a permanent provider failure marks the identity unavailable", async () => {
  const fixture = await seedEligibleIdentity({
    uid: "pwreset-permanent",
    localPart: "delivery-permanent",
  });
  const task = prepareTask(fixture.typedEmail, "password-reset-integration-permanent-1");
  const { provider, calls } = recordingBrevoProvider([rejected(400)]);

  const outcome = await processPasswordResetTask(
    task,
    firestorePasswordResetDependencies(firestore, auth, provider, keyring),
  );

  assert.equal(outcome, "permanent_failure");
  assert.equal(calls.length, 1);
  plaintextThatMustNotBeStored.push(extractActionUrl(calls[0].body.textContent));
  const delivery = await firestore.doc(`email_deliveries/${task.deliveryId}`).get();
  assert.equal(delivery.get("status"), "permanent_failure");
  assert.equal(delivery.get("retryable"), false);
  assert.equal(delivery.get("lastErrorCode"), "provider_http_400");
  assert.equal(delivery.get("nextAttemptAt"), undefined);
  assert.equal(delivery.get("leaseId"), undefined);
  const status = await firestore.doc(`email_delivery_status/${fixture.uid}`).get();
  assert.equal(status.get("availability"), "unavailable");
});

test("a repeated dispatch of a sent delivery does not send twice", async () => {
  const fixture = await seedEligibleIdentity({
    uid: "pwreset-repeat",
    localPart: "delivery-repeat",
  });
  const task = prepareTask(fixture.typedEmail, "password-reset-integration-repeat-1");
  const { provider, calls } = recordingBrevoProvider([accepted("brevo-message-once")]);
  const dependencies = firestorePasswordResetDependencies(
    firestore,
    auth,
    provider,
    keyring,
  );

  assert.equal(await processPasswordResetTask(task, dependencies), "sent");
  plaintextThatMustNotBeStored.push(extractActionUrl(calls[0].body.textContent));
  assert.equal(await processPasswordResetTask(task, dependencies), "already_final");

  assert.equal(calls.length, 1);
  const delivery = await firestore.doc(`email_deliveries/${task.deliveryId}`).get();
  assert.equal(delivery.get("status"), "sent");
  assert.equal(delivery.get("attemptCount"), 1);
  assert.equal(delivery.get("providerMessageId"), "brevo-message-once");
});

test("a continue URL that is not HTTPS refuses to build the gateway", async () => {
  const original = process.env.PASSWORD_RESET_CONTINUE_URL;
  process.env.PASSWORD_RESET_CONTINUE_URL = "http://reset.integration.example.test/finish";
  try {
    assert.throws(
      () => firestorePasswordResetDependencies(
        firestore,
        auth,
        recordingBrevoProvider([]).provider,
        keyring,
      ),
      /PASSWORD_RESET_CONTINUE_URL must be an HTTPS URL\./,
    );
  } finally {
    process.env.PASSWORD_RESET_CONTINUE_URL = original;
  }
});

// This one sweeps what the tests above wrote, so it is the single test in this
// file that a `INTEGRATION_TEST_NAME_PATTERN` run will fail: filtered down to
// itself it has nothing to sweep, and a sweep that finds nothing is exactly the
// result these three floors exist to refuse.
test("no document any of these deliveries wrote holds an address or a link", async () => {
  assert.ok(plaintextThatMustNotBeStored.length > 0);
  const [deliveries, statuses, suppressions] = await Promise.all([
    firestore.collection("email_deliveries").get(),
    firestore.collection("email_delivery_status").get(),
    firestore.collection("email_suppressions").get(),
  ]);
  assert.ok(deliveries.size > 0);
  assert.ok(statuses.size > 0);
  for (const snapshot of [deliveries, statuses, suppressions]) {
    for (const document of snapshot.docs) {
      const serialized = JSON.stringify({
        id: document.id,
        data: document.data(),
      });
      for (const plaintext of plaintextThatMustNotBeStored) {
        assert.equal(
          serialized.includes(plaintext),
          false,
          `${document.ref.path} holds plaintext ${plaintext}`,
        );
      }
    }
  }
});

function requireEmulator(name) {
  const value = process.env[name];
  if (!value || !/^127\.0\.0\.1:\d+$/.test(value)) {
    throw new Error(`${name} must target a local emulator, received ${value}`);
  }
}

/**
 * Takes the address as a caller would type it, not as the system stores it, so
 * every task here proves the folding on the request side as well.
 */
function prepareTask(typedEmail, requestId) {
  const prepared = preparePasswordResetRequest(
    { email: typedEmail, requestId },
    keyring,
  );
  assert.deepEqual(prepared.response, { accepted: true });
  assert.equal(prepared.task.normalizedEmail, typedEmail.trim().toLowerCase());
  assert.equal(prepared.taskId, `password-reset-${prepared.task.deliveryId}`);
  return prepared.task;
}

function rootRecord(email, extra = {}) {
  const now = Timestamp.now();
  return {
    email,
    accountType: "tenant_user",
    identityOrigin: "self_signup",
    globalStatus: "active",
    membershipCount: 0,
    ownedTenantCount: 0,
    ownedActiveTenantCount: 0,
    createdAt: now,
    updatedAt: now,
    ...extra,
  };
}

/**
 * The Auth record is created with a mixed-case address and `typedEmail` is
 * padded and upper-cased, so every send here proves the folding on both sides at
 * once: the hash the task carries is derived from what the caller typed, and the
 * hash it is rechecked against is derived from what Auth actually holds.
 */
async function seedEligibleIdentity({ uid, localPart, root = true }) {
  const email = `${localPart}@integration.example.test`;
  const mixedCase = `${localPart.toUpperCase()}@Integration.Example.Test`;
  plaintextThatMustNotBeStored.push(email, mixedCase, localPart);
  await auth.createUser({
    uid,
    email: mixedCase,
    emailVerified: true,
    disabled: false,
  });
  if (root) await firestore.doc(`users/${uid}`).set(rootRecord(email));
  return { uid, email, typedEmail: `  ${mixedCase}  ` };
}

function accepted(messageId) {
  return () => new Response(JSON.stringify({ messageId }), {
    status: 201,
    headers: { "content-type": "application/json" },
  });
}

function rejected(status) {
  return () => new Response(JSON.stringify({ code: "refused" }), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function recordingBrevoProvider(responses) {
  const queue = [...responses];
  const calls = [];
  const provider = new BrevoEmailProvider(PROVIDER_CONFIGURATION, async (url, init) => {
    const next = queue.shift();
    assert.ok(next, `the Brevo seam received an unexpected call to ${url}`);
    calls.push({ url, init, body: JSON.parse(init.body) });
    return next();
  });
  return { provider, calls };
}

function extractActionUrl(textContent) {
  const match = /(https?:\/\/\S+)$/.exec(textContent.trim());
  assert.ok(match, `no action link in ${textContent}`);
  return match[1];
}

async function assertNothingRecorded(task, uid) {
  const [delivery, status] = await Promise.all([
    firestore.doc(`email_deliveries/${task.deliveryId}`).get(),
    firestore.doc(`email_delivery_status/${uid}`).get(),
  ]);
  assert.equal(delivery.exists, false);
  assert.equal(status.exists, false);
}
