/// The record vocabulary the four reconciliation surfaces speak.
///
/// The day page, the one-run page, the differences list and the stock route all
/// describe the server's own reconciliation records, and three of those four had
/// written their own words for them. The wording lives here rather than in any
/// one of them for the same reason `stock_movement_labels.dart` exists: two
/// copies of "No time was recorded for this difference" is two chances to change
/// one and not the other, and they are in the same domain describing the same
/// documents, which is what makes sharing right here and wrong between domains.
///
/// **What this module found is a divergence rather than a defect of either
/// screen.** The differences list described *all three* stock kinds with the
/// stock-variance sentence, so a broken checkpoint chain whose quantities happen
/// to agree read as "0 fewer than the ledger accounts for" — a record that
/// exists because there is a difference, stating that there is none. The stock
/// route had the right words for all three and the list had never been given
/// them. It also formatted the same instant two ways: `toIso8601String()` on a
/// difference and `2026-08-01 02:30 UTC` on a run, on pages that link to each
/// other.
///
/// **What is deliberately not here** is what a screen can *do* about a record.
/// The stock route's "an adjustment recorded below is how this is put right"
/// names a form three inches down its own page; that is the screen's sentence
/// and it stays at the call site.
library;

import '../ui/status.dart';
import 'reconciliation_anomalies.dart';
import 'reconciliation_status.dart';

/// One instant format for the whole family.
///
/// A run ID carries no time and a difference is addressed by what it is about,
/// so on every one of these surfaces the recorded instants are the only ordering
/// a person has. Minute precision to the second is what the run card has always
/// shown; the seconds and milliseconds an ISO string carries are noise on a
/// nightly sweep.
String reconciliationInstant(DateTime value) {
  final utc = value.toUtc();
  String pad(int part) => part.toString().padLeft(2, '0');
  return '${utc.year}-${pad(utc.month)}-${pad(utc.day)} '
      '${pad(utc.hour)}:${pad(utc.minute)} UTC';
}

// ---------------------------------------------------------------------------
// A reconciliation run
// ---------------------------------------------------------------------------

/// A run's standing, as one of `design.md` §2.1's five statuses.
///
/// **A run has one, and that is the lookup rather than a habit.** §2.1 gives
/// "reconciled" to `ok`, "pending, awaiting" to `attention` and "difference
/// found, unreadable" to `problem`, and a page of runs genuinely mixes all
/// three — so unlike a page of differences, where every row is a difference
/// found, a badge here carries signal.
///
/// **`failed` and `quarantined` are both `problem`, and that is not a
/// collision.** §2.1 has no row for "failed, but a retry is scheduled", and
/// §2.1's own design is a container plus an icon plus a **word**: two states
/// sharing a colour while differing in the word is the system working. What
/// separates them is [reconciliationRunStatusDetail].
///
/// **`other` is `info`, following the day page's own decision** rather than
/// §2.1's "unreadable" row: a server deploy that records a state this app does
/// not model is not evidence of anything wrong, and painting it red would
/// invent in colour an answer the code refuses to invent in words.
AppStatus reconciliationRunStatus(TenantReconciliationRun run) =>
    switch (run.status) {
      TenantReconciliationRunStatus.completed => AppStatus.ok,
      TenantReconciliationRunStatus.queued => AppStatus.attention,
      TenantReconciliationRunStatus.running => AppStatus.attention,
      TenantReconciliationRunStatus.failed => AppStatus.problem,
      TenantReconciliationRunStatus.quarantined => AppStatus.problem,
      TenantReconciliationRunStatus.other => AppStatus.info,
    };

/// The badge's word. Sentence case per §8, and short enough that a badge stays
/// one line on a phone - the detail line below it is where the rest goes.
String reconciliationRunStatusWord(TenantReconciliationRun run) =>
    switch (run.status) {
      TenantReconciliationRunStatus.completed => 'Completed',
      TenantReconciliationRunStatus.queued => 'Queued',
      TenantReconciliationRunStatus.running => 'Running',
      TenantReconciliationRunStatus.failed => 'Failed',
      TenantReconciliationRunStatus.quarantined => 'Stopped',
      TenantReconciliationRunStatus.other => 'Unrecognised',
    };

/// What the badge's word leaves out, or null when it leaves nothing out.
///
/// Four of the six enum labels *are* the word above, so restating them beside
/// the badge would be the duplication §2.1's container exists to avoid. Two say
/// more than a word can - a retry is scheduled, or the server gave up after
/// repeated failures - and for an unmodelled state the stored value itself is
/// the only honest detail. Nothing here is invented: it is the enum's own label,
/// shown only where it is longer than the word.
String? reconciliationRunStatusDetail(TenantReconciliationRun run) {
  if (run.status == TenantReconciliationRunStatus.other) return run.statusValue;
  final label = run.status.label;
  return label == reconciliationRunStatusWord(run) ? null : label;
}

// ---------------------------------------------------------------------------
// A recorded difference
// ---------------------------------------------------------------------------

/// The §2.1 status a difference's container carries.
///
/// **A difference has no *standing*, and that is the same rule the `RecordList`
/// sweep applied to four record families.** §2.1 gives "difference found" to
/// `problem`, and every record on any of these surfaces is a difference the
/// server found and could not resolve - so a badge on each of them would be a
/// list with no signal in it. What the status is for is the container a notice
/// is drawn in, where the block itself is the exception on a page about
/// something else.
const AppStatus reconciliationDifferenceStatus = AppStatus.problem;

/// What kind of difference this is.
///
/// An unmodelled kind is shown verbatim rather than hidden: a server deploy that
/// records a new kind is not evidence of anything wrong, and hiding a real
/// difference would be far worse than naming it plainly.
String reconciliationDifferenceKindLabel(TenantReconciliationAnomaly anomaly) =>
    anomaly.kind == TenantReconciliationAnomalyKind.other
    ? 'Unrecognised difference: ${anomaly.kindValue}'
    : anomaly.kind.label;

/// What the difference is about.
///
/// The identity is the ID the rest of the app attributes by, so it is always
/// shown rather than resolved to a name.
String reconciliationDifferenceSubject(TenantReconciliationAnomaly anomaly) {
  if (anomaly.productId case final productId?) return 'Product $productId';
  if (anomaly.shiftId case final shiftId?) return 'Shift $shiftId';
  if (anomaly.saleId case final saleId?) return 'Sale $saleId';
  return 'This business';
}

/// The figures the record itself carries, stated and never recomputed.
///
/// **One sentence per kind, which is the whole point of this function.** The
/// model refuses a record that cannot explain its own difference - all three
/// stock kinds carry the expected quantity, the observed quantity and a variance
/// that is exactly their difference - so every branch below reads figures the
/// record is guaranteed to hold.
String reconciliationDifferenceFigures(TenantReconciliationAnomaly anomaly) =>
    switch (anomaly.kind) {
      TenantReconciliationAnomalyKind.invalidSaleLines => _saleLines(anomaly),
      TenantReconciliationAnomalyKind.invalidProductQuantity =>
        'This product\'s recorded quantity could not be read as a whole '
            'number, so its stock was not verified at all.',
      // Not the variance sentence. The chain is what makes the expected
      // quantity trustworthy, so a broken chain is a statement about the
      // starting point rather than about a disagreement - and the variance on
      // one of these records may legitimately be zero.
      TenantReconciliationAnomalyKind.checkpointChainInvalid =>
        'The tamper-evident chain of checks behind this product does not join '
            'up, so the expected quantity of ${anomaly.expectedQuantity} '
            'cannot be trusted as a starting point. This is not a quantity '
            'disagreement.',
      TenantReconciliationAnomalyKind.invalidStockMovement =>
        'A movement in this product\'s ledger could not be read, so the '
            'expected quantity of ${anomaly.expectedQuantity} does not account '
            'for everything that moved.',
      TenantReconciliationAnomalyKind.stockVariance => _stockVariance(anomaly),
      TenantReconciliationAnomalyKind.invalidOrMissingShift =>
        'The shift is missing, or did not record the totals a comparison '
            'needs, so no difference could be measured.',
      TenantReconciliationAnomalyKind.shiftVariance => _shiftVariance(anomaly),
      TenantReconciliationAnomalyKind.other =>
        'What this difference means is not something this version of the app '
            'can explain.',
    };

/// When the difference was found, and by which run.
///
/// §5.2's provenance shape - the instant first, then who - rather than the run
/// first, which is how one of the two surfaces used to order it. A record that
/// carries neither still proves the difference was found, so that is stated
/// rather than left as a silent gap.
String reconciliationDifferenceProvenance(
  TenantReconciliationAnomaly anomaly,
) {
  // Every fragment is written lowercase and the sentence is capitalised once, at
  // the end. Composing it the other way - a capitalised leading fragment and
  // lowercase followers - is how a record carrying only a run ID came out as
  // "found by run rj_abc." with a lowercase first word.
  final parts = <String>[
    if (anomaly.recordedAt case final at?)
      'first recorded ${reconciliationInstant(at)}',
    if (anomaly.updatedAt case final at?)
      'last seen ${reconciliationInstant(at)}',
    if (anomaly.jobId case final jobId?) 'found by run $jobId',
  ];
  if (parts.isEmpty) return 'No run or time was recorded for this difference.';
  final sentence = parts.join(', ');
  return '${sentence[0].toUpperCase()}${sentence.substring(1)}.';
}

String _saleLines(TenantReconciliationAnomaly anomaly) {
  final count = anomaly.invalidLineCount;
  return '$count sale ${count == 1 ? 'line' : 'lines'} could not be read, so '
      'they moved no stock.';
}

String _stockVariance(TenantReconciliationAnomaly anomaly) {
  final variance = anomaly.quantityVariance!;
  final direction = variance > 0 ? 'more' : 'fewer';
  return 'Its ledger expects ${anomaly.expectedQuantity}, and the product '
      'records ${anomaly.observedQuantity}: ${variance.abs()} $direction than '
      'the ledger accounts for.';
}

String _shiftVariance(TenantReconciliationAnomaly anomaly) =>
    'Its sales total ${_signed(anomaly.salesVariance!)} and its transaction '
    'count ${_signed(anomaly.transactionVariance!)} against the sales recorded '
    'during it.';

String _signed(num value) {
  if (value == 0) return 'agrees';
  return value > 0 ? 'is $value over' : 'is ${value.abs()} short';
}
