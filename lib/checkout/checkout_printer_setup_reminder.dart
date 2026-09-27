import 'package:hive/hive.dart';

/// Whether this device still tells a business, after each sale, that it has no
/// printer set up.
///
/// **Per business, on this device.** A shop that sells without a printer on
/// purpose says so once and the till stops asking; another business on the
/// same phone, which may yet buy one, is still told. Only the *no printer is
/// set up* notice is silenced - a printer that is set up and does not answer is
/// a fault, and is always reported.
abstract interface class CheckoutPrinterSetupReminder {
  bool isSilenced(String tenantId);

  Future<void> silence(String tenantId);
}

/// [CheckoutPrinterSetupReminder] in its own small box.
///
/// **Not encrypted, and not behind the startup storage gate.** It holds a
/// business ID and a yes, the same as the routing box beside it, and losing it
/// costs one more reminder rather than anything a person made.
final class HiveCheckoutPrinterSetupReminder
    implements CheckoutPrinterSetupReminder {
  const HiveCheckoutPrinterSetupReminder(this._box);

  static const boxName = 'checkout-printer-setup-reminder-v1';

  static Future<HiveCheckoutPrinterSetupReminder> open() async =>
      HiveCheckoutPrinterSetupReminder(await Hive.openBox<bool>(boxName));

  final Box<bool> _box;

  @override
  bool isSilenced(String tenantId) => _box.get(tenantId) ?? false;

  @override
  Future<void> silence(String tenantId) => _box.put(tenantId, true);
}
