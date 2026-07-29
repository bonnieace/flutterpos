export type InvitationAcceptanceMode = "token" | "visible";

export type InvitationAcceptanceViolation =
  | "caller_mismatch"
  | "tenant_inactive"
  | "membership_not_pending"
  | "invitation_not_pending"
  | "email_mismatch"
  | "invitation_consumed"
  | "email_unverified"
  | "versioned_proof_required";

export interface InvitationAcceptanceState {
  callerUid: string;
  invitedUid: string;
  currentEmail: string;
  invitedEmail: string;
  tenantStatus: string;
  membershipStatus: string;
  membershipInvitationStatus: string;
  invitationStatus: string;
  invitationConsumed: boolean;
  emailVerified: boolean;
  visibleAcceptanceAllowed: boolean;
}

const PENDING_INVITATION_STATUSES = new Set(["pending", "sent"]);

export function invitationAcceptanceViolation(
  mode: InvitationAcceptanceMode,
  state: InvitationAcceptanceState
): InvitationAcceptanceViolation | undefined {
  if (state.callerUid !== state.invitedUid) return "caller_mismatch";
  if (state.tenantStatus !== "active") return "tenant_inactive";
  if (state.membershipStatus !== "pending") return "membership_not_pending";
  if (!PENDING_INVITATION_STATUSES.has(state.membershipInvitationStatus)) {
    return "membership_not_pending";
  }
  if (!PENDING_INVITATION_STATUSES.has(state.invitationStatus)) {
    return "invitation_not_pending";
  }
  if (state.currentEmail !== state.invitedEmail) return "email_mismatch";
  if (state.invitationConsumed) return "invitation_consumed";
  if (mode === "visible" && !state.emailVerified) return "email_unverified";
  if (mode === "visible" && !state.visibleAcceptanceAllowed) {
    return "versioned_proof_required";
  }
  return undefined;
}
