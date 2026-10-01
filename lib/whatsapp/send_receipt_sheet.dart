/// *Send on WhatsApp*: one sale's receipt to one number, asked for by a cashier.
///
/// **For the customer standing there.** It opens on their number when the sale
/// named a customer who has one, and on an empty number otherwise, and asking
/// for it is the customer's consent to that one receipt - so the sheet says to
/// send it only when they asked.
///
/// **Promised now, sent when it can be.** The request is queued on this device
/// and the server sends it once both the request and the sale have reached it,
/// so a till with no signal can still tell the customer it is coming.
library;

import 'package:flutter/material.dart';

import '../observability/app_telemetry.dart';
import '../tenancy/tenancy.dart';
import '../ui/buttons.dart';
import '../ui/fields.dart';
import '../ui/sheet.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'receipt_delivery.dart';

/// Opens the sheet, answering with the notice to show once it closes, or null
/// when it was cancelled.
Future<AppNotice?> showSendWhatsappReceiptSheet(
  BuildContext context, {
  required TenantSession session,
  required TenantWhatsappReceiptWriter writer,
  required String saleId,
  required String receiptLabel,
  required DialCode dialCode,
  String? customerName,
  String? customerPhone,
}) => showAppSheet<AppNotice>(
  context,
  builder: (sheetContext, scrollController) => _SendReceiptSheet(
    session: session,
    writer: writer,
    saleId: saleId,
    receiptLabel: receiptLabel,
    dialCode: dialCode,
    customerName: customerName,
    customerPhone: customerPhone,
    scrollController: scrollController,
    onCompleted: (notice) => Navigator.of(sheetContext).pop(notice),
    onCancel: () => Navigator.of(sheetContext).pop(),
  ),
);

final class _SendReceiptSheet extends StatefulWidget {
  const _SendReceiptSheet({
    required this.session,
    required this.writer,
    required this.saleId,
    required this.receiptLabel,
    required this.dialCode,
    required this.customerName,
    required this.customerPhone,
    required this.scrollController,
    required this.onCompleted,
    required this.onCancel,
  });

  final TenantSession session;
  final TenantWhatsappReceiptWriter writer;
  final String saleId;
  final String receiptLabel;
  final DialCode dialCode;
  final String? customerName;
  final String? customerPhone;
  final ScrollController scrollController;
  final ValueChanged<AppNotice> onCompleted;
  final VoidCallback onCancel;

  @override
  State<_SendReceiptSheet> createState() => _SendReceiptSheetState();
}

class _SendReceiptSheetState extends State<_SendReceiptSheet> {
  late final ({DialCode dialCode, String localNumber})? _stored = splitE164(
    widget.customerPhone,
  );
  late DialCode _dialCode = _stored?.dialCode ?? widget.dialCode;
  late final TextEditingController _phone = TextEditingController(
    text: _stored?.localNumber ?? '',
  );
  bool _busy = false;
  String? _phoneError;
  String? _error;

  /// One request per sheet, so a second press is the same receipt.
  late final String _requestId = secureWhatsappReceiptRequestId();

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final defect = phoneNumberDefect(
      dialCode: _dialCode,
      localNumber: _phone.text,
    );
    if (defect != null) {
      setState(() => _phoneError = defect);
      return;
    }
    final phone = normalizeE164(dialCode: _dialCode, localNumber: _phone.text);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final intent = TenantWhatsappReceiptIntent.build(
        session: widget.session,
        saleId: widget.saleId,
        phone: phone,
        customerName: widget.customerName,
        requestId: _requestId,
      );
      await widget.writer.send(intent);
      if (!mounted) return;
      final masked = '${phone.substring(0, 4)} ••• ${phone.substring(phone.length - 3)}';
      widget.onCompleted(
        AppNotice.confirmed(
          'Receipt ${widget.receiptLabel} is on its way to $masked on '
          'WhatsApp. It goes as soon as the sale reaches the server.',
        ),
      );
    } on TenantWhatsappReceiptException catch (error, stackTrace) {
      AppTelemetry.captureHandled(error, stackTrace, boundary: 'whatsapp.send');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.code == 'invalid_phone'
            ? 'That does not look like a mobile number.'
            : 'This receipt could not be sent from here.';
      });
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(error, stackTrace, boundary: 'whatsapp.send');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            'This could not be saved on this device, so nothing was sent. '
            'Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return ListView(
      key: const ValueKey('send-receipt-sheet'),
      controller: widget.scrollController,
      padding: EdgeInsets.all(tokens.spacing.s24),
      children: <Widget>[
        Text(
          'Send on WhatsApp',
          style: tokens.typography.titleMedium.copyWith(
            color: tokens.colors.text.primary,
          ),
        ),
        SizedBox(height: tokens.spacing.s8),
        Text(
          widget.customerName == null
              ? 'Receipt ${widget.receiptLabel}. Send it only if the customer '
                    'asked for it.'
              : 'Receipt ${widget.receiptLabel} for ${widget.customerName}. '
                    'Send it only if they asked for it.',
          style: tokens.typography.caption.copyWith(
            color: tokens.colors.text.tertiary,
          ),
        ),
        SizedBox(height: tokens.spacing.s24),
        AppPhoneField(
          key: const ValueKey('send-receipt-phone'),
          label: 'Their WhatsApp number',
          error: _phoneError,
          enabled: !_busy,
          code: _dialCode.code,
          codes: <AppSelectItem<String>>[
            for (final code in dialCodes)
              AppSelectItem<String>(
                key: ValueKey('send-receipt-dial-${code.digits}'),
                value: code.code,
                label: '${code.country} (${code.code})',
              ),
          ],
          onCodeChanged: (value) => setState(() {
            _dialCode = dialCodes.firstWhere(
              (candidate) => candidate.code == value,
              orElse: () => _dialCode,
            );
            _phoneError = null;
          }),
          controller: _phone,
          onChanged: (_) {
            if (_phoneError != null) setState(() => _phoneError = null);
          },
        ),
        if (_error case final message?) ...<Widget>[
          SizedBox(height: tokens.spacing.s12),
          Callout(
            key: const ValueKey('send-receipt-error'),
            status: AppStatus.problem,
            message: message,
          ),
        ],
        SizedBox(height: tokens.spacing.s32),
        AppButton(
          key: const ValueKey('send-receipt-submit'),
          label: 'Send receipt',
          icon: Icons.send_outlined,
          tier: AppButtonTier.secondary,
          loading: _busy,
          expand: true,
          onPressed: _busy ? null : _send,
        ),
        SizedBox(height: tokens.spacing.s12),
        AppButton(
          key: const ValueKey('send-receipt-cancel'),
          label: 'Cancel',
          expand: true,
          onPressed: _busy ? null : widget.onCancel,
        ),
      ],
    );
  }
}
