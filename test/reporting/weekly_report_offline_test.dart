/// What the weekly report does when the server will not answer.
///
/// **Every takings figure on that page comes from a Cloud Function, and the
/// sales those figures describe are Firestore documents already on the
/// device.** These cover the consequences of that split: a day the server
/// cannot answer must not take the page, a week only partly answered must not
/// be presented as a whole one, and a week the device can count for itself
/// should be counted rather than waited for.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/checkout/checkout_receipt.dart';
import 'package:flutter_application_1/reporting/reporting.dart';
import 'package:flutter_application_1/sales/sale_history.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a day the server cannot answer does not take the page', () async {
    final report = await _load(
      callable: _Callable.refusingDates(const <String>{'2026-08-25'}),
    );

    // Before this, one refusal threw out of the batch's `Future.wait` and the
    // whole route became "The totals could not be reached" - taking the sale
    // scan and the expense range with it, both of which had already answered.
    expect(report.recentSales, hasLength(3));
    expect(report.itemsSold, 3);
  });

  test('a week only partly answered is not presented as a whole one', () async {
    final report = await _load(
      callable: _Callable.refusingDates(const <String>{'2026-08-25'}),
    );

    // Summing the days that did land would understate the week without saying
    // so, which is the one wrong figure this page must never print.
    expect(
      report.totals,
      isNull,
      reason: 'A partial answer is no answer.',
    );
  });

  test('a week the device can count for itself is counted', () async {
    final report = await _load(callable: _Callable.refusingEverything());

    expect(report.totals, isNull);
    expect(report.counted, isNotNull);
    // Three sales at 900 minor each, which is what the fixture holds.
    expect(report.counted!.transactions, 3);
    expect(report.counted!.salesMinor, 2700);
    expect(report.hasTakings, isTrue);
    expect(report.sales, 27.0);
    expect(report.transactions, 3);
    expect(report.averageSale, 9.0);
  });

  test('the chart draws its days from the same count', () async {
    final report = await _load(callable: _Callable.refusingEverything());

    // Monday..Sunday of the week holding 2026-08-25 (a Tuesday), so the two
    // dated sales land on the second and third slots.
    expect(report.revenueByWeekday[1], 18.0);
    expect(report.revenueByWeekday[2], 9.0);
    expect(report.revenueByWeekday[4], 0.0);
  });

  test('the server replaces what the device counted', () async {
    final report = await _load(callable: _Callable.answering(1500));

    expect(report.totals, isNotNull);
    // Three days answered at 15.00 each. The device's own 27.00 is still
    // carried, and deliberately not preferred.
    expect(report.sales, 45.0);
    expect(report.counted, isNotNull);
  });

  test('a truncated scan offers no figure of its own', () async {
    // A full page with a cursor still in hand, which is the only way a scan
    // learns it saw part of a week rather than all of it.
    final report = await _load(
      callable: _Callable.refusingEverything(),
      scanCap: _scanPageSize,
      extraSales: 60,
    );

    expect(report.scanWasTruncated, isTrue);
    // Past the cap the running total is a floor, not the week's takings, and a
    // floor printed as a total is the plausible wrong figure.
    expect(report.counted, isNull);
    expect(report.hasTakings, isFalse);
  });
}

const String _tenant = 'tenant-a';
const String _uid = 'user-a';
const String _device = 'dev-0123456789abcdef0123456789abcdef';

/// The Tuesday, Wednesday and the day the clock sits on.
const List<String> _dates = <String>['2026-08-25', '2026-08-25', '2026-08-26'];

/// What `_rollUpItems` asks for per page. A scan only learns it saw part of a
/// week by getting a full page back and still holding a cursor, so a truncation
/// test needs more sales than this.
const int _scanPageSize = 50;

Future<TenantWeeklyReport> _load({
  required _Callable callable,
  int scanCap = 300,
  int extraSales = 0,
}) async {
  final session = TenantSession.active(
    uid: _uid,
    tenantId: _tenant,
    role: TenantRole.owner,
  );
  final dates = <String>[
    ..._dates,
    for (var extra = 0; extra < extraSales; extra++) '2026-08-26',
  ];
  final reader = _Reader(<Map<String, Object?>>[
    for (final (index, date) in dates.indexed)
      _sale(
        // Padded so the descending id order the repository checks for is the
        // same order the dates put them in.
        saleId: 'co-${index.toString().padLeft(3, '0')}',
        sequence: index + 1,
        businessDate: date,
      ),
  ]);
  final loader = TenantWeeklyReportLoader(
    session: session,
    callable: callable,
    sales: TenantSaleHistoryRepository(
      session: session,
      reader: reader,
      reportReader: reader,
    ),
    saleScanCap: scanCap,
    clock: () => DateTime.utc(2026, 8, 26, 12),
  );
  return loader.load(TenantReportWeek.at(DateTime.utc(2026, 8, 26, 12)));
}

/// A totals callable that can be told which business dates to refuse.
final class _Callable implements SalesTotalsCallable {
  _Callable._(this._refused, this._salesMinor, {this.refuseAll = false});

  factory _Callable.refusingDates(Set<String> dates) => _Callable._(dates, 0);
  factory _Callable.refusingEverything() =>
      _Callable._(const <String>{}, 0, refuseAll: true);
  factory _Callable.answering(int salesMinor) =>
      _Callable._(const <String>{}, salesMinor);

  final Set<String> _refused;
  final int _salesMinor;
  final bool refuseAll;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    final start = payload['previousStartDate'];
    if (refuseAll || _refused.contains(start)) {
      throw FirebaseException(plugin: 'functions', code: 'unavailable');
    }
    // The shape `TenantSalesTotals.fromCallable` insists on: a `previous`
    // block, and a scanned count the figures inside it can account for.
    return <String, Object?>{
      'scannedTransactions': 1,
      'previous': <String, Object?>{
        'sales': _salesMinor / 100,
        'profit': 0,
        'transactions': 1,
        'incompleteCostLineCount': 0,
      },
    };
  }
}

Map<String, Object?> _line() => <String, Object?>{
  'productId': 'prod-1',
  'name': 'Tusker',
  'quantity': 1,
  'unitPriceMinor': 1000,
  'unitPrice': 10.0,
  'lineTotalMinor': 1000,
  'lineTotal': 10.0,
};

Map<String, Object?> _sale({
  required String saleId,
  required int sequence,
  required String businessDate,
}) => <String, Object?>{
  'checkoutId': saleId,
  'tenantId': _tenant,
  'soldById': _uid,
  'payloadHash': 'a' * 64,
  'payloadSchemaVersion': 1,
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
  'items': <Object?>[_line()],
  'subtotalMinor': 1000,
  'subtotal': 10.0,
  'discountMinor': 100,
  'discount': 1.0,
  'totalMinor': 900,
  'total': 9.0,
  'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 26, 12)),
};

/// Answers the sale scan and nothing else, which is all this loader asks of a
/// reader once its callable has been dealt with.
///
/// **It orders and pages the way Firestore does**, because the repository
/// checks: it refuses a page that is not descending by business date and then
/// by document id, and it decides there is more to come from being handed one
/// document past the page it asked for - so truncation cannot be reached at
/// all unless this honours the limit it is given.
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
    final ordered = <Map<String, Object?>>[..._sales]
      ..sort((a, b) {
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
