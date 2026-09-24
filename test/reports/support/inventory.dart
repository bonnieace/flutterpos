/// A small shop's catalog, for the inventory report's tests and samples.
///
/// Shaped like a real one rather than like tidy test data: the value is
/// concentrated in two lines, one product records no cost, one holds less than
/// nothing, one is retired and still on the shelf, and one is out of stock.
/// Those are the cases the report has something to say about.
library;

import 'package:flutter_application_1/reports/analysis/inventory_analysis.dart';
import 'package:flutter_application_1/tenancy/tenant_catalog.dart';

TenantProduct productRecord({
  required String id,
  required String name,
  required String sku,
  required double price,
  required int quantity,
  double? cost,
  required String categoryId,
  bool retired = false,
}) => TenantProduct.fromDocument(
  path: 'tenants/tenant-a/products/$id',
  data: <String, Object?>{
    'name': name,
    'SKU': sku,
    'price': price,
    if (cost != null) 'cost': cost,
    'quantity': quantity,
    'categoryId': categoryId,
    if (retired) 'retired': true,
  },
);

Map<String, String> fixtureCategoryNames() => const <String, String>{
  'drinks': 'Drinks',
  'dry': 'Dry goods',
};

List<TenantProduct> fixtureCatalog() => <TenantProduct>[
  // Most of the money is here.
  productRecord(
    id: 'product-1',
    name: 'Tusker 500ml',
    sku: 'TSK500',
    price: 250,
    cost: 180,
    quantity: 240,
    categoryId: 'drinks',
  ),
  productRecord(
    id: 'product-2',
    name: 'Cooking oil 1L',
    sku: 'OIL1L',
    price: 420,
    cost: 330,
    quantity: 90,
    categoryId: 'dry',
  ),
  productRecord(
    id: 'product-3',
    name: 'Bread',
    sku: 'BRD',
    price: 65,
    cost: 48,
    quantity: 30,
    categoryId: 'dry',
  ),
  // No cost was ever recorded: in the unit count and in no valuation.
  productRecord(
    id: 'product-4',
    name: 'Matches',
    sku: 'MTC',
    price: 10,
    quantity: 200,
    categoryId: 'dry',
  ),
  // Retired and still on the shelf: stock the business owns and cannot sell.
  productRecord(
    id: 'product-5',
    name: 'Old label soda',
    sku: 'OLD',
    price: 90,
    cost: 60,
    quantity: 24,
    categoryId: 'drinks',
    retired: true,
  ),
  // A book that has gone wrong.
  productRecord(
    id: 'product-6',
    name: 'Sugar 1kg',
    sku: 'SGR1',
    price: 180,
    cost: 140,
    quantity: -6,
    categoryId: 'dry',
  ),
  // Nothing on the shelf.
  productRecord(
    id: 'product-7',
    name: 'Milk 500ml',
    sku: 'MLK',
    price: 60,
    cost: 45,
    quantity: 0,
    categoryId: 'drinks',
  ),
];

/// Noon UTC on 23 September 2026.
DateTime fixtureInventoryInstant() => DateTime.utc(2026, 9, 23, 12);

TenantInventoryAnalysis fixtureInventoryAnalysis({bool truncated = false}) =>
    TenantInventoryAnalysis.from(
      takenAt: fixtureInventoryInstant(),
      products: fixtureCatalog(),
      categoryNames: fixtureCategoryNames(),
      truncated: truncated,
    );
