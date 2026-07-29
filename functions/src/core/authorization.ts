import {Firestore, Transaction} from "firebase-admin/firestore";
import {CallableRequest, HttpsError} from "firebase-functions/v2/https";
import {
  CanonicalStaffRecord,
  isTenantRole,
  PlatformAuthorizationContext,
  RootUserRecord,
  TenantAuthorizationContext,
  TenantRecord,
  TenantRole,
} from "./model";
import {requireDocumentId} from "./validation";

type AuthContext = NonNullable<CallableRequest<unknown>["auth"]>;

export interface AuthenticatedUserOptions {
  allowUnverified?: boolean;
}

export function requireAppCheckedPublic(request: CallableRequest<unknown>): void {
  if (!request.app) {
    throw new HttpsError("failed-precondition", "App verification is required.");
  }
}

export function requireAuthenticatedUser<T>(
  request: CallableRequest<T>,
  options: AuthenticatedUserOptions = {}
): AuthContext {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }
  if (!options.allowUnverified && request.auth.token.email_verified !== true) {
    throw new HttpsError("permission-denied", "A verified email is required.");
  }
  return request.auth;
}

export function assertActiveRootUser(
  uid: string,
  rawUser: RootUserRecord | undefined
): RootUserRecord {
  if (!rawUser || rawUser.globalStatus !== "active") {
    throw new HttpsError("permission-denied", "This account is not active.");
  }
  return rawUser;
}

export function assertVerifiedTenantApplicant(
  uid: string,
  rawUser: RootUserRecord | undefined
): RootUserRecord {
  const user = assertActiveRootUser(uid, rawUser);
  if (user.identityTransition) {
    throw new HttpsError("aborted", "An identity transition is currently in progress.");
  }
  if (user.accountType !== "tenant_user") {
    throw new HttpsError("permission-denied", "Platform identities cannot join tenants.");
  }
  return user;
}

export function assertTenantMemberDocuments(
  uid: string,
  tenantId: string,
  rawUser: RootUserRecord | undefined,
  rawTenant: TenantRecord | undefined,
  rawStaff: CanonicalStaffRecord | undefined,
  allowedRoles?: readonly TenantRole[]
): TenantAuthorizationContext {
  const user = assertActiveRootUser(uid, rawUser);
  if (user.accountType !== "tenant_user") {
    throw new HttpsError("permission-denied", "Platform identities cannot access tenant data.");
  }
  if (!rawTenant || rawTenant.status !== "active") {
    throw new HttpsError("permission-denied", "This tenant is not active.");
  }
  if (!rawStaff || rawStaff.uid !== uid || rawStaff.status !== "active" || !isTenantRole(rawStaff.role)) {
    throw new HttpsError("permission-denied", "An active tenant membership is required.");
  }
  if (allowedRoles && !allowedRoles.includes(rawStaff.role)) {
    throw new HttpsError("permission-denied", "Your tenant role cannot perform this operation.");
  }
  return {
    uid,
    tenantId,
    user,
    tenant: rawTenant,
    staff: {...rawStaff, role: rawStaff.role},
  };
}

export function assertPlatformAdminDocuments(
  uid: string,
  platformRole: unknown,
  rawUser: RootUserRecord | undefined
): PlatformAuthorizationContext {
  const user = assertActiveRootUser(uid, rawUser);
  if (platformRole !== "superAdmin" || user.accountType !== "platform_admin") {
    throw new HttpsError("permission-denied", "Platform administrator access is required.");
  }
  return {uid, user};
}

export async function requireVerifiedTenantApplicant<T>(
  db: Firestore,
  request: CallableRequest<T>,
  transaction?: Transaction
): Promise<{uid: string; user: RootUserRecord}> {
  const auth = requireAuthenticatedUser(request);
  const userRef = db.collection("users").doc(auth.uid);
  const userSnapshot = transaction ? await transaction.get(userRef) : await userRef.get();
  return {
    uid: auth.uid,
    user: assertVerifiedTenantApplicant(
      auth.uid,
      userSnapshot.exists ? userSnapshot.data() as RootUserRecord : undefined
    ),
  };
}

export async function requireTenantMember<T>(
  db: Firestore,
  request: CallableRequest<T>,
  tenantIdValue: unknown,
  allowedRoles?: readonly TenantRole[],
  transaction?: Transaction
): Promise<TenantAuthorizationContext> {
  const auth = requireAuthenticatedUser(request, {allowUnverified: true});
  const tenantId = requireDocumentId(tenantIdValue, "tenantId");
  const userRef = db.collection("users").doc(auth.uid);
  const tenantRef = db.collection("tenants").doc(tenantId);
  const staffRef = tenantRef.collection("staff").doc(auth.uid);
  const [userSnapshot, tenantSnapshot, staffSnapshot] = transaction ?
    await transaction.getAll(userRef, tenantRef, staffRef) :
    await db.getAll(userRef, tenantRef, staffRef);

  return assertTenantMemberDocuments(
    auth.uid,
    tenantId,
    userSnapshot.exists ? userSnapshot.data() as RootUserRecord : undefined,
    tenantSnapshot.exists ? tenantSnapshot.data() as TenantRecord : undefined,
    staffSnapshot.exists ? staffSnapshot.data() as CanonicalStaffRecord : undefined,
    allowedRoles
  );
}

export async function requirePlatformAdmin<T>(
  db: Firestore,
  request: CallableRequest<T>,
  transaction?: Transaction
): Promise<PlatformAuthorizationContext> {
  const auth = requireAuthenticatedUser(request, {allowUnverified: true});
  const userRef = db.collection("users").doc(auth.uid);
  const userSnapshot = transaction ? await transaction.get(userRef) : await userRef.get();
  return assertPlatformAdminDocuments(
    auth.uid,
    auth.token.platformRole,
    userSnapshot.exists ? userSnapshot.data() as RootUserRecord : undefined
  );
}
