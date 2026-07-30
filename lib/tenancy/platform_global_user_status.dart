import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'platform_tenant_review.dart';
import 'tenant_bootstrap.dart';
import 'tenant_id.dart';
import 'tenant_request.dart';
import 'tenant_types.dart';

enum PlatformGlobalStatus { active, disabled }

enum PlatformGlobalUserAction {
  disable('disabled'),
  reactivate('active');

  const PlatformGlobalUserAction(this.targetStatus);

  final String targetStatus;
}

final class PlatformCanonicalStaffDocument {
  const PlatformCanonicalStaffDocument({
    required this.tenantId,
    required this.id,
    required this.data,
  });

  final String tenantId;
  final String id;
  final Map<String, Object?> data;
}

abstract interface class PlatformGlobalUserDataSource {
  Future<void> prepareExactReview(String uid);

  Future<PlatformTenantDocument?> loadRootUser(String uid);

  Future<List<PlatformCanonicalStaffDocument>> loadTargetStaffDocuments(
    String uid,
  );

  Future<List<PlatformTenantDocument>> loadOwnedTenantDocuments(String uid);

  Future<PlatformTenantDocument?> loadTenant(String tenantId);

  Future<List<PlatformCanonicalStaffDocument>> loadAdministrativeStaffDocuments(
    String tenantId,
  );
}

abstract interface class GetGlobalUserStatusReviewCallable {
  Future<Object?> call(Map<String, Object?> payload);
}

final class FirebaseGetGlobalUserStatusReviewCallable
    implements GetGlobalUserStatusReviewCallable {
  FirebaseGetGlobalUserStatusReviewCallable({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    try {
      final result = await _functions
          .httpsCallable('getGlobalUserStatusReview')
          .call<Object?>(payload);
      return result.data;
    } on FirebaseFunctionsException catch (error) {
      throw PlatformGlobalUserStatusCallableException(error.code);
    }
  }
}

final class FirebasePlatformGlobalUserDataSource
    implements PlatformGlobalUserDataSource {
  FirebasePlatformGlobalUserDataSource({
    GetGlobalUserStatusReviewCallable? callable,
  }) : _callable = callable ?? FirebaseGetGlobalUserStatusReviewCallable();

  final GetGlobalUserStatusReviewCallable _callable;
  String? _loadedUid;
  _GlobalUserReviewBundle? _bundle;

  @override
  Future<void> prepareExactReview(String uid) => _load(uid);

  @override
  Future<PlatformTenantDocument?> loadRootUser(String uid) async =>
      _bundle?.roots[uid];

  @override
  Future<List<PlatformCanonicalStaffDocument>> loadTargetStaffDocuments(
    String uid,
  ) async {
    await _requireLoaded(uid);
    return _bundle!.targetStaff;
  }

  @override
  Future<List<PlatformTenantDocument>> loadOwnedTenantDocuments(
    String uid,
  ) async {
    await _requireLoaded(uid);
    return _bundle!.ownedTenants;
  }

  @override
  Future<PlatformTenantDocument?> loadTenant(String tenantId) async {
    return _bundle?.tenants[tenantId];
  }

  @override
  Future<List<PlatformCanonicalStaffDocument>> loadAdministrativeStaffDocuments(
    String tenantId,
  ) async =>
      _bundle?.administrativeStaff
          .where((staff) => staff.tenantId == tenantId)
          .toList(growable: false) ??
      const [];

  Future<void> _requireLoaded(String uid) async {
    if (_loadedUid != uid) await _load(uid);
    if (_bundle == null) {
      throw StateError('The exact global-user review is unavailable.');
    }
  }

  Future<void> _load(String uid) async {
    final response = await _callable.call({'uid': uid});
    _loadedUid = uid;
    _bundle = _GlobalUserReviewBundle.fromCallable(response, expectedUid: uid);
  }
}

final class _GlobalUserReviewBundle {
  const _GlobalUserReviewBundle({
    required this.roots,
    required this.targetStaff,
    required this.ownedTenants,
    required this.tenants,
    required this.administrativeStaff,
  });

  factory _GlobalUserReviewBundle.fromCallable(
    Object? value, {
    required String expectedUid,
  }) {
    if (value is! Map || value['found'] is! bool) {
      throw const FormatException('Exact global-user review is invalid.');
    }
    if (value['found'] == false) {
      if (value.length != 1) {
        throw const FormatException('Exact global-user review is invalid.');
      }
      return const _GlobalUserReviewBundle(
        roots: {},
        targetStaff: [],
        ownedTenants: [],
        tenants: {},
        administrativeStaff: [],
      );
    }
    const keys = {
      'found',
      'user',
      'targetStaff',
      'ownedTenants',
      'tenants',
      'administrativeStaff',
      'administrativeRoots',
    };
    if (value.length != keys.length ||
        value.keys.any((key) => key is! String || !keys.contains(key)) ||
        value['targetStaff'] is! List ||
        value['ownedTenants'] is! List ||
        value['tenants'] is! List ||
        value['administrativeStaff'] is! List ||
        value['administrativeRoots'] is! List) {
      throw const FormatException('Exact global-user review is invalid.');
    }
    final user = _reviewDocument(value['user'], root: true);
    if (user.id != expectedUid) {
      throw const FormatException(
        'Exact global-user review returned another UID.',
      );
    }
    final administrativeRoots = (value['administrativeRoots']! as List)
        .map((item) => _reviewDocument(item, root: true))
        .toList(growable: false);
    final roots = <String, PlatformTenantDocument>{user.id: user};
    for (final root in administrativeRoots) {
      if (roots.containsKey(root.id)) {
        throw const FormatException(
          'Exact global-user review has duplicate roots.',
        );
      }
      roots[root.id] = root;
    }
    final ownedTenants = (value['ownedTenants']! as List)
        .map((item) => _reviewDocument(item))
        .toList(growable: false);
    final tenantList = (value['tenants']! as List)
        .map((item) => _reviewDocument(item))
        .toList(growable: false);
    final tenants = <String, PlatformTenantDocument>{};
    for (final tenant in tenantList) {
      if (tenants.containsKey(tenant.id)) {
        throw const FormatException(
          'Exact global-user review has duplicate tenants.',
        );
      }
      tenants[tenant.id] = tenant;
    }
    return _GlobalUserReviewBundle(
      roots: Map.unmodifiable(roots),
      targetStaff: List.unmodifiable(
        (value['targetStaff']! as List).map(_reviewStaffDocument),
      ),
      ownedTenants: List.unmodifiable(ownedTenants),
      tenants: Map.unmodifiable(tenants),
      administrativeStaff: List.unmodifiable(
        (value['administrativeStaff']! as List).map(_reviewStaffDocument),
      ),
    );
  }

  final Map<String, PlatformTenantDocument> roots;
  final List<PlatformCanonicalStaffDocument> targetStaff;
  final List<PlatformTenantDocument> ownedTenants;
  final Map<String, PlatformTenantDocument> tenants;
  final List<PlatformCanonicalStaffDocument> administrativeStaff;
}

PlatformTenantDocument _reviewDocument(Object? value, {bool root = false}) {
  if (value is! Map ||
      value.length != 2 ||
      value['id'] is! String ||
      value['data'] is! Map) {
    throw const FormatException(
      'Exact global-user review document is invalid.',
    );
  }
  final data = <String, Object?>{};
  for (final entry in (value['data']! as Map).entries) {
    if (entry.key is! String) {
      throw const FormatException(
        'Exact global-user review document is invalid.',
      );
    }
    data[entry.key! as String] = entry.value;
  }
  if (root) {
    final millis = data.remove('updatedAtMillis');
    if (millis is! int) {
      throw const FormatException('Exact global-user review root is invalid.');
    }
    data['updatedAt'] = DateTime.fromMillisecondsSinceEpoch(
      millis,
      isUtc: true,
    );
  }
  return PlatformTenantDocument(id: value['id']! as String, data: data);
}

PlatformCanonicalStaffDocument _reviewStaffDocument(Object? value) {
  if (value is! Map ||
      value.length != 3 ||
      value['tenantId'] is! String ||
      value['id'] is! String ||
      value['data'] is! Map) {
    throw const FormatException('Exact global-user review staff is invalid.');
  }
  final document = _reviewDocument({'id': value['id'], 'data': value['data']});
  return PlatformCanonicalStaffDocument(
    tenantId: value['tenantId']! as String,
    id: document.id,
    data: document.data,
  );
}

final class PlatformGlobalUserRecord {
  const PlatformGlobalUserRecord._({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.accountType,
    required this.status,
    required this.updatedAt,
  });

  factory PlatformGlobalUserRecord.fromDocument(
    PlatformTenantDocument document,
  ) {
    late final String uid;
    try {
      uid = validateTenantDocumentId(document.id, fieldName: 'uid');
    } on ArgumentError {
      throw const FormatException('The root user is invalid.');
    }
    final email = document.data['email'];
    final displayName = document.data['displayName'];
    final accountType = document.data['accountType'];
    final status = document.data['globalStatus'];
    if (email is! String ||
        email.trim().isEmpty ||
        (displayName != null && displayName is! String) ||
        (accountType != 'tenant_user' && accountType != 'platform_admin') ||
        (status != 'active' && status != 'disabled')) {
      throw const FormatException('The root user is invalid.');
    }
    return PlatformGlobalUserRecord._(
      uid: uid,
      email: email.trim(),
      displayName: displayName is String && displayName.trim().isNotEmpty
          ? displayName.trim()
          : null,
      accountType: accountType == 'platform_admin'
          ? RootAccountType.platformAdmin
          : RootAccountType.tenantUser,
      status: status == 'active'
          ? PlatformGlobalStatus.active
          : PlatformGlobalStatus.disabled,
      updatedAt: _decodeGlobalUserTimestamp(document.data['updatedAt']),
    );
  }

  final String uid;
  final String email;
  final String? displayName;
  final RootAccountType accountType;
  final PlatformGlobalStatus status;
  final DateTime updatedAt;
}

enum PlatformAdministrativeImpact {
  none,
  ownerUnavailable,
  noActiveAdministrator,
}

final class PlatformAffectedTenantSummary {
  const PlatformAffectedTenantSummary._({
    required this.tenantId,
    required this.name,
    required this.slug,
    required this.status,
    required this.targetRole,
    required this.targetStaffStatus,
    required this.remainingActiveAdministrators,
    required this.impact,
  });

  final String tenantId;
  final String name;
  final String slug;
  final TenantStatus status;
  final TenantRole? targetRole;
  final MembershipStatus? targetStaffStatus;
  final int remainingActiveAdministrators;
  final PlatformAdministrativeImpact impact;
}

final class PlatformGlobalUserLookupResult {
  const PlatformGlobalUserLookupResult({
    required this.user,
    required this.affectedTenants,
  });

  final PlatformGlobalUserRecord user;
  final List<PlatformAffectedTenantSummary> affectedTenants;

  List<PlatformAffectedTenantSummary> get administrativeWarnings =>
      affectedTenants
          .where((tenant) => tenant.impact != PlatformAdministrativeImpact.none)
          .toList(growable: false);
}

final class PlatformGlobalUserLookup {
  PlatformGlobalUserLookup({
    required PlatformReviewIdentity identity,
    required PlatformGlobalUserDataSource dataSource,
  }) : _identity = identity,
       _dataSource = dataSource;

  final PlatformReviewIdentity _identity;
  final PlatformGlobalUserDataSource _dataSource;

  Future<PlatformGlobalUserLookupResult?> load(String rawUid) async {
    if (!_identity.canReview) {
      throw StateError('Platform user-status access is required.');
    }
    late final String uid;
    try {
      uid = validateTenantDocumentId(rawUid.trim(), fieldName: 'uid');
    } on ArgumentError {
      throw ArgumentError.value(rawUid, 'uid', 'Enter one exact valid UID.');
    }
    await _dataSource.prepareExactReview(uid);
    final rootDocument = await _dataSource.loadRootUser(uid);
    if (rootDocument == null) return null;
    final user = PlatformGlobalUserRecord.fromDocument(rootDocument);
    if (user.uid != uid) {
      throw const FormatException('The root user lookup returned another UID.');
    }

    final sources = await Future.wait<Object>([
      _dataSource.loadTargetStaffDocuments(uid),
      _dataSource.loadOwnedTenantDocuments(uid),
    ]);
    final staffDocuments = sources[0] as List<PlatformCanonicalStaffDocument>;
    final ownedDocuments = sources[1] as List<PlatformTenantDocument>;
    final targetStaff = <String, PlatformCanonicalStaffDocument>{};
    for (final staff in staffDocuments) {
      final decoded = _decodeTargetStaff(staff, uid);
      if (targetStaff.containsKey(decoded.tenantId)) {
        throw const FormatException('Duplicate canonical staff membership.');
      }
      targetStaff[decoded.tenantId] = staff;
    }
    final tenants = <String, PlatformTenantDocument>{};
    for (final tenant in ownedDocuments) {
      final tenantId = _validatedTenantDocumentId(tenant.id);
      if (tenant.data['ownerUid'] != uid || tenants.containsKey(tenantId)) {
        throw const FormatException('The owner tenant lookup is invalid.');
      }
      tenants[tenantId] = tenant;
    }
    for (final tenantId in targetStaff.keys) {
      final tenant =
          tenants[tenantId] ?? await _dataSource.loadTenant(tenantId);
      if (tenant == null) {
        throw const FormatException('A canonical staff tenant is missing.');
      }
      tenants[tenantId] = tenant;
    }

    final summaries = await Future.wait(
      tenants.entries.map(
        (entry) => _summarizeTenant(
          tenant: entry.value,
          targetUid: uid,
          targetStaffDocument: targetStaff[entry.key],
        ),
      ),
    );
    summaries.sort((a, b) => a.tenantId.compareTo(b.tenantId));
    return PlatformGlobalUserLookupResult(
      user: user,
      affectedTenants: List.unmodifiable(summaries),
    );
  }

  Future<PlatformAffectedTenantSummary> _summarizeTenant({
    required PlatformTenantDocument tenant,
    required String targetUid,
    required PlatformCanonicalStaffDocument? targetStaffDocument,
  }) async {
    final tenantId = _validatedTenantDocumentId(tenant.id);
    final nameValue = tenant.data['name'];
    final slugValue = tenant.data['slug'];
    final ownerValue = tenant.data['ownerUid'];
    if (nameValue is! String || slugValue is! String || ownerValue is! String) {
      throw const FormatException('An affected canonical tenant is invalid.');
    }
    late final String name;
    late final String slug;
    late final String ownerUid;
    late final TenantStatus status;
    try {
      name = normalizeTenantRequestName(nameValue);
      slug = normalizeTenantRequestSlug(slugValue);
      ownerUid = validateTenantDocumentId(ownerValue, fieldName: 'ownerUid');
      status = TenantStatus.fromWire(tenant.data['status']);
    } on (ArgumentError, FormatException) {
      throw const FormatException('An affected canonical tenant is invalid.');
    }
    final targetStaff = targetStaffDocument == null
        ? null
        : _decodeTargetStaff(targetStaffDocument, targetUid);
    if (targetStaff != null && targetStaff.tenantId != tenantId) {
      throw const FormatException('Canonical staff belongs to another tenant.');
    }
    if (ownerUid == targetUid &&
        (targetStaff == null || targetStaff.role != TenantRole.owner)) {
      throw const FormatException('The canonical owner membership is invalid.');
    }

    final administrativeStaff = await _dataSource
        .loadAdministrativeStaffDocuments(tenantId);
    var remainingActiveAdministrators = 0;
    final seen = <String>{};
    for (final staff in administrativeStaff) {
      final principal = _decodeAdministrativeStaff(staff, tenantId);
      if (!seen.add(principal.uid)) {
        throw const FormatException('Duplicate administrative membership.');
      }
      if (principal.uid == targetUid || !principal.isActive) continue;
      final root = await _dataSource.loadRootUser(principal.uid);
      if (root == null) continue;
      final record = PlatformGlobalUserRecord.fromDocument(root);
      if (record.uid == principal.uid &&
          record.status == PlatformGlobalStatus.active &&
          record.accountType == RootAccountType.tenantUser) {
        remainingActiveAdministrators++;
      }
    }
    final targetIsActiveAdministrator =
        targetStaff?.status == MembershipStatus.active &&
        (targetStaff?.role == TenantRole.owner ||
            targetStaff?.role == TenantRole.admin);
    final impact = status == TenantStatus.archived
        ? PlatformAdministrativeImpact.none
        : ownerUid == targetUid
        ? PlatformAdministrativeImpact.ownerUnavailable
        : targetIsActiveAdministrator && remainingActiveAdministrators == 0
        ? PlatformAdministrativeImpact.noActiveAdministrator
        : PlatformAdministrativeImpact.none;
    return PlatformAffectedTenantSummary._(
      tenantId: tenantId,
      name: name,
      slug: slug,
      status: status,
      targetRole: targetStaff?.role,
      targetStaffStatus: targetStaff?.status,
      remainingActiveAdministrators: remainingActiveAdministrators,
      impact: impact,
    );
  }
}

abstract interface class SetGlobalUserStatusCallable {
  Future<Object?> call(Map<String, Object?> payload);
}

final class PlatformGlobalUserStatusCallableException implements Exception {
  const PlatformGlobalUserStatusCallableException(this.code);

  final String code;
}

final class FirebaseSetGlobalUserStatusCallable
    implements SetGlobalUserStatusCallable {
  FirebaseSetGlobalUserStatusCallable({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    try {
      final result = await _functions
          .httpsCallable('setGlobalUserStatus')
          .call<Object?>(payload);
      return result.data;
    } on FirebaseFunctionsException catch (error) {
      throw PlatformGlobalUserStatusCallableException(error.code);
    }
  }
}

final class PlatformGlobalUserStatusIntent {
  const PlatformGlobalUserStatusIntent._({
    required this.actorUid,
    required this.targetUid,
    required this.recordStatus,
    required this.recordUpdatedAt,
    required this.action,
    required this.reason,
    required this.confirmation,
    required this.requestId,
  });

  final String actorUid;
  final String targetUid;
  final PlatformGlobalStatus recordStatus;
  final DateTime recordUpdatedAt;
  final PlatformGlobalUserAction action;
  final String reason;
  final String? confirmation;
  final String requestId;
}

enum PlatformGlobalOperationStatus { completed, partiallyFailed }

final class PlatformGlobalUserStatusResult {
  const PlatformGlobalUserStatusResult._({
    required this.operationId,
    required this.uid,
    required this.status,
    required this.targetStatus,
    required this.affectedTenantIds,
    required this.attemptCount,
    required this.lastErrorCode,
  });

  factory PlatformGlobalUserStatusResult.fromCallable(
    Object? value, {
    required PlatformGlobalUserStatusIntent intent,
  }) {
    const requiredKeys = {
      'operationId',
      'uid',
      'status',
      'targetStatus',
      'affectedTenantIds',
      'attemptCount',
    };
    const optionalKeys = {'lastErrorCode'};
    if (value is! Map ||
        value.length < requiredKeys.length ||
        value.length > requiredKeys.length + optionalKeys.length) {
      throw const FormatException(
        'setGlobalUserStatus response must contain the expected fields.',
      );
    }
    final data = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String ||
          (!requiredKeys.contains(entry.key) &&
              !optionalKeys.contains(entry.key))) {
        throw const FormatException(
          'setGlobalUserStatus response must contain the expected fields.',
        );
      }
      data[entry.key! as String] = entry.value;
    }
    if (!data.keys.toSet().containsAll(requiredKeys) ||
        data['operationId'] is! String ||
        data['uid'] is! String ||
        data['targetStatus'] != intent.action.targetStatus ||
        data['affectedTenantIds'] is! List ||
        data['attemptCount'] is! int ||
        (data['attemptCount']! as int) < 1) {
      throw const FormatException(
        'setGlobalUserStatus returned an invalid result.',
      );
    }
    late final String operationId;
    late final String uid;
    try {
      operationId = validateTenantDocumentId(
        data['operationId']! as String,
        fieldName: 'operationId',
      );
      uid = validateTenantDocumentId(data['uid']! as String, fieldName: 'uid');
    } on ArgumentError {
      throw const FormatException(
        'setGlobalUserStatus returned an invalid result.',
      );
    }
    if (operationId != intent.requestId || uid != intent.targetUid) {
      throw const FormatException(
        'setGlobalUserStatus returned another operation.',
      );
    }
    final status = switch (data['status']) {
      'completed' => PlatformGlobalOperationStatus.completed,
      'partially_failed' => PlatformGlobalOperationStatus.partiallyFailed,
      _ => throw const FormatException(
        'setGlobalUserStatus returned an invalid saga status.',
      ),
    };
    final rawError = data['lastErrorCode'];
    if ((status == PlatformGlobalOperationStatus.completed &&
            rawError != null) ||
        (status == PlatformGlobalOperationStatus.partiallyFailed &&
            !_isSafeErrorCode(rawError))) {
      throw const FormatException(
        'setGlobalUserStatus returned an invalid error state.',
      );
    }
    final affected = <String>[];
    for (final value in data['affectedTenantIds']! as List) {
      if (value is! String) {
        throw const FormatException('Affected tenant IDs are invalid.');
      }
      late final String tenantId;
      try {
        tenantId = validateTenantId(value);
      } on ArgumentError {
        throw const FormatException('Affected tenant IDs are invalid.');
      }
      if (affected.contains(tenantId)) {
        throw const FormatException('Affected tenant IDs are invalid.');
      }
      affected.add(tenantId);
    }
    final sorted = [...affected]..sort();
    if (!_sameStrings(affected, sorted)) {
      throw const FormatException('Affected tenant IDs are invalid.');
    }
    return PlatformGlobalUserStatusResult._(
      operationId: operationId,
      uid: uid,
      status: status,
      targetStatus: intent.action == PlatformGlobalUserAction.disable
          ? PlatformGlobalStatus.disabled
          : PlatformGlobalStatus.active,
      affectedTenantIds: List.unmodifiable(affected),
      attemptCount: data['attemptCount']! as int,
      lastErrorCode: rawError as String?,
    );
  }

  final String operationId;
  final String uid;
  final PlatformGlobalOperationStatus status;
  final PlatformGlobalStatus targetStatus;
  final List<String> affectedTenantIds;
  final int attemptCount;
  final String? lastErrorCode;

  bool get isCompleted => status == PlatformGlobalOperationStatus.completed;
}

final class PlatformGlobalUserStatusGateway {
  PlatformGlobalUserStatusGateway({
    required PlatformReviewIdentity identity,
    required PlatformGlobalUserLookupResult target,
    required SetGlobalUserStatusCallable callable,
    PlatformTenantReviewRequestIdFactory? requestIdFactory,
  }) : _identity = identity,
       _target = target,
       _callable = callable,
       _requestIdFactory = requestIdFactory;

  final PlatformReviewIdentity _identity;
  final PlatformGlobalUserLookupResult _target;
  final SetGlobalUserStatusCallable _callable;
  final PlatformTenantReviewRequestIdFactory? _requestIdFactory;

  PlatformGlobalUserStatusIntent createIntent({
    required PlatformGlobalUserAction action,
    required String reason,
    String? confirmation,
  }) {
    if (!_identity.canReview) {
      throw StateError('Platform user-status access is required.');
    }
    final expectedStatus = action == PlatformGlobalUserAction.disable
        ? PlatformGlobalStatus.active
        : PlatformGlobalStatus.disabled;
    if (_target.user.status != expectedStatus) {
      throw StateError('This global user transition is not supported.');
    }
    final normalizedReason = normalizeGlobalUserStatusReason(reason);
    final normalizedConfirmation = confirmation?.trim();
    if (action == PlatformGlobalUserAction.disable &&
        normalizedConfirmation != _target.user.uid) {
      throw ArgumentError.value(
        confirmation,
        'confirmation',
        'Must exactly match the canonical UID.',
      );
    }
    final requestId = (_requestIdFactory ?? securePlatformReviewRequestId)();
    if (!platformReviewRequestIdPattern.hasMatch(requestId)) {
      throw StateError('The platform status request ID generator is invalid.');
    }
    return PlatformGlobalUserStatusIntent._(
      actorUid: _identity.uid,
      targetUid: _target.user.uid,
      recordStatus: _target.user.status,
      recordUpdatedAt: _target.user.updatedAt,
      action: action,
      reason: normalizedReason,
      confirmation: action == PlatformGlobalUserAction.disable
          ? normalizedConfirmation
          : null,
      requestId: requestId,
    );
  }

  Future<PlatformGlobalUserStatusResult> submit(
    PlatformGlobalUserStatusIntent intent,
  ) async {
    if (!_identity.canReview ||
        intent.actorUid != _identity.uid ||
        intent.targetUid != _target.user.uid ||
        intent.recordStatus != _target.user.status ||
        intent.recordUpdatedAt != _target.user.updatedAt ||
        (intent.action == PlatformGlobalUserAction.disable &&
            intent.confirmation != _target.user.uid)) {
      throw StateError('The platform user-status intent belongs elsewhere.');
    }
    final response = await _callable.call(<String, Object?>{
      'uid': _target.user.uid,
      'status': intent.action.targetStatus,
      'reason': intent.reason,
      'requestId': intent.requestId,
    });
    return PlatformGlobalUserStatusResult.fromCallable(
      response,
      intent: intent,
    );
  }
}

final class PlatformGlobalUserStatusForm extends StatefulWidget {
  const PlatformGlobalUserStatusForm({
    super.key,
    required this.identity,
    required this.target,
    required this.action,
    required this.callable,
    required this.onCompleted,
    required this.onCancel,
    this.requestIdFactory,
    this.isCurrent,
  });

  final PlatformReviewIdentity identity;
  final PlatformGlobalUserLookupResult target;
  final PlatformGlobalUserAction action;
  final SetGlobalUserStatusCallable callable;
  final ValueChanged<PlatformGlobalUserStatusResult> onCompleted;
  final VoidCallback onCancel;
  final PlatformTenantReviewRequestIdFactory? requestIdFactory;
  final PlatformTenantReviewCurrentCheck? isCurrent;

  @override
  State<PlatformGlobalUserStatusForm> createState() =>
      _PlatformGlobalUserStatusFormState();
}

final class _PlatformGlobalUserStatusFormState
    extends State<PlatformGlobalUserStatusForm> {
  final TextEditingController _reason = TextEditingController();
  final TextEditingController _confirmation = TextEditingController();
  PlatformGlobalUserStatusIntent? _intent;
  bool _submitting = false;
  String? _safeError;

  @override
  void didUpdateWidget(covariant PlatformGlobalUserStatusForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity.uid != widget.identity.uid ||
        oldWidget.identity.canReview != widget.identity.canReview ||
        oldWidget.target.user.uid != widget.target.user.uid ||
        oldWidget.target.user.status != widget.target.user.status ||
        oldWidget.target.user.updatedAt != widget.target.user.updatedAt ||
        oldWidget.action != widget.action) {
      _intent = null;
      _safeError = null;
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final gateway = PlatformGlobalUserStatusGateway(
      identity: widget.identity,
      target: widget.target,
      callable: widget.callable,
      requestIdFactory: widget.requestIdFactory,
    );
    late final PlatformGlobalUserStatusIntent intent;
    try {
      final normalizedReason = normalizeGlobalUserStatusReason(_reason.text);
      final normalizedConfirmation =
          widget.action == PlatformGlobalUserAction.disable
          ? _confirmation.text.trim()
          : null;
      final current = _intent;
      intent =
          current != null &&
              current.reason == normalizedReason &&
              current.confirmation == normalizedConfirmation
          ? current
          : gateway.createIntent(
              action: widget.action,
              reason: _reason.text,
              confirmation: _confirmation.text,
            );
      _intent = intent;
    } catch (_) {
      setState(
        () => _safeError = widget.action == PlatformGlobalUserAction.disable
            ? 'Enter a valid reason and the exact target UID.'
            : 'Enter a valid reason before reactivating this user.',
      );
      return;
    }
    setState(() {
      _submitting = true;
      _safeError = null;
    });
    try {
      final result = await gateway.submit(intent);
      if (!mounted || !(widget.isCurrent?.call() ?? true)) return;
      if (result.isCompleted) {
        widget.onCompleted(result);
      } else {
        setState(() {
          _submitting = false;
          _safeError = platformGlobalUserPartialFailureText;
        });
      }
    } catch (error) {
      if (!mounted || !(widget.isCurrent?.call() ?? true)) return;
      setState(() {
        _submitting = false;
        _safeError = platformGlobalUserStatusSafeError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabling = widget.action == PlatformGlobalUserAction.disable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          disabling
              ? 'Disable ${widget.target.user.uid}?'
              : 'Reactivate ${widget.target.user.uid}?',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (disabling && widget.target.administrativeWarnings.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '${widget.target.administrativeWarnings.length} business warning(s) require operator follow-up.',
            key: const ValueKey('platform-global-status-impact-warning'),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('platform-global-status-reason'),
          controller: _reason,
          enabled: !_submitting,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reason',
            border: OutlineInputBorder(),
          ),
        ),
        if (disabling) ...[
          const SizedBox(height: 12),
          Text('Type ${widget.target.user.uid} to confirm.'),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('platform-global-status-confirmation'),
            controller: _confirmation,
            enabled: !_submitting,
            decoration: const InputDecoration(
              labelText: 'Exact target UID',
              border: OutlineInputBorder(),
            ),
          ),
        ],
        if (_safeError != null) ...[
          const SizedBox(height: 10),
          Text(
            _safeError!,
            key: const ValueKey('platform-global-status-error'),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          alignment: WrapAlignment.end,
          children: [
            TextButton(
              key: const ValueKey('platform-global-status-cancel'),
              onPressed: _submitting ? null : widget.onCancel,
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('platform-global-status-confirm'),
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(disabling ? 'Disable user' : 'Reactivate user'),
            ),
          ],
        ),
      ],
    );
  }
}

final class PlatformGlobalUserStatusScreen extends StatefulWidget {
  const PlatformGlobalUserStatusScreen({
    super.key,
    required this.identity,
    required this.dataSource,
    required this.callable,
    required this.onCurrentOperatorAffected,
    this.requestIdFactory,
    this.isCurrent,
  });

  final PlatformReviewIdentity identity;
  final PlatformGlobalUserDataSource dataSource;
  final SetGlobalUserStatusCallable callable;
  final Future<void> Function() onCurrentOperatorAffected;
  final PlatformTenantReviewRequestIdFactory? requestIdFactory;
  final PlatformTenantReviewCurrentCheck? isCurrent;

  @override
  State<PlatformGlobalUserStatusScreen> createState() =>
      _PlatformGlobalUserStatusScreenState();
}

final class _PlatformGlobalUserStatusScreenState
    extends State<PlatformGlobalUserStatusScreen> {
  final TextEditingController _uid = TextEditingController();
  PlatformGlobalUserLookupResult? _target;
  bool _loading = false;
  bool _changing = false;
  String? _safeError;
  int _lookupEpoch = 0;

  @override
  void didUpdateWidget(covariant PlatformGlobalUserStatusScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity.uid != widget.identity.uid ||
        oldWidget.identity.canReview != widget.identity.canReview ||
        !identical(oldWidget.dataSource, widget.dataSource)) {
      ++_lookupEpoch;
      _target = null;
      _changing = false;
      _safeError = null;
    }
  }

  @override
  void dispose() {
    _uid.dispose();
    super.dispose();
  }

  Future<void> _lookup({String? exactUid}) async {
    if (_loading) return;
    final rawUid = exactUid ?? _uid.text;
    final epoch = ++_lookupEpoch;
    setState(() {
      _loading = true;
      _changing = false;
      _safeError = null;
      _target = null;
    });
    try {
      final result = await PlatformGlobalUserLookup(
        identity: widget.identity,
        dataSource: widget.dataSource,
      ).load(rawUid);
      if (!_isCurrent(epoch)) return;
      setState(() {
        _loading = false;
        _target = result;
        _safeError = result == null
            ? 'No canonical user exists for that UID.'
            : null;
      });
    } catch (_) {
      if (!_isCurrent(epoch)) return;
      setState(() {
        _loading = false;
        _safeError = 'The exact user could not be loaded.';
      });
    }
  }

  bool _isCurrent(int epoch) =>
      mounted &&
      epoch == _lookupEpoch &&
      widget.identity.canReview &&
      (widget.isCurrent?.call() ?? true);

  void _completed(PlatformGlobalUserStatusResult result, int epoch) {
    if (!_isCurrent(epoch)) return;
    if (result.uid == widget.identity.uid) {
      unawaited(widget.onCurrentOperatorAffected());
      return;
    }
    unawaited(_lookup(exactUid: result.uid));
  }

  @override
  Widget build(BuildContext context) {
    final target = _target;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Enter one exact Firebase Auth UID. General user search and bulk actions are unavailable.',
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('platform-global-user-uid'),
                controller: _uid,
                enabled: !_loading,
                decoration: const InputDecoration(
                  labelText: 'Exact UID',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _lookup(),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              key: const ValueKey('platform-global-user-lookup'),
              onPressed: _loading ? null : _lookup,
              child: _loading
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Load user'),
            ),
          ],
        ),
        if (_safeError != null) ...[
          const SizedBox(height: 16),
          Text(
            _safeError!,
            key: const ValueKey('platform-global-user-lookup-error'),
          ),
        ],
        if (target != null) ...[
          const SizedBox(height: 20),
          Card(
            key: ValueKey('platform-global-user-${target.user.uid}'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    target.user.displayName ?? target.user.uid,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(target.user.uid),
                  Text(target.user.email),
                  Text(
                    '${target.user.accountType == RootAccountType.platformAdmin ? 'platform_admin' : 'tenant_user'} - ${target.user.status.name}',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${target.affectedTenants.length} canonical tenant relationship(s)',
                  ),
                  for (final tenant in target.affectedTenants)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${tenant.name} (${tenant.slug})'),
                      subtitle: Text(_affectedTenantText(tenant)),
                      trailing:
                          tenant.impact == PlatformAdministrativeImpact.none
                          ? null
                          : const Icon(Icons.warning_amber_outlined),
                    ),
                  const SizedBox(height: 12),
                  if (!_changing)
                    Align(
                      alignment: Alignment.centerRight,
                      child: target.user.status == PlatformGlobalStatus.active
                          ? OutlinedButton(
                              key: const ValueKey(
                                'platform-disable-global-user',
                              ),
                              onPressed: () => setState(() => _changing = true),
                              child: const Text('Disable user'),
                            )
                          : FilledButton(
                              key: const ValueKey(
                                'platform-reactivate-global-user',
                              ),
                              onPressed: () => setState(() => _changing = true),
                              child: const Text('Reactivate user'),
                            ),
                    )
                  else
                    PlatformGlobalUserStatusForm(
                      identity: widget.identity,
                      target: target,
                      action: target.user.status == PlatformGlobalStatus.active
                          ? PlatformGlobalUserAction.disable
                          : PlatformGlobalUserAction.reactivate,
                      callable: widget.callable,
                      requestIdFactory: widget.requestIdFactory,
                      isCurrent: () =>
                          _isCurrent(_lookupEpoch) &&
                          identical(_target, target) &&
                          _changing,
                      onCompleted: (result) => _completed(result, _lookupEpoch),
                      onCancel: () => setState(() => _changing = false),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

String normalizeGlobalUserStatusReason(String value) {
  final reason = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (reason.length < 3 ||
      reason.length > 1000 ||
      reason.runes.any(
        (rune) => rune <= 0x1f || (rune >= 0x7f && rune <= 0x9f),
      )) {
    throw ArgumentError.value(
      value,
      'reason',
      'Must be 3 to 1000 safe characters.',
    );
  }
  return reason;
}

const platformGlobalUserPartialFailureText =
    'The status change is partially complete and will be retried safely. You may retry this same operation now.';

String platformGlobalUserStatusSafeError(Object error) {
  if (error is PlatformGlobalUserStatusCallableException) {
    return switch (error.code) {
      'failed-precondition' =>
        'This user changed or no longer satisfies status requirements.',
      'aborted' =>
        'Another status operation is already in progress for this user.',
      'not-found' => 'This canonical user no longer exists.',
      'permission-denied' =>
        'Platform user-status access is no longer available.',
      _ => 'User status could not be changed. Please try again.',
    };
  }
  return 'User status could not be changed. Please try again.';
}

String _affectedTenantText(PlatformAffectedTenantSummary tenant) {
  final membership = tenant.targetRole == null
      ? 'owner record without membership'
      : '${tenant.targetRole!.wireValue}/${tenant.targetStaffStatus!.wireValue}';
  final impact = switch (tenant.impact) {
    PlatformAdministrativeImpact.none =>
      '${tenant.remainingActiveAdministrators} other active administrator(s)',
    PlatformAdministrativeImpact.ownerUnavailable =>
      'disabling creates an owner-unavailable alert',
    PlatformAdministrativeImpact.noActiveAdministrator =>
      'disabling leaves no active administrator',
  };
  return '${tenant.status.wireValue} - $membership - $impact';
}

({String tenantId, TenantRole role, MembershipStatus status})
_decodeTargetStaff(PlatformCanonicalStaffDocument staff, String expectedUid) {
  final tenantId = _validatedTenantDocumentId(staff.tenantId);
  late final String uid;
  late final TenantRole role;
  late final MembershipStatus status;
  try {
    uid = validateTenantDocumentId(staff.id, fieldName: 'staffUid');
    role = TenantRole.fromWire(staff.data['role']);
    status = MembershipStatus.fromWire(staff.data['status']);
  } on (ArgumentError, FormatException) {
    throw const FormatException('Canonical target staff is invalid.');
  }
  if (uid != expectedUid || staff.data['uid'] != uid) {
    throw const FormatException('Canonical target staff is invalid.');
  }
  return (tenantId: tenantId, role: role, status: status);
}

({String uid, bool isActive}) _decodeAdministrativeStaff(
  PlatformCanonicalStaffDocument staff,
  String expectedTenantId,
) {
  if (_validatedTenantDocumentId(staff.tenantId) != expectedTenantId) {
    throw const FormatException('Administrative staff belongs elsewhere.');
  }
  late final String uid;
  late final TenantRole role;
  late final MembershipStatus status;
  try {
    uid = validateTenantDocumentId(staff.id, fieldName: 'staffUid');
    role = TenantRole.fromWire(staff.data['role']);
    status = MembershipStatus.fromWire(staff.data['status']);
  } on (ArgumentError, FormatException) {
    throw const FormatException('Administrative staff is invalid.');
  }
  if (staff.data['uid'] != uid ||
      (role != TenantRole.owner && role != TenantRole.admin)) {
    throw const FormatException('Administrative staff is invalid.');
  }
  return (uid: uid, isActive: status == MembershipStatus.active);
}

String _validatedTenantDocumentId(String value) {
  try {
    return validateTenantId(value);
  } on ArgumentError {
    throw const FormatException('Canonical tenant ID is invalid.');
  }
}

DateTime _decodeGlobalUserTimestamp(Object? value) {
  if (value is Timestamp) return value.toDate().toUtc();
  if (value is DateTime) return value.toUtc();
  throw const FormatException('The root user timestamp is invalid.');
}

bool _isSafeErrorCode(Object? value) =>
    value is String &&
    value.isNotEmpty &&
    value.length <= 128 &&
    !value.runes.any((rune) => rune <= 0x1f || (rune >= 0x7f && rune <= 0x9f));

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
