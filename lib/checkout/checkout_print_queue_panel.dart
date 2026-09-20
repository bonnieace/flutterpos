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

import '../ui/buttons.dart';
import '../ui/snackbar.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'checkout_print_failures.dart';
import 'checkout_print_jobs.dart';
import 'checkout_print_transport_base.dart';

/// Sends one already-queued receipt again. Returns a
/// [PrinterTransportCode] when it still did not arrive, or null when it did.
typedef PrintJobRetry = Future<String?> Function(String receiptNumber);

/// The receipts, as a section rather than as a screen.
///
/// **It had a screen of its own until 2026-09-03**, reached from a tile in the
/// home's grid. Both are gone: a receipt that did not print is one of the
/// things this device still owes, so it is a section of the notifications page
/// the top bar's glyph opens, beside the sales that have not been sent.
///
/// **While absent, [onRetry] leaves the queue a read-only statement of what is
/// waiting.** Every other injected capability in this app behaves the same way.
final class TenantPrintQueuePanel extends StatefulWidget {
  const TenantPrintQueuePanel({
    super.key,
    required this.queue,
    required this.tenantId,
    this.onRetry,
  });

  final HivePrintJobQueue queue;

  /// Whose receipts these are.
  ///
  /// **Required rather than inferred, because the queue cannot infer it.**
  /// That box is the device's and holds the jobs of every business this device
  /// has served, keyed by receipt number; a job records the tenant it was rung
  /// for, and until 2026-09-19 nothing read it. A caller that does not say
  /// whose receipts it wants would get all of them, with a *Send again* beside
  /// each - so this asks rather than defaulting.
  final String tenantId;

  final PrintJobRetry? onRetry;

  @override
  State<TenantPrintQueuePanel> createState() => _TenantPrintQueuePanelState();
}

class _TenantPrintQueuePanelState extends State<TenantPrintQueuePanel> {
  String? _sending;

  /// Reports one write outcome, over the screen rather than inside the page.
  ///
  /// See `showAppSnackBar`: since 2026-09-03 every outcome goes there, and
  /// inline text is left to the one thing it is still right for - a field
  /// saying what is wrong with what was typed into it.
  void _report(AppNotice notice) => showAppSnackBar(context, notice);

  /// **Read on every build rather than held in a field.** The queue is a
  /// durable box that the sale path and the recovery pass both write to, so a
  /// cached list would go stale the moment a sale was rung up behind this
  /// screen. It is a synchronous read of an open box, not a query.
  ///
  /// **Narrowed to [TenantPrintQueuePanel.tenantId]**, because that box is the
  /// device's and holds the jobs of every business this device has served. See
  /// `HivePrintJobQueue.pending`.
  PrintJobListing get _listing =>
      widget.queue.pending(tenantId: widget.tenantId);

  Future<void> _retry(PrintJobRecord job) async {
    final onRetry = widget.onRetry;
    if (onRetry == null || _sending != null) return;
    setState(() {
      _sending = job.receiptNumber;
    });
    try {
      final failure = await onRetry(job.receiptNumber);
      if (!mounted) return;
      _report(
        failure == null
            ? PrinterFailureNotice.sent
            : PrinterFailureNotice.of(failure),
      );
    } finally {
      if (mounted) setState(() => _sending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final listing = _listing;
    // **One cause, said once.** Every receipt in a queue has usually failed
    // for the same reason - the printer is off, or it moved - and repeating
    // *The printer did not answer. Check it is switched on and on this
    // network.* under each of them turned a list of receipts into a stack of
    // identical paragraphs, which is what made this look like a generic feed.
    // Where the reasons differ, each row carries its own.
    final reasons = listing.jobs
        .where((job) => job.state == PrintJobState.needsAttention)
        .map((job) => job.attentionReason)
        .whereType<String>()
        .toSet();
    final shared = reasons.length == 1 ? reasons.single : null;
    return Column(
      // **No padding and no scroller of its own.** This is a section of a page
      // that already insets and already scrolls; its own `SingleChildScrollView`
      // inside that page's `ListView` was a scrollable in a scrollable, and its
      // own inset was what pushed the receipts in from the band label above
      // them so that they read as a nested panel rather than as this section's
      // content.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (listing.unreadable > 0) ...<Widget>[
          Callout(
            key: const ValueKey('print-queue-unreadable'),
            status: AppStatus.problem,
            message: listing.unreadable == 1
                ? '1 queued receipt could not be read. It was not sent.'
                : '${listing.unreadable} queued receipts could not be read. '
                      'They were not sent.',
          ),
          SizedBox(height: tokens.spacing.s16),
        ],
        // **One line, not an `EmptyState`.** This is a section of the
        // notifications page rather than a screen, and a 168-pixel drawing
        // with a title and a hint under it pushed the counts that *are* full
        // most of a screen down. The page draws one picture, for the case
        // where nothing at all is waiting; a section that happens to be
        // empty says so and gets out of the way.
        if (listing.jobs.isEmpty)
          Text(
            key: const ValueKey('print-queue-empty'),
            'No receipts are waiting.',
            style: tokens.density
                .body(tokens.typography)
                .copyWith(color: tokens.colors.text.secondary),
          )
        else ...<Widget>[
          if (shared != null) ...<Widget>[
            _SharedCause(reason: shared),
            SizedBox(height: tokens.spacing.s16),
          ],
          for (final job in listing.jobs)
            _ReceiptRow(
              job: job,
              canSend: widget.onRetry != null,
              sending: _sending == job.receiptNumber,
              showReason: shared == null,
              onRetry: _sending != null ? null : () => _retry(job),
            ),
        ],
        // **The scope, once, at the foot.** It was a three-line paragraph at
        // the top, above everything a person opened this for; it is a fact
        // about the list rather than an introduction to it, so it goes where
        // a footnote goes. Stated even when the queue is empty, because the
        // scope is true then too.
        SizedBox(height: tokens.spacing.s12),
        Text(
          key: const ValueKey('print-queue-scope'),
          'This queue is on this device only, and a receipt here is already '
          'a recorded sale.',
          style: tokens.typography.caption.copyWith(
            color: tokens.colors.text.tertiary,
          ),
        ),
      ],
    );
  }
}

/// Why none of them came out, stated above the list instead of inside it.
final class _SharedCause extends StatelessWidget {
  const _SharedCause({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final role = AppStatus.problem.role(tokens);
    return Row(
      key: const ValueKey('print-queue-shared-cause'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          AppStatus.problem.defaultIcon,
          size: StatusBadge.iconSize,
          color: role.fg,
        ),
        SizedBox(width: tokens.spacing.s8),
        Expanded(
          child: Text(
            PrinterFailureNotice.of(reason).message,
            style: tokens.density
                .body(tokens.typography)
                .copyWith(color: tokens.colors.text.secondary),
          ),
        ),
      ],
    );
  }
}

/// One receipt that has not come out, drawn as a receipt.
///
/// **Not a card, and that is the point of the redraw on 2026-09-04.** Each job
/// was a bordered box holding a glyph, a number, a badge, a repeated sentence,
/// an address and a button - six things, boxed, stacked, and identical to the
/// box above it. A queue of two filled a phone. It reads as a torn-off slip
/// now: a rule down the left in the standing's colour, the number in the type
/// a till roll prints, and everything else on one line under it.
///
/// The number is the subject because it is the only part that differs between
/// two receipts, and it is what somebody holding a roll of paper is comparing.
final class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({
    required this.job,
    required this.canSend,
    required this.sending,
    required this.showReason,
    required this.onRetry,
  });

  final PrintJobRecord job;

  /// Whether this build can send a receipt again at all.
  ///
  /// **Separate from [onRetry], and the difference is what gets drawn.** A
  /// build with no transport offers no control; a build that has one draws it
  /// on every row and **disables** it where a retry could not work - §5's
  /// matrix has a `disabled` row, and a control that vanishes tells a person
  /// nothing about why.
  final bool canSend;

  final bool sending;

  /// False when every receipt failed the same way and the section said so once.
  final bool showReason;

  /// Null while another receipt is already going.
  final VoidCallback? onRetry;

  bool get _failed => job.state == PrintJobState.needsAttention;

  AppStatus get _status => _failed ? AppStatus.problem : AppStatus.attention;

  String get _standing => switch (job.state) {
    PrintJobState.queued => 'Waiting',
    PrintJobState.printing => 'Sending',
    PrintJobState.needsAttention => 'Not sent',
    // Never listed - `pending()` filters it - but a `switch` that could not
    // name it would be a `switch` with a hole in it.
    PrintJobState.printed => 'Sent',
  };

  /// A retry that cannot possibly work is not offered: `printer_not_configured`
  /// needs a setting and `transport_unsupported` needs a different device.
  bool get _retryable {
    final reason = job.attentionReason;
    return _failed &&
        reason != null &&
        PrinterFailureNotice.isRetryable(reason);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final role = _status.role(tokens);
    final reason = job.attentionReason;
    return Padding(
      key: ValueKey('print-queue-${job.receiptNumber}'),
      padding: EdgeInsets.only(bottom: tokens.spacing.s16),
      // The rule runs the height of the slip, and a `Row` in a `Column` is
      // given unbounded height - so `stretch` needs something to stretch to.
      // The audit log's timeline rail is built the same way.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // The standing as a rule down the edge of the slip. §9 is answered
            // by the word beside it, not by this - the colour is the echo.
            SizedBox(
              width: _railWidth,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: role.fg,
                  borderRadius: BorderRadius.circular(tokens.radius.sm),
                ),
              ),
            ),
            SizedBox(width: tokens.spacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    job.receiptNumber,
                    // §2.2's `mono`: "record IDs ... strings a person compares
                    // character by character", which is exactly what somebody
                    // holding a till roll is doing.
                    style: tokens.typography.mono.copyWith(
                      color: tokens.colors.text.primary,
                    ),
                  ),
                  SizedBox(height: tokens.spacing.s4),
                  Row(
                    children: <Widget>[
                      Text(
                        _standing,
                        key: ValueKey(
                          'print-queue-status-${job.receiptNumber}',
                        ),
                        style: tokens.typography.labelMedium.copyWith(
                          color: role.fg,
                        ),
                      ),
                      SizedBox(width: tokens.spacing.s8),
                      Expanded(
                        child: Text(
                          // **The address is on the job, not on the settings**,
                          // so a receipt queued before the printer moved still
                          // says where it was going.
                          key: ValueKey(
                            'print-queue-endpoint-${job.receiptNumber}',
                          ),
                          '${job.endpoint} - ${job.attemptCount} '
                          '${job.attemptCount == 1 ? 'try' : 'tries'}',
                          overflow: TextOverflow.ellipsis,
                          style: tokens.typography.caption.copyWith(
                            color: tokens.colors.text.tertiary,
                          ),
                        ),
                      ),
                      if (canSend) ...<Widget>[
                        SizedBox(width: tokens.spacing.s8),
                        AppButton(
                          key: ValueKey(
                            'print-queue-retry-${job.receiptNumber}',
                          ),
                          label: sending ? 'Sending' : 'Send again',
                          size: AppButtonSize.sm,
                          loading: sending,
                          onPressed: _retryable && !sending ? onRetry : null,
                        ),
                      ],
                    ],
                  ),
                  if (showReason && _failed && reason != null) ...<Widget>[
                    SizedBox(height: tokens.spacing.s4),
                    Text(
                      PrinterFailureNotice.of(reason).message,
                      style: tokens.density
                          .body(tokens.typography)
                          .copyWith(color: tokens.colors.text.secondary),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The width of the standing rule. Named for the reason
  /// `EmptyState.markSize` is: `design.md` states no such value, and a rule is
  /// neither spacing nor a radius.
  static const double _railWidth = 3;
}
