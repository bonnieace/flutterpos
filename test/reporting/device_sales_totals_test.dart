import 'dart:io';

import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/reporting/reporting.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;
  late Box<dynamic> box;
  late HiveCheckoutOutbox outbox;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('device-totals-');
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>('device-totals-test');
    outbox = HiveCheckoutOutbox.fromBox(box);
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('a return held on this device comes out of its figures', () async {
    // **The offline path used to report gross**, so the same period read with
    // signal and without it disagreed by exactly the refunds - and the notice
    // under the figure blamed sales from other tills, which points the
    // opposite way from the real cause.
    final reader = _Reader(
      <TenantQueryDocumentSnapshot>[
        _canonicalSale(
          checkoutId: 'checkout-a',
          totalMinor: 900,
          lineTotalMinor: 1000,
          categoryId: 'drinks',
          costMinor: 600,
          tender: 'cash',
        ),
        _canonicalSale(
          checkoutId: 'checkout-b',
          totalMinor: 500,
          lineTotalMinor: 500,
          categoryId: 'food',
          costMinor: 200,
          tender: 'card',
        ),
      ],
      returns: <Map<String, Object?>>[
        _cachedReturn(
          returnId: 'return-a',
          saleId: 'checkout-a',
          productId: 'product-checkout-a',
        ),
      ],
    );
    final aggregator = TenantDeviceSalesAggregator(
      session: _session(),
      cacheReader: reader,
      cacheReportReader: reader,
      clock: () => DateTime.utc(2026, 9, 1, 12),
    );

    final totals = (await aggregator.load(
      aggregator.createBusinessDateQuery(businessDate: '2026-09-01'),
    )).totals!;

    // Gross is untouched: both sales happened.
    expect(totals.sales, 14);
    expect(totals.transactions, 2);
    // The single line of checkout-a came back in full, so that sale stops
    // being a transaction at all.
    expect(totals.net!.sales, 5);
    expect(totals.net!.transactions, 1);
    expect(totals.net!.returnsScanned, 1);
    expect(totals.netOrGrossSales, 5);
  });

  test('a day with nothing returned still states that it netted', () async {
    // Absent and zero are different facts. A period that read its returns and
    // found none can say so; one that never read them must not.
    final reader = _Reader(<TenantQueryDocumentSnapshot>[
      _canonicalSale(
        checkoutId: 'checkout-a',
        totalMinor: 900,
        lineTotalMinor: 1000,
        categoryId: 'drinks',
        costMinor: 600,
        tender: 'cash',
      ),
    ]);
    final aggregator = TenantDeviceSalesAggregator(
      session: _session(),
      cacheReader: reader,
      cacheReportReader: reader,
      clock: () => DateTime.utc(2026, 9, 1, 12),
    );

    final totals = (await aggregator.load(
      aggregator.createBusinessDateQuery(businessDate: '2026-09-01'),
    )).totals!;

    expect(totals.net, isNotNull);
    expect(totals.net!.returnsScanned, 0);
    expect(totals.net!.sales, totals.sales);
  });

  test('a fully returned costless line stops withholding the margin', () async {
    // The same rule the server applies: the line contributes no revenue and
    // no cost to the net figures, so its missing cost cannot move net profit
    // - and a customer undoing a sale must not leave the report permanently
    // unable to state one.
    final reader = _Reader(
      <TenantQueryDocumentSnapshot>[
        _canonicalSale(
          checkoutId: 'checkout-a',
          totalMinor: 900,
          lineTotalMinor: 1000,
          categoryId: 'drinks',
          costMinor: 600,
          tender: 'cash',
        ),
        _canonicalSale(
          checkoutId: 'checkout-b',
          totalMinor: 500,
          lineTotalMinor: 500,
          categoryId: 'food',
          costMinor: null,
          tender: 'card',
        ),
      ],
      returns: <Map<String, Object?>>[
        _cachedReturn(
          returnId: 'return-b',
          saleId: 'checkout-b',
          productId: 'product-checkout-b',
        ),
      ],
    );
    final aggregator = TenantDeviceSalesAggregator(
      session: _session(),
      cacheReader: reader,
      cacheReportReader: reader,
      clock: () => DateTime.utc(2026, 9, 1, 12),
    );

    final totals = (await aggregator.load(
      aggregator.createBusinessDateQuery(businessDate: '2026-09-01'),
    )).totals!;

    expect(totals.incompleteCostLineCount, 1);
    expect(
      totals.net!.incompleteCostLineCount,
      0,
      reason: 'the costless goods are entirely out of the net figures',
    );
    expect(totals.net!.profitReport.isShowable, isTrue);
  });

  test('matches server revenue, category, cost and tender semantics', () async {
    final reader = _Reader(<TenantQueryDocumentSnapshot>[
      _canonicalSale(
        checkoutId: 'checkout-a',
        totalMinor: 900,
        lineTotalMinor: 1000,
        categoryId: 'drinks',
        costMinor: 600,
        tender: 'cash',
      ),
      _canonicalSale(
        checkoutId: 'checkout-b',
        totalMinor: 500,
        lineTotalMinor: 500,
        categoryId: 'food',
        costMinor: null,
        tender: 'card',
      ),
    ]);
    final aggregator = TenantDeviceSalesAggregator(
      session: _session(),
      cacheReader: reader,
      cacheReportReader: reader,
      clock: () => DateTime.utc(2026, 9, 1, 12),
    );

    final all = (await aggregator.load(
      aggregator.createBusinessDateQuery(businessDate: '2026-09-01'),
    )).totals!;
    expect(all.basis, TenantSalesTotalsBasis.device);
    expect(all.sales, 14);
    expect(all.transactions, 2);
    expect(all.averageSale, 7);
    expect(all.profit, 8);
    expect(all.incompleteCostLineCount, 1);
    expect(all.tenderBreakdown!.recorded[CheckoutTender.cash]!.sales, 9);
    expect(all.tenderBreakdown!.recorded[CheckoutTender.card]!.sales, 5);

    final drinks = (await aggregator.load(
      aggregator.createBusinessDateQuery(
        businessDate: '2026-09-01',
        categoryId: 'drinks',
      ),
    )).totals!;
    expect(drinks.scannedTransactions, 2);
    expect(drinks.transactions, 1);
    // Category totals use matching line revenue, not the discounted sale total.
    expect(drinks.sales, 10);
    expect(drinks.profit, 4);
  });

  test(
    'merges outbox evidence and deduplicates a canonical checkout',
    () async {
      final first = await _save(outbox, checkoutId: 'checkout-a', sequence: 1);
      await _save(outbox, checkoutId: 'checkout-b', sequence: 2);
      final sale = CheckoutSalePayload.fromOutboxRecord(
        first,
        session: _session(),
      ).toSubmission();
      final reader = _Reader(<TenantQueryDocumentSnapshot>[
        TenantQueryDocumentSnapshot(
          path: sale.salePath,
          data: <String, Object?>{
            ...sale.saleFields,
            'createdAt': DateTime.now(),
          },
        ),
      ]);
      final aggregator = TenantDeviceSalesAggregator(
        session: _session(),
        cacheReader: reader,
        cacheReportReader: reader,
        outbox: outbox,
        clock: () => DateTime.utc(2026, 9, 1, 12),
      );

      final result = await aggregator.load(
        aggregator.createBusinessDateQuery(businessDate: '2026-09-01'),
      );
      expect(result.scannedRecordCount, 2);
      expect(result.totals!.transactions, 2);
      expect(result.totals!.sales, 20);
    },
  );

  test('withholds a provisional figure when hashes conflict', () async {
    final record = await _save(outbox, checkoutId: 'checkout-a', sequence: 1);
    final sale = CheckoutSalePayload.fromOutboxRecord(
      record,
      session: _session(),
    ).toSubmission();
    final reader = _Reader(<TenantQueryDocumentSnapshot>[
      TenantQueryDocumentSnapshot(
        path: sale.salePath,
        data: <String, Object?>{
          ...sale.saleFields,
          'payloadHash': 'f'.padRight(64, 'f'),
          'createdAt': DateTime.now(),
        },
      ),
    ]);
    final aggregator = TenantDeviceSalesAggregator(
      session: _session(),
      cacheReader: reader,
      cacheReportReader: reader,
      outbox: outbox,
      clock: () => DateTime.utc(2026, 9, 1, 12),
    );

    final result = await aggregator.load(
      aggregator.createBusinessDateQuery(businessDate: '2026-09-01'),
    );
    expect(result.totals, isNull);
    expect(result.refusal, TenantDeviceSalesRefusal.conflictingEvidence);
  });
}

Future<CheckoutOutboxRecord> _save(
  HiveCheckoutOutbox outbox, {
  required String checkoutId,
  required int sequence,
}) => outbox.saveOffline(
  uid: 'owner-a',
  tenantId: 'tenant-a',
  checkoutId: checkoutId,
  payload: <String, Object?>{
    'schemaVersion': checkoutSalePayloadSchemaVersion,
    'checkoutId': checkoutId,
    'tenantId': 'tenant-a',
    'soldById': 'owner-a',
    'currency': 'KES',
    'businessDate': '2026-09-01',
    'createdAtMs': DateTime.utc(2026, 9, 1, 8).millisecondsSinceEpoch,
    'shiftId': 'shift-a',
    'deviceId': _deviceId,
    'receiptNumber': formatCheckoutReceiptNumber(
      deviceId: _deviceId,
      businessDate: '2026-09-01',
      sequence: sequence,
    ),
    'receiptSequence': sequence,
    'tender': 'cash',
    'items': <Object?>[
      <String, Object?>{
        'productId': 'product-$checkoutId',
        'name': 'Item $checkoutId',
        'categoryId': 'drinks',
        'quantity': 1,
        'unitPriceMinor': 1000,
        'unitCostMinor': 400,
      },
    ],
    'subtotalMinor': 1000,
    'discountMinor': 0,
    'totalMinor': 1000,
  },
);

/// One return document, as this device's cache would hold it.
Map<String, Object?> _cachedReturn({
  required String returnId,
  required String saleId,
  required String productId,
  int quantity = 1,
  String businessDate = '2026-09-01',
}) => <String, Object?>{
  'returnId': returnId,
  'tenantId': 'tenant-a',
  'saleId': saleId,
  'businessDate': businessDate,
  'recordedOn': businessDate,
  'createdBy': 'owner-a',
  'status': 'pending',
  'reason': 'Customer changed their mind',
  'itemsReturned': <Object?>[
    <String, Object?>{'productId': productId, 'quantity': quantity},
  ],
  'createdAt': DateTime.utc(2026, 9, 1, 9),
};

TenantQueryDocumentSnapshot _canonicalSale({
  required String checkoutId,
  required int totalMinor,
  required int lineTotalMinor,
  required String categoryId,
  required int? costMinor,
  required String tender,
}) => TenantQueryDocumentSnapshot(
  path: 'tenants/tenant-a/sales/$checkoutId',
  data: <String, Object?>{
    'checkoutId': checkoutId,
    'tenantId': 'tenant-a',
    'soldById': 'owner-a',
    'payloadHash': 'a'.padRight(64, 'a'),
    'payloadSchemaVersion': 2,
    'tender': tender,
    'currency': 'KES',
    'businessDate': '2026-09-01',
    'shiftId': 'shift-a',
    'deviceId': _deviceId,
    'receiptNumber': formatCheckoutReceiptNumber(
      deviceId: _deviceId,
      businessDate: '2026-09-01',
      sequence: checkoutId == 'checkout-a' ? 1 : 2,
    ),
    'receiptSequence': checkoutId == 'checkout-a' ? 1 : 2,
    'items': <Object?>[
      <String, Object?>{
        'productId': 'product-$checkoutId',
        'name': 'Item',
        'categoryId': categoryId,
        'quantity': 1,
        'unitPriceMinor': lineTotalMinor,
        'lineTotalMinor': lineTotalMinor,
        if (costMinor != null) 'unitCostMinor': costMinor,
        if (costMinor != null) 'costMinor': costMinor,
      },
    ],
    'subtotalMinor': lineTotalMinor,
    'subtotal': lineTotalMinor / 100,
    'discountMinor': lineTotalMinor - totalMinor,
    'discount': (lineTotalMinor - totalMinor) / 100,
    'totalMinor': totalMinor,
    'total': totalMinor / 100,
    'createdAt': DateTime.utc(2026, 9, 1, 8),
  },
);

TenantSession _session() => TenantSession.active(
  uid: 'owner-a',
  tenantId: 'tenant-a',
  role: TenantRole.owner,
);

const String _deviceId = 'dev-0123456789abcdef0123456789abcdef';

final class _Reader implements TenantDataReader, TenantSalesHistoryQueryReader {
  _Reader(this.documents, {this.returns = const <Map<String, Object?>>[]});

  final List<TenantQueryDocumentSnapshot> documents;

  /// Return documents this device has in its cache, as the returns collection
  /// would hold them.
  final List<Map<String, Object?>> returns;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async => null;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    if (!query.collectionPath.endsWith('/returns')) {
      return const <TenantQueryDocumentSnapshot>[];
    }
    // The aggregator asks a day at a time, so the day filter is the whole of
    // the query it issues.
    final day = query.equalityFilters['businessDate'];
    return <TenantQueryDocumentSnapshot>[
      for (final record in returns)
        if (day == null || record['businessDate'] == day)
          TenantQueryDocumentSnapshot(
            path: '${query.collectionPath}/${record['returnId']}',
            data: record,
          ),
    ];
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> queryTenantSalesHistory(
    TenantSalesHistoryQuery query,
  ) async {
    final matches = documents.where((document) {
      final data = document.data;
      final date = data['businessDate']! as String;
      return date.compareTo(query.startBusinessDate) >= 0 &&
          date.compareTo(query.endBusinessDate) <= 0 &&
          (query.soldById == null || data['soldById'] == query.soldById);
    }).toList();
    matches.sort((left, right) {
      final leftDate = left.data['businessDate']! as String;
      final rightDate = right.data['businessDate']! as String;
      final byDate = rightDate.compareTo(leftDate);
      return byDate != 0 ? byDate : right.path.compareTo(left.path);
    });
    final cursor = query.startAfter;
    final after = cursor == null
        ? matches
        : matches.where((document) {
            final date = document.data['businessDate']! as String;
            final id = document.path.split('/').last;
            return date.compareTo(cursor.businessDate) < 0 ||
                date == cursor.businessDate &&
                    id.compareTo(cursor.documentId) < 0;
          }).toList();
    return after.take(query.limit).toList(growable: false);
  }
}
