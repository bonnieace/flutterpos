import 'package:flutter/material.dart';

import '../sales/sale_history.dart';
import '../sales/sale_history_panel.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import 'shift_history.dart';

/// Read-only shift history route for the selected tenant session.
final class TenantShiftHistoryScreen extends StatelessWidget {
  const TenantShiftHistoryScreen({super.key, required this.reader});

  final TenantDataReader reader;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Shift history')),
    body: TenantShiftHistoryPanel(reader: reader),
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
    this.pageSize = 20,
  });

  final TenantDataReader reader;
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
    return TenantRouteGuard<TenantShiftHistoryPage>(
      // A new key restarts the guard for a new scope or page, so an earlier
      // page can never complete into the current one.
      key: ValueKey('${_scope.name}:$_pageIndex:$cursor'),
      load: (session) => TenantShiftHistoryRepository(
        session: session,
        reader: widget.reader,
      ).loadPage(scope: _scope, pageSize: widget.pageSize, cursor: cursor),
      denied: const Center(
        key: ValueKey('shift-history-denied'),
        child: Text('Shift history is unavailable for this business.'),
      ),
      failure: (context, error) => const Center(
        key: ValueKey('shift-history-failure'),
        child: Text('Shift history could not be loaded.'),
      ),
      builder: (context, session, page) => _ShiftHistoryContents(
        session: session,
        page: page,
        pageIndex: _pageIndex,
        onScopeChanged: _setScope,
        onNextPage: () => _nextPage(page.nextCursor),
        onPreviousPage: _previousPage,
        onViewSales: (request) => _openSales(context, request),
      ),
    );
  }

  /// Opens the read-only sales route under the same session scope, so its own
  /// guard sees the exact controller this page was authorized against.
  void _openSales(BuildContext context, TenantSaleHistoryRequest request) {
    final sessions = TenantSessionScope.read(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TenantSessionScope(
          controller: sessions,
          child: TenantSaleHistoryScreen(
            reader: widget.reader,
            request: request,
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
    required this.pageIndex,
    required this.onScopeChanged,
    required this.onNextPage,
    required this.onPreviousPage,
    required this.onViewSales,
  });

  final TenantSession session;
  final TenantShiftHistoryPage page;
  final int pageIndex;
  final ValueChanged<TenantShiftHistoryScope> onScopeChanged;
  final VoidCallback onNextPage;
  final VoidCallback onPreviousPage;
  final ValueChanged<TenantSaleHistoryRequest> onViewSales;

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('shift-history'),
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Closed shifts',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 4),
      const Text(
        'Counted cash and recorded sales are shown exactly as they were '
        'closed. Reconciliation resolves any difference.',
      ),
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
        child: OutlinedButton.icon(
          key: const ValueKey('shift-history-own-sales'),
          onPressed: () => onViewSales(const TenantOwnSaleHistoryRequest()),
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text('My recent sales'),
        ),
      ),
      const SizedBox(height: 16),
      if (page.items.isEmpty)
        const Text(
          key: ValueKey('shift-history-empty'),
          'No closed shifts were found.',
        )
      else
        for (final entry in page.items)
          Card(
            key: ValueKey('shift-history-entry-${entry.id}'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${entry.businessDate} - ${_staffLabel(entry)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    key: ValueKey('shift-history-counted-${entry.id}'),
                    'Counted cash: ${_money(entry.closingCashMinor)}',
                  ),
                  if (entry.summary case final summary?) ...[
                    Text(
                      key: ValueKey('shift-history-sales-${entry.id}'),
                      'Recorded sales: ${_money(summary.totalSalesMinor)} '
                      'over ${summary.transactionCount} transactions',
                    ),
                    Text(
                      key: ValueKey('shift-history-variance-${entry.id}'),
                      _varianceLabel(entry.cashVarianceMinor!),
                    ),
                  ] else
                    Text(
                      key: ValueKey('shift-history-no-summary-${entry.id}'),
                      'No closing summary was recorded for this shift.',
                    ),
                  const SizedBox(height: 8),
                  Text(_closedLabel(entry), style: _mutedStyle(context)),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      key: ValueKey('shift-history-sales-link-${entry.id}'),
                      onPressed: () => onViewSales(_salesRequest(entry)),
                      child: const Text('View sales'),
                    ),
                  ),
                ],
              ),
            ),
          ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        children: [
          if (pageIndex > 0)
            OutlinedButton(
              key: const ValueKey('shift-history-previous'),
              onPressed: onPreviousPage,
              child: const Text('Previous page'),
            ),
          if (page.hasMore)
            FilledButton(
              key: const ValueKey('shift-history-next'),
              onPressed: onNextPage,
              child: const Text('Next page'),
            ),
        ],
      ),
    ],
  );

  String _staffLabel(TenantShiftHistoryEntry entry) =>
      entry.staffId == session.uid ? 'You' : entry.staffId;

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

  TextStyle? _mutedStyle(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall;
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
