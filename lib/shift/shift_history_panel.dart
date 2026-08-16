import 'package:flutter/material.dart';

import '../reporting/shift_amendment_feed.dart';
import '../reporting/shift_amendment_feed_panel.dart';
import '../returns/return_actions.dart';
import '../sales/sale_history.dart';
import '../sales/sale_history_panel.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../tenancy/tenant_staff_names.dart';
import '../ui/buttons.dart';
import '../ui/pagination.dart';
import '../ui/record_list.dart';
import '../ui/routes.dart';
import '../ui/scaffold.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'shift_history.dart';

/// Read-only shift history route for the selected tenant session.
final class TenantShiftHistoryScreen extends StatelessWidget {
  const TenantShiftHistoryScreen({
    super.key,
    required this.reader,
    this.returnActions,
  });

  final TenantDataReader reader;

  /// Passed through to the sales and returns routes. Recording a return stays
  /// unavailable while it is absent.
  final TenantReturnActions? returnActions;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Shift history',
    contentWidth: AppContentWidth.records,
    body: TenantShiftHistoryPanel(reader: reader, returnActions: returnActions),
  );
}

/// Pages closed shifts behind [TenantRouteGuard].
///
/// The guard owns authorization and stale-session rejection: a tenant switch
/// during an outstanding page discards that page before it can be rendered.
/// The panel owns only the requested scope and the cursor stack, and it never
/// recomputes a recorded figure.
final class TenantShiftHistoryPanel extends StatefulWidget {
  const TenantShiftHistoryPanel({
    super.key,
    required this.reader,
    this.returnActions,
    this.pageSize = 20,
  });

  final TenantDataReader reader;

  /// Passed through to the sales route only. This surface never writes.
  final TenantReturnActions? returnActions;
  final int pageSize;

  @override
  State<TenantShiftHistoryPanel> createState() =>
      _TenantShiftHistoryPanelState();
}

final class _TenantShiftHistoryPanelState
    extends State<TenantShiftHistoryPanel> {
  TenantShiftHistoryScope _scope = TenantShiftHistoryScope.ownShifts;

  /// The cursor that opened each visited page. The first page has none.
  List<String?> _cursors = <String?>[null];
  int _pageIndex = 0;
  TenantStaffNameResolver? _staffNames;
  String? _staffNamesSessionKey;

  /// One resolver per session, so its cache is discarded the moment the UID,
  /// business, or epoch changes and can never label the next session's rows.
  TenantStaffNameResolver _resolverFor(TenantSession session) {
    final key = '${session.uid}:${session.tenantId}:${session.epoch}';
    if (key != _staffNamesSessionKey || _staffNames == null) {
      _staffNamesSessionKey = key;
      _staffNames = TenantStaffNameResolver(
        session: session,
        reader: widget.reader,
      );
    }
    return _staffNames!;
  }

  void _setScope(TenantShiftHistoryScope scope) {
    if (scope == _scope) return;
    setState(() {
      _scope = scope;
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

  @override
  Widget build(BuildContext context) {
    final cursor = _cursors[_pageIndex];
    return TenantRouteGuard<TenantNamedPage<TenantShiftHistoryPage>>(
      // A new key restarts the guard for a new scope or page, so an earlier
      // page can never complete into the current one.
      key: ValueKey('${_scope.name}:$_pageIndex:$cursor'),
      load: (session) async {
        final page = await TenantShiftHistoryRepository(
          session: session,
          reader: widget.reader,
        ).loadPage(scope: _scope, pageSize: widget.pageSize, cursor: cursor);
        return TenantNamedPage<TenantShiftHistoryPage>(
          page: page,
          names: await _resolverFor(
            session,
          ).resolve(page.items.map((entry) => entry.staffId)),
        );
      },
      denied: const Center(
        key: ValueKey('shift-history-denied'),
        child: Text('Shift history is unavailable for this business.'),
      ),
      failure: (context, error) => const Center(
        key: ValueKey('shift-history-failure'),
        child: Text('Shift history could not be loaded.'),
      ),
      builder: (context, session, named) => _ShiftHistoryContents(
        session: session,
        page: named.page,
        staffNames: named.names,
        pageIndex: _pageIndex,
        // The trail's own repository is the authority on who may read it, not
        // this surface's management set. The two happen to name the same roles
        // today, and offering a link this session's server would refuse would
        // teach a cashier nothing except that the app guesses.
        canReadCorrections: TenantShiftAmendmentFeedRepository.canReadInSession(
          session,
        ),
        onScopeChanged: _setScope,
        onNextPage: () => _nextPage(named.page.nextCursor),
        onPreviousPage: _previousPage,
        onViewSales: (request) => _openSales(context, request),
        onViewCorrections: (shiftId) => _openCorrections(context, shiftId),
      ),
    );
  }

  /// Opens the read-only sales route under the same session scope, so its own
  /// guard sees the exact controller this page was authorized against.
  void _openSales(BuildContext context, TenantSaleHistoryRequest request) {
    final sessions = TenantSessionScope.read(context);
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => TenantSessionScope(
          controller: sessions,
          child: TenantSaleHistoryScreen(
            reader: widget.reader,
            request: request,
            returnActions: widget.returnActions,
          ),
        ),
      ),
    );
  }

  /// Opens the business's corrections trail narrowed to one shift, under the same
  /// session scope, so that route's guard sees the exact controller this page was
  /// authorized against.
  ///
  /// It needs no injected capability: the trail is a read of the same business
  /// through the same reader, so there is nothing here for a composition root to
  /// grant or withhold - the same reason the differences list opens it directly.
  void _openCorrections(BuildContext context, String shiftId) {
    final sessions = TenantSessionScope.read(context);
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => TenantSessionScope(
          controller: sessions,
          child: TenantShiftAmendmentScreen(
            reader: widget.reader,
            shiftId: shiftId,
          ),
        ),
      ),
    );
  }
}

final class _ShiftHistoryContents extends StatelessWidget {
  const _ShiftHistoryContents({
    required this.session,
    required this.page,
    required this.staffNames,
    required this.pageIndex,
    required this.canReadCorrections,
    required this.onScopeChanged,
    required this.onNextPage,
    required this.onPreviousPage,
    required this.onViewSales,
    required this.onViewCorrections,
  });

  final TenantSession session;
  final TenantShiftHistoryPage page;
  final Map<String, String> staffNames;
  final int pageIndex;

  /// Whether this session may read the corrections trail itself. A cashier is
  /// still told that their shift was corrected - the shift document they can
  /// already read says so, and the figures on the row are the corrected ones -
  /// but the record of who asked for it and why is the business's governance and
  /// is deliberately not theirs to read.
  final bool canReadCorrections;

  final ValueChanged<TenantShiftHistoryScope> onScopeChanged;
  final VoidCallback onNextPage;
  final VoidCallback onPreviousPage;
  final ValueChanged<TenantSaleHistoryRequest> onViewSales;

  /// Opens the trail narrowed to one shift, by its document ID.
  final ValueChanged<String> onViewCorrections;

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('shift-history'),
    padding: const EdgeInsets.all(20),
    children: [
      // §7's "Title appears once": the `AppScaffold` above says `Shift
      // history`, and this named the same list in different words under it.
      const SizedBox(height: 4),
      const Text(
        key: ValueKey('shift-history-scope-note'),
        'Counted cash and recorded sales are shown exactly as the server holds '
        'them, and are never recomputed here. Reconciliation resolves any '
        'difference. A shift whose recorded sales it corrected says so on its '
        'own row: a correction rewrites the recorded sales to the total that '
        'shift\'s own sales prove, and never the counted cash.',
      ),
      // Said once, above the list, because it is the same sentence on every
      // corrected row and it is about this session rather than about any shift.
      // It used to be repeated inside each corrected record, where §5.2 has a
      // key-value line and no room for a paragraph.
      if (!canReadCorrections &&
          page.items.any((entry) => entry.amendment != null)) ...[
        const SizedBox(height: 4),
        const Text(
          key: ValueKey('shift-history-corrections-denied'),
          'The record of who corrected a shift, and why, is available to '
          'managers, administrators, and owners.',
        ),
      ],
      const SizedBox(height: 16),
      if (TenantShiftHistoryRepository.canReadEveryCashier(session))
        SegmentedButton<TenantShiftHistoryScope>(
          key: const ValueKey('shift-history-scope'),
          segments: const [
            ButtonSegment<TenantShiftHistoryScope>(
              value: TenantShiftHistoryScope.ownShifts,
              label: Text('My shifts'),
            ),
            ButtonSegment<TenantShiftHistoryScope>(
              value: TenantShiftHistoryScope.everyCashier,
              label: Text('Every cashier'),
            ),
          ],
          selected: <TenantShiftHistoryScope>{page.scope},
          onSelectionChanged: (selection) => onScopeChanged(selection.single),
        ),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: AppButton(
          key: const ValueKey('shift-history-own-sales'),
          label: 'My recent sales',
          icon: Icons.receipt_long_outlined,
          onPressed: () => onViewSales(const TenantOwnSaleHistoryRequest()),
        ),
      ),
      const SizedBox(height: 16),
      // §4.3's responsive contract.
      RecordList(
        identityLabel: 'Shift',
        items: <RecordItem>[for (final entry in page.items) _entry(entry)],
        // §7's Empty pattern. Closing a shift happens on the shift banner and
        // not here, so this states what would be here and offers nothing.
        empty: const EmptyState(
          key: ValueKey('shift-history-empty'),
          title: 'No closed shifts yet',
          hint: 'A shift appears here once it has been closed.',
        ),
      ),
      const SizedBox(height: 16),
      Pagination(
        pageNumber: pageIndex + 1,
        previousKey: const ValueKey('shift-history-previous'),
        nextKey: const ValueKey('shift-history-next'),
        onPrevious: pageIndex > 0 ? onPreviousPage : null,
        onNext: page.hasMore ? onNextPage : null,
      ),
    ],
  );

  /// One closed shift as §5.2's rows.
  ///
  /// **This is the first record in the sweep whose standing is a lookup rather
  /// than a silence**, and the lookup is §2.1's own table. A closed shift is not
  /// merely closed - every shift on this page is, and a badge every row wears is
  /// a badge with no signal in it. What varies, and what this whole screen
  /// exists to settle, is whether the drawer agrees with the sales: `ok` is
  /// §2.1's "reconciled, confirmed", a shift that disagrees is its "difference
  /// found", and a shift that closed without a summary can be compared with
  /// nothing at all, which is "unreconciled".
  ///
  /// The figure keeps its own attribute either way, so the amount is never
  /// carried by the badge alone - and the badge's semantic label is the sentence
  /// this row used to state, so a screen reader hears no less than it did.
  RecordItem _entry(TenantShiftHistoryEntry entry) {
    final summary = entry.summary;
    final variance = entry.cashVarianceMinor;
    return RecordItem(
      id: entry.id,
      recordKey: ValueKey('shift-history-entry-${entry.id}'),
      title: '${entry.businessDate} - ${_staffLabel(entry)}',
      titleKey: ValueKey('shift-history-subject-${entry.id}'),
      status: RecordStatus(
        badgeKey: ValueKey('shift-history-status-${entry.id}'),
        status: switch (variance) {
          null => AppStatus.attention,
          0 => AppStatus.ok,
          _ => AppStatus.problem,
        },
        label: switch (variance) {
          null => 'No closing summary',
          0 => 'Cash matches',
          final over when over > 0 => 'Cash over',
          _ => 'Cash short',
        },
        semanticLabel: variance == null
            ? 'No closing summary was recorded for this shift.'
            : _varianceLabel(variance),
      ),
      attributes: <RecordAttribute>[
        RecordAttribute(
          label: 'Counted cash',
          value: _money(entry.closingCashMinor),
          valueKey: ValueKey('shift-history-counted-${entry.id}'),
        ),
        // Two figures the close recorded, and two columns: one sentence naming
        // both meant the transaction count could not be read down a page.
        if (summary != null) ...<RecordAttribute>[
          RecordAttribute(
            label: 'Recorded sales',
            value: _money(summary.totalSalesMinor),
            valueKey: ValueKey('shift-history-sales-${entry.id}'),
          ),
          RecordAttribute(
            label: 'Transactions',
            value: '${summary.transactionCount}',
            valueKey: ValueKey('shift-history-transactions-${entry.id}'),
          ),
        ],
        // Silent where the two figures agree, because the badge has already
        // said so and a difference of nothing is not a difference.
        if (variance != null && variance != 0)
          RecordAttribute(
            label: 'Cash difference',
            value: _money(variance.abs()),
            valueKey: ValueKey('shift-history-variance-${entry.id}'),
          ),
        // Said to everyone who can read the shift, whether or not they may read
        // the trail behind it: the recorded sales beside it are the corrected
        // figure, and no other line here discloses that.
        if (entry.amendment case final amendment?)
          RecordAttribute(
            label: 'Corrections',
            value: _amendedLabel(amendment),
            valueKey: ValueKey('shift-history-amended-${entry.id}'),
            flex: 2,
          ),
      ],
      provenance: _closedLabel(entry),
      provenanceKey: ValueKey('shift-history-closed-${entry.id}'),
      actions: <RecordAction>[
        RecordAction(
          label: 'View sales',
          actionKey: ValueKey('shift-history-sales-link-${entry.id}'),
          onPressed: () => onViewSales(_salesRequest(entry)),
        ),
        if (entry.amendment != null && canReadCorrections)
          RecordAction(
            label: 'View this shift\'s corrections',
            actionKey: ValueKey('shift-history-corrections-link-${entry.id}'),
            onPressed: () => onViewCorrections(entry.id),
          ),
      ],
    );
  }

  String _staffLabel(TenantShiftHistoryEntry entry) =>
      tenantStaffLabel(entry.staffId, names: staffNames, selfUid: session.uid);

  /// Carries the already-validated shift identity into the sales page, so the
  /// sales route proves attribution against this exact shift without a second
  /// read of the shift document.
  TenantSaleHistoryRequest _salesRequest(TenantShiftHistoryEntry entry) =>
      TenantShiftSaleHistoryRequest(
        shift: TenantSaleShiftScope(
          shiftId: entry.id,
          staffId: entry.staffId,
          deviceId: entry.deviceId,
          businessDate: entry.businessDate,
        ),
        recordedTransactionCount: entry.summary?.transactionCount,
        recordedTotalSalesMinor: entry.summary?.totalSalesMinor,
        countedCashMinor: entry.closingCashMinor,
      );
}

/// What a server-side correction did to the recorded sales on this row.
///
/// **The guarantee this used to repeat is stated once on the page now.** It was
/// a paragraph on every corrected row saying that the correction rewrote the
/// recorded sales to the total that shift's own sales prove and never the
/// counted cash - which is a property of the correction path rather than of any
/// shift, and is true of every row that carries this attribute. §5.2's
/// attributes are key-value, so what stayed here is what differs between rows:
/// how many times, and when the last one was.
String _amendedLabel(ShiftSummaryAmendment amendment) {
  final times = amendment.count == 1 ? 'once' : '${amendment.count} times';
  final amendedAt = amendment.amendedAt;
  return amendedAt == null
      ? 'Corrected $times; the time of the last correction was not recorded'
      : 'Corrected $times, last ${_instant(amendedAt)}';
}

/// The difference between two recorded figures, named rather than recomputed.
String _varianceLabel(int varianceMinor) {
  if (varianceMinor == 0) return 'Counted cash matches recorded sales.';
  return varianceMinor > 0
      ? 'Counted cash is over by ${_money(varianceMinor)}.'
      : 'Counted cash is short by ${_money(-varianceMinor)}.';
}

String _closedLabel(TenantShiftHistoryEntry entry) {
  final endedAt = entry.endedAt;
  return endedAt == null
      ? 'The close time has not been confirmed yet.'
      : 'Closed ${_instant(endedAt)}';
}

String _money(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);

String _instant(DateTime value) {
  final utc = value.toUtc();
  String pad(int part) => part.toString().padLeft(2, '0');
  return '${utc.year}-${pad(utc.month)}-${pad(utc.day)} '
      '${pad(utc.hour)}:${pad(utc.minute)} UTC';
}
