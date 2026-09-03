import 'package:flutter/services.dart';

/// The channel `MainActivity` answers. Android only; every other platform
/// returns null through [MissingPluginException], which is a supported answer.
const MethodChannel deviceHardwareIdentityChannel = MethodChannel(
  'pos/device-identity',
);

/// A value that names this physical device and outlives a reinstall.
///
/// **The seam exists because the alternative is a lockout.** A device identity
/// minted at random on first launch dies with the app's data, and a till that
/// comes back under a new identity cannot recognise the shift it left open -
/// see `HiveCheckoutReceiptCounters.resolveDeviceId`, which consumes this.
///
/// Returning null is normal. It means "this platform has nothing durable to
/// offer", and the caller falls back to the random identity it has always used,
/// so nothing that works today stops working on a device that answers null.
abstract interface class DeviceHardwareIdentity {
  Future<String?> read();
}

/// Reads `Settings.Secure.ANDROID_ID` through [deviceHardwareIdentityChannel].
///
/// Every failure is null rather than a throw. This is called once during
/// startup, before the first frame, and a device whose platform answer is
/// missing, malformed, or unimplemented must still be able to open the till.
final class MethodChannelDeviceHardwareIdentity
    implements DeviceHardwareIdentity {
  const MethodChannelDeviceHardwareIdentity({
    MethodChannel channel = deviceHardwareIdentityChannel,
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<String?> read() async {
    try {
      final value = await _channel.invokeMethod<String>('hardwareId');
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    } on MissingPluginException {
      // iOS, desktop, web, and the widget tests: no handler is registered, and
      // that is not an error worth reporting to a person opening a till.
      return null;
    } on PlatformException {
      return null;
    }
  }
}
