import 'package:flutter_application_1/reports/analysis/supplier_analysis.dart';
import 'package:flutter_application_1/reports/analysis/supplier_report.dart';
import 'package:flutter_application_1/reports/render/excel_report.dart';
import 'package:flutter_application_1/reports/render/pdf_report.dart';
import 'package:flutter_application_1/reports/report_document.dart';
import 'package:flutter_application_1/reports/report_run.dart';
import 'package:flutter_application_1/reports/report_scope.dart';
import 'package:flutter_application_1/suppliers/supplier_delivery.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/documents.dart';

/// What the supplier report says about a period, answered by the questions a
/// shopkeeper asks of it: who delivered, what it came to, what went up.
void main() {
  group('who delivered, and what it came to', () {
    test('suppliers are ranked by value received, and the totals add up', () {
      final analysis = TenantSupplierAnalysis.from(
        period: fixturePeriod(),
        deliveries: _deliveries(),
        restocksWithoutSupplier: 3,
      );

      expect(analysis.totals.map((row) => row.supplierName), <String>[
        'ABC Distributors',
        'Mama Njeri Flour',
      ]);
      expect(analysis.deliveryCount, 3);
      expect(analysis.unitCount, 24 + 36 + 30 + 10);
      expect(analysis.valueMinor, 24 * 4800 + 30 * 4650 + 10 * 20000);
      expect(analysis.costlessLineCount, 1);
      expect(analysis.restocksWithoutSupplier, 3);
    });

    test('a delivery received offline is reported on the day it came in', () {
      // Received on the evening of the 2nd, sent the next morning.
      final analysis = TenantSupplierAnalysis.from(
        period: fixturePeriod(),
        deliveries: <TenantSupplierDelivery>[
          _delivery(
            'sd_late',
            supplier: ('sp_abc', 'ABC Distributors'),
            at: DateTime.utc(2026, 9, 2, 17),
            arrivedAt: DateTime.utc(2026, 9, 3, 6),
            lines: <Map<String, Object?>>[
              <String, Object?>{
                'productId': 'pd-soda',
                'productName': 'Soda 500ml',
                'quantity': 24,
                'unitCostMinor': 4800,
              },
            ],
          ),
        ],
      );

      expect(analysis.rows.single.businessDate, '2026-09-02');
    });

    test('a product whose unit cost moved is named with how far', () {
      final analysis = TenantSupplierAnalysis.from(
        period: fixturePeriod(),
        deliveries: _deliveries(),
      );

      final bread = analysis.costChanges.single;
      expect(bread.productName, 'White bread loaf');
      expect(bread.firstMinor, 4650);
      expect(bread.latestMinor, 4800);
      expect(bread.change, closeTo(150 / 4650, 1e-9));
    });

    test('one supplier\'s report says nothing about restocks with no supplier', () {
      final analysis = TenantSupplierAnalysis.from(
        period: fixturePeriod(),
        deliveries: _deliveries().where((d) => d.supplierId == 'sp_abc').toList(),
        subject: const TenantReportSubjectOption(
          id: 'sp_abc',
          label: 'ABC Distributors',
        ),
        restocksWithoutSupplier: 3,
      );

      expect(analysis.restocksWithoutSupplier, isNull);
    });
  });

  group('the document', () {
    test('a narrowed report names its supplier in the title and the filename', () {
      final document = describeSupplierReport(
        identity: fixtureIdentity(),
        analysis: TenantSupplierAnalysis.from(
          period: fixturePeriod(),
          deliveries: _deliveries().where((d) => d.supplierId == 'sp_abc').toList(),
          subject: const TenantReportSubjectOption(
            id: 'sp_abc',
            label: 'ABC Distributors',
          ),
        ),
      );

      expect(document.title, 'Supplier report · ABC Distributors');
      expect(
        document.filename(TenantReportFormat.pdf),
        contains('-suppliers-abc-distributors-'),
      );
      // One supplier has nothing to rank against.
      expect(
        document.sections.map((section) => section.heading),
        isNot(contains('By supplier')),
      );
    });

    test('value received is said to be what the lines add up to, not owed', () {
      final document = describeSupplierReport(
        identity: fixtureIdentity(),
        analysis: TenantSupplierAnalysis.from(
          period: fixturePeriod(),
          deliveries: _deliveries(),
        ),
      );

      expect(document.subtitle, contains('not an amount owed'));
      final bySupplier = document.sections.firstWhere(
        (section) => section.heading == 'By supplier',
      );
      expect(bySupplier.notes.single, contains('not an amount owed'));
      // A line with no cost makes the value a floor, and the report says so.
      expect(
        document.scope.caveats.map((caveat) => caveat.kind),
        contains(TenantReportCaveatKind.missingCost),
      );
    });

    test('a capped read states the day it reached and is not complete', () {
      final document = describeSupplierReport(
        identity: fixtureIdentity(),
        analysis: TenantSupplierAnalysis.from(
          period: fixturePeriod(),
          deliveries: _deliveries(),
          truncated: true,
          reachedTo: '2026-09-15',
          recordsRead: 600,
        ),
      );

      expect(document.scope.isComplete, isFalse);
      expect(document.scope.coveredTo, '2026-09-15');
      expect(document.scope.caveats.first.sentence, contains('600 records'));
    });

    test('renders as a PDF and as a workbook', () async {
      final document = describeSupplierReport(
        identity: fixtureIdentity(),
        analysis: TenantSupplierAnalysis.from(
          period: fixturePeriod(),
          deliveries: _deliveries(),
          restocksWithoutSupplier: 3,
        ),
      );

      final pdf = await TenantPdfReportRenderer.standard().render(document);
      final excel = await TenantExcelReportRenderer.standard().render(document);

      expect(pdf.bytes, isNotEmpty);
      expect(excel.bytes, isNotEmpty);
    });

    test('an empty period is a document, not a failure', () async {
      final document = describeSupplierReport(
        identity: fixtureIdentity(),
        analysis: TenantSupplierAnalysis.from(
          period: fixturePeriod(),
          deliveries: const <TenantSupplierDelivery>[],
        ),
      );

      expect(document.sections, isEmpty);
      expect(
        (await TenantPdfReportRenderer.standard().render(document)).bytes,
        isNotEmpty,
      );
    });
  });
}

List<TenantSupplierDelivery> _deliveries() => <TenantSupplierDelivery>[
  _delivery(
    'sd_1',
    supplier: ('sp_abc', 'ABC Distributors'),
    at: DateTime.utc(2026, 9, 3, 6),
    lines: <Map<String, Object?>>[
      _line('prod-bread', 'White bread loaf', 30, 4650),
    ],
  ),
  _delivery(
    'sd_2',
    supplier: ('sp_mama', 'Mama Njeri Flour'),
    at: DateTime.utc(2026, 9, 10, 6),
    lines: <Map<String, Object?>>[_line('prod-flour', 'Flour 50kg', 10, 20000)],
  ),
  _delivery(
    'sd_3',
    supplier: ('sp_abc', 'ABC Distributors'),
    at: DateTime.utc(2026, 9, 20, 6),
    lines: <Map<String, Object?>>[
      _line('prod-bread', 'White bread loaf', 24, 4800),
      _line('prod-soap', 'Bar soap - blue', 36, null),
    ],
  ),
];

Map<String, Object?> _line(String id, String name, int quantity, int? cost) =>
    <String, Object?>{
      'productId': id,
      'productName': name,
      'quantity': quantity,
      'unitCostMinor': cost,
    };

TenantSupplierDelivery _delivery(
  String id, {
  required (String, String) supplier,
  required DateTime at,
  required List<Map<String, Object?>> lines,
  DateTime? arrivedAt,
}) => TenantSupplierDelivery.fromDocument(
  path: 'tenants/tenant-a/supplier_deliveries/$id',
  data: <String, Object?>{
    'supplierId': supplier.$1,
    'supplierName': supplier.$2,
    'reference': 'INV-$id',
    'complete': true,
    'occurredAt': at,
    'createdAt': arrivedAt ?? at,
    'lines': lines,
  },
);
