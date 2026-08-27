import '../checkout/checkout_outbox.dart';
import '../checkout/checkout_tender.dart';
import '../tenancy/tenant_id.dart';

/// Raised when local sale evidence cannot be summarized for a shift.
final class ShiftSalesLedgerException implements Exception {
  const ShiftSalesLedgerException(this.code);

  final String code;

  @override
  String toString() => 'ShiftSalesLedgerException($code)';
}

/// The largest shift total this device will ever claim, in minor units.
const int maximumShiftSalesMinor = 1000000000000;

/// One bucket of a shift's confirmed takings: what was taken, over how many
/// sales.
final class ShiftTenderTotals {
  const ShiftTenderTotals({
    required this.totalMinor,
    required this.transactionCount,
  });

  static const ShiftTenderTotals empty = ShiftTenderTotals(
    totalMinor: 0,
    transactionCount: 0,
  );

  final int totalMinor;
  final int transactionCount;

  bool get isEmpty => transactionCount == 0;
}

/// How one shift's confirmed takings split across how they were paid for.
///
/// Only the cash bucket answers the question a cashier actually asks while
/// counting a drawer, but every bucket is carried anyway: without them the
/// split cannot be shown to sum to the shift total, and an expected-cash figure
/// nothing can check is a claim rather than evidence. Because all buckets are
/// filled in the same pass from the same validated `totalMinor`, they sum to
/// [ShiftSalesSummary.totalMinor] by construction rather than by agreement.
///
/// The bucketing rule is deliberately identical to the server's
/// `saleTenderBucket`: absent or null is [unrecorded], one of the three exact
/// wire values is [recorded], and anything else is [unrecognised]. The same
/// sale must land in the same bucket whether it is counted at the till or
/// reported over a period, so the rule is stated once and copied, never
/// re-derived.
final class ShiftTenderSplit {
  const ShiftTenderSplit({
    this.recorded = const <CheckoutTender, ShiftTenderTotals>{},
    this.unrecorded = ShiftTenderTotals.empty,
    this.unrecognised = ShiftTenderTotals.empty,
  });

  static const ShiftTenderSplit empty = ShiftTenderSplit();

  /// What each modelled payment method took.
  ///
  /// The ledger always writes all three, including the ones that took nothing,
  /// but a missing entry simply means nothing was taken that way: [bucket]
  /// answers for every method rather than only the ones present, so a partial
  /// map cannot turn an empty bucket into a crash on the one screen a cashier
  /// uses to close a till.
  final Map<CheckoutTender, ShiftTenderTotals> recorded;

  /// Sales recorded before payment methods were captured at all.
  ///
  /// A statement about the record rather than about the payment: these are
  /// schema v1 sales, and they are never presented as unpaid.
  final ShiftTenderTotals unrecorded;

  /// Sales naming a payment method this app does not model.
  ///
  /// Kept apart from [unrecorded] because it is a different fact: something
  /// wrote a value nothing here recognises, which is a device defect rather
  /// than history. Their money stays inside the shift total either way.
  final ShiftTenderTotals unrecognised;

  /// This method's takings, whether or not [recorded] carries an entry for it.
  ShiftTenderTotals bucket(CheckoutTender tender) =>
      recorded[tender] ?? ShiftTenderTotals.empty;

  /// What the drawer should hold, if every cash sale was rung up as one.
  ShiftTenderTotals get cash => bucket(CheckoutTender.cash);

  bool get hasRecordedTenders =>
      recorded.values.any((totals) => !totals.isEmpty);

  /// Everything in every bucket, which is what the split claims to describe.
  int get totalMinor =>
      recorded.values.fold(0, (sum, totals) => sum + totals.totalMinor) +
      unrecorded.totalMinor +
      unrecognised.totalMinor;

  int get transactionCount =>
      recorded.values.fold(0, (sum, totals) => sum + totals.transactionCount) +
      unrecorded.transactionCount +
      unrecognised.transactionCount;

  /// Confirmed takings this device cannot attribute to a payment method.
  ///
  /// They are neither claimed as cash nor claimed as anything else, so the
  /// surface states them rather than letting an expected-cash figure quietly
  /// exclude money without saying so.
  ShiftTenderTotals get unattributed => ShiftTenderTotals(
    totalMinor: unrecorded.totalMinor + unrecognised.totalMinor,
    transactionCount:
        unrecorded.transactionCount + unrecognised.transactionCount,
  );
}

/// What this device can prove about the sales recorded during one shift.
///
/// [transactionCount] and [totalMinor] cover only sales the server has already
/// acknowledged, because those are exactly the sales nightly reconciliation
/// will aggregate. [unsettledCount] is every local sale for the shift that is
/// not yet confirmed; while it is non-zero the device cannot describe the shift
/// completely and must not write a closing summary.
final class ShiftSalesSummary {
  const ShiftSalesSummary({
    required this.transactionCount,
    required this.totalMinor,
    required this.unsettledCount,
    this.tenders = ShiftTenderSplit.empty,
  });

  static const ShiftSalesSummary empty = ShiftSalesSummary(
    transactionCount: 0,
    totalMinor: 0,
    unsettledCount: 0,
  );

  final int transactionCount;
  final int totalMinor;
  final int unsettledCount;

  /// How the confirmed takings above split across how they were paid for.
  ///
  /// It describes exactly the sales [totalMinor] covers, so an unsettled shift
  /// has an incomplete split for the same reason it has an incomplete total.
  final ShiftTenderSplit tenders;

  /// The major-unit mirror reconciliation compares against `totalSales`.
  double get totalSales => totalMinor / 100;

  bool get isComplete => unsettledCount == 0;

  /// Whether [tenders] describes exactly the takings this summary reports.
  ///
  /// The ledger fills the buckets in the same pass as the total, so what it
  /// builds always adds up. This is what every *other* source of a split has to
  /// satisfy before a surface may show one: a breakdown that does not sum to
  /// the shift total is not a smaller version of the truth, it is a different
  /// figure wearing the same label - and the label it would wear is the one a
  /// drawer is counted against.
  bool get tendersDescribeTakings =>
      tenders.totalMinor == totalMinor &&
      tenders.transactionCount == transactionCount;
}

/// The narrow boundary the shift lifecycle uses to summarize its own sales.
abstract interface class ShiftSalesLedger {
  Future<ShiftSalesSummary> summarize({
    required String uid,
    required String tenantId,
    required String shiftId,
  });
}

/// Summarizes one shift from the encrypted local checkout outbox.
///
/// The outbox is the only local record of what this device sold, and a
/// confirmed record means an exact server sale carries the same payload hash.
/// Malformed evidence raises rather than being skipped: a silently dropped sale
/// would understate the shift total and turn a device defect into a permanent
/// reconciliation variance.
final class CheckoutOutboxShiftSalesLedger implements ShiftSalesLedger {
  const CheckoutOutboxShiftSalesLedger(this._outbox);

  final HiveCheckoutOutbox _outbox;

  @override
  Future<ShiftSalesSummary> summarize({
    required String uid,
    required String tenantId,
    required String shiftId,
  }) async {
    final safeShiftId = validateTenantDocumentId(shiftId, fieldName: 'shiftId');
    final records = await _outbox.recordsForSession(
      uid: uid,
      tenantId: tenantId,
    );
    var transactionCount = 0;
    var totalMinor = 0;
    var unsettledCount = 0;
    final split = _ShiftTenderSplitBuilder();
    for (final record in records) {
      final recordShiftId = record.payload['shiftId'];
      if (recordShiftId is! String || recordShiftId.isEmpty) {
        throw const ShiftSalesLedgerException('unattributed_local_sale');
      }
      if (recordShiftId != safeShiftId) continue;
      if (record.state != CheckoutOutboxState.confirmed) {
        unsettledCount += 1;
        continue;
      }
      final total = record.payload['totalMinor'];
      if (total is! int || total < 0 || total > maximumShiftSalesMinor) {
        throw const ShiftSalesLedgerException('malformed_local_sale');
      }
      totalMinor += total;
      transactionCount += 1;
      // Deliberately the same validated `total` the shift total was just
      // grown by, and deliberately in the same iteration: that is what makes
      // the buckets sum to it rather than merely agree with it.
      //
      // An unmodelled tender does not fail the close. The money is known and
      // the total is right; refusing here would strand a cashier at the end of
      // a shift over a value they never chose. It is bucketed and stated
      // instead - the same decision the period report already makes.
      split.add(record.payload['tender'], total);
      if (totalMinor > maximumShiftSalesMinor) {
        throw const ShiftSalesLedgerException('shift_total_out_of_range');
      }
    }
    return ShiftSalesSummary(
      transactionCount: transactionCount,
      totalMinor: totalMinor,
      unsettledCount: unsettledCount,
      tenders: split.build(),
    );
  }
}

/// Accumulates one shift's buckets in a single pass over its confirmed sales.
final class _ShiftTenderSplitBuilder {
  final Map<CheckoutTender, int> _recordedMinor = <CheckoutTender, int>{
    for (final tender in CheckoutTender.values) tender: 0,
  };
  final Map<CheckoutTender, int> _recordedCount = <CheckoutTender, int>{
    for (final tender in CheckoutTender.values) tender: 0,
  };
  int _unrecordedMinor = 0;
  int _unrecordedCount = 0;
  int _unrecognisedMinor = 0;
  int _unrecognisedCount = 0;

  /// Buckets one confirmed sale exactly as the server's `saleTenderBucket`
  /// does. An absent key and a stored `null` are the same fact - a sale written
  /// before payment methods existed - so both reach [ShiftTenderSplit
  /// .unrecorded] through the one `null` this lookup returns for either.
  void add(Object? storedTender, int totalMinor) {
    if (storedTender == null) {
      _unrecordedMinor += totalMinor;
      _unrecordedCount += 1;
      return;
    }
    final tender = CheckoutTender.tryParse(storedTender);
    if (tender == null) {
      _unrecognisedMinor += totalMinor;
      _unrecognisedCount += 1;
      return;
    }
    _recordedMinor[tender] = _recordedMinor[tender]! + totalMinor;
    _recordedCount[tender] = _recordedCount[tender]! + 1;
  }

  ShiftTenderSplit build() => ShiftTenderSplit(
    recorded: <CheckoutTender, ShiftTenderTotals>{
      for (final tender in CheckoutTender.values)
        tender: ShiftTenderTotals(
          totalMinor: _recordedMinor[tender]!,
          transactionCount: _recordedCount[tender]!,
        ),
    },
    unrecorded: ShiftTenderTotals(
      totalMinor: _unrecordedMinor,
      transactionCount: _unrecordedCount,
    ),
    unrecognised: ShiftTenderTotals(
      totalMinor: _unrecognisedMinor,
      transactionCount: _unrecognisedCount,
    ),
  );
}
