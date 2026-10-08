/// The inventory report: what it reads, and what it says about it.
///
/// **The only report with no period, and the only one that says so.** The
/// catalog keeps no history, so there is nothing to range over and no earlier
/// state to compare against. The picker shows no date control for it and the
/// document is stamped with the instant it was taken - see
/// [TenantReportScope.snapshot], which carries the sentence.
///
/// **The section that justifies it is *Where the money is sitting*.** A shop's
/// stock is usually its largest asset and the inventory screen shows it one
/// product at a time. A snapshot can say that three quarters of it is in
/// eleven lines, which is the difference between a list and a report.
library;

import '../../tenancy/tenant_catalog.dart';
import '../report_document.dart';
import '../report_identity.dart';
import '../report_scope.dart';
import '../report_table.dart';
import '../report_visual.dart';
import 'inventory_analysis.dart';
import 'report_prose.dart';

/// Reads the catalog a report covers.
final class TenantInventoryReportSource {
  const TenantInventoryReportSource({
    required this.repository,
    this.pageSize = 50,
    this.maximumPages = 40,
  });

  final TenantCatalogRepository repository;

  final int pageSize;

  /// **A bound, and the report prints it when it is reached.** At 50 a page
  /// this is 2,000 products, which is a large catalog for the shops this app
  /// serves and still finite.
  final int maximumPages;

  /// Every product in the catalog, retired ones included.
  ///
  /// **Retired products are read rather than filtered out**, because a retired
  /// line the business still holds stock of is precisely what this report has
  /// to be able to say - and it is what the screen hides.
  Future<({List<TenantProduct> products, bool truncated})> gather() async {
    final products = <TenantProduct>[];
    String? cursor;

    for (var page = 0; page < maximumPages; page++) {
      final read = await repository.loadProducts(
        pageSize: pageSize,
        cursor: cursor,
      );
      products.addAll(read.items);
      cursor = read.nextCursor;
      if (!read.hasMore || cursor == null) {
        return (products: products, truncated: false);
      }
    }
    return (products: products, truncated: true);
  }

  /// The category names, so a heading reads as a name rather than an ID.
  ///
  /// **Failure here costs a label and nothing else.** A category that could not
  /// be read falls back to its ID, which still groups correctly; refusing the
  /// whole report over a missing name would be a poor trade.
  Future<Map<String, String>> categoryNames() async {
    try {
      final read = await repository.loadEveryCategory();
      return <String, String>{
        for (final category in read.items) category.id: category.name,
      };
    } on Object {
      return const <String, String>{};
    }
  }
}

/// Turns the analysis into the document both renderers draw.
TenantReportDocument describeInventoryReport({
  required TenantInventoryAnalysis analysis,
  required TenantReportIdentity identity,
}) {
  final money = identity.money;

  return TenantReportDocument(
    kind: TenantReportKind.inventory,
    identity: identity,
    scope: _scope(analysis),
    subtitle:
        'What the catalog holds as at the moment it was read, what it is '
        'worth, and what cannot be valued.',
    headline: <TenantReportFigure>[
      TenantReportFigure(
        label: 'Stock at cost',
        value: money(analysis.costMinor),
        amount: analysis.costMinor / 100,
        note: analysis.isFullyCosted
            ? 'Across ${analysis.heldProducts} products on the shelf.'
            : 'Over the ${analysis.heldProducts - analysis.uncostedProducts} '
                  'of ${analysis.heldProducts} held products that record a '
                  'cost.',
      ),
      TenantReportFigure(
        label: 'At today\'s prices',
        value: money(analysis.retailMinor),
        amount: analysis.retailMinor / 100,
        note: 'What it would take if every unit sold at the price now on it.',
      ),
      TenantReportFigure(
        label: 'Units held',
        value: analysis.units.toString(),
        amount: analysis.units,
        amountKind: TenantReportColumnKind.count,
        note: analysis.emptyProducts == 0
            ? 'Every product has something on the shelf.'
            : '${reportCount(analysis.emptyProducts, 'product')} '
                  '${reportVerb(analysis.emptyProducts, 'has', 'have')} '
                  'nothing on the shelf.',
      ),
    ],
    sections: <TenantReportSection>[
      if (analysis.largest.isNotEmpty) _whereTheMoneyIs(analysis, identity),
      if (analysis.headings.isNotEmpty) _byCategory(analysis, identity),
      _needsLookingAt(analysis, identity),
    ],
  );
}

TenantReportScope _scope(TenantInventoryAnalysis analysis) {
  return TenantReportScope.snapshot(
    at: analysis.takenAt,
    documentsRead: analysis.productCount,
    caveats: <TenantReportCaveat>[
      if (analysis.truncated)
        TenantReportCaveat(
          kind: TenantReportCaveatKind.truncated,
          sentence:
              'The read stopped at ${analysis.productCount} products before '
              'reaching the end of the catalog, so every total here is a '
              'floor rather than a sum.',
        ),
      // **Not `TenantReportCaveat.missingCost`**, which is written for sale
      // lines and talks about the profit figures below it. This report prints
      // no profit at all; what a missing cost costs it is a valuation.
      if (!analysis.isFullyCosted)
        TenantReportCaveat(
          kind: TenantReportCaveatKind.missingCost,
          sentence:
              'The stock is valued over '
              '${analysis.heldProducts - analysis.uncostedProducts} of '
              '${analysis.heldProducts} held products. The other '
              '${reportCount(analysis.uncostedProducts, 'product')} '
              '${reportVerb(analysis.uncostedProducts, 'records', 'record')} '
              'no cost, so ${reportCount(analysis.uncostedUnits, 'unit')} '
              '${reportVerb(analysis.uncostedUnits, 'is', 'are')} counted on '
              'the shelf and valued nowhere. Every figure at cost below is a '
              'floor rather than a sum.',
        ),
      if (analysis.negativeProducts > 0)
        TenantReportCaveat(
          kind: TenantReportCaveatKind.noEvidence,
          sentence:
              '${reportCount(analysis.negativeProducts, 'product')} '
              '${reportVerb(analysis.negativeProducts, 'holds', 'hold')} a '
              'quantity below nought, which cannot be true of a shelf. '
              '${reportVerb(analysis.negativeProducts, 'It is', 'They are')} '
              'counted here and valued nowhere: a holding that is worth less '
              'than nothing is not a holding, it is a book that has gone '
              'wrong.',
        ),
    ],
  );
}

/// The section the report exists for.
TenantReportSection _whereTheMoneyIs(
  TenantInventoryAnalysis analysis,
  TenantReportIdentity identity,
) {
  final money = identity.money;
  final few = analysis.productsFor(0.75);
  final topTen = analysis.shareOfTopProducts(10);

  final summary = StringBuffer();
  if (analysis.costMinor == 0) {
    summary.write(
      'No held product records a cost, so the stock cannot be valued. What '
      'is on the shelf is listed below by what it would sell for.',
    );
  } else {
    summary.write(
      '${tenantProductLabel(analysis.largest.first.name, analysis.largest.first.sku)} '
      'holds the most value, at '
      '${money(analysis.largest.first.costMinor ?? analysis.largest.first.retailMinor)}.',
    );
    if (few != null) {
      summary.write(
        ' $few of the ${analysis.heldProducts} products on the shelf '
        '${reportVerb(few, 'carries', 'carry')} three quarters of what the '
        'stock is worth.',
      );
    }
    if (topTen != null && analysis.largest.length > 10) {
      summary.write(
        ' The top ten alone are ${reportPercent(topTen)} of it, so a '
        'stocktake of those ten checks most of the money.',
      );
    }
  }

  final listed = analysis.largest
      .take(TenantInventoryAnalysis.listed)
      .toList();

  return TenantReportSection(
    heading: 'Where the money is sitting',
    summary: summary.toString(),
    visual: TenantReportVisual(
      kind: TenantReportVisualKind.ranked,
      caption: 'Stock value by product',
      valueAxisLabel: 'At cost',
      data: <TenantReportDatum>[
        for (final line in listed.take(8))
          TenantReportDatum(
            label: tenantProductLabel(line.name, line.sku),
            value: (line.costMinor ?? line.retailMinor) / 100,
            formatted: money(line.costMinor ?? line.retailMinor),
          ),
      ],
    ),
    table: TenantReportTable(
      columns: const <TenantReportColumn>[
        TenantReportColumn(heading: 'Product', kind: TenantReportColumnKind.text),
        TenantReportColumn(heading: 'Size', kind: TenantReportColumnKind.text),
        TenantReportColumn(heading: 'Units', kind: TenantReportColumnKind.count),
        TenantReportColumn(heading: 'At cost', kind: TenantReportColumnKind.money),
        TenantReportColumn(heading: 'At price', kind: TenantReportColumnKind.money),
      ],
      rows: <List<TenantReportCell>>[
        for (final line in listed)
          <TenantReportCell>[
            TenantReportTextCell(
              line.retired ? '${line.name} (retired)' : line.name,
            ),
            TenantReportTextCell(line.sku),
            TenantReportCountCell(line.quantity),
            if (line.costMinor case final cost?)
              TenantReportMoneyCell(minor: cost, formatted: money(cost))
            else
              const TenantReportAbsentCell('no cost recorded'),
            TenantReportMoneyCell(
              minor: line.retailMinor,
              formatted: money(line.retailMinor),
            ),
          ],
      ],
    ),
    notes: <String>[
      if (listed.length < analysis.largest.length)
        '${reportCount(analysis.largest.length - listed.length, 'product')} '
            'below these '
            '${reportVerb(analysis.largest.length - listed.length, 'is', 'are')} '
            'in the workbook.',
    ],
  );
}

TenantReportSection _byCategory(
  TenantInventoryAnalysis analysis,
  TenantReportIdentity identity,
) {
  final money = identity.money;
  final top = analysis.headings.first;
  final summary = StringBuffer(
    analysis.headings.length == 1
        ? 'Everything is filed under one heading.'
        : '${top.name} holds the most at ${money(top.costMinor)}, across '
              '${analysis.headings.length} headings.',
  );
  final uncosted = analysis.headings
      .where((heading) => heading.uncostedProducts > 0)
      .toList();
  if (uncosted.isNotEmpty) {
    summary.write(
      ' ${reportList(uncosted.map((heading) => heading.name))} '
      '${uncosted.length == 1 ? 'holds a product' : 'hold products'} with no '
      'cost recorded, so '
      '${uncosted.length == 1 ? 'that heading is' : 'those headings are'} '
      'understated.',
    );
  }

  return TenantReportSection(
    heading: 'By category',
    summary: summary.toString(),
    visual: TenantReportVisual(
      kind: TenantReportVisualKind.composition,
      caption: 'Stock value by heading',
      valueAxisLabel: 'At cost',
      data: <TenantReportDatum>[
        for (final heading in analysis.headings.take(8))
          TenantReportDatum(
            label: heading.name,
            value: heading.costMinor / 100,
            formatted: money(heading.costMinor),
          ),
      ],
    ),
    table: TenantReportTable(
      columns: const <TenantReportColumn>[
        TenantReportColumn(heading: 'Heading', kind: TenantReportColumnKind.text),
        TenantReportColumn(heading: 'Products', kind: TenantReportColumnKind.count),
        TenantReportColumn(heading: 'Units', kind: TenantReportColumnKind.count),
        TenantReportColumn(heading: 'At cost', kind: TenantReportColumnKind.money),
      ],
      rows: <List<TenantReportCell>>[
        for (final heading
            in analysis.headings.take(TenantInventoryAnalysis.listed))
          <TenantReportCell>[
            TenantReportTextCell(heading.name),
            TenantReportCountCell(heading.products),
            TenantReportCountCell(heading.units),
            TenantReportMoneyCell(
              minor: heading.costMinor,
              formatted: money(heading.costMinor),
            ),
          ],
      ],
    ),
  );
}

/// The actionable section: the four states that are worth chasing.
TenantReportSection _needsLookingAt(
  TenantInventoryAnalysis analysis,
  TenantReportIdentity identity,
) {
  final money = identity.money;
  final summary = StringBuffer();
  final flags = <String>[];
  if (analysis.negativeProducts > 0) {
    flags.add(
      '${reportCount(analysis.negativeProducts, 'product')} '
      '${reportVerb(analysis.negativeProducts, 'holds', 'hold')} less than '
      'nothing, which is a correction that never caught up with a sale',
    );
  }
  if (analysis.retiredHeldProducts > 0) {
    flags.add(
      '${reportCount(analysis.retiredHeldProducts, 'retired product')} still '
      '${reportVerb(analysis.retiredHeldProducts, 'has', 'have')} stock on the '
      'shelf, worth ${money(analysis.retiredHeldCostMinor)}',
    );
  }
  if (analysis.uncostedProducts > 0) {
    flags.add(
      '${reportCount(analysis.uncostedProducts, 'held product')} '
      '${reportVerb(analysis.uncostedProducts, 'records', 'record')} no cost, '
      'so ${reportCount(analysis.uncostedUnits, 'unit')} '
      '${reportVerb(analysis.uncostedUnits, 'is', 'are')} in the count above '
      'and in no valuation',
    );
  }
  if (flags.isEmpty) {
    summary.write(
      'Nothing in the catalog is in a state worth chasing: every held product '
      'records a cost, none holds less than nothing, and no retired line is '
      'still carrying stock.',
    );
  } else {
    summary.write('${reportList(flags)}.');
  }

  return TenantReportSection(
    heading: 'Worth looking at',
    summary: summary.toString(),
    table: TenantReportTable(
      columns: const <TenantReportColumn>[
        TenantReportColumn(heading: 'State', kind: TenantReportColumnKind.text),
        TenantReportColumn(heading: 'Products', kind: TenantReportColumnKind.count),
        TenantReportColumn(heading: 'Units', kind: TenantReportColumnKind.count),
      ],
      rows: <List<TenantReportCell>>[
        <TenantReportCell>[
          const TenantReportTextCell('Below nought'),
          TenantReportCountCell(analysis.negativeProducts),
          TenantReportCountCell(analysis.negativeUnits),
        ],
        <TenantReportCell>[
          const TenantReportTextCell('Retired, still held'),
          TenantReportCountCell(analysis.retiredHeldProducts),
          TenantReportCountCell(analysis.retiredHeldUnits),
        ],
        <TenantReportCell>[
          const TenantReportTextCell('Held with no cost recorded'),
          TenantReportCountCell(analysis.uncostedProducts),
          TenantReportCountCell(analysis.uncostedUnits),
        ],
        <TenantReportCell>[
          const TenantReportTextCell('Nothing on the shelf'),
          TenantReportCountCell(analysis.emptyProducts),
          const TenantReportCountCell(0),
        ],
      ],
      emphasisRow: analysis.negativeProducts > 0 ? 0 : null,
    ),
  );
}
