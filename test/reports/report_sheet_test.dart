/// The picker offers only what the records can honour, and shows what it chose.
///
/// Both halves matter. Offering a date range over records that carry no time
/// dimension produces a document stating a period it never read; and opening on
/// a period the person cannot see means two controls describing different
/// spans, which is worse than either alone.
library;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/reports/report_document.dart';
import 'package:flutter_application_1/reports/report_file.dart';
import 'package:flutter_application_1/reports/report_period.dart';
import 'package:flutter_application_1/reports/report_run.dart';
import 'package:flutter_application_1/reports/ui/report_sheet.dart';
import 'package:flutter_application_1/theme.dart';
import 'package:flutter_test/flutter_test.dart';

/// Noon UTC on 23 September 2026.
DateTime _clock() => DateTime.utc(2026, 9, 23, 12);

void main() {
  group('the period the sheet opens on is visible', () {
    test('a range sheet leads with the period it defaults to', () {
      final offered = TenantReportPreset.forSupport(
        TenantReportPeriodSupport.range,
      );

      expect(
        offered.first,
        TenantReportPreset.thisMonth,
        reason:
            'Below 768 the chip bar scrolls in one line. A default sitting '
            'fifth opened off the right-hand edge, so the sheet showed no '
            'selection at all while the callout underneath described a month.',
      );
    });

    test('a day sheet leads with the day it defaults to', () {
      final offered = TenantReportPreset.forSupport(
        TenantReportPeriodSupport.dayOnly,
      );

      expect(offered.first, TenantReportPreset.today);
    });
  });

  group('only the controls the records can honour', () {
    test('records with no time dimension get no date control', () {
      expect(
        TenantReportPreset.forSupport(TenantReportPeriodSupport.snapshot),
        isEmpty,
        reason:
            'The catalog keeps no history. A date control over it would '
            'produce a document stating a period it never read, which is the '
            'one failure this whole area is built to avoid.',
      );
    });

    test('day-only records are offered no multi-day span', () {
      final offered = TenantReportPreset.forSupport(
        TenantReportPeriodSupport.dayOnly,
      );

      for (final span in <TenantReportPreset>[
        TenantReportPreset.lastSeven,
        TenantReportPreset.lastThirty,
        TenantReportPreset.thisMonth,
      ]) {
        expect(
          offered,
          isNot(contains(span)),
          reason:
              'A span these records cannot express would be quietly collapsed '
              'to a single day the person did not ask for.',
        );
      }
    });

    test('a range sheet offers every span', () {
      expect(
        TenantReportPreset.forSupport(TenantReportPeriodSupport.range),
        TenantReportPreset.values,
      );
    });
  });

  group('what each preset means', () {
    test('the spans resolve against the injected clock', () {
      expect(
        TenantReportPreset.thisMonth.periodAt(_clock()),
        TenantReportPeriod(startDate: '2026-09-01', endDate: '2026-09-23'),
        reason: 'Month to date, not the whole month.',
      );
      expect(
        TenantReportPreset.today.periodAt(_clock()),
        TenantReportPeriod.day('2026-09-23'),
      );
      expect(
        TenantReportPreset.yesterday.periodAt(_clock()),
        TenantReportPeriod.day('2026-09-22'),
      );
      expect(
        TenantReportPreset.lastSeven.periodAt(_clock()).days,
        7,
        reason: 'Seven days means seven, with today as one of them.',
      );
      expect(TenantReportPreset.lastThirty.periodAt(_clock()).days, 30);
    });
  });

  group('the sheet shows the controls and nothing about them', () {
    testWidgets('no paragraph describes the period control', (tester) async {
      await _open(tester);

      expect(
        find.byKey(const ValueKey('report-sheet-explainer')),
        findsNothing,
        reason:
            'The chips are labelled with the spans they mean. A sentence above '
            'them saying to pick a span is a line to scroll past on the way to '
            'the same chips.',
      );
    });

    testWidgets('no callout restates the period the chips already show', (
      tester,
    ) async {
      await _open(tester);

      expect(
        find.byKey(const ValueKey('report-sheet-scope')),
        findsNothing,
        reason:
            'The selected chip says which period this is, and the document '
            'says so on its own first page. A third copy in between was two '
            'more than the person needed.',
      );
    });

    testWidgets('a snapshot report still says why it has no date control', (
      tester,
    ) async {
      await _open(tester, support: TenantReportPeriodSupport.snapshot);

      expect(
        find.byKey(const ValueKey('report-sheet-explainer')),
        findsOne,
        reason:
            'Here the sentence is not a description of a control - it is the '
            'reason there is no control, and without it the sheet offers a '
            'format for a period it never mentions.',
      );
    });
  });

  group('the period is one button onto the calendar', () {
    testWidgets('it opens on this month, like expenses', (tester) async {
      await _open(tester);

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('report-sheet-period')),
          matching: find.text('This month'),
        ),
        findsOne,
      );
      expect(
        find.byKey(const ValueKey('report-sheet-presets')),
        findsNothing,
        reason:
            'The spans are shortcuts inside the calendar now, not a chip bar '
            'in front of it.',
      );
    });

    testWidgets('a range picked on the calendar reaches the request', (
      tester,
    ) async {
      final request = await _open(
        tester,
        andThen: (tester) async {
          await tester.tap(find.byKey(const ValueKey('report-sheet-period')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('period-picker-day-2026-09-03')),
          );
          await tester.pump();
          await tester.tap(
            find.byKey(const ValueKey('period-picker-day-2026-09-10')),
          );
          await tester.pump();
          await tester.tap(find.byKey(const ValueKey('period-picker-done')));
          await tester.pumpAndSettle();

          expect(find.text('3 Sep - 10 Sep'), findsOne);

          await tester.tap(find.byKey(const ValueKey('report-sheet-create')));
          await tester.pumpAndSettle();
        },
      );

      expect(
        request?.period,
        TenantReportPeriod(startDate: '2026-09-03', endDate: '2026-09-10'),
      );
    });

    testWidgets('a day-only report is offered one day at a time', (
      tester,
    ) async {
      final request = await _open(
        tester,
        support: TenantReportPeriodSupport.dayOnly,
        andThen: (tester) async {
          expect(find.text('Today'), findsOne);
          await tester.tap(find.byKey(const ValueKey('report-sheet-period')));
          await tester.pumpAndSettle();

          expect(
            find.byKey(const ValueKey('report-preset-thisMonth')),
            findsNothing,
          );
          await tester.tap(
            find.byKey(const ValueKey('period-picker-day-2026-09-03')),
          );
          await tester.pump();
          await tester.tap(
            find.byKey(const ValueKey('period-picker-day-2026-09-10')),
          );
          await tester.pump();
          await tester.tap(find.byKey(const ValueKey('period-picker-done')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('report-sheet-create')));
          await tester.pumpAndSettle();
        },
      );

      expect(
        request?.period,
        TenantReportPeriod.day('2026-09-10'),
        reason: 'A second tap moves the day rather than making a range.',
      );
    });

    testWidgets('a snapshot report has no period control', (tester) async {
      await _open(tester, support: TenantReportPeriodSupport.snapshot);

      expect(find.byKey(const ValueKey('report-sheet-period')), findsNothing);
    });
  });

  group('the format, and where the file goes', () {
    testWidgets('each format is a card naming what it is', (tester) async {
      await _open(tester);

      for (final format in TenantReportFormat.values) {
        final card = find.byKey(ValueKey('report-format-${format.name}'));
        expect(card, findsOne);
        expect(
          find.descendant(of: card, matching: find.byType(Icon)),
          findsOne,
        );
        expect(
          find.descendant(of: card, matching: find.text(format.description)),
          findsOne,
        );
      }
    });

    testWidgets('the format picked reaches the request', (tester) async {
      final request = await _open(
        tester,
        andThen: (tester) async {
          await tester.tap(find.byKey(const ValueKey('report-format-excel')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('report-sheet-create')));
          await tester.pumpAndSettle();
        },
      );

      expect(request?.format, TenantReportFormat.excel);
    });

    testWidgets('a copy is saved without asking where', (tester) async {
      final request = await _open(
        tester,
        andThen: (tester) async {
          expect(find.text('WHEN IT IS READY'), findsNothing);
          expect(
            find.byKey(const ValueKey('report-destination-share')),
            findsNothing,
          );
          await tester.tap(find.byKey(const ValueKey('report-sheet-create')));
          await tester.pumpAndSettle();
        },
      );

      expect(request?.destination, TenantReportDestination.device);
      expect(
        request?.format,
        TenantReportFormat.pdf,
        reason: 'Untouched, so the sheet still answers with its own default.',
      );
    });

    testWidgets('creating carries the period the button is showing', (
      tester,
    ) async {
      final request = await _open(
        tester,
        andThen: (tester) async {
          await tester.tap(find.byKey(const ValueKey('report-sheet-create')));
          await tester.pumpAndSettle();
        },
      );

      expect(
        request?.period,
        TenantReportPreset.thisMonth.periodAt(_clock()),
        reason: 'This month is what the sheet opens on, as expenses does.',
      );
    });
  });

  group('the way out, and the room to reach it', () {
    testWidgets('cancel closes the sheet and asks for nothing', (tester) async {
      final request = await _open(
        tester,
        andThen: (tester) async {
          await tester.tap(find.byKey(const ValueKey('report-sheet-cancel')));
          await tester.pumpAndSettle();
        },
      );

      expect(request, isNull);
    });

    testWidgets('a tap outside the sheet does not throw the form away', (
      tester,
    ) async {
      await _open(tester);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('report-sheet-create')),
        findsOne,
        reason:
            'A scrim tap while reaching for a card threw the choices away. '
            'Cancel is the way out, and it is drawn.',
      );
    });

    testWidgets('both actions clear the system bar at the bottom', (
      tester,
    ) async {
      tester.view.viewPadding = const FakeViewPadding(bottom: 48);
      tester.view.padding = const FakeViewPadding(bottom: 48);

      await _open(tester);

      final floor =
          tester.view.physicalSize.height / tester.view.devicePixelRatio - 48;

      for (final action in <String>[
        'report-sheet-create',
        'report-sheet-cancel',
      ]) {
        expect(
          tester.getRect(find.byKey(ValueKey(action))).bottom,
          lessThanOrEqualTo(floor),
          reason:
              '$action is drawn under the phone\'s gesture bar. A sheet is '
              'anchored to the bottom of the screen and the system draws over '
              'that strip.',
        );
      }
    });

    testWidgets('the actions cannot be scrolled out of reach', (tester) async {
      await _open(tester);

      // Everything the list can give, and then some.
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('report-sheet-cancel')),
        findsOne,
        reason:
            'The footer sits outside the scrollable. Padding the foot of the '
            'list did not help on a 720x1600 phone, where the choices are '
            'taller than the sheet and the buttons were simply below the '
            'fold - which a 1080x2400 emulator never showed.',
      );
      expect(find.byKey(const ValueKey('report-sheet-create')), findsOne);
    });
  });
}

/// Opens the picker over a bare app, runs [andThen] inside it, and answers
/// whatever the sheet popped with.
Future<TenantReportRequest?> _open(
  WidgetTester tester, {
  TenantReportPeriodSupport support = TenantReportPeriodSupport.range,
  Future<void> Function(WidgetTester tester)? andThen,
}) async {
  TenantReportRequest? request;

  // **A phone's proportions, because the sheet is a fraction of them.** At the
  // 800x600 default the half detent is 420 logical pixels, the list scrolls,
  // and a `ListView` does not build what is below the fold - so the create and
  // cancel buttons are not in the tree to be found, let alone tapped.
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(412, 1400);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async => request = await showTenantReportSheet(
                context,
                kind: TenantReportKind.sales,
                support: support,
                clock: _clock,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  await andThen?.call(tester);
  return request;
}
