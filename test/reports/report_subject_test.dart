import 'package:flutter/material.dart';
import 'package:uzapay_pos/reports/report_document.dart';
import 'package:uzapay_pos/reports/report_file.dart';
import 'package:uzapay_pos/reports/report_period.dart';
import 'package:uzapay_pos/reports/report_run.dart';
import 'package:uzapay_pos/reports/ui/report_sheet.dart';
import 'package:uzapay_pos/theme.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/documents.dart';

/// The subject a report may be narrowed to - one supplier, one product - and
/// the promise that a report declaring none is exactly as it was.
void main() {
  testWidgets('a report with no subject shows no chooser', (tester) async {
    await _open(tester, subject: null);

    expect(find.byKey(const ValueKey('report-sheet-subject')), findsNothing);
    expect(find.byKey(const ValueKey('report-sheet-period')), findsOneWidget);
  });

  testWidgets('the chooser opens on all of them, and a request carries none', (
    tester,
  ) async {
    final request = await _open(
      tester,
      subject: _subject(),
      andThen: (tester) async {
        expect(
          find.byKey(const ValueKey('report-sheet-subject')),
          findsOneWidget,
        );
        expect(find.text('All suppliers'), findsWidgets);
        await tester.tap(find.byKey(const ValueKey('report-sheet-create')));
        await tester.pumpAndSettle();
      },
    );

    expect(request!.subject, isNull);
  });

  testWidgets('one chosen supplier travels with the request, inactive ones listed', (
    tester,
  ) async {
    final request = await _open(
      tester,
      subject: _subject(),
      andThen: (tester) async {
        await tester.tap(find.byKey(const ValueKey('report-sheet-subject')));
        await tester.pumpAndSettle();
        expect(find.text('XYZ Wholesale (inactive)'), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey('report-sheet-subject-sp_abc')).last,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('report-sheet-create')));
        await tester.pumpAndSettle();
      },
    );

    expect(request!.subject!.id, 'sp_abc');
  });

  testWidgets('a list that cannot be read still offers the report over all', (
    tester,
  ) async {
    final request = await _open(
      tester,
      subject: TenantReportSubject(
        label: 'Supplier',
        allLabel: 'All suppliers',
        loadOptions: () async => throw StateError('offline'),
      ),
      andThen: (tester) async {
        expect(
          find.byKey(const ValueKey('report-sheet-subject-unread')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('report-sheet-create')));
        await tester.pumpAndSettle();
      },
    );

    expect(request, isNotNull);
    expect(request!.subject, isNull);
  });

  test('a run with a subject builds for the one chosen', () async {
    TenantReportSubjectOption? built;
    final run = TenantReportRun.withSubject(
      kind: TenantReportKind.suppliers,
      support: TenantReportPeriodSupport.range,
      subject: _subject(),
      saver: _Saver(),
      buildForSubject: (period, subject) async {
        built = subject;
        return fixtureDocument();
      },
    );

    await run.deliver(
      TenantReportRequest(
        period: fixturePeriod(),
        format: TenantReportFormat.excel,
        destination: TenantReportDestination.device,
        subject: const TenantReportSubjectOption(id: 'sp_abc', label: 'ABC'),
      ),
    );

    expect(built?.id, 'sp_abc');
  });

  test('a subject names itself in a filename in lowercase words', () {
    expect(
      const TenantReportSubjectOption(id: 'sp_1', label: 'ABC  Distributors Ltd.')
          .slug,
      'abc-distributors-ltd',
    );
  });
}

TenantReportSubject _subject() => TenantReportSubject(
  label: 'Supplier',
  allLabel: 'All suppliers',
  loadOptions: () async => const <TenantReportSubjectOption>[
    TenantReportSubjectOption(id: 'sp_abc', label: 'ABC Distributors'),
    TenantReportSubjectOption(
      id: 'sp_xyz',
      label: 'XYZ Wholesale',
      note: 'inactive',
    ),
  ],
);

final class _Saver implements TenantReportSaver {
  @override
  Future<TenantReportSaveOutcome> save(
    TenantReportFile file, {
    TenantReportDestination destination = TenantReportDestination.device,
  }) async => TenantReportSaveOutcome.saved;
}

Future<TenantReportRequest?> _open(
  WidgetTester tester, {
  required TenantReportSubject? subject,
  Future<void> Function(WidgetTester tester)? andThen,
}) async {
  TenantReportRequest? request;
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
                kind: TenantReportKind.suppliers,
                support: TenantReportPeriodSupport.range,
                subject: subject,
                clock: fixtureClock,
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
