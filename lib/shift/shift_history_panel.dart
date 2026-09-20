import 'package:flutter/material.dart';

import '../reporting/reporting_currency.dart';
import '../reporting/shift_amendment_feed.dart';
import '../reporting/shift_amendment_feed_panel.dart';
import '../returns/return_actions.dart';
import '../sales/sale_history.dart';
import '../sales/sale_history_panel.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../tenancy/tenant_staff_names.dart';
import '../ui/buttons.dart';
import '../ui/chips.dart';
import '../ui/pagination.dart';
import '../ui/routes.dart';
import '../ui/scaffold.dart';
import '../ui/sheet.dart';
import '../ui/skeleton.dart';
import '../ui/states.dart';
import '../ui/stats.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'shift_history.dart';
import 'shift_history_card.dart';

/// Read-only shift history route for the selected tenant session.
///
/// **The screen was rebuilt around the question it is opened with**, which is
/// the same move `weekly_report_panel.dart` made the day before. A manager opens
/// it to find out which shifts disagree with their sales; a cashier opens it to
/// find out whether they are clear. It used to open with five lines of prose
/// about how reconciliation works, then a chronological list in which a settled
/// shift and a shift short by a thousand were the same card with a different
/// word on it.
///
/// What replaced the prose:
///
/// - **The answer first.** A [StatRow] over the loaded page - closed, settled,
///   unresolved - and, where anything is unresolved, one [Callout] naming the
///   amounts. Nothing on the screen explains the screen.
/// - **The prose itself moved into a sheet**, opened from the toolbar. It is
///   the same four claims; it is just no longer between the title and the data.
///   See [showShiftReconciliationSheet].
/// - **A filter**, so *which three of these twenty* is a tap rather than a
///   scroll. It narrows the page in hand and says so; it is not a query.
/// - **Days are groups**, so `2026-07-31 - Brian` stops being a record title.
/// - **The difference is the figure with the weight**, and only where there is
///   one. See `shift_history_card.dart`.
final class TenantShiftHistoryScreen extends StatelessWidget {
  const TenantShiftHistoryScreen({
    super.key,
    required this.reader,
    this.returnActions,
    this.pageSize = 20,
  });

  final TenantDataReader reader;

  /// Passed through to the sales and returns routes. Recording a return stays
  /// unavailable while it is absent.
  final TenantReturnActions? returnActions;

  /// Forwarded to the panel. **Here so a test can drive the route rather than
  /// the panel inside it**, which matters now that two of this screen's controls
  /// live in the toolbar: a test that pumped the panel alone would be a test of
  /// a page that no longer exists on its own.
  final int pageSize;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Shift history',
    contentWidth: AppContentWidth.records,
    // **Both of these are chrome rather than the page's subject**, which is the
    // split `AppScaffold.actions` documents. *My recent sales* cuts across every
    // shift on the page and is not what any one row is about; *how this is
    // counted* is about the screen. Neither is what the page exists for, so
    // neither takes `primaryAction`.
    actions: <Widget>[
      Builder(
        builder: (context) => AppIconButton(
          key: const ValueKey('shift-history-own-sales'),
          icon: Icons.receipt_long_outlined,
          semanticLabel: 'My recent sales',
          bordered: false,
          tier: AppButtonTier.tertiary,
          onPressed: () => _openSales(
            context,
            const TenantOwnSaleHistoryRequest(),
            reader: reader,
            returnActions: returnActions,
          ),
        ),
      ),
      Builder(
        builder: (context) => AppIconButton(
          key: const ValueKey('shift-history-explainer'),
          icon: Icons.info_outline,
          semanticLabel: 'How a shift is reconciled',
          bordered: false,
          tier: AppButtonTier.tertiary,
          onPressed: () => showShiftReconciliationSheet(context),
        ),
      ),
    ],
    body: TenantShiftHistoryPanel(
      reader: reader,
      returnActions: returnActions,
      pageSize: pageSize,
    ),
  );
}

/// Which of the page's shifts the list is showing.
///
/// **It narrows what has been read, and never what is read.** The repository
/// pages by document ID with equality filters only, so there is no server-side
/// predicate for *disagrees with its sales* to become - and a chip that silently
/// meant "of the twenty in hand" while looking like a query would be the worst
/// of both. The chip labels carry the counts, which is what says which twenty.
enum ShiftHistoryFilter {
  all('All'),
  needsAttention('Needs attention'),
  settled('Settled');

  const ShiftHistoryFilter(this.label);

  final String label;

  bool accepts(ShiftStanding standing) => switch (this) {
    ShiftHistoryFilter.all => true,
    ShiftHistoryFilter.needsAttention => standing.needsAttention,
    ShiftHistoryFilter.settled => !standing.needsAttention,
  };
}

/// One page of closed shifts, the names behind its UIDs, and what the business
/// calls its money.
///
/// **One bundle rather than three reads the page composes**, for the reason the
/// guard exists: a tenant switch mid-flight discards the whole answer, and three
/// separately-awaited futures would give it three things to discard and three
/// chances to draw half of one session's page under another's.
@immutable
final class ShiftHistoryLoad {
  const ShiftHistoryLoad({
    required this.page,
    required this.names,
    required this.currency,
  });

  final TenantShiftHistoryPage page;
  final Map<String, String> names;
  final TenantReportingCurrency currency;
}

/// Pages closed shifts behind [TenantRouteGuard].
///
/// The guard owns authorization and stale-session rejection: a tenant switch
/// during an outstanding page discards that page before it can be rendered.
/// The panel owns only the requested scope, the cursor stack and which of the
/// page's shifts are on screen, and it never recomputes a recorded figure.
final class TenantShiftHistoryPanel extends StatefulWidget {
  const TenantShiftHistoryPanel({
    super.key,
    required this.reader,
    this.returnActions,
    this.pageSize = 20,
  });

  final TenantDataReader reader;

  /// Passed through to the sales route only. This surface never writes.
  final TenantReturnActions? returnActions;
  final int pageSize;

  @override
  State<TenantShiftHistoryPanel> createState() =>
      _TenantShiftHistoryPanelState();
}

final class _TenantShiftHistoryPanelState
    extends State<TenantShiftHistoryPanel> {
  TenantShiftHistoryScope _scope = TenantShiftHistoryScope.ownShifts;
  ShiftHistoryFilter _filter = ShiftHistoryFilter.all;

  /// The cursor that opened each visited page. The first page has none.
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

  void _setScope(TenantShiftHistoryScope scope) {
    if (scope == _scope) return;
    setState(() {
      _scope = scope;
      _cursors = <String?>[null];
      _pageIndex = 0;
    });
  }

  /// **The filter survives a scope change and dies with a page change.** Which
  /// shifts a person is looking for is a property of what they came to do;
  /// which twenty are in hand is not, and a filter that cleared itself every
  /// time the scope switched would make *Needs attention, every cashier* two
  /// taps in the wrong order.
  void _setFilter(ShiftHistoryFilter? filter) {
    if (filter == null || filter == _filter) return;
    setState(() => _filter = filter);
  }

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

  /// One loader pair per scope and page, memoised so an unrelated rebuild does
  /// not restart the read. See [TenantRouteGuard.load].
  void _composeLoaders(String key) {
    if (key == _loaderKey && _loader != null) return;
    _loaderKey = key;
    final cursor = _cursors[_pageIndex];
    TenantGuardedLoader<ShiftHistoryLoad> readWith(TenantDataReader reader) =>
        (session) async {
          final page = await TenantShiftHistoryRepository(
            session: session,
            reader: reader,
          ).loadPage(scope: _scope, pageSize: widget.pageSize, cursor: cursor);
          return ShiftHistoryLoad(
            page: page,
            names: await _resolverFor(
              session,
              reader,
            ).resolve(page.items.map((entry) => entry.staffId)),
            // **Degrades to an unlabelled figure rather than failing the
            // page.** A shift history that would not open because the business
            // never published a currency would be a reconciliation screen
            // withheld over a label; see [TenantReportingCurrency].
            currency: await TenantReportingCurrency.read(
              session: session,
              reader: reader,
            ),
          );
        };
    _loader = readWith(widget.reader);
    final cache = widget.reader.cached;
    _loaderCached = cache == null ? null : readWith(cache);
  }

  String? _loaderKey;
  TenantGuardedLoader<ShiftHistoryLoad>? _loader;
  TenantGuardedLoader<ShiftHistoryLoad>? _loaderCached;

  @override
  Widget build(BuildContext context) {
    // A new loader for a new scope or page, which is what stops an earlier
    // page completing into the current one - the guard bumps its generation
    // when this closure changes, and a late answer is discarded by it.
    _composeLoaders('${_scope.name}:$_pageIndex:${_cursors[_pageIndex]}');
    return TenantRouteGuard<ShiftHistoryLoad>(
      load: _loader!,
      loadCached: _loaderCached,
      // **Placeholder cards rather than a spinner**, because this list is what
      // the wait is for and its shape is known before its contents are. §5.1's
      // `LoadingState` stays the guard's default everywhere the shape is not.
      loading: const _ShiftHistorySkeleton(),
      denied: const Center(
        key: ValueKey('shift-history-denied'),
        child: EmptyState(
          title: 'Shift history is not available here',
          hint: 'This business does not open closed shifts to your role.',
        ),
      ),
      failure: (context, error) => const Center(
        key: ValueKey('shift-history-failure'),
        child: ErrorState(
          badgeLabel: 'Not read',
          statement: 'This page of shifts did not load',
          stillTrue:
              'Nothing has changed, and every shift is still recorded on the '
              'server.',
        ),
      ),
      builder: (context, session, load) => _ShiftHistoryContents(
        session: session,
        load: load,
        pageIndex: _pageIndex,
        filter: _filter,
        // The trail's own repository is the authority on who may read it, not
        // this surface's management set. The two happen to name the same roles
        // today, and offering a link this session's server would refuse would
        // teach a cashier nothing except that the app guesses.
        canReadCorrections: TenantShiftAmendmentFeedRepository.canReadInSession(
          session,
        ),
        onScopeChanged: _setScope,
        onFilterChanged: _setFilter,
        onNextPage: () => _nextPage(load.page.nextCursor),
        onPreviousPage: _previousPage,
        onViewSales: (request) => _openSales(
          context,
          request,
          reader: widget.reader,
          returnActions: widget.returnActions,
        ),
        onViewCorrections: (shiftId) => _openCorrections(context, shiftId),
      ),
    );
  }

  /// Opens the business's corrections trail narrowed to one shift, under the
  /// same session scope, so that route's guard sees the exact controller this
  /// page was authorized against.
  ///
  /// It needs no injected capability: the trail is a read of the same business
  /// through the same reader, so there is nothing here for a composition root to
  /// grant or withhold - the same reason the differences list opens it directly.
  void _openCorrections(BuildContext context, String shiftId) {
    final sessions = TenantSessionScope.read(context);
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => TenantSessionScope(
          controller: sessions,
          child: TenantShiftAmendmentScreen(
            reader: widget.reader,
            shiftId: shiftId,
          ),
        ),
      ),
    );
  }
}

/// Opens the read-only sales route under the same session scope, so its own
/// guard sees the exact controller this page was authorized against.
///
/// A function rather than a method because the toolbar's *My recent sales* sits
/// on the screen and the row links sit in the panel, and both push the same
/// route against the same scope.
void _openSales(
  BuildContext context,
  TenantSaleHistoryRequest request, {
  required TenantDataReader reader,
  required TenantReturnActions? returnActions,
}) {
  final sessions = TenantSessionScope.read(context);
  Navigator.of(context).push(
    AppPageRoute<void>(
      builder: (_) => TenantSessionScope(
        controller: sessions,
        child: TenantSaleHistoryScreen(
          reader: reader,
          request: request,
          returnActions: returnActions,
        ),
      ),
    ),
  );
}

final class _ShiftHistoryContents extends StatelessWidget {
  const _ShiftHistoryContents({
    required this.session,
    required this.load,
    required this.pageIndex,
    required this.filter,
    required this.canReadCorrections,
    required this.onScopeChanged,
    required this.onFilterChanged,
    required this.onNextPage,
    required this.onPreviousPage,
    required this.onViewSales,
    required this.onViewCorrections,
  });

  final TenantSession session;
  final ShiftHistoryLoad load;
  final int pageIndex;
  final ShiftHistoryFilter filter;

  /// Whether this session may read the corrections trail itself. A cashier is
  /// still told that their shift was corrected - the shift document they can
  /// already read says so, and the figures on the row are the corrected ones -
  /// but the record of who asked for it and why is the business's governance and
  /// is deliberately not theirs to read.
  final bool canReadCorrections;

  final ValueChanged<TenantShiftHistoryScope> onScopeChanged;
  final ValueChanged<ShiftHistoryFilter?> onFilterChanged;
  final VoidCallback onNextPage;
  final VoidCallback onPreviousPage;
  final ValueChanged<TenantSaleHistoryRequest> onViewSales;

  /// Opens the trail narrowed to one shift, by its document ID.
  final ValueChanged<String> onViewCorrections;

  TenantShiftHistoryPage get _page => load.page;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final items = _page.items;
    final tally = ShiftHistoryTally.of(items);
    final shown = <TenantShiftHistoryEntry>[
      for (final entry in items)
        if (filter.accepts(ShiftStanding.of(entry))) entry,
    ];
    return ListView(
      key: const ValueKey('shift-history'),
      padding: EdgeInsets.all(tokens.spacing.s20),
      children: <Widget>[
        if (TenantShiftHistoryRepository.canReadEveryCashier(session)) ...<Widget>[
          SegmentedButton<TenantShiftHistoryScope>(
            key: const ValueKey('shift-history-scope'),
            segments: const <ButtonSegment<TenantShiftHistoryScope>>[
              ButtonSegment<TenantShiftHistoryScope>(
                value: TenantShiftHistoryScope.ownShifts,
                label: Text('My shifts'),
              ),
              ButtonSegment<TenantShiftHistoryScope>(
                value: TenantShiftHistoryScope.everyCashier,
                label: Text('Every cashier'),
              ),
            ],
            selected: <TenantShiftHistoryScope>{_page.scope},
            onSelectionChanged: (selection) => onScopeChanged(selection.single),
          ),
          SizedBox(height: tokens.spacing.s20),
        ],
        if (items.isNotEmpty) ...<Widget>[
          _PageRange(items: items),
          SizedBox(height: tokens.spacing.s12),
          StatRow(
            tiles: <StatTile>[
              StatTile(
                label: 'Closed',
                value: '${tally.closed}',
                valueKey: const ValueKey('shift-history-tally-closed'),
              ),
              StatTile(
                label: 'Settled',
                value: '${tally.settled}',
                valueKey: const ValueKey('shift-history-tally-settled'),
              ),
              StatTile(
                label: 'Unresolved',
                value: '${tally.unresolved}',
                valueKey: const ValueKey('shift-history-tally-unresolved'),
              ),
            ],
          ),
          if (tally.unresolved > 0) ...<Widget>[
            SizedBox(height: tokens.spacing.s12),
            Callout(
              key: const ValueKey('shift-history-unresolved'),
              status: AppStatus.attention,
              message: tally.sentence(load.currency),
            ),
          ],
          // **Said once, and only where it is true.** Reporting never assumes a
          // currency, so a business that has published none gets bare figures
          // and one sentence saying why - rather than `KES` guessed onto a
          // screen people settle cash from.
          if (!load.currency.isKnown) ...<Widget>[
            SizedBox(height: tokens.spacing.s12),
            const Callout(
              key: ValueKey('shift-history-currency-unknown'),
              status: AppStatus.info,
              message: TenantReportingCurrency.unknownNotice,
            ),
          ],
          SizedBox(height: tokens.spacing.s20),
          FilterChipBar<ShiftHistoryFilter>(
            key: const ValueKey('shift-history-filter'),
            semanticLabel: 'Show which of this page\'s shifts',
            selected: filter,
            onSelected: onFilterChanged,
            options: <FilterChipOption<ShiftHistoryFilter>>[
              FilterChipOption<ShiftHistoryFilter>(
                key: const ValueKey('shift-history-filter-all'),
                value: ShiftHistoryFilter.all,
                label: '${ShiftHistoryFilter.all.label} ${tally.closed}',
              ),
              FilterChipOption<ShiftHistoryFilter>(
                key: const ValueKey('shift-history-filter-attention'),
                value: ShiftHistoryFilter.needsAttention,
                label:
                    '${ShiftHistoryFilter.needsAttention.label} '
                    '${tally.unresolved}',
                // A chip that would empty the list is not a filter, it is a
                // dead end with a number on it.
                enabled: tally.unresolved > 0,
              ),
              FilterChipOption<ShiftHistoryFilter>(
                key: const ValueKey('shift-history-filter-settled'),
                value: ShiftHistoryFilter.settled,
                label: '${ShiftHistoryFilter.settled.label} ${tally.settled}',
                enabled: tally.settled > 0,
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.s20),
        ],
        if (items.isEmpty)
          const EmptyState(
            key: ValueKey('shift-history-empty'),
            title: 'No closed shifts yet',
            hint: 'A shift appears here once it has been closed. Closing '
                'happens on the shift banner.',
            illustration: 'schedule.svg',
          )
        else if (shown.isEmpty)
          // **A second empty state, and it is not the same fact.** An empty
          // read means nothing has been closed; an empty *filter* means
          // everything that was is fine, which on this screen is the best news
          // it has to give.
          EmptyState(
            key: const ValueKey('shift-history-nothing-matches'),
            title: 'Every shift on this page settled',
            hint: 'All ${tally.closed} of them agree with their sales.',
            action: AppButton(
              key: const ValueKey('shift-history-show-all'),
              label: 'Show all ${tally.closed}',
              onPressed: () => onFilterChanged(ShiftHistoryFilter.all),
            ),
          )
        else
          ..._days(context, tokens, shown),
        SizedBox(height: tokens.spacing.s20),
        Pagination(
          pageNumber: pageIndex + 1,
          previousKey: const ValueKey('shift-history-previous'),
          nextKey: const ValueKey('shift-history-next'),
          onPrevious: pageIndex > 0 ? onPreviousPage : null,
          onNext: _page.hasMore ? onNextPage : null,
        ),
      ],
    );
  }

  /// The shifts, grouped under the business day they closed on.
  ///
  /// **Consecutive runs, not a regrouping.** The page arrives newest document
  /// ID first and a shift ID embeds its own millisecond, so one day's shifts are
  /// already contiguous; walking the list and cutting where the date changes
  /// keeps the server's order exactly, where bucketing into a map and reading it
  /// back would impose this file's idea of one.
  List<Widget> _days(
    BuildContext context,
    AppTokens tokens,
    List<TenantShiftHistoryEntry> shown,
  ) {
    final ownShifts = _page.scope == TenantShiftHistoryScope.ownShifts;
    final rows = <Widget>[];
    var index = 0;
    while (index < shown.length) {
      final businessDate = shown[index].businessDate;
      var end = index;
      while (end < shown.length && shown[end].businessDate == businessDate) {
        end++;
      }
      if (rows.isNotEmpty) rows.add(SizedBox(height: tokens.spacing.s20));
      rows.add(
        ShiftHistoryDayHeading(
          key: ValueKey<String>('shift-history-day-$businessDate'),
          businessDate: businessDate,
          count: end - index,
        ),
      );
      for (final entry in shown.sublist(index, end)) {
        rows
          ..add(SizedBox(height: ShiftHistoryCard.blockGap(tokens.spacing)))
          ..add(_card(entry, ownShifts: ownShifts));
      }
      index = end;
    }
    return rows;
  }

  Widget _card(TenantShiftHistoryEntry entry, {required bool ownShifts}) {
    final window = shiftWindowLabel(entry);
    final sales = shiftSalesLabel(entry);
    return ShiftHistoryCard(
      entry: entry,
      // **The cashier names a row only where the rows are different cashiers.**
      // On *My shifts* every title would be the same word, so the hours name
      // the shift and the day above it names the day.
      title: ownShifts ? window : _staffLabel(entry),
      subtitle: ownShifts ? sales : '$window · $sales',
      currency: load.currency,
      onViewSales: () => onViewSales(_salesRequest(entry)),
      onViewCorrections: entry.amendment != null && canReadCorrections
          ? () => onViewCorrections(entry.id)
          : null,
    );
  }

  String _staffLabel(TenantShiftHistoryEntry entry) =>
      tenantStaffLabel(entry.staffId, names: load.names, selfUid: session.uid);

  /// Carries the already-validated shift identity into the sales page, so the
  /// sales route proves attribution against this exact shift without a second
  /// read of the shift document.
  TenantSaleHistoryRequest _salesRequest(TenantShiftHistoryEntry entry) =>
      TenantShiftSaleHistoryRequest(
        shift: TenantSaleShiftScope(
          shiftId: entry.id,
          staffId: entry.staffId,
          deviceId: entry.deviceId,
          businessDate: entry.businessDate,
        ),
        recordedTransactionCount: entry.summary?.transactionCount,
        recordedTotalSalesMinor: entry.summary?.totalSalesMinor,
        countedCashMinor: entry.closingCashMinor,
      );
}

/// What the loaded page adds up to.
///
/// **Of the page, and the screen says so.** `loadPage` takes equality filters
/// and a cursor; it has no date range and no aggregate, so there is no honest
/// way for this to be the week's answer. [_PageRange] above the tiles names the
/// days these twenty cover and the word *page*, because a figure whose scope a
/// reader has to guess at is worse on this screen than no figure.
@immutable
final class ShiftHistoryTally {
  const ShiftHistoryTally._({
    required this.closed,
    required this.settled,
    required this.unresolved,
    required this.shortMinor,
    required this.overMinor,
    required this.unknown,
  });

  factory ShiftHistoryTally.of(List<TenantShiftHistoryEntry> items) {
    var settled = 0;
    var unresolved = 0;
    var shortMinor = 0;
    var overMinor = 0;
    var unknown = 0;
    for (final entry in items) {
      final standing = ShiftStanding.of(entry);
      if (!standing.needsAttention) {
        settled++;
        continue;
      }
      unresolved++;
      switch (standing) {
        case ShiftStanding.short:
          shortMinor += -entry.cashVarianceMinor!;
        case ShiftStanding.over:
          overMinor += entry.cashVarianceMinor!;
        case ShiftStanding.unaccounted || ShiftStanding.noSummary:
          unknown++;
        case ShiftStanding.settled:
          break;
      }
    }
    return ShiftHistoryTally._(
      closed: items.length,
      settled: settled,
      unresolved: unresolved,
      shortMinor: shortMinor,
      overMinor: overMinor,
      unknown: unknown,
    );
  }

  final int closed;
  final int settled;
  final int unresolved;

  /// How much the short shifts are short by, added up. Positive.
  final int shortMinor;

  /// How much the over shifts are over by, added up. Positive.
  final int overMinor;

  /// How many shifts hold no figures to compare at all.
  final int unknown;

  /// The one sentence under the tiles.
  ///
  /// **Three amounts are not netted into one.** A shop a thousand short on
  /// Friday and a thousand over on Tuesday has two problems, and a net of zero
  /// is the single most misleading thing this screen could print.
  String sentence(TenantReportingCurrency currency) {
    final clauses = <String>[
      if (shortMinor > 0) 'short ${shiftMoney(currency, shortMinor)}',
      if (overMinor > 0) 'over ${shiftMoney(currency, overMinor)}',
      if (unknown > 0)
        unknown == 1
            ? 'one shift closed without its sales'
            : '$unknown shifts closed without their sales',
    ];
    final joined = switch (clauses.length) {
      0 => '',
      1 => clauses.single,
      2 => '${clauses[0]} and ${clauses[1]}',
      _ => '${clauses.take(clauses.length - 1).join(', ')}, and ${clauses.last}',
    };
    final subject = unresolved == 1
        ? 'One shift on this page needs attention'
        : '$unresolved shifts on this page need attention';
    return joined.isEmpty ? '$subject.' : '$subject: $joined.';
  }
}

/// Placeholder cards, in the page's own inset, while the read is outstanding.
///
/// **The list's shape rather than §5.1's spinner**, because the shape is known
/// before the contents are and this screen is a list of cards at every band.
/// The guard's `LoadingState` stays the default everywhere it is not.
final class _ShiftHistorySkeleton extends StatelessWidget {
  const _ShiftHistorySkeleton();

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.all(AppTokens.componentOf(context).spacing.s20),
    child: const SkeletonGroup(
      semanticLabel: 'Reading closed shifts.',
      child: RecordListSkeleton(),
    ),
  );
}

/// Which days the loaded page covers, and that it is a page.
final class _PageRange extends StatelessWidget {
  const _PageRange({required this.items});

  final List<TenantShiftHistoryEntry> items;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final newest = shiftBusinessDayLabel(items.first.businessDate);
    final oldest = shiftBusinessDayLabel(items.last.businessDate);
    final range = newest == oldest ? newest : '$oldest – $newest';
    return Row(
      children: <Widget>[
        Icon(
          Icons.calendar_today_outlined,
          size: StatusBadge.iconSize,
          color: tokens.colors.text.tertiary,
        ),
        SizedBox(width: tokens.spacing.s8),
        Expanded(
          child: Text(
            '$range · this page',
            key: const ValueKey('shift-history-range'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tokens.typography.labelMedium.copyWith(
              color: tokens.colors.text.secondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// The four claims that used to sit between the title and the first shift.
///
/// **Same words, different place.** They were a five-line paragraph every
/// person read past once and then past forever, above the data they were about;
/// here they are one tap from the toolbar, laid out as the four terms a person
/// would actually come looking for the meaning of.
Future<void> showShiftReconciliationSheet(BuildContext context) =>
    showAppSheet<void>(
      context,
      builder: (context, controller) {
        final tokens = AppTokens.componentOf(context);
        final body = tokens.density.body(tokens.typography);
        Widget term(String name, String meaning, Color colour) => Padding(
          padding: EdgeInsets.only(bottom: tokens.spacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                name,
                style: tokens.typography.labelMedium.copyWith(color: colour),
              ),
              SizedBox(height: tokens.spacing.s4),
              Text(
                meaning,
                style: body.copyWith(color: tokens.colors.text.secondary),
              ),
            ],
          ),
        );
        return ListView(
          key: const ValueKey('shift-history-explainer-sheet'),
          controller: controller,
          padding: EdgeInsets.fromLTRB(
            tokens.spacing.s20,
            tokens.spacing.s8,
            tokens.spacing.s20,
            tokens.spacing.s24,
          ),
          children: <Widget>[
            const SectionHeading('How a shift is reconciled'),
            SizedBox(height: tokens.spacing.s16),
            term(
              'Counted cash',
              'What was declared at the close, exactly as the server holds it. '
                  'It is never recomputed here.',
              tokens.colors.text.money,
            ),
            term(
              'Recorded sales',
              "What that shift's own sales came to, exactly as the server "
                  'holds them.',
              tokens.colors.text.money,
            ),
            term(
              'The difference',
              'The whole declaration against the whole of the sales, less any '
                  'opening float - takings, not cash alone, so a shop taking '
                  'M-Pesa does not read as short by its M-Pesa. Reconciliation '
                  'resolves it.',
              tokens.colors.status.problem.fg,
            ),
            term(
              'Corrections',
              "A correction rewrites a shift's recorded sales to the total its "
                  'own sales prove. It never changes the counted cash. The '
                  'record of who asked for one, and why, is kept for managers, '
                  'administrators and owners.',
              tokens.colors.status.attention.fg,
            ),
            AppButton(
              key: const ValueKey('shift-history-explainer-done'),
              label: 'Got it',
              tier: AppButtonTier.primary,
              expand: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
