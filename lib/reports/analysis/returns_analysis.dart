/// What a period's returns say, beyond the list the screen already shows.
///
/// **The section that justifies this report is *Which lines come back*.** The
/// returns screen answers "what came back today"; nothing in the app answers
/// "what keeps coming back". A shop losing the same three lines every week has
/// a supplier problem, a storage problem or a pricing problem, and none of
/// those is visible one return at a time.
///
/// **The second is *Waiting on verification*.** The server restores stock only
/// when a return is verified, so an unverified return is stock that is
/// physically on the shelf and absent from the books. The screen shows a badge
/// per row; only a period can say how much is sitting there and how long it has
/// been.
///
/// **Money comes from the sale, never from the return.** A return line carries
/// a product and a quantity and no money at all - see `return_offsets.dart`,
/// which makes the same point. So a value here is a joined figure, and where
/// the join could not be made the analysis holds units and says money is not
/// stated rather than guessing a price.
///
/// Pure arithmetic, no I/O, no Flutter.
library;

import '../../returns/return_history.dart';
import '../../returns/return_offsets.dart';
import '../report_period.dart';

/// One product, and everything that came back of it.
final class TenantReturnedLine {
  const TenantReturnedLine({
    required this.productId,
    required this.name,
    required this.units,
    required this.minor,
  });

  final String productId;

  /// The name a returning device recorded, or the product ID where none did.
  ///
  /// A line's name is a label the device wrote down, not the catalog's - see
  /// [TenantReturnLine.productName]. Falling back to the ID keeps the row
  /// identifiable rather than blank.
  final String name;

  final int units;

  /// What those units were worth, or null where the sale could not be read.
  final int? minor;
}

/// One person, and the returns they put through.
///
/// **A count, not an accusation.** Whoever is at the till takes the return, so
/// a high count usually means a busy shift. It is here for the same reason the
/// staff report carries a discount rate: the shape is worth seeing, and a
/// figure nobody can see is a figure nobody can ask about.
final class TenantReturnRecorder {
  const TenantReturnRecorder({
    required this.staffId,
    required this.returns,
    required this.units,
  });

  final String staffId;
  final int returns;
  final int units;
}

/// One reason, as it was typed, and how often.
final class TenantReturnReason {
  const TenantReturnReason({required this.reason, required this.count});

  final String reason;
  final int count;
}

/// A period's returns, with the period before it for company.
final class TenantReturnsAnalysis {
  const TenantReturnsAnalysis._({
    required this.period,
    required this.recordCount,
    required this.returnedUnits,
    required this.returnedMinor,
    required this.valuedReturns,
    required this.pendingCount,
    required this.pendingUnits,
    required this.verifiedCount,
    required this.lines,
    required this.recorders,
    required this.reasons,
    required this.dailyUnits,
    required this.medianWait,
    required this.previousUnits,
    required this.truncated,
  });

  /// How many lines, people or reasons a page lists before the rest is left to
  /// the workbook.
  static const int listed = 20;

  factory TenantReturnsAnalysis.from({
    required TenantReportPeriod period,
    required List<TenantReturn> returns,
    Map<String, TenantSaleReturnOffset> valuation =
        const <String, TenantSaleReturnOffset>{},
    List<TenantReturn>? previous,
    bool truncated = false,
  }) {
    final units = <String, int>{};
    final names = <String, String>{};
    final money = <String, int>{};
    final recorders = <String, ({int returns, int units})>{};
    final reasons = <String, int>{};
    final daily = <String, int>{for (final date in period.businessDates) date: 0};

    var returnedUnits = 0;
    var pendingCount = 0;
    var pendingUnits = 0;
    var verifiedCount = 0;
    final waits = <Duration>[];
    final valuedSales = <String>{};

    for (final record in returns) {
      final recordUnits = record.returnedUnits;
      returnedUnits += recordUnits;

      if (record.isVerified) {
        verifiedCount++;
        // Both instants or neither: a wait computed from one of them would be
        // a duration since an unknown moment.
        final taken = record.recordedAt;
        final verified = record.verification?.verifiedAt;
        if (taken != null && verified != null && !verified.isBefore(taken)) {
          waits.add(verified.difference(taken));
        }
      } else {
        pendingCount++;
        pendingUnits += recordUnits;
      }

      // The period's own days, so a day with no returns is drawn as the zero
      // it was rather than left out of the line.
      if (daily.containsKey(record.recordedOn)) {
        daily[record.recordedOn] = daily[record.recordedOn]! + recordUnits;
      }

      final recorder = recorders[record.createdBy] ?? (returns: 0, units: 0);
      recorders[record.createdBy] = (
        returns: recorder.returns + 1,
        units: recorder.units + recordUnits,
      );

      final reason = record.reason.trim();
      if (reason.isNotEmpty) {
        reasons[reason] = (reasons[reason] ?? 0) + 1;
      }

      final offset = valuation[record.saleId];
      if (offset != null) valuedSales.add(record.saleId);

      for (final line in record.lines) {
        units[line.productId] = (units[line.productId] ?? 0) + line.quantity;
        if (line.productName case final recorded?) {
          names[line.productId] = recorded;
        }
      }
    }

    // **Value is taken per sale, not per return.** An offset prices every unit
    // that came back out of one sale in a single pro-rata calculation - see
    // `TenantSaleReturnOffset.returnedMinorByProduct` - so adding it once per
    // return would double-count a sale two returns were filed against.
    for (final saleId in valuedSales) {
      final offset = valuation[saleId]!;
      for (final entry in offset.returnedMinorByProduct.entries) {
        money[entry.key] = (money[entry.key] ?? 0) + entry.value;
      }
    }

    final ranked =
        <TenantReturnedLine>[
          for (final entry in units.entries)
            TenantReturnedLine(
              productId: entry.key,
              name: names[entry.key] ?? entry.key,
              units: entry.value,
              minor: money[entry.key],
            ),
        ]..sort((a, b) {
          final byUnits = b.units.compareTo(a.units);
          return byUnits != 0 ? byUnits : a.name.compareTo(b.name);
        });

    final people =
        <TenantReturnRecorder>[
          for (final entry in recorders.entries)
            TenantReturnRecorder(
              staffId: entry.key,
              returns: entry.value.returns,
              units: entry.value.units,
            ),
        ]..sort((a, b) {
          // **Ties broken all the way down.** Two people who put through the
          // same number of returns would otherwise be ordered by whichever
          // happened to be read first, so the same period could rank them
          // differently on two runs - and a report that reorders people
          // between printings is one nobody can refer back to.
          final byReturns = b.returns.compareTo(a.returns);
          if (byReturns != 0) return byReturns;
          final byUnits = b.units.compareTo(a.units);
          return byUnits != 0 ? byUnits : a.staffId.compareTo(b.staffId);
        });

    final why =
        <TenantReturnReason>[
          for (final entry in reasons.entries)
            TenantReturnReason(reason: entry.key, count: entry.value),
        ]..sort((a, b) {
          final byCount = b.count.compareTo(a.count);
          return byCount != 0 ? byCount : a.reason.compareTo(b.reason);
        });

    final totalMoney = money.values.fold(0, (sum, value) => sum + value);

    return TenantReturnsAnalysis._(
      period: period,
      recordCount: returns.length,
      returnedUnits: returnedUnits,
      // **Null rather than nought where nothing could be priced.** A period
      // whose sales could not be read has an unknown value, and printing zero
      // would state that nothing of worth came back.
      returnedMinor: valuedSales.isEmpty ? null : totalMoney,
      valuedReturns: returns
          .where((record) => valuedSales.contains(record.saleId))
          .length,
      pendingCount: pendingCount,
      pendingUnits: pendingUnits,
      verifiedCount: verifiedCount,
      lines: List<TenantReturnedLine>.unmodifiable(ranked),
      recorders: List<TenantReturnRecorder>.unmodifiable(people),
      reasons: List<TenantReturnReason>.unmodifiable(why),
      dailyUnits: Map<String, int>.unmodifiable(daily),
      medianWait: _median(waits),
      previousUnits: previous?.fold<int>(
        0,
        (sum, record) => sum + record.returnedUnits,
      ),
      truncated: truncated,
    );
  }

  final TenantReportPeriod period;

  /// How many return documents the period holds.
  final int recordCount;

  final int returnedUnits;

  /// What came back, where the sales behind it could be read. Null otherwise.
  final int? returnedMinor;

  /// How many of [recordCount] were priced. The rest are counted in units.
  final int valuedReturns;

  /// Returns the server has not verified, so their stock is still off the
  /// books.
  final int pendingCount;
  final int pendingUnits;

  final int verifiedCount;

  /// Every product that came back, most units first.
  final List<TenantReturnedLine> lines;

  final List<TenantReturnRecorder> recorders;

  final List<TenantReturnReason> reasons;

  /// Units returned on each day of the period, empty days included.
  final Map<String, int> dailyUnits;

  /// The middle wait between a return being taken and being verified.
  ///
  /// Null where no return in the period carries both instants. The median
  /// rather than the mean: one return left over a holiday would drag an
  /// average past anything anybody experienced.
  final Duration? medianWait;

  /// Units returned over the preceding comparable period, or null where that
  /// window could not be read.
  final int? previousUnits;

  final bool truncated;

  /// Whether every return in the period could be priced.
  bool get isFullyValued => valuedReturns == recordCount;

  /// How far units moved against the period before, as a fraction.
  ///
  /// Null where there is no earlier window, or where it held nothing - a rise
  /// from nothing is not a percentage.
  double? get change {
    final before = previousUnits;
    if (before == null || before == 0) return null;
    return (returnedUnits - before) / before;
  }

  /// The largest line's share of everything that came back.
  double? get concentration {
    if (lines.isEmpty || returnedUnits == 0) return null;
    return lines.first.units / returnedUnits;
  }

  /// How many lines carry three quarters of the units, or null where none do.
  int? linesFor(double share) {
    if (returnedUnits == 0) return null;
    var running = 0;
    for (var i = 0; i < lines.length; i++) {
      running += lines[i].units;
      if (running / returnedUnits >= share) return i + 1;
    }
    return null;
  }

  /// The day the most came back on, or null where nothing did.
  String? get heaviestDate {
    String? heaviest;
    var most = 0;
    for (final entry in dailyUnits.entries) {
      if (entry.value > most) {
        most = entry.value;
        heaviest = entry.key;
      }
    }
    return heaviest;
  }

  /// Days in the period on which nothing came back.
  int get quietDays =>
      dailyUnits.values.where((units) => units == 0).length;

  static Duration? _median(List<Duration> waits) {
    if (waits.isEmpty) return null;
    final sorted = waits.toList()..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return Duration(
      microseconds:
          (sorted[middle - 1].inMicroseconds + sorted[middle].inMicroseconds) ~/
          2,
    );
  }
}
