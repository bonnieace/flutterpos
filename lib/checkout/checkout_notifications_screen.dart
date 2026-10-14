/// One page for everything this device is still carrying, said one fact at a
/// time.
///
/// **Counts became a list on 2026-09-15, at the developer's direction.** What
/// stood here was a headline and two sections of aggregates - *Unprinted
/// receipts 3*, *Sending to the server 2* - each of which opened onto a panel
/// somewhere else to do anything about it. A count is not actionable, and
/// gathering three of them on one page does not make them so. Every row here
/// states one thing that happened and carries whatever can be done about it,
/// which for a receipt that did not print is printing it again.
///
/// **The glyph in the bar is still the only way in, and it is still a badge.**
/// A device holding nothing draws no badge at all, so the page is offered
/// exactly when there is something on it.
///
/// **Not everything can be a row yet, and the page does not pretend.** The
/// checkout outbox reports counts and exposes no per-sale listing this surface
/// may read, so sales are one row per state rather than one per sale. That is
/// the honest shape of the evidence available; see
/// `checkout_notification_sources.dart`, which says so where it builds them.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../shift/abandoned_shift.dart';
import '../ui/notification_feed.dart';
import '../ui/scaffold.dart';
import '../ui/snackbar.dart';
import '../ui/status.dart';
import '../ui/states.dart';
import '../ui/tokens.dart';
import 'checkout_evidence.dart';
import 'checkout_notification_sources.dart';
import 'checkout_print_jobs.dart';
import 'checkout_print_queue_panel.dart';
import '../observability/app_telemetry.dart';

final class TenantNotificationsScreen extends StatelessWidget {
  const TenantNotificationsScreen({
    super.key,
    required this.evidenceSource,
    required this.printQueue,
    required this.tenantId,
    this.refreshSignals,
    this.onRetryPrint,
    this.abandonedShifts,
    this.onCloseAbandonedShift,
  });

  /// This business's shifts that nobody can close, for the roles that may see
  /// them. **Null for a cashier**, and the page then carries only what this
  /// device is holding - which is the whole of what a cashier can act on.
  final Future<List<AbandonedShift>> Function()? abandonedShifts;

  /// Ends one of them. Absent where the session may find them but not close
  /// them, which leaves the row a statement rather than a dead button.
  final Future<void> Function(AbandonedShift shift)? onCloseAbandonedShift;

  final CheckoutEvidenceSource evidenceSource;

  /// Fires when local checkout evidence may have changed.
  final Stream<Object?>? refreshSignals;

  final HivePrintJobQueue printQueue;

  /// Whose receipts to list.
  ///
  /// **Required rather than read from the session scope here.** That box is the
  /// device's and holds the jobs of every business this device has served; a
  /// job records the tenant it was rung for, and until 2026-09-19 nothing read
  /// it, so switching business left this page naming the other shop's receipt
  /// numbers with a *Send again* beside each. Passed in rather than looked up
  /// because the lookup would sit inside the `catch` below, where a missing
  /// scope would hide every receipt instead of saying anything.
  final String tenantId;

  /// While absent the receipts are a read-only statement of what is waiting.
  final PrintJobRetry? onRetryPrint;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Notifications',
    contentWidth: AppContentWidth.records,
    body: CheckoutEvidenceScope(
      source: evidenceSource,
      refreshSignals: refreshSignals,
      builder: (context, summary, {required rereading, onAcknowledge}) => _Page(
        summary: summary,
        printQueue: printQueue,
        tenantId: tenantId,
        onRetryPrint: onRetryPrint,
        abandonedShifts: abandonedShifts,
        onCloseAbandonedShift: onCloseAbandonedShift,
      ),
    ),
  );
}

final class _Page extends StatefulWidget {
  const _Page({
    required this.summary,
    required this.printQueue,
    required this.tenantId,
    required this.onRetryPrint,
    required this.abandonedShifts,
    required this.onCloseAbandonedShift,
  });

  final CheckoutEvidenceSummary summary;
  final HivePrintJobQueue printQueue;

  /// See `TenantNotificationsScreen.tenantId`.
  final String tenantId;
  final PrintJobRetry? onRetryPrint;
  final Future<List<AbandonedShift>> Function()? abandonedShifts;
  final Future<void> Function(AbandonedShift shift)? onCloseAbandonedShift;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  /// The receipt whose reprint is in flight, so its row refuses a second press
  /// while keeping its words. Null when nothing is running.
  String? _retrying;

  /// The shift whose close is in flight, for the same reason.
  String? _closing;

  /// This business's unclosable shifts, once read.
  ///
  /// **Read once per entry to this page rather than on every build.** It is a
  /// query plus a staff lookup per result, against the server, and `build` runs
  /// far more often than the answer changes. Empty until it lands, so the page
  /// draws what this device knows immediately and grows the business's rows
  /// underneath - the same shape every other surface here uses.
  List<AbandonedShift> _abandoned = const <AbandonedShift>[];

  @override
  void initState() {
    super.initState();
    unawaited(_loadAbandoned());
  }

  Future<void> _loadAbandoned() async {
    final read = widget.abandonedShifts;
    if (read == null) return;
    try {
      final found = await read();
      if (mounted) setState(() => _abandoned = found);
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'notifications.abandoned_shifts_read',
      );
      // **Silence, and deliberately.** This is one source among several on a
      // page a person opened to see the others. A business read that fails -
      // offline, a role that changed underneath - must not replace the
      // receipts and sales this device is holding with an error.
      if (mounted) setState(() => _abandoned = const <AbandonedShift>[]);
    }
  }

  Future<void> _closeAbandoned(AbandonedShift shift) async {
    final close = widget.onCloseAbandonedShift;
    if (close == null || _closing != null) return;
    setState(() => _closing = shift.shiftId);
    String? failure;
    try {
      await close(shift);
    } on AbandonedShiftCloseException catch (error) {
      failure = abandonedShiftCloseMessage(error.failure);
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'notifications.abandoned_shift_close',
      );
      failure = abandonedShiftCloseMessage(
        AbandonedShiftCloseFailure.ambiguous,
      );
    }
    if (!mounted) return;
    setState(() => _closing = null);
    if (failure != null) {
      showAppSnackBar(context, AppNotice.refused(failure));
    }
    // Re-read either way: a close that worked removes the row, and one whose
    // outcome was uncertain is settled by asking rather than by assuming.
    await _loadAbandoned();
  }

  Future<void> _retry(PrintJobRecord job) async {
    final retry = widget.onRetryPrint;
    if (retry == null || _retrying != null) return;
    setState(() => _retrying = job.receiptNumber);
    try {
      await retry(job.receiptNumber);
    } finally {
      if (mounted) setState(() => _retrying = null);
    }
  }

  /// **Read on every build rather than held.** The queue is a durable box the
  /// sale path writes to, so a cached listing goes stale behind this page.
  PrintJobListing _listing() {
    try {
      // **Narrowed to the signed-in business.** The queue is the device's, so
      // an unfiltered read lists the receipts of every business this phone has
      // served - and offers to reprint them.
      return widget.printQueue.pending(tenantId: widget.tenantId);
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'notifications.print_queue_read',
      );
      // A queue that cannot be listed is not a queue that is empty. The
      // unreadable count carries that, and this stands in only for a read that
      // failed before any of it could be counted.
      return const PrintJobListing(jobs: <PrintJobRecord>[], unreadable: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final inset = AppScaffold.horizontalInset(tokens.spacing);
    final listing = _listing();
    final items = <AppNotificationItem>[
      ...printJobNotifications(
        listing,
        sourceLabel: (job) => 'Printer ${job.host}',
        timeLabel: (job) => _attempts(job),
        onRetry: widget.onRetryPrint == null ? null : _retry,
        busyReceiptNumber: _retrying,
      ),
      if (unreadablePrintNotification(listing) case final unreadable?)
        unreadable,
      ...checkoutEvidenceNotifications(widget.summary),
      // The business's own, last: a shift somebody else left open is not more
      // urgent than a sale this till is still holding.
      ...abandonedShiftNotifications(
        _abandoned,
        onClose: widget.onCloseAbandonedShift == null ? null : _closeAbandoned,
        busyShiftId: _closing,
      ),
    ];
    // **Nothing waiting is the middle of the page, not the top of it.** An
    // empty feed left the drawing and its sentence hard under the title with
    // the rest of the screen blank beneath, which reads as a list that failed
    // to load rather than as an answer. Centred, it is the answer.
    //
    // Still a scroller, and still the same inset: the illustration and its line
    // are taller than a short viewport in landscape, and a centred child that
    // cannot scroll overflows instead of moving.
    if (items.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          key: const ValueKey('notifications'),
          padding: EdgeInsets.symmetric(horizontal: inset),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: const Center(
              child: EmptyState(
                key: ValueKey('notifications-clear'),
                title: 'No notifications',
                illustration: 'notifications.svg',
              ),
            ),
          ),
        ),
      );
    }
    return ListView(
      key: const ValueKey('notifications'),
      padding: EdgeInsets.fromLTRB(inset, inset, inset, tokens.spacing.s32),
      children: <Widget>[
        SizedBox(height: tokens.spacing.s16),
        AppNotificationFeed(
          key: const ValueKey('notifications-feed'),
          items: items,
        ),
      ],
    );
  }

  /// How hard this device has already tried, which is the only time this page
  /// can honestly state: a print job records attempts, not a wall clock a
  /// person would recognise.
  String _attempts(PrintJobRecord job) => switch (job.attemptCount) {
    0 => 'Not tried yet',
    1 => 'Tried once',
    final count => 'Tried $count times',
  };
}
