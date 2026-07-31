import 'dart:async';

import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import 'checkout_confirmation.dart';
import 'checkout_outbox.dart';

enum CheckoutRecoveryRunKind {
  completed,
  noSelectedSession,
  alreadyRunning,
  sessionChanged,
  storageUnavailable,
}

final class CheckoutRecoveryRunResult {
  const CheckoutRecoveryRunResult(
    this.kind, {
    this.confirmed = 0,
    this.retryable = 0,
    this.needsAttention = 0,
    this.retained = 0,
  });

  final CheckoutRecoveryRunKind kind;
  final int confirmed;
  final int retryable;
  final int needsAttention;
  final int retained;
}

typedef CheckoutRecoveryClock = DateTime Function();

/// Confirmation-only restart recovery for the currently selected tenant.
///
/// This coordinator never submits a Firestore sale. It only classifies exact
/// server evidence and durably updates the encrypted outbox when the captured
/// UID, tenant, and session epoch still own the result.
final class CheckoutRecoveryCoordinator {
  CheckoutRecoveryCoordinator({
    required TenantSessionController sessionController,
    required HiveCheckoutOutbox outbox,
    required CheckoutConfirmationGateway confirmationGateway,
    Duration retryBackoff = const Duration(seconds: 30),
    CheckoutRecoveryClock? clock,
  }) : _sessionController = sessionController,
       _outbox = outbox,
       _confirmationGateway = confirmationGateway,
       _retryBackoff = retryBackoff,
       _clock = clock ?? _utcNow {
    if (retryBackoff <= Duration.zero ||
        retryBackoff > const Duration(hours: 24)) {
      throw ArgumentError.value(retryBackoff, 'retryBackoff');
    }
  }

  final TenantSessionController _sessionController;
  final HiveCheckoutOutbox _outbox;
  final CheckoutConfirmationGateway _confirmationGateway;
  final Duration _retryBackoff;
  final CheckoutRecoveryClock _clock;
  bool _running = false;
  bool _rerunRequested = false;

  bool get isRunning => _running;

  Future<CheckoutRecoveryRunResult> recoverSelectedSession() async {
    if (_running) {
      _rerunRequested = true;
      return const CheckoutRecoveryRunResult(
        CheckoutRecoveryRunKind.alreadyRunning,
      );
    }
    final captured = _sessionController.session;
    if (captured == null || !captured.canAccess()) {
      return const CheckoutRecoveryRunResult(
        CheckoutRecoveryRunKind.noSelectedSession,
      );
    }

    _running = true;
    var confirmed = 0;
    var retryable = 0;
    var needsAttention = 0;
    var retained = 0;
    try {
      List<CheckoutOutboxRecord> records;
      try {
        records = await _outbox.recordsForSession(
          uid: captured.uid,
          tenantId: captured.tenantId,
        );
      } catch (_) {
        return const CheckoutRecoveryRunResult(
          CheckoutRecoveryRunKind.storageUnavailable,
        );
      }
      if (!_owns(captured)) return _sessionChanged();

      for (var record in records) {
        if (!_owns(captured)) return _sessionChanged();
        if (record.state == CheckoutOutboxState.submitting) {
          final expiry = record.leaseExpiresAt!;
          if (expiry.isAfter(_clock().toUtc())) {
            retained++;
            continue;
          }
          try {
            record = await _outbox.recoverExpiredSubmission(
              uid: record.uid,
              tenantId: record.tenantId,
              checkoutId: record.checkoutId,
            );
          } catch (_) {
            return const CheckoutRecoveryRunResult(
              CheckoutRecoveryRunKind.storageUnavailable,
            );
          }
          if (!_owns(captured)) return _sessionChanged();
        }
        if (record.state != CheckoutOutboxState.awaitingConfirmation) {
          continue;
        }

        final result = await _confirmationGateway.check(record);
        if (!_owns(captured)) return _sessionChanged();
        try {
          switch (result.kind) {
            case CheckoutConfirmationKind.matching:
              await _outbox.recordConfirmation(
                uid: record.uid,
                tenantId: record.tenantId,
                checkoutId: record.checkoutId,
                observedPayloadHash: result.observedPayloadHash!,
              );
              confirmed++;
            case CheckoutConfirmationKind.mismatching:
              await _outbox.recordConfirmation(
                uid: record.uid,
                tenantId: record.tenantId,
                checkoutId: record.checkoutId,
                observedPayloadHash: result.observedPayloadHash!,
              );
              needsAttention++;
            case CheckoutConfirmationKind.missing:
              await _outbox.markRetryableAfterMissingSale(
                proof: result.missingSaleProof!,
                backoff: _retryBackoff,
              );
              retryable++;
            case CheckoutConfirmationKind.pendingWrites ||
                CheckoutConfirmationKind.unavailable ||
                CheckoutConfirmationKind.malformed:
              retained++;
          }
        } catch (_) {
          return const CheckoutRecoveryRunResult(
            CheckoutRecoveryRunKind.storageUnavailable,
          );
        }
      }
      if (!_owns(captured)) return _sessionChanged();
      return CheckoutRecoveryRunResult(
        CheckoutRecoveryRunKind.completed,
        confirmed: confirmed,
        retryable: retryable,
        needsAttention: needsAttention,
        retained: retained,
      );
    } finally {
      _running = false;
      if (_rerunRequested) {
        _rerunRequested = false;
        unawaited(
          Future<CheckoutRecoveryRunResult>.microtask(recoverSelectedSession),
        );
      }
    }
  }

  bool _owns(TenantSession captured) {
    final current = _sessionController.session;
    return current != null &&
        current.uid == captured.uid &&
        current.tenantId == captured.tenantId &&
        current.epoch == captured.epoch;
  }

  CheckoutRecoveryRunResult _sessionChanged() =>
      const CheckoutRecoveryRunResult(CheckoutRecoveryRunKind.sessionChanged);
}

DateTime _utcNow() => DateTime.now().toUtc();
