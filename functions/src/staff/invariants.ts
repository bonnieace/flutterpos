import {MembershipStatus, RootUserRecord, TenantRole} from "../core/model";

export interface AdministrativeStaffState {
  uid: string;
  role: TenantRole;
  status: MembershipStatus;
}

export interface ProposedMembershipState {
  uid: string;
  role: TenantRole;
  status: MembershipStatus;
}

export function isAdministrativePrincipal(
  staff: AdministrativeStaffState,
  rootUser: RootUserRecord | undefined
): boolean {
  return (staff.role === "owner" || staff.role === "admin") &&
    staff.status === "active" &&
    rootUser?.globalStatus === "active" &&
    rootUser.accountType === "tenant_user" &&
    rootUser.identityTransition === undefined;
}

export function retainsAdministrativePrincipal(
  currentStaff: readonly AdministrativeStaffState[],
  rootsByUid: ReadonlyMap<string, RootUserRecord>,
  proposed: ProposedMembershipState
): boolean {
  const postMutation = currentStaff
    .filter((staff) => staff.uid !== proposed.uid)
    .concat(proposed);
  return postMutation.some((staff) =>
    isAdministrativePrincipal(staff, rootsByUid.get(staff.uid))
  );
}

export function preservesOwnerInvariant(
  tenantOwnerUid: string | undefined,
  targetUid: string,
  currentRole: TenantRole,
  proposedRole: TenantRole,
  proposedStatus: MembershipStatus
): boolean {
  if (!tenantOwnerUid) return false;
  if (targetUid === tenantOwnerUid) {
    return currentRole === "owner" &&
      proposedRole === "owner" &&
      proposedStatus === "active";
  }
  return currentRole !== "owner" && proposedRole !== "owner";
}

export function hasExactCanonicalOwner(
  tenantOwnerUid: string | undefined,
  staff: readonly AdministrativeStaffState[]
): boolean {
  if (!tenantOwnerUid) return false;
  const owners = staff.filter((membership) => membership.role === "owner");
  return owners.length === 1 &&
    owners[0].uid === tenantOwnerUid &&
    owners[0].status === "active";
}
