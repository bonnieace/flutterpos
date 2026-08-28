/// What a person sees when a receipt did not print.
///
/// **The last of printing's three surfaces, and the one that makes a failure
/// actionable rather than merely recorded.** The queue has held failed jobs
/// with their reasons since 2026-08-17; until this screen existed the only way
/// to know a receipt had not come out was to notice the paper.
///
/// **Every sentence here comes from `checkout_print_failures.dart`.** The eight
/// codes are mapped once, at the UI edge, and this screen invents none of its
/// own — it decides only *where* they appear and what is attached to them.
///
/// **It states what it could not read.** `HivePrintJobQueue.pending()` returns
/// the jobs it could parse **and** a count of the durable records it could not,
/// because a screen showing only the first would render an empty queue for a
/// box holding one corrupt record and nine good ones. That is the same shape
/// the profit display uses: never a figure that quietly excludes what it left
/// out.
library;

import 'package:flutter/material.dart';

import '../ui/record_list.dart';
import '../ui/scaffold.dart';
import '../ui/states.dart';
import '../ui/snackbar.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'checkout_print_failures.dart';
import 'checkout_print_jobs.dart';
import 'checkout_print_transport_base.dart';

/// Sends one already-queued receipt again. Returns a
/// [PrinterTransportCode] when it still did not arrive, or null when it did.
typedef PrintJobRetry = Future<String?> Function(String receiptNumber);

final class TenantPrintQueueScreen extends StatelessWidget {
  const TenantPrintQueueScreen({super.key, required this.queue, this.onRetry});

  final HivePrintJobQueue queue;

  /// While absent, the queue is a read-only statement of what is waiting. Every
  /// other injected capability in this app behaves the same way.
  final PrintJobRetry? onRetry;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Unprinted receipts',
    // §4.2's record-list row: this is a list of records.
    contentWidth: AppContentWidth.records,
    body: TenantPrintQueuePanel(queue: queue, onRetry: onRetry),
  );
}

final class TenantPrintQueuePanel extends StatefulWidget {
  const TenantPrintQueuePanel({super.key, required this.queue, this.onRetry});

  final HivePrintJobQueue queue;
  final PrintJobRetry? onRetry;

  @override
  State<TenantPrintQueuePanel> createState() => _TenantPrintQueuePanelState();
}

class _TenantPrintQueuePanelState extends State<TenantPrintQueuePanel> {
  String? _sending;
  AppNotice? _notice;

  /// Reports one write outcome, on the surface its kind belongs to.
  ///
  /// See `noticeIsTransient`: a confirmation withdraws itself, and everything
  /// that names a next step stays where it was drawn.
  void _report(AppNotice notice) {
    if (noticeIsTransient(notice)) {
      showAppSnackBar(context, notice);
      return;
    }
    setState(() => _notice = notice);
  }


  /// **Read on every build rather than held in a field.** The queue is a
  /// durable box that the sale path and the recovery pass both write to, so a
  /// cached list would go stale the moment a sale was rung up behind this
  /// screen. It is a synchronous read of an open box, not a query.
  PrintJobListing get _listing => widget.queue.pending();

  Future<void> _retry(PrintJobRecord job) async {
    final onRetry = widget.onRetry;
    if (onRetry == null || _sending != null) return;
    setState(() {
      _sending = job.receiptNumber;
      _notice = null;
    });
    try {
      final failure = await onRetry(job.receiptNumber);
      if (!mounted) return;
      _report(failure == null
            ? PrinterFailureNotice.sent
            : PrinterFailureNotice.of(failure));
    } finally {
      if (mounted) setState(() => _sending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final listing = _listing;
    return SingleChildScrollView(
      padding: EdgeInsets.all(AppScaffold.horizontalInset(tokens.spacing)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // **Phase 08's third criterion, which nothing on this screen said.**
          // The queue is a Hive box on this handset, so a receipt waiting here
          // is waiting on *this* device and no colleague's phone will show it or
          // clear it. The screen opened straight into its callouts and its list,
          // and "2 receipts waiting" with no scope reads as the business's queue.
          //
          // §2.2's `caption` in `text.tertiary`, which is the weight the till
          // gives the same kind of standing fact, and stated unconditionally:
          // the scope is true when the queue is empty too, and a line that
          // appears only when something is wrong is a line no capture covers.
          Text(
            key: const ValueKey('print-queue-scope'),
            'This queue is on this device only. Another device does not show '
            'or clear these receipts, and a receipt here is already a recorded '
            'sale.',
            style: tokens.typography.caption.copyWith(
              color: tokens.colors.text.tertiary,
            ),
          ),
          SizedBox(height: tokens.spacing.s16),
          if (listing.unreadable > 0) ...<Widget>[
            Callout(
              key: const ValueKey('print-queue-unreadable'),
              status: AppStatus.problem,
              message: listing.unreadable == 1
                  ? '1 queued receipt could not be read and is not listed '
                        'below. It was not sent, and nothing else was affected.'
                  : '${listing.unreadable} queued receipts could not be read '
                        'and are not listed below. They were not sent, and '
                        'nothing else was affected.',
            ),
            SizedBox(height: tokens.spacing.s16),
          ],
          if (_notice case final answer?) ...<Widget>[
            Callout(
              key: const ValueKey('print-queue-notice'),
              status: answer.status,
              message: answer.message,
            ),
            SizedBox(height: tokens.spacing.s16),
          ],
          RecordList(
            key: const ValueKey('print-queue-list'),
            identityLabel: 'Receipt',
            empty: const EmptyState(
              key: ValueKey('print-queue-empty'),
              title: 'No receipts are waiting',
              hint:
                  'A receipt appears here only if it did not reach the '
                  'printer.',
            ),
            items: <RecordItem>[for (final job in listing.jobs) _item(job)],
          ),
        ],
      ),
    );
  }

  RecordItem _item(PrintJobRecord job) {
    final failed = job.state == PrintJobState.needsAttention;
    final reason = job.attentionReason;
    // A retry that cannot possibly work is not offered: `printer_not_configured`
    // needs a setting and `transport_unsupported` needs a different device.
    final retryable =
        failed && reason != null && PrinterFailureNotice.isRetryable(reason);
    return RecordItem(
      id: job.receiptNumber,
      recordKey: ValueKey('print-queue-${job.receiptNumber}'),
      title: job.receiptNumber,
      subtitle: failed && reason != null
          ? PrinterFailureNotice.of(reason).message
          : null,
      status: RecordStatus(
        // §9: a status is a container, a glyph and a **word**, never a colour.
        status: failed ? AppStatus.problem : AppStatus.attention,
        label: switch (job.state) {
          PrintJobState.queued => 'Waiting',
          PrintJobState.printing => 'Sending',
          PrintJobState.needsAttention => 'Not sent',
          // Never listed - `pending()` filters it - but a `switch` that could
          // not name it would be a `switch` with a hole in it.
          PrintJobState.printed => 'Sent',
        },
        badgeKey: ValueKey('print-queue-status-${job.receiptNumber}'),
      ),
      attributes: <RecordAttribute>[
        RecordAttribute(
          label: 'Printer',
          value: job.endpoint.toString(),
          // **The address is on the job, not on the settings**, so a receipt
          // queued before the printer moved still shows where it is going.
          valueKey: ValueKey('print-queue-endpoint-${job.receiptNumber}'),
        ),
        RecordAttribute(
          kind: RecordValueKind.code,
          label: 'Tries',
          value: '${job.attemptCount}',
          // Dropped from the narrow form: a phone has room for the receipt,
          // its status and the way out, and the attempt count is the least of
          // the three.
          inNarrowForm: false,
        ),
      ],
      actions: <RecordAction>[
        if (widget.onRetry != null)
          RecordAction(
            label: _sending == job.receiptNumber ? 'Sending' : 'Send again',
            actionKey: ValueKey('print-queue-retry-${job.receiptNumber}'),
            onPressed: retryable && _sending == null ? () => _retry(job) : null,
          ),
      ],
    );
  }
}
