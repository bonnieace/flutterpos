/// The rows a report lists, typed so a spreadsheet gets numbers.
///
/// **A cell carries its kind, not just its text.** The whole reason somebody
/// picks the workbook over the PDF is to do arithmetic on it, and a column of
/// `"KES 1234.50"` strings cannot be summed, sorted or charted. So every cell
/// knows what it is: money keeps its minor units, a count keeps its integer, a
/// share keeps its fraction, and a date stays a date. The PDF prints the text;
/// the workbook writes the number and lets Excel apply the format.
///
/// **And an absence is its own kind.** `TenantShiftHistoryEntry.cashVariance`
/// returns null rather than zero when a shift closed with no evidence, and
/// `TenantProduct.cost` is normally null. Both have to reach paper as an
/// absence: a blank cell gets summed as nought by whoever opens the file, and a
/// printed 0 invents a shift that balanced. Neither is true, so neither is
/// allowed - [TenantReportAbsentCell] is the only way to say "not known".
library;

/// One value in a report's table.
sealed class TenantReportCell {
  const TenantReportCell();

  /// What the PDF prints and what a text-only reader sees.
  String get text;
}

final class TenantReportTextCell extends TenantReportCell {
  const TenantReportTextCell(this.value);

  final String value;

  @override
  String get text => value;
}

/// Money, kept in minor units so nothing rounds on the way to paper.
final class TenantReportMoneyCell extends TenantReportCell {
  const TenantReportMoneyCell({required this.minor, required this.formatted});

  final int minor;

  /// Formatted once by the analysis, which knows the currency.
  final String formatted;

  /// Major units, for a spreadsheet cell that must be a real number.
  double get major => minor / 100;

  @override
  String get text => formatted;
}

final class TenantReportCountCell extends TenantReportCell {
  const TenantReportCountCell(this.value);

  final int value;

  @override
  String get text => value.toString();
}

/// A share, kept as a fraction so Excel's own percent format applies.
final class TenantReportPercentCell extends TenantReportCell {
  const TenantReportPercentCell(this.fraction);

  final double fraction;

  @override
  String get text => '${(fraction * 100).toStringAsFixed(1)}%';
}

final class TenantReportDateCell extends TenantReportCell {
  const TenantReportDateCell(this.businessDate);

  final String businessDate;

  @override
  String get text => businessDate;
}

/// A value that is not known, as distinct from one that is nothing.
///
/// Carries [reason] so the row can say why, rather than leaving a reader to
/// guess whether the till was empty or the shift was never counted.
final class TenantReportAbsentCell extends TenantReportCell {
  const TenantReportAbsentCell(this.reason, {this.shown = notRecorded});

  final String reason;

  /// The word that stands in for the value.
  ///
  /// **Defaults to *not recorded*, but not everything absent is unknown.** A
  /// voided expense has an amount and it is perfectly well known - it simply
  /// must not be totalled, because that money never left the business. Printing
  /// *not recorded* against it would state something false about the record. So
  /// a cell that is withheld for a reason other than ignorance says which.
  ///
  /// Whatever it says must not parse as a number, or a spreadsheet will coerce
  /// it into one.
  final String shown;

  /// **Words, not a dash, and the reason is arithmetic rather than taste.**
  ///
  /// A dash in a column of money already means something: accounting
  /// convention reads it as nought, which is the one thing this cell exists to
  /// deny. An em dash would be unambiguous to a reader but cannot be drawn by
  /// the `pdf` package's built-in faces at all - and those are what a device
  /// falls back to when an asset read fails - so it renders as *nothing*, and a
  /// blank cell gets summed as nought by whoever opens the workbook. Both
  /// shorthands fail the same way round.
  ///
  /// So the cell says what it means, in ASCII, in a form no spreadsheet will
  /// coerce to a number.
  @override
  String get text => shown;

  /// What an unknown value prints as, in every format.
  static const String notRecorded = 'not recorded';

  /// What a value that is known but must not be totalled prints as.
  static const String voided = 'voided';
}

/// What a column holds, which decides how it is aligned and how wide it is.
enum TenantReportColumnKind { text, money, count, percent, date }

final class TenantReportColumn {
  const TenantReportColumn({
    required this.heading,
    required this.kind,
    this.note,
  });

  final String heading;

  final TenantReportColumnKind kind;

  /// What the column means, where the heading cannot carry it.
  final String? note;

  /// Whether the values run to the right edge, as figures do.
  bool get isNumeric => kind != TenantReportColumnKind.text;
}

/// A listing of rows beneath a report section.
final class TenantReportTable {
  TenantReportTable({
    required List<TenantReportColumn> columns,
    required List<List<TenantReportCell>> rows,
    this.emphasisRow,
  }) : columns = List<TenantReportColumn>.unmodifiable(columns),
       rows = List<List<TenantReportCell>>.unmodifiable(
         rows.map(List<TenantReportCell>.unmodifiable),
       ) {
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].length != columns.length) {
        throw ArgumentError.value(
          rows[i].length,
          'rows[$i]',
          'has ${rows[i].length} cells for ${columns.length} columns',
        );
      }
    }
  }

  final List<TenantReportColumn> columns;

  final List<List<TenantReportCell>> rows;

  /// A row drawn as a total, where the table has one.
  final int? emphasisRow;

  bool get isEmpty => rows.isEmpty;

  /// How many cells in the table are an absence rather than a value.
  ///
  /// The scope block reads this to decide whether to print a caveat about
  /// unevidenced values, so no section can quietly fill with dashes.
  int get absences =>
      rows.expand((row) => row).whereType<TenantReportAbsentCell>().length;
}
