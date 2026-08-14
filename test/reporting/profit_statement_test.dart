import 'package:flutter/material.dart';
import 'package:flutter_application_1/reporting/reporting.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a complete figure is shown, and says that it is complete', (
    tester,
  ) async {
    await _pump(
      tester,
      TenantProfitReport.from(
        sales: 1250.5,
        profit: 430.25,
        incompleteCostLineCount: 0,
      ),
      currency: 'KES',
    );

    // **Two figures, not one sentence, as of `design.md` §11 step 8.** The
    // facts are the same and the margin is still only shown where there is one;
    // what changed is that each is a `numeric.body` figure on its own line
    // rather than two numbers inside a sentence.
    expect(_text(tester, 'day-profit'), 'KES 430.25');
    expect(_text(tester, 'day-margin'), '34.4%');
    expect(find.text('Profit'), findsOne);
    expect(find.text('Margin'), findsOne);
    // The positive form of the requirement. A reader cannot tell a complete
    // figure from an overstated one by looking at it, so it is stated.
    expect(
      _text(tester, 'day-profit-note'),
      'Every sale line behind it carries a cost.',
    );
  });

  testWidgets('a loss is reported as one', (tester) async {
    await _pump(
      tester,
      TenantProfitReport.from(
        sales: 100,
        profit: -25,
        incompleteCostLineCount: 0,
      ),
      currency: 'KES',
    );

    expect(_text(tester, 'day-profit'), 'KES -25.00');
    expect(_text(tester, 'day-margin'), '-25.0%');
  });

  testWidgets('a period that took nothing carries no margin', (tester) async {
    await _pump(
      tester,
      TenantProfitReport.from(sales: 0, profit: 0, incompleteCostLineCount: 0),
      currency: 'KES',
    );

    // The figure survives and the margin line is absent entirely, rather than
    // being a percentage of nothing.
    expect(_text(tester, 'day-profit'), 'KES 0.00');
    expect(find.byKey(const ValueKey('day-margin')), findsNothing);
    expect(find.text('Margin'), findsNothing);
  });

  testWidgets('an unpublished currency loses the label, not the figure', (
    tester,
  ) async {
    await _pump(
      tester,
      TenantProfitReport.from(
        sales: 1250.5,
        profit: 430.25,
        incompleteCostLineCount: 0,
      ),
    );

    expect(_text(tester, 'day-profit'), '430.25');
    expect(_text(tester, 'day-margin'), '34.4%');
  });

  testWidgets('uncosted lines withhold the figure and name the count', (
    tester,
  ) async {
    await _pump(
      tester,
      TenantProfitReport.from(
        sales: 4820.75,
        profit: 4820.75,
        incompleteCostLineCount: 96,
      ),
      currency: 'KES',
    );

    // No figure at all: the count is not a caveat beside a number, it is the
    // reason there is no number.
    expect(find.byKey(const ValueKey('day-profit')), findsNothing);
    expect(find.textContaining('4820.75'), findsNothing);
    expect(
      _text(tester, 'day-profit-note'),
      'Profit and margin are not shown: 96 sale lines have no cost recorded, '
      'and counting them as free would overstate both.',
    );
  });

  testWidgets('one uncosted line reads in the singular', (tester) async {
    await _pump(
      tester,
      TenantProfitReport.from(
        sales: 100,
        profit: 90,
        incompleteCostLineCount: 1,
      ),
      currency: 'KES',
    );

    expect(
      _text(tester, 'day-profit-note'),
      'Profit and margin are not shown: 1 sale line has no cost recorded, and '
      'counting it as free would overstate both.',
    );
  });

  testWidgets('a figure larger than the takings is refused as untrustworthy', (
    tester,
  ) async {
    await _pump(
      tester,
      TenantProfitReport.from(
        sales: 100,
        profit: 250,
        incompleteCostLineCount: 4,
      ),
      currency: 'KES',
    );

    expect(find.byKey(const ValueKey('day-profit')), findsNothing);
    // Named as an impossible figure rather than as missing cost data, even
    // though four lines are also missing one.
    expect(
      _text(tester, 'day-profit-note'),
      'Profit and margin are not shown: the reported profit is larger than the '
      'takings it was computed from, so the figure cannot be trusted.',
    );
  });

  testWidgets('two statements on one screen keep their own keys', (
    tester,
  ) async {
    final complete = TenantProfitReport.from(
      sales: 100,
      profit: 40,
      incompleteCostLineCount: 0,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TenantProfitStatement(
                report: complete,
                currency: TenantReportingCurrency.unknown,
                keyPrefix: 'daily-summary-2026-08-07',
              ),
              TenantProfitStatement(
                report: complete,
                currency: TenantReportingCurrency.unknown,
                keyPrefix: 'daily-summary-2026-08-08',
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('daily-summary-2026-08-07-profit')),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('daily-summary-2026-08-08-profit')),
      findsOne,
    );
  });
}

String? _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data;

Future<void> _pump(
  WidgetTester tester,
  TenantProfitReport report, {
  String? currency,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TenantProfitStatement(
          report: report,
          currency: currency == null
              ? TenantReportingCurrency.unknown
              : await _published(currency),
          keyPrefix: 'day',
        ),
      ),
    ),
  );
}

/// A currency read the way every reporting surface reads one: from the
/// business's own published checkout configuration, never from a constant here.
Future<TenantReportingCurrency> _published(String code) =>
    TenantReportingCurrency.read(
      session: TenantSession.active(
        uid: 'user-a',
        tenantId: 'tenant-a',
        role: TenantRole.owner,
      ),
      reader: _Reader(code),
    );

final class _Reader implements TenantDocumentReader {
  const _Reader(this.code);

  final String code;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) =>
      Future<TenantDocumentSnapshot?>.value(
        path.endsWith('/configuration/checkout')
            ? TenantDocumentSnapshot(
                path: path,
                data: <String, Object?>{'currency': code},
              )
            : null,
      );
}
