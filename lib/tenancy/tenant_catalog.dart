import 'dart:convert';

import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../ui/record_list.dart';
import '../ui/routes.dart';
import '../ui/scaffold.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'tenant_id.dart';
import 'tenant_paths.dart';
import 'tenant_repository.dart';
import 'tenant_route_guard.dart';
import 'tenant_session_controller.dart';
import 'tenant_types.dart';

const int _maximumSafeInteger = 9007199254740991;

/// Strict read model for `tenants/{tenantId}/categories/{categoryId}`.
final class TenantCategory {
  TenantCategory.fromSnapshot(TenantQueryDocumentSnapshot snapshot)
    : id = _documentId(snapshot.path, TenantCollection.categories),
      name = _requiredTrimmedString(snapshot.data, 'name');

  final String id;
  final String name;
}

/// What a surface calls a category whose name it does not hold, opening a line.
///
/// Every catalog surface reads **one bounded page** of categories and then has
/// to name the category of a product that page may not hold. Two different
/// things produce that and from here they are indistinguishable, because both
/// arrive as an ID resolving to nothing: a business with more categories than
/// the page shows, and a product filed under a category document that cannot be
/// read at all. So the wording says only what is known - this surface is not
/// listing it - and deliberately neither claims the category exists elsewhere
/// nor hides the fact that the product has one.
const String unlistedTenantCategoryLabel = 'Category not listed here';

/// The same answer inside a sentence: "filed under a category not listed here".
const String unlistedTenantCategoryPhrase = 'a category not listed here';

/// The name lookup one surface's categories provide, keyed by document ID.
Map<String, String> tenantCategoryNames(Iterable<TenantCategory> categories) =>
    <String, String>{
      for (final category in categories) category.id: category.name,
    };

/// What a person is told a product is filed under, opening a line.
///
/// **Never the document ID.** Eight places named a category before this function
/// existed, through five copies of the same lookup, and every one of them could
/// state the ID: an import preview told somebody who had typed `Bakery` that
/// their product was filed under `cat-bakery`, and a product whose category
/// document is missing was listed under `cat-not-cached`. A document ID is the
/// system's name for a thing and never the shopkeeper's.
///
/// Deliberately unlike `tenantStaffLabel`, which keeps a UID visible even beside
/// a resolved name: a UID is the identity every sale, shift, and audit record is
/// attributed by, so a person reading a history needs it. A category ID is
/// referred to by nothing a person ever sees.
String tenantCategoryLabel(
  String categoryId, {
  required Map<String, String> names,
}) => names[categoryId] ?? unlistedTenantCategoryLabel;

/// The same answer as [tenantCategoryLabel], inside a sentence.
String tenantCategoryPhrase(
  String categoryId, {
  required Map<String, String> names,
}) => names[categoryId] ?? unlistedTenantCategoryPhrase;

/// The most categories any surface in this app will read.
///
/// The same figure the server's `MAXIMUM_IMPORT_CATEGORY_SCAN` enforces while
/// resolving a spreadsheet's category names, and deliberately not a second
/// opinion about it: a client that offered a category the import would then
/// refuse to resolve would be offering a choice that does not work.
const int maximumCatalogCategoryScan = 500;

/// How many categories one page of that scan asks for.
///
/// The largest page `readCollectionPage` will serve, so the scan is ten reads at
/// the bound rather than twenty-five.
const int _categoryScanPageSize = 50;

/// Strict read model for `tenants/{tenantId}/products/{productId}`.
///
/// New documents use `categoryId`. The legacy `category` alias is accepted
/// only while migration is in progress and must agree when both are present.
final class TenantProduct {
  factory TenantProduct.fromSnapshot(TenantQueryDocumentSnapshot snapshot) =>
      TenantProduct.fromDocument(path: snapshot.path, data: snapshot.data);

  /// Decodes one product read by its exact canonical path.
  ///
  /// A stock surface re-reads the product document rather than carrying a
  /// figure between screens, so the quantity it states is always the one the
  /// server most recently recorded.
  TenantProduct.fromDocument({
    required String path,
    required Map<String, Object?> data,
  }) : id = _documentId(path, TenantCollection.products),
       tenantId = _pathTenantId(path, TenantCollection.products),
       name = _requiredTrimmedString(data, 'name'),
       sku = _requiredTrimmedString(data, 'SKU'),
       price = _nonNegativeFiniteNumber(data, 'price'),
       cost = _optionalNonNegativeFiniteNumber(data, 'cost'),
       quantity = _signedSafeInteger(data, 'quantity'),
       categoryId = _categoryId(data),
       imageUrl = _optionalHttpsUrl(data, 'image'),
       // Read permissively on purpose: every product written before retiring
       // became a flag carries no such field, and this model is strict enough
       // that one product it refuses makes the whole cached catalog a miss.
       // Absent therefore means "in the catalog", which is what it always was.
       retired = data['retired'] == true;

  final String id;

  /// The business this exact document path belongs to. A mutation gateway
  /// compares it against its own session, so a product decoded from one
  /// business can never be adjusted while another is open.
  final String tenantId;

  final String name;
  final String sku;
  final double price;

  /// What the business paid for one unit, when it has recorded it.
  ///
  /// **Null is the normal case, not a fault.** No product created before cost
  /// existed carries one, and this read model is strict: one product it refuses
  /// makes the *whole* cached catalog a miss, so requiring `cost` would stop
  /// every existing business selling. A sale line records whatever this holds at
  /// the moment of the sale and never consults it again — see
  /// `CheckoutDraftCoordinator`.
  final double? cost;

  final int quantity;
  final String categoryId;
  final Uri? imageUrl;

  /// Whether this product has been taken out of the catalog.
  ///
  /// **Retired is not deleted, and not hidden from the books.** Reports and
  /// stock valuations count a retired product exactly as before; it simply holds
  /// nothing, because `setProductRetired` writes the movement that clears it in
  /// the same transaction. What retiring changes is that the till will not offer
  /// it and the catalog marks it - the document stays, so every past sale line
  /// and every ledger entry below it still names something that answers.
  final bool retired;
}

/// A product's standing, as one of §2.1's five - or nothing at all.
///
/// **Only a product whose recorded stock has reached or passed zero has a
/// standing to state.** What is a judgement is the silence on every other
/// product: `RecordList`'s own rule is that a list where every row wears a badge
/// is a list with no signal in it, and an ordinary stock figure is the ordinary
/// case rather than a standing.
///
/// **The badge states the figure and not a verdict on selling, and that is the
/// correction.** It read `Out of stock` until Phase 04, which is the phrase
/// Phase 03 had already refused on the till one file over
/// (`checkout_cart_panel.dart:1670`): this product never blocks a sale on a
/// stock count, so "out of stock" asserts a state the app does not have. On the
/// two surfaces that list every product it was the *only* thing said about a
/// zero or negative figure, and a cashier reading a red badge on a catalog they
/// may only read is exactly the person who would conclude they cannot sell.
/// Phase 04's second acceptance criterion is that stock display does not imply
/// sales are blocked by availability; ST-039 draws this same row as `Below zero.
/// A sale is never blocked by a stock count.`
///
/// So the label is the quantity in Phase 03's own words - `-3 in stock`,
/// `0 in stock` - and [tenantCatalogStockNeverBlocks] states the rest of the
/// design's sentence once per page. §2.1's `problem` is kept: a figure at or
/// below zero is worth a correction, and §9 is satisfied because the words
/// carry the meaning rather than the colour.
///
/// Shared by both catalog surfaces rather than written twice, for the reason
/// [tenantCategoryLabel] is: five copies of one lookup is how two screens come
/// to disagree about what the same product is.
RecordStatus? tenantProductStanding(TenantProduct product) {
  // **Retired outranks the stock figure, and is not a fault.** A retired
  // product holds nothing by construction - the retirement clears it through
  // the ledger - so the zero underneath is the expected consequence rather than
  // a problem to act on. Drawing `0 in stock` in red over it would report the
  // one state that is deliberate as the one state that needs attention.
  if (product.retired) {
    return RecordStatus(
      status: AppStatus.info,
      label: 'Retired',
      badgeKey: ValueKey('product-retired-standing-${product.id}'),
    );
  }
  return product.quantity > 0
      ? null
      : RecordStatus(
          status: AppStatus.problem,
          label: '${product.quantity} in stock',
          badgeKey: ValueKey('product-stock-standing-${product.id}'),
        );
}

/// The sentence both catalog surfaces owe a person reading a stock figure.
///
/// **ST-039's own words, and the app already said the second half of them
/// twice** - the till's freshness line (`checkout_cart_panel.dart:1282`) and the
/// stock route's disclosure (`stock_adjustment_panel.dart:528`) both end "a sale
/// is never blocked by a stock count". Neither catalog surface said it at all,
/// which is what left [tenantProductStanding]'s badge standing unqualified on
/// the two screens that list every product.
///
/// **Stated always, not only when a product is at or below zero.** A conditional
/// section that is invisible in every capture is not covered - the trap this
/// repository has now paid for three times - and the till states its own version
/// unconditionally for the same reason.
///
/// It names no route: a cashier reading this line has no stock route to be sent
/// to, and the two surfaces that do offer one already offer it per product.
const String tenantCatalogStockNeverBlocks =
    'A sale is never blocked by a stock count. A product whose recorded '
    'quantity has reached or passed zero can still be sold.';

/// The three facts both catalog surfaces state about a product, in the order
/// §4.3's table draws them as columns.
///
/// **The category is not among them, and that is a decision.** It is the
/// record's `subtitle` - §5.2's identity row explicitly admits "an address, a
/// code, a category" as a second identifying line - because as an attribute it
/// reads "Category: Category not listed here" whenever the product is filed
/// under one this page did not read, which is the one case the wording exists
/// for.
///
/// **Nothing here is marked out of the narrow form.** Three key-value lines fit
/// a card at every band, and `RecordAttribute.inNarrowForm` drops a fact rather
/// than shortening one - so using it to reach a tidier card would cost a
/// shopkeeper the code they scan by. `PLAN.md` predicted the catalog would be
/// the concession's first consumer; it is not, and the prediction was sized off
/// a six-column table that a subtitle makes five.
List<RecordAttribute> tenantProductAttributes(
  TenantProduct product, {
  required String keyPrefix,
}) => <RecordAttribute>[
  RecordAttribute(
    label: 'Code',
    value: product.sku,
    kind: RecordValueKind.code,
    valueKey: ValueKey('$keyPrefix-code-${product.id}'),
    // **Twice an ordinary column, and the first render is why.** A code is
    // §2.2's "compared character by character" string and a real one is a
    // 13-digit barcode; at an equal share the table wrapped it to
    // `61611000000` / `19`, which is the one thing a code must never do. The
    // knob is `RecordAttribute.flex`, which §4.3 already gives the caller for
    // exactly this, so nothing about the component moved.
    flex: 2,
  ),
  RecordAttribute(
    label: 'In stock',
    value: '${product.quantity}',
    kind: RecordValueKind.code,
    valueKey: ValueKey('$keyPrefix-stock-${product.id}'),
  ),
  RecordAttribute(
    label: 'Unit price',
    value: product.price.toStringAsFixed(2),
    kind: RecordValueKind.money,
    valueKey: ValueKey('$keyPrefix-price-${product.id}'),
  ),
];

/// One typed catalog page with a document-ID cursor.
final class TenantCatalogPage<T> {
  TenantCatalogPage({
    required List<T> items,
    required this.nextCursor,
    required this.hasMore,
  }) : items = List<T>.unmodifiable(items);

  final List<T> items;
  final String? nextCursor;
  final bool hasMore;
}

/// The bounded data initially rendered by the temporary catalog route.
final class TenantCatalogSnapshot {
  const TenantCatalogSnapshot({
    required this.categories,
    required this.products,
  });

  final TenantCatalogPage<TenantCategory> categories;
  final TenantCatalogPage<TenantProduct> products;
}

/// Read-only product/category repository bound to one canonical session.
final class TenantCatalogRepository extends TenantReadRepository {
  TenantCatalogRepository({
    required super.session,
    required TenantDataReader reader,
    TenantProductSearchReader? productSearchReader,
  }) : _collectionReader = reader,
       _productSearchReader =
           productSearchReader ??
           (reader is TenantProductSearchReader
               ? reader as TenantProductSearchReader
               : null),
       super(reader: reader);

  final TenantCollectionReader _collectionReader;
  final TenantProductSearchReader? _productSearchReader;

  Future<TenantCatalogPage<TenantCategory>> loadCategories({
    int pageSize = 20,
    String? cursor,
  }) async {
    final page = await readCollectionPage(
      TenantCollection.categories,
      collectionReader: _collectionReader,
      pageSize: pageSize,
      cursor: cursor,
    );
    return TenantCatalogPage<TenantCategory>(
      items: page.items.map(TenantCategory.fromSnapshot).toList(),
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
    );
  }

  /// Every category this business holds, across as many pages as it takes.
  ///
  /// **For the surfaces that have to offer a complete choice.** Filing a product
  /// under a category, moving one, and filtering the catalog by one all read a
  /// single page - so a business past that page had categories it could see in
  /// the Categories screen and could not select anywhere else. The screen said
  /// so ("this list shows the first page"), which made it an honest defect
  /// rather than a silent one, but it was still a category the product could not
  /// be put in.
  ///
  /// **Bounded, and at the figure the server already chose.** `importProducts`
  /// scans at most [maximumCatalogCategoryScan] categories while resolving names
  /// and refuses the request beyond that, so one business-wide limit governs both
  /// - a client that happily loaded more than the server will resolve would only
  /// be offering a choice the import then refuses.
  ///
  /// [TenantCatalogPage.hasMore] therefore means something much rarer than it
  /// did: not "there is another page" but "this business holds more categories
  /// than anything here will read".
  Future<TenantCatalogPage<TenantCategory>> loadEveryCategory({
    int maximum = maximumCatalogCategoryScan,
  }) async {
    final items = <TenantCategory>[];
    String? cursor;
    while (items.length < maximum) {
      final page = await loadCategories(
        pageSize: _categoryScanPageSize,
        cursor: cursor,
      );
      items.addAll(page.items);
      // **Both conditions, not just `hasMore`.** A page that reports more and
      // hands back no cursor would spin this loop for ever against the same
      // page; treating a missing cursor as the end is the only reading that
      // terminates, and it degrades to the behaviour this had before.
      if (!page.hasMore || page.nextCursor == null) {
        return TenantCatalogPage<TenantCategory>(
          items: List<TenantCategory>.unmodifiable(items),
          nextCursor: null,
          hasMore: false,
        );
      }
      cursor = page.nextCursor;
    }
    return TenantCatalogPage<TenantCategory>(
      items: List<TenantCategory>.unmodifiable(items.take(maximum)),
      nextCursor: cursor,
      hasMore: true,
    );
  }

  Future<TenantCatalogPage<TenantProduct>> loadProducts({
    int pageSize = 20,
    String? cursor,
  }) async {
    final page = await readCollectionPage(
      TenantCollection.products,
      collectionReader: _collectionReader,
      pageSize: pageSize,
      cursor: cursor,
    );
    return TenantCatalogPage<TenantProduct>(
      items: page.items.map(TenantProduct.fromSnapshot).toList(),
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
    );
  }

  /// Reads one stable backend page for the inventory search and filters.
  ///
  /// Unlike [loadProducts], this never routes through the generic collection
  /// reader: its array membership predicate, quantity range, and ordered cursor
  /// belong to the dedicated product-search boundary.
  Future<TenantCatalogPage<TenantProduct>> searchProducts({
    int pageSize = 20,
    String? cursor,
    String? searchPrefix,
    String? categoryId,
    TenantProductStockFilter stock = TenantProductStockFilter.all,
  }) async {
    if (pageSize < 1 || pageSize > 50) {
      throw RangeError.range(pageSize, 1, 50, 'pageSize');
    }
    final searchReader = _productSearchReader;
    if (searchReader == null) {
      throw StateError('This reader does not support tenant product search.');
    }
    final prefix = searchPrefix?.trim();
    if (prefix != null &&
        (prefix.length < 2 || prefix != prefix.toLowerCase())) {
      throw ArgumentError.value(
        searchPrefix,
        'searchPrefix',
        'Must be a normalized prefix of at least two characters.',
      );
    }
    final safeCategoryId = categoryId == null
        ? null
        : validateTenantDocumentId(categoryId, fieldName: 'categoryId');
    final position = cursor == null ? null : _decodeProductCursor(cursor);
    if (stock != TenantProductStockFilter.all &&
        position != null &&
        position.quantity == null) {
      throw const FormatException('The product cursor has no stock position.');
    }
    final collectionPath = paths.collectionPath(TenantCollection.products);
    final snapshots = await searchReader.searchTenantProducts(
      TenantProductSearchQuery.scoped(
        collectionPath: collectionPath,
        limit: pageSize + 1,
        stock: stock,
        searchPrefix: prefix,
        categoryId: safeCategoryId,
        startAfter: position,
      ),
    );
    if (snapshots.length > pageSize + 1) {
      throw const TenantScopeViolation(
        'Product search returned more documents than requested.',
      );
    }
    final expectedPrefix = '$collectionPath/';
    final seen = <String>{};
    for (final snapshot in snapshots) {
      if (!snapshot.path.startsWith(expectedPrefix) ||
          snapshot.path.substring(expectedPrefix.length).contains('/')) {
        throw TenantScopeViolation(
          'Product search escaped $collectionPath with ${snapshot.path}.',
        );
      }
      if (!seen.add(snapshot.path)) {
        throw const TenantScopeViolation(
          'Product search returned the same document twice.',
        );
      }
    }
    final hasMore = snapshots.length > pageSize;
    final visible = snapshots.take(pageSize).toList(growable: false);
    final last = visible.isEmpty ? null : visible.last;
    return TenantCatalogPage<TenantProduct>(
      items: visible.map(TenantProduct.fromSnapshot).toList(growable: false),
      nextCursor: hasMore && last != null
          ? _encodeProductCursor(
              TenantProductSearchPosition(
                searchName: _requiredTrimmedString(last.data, 'searchName'),
                documentId: last.path.substring(expectedPrefix.length),
                quantity: stock == TenantProductStockFilter.all
                    ? null
                    : _signedSafeInteger(last.data, 'quantity'),
              ),
            )
          : null,
      hasMore: hasMore,
    );
  }

  Future<TenantCatalogSnapshot> loadInitial() async {
    final pages = await Future.wait<Object>([
      loadEveryCategory(),
      loadProducts(),
    ]);
    return TenantCatalogSnapshot(
      categories: pages[0] as TenantCatalogPage<TenantCategory>,
      products: pages[1] as TenantCatalogPage<TenantProduct>,
    );
  }
}

String _encodeProductCursor(TenantProductSearchPosition position) =>
    base64Url.encode(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'v': 1,
          'name': position.searchName,
          'id': position.documentId,
          if (position.quantity != null) 'quantity': position.quantity,
        }),
      ),
    );

TenantProductSearchPosition _decodeProductCursor(String encoded) {
  try {
    final decoded = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(encoded))),
    );
    if (decoded is! Map<String, dynamic> || decoded['v'] != 1) {
      throw const FormatException();
    }
    final name = decoded['name'];
    final id = decoded['id'];
    final quantity = decoded['quantity'];
    if (name is! String ||
        name.isEmpty ||
        id is! String ||
        (quantity != null && quantity is! int)) {
      throw const FormatException();
    }
    return TenantProductSearchPosition(
      searchName: name,
      documentId: validateTenantDocumentId(id, fieldName: 'cursor.id'),
      quantity: quantity as int?,
    );
  } catch (_) {
    throw const FormatException('The product page cursor is invalid.');
  }
}

/// Builds the per-product stock route for one already-decoded product.
///
/// The composition root supplies it; the catalog only passes the product it
/// already proved. While it is absent the route stays unreachable and the
/// catalog is exactly the read-only surface it was before.
///
/// **It carried a `TenantProductStockMode` between 2026-08-25 and 2026-08-26**,
/// so that one builder could open either half of a route that has since stopped
/// having halves. Correcting is [TenantProductAdjustStockOpener] now — not a
/// route at all — and this builds the ledger and only the ledger.
typedef TenantProductRouteBuilder = Widget Function(TenantProduct product);

/// Opens the per-product stock **correction** over the surface that asked.
///
/// **A different shape from the builder above, because a sheet is not a
/// route.** A route builder answers with a widget for somebody else to push;
/// a sheet owns its own presentation, its own dismissal and the snack bar it
/// leaves behind, so what the composition root supplies here is the errand
/// rather than the screen. It takes the calling `BuildContext` for the same
/// reason: the sheet is shown over that surface and reports back to it.
typedef TenantProductAdjustStockOpener =
    Future<void> Function(BuildContext context, TenantProduct product);

/// Builds the business-wide stock adjustment feed route.
///
/// It is supplied by the composition root for the same reason: while it is
/// absent the route stays unreachable and the catalog is exactly the read-only
/// surface it was before.
typedef TenantAdjustmentFeedRouteBuilder = Widget Function();

/// Builds the business-wide stock movement feed route, injected for the same
/// reason as its sibling above.
typedef TenantMovementFeedRouteBuilder = Widget Function();

/// Read-only catalog route. Catalog editing remains absent; the only reachable
/// actions are the guarded per-product stock route and the two business-wide
/// stock feeds, each when one is supplied.
final class TenantCatalogScreen extends StatelessWidget {
  const TenantCatalogScreen({
    super.key,
    required this.reader,
    this.allowedRoles,
    this.productStockRoute,
    this.productStockRoles = const <TenantRole>[],
    this.adjustmentFeedRoute,
    this.adjustmentFeedRoles = const <TenantRole>[],
    this.movementFeedRoute,
    this.movementFeedRoles = const <TenantRole>[],
  });

  final TenantDataReader reader;
  final Iterable<TenantRole>? allowedRoles;
  final TenantProductRouteBuilder? productStockRoute;

  /// The roles that route is offered to, decided by the inventory domain.
  final List<TenantRole> productStockRoles;

  final TenantAdjustmentFeedRouteBuilder? adjustmentFeedRoute;

  /// The roles the feed is offered to, decided by the inventory domain.
  final List<TenantRole> adjustmentFeedRoles;

  final TenantMovementFeedRouteBuilder? movementFeedRoute;

  /// The roles the feed is offered to, decided by the inventory domain.
  final List<TenantRole> movementFeedRoles;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Product catalog',
    contentWidth: AppContentWidth.records,
    body: TenantCatalogPanel(
      reader: reader,
      allowedRoles: allowedRoles,
      productStockRoute: productStockRoute,
      productStockRoles: productStockRoles,
      adjustmentFeedRoute: adjustmentFeedRoute,
      adjustmentFeedRoles: adjustmentFeedRoles,
      movementFeedRoute: movementFeedRoute,
      movementFeedRoles: movementFeedRoles,
    ),
  );
}

/// Guarded catalog content, split out to keep access behavior widget-testable.
final class TenantCatalogPanel extends StatelessWidget {
  const TenantCatalogPanel({
    super.key,
    required this.reader,
    this.allowedRoles,
    this.productStockRoute,
    this.productStockRoles = const <TenantRole>[],
    this.adjustmentFeedRoute,
    this.adjustmentFeedRoles = const <TenantRole>[],
    this.movementFeedRoute,
    this.movementFeedRoles = const <TenantRole>[],
  });

  final TenantDataReader reader;
  final Iterable<TenantRole>? allowedRoles;
  final TenantProductRouteBuilder? productStockRoute;
  final List<TenantRole> productStockRoles;
  final TenantAdjustmentFeedRouteBuilder? adjustmentFeedRoute;
  final List<TenantRole> adjustmentFeedRoles;
  final TenantMovementFeedRouteBuilder? movementFeedRoute;
  final List<TenantRole> movementFeedRoles;

  /// The catalog read, over whichever reader it is handed.
  static TenantGuardedLoader<TenantCatalogSnapshot> _readWith(
    TenantDataReader reader,
  ) =>
      (session) => TenantCatalogRepository(
        session: session,
        reader: reader,
      ).loadInitial();

  @override
  Widget build(BuildContext context) => TenantRouteGuard<TenantCatalogSnapshot>(
    allowedRoles: allowedRoles,
    load: _readWith(reader),
    loadCached: switch (reader.cached) {
      final cached? => _readWith(cached),
      null => null,
    },
    builder: (context, session, snapshot) => _CatalogContents(
      tenantId: session.tenantId,
      snapshot: snapshot,
      // The role is taken from the guarded session, never from the caller, so
      // the action disappears the moment the session stops allowing it.
      productStockRoute: session.canAccess(allowedRoles: productStockRoles)
          ? productStockRoute
          : null,
      adjustmentFeedRoute: session.canAccess(allowedRoles: adjustmentFeedRoles)
          ? adjustmentFeedRoute
          : null,
      movementFeedRoute: session.canAccess(allowedRoles: movementFeedRoles)
          ? movementFeedRoute
          : null,
    ),
  );
}

final class _CatalogContents extends StatelessWidget {
  const _CatalogContents({
    required this.tenantId,
    required this.snapshot,
    this.productStockRoute,
    this.adjustmentFeedRoute,
    this.movementFeedRoute,
  });

  final String tenantId;
  final TenantCatalogSnapshot snapshot;
  final TenantProductRouteBuilder? productStockRoute;
  final TenantAdjustmentFeedRouteBuilder? adjustmentFeedRoute;
  final TenantMovementFeedRouteBuilder? movementFeedRoute;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final categoryNames = tenantCategoryNames(snapshot.categories.items);
    return ListView(
      padding: EdgeInsets.all(tokens.spacing.s20),
      children: [
        // **A status, not a heading, and it used to be both and neither.** This
        // route's standing was a `headlineSmall` reading "Read-only catalog" at
        // the top and an uncontained paragraph at the bottom saying which of the
        // app's capabilities it does not carry - the same fact stated twice, a
        // page apart, and neither of them rendered as §2.1 requires. §2.1 gives
        // `info` the meaning *"offline, read-only, informational"*, so the
        // lookup is the document's own, and `Callout.title` is what supplies
        // the **word** the container and the glyph go with.
        Callout(
          key: const ValueKey('catalog-read-only'),
          status: AppStatus.info,
          title: 'Read-only catalog',
          message: productStockRoute == null
              ? 'Catalog changes, stock actions, checkout, returns, and '
                    'reports are not available here.'
              : 'Catalog changes, checkout, returns, and reports are not '
                    'available here. Open a product to see and correct its '
                    'stock.',
        ),
        SizedBox(height: tokens.spacing.s12),
        Text('Business: $tenantId'),
        if (adjustmentFeedRoute != null) ...[
          SizedBox(height: tokens.spacing.s12),
          AppButton(
            key: const ValueKey('catalog-adjustment-feed'),
            label: 'View recorded stock adjustments',
            icon: Icons.fact_check_outlined,
            onPressed: () => _openAdjustmentFeed(context),
          ),
        ],
        if (movementFeedRoute != null) ...[
          SizedBox(height: tokens.spacing.s12),
          AppButton(
            key: const ValueKey('catalog-movement-feed'),
            label: 'View every recorded stock movement',
            icon: Icons.swap_vert_outlined,
            onPressed: () => _openMovementFeed(context),
          ),
        ],
        SizedBox(height: tokens.spacing.s20),
        SectionHeading('Categories'),
        SizedBox(height: tokens.spacing.s8),
        if (snapshot.categories.items.isEmpty)
          const EmptyState(
            key: ValueKey('catalog-categories-empty'),
            title: 'No categories yet',
            illustration: 'empty.svg',
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final category in snapshot.categories.items)
                Chip(label: Text(category.name)),
            ],
          ),
        if (snapshot.categories.hasMore)
          Padding(
            padding: EdgeInsets.only(top: tokens.spacing.s8),
            child: const Text('More categories are available.'),
          ),
        SizedBox(height: tokens.spacing.s24),
        SectionHeading('Products'),
        SizedBox(height: tokens.spacing.s4),
        // §2.2's `caption` in `text.tertiary`, which is the weight the till
        // gives the same fact: standing context a person needs beside a figure
        // rather than the thing being looked at.
        Text(
          key: const ValueKey('catalog-stock-never-blocks'),
          tenantCatalogStockNeverBlocks,
          style: tokens.typography.caption.copyWith(
            color: tokens.colors.text.tertiary,
          ),
        ),
        SizedBox(height: tokens.spacing.s8),
        // §4.3's responsive contract. This list used to be a `Card` around a
        // `ListTile` whose subtitle carried three separate facts in one
        // bullet-separated sentence, which is the shape §5.2 replaces with
        // key-value attributes: on a table each is a column a person can scan
        // down, and on a card each is a labelled line.
        RecordList(
          identityLabel: 'Product',
          items: <RecordItem>[
            for (final product in snapshot.products.items)
              _record(context, product, categoryNames),
          ],
          // §7's Empty pattern. This is the *read-only* catalog, so there is
          // deliberately no action: a person who can add a product does it from
          // Manage catalog, and offering it here would offer it to the roles
          // that cannot.
          empty: const EmptyState(
            key: ValueKey('catalog-products-empty'),
            title: 'No products yet',
            illustration: 'empty.svg',
          ),
        ),
        // **Deliberately still a caption and not a `Callout`.** The sweep's rule
        // makes a notice about this page, this read or this role a `Callout`,
        // and a bounded page is about this read - but this line states a
        // property of the pager rather than something a person can or cannot
        // do, and its answer is the pager itself. The same decision was taken
        // for the two on the manage-catalog route.
        if (snapshot.products.hasMore)
          Padding(
            padding: EdgeInsets.only(top: tokens.spacing.s8),
            child: const Text('More products are available.'),
          ),
      ],
    );
  }

  /// One product as §5.2's rows.
  ///
  /// **The whole row used to be the control, and now the control is a
  /// control.** Opening a product's stock was a `ListTile.onTap` with nothing
  /// on screen saying so - §5.2's "never bare text links" reaches an invisible
  /// link the same way, and §4.3's table has no row to tap at all. It is a
  /// `RecordAction` now, which is a 48dp target with the verb written on it.
  /// **What decides whether it is offered is unchanged**: the guarded session
  /// resolves `productStockRoute` to null for a role the inventory domain does
  /// not admit, exactly as it did when that decided `onTap`.
  RecordItem _record(
    BuildContext context,
    TenantProduct product,
    Map<String, String> names,
  ) => RecordItem(
    id: product.id,
    // The key this screen's tests have always addressed a product by, kept
    // across the form change so they keep addressing the record rather than
    // one band's rendering of it.
    recordKey: ValueKey('catalog-product-${product.id}'),
    title: product.name,
    subtitle: tenantCategoryLabel(product.categoryId, names: names),
    subtitleKey: ValueKey('catalog-product-category-${product.id}'),
    status: tenantProductStanding(product),
    attributes: tenantProductAttributes(product, keyPrefix: 'catalog-product'),
    actions: <RecordAction>[
      if (productStockRoute != null)
        RecordAction(
          label: 'View item',
          // Not `catalog-product-stock-`, which is the "In stock" attribute's
          // own value key. One prefix with two owners, and what caught it was
          // the role test asserting this action is *absent* for a cashier: it
          // found a `Text` reading `-2` where no widget was expected.
          actionKey: ValueKey('catalog-product-view-stock-${product.id}'),
          icon: Icons.inventory_2_outlined,
          onPressed: () => _openStockRoute(context, product),
        ),
    ],
  );

  /// Opens the stock route under the same session scope this route runs in, so
  /// a tenant switch invalidates it exactly as it does every other guarded
  /// route rather than leaving a detached screen behind.
  void _openStockRoute(BuildContext context, TenantProduct product) {
    final controller = TenantSessionScope.of(context);
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => TenantSessionScope(
          controller: controller,
          child: productStockRoute!(product),
        ),
      ),
    );
  }

  /// Opens the business-wide correction feed under the same session scope, for
  /// the same reason the per-product route does.
  void _openAdjustmentFeed(BuildContext context) {
    final controller = TenantSessionScope.of(context);
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => TenantSessionScope(
          controller: controller,
          child: adjustmentFeedRoute!(),
        ),
      ),
    );
  }

  /// Opens the business-wide movement feed, which lists every entry the
  /// corrections above are only one source of, under the same session scope.
  void _openMovementFeed(BuildContext context) {
    final controller = TenantSessionScope.of(context);
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => TenantSessionScope(
          controller: controller,
          child: movementFeedRoute!(),
        ),
      ),
    );
  }
}

String _documentId(String path, TenantCollection collection) =>
    validateTenantDocumentId(_pathSegments(path, collection)[3]);

String _pathTenantId(String path, TenantCollection collection) =>
    _pathSegments(path, collection)[1];

List<String> _pathSegments(String path, TenantCollection collection) {
  final segments = path.split('/');
  if (segments.length != 4 ||
      segments[0] != 'tenants' ||
      segments[2] != collection.segment) {
    throw FormatException('Invalid ${collection.segment} document path.');
  }
  validateTenantId(segments[1]);
  return segments;
}

String _requiredTrimmedString(Map<String, Object?> map, String field) {
  final value = map[field];
  if (value is! String || value.isEmpty || value != value.trim()) {
    throw FormatException('$field must be a non-empty trimmed string.');
  }
  for (final codeUnit in value.codeUnits) {
    if (codeUnit < 0x20 || codeUnit == 0x7f) {
      throw FormatException('$field cannot contain control characters.');
    }
  }
  return value;
}

double _nonNegativeFiniteNumber(Map<String, Object?> map, String field) {
  final value = map[field];
  if (value is! num || !value.isFinite || value < 0) {
    throw FormatException('$field must be a finite non-negative number.');
  }
  return value.toDouble();
}

/// Like [_nonNegativeFiniteNumber], but absent is a valid answer.
///
/// A stored `null` and a missing key mean the same thing: this business has not
/// recorded what the product cost. A *present* but unusable value is still a
/// refusal, because silently dropping it would report a 100% margin on the
/// product whose cost someone had tried to record.
double? _optionalNonNegativeFiniteNumber(
  Map<String, Object?> map,
  String field,
) {
  final value = map[field];
  if (value == null) return null;
  if (value is! num || !value.isFinite || value < 0) {
    throw FormatException('$field must be a finite non-negative number.');
  }
  return value.toDouble();
}

int _signedSafeInteger(Map<String, Object?> map, String field) {
  final value = map[field];
  if (value is! int ||
      value < -_maximumSafeInteger ||
      value > _maximumSafeInteger) {
    throw FormatException('$field must be a signed safe integer.');
  }
  return value;
}

String _categoryId(Map<String, Object?> map) {
  final current = map['categoryId'];
  final legacy = map['category'];
  if (current == null && legacy == null) {
    throw const FormatException('categoryId is required.');
  }
  String validate(Object? value, String field) {
    if (value is! String) {
      throw FormatException('$field must be a category document ID.');
    }
    try {
      return validateTenantDocumentId(value, fieldName: field);
    } on ArgumentError {
      throw FormatException('$field must be a category document ID.');
    }
  }

  final resolved = current == null
      ? validate(legacy, 'category')
      : validate(current, 'categoryId');
  if (legacy != null && validate(legacy, 'category') != resolved) {
    throw const FormatException(
      'category and categoryId must identify the same category.',
    );
  }
  return resolved;
}

Uri? _optionalHttpsUrl(Map<String, Object?> map, String field) {
  final value = map[field];
  if (value == null || value == '') return null;
  if (value is! String || value != value.trim()) {
    throw FormatException('$field must be an HTTPS URL when present.');
  }
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    throw FormatException('$field must be an HTTPS URL when present.');
  }
  return uri;
}
