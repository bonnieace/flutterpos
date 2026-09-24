/// The arithmetic behind the inventory report.
///
/// **Three rules under test, all of them about what not to claim.** A product
/// with no cost is not worth nothing; a quantity below nought is not a holding
/// worth less than nothing; and a margin over a partial cost is not a margin.
/// Each of those would produce a confident figure that is wrong, on a document
/// somebody may hand to an accountant.
library;

import 'package:flutter_application_1/reports/analysis/inventory_analysis.dart';
import 'package:flutter_application_1/tenancy/tenant_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/inventory.dart';

void main() {
  group('what the stock is worth', () {
    test('cost is summed over the products that record one', () {
      final analysis = fixtureInventoryAnalysis();

      // 240x180 + 90x330 + 30x48 + 24x60 = 43200 + 29700 + 1440 + 1440.
      expect(analysis.costMinor, 7578000);
      expect(
        analysis.uncostedProducts,
        1,
        reason: 'Matches records no cost, so its units are in no valuation.',
      );
      expect(analysis.uncostedUnits, 200);
      expect(analysis.isFullyCosted, isFalse);
    });

    test('units count the uncosted product even though the money cannot', () {
      final analysis = fixtureInventoryAnalysis();

      expect(
        analysis.units,
        584,
        reason:
            '240 + 90 + 30 + 200 + 24. Matches is on the shelf whether or not '
            'anybody recorded what it cost.',
      );
      expect(analysis.heldProducts, 5);
    });

    test('a margin over a partial cost is withheld', () {
      final analysis = fixtureInventoryAnalysis();

      expect(
        analysis.marginMinor,
        isNull,
        reason:
            'One held product records no cost, so the retail side and the '
            'cost side are over different sets of goods.',
      );
    });

    test('a fully costed catalog does state a margin', () {
      final analysis = TenantInventoryAnalysis.from(
        takenAt: fixtureInventoryInstant(),
        products: <TenantProduct>[
          productRecord(
            id: 'product-1',
            name: 'Bread',
            sku: 'BRD',
            price: 65,
            cost: 48,
            quantity: 10,
            categoryId: 'dry',
          ),
        ],
      );

      expect(analysis.marginMinor, 17000);
    });
  });

  group('what cannot be valued', () {
    test('a quantity below nought is counted and valued nowhere', () {
      final analysis = fixtureInventoryAnalysis();

      expect(analysis.negativeProducts, 1);
      expect(
        analysis.negativeUnits,
        6,
        reason: 'Reported as a positive count of how far below nought it is.',
      );
      // Sugar at 140 a unit would have taken 840 off the valuation if it had
      // been multiplied through.
      expect(
        analysis.costMinor,
        7578000,
        reason:
            'It is not a holding worth less than nothing; it is a book that '
            'has gone wrong.',
      );
    });

    test('a product with nothing on the shelf is counted apart', () {
      final analysis = fixtureInventoryAnalysis();

      expect(analysis.emptyProducts, 1);
      expect(analysis.productCount, 7);
    });

    test('a retired product still held is reported, not filtered away', () {
      final analysis = fixtureInventoryAnalysis();

      expect(analysis.retiredHeldProducts, 1);
      expect(analysis.retiredHeldUnits, 24);
      expect(
        analysis.retiredHeldCostMinor,
        144000,
        reason:
            'Stock the business owns and cannot sell, which is exactly what '
            'the screen hides.',
      );
    });
  });

  group('where the money is sitting', () {
    test('products are ranked by value, most first', () {
      final analysis = fixtureInventoryAnalysis();

      expect(analysis.largest.first.name, 'Tusker 500ml');
      expect(analysis.largest.first.costMinor, 4320000);
    });

    test('an uncosted line is ranked by what it would sell for', () {
      final analysis = fixtureInventoryAnalysis();

      final matches = analysis.largest.firstWhere((l) => l.name == 'Matches');
      expect(matches.costMinor, isNull);
      expect(
        matches.retailMinor,
        200000,
        reason:
            'So it is not pushed to the bottom of the ranking as though it '
            'were worthless.',
      );
    });

    test('concentration answers how few lines carry the value', () {
      final analysis = fixtureInventoryAnalysis();

      expect(
        analysis.productsFor(0.75),
        2,
        reason: 'Two products carry three quarters of what the stock is worth.',
      );
      // 4320000 + 2970000 of 7578000.
      expect(analysis.shareOfTopProducts(2), closeTo(0.9620, 0.001));
    });

    test('nothing valued claims no concentration', () {
      final analysis = TenantInventoryAnalysis.from(
        takenAt: fixtureInventoryInstant(),
        products: <TenantProduct>[
          productRecord(
            id: 'product-1',
            name: 'Matches',
            sku: 'MTC',
            price: 10,
            quantity: 5,
            categoryId: 'dry',
          ),
        ],
      );

      expect(analysis.costMinor, 0);
      expect(analysis.productsFor(0.75), isNull);
      expect(analysis.shareOfTopProducts(2), isNull);
    });
  });

  group('by category', () {
    test('headings are ranked by value and named, not keyed', () {
      final analysis = fixtureInventoryAnalysis();

      expect(analysis.headings.first.name, 'Drinks');
      expect(analysis.headings.first.costMinor, 4464000);
    });

    test('every product has a heading, because every product has a category', () {
      // `categoryId` is required on the document and the read model refuses a
      // product without one, so there is no uncategorised bucket to draw.
      final analysis = fixtureInventoryAnalysis();

      expect(
        analysis.headings.fold<int>(0, (sum, h) => sum + h.products),
        analysis.productCount,
      );
    });

    test('a category whose name could not be read falls back to its id', () {
      final analysis = TenantInventoryAnalysis.from(
        takenAt: fixtureInventoryInstant(),
        products: fixtureCatalog(),
      );

      expect(
        analysis.headings.map((heading) => heading.name),
        containsAll(<String>['drinks', 'dry']),
        reason:
            'It still groups correctly. Refusing the report over a missing '
            'label would be a poor trade.',
      );
    });

    test('a heading carries how many of its products could not be valued', () {
      final analysis = fixtureInventoryAnalysis();

      final dry = analysis.headings.firstWhere((h) => h.name == 'Dry goods');
      expect(dry.uncostedProducts, 1);
    });
  });

  test('the instant it was taken is carried, because it is the whole scope', () {
    final analysis = fixtureInventoryAnalysis();

    expect(analysis.takenAt, fixtureInventoryInstant());
  });
}
