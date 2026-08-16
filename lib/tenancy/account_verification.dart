import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'email_delivery_status.dart';
import 'tenant_bootstrap.dart';
import 'tenant_id.dart';

typedef AccountVerificationRequestIdFactory = String Function();
typedef AccountVerificationCurrentCheck = bool Function();

/// The request reached the server. §2.1's `ok` is *"reconciled, **confirmed**,
/// in stock"*, and what is confirmed is the request rather than the delivery -
/// which is exactly what the sentence is careful to say.
const AppNotice _requestAccepted = AppNotice.confirmed(
  'Request received. If this address can receive mail, a verification link is '
  'on its way. Open the link, then check again below.',
);

/// The address cannot be reached at all.
///
/// §2.1's `problem` is *"difference found, **unreadable**, out of stock"*, and
/// an address the provider will not deliver to is the closest of the five: a
/// state that will not resolve by trying again. It is deliberately not
/// `attention`, which is *awaiting*, because nothing here is awaited.
const AppNotice _undeliverable = AppNotice.refused(
  'This address cannot receive mail from us, so sending again will not help. '
  'Check the address or contact support.',
);

/// Reloads the signed-in identity from the server and reports whether the
/// address is now verified.
///
/// This is required rather than optional. `emailVerified` is a claim inside the
/// cached ID token, so it does not change when the user follows the link in
/// their mailbox; only a reload or a token refresh can observe it. A "check
/// again" action that skipped this would tell a verified user they are still
/// unverified forever.
typedef AccountVerificationReload = Future<void> Function();

/// Narrow callable boundary for `sendAccountVerification`.
abstract interface class SendAccountVerificationCallable {
  Future<Object?> call(Map<String, Object?> payload);
}

final class AccountVerificationCallableException implements Exception {
  const AccountVerificationCallableException(this.code);

  final String code;

  @override
  String toString() => 'AccountVerificationCallableException($code)';
}

/// Firebase adapter for `sendAccountVerification`; response validation remains
/// above it.
final class FirebaseSendAccountVerificationCallable
    implements SendAccountVerificationCallable {
  FirebaseSendAccountVerificationCallable({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    try {
      final result = await _functions
          .httpsCallable('sendAccountVerification')
          .call<Object?>(payload);
      return result.data;
    } on FirebaseFunctionsException catch (error) {
      throw AccountVerificationCallableException(error.code);
    }
  }
}

/// The signed-in identity that may ask for a verification email.
final class AccountVerificationIdentity {
  factory AccountVerificationIdentity({
    required String uid,
    required bool emailVerified,
    required RootRoutingProfile profile,
  }) => AccountVerificationIdentity._(
    uid: validateTenantDocumentId(uid.trim(), fieldName: 'uid'),
    emailVerified: emailVerified,
    globallyActive: profile.isActive,
  );

  const AccountVerificationIdentity._({
    required this.uid,
    required this.emailVerified,
    required this.globallyActive,
  });

  final String uid;
  final bool emailVerified;
  final bool globallyActive;

  /// Whether asking for the email is worth offering at all.
  ///
  /// The account type is deliberately not checked. Every identity signs in with
  /// an address, and the server decides eligibility from the canonical root
  /// record; narrowing it here would hide the only recovery path from an
  /// identity the server would have served.
  bool get canSendVerification => !emailVerified && globallyActive;
}

/// One request to send the email, with the idempotency key it will carry.
///
/// The key is created once per user intent and reused by every retry of that
/// intent, so a user who taps twice - or retries after a transport failure -
/// addresses the same delivery rather than sending a second email.
final class AccountVerificationIntent {
  const AccountVerificationIntent._({
    required this.uid,
    required this.requestId,
  });

  final String uid;
  final String requestId;
}

/// The outcome of an accepted request.
///
/// The server answers `{accepted: true}` for a request it took responsibility
/// for, which is deliberately **not** the same as "an email was delivered". An
/// address that is already verified is accepted and sends nothing, and a
/// suppressed address is accepted and then dropped by the delivery pipeline. No
/// surface built on this may claim a message was sent.
final class AccountVerificationResult {
  const AccountVerificationResult._();

  factory AccountVerificationResult.fromCallable(Object? value) {
    if (value is! Map || value.length != 1 || value['accepted'] != true) {
      throw const FormatException(
        'sendAccountVerification returned an invalid result.',
      );
    }
    return const AccountVerificationResult._();
  }
}

/// Guarded client boundary over `sendAccountVerification`.
final class AccountVerificationGateway {
  AccountVerificationGateway({
    required AccountVerificationIdentity identity,
    required SendAccountVerificationCallable callable,
    AccountVerificationRequestIdFactory? requestIdFactory,
  }) : _identity = identity,
       _callable = callable,
       _requestIdFactory = requestIdFactory ?? _secureVerificationRequestId;

  final AccountVerificationIdentity _identity;
  final SendAccountVerificationCallable _callable;
  final AccountVerificationRequestIdFactory _requestIdFactory;

  AccountVerificationIntent createIntent() {
    if (!_identity.canSendVerification) {
      throw StateError('This identity cannot request a verification email.');
    }
    final requestId = _requestIdFactory();
    if (!_requestIdPattern.hasMatch(requestId)) {
      throw StateError('The verification request ID generator is invalid.');
    }
    return AccountVerificationIntent._(
      uid: _identity.uid,
      requestId: requestId,
    );
  }

  Future<AccountVerificationResult> send(
    AccountVerificationIntent intent,
  ) async {
    if (!_identity.canSendVerification || intent.uid != _identity.uid) {
      throw StateError('The verification intent belongs elsewhere.');
    }
    final response = await _callable.call(<String, Object?>{
      'requestId': intent.requestId,
    });
    return AccountVerificationResult.fromCallable(response);
  }
}

/// Offers the one action that releases a stuck unverified identity.
///
/// Until the address is verified the identity cannot request a business or
/// accept an invitation, so without this panel there is no way forward at all.
/// Nothing here verifies anything itself: the server owns eligibility, the
/// recency rule, and delivery.
final class AccountVerificationPanel extends StatefulWidget {
  const AccountVerificationPanel({
    super.key,
    required this.identity,
    required this.callable,
    required this.onReload,
    this.deliveryStatusCallable,
    this.requestIdFactory,
    this.isCurrent,
  });

  final AccountVerificationIdentity identity;
  final SendAccountVerificationCallable callable;

  /// Reads whether the caller's own address can receive mail at all.
  ///
  /// Checked once an accepted request has been made, which is exactly when the
  /// user starts waiting for a message. Without it a user whose address is
  /// suppressed taps "send again" forever and is never told why nothing
  /// arrives. While it is absent the panel simply does not make the claim.
  final EmailDeliveryStatusCallable? deliveryStatusCallable;

  /// Re-reads the identity from the server so a completed verification is
  /// observed. See [AccountVerificationReload].
  final AccountVerificationReload onReload;

  final AccountVerificationRequestIdFactory? requestIdFactory;
  final AccountVerificationCurrentCheck? isCurrent;

  @override
  State<AccountVerificationPanel> createState() =>
      _AccountVerificationPanelState();
}

final class _AccountVerificationPanelState
    extends State<AccountVerificationPanel> {
  AccountVerificationIntent? _intent;
  bool _sending = false;
  bool _reloading = false;
  bool _accepted = false;
  EmailDeliveryStatus? _deliveryStatus;
  String? _safeError;

  @override
  void didUpdateWidget(covariant AccountVerificationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different identity must never inherit the previous one's idempotency
    // key, or its retry would address another user's delivery.
    if (oldWidget.identity.uid != widget.identity.uid) {
      setState(() {
        _intent = null;
        _sending = false;
        _reloading = false;
        _accepted = false;
        // Deliverability is a property of the previous identity's address, so
        // it must never be carried onto another one.
        _deliveryStatus = null;
        _safeError = null;
      });
    }
  }

  bool _isCurrent() => widget.isCurrent?.call() ?? true;

  /// Reuses the intent, so a retry after a failure sends the same request ID
  /// and the server answers the same delivery instead of queuing another.
  AccountVerificationIntent? _intentFor(AccountVerificationGateway gateway) {
    final existing = _intent;
    if (existing != null && existing.uid == widget.identity.uid) return existing;
    try {
      return _intent = gateway.createIntent();
    } catch (_) {
      return null;
    }
  }

  Future<void> _send() async {
    if (_sending || _reloading || !_isCurrent()) return;
    final gateway = AccountVerificationGateway(
      identity: widget.identity,
      callable: widget.callable,
      requestIdFactory: widget.requestIdFactory,
    );
    final intent = _intentFor(gateway);
    if (intent == null) {
      setState(() => _safeError = accountVerificationSafeError(StateError('')));
      return;
    }
    final sentUid = widget.identity.uid;
    setState(() {
      _sending = true;
      _safeError = null;
    });
    try {
      await gateway.send(intent);
    } catch (error) {
      if (!mounted || !_isStillCurrent(sentUid, intent)) return;
      setState(() {
        _sending = false;
        _safeError = accountVerificationSafeError(error);
      });
      return;
    }
    if (!mounted || !_isStillCurrent(sentUid, intent)) return;
    setState(() {
      _sending = false;
      _accepted = true;
    });
    await _readDeliveryStatus(sentUid, intent);
  }

  /// Asks whether this address can receive mail at all, once a request has been
  /// accepted.
  ///
  /// A failure here is deliberately silent. The action the user took succeeded,
  /// and this is a diagnostic about it; reporting a failed diagnostic as an
  /// error on a successful send would be misleading. An unrecognised answer is
  /// treated the same way - the parser refuses it, and the panel says nothing
  /// rather than claiming an address works.
  Future<void> _readDeliveryStatus(
    String sentUid,
    AccountVerificationIntent intent,
  ) async {
    final callable = widget.deliveryStatusCallable;
    if (callable == null) return;
    final EmailDeliveryStatus status;
    try {
      status = await EmailDeliveryStatusReader(callable: callable).read();
    } catch (_) {
      return;
    }
    if (!mounted || !_isStillCurrent(sentUid, intent)) return;
    setState(() => _deliveryStatus = status);
  }

  Future<void> _recheck() async {
    if (_sending || _reloading || !_isCurrent()) return;
    final checkedUid = widget.identity.uid;
    setState(() {
      _reloading = true;
      _safeError = null;
    });
    try {
      await widget.onReload();
    } catch (error) {
      if (!mounted || widget.identity.uid != checkedUid || !_isCurrent()) return;
      setState(() {
        _reloading = false;
        _safeError = accountVerificationSafeError(error);
      });
      return;
    }
    if (!mounted || widget.identity.uid != checkedUid || !_isCurrent()) return;
    setState(() => _reloading = false);
  }

  bool _isStillCurrent(String uid, AccountVerificationIntent intent) =>
      identical(_intent, intent) && widget.identity.uid == uid && _isCurrent();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final busy = _sending || _reloading;
    return Card(
      key: const ValueKey('account-verification'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Verify your email address',
              style: tokens.typography.titleMedium.copyWith(
                color: tokens.colors.text.primary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Until this address is verified you cannot request a business or '
              'accept an invitation.',
            ),
            // **Two of this card's three answers were told apart by hue
            // alone**, which §9 rules out and §2.1 calls the failure it was
            // written for: `colorScheme.primary` for the accepted one and
            // `colorScheme.error` for the undeliverable one, both as a colour
            // on a paragraph and neither carrying a container, a glyph or a
            // word. They are the same four outcomes `AppNotice` names.
            if (_accepted) ...[
              const SizedBox(height: 12),
              Callout(
                key: const ValueKey('account-verification-accepted'),
                // Deliberately not "we sent you an email". The server accepts
                // the request without telling the client whether anything was
                // delivered - an already-verified or suppressed address is
                // accepted and sends nothing - so claiming delivery here would
                // be asserting something this app cannot know.
                status: _requestAccepted.status,
                message: _requestAccepted.message,
              ),
            ],
            if (_deliveryStatus == EmailDeliveryStatus.unavailable) ...[
              const SizedBox(height: 12),
              Callout(
                key: const ValueKey('account-verification-undeliverable'),
                // The server gives one answer for four causes, so this names
                // none of them. Sending again cannot help, and saying so is the
                // whole point: otherwise the user retries indefinitely.
                status: _undeliverable.status,
                message: _undeliverable.message,
              ),
            ],
            if (_safeError != null) ...[
              const SizedBox(height: 12),
              Callout(
                key: const ValueKey('account-verification-error'),
                // A refusal, named as one rather than painted red: the write
                // was attempted and nothing changed. Before this the whole of
                // the status was the colour, which is the case §9 rules out.
                status: AppNotice.refused(_safeError!).status,
                message: _safeError!,
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                // `busy` covers both in-flight calls on this screen, so the
                // other one's spinner must not appear here: `loading` is this
                // button's own flag and `onPressed` carries the shared guard.
                AppButton(
                  key: const ValueKey('account-verification-send'),
                  label: _accepted ? 'Send again' : 'Send verification email',
                  icon: Icons.mark_email_read_outlined,
                  tier: AppButtonTier.primary,
                  loading: _sending,
                  onPressed: busy ? null : _send,
                ),
                AppButton(
                  key: const ValueKey('account-verification-recheck'),
                  label: 'I have verified',
                  icon: Icons.refresh,
                  loading: _reloading,
                  onPressed: busy ? null : _recheck,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Maps a failure to a message that discloses nothing about the address.
///
/// The server requires a sign-in within the last five minutes, so
/// `failed-precondition` is the expected answer for a session that has been
/// open a while. It is the one case worth naming precisely, because the user
/// can act on it.
String accountVerificationSafeError(Object error) {
  if (error is AccountVerificationCallableException) {
    return switch (error.code) {
      'failed-precondition' =>
        'For your security, sign out and sign in again, then request the '
            'email within five minutes.',
      'unauthenticated' => 'Sign in again to request a verification email.',
      'permission-denied' => 'This account is not active. Contact support.',
      'resource-exhausted' =>
        'Too many requests. Wait a few minutes and try again.',
      _ => 'The verification email could not be requested. Please try again.',
    };
  }
  return 'The verification email could not be requested. Please try again.';
}

String _secureVerificationRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'verify-${base64Url.encode(bytes).replaceAll('=', '')}';
}

/// The server's own `requestId` contract, proved before any call is made.
final _requestIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$');
