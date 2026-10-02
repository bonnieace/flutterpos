/// Who the sale on the till is for: walk-in, a customer the business already
/// has, or one added on the spot.
///
/// **Chosen from the till's title, the way a business is chosen from the
/// home's.** The word *Register* in the top bar became the customer's name,
/// with the same chevron the business switcher wears, at the developer's
/// direction on 2026-10-01. A walk-in is the default and the till returns to
/// it after every sale, so a cashier who never touches it sells exactly as
/// before.
///
/// **Nothing here stands between the cashier and the sale.** The choice is made
/// before the sale is saved, from a control that is never in the way of the
/// cart; saving never asks who the customer is.
///
/// **This device's copy answers first.** The picker draws what the cache holds
/// the moment it opens and lets the server correct it, so a till with no
/// signal still offers every customer it has seen - and one added a second ago
/// on this till, which the pending overlay draws before the server has them.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../customers/customer.dart';
import '../customers/customer_card.dart';
import '../customers/customer_credit.dart';
import '../customers/customer_form.dart';
import '../customers/customer_payment_sheet.dart';
import '../observability/app_telemetry.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_session.dart';
import '../ui/buttons.dart';
import '../ui/dialogs.dart';
import '../ui/fields.dart';
import '../ui/money_text.dart';
import '../ui/snackbar.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import '../whatsapp/receipt_delivery.dart';
import 'checkout_configuration.dart';
import 'checkout_sale.dart';

/// What the till needs to offer customers: where to search them, and where an
/// added one is queued.
final class CheckoutCustomerServices {
  const CheckoutCustomerServices({
    required this.reader,
    this.writer,
    this.receiptWriter,
    this.payments,
  });

  /// Where *Take a payment* queues a repayment. Null offers none.
  final CustomerPaymentServices? payments;

  /// The overlay reader the routes hold, so a customer queued on this device
  /// is found before the server has them.
  final TenantDataReader reader;

  /// Where a customer added at the till is queued. Null offers no *Add new
  /// customer*.
  final TenantCustomerWriter? writer;

  /// Where a cashier's *Send on WhatsApp* is queued. Null offers no such
  /// button, whatever the business's WhatsApp setting says.
  final TenantWhatsappReceiptWriter? receiptWriter;
}

/// What the cashier chose.
sealed class CheckoutCustomerPick {
  const CheckoutCustomerPick();
}

/// Nobody named on the sale.
final class CheckoutWalkInPick extends CheckoutCustomerPick {
  const CheckoutWalkInPick();
}

/// A customer, chosen from the list or added on the spot.
final class CheckoutChosenCustomerPick extends CheckoutCustomerPick {
  const CheckoutChosenCustomerPick(this.customer, {this.notice});

  final TenantCustomer customer;

  /// What to say once the picker closes - that a new customer was added, say.
  final AppNotice? notice;
}

/// The customer as a sale carries them.
CheckoutSaleCustomer checkoutSaleCustomerOf(TenantCustomer customer) =>
    CheckoutSaleCustomer(
      id: customer.id,
      name: customer.name,
      kraPin: customer.kraPin,
    );

/// Opens the picker over the till, answering with what was chosen, or null
/// when it was closed without a choice.
Future<CheckoutCustomerPick?> showCheckoutCustomerPicker(
  BuildContext context, {
  required TenantSession session,
  required CheckoutCustomerServices services,
  TenantCustomer? selected,
}) => showAppDialog<CheckoutCustomerPick>(
  context,
  barrierDismissible: true,
  builder: (dialogContext) => _CustomerPicker(
    session: session,
    services: services,
    selected: selected,
    onPicked: (pick) => Navigator.of(dialogContext).pop(pick),
    onCancel: () => Navigator.of(dialogContext).pop(),
  ),
);

final class _CustomerPicker extends StatefulWidget {
  const _CustomerPicker({
    required this.session,
    required this.services,
    required this.selected,
    required this.onPicked,
    required this.onCancel,
  });

  final TenantSession session;
  final CheckoutCustomerServices services;
  final TenantCustomer? selected;
  final ValueChanged<CheckoutCustomerPick> onPicked;
  final VoidCallback onCancel;

  /// How many customers one search offers. A picker is for finding one person;
  /// a list long enough to scroll is a list somebody should be searching.
  static const int pageSize = 8;

  @override
  State<_CustomerPicker> createState() => _CustomerPickerState();
}

final class _CustomerPickerState extends State<_CustomerPicker> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  int _generation = 0;
  List<TenantCustomer> _customers = const <TenantCustomer>[];
  bool _loading = true;
  bool _serverAnswered = false;
  bool _unreachable = false;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    unawaited(_find(''));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      AppMotion.standard.long.duration,
      () => unawaited(_find(value)),
    );
  }

  Future<TenantCustomerPage> _read(TenantDataReader reader, String query) =>
      TenantCustomerRepository(
        session: widget.session,
        reader: reader,
      ).search(search: query, pageSize: _CustomerPicker.pageSize);

  /// The cache, then the server, and the server always wins.
  Future<void> _find(String query) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _serverAnswered = false;
      _unreachable = false;
    });
    final cached = widget.services.reader.cached;
    if (cached != null) {
      unawaited(() async {
        try {
          final page = await _read(cached, query);
          if (!mounted || generation != _generation || _serverAnswered) return;
          setState(() {
            _customers = page.customers;
            _loading = page.customers.isEmpty;
          });
        } catch (error, stackTrace) {
          // A cache with nothing in it is silence, as on every route.
          AppTelemetry.captureHandled(
            error,
            stackTrace,
            boundary: 'checkout.customer_cached_search',
          );
        }
      }());
    }
    try {
      final page = await _read(widget.services.reader, query);
      if (!mounted || generation != _generation) return;
      setState(() {
        _customers = page.customers;
        _serverAnswered = true;
        _loading = false;
      });
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'checkout.customer_search',
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _unreachable = true;
      });
    }
  }

  bool get _canAdd =>
      widget.services.writer != null &&
      TenantCustomerRepository.canCreateInSession(widget.session);

  /// The chosen customer, when they owe something a cashier may take back.
  TenantCustomer? get _payable {
    final customer = widget.selected;
    if (customer == null ||
        customer.owedMinor <= 0 ||
        widget.services.payments == null ||
        !TenantCustomerCreditRepository.canTakePaymentInSession(
          widget.session,
        )) {
      return null;
    }
    return customer;
  }

  bool _paying = false;

  /// Takes a repayment from the chosen customer, then closes the picker on
  /// them - they are still who the sale is for - with what was recorded.
  Future<void> _takePayment(TenantCustomer customer) async {
    final payments = widget.services.payments;
    if (payments == null || _paying) return;
    setState(() => _paying = true);
    String currency = '';
    try {
      final reader = widget.services.reader;
      currency =
          (await TenantCheckoutConfigurationRepository(
            session: widget.session,
            reader: reader.cached ?? reader,
          ).load())?.currency ??
          '';
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'checkout.customer_currency',
      );
    }
    if (!mounted) return;
    final notice = await showCustomerPaymentDialog(
      context,
      session: widget.session,
      customer: customer,
      services: payments,
      currency: currency,
    );
    if (!mounted) return;
    setState(() => _paying = false);
    if (notice == null) return;
    widget.onPicked(CheckoutChosenCustomerPick(customer, notice: notice));
  }

  Future<void> _add() async {
    final writer = widget.services.writer;
    if (writer == null || _adding) return;
    setState(() => _adding = true);
    String? currency;
    try {
      final reader = widget.services.reader;
      currency = (await TenantCheckoutConfigurationRepository(
        session: widget.session,
        reader: reader.cached ?? reader,
      ).load())?.currency;
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'checkout.customer_currency',
      );
    }
    if (!mounted) return;
    final outcome = await showCustomerFormSheet(
      context,
      session: widget.session,
      reader: widget.services.reader,
      writer: writer,
      dialCode: dialCodeForCurrency(currency),
      atTill: true,
    );
    if (!mounted) return;
    setState(() => _adding = false);
    final customer = outcome?.customer;
    if (outcome == null || customer == null) return;
    widget.onPicked(
      CheckoutChosenCustomerPick(customer, notice: outcome.notice),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final selectedId = widget.selected?.id;
    return AppDialog(
      title: 'Who is this sale for?',
      actions: <Widget>[
        AppButton(
          key: const ValueKey('checkout-customer-cancel'),
          label: 'Cancel',
          tier: AppButtonTier.tertiary,
          onPressed: widget.onCancel,
        ),
      ],
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppTextField(
            key: const ValueKey('checkout-customer-search'),
            controller: _search,
            label: 'Search customers',
            placeholder: 'Name or number',
            leading: Icons.search,
            dense: true,
            onChanged: _onChanged,
          ),
          SizedBox(height: tokens.spacing.s8),
          _PickerRow(
            rowKey: const ValueKey('checkout-customer-walk-in'),
            icon: Icons.storefront_outlined,
            title: 'Walk-in',
            subtitle: 'Nobody named on the sale',
            selected: selectedId == null,
            onTap: () => widget.onPicked(const CheckoutWalkInPick()),
          ),
          for (final customer in _customers)
            _PickerRow(
              rowKey: ValueKey('checkout-customer-${customer.id}'),
              icon: Icons.person_outline,
              title: customer.name,
              // What they owe leads, so a long contact line can never be the
              // part that survives the one-line cut and the debt the part lost.
              subtitle: <String>[
                if (customer.owedMinor > 0)
                  'Owes ${moneyTextOfMinor(customer.owedMinor)}',
                customerContactLine(customer),
                if (customer.points > 0) customerPointsLabel(customer.points),
              ].join(' · '),
              selected: customer.id == selectedId,
              onTap: () => widget.onPicked(CheckoutChosenCustomerPick(customer)),
            ),
          if (_loading && _customers.isEmpty) ...<Widget>[
            SizedBox(height: tokens.spacing.s8),
            const LinearProgressIndicator(
              key: ValueKey('checkout-customer-loading'),
            ),
          ] else if (_customers.isEmpty && _search.text.trim().isNotEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: tokens.spacing.s12),
              child: Text(
                'No customer by that name or number.',
                key: const ValueKey('checkout-customer-none'),
                style: tokens.typography.bodyMedium.copyWith(
                  color: tokens.colors.text.tertiary,
                ),
              ),
            ),
          if (_unreachable) ...<Widget>[
            SizedBox(height: tokens.spacing.s8),
            const Callout(
              key: ValueKey('checkout-customer-offline'),
              status: AppStatus.info,
              message:
                  'Showing the customers this device holds. Others appear once '
                  'it is back online.',
            ),
          ],
          if (_payable case final customer?) ...<Widget>[
            SizedBox(height: tokens.spacing.s8),
            AppButton(
              key: const ValueKey('checkout-customer-take-payment'),
              label: 'Take a payment from ${customer.name}',
              icon: Icons.payments_outlined,
              tier: AppButtonTier.secondary,
              expand: true,
              onPressed: _paying ? null : () => _takePayment(customer),
            ),
          ],
          if (_canAdd) ...<Widget>[
            SizedBox(height: tokens.spacing.s8),
            Divider(height: 1, color: tokens.colors.surface.borderSubtle),
            SizedBox(height: tokens.spacing.s8),
            // **No spinner while the form is open.** The press opens a sheet
            // over the picker, and a button still turning behind a form the
            // cashier is filling in says something is wrong when nothing is.
            // [_adding] only stops a second press opening a second sheet.
            AppButton(
              key: const ValueKey('checkout-customer-add'),
              label: 'Add new customer',
              icon: Icons.person_add_alt_outlined,
              tier: AppButtonTier.secondary,
              expand: true,
              onPressed: _adding ? null : _add,
            ),
          ],
        ],
      ),
    );
  }
}

/// One choice in the picker: what the business switcher draws for a business.
final class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.rowKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final Key rowKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return ListTile(
      key: rowKey,
      contentPadding: EdgeInsets.zero,
      minTileHeight: tokens.density.minimumTapTarget.height,
      leading: Icon(icon, color: tokens.colors.text.secondary),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      // **The chosen one carries a glyph, not only a colour** - hard rule 4.
      trailing: selected
          ? Icon(
              Icons.check_circle,
              semanticLabel: 'Chosen',
              color: tokens.colors.action.primary.container,
            )
          : null,
      selected: selected,
      onTap: onTap,
    );
  }
}

/// Reports what the picker said once it has closed over the till.
void reportCheckoutCustomerPick(BuildContext context, CheckoutCustomerPick pick) {
  if (pick case CheckoutChosenCustomerPick(:final notice?)) {
    showAppSnackBar(context, notice);
  }
}
