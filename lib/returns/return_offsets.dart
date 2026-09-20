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
    required this.returnedUnitsInScope,
    required this.returnedMinor,
    required this.returnedMinorByProduct,
    required this.returnedCostMinor,
    required this.fullyReturnedCostlessLines,
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

  /// The same, restricted to the lines this offset was actually valued over.
  ///
  /// **The one to count with.** [returnedUnits] is every unit the return
  /// names, whatever scope the valuation ran under; under a category scope
  /// that includes units from lines this offset deliberately took no money
  /// back for. A report netting its item count has to subtract the units it
  /// added, which are these.
  final Map<String, int> returnedUnitsInScope;

  /// What those units are worth, in the sale's own currency.
  ///
  /// **Discount-adjusted, and exact at the boundary.** A sale's total is its
  /// line subtotal minus a whole-sale discount, so returning every unit at list
  /// price would hand back more than the customer paid. The returned share of
  /// the subtotal is applied to the total instead, which makes a full return
  /// worth precisely [TenantSale.totalMinor] and a partial one worth its
  /// pro-rata share of what was actually charged.
  final int returnedMinor;

  /// [returnedMinor], split across the products it came back out of.
  ///
  /// **Split here so it sums to [returnedMinor] exactly**, whatever rounding
  /// the discount ratio does at the edges: the shares are allocated in order
  /// and the last one absorbs the remainder. A per-product figure derived
  /// anywhere else would be free to disagree with the total printed above it.
  final Map<String, int> returnedMinorByProduct;

  /// What those returned units *cost*, in the sale's own currency.
  ///
  /// **Not discount-adjusted, and deliberately so.** A discount reduces what
  /// the customer paid; it does not change what the goods cost this business.
  /// So revenue comes back pro-rata and cost comes back at list.
  ///
  /// **Why this exists at all.** Netting revenue out of a period without
  /// netting its cost does not leave profit merely unfixed - it corrupts it.
  /// `TenantProfitReport.from` derives cost as takings minus profit, so a
  /// takings figure reduced on its own drives the derived cost down and, on a
  /// low-margin period with a large return, negative - which that model reads
  /// as `TenantProfitBasis.inconsistent` and withholds the margin for.
  final int returnedCostMinor;

  /// How many lines carrying no cost have come back in full.
  ///
  /// **The period subtracts this from its incomplete-cost count.** A costless
  /// line that is entirely returned contributes no revenue and no cost to the
  /// net figures, so its missing cost cannot move net profit by a shilling -
  /// and going on withholding the margin over it would let a customer undo a
  /// sale and leave the report permanently unable to state a profit about
  /// goods nobody has. A line still partly sold is not counted here: some of
  /// its cost is genuinely unknown.
  final int fullyReturnedCostlessLines;

  /// Whether every unit on every line of the sale has come back.
  ///
  /// Under a category scope this is asked of the scoped lines alone: a sale
  /// whose every drinks line came back has stopped being a drinks transaction
  /// whatever else it still holds.
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
///
/// **[categoryId] narrows the valuation to one category's lines**, for a
/// report that is already adding up only those lines. The basis changes with
/// it, and that is not a detail: a whole-sale figure is the recorded total
/// minus a whole-sale discount, while a category figure is the sum of its own
/// line totals, gross of that discount - which is exactly what
/// `saleContribution` does on the server. Pro-rating a category's returns
/// against the whole sale's discount would take back money the category was
/// never credited with.
TenantSaleReturnOffset describeReturnOffset(
  TenantSale sale,
  Map<String, int> returnedUnits, {
  String? categoryId,
}) {
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

  // Every line is still checked for an impossible quantity, whatever the
  // scope: a malformed return is malformed in every report that reads it.
  for (final line in sale.lines) {
    if ((units[line.productId] ?? 0) > line.quantity) {
      throw const TenantReturnException('return_exceeds_sale');
    }
  }

  final scoped = categoryId == null
      ? sale.lines
      : <TenantSaleLine>[
          for (final line in sale.lines)
            if (line.categoryId == categoryId) line,
        ];

  var grossMinor = 0;
  var costMinor = 0;
  var costlessLinesFullyBack = 0;
  var complete = scoped.isNotEmpty;
  final unitsInScope = <String, int>{};
  final grossByProduct = <String, int>{};
  for (final line in scoped) {
    final returned = units[line.productId] ?? 0;
    if (returned < line.quantity) complete = false;
    grossMinor += returned * line.unitPriceMinor;
    if (returned == 0) continue;
    unitsInScope[line.productId] =
        (unitsInScope[line.productId] ?? 0) + returned;
    grossByProduct[line.productId] =
        (grossByProduct[line.productId] ?? 0) + returned * line.unitPriceMinor;
    // A returned line with no recorded cost takes no cost back out, which is
    // consistent rather than incomplete: it put none in either. Whether the
    // *period* can still state a profit is the aggregator's question, asked
    // per line - a line fully returned stops making the basis incomplete,
    // because its missing cost can no longer move the net figure.
    if (line.unitCostMinor case final unitCost?) {
      costMinor += returned * unitCost;
    } else if (returned >= line.quantity) {
      costlessLinesFullyBack += 1;
    }
  }

  final returnedMinor = categoryId == null
      ? _returnedMinor(sale, grossMinor, complete)
      // The category basis is the line totals themselves. A full return of
      // the category's lines is worth what those lines were added up as,
      // which is what `complete` would otherwise short-circuit past.
      : grossMinor;

  return TenantSaleReturnOffset._(
    saleId: sale.id,
    soldById: sale.soldById,
    tender: sale.tender,
    returnedUnits: Map<String, int>.unmodifiable(units),
    returnedUnitsInScope: Map<String, int>.unmodifiable(unitsInScope),
    returnedMinor: returnedMinor,
    returnedMinorByProduct: _split(returnedMinor, grossByProduct, grossMinor),
    returnedCostMinor: costMinor,
    fullyReturnedCostlessLines: costlessLinesFullyBack,
    isFullyReturned: complete,
  );
}

/// Allocates [total] across [grossByProduct] in proportion to it.
///
/// **The parts sum to [total] and not to a rounding of it.** Each share but
/// the last is rounded on its own and the last takes what is left, so a
/// discount ratio that does not divide cleanly cannot leave a per-product list
/// that adds up to a different figure from the one beside it.
Map<String, int> _split(int total, Map<String, int> grossByProduct, int gross) {
  if (grossByProduct.isEmpty) return const <String, int>{};
  // Nothing to apportion by. Every line came back at no charge, so every share
  // is nought - which is the truth, not a division this declines to do.
  if (gross <= 0) {
    return Map<String, int>.unmodifiable(<String, int>{
      for (final productId in grossByProduct.keys) productId: 0,
    });
  }
  final shares = <String, int>{};
  var allocated = 0;
  final productIds = grossByProduct.keys.toList(growable: false);
  for (final productId in productIds.take(productIds.length - 1)) {
    final share = (grossByProduct[productId]! * total / gross).round();
    shares[productId] = share;
    allocated += share;
  }
  shares[productIds.last] = total - allocated;
  return Map<String, int>.unmodifiable(shares);
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
