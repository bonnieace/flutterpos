/// How a customer paid, as the cashier asserted it at the point of sale.
///
/// This is deliberately not a verified payment. Nothing in this app authorizes
/// a card, queries an M-Pesa STK push, or reconciles a provider statement, so
/// the recorded value is evidence of what the cashier selected and of nothing
/// else. Every surface that displays it must say so; [checkoutTenderDisclaimer]
/// is the one sentence that does, so the claim cannot drift between screens.
///
/// Wire values are lowercase and match the exact strings Firestore Rules
/// constrain a schema v2 sale to. Decoding is strict: casing, whitespace, and
/// unknown values are refused rather than coerced, because a tender nobody
/// modelled is not evidence of a payment method at all.
enum CheckoutTender {
  cash('cash', 'Cash'),
  mpesa('mpesa', 'M-Pesa'),
  card('card', 'Card');

  const CheckoutTender(this.wireValue, this.label);

  /// The exact stored string. Never derived from [name] or [label].
  final String wireValue;

  /// The customer-facing name of the payment method.
  final String label;

  /// Parses a stored tender, or returns null when the value is not modelled.
  ///
  /// Callers decide what an unrecognised value means for their surface. A read
  /// model refuses the document; nothing displays an unmodelled tender.
  static CheckoutTender? tryParse(Object? value) => switch (value) {
    'cash' => CheckoutTender.cash,
    'mpesa' => CheckoutTender.mpesa,
    'card' => CheckoutTender.card,
    _ => null,
  };

  String toJson() => wireValue;
}

/// The exact values a schema v2 sale may record, in the frozen wire form.
const List<String> checkoutTenderWireValues = <String>['cash', 'mpesa', 'card'];

/// The one sentence every surface uses when it shows a recorded tender.
///
/// The product decision recorded in PLAN.md is that the tender is the cashier's
/// assertion about how the customer paid. Displaying it without this would
/// imply the money arrived, which nothing here has checked.
const String checkoutTenderDisclaimer =
    'Recorded by the cashier at the register; the payment itself is not verified.';

/// What a surface says about a sale that recorded no tender at all.
///
/// **Two sales reach this sentence and it is true of both.** A schema v1 sale
/// predates the tender field entirely; a current sale gets here when the
/// cashier saved without saying how the customer paid. Either way this is a
/// statement about the record rather than about the payment, and neither is
/// ever presented as an unpaid sale.
const String checkoutTenderUnrecordedMessage =
    'This sale names no payment method. Either it was recorded before payment '
    'methods were captured, or nobody said how the customer paid.';
