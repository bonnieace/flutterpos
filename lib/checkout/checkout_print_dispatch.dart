/// The one call that turns a committed sale into a receipt on its way to paper.
///
/// **This is the piece that made the printing slice reachable.** The transport,
/// the configuration, the queue and the formatter each did one thing and none of
/// them knew about the others; a screen wiring them together would have had to
/// make five decisions that belong here.
///
/// **§6.3's rule is what shapes it, and it is not only about animation.** *"No
/// animation may sit between an input and its record. The sale is written
/// first."* Printing is the same argument with a larger consequence: a receipt
/// that has to be produced before a sale is durable is a sale that a paper jam
/// can lose. So [dispatch] takes a sale that **is already committed** and never
/// reports a printing failure as a checkout failure.
///
/// **A sale that cannot be queued is not a sale that is lost.** When no printer
/// is configured this refuses with `printer_not_configured` and writes no job —
/// deliberately, because a job needs an address and `docs/printer_transport.md`
/// §6 forbids guessing one. The receipt is recoverable regardless: the sale is
/// durable, and the job key is the **receipt number the sale already carries**,
/// so queueing it later produces the same job rather than a second one. That is
/// the property that lets this refuse safely instead of inventing an address to
/// avoid refusing.
library;

import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';

import 'checkout_print_configuration.dart';
import 'checkout_print_jobs.dart';
import 'checkout_print_transport_base.dart';
import 'checkout_receipt_body.dart';
import 'checkout_sale.dart';

/// What happened to one receipt.
///
/// **Three outcomes rather than a `bool`**, for the reason
/// `TenantCatalogWriteKind` gives about writes: *sent*, *queued but not sent*
/// and *not queued at all* need three different sentences and lead to three
/// different controls.
enum CheckoutPrintOutcome {
  /// The transport handed every byte off. **Not proof that paper moved** — see
  /// `PrinterTransport.send`.
  sent,

  /// The job is durable and the send failed. It carries a
  /// [PrinterTransportCode] and can be retried.
  queued,

  /// Nothing was written, because there is nowhere to send it. The reason is
  /// always `printer_not_configured`.
  refused,
}

final class CheckoutPrintResult {
  const CheckoutPrintResult._(this.outcome, this.job, this.reasonCode);

  const CheckoutPrintResult.sent(PrintJobRecord job)
    : this._(CheckoutPrintOutcome.sent, job, null);

  const CheckoutPrintResult.queued(PrintJobRecord job, String reasonCode)
    : this._(CheckoutPrintOutcome.queued, job, reasonCode);

  const CheckoutPrintResult.refused(String reasonCode)
    : this._(CheckoutPrintOutcome.refused, null, reasonCode);

  final CheckoutPrintOutcome outcome;

  /// Present unless nothing was written.
  final PrintJobRecord? job;

  /// A [PrinterTransportCode]. Null only when [outcome] is
  /// [CheckoutPrintOutcome.sent].
  final String? reasonCode;
}

/// Builds a receipt for a committed sale and moves it toward a printer.
final class CheckoutPrintDispatcher {
  const CheckoutPrintDispatcher({
    required HivePrintJobQueue queue,
    required PrinterTransport transport,
    required CapabilityProfile profile,
  }) : _queue = queue,
       _transport = transport,
       _profile = profile;

  final HivePrintJobQueue _queue;
  final PrinterTransport _transport;
  final CapabilityProfile _profile;

  /// Builds and durably queues a receipt without touching the transport.
  /// Checkout uses this local-only boundary so a slow or unreachable printer
  /// can never hold the successful sale path open.
  Future<CheckoutPrintResult> enqueue(
    CheckoutSalePayload sale, {
    required TenantConfiguredPrinter printer,
    String? businessName,
    String? servedBy,
  }) async {
    if (!printer.canPrint) {
      return const CheckoutPrintResult.refused(
        PrinterTransportCode.notConfigured,
      );
    }
    final configuration = printer.require();
    final bytes = CheckoutReceiptBody(
      profile: _profile,
      configuration: configuration,
    ).build(sale, businessName: businessName, servedBy: servedBy);
    final job = await _queue.enqueue(
      tenantId: sale.tenantId,
      receiptNumber: sale.receiptNumber,
      endpoint: configuration.endpoint,
      bytes: bytes,
    );
    return job.state == PrintJobState.printed
        ? CheckoutPrintResult.sent(job)
        : CheckoutPrintResult.queued(job, 'queued_for_printing');
  }

  /// Queues [sale]'s receipt and attempts to send it.
  ///
  /// **Never throws for a printing reason.** Every failure the transport or the
  /// queue can produce comes back as a [CheckoutPrintResult] carrying a code,
  /// because the caller is a sale path and a receipt is not allowed to break
  /// one. A malformed *durable* record is the single exception and is left to
  /// propagate: it means the box cannot be trusted, which is not a printing
  /// problem.
  Future<CheckoutPrintResult> dispatch(
    CheckoutSalePayload sale, {
    required TenantConfiguredPrinter printer,
    String? businessName,
    String? servedBy,
  }) async {
    final prepared = await enqueue(
      sale,
      printer: printer,
      businessName: businessName,
      servedBy: servedBy,
    );
    if (prepared.outcome == CheckoutPrintOutcome.refused) return prepared;
    final job = prepared.job!;
    if (job.state == PrintJobState.printed) {
      // Already sent by an earlier dispatch for the same receipt. Idempotence,
      // arriving from the queue rather than from here.
      return CheckoutPrintResult.sent(job);
    }
    final ran = await _queue.run(job.receiptNumber, transport: _transport);
    return ran.state == PrintJobState.printed
        ? CheckoutPrintResult.sent(ran)
        : CheckoutPrintResult.queued(
            ran,
            ran.attentionReason ?? PrinterTransportCode.unreachable,
          );
  }

  /// Sends a job that already exists — an operator pressing *Send again*.
  ///
  /// Separate from [dispatch] because it must not rebuild the bytes: a receipt
  /// retried after a price change has to print what was **charged**, and the
  /// bytes on the job are the ones the sale produced.
  Future<CheckoutPrintResult> retry(String receiptNumber) async {
    // **Only a *failed* job is returned to `queued`.** `HivePrintJobQueue.retry`
    // refuses any other move with `invalid_transition`, so calling it
    // unconditionally would throw for a job that is merely waiting its turn -
    // which is a state a *Send again* control can easily be pressed in, since
    // the queue and the screen do not share a frame.
    final job = _queue.read(receiptNumber);
    if (job == null) {
      return const CheckoutPrintResult.refused(
        PrinterTransportCode.notConfigured,
      );
    }
    if (job.state == PrintJobState.printed) {
      // Already done. A second copy is `reprint`, which is audited, and this
      // must not become a back door to it.
      return CheckoutPrintResult.sent(job);
    }
    if (job.state == PrintJobState.needsAttention) {
      await _queue.retry(receiptNumber);
    }
    final ran = await _queue.run(receiptNumber, transport: _transport);
    return ran.state == PrintJobState.printed
        ? CheckoutPrintResult.sent(ran)
        : CheckoutPrintResult.queued(
            ran,
            ran.attentionReason ?? PrinterTransportCode.unreachable,
          );
  }
}
