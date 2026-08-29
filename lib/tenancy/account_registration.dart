/// Creating an account, as a boundary shaped exactly like [sign_in.dart]'s.
///
/// **The gap this closes.** `createUserWithEmailAndPassword` appeared nowhere in
/// this app. The only code that ever produced a `users/{uid}` root document was
/// staff-invitation provisioning, and `requestTenant` refuses an applicant
/// without one - so the self-serve path this product is built around
/// (sign up, verify, request a business, be approved) had no first step. The
/// server half landed with `bootstrapSelfSignupIdentity`; this is the client
/// half.
///
/// **Everything here is `sign_in.dart`'s shape, deliberately.** A narrow
/// interface so nothing above it holds a `FirebaseAuthException`; an exception
/// carrying a code and no message; an input-defect check that runs first; and
/// one switch that decides the kind and the sentence together, because a second
/// switch over the same codes is how the two come to disagree.
library;

import 'package:firebase_auth/firebase_auth.dart';

import 'sign_in.dart' show SignInFailureKind;

/// Narrow boundary over creating an email-and-password account.
abstract interface class EmailPasswordRegistration {
  /// Creates the account and leaves it signed in, or throws.
  ///
  /// **Signed in on success, and that is the product decision.** Firebase signs
  /// a newly created user in as a side effect, and this does not undo it: the
  /// next step is the business selector, where `AccountVerificationPanel` and
  /// `TenantRequestForm` already live, and both need a signed-in identity.
  Future<void> call({required String email, required String password});
}

/// A refusal the identity provider issued, carrying its code and nothing else.
final class RegistrationException implements Exception {
  const RegistrationException(this.code);

  final String code;

  @override
  String toString() => 'RegistrationException($code)';
}

/// Firebase adapter for account creation.
final class FirebaseEmailPasswordRegistration
    implements EmailPasswordRegistration {
  FirebaseEmailPasswordRegistration({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  @override
  Future<void> call({required String email, required String password}) async {
    try {
      await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (error) {
      throw RegistrationException(error.code);
    }
  }
}

/// A defect in what was typed, nameable without asking anybody.
enum RegistrationInputDefect {
  missingEmail,
  missingPassword,
  missingConfirmation,

  /// The two passwords do not match.
  ///
  /// Checked here rather than at the server because the server never sees the
  /// second one: a confirmation field exists precisely so a typo in a password
  /// nobody can read is caught before it becomes the account's password.
  confirmationMismatch,

  /// Shorter than Firebase's own minimum.
  ///
  /// **Six, because that is the number Firebase enforces**, and refusing it
  /// here turns a round trip into an instant answer while the person is still
  /// looking at the field. The server still decides: `weak-password` is mapped
  /// below and remains reachable, since a project may raise the minimum.
  passwordTooShort,
}

/// The shortest password Firebase's own default policy accepts.
const int minimumRegistrationPasswordLength = 6;

/// Reads what is wrong with what was typed, before an account is requested.
RegistrationInputDefect? registrationInputDefect({
  required String email,
  required String password,
  required String confirmation,
}) {
  if (email.trim().isEmpty) return RegistrationInputDefect.missingEmail;
  if (password.isEmpty) return RegistrationInputDefect.missingPassword;
  if (password.length < minimumRegistrationPasswordLength) {
    return RegistrationInputDefect.passwordTooShort;
  }
  if (confirmation.isEmpty) return RegistrationInputDefect.missingConfirmation;
  if (password != confirmation) {
    return RegistrationInputDefect.confirmationMismatch;
  }
  return null;
}

/// The sentence shown for a defect this app found itself.
String registrationInputDefectMessage(RegistrationInputDefect defect) =>
    switch (defect) {
      RegistrationInputDefect.missingEmail =>
        'Enter the email address this account will use.',
      RegistrationInputDefect.missingPassword => 'Choose a password.',
      RegistrationInputDefect.missingConfirmation =>
        'Type the password a second time.',
      RegistrationInputDefect.confirmationMismatch =>
        'The two passwords are not the same.',
      RegistrationInputDefect.passwordTooShort =>
        'A password needs at least $minimumRegistrationPasswordLength '
            'characters.',
    };

/// A registration failure: what kind of answer it was, and the sentence for it.
final class RegistrationFailure {
  const RegistrationFailure({required this.kind, required this.message});

  /// Reused from sign-in rather than declared again: *refused* and
  /// *unreachable* mean exactly the same two things here, and a second enum
  /// with the same two values is how one screen comes to draw them differently.
  final SignInFailureKind kind;

  final String message;

  @override
  bool operator ==(Object other) =>
      other is RegistrationFailure &&
      other.kind == kind &&
      other.message == message;

  @override
  int get hashCode => Object.hash(kind, message);

  @override
  String toString() => 'RegistrationFailure(${kind.name}: $message)';
}

/// Maps any registration failure to a kind and a sentence somebody wrote.
///
/// **An address already in use is answered plainly here, and that is a
/// departure from sign-in.** `signInFailure` collapses a wrong password and an
/// unknown address into one sentence to avoid disclosing which addresses exist;
/// this cannot, because refusing to say why an account was not created leaves
/// somebody stuck with no way forward. Firebase itself makes the same
/// distinction - with email enumeration protection on it still answers
/// `email-already-in-use` - so the disclosure is the platform's, not this app's,
/// and the sentence points at the two ways out rather than stopping at *no*.
RegistrationFailure registrationFailure(Object error) {
  if (error is! RegistrationException) return _registrationUnknown;
  return switch (error.code) {
    'email-already-in-use' => const RegistrationFailure(
      kind: SignInFailureKind.refused,
      message:
          'An account already uses that email address. Sign in instead, or '
          'reset the password if it has been forgotten.',
    ),
    'invalid-email' => const RegistrationFailure(
      kind: SignInFailureKind.refused,
      message: 'That is not a valid email address. Check it and try again.',
    ),
    'weak-password' => const RegistrationFailure(
      kind: SignInFailureKind.refused,
      message: 'That password is too easy to guess. Choose a longer one.',
    ),
    'missing-email' => const RegistrationFailure(
      kind: SignInFailureKind.refused,
      message: 'Enter the email address this account will use.',
    ),
    'missing-password' => const RegistrationFailure(
      kind: SignInFailureKind.refused,
      message: 'Choose a password.',
    ),
    'too-many-requests' => const RegistrationFailure(
      kind: SignInFailureKind.refused,
      message:
          'Too many attempts from this device. Wait a few minutes and try '
          'again.',
    ),
    // **The one branch that is not a refusal**, for the reason sign-in gives:
    // nothing answered, so nothing was refused.
    'network-request-failed' => const RegistrationFailure(
      kind: SignInFailureKind.unreachable,
      message:
          'This device could not reach the server. Check the connection and '
          'try again.',
    ),
    'operation-not-allowed' => const RegistrationFailure(
      kind: SignInFailureKind.refused,
      message:
          'Creating an account with an email address and password is not '
          'enabled for this app. Contact support.',
    ),
    // **What a refused blocking function looks like from here.**
    // `bootstrapSelfSignupIdentity` runs inside account creation and aborts it
    // by throwing - an account with no usable address, or a Firestore that
    // would not take the root document. The client is handed one of these
    // rather than the reason, so the sentence names no cause and the account
    // genuinely does not exist, which is the outcome the person needs to know.
    'internal-error' ||
    'blocking-function-error-response' => const RegistrationFailure(
      kind: SignInFailureKind.refused,
      message:
          'The account could not be set up. Try again, and contact support if '
          'it keeps happening.',
    ),
    _ => _registrationUnknown,
  };
}

/// [registrationFailure]'s sentence, for a caller that wants only the words.
String registrationSafeError(Object error) => registrationFailure(error).message;

const RegistrationFailure _registrationUnknown = RegistrationFailure(
  kind: SignInFailureKind.refused,
  message:
      'The account could not be created. Try again, and contact support if it '
      'keeps happening.',
);
