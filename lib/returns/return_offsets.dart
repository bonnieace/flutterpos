/// What a day's returns take back out of that day's sales.
///
/// **This is the join the Sales Report was missing.** A sale is immutable
/// evidence and a return is a separate document beside it, so nothing on a sale
/// says it was ever reversed: the report listed a fully returned sale exactly as
/// it listed one the customer kept, and counted its money into the day's
/// takings. The product owner called that on 2026-09-06, and this is the model
/// that answers it - per sale, how many units came back, what they were worth,
/// and whether anything at all is left of the sale.
///
/// **Pending returns count, and that is the product owner's call of the same
/// day.** The server restores stock only on a verified return, and this
/// deliberately does not wait for that: the screen agrees with what the cashier
/// just did rather than with what a manager has not got to yet. Stock and
/// takings are separate claims, and only the second one is made here - nothing
/// in this file moves any stock.
///
/// **The value is derived from the sale, never from the return.** A return line
/// carries a product and a quantity and no money at all, which is correct: the
/// price a unit came back at is the price it went out at, and that is recorded
/// once, on the immutable sale.
library;

import '../checkout/checkout_tender.dart';
import '../sales/sale_history.dart';
import '../tenancy/tenant_repository.dart';
import 'return_history.dart';

/// What the returns recorded against one sale have taken back out of it.
final class TenantSaleReturnOffset {
  const TenantSaleReturnOffset._({
    required this.saleId,
    required this.soldById,
    required this.tender,
    required this.returnedUnits,
    required this.returnedMinor,
    required this.isFullyReturned,
  });

  final String saleId;

  /// The cashier the *sale* is attributed to, not whoever recorded the return.
  ///
  /// A customer returns to whoever is at the till, so the two are routinely
  /// different people - and it is the seller's day that the money comes back
  /// out of. See [TenantDayReturns.scopedTo].
  final String soldById;

  /// How the sale was paid for, so the money can be taken back off the same
  /// *Paid by* row it was added to. Null on a schema v1 sale, which recorded
  /// no tender.
  final CheckoutTender? tender;

  /// Units returned per product, summed across every return against the sale.
  final Map<String, int> returnedUnits;

  /// What those units are worth, in the sale's own currency.
  ///
  /// **Discount-adjusted, and exact at the boundary.** A sale's total is its
  /// line subtotal minus a whole-sale discount, so returning every unit at list
  /// price would hand back more than the customer paid. The returned share of
  /// the subtotal is applied to the total instead, which makes a full return
  /// worth precisely [TenantSale.totalMinor] and a partial one worth its
  /// pro-rata share of what was actually charged.
  final int returnedMinor;

  /// Whether every unit on every line of the sale has come back.
  final bool isFullyReturned;
}

/// Every return filed against one trading day, valued against its own sales.
final class TenantDayReturns {
  TenantDayReturns._(this.businessDate, List<TenantSaleReturnOffset> offsets)
    : _offsets = List<TenantSaleReturnOffset>.unmodifiable(offsets),
      _bySaleId = <String, TenantSaleReturnOffset>{
        for (final offset in offsets) offset.saleId: offset,
      };

  /// A day nothing was returned on. What a screen with no returns read draws
  /// with, and what every figure falls back to.
  static final TenantDayReturns none = TenantDayReturns._(
    null,
    const <TenantSaleReturnOffset>[],
  );

  /// Null only on [none], which describes no particular day.
  final String? businessDate;

  final List<TenantSaleReturnOffset> _offsets;
  final Map<String, TenantSaleReturnOffset> _bySaleId;

  bool get isEmpty => _offsets.isEmpty;

  /// The whole day's returned value, over every sale that traded on it.
  int get returnedMinor =>
      _offsets.fold(0, (total, offset) => total + offset.returnedMinor);

  /// How many of the day's sales came back in full.
  ///
  /// This is the figure a transaction count comes down by. A partly returned
  /// sale is still a transaction that happened.
  int get fullyReturnedSales =>
      _offsets.where((offset) => offset.isFullyReturned).length;

  /// [returnedMinor] split by how the sale being reversed was paid for, so the
  /// *Paid by* rows are netted by the same money as the total above them.
  Map<CheckoutTender?, int> get returnedMinorByTender {
    final byTender = <CheckoutTender?, int>{};
    for (final offset in _offsets) {
      byTender[offset.tender] =
          (byTender[offset.tender] ?? 0) + offset.returnedMinor;
    }
    return Map<CheckoutTender?, int>.unmodifiable(byTender);
  }

  /// [fullyReturnedSales] split the same way, so a *Paid by* row's count comes
  /// down by the same transactions its amount does.
  Map<CheckoutTender?, int> get fullyReturnedByTender {
    final byTender = <CheckoutTender?, int>{};
    for (final offset in _offsets) {
      if (!offset.isFullyReturned) continue;
      byTender[offset.tender] = (byTender[offset.tender] ?? 0) + 1;
    }
    return Map<CheckoutTender?, int>.unmodifiable(byTender);
  }

  /// What has come back out of [sale], or null where nothing has.
  TenantSaleReturnOffset? offsetFor(TenantSale sale) => _bySaleId[sale.id];

  /// Whether [sale] has been returned in full and should leave the day's list.
  bool covers(TenantSale sale) => _bySaleId[sale.id]?.isFullyReturned ?? false;

  /// What [sale] is worth once its returns are taken off it.
  int netTotalMinorOf(TenantSale sale) =>
      sale.totalMinor - (_bySaleId[sale.id]?.returnedMinor ?? 0);

  /// The same day, narrowed to the sales one colleague rang up.
  ///
  /// **The takings band takes a staff filter, so the returns netted off it must
  /// take the same one.** Deducting the shop's whole day of returns from one
  /// cashier's takings would report a figure that is not anybody's.
  TenantDayReturns scopedTo(String? soldById) {
    if (soldById == null) return this;
    return TenantDayReturns._(
      businessDate,
      _offsets
          .where((offset) => offset.soldById == soldById)
          .toList(growable: false),
    );
  }
}

/// Reads one trading day's returns and values them against their own sales.
///
/// **One query and one read per returned sale, whatever the day holds**: the
/// query is by day - which is what `businessDate` on a return document exists
/// for - and the reads cover only the sales something actually came back out
/// of. A day with no returns costs the query and nothing else.
///
/// Every refusal is a refusal. A return naming a sale this business cannot read,
/// or covering more units than that sale sold, is not netted off quietly and is
/// not ignored: it means the day's takings cannot be stated correctly, and on a
/// screen whose whole subject is the day's takings that has to be said rather
/// than absorbed.
final class TenantDayReturnsLoader extends TenantReadRepository {
  TenantDayReturnsLoader({
    required super.session,
    required TenantDataReader reader,
    this.pageSize = 50,
    this.maximumPages = 20,
  }) : _reader = reader,
       super(reader: reader);

  final TenantDataReader _reader;

  /// How many returns are read per query.
  ///
  /// 50 because that is the page bound `TenantReadRepository` enforces, and
  /// asking for more is a `RangeError` rather than a bigger page.
  final int pageSize;

  /// The bound on one day. `maximumPages * pageSize` returns in a single
  /// trading day is not a busy shop, it is a fault, and a partial answer here
  /// would understate what came back rather than state nothing.
  final int maximumPages;

  Future<TenantDayReturns> load(String businessDate) async {
    final history = TenantReturnHistoryRepository(
      session: session,
      reader: _reader,
    );
    final records = <TenantReturn>[];
    String? cursor;
    for (var page = 0; page < maximumPages; page++) {
      final read = await history.loadDayReturns(
        businessDate: businessDate,
        pageSize: pageSize,
        cursor: cursor,
      );
      records.addAll(read.items);
      cursor = read.nextCursor;
      if (!read.hasMore || cursor == null) {
        return _value(businessDate, records);
      }
    }
    throw const TenantReturnException('returns_day_too_large');
  }

  /// Groups [records] by sale, reads each of those sales, and prices them.
  Future<TenantDayReturns> _value(
    String businessDate,
    List<TenantReturn> records,
  ) async {
    final unitsBySale = <String, Map<String, int>>{};
    for (final record in records) {
      final units = unitsBySale.putIfAbsent(
        record.saleId,
        () => <String, int>{},
      );
      for (final line in record.lines) {
        units[line.productId] = (units[line.productId] ?? 0) + line.quantity;
      }
    }
    if (unitsBySale.isEmpty) {
      return TenantDayReturns._(businessDate, const <TenantSaleReturnOffset>[]);
    }

    // A direct sale read is business-wide for every reading member - see the
    // `allow get` on `sales` - so a cashier's own screen can price a return
    // filed against a colleague's sale without being shown that colleague's
    // day.
    final saleIds = unitsBySale.keys.toList(growable: false);
    final sales = await Future.wait<TenantSale>(
      saleIds.map(_readSale),
      eagerError: true,
    );
    return TenantDayReturns._(businessDate, <TenantSaleReturnOffset>[
      for (final sale in sales)
        describeReturnOffset(sale, unitsBySale[sale.id]!),
    ]);
  }

  Future<TenantSale> _readSale(String saleId) async {
    final sale = await TenantSaleHistoryRepository(
      session: session,
      reader: _reader,
    ).readSale(saleId);
    if (sale == null) {
      throw const TenantReturnException('return_sale_missing');
    }
    return sale;
  }
}

/// Prices [returnedUnits] against the sale they came out of.
///
/// Exposed so the arithmetic has exactly one definition, wherever a caller
/// already holds both halves.
TenantSaleReturnOffset describeReturnOffset(
  TenantSale sale,
  Map<String, int> returnedUnits,
) {
  final units = <String, int>{
    for (final entry in returnedUnits.entries)
      if (entry.value > 0) entry.key: entry.value,
  };
  final sold = <String, int>{
    for (final line in sale.lines) line.productId: line.quantity,
  };
  for (final productId in units.keys) {
    // A return naming a product the sale never sold cannot be valued at all,
    // and would silently take nothing off a total it claims to reduce.
    if (!sold.containsKey(productId)) {
      throw const TenantReturnException('return_exceeds_sale');
    }
  }

  var grossMinor = 0;
  var complete = sale.lines.isNotEmpty;
  for (final line in sale.lines) {
    final returned = units[line.productId] ?? 0;
    if (returned > line.quantity) {
      throw const TenantReturnException('return_exceeds_sale');
    }
    if (returned < line.quantity) complete = false;
    grossMinor += returned * line.unitPriceMinor;
  }

  return TenantSaleReturnOffset._(
    saleId: sale.id,
    soldById: sale.soldById,
    tender: sale.tender,
    returnedUnits: Map<String, int>.unmodifiable(units),
    returnedMinor: _returnedMinor(sale, grossMinor, complete),
    isFullyReturned: complete,
  );
}

/// The returned share of what was actually charged.
int _returnedMinor(TenantSale sale, int grossMinor, bool complete) {
  if (complete) return sale.totalMinor;
  if (grossMinor <= 0 || sale.subtotalMinor <= 0) return 0;
  if (sale.discountMinor == 0) return grossMinor;
  final share = grossMinor * (sale.totalMinor / sale.subtotalMinor);
  // Never more than the sale is worth, whatever rounding does at the edges.
  return share.round().clamp(0, sale.totalMinor);
}
