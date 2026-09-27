/// The report sheet and the period calendar it opens, on a phone.
///
/// **Four frames:** the sheet as it opens (this month, PDF), the calendar on
/// that month, a range being picked across it, and the months view.
library;

import 'package:flutter/material.dart';
import 'package:uzapay_pos/reports/report_document.dart';
import 'package:uzapay_pos/reports/report_period.dart';
import 'package:uzapay_pos/reports/ui/report_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

DateTime _clock() => DateTime.utc(2026, 9, 23, 12);

void main() {
  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> calendar(WidgetTester tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('report-sheet-period')));
    await tester.pumpAndSettle();
  }

  screenshotCase(
    '97-report-sheet',
    viewports: const <ScreenshotViewport>[mobileViewport],
    fullPage: false,
    build: () => const _Opener(),
    afterPump: open,
  );

  screenshotCase(
    '97-report-period-calendar',
    viewports: const <ScreenshotViewport>[mobileViewport],
    fullPage: false,
    build: () => const _Opener(),
    afterPump: calendar,
  );

  screenshotCase(
    '97-report-period-range',
    viewports: const <ScreenshotViewport>[mobileViewport],
    fullPage: false,
    build: () => const _Opener(),
    afterPump: (tester) async {
      await calendar(tester);
      await tester.tap(
        find.byKey(const ValueKey('period-picker-day-2026-09-07')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('period-picker-day-2026-09-16')),
      );
      await tester.pumpAndSettle();
    },
  );

  screenshotCase(
    '97-report-period-months',
    viewports: const <ScreenshotViewport>[mobileViewport],
    fullPage: false,
    build: () => const _Opener(),
    afterPump: (tester) async {
      await calendar(tester);
      await tester.tap(find.byKey(const ValueKey('period-picker-heading')));
      await tester.pumpAndSettle();
    },
  );
}

final class _Opener extends StatelessWidget {
  const _Opener();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => showTenantReportSheet(
          context,
          kind: TenantReportKind.sales,
          support: TenantReportPeriodSupport.range,
          clock: _clock,
        ),
        child: const Text('Open'),
      ),
    ),
  );
}
