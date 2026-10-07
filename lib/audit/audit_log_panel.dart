import 'package:flutter/material.dart';

import '../ui/fields.dart';
import '../ui/pagination.dart';
import '../ui/states.dart';
import '../ui/scaffold.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_staff_names.dart';
import '../reports/analysis/logs_analysis.dart';
import '../reports/analysis/logs_report.dart';
import '../reports/report_document.dart';
import '../reports/report_file.dart';
import '../reports/report_identity_source.dart';
import '../reports/report_people.dart';
import '../reports/report_period.dart';
import '../reports/report_run.dart';
import '../reports/ui/report_action.dart';
import '../inventory/product_image_cache.dart';
import 'audit_log.dart';

/// Read-only route listing the events recorded for one business.
final class TenantAuditLogScreen extends StatelessWidget {
  const TenantAuditLogScreen({
    super.key,
    required this.reader,
    this.eventType,
    this.clock,
    this.reportSaver,
    this.imageCache,
  });

  final TenantDataReader reader;

  /// Where a generated report goes. Null renders no toolbar control at all.
  final TenantReportSaver? reportSaver;

  /// Fetches the logo the report's branding band draws.
  final TenantImageCache? imageCache;

  /// When present, the trail opens narrowed to exactly this event.
  final TenantAuditEventType? eventType;

  /// Reads the instant the day filter opens on. Injected so a test can pin the
  /// day this page calls *today*.
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Logs',
    contentWidth: AppContentWidth.records,
    actions: <Widget>[
      TenantSessionReportAction(
        clock: clock ?? DateTime.now,
        runFor: (session) => _reportRun(session),
      ),
    ],
    body: TenantAuditLogPanel(
      reader: reader,
      eventType: eventType,
      clock: clock,
    ),
  );

  /// The trail over a period, which the screen's day filter cannot ask for.
  ///
  /// **The period is picked at the moment somebody asks for the file**, and is
  /// deliberately independent of the day showing on the page: this screen
  /// filters one page and a report reads a real span.
  TenantReportRun? _reportRun(TenantSession session) {
    final saver = reportSaver;
    if (saver == null) return null;
    // Owner and admin, exactly as `firestore.rules` already decided for the
    // screen. A report is not a way around that.
    if (!TenantAuditLogRepository.canReadInSession(session)) return null;

    final now = clock ?? DateTime.now;
    return TenantReportRun(
      kind: TenantReportKind.logs,
      support: TenantReportPeriodSupport.range,
      saver: saver,
      build: (period) async {
        final source = TenantLogsReportSource(
          repository: TenantAuditLogRepository(
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
        final analysis = TenantLogsAnalysis.from(
          period: period,
          records: read.records,
          previous: previous,
          truncated: read.truncated,
        );
        return describeLogsReport(
          identity: identity,
          analysis: analysis,
          // **Members only.** A platform actor has no staff record, and asking
          // the directory for one would spend a read to learn nothing.
          people: await readTenantReportPeople(
            session: session,
            reader: reader,
            uids: <String>[
              for (final actor in analysis.actors.take(TenantLogsAnalysis.listed))
                if (!actor.isPlatform) actor.actor,
              for (final record in analysis.critical.take(TenantLogsAnalysis.listed))
                if (record.actorType == null && record.actorUid != null)
                  record.actorUid!,
            ],
          ),
        );
      },
    );
  }
}

/// One guarded page of audit records with the staff names it needs.
final class _AuditView {
  const _AuditView({required this.page, required this.names});

  final TenantAuditRecordPage page;
  final Map<String, String> names;
}

/// Pages `tenants/{tenantId}/audit_logs` behind [TenantRouteGuard].
///
/// The guard owns authorization and stale-session rejection: a tenant switch
/// during an outstanding page discards it before it can update the UI. Nothing
/// on this surface can record, amend, or remove an event.
final class TenantAuditLogPanel extends StatefulWidget {
  const TenantAuditLogPanel({
    super.key,
    required this.reader,
    this.eventType,
    this.clock,
    this.pageSize = 20,
  });

  final TenantDataReader reader;
  final TenantAuditEventType? eventType;

  /// See [TenantAuditLogScreen.clock].
  final DateTime Function()? clock;

  final int pageSize;

  @override
  State<TenantAuditLogPanel> createState() => _TenantAuditLogPanelState();
}

final class _TenantAuditLogPanelState extends State<TenantAuditLogPanel> {
  List<String?> _cursors = <String?>[null];
  int _pageIndex = 0;
  TenantAuditEventType? _eventType;

  /// The UTC day the page is narrowed to, or null for every day on it.
  ///
  /// **UTC, because every row on this page states its instant in UTC.** A
  /// filter that cut the day on the phone's own clock would hide a row whose
  /// visible timestamp reads as the day that was asked for.
  ///
  /// **Not in the guard key, and this is the one thing to know about it.** The
  /// audit collection is paged by document ID - a digest, not a date - and the
  /// repository takes equality filters only, so there is no read that asks the
  /// server for one day. This narrows the page in hand. It is why the count of
  /// rows can fall to nothing on a day the business was plainly busy: the
  /// events of that day are on some other page. Filtering the trail itself
  /// needs a `createdAt` ordering on the query and the composite index that
  /// comes with it.
  DateTime? _day;

  final TenantStaffNameResolvers _staffNames = TenantStaffNameResolvers();
  String? _loaderKey;
  TenantGuardedLoader<_AuditView>? _loader;
  TenantGuardedLoader<_AuditView>? _loaderCached;

  @override
  void initState() {
    super.initState();
    _eventType = widget.eventType;
    // Opened on today, at the developer's direction on 2026-09-22.
    _day = _today;
  }

  /// Today, as a UTC date.
  DateTime get _today {
    final now = (widget.clock ?? DateTime.now)().toUtc();
    return DateTime.utc(now.year, now.month, now.day);
  }

  /// Narrowing to a day is a repaint, not a re-read: see [_day]. The cursor and
  /// the page number are deliberately left alone, so a person who has paged
  /// three pages in and then picks a day keeps the page they were reading.
  void _selectDay(DateTime? day) {
    if (day == _day) return;
    setState(() => _day = day);
  }

  /// Opens the calendar, and narrows to whatever day comes back.
  ///
  /// The range is the year behind today and today itself: an audit trail has no
  /// future, and a bound stops the picker offering a decade of days that cannot
  /// hold an event.
  Future<void> _pickDay() async {
    final today = _today;
    final picked = await showDatePicker(
      context: context,
      initialDate: _day ?? today,
      firstDate: DateTime.utc(today.year - 1, today.month, today.day),
      lastDate: today,
    );
    if (picked == null || !mounted) return;
    _selectDay(DateTime.utc(picked.year, picked.month, picked.day));
  }

  @override
  void didUpdateWidget(covariant TenantAuditLogPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventType != widget.eventType) _selectEvent(widget.eventType);
  }

  /// One resolver per session **and per pass**, so the cached pass resolves a
  /// name from this device rather than putting a network read in front of
  /// records it already holds. An unresolved name degrades to the UID.
  TenantStaffNameResolver _resolverFor(
    TenantSession session,
    TenantDocumentReader reader,
  ) => _staffNames.of(session: session, reader: reader);

  /// Narrowing the trail restarts it: a cursor is a document ID inside one
  /// exact query, so carrying it across a filter change would page from a
  /// position the new query never established.
  void _selectEvent(TenantAuditEventType? eventType) {
    if (eventType == _eventType) return;
    setState(() {
      _eventType = eventType;
      _cursors = <String?>[null];
      _pageIndex = 0;
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

  /// One loader per guard key, so a closure rebuilt every frame cannot restart
  /// the page on an unrelated `setState`.
  void _composeLoaders(String key) {
    if (key == _loaderKey && _loader != null) return;
    _loaderKey = key;
    final eventType = _eventType;
    final cursor = _cursors[_pageIndex];
    TenantGuardedLoader<_AuditView> readWith(TenantDataReader reader) =>
        (session) async {
          final repository = TenantAuditLogRepository(
            session: session,
            reader: reader,
          );
          final page = eventType == null
              ? await repository.loadEvents(
                  pageSize: widget.pageSize,
                  cursor: cursor,
                )
              : await repository.loadEventsOfType(
                  eventType: eventType,
                  pageSize: widget.pageSize,
                  cursor: cursor,
                );
          // Actors and targets are both staff of this business, so one bounded
          // resolver answers for both rather than a second lookup being added.
          return _AuditView(
            page: page,
            names: await _resolverFor(session, reader).resolve(<String>[
              for (final record in page.items) ...<String>[
                if (record.actorUid case final actorUid?) actorUid,
                if (record.targetUid case final targetUid?) targetUid,
              ],
            ]),
          );
        };
    _loader = readWith(widget.reader);
    final cache = widget.reader.cached;
    _loaderCached = cache == null ? null : readWith(cache);
  }

  @override
  Widget build(BuildContext context) {
    final cursor = _cursors[_pageIndex];
    final guardKey = '${_eventType?.wireValue}:$_pageIndex:$cursor';
    _composeLoaders(guardKey);
    return TenantRouteGuard<_AuditView>(
      allowedRoles: TenantAuditLogRepository.allowedRoles,
      load: _loader!,
      loadCached: _loaderCached,
      holdsNothing: (view) => view.page.items.isEmpty,
      denied: const Center(
        key: ValueKey('audit-log-denied'),
        child: Text('The activity log is available to owners and admins.'),
      ),
      failure: (context, error) => const Center(
        key: ValueKey('audit-log-failure'),
        child: Text('The recorded activity could not be loaded.'),
      ),
      builder: (context, session, view) => _AuditLogContents(
        view: view,
        selfUid: session.uid,
        pageIndex: _pageIndex,
        day: _day,
        today: _today,
        onSelectEvent: _selectEvent,
        onSelectDay: _selectDay,
        onPickDay: _pickDay,
        onNextPage: () => _nextPage(view.page.nextCursor),
        onPreviousPage: _previousPage,
      ),
    );
  }
}

final class _AuditLogContents extends StatelessWidget {
  const _AuditLogContents({
    required this.view,
    required this.selfUid,
    required this.pageIndex,
    required this.day,
    required this.today,
    required this.onSelectEvent,
    required this.onSelectDay,
    required this.onPickDay,
    required this.onNextPage,
    required this.onPreviousPage,
  });

  final _AuditView view;
  final String selfUid;
  final int pageIndex;

  /// The UTC day this page is narrowed to, or null for every day on it.
  final DateTime? day;

  /// Today as a UTC date, so the two named choices can be labelled.
  final DateTime today;

  final ValueChanged<TenantAuditEventType?> onSelectEvent;
  final ValueChanged<DateTime?> onSelectDay;
  final VoidCallback onPickDay;
  final VoidCallback onNextPage;
  final VoidCallback onPreviousPage;

  TenantAuditRecordPage get page => view.page;

  DateTime get _yesterday => today.subtract(const Duration(days: 1));

  /// The rows of [page] that fall on [day].
  ///
  /// **A record with no recorded instant is not on any day**, so it is held
  /// back whenever one is chosen rather than filed under an arbitrary one.
  /// *Any day* is where it can always be read.
  List<TenantAuditRecord> get _shown {
    final chosen = day;
    if (chosen == null) return page.items;
    final end = chosen.add(const Duration(days: 1));
    return <TenantAuditRecord>[
      for (final record in page.items)
        if (record.recordedAt case final at?)
          if (!at.toUtc().isBefore(chosen) && at.toUtc().isBefore(end)) record,
    ];
  }

  /// What the day filter is holding, as the value its items are keyed by.
  String get _dayValue {
    final chosen = day;
    if (chosen == null) return _anyDay;
    if (chosen == today) return _todayValue;
    if (chosen == _yesterday) return _yesterdayValue;
    return _exactDay;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return PagedListView(
      listKey: const ValueKey('audit-log'),
      padding: EdgeInsets.all(tokens.spacing.s20),
      pagination: Pagination(
        pageNumber: pageIndex + 1,
        previousKey: const ValueKey('audit-log-previous'),
        nextKey: const ValueKey('audit-log-next'),
        onPrevious: pageIndex > 0 ? onPreviousPage : null,
        onNext: page.hasMore ? onNextPage : null,
        endOfList: !page.hasMore,
      ),
      children: [
        // **The two paragraphs are gone, 2026-09-04.** They said the log holds
        // every event, that sales are not events, that it cannot be edited and
        // that it is ordered by record ID - four sentences a person read once
        // and then scrolled past for the rest of the product's life, standing
        // between the title and the thing they came to read. What survives of
        // them is the one fact that changes what a row means: which events are
        // on the page, and that is the control below rather than prose.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: AppSelect<TenantAuditEventType?>(
                key: const ValueKey('audit-log-filter'),
                value: page.eventType,
                label: 'Show',
                dense: true,
                leading: Icons.filter_list,
                items: <AppSelectItem<TenantAuditEventType?>>[
                  const AppSelectItem<TenantAuditEventType?>(
                    value: null,
                    label: 'All events',
                  ),
                  for (final type in TenantAuditEventType.values)
                    AppSelectItem<TenantAuditEventType?>(
                      value: type,
                      label: type.label,
                    ),
                ],
                onChanged: onSelectEvent,
              ),
            ),
            SizedBox(width: tokens.spacing.s12),
            Expanded(
              child: AppSelect<String>(
                key: const ValueKey('audit-log-day-filter'),
                value: _dayValue,
                label: 'Day',
                dense: true,
                leading: Icons.calendar_today_outlined,
                items: <AppSelectItem<String>>[
                  const AppSelectItem<String>(
                    key: ValueKey('audit-log-day-any'),
                    value: _anyDay,
                    label: 'Any day',
                  ),
                  const AppSelectItem<String>(
                    key: ValueKey('audit-log-day-today'),
                    value: _todayValue,
                    label: 'Today',
                  ),
                  const AppSelectItem<String>(
                    key: ValueKey('audit-log-day-yesterday'),
                    value: _yesterdayValue,
                    label: 'Yesterday',
                  ),
                  // The day already chosen from the calendar, so the control
                  // holds what it is showing - a select cannot sit on a value
                  // its own list does not carry.
                  if (_dayValue == _exactDay)
                    AppSelectItem<String>(
                      key: const ValueKey('audit-log-day-exact'),
                      value: _exactDay,
                      label: _dayLabel(day!),
                    ),
                  const AppSelectItem<String>(
                    key: ValueKey('audit-log-day-pick'),
                    value: _pickDay,
                    label: 'Another day...',
                  ),
                ],
                onChanged: (value) => switch (value) {
                  _anyDay => onSelectDay(null),
                  _todayValue => onSelectDay(today),
                  _yesterdayValue => onSelectDay(_yesterday),
                  _pickDay => onPickDay(),
                  // The day already chosen, chosen again.
                  _ => null,
                },
              ),
            ),
          ],
        ),
        SizedBox(height: tokens.spacing.s24),
        if (page.items.isEmpty)
          EmptyState(
            key: const ValueKey('audit-log-empty'),
            title: page.isEventScoped
                ? 'No "${page.eventType!.label}" event yet'
                : 'Nothing has been recorded yet',
            hint:
                'An event appears here when somebody changes the business, '
                'its staff, or its stock.',
            illustration: 'file-search.svg',
          )
        else if (_shown.isEmpty)
          // **Said as a fact about this page, not about the day.** The trail
          // is paged by record ID rather than by time, so the events of the
          // chosen day may be sitting on any page; claiming the business did
          // nothing that day would be a claim this screen cannot make.
          EmptyState(
            key: const ValueKey('audit-log-day-empty'),
            title: 'Nothing from ${_dayLabel(day!)} on this page',
            hint:
                'The trail is ordered by record, not by time, so that day may '
                'be further on. Turn the page, or choose any day.',
            illustration: 'file-search.svg',
          )
        else
          // **One rail, no day headings.** Grouping by day was the obvious
          // thing to reach for and it was wrong here: the query pages by
          // record ID, so a page arrives with 09-02 above 08-31 above 09-03,
          // and a screen that drew a heading per run would show four headings
          // for four events and imply an order the data does not carry. Each
          // row states its own instant instead, which is the honest unit.
          for (final record in _shown)
            _Event(
              record: record,
              actor: _actorLabel(record),
              target: record.targetUid == null
                  ? null
                  : tenantStaffLabel(
                      record.targetUid!,
                      names: view.names,
                      selfUid: selfUid,
                    ),
              last: identical(record, _shown.last),
            ),
        SizedBox(height: tokens.spacing.s16),
        // The one sentence of the two paragraphs worth keeping, at the foot
        // where a footnote goes: a page ordered by record ID is not a page
        // ordered by time, and every row carries its own instant because of it.
        Text(
          key: const ValueKey('audit-log-scope'),
          'Permanent, and listed by record rather than by time.',
          style: tokens.typography.caption.copyWith(
            color: tokens.colors.text.tertiary,
          ),
        ),
      ],
    );
  }

  /// The platform acts on a business without being a member of it, so those
  /// events are attributed to the platform rather than to a missing colleague.
  String _actorLabel(TenantAuditRecord record) {
    final actorUid = record.actorUid;
    if (actorUid == null) return 'the ${record.actorType!} operator';
    return tenantStaffLabel(actorUid, names: view.names, selfUid: selfUid);
  }
}

/// An unmodelled event is shown as itself: a server deploy recording a new one
/// is not evidence of anything wrong, and hiding the row would hide a real
/// event from the business's own trail.
/// The day filter's item values. Strings rather than an enum because one of
/// them is a door to the calendar rather than a day, and the chosen day itself
/// needs a value that does not change as the day does.
const String _anyDay = 'any';
const String _todayValue = 'today';
const String _yesterdayValue = 'yesterday';
const String _exactDay = 'exact';
const String _pickDay = 'pick';

/// One UTC date, in the order every instant on this page is written in.
String _dayLabel(DateTime day) {
  String pad(int part) => part.toString().padLeft(2, '0');
  return '${day.year}-${pad(day.month)}-${pad(day.day)}';
}

String _eventLabel(TenantAuditRecord record) =>
    record.type?.label ?? record.eventType;

String _recordedLabel(TenantAuditRecord record, String actorLabel) {
  final recordedAt = record.recordedAt;
  final when = recordedAt == null
      ? 'Recorded instant unavailable'
      : 'Recorded ${_instant(recordedAt)}';
  return '$when by $actorLabel';
}

String _instant(DateTime value) {
  final utc = value.toUtc();
  String pad(int part) => part.toString().padLeft(2, '0');
  return '${utc.year}-${pad(utc.month)}-${pad(utc.day)} '
      '${pad(utc.hour)}:${pad(utc.minute)} UTC';
}

/// One event, on the rail.
///
/// **A timeline rather than a record card.** Each event was a card with the
/// event as a title, a `CHANGE  pending to active` attribute pair under a
/// hairline, and a provenance line - three blocks and two rules for a row that
/// says one thing happened once. The rail carries the sequence, the glyph
/// carries the kind, and the sentence carries the rest.
final class _Event extends StatelessWidget {
  const _Event({
    required this.record,
    required this.actor,
    required this.target,
    required this.last,
  });

  final TenantAuditRecord record;

  /// Who caused it, already resolved to a name.
  final String actor;

  /// Who it was about, where it was about somebody.
  final String? target;

  /// Whether the rail stops here. The line joins an event to the next one, so
  /// the last of a day has nothing below it to join to.
  final bool last;

  /// The kind of thing that happened, as a glyph.
  ///
  /// **Grouped rather than one per event.** Twenty distinct glyphs is twenty
  /// things to learn; four families - the business, its people, its stock, and
  /// its books - is the shape of the trail itself, and an unmodelled event
  /// falls to the generic mark rather than being hidden.
  IconData get _glyph => switch (record.type) {
    TenantAuditEventType.tenantRequested ||
    TenantAuditEventType.tenantLifecycleChanged => Icons.storefront_outlined,
    TenantAuditEventType.ownerRecovered ||
    TenantAuditEventType.tenantOwnerUnavailable ||
    TenantAuditEventType.noActiveAdministrator ||
    TenantAuditEventType.staffInvited ||
    TenantAuditEventType.staffInvitationResent ||
    TenantAuditEventType.pendingStaffEmailReplaced ||
    TenantAuditEventType.tenantInvitationCancelled ||
    TenantAuditEventType.tenantInvitationAccepted ||
    TenantAuditEventType.visibleTenantInvitationAccepted ||
    TenantAuditEventType.staffUpdated ||
    TenantAuditEventType.staffStatusSet => Icons.people_outline,
    TenantAuditEventType.stockAdjusted ||
    TenantAuditEventType.returnVerifiedStockRestored =>
      Icons.inventory_2_outlined,
    TenantAuditEventType.tenantReconciliationRequested =>
      Icons.fact_check_outlined,
    null => Icons.circle_outlined,
  };

  /// What changed, in one line, or null where the event says it all.
  String? get _change {
    if (record.fromStatus == null && record.toStatus == null) return null;
    return '${record.fromStatus ?? 'unknown'} to ${record.toStatus ?? 'unknown'}';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    // **Only a critical event carries a status.** §2.1's five statuses each
    // mean exactly one thing and "an event was recorded" is not among them, so
    // a colour on every row would be a colour that says nothing.
    final role = record.isCritical ? tokens.colors.status.problem : null;
    final rail = record.isCritical
        ? role!.fg
        : tokens.colors.surface.borderStrong;
    return IntrinsicHeight(
      key: ValueKey('audit-log-entry-${record.id}'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Column(
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: role?.bg ?? tokens.colors.surface.raised,
                  border: Border.all(color: rail),
                  borderRadius: BorderRadius.circular(tokens.radius.pill),
                ),
                child: Padding(
                  padding: EdgeInsets.all(tokens.spacing.s8),
                  child: Icon(
                    _glyph,
                    size: StatusBadge.iconSize,
                    color: role?.fg ?? tokens.colors.text.secondary,
                  ),
                ),
              ),
              // The line that makes a list of rows a sequence. It stops at the
              // last event of a day, because there is nothing under it to join.
              if (!last)
                Expanded(
                  child: Center(
                    child: SizedBox(
                      width: _railWidth,
                      child: ColoredBox(
                        color: tokens.colors.surface.cardEdge,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(width: tokens.spacing.s12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: tokens.spacing.s20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          _eventLabel(record),
                          key: ValueKey('audit-log-event-${record.id}'),
                          // The event is the loudest thing on its row; what
                          // it was about is the line under it, not beside it.
                          style: tokens.typography.titleMedium.copyWith(
                            color: role?.fg ?? tokens.colors.text.primary,
                          ),
                        ),
                      ),
                      if (record.isCritical) ...<Widget>[
                        SizedBox(width: tokens.spacing.s8),
                        const StatusBadge(
                          status: AppStatus.problem,
                          label: 'Critical',
                          icon: Icons.warning_amber_outlined,
                          semanticLabel: 'Critical event',
                        ),
                      ],
                    ],
                  ),
                  if (_change case final change?) ...<Widget>[
                    SizedBox(height: tokens.spacing.s4),
                    Text(
                      change,
                      key: ValueKey('audit-log-status-${record.id}'),
                      style: tokens.typography.bodyMedium.copyWith(
                        color: tokens.colors.text.secondary,
                      ),
                    ),
                  ],
                  if (target case final about?) ...<Widget>[
                    SizedBox(height: tokens.spacing.s4),
                    Text(
                      about,
                      key: ValueKey('audit-log-target-${record.id}'),
                      style: tokens.typography.bodyMedium.copyWith(
                        color: tokens.colors.text.secondary,
                      ),
                    ),
                  ],
                  SizedBox(height: tokens.spacing.s4),
                  Text(
                    _recordedLabel(record, actor),
                    key: ValueKey('audit-log-recorded-${record.id}'),
                    style: tokens.typography.caption.copyWith(
                      color: tokens.colors.text.tertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The rail's own width.
  ///
  /// Named for the reason `EmptyState.markSize` is: `design.md` states no rule
  /// width, and 1 is the width every other hairline in this app is drawn at.
  static const double _railWidth = 1;
}
