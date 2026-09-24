/// The phrases every report's summary sentences are built from.
///
/// **One copy, because they had started to diverge.** These four began as
/// private helpers in the first report and were pasted into the next two; by
/// the fourth there would have been five copies of the rule that decides
/// whether a movement reads as *level*. A report saying "up 0%" because one
/// file rounded where another did not is exactly the kind of difference nobody
/// notices until an accountant asks about it.
///
/// Pure functions over numbers and dates. Nothing here reads a document, and
/// nothing here formats money - that is [TenantReportIdentity.money], because
/// only it knows whether the business has published a currency at all.
library;

/// A fraction as a whole percentage: `0.375` is `38%`.
String reportPercent(double fraction) =>
    '${(fraction * 100).toStringAsFixed(0)}%';

/// Which way a measure moved, in words.
///
/// **Under half a percent is *level*, not a direction.** A period that moved by
/// a rounding error has not moved, and "up 0%" is a sentence that makes a
/// reader distrust every other figure on the page.
String reportDirection(double moved) {
  final percent = (moved * 100).abs().toStringAsFixed(0);
  if (moved > 0.005) return 'up $percent%';
  if (moved < -0.005) return 'down $percent%';
  return 'level';
}

/// A count and its noun, agreeing: `1 product`, `3 products`.
///
/// **One copy, because the first pass got it wrong in nine places.** Every
/// report writes sentences with a figure in them, and a document that says
/// "1 products have nothing on the shelf" reads as machine output - which
/// undermines the figures beside it far more than the missing letter costs.
/// [plural] is for the nouns that do not take a bare `s`.
String reportCount(int count, String singular, {String? plural}) =>
    '$count ${reportNoun(count, singular, plural: plural)}';

/// The noun alone, agreeing with [count].
String reportNoun(int count, String singular, {String? plural}) =>
    count == 1 ? singular : (plural ?? '${singular}s');

/// The verb form agreeing with [count]: `was`/`were`, `has`/`have`.
String reportVerb(int count, String singular, String plural) =>
    count == 1 ? singular : plural;

/// A list in prose: `a`, `a and b`, `a, b and c`.
String reportList(Iterable<String> items) {
  final all = items.toList();
  if (all.isEmpty) return '';
  if (all.length == 1) return all.first;
  return '${all.take(all.length - 1).join(', ')} and ${all.last}';
}

/// A business date as a reader says it: `2026-09-23` is `23 Sep`.
String reportShortDate(String businessDate) {
  const months = <String>[
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
  final month = int.parse(businessDate.substring(5, 7));
  final day = int.parse(businessDate.substring(8, 10));
  return '$day ${months[month - 1]}';
}

/// A span of time as a person would say it, to one unit.
///
/// **Rounded to the unit that carries the meaning.** "2 days" is what somebody
/// acts on; "2 days, 4 hours and 11 minutes" is a measurement of something
/// nobody was timing that precisely.
String reportDuration(Duration span) {
  if (span.inDays >= 1) {
    final days = span.inDays;
    return '$days ${days == 1 ? 'day' : 'days'}';
  }
  if (span.inHours >= 1) {
    final hours = span.inHours;
    return '$hours ${hours == 1 ? 'hour' : 'hours'}';
  }
  final minutes = span.inMinutes;
  return '$minutes ${minutes == 1 ? 'minute' : 'minutes'}';
}
