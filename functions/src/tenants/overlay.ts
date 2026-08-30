import {
  CanonicalStaffRecord,
  isTenantRole,
  MembershipStatus,
  RootUserRecord,
  TenantRecord,
  TenantRole,
  TenantStatus,
} from "../core/model";

const MEMBERSHIP_STATUS_VALUES = new Set<string>(["pending", "active", "inactive"]);
const TENANT_STATUS_VALUES = new Set<string>([
  "pending",
  "active",
  "suspended",
  "rejected",
  "archived",
]);
const INVITATION_STATUS_VALUES = new Set<string>([
  "pending",
  "sent",
  "accepted",
  "cancelled",
  "expired",
]);

export interface TenantMirrorRecord {
  tenantId?: unknown;
  tenantName?: unknown;
  tenantSlug?: unknown;
  role?: unknown;
  membershipStatus?: unknown;
  tenantStatus?: unknown;
  invitationStatus?: unknown;
  isOwner?: unknown;
  createdAt?: unknown;
  joinedAt?: unknown;
  updatedAt?: unknown;
  mirrorVersion?: unknown;
  provisionalUntil?: unknown;
}

export interface TenantListItem {
  tenantId: string;
  tenantName: string;
  tenantSlug: string;
  role: TenantRole;
  membershipStatus: MembershipStatus;
  tenantStatus: TenantStatus;
  invitationStatus: string | null;
  isOwner: boolean;
  createdAt: string | null;
  joinedAt: string | null;
  updatedAt: string | null;
  mirrorVersion: number;
  /**
   * When a self-serve request's provisional trading window shuts, ISO-8601, or
   * null where there is no window.
   *
   * **Projected, not left to the client to find.** The app never reads the
   * membership mirror or the tenant document to decide what a business may do -
   * it reads this list. A window written onto both of those and omitted here is
   * a window the app cannot see, which is exactly the defect this field closes:
   * every provisional business drew a padlock.
   */
  provisionalUntil: string | null;
  canAccess: boolean;
  canonicalTenantExists: boolean;
  canonicalMembershipExists: boolean;
}

export interface TenantOverlayRecord extends TenantRecord {
  updatedAt?: unknown;
}

export interface CanonicalStaffOverlayRecord extends CanonicalStaffRecord {
  joinedAt?: unknown;
  updatedAt?: unknown;
}

interface FirestoreTimestampLike {
  toDate(): Date;
}

function nonEmptyString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

function tenantStatus(value: unknown): TenantStatus | undefined {
  return typeof value === "string" && TENANT_STATUS_VALUES.has(value) ?
    value as TenantStatus :
    undefined;
}

function membershipStatus(value: unknown): MembershipStatus | undefined {
  return typeof value === "string" && MEMBERSHIP_STATUS_VALUES.has(value) ?
    value as MembershipStatus :
    undefined;
}

function invitationStatus(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const normalized = value.trim().toLowerCase();
  return INVITATION_STATUS_VALUES.has(normalized) ? normalized : undefined;
}

function isoTimestamp(value: unknown): string | null {
  let date: Date | undefined;
  if (value instanceof Date) {
    date = value;
  } else if (
    value &&
    typeof value === "object" &&
    typeof (value as Partial<FirestoreTimestampLike>).toDate === "function"
  ) {
    date = (value as FirestoreTimestampLike).toDate();
  } else if (typeof value === "string") {
    const milliseconds = Date.parse(value);
    if (Number.isFinite(milliseconds)) date = new Date(milliseconds);
  }
  return date && Number.isFinite(date.getTime()) ? date.toISOString() : null;
}

function mirrorRole(value: unknown): TenantRole {
  return isTenantRole(value) ? value : "cashier";
}

export function overlayCanonicalTenantState(
  uid: string,
  tenantId: string,
  mirror: TenantMirrorRecord,
  user: RootUserRecord | undefined,
  tenant: TenantOverlayRecord | undefined,
  staff: CanonicalStaffOverlayRecord | undefined
): TenantListItem {
  const canonicalTenantExists = tenant !== undefined;
  const canonicalMembershipExists = staff !== undefined && staff.uid === uid;
  const canonicalRole = canonicalMembershipExists && isTenantRole(staff.role) ?
    staff.role :
    undefined;
  const currentTenantStatus = canonicalTenantExists ?
    tenantStatus(tenant.status) ?? "archived" :
    tenantStatus(mirror.tenantStatus) ?? "archived";
  const currentMembershipStatus = canonicalMembershipExists ?
    membershipStatus(staff.status) ?? "inactive" :
    membershipStatus(mirror.membershipStatus) ?? "inactive";
  const currentRole = canonicalRole ?? mirrorRole(mirror.role);
  const ownerInvariantValid = canonicalRole !== "owner" || tenant?.ownerUid === uid;
  const provisionalUntil = isoTimestamp(
    tenant?.provisionalUntil ?? mirror.provisionalUntil
  );
  // **A pending business inside its provisional window may trade**, which is
  // what `tradingTenant` in `firestore.rules` and `tenantSatisfiesAccessMode`
  // both already say. This third copy of the same question exists because the
  // app asks it of this list rather than of either of those, and it answered
  // "no" for every provisional business - a padlock on a shop that was entitled
  // to sell.
  const withinProvisionalWindow = currentTenantStatus === "pending" &&
    provisionalUntil !== null &&
    Date.parse(provisionalUntil) > Date.now();
  const canAccess = user?.globalStatus === "active" &&
    user.accountType === "tenant_user" &&
    canonicalTenantExists &&
    (currentTenantStatus === "active" || withinProvisionalWindow) &&
    canonicalMembershipExists &&
    currentMembershipStatus === "active" &&
    canonicalRole !== undefined &&
    ownerInvariantValid;

  return {
    // The mirror document ID is authoritative for routing. A stale field cannot
    // redirect canonical lookups to a different tenant.
    tenantId,
    tenantName: nonEmptyString(tenant?.name) ??
      nonEmptyString(mirror.tenantName) ??
      tenantId,
    tenantSlug: nonEmptyString(tenant?.slug) ??
      nonEmptyString(mirror.tenantSlug) ??
      tenantId,
    role: currentRole,
    membershipStatus: currentMembershipStatus,
    tenantStatus: currentTenantStatus,
    invitationStatus: invitationStatus(staff?.invitationStatus) ??
      invitationStatus(mirror.invitationStatus) ??
      null,
    isOwner: canonicalTenantExists &&
      canonicalMembershipExists &&
      tenant.ownerUid === uid &&
      canonicalRole === "owner",
    createdAt: isoTimestamp(mirror.createdAt),
    joinedAt: isoTimestamp(staff?.joinedAt ?? mirror.joinedAt),
    updatedAt: isoTimestamp(staff?.updatedAt ?? tenant?.updatedAt ?? mirror.updatedAt),
    mirrorVersion: Number.isSafeInteger(mirror.mirrorVersion) &&
      (mirror.mirrorVersion as number) >= 0 ? mirror.mirrorVersion as number : 0,
    provisionalUntil,
    canAccess,
    canonicalTenantExists,
    canonicalMembershipExists,
  };
}
