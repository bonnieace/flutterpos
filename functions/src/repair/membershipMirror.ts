import {
  CanonicalStaffRecord,
  isTenantRole,
  MEMBERSHIP_STATUSES,
  MembershipStatus,
  RootUserRecord,
  TENANT_STATUSES,
  TenantMembershipMirror,
  TenantRecord,
  TenantStatus,
} from "../core/model";

export type MirrorRepairIssue =
  | "missing_canonical_membership"
  | "mismatched_canonical_uid"
  | "invalid_canonical_role"
  | "invalid_membership_status"
  | "missing_tenant"
  | "invalid_tenant_status"
  | "invalid_tenant_identity"
  | "invalid_owner_invariant"
  | "missing_root_user"
  | "invalid_root_identity"
  | "mirror_missing"
  | "mirror_drift";

export interface MirrorRepairInput {
  uid: string;
  tenantId: string;
  tenant?: TenantRecord;
  staff?: CanonicalStaffRecord;
  mirror?: Partial<TenantMembershipMirror>;
  /**
   * `undefined` means the caller did not load the root document. `null` means
   * it performed the canonical read and the root document does not exist.
   */
  root?: RootUserRecord | null;
  /** Forces a canonical rewrite for transport metadata such as `createdAt`. */
  forceDrift?: boolean;
}

export type MirrorRepairDecision =
  | {
    action: "delete";
    tenantId: string;
    issues: readonly MirrorRepairIssue[];
  }
  | {
    action: "noop" | "upsert";
    tenantId: string;
    issues: readonly MirrorRepairIssue[];
    value: TenantMembershipMirror;
  };

export interface RootRoutingRepair {
  membershipCount: number;
  ownedTenantCount: number;
  ownedActiveTenantCount: number;
  clearDefaultTenant: boolean;
}

export type RootRoutingCounts = Omit<RootRoutingRepair, "clearDefaultTenant">;

function nonEmptyString(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const normalized = value.trim();
  return normalized.length > 0 ? normalized : undefined;
}

function isMembershipStatus(value: unknown): value is MembershipStatus {
  return typeof value === "string" &&
    MEMBERSHIP_STATUSES.includes(value as MembershipStatus);
}

function isTenantStatus(value: unknown): value is TenantStatus {
  return typeof value === "string" &&
    TENANT_STATUSES.includes(value as TenantStatus);
}

function safeMirrorVersion(value: unknown): number {
  return Number.isSafeInteger(value) && (value as number) >= 0 ? value as number : 0;
}

function comparableMirror(
  value: Partial<TenantMembershipMirror> | undefined
): Omit<TenantMembershipMirror, "mirrorVersion"> | undefined {
  if (!value) return undefined;
  return {
    tenantId: value.tenantId as string,
    tenantName: value.tenantName as string,
    tenantSlug: value.tenantSlug as string,
    role: value.role as TenantMembershipMirror["role"],
    membershipStatus: value.membershipStatus as MembershipStatus,
    tenantStatus: value.tenantStatus as TenantStatus,
    ...(value.invitationStatus === undefined ? {} : {
      invitationStatus: value.invitationStatus,
    }),
    isOwner: value.isOwner as boolean,
  };
}

function mirrorsEqual(
  left: Omit<TenantMembershipMirror, "mirrorVersion"> | undefined,
  right: Omit<TenantMembershipMirror, "mirrorVersion">
): boolean {
  if (!left) return false;
  return left.tenantId === right.tenantId &&
    left.tenantName === right.tenantName &&
    left.tenantSlug === right.tenantSlug &&
    left.role === right.role &&
    left.membershipStatus === right.membershipStatus &&
    left.tenantStatus === right.tenantStatus &&
    left.invitationStatus === right.invitationStatus &&
    left.isOwner === right.isOwner;
}

function deleteDecision(
  tenantId: string,
  issue: MirrorRepairIssue
): MirrorRepairDecision {
  return {action: "delete", tenantId, issues: [issue]};
}

/**
 * Projects one routing mirror exclusively from canonical tenant/staff data.
 * A malformed canonical record is never repaired from the existing mirror.
 */
export function planMembershipMirrorRepair(
  input: MirrorRepairInput
): MirrorRepairDecision {
  const {uid, tenantId, tenant, staff, mirror} = input;
  if (input.root === null) return deleteDecision(tenantId, "missing_root_user");
  if (input.root !== undefined && (
    input.root.accountType !== "tenant_user" ||
    (input.root.globalStatus !== "active" && input.root.globalStatus !== "disabled")
  )) {
    return deleteDecision(tenantId, "invalid_root_identity");
  }
  if (!staff) return deleteDecision(tenantId, "missing_canonical_membership");
  if (staff.uid !== uid) return deleteDecision(tenantId, "mismatched_canonical_uid");
  if (!isTenantRole(staff.role)) return deleteDecision(tenantId, "invalid_canonical_role");
  if (!isMembershipStatus(staff.status)) {
    return deleteDecision(tenantId, "invalid_membership_status");
  }
  if (!tenant) return deleteDecision(tenantId, "missing_tenant");
  if (!isTenantStatus(tenant.status)) {
    return deleteDecision(tenantId, "invalid_tenant_status");
  }
  const tenantName = nonEmptyString(tenant.name);
  const tenantSlug = nonEmptyString(tenant.slug);
  if (!tenantName || !tenantSlug) {
    return deleteDecision(tenantId, "invalid_tenant_identity");
  }
  const canonicalOwner = tenant.ownerUid === uid;
  if (tenant.status !== "archived" && (
    (staff.role === "owner") !== canonicalOwner
  )) {
    return deleteDecision(tenantId, "invalid_owner_invariant");
  }

  const baseValue: Omit<TenantMembershipMirror, "mirrorVersion"> = {
    tenantId,
    tenantName,
    tenantSlug,
    role: staff.role,
    membershipStatus: staff.status,
    tenantStatus: tenant.status,
    ...(typeof staff.invitationStatus === "string" ? {
      invitationStatus: staff.invitationStatus,
    } : {}),
    isOwner: staff.role === "owner" && canonicalOwner,
  };
  const mirrorMatches = !input.forceDrift && mirrorsEqual(comparableMirror(mirror), baseValue);
  const previousVersion = safeMirrorVersion(mirror?.mirrorVersion);
  return {
    action: mirrorMatches ? "noop" : "upsert",
    tenantId,
    issues: mirrorMatches ? [] : [mirror ? "mirror_drift" : "mirror_missing"],
    value: {
      ...baseValue,
      mirrorVersion: mirrorMatches ? previousVersion : previousVersion + 1,
    },
  };
}

/** Returns the exact advisory counter contribution of one canonical projection. */
export function rootRoutingContribution(
  decision: MirrorRepairDecision
): RootRoutingCounts {
  if (decision.action === "delete") {
    return {membershipCount: 0, ownedTenantCount: 0, ownedActiveTenantCount: 0};
  }
  const {value} = decision;
  return {
    membershipCount: 1,
    ownedTenantCount: value.isOwner && value.tenantStatus !== "archived" ? 1 : 0,
    ownedActiveTenantCount: value.isOwner &&
      value.membershipStatus === "active" &&
      value.tenantStatus === "active" ? 1 : 0,
  };
}

export function addRootRoutingCounts(
  left: RootRoutingCounts,
  right: RootRoutingCounts
): RootRoutingCounts {
  return {
    membershipCount: left.membershipCount + right.membershipCount,
    ownedTenantCount: left.ownedTenantCount + right.ownedTenantCount,
    ownedActiveTenantCount: left.ownedActiveTenantCount + right.ownedActiveTenantCount,
  };
}

/** Derives advisory root counters and default-tenant validity from repairs. */
export function planRootRoutingRepair(
  decisions: readonly MirrorRepairDecision[],
  defaultTenantId: string | undefined
): RootRoutingRepair {
  const memberships = decisions.filter(
    (decision): decision is Extract<MirrorRepairDecision, {value: TenantMembershipMirror}> =>
      decision.action !== "delete"
  );
  const counts = decisions.reduce(
    (total, decision) => addRootRoutingCounts(total, rootRoutingContribution(decision)),
    {membershipCount: 0, ownedTenantCount: 0, ownedActiveTenantCount: 0}
  );
  return {
    ...counts,
    clearDefaultTenant: defaultTenantId !== undefined && !memberships.some((item) =>
      item.tenantId === defaultTenantId &&
      item.value.membershipStatus === "active" &&
      item.value.tenantStatus === "active"
    ),
  };
}
