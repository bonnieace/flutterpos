/// Counts waiting to be looked at, and the act of accepting one.
///
/// **This is the half of stock take where stock actually moves**, which is why
/// it is owner/admin/manager and the counting screen is everybody. A count is an
/// observation until somebody with the standing to move a quantity decides what
/// it means; that decision is the *Accept* button here, and it writes the same
/// ledger entries `adjustStock` writes.
///
/// **Only the differing lines are listed.** A count of four hundred products
/// where six disagree is a report about six products. How many agreed is stated
/// on the count itself, so nothing is hidden by leaving the rest out.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../reports/analysis/stock_counts_analysis.dart';
import '../reports/analysis/stock_counts_report.dart';
import '../reports/report_document.dart';
import '../reports/report_file.dart';
import '../reports/report_identity_source.dart';
import '../reports/report_people.dart';
import '../reports/report_period.dart';
import '../reports/report_run.dart';
import '../reports/ui/report_action.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../tenancy/tenant_staff_names.dart';
import 'product_image_cache.dart';
import '../ui/record_sheet.dart';
import '../ui/buttons.dart';
import '../ui/card.dart';
import '../ui/dialogs.dart';
import '../ui/fields.dart';
import '../ui/routes.dart';
import '../ui/scaffold.dart';
import '../ui/snackbar.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tabs.dart';
import '../ui/tokens.dart';
import 'stock_take_card.dart';
import 'stock_take_review.dart';
import 'stock_take_schedule.dart';

/// The reading route for this business's counts.
final class TenantStockTakeReviewScreen extends StatelessWidget {
  const TenantStockTakeReviewScreen({
    super.key,
    required this.reader,
    this.applyCallable,
    this.onApplied,
    this.countRoute,
    this.settings,
    this.reportSaver,
    this.imageCache,
    this.clock,
  });

  final TenantDataReader reader;

  /// Where a generated report goes. Null renders no toolbar control at all.
  final TenantReportSaver? reportSaver;

  /// Fetches the logo the report's branding band draws.
  final TenantImageCache? imageCache;

  /// Reads the instant a report calls *now*. Injected so a test can pin it.
  final DateTime Function()? clock;

  /// Absent in a build with no callable wired, which renders read-only.
  final ApplyStockTakeCallable? applyCallable;
  final VoidCallback? onApplied;

  /// The counting screen, started from here.
  ///
  /// **The act, on the page that holds its record.** Taking a count and reading
  /// what counts said were two tiles on the home menu differing by one letter;
  /// this is the act, put where somebody who has just read a count goes looking
  /// for it. Absent leaves the button off, which is what a role that may read
  /// counts but not take one would get - there is no such role today, and the
  /// screen should not assume there never will be.
  final WidgetBuilder? countRoute;

  /// When a count is due and who takes it, drawn as this screen's second tab.
  ///
  /// **On the page whose counts it schedules, at the developer's direction on
  /// 2026-10-04.** It was a tab of *Configs*, a screen away from the counts it
  /// decides. Only an owner or administrator may publish it, so anybody else
  /// who reads counts here - a manager, every day - gets the counts alone with
  /// no switch above them, rather than a tab that says *Not allowed*. Absent
  /// draws the same single page.
  final WidgetBuilder? settings;

  @override
  Widget build(BuildContext context) {
    final counts = TenantStockTakeReviewPanel(
      reader: reader,
      applyCallable: applyCallable,
      onApplied: onApplied,
      countRoute: countRoute,
    );
    final settings = this.settings;
    final session = settings == null
        ? null
        : TenantSessionScope.of(context).session;
    final tabbed =
        settings != null &&
        session != null &&
        session.canAccess(
          allowedRoles: TenantStockTakeSchedulePublisher.allowedRoles,
        );
    return AppScaffold(
      title: 'Stock counts',
      contentWidth: RecordSheet.contentWidth(context),
      // **One toolbar action since 2026-09-24**, and only one. *Count stock*
      // stays a button the width of the page at the head of the body, with the
      // two filters under it - the shape expenses and staff open in, and the
      // developer's direction of 2026-09-22 that took the act off the toolbar.
      // Taking a copy of a period away is not the act this page exists for, so
      // it is chrome and it goes here.
      actions: <Widget>[
        TenantSessionReportAction(
          clock: clock ?? DateTime.now,
          runFor: (session) => _reportRun(session),
        ),
      ],
      body: tabbed
          ? _StockCountsTabs(counts: counts, settings: settings)
          : counts,
    );
  }

  /// Counts over a period, which the review list cannot ask for.
  TenantReportRun? _reportRun(TenantSession session) {
    final saver = reportSaver;
    if (saver == null) return null;
    // The same set that may read a count and the lines under it.
    if (!session.canAccess(
      allowedRoles: TenantStockTakeReviewRepository.allowedRoles,
    )) {
      return null;
    }

    final now = clock ?? DateTime.now;
    return TenantReportRun(
      kind: TenantReportKind.stockCounts,
      support: TenantReportPeriodSupport.range,
      saver: saver,
      build: (period) async {
        final source = TenantStockCountsReportSource(
          repository: TenantStockTakeReviewRepository(
            session: session,
            reader: reader,
          ),
          reader: reader,
        );
        final read = await source.gather(period);
        final previous = await source.gatherPrevious(period);
        final identity = await readTenantReportIdentity(
          session: session,
          reader: reader,
          generatedAt: now(),
          imageCache: imageCache,
        );
        final analysis = TenantStockCountsAnalysis.from(
          period: period,
          takes: read.takes,
          previous: previous,
          truncated: read.truncated,
        );
        return describeStockCountsReport(
          identity: identity,
          analysis: analysis,
          people: await readTenantReportPeople(
            session: session,
            reader: reader,
            uids: analysis.counters
                .take(TenantStockCountsAnalysis.listed)
                .map((person) => person.staffId),
          ),
        );
      },
    );
  }
}

/// *Counts* and *Settings*, as two tabs of one screen.
///
/// **Both stay alive**, so an unsaved change to the rota survives a look at the
/// counts, and going back to the counts never reads them again. The rota is
/// read the first time its tab is opened, not on the way in.
final class _StockCountsTabs extends StatelessWidget {
  const _StockCountsTabs({required this.counts, required this.settings});

  final Widget counts;
  final WidgetBuilder settings;

  @override
  Widget build(BuildContext context) {
    // The counts tab pads its button, its filters and its cards by `space.16`,
    // and the rota takes the same. What a person sees of each stands in the
    // focus ring's gutter inside that; the switch carries no gutter of its own,
    // so it takes the gutter as well and the page keeps one edge whichever tab
    // is showing.
    final tokens = AppTokens.componentOf(context);
    final ring = tokens.colors.action.focusRing;
    final inset = RecordSheet.drawnAt(MediaQuery.sizeOf(context).width)
        ? tokens.spacing.s24
        : tokens.spacing.s16;
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppTabs(
            key: const ValueKey('stock-take-review-tabs'),
            tabs: const <String>['Counts', 'Settings'],
            inset: inset + ring.width + ring.offset,
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                AppKeptTab(child: counts),
                // The scroll the rota's panel leaves to its host, as *Configs*
                // gave it one.
                AppKeptTab(
                  child: SingleChildScrollView(
                    key: const ValueKey('stock-take-settings-tab'),
                    padding: EdgeInsets.all(inset),
                    // The reading width the rota has on its own screen,
                    // centred: the counts beside it take the table's width,
                    // a form does not.
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: tokens.layout.reading,
                        ),
                        child: Builder(builder: settings),
                      ),
                    ),
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

final class TenantStockTakeReviewPanel extends StatefulWidget {
  const TenantStockTakeReviewPanel({
    super.key,
    required this.reader,
    this.applyCallable,
    this.onApplied,
    this.countRoute,
    this.pageSize = TenantStockTakeReviewRepository.defaultPageSize,
  });

  final TenantDataReader reader;
  final ApplyStockTakeCallable? applyCallable;
  final VoidCallback? onApplied;

  /// The counting screen, started from the button at the head of this panel.
  /// Absent leaves the button off - see [TenantStockTakeReviewScreen.countRoute].
  final WidgetBuilder? countRoute;

  final int pageSize;

  @override
  State<TenantStockTakeReviewPanel> createState() =>
      _TenantStockTakeReviewPanelState();
}

class _TenantStockTakeReviewPanelState extends State<TenantStockTakeReviewPanel>
    with RereadOnReturn<TenantStockTakeReviewPanel> {
  /// **Handing a count in left this list showing "No counts yet".** *Count
  /// stock* is pushed from the screen above this panel, which cannot reach
  /// [_generation], so nothing re-read when it popped - and the count a person
  /// had just handed in was missing from the only list that shows it. Opening
  /// one for review had the same shape and was fixed by hand in [_open]; this
  /// covers both, and anything else pushed from here.
  @override
  void rereadAfterReturn() => setState(() => _generation++);

  int _generation = 0;

  /// The standing the list is narrowed to, as the label a count's card wears,
  /// or null for every standing.
  ///
  /// **The card's own words**, so a filter and the badge it narrows by cannot
  /// disagree: both come from [TenantStockTakeStanding.of].
  String? _standing;

  /// The counter the list is narrowed to, or null for everybody.
  ///
  /// **Neither filter is in the loader key.** `loadTakes` reads one bounded
  /// page and both of these narrow what is already in hand, so a change here is
  /// a repaint rather than a read - and a filter that spent a read to throw
  /// rows away would also renumber the page it filtered.
  String? _counterUid;

  final TenantStaffNameResolvers _staffNames = TenantStaffNameResolvers();

  /// One resolver per session **and per pass**, so the cached pass resolves a
  /// name from this device rather than putting a network read in front of
  /// records it already holds. An unresolved name degrades to the UID.
  TenantStaffNameResolver _resolverFor(
    TenantSession session,
    TenantDocumentReader reader,
  ) => _staffNames.of(session: session, reader: reader);

  @override
  Widget build(BuildContext context) {
    // **Memoised rather than keyed.** Putting the generation in a `ValueKey` on
    // the guard would destroy its `State` and blank the page for the length of
    // every re-read; the guard already notices a changed `load` and re-reads
    // while keeping what it is drawing. `_composeLoaders` in the catalog panel
    // is the same pattern and the reason it exists.
    _composeLoaders('$_generation');
    final tokens = AppTokens.componentOf(context);
    final table = RecordSheet.drawnAt(MediaQuery.sizeOf(context).width);
    final count = _countButton(context, expand: !table);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // **Above the guard, exactly where the toolbar button was.** Taking a
        // count is not a thing this page read, so it does not wait on the read
        // and it does not disappear when the read refuses: the same standing
        // the control had in the top bar, moved down into the page.
        if (count != null)
          Padding(
            padding: RecordSheet.pagePadding(
              context,
              fallback: EdgeInsets.all(tokens.spacing.s16),
              belowScaffold: DefaultTabController.maybeOf(context) == null,
            ).resolve(Directionality.of(context)).copyWith(bottom: 0),
            // **At its own width on the trailing edge from 1024**, over the
            // table, rather than inside the table's bar: it stays out here
            // because a session the read refuses - a cashier, who may count but
            // not read counts - must still be offered it.
            child: table
                ? Align(alignment: AlignmentDirectional.centerEnd, child: count)
                : count,
          ),
        Expanded(
          child: TenantRouteGuard<TenantNamedPage<List<TenantStockTakeRecord>>>(
            allowedRoles: TenantStockTakeReviewRepository.allowedRoles,
            load: _loader!,
            loadCached: _loaderCached,
            holdsNothing: (named) => named.page.isEmpty,
            denied: const ErrorState(
              status: AppStatus.problem,
              badgeLabel: 'Not allowed',
              statement:
                  'Only an owner, administrator or manager may read stock '
                  'counts.',
            ),
            builder: _buildList,
          ),
        ),
      ],
    );
  }

  /// *Count stock*: the width of the page below 1024, its own width above.
  Widget? _countButton(BuildContext context, {required bool expand}) {
    final route = widget.countRoute;
    if (route == null) return null;
    return AppButton(
      key: const ValueKey('stock-take-review-count'),
      label: 'Count stock',
      icon: Icons.checklist_outlined,
      tier: AppButtonTier.secondary,
      expand: expand,
      onPressed: () {
        final controller = TenantSessionScope.of(context);
        Navigator.of(context).push(
          AppPageRoute<void>(
            builder: (routeContext) => TenantSessionScope(
              controller: controller,
              child: route(routeContext),
            ),
          ),
        );
      },
    );
  }

  String? _loaderKey;
  TenantGuardedLoader<TenantNamedPage<List<TenantStockTakeRecord>>>? _loader;
  TenantGuardedLoader<TenantNamedPage<List<TenantStockTakeRecord>>>?
  _loaderCached;

  /// One loader per generation, cached so a `setState` for a busy flag or a
  /// notice does not restart the read.
  void _composeLoaders(String key) {
    if (key == _loaderKey && _loader != null) return;
    _loaderKey = key;
    TenantGuardedLoader<TenantNamedPage<List<TenantStockTakeRecord>>> readWith(
      TenantDataReader reader,
    ) => (session) async {
      final takes = await TenantStockTakeReviewRepository(
        session: session,
        reader: reader,
      ).loadTakes(collectionReader: reader, pageSize: widget.pageSize);
      // **Who counted it, by name.** A count is evidence about a person's
      // work, and a page of raw UIDs is unreadable to the manager the screen
      // exists for. `TenantStaffNameResolver` bounds the reads and degrades an
      // unresolvable UID to itself, so a missing staff record costs a label
      // rather than the row.
      return TenantNamedPage<List<TenantStockTakeRecord>>(
        page: takes,
        names: await _resolverFor(
          session,
          reader,
        ).resolve(takes.map((take) => take.counterUid)),
      );
    };
    _loader = readWith(widget.reader);
    final cache = widget.reader.cached;
    _loaderCached = cache == null ? null : readWith(cache);
  }

  Widget _buildList(
    BuildContext context,
    TenantSession session,
    TenantNamedPage<List<TenantStockTakeRecord>> named,
  ) {
    final takes = named.page;
    final tokens = AppTokens.componentOf(context);
    if (takes.isEmpty) {
      return const EmptyState(
        key: ValueKey('stock-take-review-empty'),
        illustration: 'stock-review.svg',
        title: 'No counts yet',
        hint: 'Submitted counts appear here. Manage the schedule in Settings.',
      );
    }
    final shown = takes
        .where(
          (take) =>
              (_standing == null ||
                  TenantStockTakeStanding.of(take).label == _standing) &&
              (_counterUid == null || take.counterUid == _counterUid),
        )
        .toList(growable: false);
    if (RecordSheet.drawnAt(MediaQuery.sizeOf(context).width)) {
      return _sheet(context, session, named, shown);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(
            tokens.spacing.s16,
            tokens.spacing.s16,
            tokens.spacing.s16,
            0,
          ),
          child: _filters(context, session, named),
        ),
        // **A `ListView`, and the scroll is still the caller's.** It was a
        // `RecordList` inside one, because that component is a bare `Column`;
        // it is now a list of `TenantStockTakeCard`, which is a bare card for
        // the same reason. Without the scroll a third count overflows the
        // viewport instead of scrolling, which is what the device run found.
        Expanded(
          child: shown.isEmpty
              // **Not "No counts yet".** This page holds counts; these two
              // filters are why none is on screen, and the way out is to widen
              // them rather than to hand another one in.
              ? const EmptyState(
                  key: ValueKey('stock-take-review-no-matches'),
                  illustration: 'stock-search.svg',
                  title: 'No counts match',
                  hint: 'Try another status or person.',
                )
              : ListView.separated(
                  key: const ValueKey('stock-take-review-list'),
                  padding: EdgeInsets.all(tokens.spacing.s16),
                  itemCount: shown.length,
                  separatorBuilder: (context, index) =>
                      SizedBox(height: tokens.spacing.s12),
                  itemBuilder: (context, index) {
                    final take = shown[index];
                    final counterLabel = tenantStaffLabel(
                      take.counterUid,
                      names: named.names,
                      selfUid: session.uid,
                    );
                    return TenantStockTakeCard(
                      // The key the record card carried, kept so a test written
                      // against this list keeps addressing the same count.
                      key: ValueKey<String>('stock-take-${take.id}'),
                      take: take,
                      counterLabel: counterLabel,
                      onOpen: () => _open(take, counterLabel),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// The standing and the counter, side by side.
  ///
  /// **The counters are the ones on this page, not the business's staff.** The
  /// page is one bounded read and the names arrived with it, so offering
  /// somebody who took no count on it would be a choice that empties the list
  /// and explains nothing. A counter the filter is holding stays on offer even
  /// after a re-read drops them, because a select has to hold what it shows.
  Widget _filters(
    BuildContext context,
    TenantSession session,
    TenantNamedPage<List<TenantStockTakeRecord>> named,
  ) {
    final tokens = AppTokens.componentOf(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: _standingFilter()),
        SizedBox(width: tokens.spacing.s12),
        Expanded(child: _counterFilter(session, named)),
      ],
    );
  }

  /// Which standing the loaded page is narrowed to.
  Widget _standingFilter() => AppSelect<String?>(
    key: const ValueKey('stock-take-review-status-filter'),
    label: 'Standing',
    dense: true,
    leading: Icons.filter_alt_outlined,
    value: _standing,
    items: const <AppSelectItem<String?>>[
      AppSelectItem<String?>(
        key: ValueKey('stock-take-review-status-all'),
        value: null,
        label: 'Standing',
      ),
      AppSelectItem<String?>(
        key: ValueKey('stock-take-review-status-needs-review'),
        value: 'Needs review',
        label: 'Needs review',
      ),
      AppSelectItem<String?>(
        key: ValueKey('stock-take-review-status-accepted'),
        value: 'Accepted',
        label: 'Accepted',
      ),
      AppSelectItem<String?>(
        key: ValueKey('stock-take-review-status-all-agreed'),
        value: 'All agreed',
        label: 'All agreed',
      ),
    ],
    onChanged: (standing) => setState(() => _standing = standing),
  );

  /// Whose counts the loaded page is narrowed to.
  Widget _counterFilter(
    TenantSession session,
    TenantNamedPage<List<TenantStockTakeRecord>> named,
  ) {
    final counters = <String>{
      for (final take in named.page) take.counterUid,
      if (_counterUid != null) _counterUid!,
    }.toList(growable: false)..sort();
    return AppSelect<String?>(
      key: const ValueKey('stock-take-review-counter-filter'),
      label: 'Counted by',
      dense: true,
      leading: Icons.person_outline,
      value: _counterUid,
      items: <AppSelectItem<String?>>[
        const AppSelectItem<String?>(
          key: ValueKey('stock-take-review-counter-all'),
          value: null,
          label: 'Staff',
        ),
        for (final uid in counters)
          AppSelectItem<String?>(
            key: ValueKey<String>('stock-take-review-counter-$uid'),
            value: uid,
            label: tenantStaffLabel(
              uid,
              names: named.names,
              selfUid: session.uid,
            ),
          ),
      ],
      onChanged: (uid) => setState(() => _counterUid = uid),
    );
  }

  /// The large-screen list: one table, its two filters on its top edge.
  ///
  /// **The same loaded page, narrowed the same way, drawn as rows** -
  /// `docs/design/tables/`, at the developer's direction on 2026-10-13. A
  /// count's coverage and its differences line up down columns, so *Needs
  /// review* is the row that stands out rather than one card among several
  /// with two large boxes each. Below 1024 the cards are unchanged.
  Widget _sheet(
    BuildContext context,
    TenantSession session,
    TenantNamedPage<List<TenantStockTakeRecord>> named,
    List<TenantStockTakeRecord> shown,
  ) {
    final tokens = AppTokens.componentOf(context);
    return ListView(
      key: const ValueKey('stock-take-review-list'),
      padding: RecordSheet.pagePadding(
        context,
        fallback: EdgeInsets.all(tokens.spacing.s16),
        belowScaffold:
            widget.countRoute == null &&
            DefaultTabController.maybeOf(context) == null,
      ),
      children: <Widget>[
        RecordSheet(
          key: const ValueKey('stock-take-review-sheet'),
          columns: const <SheetColumn>[
            SheetColumn(label: 'Count', kind: SheetColumnKind.identity),
            SheetColumn(label: 'Counted by', kind: SheetColumnKind.text),
            SheetColumn(label: 'Counted', kind: SheetColumnKind.figure),
            SheetColumn(label: 'Products differ', kind: SheetColumnKind.figure),
            SheetColumn(label: 'Units apart', kind: SheetColumnKind.figure),
            SheetColumn(label: 'Standing', kind: SheetColumnKind.status),
          ],
          bar: Row(
            children: <Widget>[
              SizedBox(
                width: tokens.layout.tableFilter,
                child: _standingFilter(),
              ),
              SizedBox(width: tokens.spacing.s12),
              SizedBox(
                width: tokens.layout.tableFilter,
                child: _counterFilter(session, named),
              ),
            ],
          ),
          // **Not "No counts yet"**, for the cards' reason: the page holds
          // counts, and these two filters are why none is on screen.
          body: shown.isEmpty
              ? const EmptyState(
                  key: ValueKey('stock-take-review-no-matches'),
                  illustration: 'stock-search.svg',
                  title: 'No counts match',
                  hint: 'Try another status or person.',
                )
              : null,
          rows: <SheetRow>[
            for (final take in shown) _row(session, named, take),
          ],
        ),
      ],
    );
  }

  SheetRow _row(
    TenantSession session,
    TenantNamedPage<List<TenantStockTakeRecord>> named,
    TenantStockTakeRecord take,
  ) {
    final id = take.id;
    final counterLabel = tenantStaffLabel(
      take.counterUid,
      names: named.names,
      selfUid: session.uid,
    );
    final who = tenantStaffLabelParts(
      take.counterUid,
      names: named.names,
      selfUid: session.uid,
    );
    final standing = TenantStockTakeStanding.of(take);
    final arriving = take.status == TenantStockTakeStatus.submitting;
    final scope = take.categoryId == null ? 'Whole catalog' : 'One category';
    final uncounted = take.uncountedLineCount;
    final notes = <String>[
      if (arriving) stockTakeArrivingNote,
      if (take.unmatchedLineCount > 0)
        stockTakeUnmatchedNote(take.unmatchedLineCount),
    ];
    return SheetRow(
      id: id,
      // The key the card carries, so a test addresses the same count in
      // either form.
      key: ValueKey<String>('stock-take-$id'),
      pressKey: ValueKey<String>('stock-take-open-$id'),
      onPressed: () => _open(take, counterLabel),
      semanticLabel: '$scope, ${take.businessDate}',
      semanticHint: 'Opens this count.',
      cells: <SheetCell?>[
        SheetText(scope, caption: take.businessDate),
        SheetText(who.name, caption: who.under),
        SheetFigure(
          '${take.countedLineCount} of ${take.productsInScope}',
          key: ValueKey<String>('stock-take-coverage-$id'),
          // What the card's coverage line says beside its bar.
          caption: uncounted > 0
              ? '$uncounted not counted'
              : arriving
              ? 'so far'
              : null,
          captionKey: ValueKey<String>('stock-take-uncounted-$id'),
        ),
        SheetFigure(
          '${take.varianceLineCount}',
          key: ValueKey<String>('stock-take-variance-$id'),
        ),
        SheetFigure(
          '${take.absoluteVarianceUnits}',
          key: ValueKey<String>('stock-take-units-$id'),
        ),
        SheetStatus(
          key: ValueKey<String>('stock-take-standing-$id'),
          status: standing.status,
          label: standing.label,
          // Accepted and agreed are settled; a count still arriving or
          // needing review is what a manager opens this list to find.
          quiet: standing.status == AppStatus.ok,
        ),
      ],
      fold: notes.isEmpty
          ? null
          : SheetFold(
              note: notes.join(' '),
              noteKey: ValueKey<String>('stock-take-note-$id'),
              toggleKey: ValueKey<String>('stock-take-fold-$id'),
              showLabel: 'Show more about this count',
              hideLabel: 'Show less about this count',
            ),
    );
  }

  Future<void> _open(TenantStockTakeRecord take, String counterLabel) async {
    final sessions = TenantSessionScope.of(context);
    await Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => TenantSessionScope(
          controller: sessions,
          child: _TenantStockTakeDetailScreen(
            take: take,
            counterLabel: counterLabel,
            reader: widget.reader,
            applyCallable: widget.applyCallable,
            onApplied: () {
              widget.onApplied?.call();
              if (mounted) setState(() => _generation++);
            },
          ),
        ),
      ),
    );
    if (mounted) setState(() => _generation++);
  }
}

/// One count's differing lines, with the names of the products they name.
final class _TenantStockTakeLines {
  const _TenantStockTakeLines({required this.lines, required this.names});

  final List<TenantStockTakeLineRecord> lines;
  final Map<String, String> names;
}

/// One count, line by line.
final class _TenantStockTakeDetailScreen extends StatefulWidget {
  const _TenantStockTakeDetailScreen({
    required this.take,
    required this.counterLabel,
    required this.reader,
    this.applyCallable,
    this.onApplied,
  });

  final TenantStockTakeRecord take;

  /// Who counted it, already resolved by the list this was opened from.
  final String counterLabel;
  final TenantDataReader reader;
  final ApplyStockTakeCallable? applyCallable;
  final VoidCallback? onApplied;

  @override
  State<_TenantStockTakeDetailScreen> createState() =>
      _TenantStockTakeDetailScreenState();
}

class _TenantStockTakeDetailScreenState
    extends State<_TenantStockTakeDetailScreen> {
  bool _applying = false;
  bool _applied = false;
  String? _loaderKey;
  TenantGuardedLoader<_TenantStockTakeLines>? _loader;
  TenantGuardedLoader<_TenantStockTakeLines>? _loaderCached;

  @override
  Widget build(BuildContext context) {
    _composeLoaders(widget.take.id);
    return AppScaffold(
      title: 'The count',
      subtitle: _subtitle(widget.take, widget.counterLabel),
      contentWidth: AppContentWidth.records,
      body: TenantRouteGuard<_TenantStockTakeLines>(
        allowedRoles: TenantStockTakeReviewRepository.allowedRoles,
        load: _loader!,
        loadCached: _loaderCached,
        holdsNothing: (take) => take.lines.isEmpty,
        builder: _buildLines,
      ),
    );
  }

  /// *Fri 19 Sep · Whole catalog · Grace Wanjiku*: when, what and who.
  ///
  /// The business date is stored as `yyyy-MM-dd`; one this cannot read is
  /// shown as it is rather than dropped.
  static String _subtitle(TenantStockTakeRecord take, String counterLabel) {
    final date = DateTime.tryParse(take.businessDate);
    return <String>[
      date == null ? take.businessDate : _dayFormat.format(date),
      take.categoryId == null ? 'Whole catalog' : 'One category',
      counterLabel,
    ].join(' · ');
  }

  static final DateFormat _dayFormat = DateFormat('EEE d MMM');

  /// The lines, and the names of the products they name.
  ///
  /// Read together rather than drawn from the line documents, because a line
  /// carries no name - see `TenantStockTakeProductNames`.
  ///
  /// **Both passes, because the list this was opened from has both.** A count
  /// reached from a cached list is a count this device already holds, and
  /// reading its lines through the live reader alone made tapping one wait for
  /// a network the list in front of it had not needed. Product names follow the
  /// same reader and degrade to the product ID, exactly as they do on the list.
  ///
  /// One loader per count, so a closure rebuilt on `setState` cannot restart
  /// the read underneath the guard.
  void _composeLoaders(String key) {
    if (key == _loaderKey && _loader != null) return;
    _loaderKey = key;
    TenantGuardedLoader<_TenantStockTakeLines> readWith(
      TenantDataReader reader,
    ) => (session) async {
      final lines = await TenantStockTakeReviewRepository(
        session: session,
        reader: reader,
      ).loadVarianceLines(widget.take.id, collectionReader: reader);
      final names = await TenantStockTakeProductNames(
        session: session,
        reader: reader,
      ).resolve(lines.map((line) => line.productId));
      return _TenantStockTakeLines(lines: lines, names: names);
    };
    _loader = readWith(widget.reader);
    final cache = widget.reader.cached;
    _loaderCached = cache == null ? null : readWith(cache);
  }

  Widget _buildLines(
    BuildContext context,
    TenantSession session,
    _TenantStockTakeLines loaded,
  ) {
    final take = widget.take;
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final inset = AppScaffold.horizontalInset(tokens.spacing);
    final ring = colors.action.focusRing;
    final gutter = ring.width + ring.offset;
    // Biggest difference first, which is the order somebody investigating wants
    // and the order Firestore cannot give: it sorts by the stored value, and
    // what matters here is the size of it either way.
    final sorted = loaded.lines.toList()
      ..sort(
        (left, right) =>
            (right.variance ?? 0).abs().compareTo((left.variance ?? 0).abs()),
      );
    // Counted, less what differed and what matched no product: the lines this
    // screen leaves out, said so that leaving them out hides nothing.
    final agreed =
        take.countedLineCount -
        take.varianceLineCount -
        take.unmatchedLineCount;
    final canAccept = sorted.isNotEmpty && !_applied && take.canApply;

    final Widget? standing = take.status == TenantStockTakeStatus.submitting
        ? const Callout(
            key: ValueKey('stock-take-detail-arriving'),
            status: AppStatus.attention,
            title: 'This count is still arriving',
            message:
                'The device that took it has not finished sending. Accepting '
                'it now would correct only the part that has arrived, so the '
                'server will refuse until the rest lands.',
          )
        : _applied || take.status == TenantStockTakeStatus.applied
        ? const Callout(
            key: ValueKey('stock-take-detail-applied'),
            status: AppStatus.ok,
            title: 'Accepted',
            message:
                'Every difference below has been written to the stock ledger, '
                'where it can be read against the product it moved.',
          )
        : sorted.isEmpty
        ? const Callout(
            key: ValueKey('stock-take-detail-agreed'),
            status: AppStatus.ok,
            title: 'Everything counted agreed with the books',
            message: 'There is nothing to correct.',
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: EdgeInsets.all(inset),
            children: <Widget>[
              if (standing != null) ...<Widget>[
                standing,
                SizedBox(height: tokens.spacing.s16),
              ],
              _TenantStockTakeSummary(take: take),
              if (sorted.isNotEmpty) ...<Widget>[
                SizedBox(height: tokens.spacing.s24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Text(
                      'What differs',
                      style: tokens.typography.labelMedium.copyWith(
                        color: colors.text.primary,
                      ),
                    ),
                    SizedBox(width: tokens.spacing.s12),
                    Expanded(
                      child: Text(
                        key: const ValueKey('stock-take-detail-order'),
                        agreed > 0
                            ? 'Biggest first · $agreed that agreed are not '
                                  'listed'
                            : 'Biggest first',
                        style: tokens.typography.caption.copyWith(
                          color: colors.text.tertiary,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: tokens.spacing.s12),
                if (RecordSheet.drawnAt(MediaQuery.sizeOf(context).width))
                  RecordSheet(
                    columns: const [
                      SheetColumn(
                        label: 'Product',
                        kind: SheetColumnKind.identity,
                      ),
                      SheetColumn(
                        label: 'Counted',
                        kind: SheetColumnKind.figure,
                      ),
                      SheetColumn(
                        label: 'Recorded',
                        kind: SheetColumnKind.figure,
                      ),
                      SheetColumn(
                        label: 'Difference',
                        kind: SheetColumnKind.figure,
                      ),
                      SheetColumn(label: 'Status', kind: SheetColumnKind.text),
                    ],
                    rows: [
                      for (final line in sorted)
                        SheetRow(
                          id: line.productId,
                          key: ValueKey('stock-take-line-${line.productId}'),
                          cells: [
                            SheetText(
                              loaded.names[line.productId] ?? line.productId,
                              caption: !line.matched
                                  ? 'No matching product on the server'
                                  : null,
                            ),
                            SheetFigure(
                              '${line.counted}',
                              key: ValueKey(
                                'stock-take-line-counted-${line.productId}',
                              ),
                            ),
                            SheetFigure(
                              line.matched ? '${line.expected}' : '\u2014',
                              key: ValueKey(
                                'stock-take-line-expected-${line.productId}',
                              ),
                            ),
                            SheetFigure(
                              line.variance?.toString() ?? '\u2014',
                              key: ValueKey(
                                'stock-take-line-variance-${line.productId}',
                              ),
                            ),
                            SheetText(
                              line.isApplied
                                  ? 'Corrected'
                                  : 'Awaiting correction',
                            ),
                          ],
                          fold: line.movedWhileCounting
                              ? SheetFold(
                                  note:
                                      'The phone held ${line.seenQuantity} when the number was typed, so the books moved while counting.',
                                  noteKey: ValueKey(
                                    'stock-take-line-seen-${line.productId}',
                                  ),
                                  alwaysOpen: true,
                                )
                              : null,
                        ),
                    ],
                  )
                else
                  for (final (index, line) in sorted.indexed) ...<Widget>[
                    if (index > 0) SizedBox(height: tokens.spacing.s12),
                    _TenantStockTakeLineCard(
                      key: ValueKey('stock-take-line-${line.productId}'),
                      line: line,
                      name: loaded.names[line.productId],
                    ),
                  ],
              ],
            ],
          ),
        ),
        // **Pinned, the way the counting screen pins its hand-in**, with the
        // sentence that stops somebody reading the result as a bug under it.
        if (canAccept)
          ColoredBox(
            color: colors.surface.base,
            child: SafeArea(
              top: false,
              minimum: EdgeInsets.fromLTRB(
                inset - gutter,
                tokens.spacing.s12,
                inset - gutter,
                tokens.spacing.s20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AppButton(
                    key: const ValueKey('stock-take-accept'),
                    label: 'Accept and correct the stock',
                    tier: AppButtonTier.primary,
                    expand: !RecordSheet.drawnAt(
                      MediaQuery.sizeOf(context).width,
                    ),
                    loading: _applying,
                    onPressed: widget.applyCallable == null || _applying
                        ? null
                        : () => _apply(session, sorted.length),
                  ),
                  SizedBox(height: tokens.spacing.s8),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: gutter),
                    child: Text(
                      key: const ValueKey('stock-take-accept-note'),
                      'Each correction is the difference this count found, not '
                      'the figure it counted. Anything sold since then stays '
                      'sold.',
                      style: tokens.typography.caption.copyWith(
                        color: colors.text.tertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _apply(TenantSession session, int differing) async {
    final callable = widget.applyCallable;
    if (callable == null || _applying) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Accept this count?',
      consequence:
          'This writes $differing ${differing == 1 ? 'correction' : 'corrections'} '
          'to the stock ledger, moving ${widget.take.absoluteVarianceUnits} '
          'units in total.',
      // §8 rule 6, and the sentence that stops somebody reading the result as a
      // bug. Sales since the count are real movements of their own.
      stillTrue:
          'Each correction is the difference the count found, not the figure it '
          'counted. Anything sold since then stays sold.',
      // One word, because the longer label was truncated to "Accept the c..."
      // on a phone - and `ConfirmDialog`'s title already asks the question.
      confirmLabel: 'Accept',
      cancelLabel: 'Not yet',
      // **Chosen, where it used to be the `destructive` default nobody passed.**
      // Accepting a count writes ledger entries; it removes and reverses
      // nothing, which is what that tier is for.
      tier: AppButtonTier.primary,
      confirmKey: const ValueKey('stock-take-accept-confirm'),
    );
    if (!confirmed || !mounted) return;

    setState(() => _applying = true);
    try {
      final outcome = await applyWholeStockTake(
        callable: callable,
        tenantId: session.tenantId,
        takeId: widget.take.id,
      );
      if (!mounted) return;
      setState(() => _applied = true);
      widget.onApplied?.call();
      showAppSnackBar(
        context,
        AppNotice.confirmed(
          'Accepted. ${outcome.applied} '
          '${outcome.applied == 1 ? 'product' : 'products'} corrected.',
        ),
      );
    } on TenantStockTakeApplyException catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, _failureNotice(error.failure));
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  AppNotice _failureNotice(TenantStockTakeApplyFailure failure) =>
      switch (failure) {
        TenantStockTakeApplyFailure.forbidden => const AppNotice.refused(
          'You are not allowed to correct stock in this business, so nothing '
          'was changed.',
        ),
        TenantStockTakeApplyFailure.stillArriving => const AppNotice.refused(
          'This count has not finished arriving, so nothing was changed. Try '
          'again once the rest of it lands.',
        ),
        TenantStockTakeApplyFailure.missing => const AppNotice.refused(
          'This count is no longer on the server, so nothing was changed.',
        ),
        TenantStockTakeApplyFailure.invalidStoredQuantity =>
          const AppNotice.refused(
            'A product in this count holds a quantity that is not a whole '
            'number, so it cannot be corrected. That needs reconciliation '
            'first.',
          ),
        // **Never "nothing happened".** A refusal partway through has already
        // written part of the count, and saying otherwise would send somebody
        // looking for corrections that are already there.
        TenantStockTakeApplyFailure.ambiguous => const AppNotice.unknown(
          'This count has not finished being accepted. Part of it may already '
          'be in the stock ledger. Open it again to see what is left.',
        ),
        TenantStockTakeApplyFailure.refused => const AppNotice.refused(
          'This count was not accepted and nothing was changed.',
        ),
      };
}

/// The count in three figures: how many were counted, how many differ, and by
/// how many units in total.
final class _TenantStockTakeSummary extends StatelessWidget {
  const _TenantStockTakeSummary({required this.take});

  final TenantStockTakeRecord take;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final divider = VerticalDivider(
      width: tokens.spacing.s24 + 1,
      thickness: 1,
      color: tokens.colors.surface.borderSubtle,
    );
    return AppCard(
      key: const ValueKey('stock-take-detail-summary'),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: _figure(
                tokens,
                id: 'counted',
                value: take.countedLineCount,
                caption: 'counted',
              ),
            ),
            divider,
            Expanded(
              child: _figure(
                tokens,
                id: 'differ',
                value: take.varianceLineCount,
                caption: take.varianceLineCount == 1 ? 'differs' : 'differ',
              ),
            ),
            divider,
            Expanded(
              child: _figure(
                tokens,
                id: 'units',
                value: take.absoluteVarianceUnits,
                caption: take.absoluteVarianceUnits == 1
                    ? 'unit apart'
                    : 'units apart',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _figure(
    AppTokens tokens, {
    required String id,
    required int value,
    required String caption,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Text(
        '$value',
        key: ValueKey('stock-take-detail-$id'),
        style: tokens.typography.numericCompact.copyWith(
          color: tokens.colors.text.primary,
        ),
      ),
      Text(
        caption,
        style: tokens.typography.caption.copyWith(
          color: tokens.colors.text.tertiary,
        ),
      ),
    ],
  );
}

/// One product that did not agree with the books.
///
/// **The difference is the box at the trailing edge**, because it is what the
/// line is listed for; the figures that make it are the words on the left.
/// Short, over and unmatched say themselves in words and a sign as well as in
/// the box's colour.
final class _TenantStockTakeLineCard extends StatelessWidget {
  const _TenantStockTakeLineCard({
    super.key,
    required this.line,
    required this.name,
  });

  final TenantStockTakeLineRecord line;

  /// Null when the product could not be read, which falls back to its ID: the
  /// only thing certainly true about a line whose product is not there.
  final String? name;

  /// The difference box's width: the counting screen's box, so the figure a
  /// count is about sits in a box of one size on both of its screens.
  static double boxWidth(AppTokens tokens) =>
      tokens.spacing.s48 + tokens.spacing.s48;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    return AppCard(
      padding: EdgeInsets.all(tokens.spacing.s12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  name ?? line.productId,
                  style: tokens.typography.titleMedium.copyWith(
                    color: colors.text.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!line.matched) ...<Widget>[
                  SizedBox(height: tokens.spacing.s4),
                  Text(
                    'No product on the server answers to this yet',
                    style: tokens.typography.bodyMedium.copyWith(
                      color: colors.text.tertiary,
                    ),
                  ),
                ],
                SizedBox(height: tokens.spacing.s8),
                Wrap(
                  spacing: tokens.spacing.s16,
                  runSpacing: tokens.spacing.s4,
                  children: <Widget>[
                    _figure(
                      tokens,
                      label: 'Counted',
                      value: Text(
                        '${line.counted}',
                        key: ValueKey(
                          'stock-take-line-counted-${line.productId}',
                        ),
                        style: _figureStyle(tokens).copyWith(
                          color: colors.text.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _figure(
                      tokens,
                      label: 'Books said',
                      value: Text(
                        line.matched ? '${line.expected}' : 'nothing',
                        key: ValueKey(
                          'stock-take-line-expected-${line.productId}',
                        ),
                        style: line.matched
                            ? _figureStyle(tokens).copyWith(
                                color: colors.status.info.fg,
                                fontWeight: FontWeight.w700,
                              )
                            : tokens.typography.bodyMedium.copyWith(
                                color: colors.text.tertiary,
                              ),
                      ),
                    ),
                  ],
                ),
                // The window `seenQuantity` exists for, said plainly: it is the
                // difference between a shortfall and a count taken while the
                // shop was still trading. **Only when the books did move** - a
                // note on every line saying nothing happened is noise.
                if (line.movedWhileCounting) ...<Widget>[
                  SizedBox(height: tokens.spacing.s8),
                  _note(
                    tokens,
                    key: ValueKey('stock-take-line-seen-${line.productId}'),
                    message:
                        'The phone held ${line.seenQuantity} when the number '
                        'was typed, so the books moved while counting.',
                  ),
                ],
                if (line.isApplied) ...<Widget>[
                  SizedBox(height: tokens.spacing.s8),
                  StatusBadge(
                    key: ValueKey(
                      'stock-take-line-corrected-${line.productId}',
                    ),
                    status: AppStatus.ok,
                    label: 'Corrected',
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: tokens.spacing.s12),
          _difference(tokens),
        ],
      ),
    );
  }

  /// A figure beside a body-sized label: `numeric.body`'s face at `body.lg`'s
  /// size, so the number reads a step above the words naming it.
  static TextStyle _figureStyle(AppTokens tokens) =>
      tokens.typography.numericBody.copyWith(
        fontSize: tokens.typography.bodyLarge.fontSize,
        height: tokens.typography.bodyLarge.height,
      );

  /// One labelled figure: *Counted 41*.
  Widget _figure(
    AppTokens tokens, {
    required String label,
    required Widget value,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: <Widget>[
      Text(
        label,
        style: tokens.typography.bodyMedium.copyWith(
          color: tokens.colors.text.secondary,
        ),
      ),
      SizedBox(width: tokens.spacing.s4),
      value,
    ],
  );

  /// The difference, signed and named: *-7 short*, *+3 over*, or *unmatched*.
  Widget _difference(AppTokens tokens) {
    final variance = line.variance;
    final role = variance == null
        ? tokens.colors.status.attention
        : tokens.colors.status.problem;
    final Widget mark = variance == null
        ? Icon(
            Icons.warning_amber_rounded,
            size: tokens.spacing.s24,
            color: role.fg,
          )
        : Text(
            variance > 0 ? '+$variance' : '$variance',
            key: ValueKey('stock-take-line-variance-${line.productId}'),
            style: tokens.typography.numericHero.copyWith(color: role.fg),
          );
    final word = switch (variance) {
      null => 'unmatched',
      > 0 => 'over',
      _ => 'short',
    };
    return Container(
      width: boxWidth(tokens),
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.s8,
        vertical: tokens.spacing.s12,
      ),
      decoration: BoxDecoration(
        color: role.bg,
        border: Border.all(color: role.border),
        borderRadius: BorderRadius.circular(tokens.radius.md),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          mark,
          SizedBox(height: tokens.spacing.s4),
          Text(
            word,
            key: ValueKey('stock-take-line-word-${line.productId}'),
            style: tokens.typography.labelMedium.copyWith(
              color: tokens.colors.text.primary,
            ),
          ),
        ],
      ),
    );
  }

  /// A tinted aside under the figures, the same shape a count's card uses.
  Widget _note(AppTokens tokens, {required Key key, required String message}) {
    final role = tokens.colors.status.info;
    return DecoratedBox(
      key: key,
      decoration: BoxDecoration(
        color: role.bg,
        border: Border.all(color: role.border),
        borderRadius: BorderRadius.circular(tokens.radius.md),
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.s8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.info_outline,
              size: StatusBadge.iconSize,
              color: role.fg,
            ),
            SizedBox(width: tokens.spacing.s8),
            Expanded(
              child: Text(
                message,
                style: tokens.typography.caption.copyWith(
                  color: tokens.colors.text.secondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
