import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../tenancy/tenant_catalog.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../tenancy/tenant_types.dart';
import '../ui/buttons.dart';
import '../ui/chips.dart';
import '../ui/dialogs.dart';
import '../ui/fields.dart';
import '../ui/pagination.dart';
import '../ui/routes.dart';
import '../ui/scaffold.dart';
import '../ui/sheet.dart';
import '../ui/snackbar.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'catalog_management.dart';
import 'product_background_removal.dart';
import 'stock_adjustment.dart';
import 'product_image_store.dart';
import 'product_visual.dart';

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
    this.productSearchReader,
    this.imageStore,
    this.backgroundRemover,
    this.productStockRoute,
    this.adjustStockSheet,
    this.productStockRoles = const <TenantRole>[],
    this.adjustmentFeedRoute,
    this.adjustmentFeedRoles = const <TenantRole>[],
    this.movementFeedRoute,
    this.movementFeedRoles = const <TenantRole>[],
    this.productVisualBuilder,
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
  final TenantProductSearchReader? productSearchReader;
  final TenantProductImageStore? imageStore;

  /// Cuts a product photograph out of its background, and is absent wherever
  /// no such service is configured - which draws no such action rather than a
  /// broken one. See `product_background_removal.dart`.
  final TenantProductBackgroundRemover? backgroundRemover;

  final TenantProductRouteBuilder? productStockRoute;

  /// Opens the stock-correction sheet. See [TenantProductAdjustStockOpener].
  ///
  /// **Separate from [productStockRoute] since 2026-08-26**, where the two used
  /// to be one builder taking a mode. Reading a ledger is a route and
  /// correcting a figure is a sheet, and one signature could not honestly
  /// describe both.
  final TenantProductAdjustStockOpener? adjustStockSheet;

  final List<TenantRole> productStockRoles;
  final TenantAdjustmentFeedRouteBuilder? adjustmentFeedRoute;
  final List<TenantRole> adjustmentFeedRoles;
  final TenantMovementFeedRouteBuilder? movementFeedRoute;
  final List<TenantRole> movementFeedRoles;
  final TenantProductVisualBuilder? productVisualBuilder;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Inventory Manager',
    subtitle: 'Manage products, categories, and stock.',
    contentWidth: AppContentWidth.records,
    body: TenantCatalogManagementPanel(
      reader: reader,
      writer: writer,
      updateCallable: updateCallable,
      bulkRoute: bulkRoute,
      onChanged: onChanged,
      requestIdFactory: requestIdFactory,
      productSearchReader: productSearchReader,
      imageStore: imageStore,
      backgroundRemover: backgroundRemover,
      productStockRoute: productStockRoute,
      adjustStockSheet: adjustStockSheet,
      productStockRoles: productStockRoles,
      adjustmentFeedRoute: adjustmentFeedRoute,
      adjustmentFeedRoles: adjustmentFeedRoles,
      movementFeedRoute: movementFeedRoute,
      movementFeedRoles: movementFeedRoles,
      productVisualBuilder: productVisualBuilder,
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
    this.productSearchReader,
    this.imageStore,
    this.backgroundRemover,
    this.productStockRoute,
    this.adjustStockSheet,
    this.productStockRoles = const <TenantRole>[],
    this.adjustmentFeedRoute,
    this.adjustmentFeedRoles = const <TenantRole>[],
    this.movementFeedRoute,
    this.movementFeedRoles = const <TenantRole>[],
    this.productVisualBuilder,
  });

  final TenantDataReader reader;
  final TenantCatalogWriter? writer;
  final UpdateProductCallable? updateCallable;
  final WidgetBuilder? bulkRoute;
  final VoidCallback? onChanged;
  final TenantCatalogRequestIdFactory? requestIdFactory;
  final int pageSize;
  final int categoryPageSize;
  final TenantProductSearchReader? productSearchReader;
  final TenantProductImageStore? imageStore;
  final TenantProductBackgroundRemover? backgroundRemover;
  final TenantProductRouteBuilder? productStockRoute;

  /// Opens the stock-correction sheet. See [TenantProductAdjustStockOpener].
  ///
  /// **Separate from [productStockRoute] since 2026-08-26**, where the two used
  /// to be one builder taking a mode. Reading a ledger is a route and
  /// correcting a figure is a sheet, and one signature could not honestly
  /// describe both.
  final TenantProductAdjustStockOpener? adjustStockSheet;

  final List<TenantRole> productStockRoles;
  final TenantAdjustmentFeedRouteBuilder? adjustmentFeedRoute;
  final List<TenantRole> adjustmentFeedRoles;
  final TenantMovementFeedRouteBuilder? movementFeedRoute;
  final List<TenantRole> movementFeedRoles;
  final TenantProductVisualBuilder? productVisualBuilder;

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
  final TextEditingController _search = TextEditingController();

  String? _selectedCategoryId;
  List<String?> _cursors = <String?>[null];
  int _pageIndex = 0;
  int _generation = 0;
  bool _busy = false;
  AppNotice? _notice;

  /// Reports one write outcome, on the surface its kind belongs to.
  ///
  /// See `noticeIsTransient`: a confirmation withdraws itself, and everything
  /// that names a next step stays where it was drawn.
  void _report(AppNotice notice) {
    if (noticeIsTransient(notice)) {
      showAppSnackBar(context, notice);
      return;
    }
    setState(() => _notice = notice);
  }

  Timer? _searchDebounce;
  String _searchPrefix = '';
  String? _categoryFilter;
  TenantProductStockFilter _stockFilter = TenantProductStockFilter.all;
  TenantProductImageCandidate? _productImage;

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
    _searchDebounce?.cancel();
    _search.dispose();
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

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(AppMotion.standard.long.duration, () {
      if (!mounted) return;
      final normalized = tenantProductSearchTerm(value);
      final next = normalized.length >= 2 ? normalized : '';
      if (next == _searchPrefix) {
        setState(() {});
        return;
      }
      setState(() {
        _searchPrefix = next;
        _cursors = <String?>[null];
        _pageIndex = 0;
        _generation++;
      });
    });
  }

  void _setCategoryFilter(String? categoryId) {
    if (_categoryFilter == categoryId) return;
    setState(() {
      _categoryFilter = categoryId;
      _cursors = <String?>[null];
      _pageIndex = 0;
      _generation++;
    });
  }

  void _setStockFilter(TenantProductStockFilter stock) {
    if (_stockFilter == stock) return;
    setState(() {
      _stockFilter = stock;
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
      _report(_refusalNotice(error.code));
      return;
    }
    if (!await _confirmed(
          title: 'Add the category "${intent.name}"?',
          body:
              'A category groups products in the catalog and filters them at '
              'the till. Every product names one, so this is what a new product '
              'can be filed under. It can be renamed later, but is never '
              'deleted from this screen.',
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
      _report(_categoryNotice(result));
      if (result.kind != TenantCatalogWriteKind.rejected) _reload();
      if (result.kind == TenantCatalogWriteKind.committed) {
        _categoryName.clear();
        widget.onChanged?.call();
      }
    } on TenantCatalogManagementException catch (error) {
      if (!_stillCurrent(capturedKey)) return;
      _report(_refusalNotice(error.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _renameCategory(
    TenantSession session,
    TenantCategory category,
  ) async {
    final writer = widget.writer;
    if (writer == null || _busy) return;
    final nextName = await showAppDialog<String>(
      context,
      builder: (context) => _RenameCategoryDialog(category: category),
    );
    if (nextName == null || !_stillCurrent(_sessionKey(session))) return;
    final TenantCategoryRenameIntent intent;
    try {
      intent = _repository(
        session,
      ).buildCategoryRenameIntent(category: category, name: nextName);
    } on TenantCatalogManagementException catch (error) {
      _report(_refusalNotice(error.code));
      return;
    }
    if (!await _confirmed(
      title: 'Rename "${category.name}" to "${intent.name}"?',
      body:
          'The category keeps the same identity. Existing products stay filed '
          'under it and no product documents are rewritten.',
      action: 'Rename category',
    )) {
      return;
    }
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final result = await writer.renameCategory(intent);
      if (!mounted) return;
      _report(_categoryRenameNotice(result));
      if (result.kind != TenantCatalogWriteKind.rejected) _reload();
      if (result.kind == TenantCatalogWriteKind.committed) {
        widget.onChanged?.call();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<TenantProductImageCandidate?> _chooseProductImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    if (!mounted || result == null) return null;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      _report(const AppNotice.refused(
          'That image could not be read. Choose a JPEG, PNG, or WebP file.',
        ));
      return null;
    }
    try {
      return TenantProductImageCandidate(bytes: bytes, fileName: file.name);
    } on TenantProductImageException catch (error) {
      _report(_imageNotice(error));
      return null;
    }
  }


  /// Opens a product form as a sheet over this catalog.
  ///
  /// **Two arrangements, decided by width, at the product owner's direction on
  /// 2026-08-26.** Below §4.1's `medium` floor the picture is the sheet's
  /// masthead - bleeding into its own top corners, drag handle overlaid, the
  /// fields scrolling underneath. At and above it the two-column form survives
  /// unchanged, because a wide sheet has room to put the picture beside its
  /// fields rather than above them.
  ///
  /// The masthead needs the picture the form is holding, and it is built above
  /// that form's state; [_ProductImagePreviewModel] is what carries it across.
  Future<T?> _openProductFormSheet<T>({
    required TenantProduct? product,
    required Widget Function(
      ScrollController controller,
      _ProductImagePreviewModel? preview,
    )
    form,
  }) {
    final controller = TenantSessionScope.of(context);
    final compact = !AppLayout.contract.isAtLeast(
      MediaQuery.sizeOf(context).width,
      AppBreakpoint.medium,
    );
    final preview = compact
        ? (_ProductImagePreviewModel(product: product)..show(_productImage))
        : null;
    return showAppSheet<T>(
      context,
      initialDetent: AppSheetDetent.full,
      masthead: preview == null
          ? null
          : (context) => ListenableBuilder(
              listenable: preview,
              builder: (context, _) => _ProductImagePreview(
                key: const ValueKey('inventory-product-masthead'),
                image: preview.image,
                product: preview.shownProduct,
                // The masthead is the sheet's own top; its corners are the
                // sheet's and it must not round any of its own inside them.
                square: true,
              ),
            ),
      builder: (sheetContext, sheetController) => TenantSessionScope(
        controller: controller,
        child: form(sheetController, preview),
      ),
    );
  }

  Future<void> _openAddProduct(TenantSession session, _CatalogView view) async {
    final submit = await _openProductFormSheet<bool>(
      product: null,
      form: (sheetController, preview) => _AddProductScreen(
            scrollController: sheetController,
            preview: preview,
            categories: view.categories.items,
            moreCategories: view.categories.hasMore,
            name: _productName,
            sku: _productSku,
            price: _productPrice,
            cost: _productCost,
            canRecordCost:
                TenantCatalogManagementRepository.canRecordCostInSession(
                  session,
                ),
            selectedCategoryId: _selectedCategoryId,
            image: _productImage,
            busy: _busy,
            onCategorySelected: (categoryId) {
              _selectedCategoryId = categoryId;
            },
            onChooseImage: widget.imageStore == null
                ? null
                : _chooseProductImage,
            onImageChanged: (image) => _productImage = image,
            session: session,
            backgroundRemover: widget.backgroundRemover,
          ),
    );
    if (submit == true && mounted) await _addProduct(session, view);
  }

  Future<void> _openCategories(TenantSession session) async {
    await showAppDialog<void>(
      context,
      builder: (context) => _CategoriesDialog(
        session: session,
        reader: widget.reader,
        writer: widget.writer,
        pageSize: widget.categoryPageSize.clamp(1, 20),
        name: _categoryName,
        busy: _busy,
        onAdd: () => _addCategory(session),
        onRename: (category) => _renameCategory(session, category),
      ),
    );
  }

  Future<void> _openProduct(TenantProduct product) =>
      _openScopedRoute(() => widget.productStockRoute?.call(product));

  /// The correction, as a sheet over this catalog.
  ///
  /// **It does not go through [_openScopedRoute], and the difference is the
  /// whole point of the change.** That helper pushes a route and wraps it in a
  /// captured session scope; the sheet opener does its own scope capture and
  /// stays over this list rather than replacing it, so the row a person was
  /// working on is still behind the scrim when they close it.
  Future<void> _adjustProduct(TenantProduct product) async {
    final open = widget.adjustStockSheet;
    if (open == null || _busy) return;
    await open(context, product);
  }

  Future<void> _openScopedRoute(Widget? Function()? build) async {
    final route = build?.call();
    if (route == null || _busy) return;
    final controller = TenantSessionScope.of(context);
    await Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (context) =>
            TenantSessionScope(controller: controller, child: route),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _addProduct(TenantSession session, _CatalogView view) async {
    final writer = widget.writer;
    if (writer == null || _busy) return;
    final capturedKey = _sessionKey(session);

    TenantProductCreateIntent intent;
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
      _report(_refusalNotice(error.code));
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
    TenantProductImageUpload? upload;
    try {
      final candidate = _productImage;
      final store = widget.imageStore;
      if (candidate != null && store != null) {
        upload = await store.upload(
          tenantId: session.tenantId,
          productId: intent.productId,
          candidate: candidate,
        );
        intent = _repository(session).buildProductIntent(
          name: _productName.text,
          sku: _productSku.text,
          price: _productPrice.text,
          cost: _productCost.text,
          categoryId: _selectedCategoryId ?? '',
          categories: view.categories.items,
          requestId: _productRequestId!,
          imageUrl: upload.url,
        );
      }
      final result = await writer.createProduct(intent);
      if (upload != null &&
          result.kind != TenantCatalogWriteKind.committed &&
          result.kind != TenantCatalogWriteKind.ambiguous) {
        await _removeOwnedQuietly(
          session: session,
          productId: intent.productId,
          imageUrl: upload.url,
        );
      }
      if (!_stillCurrent(capturedKey)) return;
      if (result.kind != TenantCatalogWriteKind.ambiguous) {
        _productRequestId = null;
      }
      _report(_productNotice(result));
      if (result.kind != TenantCatalogWriteKind.rejected) _reload();
      if (result.kind == TenantCatalogWriteKind.committed) {
        _clearProductForm();
        widget.onChanged?.call();
      }
    } on TenantCatalogManagementException catch (error) {
      if (upload != null) {
        await _removeOwnedQuietly(
          session: session,
          productId: intent.productId,
          imageUrl: upload.url,
        );
      }
      if (!_stillCurrent(capturedKey)) return;
      _report(_refusalNotice(error.code));
    } on TenantProductImageException catch (error) {
      if (!_stillCurrent(capturedKey)) return;
      _report(_imageNotice(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeOwnedQuietly({
    required TenantSession session,
    required String productId,
    required Uri imageUrl,
  }) async {
    try {
      await widget.imageStore?.removeOwned(
        tenantId: session.tenantId,
        productId: productId,
        imageUrl: imageUrl,
      );
    } catch (_) {
      // Cleanup is best effort; the product outcome remains the primary fact.
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
      _report(_refusalNotice(error.code));
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
      _report(_retireNotice(result, intent));
      if (result.kind != TenantCatalogWriteKind.rejected) _reload();
      if (result.kind == TenantCatalogWriteKind.committed) {
        widget.onChanged?.call();
      }
    } on TenantCatalogManagementException catch (error) {
      if (!_stillCurrent(capturedKey)) return;
      _report(_refusalNotice(error.code));
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

    final draft = await _openProductFormSheet<_ProductEditDraft>(
      product: product,
      form: (sheetController, preview) => _EditProductScreen(
            scrollController: sheetController,
            preview: preview,
            product: product,
            categories: view.categories.items,
            moreCategories: view.categories.hasMore,
            // A price and a cost are money and sit behind owner or
            // administrator. The field is not offered at all to anyone else,
            // because the callable reads its tier from the fields a payload
            // names: a form that offered a price it knew would be refused
            // would teach a manager only that the app guesses.
            canChangeMoney:
                TenantCatalogManagementRepository.canRecordCostInSession(
                  session,
                ),
            canChangeImage: widget.imageStore != null,
            onChooseImage: _chooseProductImage,
            session: session,
            backgroundRemover: widget.backgroundRemover,
          ),
    );
    if (draft == null || !_stillCurrent(capturedKey)) return;

    TenantProductImageUpload? stagedImage;
    if (draft.image != null) {
      final store = widget.imageStore;
      if (store == null) return;
      setState(() {
        _busy = true;
        _notice = null;
      });
      try {
        stagedImage = await store.upload(
          tenantId: session.tenantId,
          productId: product.id,
          candidate: draft.image!,
        );
      } on TenantProductImageException catch (error) {
        if (_stillCurrent(capturedKey)) {
          setState(() {
            _busy = false;
            _notice = _imageNotice(error);
          });
        }
        return;
      }
    }

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
        imageUrl: stagedImage?.url,
        clearImage: draft.removeImage,
      );
    } on TenantCatalogManagementException catch (error) {
      if (stagedImage != null) {
        await _removeOwnedQuietly(
          session: session,
          productId: product.id,
          imageUrl: stagedImage.url,
        );
      }
      _forgetEditRequestId();
      setState(() {
        _busy = false;
        _notice = _refusalNotice(error.code);
      });
      return;
    }
    if (!await _confirmed(
          title: 'Correct "${product.name}"?',
          body: _editConfirmation(intent),
          action: 'Save correction',
        ) ||
        !_stillCurrent(capturedKey)) {
      if (stagedImage != null) {
        await _removeOwnedQuietly(
          session: session,
          productId: product.id,
          imageUrl: stagedImage.url,
        );
      }
      if (mounted) setState(() => _busy = false);
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
      if ((stagedImage != null || draft.removeImage) &&
          product.imageUrl != null) {
        await _removeOwnedQuietly(
          session: session,
          productId: product.id,
          imageUrl: product.imageUrl!,
        );
      }
      if (!_stillCurrent(capturedKey)) return;
      _forgetEditRequestId();
      _report(_updateNotice(result));
      _reload();
      widget.onChanged?.call();
    } on TenantProductUpdateException catch (error) {
      if (!error.mayHaveCommitted && stagedImage != null) {
        await _removeOwnedQuietly(
          session: session,
          productId: product.id,
          imageUrl: stagedImage.url,
        );
      }
      if (!_stillCurrent(capturedKey)) return;
      // Only an unknown outcome may have landed, so only it keeps the request
      // ID. Every other refusal is proof nothing changed, and reusing its ID
      // would deny an edited retry as a duplicate.
      if (!error.mayHaveCommitted) _forgetEditRequestId();
      _report(_updateFailureNotice(error.failure));
      if (error.mayHaveCommitted) _reload();
    } on FormatException {
      if (!_stillCurrent(capturedKey)) return;
      // The correction may well have been applied; only its answer was
      // unusable. The request ID is kept for exactly that reason: repeating
      // this same correction answers off the server's record rather than
      // auditing it twice.
      setState(
        () => _notice = const AppNotice.unknown(
          'The correction was sent and its answer could not be trusted. The '
          'catalog below has been re-read; it states what the server holds.',
        ),
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
      AppPageRoute<void>(
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
    _productImage = null;
  }

  Future<bool> _confirmed({
    required String title,
    required String body,
    required String action,
    bool destructive = false,
  }) async {
    // The `destructive` flag used to paint `colorScheme.error` onto a filled
    // button by hand. §2.1 has a tier for exactly this, so the flag chooses a
    // tier instead of a colour - which is `claude.md` hard rule 2 - and
    // `ConfirmDialog` carries the tier through to the barrier as well: a
    // destructive question can be escaped by its scrim because cancel is the
    // safe answer, and a primary one cannot.
    final confirmed = await showConfirmDialog(
      context,
      title: title,
      consequence: body,
      confirmLabel: action,
      tier: destructive ? AppButtonTier.destructive : AppButtonTier.primary,
      confirmKey: const ValueKey('catalog-management-confirm'),
      cancelKey: const ValueKey('catalog-management-cancel'),
    );
    return confirmed && mounted;
  }

  /// One loader per guard key, cached so a `setState` for the busy flag or a
  /// notice does not restart the read.
  void _composeLoaders(String key) {
    if (key == _loaderKey && _loader != null) return;
    _loaderKey = key;
    final cursor = _cursors[_pageIndex];
    TenantGuardedLoader<_CatalogView> readWith(TenantDataReader reader) =>
        (session) async {
      final repository = TenantCatalogRepository(
        session: session,
        reader: reader,
        productSearchReader: widget.productSearchReader,
      );
      final categories = await repository.loadCategories(
        pageSize: widget.categoryPageSize,
      );
      final supportsSearch =
          widget.productSearchReader != null ||
          reader is TenantProductSearchReader;
      final products = supportsSearch
          ? await repository.searchProducts(
              pageSize: widget.pageSize,
              cursor: cursor,
              searchPrefix: _searchPrefix.isEmpty ? null : _searchPrefix,
              categoryId: _categoryFilter,
              stock: _stockFilter,
            )
          : await repository.loadProducts(
              pageSize: widget.pageSize,
              cursor: cursor,
            );
      return _CatalogView(categories: categories, products: products);
    };
    _loader = readWith(widget.reader);
    final cache = widget.reader.cached;
    _loaderCached = cache == null ? null : readWith(cache);
  }

  String? _loaderKey;
  TenantGuardedLoader<_CatalogView>? _loader;
  TenantGuardedLoader<_CatalogView>? _loaderCached;

  @override
  Widget build(BuildContext context) {
    final guardKey =
        'inventory:$_generation:$_pageIndex:$_searchPrefix:'
        '${_categoryFilter ?? ''}:${_stockFilter.name}';
    _composeLoaders(guardKey);
    return TenantRouteGuard<_CatalogView>(
      key: ValueKey(guardKey),
      allowedRoles: null,
      load: _loader!,
      loadCached: _loaderCached,
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
      builder: (context, session, view) => _UnifiedInventoryContents(
        view: view,
        busy: _busy,
        notice: _notice,
        canWrite:
            widget.writer != null &&
            session.canAccess(
              allowedRoles: TenantCatalogManagementRepository.allowedRoles,
            ),
        // Taken from the guarded session, never from the caller, so the action
        // disappears the moment the session stops allowing it.
        canRetire: TenantCatalogManagementRepository.canRetireInSession(
          session,
        ),
        // Correcting needs only the operational three the guard already
        // admitted, so what decides this is whether the build has the callable
        // at all. Which of the five fields the form then offers is decided
        // per session inside it.
        canEdit:
            widget.updateCallable != null &&
            session.canAccess(
              allowedRoles: TenantCatalogManagementRepository.allowedRoles,
            ),
        canView:
            widget.productStockRoute != null &&
            session.canAccess(allowedRoles: widget.productStockRoles),
        // **Narrower than `canView` on purpose.** Everyone the stock route
        // admits may read the ledger; only the roles the adjust callable
        // itself enforces may correct a figure, and the gateway is what
        // decides that rather than this surface.
        canAdjust:
            widget.adjustStockSheet != null &&
            session.canAccess(allowedRoles: widget.productStockRoles) &&
            TenantStockAdjustmentGateway.canAdjustInSession(session),
        canViewCost: TenantCatalogManagementRepository.canRecordCostInSession(
          session,
        ),
        onBulk: widget.bulkRoute == null ? null : _openBulk,
        search: _search,
        searchPrefix: _searchPrefix,
        categoryFilter: _categoryFilter,
        stockFilter: _stockFilter,
        pageIndex: _pageIndex,
        onSearchChanged: _onSearchChanged,
        onCategoryFilterChanged: _setCategoryFilter,
        onStockFilterChanged: _setStockFilter,
        onOpenCategories: () => _openCategories(session),
        onOpenAddProduct: () => _openAddProduct(session, view),
        onView: _openProduct,
        onAdjust: _adjustProduct,
        onEdit: (product) => _edit(session, view, product),
        onRetire: (product) => _retire(session, product),
        onNextPage: () => _nextPage(view.products.nextCursor),
        onPreviousPage: _previousPage,
        productVisualBuilder: widget.productVisualBuilder,
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

/// The legacy `goods.dart` hierarchy rebuilt on the tenant-safe catalog model.
final class _UnifiedInventoryContents extends StatelessWidget {
  const _UnifiedInventoryContents({
    required this.view,
    required this.busy,
    required this.notice,
    required this.canWrite,
    required this.canRetire,
    required this.canEdit,
    required this.canView,
    required this.canAdjust,
    required this.canViewCost,
    required this.onBulk,
    required this.search,
    required this.searchPrefix,
    required this.categoryFilter,
    required this.stockFilter,
    required this.pageIndex,
    required this.onSearchChanged,
    required this.onCategoryFilterChanged,
    required this.onStockFilterChanged,
    required this.onOpenCategories,
    required this.onOpenAddProduct,
    required this.onView,
    required this.onAdjust,
    required this.onEdit,
    required this.onRetire,
    required this.onNextPage,
    required this.onPreviousPage,
    required this.productVisualBuilder,
  });

  final _CatalogView view;
  final bool busy;
  final AppNotice? notice;
  final bool canWrite;
  final bool canRetire;
  final bool canEdit;
  final bool canView;

  /// Whether this session may correct a stock figure. See its derivation.
  final bool canAdjust;
  final bool canViewCost;
  final VoidCallback? onBulk;
  final TextEditingController search;
  final String searchPrefix;
  final String? categoryFilter;
  final TenantProductStockFilter stockFilter;
  final int pageIndex;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String?> onCategoryFilterChanged;
  final ValueChanged<TenantProductStockFilter> onStockFilterChanged;
  final VoidCallback onOpenCategories;
  final VoidCallback onOpenAddProduct;
  final ValueChanged<TenantProduct> onView;
  final ValueChanged<TenantProduct> onAdjust;
  final ValueChanged<TenantProduct> onEdit;
  final ValueChanged<TenantProduct> onRetire;
  final VoidCallback onNextPage;
  final VoidCallback onPreviousPage;
  final TenantProductVisualBuilder? productVisualBuilder;

  bool get _hasActiveQuery =>
      searchPrefix.isNotEmpty ||
      categoryFilter != null ||
      stockFilter != TenantProductStockFilter.all;

  List<_InventoryProductAction> _actions(TenantProduct product) =>
      <_InventoryProductAction>[
        if (canView)
          _InventoryProductAction(
            label: 'View stock',
            icon: Icons.visibility_outlined,
            key: ValueKey('inventory-view-${product.id}'),
            onPressed: busy ? null : () => onView(product),
          ),
        if (canAdjust)
          _InventoryProductAction(
            label: 'Adjust stock',
            icon: Icons.tune,
            key: ValueKey('inventory-adjust-${product.id}'),
            onPressed: busy ? null : () => onAdjust(product),
          ),
        if (canEdit)
          _InventoryProductAction(
            label: 'Correct product',
            icon: Icons.edit_outlined,
            key: ValueKey('catalog-management-edit-${product.id}'),
            onPressed: busy ? null : () => onEdit(product),
          ),
        if (canRetire && canWrite)
          _InventoryProductAction(
            label: 'Retire product',
            icon: Icons.remove_shopping_cart_outlined,
            key: ValueKey('catalog-management-retire-${product.id}'),
            tier: AppButtonTier.destructive,
            onPressed: busy ? null : () => onRetire(product),
          ),
      ];

  Widget _visual(TenantProduct product) =>
      productVisualBuilder?.call(product) ??
      TenantProductVisual(product: product);

  Widget _actionHeader(BuildContext context, {required bool compact}) {
    final tokens = AppTokens.componentOf(context);
    final add = AppButton(
      key: const ValueKey('inventory-add-product'),
      label: 'Add product',
      icon: Icons.add,
      expand: compact,
      onPressed: busy ? null : onOpenAddProduct,
    );
    final bulkButton = onBulk == null
        ? null
        : AppButton(
            key: const ValueKey('catalog-management-bulk'),
            label: compact ? 'Bulk & import' : 'Bulk changes & import',
            icon: Icons.cloud_upload_outlined,
            expand: compact,
            onPressed: busy ? null : onBulk,
          );
    final Widget? bulk = bulkButton == null
        ? null
        : Semantics(
            label: 'Bulk changes & import',
            button: true,
            child: ExcludeSemantics(child: bulkButton),
          );
    final categories = AppButton(
      key: const ValueKey('inventory-categories'),
      label: 'Categories',
      icon: Icons.category_outlined,
      tier: AppButtonTier.primary,
      expand: compact,
      onPressed: busy ? null : onOpenCategories,
    );
    if (compact) {
      // **One full-width action over two halves, not three thirds.** The
      // primary act of this route is adding a product, and a third of a phone
      // is not enough width for its label to survive beside two others. The
      // pair below it stays horizontal: a two-action stack is what reads as an
      // arbitrary difference by device, and that is what this composition was
      // asked to stop doing.
      if (bulk == null) {
        return AppActionRow(
          expandActions: true,
          actions: <Widget>[add, categories],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          add,
          SizedBox(height: tokens.spacing.s12),
          AppActionRow(expandActions: true, actions: <Widget>[bulk, categories]),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        add,
        if (bulk != null) ...<Widget>[
          SizedBox(width: tokens.spacing.s12),
          bulk,
        ],
        SizedBox(width: tokens.spacing.s12),
        categories,
      ],
    );
  }

  Widget _filters(BuildContext context, {required bool compact}) {
    final tokens = AppTokens.componentOf(context);
    final category = categoryFilter ?? '';
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            key: const ValueKey('inventory-search'),
            controller: search,
            onChanged: onSearchChanged,
            style: tokens.typography.bodyMedium.copyWith(
              color: tokens.colors.text.primary,
            ),
            decoration: InputDecoration(
              hintText: 'Search SKU / Name...',
              hintStyle: tokens.typography.bodyMedium.copyWith(
                color: tokens.colors.text.tertiary,
              ),
              prefixIcon: Icon(
                Icons.qr_code_scanner,
                color: tokens.colors.text.secondary,
              ),
              filled: true,
              fillColor: tokens.colors.surface.raised,
              contentPadding: EdgeInsets.symmetric(
                horizontal: tokens.spacing.s12,
                vertical: tokens.spacing.s12,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(tokens.radius.lg),
                borderSide: BorderSide(
                  color: tokens.colors.surface.borderSubtle,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(tokens.radius.lg),
                borderSide: BorderSide(
                  color: tokens.colors.action.focusRing.color,
                  width: tokens.colors.action.focusRing.width,
                ),
              ),
            ),
          ),
          SizedBox(height: tokens.spacing.s12),
          Row(
            children: <Widget>[
              Expanded(
                child: _LegacyInventorySelect<String>(
                  key: const ValueKey('inventory-category-filter'),
                  semanticLabel: 'Filter products by category',
                  icon: Icons.category,
                  value: category,
                  items: <DropdownMenuItem<String>>[
                    const DropdownMenuItem<String>(
                      value: '',
                      child: Text('All categories'),
                    ),
                    for (final item in view.categories.items)
                      DropdownMenuItem<String>(
                        value: item.id,
                        child: Text(item.name),
                      ),
                  ],
                  onChanged: (value) => onCategoryFilterChanged(
                    value == null || value.isEmpty ? null : value,
                  ),
                ),
              ),
              SizedBox(width: tokens.spacing.s8),
              Expanded(
                child: _LegacyInventorySelect<TenantProductStockFilter>(
                  key: const ValueKey('inventory-stock-filter'),
                  semanticLabel: 'Filter products by stock',
                  icon: Icons.filter_alt,
                  value: stockFilter,
                  items: const <DropdownMenuItem<TenantProductStockFilter>>[
                    DropdownMenuItem<TenantProductStockFilter>(
                      value: TenantProductStockFilter.all,
                      child: Text('All'),
                    ),
                    DropdownMenuItem<TenantProductStockFilter>(
                      value: TenantProductStockFilter.aboveZero,
                      child: Text('Above zero'),
                    ),
                    DropdownMenuItem<TenantProductStockFilter>(
                      value: TenantProductStockFilter.atOrBelowZero,
                      child: Text('At/below zero'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) onStockFilterChanged(value);
                  },
                ),
              ),
            ],
          ),
        ],
      );
    }
    final searchControl = AppTextField(
      key: const ValueKey('inventory-search'),
      controller: search,
      label: 'Search products',
      leading: Icons.qr_code_scanner_outlined,
      helper: 'Type at least 2 characters from a name word or product code.',
      onChanged: onSearchChanged,
    );
    final categoryControl = AppSelect<String>(
      key: const ValueKey('inventory-category-filter'),
      label: 'Category',
      leading: Icons.category_outlined,
      value: category,
      items: <AppSelectItem<String>>[
        const AppSelectItem<String>(value: '', label: 'All categories'),
        for (final item in view.categories.items)
          AppSelectItem<String>(value: item.id, label: item.name),
      ],
      onChanged: (value) => onCategoryFilterChanged(
        value == null || value.isEmpty ? null : value,
      ),
    );
    final stockControl = AppSelect<TenantProductStockFilter>(
      key: const ValueKey('inventory-stock-filter'),
      label: 'Stock',
      leading: Icons.filter_alt_outlined,
      value: stockFilter,
      items: const <AppSelectItem<TenantProductStockFilter>>[
        AppSelectItem<TenantProductStockFilter>(
          value: TenantProductStockFilter.all,
          label: 'All',
        ),
        AppSelectItem<TenantProductStockFilter>(
          value: TenantProductStockFilter.aboveZero,
          label: 'Above zero',
        ),
        AppSelectItem<TenantProductStockFilter>(
          value: TenantProductStockFilter.atOrBelowZero,
          label: 'At/below zero',
        ),
      ],
      onChanged: (value) {
        if (value != null) onStockFilterChanged(value);
      },
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: searchControl),
        SizedBox(width: tokens.spacing.s12),
        SizedBox(width: 220, child: categoryControl),
        SizedBox(width: tokens.spacing.s12),
        SizedBox(width: 188, child: stockControl),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final wide = AppLayout.contract.isAtLeast(width, AppBreakpoint.medium);
    final expanded = AppLayout.contract.isAtLeast(
      width,
      AppBreakpoint.expanded,
    );
    final horizontalPadding = !wide
        ? tokens.spacing.s16
        : expanded
        ? tokens.spacing.s32
        : tokens.spacing.s24;
    final categoryNames = tenantCategoryNames(view.categories.items);
    final empty = Text(
      key: ValueKey(
        _hasActiveQuery
            ? 'inventory-no-matching-products'
            : 'inventory-empty-catalog',
      ),
      _hasActiveQuery
          ? 'No products match this search and filter combination.'
          : 'This catalog has no products yet.',
      textAlign: TextAlign.center,
      style: tokens.typography.bodyMedium.copyWith(
        color: tokens.colors.text.secondary,
      ),
    );
    return ListView(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        tokens.spacing.s8,
        horizontalPadding,
        tokens.spacing.s20,
      ),
      children: <Widget>[
        if (canWrite) _actionHeader(context, compact: !wide),
        if (notice case final answer?) ...<Widget>[
          SizedBox(height: tokens.spacing.s16),
          Callout(
            key: const ValueKey('catalog-management-notice'),
            status: answer.status,
            message: answer.message,
          ),
        ],
        SizedBox(height: tokens.spacing.s20),
        _filters(context, compact: !wide),
        SizedBox(height: tokens.spacing.s16),
        _InventoryProductList(
          products: view.products.items,
          categoryNames: categoryNames,
          showCost: canViewCost,
          empty: empty,
          actionsOf: _actions,
          visualOf: _visual,
        ),
        SizedBox(height: tokens.spacing.s12),
        Pagination(
          pageNumber: pageIndex + 1,
          previousKey: const ValueKey('catalog-management-previous-page'),
          pageKey: const ValueKey('catalog-management-page'),
          nextKey: const ValueKey('catalog-management-next-page'),
          onPrevious: pageIndex == 0 || busy ? null : onPreviousPage,
          onNext: view.products.hasMore && !busy ? onNextPage : null,
        ),
      ],
    );
  }
}

final class _LegacyInventorySelect<T> extends StatelessWidget {
  const _LegacyInventorySelect({
    super.key,
    required this.semanticLabel,
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String semanticLabel;
  final IconData icon;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Semantics(
      label: semanticLabel,
      button: true,
      child: Container(
        height: 52,
        padding: EdgeInsets.only(
          left: tokens.spacing.s12,
          right: tokens.spacing.s8,
        ),
        decoration: BoxDecoration(
          color: tokens.colors.surface.raised,
          borderRadius: BorderRadius.circular(tokens.radius.lg),
          border: Border.all(color: tokens.colors.surface.borderSubtle),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 18, color: tokens.colors.text.secondary),
            SizedBox(width: tokens.spacing.s8),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<T>(
                  value: value,
                  isExpanded: true,
                  isDense: true,
                  dropdownColor: tokens.colors.surface.raised,
                  icon: Icon(
                    Icons.expand_more,
                    color: tokens.colors.text.secondary,
                  ),
                  style: tokens.typography.bodyMedium.copyWith(
                    color: tokens.colors.text.primary,
                  ),
                  items: items,
                  onChanged: onChanged,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

@immutable
final class _InventoryProductAction {
  const _InventoryProductAction({
    required this.label,
    required this.icon,
    required this.key,
    required this.onPressed,
    this.tier = AppButtonTier.secondary,
  });

  final String label;
  final IconData icon;
  final Key key;
  final VoidCallback? onPressed;
  final AppButtonTier tier;
}

final class _InventoryProductList extends StatelessWidget {
  const _InventoryProductList({
    required this.products,
    required this.categoryNames,
    required this.showCost,
    required this.empty,
    required this.actionsOf,
    required this.visualOf,
  });

  final List<TenantProduct> products;
  final Map<String, String> categoryNames;
  final bool showCost;
  final Widget empty;
  final List<_InventoryProductAction> Function(TenantProduct product) actionsOf;
  final Widget Function(TenantProduct product) visualOf;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final table = AppLayout.contract.isAtLeast(width, AppBreakpoint.medium);
    final showCategory = AppLayout.contract.isAtLeast(
      width,
      AppBreakpoint.expanded,
    );
    final showExtended = width >= 1200;
    final contents = products.isEmpty
        ? Padding(padding: EdgeInsets.all(tokens.spacing.s32), child: empty)
        : table
        ? _InventoryProductTable(
            products: products,
            categoryNames: categoryNames,
            showCategory: showCategory,
            showCost: showCost && showExtended,
            showValue: showExtended,
            actionsOf: actionsOf,
            visualOf: visualOf,
          )
        : Padding(
            padding: EdgeInsets.symmetric(vertical: tokens.spacing.s4),
            child: Column(
              children: <Widget>[
                for (final product in products)
                  _InventoryProductCard(
                    product: product,
                    categoryName: tenantCategoryLabel(
                      product.categoryId,
                      names: categoryNames,
                    ),
                    actions: actionsOf(product),
                    visual: visualOf(product),
                  ),
              ],
            ),
          );
    return Container(
      key: ValueKey(
        table ? 'inventory-product-table' : 'inventory-product-cards',
      ),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: tokens.colors.surface.raised,
        borderRadius: BorderRadius.circular(tokens.radius.md),
        border: Border.all(color: tokens.colors.surface.borderSubtle),
      ),
      child: contents,
    );
  }
}

final class _InventoryProductCard extends StatelessWidget {
  const _InventoryProductCard({
    required this.product,
    required this.categoryName,
    required this.actions,
    required this.visual,
  });

  final TenantProduct product;
  final String categoryName;
  final List<_InventoryProductAction> actions;
  final Widget visual;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final standing = tenantProductStanding(product);
    return Container(
      key: ValueKey('catalog-management-product-${product.id}'),
      margin: EdgeInsets.symmetric(horizontal: tokens.spacing.s8, vertical: 6),
      padding: EdgeInsets.all(tokens.spacing.s12),
      decoration: BoxDecoration(
        color: tokens.colors.surface.base,
        borderRadius: BorderRadius.circular(tokens.radius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox.square(dimension: tokens.spacing.s64, child: visual),
              SizedBox(width: tokens.spacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.typography.bodyLarge.copyWith(
                        color: tokens.colors.text.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: tokens.spacing.s4),
                    Text(
                      'SKU: ${product.sku}',
                      key: ValueKey(
                        'catalog-management-product-code-${product.id}',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.typography.mono.copyWith(
                        color: tokens.colors.text.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (standing != null) ...<Widget>[
                SizedBox(width: tokens.spacing.s8),
                StatusBadge(
                  key: standing.badgeKey,
                  status: standing.status,
                  label: standing.label,
                  icon: standing.icon,
                  semanticLabel: standing.semanticLabel,
                ),
              ],
            ],
          ),
          SizedBox(height: tokens.spacing.s12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: _InventoryProductMetric(
                  label: 'Category',
                  value: categoryName,
                  valueKey: ValueKey(
                    'catalog-management-category-of-${product.id}',
                  ),
                  money: false,
                  monospace: false,
                ),
              ),
              SizedBox(width: tokens.spacing.s8),
              SizedBox(
                width: 44,
                child: _InventoryProductMetric(
                  label: 'In stock',
                  value: '${product.quantity}',
                  valueKey: ValueKey(
                    'catalog-management-product-stock-${product.id}',
                  ),
                  money: false,
                ),
              ),
              SizedBox(width: tokens.spacing.s8),
              SizedBox(
                width: 56,
                child: _InventoryProductMetric(
                  label: 'Price',
                  value: product.price.toStringAsFixed(2),
                  valueKey: ValueKey(
                    'catalog-management-product-price-${product.id}',
                  ),
                  money: true,
                ),
              ),
              if (actions.isNotEmpty) ...<Widget>[
                SizedBox(width: tokens.spacing.s8),
                _InventoryProductActions(
                  actions: actions,
                  menuKey: ValueKey('inventory-actions-${product.id}'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

final class _InventoryProductMetric extends StatelessWidget {
  const _InventoryProductMetric({
    required this.label,
    required this.value,
    required this.valueKey,
    required this.money,
    this.monospace = true,
  });

  final String label;
  final String value;
  final Key valueKey;
  final bool money;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tokens.typography.caption.copyWith(
            color: tokens.colors.text.tertiary,
          ),
        ),
        SizedBox(height: tokens.spacing.s4),
        Text(
          value,
          key: valueKey,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:
              (monospace
                      ? tokens.typography.mono
                      : tokens.typography.bodyMedium)
                  .copyWith(
                    color: money
                        ? tokens.colors.text.money
                        : tokens.colors.text.secondary,
                  ),
        ),
      ],
    );
  }
}

final class _InventoryProductActions extends StatelessWidget {
  const _InventoryProductActions({
    required this.actions,
    required this.menuKey,
  });

  static const double menuExtent = 64;

  final List<_InventoryProductAction> actions;
  final Key menuKey;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return PopupMenuButton<int>(
      key: menuKey,
      tooltip: 'Product actions',
      icon: const Icon(Icons.more_vert),
      color: tokens.colors.surface.raised,
      onSelected: (index) => actions[index].onPressed?.call(),
      itemBuilder: (context) => <PopupMenuEntry<int>>[
        for (final (index, action) in actions.indexed)
          PopupMenuItem<int>(
            key: action.key,
            value: index,
            enabled: action.onPressed != null,
            child: Row(
              children: <Widget>[
                Icon(
                  action.icon,
                  size: 20,
                  color: action.tier == AppButtonTier.destructive
                      ? tokens.colors.action.destructive.label
                      : tokens.colors.text.secondary,
                ),
                SizedBox(width: tokens.spacing.s12),
                Text(
                  action.label,
                  style: tokens.typography.bodyMedium.copyWith(
                    color: action.tier == AppButtonTier.destructive
                        ? tokens.colors.action.destructive.label
                        : tokens.colors.text.primary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

final class _InventoryProductTable extends StatelessWidget {
  const _InventoryProductTable({
    required this.products,
    required this.categoryNames,
    required this.showCategory,
    required this.showCost,
    required this.showValue,
    required this.actionsOf,
    required this.visualOf,
  });

  final List<TenantProduct> products;
  final Map<String, String> categoryNames;
  final bool showCategory;
  final bool showCost;
  final bool showValue;
  final List<_InventoryProductAction> Function(TenantProduct product) actionsOf;
  final Widget Function(TenantProduct product) visualOf;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final hasActions = actionsOf(products.first).isNotEmpty;
    final actionWidth = !hasActions ? 0.0 : _InventoryProductActions.menuExtent;
    return Column(
      children: <Widget>[
        Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: tokens.colors.surface.borderSubtle),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: showCategory
                  ? tokens.spacing.s24
                  : tokens.spacing.s16,
              vertical: tokens.spacing.s16,
            ),
            child: _InventoryProductTableColumns(
              showCategory: showCategory,
              showCost: showCost,
              showValue: showValue,
              actionWidth: actionWidth,
              product: const _InventoryTableHeader('Product'),
              category: const _InventoryTableHeader('Category'),
              stock: const _InventoryTableHeader('In stock'),
              price: const _InventoryTableHeader('Unit price'),
              cost: const _InventoryTableHeader('Unit cost'),
              value: const _InventoryTableHeader('Retail value'),
              actions: const _InventoryTableHeader(
                'Actions',
                alignment: TextAlign.end,
              ),
            ),
          ),
        ),
        for (final (index, product) in products.indexed)
          _InventoryProductTableRow(
            product: product,
            categoryName: tenantCategoryLabel(
              product.categoryId,
              names: categoryNames,
            ),
            showCategory: showCategory,
            showCost: showCost,
            showValue: showValue,
            actionWidth: actionWidth,
            actions: actionsOf(product),
            visual: visualOf(product),
            showDivider: index != products.length - 1,
          ),
      ],
    );
  }
}

final class _InventoryProductTableColumns extends StatelessWidget {
  const _InventoryProductTableColumns({
    required this.showCategory,
    required this.showCost,
    required this.showValue,
    required this.actionWidth,
    required this.product,
    required this.category,
    required this.stock,
    required this.price,
    required this.cost,
    required this.value,
    required this.actions,
  });

  final bool showCategory;
  final bool showCost;
  final bool showValue;
  final double actionWidth;
  final Widget product;
  final Widget category;
  final Widget stock;
  final Widget price;
  final Widget cost;
  final Widget value;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Row(
      children: <Widget>[
        Expanded(flex: showCategory ? 4 : 5, child: product),
        SizedBox(width: tokens.spacing.s16),
        if (showCategory) ...<Widget>[
          Expanded(flex: 2, child: category),
          SizedBox(width: tokens.spacing.s16),
        ],
        Expanded(child: stock),
        SizedBox(width: tokens.spacing.s16),
        Expanded(flex: 2, child: price),
        if (showCost) ...<Widget>[
          SizedBox(width: tokens.spacing.s16),
          Expanded(flex: 2, child: cost),
        ],
        if (showValue) ...<Widget>[
          SizedBox(width: tokens.spacing.s16),
          Expanded(flex: 2, child: value),
        ],
        if (actionWidth > 0) ...<Widget>[
          SizedBox(width: tokens.spacing.s16),
          SizedBox(width: actionWidth, child: actions),
        ],
      ],
    );
  }
}

final class _InventoryTableHeader extends StatelessWidget {
  const _InventoryTableHeader(this.label, {this.alignment = TextAlign.start});

  final String label;
  final TextAlign alignment;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Text(
      label.toUpperCase(),
      textAlign: alignment,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: tokens.typography.labelEyebrow.copyWith(
        color: tokens.colors.text.tertiary,
      ),
    );
  }
}

final class _InventoryProductTableRow extends StatelessWidget {
  const _InventoryProductTableRow({
    required this.product,
    required this.categoryName,
    required this.showCategory,
    required this.showCost,
    required this.showValue,
    required this.actionWidth,
    required this.actions,
    required this.visual,
    required this.showDivider,
  });

  final TenantProduct product;
  final String categoryName;
  final bool showCategory;
  final bool showCost;
  final bool showValue;
  final double actionWidth;
  final List<_InventoryProductAction> actions;
  final Widget visual;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final standing = tenantProductStanding(product);
    return Container(
      key: ValueKey('catalog-management-product-${product.id}'),
      padding: EdgeInsets.symmetric(
        horizontal: showCategory ? tokens.spacing.s24 : tokens.spacing.s16,
        vertical: showCategory ? tokens.spacing.s16 : tokens.spacing.s12,
      ),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(
                bottom: BorderSide(color: tokens.colors.surface.borderSubtle),
              )
            : null,
      ),
      child: _InventoryProductTableColumns(
        showCategory: showCategory,
        showCost: showCost,
        showValue: showValue,
        actionWidth: actionWidth,
        product: Row(
          children: <Widget>[
            SizedBox.square(dimension: tokens.spacing.s48, child: visual),
            SizedBox(width: tokens.spacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.typography.bodyLarge.copyWith(
                      color: tokens.colors.text.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: tokens.spacing.s4),
                  if (showCategory)
                    Text(
                      'SKU: ${product.sku}',
                      key: ValueKey(
                        'catalog-management-product-code-${product.id}',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.typography.mono.copyWith(
                        color: tokens.colors.text.secondary,
                      ),
                    )
                  else
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            'SKU: ${product.sku}',
                            key: ValueKey(
                              'catalog-management-product-code-${product.id}',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tokens.typography.mono.copyWith(
                              color: tokens.colors.text.secondary,
                            ),
                          ),
                        ),
                        Text(
                          ' • ',
                          style: tokens.typography.caption.copyWith(
                            color: tokens.colors.text.tertiary,
                          ),
                        ),
                        Flexible(
                          child: Text(
                            categoryName,
                            key: ValueKey(
                              'catalog-management-category-of-${product.id}',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tokens.typography.caption.copyWith(
                              color: tokens.colors.text.secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (standing != null) ...<Widget>[
              SizedBox(width: tokens.spacing.s8),
              StatusBadge(
                key: standing.badgeKey,
                status: standing.status,
                label: standing.label,
                icon: standing.icon,
                semanticLabel: standing.semanticLabel,
              ),
            ],
          ],
        ),
        category: Text(
          categoryName,
          key: ValueKey('catalog-management-category-of-${product.id}'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tokens.typography.bodyMedium.copyWith(
            color: tokens.colors.text.secondary,
          ),
        ),
        stock: Text(
          '${product.quantity}',
          key: ValueKey('catalog-management-product-stock-${product.id}'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tokens.typography.mono.copyWith(
            color: tokens.colors.text.secondary,
          ),
        ),
        price: Text(
          product.price.toStringAsFixed(2),
          key: ValueKey('catalog-management-product-price-${product.id}'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tokens.typography.mono.copyWith(
            color: tokens.colors.text.money,
          ),
        ),
        cost: Text(
          product.cost?.toStringAsFixed(2) ?? '—',
          key: ValueKey('catalog-management-product-cost-${product.id}'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tokens.typography.mono.copyWith(
            color: product.cost == null
                ? tokens.colors.text.tertiary
                : tokens.colors.text.secondary,
          ),
        ),
        value: Text(
          (product.price * product.quantity).toStringAsFixed(2),
          key: ValueKey('catalog-management-product-value-${product.id}'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tokens.typography.mono.copyWith(
            color: tokens.colors.text.money,
          ),
        ),
        actions: Align(
          alignment: Alignment.centerRight,
          child: _InventoryProductActions(
            actions: actions,
            menuKey: ValueKey('inventory-actions-${product.id}'),
          ),
        ),
      ),
    );
  }
}

AppNotice _categoryNotice(
  TenantCatalogWriteResult result,
) => switch (result.kind) {
  TenantCatalogWriteKind.committed => const AppNotice.confirmed(
    'Category added. It can be chosen for a product straight away.',
  ),
  TenantCatalogWriteKind.rejected => const AppNotice.refused(
    'The category was refused and nothing was written. Only an owner, '
    'administrator, or manager may change the catalog.',
  ),
  TenantCatalogWriteKind.ambiguous => const AppNotice.unknown(
    'The result is unknown. The categories above have been re-read; if it is '
    'not listed, add it again - the retry addresses the same document, so '
    'it cannot be added twice.',
  ),
  TenantCatalogWriteKind.unavailable => const AppNotice.offline(
    'This device is offline, so nothing was written. The catalog can only be '
    'changed while online.',
  ),
};

AppNotice _categoryRenameNotice(TenantCatalogWriteResult result) =>
    switch (result.kind) {
      TenantCatalogWriteKind.committed => const AppNotice.confirmed(
        'Category renamed. Existing products remain filed under it.',
      ),
      TenantCatalogWriteKind.rejected => const AppNotice.refused(
        'The category rename was refused and nothing was changed.',
      ),
      TenantCatalogWriteKind.ambiguous => const AppNotice.unknown(
        'The rename result is unknown. Categories have been re-read.',
      ),
      TenantCatalogWriteKind.unavailable => const AppNotice.offline(
        'This device is offline, so the category was not renamed.',
      ),
    };

AppNotice _imageNotice(TenantProductImageException error) =>
    switch (error.code) {
      'invalid_image_size' => const AppNotice.refused(
        'Choose an image no larger than 5 MiB.',
      ),
      'unsupported_image_type' => const AppNotice.refused(
        'Choose a JPEG, PNG, or WebP image.',
      ),
      _ => const AppNotice.refused(
        'The product image could not be uploaded. Nothing was written.',
      ),
    };

AppNotice _productNotice(TenantCatalogWriteResult result) =>
    switch (result.kind) {
      TenantCatalogWriteKind.committed => const AppNotice.confirmed(
        'Product added, holding no stock. Record its opening quantity from the '
        'product itself so the ledger says where those units came from. This '
        'device re-reads the catalog on its next sync, and every other device '
        'picks it up when it syncs.',
      ),
      TenantCatalogWriteKind.rejected => const AppNotice.refused(
        'The product was refused and nothing was written. Only an owner, '
        'administrator, or manager may change the catalog, and an entry that '
        'already exists is never overwritten.',
      ),
      TenantCatalogWriteKind.ambiguous => const AppNotice.unknown(
        'The result is unknown. The catalog below has been re-read; if the '
        'product is not listed, add it again - the retry addresses the same '
        'document, so it cannot be stocked twice.',
      ),
      TenantCatalogWriteKind.unavailable => const AppNotice.offline(
        'This device is offline, so nothing was written. The catalog can only '
        'be changed while online.',
      ),
    };

AppNotice _retireNotice(
  TenantCatalogWriteResult result,
  TenantProductRetireIntent intent,
) => switch (result.kind) {
  TenantCatalogWriteKind.committed => AppNotice.confirmed(
    '${intent.name} is retired. Its stock ledger and every sale that already '
    'named it are untouched.',
  ),
  TenantCatalogWriteKind.rejected => const AppNotice.refused(
    'Nothing was retired. Only an owner or administrator may retire a product.',
  ),
  TenantCatalogWriteKind.ambiguous => const AppNotice.unknown(
    'The result is unknown. The catalog below has been re-read; if the product '
    'is still listed, retire it again - retiring the same product twice '
    'does nothing further.',
  ),
  TenantCatalogWriteKind.unavailable => const AppNotice.offline(
    'This device is offline, so nothing was retired. The catalog can only be '
    'changed while online.',
  ),
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

AppNotice _updateNotice(TenantProductUpdateResult result) =>
    AppNotice.confirmed(_updateMessage(result));

String _updateMessage(TenantProductUpdateResult result) {
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

/// **Ten refusals, one unknown, and one that is neither.**
/// `unchanged` is `info` rather than `problem`: the product already holds every
/// value in the correction, so the operator's intent is satisfied and the
/// sentence's own point is that there was nothing to do. It is deliberately not
/// `neutral`, which the bulk report gives an *unchanged row* — a row that is out
/// of play and a page that has nothing to report are two different claims, and
/// one status meaning both at two scales is the failure §2.1 exists to end.
AppNotice _updateFailureNotice(TenantProductUpdateFailure failure) =>
    switch (failure) {
      TenantProductUpdateFailure.forbidden => const AppNotice.refused(
        'Only an owner, administrator, or manager may correct a product, and '
        'nothing was changed.',
      ),
      TenantProductUpdateFailure.priceForbidden => const AppNotice.refused(
        'Only an owner or administrator may change a price. Nothing was '
        'changed, including the fields that are not money.',
      ),
      TenantProductUpdateFailure.costForbidden => const AppNotice.refused(
        'Only an owner or administrator may change what a product costs. '
        'Nothing was changed, including the fields that are not money.',
      ),
      TenantProductUpdateFailure.productMissing => const AppNotice.refused(
        'This product no longer exists in this business, so nothing was '
        'changed.',
      ),
      TenantProductUpdateFailure.categoryMissing => const AppNotice.refused(
        'That category no longer exists in this business. Nothing was changed; '
        'the categories above have been re-read.',
      ),
      TenantProductUpdateFailure.unchanged => const AppNotice.offline(
        'The product already holds every value in this correction, so nothing '
        'was changed. Somebody else may have made the same correction.',
      ),
      TenantProductUpdateFailure.productUnreadable => const AppNotice.refused(
        'This product holds a value no device can read, and a correction has '
        'to repair every one of them at once. Nothing was changed. Correct '
        'each field on this form together and save again.',
      ),
      TenantProductUpdateFailure.needsOperator => const AppNotice.refused(
        'This product is stored in a state no correction can repair - its '
        'stock quantity or its image. Nothing was changed, and it needs an '
        'operator.',
      ),
      TenantProductUpdateFailure.duplicateRequest => const AppNotice.refused(
        'An earlier attempt already used this correction. Nothing was changed '
        'a second time; re-read the catalog below and start again.',
      ),
      TenantProductUpdateFailure.invalidRequest => const AppNotice.refused(
        'The server refused this correction as malformed and nothing was '
        'changed. This build and the server disagree about what a product '
        'may hold.',
      ),
      TenantProductUpdateFailure.refused => const AppNotice.refused(
        'The correction was refused and nothing was changed.',
      ),
      TenantProductUpdateFailure.ambiguous => const AppNotice.unknown(
        'The result is unknown. The catalog below has been re-read; if the '
        'correction is not there, save it again - repeating the same '
        'correction cannot apply it twice.',
      ),
    };

/// The client refusing before anything was sent — **with one exception, and it
/// is the same exception the server's own `unchanged` is.**
/// `product_unchanged` means the form holds nothing the product does not
/// already hold, so there was nothing to correct: the operator's intent is
/// satisfied and reporting it in red would claim a fault that does not exist.
/// Every other code is a genuine refusal of a genuine change.
AppNotice _refusalNotice(String code) => code == 'product_unchanged'
    ? AppNotice.offline(_refusalMessage(code))
    : AppNotice.refused(_refusalMessage(code));

String _refusalMessage(String code) => switch (code) {
  'invalid_category_name' =>
    'Enter a category name of at most $maximumCatalogNameLength characters.',
  'category_unchanged' =>
    'The category already has that name, so nothing was changed.',
  'invalid_product_image' =>
    'The product image address is invalid, so nothing was written.',
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

/// The shared full-screen frame for adding and correcting one product.
///
/// The form and its image are one continuous surface. The action pair stays
/// fixed, horizontal, and reachable while the form itself scrolls.
/// The body of a product form: the fields, and the controls that submit them.
///
/// **A sheet body rather than a route since 2026-08-26.** It was an
/// `AppScaffold` with the fields in a `ListView` and the actions pinned under
/// them; the actions and the scroll are unchanged, and what left is the page
/// chrome - a sheet supplies its own.
final class _CatalogProductFormScreen extends StatelessWidget {
  const _CatalogProductFormScreen({
    required this.screenKey,
    required this.scrollKey,
    required this.title,
    this.subtitle,
    required this.form,
    required this.actions,
    this.scrollController,
    this.showsHeader = true,
  });

  final Key screenKey;
  final Key scrollKey;
  final String title;
  final String? subtitle;
  final Widget form;
  final List<Widget> actions;

  /// The sheet's own controller, so dragging the form drags the sheet. Null
  /// where this is still pumped as a page, which is how its tests reach it.
  final ScrollController? scrollController;

  /// Drawn above the fields where the sheet has no masthead to carry it.
  ///
  /// **§7's "title appears once", read across two arrangements.** A sheet has
  /// no app bar, so the errand has to be named inside it - except on the
  /// compact sheet, where the masthead is the picture and the header sits
  /// above the fields under it. Either way it is stated exactly once.
  final bool showsHeader;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return KeyedSubtree(
      key: screenKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            // **The fields scroll, not the sheet.** The sheet's own drag is
            // coupled to this controller, so a form taller than the sheet
            // scrolls its fields under a masthead that stays put - rather than
            // putting a second scrollbar on a surface that already has one.
            child: ListView(
              key: scrollKey,
              controller: scrollController,
              padding: EdgeInsets.fromLTRB(
                tokens.spacing.s20,
                showsHeader ? tokens.spacing.s8 : tokens.spacing.s16,
                tokens.spacing.s20,
                tokens.spacing.s24,
              ),
              children: <Widget>[
                if (showsHeader) ...<Widget>[
                  PageHeader(title: title, subtitle: subtitle),
                  SizedBox(height: tokens.spacing.s16),
                ],
                form,
              ],
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.colors.surface.base,
              border: Border(
                top: BorderSide(color: tokens.colors.surface.borderSubtle),
              ),
            ),
            child: SafeArea(
              top: false,
              minimum: EdgeInsets.fromLTRB(
                tokens.spacing.s20,
                tokens.spacing.s12,
                tokens.spacing.s20,
                tokens.spacing.s12,
              ),
              child: AppActionRow(expandActions: true, actions: actions),
            ),
          ),
        ],
      ),
    );
  }
}

final class _AddProductScreen extends StatefulWidget {
  const _AddProductScreen({
    required this.categories,
    required this.moreCategories,
    required this.name,
    required this.sku,
    required this.price,
    required this.cost,
    required this.canRecordCost,
    required this.selectedCategoryId,
    required this.image,
    required this.busy,
    required this.onCategorySelected,
    required this.onChooseImage,
    required this.onImageChanged,
    required this.session,
    required this.backgroundRemover,
    this.scrollController,
    this.preview,
  });

  final List<TenantCategory> categories;
  final bool moreCategories;
  final TextEditingController name;
  final TextEditingController sku;
  final TextEditingController price;
  final TextEditingController cost;
  final bool canRecordCost;
  final String? selectedCategoryId;
  final TenantProductImageCandidate? image;
  final bool busy;
  final ValueChanged<String> onCategorySelected;
  final Future<TenantProductImageCandidate?> Function()? onChooseImage;
  final ValueChanged<TenantProductImageCandidate?> onImageChanged;

  /// Both only so the image well can decide whether to offer a cut-out; this
  /// form neither reads nor writes anything else through them.
  final TenantSession session;
  final TenantProductBackgroundRemover? backgroundRemover;

  /// The sheet's own controller, which must reach the scrollable this builds or
  /// dragging the form scrolls the form and the sheet never moves.
  final ScrollController? scrollController;

  /// Published so the sheet's masthead can paint the same picture this form is
  /// changing. Null in the wide arrangement, which draws its own.
  /// See [_ProductImagePreviewModel].
  final _ProductImagePreviewModel? preview;

  @override
  State<_AddProductScreen> createState() => _AddProductScreenState();
}

final class _AddProductScreenState extends State<_AddProductScreen> {
  late String _categoryId =
      widget.categories.any(
        (category) => category.id == widget.selectedCategoryId,
      )
      ? widget.selectedCategoryId!
      : '';
  late TenantProductImageCandidate? _image = widget.image;

  bool get _canSubmit =>
      !widget.busy &&
      widget.name.text.trim().isNotEmpty &&
      widget.sku.text.trim().isNotEmpty &&
      widget.price.text.trim().isNotEmpty &&
      _categoryId.isNotEmpty;

  void _acceptImage(TenantProductImageCandidate candidate) {
    setState(() => _image = candidate);
    widget.onImageChanged(candidate);
    // Alongside `setState` rather than instead of it: this form stays
    // authoritative and the model carries only what the masthead paints.
    widget.preview?.show(candidate);
  }

  void _removeImage() {
    setState(() => _image = null);
    widget.onImageChanged(null);
    widget.preview?.show(null);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final choose = widget.onChooseImage;
    // A masthead means the sheet is already showing the picture, so the well
    // below draws its controls and nothing else - and the fields sit in one
    // column under it rather than beside a second copy of the image.
    final hasMasthead = widget.preview != null;
    return _CatalogProductFormScreen(
      screenKey: const ValueKey('catalog-management-add-screen'),
      scrollKey: const ValueKey('catalog-management-add-scroll'),
      title: 'Add product',
      scrollController: widget.scrollController,
      showsHeader: !hasMasthead,
      form: _FormWithImageWell(
        stacked: hasMasthead,
        well: choose == null
            ? null
            : _ProductImageWell(
                showsPreview: !hasMasthead,
                image: _image,
                savedImageRemoved: false,
                remover: widget.backgroundRemover,
                session: widget.session,
                onChoose: choose,
                onImageChanged: _acceptImage,
                onRemoveImage: _image == null ? null : _removeImage,
              ),
        fields: <Widget>[
          AppTextField(
            key: const ValueKey('catalog-management-product-name'),
            controller: widget.name,
            enabled: !widget.busy,
            maxLength: maximumCatalogNameLength,
            onChanged: (_) => setState(() {}),
            label: 'Product name',
          ),
          SizedBox(height: tokens.spacing.s8),
          AppTextField(
            key: const ValueKey('catalog-management-product-sku'),
            controller: widget.sku,
            enabled: !widget.busy,
            maxLength: maximumCatalogSkuLength,
            onChanged: (_) => setState(() {}),
            label: 'Code (SKU or barcode)',
            leading: Icons.tag,
            helper: 'What the till matches a scan against. No spaces.',
          ),
          SizedBox(height: tokens.spacing.s8),
          AppTextField(
            key: const ValueKey('catalog-management-product-price'),
            controller: widget.price,
            enabled: !widget.busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            label: 'Unit price',
            leading: Icons.payments_outlined,
          ),
          if (widget.canRecordCost) ...<Widget>[
            SizedBox(height: tokens.spacing.s8),
            AppTextField(
              key: const ValueKey('catalog-management-product-cost'),
              controller: widget.cost,
              enabled: !widget.busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              label: 'Unit cost (optional)',
              leading: Icons.payments_outlined,
            ),
          ],
          SizedBox(height: tokens.spacing.s8),
          AppSelect<String>(
            key: const ValueKey('catalog-management-product-category'),
            label: 'Category',
            value: _categoryId,
            helper: widget.moreCategories
                ? 'More categories exist; this list shows the first page.'
                : null,
            items: <AppSelectItem<String>>[
              const AppSelectItem<String>(value: '', label: 'Choose category'),
              for (final category in widget.categories)
                AppSelectItem<String>(
                  value: category.id,
                  label: category.name,
                  key: ValueKey('catalog-management-category-${category.id}'),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _categoryId = value);
              if (value.isNotEmpty) widget.onCategorySelected(value);
            },
          ),
        ],
      ),
      actions: <Widget>[
        AppButton(
          key: const ValueKey('catalog-management-add-cancel'),
          label: 'Cancel',
          tier: AppButtonTier.tertiary,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton(
          key: const ValueKey('catalog-management-add-product'),
          label: 'Add product',
          icon: Icons.add_box_outlined,
          tier: AppButtonTier.primary,
          onPressed: _canSubmit ? () => Navigator.of(context).pop(true) : null,
        ),
      ],
    );
  }
}

final class _RenameCategoryDialog extends StatefulWidget {
  const _RenameCategoryDialog({required this.category});

  final TenantCategory category;

  @override
  State<_RenameCategoryDialog> createState() => _RenameCategoryDialogState();
}

final class _RenameCategoryDialogState extends State<_RenameCategoryDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.category.name,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: 'Rename category',
    content: AppTextField(
      key: const ValueKey('catalog-management-rename-category-name'),
      controller: _name,
      maxLength: maximumCatalogNameLength,
      label: 'Category name',
    ),
    actions: <Widget>[
      AppButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
      AppButton(
        key: const ValueKey('catalog-management-rename-category-save'),
        label: 'Rename category',
        tier: AppButtonTier.primary,
        onPressed: () => Navigator.of(context).pop(_name.text),
      ),
    ],
  );
}

final class _CategoriesDialog extends StatefulWidget {
  const _CategoriesDialog({
    required this.session,
    required this.reader,
    required this.writer,
    required this.pageSize,
    required this.name,
    required this.busy,
    required this.onAdd,
    required this.onRename,
  });

  final TenantSession session;
  final TenantDataReader reader;
  final TenantCatalogWriter? writer;
  final int pageSize;
  final TextEditingController name;
  final bool busy;
  final Future<void> Function() onAdd;
  final Future<void> Function(TenantCategory category) onRename;

  @override
  State<_CategoriesDialog> createState() => _CategoriesDialogState();
}

final class _CategoriesDialogState extends State<_CategoriesDialog> {
  List<String?> _cursors = <String?>[null];
  int _page = 0;
  int _generation = 0;
  bool _working = false;

  Future<TenantCatalogPage<TenantCategory>> _load() => TenantCatalogRepository(
    session: widget.session,
    reader: widget.reader,
  ).loadCategories(pageSize: widget.pageSize, cursor: _cursors[_page]);

  Future<void> _run(Future<void> Function() action) async {
    if (_working || widget.busy) return;
    setState(() => _working = true);
    try {
      await action();
      if (mounted) setState(() => _generation++);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return AppDialog(
      title: 'Categories',
      content: FutureBuilder<TenantCatalogPage<TenantCategory>>(
        key: ValueKey('inventory-category-page-$_page-$_generation'),
        future: _load(),
        builder: (context, snapshot) {
          final page = snapshot.data;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (snapshot.connectionState != ConnectionState.done)
                const Center(child: CircularProgressIndicator())
              else if (snapshot.hasError)
                const Text('Categories could not be read.')
              else if (page == null || page.items.isEmpty)
                const Text('No categories on this page.')
              else
                for (final category in page.items) ...<Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(child: Text(category.name)),
                      AppButton(
                        key: ValueKey('inventory-rename-${category.id}'),
                        label: 'Rename',
                        icon: Icons.edit_outlined,
                        onPressed: _working
                            ? null
                            : () => _run(() => widget.onRename(category)),
                      ),
                    ],
                  ),
                  SizedBox(height: tokens.spacing.s8),
                ],
              if (page != null) ...<Widget>[
                Pagination(
                  pageNumber: _page + 1,
                  onPrevious: _page == 0 || _working
                      ? null
                      : () => setState(() => _page--),
                  onNext: page.hasMore && !_working
                      ? () => setState(() {
                          _cursors = <String?>[
                            ..._cursors.take(_page + 1),
                            page.nextCursor,
                          ];
                          _page++;
                        })
                      : null,
                ),
              ],
              if (widget.writer != null) ...<Widget>[
                SizedBox(height: tokens.spacing.s16),
                AppTextField(
                  key: const ValueKey('catalog-management-category-name'),
                  controller: widget.name,
                  maxLength: maximumCatalogNameLength,
                  label: 'New category name',
                  onChanged: (_) => setState(() {}),
                ),
                SizedBox(height: tokens.spacing.s8),
                AppButton(
                  key: const ValueKey('catalog-management-add-category'),
                  label: 'Add category',
                  icon: Icons.new_label_outlined,
                  tier: AppButtonTier.primary,
                  onPressed: _working || widget.name.text.trim().isEmpty
                      ? null
                      : () => _run(widget.onAdd),
                ),
              ],
            ],
          );
        },
      ),
      actions: <Widget>[
        AppButton(
          label: 'Close',
          onPressed: _working ? null : () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

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
    required this.image,
    required this.removeImage,
  });

  final String name;
  final String sku;
  final String categoryId;
  final String? price;
  final String? cost;

  /// Clearing a recorded cost is its own act, never an empty cost field. An
  /// omitted cost leaves the stored figure alone; this removes it.
  final bool clearCost;
  final TenantProductImageCandidate? image;
  final bool removeImage;

  /// Identifies this exact correction, so a retained request ID can be held
  /// against the correction it was issued for and no other.
  String fingerprint(String productId) => <String>[
    productId,
    name,
    sku,
    categoryId,
    price ?? '',
    cost ?? '',
    '$clearCost',
    image?.fileName ?? '',
    '${image?.bytes.length ?? 0}',
    '$removeImage',
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
final class _EditProductScreen extends StatefulWidget {
  const _EditProductScreen({
    required this.product,
    required this.categories,
    required this.moreCategories,
    required this.canChangeMoney,
    required this.canChangeImage,
    required this.onChooseImage,
    required this.session,
    required this.backgroundRemover,
    this.scrollController,
    this.preview,
  });

  final TenantProduct product;
  final List<TenantCategory> categories;

  /// Whether more categories exist than were read, in which case a product can
  /// only be moved into one of those offered.
  final bool moreCategories;

  final bool canChangeMoney;
  final bool canChangeImage;
  final Future<TenantProductImageCandidate?> Function() onChooseImage;

  /// Both only so the image well can decide whether to offer a cut-out.
  final TenantSession session;
  final TenantProductBackgroundRemover? backgroundRemover;

  /// The sheet's own controller, which must reach the scrollable this builds or
  /// dragging the form scrolls the form and the sheet never moves.
  final ScrollController? scrollController;

  /// Published so the sheet's masthead can paint the same picture this form is
  /// changing. Null in the wide arrangement, which draws its own.
  /// See [_ProductImagePreviewModel].
  final _ProductImagePreviewModel? preview;

  @override
  State<_EditProductScreen> createState() => _EditProductScreenState();
}

final class _EditProductScreenState extends State<_EditProductScreen> {
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
  TenantProductImageCandidate? _image;
  bool _removeImage = false;

  void _acceptImage(TenantProductImageCandidate candidate) {
    setState(() {
      _image = candidate;
      _removeImage = false;
    });
    // Alongside `setState` rather than instead of it: this form stays
    // authoritative and the model carries only what the masthead paints.
    widget.preview?.show(candidate);
  }

  /// Whether there is anything for *Remove image* to act on: a photograph
  /// chosen here, or a saved one this correction has not already dropped.
  bool get _hasImageToRemove =>
      _image != null || (widget.product.imageUrl != null && !_removeImage);

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
    final tokens = AppTokens.componentOf(context);
    // The form is one continuous page surface; its image section is not a
    // raised card nested inside a modal card.
    final hasMasthead = widget.preview != null;
    final form = _FormWithImageWell(
      stacked: hasMasthead,
      well: widget.canChangeImage
          ? _ProductImageWell(
              showsPreview: !hasMasthead,
              product: widget.product,
              image: _image,
              savedImageRemoved: _removeImage,
              remover: widget.backgroundRemover,
              session: widget.session,
              onChoose: widget.onChooseImage,
              onImageChanged: _acceptImage,
              onRemoveImage: _hasImageToRemove
                  ? () {
                      setState(() {
                        _image = null;
                        _removeImage = true;
                      });
                      // `savedRemoved` so the masthead stops showing the saved
                      // photograph too: dropping the picture must look like
                      // dropping it, not like reverting to the old one.
                      widget.preview?.show(null, savedRemoved: true);
                    }
                  : null,
            )
          : null,
      fields: [
        // A permanent helper paragraph, true of every correction this
        // dialog will ever make, so it folds. A dialog is the place where
        // the height it costs is worth most: what a person came here to do
        // is edit five fields, and the explanation of how they are checked
        // is read once and then never again.
        //
        // **The summary is short because a dialog is not a page.** This
        // shipped as `How a correction is checked` - 27 characters, inside
        // `Disclosure.summaryCharacterBudget` - and truncated the first time
        // anything photographed this dialog on a phone. See
        // `Disclosure.dialogSummaryCharacterBudget`.
        const Disclosure(
          key: ValueKey('catalog-management-edit-scope-disclosure'),
          summary: 'How this is checked',
          child: Text(
            key: ValueKey('catalog-management-edit-scope'),
            'Every field is filled in with what the product holds now. '
            'Change the ones that are wrong and save them together: a '
            'correction is checked against the whole product, so one that '
            'leaves a different field unreadable is refused outright.',
          ),
        ),
        SizedBox(height: tokens.spacing.s12),
        AppTextField(
          key: const ValueKey('catalog-management-edit-name'),
          controller: _name,
          maxLength: maximumCatalogNameLength,
          label: 'Product name',
        ),
        SizedBox(height: tokens.spacing.s8),
        AppTextField(
          key: const ValueKey('catalog-management-edit-sku'),
          controller: _sku,
          maxLength: maximumCatalogSkuLength,
          label: 'Code (SKU or barcode)',
          leading: Icons.tag,
          helper:
              'What the till matches a scan against. No spaces. The old '
              'code stops finding this product.',
        ),
        if (widget.canChangeMoney) ...[
          SizedBox(height: tokens.spacing.s8),
          AppTextField(
            key: const ValueKey('catalog-management-edit-price'),
            controller: _price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            label: 'Unit price',
            leading: Icons.payments_outlined,
            helper:
                'Applies to the next sale. Sales already recorded keep '
                'the price they were sold at.',
          ),
          SizedBox(height: tokens.spacing.s8),
          AppTextField(
            key: const ValueKey('catalog-management-edit-cost'),
            controller: _cost,
            enabled: !_clearCost,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            label: 'Unit cost',
            leading: Icons.payments_outlined,
            helper: widget.product.cost == null
                ? 'No unit cost is recorded. Enter one to start recording '
                      'it; leave it blank to keep reporting no profit for '
                      'this product.'
                : 'Leaving this blank keeps the recorded cost as it is. '
                      'Removing it is a separate act, below.',
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
              onChanged: (value) => setState(() => _clearCost = value ?? false),
            ),
        ] else ...[
          SizedBox(height: tokens.spacing.s12),
          // A role notice, at `info` for the reason every other one on this
          // route is: two of the five fields are not offered, and the other
          // three are - nothing has failed and nothing is hidden.
          const Callout(
            key: ValueKey('catalog-management-edit-money-hidden'),
            status: AppStatus.info,
            message:
                'Only an owner or administrator may change what this '
                'product is priced at or what it costs, so neither is '
                'offered here.',
          ),
        ],
        SizedBox(height: tokens.spacing.s12),
        SectionHeading('Category'),
        SizedBox(height: tokens.spacing.s8),
        FilterChipBar<String>(
          semanticLabel: 'The category this product is filed under',
          selected: _categoryId,
          onSelected: (value) =>
              setState(() => _categoryId = value ?? _categoryId),
          options: <FilterChipOption<String>>[
            for (final category in widget.categories)
              FilterChipOption<String>(
                key: ValueKey(
                  'catalog-management-edit-category-${category.id}',
                ),
                value: category.id,
                label: category.name,
              ),
          ],
        ),
        if (!_categoryOffered)
          Padding(
            padding: EdgeInsets.only(top: tokens.spacing.s8),
            child: Text(
              key: const ValueKey('catalog-management-edit-category-off'),
              'This product is filed under $unlistedTenantCategoryPhrase. '
              'Leaving it there is fine; choosing one above moves it.',
              style: tokens.typography.caption.copyWith(
                color: tokens.colors.text.tertiary,
              ),
            ),
          )
        else if (widget.moreCategories)
          Padding(
            padding: EdgeInsets.only(top: tokens.spacing.s8),
            child: Text(
              key: const ValueKey('catalog-management-edit-more-categories'),
              'More categories exist than are shown here. A product can '
              'only be moved into one of those above.',
              style: tokens.typography.caption.copyWith(
                color: tokens.colors.text.tertiary,
              ),
            ),
          ),
      ],
    );
    return _CatalogProductFormScreen(
      screenKey: const ValueKey('catalog-management-edit-screen'),
      scrollKey: const ValueKey('catalog-management-edit-scroll'),
      title: 'Correct product',
      subtitle: widget.product.name,
      scrollController: widget.scrollController,
      showsHeader: widget.preview == null,
      form: form,
      actions: <Widget>[
        AppButton(
          key: const ValueKey('catalog-management-edit-cancel'),
          label: 'Cancel',
          tier: AppButtonTier.tertiary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton(
          key: const ValueKey('catalog-management-edit-review'),
          label: 'Review correction',
          tier: AppButtonTier.primary,
          onPressed: () => Navigator.of(context).pop(
            _ProductEditDraft(
              name: _name.text,
              sku: _sku.text,
              categoryId: _categoryId,
              price: widget.canChangeMoney ? _price.text : null,
              cost: widget.canChangeMoney && !_clearCost ? _cost.text : null,
              clearCost: widget.canChangeMoney && _clearCost,
              image: _image,
              removeImage: _removeImage,
            ),
          ),
        ),
      ],
    );
  }
}

/// The framed panel a product photograph is chosen in.
///
/// **The old catalog form's presentation, restored on 2026-08-25.**
/// `lib/pos/goods.dart` drew a bordered box headed *Product Image*, the picture
/// 350 high across the full width of it, and the actions stacked underneath -
/// and the same box served both the add form and the correct form. The Stitch
/// pass had replaced it with a 64px thumbnail in a row, which is a size at
/// which the wrong photograph and the right one are the same picture.
///
/// **It owns only the removal it performs.** Which image is selected stays with
/// the form - the form is what submits it, and a well holding its own copy is
/// how the two come to disagree. What is local here is the state of the one
/// asynchronous act this panel makes: whether a cut-out is in flight and what
/// the last one said.
final class _ProductImageWell extends StatefulWidget {
  const _ProductImageWell({
    this.product,
    required this.image,
    required this.savedImageRemoved,
    required this.remover,
    required this.session,
    required this.onChoose,
    required this.onImageChanged,
    required this.onRemoveImage,
    this.showsPreview = true,
  });

  /// Whether this draws the picture as well as the controls.
  ///
  /// **False on a sheet with a masthead**, where the picture is already the top
  /// of the sheet: drawing it again here is the "double card" this arrangement
  /// exists to remove. True in the wide two-column form, where the image column
  /// is the picture and its controls together.
  final bool showsPreview;

  /// The product being corrected, whose saved photograph is shown until a new
  /// one is chosen. Null in the add form, which has no product yet.
  final TenantProduct? product;

  /// The photograph chosen in this form and not yet saved.
  final TenantProductImageCandidate? image;

  /// Whether the correction will remove the saved photograph.
  final bool savedImageRemoved;

  /// Null where no background-removal service is configured, which draws no
  /// such action at all. See `product_background_removal.dart`.
  final TenantProductBackgroundRemover? remover;

  /// Needed to send a cut-out and to decide whether to offer one. Null in the
  /// harness, which draws the well without a session behind it.
  final TenantSession? session;

  final Future<TenantProductImageCandidate?> Function() onChoose;
  final ValueChanged<TenantProductImageCandidate> onImageChanged;

  /// Null where there is nothing to remove - neither a chosen photograph nor a
  /// saved one - which disables the control rather than hiding it, for the
  /// reason `Pagination` states.
  final VoidCallback? onRemoveImage;

  @override
  State<_ProductImageWell> createState() => _ProductImageWellState();
}

final class _ProductImageWellState extends State<_ProductImageWell> {
  bool _busy = false;
  TenantBackgroundRemovalFailure? _failure;

  /// Whether the product's saved photograph is still what would be shown.
  bool get _showsSavedImage =>
      widget.image == null &&
      !widget.savedImageRemoved &&
      widget.product?.imageUrl != null;

  /// Whether anything at all is on display.
  bool get _hasImage => widget.image != null || _showsSavedImage;

  /// Whether the cut-out action is drawn.
  ///
  /// Hidden rather than disabled when there is no service or no role for it: a
  /// disabled control says *this is available and not right now*, and neither
  /// of those is the case. Once drawn it is disabled in the states where the
  /// answer really is "not right now", which is what the disabled row is for.
  bool get _offersRemoval {
    final remover = widget.remover;
    final session = widget.session;
    if (remover == null || session == null) return false;
    return remover.canRemoveInSession(session);
  }

  Future<void> _choose() async {
    final candidate = await widget.onChoose();
    if (!mounted || candidate == null) return;
    setState(() => _failure = null);
    widget.onImageChanged(candidate);
  }

  Future<void> _removeBackground() async {
    final remover = widget.remover;
    final session = widget.session;
    final candidate = widget.image;
    if (_busy || remover == null || session == null || candidate == null) {
      return;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final cutOut = await remover.remove(
        session: session,
        candidate: candidate,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      widget.onImageChanged(cutOut);
    } on TenantBackgroundRemovalException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = error.failure;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (widget.showsPreview) ...<Widget>[
          // **No `SectionHeading('Product image')` here since 2026-08-26.** On
          // the sheet the picture *is* the top of the sheet and needs no label;
          // in the wide two-column form the column is plainly a picture and its
          // controls. Either way the heading was naming what the reader could
          // already see, which is §7's own complaint about it.
          //
          // The lesser of the old form's 350 and a square of whatever width
          // this well was given, so a phone draws a square rather than a
          // letterbox and a desktop draws the figure the old form drew.
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: tokens.layout.productImagePreview,
            ),
            child: AspectRatio(
              aspectRatio: 1,
              child: _ProductImagePreview(
                image: widget.image,
                product: _showsSavedImage ? widget.product : null,
              ),
            ),
          ),
          SizedBox(height: tokens.spacing.s12),
        ],
        Row(
          children: <Widget>[
            Expanded(
              child: AppButton(
                key: ValueKey(
                  widget.product == null
                      ? 'inventory-choose-product-image'
                      : 'inventory-replace-image',
                ),
                label: _hasImage ? 'Replace image' : 'Choose image',
                icon: Icons.add_photo_alternate_outlined,
                expand: true,
                onPressed: _busy ? null : _choose,
              ),
            ),
            if (_offersRemoval) ...<Widget>[
              SizedBox(width: tokens.spacing.s8),
              AppIconButton(
                key: const ValueKey('inventory-remove-background'),
                icon: Icons.auto_fix_high,
                semanticLabel: 'Remove image background',
                tier: AppButtonTier.primary,
                loading: _busy,
                // Only a photograph chosen in this form can be cut out: the
                // bytes are what goes to the service, and a saved photograph
                // is a URL this form never downloads.
                onPressed: widget.image == null ? null : _removeBackground,
              ),
            ],
            SizedBox(width: tokens.spacing.s8),
            AppIconButton(
              key: const ValueKey('inventory-remove-image'),
              icon: Icons.delete_outline,
              semanticLabel: 'Remove image',
              tier: AppButtonTier.destructive,
              onPressed: _busy ? null : widget.onRemoveImage,
            ),
          ],
        ),
        if (_failure case final failure?) ...<Widget>[
          SizedBox(height: tokens.spacing.s12),
          Callout(
            key: const ValueKey('inventory-remove-background-failed'),
            status: AppStatus.problem,
            message: backgroundRemovalMessage(failure),
          ),
        ],
        if (widget.savedImageRemoved) ...<Widget>[
          SizedBox(height: tokens.spacing.s8),
          Text(
            key: const ValueKey('inventory-image-removal-pending'),
            'The saved image will be removed when this correction commits.',
            style: tokens.typography.caption.copyWith(
              color: tokens.colors.text.tertiary,
            ),
          ),
        ],
        SizedBox(height: tokens.spacing.s8),
        Text(
          _offersRemoval && widget.image == null
              ? 'JPEG, PNG, or WebP up to 5 MiB. Choose a photograph to cut '
                    'its background out.'
              : 'JPEG, PNG, or WebP up to 5 MiB.',
          style: tokens.typography.caption.copyWith(
            color: tokens.colors.text.tertiary,
          ),
        ),
      ],
    );
  }
}

/// What the well shows: the photograph chosen here, the one already saved, or
/// the fact that there is neither.
/// The picture a product form is currently showing.
///
/// **It exists because the masthead is outside the form's own subtree.** A
/// sheet's masthead is built by `showAppSheet`, which is above the form state
/// holding the chosen photograph — so the two cannot see each other by
/// ordinary means, and the picture has to be published somewhere they both
/// reach.
///
/// **The form stays authoritative.** This carries only what is needed to
/// *paint* — the chosen bytes and whether the saved photograph still counts —
/// and the form writes to it alongside its own `setState` rather than instead
/// of it. Making this the source of truth would mean rewriting both forms'
/// image handling to fix a rendering seam, which is a much larger change for
/// no behaviour gained.
final class _ProductImagePreviewModel extends ChangeNotifier {
  _ProductImagePreviewModel({this.product});

  /// The product being corrected, or null in the add form.
  final TenantProduct? product;

  TenantProductImageCandidate? _image;
  bool _savedRemoved = false;

  TenantProductImageCandidate? get image => _image;

  /// The saved photograph, or null once it has been chosen away or removed.
  TenantProduct? get shownProduct =>
      _image == null && !_savedRemoved ? product : null;

  void show(TenantProductImageCandidate? image, {bool savedRemoved = false}) {
    if (_image == image && _savedRemoved == savedRemoved) return;
    _image = image;
    _savedRemoved = savedRemoved;
    notifyListeners();
  }
}

final class _ProductImagePreview extends StatelessWidget {
  const _ProductImagePreview({
    super.key,
    required this.image,
    required this.product,
    this.square = false,
  });

  /// Draws no corner radius of its own.
  ///
  /// **True where this *is* the sheet's top.** The sheet clips to §2.3's
  /// `radius.lg`; a second radius inside that one shows the surface through
  /// four crescents at the corners.
  final bool square;

  final TenantProductImageCandidate? image;

  /// Non-null only where the saved photograph is what should be shown.
  final TenantProduct? product;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    // Zero where this is the sheet's own top: see [square].
    final radius = BorderRadius.circular(square ? 0 : tokens.radius.md);
    if (image case final chosen?) {
      return ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(color: tokens.colors.surface.overlay),
          child: Image.memory(
            chosen.bytes,
            key: const ValueKey('inventory-product-image-preview'),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            semanticLabel: 'The product image you chose, ${chosen.fileName}',
          ),
        ),
      );
    }
    if (product case final saved?) {
      return TenantProductVisual(product: saved);
    }
    return ClipRRect(
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(color: tokens.colors.surface.overlay),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.image_outlined,
                // §9's no-colour-alone rule is answered by the sentence under
                // it rather than by the glyph.
                color: tokens.colors.text.tertiary,
              ),
              SizedBox(height: tokens.spacing.s8),
              Text(
                'No image',
                key: const ValueKey('inventory-product-image-empty'),
                style: tokens.typography.caption.copyWith(
                  color: tokens.colors.text.tertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The old catalog form's arrangement: the photograph beside the fields on a
/// tablet or a desktop, above them on a phone.
///
/// `lib/pos/goods.dart` drew exactly this - a `Row` of `flex: 2` image and
/// `flex: 3` fields with 24 between them, and a single stacked column below its
/// mobile breakpoint. Both catalog forms use it, because the old app used one
/// image section for both and two different arrangements for one job is how
/// they drift apart.
final class _FormWithImageWell extends StatelessWidget {
  const _FormWithImageWell({
    required this.well,
    required this.fields,
    this.stacked = false,
  });

  /// Forces the single-column arrangement whatever the width.
  ///
  /// **True on a sheet with a masthead.** The two-column form exists to put a
  /// picture beside its fields; where the picture is already the top of the
  /// sheet, a second column would be an empty one - and the well under it is
  /// three controls, which do not want half the width.

  /// Null where the form offers no image at all - no store is configured, or
  /// this session may not change one - in which case the fields are the whole
  /// form and there is no second column to make.
  final bool stacked;

  final Widget? well;

  final List<Widget> fields;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: fields,
    );
    final image = well;
    if (image == null) return column;
    // **`MediaQuery`, not a `LayoutBuilder`.** `AppDialog` is an `AlertDialog`
    // underneath, which sizes its content by intrinsic height, and a
    // `LayoutBuilder` refuses to answer an intrinsic query - the defect
    // `Pagination` records by name after three dialogs threw it.
    final wide =
        !stacked &&
        AppLayout.contract.isAtLeast(
          MediaQuery.sizeOf(context).width,
          AppBreakpoint.medium,
        );
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          image,
          SizedBox(height: tokens.spacing.s16),
          column,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(flex: 2, child: image),
        SizedBox(width: tokens.spacing.s24),
        Expanded(flex: 3, child: column),
      ],
    );
  }
}
