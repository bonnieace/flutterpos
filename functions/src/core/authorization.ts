import {Firestore, Transaction} from "firebase-admin/firestore";
import {CallableRequest, HttpsError} from "firebase-functions/v2/https";
import {
  CanonicalStaffRecord,
  isTenantRole,
  PlatformAuthorizationContext,
  RootUserRecord,
  TenantAccessMode,
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
  rawUser: RootUserRecord | undefined,
  authTime?: unknown
): RootUserRecord {
  if (!rawUser || rawUser.globalStatus !== "active") {
    throw new HttpsError("permission-denied", "This account is not active.");
  }
  if (rawUser.authValidAfterSeconds !== undefined && (
    !Number.isSafeInteger(rawUser.authValidAfterSeconds) ||
    typeof authTime !== "number" ||
    !Number.isSafeInteger(authTime) ||
    authTime < rawUser.authValidAfterSeconds
  )) {
    throw new HttpsError(
      "permission-denied",
      "A new sign-in is required for this account."
    );
  }
  return rawUser;
}

export function assertVerifiedTenantApplicant(
  uid: string,
  rawUser: RootUserRecord | undefined,
  authTime?: unknown
): RootUserRecord {
  const user = assertActiveRootUser(uid, rawUser, authTime);
  if (user.identityTransition) {
    throw new HttpsError("aborted", "An identity transition is currently in progress.");
  }
  if (user.accountType !== "tenant_user") {
    throw new HttpsError("permission-denied", "Platform identities cannot join tenants.");
  }
  return user;
}

/** How the tenant's own standing is judged, and against what clock. */
export interface TenantAccessOptions {
  mode?: TenantAccessMode;
  /** Milliseconds since the epoch. Injected so the window is testable. */
  now?: number;
}

/**
 * Whether a tenant record satisfies [mode].
 *
 * **The window is judged here and in `firestore.rules`, and the two must
 * agree.** Rules compare `request.time` against `provisionalUntil`; this
 * compares the same field against the same instant. A `pending` tenant with no
 * `provisionalUntil` is lapsed, never permanently provisional - which is what
 * keeps every tenant written before this field existed behaving as it did.
 */
export function tenantSatisfiesAccessMode(
  tenant: TenantRecord,
  mode: TenantAccessMode,
  now: number
): boolean {
  if (tenant.status === "active") return true;
  if (tenant.status !== "pending") return false;
  if (mode === "approved") return false;
  if (mode === "reading") return true;
  const until = tenant.provisionalUntil;
  return until !== undefined && now < until.toMillis();
}

export function assertTenantMemberDocuments(
  uid: string,
  tenantId: string,
  rawUser: RootUserRecord | undefined,
  rawTenant: TenantRecord | undefined,
  rawStaff: CanonicalStaffRecord | undefined,
  allowedRoles?: readonly TenantRole[],
  authTime?: unknown,
  options?: TenantAccessOptions
): TenantAuthorizationContext {
  const user = assertActiveRootUser(uid, rawUser, authTime);
  if (user.accountType !== "tenant_user") {
    throw new HttpsError("permission-denied", "Platform identities cannot access tenant data.");
  }
  const mode = options?.mode ?? "trading";
  if (!rawTenant || !tenantSatisfiesAccessMode(rawTenant, mode, options?.now ?? Date.now())) {
    // Deliberately one sentence for every reason. Which of "not approved yet",
    // "the trial has run out" and "rejected" applies is a fact about the
    // business that the client reads from the tenant document it is allowed to
    // read; repeating it here would be a second place for the two to disagree.
    throw new HttpsError("permission-denied", "This tenant is not active.");
  }
  if (!rawStaff || rawStaff.uid !== uid || rawStaff.status !== "active" || !isTenantRole(rawStaff.role)) {
    throw new HttpsError("permission-denied", "An active tenant membership is required.");
  }
  if (rawStaff.role === "owner" && rawTenant.ownerUid !== uid) {
    throw new HttpsError("permission-denied", "The tenant owner invariant is invalid.");
  }
  const satisfiesAllowedRole = !allowedRoles ||
    allowedRoles.includes(rawStaff.role) ||
    (rawStaff.role === "owner" && allowedRoles.includes("admin"));
  if (!satisfiesAllowedRole) {
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
  rawUser: RootUserRecord | undefined,
  authTime?: unknown
): PlatformAuthorizationContext {
  const user = assertActiveRootUser(uid, rawUser, authTime);
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
      userSnapshot.exists ? userSnapshot.data() as RootUserRecord : undefined,
      auth.token.auth_time
    ),
  };
}

export async function requireTenantMember<T>(
  db: Firestore,
  request: CallableRequest<T>,
  tenantIdValue: unknown,
  allowedRoles?: readonly TenantRole[],
  transaction?: Transaction,
  options?: TenantAccessOptions
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
    allowedRoles,
    auth.token.auth_time,
    options
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
    userSnapshot.exists ? userSnapshot.data() as RootUserRecord : undefined,
    auth.token.auth_time
  );
}
