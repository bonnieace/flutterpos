import {
  Auth,
  getAuth,
  UserRecord,
} from "firebase-admin/auth";
import {
  DocumentReference,
  DocumentSnapshot,
  FieldValue,
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";
import {CallableRequest, HttpsError} from "firebase-functions/v2/https";
import {requireTenantMember} from "../core/authorization";
import {buildIdempotencyIdentity} from "../core/idempotency";
import {
  isTenantRole,
  MEMBERSHIP_STATUSES,
  MembershipStatus,
  RootUserRecord,
  TenantAuthorizationContext,
  TenantRole,
} from "../core/model";
import {assertTenantIdentityTarget, normalizedCounter} from "./identity";
import {
  AdministrativeStaffState,
  hasExactCanonicalOwner,
  preservesOwnerInvariant,
  ProposedMembershipState,
  retainsAdministrativePrincipal,
} from "./invariants";
import {
  StoredMirrorRecord,
  StoredStaffRecord,
  StoredTenantRecord,
} from "./types";

const PENDING_INVITATION_STATUSES = new Set(["pending", "sent"]);
export const STAFF_MANAGEMENT_ROLES: readonly TenantRole[] = ["owner", "admin"];

export interface AuthIdentity {
  uid: string;
  email: string;
  displayName: string;
  emailVerified: boolean;
  disabled: boolean;
  hasPlatformClaim: boolean;
  newlyCreated: boolean;
}

export interface PreparedTargetRoot {
  user: RootUserRecord;
  create: boolean;
}

function authErrorCode(error: unknown): string | undefined {
  return error && typeof error === "object" && "code" in error ?
    String((error as {code?: unknown}).code) :
    undefined;
}

function platformClaim(user: UserRecord): boolean {
  return user.customClaims?.platformRole !== undefined;
}

function authIdentity(user: UserRecord, newlyCreated: boolean): AuthIdentity {
  if (!user.email) {
    throw new HttpsError("failed-precondition", "The target Auth identity has no email.");
  }
  return {
    uid: user.uid,
    email: user.email.trim().toLowerCase(),
    displayName: user.displayName?.trim() ?? "",
    emailVerified: user.emailVerified,
    disabled: user.disabled,
    hasPlatformClaim: platformClaim(user),
    newlyCreated,
  };
}

async function getByEmail(auth: Auth, email: string): Promise<UserRecord | undefined> {
  try {
    return await auth.getUserByEmail(email);
  } catch (error) {
    if (authErrorCode(error) === "auth/user-not-found") return undefined;
    throw error;
  }
}

export async function readAuthIdentityIfExists(
  uid: string,
  auth: Auth = getAuth()
): Promise<AuthIdentity | undefined> {
  try {
    return authIdentity(await auth.getUser(uid), false);
  } catch (error) {
    if (authErrorCode(error) === "auth/user-not-found") return undefined;
    throw error;
  }
}

export async function resolveOrCreateAuthIdentity(
  email: string,
  displayName: string,
  provisionalUid?: string,
  auth: Auth = getAuth()
): Promise<AuthIdentity> {
  const existing = await getByEmail(auth, email);
  if (existing) return authIdentity(existing, existing.uid === provisionalUid);

  try {
    const created = await auth.createUser({
      ...(provisionalUid ? {uid: provisionalUid} : {}),
      email,
      ...(displayName ? {displayName} : {}),
      emailVerified: false,
      disabled: false,
    });
    return authIdentity(created, true);
  } catch (error) {
    if (authErrorCode(error) !== "auth/email-already-exists") throw error;
    const racedIdentity = await getByEmail(auth, email);
    if (!racedIdentity) throw error;
    return authIdentity(racedIdentity, racedIdentity.uid === provisionalUid);
  }
}

export async function readAuthIdentity(uid: string): Promise<AuthIdentity> {
  try {
    return authIdentity(await getAuth().getUser(uid), false);
  } catch (error) {
    if (authErrorCode(error) === "auth/user-not-found") {
      throw new HttpsError("not-found", "The target Auth identity does not exist.");
    }
    throw error;
  }
}

export async function preauthorizeTenantAdministrator<T>(
  db: Firestore,
  request: CallableRequest<T>,
  tenantId: string
): Promise<TenantAuthorizationContext> {
  return requireTenantMember(db, request, tenantId, STAFF_MANAGEMENT_ROLES);
}

export function prepareTargetRoot(
  snapshot: DocumentSnapshot,
  identity: AuthIdentity,
  requireActive: boolean
): PreparedTargetRoot {
  if (identity.disabled && requireActive) {
    throw new HttpsError("failed-precondition", "The target Auth identity is disabled.");
  }
  if (!snapshot.exists) {
    if (identity.hasPlatformClaim) {
      throw new HttpsError(
        "permission-denied",
        "Platform identities cannot have tenant memberships."
      );
    }
    return {
      create: true,
      user: {
        email: identity.email,
        displayName: identity.displayName,
        accountType: "tenant_user",
        identityOrigin: "staff_invitation",
        globalStatus: identity.disabled ? "disabled" : "active",
        membershipCount: 0,
        ownedTenantCount: 0,
        ownedActiveTenantCount: 0,
      },
    };
  }
  return {
    create: false,
    user: assertTenantIdentityTarget(snapshot.data() as RootUserRecord, {
      requireActive,
      hasPlatformClaim: identity.hasPlatformClaim,
    }),
  };
}

export function prepareExistingTargetRoot(
  snapshot: DocumentSnapshot,
  identity: AuthIdentity | undefined,
  requireActive: boolean
): PreparedTargetRoot {
  if (!snapshot.exists) {
    throw new HttpsError("failed-precondition", "The canonical root user does not exist.");
  }
  if (!identity && requireActive) {
    throw new HttpsError("failed-precondition", "The target Auth identity does not exist.");
  }
  if (identity?.disabled && requireActive) {
    throw new HttpsError("failed-precondition", "The target Auth identity is disabled.");
  }
  return {
    create: false,
    user: assertTenantIdentityTarget(snapshot.data() as RootUserRecord, {
      requireActive,
      hasPlatformClaim: identity?.hasPlatformClaim ?? false,
    }),
  };
}

export function writePreparedRoot(
  transaction: Transaction,
  rootRef: DocumentReference,
  prepared: PreparedTargetRoot,
  membershipDelta: -1 | 0 | 1
): void {
  if (prepared.create && membershipDelta < 0) {
    throw new HttpsError(
      "failed-precondition",
      "A missing root user cannot be created while removing a membership."
    );
  }
  const membershipCount = Math.max(
    0,
    normalizedCounter(prepared.user.membershipCount) + membershipDelta
  );
  if (prepared.create) {
    transaction.create(rootRef, {
      ...prepared.user,
      membershipCount,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return;
  }
  transaction.update(rootRef, {
    membershipCount,
    updatedAt: FieldValue.serverTimestamp(),
  });
}

/** Applies a removal/update only when a canonical root already exists. */
export function writeExistingRootMembershipDelta(
  transaction: Transaction,
  rootRef: DocumentReference,
  snapshot: DocumentSnapshot,
  membershipDelta: -1 | 0 | 1
): void {
  if (!snapshot.exists) return;
  const root = snapshot.data() as RootUserRecord;
  if (root.accountType !== "tenant_user") {
    throw new HttpsError(
      "failed-precondition",
      "The canonical membership belongs to an incompatible root identity."
    );
  }
  transaction.update(rootRef, {
    membershipCount: Math.max(0, normalizedCounter(root.membershipCount) + membershipDelta),
    updatedAt: FieldValue.serverTimestamp(),
  });
}

function safeMirrorVersion(value: unknown): number {
  return Number.isSafeInteger(value) && (value as number) >= 0 ? value as number : 0;
}

export function membershipMirrorData(
  tenantId: string,
  tenant: StoredTenantRecord,
  staff: StoredStaffRecord,
  currentMirror: StoredMirrorRecord | undefined,
  joined: boolean
): Record<string, unknown> {
  if (
    !tenant.name ||
    !tenant.slug ||
    !tenant.status ||
    !staff.uid ||
    !isTenantRole(staff.role) ||
    !MEMBERSHIP_STATUSES.includes(staff.status as MembershipStatus)
  ) {
    throw new HttpsError("failed-precondition", "Canonical membership data is invalid.");
  }
  return {
    tenantId,
    tenantName: tenant.name,
    tenantSlug: tenant.slug,
    role: staff.role,
    membershipStatus: staff.status,
    tenantStatus: tenant.status,
    invitationStatus: typeof staff.invitationStatus === "string" ?
      staff.invitationStatus :
      null,
    isOwner: staff.role === "owner" && tenant.ownerUid === staff.uid,
    mirrorVersion: safeMirrorVersion(currentMirror?.mirrorVersion) + 1,
    createdAt: currentMirror?.createdAt ?? FieldValue.serverTimestamp(),
    joinedAt: joined ? FieldValue.serverTimestamp() :
      currentMirror?.joinedAt ?? null,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

export function assertCanonicalTargetStaff(
  targetUid: string,
  tenant: StoredTenantRecord,
  staff: StoredStaffRecord | undefined
): StoredStaffRecord & {role: TenantRole; status: MembershipStatus} {
  if (
    !staff ||
    staff.uid !== targetUid ||
    !isTenantRole(staff.role) ||
    !MEMBERSHIP_STATUSES.includes(staff.status as MembershipStatus)
  ) {
    throw new HttpsError("not-found", "The canonical staff membership does not exist.");
  }
  const ownerConsistent = targetUid === tenant.ownerUid ?
    staff.role === "owner" :
    staff.role !== "owner";
  if (!ownerConsistent) {
    throw new HttpsError("failed-precondition", "The tenant owner invariant is invalid.");
  }
  return {...staff, role: staff.role, status: staff.status as MembershipStatus};
}

export function assertOwnerMutation(
  tenant: StoredTenantRecord,
  targetUid: string,
  currentRole: TenantRole,
  proposedRole: TenantRole,
  proposedStatus: MembershipStatus
): void {
  if (!preservesOwnerInvariant(
    tenant.ownerUid,
    targetUid,
    currentRole,
    proposedRole,
    proposedStatus
  )) {
    throw new HttpsError(
      "failed-precondition",
      "The tenant owner cannot be assigned, demoted, or deactivated here."
    );
  }
}

export async function assertAdministrativePrincipalAfterMutation(
  db: Firestore,
  transaction: Transaction,
  tenantId: string,
  tenantOwnerUid: string | undefined,
  proposed: ProposedMembershipState
): Promise<void> {
  const staffSnapshot = await transaction.get(
    db.collection("tenants").doc(tenantId).collection("staff")
      .where("role", "in", ["owner", "admin"])
  );
  const staffStates: AdministrativeStaffState[] = [];
  for (const document of staffSnapshot.docs) {
    const data = document.data() as StoredStaffRecord;
    if (
      data.uid !== document.id ||
      !isTenantRole(data.role) ||
      !MEMBERSHIP_STATUSES.includes(data.status as MembershipStatus)
    ) {
      throw new HttpsError(
        "failed-precondition",
        "Canonical administrative membership data is invalid."
      );
    }
    staffStates.push({
      uid: data.uid,
      role: data.role,
      status: data.status as MembershipStatus,
    });
  }
  if (!hasExactCanonicalOwner(tenantOwnerUid, staffStates)) {
    throw new HttpsError(
      "failed-precondition",
      "The tenant must have exactly one active canonical owner."
    );
  }
  const candidateUids = new Set(staffStates.map((staff) => staff.uid));
  candidateUids.add(proposed.uid);
  const rootRefs = [...candidateUids].map((uid) => db.collection("users").doc(uid));
  const rootSnapshots = rootRefs.length > 0 ?
    await transaction.getAll(rootRefs[0], ...rootRefs.slice(1)) :
    [];
  const rootsByUid = new Map<string, RootUserRecord>();
  for (const snapshot of rootSnapshots) {
    if (snapshot.exists) rootsByUid.set(snapshot.id, snapshot.data() as RootUserRecord);
  }
  if (!retainsAdministrativePrincipal(staffStates, rootsByUid, proposed)) {
    throw new HttpsError(
      "failed-precondition",
      "This change would leave the tenant without an active administrative principal."
    );
  }
}

export async function assertExactCanonicalOwner(
  db: Firestore,
  transaction: Transaction,
  tenantId: string,
  tenantOwnerUid: string | undefined
): Promise<void> {
  const ownerSnapshot = await transaction.get(
    db.collection("tenants").doc(tenantId).collection("staff")
      .where("role", "==", "owner")
  );
  const owners: AdministrativeStaffState[] = ownerSnapshot.docs.map((document) => {
    const data = document.data() as StoredStaffRecord;
    if (
      data.uid !== document.id ||
      data.role !== "owner" ||
      !MEMBERSHIP_STATUSES.includes(data.status as MembershipStatus)
    ) {
      throw new HttpsError(
        "failed-precondition",
        "Canonical owner membership data is invalid."
      );
    }
    return {uid: data.uid, role: "owner", status: data.status as MembershipStatus};
  });
  if (!hasExactCanonicalOwner(tenantOwnerUid, owners)) {
    throw new HttpsError(
      "failed-precondition",
      "The tenant must have exactly one active canonical owner."
    );
  }
}

export function isPendingInvitationStatus(value: unknown): boolean {
  return typeof value === "string" && PENDING_INVITATION_STATUSES.has(value);
}

export function isUnexpiredTimestamp(value: unknown, now: Timestamp): boolean {
  return value instanceof Timestamp && value.toMillis() > now.toMillis();
}

export function operationDocumentId(
  actorUid: string,
  operation: string,
  tenantId: string,
  requestId: string
): string {
  return buildIdempotencyIdentity(actorUid, operation, tenantId, requestId).documentId;
}

export function auditData(
  tenantId: string,
  eventType: string,
  actorUid: string,
  targetUid: string,
  requestId: string,
  details: Record<string, unknown> = {}
): Record<string, unknown> {
  return {
    tenantId,
    eventType,
    actorUid,
    targetUid,
    requestId,
    ...details,
    createdAt: FieldValue.serverTimestamp(),
  };
}

export function deliveryData(
  deliveryId: string,
  tenantId: string,
  targetUid: string,
  recipientHash: string,
  recipientHashKeyVersion: string,
  invitationVersion: number,
  invitationPath: string
): Record<string, unknown> {
  return {
    deliveryId,
    deliveryType: "staff_invitation",
    status: "pending_enqueue",
    tenantId,
    targetUid,
    recipientHash,
    recipientHashKeyVersion,
    invitationVersion,
    invitationPath,
    sendable: true,
    attemptCount: 0,
    nextAttemptAt: FieldValue.serverTimestamp(),
    tokenMaterialStatus: "transient_task_payload_only",
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}
