import 'package:flutter/material.dart';

import '../ui/routes.dart';
import '../ui/scaffold.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session_controller.dart';
import '../tenancy/tenant_staff_names.dart';
import 'reconciliation_labels.dart';
import 'reconciliation_status.dart';

/// Opens one run under the caller's own session scope, so a tenant switch
/// invalidates it exactly as it does every other guarded route.
void openTenantReconciliationRun(
  BuildContext context, {
  required TenantDataReader reader,
  required String jobId,
}) {
  final controller = TenantSessionScope.of(context);
  Navigator.of(context).push(
    AppPageRoute<void>(
      builder: (_) => TenantSessionScope(
        controller: controller,
        child: TenantReconciliationRunScreen(reader: reader, jobId: jobId),
      ),
    ),
  );
}

/// Route describing the one run a difference names as having found it.
///
/// Every recorded difference carries a `jobId` and says so, and until this route
/// existed that was the end of the trail: the day page is addressed by business
/// date, and a difference is about a product or a shift rather than a day. What
/// this answers is whether the run that found it finished, what else it found,
/// and whether it is going to run again.
///
/// It lives in its own library rather than beside the day page because the day
/// page and the differences list both describe a run with the card below, and
/// the day page already opens the differences list - putting the card in either
/// would make those two import each other. The route itself is opened only from
/// a difference: the day page already lists that card for every run it holds, so
/// opening one from there would answer a question that is on screen already.
final class TenantReconciliationRunScreen extends StatelessWidget {
  const TenantReconciliationRunScreen({
    super.key,
    required this.reader,
    required this.jobId,
  });

  final TenantDataReader reader;
  final String jobId;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Reconciliation run',
    contentWidth: AppContentWidth.reading,
    body: TenantReconciliationRunPanel(reader: reader, jobId: jobId),
  );
}

/// One guarded run with the staff name it needs, if it names a member at all.
final class _RunView {
  const _RunView({required this.run, required this.names});

  /// Null when no run is stored at that ID any more.
  final TenantReconciliationRun? run;
  final Map<String, String> names;
}

/// Reads one run by ID behind [TenantRouteGuard].
///
/// The route guard owns authorization and stale-session rejection: a tenant
/// switch during an outstanding read discards it before it can update the UI.
/// This surface writes nothing and offers nothing to write with - asking for a
/// run is done from the day it belongs to, where the cooldown that request
/// spends is explained.
final class TenantReconciliationRunPanel extends StatefulWidget {
  const TenantReconciliationRunPanel({
    super.key,
    required this.reader,
    required this.jobId,
  });

  final TenantDataReader reader;
  final String jobId;

  @override
  State<TenantReconciliationRunPanel> createState() =>
      _TenantReconciliationRunPanelState();
}

final class _TenantReconciliationRunPanelState
    extends State<TenantReconciliationRunPanel> {
  String? _loaderKey;
  TenantGuardedLoader<_RunView>? _loader;

  /// One loader per run, so a rebuild cannot restart a read in flight.
  TenantGuardedLoader<_RunView> _loaderFor(String key) {
    if (key == _loaderKey && _loader != null) return _loader!;
    _loaderKey = key;
    return _loader = (session) async {
      final run = await TenantReconciliationStatusRepository(
        session: session,
        reader: widget.reader,
      ).readRun(widget.jobId);
      final actorUid = run?.actorUid;
      // Resolved so this route and the day page describe one run identically. A
      // server actor names no member and is not offered to the resolver; an
      // unresolved member degrades to the authoritative UID.
      return _RunView(
        run: run,
        names: actorUid == null
            ? const <String, String>{}
            : await TenantStaffNameResolver(
                session: session,
                reader: widget.reader,
              ).resolve(<String>[actorUid]),
      );
    };
  }

  @override
  Widget build(BuildContext context) => TenantRouteGuard<_RunView>(
    key: ValueKey(widget.jobId),
    allowedRoles: TenantReconciliationStatusRepository.allowedRoles,
    load: _loaderFor(widget.jobId),
    denied: const Center(
      key: ValueKey('reconciliation-run-denied'),
      child: Text('Reconciliation runs are available to managers and owners.'),
    ),
    failure: (context, error) => const Center(
      key: ValueKey('reconciliation-run-failure'),
      child: Text('This reconciliation run could not be loaded.'),
    ),
    builder: (context, session, view) => ListView(
      key: const ValueKey('reconciliation-run'),
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          key: const ValueKey('reconciliation-run-title'),
          'Run ${widget.jobId}',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        // §5.1's own description of what `Disclosure` replaces: a permanent
        // helper paragraph. Both sentences are page-invariant - they are true of
        // every run this route will ever show - and the second used to be
        // repeated *under the record* as though it were a fact about that run.
        // The day page next door has said the same kind of thing behind the same
        // component since step 4; this is that decision reaching the other three
        // surfaces in the family.
        const Disclosure(
          key: ValueKey('reconciliation-run-scope-disclosure'),
          summary: 'What this page cannot do',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                key: ValueKey('reconciliation-run-scope'),
                'The server does the work; this is its own record of one piece '
                'of it. Nothing on this page can start, stop, or repeat a run.',
              ),
              SizedBox(height: 8),
              Text(
                key: ValueKey('reconciliation-run-outlives'),
                'A difference a run found is about a product or a shift rather '
                'than a day, so it stays listed until it is resolved even '
                'after the run itself is finished.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (view.run case final run?) ...[
          TenantReconciliationRunCard(
            run: run,
            names: view.names,
            selfUid: session.uid,
          ),
          const SizedBox(height: 8),
          // What is left of that paragraph once the page-invariant half of it
          // moved: a fact about this run, which the card does not state because
          // the day page mounts the same card under a heading that already
          // names the date.
          Text(
            key: const ValueKey('reconciliation-run-day'),
            'This run covered ${run.businessDate}.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ] else
          // A notice about the state of this page rather than a helper
          // paragraph, so `Callout` rather than `Disclosure` - and `info`
          // rather than `problem` because the sentence's own point is that
          // this is an ordinary answer.
          const Callout(
            key: ValueKey('reconciliation-run-missing'),
            status: AppStatus.info,
            message:
                'No run is recorded at this ID any more. A difference outlives '
                'the run that found it, so this is an ordinary answer rather '
                'than a fault - what the difference itself records still '
                'stands.',
          ),
      ],
    ),
  );
}

/// One run, stated the same way wherever it is shown.
///
/// Public and shared because a run is reached from two directions: the day it was
/// queued for, and any difference it found. Two descriptions of one record that
/// disagreed about what "completed" or "quarantined" means would be worse than
/// either.
final class TenantReconciliationRunCard extends StatelessWidget {
  const TenantReconciliationRunCard({
    super.key,
    required this.run,
    required this.names,
    required this.selfUid,
  });

  final TenantReconciliationRun run;

  /// Resolved staff names, empty when the run names no member of the business.
  final Map<String, String> names;

  final String selfUid;

  @override
  Widget build(BuildContext context) => Card(
    key: ValueKey('reconciliation-status-run-${run.id}'),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // §5.1: a `StatusBadge` replaces inline coloured text, and §5.2 puts
          // the status in the record's leading position. A run's state was a
          // word in a title here, which is the one rendering §2.1 forbids - a
          // page of runs mixes completed, queued and failed, so the badge is
          // what makes that scannable without reading every card.
          Align(
            alignment: Alignment.centerLeft,
            child: StatusBadge(
              key: ValueKey('reconciliation-status-run-badge-${run.id}'),
              status: reconciliationRunStatus(run),
              label: reconciliationRunStatusWord(run),
              semanticLabel:
                  'Run ${run.id}: ${reconciliationRunStatusWord(run)}',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            key: ValueKey('reconciliation-status-run-state-${run.id}'),
            _sourceLabel(run),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          // Only where the enum's own label says more than the badge's word: a
          // retry is scheduled, the server gave up after repeated failures, or
          // the state is one this build does not model and the stored value is
          // the only honest thing to show.
          if (reconciliationRunStatusDetail(run) case final detail?)
            Text(
              key: ValueKey('reconciliation-status-run-state-detail-${run.id}'),
              detail,
            ),
          const SizedBox(height: 8),
          Text(
            key: ValueKey('reconciliation-status-run-progress-${run.id}'),
            _progress(run),
          ),
          if (run.lastErrorCode case final code?)
            Text(
              key: ValueKey('reconciliation-status-run-error-${run.id}'),
              'Server code: $code',
            ),
          if (run.hasVariances)
            Text(
              key: ValueKey('reconciliation-status-run-variance-${run.id}'),
              '${run.stockVarianceCount} stock and ${run.shiftVarianceCount} '
              'shift differences were recorded.',
            ),
          if (run.rerunRequested)
            Text(
              key: ValueKey('reconciliation-status-run-rerun-${run.id}'),
              'A change arrived while this run was working, so it will run '
              'again.',
            ),
          Text(
            key: ValueKey('reconciliation-status-run-requested-${run.id}'),
            'Requested by ${_requestedByLabel(run)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            key: ValueKey('reconciliation-status-run-instants-${run.id}'),
            _instants(run),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );

  /// A member's UID resolves to a name; a `system:` actor names no member of the
  /// business and is shown as the server work it is.
  String _requestedByLabel(TenantReconciliationRun run) {
    final actorUid = run.actorUid;
    if (actorUid == null) return 'the server (${run.requestedBy})';
    return tenantStaffLabel(actorUid, names: names, selfUid: selfUid);
  }
}

/// An unmodelled value is shown as itself: hiding a real run, or renaming its
/// source, would be worse than naming what the server actually recorded. The
/// same rule for a run's *state* is [reconciliationRunStatusDetail].
String _sourceLabel(TenantReconciliationRun run) =>
    run.source == TenantReconciliationRunSource.other
    ? run.sourceValue
    : run.source.label;

String _phaseLabel(TenantReconciliationRun run) =>
    run.phase == TenantReconciliationRunPhase.other
    ? run.phaseValue
    : run.phase.label;

String _modeLabel(TenantReconciliationRun run) => switch (run.mode) {
  'incremental' => 'Incremental',
  'full' => 'Full check',
  final other => other,
};

/// When the run did what it did.
///
/// A run ID carries no time - it is a digest for a scheduled or manual run and a
/// five-minute bucket for a sale trigger - and both surfaces order runs by ID, so
/// these are the only times a run has. A run that records none is stated as such
/// rather than left with a silent gap where a time belongs.
String _instants(TenantReconciliationRun run) {
  final recorded = <String>[
    if (run.completedAt case final at?)
      'Completed ${reconciliationInstant(at)}',
    if (run.lastFailedAt case final at?)
      'Last failed ${reconciliationInstant(at)}',
    if (run.updatedAt case final at?)
      'Last updated ${reconciliationInstant(at)}',
  ];
  if (recorded.isEmpty) return 'No instant was recorded for this run.';
  return recorded.join(' • ');
}

String _progress(TenantReconciliationRun run) {
  final attempts =
      '${run.attemptCount} '
      '${run.attemptCount == 1 ? 'attempt' : 'attempts'}';
  final failures = run.consecutiveFailureCount == 0
      ? ''
      : ', ${run.consecutiveFailureCount} in a row failed';
  return '${_modeLabel(run)} • reached ${_phaseLabel(run)} • '
      '$attempts$failures';
}
