import '../ui/money_text.dart';
import '../tenancy/tenant_catalog.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../checkout/checkout_tender.dart';
import '../returns/return_actions.dart';
import '../returns/return_history_panel.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_staff_names.dart';
import '../ui/pagination.dart';
import '../ui/record_list.dart';
import '../ui/scaffold.dart';
import '../ui/skeleton.dart';
import '../ui/states.dart';
import '../ui/tokens.dart';
import 'sale_history.dart';

/// What a sale page is scoped to.
sealed class TenantSaleHistoryRequest {
  const TenantSaleHistoryRequest();

  String get title;

  /// Which slice of [title] this page is showing, where it is showing one.
  ///
  /// **`PageHeader.subtitle`'s first reader, and it writes no new copy.** The
  /// slot has existed since step 5a and was populated at no call site, because
  /// "rewriting a title into a title-and-subtitle pair is a copy decision".
  /// This is not that: the shift branch already drew `Shift 2026-08-14` as a
  /// second heading inside the page, which is §7's "Title appears once" defect,
  /// and the value moves into the slot built for it rather than a new string
  /// being invented. The title says what the page is; this says which one.
  String? get subtitle => null;

  /// A stable identity for the guard key, so a new request restarts the load.
  String get key;
}

/// The sales recorded during one canonical shift.
final class TenantShiftSaleHistoryRequest extends TenantSaleHistoryRequest {
  const TenantShiftSaleHistoryRequest({
    required this.shift,
    required this.recordedTransactionCount,
    required this.recordedTotalSalesMinor,
    required this.countedCashMinor,
  });

  final TenantSaleShiftScope shift;

  /// The figures the closing device recorded. They are shown for inspection
  /// and never recalculated here: only reconciliation may contradict them.
  final int? recordedTransactionCount;
  final int? recordedTotalSalesMinor;
  final int countedCashMinor;

  @override
  String get title => 'Shift sales';

  @override
  String get subtitle => shift.businessDate;

  @override
  String get key => 'shift:${shift.shiftId}';
}

/// This cashier's own most recent sales, for receipt lookup.
final class TenantOwnSaleHistoryRequest extends TenantSaleHistoryRequest {
  const TenantOwnSaleHistoryRequest();

  @override
  String get title => 'My recent sales';

  @override
  String get key => 'own';
}

/// Read-only sales route for the selected tenant session.
final class TenantSaleHistoryScreen extends StatelessWidget {
  const TenantSaleHistoryScreen({
    super.key,
    required this.reader,
    required this.request,
    this.returnActions,
  });

  final TenantDataReader reader;
  final TenantSaleHistoryRequest request;

  /// Passed through to the returns route. Recording stays unavailable while it
  /// is absent, and that route is read-only.
  final TenantReturnActions? returnActions;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: request.title,
    subtitle: request.subtitle,
    contentWidth: AppContentWidth.records,
    body: TenantSaleHistoryPanel(
      reader: reader,
      request: request,
      returnActions: returnActions,
    ),
  );
}

/// Pages immutable sales behind [TenantRouteGuard].
final class TenantSaleHistoryPanel extends StatefulWidget {
  const TenantSaleHistoryPanel({
    super.key,
    required this.reader,
    required this.request,
    this.returnActions,
    this.pageSize = 20,
  });

  final TenantDataReader reader;
  final TenantSaleHistoryRequest request;

  /// Passed through to the returns route only. This surface never writes.
  final TenantReturnActions? returnActions;
  final int pageSize;

  @override
  State<TenantSaleHistoryPanel> createState() => _TenantSaleHistoryPanelState();
}

final class _TenantSaleHistoryPanelState extends State<TenantSaleHistoryPanel> {
  List<String?> _cursors = <String?>[null];
  int _pageIndex = 0;
  final TenantStaffNameResolvers _staffNames = TenantStaffNameResolvers();

  /// One resolver per session **and per pass**, so the cached pass resolves a
  /// name from this device rather than putting a network read in front of
  /// records it already holds. An unresolved name degrades to the UID.
  TenantStaffNameResolver _resolverFor(
    TenantSession session,
    TenantDocumentReader reader,
  ) => _staffNames.of(session: session, reader: reader);

  void _nextPage(String? cursor) {
    if (cursor == null) return;
    setState(() {
      _cursors = <String?>[..._cursors.take(_pageIndex + 1), cursor];
      _pageIndex++;
    });
  }

  void _previousPage() {
    if (_pageIndex == 0) return;
    setState(() => _pageIndex--);
  }

  /// One loader pair per page and request, memoised so an unrelated rebuild
  /// does not restart the read. See [TenantRouteGuard.load].
  void _composeLoaders(String key) {
    if (key == _loaderKey && _loader != null) return;
    _loaderKey = key;
    final cursor = _cursors[_pageIndex];
    final request = widget.request;
    TenantGuardedLoader<TenantNamedPage<TenantSalePage>> readWith(
      TenantDataReader reader,
    ) => (session) async {
      final repository = TenantSaleHistoryRepository(
        session: session,
        reader: reader,
      );
      final page = await switch (request) {
        TenantShiftSaleHistoryRequest(:final shift) =>
          repository.loadShiftSales(
            shift: shift,
            pageSize: widget.pageSize,
            cursor: cursor,
          ),
        TenantOwnSaleHistoryRequest() => repository.loadOwnRecentSales(
          pageSize: widget.pageSize,
          cursor: cursor,
        ),
      };
      return TenantNamedPage<TenantSalePage>(
        page: page,
        names: await _resolverFor(
          session,
          reader,
        ).resolve(page.items.map((sale) => sale.soldById)),
      );
    };
    _loader = readWith(widget.reader);
    final cache = widget.reader.cached;
    _loaderCached = cache == null ? null : readWith(cache);
  }

  String? _loaderKey;
  TenantGuardedLoader<TenantNamedPage<TenantSalePage>>? _loader;
  TenantGuardedLoader<TenantNamedPage<TenantSalePage>>? _loaderCached;

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    _composeLoaders('${request.key}:$_pageIndex:${_cursors[_pageIndex]}');
    return TenantRouteGuard<TenantNamedPage<TenantSalePage>>(
      load: _loader!,
      loadCached: _loaderCached,
      holdsNothing: (named) => named.page.items.isEmpty,
      // **The page itself, with placeholders where the sales will be.** It used
      // to take the guard's default full-page spinner, which replaced the
      // heading and the pagination along with the records - so a person waiting
      // learned nothing about the screen they were waiting for. Decision 35:
      // only the read is a placeholder.
      loading: _SaleHistoryContents(
        request: request,
        page: null,
        pageIndex: _pageIndex,
      ),
      denied: const Center(
        key: ValueKey('sale-history-denied'),
        child: Text('Sales are unavailable for this business.'),
      ),
      failure: (context, error) => const Center(
        key: ValueKey('sale-history-failure'),
        child: Text('Sales could not be loaded.'),
      ),
      builder: (context, session, named) => _SaleHistoryContents(
        request: request,
        page: named.page,
        staffNames: named.names,
        selfUid: session.uid,
        pageIndex: _pageIndex,
        onNextPage: () => _nextPage(named.page.nextCursor),
        onPreviousPage: _previousPage,
        onViewReturns: (sale) => _openReturns(context, sale),
      ),
    );
  }

  /// Opens the return sheet over this list.
  ///
  /// **A sheet rather than a pushed route since 2026-08-26.** It captures its
  /// own session scope and reports its own answer, so there is nothing left to
  /// do here but name the sale.
  void _openReturns(BuildContext context, TenantSale sale) {
    unawaited(
      openTenantSaleReturnSheet(
        context,
        reader: widget.reader,
        request: TenantSaleReturnsRequest(sale: sale),
        actions: widget.returnActions,
      ),
    );
  }
}

/// The page, whether or not its sales have arrived yet.
///
/// **One composition for the loading state and the loaded one**, which is
/// decision 35 (`docs/stitch/OPEN_QUESTIONS.md`, 2026-08-27) made structural
/// rather than promised: the heading, the shift's recorded-figures note and the
/// pagination do not come from the read, so they are built here once and drawn
/// in both. There is no second widget that could drift from this one.
///
/// This is the shape `weekly_report_panel.dart` already uses for its *failure*
/// state - `WeeklyReportContents(report: null)`, keeping the filters alive - and
/// all that has happened is that the loading state now takes it too.
final class _SaleHistoryContents extends StatelessWidget {
  const _SaleHistoryContents({
    required this.request,
    required this.page,
    this.staffNames = const <String, String>{},
    this.selfUid,
    required this.pageIndex,
    this.onNextPage,
    this.onPreviousPage,
    this.onViewReturns,
  });

  final TenantSaleHistoryRequest request;

  /// Null while the read is outstanding. **Not null-for-empty**: an empty read
  /// has answered, and answers with `page.items.isEmpty`, which is what puts
  /// `RecordList`'s own empty state on screen instead of a placeholder.
  final TenantSalePage? page;

  final Map<String, String> staffNames;

  /// Null only while [page] is, since nothing reads it until there are records.
  final String? selfUid;

  final int pageIndex;

  /// Null while loading. The buttons still draw - they are the page's furniture
  /// rather than the read's - and `Pagination` already renders a null handler as
  /// a disabled control, which is the truth: there is no next page to go to
  /// until this one has been read.
  final VoidCallback? onNextPage;
  final VoidCallback? onPreviousPage;
  final ValueChanged<TenantSale>? onViewReturns;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return PagedListView(
      listKey: const ValueKey('sale-history'),
      padding: EdgeInsets.all(tokens.spacing.s20),
      pagination: Pagination(
        pageNumber: pageIndex + 1,
        previousKey: const ValueKey('sale-history-previous'),
        nextKey: const ValueKey('sale-history-next'),
        onPrevious: pageIndex > 0 ? onPreviousPage : null,
        onNext: (page?.hasMore ?? false) ? onNextPage : null,
        endOfList: page?.hasMore == false,
      ),
      children: [
        // **§7's "Title appears once".** Both branches drew this route's name a
        // second time under the `PageHeader` that carries it — `Recent sales`
        // beneath `My recent sales`, and `Shift 2026-08-14` beneath `Shift sales`.
        // The first was a duplicate and is gone; the second named *which* shift,
        // which is what `PageHeader.subtitle` is for, and the screen supplies it
        // from the same request this panel reads.
        if (request case final TenantShiftSaleHistoryRequest shift) ...[
          Text(
            key: const ValueKey('sale-history-recorded'),
            _recordedLabel(shift),
          ),
          SizedBox(height: tokens.spacing.s4),
          const Text(
            'These are the figures the shift recorded when it closed. Page '
            'through the sales to inspect them; this screen calculates no '
            'replacement total.',
          ),
        ],
        SizedBox(height: tokens.spacing.s16),
        // The sales themselves are the read, so they are the one region that
        // becomes a placeholder. Everything above and below this is furniture
        // and is already on screen.
        if (page case final loaded?)
          // §4.3's responsive contract.
          RecordList(
            identityLabel: 'Sale',
            items: <RecordItem>[for (final sale in loaded.items) _record(sale)],
            // §7's Empty pattern. No action: a sale is rung up at the till
            // rather than from its own history, so there is nothing here for a
            // person to press that would end the emptiness.
            empty: const EmptyState(
              key: ValueKey('sale-history-empty'),
              title: 'No sales yet',
              hint: 'Confirmed sales appear here.',
              illustration: 'receipt-history.svg',
            ),
          )
        else
          const SkeletonGroup(
            key: ValueKey('sale-history-skeleton'),
            semanticLabel: 'Reading the sales.',
            child: RecordListSkeleton(),
          ),
        // **Said once under the list, in the words `sales_totals_panel.dart`
        // already says them.** It rode on every row as the second half of "Paid
        // by Cash. …", which at §5.2's key-value made the payment column three
        // lines tall on every record and the tallest thing on the page - a
        // seventy-character invariant repeated twenty times. It is a property of
        // how a tender is captured rather than of any sale, and this screen still
        // states it, which is what `sale_history.dart` requires of a surface that
        // shows one.
        if (page?.items.any((sale) => sale.tender != null) ?? false) ...[
          SizedBox(height: tokens.spacing.s8),
          const Text(
            key: ValueKey('sale-history-tender-disclaimer'),
            checkoutTenderDisclaimer,
          ),
        ],
        // Deliberately a different sentence from `checkoutTenderUnrecordedMessage`
        // for the reason the totals page gives: that one says "This sale", which
        // is a claim about one record and is wrong above a list of them. The fact
        // is the same and is stated again rather than reused wrongly.
        if (page?.items.any((sale) => sale.tenderUnanswered) ?? false) ...[
          SizedBox(height: tokens.spacing.s8),
          const Text(
            key: ValueKey('sale-history-tender-unrecorded-note'),
            'A sale names no payment method when it was recorded before they '
            'were captured, or when nobody said how the customer paid, so its '
            'payment is stated as not recorded.',
          ),
        ],
      ],
    );
  }

  /// One sale as §5.2's rows.
  ///
  /// **No standing, and that is the same reading the ledger reached.** §2.1's
  /// five each mean one thing and "a sale was rung up" is not among them. The
  /// one thing that varies between these records is whether this device has
  /// seen the server confirm the sale, and every surface in this app states that
  /// in its provenance line rather than as a badge - so a badge here would say
  /// on one screen what a sentence says on the next.
  RecordItem _record(TenantSale sale) => RecordItem(
    id: sale.id,
    recordKey: ValueKey('sale-history-entry-${sale.id}'),
    title: sale.receiptNumber,
    titleKey: ValueKey('sale-history-receipt-${sale.id}'),
    attributes: <RecordAttribute>[
      // Twice an ordinary share, because it is a currency code and an amount
      // where its neighbours are one figure each. The first render wrapped
      // `KES 285.00` against the discount beside it.
      RecordAttribute(
        label: 'Total',
        value: '${sale.currency} ${_money(sale.totalMinor)}',
        kind: RecordValueKind.money,
        valueKey: ValueKey('sale-history-total-${sale.id}'),
        flex: 2,
      ),
      // Its own column rather than a clause on the total, because a discount is
      // the fact a person scans a page of sales for and "after 5.00 discount"
      // is unscannable at the end of another figure. Silent where there was
      // none: a discount of nothing is not a discount.
      if (sale.discountMinor > 0)
        RecordAttribute(
          label: 'Discount',
          value: _money(sale.discountMinor),
          kind: RecordValueKind.money,
          valueKey: ValueKey('sale-history-discount-${sale.id}'),
        ),
      RecordAttribute(
        label: 'Items',
        value: '${sale.lines.length}',
        kind: RecordValueKind.code,
        valueKey: ValueKey('sale-history-items-${sale.id}'),
      ),
      RecordAttribute(
        label: 'Sold',
        value: sale.lines
            .map(
              (line) =>
                  '${line.quantity} x ${tenantProductLabel(line.name, line.sku)}',
            )
            .join(', '),
        valueKey: ValueKey('sale-history-lines-${sale.id}'),
        flex: 2,
      ),
      // **`Not recorded` is the totals page's own word for the same absence**,
      // rather than a second vocabulary invented here for the same fact. The
      // sentence that used to be appended to every one of these values is under
      // the list now; see the note there for why.
      RecordAttribute(
        label: 'Payment',
        value: tenantSalePaymentLabel(sale),
        valueKey: ValueKey('sale-history-tender-${sale.id}'),
      ),
      // **Only when the till named somebody.** A walk-in is the ordinary sale,
      // and a row reading *Customer: Walk-in* on most of a day's sales is a
      // label with nothing in it.
      if (sale.customer case final customer?)
        RecordAttribute(
          label: 'Customer',
          value: customer.name,
          valueKey: ValueKey('sale-history-customer-${sale.id}'),
        ),
    ],
    provenance: _recordedAtLabel(
      sale,
      tenantStaffLabel(
        sale.soldById,
        names: staffNames,
        selfUid: selfUid ?? '',
      ),
    ),
    provenanceKey: ValueKey('sale-history-recorded-at-${sale.id}'),
    actions: <RecordAction>[
      RecordAction(
        label: 'View returns',
        actionKey: ValueKey('sale-history-returns-link-${sale.id}'),
        onPressed: () => onViewReturns?.call(sale),
      ),
    ],
  );
}

String _recordedLabel(TenantShiftSaleHistoryRequest request) {
  final count = request.recordedTransactionCount;
  final total = request.recordedTotalSalesMinor;
  if (count == null || total == null) {
    return 'This shift closed without a recorded summary. Counted cash was '
        '${_money(request.countedCashMinor)}.';
  }
  return 'Recorded: ${_money(total)} over $count transactions. Counted cash '
      'was ${_money(request.countedCashMinor)}.';
}

String _recordedAtLabel(TenantSale sale, String soldByLabel) {
  final recordedAt = sale.recordedAt;
  // When it was rung up, once the server holds it. A sale sent late reached
  // the server hours after the customer paid, and this line is about the
  // customer.
  return recordedAt == null
      ? 'The server has not confirmed this sale yet.'
      : 'Recorded ${_instant(sale.rungAt ?? recordedAt)} by $soldByLabel';
}

String _money(int minorUnits) => moneyTextOfMinor(minorUnits);

String _instant(DateTime value) {
  final utc = value.toUtc();
  String pad(int part) => part.toString().padLeft(2, '0');
  return '${utc.year}-${pad(utc.month)}-${pad(utc.day)} '
      '${pad(utc.hour)}:${pad(utc.minute)} UTC';
}
