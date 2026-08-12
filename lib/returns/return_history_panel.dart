import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../ui/fields.dart';
import '../ui/scaffold.dart';
import '../sales/sale_history.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../tenancy/tenant_staff_names.dart';
import 'return_actions.dart';
import 'return_history.dart';
import 'return_request.dart';
import 'return_verification.dart';

/// What one returns page is scoped to.
///
/// Only a sale-scoped page exists. A business-wide returns list would need its
/// own deliberate filter, index, and read decision; a descending page always
/// carries an equality filter, so there is no unfiltered scan to fall into.
final class TenantSaleReturnsRequest {
  const TenantSaleReturnsRequest({required this.sale});

  /// The already-validated sale being reversed. It is carried from the sale
  /// page rather than re-read, so the returnable quantities are derived from
  /// the exact immutable document that was proved there.
  final TenantSale sale;

  String get saleId => sale.id;
  String get receiptNumber => sale.receiptNumber;
  String get key => 'sale:$saleId';
}

/// Read/record returns route for the selected tenant session.
final class TenantSaleReturnsScreen extends StatelessWidget {
  const TenantSaleReturnsScreen({
    super.key,
    required this.reader,
    required this.request,
    this.actions,
  });

  final TenantDataReader reader;
  final TenantSaleReturnsRequest request;

  /// Supplied by the composition root. Whatever is absent stays unavailable, so
  /// a route with no actions is exactly the read-only surface it was before.
  final TenantReturnActions? actions;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Returns',
    body: TenantSaleReturnsPanel(
      reader: reader,
      request: request,
      actions: actions,
    ),
  );
}

/// One guarded view of a sale's returns and what may still be returned.
final class _ReturnsView {
  const _ReturnsView({
    required this.page,
    required this.names,
    required this.returnable,
  });

  final TenantReturnPage page;
  final Map<String, String> names;

  /// Present only when this page is the complete set of returns for the sale.
  final TenantReturnableSale? returnable;
}

/// Pages the returns recorded against one sale behind [TenantRouteGuard], and
/// records a new pending one.
///
/// The guard owns authorization and stale-session rejection: a tenant switch
/// during an outstanding page or write discards it before it can update the UI.
/// Nothing here verifies a return or restores any stock.
final class TenantSaleReturnsPanel extends StatefulWidget {
  const TenantSaleReturnsPanel({
    super.key,
    required this.reader,
    required this.request,
    this.actions,
    this.pageSize = 20,
    this.requestIdFactory,
  });

  final TenantDataReader reader;
  final TenantSaleReturnsRequest request;
  final TenantReturnActions? actions;
  final int pageSize;

  /// One fresh request ID per confirmation or verification intent.
  final String Function()? requestIdFactory;

  @override
  State<TenantSaleReturnsPanel> createState() => _TenantSaleReturnsPanelState();
}

final class _TenantSaleReturnsPanelState extends State<TenantSaleReturnsPanel> {
  List<String?> _cursors = <String?>[null];
  int _pageIndex = 0;
  int _generation = 0;
  bool _busy = false;
  String? _notice;

  /// Retained only across an ambiguous attempt, so a retry addresses the same
  /// deterministic document instead of recording the reversal twice.
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

  Future<void> _record(
    TenantSession session,
    TenantReturnableSale returnable,
    Map<String, int> quantities,
    String reason,
  ) async {
    final writer = widget.actions?.writer;
    if (writer == null || _busy) return;
    final capturedKey = _sessionKey(session);
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final intent = TenantReturnRequestRepository(
        session: session,
        reader: widget.reader,
      ).buildCreateIntent(
        returnable: returnable,
        quantities: quantities,
        reason: reason,
        requestId: _requestId ??=
            (widget.requestIdFactory ?? secureTenantReturnRequestId)(),
      );
      final result = await writer.recordReturn(intent);
      if (!_stillCurrent(capturedKey)) return;
      // Only an ambiguous outcome may have landed, so only it keeps the
      // request ID. A rejected or unattempted write left nothing behind, and
      // reusing its ID would deny an edited retry as a duplicate.
      if (result.kind != TenantReturnWriteKind.ambiguous) _requestId = null;
      setState(() => _notice = _resultNotice(result));
      if (result.kind == TenantReturnWriteKind.committed) _reload();
    } on TenantReturnException catch (error) {
      if (!_stillCurrent(capturedKey)) return;
      _requestId = null;
      setState(() => _notice = _refusalNotice(error.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Whether the session this work was authorized against is still selected.
  bool _stillCurrent(String capturedKey) {
    if (!mounted) return false;
    final current = TenantSessionScope.of(context).session;
    return current != null && _sessionKey(current) == capturedKey;
  }

  /// One loader per guard key.
  ///
  /// [TenantRouteGuard] restarts whenever its loader changes identity, which is
  /// how a new loader is stopped from serving an old page. A closure rebuilt on
  /// every frame would therefore reload on every `setState` - discarding the
  /// half-filled record form each time the busy flag or a notice changed - so
  /// the loader is cached against the same key the guard is keyed by.
  TenantGuardedLoader<_ReturnsView> _loaderFor(String key) {
    if (key == _loaderKey && _loader != null) return _loader!;
    _loaderKey = key;
    final request = widget.request;
    final cursor = _cursors[_pageIndex];
    final pageIndex = _pageIndex;
    return _loader = (session) async {
      final page = await TenantReturnHistoryRepository(
        session: session,
        reader: widget.reader,
      ).loadSaleReturns(
        saleId: request.saleId,
        pageSize: widget.pageSize,
        cursor: cursor,
      );
      return _ReturnsView(
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
        // The remaining returnable quantity can only be derived from the
        // complete set of returns, which is exactly a first page with nothing
        // behind it.
        returnable: pageIndex == 0 && !page.hasMore
            ? TenantReturnRequestRepository(
                session: session,
                reader: widget.reader,
              ).describeReturnable(sale: request.sale, recorded: page)
            : null,
      );
    };
  }

  String? _loaderKey;
  TenantGuardedLoader<_ReturnsView>? _loader;

  @override
  Widget build(BuildContext context) {
    final cursor = _cursors[_pageIndex];
    final request = widget.request;
    final guardKey = '${request.key}:$_generation:$_pageIndex:$cursor';
    return TenantRouteGuard<_ReturnsView>(
      key: ValueKey(guardKey),
      load: _loaderFor(guardKey),
      denied: const Center(
        key: ValueKey('sale-returns-denied'),
        child: Text('Returns are unavailable for this business.'),
      ),
      failure: (context, error) => const Center(
        key: ValueKey('sale-returns-failure'),
        child: Text('Returns could not be loaded.'),
      ),
      builder: (context, session, view) => _SaleReturnsContents(
        request: request,
        view: view,
        selfUid: session.uid,
        pageIndex: _pageIndex,
        busy: _busy,
        notice: _notice,
        canRecord:
            widget.actions?.writer != null &&
            session.canAccess(
              allowedRoles: TenantReturnRequestRepository.allowedRoles,
            ),
        canVerify:
            widget.actions?.verifyCallable != null &&
            TenantReturnVerificationGateway.canVerifyInSession(session),
        onNextPage: () => _nextPage(view.page.nextCursor),
        onPreviousPage: _previousPage,
        onRecord: (quantities, reason) =>
            _record(session, view.returnable!, quantities, reason),
        onVerify: (record) => _verify(session, record),
      ),
    );
  }

  /// Verifies one pending return and restores its stock.
  ///
  /// The gateway is bound to this exact session and this exact decoded record,
  /// so nothing on this screen can name another business or another return.
  /// After any outcome the page is re-read, so what is shown is the server's own
  /// verification evidence rather than an optimistic local state.
  Future<void> _verify(TenantSession session, TenantReturn record) async {
    final callable = widget.actions?.verifyCallable;
    if (callable == null || _busy) return;
    final capturedKey = _sessionKey(session);
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final gateway = TenantReturnVerificationGateway(
        session: session,
        target: record,
        callable: callable,
        requestIdFactory: widget.requestIdFactory == null
            ? null
            : () => 'verify-${widget.requestIdFactory!()}',
      );
      final result = await gateway.submit(gateway.createIntent());
      if (!_stillCurrent(capturedKey)) return;
      setState(
        () => _notice =
            'Restored ${result.restoredUnits} '
            '${result.restoredUnits == 1 ? 'unit' : 'units'} across '
            '${result.restoredProducts.length} '
            '${result.restoredProducts.length == 1 ? 'product' : 'products'}.',
      );
      _reload();
    } on TenantReturnVerificationException catch (error) {
      if (!_stillCurrent(capturedKey)) return;
      setState(() => _notice = _verificationNotice(error.failure));
      // Only an unknown outcome may have restored stock, and only the server
      // can say. Re-reading is the one safe response; retrying is not.
      if (error.mayHaveCommitted) _reload();
    } on FormatException {
      if (!_stillCurrent(capturedKey)) return;
      // The call may well have restored stock; only its answer was unusable.
      setState(
        () => _notice =
            'The verification response could not be trusted. Reload this page '
            'to see what the server recorded.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

String _verificationNotice(TenantReturnVerificationFailure failure) =>
    switch (failure) {
      TenantReturnVerificationFailure.forbidden =>
        'Only an owner, administrator, or manager may restore stock.',
      TenantReturnVerificationFailure.notFound =>
        'This return no longer exists in this business.',
      TenantReturnVerificationFailure.alreadyVerified =>
        'This return had already been verified, so nothing was restored again.',
      TenantReturnVerificationFailure.exceedsSale =>
        'This return covers more than the original sale still allows. It '
            'cannot be verified; record a corrected return instead.',
      TenantReturnVerificationFailure.missingProduct =>
        'A returned product no longer exists, so its stock cannot be restored.',
      TenantReturnVerificationFailure.missingSale =>
        'The original sale is missing, so nothing bounds this restoration.',
      TenantReturnVerificationFailure.tooManyVerifications =>
        'This sale has too many prior verifications for automatic '
            'restoration. It needs manual stock adjustment.',
      TenantReturnVerificationFailure.refused =>
        'The return was refused and no stock was restored.',
      TenantReturnVerificationFailure.ambiguous =>
        'The result is unknown. This page has been reloaded; check whether the '
            'return is now verified before trying again.',
      TenantReturnVerificationFailure.unavailable =>
        'The server could not be reached, so no stock was restored.',
    };

String _resultNotice(TenantReturnWriteResult result) =>
    switch (result.kind) {
      TenantReturnWriteKind.committed =>
        'Return recorded. No stock has been restored yet; a manager must '
            'verify it first.',
      TenantReturnWriteKind.rejected =>
        'The return was refused and nothing was recorded. Check the '
            'quantities and try again.',
      TenantReturnWriteKind.ambiguous =>
        'The result is unknown. Reload this page to see whether the return '
            'was recorded, and do not record it again.',
      TenantReturnWriteKind.unavailable =>
        'This device is offline, so nothing was recorded. A return must be '
            'recorded while online.',
    };

String _refusalNotice(String code) => switch (code) {
  'return_exceeds_sale' =>
    'That is more than this sale still has available to return.',
  'invalid_return_reason' =>
    'Record a reason of at least 3 characters for this return.',
  'invalid_return_quantities' => 'Choose at least one unit to return.',
  'return_forbidden' => 'This role may not record a return.',
  _ => 'The return could not be recorded.',
};

final class _SaleReturnsContents extends StatelessWidget {
  const _SaleReturnsContents({
    required this.request,
    required this.view,
    required this.selfUid,
    required this.pageIndex,
    required this.busy,
    required this.notice,
    required this.canRecord,
    required this.canVerify,
    required this.onNextPage,
    required this.onPreviousPage,
    required this.onRecord,
    required this.onVerify,
  });

  final TenantSaleReturnsRequest request;
  final _ReturnsView view;
  final String selfUid;
  final int pageIndex;
  final bool busy;
  final String? notice;
  final bool canRecord;

  /// Whether this session may restore stock. The action is offered on a pending
  /// return only; a verified one is terminal.
  final bool canVerify;
  final VoidCallback onNextPage;
  final VoidCallback onPreviousPage;
  final void Function(Map<String, int> quantities, String reason) onRecord;
  final ValueChanged<TenantReturn> onVerify;

  TenantReturnPage get page => view.page;

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
      if (notice case final message?) ...[
        const SizedBox(height: 12),
        Text(key: const ValueKey('sale-returns-notice'), message),
      ],
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
        for (final record in page.items) _entry(context, record),
      ],
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        children: [
          if (pageIndex > 0)
            AppButton(
              key: const ValueKey('sale-returns-previous'),
              label: 'Previous page',
              onPressed: onPreviousPage,
            ),
          if (page.hasMore)
            AppButton(
              key: const ValueKey('sale-returns-next'),
              label: 'Next page',
              tier: AppButtonTier.primary,
              onPressed: onNextPage,
            ),
        ],
      ),
      if (canRecord) ...[
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 12),
        if (view.returnable case final returnable?)
          if (returnable.hasReturnableLines)
            _RecordReturnForm(
              key: const ValueKey('sale-returns-form'),
              returnable: returnable,
              busy: busy,
              onRecord: onRecord,
            )
          else
            const Text(
              key: ValueKey('sale-returns-nothing-left'),
              'Every unit on this sale has already been returned.',
            )
        else
          const Text(
            key: ValueKey('sale-returns-form-unavailable'),
            'More returns exist than this page shows. Go back to the first '
            'page to record another return against this sale.',
          ),
      ],
    ],
  );

  Widget _entry(BuildContext context, TenantReturn record) => Card(
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
          Text(
            key: ValueKey('sale-returns-reason-${record.id}'),
            'Reason: ${record.reason}',
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
            )
          else if (canVerify) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                       key: ValueKey('sale-returns-verify-${record.id}'),
                       label: 'Verify and restore stock',
                       tier: AppButtonTier.primary,
                       onPressed: busy
                    ? null
                    : () => _confirmVerification(context, record),
                     ),
            ),
          ],
        ],
      ),
    ),
  );

  /// Names the exact products and units whose stock will move before anything
  /// is restored. Restoration is not reversible through this app.
  Future<void> _confirmVerification(
    BuildContext context,
    TenantReturn record,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore this stock?'),
        content: Text(
          'This verifies the return and adds '
          '${record.lines.map(_lineLabel).join(', ')} back to stock. It '
          'cannot be undone from this app.',
        ),
        actions: [
          AppButton(
            key: const ValueKey('sale-returns-cancel-verify'),
            label: 'Cancel',
            tier: AppButtonTier.tertiary,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          AppButton(
            key: const ValueKey('sale-returns-confirm-verify'),
            label: 'Verify and restore',
            tier: AppButtonTier.primary,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed == true) onVerify(record);
  }

  String _label(String uid) =>
      tenantStaffLabel(uid, names: view.names, selfUid: selfUid);
}

/// Selects the units to return and requires an explicit confirmation.
final class _RecordReturnForm extends StatefulWidget {
  const _RecordReturnForm({
    super.key,
    required this.returnable,
    required this.busy,
    required this.onRecord,
  });

  final TenantReturnableSale returnable;
  final bool busy;
  final void Function(Map<String, int> quantities, String reason) onRecord;

  @override
  State<_RecordReturnForm> createState() => _RecordReturnFormState();
}

final class _RecordReturnFormState extends State<_RecordReturnForm> {
  final Map<String, int> _quantities = <String, int>{};
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  int _quantityOf(String productId) => _quantities[productId] ?? 0;

  void _change(TenantReturnableLine line, int delta) {
    final next = _quantityOf(line.productId) + delta;
    if (next < 0 || next > line.remainingQuantity) return;
    setState(() => _quantities[line.productId] = next);
  }

  int get _selectedUnits =>
      _quantities.values.fold(0, (total, value) => total + value);

  bool get _canSubmit =>
      !widget.busy &&
      _selectedUnits > 0 &&
      _reason.text.trim().length >= minimumReturnReasonLength;

  Future<void> _confirm() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record this return?'),
        content: Text(
          'This records $_selectedUnits '
          '${_selectedUnits == 1 ? 'unit' : 'units'} as a pending return. It '
          'restores no stock: a manager must verify it first.',
        ),
        actions: [
          AppButton(
            key: const ValueKey('sale-returns-cancel-confirm'),
            label: 'Cancel',
            tier: AppButtonTier.tertiary,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          AppButton(
            key: const ValueKey('sale-returns-confirm'),
            label: 'Record return',
            tier: AppButtonTier.primary,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    widget.onRecord(
      Map<String, int>.unmodifiable(_quantities),
      _reason.text,
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Record a return',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 4),
      const Text(
        'Only what this sale still has available may be returned. Pending '
        'returns already count against it.',
      ),
      const SizedBox(height: 12),
      for (final line in widget.returnable.lines)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  key: ValueKey('sale-returns-remaining-${line.productId}'),
                  '${line.name}: ${line.remainingQuantity} of '
                  '${line.soldQuantity} available',
                ),
              ),
              IconButton(
                key: ValueKey('sale-returns-decrease-${line.productId}'),
                onPressed: line.remainingQuantity == 0
                    ? null
                    : () => _change(line, -1),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text(
                key: ValueKey('sale-returns-quantity-${line.productId}'),
                '${_quantityOf(line.productId)}',
              ),
              IconButton(
                key: ValueKey('sale-returns-increase-${line.productId}'),
                onPressed: line.remainingQuantity == 0
                    ? null
                    : () => _change(line, 1),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        ),
      const SizedBox(height: 12),
      AppTextField(
        key: const ValueKey('sale-returns-reason'),
        controller: _reason,
        maxLength: maximumReturnReasonLength,
        onChanged: (_) => setState(() {}),
        label: 'Reason for this return',
      ),
      const SizedBox(height: 12),
      AppButton(
        key: const ValueKey('sale-returns-submit'),
        label: 'Record return',
        tier: AppButtonTier.primary,
        onPressed: _canSubmit ? _confirm : null,
      ),
    ],
  );
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
