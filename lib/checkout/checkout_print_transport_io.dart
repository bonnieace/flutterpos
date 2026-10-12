/// The `dart:io` transport: one socket per job, Android through Linux.
///
/// **One implementation covers all five Phase 1 targets**, which is why
/// deferring web costs so little — `docs/printer_transport.md` §4.
///
/// **A connection per job, never pooled.** Both of the borrowed repo's real
/// transports open, write, close, and that is correct for ESC/POS: printers
/// drop idle connections without notice, and a pooled socket that *looks* alive
/// but is not turns into a silently lost receipt.
///
/// **Connect and write timeouts are distinct**, because the faults are
/// distinct and the operator guidance differs. A printer that never answers TCP
/// is off or on the wrong network; one that accepts the connection and then
/// stalls has a paper jam or an open cover.
///
/// **`SocketException`, not `TimeoutException`, is what a connect timeout
/// throws.** `docs/printer_transport.md` §2 records this as verified against
/// the borrowed repo at commit `95b07d4`: it wraps `Socket.connect(timeout:)`
/// in `on TimeoutException`, which is a dead branch, so its more helpful
/// message never renders. This file reads the exception's `osError` instead,
/// and falls back on the elapsed time rather than trusting a platform code.
library;

import 'dart:async';
import 'dart:io';

import 'checkout_print_helper.dart';
import 'checkout_bluetooth_printer.dart';
import 'checkout_print_transport_base.dart';
import 'checkout_print_transport_bluetooth.dart';
import 'checkout_system_printer.dart';
import 'checkout_usb_printer.dart';

/// Opens a real socket. Injected so a test can drive a `ServerSocket` that
/// accepts, or stalls, or refuses — which is `docs/printer_transport.md` §9's
/// required coverage.
typedef PrinterSocketConnector =
    Future<Socket> Function(String host, int port, {Duration? timeout});

/// Sockets for network printers and, on Android, Bluetooth for paired ones -
/// chosen per job by the job's own endpoint.
PrinterTransport createPrinterTransport() => RoutedPrinterTransport(
  network: IoPrinterTransport(),
  // Only Android has Bluetooth Classic serial. Elsewhere a Bluetooth endpoint
  // cannot be chosen in the first place, and the stub says so if one arrives.
  bluetooth: Platform.isAndroid
      ? AndroidBluetoothPrinterTransport()
      : const _NoBluetoothPrinterTransport(),
  // Android's print screen, for a printer reached through a print service.
  system: const SystemPrintTransport(),
);

BluetoothPrinterDiscovery createBluetoothPrinterDiscovery() =>
    Platform.isAndroid
    ? AndroidBluetoothPrinterDiscovery()
    : const UnsupportedBluetoothPrinterDiscovery();

/// USB printing is the web's; the app on a phone or a computer does not need
/// it (the developer's call, 2026-10-10).
/// Never seen: the print helper is for a browser, and this is not one.
PrintHelperMemory createPrintHelperMemory() => _noPrintHelper;

final PrintHelperMemory _noPrintHelper = InMemoryPrintHelperMemory();

UsbPrinterChooser createUsbPrinterChooser() =>
    const UnsupportedUsbPrinterChooser();

final class _NoBluetoothPrinterTransport implements PrinterTransport {
  const _NoBluetoothPrinterTransport();

  @override
  PrinterTransportCapability get capability => const PrinterTransportCapability(
    kind: PrinterTransportKind.none,
    endpointIsPrinter: false,
    label: 'Bluetooth printing is not available on this platform',
  );

  @override
  Future<void> probe(PrinterEndpoint endpoint) async =>
      throw const PrinterTransportException(PrinterTransportCode.unsupported);

  @override
  Future<void> send(PrinterEndpoint endpoint, List<int> bytes) async =>
      throw const PrinterTransportException(PrinterTransportCode.unsupported);

  @override
  Future<void> dispose() async {}
}

final class IoPrinterTransport implements PrinterTransport {
  IoPrinterTransport({
    PrinterSocketConnector? connect,
    this.connectTimeout = const Duration(seconds: 5),
    this.writeTimeout = const Duration(seconds: 8),
  }) : _connect = connect ?? _defaultConnect {
    if (connectTimeout <= Duration.zero) {
      throw ArgumentError.value(connectTimeout, 'connectTimeout');
    }
    if (writeTimeout <= Duration.zero) {
      throw ArgumentError.value(writeTimeout, 'writeTimeout');
    }
  }

  /// The two figures the borrowed repo separates, kept as a shape rather than
  /// as gospel. Five seconds is a printer on the same LAN; eight is a payload
  /// with a logo in it.
  final Duration connectTimeout;
  final Duration writeTimeout;

  final PrinterSocketConnector _connect;

  static Future<Socket> _defaultConnect(
    String host,
    int port, {
    Duration? timeout,
  }) => Socket.connect(host, port, timeout: timeout);

  @override
  PrinterTransportCapability get capability => const PrinterTransportCapability(
    kind: PrinterTransportKind.directTcp,
    // The operator configures the printer itself here, so a setup screen
    // shows the address field. On the Phase 2 bridge it does not.
    endpointIsPrinter: true,
    label: 'Direct network printing',
  );

  /// Connects and closes without writing a byte.
  @override
  Future<void> probe(PrinterEndpoint endpoint) async {
    final socket = await _open(endpoint);
    await _close(socket);
  }

  @override
  Future<void> send(PrinterEndpoint endpoint, List<int> bytes) async {
    final socket = await _open(endpoint);
    try {
      socket.add(bytes);
      // **`flush` is where a stalled printer is actually discovered.** `add` is
      // buffered and returns immediately, so a transport that timed only the
      // `add` would report success for a payload still sitting in the socket's
      // send buffer against a printer with its cover open.
      await socket.flush().timeout(writeTimeout);
    } on TimeoutException {
      _destroy(socket);
      throw const PrinterTransportException(PrinterTransportCode.writeTimeout);
    } on SocketException {
      _destroy(socket);
      // A socket that dies mid-payload is the same fault as one that stalls,
      // from the operator's side: the connection was accepted and the print did
      // not finish.
      throw const PrinterTransportException(PrinterTransportCode.writeTimeout);
    }
    await _close(socket);
  }

  @override
  Future<void> dispose() async {}

  Future<Socket> _open(PrinterEndpoint endpoint) async {
    final started = DateTime.now();
    try {
      return await _connect(
        endpoint.host,
        endpoint.port,
        timeout: connectTimeout,
      );
    } on SocketException {
      // **The timeout is inferred from elapsed time, not from an errno.**
      // `Socket.connect` reports a timeout as a `SocketException` whose
      // `osError` differs per platform — 10060 on Windows, `ETIMEDOUT` on
      // POSIX, and nothing at all when the SDK's own timer fires first. Elapsed
      // time is the one signal that means the same thing everywhere.
      throw PrinterTransportException(
        DateTime.now().difference(started) >= connectTimeout
            ? PrinterTransportCode.connectTimeout
            : PrinterTransportCode.unreachable,
      );
    } on TimeoutException {
      // Belt and braces: a connector injected by a test may throw this even
      // though the SDK does not.
      throw const PrinterTransportException(
        PrinterTransportCode.connectTimeout,
      );
    }
  }

  Future<void> _close(Socket socket) async {
    try {
      await socket.close();
    } on SocketException {
      // The bytes were flushed; a failure to shut the socket down cleanly is
      // not a failed print and must not be reported as one.
    }
    _destroy(socket);
  }

  void _destroy(Socket socket) {
    try {
      socket.destroy();
    } catch (_) {
      // Already gone.
    }
  }
}
