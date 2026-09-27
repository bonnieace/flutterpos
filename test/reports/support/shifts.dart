/// A week of shifts, for the shifts report's tests and samples.
///
/// Shaped like a real small shop rather than like tidy test data: one cashier
/// is repeatedly short and another is once over, one shift was closed by a
/// manager holding none of its sales, one is still running, and most days have
/// a single shift. Those are the cases the report has something to say about.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uzapay_pos/reports/analysis/shifts_analysis.dart';
import 'package:uzapay_pos/reports/report_period.dart';
import 'package:uzapay_pos/shift/shift_history.dart';

const String _device = 'dev-0123456789abcdef0123456789abcdef';

/// One shift, as the server records it.
///
/// [declaredMinor] is what the cashier counted into the drawer, including the
/// float; [takingsMinor] is what the sales say it should have been. The
/// variance the report reads is `declared - float - takings`.
TenantShiftDaySlice shiftRecord({
  required String id,
  required String businessDate,
  required String staffId,
  int? takingsMinor,
  int? declaredMinor,
  int transactions = 12,
  int floatMinor = 0,
  bool open = false,
  bool closedWithoutEvidence = false,
  int startHour = 6,
  int endHour = 18,
}) {
  final data = <String, Object?>{
    'shiftId': id,
    'tenantId': 'tenant-a',
    'staffId': staffId,
    'deviceId': _device,
    'businessDate': businessDate,
    'status': open ? 'open' : 'closed',
    'startTime': Timestamp.fromDate(
      DateTime.parse('${businessDate}T00:00:00Z').add(
        Duration(hours: startHour),
      ),
    ),
    if (floatMinor > 0) 'openingFloatMinor': floatMinor,
    if (closedWithoutEvidence) 'closedWithoutEvidence': true,
  };

  if (!open) {
    data['endTime'] = Timestamp.fromDate(
      DateTime.parse('${businessDate}T00:00:00Z').add(Duration(hours: endHour)),
    );
    if (declaredMinor != null) {
      data['closingCashMinor'] = declaredMinor;
      data['closingCash'] = declaredMinor / 100;
      data['declaredCashMinor'] = declaredMinor;
      data['declaredMpesaMinor'] = 0;
      data['declaredCardMinor'] = 0;
    }
    if (takingsMinor != null) {
      data['totalSalesMinor'] = takingsMinor;
      data['totalSales'] = takingsMinor / 100;
      data['transactionCount'] = transactions;
    }
  }

  return TenantShiftDaySlice.fromDocument(
    path: 'tenants/tenant-a/shifts/$id',
    data: data,
  );
}

/// The first week of September.
TenantReportPeriod fixtureShiftsPeriod() =>
    TenantReportPeriod(startDate: '2026-09-01', endDate: '2026-09-07');

List<TenantShiftDaySlice> fixtureShifts() => <TenantShiftDaySlice>[
  // Level.
  shiftRecord(
    id: 'shift-1',
    businessDate: '2026-09-01',
    staffId: 'cashier-a',
    takingsMinor: 120000,
    declaredMinor: 120000,
  ),
  // Short by 500.
  shiftRecord(
    id: 'shift-2',
    businessDate: '2026-09-02',
    staffId: 'cashier-a',
    takingsMinor: 98000,
    declaredMinor: 97500,
  ),
  // Short by 1500 - the worst of the week.
  shiftRecord(
    id: 'shift-3',
    businessDate: '2026-09-03',
    staffId: 'cashier-a',
    takingsMinor: 110000,
    declaredMinor: 108500,
  ),
  // Over by 300, and a float that has to come back out of the comparison.
  shiftRecord(
    id: 'shift-4',
    businessDate: '2026-09-04',
    staffId: 'cashier-b',
    takingsMinor: 76000,
    declaredMinor: 81300,
    floatMinor: 5000,
  ),
  // Closed by a manager holding none of its sales: no variance at all.
  shiftRecord(
    id: 'shift-5',
    businessDate: '2026-09-05',
    staffId: 'cashier-b',
    declaredMinor: 0,
    closedWithoutEvidence: true,
  ),
  // Still running when the report was taken.
  shiftRecord(
    id: 'shift-6',
    businessDate: '2026-09-07',
    staffId: 'cashier-a',
    open: true,
  ),
];

TenantShiftsAnalysis fixtureShiftsAnalysis({
  List<TenantShiftDaySlice>? previous,
  bool truncated = false,
}) => TenantShiftsAnalysis.from(
  period: fixtureShiftsPeriod(),
  shifts: fixtureShifts(),
  previous: previous,
  truncated: truncated,
);
