/// What the catalog is worth as it stands, and what cannot be said about it.
///
/// **This is the one report with no period, and that is a fact about the
/// records rather than a gap.** `products` carries no history: a product
/// document holds the quantity it holds now and nothing about the quantity it
/// held last Tuesday. So there is nothing to range over, no trend to draw and
/// no earlier window to compare against, and the document says as much on its
/// first page instead of implying a period it never read.
///
/// **The finding is where the money is sitting.** A shop's stock is its largest
/// asset and the inventory screen shows it one product at a time. A snapshot
/// can say that three quarters of it is in eleven lines, that a tenth of it is
/// in products nobody has sold, and that some of it cannot be valued at all.
///
/// **A product with no cost is not worth nothing.** Cost is optional on every
/// product created before the field existed - see [TenantProduct.cost] - so a
/// valuation over the catalog is always a valuation over the part of it that
/// records a cost. The count of the rest is carried beside the figure.
///
/// **Retired products count.** A retired line still on the shelf is stock the
/// business owns and cannot sell, which is worth knowing precisely because the
/// screen filters it away.
///
/// Pure arithmetic, no I/O, no Flutter.
library;

import '../../reporting/profit_report.dart';
import '../../tenancy/tenant_catalog.dart';

/// One category's holding.
final class TenantInventoryHeading {
  const TenantInventoryHeading({
    required this.categoryId,
    required this.name,
    required this.products,
    required this.units,
    required this.costMinor,
    required this.retailMinor,
    required this.uncostedProducts,
  });

  /// Every product files itself under exactly one category - `categoryId` is
  /// required on the document and the read model refuses one without it.
  final String categoryId;

  /// The category's name, or a stand-in where it could not be resolved.
  final String name;

  final int products;
  final int units;

  /// What the units cost, over the products that record a cost.
  final int costMinor;

  /// What they would sell for at the price now on the product.
  final int retailMinor;

  /// Products here whose cost was never recorded.
  final int uncostedProducts;
}

/// One product worth naming on its own.
final class TenantInventoryLine {
  const TenantInventoryLine({
    required this.productId,
    required this.name,
    required this.sku,
    required this.quantity,
    required this.costMinor,
    required this.retailMinor,
    required this.retired,
  });

  final String productId;
  final String name;
  final String sku;
  final int quantity;

  /// Null where the product records no cost.
  final int? costMinor;

  final int retailMinor;
  final bool retired;
}

/// The catalog as at the moment it was read.
final class TenantInventoryAnalysis {
  const TenantInventoryAnalysis._({
    required this.takenAt,
    required this.productCount,
    required this.heldProducts,
    required this.units,
    required this.costMinor,
    required this.retailMinor,
    required this.uncostedProducts,
    required this.uncostedUnits,
    required this.negativeProducts,
    required this.negativeUnits,
    required this.emptyProducts,
    required this.retiredHeldProducts,
    required this.retiredHeldUnits,
    required this.retiredHeldCostMinor,
    required this.headings,
    required this.largest,
    required this.truncated,
  });

  /// How many rows a page lists before the rest is left to the workbook.
  static const int listed = 20;

  factory TenantInventoryAnalysis.from({
    required DateTime takenAt,
    required List<TenantProduct> products,
    Map<String, String> categoryNames = const <String, String>{},
    bool truncated = false,
  }) {
    final headings = <String, _Running>{};

    var held = 0;
    var units = 0;
    var cost = 0;
    var retail = 0;
    var uncosted = 0;
    var uncostedUnits = 0;
    var negative = 0;
    var negativeUnits = 0;
    var empty = 0;
    var retiredHeld = 0;
    var retiredHeldUnits = 0;
    var retiredHeldCost = 0;
    final lines = <TenantInventoryLine>[];

    for (final product in products) {
      final costMinor = product.cost == null
          ? null
          : reportingMinorUnits(product.cost!);
      final priceMinor = reportingMinorUnits(product.price);
      final quantity = product.quantity;

      // **A negative quantity is counted and never valued.** It is not a
      // holding that is worth less than nothing; it is a book that has gone
      // wrong, usually a sale against stock a correction never caught up with.
      if (quantity < 0) {
        negative++;
        negativeUnits += -quantity;
      } else if (quantity == 0) {
        empty++;
      } else {
        held++;
        units += quantity;
        retail += priceMinor * quantity;
        if (costMinor == null) {
          uncosted++;
          uncostedUnits += quantity;
        } else {
          cost += costMinor * quantity;
        }
        if (product.retired) {
          retiredHeld++;
          retiredHeldUnits += quantity;
          if (costMinor != null) retiredHeldCost += costMinor * quantity;
        }
      }

      final running = headings[product.categoryId] ?? _Running();
      headings[product.categoryId] = running;
      running.products++;
      if (quantity > 0) {
        running.units += quantity;
        running.retail += priceMinor * quantity;
        if (costMinor == null) {
          running.uncosted++;
        } else {
          running.cost += costMinor * quantity;
        }
      }

      lines.add(
        TenantInventoryLine(
          productId: product.id,
          name: product.name,
          sku: product.sku,
          quantity: quantity,
          costMinor: costMinor == null ? null : costMinor * quantity,
          retailMinor: priceMinor * quantity,
          retired: product.retired,
        ),
      );
    }

    final byCategory =
        <TenantInventoryHeading>[
          for (final entry in headings.entries)
            TenantInventoryHeading(
              categoryId: entry.key,
              // The name where it could be read, and the ID where it could
              // not: a heading still groups correctly under its key, and
              // refusing the whole report over a missing label would be a
              // poor trade.
              name: categoryNames[entry.key] ?? entry.key,
              products: entry.value.products,
              units: entry.value.units,
              costMinor: entry.value.cost,
              retailMinor: entry.value.retail,
              uncostedProducts: entry.value.uncosted,
            ),
        ]..sort((a, b) {
          final byCost = b.costMinor.compareTo(a.costMinor);
          if (byCost != 0) return byCost;
          final byUnits = b.units.compareTo(a.units);
          return byUnits != 0 ? byUnits : a.name.compareTo(b.name);
        });

    // Most valuable first, and a line with no cost sorts by what it would sell
    // for so it is not pushed to the bottom as though it were worthless.
    final ranked = lines.where((line) => line.quantity > 0).toList()
      ..sort((a, b) {
        final left = a.costMinor ?? a.retailMinor;
        final right = b.costMinor ?? b.retailMinor;
        final byValue = right.compareTo(left);
        return byValue != 0 ? byValue : a.name.compareTo(b.name);
      });

    return TenantInventoryAnalysis._(
      takenAt: takenAt,
      productCount: products.length,
      heldProducts: held,
      units: units,
      costMinor: cost,
      retailMinor: retail,
      uncostedProducts: uncosted,
      uncostedUnits: uncostedUnits,
      negativeProducts: negative,
      negativeUnits: negativeUnits,
      emptyProducts: empty,
      retiredHeldProducts: retiredHeld,
      retiredHeldUnits: retiredHeldUnits,
      retiredHeldCostMinor: retiredHeldCost,
      headings: List<TenantInventoryHeading>.unmodifiable(byCategory),
      largest: List<TenantInventoryLine>.unmodifiable(ranked),
      truncated: truncated,
    );
  }

  /// The instant the catalog was read. The figures are true of it and of no
  /// other.
  final DateTime takenAt;

  /// Every product read, whatever its quantity.
  final int productCount;

  /// Products with something on the shelf.
  final int heldProducts;

  final int units;

  /// What the held units cost, over the products that record a cost.
  final int costMinor;

  /// What they would sell for at the price now on each product.
  final int retailMinor;

  /// Held products whose cost was never recorded, and their units.
  final int uncostedProducts;
  final int uncostedUnits;

  /// Products whose quantity is below nought, which cannot be true of a shelf.
  final int negativeProducts;
  final int negativeUnits;

  /// Products with nothing on the shelf.
  final int emptyProducts;

  /// Retired products the business is still holding stock of.
  final int retiredHeldProducts;
  final int retiredHeldUnits;
  final int retiredHeldCostMinor;

  final List<TenantInventoryHeading> headings;

  /// Held products, most valuable first.
  final List<TenantInventoryLine> largest;

  final bool truncated;

  /// Whether every held product could be valued.
  bool get isFullyCosted => uncostedProducts == 0;

  /// What the stock would make if it all sold at today's price.
  ///
  /// Null where any held product records no cost, because a margin over a
  /// partial cost is not a margin.
  int? get marginMinor {
    if (!isFullyCosted) return null;
    return retailMinor - costMinor;
  }

  /// The share of the valuation sitting in the most valuable products.
  ///
  /// Null where nothing is valued at all.
  double? shareOfTopProducts(int count) {
    if (costMinor == 0 || largest.isEmpty) return null;
    final top = largest
        .take(count)
        .fold<int>(0, (sum, line) => sum + (line.costMinor ?? 0));
    return top / costMinor;
  }

  /// How many products carry [share] of the valuation, or null where none do.
  int? productsFor(double share) {
    if (costMinor == 0) return null;
    var running = 0;
    for (var i = 0; i < largest.length; i++) {
      running += largest[i].costMinor ?? 0;
      if (running / costMinor >= share) return i + 1;
    }
    return null;
  }
}

/// Mutable running totals, so the loop above stays one pass.
final class _Running {
  int products = 0;
  int units = 0;
  int cost = 0;
  int retail = 0;
  int uncosted = 0;
}
