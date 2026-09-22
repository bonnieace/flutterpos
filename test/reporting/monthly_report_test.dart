import 'package:flutter_application_1/reporting/reporting.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-29 09:00 UTC. The Africa/Nairobi business day is already the 29th.
final DateTime _now = DateTime.utc(2026, 8, 29, 9);

void main() {
  group('the month a report covers', () {
    test('the current month runs from its first day to today', () {
      final month = TenantReportMonth.at(_now);

      expect(month.label, 'August 2026');
      expect(month.startBusinessDate, '2026-08-01');
      expect(month.endBusinessDate, '2026-08-31');
      // Clamped: the callable refuses a future business date outright, so a
      // month in progress is asked only for the days it has.
      expect(month.endBusinessDateAt(_now), '2026-08-29');
      expect(month.isCurrent, isTrue);
    });

    test('a finished month is asked for the whole of itself', () {
      final month = TenantReportMonth.at(_now, offset: -1);

      expect(month.label, 'July 2026');
      expect(month.startBusinessDate, '2026-07-01');
      expect(month.endBusinessDateAt(_now), '2026-07-31');
      expect(month.isCurrent, isFalse);
    });

    test('paging back crosses a year without arithmetic of its own', () {
      // `DateTime.utc` normalises month 0 into December of the year before, so
      // nothing here has to know where a year ends.
      final month = TenantReportMonth.at(_now, offset: -8);

      expect(month.label, 'December 2025');
      expect(month.startBusinessDate, '2025-12-01');
      expect(month.endBusinessDate, '2025-12-31');
    });

    test('a short month ends on its own last day', () {
      expect(
        TenantReportMonth.at(_now, offset: -6).endBusinessDate,
        '2026-02-28',
      );
      // 2028 is a leap year, and day 0 of March finds the 29th without a rule
      // about leap years being written here.
      expect(
        TenantReportMonth.at(DateTime.utc(2028, 2, 15, 9)).endBusinessDate,
        '2028-02-29',
      );
    });

    test('the business day boundary decides which month a night belongs to', () {
      // 2026-07-31 22:00 UTC is 2026-08-01 01:00 in Nairobi, so a sale rung up
      // then carries an August business date and belongs to August.
      final month = TenantReportMonth.at(DateTime.utc(2026, 7, 31, 22));

      expect(month.label, 'August 2026');
    });

    test('previous and next step one month at a time', () {
      final august = TenantReportMonth.at(_now);

      expect(august.previous.label, 'July 2026');
      expect(august.previous.next, august);
      expect(august.offset, 0);
      expect(august.previous.offset, -1);
    });

    test('a month that has not begun says so', () {
      expect(TenantReportMonth.at(_now).hasBegun(_now), isTrue);
      expect(TenantReportMonth.at(_now, offset: 1).hasBegun(_now), isFalse);
    });
  });

  group('loading a month', () {
    test('asks twice: this month, and the month before', () async {
      final callable = _Callable(<Object?>[
        _response(),
        _response(sales: 4000),
      ]);
      final report = await _loader(callable).load(TenantReportMonth.at(_now));

      expect(callable.payloads, hasLength(2));
      // The month in progress, clamped to today.
      expect(callable.payloads[0]['previousStartDate'], '2026-08-01');
      expect(callable.payloads[0]['previousEndDate'], '2026-08-29');
      // The whole of the month before it.
      expect(callable.payloads[1]['previousStartDate'], '2026-07-01');
      expect(callable.payloads[1]['previousEndDate'], '2026-07-31');
      expect(report.totals, isNotNull);
      expect(report.previousTotals, isNotNull);
    });

    test('a month in progress is reported as partial', () async {
      final report = await _loader(
        _Callable(<Object?>[_response(), _response()]),
      ).load(TenantReportMonth.at(_now));

      expect(report.isPartial, isTrue);
    });

    test('a finished month is not partial', () async {
      final report = await _loader(
        _Callable(<Object?>[_response(), _response()]),
      ).load(TenantReportMonth.at(_now, offset: -1));

      expect(report.isPartial, isFalse);
    });

    test('a comparison that cannot be read is dropped, not raised', () async {
      // A missing comparison is a missing arrow beside a figure. The figure is
      // what the page is for, and losing it because last month would not read
      // would be the wrong trade.
      final callable = _Callable(<Object?>[
        _response(),
        StateError('last month is unreadable'),
      ]);
      final report = await _loader(callable).load(TenantReportMonth.at(_now));

      expect(report.totals, isNotNull);
      expect(report.previousTotals, isNull);
      expect(report.salesChange, isNull);
    });

    test('the month itself failing takes the page', () async {
      // The opposite trade, and deliberately so: the month on screen is the
      // subject, and showing nothing is honest where showing a stale or absent
      // figure would not be.
      final callable = _Callable(<Object?>[
        StateError('this month is unreadable'),
        _response(),
      ]);

      // The gateway maps a transport failure to its own typed refusal, which is
      // what the page turns into a sentence - so what escapes here is
      // `TenantSalesTotalsException`, not the raw error.
      await expectLater(
        _loader(callable).load(TenantReportMonth.at(_now)),
        throwsA(
          isA<TenantSalesTotalsException>().having(
            (error) => error.failure,
            'failure',
            TenantSalesTotalsFailure.unavailable,
          ),
        ),
      );
    });

    test('a month that has not begun asks nothing at all', () async {
      final callable = _Callable(<Object?>[_response()]);
      final report = await _loader(
        callable,
      ).load(TenantReportMonth.at(_now, offset: 1));

      expect(callable.payloads, isEmpty);
      expect(report.totals, isNull);
      expect(report.previousTotals, isNull);
    });

    test('the change is a share of the month before', () async {
      final report = await _loader(
        _Callable(<Object?>[
          _response(sales: 150, transactions: 30),
          _response(sales: 100, transactions: 40),
        ]),
      ).load(TenantReportMonth.at(_now));

      expect(report.salesChange, closeTo(50, 0.001));
      expect(report.transactionsChange, closeTo(-25, 0.001));
    });

    test('nothing taken last month is no percentage rather than infinity', () {
      // Dividing by a month that took nothing has no answer, and rendering one
      // would put an arrow on a comparison that does not exist.
      final report = TenantMonthlyReport(
        month: TenantReportMonth.at(_now),
        totals: null,
        previousTotals: null,
        isPartial: true,
      );

      expect(report.salesChange, isNull);
    });
  });
}

TenantMonthlyReportLoader _loader(_Callable callable) =>
    TenantMonthlyReportLoader(
      session: TenantSession.active(
        uid: 'user-a',
        tenantId: 'tenant-a',
        role: TenantRole.owner,
      ),
      callable: callable,
      clock: () => _now,
    );

Map<String, Object?> _response({
  double sales = 4820.75,
  int transactions = 37,
}) => <String, Object?>{
  'previous': <String, Object?>{
    'sales': sales,
    'profit': sales,
    'transactions': transactions,
    'incompleteCostLineCount': 0,
  },
  // The canonical answer always carries `net`; no returns in the
  // period means it is the gross figures again.
  'net': <String, Object?>{
    'sales': sales,
    'profit': sales,
    'transactions': transactions,
    'incompleteCostLineCount': 0,
  },
  'scannedTransactions': transactions,
};

/// Answers each call with the next outcome; an outcome that is an [Object]
/// error is thrown rather than returned.
final class _Callable implements SalesTotalsCallable {
  _Callable(this._outcomes);

  final List<Object?> _outcomes;
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];
  int _index = 0;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(payload);
    final outcome =
        _outcomes[_index < _outcomes.length ? _index++ : _outcomes.length - 1];
    if (outcome is Error) throw outcome;
    if (outcome is Exception) throw outcome;
    return outcome;
  }
}
