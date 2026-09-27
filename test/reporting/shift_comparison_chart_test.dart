import 'package:flutter/material.dart';
import 'package:uzapay_pos/reporting/reporting.dart';
import 'package:uzapay_pos/shift/shift_history.dart';
import 'package:uzapay_pos/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('comparedShifts', () {
    test('orders by the instant the record holds, not by document ID', () {
      // The chart prints each start time, so reading the order off anything
      // else is how it comes to disagree with its own labels.
      final ordered = comparedShifts(<TenantShiftDaySlice>[
        _shift(id: 'shift-900', hour: 6),
        _shift(id: 'shift-100', hour: 18),
        _shift(id: 'shift-500', hour: 12),
      ]);

      expect(ordered.map((shift) => shift.startedAt!.hour), <int>[6, 12, 18]);
    });

    test('a shift with no recorded start sorts last and is not dropped', () {
      // It still took money.
      final ordered = comparedShifts(<TenantShiftDaySlice>[
        _shift(id: 'shift-200', hour: null),
        _shift(id: 'shift-100', hour: 9),
      ]);

      expect(ordered.length, 2);
      expect(ordered.last.startedAt, isNull);
    });

    test('caps the columns rather than drawing an unreadable one', () {
      final ordered = comparedShifts(<TenantShiftDaySlice>[
        for (var hour = 1; hour <= 9; hour++)
          _shift(id: 'shift-${hour}00', hour: hour),
      ]);

      expect(ordered.length, maximumComparedShifts);
      expect(ordered.first.startedAt!.hour, 1, reason: 'oldest first');
    });
  });

  group('ShiftComparisonChart', () {
    testWidgets('prints every bar figure and every name', (tester) async {
      // Hard rule 4: the chart is never the whole statement.
      await _pump(tester, <TenantShiftDaySlice>[
        _shift(id: 'shift-100', hour: 6, salesMinor: 1840000),
        _shift(id: 'shift-200', hour: 12, salesMinor: 2170000),
      ]);

      expect(find.text('18.4k'), findsOne);
      expect(find.text('21.7k'), findsOne);
      // The given name, because a full one ellipsises to nothing at five
      // columns. One per column, and this fixture calls both cashiers the
      // same thing.
      expect(find.text('Grace'), findsExactly(2));
      // Rendered in the reader's own zone, so the expectation is computed
      // rather than written as a literal - a hard-coded UTC clock would pass
      // only on a machine at UTC.
      expect(find.text(_localClock(6)), findsOne);
      expect(find.text(_localClock(12)), findsOne);
    });

    testWidgets('a running shift says Open rather than a figure', (
      tester,
    ) async {
      // Its takings are written by the close, so a filled bar at any height
      // would be inventing a number.
      await _pump(tester, <TenantShiftDaySlice>[
        _shift(id: 'shift-100', hour: 6, salesMinor: 1840000),
        _shift(id: 'shift-200', hour: 12, salesMinor: 2170000),
        _shift(id: 'shift-300', hour: 18),
      ]);

      expect(find.text('Open'), findsOne);
      expect(find.text('18.4k'), findsOne);
      expect(find.text('21.7k'), findsOne);
    });

    testWidgets('a running shift does not set the scale it is not on', (
      tester,
    ) async {
      // **The drift this chart was one edit away from.** A shift carries
      // totals while it runs, and they are partial - the close writes the
      // real ones. The bar refuses to plot them, so letting them set the
      // ceiling would shrink every real bar against a figure drawn nowhere.
      await _pump(tester, <TenantShiftDaySlice>[
        _shift(id: 'shift-100', hour: 6, salesMinor: 40000),
        _shift(id: 'shift-200', hour: 12, salesMinor: 20000),
        _openShiftHolding(id: 'shift-300', hour: 18, partialMinor: 900000),
      ]);

      // The taller closed shift reaches the ceiling, rather than a ninth of it.
      final tallest = tester.getSize(
        find.byKey(const ValueKey<String>('shift-bar-shift-100')),
      );
      expect(
        tallest.height,
        ShiftComparisonChart.plotHeight - ShiftComparisonChart.labelHeight,
      );
      // And the running shift is still drawn with no height of its own.
      expect(
        tester
            .getSize(find.byKey(const ValueKey<String>('shift-bar-shift-300')))
            .height,
        ShiftComparisonChart.minimumBar,
      );
      expect(find.text('9000'), findsNothing, reason: 'a partial total');
    });

    testWidgets('one closed shift and one running one is not a chart', (
      tester,
    ) async {
      // **The morning case, and the common one.** An open shift has no height,
      // so plotting here reserves 132 pixels to draw a single bar against
      // nothing - the void reads as missing data rather than as a scale. Both
      // shifts are still stated, in full rather than abbreviated, because a
      // row has the width a column did not.
      await _pump(tester, <TenantShiftDaySlice>[
        _shift(id: 'shift-100', hour: 6, salesMinor: 1840000),
        _shift(id: 'shift-200', hour: 18),
      ]);

      expect(find.text('18.4k'), findsNothing, reason: 'no bar to label');
      expect(find.text('18400'), findsOne);
      expect(find.text('Open'), findsOne);
      // The whole name, not the given one: a row is not five columns wide.
      expect(find.text('Grace Wanjiru'), findsExactly(2));
    });

    testWidgets('announces the whole name, not the shortened one', (
      tester,
    ) async {
      await _pump(tester, <TenantShiftDaySlice>[
        _shift(id: 'shift-100', hour: 6, salesMinor: 1840000),
      ]);

      expect(
        find.bySemanticsLabel(RegExp('Grace Wanjiru')),
        findsOne,
        reason: 'a screen reader has no width limit',
      );
    });
  });
}

/// What the chart will print for a shift started at [utcHour], in this
/// machine's zone.
String _localClock(int utcHour) {
  final local = DateTime.utc(2026, 7, 31, utcHour).toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

Future<void> _pump(
  WidgetTester tester,
  List<TenantShiftDaySlice> shifts,
) async {
  tester.view.physicalSize = const Size(411, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: Scaffold(
        body: ShiftComparisonChart(
          shifts: comparedShifts(shifts),
          currency: TenantReportingCurrency.unknown,
          nameFor: (_) => 'Grace Wanjiru',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// A shift still running that already carries the totals written so far.
///
/// This is what the seeded fixtures hold and what a real open shift looks
/// like mid-day, which is why the chart cannot treat "has a total" as "can be
/// drawn".
TenantShiftDaySlice _openShiftHolding({
  required String id,
  required int hour,
  required int partialMinor,
}) => TenantShiftDaySlice.fromDocument(
  path: 'tenants/tenant-a/shifts/$id',
  data: <String, Object?>{
    'shiftId': id,
    'tenantId': 'tenant-a',
    'staffId': 'user-a',
    'deviceId': 'dev-0123456789abcdef01234567deadbeef',
    'businessDate': '2026-07-31',
    'status': 'open',
    'startTime': DateTime.utc(2026, 7, 31, hour),
    'totalSalesMinor': partialMinor,
    'totalSales': partialMinor / 100,
    'transactionCount': 3,
  },
);

TenantShiftDaySlice _shift({
  required String id,
  required int? hour,
  int? salesMinor,
}) => TenantShiftDaySlice.fromDocument(
  path: 'tenants/tenant-a/shifts/$id',
  data: <String, Object?>{
    'shiftId': id,
    'tenantId': 'tenant-a',
    'staffId': 'user-a',
    'deviceId': 'dev-0123456789abcdef01234567deadbeef',
    'businessDate': '2026-07-31',
    'status': salesMinor == null ? 'open' : 'closed',
    if (hour != null) 'startTime': DateTime.utc(2026, 7, 31, hour),
    if (salesMinor != null) ...<String, Object?>{
      'closingCashMinor': salesMinor,
      'totalSalesMinor': salesMinor,
      'totalSales': salesMinor / 100,
      'transactionCount': 6,
    },
  },
);
