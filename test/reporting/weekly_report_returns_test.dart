/// What the weekly report's item figures do about the goods that came back.
///
/// **The reported defect, 2026-09-20.** *Items sold* counted every unit that
/// crossed the counter while every figure beside it - takings, average sale,
/// profit - had its returns taken off by the server. A week with returns
/// therefore read more items than its own money implied, and nothing on the
/// page said why. *Top selling items* was gross for the same reason, so the
/// list under the card did not add up to the card either.
///
/// Netting it costs one query per elapsed day and no extra sale reads: a return
/// is valued against the sale it reverses, and the roll-up has already read
/// every sale it counted.
///
/// Kept apart from `weekly_report_filters_test.dart`, which is about what the
/// staff and category filters reach, though the two share a fixture shape.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/checkout/checkout_receipt.dart';
import 'package:flutter_application_1/expenses/expense_repository.dart';
import 'package:flutter_application_1/reporting/reporting.dart';
import 'package:flutter_application_1/returns/returns.dart';
import 'package:flutter_application_1/sales/sale_history.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wednesday, so the current week holds three elapsed days of seven.
final DateTime _now = DateTime.utc(2026, 8, 26, 12);

const String _tenant = 'tenant-a';
const String _uid = 'user-a';
const String _device = 'dev-0123456789abcdef0123456789abcdef';

void main() {
  group('a week states its items on the same basis as its money', () {
    test('a week with no returns read is gross, and says so', () async {
      // The composition without a returns reader, which is what every caller
      // did until now. The figure is unchanged; what is new is that it no
      // longer presents itself as comparable with the net money beside it.
      final report = await _load(readsReturns: false);

      expect(report.itemsSold, 6);
      expect(report.netsItemsSold, isFalse);
    });

    test('returned units come out of the count', () async {
      // One loaf back out of `co-002`, and one beer out of the mixed receipt.
      final report = await _load();

      expect(report.itemsSold, 4);
      expect(report.netsItemsSold, isTrue);
    });

    test('returned value comes off the seller it came back from', () async {
      final report = await _load();
      final byProduct = <String, TenantReportItem>{
        for (final item in report.topItems) item.productId: item,
      };

      // Beer: three sold at 1000, one back. Bread: three sold, one back.
      expect(byProduct['beer']!.quantity, 2);
      expect(byProduct['beer']!.revenueMinor, 2000);
      expect(byProduct['bread']!.quantity, 2);
      expect(byProduct['bread']!.revenueMinor, 2000);
    });

    test('a category nets only what came back inside it', () async {
      // The loaf that came back is food. Under drinks it must take nothing
      // off, exactly as the sale it came out of contributes nothing.
      final report = await _load(categoryId: 'drinks');

      expect(report.itemsSold, 2, reason: 'three beers sold, one returned');
      expect(report.netsItemsSold, isTrue);
    });

    test(
      'a return against a colleague nobody asked about is left alone',
      () async {
        // The scan is already filtered to one seller, so a return against a sale
        // it never counted cannot take anything off it. Here every sale belongs
        // to `_uid`, so filtering to another colleague empties the roll-up and
        // the returns have nothing to reach.
        final report = await _load(soldById: 'user-elsewhere');

        expect(report.itemsSold, 0);
      },
    );
  });

  group('a netting that cannot be trusted is not done at all', () {
    test('a refused returns read leaves the week gross and labelled', () async {
      // Netting part of a week understates the items silently while wearing
      // the net label, which is worse than the defect this fixes.
      final report = await _load(returnsFail: true);

      expect(report.itemsSold, 6);
      expect(report.netsItemsSold, isFalse);
    });

    test('a return naming a product its sale never sold is refused', () async {
      final report = await _load(
        returns: <Map<String, Object?>>[
          _returnDoc(
            returnId: 'ret-001',
            saleId: 'co-002',
            businessDate: '2026-08-25',
            // `co-002` sold bread and nothing else.
            lines: <Map<String, Object?>>[
              <String, Object?>{'productId': 'beer', 'quantity': 1},
            ],
          ),
        ],
      );

      expect(report.itemsSold, 6);
      expect(report.netsItemsSold, isFalse);
    });
  });
}

Future<TenantWeeklyReport> _load({
  String? soldById,
  String? categoryId,
  bool returnsFail = false,
  bool readsReturns = true,
  List<Map<String, Object?>>? returns,
}) async {
  final session = TenantSession.active(
    uid: _uid,
    tenantId: _tenant,
    role: TenantRole.owner,
  );
  final reader = _Reader(
    sales: <Map<String, Object?>>[
      _sale(
        saleId: 'co-001',
        sequence: 1,
        businessDate: '2026-08-25',
        lines: <Map<String, Object?>>[
          _line(productId: 'beer', categoryId: 'drinks'),
        ],
      ),
      _sale(
        saleId: 'co-002',
        sequence: 2,
        businessDate: '2026-08-25',
        lines: <Map<String, Object?>>[
          _line(productId: 'bread', categoryId: 'food', quantity: 2),
        ],
      ),
      _sale(
        saleId: 'co-003',
        sequence: 3,
        businessDate: '2026-08-26',
        lines: <Map<String, Object?>>[
          _line(productId: 'beer', categoryId: 'drinks'),
        ],
      ),
      _sale(
        saleId: 'co-004',
        sequence: 4,
        businessDate: '2026-08-26',
        lines: <Map<String, Object?>>[
          _line(productId: 'bread', categoryId: 'food'),
          _line(productId: 'beer', categoryId: 'drinks'),
        ],
      ),
    ],
    returns: returns ?? _defaultReturns,
    returnsFail: returnsFail,
  );
  final loader = TenantWeeklyReportLoader(
    session: session,
    callable: _Callable(),
    sales: TenantSaleHistoryRepository(
      session: session,
      reader: reader,
      reportReader: reader,
    ),
    expenses: TenantExpenseRepository(session: session, reader: reader),
    returns: readsReturns
        ? TenantReturnHistoryRepository(session: session, reader: reader)
        : null,
    clock: () => _now,
  );
  return loader.load(
    TenantReportWeek.at(_now),
    soldById: soldById,
    categoryId: categoryId,
  );
}

/// One loaf back out of a food-only sale, and one beer out of a mixed receipt,
/// so a category scope has something to include and something to leave out.
final List<Map<String, Object?>> _defaultReturns = <Map<String, Object?>>[
  _returnDoc(
    returnId: 'ret-001',
    saleId: 'co-002',
    businessDate: '2026-08-25',
    lines: <Map<String, Object?>>[
      <String, Object?>{'productId': 'bread', 'quantity': 1},
    ],
  ),
  _returnDoc(
    returnId: 'ret-002',
    saleId: 'co-004',
    businessDate: '2026-08-26',
    lines: <Map<String, Object?>>[
      <String, Object?>{'productId': 'beer', 'quantity': 1},
    ],
  ),
];

Map<String, Object?> _returnDoc({
  required String returnId,
  required String saleId,
  required String businessDate,
  required List<Map<String, Object?>> lines,
}) => <String, Object?>{
  'returnId': returnId,
  'tenantId': _tenant,
  'saleId': saleId,
  'businessDate': businessDate,
  'recordedOn': businessDate,
  'createdBy': _uid,
  'status': 'pending',
  'reason': 'Damaged',
  'itemsReturned': lines,
  'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 26, 12)),
};

/// Answers every range with the same shape. The comparison is not what this
/// file is about; it only has to exist so the week composes.
final class _Callable implements SalesTotalsCallable {
  @override
  Future<Object?> call(Map<String, Object?> payload) async => <String, Object?>{
    'scannedTransactions': 1,
    'previous': <String, Object?>{
      'sales': 10.0,
      'profit': 4.0,
      'transactions': 1,
      'incompleteCostLineCount': 0,
    },
    'net': <String, Object?>{
      'sales': 10.0,
      'profit': 4.0,
      'transactions': 1,
      'incompleteCostLineCount': 0,
    },
  };
}

Map<String, Object?> _line({
  required String productId,
  required String categoryId,
  int quantity = 1,
}) => <String, Object?>{
  'productId': productId,
  'name': productId,
  'categoryId': categoryId,
  'quantity': quantity,
  'unitPriceMinor': 1000,
  'unitPrice': 10.0,
  'lineTotalMinor': 1000 * quantity,
  'lineTotal': 10.0 * quantity,
};

Map<String, Object?> _sale({
  required String saleId,
  required int sequence,
  required String businessDate,
  required List<Map<String, Object?>> lines,
}) {
  final subtotal = lines.fold<int>(
    0,
    (total, line) => total + (line['lineTotalMinor']! as int),
  );
  return <String, Object?>{
    'checkoutId': saleId,
    'tenantId': _tenant,
    'soldById': _uid,
    'payloadHash': 'a' * 64,
    'payloadSchemaVersion': 2,
    'currency': 'KES',
    'businessDate': businessDate,
    'clientCreatedAtMs': 1785484800000,
    'shiftId': 'shift-a',
    'deviceId': _device,
    'receiptNumber': formatCheckoutReceiptNumber(
      deviceId: _device,
      businessDate: businessDate,
      sequence: sequence,
    ),
    'receiptSequence': sequence,
    'items': lines,
    'subtotalMinor': subtotal,
    'subtotal': subtotal / 100,
    'discountMinor': 0,
    'discount': 0.0,
    'totalMinor': subtotal,
    'total': subtotal / 100,
    'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 26, 12)),
  };
}

/// Pages the sale scan the way Firestore does, serves the returns collection,
/// and answers every other read empty.
final class _Reader implements TenantDataReader, TenantSalesHistoryQueryReader {
  _Reader({
    required List<Map<String, Object?>> sales,
    required List<Map<String, Object?>> returns,
    required this.returnsFail,
  }) : _sales = sales,
       _returns = returns;

  final List<Map<String, Object?>> _sales;
  final List<Map<String, Object?>> _returns;
  final bool returnsFail;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async => null;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    if (!query.collectionPath.endsWith('/returns')) {
      return const <TenantQueryDocumentSnapshot>[];
    }
    if (returnsFail) throw StateError('permission-denied');
    final matches =
        <Map<String, Object?>>[
          for (final record in _returns)
            if (query.equalityFilters.entries.every(
              (filter) => record[filter.key] == filter.value,
            ))
              record,
        ]..sort(
          (a, b) =>
              (b['returnId']! as String).compareTo(a['returnId']! as String),
        );
    return <TenantQueryDocumentSnapshot>[
      for (final record in matches.take(query.limit))
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
    final ordered =
        <Map<String, Object?>>[
          for (final sale in _sales)
            if ((sale['businessDate']! as String).compareTo(
                      query.startBusinessDate,
                    ) >=
                    0 &&
                (sale['businessDate']! as String).compareTo(
                      query.endBusinessDate,
                    ) <=
                    0 &&
                (query.soldById == null || sale['soldById'] == query.soldById))
              sale,
        ]..sort((a, b) {
          final byDate = (b['businessDate']! as String).compareTo(
            a['businessDate']! as String,
          );
          if (byDate != 0) return byDate;
          return (b['checkoutId']! as String).compareTo(
            a['checkoutId']! as String,
          );
        });
    var rest = ordered;
    if (query.startAfter case final cursor?) {
      final at = ordered.indexWhere(
        (sale) => sale['checkoutId'] == cursor.documentId,
      );
      rest = at == -1 ? ordered : ordered.sublist(at + 1);
    }
    final take = rest.length < query.limit ? rest.length : query.limit;
    return <TenantQueryDocumentSnapshot>[
      for (final sale in rest.take(take))
        TenantQueryDocumentSnapshot(
          path: '${query.collectionPath}/${sale['checkoutId']}',
          data: sale,
        ),
    ];
  }
}
