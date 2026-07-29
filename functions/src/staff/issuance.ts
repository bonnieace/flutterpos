import {
  FieldValue,
  Firestore,
  getFirestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {
  requireAuthenticatedUser,
  requireTenantMember,
} from "../core/authorization";
import {runIdempotentFirestoreTransaction} from "../core/idempotency";
import {
  requireDocumentId,
  requireObject,
  requireRequestId,
} from "../core/validation";
import {EMAIL_RECIPIENT_HMAC_KEYRING} from "../email/config";
import {parseRecipientHmacKeyring} from "../email/recipientHash";
import {bindRecipientPrivacy} from "../email/suppressionLookup";
import {
  dispatchInvitationDelivery,
} from "./invitationDelivery";
import {
  finalizeReservedStaffOperation,
  provisionalStaffUid,
  reserveStaffIdentityOperation,
  resolveReservedStaffIdentity,
} from "./identityProvisioning";
import {STAFF_INVITATION_HMAC_SECRET, invitationHmacSecretValue} from "./secret";
import {
  assertCanonicalTargetStaff,
  assertExactCanonicalOwner,
  auditData,
  deliveryData,
  isPendingInvitationStatus,
  membershipMirrorData,
  operationDocumentId,
  preauthorizeTenantAdministrator,
  prepareTargetRoot,
  readAuthIdentity,
  STAFF_MANAGEMENT_ROLES,
  writePreparedRoot,
  writeExistingRootMembershipDelta,
} from "./shared";
import {
  DeliveryMetadata,
  StoredInvitationRecord,
  StoredMirrorRecord,
  StoredStaffRecord,
  StoredTenantRecord,
} from "./types";
import {
  normalizeEmail,
  normalizePhone,
  normalizeStaffName,
  requireCancellationReason,
  requireInvitableRole,
} from "./validation";

interface InviteStaffRequest {
  tenantId?: unknown;
  email?: unknown;
  name?: unknown;
  phone?: unknown;
  role?: unknown;
  requestId?: unknown;
}

interface ReplacePendingStaffEmailRequest {
  tenantId?: unknown;
  uid?: unknown;
  email?: unknown;
  requestId?: unknown;
}

interface TargetInvitationRequest {
  tenantId?: unknown;
  uid?: unknown;
  requestId?: unknown;
}

interface CancelTenantInvitationRequest extends TargetInvitationRequest {
  reason?: unknown;
}

interface InvitationMutationResponse {
  tenantId: string;
  uid: string;
  invitationStatus: "pending" | "cancelled";
  invitationVersion: number;
  delivery: DeliveryMetadata | null;
}

function ownedProvisioningOperation(
  invitation: StoredInvitationRecord | undefined,
  uid: string
): string | undefined {
  const operationId = invitation?.identityProvisioningOperationId;
  return invitation?.identityOwnedByInvitation === true &&
    typeof operationId === "string" &&
    provisionalStaffUid(operationId) === uid ? operationId : undefined;
}

function scheduleCancelledIdentityCleanup(
  db: Firestore,
  transaction: Transaction,
  input: {
    actorUid: string;
    tenantId: string;
    targetUid: string;
    requestId: string;
    source: "email_replaced" | "invitation_cancelled";
    invitation: StoredInvitationRecord;
  }
): void {
  const provisioningOperationId = ownedProvisioningOperation(
    input.invitation,
    input.targetUid
  );
  if (!provisioningOperationId) return;
  const cleanupOperationId = operationDocumentId(
    input.actorUid,
    "cleanupCancelledStaffIdentity",
    input.tenantId,
    `${input.source}:${input.requestId}:${input.targetUid}`
  );
  transaction.create(
    db.collection("staff_identity_operations").doc(cleanupOperationId),
    {
      operationId: cleanupOperationId,
      actorUid: input.actorUid,
      operation: "cleanupCancelledStaffIdentity",
      tenantId: input.tenantId,
      requestId: input.requestId,
      source: input.source,
      sourceProvisioningOperationId: provisioningOperationId,
      provisionalUid: input.targetUid,
      identityUid: input.targetUid,
      identityOwnedByOperation: true,
      status: "identity_resolved",
      cleanupAfterAt: Timestamp.now(),
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }
  );
}

function storedInvitationVersion(
  invitation: StoredInvitationRecord | undefined,
  allowMissing: boolean
): number {
  if (!invitation && allowMissing) return 0;
  if (
    invitation &&
    Number.isSafeInteger(invitation.invitationVersion) &&
    (invitation.invitationVersion as number) >= 1
  ) {
    return invitation.invitationVersion as number;
  }
  throw new HttpsError("failed-precondition", "Invitation version state is invalid.");
}

function requirePendingStaffInvitation(
  targetUid: string,
  tenantId: string,
  tenant: StoredTenantRecord,
  staff: StoredStaffRecord | undefined,
  invitation: StoredInvitationRecord | undefined
): {
  staff: StoredStaffRecord & {role: Exclude<NonNullable<StoredStaffRecord["role"]>, "owner">};
  invitation: StoredInvitationRecord;
} {
  const canonical = assertCanonicalTargetStaff(targetUid, tenant, staff);
  if (
    canonical.role === "owner" ||
    canonical.status !== "pending" ||
    !isPendingInvitationStatus(canonical.invitationStatus) ||
    !invitation ||
    invitation.uid !== targetUid ||
    invitation.tenantId !== tenantId
  ) {
    throw new HttpsError("failed-precondition", "The target invitation is not pending.");
  }
  if (!isPendingInvitationStatus(invitation.invitationStatus)) {
    throw new HttpsError("failed-precondition", "The target invitation is not pending.");
  }
  return {
    staff: canonical as StoredStaffRecord & {
      role: Exclude<NonNullable<StoredStaffRecord["role"]>, "owner">;
    },
    invitation,
  };
}

export const inviteStaff = onCall<InviteStaffRequest, Promise<InvitationMutationResponse>>(
  {secrets: [STAFF_INVITATION_HMAC_SECRET, EMAIL_RECIPIENT_HMAC_KEYRING]},
  async (request: CallableRequest<InviteStaffRequest>): Promise<InvitationMutationResponse> => {
    const auth = requireAuthenticatedUser(request, {allowUnverified: true});
    const data = requireObject(request.data);
    const tenantId = requireDocumentId(data.tenantId, "tenantId");
    const email = normalizeEmail(data.email);
    const name = normalizeStaffName(data.name);
    const phone = normalizePhone(data.phone);
    const role = requireInvitableRole(data.role);
    const requestId = requireRequestId(data.requestId);
    const db = getFirestore();

    await preauthorizeTenantAdministrator(db, request, tenantId);
    const secret = invitationHmacSecretValue();
    const deliveryId = operationDocumentId(auth.uid, "inviteStaff", tenantId, requestId);
    const operationInput = {email, name, phone, role};
    const reservation = await reserveStaffIdentityOperation<
      typeof operationInput,
      InvitationMutationResponse
    >(db, {
      operationId: deliveryId,
      actorUid: auth.uid,
      operation: "inviteStaff",
      tenantId,
      requestId,
      input: operationInput,
      email,
      displayName: name,
    });
    if (reservation.status === "completed" && reservation.result) {
      await dispatchInvitationDelivery(db, deliveryId, secret);
      return reservation.result;
    }
    const targetIdentity = await resolveReservedStaffIdentity(db, reservation);
    const recipient = bindRecipientPrivacy(
      targetIdentity.email,
      parseRecipientHmacKeyring(EMAIL_RECIPIENT_HMAC_KEYRING.value())
    );
    if (!recipient) {
      throw new HttpsError("failed-precondition", "The target Auth email is invalid.");
    }

    const result = await finalizeReservedStaffOperation(
      db,
      reservation,
      targetIdentity,
      async (transaction): Promise<InvitationMutationResponse> => {
      const actorContext = await requireTenantMember(
        db,
        request,
        tenantId,
        STAFF_MANAGEMENT_ROLES,
        transaction
      );
      const tenant = actorContext.tenant as StoredTenantRecord;
      const targetRootRef = db.collection("users").doc(targetIdentity.uid);
      const targetStaffRef = db.collection("tenants").doc(tenantId)
        .collection("staff").doc(targetIdentity.uid);
      const mirrorRef = targetRootRef.collection("tenant_memberships").doc(tenantId);
      const invitationRef = db.collection("tenants").doc(tenantId)
        .collection("staff_invitations").doc(targetIdentity.uid);
      const [rootSnapshot, staffSnapshot, mirrorSnapshot, invitationSnapshot] =
        await transaction.getAll(targetRootRef, targetStaffRef, mirrorRef, invitationRef);
      const preparedRoot = prepareTargetRoot(rootSnapshot, targetIdentity, true);
      if (staffSnapshot.exists) {
        throw new HttpsError("already-exists", "This identity already has a membership.");
      }
      const priorInvitation = invitationSnapshot.exists ?
        invitationSnapshot.data() as StoredInvitationRecord :
        undefined;
      const invitationVersion = storedInvitationVersion(priorInvitation, true) + 1;
      const identityProvisioningOperationId = targetIdentity.newlyCreated ?
        deliveryId : ownedProvisioningOperation(priorInvitation, targetIdentity.uid);
      const nextStaff: StoredStaffRecord = {
        uid: targetIdentity.uid,
        email: targetIdentity.email,
        name,
        phone,
        role,
        status: "pending",
        invitationStatus: "pending",
      };

      await assertExactCanonicalOwner(db, transaction, tenantId, tenant.ownerUid);

      writePreparedRoot(transaction, targetRootRef, preparedRoot, 1);
      transaction.create(targetStaffRef, {
        ...nextStaff,
        createdAt: FieldValue.serverTimestamp(),
        joinedAt: null,
        updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.set(mirrorRef, membershipMirrorData(
        tenantId,
        tenant,
        nextStaff,
        mirrorSnapshot.exists ? mirrorSnapshot.data() as StoredMirrorRecord : undefined,
        false
      ));
      transaction.set(invitationRef, {
        uid: targetIdentity.uid,
        tenantId,
        invitationVersion,
        invitationTokenHash: null,
        invitationTokenKeyVersion: null,
        invitationIssuedAt: null,
        invitationExpiresAt: null,
        invitationTokenUsedAt: null,
        invitationStatus: "pending",
        invitedEmail: targetIdentity.email,
        invitedBy: auth.uid,
        latestDeliveryId: deliveryId,
        visibleAcceptanceAllowed: !targetIdentity.newlyCreated && targetIdentity.emailVerified,
        identityOwnedByInvitation: identityProvisioningOperationId !== undefined,
        identityProvisioningOperationId: identityProvisioningOperationId ?? null,
        updatedAt: FieldValue.serverTimestamp(),
        createdAt: priorInvitation ? priorInvitation.createdAt ??
          FieldValue.serverTimestamp() : FieldValue.serverTimestamp(),
      });
      transaction.create(
        db.collection("email_deliveries").doc(deliveryId),
        deliveryData(
          deliveryId,
          tenantId,
          targetIdentity.uid,
          recipient.current.recipientHash,
          recipient.current.keyVersion,
          invitationVersion,
          invitationRef.path
        )
      );
      transaction.create(
        db.collection("tenants").doc(tenantId).collection("audit_logs").doc(deliveryId),
        auditData(tenantId, "staff_invited", auth.uid, targetIdentity.uid, requestId, {
          role,
          recipientHash: recipient.current.recipientHash,
          recipientHashKeyVersion: recipient.current.keyVersion,
          invitationVersion,
        })
      );
      return {
        tenantId,
        uid: targetIdentity.uid,
        invitationStatus: "pending",
        invitationVersion,
        delivery: {deliveryId, status: "pending_enqueue"},
      };
      }
    );
    await dispatchInvitationDelivery(db, deliveryId, secret);
    return result;
  }
);

export const resendStaffInvitation = onCall<
  TargetInvitationRequest,
  Promise<InvitationMutationResponse>
>(
  {secrets: [STAFF_INVITATION_HMAC_SECRET, EMAIL_RECIPIENT_HMAC_KEYRING]},
  async (
    request: CallableRequest<TargetInvitationRequest>
  ): Promise<InvitationMutationResponse> => {
    const auth = requireAuthenticatedUser(request, {allowUnverified: true});
    const data = requireObject(request.data);
    const tenantId = requireDocumentId(data.tenantId, "tenantId");
    const targetUid = requireDocumentId(data.uid, "uid");
    const requestId = requireRequestId(data.requestId);
    const db = getFirestore();

    await preauthorizeTenantAdministrator(db, request, tenantId);
    const targetIdentity = await readAuthIdentity(targetUid);
    const recipient = bindRecipientPrivacy(
      targetIdentity.email,
      parseRecipientHmacKeyring(EMAIL_RECIPIENT_HMAC_KEYRING.value())
    );
    if (!recipient) {
      throw new HttpsError("failed-precondition", "The target Auth email is invalid.");
    }
    const secret = invitationHmacSecretValue();
    const deliveryId = operationDocumentId(
      auth.uid,
      "resendStaffInvitation",
      tenantId,
      requestId
    );

    const result = await runIdempotentFirestoreTransaction(db, {
      actorUid: auth.uid,
      operation: "resendStaffInvitation",
      tenantId,
      requestId,
      input: {targetUid},
    }, async (transaction): Promise<InvitationMutationResponse> => {
      const actorContext = await requireTenantMember(
        db, request, tenantId, STAFF_MANAGEMENT_ROLES, transaction
      );
      const tenant = actorContext.tenant as StoredTenantRecord;
      const targetRootRef = db.collection("users").doc(targetUid);
      const staffRef = db.collection("tenants").doc(tenantId).collection("staff").doc(targetUid);
      const mirrorRef = targetRootRef.collection("tenant_memberships").doc(tenantId);
      const invitationRef = db.collection("tenants").doc(tenantId)
        .collection("staff_invitations").doc(targetUid);
      const [rootSnapshot, staffSnapshot, mirrorSnapshot, invitationSnapshot] =
        await transaction.getAll(targetRootRef, staffRef, mirrorRef, invitationRef);
      const preparedRoot = prepareTargetRoot(rootSnapshot, targetIdentity, true);
      const pending = requirePendingStaffInvitation(
        targetUid,
        tenantId,
        tenant,
        staffSnapshot.exists ? staffSnapshot.data() as StoredStaffRecord : undefined,
        invitationSnapshot.exists ? invitationSnapshot.data() as StoredInvitationRecord : undefined
      );
      if (
        typeof pending.invitation.invitedEmail !== "string" ||
        pending.invitation.invitedEmail.trim().toLowerCase() !== targetIdentity.email
      ) {
        throw new HttpsError(
          "failed-precondition",
          "The Auth email no longer matches this invitation. Replace the pending email instead."
        );
      }
      const invitationVersion = storedInvitationVersion(pending.invitation, false) + 1;
      const nextStaff: StoredStaffRecord = {
        ...pending.staff,
        uid: targetUid,
        invitationStatus: "pending",
      };

      await assertExactCanonicalOwner(db, transaction, tenantId, tenant.ownerUid);

      writePreparedRoot(transaction, targetRootRef, preparedRoot, preparedRoot.create ? 1 : 0);
      transaction.update(staffRef, {
        uid: targetUid,
        invitationStatus: "pending",
        updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.set(mirrorRef, membershipMirrorData(
        tenantId,
        tenant,
        nextStaff,
        mirrorSnapshot.exists ? mirrorSnapshot.data() as StoredMirrorRecord : undefined,
        false
      ));
      transaction.update(invitationRef, {
        invitationVersion,
        invitationTokenHash: null,
        invitationTokenKeyVersion: null,
        invitationIssuedAt: null,
        invitationExpiresAt: null,
        invitationTokenUsedAt: null,
        invitationStatus: "pending",
        invitedEmail: targetIdentity.email,
        invitedBy: auth.uid,
        latestDeliveryId: deliveryId,
        visibleAcceptanceAllowed: pending.invitation.visibleAcceptanceAllowed === true,
        updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.create(
        db.collection("email_deliveries").doc(deliveryId),
        deliveryData(
          deliveryId,
          tenantId,
          targetUid,
          recipient.current.recipientHash,
          recipient.current.keyVersion,
          invitationVersion,
          invitationRef.path
        )
      );
      transaction.create(
        db.collection("tenants").doc(tenantId).collection("audit_logs").doc(deliveryId),
        auditData(tenantId, "staff_invitation_resent", auth.uid, targetUid, requestId, {
          invitationVersion,
        })
      );
      return {
        tenantId,
        uid: targetUid,
        invitationStatus: "pending",
        invitationVersion,
        delivery: {deliveryId, status: "pending_enqueue"},
      };
    });
    await dispatchInvitationDelivery(db, deliveryId, secret);
    return result;
  }
);

export const replacePendingStaffEmail = onCall<
  ReplacePendingStaffEmailRequest,
  Promise<InvitationMutationResponse>
>(
  {secrets: [STAFF_INVITATION_HMAC_SECRET, EMAIL_RECIPIENT_HMAC_KEYRING]},
  async (
    request: CallableRequest<ReplacePendingStaffEmailRequest>
  ): Promise<InvitationMutationResponse> => {
    const auth = requireAuthenticatedUser(request, {allowUnverified: true});
    const data = requireObject(request.data);
    const tenantId = requireDocumentId(data.tenantId, "tenantId");
    const oldUid = requireDocumentId(data.uid, "uid");
    const correctedEmail = normalizeEmail(data.email);
    const requestId = requireRequestId(data.requestId);
    const db = getFirestore();

    const preliminaryContext = await preauthorizeTenantAdministrator(db, request, tenantId);
    const secret = invitationHmacSecretValue();
    const deliveryId = operationDocumentId(
      auth.uid,
      "replacePendingStaffEmail",
      tenantId,
      requestId
    );
    const operationInput = {oldUid, correctedEmail};
    const reservation = await reserveStaffIdentityOperation<
      typeof operationInput,
      InvitationMutationResponse
    >(db, {
      operationId: deliveryId,
      actorUid: auth.uid,
      operation: "replacePendingStaffEmail",
      tenantId,
      requestId,
      input: operationInput,
      email: correctedEmail,
      displayName: "",
    });
    if (reservation.status === "completed" && reservation.result) {
      await dispatchInvitationDelivery(db, deliveryId, secret);
      return reservation.result;
    }
    const preliminaryTenant = preliminaryContext.tenant as StoredTenantRecord;
    const preliminaryTenantRef = db.collection("tenants").doc(tenantId);
    const [preliminaryStaff, preliminaryInvitation] = await db.getAll(
      preliminaryTenantRef.collection("staff").doc(oldUid),
      preliminaryTenantRef.collection("staff_invitations").doc(oldUid)
    );
    requirePendingStaffInvitation(
      oldUid,
      tenantId,
      preliminaryTenant,
      preliminaryStaff.exists ? preliminaryStaff.data() as StoredStaffRecord : undefined,
      preliminaryInvitation.exists ?
        preliminaryInvitation.data() as StoredInvitationRecord : undefined
    );
    // Repeat these reads transactionally below; this preliminary pass prevents
    // creating a replacement Auth identity for an already-invalid request.
    const replacementIdentity = await resolveReservedStaffIdentity(db, reservation);
    const recipient = bindRecipientPrivacy(
      replacementIdentity.email,
      parseRecipientHmacKeyring(EMAIL_RECIPIENT_HMAC_KEYRING.value())
    );
    if (!recipient) {
      throw new HttpsError("failed-precondition", "The target Auth email is invalid.");
    }
    if (replacementIdentity.uid === oldUid) {
      throw new HttpsError(
        "invalid-argument",
        "The corrected email already belongs to this identity."
      );
    }
    const result = await finalizeReservedStaffOperation(
      db,
      reservation,
      replacementIdentity,
      async (transaction): Promise<InvitationMutationResponse> => {
      const actorContext = await requireTenantMember(
        db, request, tenantId, STAFF_MANAGEMENT_ROLES, transaction
      );
      const tenant = actorContext.tenant as StoredTenantRecord;
      const tenantRef = db.collection("tenants").doc(tenantId);
      const oldRootRef = db.collection("users").doc(oldUid);
      const oldStaffRef = tenantRef.collection("staff").doc(oldUid);
      const oldMirrorRef = oldRootRef.collection("tenant_memberships").doc(tenantId);
      const oldInvitationRef = tenantRef.collection("staff_invitations").doc(oldUid);
      const replacementRootRef = db.collection("users").doc(replacementIdentity.uid);
      const replacementStaffRef = tenantRef.collection("staff").doc(replacementIdentity.uid);
      const replacementMirrorRef = replacementRootRef
        .collection("tenant_memberships").doc(tenantId);
      const replacementInvitationRef = tenantRef
        .collection("staff_invitations").doc(replacementIdentity.uid);
      const snapshots = await transaction.getAll(
        oldRootRef,
        oldStaffRef,
        oldMirrorRef,
        oldInvitationRef,
        replacementRootRef,
        replacementStaffRef,
        replacementMirrorRef,
        replacementInvitationRef
      );
      const oldPending = requirePendingStaffInvitation(
        oldUid,
        tenantId,
        tenant,
        snapshots[1].exists ? snapshots[1].data() as StoredStaffRecord : undefined,
        snapshots[3].exists ? snapshots[3].data() as StoredInvitationRecord : undefined
      );
      const replacementPreparedRoot = prepareTargetRoot(
        snapshots[4],
        replacementIdentity,
        true
      );
      if (snapshots[5].exists) {
        throw new HttpsError(
          "already-exists",
          "The corrected identity already has a membership in this tenant."
        );
      }
      const priorReplacementInvitation = snapshots[7].exists ?
        snapshots[7].data() as StoredInvitationRecord :
        undefined;
      const invitationVersion = storedInvitationVersion(
        priorReplacementInvitation,
        true
      ) + 1;
      const identityProvisioningOperationId = replacementIdentity.newlyCreated ?
        deliveryId : ownedProvisioningOperation(
          priorReplacementInvitation,
          replacementIdentity.uid
        );
      const replacementStaff: StoredStaffRecord = {
        uid: replacementIdentity.uid,
        email: replacementIdentity.email,
        name: oldPending.staff.name ?? replacementIdentity.displayName,
        phone: oldPending.staff.phone ?? "",
        role: oldPending.staff.role,
        status: "pending",
        invitationStatus: "pending",
      };

      await assertExactCanonicalOwner(db, transaction, tenantId, tenant.ownerUid);

      writeExistingRootMembershipDelta(transaction, oldRootRef, snapshots[0], -1);
      transaction.delete(oldStaffRef);
      transaction.delete(oldMirrorRef);
      transaction.update(oldInvitationRef, {
        invitationStatus: "cancelled",
        invitationTokenUsedAt: FieldValue.serverTimestamp(),
        cancelledAt: FieldValue.serverTimestamp(),
        cancelledBy: auth.uid,
        cancellationReason: "email_replaced",
        replacedByUid: replacementIdentity.uid,
        updatedAt: FieldValue.serverTimestamp(),
      });
      scheduleCancelledIdentityCleanup(db, transaction, {
        actorUid: auth.uid,
        tenantId,
        targetUid: oldUid,
        requestId,
        source: "email_replaced",
        invitation: oldPending.invitation,
      });

      writePreparedRoot(transaction, replacementRootRef, replacementPreparedRoot, 1);
      transaction.create(replacementStaffRef, {
        ...replacementStaff,
        createdAt: FieldValue.serverTimestamp(),
        joinedAt: null,
        updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.set(replacementMirrorRef, membershipMirrorData(
        tenantId,
        tenant,
        replacementStaff,
        snapshots[6].exists ? snapshots[6].data() as StoredMirrorRecord : undefined,
        false
      ));
      transaction.set(replacementInvitationRef, {
        uid: replacementIdentity.uid,
        tenantId,
        invitationVersion,
        invitationTokenHash: null,
        invitationTokenKeyVersion: null,
        invitationIssuedAt: null,
        invitationExpiresAt: null,
        invitationTokenUsedAt: null,
        invitationStatus: "pending",
        invitedEmail: replacementIdentity.email,
        invitedBy: auth.uid,
        latestDeliveryId: deliveryId,
        visibleAcceptanceAllowed: !replacementIdentity.newlyCreated &&
          replacementIdentity.emailVerified,
        identityOwnedByInvitation: identityProvisioningOperationId !== undefined,
        identityProvisioningOperationId: identityProvisioningOperationId ?? null,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.create(
        db.collection("email_deliveries").doc(deliveryId),
        deliveryData(
          deliveryId,
          tenantId,
          replacementIdentity.uid,
          recipient.current.recipientHash,
          recipient.current.keyVersion,
          invitationVersion,
          replacementInvitationRef.path
        )
      );
      transaction.create(
        tenantRef.collection("audit_logs").doc(deliveryId),
        auditData(
          tenantId,
          "pending_staff_email_replaced",
          auth.uid,
          oldUid,
          requestId,
          {
            replacementUid: replacementIdentity.uid,
            recipientHash: recipient.current.recipientHash,
            recipientHashKeyVersion: recipient.current.keyVersion,
            invitationVersion,
          }
        )
      );
      return {
        tenantId,
        uid: replacementIdentity.uid,
        invitationStatus: "pending",
        invitationVersion,
        delivery: {deliveryId, status: "pending_enqueue"},
      };
      }
    );
    await dispatchInvitationDelivery(db, deliveryId, secret);
    return result;
  }
);

export const cancelTenantInvitation = onCall<
  CancelTenantInvitationRequest,
  Promise<InvitationMutationResponse>
>(async (
  request: CallableRequest<CancelTenantInvitationRequest>
): Promise<InvitationMutationResponse> => {
  const auth = requireAuthenticatedUser(request, {allowUnverified: true});
  const data = requireObject(request.data);
  const tenantId = requireDocumentId(data.tenantId, "tenantId");
  const targetUid = requireDocumentId(data.uid, "uid");
  const reason = requireCancellationReason(data.reason);
  const requestId = requireRequestId(data.requestId);
  const db = getFirestore();

  await preauthorizeTenantAdministrator(db, request, tenantId);
  return runIdempotentFirestoreTransaction(db, {
    actorUid: auth.uid,
    operation: "cancelTenantInvitation",
    tenantId,
    requestId,
    input: {targetUid, reason},
  }, async (transaction) => {
    const actorContext = await requireTenantMember(
      db, request, tenantId, STAFF_MANAGEMENT_ROLES, transaction
    );
    const tenant = actorContext.tenant as StoredTenantRecord;
    const tenantRef = db.collection("tenants").doc(tenantId);
    const targetRootRef = db.collection("users").doc(targetUid);
    const staffRef = tenantRef.collection("staff").doc(targetUid);
    const mirrorRef = targetRootRef.collection("tenant_memberships").doc(tenantId);
    const invitationRef = tenantRef.collection("staff_invitations").doc(targetUid);
    const [rootSnapshot, staffSnapshot, mirrorSnapshot, invitationSnapshot] =
      await transaction.getAll(targetRootRef, staffRef, mirrorRef, invitationRef);
    const pending = requirePendingStaffInvitation(
      targetUid,
      tenantId,
      tenant,
      staffSnapshot.exists ? staffSnapshot.data() as StoredStaffRecord : undefined,
      invitationSnapshot.exists ? invitationSnapshot.data() as StoredInvitationRecord : undefined
    );
    const invitationVersion = storedInvitationVersion(pending.invitation, false);

    await assertExactCanonicalOwner(db, transaction, tenantId, tenant.ownerUid);

    writeExistingRootMembershipDelta(transaction, targetRootRef, rootSnapshot, -1);
    transaction.delete(staffRef);
    if (mirrorSnapshot.exists) transaction.delete(mirrorRef);
    transaction.update(invitationRef, {
      invitationStatus: "cancelled",
      invitationTokenUsedAt: FieldValue.serverTimestamp(),
      cancelledAt: FieldValue.serverTimestamp(),
      cancelledBy: auth.uid,
      cancellationReason: reason,
      updatedAt: FieldValue.serverTimestamp(),
    });
    scheduleCancelledIdentityCleanup(db, transaction, {
      actorUid: auth.uid,
      tenantId,
      targetUid,
      requestId,
      source: "invitation_cancelled",
      invitation: pending.invitation,
    });
    const auditId = operationDocumentId(
      auth.uid,
      "cancelTenantInvitation",
      tenantId,
      requestId
    );
    transaction.create(
      tenantRef.collection("audit_logs").doc(auditId),
      auditData(tenantId, "tenant_invitation_cancelled", auth.uid, targetUid, requestId, {
        reason,
        invitationVersion,
      })
    );
    return {
      tenantId,
      uid: targetUid,
      invitationStatus: "cancelled",
      invitationVersion,
      delivery: null,
    };
  });
});
