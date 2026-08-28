import 'package:flutter/material.dart';

import '../ui/fields.dart';
import '../ui/pagination.dart';
import '../ui/record_list.dart';
import '../ui/scaffold.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_staff_names.dart';
import 'audit_log.dart';

/// Read-only route listing the events recorded for one business.
final class TenantAuditLogScreen extends StatelessWidget {
  const TenantAuditLogScreen({super.key, required this.reader, this.eventType});

  final TenantDataReader reader;

  /// When present, the trail opens narrowed to exactly this event.
  final TenantAuditEventType? eventType;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Activity log',
    contentWidth: AppContentWidth.records,
    body: TenantAuditLogPanel(reader: reader, eventType: eventType),
  );
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
    this.pageSize = 20,
  });

  final TenantDataReader reader;
  final TenantAuditEventType? eventType;
  final int pageSize;

  @override
  State<TenantAuditLogPanel> createState() => _TenantAuditLogPanelState();
}

final class _TenantAuditLogPanelState extends State<TenantAuditLogPanel> {
  List<String?> _cursors = <String?>[null];
  int _pageIndex = 0;
  TenantAuditEventType? _eventType;
  TenantStaffNameResolver? _staffNames;
  String? _staffNamesSessionKey;
  String? _loaderKey;
  TenantGuardedLoader<_AuditView>? _loader;
  TenantGuardedLoader<_AuditView>? _loaderCached;

  @override
  void initState() {
    super.initState();
    _eventType = widget.eventType;
  }

  @override
  void didUpdateWidget(covariant TenantAuditLogPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventType != widget.eventType) _selectEvent(widget.eventType);
  }

  static String _sessionKey(TenantSession session) =>
      '${session.uid}:${session.tenantId}:${session.epoch}';

  /// One resolver per session, so its cache can never label another session's
  /// rows. An unresolved name degrades to the authoritative UID.
  TenantStaffNameResolver _resolverFor(TenantSession session) {
    final key = _sessionKey(session);
    if (key != _staffNamesSessionKey || _staffNames == null) {
      _staffNamesSessionKey = key;
      _staffNames = TenantStaffNameResolver(
        session: session,
        reader: widget.reader,
      );
    }
    return _staffNames!;
  }

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
        names: await _resolverFor(session).resolve(<String>[
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
      key: ValueKey(guardKey),
      allowedRoles: TenantAuditLogRepository.allowedRoles,
      load: _loader!,
      loadCached: _loaderCached,
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
        onSelectEvent: _selectEvent,
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
    required this.onSelectEvent,
    required this.onNextPage,
    required this.onPreviousPage,
  });

  final _AuditView view;
  final String selfUid;
  final int pageIndex;
  final ValueChanged<TenantAuditEventType?> onSelectEvent;
  final VoidCallback onNextPage;
  final VoidCallback onPreviousPage;

  TenantAuditRecordPage get page => view.page;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return ListView(
      key: const ValueKey('audit-log'),
      padding: EdgeInsets.all(tokens.spacing.s20),
      children: [
        // §7's "Title appears once": the `AppScaffold` above says `Activity log`,
        // and this said the same thing at greater length directly under it.
        SizedBox(height: tokens.spacing.s4),
        Text(
          key: const ValueKey('audit-log-scope'),
          page.isEventScoped
              ? 'Every "${page.eventType!.label}" event recorded for this '
                    'business. Other events are not listed on this page.'
              : 'Every event this business recorded, including the ones the '
                    'platform caused. Individual sales are not events and are '
                    'not listed here.',
        ),
        SizedBox(height: tokens.spacing.s4),
        const Text(
          'The log is permanent and cannot be edited from this app. It is '
          'listed by record ID, which is not time order; each entry states when '
          'it was recorded.',
        ),
        SizedBox(height: tokens.spacing.s16),
        AppSelect<TenantAuditEventType?>(
          key: const ValueKey('audit-log-filter'),
          value: page.eventType,
          label: 'Show',
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
        SizedBox(height: tokens.spacing.s16),
        // §4.3's responsive contract: stacked cards on a phone, two-column cards
        // on a tablet, and a table on a desktop window - which this route never
        // had before step 6, and which is the form an activity log is most
        // legible in. Nothing about what an event says has changed; only what
        // shape it is said in.
        RecordList(
          identityLabel: 'Event',
          items: <RecordItem>[for (final record in page.items) _record(record)],
          empty: Text(
            key: const ValueKey('audit-log-empty'),
            page.isEventScoped
                ? 'No "${page.eventType!.label}" event has been recorded for '
                      'this business.'
                : 'No event has been recorded for this business.',
          ),
        ),
        SizedBox(height: tokens.spacing.s16),
        Pagination(
          pageNumber: pageIndex + 1,
          previousKey: const ValueKey('audit-log-previous'),
          nextKey: const ValueKey('audit-log-next'),
          onPrevious: pageIndex > 0 ? onPreviousPage : null,
          onNext: page.hasMore ? onNextPage : null,
        ),
      ],
    );
  }

  /// One event as §5.2's five rows.
  ///
  /// **Only a critical event carries a status, and an ordinary one carries
  /// none.** §2.1's five statuses each mean exactly one thing and "an event was
  /// recorded" is not among them, so a badge on every row would be a badge that
  /// says nothing - which is the drift §1 describes, arriving by a different
  /// door. It is also what this screen already meant: the warning triangle was
  /// drawn for `isCritical` and the ordinary glyph was a decoration beside every
  /// other row.
  ///
  /// The record ID is deliberately not shown. It was never on this card, and
  /// §2.2's `mono` role - the one for "strings a person compares character by
  /// character" - names no family until the `Inter` / Roboto question is
  /// answered.
  RecordItem _record(TenantAuditRecord record) => RecordItem(
    id: record.id,
    recordKey: ValueKey('audit-log-entry-${record.id}'),
    title: _eventLabel(record),
    titleKey: ValueKey('audit-log-event-${record.id}'),
    status: record.isCritical
        ? RecordStatus(
            status: AppStatus.problem,
            label: 'Critical',
            icon: Icons.warning_amber_outlined,
            semanticLabel: 'Critical event',
          )
        : null,
    attributes: <RecordAttribute>[
      if (record.fromStatus != null || record.toStatus != null)
        RecordAttribute(
          label: 'Change',
          value:
              '${record.fromStatus ?? 'unknown'} to '
              '${record.toStatus ?? 'unknown'}',
          valueKey: ValueKey('audit-log-status-${record.id}'),
        ),
      if (record.targetUid case final targetUid?)
        RecordAttribute(
          label: 'About',
          value: tenantStaffLabel(
            targetUid,
            names: view.names,
            selfUid: selfUid,
          ),
          valueKey: ValueKey('audit-log-target-${record.id}'),
          flex: 2,
        ),
    ],
    provenance: _recordedLabel(record, _actorLabel(record)),
    provenanceKey: ValueKey('audit-log-recorded-${record.id}'),
  );

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
