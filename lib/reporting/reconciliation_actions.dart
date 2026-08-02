import 'reconciliation_request.dart';

/// The write capabilities the reconciliation status route may be granted.
///
/// The composition root supplies these; the reporting surface only passes them
/// through. Whatever is absent stays unavailable, so a route with no actions at
/// all is exactly the read-only explanation it was before.
final class TenantReconciliationActions {
  const TenantReconciliationActions({this.requestCallable});

  /// Asks the server to reconcile this business. Owner and administrator only,
  /// which the callable itself enforces; nothing here can retry, cancel, or
  /// re-order the work the reconciliation runners own.
  final RequestReconciliationCallable? requestCallable;
}
