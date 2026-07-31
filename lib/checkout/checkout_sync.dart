import 'dart:async';
import 'dart:math';

import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import 'checkout_outbox.dart';
import 'checkout_sale.dart';
import 'checkout_submission.dart';

enum CheckoutSyncRunKind {
  completed,
  noSelectedSession,
  alreadyRunning,
  sessionChanged,
  offline,
  storageUnavailable,
}

final class CheckoutSyncRunResult {
  const CheckoutSyncRunResult(
    this.kind, {
    this.submitted = 0,
    this.ambiguous = 0,
    this.rejected = 0,
    this.malformed = 0,
    this.skipped = 0,
  });

  final CheckoutSyncRunKind kind;

  /// Commits acknowledged by the server and durably awaiting confirmation.
  final int submitted;

  /// Attempts whose outcome only a confirmation check can settle.
  final int ambiguous;

  /// Attempts the server refused; they stay submitting until lease expiry.
  final int rejected;

  /// Records whose frozen payload could not be trusted for a write.
  final int malformed;

  /// Records that were not due, not eligible, or owned by another worker.
  final int skipped;
}

typedef CheckoutSyncClock = DateTime Function();
typedef CheckoutSyncOnlineCheck = Future<bool> Function();

/// Submits due offline checkouts for the currently selected tenant session.
///
/// The worker acquires the durable outbox lease before the single
/// `batch.commit()` call, so two local workers cannot submit one checkout. A
/// committed batch moves the record to `awaiting_confirmation`; every other
/// outcome deliberately leaves it `submitting`, where only lease expiry plus a
/// server confirmation check may decide what happens next. The worker never
/// resubmits an expired lease and never invents a retry.
final class CheckoutSubmissionWorker {
  CheckoutSubmissionWorker({
    required TenantSessionController sessionController,
    required HiveCheckoutOutbox outbox,
    required CheckoutSubmissionGateway submissionGateway,
    required CheckoutSyncOnlineCheck isOnline,
    String? workerId,
    Duration leaseDuration = const Duration(minutes: 2),
    CheckoutSyncClock? clock,
  }) : _sessionController = sessionController,
       _outbox = outbox,
       _submissionGateway = submissionGateway,
       _isOnline = isOnline,
       _workerId = workerId ?? _generateWorkerId(),
       _leaseDuration = leaseDuration,
       _clock = clock ?? _utcNow {
    if (_workerId.isEmpty ||
        _workerId.contains(':') ||
        _workerId != _workerId.trim()) {
      throw ArgumentError.value(workerId, 'workerId');
    }
    if (leaseDuration <= Duration.zero ||
        leaseDuration > const Duration(hours: 1)) {
      throw ArgumentError.value(leaseDuration, 'leaseDuration');
    }
  }

  final TenantSessionController _sessionController;
  final HiveCheckoutOutbox _outbox;
  final CheckoutSubmissionGateway _submissionGateway;
  final CheckoutSyncOnlineCheck _isOnline;
  final String _workerId;
  final Duration _leaseDuration;
  final CheckoutSyncClock _clock;
  bool _running = false;
  bool _rerunRequested = false;

  bool get isRunning => _running;
  String get workerId => _workerId;

  Future<CheckoutSyncRunResult> submitDueCheckouts() async {
    if (_running) {
      _rerunRequested = true;
      return const CheckoutSyncRunResult(CheckoutSyncRunKind.alreadyRunning);
    }
    final captured = _sessionController.session;
    if (captured == null || !captured.canAccess()) {
      return const CheckoutSyncRunResult(CheckoutSyncRunKind.noSelectedSession);
    }

    _running = true;
    var submitted = 0;
    var ambiguous = 0;
    var rejected = 0;
    var malformed = 0;
    var skipped = 0;
    try {
      if (!await _online()) {
        return const CheckoutSyncRunResult(CheckoutSyncRunKind.offline);
      }
      if (!_owns(captured)) return _sessionChanged();

      List<CheckoutOutboxRecord> records;
      try {
        records = await _outbox.recordsForSession(
          uid: captured.uid,
          tenantId: captured.tenantId,
        );
      } catch (_) {
        return const CheckoutSyncRunResult(
          CheckoutSyncRunKind.storageUnavailable,
        );
      }

      for (final record in records) {
        if (!_owns(captured)) return _sessionChanged();
        if (record.state != CheckoutOutboxState.savedOffline) {
          skipped++;
          continue;
        }
        final retryAt = record.retryAt;
        if (retryAt != null && retryAt.isAfter(_clock().toUtc())) {
          skipped++;
          continue;
        }

        final CheckoutSaleSubmission submission;
        try {
          submission = CheckoutSalePayload.fromOutboxRecord(
            record,
            session: captured,
          ).toSubmission();
        } catch (_) {
          malformed++;
          continue;
        }

        try {
          await _outbox.beginSubmission(
            uid: record.uid,
            tenantId: record.tenantId,
            checkoutId: record.checkoutId,
            leaseOwner: _workerId,
            leaseDuration: _leaseDuration,
          );
        } on CheckoutOutboxException catch (error) {
          if (error.code == 'malformed_record') {
            return const CheckoutSyncRunResult(
              CheckoutSyncRunKind.storageUnavailable,
            );
          }
          skipped++;
          continue;
        } catch (_) {
          return const CheckoutSyncRunResult(
            CheckoutSyncRunKind.storageUnavailable,
          );
        }
        if (!_owns(captured)) return _sessionChanged();

        final result = await _submissionGateway.submit(submission);
        if (!_owns(captured)) return _sessionChanged();
        switch (result.kind) {
          case CheckoutSubmissionKind.committed:
            try {
              await _outbox.markAwaitingConfirmation(
                uid: record.uid,
                tenantId: record.tenantId,
                checkoutId: record.checkoutId,
                leaseOwner: _workerId,
              );
              submitted++;
            } on CheckoutOutboxException {
              ambiguous++;
            } catch (_) {
              return const CheckoutSyncRunResult(
                CheckoutSyncRunKind.storageUnavailable,
              );
            }
          case CheckoutSubmissionKind.rejected:
            rejected++;
          case CheckoutSubmissionKind.ambiguous:
            ambiguous++;
          case CheckoutSubmissionKind.unavailable:
            ambiguous++;
            skipped += _remainingDueCount(records, record);
            return CheckoutSyncRunResult(
              CheckoutSyncRunKind.completed,
              submitted: submitted,
              ambiguous: ambiguous,
              rejected: rejected,
              malformed: malformed,
              skipped: skipped,
            );
        }
      }

      if (!_owns(captured)) return _sessionChanged();
      return CheckoutSyncRunResult(
        CheckoutSyncRunKind.completed,
        submitted: submitted,
        ambiguous: ambiguous,
        rejected: rejected,
        malformed: malformed,
        skipped: skipped,
      );
    } finally {
      _running = false;
      if (_rerunRequested) {
        _rerunRequested = false;
        unawaited(Future<CheckoutSyncRunResult>.microtask(submitDueCheckouts));
      }
    }
  }

  int _remainingDueCount(
    List<CheckoutOutboxRecord> records,
    CheckoutOutboxRecord current,
  ) {
    final index = records.indexOf(current);
    return index < 0 ? 0 : records.length - index - 1;
  }

  Future<bool> _online() async {
    try {
      return await _isOnline();
    } catch (_) {
      return false;
    }
  }

  bool _owns(TenantSession captured) {
    final current = _sessionController.session;
    return current != null &&
        current.uid == captured.uid &&
        current.tenantId == captured.tenantId &&
        current.epoch == captured.epoch;
  }

  CheckoutSyncRunResult _sessionChanged() =>
      const CheckoutSyncRunResult(CheckoutSyncRunKind.sessionChanged);
}

String _generateWorkerId() {
  final random = Random.secure();
  final suffix = List<String>.generate(
    4,
    (_) => random.nextInt(0x10000).toRadixString(16).padLeft(4, '0'),
  ).join();
  return 'checkout-sync-$suffix';
}

DateTime _utcNow() => DateTime.now().toUtc();
