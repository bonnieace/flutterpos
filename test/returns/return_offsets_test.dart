import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:uzapay_pos/returns/returns.dart';
import 'package:uzapay_pos/sales/sales.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

const String _deviceA = 'dev-0123456789abcdef0123456789abcdef';
const String _businessDate = '2026-07-31';
const String _payloadHash =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

void main() {
  group('what one sale has had taken back out of it', () {
    test('a partial return is worth what those units were sold for', () {
      final offset = describeReturnOffset(_sale(), <String, int>{
        'product-1': 2,
      });

      expect(offset.returnedUnits, <String, int>{'product-1': 2});
      expect(offset.returnedMinor, 1000);
      expect(offset.isFullyReturned, isFalse);
      expect(offset.tender, CheckoutTender.cash);
      expect(offset.soldById, 'user-a');
    });

    test('a return of every unit is worth the sale, not its lines', () {
      // 2500 of lines, discounted to 2200. Priced line by line a full return
      // would hand back 2500 - three hundred shillings the customer never paid.
      final offset = describeReturnOffset(
        _sale(discountMinor: 300),
        <String, int>{'product-1': 4, 'product-2': 5},
      );

      expect(offset.isFullyReturned, isTrue);
      expect(offset.returnedMinor, 2200);
    });

    test('a discount is shared pro rata across a partial return', () {
      // 1000 of a 2500 subtotal, on a sale charged at 2200: 1000 * 2200/2500.
      final offset = describeReturnOffset(
        _sale(discountMinor: 300),
        <String, int>{'product-1': 2},
      );

      expect(offset.returnedMinor, 880);
      expect(offset.isFullyReturned, isFalse);
    });

    test('the per-product split adds up to the figure beside it', () {
      // 2500 of lines discounted to 2200, every unit back: 4 x 500 and 5 x 100
      // apportioned over 2200. Neither share divides cleanly, and the two of
      // them still have to be the 2200 printed above them.
      final offset = describeReturnOffset(
        _sale(discountMinor: 300),
        <String, int>{'product-1': 4, 'product-2': 5},
      );

      expect(
        offset.returnedMinorByProduct.values.fold<int>(
          0,
          (total, share) => total + share,
        ),
        offset.returnedMinor,
      );
      expect(offset.returnedMinorByProduct['product-1'], 1760);
      expect(offset.returnedMinorByProduct['product-2'], 440);
    });

    test('a category scope counts only the units it valued', () {
      // `returnedUnits` names everything the return covers whatever scope it
      // was priced under. A report netting a category's item count has to
      // subtract what that category added, which is the narrower map.
      final offset = describeReturnOffset(_sale(), <String, int>{
        'product-1': 2,
        'product-2': 1,
      }, categoryId: 'drinks');

      expect(offset.returnedUnits, <String, int>{
        'product-1': 2,
        'product-2': 1,
      });
      expect(offset.returnedUnitsInScope, <String, int>{'product-1': 2});
    });

    test('more units than the sale sold is refused, never clamped', () {
      expect(
        () => describeReturnOffset(_sale(), <String, int>{'product-1': 5}),
        _code('return_exceeds_sale'),
      );
    });

    test('a product the sale never sold is refused', () {
      expect(
        () => describeReturnOffset(_sale(), <String, int>{'product-9': 1}),
        _code('return_exceeds_sale'),
      );
    });
  });

  group('a trading day of returns', () {
    test('is read by the sale it reverses, and priced against it', () async {
      final reader = _Reader(
        sales: <String, TenantSale>{
          'co-1': _sale(),
          'co-2': _sale(id: 'co-2'),
        },
        returns: <TenantQueryDocumentSnapshot>[
          _record(
            'rt-1',
            saleId: 'co-1',
            quantities: <String, int>{'product-1': 4, 'product-2': 5},
          ),
          _record(
            'rt-2',
            saleId: 'co-2',
            quantities: <String, int>{'product-2': 1},
          ),
        ],
      );

      final day = await TenantDayReturnsLoader(
        session: _session(),
        reader: reader,
      ).load(_businessDate);

      // The query is by the sale's day, and only the sales something came out
      // of are read.
      expect(reader.returnQueries.single, _businessDate);
      expect(reader.readSales, unorderedEquals(<String>['co-1', 'co-2']));
      expect(day.returnedMinor, 2500 + 100);
      expect(day.fullyReturnedSales, 1);
      expect(day.returnedMinorByTender, <CheckoutTender?, int>{
        CheckoutTender.cash: 2600,
      });
      expect(day.fullyReturnedByTender, <CheckoutTender?, int>{
        CheckoutTender.cash: 1,
      });
    });

    test(
      'two returns against one sale add up before they are priced',
      () async {
        final reader = _Reader(
          sales: <String, TenantSale>{'co-1': _sale()},
          returns: <TenantQueryDocumentSnapshot>[
            _record(
              'rt-1',
              saleId: 'co-1',
              quantities: <String, int>{'product-1': 4},
            ),
            _record(
              'rt-2',
              saleId: 'co-1',
              quantities: <String, int>{'product-2': 5},
            ),
          ],
        );

        final day = await TenantDayReturnsLoader(
          session: _session(),
          reader: reader,
        ).load(_businessDate);

        // Neither return covers the sale on its own; together they do.
        expect(day.covers(_sale()), isTrue);
        expect(day.returnedMinor, 2500);
      },
    );

    test('narrows to one colleague by who sold, not by who refunded', () async {
      final reader = _Reader(
        sales: <String, TenantSale>{
          'co-1': _sale(),
          'co-2': _sale(id: 'co-2', soldById: 'user-b'),
        },
        returns: <TenantQueryDocumentSnapshot>[
          // Recorded by user-a against a sale user-b rang up: it comes out of
          // user-b's day.
          _record(
            'rt-1',
            saleId: 'co-2',
            quantities: <String, int>{'product-1': 2},
          ),
          _record(
            'rt-2',
            saleId: 'co-1',
            quantities: <String, int>{'product-2': 1},
          ),
        ],
      );

      final day = await TenantDayReturnsLoader(
        session: _session(),
        reader: reader,
      ).load(_businessDate);

      expect(day.returnedMinor, 1100);
      expect(day.scopedTo('user-a').returnedMinor, 100);
      expect(day.scopedTo('user-b').returnedMinor, 1000);
      expect(day.scopedTo(null).returnedMinor, 1100);
    });

    test('a return whose sale cannot be read fails the day closed', () async {
      final reader = _Reader(
        sales: const <String, TenantSale>{},
        returns: <TenantQueryDocumentSnapshot>[
          _record(
            'rt-1',
            saleId: 'co-1',
            quantities: <String, int>{'product-1': 1},
          ),
        ],
      );

      // Under-netting a day's takings by the one return it could not price is
      // exactly the wrong figure this whole model exists to remove.
      await expectLater(
        TenantDayReturnsLoader(
          session: _session(),
          reader: reader,
        ).load(_businessDate),
        _code('return_sale_missing'),
      );
    });

    test('a day with nothing returned reads no sale at all', () async {
      final reader = _Reader(
        sales: <String, TenantSale>{'co-1': _sale()},
        returns: const <TenantQueryDocumentSnapshot>[],
      );

      final day = await TenantDayReturnsLoader(
        session: _session(),
        reader: reader,
      ).load(_businessDate);

      expect(day.isEmpty, isTrue);
      expect(day.returnedMinor, 0);
      expect(reader.readSales, isEmpty);
      expect(day.netTotalMinorOf(_sale()), 2500);
      expect(day.covers(_sale()), isFalse);
    });
  });
}

TenantSession _session() => TenantSession.active(
  uid: 'user-a',
  tenantId: 'tenant-a',
  role: TenantRole.manager,
);

TenantSale _sale({
  String id = 'co-1',
  String soldById = 'user-a',
  int discountMinor = 0,
  int sequence = 1,
}) => TenantSale.fromDocument(
  path: 'tenants/tenant-a/sales/$id',
  data: <String, Object?>{
    'checkoutId': id,
    'tenantId': 'tenant-a',
    'soldById': soldById,
    'payloadHash': _payloadHash,
    'payloadSchemaVersion': 2,
    'tender': 'cash',
    'currency': 'KES',
    'businessDate': _businessDate,
    'shiftId': 'shift-a',
    'deviceId': _deviceA,
    'receiptNumber': formatCheckoutReceiptNumber(
      deviceId: _deviceA,
      businessDate: _businessDate,
      sequence: sequence,
    ),
    'receiptSequence': sequence,
    'items': <Object?>[
      <String, Object?>{
        'productId': 'product-1',
        'name': 'Tusker',
        // Two categories, so a scoped valuation has one line to keep and one
        // to leave out. Nothing above reads these unless it passes a scope.
        'categoryId': 'drinks',
        'quantity': 4,
        'unitPriceMinor': 500,
        'lineTotalMinor': 2000,
      },
      <String, Object?>{
        'productId': 'product-2',
        'name': 'Water',
        'categoryId': 'food',
        'quantity': 5,
        'unitPriceMinor': 100,
        'lineTotalMinor': 500,
      },
    ],
    'subtotalMinor': 2500,
    'subtotal': 25.0,
    'discountMinor': discountMinor,
    'discount': discountMinor / 100,
    'totalMinor': 2500 - discountMinor,
    'total': (2500 - discountMinor) / 100,
    'createdAt': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 12)),
  },
);

TenantQueryDocumentSnapshot _record(
  String id, {
  required String saleId,
  required Map<String, int> quantities,
}) => TenantQueryDocumentSnapshot(
  path: 'tenants/tenant-a/returns/$id',
  data: <String, Object?>{
    'returnId': id,
    'tenantId': 'tenant-a',
    'saleId': saleId,
    'businessDate': _businessDate,
    'recordedOn': _businessDate,
    'createdBy': 'user-a',
    'status': 'pending',
    'reason': 'Damaged bottle',
    'itemsReturned': <Object?>[
      for (final entry in quantities.entries)
        <String, Object?>{'productId': entry.key, 'quantity': entry.value},
    ],
    'createdAt': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 13)),
  },
);

Matcher _code(String code) => throwsA(
  isA<TenantReturnException>().having((error) => error.code, 'code', code),
);

/// Answers the day's returns query and the sale reads that price it.
final class _Reader implements TenantDataReader {
  _Reader({required this.sales, required this.returns});

  final Map<String, TenantSale> sales;
  final List<TenantQueryDocumentSnapshot> returns;

  /// The business date each returns query asked for.
  final List<String> returnQueries = <String>[];

  /// Every sale read by exact path, in order.
  final List<String> readSales = <String>[];

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    final match = RegExp(r'^tenants/tenant-a/sales/([^/]+)$').firstMatch(path);
    if (match == null) return null;
    final id = match.group(1)!;
    readSales.add(id);
    final sale = sales[id];
    if (sale == null) return null;
    return TenantDocumentSnapshot(path: path, data: _document(sale));
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    if (query.collectionPath != 'tenants/tenant-a/returns') {
      return const <TenantQueryDocumentSnapshot>[];
    }
    returnQueries.add(query.equalityFilters['businessDate']! as String);
    final matches =
        returns
            .where(
              (snapshot) => query.equalityFilters.entries.every(
                (filter) => snapshot.data[filter.key] == filter.value,
              ),
            )
            .toList()
          // Newest document ID first, which is the order the descending page
          // proves it was given.
          ..sort((left, right) => right.path.compareTo(left.path));
    return matches.take(query.limit).toList();
  }

  /// The document a decoded sale came from, rebuilt so the loader can decode
  /// it again. Only the fields `TenantSale` reads are restated.
  Map<String, Object?> _document(TenantSale sale) => <String, Object?>{
    'checkoutId': sale.id,
    'tenantId': sale.tenantId,
    'soldById': sale.soldById,
    'payloadHash': sale.payloadHash,
    'payloadSchemaVersion': sale.schemaVersion,
    if (sale.tender case final tender?) 'tender': tender.wireValue,
    'currency': sale.currency,
    'businessDate': sale.businessDate,
    'shiftId': sale.shiftId,
    'deviceId': sale.deviceId,
    'receiptNumber': sale.receiptNumber,
    'receiptSequence': sale.receiptSequence,
    'items': <Object?>[
      for (final line in sale.lines)
        <String, Object?>{
          'productId': line.productId,
          'name': line.name,
          'quantity': line.quantity,
          'unitPriceMinor': line.unitPriceMinor,
          'lineTotalMinor': line.lineTotalMinor,
        },
    ],
    'subtotalMinor': sale.subtotalMinor,
    'subtotal': sale.subtotalMinor / 100,
    'discountMinor': sale.discountMinor,
    'discount': sale.discountMinor / 100,
    'totalMinor': sale.totalMinor,
    'total': sale.totalMinor / 100,
  };
}
