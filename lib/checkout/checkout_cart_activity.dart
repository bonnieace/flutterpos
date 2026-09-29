/// Whether a till on this device is holding a sale it has not saved yet.
///
/// **For whatever would take the screen from a cashier mid-sale.** A Play
/// update restarts the app, and a cart exists only in memory until it is
/// saved, so the update waits for a till with nothing on it. A saved sale is
/// already in the outbox and is not what this watches.
///
/// **Held per till, not as one flag.** A till reports as itself, so a second
/// one closing with an empty cart cannot clear a sale the first still holds.
final class CheckoutCartActivity {
  final Set<Object> _holders = <Object>{};

  /// Whether any till reported a sale it has not saved.
  bool get saleInProgress => _holders.isNotEmpty;

  /// Records whether [till] holds an unsaved sale.
  void report(Object till, {required bool holdsSale}) {
    if (holdsSale) {
      _holders.add(till);
    } else {
      _holders.remove(till);
    }
  }
}
