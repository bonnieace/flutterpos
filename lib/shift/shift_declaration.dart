import '../checkout/checkout_tender.dart';

/// The largest amount a close may record for one payment method, in minor units.
///
/// It bounds each declared figure *and* their sum, so a declaration can never
/// carry a total no single field could have held.
const int maximumShiftCashMinor = 1000000000000;

/// What a cashier says the till holds, by payment method, at close.
///
/// **This is a statement, not a derivation.** Nothing here is computed from
/// sale evidence and nothing here is compared against it on the device: the
/// cashier is shown no expected figure and no shift total while they type, so
/// what they enter is what they counted rather than what they were told to
/// expect. Reconciliation makes the comparison later, from the sales the server
/// already holds - see the shift verifier in `functions/src/reconciliation`.
///
/// **All three or none.** A partial declaration is not a smaller truth, it is a
/// different figure wearing the same label: two methods declared and one absent
/// would present the missing one as zero to every reader downstream. The type
/// has no way to express a partial one, and the durable record refuses one.
///
/// The declaration is the app's only chance to record a true tender split. A
/// sale carries the method the till was told at the moment of payment, which
/// nothing later corrects: some payments are settled after the sale, and there
/// is no way to edit a sale's tender. So the split derived from sale documents
/// is this app's belief, and this is the person who knows.
final class ShiftTenderDeclaration {
  const ShiftTenderDeclaration._({
    required this.cashMinor,
    required this.mpesaMinor,
    required this.cardMinor,
  });

  /// Builds a declaration, or `null` where any figure is out of range.
  ///
  /// Returning `null` rather than raising is deliberate: every caller is either
  /// a form that must say which box is wrong or a decoder that must refuse a
  /// document, and neither wants an exception to carry that.
  static ShiftTenderDeclaration? tryParse({
    required int cash,
    required int mpesa,
    required int card,
  }) {
    for (final figure in <int>[cash, mpesa, card]) {
      if (figure < 0 || figure > maximumShiftCashMinor) return null;
    }
    // Checked on the sum as well as the parts, because three figures each
    // inside the bound can still add to one that is not - and the total is what
    // every report of this declaration is read against.
    if (cash + mpesa + card > maximumShiftCashMinor) return null;
    return ShiftTenderDeclaration._(
      cashMinor: cash,
      mpesaMinor: mpesa,
      cardMinor: card,
    );
  }

  /// A declaration of nothing, which is a real answer a till may give.
  static const ShiftTenderDeclaration zero = ShiftTenderDeclaration._(
    cashMinor: 0,
    mpesaMinor: 0,
    cardMinor: 0,
  );

  final int cashMinor;
  final int mpesaMinor;
  final int cardMinor;

  /// What this declaration says the shift took in all, in minor units.
  ///
  /// Derived rather than stored, here and in the shift document: a stored sum
  /// is one more figure that can come to disagree with its parts.
  int get totalMinor => cashMinor + mpesaMinor + cardMinor;

  /// Whether every method was declared as nothing.
  bool get isZero => totalMinor == 0;

  /// The figure declared for one payment method.
  int minorFor(CheckoutTender tender) => switch (tender) {
    CheckoutTender.cash => cashMinor,
    CheckoutTender.mpesa => mpesaMinor,
    CheckoutTender.card => cardMinor,
  };

  @override
  bool operator ==(Object other) =>
      other is ShiftTenderDeclaration &&
      other.cashMinor == cashMinor &&
      other.mpesaMinor == mpesaMinor &&
      other.cardMinor == cardMinor;

  @override
  int get hashCode => Object.hash(cashMinor, mpesaMinor, cardMinor);

  @override
  String toString() =>
      'ShiftTenderDeclaration(cash: $cashMinor, mpesa: $mpesaMinor, '
      'card: $cardMinor)';
}
