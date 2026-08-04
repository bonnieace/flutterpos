import 'package:flutter/material.dart';

import '../reporting/reconciliation_anomalies.dart';
import '../tenancy/tenant_catalog.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../tenancy/tenant_staff_names.dart';
import 'stock_actions.dart';
import 'stock_adjustment.dart';
import 'stock_adjustment_feed_panel.dart';
import 'stock_movements.dart';

/// Read-and-correct stock route for one product in the selected tenant.
final class TenantProductStockScreen extends StatelessWidget {
  const TenantProductStockScreen({
    super.key,
    required this.reader,
    required this.product,
    this.actions,
  });

  final TenantDataReader reader;

  /// The already-decoded catalog record this route was opened for. Only its ID
  /// is used to read: the quantity shown is always re-read canonically.
  final TenantProduct product;

  final TenantStockActions? actions;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(product.name)),
    body: TenantProductStockPanel(
      reader: reader,
      product: product,
      actions: actions,
    ),
  );
}

/// How many of a product's recorded differences this route reads.
///
/// Reconciliation writes one record per run that found a difference and never
/// deletes an old one, so a long-neglected product can hold many. This is a
/// summary beside a stock figure rather than a list to page through, so it is
/// deliberately small and says when there are more.
const int _productDifferencePageSize = 5;

/// What this route could learn about the differences listed against a product.
///
/// A separate outcome from the stock read on purpose. The recorded quantity and
/// the ledger are what this route exists for, so a reconciliation read that fails
/// or is refused is carried here as a value and reported in place, rather than
/// thrown into the route guard's failure state where it would take the stock
/// figure off the screen with it. The same degrade-rather-than-fail rule the
/// staff-name resolver beside it already follows.
final class _ProductDifferences {
  const _ProductDifferences.listed({
    required this.items,
    required this.hasMore,
  }) : readable = true;

  const _ProductDifferences.unreadable()
    : items = const <TenantReconciliationAnomaly>[],
      hasMore = false,
      readable = false;

  final List<TenantReconciliationAnomaly> items;

  /// Whether more are recorded against this product than were read.
  final bool hasMore;

  /// False only when the read failed or this session may not make it. An empty
  /// readable answer and an unreadable one say very different things, and the
  /// surface must never present the second as the first.
  final bool readable;
}

/// One guarded view of a product's recorded stock and its ledger page.
final class _StockView {
  const _StockView({
    required this.stock,
    required this.names,
    required this.differences,
  });

  final TenantProductStockView stock;
  final Map<String, String> names;
  final _ProductDifferences differences;
}

/// Shows one product's recorded stock, pages its server-written ledger, and
/// records a management-only adjustment behind [TenantRouteGuard].
///
/// The guard owns authorization and stale-session rejection: a tenant switch
/// during an outstanding page or call discards it before it can update the UI.
final class TenantProductStockPanel extends StatefulWidget {
  const TenantProductStockPanel({
    super.key,
    required this.reader,
    required this.product,
    this.actions,
    this.pageSize = 20,
    this.requestIdFactory,
  });

  final TenantDataReader reader;
  final TenantProduct product;
  final TenantStockActions? actions;
  final int pageSize;

  /// One fresh request ID per confirmation intent.
  final String Function()? requestIdFactory;

  @override
  State<TenantProductStockPanel> createState() =>
      _TenantProductStockPanelState();
}

final class _TenantProductStockPanelState
    extends State<TenantProductStockPanel> {
  List<String?> _cursors = <String?>[null];
  int _pageIndex = 0;
  int _generation = 0;
  bool _busy = false;
  String? _notice;

  /// Retained only across an ambiguous attempt, so a retry addresses the same
  /// idempotency record instead of moving the same stock twice.
  String? _requestId;
  TenantStaffNameResolver? _staffNames;
  String? _staffNamesSessionKey;

  /// One resolver per session, so its cache can never label another session's
  /// rows. An unresolved name degrades to the authoritative UID.
  TenantStaffNameResolver _resolverFor(TenantSession session) {
    final key = _sessionKey(session);
    if (key != _staffNamesSessionKey || _staffNames == null) {
      _staffNamesSessionKey = key;
      _staffNames = TenantStaffNameResolver(
        session: session,
        reader: widget.reader,
      );
    }
    return _staffNames!;
  }

  static String _sessionKey(TenantSession session) =>
      '${session.uid}:${session.tenantId}:${session.epoch}';

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

  /// Restarts the guarded load from the first page.
  void _reload() {
    setState(() {
      _cursors = <String?>[null];
      _pageIndex = 0;
      _generation++;
    });
  }

  /// Whether the session this work was authorized against is still selected.
  bool _stillCurrent(String capturedKey) {
    if (!mounted) return false;
    final current = TenantSessionScope.of(context).session;
    return current != null && _sessionKey(current) == capturedKey;
  }

  /// One loader per guard key; a closure rebuilt every frame would reload on
  /// every `setState` and discard the half-filled adjustment form.
  TenantGuardedLoader<_StockView> _loaderFor(String key) {
    if (key == _loaderKey && _loader != null) return _loader!;
    _loaderKey = key;
    final productId = widget.product.id;
    final cursor = _cursors[_pageIndex];
    return _loader = (session) async {
      final stock =
          await TenantProductStockRepository(
            session: session,
            reader: widget.reader,
          ).loadStock(
            productId: productId,
            pageSize: widget.pageSize,
            cursor: cursor,
          );
      return _StockView(
        stock: stock,
        names: await _resolverFor(session).resolve(
          stock.movements.items
              .map((movement) => movement.actorUid)
              .whereType<String>(),
        ),
        differences: await _readDifferences(session, productId),
      );
    };
  }

  /// Reads what reconciliation recorded against this product, and never fails
  /// the page.
  ///
  /// The repository refuses a session it does not admit, and that refusal is
  /// reported here rather than thrown: this route's own guard already decides who
  /// may see a product's stock, and a difference nobody can read is not a reason
  /// to hide the quantity somebody is accountable for.
  Future<_ProductDifferences> _readDifferences(
    TenantSession session,
    String productId,
  ) async {
    try {
      final page = await TenantReconciliationAnomalyRepository(
        session: session,
        reader: widget.reader,
      ).loadProductPage(
        productId: productId,
        pageSize: _productDifferencePageSize,
      );
      return _ProductDifferences.listed(
        items: page.items,
        hasMore: page.hasMore,
      );
    } catch (_) {
      return const _ProductDifferences.unreadable();
    }
  }

  String? _loaderKey;
  TenantGuardedLoader<_StockView>? _loader;

  /// Adjusts this product's stock through the session- and product-bound
  /// gateway, then re-reads so what is shown is the server's own figure rather
  /// than an optimistic local one.
  Future<void> _adjust(
    TenantSession session,
    TenantProduct product,
    TenantStockAdjustmentType type,
    int quantityDelta,
    String reason,
  ) async {
    final callable = widget.actions?.adjustCallable;
    if (callable == null || _busy) return;
    final capturedKey = _sessionKey(session);
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final gateway = TenantStockAdjustmentGateway(
        session: session,
        product: product,
        callable: callable,
        requestIdFactory: () => _requestId ??=
            (widget.requestIdFactory ?? secureStockAdjustmentRequestId)(),
      );
      final result = await gateway.submit(
        gateway.createIntent(
          type: type,
          quantityDelta: quantityDelta,
          reason: reason,
        ),
      );
      if (!_stillCurrent(capturedKey)) return;
      _requestId = null;
      setState(
        () => _notice =
            'Stock changed from ${result.previousQuantity} to '
            '${result.quantity}.',
      );
      _reload();
    } on TenantStockAdjustmentException catch (error) {
      if (!_stillCurrent(capturedKey)) return;
      // Only an unknown outcome may have moved stock, so only it keeps the
      // request ID. Every other refusal left nothing behind, and reusing its ID
      // would make an edited retry fail as a duplicate.
      if (!error.mayHaveCommitted) _requestId = null;
      setState(() => _notice = _adjustmentNotice(error.failure));
      if (error.mayHaveCommitted) _reload();
    } on FormatException {
      if (!_stillCurrent(capturedKey)) return;
      // The call may well have moved stock; only its answer was unusable.
      setState(
        () => _notice =
            'The adjustment response could not be trusted. Reload this page to '
            'see what the server recorded.',
      );
      _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cursor = _cursors[_pageIndex];
    final guardKey = '${widget.product.id}:$_generation:$_pageIndex:$cursor';
    return TenantRouteGuard<_StockView>(
      key: ValueKey(guardKey),
      allowedRoles: TenantProductStockRepository.allowedRoles,
      load: _loaderFor(guardKey),
      denied: const Center(
        key: ValueKey('product-stock-denied'),
        child: Text('Stock is unavailable for this business.'),
      ),
      failure: (context, error) => const Center(
        key: ValueKey('product-stock-failure'),
        child: Text('This product\'s stock could not be loaded.'),
      ),
      builder: (context, session, view) => _ProductStockContents(
        view: view,
        selfUid: session.uid,
        pageIndex: _pageIndex,
        busy: _busy,
        notice: _notice,
        // The same domain owns both surfaces, so this route needs no injection
        // from the composition root; it opens under this route's own scope.
        onOpenAdjustments: () => openTenantStockAdjustmentFeed(
          context,
          reader: widget.reader,
          product: view.stock.product,
        ),
        canAdjust:
            widget.actions?.adjustCallable != null &&
            TenantStockAdjustmentGateway.canAdjustInSession(session),
        onNextPage: () => _nextPage(view.stock.movements.nextCursor),
        onPreviousPage: _previousPage,
        onAdjust: (type, quantityDelta, reason) =>
            _adjust(session, view.stock.product, type, quantityDelta, reason),
      ),
    );
  }
}

/// The figures a recorded difference carries, stated and never recomputed.
///
/// Only one of the four kinds a product can hold is a quantity disagreement an
/// adjustment resolves. The other three say the comparison itself could not be
/// trusted, and each says so rather than inviting a correction that would not
/// resolve it.
String _differenceDetail(TenantReconciliationAnomaly anomaly) {
  switch (anomaly.kind) {
    case TenantReconciliationAnomalyKind.stockVariance:
      // The same sentence the differences list uses for this record, so the two
      // surfaces describe one figure the same way.
      final variance = anomaly.quantityVariance!;
      final direction = variance > 0 ? 'more' : 'fewer';
      return 'Its ledger expects ${anomaly.expectedQuantity}, and the product '
          'records ${anomaly.observedQuantity}: ${variance.abs()} $direction '
          'than the ledger accounts for. An adjustment recorded below is how '
          'this is put right.';
    case TenantReconciliationAnomalyKind.invalidStockMovement:
      return 'A movement in the ledger below could not be read, so the expected '
          'quantity of ${anomaly.expectedQuantity} does not account for '
          'everything that moved. An adjustment will not resolve this: the '
          'ledger entry is what needs looking at.';
    case TenantReconciliationAnomalyKind.checkpointChainInvalid:
      return 'The tamper-evident chain of checks behind this product does not '
          'join up, so the expected quantity of ${anomaly.expectedQuantity} '
          'cannot be trusted as a starting point. This is not a quantity '
          'disagreement and an adjustment will not resolve it.';
    case TenantReconciliationAnomalyKind.invalidProductQuantity:
      return 'This product\'s recorded quantity could not be read as a whole '
          'number, so its stock was not verified at all. Nothing can be added '
          'to it until that is repaired.';
    case TenantReconciliationAnomalyKind.invalidSaleLines:
    case TenantReconciliationAnomalyKind.invalidOrMissingShift:
    case TenantReconciliationAnomalyKind.shiftVariance:
    case TenantReconciliationAnomalyKind.other:
      // Reachable only for a kind this build does not model, or one a server
      // started filing against a product. Naming it plainly beats hiding a real
      // difference, and beats describing it as something it may not be.
      return 'The server recorded this against this product. What it means is '
          'not something this version of the app can explain.';
  }
}

String _foundLabel(TenantReconciliationAnomaly anomaly) {
  final parts = <String>[
    if (anomaly.jobId case final jobId?) 'Found by run $jobId',
    if (anomaly.recordedAt case final at?) 'first recorded ${_time(at)}',
    if (anomaly.updatedAt case final at?) 'last seen ${_time(at)}',
  ];
  if (parts.isEmpty) return 'No run or time was recorded for this difference.';
  return '${parts.join(', ')}.';
}

String _time(DateTime value) => value.toIso8601String();

String _adjustmentNotice(TenantStockAdjustmentFailure failure) =>
    switch (failure) {
      TenantStockAdjustmentFailure.forbidden =>
        'Only an owner, administrator, or manager may adjust stock.',
      TenantStockAdjustmentFailure.productMissing =>
        'This product no longer exists in this business, so nothing changed.',
      TenantStockAdjustmentFailure.refusedDirection =>
        'That adjustment type cannot move stock in that direction. Nothing '
            'changed.',
      TenantStockAdjustmentFailure.invalidQuantity =>
        'Enter a whole number of units between 1 and '
            '$maximumStockAdjustmentQuantityDelta.',
      TenantStockAdjustmentFailure.invalidReason =>
        'Record a reason of at least $minimumStockAdjustmentReasonLength '
            'characters for this adjustment.',
      TenantStockAdjustmentFailure.duplicateRequest =>
        'An earlier attempt already used this correction. Nothing changed a '
            'second time; start a new adjustment.',
      TenantStockAdjustmentFailure.outOfRange =>
        'The resulting quantity would be too large to record. Nothing changed.',
      TenantStockAdjustmentFailure.invalidStoredQuantity =>
        'This product\'s recorded quantity is not a whole number, so nothing '
            'can be added to it. It needs reconciliation.',
      TenantStockAdjustmentFailure.refused =>
        'The adjustment was refused and no stock changed.',
      TenantStockAdjustmentFailure.ambiguous =>
        'The result is unknown. This page has been reloaded; check the stock '
            'and the ledger below before trying again.',
    };

final class _ProductStockContents extends StatelessWidget {
  const _ProductStockContents({
    required this.view,
    required this.selfUid,
    required this.pageIndex,
    required this.busy,
    required this.notice,
    required this.canAdjust,
    required this.onNextPage,
    required this.onPreviousPage,
    required this.onOpenAdjustments,
    required this.onAdjust,
  });

  final _StockView view;
  final String selfUid;
  final int pageIndex;
  final bool busy;
  final String? notice;
  final bool canAdjust;
  final VoidCallback onNextPage;
  final VoidCallback onPreviousPage;

  /// Opens the manual-correction feed narrowed to this product.
  final VoidCallback onOpenAdjustments;

  final void Function(
    TenantStockAdjustmentType type,
    int quantityDelta,
    String reason,
  )
  onAdjust;

  TenantProduct get product => view.stock.product;
  TenantStockMovementPage get page => view.stock.movements;
  _ProductDifferences get differences => view.differences;

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('product-stock'),
    padding: const EdgeInsets.all(20),
    children: [
      Text(product.name, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 4),
      Text('SKU ${product.sku}'),
      const SizedBox(height: 12),
      Text(
        key: const ValueKey('product-stock-quantity'),
        'Recorded stock: ${product.quantity}',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 4),
      const Text(
        'This is the quantity the server holds, not a figure derived on this '
        'device. Stock may legitimately be negative: a sale is never blocked '
        'by a stock count, so a product can be sold past zero and corrected '
        'here afterwards.',
      ),
      if (notice case final message?) ...[
        const SizedBox(height: 12),
        Text(key: const ValueKey('product-stock-notice'), message),
      ],
      ..._differencesSection(context),
      const SizedBox(height: 24),
      Text('Stock ledger', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      const Text(
        'Every sale, verified return, and manual adjustment the server '
        'recorded for this product. It is listed by record ID, which is not '
        'time order; each entry states when it was recorded.',
      ),
      const SizedBox(height: 12),
      if (page.items.isEmpty)
        const Text(
          key: ValueKey('product-stock-empty'),
          'No stock movements have been recorded for this product.',
        )
      else
        for (final movement in page.items) _entry(context, movement),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        children: [
          if (pageIndex > 0)
            OutlinedButton(
              key: const ValueKey('product-stock-previous'),
              onPressed: onPreviousPage,
              child: const Text('Previous page'),
            ),
          if (page.hasMore)
            FilledButton(
              key: const ValueKey('product-stock-next'),
              onPressed: onNextPage,
              child: const Text('Next page'),
            ),
          // The ledger explains every movement; this narrows the business-wide
          // correction record to the manual ones recorded against this product.
          OutlinedButton.icon(
            key: const ValueKey('product-stock-adjustments'),
            onPressed: onOpenAdjustments,
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Manual adjustments'),
          ),
        ],
      ),
      if (canAdjust) ...[
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 12),
        _AdjustStockForm(
          key: const ValueKey('product-stock-form'),
          quantity: product.quantity,
          busy: busy,
          onAdjust: onAdjust,
        ),
      ],
    ],
  );

  /// What reconciliation recorded against this product, said where the person
  /// who can act on it is already standing.
  ///
  /// Nothing at all is shown for a product with no recorded difference: this
  /// section is an exception report, and a permanent "no differences" line on
  /// every product would make the one that matters easier to miss rather than
  /// harder.
  List<Widget> _differencesSection(BuildContext context) {
    if (!differences.readable) {
      return <Widget>[
        const SizedBox(height: 12),
        Text(
          key: const ValueKey('product-stock-differences-unreadable'),
          'Whether reconciliation recorded a difference for this product could '
          'not be read. The stock and ledger below are unaffected.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ];
    }
    if (differences.items.isEmpty) return const <Widget>[];
    return <Widget>[
      const SizedBox(height: 24),
      Text(
        'Reconciliation found',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 4),
      const Text(
        key: ValueKey('product-stock-differences-scope'),
        // The distinction that keeps this honest. A shift correction deletes the
        // difference it resolved; nothing deletes one of these, so an old record
        // may already have been dealt with and this list cannot tell you which.
        'A record is kept for each run that found a difference here, and none is '
        'ever removed: a later run that agrees simply records nothing new. So an '
        'older entry may already have been put right. Each one names the run '
        'that found it.',
      ),
      if (differences.hasMore)
        Text(
          key: const ValueKey('product-stock-differences-truncated'),
          'More are recorded against this product than are shown here, and this '
          'is not a list in time order, so these are not the most recent ones.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      const SizedBox(height: 12),
      for (final anomaly in differences.items) _difference(context, anomaly),
    ];
  }

  Widget _difference(
    BuildContext context,
    TenantReconciliationAnomaly anomaly,
  ) => Card(
    key: ValueKey('product-stock-difference-${anomaly.id}'),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            key: ValueKey('product-stock-difference-kind-${anomaly.id}'),
            anomaly.kind == TenantReconciliationAnomalyKind.other
                ? 'Unrecognised difference: ${anomaly.kindValue}'
                : anomaly.kind.label,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            key: ValueKey('product-stock-difference-detail-${anomaly.id}'),
            _differenceDetail(anomaly),
          ),
          const SizedBox(height: 4),
          Text(
            key: ValueKey('product-stock-difference-found-${anomaly.id}'),
            _foundLabel(anomaly),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );

  Widget _entry(BuildContext context, TenantStockMovement movement) => Card(
    key: ValueKey('product-stock-entry-${movement.id}'),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                movement.increasesStock
                    ? Icons.arrow_upward
                    : Icons.arrow_downward,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                key: ValueKey('product-stock-delta-${movement.id}'),
                '${movement.increasesStock ? '+' : ''}'
                '${movement.quantityDelta} • ${_sourceLabel(movement)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            key: ValueKey('product-stock-figures-${movement.id}'),
            movement.previousQuantity == null
                ? 'The recorded before and after quantities are not part of '
                      'this entry.'
                : '${movement.previousQuantity} to ${movement.quantityAfter}',
          ),
          if (movement.reason case final reason?)
            Text(
              key: ValueKey('product-stock-reason-${movement.id}'),
              'Reason: $reason',
            ),
          if (movement.sourceId case final sourceId?)
            Text(
              key: ValueKey('product-stock-source-${movement.id}'),
              'Source: $sourceId',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          Text(
            key: ValueKey('product-stock-recorded-${movement.id}'),
            _recordedLabel(movement, _actorLabel(movement)),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );

  String? _actorLabel(TenantStockMovement movement) {
    final actorUid = movement.actorUid;
    if (actorUid == null) return null;
    return tenantStaffLabel(actorUid, names: view.names, selfUid: selfUid);
  }
}

String _sourceLabel(TenantStockMovement movement) => switch (movement.source) {
  TenantStockMovementSource.sale => 'Sale',
  TenantStockMovementSource.verifiedReturn => 'Verified return',
  TenantStockMovementSource.manualAdjustment =>
    'Adjustment: ${movement.adjustmentType ?? 'unspecified'}',
  TenantStockMovementSource.other => movement.sourceType,
};

String _recordedLabel(TenantStockMovement movement, String? actorLabel) {
  final recordedAt = movement.recordedAt ?? movement.occurredAt;
  final when = recordedAt == null
      ? 'Recorded instant unavailable'
      : 'Recorded ${_instant(recordedAt)}';
  return actorLabel == null ? when : '$when by $actorLabel';
}

String _instant(DateTime value) {
  final utc = value.toUtc();
  String pad(int part) => part.toString().padLeft(2, '0');
  return '${utc.year}-${pad(utc.month)}-${pad(utc.day)} '
      '${pad(utc.hour)}:${pad(utc.minute)} UTC';
}

/// Chooses one typed adjustment and requires an explicit confirmation.
///
/// The direction offered is decided by the type, because the server binds them:
/// a restock can only add and damage can only remove. Offering a combination
/// the callable refuses would teach an operator nothing except that the app
/// guesses.
final class _AdjustStockForm extends StatefulWidget {
  const _AdjustStockForm({
    super.key,
    required this.quantity,
    required this.busy,
    required this.onAdjust,
  });

  final int quantity;
  final bool busy;
  final void Function(
    TenantStockAdjustmentType type,
    int quantityDelta,
    String reason,
  )
  onAdjust;

  @override
  State<_AdjustStockForm> createState() => _AdjustStockFormState();
}

final class _AdjustStockFormState extends State<_AdjustStockForm> {
  TenantStockAdjustmentType _type = TenantStockAdjustmentType.restock;
  bool _increase = true;
  final TextEditingController _units = TextEditingController();
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _units.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _changeType(TenantStockAdjustmentType? type) {
    if (type == null) return;
    setState(() {
      _type = type;
      // A type that only moves one way decides the direction itself.
      if (!type.allowsIncrease) _increase = false;
      if (!type.allowsDecrease) _increase = true;
    });
  }

  int? get _unitCount {
    final parsed = int.tryParse(_units.text.trim());
    if (parsed == null ||
        parsed < 1 ||
        parsed > maximumStockAdjustmentQuantityDelta) {
      return null;
    }
    return parsed;
  }

  int? get _quantityDelta {
    final units = _unitCount;
    return units == null ? null : (_increase ? units : -units);
  }

  bool get _canSubmit =>
      !widget.busy &&
      _quantityDelta != null &&
      normalizeStockAdjustmentReason(_reason.text) != null;

  Future<void> _confirm() async {
    final quantityDelta = _quantityDelta;
    if (quantityDelta == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Adjust this stock?'),
        content: Text(
          'This records a ${_type.wireValue} of '
          '${quantityDelta > 0 ? '+' : ''}$quantityDelta units. From the '
          'quantity recorded now, that is ${widget.quantity} to '
          '${widget.quantity + quantityDelta}. The server re-reads the '
          'product, so the final figure is whatever it holds at that moment. '
          'It cannot be undone from this app except by another adjustment.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('product-stock-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('product-stock-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Adjust stock'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    widget.onAdjust(_type, quantityDelta, _reason.text);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Adjust stock', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      const Text(
        'An adjustment is recorded permanently with its reason and cannot be '
        'deleted. Correcting a mistake means recording another adjustment.',
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<TenantStockAdjustmentType>(
        key: const ValueKey('product-stock-type'),
        initialValue: _type,
        decoration: const InputDecoration(labelText: 'Adjustment type'),
        items: [
          for (final type in TenantStockAdjustmentType.values)
            DropdownMenuItem<TenantStockAdjustmentType>(
              value: type,
              child: Text(type.label),
            ),
        ],
        onChanged: widget.busy ? null : _changeType,
      ),
      const SizedBox(height: 12),
      if (_type.direction == TenantStockAdjustmentDirection.either)
        SegmentedButton<bool>(
          key: const ValueKey('product-stock-direction'),
          segments: const [
            ButtonSegment<bool>(value: true, label: Text('Add stock')),
            ButtonSegment<bool>(value: false, label: Text('Remove stock')),
          ],
          selected: <bool>{_increase},
          onSelectionChanged: widget.busy
              ? null
              : (selection) => setState(() => _increase = selection.single),
        )
      else
        Text(
          key: const ValueKey('product-stock-fixed-direction'),
          _increase
              ? 'This type always adds stock.'
              : 'This type always removes stock.',
        ),
      const SizedBox(height: 12),
      TextField(
        key: const ValueKey('product-stock-units'),
        controller: _units,
        keyboardType: TextInputType.number,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(labelText: 'Units'),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const ValueKey('product-stock-reason'),
        controller: _reason,
        maxLength: maximumStockAdjustmentReasonLength,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'Reason for this adjustment',
        ),
      ),
      const SizedBox(height: 12),
      FilledButton(
        key: const ValueKey('product-stock-submit'),
        onPressed: _canSubmit ? _confirm : null,
        child: const Text('Adjust stock'),
      ),
    ],
  );
}
