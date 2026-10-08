import 'package:flutter/material.dart';

import '../checkout/checkout_draft.dart';
import '../checkout/checkout_receipt.dart';
import '../sales/sale_history.dart';
import '../inventory/product_image_cache.dart';
import '../reports/analysis/returns_analysis.dart';
import '../reports/analysis/returns_report.dart';
import '../reports/report_document.dart';
import '../reports/report_file.dart';
import '../reports/report_identity_source.dart';
import '../reports/report_people.dart';
import '../reports/report_period.dart';
import '../reports/report_run.dart';
import '../reports/ui/report_action.dart';
import '../tenancy/tenant_catalog.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../tenancy/tenant_staff_names.dart';
import '../ui/buttons.dart';
import '../ui/card.dart';
import '../ui/dialogs.dart';
import '../ui/fields.dart';
import '../ui/money_text.dart';
import '../ui/pagination.dart';
import '../ui/routes.dart';
import '../ui/scaffold.dart';
import '../ui/snackbar.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'return_actions.dart';
import 'return_history.dart';
import 'return_journal.dart';
import 'return_offsets.dart';
import 'return_verification.dart';
import '../observability/app_telemetry.dart';

/// Business-wide return history reached from the home screen.
final class TenantReturnFeedScreen extends StatelessWidget {
  const TenantReturnFeedScreen({
    super.key,
    required this.reader,
    this.actions,
    this.clock,
    this.reportSaver,
    this.imageCache,
  });

  final TenantDataReader reader;
  final TenantReturnActions? actions;

  /// Where a generated report goes. Null renders no toolbar control at all.
  final TenantReportSaver? reportSaver;

  /// Fetches the logo the report's branding band draws.
  final TenantImageCache? imageCache;

  /// What "today" means to the day filter. Absent, the wall clock.
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Returns',
    subtitle: 'All returns recorded by this business',
    contentWidth: AppContentWidth.records,
    actions: <Widget>[
      TenantSessionReportAction(
        clock: clock ?? DateTime.now,
        runFor: (session) => _reportRun(session),
      ),
    ],
    body: TenantReturnFeedPanel(reader: reader, actions: actions, clock: clock),
  );

  /// Returns over a period, which the day filter cannot ask for.
  ///
  /// **Priced by reading the sales behind them.** A return line carries a
  /// product and a quantity and no money at all, exactly as this page's own
  /// `_ReturnFacts` has to work around - so the report joins to the sale for
  /// the same reason and states units alone where it cannot.
  TenantReportRun? _reportRun(TenantSession session) {
    final saver = reportSaver;
    if (saver == null) return null;
    // Every active member may review returns, which is what the rules allow
    // and what this page is already open to.
    if (!session.canAccess(
      allowedRoles: TenantReturnHistoryRepository.allowedRoles,
    )) {
      return null;
    }

    final now = clock ?? DateTime.now;
    return TenantReportRun(
      kind: TenantReportKind.returns,
      support: TenantReportPeriodSupport.range,
      saver: saver,
      build: (period) async {
        final source = TenantReturnsReportSource(
          repository: TenantReturnHistoryRepository(
            session: session,
            reader: reader,
          ),
          sales: TenantSaleHistoryRepository(session: session, reader: reader),
        );
        final read = await source.gather(period);
        final valuation = await source.value(read.returns);
        final previous = await source.gatherPrevious(period);
        final identity = await readTenantReportIdentity(
          session: session,
          reader: reader,
          generatedAt: now(),
          imageCache: imageCache,
        );
        final analysis = TenantReturnsAnalysis.from(
          period: period,
          returns: read.returns,
          valuation: valuation,
          previous: previous,
          truncated: read.truncated,
        );
        return describeReturnsReport(
          identity: identity,
          analysis: analysis,
          // **Resolved after the analysis**, because only then is it known
          // which people the report will actually list. Grouping stays on the
          // UID; the name is a label put on at the last moment, and a cashier
          // reading this will see its colleagues by UID exactly as this page
          // already shows them.
          people: await readTenantReportPeople(
            session: session,
            reader: reader,
            uids: analysis.recorders
                .take(TenantReturnsAnalysis.listed)
                .map((person) => person.staffId),
          ),
        );
      },
    );
  }
}

final class _ReturnFeedView {
  const _ReturnFeedView({
    required this.page,
    required this.names,
    required this.facts,
  });

  final TenantReturnPage page;
  final Map<String, String> names;

  /// What the sale behind each return says about it, by return ID.
  final Map<String, _ReturnFacts> facts;
}

/// The three things a return can only learn from the sale it reverses.
///
/// **Read here rather than written onto the return.** A return document's key
/// set is frozen by the create rule, and the receipt, the hour of the sale and
/// the money are all already recorded once - on the immutable sale. One direct
/// read per sale on the page is the cost of not storing a fourth copy of them.
final class _ReturnFacts {
  const _ReturnFacts({
    required this.receipt,
    required this.productNames,
    required this.soldAt,
    required this.returnedMinor,
    required this.currency,
  });

  /// The receipt's trailing number, as the sales list prints it.
  final String receipt;

  /// What the sale called each product, by product ID.
  ///
  /// **The fallback that rescues every return recorded before 2026-09-06.**
  /// Those carry no `productName` of their own, and a 40-character document ID
  /// as a card's headline is worse than useless - it was the first thing the
  /// product owner saw on a device. The sale is already being read for the
  /// receipt and the hour, and it names every product it sold, so the history
  /// reads properly with no backfill and no second write.
  final Map<String, String> productNames;

  /// When the customer bought what they have just brought back.
  final DateTime? soldAt;

  /// What this one return handed back, priced against the sale's own lines.
  ///
  /// Null where the return cannot be priced against its sale at all - a line
  /// naming a product the sale never sold. **Absent rather than wrong**: an
  /// amount is a figure a shop acts on, and there is no honest guess at one.
  final int? returnedMinor;

  final String currency;
}

/// Tenant-scoped, paged history of returns across every sale.
final class TenantReturnFeedPanel extends StatefulWidget {
  const TenantReturnFeedPanel({
    super.key,
    required this.reader,
    this.actions,
    this.pageSize = 20,
    this.requestIdFactory,
    this.clock,
  });

  final TenantDataReader reader;
  final TenantReturnActions? actions;
  final int pageSize;
  final String Function()? requestIdFactory;

  /// What "today" means to the day filter. Absent, the wall clock.
  final DateTime Function()? clock;

  @override
  State<TenantReturnFeedPanel> createState() => _TenantReturnFeedPanelState();
}

final class _TenantReturnFeedPanelState extends State<TenantReturnFeedPanel> {
  List<String?> _cursors = <String?>[null];
  int _pageIndex = 0;
  int _generation = 0;
  bool _busy = false;

  /// The day the reversal was taken. Exactly one day, always.
  ///
  /// **Today, on the product owner's call of 2026-09-06.** A returns screen is
  /// opened to answer "what came back today" far more often than "what has ever
  /// come back".
  ///
  /// **And no "every day" reading, as of 2026-09-21.** The control was three
  /// fixed options - today, yesterday, all dates - and is a date picker now, so
  /// every day is reachable and exactly one is ever applied. The sentinel that
  /// stood for "all dates" went with it, and so did the reason it was kept: that
  /// returns predating `recordedOn` had no day and would otherwise be
  /// unreachable. That expired when the field became required (#110), on the
  /// finding that SIT holds no such return.
  late String _recordedOn;

  /// The standing shown, or null for every standing.
  TenantReturnStatus? _standing;

  @override
  void initState() {
    super.initState();
    _recordedOn = _today;
  }

  String get _today =>
      checkoutBusinessDate((widget.clock?.call() ?? DateTime.now()).toUtc());

  void _setRecordedOn(String value) {
    if (value == _recordedOn) return;
    setState(() {
      _recordedOn = value;
      _resetPages();
    });
  }

  void _setStanding(TenantReturnStatus? value) {
    if (value == _standing) return;
    setState(() {
      _standing = value;
      _resetPages();
    });
  }

  void _resetPages() {
    _cursors = <String?>[null];
    _pageIndex = 0;
    _generation++;
  }

  /// Reports one write outcome, over the screen rather than inside the page.
  ///
  /// See `showAppSnackBar`: since 2026-09-03 every outcome goes there, and
  /// inline text is left to the one thing it is still right for - a field
  /// saying what is wrong with what was typed into it.
  void _report(AppNotice notice) => showAppSnackBar(context, notice);

  final TenantStaffNameResolvers _staffNames = TenantStaffNameResolvers();
  String? _loaderKey;
  TenantGuardedLoader<_ReturnFeedView>? _loader;
  TenantGuardedLoader<_ReturnFeedView>? _loaderCached;

  static String _sessionKey(TenantSession session) =>
      '${session.uid}:${session.tenantId}:${session.epoch}';

  /// One resolver per session **and per pass**, so the cached pass resolves a
  /// name from this device rather than putting a network read in front of
  /// records it already holds. An unresolved name degrades to the UID.
  TenantStaffNameResolver _resolverFor(
    TenantSession session,
    TenantDocumentReader reader,
  ) => _staffNames.of(session: session, reader: reader);

  bool _stillCurrent(String capturedKey) {
    if (!mounted) return false;
    final current = TenantSessionScope.of(context).session;
    return current != null && _sessionKey(current) == capturedKey;
  }

  void _next(String? cursor) {
    if (cursor == null) return;
    setState(() {
      _cursors = <String?>[..._cursors.take(_pageIndex + 1), cursor];
      _pageIndex++;
    });
  }

  void _previous() {
    if (_pageIndex == 0) return;
    setState(() => _pageIndex--);
  }

  void _reload() {
    setState(() {
      _cursors = <String?>[null];
      _pageIndex = 0;
      _generation++;
    });
  }

  void _composeLoaders(String key) {
    if (_loaderKey == key && _loader != null) return;
    _loaderKey = key;
    final cursor = _cursors[_pageIndex];
    final recordedOn = _recordedOn;
    final standing = _standing;
    TenantGuardedLoader<_ReturnFeedView> readWith(TenantDataReader reader) =>
        (session) async {
          final page =
              await TenantReturnHistoryRepository(
                session: session,
                reader: reader,
              ).loadReturns(
                pageSize: widget.pageSize,
                cursor: cursor,
                recordedOn: recordedOn,
                status: standing,
              );
          final names = await _resolverFor(session, reader).resolve(
            page.items.expand(
              (record) => <String>[
                record.createdBy,
                if (record.verification case final verification?)
                  verification.verifiedBy,
              ],
            ),
          );
          return _ReturnFeedView(
            page: page,
            names: names,
            facts: await _readFacts(session, reader, page),
          );
        };
    _loader = readWith(widget.reader);
    final cache = widget.reader.cached;
    _loaderCached = cache == null ? null : readWith(cache);
  }

  /// Reads the sale behind every return on [page], once per sale.
  ///
  /// **A sale that cannot be read costs a label, not the page.** Unlike the
  /// takings on the Sales Report - where a return nobody can price makes the
  /// day's figure wrong - everything here is a caption beside a record that is
  /// already on screen, so a missing sale drops back to the return's own IDs
  /// rather than taking the whole returns history down with it.
  Future<Map<String, _ReturnFacts>> _readFacts(
    TenantSession session,
    TenantDataReader reader,
    TenantReturnPage page,
  ) async {
    final saleIds = page.items
        .map((record) => record.saleId)
        .toSet()
        .toList(growable: false);
    if (saleIds.isEmpty) return const <String, _ReturnFacts>{};
    final repository = TenantSaleHistoryRepository(
      session: session,
      reader: reader,
    );
    final sales = <String, TenantSale>{};
    final read = await Future.wait<TenantSale?>(
      saleIds.map((id) async {
        try {
          return await repository.readSale(id);
        } catch (error, stackTrace) {
          AppTelemetry.captureHandled(
            error,
            stackTrace,
            boundary: 'returns.feed_sale_read',
          );
          return null;
        }
      }),
    );
    for (final (index, sale) in read.indexed) {
      if (sale != null) sales[saleIds[index]] = sale;
    }

    final facts = <String, _ReturnFacts>{};
    for (final record in page.items) {
      final sale = sales[record.saleId];
      if (sale == null) continue;
      int? returnedMinor;
      try {
        returnedMinor = describeReturnOffset(sale, <String, int>{
          for (final line in record.lines) line.productId: line.quantity,
        }).returnedMinor;
      } on TenantReturnException {
        returnedMinor = null;
      }
      facts[record.id] = _ReturnFacts(
        productNames: <String, String>{
          for (final line in sale.lines)
            line.productId: tenantProductLabel(line.name, line.sku),
        },
        receipt:
            '#'
            '${sale.receiptSequence.toString().padLeft(checkoutReceiptSequenceDigits, '0')}',
        soldAt: sale.rungAt ?? sale.recordedAt,
        returnedMinor: returnedMinor,
        currency: sale.currency,
      );
    }
    return facts;
  }

  Future<void> _verify(TenantSession session, TenantReturn record) async {
    final callable = widget.actions?.verifyCallable;
    if (callable == null || _busy) return;
    final capturedKey = _sessionKey(session);
    setState(() {
      _busy = true;
    });
    try {
      final gateway = TenantReturnVerificationGateway(
        session: session,
        target: record,
        callable: callable,
        requestIdFactory: widget.requestIdFactory,
      );
      final result = await gateway.submit(gateway.createIntent());
      if (!_stillCurrent(capturedKey)) return;
      _report(
        AppNotice.confirmed(
          'Verified this return and restored ${result.restoredUnits} '
          '${result.restoredUnits == 1 ? 'unit' : 'units'}.',
        ),
      );
      _reload();
    } on TenantReturnVerificationException catch (error) {
      if (!_stillCurrent(capturedKey)) return;
      _report(_verificationFailureNotice(error.failure));
      if (error.mayHaveCommitted) _reload();
    } on FormatException {
      if (!_stillCurrent(capturedKey)) return;
      _report(
        const AppNotice.unknown(
          'The verification response could not be trusted. The returns list '
          'has been reloaded so the server can show what happened.',
        ),
      );
      _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cursor = _cursors[_pageIndex];
    final guardKey =
        'return-feed:$_generation:$_pageIndex:$cursor:$_recordedOn:'
        '${_standing?.wireValue ?? '-'}';
    _composeLoaders(guardKey);
    return TenantRouteGuard<_ReturnFeedView>(
      load: _loader!,
      loadCached: _loaderCached,
      holdsNothing: (view) => view.page.items.isEmpty,
      denied: const Center(
        key: ValueKey('return-feed-denied'),
        child: Text('Returns are unavailable for this business.'),
      ),
      failure: (context, error) => const Center(
        key: ValueKey('return-feed-failure'),
        child: Text('Returns could not be loaded.'),
      ),
      builder: (context, session, view) => _ReturnFeedContents(
        view: view,
        selfUid: session.uid,
        pageIndex: _pageIndex,
        busy: _busy,
        recordedOn: _recordedOn,
        today: _today,
        standing: _standing,
        onRecordedOnChanged: _setRecordedOn,
        onStandingChanged: _setStanding,
        canVerify:
            widget.actions?.verifyCallable != null &&
            TenantReturnVerificationGateway.canVerifyInSession(session),
        onPrevious: _previous,
        onNext: () => _next(view.page.nextCursor),
        onVerify: (record) => _verify(session, record),
      ),
    );
  }
}

final class _ReturnFeedContents extends StatelessWidget {
  const _ReturnFeedContents({
    required this.view,
    required this.selfUid,
    required this.pageIndex,
    required this.busy,
    required this.recordedOn,
    required this.today,
    required this.standing,
    required this.onRecordedOnChanged,
    required this.onStandingChanged,
    required this.canVerify,
    required this.onPrevious,
    required this.onNext,
    required this.onVerify,
  });

  final _ReturnFeedView view;
  final String selfUid;
  final int pageIndex;
  final bool busy;

  /// The day filter's value, and the latest day it may name.
  final String recordedOn;
  final String today;

  /// The standing filter's value. Null is every standing.
  final TenantReturnStatus? standing;

  final ValueChanged<String> onRecordedOnChanged;
  final ValueChanged<TenantReturnStatus?> onStandingChanged;

  final bool canVerify;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<TenantReturn> onVerify;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final page = view.page;
    return PagedListView(
      listKey: const ValueKey('return-feed'),
      padding: EdgeInsets.all(tokens.spacing.s20),
      pagination: Pagination(
        pageNumber: pageIndex + 1,
        previousKey: const ValueKey('return-feed-previous'),
        nextKey: const ValueKey('return-feed-next'),
        onPrevious: pageIndex > 0 ? onPrevious : null,
        onNext: page.hasMore ? onNext : null,
        endOfList: !page.hasMore,
      ),
      children: <Widget>[
        // **Two filters, and they are the screen's own furniture.** Like the
        // Sales Report's date and staff pair they are drawn before anything is
        // read and stay put through a reload, because what a person is looking
        // *at* must not wait on the answer.
        _Filters(
          recordedOn: recordedOn,
          today: today,
          standing: standing,
          onRecordedOnChanged: onRecordedOnChanged,
          onStandingChanged: onStandingChanged,
        ),
        SizedBox(height: tokens.spacing.s16),
        // **The pending and verified tiles are gone too, 2026-09-22.** The
        // paragraph and the counts sentence went on 2026-09-04 and left a pair
        // of figures behind; those are now gone at the developer's direction.
        // Neither was a total for the business - both counted the page in hand
        // - and every card below already wears its own standing, so the pair
        // restated in two tiles what the list says row by row.
        // **Day headings and cards, not a record table, since 2026-08-26.**
        // The old till grouped its returns under *Today*, *Yesterday* and then
        // a date, and drew each one as a card with a tinted glyph for its
        // standing. A `RecordList` states the same facts in the same order and
        // reads as a ledger: nothing on the row is louder than anything else,
        // so a person scanning for the odd return has to read every one.
        if (page.items.isEmpty)
          // **A filter that matched nothing is not a business with no
          // returns**, and telling a manager "no returns yet" about a shop
          // that has taken hundreds would be the screen lying about its own
          // controls.
          // **One empty state, because there is only one thing it can mean.**
          // A day is always applied now, so an empty page is never "this
          // business has never taken a return" - it is "none on this day", and
          // saying the first about a shop that has taken hundreds would be the
          // screen lying about its own controls. The `return-feed-empty` key
          // went with the reading it named.
          EmptyState(
            key: const ValueKey('return-feed-no-matches'),
            title: 'No returns on $recordedOn',
            hint: standing == null
                ? 'Pick another day to look at.'
                : 'Try another day, or every standing.',
            illustration: 'file-search.svg',
          )
        else
          for (final day in _byDay(page.items)) ...<Widget>[
            // **An eyebrow and a rule, not a bright green heading.** The day
            // was set in the action colour at `title.md` bold, which made the
            // dates the loudest thing on a page whose subject is the returns
            // under them.
            Padding(
              padding: EdgeInsets.only(bottom: tokens.spacing.s12),
              child: Row(
                children: <Widget>[
                  Text(
                    day.label,
                    key: ValueKey('return-feed-day-${day.key}'),
                    style: tokens.typography.labelEyebrow.copyWith(
                      color: tokens.colors.text.tertiary,
                    ),
                  ),
                  SizedBox(width: tokens.spacing.s12),
                  Expanded(
                    child: Divider(
                      height: 0,
                      color: tokens.colors.surface.cardEdge,
                    ),
                  ),
                ],
              ),
            ),
            for (final record in day.records) ...<Widget>[
              _ReturnCard(
                record: record,
                facts: view.facts[record.id],
                who: _label(record.createdBy),
                onOpen: () => _openJournal(context, record),
                onVerify: !record.isVerified && canVerify && !busy
                    ? () => _confirmVerification(context, record)
                    : null,
              ),
              SizedBox(height: tokens.spacing.s12),
            ],
          ],
        // **A footnote rather than a `Callout`.** Whose job it is to verify a
        // return is policy, not a notice: it does not change, nothing is wrong
        // when it applies, and the control it explains is simply not drawn. It
        // was three lines in an `info` container above every card on the page.
        if (!canVerify) ...<Widget>[
          SizedBox(height: tokens.spacing.s16),
          Text(
            key: const ValueKey('return-feed-verification-unavailable'),
            'Only an owner, administrator or manager can verify a return.',
            style: tokens.typography.caption.copyWith(
              color: tokens.colors.text.tertiary,
            ),
          ),
        ],
      ],
    );
  }

  /// Opens the journal page for one return.
  ///
  /// **No session travels with it and none is needed.** The page is handed the
  /// record it draws and reads nothing, so it takes a plain route rather than a
  /// `TenantSessionScope` - the guard that produced this row is the guard.
  ///
  /// Verifying from the page comes back here rather than acting there: the
  /// confirmation, the callable and the refresh all already live on this panel,
  /// and a second copy on the journal would be a second place for them to
  /// disagree.
  Future<void> _openJournal(BuildContext context, TenantReturn record) =>
      Navigator.of(context).push<void>(
        AppPageRoute<void>(
          builder: (routeContext) => TenantReturnJournalScreen(
            record: record,
            staffNames: view.names,
            productNames:
                view.facts[record.id]?.productNames ?? const <String, String>{},
            receipt: view.facts[record.id]?.receipt,
            selfUid: selfUid,
            onVerify: !record.isVerified && canVerify && !busy
                ? () {
                    Navigator.of(routeContext).pop();
                    _confirmVerification(context, record);
                  }
                : null,
          ),
        ),
      );

  Future<void> _confirmVerification(
    BuildContext context,
    TenantReturn record,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Restore this stock?',
      consequence:
          'This verifies the return and adds '
          '${record.lines.map((line) => _lineLabel(line, view.facts[record.id]?.productNames ?? const <String, String>{})).join(', ')} '
          'back to stock.',
      stillTrue: 'It cannot be undone from this app.',
      confirmLabel: 'Verify and restore',
      confirmKey: const ValueKey('return-feed-confirm-verify'),
      cancelKey: const ValueKey('return-feed-cancel-verify'),
    );
    if (confirmed) onVerify(record);
  }

  String _label(String uid) =>
      tenantStaffLabel(uid, names: view.names, selfUid: selfUid);
}

AppNotice _verificationFailureNotice(TenantReturnVerificationFailure failure) =>
    switch (failure) {
      TenantReturnVerificationFailure.forbidden => const AppNotice.refused(
        'Only an owner, administrator, or manager may restore stock.',
      ),
      TenantReturnVerificationFailure.notFound => const AppNotice.refused(
        'This return no longer exists in this business.',
      ),
      TenantReturnVerificationFailure.alreadyVerified =>
        const AppNotice.offline(
          'This return was already verified, so stock was not restored twice.',
        ),
      TenantReturnVerificationFailure.exceedsSale => const AppNotice.refused(
        'This return exceeds what the original sale allows.',
      ),
      TenantReturnVerificationFailure.missingProduct => const AppNotice.refused(
        'A returned product no longer exists, so stock cannot be restored.',
      ),
      TenantReturnVerificationFailure.missingSale => const AppNotice.refused(
        'The original sale is missing, so stock cannot be restored.',
      ),
      TenantReturnVerificationFailure.tooManyVerifications =>
        const AppNotice.refused('This sale needs a manual stock adjustment.'),
      TenantReturnVerificationFailure.refused => const AppNotice.refused(
        'The return was refused and no stock was restored.',
      ),
      TenantReturnVerificationFailure.ambiguous => const AppNotice.unknown(
        'The result is unknown. The returns list has been reloaded.',
      ),
      TenantReturnVerificationFailure.unavailable => const AppNotice.offline(
        'The server could not be reached, so no stock was restored.',
      ),
    };

/// What one returned line is called.
///
/// Three sources in order of authority: the name the **return** recorded, the
/// name the **sale** recorded, and - only when neither exists - the product ID,
/// which is at least unambiguous.
String _lineLabel(
  TenantReturnLine line, [
  Map<String, String> fromSale = const <String, String>{},
]) =>
    '${line.quantity} x '
    '${line.label ?? fromSale[line.productId] ?? line.productId}';

/// One return, as the old till drew one.
///
/// A tinted glyph for its standing, the units it took back, its reason, and
/// who recorded it when. §9 keeps the standing a **word** in the trailing
/// column as well as a colour on the glyph.
/// The day a return was taken, and the standing it is in.
///
/// **Exact values, not a range, and that is the read boundary's rule rather
/// than a simplification.** `TenantReadRepository` refuses a range filter, so
/// a period control here would have to be a client-side sieve over one page -
/// which would quietly hide records rather than not match them.
final class _Filters extends StatelessWidget {
  const _Filters({
    required this.recordedOn,
    required this.today,
    required this.standing,
    required this.onRecordedOnChanged,
    required this.onStandingChanged,
  });

  final String recordedOn;
  final String today;
  final TenantReturnStatus? standing;
  final ValueChanged<String> onRecordedOnChanged;
  final ValueChanged<TenantReturnStatus?> onStandingChanged;

  /// The standing filter's value for "every standing".
  static const String _allStandings = '';

  /// Opens the day picker and reports the day chosen.
  ///
  /// **Bounded above by [today] and not by the clock.** The feed's own business
  /// date is what every record on this screen is filed under, and a day after
  /// it is a day no return can have been recorded on - so offering it would be
  /// offering a reading that is empty by construction. `_pickBusinessDate` on
  /// the sales report bounds itself the same way.
  ///
  /// The floor is 2020: returns carry a business date rather than a timestamp,
  /// and no business this app has ever served predates it.
  Future<void> _pickDay(BuildContext context) async {
    final last = DateTime.parse(today);
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(recordedOn),
      firstDate: DateTime(2020),
      lastDate: last,
      helpText: 'Returns recorded on',
    );
    if (picked == null) return;
    onRecordedOnChanged(picked.toIso8601String().substring(0, 10));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          // **A date picker since 2026-09-21, where this was a list of three.**
          // *Today*, *Yesterday* and *All dates* were the only days a person
          // could reach from this screen, so a return taken the Friday before
          // last could be found only by reading back through every page. The
          // read boundary always accepted any business date - `loadReturns`
          // takes one exact value and validates it - so the three options were
          // the control's limit and never the query's.
          //
          // **The caption above it went with them.** A button showing a date
          // behind a calendar glyph does not need the word *Recorded* over it,
          // which is the same redundancy the other filters on this screen shed
          // on the same day. It keeps the word as its announcement, because
          // `AppButton` has no `semanticLabel` and a button reading only
          // `2026-09-21` says nothing about what pressing it does.
          child: Semantics(
            key: const ValueKey('return-feed-day-filter'),
            label: 'Returns recorded on $recordedOn. Change the day.',
            button: true,
            excludeSemantics: true,
            child: AppButton(
              key: const ValueKey('return-feed-day-picker'),
              label: recordedOn,
              icon: Icons.calendar_today_outlined,
              tier: AppButtonTier.secondary,
              expand: true,
              onPressed: () => _pickDay(context),
            ),
          ),
        ),
        SizedBox(width: tokens.spacing.s12),
        Expanded(
          child: AppSelect<String>(
            key: const ValueKey('return-feed-standing-filter'),
            value: standing?.wireValue ?? _allStandings,
            label: 'Standing',
            // The day control is a button now rather than a second well with a
            // glyph in it, so this one can afford the glyph that lets its own
            // caption go - the pair that `AppSelect.dense` asks for.
            dense: true,
            leading: Icons.filter_alt_outlined,
            items: <AppSelectItem<String>>[
              const AppSelectItem<String>(
                key: ValueKey('return-feed-standing-all'),
                value: _allStandings,
                label: 'All types',
              ),
              AppSelectItem<String>(
                key: const ValueKey('return-feed-standing-pending'),
                value: TenantReturnStatus.pending.wireValue,
                label: 'Pending',
              ),
              AppSelectItem<String>(
                key: const ValueKey('return-feed-standing-verified'),
                value: TenantReturnStatus.verified.wireValue,
                label: 'Verified',
              ),
            ],
            onChanged: (value) => onStandingChanged(
              value == null || value == _allStandings
                  ? null
                  : TenantReturnStatus.values.firstWhere(
                      (status) => status.wireValue == value,
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One return, as the old till drew one and then some.
///
/// **Rebuilt on 2026-09-06**, on three things the product owner asked for in
/// one breath: the *item* rather than a document ID, the receipt's trailing
/// number rather than the sale's, and the hour the goods were sold beside the
/// hour they came back. The first is a write - see
/// [TenantReturnRequestLine.name] - and the other two come off the sale, which
/// is what [_ReturnFacts] is.
///
/// **The money belongs here and not on the sale card.** That is the same
/// decision, read the other way round: what came back stopped being part of
/// the sale, so the sale card states only its own net figure and this card
/// states what was handed over.
///
/// The layout is three bands under one glyph — what came back, when it moved,
/// and who said so — because a return is read as a sequence of events and the
/// old single column made every line weigh the same.
final class _ReturnCard extends StatelessWidget {
  const _ReturnCard({
    required this.record,
    required this.facts,
    required this.who,
    required this.onOpen,
    required this.onVerify,
  });

  final TenantReturn record;

  /// What the sale said. Null where it could not be read - see `_readFacts`.
  final _ReturnFacts? facts;

  final String who;
  final VoidCallback onOpen;
  final VoidCallback? onVerify;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final status = record.isVerified
        ? tokens.colors.status.ok
        : tokens.colors.status.attention;
    final sale = facts;
    return AppCard(
      key: ValueKey('return-feed-entry-${record.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _StandingTile(record: record, tokens: tokens),
              SizedBox(width: tokens.spacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // **The goods, which is what a person is looking for.** It
                    // was a unit count, and the count is still here - one line
                    // down, where a number belongs beside the money.
                    Text(
                      record.lines
                          .map(
                            (line) => _lineLabel(
                              line,
                              sale?.productNames ?? const <String, String>{},
                            ),
                          )
                          .join(', '),
                      key: ValueKey('return-feed-subject-${record.id}'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.typography.bodyLarge.copyWith(
                        color: tokens.colors.text.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: tokens.spacing.s4),
                    // **The receipt, not the sale's document ID.** A person
                    // holding the paper can match this; nobody can match a
                    // `co_1f3a…`.
                    // **Three facts that flow, rather than three that
                    // compete.** These were a `Row` whose only flexible child
                    // was the receipt, so on a phone the receipt was the one
                    // thing that gave way - a card reading `#0` and an ellipsis
                    // beside a whole unit count and a whole amount. It is the
                    // fact somebody holding the paper is matching against, and
                    // the shortest of the three; it must never be the one that
                    // is cut. A `Wrap` takes a second line instead, and still
                    // bounds each child to the card, so the long fallback below
                    // cannot run off the edge either.
                    Wrap(
                      spacing: tokens.spacing.s8,
                      runSpacing: tokens.spacing.s4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              Icons.receipt_long_outlined,
                              size: 14,
                              color: tokens.colors.text.tertiary,
                            ),
                            SizedBox(width: tokens.spacing.s4),
                            Text(
                              sale?.receipt ?? record.saleId,
                              key: ValueKey('return-feed-sale-${record.id}'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tokens.typography.mono.copyWith(
                                color: tokens.colors.text.tertiary,
                                fontSize: tokens.typography.caption.fontSize,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${record.returnedUnits} '
                          '${record.returnedUnits == 1 ? 'unit' : 'units'}',
                          key: ValueKey('return-feed-units-${record.id}'),
                          style: tokens.typography.caption.copyWith(
                            color: tokens.colors.text.tertiary,
                          ),
                        ),
                        if (sale?.returnedMinor case final minor?)
                          Text(
                            '${sale!.currency} ${_money(minor)}',
                            key: ValueKey('return-feed-value-${record.id}'),
                            style: tokens.typography.numericBody.copyWith(
                              color: tokens.colors.text.money,
                              fontSize: tokens.typography.caption.fontSize,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: tokens.spacing.s8),
              Text(
                record.isVerified ? 'VERIFIED' : 'PENDING',
                key: ValueKey('return-feed-status-${record.id}'),
                style: tokens.typography.labelEyebrow.copyWith(
                  color: status.fg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.s12),
          Divider(height: 1, color: tokens.colors.surface.borderSubtle),
          SizedBox(height: tokens.spacing.s12),
          // **Sold, then returned, in that order and on one line.** The old
          // till put the hour of the return on its card and nothing else, so
          // "did this come back the same evening or three weeks later" - the
          // question a shopkeeper actually asks of a return - could not be
          // answered from the list at all.
          // **It flows for the same reason the facts line above it does.**
          // Two labelled instants and an arrow do not fit across a phone, and
          // as a `Row` they did not ellipsize - they ran off the edge, which
          // takes one of the two hours out of sight entirely. The arrow leads
          // the second run rather than ending the first, so a wrapped card
          // still reads *Sold ... -> Returned ...* in that order.
          Wrap(
            key: ValueKey('return-feed-recorded-${record.id}'),
            spacing: tokens.spacing.s8,
            runSpacing: tokens.spacing.s4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              _Moment(
                icon: Icons.shopping_bag_outlined,
                label: 'Sold',
                at: sale?.soldAt,
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.arrow_forward,
                    size: 14,
                    color: tokens.colors.text.tertiary,
                  ),
                  SizedBox(width: tokens.spacing.s8),
                  _Moment(
                    icon: Icons.assignment_return_outlined,
                    label: 'Returned',
                    at: record.recordedAt,
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.s8),
          Text(
            record.reason,
            key: ValueKey('return-feed-reason-${record.id}'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: tokens.typography.bodyMedium.copyWith(
              color: tokens.colors.text.secondary,
            ),
          ),
          // **A pending return has already moved the money and has not yet
          // moved the stock, and only one of those halves was ever on screen.**
          // The takings net a return the moment a cashier files it - the
          // product owner's call of 2026-09-06, so the figures agree with what
          // the cashier just did - while the server restores stock only once a
          // manager has verified the goods really are back. Both halves are
          // right. What is wrong is the reading a person forms from watching
          // the amount come off and assuming the shelf came with it, and the
          // cure for that is to say so on the card where the belief is formed,
          // not to move stock nobody has confirmed.
          if (!record.isVerified) ...<Widget>[
            SizedBox(height: tokens.spacing.s8),
            Row(
              key: ValueKey('return-feed-stock-note-${record.id}'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.inventory_2_outlined,
                  size: 14,
                  color: tokens.colors.status.attention.fg,
                ),
                SizedBox(width: tokens.spacing.s4),
                Expanded(
                  child: Text(
                    'Already off the takings. The stock comes back when this '
                    'is verified.',
                    style: tokens.typography.caption.copyWith(
                      color: tokens.colors.status.attention.fg,
                    ),
                  ),
                ),
              ],
            ),
          ],
          SizedBox(height: tokens.spacing.s12),
          Row(
            children: <Widget>[
              Icon(
                Icons.person_outline,
                size: 16,
                color: tokens.colors.text.tertiary,
              ),
              SizedBox(width: tokens.spacing.s4),
              Expanded(
                child: Text(
                  who,
                  key: ValueKey('return-feed-actor-${record.id}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.typography.caption.copyWith(
                    color: tokens.colors.text.tertiary,
                  ),
                ),
              ),
              if (onVerify case final verify?) ...<Widget>[
                AppIconButton(
                  key: ValueKey('return-feed-verify-${record.id}'),
                  icon: Icons.verified_outlined,
                  semanticLabel: 'Verify this return and restore its stock',
                  onPressed: verify,
                ),
                SizedBox(width: tokens.spacing.s8),
              ],
              AppIconButton(
                key: ValueKey('return-feed-open-${record.id}'),
                icon: Icons.visibility_outlined,
                semanticLabel: 'View this return',
                onPressed: onOpen,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One labelled instant, or an honest dash where there is none.
///
/// A server timestamp is absent while a write is still on its way, and the
/// sale's is absent when this device could not read the sale. Neither is a
/// reason to guess an hour onto a record of money moving.
final class _Moment extends StatelessWidget {
  const _Moment({required this.icon, required this.label, required this.at});

  final IconData icon;
  final String label;
  final DateTime? at;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final value = at;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 14, color: tokens.colors.text.tertiary),
        SizedBox(width: tokens.spacing.s4),
        Text(
          '$label ',
          style: tokens.typography.caption.copyWith(
            color: tokens.colors.text.tertiary,
          ),
        ),
        Text(
          value == null ? '\u2014' : _clock(value),
          style: tokens.typography.mono.copyWith(
            color: value == null
                ? tokens.colors.text.tertiary
                : tokens.colors.text.secondary,
            fontSize: tokens.typography.caption.fontSize,
          ),
        ),
      ],
    );
  }
}

String _money(int minorUnits) => moneyTextOfMinor(minorUnits);

/// The old card's tinted glyph square.
final class _StandingTile extends StatelessWidget {
  const _StandingTile({required this.record, required this.tokens});

  final TenantReturn record;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    final status = record.isVerified
        ? tokens.colors.status.ok
        : tokens.colors.status.attention;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: status.bg,
        borderRadius: BorderRadius.circular(tokens.radius.md),
        border: Border.all(color: status.border),
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.s8),
        child: Icon(
          record.isVerified
              ? Icons.assignment_turned_in_outlined
              : Icons.assignment_return_outlined,
          size: tokens.typography.titleLarge.fontSize,
          color: status.fg,
        ),
      ),
    );
  }
}

/// One day's returns, under the heading the old screen gave them.
final class _ReturnDay {
  const _ReturnDay({
    required this.key,
    required this.label,
    required this.records,
  });

  final String key;
  final String label;
  final List<TenantReturn> records;
}

/// Groups a page by the day each return was recorded, newest day first.
///
/// **The reader's own day, not UTC.** A return recorded at 01:00 local belongs
/// to the day the person remembers it on, which is what makes *Today* mean
/// anything. A return the server has not stamped yet cannot be filed under a
/// day at all, so it keeps its own heading rather than being guessed into one.
List<_ReturnDay> _byDay(List<TenantReturn> items) {
  final undated = <TenantReturn>[];
  final days = <DateTime, List<TenantReturn>>{};
  for (final record in items) {
    final recordedAt = record.recordedAt;
    if (recordedAt == null) {
      undated.add(record);
      continue;
    }
    final local = recordedAt.toLocal();
    days
        .putIfAbsent(
          DateTime(local.year, local.month, local.day),
          () => <TenantReturn>[],
        )
        .add(record);
  }
  final ordered = days.keys.toList()..sort((a, b) => b.compareTo(a));
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return <_ReturnDay>[
    for (final day in ordered)
      _ReturnDay(
        key: _dayKey(day),
        label: _dayLabel(day, today),
        records: days[day]!,
      ),
    if (undated.isNotEmpty)
      _ReturnDay(
        key: 'undated',
        label: 'Awaiting server time',
        records: undated,
      ),
  ];
}

String _dayKey(DateTime day) =>
    '${day.year}-${_pad(day.month)}-${_pad(day.day)}';

String _dayLabel(DateTime day, DateTime today) {
  final difference = today.difference(day).inDays;
  if (difference == 0) return 'Today';
  if (difference == 1) return 'Yesterday';
  return _dayKey(day);
}

String _clock(DateTime value) {
  final local = value.toLocal();
  return '${_pad(local.hour)}:${_pad(local.minute)}';
}

String _pad(int part) => part.toString().padLeft(2, '0');
