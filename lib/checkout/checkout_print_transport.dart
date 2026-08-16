/// The conditional-import shim: `docs/printer_transport.md` §1.1, verbatim.
///
/// **Why this over `if (kIsWeb)` branching**: `dart:io` and the web transport
/// are never both compiled into a binary, so neither platform pays for the
/// other and neither can accidentally reference the other's types.
///
/// **Phase 1 writes three of the four implementations** — `_base`, `_io` and
/// `_unsupported`. **There is no `js_interop` branch here and that is not an
/// omission**: §1.1's example lists one, but a conditional import naming a file
/// that does not exist will not compile, so `_web` gets its branch on the day
/// it gets its file. Until then the *default* import is the stub, which is the
/// same outcome — printing on a web build throws `transport_unsupported`.
///
/// Keeping the shim now rather than importing `dart:io` directly is the entire
/// reason Phase 2 is a new file instead of a refactor of every call site, and
/// it costs about forty lines.
///
/// Note that `lib/services/thermal_printer_service.dart` imports `dart:io`
/// unconditionally, so an unguarded import is the status quo this improves on
/// rather than a risk it introduces.
library;

import 'checkout_print_transport_base.dart';
import 'checkout_print_transport_unsupported.dart'
    if (dart.library.io) 'checkout_print_transport_io.dart'
    as implementation;

export 'checkout_print_transport_base.dart';

/// The transport for the platform this binary was compiled for.
PrinterTransport createPrinterTransport() =>
    implementation.createPrinterTransport();
