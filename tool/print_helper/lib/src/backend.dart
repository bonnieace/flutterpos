/// What the helper prints with: USB printers through Windows' own driver,
/// network printers by socket.
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'network_printer.dart';
import 'protocol.dart';
import 'usb_printers.dart';

/// The printing the server asks for. An interface so the server can be tested
/// without a printer.
abstract interface class PrinterBackend {
  /// The USB printers this computer has now.
  Future<List<UsbPrinterInfo>> usbPrinters();

  /// Null when every byte was handed off, otherwise a [HelperCode].
  Future<String?> print(PrintTarget target, Uint8List bytes);

  /// Null when the printer is there to print to, otherwise a [HelperCode].
  Future<String?> probe(PrintTarget target);
}

/// [PrinterBackend] on this Windows computer.
final class WindowsPrinterBackend implements PrinterBackend {
  WindowsPrinterBackend({
    this.usbWriteTimeout = const Duration(seconds: 10),
    Future<List<UsbPrinterInfo>> Function()? listUsb,
    this.log,
  }) : _listUsb = listUsb ?? _listOnAnotherIsolate;

  /// Where each USB write's answer from Windows is written down.
  final void Function(String line)? log;

  final Duration usbWriteTimeout;

  /// The USB printers Windows has now. Injected so a test can name a printer
  /// that is not there and still go all the way to the write.
  final Future<List<UsbPrinterInfo>> Function() _listUsb;

  /// One job at a time per printer: two pages interleaved on one roll would
  /// be two spoiled receipts.
  final Map<String, Future<void>> _tails = <String, Future<void>>{};

  @override
  Future<List<UsbPrinterInfo>> usbPrinters() => _listUsb();

  @override
  Future<String?> print(PrintTarget target, Uint8List bytes) =>
      _serialized(target, () async {
        switch (target) {
          case UsbTarget(:final key):
            final path = await _pathFor(key);
            if (path == null) return HelperCode.usbNotFound;
            final result = await _writeOnAnotherIsolate(
              path,
              bytes,
              usbWriteTimeout.inMilliseconds,
            );
            log?.call('usb $key: ${result.code ?? 'ok'}, ${result.detail}');
            return result.code;
          case NetworkTarget():
            return sendNetworkPrinter(target, bytes);
        }
      });

  @override
  Future<String?> probe(PrintTarget target) async {
    switch (target) {
      case UsbTarget(:final key):
        final path = await _pathFor(key);
        if (path == null) return HelperCode.usbNotFound;
        return _openOnAnotherIsolate(path);
      case NetworkTarget():
        return probeNetworkPrinter(target);
    }
  }

  Future<String?> _pathFor(String key) async {
    for (final printer in await usbPrinters()) {
      if (usbKeyMatches(key, printer.key)) return printer.path;
    }
    return null;
  }

  Future<String?> _serialized(
    PrintTarget target,
    Future<String?> Function() job,
  ) async {
    final previous = _tails[target.lockKey] ?? Future<void>.value();
    final done = Completer<void>();
    _tails[target.lockKey] = done.future;
    try {
      await previous;
      return await job();
    } finally {
      done.complete();
      if (identical(_tails[target.lockKey], done.future)) {
        // Already complete: nothing is waiting on the one removed.
        _tails.remove(target.lockKey)?.ignore();
      }
    }
  }
}

// **Top-level, and that is the fix for 1.0.0's only bug.** A closure sent to
// another isolate takes its whole context with it, and one written inside
// the backend's methods took the backend - whose queue of pending jobs holds
// futures, which cannot cross. Every USB print failed before it reached the
// printer. Out here a closure holds only what it is given.

Future<List<UsbPrinterInfo>> _listOnAnotherIsolate() =>
    Isolate.run(listUsbPrinters);

Future<UsbWriteResult> _writeOnAnotherIsolate(
  String path,
  Uint8List bytes,
  int timeoutMs,
) => Isolate.run(() => writeUsbPrinter(path, bytes, timeoutMs));

Future<String?> _openOnAnotherIsolate(String path) =>
    Isolate.run(() => openUsbPrinter(path));
