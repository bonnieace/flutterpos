/// A roster and a fortnight of trading, for the staff report.
///
/// Shaped so the comparisons have something to say: one person well ahead, one
/// who climbed the order, one on far fewer shifts who takes more per day than
/// the person above them, one who gives away noticeably more in discounts, and
/// one on the roster who rang nothing up at all.
library;

import 'package:flutter_application_1/reports/analysis/staff_analysis.dart';
import 'package:flutter_application_1/reports/report_period.dart';
import 'package:flutter_application_1/sales/sale_history.dart';
import 'package:flutter_application_1/tenancy/tenant_repository.dart';
import 'package:flutter_application_1/tenancy/tenant_staff_directory.dart';
import 'package:flutter_application_1/tenancy/tenant_types.dart';

import 'sales.dart';

TenantStaffSummary staffMember({
  required String uid,
  required String name,
  TenantRole role = TenantRole.cashier,
}) => TenantStaffSummary.fromSnapshot(
  TenantQueryDocumentSnapshot(
    path: 'tenants/tenant-a/staff/$uid',
    data: <String, Object?>{
      'uid': uid,
      'email': '$uid@shop.test',
      'name': name,
      'role': role.name,
      'status': 'active',
      'invitationStatus': 'accepted',
    },
  ),
  ownerUid: 'u-grace',
);

TenantStaffAnalysis fixtureStaffAnalysis() {
  final period = TenantReportPeriod(
    startDate: '2026-09-09',
    endDate: '2026-09-22',
  );

  final roster = <TenantStaffSummary>[
    staffMember(uid: 'u-grace', name: 'Grace Wanjiru', role: TenantRole.owner),
    staffMember(uid: 'u-peter', name: 'Peter Otieno'),
    staffMember(uid: 'u-amina', name: 'Amina Hassan'),
    staffMember(uid: 'u-joseph', name: 'Joseph Kamau', role: TenantRole.manager),
    // On the roster, rang nothing up. A finding, so it gets a row.
    staffMember(uid: 'u-mary', name: 'Mary Achieng'),
  ];

  final sales = <TenantSale>[];
  var sequence = 0;

  TenantSale sale({
    required String uid,
    required String date,
    required int unitPriceMinor,
    int quantity = 1,
    int? unitCostMinor = 24000,
    int discountMinor = 0,
  }) {
    sequence++;
    return fixtureSale(
      id: 'co-$uid-$date-$sequence',
      businessDate: date,
      soldById: uid,
      sequence: sequence,
      discountMinor: discountMinor,
      lines: <Map<String, Object?>>[
        saleLine(
          productId: 'p-1',
          name: 'Sugar 2kg',
          quantity: quantity,
          unitPriceMinor: unitPriceMinor,
          unitCostMinor: unitCostMinor,
        ),
      ],
    );
  }

  final dates = period.businessDates;
  for (final (index, date) in dates.indexed) {
    // Grace works every day and takes the most overall.
    sales.add(sale(uid: 'u-grace', date: date, unitPriceMinor: 32000, quantity: 2));
    if (index.isEven) {
      sales.add(
        sale(uid: 'u-grace', date: date, unitPriceMinor: 28000, quantity: 2),
      );
    }

    // Peter is on most days and is second overall, but climbed the order.
    if (index % 3 != 2) {
      sales.add(
        sale(uid: 'u-peter', date: date, unitPriceMinor: 41000, quantity: 2),
      );
    }

    // Amina is on four shifts only, and takes more per day worked than Peter.
    if (index % 4 == 0) {
      sales.add(
        sale(uid: 'u-amina', date: date, unitPriceMinor: 88000, quantity: 3),
      );
    }

    // Joseph discounts heavily, which is a question rather than a fault.
    if (index % 2 == 1) {
      sales.add(
        sale(
          uid: 'u-joseph',
          date: date,
          unitPriceMinor: 30000,
          quantity: 2,
          discountMinor: 9000,
        ),
      );
    }
  }

  // The period before: Peter led it, so this period shows him overtaken.
  final earlier = period.precedingComparable;
  final previous = <TenantSale>[
    for (final (index, date) in earlier.businessDates.indexed) ...<TenantSale>[
      sale(uid: 'u-peter', date: date, unitPriceMinor: 52000, quantity: 2),
      if (index.isEven)
        sale(uid: 'u-grace', date: date, unitPriceMinor: 30000, quantity: 2),
      if (index % 4 == 0)
        sale(uid: 'u-amina', date: date, unitPriceMinor: 40000, quantity: 2),
    ],
  ];

  return TenantStaffAnalysis.from(
    period: period,
    roster: roster,
    sales: sales,
    previous: previous,
    documentsRead: roster.length + sales.length + previous.length,
  );
}
