import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../ui/fields.dart';
import '../ui/scaffold.dart';
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
  TenantGuardedLoader<_AuditView> _loaderFor(String key) {
    if (key == _loaderKey && _loader != null) return _loader!;
    _loaderKey = key;
    final eventType = _eventType;
    final cursor = _cursors[_pageIndex];
    return _loader = (session) async {
      final repository = TenantAuditLogRepository(
        session: session,
        reader: widget.reader,
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
  }

  @override
  Widget build(BuildContext context) {
    final cursor = _cursors[_pageIndex];
    final guardKey = '${_eventType?.wireValue}:$_pageIndex:$cursor';
    return TenantRouteGuard<_AuditView>(
      key: ValueKey(guardKey),
      allowedRoles: TenantAuditLogRepository.allowedRoles,
      load: _loaderFor(guardKey),
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
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('audit-log'),
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Business activity log',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 4),
      Text(
        key: const ValueKey('audit-log-scope'),
        page.isEventScoped
            ? 'Every "${page.eventType!.label}" event recorded for this '
                  'business. Other events are not listed on this page.'
            : 'Every event this business recorded, including the ones the '
                  'platform caused. Individual sales are not events and are '
                  'not listed here.',
      ),
      const SizedBox(height: 4),
      const Text(
        'The log is permanent and cannot be edited from this app. It is '
        'listed by record ID, which is not time order; each entry states when '
        'it was recorded.',
      ),
      const SizedBox(height: 16),
      AppSelect<TenantAuditEventType?>(
        key: const ValueKey('audit-log-filter'),
        value: page.eventType,
        label: 'Show',
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
      const SizedBox(height: 16),
      if (page.items.isEmpty)
        Text(
          key: const ValueKey('audit-log-empty'),
          page.isEventScoped
              ? 'No "${page.eventType!.label}" event has been recorded for '
                    'this business.'
              : 'No event has been recorded for this business.',
        )
      else
        for (final record in page.items) _entry(context, record),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        children: [
          if (pageIndex > 0)
            AppButton(
              key: const ValueKey('audit-log-previous'),
              label: 'Previous page',
              onPressed: onPreviousPage,
            ),
          if (page.hasMore)
            AppButton(
              key: const ValueKey('audit-log-next'),
              label: 'Next page',
              tier: AppButtonTier.primary,
              onPressed: onNextPage,
            ),
        ],
      ),
    ],
  );

  Widget _entry(BuildContext context, TenantAuditRecord record) => Card(
    key: ValueKey('audit-log-entry-${record.id}'),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                record.isCritical
                    ? Icons.warning_amber_outlined
                    : Icons.history_outlined,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  key: ValueKey('audit-log-event-${record.id}'),
                  _eventLabel(record),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (record.fromStatus != null || record.toStatus != null)
            Text(
              key: ValueKey('audit-log-status-${record.id}'),
              '${record.fromStatus ?? 'unknown'} to '
              '${record.toStatus ?? 'unknown'}',
            ),
          if (record.targetUid case final targetUid?)
            Text(
              key: ValueKey('audit-log-target-${record.id}'),
              'About ${tenantStaffLabel(targetUid, names: view.names, selfUid: selfUid)}',
            ),
          Text(
            key: ValueKey('audit-log-recorded-${record.id}'),
            _recordedLabel(record, _actorLabel(record)),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
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
