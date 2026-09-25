import 'package:flutter_application_1/production/production_batch.dart';
import 'package:flutter_application_1/reports/analysis/production_analysis.dart';
import 'package:flutter_application_1/reports/analysis/production_report.dart';
import 'package:flutter_application_1/reports/render/excel_report.dart';
import 'package:flutter_application_1/reports/render/pdf_report.dart';
import 'package:flutter_application_1/reports/report_document.dart';
import 'package:flutter_application_1/reports/report_run.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/documents.dart';

/// What the production report says: what was made, what it cost, and how the
/// cost of one unit moved.
void main() {
  test('products are ranked by what they cost to make, with their movement', () {
    final analysis = TenantProductionAnalysis.from(
      period: fixturePeriod(),
      batches: _batches(),
    );

    expect(analysis.products.map((row) => row.productName), <String>[
      'White bread loaf',
      'Mandazi',
    ]);
    expect(analysis.batchCount, 3);
    expect(analysis.unitCount, 100 + 100 + 200);
    expect(analysis.spentMinor, 280000 + 300000 + 100000);
    final bread = analysis.products.first;
    expect(bread.firstUnitCostMinor, 2800);
    expect(bread.latestUnitCostMinor, 3000);
    expect(bread.change, closeTo(200 / 2800, 1e-9));
    // One batch has no movement to speak of.
    expect(analysis.products.last.change, isNull);
    expect(analysis.moved.single.productName, 'White bread loaf');
  });

  test('one product\'s report charts its cost per unit batch by batch', () {
    final document = describeProductionReport(
      identity: fixtureIdentity(),
      analysis: TenantProductionAnalysis.from(
        period: fixturePeriod(),
        batches: _batches().where((b) => b.productId == 'prod-bread').toList(),
        subject: const TenantReportSubjectOption(
          id: 'prod-bread',
          label: 'White bread loaf',
        ),
      ),
    );

    expect(document.title, 'Production report · White bread loaf');
    expect(
      document.sections.map((section) => section.heading),
      contains('Cost per unit, batch by batch'),
    );
    expect(
      document.headline.map((figure) => figure.label),
      contains('Latest cost per unit'),
    );
    expect(
      document.filename(TenantReportFormat.excel),
      contains('-production-white-bread-loaf-'),
    );
  });

  test('says production costs are not Expenses', () {
    final document = describeProductionReport(
      identity: fixtureIdentity(),
      analysis: TenantProductionAnalysis.from(
        period: fixturePeriod(),
        batches: _batches(),
      ),
    );

    final byProduct = document.sections.firstWhere(
      (section) => section.heading == 'By product',
    );
    expect(byProduct.notes.single, contains('not in Expenses'));
  });

  test('renders as a PDF and as a workbook', () async {
    for (final batches in <List<TenantProductionBatch>>[
      _batches(),
      _batches().where((b) => b.productId == 'prod-bread').toList(),
      const <TenantProductionBatch>[],
    ]) {
      final document = describeProductionReport(
        identity: fixtureIdentity(),
        analysis: TenantProductionAnalysis.from(
          period: fixturePeriod(),
          batches: batches,
        ),
      );

      expect(
        (await TenantPdfReportRenderer.standard().render(document)).bytes,
        isNotEmpty,
      );
      expect(
        (await TenantExcelReportRenderer.standard().render(document)).bytes,
        isNotEmpty,
      );
    }
  });
}

List<TenantProductionBatch> _batches() => <TenantProductionBatch>[
  _batch('pb_1', 'prod-bread', 'White bread loaf', 100, 280000, 2800, 2),
  _batch('pb_2', 'prod-bread', 'White bread loaf', 100, 300000, 3000, 9),
  _batch('pb_3', 'prod-mandazi', 'Mandazi', 200, 100000, 500, 12),
];

TenantProductionBatch _batch(
  String id,
  String productId,
  String name,
  int quantity,
  int total,
  int unit,
  int day,
) => TenantProductionBatch.fromDocument(
  path: 'tenants/tenant-a/production_batches/$id',
  data: <String, Object?>{
    'batchNumber': 'PB-202609${day.toString().padLeft(2, '0')}-AAAAAA',
    'productId': productId,
    'productName': name,
    'quantity': quantity,
    'expenses': <Map<String, Object?>>[
      <String, Object?>{'description': 'Flour', 'amountMinor': total},
    ],
    'totalCostMinor': total,
    'unitCostMinor': unit,
    'createdAt': DateTime.utc(2026, 9, day, 5),
  },
);
