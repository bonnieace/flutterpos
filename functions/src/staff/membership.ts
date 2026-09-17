import {FieldValue, getFirestore} from "firebase-admin/firestore";
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
import {
  assertAdministrativePrincipalAfterMutation,
  assertCanonicalTargetStaff,
  assertOwnerMutation,
  auditData,
  membershipMirrorData,
  operationDocumentId,
  preauthorizeTenantAdministrator,
  prepareExistingTargetRoot,
  readAuthIdentityIfExists,
  STAFF_MANAGEMENT_ROLES,
  writePreparedRoot,
} from "./shared";
import {
  StoredMirrorRecord,
  StoredStaffRecord,
  StoredTenantRecord,
} from "./types";
import {
  normalizePhone,
  normalizeStaffName,
  requireSettableMembershipStatus,
  requireStaffRole,
} from "./validation";
import {staffSearchFields} from "./search";

interface UpdateStaffUserRequest {
  tenantId?: unknown;
  uid?: unknown;
  name?: unknown;
  phone?: unknown;
  role?: unknown;
  requestId?: unknown;
}

interface SetStaffStatusRequest {
  tenantId?: unknown;
  uid?: unknown;
  status?: unknown;
  requestId?: unknown;
}

interface StaffMutationResponse {
  tenantId: string;
  uid: string;
  role: string;
  status: string;
}

export const updateStaffUser = onCall<
  UpdateStaffUserRequest,
  Promise<StaffMutationResponse>
>(async (
  request: CallableRequest<UpdateStaffUserRequest>
): Promise<StaffMutationResponse> => {
  const auth = requireAuthenticatedUser(request, {allowUnverified: true});
  const data = requireObject(request.data);
  const tenantId = requireDocumentId(data.tenantId, "tenantId");
  const targetUid = requireDocumentId(data.uid, "uid");
  const name = normalizeStaffName(data.name);
  const phone = normalizePhone(data.phone);
  const role = requireStaffRole(data.role);
  const requestId = requireRequestId(data.requestId);
  const db = getFirestore();

  await preauthorizeTenantAdministrator(db, request, tenantId);
  const targetIdentity = await readAuthIdentityIfExists(targetUid);

  return runIdempotentFirestoreTransaction(db, {
    actorUid: auth.uid,
    operation: "updateStaffUser",
    tenantId,
    requestId,
    input: {targetUid, name, phone, role},
  }, async (transaction) => {
    const actorContext = await requireTenantMember(
      db,
      request,
      tenantId,
      STAFF_MANAGEMENT_ROLES,
      transaction
    );
    const tenant = actorContext.tenant as StoredTenantRecord;
    const targetRootRef = db.collection("users").doc(targetUid);
    const targetStaffRef = db.collection("tenants").doc(tenantId)
      .collection("staff").doc(targetUid);
    const targetMirrorRef = targetRootRef.collection("tenant_memberships").doc(tenantId);
    const [rootSnapshot, staffSnapshot, mirrorSnapshot] = await transaction.getAll(
      targetRootRef,
      targetStaffRef,
      targetMirrorRef
    );
    const preparedRoot = prepareExistingTargetRoot(rootSnapshot, targetIdentity, false);
    const currentStaff = assertCanonicalTargetStaff(
      targetUid,
      tenant,
      staffSnapshot.exists ? staffSnapshot.data() as StoredStaffRecord : undefined
    );
    assertOwnerMutation(tenant, targetUid, currentStaff.role, role, currentStaff.status);
    await assertAdministrativePrincipalAfterMutation(db, transaction, tenantId, tenant.ownerUid, {
      uid: targetUid,
      role,
      status: currentStaff.status,
    });

    const nextStaff: StoredStaffRecord = {
      ...currentStaff,
      uid: targetUid,
      name,
      phone,
      role,
    };
    writePreparedRoot(
      transaction,
      targetRootRef,
      preparedRoot,
      preparedRoot.create ? 1 : 0
    );
    transaction.update(targetStaffRef, {
      uid: targetUid,
      name,
      phone,
      role,
      ...staffSearchFields(name, currentStaff.email ?? ""),
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(targetMirrorRef, membershipMirrorData(
      tenantId,
      tenant,
      nextStaff,
      mirrorSnapshot.exists ? mirrorSnapshot.data() as StoredMirrorRecord : undefined,
      false
    ));
    const auditId = operationDocumentId(auth.uid, "updateStaffUser", tenantId, requestId);
    transaction.create(
      db.collection("tenants").doc(tenantId).collection("audit_logs").doc(auditId),
      auditData(tenantId, "staff_updated", auth.uid, targetUid, requestId, {
        role,
      })
    );
    return {tenantId, uid: targetUid, role, status: currentStaff.status};
  });
});

export const setStaffStatus = onCall<SetStaffStatusRequest, Promise<StaffMutationResponse>>(
  async (request: CallableRequest<SetStaffStatusRequest>): Promise<StaffMutationResponse> => {
    const auth = requireAuthenticatedUser(request, {allowUnverified: true});
    const data = requireObject(request.data);
    const tenantId = requireDocumentId(data.tenantId, "tenantId");
    const targetUid = requireDocumentId(data.uid, "uid");
    const status = requireSettableMembershipStatus(data.status);
    const requestId = requireRequestId(data.requestId);
    const db = getFirestore();

    await preauthorizeTenantAdministrator(db, request, tenantId);
    const targetIdentity = await readAuthIdentityIfExists(targetUid);

    return runIdempotentFirestoreTransaction(db, {
      actorUid: auth.uid,
      operation: "setStaffStatus",
      tenantId,
      requestId,
      input: {targetUid, status},
    }, async (transaction) => {
      const actorContext = await requireTenantMember(
        db,
        request,
        tenantId,
        STAFF_MANAGEMENT_ROLES,
        transaction
      );
      const tenant = actorContext.tenant as StoredTenantRecord;
      const targetRootRef = db.collection("users").doc(targetUid);
      const targetStaffRef = db.collection("tenants").doc(tenantId)
        .collection("staff").doc(targetUid);
      const targetMirrorRef = targetRootRef.collection("tenant_memberships").doc(tenantId);
      const [rootSnapshot, staffSnapshot, mirrorSnapshot] = await transaction.getAll(
        targetRootRef,
        targetStaffRef,
        targetMirrorRef
      );
      const preparedRoot = rootSnapshot.exists ? prepareExistingTargetRoot(
        rootSnapshot,
        targetIdentity,
        status === "active"
      ) : undefined;
      if (!preparedRoot && status === "active") {
        throw new HttpsError(
          "failed-precondition",
          "A membership cannot be activated without its root identity."
        );
      }
      const currentStaff = assertCanonicalTargetStaff(
        targetUid,
        tenant,
        staffSnapshot.exists ? staffSnapshot.data() as StoredStaffRecord : undefined
      );
      if (currentStaff.status === "pending") {
        throw new HttpsError(
          "failed-precondition",
          "Pending invitations must be accepted or cancelled through invitation APIs."
        );
      }
      if (currentStaff.invitationStatus !== "accepted") {
        throw new HttpsError(
          "failed-precondition",
          "Only accepted memberships can be activated or deactivated."
        );
      }
      assertOwnerMutation(tenant, targetUid, currentStaff.role, currentStaff.role, status);
      await assertAdministrativePrincipalAfterMutation(
        db,
        transaction,
        tenantId,
        tenant.ownerUid,
        {
        uid: targetUid,
        role: currentStaff.role,
        status,
        }
      );

      const nextStaff: StoredStaffRecord = {...currentStaff, uid: targetUid, status};
      if (preparedRoot) {
        writePreparedRoot(transaction, targetRootRef, preparedRoot, 0);
      }
      transaction.update(targetStaffRef, {
        uid: targetUid,
        status,
        // **When the door closed**, which is what `drainStrandedSales` measures
        // a stranded sale against: a deactivated cashier may still hand over
        // sales they rang up *before* this instant, and nothing after it. An
        // activation clears it, so a rehired member carries no stale window.
        deactivatedAt: status === "inactive" ?
          FieldValue.serverTimestamp() :
          FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      if (preparedRoot) {
        transaction.set(targetMirrorRef, membershipMirrorData(
          tenantId,
          tenant,
          nextStaff,
          mirrorSnapshot.exists ? mirrorSnapshot.data() as StoredMirrorRecord : undefined,
          false
        ));
      } else if (mirrorSnapshot.exists) {
        transaction.delete(targetMirrorRef);
      }
      const auditId = operationDocumentId(auth.uid, "setStaffStatus", tenantId, requestId);
      transaction.create(
        db.collection("tenants").doc(tenantId).collection("audit_logs").doc(auditId),
        auditData(tenantId, "staff_status_set", auth.uid, targetUid, requestId, {status})
      );
      return {tenantId, uid: targetUid, role: currentStaff.role, status};
    });
  }
);
