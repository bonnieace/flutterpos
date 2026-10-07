/// Bluetooth Classic printing on Android: the transport and the discovery.
///
/// **One connection per job, exactly as the network transport does it** - see
/// `checkout_print_transport_io.dart`. A held-open link looks alive long after
/// the printer has gone out of range, and `flutter_blue_classic` makes that
/// worse than a socket would: its Kotlin `write` logs a failed write and
/// reports success. A fresh `connect` is the one step that fails honestly, so
/// every receipt pays for one.
///
/// **The plugin is never allowed to ask for a permission.** Its `connect`
/// requests one and carries on without waiting for the answer, which fails the
/// connect and then answers the same call a second time. So this file asks
/// first, through `permission_handler`, and the transport - which runs after a
/// sale, with nobody looking at a dialog - only checks.
///
/// Imported only from the `dart:io` branch of the platform seam, and only
/// constructed on Android.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_blue_classic/flutter_blue_classic.dart';
import 'package:permission_handler/permission_handler.dart';

import 'checkout_bluetooth_printer.dart';
import 'checkout_print_transport_base.dart';

/// Android 12, where Bluetooth became its own runtime permission.
const int _androidS = 31;

/// The permissions a search and a connect need, by Android version.
///
/// Android 12 and later: *Nearby devices* (`BLUETOOTH_SCAN` and
/// `BLUETOOTH_CONNECT`). Before it, discovery needs location and connecting
/// needs nothing at run time.
final class _AndroidBluetoothPermissions {
  int? _sdk;

  Future<int> _sdkInt() async =>
      _sdk ??= (await DeviceInfoPlugin().androidInfo).version.sdkInt;

  Future<bool> request() async {
    final permissions = await _sdkInt() >= _androidS
        ? <Permission>[Permission.bluetoothScan, Permission.bluetoothConnect]
        : <Permission>[Permission.locationWhenInUse];
    final statuses = await permissions.request();
    return statuses.values.every((status) => status.isGranted);
  }

  /// Checks, never asks. The plugin's `connect` wants both.
  Future<bool> canConnect() async {
    if (await _sdkInt() < _androidS) return true;
    return await Permission.bluetoothConnect.isGranted &&
        await Permission.bluetoothScan.isGranted;
  }
}

final class AndroidBluetoothPrinterTransport implements PrinterTransport {
  AndroidBluetoothPrinterTransport({
    FlutterBlueClassic? bluetooth,
    this.connectTimeout = const Duration(seconds: 15),
    this.writeTimeout = const Duration(seconds: 30),
  }) : _bluetooth = bluetooth ?? FlutterBlueClassic();

  /// Longer than the network's five: a first connect after pairing does a
  /// service lookup and an authentication before the link opens.
  final Duration connectTimeout;

  /// A Bluetooth printer takes bytes as fast as it prints them, so a receipt
  /// with a logo can take several seconds to accept.
  final Duration writeTimeout;

  final FlutterBlueClassic _bluetooth;
  final _AndroidBluetoothPermissions _permissions =
      _AndroidBluetoothPermissions();

  @override
  PrinterTransportCapability get capability => const PrinterTransportCapability(
    kind: PrinterTransportKind.bluetooth,
    endpointIsPrinter: true,
    label: 'Bluetooth printing',
  );

  @override
  Future<void> probe(PrinterEndpoint endpoint) async {
    final link = await _open(endpoint);
    await link.close();
  }

  @override
  Future<void> send(PrinterEndpoint endpoint, List<int> bytes) async {
    final link = await _open(endpoint);
    final connection = link.connection;
    try {
      connection.output.add(Uint8List.fromList(bytes));
      await connection.output.allSent.timeout(writeTimeout);
      if (link.dropped || !connection.isConnected) {
        throw const PrinterTransportException(
          PrinterTransportCode.writeTimeout,
        );
      }
      // **Handed to the radio is not yet at the printer.** Android's write
      // returns once the bytes are in the stack's buffer, and closing the
      // socket can discard what is still in it - the classic receipt with its
      // last lines missing. So the link is held for as long as the tail could
      // take to drain before it is closed.
      await Future<void>.delayed(drainTime(bytes.length));
      if (link.dropped) {
        throw const PrinterTransportException(
          PrinterTransportCode.writeTimeout,
        );
      }
    } on TimeoutException {
      throw const PrinterTransportException(PrinterTransportCode.writeTimeout);
    } on StateError {
      // `Not connected!`: the link closed between connect and write.
      throw const PrinterTransportException(PrinterTransportCode.writeTimeout);
    } finally {
      await link.close();
    }
  }

  /// How long a payload's tail is given to leave the phone before the link is
  /// closed: a quarter second, plus [bytes] at 8 KB/s, at most six seconds.
  ///
  /// **An estimate, and the one number here to revisit on hardware.** 8 KB/s is
  /// below what a cheap SPP printer accepts, so a receipt is not cut short; the
  /// cost of guessing low is a slower queue, the cost of guessing high is a
  /// receipt missing its total.
  static Duration drainTime(int bytes) => Duration(
    milliseconds: math.min(250 + bytes ~/ 8, 6000),
  );

  @override
  Future<void> dispose() async {}

  Future<_Link> _open(PrinterEndpoint endpoint) async =>
      _Link(await _connect(endpoint));

  Future<BluetoothConnection> _connect(PrinterEndpoint endpoint) async {
    if (!endpoint.isBluetooth) {
      throw ArgumentError.value(endpoint, 'endpoint', 'Not a Bluetooth printer.');
    }
    // **Every way this can fail is a Bluetooth reason.** A platform error from
    // the permission or adapter check used to escape as itself, and the print
    // queue's catch-all read it as a network printer it could not reach - the
    // wrong advice for a printer on Bluetooth.
    try {
      if (!await _permissions.canConnect()) {
        throw const PrinterTransportException(
          PrinterTransportCode.bluetoothPermissionDenied,
        );
      }
      if (!await _bluetooth.isEnabled) {
        throw const PrinterTransportException(
          PrinterTransportCode.bluetoothOff,
        );
      }
    } on PlatformException catch (error) {
      throw PrinterTransportException(
        error.code == 'permissionDenied'
            ? PrinterTransportCode.bluetoothPermissionDenied
            : PrinterTransportCode.bluetoothUnreachable,
      );
    }
    final attempt = _bluetooth.connect(endpoint.host);
    try {
      final connection = await attempt.timeout(connectTimeout);
      if (connection == null) {
        throw const PrinterTransportException(
          PrinterTransportCode.bluetoothUnreachable,
        );
      }
      return connection;
    } on TimeoutException {
      // The platform keeps trying after this gives up. Whatever it opens late
      // is closed at once, never left holding the printer's only link.
      unawaited(
        attempt.then<void>(
          (late) async {
            if (late != null) await _Link(late).close();
          },
          onError: (Object _) {},
        ),
      );
      throw const PrinterTransportException(
        PrinterTransportCode.bluetoothUnreachable,
      );
    } on PlatformException catch (error) {
      throw PrinterTransportException(
        error.code == 'permissionDenied'
            ? PrinterTransportCode.bluetoothPermissionDenied
            : PrinterTransportCode.bluetoothUnreachable,
      );
    }
  }

}

/// One open connection, read from the moment it opens.
///
/// **Listening is not optional, and the reason is a hang.** The plugin's
/// `close` waits on its input controller's `close`, and a single-subscription
/// controller nobody ever listened to never finishes closing - so a probe that
/// opened and closed without reading would wait forever. Listening from the
/// start, and cancelling before closing, makes `close` return at once.
///
/// The listener also does the transport a service: a printer that drops the
/// link shows up here first, as the read side ending, which the plugin's own
/// write cannot report - see the library note.
final class _Link {
  _Link(this.connection) {
    _reading = connection.input?.listen(
      (_) {},
      onDone: () => _dropped = true,
      onError: (Object _) => _dropped = true,
    );
  }

  final BluetoothConnection connection;
  StreamSubscription<Uint8List>? _reading;
  bool _dropped = false;

  bool get dropped => _dropped;

  Future<void> close() async {
    try {
      await _reading?.cancel();
      // Bounded all the same: a teardown that stalls must not hold the
      // printer's queue, and the link is already being let go.
      await connection.close().timeout(const Duration(seconds: 3));
    } catch (_) {
      // The bytes were handed off; a failure to tear the link down is not a
      // failed print and must not be reported as one.
    }
  }
}

final class AndroidBluetoothPrinterDiscovery
    implements BluetoothPrinterDiscovery {
  AndroidBluetoothPrinterDiscovery({FlutterBlueClassic? bluetooth})
    : _bluetooth = bluetooth ?? FlutterBlueClassic();

  /// Longer than Android's own twelve-second discovery, so a discovery that
  /// never reports its end still ends.
  static const Duration searchLimit = Duration(seconds: 20);

  /// How long pairing waits for the person to answer the system's prompt.
  static const Duration pairingLimit = Duration(seconds: 40);
  static const Duration _pairingPoll = Duration(milliseconds: 750);

  final FlutterBlueClassic _bluetooth;
  final _AndroidBluetoothPermissions _permissions =
      _AndroidBluetoothPermissions();

  @override
  bool get isSupported => true;

  @override
  Future<BluetoothReadiness> prepare() async {
    if (!await _bluetooth.isSupported) return BluetoothReadiness.unsupported;
    if (!await _permissions.request()) {
      return BluetoothReadiness.permissionDenied;
    }
    return await _bluetooth.isEnabled
        ? BluetoothReadiness.ready
        : BluetoothReadiness.off;
  }

  @override
  Future<bool> turnOn() async {
    try {
      return await _bluetooth.turnOn();
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> openPermissionSettings() async {
    await openAppSettings();
  }

  @override
  Future<List<BluetoothPrinterDevice>> paired() async {
    final bonded = await _bluetooth.bondedDevices ?? const <BluetoothDevice>[];
    return <BluetoothPrinterDevice>[
      for (final device in bonded) _device(device, paired: true),
    ];
  }

  @override
  Stream<BluetoothPrinterDevice> search() {
    late final StreamController<BluetoothPrinterDevice> controller;
    StreamSubscription<BluetoothDevice>? results;
    StreamSubscription<bool>? scanning;
    Timer? limit;
    var started = false;
    Future<void> finish() async {
      limit?.cancel();
      if (!controller.isClosed) await controller.close();
    }

    controller = StreamController<BluetoothPrinterDevice>(
      onListen: () {
        results = _bluetooth.scanResults.listen(
          (device) => controller.add(
            _device(device, paired: device.bondState == BluetoothBondState.bonded),
          ),
          onError: controller.addError,
        );
        scanning = _bluetooth.isScanning.listen((on) {
          if (on) {
            started = true;
          } else if (started) {
            unawaited(finish());
          }
        });
        limit = Timer(searchLimit, () => unawaited(finish()));
        _bluetooth.startScan();
      },
      onCancel: () async {
        limit?.cancel();
        _bluetooth.stopScan();
        await results?.cancel();
        await scanning?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<bool> pair(String address) async {
    final wanted = address.toUpperCase();
    bool bonded(List<BluetoothPrinterDevice> devices) =>
        devices.any((device) => device.address.toUpperCase() == wanted);
    if (bonded(await paired())) return true;
    try {
      if (!await _bluetooth.bondDevice(wanted)) return false;
    } on PlatformException {
      return false;
    }
    // `createBond` only starts pairing; the person answers the system's
    // prompt in their own time, so the bond is watched for rather than
    // awaited.
    final deadline = DateTime.now().add(pairingLimit);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(_pairingPoll);
      if (bonded(await paired())) return true;
    }
    return false;
  }

  static BluetoothPrinterDevice _device(
    BluetoothDevice device, {
    required bool paired,
  }) => BluetoothPrinterDevice(
    address: device.address.toUpperCase(),
    name: device.alias ?? device.name,
    paired: paired,
  );
}
