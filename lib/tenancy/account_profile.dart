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
      final result = await _functions
          .httpsCallable('completeSelfSignup')
          .call<Object?>(payload);
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
      final result = await _functions
          .httpsCallable('changeSignupEmail')
          .call<Object?>(payload);
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

  /// Names the account and records the phone. The server sends the first
  /// verification email as part of this call; nothing here asks for it.
  Future<void> completeSignup({
    required String displayName,
    required String phone,
  }) async {
    final response = await _complete.call(<String, Object?>{
      'displayName': displayName.trim(),
      'phone': phone,
      'requestId': _requestIdFactory(),
    });
    if (response is! Map ||
        response['displayName'] is! String ||
        response['phone'] is! String) {
      throw const FormatException('completeSelfSignup returned an invalid result.');
    }
  }

  /// Moves an unverified signup's address, and sends the link to the new one.
  Future<String> changeEmail(String email) async {
    final response = await _changeEmail.call(<String, Object?>{
      'email': email.trim(),
      'requestId': _requestIdFactory(),
    });
    if (response is! Map || response['email'] is! String) {
      throw const FormatException('changeSignupEmail returned an invalid result.');
    }
    return response['email']! as String;
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
      message: 'That has been changed too many times today. Try again tomorrow.',
    ),
    'failed-precondition' => (
      kind: SignInFailureKind.refused,
      message: 'That address cannot be changed here.',
    ),
    'permission-denied' => (
      kind: SignInFailureKind.refused,
      message: 'This account cannot be set up. Contact support.',
    ),
    'unavailable' || 'deadline-exceeded' => (
      kind: SignInFailureKind.unreachable,
      message: 'The server could not be reached. Check your connection.',
    ),
    _ => (
      kind: SignInFailureKind.refused,
      message: 'Something went wrong. Try again, and contact support if it '
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
