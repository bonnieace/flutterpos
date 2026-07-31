import '../checkout/checkout_outbox.dart';
import '../tenancy/tenant_id.dart';

/// Raised when local sale evidence cannot be summarized for a shift.
final class ShiftSalesLedgerException implements Exception {
  const ShiftSalesLedgerException(this.code);

  final String code;

  @override
  String toString() => 'ShiftSalesLedgerException($code)';
}

/// The largest shift total this device will ever claim, in minor units.
const int maximumShiftSalesMinor = 1000000000000;

/// What this device can prove about the sales recorded during one shift.
///
/// [transactionCount] and [totalMinor] cover only sales the server has already
/// acknowledged, because those are exactly the sales nightly reconciliation
/// will aggregate. [unsettledCount] is every local sale for the shift that is
/// not yet confirmed; while it is non-zero the device cannot describe the shift
/// completely and must not write a closing summary.
final class ShiftSalesSummary {
  const ShiftSalesSummary({
    required this.transactionCount,
    required this.totalMinor,
    required this.unsettledCount,
  });

  static const ShiftSalesSummary empty = ShiftSalesSummary(
    transactionCount: 0,
    totalMinor: 0,
    unsettledCount: 0,
  );

  final int transactionCount;
  final int totalMinor;
  final int unsettledCount;

  /// The major-unit mirror reconciliation compares against `totalSales`.
  double get totalSales => totalMinor / 100;

  bool get isComplete => unsettledCount == 0;
}

/// The narrow boundary the shift lifecycle uses to summarize its own sales.
abstract interface class ShiftSalesLedger {
  Future<ShiftSalesSummary> summarize({
    required String uid,
    required String tenantId,
    required String shiftId,
  });
}

/// Summarizes one shift from the encrypted local checkout outbox.
///
/// The outbox is the only local record of what this device sold, and a
/// confirmed record means an exact server sale carries the same payload hash.
/// Malformed evidence raises rather than being skipped: a silently dropped sale
/// would understate the shift total and turn a device defect into a permanent
/// reconciliation variance.
final class CheckoutOutboxShiftSalesLedger implements ShiftSalesLedger {
  const CheckoutOutboxShiftSalesLedger(this._outbox);

  final HiveCheckoutOutbox _outbox;

  @override
  Future<ShiftSalesSummary> summarize({
    required String uid,
    required String tenantId,
    required String shiftId,
  }) async {
    final safeShiftId = validateTenantDocumentId(
      shiftId,
      fieldName: 'shiftId',
    );
    final records = await _outbox.recordsForSession(
      uid: uid,
      tenantId: tenantId,
    );
    var transactionCount = 0;
    var totalMinor = 0;
    var unsettledCount = 0;
    for (final record in records) {
      final recordShiftId = record.payload['shiftId'];
      if (recordShiftId is! String || recordShiftId.isEmpty) {
        throw const ShiftSalesLedgerException('unattributed_local_sale');
      }
      if (recordShiftId != safeShiftId) continue;
      if (record.state != CheckoutOutboxState.confirmed) {
        unsettledCount += 1;
        continue;
      }
      final total = record.payload['totalMinor'];
      if (total is! int || total < 0 || total > maximumShiftSalesMinor) {
        throw const ShiftSalesLedgerException('malformed_local_sale');
      }
      totalMinor += total;
      transactionCount += 1;
      if (totalMinor > maximumShiftSalesMinor) {
        throw const ShiftSalesLedgerException('shift_total_out_of_range');
      }
    }
    return ShiftSalesSummary(
      transactionCount: transactionCount,
      totalMinor: totalMinor,
      unsettledCount: unsettledCount,
    );
  }
}
