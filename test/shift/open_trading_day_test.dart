import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uzapay_pos/shift/shift.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';

import '../support/shift_fakes.dart';

void main() {
  late ShiftServer server;
  late _CountingReader reader;

  setUp(() {
    server = ShiftServer();
    reader = _CountingReader(ShiftReader(server));
  });

  // 02:00 on 2026-07-31 in Nairobi: past midnight, before the 06:00 cutoff.
  final night = DateTime.utc(2026, 7, 30, 23);

  void open(
    String id, {
    required String businessDate,
    required DateTime startedAt,
    String staffId = 'user-a',
  }) {
    server.shifts['tenants/tenant-a/shifts/$id'] = shiftDocument(
      overrides: <String, Object?>{
        'shiftId': id,
        'staffId': staffId,
        'businessDate': businessDate,
        'startTime': Timestamp.fromDate(startedAt),
      },
    );
  }

  Future<TenantOpenTradingDay?> read(
    DateTime now, {
    TenantRole role = TenantRole.manager,
  }) => TenantOpenTradingDayRepository(
    session: TenantSession.active(
      uid: 'user-a',
      tenantId: 'tenant-a',
      role: role,
    ),
    reader: reader,
  ).read(collectionReader: reader, nowUtc: now);

  test('finds the earlier day a shift is still selling under', () async {
    // 18:00 on the 30th in Nairobi, eight hours ago.
    open(
      'shift-a',
      businessDate: '2026-07-30',
      startedAt: DateTime.utc(2026, 7, 30, 15),
    );

    final day = await read(night);
    expect(day?.businessDate, '2026-07-30');
    expect(day?.firstOpenedAt, DateTime.utc(2026, 7, 30, 15));
    // 06:00 on the 31st in Nairobi.
    expect(day?.sellingEndsAt, DateTime.utc(2026, 7, 31, 3));
    expect(day?.endsAtTheCap, isFalse);
    expect(day?.shiftCount, 1);
    expect(day?.isOwn, isTrue);
  });

  test(
    'several shifts make one night: the first opening, the last stop',
    () async {
      open(
        'shift-a',
        businessDate: '2026-07-30',
        startedAt: DateTime.utc(2026, 7, 30, 15),
      );
      // 17:40 on the 30th in Nairobi, a colleague's, and the first to open.
      open(
        'shift-b',
        businessDate: '2026-07-30',
        startedAt: DateTime.utc(2026, 7, 30, 14, 40),
        staffId: 'user-b',
      );

      final day = await read(night);

      expect(day?.shiftCount, 2);
      expect(day?.firstOpenedAt, DateTime.utc(2026, 7, 30, 14, 40));
      expect(day?.sellingEndsAt, DateTime.utc(2026, 7, 31, 3));
      expect(day?.isOwn, isFalse);
    },
  );

  test('a night that ends at its 24-hour cap says so', () async {
    // 02:10 on the 30th in Nairobi: 24 hours on is 02:10 on the 31st, before
    // that day's 06:00 cutoff.
    open(
      'shift-a',
      businessDate: '2026-07-30',
      startedAt: DateTime.utc(2026, 7, 29, 23, 10),
    );

    final day = await read(night);

    expect(day?.sellingEndsAt, DateTime.utc(2026, 7, 30, 23, 10));
    expect(day?.endsAtTheCap, isTrue);
  });

  test("today's shift is not an earlier day", () async {
    // 01:30 on the 31st in Nairobi: opened after midnight, so filed today.
    open(
      'shift-a',
      businessDate: '2026-07-31',
      startedAt: DateTime.utc(2026, 7, 30, 22, 30),
    );

    expect(await read(night), isNull);
  });

  test('a shift past its 24-hour cap is not trading', () async {
    // 01:00 on the 30th in Nairobi: its cap arrived an hour ago, before its
    // trading day's cutoff did.
    open(
      'shift-a',
      businessDate: '2026-07-30',
      startedAt: DateTime.utc(2026, 7, 29, 22),
    );

    expect(await read(night), isNull);
  });

  test('reads nothing once the cutoff has passed', () async {
    open(
      'shift-a',
      businessDate: '2026-07-30',
      startedAt: DateTime.utc(2026, 7, 30, 15),
    );
    // 06:00 on the 31st in Nairobi.
    final cutoff = DateTime.utc(2026, 7, 31, 3);

    expect(
      TenantOpenTradingDayRepository.mayStillBeTrading(
        cutoff.subtract(const Duration(minutes: 1)),
      ),
      isTrue,
    );
    expect(TenantOpenTradingDayRepository.mayStillBeTrading(cutoff), isFalse);
    expect(await read(cutoff), isNull);
    expect(reader.collectionQueries, isEmpty);
  });

  test('management is answered for every shift in the business', () async {
    open(
      'shift-b',
      businessDate: '2026-07-30',
      startedAt: DateTime.utc(2026, 7, 30, 15),
      staffId: 'user-b',
    );

    expect((await read(night))?.businessDate, '2026-07-30');
    expect(reader.collectionQueries.single.equalityFilters, <String, Object?>{
      'status': 'open',
    });
  });

  test('a cashier is asked only about their own shifts', () async {
    // `firestore.rules` lets a cashier read only their own, so a query that
    // could return a colleague's would be refused outright.
    open(
      'shift-b',
      businessDate: '2026-07-30',
      startedAt: DateTime.utc(2026, 7, 30, 15),
      staffId: 'user-b',
    );

    expect(await read(night, role: TenantRole.cashier), isNull);
    expect(reader.collectionQueries.single.equalityFilters, <String, Object?>{
      'staffId': 'user-a',
      'status': 'open',
    });
  });
}

final class _CountingReader implements TenantDataReader {
  _CountingReader(this._inner);

  final TenantDataReader _inner;
  final List<TenantCollectionQuery> collectionQueries =
      <TenantCollectionQuery>[];

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) =>
      _inner.getDocument(path);

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) {
    collectionQueries.add(query);
    return _inner.getCollectionPage(query);
  }
}
