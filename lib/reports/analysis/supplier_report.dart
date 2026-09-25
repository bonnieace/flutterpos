/// The supplier report: what each supplier delivered over a period, what it
/// cost, and how unit costs moved.
///
/// **Value received, never an amount owed.** This app records deliveries and
/// their unit costs; it records no invoices and no payments. Every total here
/// is what the deliveries' own lines add up to, and the report says so.
library;

import '../../checkout/checkout_draft.dart';
import '../../suppliers/supplier_delivery.dart';
import '../../tenancy/tenant_repository.dart';
import '../report_document.dart';
import '../report_identity.dart';
import '../report_period.dart';
import '../report_scope.dart';
import '../report_table.dart';
import '../report_visual.dart';
import 'report_prose.dart';
import 'supplier_analysis.dart';

/// Reads the deliveries a supplier report covers.
final class TenantSupplierReportSource {
  const TenantSupplierReportSource({
    required this.repository,
    this.pageSize = 50,
    this.maximumPages = 12,
  });

  final TenantSupplierDeliveryRepository repository;
  final int pageSize;

  /// **A bound, and the report prints the day it reached when it is hit.** At
  /// fifty a page this is six hundred deliveries in a period.
  final int maximumPages;

  /// Every delivery recorded in [period], narrowed to [supplierId] when one is
  /// named, and - for a report over every supplier - how many restocks arrived
  /// with no supplier at all.
  Future<
    ({
      List<TenantSupplierDelivery> deliveries,
      bool truncated,
      String? reachedTo,
      int read,
      int? restocks,
      bool restocksTruncated,
    })
  >
  gather(TenantReportPeriod period, {String? supplierId}) async {
    final startAt = _startOf(period);
    final endAt = _endOf(period);
    final deliveries = <TenantSupplierDelivery>[];
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
      for (final delivery in chunk.items) {
        if (supplierId == null || delivery.supplierId == supplierId) {
          deliveries.add(delivery);
        }
        if (delivery.createdAt case final at?) {
          reachedTo = checkoutBusinessDate(at.toUtc());
        }
      }
      position = chunk.next;
      if (position == null) break;
    }
    int? restocks;
    var restocksTruncated = false;
    if (supplierId == null) {
      try {
        final count = await repository.countRestocksWithoutSupplier(
          startAt: startAt,
          endAt: endAt,
        );
        restocks = count.count;
        restocksTruncated = count.truncated;
      } on Object {
        // A figure that could not be read is left out rather than stated as
        // nought; the rest of the report stands without it.
        restocks = null;
      }
    }
    return (
      deliveries: deliveries,
      truncated: truncated,
      reachedTo: truncated ? reachedTo : null,
      read: read,
      restocks: restocks,
      restocksTruncated: restocksTruncated,
    );
  }

  static DateTime _startOf(TenantReportPeriod period) =>
      DateTime.parse('${period.startDate}T00:00:00Z').subtract(
        checkoutBusinessDayOffset,
      );

  static DateTime _endOf(TenantReportPeriod period) =>
      DateTime.parse('${period.endDate}T23:59:59.999Z').subtract(
        checkoutBusinessDayOffset,
      );
}

/// Turns the analysis into the document both renderers draw.
TenantReportDocument describeSupplierReport({
  required TenantSupplierAnalysis analysis,
  required TenantReportIdentity identity,
}) {
  final money = identity.money;
  final subject = analysis.subject;
  final restocks = analysis.restocksWithoutSupplier;
  return TenantReportDocument(
    kind: TenantReportKind.suppliers,
    title: subject == null
        ? TenantReportKind.suppliers.title
        : '${TenantReportKind.suppliers.title} · ${subject.label}',
    subjectSlug: subject?.slug,
    identity: identity,
    scope: _scope(analysis),
    subtitle:
        'What ${subject == null ? 'each supplier' : subject.label} delivered '
        'over the period, and what it cost. Value received, not an amount '
        'owed.',
    headline: <TenantReportFigure>[
      TenantReportFigure(
        label: 'Deliveries',
        value: '${analysis.deliveryCount}',
        amount: analysis.deliveryCount,
        amountKind: TenantReportColumnKind.count,
      ),
      TenantReportFigure(
        label: 'Units received',
        value: '${analysis.unitCount}',
        amount: analysis.unitCount,
        amountKind: TenantReportColumnKind.count,
      ),
      TenantReportFigure(
        label: 'Value received',
        value: money(analysis.valueMinor),
        amount: analysis.valueMinor / 100,
        note: analysis.costlessLineCount == 0
            ? null
            : '${reportCount(analysis.costlessLineCount, 'line')} named no unit '
                  'cost and ${reportVerb(analysis.costlessLineCount, 'is', 'are')} '
                  'not in this figure.',
      ),
      if (restocks != null)
        TenantReportFigure(
          label: 'Restocks with no supplier',
          value: '$restocks${analysis.restocksTruncated ? '+' : ''}',
          amount: restocks,
          amountKind: TenantReportColumnKind.count,
          note: 'Stock added through Adjust stock, with no delivery recorded '
              'behind it.',
        ),
    ],
    sections: <TenantReportSection>[
      if (subject == null && analysis.totals.isNotEmpty)
        _bySupplier(analysis, identity),
      if (analysis.costChanges.isNotEmpty) _costChanges(analysis, identity),
      if (analysis.rows.isNotEmpty) _deliveries(analysis, identity),
    ],
  );
}

TenantReportScope _scope(TenantSupplierAnalysis analysis) {
  final reached = analysis.reachedTo;
  return TenantReportScope(
    period: analysis.period,
    documentsRead: analysis.recordsRead,
    // **The day the read reached, not the day asked for**, so a capped read
    // says it is short rather than claiming the whole period.
    coveredTo: analysis.truncated && reached != null ? reached : null,
    caveats: <TenantReportCaveat>[
      if (analysis.truncated)
        TenantReportCaveat.truncated(
          asked: analysis.period,
          reachedFrom: analysis.period.startDate,
          reachedTo: reached ?? analysis.period.startDate,
          records: analysis.recordsRead,
        ),
      if (analysis.costlessLineCount > 0)
        TenantReportCaveat(
          kind: TenantReportCaveatKind.missingCost,
          sentence:
              '${analysis.costlessLineCount} of ${analysis.lineCount} '
              'delivery lines named no unit cost, so value received is a '
              'floor: it counts only the lines that stated what they cost.',
        ),
      if (analysis.restocksTruncated)
        const TenantReportCaveat(
          kind: TenantReportCaveatKind.truncated,
          sentence:
              'The count of restocks with no supplier stopped at its bound, so '
              'it is at least the figure shown.',
        ),
    ],
  );
}

TenantReportSection _bySupplier(
  TenantSupplierAnalysis analysis,
  TenantReportIdentity identity,
) {
  final top = analysis.totals.first;
  final total = analysis.valueMinor;
  final summary = StringBuffer(
    '${reportCount(analysis.totals.length, 'supplier')} delivered in this '
    'period.',
  );
  if (total > 0) {
    summary.write(
      ' ${top.supplierName} is the largest by value received, at '
      '${reportPercent(top.valueMinor / total)} of it.',
    );
  }
  return TenantReportSection(
    heading: 'By supplier',
    summary: summary.toString(),
    visual: total == 0
        ? null
        : TenantReportVisual(
            kind: TenantReportVisualKind.ranked,
            caption: 'Value received from each supplier',
            valueAxisLabel: 'Value received',
            data: <TenantReportDatum>[
              for (final row in analysis.totals)
                TenantReportDatum(
                  label: row.supplierName,
                  value: row.valueMinor / 100,
                  formatted: identity.money(row.valueMinor),
                ),
            ],
          ),
    table: TenantReportTable(
      columns: const <TenantReportColumn>[
        TenantReportColumn(heading: 'Supplier', kind: TenantReportColumnKind.text),
        TenantReportColumn(heading: 'Deliveries', kind: TenantReportColumnKind.count),
        TenantReportColumn(heading: 'Units', kind: TenantReportColumnKind.count),
        TenantReportColumn(
          heading: 'Value received',
          kind: TenantReportColumnKind.money,
        ),
        TenantReportColumn(heading: 'Products', kind: TenantReportColumnKind.text),
      ],
      rows: <List<TenantReportCell>>[
        for (final row in analysis.totals)
          <TenantReportCell>[
            TenantReportTextCell(row.supplierName),
            TenantReportCountCell(row.deliveries),
            TenantReportCountCell(row.units),
            TenantReportMoneyCell(
              minor: row.valueMinor,
              formatted: identity.money(row.valueMinor),
            ),
            TenantReportTextCell(reportList(row.products.toList()..sort())),
          ],
      ],
    ),
    notes: const <String>[
      'Value received is what the delivered lines\' unit costs add up to. It is '
          'not an amount owed: this app records no invoices or payments.',
    ],
  );
}

TenantReportSection _costChanges(
  TenantSupplierAnalysis analysis,
  TenantReportIdentity identity,
) {
  final biggest = analysis.costChanges.first;
  return TenantReportSection(
    heading: 'What unit costs did',
    summary:
        '${reportCount(analysis.costChanges.length, 'product')} changed unit '
        'cost across the deliveries of this period. The largest move was '
        '${biggest.productName}, ${reportDirection(biggest.change)}: from '
        '${identity.money(biggest.firstMinor)} to '
        '${identity.money(biggest.latestMinor)}.',
    table: TenantReportTable(
      columns: const <TenantReportColumn>[
        TenantReportColumn(heading: 'Product', kind: TenantReportColumnKind.text),
        TenantReportColumn(heading: 'Supplier', kind: TenantReportColumnKind.text),
        TenantReportColumn(heading: 'First cost', kind: TenantReportColumnKind.money),
        TenantReportColumn(heading: 'Latest cost', kind: TenantReportColumnKind.money),
        TenantReportColumn(heading: 'Change', kind: TenantReportColumnKind.percent),
      ],
      rows: <List<TenantReportCell>>[
        for (final change in analysis.costChanges)
          <TenantReportCell>[
            TenantReportTextCell(change.productName),
            TenantReportTextCell(change.supplierName),
            TenantReportMoneyCell(
              minor: change.firstMinor,
              formatted: identity.money(change.firstMinor),
            ),
            TenantReportMoneyCell(
              minor: change.latestMinor,
              formatted: identity.money(change.latestMinor),
            ),
            TenantReportPercentCell(change.change),
          ],
      ],
    ),
    notes: const <String>[
      'The latest unit cost is the one each product now carries: every sale '
          'after that delivery was costed at it, and every sale before keeps '
          'the cost it was sold at.',
    ],
  );
}

TenantReportSection _deliveries(
  TenantSupplierAnalysis analysis,
  TenantReportIdentity identity,
) => TenantReportSection(
  heading: 'Every delivery',
  summary:
      '${reportCount(analysis.deliveryCount, 'delivery', plural: 'deliveries')}, '
      'newest first.',
  table: TenantReportTable(
    columns: const <TenantReportColumn>[
      TenantReportColumn(heading: 'Date', kind: TenantReportColumnKind.date),
      TenantReportColumn(heading: 'Supplier', kind: TenantReportColumnKind.text),
      TenantReportColumn(heading: 'Reference', kind: TenantReportColumnKind.text),
      TenantReportColumn(heading: 'Products', kind: TenantReportColumnKind.count),
      TenantReportColumn(heading: 'Units', kind: TenantReportColumnKind.count),
      TenantReportColumn(
        heading: 'Value received',
        kind: TenantReportColumnKind.money,
      ),
    ],
    rows: <List<TenantReportCell>>[
      for (final row in analysis.rows)
        <TenantReportCell>[
          TenantReportDateCell(row.businessDate),
          TenantReportTextCell(
            row.delivery.supplierName ?? row.delivery.supplierId,
          ),
          if (row.delivery.reference case final reference?)
            TenantReportTextCell(reference)
          else
            const TenantReportAbsentCell('no reference was entered'),
          TenantReportCountCell(row.delivery.lines.length),
          TenantReportCountCell(row.delivery.unitCount),
          if (row.delivery.costlessLineCount == row.delivery.lines.length)
            const TenantReportAbsentCell('no line named a unit cost')
          else
            TenantReportMoneyCell(
              minor: row.delivery.valueMinor,
              formatted: identity.money(row.delivery.valueMinor),
            ),
        ],
    ],
  ),
);
