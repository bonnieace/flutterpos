import 'dart:async';

import 'package:flutter/material.dart';

import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import 'checkout_outbox.dart';

/// Read-only counts of locally retained checkout evidence for one session.
final class CheckoutEvidenceSummary {
  const CheckoutEvidenceSummary({
    this.savedOffline = 0,
    this.submitting = 0,
    this.awaitingConfirmation = 0,
    this.confirmed = 0,
    this.needsAttention = 0,
  });

  final int savedOffline;
  final int submitting;
  final int awaitingConfirmation;
  final int confirmed;
  final int needsAttention;

  int get total =>
      savedOffline +
      submitting +
      awaitingConfirmation +
      confirmed +
      needsAttention;

  /// Records that still block tenant switching.
  int get unsettled =>
      savedOffline + submitting + awaitingConfirmation + needsAttention;
}

/// The narrow read boundary used by the pending-checkout evidence panel.
abstract interface class CheckoutEvidenceSource {
  Future<CheckoutEvidenceSummary> summarize(TenantSession session);
}

/// Counts encrypted outbox records for the exact session UID and tenant.
final class CheckoutOutboxEvidenceSource implements CheckoutEvidenceSource {
  const CheckoutOutboxEvidenceSource(this._outbox);

  final HiveCheckoutOutbox _outbox;

  @override
  Future<CheckoutEvidenceSummary> summarize(TenantSession session) async {
    final records = await _outbox.recordsForSession(
      uid: session.uid,
      tenantId: session.tenantId,
    );
    var savedOffline = 0;
    var submitting = 0;
    var awaitingConfirmation = 0;
    var confirmed = 0;
    var needsAttention = 0;
    for (final record in records) {
      switch (record.state) {
        case CheckoutOutboxState.savedOffline:
          savedOffline++;
        case CheckoutOutboxState.submitting:
          submitting++;
        case CheckoutOutboxState.awaitingConfirmation:
          awaitingConfirmation++;
        case CheckoutOutboxState.confirmed:
          confirmed++;
        case CheckoutOutboxState.needsAttention:
          needsAttention++;
      }
    }
    return CheckoutEvidenceSummary(
      savedOffline: savedOffline,
      submitting: submitting,
      awaitingConfirmation: awaitingConfirmation,
      confirmed: confirmed,
      needsAttention: needsAttention,
    );
  }
}

/// Guarded, read-only outbox state counts for the safe landing route.
///
/// The panel deliberately exposes no submit, retry, edit, cancel, or delete
/// action; every transition stays owned by the recovery and submission workers.
///
/// [refreshSignals] is how it learns that those workers, or a sale saved at the
/// till, moved something. Without it the counts are read once when the session
/// opens and then never again, so a cashier who rang up two sales was still
/// told none was stored on this device until the app was restarted.
final class CheckoutPendingEvidencePanel extends StatefulWidget {
  const CheckoutPendingEvidencePanel({
    super.key,
    required this.source,
    this.refreshSignals,
  });

  final CheckoutEvidenceSource source;

  /// Fires when local checkout evidence may have changed.
  final Stream<Object?>? refreshSignals;

  @override
  State<CheckoutPendingEvidencePanel> createState() =>
      _CheckoutPendingEvidencePanelState();
}

final class _CheckoutPendingEvidencePanelState
    extends State<CheckoutPendingEvidencePanel> {
  StreamSubscription<Object?>? _subscription;
  int _generation = 0;
  int _loaderGeneration = -1;
  TenantGuardedLoader<CheckoutEvidenceSummary>? _load;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant CheckoutPendingEvidencePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.refreshSignals, widget.refreshSignals)) {
      _subscription?.cancel();
      _subscribe();
    }
    if (!identical(oldWidget.source, widget.source)) _generation++;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _subscribe() {
    _subscription = widget.refreshSignals?.listen(
      (_) {
        if (mounted) setState(() => _generation++);
      },
      onError: (Object _, StackTrace _) {},
    );
  }

  @override
  Widget build(BuildContext context) {
    // The guard restarts whenever its loader changes identity, which is how a
    // refresh is asked for - and why the loader is cached against the
    // generation rather than rebuilt every frame, since an unrelated rebuild
    // must not restart the read.
    if (_loaderGeneration != _generation || _load == null) {
      _loaderGeneration = _generation;
      _load = (session) => widget.source.summarize(session);
    }
    return TenantRouteGuard<CheckoutEvidenceSummary>(
      load: _load!,
      loading: const SizedBox.shrink(),
      denied: const SizedBox.shrink(),
      failure: (context, error) =>
          const Text('Local checkout evidence is unavailable.'),
      builder: (context, session, summary) => _EvidenceContents(summary),
    );
  }
}

final class _EvidenceContents extends StatelessWidget {
  const _EvidenceContents(this.summary);

  final CheckoutEvidenceSummary summary;

  @override
  Widget build(BuildContext context) {
    if (summary.total == 0) {
      return const Text(
        key: ValueKey('pending-checkout-evidence-empty'),
        'No checkouts are stored on this device.',
      );
    }
    return Column(
      key: const ValueKey('pending-checkout-evidence'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Checkouts stored on this device',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        Text('Saved offline: ${summary.savedOffline}'),
        Text('Submitting: ${summary.submitting}'),
        Text('Awaiting confirmation: ${summary.awaitingConfirmation}'),
        Text('Needs attention: ${summary.needsAttention}'),
        Text('Confirmed: ${summary.confirmed}'),
        const SizedBox(height: 6),
        const Text(
          'This panel is read-only. Submission and confirmation remain '
          'automatic; no checkout can be edited, retried, or deleted here.',
        ),
      ],
    );
  }
}
