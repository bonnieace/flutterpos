import 'package:flutter/material.dart';

import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session_controller.dart';
import 'reconciliation_anomalies.dart';

/// Opens the list under the caller's own session scope, so a tenant switch
/// invalidates it exactly as it does every other guarded route rather than
/// leaving a detached screen behind.
///
/// It needs no injected route builder: both this and the run list that points
/// at it belong to the reporting domain, so nothing crosses a domain boundary.
void openTenantReconciliationAnomalies(
  BuildContext context, {
  required TenantDataReader reader,
  TenantReconciliationAnomalyKind? kind,
}) {
  final controller = TenantSessionScope.of(context);
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TenantSessionScope(
        controller: controller,
        child: TenantReconciliationAnomalyScreen(reader: reader, kind: kind),
      ),
    ),
  );
}

/// Route listing the differences reconciliation found and could not resolve.
///
/// The runs page reports how many stock and shift differences a run found. This
/// says which ones, which is the only thing that makes a count actionable.
final class TenantReconciliationAnomalyScreen extends StatelessWidget {
  const TenantReconciliationAnomalyScreen({
    super.key,
    required this.reader,
    this.kind,
  });

  final TenantDataReader reader;

  /// Opens the list already narrowed to one kind.
  final TenantReconciliationAnomalyKind? kind;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Unresolved differences')),
    body: TenantReconciliationAnomalyPanel(reader: reader, kind: kind),
  );
}

/// Shows one bounded page of recorded differences, optionally narrowed to one
/// kind.
///
/// The route guard owns authorization and stale-session rejection: a tenant
/// switch during an outstanding page discards it before it can update the UI.
final class TenantReconciliationAnomalyPanel extends StatefulWidget {
  const TenantReconciliationAnomalyPanel({
    super.key,
    required this.reader,
    this.kind,
    this.pageSize = 20,
  });

  final TenantDataReader reader;
  final TenantReconciliationAnomalyKind? kind;
  final int pageSize;

  @override
  State<TenantReconciliationAnomalyPanel> createState() =>
      _TenantReconciliationAnomalyPanelState();
}

final class _TenantReconciliationAnomalyPanelState
    extends State<TenantReconciliationAnomalyPanel> {
  List<String?> _cursors = <String?>[null];
  int _pageIndex = 0;
  TenantReconciliationAnomalyKind? _kind;
  String? _loaderKey;
  TenantGuardedLoader<TenantReconciliationAnomalyPage>? _loader;

  @override
  void initState() {
    super.initState();
    _kind = widget.kind;
  }

  @override
  void didUpdateWidget(covariant TenantReconciliationAnomalyPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind) _narrow(widget.kind);
  }

  /// A cursor is a position inside one exact query, so changing the filter
  /// starts the list again rather than resuming from somewhere the new query
  /// never established.
  void _narrow(TenantReconciliationAnomalyKind? kind) {
    setState(() {
      _kind = kind;
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
  TenantGuardedLoader<TenantReconciliationAnomalyPage> _loaderFor(String key) {
    if (key == _loaderKey && _loader != null) return _loader!;
    _loaderKey = key;
    final cursor = _cursors[_pageIndex];
    final kind = _kind;
    return _loader = (session) =>
        TenantReconciliationAnomalyRepository(
          session: session,
          reader: widget.reader,
        ).loadPage(kind: kind, pageSize: widget.pageSize, cursor: cursor);
  }

  @override
  Widget build(BuildContext context) {
    final cursor = _cursors[_pageIndex];
    final guardKey = '${_kind?.wireValue}:$_pageIndex:$cursor';
    return TenantRouteGuard<TenantReconciliationAnomalyPage>(
      key: ValueKey(guardKey),
      allowedRoles: TenantReconciliationAnomalyRepository.allowedRoles,
      load: _loaderFor(guardKey),
      denied: const Center(
        key: ValueKey('reconciliation-anomalies-denied'),
        child: Text(
          'Unresolved differences are available to managers and owners.',
        ),
      ),
      failure: (context, error) => const Center(
        key: ValueKey('reconciliation-anomalies-failure'),
        child: Text('The unresolved differences could not be loaded.'),
      ),
      builder: (context, session, page) => _AnomalyContents(
        page: page,
        selected: _kind,
        pageIndex: _pageIndex,
        onNarrow: _narrow,
        onNextPage: () => _nextPage(page.nextCursor),
        onPreviousPage: _previousPage,
      ),
    );
  }
}

final class _AnomalyContents extends StatelessWidget {
  const _AnomalyContents({
    required this.page,
    required this.selected,
    required this.pageIndex,
    required this.onNarrow,
    required this.onNextPage,
    required this.onPreviousPage,
  });

  final TenantReconciliationAnomalyPage page;
  final TenantReconciliationAnomalyKind? selected;
  final int pageIndex;
  final ValueChanged<TenantReconciliationAnomalyKind?> onNarrow;
  final VoidCallback onNextPage;
  final VoidCallback onPreviousPage;

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('reconciliation-anomalies'),
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Unresolved differences',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 4),
      const Text(
        key: ValueKey('reconciliation-anomalies-scope'),
        'These are the differences the server found and could not resolve on '
        'its own. They belong to a product, a shift, or a sale rather than to '
        'one business day, so this list covers the whole business and is not '
        'narrowed to the day you came from.',
      ),
      const SizedBox(height: 4),
      const Text(
        'Nothing here changed stock, a shift, or a sale, and nothing on this '
        'page can. Correct a stock figure from the product it belongs to.',
      ),
      const SizedBox(height: 16),
      _KindChips(selected: selected, onNarrow: onNarrow),
      const SizedBox(height: 16),
      if (page.items.isEmpty)
        Text(
          key: const ValueKey('reconciliation-anomalies-empty'),
          selected == null
              ? 'The server has recorded no unresolved differences for this '
                    'business.'
              : 'No unresolved difference of this kind has been recorded.',
        )
      else
        for (final anomaly in page.items) _anomaly(context, anomaly),
      const SizedBox(height: 8),
      Text(
        'This list is not in time order: a record is addressed by what it is '
        'about, not by when it was found. Each one states its own instants.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        children: [
          if (pageIndex > 0)
            OutlinedButton(
              key: const ValueKey('reconciliation-anomalies-previous'),
              onPressed: onPreviousPage,
              child: const Text('Previous page'),
            ),
          if (page.hasMore)
            FilledButton(
              key: const ValueKey('reconciliation-anomalies-next'),
              onPressed: onNextPage,
              child: const Text('Next page'),
            ),
        ],
      ),
    ],
  );

  Widget _anomaly(BuildContext context, TenantReconciliationAnomaly anomaly) =>
      Card(
        key: ValueKey('reconciliation-anomaly-${anomaly.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                key: ValueKey('reconciliation-anomaly-kind-${anomaly.id}'),
                anomaly.kind == TenantReconciliationAnomalyKind.other
                    ? 'Unrecognised difference: ${anomaly.kindValue}'
                    : anomaly.kind.label,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                key: ValueKey('reconciliation-anomaly-subject-${anomaly.id}'),
                _subject(anomaly),
              ),
              if (_detail(anomaly) case final detail?)
                Text(
                  key: ValueKey('reconciliation-anomaly-detail-${anomaly.id}'),
                  detail,
                ),
              const SizedBox(height: 4),
              Text(
                key: ValueKey('reconciliation-anomaly-instants-${anomaly.id}'),
                _instants(anomaly),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
}

/// What the difference is about. The identity is the ID the rest of the app
/// attributes by, so it is always shown rather than resolved to a name.
String _subject(TenantReconciliationAnomaly anomaly) {
  if (anomaly.productId case final productId?) return 'Product $productId';
  if (anomaly.shiftId case final shiftId?) return 'Shift $shiftId';
  if (anomaly.saleId case final saleId?) return 'Sale $saleId';
  return 'This business';
}

/// The figures the record itself carries, stated and never recomputed.
String? _detail(TenantReconciliationAnomaly anomaly) {
  if (anomaly.invalidLineCount case final count?) {
    return '$count sale ${count == 1 ? 'line' : 'lines'} could not be read, so '
        'they moved no stock.';
  }
  if (anomaly.isStockAnomaly) {
    final variance = anomaly.quantityVariance!;
    final direction = variance > 0 ? 'more' : 'fewer';
    return 'Its ledger expects ${anomaly.expectedQuantity}, and the product '
        'records ${anomaly.observedQuantity}: ${variance.abs()} $direction '
        'than the ledger accounts for.';
  }
  if (anomaly.kind == TenantReconciliationAnomalyKind.invalidOrMissingShift) {
    return 'The shift is missing, or did not record the totals a comparison '
        'needs, so no difference could be measured.';
  }
  if (anomaly.kind == TenantReconciliationAnomalyKind.shiftVariance) {
    return 'Its sales total ${_signed(anomaly.salesVariance!)} and its '
        'transaction count ${_signed(anomaly.transactionVariance!)} against '
        'the sales recorded during it.';
  }
  return null;
}

String _signed(num value) {
  if (value == 0) return 'agrees';
  return value > 0 ? 'is $value over' : 'is ${value.abs()} short';
}

String _instants(TenantReconciliationAnomaly anomaly) {
  final parts = <String>[
    if (anomaly.recordedAt case final at?) 'First recorded ${_time(at)}',
    if (anomaly.updatedAt case final at?) 'last seen ${_time(at)}',
    if (anomaly.jobId case final jobId?) 'found by run $jobId',
  ];
  // A record with no recorded time still proves the difference was found, so it
  // is named as such rather than hidden.
  if (parts.isEmpty) return 'No time was recorded for this difference.';
  return '${parts.join(', ')}.';
}

String _time(DateTime value) => value.toIso8601String();

/// One chip per kind this client models, plus every kind.
///
/// `other` is deliberately absent: it names every kind this build does not
/// model, so it identifies no stored value and cannot be asked for. Those
/// records still appear in the unnarrowed list.
final class _KindChips extends StatelessWidget {
  const _KindChips({required this.selected, required this.onNarrow});

  final TenantReconciliationAnomalyKind? selected;
  final ValueChanged<TenantReconciliationAnomalyKind?> onNarrow;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      ChoiceChip(
        key: const ValueKey('reconciliation-anomaly-kind-all'),
        label: const Text('Every kind'),
        selected: selected == null,
        onSelected: (_) => onNarrow(null),
      ),
      for (final kind in TenantReconciliationAnomalyKind.values)
        if (kind != TenantReconciliationAnomalyKind.other)
          ChoiceChip(
            key: ValueKey('reconciliation-anomaly-kind-${kind.wireValue}'),
            label: Text(kind.label),
            selected: selected == kind,
            onSelected: (_) => onNarrow(kind),
          ),
    ],
  );
}
