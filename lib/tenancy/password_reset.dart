/// Asking for a password-reset email.
///
/// **The backend for this has been complete and tested the whole time.**
/// `requestPasswordReset` enqueues `deliverPasswordReset`, which mints a
/// Firebase reset link, sends it through Brevo, hashes the recipient with a
/// keyring, honours the suppression list and retries with backoff. Nothing in
/// Dart has ever called it, and the sign-in screen has never carried a *Forgot
/// password* control - so a cashier who forgot a password was locked out with
/// no route back that did not involve an administrator.
///
/// **The one rule this file exists to keep: the answer is always the same.**
/// `preparePasswordResetRequest` returns `{accepted: true}` whether or not the
/// address belongs to an account, deliberately, so that the endpoint cannot be
/// used to discover who has one. A UI that said *no account uses that address*
/// would hand back exactly the disclosure the server refused to make. This
/// boundary therefore has **no** notion of "not found": there is one success
/// state, and the failures below are all about whether the request was
/// *delivered to the server*, never about what the server found.
library;

import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import '../observability/app_telemetry.dart';

/// Narrow callable boundary over `requestPasswordReset`.
abstract interface class RequestPasswordResetCallable {
  Future<Object?> call(Map<String, Object?> payload);
}

/// A refusal the callable issued, carrying its code and nothing else.
final class PasswordResetCallableException implements Exception {
  const PasswordResetCallableException(this.code);

  final String code;

  @override
  String toString() => 'PasswordResetCallableException($code)';
}

/// Firebase adapter for `requestPasswordReset`.
///
/// **The one endpoint an unauthenticated stranger may call.** It enforced App
/// Check until 2026-09-24, which refused every release build because none
/// sends a token; it no longer does, so a release build is answered like a
/// debug one.
final class FirebaseRequestPasswordResetCallable
    implements RequestPasswordResetCallable {
  FirebaseRequestPasswordResetCallable({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    try {
      final result = await traceServerCall(
        'requestPasswordReset',
        () => _functions
            .httpsCallable('requestPasswordReset')
            .call<Object?>(payload),
      );
      return result.data;
    } on FirebaseFunctionsException catch (error) {
      throw PasswordResetCallableException(error.code);
    }
  }
}

typedef PasswordResetRequestIdFactory = String Function();

/// A defect in what was typed, nameable without asking anybody.
enum PasswordResetInputDefect { missingEmail }

/// Reads what is wrong with what was typed, before the server is asked.
PasswordResetInputDefect? passwordResetInputDefect({required String email}) =>
    email.trim().isEmpty ? PasswordResetInputDefect.missingEmail : null;

String passwordResetInputDefectMessage(PasswordResetInputDefect defect) =>
    switch (defect) {
      PasswordResetInputDefect.missingEmail =>
        'Enter the email address for the account.',
    };

/// What kind of answer a reset request got.
enum PasswordResetFailureKind {
  /// The server answered and would not take the request.
  refused,

  /// The server was never reached, so nothing was requested.
  unreachable,
}

final class PasswordResetFailure {
  const PasswordResetFailure({required this.kind, required this.message});

  final PasswordResetFailureKind kind;
  final String message;

  @override
  bool operator ==(Object other) =>
      other is PasswordResetFailure &&
      other.kind == kind &&
      other.message == message;

  @override
  int get hashCode => Object.hash(kind, message);

  @override
  String toString() => 'PasswordResetFailure(${kind.name}: $message)';
}

/// Maps any reset failure to a kind and a sentence somebody wrote.
///
/// **Nothing here can say whether an account exists**, because nothing here
/// knows: a delivered request is `{accepted: true}` in every case. See the
/// library note.
PasswordResetFailure passwordResetFailure(Object error) {
  if (error is! PasswordResetCallableException) return _passwordResetUnknown;
  return switch (error.code) {
    'unavailable' || 'deadline-exceeded' => const PasswordResetFailure(
      kind: PasswordResetFailureKind.unreachable,
      message:
          'This device could not reach the server. Check the connection and '
          'try again.',
    ),
    'resource-exhausted' => const PasswordResetFailure(
      kind: PasswordResetFailureKind.refused,
      message:
          'Too many requests from this device. Wait a few minutes and try '
          'again.',
    ),
    // The server would not accept this caller. App Check was the reason until
    // the function stopped enforcing it; nothing expected produces this now.
    // It is not the person's fault or their address's - so it names neither.
    'unauthenticated' || 'permission-denied' => const PasswordResetFailure(
      kind: PasswordResetFailureKind.refused,
      message:
          'This app could not prove itself to the server. Update the app, and '
          'contact support if it keeps happening.',
    ),
    'invalid-argument' => const PasswordResetFailure(
      kind: PasswordResetFailureKind.refused,
      message: 'That is not a valid email address. Check it and try again.',
    ),
    _ => _passwordResetUnknown,
  };
}

const PasswordResetFailure _passwordResetUnknown = PasswordResetFailure(
  kind: PasswordResetFailureKind.refused,
  message:
      'The request could not be sent. Try again, and contact support if it '
      'keeps happening.',
);

/// One request to send a reset email.
final class PasswordResetIntent {
  const PasswordResetIntent._({required this.email, required this.requestId});

  final String email;
  final String requestId;

  Map<String, Object?> toPayload() => <String, Object?>{
    'email': email,
    'requestId': requestId,
  };
}

/// The guarded boundary a screen calls.
final class PasswordResetGateway {
  PasswordResetGateway({
    required RequestPasswordResetCallable callable,
    PasswordResetRequestIdFactory? requestIdFactory,
  }) : _callable = callable,
       _requestIdFactory = requestIdFactory ?? _secureResetRequestId;

  final RequestPasswordResetCallable _callable;
  final PasswordResetRequestIdFactory _requestIdFactory;

  PasswordResetIntent createIntent({required String email}) {
    final defect = passwordResetInputDefect(email: email);
    if (defect != null) {
      throw StateError('The reset request is missing an email address.');
    }
    final requestId = _requestIdFactory();
    if (!_requestIdPattern.hasMatch(requestId)) {
      throw StateError('The reset request ID generator is invalid.');
    }
    // Normalized here as well as on the server: the same address typed with a
    // capital would otherwise be a different `requestId` subject on retry, and
    // the server's own `normalizeEmail` would then collapse two requests it had
    // already given two task IDs.
    return PasswordResetIntent._(
      email: email.trim().toLowerCase(),
      requestId: requestId,
    );
  }

  /// Sends [intent]. Completes on success and throws a
  /// [PasswordResetCallableException] otherwise.
  ///
  /// **The response is deliberately not inspected.** It is `{accepted: true}`
  /// and nothing else, in every case the server handles, so parsing it could
  /// only ever produce a distinction the server refused to draw.
  Future<void> submit(PasswordResetIntent intent) async {
    await _callable.call(intent.toPayload());
  }
}

/// The sentence shown once a request has been accepted.
///
/// **It names no account, and that is the point.** The server answers
/// identically for an address it knows and one it does not; saying "we have
/// sent you an email" would assert something this app was never told.
const String passwordResetAcceptedMessage =
    'If that address belongs to an account, a link to set a new password is on '
    'its way. It may take a minute, and it may be in the spam folder.';

String _secureResetRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'reset-${base64Url.encode(bytes).replaceAll('=', '')}';
}

final _requestIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$');
