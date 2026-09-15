import 'dart:async';

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
import '../ui/card.dart';
import '../ui/press.dart';
import '../ui/records.dart';
import '../ui/states.dart';
import '../ui/routes.dart';
import '../ui/scaffold.dart';
import '../ui/skeleton.dart';
import '../ui/snackbar.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'catalog_management.dart';
import 'product_background_removal.dart';
import 'product_image_framing.dart';
import 'product_image_framing_panel.dart';
import 'product_image_picker.dart';
import 'stock_adjustment.dart';
import 'product_image_drafts.dart';
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
    this.updateQueue,
    this.bulkRoute,
    this.onChanged,
    this.requestIdFactory,
    this.productSearchReader,
    this.imageStore,
    this.imageDrafts,
    this.undo,
    this.backgroundRemover,
    this.productStockRoute,
    this.adjustStockRoute,
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

  /// Where a correction waits until this device can send it.
  ///
  /// Present in the app and absent in most tests, which is the seam that lets a
  /// test drive [updateCallable] directly. With it, the form answers from the
  /// correction itself rather than from a round trip, and the overlay draws the
  /// corrected product until the server confirms or refuses it.
  final TenantProductUpdateQueue? updateQueue;

  /// Where a chosen photograph waits until Storage can take it.
  ///
  /// Present in the app and absent in most tests, which is the seam that keeps
  /// the inline upload path exercisable. With it, saving a product never waits
  /// on Storage and can happen with no connection at all.
  final HiveTenantProductImageDrafts? imageDrafts;

  /// Withdraws a queued catalog change that has not been sent. See
  /// [TenantCatalogManagementPanel.undo].
  final TenantCatalogUndo? undo;

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

  /// Opens the stock-correction screen. See [TenantProductAdjustStockOpener].
  ///
  /// **Separate from [productStockRoute] since 2026-08-26**, where the two used
  /// to be one builder taking a mode. Both are routes again, but only one of
  /// them reports an answer back to this catalog, and a builder that answers
  /// with a widget cannot carry that.
  final TenantProductAdjustStockOpener? adjustStockRoute;

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
      updateQueue: updateQueue,
      bulkRoute: bulkRoute,
      onChanged: onChanged,
      requestIdFactory: requestIdFactory,
      productSearchReader: productSearchReader,
      imageStore: imageStore,
      imageDrafts: imageDrafts,
      undo: undo,
      backgroundRemover: backgroundRemover,
      productStockRoute: productStockRoute,
      adjustStockRoute: adjustStockRoute,
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
    this.updateQueue,
    this.bulkRoute,
    this.onChanged,
    this.requestIdFactory,
    this.pageSize = 20,
    this.categoryPageSize = 50,
    this.productSearchReader,
    this.imageStore,
    this.imageDrafts,
    this.undo,
    this.backgroundRemover,
    this.productStockRoute,
    this.adjustStockRoute,
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
  final TenantProductUpdateQueue? updateQueue;
  final HiveTenantProductImageDrafts? imageDrafts;

  /// Withdraws a queued catalog change that has not been sent.
  ///
  /// **This is what replaced the confirmation dialogs.** Adding, retiring and
  /// correcting a product each used to open several paragraphs of prose before
  /// anything happened; at the developer's direction on 2026-09-04 they go
  /// straight through and the notice afterwards carries *Undo* instead. The
  /// offer is honest only while the change is still queued, which is exactly
  /// what [TenantPendingMutationStore.cancel] reports - so the answer decides
  /// what the shopkeeper is told, and a change already on its way says so
  /// rather than pretending to come back.
  final TenantCatalogUndo? undo;
  final WidgetBuilder? bulkRoute;
  final VoidCallback? onChanged;
  final TenantCatalogRequestIdFactory? requestIdFactory;
  final int pageSize;
  final int categoryPageSize;
  final TenantProductSearchReader? productSearchReader;
  final TenantProductImageStore? imageStore;
  final TenantProductBackgroundRemover? backgroundRemover;
  final TenantProductRouteBuilder? productStockRoute;

  /// Opens the stock-correction screen. See [TenantProductAdjustStockOpener].
  ///
  /// **Separate from [productStockRoute] since 2026-08-26**, where the two used
  /// to be one builder taking a mode. Both are routes again, but only one of
  /// them reports an answer back to this catalog, and a builder that answers
  /// with a widget cannot carry that.
  final TenantProductAdjustStockOpener? adjustStockRoute;

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
  final TextEditingController _productQuantity = TextEditingController();

  /// One retirement key per product, kept only across an unknown outcome.
  ///
  /// Keyed by product rather than held as a single field, because the catalog
  /// lists many and a person may retire two before either settles.
  final Map<String, String> _retireRequestIds = <String, String>{};
  final TextEditingController _search = TextEditingController();

  String? _selectedCategoryId;
  List<String?> _cursors = <String?>[null];
  int _pageIndex = 0;
  int _generation = 0;
  bool _busy = false;

  /// Reports one write outcome, over the screen rather than inside the page.
  ///
  /// See `showAppSnackBar`: since 2026-09-03 every outcome goes there, and
  /// inline text is left to the one thing it is still right for - a field
  /// saying what is wrong with what was typed into it.
  void _report(AppNotice notice, {Widget? action}) =>
      showAppSnackBar(context, notice, action: action);

  /// The *Undo* offered beside a queued change, or nothing.
  ///
  /// **Nothing when there is nothing to undo**: a change that was refused, or
  /// went straight to the server, or a build with no queue wired. The offer
  /// exists only for a record still sitting on this device.
  Widget? _undoAction(
    TenantSession session,
    TenantCatalogWriteResult result, {
    required String label,
    required String productId,
  }) {
    final undo = widget.undo;
    final operationId = result.operationId;
    if (undo == null || operationId == null) return null;
    return AppButton(
      key: const ValueKey('catalog-management-undo'),
      label: label,
      icon: Icons.undo,
      onPressed: () async {
        final withdrawn = await undo(
          tenantId: session.tenantId,
          operationId: operationId,
        );
        if (!mounted) return;
        if (withdrawn) {
          await _discardStagedQuietly(session, productId);
          if (!mounted) return;
          _reload();
          widget.onChanged?.call();
          _report(const AppNotice.confirmed('Undone. Nothing was sent.'));
          return;
        }
        // **Not a failure, and worded as the fact it is.** The change left this
        // device between the notice appearing and the button being pressed, so
        // there is no local record left to withdraw. Saying "undo failed" would
        // describe the app; saying where the change is describes the shop.
        _report(
          const AppNotice.unknown(
            'This has already been sent, so it cannot be taken back here. '
            'Change it again from the list.',
          ),
        );
      },
    );
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
    _productQuantity.dispose();
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

  /// **The picker itself is `chooseTenantImageFile`**, shared with the business
  /// details screen since 2026-09-05: which extensions are offered, `withData`,
  /// and the strict candidate validation are one decision, and a logo asks it
  /// in exactly the same words. What stays here is where the refusal is drawn,
  /// which this form answers with a snack bar and that one answers under its
  /// own well.
  Future<TenantProductImageCandidate?> _chooseProductImage() async {
    final chosen = await chooseTenantImageFile();
    if (!mounted || chosen == null) return null;
    switch (chosen) {
      case TenantImageChoiceCandidate(:final candidate):
        return candidate;
      case TenantImageChoiceRefused(:final message):
        _report(AppNotice.refused(message));
        return null;
    }
  }

  /// Opens a product form as a screen of its own.
  ///
  /// **A route again, at the product owner's direction on 2026-09-02**,
  /// reversing the 2026-08-26 move to a sheet and taking the compact masthead
  /// arrangement with it. Both forms ask for money - a price, a cost - and a
  /// sheet is anchored to the bottom of the screen, which is where the keyboard
  /// comes up: the fields at the foot of the form were under the keys at the
  /// moment they were being typed into.
  ///
  /// **What the masthead did, `_FormWithImageWell` already does.** Its narrow
  /// arrangement is the picture above the fields in one column, which is what
  /// the masthead was for; the difference was only that a sheet's top band
  /// bleeds into the sheet's own corners. A route has no such corners to fill,
  /// so the well draws its own preview again and `_ProductImagePreviewModel` -
  /// which existed solely to carry the picture up out of the form's state and
  /// into the sheet's chrome - is gone with it.
  Future<T?> _openProductFormRoute<T>({required Widget Function() form}) {
    final controller = TenantSessionScope.of(context);
    return Navigator.of(context).push<T>(
      AppPageRoute<T>(
        builder: (routeContext) =>
            TenantSessionScope(controller: controller, child: form()),
      ),
    );
  }

  Future<void> _openAddProduct(TenantSession session, _CatalogView view) async {
    final submit = await _openProductFormRoute<bool>(
      form: () => _AddProductScreen(
        categories: view.categories.items,
        moreCategories: view.categories.hasMore,
        name: _productName,
        sku: _productSku,
        price: _productPrice,
        cost: _productCost,
        openingQuantity: _productQuantity,
        canRecordCost: TenantCatalogManagementRepository.canRecordCostInSession(
          session,
        ),
        selectedCategoryId: _selectedCategoryId,
        image: _productImage,
        busy: _busy,
        onCategorySelected: (categoryId) {
          _selectedCategoryId = categoryId;
        },
        onChooseImage: widget.imageStore == null ? null : _chooseProductImage,
        onImageChanged: (image) => _productImage = image,
        session: session,
        backgroundRemover: widget.backgroundRemover,
      ),
    );
    if (submit == true && mounted) await _addProduct(session, view);
  }

  Future<void> _openCategories(TenantSession session) async {
    await _openProductFormRoute<void>(
      form: () => _CategoriesScreen(
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
    final open = widget.adjustStockRoute;
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
        openingQuantity: _productQuantity.text,
        categoryId: _selectedCategoryId ?? '',
        categories: view.categories.items,
        requestId: _productRequestId ??= _newRequestId(),
      );
    } on TenantCatalogManagementException catch (error) {
      _productRequestId = null;
      _report(_refusalNotice(error.code));
      return;
    }
    // **No confirmation, at the developer's direction on 2026-09-04.** What
    // stood here was ten lines of prose about categories, codes, cost and
    // stock, read after the form was filled in rather than while it was being
    // filled in - so it was answered by reflex on every product a shop added.
    // Those consequences are in the form itself now, beside the fields they
    // are about, and the change is withdrawable from the notice afterwards.
    if (!_stillCurrent(capturedKey)) return;

    setState(() {
      _busy = true;
    });
    TenantProductImageUpload? upload;
    var staged = false;
    try {
      final candidate = _productImage;
      final drafts = widget.imageDrafts;
      final store = widget.imageStore;
      if (candidate != null && drafts != null) {
        // **The photograph is held, not sent.** It is on screen from here on
        // through `TenantProductImageDraftScope`, and
        // `TenantProductImageUploadWorker` carries it to Storage once the
        // product itself is on the server. Before 2026-09-04 this line was a
        // `putData` of up to five megabytes followed by a `getDownloadURL`,
        // both awaited, both ahead of the product being written at all - which
        // is why adding a product offline was refused outright.
        await drafts.stage(
          tenantId: session.tenantId,
          productId: intent.productId,
          candidate: candidate,
        );
        staged = true;
      } else if (candidate != null && store != null) {
        // The inline path, kept for a build with no draft store wired.
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
          openingQuantity: _productQuantity.text,
          categoryId: _selectedCategoryId ?? '',
          categories: view.categories.items,
          requestId: _productRequestId!,
          imageUrl: upload.url,
        );
      }
      final result = await writer.createProduct(intent);
      final kept =
          result.kind == TenantCatalogWriteKind.committed ||
          result.kind == TenantCatalogWriteKind.queued ||
          result.kind == TenantCatalogWriteKind.ambiguous;
      if (upload != null && !kept) {
        await _removeOwnedQuietly(
          session: session,
          productId: intent.productId,
          imageUrl: upload.url,
        );
      }
      // A product that was refused has no photograph to keep waiting for it.
      if (staged && !kept) {
        await _discardStagedQuietly(session, intent.productId);
      }
      if (!_stillCurrent(capturedKey)) return;
      if (result.kind != TenantCatalogWriteKind.ambiguous) {
        _productRequestId = null;
      }
      _report(
        _productNotice(result, intent),
        action: _undoAction(
          session,
          result,
          label: 'Undo adding this',
          productId: intent.productId,
        ),
      );
      if (result.kind != TenantCatalogWriteKind.rejected) _reload();
      if (kept) {
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
      if (staged) await _discardStagedQuietly(session, intent.productId);
      if (!_stillCurrent(capturedKey)) return;
      _report(_refusalNotice(error.code));
    } on TenantProductImageException catch (error) {
      if (!_stillCurrent(capturedKey)) return;
      _report(_imageNotice(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Forgets a staged photograph whose product never made it.
  ///
  /// Best effort, on the same grounds as [_removeOwnedQuietly]: the product's
  /// outcome is the fact worth reporting, and a draft left behind costs a
  /// little disk and one upload attempt that will answer `not-found`.
  Future<void> _discardStagedQuietly(
    TenantSession session,
    String productId,
  ) async {
    try {
      await widget.imageDrafts?.discard(
        tenantId: session.tenantId,
        productId: productId,
      );
    } catch (_) {
      // See above.
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

  Future<void> _retire(
    TenantSession session,
    TenantProduct product, {
    bool retired = true,
  }) async {
    final writer = widget.writer;
    if (writer == null || _busy) return;
    final capturedKey = _sessionKey(session);

    final TenantProductRetireIntent intent;
    try {
      intent = _repository(session).buildRetireIntent(
        product,
        // One key per attempt, held per product: a retry after an unknown
        // outcome must settle the first retirement rather than clear the stock
        // a second time, and two products retired in one sitting are two
        // operations.
        requestId: _retireRequestIds[product.id] ??= _newRequestId(),
        retired: retired,
      );
    } on TenantCatalogManagementException catch (error) {
      _retireRequestIds.remove(product.id);
      _report(_refusalNotice(error.code));
      return;
    }
    // **A confirmation, because this one clears stock.** Adding a product lost
    // its confirmation on 2026-09-04 and rightly: nothing was at stake and the
    // notice offered an undo. Retiring a product holding units writes a movement
    // that takes them off the books, and the figure is worth stating before it
    // happens rather than afterwards.
    if (retired &&
        product.quantity != 0 &&
        !await _confirmed(
          title: 'Retire ${intent.name}?',
          body:
              'It holds ${intent.quantity} '
              '${intent.quantity == 1 ? 'unit' : 'units'}. Retiring records an '
              'adjustment clearing them to zero, so the stock ledger says where '
              'they went, and takes the product off the till. Its ledger and '
              'every past sale stay exactly as they are, and it can be restored '
              'from this screen.',
          action: 'Retire product',
        )) {
      _retireRequestIds.remove(product.id);
      return;
    }
    if (!_stillCurrent(capturedKey)) return;

    setState(() {
      _busy = true;
    });
    try {
      final result = await writer.retireProduct(intent);
      if (!_stillCurrent(capturedKey)) return;
      // Only an unknown outcome keeps the key. Everything else settled, so the
      // next retirement of this product is a new operation clearing whatever it
      // holds then.
      if (result.kind != TenantCatalogWriteKind.ambiguous) {
        _retireRequestIds.remove(product.id);
      }
      _report(
        _retireNotice(result, intent),
        action: _undoAction(
          session,
          result,
          label: retired ? 'Undo retiring this' : 'Undo restoring this',
          productId: intent.productId,
        ),
      );
      if (result.kind != TenantCatalogWriteKind.rejected) _reload();
      if (result.kind == TenantCatalogWriteKind.committed ||
          result.kind == TenantCatalogWriteKind.queued) {
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

    final draft = await _openProductFormRoute<_ProductEditDraft>(
      form: () => _EditProductScreen(
        product: product,
        categories: view.categories.items,
        moreCategories: view.categories.hasMore,
        // A price and a cost are money and sit behind owner or
        // administrator. The field is not offered at all to anyone else,
        // because the callable reads its tier from the fields a payload
        // names: a form that offered a price it knew would be refused
        // would teach a manager only that the app guesses.
        canChangeMoney:
            TenantCatalogManagementRepository.canRecordCostInSession(session),
        canChangeImage: widget.imageStore != null,
        onChooseImage: _chooseProductImage,
        session: session,
        backgroundRemover: widget.backgroundRemover,
      ),
    );
    if (draft == null || !_stillCurrent(capturedKey)) return;

    TenantProductImageUpload? stagedImage;
    // **A new photograph is held rather than uploaded, and it leaves the
    // correction entirely.** The bytes go to the draft store, every surface
    // draws them at once, and `TenantProductImageUploadWorker` files the
    // resulting URL as its own correction once Storage has taken it. That is
    // why `imageUrl` below is null on this path: this correction is about the
    // fields a person typed, and the picture settles on its own.
    var heldImage = false;
    final imageDrafts = widget.imageDrafts;
    if (draft.image != null && imageDrafts != null) {
      setState(() {
        _busy = true;
      });
      await imageDrafts.stage(
        tenantId: session.tenantId,
        productId: product.id,
        candidate: draft.image!,
      );
      heldImage = true;
    } else if (draft.image != null) {
      final store = widget.imageStore;
      if (store == null) return;
      setState(() {
        _busy = true;
      });
      try {
        stagedImage = await store.upload(
          tenantId: session.tenantId,
          productId: product.id,
          candidate: draft.image!,
        );
      } on TenantProductImageException catch (error) {
        if (_stillCurrent(capturedKey)) {
          setState(() => _busy = false);
          _report(_imageNotice(error));
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
      // **A new photograph on its own is not an unchanged correction.** With
      // the picture out of the intent, changing only the picture leaves nothing
      // for `updateProduct` to do - so `product_unchanged` here means the
      // photograph *is* the change, and it is already saved.
      if (error.code == 'product_unchanged' && heldImage) {
        _forgetEditRequestId();
        if (!_stillCurrent(capturedKey)) return;
        setState(() => _busy = false);
        _report(
          const AppNotice.confirmed(
            'Photograph saved. It is on this device now and uploads on its '
            'own; every other device sees it once it has.',
          ),
        );
        _reload();
        return;
      }
      if (stagedImage != null) {
        await _removeOwnedQuietly(
          session: session,
          productId: product.id,
          imageUrl: stagedImage.url,
        );
      }
      if (heldImage) await _discardStagedQuietly(session, product.id);
      _forgetEditRequestId();
      // **Guarded, unlike every sibling in this method until 2026-09-04.** The
      // awaits above this line - a Storage delete, a draft discard - can span a
      // disposal, and `setState` on a dead element throws. Every other exit
      // from this method already checked; this one did not.
      if (!_stillCurrent(capturedKey)) return;
      setState(() => _busy = false);
      _report(_refusalNotice(error.code));
      return;
    }
    // The third confirmation, gone on the same grounds. A correction states
    // every field that moves in the form the person is looking at, and
    // `_editConfirmation` restated it on a second screen after they had already
    // decided. Every correction is still recorded, with actor and previous
    // value, which is what makes it safe to let it through.
    if (!_stillCurrent(capturedKey)) {
      if (stagedImage != null) {
        await _removeOwnedQuietly(
          session: session,
          productId: product.id,
          imageUrl: stagedImage.url,
        );
      }
      if (heldImage) await _discardStagedQuietly(session, product.id);
      if (mounted) setState(() => _busy = false);
      return;
    }

    setState(() {
      _busy = true;
    });
    try {
      final result = await TenantProductUpdateGateway(
        session: session,
        callable: callable,
        queue: widget.updateQueue,
      ).submit(intent, previous: product);
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
      _report(
        const AppNotice.unknown(
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
    _productQuantity.clear();
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
    // **Both readers travel together, and that is the point.** Until
    // 2026-09-14 this closure took the reader for the pass and then named
    // `widget.productSearchReader` anyway - the live one - and
    // `TenantCatalogRepository` lets an explicit search reader outrank the
    // reader it is given. So the cached pass read its categories off the disk
    // and then blocked on the network for the products, and a catalog this
    // device was holding the whole time took fifteen seconds to draw with no
    // signal while every other offline-first route drew in two.
    TenantGuardedLoader<_CatalogView> readWith(
      TenantDataReader reader,
      TenantProductSearchReader? searchReader,
    ) => (session) async {
      final repository = TenantCatalogRepository(
        session: session,
        reader: reader,
        productSearchReader: searchReader,
      );
      // Every category, not the first page: this list is what the add
      // and edit forms file a product under and what the filter offers, so
      // a category missing from it is a category no product can be put in.
      final categories = await repository.loadEveryCategory();
      // The same question the repository's constructor answers, asked the
      // same way: a pass whose own reader can search needs no companion,
      // and one that cannot falls back to the companion it was handed.
      final supportsSearch =
          searchReader != null || reader is TenantProductSearchReader;
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
    _loader = readWith(widget.reader, widget.productSearchReader);
    final cache = widget.reader.cached;
    final cachedSearch = widget.productSearchReader?.cachedProductSearch;
    if (cache == null) {
      _loaderCached = null;
      return;
    }
    final readCached = readWith(cache, cachedSearch);
    // **An empty answer from the disk is not an answer.** `Source.cache` is
    // silent rather than failing for a path it has never seen - it hands back
    // an empty page - so a device that has never synced cannot be told apart
    // from a business that sells nothing. Drawing that would put *no products*
    // on screen and then take it back a moment later, which on the catalog
    // reads as the shop's products having been lost.
    //
    // Throwing is how a cached pass says it holds nothing:
    // `TenantRouteGuard._loadFromCache` swallows every failure in silence and
    // leaves the page on its shimmer until the server answers. Categories and
    // products both, because a business with categories and no products yet is
    // a real state worth drawing at once.
    _loaderCached = (session) async {
      final view = await readCached(session);
      if (view.categories.items.isEmpty && view.products.items.isEmpty) {
        throw const _NothingHeldOnThisDevice();
      }
      return view;
    };
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
      // **Deliberately unkeyed since 2026-09-04.** A `ValueKey(guardKey)` here
      // destroyed and rebuilt the guard's whole `State` on every page turn,
      // filter change and post-write re-read, which threw away the catalog
      // that was on screen and dropped the page back to placeholders. The
      // guard notices a changed `load` on its own and keeps what it holds
      // while the next answer arrives; `_composeLoaders` is what makes that
      // safe, by memoising the closure so it changes identity exactly when
      // this key does and not once per frame.
      allowedRoles: null,
      load: _loader!,
      loadCached: _loaderCached,
      // **A shimmer of the catalog rather than a spinner, at the developer's
      // direction on 2026-08-28.** This route was on the guard's default
      // `LoadingState`, which is one indicator and one sentence in the middle
      // of an empty page - it says something is happening and nothing about
      // what, on the screen a shopkeeper opens most often and knows the shape
      // of best.
      // **The page itself, with its list still arriving.** Until 2026-09-04
      // this slot was a separate widget that drew placeholders for the whole
      // screen; the developer asked for the controls to stop disappearing
      // while the catalog reads, and the way to guarantee they never move
      // between the two states is for there to be only one widget that lays
      // them out. `_UnifiedInventoryContents` takes a null view now and draws
      // the toolbar for real over a placeholder list.
      //
      // **The session is read from the scope rather than waited for.** The
      // guard only hands one to `builder`, but the controller has it already,
      // so the loading state can decide `canWrite` on exactly the same terms
      // the loaded state does - which is what keeps a cashier from seeing
      // *Add product* flash up and vanish.
      loading: _contents(TenantSessionScope.of(context).session, null),
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
      builder: (context, session, view) => _contents(session, view),
    );
  }

  /// The catalog page, in either state.
  ///
  /// [view] is null while the read is in flight. Every control below is
  /// therefore drawn from what is knowable without it - the composition root's
  /// wiring and the session's roles - and disabled until the data lands.
  Widget _contents(TenantSession? session, _CatalogView? view) =>
      _UnifiedInventoryContents(
        view: view,
        // **Busy while reading**, which is what disables every control through
        // the gating each of them already had. A search typed against a
        // catalog that has not been read is a search with nothing to run on.
        busy: _busy || view == null,
        canWrite:
            widget.writer != null &&
            session != null &&
            session.canAccess(
              allowedRoles: TenantCatalogManagementRepository.allowedRoles,
            ),
        // Taken from the guarded session, never from the caller, so the action
        // disappears the moment the session stops allowing it.
        canRetire:
            session != null &&
            TenantCatalogManagementRepository.canRetireInSession(session),
        // Correcting needs only the operational three the guard already
        // admitted, so what decides this is whether the build has the callable
        // at all. Which of the five fields the form then offers is decided
        // per session inside it.
        canEdit:
            widget.updateCallable != null &&
            session != null &&
            session.canAccess(
              allowedRoles: TenantCatalogManagementRepository.allowedRoles,
            ),
        canView:
            widget.productStockRoute != null &&
            session != null &&
            session.canAccess(allowedRoles: widget.productStockRoles),
        // **Narrower than `canView` on purpose.** Everyone the stock route
        // admits may read the ledger; only the roles the adjust callable
        // itself enforces may correct a figure, and the gateway is what
        // decides that rather than this surface.
        canAdjust:
            widget.adjustStockRoute != null &&
            session != null &&
            session.canAccess(allowedRoles: widget.productStockRoles) &&
            TenantStockAdjustmentGateway.canAdjustInSession(session),
        canViewCost:
            session != null &&
            TenantCatalogManagementRepository.canRecordCostInSession(session),
        onBulk: widget.bulkRoute == null ? null : _openBulk,
        search: _search,
        searchPrefix: _searchPrefix,
        categoryFilter: _categoryFilter,
        stockFilter: _stockFilter,
        pageIndex: _pageIndex,
        onSearchChanged: _onSearchChanged,
        onCategoryFilterChanged: _setCategoryFilter,
        onStockFilterChanged: _setStockFilter,
        onOpenCategories: () {
          if (session != null) _openCategories(session);
        },
        onOpenAddProduct: () {
          if (session != null && view != null) _openAddProduct(session, view);
        },
        onView: _openProduct,
        onAdjust: _adjustProduct,
        onEdit: (product) {
          if (session != null && view != null) _edit(session, view, product);
        },
        onRetire: (product) {
          if (session != null) _retire(session, product);
        },
        onRestore: (product) {
          if (session != null) _retire(session, product, retired: false);
        },
        onNextPage: () {
          if (view != null) _nextPage(view.products.nextCursor);
        },
        onPreviousPage: _previousPage,
        productVisualBuilder: widget.productVisualBuilder,
      );
}

/// One guarded read of everything this route renders.
final class _CatalogView {
  const _CatalogView({required this.categories, required this.products});

  final TenantCatalogPage<TenantCategory> categories;
  final TenantCatalogPage<TenantProduct> products;
}

/// What the cached pass throws when this device is holding no catalog at all.
///
/// Never shown to anybody and never caught by name: it exists so the guard's
/// silent-failure path can carry the one fact a `Source.cache` read cannot
/// state for itself - see `_composeLoaders`.
final class _NothingHeldOnThisDevice implements Exception {
  const _NothingHeldOnThisDevice();
}

/// The legacy `goods.dart` hierarchy rebuilt on the tenant-safe catalog model.
final class _UnifiedInventoryContents extends StatelessWidget {
  const _UnifiedInventoryContents({
    required this.view,
    required this.busy,
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
    required this.onRestore,
    required this.onNextPage,
    required this.onPreviousPage,
    required this.productVisualBuilder,
  });

  /// Null while the catalog is still being read, in which case the toolbar is
  /// drawn for real and the list is drawn as placeholders.
  final _CatalogView? view;
  final bool busy;
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

  /// Puts a retired product back in the catalog. It does **not** give the stock
  /// back: those units were accounted for as leaving, and inventing them again
  /// would be a movement nobody could explain. A restored product takes an
  /// ordinary opening balance.
  final ValueChanged<TenantProduct> onRestore;
  final VoidCallback onNextPage;
  final VoidCallback onPreviousPage;
  final TenantProductVisualBuilder? productVisualBuilder;

  /// How wide each filter is once there is room to put both beside the search
  /// field.
  ///
  /// **Named so the placeholder can read them**, and neither is on §2.3's scale
  /// because neither is a spacing: they are how much room *All categories* and
  /// *At/below zero* need beside their labels. A skeleton that guessed would
  /// draw the filter row at one width and shuffle it sideways when the catalog
  /// landed.
  static const double categoryFilterWidth = 220;
  static const double stockFilterWidth = 188;

  /// The sentence under the search field.
  ///
  /// Named for the same reason the widths are: it is a line of the field's own
  /// height, so a placeholder that left it out would draw the whole filter row
  /// one line short and move everything under it when the catalog landed.
  static const String searchHelper =
      'Type at least 2 characters from a name word or product code.';

  bool get _hasActiveQuery =>
      searchPrefix.isNotEmpty ||
      categoryFilter != null ||
      stockFilter != TenantProductStockFilter.all;

  List<_InventoryProductAction> _actions(TenantProduct product) =>
      <_InventoryProductAction>[
        if (canView)
          _InventoryProductAction(
            label: 'View item',
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
            label: 'Edit item',
            icon: Icons.edit_outlined,
            key: ValueKey('catalog-management-edit-${product.id}'),
            onPressed: busy ? null : () => onEdit(product),
          ),
        // **One control, two directions.** A retired product is still listed -
        // it is a flag now rather than a delete - so the row that retired it is
        // the row that puts it back. Restoring is not destructive and is not
        // drawn as though it were.
        if (canRetire && canWrite)
          product.retired
              ? _InventoryProductAction(
                  label: 'Restore product',
                  icon: Icons.add_shopping_cart_outlined,
                  key: ValueKey('catalog-management-restore-${product.id}'),
                  onPressed: busy ? null : () => onRestore(product),
                )
              : _InventoryProductAction(
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
            // Named for the one job it does since 2026-09-14. It read "Bulk
            // changes & import" while it was two jobs behind a pair of chips.
            label: compact ? 'Add many' : 'Add many products',
            icon: Icons.cloud_upload_outlined,
            expand: compact,
            onPressed: busy ? null : onBulk,
          );
    final Widget? bulk = bulkButton == null
        ? null
        : Semantics(
            // The full wording the compact button shortens, so a screen reader
            // hears the same thing at every width.
            label: 'Add many products',
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
          AppActionRow(
            expandActions: true,
            actions: <Widget>[bulk, categories],
          ),
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
    final categories = view?.categories.items ?? const <TenantCategory>[];
    // **A filter that is applied has to stay selectable while the page it
    // filters is re-read.** The categories arrive with the products, so during
    // a read the list is empty while `category` still names one - and a
    // `DropdownButton` asserts outright that its value is among its items.
    // This is the same "a category whose name this surface does not hold" case
    // `tenantCategoryLabel` exists for, and it is answered the same way.
    final unlisted =
        category.isNotEmpty && !categories.any((item) => item.id == category);
    final unlistedLabel = tenantCategoryLabel(
      category,
      names: tenantCategoryNames(categories),
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            key: const ValueKey('inventory-search'),
            controller: search,
            enabled: !busy,
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
                    for (final item in categories)
                      DropdownMenuItem<String>(
                        value: item.id,
                        child: Text(item.name),
                      ),
                    if (unlisted)
                      DropdownMenuItem<String>(
                        value: category,
                        child: Text(unlistedLabel),
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
      helper: searchHelper,
      onChanged: onSearchChanged,
    );
    final categoryControl = AppSelect<String>(
      key: const ValueKey('inventory-category-filter'),
      label: 'Category',
      leading: Icons.category_outlined,
      value: category,
      items: <AppSelectItem<String>>[
        const AppSelectItem<String>(value: '', label: 'All categories'),
        for (final item in categories)
          AppSelectItem<String>(value: item.id, label: item.name),
        if (unlisted)
          AppSelectItem<String>(value: category, label: unlistedLabel),
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
        SizedBox(width: categoryFilterWidth, child: categoryControl),
        SizedBox(width: tokens.spacing.s12),
        SizedBox(width: stockFilterWidth, child: stockControl),
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
    final data = view;
    final categoryNames = tenantCategoryNames(
      data?.categories.items ?? const <TenantCategory>[],
    );
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
        SizedBox(height: tokens.spacing.s20),
        _filters(context, compact: !wide),
        SizedBox(height: tokens.spacing.s16),
        if (data == null)
          // Only the records shimmer. Decision 35's rule, and now the whole of
          // what this route applies it to.
          _InventoryReading(wide: wide)
        else ...<Widget>[
          _InventoryProductList(
            products: data.products.items,
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
            onNext: data.products.hasMore && !busy ? onNextPage : null,
          ),
        ],
      ],
    );
  }
}

/// The product list while it is still being read.
///
/// **The list and nothing else, since 2026-09-04.** This drew the whole page
/// once - placeholder buttons, a placeholder search well, placeholder filters,
/// then the records - and every one of those except the records was standing
/// in for something that was never being read. The toolbar above is page
/// state: its labels are fixed words and its values were decided before the
/// read started, so `_UnifiedInventoryContents` draws it for real in both
/// states and this fills only the part that is actually arriving. Nothing
/// moves when the read lands, because nothing above the list was ever a
/// placeholder.
/// Decision 35's rule, and the labels inside each card - *Category*, *In
/// stock*, *Price* - are drawn for real, because they are the same three words
/// whatever the read returns.
///
/// **The action row is drawn without knowing whether the session may write.**
/// That is decided from the guarded session and so does not exist yet; the
/// space is reserved because the roles this route admits are mostly roles that
/// can add a product, and content that settles into reserved space is a better
/// failure than content that jumps up when a row it was never getting
/// collapses. The read-only case loses one row's height when the page lands.
final class _InventoryReading extends StatelessWidget {
  const _InventoryReading({required this.wide});

  /// Which form the list takes, decided by the page around it rather than
  /// measured again here - two readings of one breakpoint is how a placeholder
  /// ends up a different shape from the thing it stands in for.
  final bool wide;

  /// Four placeholder products, which fills a phone without pretending to know
  /// how large the catalog is.
  static const int _cards = 4;

  /// Placeholder table rows for the wide form. Six, because a table row is
  /// `space.48` and a desk screen shows appreciably more of them than a phone
  /// shows cards.
  static const int _rows = 6;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return SkeletonGroup(
      semanticLabel: 'Reading the products in this catalog.',
      child: Container(
        key: const ValueKey('inventory-reading'),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: tokens.colors.surface.raised,
          borderRadius: BorderRadius.circular(tokens.radius.md),
          border: Border.all(color: tokens.colors.surface.borderSubtle),
        ),
        child: wide
            ? _table(context)
            : Padding(
                padding: EdgeInsets.symmetric(vertical: tokens.spacing.s4),
                child: Column(
                  children: <Widget>[
                    for (var card = 0; card < _cards; card++)
                      const _InventoryProductCardSkeleton(),
                  ],
                ),
              ),
      ),
    );
  }

  /// The wide form's placeholder: the header rule the table draws, then its
  /// rows at §9's tap target - the same shape `RecordListSkeleton` gives a
  /// table, which this cannot call because that component picks its form from
  /// `RecordList`'s breakpoints and this table picks its own.
  Widget _table(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Padding(
      padding: EdgeInsets.all(tokens.spacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SkeletonBlock(
            height: tokens.spacing.s32,
            radius: tokens.radius.sm,
            tone: SkeletonTone.onRaised,
          ),
          for (var row = 0; row < _rows; row++) ...<Widget>[
            SizedBox(height: tokens.spacing.s8),
            SkeletonBlock(
              height: tokens.spacing.s48,
              tone: SkeletonTone.onRaised,
            ),
          ],
        ],
      ),
    );
  }
}

/// One placeholder product, arranged like [_InventoryProductCard].
///
/// **The card's frame and its three column labels are real; only the values
/// shimmer.** *Category*, *In stock* and *Price* are the same three words
/// whatever the catalog holds, so under decision 35 they are not the read's to
/// withhold - and they are what tells a person, before anything lands, that
/// this is the screen where a price is checked.
final class _InventoryProductCardSkeleton extends StatelessWidget {
  const _InventoryProductCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    // The card is painted `surface.base` - the page tier - inside a `raised`
    // list, so its blocks step up from the page rather than from the list.
    const tone = SkeletonTone.onPage;
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: tokens.spacing.s8,
        vertical: tokens.spacing.s4,
      ),
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
              // The product's picture, at the square the real card gives it.
              SkeletonBlock(
                width: tokens.spacing.s64,
                height: tokens.spacing.s64,
                radius: tokens.radius.md,
                tone: tone,
              ),
              SizedBox(width: tokens.spacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    SkeletonLine(
                      widthFactor: 0.66,
                      style: tokens.typography.bodyLarge,
                      tone: tone,
                    ),
                    SizedBox(height: tokens.spacing.s4),
                    SkeletonLine(
                      widthFactor: 0.42,
                      style: tokens.typography.mono,
                      tone: tone,
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.s12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              const Expanded(
                child: _InventoryMetricSkeleton(
                  label: 'Category',
                  widthFactor: 0.7,
                ),
              ),
              SizedBox(width: tokens.spacing.s8),
              const SizedBox(
                width: _InventoryProductCard.stockColumnWidth,
                child: _InventoryMetricSkeleton(
                  label: 'In stock',
                  widthFactor: 0.6,
                ),
              ),
              SizedBox(width: tokens.spacing.s8),
              const SizedBox(
                width: _InventoryProductCard.priceColumnWidth,
                child: _InventoryMetricSkeleton(
                  label: 'Price',
                  widthFactor: 0.85,
                ),
              ),
              SizedBox(width: tokens.spacing.s8),
              SkeletonBlock(
                width: tokens.spacing.s24,
                height: tokens.spacing.s24,
                radius: tokens.radius.sm,
                tone: tone,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A real column label over a value that has not arrived, matching
/// [_InventoryProductMetric] line for line.
final class _InventoryMetricSkeleton extends StatelessWidget {
  const _InventoryMetricSkeleton({
    required this.label,
    required this.widthFactor,
  });

  final String label;
  final double widthFactor;

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
        SkeletonLine(widthFactor: widthFactor, style: tokens.typography.mono),
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

  /// The well's painted height, which the placeholder for it also reads.
  ///
  /// Above §9's 48 minimum rather than on it: this is the height the legacy
  /// catalog drew its two filters at, and it is carried rather than rounded so
  /// the filter row is the height it has always been on this screen.
  static const double height = 52;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Semantics(
      label: semanticLabel,
      button: true,
      child: Container(
        height: height,
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

  /// The stock column's width, and the price column's beside it.
  ///
  /// **Named rather than inlined so the placeholder can read them.** They are
  /// content measurements rather than spacings - what three digits and a
  /// two-decimal figure need - which is why they are not on §2.3's scale; and a
  /// skeleton that guessed them would put the price column in one place and
  /// then move it when the read landed.
  static const double stockColumnWidth = 44;
  static const double priceColumnWidth = 56;

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
                width: stockColumnWidth,
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
                width: priceColumnWidth,
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
  TenantCatalogWriteKind.committed ||
  TenantCatalogWriteKind.queued => const AppNotice.confirmed(
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
      TenantCatalogWriteKind.committed ||
      TenantCatalogWriteKind.queued => const AppNotice.confirmed(
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
      // **The code goes in the sentence, and it is not clutter.** Two of
      // Storage's refusals are this app's own fault and are worded above; every
      // other one - `permission-denied`, `unauthenticated`, `unauthorized`,
      // `retry-limit-exceeded`, a plain network timeout - arrived here as one
      // indistinguishable line, so a shop reporting "it will not upload" was
      // reporting five different faults under one name and neither they nor
      // anybody reading a screenshot could tell which. The sentence still says
      // what happened first and what it cost; the code is what makes the report
      // worth having.
      _ => AppNotice.refused(
        'The product image could not be uploaded (${error.code}). Nothing was '
        'written.',
      ),
    };

/// **The confirmed sentence is two, because adding a product now is.**
/// It used to say "holding no stock" and then tell the operator to go and record
/// an opening quantity from the product itself - two journeys, which is the thing
/// this form stopped needing. A product added with stock says what it holds and
/// where that figure is recorded; one added empty still says so plainly, because
/// "no stock" is a fact about the shelf worth stating rather than an omission.
AppNotice _productNotice(
  TenantCatalogWriteResult result,
  TenantProductCreateIntent intent,
) => switch (result.kind) {
  TenantCatalogWriteKind.committed ||
  TenantCatalogWriteKind.queued => AppNotice.confirmed(
    intent.quantity > 0
        ? '${intent.name} added, holding ${intent.quantity} '
              '${intent.quantity == 1 ? 'unit' : 'units'}. Those units are '
              'recorded in its stock ledger as an opening balance, so the '
              'figure says where it came from. It is on its way to the '
              'server now; every other device picks it up when it syncs.'
        : '${intent.name} added, holding no stock. Record what arrives from '
              'the product itself, so the ledger says where those units '
              'came from. It is on its way to the server now; every other '
              'device picks it up when it syncs.',
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

/// **Every sentence here changed on 2026-09-13, because the act did.**
/// Retiring was a delete: the document carrying the quantity was removed, no
/// movement recorded the stock leaving, and the confirmed sentence mentioned
/// only the half that survived. It is a flag now, the units are cleared through
/// the ledger in the same transaction, and the product stays - so the sentence
/// says what happened to the stock rather than what did not happen to history.
AppNotice _retireNotice(
  TenantCatalogWriteResult result,
  TenantProductRetireIntent intent,
) => switch (result.kind) {
  TenantCatalogWriteKind.committed ||
  TenantCatalogWriteKind.queued => AppNotice.confirmed(
    intent.retired
        ? intent.quantity == 0
              ? '${intent.name} is retired and off the till. It held no stock, '
                    'so nothing was cleared. Its ledger and every past sale are '
                    'unchanged, and it can be restored from this screen.'
              : '${intent.name} is retired and off the till. The '
                    '${intent.quantity} '
                    '${intent.quantity == 1 ? 'unit' : 'units'} it held are '
                    'cleared to zero, recorded in its stock ledger. It can be '
                    'restored from this screen.'
        : '${intent.name} is back in the catalog, holding no stock. Record what '
              'is on the shelf from the product itself.',
  ),
  TenantCatalogWriteKind.rejected => AppNotice.refused(
    intent.retired
        ? 'Nothing was retired. Only an owner or administrator may retire a '
              'product.'
        : 'Nothing was restored. Only an owner or administrator may restore a '
              'product.',
  ),
  TenantCatalogWriteKind.ambiguous => const AppNotice.unknown(
    'The result is unknown. The catalog below has been re-read; if it has not '
    'changed, try again - the retry settles the first attempt rather than '
    'clearing the stock a second time.',
  ),
  TenantCatalogWriteKind.unavailable => const AppNotice.offline(
    'This device is offline, so nothing was changed. The catalog can only be '
    'changed while online.',
  ),
};

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
      TenantProductUpdateFailure.notRecorded => const AppNotice.refused(
        'This device could not store the correction, so nothing was recorded '
        'and nothing was sent. Try again, and report it if it keeps happening.',
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
  'invalid_opening_quantity' =>
    'Enter the opening stock as a whole number of units, at most '
        '$maximumCatalogOpeningQuantity - or leave it blank if the product has '
        'none yet.',
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
///
/// **A route again since 2026-09-02**, which is what it was before it spent a
/// week as a sheet body. The `ListView` and the pinned action bar never
/// changed; what came back is the page chrome around them, and with it a
/// toolbar that names the errand and a way out of it that is not a drag.
///
/// **§7's "title appears once", and the toolbar is where.** `AppScaffold` puts
/// the title and its subtitle in the bar, so nothing repeats them in the body.
final class _CatalogProductFormScreen extends StatelessWidget {
  const _CatalogProductFormScreen({
    required this.screenKey,
    required this.scrollKey,
    required this.title,
    this.subtitle,
    required this.form,
    required this.actions,
  });

  final Key screenKey;
  final Key scrollKey;
  final String title;
  final String? subtitle;
  final Widget form;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return AppScaffold(
      key: screenKey,
      title: title,
      subtitle: subtitle,
      // §4.2's row for a form rather than the `records` row the catalog behind
      // it takes: a price and a name do not want 1200 pixels of line length.
      contentWidth: AppContentWidth.reading,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            // The fields scroll; the action pair below them does not, so the
            // control that submits the form is reachable from any scroll
            // position without hunting for it.
            child: ListView(
              key: scrollKey,
              padding: EdgeInsets.fromLTRB(
                tokens.spacing.s20,
                tokens.spacing.s8,
                tokens.spacing.s20,
                tokens.spacing.s24,
              ),
              children: <Widget>[form],
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
    required this.openingQuantity,
    required this.canRecordCost,
    required this.selectedCategoryId,
    required this.image,
    required this.busy,
    required this.onCategorySelected,
    required this.onChooseImage,
    required this.onImageChanged,
    required this.session,
    required this.backgroundRemover,
  });

  final List<TenantCategory> categories;
  final bool moreCategories;
  final TextEditingController name;
  final TextEditingController sku;
  final TextEditingController price;
  final TextEditingController cost;

  /// What the business already holds, blank when it holds none.
  ///
  /// A plain controller rather than a validated figure, for the reason every
  /// other field here is one: what was typed is what decides whether the amount
  /// is recordable, and `tenantCatalogOpeningQuantity` is what decides it.
  final TextEditingController openingQuantity;
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
  }

  void _removeImage() {
    setState(() => _image = null);
    widget.onImageChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final choose = widget.onChooseImage;
    return _CatalogProductFormScreen(
      screenKey: const ValueKey('catalog-management-add-screen'),
      scrollKey: const ValueKey('catalog-management-add-scroll'),
      title: 'Add product',
      form: _FormWithImageWell(
        well: choose == null
            ? null
            : _ProductImageWell(
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
          // **Optional, and blank is the ordinary case.** A product being added
          // for the first time usually holds nothing yet; one being brought
          // across from a shelf that already exists usually does. Deliberately
          // not part of `_canSubmit`, so nobody has to type a zero to add a
          // product, and whole units only - stock is counted, not measured.
          AppTextField(
            key: const ValueKey('catalog-management-product-quantity'),
            controller: widget.openingQuantity,
            enabled: !widget.busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: false),
            label: 'Opening stock (optional)',
            leading: Icons.inventory_2_outlined,
            helper:
                'How many units are on the shelf now. It is recorded in the '
                'stock ledger as an opening balance, so the figure says where '
                'it came from.',
          ),
          SizedBox(height: tokens.spacing.s8),
          AppSelect<String>(
            key: const ValueKey('catalog-management-product-category'),
            label: 'Category',
            value: _categoryId,
            helper: widget.moreCategories
                // Reachable only past `maximumCatalogCategoryScan`, which is
                // the figure the server refuses a name-resolving import at. It
                // used to mean "there is a second page" and meant it often.
                ? 'This business has more categories than any screen here '
                      'reads, so some are not listed.'
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

/// The categories route: what the till groups by, and the only screen that
/// changes it.
///
/// **A screen rather than the dialog it was, at the developer's direction on
/// 2026-09-04.** The dialog put three identical full-width *Rename* buttons in
/// a column with a paginator and a text field under them, on a scrim, at
/// whatever height the content happened to reach - a control panel rather than
/// a place. Categories are the spine of the catalog and of the till's filter
/// row, and they deserve the treatment the catalog itself gets.
///
/// **Nothing about the flow changed with the layout.** The same page is read,
/// the same rename dialog opens, the same confirmation guards the same write,
/// and both controls keep the keys they had. What changed is that a category
/// is drawn as a record now - a mark, a name, one affordance - instead of as a
/// label beside a button competing with it for width.
final class _CategoriesScreen extends StatefulWidget {
  const _CategoriesScreen({
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
  State<_CategoriesScreen> createState() => _CategoriesScreenState();
}

final class _CategoriesScreenState extends State<_CategoriesScreen> {
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
    return AppScaffold(
      key: const ValueKey('inventory-categories-screen'),
      title: 'Categories',
      subtitle: 'How the till groups what you sell.',
      // A column of short names takes reading width, not a table's. §4.2.
      contentWidth: AppContentWidth.reading,
      body: FutureBuilder<TenantCatalogPage<TenantCategory>>(
        key: ValueKey('inventory-category-page-$_page-$_generation'),
        future: _load(),
        builder: (context, snapshot) {
          final page = snapshot.data;
          final reading = snapshot.connectionState != ConnectionState.done;
          return ListView(
            key: const ValueKey('inventory-categories-scroll'),
            padding: EdgeInsets.fromLTRB(
              tokens.spacing.s20,
              tokens.spacing.s8,
              tokens.spacing.s20,
              tokens.spacing.s24,
            ),
            children: <Widget>[
              if (reading)
                const LoadingState(message: 'Reading your categories')
              else if (snapshot.hasError)
                const EmptyState(
                  key: ValueKey('inventory-categories-unreadable'),
                  title: 'Categories could not be read',
                  hint: 'Check the connection, then open this again.',
                  illustration: 'no-data.svg',
                )
              else if (page == null || page.items.isEmpty)
                EmptyState(
                  key: const ValueKey('inventory-categories-empty'),
                  title: _page == 0
                      ? 'No categories yet'
                      : 'Nothing on this page',
                  hint: _page == 0
                      ? 'A category groups products in the catalog and filters '
                            'them at the till.'
                      : null,
                  illustration: 'my-files.svg',
                )
              else
                _CategoryList(
                  categories: page.items,
                  onRename: _working
                      ? null
                      : (category) => _run(() => widget.onRename(category)),
                ),
              if (page != null && !reading) ...<Widget>[
                SizedBox(height: tokens.spacing.s16),
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
                SizedBox(height: tokens.spacing.s24),
                _CategoryComposer(
                  name: widget.name,
                  busy: _working || widget.busy,
                  onAdd: () => _run(widget.onAdd),
                  onChanged: () => setState(() {}),
                ),
              ],
              SizedBox(height: tokens.spacing.s16),
              // The one fact about this screen that is not visible on it, and
              // the one somebody hunting for a delete control needs.
              Text(
                'Categories are renamed here, never deleted.',
                key: const ValueKey('inventory-categories-scope'),
                style: tokens.typography.caption.copyWith(
                  color: tokens.colors.text.tertiary,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The categories on this page, as one bordered surface rather than as a
/// column of buttons.
final class _CategoryList extends StatelessWidget {
  const _CategoryList({required this.categories, required this.onRename});

  final List<TenantCategory> categories;

  /// Null while a write is in flight, which disables every row at once - a
  /// second rename landing on top of the first is the state this prevents.
  final ValueChanged<TenantCategory>? onRename;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final rename = onRename;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final (index, category) in categories.indexed)
            DecoratedBox(
              decoration: BoxDecoration(
                // A hairline between rows rather than a border around each:
                // one list of categories, not a stack of cards.
                border: index == 0
                    ? null
                    : Border(
                        top: BorderSide(
                          color: tokens.colors.surface.borderSubtle,
                        ),
                      ),
              ),
              child: _CategoryRow(
                category: category,
                onRename: rename == null ? null : () => rename(category),
              ),
            ),
        ],
      ),
    );
  }
}

final class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category, required this.onRename});

  final TenantCategory category;
  final VoidCallback? onRename;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return PressSurface(
      // The key the button carried, on the control that replaced it.
      key: ValueKey('inventory-rename-${category.id}'),
      borderRadius: BorderRadius.circular(tokens.radius.md),
      onPressed: onRename,
      // §9: a pencil is conventional but it is not a word, so the row itself
      // says what pressing it does.
      semanticLabel: 'Rename ${category.name}',
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.s12),
        child: Row(
          children: <Widget>[
            _CategoryMark(name: category.name),
            SizedBox(width: tokens.spacing.s12),
            Expanded(
              child: Text(
                category.name,
                style: tokens.typography.titleMedium.copyWith(
                  color: tokens.colors.text.primary,
                ),
              ),
            ),
            SizedBox(width: tokens.spacing.s8),
            Icon(
              Icons.edit_outlined,
              size: AppButton.iconSize,
              color: onRename == null
                  ? tokens.colors.text.tertiary
                  : tokens.colors.text.secondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// A category's initials, on the ground every picture-shaped thing uses.
///
/// A category has no image and never will. This is what gives its row the same
/// left edge as a product's, so the two read as the same kind of thing.
final class _CategoryMark extends StatelessWidget {
  const _CategoryMark({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return SizedBox.square(
      dimension: tokens.spacing.s40,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.colors.surface.overlay,
          borderRadius: BorderRadius.circular(tokens.radius.md),
        ),
        child: Center(
          child: Text(
            TenantInitialsAvatar.initialsOf(name),
            style: tokens.typography.labelMedium.copyWith(
              color: tokens.colors.text.secondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Adding one: kept where it was in the order, given a surface of its own.
final class _CategoryComposer extends StatelessWidget {
  const _CategoryComposer({
    required this.name,
    required this.busy,
    required this.onAdd,
    required this.onChanged,
  });

  final TextEditingController name;
  final bool busy;
  final VoidCallback onAdd;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'Add a category',
            style: tokens.typography.labelEyebrow.copyWith(
              color: tokens.colors.text.secondary,
            ),
          ),
          SizedBox(height: tokens.spacing.s12),
          AppTextField(
            key: const ValueKey('catalog-management-category-name'),
            controller: name,
            maxLength: maximumCatalogNameLength,
            label: 'Category name',
            onChanged: (_) => onChanged(),
          ),
          SizedBox(height: tokens.spacing.s12),
          AppButton(
            key: const ValueKey('catalog-management-add-category'),
            label: 'Add category',
            icon: Icons.new_label_outlined,
            tier: AppButtonTier.primary,
            expand: true,
            onPressed: busy || name.text.trim().isEmpty ? null : onAdd,
          ),
        ],
      ),
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
    final form = _FormWithImageWell(
      well: widget.canChangeImage
          ? _ProductImageWell(
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
            // **These four paragraphs were a confirmation dialog until
            // 2026-09-04.** They are the same sentences, moved to where they
            // can be read *while* the fields are being changed rather than on
            // a second screen after the decision was made. A consequence read
            // after the fact is a consequence answered by reflex.
            'Every field is filled in with what the product holds now. '
            'Change the ones that are wrong and save them together: a '
            'correction is checked against the whole product, so one that '
            'leaves a different field unreadable is refused outright.\n\n'
            'Every correction is recorded permanently against the product, '
            'with who made it and what each field held before. Nothing else '
            'about the product changes: its stock is untouched, its identity '
            'stays the same, and every sale, return, and reported figure '
            'already recorded still names it.\n\n'
            'A new price applies to the next sale, and sales already recorded '
            'keep the price they were sold at. A unit cost works the same way: '
            'every sale records what a unit cost at the moment of that sale, '
            'so correcting it prices the next sale and never changes a profit '
            'already reported.\n\n'
            'The till matches a scan against the code, so changing it stops '
            'the old one finding this product. Nothing makes a code unique '
            'either - if another product already scans as the new one, the '
            'till refuses that scan rather than picking one.',
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
      title: 'Edit item',
      subtitle: widget.product.name,
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
  });

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

  /// Separate from [_busy] so the framing button can carry its own spinner:
  /// the two actions take different amounts of time for different reasons, and
  /// one shared flag would put the wand's spinner on a download.
  bool _fetching = false;
  TenantBackgroundRemovalFailure? _failure;
  String? _fetchFailure;

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

  /// Whether there is a photograph to frame - chosen here or already saved.
  bool get _canFrame => widget.image != null || _savedImageUrl != null;

  Uri? get _savedImageUrl => _showsSavedImage ? widget.product?.imageUrl : null;

  /// Opens the framing editor, downloading the saved photograph first if that
  /// is the one on display.
  ///
  /// **The cut-out button's rule does not apply here**, and the difference is
  /// worth naming because the two controls sit side by side. A cut-out is a
  /// paid call against a photograph somebody just chose; framing is a local
  /// redraw, and refusing to do it to a saved picture would mean re-picking a
  /// file off the phone to move a bottle two centimetres left. So this one
  /// fetches. The download is the same request that drew the picture on the
  /// page behind this form, and it is the only network call in the well - the
  /// two states it can fail in are reported in place.
  Future<void> _frame() async {
    if (_busy || _fetching) return;
    final chosen = widget.image;
    final TenantProductImageCandidate candidate;
    if (chosen != null) {
      candidate = chosen;
    } else {
      final url = _savedImageUrl;
      if (url == null) return;
      setState(() {
        _fetching = true;
        _fetchFailure = null;
      });
      try {
        candidate = await fetchProductImage(url);
      } on TenantProductImageException catch (error) {
        if (!mounted) return;
        setState(() {
          _fetching = false;
          _fetchFailure = error.code == 'image_unreachable'
              ? 'That photograph could not be downloaded. Check the '
                    'connection and try again.'
              : 'That photograph could not be read well enough to move it. '
                    'Replace the image instead.';
        });
        return;
      }
      if (!mounted) return;
      setState(() => _fetching = false);
    }
    final framed = await showProductFramingEditor(context, image: candidate);
    if (!mounted || framed == null) return;
    setState(() {
      _failure = null;
      _fetchFailure = null;
    });
    widget.onImageChanged(framed);
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
        // **No `SectionHeading('Product image')` here since 2026-08-26.** The
        // column is plainly a picture and its controls - above the fields on a
        // phone, beside them on a wider screen - and the heading was naming
        // what the reader could already see, which is §7's own complaint about
        // it.
        //
        // The lesser of the old form's 350 and a square of whatever width this
        // well was given, so a phone draws a square rather than a letterbox and
        // a desktop draws the figure the old form drew.
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
        SizedBox(height: tokens.spacing.s8),
        // **Its own row rather than a fourth control beside the others.** The
        // action row above is already a label and two 48-pixel squares, and a
        // phone at 411 leaves *Replace image* about 200 for its own label;
        // taking another 56 out of that is what makes a button read
        // "Replace i…". This also gives the action a name, which a crop glyph
        // on its own does not have - §9 again.
        //
        // Drawn always and disabled without a chosen photograph, which is the
        // distinction `_offersRemoval` draws: framing needs no service and no
        // particular role, so it is always available and sometimes not right
        // now, and that is what a disabled control says.
        AppButton(
          key: const ValueKey('inventory-frame-image'),
          label: 'Position and zoom',
          icon: Icons.crop,
          expand: true,
          loading: _fetching,
          onPressed: _busy || _fetching || !_canFrame ? null : _frame,
        ),
        if (_fetchFailure case final failure?) ...<Widget>[
          SizedBox(height: tokens.spacing.s12),
          Callout(
            key: const ValueKey('inventory-frame-image-failed'),
            status: AppStatus.problem,
            message: failure,
          ),
        ],
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
///
/// **The first two must be framed identically.** A person chooses a picture,
/// sees it here, and saves; if the saved branch drew it differently the act of
/// saving would appear to have changed their photograph. So the `cover` below
/// and `TenantProductVisual`'s are one decision in two places - change either
/// and change both.
final class _ProductImagePreview extends StatelessWidget {
  const _ProductImagePreview({required this.image, required this.product});

  final TenantProductImageCandidate? image;

  /// Non-null only where the saved photograph is what should be shown.
  final TenantProduct? product;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final radius = BorderRadius.circular(tokens.radius.md);
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
  const _FormWithImageWell({required this.well, required this.fields});

  /// Null where the form offers no image at all - no store is configured, or
  /// this session may not change one - in which case the fields are the whole
  /// form and there is no second column to make.
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
    final wide = AppLayout.contract.isAtLeast(
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
