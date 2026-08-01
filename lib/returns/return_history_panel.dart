import 'package:flutter/material.dart';

import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_staff_names.dart';
import 'return_history.dart';

/// What one returns page is scoped to.
///
/// Only a sale-scoped page exists. A business-wide returns list would need its
/// own deliberate filter, index, and read decision; a descending page always
/// carries an equality filter, so there is no unfiltered scan to fall into.
final class TenantSaleReturnsRequest {
  const TenantSaleReturnsRequest({
    required this.saleId,
    required this.receiptNumber,
  });

  final String saleId;

  /// The receipt the sale itself proved. Shown so the page names the customer
  /// document being reversed, never re-derived here.
  final String receiptNumber;

  String get key => 'sale:$saleId';
}

/// Read-only returns route for the selected tenant session.
final class TenantSaleReturnsScreen extends StatelessWidget {
  const TenantSaleReturnsScreen({
    super.key,
    required this.reader,
    required this.request,
  });

  final TenantDataReader reader;
  final TenantSaleReturnsRequest request;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Returns')),
    body: TenantSaleReturnsPanel(reader: reader, request: request),
  );
}

/// Pages the returns recorded against one sale behind [TenantRouteGuard].
///
/// The guard owns authorization and stale-session rejection: a tenant switch
/// during an outstanding page discards it before it can be rendered. Nothing on
/// this surface can create, verify, or restore anything.
final class TenantSaleReturnsPanel extends StatefulWidget {
  const TenantSaleReturnsPanel({
    super.key,
    required this.reader,
    required this.request,
    this.pageSize = 20,
  });

  final TenantDataReader reader;
  final TenantSaleReturnsRequest request;
  final int pageSize;

  @override
  State<TenantSaleReturnsPanel> createState() => _TenantSaleReturnsPanelState();
}

final class _TenantSaleReturnsPanelState extends State<TenantSaleReturnsPanel> {
  List<String?> _cursors = <String?>[null];
  int _pageIndex = 0;
  TenantStaffNameResolver? _staffNames;
  String? _staffNamesSessionKey;

  /// One resolver per session, so its cache can never label another session's
  /// rows. An unresolved name degrades to the authoritative UID.
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
    return TenantRouteGuard<TenantNamedPage<TenantReturnPage>>(
      key: ValueKey('${request.key}:$_pageIndex:$cursor'),
      load: (session) async {
        final page = await TenantReturnHistoryRepository(
          session: session,
          reader: widget.reader,
        ).loadSaleReturns(
          saleId: request.saleId,
          pageSize: widget.pageSize,
          cursor: cursor,
        );
        return TenantNamedPage<TenantReturnPage>(
          page: page,
          names: await _resolverFor(session).resolve(
            page.items.expand(
              (record) => <String>[
                record.createdBy,
                if (record.verification case final verification?)
                  verification.verifiedBy,
              ],
            ),
          ),
        );
      },
      denied: const Center(
        key: ValueKey('sale-returns-denied'),
        child: Text('Returns are unavailable for this business.'),
      ),
      failure: (context, error) => const Center(
        key: ValueKey('sale-returns-failure'),
        child: Text('Returns could not be loaded.'),
      ),
      builder: (context, session, named) => _SaleReturnsContents(
        request: request,
        page: named.page,
        staffNames: named.names,
        selfUid: session.uid,
        pageIndex: _pageIndex,
        onNextPage: () => _nextPage(named.page.nextCursor),
        onPreviousPage: _previousPage,
      ),
    );
  }
}

final class _SaleReturnsContents extends StatelessWidget {
  const _SaleReturnsContents({
    required this.request,
    required this.page,
    required this.staffNames,
    required this.selfUid,
    required this.pageIndex,
    required this.onNextPage,
    required this.onPreviousPage,
  });

  final TenantSaleReturnsRequest request;
  final TenantReturnPage page;
  final Map<String, String> staffNames;
  final String selfUid;
  final int pageIndex;
  final VoidCallback onNextPage;
  final VoidCallback onPreviousPage;

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('sale-returns'),
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Returns against ${request.receiptNumber}',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 4),
      const Text(
        'Stock is restored only when a return is verified. A pending return '
        'has changed no stock yet.',
      ),
      const SizedBox(height: 16),
      if (page.items.isEmpty)
        const Text(
          key: ValueKey('sale-returns-empty'),
          'No returns were recorded against this sale.',
        )
      else ...[
        Text(
          key: const ValueKey('sale-returns-counts'),
          _countsLabel(page),
        ),
        const SizedBox(height: 12),
        for (final record in page.items)
          Card(
            key: ValueKey('sale-returns-entry-${record.id}'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        record.isVerified
                            ? Icons.verified_outlined
                            : Icons.hourglass_empty,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        key: ValueKey('sale-returns-status-${record.id}'),
                        record.isVerified
                            ? 'Verified - stock restored'
                            : 'Pending verification',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    key: ValueKey('sale-returns-lines-${record.id}'),
                    '${record.returnedUnits} '
                    '${record.returnedUnits == 1 ? 'unit' : 'units'} across '
                    '${record.lines.length} '
                    '${record.lines.length == 1 ? 'product' : 'products'}: '
                    '${record.lines.map(_lineLabel).join(', ')}',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    key: ValueKey('sale-returns-recorded-${record.id}'),
                    _recordedLabel(record, _label(record.createdBy)),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (record.verification case final verification?)
                    Text(
                      key: ValueKey('sale-returns-verified-${record.id}'),
                      'Verified ${_instant(verification.verifiedAt)} by '
                      '${_label(verification.verifiedBy)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ),
      ],
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        children: [
          if (pageIndex > 0)
            OutlinedButton(
              key: const ValueKey('sale-returns-previous'),
              onPressed: onPreviousPage,
              child: const Text('Previous page'),
            ),
          if (page.hasMore)
            FilledButton(
              key: const ValueKey('sale-returns-next'),
              onPressed: onNextPage,
              child: const Text('Next page'),
            ),
        ],
      ),
    ],
  );

  String _label(String uid) =>
      tenantStaffLabel(uid, names: staffNames, selfUid: selfUid);
}

/// Names the two states separately on the page a user is inspecting.
///
/// The counts describe this page only. They are not a total for the sale: a
/// later page may carry more, and a running total computed here would be a
/// second, weaker aggregate that disagrees with the server's.
String _countsLabel(TenantReturnPage page) {
  final verified = page.verified.length;
  final pending = page.pending.length;
  return 'On this page: $verified verified, $pending pending.';
}

String _lineLabel(TenantReturnLine line) =>
    '${line.quantity} x ${line.productName ?? line.productId}';

String _recordedLabel(TenantReturn record, String createdByLabel) {
  final recordedAt = record.recordedAt;
  return recordedAt == null
      ? 'Recorded by $createdByLabel; the server has not confirmed it yet.'
      : 'Recorded ${_instant(recordedAt)} by $createdByLabel';
}

String _instant(DateTime value) {
  final utc = value.toUtc();
  String pad(int part) => part.toString().padLeft(2, '0');
  return '${utc.year}-${pad(utc.month)}-${pad(utc.day)} '
      '${pad(utc.hour)}:${pad(utc.minute)} UTC';
}
