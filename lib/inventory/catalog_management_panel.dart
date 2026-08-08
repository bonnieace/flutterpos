import 'package:flutter/material.dart';

import '../tenancy/tenant_catalog.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import 'catalog_management.dart';

/// The catalog route that adds to, corrects, and retires from one business's
/// catalog.
///
/// It is the first surface in the migrated client that puts a product in. Every
/// operational surface below it - the till, stock, returns, reporting,
/// reconciliation - already assumed a product existed, and until this route
/// nothing but `seed-dev-emulator.js` could create one.
///
/// Its three write paths do not share a transport, and that is a decision rather
/// than an accident. Creating and retiring are direct Firestore writes, because
/// the rules on `products` and `categories` already name the roles this route is
/// offered to. **Correcting is a callable**, because `allow update` on `products`
/// is the checkout decrement and nothing else, and widening it would trade a
/// stock-integrity guarantee for a price edit that records no actor, no previous
/// value, and no reason.
final class TenantCatalogManagementScreen extends StatelessWidget {
  const TenantCatalogManagementScreen({
    super.key,
    required this.reader,
    this.writer,
    this.updateCallable,
    this.bulkRoute,
    this.onChanged,
    this.requestIdFactory,
  });

  final TenantDataReader reader;

  /// Supplied by the composition root. While it is absent this route is exactly
  /// a read-only statement of the catalog, as every other injected capability
  /// in this app behaves.
  final TenantCatalogWriter? writer;

  /// The bulk route, reached from here rather than from the landing route.
  ///
  /// It belongs beside the catalog for the reason the catalog belongs beside the
  /// till: correcting many products starts by looking at them, and its own
  /// product list is the same list this route shows.
  final WidgetBuilder? bulkRoute;

  /// Corrects one product's name, code, price, cost, or category. Injected for
  /// the same reason and with the same consequence: while it is absent, nothing
  /// on this route offers to correct anything.
  final UpdateProductCallable? updateCallable;

  /// Called after the server acknowledged a change, so the composition root can
  /// ask the sync pass to re-read what this device caches.
  final VoidCallback? onChanged;

  /// One fresh request ID per confirmed create or correction.
  final TenantCatalogRequestIdFactory? requestIdFactory;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Manage catalog')),
    body: TenantCatalogManagementPanel(
      reader: reader,
      writer: writer,
      updateCallable: updateCallable,
      bulkRoute: bulkRoute,
      onChanged: onChanged,
      requestIdFactory: requestIdFactory,
    ),
  );
}

/// Guarded catalog-management content, split out to keep it widget-testable.
///
/// The guard owns authorization and stale-session rejection, and its role list
/// is the *create* list. Retiring is narrower still and is decided per render
/// from the guarded session, so the action disappears the moment the session
/// stops allowing it.
final class TenantCatalogManagementPanel extends StatefulWidget {
  const TenantCatalogManagementPanel({
    super.key,
    required this.reader,
    this.writer,
    this.updateCallable,
    this.bulkRoute,
    this.onChanged,
    this.requestIdFactory,
    this.pageSize = 20,
    this.categoryPageSize = 50,
  });

  final TenantDataReader reader;
  final TenantCatalogWriter? writer;
  final UpdateProductCallable? updateCallable;
  final WidgetBuilder? bulkRoute;
  final VoidCallback? onChanged;
  final TenantCatalogRequestIdFactory? requestIdFactory;
  final int pageSize;
  final int categoryPageSize;

  @override
  State<TenantCatalogManagementPanel> createState() =>
      _TenantCatalogManagementPanelState();
}

final class _TenantCatalogManagementPanelState
    extends State<TenantCatalogManagementPanel> {
  // The form lives above the guard on purpose. Paging and reloading both
  // replace the guarded subtree with a loading indicator, and a half-typed
  // product would go with it if the controllers lived below.
  final TextEditingController _categoryName = TextEditingController();
  final TextEditingController _productName = TextEditingController();
  final TextEditingController _productSku = TextEditingController();
  final TextEditingController _productPrice = TextEditingController();
  final TextEditingController _productCost = TextEditingController();

  String? _selectedCategoryId;
  List<String?> _cursors = <String?>[null];
  int _pageIndex = 0;
  int _generation = 0;
  bool _busy = false;
  String? _notice;

  /// Retained only across an ambiguous attempt, so a retry addresses the same
  /// deterministic document instead of stocking the shelf twice.
  String? _categoryRequestId;
  String? _productRequestId;

  /// The same rule for corrections, with one addition the creates do not need.
  ///
  /// A create's request ID decides a document identity, so reusing it is always
  /// the safe thing. A correction's decides an *idempotency* record, and the
  /// server refuses a reused ID carrying different input - so the retained ID is
  /// held against the exact correction it was issued for, and an operator who
  /// changes their mind after an unknown outcome gets a fresh one rather than a
  /// duplicate-request refusal.
  String? _editRequestId;
  String? _editFingerprint;

  @override
  void dispose() {
    _categoryName.dispose();
    _productName.dispose();
    _productSku.dispose();
    _productPrice.dispose();
    _productCost.dispose();
    super.dispose();
  }

  static String _sessionKey(TenantSession session) =>
      '${session.uid}:${session.tenantId}:${session.epoch}';

  /// Whether the session this work was authorized against is still selected.
  bool _stillCurrent(String capturedKey) {
    if (!mounted) return false;
    final current = TenantSessionScope.of(context).session;
    return current != null && _sessionKey(current) == capturedKey;
  }

  /// Restarts the guarded read from the first page, so what is listed is the
  /// server's own catalog rather than what was just typed.
  void _reload() {
    setState(() {
      _cursors = <String?>[null];
      _pageIndex = 0;
      _generation++;
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

  String _newRequestId() =>
      (widget.requestIdFactory ?? secureTenantCatalogRequestId)();

  TenantCatalogManagementRepository _repository(TenantSession session) =>
      TenantCatalogManagementRepository(
        session: session,
        reader: widget.reader,
      );

  Future<void> _addCategory(TenantSession session) async {
    final writer = widget.writer;
    if (writer == null || _busy) return;
    final capturedKey = _sessionKey(session);

    // The intent is built before anything is confirmed, so a name this boundary
    // would refuse is reported instead of being asked about.
    final TenantCategoryCreateIntent intent;
    try {
      intent = _repository(session).buildCategoryIntent(
        name: _categoryName.text,
        requestId: _categoryRequestId ??= _newRequestId(),
      );
    } on TenantCatalogManagementException catch (error) {
      _categoryRequestId = null;
      setState(() => _notice = _refusalNotice(error.code));
      return;
    }
    if (!await _confirmed(
          title: 'Add the category "${intent.name}"?',
          body:
              'A category groups products in the catalog and filters them at '
              'the till. Every product names one, so this is what a new product '
              'can be filed under. It cannot be renamed or removed from here.',
          action: 'Add category',
        ) ||
        !_stillCurrent(capturedKey)) {
      return;
    }

    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final result = await writer.createCategory(intent);
      if (!_stillCurrent(capturedKey)) return;
      // Only an unknown outcome may have landed, so only it keeps the request
      // ID. A rejected or unattempted write left nothing behind, and reusing
      // its ID would deny an edited retry as a replay.
      if (result.kind != TenantCatalogWriteKind.ambiguous) {
        _categoryRequestId = null;
      }
      setState(() => _notice = _categoryNotice(result));
      if (result.kind != TenantCatalogWriteKind.rejected) _reload();
      if (result.kind == TenantCatalogWriteKind.committed) {
        _categoryName.clear();
        widget.onChanged?.call();
      }
    } on TenantCatalogManagementException catch (error) {
      if (!_stillCurrent(capturedKey)) return;
      setState(() => _notice = _refusalNotice(error.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addProduct(TenantSession session, _CatalogView view) async {
    final writer = widget.writer;
    if (writer == null || _busy) return;
    final capturedKey = _sessionKey(session);

    final TenantProductCreateIntent intent;
    try {
      intent = _repository(session).buildProductIntent(
        name: _productName.text,
        sku: _productSku.text,
        price: _productPrice.text,
        cost: _productCost.text,
        categoryId: _selectedCategoryId ?? '',
        categories: view.categories.items,
        requestId: _productRequestId ??= _newRequestId(),
      );
    } on TenantCatalogManagementException catch (error) {
      _productRequestId = null;
      setState(() => _notice = _refusalNotice(error.code));
      return;
    }
    if (!await _confirmed(
          title: 'Add "${intent.name}" to the catalog?',
          body:
              '${intent.name} is filed under ${intent.categoryName}, scanned as '
              '${intent.sku}, and priced at ${_money(intent.priceMinor)} in the '
              'currency this business publishes. '
              '${intent.costMinor == null ? 'No unit cost is recorded, so its '
                    'sales report no profit and are counted as missing cost data.' : 'It costs ${_money(intent.costMinor!)} a unit; every sale '
                    'records that figure as it stands at the moment of the sale, '
                    'so correcting it later never changes a profit already '
                    'reported.'} '
              'It is added holding no stock: '
              'record the opening quantity from the product itself, so the '
              'ledger says where those units came from.\n\n'
              '${widget.updateCallable == null ? 'Nothing in this app can change a name, a code, or a price '
                    'afterwards.' : 'A name, code, price, or unit cost can be corrected afterwards '
                    'from this same list, and every correction is recorded.'} '
              'Nothing makes a code unique either - if another '
              'product already scans as ${intent.sku}, the till will refuse '
              'that scan rather than pick one.',
          action: 'Add product',
        ) ||
        !_stillCurrent(capturedKey)) {
      return;
    }

    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final result = await writer.createProduct(intent);
      if (!_stillCurrent(capturedKey)) return;
      if (result.kind != TenantCatalogWriteKind.ambiguous) {
        _productRequestId = null;
      }
      setState(() => _notice = _productNotice(result));
      if (result.kind != TenantCatalogWriteKind.rejected) _reload();
      if (result.kind == TenantCatalogWriteKind.committed) {
        _clearProductForm();
        widget.onChanged?.call();
      }
    } on TenantCatalogManagementException catch (error) {
      if (!_stillCurrent(capturedKey)) return;
      setState(() => _notice = _refusalNotice(error.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retire(TenantSession session, TenantProduct product) async {
    final writer = widget.writer;
    if (writer == null || _busy) return;
    final capturedKey = _sessionKey(session);

    final TenantProductRetireIntent intent;
    try {
      intent = _repository(session).buildRetireIntent(product);
    } on TenantCatalogManagementException catch (error) {
      setState(() => _notice = _refusalNotice(error.code));
      return;
    }
    if (!await _confirmed(
          title: 'Retire "${intent.name}"?',
          body:
              'It stops appearing in the catalog and at the till. Everything '
              'already recorded keeps naming it: its stock ledger, every past '
              'sale line, and every reported figure. Nothing is undone and no '
              'money changes.\n\n'
              'It still holds ${intent.quantity} in stock. Retiring moves that '
              'nowhere and records no movement for it.\n\n'
              'This is not how a mistake is corrected. A replacement product '
              'gets its own identity, and this one keeps its whole history, so '
              'adding one back does not repair a wrong name, code, or price.'
              '${widget.updateCallable == null ? '' : ' Correct it instead, from the same list.'}',
          action: 'Retire product',
          destructive: true,
        ) ||
        !_stillCurrent(capturedKey)) {
      return;
    }

    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final result = await writer.retireProduct(intent);
      if (!_stillCurrent(capturedKey)) return;
      setState(() => _notice = _retireNotice(result, intent));
      if (result.kind != TenantCatalogWriteKind.rejected) _reload();
      if (result.kind == TenantCatalogWriteKind.committed) {
        widget.onChanged?.call();
      }
    } on TenantCatalogManagementException catch (error) {
      if (!_stillCurrent(capturedKey)) return;
      setState(() => _notice = _refusalNotice(error.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Corrects one product through `updateProduct`, then re-reads.
  ///
  /// Every field is offered at once, deliberately. The callable validates the
  /// *resulting* document rather than only the fields being written, so a
  /// refusal can name a field this correction never touched - the contract is
  /// "name every broken field in one request, or none", and a single-field edit
  /// could not honour it.
  Future<void> _edit(
    TenantSession session,
    _CatalogView view,
    TenantProduct product,
  ) async {
    final callable = widget.updateCallable;
    if (callable == null || _busy) return;
    final capturedKey = _sessionKey(session);

    final draft = await showDialog<_ProductEditDraft>(
      context: context,
      builder: (context) => _EditProductDialog(
        product: product,
        categories: view.categories.items,
        moreCategories: view.categories.hasMore,
        // A price and a cost are money and sit behind owner or administrator.
        // The field is not offered at all to anyone else, because the callable
        // reads its tier from the fields a payload names: a form that offered a
        // price it knew would be refused would teach a manager only that the
        // app guesses.
        canChangeMoney: TenantCatalogManagementRepository.canRecordCostInSession(
          session,
        ),
      ),
    );
    if (draft == null || !_stillCurrent(capturedKey)) return;

    final TenantProductUpdateIntent intent;
    try {
      intent = _repository(session).buildUpdateIntent(
        product: product,
        name: draft.name,
        sku: draft.sku,
        price: draft.price,
        cost: draft.cost,
        clearCost: draft.clearCost,
        categoryId: draft.categoryId,
        categories: view.categories.items,
        requestId: _editRequestIdFor(draft.fingerprint(product.id)),
      );
    } on TenantCatalogManagementException catch (error) {
      _forgetEditRequestId();
      setState(() => _notice = _refusalNotice(error.code));
      return;
    }
    if (!await _confirmed(
          title: 'Correct "${product.name}"?',
          body: _editConfirmation(intent),
          action: 'Save correction',
        ) ||
        !_stillCurrent(capturedKey)) {
      return;
    }

    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final result = await TenantProductUpdateGateway(
        session: session,
        callable: callable,
      ).submit(intent);
      if (!_stillCurrent(capturedKey)) return;
      _forgetEditRequestId();
      setState(() => _notice = _updateNotice(result));
      _reload();
      widget.onChanged?.call();
    } on TenantProductUpdateException catch (error) {
      if (!_stillCurrent(capturedKey)) return;
      // Only an unknown outcome may have landed, so only it keeps the request
      // ID. Every other refusal is proof nothing changed, and reusing its ID
      // would deny an edited retry as a duplicate.
      if (!error.mayHaveCommitted) _forgetEditRequestId();
      setState(() => _notice = _updateFailureNotice(error.failure));
      if (error.mayHaveCommitted) _reload();
    } on FormatException {
      if (!_stillCurrent(capturedKey)) return;
      // The correction may well have been applied; only its answer was
      // unusable. The request ID is kept for exactly that reason: repeating
      // this same correction answers off the server's record rather than
      // auditing it twice.
      setState(
        () => _notice =
            'The correction was sent and its answer could not be trusted. The '
            'catalog below has been re-read; it states what the server holds.',
      );
      _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// One request ID per correction, held across a retry of that same
  /// correction and never across a different one.
  String _editRequestIdFor(String fingerprint) {
    final retained = _editRequestId;
    if (retained != null && _editFingerprint == fingerprint) return retained;
    _editFingerprint = fingerprint;
    return _editRequestId = _newRequestId();
  }

  void _forgetEditRequestId() {
    _editRequestId = null;
    _editFingerprint = null;
  }

  /// Opens the bulk route, carrying the session and re-reading on the way back.
  ///
  /// The re-read is the point: a bulk correction changes products this list is
  /// currently stating, and returning to a stale page would show prices the
  /// business no longer sells at.
  Future<void> _openBulk() async {
    final builder = widget.bulkRoute;
    if (builder == null || _busy) return;
    final controller = TenantSessionScope.of(context);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            TenantSessionScope(controller: controller, child: builder(context)),
      ),
    );
    if (mounted) _reload();
  }

  void _clearProductForm() {
    _productName.clear();
    _productSku.clear();
    _productPrice.clear();
    _productCost.clear();
    _selectedCategoryId = null;
  }

  Future<bool> _confirmed({
    required String title,
    required String body,
    required String action,
    bool destructive = false,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(body)),
        actions: [
          TextButton(
            key: const ValueKey('catalog-management-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('catalog-management-confirm'),
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  )
                : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return confirmed == true && mounted;
  }

  /// One loader per guard key, cached so a `setState` for the busy flag or a
  /// notice does not restart the read.
  TenantGuardedLoader<_CatalogView> _loaderFor(String key) {
    if (key == _loaderKey && _loader != null) return _loader!;
    _loaderKey = key;
    final cursor = _cursors[_pageIndex];
    return _loader = (session) async {
      final repository = TenantCatalogRepository(
        session: session,
        reader: widget.reader,
      );
      final categories = await repository.loadCategories(
        pageSize: widget.categoryPageSize,
      );
      final products = await repository.loadProducts(
        pageSize: widget.pageSize,
        cursor: cursor,
      );
      return _CatalogView(categories: categories, products: products);
    };
  }

  String? _loaderKey;
  TenantGuardedLoader<_CatalogView>? _loader;

  @override
  Widget build(BuildContext context) {
    final guardKey = 'catalog-management:$_generation:$_pageIndex';
    return TenantRouteGuard<_CatalogView>(
      key: ValueKey(guardKey),
      allowedRoles: TenantCatalogManagementRepository.allowedRoles,
      load: _loaderFor(guardKey),
      denied: const Center(
        key: ValueKey('catalog-management-denied'),
        child: Text(
          'Only an owner, administrator, or manager may change the catalog.',
        ),
      ),
      failure: (context, error) => const Center(
        key: ValueKey('catalog-management-failure'),
        child: Text('The catalog could not be read.'),
      ),
      builder: (context, session, view) => _CatalogManagementContents(
        view: view,
        busy: _busy,
        notice: _notice,
        canWrite: widget.writer != null,
        // Taken from the guarded session, never from the caller, so the action
        // disappears the moment the session stops allowing it.
        canRetire: TenantCatalogManagementRepository.canRetireInSession(
          session,
        ),
        // Correcting needs only the operational three the guard already
        // admitted, so what decides this is whether the build has the callable
        // at all. Which of the five fields the form then offers is decided
        // per session inside it.
        canEdit: widget.updateCallable != null,
        onBulk: widget.bulkRoute == null ? null : _openBulk,
        categoryName: _categoryName,
        productName: _productName,
        productSku: _productSku,
        productPrice: _productPrice,
        productCost: _productCost,
        canRecordCost:
            TenantCatalogManagementRepository.canRecordCostInSession(session),
        selectedCategoryId: _selectedCategoryId,
        pageIndex: _pageIndex,
        onCategorySelected: (categoryId) =>
            setState(() => _selectedCategoryId = categoryId),
        onFormChanged: () => setState(() {}),
        onAddCategory: () => _addCategory(session),
        onAddProduct: () => _addProduct(session, view),
        onEdit: (product) => _edit(session, view, product),
        onRetire: (product) => _retire(session, product),
        onNextPage: () => _nextPage(view.products.nextCursor),
        onPreviousPage: _previousPage,
      ),
    );
  }
}

/// One guarded read of everything this route renders.
final class _CatalogView {
  const _CatalogView({required this.categories, required this.products});

  final TenantCatalogPage<TenantCategory> categories;
  final TenantCatalogPage<TenantProduct> products;
}

final class _CatalogManagementContents extends StatelessWidget {
  const _CatalogManagementContents({
    required this.view,
    required this.busy,
    required this.notice,
    required this.canWrite,
    required this.canRetire,
    required this.canEdit,
    required this.onBulk,
    required this.categoryName,
    required this.productName,
    required this.productSku,
    required this.productPrice,
    required this.productCost,
    required this.canRecordCost,
    required this.selectedCategoryId,
    required this.pageIndex,
    required this.onCategorySelected,
    required this.onFormChanged,
    required this.onAddCategory,
    required this.onAddProduct,
    required this.onEdit,
    required this.onRetire,
    required this.onNextPage,
    required this.onPreviousPage,
  });

  final _CatalogView view;
  final bool busy;
  final String? notice;
  final bool canWrite;
  final bool canRetire;

  /// Whether this build can correct a product at all, which is whether the
  /// composition root supplied the callable. The role tier inside a correction
  /// is decided by the form, not here.
  final bool canEdit;

  /// Opens the bulk route, or null when this build does not carry one.
  final VoidCallback? onBulk;

  final TextEditingController categoryName;
  final TextEditingController productName;
  final TextEditingController productSku;
  final TextEditingController productPrice;
  final TextEditingController productCost;

  /// Whether this member may record what the business paid. A manager may add
  /// a product and may not state its margin.
  final bool canRecordCost;
  final String? selectedCategoryId;
  final int pageIndex;
  final ValueChanged<String> onCategorySelected;
  final VoidCallback onFormChanged;
  final VoidCallback onAddCategory;
  final VoidCallback onAddProduct;
  final ValueChanged<TenantProduct> onEdit;
  final ValueChanged<TenantProduct> onRetire;
  final VoidCallback onNextPage;
  final VoidCallback onPreviousPage;

  /// The category chosen, if it is still one the current page offers. A reload
  /// can drop it, and filing a product under a grouping this surface no longer
  /// shows would be refused later rather than here.
  String? get _selected {
    for (final category in view.categories.items) {
      if (category.id == selectedCategoryId) return category.id;
    }
    return null;
  }

  /// The actions offered against one product, or nothing at all.
  ///
  /// Correcting and retiring are separate capabilities with separate role sets
  /// and separate transports, so a build or a session may offer either, both, or
  /// neither.
  Widget? _actions(TenantProduct product) {
    final actions = <Widget>[
      if (canEdit)
        TextButton(
          key: ValueKey('catalog-management-edit-${product.id}'),
          onPressed: busy ? null : () => onEdit(product),
          child: const Text('Correct'),
        ),
      if (canRetire && canWrite)
        TextButton(
          key: ValueKey('catalog-management-retire-${product.id}'),
          onPressed: busy ? null : () => onRetire(product),
          child: const Text('Retire'),
        ),
    ];
    if (actions.isEmpty) return null;
    return Row(mainAxisSize: MainAxisSize.min, children: actions);
  }

  bool get _canSubmitProduct =>
      canWrite &&
      !busy &&
      _selected != null &&
      productName.text.trim().isNotEmpty &&
      productSku.text.trim().isNotEmpty &&
      productPrice.text.trim().isNotEmpty;

  bool get _canSubmitCategory =>
      canWrite && !busy && categoryName.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final categoryNames = <String, String>{
      for (final category in view.categories.items) category.id: category.name,
    };
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Catalog', style: text.titleMedium),
        const SizedBox(height: 4),
        Text(
          key: const ValueKey('catalog-management-scope'),
          canEdit
              ? 'A product added here can be sold, counted, returned, and '
                    'reported on immediately. Its name, code, price, and unit '
                    'cost can be corrected afterwards, and every correction is '
                    'recorded with what each field held before. What cannot be '
                    'changed here is its stock, which belongs to the product '
                    'itself, and retiring it does not undo anything already '
                    'recorded.'
              : 'A product added here can be sold, counted, returned, and '
                    'reported on immediately. Its name, code, and price are '
                    'permanent: nothing in this build can correct them '
                    'afterwards, and retiring it does not undo anything '
                    'already recorded.',
        ),
        if (!canWrite) ...[
          const SizedBox(height: 12),
          const Text(
            key: ValueKey('catalog-management-read-only'),
            'This build cannot change the catalog from here.',
          ),
        ],
        if (notice case final notice?) ...[
          const SizedBox(height: 16),
          Text(key: const ValueKey('catalog-management-notice'), notice),
        ],
        const SizedBox(height: 24),
        Text('Categories', style: text.titleMedium),
        const SizedBox(height: 8),
        if (view.categories.items.isEmpty)
          const Text(
            key: ValueKey('catalog-management-no-categories'),
            'This business has no categories yet. Every product is filed under '
            'one, so the first category comes before the first product.',
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final category in view.categories.items)
                ChoiceChip(
                  key: ValueKey('catalog-management-category-${category.id}'),
                  label: Text(category.name),
                  selected: category.id == _selected,
                  onSelected: canWrite && !busy
                      ? (_) => onCategorySelected(category.id)
                      : null,
                ),
            ],
          ),
        if (view.categories.hasMore)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              key: ValueKey('catalog-management-more-categories'),
              'More categories exist than are shown here. A product can only be '
              'filed under one of the categories above.',
            ),
          ),
        if (canWrite) ...[
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('catalog-management-category-name'),
            controller: categoryName,
            enabled: !busy,
            maxLength: maximumCatalogNameLength,
            onChanged: (_) => onFormChanged(),
            decoration: const InputDecoration(
              labelText: 'New category name',
              helperText: 'Such as Bakery, Drinks, or Household.',
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('catalog-management-add-category'),
            onPressed: _canSubmitCategory ? onAddCategory : null,
            icon: const Icon(Icons.new_label_outlined),
            label: const Text('Add category'),
          ),
        ],
        const SizedBox(height: 28),
        Text('Add a product', style: text.titleMedium),
        const SizedBox(height: 8),
        if (!canWrite)
          const Text(
            key: ValueKey('catalog-management-product-read-only'),
            'Products cannot be added from this build.',
          )
        else ...[
          TextField(
            key: const ValueKey('catalog-management-product-name'),
            controller: productName,
            enabled: !busy,
            maxLength: maximumCatalogNameLength,
            onChanged: (_) => onFormChanged(),
            decoration: const InputDecoration(labelText: 'Product name'),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('catalog-management-product-sku'),
            controller: productSku,
            enabled: !busy,
            maxLength: maximumCatalogSkuLength,
            onChanged: (_) => onFormChanged(),
            decoration: const InputDecoration(
              labelText: 'Code (SKU or barcode)',
              helperText: 'What the till matches a scan against. No spaces.',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('catalog-management-product-price'),
            controller: productPrice,
            enabled: !busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => onFormChanged(),
            decoration: const InputDecoration(
              labelText: 'Unit price',
              helperText:
                  'At most two decimal places, in the currency this business '
                  'publishes. A price this app cannot record exactly is '
                  'refused here rather than at the till.',
            ),
          ),
          if (canRecordCost) ...[
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('catalog-management-product-cost'),
              controller: productCost,
              enabled: !busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => onFormChanged(),
              decoration: const InputDecoration(
                labelText: 'Unit cost (optional)',
                helperText:
                    'What one unit costs this business. Every sale records the '
                    'cost as it stands at that moment, so correcting this later '
                    'prices the next sale and never changes a profit figure '
                    'already reported. Leave blank if you do not track it.',
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            key: const ValueKey('catalog-management-selected-category'),
            _selected == null
                ? view.categories.items.isEmpty
                      ? 'Add a category before adding a product.'
                      : 'Choose the category this product is filed under.'
                : 'Filed under ${categoryNames[_selected] ?? _selected}.',
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const ValueKey('catalog-management-add-product'),
            onPressed: _canSubmitProduct ? onAddProduct : null,
            icon: const Icon(Icons.add_box_outlined),
            label: const Text('Add product'),
          ),
        ],
        if (onBulk case final onBulk?) ...[
          const SizedBox(height: 28),
          Text('Many products at once', style: text.titleMedium),
          const SizedBox(height: 8),
          const Text(
            key: ValueKey('catalog-management-bulk-scope'),
            'One correction can be applied across many products, and a catalog '
            'can be created from a spreadsheet. Both are previewed row by row '
            'before anything is written.',
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('catalog-management-bulk'),
            onPressed: busy ? null : onBulk,
            icon: const Icon(Icons.playlist_add_check_outlined),
            label: const Text('Bulk changes and import'),
          ),
        ],
        const SizedBox(height: 28),
        Text('Products', style: text.titleMedium),
        const SizedBox(height: 8),
        if (view.products.items.isEmpty)
          const Text(
            key: ValueKey('catalog-management-no-products'),
            'No products on this page.',
          )
        else
          for (final product in view.products.items)
            Card(
              child: ListTile(
                key: ValueKey('catalog-management-product-${product.id}'),
                title: Text(product.name),
                subtitle: Text(
                  '${categoryNames[product.categoryId] ?? product.categoryId} '
                  '• ${product.sku} • ${product.quantity} in stock '
                  '• ${product.price.toStringAsFixed(2)}',
                ),
                trailing: _actions(product),
              ),
            ),
        if (!canRetire) ...[
          const SizedBox(height: 8),
          const Text(
            key: ValueKey('catalog-management-retire-unavailable'),
            'Only an owner or administrator may retire a product.',
          ),
        ],
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              key: const ValueKey('catalog-management-previous-page'),
              onPressed: pageIndex == 0 || busy ? null : onPreviousPage,
              child: const Text('Previous'),
            ),
            Text(
              key: const ValueKey('catalog-management-page'),
              'Page ${pageIndex + 1}',
            ),
            TextButton(
              key: const ValueKey('catalog-management-next-page'),
              onPressed: view.products.hasMore && !busy ? onNextPage : null,
              child: const Text('Next'),
            ),
          ],
        ),
      ],
    );
  }
}

String _categoryNotice(
  TenantCatalogWriteResult result,
) => switch (result.kind) {
  TenantCatalogWriteKind.committed =>
    'Category added. It can be chosen for a product straight away.',
  TenantCatalogWriteKind.rejected =>
    'The category was refused and nothing was written. Only an owner, '
        'administrator, or manager may change the catalog.',
  TenantCatalogWriteKind.ambiguous =>
    'The result is unknown. The categories above have been re-read; if it is '
        'not listed, add it again - the retry addresses the same document, so '
        'it cannot be added twice.',
  TenantCatalogWriteKind.unavailable =>
    'This device is offline, so nothing was written. The catalog can only be '
        'changed while online.',
};

String _productNotice(TenantCatalogWriteResult result) => switch (result.kind) {
  TenantCatalogWriteKind.committed =>
    'Product added, holding no stock. Record its opening quantity from the '
        'product itself so the ledger says where those units came from. This '
        'device re-reads the catalog on its next sync, and every other device '
        'picks it up when it syncs.',
  TenantCatalogWriteKind.rejected =>
    'The product was refused and nothing was written. Only an owner, '
        'administrator, or manager may change the catalog, and an entry that '
        'already exists is never overwritten.',
  TenantCatalogWriteKind.ambiguous =>
    'The result is unknown. The catalog below has been re-read; if the product '
        'is not listed, add it again - the retry addresses the same document, '
        'so it cannot be stocked twice.',
  TenantCatalogWriteKind.unavailable =>
    'This device is offline, so nothing was written. The catalog can only be '
        'changed while online.',
};

String _retireNotice(
  TenantCatalogWriteResult result,
  TenantProductRetireIntent intent,
) => switch (result.kind) {
  TenantCatalogWriteKind.committed =>
    '${intent.name} is retired. Its stock ledger and every sale that already '
        'named it are untouched.',
  TenantCatalogWriteKind.rejected =>
    'Nothing was retired. Only an owner or administrator may retire a product.',
  TenantCatalogWriteKind.ambiguous =>
    'The result is unknown. The catalog below has been re-read; if the product '
        'is still listed, retire it again - retiring the same product twice '
        'does nothing further.',
  TenantCatalogWriteKind.unavailable =>
    'This device is offline, so nothing was retired. The catalog can only be '
        'changed while online.',
};

/// States every field that moves, and the consequence of each kind of move.
///
/// The changes are listed before the consequences on purpose: an operator who
/// mistyped a price and is about to correct it needs to see the before and the
/// after side by side, which is the one thing a form full of prefilled fields
/// cannot show them.
String _editConfirmation(TenantProductUpdateIntent intent) {
  bool moves(TenantProductField field) =>
      intent.changes.any((change) => change.field == field);
  final buffer = StringBuffer(
    intent.changes.map((change) => '- $change').join('\n'),
  );
  buffer.write(
    '\n\nThis is recorded permanently against the product, with who made it '
    'and what each field held before. Nothing else about the product changes: '
    'its stock is untouched, its identity stays the same, and every sale, '
    'return, and reported figure already recorded still names it.',
  );
  if (moves(TenantProductField.price)) {
    buffer.write(
      '\n\nA new price applies to the next sale. Sales already recorded keep '
      'the price they were sold at, so no figure already reported moves.',
    );
  }
  if (moves(TenantProductField.cost)) {
    buffer.write(
      '\n\nEvery sale records what a unit cost at the moment of that sale, so '
      'this prices the next sale and never changes a profit already reported.',
    );
  }
  if (moves(TenantProductField.sku)) {
    buffer.write(
      '\n\nThe till matches a scan against the code, so the old one stops '
      'finding this product. Nothing makes a code unique either - if another '
      'product already scans as the new one, the till refuses that scan rather '
      'than picking one.',
    );
  }
  buffer.write(
    '\n\nThis device re-reads the catalog on its next sync, and every other '
    'device picks the correction up when it syncs.',
  );
  return buffer.toString();
}

String _updateNotice(TenantProductUpdateResult result) {
  final fields = result.changedFields
      .map((field) => field.label.toLowerCase())
      .join(', ');
  // The cost is stated from the answer rather than left to the re-read below.
  // It is the one corrected field whose new value used to be unconfirmable: the
  // response named it in `changedFields` with no figure beside it until it began
  // echoing `cost` and `costMinor`.
  final cost = result.changedFields.contains(TenantProductField.cost)
      ? result.costMinor == null
            ? ' Its unit cost is no longer recorded, so its sales report no '
                  'profit and are counted as missing cost data.'
            : ' Its unit cost is now ${_money(result.costMinor!)}.'
      : '';
  return 'Corrected: $fields.$cost What each field held before is recorded '
      'against the product. The catalog below has been re-read; this device '
      're-reads its own copy on the next sync.';
}

String _updateFailureNotice(TenantProductUpdateFailure failure) =>
    switch (failure) {
      TenantProductUpdateFailure.forbidden =>
        'Only an owner, administrator, or manager may correct a product, and '
            'nothing was changed.',
      TenantProductUpdateFailure.priceForbidden =>
        'Only an owner or administrator may change a price. Nothing was '
            'changed, including the fields that are not money.',
      TenantProductUpdateFailure.costForbidden =>
        'Only an owner or administrator may change what a product costs. '
            'Nothing was changed, including the fields that are not money.',
      TenantProductUpdateFailure.productMissing =>
        'This product no longer exists in this business, so nothing was '
            'changed.',
      TenantProductUpdateFailure.categoryMissing =>
        'That category no longer exists in this business. Nothing was changed; '
            'the categories above have been re-read.',
      TenantProductUpdateFailure.unchanged =>
        'The product already holds every value in this correction, so nothing '
            'was changed. Somebody else may have made the same correction.',
      TenantProductUpdateFailure.productUnreadable =>
        'This product holds a value no device can read, and a correction has '
            'to repair every one of them at once. Nothing was changed. Correct '
            'each field on this form together and save again.',
      TenantProductUpdateFailure.needsOperator =>
        'This product is stored in a state no correction can repair - its '
            'stock quantity or its image. Nothing was changed, and it needs an '
            'operator.',
      TenantProductUpdateFailure.duplicateRequest =>
        'An earlier attempt already used this correction. Nothing was changed '
            'a second time; re-read the catalog below and start again.',
      TenantProductUpdateFailure.invalidRequest =>
        'The server refused this correction as malformed and nothing was '
            'changed. This build and the server disagree about what a product '
            'may hold.',
      TenantProductUpdateFailure.refused =>
        'The correction was refused and nothing was changed.',
      TenantProductUpdateFailure.ambiguous =>
        'The result is unknown. The catalog below has been re-read; if the '
            'correction is not there, save it again - repeating the same '
            'correction cannot apply it twice.',
    };

String _refusalNotice(String code) => switch (code) {
  'invalid_category_name' =>
    'Enter a category name of at most $maximumCatalogNameLength characters.',
  'invalid_product_name' =>
    'Enter a product name of at most $maximumCatalogNameLength characters.',
  'invalid_sku' =>
    'Enter a code of at most $maximumCatalogSkuLength characters, with no '
        'spaces - it is what the till matches a scan against.',
  'invalid_price' =>
    'Enter a price as a plain amount with at most two decimal places, such as '
        '65 or 19.99.',
  'price_not_representable' =>
    'That price is larger than a sale in this app can record. It is refused '
        'here rather than at the till, where it would stop a customer.',
  'invalid_cost' =>
    'Enter the unit cost as a plain amount with at most two decimal places, '
        'such as 40 or 12.50 - or leave it blank if you do not track it.',
  'cost_not_representable' =>
    'That unit cost is larger than a sale in this app can record. A sale '
        'records the cost alongside the price, so it is refused here.',
  'cost_forbidden' =>
    'Only an owner or administrator may record what a product costs. Leave the '
        'unit cost blank, or ask one of them to set it.',
  'price_forbidden' =>
    'Only an owner or administrator may change a price. Nothing was sent, so '
        'the other fields were not changed either.',
  'product_unchanged' =>
    'Nothing on the form differs from what the product already holds, so there '
        'was nothing to correct and nothing was sent.',
  'unknown_category' =>
    'Choose one of the categories shown above before adding the product.',
  'catalog_forbidden' =>
    'Only an owner, administrator, or manager may change the catalog.',
  'retire_forbidden' => 'Only an owner or administrator may retire a product.',
  'edit_forbidden' =>
    'That product belongs to another business, so nothing was changed.',
  _ => 'The catalog could not be changed.',
};

String _money(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);

/// What one correction asks for, before anything has been validated.
///
/// [price] and [cost] are nullable because the form does not offer either to a
/// manager, and null means "this form never asked" rather than "make it empty".
final class _ProductEditDraft {
  const _ProductEditDraft({
    required this.name,
    required this.sku,
    required this.categoryId,
    required this.price,
    required this.cost,
    required this.clearCost,
  });

  final String name;
  final String sku;
  final String categoryId;
  final String? price;
  final String? cost;

  /// Clearing a recorded cost is its own act, never an empty cost field. An
  /// omitted cost leaves the stored figure alone; this removes it.
  final bool clearCost;

  /// Identifies this exact correction, so a retained request ID can be held
  /// against the correction it was issued for and no other.
  String fingerprint(String productId) =>
      <String>[
        productId,
        name,
        sku,
        categoryId,
        price ?? '',
        cost ?? '',
        '$clearCost',
      // NUL-separated, matching every other identity digest in this codebase.
      // Written as an escape rather than typed: it reached this file as a
      // literal NUL byte, which made `grep` report the whole module as binary
      // and return nothing from it - the standing trap, met here in Dart for
      // the first time. It must stay a NUL rather than become a space, because
      // this is what a retained request ID is held against.
      ].join('\u0000');
}

/// The one form that corrects a product, offering every editable field at once.
///
/// Every field is prefilled with what the product holds, so the form states the
/// current value as well as collecting the new one, and an untouched field is
/// compared equal and never sent.
final class _EditProductDialog extends StatefulWidget {
  const _EditProductDialog({
    required this.product,
    required this.categories,
    required this.moreCategories,
    required this.canChangeMoney,
  });

  final TenantProduct product;
  final List<TenantCategory> categories;

  /// Whether more categories exist than were read, in which case a product can
  /// only be moved into one of those offered.
  final bool moreCategories;

  final bool canChangeMoney;

  @override
  State<_EditProductDialog> createState() => _EditProductDialogState();
}

final class _EditProductDialogState extends State<_EditProductDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.product.name,
  );
  late final TextEditingController _sku = TextEditingController(
    text: widget.product.sku,
  );
  late final TextEditingController _price = TextEditingController(
    text: widget.product.price.toStringAsFixed(2),
  );
  late final TextEditingController _cost = TextEditingController(
    text: widget.product.cost?.toStringAsFixed(2) ?? '',
  );
  late String _categoryId = widget.product.categoryId;
  bool _clearCost = false;

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    _price.dispose();
    _cost.dispose();
    super.dispose();
  }

  /// Whether the product's own category is one this page read. A business may
  /// hold more categories than one page shows, and leaving a product where it
  /// already is needs no proof.
  bool get _categoryOffered =>
      widget.categories.any((category) => category.id == _categoryId);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text('Correct "${widget.product.name}"'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              key: ValueKey('catalog-management-edit-scope'),
              'Every field is filled in with what the product holds now. '
              'Change the ones that are wrong and save them together: a '
              'correction is checked against the whole product, so one that '
              'leaves a different field unreadable is refused outright.',
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('catalog-management-edit-name'),
              controller: _name,
              maxLength: maximumCatalogNameLength,
              decoration: const InputDecoration(labelText: 'Product name'),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('catalog-management-edit-sku'),
              controller: _sku,
              maxLength: maximumCatalogSkuLength,
              decoration: const InputDecoration(
                labelText: 'Code (SKU or barcode)',
                helperText:
                    'What the till matches a scan against. No spaces. The old '
                    'code stops finding this product.',
              ),
            ),
            if (widget.canChangeMoney) ...[
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('catalog-management-edit-price'),
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Unit price',
                  helperText:
                      'Applies to the next sale. Sales already recorded keep '
                      'the price they were sold at.',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('catalog-management-edit-cost'),
                controller: _cost,
                enabled: !_clearCost,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Unit cost',
                  helperText: widget.product.cost == null
                      ? 'No unit cost is recorded. Enter one to start recording '
                            'it; leave it blank to keep reporting no profit for '
                            'this product.'
                      : 'Leaving this blank keeps the recorded cost as it is. '
                            'Removing it is a separate act, below.',
                ),
              ),
              if (widget.product.cost != null)
                CheckboxListTile(
                  key: const ValueKey('catalog-management-edit-clear-cost'),
                  value: _clearCost,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Remove the recorded unit cost'),
                  subtitle: const Text(
                    'Its sales then report no profit and are counted as '
                    'missing cost data, rather than reporting the whole price '
                    'as profit.',
                  ),
                  onChanged: (value) =>
                      setState(() => _clearCost = value ?? false),
                ),
            ] else ...[
              const SizedBox(height: 12),
              Text(
                key: const ValueKey('catalog-management-edit-money-hidden'),
                'Only an owner or administrator may change what this product '
                'is priced at or what it costs, so neither is offered here.',
                style: text.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            Text('Category', style: text.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in widget.categories)
                  ChoiceChip(
                    key: ValueKey(
                      'catalog-management-edit-category-${category.id}',
                    ),
                    label: Text(category.name),
                    selected: category.id == _categoryId,
                    onSelected: (_) =>
                        setState(() => _categoryId = category.id),
                  ),
              ],
            ),
            if (!_categoryOffered)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  key: const ValueKey('catalog-management-edit-category-off'),
                  'This product is filed under ${widget.product.categoryId}, '
                  'which is not among the categories read here. Leaving it '
                  'there is fine; choosing one above moves it.',
                  style: text.bodySmall,
                ),
              )
            else if (widget.moreCategories)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  key: const ValueKey('catalog-management-edit-more-categories'),
                  'More categories exist than are shown here. A product can '
                  'only be moved into one of those above.',
                  style: text.bodySmall,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('catalog-management-edit-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('catalog-management-edit-review'),
          onPressed: () => Navigator.of(context).pop(
            _ProductEditDraft(
              name: _name.text,
              sku: _sku.text,
              categoryId: _categoryId,
              price: widget.canChangeMoney ? _price.text : null,
              cost: widget.canChangeMoney && !_clearCost ? _cost.text : null,
              clearCost: widget.canChangeMoney && _clearCost,
            ),
          ),
          child: const Text('Review correction'),
        ),
      ],
    );
  }
}
