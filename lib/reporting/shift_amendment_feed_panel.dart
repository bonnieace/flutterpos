import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session_controller.dart';
import '../tenancy/tenant_staff_names.dart';
import 'shift_amendment_feed.dart';

/// Opens the trail under the caller's own session scope, so a tenant switch
/// invalidates it exactly as it does every other guarded route rather than
/// leaving a detached screen behind.
void openTenantShiftAmendments(
  BuildContext context, {
  required TenantDataReader reader,
  String? shiftId,
}) {
  final controller = TenantSessionScope.of(context);
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TenantSessionScope(
        controller: controller,
        child: TenantShiftAmendmentScreen(reader: reader, shiftId: shiftId),
      ),
    ),
  );
}

/// Route listing every closed shift whose summary was corrected.
final class TenantShiftAmendmentScreen extends StatelessWidget {
  const TenantShiftAmendmentScreen({
    super.key,
    required this.reader,
    this.shiftId,
  });

  final TenantDataReader reader;

  /// Opens the trail already narrowed to one shift.
  final String? shiftId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Shift corrections')),
    body: TenantShiftAmendmentPanel(reader: reader, shiftId: shiftId),
  );
}

/// Shows one bounded page of the business's shift corrections.
///
/// This surface writes nothing, and cannot: `shift_amendments` is `allow write:
/// if false` for every client, and the record it lists was appended by the same
/// transaction that rewrote the shift. It exists because a correction that
/// nobody can see afterwards is not answerable - the differences list offers the
/// correction, and this is the only account of the ones already made.
///
/// The route guard owns authorization and stale-session rejection: a tenant
/// switch during an outstanding page discards it before it can update the UI.
final class TenantShiftAmendmentPanel extends StatefulWidget {
  const TenantShiftAmendmentPanel({
    super.key,
    required this.reader,
    this.shiftId,
    this.pageSize = 20,
  });

  final TenantDataReader reader;
  final String? shiftId;
  final int pageSize;

  @override
  State<TenantShiftAmendmentPanel> createState() =>
      _TenantShiftAmendmentPanelState();
}

final class _TenantShiftAmendmentPanelState
    extends State<TenantShiftAmendmentPanel> {
  List<String?> _cursors = <String?>[null];
  int _pageIndex = 0;
  String? _shiftId;
  String? _loaderKey;
  TenantGuardedLoader<TenantShiftAmendmentRecordPage>? _loader;

  @override
  void initState() {
    super.initState();
    _shiftId = widget.shiftId;
  }

  @override
  void didUpdateWidget(covariant TenantShiftAmendmentPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shiftId != widget.shiftId) _narrow(widget.shiftId);
  }

  /// A cursor is a position inside one exact query, so changing the filter
  /// starts the list again rather than resuming from somewhere the new query
  /// never established.
  void _narrow(String? shiftId) {
    setState(() {
      _shiftId = shiftId;
      _cursors = <String?>[null];
      _pageIndex = 0;
    });
  }

  void _nextPage(String? cursor) {
    if (cursor == null) return;
    setState(() {
      _cursors = <String?>[..._cursors.take(_pageIndex + 1), cursor];
      _pageIndex++;
    });
  }

  void _previousPage() {
    if (_pageIndex == 0) return;
    setState(() => _pageIndex--);
  }

  /// One loader per guard key, so a closure rebuilt every frame cannot restart
  /// the load on an unrelated `setState`.
  TenantGuardedLoader<TenantShiftAmendmentRecordPage> _loaderFor(String key) {
    if (key == _loaderKey && _loader != null) return _loader!;
    _loaderKey = key;
    final cursor = _cursors[_pageIndex];
    final shiftId = _shiftId;
    return _loader = (session) {
      final repository = TenantShiftAmendmentFeedRepository(
        session: session,
        reader: widget.reader,
      );
      return shiftId == null
          ? repository.loadAmendments(
              pageSize: widget.pageSize,
              cursor: cursor,
            )
          : repository.loadShiftAmendments(
              shiftId: shiftId,
              pageSize: widget.pageSize,
              cursor: cursor,
            );
    };
  }

  @override
  Widget build(BuildContext context) {
    final cursor = _cursors[_pageIndex];
    final guardKey = '$_shiftId:$_pageIndex:$cursor';
    return TenantRouteGuard<TenantShiftAmendmentRecordPage>(
      key: ValueKey(guardKey),
      allowedRoles: TenantShiftAmendmentFeedRepository.allowedRoles,
      load: _loaderFor(guardKey),
      denied: const Center(
        key: ValueKey('shift-amendments-denied'),
        child: Text('Shift corrections are available to managers and owners.'),
      ),
      failure: (context, error) => const Center(
        key: ValueKey('shift-amendments-failure'),
        child: Text('The shift corrections could not be loaded.'),
      ),
      builder: (context, session, page) => _AmendmentContents(
        page: page,
        selfUid: session.uid,
        pageIndex: _pageIndex,
        onShowAllShifts: () => _narrow(null),
        onNextPage: () => _nextPage(page.nextCursor),
        onPreviousPage: _previousPage,
      ),
    );
  }
}

final class _AmendmentContents extends StatelessWidget {
  const _AmendmentContents({
    required this.page,
    required this.selfUid,
    required this.pageIndex,
    required this.onShowAllShifts,
    required this.onNextPage,
    required this.onPreviousPage,
  });

  final TenantShiftAmendmentRecordPage page;
  final String selfUid;
  final int pageIndex;
  final VoidCallback onShowAllShifts;
  final VoidCallback onNextPage;
  final VoidCallback onPreviousPage;

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('shift-amendments'),
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        page.isShiftScoped
            ? 'Corrections to shift ${page.shiftId}'
            : 'Shift corrections',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 4),
      const Text(
        key: ValueKey('shift-amendments-scope'),
        'A closed shift can be corrected to the total its own sales prove, when '
        'the server found the two disagreed. Every correction is recorded here '
        'permanently, with the reason given and the person who asked. Nothing '
        'on this page can make, change, or remove one.',
      ),
      const SizedBox(height: 4),
      const Text(
        key: ValueKey('shift-amendments-cash'),
        'No correction here changed a drawer count. The recorded sales and the '
        'counted cash are separate figures, and only the first can be '
        'corrected this way - so a shift may still be reported short after one.',
      ),
      if (page.isShiftScoped) ...[
        const SizedBox(height: 16),
        AppButton(
          key: const ValueKey('shift-amendments-show-all'),
          label: 'Show every shift',
          onPressed: onShowAllShifts,
        ),
      ],
      const SizedBox(height: 16),
      if (page.items.isEmpty)
        Text(
          key: const ValueKey('shift-amendments-empty'),
          page.isShiftScoped
              ? 'This shift\'s summary has never been corrected.'
              : 'No shift summary has been corrected in this business.',
        )
      else
        for (final record in page.items) _record(context, record),
      const SizedBox(height: 8),
      Text(
        'This list is not in time order: a record is addressed by the request '
        'that made it, not by when it was made. Each one states its own '
        'recorded instant.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        children: [
          if (pageIndex > 0)
            AppButton(
              key: const ValueKey('shift-amendments-previous'),
              label: 'Previous page',
              onPressed: onPreviousPage,
            ),
          if (page.hasMore)
            AppButton(
              key: const ValueKey('shift-amendments-next'),
              label: 'Next page',
              tier: AppButtonTier.primary,
              onPressed: onNextPage,
            ),
        ],
      ),
    ],
  );

  Widget _record(BuildContext context, TenantShiftAmendmentRecord record) => Card(
    key: ValueKey('shift-amendment-${record.id}'),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            key: ValueKey('shift-amendment-subject-${record.id}'),
            'Shift ${record.shiftId} on ${record.businessDate}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            key: ValueKey('shift-amendment-change-${record.id}'),
            _change(record),
          ),
          Text(
            key: ValueKey('shift-amendment-difference-${record.id}'),
            _difference(record),
          ),
          if (!record.previousRepresentationsAgreed)
            Text(
              key: ValueKey('shift-amendment-inconsistent-${record.id}'),
              'Before this, the shift\'s two records of the same money did not '
              'agree with each other. Both were rewritten.',
            ),
          if (record.clearedAnomalyId case final anomalyId?)
            Text(
              key: ValueKey('shift-amendment-cleared-${record.id}'),
              'This removed difference $anomalyId from the unresolved list.',
            ),
          const SizedBox(height: 4),
          Text(
            key: ValueKey('shift-amendment-reason-${record.id}'),
            'Reason given: ${record.reason}',
          ),
          const SizedBox(height: 4),
          Text(
            key: ValueKey('shift-amendment-actor-${record.id}'),
            _actor(record),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            key: ValueKey('shift-amendment-evidence-${record.id}'),
            _evidence(record),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );

  /// What the correction actually moved, said only about the figures that moved.
  ///
  /// A correction may change the money, the transaction count, or both, and
  /// claiming a figure changed when it did not would misstate the record.
  String _change(TenantShiftAmendmentRecord record) {
    final parts = <String>[
      if (record.changedSales)
        'its recorded sales from ${_money(record.previousTotalSalesMinor)} to '
            '${_money(record.totalSalesMinor)}',
      if (record.changedTransactionCount)
        'its transaction count from ${record.previousTransactionCount} to '
            '${record.transactionCount}',
    ];
    if (parts.isEmpty) {
      // Reachable only for a shift whose two money representations disagreed:
      // both were rewritten from one figure without either total changing.
      return 'This correction rewrote the shift\'s totals without changing '
          'either figure.';
    }
    return 'Corrected ${parts.join(' and ')}.';
  }

  /// The difference that was resolved, in the direction the server recorded it.
  String _difference(TenantShiftAmendmentRecord record) {
    final money = record.salesVarianceMinor == 0
        ? null
        : 'recorded ${_money(record.salesVarianceMinor.abs())} '
              '${record.overstatedSales ? 'more' : 'less'} than its sales prove';
    final counts = record.transactionVariance == 0
        ? null
        : 'counted ${record.transactionVariance.abs()} '
              '${record.transactionVariance.abs() == 1 ? 'transaction' : 'transactions'} '
              '${record.transactionVariance > 0 ? 'more' : 'fewer'}';
    final parts = <String>[
      if (money case final part?) part,
      if (counts case final part?) part,
    ];
    if (parts.isEmpty) {
      return 'The server recorded no difference in the figures themselves.';
    }
    return 'The shift had ${parts.join(', and ')}.';
  }

  /// Who asked, and when the server committed it.
  ///
  /// A name is resolved only for the person reading: this surface deliberately
  /// makes no staff-directory read, so the correction trail stays readable even
  /// when the directory is not. Every other record in the business attributes
  /// its actor by UID for the same reason.
  String _actor(TenantShiftAmendmentRecord record) {
    final actor = tenantStaffLabel(
      record.actorUid,
      names: const <String, String>{},
      selfUid: selfUid,
    );
    final at = record.recordedAt;
    final when = at == null
        ? 'no time was recorded'
        : 'recorded ${at.toIso8601String()}';
    return 'Corrected by $actor, $when.';
  }

  /// The evidence the correction was read from, so the record can be traced
  /// rather than merely believed.
  String _evidence(TenantShiftAmendmentRecord record) =>
      'Shift belonged to ${record.staffId}. Corrected from expectation '
      '${record.expectationId} at generation ${record.expectationGeneration}. '
      'Recorded as ${record.id}.';
}

String _money(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);
