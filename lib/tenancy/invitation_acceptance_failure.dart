/// The refusal boundary shared by both invitation-acceptance callables.
///
/// It is one module because it is one server function. `acceptTenantInvitation`
/// and `acceptVisibleTenantInvitation` are two `onCall` wrappers over a single
/// `acceptInvitation`, and both refuse through the single policy function
/// `invitationAcceptanceViolation` in `functions/src/staff/acceptancePolicy.ts`.
/// Two client copies of this mapping would be two ways to word one server
/// decision, and the first divergence would be invisible.
library;

/// Which of the two acceptance paths a refusal came back from.
///
/// Mirrors the server's own `InvitationAcceptanceMode`. It is carried because
/// the server branches on it: a `permission-denied` that names no violation
/// means a rejected token proof on one path and an ineligible signed-in
/// identity on the other, and one sentence covering both would be vague on
/// purpose.
enum InvitationAcceptanceMode {
  /// Acceptance by versioned proof, from the link in the invitation email.
  token,

  /// In-app acceptance of an invitation the caller can already see.
  visible,
}

/// The reasons the server refuses an acceptance, as it enumerates them.
///
/// A one-for-one mirror of `InvitationAcceptanceViolation` in
/// `acceptancePolicy.ts`. These are server-authored tokens rather than prose,
/// which is the only reason they may cross this boundary at all: the rule that
/// no string this app did not write reaches a user is unchanged.
enum InvitationAcceptanceViolation {
  callerMismatch('caller_mismatch'),
  tenantInactive('tenant_inactive'),
  membershipNotPending('membership_not_pending'),
  invitationNotPending('invitation_not_pending'),
  emailMismatch('email_mismatch'),
  invitationConsumed('invitation_consumed'),

  /// Unreachable today, and mapped anyway.
  ///
  /// The server's own `mode === "visible" && emailVerified !== true` guard
  /// throws before the policy function is ever consulted, so this token is
  /// currently produced by nothing. It is modelled because the server declares
  /// it, and dropping it here would make a later server change silently answer
  /// the fallback.
  emailUnverified('email_unverified'),

  /// The one the device run hit.
  ///
  /// `visibleAcceptanceAllowed` is decided once, at invite time, by
  /// `!newlyCreated && emailVerified` in `functions/src/staff/issuance.ts`.
  /// Nothing the user does afterwards changes it — verifying the address later
  /// does not — so this refusal is permanent for this invitation and the only
  /// way forward is the emailed link.
  versionedProofRequired('versioned_proof_required');

  const InvitationAcceptanceViolation(this.wireValue);

  final String wireValue;

  /// Reads a violation the server named, or `null` for anything else.
  ///
  /// Deliberately tolerant, and it is the one place in this file that is. A
  /// server that adds a violation must not turn a refusal into an unrenderable
  /// failure on an older client; an unrecognised token simply falls through to
  /// the code-level sentence, which is always safe because it names no cause.
  static InvitationAcceptanceViolation? fromWireOrNull(Object? value) {
    if (value is! String) return null;
    for (final violation in values) {
      if (violation.wireValue == value) return violation;
    }
    return null;
  }
}

/// A refusal an invitation-acceptance callable issued, carrying its code and
/// the server's own violation token, and nothing else.
///
/// Deliberately no `message`, for the reason `SignInException` carries none:
/// the provider's sentence is written for a log reader, is not translated, and
/// is sometimes not a sentence at all. Dropping it here is what makes "a user
/// is shown a sentence somebody wrote" a property of the type rather than of
/// care taken at each of the two call sites that were getting it wrong.
final class InvitationAcceptanceException implements Exception {
  const InvitationAcceptanceException(this.code, {this.violation});

  /// The callable's error code, such as `permission-denied`.
  final String code;

  /// The refusal the server named in `details.violation`, when it named one.
  final InvitationAcceptanceViolation? violation;

  @override
  String toString() =>
      'InvitationAcceptanceException($code, violation: ${violation?.wireValue})';
}

/// Reads the server's violation out of a callable's `details`, or `null`.
///
/// Strict about shape and permissive about content, in that order: only a
/// string at `violation`, inside a map, that names a violation this client
/// knows, is read. Everything else is discarded rather than rendered, because
/// `details` is `dynamic` and an arbitrary value reaching a widget is the
/// defect this whole boundary exists to prevent.
InvitationAcceptanceViolation? invitationAcceptanceViolationFromDetails(
  Object? details,
) {
  if (details is! Map) return null;
  return InvitationAcceptanceViolation.fromWireOrNull(details['violation']);
}

/// Maps any acceptance failure to a sentence somebody wrote.
///
/// The organising rule is one sentence, and it is what the reported defect
/// violated:
///
/// > **Only a failure this app knows to be transient may invite a retry.**
///
/// Every refusal the server's policy produces is permanent for the invitation
/// it refused — a flag fixed at invite time, a consumed token, a cancelled
/// invitation, a suspended business — so none of them says "try again", and
/// each names the one thing that can actually move the user forward instead.
/// Only an unreachable server and an exhausted rate limit do, because for those
/// two a retry is the answer.
String invitationAcceptanceSafeError(
  Object error, {
  required InvitationAcceptanceMode mode,
}) {
  if (error is! InvitationAcceptanceException) return _unknownFailure;

  final violation = error.violation;
  if (violation != null) {
    return switch (violation) {
      InvitationAcceptanceViolation.versionedProofRequired =>
        'This invitation has to be opened from the link in your invitation '
            'email, so it cannot be accepted here. Ask your administrator to '
            'send the invitation again if you no longer have that email.',
      InvitationAcceptanceViolation.emailUnverified =>
        'Verify your email address first, then accept this invitation.',
      InvitationAcceptanceViolation.callerMismatch =>
        'This invitation was issued to a different account. Sign in as the '
            'invited account to accept it.',
      InvitationAcceptanceViolation.emailMismatch =>
        'This invitation was sent to a different email address than the one '
            'you are signed in with. Sign in as the invited address, or ask '
            'your administrator to reissue the invitation.',
      InvitationAcceptanceViolation.invitationConsumed =>
        'This invitation has already been used. Ask your administrator if you '
            'still cannot reach the business.',
      // One sentence for two tokens on purpose. The server separates the
      // membership record from the invitation record; a user has no way to
      // tell them apart and the same person fixes both.
      InvitationAcceptanceViolation.membershipNotPending ||
      InvitationAcceptanceViolation.invitationNotPending =>
        'This invitation is no longer open. Ask your administrator to invite '
            'you again.',
      InvitationAcceptanceViolation.tenantInactive =>
        'This business is not active, so its invitations cannot be accepted. '
            'Ask your administrator.',
    };
  }

  return switch (error.code) {
    // The server refuses several ways without naming a violation, and which
    // ones are reachable depends entirely on the path: a rejected HMAC proof on
    // the token path, and a disabled, address-less, or unverified identity on
    // the visible one.
    'permission-denied' => switch (mode) {
      InvitationAcceptanceMode.token =>
        'This invitation link is no longer valid. Ask your administrator to '
            'send a new invitation.',
      InvitationAcceptanceMode.visible =>
        'This account cannot accept invitations yet. Check that your email '
            'address is verified, and ask your administrator if it still '
            'fails.',
    },
    // Overloaded on the server, and worded for the case that actually happens.
    // Acceptance requires an authentication under five minutes old, so a
    // session left open is the ordinary cause; the same instruction is what
    // `accountVerificationSafeError` gives for its own five-minute window.
    'failed-precondition' =>
      'For your security, sign out and sign in again, then accept the '
          'invitation within five minutes.',
    'unauthenticated' => 'Sign in again to accept this invitation.',
    'resource-exhausted' =>
      'Too many attempts from this device. Wait a few minutes and try again.',
    'unavailable' ||
    'deadline-exceeded' =>
      'This device could not reach the server. Check the connection and try '
          'again.',
    _ => _unknownFailure,
  };
}

/// Names no cause, and offers no retry.
///
/// It cannot name one: the failure reaching here is a code this client does not
/// model, a malformed response, or a defect. It deliberately stops short of
/// "try again" — an acceptance that failed for an unmodelled reason is far more
/// often a policy refusal than a blip, the button is still there for anyone who
/// wants to retry anyway, and naming the person who can actually reissue the
/// invitation is the only advice that is true either way.
const String _unknownFailure =
    'This invitation could not be accepted. Ask your administrator to send it '
    'again if this keeps happening.';
