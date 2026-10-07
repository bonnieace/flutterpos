import 'package:uzapay_pos/tenancy/platform_console_data.dart';
import 'package:uzapay_pos/tenancy/platform_global_user_status.dart';
import 'package:uzapay_pos/tenancy/platform_tenant_console.dart';

/// Answers the console's [PlatformQuery]s from documents held by path, with
/// Firestore's semantics for the parts the console uses: a document missing
/// the order field is not in an ordered result, ties break on the document id
/// in the sort's own direction,
/// and a cursor starts after its row.
final class MemoryPlatformConsoleDataSource
    implements PlatformConsoleDataSource {
  MemoryPlatformConsoleDataSource(Map<String, Map<String, Object?>> documents)
    : documents = Map.of(documents);

  final Map<String, Map<String, Object?>> documents;
  final List<PlatformQuery> queries = <PlatformQuery>[];
  int counts = 0;

  bool _inCollection(String path, PlatformQuery query) {
    final parts = path.split('/');
    if (query.collectionGroup) {
      return parts.length >= 2 && parts[parts.length - 2] == query.collection;
    }
    final parent = parts.sublist(0, parts.length - 1).join('/');
    return parent == query.collection;
  }

  static int _compare(Object? a, Object? b) {
    if (a is DateTime && b is DateTime) return a.compareTo(b);
    if (a is num && b is num) return a.compareTo(b);
    if (a is String && b is String) return a.compareTo(b);
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    return a.toString().compareTo(b.toString());
  }

  static bool _matches(Map<String, Object?> data, PlatformWhere clause) {
    if (!data.containsKey(clause.field)) return false;
    final value = data[clause.field];
    return switch (clause.op) {
      PlatformQueryOp.equals => value == clause.value,
      PlatformQueryOp.isIn => (clause.value! as List).contains(value),
      PlatformQueryOp.greaterThan =>
        value != null &&
            value.runtimeType == clause.value.runtimeType &&
            _compare(value, clause.value) > 0,
      PlatformQueryOp.greaterOrEqual =>
        value != null &&
            value.runtimeType == clause.value.runtimeType &&
            _compare(value, clause.value) >= 0,
      PlatformQueryOp.lessThan =>
        value != null &&
            value.runtimeType == clause.value.runtimeType &&
            _compare(value, clause.value) < 0,
    };
  }

  List<MapEntry<String, Map<String, Object?>>> _filtered(PlatformQuery query) =>
      documents.entries
          .where((entry) => _inCollection(entry.key, query))
          .where((entry) => query.where.every((c) => _matches(entry.value, c)))
          .toList();

  static String _id(String path) => path.substring(path.lastIndexOf('/') + 1);

  @override
  Future<List<PlatformRecord>> query(PlatformQuery query) async {
    queries.add(query);
    var rows = _filtered(query);
    final order = query.orderBy;
    if (order != null) {
      rows = rows.where((row) => row.value.containsKey(order)).toList()
        ..sort((a, b) {
          final byField = _compare(a.value[order], b.value[order]);
          final byId = _id(a.key).compareTo(_id(b.key));
          final both = byField != 0 ? byField : byId;
          return query.descending ? -both : both;
        });
      final cursor = query.startAfter;
      if (cursor != null) {
        final index = rows.indexWhere(
          (row) =>
              _compare(row.value[order], cursor.value) == 0 &&
              _id(row.key) == cursor.id,
        );
        rows = index < 0 ? rows : rows.sublist(index + 1);
      }
    } else {
      rows.sort((a, b) => _id(a.key).compareTo(_id(b.key)));
    }
    if (query.limit != null && rows.length > query.limit!) {
      rows = rows.sublist(0, query.limit);
    }
    return <PlatformRecord>[
      for (final row in rows)
        PlatformRecord(path: row.key, data: Map.of(row.value)),
    ];
  }

  @override
  Future<int> count(PlatformQuery query) async {
    counts++;
    return _filtered(query).length;
  }

  @override
  Future<PlatformRecord?> get(String path) async {
    final data = documents[path];
    return data == null ? null : PlatformRecord(path: path, data: Map.of(data));
  }
}

/// The exact-review data source the person page reads, answered from the
/// same documents.
final class MemoryPlatformGlobalUserDataSource
    implements PlatformGlobalUserDataSource {
  MemoryPlatformGlobalUserDataSource(this.memory);

  final MemoryPlatformConsoleDataSource memory;

  PlatformTenantDocument _document(String path) => PlatformTenantDocument(
    id: path.substring(path.lastIndexOf('/') + 1),
    data: <String, Object?>{
      ...memory.documents[path]!,
      'updatedAt': memory.documents[path]!['updatedAt'] ?? DateTime.utc(2026),
    },
  );

  @override
  Future<void> prepareExactReview(String uid) async {}

  @override
  Future<PlatformTenantDocument?> loadRootUser(String uid) async =>
      memory.documents.containsKey('users/$uid')
      ? _document('users/$uid')
      : null;

  @override
  Future<List<PlatformCanonicalStaffDocument>> loadTargetStaffDocuments(
    String uid,
  ) async => <PlatformCanonicalStaffDocument>[
    for (final entry in memory.documents.entries)
      if (entry.key.startsWith('tenants/') &&
          entry.key.contains('/staff/') &&
          entry.value['uid'] == uid)
        PlatformCanonicalStaffDocument(
          tenantId: entry.key.split('/')[1],
          id: uid,
          data: <String, Object?>{
            'uid': uid,
            'role': entry.value['role'],
            'status': entry.value['status'],
          },
        ),
  ];

  @override
  Future<List<PlatformTenantDocument>> loadOwnedTenantDocuments(
    String uid,
  ) async => <PlatformTenantDocument>[
    for (final entry in memory.documents.entries)
      if (entry.key.split('/').length == 2 &&
          entry.key.startsWith('tenants/') &&
          entry.value['ownerUid'] == uid)
        _document(entry.key),
  ];

  @override
  Future<PlatformTenantDocument?> loadTenant(String tenantId) async =>
      memory.documents.containsKey('tenants/$tenantId')
      ? _document('tenants/$tenantId')
      : null;

  @override
  Future<List<PlatformCanonicalStaffDocument>> loadAdministrativeStaffDocuments(
    String tenantId,
  ) async => <PlatformCanonicalStaffDocument>[
    for (final entry in memory.documents.entries)
      if (entry.key.startsWith('tenants/$tenantId/staff/') &&
          (entry.value['role'] == 'owner' || entry.value['role'] == 'admin'))
        PlatformCanonicalStaffDocument(
          tenantId: tenantId,
          id: entry.key.split('/').last,
          data: <String, Object?>{
            'uid': entry.value['uid'],
            'role': entry.value['role'],
            'status': entry.value['status'],
          },
        ),
  ];
}

/// Answers `reviewEmailSuppression`: one address is suppressed.
final class MemoryReviewEmailSuppressionCallable
    implements ReviewEmailSuppressionCallable {
  MemoryReviewEmailSuppressionCallable({this.suppressed = const {}});

  /// Address to (category, ISO date).
  final Map<String, (String, String)> suppressed;
  final List<Map<String, Object?>> calls = <Map<String, Object?>>[];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    calls.add(payload);
    final hit = suppressed[payload['email']];
    final clearing = payload['action'] == 'clear';
    return <String, Object?>{
      'items': <Object?>[
        if (hit != null)
          <String, Object?>{
            'category': hit.$1,
            'eventDate': hit.$2,
            'status': clearing ? 'cleared' : 'active',
            'providerReasonClass': hit.$1,
          },
      ],
      'clearedCount': clearing && hit != null ? 1 : 0,
    };
  }
}

/// Records `setTenantLifecycle` calls and answers as the backend does.
final class MemorySetTenantLifecycleCallable
    implements SetTenantLifecycleCallable {
  final List<Map<String, Object?>> calls = <Map<String, Object?>>[];
  Object? failWith;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    calls.add(payload);
    if (failWith case final error?) throw error;
    return <String, Object?>{
      'tenantId': payload['tenantId'],
      'previousStatus': 'active',
      'status': payload['status'],
      'fanoutOperationId': 'fanout-1',
    };
  }
}
