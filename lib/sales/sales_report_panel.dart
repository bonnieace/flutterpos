import '../ui/money_text.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../checkout/checkout_catalog_cache.dart';
import '../checkout/checkout_draft.dart';
import '../checkout/checkout_outbox.dart';
import '../checkout/checkout_print_transport_base.dart';
import '../checkout/checkout_receipt.dart';
import '../checkout/checkout_tender.dart';
import '../reporting/reporting_currency.dart';
import '../reporting/device_sales_totals.dart';
import '../reporting/sales_totals.dart';
import '../reporting/sales_totals_session_context.dart';
import '../returns/return_actions.dart';
import '../returns/return_history_panel.dart';
import '../returns/return_offsets.dart';
import '../inventory/product_image_cache.dart';
import '../reports/analysis/sales_analysis.dart';
import '../reports/analysis/sales_report.dart';
import '../reports/report_document.dart';
import '../reports/report_file.dart';
import '../reports/report_identity_source.dart';
import '../reports/report_period.dart';
import '../reports/report_run.dart';
import '../reports/ui/report_action.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../tenancy/tenant_staff_names.dart';
import '../ui/buttons.dart';
import '../ui/card.dart';
import '../ui/fields.dart';
import '../ui/pagination.dart';
import '../ui/scaffold.dart';
import '../ui/rolling_number.dart';
import '../ui/skeleton.dart';
import '../ui/states.dart';
import '../ui/snackbar.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import '../inventory/product_visual.dart';
import 'receipt_lookup.dart';
import 'sale_history.dart';
import 'sale_tender.dart';
import 'sale_line_products.dart';
import 'sale_reprint.dart';

/// One tenant-safe Sales destination for daily browsing, lookup, and returns.
/// The toolbar control that takes a sales report away.
///
/// **Management only, and the reason is honesty rather than privilege.**
/// `loadReport` forces `soldById` to the reader's own uid for anybody outside
/// `managementReportRoles` - which is right for a cashier looking at their own
/// day on screen, and wrong for a document headed with the business's name. A
/// cashier's report would be their own sales presented as the shop's takings,
/// so there is no control rather than a misleading file.
///
/// Absent too where no saver is wired, and while the session is still opening.
Widget _salesReportAction(
  BuildContext context, {
  required TenantDataReader reader,
  required TenantReportSaver? saver,
  required TenantImageCache? imageCache,
  required DateTime Function()? clock,
}) {
  final session = TenantSessionScope.of(context).session;
  if (saver == null ||
      session == null ||
      !session.canAccess(
        allowedRoles: TenantSaleHistoryRepository.managementReportRoles,
      )) {
    return const SizedBox.shrink();
  }

  DateTime now() => (clock ?? () => DateTime.now().toUtc())().toUtc();

  return TenantReportAction(
    clock: now,
    run: TenantReportRun(
      kind: TenantReportKind.sales,
      support: TenantReportPeriodSupport.range,
      saver: saver,
      build: (period) async {
        final source = TenantSalesReportSource(
          repository: TenantSaleHistoryRepository(
            session: session,
            reader: reader,
          ),
        );
        final read = await source.gather(period);
        final previous = await source.gatherPrevious(period);
        final identity = await readTenantReportIdentity(
          session: session,
          reader: reader,
          generatedAt: now(),
          imageCache: imageCache,
        );
        return describeSalesReport(
          identity: identity,
          analysis: TenantSalesAnalysis.from(
            period: period,
            sales: read.sales,
            previous: previous,
            truncated: read.truncated,
            documentsRead: read.sales.length + (previous?.length ?? 0),
          ),
        );
      },
    ),
  );
}

final class TenantSalesReportScreen extends StatelessWidget {
  const TenantSalesReportScreen({
    super.key,
    required this.reader,
    this.reportReader,
    this.totalsCallable,
    this.returnActions,
    this.reprinter,
    this.tenderCallable,
    this.checkoutOutbox,
    this.catalog,
    this.clock,
    this.initialBusinessDate,
    this.initialStaffId,
    this.reportSaver,
    this.imageCache,
  });

  /// Where a generated report goes. Null renders no report control at all.
  final TenantReportSaver? reportSaver;

  /// Lets a report's branding lockup reuse the logo this device already holds.
  final TenantImageCache? imageCache;

  final TenantDataReader reader;
  final TenantSalesHistoryQueryReader? reportReader;
  final SalesTotalsCallable? totalsCallable;
  final TenantReturnActions? returnActions;

  /// See [TenantSalesReportPanel.initialBusinessDate].
  final String? initialBusinessDate;

  /// See [TenantSalesReportPanel.initialStaffId].
  final String? initialStaffId;

  /// A second copy of a receipt, audited. Absent, the sale menu offers none -
  /// see [TenantReceiptReprinter].
  final TenantReceiptReprinter? reprinter;

  /// Answers *how was this paid for?* on a sale that did not say. Absent, the
  /// sale menu offers none - see [TenantSaleTenderGateway].
  final SetSaleTenderCallable? tenderCallable;

  final HiveCheckoutOutbox? checkoutOutbox;

  /// The offline catalog the item rows take their photographs from. Absent,
  /// every row draws its glyph - see [SaleLineProducts].
  final CheckoutCatalogSource? catalog;

  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Sales Report',
    subtitle: 'Review transactions, receipts, and returns.',
    contentWidth: AppContentWidth.records,
    actions: <Widget>[
      Builder(
        builder: (context) => _salesReportAction(
          context,
          reader: reader,
          saver: reportSaver,
          imageCache: imageCache,
          clock: clock,
        ),
      ),
    ],
    body: TenantSalesReportPanel(
      reader: reader,
      reportReader: reportReader,
      totalsCallable: totalsCallable,
      returnActions: returnActions,
      reprinter: reprinter,
      tenderCallable: tenderCallable,
      checkoutOutbox: checkoutOutbox,
      catalog: catalog,
      clock: clock,
      initialBusinessDate: initialBusinessDate,
      initialStaffId: initialStaffId,
    ),
  );
}

/// Guarded, paginated daily Sales report with receipt-ending lookup.
final class TenantSalesReportPanel extends StatefulWidget {
  const TenantSalesReportPanel({
    super.key,
    required this.reader,
    this.reportReader,
    this.totalsCallable,
    this.returnActions,
    this.reprinter,
    this.tenderCallable,
    this.checkoutOutbox,
    this.catalog,
    this.clock,
    this.pageSize = 20,
    this.staffPageSize = 50,
    this.initialBusinessDate,
    this.initialStaffId,
  });

  /// The business date the report opens on. Null is today, which is how the
  /// home opens it.
  ///
  /// **Where the filters start, not a lock on them**: the date button moves it
  /// as it always does. Set by a screen that opens the report *about*
  /// something - a shift history card opens the day its shift belonged to.
  final String? initialBusinessDate;

  /// The member the report opens narrowed to. Null is everyone.
  ///
  /// Taken exactly as a choice in the staff select is: management only, and
  /// only for a member the roster lists. A cashier's report is their own
  /// whatever this says.
  final String? initialStaffId;

  final TenantDataReader reader;
  final TenantSalesHistoryQueryReader? reportReader;
  final SalesTotalsCallable? totalsCallable;
  final TenantReturnActions? returnActions;

  /// A second copy of a receipt, audited. Absent, the sale menu offers none.
  final TenantReceiptReprinter? reprinter;

  /// Answers *how was this paid for?* on a sale that did not say.
  final SetSaleTenderCallable? tenderCallable;

  final HiveCheckoutOutbox? checkoutOutbox;

  /// The offline catalog the item rows take their photographs from.
  final CheckoutCatalogSource? catalog;

  final DateTime Function()? clock;
  final int pageSize;
  final int staffPageSize;

  @override
  State<TenantSalesReportPanel> createState() => _TenantSalesReportPanelState();
}

final class _TenantSalesReportPanelState extends State<TenantSalesReportPanel> {
  final TextEditingController _receipt = TextEditingController();
  late String _businessDate;
  String? _staffId;
  List<String?> _cursors = <String?>[null];
  int _pageIndex = 0;

  /// Which way the last page turn went, so the pager can say which of its
  /// segments is working while that page is read. Null after anything that
  /// starts the day again from its first page.
  PaginationDirection? _paging;
  int _generation = 0;
  String? _submittedEnding;
  String? _receiptRejection;
  String? _historyLoaderKey;
  TenantGuardedLoader<_SalesReportView>? _historyLoader;
  String? _receiptLoaderKey;
  TenantGuardedLoader<TenantReceiptEndingLookupResult>? _receiptLoader;
  TenantGuardedLoader<TenantReceiptEndingLookupResult>? _receiptLoaderCached;
  final Map<String, Future<_SalesTotalsOutcome>> _totals =
      <String, Future<_SalesTotalsOutcome>>{};

  /// The session context, memoised as a **future** rather than as a value.
  ///
  /// `SalesTotalsSessionContextLoader` caches its result, which dedupes a
  /// second read only once the first has finished. Two readers starting in the
  /// same frame - which is exactly what the split below creates - would both
  /// miss that cache and read the categories, the staff and the currency
  /// twice. Memoising the future is what makes the day's sales and the day's
  /// takings fork from one read rather than from two.
  final Map<String, Future<SalesTotalsSessionContext>> _contexts =
      <String, Future<SalesTotalsSessionContext>>{};

  /// What the totals band is waiting on, per guard key.
  final Map<String, _TotalsBandController> _bands =
      <String, _TotalsBandController>{};

  /// The day's returns, per session, day and reader. See [_dayReturnsFor].
  final Map<String, Future<TenantDayReturns>> _dayReturns =
      <String, Future<TenantDayReturns>>{};

  /// One reprint at a time. Two taps on one card are two pieces of paper and
  /// two audit lines, and the second is almost always the first tap repeated
  /// because nothing had happened yet.
  bool _reprinting = false;
  @override
  void initState() {
    super.initState();
    _businessDate = widget.initialBusinessDate ?? _todayBusinessDate;
    _staffId = widget.initialStaffId;
  }

  String get _todayBusinessDate => checkoutBusinessDate(
    (widget.clock?.call() ?? DateTime.now().toUtc()).toUtc(),
  );

  @override
  void dispose() {
    _receipt.dispose();
    for (final band in _bands.values) {
      band.dispose();
    }
    super.dispose();
  }

  void _resetPages() {
    _cursors = <String?>[null];
    _pageIndex = 0;
    _paging = null;
    _generation++;
  }

  void _setBusinessDate(String businessDate) {
    if (businessDate == _businessDate) return;
    setState(() {
      _businessDate = businessDate;
      _resetPages();
    });
  }

  Future<void> _pickBusinessDate() async {
    final today = _todayBusinessDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(_businessDate),
      firstDate: DateTime(2000),
      lastDate: DateTime.parse(today),
      helpText: 'Select sales date',
    );
    if (picked == null || !mounted) return;
    _setBusinessDate(picked.toIso8601String().substring(0, 10));
  }

  void _setStaff(String? staffId) {
    if (staffId == _staffId) return;
    setState(() {
      _staffId = staffId;
      _resetPages();
    });
  }

  void _next(String? cursor) {
    if (cursor == null) return;
    setState(() {
      _cursors = <String?>[..._cursors.take(_pageIndex + 1), cursor];
      _pageIndex++;
      _paging = PaginationDirection.next;
    });
  }

  void _previous() {
    if (_pageIndex == 0) return;
    setState(() {
      _pageIndex--;
      _paging = PaginationDirection.previous;
    });
  }

  void _onReceiptChanged(String value) {
    if (value.trim().isNotEmpty ||
        _submittedEnding == null && _receiptRejection == null) {
      return;
    }
    setState(() {
      _submittedEnding = null;
      _receiptRejection = null;
    });
  }

  void _submitReceipt() {
    try {
      final query = TenantReceiptEndingQuery.parse(
        businessDate: _businessDate,
        ending: _receipt.text,
        maximumBusinessDate: _todayBusinessDate,
      );
      setState(() {
        _submittedEnding = query.displayEnding;
        _receiptRejection = null;
      });
    } on TenantReceiptLookupException {
      setState(() {
        _submittedEnding = null;
        _receiptRejection =
            'Enter the receipt ending as 1 to 6 digits, such as 0042.';
      });
    }
  }

  TenantGuardedLoader<_SalesReportView>? _historyLoaderCached;

  /// One pair of loaders per guard key: the day from the server, and the day
  /// from the sale documents this device already holds.
  void _composeHistoryLoaders(String key) {
    if (_historyLoaderKey == key && _historyLoader != null) return;
    _historyLoaderKey = key;
    final businessDate = _businessDate;
    final chosenStaffId = _staffId;
    final cursor = _cursors[_pageIndex];
    _historyLoader = _readWith(
      widget.reader,
      widget.reportReader,
      businessDate: businessDate,
      chosenStaffId: chosenStaffId,
      cursor: cursor,
      cacheOnly: false,
    );
    final cache = widget.reader.cached;
    _historyLoaderCached = cache == null
        ? null
        : _readWith(
            cache,
            widget.reportReader?.cachedSalesHistory,
            businessDate: businessDate,
            chosenStaffId: chosenStaffId,
            cursor: cursor,
            cacheOnly: true,
          );
  }

  /// The day's sales, over whichever pair of readers this is handed.
  TenantGuardedLoader<_SalesReportView> _readWith(
    TenantDataReader reader,
    TenantSalesHistoryQueryReader? reportReader, {
    required String businessDate,
    required String? chosenStaffId,
    required String? cursor,
    required bool cacheOnly,
  }) {
    return (session) async {
      final management = session.canAccess(
        allowedRoles: TenantSaleHistoryRepository.managementReportRoles,
      );
      final context = await _contextFor(
        session,
        reader: reader,
        management: management,
      );
      final appliedStaffId =
          management &&
              chosenStaffId != null &&
              (cacheOnly || context.staff.contains(chosenStaffId))
          ? chosenStaffId
          : null;
      final page =
          await TenantSaleHistoryRepository(
            session: session,
            reader: reader,
            reportReader: reportReader,
          ).loadReport(
            startBusinessDate: businessDate,
            endBusinessDate: businessDate,
            selectedStaffId: management ? appliedStaffId : session.uid,
            pageSize: widget.pageSize,
            cursor: cursor,
          );
      final resolved = await TenantStaffNameResolver(
        session: session,
        reader: reader,
      ).resolve(page.items.map((sale) => sale.soldById));
      // **Read with the day rather than beside it.** A sale that has been
      // returned in full leaves this list, so the list cannot be drawn at all
      // until the returns have answered - drawing it first would put a sale on
      // screen for a frame and then take it away again, which on a screen about
      // money reads as the report changing its mind.
      final returns = await _dayReturnsFor(
        session,
        reader: reader,
        businessDate: businessDate,
      );
      return _SalesReportView(
        page: page,
        businessDate: businessDate,
        appliedStaffId: appliedStaffId,
        management: management,
        context: context,
        names: <String, String>{...context.staff.names, ...resolved},
        returns: returns,
      );
    };
  }

  /// What the totals band reads, on its own and in parallel with the day.
  ///
  /// **This used to be the last `await` in the loader above, and that was the
  /// defect the product owner reported on 2026-08-27**: *the online data makes
  /// the offline data come late*. The day's sales are a Firestore read and
  /// serve from its cache; the takings are a callable and cannot be served
  /// offline at all. Chained, the whole page moved at the speed of the one
  /// region that needs a network - so a cashier with no signal watched a
  /// skeleton over sales this device was holding the whole time.
  ///
  /// It forks after the context because it has to: a stale staff selection is
  /// dropped rather than sent, and only the context can say whether the chosen
  /// colleague still exists. That read is shared, not repeated - see
  /// [_contextFor].
  ///
  /// Null where there is nothing to read: a cashier does not see the band, and
  /// no callable means the figures were never on offer.
  _TotalsBandController? _totalsBandFor(String key, TenantSession session) {
    final management = session.canAccess(
      allowedRoles: TenantSaleHistoryRepository.managementReportRoles,
    );
    final cache = widget.reader.cached;
    if (!management || cache == null && widget.totalsCallable == null) {
      return null;
    }
    final businessDate = _businessDate;
    final chosenStaffId = _staffId;
    return _bands.putIfAbsent(key, () {
      final Future<_TotalsBandData>? local = cache == null
          ? null
          : () async {
              final context = await _contextFor(
                session,
                reader: cache,
                management: true,
              );
              final aggregator = TenantDeviceSalesAggregator(
                session: session,
                cacheReader: cache,
                outbox: widget.checkoutOutbox,
                clock: widget.clock,
              );
              final result = await aggregator.load(
                aggregator.createBusinessDateQuery(
                  businessDate: businessDate,
                  // Preserve the requested scope even when the local staff
                  // directory has not cached that member yet.
                  soldById: chosenStaffId,
                ),
              );
              final totals = result.totals;
              if (totals == null) {
                throw StateError('device_sales_unavailable');
              }
              return _TotalsBandData(
                outcome: _SalesTotalsOutcome(value: totals),
                currency: context.currency,
                returns: (await _dayReturnsFor(
                  session,
                  reader: cache,
                  businessDate: businessDate,
                )).scopedTo(chosenStaffId),
              );
            }();
      final callable = widget.totalsCallable;
      final Future<_TotalsBandData>? server = callable == null
          ? null
          : () async {
              final context = await _contextFor(
                session,
                reader: widget.reader,
                management: true,
              );
              final appliedStaffId =
                  chosenStaffId != null && context.staff.contains(chosenStaffId)
                  ? chosenStaffId
                  : null;
              final gateway = TenantSalesTotalsGateway(
                session: session,
                callable: callable,
                clock: widget.clock,
              );
              // Narrowed by the same colleague the takings were: the shop's
              // whole day of returns taken off one cashier's figure would be
              // nobody's number.
              final returns = (await _dayReturnsFor(
                session,
                reader: widget.reader,
                businessDate: businessDate,
              )).scopedTo(appliedStaffId);
              return _TotalsBandData(
                outcome: await _totalsFor(
                  session,
                  gateway.createBusinessDateQuery(
                    businessDate: businessDate,
                    soldById: appliedStaffId,
                  ),
                ),
                currency: context.currency,
                returns: returns,
              );
            }();
      return _TotalsBandController(local: local, server: server);
    });
  }

  /// The day's returns for [session], read at most once however many regions
  /// ask.
  ///
  /// Memoised exactly as [_contextFor] is, and for the same reason: the day's
  /// sales and the day's takings fork from here and would otherwise each pay
  /// for their own copy of the same query. Keyed by reader as well, because the
  /// cache-only fork is a different answer about the same day rather than the
  /// same one.
  Future<TenantDayReturns> _dayReturnsFor(
    TenantSession session, {
    required TenantDataReader reader,
    required String businessDate,
  }) {
    final key =
        '${session.uid}:${session.tenantId}:${session.epoch}:$businessDate:'
        '${identityHashCode(reader)}';
    return _dayReturns.putIfAbsent(
      key,
      () => TenantDayReturnsLoader(
        session: session,
        reader: reader,
      ).load(businessDate),
    );
  }

  /// The context for [session], read at most once however many regions ask.
  Future<SalesTotalsSessionContext> _contextFor(
    TenantSession session, {
    required TenantDataReader reader,
    required bool management,
  }) {
    final key =
        '${session.uid}:${session.tenantId}:${session.epoch}:$management:'
        '${identityHashCode(reader)}';
    return _contexts.putIfAbsent(
      key,
      () => management
          ? SalesTotalsSessionContextLoader(
              reader: reader,
              staffPageSize: widget.staffPageSize,
            ).load(session)
          : _cashierContext(session, reader),
    );
  }

  Future<SalesTotalsSessionContext> _cashierContext(
    TenantSession session,
    TenantDataReader reader,
  ) async {
    TenantReportingCurrency currency;
    try {
      currency = await TenantReportingCurrency.read(
        session: session,
        reader: reader,
      );
    } catch (_) {
      currency = TenantReportingCurrency.unknown;
    }
    return SalesTotalsSessionContext(
      categories: const SalesTotalsCategoryOptions.unreadable(),
      staff: const SalesTotalsStaffOptions.unreadable(),
      currency: currency,
    );
  }

  Future<_SalesTotalsOutcome> _totalsFor(
    TenantSession session,
    TenantSalesTotalsQuery query,
  ) {
    final key =
        '${session.uid}:${session.tenantId}:${session.epoch}:'
        '${query.startDate}:${query.endDate}:${query.soldById ?? '-'}';
    return _totals.putIfAbsent(key, () async {
      try {
        return _SalesTotalsOutcome(
          value: await TenantSalesTotalsGateway(
            session: session,
            callable: widget.totalsCallable!,
            clock: widget.clock,
          ).load(query),
        );
      } catch (error) {
        return _SalesTotalsOutcome(error: error);
      }
    });
  }

  TenantGuardedLoader<TenantReceiptEndingLookupResult> _receiptLoaderFor({
    required String ending,
    required String businessDate,
    required String? soldById,
  }) {
    final key = '$businessDate:$ending:${soldById ?? '-'}';
    if (_receiptLoaderKey == key && _receiptLoader != null) {
      return _receiptLoader!;
    }
    _receiptLoaderKey = key;
    _receiptLoader = (session) =>
        TenantReceiptLookupRepository(
          session: session,
          reader: widget.reader,
        ).findByEnding(
          businessDate: businessDate,
          ending: ending,
          soldById: soldById,
          maximumBusinessDate: _todayBusinessDate,
        );
    final cache = widget.reader.cached;
    _receiptLoaderCached = cache == null
        ? null
        : (session) =>
              TenantReceiptLookupRepository(
                session: session,
                reader: cache,
              ).findByEnding(
                businessDate: businessDate,
                ending: ending,
                soldById: soldById,
                maximumBusinessDate: _todayBusinessDate,
              );
    return _receiptLoader!;
  }

  /// Opens the return sheet over this list.
  ///
  /// **A sheet rather than a pushed route since 2026-08-26.** It captures its
  /// own session scope and reports its own answer, so naming the sale is
  /// almost all there is to do here.
  ///
  /// **The almost is the day, and it is the second half of the 2026-09-06
  /// report.** A return changes what this page says - a sale returned in full
  /// leaves the list and every figure in the band comes down - and nothing used
  /// to ask the page to look again, so the sale the customer had just handed
  /// back sat there with its money still counted. A settled return re-reads the
  /// day; an abandoned sheet costs nothing.
  void _openReturns(BuildContext context, TenantSale sale) {
    unawaited(() async {
      final answer = await openTenantSaleReturnSheet(
        context,
        reader: widget.reader,
        request: TenantSaleReturnsRequest(sale: sale),
        actions: widget.returnActions,
      );
      if (answer != null && mounted) _refreshDay();
    }());
  }

  /// The reprint action for [session], or null where there is not one.
  ///
  /// Two gates, and they are different questions. The reprinter is absent on a
  /// build with no printer composition at all; the role check is the one the
  /// callable enforces, asked here so a cashier is not offered a control that
  /// would refuse them - §2.1's rule that an action a person cannot take is not
  /// drawn.
  /// Offers the tender answer only where this build can carry it.
  ///
  /// The per-sale conditions - no method recorded, and this viewer rang it up -
  /// are applied by `_SalesPresentation`, which has the sale in hand.
  ValueChanged<TenantSale>? _setTenderAction(
    BuildContext context,
    TenantSession session,
  ) {
    final callable = widget.tenderCallable;
    if (callable == null) return null;
    return (sale) => unawaited(_setTender(context, session, sale));
  }

  /// Asks how a sale was paid for, and records the answer.
  ///
  /// **The only write this screen makes to a sale, and it is one-way.** A sale
  /// that already names a method is never offered this and the server refuses
  /// it regardless: everything downstream of a sale leans on the record not
  /// moving under it, so completing a blank is allowed and changing an answer
  /// is not.
  Future<void> _setTender(
    BuildContext context,
    TenantSession session,
    TenantSale sale,
  ) async {
    final callable = widget.tenderCallable;
    if (callable == null) return;
    final chosen = await showSaleTenderDialog(context, sale: sale);
    if (chosen == null || !context.mounted) return;

    try {
      await TenantSaleTenderGateway(
        session: session,
        target: sale,
        callable: callable,
      ).record(chosen);
    } on TenantSaleTenderException catch (error) {
      if (!context.mounted) return;
      showAppSnackBar(
        context,
        AppNotice.refused(tenantSaleTenderFailureMessage(error.failure)),
      );
      // **Re-read even on a refusal.** An ambiguous answer may have been
      // recorded, and a row that still says *Not recorded* when the server
      // disagrees is the one thing worse than the refusal itself.
      if (mounted) _refreshDay();
      return;
    }
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      AppNotice.confirmed('Recorded as ${chosen.label}.'),
    );
    if (mounted) _refreshDay();
  }

  ValueChanged<TenantSale>? _reprintAction(TenantSession session) {
    if (widget.reprinter == null) return null;
    if (!session.canAccess(allowedRoles: tenantReceiptReprintRoles)) {
      return null;
    }
    return (sale) => unawaited(_reprint(session, sale));
  }

  /// Puts a second copy of one receipt on paper, and says what happened.
  ///
  /// **Nothing on this page changes**, which is what separates a reprint from
  /// every other action here: it writes an audit line and some bytes to a
  /// printer, and the day's sales and takings are exactly what they were. So
  /// there is no re-read, only a sentence.
  Future<void> _reprint(TenantSession session, TenantSale sale) async {
    final reprinter = widget.reprinter;
    if (reprinter == null || _reprinting) return;
    setState(() => _reprinting = true);
    try {
      final report = await reprinter.reprint(session: session, sale: sale);
      if (!mounted) return;
      showAppSnackBar(context, _reprintNotice(sale, report));
    } finally {
      if (mounted) setState(() => _reprinting = false);
    }
  }

  /// Reads the selected day again, returns and takings included.
  ///
  /// The band controllers are deliberately *not* cleared: they are keyed by the
  /// guard key, which carries the generation this bumps, so the next build
  /// composes a new one and the old is disposed with the panel. Disposing one
  /// here would pull it out from under the `AnimatedBuilder` still listening to
  /// it.
  void _refreshDay() {
    setState(() {
      _dayReturns.clear();
      _totals.clear();
      _resetPages();
    });
  }

  @override
  Widget build(BuildContext context) {
    final key =
        'sales:$_generation:$_pageIndex:$_businessDate:${_staffId ?? '-'}';
    // **Started here rather than inside either branch, and handed to both.**
    // The band outlives the guard's loading state: it is the same widget and
    // the same future before and after the day's sales land, so it neither
    // restarts nor blinks when they do.
    final scoped = TenantSessionScope.of(context).session;
    final band = scoped == null ? null : _totalsBandFor(key, scoped);
    _composeHistoryLoaders(key);
    // **The catalog is read once around the guard rather than once per card.**
    // The day's sales and a receipt lookup draw the same rows, and a page turn
    // rebuilds them all; a lookup that started at the row would read the box
    // again for every line on the page.
    final report = TenantRouteGuard<_SalesReportView>(
      allowedRoles: TenantSaleHistoryRepository.reportRoles,
      load: _historyLoader!,
      loadCached: _historyLoaderCached,
      // **The report itself, with placeholders where the read will land.** It
      // took the guard's default full-page spinner until 2026-08-27, which
      // replaced the receipt search, the date button and the pagination along
      // with the figures - so a cashier who came to look up a receipt had to
      // wait for a day's sales they had not asked for. Decision 35: the
      // furniture is drawn, and only the day's takings and its sales are
      // placeholders.
      //
      // The session is read from the scope rather than the guard, because the
      // guard has not admitted one yet at this point; `requireSession` is what
      // decides that, and a denied session never reaches here.
      loading: switch (scoped) {
        final session? => _SalesReportContents(
          session: session,
          view: null,
          totalsBand: band,
          businessDate: _businessDate,
          management: session.canAccess(
            allowedRoles: TenantSaleHistoryRepository.managementReportRoles,
          ),
          receipt: _receipt,
          submittedEnding: _submittedEnding,
          receiptRejection: _receiptRejection,
          receiptResult: null,
          pageIndex: _pageIndex,
          paging: _paging,
          pageSize: widget.pageSize,
          onReceiptChanged: _onReceiptChanged,
          onSubmitReceipt: _submitReceipt,
          onPickDate: _pickBusinessDate,
          onStaffChanged: _setStaff,
          onPrevious: null,
          onNext: null,
          onOpenReturns: (sale) => _openReturns(context, sale),
          onReprint: _reprintAction(session),
          onSetTender: _setTenderAction(context, session),
        ),
        // No session in scope at all is the guard's own `denied` case arriving
        // a frame early. Drawing nothing is what it draws.
        null => const SizedBox.shrink(),
      },
      // **The page, with a notice on it - not a sentence where the page was.**
      // This used to draw one centred line and nothing else, which took the
      // date picker and the receipt search away along with the sales: a person
      // whose day failed to read could not even ask for a different day. The
      // weekly report already keeps its furniture through a failure; this is
      // the same call.
      failure: (context, error) => switch (scoped) {
        final session? => _SalesReportContents(
          session: session,
          view: null,
          totalsBand: band,
          businessDate: _businessDate,
          management: session.canAccess(
            allowedRoles: TenantSaleHistoryRepository.managementReportRoles,
          ),
          receipt: _receipt,
          submittedEnding: _submittedEnding,
          receiptRejection: _receiptRejection,
          receiptResult: null,
          pageIndex: _pageIndex,
          paging: _paging,
          pageSize: widget.pageSize,
          failureMessage: 'The sales for this day could not be read.',
          onReceiptChanged: _onReceiptChanged,
          onSubmitReceipt: _submitReceipt,
          onPickDate: _pickBusinessDate,
          onStaffChanged: _setStaff,
          onPrevious: null,
          onNext: null,
          onOpenReturns: (sale) => _openReturns(context, sale),
          onReprint: _reprintAction(session),
          onSetTender: _setTenderAction(context, session),
        ),
        null => const SizedBox.shrink(),
      },
      builder: (context, session, view) {
        final ending = _submittedEnding;
        final Widget? receiptResult = ending == null
            ? null
            // **Keyed, unlike the report guard above it.** This is the one
            // shape [TenantRouteGuard.load] names as an exception: its
            // subject changes within one instance, so holding the previous
            // receipt on screen while the next one is looked up would state
            // the wrong sale rather than merely be a moment behind.
            : TenantRouteGuard<TenantReceiptEndingLookupResult>(
                key: ValueKey(
                  'sales-receipt:${view.businessDate}:$ending:'
                  '${view.appliedStaffId ?? '-'}',
                ),
                allowedRoles: TenantReceiptLookupRepository.allowedRoles,
                load: _receiptLoaderFor(
                  ending: ending,
                  businessDate: view.businessDate,
                  soldById: view.appliedStaffId,
                ),
                loadCached: _receiptLoaderCached,
                failure: (context, error) => Callout(
                  key: const ValueKey('sales-receipt-failure'),
                  status: AppStatus.problem,
                  message:
                      error is TenantReceiptLookupException &&
                          error.code == 'too_many_matches'
                      ? 'More than 50 sales share this ending. Select a staff '
                            'member to narrow the search.'
                      : 'That receipt could not be looked up.',
                ),
                builder: (context, session, result) => _ReceiptSearchResult(
                  result: result,
                  returns: view.returns,
                  names: view.names,
                  selfUid: session.uid,
                  onOpenReturns: (sale) => _openReturns(context, sale),
                  onReprint: _reprintAction(session),
                  onSetTender: _setTenderAction(context, session),
                ),
              );
        return _SalesReportContents(
          onSetTender: _setTenderAction(context, session),
          session: session,
          view: view,
          totalsBand: band,
          businessDate: view.businessDate,
          management: view.management,
          receipt: _receipt,
          submittedEnding: _submittedEnding,
          receiptRejection: _receiptRejection,
          receiptResult: receiptResult,
          pageIndex: _pageIndex,
          paging: _paging,
          pageSize: widget.pageSize,
          onReceiptChanged: _onReceiptChanged,
          onSubmitReceipt: _submitReceipt,
          onPickDate: _pickBusinessDate,
          onStaffChanged: _setStaff,
          onReprint: _reprintAction(session),
          onPrevious: _pageIndex == 0 ? null : _previous,
          onNext: view.page.hasMore ? () => _next(view.page.nextCursor) : null,
          onOpenReturns: (sale) => _openReturns(context, sale),
        );
      },
    );
    return SaleLineProducts(
      catalog: widget.catalog,
      session: scoped,
      child: report,
    );
  }
}

final class _SalesTotalsOutcome {
  const _SalesTotalsOutcome({this.value, this.error});

  final TenantSalesTotals? value;
  final Object? error;
}

final class _SalesReportView {
  const _SalesReportView({
    required this.page,
    required this.businessDate,
    required this.appliedStaffId,
    required this.management,
    required this.context,
    required this.names,
    required this.returns,
  });

  final TenantSalePage page;
  final String businessDate;
  final String? appliedStaffId;
  final bool management;
  final SalesTotalsSessionContext context;
  final Map<String, String> names;

  /// What the day's returns have taken back out of it, read once and shared
  /// with the takings band. See [TenantDayReturns].
  final TenantDayReturns returns;
}

/// What the totals band draws once its own read lands.
final class _TotalsBandData {
  const _TotalsBandData({
    required this.outcome,
    required this.currency,
    required this.returns,
  });

  final _SalesTotalsOutcome outcome;

  /// Read with the band rather than taken from the day, because the band is
  /// the only region on this page that states money.
  final TenantReportingCurrency currency;

  /// What came back out of the day these takings are for, already narrowed to
  /// whoever [outcome] reports on.
  final TenantDayReturns returns;
}

/// The report, whether or not the day's sales have arrived yet.
///
/// **The screen decision 35 was taken for.** Everything a person came here to
/// *do* - look up a receipt, change the date, narrow to a colleague, page
/// through - is furniture rather than data, and none of it has any reason to
/// wait for a read. So this composition is built once and drawn in both states:
/// [view] null means the sales and the totals are outstanding, and they are the
/// only two regions that become placeholders.
///
/// **[businessDate] and [management] are passed rather than read off [view]**,
/// which is what makes the date button and the staff filter genuinely
/// independent of the read. The date is the panel's own selection - it is what
/// was *asked for*, and the panel knows it before anyone answers - and whether
/// this member manages is a property of the session, which the guard has
/// already established. Taking either from the loaded view would have made two
/// controls wait for a figure neither of them shows.
final class _SalesReportContents extends StatelessWidget {
  const _SalesReportContents({
    required this.session,
    required this.view,
    required this.totalsBand,
    required this.businessDate,
    required this.management,
    required this.receipt,
    required this.submittedEnding,
    required this.receiptRejection,
    required this.receiptResult,
    required this.pageIndex,
    required this.paging,
    required this.pageSize,
    this.failureMessage,
    required this.onReceiptChanged,
    required this.onSubmitReceipt,
    required this.onPickDate,
    required this.onStaffChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onOpenReturns,
    required this.onReprint,
    required this.onSetTender,
  });

  final TenantSession session;

  /// Null while the day is still being read. **Not null-for-empty**: a day with
  /// no sales has answered, and `_SalesPresentation` has its own empty state
  /// for exactly that.
  final _SalesReportView? view;

  /// The day's takings, on their own clock. Null where this member is not
  /// offered them at all, in which case no band is drawn.
  final _TotalsBandController? totalsBand;

  /// What went wrong reading the day, or null where nothing did.
  ///
  /// Drawn as a notice above the controls rather than in place of them: the
  /// read failing is a fact about the day, not about the screen.
  final String? failureMessage;

  /// The day being asked about, which the panel knows before anything answers.
  final String businessDate;

  /// Whether this member may narrow the day to one colleague, from the session
  /// rather than from the read.
  final bool management;
  final TextEditingController receipt;
  final String? submittedEnding;
  final String? receiptRejection;
  final Widget? receiptResult;
  final int pageIndex;

  /// Which way the last page turn went. While the guard is re-reading it is
  /// the read the pager says it is waiting on; once the page lands it says
  /// nothing.
  final PaginationDirection? paging;

  /// How many sales a page reads, which is what numbers the records shown.
  final int pageSize;
  final ValueChanged<String> onReceiptChanged;
  final VoidCallback onSubmitReceipt;
  final VoidCallback onPickDate;
  final ValueChanged<String?> onStaffChanged;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final ValueChanged<TenantSale> onOpenReturns;

  /// Null where this member may not reprint, or this build has no printer.
  final ValueChanged<TenantSale>? onReprint;

  /// Answers *how was this paid for?* on a sale that did not say.
  final ValueChanged<TenantSale>? onSetTender;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final inset = width < AppLayout.contract.mediumFloor
        ? tokens.spacing.s16
        : width < AppLayout.contract.expandedFloor
        ? tokens.spacing.s20
        : tokens.spacing.s24;
    final showingReceipt = submittedEnding != null && receiptResult != null;
    return PagedListView(
      listKey: const ValueKey('sales-report'),
      padding: EdgeInsets.all(inset),
      // A receipt looked up by its number is one sale, and does not page.
      pagination: showingReceipt ? null : _pager(context),
      children: <Widget>[
        if (failureMessage case final message?) ...<Widget>[
          Callout(
            key: const ValueKey('sales-report-failure'),
            status: AppStatus.problem,
            title: 'Not read',
            message: message,
          ),
          SizedBox(height: tokens.spacing.s16),
        ],
        _receiptSearch(context),
        if (receiptRejection case final message?) ...<Widget>[
          SizedBox(height: tokens.spacing.s12),
          Callout(
            key: const ValueKey('sales-receipt-invalid'),
            status: AppStatus.attention,
            message: message,
          ),
        ],
        SizedBox(height: tokens.spacing.s12),
        _scopeControls(context),
        SizedBox(height: tokens.spacing.s16),
        if (showingReceipt)
          receiptResult!
        else ...<Widget>[
          // **The one region on this page that genuinely needs a server**, and
          // since 2026-08-27 the only one that waits for it. The day's sales
          // come from Firestore and serve from its cache offline; the totals
          // are a callable and do not. Both used to hang off one read, so the
          // sales waited for the takings - which offline meant waiting for
          // something that was never going to arrive.
          if (management && totalsBand != null) ...<Widget>[
            _TotalsBand(band: totalsBand!, businessDate: businessDate),
            SizedBox(height: tokens.spacing.s20),
          ],
          if (view case final loaded?)
            _SalesPresentation(
              sales: loaded.page.items,
              returns: loaded.returns,
              // The day's list is a list of what the shop sold and still has
              // the money for. A sale returned in full belongs to the returns
              // record, not here.
              hideFullyReturned: true,
              names: loaded.names,
              selfUid: session.uid,
              filtered: loaded.appliedStaffId != null,
              onOpenReturns: onOpenReturns,
              onReprint: onReprint,
              onSetTender: onSetTender,
            )
          else
            const _SaleCardsSkeleton(key: ValueKey('sales-report-skeleton')),
        ],
      ],
    );
  }

  /// The pager for the day's cards, held at the bottom of the screen by
  /// [PagedListView].
  ///
  /// **While a turned page is read, the page being left stays on screen** -
  /// the guard holds it, see [TenantReadFreshness.rereading] - so the pager
  /// says so too: the figure is that page's, the segment that was pressed
  /// shows a spinner, and neither answers a second press. The figure rolls
  /// when the new page's sales land, so the roll is the arrival rather than
  /// the press. A re-read that is not a page turn - a new date, a new
  /// colleague, a return settled - draws no spinner.
  Pagination _pager(BuildContext context) {
    final loaded = view;
    final rereading = TenantReadFreshness.maybeOf(context)?.rereading ?? false;
    final reading = rereading ? paging : null;
    final pageNumber = switch (reading) {
      PaginationDirection.next => pageIndex,
      PaginationDirection.previous => pageIndex + 2,
      null => pageIndex + 1,
    };
    final first = (pageNumber - 1) * pageSize + 1;
    return Pagination(
      pageNumber: pageNumber,
      previousKey: const ValueKey('sales-report-previous-page'),
      nextKey: const ValueKey('sales-report-next-page'),
      pageKey: const ValueKey('sales-report-page'),
      onPrevious: onPrevious,
      onNext: onNext,
      loading: reading,
      // Only a page that has answered can say whether it was the last one.
      endOfList: loaded != null && !loaded.page.hasMore,
      // **The records this page read**, as the design numbers them - a sale
      // returned in full is still one of them, though its card has left the
      // list.
      range: loaded == null || loaded.page.items.isEmpty
          ? null
          : (first: first, last: first + loaded.page.items.length - 1),
    );
  }

  Widget _receiptSearch(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final field = AppTextField(
      key: const ValueKey('sales-receipt-search'),
      controller: receipt,
      label: '',
      placeholder: 'Receipt ending, e.g. 0042',
      leading: Icons.receipt_long_outlined,
      maxLength: 6,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.search,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
      ],
      autocorrect: false,
      enableSuggestions: false,
      onChanged: onReceiptChanged,
      onSubmitted: (_) => onSubmitReceipt(),
    );
    final button = AppIconButton(
      key: const ValueKey('sales-receipt-submit'),
      icon: Icons.search,
      semanticLabel: 'Find receipt',
      onPressed: onSubmitReceipt,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(child: field),
        SizedBox(width: tokens.spacing.s12),
        button,
      ],
    );
  }

  Widget _scopeControls(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final loaded = view;
    // **No caption over either control.** *Date* sat above a button already
    // showing a date behind a calendar glyph, and *Sold by* above a control
    // reading *All staff* - both of them the same word twice, and between them
    // two lines of type over the figures this page exists to show.
    //
    // **The date button keeps the word as its announcement**, because
    // `AppButton` has no `semanticLabel` of its own and a button reading only
    // `2026-09-21` tells a screen reader nothing about what pressing it does.
    // Hidden, never removed - the contract `AppTextField.dense` states.
    final date = Semantics(
      key: const ValueKey('sales-date-filter'),
      label: 'Date, $businessDate',
      button: true,
      excludeSemantics: true,
      child: AppButton(
        key: const ValueKey('sales-date-picker'),
        label: businessDate,
        icon: Icons.calendar_today_outlined,
        tier: AppButtonTier.secondary,
        expand: true,
        onPressed: onPickDate,
      ),
    );
    // A member who cannot narrow the day never gets this control in either
    // state. While the read is outstanding the directory has not answered yet,
    // so the control is drawn holding the only option it can honestly offer.
    if (!management || (loaded != null && !loaded.context.staff.readable)) {
      return date;
    }
    final staff = AppSelect<String>(
      key: const ValueKey('sales-staff-filter'),
      value: loaded?.appliedStaffId ?? '',
      label: 'Sold by',
      dense: true,
      leading: Icons.person_outline,
      // **Disabled rather than absent while the colleagues are being read.**
      // Absent would move the date button from half the row to all of it and
      // back again, which is the jump this whole change exists to remove; and a
      // list a person can open onto one option is a control that lies about
      // being ready. `AppSelect` draws its own disabled state.
      enabled: loaded != null,
      items: <AppSelectItem<String>>[
        const AppSelectItem<String>(value: '', label: 'All staff'),
        if (loaded != null)
          for (final uid in loaded.context.staff.uids)
            AppSelectItem<String>(
              value: uid,
              label: tenantStaffLabel(
                uid,
                names: loaded.context.staff.names,
                selfUid: session.uid,
              ),
            ),
      ],
      onChanged: (value) =>
          onStaffChanged(value == null || value.isEmpty ? null : value),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: date),
        SizedBox(width: tokens.spacing.s12),
        Expanded(child: staff),
      ],
    );
  }
}

/// The totals band's height while it is being read.
///
/// **Named here rather than tokenised, for the reason `EmptyState.markSize`
/// gives**: no source this app has states this band's box, and
/// `_ManagementSalesSummary` derives its own from figures a placeholder does
/// not have. 96 is what the takings-and-count pair measures once its payment
/// rows are folded, which is the shape it opens in.
const double _totalsBandHeight = 96;

/// The hairline this page's cards are ruled with: one logical pixel, which is
/// `Divider`'s own default. Named rather than inlined because this app has no
/// stroke-width token to read it from - recorded here rather than invented as
/// one.
const double _hairline = 1;

/// A sale card's frame: `surface.raised` inside a `cardEdge` hairline at
/// `radius.lg`, with everything in it clipped inside the edge.
///
/// **Not `AppCard`, and the foot is why.** `AppCard` lays its child over its
/// own border, which is right for a card whose content is inset and wrong for
/// this one: the foot is a filled strip running edge to edge, and it painted
/// its square corners over the card's rounded ones and its fill over the
/// card's bottom edge, so the card had no edge along the bottom at all. The
/// design draws the strip *inside* the edge, as a border-box does, and that is
/// what the inset and the clip reproduce.
///
/// **`radius.lg` rather than `AppCard`'s `radius.md`**, because the design
/// draws these cards at 12.
final class _SaleCardFrame extends StatelessWidget {
  const _SaleCardFrame({super.key, required this.child});

  final Widget child;

  /// The space between two cards in the day's list.
  static double gap(AppTokens tokens) => tokens.spacing.s12;

  /// The foot's padding. The design draws 10 above and below the line, which
  /// falls between two steps of the scale; `space.8` is the slimmer of the
  /// pair.
  static EdgeInsets footPadding(AppTokens tokens) => EdgeInsets.symmetric(
    horizontal: tokens.spacing.s12,
    vertical: tokens.spacing.s8,
  );

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final radius = tokens.radius.lg;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.colors.surface.raised,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: tokens.colors.surface.cardEdge,
          width: _hairline,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(_hairline),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius - _hairline),
          child: child,
        ),
      ),
    );
  }
}

/// Placeholder sale cards, for the day that has not been read yet.
///
/// **Its own widget rather than `RecordListSkeleton`**, because
/// `_SalesPresentation` draws cards at every width - it is not a `RecordList`
/// and does not become a table at `expanded`. A placeholder that turned into a
/// table here would promise a screen this page never draws.
final class _SaleCardsSkeleton extends StatelessWidget {
  const _SaleCardsSkeleton({super.key});

  /// Four fills a phone without pretending to know what the day holds.
  static const int _cards = 4;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return SkeletonGroup(
      semanticLabel: 'Reading the sales for this day.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (var card = 0; card < _cards; card++)
            Padding(
              padding: EdgeInsets.only(
                top: card == 0 ? 0 : _SaleCardFrame.gap(tokens),
              ),
              child: const _SaleCardSkeleton(),
            ),
        ],
      ),
    );
  }
}

/// One placeholder sale card, arranged like the card it stands in for.
///
/// **A featureless slab was wrong and 2026-08-27 replaces it**, at the product
/// owner's report. The first version drew one 148-pixel block per sale, which
/// reserves the right *space* and says nothing about what will fill it: four
/// grey slabs are indistinguishable from four loading anything. A person
/// waiting on this screen should be able to see, before the read lands, that a
/// sale is a time and a receipt over its items with a total - which is the
/// whole argument for a skeleton over a spinner.
///
/// **The chrome is real, and only the values are blocks.** Decision 35 again:
/// the card frame, both rules and the foot's fill do not change when the read
/// returns, so they are drawn rather than approximated. What shimmers is
/// exactly the set of things the server is still deciding, each block where
/// [_SaleCard] puts the value it stands for.
final class _SaleCardSkeleton extends StatelessWidget {
  const _SaleCardSkeleton();

  /// Two item rows, because a placeholder cannot know a basket's size and two
  /// is enough to read as *a list of things* rather than as one more line.
  static const int _items = 2;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    // Everything sits inside a card, so every block steps up from `raised`
    // rather than matching it.
    const tone = SkeletonTone.onRaised;
    return _SaleCardFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: tokens.spacing.s12,
              top: tokens.spacing.s4,
              bottom: tokens.spacing.s4,
            ),
            child: Row(
              children: <Widget>[
                SkeletonBlock(
                  width: AppButton.iconSize,
                  height: AppButton.iconSize,
                  radius: tokens.radius.sm,
                  tone: tone,
                ),
                SizedBox(width: tokens.spacing.s8),
                Expanded(
                  child: Row(
                    children: <Widget>[
                      // The time, which leads the real card and so leads this.
                      Expanded(
                        child: SkeletonLine(
                          widthFactor: 0.72,
                          style: tokens.typography.numericBody.copyWith(
                            fontSize: tokens.typography.titleMedium.fontSize,
                          ),
                          tone: tone,
                        ),
                      ),
                      SizedBox(width: tokens.spacing.s8),
                      Expanded(
                        child: SkeletonLine(
                          widthFactor: 0.62,
                          style: tokens.typography.caption,
                          tone: tone,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: tokens.spacing.s8),
                SizedBox(
                  width: tokens.spacing.s64,
                  child: SkeletonLine(
                    style: tokens.typography.numericBody.copyWith(
                      fontSize: tokens.typography.bodyLarge.fontSize,
                    ),
                    tone: tone,
                  ),
                ),
                // The menu's glyph, in the menu's square.
                SizedBox.square(
                  dimension: tokens.density.minimumTapTarget.height,
                  child: Center(
                    child: SkeletonBlock(
                      width: tokens.spacing.s20,
                      height: tokens.spacing.s20,
                      radius: tokens.radius.sm,
                      tone: tone,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: _hairline, color: tokens.colors.surface.borderSubtle),
          for (var item = 0; item < _items; item++) ...<Widget>[
            if (item > 0)
              Divider(
                height: _hairline,
                indent: tokens.spacing.s16,
                endIndent: tokens.spacing.s16,
                color: tokens.colors.surface.borderSubtle,
              ),
            const _SaleItemRowSkeleton(tone: tone),
          ],
          Container(
            padding: _SaleCardFrame.footPadding(tokens),
            color: tokens.colors.surface.overlay,
            child: Wrap(
              spacing: tokens.spacing.s12,
              runSpacing: tokens.spacing.s4,
              children: <Widget>[
                // Two ragged widths rather than two equal ones: a staff name
                // and a tender are not the same length, and a placeholder that
                // pretends they are reads as a table.
                SizedBox(
                  width: tokens.spacing.s64 + tokens.spacing.s32,
                  child: SkeletonLine(
                    style: tokens.typography.caption,
                    tone: tone,
                  ),
                ),
                SizedBox(
                  width: tokens.spacing.s40,
                  child: SkeletonLine(
                    style: tokens.typography.caption,
                    tone: tone,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One placeholder item row, shaped like [_SaleItemRow]: a product square, its
/// name over its quantity, and the line total against the trailing edge.
final class _SaleItemRowSkeleton extends StatelessWidget {
  const _SaleItemRowSkeleton({required this.tone});

  final SkeletonTone tone;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.s16,
        vertical: tokens.spacing.s12,
      ),
      child: Row(
        children: <Widget>[
          SkeletonBlock(
            width: tokens.spacing.s40,
            height: tokens.spacing.s40,
            radius: tokens.radius.md,
            tone: tone,
          ),
          SizedBox(width: tokens.spacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SkeletonLine(
                  widthFactor: 0.62,
                  style: tokens.typography.labelMedium,
                  tone: tone,
                ),
                SkeletonLine(
                  widthFactor: 0.34,
                  style: tokens.typography.caption,
                  tone: tone,
                ),
              ],
            ),
          ),
          SizedBox(width: tokens.spacing.s12),
          SizedBox(
            width: tokens.spacing.s64,
            child: SkeletonLine(
              style: tokens.typography.numericBody,
              tone: tone,
            ),
          ),
        ],
      ),
    );
  }
}

/// The day's takings, and the placeholder that stands in while they are read.
///
/// **A region with its own clock.** It is the page's only callable, so it is
/// the page's only genuinely online region, and it reveals when its own answer
/// arrives rather than when the day's sales do. A refusal - which offline is
/// every time - states itself here and leaves the rest of the page alone.
final class _TotalsBand extends StatelessWidget {
  const _TotalsBand({required this.band, required this.businessDate});

  final _TotalsBandController band;
  final String businessDate;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: band,
    builder: (context, child) {
      final data = band.data;
      if (data == null) {
        // `_totalsBandFor` catches its own refusals into an outcome, so
        // nothing that reaches this branch is something the band can word. It
        // draws the placeholder rather than claim a figure it does not have.
        return const SkeletonGroup(
          key: ValueKey('sales-report-totals-skeleton'),
          semanticLabel: 'Reading the totals for this day.',
          child: SkeletonBlock(height: _totalsBandHeight),
        );
      }
      return _ManagementSalesSummary(
        outcome: data.outcome,
        currency: data.currency,
        businessDate: businessDate,
        returns: data.returns,
      );
    },
  );
}

final class _TotalsBandController extends ChangeNotifier {
  _TotalsBandController({
    required Future<_TotalsBandData>? local,
    required Future<_TotalsBandData>? server,
  }) {
    local
        ?.then((value) {
          if (_disposed || _serverWon) return;
          data = value;
          notifyListeners();
        })
        .catchError((Object _) {});
    server
        ?.then((value) {
          if (_disposed) return;
          if (value.outcome.value != null) {
            _serverWon = true;
            data = value;
            notifyListeners();
          } else if (data == null) {
            data = value;
            notifyListeners();
          }
        })
        .catchError((Object _) {});
  }

  _TotalsBandData? data;
  bool _serverWon = false;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final class _ManagementSalesSummary extends StatelessWidget {
  const _ManagementSalesSummary({
    required this.outcome,
    required this.currency,
    required this.businessDate,
    required this.returns,
  });

  final _SalesTotalsOutcome outcome;
  final TenantReportingCurrency currency;
  final String businessDate;

  /// What came back out of this day, already narrowed to whoever [outcome]
  /// reports on.
  ///
  /// **Netted here rather than in the decoder, and that is deliberate.**
  /// [TenantSalesTotals] is the server's answer and checks itself against its
  /// own tender split; taking money off it there would leave a decoded object
  /// that no longer describes what the server said. What the returns change is
  /// the figure a person is shown, so the deduction lives where the figure is
  /// drawn - and the count comes down only for the sales that came back in
  /// *full*, because a partly returned sale is still a transaction that
  /// happened.
  final TenantDayReturns returns;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final totals = outcome.value;
    if (totals == null) {
      if (outcome.error == null) return const SizedBox.shrink();
      return Callout(
        key: const ValueKey('sales-report-totals-failure'),
        status: AppStatus.attention,
        title: 'Totals unavailable',
        message: _totalsFailureMessage(outcome.error!),
      );
    }
    // **The server's netting where it sends one, this screen's where it does
    // not.** Both compute the same rule from the same returns, and that is the
    // problem: two implementations of one money rule drift. The callable now
    // joins the period's returns itself and reports `net` beside the gross
    // figures, so that is the answer wherever it arrives - and it is the
    // better one, being read from Firestore rather than from whatever this
    // device happened to have cached.
    //
    // The local arithmetic stays as the fallback and nothing more. An older
    // deployment sends no `net`, and this screen netted returns long before
    // the rest of the reporting stack did; losing that against an old server
    // would be a regression, not a simplification.
    final serverNet = totals.net;
    final returnedMinor = returns.returnedMinor;
    final netSales =
        serverNet?.sales ?? _nonNegative(totals.sales - returnedMinor / 100);
    final netTransactions =
        serverNet?.transactions ??
        (totals.transactions - returns.fullyReturnedSales).clamp(
          0,
          totals.transactions,
        );
    // The split has to describe the same money as the total above it, so it
    // comes from whichever side that total did.
    final breakdown = serverNet == null
        ? totals.tenderBreakdown
        : serverNet.tenderBreakdown;
    // A server breakdown arrives already netted, so netting it again here
    // would take the same returns off the rows twice.
    TenantSalesTenderTotals row(
      CheckoutTender? tender,
      TenantSalesTenderTotals gross,
    ) => serverNet == null ? _netTender(tender, gross) : gross;
    final paymentRows = breakdown == null
        ? const <_PaymentSummaryEntry>[]
        : <_PaymentSummaryEntry>[
            for (final entry in breakdown.recorded.entries)
              if (!row(entry.key, entry.value).isEmpty)
                _PaymentSummaryEntry(
                  label: entry.key.label,
                  icon: switch (entry.key) {
                    CheckoutTender.cash => Icons.payments_outlined,
                    CheckoutTender.mpesa => Icons.phone_android_outlined,
                    CheckoutTender.card => Icons.credit_card_outlined,
                  },
                  totals: row(entry.key, entry.value),
                ),
            // A schema v1 sale recorded no tender, so the money that comes back
            // out of one comes off this row rather than off a payment method it
            // never named.
            if (!row(null, breakdown.unrecorded).isEmpty)
              _PaymentSummaryEntry(
                label: 'Not recorded',
                icon: Icons.history_outlined,
                totals: row(null, breakdown.unrecorded),
              ),
            // Nothing is ever netted off this one: a sale carrying a tender
            // this app does not model is a sale `TenantSale` refuses to decode,
            // so no return can be attributed to it.
            if (!breakdown.unrecognised.isEmpty)
              _PaymentSummaryEntry(
                label: 'Unrecognised',
                icon: Icons.help_outline,
                totals: breakdown.unrecognised,
              ),
          ];
    return AppCard(
      key: const ValueKey('sales-report-summary'),
      padding: EdgeInsets.all(tokens.spacing.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // **No basis caption over the figure**, at the developer's direction
          // on 2026-09-22. A caption reading *On this device* sat above the
          // takings whenever the totals came off the cache rather than the
          // callable, and it appeared and disappeared under the same day's
          // figure as the network came and went. The other report surfaces -
          // the monthly report, the totals page, the weekly sections - still
          // carry their own; this one does not.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.colors.status.ok.bg,
                  borderRadius: BorderRadius.circular(tokens.radius.md),
                ),
                child: Padding(
                  padding: EdgeInsets.all(tokens.spacing.s12),
                  child: Icon(
                    Icons.payments_outlined,
                    color: tokens.colors.text.money,
                    size: 24,
                  ),
                ),
              ),
              SizedBox(width: tokens.spacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'Revenue',
                      style: tokens.typography.labelMedium.copyWith(
                        color: tokens.colors.text.secondary,
                      ),
                    ),
                    SizedBox(height: tokens.spacing.s4),
                    // **It rolls, because this figure corrects itself.** The
                    // takings come from a callable while the sales beside them
                    // come off this device, so the number on screen can be
                    // replaced a moment after it is read. A total that silently
                    // becomes a different total is the kind of thing somebody
                    // notices afterwards and stops trusting; the `numeric`
                    // roles are tabular, so only the digits that changed move.
                    //
                    // **Still inside the `FittedBox`.** A phone's card has to
                    // hold six figures of takings beside a transaction count,
                    // and a truncated amount is a wrong amount where a smaller
                    // one is the same amount.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: RollingNumber(
                        value: currency.format(netSales),
                        textKey: const ValueKey('sales-report-revenue'),
                        style: tokens.typography.numericHero.copyWith(
                          color: currency.isKnown
                              ? tokens.colors.text.money
                              : tokens.colors.text.primary,
                        ),
                      ),
                    ),
                    SizedBox(height: tokens.spacing.s4),
                    Text(
                      businessDate,
                      key: const ValueKey('sales-report-summary-range'),
                      style: tokens.typography.caption.copyWith(
                        color: tokens.colors.text.tertiary,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: tokens.spacing.s12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'Transactions',
                    style: tokens.typography.labelMedium.copyWith(
                      color: tokens.colors.text.secondary,
                    ),
                  ),
                  SizedBox(height: tokens.spacing.s4),
                  RollingNumber(
                    value: '$netTransactions',
                    textKey: const ValueKey('sales-report-transactions'),
                    style: tokens.typography.numericHero.copyWith(
                      color: tokens.colors.text.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (paymentRows.isNotEmpty) ...<Widget>[
            SizedBox(height: tokens.spacing.s16),
            Divider(height: 1, color: tokens.colors.surface.borderSubtle),
            SizedBox(height: tokens.spacing.s12),
            Text(
              'Paid by',
              style: tokens.typography.titleMedium.copyWith(
                color: tokens.colors.text.primary,
              ),
            ),
            SizedBox(height: tokens.spacing.s8),
            for (
              var index = 0;
              index < paymentRows.length;
              index++
            ) ...<Widget>[
              if (index > 0) SizedBox(height: tokens.spacing.s12),
              _PaymentSummaryLine(
                entry: paymentRows[index],
                periodSales: netSales,
                currency: currency,
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// One *Paid by* row with its day's returns taken back off it.
  ///
  /// **Only reached on the fallback.** When the server sends `netByTender`
  /// the rows are already netted and are passed through untouched; netting
  /// them again here would take the same returns off twice.
  TenantSalesTenderTotals _netTender(
    CheckoutTender? tender,
    TenantSalesTenderTotals gross,
  ) => TenantSalesTenderTotals(
    sales: _nonNegative(
      gross.sales - (returns.returnedMinorByTender[tender] ?? 0) / 100,
    ),
    transactions:
        (gross.transactions - (returns.fullyReturnedByTender[tender] ?? 0))
            .clamp(0, gross.transactions)
            .toInt(),
  );
}

/// **A figure this screen states is never below zero.** The takings come from a
/// callable and the returns from Firestore, so the two can disagree for a
/// moment - a return that has synced against a total read before it did - and
/// "the shop took minus four hundred shillings today" is a sentence no report
/// should ever print. The floor is the honest reading of that disagreement:
/// everything this day took has come back.
double _nonNegative(double value) => value < 0 ? 0 : value;

final class _PaymentSummaryEntry {
  const _PaymentSummaryEntry({
    required this.label,
    required this.icon,
    required this.totals,
  });

  final String label;
  final IconData icon;
  final TenantSalesTenderTotals totals;
}

final class _PaymentSummaryLine extends StatelessWidget {
  const _PaymentSummaryLine({
    required this.entry,
    required this.periodSales,
    required this.currency,
  });

  final _PaymentSummaryEntry entry;
  final double periodSales;
  final TenantReportingCurrency currency;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final share = periodSales <= 0
        ? 0.0
        : (entry.totals.sales / periodSales).clamp(0.0, 1.0).toDouble();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.colors.surface.overlay,
            borderRadius: BorderRadius.circular(tokens.radius.sm),
          ),
          child: SizedBox.square(
            dimension: 36,
            child: Icon(entry.icon, size: 18, color: tokens.colors.text.money),
          ),
        ),
        SizedBox(width: tokens.spacing.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      entry.label,
                      style: tokens.typography.labelMedium.copyWith(
                        color: tokens.colors.text.primary,
                      ),
                    ),
                  ),
                  Text(
                    '${entry.totals.transactions} '
                    '${entry.totals.transactions == 1 ? 'sale' : 'sales'}',
                    style: tokens.typography.caption.copyWith(
                      color: tokens.colors.text.tertiary,
                    ),
                  ),
                ],
              ),
              SizedBox(height: tokens.spacing.s4),
              ClipRRect(
                borderRadius: BorderRadius.circular(tokens.radius.sm),
                child: LinearProgressIndicator(
                  minHeight: 4,
                  value: share,
                  backgroundColor: tokens.colors.surface.borderSubtle,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    tokens.colors.text.money,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: tokens.spacing.s12),
        SizedBox(
          width: 112,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerEnd,
                child: Text(
                  currency.format(entry.totals.sales),
                  maxLines: 1,
                  style: tokens.typography.numericBody.copyWith(
                    color: currency.isKnown
                        ? tokens.colors.text.money
                        : tokens.colors.text.primary,
                  ),
                ),
              ),
              Text(
                '${(share * 100).round()}%',
                style: tokens.typography.caption.copyWith(
                  color: tokens.colors.text.tertiary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _totalsFailureMessage(Object error) {
  if (error is! TenantSalesTotalsException) {
    return 'The trusted selected-day totals could not be read. The sales list '
        'below is still available and is not presented as a total.';
  }
  return switch (error.failure) {
    TenantSalesTotalsFailure.periodTooLarge =>
      'This day contains more than ${TenantSalesTotals.maximumTransactions} '
          'sales, so the server refused to present a partial total.',
    TenantSalesTotalsFailure.unusableSaleData =>
      'A stored sale could not be safely included, so no total is shown.',
    TenantSalesTotalsFailure.forbidden =>
      'Your current access no longer permits business-wide totals.',
    _ =>
      'The trusted selected-day totals could not be read. The sales list '
          'below is still available and is not presented as a total.',
  };
}

final class _ReceiptSearchResult extends StatelessWidget {
  const _ReceiptSearchResult({
    required this.result,
    required this.returns,
    required this.names,
    required this.selfUid,
    required this.onOpenReturns,
    required this.onReprint,
    required this.onSetTender,
  });

  final TenantReceiptEndingLookupResult result;

  /// The day's returns, so a receipt that was reversed says so.
  final TenantDayReturns returns;

  final Map<String, String> names;
  final String selfUid;
  final ValueChanged<TenantSale> onOpenReturns;
  final ValueChanged<TenantSale>? onReprint;
  final ValueChanged<TenantSale>? onSetTender;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    if (result.isMissing) {
      return const EmptyState(
        key: ValueKey('sales-receipt-missing'),
        title: 'Receipt not found',
        hint: 'Check the selected date and receipt ending, then try again.',
        illustration: 'file-search.svg',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (result.isAmbiguous) ...<Widget>[
          Callout(
            key: const ValueKey('sales-receipt-ambiguous'),
            status: AppStatus.attention,
            title: 'More than one sale matches',
            message:
                '${result.matches.length} sales share #'
                '${result.query.displayEnding} on this date. Compare the '
                'recorded time, staff member, and items before opening returns.',
          ),
          SizedBox(height: tokens.spacing.s12),
        ],
        _SalesPresentation(
          sales: result.matches,
          returns: returns,
          // **A receipt looked up by its number is always shown, returned or
          // not.** Somebody has the paper in their hand and is asking this
          // screen what happened to it; answering "no such receipt" because it
          // came back would be the screen refusing the only question it was
          // asked.
          hideFullyReturned: false,
          names: names,
          selfUid: selfUid,
          filtered: true,
          onOpenReturns: onOpenReturns,
          onReprint: onReprint,
          onSetTender: onSetTender,
        ),
      ],
    );
  }
}

final class _SalesPresentation extends StatelessWidget {
  const _SalesPresentation({
    required this.sales,
    required this.returns,
    required this.hideFullyReturned,
    required this.names,
    required this.selfUid,
    required this.filtered,
    required this.onOpenReturns,
    required this.onReprint,
    required this.onSetTender,
  });

  final List<TenantSale> sales;

  /// What came back out of these sales. [TenantDayReturns.none] where nothing
  /// did, or where the caller has no returns read of its own.
  final TenantDayReturns returns;

  /// Whether a sale every unit of which has been returned is dropped rather
  /// than drawn. The day's list drops it; a receipt lookup does not.
  final bool hideFullyReturned;

  final Map<String, String> names;
  final String selfUid;
  final bool filtered;
  final ValueChanged<TenantSale> onOpenReturns;

  /// Null where this member may not reprint, or this build has no printer.
  final ValueChanged<TenantSale>? onReprint;

  /// Answers *how was this paid for?* on a sale that did not say. Null where
  /// this build cannot reach the callable.
  final ValueChanged<TenantSale>? onSetTender;

  @override
  Widget build(BuildContext context) {
    final shown = hideFullyReturned
        ? sales.where((sale) => !returns.covers(sale)).toList(growable: false)
        : sales;
    if (shown.isEmpty) {
      // **Three empty days, not two.** A day that traded and had every sale
      // returned is a different fact from a day that never traded, and telling
      // a shop owner "no sales yet" about a morning they served customers
      // through would read as the report having lost them.
      final allReturned = sales.isNotEmpty;
      return EmptyState(
        key: ValueKey(
          allReturned
              ? 'sales-report-all-returned'
              : filtered
              ? 'sales-report-no-matches'
              : 'sales-report-empty',
        ),
        title: allReturned
            ? 'Every sale was returned'
            : filtered
            ? 'No matching sales'
            : 'No sales yet',
        hint: allReturned
            ? 'Every sale recorded on this date has been returned in full. '
                  'The returns themselves are on the Returns screen.'
            : filtered
            ? 'Try another date or staff member.'
            : 'Transactions recorded on this date will appear here.',
        // A filter that matched nothing and a day that had nothing are
        // different facts, and section 7 already gives them different words.
        // They get different drawings for the same reason.
        illustration: filtered || allReturned
            ? 'file-search.svg'
            : 'no-data.svg',
      );
    }
    final tokens = AppTokens.componentOf(context);
    return Column(
      key: const ValueKey('sales-report-cards'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final (index, sale) in shown.indexed)
          Padding(
            padding: EdgeInsets.only(
              top: index == 0 ? 0 : _SaleCardFrame.gap(tokens),
            ),
            child: _SaleCard(
              sale: sale,
              offset: returns.offsetFor(sale),
              staffLabel: _staffLabel(sale),
              onOpenReturns: () => onOpenReturns(sale),
              onReprint: onReprint == null ? null : () => onReprint!(sale),
              // **Only the cashier who rang it up.** They are the one person
              // who was at the counter; anybody else would be guessing, and the
              // server refuses them regardless. Whether the method may still be
              // *changed* depends on the shift, which this surface cannot see
              // without a read of its own - so that one is left to the server,
              // which says so in words.
              onSetTender: onSetTender == null || sale.soldById != selfUid
                  ? null
                  : () => onSetTender!(sale),
            ),
          ),
      ],
    );
  }

  String _staffLabel(TenantSale sale) =>
      tenantStaffLabel(sale.soldById, names: names, selfUid: selfUid);
}

final class _SaleCard extends StatelessWidget {
  const _SaleCard({
    required this.sale,
    required this.offset,
    required this.staffLabel,
    required this.onOpenReturns,
    required this.onReprint,
    required this.onSetTender,
  });

  final TenantSale sale;

  /// What has come back out of this sale, or null where nothing has.
  ///
  /// A card is only ever drawn with a *partial* offset on the day's list - a
  /// sale returned in full has left it - but a receipt lookup draws whatever it
  /// was asked for, so a full one is stated rather than assumed away.
  final TenantSaleReturnOffset? offset;

  final String staffLabel;
  final VoidCallback onOpenReturns;

  /// Null where this member may not reprint, or this build has no printer.
  final VoidCallback? onReprint;

  /// Null unless this sale names no payment method and this viewer is the
  /// cashier who rang it up. See [_SalesPresentation].
  final VoidCallback? onSetTender;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final returned = offset;
    return _SaleCardFrame(
      key: ValueKey('sales-record-${sale.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            // **56 high, and the menu's target is what sets it.** The design
            // draws this row as 16 above and below a 24 line; the menu is §9's
            // 48 square, so the same 56 is 4 above and below it, and the
            // square sits against the card's edge where the design has its
            // 12 of padding.
            padding: EdgeInsetsDirectional.only(
              start: tokens.spacing.s12,
              top: tokens.spacing.s4,
              bottom: tokens.spacing.s4,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.schedule_outlined,
                  size: AppButton.iconSize,
                  color: tokens.colors.action.primary.container,
                ),
                SizedBox(width: tokens.spacing.s8),
                Expanded(
                  child: Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          _recordedTime(sale),
                          key: ValueKey('sales-recorded-time-${sale.id}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          // The figures' face at the title size: the time is
                          // what a person scans the day's cards by.
                          style: tokens.typography.numericBody.copyWith(
                            color: tokens.colors.text.primary,
                            fontSize: tokens.typography.titleMedium.fontSize,
                          ),
                        ),
                      ),
                      SizedBox(width: tokens.spacing.s8),
                      Flexible(
                        child: Text(
                          _receiptEnding(sale),
                          key: ValueKey('sales-receipt-ending-${sale.id}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tokens.typography.caption.copyWith(
                            color: tokens.colors.text.tertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: tokens.spacing.s8),
                // **What the shop still has, not what it rang up.** The gross
                // is not lost: it is the sale's line rows, immediately below,
                // and what came off it is named in the footer.
                Text(
                  _saleMoney(
                    sale,
                    sale.totalMinor - (returned?.returnedMinor ?? 0),
                  ),
                  key: ValueKey('sales-total-${sale.id}'),
                  style: tokens.typography.numericBody.copyWith(
                    color: tokens.colors.text.money,
                    fontSize: tokens.typography.bodyLarge.fontSize,
                  ),
                ),
                _SaleMenu(
                  sale: sale,
                  onOpenReturns: onOpenReturns,
                  onReprint: onReprint,
                  onSetTender: onSetTender,
                ),
              ],
            ),
          ),
          Divider(height: _hairline, color: tokens.colors.surface.borderSubtle),
          for (final (index, line) in sale.lines.indexed) ...<Widget>[
            if (index > 0)
              Divider(
                height: _hairline,
                indent: tokens.spacing.s16,
                endIndent: tokens.spacing.s16,
                color: tokens.colors.surface.borderSubtle,
              ),
            _SaleItemRow(sale: sale, line: line, index: index),
          ],
          Container(
            padding: _SaleCardFrame.footPadding(tokens),
            color: tokens.colors.surface.overlay,
            child: Wrap(
              // The spare width goes between the facts rather than after the
              // last one, so the strip spans the card.
              alignment: WrapAlignment.spaceBetween,
              spacing: tokens.spacing.s12,
              runSpacing: tokens.spacing.s4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                // **Words, no glyphs.** Each of these reads as what it is - a
                // name, a way of paying, a till's receipt number, a sync time -
                // and a glyph in front of each one was four more marks on a
                // strip that exists to be read second.
                _SaleMeta(label: staffLabel),
                _SaleMeta(label: _tender(sale)),
                // **The till, named here because the header has no room.**
                // The header's `#0001` is the same on every register's first
                // sale of a day - see `_receiptEnding` for the measurement -
                // and this foot is a `Wrap`, so it reflows onto another line
                // instead of ellipsizing the way that slot does.
                _SaleMeta(
                  key: ValueKey('sales-receipt-till-${sale.id}'),
                  label: _receiptLabel(sale),
                ),
                // **Only where the two times disagree.** The header now shows
                // when the customer paid; this says when the books heard of it,
                // so a sale that waited out an outage reads as one rather than
                // as a till with the wrong hour set.
                if (_syncedLaterAt(sale) case final synced?)
                  _SaleMeta(
                    key: ValueKey('sales-synced-later-${sale.id}'),
                    label: 'Synced ${_clockTime(synced)}',
                  ),
                // §9: the standing is a word as well as a colour, and it is
                // *all* this card says about the return.
                //
                // **What came back is not stated here, and that is the product
                // owner's call of 2026-09-06**: a returned unit stopped being
                // part of this sale the moment it came back, so its quantity
                // and its money belong to the Returns record rather than beside
                // the sale's own immutable lines. The badge stays because
                // without it the header's netted figure and the line rows below
                // it disagree with nothing to explain them.
                if (returned != null)
                  StatusBadge(
                    key: ValueKey('sales-returned-badge-${sale.id}'),
                    status: AppStatus.attention,
                    icon: Icons.assignment_return_outlined,
                    label: returned.isFullyReturned
                        ? 'Returned'
                        : 'Partly returned',
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _SaleItemRow extends StatelessWidget {
  const _SaleItemRow({
    required this.sale,
    required this.line,
    required this.index,
  });

  final TenantSale sale;
  final TenantSaleLine line;
  final int index;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    // **The product this line sold, when this device still holds it.** The
    // line records the name and the price it went out at and nothing else - a
    // sale is evidence and does not change when the catalog does - so the
    // picture is looked up rather than read off the sale. A product that is
    // not cached, or has since been deleted, keeps the glyph.
    final product = SaleLineProducts.of(context, line.productId);
    return Padding(
      key: ValueKey('sales-item-${sale.id}-$index'),
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.s16,
        vertical: tokens.spacing.s12,
      ),
      child: Row(
        children: <Widget>[
          SizedBox.square(
            dimension: tokens.spacing.s40,
            child: product == null
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      color: tokens.colors.surface.overlay,
                      borderRadius: BorderRadius.circular(tokens.radius.md),
                    ),
                    child: Icon(
                      Icons.inventory_2_outlined,
                      size: tokens.spacing.s20,
                      color: tokens.colors.text.tertiary,
                    ),
                  )
                // The till's own treatment, at the till's own radius: a
                // photograph that fills its box, and the product's initials
                // where there is no photograph. See `TenantProductVisual`.
                : TenantProductVisual(
                    key: ValueKey('sales-item-image-${sale.id}-$index'),
                    product: product,
                    semanticLabel: '${line.name} product image',
                  ),
          ),
          SizedBox(width: tokens.spacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // One line, as the design draws it: a basket reads as a column
                // of names, and a name that wraps breaks the column.
                Text(
                  line.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.typography.labelMedium.copyWith(
                    color: tokens.colors.text.primary,
                  ),
                ),
                Text(
                  '${line.quantity} × ${sale.currency} '
                  '${_money(line.unitPriceMinor)}',
                  style: tokens.typography.caption.copyWith(
                    color: tokens.colors.text.tertiary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: tokens.spacing.s12),
          Text(
            '${sale.currency} ${_money(line.lineTotalMinor)}',
            style: tokens.typography.numericBody.copyWith(
              color: tokens.colors.text.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// One fact in a sale card's foot: `caption` at `text.secondary`.
///
/// **Bounded by the foot, not by a figure of its own.** A `Wrap` hands each
/// child at most its own width, so a name longer than the strip ellipsizes at
/// the strip's edge and everything after it takes the next run.
final class _SaleMeta extends StatelessWidget {
  const _SaleMeta({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: tokens.typography.caption.copyWith(
        color: tokens.colors.text.secondary,
      ),
    );
  }
}

/// The sale card's overflow menu.
///
/// **The surface is drawn from the token layer rather than left to Material,
/// and the edge is the point.** Depth in this app is a surface step and never a
/// drop shadow - see [AppSurfaceRoles] - and the step from a card to a menu is
/// one tone: `surface.raised` is `#0D1F16` and `surface.overlay` is `#132A1F`.
/// Material's default menu paints that step and nothing else, so a menu opened
/// over a sale card had no findable edge and read as part of the card behind it,
/// which is the defect reported on 2026-09-06. `borderStrong` is the hairline
/// that separates them: it is lighter than the `cardEdge` every card already
/// wears, so the menu reads as the layer in front rather than as another card.
/// What a sale card's menu offers.
enum _SaleAction { returns, reprint, setTender }

final class _SaleMenu extends StatelessWidget {
  const _SaleMenu({
    required this.sale,
    required this.onOpenReturns,
    required this.onReprint,
    required this.onSetTender,
  });

  final TenantSale sale;
  final VoidCallback onOpenReturns;
  final VoidCallback? onReprint;

  /// Null unless this sale names no payment method and this viewer rang it up.
  final VoidCallback? onSetTender;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return PopupMenuButton<_SaleAction>(
      key: ValueKey('sales-actions-${sale.id}'),
      tooltip: 'Actions for receipt ${sale.receiptNumber}',
      icon: Icon(
        Icons.more_vert,
        size: tokens.spacing.s20,
        color: tokens.colors.text.secondary,
      ),
      iconSize: tokens.spacing.s20,
      color: tokens.colors.surface.overlay,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius.md),
        side: BorderSide(color: tokens.colors.surface.borderStrong),
      ),
      // §9's target, whatever the label inside it comes out as.
      constraints: BoxConstraints(
        minHeight: tokens.density.minimumTapTarget.height,
      ),
      onSelected: (action) => switch (action) {
        _SaleAction.returns => onOpenReturns(),
        _SaleAction.reprint => onReprint?.call(),
        _SaleAction.setTender => onSetTender?.call(),
      },
      itemBuilder: (context) => <PopupMenuEntry<_SaleAction>>[
        PopupMenuItem<_SaleAction>(
          key: ValueKey('sales-returns-${sale.id}'),
          value: _SaleAction.returns,
          height: tokens.density.minimumTapTarget.height,
          child: const _SaleMenuLabel(
            icon: Icons.assignment_return_outlined,
            label: 'Return',
          ),
        ),
        // Absent rather than disabled where this member may not reprint: a
        // greyed control invites the question "why not", and the answer is a
        // role this screen has no room to explain.
        if (onReprint != null)
          PopupMenuItem<_SaleAction>(
            key: ValueKey('sales-reprint-${sale.id}'),
            value: _SaleAction.reprint,
            height: tokens.density.minimumTapTarget.height,
            child: const _SaleMenuLabel(
              icon: Icons.print_outlined,
              label: 'Reprint receipt',
            ),
          ),
        // Absent for the same reason the reprint is: a colleague answering for
        // somebody else's counter would be guessing, and the server refuses
        // them - this keeps the entry off a menu where it could not work.
        //
        // **The verb changes with the sale**, because filling a blank and
        // correcting a mis-tap are different acts and a person should know
        // which one they are about to do.
        if (onSetTender != null)
          PopupMenuItem<_SaleAction>(
            key: ValueKey('sales-set-tender-${sale.id}'),
            value: _SaleAction.setTender,
            height: tokens.density.minimumTapTarget.height,
            child: _SaleMenuLabel(
              icon: Icons.payments_outlined,
              label: sale.tender == null
                  ? 'Set payment method'
                  : 'Change payment method',
            ),
          ),
      ],
    );
  }
}

final class _SaleMenuLabel extends StatelessWidget {
  const _SaleMenuLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Row(
      children: <Widget>[
        Icon(icon, size: 20, color: tokens.colors.text.secondary),
        SizedBox(width: tokens.spacing.s12),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tokens.typography.labelLarge.copyWith(
              color: tokens.colors.text.primary,
            ),
          ),
        ),
      ],
    );
  }
}

/// What a reprint says for itself.
///
/// **`queued` is `info` and not `ok`.** The audit line exists and the bytes are
/// durable, which is genuinely different from a refusal - but no paper has come
/// out, and on a screen where somebody is waiting to hand a customer a receipt,
/// a green tick that means "eventually" is the wrong claim.
AppNotice _reprintNotice(TenantSale sale, TenantReceiptReprintReport report) {
  final receipt = _receiptLabel(sale);
  return switch (report.outcome) {
    TenantReceiptReprintOutcome.printed => AppNotice.confirmed(
      'Receipt $receipt reprinted.',
    ),
    TenantReceiptReprintOutcome.queued => AppNotice.offline(
      'Receipt $receipt is recorded and waiting for the printer. '
      '${_reprintReason(report.reasonCode)}',
    ),
    TenantReceiptReprintOutcome.refused => AppNotice.refused(
      'Nothing was printed. ${_reprintReason(report.reasonCode)}',
    ),
  };
}

String _reprintReason(String? code) => switch (code) {
  PrinterTransportCode.notConfigured =>
    'This business has no printer configured.',
  PrinterTransportCode.unreachable => 'The printer could not be reached.',
  PrinterTransportCode.connectTimeout => 'The printer did not answer in time.',
  PrinterTransportCode.writeTimeout =>
    'The printer stopped part-way through; check the paper and the cover.',
  PrinterTransportCode.unsupported => 'This device cannot print.',
  PrinterTransportCode.bridgeUnreachable ||
  PrinterTransportCode.bridgeRejected ||
  PrinterTransportCode.bridgeUnauthorized =>
    'The print bridge refused the receipt.',
  TenantReceiptReprintCode.forbidden =>
    'Only an owner, administrator, or manager may reprint a receipt.',
  TenantReceiptReprintCode.notFound =>
    'That sale is not in this business, or its receipt number has changed.',
  TenantReceiptReprintCode.serviceMissing =>
    'Reprinting is not switched on for this business yet.',
  TenantReceiptReprintCode.unavailable =>
    'A reprint is recorded on the server, so it must be asked for online.',
  _ => 'The receipt could not be reprinted.',
};

/// The receipt as this screen says it: the till's code and the day's sequence.
///
/// **The date goes, the device code stays.** The screen is already filtered to
/// one business date, so repeating it in every row spends width on the one part
/// that cannot differ - while the code is the part that tells two tills apart,
/// and every till starts a day at 0001. Printing the sequence alone showed
/// `#0001` against two different receipts on 2026-09-17, one from each of two
/// registers, and nothing on the row said which was which.
///
/// **Split from the stored number rather than rebuilt from the device id.**
/// `TenantSale` has already proved the stored number is the one this device,
/// date and sequence produce, so a split cannot disagree with the paper the
/// customer is holding, where a second derivation could.
String _receiptLabel(TenantSale sale) {
  final parts = sale.receiptNumber.split('-');
  if (parts.length != 4) return sale.receiptNumber;
  return '${parts[0]}-${parts[1]}-${parts[3]}';
}

/// The sequence alone, for the one slot too narrow to name the till.
///
/// **It is not enough, and that is measured rather than assumed.** The row
/// holds the time and this side by side as two equal `Flexible`s inside about
/// 133 logical pixels at 411, so this slot is roughly 66 - five and a half
/// characters. `_receiptLabel` needs 131.5 and would be silently ellipsized,
/// because the row sets `TextOverflow.ellipsis` and nothing throws.
///
/// So the till is named in the card's foot instead, where the `Wrap` reflows
/// rather than truncates - see `_receiptLabel`. Putting it back on this line
/// means the row giving up the time or the amount, which is a layout decision
/// and not this change's to make.
String _receiptEnding(TenantSale sale) =>
    '#${sale.receiptSequence.toString().padLeft(checkoutReceiptSequenceDigits, '0')}';

/// The way a sale was paid, as its card's foot says it.
///
/// **The blank names what is blank.** The foot's facts stand as words alone
/// since 2026-09-22, so a bare *Not recorded* no longer had a payments glyph in
/// front of it to say what was not.
String _tender(TenantSale sale) => sale.tender?.label ?? 'Not recorded';

String _saleMoney(TenantSale sale, int minorUnits) =>
    '${sale.currency} ${_money(minorUnits)}';

String _money(int minorUnits) => moneyTextOfMinor(minorUnits);

/// When the customer paid, which offline is not when the server heard of it.
///
/// **The till's own stamp is preferred, and that is the whole fix.** A sale
/// rung with no signal has its server timestamp resolved when the batch finally
/// lands, so reading that put a 22:10 sale in the next morning's history at the
/// hour it synced. The selling device recorded the real moment at checkout and
/// every sale has carried it since; nothing read it.
///
/// **It is a label and never an order.** `recordedAt` still sorts the day,
/// because a till with a wrong clock must be able to mislabel its own row and
/// nothing else. Falls back to the server stamp for a sale written before the
/// client one existed.
String _recordedTime(TenantSale sale) {
  final value = sale.rungAt ?? sale.recordedAt;
  if (value == null) return 'Awaiting server time';
  return _clockTime(value);
}

String _clockTime(DateTime instant) {
  final local = instant.toLocal();
  String pad(int part) => part.toString().padLeft(2, '0');
  return '${pad(local.hour)}:${pad(local.minute)}';
}

/// A sale is long enough after the fact to be worth saying so.
///
/// An online commit lands in under a second and a slow one in a few; anything
/// past this was queued, which is a different fact about the sale.
const Duration _materialSyncDelay = Duration(minutes: 2);

/// When the server heard about a sale, where that is materially after it was
/// rung - otherwise null, which is the ordinary case.
///
/// **Said out loud so the row is not read as a wrong clock.** Once the time
/// shown is the till's, a sale can sit in a day's history hours before the
/// moment it reached the books, and a shopkeeper comparing the two has a right
/// to know which is which.
DateTime? _syncedLaterAt(TenantSale sale) {
  final rung = sale.rungAt;
  final recorded = sale.recordedAt;
  if (rung == null || recorded == null) return null;
  return recorded.difference(rung) >= _materialSyncDelay ? recorded : null;
}
