import 'checkout_draft.dart';
import 'checkout_sale.dart';

/// What the till tells a cashier when a checkout draft is refused.
///
/// [CheckoutDraftService] refuses with a machine code, and the codes arrive
/// from four different places: the draft builder itself, the shift binder
/// (whose refusal is passed through verbatim), the receipt counters (rethrown
/// as a draft code), and the catalog cache. A cashier cannot act on any of
/// them, so every one is mapped here.
///
/// The distinction that matters is not severity but **who can clear it**. A
/// closed shift and a damaged receipt counter both stop the sale, but the first
/// is fixed at the till in seconds and the second must never be retried in a
/// loop: the counter is deliberately refused rather than restarted, because
/// restarting it would reissue a receipt number a committed sale already
/// carries. [cashierCanFix] carries that difference so the screen can offer a
/// retry only where retrying can succeed.
final class CheckoutRefusal {
  const CheckoutRefusal._(
    this.code,
    this.message, {
    required this.cashierCanFix,
  });

  /// Maps one refusal code raised while building a draft.
  factory CheckoutRefusal.forCode(String code) => switch (code) {
    // The session the draft was captured against.
    'no_selected_session' => const CheckoutRefusal._(
      'no_selected_session',
      'Choose a business before starting a sale.',
      cashierCanFix: true,
    ),
    'session_changed' => const CheckoutRefusal._(
      'session_changed',
      'The business changed while this sale was being saved, so nothing was '
          'saved. Start it again.',
      cashierCanFix: true,
    ),

    // The canonical open shift every sale is attributed to.
    'checkout_start_unavailable' => const CheckoutRefusal._(
      'checkout_start_unavailable',
      'This device could not read your shift, so a sale cannot be started. '
          'Try again in a moment.',
      cashierCanFix: true,
    ),
    'no_open_shift' => const CheckoutRefusal._(
      'no_open_shift',
      'Open a shift before selling.',
      cashierCanFix: true,
    ),
    'other_tenant_shift_open' => const CheckoutRefusal._(
      'other_tenant_shift_open',
      'You still have a shift open in another business on this device. Close '
          'that shift before selling here.',
      cashierCanFix: true,
    ),
    // **Kept for a refusal nothing raises any more.** Binding stopped
    // requiring a server-confirmed shift on 2026-09-05, because requiring one
    // meant a till that opened its shift offline could not sell at all. A
    // device still holding an old refusal in an outbox record must still be
    // able to word it.
    'shift_not_confirmed' => const CheckoutRefusal._(
      'shift_not_confirmed',
      'The server has not confirmed your shift yet. Wait for it to confirm, '
          'then start the sale again.',
      cashierCanFix: true,
    ),
    'shift_closed_pending' => const CheckoutRefusal._(
      'shift_closed_pending',
      'This shift is closed and its count is saved, so no new sale can be '
          'recorded on it. It reaches the server on its own, and a new shift '
          'can be opened once it has.',
      cashierCanFix: true,
    ),
    'shift_closing' => const CheckoutRefusal._(
      'shift_closing',
      'Your shift is being closed, so no new sale can be recorded on it.',
      cashierCanFix: true,
    ),
    // **A shift is the unit a day's takings are reconciled in**, so one left
    // running for days makes its own summary meaningless. Ending it needs no
    // network, which is what makes refusing here safe to do.
    'shift_expired' => const CheckoutRefusal._(
      'shift_expired',
      'Your shift has been open more than a day, so no new sale can be '
          'recorded on it. Count the cash and close it, then open a new one.',
      cashierCanFix: true,
    ),
    'invalid_shift_id' => const CheckoutRefusal._(
      'invalid_shift_id',
      'This device holds an unusable shift reference, so a sale cannot be '
          'filed against it. Ask for help before selling.',
      cashierCanFix: false,
    ),
    'shift_binding_mismatch' => const CheckoutRefusal._(
      'shift_binding_mismatch',
      'Your shift does not match this cashier, business, or device, so a sale '
          'cannot be filed against it. Ask for help before selling.',
      cashierCanFix: false,
    ),

    // The offline product catalog the prices are taken from.
    'catalog_cache_unavailable' => const CheckoutRefusal._(
      'catalog_cache_unavailable',
      'This device has no product list for this business yet. Connect to sync '
          'the products, then start the sale again.',
      cashierCanFix: true,
    ),
    'unknown_product' => const CheckoutRefusal._(
      'unknown_product',
      'One of these items is no longer in the product list for this '
          'business. Remove it and start the sale again.',
      cashierCanFix: true,
    ),
    // The catalog price does not convert to exact minor units. Rounding it
    // would record a sale that disagrees with the catalog, so it is refused.
    'price_not_representable' => const CheckoutRefusal._(
      'price_not_representable',
      'One of these items has a price this register cannot record exactly. Ask a '
          'manager to correct the price.',
      cashierCanFix: false,
    ),

    // The requested cart.
    'invalid_line_count' => const CheckoutRefusal._(
      'invalid_line_count',
      'A sale needs between 1 and 16 items.',
      cashierCanFix: true,
    ),
    'duplicate_product' => const CheckoutRefusal._(
      'duplicate_product',
      'The same product appears twice. Combine it into one line with the full '
          'quantity.',
      cashierCanFix: true,
    ),
    'invalid_quantity' => const CheckoutRefusal._(
      'invalid_quantity',
      'Every item needs a whole quantity of at least 1.',
      cashierCanFix: true,
    ),
    'invalid_discount' => const CheckoutRefusal._(
      'invalid_discount',
      'The discount cannot be negative or larger than the sale.',
      cashierCanFix: true,
    ),
    // The draft builder re-prices every line from the cache, so a listed
    // price that changed since the cart was drawn can put the agreed total at
    // or above the new listed one. The cashier agrees it again.
    'agreed_price_out_of_range' => const CheckoutRefusal._(
      'agreed_price_out_of_range',
      'The agreed price must be more than nothing and less than the listed '
          'total. The listed prices may have just changed on this device: '
          'agree the price again.',
      cashierCanFix: true,
    ),
    'agreed_price_reason_required' => const CheckoutRefusal._(
      'agreed_price_reason_required',
      'Say why the price was agreed, in at least '
          '$minimumCheckoutDiscountReasonLength characters, before saving.',
      cashierCanFix: true,
    ),
    'credit_requires_customer' => const CheckoutRefusal._(
      'credit_requires_customer',
      'Choose who the sale is for before putting it on credit.',
      cashierCanFix: true,
    ),
    'credit_with_tender' => const CheckoutRefusal._(
      'credit_with_tender',
      'Choose either a payment method or credit, not both.',
      cashierCanFix: true,
    ),
    'credit_paid_out_of_range' => const CheckoutRefusal._(
      'credit_paid_out_of_range',
      'What is paid now must be less than the total. If they are paying it '
          'all, choose how they paid instead of credit.',
      cashierCanFix: true,
    ),
    'credit_paid_tender_required' => const CheckoutRefusal._(
      'credit_paid_tender_required',
      'Say how the part paid now was paid.',
      cashierCanFix: true,
    ),
    'invalid_product_id' => const CheckoutRefusal._(
      'invalid_product_id',
      'One of these items has an unusable product reference and cannot be '
          'sold. Ask for help.',
      cashierCanFix: false,
    ),

    // Durable local state this device cannot sell without.
    'invalid_business_date' => const CheckoutRefusal._(
      'invalid_business_date',
      'This device could not work out the business date for today. '
          'Check the clock and date on this device before selling.',
      cashierCanFix: false,
    ),
    'invalid_checkout_id' => const CheckoutRefusal._(
      'invalid_checkout_id',
      'This device could not create a usable sale reference. Ask for help '
          'before selling.',
      cashierCanFix: false,
    ),
    'draft_contract_violation' => const CheckoutRefusal._(
      'draft_contract_violation',
      'This sale did not pass the checks this register applies, so nothing was '
          'saved. Ask for help before selling.',
      cashierCanFix: false,
    ),
    'device_identity_unavailable' => const CheckoutRefusal._(
      'device_identity_unavailable',
      'The identity of this device could not be read, so it cannot number a '
          'receipt. Ask for help before selling.',
      cashierCanFix: false,
    ),
    // Reinstalling would issue a new identity and restart the receipt
    // sequence, so the warning about unsynced sales is not optional advice.
    'malformed_device_identity' => const CheckoutRefusal._(
      'malformed_device_identity',
      'The stored identity of this device is damaged, so it cannot number a '
          'receipt. Ask for help, and do not reinstall until the sales already '
          'stored on it have synced.',
      cashierCanFix: false,
    ),
    'receipt_sequence_exhausted' => const CheckoutRefusal._(
      'receipt_sequence_exhausted',
      'This device has issued every receipt number available for today. It can '
          'sell again once the business day rolls over.',
      cashierCanFix: false,
    ),
    'malformed_receipt_counter' => const CheckoutRefusal._(
      'malformed_receipt_counter',
      'The receipt counter on this device is damaged. Selling is stopped '
          'rather than risk printing a receipt number an existing sale already '
          'carries. Ask for help.',
      cashierCanFix: false,
    ),
    // Raised when the encrypted boxes are opened rather than while drafting, so
    // it normally surfaces at startup. It is mapped anyway: a cashier who does
    // reach it needs a sentence, not a code.
    'invalid_encryption_key' => const CheckoutRefusal._(
      'invalid_encryption_key',
      'The secure checkout storage on this device could not be opened. Ask '
          'help; the sales already stored on it are not lost.',
      cashierCanFix: false,
    ),

    // An unrecognised code fails closed. Promising a retry for something this
    // build does not understand is how a till ends up in a refusal loop.
    _ => CheckoutRefusal._(
      code,
      'This sale could not be saved on this device. Try again, and ask for '
      'help if it keeps happening.',
      cashierCanFix: false,
    ),
  };

  /// Maps whatever [CheckoutDraftService.createDraft] threw.
  ///
  /// A failure that is not a [CheckoutDraftException] - a storage fault, say -
  /// must still reach the cashier as a sentence rather than as a crash.
  factory CheckoutRefusal.forError(Object error) => CheckoutRefusal.forCode(
    error is CheckoutDraftException ? error.code : 'unknown_error',
  );

  /// The machine code, retained for diagnostics and never displayed.
  final String code;

  /// The sentence shown at the till.
  final String message;

  /// Whether the person at the till can clear this themselves right now.
  ///
  /// False means retrying cannot succeed until somebody intervenes, so the
  /// screen must not offer a retry that is guaranteed to fail again.
  final bool cashierCanFix;
}
