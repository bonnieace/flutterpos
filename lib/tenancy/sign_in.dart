import 'package:firebase_auth/firebase_auth.dart';

/// Narrow boundary over email-and-password sign-in.
///
/// It exists so that nothing above it ever holds a `FirebaseAuthException`, and
/// therefore nothing above it can render one. "A user is shown a sentence, never
/// an exception" is a property of this shape rather than of care taken at each
/// call site: the only thing that crosses the boundary is a code.
abstract interface class EmailPasswordSignIn {
  /// Signs in, or throws.
  ///
  /// [remember] selects the Firebase persistence the session is kept under. It
  /// is part of the call rather than a separate step because the two are one
  /// intent, and a caller that could do the second without the first would be
  /// able to change persistence for a session it is not creating.
  Future<void> call({
    required String email,
    required String password,
    required bool remember,
  });
}

/// A refusal the identity provider issued, carrying its code and nothing else.
///
/// Deliberately no `message`. The provider's sentence is written for whoever is
/// reading a log, it is not translated, and it is sometimes not a sentence at
/// all — see [signInSafeError] — so it is dropped here rather than guarded
/// against at every surface that might display it.
final class SignInException implements Exception {
  const SignInException(this.code);

  final String code;

  @override
  String toString() => 'SignInException($code)';
}

/// Firebase adapter for email-and-password sign-in.
final class FirebaseEmailPasswordSignIn implements EmailPasswordSignIn {
  FirebaseEmailPasswordSignIn({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  @override
  Future<void> call({
    required String email,
    required String password,
    required bool remember,
  }) async {
    try {
      await _auth.setPersistence(
        remember ? Persistence.LOCAL : Persistence.SESSION,
      );
    } catch (_) {
      // Persistence is a web concept. Every other platform is always local and
      // answers `unimplemented`, so a failure here is the expected case on the
      // platforms this app ships to and must never decide whether the sign-in
      // below is attempted.
    }

    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (error) {
      throw SignInException(error.code);
    }
  }
}

/// A defect in what was typed, nameable without asking anybody.
enum SignInInputDefect {
  /// No email address was typed.
  missingEmail,

  /// No password was typed.
  missingPassword,
}

/// Reads what is wrong with what was typed, before a credential is sent.
///
/// This is correctness, not politeness. An empty password is not a credential,
/// and submitting one reached a platform channel that threw something which was
/// **not** a `FirebaseAuthException`, so the first screen of this app printed
/// `dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.signInWithEmailAndPassword`
/// at whoever was signing in. Refusing it here is the fix for that path;
/// [signInSafeError] is what makes the whole class of defect unrenderable.
SignInInputDefect? signInInputDefect({
  required String email,
  required String password,
}) {
  if (email.trim().isEmpty) return SignInInputDefect.missingEmail;
  // Deliberately not trimmed, and deliberately not otherwise judged. A space is
  // a character a password may legitimately contain, so a password made of them
  // is one the server must decide about; the only thing this app knows is wrong
  // is a password that is not there at all.
  if (password.isEmpty) return SignInInputDefect.missingPassword;
  return null;
}

/// The sentence shown for a defect this app found itself.
String signInInputDefectMessage(SignInInputDefect defect) => switch (defect) {
  SignInInputDefect.missingEmail => 'Enter the email address for this account.',
  SignInInputDefect.missingPassword => 'Enter the password for this account.',
};

/// What kind of answer a sign-in failure is.
///
/// **It exists because two of these are not the same thing and had been drawn
/// identically.** Until §11 step 9 the screen held a `String?` and painted every
/// one of them red, so *this device has no connection* and *that password is
/// wrong* were one sentence in one colour — the same half-model the seven
/// back-office surfaces held before `AppNotice`, on the one screen the notice
/// sweep of 2026-08-15 did not reach, because sign-in names its state
/// `login-error` rather than a notice.
///
/// **The kind is decided here rather than at the screen** for the reason
/// [signInSafeError] gives about the message: the only thing that crosses this
/// boundary is a code, so the only place that can read one is this file. What
/// the screen does with the kind — which §2.1 status it becomes — is the
/// screen's, and stays there.
enum SignInFailureKind {
  /// The attempt was answered and nobody was signed in.
  ///
  /// A wrong credential, a disabled account, a rate limit, a method that is not
  /// enabled: all different sentences, all the same standing. It is also where
  /// an unrecognised code lands, because a failure this app cannot name is
  /// still a failure to sign in rather than an open question.
  refused,

  /// The identity provider was never reached, so nothing was refused.
  ///
  /// Nothing is wrong with the credential and nothing is wrong with the
  /// account; the device could not get there. §2.1 gives that `info` and not
  /// `problem`, and it is the whole reason this enum has two values.
  unreachable,
}

/// A sign-in failure: what kind of answer it was, and the sentence for it.
final class SignInFailure {
  const SignInFailure({required this.kind, required this.message});

  final SignInFailureKind kind;

  /// The sentence a person reads. See [signInSafeError].
  final String message;

  @override
  bool operator ==(Object other) =>
      other is SignInFailure &&
      other.kind == kind &&
      other.message == message;

  @override
  int get hashCode => Object.hash(kind, message);

  @override
  String toString() => 'SignInFailure(${kind.name}: $message)';
}

/// Maps any sign-in failure to a kind and a sentence somebody wrote.
///
/// Three properties, and the first is the one that matters:
///
/// 1. **It reads a code and never a message.** Anything that is not a
///    [SignInException] — a platform channel error, a plugin defect, a
///    programming mistake — answers with [_signInUnknownFailure], so no string
///    this app did not write can reach a user. Mapping the one code that caused
///    the reported defect would have left every other channel-level failure
///    printing itself.
/// 2. **A wrong password, an unknown address, and a malformed credential give
///    one identical sentence.** Firebase itself collapses them into
///    `invalid-credential` once email enumeration protection is on, so
///    distinguishing them here would be a disclosure that survives only until
///    that setting changes — and this app already closes enumeration deliberately
///    on the password-reset endpoint.
/// 3. **The fallback names no cause.** It cannot: the failure may have nothing
///    to do with the credential, and telling somebody with a correct password to
///    check their password is how a real fault stays hidden.
///
/// **One switch, not two.** The kind and the sentence are decided together
/// because a second switch over the same codes is how the two come to disagree
/// about one failure — the drift the token layer exists to prevent, in prose.
SignInFailure signInFailure(Object error) {
  if (error is! SignInException) return _signInUnknown;
  return switch (error.code) {
    'invalid-email' => const SignInFailure(
      kind: SignInFailureKind.refused,
      message: 'That is not a valid email address. Check it and try again.',
    ),
    // Structurally unreachable while `signInInputDefect` runs first, and worded
    // through it anyway so one fact cannot be worded two ways.
    'missing-email' => const SignInFailure(
      kind: SignInFailureKind.refused,
      message: 'Enter the email address for this account.',
    ),
    'missing-password' => const SignInFailure(
      kind: SignInFailureKind.refused,
      message: 'Enter the password for this account.',
    ),
    'user-disabled' => const SignInFailure(
      kind: SignInFailureKind.refused,
      message: 'This account has been disabled. Contact your administrator.',
    ),
    'too-many-requests' => const SignInFailure(
      kind: SignInFailureKind.refused,
      message:
          'Too many sign-in attempts from this device. Wait a few minutes and '
          'try again.',
    ),
    // **The one branch that is not a refusal.** Nothing answered, so nothing was
    // refused: the credential may be perfect and the account may be in order.
    'network-request-failed' => const SignInFailure(
      kind: SignInFailureKind.unreachable,
      message:
          'This device could not reach the server. Check the connection and '
          'try again.',
    ),
    'operation-not-allowed' => const SignInFailure(
      kind: SignInFailureKind.refused,
      message:
          'Signing in with an email address and password is not enabled for '
          'this app. Contact support.',
    ),
    'wrong-password' ||
    'user-not-found' ||
    'invalid-credential' ||
    'invalid-login-credentials' ||
    'INVALID_LOGIN_CREDENTIALS' => const SignInFailure(
      kind: SignInFailureKind.refused,
      message: _signInCredentialMismatch,
    ),
    _ => _signInUnknown,
  };
}

/// [signInFailure]'s sentence, for a caller that wants only the words.
String signInSafeError(Object error) => signInFailure(error).message;

const String _signInCredentialMismatch =
    'That email address and password do not match an account. Check both and '
    'try again.';

/// The answer for a failure this app cannot name.
///
/// **Refused rather than unknown**, and that is a decision worth stating: the
/// *cause* is unknown, which is why the sentence names none, but the *outcome*
/// is not — the screen is still here and nobody is signed in. §2.1's `attention`
/// means "awaiting", and nothing is awaiting.
const SignInFailure _signInUnknown = SignInFailure(
  kind: SignInFailureKind.refused,
  message:
      'Sign-in could not be completed. Try again, and contact support if it '
      'keeps happening.',
);
