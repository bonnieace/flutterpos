/// Charts with barely any data in them.
///
/// **A one-person shop is the commonest business this app serves**, and for a
/// while it was the one the staff report could not draw: a category axis with
/// a single point has no span, the bar geometry divides by it, and the `pdf`
/// package asserts on the NaN that comes out. Every shape here is checked
/// against the smallest and flattest data it can be handed.
library;

import 'package:flutter_application_1/reports/render/pdf_report.dart';
import 'package:flutter_application_1/reports/report_document.dart';
import 'package:flutter_application_1/reports/report_scope.dart';
import 'package:flutter_application_1/reports/report_visual.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/documents.dart';

TenantReportDocument _withVisual(TenantReportVisual visual) =>
    TenantReportDocument(
      kind: TenantReportKind.staff,
      identity: fixtureIdentity(),
      scope: TenantReportScope(
        period: fixturePeriod(),
        documentsRead: 1,
      ),
      subtitle: 'x',
      headline: const <TenantReportFigure>[],
      sections: <TenantReportSection>[
        TenantReportSection(heading: 'Only one', summary: 'x', visual: visual),
      ],
    );

TenantReportDatum _d(String label, double value, {double? was}) =>
    TenantReportDatum(
      label: label,
      value: value,
      formatted: value.toStringAsFixed(2),
      comparison: was,
      comparisonFormatted: was?.toStringAsFixed(2),
    );

void main() {
  for (final kind in TenantReportVisualKind.values) {
    group('a ${kind.name} chart', () {
      test('draws with a single category', () async {
        final document = _withVisual(
          TenantReportVisual(
            kind: kind,
            caption: 'One',
            valueAxisLabel: 'Takings',
            comparisonLabel: 'The middle',
            data: <TenantReportDatum>[_d('Grace', 820, was: 820)],
          ),
        );

        await expectLater(
          TenantPdfReportRenderer.standard().render(document),
          completes,
          reason:
              'A one-person shop is the commonest business this app serves. '
              'An axis of one point must still have a span to divide by.',
        );
      });

      test('draws when every value is zero', () async {
        final document = _withVisual(
          TenantReportVisual(
            kind: kind,
            caption: 'Nothing',
            valueAxisLabel: 'Takings',
            comparisonLabel: 'The middle',
            data: <TenantReportDatum>[
              _d('Grace', 0, was: 0),
              _d('Peter', 0, was: 0),
            ],
          ),
        );

        await expectLater(
          TenantPdfReportRenderer.standard().render(document),
          completes,
          reason: 'A quiet period is a real answer, not a crash.',
        );
      });

      test('draws when every value is identical', () async {
        final document = _withVisual(
          TenantReportVisual(
            kind: kind,
            caption: 'Level',
            valueAxisLabel: 'Takings',
            comparisonLabel: 'The middle',
            data: <TenantReportDatum>[
              _d('Grace', 500, was: 500),
              _d('Peter', 500, was: 500),
            ],
          ),
        );

        await expectLater(
          TenantPdfReportRenderer.standard().render(document),
          completes,
          reason: 'A flat axis still has to be drawable.',
        );
      });
    });
  }
}
