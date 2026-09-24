/// Staff against each other, and what a partial read is allowed to claim.
///
/// The case this file exists for is the denominator rule. The staff screen
/// deleted four counters because a figure assembled from one page was judged a
/// lie; this report reads the whole roster or quotes no share at all. Both
/// halves of that are checked here: that a complete read quotes shares, and
/// that an incomplete one still prints every ranked figure while withholding
/// every share.
library;

import 'package:flutter_application_1/reports/analysis/staff_analysis.dart';
import 'package:flutter_application_1/reports/report_period.dart';
import 'package:flutter_application_1/sales/sale_history.dart';
import 'package:flutter_application_1/tenancy/tenant_repository.dart';
import 'package:flutter_application_1/tenancy/tenant_staff_directory.dart';
import 'package:flutter_application_1/tenancy/tenant_types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sales.dart';

TenantStaffSummary _member({
  required String uid,
  String? name,
  TenantRole role = TenantRole.cashier,
  MembershipStatus status = MembershipStatus.active,
}) => TenantStaffSummary.fromSnapshot(
  TenantQueryDocumentSnapshot(
    path: 'tenants/tenant-a/staff/$uid',
    data: <String, Object?>{
      'uid': uid,
      'email': '$uid@shop.test',
      if (name != null) 'name': name,
      'role': role.name,
      'status': status.name,
      'invitationStatus': 'accepted',
    },
  ),
  ownerUid: 'u-owner',
);

TenantReportPeriod _period() =>
    TenantReportPeriod(startDate: '2026-09-09', endDate: '2026-09-15');

TenantSale _sale({
  required String id,
  required String soldById,
  required int unitPriceMinor,
  int quantity = 1,
  int? unitCostMinor,
  int discountMinor = 0,
  String businessDate = '2026-09-10',
  int sequence = 1,
}) => fixtureSale(
  id: id,
  businessDate: businessDate,
  soldById: soldById,
  sequence: sequence,
  discountMinor: discountMinor,
  lines: <Map<String, Object?>>[
    saleLine(
      productId: 'p-1',
      name: 'Thing',
      quantity: quantity,
      unitPriceMinor: unitPriceMinor,
      unitCostMinor: unitCostMinor,
    ),
  ],
);

void main() {
  group('a share of an unknown whole is not a measurement', () {
    test('a complete read quotes shares', () {
      final analysis = TenantStaffAnalysis.from(
        period: _period(),
        roster: <TenantStaffSummary>[
          _member(uid: 'u-a', name: 'Grace'),
          _member(uid: 'u-b', name: 'Peter'),
        ],
        sales: <TenantSale>[
          _sale(id: 'co-1', soldById: 'u-a', unitPriceMinor: 75000),
          _sale(
            id: 'co-2',
            soldById: 'u-b',
            unitPriceMinor: 25000,
            sequence: 2,
          ),
        ],
      );

      expect(analysis.isComplete, isTrue);
      expect(analysis.concentration, 0.75);
      expect(analysis.headCountFor(0.75), 1);
      expect(analysis.shareOf(analysis.trading.first), 0.75);
    });

    test('an incomplete read withholds every share', () {
      final analysis = TenantStaffAnalysis.from(
        period: _period(),
        roster: <TenantStaffSummary>[_member(uid: 'u-a', name: 'Grace')],
        sales: <TenantSale>[
          _sale(id: 'co-1', soldById: 'u-a', unitPriceMinor: 75000),
        ],
        isComplete: false,
      );

      expect(
        analysis.concentration,
        isNull,
        reason:
            'The staff screen removed four counters over precisely this. A '
            'share of a roster that was not fully read is not a measurement.',
      );
      expect(analysis.headCountFor(0.75), isNull);
      expect(analysis.shareOf(analysis.trading.first), isNull);
    });

    test('but an incomplete read still ranks exactly', () {
      final analysis = TenantStaffAnalysis.from(
        period: _period(),
        roster: <TenantStaffSummary>[
          _member(uid: 'u-a', name: 'Grace'),
          _member(uid: 'u-b', name: 'Peter'),
        ],
        sales: <TenantSale>[
          _sale(id: 'co-1', soldById: 'u-a', unitPriceMinor: 30000),
          _sale(
            id: 'co-2',
            soldById: 'u-b',
            unitPriceMinor: 90000,
            sequence: 2,
          ),
        ],
        isComplete: false,
      );

      expect(
        analysis.trading.first.name,
        'Peter',
        reason:
            'What each named person took is exact whatever the walk reached. '
            'Only the share of the whole is unknowable.',
      );
      expect(analysis.trading.first.revenueMinor, 90000);
    });
  });

  group('the comparisons the report is for', () {
    test('the middle sale is a median, not a mean of means', () {
      final analysis = TenantStaffAnalysis.from(
        period: _period(),
        roster: <TenantStaffSummary>[
          _member(uid: 'u-a'),
          _member(uid: 'u-b'),
          _member(uid: 'u-c'),
        ],
        sales: <TenantSale>[
          _sale(id: 'co-1', soldById: 'u-a', unitPriceMinor: 1000),
          _sale(
            id: 'co-2',
            soldById: 'u-b',
            unitPriceMinor: 3000,
            sequence: 2,
          ),
          // One extraordinary fortnight, which a mean would let move the line
          // everybody else is read against.
          _sale(
            id: 'co-3',
            soldById: 'u-c',
            unitPriceMinor: 500000,
            sequence: 3,
          ),
        ],
      );

      expect(
        analysis.medianAverageSaleMinor,
        3000,
        reason:
            'The middle of 1000, 3000, 500000. A mean would be 168,000 and '
            'would put two of the three people below the line.',
      );
    });

    test('a rank that moved is reported', () {
      final analysis = TenantStaffAnalysis.from(
        period: _period(),
        roster: <TenantStaffSummary>[
          _member(uid: 'u-a', name: 'Grace'),
          _member(uid: 'u-b', name: 'Peter'),
        ],
        sales: <TenantSale>[
          _sale(id: 'co-1', soldById: 'u-a', unitPriceMinor: 90000),
          _sale(
            id: 'co-2',
            soldById: 'u-b',
            unitPriceMinor: 30000,
            sequence: 2,
          ),
        ],
        previous: <TenantSale>[
          _sale(
            id: 'co-p1',
            soldById: 'u-b',
            unitPriceMinor: 90000,
            businessDate: '2026-09-02',
            sequence: 3,
          ),
          _sale(
            id: 'co-p2',
            soldById: 'u-a',
            unitPriceMinor: 30000,
            businessDate: '2026-09-02',
            sequence: 4,
          ),
        ],
      );

      final grace = analysis.trading.firstWhere((p) => p.name == 'Grace');

      expect(
        analysis.rankChangeOf(grace),
        1,
        reason:
            'Second to first. A rank that moved survives a shop whose takings '
            'went up or down as a whole, which a bare figure does not.',
      );
    });

    test('somebody not ranked before has no rank change to claim', () {
      final analysis = TenantStaffAnalysis.from(
        period: _period(),
        roster: <TenantStaffSummary>[_member(uid: 'u-a', name: 'Grace')],
        sales: <TenantSale>[
          _sale(id: 'co-1', soldById: 'u-a', unitPriceMinor: 90000),
        ],
      );

      expect(
        analysis.rankChangeOf(analysis.trading.first),
        isNull,
        reason: 'A new starter did not climb from anywhere.',
      );
    });

    test('takings per day worked is the fairer comparison', () {
      final analysis = TenantStaffAnalysis.from(
        period: _period(),
        roster: <TenantStaffSummary>[
          _member(uid: 'u-a', name: 'Full time'),
          _member(uid: 'u-b', name: 'Two shifts'),
        ],
        sales: <TenantSale>[
          for (final (index, date) in <String>[
            '2026-09-09',
            '2026-09-10',
            '2026-09-11',
            '2026-09-12',
          ].indexed)
            _sale(
              id: 'co-a$index',
              soldById: 'u-a',
              unitPriceMinor: 20000,
              businessDate: date,
              sequence: index + 1,
            ),
          for (final (index, date) in <String>[
            '2026-09-09',
            '2026-09-10',
          ].indexed)
            _sale(
              id: 'co-b$index',
              soldById: 'u-b',
              unitPriceMinor: 30000,
              businessDate: date,
              sequence: index + 10,
            ),
        ],
      );

      final full = analysis.people.firstWhere((p) => p.name == 'Full time');
      final part = analysis.people.firstWhere((p) => p.name == 'Two shifts');

      expect(full.revenueMinor, 80000);
      expect(part.revenueMinor, 60000);
      expect(full.daysTraded, 4);
      expect(part.daysTraded, 2);
      expect(
        part.revenuePerDayMinor,
        greaterThan(full.revenuePerDayMinor),
        reason:
            'The part-timer takes less in total and more per day worked, '
            'which is the honest way to read two people on different hours.',
      );
    });
  });

  group('who is counted', () {
    test('somebody on the roster who sold nothing still gets a row', () {
      final analysis = TenantStaffAnalysis.from(
        period: _period(),
        roster: <TenantStaffSummary>[
          _member(uid: 'u-a', name: 'Grace'),
          _member(uid: 'u-idle', name: 'Joseph'),
        ],
        sales: <TenantSale>[
          _sale(id: 'co-1', soldById: 'u-a', unitPriceMinor: 90000),
        ],
      );

      expect(analysis.people.length, 2);
      expect(analysis.idle.single.name, 'Joseph');
      expect(
        analysis.trading.length,
        1,
        reason:
            'A cashier with no sales for a fortnight is either not working or '
            'not using the till. Both are findings, so the row stays.',
      );
    });

    test('a sale by somebody off the roster is kept, not dropped', () {
      final analysis = TenantStaffAnalysis.from(
        period: _period(),
        roster: <TenantStaffSummary>[_member(uid: 'u-a', name: 'Grace')],
        sales: <TenantSale>[
          _sale(id: 'co-1', soldById: 'u-a', unitPriceMinor: 60000),
          _sale(
            id: 'co-2',
            soldById: 'u-gone',
            unitPriceMinor: 40000,
            sequence: 2,
          ),
        ],
      );

      expect(
        analysis.revenueMinor,
        100000,
        reason:
            'The sale happened and the money is the shop\'s. Dropping it '
            'would make the staff report disagree with the sales report.',
      );
      expect(
        analysis.people.map((p) => p.name),
        contains('No longer on the roster'),
      );
    });
  });

  group('margin and discounts per person', () {
    test('a person whose lines record no cost carries no margin', () {
      final analysis = TenantStaffAnalysis.from(
        period: _period(),
        roster: <TenantStaffSummary>[_member(uid: 'u-a', name: 'Grace')],
        sales: <TenantSale>[
          _sale(id: 'co-1', soldById: 'u-a', unitPriceMinor: 90000),
        ],
      );

      expect(
        analysis.people.single.marginMinor,
        isNull,
        reason:
            'On a page comparing people this matters twice over: it would '
            'rank whoever sells the least well-recorded stock highest.',
      );
    });

    test('a discount rate is of what would otherwise have been taken', () {
      final analysis = TenantStaffAnalysis.from(
        period: _period(),
        roster: <TenantStaffSummary>[_member(uid: 'u-a', name: 'Grace')],
        sales: <TenantSale>[
          _sale(
            id: 'co-1',
            soldById: 'u-a',
            unitPriceMinor: 10000,
            discountMinor: 2000,
          ),
        ],
      );

      expect(analysis.people.single.revenueMinor, 8000);
      expect(
        analysis.people.single.discountRate,
        closeTo(0.2, 0.0001),
        reason: '2000 off a 10,000 subtotal, not off the 8000 taken.',
      );
    });

    test('an outlier needs a shop to stand out from', () {
      final analysis = TenantStaffAnalysis.from(
        period: _period(),
        roster: <TenantStaffSummary>[
          _member(uid: 'u-a'),
          _member(uid: 'u-b'),
        ],
        sales: <TenantSale>[
          _sale(
            id: 'co-1',
            soldById: 'u-a',
            unitPriceMinor: 10000,
            discountMinor: 5000,
          ),
          _sale(
            id: 'co-2',
            soldById: 'u-b',
            unitPriceMinor: 10000,
            sequence: 2,
          ),
        ],
      );

      expect(
        analysis.discountOutlier,
        isNull,
        reason:
            'Two people is not a distribution. Naming one of them an outlier '
            'would be an accusation dressed as arithmetic.',
      );
    });
  });
}
