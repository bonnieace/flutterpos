/// Writes sample reports to `screenshots/reports/` so a person can look at them.
///
/// **This exists because nothing else can check a document.** The unit tests
/// prove a report renders, names itself correctly and carries its caveats; they
/// cannot prove it is well laid out, because `pdf` does not parse its own
/// output. `tool/screenshots` cannot help either - it rasterises a Flutter
/// widget tree, and a `pw.Widget` never enters one. So fidelity is checked the
/// only way it can be: by opening the files.
///
/// It lives in `tool/` rather than `test/` for the reason the screenshot
/// harness gives - `flutter test` walks `test/`, and a file that asserts
/// nothing would make the suite baseline mean two things.
///
/// ```
/// flutter test tool/reports
/// ```
///
/// Output lands in `screenshots/reports/`, which `.gitignore` already covers.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_application_1/reporting/reporting_currency.dart';
import 'package:flutter_application_1/reports/report_people.dart';
import 'package:flutter_application_1/reports/render/pdf_report.dart';
import 'package:flutter_application_1/reports/render/report_fonts.dart';
import 'package:flutter_application_1/reports/render/report_palette.dart';
import 'package:flutter_application_1/reports/report_document.dart';
import 'package:flutter_application_1/reports/report_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:flutter_application_1/reports/analysis/expense_report.dart';
import 'package:flutter_application_1/reports/analysis/inventory_report.dart';
import 'package:flutter_application_1/reports/analysis/logs_report.dart';
import 'package:flutter_application_1/reports/analysis/production_report.dart';
import 'package:flutter_application_1/reports/analysis/returns_report.dart';
import 'package:flutter_application_1/reports/analysis/sales_report.dart';
import 'package:flutter_application_1/reports/analysis/shifts_report.dart';
import 'package:flutter_application_1/reports/analysis/staff_report.dart';
import 'package:flutter_application_1/reports/analysis/stock_counts_report.dart';
import 'package:flutter_application_1/reports/analysis/supplier_report.dart';
import 'package:flutter_application_1/reports/render/excel_report.dart';

import '../../test/reports/support/documents.dart';
import '../../test/reports/support/expenses.dart';
import '../../test/reports/support/inventory.dart';
import '../../test/reports/support/logs.dart';
import '../../test/reports/support/production.dart';
import '../../test/reports/support/returns.dart';
import '../../test/reports/support/sales.dart';
import '../../test/reports/support/shifts.dart';
import '../../test/reports/support/staff.dart';
import '../../test/reports/support/stock_counts.dart';
import '../../test/reports/support/suppliers.dart';

const String _outputDirectory = 'screenshots/reports';

void main() {
  testWidgets('sample reports', (tester) async {
    final directory = Directory(_outputDirectory);
    if (!directory.existsSync()) directory.createSync(recursive: true);

    // The brand's own faces where the bundle will give them up, which is what a
    // device gets. `load` falls back whole rather than to a document set half
    // in one family and half in another.
    late final TenantReportFonts fonts;
    await tester.runAsync(() async {
      fonts = await TenantReportFonts.load();
    });

    final renderer = TenantPdfReportRenderer(
      palette: TenantReportPalette.standard,
      fonts: fonts,
    );

    final samples = <String, TenantReportDocument>{
      // The ordinary case: a named business, a published currency, a logo.
      'sales-full': fixtureDocument(
        identity: fixtureIdentity(logo: _placeholderLogo()),
      ),
      // The commonest case in this app: a name and nothing else.
      'sales-plain': fixtureDocument(
        identity: fixtureIdentity(
          slogan: null,
          currency: TenantReportingCurrency.unknown,
        ),
      ),
      // What a capped read looks like, which is the page nobody designs and
      // everybody eventually sees.
      'sales-truncated': fixtureDocument(
        scope: TenantReportScope(
          period: fixturePeriod(),
          documentsRead: 250,
          coveredFrom: '2026-09-14',
          coveredTo: '2026-09-22',
          caveats: <TenantReportCaveat>[
            TenantReportCaveat.truncated(
              asked: fixturePeriod(),
              reachedFrom: '2026-09-14',
              reachedTo: '2026-09-22',
              records: 250,
            ),
            TenantReportCaveat.noEvidence(
              count: 3,
              of: 'shifts',
              because: 'closed without a count',
            ),
          ],
        ),
      ),
    };

    // The real thing: a month of spending through the actual analysis and the
    // actual describe(), not a hand-built document.
    final logo = _placeholderLogo();
    samples['expenses'] = describeExpenseReport(
      analysis: fixtureExpenseAnalysis(),
      identity: fixtureIdentity(logo: logo),
    );
    samples['sales'] = describeSalesReport(
      analysis: fixtureSalesAnalysis(),
      identity: fixtureIdentity(logo: logo),
    );
    samples['staff'] = describeStaffReport(
      analysis: fixtureStaffAnalysis(),
      identity: fixtureIdentity(logo: logo),
    );
    samples['returns'] = describeReturnsReport(
      analysis: fixtureReturnsAnalysis(),
      identity: fixtureIdentity(logo: logo),
      // **One name deliberately missing.** Returns is the one report a cashier
      // may generate, and a cashier may read only its own staff record, so the
      // sample has to show what that actually looks like on paper - the
      // colleague by identifier, and the caveat that says why.
      people: const TenantReportPeople(<String, String>{
        'cashier-a': 'Amina Juma',
      }),
    );
    samples['shifts'] = describeShiftsReport(
      analysis: fixtureShiftsAnalysis(),
      identity: fixtureIdentity(logo: logo),
      people: _fixturePeople,
    );
    samples['stock-counts'] = describeStockCountsReport(
      analysis: fixtureStockCountsAnalysis(),
      identity: fixtureIdentity(logo: logo),
      people: _fixturePeople,
    );
    samples['inventory'] = describeInventoryReport(
      analysis: fixtureInventoryAnalysis(),
      identity: fixtureIdentity(logo: logo),
    );
    samples['logs'] = describeLogsReport(
      analysis: fixtureLogsAnalysis(),
      identity: fixtureIdentity(logo: logo),
      people: _fixturePeople,
    );
    samples['suppliers'] = describeSupplierReport(
      analysis: fixtureSupplierAnalysis(),
      identity: fixtureIdentity(logo: logo),
    );
    samples['production'] = describeProductionReport(
      analysis: fixtureProductionAnalysis(),
      identity: fixtureIdentity(logo: logo),
    );

    final workbooks = TenantExcelReportRenderer.standard();
    for (final MapEntry(key: name, value: document) in samples.entries) {
      final file = await renderer.render(document);
      File('$_outputDirectory/$name.pdf').writeAsBytesSync(file.bytes);
      final book = await workbooks.render(document);
      File('$_outputDirectory/$name.xlsx').writeAsBytesSync(book.bytes);
      // ignore: avoid_print
      print(
        '  $_outputDirectory/$name  '
        'pdf ${file.sizeInBytes} / xlsx ${book.sizeInBytes} bytes',
      );
    }

    expect(
      Directory(_outputDirectory).listSync().whereType<File>().length,
      greaterThanOrEqualTo(samples.length),
      reason: 'Every sample should have reached disk for somebody to open.',
    );
  });
}

/// A stand-in mark, so the branding lockup is exercised.
///
/// Deliberately not square and not the tidy size the layout would prefer - a
/// real business uploads whatever it has, and a lockup that only works on a
/// perfect asset does not work.
img.Image _buildMark() {
  final mark = img.Image(width: 240, height: 160);
  img.fill(mark, color: img.ColorRgb8(0x2C, 0x53, 0x40));
  img.fillCircle(
    mark,
    x: 120,
    y: 80,
    radius: 54,
    color: img.ColorRgb8(0x45, 0xF2, 0x8D),
  );
  return mark;
}

Uint8List _placeholderLogo() =>
    Uint8List.fromList(img.encodePng(_buildMark()));

/// The roster the samples are drawn against.
///
/// Management opens shifts, stock counts and logs, and management may read the
/// whole directory, so every person in those three is named.
const TenantReportPeople _fixturePeople = TenantReportPeople(<String, String>{
  'cashier-a': 'Amina Juma',
  'cashier-b': 'Peter Mwangi',
  'manager-a': 'Grace Otieno',
  'owner-a': 'Bonnie Masota',
});
