import 'package:hive/hive.dart';

/// Whether this device still explains, when the Sales report opens on the day
/// a shift is still trading in, why it is not on today.
///
/// **Per business, on this device**, exactly as the till's no-printer reminder
/// is. A manager who has read it once says so and is not asked again on this
/// phone; another business on the same phone, whose staff may not know the
/// rule yet, still is. Only the explanation is silenced - the report still
/// opens on the day the till is trading in.
abstract interface class SalesTradingDayNotice {
  bool isSilenced(String tenantId);

  Future<void> silence(String tenantId);
}

/// [SalesTradingDayNotice] in its own small box.
///
/// **Not encrypted, and not behind the startup storage gate**, for the reason
/// `HiveCheckoutPrinterSetupReminder` gives: it holds a business ID and a yes,
/// and losing it costs one more explanation rather than anything a person
/// made.
final class HiveSalesTradingDayNotice implements SalesTradingDayNotice {
  const HiveSalesTradingDayNotice(this._box);

  static const boxName = 'sales-trading-day-notice-v1';

  static Future<HiveSalesTradingDayNotice> open() async =>
      HiveSalesTradingDayNotice(await Hive.openBox<bool>(boxName));

  final Box<bool> _box;

  @override
  bool isSilenced(String tenantId) => _box.get(tenantId) ?? false;

  @override
  Future<void> silence(String tenantId) => _box.put(tenantId, true);
}
