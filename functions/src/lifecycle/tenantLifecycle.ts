import {
  FieldValue,
  getFirestore,
} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {
  assertVerifiedTenantApplicant,
  requireAuthenticatedUser,
  requirePlatformAdmin,
} from "../core/authorization";
import {buildIdempotencyIdentity, runIdempotentFirestoreTransaction} from "../core/idempotency";
import {
  CanonicalStaffRecord,
  RootUserRecord,
  TENANT_STATUSES,
  TenantRecord,
  TenantStatus,
} from "../core/model";
import {
  optionalString,
  requireDocumentId,
  requireObject,
  requireRequestId,
} from "../core/validation";
import {resolveTenantLimits} from "../tenants/limits";

const TRANSITIONS: Readonly<Record<TenantStatus, readonly TenantStatus[]>> = {
  active: ["suspended", "archived"],
  suspended: ["active", "archived"],
  archived: [],
};

export interface SetTenantLifecycleRequest {
  tenantId?: unknown;
  status?: unknown;
  reason?: unknown;
  requestId?: unknown;
}

export interface SetTenantLifecycleResponse {
  tenantId: string;
  previousStatus: TenantStatus;
  status: TenantStatus;
  fanoutOperationId: string;
}

export function requireTenantStatus(value: unknown): TenantStatus {
  if (typeof value !== "string" || !TENANT_STATUSES.includes(value as TenantStatus)) {
    throw new HttpsError("invalid-argument", "status is not a supported tenant status.");
  }
  return value as TenantStatus;
}

export function assertTenantLifecycleTransition(
  currentStatus: TenantStatus,
  targetStatus: TenantStatus
): void {
  if (!TRANSITIONS[currentStatus].includes(targetStatus)) {
    throw new HttpsError(
      "failed-precondition",
      `Tenant lifecycle cannot transition from ${currentStatus} to ${targetStatus}.`
    );
  }
}

export function isTenantActivation(
  currentStatus: TenantStatus,
  targetStatus: TenantStatus
): boolean {
  return currentStatus !== "active" && targetStatus === "active";
}

export function assertOwnedActiveTenantCapacity(
  existingActiveOwnedTenants: number,
  maximumActiveOwnedTenants: number
): void {
  if (existingActiveOwnedTenants >= maximumActiveOwnedTenants) {
    throw new HttpsError(
      "resource-exhausted",
      "The tenant owner has reached the active owned tenant limit.",
      {
        violation: "max_owned_active_tenants",
        limit: maximumActiveOwnedTenants,
      }
    );
  }
}

function advisoryCounter(value: unknown): number {
  return Number.isSafeInteger(value) && (value as number) >= 0 ? value as number : 0;
}

export function lifecycleOwnerCounterUpdates(
  owner: RootUserRecord,
  previousStatus: TenantStatus,
  targetStatus: TenantStatus
): Pick<RootUserRecord, "ownedTenantCount" | "ownedActiveTenantCount"> | undefined {
  const updates: Pick<RootUserRecord, "ownedTenantCount" | "ownedActiveTenantCount"> = {};
  if (previousStatus !== "archived" && targetStatus === "archived") {
    updates.ownedTenantCount = Math.max(0, advisoryCounter(owner.ownedTenantCount) - 1);
  }
  if (previousStatus === "active" && targetStatus !== "active") {
    updates.ownedActiveTenantCount = Math.max(
      0,
      advisoryCounter(owner.ownedActiveTenantCount) - 1
    );
  } else if (isTenantActivation(previousStatus, targetStatus)) {
    updates.ownedActiveTenantCount = advisoryCounter(owner.ownedActiveTenantCount) + 1;
  }
  return Object.keys(updates).length > 0 ? updates : undefined;
}

function currentTenantStatus(rawTenant: TenantRecord | undefined): TenantStatus {
  if (!rawTenant || !rawTenant.status || !TENANT_STATUSES.includes(rawTenant.status)) {
    throw new HttpsError("not-found", "The canonical tenant does not exist or is invalid.");
  }
  return rawTenant.status;
}

export function assertActivationOwnerDocuments(
  ownerUid: string,
  rawOwner: RootUserRecord | undefined,
  rawOwnerStaff: CanonicalStaffRecord | undefined
): void {
  assertVerifiedTenantApplicant(ownerUid, rawOwner);
  assertExactCanonicalOwnerDocuments(ownerUid, [{
    documentId: ownerUid,
    data: rawOwnerStaff,
  }]);
}

export interface CanonicalOwnerDocument {
  documentId: string;
  data: CanonicalStaffRecord | undefined;
}

export function assertExactCanonicalOwnerDocuments(
  ownerUid: string,
  ownerDocuments: readonly CanonicalOwnerDocument[]
): CanonicalStaffRecord {
  if (ownerDocuments.length !== 1) {
    throw new HttpsError(
      "failed-precondition",
      "The tenant must have exactly one active canonical owner."
    );
  }
  const ownerDocument = ownerDocuments[0];
  const owner = ownerDocument.data;
  if (
    !owner ||
    ownerDocument.documentId !== ownerUid ||
    owner.uid !== ownerUid ||
    owner.role !== "owner" ||
    owner.status !== "active"
  ) {
    throw new HttpsError(
      "failed-precondition",
      "The tenant must have exactly one active canonical owner."
    );
  }
  return owner;
}

export interface TenantLifecycleAuditInput {
  tenantId: string;
  previousStatus: TenantStatus;
  targetStatus: TenantStatus;
  actorUid: string;
  requestId: string;
  reason: string | undefined;
  fanoutOperationId: string;
}

export function tenantReadableLifecycleAuditData(
  input: TenantLifecycleAuditInput
): Record<string, unknown> {
  return {
    tenantId: input.tenantId,
    eventType: "tenant_lifecycle_changed",
    fromStatus: input.previousStatus,
    toStatus: input.targetStatus,
    actorType: "platform_admin",
    fanoutOperationId: input.fanoutOperationId,
  };
}

export function privilegedLifecycleAuditData(
  input: TenantLifecycleAuditInput
): Record<string, unknown> {
  return {
    tenantId: input.tenantId,
    eventType: "tenant_lifecycle_changed",
    fromStatus: input.previousStatus,
    toStatus: input.targetStatus,
    actorUid: input.actorUid,
    requestId: input.requestId,
    reason: input.reason ?? null,
    fanoutOperationId: input.fanoutOperationId,
  };
}

export const setTenantLifecycle = onCall<
  SetTenantLifecycleRequest,
  Promise<SetTenantLifecycleResponse>
>(async (
  request: CallableRequest<SetTenantLifecycleRequest>
): Promise<SetTenantLifecycleResponse> => {
  const auth = requireAuthenticatedUser(request, {allowUnverified: true});
  const data = requireObject(request.data);
  const tenantId = requireDocumentId(data.tenantId, "tenantId");
  const targetStatus = requireTenantStatus(data.status);
  const reason = optionalString(data.reason, "reason", {maxLength: 1000});
  const requestId = requireRequestId(data.requestId);
  const db = getFirestore();
  const operationIdentity = buildIdempotencyIdentity(
    auth.uid,
    "setTenantLifecycle",
    tenantId,
    requestId
  );

  return runIdempotentFirestoreTransaction(db, {
    actorUid: auth.uid,
    operation: "setTenantLifecycle",
    tenantId,
    requestId,
    input: {tenantId, status: targetStatus, reason: reason ?? null},
  }, async (transaction) => {
    await requirePlatformAdmin(db, request, transaction);
    const tenantRef = db.collection("tenants").doc(tenantId);
    const tenantSnapshot = await transaction.get(tenantRef);
    const tenant = tenantSnapshot.exists ? tenantSnapshot.data() as TenantRecord : undefined;
    const previousStatus = currentTenantStatus(tenant);
    assertTenantLifecycleTransition(previousStatus, targetStatus);

    const ownerUid = requireDocumentId(tenant?.ownerUid, "tenant.ownerUid");
    let canonicalOwnerStaff: CanonicalStaffRecord | undefined;
    if (targetStatus !== "archived") {
      const canonicalOwnersSnapshot = await transaction.get(
        tenantRef.collection("staff")
          .where("role", "==", "owner")
          .limit(2)
      );
      canonicalOwnerStaff = assertExactCanonicalOwnerDocuments(
        ownerUid,
        canonicalOwnersSnapshot.docs.map((document) => ({
          documentId: document.id,
          data: document.data() as CanonicalStaffRecord,
        }))
      );
    }
    const ownerRef = db.collection("users").doc(ownerUid);
    const ownerMirrorRef = ownerRef.collection("tenant_memberships").doc(tenantId);
    const limitsRef = db.collection("platform_config").doc("limits");
    const [ownerSnapshot, ownerMirrorSnapshot, limitsSnapshot] =
      await transaction.getAll(ownerRef, ownerMirrorRef, limitsRef);
    const owner = ownerSnapshot.exists ? ownerSnapshot.data() as RootUserRecord : undefined;

    if (isTenantActivation(previousStatus, targetStatus)) {
      assertActivationOwnerDocuments(
        ownerUid,
        owner,
        canonicalOwnerStaff
      );
      const limits = resolveTenantLimits(
        limitsSnapshot.exists ? limitsSnapshot.data() : undefined
      );
      const activeOwnedSnapshot = await transaction.get(
        db.collection("tenants")
          .where("ownerUid", "==", ownerUid)
          .where("status", "==", "active")
          .limit(Math.max(1, limits.maxOwnedActiveTenantsPerUser))
      );
      assertOwnedActiveTenantCapacity(
        activeOwnedSnapshot.size,
        limits.maxOwnedActiveTenantsPerUser
      );
    }

    const fanoutRef = tenantRef
      .collection("membership_fanout_jobs")
      .doc(operationIdentity.documentId);
    const lifecycleRef = tenantRef
      .collection("lifecycle_history")
      .doc(operationIdentity.documentId);
    const tenantAuditRef = tenantRef
      .collection("audit_logs")
      .doc(operationIdentity.documentId);
    const platformAuditRef = db
      .collection("platform_audit_logs")
      .doc(operationIdentity.documentId);

    transaction.update(tenantRef, {
      status: targetStatus,
      membershipFanoutStatus: "pending",
      membershipFanoutOperationId: operationIdentity.documentId,
      membershipFanoutTargetStatus: targetStatus,
      membershipFanoutUpdatedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.create(fanoutRef, {
      tenantId,
      fromStatus: previousStatus,
      toStatus: targetStatus,
      status: "pending",
      actorUid: auth.uid,
      requestId,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    if (ownerMirrorSnapshot.exists) {
      transaction.update(ownerMirrorRef, {
        tenantStatus: targetStatus,
        mirrorVersion: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    const counterUpdates = owner ? lifecycleOwnerCounterUpdates(
      owner,
      previousStatus,
      targetStatus
    ) : undefined;
    if (ownerSnapshot.exists && counterUpdates) {
      transaction.update(ownerRef, {
        ...counterUpdates,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    const auditInput: TenantLifecycleAuditInput = {
      tenantId,
      previousStatus,
      targetStatus,
      actorUid: auth.uid,
      requestId,
      reason,
      fanoutOperationId: operationIdentity.documentId,
    };
    const privilegedAuditData = {
      ...privilegedLifecycleAuditData(auditInput),
      createdAt: FieldValue.serverTimestamp(),
    };
    const tenantAuditData = {
      ...tenantReadableLifecycleAuditData(auditInput),
      createdAt: FieldValue.serverTimestamp(),
    };
    transaction.create(lifecycleRef, privilegedAuditData);
    transaction.create(tenantAuditRef, tenantAuditData);
    transaction.create(platformAuditRef, privilegedAuditData);

    return {
      tenantId,
      previousStatus,
      status: targetStatus,
      fanoutOperationId: operationIdentity.documentId,
    };
  });
});
