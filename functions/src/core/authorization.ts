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

/** Enough of an Auth record to judge whether its owner may act. */
export interface VerifiableAuthIdentity {
  disabled: boolean;
  emailVerified: boolean;
}

/**
 * Confirms the address is verified against the **Auth record** rather than the
 * caller's ID token.
 *
 * `token.email_verified` is minted at sign-in and does not change when somebody
 * follows the link in their mailbox, so a token up to an hour old still reads
 * false for an address that is in fact verified - while the client's own
 * `reload()` has already flipped `User.emailVerified` and unlocked the control.
 * The person is told to verify, verifies, watches the button light up, presses
 * it, and is refused. Reading the Auth record closes that gap, and is what every
 * other callable here already does; see `staff/acceptance.ts`.
 *
 * Pure on purpose: the caller fetches the record, so this stays testable without
 * standing up `getAuth()`.
 */
export function assertVerifiedAuthIdentity(
  uid: string,
  identity: VerifiableAuthIdentity | undefined
): void {
  if (!identity) {
    throw new HttpsError("failed-precondition", "The current identity is unavailable.");
  }
  if (identity.disabled) {
    throw new HttpsError("permission-denied", "This account is not active.");
  }
  if (identity.emailVerified !== true) {
    throw new HttpsError("permission-denied", "A verified email is required.");
  }
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

export function assertTenantMemberDocuments(
  uid: string,
  tenantId: string,
  rawUser: RootUserRecord | undefined,
  rawTenant: TenantRecord | undefined,
  rawStaff: CanonicalStaffRecord | undefined,
  allowedRoles?: readonly TenantRole[],
  authTime?: unknown
): TenantAuthorizationContext {
  const user = assertActiveRootUser(uid, rawUser, authTime);
  if (user.accountType !== "tenant_user") {
    throw new HttpsError("permission-denied", "Platform identities cannot access tenant data.");
  }
  if (rawTenant?.status !== "active") {
    // Deliberately one sentence for every reason. Which of "suspended" and
    // "archived" applies is a fact about the business that the client reads
    // from the tenant document it is allowed to read; repeating it here would
    // be a second place for the two to disagree.
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
  // Verification is established by the caller against the Auth record, before
  // this transaction opens - see `assertVerifiedAuthIdentity`. Checking the token
  // again here would reinstate the stale-token refusal from inside the
  // transaction, where the caller's own check cannot reach it.
  const auth = requireAuthenticatedUser(request, {allowUnverified: true});
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
    allowedRoles,
    auth.token.auth_time
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
