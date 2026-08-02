import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tenancy/tenant_catalog.dart';
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

/// Guarded point-of-sale route for the selected tenant session.
final class TenantCheckoutScreen extends StatelessWidget {
  const TenantCheckoutScreen({super.key, required this.cache, this.drafts});

  final CheckoutCatalogSource cache;

  /// Absent until the composition root supplies it; the cart then prices a
  /// sale but cannot save one, exactly as the returns route behaves.
  final CheckoutDraftSink? drafts;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('New sale')),
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
  String? _codeNotice;

  CheckoutCatalogSnapshot get _snapshot => widget.snapshot;

  @override
  void dispose() {
    _search.dispose();
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
        _codeNotice =
            'More than one product on this device carries that code, so '
            'nothing was added. Pick the right one from the list.';
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
          ? 'Nothing on this device matches that. Check the code and try '
                'again.'
          : 'That matches more than one product, so nothing was added. Pick '
                'one from the list, or enter its exact code.';
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

  @override
  Widget build(BuildContext context) {
    final total = _totalMinor;
    final currency = _snapshot.configuration.currency;
    final text = Theme.of(context).textTheme;
    return ListView(
      key: const ValueKey('checkout-cart'),
      padding: const EdgeInsets.all(20),
      children: [
        Text('New sale', style: text.headlineSmall),
        const SizedBox(height: 16),
        ..._receiptSection(context),
        ..._catalogSection(context, currency),
        ..._saleSection(context, currency, total),
        ..._tenderSection(context),
        ..._saveSection(context, total),
        const SizedBox(height: 16),
        const Text(
          'A saved sale is submitted and confirmed automatically. It cannot be '
          'edited, retried, or deleted here.',
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
  List<Widget> _receiptSection(BuildContext context) {
    final saved = _saved;
    if (saved == null) return const <Widget>[];
    final receipt = saved.receiptNumber;
    return <Widget>[
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                key: const ValueKey('checkout-saved'),
                receipt == null
                    ? 'Saved on this device, but it could not state a receipt '
                          'number for this sale. The sale still syncs on its '
                          'own. Ask for help before giving the customer a '
                          'receipt number.'
                    : 'Saved on this device as $receipt. It syncs on its own; '
                          'there is nothing else to press. This stays here '
                          'until you close it, so the number can be written '
                          'down.',
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  if (receipt != null)
                    OutlinedButton(
                      key: const ValueKey('checkout-copy-receipt'),
                      onPressed: () => _copyReceipt(receipt),
                      child: const Text('Copy receipt number'),
                    ),
                  TextButton(
                    key: const ValueKey('checkout-dismiss-receipt'),
                    onPressed: _dismissReceipt,
                    child: const Text('Close'),
                  ),
                ],
              ),
              if (_receiptCopied)
                const Text(
                  key: ValueKey('checkout-receipt-copied'),
                  'Receipt number copied.',
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),
    ];
  }

  List<Widget> _catalogSection(BuildContext context, String currency) {
    final text = Theme.of(context).textTheme;
    final matches = _visibleProducts;
    // A `Wrap` builds every child eagerly even inside a `ListView`, and the
    // cache admits two thousand products. Only what is drawn is bounded; every
    // match stays sellable by narrowing the search or entering its code.
    final visible = matches.length > maximumRenderedCheckoutProducts
        ? matches.sublist(0, maximumRenderedCheckoutProducts)
        : matches;
    return <Widget>[
      Text('Products', style: text.titleSmall),
      const SizedBox(height: 4),
      Text(
        key: const ValueKey('checkout-catalog-freshness'),
        'Prices and stock come from this device, last synced '
        '${_instant(_snapshot.refreshedAt)}. A sale is never blocked by a '
        'stock count.',
        style: text.bodySmall,
      ),
      if (!_snapshot.complete)
        Text(
          key: const ValueKey('checkout-catalog-partial'),
          'This device holds only part of the product list for this business, '
          'so a product may be missing from it.',
          style: text.bodySmall,
        ),
      const SizedBox(height: 8),
      TextField(
        key: const ValueKey('checkout-search'),
        controller: _search,
        textInputAction: TextInputAction.done,
        onChanged: (_) => setState(() => _codeNotice = null),
        onSubmitted: (_) => _submitSearch(),
        decoration: const InputDecoration(
          labelText: 'Search by name or code',
          helperText: 'Scan or enter a code and press enter to add it.',
          isDense: true,
        ),
      ),
      if (_codeNotice case final notice?) ...[
        const SizedBox(height: 4),
        Text(key: const ValueKey('checkout-code-notice'), notice),
      ],
      if (_snapshot.categories.isNotEmpty || _hasUncachedCategories) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
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
      const SizedBox(height: 8),
      if (_snapshot.products.isEmpty)
        const Text(
          key: ValueKey('checkout-catalog-empty'),
          'This device holds no products for this business yet. Connect to '
          'sync them before selling.',
        )
      else if (visible.isEmpty)
        const Text(
          key: ValueKey('checkout-catalog-no-matches'),
          'No product on this device matches that search. Clear it to see the '
          'whole list.',
        )
      else ...[
        if (matches.length > visible.length) ...[
          Text(
            key: const ValueKey('checkout-catalog-truncated'),
            'Showing ${visible.length} of ${matches.length} matching '
            'products. Narrow the search, or enter a code to add one '
            'directly.',
            style: text.bodySmall,
          ),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final product in visible)
              OutlinedButton(
                key: ValueKey('checkout-product-${product.id}'),
                onPressed: () => _add(product),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name),
                    Text(
                      key: ValueKey('checkout-product-stock-${product.id}'),
                      _productDetail(product, currency),
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
      const SizedBox(height: 20),
    ];
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
    String currency,
    int? total,
  ) {
    final text = Theme.of(context).textTheme;
    return <Widget>[
      Text('This sale', style: text.titleSmall),
      const SizedBox(height: 4),
      if (_quantities.isEmpty)
        const Text(
          key: ValueKey('checkout-cart-empty'),
          'No items yet. Add a product to start the sale.',
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
      const SizedBox(height: 12),
      Text(
        key: const ValueKey('checkout-total'),
        total == null
            ? 'This sale cannot be totalled because one item has a price the '
                  'till cannot record exactly.'
            : 'Total: $currency ${_money(total)}',
        style: text.titleMedium,
      ),
      // Offered only when there is something to abandon, and never for a saved
      // sale: nothing here is persisted, so this destroys no record.
      if (_quantities.isNotEmpty) ...[
        const SizedBox(height: 8),
        OutlinedButton(
          key: const ValueKey('checkout-clear-sale'),
          onPressed: _saving ? null : () => _confirmClearSale(context),
          child: const Text('Clear this sale'),
        ),
      ],
      const SizedBox(height: 20),
    ];
  }

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
          TextButton(
            key: const ValueKey('checkout-clear-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            key: const ValueKey('checkout-clear-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear it'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) _clearSale();
  }

  List<Widget> _tenderSection(BuildContext context) => <Widget>[
    Text(
      'How did the customer pay?',
      style: Theme.of(context).textTheme.titleSmall,
    ),
    const SizedBox(height: 4),
    const Text(checkoutTenderDisclaimer),
    const SizedBox(height: 8),
    Wrap(
      spacing: 8,
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
    const SizedBox(height: 20),
  ];

  List<Widget> _saveSection(BuildContext context, int? total) {
    if (widget.drafts == null) {
      return const <Widget>[
        Text(
          key: ValueKey('checkout-unavailable'),
          'Saving a sale is unavailable on this device.',
        ),
      ];
    }
    final blocker = _blocker(total);
    return <Widget>[
      FilledButton(
        key: const ValueKey('checkout-save'),
        onPressed: blocker == null && !_saving ? _save : null,
        child: Text(_saving ? 'Saving...' : 'Save sale'),
      ),
      if (blocker case final reason?) ...[
        const SizedBox(height: 8),
        Text(key: const ValueKey('checkout-save-blocked'), reason),
      ],
      if (_refusal case final refused?) ...[
        const SizedBox(height: 16),
        Text(key: const ValueKey('checkout-refusal'), refused.message),
        if (!refused.cashierCanFix)
          const Text(
            key: ValueKey('checkout-refusal-needs-help'),
            'Trying again will not clear this on its own.',
          ),
      ],
    ];
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
    final resolved = product;
    final minor = resolved == null
        ? null
        : checkoutMinorUnitsFromMajor(resolved.price);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(resolved?.name ?? 'Unavailable product'),
                      Text(
                        key: ValueKey('checkout-line-amount-$productId'),
                        minor == null
                            ? 'This item cannot be priced on this device.'
                            : '$quantity x $currency ${_money(minor)}'
                                  ' = $currency ${_money(minor * quantity)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                _QuantityField(
                  key: ValueKey('checkout-line-quantity-$productId'),
                  quantity: quantity,
                  onChanged: onQuantityChanged,
                ),
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
                style: Theme.of(context).textTheme.bodySmall,
              ),
            // Stated, never enforced: the cached figure is what this device
            // last saw, and the server permits stock to go negative.
            if (resolved != null && quantity > resolved.quantity)
              Text(
                key: ValueKey('checkout-line-stock-$productId'),
                'This device last saw ${resolved.quantity} in stock. The sale '
                'is not blocked by that count.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
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
    width: 104,
    child: TextField(
      controller: _controller,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      onChanged: widget.onChanged,
      decoration: const InputDecoration(labelText: 'Quantity', isDense: true),
    ),
  );
}

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
