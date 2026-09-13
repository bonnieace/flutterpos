export type InvitationAcceptanceMode = "token" | "visible";

export type InvitationAcceptanceViolation =
  | "caller_mismatch"
  | "tenant_inactive"
  | "membership_not_pending"
  | "invitation_not_pending"
  | "email_mismatch"
  | "invitation_consumed"
  | "invitation_expired"
  | "email_unverified";

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

  /**
   * The invitation carried a lifetime and it has passed.
   *
   * False when there is no lifetime to have passed, which is an invitation
   * whose first delivery has not been dispatched yet: the expiry is written
   * when the token is minted, and nothing has been emailed before that.
   */
  invitationExpired: boolean;

  /** Live from the Auth record, not a flag stored when the invite was sent. */
  emailVerified: boolean;
}

const PENDING_INVITATION_STATUSES = new Set(["pending", "sent"]);

/**
 * Whether this identity may accept this invitation, by either route.
 *
 * **The two routes prove the same thing and are therefore gated the same way.**
 * Until 2026-09-08 the tokenless route additionally required a stored
 * `visibleAcceptanceAllowed`, fixed at invite time by
 * `!newlyCreated && emailVerified`, which was `false` for every new hire and
 * could never afterwards become true - not by verifying the address, not by a
 * resend, which copied the old value forward. Those invitees were told to use
 * the emailed link, and the emailed link's landing page told them to accept in
 * the app. They were locked out of both.
 *
 * The flag was standing in for mailbox control, and `emailVerified` is that,
 * read live from Auth rather than remembered from before the invitee had ever
 * opened their mail. An address is verified only by following something sent to
 * it - the credential-bootstrap link this invitation itself mints, or a
 * verification mail - so an identity the inviter created gets no further than
 * one the invitee created. What the token adds over that is the seven days the
 * email promises, and that is now `invitationExpired` and applies to both
 * routes.
 */
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
  if (state.invitationExpired) return "invitation_expired";
  // The token route reaches here holding proof the address received mail; the
  // tokenless one has to be told, and `mode` is why the check is not shared.
  if (mode === "visible" && !state.emailVerified) return "email_unverified";
  return undefined;
}
