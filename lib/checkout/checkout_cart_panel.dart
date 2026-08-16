/// The till: `design.md` §11 step **7**, in the components that already exist.
///
/// **This screen had none of the redesign until 2026-08-16, and it is the one a
/// cashier uses all day.** Ten chunks migrated the back office around it because
/// §11 step 7 also names four components nobody has specified. Those four are a
/// reason not to *finish* the step and were never a reason not to start it: the
/// tier inversion, the page frame, the two fields and the twelve `textTheme`
/// reads need none of them.
///
/// **The defect §2.1 was written about was still on this screen.** That
/// section's own worked example reads *"**Clear this sale** is `destructive`,
/// **Save sale** is `primary`. Today the destructive action is the more
/// prominent of the two."* It was: *Clear this sale* was an `OutlinedButton`
/// with the theme's mint outline and *Save sale* was a `FilledButton`, so the
/// two read as equals with the destructive one first. They are now
/// [AppButtonTier.destructive] and [AppButtonTier.primary].
///
/// **What is deliberately still Material, and why each one is not guessed at.**
/// §5.1 gives all five a row and §5.2 specifies none of them:
///
/// - `QuantityStepper` (§5.1 priority **1**) - the minus and the bin are still
///   `IconButton`s. "minus + delete, no plus" is §5.1's own description of the
///   defect, and the component that fixes it decides what a stepper *is*.
/// - `FilterChipBar` - the category and tender choosers are still
///   `ChoiceChip`s. §4.3 gives `FilterChips` a row and §2.3 now guards the chip
///   radius alone, which is an open decision rather than a settled value.
/// - `ConfirmDialog` - the clear-sale confirmation is still an `AlertDialog`
///   with `AppButton`s in it. §7 asks for a filled destructive confirm and §2.1
///   has no filled destructive tier; see `PLAN.md`.
/// - `AppSheet` - the compact cart is still `showModalBottomSheet`. It is what
///   blocks the *responsive* half of this step, not this one.
/// - `RollingNumber` - the total is a `StatTile` that redraws, not one that
///   rolls. §6.2's row for it is motion, and motion is step 10's.
///
/// **The band boundary moved and the numbers behind it are §4.1's and §4.2's.**
/// The split used to be `medium` (768), which was this app's own inherited
/// figure; §4.3 gives `Sale` *"products + cart sheet"* at `compact` **and**
/// `medium` and two panes only at `expanded`, so a 900-wide tablet is a sheet
/// now. The cart pane is [AppLayout.salePane] - 420, declared in step 6a and
/// read by nothing until this file.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tenancy/tenant_catalog.dart';
import '../ui/buttons.dart';
import '../ui/fields.dart';
import '../ui/press.dart';
import '../ui/records.dart';
import '../ui/scaffold.dart';
import '../ui/stats.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import 'checkout_catalog_cache.dart';
import 'checkout_draft.dart';
import 'checkout_refusal.dart';
import 'checkout_sale.dart';
import 'checkout_tender.dart';

/// The largest number of product buttons the till draws at once.
///
/// `CheckoutCatalogCacheRefresher` caches up to two thousand products, and the
/// products are laid out in a `Wrap`, which builds every child eagerly even
/// inside a `ListView`. This bounds the drawing only: a product past the cap is
/// still reachable by search and still reachable by its exact code.
const int maximumRenderedCheckoutProducts = 60;

/// The widest a product tile is allowed to grow before the grid takes another
/// column, and how tall one is.
///
/// **Named rather than moved into the token layer, and that is the honest
/// place for them.** `claude.md` hard rule 2 forbids a magic number in a
/// widget; it does not turn every measurement into a token, and `design.md`
/// states no product-tile geometry in §2.3 or anywhere else. Inventing
/// `size.productTile` would be inventing a token, which the same file forbids
/// one rule earlier. Both figures are what this grid already drew.
const double _productTileExtent = 230;
const double _productTileHeight = 116;

/// The side of the square a product's picture, or its stand-in, is drawn in.
/// Named for the same reason as the two figures above, and unchanged at 52.
const double _thumbnailSize = 52;

/// A till that can price a sale and cannot save one.
///
/// §2.1's `info` is *"offline, read-only, informational"*, and a panel with no
/// [CheckoutDraftSink] is exactly read-only. It is deliberately **not** a
/// refusal: nothing was attempted, so nothing failed.
const AppNotice _unavailable = AppNotice.offline(
  'Saving a sale is unavailable on this device.',
);

/// Guarded point-of-sale route for the selected tenant session.
///
/// **The one screen §4.2 gives `full` to, and until now nothing read that
/// row.** `AppContentWidth.full` has been declared since step 6a and answers
/// `null` from `AppLayout.maxWidthOf`, because the sale is the only page in the
/// app that is not centred inside a maximum: §4.2's third row is *"products
/// flex, cart pane fixed 420"*, and a till that gave back the edges of a wide
/// screen would be spending the space a cashier is aiming at.
final class TenantCheckoutScreen extends StatelessWidget {
  const TenantCheckoutScreen({super.key, required this.cache, this.drafts});

  final CheckoutCatalogSource cache;

  /// Absent until the composition root supplies it; the cart then prices a
  /// sale but cannot save one, exactly as the returns route behaves.
  final CheckoutDraftSink? drafts;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'New sale',
    contentWidth: AppContentWidth.full,
    body: TenantCheckoutPanel(cache: cache, drafts: drafts),
  );
}

/// Builds one offline sale from the cached catalog and saves it to the outbox.
///
/// The panel ends at [CheckoutDraftSink.saveDraft]. Submission,
/// confirmation, and recovery are already owned by the sync and recovery
/// workers and run on their own, so there is deliberately no submit, retry, or
/// cancel control here - the same rule the read-only evidence panel follows.
///
/// Four scope decisions are recorded here because each is easy to reverse by
/// accident:
///
/// - **The discount is pinned to zero and has no control.**
///   `CheckoutDraftRequest.discountMinor` exists and is validated, so leaving a
///   field wired to it would hand every cashier an unaudited way to reduce a
///   sale. No role check authorizes a till discount today, so the cart does not
///   offer one. Adding it later is additive; adding it now would be a cash
///   shrinkage path nothing reviews.
/// - **There is no default tender.** A pre-selected payment method would be
///   indistinguishable from an observed one, and the whole point of the field
///   is that a person looked at how the customer paid.
/// - **The cached stock figure is shown and never blocks a sale.** Firestore
///   Rules deliberately permit signed stock, the stock surface already states
///   that a sale is never blocked by a stock count, and this device holds a
///   figure that was true at the last sync rather than now. Refusing to sell
///   below zero here would therefore guarantee nothing on the server while
///   reliably blocking a legitimate sale whenever the cached figure is merely
///   stale - a cashier told "out of stock" by a device that cannot know is
///   worse than one told what the device last saw. So the till states the
///   figure, states when it was read, warns when a line exceeds it, and sells.
/// - **Search and filtering read only the cached snapshot.** The till issues no
///   Firestore read of its own; a sale must be buildable with no network at
///   all, which is the entire reason the offline catalog exists.
/// - **Submitting the search adds a product by its code, and refuses to
///   guess.** A retail barcode scanner presents itself as a keyboard, so a scan
///   arrives here as typed text followed by a submit. Nothing is added unless
///   the query resolves to exactly one product, because a till that picks one
///   of two candidates sells the wrong thing silently. Nothing in Firestore
///   Rules or in [HiveCheckoutCatalogCache] makes a SKU unique - only the
///   product ID is checked for duplicates - so two products really can carry
///   one code, and that case is refused rather than resolved.
/// - **Only a bounded number of products is drawn.** A `Wrap` builds every
///   child eagerly even inside a `ListView`, and the cache admits up to two
///   thousand products, so the list is capped at
///   [maximumRenderedCheckoutProducts] and says how many matched. This changes
///   what is drawn and never what can be sold: a capped-out product is still
///   reachable by search and still reachable by its code.
final class TenantCheckoutPanel extends StatefulWidget {
  const TenantCheckoutPanel({super.key, required this.cache, this.drafts});

  final CheckoutCatalogSource cache;
  final CheckoutDraftSink? drafts;

  /// Whether [screenWidth] gets the two-pane till.
  ///
  /// **§4.3's `Sale` row, and the boundary moved because of it.** That row
  /// reads *products + cart sheet* at `compact` **and** at `medium`, and *two
  /// panes* only at `expanded` - so the answer is §4.1's `expanded` floor and
  /// not the `medium` one this file used to ask for. The figure it used to read
  /// was 768, which was the previous app's own split and predates §4.3 saying
  /// anything about a till; a 900-wide tablet was getting two panes that §4.3
  /// gives a sheet.
  ///
  /// **The screen's width, not the panel's box**, which is the rule §4.1 states
  /// and `PageHeader.showsDisplayTitle` argues for at length: a band is a
  /// property of the surface a person is looking at, and resolving it inside a
  /// padded page invents a fourth boundary by arithmetic. This used to be a
  /// `LayoutBuilder` over the panel's own constraints, which were the window's
  /// only because nothing sat between them.
  ///
  /// Exposed so a test can ask the same question the widget asks, rather than
  /// asserting a pixel width and hoping the two agree - the same reason
  /// `PageHeader` exposes its two.
  static bool showsTwoPanes(double screenWidth) =>
      AppLayout.contract.isAtLeast(screenWidth, AppBreakpoint.expanded);

  @override
  State<TenantCheckoutPanel> createState() => _TenantCheckoutPanelState();
}

final class _TenantCheckoutPanelState extends State<TenantCheckoutPanel> {
  /// One loader per session, so a tenant switch reloads rather than reusing
  /// another business's catalog.
  String? _loaderKey;
  TenantGuardedLoader<CheckoutCatalogSnapshot>? _loader;

  static String _sessionKey(TenantSession session) =>
      '${session.uid}:${session.tenantId}:${session.epoch}';

  TenantGuardedLoader<CheckoutCatalogSnapshot> _loaderFor(
    TenantSession session,
  ) {
    final key = _sessionKey(session);
    if (key == _loaderKey && _loader != null) return _loader!;
    _loaderKey = key;
    return _loader = (session) async {
      final snapshot = await widget.cache.read(
        uid: session.uid,
        tenantId: session.tenantId,
      );
      // A missing or foreign snapshot is refused rather than priced against.
      if (snapshot == null || !snapshot.ownsSession(session)) {
        throw const CheckoutDraftException('catalog_cache_unavailable');
      }
      return snapshot;
    };
  }

  @override
  Widget build(BuildContext context) =>
      TenantRouteGuard<CheckoutCatalogSnapshot>(
        load: (session) => _loaderFor(session)(session),
        // Deliberately not the guard's default spinner: a till shows what it is
        // waiting for, and an indeterminate animation also makes the screen
        // impossible to settle in a widget test.
        loading: const Center(
          key: ValueKey('checkout-loading'),
          child: Text('Reading the product list on this device...'),
        ),
        denied: const Center(
          key: ValueKey('checkout-denied'),
          child: Text('Selling is unavailable for this business.'),
        ),
        failure: (context, error) => Center(
          child: Text(
            key: const ValueKey('checkout-failure'),
            CheckoutRefusal.forError(error).message,
          ),
        ),
        // Keyed by session: a business switch discards the cart, the search
        // text, the chosen tender, and the previous receipt rather than
        // carrying any of them into another business.
        builder: (context, session, snapshot) => _CartEditor(
          key: ValueKey('checkout-editor-${_sessionKey(session)}'),
          snapshot: snapshot,
          drafts: widget.drafts,
        ),
      );
}

/// The editable cart for one loaded catalog snapshot and one live session.
final class _CartEditor extends StatefulWidget {
  const _CartEditor({super.key, required this.snapshot, required this.drafts});

  final CheckoutCatalogSnapshot snapshot;
  final CheckoutDraftSink? drafts;

  @override
  State<_CartEditor> createState() => _CartEditorState();
}

final class _CartEditorState extends State<_CartEditor> {
  /// Requested quantity per product, in insertion order.
  final Map<String, int> _quantities = <String, int>{};

  /// Lines whose typed quantity is not a usable whole number. The line keeps
  /// its last usable quantity, so a half-typed number never becomes the sale.
  final Set<String> _unusableQuantities = <String>{};

  final TextEditingController _search = TextEditingController();

  /// The selected category, or null for every category. Never set while
  /// [_uncachedCategoriesOnly] is true.
  String? _categoryId;

  /// Whether only products naming a category this device does not hold are
  /// listed. Tracked separately from [_categoryId] rather than as a sentinel
  /// ID, because a real category could legitimately be named anything.
  bool _uncachedCategoriesOnly = false;

  CheckoutTender? _tender;
  bool _saving = false;
  CheckoutRefusal? _refusal;

  /// The last durable save. It deliberately survives every later cart edit and
  /// is cleared only by the next save attempt or by the cashier closing it: a
  /// receipt number describes a finished sale, not the cart on screen, and a
  /// cashier who saves and immediately serves the next customer must still be
  /// able to read and copy it.
  CheckoutSavedDraft? _saved;
  bool _receiptCopied = false;

  /// Why the last submitted search added nothing. Cleared by the next edit.
  ///
  /// **An [AppNotice] rather than a `String?`, which is the whole argument that
  /// component makes.** Every one of the three sentences below is a refusal -
  /// nothing was added - and holding the outcome beside the words is what stops
  /// a later branch that *did* add something being drawn in the same red block.
  AppNotice? _codeNotice;

  /// Bumped on every state change, so the compact layout's cart sheet can
  /// follow along.
  ///
  /// The sheet is pushed as its own route and therefore does not rebuild when
  /// this element does. Rather than route every mutation through a second
  /// callback - and risk one of them being missed - [setState] is overridden
  /// below to bump this, which is the one place every change already passes
  /// through.
  final ValueNotifier<int> _revision = ValueNotifier<int>(0);

  CheckoutCatalogSnapshot get _snapshot => widget.snapshot;

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _revision.value++;
  }

  @override
  void dispose() {
    _search.dispose();
    _revision.dispose();
    super.dispose();
  }

  // --- Catalog filtering -----------------------------------------------

  /// Whether any cached product names a category this device does not hold.
  ///
  /// Such a product must stay reachable, otherwise filtering would silently
  /// hide something the till can legitimately sell.
  bool get _hasUncachedCategories => _snapshot.products.any(
    (product) => _snapshot.categoryById(product.categoryId) == null,
  );

  List<TenantProduct> get _visibleProducts {
    final query = _search.text.trim().toLowerCase();
    return <TenantProduct>[
      for (final product in _snapshot.products)
        if (_matchesCategory(product) && _matchesQuery(product, query)) product,
    ];
  }

  bool _matchesCategory(TenantProduct product) {
    if (_uncachedCategoriesOnly) {
      return _snapshot.categoryById(product.categoryId) == null;
    }
    final selected = _categoryId;
    return selected == null || product.categoryId == selected;
  }

  bool _matchesQuery(TenantProduct product, String query) =>
      query.isEmpty ||
      product.name.toLowerCase().contains(query) ||
      product.sku.toLowerCase().contains(query);

  void _selectCategory({String? categoryId, bool uncachedOnly = false}) {
    setState(() {
      _categoryId = uncachedOnly ? null : categoryId;
      _uncachedCategoriesOnly = uncachedOnly;
      _codeNotice = null;
    });
  }

  /// Adds the one product the submitted search names, or explains why it did
  /// not. A barcode scanner arrives here: it types the code and submits.
  ///
  /// The code lookup deliberately spans the whole cached catalog rather than
  /// the filtered view. A scanned code is unambiguous evidence about which
  /// product is in the cashier's hand, and refusing it because a category chip
  /// happens to be set would make the scanner useless the moment anyone
  /// filtered. The category filter is therefore left exactly as it was.
  void _submitSearch() {
    final query = _search.text.trim();
    if (query.isEmpty) return;

    final byCode = <TenantProduct>[
      for (final product in _snapshot.products)
        if (product.sku.toLowerCase() == query.toLowerCase()) product,
    ];
    // Nothing makes a SKU unique - not Firestore Rules, not the cache, which
    // only refuses duplicate product IDs - so a shared code is a real state and
    // is refused rather than resolved by picking the first one.
    if (byCode.length > 1) {
      setState(() {
        _codeNotice = const AppNotice.refused(
          'More than one product on this device carries that code, so '
          'nothing was added. Pick the right one from the list.',
        );
      });
      return;
    }
    if (byCode.length == 1) {
      _addFromSearch(byCode.single);
      return;
    }

    // No code matched, so fall back to the list the cashier is looking at.
    // One visible product is as unambiguous as a code; more than one is not.
    final visible = _visibleProducts;
    if (visible.length == 1) {
      _addFromSearch(visible.single);
      return;
    }
    setState(() {
      _codeNotice = visible.isEmpty
          ? const AppNotice.refused(
              'Nothing on this device matches that. Check the code and try '
              'again.',
            )
          : const AppNotice.refused(
              'That matches more than one product, so nothing was added. Pick '
              'one from the list, or enter its exact code.',
            );
    });
  }

  /// Adds [product] and clears the search so the next scan starts clean.
  void _addFromSearch(TenantProduct product) {
    _add(product);
    if (!mounted) return;
    setState(() {
      _search.clear();
      _codeNotice = null;
    });
  }

  /// Empties the cart without saving anything.
  ///
  /// Nothing is persisted until [_save], so this destroys no record - only the
  /// lines a cashier rang up for a customer who left. The saved receipt is
  /// deliberately untouched: it describes a different, finished sale.
  void _clearSale() {
    setState(() {
      _quantities.clear();
      _unusableQuantities.clear();
      _tender = null;
      _codeNotice = null;
      _clearRefusal();
    });
  }

  // --- Cart editing -----------------------------------------------------

  void _add(TenantProduct product) {
    if (!_quantities.containsKey(product.id) &&
        _quantities.length >= maximumCheckoutSaleLines) {
      setState(() {
        _codeNotice = null;
        _refusal = CheckoutRefusal.forCode('invalid_line_count');
      });
      return;
    }
    setState(() {
      final next = (_quantities[product.id] ?? 0) + 1;
      _quantities[product.id] = next > maximumCheckoutLineQuantity
          ? maximumCheckoutLineQuantity
          : next;
      _unusableQuantities.remove(product.id);
      _clearRefusal();
    });
  }

  void _decrement(String productId) {
    setState(() {
      final next = (_quantities[productId] ?? 0) - 1;
      if (next < 1) {
        _quantities.remove(productId);
      } else {
        _quantities[productId] = next;
      }
      _unusableQuantities.remove(productId);
      _clearRefusal();
    });
  }

  void _remove(String productId) {
    setState(() {
      _quantities.remove(productId);
      _unusableQuantities.remove(productId);
      _clearRefusal();
    });
  }

  /// Applies a directly typed quantity for a line already in the cart.
  void _setQuantity(String productId, String raw) {
    if (!_quantities.containsKey(productId)) return;
    final parsed = int.tryParse(raw.trim());
    setState(() {
      _clearRefusal();
      if (parsed == null ||
          parsed < 1 ||
          parsed > maximumCheckoutLineQuantity) {
        _unusableQuantities.add(productId);
        return;
      }
      _unusableQuantities.remove(productId);
      _quantities[productId] = parsed;
    });
  }

  void _chooseTender(CheckoutTender tender) {
    setState(() {
      _tender = tender;
      _clearRefusal();
    });
  }

  /// Clears the previous attempt's refusal and code notice so neither can sit
  /// beside a cart the cashier has since changed. The saved receipt is
  /// deliberately not cleared here; it describes a sale that is already
  /// finished.
  void _clearRefusal() {
    _refusal = null;
    _codeNotice = null;
  }

  void _dismissReceipt() {
    setState(() {
      _saved = null;
      _receiptCopied = false;
    });
  }

  Future<void> _copyReceipt(String receiptNumber) async {
    await Clipboard.setData(ClipboardData(text: receiptNumber));
    if (!mounted) return;
    setState(() => _receiptCopied = true);
  }

  // --- Pricing ----------------------------------------------------------

  /// The cart total, or null when a selected price cannot be recorded exactly.
  ///
  /// The returned value may exceed [maximumCheckoutMinorAmount]; that is a
  /// separate refusal, reported by [_blocker] rather than hidden here.
  int? get _totalMinor {
    var total = 0;
    for (final entry in _quantities.entries) {
      final minor = _unitPriceMinor(entry.key);
      if (minor == null) return null;
      total += minor * entry.value;
    }
    return total;
  }

  int? _unitPriceMinor(String productId) {
    final product = _snapshot.productById(productId);
    return product == null
        ? null
        : checkoutMinorUnitsFromMajor(product.price);
  }

  /// Whether any line total, or the cart total, is beyond what a sale records.
  ///
  /// Direct quantity entry makes this reachable at the till: the frozen payload
  /// contract refuses it as `draft_contract_violation`, which tells a cashier to
  /// ask for help when the real answer is to type a smaller number.
  bool _exceedsRecordableAmount(int? total) {
    if (total == null) return false;
    if (total > maximumCheckoutMinorAmount) return true;
    for (final entry in _quantities.entries) {
      final minor = _unitPriceMinor(entry.key);
      if (minor != null && minor * entry.value > maximumCheckoutMinorAmount) {
        return true;
      }
    }
    return false;
  }

  /// Why saving is not offered yet, or null when the sale may be saved.
  ///
  /// The cart states the reason rather than presenting a dead button, because
  /// a disabled control with no explanation is how a till stalls.
  String? _blocker(int? total) {
    if (_quantities.isEmpty) return 'Add at least one item to save this sale.';
    if (_unusableQuantities.isNotEmpty) {
      return 'Enter a whole quantity between 1 and '
          '${_grouped(maximumCheckoutLineQuantity)} for every item.';
    }
    if (total == null) {
      return 'Remove the item whose price cannot be recorded exactly.';
    }
    if (_exceedsRecordableAmount(total)) {
      return 'This sale is larger than this till can record. Reduce a '
          'quantity.';
    }
    if (_tender == null) return 'Choose how the customer paid.';
    return null;
  }

  // --- Saving -----------------------------------------------------------

  Future<void> _save() async {
    final drafts = widget.drafts;
    final tender = _tender;
    if (drafts == null || tender == null || _saving) return;

    setState(() {
      _saving = true;
      _clearRefusal();
      // The previous receipt goes now rather than when the answer arrives, so
      // an older number is never on screen beside a save in flight.
      _saved = null;
      _receiptCopied = false;
    });

    CheckoutSavedDraft? saved;
    CheckoutRefusal? refusal;
    try {
      saved = await drafts.saveDraft(
        CheckoutDraftRequest(
          tender: tender,
          lines: <CheckoutDraftLineRequest>[
            for (final entry in _quantities.entries)
              CheckoutDraftLineRequest(
                productId: entry.key,
                quantity: entry.value,
              ),
          ],
        ),
      );
    } catch (error) {
      refusal = CheckoutRefusal.forError(error);
    }

    // The await above can outlive this route: a tenant switch or a pop while
    // the draft was being written must not write state into a dead element.
    if (!mounted) return;
    setState(() {
      _saving = false;
      _refusal = refusal;
      _saved = saved;
      // The cart is cleared only when the draft is durable, so a refused sale
      // keeps every line the cashier already rang up.
      if (saved != null) {
        _quantities.clear();
        _unusableQuantities.clear();
        _tender = null;
        // The till returns to its neutral state for the next customer rather
        // than leaving them a catalog narrowed by somebody else's search.
        _search.clear();
        _categoryId = null;
        _uncachedCategoriesOnly = false;
      }
    });
  }

  // --- Rendering --------------------------------------------------------

  /// How many units the cart holds, for the compact layout's badge.
  int get _itemCount =>
      _quantities.values.fold<int>(0, (sum, quantity) => sum + quantity);

  @override
  Widget build(BuildContext context) {
    final total = _totalMinor;
    final currency = _snapshot.configuration.currency;
    return KeyedSubtree(
      key: const ValueKey('checkout-cart'),
      child: TenantCheckoutPanel.showsTwoPanes(MediaQuery.sizeOf(context).width)
          ? _wideLayout(context, currency, total)
          : _compactLayout(context, currency, total),
    );
  }

  /// Products beside a cart that is always on screen.
  ///
  /// **§4.2's third row, in its own words: "products flex, cart pane fixed
  /// 420".** The proportion used to be a 3:2 flex, which is the previous app's
  /// and which gave the cart 560 pixels of a 1400 window and 200 of a 500 one.
  /// [AppLayout.salePane] is the figure §4.2 states, and it is the last of the
  /// three content widths that had no reader.
  Widget _wideLayout(BuildContext context, String currency, int? total) {
    final tokens = AppTokens.componentOf(context);
    return Row(
      key: const ValueKey('checkout-wide'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _productsPane(context, currency)),
        // §2.1's hairline, which is what separates two regions everywhere else
        // in this app. `VerticalDivider` paints `dividerColor`, and the theme's
        // is the same role - this reads it by name rather than by inheritance.
        Container(width: 1, color: tokens.colors.surface.borderSubtle),
        SizedBox(
          width: tokens.layout.salePane,
          child: _cartPane(context, currency, total),
        ),
      ],
    );
  }

  /// Products at full width, with the cart one tap away.
  ///
  /// The cart is a sheet rather than a section further down the same scroll,
  /// because the two are used alternately: every item added is a trip to the
  /// cart and back, and on a phone that was a scroll past the whole catalog in
  /// each direction. The bar states the total without the sheet being open, so
  /// the number a customer is waiting for is never behind a tap.
  Widget _compactLayout(BuildContext context, String currency, int? total) =>
      Column(
        key: const ValueKey('checkout-compact'),
        children: [
          Expanded(child: _productsPane(context, currency)),
          _CartBar(
            currency: currency,
            total: total,
            itemCount: _itemCount,
            onOpen: () => _openCartSheet(context, currency),
          ),
        ],
      );

  Future<void> _openCartSheet(BuildContext context, String currency) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => ValueListenableBuilder<int>(
        valueListenable: _revision,
        // The sheet is a route of its own, so this element does not rebuild
        // when the panel behind it does. [_revision] is what keeps the two in
        // step - without it, adding an item from inside the sheet would leave
        // the sheet showing the cart as it was when it opened.
        builder: (context, _, _) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          builder: (context, controller) => _cartPane(
            context,
            currency,
            _totalMinor,
            controller: controller,
          ),
        ),
      ),
    );
  }

  /// Everything a cashier needs once the items are chosen.
  Widget _cartPane(
    BuildContext context,
    String currency,
    int? total, {
    ScrollController? controller,
  }) {
    final tokens = AppTokens.componentOf(context);
    return ListView(
      key: const ValueKey('checkout-cart-pane'),
      controller: controller,
      padding: EdgeInsets.all(AppScaffold.horizontalInset(tokens.spacing)),
      children: [
        ..._receiptSection(context, tokens),
        ..._saleSection(context, tokens, currency, total),
        ..._tenderSection(context, tokens),
        ..._saveSection(context, tokens, total),
        SizedBox(height: tokens.spacing.s16),
        // **§7's "Long copy" pattern, and this is policy rather than state.**
        // "Anything over two lines that explains *policy* rather than *the
        // current state* goes in a `Disclosure`" - and what a saved sale does
        // afterwards is the policy this panel's own class comment spends four
        // paragraphs on. It was permanent body text at the foot of every cart.
        const Disclosure(
          key: ValueKey('checkout-submission-disclosure'),
          // 30 characters, inside `Disclosure.summaryCharacterBudget`.
          summary: 'What happens to a saved sale',
          child: Text(
            key: ValueKey('checkout-submission-policy'),
            'A saved sale is submitted and confirmed automatically. It cannot '
            'be edited, retried, or deleted here.',
          ),
        ),
      ],
    );
  }

  /// The last durable save, stated until the cashier closes it.
  ///
  /// [CheckoutSavedDraft.receiptNumber] is nullable, and the sale is saved
  /// either way, so the absent case is reported rather than rendered as
  /// silence: a cashier who saved a sale and was told nothing would ring it up
  /// again.
  List<Widget> _receiptSection(BuildContext context, AppTokens tokens) {
    final saved = _saved;
    if (saved == null) return const <Widget>[];
    final receipt = saved.receiptNumber;
    // **The eighth notice surface, and the one branch that is not a
    // confirmation.** A sale with a receipt number is `AppNotice.confirmed` -
    // §2.1's `ok` is "reconciled, **confirmed**, in stock". A sale saved
    // durably whose receipt number could not be stated is `AppNotice.unknown`:
    // nothing failed, the sale syncs either way, and what is awaited is the
    // number. Both were the same black paragraph in the same position, which is
    // exactly the failure `AppNotice` was written for - and here the two differ
    // by whether a cashier may read a number out to a customer.
    final notice = receipt == null
        ? const AppNotice.unknown(
            'Saved on this device, but it could not state a receipt number '
            'for this sale. The sale still syncs on its own. Ask for help '
            'before giving the customer a receipt number.',
          )
        : AppNotice.confirmed(
            'Saved on this device as $receipt. It syncs on its own; there is '
            'nothing else to press. This stays here until you close it, so '
            'the number can be written down.',
          );
    return <Widget>[
      Callout(
        key: const ValueKey('checkout-saved'),
        status: notice.status,
        message: notice.message,
        action: Wrap(
          spacing: tokens.spacing.s8,
          runSpacing: tokens.spacing.s8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (receipt != null)
              AppButton(
                key: const ValueKey('checkout-copy-receipt'),
                label: 'Copy receipt number',
                onPressed: () => _copyReceipt(receipt),
              ),
            AppButton(
              key: const ValueKey('checkout-dismiss-receipt'),
              label: 'Close',
              tier: AppButtonTier.tertiary,
              onPressed: _dismissReceipt,
            ),
            if (_receiptCopied)
              Text(
                key: const ValueKey('checkout-receipt-copied'),
                'Receipt number copied.',
                style: tokens.typography.caption.copyWith(
                  color: tokens.colors.text.tertiary,
                ),
              ),
          ],
        ),
      ),
      SizedBox(height: tokens.spacing.s20),
    ];
  }

  /// The catalog: what is sellable, and how it is found.
  ///
  /// The grid replaced a `Wrap` of buttons whose widths followed their labels,
  /// so a long product name made its own tile wider than its neighbours and
  /// nothing lined up. A cashier scans this by position, so the columns are
  /// fixed and the tiles are not.
  Widget _productsPane(BuildContext context, String currency) {
    final tokens = AppTokens.componentOf(context);
    // §2.2's `caption` row - "timestamps, attribution" - in `text.tertiary`,
    // which §2.1 names the floor for anything a person is expected to read.
    // This used to be `bodySmall` in `onSurfaceVariant`, which is Material's
    // pair for the same intent and is not one of §2.2's twelve roles.
    final quiet = tokens.typography.caption.copyWith(
      color: tokens.colors.text.tertiary,
    );
    final body = tokens.density
        .body(tokens.typography)
        .copyWith(color: tokens.colors.text.secondary);
    final matches = _visibleProducts;
    // A `Wrap` builds every child eagerly even inside a `ListView`, and the
    // cache admits two thousand products. Only what is drawn is bounded; every
    // match stays sellable by narrowing the search or entering its code.
    final visible = matches.length > maximumRenderedCheckoutProducts
        ? matches.sublist(0, maximumRenderedCheckoutProducts)
        : matches;
    return ListView(
      padding: EdgeInsets.all(AppScaffold.horizontalInset(tokens.spacing)),
      children: <Widget>[
      // **A section head is `title.md` here, and §2.2 says `title.lg`.** Ten
      // migrated screens read the row the other way - `Reconciliation runs`,
      // `Paid by` and eight more are `title.md` - and the reason holds up: at
      // §4.1's `compact` band `PageHeader` gives the *screen* title `title.lg`,
      // so a section head at the same role puts two titles of equal weight on
      // a phone, which is what §7's "title appears once" is about. The tree's
      // convention wins over a fresh reading of the row; the contradiction is
      // an open decision in `PLAN.md` rather than something a sweep settles.
      // It was `titleSmall`, which is Material's scale and not one of §2.2's.
      Text(
        'Products',
        style: tokens.typography.titleMedium.copyWith(
          color: tokens.colors.text.primary,
        ),
      ),
      SizedBox(height: tokens.spacing.s4),
      // Quietened rather than deleted. It is true, and a cashier pricing from
      // a stale device needs it - but it is standing context, not the thing
      // being looked at, so it no longer competes with the products for
      // attention the way full-weight body text did.
      Text(
        key: const ValueKey('checkout-catalog-freshness'),
        'Prices and stock come from this device, last synced '
        '${_instant(_snapshot.refreshedAt)}. A sale is never blocked by a '
        'stock count.',
        style: quiet,
      ),
      if (!_snapshot.complete)
        Text(
          key: const ValueKey('checkout-catalog-partial'),
          'This device holds only part of the product list for this business, '
          'so a product may be missing from it.',
          style: quiet,
        ),
      SizedBox(height: tokens.spacing.s8),
      // §5.2's field, and the last two call sites of §11 step 3's sweep. The
      // leading glyph is the "optional in the strong sense" case that section
      // describes: a magnifier says *this one is searched*, which the label
      // cannot say faster, and the till is where a cashier is not reading.
      AppTextField(
        key: const ValueKey('checkout-search'),
        label: 'Search by name or code',
        leading: Icons.search,
        controller: _search,
        textInputAction: TextInputAction.done,
        onChanged: (_) => setState(() => _codeNotice = null),
        onSubmitted: (_) => _submitSearch(),
        helper: 'Scan or enter a code and press enter to add it.',
      ),
      // **The eighth notice surface `AppNotice` has been waiting for.** All
      // three sentences `_submitSearch` writes here are the same outcome -
      // nothing was added - so this is one `refused`, not a status picked per
      // branch. It was a bare `Text`, in the position a confirmation would
      // also have taken.
      if (_codeNotice case final notice?) ...[
        SizedBox(height: tokens.spacing.s8),
        Callout(
          key: const ValueKey('checkout-code-notice'),
          status: notice.status,
          message: notice.message,
        ),
      ],
      if (_snapshot.categories.isNotEmpty || _hasUncachedCategories) ...[
        SizedBox(height: tokens.spacing.s8),
        Wrap(
          spacing: tokens.spacing.s8,
          runSpacing: tokens.spacing.s8,
          children: [
            ChoiceChip(
              key: const ValueKey('checkout-category-all'),
              label: const Text('All'),
              selected: _categoryId == null && !_uncachedCategoriesOnly,
              onSelected: (_) => _selectCategory(),
            ),
            for (final category in _snapshot.categories)
              ChoiceChip(
                key: ValueKey('checkout-category-${category.id}'),
                label: Text(category.name),
                selected: _categoryId == category.id,
                onSelected: (_) => _selectCategory(categoryId: category.id),
              ),
            if (_hasUncachedCategories)
              ChoiceChip(
                key: const ValueKey('checkout-category-other'),
                label: const Text('Other'),
                selected: _uncachedCategoriesOnly,
                onSelected: (_) => _selectCategory(uncachedOnly: true),
              ),
          ],
        ),
      ],
      SizedBox(height: tokens.spacing.s8),
      // **Two full-page-ish states that stay prose, deliberately.** §5.1 gives
      // `EmptyState` a row and §5.2 specifies it nowhere, and step 9 already
      // took this decision once for screen 08: giving one of the three missing
      // full-page states a bespoke treatment here is how a fourth
      // implementation of an empty state gets written. They take a §2.2 role
      // and no shape of their own.
      if (_snapshot.products.isEmpty)
        Text(
          key: const ValueKey('checkout-catalog-empty'),
          'This device holds no products for this business yet. Connect to '
          'sync them before selling.',
          style: body,
        )
      else if (visible.isEmpty)
        Text(
          key: const ValueKey('checkout-catalog-no-matches'),
          'No product on this device matches that search. Clear it to see the '
          'whole list.',
          style: body,
        )
      else ...[
        if (matches.length > visible.length) ...[
          Text(
            key: const ValueKey('checkout-catalog-truncated'),
            'Showing ${visible.length} of ${matches.length} matching '
            'products. Narrow the search, or enter a code to add one '
            'directly.',
            style: quiet,
          ),
          SizedBox(height: tokens.spacing.s8),
        ],
        GridView.builder(
          // The cap above is what makes eager building safe, so the grid does
          // not need to be lazy and must not scroll itself - it sits inside
          // the pane's own scroll.
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            // An extent rather than a column count, so one grid serves a phone
            // and a till screen without a second breakpoint deciding columns.
            //
            // **The extent and the height are this component's own and are not
            // §2.3's to supply.** A tile is not a spacing, a radius or a size
            // token - `design.md` states no product-tile geometry anywhere -
            // and 230 x 116 is what this grid already used. The two *gaps* are
            // §2.3's, and were 8 by coincidence rather than by reference.
            maxCrossAxisExtent: _productTileExtent,
            mainAxisExtent: _productTileHeight,
            crossAxisSpacing: tokens.spacing.s8,
            mainAxisSpacing: tokens.spacing.s8,
          ),
          itemCount: visible.length,
          itemBuilder: (context, index) {
            final product = visible[index];
            return _ProductTile(
              key: ValueKey('checkout-product-${product.id}'),
              product: product,
              detail: _productDetail(product, currency),
              onTap: () => _add(product),
            );
          },
        ),
      ],
      SizedBox(height: tokens.spacing.s20),
      ],
    );
  }

  String _productDetail(TenantProduct product, String currency) {
    final minor = checkoutMinorUnitsFromMajor(product.price);
    final price = minor == null
        ? 'Price unusable'
        : '$currency ${_money(minor)}';
    return '$price, ${product.quantity} in stock';
  }

  List<Widget> _saleSection(
    BuildContext context,
    AppTokens tokens,
    String currency,
    int? total,
  ) {
    return <Widget>[
      Text(
        'This sale',
        style: tokens.typography.titleMedium.copyWith(
          color: tokens.colors.text.primary,
        ),
      ),
      SizedBox(height: tokens.spacing.s4),
      if (_quantities.isEmpty)
        Text(
          key: const ValueKey('checkout-cart-empty'),
          'No items yet. Add a product to start the sale.',
          style: tokens.density
              .body(tokens.typography)
              .copyWith(color: tokens.colors.text.secondary),
        )
      else
        for (final entry in _quantities.entries)
          _CartLine(
            key: ValueKey('checkout-line-${entry.key}'),
            product: _snapshot.productById(entry.key),
            productId: entry.key,
            quantity: entry.value,
            quantityUnusable: _unusableQuantities.contains(entry.key),
            currency: currency,
            onQuantityChanged: (raw) => _setQuantity(entry.key, raw),
            onDecrement: () => _decrement(entry.key),
            onRemove: () => _remove(entry.key),
          ),
      SizedBox(height: tokens.spacing.s12),
      // **§2.2's "the one figure a stat tile exists for", and on this screen it
      // is not a figurative claim.** The total is the number a customer is
      // waiting to hear, and it was `titleMedium` inside the sentence "Total:
      // KES 248.00" - proportional figures in a label, which is the exact
      // complaint §2.2 makes about the daily summary. It is `numeric.hero`,
      // tabular, with the word beside it rather than in front of it.
      //
      // **The untotalled branch is not a tile**, because there is no figure:
      // §2.1's `problem` says "difference found, **unreadable**", and a price
      // this till cannot record exactly is a record it cannot read.
      if (total == null)
        Callout(
          key: const ValueKey('checkout-total-unavailable'),
          status: AppStatus.problem,
          message:
              'This sale cannot be totalled because one item has a price the '
              'till cannot record exactly.',
        )
      else
        StatTile(
          label: 'Total',
          value: '$currency ${_money(total)}',
          valueKey: const ValueKey('checkout-total'),
        ),
      // Offered only when there is something to abandon, and never for a saved
      // sale: nothing here is persisted, so this destroys no record.
      //
      // **§2.1's own worked example, closed.** "Clear this sale is
      // `destructive`, Save sale is `primary`. Today the destructive action is
      // the more prominent of the two." It was an `OutlinedButton` wearing the
      // theme's mint outline, directly above a `FilledButton`; it is
      // §2.1's destructive tier now - red label, red border, transparent
      // container - and the primary one is the save.
      if (_quantities.isNotEmpty) ...[
        SizedBox(height: tokens.spacing.s8),
        AppButton(
          key: const ValueKey('checkout-clear-sale'),
          label: 'Clear this sale',
          tier: AppButtonTier.destructive,
          onPressed: _saving ? null : () => _confirmClearSale(context),
        ),
      ],
      SizedBox(height: tokens.spacing.s20),
    ];
  }

  /// **§7's destructive pattern, in an `AlertDialog` on purpose.**
  ///
  /// `ConfirmDialog` is §5.1's own row for this and does not exist. What §7
  /// asks for is *"`action.destructive`, **filled**"* on the confirm button,
  /// and §2.1 has no filled destructive tier at all - its destructive row is a
  /// transparent container with a red label and a red border. The two sections
  /// disagree, and inventing the missing container here is what `claude.md`
  /// forbids, so the confirm takes §2.1's tier and the disagreement is an open
  /// decision in `PLAN.md`. The buttons are `AppButton`s either way, which is
  /// what closes step 3's last two Material controls in a dialog.
  Future<void> _confirmClearSale(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear this sale?'),
        content: const Text(
          'Every item is removed and the payment method is cleared. Nothing '
          'has been saved yet, so no record is lost.',
        ),
        actions: [
          AppButton(
            key: const ValueKey('checkout-clear-cancel'),
            label: 'Keep it',
            onPressed: () => Navigator.of(context).pop(false),
          ),
          AppButton(
            key: const ValueKey('checkout-clear-confirm'),
            label: 'Clear it',
            tier: AppButtonTier.destructive,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) _clearSale();
  }

  List<Widget> _tenderSection(BuildContext context, AppTokens tokens) =>
      <Widget>[
        Text(
          'How did the customer pay?',
          style: tokens.typography.titleMedium.copyWith(
            color: tokens.colors.text.primary,
          ),
        ),
        SizedBox(height: tokens.spacing.s4),
        // **Kept as permanent prose rather than folded**, which is the rule the
        // step-4 sweep settled: a `Disclosure` holds *policy*, and §7 says
        // "anything over two lines that explains policy rather than **the
        // current state**". This states what recording a tender does and does
        // not mean about the money, and a cashier is choosing one as they read
        // it - folding it would hide the caveat behind the control it is about.
        Text(
          checkoutTenderDisclaimer,
          style: tokens.typography.caption.copyWith(
            color: tokens.colors.text.tertiary,
          ),
        ),
        SizedBox(height: tokens.spacing.s8),
        Wrap(
          spacing: tokens.spacing.s8,
          runSpacing: tokens.spacing.s8,
          children: [
            for (final option in CheckoutTender.values)
              ChoiceChip(
                key: ValueKey('checkout-tender-${option.wireValue}'),
                label: Text(option.label),
                selected: _tender == option,
                onSelected: (_) => _chooseTender(option),
              ),
          ],
        ),
        SizedBox(height: tokens.spacing.s20),
      ];

  List<Widget> _saveSection(
    BuildContext context,
    AppTokens tokens,
    int? total,
  ) {
    if (widget.drafts == null) {
      return <Widget>[
        Callout(
          key: const ValueKey('checkout-unavailable'),
          status: _unavailable.status,
          message: _unavailable.message,
        ),
      ];
    }
    final blocker = _blocker(total);
    return <Widget>[
      // **§2.1's one `primary` per screen region.** It was a `FilledButton`
      // with a label that changed to "Saving..." mid-press, which is the exact
      // thing §2.1's loading row forbids - the container is held, the label is
      // replaced by a spinner, and the width is frozen so the button does not
      // resize under the finger that pressed it.
      AppButton(
        key: const ValueKey('checkout-save'),
        label: 'Save sale',
        tier: AppButtonTier.primary,
        expand: true,
        loading: _saving,
        onPressed: blocker == null && !_saving ? _save : null,
      ),
      if (blocker case final reason?) ...[
        SizedBox(height: tokens.spacing.s8),
        Text(
          key: const ValueKey('checkout-save-blocked'),
          reason,
          style: tokens.typography.caption.copyWith(
            color: tokens.colors.text.tertiary,
          ),
        ),
      ],
      if (_refusal case final refused?) ...[
        SizedBox(height: tokens.spacing.s16),
        // Every branch of [CheckoutRefusal] is a sale that was **not** written,
        // which is `AppNotice.refused` whatever `cashierCanFix` says: that flag
        // decides what to do next, not whether anything happened.
        Callout(
          key: const ValueKey('checkout-refusal'),
          status: AppNotice.refused(refused.message).status,
          message: refused.message,
        ),
        // §8 rule 6, "say what is still true", and it is a different fact from
        // the refusal itself - so it stays its own line rather than being
        // concatenated into one paragraph a cashier has to read to the end of.
        if (!refused.cashierCanFix) ...[
          SizedBox(height: tokens.spacing.s4),
          Text(
            key: const ValueKey('checkout-refusal-needs-help'),
            'Trying again will not clear this on its own.',
            style: tokens.typography.caption.copyWith(
              color: tokens.colors.text.tertiary,
            ),
          ),
        ],
      ],
    ];
  }
}

/// One sellable product in the grid.
///
/// **A depleted product is marked and stays sellable.** The panel's own scope
/// decision is that the cached figure never blocks a sale - it is what this
/// device last saw, not what the shop holds - so this changes what a cashier
/// can see at a glance and never what they can ring up. It is marked with a
/// word and an icon rather than by colour alone, because colour alone is not
/// readable to everyone and does not survive a photocopied training sheet.
final class _ProductTile extends StatelessWidget {
  const _ProductTile({
    super.key,
    required this.product,
    required this.detail,
    required this.onTap,
  });

  final TenantProduct product;

  /// The price-and-stock sentence, worded by the panel so that one place
  /// decides how a cached figure is stated.
  final String detail;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final depleted = product.quantity <= 0;
    final problem = tokens.colors.status.problem;
    // §2.3's row for "cards, rows, sheets". It was 14, which is not on §2.3's
    // radius scale at all - the nearest named value is `radius.md`.
    final radius = BorderRadius.circular(tokens.radius.md);
    return PressSurface(
      // §2.4's press, and §5.1's own replacement for the `InkWell` this used to
      // be. The ripple was already dead at the theme since step 2; what was
      // missing on the most-pressed control in the app was the scale.
      borderRadius: radius,
      onPressed: onTap,
      fillWidth: true,
      fillHeight: true,
      hoverOverlay: tokens.colors.action.secondary.hoverFill(),
      pressedOverlay: tokens.colors.action.secondary.pressedFill(),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.colors.surface.raised,
          borderRadius: radius,
          // **A depleted tile keeps its red edge and never relies on it.** §9
          // forbids status by hue alone, and the word and the glyph below are
          // what carry it; the border is the same signal drawn again.
          border: Border.all(
            color: depleted ? problem.border : tokens.colors.surface.borderSubtle,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.s8),
          // The picture and the name share a row; the price and stock run the
          // full width beneath them. Beside the thumbnail there was room for
          // "KES 65.00, 40 i..." and no more - and the figure that got cut was
          // the stock, which is the one a cashier is checking.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ProductThumbnail(product: product),
                  SizedBox(width: tokens.spacing.s8),
                  Expanded(
                    child: Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      // §2.2's `title.md`: "card title, **record name**". It
                      // was `titleSmall` with a hand-applied `w600`, which is
                      // Material's scale plus a weight nobody wrote down.
                      style: tokens.typography.titleMedium.copyWith(
                        color: tokens.colors.text.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                key: ValueKey('checkout-product-stock-${product.id}'),
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens.typography.caption.copyWith(
                  color: tokens.colors.text.tertiary,
                ),
              ),
              if (depleted)
                Row(
                  key: ValueKey('checkout-product-depleted-${product.id}'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      AppStatus.problem.defaultIcon,
                      size: StatusBadge.iconSize,
                      color: problem.fg,
                    ),
                    SizedBox(width: tokens.spacing.s4),
                    Flexible(
                      child: Text(
                        'Out of stock',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tokens.typography.labelMedium.copyWith(
                          color: problem.fg,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The picture on a product tile, or a stand-in for it.
///
/// **Nothing in this app can put a picture here yet, and that is deliberate
/// rather than missing.** `TenantProduct` reads an optional HTTPS `image`, so a
/// product that has one is drawn with it - but `importProducts` refuses an
/// `image` column outright and `updateProduct` refuses the field as an unknown
/// key, so the only way one exists today is an operator writing it directly.
/// The stand-in is therefore the case that renders, and it is drawn as a
/// deliberate mark rather than as a broken-image glyph: an initial on the
/// surface's own tint, which is what the record cards elsewhere do for a person
/// with no photograph.
final class _ProductThumbnail extends StatelessWidget {
  const _ProductThumbnail({required this.product});

  final TenantProduct product;

  @override
  Widget build(BuildContext context) {
    final url = product.imageUrl;
    final tokens = AppTokens.componentOf(context);
    return ClipRRect(
      // §2.3's smallest named radius. It was 10, which is not on the scale.
      borderRadius: BorderRadius.circular(tokens.radius.sm),
      child: SizedBox(
        width: _thumbnailSize,
        height: _thumbnailSize,
        child: url == null
            ? _placeholder(context)
            : Image.network(
                url.toString(),
                fit: BoxFit.cover,
                // A product whose picture cannot be fetched still has to be
                // sellable, so a failed load falls back rather than throwing a
                // broken glyph into the middle of the till.
                errorBuilder: (context, _, _) => _placeholder(context),
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : _placeholder(context),
              ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    // §2.1's `overlay` is the step above a card, which is what a stand-in for a
    // photograph on a raised tile should be. It was `primaryContainer`, which
    // is Material's own pairing and had the initial in `onPrimaryContainer`.
    return Container(
      color: tokens.colors.surface.overlay,
      alignment: Alignment.center,
      child: Text(
        TenantInitialsAvatar.initialsOf(product.name),
        style: tokens.typography.titleMedium.copyWith(
          color: tokens.colors.text.secondary,
        ),
      ),
    );
  }
}

/// The compact layout's standing cart summary.
///
/// It states the total without the sheet being open, because that is the
/// number a customer is waiting to hear and putting it behind a tap is what
/// made the old single-scroll layout slow.
final class _CartBar extends StatelessWidget {
  const _CartBar({
    required this.currency,
    required this.total,
    required this.itemCount,
    required this.onOpen,
  });

  final String currency;
  final int? total;
  final int itemCount;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final accent = tokens.colors.action.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.colors.surface.raised,
        // The bar is the only thing separating the products from the page edge
        // on a phone, so its top edge is a boundary a person must perceive -
        // §9's own words for when the 3:1 row applies rather than not.
        border: Border(
          top: BorderSide(color: tokens.colors.surface.borderStrong),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.spacing.s16,
            vertical: tokens.spacing.s12,
          ),
          child: Row(
            children: [
              // §2.2's `numeric.body` - "money and counts **in flow**" - rather
              // than the hero role the cart pane's own total takes, and rather
              // than the `titleMedium` it was, which is a title role carrying
              // proportional figures.
              //
              // **A `StatLine` here and it overflowed at 411, which is worth
              // recording rather than quietly reverting.** That component is a
              // label column and a right-aligned figure column, sized for a
              // card where several of them stack; this strip has one figure and
              // about 200 logical pixels to put it in beside the control, so
              // the label column and the figure column fought over the same
              // room. §2.2's complaint about figures inside sentences is about
              // a *column* of them not lining up - a lone figure on a bar has
              // no column to line up with, and the role is what matters here.
              Expanded(
                child: Text(
                  key: const ValueKey('checkout-cart-bar-total'),
                  total == null
                      ? 'Total unavailable'
                      : 'Total: $currency ${_money(total!)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.typography.numericBody.copyWith(
                    color: total == null
                        ? tokens.colors.status.problem.fg
                        : tokens.colors.text.primary,
                  ),
                ),
              ),
              SizedBox(width: tokens.spacing.s12),
              Badge(
                key: const ValueKey('checkout-cart-badge'),
                isLabelVisible: itemCount > 0,
                // **Painted from §2.1 rather than from Material's default**,
                // which is the error red - a count of items in a cart is not a
                // problem, and drawing it in the palette's critical colour is
                // precisely the "one colour doing seven jobs" §1 objects to.
                backgroundColor: accent.container,
                textColor: accent.label,
                label: Text('$itemCount'),
                child: AppButton(
                  key: const ValueKey('checkout-open-cart'),
                  // §8 rule 3 and §5.2: a button label is "always a verb phrase
                  // naming the effect". It said "Cart", which is the noun for
                  // where it goes rather than the verb for what it does - and
                  // §11 step 11's copy pass could not reach this screen,
                  // because the whole file was step 7's.
                  label: 'Open the cart',
                  icon: Icons.shopping_cart_outlined,
                  onPressed: onOpen,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _CartLine extends StatelessWidget {
  const _CartLine({
    super.key,
    required this.product,
    required this.productId,
    required this.quantity,
    required this.quantityUnusable,
    required this.currency,
    required this.onQuantityChanged,
    required this.onDecrement,
    required this.onRemove,
  });

  /// Null when the cached catalog no longer holds the product.
  final TenantProduct? product;
  final String productId;
  final int quantity;

  /// Whether the field currently holds something that is not a usable
  /// quantity. The line still carries [quantity], its last usable value.
  final bool quantityUnusable;

  final String currency;
  final ValueChanged<String> onQuantityChanged;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final resolved = product;
    final minor = resolved == null
        ? null
        : checkoutMinorUnitsFromMajor(resolved.price);
    final note = tokens.typography.caption.copyWith(
      color: tokens.colors.text.tertiary,
    );
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.spacing.s8),
      child: DecoratedBox(
        // A `Card` painted Material's own surface and elevation. §2.1 is blunt
        // that "depth is expressed by surface step, never by drop shadow", and
        // a raised surface with a hairline is what a card is everywhere else in
        // this app - `StatTile` and `Callout` are both made of these two rows.
        decoration: BoxDecoration(
          color: tokens.colors.surface.raised,
          border: Border.all(color: tokens.colors.surface.borderSubtle),
          borderRadius: BorderRadius.circular(tokens.radius.md),
        ),
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          resolved?.name ?? 'Unavailable product',
                          style: tokens.typography.titleMedium.copyWith(
                            color: tokens.colors.text.primary,
                          ),
                        ),
                        Text(
                          key: ValueKey('checkout-line-amount-$productId'),
                          minor == null
                              ? 'This item cannot be priced on this device.'
                              : '$quantity x $currency ${_money(minor)}'
                                    ' = $currency ${_money(minor * quantity)}',
                          // §2.2's `numeric.body`, which is the row for "money
                          // and counts in flow" and carries tabular figures -
                          // so a column of line amounts stops being ragged.
                          style: tokens.typography.numericBody.copyWith(
                            color: tokens.colors.text.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: tokens.spacing.s8),
                  _QuantityField(
                    key: ValueKey('checkout-line-quantity-$productId'),
                    quantity: quantity,
                    onChanged: onQuantityChanged,
                  ),
                  // **Still `IconButton`s, and that is `QuantityStepper`'s to
                  // fix.** §5.1 gives it priority 1 and describes the defect as
                  // "minus + delete, no plus"; a component that decides what a
                  // stepper is cannot be guessed at inside a restyling chunk,
                  // and painting these two would settle its shape by accident.
                  IconButton(
                    key: ValueKey('checkout-line-less-$productId'),
                    onPressed: onDecrement,
                    icon: const Icon(Icons.remove),
                    tooltip: 'One fewer',
                  ),
                  IconButton(
                    key: ValueKey('checkout-line-remove-$productId'),
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Remove item',
                  ),
                ],
              ),
              if (quantityUnusable)
                Text(
                  key: ValueKey('checkout-line-quantity-invalid-$productId'),
                  'That is not a quantity this till can sell. This line still '
                  'has $quantity.',
                  style: note.copyWith(color: tokens.colors.status.problem.fg),
                ),
              // Stated, never enforced: the cached figure is what this device
              // last saw, and the server permits stock to go negative.
              if (resolved != null && quantity > resolved.quantity)
                Text(
                  key: ValueKey('checkout-line-stock-$productId'),
                  'This device last saw ${resolved.quantity} in stock. The '
                  'sale is not blocked by that count.',
                  style: note,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Direct quantity entry for one cart line.
///
/// The field belongs to the cashier, not to the cart: it is overwritten only
/// when the cart itself moved the number - a plus or minus tap - and never
/// while an entry is merely unusable. Snapping a rejected entry back to the
/// last good value would leave a valid number on screen beside a message
/// saying the quantity is wrong, with nothing to correct.
final class _QuantityField extends StatefulWidget {
  const _QuantityField({
    super.key,
    required this.quantity,
    required this.onChanged,
  });

  final int quantity;
  final ValueChanged<String> onChanged;

  @override
  State<_QuantityField> createState() => _QuantityFieldState();
}

final class _QuantityFieldState extends State<_QuantityField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.quantity.toString(),
  );

  @override
  void didUpdateWidget(covariant _QuantityField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.quantity != widget.quantity &&
        int.tryParse(_controller.text.trim()) != widget.quantity) {
      _controller.text = widget.quantity.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    // **Wider than the 104 it was, and the reason is measurable.** §5.2 gives a
    // field `space.20` of horizontal padding inside a pill on each side, which
    // is 40 before a digit is drawn; a 104-wide well left about 60 for the
    // number and its caret. This is the second of step 3's two remaining call
    // sites and the only one whose width is fixed by its own row.
    width: _quantityFieldWidth,
    child: AppTextField(
      label: 'Quantity',
      controller: _controller,
      keyboardType: TextInputType.number,
      onChanged: widget.onChanged,
    ),
  );
}

/// How wide the cart line's quantity well is drawn.
///
/// Named rather than tokenised, for the reason [_productTileExtent] gives: a
/// field's *width* is not one of §2.3's rows, and §5.2 fixes a field's height
/// and padding and says nothing about how wide a numeric one should be.
const double _quantityFieldWidth = 132;

String _money(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);

/// Thousands separators, so a bound quoted to a cashier stays readable and
/// stays derived from the constant it describes.
String _grouped(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write(',');
    buffer.write(digits[index]);
  }
  return buffer.toString();
}

String _instant(DateTime value) {
  final utc = value.toUtc();
  String pad(int part) => part.toString().padLeft(2, '0');
  return '${utc.year}-${pad(utc.month)}-${pad(utc.day)} '
      '${pad(utc.hour)}:${pad(utc.minute)} UTC';
}
