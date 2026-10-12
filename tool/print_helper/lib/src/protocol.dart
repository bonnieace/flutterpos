/// What the web till and the print helper say to each other.
///
/// **The helper listens on this computer only, on one fixed port**, so a page
/// can find it without being told where: `http://127.0.0.1:17919`. A browser
/// treats a loopback address as secure, so an https till may call it, and
/// Chrome asks the person once before a public site may.
///
/// **Only UzaPay's own pages may make it print.** Every browser request
/// carries an `Origin`, and one that is not UzaPay's is refused before
/// anything is read - which is what stops another website from feeding a
/// shop's printer. A request with no `Origin` comes from a program on this
/// computer, not from a page, and a program here could print anyway.
///
/// **Codes are the app's own `PrinterTransportCode` strings**, so the till
/// shows the sentences it already has for each outcome.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Who answers on [helperPort], so the page knows it found this and not some
/// other program.
const String helperApp = 'uzapay-print-helper';

/// Kept equal to `pubspec.yaml`'s version by a test.
const String helperVersion = '1.0.4';

/// The one port the helper listens on, on `127.0.0.1` only.
const int helperPort = 17919;

/// The largest request body the helper reads: a receipt with a logo is a few
/// kilobytes, so this is generous and still stops a page from filling memory.
const int maximumBodyBytes = 4 * 1024 * 1024;

/// Outcomes the helper reports, spelled as the app spells them.
abstract final class HelperCode {
  static const String usbNotFound = 'usb_printer_not_found';
  static const String usbBusy = 'usb_printer_busy';
  static const String usbFailed = 'usb_printer_failed';
  static const String unreachable = 'printer_unreachable';
  static const String connectTimeout = 'printer_connect_timeout';
  static const String writeTimeout = 'printer_write_timeout';

  /// A printer address the helper will not send to: one outside this shop's
  /// own network.
  static const String refused = 'print_helper_refused';

  /// A request the helper could not read.
  static const String badRequest = 'bad_request';
}

/// Where a job goes.
sealed class PrintTarget {
  const PrintTarget();

  /// What jobs for the same printer queue behind, one at a time.
  String get lockKey;
}

/// A USB printer, by the key the app stores: `1FC9:2016` or
/// `1FC9:2016:06C6ACA91073`.
final class UsbTarget extends PrintTarget {
  const UsbTarget(this.key);

  final String key;

  @override
  String get lockKey => 'usb:${key.toUpperCase()}';
}

/// A network printer, by address and port.
final class NetworkTarget extends PrintTarget {
  const NetworkTarget(this.host, this.port);

  final String host;
  final int port;

  @override
  String get lockKey => 'net:${host.toLowerCase()}:$port';
}

final RegExp _usbKey = RegExp(
  r'^[0-9A-Fa-f]{4}:[0-9A-Fa-f]{4}(:[A-Za-z0-9._\-]{1,64})?$',
);

/// The app's own host rule: a bare name or IPv4 address, no scheme, path,
/// port or whitespace.
final RegExp _host = RegExp(
  r'^[A-Za-z0-9]([A-Za-z0-9\-]{0,61}[A-Za-z0-9])?'
  r'(\.[A-Za-z0-9]([A-Za-z0-9\-]{0,61}[A-Za-z0-9])?)*$',
);

/// Reads a `target` object, or throws [FormatException].
PrintTarget parseTarget(Object? json) {
  if (json is! Map) throw const FormatException('target');
  switch (json['kind']) {
    case 'usb':
      final key = json['key'];
      if (key is! String || !_usbKey.hasMatch(key)) {
        throw const FormatException('key');
      }
      return UsbTarget(key);
    case 'network':
      final host = json['host'];
      final port = json['port'];
      if (host is! String ||
          host.length > 253 ||
          !_host.hasMatch(host) ||
          host == '0.0.0.0' ||
          port is! int ||
          port < 1 ||
          port > 65535) {
        throw const FormatException('address');
      }
      return NetworkTarget(host, port);
    default:
      throw const FormatException('kind');
  }
}

/// A print request: where, and the bytes, which travel as base64.
({PrintTarget target, Uint8List bytes}) parsePrint(Object? json) {
  if (json is! Map) throw const FormatException('body');
  final data = json['data'];
  if (data is! String || data.isEmpty) throw const FormatException('data');
  final Uint8List bytes;
  try {
    bytes = base64Decode(data);
  } on FormatException {
    throw const FormatException('data');
  }
  return (target: parseTarget(json['target']), bytes: bytes);
}

/// Whether a page at [origin] may use the helper.
///
/// **Loopback pages are allowed on any port**, because that is how the till is
/// served while it is developed and tried on this computer, and a program
/// serving pages here is already trusted with this computer. Otherwise only
/// UzaPay's own addresses, over https.
bool isAllowedOrigin(String origin) {
  final uri = Uri.tryParse(origin);
  if (uri == null || uri.host.isEmpty) return false;
  if (uri.path.isNotEmpty && uri.path != '/') return false;
  final host = uri.host.toLowerCase();
  const loopback = <String>{'127.0.0.1', 'localhost', '::1', '[::1]'};
  if (loopback.contains(host)) {
    return uri.scheme == 'http' || uri.scheme == 'https';
  }
  if (uri.scheme != 'https') return false;
  const hosted = <String>{
    'multitenant-pos-b8326.web.app',
    'multitenant-pos-b8326.firebaseapp.com',
    'uzapay.co.ke',
  };
  return hosted.contains(host) || host.endsWith('.uzapay.co.ke');
}

/// Whether [address] is on this shop's own network - private, link-local or
/// this computer - which is the only place a receipt printer is.
///
/// **This is what keeps the helper from being a way out of the building.**
/// The app sends whatever address the business saved; refusing anything
/// public means a page that somehow got through could still only reach the
/// shop's own devices.
bool isLocalAddress(InternetAddress address) {
  final raw = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) {
    final a = raw[0];
    final b = raw[1];
    return a == 10 ||
        a == 127 ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168) ||
        (a == 169 && b == 254);
  }
  if (address.type == InternetAddressType.IPv6) {
    if (address.isLoopback) return true;
    // fe80::/10 link-local, fc00::/7 unique local.
    return (raw[0] == 0xFE && (raw[1] & 0xC0) == 0x80) ||
        (raw[0] & 0xFE) == 0xFC;
  }
  return false;
}

/// The key Windows' own USB printer driver gives a printer, from the path its
/// port monitor writes to: `\\?\usb#vid_1fc9&pid_2016#06c6aca91073#{...}`.
///
/// **Upper-case hex, and the serial number when the printer has one**, which
/// is the key the app's USB tab builds from what a browser reports - so a
/// printer is one key whichever way it was found. A printer with no serial
/// number gets an instance name from Windows with `&` in it, which is not a
/// serial and is left off.
String? usbKeyFromDevicePath(String path) {
  final parts = path.split('#');
  if (parts.length < 3) return null;
  final ids = RegExp(
    r'vid_([0-9a-f]{4})&pid_([0-9a-f]{4})',
    caseSensitive: false,
  ).firstMatch(parts[1]);
  if (ids == null) return null;
  final model = '${ids[1]!.toUpperCase()}:${ids[2]!.toUpperCase()}';
  final serial = parts[2];
  final isSerial =
      !serial.contains('&') &&
      RegExp(r'^[A-Za-z0-9._\-]{1,64}$').hasMatch(serial);
  return isSerial ? '$model:${serial.toUpperCase()}' : model;
}

/// Whether a printer found with [found] is the one [wanted] names.
///
/// **Case does not decide it**: Windows lower-cases a serial in its paths and
/// a browser reports it as the printer does. A key with no serial number is
/// the model, and matches the first printer of that model.
bool usbKeyMatches(String wanted, String found) {
  final a = wanted.toUpperCase();
  final b = found.toUpperCase();
  if (a == b) return true;
  final parts = a.split(':');
  return parts.length == 2 && b.startsWith('$a:');
}
