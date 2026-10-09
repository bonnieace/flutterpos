import '../checkout/checkout_outbox.dart';
import '../checkout/checkout_sale.dart';
import '../checkout/checkout_tender.dart';
import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_pending_mutation.dart';

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
    this.creditOwedMinor = 0,
    this.repaidMinor = 0,
    this.refundedMinor = 0,
  });

  static const ShiftSalesSummary empty = ShiftSalesSummary(
    transactionCount: 0,
    totalMinor: 0,
    unsettledCount: 0,
  );

  final int transactionCount;
  final int totalMinor;
  final int unsettledCount;

  /// The part of [totalMinor] customers took on credit, which is in the sales
  /// and not in the drawer.
  final int creditOwedMinor;

  /// What customers paid back into this shift, which is in the drawer and is
  /// not a sale.
  final int repaidMinor;

  /// What this drawer handed back over the counter for returns, which left it
  /// and is not a sale. See `TenantReturnRefund`.
  final int refundedMinor;

  /// What the drawer should hold from trading, before any float: the sales
  /// less what was lent, plus what was paid back, less what was handed back.
  int get drawerMinor =>
      totalMinor - creditOwedMinor + repaidMinor - refundedMinor;

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

/// What the server holds for one shift, counted there rather than here.
final class ShiftServerTotals {
  const ShiftServerTotals({
    required this.transactionCount,
    required this.totalMinor,
    this.creditOwedMinor,
    this.repaidMinor,
    this.repaidPaymentIds,
    this.refundedMinor,
    this.refundedReturnIds,
  }) : assert(
         (repaidMinor == null) == (repaidPaymentIds == null),
         'A repaid figure is read with the payments that make it up.',
       ),
       assert(
         (refundedMinor == null) == (refundedReturnIds == null),
         'A refunded figure is read with the returns that make it up.',
       );

  final int transactionCount;
  final int totalMinor;

  /// The part of [totalMinor] left owing on credit sales, or null where that
  /// could not be read - which is never zero.
  final int? creditOwedMinor;

  /// What customers paid back into the shift, or null where that could not
  /// be read - which is never zero.
  final int? repaidMinor;

  /// The payments [repaidMinor] counts, so a repayment this phone still has
  /// queued is added once and a landed one is not added twice. Null exactly
  /// where [repaidMinor] is: the two are one read.
  final Set<String>? repaidPaymentIds;

  /// What the shift handed back for returns, or null where that could not be
  /// read - which is never zero.
  final int? refundedMinor;

  /// The returns [refundedMinor] counts, so one this phone still has queued
  /// is added once and a landed one is not added twice.
  final Set<String>? refundedReturnIds;
}

/// Repayments this phone took into a shift, from its own durable queue.
///
/// **Why a close needs this.** A repayment is a callable, so one taken with no
/// signal is on no server until the queue drains, and the server's count at
/// close leaves it out - while the cashier counts its cash in the drawer. The
/// close adds every one of these the server did not count.
abstract interface class ShiftQueuedRepayments {
  /// Each repayment's amount by payment ID, for [shiftId]. Refused ones are
  /// not in it: their money was handed back or never taken.
  Future<Map<String, int>> forShift({
    required String uid,
    required String tenantId,
    required String shiftId,
  });
}

/// [ShiftQueuedRepayments] over the pending-mutation store.
final class PendingMutationShiftRepayments implements ShiftQueuedRepayments {
  const PendingMutationShiftRepayments(this._store);

  final TenantPendingMutationStore _store;

  @override
  Future<Map<String, int>> forShift({
    required String uid,
    required String tenantId,
    required String shiftId,
  }) async {
    final repayments = <String, int>{};
    for (final record in await _store.recordsForSession(
      uid: uid,
      tenantId: tenantId,
    )) {
      if (record.kind != TenantPendingMutationKind.customerPayment ||
          record.state == TenantPendingMutationState.rejected ||
          record.payload['shiftId'] != shiftId) {
        continue;
      }
      final paymentId = record.payload['paymentId'];
      final amount = record.payload['amountMinor'];
      if (paymentId is String && amount is int && amount > 0) {
        repayments[paymentId] = amount;
      }
    }
    return repayments;
  }
}

/// Refunds this phone handed out of a shift, from its own durable queue.
///
/// **Why a close needs this.** A return is recorded queue-first, so one taken
/// with no signal is on no server until the queue drains, and the server's
/// count at close leaves its refund out - while the cashier has already handed
/// the money over. The close takes off every one of these the server did not
/// count, exactly as [ShiftQueuedRepayments] adds repayments.
abstract interface class ShiftQueuedRefunds {
  /// Each refund's amount by return ID, for [shiftId]. Refused returns are
  /// not in it: the server never accepted that money leaving.
  Future<Map<String, int>> forShift({
    required String uid,
    required String tenantId,
    required String shiftId,
  });
}

/// [ShiftQueuedRefunds] over the pending-mutation store.
final class PendingMutationShiftRefunds implements ShiftQueuedRefunds {
  const PendingMutationShiftRefunds(this._store);

  final TenantPendingMutationStore _store;

  @override
  Future<Map<String, int>> forShift({
    required String uid,
    required String tenantId,
    required String shiftId,
  }) async {
    final refunds = <String, int>{};
    for (final record in await _store.recordsForSession(
      uid: uid,
      tenantId: tenantId,
    )) {
      if (record.kind != TenantPendingMutationKind.pendingReturnCreate ||
          record.state == TenantPendingMutationState.rejected ||
          record.payload['refundShiftId'] != shiftId) {
        continue;
      }
      final returnId = record.payload['returnId'];
      final amount = record.payload['refundMinor'];
      if (returnId is String && amount is int && amount > 0) {
        refunds[returnId] = amount;
      }
    }
    return refunds;
  }
}

/// Counts one shift's sales on the server, whichever phone rang them up.
///
/// **Why a close needs this at all, since 2026-09-29.** A shift belongs to its
/// cashier on any phone, so the outbox of the phone doing the count holds only
/// that phone's share. A closing summary built from it alone would be short by
/// every sale the cashier's other phones had already sent, and reconciliation
/// would report that as a difference on every shift that used two phones. The
/// server holds every sale that has arrived, so the close states those - and
/// what reconciliation can still find missing is only what arrived after it.
abstract interface class ShiftServerSalesTotals {
  /// The shift's server-held totals, or null when they could not be read.
  ///
  /// **Null is never zero.** Offline, a timeout, a refusal or a value that is
  /// not a whole non-negative figure all answer null, and the caller falls back
  /// to what this phone can prove rather than closing on a guess.
  Future<ShiftServerTotals?> read({
    required String tenantId,
    required String uid,
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
    var creditOwedMinor = 0;
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
      final owed = record.payload['tender'] == checkoutCreditTenderWireValue
          ? record.payload['creditOwedMinor']
          : null;
      if (owed is int && owed > 0 && owed <= total) {
        creditOwedMinor += owed;
        split.addCredit(record.payload['creditPaidTender'], total, owed);
      } else {
        split.add(record.payload['tender'], total);
      }
      if (totalMinor > maximumShiftSalesMinor) {
        throw const ShiftSalesLedgerException('shift_total_out_of_range');
      }
    }
    return ShiftSalesSummary(
      transactionCount: transactionCount,
      totalMinor: totalMinor,
      unsettledCount: unsettledCount,
      tenders: split.build(),
      creditOwedMinor: creditOwedMinor,
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
  /// does. An absent key and a stored `null` are the same fact - either a sale
  /// written before payment methods existed, or one whose cashier was never
  /// told how the customer paid - so both reach [ShiftTenderSplit.unrecorded]
  /// through the one `null` this lookup returns for either.
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

  /// Buckets one credit sale: the paid part by how it was paid, the owed
  /// part as money no method accounts for, and the sale counted once - in the
  /// bucket of what was paid, or with the owed part when nothing was.
  void addCredit(Object? paidTender, int totalMinor, int owedMinor) {
    final paid = totalMinor - owedMinor;
    final tender = CheckoutTender.tryParse(paidTender);
    _unrecognisedMinor += owedMinor;
    if (paid > 0 && tender != null) {
      _recordedMinor[tender] = _recordedMinor[tender]! + paid;
      _recordedCount[tender] = _recordedCount[tender]! + 1;
    } else {
      _unrecognisedMinor += paid;
      _unrecognisedCount += 1;
    }
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
