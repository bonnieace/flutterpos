/// *Send by email*: one sale's receipt to one address, asked for by a cashier.
///
/// *Send on WhatsApp*'s sheet (`lib/whatsapp/send_receipt_sheet.dart`) with an
/// address instead of a number: it opens on the customer's email when the sale
/// named a customer who has one, asking for it is the customer's consent to
/// that one receipt, and the request is queued on this device and sent once it
/// and the sale have both reached the server.
library;

import 'package:flutter/material.dart';

import '../observability/app_telemetry.dart';
import '../tenancy/tenancy.dart';
import '../ui/buttons.dart';
import '../ui/fields.dart';
import '../ui/sheet.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'email_receipt_delivery.dart';

/// Opens the sheet, answering with the notice to show once it closes, or null
/// when it was cancelled.
Future<AppNotice?> showSendEmailReceiptSheet(
  BuildContext context, {
  required TenantSession session,
  required TenantEmailReceiptWriter writer,
  required String saleId,
  required String receiptLabel,
  String? customerName,
  String? customerEmail,
}) => showAppSheet<AppNotice>(
  context,
  builder: (sheetContext, scrollController) => _SendEmailReceiptSheet(
    session: session,
    writer: writer,
    saleId: saleId,
    receiptLabel: receiptLabel,
    customerName: customerName,
    customerEmail: customerEmail,
    scrollController: scrollController,
    onCompleted: (notice) => Navigator.of(sheetContext).pop(notice),
    onCancel: () => Navigator.of(sheetContext).pop(),
  ),
);

/// `j•••@gmail.com`, as the server masks it - for the notice, which another
/// customer at the counter may read over the cashier's shoulder.
String maskReceiptEmail(String email) {
  final at = email.lastIndexOf('@');
  if (at < 1) return '•••';
  return '${email.substring(0, 1)}•••${email.substring(at)}';
}

final class _SendEmailReceiptSheet extends StatefulWidget {
  const _SendEmailReceiptSheet({
    required this.session,
    required this.writer,
    required this.saleId,
    required this.receiptLabel,
    required this.customerName,
    required this.customerEmail,
    required this.scrollController,
    required this.onCompleted,
    required this.onCancel,
  });

  final TenantSession session;
  final TenantEmailReceiptWriter writer;
  final String saleId;
  final String receiptLabel;
  final String? customerName;
  final String? customerEmail;
  final ScrollController scrollController;
  final ValueChanged<AppNotice> onCompleted;
  final VoidCallback onCancel;

  @override
  State<_SendEmailReceiptSheet> createState() => _SendEmailReceiptSheetState();
}

class _SendEmailReceiptSheetState extends State<_SendEmailReceiptSheet> {
  late final TextEditingController _email = TextEditingController(
    text: widget.customerEmail ?? '',
  );
  bool _busy = false;
  String? _emailError;
  String? _error;

  /// One request per sheet, so a second press is the same receipt.
  late final String _requestId = secureEmailReceiptRequestId();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final address = normalizeReceiptEmail(_email.text);
    if (address == null) {
      setState(
        () => _emailError = 'That email address is not one mail can reach.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final intent = TenantEmailReceiptIntent.build(
        session: widget.session,
        saleId: widget.saleId,
        email: address,
        customerName: widget.customerName,
        requestId: _requestId,
      );
      await widget.writer.send(intent);
      if (!mounted) return;
      widget.onCompleted(
        AppNotice.confirmed(
          'Receipt ${widget.receiptLabel} is on its way to '
          '${maskReceiptEmail(address)}. It goes as soon as the sale reaches '
          'the server.',
        ),
      );
    } on TenantEmailReceiptException catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'email_receipt.send',
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.code == 'invalid_email'
            ? 'That email address is not one mail can reach.'
            : 'This receipt could not be sent from here.';
      });
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'email_receipt.send',
      );
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
      key: const ValueKey('send-email-receipt-sheet'),
      controller: widget.scrollController,
      padding: EdgeInsets.all(tokens.spacing.s24),
      children: <Widget>[
        Text(
          'Send by email',
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
        AppTextField(
          key: const ValueKey('send-email-receipt-address'),
          controller: _email,
          label: 'Their email address',
          leading: Icons.mail_outline,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.send,
          autocorrect: false,
          enableSuggestions: false,
          enabled: !_busy,
          error: _emailError,
          onChanged: (_) {
            if (_emailError != null) setState(() => _emailError = null);
          },
          onSubmitted: (_) {
            if (!_busy) _send();
          },
        ),
        if (_error case final message?) ...<Widget>[
          SizedBox(height: tokens.spacing.s12),
          Callout(
            key: const ValueKey('send-email-receipt-error'),
            status: AppStatus.problem,
            message: message,
          ),
        ],
        SizedBox(height: tokens.spacing.s32),
        AppButton(
          key: const ValueKey('send-email-receipt-submit'),
          label: 'Send receipt',
          icon: Icons.send_outlined,
          tier: AppButtonTier.secondary,
          loading: _busy,
          expand: true,
          onPressed: _busy ? null : _send,
        ),
        SizedBox(height: tokens.spacing.s12),
        AppButton(
          key: const ValueKey('send-email-receipt-cancel'),
          label: 'Cancel',
          expand: true,
          onPressed: _busy ? null : widget.onCancel,
        ),
      ],
    );
  }
}
