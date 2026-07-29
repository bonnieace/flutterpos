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
  identityTransition?: "granting_platform" | "cleanup_pending";
  globalStatus?: GlobalStatus;
  defaultTenantId?: string;
  membershipCount?: number;
  ownedTenantCount?: number;
  ownedActiveTenantCount?: number;
}
export interface TenantRecord {
  name?: string;
  slug?: string;
  status?: TenantStatus;
  ownerUid?: string;
}

export interface CanonicalStaffRecord {
  uid?: string;
  email?: string;
  name?: string;
  phone?: string;
  role?: TenantRole;
  status?: MembershipStatus;
  invitationStatus?: string;
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
