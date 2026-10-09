import '../checkout/checkout_draft.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import 'return_request.dart';
import 'return_verification.dart';

/// Finds the recorder's own open shift on this phone - or the refusal code
/// where there is none.
///
/// Given the session's controller as well as the session, because the binding
/// has to ask the server through that session's shift controller first: a
/// shift closed on another phone is still open in this phone's record until
/// something does. See `ServerCheckedShiftBinder`.
typedef TenantReturnShiftBinder =
    Future<CheckoutShiftBinding> Function(
      TenantSessionController sessions,
      TenantSession session,
    );

/// The write capabilities the returns route may be granted.
///
/// The composition root supplies these; tenancy, shift, and sales code only
/// pass them through. Whatever is absent stays unavailable, so a route with no
/// actions at all is exactly the read-only surface it was before.
final class TenantReturnActions {
  const TenantReturnActions({this.writer, this.verifyCallable, this.bindShift});

  /// Records a pending return. Available to every active member, because
  /// recording changes no stock.
  final TenantReturnWriter? writer;

  /// Verifies a pending return and restores its stock. Management-only, which
  /// the callable itself enforces; the two capabilities are deliberately
  /// separate so recording and restoring stay a two-person control.
  final VerifyReturnCallable? verifyCallable;

  /// The drawer money handed back for a return comes out of. Absent, the form
  /// records no refund at all, which is every return before 2026-10-09.
  final TenantReturnShiftBinder? bindShift;
}
