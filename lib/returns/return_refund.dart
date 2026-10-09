/// Money handed back over the counter for a return, and the drawer it left.
///
/// **The other half of a return, missing until 2026-10-09.** A return records
/// what came back and is valued against its sale; it never said what money went
/// out, or from which till. So the drawer that paid was counted short by every
/// refund it handed over - on the shift's own history row and in nightly
/// reconciliation alike - while the Returns screen told the same cashier the
/// money was "already off the takings".
///
/// **Its own day and its own shift, not the sale's.** A return nets the day its
/// sale traded; a refund leaves the drawer open where the customer stood, which
/// for last week's goods is this morning's. So a refund names the shift that
/// paid it and that shift's trading day, and nightly reconciliation reads it by
/// that day.
library;

import '../checkout/checkout_tender.dart';
import '../tenancy/tenant_id.dart';
import 'return_history.dart';

/// What one return handed back, from which drawer.
final class TenantReturnRefund {
  const TenantReturnRefund({
    required this.amountMinor,
    required this.tender,
    required this.shiftId,
    required this.businessDate,
  });

  /// What was handed over, in the sale's currency. Always above zero: a return
  /// that handed nothing back records no refund at all.
  final int amountMinor;

  /// How it was handed over, which is the part of the drawer it came out of.
  final CheckoutTender tender;

  /// The recorder's own shift - the drawer the money left.
  final String shiftId;

  /// That shift's trading day, which is the day reconciliation takes it off.
  final String businessDate;

  /// The four fields the create rule accepts together or not at all.
  Map<String, Object?> documentFields() => <String, Object?>{
    'refundMinor': amountMinor,
    'refundTender': tender.wireValue,
    'refundShiftId': shiftId,
    'refundBusinessDate': businessDate,
  };

  /// The refund a stored return records, or null when it records none.
  ///
  /// **Half a refund is refused, not read as none.** Rules accept all four
  /// fields or no field, so a document holding some of them was not written
  /// by this app, and quietly reading it as "nothing handed back" would put
  /// money back into a drawer that paid it out.
  static TenantReturnRefund? fromFields(Map<String, Object?> data) {
    const keys = <String>[
      'refundMinor',
      'refundTender',
      'refundShiftId',
      'refundBusinessDate',
    ];
    final present = keys.where(data.containsKey).length;
    if (present == 0) return null;
    final amount = data['refundMinor'];
    final tender = CheckoutTender.tryParse(data['refundTender']);
    final shiftId = data['refundShiftId'];
    final businessDate = data['refundBusinessDate'];
    if (present != keys.length ||
        amount is! int ||
        amount <= 0 ||
        tender == null ||
        shiftId is! String ||
        businessDate is! String ||
        !_businessDatePattern.hasMatch(businessDate)) {
      throw const TenantReturnException('invalid_return_refund');
    }
    try {
      validateTenantDocumentId(shiftId, fieldName: 'refundShiftId');
    } on ArgumentError {
      throw const TenantReturnException('invalid_return_refund');
    }
    return TenantReturnRefund(
      amountMinor: amount,
      tender: tender,
      shiftId: shiftId,
      businessDate: businessDate,
    );
  }
}

final RegExp _businessDatePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
