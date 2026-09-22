import 'package:flutter/material.dart';

import '../checkout/checkout_draft.dart';
import '../reporting/reporting_currency.dart';
import '../reporting/shift_amendment_feed.dart';
import '../reporting/shift_amendment_feed_panel.dart';
import '../returns/return_actions.dart';
import '../sales/sale_history_panel.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../tenancy/tenant_staff_directory.dart';
import '../tenancy/tenant_staff_names.dart';
import '../ui/buttons.dart';
import '../ui/fields.dart';
import '../ui/pagination.dart';
import '../ui/routes.dart';
import '../ui/scaffold.dart';
import '../ui/sheet.dart';
import '../ui/skeleton.dart';
import '../ui/states.dart';
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
/// - **A day and a person, in one row** - the pair the sales report carries,
///   since 2026-09-22 and at the product owner's direction. It replaced a *My
///   shifts / Every cashier* toggle, a strip naming the days the page covered,
///   three tiles and a notice adding the page up, and a row of chips narrowing
///   it: five things between the title and the first shift, every one of them
///   about *which twenty happened to be read*. A day is a question the read
///   answers exactly, and each card still says whether it settled.
/// - **The prose itself moved into a sheet**, opened from the toolbar. It is
///   the same four claims; it is just no longer between the title and the data.
///   See [showShiftReconciliationSheet].
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
  });

  final TenantDataReader reader;

  /// Forwarded to the panel. See [TenantShiftHistoryPanel.salesReportRoute].
  final ShiftSalesReportRoute salesReportRoute;

  /// Passed through to the sales and returns routes. Recording a return stays
  /// unavailable while it is absent.
  final TenantReturnActions? returnActions;

  /// Forwarded to the panel. **Here so a test can drive the route rather than
  /// the panel inside it**, which matters now that two of this screen's controls
  /// live in the toolbar: a test that pumped the panel alone would be a test of
  /// a page that no longer exists on its own.
  final int pageSize;

  /// Forwarded to the panel. See [TenantShiftHistoryPanel.clock].
  final DateTime Function()? clock;

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
      salesReportRoute: salesReportRoute,
      returnActions: returnActions,
      pageSize: pageSize,
      clock: clock,
    ),
  );
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
    } catch (_) {
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
      loading: switch (scoped) {
        final session? => contents(context, session),
        // No session in scope at all is the guard's own `denied` case arriving
        // a frame early. Drawing nothing is what it draws.
        null => const SizedBox.shrink(),
      },
      denied: const Center(
        key: ValueKey('shift-history-denied'),
        child: EmptyState(
          title: 'Shift history is not available here',
          hint: 'This business does not open closed shifts to your role.',
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

/// Opens the read-only sales route under the same session scope, so its own
/// guard sees the exact controller this page was authorized against.
///
/// The toolbar's *My recent sales* is its one caller since a shift's card opens
/// the Sales report instead - see [TenantShiftHistoryPanel.salesReportRoute].
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
    return PagedListView(
      listKey: const ValueKey('shift-history'),
      padding: EdgeInsets.all(tokens.spacing.s20),
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
        _filters(tokens),
        // **Said once, and only where it is true.** Reporting never assumes a
        // currency, so a business that has published none gets bare figures
        // and one sentence saying why - rather than `KES` guessed onto a
        // screen people settle cash from.
        if (loaded != null && !loaded.currency.isKnown) ...<Widget>[
          SizedBox(height: tokens.spacing.s12),
          const Callout(
            key: ValueKey('shift-history-currency-unknown'),
            status: AppStatus.info,
            message: TenantReportingCurrency.unknownNotice,
          ),
        ],
        SizedBox(height: tokens.spacing.s20),
        if (failed)
          const ErrorState(
            key: ValueKey('shift-history-failure'),
            badgeLabel: 'Not read',
            statement: 'This page of shifts did not load',
            stillTrue:
                'Nothing has changed, and every shift is still recorded on the '
                'server.',
          )
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
          const EmptyState(
            key: ValueKey('shift-history-empty'),
            title: 'No closed shifts on this day',
            hint:
                'A shift appears here once it has been closed. Closing happens '
                'on the shift banner.',
            illustration: 'schedule.svg',
          )
        else
          ..._days(tokens, loaded),
      ],
    );
  }

  /// The day, and whose shifts - one row, as the sales report draws its own.
  ///
  /// **No caption over either control**, for the sales report's reason: a
  /// button showing a date behind a calendar glyph does not need *Date* over
  /// it, and a select reading *All staff* does not need *Staff*. Both keep the
  /// word as what a screen reader hears.
  Widget _filters(AppTokens tokens) {
    final date = Semantics(
      key: const ValueKey('shift-history-date-filter'),
      label: 'Shifts for $businessDate. Change the day.',
      button: true,
      excludeSemantics: true,
      child: AppButton(
        key: const ValueKey('shift-history-date-picker'),
        label: businessDate,
        icon: Icons.calendar_today_outlined,
        tier: AppButtonTier.secondary,
        expand: true,
        onPressed: onPickDate,
      ),
    );
    // A cashier reads their own shifts and nothing else, so there is nobody to
    // choose between and the day takes the row.
    if (!TenantShiftHistoryRepository.canReadEveryCashier(session)) {
      return date;
    }
    final offered = roster;
    final names = offered?.names ?? const <String, String>{};
    String label(String uid) =>
        tenantStaffLabel(uid, names: names, selfUid: session.uid);
    final chosen = staffId;
    final listed = offered?.uids ?? const <String>[];
    final staff = AppSelect<String>(
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: date),
        SizedBox(width: tokens.spacing.s12),
        Expanded(child: staff),
      ],
    );
  }

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
