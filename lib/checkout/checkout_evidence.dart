import 'dart:async';

import 'package:flutter/material.dart';

import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_pending_mutation.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../ui/status.dart';
import '../ui/sync_indicator.dart';
import '../ui/tokens.dart';
import 'checkout_outbox.dart';

/// Read-only counts of locally retained checkout evidence for one session.
final class CheckoutEvidenceSummary {
  const CheckoutEvidenceSummary({
    this.savedOffline = 0,
    this.submitting = 0,
    this.awaitingConfirmation = 0,
    this.confirmed = 0,
    this.needsAttention = 0,
    this.mutations = const TenantMutationEvidenceSummary(),
  });

  final int savedOffline;
  final int submitting;
  final int awaitingConfirmation;
  final int confirmed;
  final int needsAttention;
  final TenantMutationEvidenceSummary mutations;

  int get total =>
      savedOffline +
      submitting +
      awaitingConfirmation +
      confirmed +
      needsAttention +
      mutations.total;

  /// Records that still block tenant switching.
  int get unsettled =>
      savedOffline +
      submitting +
      awaitingConfirmation +
      needsAttention +
      mutations.unsettled;

  CheckoutEvidenceSummary withMutations(TenantMutationEvidenceSummary value) =>
      CheckoutEvidenceSummary(
        savedOffline: savedOffline,
        submitting: submitting,
        awaitingConfirmation: awaitingConfirmation,
        confirmed: confirmed,
        needsAttention: needsAttention,
        mutations: value,
      );
}

/// Counts and retained review evidence for safe non-checkout mutations.
final class TenantMutationEvidenceSummary {
  const TenantMutationEvidenceSummary({
    this.queued = 0,
    this.submitting = 0,
    this.awaitingConfirmation = 0,
    this.confirmed = 0,
    this.rejected = 0,
    this.needsAttention = 0,
    this.reviewItems = const <TenantPendingMutationRecord>[],
  });

  final int queued;
  final int submitting;
  final int awaitingConfirmation;
  final int confirmed;
  final int rejected;
  final int needsAttention;
  final List<TenantPendingMutationRecord> reviewItems;

  int get total =>
      queued +
      submitting +
      awaitingConfirmation +
      confirmed +
      rejected +
      needsAttention;

  int get unsettled =>
      queued + submitting + awaitingConfirmation + needsAttention;

  int get failures => rejected + needsAttention;
}

/// The narrow read boundary used by the pending-checkout evidence panel.
abstract interface class CheckoutEvidenceSource {
  Future<CheckoutEvidenceSummary> summarize(TenantSession session);
}

abstract interface class TenantMutationEvidenceController {
  Future<void> acknowledge(TenantSession session, String operationId);
}

/// Joins the checkout outbox and mutation outbox into one session-scoped read.
final class CombinedLocalWorkEvidenceSource
    implements CheckoutEvidenceSource, TenantMutationEvidenceController {
  const CombinedLocalWorkEvidenceSource({
    required CheckoutEvidenceSource checkouts,
    required TenantPendingMutationStore mutations,
  }) : _checkouts = checkouts,
       _mutations = mutations;

  final CheckoutEvidenceSource _checkouts;
  final TenantPendingMutationStore _mutations;

  @override
  Future<CheckoutEvidenceSummary> summarize(TenantSession session) async {
    final checkoutFuture = _checkouts.summarize(session);
    final mutationFuture = _summarizeMutations(session);
    final checkouts = await checkoutFuture;
    return checkouts.withMutations(await mutationFuture);
  }

  Future<TenantMutationEvidenceSummary> _summarizeMutations(
    TenantSession session,
  ) async {
    final records = await _mutations.recordsForSession(
      uid: session.uid,
      tenantId: session.tenantId,
    );
    var queued = 0;
    var submitting = 0;
    var awaitingConfirmation = 0;
    var confirmed = 0;
    var rejected = 0;
    var needsAttention = 0;
    final review = <TenantPendingMutationRecord>[];
    for (final record in records) {
      switch (record.state) {
        case TenantPendingMutationState.queued:
          queued++;
        case TenantPendingMutationState.submitting:
          submitting++;
        case TenantPendingMutationState.awaitingConfirmation:
          awaitingConfirmation++;
        case TenantPendingMutationState.confirmed:
          confirmed++;
        case TenantPendingMutationState.rejected:
          rejected++;
          review.add(record);
        case TenantPendingMutationState.needsAttention:
          needsAttention++;
          review.add(record);
      }
    }
    return TenantMutationEvidenceSummary(
      queued: queued,
      submitting: submitting,
      awaitingConfirmation: awaitingConfirmation,
      confirmed: confirmed,
      rejected: rejected,
      needsAttention: needsAttention,
      reviewItems: List<TenantPendingMutationRecord>.unmodifiable(review),
    );
  }

  @override
  Future<void> acknowledge(TenantSession session, String operationId) =>
      _mutations.acknowledge(
        uid: session.uid,
        tenantId: session.tenantId,
        operationId: operationId,
      );
}

/// Combines local-evidence streams without adding a polling timer.
Stream<Object?> mergeLocalWorkEvidenceSignals(
  Stream<Object?> checkouts,
  Stream<Object?> mutations,
) => Stream<Object?>.multi((controller) {
  final subscriptions = <StreamSubscription<Object?>>[
    checkouts.listen(controller.add, onError: controller.addError),
    mutations.listen(controller.add, onError: controller.addError),
  ];
  controller.onCancel = () async {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  };
});

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

  /// The last counts read for [_lastSessionKey], kept so a refresh does not
  /// blank the panel.
  ///
  /// Every refresh signal changes the loader's identity, which restarts the
  /// guard and puts it back into its loading state - so without this the whole
  /// panel vanishes and reappears on each signal. `CheckoutSyncPass` reports a
  /// change more than once per sale, so a cashier watching the counts after a
  /// sale sees them come and go rather than settle. Slightly stale counts, said
  /// to be stale, are better than counts that disappear.
  CheckoutEvidenceSummary? _last;
  String? _lastSessionKey;

  static String _sessionKey(TenantSession session) =>
      '${session.uid}:${session.tenantId}:${session.epoch}';

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
    _subscription = widget.refreshSignals?.listen((_) {
      if (mounted) setState(() => _generation++);
    }, onError: (Object _, StackTrace _) {});
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
    // A refresh re-reads the same session's counts, so the previous ones are
    // still the best thing to show while it is in flight. A session change is
    // not a refresh: one business's counts must never appear under another
    // business's name, so they are dropped the moment the session key moves.
    final session = TenantSessionScope.of(context).session;
    final sessionKey = session == null ? null : _sessionKey(session);
    if (sessionKey != _lastSessionKey) {
      _lastSessionKey = sessionKey;
      _last = null;
    }
    final previous = _last;
    return TenantRouteGuard<CheckoutEvidenceSummary>(
      load: _load!,
      loading: previous == null
          ? const SizedBox.shrink()
          : _EvidenceContents(previous, rereading: true),
      denied: const SizedBox.shrink(),
      failure: (context, error) =>
          const Text('Local work evidence is unavailable.'),
      builder: (context, session, summary) {
        // Caching the answer for the next refresh's loading frame. This assigns
        // a field rather than calling `setState`, so it adds no build cycle.
        _last = summary;
        final source = widget.source;
        final mutationController = source is TenantMutationEvidenceController
            ? source as TenantMutationEvidenceController
            : null;
        return _EvidenceContents(
          summary,
          onAcknowledge: mutationController == null
              ? null
              : (operationId) =>
                    mutationController.acknowledge(session, operationId),
        );
      },
    );
  }
}

/// The five counts, as §5.1's `SyncIndicator` rather than as five lines.
///
/// **§5.1 names this widget's old rendering in its "Replaces" column** — "five-line
/// offline queue list" — and §7 says where the counts go: *"the checkout queue
/// counts belong in a `StatRow`, not a five-line list."* They are a badged button
/// now, and the five counts live in the panel it opens.
///
/// **Nothing about what is read changed.** This widget already held the summary;
/// it draws it differently. The button can therefore sit in the home's top bar
/// without the count being hoisted anywhere, which is what makes §4.4's bar a
/// restyle rather than a rewiring.
///
/// Every state is still named even when its count is zero. A cashier reading this
/// is answering "where did my sale go", and a list that omitted the empty buckets
/// would make an absent line and a zero indistinguishable.
final class _EvidenceContents extends StatefulWidget {
  const _EvidenceContents(
    this.summary, {
    this.rereading = false,
    this.onAcknowledge,
  });

  final CheckoutEvidenceSummary summary;

  /// Whether these counts are the previous read, shown while a fresh one is in
  /// flight. Said out loud rather than left to be inferred, because the figures
  /// are about work the device may be in the middle of moving.
  final bool rereading;
  final Future<void> Function(String operationId)? onAcknowledge;

  @override
  State<_EvidenceContents> createState() => _EvidenceContentsState();
}

final class _EvidenceContentsState extends State<_EvidenceContents> {
  bool _open = false;
  bool _reviewing = false;

  /// What is still waiting, which is what the badge counts.
  ///
  /// **Confirmed checkouts are deliberately not in it.** Eleven sales that
  /// reached the server are not news; two that have not are. A badge counting
  /// everything would read "13" on a device with nothing wrong with it.
  int get _waiting =>
      widget.summary.savedOffline +
      widget.summary.submitting +
      widget.summary.awaitingConfirmation +
      widget.summary.needsAttention +
      widget.summary.mutations.queued +
      widget.summary.mutations.submitting +
      widget.summary.mutations.awaitingConfirmation +
      widget.summary.mutations.needsAttention;

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final indicator = SyncIndicator(
      key: const ValueKey('pending-checkout-evidence'),
      waiting: _waiting,
      needsAttention:
          summary.needsAttention > 0 || summary.mutations.failures > 0,
      subject: 'Local work on this device',
      onOpen: () => setState(() => _open = true),
    );
    if (!_open) return indicator;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topRight,
      children: <Widget>[
        indicator,
        // The panel hangs under the button that opened it rather than being a
        // route: §7's offline pattern is a readout, and pushing a route for a
        // list of five numbers would put a back arrow in front of them.
        Positioned(
          top: SyncIndicator.size + 8,
          right: 0,
          width: _panelWidth,
          child: _panel(summary),
        ),
      ],
    );
  }

  Widget _panel(CheckoutEvidenceSummary summary) {
    // `State.context`, because this helper takes no `BuildContext` of its
    // own and does not need one: it is only ever called from `build`.
    final tokens = AppTokens.componentOf(context);
    return SyncQueuePanel(
      key: const ValueKey('pending-checkout-evidence-panel'),
      title: 'Local work on this device',
      onClose: () => setState(() => _open = false),
      // **The empty sentence survives, inside the panel.** A device holding
      // nothing draws no badge at all - §5.1's rule, and the reason the button is
      // quiet when there is no news - so the one place left to say it is the
      // readout somebody opened to ask.
      emptyMessage: summary.total == 0
          ? 'No local work is stored on this device.'
          : null,
      entries: <SyncQueueEntry>[
        SyncQueueEntry(
          label: 'Saved offline',
          count: summary.savedOffline,
          status: summary.savedOffline > 0 ? AppStatus.attention : null,
        ),
        SyncQueueEntry(label: 'Submitting', count: summary.submitting),
        SyncQueueEntry(
          label: 'Awaiting confirmation',
          count: summary.awaitingConfirmation,
        ),
        SyncQueueEntry(
          label: 'Needs attention',
          count: summary.needsAttention,
          status: summary.needsAttention > 0 ? AppStatus.problem : null,
        ),
        SyncQueueEntry(label: 'Confirmed', count: summary.confirmed),
        SyncQueueEntry(
          label: 'Queued changes',
          count: summary.mutations.queued,
          status: summary.mutations.queued > 0 ? AppStatus.attention : null,
        ),
        SyncQueueEntry(
          label: 'Submitting changes',
          count: summary.mutations.submitting,
        ),
        SyncQueueEntry(
          label: 'Awaiting change confirmation',
          count: summary.mutations.awaitingConfirmation,
        ),
        SyncQueueEntry(
          label: 'Changes needing review',
          count: summary.mutations.needsAttention,
          status: summary.mutations.needsAttention > 0
              ? AppStatus.problem
              : null,
        ),
        SyncQueueEntry(
          label: 'Rejected changes',
          count: summary.mutations.rejected,
          status: summary.mutations.rejected > 0 ? AppStatus.problem : null,
        ),
        SyncQueueEntry(
          label: 'Confirmed changes',
          count: summary.mutations.confirmed,
        ),
      ],
      explanation: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (widget.rereading)
            Padding(
              padding: EdgeInsets.only(bottom: tokens.spacing.s8),
              child: Text(
                key: const ValueKey('pending-checkout-evidence-rereading'),
                'Re-reading the records on this device; these counts may be a '
                'moment old.',
                style: AppTokens.componentOf(context).typography.caption
                    .copyWith(
                      color: AppTokens.componentOf(
                        context,
                      ).colors.text.tertiary,
                    ),
              ),
            ),
          if (summary.mutations.reviewItems.isNotEmpty) ...<Widget>[
            TextButton(
              key: const ValueKey('local-work-review-link'),
              onPressed: () => setState(() => _reviewing = !_reviewing),
              child: Text(_reviewing ? 'Hide review items' : 'Review failures'),
            ),
            if (_reviewing)
              for (final record in summary.mutations.reviewItems)
                _MutationReviewRow(
                  record: record,
                  onAcknowledge: widget.onAcknowledge,
                ),
          ],
          // §7's *Long copy*: this explains policy rather than the current
          // state, so it folds. It was a permanent three-line paragraph.
          const Disclosure(
            key: ValueKey('pending-checkout-evidence-policy'),
            summary: 'Why can I not send these?',
            child: Text(
              'Submission and confirmation remain automatic. Checkouts cannot '
              'be edited or deleted here. Failed safe changes remain as '
              'evidence until they are reviewed and acknowledged.',
            ),
          ),
        ],
      ),
    );
  }

  /// How wide the panel hangs. Named for the reason `EmptyState.markSize` is:
  /// `design.md` states no panel width, and a readout of five counts wants
  /// enough room for its longest label and no more.
  static const double _panelWidth = 320;
}

final class _MutationReviewRow extends StatefulWidget {
  const _MutationReviewRow({required this.record, this.onAcknowledge});

  final TenantPendingMutationRecord record;
  final Future<void> Function(String operationId)? onAcknowledge;

  @override
  State<_MutationReviewRow> createState() => _MutationReviewRowState();
}

final class _MutationReviewRowState extends State<_MutationReviewRow> {
  bool _working = false;

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final reason = record.reasonCode?.replaceAll('_', ' ') ?? 'not accepted';
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(_mutationKindLabel(record.kind)),
      subtitle: Text(reason),
      trailing: widget.onAcknowledge == null
          ? null
          : TextButton(
              onPressed: _working
                  ? null
                  : () async {
                      setState(() => _working = true);
                      try {
                        await widget.onAcknowledge!(record.operationId);
                      } finally {
                        if (mounted) setState(() => _working = false);
                      }
                    },
              child: const Text('Acknowledge'),
            ),
    );
  }
}

String _mutationKindLabel(TenantPendingMutationKind kind) => switch (kind) {
  TenantPendingMutationKind.expenseCreate => 'Expense creation',
  TenantPendingMutationKind.expenseVoid => 'Expense void',
  TenantPendingMutationKind.pendingReturnCreate => 'Pending return',
  TenantPendingMutationKind.brandingMerge => 'Branding change',
  TenantPendingMutationKind.printerConfigurationMerge => 'Printer change',
};
