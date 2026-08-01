import 'package:flutter/material.dart';

import '../tenancy/tenant_catalog.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import 'checkout_catalog_cache.dart';
import 'checkout_draft.dart';
import 'checkout_refusal.dart';
import 'checkout_sale.dart';
import 'checkout_tender.dart';

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
/// Two scope decisions are recorded here because both are easy to reverse by
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
final class TenantCheckoutPanel extends StatefulWidget {
  const TenantCheckoutPanel({super.key, required this.cache, this.drafts});

  final CheckoutCatalogSource cache;
  final CheckoutDraftSink? drafts;

  @override
  State<TenantCheckoutPanel> createState() => _TenantCheckoutPanelState();
}

final class _TenantCheckoutPanelState extends State<TenantCheckoutPanel> {
  /// Requested quantity per product, in insertion order.
  final Map<String, int> _quantities = <String, int>{};

  CheckoutTender? _tender;
  bool _saving = false;
  CheckoutRefusal? _refusal;
  String? _savedReceipt;

  /// One loader per session, so a tenant switch reloads rather than reusing
  /// another business's catalog.
  String? _loaderKey;
  TenantGuardedLoader<CheckoutCatalogSnapshot>? _loader;

  TenantGuardedLoader<CheckoutCatalogSnapshot> _loaderFor(
    TenantSession session,
  ) {
    final key = '${session.uid}:${session.tenantId}:${session.epoch}';
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

  void _add(TenantProduct product) {
    if (!_quantities.containsKey(product.id) &&
        _quantities.length >= maximumCheckoutSaleLines) {
      setState(() {
        _refusal = CheckoutRefusal.forCode('invalid_line_count');
      });
      return;
    }
    setState(() {
      _quantities[product.id] = (_quantities[product.id] ?? 0) + 1;
      _clearOutcome();
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
      _clearOutcome();
    });
  }

  void _remove(String productId) {
    setState(() {
      _quantities.remove(productId);
      _clearOutcome();
    });
  }

  void _chooseTender(CheckoutTender tender) {
    setState(() {
      _tender = tender;
      _clearOutcome();
    });
  }

  /// Clears the previous attempt's outcome so a stale receipt or refusal can
  /// never sit beside a cart the cashier has since changed.
  void _clearOutcome() {
    _refusal = null;
    _savedReceipt = null;
  }

  Future<void> _save(CheckoutCatalogSnapshot snapshot) async {
    final drafts = widget.drafts;
    final tender = _tender;
    if (drafts == null || tender == null || _saving) return;

    setState(() {
      _saving = true;
      _clearOutcome();
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
      _savedReceipt = saved?.receiptNumber;
      // The cart is cleared only when the draft is durable, so a refused sale
      // keeps every line the cashier already rang up.
      if (saved != null) {
        _quantities.clear();
        _tender = null;
      }
    });
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
        builder: (context, session, snapshot) => _CartContents(
          snapshot: snapshot,
          quantities: Map<String, int>.unmodifiable(_quantities),
          tender: _tender,
          saving: _saving,
          refusal: _refusal,
          savedReceipt: _savedReceipt,
          canSave: widget.drafts != null,
          onAdd: _add,
          onDecrement: _decrement,
          onRemove: _remove,
          onChooseTender: _chooseTender,
          onSave: () => _save(snapshot),
        ),
      );
}

final class _CartContents extends StatelessWidget {
  const _CartContents({
    required this.snapshot,
    required this.quantities,
    required this.tender,
    required this.saving,
    required this.refusal,
    required this.savedReceipt,
    required this.canSave,
    required this.onAdd,
    required this.onDecrement,
    required this.onRemove,
    required this.onChooseTender,
    required this.onSave,
  });

  final CheckoutCatalogSnapshot snapshot;
  final Map<String, int> quantities;
  final CheckoutTender? tender;
  final bool saving;
  final CheckoutRefusal? refusal;
  final String? savedReceipt;
  final bool canSave;
  final ValueChanged<TenantProduct> onAdd;
  final ValueChanged<String> onDecrement;
  final ValueChanged<String> onRemove;
  final ValueChanged<CheckoutTender> onChooseTender;
  final VoidCallback onSave;

  /// The cart total, or null when a selected price cannot be recorded exactly.
  int? get _totalMinor {
    var total = 0;
    for (final entry in quantities.entries) {
      final product = snapshot.productById(entry.key);
      if (product == null) return null;
      final minor = checkoutMinorUnitsFromMajor(product.price);
      if (minor == null) return null;
      total += minor * entry.value;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final total = _totalMinor;
    final currency = snapshot.configuration.currency;
    return ListView(
      key: const ValueKey('checkout-cart'),
      padding: const EdgeInsets.all(20),
      children: [
        Text('New sale', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),

        Text('Products', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        if (snapshot.products.isEmpty)
          const Text(
            key: ValueKey('checkout-catalog-empty'),
            'This device holds no products for this business yet. Connect to '
            'sync them before selling.',
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final product in snapshot.products)
                OutlinedButton(
                  key: ValueKey('checkout-product-${product.id}'),
                  onPressed: () => onAdd(product),
                  child: Text(product.name),
                ),
            ],
          ),
        const SizedBox(height: 20),

        Text('This sale', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        if (quantities.isEmpty)
          const Text(
            key: ValueKey('checkout-cart-empty'),
            'No items yet. Add a product to start the sale.',
          )
        else
          for (final entry in quantities.entries)
            _CartLine(
              product: snapshot.productById(entry.key),
              productId: entry.key,
              quantity: entry.value,
              currency: currency,
              onDecrement: () => onDecrement(entry.key),
              onRemove: () => onRemove(entry.key),
            ),
        const SizedBox(height: 12),
        Text(
          key: const ValueKey('checkout-total'),
          total == null
              ? 'This sale cannot be totalled because one item has a price the '
                    'till cannot record exactly.'
              : 'Total: $currency ${_money(total)}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 20),

        Text('How did the customer pay?',
            style: Theme.of(context).textTheme.titleSmall),
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
                selected: tender == option,
                onSelected: (_) => onChooseTender(option),
              ),
          ],
        ),
        const SizedBox(height: 20),

        if (!canSave)
          const Text(
            key: ValueKey('checkout-unavailable'),
            'Saving a sale is unavailable on this device.',
          )
        else ...[
          FilledButton(
            key: const ValueKey('checkout-save'),
            onPressed: _blocker(total) == null && !saving ? onSave : null,
            child: Text(saving ? 'Saving...' : 'Save sale'),
          ),
          if (_blocker(total) case final reason?) ...[
            const SizedBox(height: 8),
            Text(key: const ValueKey('checkout-save-blocked'), reason),
          ],
        ],

        if (refusal case final refused?) ...[
          const SizedBox(height: 16),
          Text(key: const ValueKey('checkout-refusal'), refused.message),
          if (!refused.cashierCanFix)
            const Text(
              key: ValueKey('checkout-refusal-needs-help'),
              'Trying again will not clear this on its own.',
            ),
        ],
        if (savedReceipt case final receipt?) ...[
          const SizedBox(height: 16),
          Text(
            key: const ValueKey('checkout-saved'),
            'Saved on this device as $receipt. It syncs on its own; there is '
            'nothing else to press.',
          ),
        ],

        const SizedBox(height: 16),
        const Text(
          'A saved sale is submitted and confirmed automatically. It cannot be '
          'edited, retried, or deleted here.',
        ),
      ],
    );
  }

  /// Why saving is not offered yet, or null when the sale may be saved.
  ///
  /// The cart states the reason rather than presenting a dead button, because
  /// a disabled control with no explanation is how a till stalls.
  String? _blocker(int? total) {
    if (quantities.isEmpty) return 'Add at least one item to save this sale.';
    if (total == null) {
      return 'Remove the item whose price cannot be recorded exactly.';
    }
    if (tender == null) return 'Choose how the customer paid.';
    return null;
  }
}

final class _CartLine extends StatelessWidget {
  const _CartLine({
    required this.product,
    required this.productId,
    required this.quantity,
    required this.currency,
    required this.onDecrement,
    required this.onRemove,
  });

  /// Null when the cached catalog no longer holds the product.
  final TenantProduct? product;
  final String productId;
  final int quantity;
  final String currency;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final resolved = product;
    final minor = resolved == null
        ? null
        : checkoutMinorUnitsFromMajor(resolved.price);
    return Card(
      key: ValueKey('checkout-line-$productId'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
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
      ),
    );
  }
}

String _money(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);
