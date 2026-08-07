import 'dart:async';

import 'checkout_draft.dart';

/// Marks a sync run that was asked for because a sale just became durable.
///
/// The composition root decides what each reason justifies. A sale needs
/// submitting; it does not need the whole product catalog re-read from
/// Firestore, which is what a till would pay for on every single customer.
final class CheckoutSaveSyncRequest {
  const CheckoutSaveSyncRequest();
}

/// The one seam between a saved sale and the workers that carry it to the
/// server.
///
/// Before this existed the submission worker ran only when a tenant session
/// opened and when connectivity was restored. Neither happens while a cashier
/// stands at a till, so a sale rang up on an open till stayed `saved_offline`
/// until the app was next restarted - and the shift could not be closed,
/// because closing refuses while any sale is unsettled.
///
/// Two streams, because they answer two different questions:
///
/// * [syncRequests] asks the workers to run. The routing shell consumes it.
/// * [evidenceChanges] says local checkout state may have moved, so a
///   read-only surface should re-read. A durable save fires both; the end of a
///   sync run fires only the second, since a run must not ask for another run.
final class CheckoutSyncSignals {
  CheckoutSyncSignals();

  final StreamController<Object?> _syncRequests =
      StreamController<Object?>.broadcast();
  final StreamController<Object?> _evidenceChanges =
      StreamController<Object?>.broadcast();

  /// Cached deliberately: the routing shell compares this stream by identity to
  /// decide whether to resubscribe, and a broadcast controller hands out a new
  /// stream object on every `.stream` read.
  late final Stream<Object?> syncRequests = _syncRequests.stream;
  late final Stream<Object?> evidenceChanges = _evidenceChanges.stream;

  /// A sale is durable on this device. Submit it now, and re-read the evidence.
  void requestSyncAfterSave() {
    _add(_syncRequests, const CheckoutSaveSyncRequest());
    _add(_evidenceChanges, null);
  }

  /// Connectivity returned. Everything the composition root runs is justified,
  /// including refreshing derived data that could not be read while offline.
  void requestSyncAfterReconnect() => _add(_syncRequests, null);

  /// The business published different checkout settings, so what this device
  /// caches is stale.
  ///
  /// This asks for the same full pass a reconnect does rather than a save-shaped
  /// one, because the catalog refresh is the only thing that re-reads
  /// `configuration/checkout` - and until it runs the till keeps pricing new
  /// sales with the currency it was published to replace.
  void requestSyncAfterConfigurationChange() => _add(_syncRequests, null);

  /// A sync run finished, so what it settled is now worth re-reading.
  void reportEvidenceChanged() => _add(_evidenceChanges, null);

  Future<void> dispose() async {
    await _syncRequests.close();
    await _evidenceChanges.close();
  }

  void _add(StreamController<Object?> controller, Object? event) {
    if (controller.isClosed) return;
    controller.add(event);
  }
}

/// Asks for a sync run as soon as a draft becomes durable.
///
/// This decorates the sink rather than living in the checkout screen, so no
/// surface gains the ability to submit, retry, or otherwise move a checkout
/// through a state the sync and recovery workers own. The screen still only
/// saves; the composition root still owns what a save sets off.
final class CheckoutSyncOnSaveDraftSink implements CheckoutDraftSink {
  const CheckoutSyncOnSaveDraftSink({
    required CheckoutDraftSink delegate,
    required CheckoutSyncSignals signals,
  }) : _delegate = delegate,
       _signals = signals;

  final CheckoutDraftSink _delegate;
  final CheckoutSyncSignals _signals;

  @override
  Future<CheckoutSavedDraft> saveDraft(CheckoutDraftRequest request) async {
    // A refusal propagates from here untouched, so nothing is ever asked for on
    // behalf of a sale that was not recorded.
    final saved = await _delegate.saveDraft(request);
    try {
      _signals.requestSyncAfterSave();
    } catch (_) {
      // The sale is already durable. Reporting a failed signal as a failed save
      // would send a cashier to ring the same sale up twice, and the sale is
      // still picked up on the next reconnect or session open.
    }
    return saved;
  }
}
