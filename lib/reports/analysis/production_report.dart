/// The production report: what was made over a period, what it cost to make,
/// and how the cost of one unit moved.
library;

import '../../checkout/checkout_draft.dart';
import '../../production/production_batch.dart';
import '../../tenancy/tenant_repository.dart';
import '../report_document.dart';
import '../report_identity.dart';
import '../report_period.dart';
import '../report_scope.dart';
import '../report_table.dart';
import '../report_visual.dart';
import 'production_analysis.dart';
import 'report_prose.dart';

/// Reads the batches a production report covers.
final class TenantProductionReportSource {
  const TenantProductionReportSource({
    required this.repository,
    this.pageSize = 50,
    this.maximumPages = 12,
  });

  final TenantProductionRepository repository;
  final int pageSize;

  /// A bound, and the report prints the day it reached when it is hit.
  final int maximumPages;

  /// Every batch recorded in [period], narrowed to [productId] when one is
  /// named.
  Future<
    ({
      List<TenantProductionBatch> batches,
      bool truncated,
      String? reachedTo,
      int read,
    })
  >
  gather(TenantReportPeriod period, {String? productId}) async {
    final startAt = DateTime.parse('${period.startDate}T00:00:00Z').subtract(
      checkoutBusinessDayOffset,
    );
    final endAt = DateTime.parse('${period.endDate}T23:59:59.999Z').subtract(
      checkoutBusinessDayOffset,
    );
    final batches = <TenantProductionBatch>[];
    TenantInstantRangePosition? position;
    var truncated = false;
    var read = 0;
    String? reachedTo;
    for (var page = 0; ; page++) {
      if (page >= maximumPages) {
        truncated = true;
        break;
      }
      final chunk = await repository.loadRange(
        startAt: startAt,
        endAt: endAt,
        pageSize: pageSize,
        startAfter: position,
      );
      read += chunk.items.length;
      for (final batch in chunk.items) {
        if (productId == null || batch.productId == productId) {
          batches.add(batch);
        }
        if (batch.occurredAt case final at?) {
          reachedTo = checkoutBusinessDate(at.toUtc());
        }
      }
      position = chunk.next;
      if (position == null) break;
    }
    return (
      batches: batches,
      truncated: truncated,
      reachedTo: truncated ? reachedTo : null,
      read: read,
    );
  }
}

/// Turns the analysis into the document both renderers draw.
TenantReportDocument describeProductionReport({
  required TenantProductionAnalysis analysis,
  required TenantReportIdentity identity,
}) {
  final money = identity.money;
  final subject = analysis.subject;
  final single = analysis.products.length == 1 ? analysis.products.first : null;
  return TenantReportDocument(
    kind: TenantReportKind.production,
    title: subject == null
        ? TenantReportKind.production.title
        : '${TenantReportKind.production.title} · ${subject.label}',
    subjectSlug: subject?.slug,
    identity: identity,
    scope: _scope(analysis),
    subtitle:
        'What was made${subject == null ? '' : ' of ${subject.label}'} over the '
        'period, what it cost to make, and how the cost of one unit moved.',
    headline: <TenantReportFigure>[
      TenantReportFigure(
        label: 'Batches',
        value: '${analysis.batchCount}',
        amount: analysis.batchCount,
        amountKind: TenantReportColumnKind.count,
      ),
      TenantReportFigure(
        label: 'Units made',
        value: '${analysis.unitCount}',
        amount: analysis.unitCount,
        amountKind: TenantReportColumnKind.count,
      ),
      TenantReportFigure(
        label: 'Spent on production',
        value: money(analysis.spentMinor),
        amount: analysis.spentMinor / 100,
      ),
      if (single?.latestUnitCostMinor case final latest?)
        TenantReportFigure(
          label: 'Latest cost per unit',
          value: money(latest),
          amount: latest / 100,
          note: single!.change == null
              ? null
              : '${reportDirection(single.change!)} on the first batch of '
                    'the period.',
        ),
    ],
    sections: <TenantReportSection>[
      if (analysis.products.isNotEmpty) _byProduct(analysis, identity),
      if (single != null && single.batches > 1) _trend(analysis, identity),
      if (analysis.rows.isNotEmpty) _batches(analysis, identity),
    ],
  );
}

TenantReportScope _scope(TenantProductionAnalysis analysis) {
  final reached = analysis.reachedTo;
  return TenantReportScope(
    period: analysis.period,
    documentsRead: analysis.recordsRead,
    coveredTo: analysis.truncated && reached != null ? reached : null,
    caveats: <TenantReportCaveat>[
      if (analysis.truncated)
        TenantReportCaveat.truncated(
          asked: analysis.period,
          reachedFrom: analysis.period.startDate,
          reachedTo: reached ?? analysis.period.startDate,
          records: analysis.recordsRead,
        ),
    ],
  );
}

TenantReportSection _byProduct(
  TenantProductionAnalysis analysis,
  TenantReportIdentity identity,
) {
  final moved = analysis.moved;
  final summary = StringBuffer(
    '${reportCount(analysis.products.length, 'product')} '
    '${reportVerb(analysis.products.length, 'was', 'were')} made in this '
    'period, in ${reportCount(analysis.batchCount, 'batch', plural: 'batches')}.',
  );
  if (moved.isNotEmpty) {
    final most = moved.first;
    summary.write(
      ' The cost of one ${most.productName} moved most, '
      '${reportDirection(most.change!)} from '
      '${identity.money(most.firstUnitCostMinor!)} to '
      '${identity.money(most.latestUnitCostMinor!)}.',
    );
  }
  return TenantReportSection(
    heading: 'By product',
    summary: summary.toString(),
    visual: analysis.spentMinor == 0 || analysis.products.length < 2
        ? null
        : TenantReportVisual(
            kind: TenantReportVisualKind.ranked,
            caption: 'What each product cost to make over the period',
            valueAxisLabel: 'Spent',
            data: <TenantReportDatum>[
              for (final product in analysis.products)
                TenantReportDatum(
                  label: product.productName,
                  value: product.spentMinor / 100,
                  formatted: identity.money(product.spentMinor),
                ),
            ],
          ),
    table: TenantReportTable(
      columns: const <TenantReportColumn>[
        TenantReportColumn(heading: 'Product', kind: TenantReportColumnKind.text),
        TenantReportColumn(heading: 'Batches', kind: TenantReportColumnKind.count),
        TenantReportColumn(heading: 'Units made', kind: TenantReportColumnKind.count),
        TenantReportColumn(heading: 'Spent', kind: TenantReportColumnKind.money),
        TenantReportColumn(
          heading: 'First cost per unit',
          kind: TenantReportColumnKind.money,
        ),
        TenantReportColumn(
          heading: 'Latest cost per unit',
          kind: TenantReportColumnKind.money,
        ),
      ],
      rows: <List<TenantReportCell>>[
        for (final product in analysis.products)
          <TenantReportCell>[
            TenantReportTextCell(product.productName),
            TenantReportCountCell(product.batches),
            TenantReportCountCell(product.units),
            TenantReportMoneyCell(
              minor: product.spentMinor,
              formatted: identity.money(product.spentMinor),
            ),
            TenantReportMoneyCell(
              minor: product.firstUnitCostMinor ?? 0,
              formatted: identity.money(product.firstUnitCostMinor ?? 0),
            ),
            TenantReportMoneyCell(
              minor: product.latestUnitCostMinor ?? 0,
              formatted: identity.money(product.latestUnitCostMinor ?? 0),
            ),
          ],
      ],
    ),
    notes: const <String>[
      'Production costs are counted in the cost of each unit sold, not in '
          'Expenses. The latest cost per unit is the one each product now '
          'carries; sales before it keep the cost they were sold at.',
    ],
  );
}

TenantReportSection _trend(
  TenantProductionAnalysis analysis,
  TenantReportIdentity identity,
) {
  final product = analysis.products.single;
  return TenantReportSection(
    heading: 'Cost per unit, batch by batch',
    summary:
        'Across ${reportCount(product.batches, 'batch', plural: 'batches')} the '
        'cost of one ${product.productName} went from '
        '${identity.money(product.firstUnitCostMinor!)} to '
        '${identity.money(product.latestUnitCostMinor!)}'
        '${product.change == null ? '' : ', ${reportDirection(product.change!)}'}.',
    visual: TenantReportVisual(
      kind: TenantReportVisualKind.trend,
      caption: 'What one unit cost to make, in the order the batches were made',
      valueAxisLabel: 'Cost per unit',
      data: <TenantReportDatum>[
        for (final row in analysis.rows)
          TenantReportDatum(
            label: reportShortDate(row.businessDate),
            value: row.batch.unitCostMinor / 100,
            formatted: identity.money(row.batch.unitCostMinor),
          ),
      ],
    ),
  );
}

TenantReportSection _batches(
  TenantProductionAnalysis analysis,
  TenantReportIdentity identity,
) => TenantReportSection(
  heading: 'Every batch',
  summary:
      '${reportCount(analysis.batchCount, 'batch', plural: 'batches')}, oldest '
      'first.',
  table: TenantReportTable(
    columns: const <TenantReportColumn>[
      TenantReportColumn(heading: 'Date', kind: TenantReportColumnKind.date),
      TenantReportColumn(heading: 'Batch', kind: TenantReportColumnKind.text),
      TenantReportColumn(heading: 'Product', kind: TenantReportColumnKind.text),
      TenantReportColumn(heading: 'Made', kind: TenantReportColumnKind.count),
      TenantReportColumn(heading: 'Total cost', kind: TenantReportColumnKind.money),
      TenantReportColumn(heading: 'Cost per unit', kind: TenantReportColumnKind.money),
    ],
    rows: <List<TenantReportCell>>[
      for (final row in analysis.rows)
        <TenantReportCell>[
          TenantReportDateCell(row.businessDate),
          TenantReportTextCell(row.batch.batchNumber),
          TenantReportTextCell(row.productLabel),
          TenantReportCountCell(row.batch.quantity),
          TenantReportMoneyCell(
            minor: row.batch.totalCostMinor,
            formatted: identity.money(row.batch.totalCostMinor),
          ),
          TenantReportMoneyCell(
            minor: row.batch.unitCostMinor,
            formatted: identity.money(row.batch.unitCostMinor),
          ),
        ],
    ],
  ),
);
