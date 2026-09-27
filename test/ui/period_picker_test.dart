/// One calendar answers a day, a range and a month.
///
/// The picker replaced two Material routes and a chip bar in front of them, so
/// these pin the three answers it gives and the bounds it keeps.
library;

import 'package:flutter/material.dart';
import 'package:uzapay_pos/theme.dart';
import 'package:uzapay_pos/ui/period_picker.dart';
import 'package:flutter_test/flutter_test.dart';

final _today = DateTime(2026, 9, 23);

void main() {
  testWidgets('one tap is a day, and already a whole answer', (tester) async {
    final picked = await _pump(tester);

    await tester.tap(_day('2026-09-10'));
    await tester.pump();
    expect(find.text('Tap another day to make it a range.'), findsOne);
    await tester.tap(find.byKey(const ValueKey('period-picker-done')));

    expect(picked.value, DateTimeRange(start: _d(9, 10), end: _d(9, 10)));
  });

  testWidgets('a second tap makes a range, in either order', (tester) async {
    final picked = await _pump(tester);

    await tester.tap(_day('2026-09-18'));
    await tester.pump();
    await tester.tap(_day('2026-09-04'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('period-picker-done')));

    expect(picked.value, DateTimeRange(start: _d(9, 4), end: _d(9, 18)));
    expect(find.textContaining('15 days'), findsOne);
  });

  testWidgets('a third tap starts again from one day', (tester) async {
    final picked = await _pump(tester);

    for (final day in <String>['2026-09-04', '2026-09-18', '2026-09-07']) {
      await tester.tap(_day(day));
      await tester.pump();
    }
    await tester.tap(find.byKey(const ValueKey('period-picker-done')));

    expect(picked.value, DateTimeRange(start: _d(9, 7), end: _d(9, 7)));
  });

  testWidgets('a month is picked whole, and cut at today', (tester) async {
    final picked = await _pump(tester);

    await tester.tap(find.byKey(const ValueKey('period-picker-heading')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('period-picker-month-2026-8')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('period-picker-done')));
    expect(picked.value, DateTimeRange(start: _d(8, 1), end: _d(8, 31)));

    await tester.tap(find.byKey(const ValueKey('period-picker-heading')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('period-picker-month-2026-9')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('period-picker-done')));
    expect(
      picked.value,
      DateTimeRange(start: _d(9, 1), end: _d(9, 23)),
      reason: 'Days nobody has traded yet are not part of any period.',
    );
  });

  testWidgets('a day after the last date cannot be picked', (tester) async {
    final picked = await _pump(tester);

    await tester.tap(_day('2026-09-25'), warnIfMissed: false);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('period-picker-done')));

    expect(
      picked.value,
      DateTimeRange(start: _d(9, 1), end: _d(9, 23)),
      reason: 'The initial selection stands; the tap did nothing.',
    );
    // Nothing after this month to step to, either.
    await tester.tap(find.byKey(const ValueKey('period-picker-next')));
    await tester.pump();
    expect(find.byKey(const ValueKey('period-picker-days-2026-9')), findsOne);
  });

  testWidgets('a shortcut sets the span and shows as chosen', (tester) async {
    final picked = await _pump(
      tester,
      shortcuts: <AppPeriodShortcut>[
        AppPeriodShortcut(
          key: const ValueKey('shortcut-week'),
          label: 'Last 7 days',
          range: DateTimeRange(start: _d(9, 17), end: _d(9, 23)),
        ),
      ],
    );

    await tester.tap(find.byKey(const ValueKey('shortcut-week')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('period-picker-done')));

    expect(picked.value, DateTimeRange(start: _d(9, 17), end: _d(9, 23)));
  });

  testWidgets('with ranges off, every tap is one day and no month view', (
    tester,
  ) async {
    final picked = await _pump(tester, allowRange: false);

    await tester.tap(_day('2026-09-04'));
    await tester.pump();
    await tester.tap(_day('2026-09-18'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('period-picker-heading')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('period-picker-months-2026')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('period-picker-done')));

    expect(picked.value, DateTimeRange(start: _d(9, 18), end: _d(9, 18)));
  });

  testWidgets('seven 48dp days fit a 360 handset', (tester) async {
    await _pump(tester, width: 360);

    final cell = tester.getSize(_day('2026-09-10'));
    // The press surface paints inside the ring's gutter; its hit area is what
    // §9 measures.
    expect(tester.takeException(), isNull);
    expect(cell.width, greaterThanOrEqualTo(40));
    final row =
        tester.getRect(_day('2026-09-14')).left -
        tester.getRect(_day('2026-09-13')).left;
    expect(
      row.abs(),
      greaterThanOrEqualTo(AppPeriodPicker.cellExtent),
      reason: 'Each day owns a full 48 of the row.',
    );
  });
}

DateTime _d(int month, int day) => DateTime(2026, month, day);

Finder _day(String date) => find.byKey(ValueKey('period-picker-day-$date'));

/// Pumps the picker on this month to date and answers whatever *Done* hands
/// back, latest first.
Future<ValueNotifier<DateTimeRange?>> _pump(
  WidgetTester tester, {
  bool allowRange = true,
  List<AppPeriodShortcut> shortcuts = const <AppPeriodShortcut>[],
  double width = 412,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.reset);

  final picked = ValueNotifier<DateTimeRange?>(null);
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: Scaffold(
        body: AppPeriodPicker(
          initial: DateTimeRange(start: _d(9, 1), end: _today),
          firstDate: DateTime(2025, 9, 23),
          lastDate: _today,
          allowRange: allowRange,
          shortcuts: shortcuts,
          onDone: (range) => picked.value = range,
          onCancel: () {},
        ),
      ),
    ),
  );
  return picked;
}
