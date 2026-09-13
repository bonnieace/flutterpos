import assert from "node:assert/strict";
import test from "node:test";
import {
  bindStaffDeliveryRecipient,
  invitationDeliveryLink,
  isEligibleStaffInvitationRecipient,
  validateInvitationDeliveryTask,
} from "./invitationDelivery";
import {hashRecipient} from "../email/recipientHash";
import {storedCredentialBootstrapRequired} from "./shared";

const TASK = {
  deliveryId: "delivery-1",
  tenantId: "tenant-1",
  targetUid: "user-1",
  invitedEmail: "person@example.com",
  invitationVersion: 2,
  invitationToken: "private-token",
  invitationPath: "tenants/tenant-1/staff_invitations/user-1",
  dispatchAttempt: 1,
  credentialBootstrapRequired: false,
};

test("delivery tasks require a complete versioned transient proof binding", () => {
  assert.deepEqual(validateInvitationDeliveryTask(TASK), TASK);
  assert.throws(() => validateInvitationDeliveryTask({...TASK, invitationToken: ""}));
  assert.throws(() => validateInvitationDeliveryTask({...TASK, invitationVersion: 0}));
  assert.throws(() => validateInvitationDeliveryTask({...TASK, dispatchAttempt: 1.5}));
});

test("unverified invitees receive a transient credential bootstrap link", async () => {
  let generatedFor: {email: string; continueUrl: string} | undefined;
  const link = await invitationDeliveryLink({
    ...TASK,
    credentialBootstrapRequired: true,
  }, async (email, continueUrl) => {
    generatedFor = {email, continueUrl};
    return "https://firebase.example.test/password-setup?oobCode=private";
  }, "https://app.example.test/accept-invitation");
  assert.equal(link, "https://firebase.example.test/password-setup?oobCode=private");
  assert.equal(generatedFor?.email, TASK.invitedEmail);
  assert.match(generatedFor?.continueUrl ?? "", /invitationToken=private-token/);
});

test("verified invitees use the proof action directly without generating credentials", async () => {
  let generated = false;
  const link = await invitationDeliveryLink(TASK, async () => {
    generated = true;
    return "unexpected";
  }, "https://app.example.test/accept-invitation");
  assert.equal(generated, false);
  assert.match(link, /invitationToken=private-token/);
});

test("an invitation written before the rename still picks its own email", () => {
  // `visibleAcceptanceAllowed` was the exact negation of this question until
  // 2026-09-08. Reading it is what stops an invitation already in the
  // collection being sent the wrong one of the two letters after the rename.
  assert.equal(
    storedCredentialBootstrapRequired({visibleAcceptanceAllowed: false}),
    true
  );
  assert.equal(
    storedCredentialBootstrapRequired({visibleAcceptanceAllowed: true}),
    false
  );
  // Absent entirely, which is an invitation from before either field existed:
  // the safe answer is the link that sets a password on the way through.
  assert.equal(storedCredentialBootstrapRequired({}), true);
  // The new field wins wherever it is present.
  assert.equal(
    storedCredentialBootstrapRequired({
      credentialBootstrapRequired: false,
      visibleAcceptanceAllowed: false,
    }),
    false
  );
});

test("staff delivery recipient is bound to the shared versioned HMAC", () => {
  const keyring = {
    currentVersion: "v2",
    keys: {v2: "a sufficiently long recipient privacy key"},
  };
  const expected = hashRecipient(TASK.invitedEmail, keyring);
  assert.ok(bindStaffDeliveryRecipient(TASK.invitedEmail, {
    recipientHash: expected.recipientHash,
    recipientHashKeyVersion: expected.keyVersion,
  }, keyring));
  assert.equal(bindStaffDeliveryRecipient(TASK.invitedEmail, {
    recipientHash: "wrong",
    recipientHashKeyVersion: expected.keyVersion,
  }, keyring), undefined);
});

test("staff delivery survives an HMAC rotation while the persisted key remains supported", () => {
  const oldKeyring = {
    currentVersion: "v1",
    keys: {v1: "the previous recipient privacy key is sufficiently long"},
  };
  const rotatedKeyring = {
    currentVersion: "v2",
    keys: {
      v2: "the current recipient privacy key is sufficiently long",
      v1: oldKeyring.keys.v1,
    },
  };
  const persisted = hashRecipient(TASK.invitedEmail, oldKeyring);
  assert.ok(bindStaffDeliveryRecipient(TASK.invitedEmail, {
    recipientHash: persisted.recipientHash,
    recipientHashKeyVersion: persisted.keyVersion,
  }, rotatedKeyring));
});

test("staff delivery rechecks the current Auth and canonical tenant identity", () => {
  const auth = {uid: TASK.targetUid, email: TASK.invitedEmail, disabled: false};
  const root = {
    accountType: "tenant_user" as const,
    globalStatus: "active" as const,
  };
  const tenant = {status: "active" as const};
  const staff = {
    uid: TASK.targetUid,
    email: TASK.invitedEmail,
    role: "cashier" as const,
    status: "pending" as const,
    invitationStatus: "pending",
  };
  assert.equal(isEligibleStaffInvitationRecipient(TASK, auth, root, tenant, staff), true);
  assert.equal(isEligibleStaffInvitationRecipient(
    TASK,
    {...auth, email: "changed@example.com"},
    root,
    tenant,
    staff
  ), false);
  assert.equal(isEligibleStaffInvitationRecipient(
    TASK,
    auth,
    {...root, identityTransition: "granting_platform"},
    tenant,
    staff
  ), false);
  assert.equal(isEligibleStaffInvitationRecipient(
    TASK,
    auth,
    root,
    {...tenant, status: "suspended"},
    staff
  ), false);
});
