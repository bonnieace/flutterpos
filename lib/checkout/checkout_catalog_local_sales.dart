/// What this device has sold since the catalog it prices from was last read.
///
/// **The register was showing a stock figure that never moved.** A sale
/// deliberately does not refresh the catalog - `CheckoutSyncPass` skips it for
/// a pass a saved sale asked for, because refreshing there would make a till
/// re-read every product in the business on every customer. The side effect was
/// that the number under each product stayed at whatever the last refresh saw,
/// so it drifted further from the truth with every sale of the day: seen on a
/// device reading `84 in stock` while Inventory read `82`, and still reading
/// `84` after two more sales and a trip out of the screen and back.
///
/// **The device already knew.** It had just sold the units; nothing needed
/// reading to know they had gone. This is that knowledge, held between the sale
/// and the next catalog refresh, and subtracted when the catalog is read.
///
/// **In memory, and that is enough.** The tally only has to bridge the gap
/// between one catalog refresh and the next, and a refresh happens whenever a
/// tenant session opens or connectivity returns - so it can never need to
/// outlive the process that recorded it. Nothing durable is written, which is
/// the whole point: the alternative was rewriting a cached catalog measured in
/// megabytes once per customer.
///
/// **Scoped per UID and tenant**, like every other piece of local checkout
/// state, so a device that switches business cannot subtract one shop's sales
/// from another's shelves.
final class CheckoutCatalogLocalSales {
  final Map<String, Map<String, int>> _soldBySession =
      <String, Map<String, int>>{};

  static String _key(String uid, String tenantId) => '$uid:$tenantId';

  /// Records units that have left the shelf on this device.
  ///
  /// Additive, because a shelf sold from twice is down by both. A quantity
  /// that is not a positive whole number is ignored rather than trusted: this
  /// only ever reduces a figure, and a negative would make the register claim
  /// stock the catalog never reported.
  void recordSale({
    required String uid,
    required String tenantId,
    required Map<String, int> unitsByProduct,
  }) {
    if (unitsByProduct.isEmpty) return;
    final sold = _soldBySession.putIfAbsent(
      _key(uid, tenantId),
      () => <String, int>{},
    );
    for (final entry in unitsByProduct.entries) {
      if (entry.value <= 0) continue;
      sold[entry.key] = (sold[entry.key] ?? 0) + entry.value;
    }
  }

  /// How many units of one product this device has sold since the last read.
  int soldFor({
    required String uid,
    required String tenantId,
    required String productId,
  }) => _soldBySession[_key(uid, tenantId)]?[productId] ?? 0;

  /// Whether anything is owed against this session's catalog.
  bool hasSalesFor({required String uid, required String tenantId}) =>
      _soldBySession[_key(uid, tenantId)]?.isNotEmpty ?? false;

  /// Forgets this session's tally.
  ///
  /// **Called when a fresh catalog is written, not on a timer.** That snapshot
  /// was read from the server, which already counted these sales, so keeping
  /// the tally would subtract them a second time.
  void clearFor({required String uid, required String tenantId}) {
    _soldBySession.remove(_key(uid, tenantId));
  }
}
