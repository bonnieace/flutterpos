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
///
/// **A difference is stated in two forms, and both live in one `switch` so they
/// cannot drift.** `design.md` §11 step 8 takes the figures out of the prose, so
/// the differences list wants a column of labelled numbers at §2.2's
/// `numeric.body` role; the stock route draws the same record as a [Callout],
/// which takes a single `message` string and has no slot for a widget. Rather
/// than let the two surfaces word one document two ways again - the exact
/// divergence this module was written to end - each kind's reading is declared
/// once, as [_DifferenceReading]: the sentence the notice needs, the prose left
/// once the figures are pulled out of it, and the figures themselves. They sit
/// on adjacent lines, and `reconciliation_labels_test.dart` asserts that every
/// figure a record states also appears in its sentence.
library;

import '../checkout/checkout_tender.dart';
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

/// One figure a record states, ready to be drawn as a `StatLine`.
///
/// `design.md` §2.2 makes tabular figures mandatory "anywhere numbers stack
/// vertically" and §11 step 8 names 27, 28 and 29 as the screens still carrying
/// the original complaint. A record that states an expected quantity against an
/// observed one is exactly a column of numbers, so the module hands the screen
/// the parts rather than a sentence with the parts embedded in it.
final class ReconciliationFigure {
  const ReconciliationFigure({
    required this.slug,
    required this.label,
    required this.value,
    this.detail,
  });

  /// A stable name for what this figure *is*, independent of the kind that
  /// carries it, so a call site keys its own widget by meaning rather than by
  /// position in a list.
  final String slug;

  /// The key. Sentence case, per §8 rule 7.
  ///
  /// **Deliberately not inflected for its own value.** A label beside a figure
  /// is a column heading rather than a clause, so `Unreadable sale lines: 1`
  /// needs no singular - which is the same grammar the daily summary lost when
  /// its three counts stopped being a sentence.
  final String label;

  /// The figure, formatted. A variance carries its sign, because a column of
  /// differences is unreadable without one.
  final String value;

  /// What the figure is against, or what it does not prove. **A direction is
  /// stated here as a word as well as in [value]'s sign**, so the two agree and
  /// neither carries the meaning alone.
  final String? detail;
}

/// Everything one kind of difference says about itself.
///
/// Three renderings of one reading, declared together so they cannot drift:
/// see the note at the top of this library for why both a sentence and a set of
/// figures are needed at once.
final class _DifferenceReading {
  const _DifferenceReading({
    required this.sentence,
    this.explanation,
    this.figures = const <ReconciliationFigure>[],
  });

  /// The whole record as one string, figures included, for a container that
  /// takes prose and nothing else.
  final String sentence;

  /// What is left of [sentence] once the figures are pulled out of it, or null
  /// where the figures were the whole of it.
  final String? explanation;

  final List<ReconciliationFigure> figures;
}

/// The figures the record itself carries, stated and never recomputed.
///
/// **One sentence per kind, which is the whole point of this function.** The
/// model refuses a record that cannot explain its own difference - all three
/// stock kinds carry the expected quantity, the observed quantity and a variance
/// that is exactly their difference - so every branch below reads figures the
/// record is guaranteed to hold.
///
/// This is the prose form, for a surface whose container is a sentence. Screen
/// 21's exception report is the one that needs it: a difference there is a
/// [Callout], and a `Callout` has a `message` and no slot for a column.
String reconciliationDifferenceFigures(TenantReconciliationAnomaly anomaly) =>
    _reading(anomaly).sentence;

/// What the record says once its figures are drawn separately, or null when the
/// figures were the whole statement.
///
/// A stock variance returns null: `Expected 10 / Recorded 7 / Difference -3` is
/// the entire content of "Its ledger expects 10, and the product records 7", and
/// a screen that drew both would state one difference twice.
String? reconciliationDifferenceExplanation(
  TenantReconciliationAnomaly anomaly,
) => _reading(anomaly).explanation;

/// The figures this record carries, in reading order, possibly none.
///
/// Three of the eight kinds carry no figure at all - they report that something
/// could not be read, which is a fact about the record rather than a
/// measurement - and for those the explanation above is the whole of it.
List<ReconciliationFigure> reconciliationDifferenceFigureLines(
  TenantReconciliationAnomaly anomaly,
) => _reading(anomaly).figures;

_DifferenceReading _reading(
  TenantReconciliationAnomaly anomaly,
) => switch (anomaly.kind) {
  TenantReconciliationAnomalyKind.invalidSaleLines => _saleLines(anomaly),
  TenantReconciliationAnomalyKind.invalidProductQuantity =>
    const _DifferenceReading(
      sentence:
          'This product\'s recorded quantity could not be read as a whole '
          'number, so its stock was not verified at all.',
      explanation:
          'This product\'s recorded quantity could not be read as a whole '
          'number, so its stock was not verified at all.',
    ),
  // Not the variance sentence. The chain is what makes the expected
  // quantity trustworthy, so a broken chain is a statement about the
  // starting point rather than about a disagreement - and the variance on
  // one of these records may legitimately be zero.
  TenantReconciliationAnomalyKind.checkpointChainInvalid => _DifferenceReading(
    sentence:
        'The tamper-evident chain of checks behind this product does not '
        'join up, so the expected quantity of ${anomaly.expectedQuantity} '
        'cannot be trusted as a starting point. This is not a quantity '
        'disagreement.',
    explanation:
        'The tamper-evident chain of checks behind this product does not '
        'join up, so the expected quantity cannot be trusted as a '
        'starting point. This is not a quantity disagreement.',
    figures: <ReconciliationFigure>[
      ReconciliationFigure(
        slug: 'expected',
        label: 'Expected by the ledger',
        value: '${anomaly.expectedQuantity}',
        detail: 'not trustworthy as a starting point',
      ),
    ],
  ),
  TenantReconciliationAnomalyKind.invalidStockMovement => _DifferenceReading(
    sentence:
        'A movement in this product\'s ledger could not be read, so the '
        'expected quantity of ${anomaly.expectedQuantity} does not '
        'account for everything that moved.',
    explanation: 'A movement in this product\'s ledger could not be read.',
    figures: <ReconciliationFigure>[
      ReconciliationFigure(
        slug: 'expected',
        label: 'Expected by the ledger',
        value: '${anomaly.expectedQuantity}',
        detail: 'does not account for everything that moved',
      ),
    ],
  ),
  TenantReconciliationAnomalyKind.stockVariance => _stockVariance(anomaly),
  TenantReconciliationAnomalyKind.invalidOrMissingShift =>
    const _DifferenceReading(
      sentence:
          'The shift is missing, or did not record the totals a comparison '
          'needs, so no difference could be measured.',
      explanation:
          'The shift is missing, or did not record the totals a comparison '
          'needs, so no difference could be measured.',
    ),
  TenantReconciliationAnomalyKind.shiftVariance => _shiftVariance(anomaly),
  TenantReconciliationAnomalyKind.shiftTenderVariance => _tenderVariance(
    anomaly,
  ),
  TenantReconciliationAnomalyKind.missingTenderDeclaration =>
    const _DifferenceReading(
      sentence:
          'This shift was closed without saying what the register held, so '
          'nothing could be compared against its sales.',
      explanation:
          'This shift was closed without saying what the register held, so '
          'nothing could be compared against its sales.',
    ),
  TenantReconciliationAnomalyKind.other => const _DifferenceReading(
    sentence:
        'What this difference means is not something this version of the '
        'app can explain.',
    explanation:
        'What this difference means is not something this version of the '
        'app can explain.',
  ),
};

/// When the difference was found, and by which run.
///
/// §5.2's provenance shape - the instant first, then who - rather than the run
/// first, which is how one of the two surfaces used to order it. A record that
/// carries neither still proves the difference was found, so that is stated
/// rather than left as a silent gap.
String reconciliationDifferenceProvenance(TenantReconciliationAnomaly anomaly) {
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

_DifferenceReading _saleLines(TenantReconciliationAnomaly anomaly) {
  final count = anomaly.invalidLineCount;
  return _DifferenceReading(
    sentence:
        '$count sale ${count == 1 ? 'line' : 'lines'} could not be read, so '
        'they moved no stock.',
    explanation: 'Those lines moved no stock.',
    figures: <ReconciliationFigure>[
      ReconciliationFigure(
        slug: 'invalid-lines',
        label: 'Unreadable sale lines',
        value: '$count',
        detail: 'on this sale',
      ),
    ],
  );
}

_DifferenceReading _stockVariance(TenantReconciliationAnomaly anomaly) {
  final variance = anomaly.quantityVariance!;
  final direction = variance > 0 ? 'more' : 'fewer';
  return _DifferenceReading(
    sentence:
        'Its ledger expects ${anomaly.expectedQuantity}, and the product '
        'records ${anomaly.observedQuantity}: ${variance.abs()} $direction '
        'than the ledger accounts for.',
    // Nothing is left over. Three labelled figures state the whole of that
    // sentence, and a screen drawing both would report one difference twice.
    figures: <ReconciliationFigure>[
      ReconciliationFigure(
        slug: 'expected',
        label: 'Expected by the ledger',
        value: '${anomaly.expectedQuantity}',
      ),
      ReconciliationFigure(
        slug: 'observed',
        label: 'Recorded on the product',
        value: '${anomaly.observedQuantity}',
      ),
      ReconciliationFigure(
        slug: 'variance',
        label: 'Difference',
        value: _signedFigure(variance),
        detail: '$direction than the ledger accounts for',
      ),
    ],
  );
}

_DifferenceReading _shiftVariance(TenantReconciliationAnomaly anomaly) {
  final sales = anomaly.salesVariance!;
  final transactions = anomaly.transactionVariance!;
  return _DifferenceReading(
    sentence:
        'Its sales total ${_signed(sales)} and its transaction count '
        '${_signed(transactions)} against the sales recorded during it.',
    explanation:
        'Its closing totals disagree with the sales recorded during it.',
    // **Neither figure carries a currency code, and §8 rule 8 says money always
    // does.** The code lives in `configuration/checkout`, which this screen does
    // not read and cannot be made to read inside a visual chunk; the sentence
    // above has been unlabelled since it was written, so this is the same debt
    // in a new rendering rather than a new one. `PLAN.md` carries it.
    figures: <ReconciliationFigure>[
      ReconciliationFigure(
        slug: 'sales-variance',
        label: 'Sales total',
        value: _signedFigure(sales),
        detail: _against(sales),
      ),
      ReconciliationFigure(
        slug: 'transaction-variance',
        label: 'Transactions',
        value: _signedFigure(transactions),
        detail: _against(transactions),
      ),
    ],
  );
}

/// The declaration, the sales it is measured against, and the gap - per method.
///
/// **Nine figures rather than three.** A difference on its own says how far out
/// the till is and nothing about which side moved, and the person reading this
/// is deciding whether to accept it. Grouped by method rather than by role, so
/// each row reads as one question answered twice and then subtracted.
_DifferenceReading _tenderVariance(TenantReconciliationAnomaly anomaly) {
  final figures = <ReconciliationFigure>[];
  final over = <String>[];
  final short = <String>[];
  for (final tender in CheckoutTender.values) {
    final declared = anomaly.declaredMinor[tender]!;
    final expected = anomaly.expectedMinor[tender]!;
    final variance = anomaly.tenderVarianceMinor[tender]!;
    figures.addAll(<ReconciliationFigure>[
      ReconciliationFigure(
        slug: '${tender.wireValue}-declared',
        label: '${tender.label} declared',
        value: _money(declared),
      ),
      ReconciliationFigure(
        slug: '${tender.wireValue}-expected',
        label: '${tender.label} from the sales',
        value: _money(expected),
      ),
      ReconciliationFigure(
        slug: '${tender.wireValue}-variance',
        label: '${tender.label} difference',
        value: _signedFigure(_major(variance)),
        detail: _against(variance),
      ),
    ]);
    if (variance > 0) over.add(tender.label);
    if (variance < 0) short.add(tender.label);
  }
  final clauses = <String>[
    if (over.isNotEmpty)
      '${_list(over)} came to more than the sales account '
          'for',
    if (short.isNotEmpty) '${_list(short)} came to less',
  ];
  return _DifferenceReading(
    sentence: clauses.isEmpty
        ? 'What was declared and what the sales account for disagree.'
        : '${_capitalise(clauses.join(', and '))}.',
    // **The unattributed figure is named, not quietly dropped.** It is inside
    // the shift's takings but in none of the three above, so a reader adding
    // them up would otherwise find the report short by exactly that much and
    // conclude the wrong thing.
    explanation: <String>[
      'What the cashier said the register held disagrees with what its own sales '
          'account for.',
      if ((anomaly.expectedUnattributedMinor ?? 0) > 0)
        'A further ${_money(anomaly.expectedUnattributedMinor!)} of this '
            "shift's sales name no payment method this app recognises, so it "
            'is in the shift total but in none of the three figures above.',
      checkoutTenderDisclaimer,
    ].join(' '),
    figures: figures,
  );
}

/// Minor units as money, unlabelled for the reason `_shiftVariance` records:
/// this screen has no access to the business's currency code.
String _money(int minorUnits) => _major(minorUnits).toStringAsFixed(2);

num _major(int minorUnits) => minorUnits / 100;

String _list(List<String> items) => items.length == 1
    ? items.single
    : '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';

String _capitalise(String sentence) => sentence.isEmpty
    ? sentence
    : sentence[0].toUpperCase() + sentence.substring(1);

String _signed(num value) {
  if (value == 0) return 'agrees';
  return value > 0 ? 'is $value over' : 'is ${value.abs()} short';
}

/// A variance with its sign, because a column of differences that all read as
/// bare magnitudes says nothing about which way any of them went.
String _signedFigure(num value) => value > 0 ? '+$value' : '$value';

/// The direction as a word, so the sign in the figure is never the only thing
/// carrying it.
String _against(num value) => switch (value) {
  0 => 'agrees with the sales recorded',
  < 0 => 'short of the sales recorded',
  _ => 'over the sales recorded',
};
