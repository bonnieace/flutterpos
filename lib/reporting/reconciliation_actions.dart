import 'reconciliation_request.dart';
import 'shift_amendment.dart';

/// The write capabilities the reconciliation surfaces may be granted.
///
/// The composition root supplies these; the reporting surfaces only pass them
/// through. Whatever is absent stays unavailable, so a route with no actions at
/// all is exactly the read-only explanation it was before.
final class TenantReconciliationActions {
  const TenantReconciliationActions({
    this.requestCallable,
    this.amendShiftSummaryCallable,
  });

  /// Asks the server to reconcile this business. Owner and administrator only,
  /// which the callable itself enforces; nothing here can retry, cancel, or
  /// re-order the work the reconciliation runners own.
  final RequestReconciliationCallable? requestCallable;

  /// Corrects one closed shift's summary to the total its own sales prove.
  /// Owner and administrator only, which the callable itself enforces; nothing
  /// here can choose the corrected figure, and the counted cash is never
  /// written.
  final AmendShiftSummaryCallable? amendShiftSummaryCallable;
}
