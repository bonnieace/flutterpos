import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../ui/pagination.dart';
import '../ui/record_list.dart';
import '../ui/routes.dart';
import '../ui/scaffold.dart';
import '../ui/tokens.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session_controller.dart';
import '../tenancy/tenant_staff_names.dart';
import 'reconciliation_labels.dart';
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
    AppPageRoute<void>(
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
  Widget build(BuildContext context) => AppScaffold(
    title: 'Shift corrections',
    subtitle: shiftId,
    contentWidth: AppContentWidth.records,
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
  TenantGuardedLoader<TenantShiftAmendmentRecordPage>? _loaderCached;

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
  void _composeLoaders(String key) {
    if (key == _loaderKey && _loader != null) return;
    _loaderKey = key;
    final cursor = _cursors[_pageIndex];
    final shiftId = _shiftId;
    TenantGuardedLoader<TenantShiftAmendmentRecordPage> readWith(TenantDataReader reader) =>
        (session) {
      final repository = TenantShiftAmendmentFeedRepository(
        session: session,
        reader: reader,
      );
      return shiftId == null
          ? repository.loadAmendments(pageSize: widget.pageSize, cursor: cursor)
          : repository.loadShiftAmendments(
              shiftId: shiftId,
              pageSize: widget.pageSize,
              cursor: cursor,
            );
    };
    _loader = readWith(widget.reader);
    final cache = widget.reader.cached;
    _loaderCached = cache == null ? null : readWith(cache);
  }

  @override
  Widget build(BuildContext context) {
    final cursor = _cursors[_pageIndex];
    final guardKey = '$_shiftId:$_pageIndex:$cursor';
    _composeLoaders(guardKey);
    return TenantRouteGuard<TenantShiftAmendmentRecordPage>(
      key: ValueKey(guardKey),
      allowedRoles: TenantShiftAmendmentFeedRepository.allowedRoles,
      load: _loader!,
      loadCached: _loaderCached,
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
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return ListView(
      key: const ValueKey('shift-amendments'),
      padding: EdgeInsets.all(tokens.spacing.s20),
      children: [
        // §7's "Title appears once", in both of this route's two forms: unscoped
        // it repeated the `AppScaffold` title exactly, and scoped it named
        // *which* shift, which is `PageHeader.subtitle`'s row. The screen has the
        // shift ID as a constructor argument, so it supplies the subtitle
        // directly rather than this panel waiting for the page to load to say
        // which shift it is showing.
        const Text(
          key: ValueKey('shift-amendments-scope'),
          'A closed shift can be corrected to the total its own sales prove, when '
          'the server found the two disagreed. Every correction is recorded here '
          'permanently, with the reason given and the person who asked. Nothing '
          'on this page can make, change, or remove one.',
        ),
        SizedBox(height: tokens.spacing.s4),
        const Text(
          key: ValueKey('shift-amendments-cash'),
          'No correction here changed a drawer count. The recorded sales and the '
          'counted cash are separate figures, and only the first can be '
          'corrected this way - so a shift may still be reported short after one.',
        ),
        if (page.isShiftScoped) ...[
          SizedBox(height: tokens.spacing.s16),
          AppButton(
            key: const ValueKey('shift-amendments-show-all'),
            label: 'Show every shift',
            onPressed: onShowAllShifts,
          ),
        ],
        SizedBox(height: tokens.spacing.s16),
        // §4.3's responsive contract. A correction is the densest record in this
        // app - it states what moved, what disagreed, why, and where it was read
        // from - so what a column is worth was decided by what a person scans a
        // correction trail for rather than by giving every sentence its own.
        RecordList(
          identityLabel: 'Correction',
          items: <RecordItem>[for (final record in page.items) _record(record)],
          empty: Text(
            key: const ValueKey('shift-amendments-empty'),
            page.isShiftScoped
                ? 'This shift\'s summary has never been corrected.'
                : 'No shift summary has been corrected in this business.',
          ),
        ),
        SizedBox(height: tokens.spacing.s8),
        Text(
          'This list is not in time order: a record is addressed by the request '
          'that made it, not by when it was made. Each one states its own '
          'recorded instant.',
          style: tokens.typography.caption.copyWith(
            color: tokens.colors.text.tertiary,
          ),
        ),
        SizedBox(height: tokens.spacing.s16),
        Pagination(
          pageNumber: pageIndex + 1,
          previousKey: const ValueKey('shift-amendments-previous'),
          nextKey: const ValueKey('shift-amendments-next'),
          onPrevious: pageIndex > 0 ? onPreviousPage : null,
          onNext: page.hasMore ? onNextPage : null,
        ),
      ],
    );
  }

  /// One correction as §5.2's rows.
  ///
  /// **The record is the correction, not the shift it corrected**, which is why
  /// the shift is the title and the correction's own ID is the second
  /// identifying line. It used to be the last clause of the evidence sentence,
  /// where nothing could be scanned by it.
  ///
  /// **No standing.** §2.1's five each mean exactly one thing and "a correction
  /// was recorded" is not among them - the same reading the activity log and the
  /// stock ledger reached, and for the same reason: a list where every row wears
  /// a badge is a list with no signal in it. What a correction *cleared* is a
  /// fact about it and is stated as one.
  RecordItem _record(TenantShiftAmendmentRecord record) => RecordItem(
    id: record.id,
    recordKey: ValueKey('shift-amendment-${record.id}'),
    title: 'Shift ${record.shiftId} on ${record.businessDate}',
    titleKey: ValueKey('shift-amendment-subject-${record.id}'),
    subtitle: 'Recorded as ${record.id}',
    subtitleKey: ValueKey('shift-amendment-record-${record.id}'),
    attributes: <RecordAttribute>[
      // **Two figures, two columns**, where one assembled sentence used to name
      // whichever of them moved. A sentence that sometimes says sales, sometimes
      // the count and sometimes both cannot be a column: the same document would
      // be filed under a different heading depending on what it happened to
      // change. The unmoved case says so rather than going silent, because an
      // empty cell here would read as a figure nobody recorded.
      RecordAttribute(
        kind: RecordValueKind.money,
        label: 'Recorded sales',
        value: record.changedSales
            ? '${_money(record.previousTotalSalesMinor)} to '
                  '${_money(record.totalSalesMinor)}'
            : 'Unchanged',
        valueKey: ValueKey('shift-amendment-sales-${record.id}'),
        flex: 2,
      ),
      // Twice an ordinary share for its *heading* rather than its value: the
      // word "Transactions" is wider than "1 to 3", and at an equal share the
      // first render ran it into the column beside it.
      RecordAttribute(
        kind: RecordValueKind.code,
        label: 'Transactions',
        value: record.changedTransactionCount
            ? '${record.previousTransactionCount} to ${record.transactionCount}'
            : 'Unchanged',
        valueKey: ValueKey('shift-amendment-transactions-${record.id}'),
        flex: 2,
      ),
      RecordAttribute(
        kind: RecordValueKind.money,
        label: 'Difference',
        value: _difference(record),
        valueKey: ValueKey('shift-amendment-difference-${record.id}'),
        flex: 3,
      ),
      RecordAttribute(
        label: 'Reason',
        value: record.reason,
        valueKey: ValueKey('shift-amendment-reason-${record.id}'),
        flex: 2,
      ),
      RecordAttribute(
        label: 'Evidence',
        value: _evidence(record),
        valueKey: ValueKey('shift-amendment-evidence-${record.id}'),
        flex: 2,
      ),
    ],
    provenance: _actor(record),
    provenanceKey: ValueKey('shift-amendment-actor-${record.id}'),
  );

  /// Everything this correction found wrong and everything it settled.
  ///
  /// **One column rather than three, and the three used to be three lines.**
  /// The money variance, the transaction variance, a shift whose two records of
  /// the same money disagreed, and a difference struck off the unresolved list
  /// are four statements about *one* disagreement, so splitting them would spend
  /// four columns saying what happened once - and two of the four are silent on
  /// most records, which is a table of mostly empty cells.
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
    final sentences = <String>[
      parts.isEmpty
          ? 'The server recorded no difference in the figures themselves.'
          : 'The shift had ${parts.join(', and ')}.',
      if (!record.previousRepresentationsAgreed)
        'Before this, the shift\'s two records of the same money did not agree '
            'with each other. Both were rewritten.',
      if (record.clearedAnomalyId case final anomalyId?)
        'This removed difference $anomalyId from the unresolved list.',
    ];
    return sentences.join(' ');
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
    // **§8 rule 9 - a timestamp states its zone - and this was the one surface
    // still printing a raw ISO instant.** `2026-08-01T02:30:00.000Z` is the wire
    // format; every other screen in this family says `2026-08-01 02:30 UTC`, and
    // `reconciliation_labels.dart` records fixing exactly this defect on the
    // pages that link to this one. The seconds and milliseconds were noise on a
    // record whose own ordering is by the minute.
    final when = at == null
        ? 'no time was recorded'
        : 'recorded ${reconciliationInstant(at)}';
    return 'Corrected by $actor, $when.';
  }

  /// The evidence the correction was read from, so the record can be traced
  /// rather than merely believed.
  ///
  /// It named the correction's own document last, and that clause is the
  /// record's second identifying line now: a person tracing one addresses it by
  /// that ID, and an identity is where an ID a person addresses a record by
  /// belongs.
  String _evidence(TenantShiftAmendmentRecord record) =>
      'Shift belonged to ${record.staffId}. Corrected from expectation '
      '${record.expectationId} at generation ${record.expectationGeneration}.';
}

String _money(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);
