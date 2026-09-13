/// One page for everything this device is still carrying.
///
/// **Two readouts that were in three places, gathered on 2026-09-03 at the
/// product owner's direction.** The local work counts hung off the top bar's
/// glyph as a 320-wide panel; the unprinted receipts were a tile in the home's
/// grid, between *Sales* and *Inventory*, competing with the things a shop
/// opens the app to do. Neither is a destination in that sense: both are
/// answers to *what has not gone through yet*, which is one question and now
/// one page.
///
/// **The glyph in the bar is the only way in, and it is a badge.** A device
/// holding nothing draws no badge at all, so the page is offered exactly when
/// there is something on it - which is the rule `SyncIndicator` already keeps
/// and the reason the grid tile could go.
///
/// **It opens on the answer, 2026-09-04.** The page was a heading, a card of
/// twelve `label ....... 0` rows, a folded paragraph about policy, and a
/// three-line note about which device the queue belongs to - four things to
/// read before the one fact a person came for. It leads with that fact now:
/// how much is waiting, in one line, with the detail underneath for whoever
/// wants it.
library;

import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../ui/scaffold.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'checkout_evidence.dart';
import 'checkout_print_jobs.dart';
import 'checkout_print_queue_panel.dart';

final class TenantNotificationsScreen extends StatelessWidget {
  const TenantNotificationsScreen({
    super.key,
    required this.evidenceSource,
    required this.printQueue,
    this.refreshSignals,
    this.onRetryPrint,
  });

  final CheckoutEvidenceSource evidenceSource;

  /// Fires when local checkout evidence may have changed.
  final Stream<Object?>? refreshSignals;

  final HivePrintJobQueue printQueue;

  /// While absent the receipts are a read-only statement of what is waiting.
  final PrintJobRetry? onRetryPrint;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Notifications',
    // §4.2's record-list row: the larger half of this page is a list of
    // receipts.
    contentWidth: AppContentWidth.records,
    body: CheckoutEvidenceScope(
      source: evidenceSource,
      refreshSignals: refreshSignals,
      builder: (context, summary, {required rereading, onAcknowledge}) => _Page(
        summary: summary,
        rereading: rereading,
        onAcknowledge: onAcknowledge,
        printQueue: printQueue,
        onRetryPrint: onRetryPrint,
      ),
    ),
  );
}

final class _Page extends StatelessWidget {
  const _Page({
    required this.summary,
    required this.rereading,
    required this.onAcknowledge,
    required this.printQueue,
    required this.onRetryPrint,
  });

  final CheckoutEvidenceSummary summary;
  final bool rereading;
  final Future<void> Function(String operationId)? onAcknowledge;
  final HivePrintJobQueue printQueue;
  final PrintJobRetry? onRetryPrint;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final inset = AppScaffold.horizontalInset(tokens.spacing);
    // **Read on every build rather than held.** The queue is a durable box the
    // sale path writes to, so a cached listing goes stale behind this page.
    final receipts = _listing();
    final waiting = checkoutWaitingCount(summary);
    final unprinted = receipts.jobs.length;
    final failed = receipts.jobs
        .where((job) => job.state == PrintJobState.needsAttention)
        .length;
    final clear = waiting == 0 && unprinted == 0 && receipts.unreadable == 0;
    return ListView(
      key: const ValueKey('notifications'),
      padding: EdgeInsets.fromLTRB(inset, inset, inset, tokens.spacing.s32),
      children: <Widget>[
        _Headline(
          waiting: waiting,
          unprinted: unprinted,
          unreadable: receipts.unreadable,
          needsAttention: summary.needsAttention + summary.mutations.failures,
          failedPrints: failed,
        ),
        // **A clear device is one statement, not three.** The sections below
        // are lists, and both of them empty is the same news the headline just
        // gave - *Everything has gone through*, then *No receipts are
        // waiting*, then *No local work is stored on this device* was one fact
        // said three ways down an otherwise blank page. The drawing takes their
        // place; the moment either list has something in it, both come back.
        if (clear) ...<Widget>[
          SizedBox(height: tokens.spacing.s16),
          const EmptyState(
            key: ValueKey('notifications-clear'),
            title: 'Nothing is waiting',
            hint:
                'Every sale and every receipt on this device has gone '
                'through.',
            illustration: 'approve.svg',
          ),
        ] else ...<Widget>[
          SizedBox(height: tokens.spacing.s32),
          _Section(
            label: 'Unprinted receipts',
            count: unprinted,
            child: TenantPrintQueuePanel(
              key: const ValueKey('notifications-print-queue'),
              queue: printQueue,
              onRetry: onRetryPrint,
            ),
          ),
          SizedBox(height: tokens.spacing.s32),
          _Section(
            label: 'Sending to the server',
            count: waiting,
            child: CheckoutLocalWorkPanel(
              key: const ValueKey('notifications-local-work'),
              summary: summary,
              rereading: rereading,
              onAcknowledge: onAcknowledge,
            ),
          ),
        ],
      ],
    );
  }

  PrintJobListing _listing() {
    try {
      return printQueue.pending();
    } catch (_) {
      // A queue that cannot be listed is not a queue that is empty. The panel
      // below states that; the headline simply does not count it.
      return const PrintJobListing(jobs: <PrintJobRecord>[], unreadable: 0);
    }
  }
}

/// The one fact this page exists to state, before anything else on it.
///
/// **A sentence and a figure, not a card of twelve zeroes.** A person opens
/// this because a badge told them something was waiting; the first line answers
/// how much and of what kind, and the sections underneath say which.
final class _Headline extends StatelessWidget {
  const _Headline({
    required this.waiting,
    required this.unprinted,
    required this.unreadable,
    required this.needsAttention,
    required this.failedPrints,
  });

  final int waiting;
  final int unprinted;
  final int unreadable;
  final int needsAttention;
  final int failedPrints;

  /// `problem` where something needs a person, `attention` where something is
  /// merely still moving, `ok` where the device is clear. Never `info`: this is
  /// a standing, and §2.1's `info` is for a notice.
  AppStatus get _status {
    if (needsAttention > 0 || failedPrints > 0 || unreadable > 0) {
      return AppStatus.problem;
    }
    return waiting + unprinted == 0 ? AppStatus.ok : AppStatus.attention;
  }

  String get _heading {
    final total = waiting + unprinted;
    if (total == 0) return 'Everything has gone through';
    return total == 1 ? '1 thing is waiting' : '$total things are waiting';
  }

  /// What the figure is made of, in the shopkeeper's own nouns.
  String get _detail {
    final parts = <String>[
      if (waiting > 0)
        waiting == 1 ? '1 sale or change' : '$waiting sales and changes',
      if (unprinted > 0) unprinted == 1 ? '1 receipt' : '$unprinted receipts',
    ];
    if (unreadable > 0) {
      parts.add(
        unreadable == 1
            ? '1 receipt that could not be read'
            : '$unreadable receipts that could not be read',
      );
    }
    if (parts.isEmpty) {
      return 'Nothing here is waiting to be sent or printed.';
    }
    final made = parts.join(' and ');
    if (needsAttention > 0 || failedPrints > 0 || unreadable > 0) {
      return '$made. Some of them need you.';
    }
    return '$made. They are being sent on their own.';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final role = _status.role(tokens);
    return DecoratedBox(
      key: const ValueKey('notifications-headline'),
      decoration: BoxDecoration(
        color: role.bg,
        border: Border.all(color: role.border),
        borderRadius: BorderRadius.circular(tokens.radius.lg),
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.s20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                color: role.border,
                borderRadius: BorderRadius.circular(tokens.radius.md),
              ),
              child: Padding(
                padding: EdgeInsets.all(tokens.spacing.s12),
                child: Icon(
                  _status.defaultIcon,
                  size: AppButton.prominentIconSize,
                  color: role.fg,
                ),
              ),
            ),
            SizedBox(width: tokens.spacing.s16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    _heading,
                    key: const ValueKey('notifications-heading'),
                    style: tokens.typography.titleLarge.copyWith(
                      color: role.fg,
                    ),
                  ),
                  SizedBox(height: tokens.spacing.s4),
                  Text(
                    _detail,
                    style: tokens.density
                        .body(tokens.typography)
                        .copyWith(color: tokens.colors.text.secondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A section heading that carries its own count.
///
/// **The count is on the heading rather than inside the section**, which is
/// what lets the page be scanned without being read: somebody looking for the
/// receipts finds *UNPRINTED RECEIPTS 3* and stops there.
final class _Section extends StatelessWidget {
  const _Section({
    required this.label,
    required this.count,
    required this.child,
  });

  final String label;
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                // §2.2's `label.eyebrow`, the one role allowed uppercase and
                // the one this app uses for a band above content.
                style: tokens.typography.labelEyebrow.copyWith(
                  color: tokens.colors.text.tertiary,
                ),
              ),
            ),
            if (count > 0)
              Text(
                '$count',
                style: tokens.typography.numericBody.copyWith(
                  color: tokens.colors.text.secondary,
                ),
              ),
          ],
        ),
        Divider(
          height: tokens.spacing.s16,
          color: tokens.colors.surface.cardEdge,
        ),
        child,
      ],
    );
  }
}
