/// The failure codes, as the sentences a shopkeeper reads.
///
/// **`docs/printer_transport.md` §8: "Mapping happens at the UI edge. The
/// transport never builds a sentence."** This file is that edge, and it is the
/// only place in the printing slice that contains English.
///
/// **Every sentence says *sent*, never *printed*.** `send` returning normally
/// means the transport handed every byte off; no ESC/POS network transport can
/// prove paper moved without reading printer status back, which Phase 1 does
/// not do. A confirmation that claimed otherwise would be the app asserting
/// something it cannot know, about the one document a customer takes away.
///
/// **Each maps to an `AppStatus` as well as to a sentence**, because §9 does
/// not let a status be carried by a sentence alone and `Callout` needs the
/// kind, not just the words.
library;

import '../ui/status.dart';
import 'checkout_print_transport_base.dart';

/// One printing outcome, in this app's own vocabulary.
///
/// Built from a [PrinterTransportCode] rather than from an exception, so a
/// job's stored `attentionReason` — which is a string on disk — maps through
/// exactly the same path a live failure does.
abstract final class PrinterFailureNotice {
  /// The notice for [code], or a refusal naming the code itself.
  ///
  /// **An unknown code is not silently swallowed.** A code this build has never
  /// heard of means a durable record written by a newer build, and saying so is
  /// more useful than a generic apology.
  static AppNotice of(String code) => switch (code) {
    PrinterTransportCode.unreachable => const AppNotice.refused(
      'The printer did not answer. Check it is switched on and on this '
      'network.',
    ),
    PrinterTransportCode.connectTimeout => const AppNotice.refused(
      'The printer took too long to answer. Check its address and the '
      'Wi-Fi network.',
    ),
    // **`attention`, not `problem`, and it is the one judgement in this file.**
    // The connection was accepted and the payload stalled part-way, so
    // something physical is in the way — paper, a cover, a jam — and §2.1's
    // `attention` is "unreconciled, pending, awaiting". It is the one code
    // where the receipt may yet come out of the machine.
    PrinterTransportCode.writeTimeout => const AppNotice.unknown(
      'The printer stopped part-way. Check for a paper jam or an open '
      'cover, then send it again.',
    ),
    // **`info`, because nothing failed.** No printer has been set up, which is
    // a thing to do rather than a fault to report, and painting it red would
    // send an owner looking for a broken machine they have not bought yet.
    PrinterTransportCode.notConfigured => const AppNotice.offline(
      'No printer is set up for this business yet. Finish printer setup to '
      'start sending receipts.',
    ),
    // **A browser reaches a printer by USB, through its own print window, or
    // through the print helper, and nothing else**, so this says so - it is
    // the code a web till gets for a network or Bluetooth printer.
    PrinterTransportCode.unsupported => const AppNotice.offline(
      'This printer cannot be reached from a browser by itself. On a Windows '
      'computer, install the print helper from the Printer page. Or choose a '
      'USB printer or the print dialog there - or print from the app on a '
      'phone or tablet.',
    ),
    PrinterTransportCode.bridgeUnreachable => const AppNotice.refused(
      'The print bridge did not answer. Check that computer is running.',
    ),
    PrinterTransportCode.bridgeRejected => const AppNotice.refused(
      'The print bridge refused the receipt.',
    ),
    PrinterTransportCode.bridgeUnauthorized => const AppNotice.refused(
      'The print bridge did not accept this device. Re-enter the print token.',
    ),
    // **The Bluetooth three name the phone's own switch and permission**,
    // because those are the faults a person can see and fix from where they
    // stand - a printer that is "not on this network" means nothing over
    // Bluetooth.
    PrinterTransportCode.bluetoothOff => const AppNotice.refused(
      'Bluetooth is off on this device. Turn it on, then send it again.',
    ),
    PrinterTransportCode.bluetoothPermissionDenied => const AppNotice.refused(
      'This app is not allowed to use Bluetooth. Allow Nearby devices for '
      'UzaPay in the phone settings, then send it again.',
    ),
    PrinterTransportCode.bluetoothUnreachable => const AppNotice.refused(
      'The Bluetooth printer did not answer. Check it is switched on, close '
      'to this device and not connected to another phone.',
    ),
    // **The USB three name the cable, the power and Windows' own driver**,
    // which are what a person at a till can see and change.
    PrinterTransportCode.usbNotFound => const AppNotice.refused(
      'The USB printer is not connected. Check its cable and that it is '
      'switched on, then send it again. If it still is not found, choose it '
      'again on the Printer page.',
    ),
    PrinterTransportCode.usbBusy => const AppNotice.refused(
      'Another program is using the USB printer, so the browser cannot. On '
      'Windows this is usually the printer’s own driver: close other '
      'browser tabs using it, or replace its driver with WinUSB, then send '
      'it again.',
    ),
    PrinterTransportCode.usbFailed => const AppNotice.refused(
      'The USB printer did not take the receipt. Check its cable and power, '
      'then send it again.',
    ),
    // Not a failure of anything: somebody closed the window. `info`, like an
    // unconfigured printer, and sending it again opens the window again.
    PrinterTransportCode.printDialogClosed => const AppNotice.offline(
      'The print window was closed without printing. Send it again to open '
      'it again.',
    ),
    PrinterTransportCode.printDialogFailed => const AppNotice.refused(
      'This device could not open its print window. Send it again; if it '
      'keeps failing, close and reopen the app.',
    ),
    PrinterTransportCode.printHelperUnreachable => const AppNotice.refused(
      'The print helper is not running on this computer. Restart the '
      'computer, or download it again from the Printer page and run it, then '
      'send the receipt again.',
    ),
    PrinterTransportCode.printHelperRefused => const AppNotice.refused(
      'The print helper only sends to printers on this shop’s own network, '
      'and this printer’s address is not one of them. Check the address on '
      'the Printer page.',
    ),
    _ => AppNotice.unknown(
      'This device does not recognise the printing result "$code". It may '
      'have been recorded by a newer version of the app.',
    ),
  };

  /// The confirmation. **Sent, not printed** — see the library note.
  static const AppNotice sent = AppNotice.confirmed(
    'Receipt sent to the printer.',
  );

  /// What a person is told while a receipt is waiting its turn.
  static const AppNotice queued = AppNotice.unknown(
    'Receipt queued. It is sent as soon as the printer is free.',
  );

  /// This device's queue depth, in words, or null when there is nothing to say.
  ///
  /// **Here rather than at the composition root**, because it is a sentence and
  /// this is the file that holds them. The home's destination card and the
  /// screenshot harness would otherwise word the same fact twice.
  ///
  /// §4.4: *"a card states its own condition ... queue depth"*, and one that
  /// carries none is a button. Null when nothing is waiting, because a card
  /// reading *0 waiting to send* is noise — §8 rule 2 asks a surface to state
  /// what is true, not what is available.
  ///
  /// **[unreadable] is stated separately and never folded into [waiting]**, for
  /// the reason `HivePrintJobQueue.pending` gives: a figure that quietly
  /// excluded the records it could not parse would under-report exactly the
  /// queue that most needs attention.
  static String? queueDepth({required int waiting, required int unreadable}) {
    final parts = <String>[
      if (waiting > 0) '$waiting waiting to send',
      if (unreadable > 0) '$unreadable could not be read',
    ];
    return parts.isEmpty ? null : parts.join(', ');
  }

  /// Whether [code] describes something the person can act on right now.
  ///
  /// `notConfigured` and `unsupported` are the two that a retry cannot fix:
  /// one needs a setting and the other needs a different device. Offering
  /// *Send again* on either would be a control that is guaranteed to fail.
  static bool isRetryable(String code) =>
      code != PrinterTransportCode.notConfigured &&
      code != PrinterTransportCode.unsupported &&
      code != PrinterTransportCode.printHelperRefused;
}
