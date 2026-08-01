import 'return_request.dart';
import 'return_verification.dart';

/// The write capabilities the returns route may be granted.
///
/// The composition root supplies these; tenancy, shift, and sales code only
/// pass them through. Whatever is absent stays unavailable, so a route with no
/// actions at all is exactly the read-only surface it was before.
final class TenantReturnActions {
  const TenantReturnActions({this.writer, this.verifyCallable});

  /// Records a pending return. Available to every active member, because
  /// recording changes no stock.
  final TenantReturnWriter? writer;

  /// Verifies a pending return and restores its stock. Management-only, which
  /// the callable itself enforces; the two capabilities are deliberately
  /// separate so recording and restoring stay a two-person control.
  final VerifyReturnCallable? verifyCallable;
}
