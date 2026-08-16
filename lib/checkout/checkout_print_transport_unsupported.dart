/// The transport a platform with no transport gets.
///
/// **It throws rather than silently no-oping, and that is the whole point.**
/// `docs/printer_transport.md` §1.1: *"The unsupported stub throws rather than
/// silently no-oping, so a new platform target fails loudly at first print
/// instead of quietly dropping receipts."* A receipt that was never printed and
/// never complained is the worst outcome available here — the shop finds out
/// from a customer.
///
/// **In Phase 1 this is what a web build resolves to**, because browsers cannot
/// open raw TCP and the Flask bridge in §5 is Phase 2. That is correct deferred
/// behaviour: honest and loud.
library;

import 'checkout_print_transport_base.dart';

PrinterTransport createPrinterTransport() => const UnsupportedPrinterTransport();

final class UnsupportedPrinterTransport implements PrinterTransport {
  const UnsupportedPrinterTransport();

  @override
  PrinterTransportCapability get capability =>
      const PrinterTransportCapability(
        kind: PrinterTransportKind.none,
        // Nothing is configurable, so the question does not arise; `false`
        // keeps a setup screen from offering a printer address field it could
        // never use.
        endpointIsPrinter: false,
        label: 'Printing is not available on this platform',
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
