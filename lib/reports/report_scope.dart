/// What a report actually covered, and every reason it fell short.
///
/// **A document that leaves the device is held to a higher standard than a
/// screen.** A figure on a screen is provisional - the person can page further,
/// change the filter, or watch it fill in. A figure in a file gets mailed to an
/// accountant, and nobody who opens it six months later can tell that the read
/// stopped at 250 records. So every report carries its own scope, and the scope
/// block prints even when nothing went wrong: a provenance note that appears
/// only when something is broken teaches people to skip it.
///
/// This follows what the app already does rather than inventing a standard.
/// `TenantExpensePeriod.truncated` flags a capped read, `TenantSalesTotals`
/// carries `incompleteCostLineCount` beside the profit it could only partly
/// compute, `TenantReportingCurrency` prints a sentence rather than guess a
/// code, and the staff directory deleted four counters because a figure
/// assembled from one page was judged a lie. Same discipline, one vocabulary.
library;

import '../checkout/checkout_draft.dart';
import 'report_period.dart';

/// The kinds of shortfall a report can have.
///
/// A closed set rather than free text, so a renderer can decide how loudly to
/// print one and a test can assert a specific shortfall was recorded.
enum TenantReportCaveatKind {
  /// A read stopped at a cap before reaching the whole period.
  truncated,

  /// Money could not be computed because cost was not recorded on every line.
  missingCost,

  /// The business has published no currency, so figures carry no code.
  unknownCurrency,

  /// A total's denominator could not be established, so shares are withheld.
  partialDirectory,

  /// Records exist that carry no usable timestamp and are therefore not here.
  missingTimestamps,

  /// A value was not evidenced, as distinct from being zero.
  noEvidence,

  /// The reader's role withheld part of what this report would otherwise say.
  roleRestricted,

  /// The figures are as at a moment, because the records carry no history.
  snapshotOnly,
}

/// One whole sentence about something this report could not do.
///
/// **A sentence, not a code.** The renderers print [sentence] verbatim; they do
/// not assemble prose from the kind, because the useful version of a caveat
/// names real numbers - "the read stopped at 250 records, covering 1 to 14
/// September of the 1 to 30 September asked for" - and only the loader that hit
/// the cap knows those.
final class TenantReportCaveat {
  const TenantReportCaveat({required this.kind, required this.sentence});

  /// A read that stopped short, naming what it actually reached.
  factory TenantReportCaveat.truncated({
    required TenantReportPeriod asked,
    required String reachedFrom,
    required String reachedTo,
    required int records,
  }) => TenantReportCaveat(
    kind: TenantReportCaveatKind.truncated,
    sentence:
        'The read stopped at $records records. These figures cover '
        '${TenantReportPeriod(startDate: reachedFrom, endDate: reachedTo).spelled}, '
        'not the whole of ${asked.spelled}, and every total below is a floor '
        'rather than a sum.',
  );

  /// Money computed over lines that did not all record a cost.
  ///
  /// Follows `TenantSalesTotals.incompleteCostLineCount`: the figure is printed,
  /// its denominator is stated, and the missing rows are counted rather than
  /// guessed at.
  factory TenantReportCaveat.missingCost({
    required int lines,
    required int of,
  }) => TenantReportCaveat(
    kind: TenantReportCaveatKind.missingCost,
    sentence:
        'Profit is computed over ${of - lines} of $of lines. The other $lines '
        'record no cost, so they contribute their takings but no margin, and '
        'every profit figure below understates by whatever those cost.',
  );

  /// A share whose whole could not be established.
  factory TenantReportCaveat.partialDirectory({
    required int read,
    required String of,
  }) => TenantReportCaveat(
    kind: TenantReportCaveatKind.partialDirectory,
    sentence:
        'Only $read $of were read, so the figures below are exact for each one '
        'named and no share or ranking across the whole is shown - a share of '
        'an unknown total would not be a measurement.',
  );

  /// Values that were not evidenced, kept apart from values that were zero.
  ///
  /// **[of] and [because] are given in both numbers**, because one of these
  /// reads "1 shift were closed" otherwise - and a document that cannot count
  /// to one undermines every figure printed beside it. [ofOne] and
  /// [becauseOne] default to the plural forms for a caller whose wording does
  /// not change.
  factory TenantReportCaveat.noEvidence({
    required int count,
    required String of,
    required String because,
    String? ofOne,
    String? becauseOne,
  }) {
    final one = count == 1;
    return TenantReportCaveat(
      kind: TenantReportCaveatKind.noEvidence,
      sentence:
          '$count ${one ? (ofOne ?? of) : of} '
          '${one ? (becauseOne ?? because) : because}. '
          '${one ? 'It is' : 'They are'} shown as not recorded and left out of '
          'the averages, because counting ${one ? 'it' : 'them'} as nought '
          'would invent a figure nobody measured.',
    );
  }

  final TenantReportCaveatKind kind;

  /// The whole sentence, printed as it is.
  final String sentence;

  @override
  String toString() => sentence;
}

/// What a report covered, printed on every cover page.
final class TenantReportScope {
  TenantReportScope({
    required this.period,
    required this.documentsRead,
    String? coveredFrom,
    String? coveredTo,
    List<TenantReportCaveat> caveats = const <TenantReportCaveat>[],
  }) : coveredFrom = coveredFrom ?? period.startDate,
       coveredTo = coveredTo ?? period.endDate,
       caveats = List<TenantReportCaveat>.unmodifiable(caveats);

  /// A report over records that carry no history at all.
  ///
  /// Inventory is the only one of these: `products` has no time dimension, so
  /// there is nothing to range over and the figures are true of the instant
  /// they were read and of no other.
  factory TenantReportScope.snapshot({
    required DateTime at,
    required int documentsRead,
    List<TenantReportCaveat> caveats = const <TenantReportCaveat>[],
  }) {
    final date = checkoutBusinessDate(at);
    return TenantReportScope(
      period: TenantReportPeriod.day(date),
      documentsRead: documentsRead,
      caveats: <TenantReportCaveat>[
        const TenantReportCaveat(
          kind: TenantReportCaveatKind.snapshotOnly,
          sentence:
              'These figures are as at the moment they were read. The catalog '
              'keeps no history, so there is no earlier state to compare them '
              'against and nothing here is a trend.',
        ),
        ...caveats,
      ],
    );
  }

  /// The span the report was asked for.
  final TenantReportPeriod period;

  /// The first business date the read actually reached.
  final String coveredFrom;

  /// The last business date the read actually reached.
  final String coveredTo;

  /// How many documents were read to produce this. Printed, because on a phone
  /// somebody is paying for them.
  final int documentsRead;

  final List<TenantReportCaveat> caveats;

  /// Whether the read reached every day it was asked for.
  bool get isComplete =>
      coveredFrom == period.startDate && coveredTo == period.endDate;

  /// Whether any figure here is a floor rather than a total.
  bool get isTruncated =>
      caveats.any((c) => c.kind == TenantReportCaveatKind.truncated);

  /// Whether a share of a whole may honestly be printed.
  ///
  /// False where the denominator was never established. The staff report reads
  /// this before printing a concentration figure, for the reason the staff
  /// screen removed its counters.
  bool get canQuoteShares =>
      !caveats.any((c) => c.kind == TenantReportCaveatKind.partialDirectory);

  /// The one-line summary that heads the scope block.
  ///
  /// Prints whether or not anything went wrong. "Read 214 records across 22
  /// days. Complete." is the normal case and it still prints.
  ///
  /// **It no longer names where the figures came from**, at the developer's
  /// direction on 2026-09-23. "Device figures" was `TenantSalesTotals`'
  /// vocabulary carried onto paper, and on paper it answered a question nobody
  /// reading a report asks: a phone is where the app runs, not a second set of
  /// books, and the sentence read as a disclaimer about figures that have none
  /// to make. What the read actually reached is the part that matters, and
  /// that is what is left.
  String get summary {
    final covered = TenantReportPeriod(
      startDate: coveredFrom,
      endDate: coveredTo,
    );
    final span = covered.isSingleDay ? '1 day' : '${covered.days} days';
    final standing = isComplete ? 'Complete.' : 'Short of the period asked for.';
    return 'Read $documentsRead records across $span. $standing';
  }

  TenantReportScope withCaveat(TenantReportCaveat caveat) => TenantReportScope(
    period: period,
    documentsRead: documentsRead,
    coveredFrom: coveredFrom,
    coveredTo: coveredTo,
    caveats: <TenantReportCaveat>[...caveats, caveat],
  );
}
