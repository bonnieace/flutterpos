/// *Record a payment*: a customer paying back what they owe, at the counter.
///
/// **Offered from the customer's record and from the till**, and the same form
/// in both: how much, and how it was paid. The money goes into the cashier's
/// own open shift - the one a sale would be in - so with no shift open it says
/// so, in the words the till uses, rather than taking money into no drawer.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uzapay_pos/observability/app_telemetry.dart';

import '../checkout/checkout_draft.dart';
import '../checkout/checkout_refusal.dart';
import '../checkout/checkout_tender.dart';
import '../inventory/catalog_management.dart';
import '../tenancy/tenant_session.dart';
import '../ui/buttons.dart';
import '../ui/chips.dart';
import '../ui/dialogs.dart';
import '../ui/fields.dart';
import '../ui/money_text.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'customer.dart';
import 'customer_credit.dart';

/// What *Record a payment* needs: where to queue it, and whose drawer it goes
/// into.
final class CustomerPaymentServices {
  const CustomerPaymentServices({required this.writer, required this.shifts});

  final TenantCustomerPaymentWriter writer;

  /// The till's own binder, so a payment is in exactly the shift a sale
  /// would be in, refused for exactly the reasons a sale would be.
  final CheckoutShiftBinder shifts;
}

/// Asks for one repayment from [customer], and answers the notice to show, or
/// null when the person changed their mind.
Future<AppNotice?> showCustomerPaymentDialog(
  BuildContext context, {
  required TenantSession session,
  required TenantCustomer customer,
  required CustomerPaymentServices services,
  required String currency,
}) => showAppDialog<AppNotice>(
  context,
  barrierDismissible: true,
  builder: (_) => _CustomerPaymentDialog(
    session: session,
    customer: customer,
    services: services,
    currency: currency,
  ),
);

final class _CustomerPaymentDialog extends StatefulWidget {
  const _CustomerPaymentDialog({
    required this.session,
    required this.customer,
    required this.services,
    required this.currency,
  });

  final TenantSession session;
  final TenantCustomer customer;
  final CustomerPaymentServices services;
  final String currency;

  @override
  State<_CustomerPaymentDialog> createState() => _CustomerPaymentDialogState();
}

class _CustomerPaymentDialogState extends State<_CustomerPaymentDialog> {
  // What they owe, as a starting point: most repayments settle the account.
  late final TextEditingController _amount = TextEditingController(
    text: widget.customer.owedMinor > 0
        ? _typedAmount(widget.customer.owedMinor)
        : '',
  );
  CheckoutTender? _tender;
  String? _amountError;
  String? _error;
  bool _busy = false;

  /// One request per payment being recorded, so a second press records the
  /// same payment rather than a second one.
  final String _requestId = secureCustomerPaymentRequestId();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  int? get _typedAmountMinor {
    try {
      return tenantCatalogPriceMinorUnits(_amount.text);
    } on TenantCatalogManagementException {
      return null;
    }
  }

  Future<void> _confirm() async {
    final amount = _typedAmountMinor;
    if (amount == null || amount <= 0) {
      setState(() => _amountError = 'Enter the amount paid, like 500.');
      return;
    }
    final tender = _tender;
    if (tender == null) {
      setState(() => _error = 'Say how they paid.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final binding = await widget.services.shifts.bindCheckoutShift(
        widget.session,
      );
      final shift = binding.attribution;
      if (shift == null) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = CheckoutRefusal.forCode(
            binding.refusalCode ?? 'no_open_shift',
          ).message;
        });
        return;
      }
      final intent = TenantCustomerPaymentIntent.build(
        session: widget.session,
        customer: widget.customer,
        amountMinor: amount,
        tender: tender,
        shift: shift,
        requestId: _requestId,
      );
      await widget.services.writer.recordPayment(intent);
      if (!mounted) return;
      Navigator.of(context).pop(
        AppNotice.confirmed(
          '${widget.currency} ${moneyTextOfMinor(amount)} from '
          '${widget.customer.name} recorded in your shift. Their balance '
          'moves when it reaches the server.',
        ),
      );
    } on TenantCustomerPaymentException catch (error, stackTrace) {
      AppTelemetry.captureHandled(error, stackTrace);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = switch (error.code) {
          'invalid_payment_amount' => 'That amount is more than one payment '
              'can be.',
          _ => 'This payment could not be recorded here.',
        };
      });
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(error, stackTrace);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            'This payment could not be saved on this device, so nothing was '
            'recorded. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final customer = widget.customer;
    final currency = widget.currency;
    final owes = customer.balanceMinor > 0
        ? '${customer.name} owes $currency '
              '${moneyTextOfMinor(customer.balanceMinor)}.'
        : customer.balanceMinor < 0
        ? '${customer.name} is $currency '
              '${moneyTextOfMinor(-customer.balanceMinor)} ahead.'
        : '${customer.name} owes nothing.';
    return AppDialog(
      title: 'Record a payment',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            key: const ValueKey('customer-payment-owes'),
            owes,
            style: tokens.density
                .body(tokens.typography)
                .copyWith(color: tokens.colors.text.secondary),
          ),
          SizedBox(height: tokens.spacing.s16),
          AppTextField(
            key: const ValueKey('customer-payment-amount'),
            controller: _amount,
            enabled: !_busy,
            label: 'Amount paid',
            leading: Icons.payments_outlined,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            error: _amountError,
            onChanged: (_) => setState(() => _amountError = null),
          ),
          SizedBox(height: tokens.spacing.s12),
          FilterChipBar<CheckoutTender>(
            semanticLabel: 'How they paid',
            selected: _tender,
            onSelected: (value) => setState(() {
              _tender = value;
              _error = null;
            }),
            options: <FilterChipOption<CheckoutTender>>[
              for (final option in CheckoutTender.values)
                FilterChipOption<CheckoutTender>(
                  key: ValueKey('customer-payment-${option.wireValue}'),
                  value: option,
                  label: option.label,
                ),
            ],
          ),
          SizedBox(height: tokens.spacing.s8),
          Text(
            'It goes into your shift, so your drawer is expected to hold it '
            'when you count it.',
            style: tokens.typography.caption.copyWith(
              color: tokens.colors.text.tertiary,
            ),
          ),
          if (_error case final message?) ...<Widget>[
            SizedBox(height: tokens.spacing.s12),
            Callout(
              key: const ValueKey('customer-payment-error'),
              status: AppStatus.problem,
              message: message,
            ),
          ],
        ],
      ),
      actions: <Widget>[
        AppButton(
          key: const ValueKey('customer-payment-cancel'),
          label: 'Cancel',
          tier: AppButtonTier.secondary,
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
        AppButton(
          key: const ValueKey('customer-payment-confirm'),
          label: 'Record payment',
          tier: AppButtonTier.primary,
          loading: _busy,
          onPressed: _busy ? null : _confirm,
        ),
      ],
    );
  }

  static String _typedAmount(int minorUnits) {
    final major = minorUnits ~/ 100;
    final minor = minorUnits % 100;
    return minor == 0 ? '$major' : '$major.${minor.toString().padLeft(2, '0')}';
  }
}
