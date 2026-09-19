/// What the weekly report's filters actually reach, and what they compare to.
///
/// **Three defects with one shape.** The week's totals and its revenue chart
/// honoured the staff and category filters; three other things on the same
/// page did not. The net-profit card subtracted the whole business's spending
/// from one colleague's takings. The item roll-up behind *Top selling items*,
/// *Items sold* and *Recent transactions* was never handed the category at
/// all. And the comparison beside every figure read a whole previous week
/// against a current week that had only partly happened.
///
/// None of them corrupted a stored record, which is why none was caught: every
/// one is a figure that is honestly computed from the wrong question.
///
/// Kept apart from `weekly_report_test.dart`, which tests the week arithmetic
/// and the report's own getters with no loader, no reader and no callable.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/checkout/checkout_receipt.dart';
import 'package:flutter_application_1/expenses/expense_repository.dart';
import 'package:flutter_application_1/reporting/reporting.dart';
import 'package:flutter_application_1/sales/sale_history.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wednesday, so the current week holds three elapsed days of seven.
final DateTime _now = DateTime.utc(2026, 8, 26, 12);

const String _tenant = 'tenant-a';
const String _uid = 'user-a';
const String _device = 'dev-0123456789abcdef0123456789abcdef';

void main() {
  group('a filtered week reads no expenses', () {
    test('an unfiltered week composes a net figure', () async {
      final report = await _load();

      expect(report.expenses, isNotNull);
      expect(
        report.netProfitReport,
        isNotNull,
        reason: 'The whole business over the whole week is what net means.',
      );
    });

    test('a week filtered to one colleague composes none', () async {
      // An expense belongs to the business and to a date. It belongs to no
      // colleague, so there is no allocation that makes the shop's rent part
      // of one cashier's net profit - and a card labelled NET PROFIT that
      // subtracts it anyway is a number nobody can act on.
      final report = await _load(soldById: _uid);

      expect(report.expenses, isNull);
      expect(report.netProfitReport, isNull);
    });

    test('a week filtered to one category composes none', () async {
      final report = await _load(categoryId: 'drinks');

      expect(report.expenses, isNull);
      expect(report.netProfitReport, isNull);
    });
  });

  group('the category filter reaches the item roll-up', () {
    test('an unfiltered week rolls up every line', () async {
      final report = await _load();

      // 1 beer + 2 bread + 1 beer, and the mixed receipt's two.
      expect(report.itemsSold, 6);
      expect(report.recentSales, hasLength(4));
      expect(
        report.topItems.map((item) => item.productId),
        containsAll(<String>['beer', 'bread']),
      );
    });

    test('a category keeps only the lines in it', () async {
      final report = await _load(categoryId: 'drinks');

      // Three drinks lines over three sales - one of them a receipt that also
      // held food. The food-only sale contributes nothing.
      expect(report.itemsSold, 3);
      expect(
        report.topItems.map((item) => item.productId),
        <String>['beer'],
        reason: 'A product outside the category is not a top seller in it.',
      );
    });

    test('a sale holding nothing in the category is left out entirely', () async {
      final report = await _load(categoryId: 'drinks');

      expect(
        report.recentSales.map((row) => row.sale.id),
        isNot(contains('co-002')),
        reason:
            'The food-only sale did not happen as far as drinks is concerned - '
            'the same rule `saleContribution` applies on the server.',
      );
      expect(report.recentSales, hasLength(3));
    });

    test('a mixed receipt is listed by its lines in the category', () async {
      // **The row used to describe the whole receipt.** It printed whichever
      // line the till wrote first - here the food one - a count including the
      // food line, and the whole-sale total. Under a drinks heading that named
      // another category's product and an amount the drinks figures above it
      // had never counted, so the rows did not add up to their own total.
      final report = await _load(categoryId: 'drinks');
      final mixed = report.recentSales.firstWhere(
        (row) => row.sale.id == 'co-004',
      );

      expect(mixed.sale.totalMinor, 2000, reason: 'the receipt is unchanged');
      expect(
        mixed.lines.map((line) => line.productId),
        <String>['beer'],
        reason: 'the food line is not part of this listing',
      );
      expect(
        mixed.totalMinor,
        1000,
        reason: 'the row states the money this category was credited with',
      );
    });

    test('an unfiltered receipt is still listed whole', () async {
      final report = await _load();
      final mixed = report.recentSales.firstWhere(
        (row) => row.sale.id == 'co-004',
      );

      expect(mixed.lines, hasLength(2));
      // The sale's own total, so a whole-sale discount is still reflected
      // rather than recomputed from the lines.
      expect(mixed.totalMinor, 2000);
    });
  });

  group('the comparison covers the same span as the week it is beside', () {
    test('a running week is compared against its own elapsed days', () async {
      final callable = _Callable();
      await _load(callable: callable);

      // Monday the 17th to Wednesday the 19th: the same three weekdays the
      // current week has had. Before this it asked to the 23rd, so a Wednesday
      // was held against a full Monday-to-Sunday and read as a collapse.
      expect(
        callable.rangeFor('2026-08-17'),
        '2026-08-19',
      );
    });

    test('a finished week is still compared whole against whole', () async {
      final callable = _Callable();
      await _load(callable: callable, weekOffset: -1);

      // Nothing partial about either side, so nothing to clamp.
      expect(callable.rangeFor('2026-08-10'), '2026-08-16');
    });
  });
}

Future<TenantWeeklyReport> _load({
  _Callable? callable,
  String? soldById,
  String? categoryId,
  int weekOffset = 0,
}) async {
  final session = TenantSession.active(
    uid: _uid,
    tenantId: _tenant,
    role: TenantRole.owner,
  );
  final reader = _Reader(<Map<String, Object?>>[
    // Two drinks lines across two sales, one food-only sale between them.
    _sale(saleId: 'co-001', sequence: 1, businessDate: '2026-08-25', lines: <Map<String, Object?>>[_line(productId: 'beer', categoryId: 'drinks')]),
    _sale(saleId: 'co-002', sequence: 2, businessDate: '2026-08-25', lines: <Map<String, Object?>>[_line(productId: 'bread', categoryId: 'food', quantity: 2)]),
    _sale(saleId: 'co-003', sequence: 3, businessDate: '2026-08-26', lines: <Map<String, Object?>>[_line(productId: 'beer', categoryId: 'drinks')]),
    // **One receipt holding both categories.** This is the case the first pass
    // at this page never built, and the one the row rendering got wrong.
    _sale(saleId: 'co-004', sequence: 4, businessDate: '2026-08-26', lines: <Map<String, Object?>>[
      _line(productId: 'bread', categoryId: 'food'),
      _line(productId: 'beer', categoryId: 'drinks'),
    ]),
  ]);
  final loader = TenantWeeklyReportLoader(
    session: session,
    callable: callable ?? _Callable(),
    sales: TenantSaleHistoryRepository(
      session: session,
      reader: reader,
      reportReader: reader,
    ),
    expenses: TenantExpenseRepository(session: session, reader: reader),
    clock: () => _now,
  );
  return loader.load(
    TenantReportWeek.at(_now, offset: weekOffset),
    soldById: soldById,
    categoryId: categoryId,
  );
}

/// Answers every range, and remembers which ranges it was asked for.
final class _Callable implements SalesTotalsCallable {
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];

  /// The end date the one call starting on [start] asked for.
  String? rangeFor(String start) {
    for (final payload in payloads) {
      if (payload['previousStartDate'] == start) {
        return payload['previousEndDate'] as String?;
      }
    }
    return null;
  }

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(payload);
    return <String, Object?>{
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

/// Pages the sale scan the way Firestore does, and answers every other read
/// empty - which is what an expense range with nothing recorded looks like.
final class _Reader implements TenantDataReader, TenantSalesHistoryQueryReader {
  _Reader(this._sales);

  final List<Map<String, Object?>> _sales;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async => null;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async => const <TenantQueryDocumentSnapshot>[];

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
