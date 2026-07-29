import {getAuth} from "firebase-admin/auth";
import {
  FieldValue,
  getFirestore,
  Timestamp,
} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {requireAuthenticatedUser} from "../core/authorization";
import {runIdempotentFirestoreTransaction} from "../core/idempotency";
import {RootUserRecord} from "../core/model";
import {
  requireDocumentId,
  requireObject,
  requireRequestId,
} from "../core/validation";
import {assertTenantIdentityTarget} from "./identity";
import {invitationAcceptanceViolation} from "./acceptancePolicy";
import {
  isRecentAuthentication,
  verifyInvitationProof,
} from "./invitationProof";
import {STAFF_INVITATION_HMAC_SECRET, invitationHmacSecretValue} from "./secret";
import {
  assertAdministrativePrincipalAfterMutation,
  assertCanonicalTargetStaff,
  assertExactCanonicalOwner,
  auditData,
  isUnexpiredTimestamp,
  membershipMirrorData,
  operationDocumentId,
} from "./shared";
import {
  StoredInvitationRecord,
  StoredMirrorRecord,
  StoredStaffRecord,
  StoredTenantRecord,
} from "./types";
import {
  normalizeEmail,
  requireInvitationToken,
  requireInvitationVersion,
} from "./validation";

interface AcceptTenantInvitationRequest {
  tenantId?: unknown;
  invitationVersion?: unknown;
  invitationToken?: unknown;
  requestId?: unknown;
}

interface AcceptVisibleTenantInvitationRequest {
  tenantId?: unknown;
  requestId?: unknown;
}

interface AcceptInvitationResponse {
  tenantId: string;
  uid: string;
  role: string;
  membershipStatus: "active";
  invitationStatus: "accepted";
}

interface AcceptanceInput {
  tenantId: string;
  requestId: string;
  invitationVersion?: number;
  invitationToken?: string;
}

async function acceptInvitation(
  request: CallableRequest<unknown>,
  input: AcceptanceInput,
  mode: "token" | "visible",
  secret?: string
): Promise<AcceptInvitationResponse> {
  const auth = requireAuthenticatedUser(request, {allowUnverified: true});
  const now = Timestamp.now();
  if (!isRecentAuthentication(auth.token.auth_time, now.toMillis())) {
    throw new HttpsError(
      "failed-precondition",
      "Recent authentication is required to accept an invitation."
    );
  }
  let currentAuthUser;
  try {
    currentAuthUser = await getAuth().getUser(auth.uid);
  } catch {
    throw new HttpsError("failed-precondition", "The current identity is unavailable.");
  }
  const currentEmail = normalizeEmail(currentAuthUser.email);
  if (currentAuthUser.disabled || !currentEmail) {
    throw new HttpsError("permission-denied", "The current identity cannot accept invitations.");
  }
  if (mode === "visible" && currentAuthUser.emailVerified !== true) {
    throw new HttpsError(
      "permission-denied",
      "A verified email is required for visible invitation acceptance."
    );
  }
  const db = getFirestore();
  const operation = mode === "token" ?
    "acceptTenantInvitation" :
    "acceptVisibleTenantInvitation";

  return runIdempotentFirestoreTransaction(db, {
    actorUid: auth.uid,
    operation,
    tenantId: input.tenantId,
    requestId: input.requestId,
    input: mode === "token" ? {
      invitationVersion: input.invitationVersion,
      invitationToken: input.invitationToken,
    } : {},
  }, async (transaction) => {
    const userRef = db.collection("users").doc(auth.uid);
    const tenantRef = db.collection("tenants").doc(input.tenantId);
    const staffRef = tenantRef.collection("staff").doc(auth.uid);
    const mirrorRef = userRef.collection("tenant_memberships").doc(input.tenantId);
    const invitationRef = tenantRef.collection("staff_invitations").doc(auth.uid);
    const [userSnapshot, tenantSnapshot, staffSnapshot, mirrorSnapshot, invitationSnapshot] =
      await transaction.getAll(userRef, tenantRef, staffRef, mirrorRef, invitationRef);
    if (!userSnapshot.exists) {
      throw new HttpsError("failed-precondition", "The root user does not exist.");
    }
    assertTenantIdentityTarget(
      userSnapshot.data() as RootUserRecord,
      {
        requireActive: true,
        hasPlatformClaim: auth.token.platformRole !== undefined,
      }
    );
    const tenant = tenantSnapshot.exists ?
      tenantSnapshot.data() as StoredTenantRecord :
      undefined;
    if (!tenant || tenant.status !== "active") {
      throw new HttpsError("failed-precondition", "The tenant is not active.");
    }
    const staff = assertCanonicalTargetStaff(
      auth.uid,
      tenant,
      staffSnapshot.exists ? staffSnapshot.data() as StoredStaffRecord : undefined
    );
    const invitation = invitationSnapshot.exists ?
      invitationSnapshot.data() as StoredInvitationRecord :
      undefined;
    if (
      staff.role === "owner" ||
      !invitation ||
      invitation.tenantId !== input.tenantId ||
      typeof invitation.invitedEmail !== "string"
    ) {
      throw new HttpsError("failed-precondition", "The invitation cannot be accepted.");
    }
    const acceptanceViolation = invitationAcceptanceViolation(mode, {
      callerUid: auth.uid,
      invitedUid: typeof invitation.uid === "string" ? invitation.uid : "",
      currentEmail,
      invitedEmail: invitation.invitedEmail.trim().toLowerCase(),
      tenantStatus: tenant.status ?? "",
      membershipStatus: staff.status,
      membershipInvitationStatus: staff.invitationStatus ?? "",
      invitationStatus: typeof invitation.invitationStatus === "string" ?
        invitation.invitationStatus : "",
      invitationConsumed: invitation.invitationTokenUsedAt !== null &&
        invitation.invitationTokenUsedAt !== undefined,
      emailVerified: currentAuthUser.emailVerified === true,
      visibleAcceptanceAllowed: invitation.visibleAcceptanceAllowed === true,
    });
    if (acceptanceViolation) {
      throw new HttpsError("permission-denied", "The invitation cannot be accepted.", {
        violation: acceptanceViolation,
      });
    }

    if (mode === "token") {
      if (
        invitation.invitationVersion !== input.invitationVersion ||
        typeof invitation.invitationTokenHash !== "string" ||
        !isUnexpiredTimestamp(invitation.invitationExpiresAt, now) ||
        !secret ||
        !verifyInvitationProof({
          tenantId: input.tenantId,
          uid: auth.uid,
          invitedEmail: currentEmail,
          invitationVersion: input.invitationVersion as number,
        }, input.invitationToken as string, invitation.invitationTokenHash,
        invitation.invitationTokenKeyVersion, secret)
      ) {
        throw new HttpsError("permission-denied", "The invitation proof is invalid.");
      }
    }

    const nextStaff: StoredStaffRecord = {
      ...staff,
      uid: auth.uid,
      status: "active",
      invitationStatus: "accepted",
    };
    await assertExactCanonicalOwner(
      db,
      transaction,
      input.tenantId,
      tenant.ownerUid
    );
    await assertAdministrativePrincipalAfterMutation(
      db,
      transaction,
      input.tenantId,
      tenant.ownerUid,
      {uid: auth.uid, role: staff.role, status: "active"}
    );
    transaction.update(userRef, {updatedAt: FieldValue.serverTimestamp()});
    transaction.update(staffRef, {
      uid: auth.uid,
      status: "active",
      invitationStatus: "accepted",
      joinedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(mirrorRef, membershipMirrorData(
      input.tenantId,
      tenant,
      nextStaff,
      mirrorSnapshot.exists ? mirrorSnapshot.data() as StoredMirrorRecord : undefined,
      true
    ));
    transaction.update(invitationRef, {
      invitationStatus: "accepted",
      invitationTokenUsedAt: FieldValue.serverTimestamp(),
      acceptedAt: FieldValue.serverTimestamp(),
      acceptedBy: auth.uid,
      acceptanceMode: mode,
      updatedAt: FieldValue.serverTimestamp(),
    });
    const auditId = operationDocumentId(
      auth.uid,
      operation,
      input.tenantId,
      input.requestId
    );
    transaction.create(
      tenantRef.collection("audit_logs").doc(auditId),
      auditData(
        input.tenantId,
        mode === "token" ?
          "tenant_invitation_accepted" :
          "visible_tenant_invitation_accepted",
        auth.uid,
        auth.uid,
        input.requestId,
        {role: staff.role, acceptanceMode: mode}
      )
    );
    return {
      tenantId: input.tenantId,
      uid: auth.uid,
      role: staff.role,
      membershipStatus: "active",
      invitationStatus: "accepted",
    };
  });
}

export const acceptTenantInvitation = onCall<
  AcceptTenantInvitationRequest,
  Promise<AcceptInvitationResponse>
>(
  {secrets: [STAFF_INVITATION_HMAC_SECRET]},
  async (
    request: CallableRequest<AcceptTenantInvitationRequest>
  ): Promise<AcceptInvitationResponse> => {
    const data = requireObject(request.data);
    const tenantId = requireDocumentId(data.tenantId, "tenantId");
    const invitationVersion = requireInvitationVersion(data.invitationVersion);
    const invitationToken = requireInvitationToken(data.invitationToken);
    const requestId = requireRequestId(data.requestId);
    return acceptInvitation(
      request,
      {tenantId, invitationVersion, invitationToken, requestId},
      "token",
      invitationHmacSecretValue()
    );
  }
);

export const acceptVisibleTenantInvitation = onCall<
  AcceptVisibleTenantInvitationRequest,
  Promise<AcceptInvitationResponse>
>(async (
  request: CallableRequest<AcceptVisibleTenantInvitationRequest>
): Promise<AcceptInvitationResponse> => {
  const data = requireObject(request.data);
  const tenantId = requireDocumentId(data.tenantId, "tenantId");
  const requestId = requireRequestId(data.requestId);
  return acceptInvitation(
    request,
    {tenantId, requestId},
    "visible"
  );
});
