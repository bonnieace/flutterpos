import 'package:flutter/material.dart';

import '../checkout/checkout_tender.dart';
import '../returns/return_history_panel.dart';
import '../returns/return_actions.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../tenancy/tenant_staff_names.dart';
import 'sale_history.dart';

/// What a sale page is scoped to.
sealed class TenantSaleHistoryRequest {
  const TenantSaleHistoryRequest();

  String get title;

  /// A stable identity for the guard key, so a new request restarts the load.
  String get key;
}

/// The sales recorded during one canonical shift.
final class TenantShiftSaleHistoryRequest extends TenantSaleHistoryRequest {
  const TenantShiftSaleHistoryRequest({
    required this.shift,
    required this.recordedTransactionCount,
    required this.recordedTotalSalesMinor,
    required this.countedCashMinor,
  });

  final TenantSaleShiftScope shift;

  /// The figures the closing device recorded. They are shown for inspection
  /// and never recalculated here: only reconciliation may contradict them.
  final int? recordedTransactionCount;
  final int? recordedTotalSalesMinor;
  final int countedCashMinor;

  @override
  String get title => 'Shift sales';

  @override
  String get key => 'shift:${shift.shiftId}';
}

/// This cashier's own most recent sales, for receipt lookup.
final class TenantOwnSaleHistoryRequest extends TenantSaleHistoryRequest {
  const TenantOwnSaleHistoryRequest();

  @override
  String get title => 'My recent sales';

  @override
  String get key => 'own';
}

/// Read-only sales route for the selected tenant session.
final class TenantSaleHistoryScreen extends StatelessWidget {
  const TenantSaleHistoryScreen({
    super.key,
    required this.reader,
    required this.request,
    this.returnActions,
  });

  final TenantDataReader reader;
  final TenantSaleHistoryRequest request;

  /// Passed through to the returns route. Recording stays unavailable while it
  /// is absent, and that route is read-only.
  final TenantReturnActions? returnActions;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(request.title)),
    body: TenantSaleHistoryPanel(
      reader: reader,
      request: request,
      returnActions: returnActions,
    ),
  );
}

/// Pages immutable sales behind [TenantRouteGuard].
final class TenantSaleHistoryPanel extends StatefulWidget {
  const TenantSaleHistoryPanel({
    super.key,
    required this.reader,
    required this.request,
    this.returnActions,
    this.pageSize = 20,
  });

  final TenantDataReader reader;
  final TenantSaleHistoryRequest request;

  /// Passed through to the returns route only. This surface never writes.
  final TenantReturnActions? returnActions;
  final int pageSize;

  @override
  State<TenantSaleHistoryPanel> createState() => _TenantSaleHistoryPanelState();
}

final class _TenantSaleHistoryPanelState extends State<TenantSaleHistoryPanel> {
  List<String?> _cursors = <String?>[null];
  int _pageIndex = 0;
  TenantStaffNameResolver? _staffNames;
  String? _staffNamesSessionKey;

  /// One resolver per session, so its cache can never label another session's
  /// rows. See [TenantStaffNameResolver] for why an unresolved name degrades
  /// to the UID instead of failing the page.
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
    final request = widget.request;
    return TenantRouteGuard<TenantNamedPage<TenantSalePage>>(
      key: ValueKey('${request.key}:$_pageIndex:$cursor'),
      load: (session) async {
        final repository = TenantSaleHistoryRepository(
          session: session,
          reader: widget.reader,
        );
        final page = await switch (request) {
          TenantShiftSaleHistoryRequest(:final shift) => repository
              .loadShiftSales(
                shift: shift,
                pageSize: widget.pageSize,
                cursor: cursor,
              ),
          TenantOwnSaleHistoryRequest() => repository.loadOwnRecentSales(
            pageSize: widget.pageSize,
            cursor: cursor,
          ),
        };
        return TenantNamedPage<TenantSalePage>(
          page: page,
          names: await _resolverFor(
            session,
          ).resolve(page.items.map((sale) => sale.soldById)),
        );
      },
      denied: const Center(
        key: ValueKey('sale-history-denied'),
        child: Text('Sales are unavailable for this business.'),
      ),
      failure: (context, error) => const Center(
        key: ValueKey('sale-history-failure'),
        child: Text('Sales could not be loaded.'),
      ),
      builder: (context, session, named) => _SaleHistoryContents(
        request: request,
        page: named.page,
        staffNames: named.names,
        selfUid: session.uid,
        pageIndex: _pageIndex,
        onNextPage: () => _nextPage(named.page.nextCursor),
        onPreviousPage: _previousPage,
        onViewReturns: (sale) => _openReturns(context, sale),
      ),
    );
  }

  /// Opens the read-only returns route under the same session scope, so its own
  /// guard sees the exact controller this page was authorized against.
  void _openReturns(BuildContext context, TenantSale sale) {
    final sessions = TenantSessionScope.read(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TenantSessionScope(
          controller: sessions,
          child: TenantSaleReturnsScreen(
            reader: widget.reader,
            request: TenantSaleReturnsRequest(sale: sale),
            actions: widget.returnActions,
          ),
        ),
      ),
    );
  }
}

final class _SaleHistoryContents extends StatelessWidget {
  const _SaleHistoryContents({
    required this.request,
    required this.page,
    required this.staffNames,
    required this.selfUid,
    required this.pageIndex,
    required this.onNextPage,
    required this.onPreviousPage,
    required this.onViewReturns,
  });

  final TenantSaleHistoryRequest request;
  final TenantSalePage page;
  final Map<String, String> staffNames;
  final String selfUid;
  final int pageIndex;
  final VoidCallback onNextPage;
  final VoidCallback onPreviousPage;
  final ValueChanged<TenantSale> onViewReturns;

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('sale-history'),
    padding: const EdgeInsets.all(20),
    children: [
      if (request case final TenantShiftSaleHistoryRequest shift) ...[
        Text(
          'Shift ${shift.shift.businessDate}',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          key: const ValueKey('sale-history-recorded'),
          _recordedLabel(shift),
        ),
        const SizedBox(height: 4),
        const Text(
          'These are the figures the shift recorded when it closed. Page '
          'through the sales to inspect them; this screen calculates no '
          'replacement total.',
        ),
      ] else
        Text(
          'Recent sales',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      const SizedBox(height: 16),
      if (page.items.isEmpty)
        const Text(
          key: ValueKey('sale-history-empty'),
          'No sales were found.',
        )
      else
        for (final sale in page.items)
          Card(
            key: ValueKey('sale-history-entry-${sale.id}'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sale.receiptNumber,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    key: ValueKey('sale-history-total-${sale.id}'),
                    'Total: ${sale.currency} ${_money(sale.totalMinor)}'
                    '${sale.discountMinor > 0 ? ' after ${_money(sale.discountMinor)} discount' : ''}',
                  ),
                  Text(
                    key: ValueKey('sale-history-lines-${sale.id}'),
                    '${sale.lines.length} '
                    '${sale.lines.length == 1 ? 'item' : 'items'}: '
                    '${sale.lines.map((line) => '${line.quantity} x ${line.name}').join(', ')}',
                  ),
                  Text(
                    key: ValueKey('sale-history-tender-${sale.id}'),
                    _tenderLabel(sale),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    key: ValueKey('sale-history-recorded-at-${sale.id}'),
                    _recordedAtLabel(
                      sale,
                      tenantStaffLabel(
                        sale.soldById,
                        names: staffNames,
                        selfUid: selfUid,
                      ),
                    ),
                    style: _muted(context),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      key: ValueKey('sale-history-returns-link-${sale.id}'),
                      onPressed: () => onViewReturns(sale),
                      child: const Text('View returns'),
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
              key: const ValueKey('sale-history-previous'),
              onPressed: onPreviousPage,
              child: const Text('Previous page'),
            ),
          if (page.hasMore)
            FilledButton(
              key: const ValueKey('sale-history-next'),
              onPressed: onNextPage,
              child: const Text('Next page'),
            ),
        ],
      ),
    ],
  );

  TextStyle? _muted(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall;
}

String _recordedLabel(TenantShiftSaleHistoryRequest request) {
  final count = request.recordedTransactionCount;
  final total = request.recordedTotalSalesMinor;
  if (count == null || total == null) {
    return 'This shift closed without a recorded summary. Counted cash was '
        '${_money(request.countedCashMinor)}.';
  }
  return 'Recorded: ${_money(total)} over $count transactions. Counted cash '
      'was ${_money(request.countedCashMinor)}.';
}

/// States how the sale was paid for without implying the payment was checked.
///
/// The disclaimer travels with the value on purpose: a bare "Paid by M-Pesa"
/// reads as a settled transaction, and nothing in this system has confirmed
/// that the money arrived.
String _tenderLabel(TenantSale sale) {
  final tender = sale.tender;
  return tender == null
      ? checkoutTenderUnrecordedMessage
      : 'Paid by ${tender.label}. $checkoutTenderDisclaimer';
}

String _recordedAtLabel(TenantSale sale, String soldByLabel) {
  final recordedAt = sale.recordedAt;
  return recordedAt == null
      ? 'The server has not confirmed this sale yet.'
      : 'Recorded ${_instant(recordedAt)} by $soldByLabel';
}

String _money(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);

String _instant(DateTime value) {
  final utc = value.toUtc();
  String pad(int part) => part.toString().padLeft(2, '0');
  return '${utc.year}-${pad(utc.month)}-${pad(utc.day)} '
      '${pad(utc.hour)}:${pad(utc.minute)} UTC';
}
