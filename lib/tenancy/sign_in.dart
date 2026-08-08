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

/// Maps any sign-in failure to a sentence somebody wrote.
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
String signInSafeError(Object error) {
  if (error is! SignInException) return _signInUnknownFailure;
  return switch (error.code) {
    'invalid-email' =>
      'That is not a valid email address. Check it and try again.',
    // Structurally unreachable while `signInInputDefect` runs first, and worded
    // through it anyway so one fact cannot be worded two ways.
    'missing-email' => 'Enter the email address for this account.',
    'missing-password' => 'Enter the password for this account.',
    'user-disabled' =>
      'This account has been disabled. Contact your administrator.',
    'too-many-requests' =>
      'Too many sign-in attempts from this device. Wait a few minutes and try '
          'again.',
    'network-request-failed' =>
      'This device could not reach the server. Check the connection and try '
          'again.',
    'operation-not-allowed' =>
      'Signing in with an email address and password is not enabled for this '
          'app. Contact support.',
    'wrong-password' ||
    'user-not-found' ||
    'invalid-credential' ||
    'invalid-login-credentials' ||
    'INVALID_LOGIN_CREDENTIALS' => _signInCredentialMismatch,
    _ => _signInUnknownFailure,
  };
}

const String _signInCredentialMismatch =
    'That email address and password do not match an account. Check both and '
    'try again.';

const String _signInUnknownFailure =
    'Sign-in could not be completed. Try again, and contact support if it keeps '
    'happening.';
