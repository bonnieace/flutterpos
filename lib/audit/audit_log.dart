import 'package:cloud_firestore/cloud_firestore.dart';

import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_paths.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_types.dart';

/// Raised when a tenant audit record cannot be trusted or read.
final class TenantAuditLogException implements Exception {
  const TenantAuditLogException(this.code);

  final String code;

  @override
  String toString() => 'TenantAuditLogException($code)';
}

/// Every `eventType` a `tenants/{tenantId}/audit_logs` writer records today.
///
/// The Functions writers are the only authority on these wire values:
/// `tenants/onboarding.ts`, `lifecycle/tenantLifecycle.ts`,
/// `lifecycle/impactScan.ts`, `recovery/ownerRecovery.ts`, `staff/issuance.ts`,
/// `staff/acceptance.ts`, `staff/membership.ts`, `operations/stock.ts`,
/// `operations/returns.ts`, and `reconciliation/handlers.ts`. A value this
/// client does not model yet is deliberately **not** an error: see
/// [TenantAuditRecord.type].
enum TenantAuditEventType {
  tenantRequested('tenant_requested', 'Business requested'),
  tenantLifecycleChanged('tenant_lifecycle_changed', 'Business status changed'),
  ownerRecovered('owner_recovered', 'Owner recovered'),
  tenantOwnerUnavailable('tenant_owner_unavailable', 'Owner unavailable'),
  noActiveAdministrator('no_active_administrator', 'No active administrator'),
  staffInvited('staff_invited', 'Staff invited'),
  staffInvitationResent('staff_invitation_resent', 'Staff invitation resent'),
  pendingStaffEmailReplaced(
    'pending_staff_email_replaced',
    'Pending staff email replaced',
  ),
  tenantInvitationCancelled(
    'tenant_invitation_cancelled',
    'Invitation cancelled',
  ),
  tenantInvitationAccepted('tenant_invitation_accepted', 'Invitation accepted'),
  visibleTenantInvitationAccepted(
    'visible_tenant_invitation_accepted',
    'Listed invitation accepted',
  ),
  staffUpdated('staff_updated', 'Staff member updated'),
  staffStatusSet('staff_status_set', 'Staff status changed'),
  stockAdjusted('stock_adjusted', 'Stock corrected'),
  returnVerifiedStockRestored(
    'return_verified_stock_restored',
    'Return verified, stock restored',
  ),
  tenantReconciliationRequested(
    'tenant_reconciliation_requested',
    'Reconciliation requested',
  );

  const TenantAuditEventType(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static TenantAuditEventType? tryParse(String value) {
    for (final type in TenantAuditEventType.values) {
      if (type.wireValue == value) return type;
    }
    return null;
  }
}

/// Strict read model for `tenants/{tenantId}/audit_logs/{auditId}`.
///
/// This is the whole business's event trail. Server code is its only writer,
/// and the writers agree on one envelope - the business, the event type, who or
/// what caused it, and when - while each event carries its own detail beyond
/// that. Only the envelope is decoded here: modelling sixteen payload shapes to
/// render one line each would make the surface fail closed every time a writer
/// added a field, which is exactly the outcome an audit trail must avoid.
final class TenantAuditRecord {
  factory TenantAuditRecord.fromDocument({
    required String path,
    required Map<String, Object?> data,
  }) {
    final segments = path.split('/');
    if (segments.length != 4 ||
        segments[0] != 'tenants' ||
        segments[2] != TenantCollection.auditLogs.segment) {
      throw const TenantAuditLogException('invalid_audit_path');
    }
    final String tenantId;
    final String auditId;
    try {
      tenantId = validateTenantId(segments[1]);
      auditId = validateTenantDocumentId(segments[3], fieldName: 'auditId');
    } on ArgumentError {
      throw const TenantAuditLogException('invalid_audit_path');
    }
    // An audit record does not repeat its own ID - the writers address it by
    // the operation, request, or delivery ID it belongs to - so its path is the
    // one authority on which event it is. The business it names must still
    // agree with the path it was read from.
    if (data['tenantId'] != tenantId) {
      throw const TenantAuditLogException('audit_identity_mismatch');
    }

    final eventType = _requiredString(data, 'eventType');
    // Every real record is caused either by a named tenant actor or by the
    // platform acting on the business. A record that names neither cannot be
    // attributed to anybody, so it is refused rather than listed as evidence.
    final actorUid = _optionalDocumentId(data, 'actorUid');
    final actorType = _optionalString(data, 'actorType');
    if (actorUid == null && actorType == null) {
      throw const TenantAuditLogException('unattributed_audit_record');
    }

    return TenantAuditRecord._(
      id: auditId,
      tenantId: tenantId,
      eventType: eventType,
      type: TenantAuditEventType.tryParse(eventType),
      actorUid: actorUid,
      actorType: actorType,
      targetUid: _optionalDocumentId(data, 'targetUid'),
      requestId: _optionalString(data, 'requestId'),
      severity: _optionalString(data, 'severity'),
      fromStatus: _optionalString(data, 'fromStatus'),
      toStatus: _optionalString(data, 'toStatus'),
      recordedAt: _optionalInstant(data, 'createdAt'),
    );
  }

  const TenantAuditRecord._({
    required this.id,
    required this.tenantId,
    required this.eventType,
    required this.type,
    required this.actorUid,
    required this.actorType,
    required this.targetUid,
    required this.requestId,
    required this.severity,
    required this.fromStatus,
    required this.toStatus,
    required this.recordedAt,
  });

  final String id;
  final String tenantId;

  /// The raw event type, kept so an unmodelled one can be shown as itself.
  final String eventType;

  /// The modelled event, or null when this client does not know it yet.
  ///
  /// A server deploy that starts recording a new event is not evidence of
  /// anything wrong, and hiding a real event from the business's own trail
  /// would be far worse than naming it honestly.
  final TenantAuditEventType? type;

  /// The tenant member or platform operator who caused the event, when one is
  /// named. A platform-driven event records [actorType] instead.
  final String? actorUid;

  /// `platform_admin` or `platform` on the events the platform causes.
  final String? actorType;

  /// The staff member the event was about, on the events that name one.
  final String? targetUid;

  /// The idempotency key the actor's attempt carried, when it is recorded.
  final String? requestId;

  /// `critical` on the administrative alerts the impact scan records.
  final String? severity;

  /// The lifecycle statuses a `tenant_lifecycle_changed` record moved between.
  final String? fromStatus;
  final String? toStatus;

  /// The server instant the event was recorded.
  ///
  /// Optional for the same reason the per-product ledger and the stock
  /// correction feed treat it as optional: a row without a time still proves
  /// that the event happened, names who caused it, and says what it was, and
  /// failing a whole page of the business's trail closed over one missing
  /// convenience field would deny an owner the evidence entirely.
  final DateTime? recordedAt;

  bool get isCritical => severity == 'critical';

  /// Whether the platform, rather than a member of this business, caused it.
  bool get isPlatformEvent => actorUid == null;
}

/// One bounded page of a business's audit trail.
final class TenantAuditRecordPage {
  TenantAuditRecordPage({
    required List<TenantAuditRecord> items,
    required this.nextCursor,
    required this.hasMore,
    required this.eventType,
  }) : items = List<TenantAuditRecord>.unmodifiable(items);

  final List<TenantAuditRecord> items;
  final String? nextCursor;
  final bool hasMore;

  /// The exact event this page was narrowed to, or null for the whole trail. A
  /// surface states which one it is showing rather than implying that a
  /// filtered page is everything the business recorded.
  final TenantAuditEventType? eventType;

  bool get isEventScoped => eventType != null;
}

/// Guarded read boundary over one tenant's `audit_logs` collection.
///
/// Every path is derived from the session's [TenantPaths] and the exact-child,
/// uniqueness, page-size, and ordering proofs of [TenantReadRepository] still
/// apply. No caller can supply a collection path, an ordering, or a raw filter.
final class TenantAuditLogRepository extends TenantReadRepository {
  TenantAuditLogRepository({
    required super.session,
    required TenantDataReader reader,
  }) : _collectionReader = reader,
       super(reader: reader);

  /// Owner and admin only, exactly as `firestore.rules` already decided.
  ///
  /// This is deliberately narrower than the owner/admin/manager stock surfaces:
  /// those show the stock corrections a manager both records and answers for,
  /// while this is the whole business's event trail - who was invited,
  /// deactivated, or recovered, and every lifecycle change the platform made.
  static const List<TenantRole> allowedRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
  ];

  final TenantCollectionReader _collectionReader;

  static bool canReadInSession(TenantSession session) =>
      session.canAccess(allowedRoles: allowedRoles);

  /// Pages every event recorded for this business.
  Future<TenantAuditRecordPage> loadEvents({
    int pageSize = 20,
    String? cursor,
  }) => _load(pageSize: pageSize, cursor: cursor, eventType: null);

  /// Pages the events of exactly one modelled type.
  ///
  /// The filter is a typed enum rather than a caller-supplied string, so no
  /// caller can name an arbitrary field value, and it becomes one exact
  /// `eventType ==` equality on the same ascending key order - served by
  /// Firestore's automatic single-field index without a composite index. An
  /// event type this client does not model cannot be filtered for; the
  /// unfiltered page still lists it.
  Future<TenantAuditRecordPage> loadEventsOfType({
    required TenantAuditEventType eventType,
    int pageSize = 20,
    String? cursor,
  }) => _load(pageSize: pageSize, cursor: cursor, eventType: eventType);

  /// Reads one bounded page, optionally narrowed to one event type.
  ///
  /// The page is ordered by ascending document ID and is deliberately **not**
  /// presented as chronological: an audit ID is the operation, request, or
  /// delivery ID the event belongs to - a digest for most writers and the
  /// tenant ID itself for `tenant_requested` - so document order carries no
  /// time information at all. Each record states its own recorded instant
  /// instead. Ascending order also keeps both pages servable by Firestore's
  /// automatic index, since a descending key scan would need a filter and a
  /// composite index while buying nothing but a different arbitrary order.
  Future<TenantAuditRecordPage> _load({
    required int pageSize,
    required String? cursor,
    required TenantAuditEventType? eventType,
  }) async {
    if (!canReadInSession(session)) {
      throw const TenantAuditLogException('audit_logs_forbidden');
    }
    final page = await readCollectionPage(
      TenantCollection.auditLogs,
      collectionReader: _collectionReader,
      pageSize: pageSize,
      cursor: cursor,
      equalityFilters: eventType == null
          ? const <String, Object?>{}
          : <String, Object?>{'eventType': eventType.wireValue},
    );
    final items = <TenantAuditRecord>[];
    for (final snapshot in page.items) {
      final record = TenantAuditRecord.fromDocument(
        path: snapshot.path,
        data: snapshot.data,
      );
      if (record.tenantId != session.tenantId) {
        throw const TenantAuditLogException('cross_tenant_audit_record');
      }
      // A page narrowed to one event that answers with another one is a broken
      // boundary, not a row to quietly skip past.
      if (eventType != null && record.eventType != eventType.wireValue) {
        throw const TenantAuditLogException('foreign_audit_event_type');
      }
      items.add(record);
    }
    return TenantAuditRecordPage(
      items: items,
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
      eventType: eventType,
    );
  }

  /// Every event recorded between two instants, oldest first.
  ///
  /// **This is the read the logs report was waiting for.** The trail is keyed
  /// by the operation, request or delivery ID an event belongs to - a digest
  /// for most writers - so document order carries no time information at all,
  /// and the screen's own day filter is honest about being a sieve over one
  /// page. Ordering by `createdAt` is what makes a period answerable, and it
  /// is the same move [TenantCollectionOrder.createdAt] already made for the
  /// stock ledger.
  ///
  /// **A record with no `createdAt` cannot appear here, and the report says
  /// so.** [TenantAuditRecord.recordedAt] is optional because a row without a
  /// time still proves an event happened; but an ordering cannot include a
  /// document that has no value to order by. Firestore leaves those out of the
  /// index entirely, so they are missing rather than misplaced - which is the
  /// honest outcome, provided the document admits it.
  Future<
    ({List<TenantAuditRecord> items, TenantInstantRangePosition? next})
  >
  loadRecordedRange({
    required DateTime startAt,
    required DateTime endAt,
    int pageSize = 50,
    TenantInstantRangePosition? startAfter,
  }) async {
    if (!canReadInSession(session)) {
      throw const TenantAuditLogException('audit_logs_forbidden');
    }
    if (pageSize < 1 || pageSize > 50) {
      throw RangeError.range(pageSize, 1, 50, 'pageSize');
    }
    if (startAt.isAfter(endAt)) {
      throw const TenantAuditLogException('invalid_audit_range');
    }
    final reader = _collectionReader is TenantReportRangeReader
        ? _collectionReader as TenantReportRangeReader
        : null;
    if (reader == null) {
      throw StateError('This reader cannot read an audit period.');
    }

    final requested = pageSize + 1;
    final snapshots = await reader.queryTenantInstantRange(
      TenantInstantRangeQuery.scoped(
        collectionPath: paths.collectionPath(TenantCollection.auditLogs),
        limit: requested,
        startAt: startAt.toUtc(),
        endAt: endAt.toUtc(),
        startAfter: startAfter,
      ),
    );
    if (snapshots.length > requested) {
      throw const TenantScopeViolation(
        'The audit period returned more documents than requested.',
      );
    }

    final items = <TenantAuditRecord>[];
    final seen = <String>{};
    for (final snapshot in snapshots) {
      final record = TenantAuditRecord.fromDocument(
        path: snapshot.path,
        data: snapshot.data,
      );
      if (!seen.add(record.id)) {
        throw const TenantScopeViolation(
          'The audit period returned a duplicate document.',
        );
      }
      if (record.tenantId != session.tenantId) {
        throw const TenantAuditLogException('cross_tenant_audit_record');
      }
      // Ordered by the instant, so every row must carry one. A document the
      // transport returned without it was never in the index this asked of,
      // and putting it in a period it cannot claim would be an invention.
      final at = record.recordedAt;
      if (at == null ||
          at.isBefore(startAt.toUtc()) ||
          at.isAfter(endAt.toUtc())) {
        throw const TenantAuditLogException('foreign_audit_instant');
      }
      items.add(record);
    }

    final hasMore = items.length > pageSize;
    final visible = hasMore
        ? items.take(pageSize).toList(growable: false)
        : items;
    return (
      items: visible,
      next: hasMore
          ? TenantInstantRangePosition(
              at: visible.last.recordedAt!,
              documentId: visible.last.id,
            )
          : null,
    );
  }
}

String _requiredString(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! String || value.isEmpty || value != value.trim()) {
    throw const TenantAuditLogException('invalid_audit_document');
  }
  if (value.length > 200) {
    throw const TenantAuditLogException('invalid_audit_document');
  }
  for (final codeUnit in value.codeUnits) {
    if (codeUnit < 0x20 || codeUnit == 0x7f) {
      throw const TenantAuditLogException('invalid_audit_document');
    }
  }
  return value;
}

/// Absent is allowed; present but malformed is not. A writer that recorded a
/// field at all recorded a real value, so a broken one is a broken record.
String? _optionalString(Map<String, Object?> data, String field) =>
    data[field] == null ? null : _requiredString(data, field);

String? _optionalDocumentId(Map<String, Object?> data, String field) {
  final value = _optionalString(data, field);
  if (value == null) return null;
  try {
    return validateTenantDocumentId(value, fieldName: field);
  } on ArgumentError {
    throw const TenantAuditLogException('invalid_audit_document');
  }
}

DateTime? _optionalInstant(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value == null) return null;
  if (value is Timestamp) return value.toDate().toUtc();
  if (value is DateTime) return value.toUtc();
  throw const TenantAuditLogException('invalid_audit_document');
}
