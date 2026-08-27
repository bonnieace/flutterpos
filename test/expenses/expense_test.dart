/// The expense record, the range walk that reads it back, and the writer.
///
/// **The range walk is what most of this file is about.** A client repository
/// here orders only by document ID and takes only equality filters, so reading
/// "every expense between these two dates" rests entirely on the business date
/// being the leading part of the key. That is a load-bearing convention with no
/// type behind it, so the cases below pin the three places it can go wrong: the
/// opening day being skipped, the walk not stopping at the closing one, and a
/// period larger than one reading quietly returning a small total.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/expenses/expense.dart';
import 'package:flutter_application_1/expenses/expense_repository.dart';
import 'package:flutter_application_1/expenses/expense_request.dart';
import 'package:flutter_application_1/tenancy/tenant_repository.dart';
import 'package:flutter_application_1/tenancy/tenant_session.dart';
import 'package:flutter_application_1/tenancy/tenant_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the document ID carries the business date', () {
    test('an ID is the date, a dash, and the token', () {
      expect(tenantExpenseId('2026-08-27', 'Ab3xK9'), '2026-08-27-Ab3xK9');
    });

    test('the date is read back out of the key', () {
      expect(tenantExpenseIdBusinessDate('2026-08-27-Ab3xK9'), '2026-08-27');
    });

    test('a key that carries no usable date reads as none', () {
      // The walk uses this to decide it has left the period. Anything it cannot
      // read a date from must not be silently treated as in range.
      expect(tenantExpenseIdBusinessDate('expense-1'), isNull);
      expect(tenantExpenseIdBusinessDate('2026-08-27'), isNull);
      expect(tenantExpenseIdBusinessDate('2026-13-01-Ab3xK9'), isNull);
      expect(tenantExpenseIdBusinessDate('2026-08-27_Ab3xK9'), isNull);
    });

    test('a token that could break the key is refused', () {
      expect(() => tenantExpenseId('2026-08-27', ''), throwsArgumentError);
      expect(() => tenantExpenseId('2026-08-27', 'a b'), throwsArgumentError);
      expect(() => tenantExpenseId('2026-08-27', 'a/b'), throwsArgumentError);
    });

    test('a fresh token is URL-safe and usable as a key', () {
      final token = secureTenantExpenseToken();
      expect(() => tenantExpenseId('2026-08-27', token), returnsNormally);
    });
  });

  group('reading a range', () {
    test('the opening day is included, and the day before is not', () async {
      // **The case the whole cursor scheme turns on.** The walk starts after
      // the bare start date, and every ID on that day is `{date}-{token}` -
      // which sorts after the bare date because a prefix comes first. Get this
      // wrong and the first day of every period silently vanishes.
      final reader = _ExpenseReader(<String, Map<String, Object?>>{
        ..._expense(date: '2026-08-19', token: 'aaa', amountMinor: 100),
        ..._expense(date: '2026-08-20', token: 'bbb', amountMinor: 200),
        ..._expense(date: '2026-08-21', token: 'ccc', amountMinor: 300),
      });

      final period = await _repository(
        reader,
      ).readRange(startDate: '2026-08-20', endDate: '2026-08-21');

      expect(
        period.records.map((record) => record.businessDate),
        <String>['2026-08-21', '2026-08-20'],
        reason: 'Newest first, and nothing from before the opening day.',
      );
      expect(period.totalMinor, 500);
    });

    test('the walk stops at the closing day', () async {
      final reader = _ExpenseReader(<String, Map<String, Object?>>{
        ..._expense(date: '2026-08-20', token: 'aaa', amountMinor: 100),
        ..._expense(date: '2026-08-22', token: 'bbb', amountMinor: 999),
      });

      final period = await _repository(
        reader,
      ).readRange(startDate: '2026-08-20', endDate: '2026-08-21');

      expect(period.totalMinor, 100);
      expect(period.records, hasLength(1));
    });

    test('a start date with no expenses on it is a valid position', () async {
      // The cursor is a position rather than a document, so a date nothing was
      // filed under must not end the walk before it starts.
      final reader = _ExpenseReader(<String, Map<String, Object?>>{
        ..._expense(date: '2026-08-25', token: 'aaa', amountMinor: 400),
      });

      final period = await _repository(
        reader,
      ).readRange(startDate: '2026-08-20', endDate: '2026-08-27');

      expect(period.totalMinor, 400);
    });

    test(
      'a period larger than the read says so rather than under-reporting',
      () async {
        // **The failure this reports exists because of which way it is wrong.**
        // Missing expenses make net profit look *better*, so a short total is
        // worse than no total. `TenantNetProfitReport` withholds the figure when
        // this is set.
        final records = <String, Map<String, Object?>>{};
        for (var index = 0; index < 300; index++) {
          records.addAll(
            _expense(
              date: '2026-08-20',
              token: 'tok${index.toString().padLeft(4, '0')}',
              amountMinor: 100,
            ),
          );
        }
        final reader = _ExpenseReader(records);

        final period = await _repository(
          reader,
        ).readRange(startDate: '2026-08-20', endDate: '2026-08-21');

        expect(period.truncated, isTrue);
        expect(
          period.records.length,
          lessThan(300),
          reason: 'The read is bounded; the point is that it admits it.',
        );
      },
    );

    test('a period that fits is not reported as truncated', () async {
      final reader = _ExpenseReader(<String, Map<String, Object?>>{
        ..._expense(date: '2026-08-20', token: 'aaa', amountMinor: 100),
      });

      final period = await _repository(
        reader,
      ).readRange(startDate: '2026-08-20', endDate: '2026-08-21');

      expect(period.truncated, isFalse);
    });

    test('a voided record is listed and counts towards nothing', () async {
      final reader = _ExpenseReader(<String, Map<String, Object?>>{
        ..._expense(date: '2026-08-20', token: 'aaa', amountMinor: 100),
        ..._expense(
          date: '2026-08-20',
          token: 'bbb',
          amountMinor: 900,
          voided: true,
        ),
      });

      final period = await _repository(reader).readDay('2026-08-20');

      expect(period.records, hasLength(2));
      expect(period.totalMinor, 100);
    });

    test('a range that runs backwards is refused', () async {
      final repository = _repository(_ExpenseReader(const {}));
      expect(
        () => repository.readRange(
          startDate: '2026-08-21',
          endDate: '2026-08-20',
        ),
        throwsA(isA<TenantExpenseException>()),
      );
    });

    test('a document from another business is refused', () async {
      final reader = _ExpenseReader(<String, Map<String, Object?>>{
        ..._expense(date: '2026-08-20', token: 'aaa', amountMinor: 100),
      }, overrideTenantId: 'tenant-b');
      // The repository's own path proof catches it before the decoder does,
      // which is the right order: a reader answering outside this tenant is a
      // broken boundary, not a malformed record.
      expect(
        () => _repository(reader).readDay('2026-08-20'),
        throwsA(isA<TenantScopeViolation>()),
      );
    });
  });

  group('per-category totals', () {
    test('categories are ordered by what they took', () async {
      final reader = _ExpenseReader(<String, Map<String, Object?>>{
        ..._expense(
          date: '2026-08-20',
          token: 'aaa',
          amountMinor: 100,
          category: TenantExpenseCategory.transport,
        ),
        ..._expense(
          date: '2026-08-20',
          token: 'bbb',
          amountMinor: 900,
          category: TenantExpenseCategory.rent,
        ),
      });

      final period = await _repository(reader).readDay('2026-08-20');

      expect(period.spentCategories, <TenantExpenseCategory>[
        TenantExpenseCategory.rent,
        TenantExpenseCategory.transport,
      ]);
      expect(period.shareOf(TenantExpenseCategory.rent), closeTo(0.9, 1e-9));
    });

    test('a period that spent nothing has no share to state', () {
      final period = TenantExpensePeriod.empty(
        startDate: '2026-08-20',
        endDate: '2026-08-20',
      );
      // Null rather than zero, for the reason a margin on no takings is null:
      // a share of nothing is a division by zero.
      expect(period.shareOf(TenantExpenseCategory.rent), isNull);
      expect(period.spentCategories, isEmpty);
    });

    test(
      'one date can be sliced out, carrying the shortfall with it',
      () async {
        final reader = _ExpenseReader(<String, Map<String, Object?>>{
          ..._expense(date: '2026-08-20', token: 'aaa', amountMinor: 100),
          ..._expense(date: '2026-08-21', token: 'bbb', amountMinor: 700),
        });

        final period = await _repository(
          reader,
        ).readRange(startDate: '2026-08-20', endDate: '2026-08-21');

        expect(period.forDate('2026-08-21').totalMinor, 700);
        expect(period.forDate('2026-08-19').totalMinor, 0);
      },
    );
  });

  group('slicing a period for a chart', () {
    test('one category keeps the whole period as its span', () async {
      // The chart on the category route must cover the days the person chose,
      // not only the days that category happened to fall on.
      final reader = _ExpenseReader(<String, Map<String, Object?>>{
        ..._expense(date: '2026-08-20', token: 'aaa', amountMinor: 100),
        ..._expense(
          date: '2026-08-22',
          token: 'bbb',
          amountMinor: 900,
          category: TenantExpenseCategory.transport,
        ),
      });

      final period = await _repository(
        reader,
      ).readRange(startDate: '2026-08-20', endDate: '2026-08-22');
      final rent = period.forCategory(TenantExpenseCategory.rent);

      expect(rent.totalMinor, 100);
      expect(rent.startDate, '2026-08-20');
      expect(rent.endDate, '2026-08-22');
      expect(rent.businessDates, hasLength(3));
    });

    test('every day of the span is enumerated, empty ones included', () {
      // A week with one expense is six gaps and one bar. Dropping the gaps
      // would draw that single day as the whole week.
      final period = TenantExpensePeriod.empty(
        startDate: '2026-08-20',
        endDate: '2026-08-26',
      );
      expect(period.businessDates, <String>[
        '2026-08-20',
        '2026-08-21',
        '2026-08-22',
        '2026-08-23',
        '2026-08-24',
        '2026-08-25',
        '2026-08-26',
      ]);
    });

    test('a span crossing a month end is enumerated correctly', () {
      final period = TenantExpensePeriod.empty(
        startDate: '2026-08-30',
        endDate: '2026-09-02',
      );
      expect(period.businessDates, <String>[
        '2026-08-30',
        '2026-08-31',
        '2026-09-01',
        '2026-09-02',
      ]);
    });

    test('a single day is a span of one', () {
      final period = TenantExpensePeriod.empty(
        startDate: '2026-08-20',
        endDate: '2026-08-20',
      );
      expect(period.businessDates, <String>['2026-08-20']);
    });

    test('one day of the span totals only its own records', () async {
      final reader = _ExpenseReader(<String, Map<String, Object?>>{
        ..._expense(date: '2026-08-20', token: 'aaa', amountMinor: 100),
        ..._expense(date: '2026-08-20', token: 'bbb', amountMinor: 200),
        ..._expense(date: '2026-08-21', token: 'ccc', amountMinor: 900),
      });

      final period = await _repository(
        reader,
      ).readRange(startDate: '2026-08-20', endDate: '2026-08-21');

      expect(period.totalMinorOn('2026-08-20'), 300);
      expect(period.totalMinorOn('2026-08-21'), 900);
      expect(period.totalMinorOn('2026-08-19'), 0);
    });

    test('a voided record counts towards no day', () async {
      final reader = _ExpenseReader(<String, Map<String, Object?>>{
        ..._expense(
          date: '2026-08-20',
          token: 'aaa',
          amountMinor: 900,
          voided: true,
        ),
      });

      final period = await _repository(reader).readDay('2026-08-20');

      expect(period.totalMinorOn('2026-08-20'), 0);
    });

    test('a truncated period stays truncated through every slice', () async {
      // A read that stopped early may have dropped records from any day or any
      // category, so no slice of it can claim to be complete.
      final records = <String, Map<String, Object?>>{};
      for (var index = 0; index < 300; index++) {
        records.addAll(
          _expense(
            date: '2026-08-20',
            token: 'tok${index.toString().padLeft(4, '0')}',
            amountMinor: 100,
          ),
        );
      }

      final period = await _repository(
        _ExpenseReader(records),
      ).readRange(startDate: '2026-08-20', endDate: '2026-08-21');

      expect(period.truncated, isTrue);
      expect(period.forCategory(TenantExpenseCategory.rent).truncated, isTrue);
      expect(period.forDate('2026-08-20').truncated, isTrue);
    });
  });

  group('decoding refuses what it cannot trust', () {
    test('a key that disagrees with the stored date is refused', () {
      // The walk trusts the key. A record whose field said otherwise would be
      // counted into a period it does not belong to.
      expect(
        () => TenantExpense.fromDocument(
          path: 'tenants/tenant-a/expenses/2026-08-20-aaa',
          data: _expenseData(
            expenseId: '2026-08-20-aaa',
            date: '2026-08-21',
            amountMinor: 100,
          ),
        ),
        _code('expense_identity_mismatch'),
      );
    });

    test('the two halves of the amount must agree', () {
      final data = _expenseData(
        expenseId: '2026-08-20-aaa',
        date: '2026-08-20',
        amountMinor: 100,
      )..['amount'] = 9.99;
      expect(
        () => TenantExpense.fromDocument(
          path: 'tenants/tenant-a/expenses/2026-08-20-aaa',
          data: data,
        ),
        _code('inconsistent_expense_amount'),
      );
    });

    test('a category nothing recognises is refused, not folded into other', () {
      final data = _expenseData(
        expenseId: '2026-08-20-aaa',
        date: '2026-08-20',
        amountMinor: 100,
      )..['category'] = 'kickbacks';
      expect(
        () => TenantExpense.fromDocument(
          path: 'tenants/tenant-a/expenses/2026-08-20-aaa',
          data: data,
        ),
        _code('unknown_expense_category'),
      );
    });

    test('an expense of nothing is refused', () {
      final data =
          _expenseData(
              expenseId: '2026-08-20-aaa',
              date: '2026-08-20',
              amountMinor: 100,
            )
            ..['amountMinor'] = 0
            ..['amount'] = 0.0;
      expect(
        () => TenantExpense.fromDocument(
          path: 'tenants/tenant-a/expenses/2026-08-20-aaa',
          data: data,
        ),
        _code('invalid_expense_document'),
      );
    });
  });

  group('the write boundary', () {
    test('a record carries the server timestamp and no client clock', () async {
      Map<String, Object?>? written;
      final writer = FirebaseTenantExpenseWriter.forTesting(
        create: (path, data) async => written = data,
        update: (path, data) async {},
        isOnline: () async => true,
      );

      final result = await writer.recordExpense(_intent());

      expect(result.kind, TenantExpenseWriteKind.committed);
      expect(written!['createdAt'], isA<FieldValue>());
      expect(written!['recordedBy'], 'owner-a');
      expect(written!['amountMinor'], 12345);
      expect(written!['amount'], 123.45);
      expect(written!['category'], 'rent');
    });

    test('an offline device is told, and nothing is attempted', () async {
      var attempted = false;
      final writer = FirebaseTenantExpenseWriter.forTesting(
        create: (path, data) async => attempted = true,
        update: (path, data) async {},
        isOnline: () async => false,
      );

      final result = await writer.recordExpense(_intent());

      expect(result.kind, TenantExpenseWriteKind.unavailable);
      expect(attempted, isFalse);
    });

    test('a refusal the server will repeat is reported as rejected', () async {
      final writer = FirebaseTenantExpenseWriter.forTesting(
        create: (path, data) async =>
            throw FirebaseException(plugin: 'test', code: 'permission-denied'),
        update: (path, data) async {},
        isOnline: () async => true,
      );

      final result = await writer.recordExpense(_intent());

      expect(result.kind, TenantExpenseWriteKind.rejected);
      expect(result.reasonCode, 'permission-denied');
    });

    test('a timeout is ambiguous, never a failure', () async {
      // The write may well have landed. Reporting it as failed would invite a
      // second one for the same money.
      final writer = FirebaseTenantExpenseWriter.forTesting(
        create: (path, data) =>
            Future<void>.delayed(const Duration(milliseconds: 50)),
        update: (path, data) async {},
        isOnline: () async => true,
        writeTimeout: const Duration(milliseconds: 1),
      );

      final result = await writer.recordExpense(_intent());

      expect(result.kind, TenantExpenseWriteKind.ambiguous);
      expect(result.reasonCode, 'write_timeout');
    });

    test('an unrecognised code is ambiguous rather than rejected', () async {
      final writer = FirebaseTenantExpenseWriter.forTesting(
        create: (path, data) async =>
            throw FirebaseException(plugin: 'test', code: 'unavailable'),
        update: (path, data) async {},
        isOnline: () async => true,
      );

      final result = await writer.recordExpense(_intent());

      expect(result.kind, TenantExpenseWriteKind.ambiguous);
    });

    test('a void writes exactly the three keys the rule permits', () async {
      Map<String, Object?>? written;
      final writer = FirebaseTenantExpenseWriter.forTesting(
        create: (path, data) async {},
        update: (path, data) async => written = data,
        isOnline: () async => true,
      );

      final result = await writer.voidExpense(
        TenantExpenseVoidIntent(
          tenantId: 'tenant-a',
          expenseId: '2026-08-20-aaa',
          reason: 'Recorded twice.',
          voidedBy: 'owner-a',
        ),
      );

      expect(result.kind, TenantExpenseWriteKind.committed);
      expect(written!.keys.toSet(), <String>{
        'voidReason',
        'voidedBy',
        'voidedAt',
      });
      expect(written!['voidedAt'], isA<FieldValue>());
    });

    test('an intent the rules would refuse is refused before the network', () {
      expect(
        () => TenantExpenseCreateIntent(
          tenantId: 'tenant-a',
          businessDate: '2026-08-20',
          token: 'aaa',
          category: TenantExpenseCategory.rent,
          description: 'no',
          amountMinor: 100,
          recordedBy: 'owner-a',
        ),
        _code('invalid_expense_description'),
      );
      expect(
        () => TenantExpenseCreateIntent(
          tenantId: 'tenant-a',
          businessDate: '2026-08-20',
          token: 'aaa',
          category: TenantExpenseCategory.rent,
          description: 'August rent',
          amountMinor: 0,
          recordedBy: 'owner-a',
        ),
        _code('invalid_expense_amount'),
      );
    });
  });
}

Matcher _code(String code) => throwsA(
  isA<TenantExpenseException>().having((error) => error.code, 'code', code),
);

TenantExpenseCreateIntent _intent() => TenantExpenseCreateIntent(
  tenantId: 'tenant-a',
  businessDate: '2026-08-20',
  token: 'aaa',
  category: TenantExpenseCategory.rent,
  description: 'August rent',
  amountMinor: 12345,
  recordedBy: 'owner-a',
);

TenantExpenseRepository _repository(
  _ExpenseReader reader, {
  TenantRole role = TenantRole.owner,
}) => TenantExpenseRepository(
  session: TenantSession.active(
    uid: 'owner-a',
    tenantId: 'tenant-a',
    role: role,
  ),
  reader: reader,
);

Map<String, Map<String, Object?>> _expense({
  required String date,
  required String token,
  required int amountMinor,
  TenantExpenseCategory category = TenantExpenseCategory.rent,
  bool voided = false,
}) {
  final id = '$date-$token';
  return <String, Map<String, Object?>>{
    id: _expenseData(
      expenseId: id,
      date: date,
      amountMinor: amountMinor,
      category: category,
      voided: voided,
    ),
  };
}

Map<String, Object?> _expenseData({
  required String expenseId,
  required String date,
  required int amountMinor,
  TenantExpenseCategory category = TenantExpenseCategory.rent,
  bool voided = false,
}) => <String, Object?>{
  'expenseId': expenseId,
  'tenantId': 'tenant-a',
  'businessDate': date,
  'category': category.wireValue,
  'description': 'Something the business paid for',
  'amountMinor': amountMinor,
  'amount': amountMinor / 100,
  'recordedBy': 'owner-a',
  'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 20, 9)),
  if (voided) ...<String, Object?>{
    'voidedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 20, 10)),
    'voidedBy': 'owner-a',
    'voidReason': 'Recorded twice.',
  },
};

/// A reader that pages by document ID exactly as Firestore does.
///
/// **`startAfter` is a value, not a document.** The cursor skips every ID that
/// sorts at or before it, which is what makes a bare `2026-08-20` sit before
/// every `2026-08-20-…` on that day. Getting this wrong in the fake would hide
/// the very defect the range cases exist to catch.
final class _ExpenseReader implements TenantDataReader {
  _ExpenseReader(this.records, {this.overrideTenantId});

  final Map<String, Map<String, Object?>> records;

  /// Answers with documents belonging to another business.
  final String? overrideTenantId;

  final List<TenantCollectionQuery> queries = <TenantCollectionQuery>[];

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async => null;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    queries.add(query);
    final tenantId = overrideTenantId ?? 'tenant-a';
    final ids = records.keys.toList()..sort();
    final cursor = query.startAfterDocumentId;
    final page = <TenantQueryDocumentSnapshot>[];
    for (final id in ids) {
      if (cursor != null && id.compareTo(cursor) <= 0) continue;
      if (page.length >= query.limit) break;
      page.add(
        TenantQueryDocumentSnapshot(
          path: 'tenants/$tenantId/expenses/$id',
          data: <String, Object?>{
            ...records[id]!,
            if (overrideTenantId != null) 'tenantId': overrideTenantId,
          },
        ),
      );
    }
    return page;
  }
}
