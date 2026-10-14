import 'package:flutter/material.dart';

import '../checkout/checkout_draft.dart';
import '../reporting/reporting_currency.dart';
import '../reporting/shift_amendment_feed.dart';
import '../reporting/shift_amendment_feed_panel.dart';
import '../returns/return_actions.dart';
import '../inventory/product_image_cache.dart';
import '../reports/analysis/shifts_analysis.dart';
import '../reports/analysis/shifts_report.dart';
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
import '../tenancy/tenant_staff_directory.dart';
import '../tenancy/tenant_staff_names.dart';
import '../ui/buttons.dart';
import '../ui/fields.dart';
import '../ui/money_text.dart';
import '../ui/pagination.dart';
import '../ui/record_list.dart';
import '../ui/record_sheet.dart';
import '../ui/routes.dart';
import '../ui/scaffold.dart';
import '../ui/skeleton.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'shift_history.dart';
import 'shift_history_card.dart';
import '../observability/app_telemetry.dart';

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
/// - **A day and a person, in one row** - the pair the sales report carries,
///   since 2026-09-22 and at the product owner's direction. It replaced a *My
///   shifts / Every cashier* toggle, a strip naming the days the page covered,
///   three tiles and a notice adding the page up, and a row of chips narrowing
///   it: five things between the title and the first shift, every one of them
///   about *which twenty happened to be read*. A day is a question the read
///   answers exactly, and each card still says whether it settled.
/// - **Days are groups**, so `2026-07-31 - Brian` stops being a record title.
/// - **The difference is the figure with the weight**, and only where there is
///   one. See `shift_history_card.dart`.
final class TenantShiftHistoryScreen extends StatelessWidget {
  const TenantShiftHistoryScreen({
    super.key,
    required this.reader,
    required this.salesReportRoute,
    this.returnActions,
    this.pageSize = 20,
    this.clock,
    this.reportSaver,
    this.imageCache,
  });

  final TenantDataReader reader;

  /// Where a generated report goes. Null renders no toolbar control at all.
  final TenantReportSaver? reportSaver;

  /// Fetches the logo the report's branding band draws.
  final TenantImageCache? imageCache;

  /// Forwarded to the panel. See [TenantShiftHistoryPanel.salesReportRoute].
  final ShiftSalesReportRoute salesReportRoute;

  /// Passed through to the sales and returns routes. Recording a return stays
  /// unavailable while it is absent.
  final TenantReturnActions? returnActions;

  /// Forwarded to the panel, so a test can drive the route rather than the
  /// panel inside it.
  final int pageSize;

  /// Forwarded to the panel. See [TenantShiftHistoryPanel.clock].
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Shift history',
    contentWidth: RecordSheet.contentWidth(context),
    // **One toolbar control since 2026-09-24.** *My recent sales* and the
    // reconciliation explainer were taken off this bar on 2026-09-23 because
    // the day and the person above the list are the whole of what the page
    // asks. This is not a third question about the page - it is a copy of a
    // period taken away, which is chrome by the same reading.
    actions: <Widget>[
      TenantSessionReportAction(
        clock: clock ?? DateTime.now,
        runFor: (session) => _reportRun(session),
      ),
    ],
    body: TenantShiftHistoryPanel(
      reader: reader,
      salesReportRoute: salesReportRoute,
      returnActions: returnActions,
      pageSize: pageSize,
      clock: clock,
    ),
  );

  /// Shifts over a period, which the day filter cannot ask for.
  ///
  /// **Management only, and there is no own-shifts version.** A period report
  /// over the whole business is the every-cashier permission whichever way it
  /// is sliced, so a cashier gets no control rather than one covering only
  /// themselves - which would read as the shop's and be one person's.
  TenantReportRun? _reportRun(TenantSession session) {
    final saver = reportSaver;
    if (saver == null) return null;
    if (!TenantShiftHistoryRepository.canReadEveryCashier(session)) return null;

    final now = clock ?? DateTime.now;
    return TenantReportRun(
      kind: TenantReportKind.shifts,
      support: TenantReportPeriodSupport.range,
      saver: saver,
      build: (period) async {
        final source = TenantShiftsReportSource(
          repository: TenantShiftHistoryRepository(
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
        final analysis = TenantShiftsAnalysis.from(
          period: period,
          shifts: read.shifts,
          previous: previous,
          truncated: read.truncated,
        );
        return describeShiftsReport(
          identity: identity,
          analysis: analysis,
          people: await readTenantReportPeople(
            session: session,
            reader: reader,
            uids: analysis.people
                .take(TenantShiftsAnalysis.listed)
                .map((person) => person.staffId),
          ),
        );
      },
    );
  }
}

/// Builds the Sales report opened on [businessDate], narrowed to [staffId].
///
/// **A route handed in rather than built here**, because the report needs what
/// only the composition root holds - its totals callable, its reprinter, the
/// till's outbox and catalog - and a report built without them would be a
/// thinner screen than the one the home opens, under the same name.
typedef ShiftSalesReportRoute =
    Widget Function({required String businessDate, required String staffId});

/// The colleagues the staff filter offers, and their names.
///
/// **One bounded page of the canonical staff**, read the way the sales report's
/// own staff filter reads it (`SalesTotalsSessionContextLoader`) and degraded
/// the same way: a roster the server will not give leaves *All staff* and the
/// session's own shifts, both of which are answerable from the session alone.
@immutable
final class ShiftHistoryRoster {
  const ShiftHistoryRoster({required this.uids, required this.names});

  /// Nothing read: a cashier's, who is offered no one, or one refused.
  static const ShiftHistoryRoster unread = ShiftHistoryRoster(
    uids: <String>[],
    names: <String, String>{},
  );

  final List<String> uids;

  /// Display names by UID. A member with none recorded degrades to the UID.
  final Map<String, String> names;
}

/// One day's closed shifts, the names behind their UIDs, what the business
/// calls its money, and who the staff filter can offer.
///
/// **One bundle rather than four reads the page composes**, for the reason the
/// guard exists: a tenant switch mid-flight discards the whole answer, and
/// separately-awaited futures would give it several things to discard and as
/// many chances to draw half of one session's page under another's.
@immutable
final class ShiftHistoryLoad {
  const ShiftHistoryLoad({
    required this.page,
    required this.names,
    required this.currency,
    this.roster = ShiftHistoryRoster.unread,
  });

  final TenantShiftHistoryPage page;
  final Map<String, String> names;
  final TenantReportingCurrency currency;
  final ShiftHistoryRoster roster;
}

/// Pages one day's closed shifts behind [TenantRouteGuard].
///
/// The guard owns authorization and stale-session rejection: a tenant switch
/// during an outstanding page discards that page before it can be rendered.
/// The panel owns only the day, whose shifts, and the cursor stack, and it
/// never recomputes a recorded figure.
final class TenantShiftHistoryPanel extends StatefulWidget {
  const TenantShiftHistoryPanel({
    super.key,
    required this.reader,
    required this.salesReportRoute,
    this.returnActions,
    this.pageSize = 20,
    this.staffPageSize = 25,
    this.clock,
  });

  final TenantDataReader reader;

  /// What a shift's card opens: the Sales report on that shift's business
  /// date, narrowed to the member who ran it.
  ///
  /// **The Sales report rather than the shift's own sales, since 2026-09-22
  /// and at the product owner's direction.** It is the screen a person already
  /// reads a day's sales on - totals, receipts, returns - opened exactly as its
  /// own two filters would leave it, and nothing is added to it for the trip.
  final ShiftSalesReportRoute salesReportRoute;

  /// Passed through to the sales route only. This surface never writes.
  final TenantReturnActions? returnActions;
  final int pageSize;

  /// The most colleagues the staff filter offers, in one page - the sales
  /// report's figure.
  final int staffPageSize;

  /// What *today* is. The screen opens on today's business date, as the sales
  /// report does, and a test pins the day here rather than racing midnight.
  final DateTime Function()? clock;

  @override
  State<TenantShiftHistoryPanel> createState() =>
      _TenantShiftHistoryPanelState();
}

final class _TenantShiftHistoryPanelState
    extends State<TenantShiftHistoryPanel> {
  /// The trading day on screen: today's when the screen opens.
  late String _businessDate;

  /// Whose shifts, as management chose them. Null is everyone's, which is
  /// where the sales report's own filter starts. A cashier's reads are their
  /// own whatever this holds - see [_staffFor].
  String? _staffId;

  /// The cursor that opened each visited page. The first page has none.
  List<String?> _cursors = <String?>[null];
  int _pageIndex = 0;
  final TenantStaffNameResolvers _staffNames = TenantStaffNameResolvers();

  /// The roster read, per session and pass, so a new day does not read it
  /// again. See [_rosterFor].
  final Map<String, Future<ShiftHistoryRoster>> _rosters =
      <String, Future<ShiftHistoryRoster>>{};

  /// The last roster each session finished reading. The staff filter draws
  /// from it while the next day is read, so its options do not vanish and come
  /// back every time the day changes.
  final Map<String, ShiftHistoryRoster> _knownRosters =
      <String, ShiftHistoryRoster>{};

  @override
  void initState() {
    super.initState();
    _businessDate = _today;
  }

  String get _today => checkoutBusinessDate(
    (widget.clock?.call() ?? DateTime.now().toUtc()).toUtc(),
  );

  /// One resolver per session **and per pass**, so the cached pass resolves a
  /// name from this device rather than putting a network read in front of
  /// records it already holds. An unresolved name degrades to the UID.
  TenantStaffNameResolver _resolverFor(
    TenantSession session,
    TenantDocumentReader reader,
  ) => _staffNames.of(session: session, reader: reader);

  static String _sessionKey(TenantSession session) =>
      '${session.uid}:${session.tenantId}:${session.epoch}';

  /// Whose shifts a read asks for: the filter's choice for management, and
  /// the session's own for everyone else.
  static String? _staffFor(TenantSession session, String? chosen) =>
      TenantShiftHistoryRepository.canReadEveryCashier(session)
      ? chosen
      : session.uid;

  void _resetPages() {
    _cursors = <String?>[null];
    _pageIndex = 0;
  }

  void _setBusinessDate(String businessDate) {
    if (businessDate == _businessDate) return;
    setState(() {
      _businessDate = businessDate;
      _resetPages();
    });
  }

  /// Opens the day picker and reads the day chosen.
  ///
  /// **Bounded above by today**: no shift can have been opened for a day that
  /// has not started, and offering one is offering an answer that is empty by
  /// construction. The floor is the returns feed's, for its reason.
  Future<void> _pickBusinessDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(_businessDate),
      firstDate: DateTime(2020),
      lastDate: DateTime.parse(_today),
      helpText: 'Select shift date',
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

  /// The roster, read once per session and pass however many days are read.
  Future<ShiftHistoryRoster> _rosterFor(
    TenantSession session,
    TenantDataReader reader,
    String pass,
  ) {
    final key = _sessionKey(session);
    return _rosters.putIfAbsent('$key:$pass', () async {
      final roster = await _readRoster(session, reader);
      _knownRosters[key] = roster;
      return roster;
    });
  }

  Future<ShiftHistoryRoster> _readRoster(
    TenantSession session,
    TenantDataReader reader,
  ) async {
    // A cashier is offered no one, so nothing is read on their behalf.
    if (!TenantShiftHistoryRepository.canReadEveryCashier(session)) {
      return ShiftHistoryRoster.unread;
    }
    try {
      final page = await TenantStaffDirectoryRepository(
        session: session,
        reader: reader,
      ).loadPage(pageSize: widget.staffPageSize);
      return ShiftHistoryRoster(
        uids: <String>[for (final member in page.items) member.uid],
        names: <String, String>{
          for (final member in page.items)
            if (member.name case final name?) member.uid: name,
        },
      );
    } on TenantScopeViolation {
      rethrow;
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'shift.history_roster_read',
      );
      return ShiftHistoryRoster.unread;
    }
  }

  /// One loader pair per day, person and page, memoised so an unrelated
  /// rebuild does not restart the read. See [TenantRouteGuard.load].
  void _composeLoaders(String key) {
    if (key == _loaderKey && _loader != null) return;
    _loaderKey = key;
    final cursor = _cursors[_pageIndex];
    final businessDate = _businessDate;
    final chosen = _staffId;
    TenantGuardedLoader<ShiftHistoryLoad> readWith(
      TenantDataReader reader,
      String pass,
    ) => (session) async {
      final roster = await _rosterFor(session, reader, pass);
      final page =
          await TenantShiftHistoryRepository(
            session: session,
            reader: reader,
          ).loadDayPage(
            businessDate: businessDate,
            staffId: _staffFor(session, chosen),
            pageSize: widget.pageSize,
            cursor: cursor,
          );
      return ShiftHistoryLoad(
        page: page,
        names: await _resolverFor(
          session,
          reader,
        ).resolve(page.items.map((entry) => entry.staffId)),
        // **Degrades to an unlabelled figure rather than failing the page.** A
        // shift history that would not open because the business never
        // published a currency would be a reconciliation screen withheld over
        // a label; see [TenantReportingCurrency].
        currency: await TenantReportingCurrency.read(
          session: session,
          reader: reader,
        ),
        roster: roster,
      );
    };
    _loader = readWith(widget.reader, 'live');
    final cache = widget.reader.cached;
    _loaderCached = cache == null ? null : readWith(cache, 'cached');
  }

  String? _loaderKey;
  TenantGuardedLoader<ShiftHistoryLoad>? _loader;
  TenantGuardedLoader<ShiftHistoryLoad>? _loaderCached;

  @override
  Widget build(BuildContext context) {
    // A new loader for a new day, person or page, which is what stops an
    // earlier read completing into the current one - the guard bumps its
    // generation when this closure changes, and a late answer is discarded.
    _composeLoaders(
      '$_businessDate:${_staffId ?? '-'}:$_pageIndex:${_cursors[_pageIndex]}',
    );
    // **The filters are drawn in every state, the sales report's call.** While
    // a day is read, and after one fails, a person can still ask for another.
    // The session comes from the scope because the guard has not admitted one
    // yet; a denied session is the guard's own case and never reaches these.
    final scoped = TenantSessionScope.of(context).session;
    Widget contents(
      BuildContext context,
      TenantSession session, {
      ShiftHistoryLoad? load,
      bool failed = false,
    }) => _ShiftHistoryContents(
      session: session,
      load: load,
      failed: failed,
      businessDate: _businessDate,
      staffId: _staffFor(session, _staffId),
      roster: load?.roster ?? _knownRosters[_sessionKey(session)],
      pageIndex: _pageIndex,
      // The trail's own repository is the authority on who may read it, not
      // this surface's management set. The two happen to name the same roles
      // today, and offering a link this session's server would refuse would
      // teach a cashier nothing except that the app guesses.
      canReadCorrections: TenantShiftAmendmentFeedRepository.canReadInSession(
        session,
      ),
      onPickDate: _pickBusinessDate,
      onStaffChanged: _setStaff,
      onNextPage: load == null ? null : () => _nextPage(load.page.nextCursor),
      onPreviousPage: _previousPage,
      onViewSales: (entry) => _openSalesReport(context, entry),
      onViewCorrections: (shiftId) => _openCorrections(context, shiftId),
    );
    return TenantRouteGuard<ShiftHistoryLoad>(
      load: _loader!,
      loadCached: _loaderCached,
      holdsNothing: (load) => load.page.items.isEmpty,
      loading: switch (scoped) {
        final session? => contents(context, session),
        // No session in scope at all is the guard's own `denied` case arriving
        // a frame early. Drawing nothing is what it draws.
        null => const SizedBox.shrink(),
      },
      denied: const Center(
        key: ValueKey('shift-history-denied'),
        child: EmptyState(
          illustration: 'access-denied.svg',
          title: 'Shift history unavailable',
          hint: 'Your role cannot view closed shifts.',
        ),
      ),
      failure: (context, error) => switch (scoped) {
        final session? => contents(context, session, failed: true),
        null => const SizedBox.shrink(),
      },
      builder: (context, session, load) =>
          contents(context, session, load: load),
    );
  }

  /// Opens the Sales report on [entry]'s business date, narrowed to the member
  /// who ran it, under the same session scope - so the report's own guard sees
  /// the exact controller this page was authorized against. See
  /// [TenantShiftHistoryPanel.salesReportRoute].
  void _openSalesReport(BuildContext context, TenantShiftHistoryEntry entry) {
    final sessions = TenantSessionScope.read(context);
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => TenantSessionScope(
          controller: sessions,
          child: widget.salesReportRoute(
            businessDate: entry.businessDate,
            staffId: entry.staffId,
          ),
        ),
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

final class _ShiftHistoryContents extends StatelessWidget {
  const _ShiftHistoryContents({
    required this.session,
    required this.load,
    required this.failed,
    required this.businessDate,
    required this.staffId,
    required this.roster,
    required this.pageIndex,
    required this.canReadCorrections,
    required this.onPickDate,
    required this.onStaffChanged,
    required this.onNextPage,
    required this.onPreviousPage,
    required this.onViewSales,
    required this.onViewCorrections,
  });

  final TenantSession session;

  /// The day's page, or null while it is read and after it failed to be.
  final ShiftHistoryLoad? load;

  /// Whether the read failed. The filters stay, so another day is one tap.
  final bool failed;

  final String businessDate;

  /// Whose shifts are asked for: null is everyone's. Always the session's own
  /// for a cashier.
  final String? staffId;

  /// Who the staff filter can offer, or null before anything has been read.
  final ShiftHistoryRoster? roster;

  final int pageIndex;

  /// Whether this session may read the corrections trail itself. A cashier is
  /// still told that their shift was corrected - the shift document they can
  /// already read says so, and the figures on the row are the corrected ones -
  /// but the record of who asked for it and why is the business's governance and
  /// is deliberately not theirs to read.
  final bool canReadCorrections;

  final VoidCallback onPickDate;
  final ValueChanged<String?> onStaffChanged;
  final VoidCallback? onNextPage;
  final VoidCallback onPreviousPage;

  /// Opens the Sales report for a shift's day and member.
  final ValueChanged<TenantShiftHistoryEntry> onViewSales;

  /// Opens the trail narrowed to one shift, by its document ID.
  final ValueChanged<String> onViewCorrections;

  /// The staff filter's value for *All staff*. Never a UID: a UID is not empty.
  static const String _everyone = '';

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final loaded = load;
    final table = RecordSheet.drawnAt(MediaQuery.sizeOf(context).width);
    return PagedListView(
      listKey: const ValueKey('shift-history'),
      padding: RecordSheet.pagePadding(
        context,
        fallback: EdgeInsets.all(tokens.spacing.s20),
      ),
      pagination: loaded == null
          ? null
          : Pagination(
              pageNumber: pageIndex + 1,
              previousKey: const ValueKey('shift-history-previous'),
              nextKey: const ValueKey('shift-history-next'),
              onPrevious: pageIndex > 0 ? onPreviousPage : null,
              onNext: loaded.page.hasMore ? onNextPage : null,
              endOfList: !loaded.page.hasMore,
            ),
      children: <Widget>[
        if (!table) _filters(tokens),
        // **Said once, and only where it is true.** Reporting never assumes a
        // currency, so a business that has published none gets bare figures
        // and one sentence saying why - rather than `KES` guessed onto a
        // screen people settle cash from.
        if (loaded != null && !loaded.currency.isKnown) ...<Widget>[
          if (!table) SizedBox(height: tokens.spacing.s12),
          const Callout(
            key: ValueKey('shift-history-currency-unknown'),
            status: AppStatus.info,
            message: TenantReportingCurrency.unknownNotice,
          ),
          if (table) SizedBox(height: tokens.spacing.s20),
        ],
        if (table)
          _sheet(tokens)
        else ...<Widget>[
          SizedBox(height: tokens.spacing.s20),
          ..._cards(tokens),
        ],
      ],
    );
  }

  static const Widget _failure = ErrorState(
    key: ValueKey('shift-history-failure'),
    badgeLabel: 'Not read',
    statement: 'This page of shifts did not load',
    stillTrue:
        'Nothing has changed, and every shift is still recorded on the '
        'server.',
  );

  static const Widget _empty = EmptyState(
    key: ValueKey('shift-history-empty'),
    title: 'No closed shifts on this day',
    hint: 'Close a shift from the shift banner.',
    illustration: 'closed-shift.svg',
  );

  /// The phone's and the tablet's list: one card per shift, under its day.
  /// Unchanged by the table.
  List<Widget> _cards(AppTokens tokens) {
    final loaded = load;
    return <Widget>[
      if (failed)
        _failure
      else if (loaded == null)
        // **Placeholder cards rather than a spinner**, because this list is
        // what the wait is for and its shape is known before its contents
        // are. §5.1's `LoadingState` stays the guard's default everywhere the
        // shape is not.
        const SkeletonGroup(
          semanticLabel: 'Reading closed shifts.',
          child: RecordListSkeleton(),
        )
      else if (loaded.page.items.isEmpty)
        _empty
      else
        ..._days(tokens, loaded),
    ];
  }

  /// The day, and whose shifts - one row, as the sales report draws its own.
  ///
  /// **No caption over either control**, for the sales report's reason: a
  /// button showing a date behind a calendar glyph does not need *Date* over
  /// it, and a select reading *All staff* does not need *Staff*. Both keep the
  /// word as what a screen reader hears.
  Widget _filters(AppTokens tokens) {
    final date = _dateFilter(expand: true);
    final staff = _staffFilter();
    // A cashier reads their own shifts and nothing else, so there is nobody to
    // choose between and the day takes the row.
    if (staff == null) return date;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: date),
        SizedBox(width: tokens.spacing.s12),
        Expanded(child: staff),
      ],
    );
  }

  Widget _dateFilter({required bool expand}) => Semantics(
    key: const ValueKey('shift-history-date-filter'),
    label: 'Shifts for $businessDate. Change the day.',
    button: true,
    excludeSemantics: true,
    child: AppButton(
      key: const ValueKey('shift-history-date-picker'),
      label: businessDate,
      icon: Icons.calendar_today_outlined,
      tier: AppButtonTier.secondary,
      expand: expand,
      onPressed: onPickDate,
    ),
  );

  /// Whose shifts, for management. Null for a cashier, who reads their own.
  Widget? _staffFilter() {
    if (!TenantShiftHistoryRepository.canReadEveryCashier(session)) {
      return null;
    }
    final offered = roster;
    final names = offered?.names ?? const <String, String>{};
    String label(String uid) =>
        tenantStaffLabel(uid, names: names, selfUid: session.uid);
    final chosen = staffId;
    final listed = offered?.uids ?? const <String>[];
    return AppSelect<String>(
      key: const ValueKey('shift-history-staff-filter'),
      value: chosen ?? _everyone,
      label: 'Staff',
      dense: true,
      leading: Icons.person_outline,
      // **Disabled rather than absent until the roster is read**, for the sales
      // report's reason: absent would move the day from half the row to all of
      // it and back again.
      enabled: offered != null,
      items: <AppSelectItem<String>>[
        const AppSelectItem<String>(
          key: ValueKey('shift-history-staff-all'),
          value: _everyone,
          label: 'All staff',
        ),
        // The session's own shifts are on offer whatever the roster says: its
        // UID comes from the session, which no read can make unavailable.
        AppSelectItem<String>(
          key: const ValueKey('shift-history-staff-self'),
          value: session.uid,
          label: label(session.uid),
        ),
        for (final uid in listed)
          if (uid != session.uid)
            AppSelectItem<String>(
              key: ValueKey<String>('shift-history-staff-$uid'),
              value: uid,
              label: label(uid),
            ),
        // A choice this roster does not list - another business's colleague,
        // after a switch - is still drawn: a select has to hold what it shows.
        if (chosen != null && chosen != session.uid && !listed.contains(chosen))
          AppSelectItem<String>(value: chosen, label: label(chosen)),
      ],
      onChanged: (value) =>
          onStaffChanged(value == null || value == _everyone ? null : value),
    );
  }

  /// The large-screen list: one table, its filters on its top edge.
  ///
  /// **The same page, read the same way, drawn as rows** - `docs/design/
  /// tables/`, the Sales and Widths boards. A shift is a row of the figures the
  /// card stacks: its hours, its sales, the recorded and counted amounts, the
  /// difference between them signed, and the standing. What a card adds only
  /// sometimes - a float, credit, repayments, refunds, or why there is nothing
  /// to compare - folds under the row that has it, so every row is the same
  /// height until somebody asks.
  Widget _sheet(AppTokens tokens) {
    final loaded = load;
    final onePerson = staffId != null;
    final code = loaded?.currency.code;
    final columns = <SheetColumn>[
      // **The cashier names a row only where the rows are different cashiers**,
      // the cards' rule: with one person chosen, the hours name the shift.
      if (!onePerson)
        const SheetColumn(label: 'Cashier', kind: SheetColumnKind.identity),
      SheetColumn(
        label: 'Hours',
        kind: onePerson ? SheetColumnKind.identity : SheetColumnKind.time,
      ),
      const SheetColumn(label: 'Sales', kind: SheetColumnKind.figure),
      SheetColumn(label: 'Recorded', kind: SheetColumnKind.figure, unit: code),
      SheetColumn(label: 'Counted', kind: SheetColumnKind.figure, unit: code),
      SheetColumn(
        label: 'Difference',
        kind: SheetColumnKind.figure,
        unit: code,
      ),
      const SheetColumn(label: 'Standing', kind: SheetColumnKind.status),
    ];
    final staff = _staffFilter();
    final bar = Row(
      children: <Widget>[
        _dateFilter(expand: false),
        if (staff != null) ...<Widget>[
          SizedBox(width: tokens.spacing.s12),
          SizedBox(width: tokens.layout.tableFilter, child: staff),
        ],
      ],
    );
    final Widget? state;
    if (failed) {
      state = _failure;
    } else if (loaded != null && loaded.page.items.isEmpty) {
      state = _empty;
    } else {
      state = null;
    }
    return RecordSheet(
      key: const ValueKey('shift-history-sheet'),
      columns: columns,
      bar: bar,
      body: state,
      rows: loaded == null || state != null
          ? null
          : _rows(loaded, columns, onePerson: onePerson),
      // No foot caption, at the developer's direction on 2026-10-13. What a
      // row opens is still each row's screen-reader hint.
      loadingLabel: 'Reading closed shifts.',
    );
  }

  /// The page as the sheet's rows, in the page's own order: oldest first, the
  /// order the day was worked in.
  ///
  /// **No day heading, at the developer's direction on 2026-10-13.** The date
  /// filter on the sheet's top edge already names the one day a page holds,
  /// so a band repeating it under the header said the same thing twice. The
  /// cards keep theirs.
  List<SheetRow> _rows(
    ShiftHistoryLoad loaded,
    List<SheetColumn> columns, {
    required bool onePerson,
  }) {
    final shown = loaded.page.items;
    final counted = columns.indexWhere((column) => column.label == 'Counted');

    // **Whole amounts hold `.00` as blank space where their column has cents**,
    // so `1,250` sits with its units under the units of `982.50`. Decided per
    // column from the amounts themselves, which this screen holds as minor
    // units - nothing is read back out of a formatted string.
    bool hasCents(Iterable<int?> amounts) =>
        amounts.any((minor) => minor != null && minor % 100 != 0);
    String? reserveFor(bool cents, int? minor) =>
        cents && (minor == null || minor % 100 == 0) ? '.00' : null;
    List<int> foldAmounts(TenantShiftHistoryEntry entry) => <int>[
      entry.openingFloatMinor,
      ...?switch (entry.summary) {
        final summary? => <int>[
          summary.creditOwedMinor,
          summary.repaidMinor,
          summary.refundedMinor,
        ],
        null => null,
      },
    ];
    final recordedCents = hasCents(
      shown.map((entry) => entry.summary?.totalSalesMinor),
    );
    final countedCents = hasCents(<int>[
      for (final entry in shown) ...<int>[
        entry.closingCashMinor,
        ...foldAmounts(entry),
      ],
    ]);
    final differenceCents = hasCents(
      shown.map((entry) => entry.cashVarianceMinor),
    );

    return <SheetRow>[
      for (final entry in shown)
        _row(
          loaded,
          entry,
          onePerson: onePerson,
          counted: counted,
          reserve: (
            recorded: (int? minor) => reserveFor(recordedCents, minor),
            counted: (int? minor) => reserveFor(countedCents, minor),
            difference: (int? minor) => reserveFor(differenceCents, minor),
          ),
        ),
    ];
  }

  SheetRow _row(
    ShiftHistoryLoad loaded,
    TenantShiftHistoryEntry entry, {
    required bool onePerson,
    required int counted,
    required ({
      String? Function(int?) recorded,
      String? Function(int?) counted,
      String? Function(int?) difference,
    })
    reserve,
  }) {
    final id = entry.id;
    final summary = entry.summary;
    final variance = entry.cashVarianceMinor;
    final standing = ShiftStanding.of(entry);
    final hours = shiftHoursLabel(entry);
    final title = onePerson
        ? hours
        : tenantStaffLabel(
            entry.staffId,
            names: loaded.names,
            selfUid: session.uid,
          );
    final who = tenantStaffLabelParts(
      entry.staffId,
      names: loaded.names,
      selfUid: session.uid,
    );
    final amendment = entry.amendment;

    final lines = <SheetFoldLine>[
      if (entry.openingFloatMinor > 0)
        _foldLine(
          'Opening float',
          entry.openingFloatMinor,
          counted,
          reserve.counted,
          ValueKey<String>('shift-history-float-$id'),
        ),
      if (summary != null && summary.creditOwedMinor > 0)
        _foldLine(
          'Sold on credit',
          summary.creditOwedMinor,
          counted,
          reserve.counted,
          ValueKey<String>('shift-history-credit-$id'),
        ),
      if (summary != null && summary.repaidMinor > 0)
        _foldLine(
          'Paid back by customers',
          summary.repaidMinor,
          counted,
          reserve.counted,
          ValueKey<String>('shift-history-repaid-$id'),
        ),
      if (summary != null && summary.refundedMinor > 0)
        _foldLine(
          'Handed back for returns',
          summary.refundedMinor,
          counted,
          reserve.counted,
          ValueKey<String>('shift-history-refunded-$id'),
        ),
    ];
    final silence = shiftSilenceSentence(standing);

    return SheetRow(
      id: id,
      key: ValueKey<String>('shift-history-entry-$id'),
      pressKey: ValueKey<String>('shift-history-sales-link-$id'),
      onPressed: () => onViewSales(entry),
      semanticLabel: title,
      semanticHint: "Opens the sales report for this shift's day and cashier.",
      cells: <SheetCell?>[
        if (!onePerson)
          SheetText(
            who.name,
            caption: who.under,
            key: ValueKey<String>('shift-history-subject-$id'),
            captionKey: ValueKey<String>('shift-history-uid-$id'),
          ),
        SheetText(
          hours,
          key: ValueKey<String>(
            onePerson
                ? 'shift-history-subject-$id'
                : 'shift-history-window-$id',
          ),
        ),
        switch (summary) {
          final closed? => SheetFigure(
            '${closed.transactionCount}',
            key: ValueKey<String>('shift-history-count-$id'),
          ),
          null => SheetFigure.unknown(
            key: ValueKey<String>('shift-history-count-$id'),
          ),
        },
        switch (summary) {
          final closed? => SheetFigure(
            moneyTextGroupedOfMinor(closed.totalSalesMinor),
            reserve: reserve.recorded(closed.totalSalesMinor),
            key: ValueKey<String>('shift-history-sales-$id'),
            // **The marker rides on the figure it is about**, as it does on the
            // card: a corrected shift's recorded sales are the rewritten ones.
            caption: amendment == null ? null : 'corrected ×${amendment.count}',
            captionKey: ValueKey<String>('shift-history-amended-$id'),
          ),
          null => SheetFigure.unknown(
            reserve: reserve.recorded(null),
            key: ValueKey<String>('shift-history-sales-$id'),
          ),
        },
        SheetFigure(
          moneyTextGroupedOfMinor(entry.closingCashMinor),
          reserve: reserve.counted(entry.closingCashMinor),
          key: ValueKey<String>('shift-history-counted-$id'),
        ),
        switch (variance) {
          final difference? => SheetFigure(
            shiftDifferenceLabel(difference),
            reserve: reserve.difference(difference),
            key: ValueKey<String>('shift-history-variance-$id'),
          ),
          null => SheetFigure.unknown(
            reserve: reserve.difference(null),
            key: ValueKey<String>('shift-history-variance-$id'),
          ),
        },
        SheetStatus(
          key: ValueKey<String>('shift-history-status-$id'),
          status: standing.status,
          label: standing.label,
          icon: standing.icon,
          semanticLabel: shiftStandingSemantics(entry),
          // A drawer that agreed is the one state nobody has to act on, so it
          // is a glyph and a word rather than a badge - which is what lets the
          // shifts that need a look stand out of the column.
          quiet: standing == ShiftStanding.settled,
        ),
      ],
      actions: <RecordAction>[
        if (amendment != null && canReadCorrections)
          RecordAction(
            label: "This shift's corrections",
            icon: Icons.history,
            onPressed: () => onViewCorrections(id),
            actionKey: ValueKey<String>('shift-history-corrections-link-$id'),
          ),
      ],
      actionsKey: ValueKey<String>('shift-history-menu-$id'),
      actionsTooltip: 'More for this shift',
      fold: silence == null && lines.isEmpty
          ? null
          : SheetFold(
              note: silence,
              noteKey: ValueKey<String>('shift-history-silence-$id'),
              lines: lines,
              toggleKey: ValueKey<String>('shift-history-fold-$id'),
              showLabel: "Show the rest of this shift's figures",
              hideLabel: "Hide the rest of this shift's figures",
            ),
    );
  }

  SheetFoldLine _foldLine(
    String label,
    int minor,
    int column,
    String? Function(int?) reserve,
    Key key,
  ) => SheetFoldLine(
    label: label,
    value: moneyTextGroupedOfMinor(minor),
    column: column,
    reserve: reserve(minor),
    valueKey: key,
  );

  /// The shifts, under the business day they belong to.
  ///
  /// **One day since the day became a filter**, so this draws one heading -
  /// with the count, which the button above it does not carry. It still cuts
  /// consecutive runs rather than assuming one, so the page's own order is kept
  /// exactly: oldest first, the order the day was worked in.
  List<Widget> _days(AppTokens tokens, ShiftHistoryLoad loaded) {
    final shown = loaded.page.items;
    // **The cashier names a row only where the rows are different cashiers.**
    // With one person chosen every title would be the same word, so the hours
    // name the shift and the filter names the person.
    final onePerson = staffId != null;
    final rows = <Widget>[];
    var index = 0;
    while (index < shown.length) {
      final day = shown[index].businessDate;
      var end = index;
      while (end < shown.length && shown[end].businessDate == day) {
        end++;
      }
      if (rows.isNotEmpty) rows.add(SizedBox(height: tokens.spacing.s20));
      rows.add(
        ShiftHistoryDayHeading(
          key: ValueKey<String>('shift-history-day-$day'),
          businessDate: day,
          count: end - index,
        ),
      );
      for (final entry in shown.sublist(index, end)) {
        rows
          ..add(SizedBox(height: ShiftHistoryCard.blockGap(tokens.spacing)))
          ..add(_card(loaded, entry, onePerson: onePerson));
      }
      index = end;
    }
    return rows;
  }

  Widget _card(
    ShiftHistoryLoad loaded,
    TenantShiftHistoryEntry entry, {
    required bool onePerson,
  }) {
    final window = shiftWindowLabel(entry);
    final sales = shiftSalesLabel(entry);
    return ShiftHistoryCard(
      entry: entry,
      title: onePerson
          ? window
          : tenantStaffLabel(
              entry.staffId,
              names: loaded.names,
              selfUid: session.uid,
            ),
      subtitle: onePerson ? sales : '$window · $sales',
      currency: loaded.currency,
      onViewSales: () => onViewSales(entry),
      onViewCorrections: entry.amendment != null && canReadCorrections
          ? () => onViewCorrections(entry.id)
          : null,
    );
  }
}
