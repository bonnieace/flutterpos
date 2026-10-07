import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../observability/app_telemetry.dart';
import 'platform_tenant_console.dart';
import 'tenant_id.dart';
import 'tenant_types.dart';

/// What the platform console reads, described rather than executed.
///
/// **A query is a value here, and that is the whole testing seam.** Every
/// screen of the console asks its questions through [PlatformConsoleDataSource]
/// as one of these, so the Firestore implementation is a translation and the
/// harness's fake answers the same questions from seeded documents. Nothing in
/// the console builds a Firestore query itself.
enum PlatformQueryOp { equals, isIn, greaterThan, greaterOrEqual, lessThan }

final class PlatformWhere {
  const PlatformWhere(this.field, this.op, this.value);

  final String field;
  final PlatformQueryOp op;
  final Object? value;
}

final class PlatformQuery {
  const PlatformQuery(
    this.collection, {
    this.collectionGroup = false,
    this.where = const <PlatformWhere>[],
    this.orderBy,
    this.descending = true,
    this.limit,
    this.startAfter,
  });

  /// A collection path (`tenants`, `tenants/t1/staff`) or, with
  /// [collectionGroup], a collection id.
  final String collection;
  final bool collectionGroup;
  final List<PlatformWhere> where;

  /// Ordered by this field (in [descending] order) and then by document id in
  /// the same direction.
  final String? orderBy;
  final bool descending;
  final int? limit;

  /// The last row of the previous page: its [orderBy] value and its id.
  final PlatformCursor? startAfter;
}

final class PlatformCursor {
  const PlatformCursor(this.value, this.id);

  final Object? value;
  final String id;
}

/// One document the console read: its path, its id, its fields.
final class PlatformRecord {
  const PlatformRecord({required this.path, required this.data});

  final String path;
  final Map<String, Object?> data;

  String get id => path.substring(path.lastIndexOf('/') + 1);

  /// The parent document's id for a subcollection record
  /// (`tenants/{t}/staff/{uid}` gives `t`).
  String? get parentId {
    final parts = path.split('/');
    return parts.length >= 4 ? parts[parts.length - 3] : null;
  }
}

abstract interface class PlatformConsoleDataSource {
  Future<List<PlatformRecord>> query(PlatformQuery query);

  Future<int> count(PlatformQuery query);

  Future<PlatformRecord?> get(String path);
}

final class FirebasePlatformConsoleDataSource
    implements PlatformConsoleDataSource {
  FirebasePlatformConsoleDataSource({FirebaseFirestore? firestore})
    : _given = firestore;

  /// Resolved on first read, as the suppression callable is.
  final FirebaseFirestore? _given;

  FirebaseFirestore get _firestore => _given ?? FirebaseFirestore.instance;

  Query<Map<String, dynamic>> _build(
    PlatformQuery spec, {
    bool ordered = true,
  }) {
    Query<Map<String, dynamic>> query = spec.collectionGroup
        ? _firestore.collectionGroup(spec.collection)
        : _firestore.collection(spec.collection);
    for (final clause in spec.where) {
      final value = _wire(clause.value);
      query = switch (clause.op) {
        PlatformQueryOp.equals => query.where(clause.field, isEqualTo: value),
        PlatformQueryOp.isIn => query.where(
          clause.field,
          whereIn: value! as List<Object?>,
        ),
        PlatformQueryOp.greaterThan => query.where(
          clause.field,
          isGreaterThan: value,
        ),
        PlatformQueryOp.greaterOrEqual => query.where(
          clause.field,
          isGreaterThanOrEqualTo: value,
        ),
        PlatformQueryOp.lessThan => query.where(
          clause.field,
          isLessThan: value,
        ),
      };
    }
    if (ordered && spec.orderBy != null) {
      // The tie-break runs the same way as the sort, so a sort on one field
      // is served by Firestore's automatic index and needs no composite.
      query = query
          .orderBy(spec.orderBy!, descending: spec.descending)
          .orderBy(FieldPath.documentId, descending: spec.descending);
      if (spec.startAfter case final cursor?) {
        query = query.startAfter(<Object?>[_wire(cursor.value), cursor.id]);
      }
    }
    if (ordered && spec.limit != null) query = query.limit(spec.limit!);
    return query;
  }

  static Object? _wire(Object? value) => switch (value) {
    final DateTime date => Timestamp.fromDate(date.toUtc()),
    final List<Object?> list => list.map(_wire).toList(),
    _ => value,
  };

  @override
  Future<List<PlatformRecord>> query(PlatformQuery query) async {
    final snapshot = await _build(query).get();
    return snapshot.docs
        .map(
          (document) => PlatformRecord(
            path: document.reference.path,
            data: document.data(),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<int> count(PlatformQuery query) async {
    final snapshot = await _build(query, ordered: false).count().get();
    return snapshot.count ?? 0;
  }

  @override
  Future<PlatformRecord?> get(String path) async {
    final snapshot = await _firestore.doc(path).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    return PlatformRecord(path: snapshot.reference.path, data: data);
  }
}

// ---------------------------------------------------------------------------
// Field readers. A malformed record is skipped by the reader that meets it,
// never shown half-read: a console row that guesses is worse than a missing one.
// ---------------------------------------------------------------------------

DateTime? platformTime(Object? value) => switch (value) {
  final Timestamp stamp => stamp.toDate(),
  final DateTime date => date,
  _ => null,
};

String? platformText(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty || platformTextHasControl(trimmed)) return null;
  return trimmed;
}

int? platformInt(Object? value) => value is int ? value : null;

bool _isTenantId(String value) {
  try {
    validateTenantId(value);
    return true;
  } on ArgumentError {
    return false;
  }
}

// ---------------------------------------------------------------------------
// People and names.
// ---------------------------------------------------------------------------

enum PlatformPersonStanding { active, disabled }

/// One `users/{uid}` root, as the console shows it.
final class PlatformPerson {
  const PlatformPerson({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.phone,
    required this.isPlatformAdmin,
    required this.standing,
    required this.signedUp,
    required this.createdAt,
    required this.membershipCount,
    required this.ownedTenantCount,
  });

  static PlatformPerson? fromRecord(PlatformRecord record) {
    final email = platformText(record.data['email']);
    final accountType = record.data['accountType'];
    final status = record.data['globalStatus'];
    if (email == null ||
        (accountType != 'tenant_user' && accountType != 'platform_admin') ||
        (status != 'active' && status != 'disabled')) {
      return null;
    }
    return PlatformPerson(
      uid: record.id,
      email: email,
      displayName: platformText(record.data['displayName']),
      phone: platformText(record.data['phone']),
      isPlatformAdmin: accountType == 'platform_admin',
      standing: status == 'active'
          ? PlatformPersonStanding.active
          : PlatformPersonStanding.disabled,
      signedUp: record.data['identityOrigin'] != 'staff_invitation',
      createdAt: platformTime(record.data['createdAt']),
      membershipCount: platformInt(record.data['membershipCount']) ?? 0,
      ownedTenantCount: platformInt(record.data['ownedTenantCount']) ?? 0,
    );
  }

  final String uid;
  final String email;
  final String? displayName;
  final String? phone;
  final bool isPlatformAdmin;
  final PlatformPersonStanding standing;

  /// Signed themselves up, rather than arriving by an invitation.
  final bool signedUp;
  final DateTime? createdAt;
  final int membershipCount;
  final int ownedTenantCount;

  String get name => displayName ?? email;
}

/// Resolves user ids to names once per screen, so a list of twenty audit
/// lines by the same three people reads three roots, not twenty.
final class PlatformNameBook {
  PlatformNameBook(this._source);

  final PlatformConsoleDataSource _source;
  final Map<String, Future<PlatformPerson?>> _people = {};

  Future<PlatformPerson?> person(String uid) =>
      _people.putIfAbsent(uid, () async {
        try {
          validateTenantDocumentId(uid, fieldName: 'uid');
        } on ArgumentError {
          return null;
        }
        final record = await _source.get('users/$uid');
        return record == null ? null : PlatformPerson.fromRecord(record);
      });

  Future<String?> name(String? uid) async =>
      uid == null ? null : (await person(uid))?.name;

  Future<Map<String, String>> names(Iterable<String?> uids) async {
    final unique = uids.whereType<String>().toSet();
    final resolved = await Future.wait(
      unique.map((uid) async => MapEntry(uid, await name(uid))),
    );
    return <String, String>{
      for (final entry in resolved)
        if (entry.value != null) entry.key: entry.value!,
    };
  }
}

// ---------------------------------------------------------------------------
// Businesses.
// ---------------------------------------------------------------------------

final class PlatformBusiness {
  const PlatformBusiness({
    required this.tenantId,
    required this.name,
    required this.slug,
    required this.status,
    required this.ownerUid,
    required this.createdAt,
    required this.updatedAt,
  });

  static PlatformBusiness? fromRecord(PlatformRecord record) {
    final name = platformText(record.data['name']);
    final slug = platformText(record.data['slug']);
    final ownerUid = platformText(record.data['ownerUid']);
    late final TenantStatus status;
    try {
      status = TenantStatus.fromWire(record.data['status']);
    } on FormatException {
      return null;
    }
    if (!_isTenantId(record.id) ||
        name == null ||
        slug == null ||
        ownerUid == null) {
      return null;
    }
    return PlatformBusiness(
      tenantId: record.id,
      name: name,
      slug: slug,
      status: status,
      ownerUid: ownerUid,
      createdAt: platformTime(record.data['createdAt']),
      updatedAt: platformTime(record.data['updatedAt']),
    );
  }

  final String tenantId;
  final String name;
  final String slug;
  final TenantStatus status;
  final String ownerUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

/// A row of the businesses list: the business, its owner, how many people
/// work there, the open alert on it, and the change that put it where it is.
final class PlatformBusinessRow {
  const PlatformBusinessRow({
    required this.business,
    required this.owner,
    required this.staffCount,
    required this.alert,
    required this.lastChange,
    required this.lastChangeActor,
  });

  final PlatformBusiness business;
  final PlatformPerson? owner;
  final int staffCount;
  final PlatformAlert? alert;

  /// The latest lifecycle event, read for a suspended or archived business
  /// only: its reason is the note the row carries.
  final PlatformLifecycleEvent? lastChange;
  final String? lastChangeActor;
}

enum PlatformBusinessFilter { all, trading, suspended, archived, attention }

extension on PlatformBusinessFilter {
  TenantStatus? get status => switch (this) {
    PlatformBusinessFilter.trading => TenantStatus.active,
    PlatformBusinessFilter.suspended => TenantStatus.suspended,
    PlatformBusinessFilter.archived => TenantStatus.archived,
    _ => null,
  };
}

final class PlatformPage<T> {
  const PlatformPage({
    required this.items,
    required this.next,
    required this.firstIndex,
  });

  final List<T> items;

  /// Where the following page starts, or null at the end.
  final PlatformCursor? next;

  /// The 0-based index of [items]' first row in the whole list.
  final int firstIndex;
}

/// Turns free text into the slug prefix it would be: lower case, spaces as
/// hyphens. Search is by slug because a slug is the one lower-cased name a
/// business record carries.
String platformSlugPrefix(String raw) => raw
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+'), '');

const String _prefixEnd = '';

final class PlatformBusinessDirectory {
  PlatformBusinessDirectory(this._source, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final PlatformConsoleDataSource _source;
  final DateTime Function() _clock;

  /// Each count on its own, as the people directory's are.
  Future<Map<PlatformBusinessFilter, int?>> counts() async {
    final alerts = await platformOrNull(
      PlatformAlertsReader(_source, clock: _clock).recent(),
      'platform.business_alerts_read',
    );
    final results = await Future.wait(<Future<int?>>[
      platformOrNull(
        _source.count(const PlatformQuery('tenants')),
        'platform.business_count_read',
      ),
      for (final status in TenantStatus.values)
        platformOrNull(
          _source.count(
            PlatformQuery(
              'tenants',
              where: <PlatformWhere>[
                PlatformWhere(
                  'status',
                  PlatformQueryOp.equals,
                  status.wireValue,
                ),
              ],
            ),
          ),
          'platform.business_count_read',
        ),
    ]);
    return <PlatformBusinessFilter, int?>{
      PlatformBusinessFilter.all: results[0],
      PlatformBusinessFilter.trading: results[1],
      PlatformBusinessFilter.suspended: results[2],
      PlatformBusinessFilter.archived: results[3],
      PlatformBusinessFilter.attention: alerts
          ?.map((alert) => alert.tenantId)
          .whereType<String>()
          .toSet()
          .length,
    };
  }

  Future<PlatformPage<PlatformBusinessRow>> page({
    required PlatformBusinessFilter filter,
    String search = '',
    PlatformCursor? after,
    int firstIndex = 0,
    int pageSize = 8,
  }) async {
    final alerts =
        await platformOrNull(
          PlatformAlertsReader(_source, clock: _clock).recent(),
          'platform.business_alerts_read',
        ) ??
        const <PlatformAlert>[];
    final alertByTenant = <String, PlatformAlert>{};
    for (final alert in alerts) {
      if (alert.tenantId case final tenantId?) {
        alertByTenant.putIfAbsent(tenantId, () => alert);
      }
    }
    final prefix = platformSlugPrefix(search);
    List<PlatformRecord> records;
    PlatformCursor? next;
    if (filter == PlatformBusinessFilter.attention) {
      final ids = alertByTenant.keys.toList();
      final fetched = await Future.wait(
        ids.map((id) => _source.get('tenants/$id')),
      );
      records = fetched.whereType<PlatformRecord>().toList();
      next = null;
    } else {
      final status = filter.status;
      final query = prefix.isNotEmpty
          ? PlatformQuery(
              'tenants',
              where: <PlatformWhere>[
                PlatformWhere('slug', PlatformQueryOp.greaterOrEqual, prefix),
                PlatformWhere(
                  'slug',
                  PlatformQueryOp.lessThan,
                  '$prefix$_prefixEnd',
                ),
                if (status != null)
                  PlatformWhere(
                    'status',
                    PlatformQueryOp.equals,
                    status.wireValue,
                  ),
              ],
              orderBy: 'slug',
              descending: false,
              limit: pageSize + 1,
              startAfter: after,
            )
          : PlatformQuery(
              'tenants',
              where: <PlatformWhere>[
                if (status != null)
                  PlatformWhere(
                    'status',
                    PlatformQueryOp.equals,
                    status.wireValue,
                  ),
              ],
              orderBy: 'createdAt',
              limit: pageSize + 1,
              startAfter: after,
            );
      records = await _source.query(query);
      if (records.length > pageSize) {
        records = records.take(pageSize).toList();
        final last = records.last;
        next = PlatformCursor(
          prefix.isNotEmpty ? last.data['slug'] : last.data['createdAt'],
          last.id,
        );
      }
    }
    final businesses = records
        .map(PlatformBusiness.fromRecord)
        .whereType<PlatformBusiness>()
        .toList();
    final names = PlatformNameBook(_source);
    final rows = await Future.wait(
      businesses.map(
        (business) => _row(business, names, alertByTenant[business.tenantId]),
      ),
    );
    return PlatformPage(items: rows, next: next, firstIndex: firstIndex);
  }

  Future<PlatformBusinessRow> _row(
    PlatformBusiness business,
    PlatformNameBook names,
    PlatformAlert? alert,
  ) async {
    final owner = names.person(business.ownerUid);
    final staff = _source.count(
      PlatformQuery('tenants/${business.tenantId}/staff'),
    );
    PlatformLifecycleEvent? change;
    String? actor;
    if (business.status != TenantStatus.active) {
      final history = await PlatformBusinessReader.history(
        _source,
        business.tenantId,
        limit: 1,
      );
      change = history.isEmpty ? null : history.first;
      actor = await names.name(change?.actorUid);
    }
    return PlatformBusinessRow(
      business: business,
      owner: await owner,
      staffCount: await staff,
      alert: alert,
      lastChange: change,
      lastChangeActor: actor,
    );
  }
}

enum PlatformLifecycleKind { created, changed, ownerRecovered, unknown }

final class PlatformLifecycleEvent {
  const PlatformLifecycleEvent({
    required this.id,
    required this.kind,
    required this.from,
    required this.to,
    required this.actorUid,
    required this.reason,
    required this.createdAt,
  });

  static PlatformLifecycleEvent? fromRecord(PlatformRecord record) {
    final createdAt = platformTime(record.data['createdAt']);
    if (createdAt == null) return null;
    final kind = switch (record.data['eventType']) {
      'tenant_requested' => PlatformLifecycleKind.created,
      'tenant_lifecycle_changed' => PlatformLifecycleKind.changed,
      'owner_recovered' => PlatformLifecycleKind.ownerRecovered,
      _ => PlatformLifecycleKind.unknown,
    };
    TenantStatus? status(Object? value) {
      try {
        return value == null ? null : TenantStatus.fromWire(value);
      } on FormatException {
        return null;
      }
    }

    return PlatformLifecycleEvent(
      id: record.id,
      kind: kind,
      from: status(record.data['fromStatus']),
      to: status(record.data['toStatus']),
      actorUid: platformText(record.data['actorUid']),
      reason: platformText(record.data['reason']),
      createdAt: createdAt,
    );
  }

  final String id;
  final PlatformLifecycleKind kind;
  final TenantStatus? from;
  final TenantStatus? to;
  final String? actorUid;
  final String? reason;
  final DateTime createdAt;
}

enum PlatformStaffStanding {
  active,
  invited,
  linkExpired,
  emailRejected,
  deactivated,
}

final class PlatformStaffMember {
  const PlatformStaffMember({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    required this.standing,
  });

  static PlatformStaffMember? fromRecord(PlatformRecord record, DateTime now) {
    final name = platformText(record.data['name']);
    final email = platformText(record.data['email']);
    late final TenantRole role;
    late final MembershipStatus status;
    try {
      role = TenantRole.fromWire(record.data['role']);
      status = MembershipStatus.fromWire(record.data['status']);
    } on FormatException {
      return null;
    }
    if (email == null) return null;
    final expires = platformTime(record.data['invitationExpiresAt']);
    final standing = switch (status) {
      MembershipStatus.active => PlatformStaffStanding.active,
      MembershipStatus.inactive => PlatformStaffStanding.deactivated,
      MembershipStatus.pending
          when record.data['invitationDeliveryState'] == 'failed' =>
        PlatformStaffStanding.emailRejected,
      MembershipStatus.pending when expires != null && expires.isBefore(now) =>
        PlatformStaffStanding.linkExpired,
      MembershipStatus.pending => PlatformStaffStanding.invited,
    };
    return PlatformStaffMember(
      uid: record.id,
      name: name ?? email,
      email: email,
      phone: platformText(record.data['phone']),
      role: role,
      standing: standing,
    );
  }

  final String uid;
  final String name;
  final String email;
  final String? phone;
  final TenantRole role;
  final PlatformStaffStanding standing;

  bool get needsAttention =>
      standing == PlatformStaffStanding.linkExpired ||
      standing == PlatformStaffStanding.emailRejected;
}

final class PlatformStaffCounts {
  const PlatformStaffCounts({
    required this.total,
    required this.active,
    required this.invited,
    required this.needAttention,
    required this.deactivated,
  });

  final int total;
  final int active;
  final int invited;
  final int needAttention;
  final int deactivated;
}

/// One line of a business's own audit log, as far as the record lets it be
/// said. **Product names are not on most of these records** and products are
/// closed to a platform administrator, so a stock line says what moved, not
/// what it moved on.
final class PlatformAuditEntry {
  const PlatformAuditEntry({
    required this.id,
    required this.eventType,
    required this.actorUid,
    required this.targetUid,
    required this.data,
    required this.createdAt,
  });

  static PlatformAuditEntry? fromRecord(PlatformRecord record) {
    final eventType = platformText(record.data['eventType']);
    final createdAt = platformTime(record.data['createdAt']);
    if (eventType == null || createdAt == null) return null;
    return PlatformAuditEntry(
      id: record.id,
      eventType: eventType,
      actorUid: platformText(record.data['actorUid']),
      targetUid: platformText(record.data['targetUid']),
      data: record.data,
      createdAt: createdAt,
    );
  }

  final String id;
  final String eventType;
  final String? actorUid;
  final String? targetUid;
  final Map<String, Object?> data;
  final DateTime createdAt;
}

final class PlatformBusinessDetail {
  const PlatformBusinessDetail({
    required this.business,
    required this.owner,
    required this.administrators,
    required this.counts,
    required this.staffPreview,
    required this.history,
    required this.audit,
    required this.names,
  });

  final PlatformBusiness business;
  final PlatformPerson? owner;

  /// The owner and every administrator, with their staff record.
  final List<PlatformStaffMember> administrators;
  final PlatformStaffCounts counts;

  /// Up to four people who are not owner or administrator, those needing
  /// attention first.
  final List<PlatformStaffMember> staffPreview;
  final List<PlatformLifecycleEvent> history;
  final List<PlatformAuditEntry> audit;

  /// Every id the history and the audit log mention, resolved to a name.
  final Map<String, String> names;
}

final class PlatformBusinessReader {
  PlatformBusinessReader(this._source, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final PlatformConsoleDataSource _source;
  final DateTime Function() _clock;

  static Future<List<PlatformLifecycleEvent>> history(
    PlatformConsoleDataSource source,
    String tenantId, {
    int limit = 10,
  }) async {
    final records = await source.query(
      PlatformQuery(
        'tenants/$tenantId/lifecycle_history',
        orderBy: 'createdAt',
        limit: limit,
      ),
    );
    return records
        .map(PlatformLifecycleEvent.fromRecord)
        .whereType<PlatformLifecycleEvent>()
        .toList();
  }

  Future<PlatformBusinessDetail?> load(String tenantId) async {
    final record = await _source.get('tenants/$tenantId');
    if (record == null) return null;
    final business = PlatformBusiness.fromRecord(record);
    if (business == null) {
      throw const FormatException('The business record is invalid.');
    }
    final now = _clock();
    final staffPath = 'tenants/$tenantId/staff';
    final results = await Future.wait<Object>([
      _source.query(
        PlatformQuery(
          staffPath,
          where: const <PlatformWhere>[
            PlatformWhere('role', PlatformQueryOp.isIn, <String>[
              'owner',
              'admin',
            ]),
          ],
          limit: 20,
        ),
      ),
      _source.query(PlatformQuery(staffPath, limit: 100)),
      _source.count(PlatformQuery(staffPath)),
      history(_source, tenantId),
      _source.query(
        PlatformQuery(
          'tenants/$tenantId/audit_logs',
          orderBy: 'createdAt',
          limit: 6,
        ),
      ),
    ]);
    PlatformStaffMember? member(PlatformRecord record) =>
        PlatformStaffMember.fromRecord(record, now);
    final administrators =
        (results[0] as List<PlatformRecord>)
            .map(member)
            .whereType<PlatformStaffMember>()
            .toList()
          ..sort((a, b) => a.role.index.compareTo(b.role.index));
    final everyone = (results[1] as List<PlatformRecord>)
        .map(member)
        .whereType<PlatformStaffMember>()
        .toList();
    final total = results[2] as int;
    final lifecycle = results[3] as List<PlatformLifecycleEvent>;
    final audit = (results[4] as List<PlatformRecord>)
        .map(PlatformAuditEntry.fromRecord)
        .whereType<PlatformAuditEntry>()
        .toList();
    final counts = PlatformStaffCounts(
      total: total,
      active: everyone
          .where((m) => m.standing == PlatformStaffStanding.active)
          .length,
      invited: everyone
          .where((m) => m.standing == PlatformStaffStanding.invited)
          .length,
      needAttention: everyone.where((m) => m.needsAttention).length,
      deactivated: everyone
          .where((m) => m.standing == PlatformStaffStanding.deactivated)
          .length,
    );
    int rank(PlatformStaffMember m) => switch (m.standing) {
      PlatformStaffStanding.emailRejected => 0,
      PlatformStaffStanding.linkExpired => 1,
      PlatformStaffStanding.invited => 2,
      PlatformStaffStanding.active => 3,
      PlatformStaffStanding.deactivated => 4,
    };
    final preview =
        everyone
            .where(
              (m) => m.role != TenantRole.owner && m.role != TenantRole.admin,
            )
            .toList()
          ..sort((a, b) {
            final byRank = rank(a).compareTo(rank(b));
            return byRank != 0 ? byRank : a.name.compareTo(b.name);
          });
    final staffNames = <String, String>{
      for (final m in everyone) m.uid: m.name,
    };
    final book = PlatformNameBook(_source);
    final missing = <String?>[
      ...lifecycle.map((event) => event.actorUid),
      ...audit.expand((entry) => <String?>[entry.actorUid, entry.targetUid]),
    ].whereType<String>().where((uid) => !staffNames.containsKey(uid));
    final resolved = await book.names(missing);
    return PlatformBusinessDetail(
      business: business,
      owner: await book.person(business.ownerUid),
      administrators: administrators,
      counts: counts,
      staffPreview: preview.take(4).toList(),
      history: lifecycle,
      audit: audit,
      names: <String, String>{...resolved, ...staffNames},
    );
  }
}

// ---------------------------------------------------------------------------
// Alerts, operations, activity.
// ---------------------------------------------------------------------------

enum PlatformAlertType {
  ownerUnavailable,
  noActiveAdministrator,
  reconciliationQuarantined,
  unknown,
}

final class PlatformAlert {
  const PlatformAlert({
    required this.id,
    required this.type,
    required this.tenantId,
    required this.uid,
    required this.requestedBy,
    required this.reason,
    required this.errorCode,
    required this.failureCount,
    required this.notified,
    required this.createdAt,
  });

  static PlatformAlert? fromRecord(PlatformRecord record) {
    final createdAt = platformTime(record.data['createdAt']);
    if (createdAt == null) return null;
    final tenantId = platformText(record.data['tenantId']);
    return PlatformAlert(
      id: record.id,
      type: switch (record.data['type']) {
        'tenant_owner_unavailable' => PlatformAlertType.ownerUnavailable,
        'no_active_administrator' => PlatformAlertType.noActiveAdministrator,
        'tenant_reconciliation_quarantined' =>
          PlatformAlertType.reconciliationQuarantined,
        _ => PlatformAlertType.unknown,
      },
      tenantId: tenantId != null && _isTenantId(tenantId) ? tenantId : null,
      uid: platformText(record.data['uid']),
      requestedBy: platformText(record.data['requestedBy']),
      reason: platformText(record.data['reason']),
      errorCode: platformText(record.data['errorCode']),
      failureCount: platformInt(record.data['consecutiveFailureCount']),
      notified: record.data['notificationStatus'] == 'completed',
      createdAt: createdAt,
    );
  }

  final String id;
  final PlatformAlertType type;
  final String? tenantId;

  /// The person whose disabling raised it.
  final String? uid;
  final String? requestedBy;
  final String? reason;
  final String? errorCode;
  final int? failureCount;

  /// The notification worker finished emailing it.
  final bool notified;
  final DateTime createdAt;
}

/// An alert with the names it mentions.
final class PlatformAlertView {
  const PlatformAlertView({
    required this.alert,
    required this.businessName,
    required this.personName,
    required this.requesterName,
  });

  final PlatformAlert alert;
  final String? businessName;
  final String? personName;
  final String? requesterName;
}

final class PlatformAlertsReader {
  PlatformAlertsReader(this._source, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final PlatformConsoleDataSource _source;
  final DateTime Function() _clock;

  /// **What counts as needing someone: raised in the last seven days.** An
  /// alert has no handled state - nothing writes one - so a window is the
  /// honest version of "open". Older alerts stay on the Alerts screen.
  static const Duration recentWindow = Duration(days: 7);

  Future<List<PlatformAlert>> recent() async {
    final since = _clock().subtract(recentWindow);
    final all = await list(limit: 50);
    return all.where((alert) => alert.createdAt.isAfter(since)).toList();
  }

  Future<List<PlatformAlert>> list({int limit = 30}) async {
    final records = await _source.query(
      PlatformQuery('platform_alerts', orderBy: 'createdAt', limit: limit),
    );
    return records
        .map(PlatformAlert.fromRecord)
        .whereType<PlatformAlert>()
        .toList();
  }

  Future<List<PlatformAlertView>> views(List<PlatformAlert> alerts) async {
    final names = PlatformNameBook(_source);
    final tenantNames = <String, Future<String?>>{};
    Future<String?> tenantName(String id) => tenantNames.putIfAbsent(
      id,
      () async => PlatformBusiness.fromRecord(
        await _source.get('tenants/$id') ??
            const PlatformRecord(path: 'tenants/-', data: {}),
      )?.name,
    );
    return Future.wait(
      alerts.map(
        (alert) async => PlatformAlertView(
          alert: alert,
          businessName: alert.tenantId == null
              ? null
              : await tenantName(alert.tenantId!),
          personName: await names.name(alert.uid),
          requesterName: await names.name(alert.requestedBy),
        ),
      ),
    );
  }
}

enum PlatformOperationStatus {
  pending,
  partiallyFailed,
  completed,
  quarantined,
}

final class PlatformOperation {
  const PlatformOperation({
    required this.id,
    required this.uid,
    required this.reactivating,
    required this.status,
    required this.attemptCount,
    required this.lastErrorCode,
    required this.nextAttemptAt,
  });

  static PlatformOperation? fromRecord(PlatformRecord record) {
    final uid = platformText(record.data['uid']);
    final target = record.data['targetStatus'];
    final status = switch (record.data['status']) {
      'pending' => PlatformOperationStatus.pending,
      'partially_failed' => PlatformOperationStatus.partiallyFailed,
      'completed' => PlatformOperationStatus.completed,
      'quarantined' => PlatformOperationStatus.quarantined,
      _ => null,
    };
    if (uid == null ||
        status == null ||
        (target != 'active' && target != 'disabled')) {
      return null;
    }
    return PlatformOperation(
      id: record.id,
      uid: uid,
      reactivating: target == 'active',
      status: status,
      attemptCount: platformInt(record.data['attemptCount']) ?? 1,
      lastErrorCode: platformText(record.data['lastErrorCode']),
      nextAttemptAt: platformTime(record.data['nextAttemptAt']),
    );
  }

  final String id;
  final String uid;
  final bool reactivating;
  final PlatformOperationStatus status;
  final int attemptCount;
  final String? lastErrorCode;
  final DateTime? nextAttemptAt;
}

Future<List<PlatformOperation>> loadPlatformOperationsInFlight(
  PlatformConsoleDataSource source,
) async {
  final records = await source.query(
    const PlatformQuery(
      'platform_user_operations',
      where: <PlatformWhere>[
        PlatformWhere('status', PlatformQueryOp.isIn, <String>[
          'pending',
          'partially_failed',
        ]),
      ],
      limit: 10,
    ),
  );
  return records
      .map(PlatformOperation.fromRecord)
      .whereType<PlatformOperation>()
      .toList();
}

enum PlatformActivityKind {
  businessCreated,
  businessChanged,
  personStatusChanged,
  suppressionInspected,
  suppressionCleared,
  ownerRecovered,
  administratorGranted,
  administratorRevoked,
  unknown,
}

enum PlatformActivityFilter {
  everything,
  businesses,
  people,
  administrators,
  email,
}

final class PlatformActivityEntry {
  const PlatformActivityEntry({
    required this.id,
    required this.kind,
    required this.actorUid,
    required this.targetUid,
    required this.tenantId,
    required this.from,
    required this.to,
    required this.reason,
    required this.status,
    required this.attemptCount,
    required this.affectedTenants,
    required this.reactivation,
    required this.createdAt,
  });

  static PlatformActivityEntry? fromRecord(PlatformRecord record) {
    final createdAt = platformTime(record.data['createdAt']);
    if (createdAt == null) return null;
    final data = record.data;
    final kind = switch ((data['eventType'], data['action'])) {
      ('tenant_requested', _) => PlatformActivityKind.businessCreated,
      ('tenant_lifecycle_changed', _) => PlatformActivityKind.businessChanged,
      ('global_user_status_changed', _) =>
        PlatformActivityKind.personStatusChanged,
      ('email_suppression_inspected', _) =>
        PlatformActivityKind.suppressionInspected,
      ('email_suppression_cleared', _) =>
        PlatformActivityKind.suppressionCleared,
      ('owner_recovered', _) => PlatformActivityKind.ownerRecovered,
      (_, 'grant_platform_admin') => PlatformActivityKind.administratorGranted,
      (_, 'revoke_platform_admin') => PlatformActivityKind.administratorRevoked,
      _ => PlatformActivityKind.unknown,
    };
    TenantStatus? status(Object? value) {
      try {
        return value == null ? null : TenantStatus.fromWire(value);
      } on FormatException {
        return null;
      }
    }

    final targetStatus = data['targetStatus'];
    return PlatformActivityEntry(
      id: record.id,
      kind: kind,
      actorUid:
          platformText(data['actorUid']) ?? platformText(data['requestedBy']),
      targetUid:
          platformText(data['uid']) ??
          platformText(data['targetUid']) ??
          platformText(data['replacementUid']),
      tenantId: platformText(data['tenantId']),
      from: status(data['fromStatus']),
      to: kind == PlatformActivityKind.personStatusChanged
          ? null
          : status(data['toStatus']),
      reason: platformText(data['reason']),
      status:
          platformText(data['status']) ??
          (targetStatus is String ? targetStatus : null),
      attemptCount: platformInt(data['attemptCount']),
      affectedTenants: data['affectedTenantIds'] is List
          ? (data['affectedTenantIds']! as List).length
          : null,
      reactivation: targetStatus == 'active'
          ? true
          : targetStatus == 'disabled'
          ? false
          : null,
      createdAt: createdAt,
    );
  }

  final String id;
  final PlatformActivityKind kind;
  final String? actorUid;
  final String? targetUid;
  final String? tenantId;
  final TenantStatus? from;
  final TenantStatus? to;
  final String? reason;

  /// For a person's status change: the saga's status. For others: whatever
  /// status field the record carries.
  final String? status;
  final int? attemptCount;
  final int? affectedTenants;

  /// For a person's status change: true when it reactivates, false when it
  /// disables.
  final bool? reactivation;
  final DateTime createdAt;

  /// A person's status change that has not finished.
  bool get inProgress => status == 'pending' || status == 'partially_failed';
}

final class PlatformActivityPage {
  const PlatformActivityPage({
    required this.entries,
    required this.next,
    required this.people,
    required this.businesses,
  });

  final List<PlatformActivityEntry> entries;
  final PlatformCursor? next;
  final Map<String, String> people;
  final Map<String, String> businesses;
}

final class PlatformActivityReader {
  PlatformActivityReader(this._source);

  final PlatformConsoleDataSource _source;

  static List<PlatformWhere> _where(PlatformActivityFilter filter) =>
      switch (filter) {
        PlatformActivityFilter.everything => const <PlatformWhere>[],
        PlatformActivityFilter.businesses => const <PlatformWhere>[
          PlatformWhere('eventType', PlatformQueryOp.isIn, <String>[
            'tenant_requested',
            'tenant_lifecycle_changed',
            'owner_recovered',
          ]),
        ],
        PlatformActivityFilter.people => const <PlatformWhere>[
          PlatformWhere(
            'eventType',
            PlatformQueryOp.equals,
            'global_user_status_changed',
          ),
        ],
        PlatformActivityFilter.administrators => const <PlatformWhere>[
          PlatformWhere('action', PlatformQueryOp.isIn, <String>[
            'grant_platform_admin',
            'revoke_platform_admin',
          ]),
        ],
        PlatformActivityFilter.email => const <PlatformWhere>[
          PlatformWhere('eventType', PlatformQueryOp.isIn, <String>[
            'email_suppression_inspected',
            'email_suppression_cleared',
          ]),
        ],
      };

  Future<PlatformActivityPage> page({
    PlatformActivityFilter filter = PlatformActivityFilter.everything,
    PlatformCursor? after,
    int pageSize = 20,
    String? aboutUid,
  }) async {
    var records = await _source.query(
      PlatformQuery(
        'platform_audit_logs',
        where: <PlatformWhere>[
          ..._where(filter),
          if (aboutUid != null)
            PlatformWhere('uid', PlatformQueryOp.equals, aboutUid),
        ],
        orderBy: 'createdAt',
        limit: pageSize + 1,
        startAfter: after,
      ),
    );
    PlatformCursor? next;
    if (records.length > pageSize) {
      records = records.take(pageSize).toList();
      next = PlatformCursor(records.last.data['createdAt'], records.last.id);
    }
    final entries = records
        .map(PlatformActivityEntry.fromRecord)
        .whereType<PlatformActivityEntry>()
        .toList();
    final people = await PlatformNameBook(
      _source,
    ).names(entries.expand((e) => <String?>[e.actorUid, e.targetUid]));
    final tenantIds = entries
        .map((e) => e.tenantId)
        .whereType<String>()
        .where(_isTenantId)
        .toSet();
    final tenants = await Future.wait(
      tenantIds.map((id) => _source.get('tenants/$id')),
    );
    return PlatformActivityPage(
      entries: entries,
      next: next,
      people: people,
      businesses: <String, String>{
        for (final record in tenants.whereType<PlatformRecord>())
          if (PlatformBusiness.fromRecord(record) case final business?)
            business.tenantId: business.name,
      },
    );
  }

  Future<int> countSince(DateTime since) => _source.count(
    PlatformQuery(
      'platform_audit_logs',
      where: <PlatformWhere>[
        PlatformWhere('createdAt', PlatformQueryOp.greaterOrEqual, since),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// The overview.
// ---------------------------------------------------------------------------

final class PlatformSuspension {
  const PlatformSuspension({required this.name, required this.since});

  final String name;
  final DateTime? since;
}

final class PlatformLimits {
  const PlatformLimits({
    required this.requestsPerDay,
    required this.businessesPerOwner,
  });

  static const PlatformLimits defaults = PlatformLimits(
    requestsPerDay: 5,
    businessesPerOwner: 25,
  );

  /// As the backend reads it: an integer outside 0..10000 is the default.
  static PlatformLimits fromRecord(PlatformRecord? record) {
    int read(String field, int fallback) {
      final value = record?.data[field];
      return value is int && value >= 0 && value <= 10000 ? value : fallback;
    }

    return PlatformLimits(
      requestsPerDay: read(
        'maxTenantRequestsPer24Hours',
        defaults.requestsPerDay,
      ),
      businessesPerOwner: read(
        'maxOwnedActiveTenantsPerUser',
        defaults.businessesPerOwner,
      ),
    );
  }

  final int requestsPerDay;
  final int businessesPerOwner;
}

/// What the overview reads, part by part.
enum PlatformOverviewPart {
  businesses,
  opened,
  accounts,
  alerts,
  suspensions,
  activity,
  operations,
  administrators,
}

final class PlatformOverview {
  const PlatformOverview({
    required this.readAt,
    required this.trading,
    required this.suspended,
    required this.archived,
    required this.openedThisMonth,
    required this.openedThisWeek,
    required this.businessesByWeek,
    required this.accounts,
    required this.accountsThisWeek,
    required this.accountsByWeek,
    required this.disabledAccounts,
    required this.alerts,
    required this.suspensions,
    required this.activity,
    required this.activityLastWeek,
    required this.operations,
    required this.operationNames,
    required this.administrators,
    required this.limits,
    this.unread = const <PlatformOverviewPart>{},
  });

  /// The parts that could not be read. Their tiles say so, and every other
  /// tile is drawn from what was read: one refused query - an index still
  /// building, a rule not yet deployed - costs one tile, not the overview.
  final Set<PlatformOverviewPart> unread;

  final DateTime readAt;
  final int trading;
  final int suspended;
  final int archived;
  final int openedThisMonth;
  final int openedThisWeek;

  /// Twelve weeks, oldest first, the current week last.
  final List<int> businessesByWeek;
  final int accounts;
  final int accountsThisWeek;
  final List<int> accountsByWeek;
  final int disabledAccounts;
  final List<PlatformAlertView> alerts;

  /// Suspended businesses, longest suspended first.
  final List<PlatformSuspension> suspensions;
  final PlatformActivityPage activity;
  final int activityLastWeek;
  final List<PlatformOperation> operations;
  final Map<String, String> operationNames;
  final List<PlatformPerson> administrators;
  final PlatformLimits limits;

  int get businesses => trading + suspended + archived;
}

/// Monday 00:00 of the week [moment] falls in, in local time.
DateTime platformWeekStart(DateTime moment) {
  final day = DateTime(moment.year, moment.month, moment.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

final class PlatformOverviewReader {
  PlatformOverviewReader(this._source, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final PlatformConsoleDataSource _source;
  final DateTime Function() _clock;

  static const int weeks = 12;

  Future<PlatformOverview> load() async {
    final now = _clock();
    final thisWeek = platformWeekStart(now);
    final starts = <DateTime>[
      for (var index = weeks - 1; index >= 0; index--)
        thisWeek.subtract(Duration(days: 7 * index)),
    ];
    final monthStart = DateTime(now.year, now.month);

    PlatformQuery between(String collection, DateTime from, DateTime? to) =>
        PlatformQuery(
          collection,
          where: <PlatformWhere>[
            PlatformWhere('createdAt', PlatformQueryOp.greaterOrEqual, from),
            if (to != null)
              PlatformWhere('createdAt', PlatformQueryOp.lessThan, to),
          ],
        );
    Future<List<int>> weekly(String collection) => Future.wait(<Future<int>>[
      for (var index = 0; index < weeks; index++)
        _source.count(
          between(
            collection,
            starts[index],
            index + 1 < weeks ? starts[index + 1] : null,
          ),
        ),
    ]);
    PlatformQuery status(String collection, String field, String value) =>
        PlatformQuery(
          collection,
          where: <PlatformWhere>[
            PlatformWhere(field, PlatformQueryOp.equals, value),
          ],
        );

    final alertsReader = PlatformAlertsReader(_source, clock: _clock);
    final activityReader = PlatformActivityReader(_source);
    final unread = <PlatformOverviewPart>{};
    Future<T> part<T>(
      PlatformOverviewPart name,
      Future<T> Function() read,
      T fallback,
    ) async {
      try {
        return await read();
      } catch (error, stackTrace) {
        reportPlatformRead(error, stackTrace, 'platform.overview_${name.name}');
        unread.add(name);
        return fallback;
      }
    }

    final noWeeks = List<int>.filled(weeks, 0);
    final results = await Future.wait<Object?>([
      part(
        PlatformOverviewPart.businesses,
        () => Future.wait(<Future<int>>[
          _source.count(status('tenants', 'status', 'active')),
          _source.count(status('tenants', 'status', 'suspended')),
          _source.count(status('tenants', 'status', 'archived')),
        ]),
        const <int>[0, 0, 0],
      ),
      part(
        PlatformOverviewPart.opened,
        () async => <Object>[
          await _source.count(between('tenants', monthStart, null)),
          await weekly('tenants'),
        ],
        <Object>[0, noWeeks],
      ),
      part(
        PlatformOverviewPart.accounts,
        () async => <Object>[
          await _source.count(const PlatformQuery('users')),
          await weekly('users'),
          await _source.count(status('users', 'globalStatus', 'disabled')),
        ],
        <Object>[0, noWeeks, 0],
      ),
      part(
        PlatformOverviewPart.alerts,
        () async => alertsReader.views(await alertsReader.recent()),
        const <PlatformAlertView>[],
      ),
      part(
        PlatformOverviewPart.suspensions,
        () => _source.query(
          const PlatformQuery(
            'tenants',
            where: <PlatformWhere>[
              PlatformWhere('status', PlatformQueryOp.equals, 'suspended'),
            ],
            orderBy: 'updatedAt',
            limit: 50,
          ),
        ),
        const <PlatformRecord>[],
      ),
      part(
        PlatformOverviewPart.activity,
        () async => <Object>[
          await activityReader.page(pageSize: 4),
          await activityReader.countSince(
            now.subtract(const Duration(days: 7)),
          ),
        ],
        <Object>[
          const PlatformActivityPage(
            entries: <PlatformActivityEntry>[],
            next: null,
            people: <String, String>{},
            businesses: <String, String>{},
          ),
          0,
        ],
      ),
      part(
        PlatformOverviewPart.operations,
        () async {
          final operations = await loadPlatformOperationsInFlight(_source);
          return <Object>[
            operations,
            await PlatformNameBook(
              _source,
            ).names(operations.map((operation) => operation.uid)),
          ];
        },
        <Object>[const <PlatformOperation>[], const <String, String>{}],
      ),
      part(
        PlatformOverviewPart.administrators,
        () => _source.query(
          const PlatformQuery(
            'users',
            where: <PlatformWhere>[
              PlatformWhere(
                'accountType',
                PlatformQueryOp.equals,
                'platform_admin',
              ),
            ],
            limit: 10,
          ),
        ),
        const <PlatformRecord>[],
      ),
      // The limits fall back to the backend's own defaults, which is what the
      // backend does with a missing document too.
      platformOrNull<PlatformRecord?>(
        _source.get('platform_config/limits'),
        'platform.overview_limits',
      ),
    ]);
    if (unread.length == PlatformOverviewPart.values.length) {
      throw StateError('No part of the platform overview could be read.');
    }
    final businesses = results[0]! as List<int>;
    final opened = results[1]! as List<Object>;
    final accounts = results[2]! as List<Object>;
    final businessesByWeek = opened[1] as List<int>;
    final accountsByWeek = accounts[1] as List<int>;
    final suspended =
        (results[4]! as List<PlatformRecord>)
            .map(PlatformBusiness.fromRecord)
            .whereType<PlatformBusiness>()
            .toList()
          ..sort((a, b) => (a.updatedAt ?? now).compareTo(b.updatedAt ?? now));
    final activity = results[5]! as List<Object>;
    final operations = results[6]! as List<Object>;
    final administrators = (results[7]! as List<PlatformRecord>)
        .map(PlatformPerson.fromRecord)
        .whereType<PlatformPerson>()
        .toList();
    return PlatformOverview(
      readAt: now,
      trading: businesses[0],
      suspended: businesses[1],
      archived: businesses[2],
      openedThisMonth: opened[0] as int,
      openedThisWeek: businessesByWeek.last,
      businessesByWeek: businessesByWeek,
      accounts: accounts[0] as int,
      accountsThisWeek: accountsByWeek.last,
      accountsByWeek: accountsByWeek,
      disabledAccounts: accounts[2] as int,
      alerts: results[3]! as List<PlatformAlertView>,
      suspensions: <PlatformSuspension>[
        for (final business in suspended)
          PlatformSuspension(name: business.name, since: business.updatedAt),
      ],
      activity: activity[0] as PlatformActivityPage,
      activityLastWeek: activity[1] as int,
      operations: operations[0] as List<PlatformOperation>,
      operationNames: operations[1] as Map<String, String>,
      administrators: administrators,
      limits: PlatformLimits.fromRecord(results[8] as PlatformRecord?),
      unread: Set.unmodifiable(unread),
    );
  }
}

// ---------------------------------------------------------------------------
// People.
// ---------------------------------------------------------------------------

enum PlatformPeopleFilter {
  everyone,
  owners,
  staff,
  noBusiness,
  disabled,
  platform,
}

/// Where a person works, as a row shows it.
final class PlatformMembership {
  const PlatformMembership({
    required this.tenantId,
    required this.businessName,
    required this.role,
    required this.status,
  });

  final String tenantId;
  final String businessName;
  final TenantRole role;
  final MembershipStatus status;
}

final class PlatformPersonRow {
  const PlatformPersonRow({
    required this.person,
    required this.memberships,
    required this.operation,
    this.membershipsKnown = true,
  });

  final PlatformPerson person;
  final List<PlatformMembership> memberships;

  /// False when where this person works could not be read, and [memberships]
  /// is empty for that reason rather than because they work nowhere. The row
  /// then says what the person's own counters say.
  final bool membershipsKnown;

  /// A disable or reactivation still running for this person.
  final PlatformOperation? operation;
}

final class PlatformPeopleDirectory {
  PlatformPeopleDirectory(this._source);

  final PlatformConsoleDataSource _source;

  static List<PlatformWhere> _where(PlatformPeopleFilter filter) =>
      switch (filter) {
        PlatformPeopleFilter.everyone => const <PlatformWhere>[],
        PlatformPeopleFilter.owners => const <PlatformWhere>[
          PlatformWhere('ownedTenantCount', PlatformQueryOp.greaterThan, 0),
        ],
        PlatformPeopleFilter.staff => const <PlatformWhere>[
          PlatformWhere('ownedTenantCount', PlatformQueryOp.equals, 0),
          PlatformWhere('membershipCount', PlatformQueryOp.greaterThan, 0),
        ],
        PlatformPeopleFilter.noBusiness => const <PlatformWhere>[
          PlatformWhere('accountType', PlatformQueryOp.equals, 'tenant_user'),
          PlatformWhere('membershipCount', PlatformQueryOp.equals, 0),
        ],
        PlatformPeopleFilter.disabled => const <PlatformWhere>[
          PlatformWhere('globalStatus', PlatformQueryOp.equals, 'disabled'),
        ],
        PlatformPeopleFilter.platform => const <PlatformWhere>[
          PlatformWhere(
            'accountType',
            PlatformQueryOp.equals,
            'platform_admin',
          ),
        ],
      };

  /// The field a filter must order by first: Firestore orders an inequality
  /// field before any other.
  static String _orderOf(PlatformPeopleFilter filter) => switch (filter) {
    PlatformPeopleFilter.owners => 'ownedTenantCount',
    PlatformPeopleFilter.staff => 'membershipCount',
    _ => 'createdAt',
  };

  /// Each count on its own: one that cannot be read - an index still
  /// building, say - leaves its chip without a figure, not every chip.
  Future<Map<PlatformPeopleFilter, int?>> counts() async {
    final values = await Future.wait(
      PlatformPeopleFilter.values.map(
        (filter) => platformOrNull(
          _source.count(PlatformQuery('users', where: _where(filter))),
          'platform.people_count_read',
        ),
      ),
    );
    return <PlatformPeopleFilter, int?>{
      for (var index = 0; index < values.length; index++)
        PlatformPeopleFilter.values[index]: values[index],
    };
  }

  Future<PlatformPage<PlatformPersonRow>> page({
    required PlatformPeopleFilter filter,
    String search = '',
    PlatformCursor? after,
    int firstIndex = 0,
    int pageSize = 8,
  }) async {
    final prefix = search.trim().toLowerCase();
    final order = prefix.isNotEmpty ? 'email' : _orderOf(filter);
    var records = await _source.query(
      PlatformQuery(
        'users',
        where: <PlatformWhere>[
          if (prefix.isNotEmpty) ...<PlatformWhere>[
            PlatformWhere('email', PlatformQueryOp.greaterOrEqual, prefix),
            PlatformWhere(
              'email',
              PlatformQueryOp.lessThan,
              '$prefix$_prefixEnd',
            ),
          ] else
            ..._where(filter),
        ],
        orderBy: order,
        descending: prefix.isEmpty,
        limit: pageSize + 1,
        startAfter: after,
      ),
    );
    PlatformCursor? next;
    if (records.length > pageSize) {
      records = records.take(pageSize).toList();
      next = PlatformCursor(records.last.data[order], records.last.id);
    }
    final people = records
        .map(PlatformPerson.fromRecord)
        .whereType<PlatformPerson>()
        .toList();
    final operations = await loadPlatformOperationsInFlight(_source);
    final tenantNames = <String, Future<String?>>{};
    Future<String?> tenantName(String id) =>
        tenantNames.putIfAbsent(id, () async {
          final record = await _source.get('tenants/$id');
          return record == null
              ? null
              : PlatformBusiness.fromRecord(record)?.name;
        });
    var membershipsFailed = false;
    final rows = await Future.wait(
      people.map((person) async {
        // **Where someone works is a collection-group read on `staff`**, which
        // the rules may refuse. A refusal costs the row its business names,
        // not the whole list: the person is still read, and the row falls
        // back to their own counters.
        List<PlatformRecord> staff;
        try {
          staff = person.isPlatformAdmin
              ? const <PlatformRecord>[]
              : await _source.query(
                  PlatformQuery(
                    'staff',
                    collectionGroup: true,
                    where: <PlatformWhere>[
                      PlatformWhere('uid', PlatformQueryOp.equals, person.uid),
                    ],
                    limit: 5,
                  ),
                );
        } catch (error, stackTrace) {
          if (!membershipsFailed) {
            membershipsFailed = true;
            reportPlatformRead(
              error,
              stackTrace,
              'platform.people_memberships_read',
            );
          }
          return PlatformPersonRow(
            person: person,
            memberships: const <PlatformMembership>[],
            membershipsKnown: false,
            operation: operations
                .where((operation) => operation.uid == person.uid)
                .firstOrNull,
          );
        }
        final memberships = <PlatformMembership>[];
        for (final record in staff) {
          final tenantId = record.parentId;
          if (tenantId == null || !_isTenantId(tenantId)) continue;
          try {
            final name = await tenantName(tenantId);
            if (name == null) continue;
            memberships.add(
              PlatformMembership(
                tenantId: tenantId,
                businessName: name,
                role: TenantRole.fromWire(record.data['role']),
                status: MembershipStatus.fromWire(record.data['status']),
              ),
            );
          } on FormatException {
            continue;
          }
        }
        memberships.sort((a, b) => a.role.index.compareTo(b.role.index));
        return PlatformPersonRow(
          person: person,
          memberships: memberships,
          operation: operations
              .where((operation) => operation.uid == person.uid)
              .firstOrNull,
        );
      }),
    );
    return PlatformPage(items: rows, next: next, firstIndex: firstIndex);
  }
}

// ---------------------------------------------------------------------------
// Email delivery.
// ---------------------------------------------------------------------------

enum PlatformSuppressionCategory {
  hardBounce,
  invalidRecipient,
  spamComplaint,
  providerBlock,
}

final class PlatformSuppression {
  const PlatformSuppression({
    required this.category,
    required this.since,
    required this.active,
    required this.reasonClass,
  });

  final PlatformSuppressionCategory category;
  final DateTime? since;
  final bool active;
  final String reasonClass;
}

final class PlatformSuppressionReview {
  const PlatformSuppressionReview({
    required this.items,
    required this.clearedCount,
  });

  static PlatformSuppressionReview fromCallable(Object? value) {
    if (value is! Map ||
        value['items'] is! List ||
        value['clearedCount'] is! int) {
      throw const FormatException('The suppression review is invalid.');
    }
    final items = <PlatformSuppression>[];
    for (final item in value['items']! as List) {
      if (item is! Map) {
        throw const FormatException('The suppression review is invalid.');
      }
      final category = switch (item['category']) {
        'hard_bounce' => PlatformSuppressionCategory.hardBounce,
        'invalid_recipient' => PlatformSuppressionCategory.invalidRecipient,
        'spam_complaint' => PlatformSuppressionCategory.spamComplaint,
        'permanent_provider_block' => PlatformSuppressionCategory.providerBlock,
        _ => throw const FormatException('The suppression review is invalid.'),
      };
      final eventDate = item['eventDate'];
      items.add(
        PlatformSuppression(
          category: category,
          since: eventDate is String ? DateTime.tryParse(eventDate) : null,
          active: item['status'] == 'active',
          reasonClass: item['providerReasonClass'] is String
              ? item['providerReasonClass']! as String
              : 'unknown_temporary',
        ),
      );
    }
    return PlatformSuppressionReview(
      items: List.unmodifiable(items),
      clearedCount: value['clearedCount']! as int,
    );
  }

  final List<PlatformSuppression> items;
  final int clearedCount;

  List<PlatformSuppression> get active =>
      items.where((item) => item.active).toList();

  bool get needsSpamEvidence => active.any(
    (item) => item.category == PlatformSuppressionCategory.spamComplaint,
  );
}

/// Why an address may be cleared, as the backend accepts it.
enum PlatformClearConfirmation {
  addressCorrected('address_corrected'),
  addressVerified('address_independently_verified'),
  spamComplaint('clear_spam_complaint');

  const PlatformClearConfirmation(this.wireValue);

  final String wireValue;
}

abstract interface class ReviewEmailSuppressionCallable {
  Future<Object?> call(Map<String, Object?> payload);
}

final class PlatformSuppressionCallableException implements Exception {
  const PlatformSuppressionCallableException(this.code);

  final String code;
}

final class FirebaseReviewEmailSuppressionCallable
    implements ReviewEmailSuppressionCallable {
  FirebaseReviewEmailSuppressionCallable({FirebaseFunctions? functions})
    : _given = functions;

  /// Resolved on first call, so building the console never needs a Firebase
  /// app until it actually asks for something.
  final FirebaseFunctions? _given;

  FirebaseFunctions get _functions => _given ?? FirebaseFunctions.instance;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    try {
      final result = await traceServerCall(
        'reviewEmailSuppression',
        () => _functions
            .httpsCallable('reviewEmailSuppression')
            .call<Object?>(payload),
      );
      return result.data;
    } on FirebaseFunctionsException catch (error) {
      throw PlatformSuppressionCallableException(error.code);
    }
  }
}

final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// The address as the backend will look it up, or null when it would refuse it.
String? normalizePlatformEmail(String raw) {
  final email = raw.trim().toLowerCase();
  if (email.length < 3 ||
      email.length > 320 ||
      !_emailPattern.hasMatch(email)) {
    return null;
  }
  return email;
}

final class PlatformSuppressionGateway {
  PlatformSuppressionGateway(
    this._callable, {
    PlatformTenantRequestIdFactory? requestIdFactory,
  }) : _requestIds = requestIdFactory ?? securePlatformRequestId;

  final ReviewEmailSuppressionCallable _callable;
  final PlatformTenantRequestIdFactory _requestIds;

  /// The reason a lookup is recorded under. **A lookup is itself audited** -
  /// the backend writes `email_suppression_inspected` on every call - so it
  /// says plainly where it came from.
  static const String inspectReason = 'Looked up from the platform console.';

  Future<PlatformSuppressionReview> inspect(String email) async {
    final normalized = normalizePlatformEmail(email);
    if (normalized == null) throw ArgumentError.value(email, 'email');
    return PlatformSuppressionReview.fromCallable(
      await _callable.call(<String, Object?>{
        'email': normalized,
        'action': 'inspect',
        'reason': inspectReason,
        'requestId': _requestIds(),
      }),
    );
  }

  Future<PlatformSuppressionReview> clear({
    required String email,
    required String reason,
    required PlatformClearConfirmation confirmation,
    String? evidenceReference,
  }) async {
    final normalized = normalizePlatformEmail(email);
    final trimmed = reason.trim();
    if (normalized == null) throw ArgumentError.value(email, 'email');
    if (trimmed.isEmpty || trimmed.length > 1000) {
      throw ArgumentError.value(reason, 'reason');
    }
    return PlatformSuppressionReview.fromCallable(
      await _callable.call(<String, Object?>{
        'email': normalized,
        'action': 'clear',
        'reason': trimmed,
        'confirmation': confirmation.wireValue,
        if (evidenceReference != null && evidenceReference.trim().isNotEmpty)
          'evidenceReference': evidenceReference.trim(),
        'requestId': _requestIds(),
      }),
    );
  }
}

/// [future]'s value, or null - reported - when it cannot be read: for the
/// parts of a screen that can be missing without the screen failing.
Future<T?> platformOrNull<T>(Future<T> future, String boundary) async {
  try {
    return await future;
  } catch (error, stackTrace) {
    reportPlatformRead(error, stackTrace, boundary);
    return null;
  }
}

/// Reports a console read that failed, the way every platform screen does.
void reportPlatformRead(Object error, StackTrace stackTrace, String boundary) {
  AppTelemetry.captureHandled(error, stackTrace, boundary: boundary);
}
