import 'checkout_draft.dart';

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
    'shift_not_confirmed' => const CheckoutRefusal._(
      'shift_not_confirmed',
      'The server has not confirmed your shift yet. Wait for it to confirm, '
          'then start the sale again.',
      cashierCanFix: true,
    ),
    'shift_closing' => const CheckoutRefusal._(
      'shift_closing',
      'Your shift is being closed, so no new sale can be recorded on it.',
      cashierCanFix: true,
    ),
    // A shift from another business day could never be reconciled against this
    // sale, so the shift is ended rather than the sale re-dated.
    'shift_business_date_mismatch' => const CheckoutRefusal._(
      'shift_business_date_mismatch',
      'Your shift belongs to an earlier business day, so a sale today could '
          'never be balanced against it. Close that shift and open a new one.',
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
      'One of these items has a price this till cannot record exactly. Ask a '
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
      'This sale did not pass the checks this till applies, so nothing was '
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
