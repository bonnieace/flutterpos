/// Turning what this device is carrying into things a person can read and act
/// on.
///
/// **Pure, and separate from the screen, because the wording is the feature.**
/// The notifications page used to be counts, and a count needs no vocabulary;
/// a list of individual facts needs one sentence per fact and an honest answer
/// about what can be done. Keeping that here means it is tested without
/// pumping a widget, and that the screen stays a layout.
library;

import 'package:flutter/foundation.dart' show ValueKey;

import '../shift/abandoned_shift.dart';
import '../ui/notification_feed.dart';
import '../ui/status.dart';
import 'checkout_evidence.dart';
import 'checkout_print_failures.dart';
import 'checkout_print_jobs.dart';

/// One receipt that has not come out of a printer, as a notification.
///
/// **Per receipt rather than per count**, which is the whole point: *three
/// receipts did not print* cannot be acted on, and this can. The action is
/// offered only where the transport says another attempt could succeed - a
/// printer that is not configured will refuse identically for ever, and a
/// button that cannot work is worse than none.
List<AppNotificationItem> printJobNotifications(
  PrintJobListing listing, {
  required String Function(PrintJobRecord job) sourceLabel,
  required String Function(PrintJobRecord job) timeLabel,
  void Function(PrintJobRecord job)? onRetry,
  String? busyReceiptNumber,
}) {
  final items = <AppNotificationItem>[];
  for (final job in listing.jobs) {
    final reason = job.attentionReason;
    final notice = reason == null ? null : PrinterFailureNotice.of(reason);
    final failed = job.state == PrintJobState.needsAttention;
    final retryable =
        onRetry != null &&
        failed &&
        reason != null &&
        PrinterFailureNotice.isRetryable(reason);
    items.add(
      AppNotificationItem(
        id: 'print-${job.receiptNumber}',
        status: failed
            ? (notice?.status ?? AppStatus.problem)
            : AppStatus.attention,
        title: failed ? 'Receipt did not print' : 'Receipt waiting to print',
        summary: job.receiptNumber,
        // The transport's own words, which are the only thing that says what
        // to go and do about it - switch the printer on, clear the jam.
        detail: notice?.message,
        sourceLabel: sourceLabel(job),
        timeLabel: timeLabel(job),
        busy: busyReceiptNumber == job.receiptNumber,
        actions: <AppNotificationAction>[
          if (retryable)
            AppNotificationAction(
              label: 'Print again',
              actionKey: ValueKey('notification-reprint-${job.receiptNumber}'),
              onPressed: () => onRetry(job),
            ),
        ],
      ),
    );
  }
  return List<AppNotificationItem>.unmodifiable(items);
}

/// A queue this device cannot read at all.
///
/// **Not the same as an empty queue, and never folded into one.** A listing
/// that threw means durable records exist that this build cannot decode, and
/// reporting nothing would tell a shopkeeper every receipt had printed.
AppNotificationItem? unreadablePrintNotification(PrintJobListing listing) {
  if (listing.unreadable <= 0) return null;
  return AppNotificationItem(
    id: 'print-unreadable',
    status: AppStatus.problem,
    title: 'Some receipts could not be read',
    summary:
        '${listing.unreadable} stored ${listing.unreadable == 1 ? 'receipt' : 'receipts'}',
    detail:
        'These were written by a newer version of the app than this device is '
        'running. Update the app on this register and they can be printed.',
  );
}

/// What is still on its way to the server.
///
/// **Aggregated on purpose, and it is the one place here that is.** The outbox
/// reports counts and holds no per-sale listing this surface may read, so a row
/// per sale would be a fiction. One row per state is what the evidence
/// supports: it says how many and what it means, and it does not pretend to
/// name sales it cannot see.
List<AppNotificationItem> checkoutEvidenceNotifications(
  CheckoutEvidenceSummary summary,
) {
  final items = <AppNotificationItem>[];
  final waiting = summary.savedOffline + summary.submitting;
  if (waiting > 0) {
    items.add(
      AppNotificationItem(
        id: 'sales-waiting',
        status: AppStatus.attention,
        title:
            '$waiting ${waiting == 1 ? 'sale is' : 'sales are'} waiting to send',
        summary: 'Saved on this device',
        detail:
            'They are recorded here and will go to the server on their own. '
            'Nothing is lost while this register is offline.',
      ),
    );
  }
  if (summary.awaitingConfirmation > 0) {
    items.add(
      AppNotificationItem(
        id: 'sales-confirming',
        status: AppStatus.info,
        title:
            '${summary.awaitingConfirmation} '
            '${summary.awaitingConfirmation == 1 ? 'sale is' : 'sales are'} '
            'being confirmed',
        summary: 'Sent, awaiting the server',
      ),
    );
  }
  if (summary.needsAttention > 0) {
    items.add(
      AppNotificationItem(
        id: 'sales-attention',
        status: AppStatus.problem,
        title:
            '${summary.needsAttention} '
            '${summary.needsAttention == 1 ? 'sale needs' : 'sales need'} '
            'looking at',
        summary: 'Stored here and not settled',
        detail:
            'The server did not accept these as they were sent. They are still '
            'on this device and have not been lost.',
      ),
    );
  }
  final failures = summary.mutations.failures;
  if (failures > 0) {
    items.add(
      AppNotificationItem(
        id: 'mutations-failed',
        status: AppStatus.problem,
        title:
            '$failures ${failures == 1 ? 'change' : 'changes'} could not be saved',
        summary: 'Stock and catalog edits made on this device',
      ),
    );
  }
  return List<AppNotificationItem>.unmodifiable(items);
}

/// Shifts this business cannot close, for the people who can.
///
/// **The first notification here that is about the business rather than this
/// device**, and it is why the page needed a list at all: a count could never
/// have carried the one thing an owner has to do about it. Only an owner,
/// administrator or manager is ever shown these - a cashier cannot read another
/// cashier's shift, let alone end it.
///
/// **Named by the person, not the shift id.** The row exists so somebody can
/// recognise a colleague whose till was left open, and a document id recognises
/// nobody. The date is what separates two of them.
List<AppNotificationItem> abandonedShiftNotifications(
  List<AbandonedShift> shifts, {
  void Function(AbandonedShift shift)? onClose,
  String? busyShiftId,
}) => List<AppNotificationItem>.unmodifiable(<AppNotificationItem>[
  for (final shift in shifts)
    AppNotificationItem(
      id: 'abandoned-shift-${shift.shiftId}',
      status: AppStatus.problem,
      title:
          '${shift.staffName ?? 'A cashier'} left a shift open and can no '
          'longer close it',
      summary: shift.businessDate,
      detail:
          'Their access to this business ended while the shift was still open, '
          'so neither they nor anybody else can close it from a register. Closing '
          'it here records no takings, because nobody counted that drawer - '
          'the shift is reported as unverifiable rather than as one that took '
          'nothing.',
      busy: busyShiftId == shift.shiftId,
      actions: <AppNotificationAction>[
        if (onClose != null)
          AppNotificationAction(
            label: 'Close this shift',
            destructive: true,
            actionKey: ValueKey('notification-close-shift-${shift.shiftId}'),
            onPressed: () => onClose(shift),
          ),
      ],
    ),
]);
