import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../checkout/checkout_tender.dart';
import '../returns/return_actions.dart';
import '../returns/return_history_panel.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session_controller.dart';
import 'receipt_lookup.dart';
import 'sale_history.dart';

/// Guarded receipt lookup route for the selected tenant session.
final class TenantReceiptLookupScreen extends StatelessWidget {
  const TenantReceiptLookupScreen({
    super.key,
    required this.reader,
    this.returnActions,
  });

  final TenantDataReader reader;

  /// Passed through to the returns route this lookup opens.
  final TenantReturnActions? returnActions;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Find a receipt')),
    body: TenantReceiptLookupPanel(
      reader: reader,
      returnActions: returnActions,
    ),
  );
}

/// Looks one receipt up behind [TenantRouteGuard].
///
/// The guard owns authorization and stale-session rejection: a tenant switch
/// during an outstanding lookup discards it before it can be rendered. The
/// panel owns only the submitted receipt.
final class TenantReceiptLookupPanel extends StatefulWidget {
  const TenantReceiptLookupPanel({
    super.key,
    required this.reader,
    this.returnActions,
  });

  final TenantDataReader reader;
  final TenantReturnActions? returnActions;

  @override
  State<TenantReceiptLookupPanel> createState() =>
      _TenantReceiptLookupPanelState();
}

final class _TenantReceiptLookupPanelState
    extends State<TenantReceiptLookupPanel> {
  final TextEditingController _receipt = TextEditingController();

  /// The exact receipt a lookup was submitted for. Nothing is read until one
  /// is submitted, so opening the route issues no query at all.
  String? _submitted;
  String? _rejection;

  @override
  void dispose() {
    _receipt.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _receipt.text.trim();
    try {
      // Refused here, before any read: a malformed receipt is a typing mistake,
      // not a query.
      final query = TenantReceiptQuery.parse(value);
      setState(() {
        _rejection = null;
        _submitted = query.receiptNumber;
      });
    } on TenantReceiptLookupException {
      setState(() {
        _rejection =
            'That is not a receipt number. A receipt reads like '
            'CT-A7F-20260731-0042.';
        _submitted = null;
      });
    }
  }

  /// One loader per submitted receipt, so a rebuild does not re-issue the read.
  TenantGuardedLoader<TenantReceiptLookupResult> _loaderFor(String receipt) {
    if (receipt == _loaderKey && _loader != null) return _loader!;
    _loaderKey = receipt;
    return _loader = (session) => TenantReceiptLookupRepository(
      session: session,
      reader: widget.reader,
    ).findByReceipt(receipt);
  }

  String? _loaderKey;
  TenantGuardedLoader<TenantReceiptLookupResult>? _loader;

  void _openReturns(BuildContext context, TenantSale sale) {
    final sessions = TenantSessionScope.read(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TenantSessionScope(
          controller: sessions,
          child: TenantSaleReturnsScreen(
            reader: widget.reader,
            request: TenantSaleReturnsRequest(sale: sale),
            actions: widget.returnActions,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('receipt-lookup'),
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Find a receipt',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 4),
      const Text(
        'Enter the receipt printed for the customer to open the sale it '
        'describes.',
      ),
      const SizedBox(height: 16),
      TextField(
        key: const ValueKey('receipt-lookup-input'),
        controller: _receipt,
        autocorrect: false,
        textCapitalization: TextCapitalization.characters,
        onSubmitted: (_) => _submit(),
        decoration: const InputDecoration(
          labelText: 'Receipt number',
          hintText: 'CT-A7F-20260731-0042',
        ),
      ),
      const SizedBox(height: 12),
      AppButton(
        key: const ValueKey('receipt-lookup-submit'),
        label: 'Find receipt',
        tier: AppButtonTier.primary,
        onPressed: _submit,
      ),
      if (_rejection case final message?) ...[
        const SizedBox(height: 16),
        Text(key: const ValueKey('receipt-lookup-invalid'), message),
      ],
      if (_submitted case final receipt?) ...[
        const SizedBox(height: 24),
        TenantRouteGuard<TenantReceiptLookupResult>(
          key: ValueKey('receipt:$receipt'),
          allowedRoles: TenantReceiptLookupRepository.allowedRoles,
          load: _loaderFor(receipt),
          denied: const Text(
            key: ValueKey('receipt-lookup-denied'),
            'Receipt lookup is unavailable for this business.',
          ),
          failure: (context, error) => const Text(
            key: ValueKey('receipt-lookup-failure'),
            'That receipt could not be looked up.',
          ),
          builder: (context, session, result) => _ReceiptLookupResult(
            result: result,
            onOpenReturns: (sale) => _openReturns(context, sale),
          ),
        ),
      ],
    ],
  );
}

final class _ReceiptLookupResult extends StatelessWidget {
  const _ReceiptLookupResult({
    required this.result,
    required this.onOpenReturns,
  });

  final TenantReceiptLookupResult result;
  final ValueChanged<TenantSale> onOpenReturns;

  @override
  Widget build(BuildContext context) {
    if (result.isMissing) {
      return const Text(
        key: ValueKey('receipt-lookup-missing'),
        'No sale in this business carries that receipt. Check the number, and '
        'remember a receipt belongs to the business that issued it.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (result.isAmbiguous)
          Text(
            key: const ValueKey('receipt-lookup-ambiguous'),
            // The device code is a three-character digest, so two devices can
            // share one. Picking a sale here would attribute a return to the
            // wrong till; reconciliation is the place that resolves it.
            '${result.matches.length} sales carry that receipt. Two devices '
            'share a receipt code, so open the one whose items and time match '
            'the customer, or ask a manager to reconcile them.',
          ),
        for (final sale in result.matches)
          Card(
            key: ValueKey('receipt-lookup-sale-${sale.id}'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sale.receiptNumber,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    key: ValueKey('receipt-lookup-total-${sale.id}'),
                    'Total: ${sale.currency} ${_money(sale.totalMinor)}',
                  ),
                  Text(
                    key: ValueKey('receipt-lookup-lines-${sale.id}'),
                    sale.lines
                        .map((line) => '${line.quantity} x ${line.name}')
                        .join(', '),
                  ),
                  Text(
                    key: ValueKey('receipt-lookup-tender-${sale.id}'),
                    _tenderLabel(sale),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    key: ValueKey('receipt-lookup-recorded-${sale.id}'),
                    _recordedLabel(sale),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AppButton(
                             key: ValueKey('receipt-lookup-returns-${sale.id}'),
                             label: 'View returns',
                             onPressed: () => onOpenReturns(sale),
                           ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// States how the sale was paid for without implying the payment was checked.
///
/// This lookup is the surface a return starts from, so the payment method is
/// operationally useful here - and precisely for that reason it must not read
/// as a settled transaction. Nothing has confirmed the money arrived.
String _tenderLabel(TenantSale sale) {
  final tender = sale.tender;
  return tender == null
      ? checkoutTenderUnrecordedMessage
      : 'Paid by ${tender.label}. $checkoutTenderDisclaimer';
}

String _recordedLabel(TenantSale sale) {
  final recordedAt = sale.recordedAt;
  return recordedAt == null
      ? 'The server has not confirmed this sale yet.'
      : 'Recorded ${_instant(recordedAt)} on ${sale.businessDate}';
}

String _money(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);

String _instant(DateTime value) {
  final utc = value.toUtc();
  String pad(int part) => part.toString().padLeft(2, '0');
  return '${utc.year}-${pad(utc.month)}-${pad(utc.day)} '
      '${pad(utc.hour)}:${pad(utc.minute)} UTC';
}
