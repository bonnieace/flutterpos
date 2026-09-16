import assert from "node:assert/strict";
import test from "node:test";
import {
  bindStaffDeliveryRecipient,
  invitationDeliveryLink,
  isEligibleStaffInvitationRecipient,
  mirrorDeliveryStateOntoStaff,
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

test("the delivery mirror writes only onto a still-pending staff record", () => {
  // **The guard is the whole of this helper.** The worker runs long after the
  // transaction that queued it, so by the time it lands the member may have
  // accepted or the invitation may have been cancelled and the record deleted.
  const writes: Array<Record<string, unknown>> = [];
  const transaction = {
    update: (_ref: unknown, data: Record<string, unknown>) => {
      writes.push(data);
    },
  } as unknown as Parameters<typeof mirrorDeliveryStateOntoStaff>[0];
  const staffRef = {id: "user-1"} as
    Parameters<typeof mirrorDeliveryStateOntoStaff>[1];
  const snapshot = (
    exists: boolean,
    data?: Record<string, unknown>
  ) => ({exists, data: () => data}) as unknown as
    Parameters<typeof mirrorDeliveryStateOntoStaff>[2];

  // Still pending: the one case that writes.
  mirrorDeliveryStateOntoStaff(
    transaction,
    staffRef,
    snapshot(true, {uid: "user-1", status: "pending"}),
    {invitationDeliveryState: "sent"}
  );
  assert.equal(writes.length, 1);
  assert.equal(writes[0].invitationDeliveryState, "sent");

  // Accepted between the send and this write: the membership has moved on and a
  // delivery label must not be hung on it.
  mirrorDeliveryStateOntoStaff(
    transaction,
    staffRef,
    snapshot(true, {uid: "user-1", status: "active"}),
    {invitationDeliveryState: "sent"}
  );
  // Cancelled: the record is gone, and updating it would fail the task into a
  // retry loop against a document that is never coming back.
  mirrorDeliveryStateOntoStaff(
    transaction,
    staffRef,
    snapshot(false),
    {invitationDeliveryState: "failed"}
  );
  // A record whose projected uid is not its own document id.
  mirrorDeliveryStateOntoStaff(
    transaction,
    staffRef,
    snapshot(true, {uid: "someone-else", status: "pending"}),
    {invitationDeliveryState: "failed"}
  );
  assert.equal(writes.length, 1);
});

test("the delivery mirror never touches the membership's own invitation state", () => {
  // Four server gates read `invitationStatus` on this record -
  // `requirePendingStaffInvitation`, `acceptancePolicy`,
  // `isEligibleStaffInvitationRecipient` and the client's strict projection - so
  // a delivery outcome folded into it would refuse the recipient's acceptance
  // and the administrator's replace-the-address.
  const writes: Array<Record<string, unknown>> = [];
  const transaction = {
    update: (_ref: unknown, data: Record<string, unknown>) => {
      writes.push(data);
    },
  } as unknown as Parameters<typeof mirrorDeliveryStateOntoStaff>[0];

  mirrorDeliveryStateOntoStaff(
    transaction,
    {id: "user-1"} as Parameters<typeof mirrorDeliveryStateOntoStaff>[1],
    ({exists: true, data: () => ({uid: "user-1", status: "pending"})}) as
      unknown as Parameters<typeof mirrorDeliveryStateOntoStaff>[2],
    {invitationDeliveryState: "failed"}
  );

  assert.equal(writes.length, 1);
  assert.ok(!("invitationStatus" in writes[0]));
  assert.equal(writes[0].invitationDeliveryState, "failed");
});
