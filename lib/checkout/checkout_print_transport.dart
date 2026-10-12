/// The conditional-import shim: `docs/printer_transport.md` §1.1, verbatim.
///
/// **Why this over `if (kIsWeb)` branching**: `dart:io` and the web transport
/// are never both compiled into a binary, so neither platform pays for the
/// other and neither can accidentally reference the other's types.
///
/// **All four implementations exist since 2026-10-10** — `_base`, `_io`,
/// `_unsupported`, and `_web`, which is WebUSB: the developer chose USB as the
/// way a web till prints. The stub is still the default, so a platform that is
/// neither `dart:io` nor a browser fails loudly at its first receipt.
///
/// Keeping the shim rather than importing `dart:io` directly is the entire
/// reason the web transport was a new file instead of a refactor of every
/// call site.
///
/// Note that `lib/services/thermal_printer_service.dart` imports `dart:io`
/// unconditionally, so an unguarded import is the status quo this improves on
/// rather than a risk it introduces.
library;

import 'checkout_bluetooth_printer.dart';
import 'checkout_print_helper.dart';
import 'checkout_print_transport_base.dart';
import 'checkout_print_transport_unsupported.dart'
    if (dart.library.io) 'checkout_print_transport_io.dart'
    if (dart.library.js_interop) 'checkout_print_transport_web.dart'
    as implementation;
import 'checkout_usb_printer.dart';

export 'checkout_bluetooth_printer.dart';
export 'checkout_print_helper.dart';
export 'checkout_print_mode.dart';
export 'checkout_print_transport_base.dart';
export 'checkout_system_printer.dart';
export 'checkout_usb_printer.dart';

/// The transport for the platform this binary was compiled for.
PrinterTransport createPrinterTransport() =>
    implementation.createPrinterTransport();

/// Bluetooth printer search and pairing on Android; an honest "not here"
/// everywhere else, web included - so the Bluetooth plugin is never compiled
/// into a web build.
BluetoothPrinterDiscovery createBluetoothPrinterDiscovery() =>
    implementation.createBluetoothPrinterDiscovery();

/// Choosing a USB printer through the browser's own picker on the web; an
/// honest "not here" on every other platform.
UsbPrinterChooser createUsbPrinterChooser() =>
    implementation.createUsbPrinterChooser();

/// Whether this browser has found the print helper. See
/// `checkout_print_helper.dart`.
PrintHelperMemory createPrintHelperMemory() =>
    implementation.createPrintHelperMemory();
