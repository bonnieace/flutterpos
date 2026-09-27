/// The rest of signing up: who this is, and correcting where the link went.
///
/// **Shaped like `account_registration.dart`, deliberately.** A narrow interface
/// so nothing above it holds a `FirebaseFunctionsException`; an exception
/// carrying a code and no message; input-defect checks that run first; and one
/// switch per callable that decides the kind and the sentence together, because
/// a second switch over the same codes is how the two come to disagree.
///
/// **Why these are callables rather than writes.** `firestore.rules` holds
/// `users/{uid}` at `allow create, update, delete: if false` - the root document
/// is server-owned, and that is what keeps `accountType`, `globalStatus` and
/// `identityOrigin` out of a client's reach. A name and a phone live on the same
/// document, so they arrive the same way.
library;

import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';

import 'sign_in.dart' show SignInFailureKind;
import '../observability/app_telemetry.dart';

typedef AccountProfileRequestIdFactory = String Function();

/// Narrow boundary over `completeSelfSignup`.
abstract interface class CompleteSelfSignupCallable {
  Future<Object?> call(Map<String, Object?> payload);
}

/// Narrow boundary over `changeSignupEmail`.
abstract interface class ChangeSignupEmailCallable {
  Future<Object?> call(Map<String, Object?> payload);
}

/// A refusal the server issued, carrying its code and nothing else.
final class AccountProfileException implements Exception {
  const AccountProfileException(this.code);

  final String code;

  @override
  String toString() => 'AccountProfileException($code)';
}

final class FirebaseCompleteSelfSignupCallable
    implements CompleteSelfSignupCallable {
  FirebaseCompleteSelfSignupCallable({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    try {
      final result = await traceServerCall(
        'completeSelfSignup',
        () => _functions
            .httpsCallable('completeSelfSignup')
            .call<Object?>(payload),
      );
      return result.data;
    } on FirebaseFunctionsException catch (error) {
      throw AccountProfileException(error.code);
    }
  }
}

final class FirebaseChangeSignupEmailCallable
    implements ChangeSignupEmailCallable {
  FirebaseChangeSignupEmailCallable({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    try {
      final result = await traceServerCall(
        'changeSignupEmail',
        () => _functions
            .httpsCallable('changeSignupEmail')
            .call<Object?>(payload),
      );
      return result.data;
    } on FirebaseFunctionsException catch (error) {
      throw AccountProfileException(error.code);
    }
  }
}

/// A defect in what was typed, nameable without asking anybody.
enum AccountProfileInputDefect { missingName, nameTooShort, nameTooLong }

const int minimumAccountNameLength = 2;
const int maximumAccountNameLength = 80;

/// Reads what is wrong with the name, before the server is asked.
///
/// The phone has its own rules and its own sentences in `phone_number.dart`,
/// because a dialling code and a subscriber number fail in ways a length check
/// cannot name.
AccountProfileInputDefect? accountNameDefect(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return AccountProfileInputDefect.missingName;
  if (trimmed.length < minimumAccountNameLength) {
    return AccountProfileInputDefect.nameTooShort;
  }
  if (trimmed.length > maximumAccountNameLength) {
    return AccountProfileInputDefect.nameTooLong;
  }
  return null;
}

String accountProfileInputDefectMessage(AccountProfileInputDefect defect) =>
    switch (defect) {
      AccountProfileInputDefect.missingName => 'Enter your name.',
      AccountProfileInputDefect.nameTooShort =>
        'Enter at least $minimumAccountNameLength characters.',
      AccountProfileInputDefect.nameTooLong =>
        'Use at most $maximumAccountNameLength characters.',
    };

/// An address that moved, and the session offered to outlive the move.
final class AccountAddressChange {
  const AccountAddressChange({required this.email, this.sessionToken});

  /// The address the account now holds, as the server normalized it.
  final String email;

  /// A single-use credential for the same account, or null if none was minted.
  final String? sessionToken;
}

/// One attempt at naming the account, and its stable idempotency key.
///
/// **The key travels with the input it was minted for.** The server records a
/// hash of the payload against the key, and refuses a replay whose input has
/// moved - so a key reused for a different name is a refusal rather than an
/// edit. Carrying both on one object is what makes that unreachable from here:
/// there is no way to send this key with anything but these values.
final class AccountSignupIntent {
  const AccountSignupIntent._({
    required this.displayName,
    required this.phone,
    required this.requestId,
  });

  /// Trimmed here rather than at the callable, so what the key was minted for
  /// and what is sent are the same string.
  final String displayName;
  final String phone;
  final String requestId;
}

/// One attempt at moving the address, and its stable idempotency key.
///
/// Same reasoning as [AccountSignupIntent]. The address is the whole of the
/// input, so comparing it is how a caller knows whether it may reuse the key.
final class AccountAddressChangeIntent {
  const AccountAddressChangeIntent._({
    required this.email,
    required this.requestId,
  });

  final String email;
  final String requestId;
}

/// The shape every request ID in this app is checked against before it is sent.
///
/// Declared per file rather than shared, as `tenant_request.dart` and the staff
/// surfaces declare it: an invalid key is a defect in whatever was injected, and
/// it is worth catching here rather than at the server.
final RegExp _accountProfileRequestIdPattern = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$',
);

/// What the client sends and what it gets back, as one guarded round trip.
final class AccountProfileGateway {
  AccountProfileGateway({
    required CompleteSelfSignupCallable completeCallable,
    required ChangeSignupEmailCallable changeEmailCallable,
    AccountProfileRequestIdFactory? requestIdFactory,
  }) : _complete = completeCallable,
       _changeEmail = changeEmailCallable,
       _requestIdFactory = requestIdFactory ?? _secureAccountProfileRequestId;

  final CompleteSelfSignupCallable _complete;
  final ChangeSignupEmailCallable _changeEmail;
  final AccountProfileRequestIdFactory _requestIdFactory;

  /// Mints one key for one attempt at naming the account.
  ///
  /// **Called once per attempt, never per call.** Minting inside [completeSignup]
  /// is what made a retry a second logical operation: the server is idempotent by
  /// request ID, and a fresh ID every time is the one input that defeats it. The
  /// caller holds what this returns for as long as the attempt lasts. See
  /// `_OnboardingFlowState._signupIntentFor`.
  AccountSignupIntent createSignupIntent({
    required String displayName,
    required String phone,
  }) {
    final requestId = _requestIdFactory();
    if (!_accountProfileRequestIdPattern.hasMatch(requestId)) {
      throw StateError('The account profile request ID is invalid.');
    }
    return AccountSignupIntent._(
      displayName: displayName.trim(),
      phone: phone,
      requestId: requestId,
    );
  }

  /// Mints one key for one attempt at moving the address.
  ///
  /// The same reasoning as [createSignupIntent], and the failure it cures is
  /// worse: a retry under a fresh key is refused by the address the previous
  /// attempt already set.
  AccountAddressChangeIntent createAddressChangeIntent(String email) {
    final requestId = _requestIdFactory();
    if (!_accountProfileRequestIdPattern.hasMatch(requestId)) {
      throw StateError('The account profile request ID is invalid.');
    }
    return AccountAddressChangeIntent._(
      email: email.trim(),
      requestId: requestId,
    );
  }

  /// Names the account and records the phone. The server sends the first
  /// verification email as part of this call; nothing here asks for it.
  Future<void> completeSignup(AccountSignupIntent intent) async {
    final response = await _complete.call(<String, Object?>{
      'displayName': intent.displayName,
      'phone': intent.phone,
      'requestId': intent.requestId,
    });
    if (response is! Map ||
        response['displayName'] is! String ||
        response['phone'] is! String) {
      throw const FormatException(
        'completeSelfSignup returned an invalid result.',
      );
    }
  }

  /// Moves an unverified signup's address, and sends the link to the new one.
  ///
  /// **[AccountAddressChange.sessionToken] is how the session survives this.**
  /// Rewriting the Auth email rebinds the password credential, so the refresh
  /// token on the device stops working and the SDK signs out moments later. The
  /// server mints a replacement the client can exchange before that happens.
  /// Absent means it could not: the address still moved, and the session is
  /// still about to end.
  ///
  /// **A replay is how an ambiguous attempt recovers.** Sending [intent] again
  /// after a lost response reaches `changeSignupEmail`'s recorded result rather
  /// than its "that is already your address" guard, and the reply carries a
  /// freshly minted session token - which is exactly what the lost response took
  /// with it.
  Future<AccountAddressChange> changeEmail(
    AccountAddressChangeIntent intent,
  ) async {
    final response = await _changeEmail.call(<String, Object?>{
      'email': intent.email,
      'requestId': intent.requestId,
    });
    if (response is! Map || response['email'] is! String) {
      throw const FormatException(
        'changeSignupEmail returned an invalid result.',
      );
    }
    final token = response['sessionToken'];
    return AccountAddressChange(
      email: response['email']! as String,
      // Read defensively rather than asserted: a server that could not mint one
      // sends no field at all, and that is a documented outcome rather than a
      // malformed reply.
      sessionToken: token is String && token.isNotEmpty ? token : null,
    );
  }
}

/// The sentence shown for a refusal, and the shape it is drawn in.
///
/// One switch for both, for the reason `registrationFailure` gives: two switches
/// over the same codes are how the kind and the sentence come to disagree.
({SignInFailureKind kind, String message}) accountProfileFailure(Object error) {
  final code = error is AccountProfileException ? error.code : '';
  return switch (code) {
    'unauthenticated' => (
      kind: SignInFailureKind.refused,
      message: 'Sign in again to finish setting up your account.',
    ),
    'already-exists' => (
      kind: SignInFailureKind.refused,
      message: 'An account already uses that address. Try signing in instead.',
    ),
    'invalid-argument' => (
      kind: SignInFailureKind.refused,
      message: 'Check the details and try again.',
    ),
    'resource-exhausted' => (
      kind: SignInFailureKind.refused,
      message:
          'That has been changed too many times today. Try again tomorrow.',
    ),
    'failed-precondition' => (
      kind: SignInFailureKind.refused,
      message: 'That address cannot be changed here.',
    ),
    'permission-denied' => (
      kind: SignInFailureKind.refused,
      message: 'This account cannot be set up. Contact support.',
    ),
    // **The callable is not there.** A build that reaches a backend without
    // `completeSelfSignup` deployed answers `not-found`, and it used to fall
    // through to "Something went wrong", which is the one sentence that cannot
    // be acted on by the person reading it *or* by whoever they report it to.
    // The account itself is fine - it exists and the flow resumes at this same
    // step - so this says the part that is actually wrong.
    'not-found' || 'unimplemented' => (
      kind: SignInFailureKind.unreachable,
      message:
          'This app is newer than the server. Update the app, or ask '
          'support to finish the deployment.',
    ),
    'unavailable' || 'deadline-exceeded' => (
      kind: SignInFailureKind.unreachable,
      message: 'The server could not be reached. Check your connection.',
    ),
    _ => (
      kind: SignInFailureKind.refused,
      message:
          'Something went wrong. Try again, and contact support if it '
          'keeps happening.',
    ),
  };
}

/// 18 random bytes, base64url, behind a readable prefix.
///
/// The same shape and the same reasoning as the tenant-request and verification
/// ids: it is an idempotency key, so it must be unguessable and stable across
/// the retries of one attempt.
String _secureAccountProfileRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'profile-${base64Url.encode(bytes).replaceAll('=', '')}';
}
