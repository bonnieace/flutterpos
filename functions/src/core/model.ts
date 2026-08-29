export const TENANT_ROLES = ["owner", "admin", "manager", "cashier"] as const;
export type TenantRole = (typeof TENANT_ROLES)[number];

export const TENANT_STATUSES = [
  "pending",
  "active",
  "suspended",
  "rejected",
  "archived",
] as const;
export type TenantStatus = (typeof TENANT_STATUSES)[number];

export const MEMBERSHIP_STATUSES = ["pending", "active", "inactive"] as const;
export type MembershipStatus = (typeof MEMBERSHIP_STATUSES)[number];

export const ACCOUNT_TYPES = ["tenant_user", "platform_admin"] as const;
export type AccountType = (typeof ACCOUNT_TYPES)[number];

export const GLOBAL_STATUSES = ["active", "disabled"] as const;
export type GlobalStatus = (typeof GLOBAL_STATUSES)[number];

export interface RootUserRecord {
  email?: string;
  displayName?: string;
  accountType?: AccountType;
  identityOrigin?: "self_signup" | "staff_invitation" | "platform_bootstrap";
  identityTransition?:
    | "granting_platform"
    | "revoking_platform"
    | "cleanup_pending";
  platformIdentityOperationId?: string;
  globalStatus?: GlobalStatus;
  authValidAfterSeconds?: number;
  defaultTenantId?: string;
  membershipCount?: number;
  ownedTenantCount?: number;
  ownedActiveTenantCount?: number;
}
/** Anything that can answer "what instant is this", without importing Firestore. */
export interface MillisecondInstant {
  toMillis(): number;
}

export interface TenantRecord {
  name?: string;
  slug?: string;
  status?: TenantStatus;
  ownerUid?: string;
  /**
   * When a self-serve request's provisional trading window shuts.
   *
   * Set once by `requestTenant` and never moved. A `pending` tenant may trade
   * until this instant and may only be read after it; approval replaces the
   * question entirely by moving `status` to `active`.
   *
   * Absent on a tenant requested before the window existed, and on every tenant
   * that was seeded rather than requested - both of which therefore read as
   * lapsed rather than as permanently provisional.
   */
  provisionalUntil?: MillisecondInstant;
}

/** How much standing a caller needs in a tenant for the operation at hand. */
export type TenantAccessMode =
  /**
   * The business must be approved outright. For operations whose effects reach
   * outside the business and cannot be taken back if it is never approved -
   * provisioning an Auth identity for an invited colleague, sending them mail.
   */
  | "approved"
  /**
   * The business may be traded in: approved, or a request inside its
   * provisional window. The default, and what every write asks for.
   */
  | "trading"
  /**
   * The business's records may be read: everything `trading` allows, plus a
   * request whose window has shut. A lapsed request keeps sight of the week it
   * traded; it just cannot add to it.
   */
  | "reading";

export interface CanonicalStaffRecord {
  uid?: string;
  email?: string;
  name?: string;
  phone?: string;
  role?: TenantRole;
  status?: MembershipStatus;
  invitationStatus?: string;
  searchName?: string;
  searchPrefixes?: string[];
}

export interface TenantMembershipMirror {
  tenantId: string;
  tenantName: string;
  tenantSlug: string;
  role: TenantRole;
  membershipStatus: MembershipStatus;
  tenantStatus: TenantStatus;
  invitationStatus?: string;
  isOwner: boolean;
  mirrorVersion: number;
}

export interface TenantAuthorizationContext {
  uid: string;
  tenantId: string;
  user: RootUserRecord;
  tenant: TenantRecord;
  staff: CanonicalStaffRecord & {role: TenantRole};
}

export interface PlatformAuthorizationContext {
  uid: string;
  user: RootUserRecord;
}

export function isTenantRole(value: unknown): value is TenantRole {
  return typeof value === "string" && TENANT_ROLES.includes(value as TenantRole);
}
