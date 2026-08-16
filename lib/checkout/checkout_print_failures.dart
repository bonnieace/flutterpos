/// The eight failure codes, as the eight sentences a shopkeeper reads.
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
    PrinterTransportCode.unsupported => const AppNotice.offline(
      'Printing is not available in the browser yet. Use the app on a phone, '
      'a tablet or a computer.',
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

  /// Whether [code] describes something the person can act on right now.
  ///
  /// `notConfigured` and `unsupported` are the two that a retry cannot fix:
  /// one needs a setting and the other needs a different device. Offering
  /// *Send again* on either would be a control that is guaranteed to fail.
  static bool isRetryable(String code) =>
      code != PrinterTransportCode.notConfigured &&
      code != PrinterTransportCode.unsupported;
}
