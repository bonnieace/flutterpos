import 'package:flutter_test/flutter_test.dart';
import 'package:uzapay_pos/sales/trading_day_explanation.dart';
import 'package:uzapay_pos/shift/open_trading_day.dart';

void main() {
  // 01:30 on Monday 24 Aug 2026 in Nairobi.
  final now = DateTime.utc(2026, 8, 23, 22, 30);

  TenantOpenTradingDay day({
    DateTime? firstOpenedAt,
    DateTime? sellingEndsAt,
    int shiftCount = 1,
    bool isOwn = false,
  }) => TenantOpenTradingDay(
    businessDate: '2026-08-23',
    // 18:02 on Sunday.
    firstOpenedAt: firstOpenedAt ?? DateTime.utc(2026, 8, 23, 15, 2),
    // 06:00 on Monday.
    sellingEndsAt: sellingEndsAt ?? DateTime.utc(2026, 8, 24, 3),
    shiftCount: shiftCount,
    isOwn: isOwn,
  );

  test('a colleague’s shift, read by a manager', () {
    final explanation = TradingDayExplanation.of(day(), now: now);

    expect(explanation.eyebrow, 'SUN 23 AUG · BUSINESS DAY');
    expect(explanation.title, 'Still trading on Sunday');
    expect(explanation.weekday, 'Sunday');
    expect(
      explanation.body,
      'Sales made since midnight count toward Sunday until the shift is '
      'closed, or 06:00 at the latest.',
    );
    final night = explanation.night!;
    expect(night.opened, '18:02');
    expect(night.openedWord, 'opened');
    expect(night.ends, '06:00');
    expect(night.endsWord, 'stops');
    expect(night.now, '01:30');
    // 7 h 28 of 11 h 58, and midnight at 5 h 58.
    expect(night.nowAt, closeTo(0.624, 0.001));
    expect(night.midnightAt, closeTo(0.499, 0.001));
    expect(night.showsMidnight, isTrue);
    expect(night.nowAnchor, TradingNightAnchor.centre);
    expect(
      night.semanticsLabel,
      'Shift opened 18:02 on Sunday. It is now 01:30. It stops selling at '
      '06:00.',
    );
  });

  test('the reader’s own shift is spoken to them', () {
    final explanation = TradingDayExplanation.of(day(isOwn: true), now: now);

    expect(
      explanation.body,
      'Your shift from Sunday is still open, so your sales since midnight '
      'count toward Sunday until you close it, or 06:00 at the latest.',
    );
    expect(explanation.night!.semanticsLabel, startsWith('Your shift opened'));
  });

  test('a night that ends at its 24-hour cap names it', () {
    final explanation = TradingDayExplanation.of(
      day(
        // 02:10 on Sunday, so it stops at 02:10 on Monday.
        firstOpenedAt: DateTime.utc(2026, 8, 22, 23, 10),
        sellingEndsAt: DateTime.utc(2026, 8, 23, 23, 10),
      ),
      now: now,
    );

    expect(
      explanation.body,
      'Sales made since midnight count toward Sunday until the shift is '
      'closed, or 02:10, when it reaches 24 hours.',
    );
    final night = explanation.night!;
    expect(night.endsWord, '24 h');
    // Midnight is 91% of the way along: its label would sit on the stop.
    expect(night.midnightAt, closeTo(0.910, 0.001));
    expect(night.showsMidnight, isFalse);
    // Now is 97% along, so its label ends at the mark rather than running off.
    expect(night.nowAnchor, TradingNightAnchor.end);
  });

  test('several shifts are counted, and the night starts at the first', () {
    final explanation = TradingDayExplanation.of(
      day(shiftCount: 2, firstOpenedAt: DateTime.utc(2026, 8, 23, 14, 40)),
      now: now,
    );

    expect(
      explanation.body,
      'Two shifts from Sunday are still open, so sales made since midnight '
      'count toward Sunday until they are closed, or 06:00 at the latest.',
    );
    expect(explanation.night!.opened, '17:40');
    expect(explanation.night!.openedWord, 'first opened');
  });

  test('just past midnight the now label still sits on its mark', () {
    final night = TradingDayExplanation.of(
      day(),
      now: DateTime.utc(2026, 8, 23, 21, 5),
    ).night!;

    expect(night.now, '00:05');
    expect(night.nowAnchor, TradingNightAnchor.centre);
  });

  test('a night with no known start is not drawn; the sentence stands', () {
    final explanation = TradingDayExplanation.of(
      TenantOpenTradingDay(
        businessDate: '2026-08-23',
        firstOpenedAt: null,
        sellingEndsAt: DateTime.utc(2026, 8, 24, 3),
        shiftCount: 1,
        isOwn: false,
      ),
      now: now,
    );

    expect(explanation.night, isNull);
    expect(explanation.title, 'Still trading on Sunday');
  });
}
