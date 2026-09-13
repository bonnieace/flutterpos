import 'dart:async';

import 'package:flutter/material.dart';

import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_pending_mutation.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../ui/buttons.dart';
import '../ui/routes.dart';
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
/// Draws one read of the local work counts.
typedef CheckoutEvidenceBuilder =
    Widget Function(
      BuildContext context,
      CheckoutEvidenceSummary summary, {
      required bool rereading,
      Future<void> Function(String operationId)? onAcknowledge,
    });

/// The guarded read, without an opinion about how the counts are drawn.
///
/// **Split out on 2026-09-03**, when the counts got a second home. They are
/// the badge on the top bar's glyph *and* the readout on the notifications
/// route it opens; both want the same session guard, the same refresh
/// subscription and the same "keep the last answer while re-reading" rule, and
/// two copies of that machinery is how the two come to disagree about what a
/// device is holding.
final class CheckoutEvidenceScope extends StatefulWidget {
  const CheckoutEvidenceScope({
    super.key,
    required this.source,
    required this.builder,
    this.refreshSignals,
  });

  final CheckoutEvidenceSource source;

  /// Fires when local checkout evidence may have changed.
  final Stream<Object?>? refreshSignals;

  final CheckoutEvidenceBuilder builder;

  @override
  State<CheckoutEvidenceScope> createState() => _CheckoutEvidenceScopeState();
}

final class _CheckoutEvidenceScopeState extends State<CheckoutEvidenceScope> {
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
  void didUpdateWidget(covariant CheckoutEvidenceScope oldWidget) {
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
      // **Only a first entry reaches this now.** Until 2026-09-04 the guard
      // blanked its value whenever the loader changed, so this panel kept its
      // own copy of the last summary and re-drew it from the loading slot to
      // stop a refresh emptying the list. The guard retains the value itself
      // since then and stays in `ready`, so the retained counts come through
      // `builder` below and this slot is left for the case it was always for:
      // a panel that has never read anything yet.
      loading: previous == null
          ? const SizedBox.shrink()
          : widget.builder(context, previous, rereading: true),
      denied: const SizedBox.shrink(),
      failure: (context, error) =>
          const Text('Local work evidence is unavailable.'),
      builder: (context, session, summary) {
        // Caching the answer for a first frame after a session change, which is
        // the one case the guard cannot retain across. This assigns a field
        // rather than calling `setState`, so it adds no build cycle.
        _last = summary;
        final source = widget.source;
        final mutationController = source is TenantMutationEvidenceController
            ? source as TenantMutationEvidenceController
            : null;
        return widget.builder(
          context,
          summary,
          // The guard's own flag, rather than this panel's guess at it. It is
          // true exactly while these counts are the previous read's and the
          // next one is in flight.
          rereading: TenantReadFreshness.maybeOf(context)?.rereading ?? false,
          onAcknowledge: mutationController == null
              ? null
              : (operationId) =>
                    mutationController.acknowledge(session, operationId),
        );
      },
    );
  }
}

/// What is still waiting, which is what the badge counts.
///
/// **Confirmed checkouts are deliberately not in it.** Eleven sales that
/// reached the server are not news; two that have not are. A badge counting
/// everything would read "13" on a device with nothing wrong with it.
///
/// **A refused change is in it, since 2026-09-05.** It was not, and that was a
/// defect the moment the catalog started writing through this queue: a product
/// the server rejected left `rejected` at one and every other count at zero, so
/// the notifications page computed *clear* and drew "Everything has gone
/// through" directly above a row reading *Changes the server refused*. The two
/// sentences cannot both be true. A refusal is the loudest thing this device
/// can be carrying - it is the reversal a person watched happen on their
/// screen - and it stays counted until they acknowledge it.
int checkoutWaitingCount(CheckoutEvidenceSummary summary) =>
    summary.savedOffline +
    summary.submitting +
    summary.awaitingConfirmation +
    summary.needsAttention +
    summary.mutations.queued +
    summary.mutations.submitting +
    summary.mutations.awaitingConfirmation +
    summary.mutations.needsAttention +
    summary.mutations.rejected;

/// The top bar's glyph: how much this device is still carrying, and the way in
/// to the page that says what it is.
///
/// **It opens a route rather than a panel hanging under itself.** Until
/// 2026-09-03 it dropped a 320-wide readout below the bar; the same page now
/// also has to carry the unprinted receipts, which came off the home's grid,
/// and a list of receipts with a *Send again* on each is not something to hang
/// off a top-bar button.
final class CheckoutPendingEvidencePanel extends StatelessWidget {
  const CheckoutPendingEvidencePanel({
    super.key,
    required this.source,
    this.refreshSignals,
    this.notificationsRoute,
    this.alsoWaiting,
  });

  final CheckoutEvidenceSource source;

  /// Fires when local checkout evidence may have changed.
  final Stream<Object?>? refreshSignals;

  /// The page this glyph opens. While absent the glyph is a readout and
  /// nothing else, which is what every test that does not compose a route
  /// gets.
  final WidgetBuilder? notificationsRoute;

  /// Waiting work this panel does not read for itself.
  ///
  /// **Unprinted receipts, supplied by the composition root.** They are a
  /// durable box on this device rather than checkout evidence, and they left
  /// the home's grid on 2026-09-03 - so the badge that carries everything else
  /// this device still owes carries them too, or nothing does.
  final int Function()? alsoWaiting;

  @override
  Widget build(BuildContext context) => CheckoutEvidenceScope(
    source: source,
    refreshSignals: refreshSignals,
    builder: (context, summary, {required rereading, onAcknowledge}) {
      final sessions = TenantSessionScope.of(context);
      final route = notificationsRoute;
      return SyncIndicator(
        key: const ValueKey('pending-checkout-evidence'),
        waiting: checkoutWaitingCount(summary) + (alsoWaiting?.call() ?? 0),
        needsAttention:
            summary.needsAttention > 0 || summary.mutations.failures > 0,
        // A reload line, at the product owner's direction on 2026-09-03. The
        // upload arrow said "sending"; what this button is actually about is
        // everything on this device that has not settled yet.
        icon: Icons.notifications_outlined,
        subject: 'Notifications',
        onOpen: route == null
            ? () {}
            : () => Navigator.of(context).push(
                AppPageRoute<void>(
                  builder: (_) => TenantSessionScope(
                    controller: sessions,
                    child: Builder(builder: route),
                  ),
                ),
              ),
      );
    },
  );
}

/// The counts themselves, drawn from a summary somebody else already read.
///
/// **It takes the summary rather than the source**, because the page it sits on
/// needs the same figures for its own headline and a second `CheckoutEvidenceScope`
/// would be a second read of one device's boxes per frame. The page opens the
/// scope; this draws the part of it that is a breakdown.
final class CheckoutLocalWorkPanel extends StatelessWidget {
  const CheckoutLocalWorkPanel({
    super.key,
    required this.summary,
    this.rereading = false,
    this.onAcknowledge,
  });

  final CheckoutEvidenceSummary summary;

  /// Whether these counts are the previous read, shown while a fresh one is in
  /// flight.
  final bool rereading;

  final Future<void> Function(String operationId)? onAcknowledge;

  @override
  Widget build(BuildContext context) => _EvidenceContents(
    summary,
    rereading: rereading,
    onAcknowledge: onAcknowledge,
  );
}

/// What this device is still carrying, said in the shopkeeper's words.
///
/// **Only what is outstanding, and only when there is some, 2026-09-04.** This
/// drew twelve cells - *Saved offline*, *Submitting*, *Awaiting confirmation*,
/// *Confirmed*, *Queued changes*, *Submitting changes* and so on - almost all
/// of them reading zero, in the vocabulary of the queue rather than of the
/// shop. On a notifications page that is a grid of noughts standing where the
/// news should be.
///
/// Two rules now. **A state with nothing in it is not drawn**: this page
/// exists to answer *what has not gone through*, and a zero is not an answer
/// to it. **A state that has gone through is not drawn either** - *Confirmed*
/// is the absence of news, and it was taking a cell beside the states that are
/// news.
///
/// The earlier reasoning for naming every bucket was that a cashier asking
/// "where did my sale go" could not otherwise tell an absent line from a zero.
/// That holds for a debugging readout and not for this: the page is reached
/// from a badge that only appears when something is waiting, so the question
/// it answers is *what*, and every line it draws is part of the answer.
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
  bool _reviewing = false;

  @override
  Widget build(BuildContext context) => _panel(widget.summary);

  Widget _panel(CheckoutEvidenceSummary summary) {
    // `State.context`, because this helper takes no `BuildContext` of its
    // own and does not need one: it is only ever called from `build`.
    final tokens = AppTokens.componentOf(context);
    final lines = <_WorkLine>[
      _WorkLine(
        'Saved here, waiting to send',
        summary.savedOffline,
        AppStatus.attention,
      ),
      _WorkLine('Sending now', summary.submitting, AppStatus.attention),
      _WorkLine(
        'Sent, waiting for the server',
        summary.awaitingConfirmation,
        AppStatus.attention,
      ),
      _WorkLine(
        'Sales that need you',
        summary.needsAttention,
        AppStatus.problem,
      ),
      _WorkLine(
        'Changes waiting to send',
        summary.mutations.queued,
        AppStatus.attention,
      ),
      _WorkLine(
        'Changes sending now',
        summary.mutations.submitting,
        AppStatus.attention,
      ),
      _WorkLine(
        'Changes waiting for the server',
        summary.mutations.awaitingConfirmation,
        AppStatus.attention,
      ),
      _WorkLine(
        'Changes that need you',
        summary.mutations.needsAttention,
        AppStatus.problem,
      ),
      _WorkLine(
        'Changes the server refused',
        summary.mutations.rejected,
        AppStatus.problem,
      ),
    ].where((line) => line.count > 0).toList();

    return Column(
      key: const ValueKey('pending-checkout-evidence-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (lines.isEmpty)
          Text(
            'Nothing on this device is waiting to be sent.',
            key: const ValueKey('pending-checkout-evidence-empty'),
            style: tokens.typography.caption.copyWith(
              color: tokens.colors.text.tertiary,
            ),
          )
        else
          for (final line in lines) _WorkRow(line: line),
        if (widget.rereading) ...<Widget>[
          SizedBox(height: tokens.spacing.s12),
          Text(
            key: const ValueKey('pending-checkout-evidence-rereading'),
            'Re-reading the records on this device; these counts may be a '
            'moment old.',
            style: tokens.typography.caption.copyWith(
              color: tokens.colors.text.tertiary,
            ),
          ),
        ],
        if (summary.mutations.reviewItems.isNotEmpty) ...<Widget>[
          SizedBox(height: tokens.spacing.s8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: const ValueKey('local-work-review-link'),
              onPressed: () => setState(() => _reviewing = !_reviewing),
              child: Text(_reviewing ? 'Hide review items' : 'Review failures'),
            ),
          ),
          if (_reviewing)
            for (final record in summary.mutations.reviewItems)
              _MutationReviewRow(
                record: record,
                onAcknowledge: widget.onAcknowledge,
              ),
        ],
      ],
    );
  }
}

/// One outstanding state: how many, and what it means.
final class _WorkLine {
  const _WorkLine(this.label, this.count, this.status);

  final String label;
  final int count;
  final AppStatus status;
}

/// A count, a word, and a glyph carrying the standing.
///
/// The figure leads because it is what is being read; §9's no-colour-alone
/// rule is answered by the glyph beside it and by the sentence itself, not by
/// the tint.
final class _WorkRow extends StatelessWidget {
  const _WorkRow({required this.line});

  final _WorkLine line;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final role = line.status.role(tokens);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: tokens.spacing.s8),
      child: Row(
        children: <Widget>[
          Icon(
            line.status.defaultIcon,
            size: AppButton.iconSize,
            color: role.fg,
          ),
          SizedBox(width: tokens.spacing.s12),
          Text(
            '${line.count}',
            style: tokens.typography.numericBody.copyWith(
              color: tokens.colors.text.primary,
            ),
          ),
          SizedBox(width: tokens.spacing.s8),
          Expanded(
            child: Text(
              line.label,
              style: tokens.density
                  .body(tokens.typography)
                  .copyWith(color: tokens.colors.text.secondary),
            ),
          ),
        ],
      ),
    );
  }
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
  TenantPendingMutationKind.productCreate => 'New product',
  TenantPendingMutationKind.productRetire => 'Retired product',
  TenantPendingMutationKind.categoryCreate => 'New category',
  TenantPendingMutationKind.categoryRename => 'Renamed category',
  TenantPendingMutationKind.productCorrect => 'Product correction',
  TenantPendingMutationKind.stockAdjust => 'Stock adjustment',
};
