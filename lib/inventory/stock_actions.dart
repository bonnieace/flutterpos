import 'stock_adjustment.dart';

/// The write capabilities the product stock route may be granted.
///
/// The composition root supplies these; tenancy code only passes them through.
/// Whatever is absent stays unavailable, so a route with no actions at all is
/// exactly the read-only ledger it was before.
final class TenantStockActions {
  const TenantStockActions({this.adjustCallable});

  /// Adjusts one product's stock. Management-only, which the callable itself
  /// enforces; there is no cashier-facing stock mutation anywhere in the app.
  final AdjustStockCallable? adjustCallable;
}
