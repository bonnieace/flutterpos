/// The trading day sales are still being filed under, where that is not today.
///
/// **Why the sales report needs to ask.** A sale takes its business date from
/// its shift, not from the clock - `validSaleShift` requires the two to agree -
/// so a shift opened one evening files everything it sells after midnight under
/// the evening's date. Between midnight and
/// [TenantShiftController.tradingDayCutoff] the report's *today* is therefore a
/// day the shop is not trading in yet, and opened on it the report read empty
/// while the till was busy. This finds the day the till is really trading in.
library;

import 'dart:async';

import '../checkout/checkout_draft.dart';
import '../tenancy/tenant_paths.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_types.dart';
import 'shift_controller.dart';
import 'tenant_shift.dart';

/// The earlier business day an open shift is still selling under, and the
/// night it is part of.
///
/// **More than the date since 2026-10-12**, because the report's explanation
/// draws that night: when it began, and when it stops (see
/// `docs/design/still-trading/`). Every field is read from the same shifts the
/// date was, so asking costs nothing more.
final class TenantOpenTradingDay {
  const TenantOpenTradingDay({
    required this.businessDate,
    required this.firstOpenedAt,
    required this.sellingEndsAt,
    required this.shiftCount,
    required this.isOwn,
  });

  /// The day those shifts file their sales under.
  final String businessDate;

  /// When the first of them opened, or null where none has a server start
  /// yet - a shift opened offline and not yet confirmed.
  final DateTime? firstOpenedAt;

  /// When the last of them stops selling: [TenantShiftController.sellingEndsAt].
  final DateTime sellingEndsAt;

  /// How many shifts are still selling under [businessDate].
  final int shiftCount;

  /// Whether every one of them is the reader's own - always so for a
  /// cashier, who is only ever told about their own.
  final bool isOwn;

  /// Whether the night ends at a 24-hour cap rather than at
  /// [TenantShiftController.tradingDayCutoff].
  bool get endsAtTheCap => sellingEndsAt.isBefore(
    TenantShiftController.tradingDayEndsAt(businessDate),
  );
}

/// Reads the earliest earlier business day an open shift can still sell under.
final class TenantOpenTradingDayRepository extends TenantReadRepository {
  TenantOpenTradingDayRepository({
    required super.session,
    required super.reader,
  });

  /// The roles `firestore.rules` lets read every shift in the business. Every
  /// other member may read only their own, so is asked only about those.
  static const List<TenantRole> businessWideRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
    TenantRole.manager,
  ];

  /// More open shifts than this in one business is not a trading day this
  /// question can describe; the earliest of the ones read still stands.
  static const int scanned = 20;

  /// How long the report holds its first read for this answer. Offline,
  /// Firestore can take a while to give up on the server and answer from its
  /// cache, and a report that waited for it would be a skeleton over a day
  /// the device may well be holding.
  static const Duration patience = Duration(seconds: 4);

  /// Whether a shift dated before today could still be selling at [nowUtc]:
  /// whether yesterday's trading day has not reached its cutoff yet.
  ///
  /// **The report asks this before it reads anything.** Past the cutoff the
  /// answer to [read] is known to be null, so the report opens on today with
  /// no read and no wait - which is every hour but the first six of the day.
  static bool mayStillBeTrading(DateTime nowUtc) {
    final now = nowUtc.toUtc();
    final yesterday = checkoutBusinessDate(
      now.subtract(const Duration(days: 1)),
    );
    return now.isBefore(TenantShiftController.tradingDayEndsAt(yesterday));
  }

  /// The earliest business day before today that an open shift may still
  /// take a sale under at [nowUtc], or null where there is none.
  ///
  /// Fails with a [TimeoutException] after [patience], and with whatever the
  /// read failed with; the caller opens on today either way.
  Future<TenantOpenTradingDay?> read({
    required TenantCollectionReader collectionReader,
    required DateTime nowUtc,
  }) async {
    final now = nowUtc.toUtc();
    if (!mayStillBeTrading(now)) return null;
    final today = checkoutBusinessDate(now);
    final businessWide = session.canAccess(allowedRoles: businessWideRoles);
    final page = await readCollectionPage(
      TenantCollection.shifts,
      collectionReader: collectionReader,
      pageSize: scanned,
      equalityFilters: <String, Object?>{
        if (!businessWide) 'staffId': session.uid,
        'status': TenantShiftStatus.open.wireValue,
      },
    ).timeout(patience);
    final selling = <TenantShift>[];
    for (final item in page.items) {
      final TenantShift shift;
      try {
        shift = TenantShift.fromDocument(path: item.path, data: item.data);
      } on TenantShiftException {
        // One unreadable shift says nothing about the day the others are
        // trading in.
        continue;
      }
      if (shift.tenantId != session.tenantId || !shift.isOpen) continue;
      if (shift.businessDate.compareTo(today) >= 0) continue;
      if (!TenantShiftController.canStillSell(
        openedAt: shift.startedAt,
        businessDate: shift.businessDate,
        now: now,
      )) {
        continue;
      }
      selling.add(shift);
    }
    if (selling.isEmpty) return null;

    final day = selling
        .map((shift) => shift.businessDate)
        .reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
    final ofDay = selling.where((shift) => shift.businessDate == day).toList();
    DateTime? firstOpenedAt;
    DateTime? lastEnd;
    for (final shift in ofDay) {
      final opened = shift.startedAt;
      if (opened != null &&
          (firstOpenedAt == null || opened.isBefore(firstOpenedAt))) {
        firstOpenedAt = opened;
      }
      final ends = TenantShiftController.sellingEndsAt(
        openedAt: opened,
        businessDate: shift.businessDate,
      );
      if (lastEnd == null || ends.isAfter(lastEnd)) lastEnd = ends;
    }
    return TenantOpenTradingDay(
      businessDate: day,
      firstOpenedAt: firstOpenedAt?.toUtc(),
      sellingEndsAt: lastEnd!,
      shiftCount: ofDay.length,
      isOwn: ofDay.every((shift) => shift.staffId == session.uid),
    );
  }
}
