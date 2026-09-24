/// The stretch of trading a report covers, and the arithmetic over it.
///
/// **A business date, not an instant.** Every dated record in this app is
/// stamped with an Africa/Nairobi business date - a `yyyy-MM-dd` string, not a
/// timestamp - because a sale rung at half past midnight belongs to the day the
/// shop was open, not to the calendar day the clock had reached. A period is
/// therefore two of those strings, inclusive at both ends, and all of its
/// arithmetic stays in that space. Converting to a local `DateTime` and back
/// would reintroduce exactly the drift the business date exists to remove.
library;

import '../checkout/checkout_draft.dart';
import '../checkout/checkout_receipt.dart';

/// How much of a period a screen's data can honestly answer for.
///
/// **This is the range-read constraint, made visible.** Some collections can be
/// read across a span; `products` carries no time dimension whatever, so a date
/// control over it would be a control that produces a lie. A report declares
/// which of the three it is, and the picker shows only the controls that one
/// supports.
enum TenantReportPeriodSupport {
  /// Any span, including a single day.
  range,

  /// Exactly one business date at a time.
  dayOnly,

  /// No date at all - the figures are as at the moment they were read.
  snapshot,
}

/// A closed span of business dates.
final class TenantReportPeriod {
  TenantReportPeriod({required String startDate, required String endDate})
    : startDate = validateCheckoutBusinessDate(startDate),
      endDate = validateCheckoutBusinessDate(endDate) {
    if (this.startDate.compareTo(this.endDate) > 0) {
      throw ArgumentError.value(
        '$startDate..$endDate',
        'period',
        'starts after it ends',
      );
    }
  }

  /// One trading day.
  factory TenantReportPeriod.day(String businessDate) =>
      TenantReportPeriod(startDate: businessDate, endDate: businessDate);

  /// The business day containing [nowUtc].
  factory TenantReportPeriod.today(DateTime nowUtc) =>
      TenantReportPeriod.day(checkoutBusinessDate(nowUtc));

  /// [days] trading days ending on the business day containing [nowUtc].
  ///
  /// Inclusive of today, so a seven-day period is a week ending today rather
  /// than a week ending yesterday. A [days] of 1 is [TenantReportPeriod.today].
  factory TenantReportPeriod.lastDays(int days, DateTime nowUtc) {
    if (days < 1) {
      throw ArgumentError.value(days, 'days', 'must cover at least one day');
    }
    final end = checkoutBusinessDate(nowUtc);
    return TenantReportPeriod(startDate: _shift(end, 1 - days), endDate: end);
  }

  /// The calendar month containing [nowUtc], to date.
  ///
  /// Month *to date*, never the whole month: a period running to the end of a
  /// month that has not happened yet would report days with no trading as days
  /// with no takings, which is a different fact.
  factory TenantReportPeriod.monthOf(DateTime nowUtc) {
    final today = checkoutBusinessDate(nowUtc);
    return TenantReportPeriod(
      startDate: '${today.substring(0, 7)}-01',
      endDate: today,
    );
  }

  /// The first business date covered, inclusive.
  final String startDate;

  /// The last business date covered, inclusive.
  final String endDate;

  /// Every business date in the span, ascending, including days with no
  /// records at all.
  ///
  /// **Gaps included deliberately.** A chart drawn only over the days that
  /// happened to have a record compresses a quiet week into a point and makes a
  /// closed Sunday invisible. A day with nothing in it is a fact about the
  /// business, so the series carries it and the renderer draws the zero.
  List<String> get businessDates {
    final dates = <String>[];
    for (var date = startDate; date.compareTo(endDate) <= 0; ) {
      dates.add(date);
      date = _shift(date, 1);
    }
    return List<String>.unmodifiable(dates);
  }

  /// How many business dates the span covers, both ends included.
  int get days {
    var count = 0;
    for (var date = startDate; date.compareTo(endDate) <= 0; ) {
      count++;
      date = _shift(date, 1);
    }
    return count;
  }

  bool get isSingleDay => startDate == endDate;

  /// The equal-length span immediately before this one.
  ///
  /// **The comparison axis for every report that has one.** A figure on its own
  /// is a number; the same figure against the period before it is information,
  /// and that is the difference between this feature and an export button. The
  /// window is the same length so the two are comparable - a month against the
  /// month before it, a Tuesday against the Monday.
  TenantReportPeriod get precedingComparable => TenantReportPeriod(
    startDate: _shift(startDate, -days),
    endDate: _shift(startDate, -1),
  );

  /// Whether [businessDate] falls inside the span.
  bool covers(String businessDate) =>
      businessDate.compareTo(startDate) >= 0 &&
      businessDate.compareTo(endDate) <= 0;

  /// What to call this period on a control and in a sentence.
  ///
  /// The four shapes people actually pick, then a plain span. [nowUtc] decides
  /// what counts as today, so a report generated at midnight and a test with an
  /// injected clock agree.
  String label(DateTime nowUtc) {
    final today = checkoutBusinessDate(nowUtc);
    if (isSingleDay) {
      if (startDate == today) return 'Today';
      if (startDate == _shift(today, -1)) return 'Yesterday';
      return _longDay(startDate);
    }
    if (endDate == today && startDate == '${today.substring(0, 7)}-01') {
      return 'This month';
    }
    if (endDate == today) {
      final span = days;
      if (span == 7) return 'Last 7 days';
      if (span == 30) return 'Last 30 days';
      if (span == 90) return 'Last 90 days';
    }
    return '${_shortDay(startDate)} - ${_shortDay(endDate)}';
  }

  /// The span written out in full, for a cover page that must be unambiguous.
  ///
  /// Separate from [label] on purpose: a control says *This month* because the
  /// person picking it knows which month they are in, but a document read six
  /// months later by an accountant does not, so paper always spells it out.
  String get spelled => isSingleDay
      ? _longDay(startDate)
      : '${_longDay(startDate)} to ${_longDay(endDate)}';

  /// The span as a filename fragment.
  String get slug => isSingleDay ? startDate : '$startDate-to-$endDate';

  @override
  bool operator ==(Object other) =>
      other is TenantReportPeriod &&
      other.startDate == startDate &&
      other.endDate == endDate;

  @override
  int get hashCode => Object.hash(startDate, endDate);

  @override
  String toString() => 'TenantReportPeriod($startDate..$endDate)';
}

const List<String> _monthNames = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Moves a business date by whole days, staying in the business-date space.
///
/// The date is read as a calendar date at UTC midnight, which is what makes the
/// arithmetic exact: there is no zone to cross, no hour to lose, and every
/// month length and leap year comes free from `DateTime`.
String _shift(String businessDate, int days) {
  final at = DateTime.utc(
    int.parse(businessDate.substring(0, 4)),
    int.parse(businessDate.substring(5, 7)),
    int.parse(businessDate.substring(8, 10)),
  ).add(Duration(days: days));
  final month = at.month.toString().padLeft(2, '0');
  final day = at.day.toString().padLeft(2, '0');
  return '${at.year.toString().padLeft(4, '0')}-$month-$day';
}

String _shortDay(String businessDate) {
  final month = int.parse(businessDate.substring(5, 7));
  final day = int.parse(businessDate.substring(8, 10));
  return '$day ${_monthNames[month - 1]}';
}

String _longDay(String businessDate) =>
    '${_shortDay(businessDate)} ${businessDate.substring(0, 4)}';
