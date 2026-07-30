import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'tenant_bootstrap.dart';
import 'tenant_id.dart';
import 'tenant_request.dart';
import 'tenant_types.dart';

typedef PlatformTenantReviewRequestIdFactory = String Function();
typedef PlatformTenantReviewCurrentCheck = bool Function();

final class PlatformReviewIdentity {
  factory PlatformReviewIdentity({
    required String uid,
    required RootRoutingProfile profile,
    required bool hasSuperAdminClaim,
  }) => PlatformReviewIdentity._(
    uid: validateTenantDocumentId(uid.trim(), fieldName: 'uid'),
    accountType: profile.accountType,
    globallyActive: profile.isActive,
    hasSuperAdminClaim: hasSuperAdminClaim,
  );

  const PlatformReviewIdentity._({
    required this.uid,
    required this.accountType,
    required this.globallyActive,
    required this.hasSuperAdminClaim,
  });

  final String uid;
  final RootAccountType accountType;
  final bool globallyActive;
  final bool hasSuperAdminClaim;

  bool get canReview =>
      globallyActive &&
      hasSuperAdminClaim &&
      accountType == RootAccountType.platformAdmin;
}

final class PlatformPendingTenantCursor {
  const PlatformPendingTenantCursor({
    required this.createdAt,
    required this.tenantId,
  });

  final Timestamp createdAt;
  final String tenantId;
}

final class PlatformTenantDocument {
  const PlatformTenantDocument({required this.id, required this.data});

  final String id;
  final Map<String, Object?> data;
}

abstract interface class PlatformPendingTenantDataSource {
  Future<List<PlatformTenantDocument>> loadPendingTenantDocuments({
    required int limit,
    PlatformPendingTenantCursor? cursor,
  });

  Future<PlatformTenantDocument?> loadRootUser(String uid);
}

final class FirebasePlatformPendingTenantDataSource
    implements PlatformPendingTenantDataSource {
  FirebasePlatformPendingTenantDataSource({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<List<PlatformTenantDocument>> loadPendingTenantDocuments({
    required int limit,
    PlatformPendingTenantCursor? cursor,
  }) async {
    Query<Map<String, dynamic>> query = _firestore
        .collection('tenants')
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .orderBy(FieldPath.documentId)
        .limit(limit);
    if (cursor != null) {
      query = query.startAfter(<Object>[cursor.createdAt, cursor.tenantId]);
    }
    final snapshot = await query.get();
    return snapshot.docs
        .map(
          (document) =>
              PlatformTenantDocument(id: document.id, data: document.data()),
        )
        .toList(growable: false);
  }

  @override
  Future<PlatformTenantDocument?> loadRootUser(String uid) async {
    final snapshot = await _firestore.collection('users').doc(uid).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    return PlatformTenantDocument(id: snapshot.id, data: data);
  }
}

final class PlatformTenantOwnerSummary {
  const PlatformTenantOwnerSummary._({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.globallyActive,
  });

  factory PlatformTenantOwnerSummary.fromDocument(
    PlatformTenantDocument document, {
    required String expectedUid,
  }) {
    late final String uid;
    try {
      uid = validateTenantDocumentId(document.id, fieldName: 'ownerUid');
    } on ArgumentError {
      throw const FormatException('Pending tenant owner is invalid.');
    }
    final email = document.data['email'];
    final displayName = document.data['displayName'];
    final globalStatus = document.data['globalStatus'];
    if (uid != expectedUid ||
        document.data['accountType'] != 'tenant_user' ||
        (globalStatus != 'active' && globalStatus != 'disabled') ||
        email is! String ||
        email.trim().isEmpty ||
        (displayName != null && displayName is! String)) {
      throw const FormatException('Pending tenant owner is invalid.');
    }
    return PlatformTenantOwnerSummary._(
      uid: uid,
      email: email.trim(),
      displayName: displayName is String && displayName.trim().isNotEmpty
          ? displayName.trim()
          : null,
      globallyActive: globalStatus == 'active',
    );
  }

  final String uid;
  final String email;
  final String? displayName;
  final bool globallyActive;
}

final class PlatformPendingTenant {
  const PlatformPendingTenant._({
    required this.tenantId,
    required this.name,
    required this.slug,
    required this.owner,
    required this.createdAt,
    required this.createdAtCursor,
  });

  factory PlatformPendingTenant.fromDocuments({
    required PlatformTenantDocument tenant,
    required PlatformTenantDocument owner,
  }) {
    late final String tenantId;
    late final String name;
    late final String slug;
    late final String ownerUid;
    try {
      tenantId = validateTenantId(tenant.id);
      if (tenant.data['name'] is! String ||
          tenant.data['slug'] is! String ||
          tenant.data['ownerUid'] is! String) {
        throw const FormatException('Pending tenant fields are invalid.');
      }
      name = normalizeTenantRequestName(tenant.data['name']! as String);
      slug = normalizeTenantRequestSlug(tenant.data['slug']! as String);
      ownerUid = validateTenantDocumentId(
        tenant.data['ownerUid']! as String,
        fieldName: 'ownerUid',
      );
    } on ArgumentError {
      throw const FormatException('Pending tenant fields are invalid.');
    }
    if (tenant.data['status'] != 'pending') {
      throw const FormatException(
        'Tenant queue returned a non-pending record.',
      );
    }
    final createdAtCursor = _decodeTimestamp(tenant.data['createdAt']);
    return PlatformPendingTenant._(
      tenantId: tenantId,
      name: name,
      slug: slug,
      owner: PlatformTenantOwnerSummary.fromDocument(
        owner,
        expectedUid: ownerUid,
      ),
      createdAt: createdAtCursor.toDate().toUtc(),
      createdAtCursor: createdAtCursor,
    );
  }

  final String tenantId;
  final String name;
  final String slug;
  final PlatformTenantOwnerSummary owner;
  final DateTime createdAt;
  final Timestamp createdAtCursor;

  PlatformPendingTenantCursor get cursor => PlatformPendingTenantCursor(
    createdAt: createdAtCursor,
    tenantId: tenantId,
  );
}

final class PlatformPendingTenantPage {
  const PlatformPendingTenantPage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<PlatformPendingTenant> items;
  final PlatformPendingTenantCursor? nextCursor;
  final bool hasMore;
}

final class PlatformPendingTenantQueue {
  PlatformPendingTenantQueue({
    required PlatformReviewIdentity identity,
    required PlatformPendingTenantDataSource dataSource,
  }) : _identity = identity,
       _dataSource = dataSource;

  final PlatformReviewIdentity _identity;
  final PlatformPendingTenantDataSource _dataSource;

  Future<PlatformPendingTenantPage> load({
    int pageSize = 20,
    PlatformPendingTenantCursor? cursor,
  }) async {
    if (!_identity.canReview) {
      throw StateError('Platform review access is required.');
    }
    if (pageSize < 1 || pageSize > 50) {
      throw RangeError.range(pageSize, 1, 50, 'pageSize');
    }
    final documents = await _dataSource.loadPendingTenantDocuments(
      limit: pageSize + 1,
      cursor: cursor,
    );
    final hasMore = documents.length > pageSize;
    final selected = documents.take(pageSize).toList(growable: false);
    final items = await Future.wait(
      selected.map((tenant) async {
        final rawOwnerUid = tenant.data['ownerUid'];
        if (rawOwnerUid is! String) {
          throw const FormatException('Pending tenant owner is missing.');
        }
        late final String ownerUid;
        try {
          ownerUid = validateTenantDocumentId(
            rawOwnerUid,
            fieldName: 'ownerUid',
          );
        } on ArgumentError {
          throw const FormatException('Pending tenant owner is invalid.');
        }
        final owner = await _dataSource.loadRootUser(ownerUid);
        if (owner == null) {
          throw const FormatException('Pending tenant owner is missing.');
        }
        return PlatformPendingTenant.fromDocuments(
          tenant: tenant,
          owner: owner,
        );
      }),
    );
    return PlatformPendingTenantPage(
      items: List<PlatformPendingTenant>.unmodifiable(items),
      nextCursor: hasMore && items.isNotEmpty ? items.last.cursor : null,
      hasMore: hasMore,
    );
  }
}

enum PlatformTenantReviewAction {
  approve('active'),
  reject('rejected');

  const PlatformTenantReviewAction(this.targetStatus);

  final String targetStatus;
}

abstract interface class SetTenantLifecycleCallable {
  Future<Object?> call(Map<String, Object?> payload);
}

final class PlatformTenantReviewCallableException implements Exception {
  const PlatformTenantReviewCallableException(this.code);

  final String code;
}

final class FirebaseSetTenantLifecycleCallable
    implements SetTenantLifecycleCallable {
  FirebaseSetTenantLifecycleCallable({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    try {
      final result = await _functions
          .httpsCallable('setTenantLifecycle')
          .call<Object?>(payload);
      return result.data;
    } on FirebaseFunctionsException catch (error) {
      throw PlatformTenantReviewCallableException(error.code);
    }
  }
}

final class PlatformTenantReviewIntent {
  const PlatformTenantReviewIntent._({
    required this.actorUid,
    required this.tenantId,
    required this.recordCreatedAt,
    required this.action,
    required this.reason,
    required this.requestId,
  });

  final String actorUid;
  final String tenantId;
  final DateTime recordCreatedAt;
  final PlatformTenantReviewAction action;
  final String? reason;
  final String requestId;
}

final class PlatformTenantReviewResult {
  const PlatformTenantReviewResult._({
    required this.tenantId,
    required this.previousStatus,
    required this.status,
    required this.fanoutOperationId,
  });

  factory PlatformTenantReviewResult.fromCallable(
    Object? value, {
    required PlatformTenantReviewIntent intent,
  }) {
    const keys = {'tenantId', 'previousStatus', 'status', 'fanoutOperationId'};
    if (value is! Map || value.length != keys.length) {
      throw const FormatException(
        'setTenantLifecycle response must contain the expected fields.',
      );
    }
    final data = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String || !keys.contains(entry.key)) {
        throw const FormatException(
          'setTenantLifecycle response must contain the expected fields.',
        );
      }
      data[entry.key! as String] = entry.value;
    }
    if (data['tenantId'] is! String ||
        data['fanoutOperationId'] is! String ||
        data['previousStatus'] != 'pending' ||
        data['status'] != intent.action.targetStatus) {
      throw const FormatException(
        'setTenantLifecycle returned an invalid result.',
      );
    }
    late final String tenantId;
    late final String fanoutOperationId;
    try {
      tenantId = validateTenantId(data['tenantId']! as String);
      fanoutOperationId = validateTenantDocumentId(
        data['fanoutOperationId']! as String,
        fieldName: 'fanoutOperationId',
      );
    } on ArgumentError {
      throw const FormatException(
        'setTenantLifecycle returned an invalid result.',
      );
    }
    if (tenantId != intent.tenantId) {
      throw const FormatException(
        'setTenantLifecycle returned another tenant.',
      );
    }
    return PlatformTenantReviewResult._(
      tenantId: tenantId,
      previousStatus: TenantStatus.pending,
      status: TenantStatus.fromWire(data['status']),
      fanoutOperationId: fanoutOperationId,
    );
  }

  final String tenantId;
  final TenantStatus previousStatus;
  final TenantStatus status;
  final String fanoutOperationId;
}

final class PlatformTenantReviewGateway {
  PlatformTenantReviewGateway({
    required PlatformReviewIdentity identity,
    required PlatformPendingTenant tenant,
    required SetTenantLifecycleCallable callable,
    PlatformTenantReviewRequestIdFactory? requestIdFactory,
  }) : _identity = identity,
       _tenant = tenant,
       _callable = callable,
       _requestIdFactory = requestIdFactory ?? securePlatformReviewRequestId;

  final PlatformReviewIdentity _identity;
  final PlatformPendingTenant _tenant;
  final SetTenantLifecycleCallable _callable;
  final PlatformTenantReviewRequestIdFactory _requestIdFactory;

  PlatformTenantReviewIntent createIntent({
    required PlatformTenantReviewAction action,
    String? reason,
  }) {
    if (!_identity.canReview) {
      throw StateError('Platform review access is required.');
    }
    final normalizedReason = action == PlatformTenantReviewAction.reject
        ? normalizeTenantRejectionReason(reason ?? '')
        : null;
    final requestId = _requestIdFactory();
    if (!platformReviewRequestIdPattern.hasMatch(requestId)) {
      throw StateError('The platform review request ID generator is invalid.');
    }
    return PlatformTenantReviewIntent._(
      actorUid: _identity.uid,
      tenantId: _tenant.tenantId,
      recordCreatedAt: _tenant.createdAt,
      action: action,
      reason: normalizedReason,
      requestId: requestId,
    );
  }

  Future<PlatformTenantReviewResult> submit(
    PlatformTenantReviewIntent intent,
  ) async {
    if (!_identity.canReview ||
        intent.actorUid != _identity.uid ||
        intent.tenantId != _tenant.tenantId ||
        intent.recordCreatedAt != _tenant.createdAt) {
      throw StateError('The platform review intent belongs elsewhere.');
    }
    final response = await _callable.call(<String, Object?>{
      'tenantId': _tenant.tenantId,
      'status': intent.action.targetStatus,
      if (intent.reason != null) 'reason': intent.reason,
      'requestId': intent.requestId,
    });
    return PlatformTenantReviewResult.fromCallable(response, intent: intent);
  }
}

final class PlatformTenantReviewForm extends StatefulWidget {
  const PlatformTenantReviewForm({
    super.key,
    required this.identity,
    required this.tenant,
    required this.action,
    required this.callable,
    required this.onSuccess,
    required this.onCancel,
    this.requestIdFactory,
    this.isCurrent,
  });

  final PlatformReviewIdentity identity;
  final PlatformPendingTenant tenant;
  final PlatformTenantReviewAction action;
  final SetTenantLifecycleCallable callable;
  final ValueChanged<PlatformTenantReviewResult> onSuccess;
  final VoidCallback onCancel;
  final PlatformTenantReviewRequestIdFactory? requestIdFactory;
  final PlatformTenantReviewCurrentCheck? isCurrent;

  @override
  State<PlatformTenantReviewForm> createState() =>
      _PlatformTenantReviewFormState();
}

final class _PlatformTenantReviewFormState
    extends State<PlatformTenantReviewForm> {
  final _reasonController = TextEditingController();
  PlatformTenantReviewIntent? _intent;
  bool _submitting = false;
  String? _safeError;

  @override
  void didUpdateWidget(covariant PlatformTenantReviewForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity.uid == widget.identity.uid &&
        oldWidget.tenant.tenantId == widget.tenant.tenantId &&
        oldWidget.tenant.createdAt == widget.tenant.createdAt &&
        oldWidget.action == widget.action) {
      return;
    }
    _intent = null;
    _submitting = false;
    _safeError = null;
    _reasonController.clear();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  void _reasonChanged(String _) {
    if (_intent == null && _safeError == null) return;
    setState(() {
      _intent = null;
      _safeError = null;
    });
  }

  Future<void> _submit() async {
    if (_submitting || !_isCurrent()) return;
    final identity = widget.identity;
    final tenant = widget.tenant;
    final action = widget.action;
    final gateway = _gateway();
    late final PlatformTenantReviewIntent intent;
    try {
      intent = _intent ??= gateway.createIntent(
        action: action,
        reason: _reasonController.text,
      );
    } catch (_) {
      if (!mounted || !_isStillCurrent(identity, tenant, action)) return;
      setState(
        () => _safeError = action == PlatformTenantReviewAction.reject
            ? 'Enter a rejection reason between 3 and 1000 characters.'
            : 'This tenant request cannot be approved.',
      );
      return;
    }
    setState(() {
      _submitting = true;
      _safeError = null;
    });
    late final PlatformTenantReviewResult result;
    try {
      result = await gateway.submit(intent);
    } catch (error) {
      if (!mounted ||
          !_isStillCurrent(identity, tenant, action) ||
          !identical(_intent, intent)) {
        return;
      }
      setState(() {
        _submitting = false;
        _safeError = platformTenantReviewSafeError(error, action: action);
      });
      return;
    }
    if (!mounted ||
        !_isStillCurrent(identity, tenant, action) ||
        !identical(_intent, intent)) {
      return;
    }
    setState(() => _submitting = false);
    widget.onSuccess(result);
  }

  PlatformTenantReviewGateway _gateway() => PlatformTenantReviewGateway(
    identity: widget.identity,
    tenant: widget.tenant,
    callable: widget.callable,
    requestIdFactory: widget.requestIdFactory,
  );

  bool _isStillCurrent(
    PlatformReviewIdentity identity,
    PlatformPendingTenant tenant,
    PlatformTenantReviewAction action,
  ) =>
      widget.identity.uid == identity.uid &&
      widget.tenant.tenantId == tenant.tenantId &&
      widget.tenant.createdAt == tenant.createdAt &&
      widget.action == action &&
      _isCurrent();

  bool _isCurrent() =>
      widget.identity.canReview && (widget.isCurrent?.call() ?? true);

  @override
  Widget build(BuildContext context) {
    final rejecting = widget.action == PlatformTenantReviewAction.reject;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          rejecting
              ? 'Reject ${widget.tenant.name}?'
              : 'Approve ${widget.tenant.name}?',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          rejecting
              ? 'The business will remain inaccessible to its owner.'
              : 'The owner will gain operational access after approval.',
        ),
        if (rejecting) ...[
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('platform-review-reason'),
            controller: _reasonController,
            enabled: !_submitting,
            minLines: 2,
            maxLines: 4,
            maxLength: 1000,
            onChanged: _reasonChanged,
            decoration: const InputDecoration(labelText: 'Rejection reason'),
          ),
        ],
        if (_safeError != null) ...[
          const SizedBox(height: 12),
          Text(
            _safeError!,
            key: const ValueKey('platform-review-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              key: const ValueKey('platform-review-cancel'),
              onPressed: _submitting ? null : widget.onCancel,
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              key: ValueKey(
                rejecting
                    ? 'platform-review-reject-confirm'
                    : 'platform-review-approve-confirm',
              ),
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(rejecting ? Icons.close : Icons.check),
              label: Text(
                _submitting
                    ? 'Saving...'
                    : rejecting
                    ? 'Reject request'
                    : 'Approve request',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

final class PlatformPendingTenantReviewScreen extends StatefulWidget {
  const PlatformPendingTenantReviewScreen({
    super.key,
    required this.identity,
    required this.dataSource,
    required this.callable,
    required this.onSignOut,
    this.requestIdFactory,
    this.isCurrent,
    this.pageSize = 20,
    this.embedded = false,
  });

  final PlatformReviewIdentity identity;
  final PlatformPendingTenantDataSource dataSource;
  final SetTenantLifecycleCallable callable;
  final Future<void> Function() onSignOut;
  final PlatformTenantReviewRequestIdFactory? requestIdFactory;
  final PlatformTenantReviewCurrentCheck? isCurrent;
  final int pageSize;
  final bool embedded;

  @override
  State<PlatformPendingTenantReviewScreen> createState() =>
      _PlatformPendingTenantReviewScreenState();
}

final class _PlatformPendingTenantReviewScreenState
    extends State<PlatformPendingTenantReviewScreen> {
  final List<PlatformPendingTenant> _items = [];
  PlatformPendingTenantCursor? _cursor;
  bool _hasMore = false;
  bool _loading = false;
  String? _safeError;
  int _queueEpoch = 0;
  String? _reviewingTenantId;
  PlatformTenantReviewAction? _reviewAction;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant PlatformPendingTenantReviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity.uid != widget.identity.uid ||
        oldWidget.identity.canReview != widget.identity.canReview ||
        !identical(oldWidget.dataSource, widget.dataSource)) {
      _reload();
    }
  }

  Future<void> _reload() async {
    final epoch = ++_queueEpoch;
    setState(() {
      _items.clear();
      _cursor = null;
      _hasMore = false;
      _loading = true;
      _safeError = null;
      _reviewingTenantId = null;
      _reviewAction = null;
    });
    await _loadPage(epoch, replace: true);
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    final epoch = _queueEpoch;
    setState(() {
      _loading = true;
      _safeError = null;
    });
    await _loadPage(epoch, replace: false);
  }

  Future<void> _loadPage(int epoch, {required bool replace}) async {
    if (!_isCurrent(epoch)) return;
    try {
      final page = await PlatformPendingTenantQueue(
        identity: widget.identity,
        dataSource: widget.dataSource,
      ).load(pageSize: widget.pageSize, cursor: replace ? null : _cursor);
      if (!mounted || !_isCurrent(epoch)) return;
      setState(() {
        if (replace) _items.clear();
        _items.addAll(page.items);
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || !_isCurrent(epoch)) return;
      setState(() {
        _loading = false;
        _safeError = 'Pending business requests could not be loaded.';
      });
    }
  }

  bool _isCurrent(int epoch) =>
      mounted &&
      epoch == _queueEpoch &&
      widget.identity.canReview &&
      (widget.isCurrent?.call() ?? true);

  void _review(
    PlatformPendingTenant tenant,
    PlatformTenantReviewAction action,
  ) {
    if (_loading) return;
    setState(() {
      _reviewingTenantId = tenant.tenantId;
      _reviewAction = action;
    });
  }

  void _reviewed(PlatformTenantReviewResult _) {
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return _buildBody(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending business reviews'),
        actions: [
          IconButton(
            key: const ValueKey('platform-review-refresh'),
            tooltip: 'Refresh pending requests',
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
          TextButton(
            onPressed: widget.onSignOut,
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_safeError != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_safeError!, key: const ValueKey('platform-queue-error')),
            const SizedBox(height: 12),
            FilledButton(onPressed: _reload, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(child: Text('No pending business requests.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: _items.length + (_hasMore || _loading ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == _items.length) {
          return Center(
            child: _loading
                ? const CircularProgressIndicator()
                : OutlinedButton(
                    key: const ValueKey('platform-review-load-more'),
                    onPressed: _loadMore,
                    child: const Text('Load more'),
                  ),
          );
        }
        final tenant = _items[index];
        final reviewing = _reviewingTenantId == tenant.tenantId;
        final epoch = _queueEpoch;
        return Card(
          key: ValueKey('platform-tenant-${tenant.tenantId}'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tenant.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '${tenant.slug} - ${tenant.owner.displayName ?? tenant.owner.uid}',
                ),
                Text(tenant.owner.email),
                if (!tenant.owner.globallyActive)
                  const Text('Owner account disabled'),
                const SizedBox(height: 12),
                if (!reviewing)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        key: ValueKey('platform-reject-${tenant.tenantId}'),
                        onPressed: () =>
                            _review(tenant, PlatformTenantReviewAction.reject),
                        child: const Text('Reject'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        key: ValueKey('platform-approve-${tenant.tenantId}'),
                        onPressed: () =>
                            _review(tenant, PlatformTenantReviewAction.approve),
                        child: const Text('Approve'),
                      ),
                    ],
                  )
                else
                  PlatformTenantReviewForm(
                    identity: widget.identity,
                    tenant: tenant,
                    action: _reviewAction!,
                    callable: widget.callable,
                    requestIdFactory: widget.requestIdFactory,
                    isCurrent: () =>
                        _isCurrent(epoch) &&
                        _reviewingTenantId == tenant.tenantId,
                    onSuccess: _reviewed,
                    onCancel: () => setState(() {
                      _reviewingTenantId = null;
                      _reviewAction = null;
                    }),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

String normalizeTenantRejectionReason(String value) {
  final reason = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (reason.length < 3 || reason.length > 1000 || _hasControl(reason)) {
    throw ArgumentError.value(
      value,
      'reason',
      'Must be 3 to 1000 safe characters.',
    );
  }
  return reason;
}

String platformTenantReviewSafeError(
  Object error, {
  required PlatformTenantReviewAction action,
}) {
  if (error is PlatformTenantReviewCallableException) {
    return switch (error.code) {
      'resource-exhausted' =>
        'The owner has reached the active business limit.',
      'failed-precondition' =>
        'This request changed or no longer satisfies review requirements.',
      'not-found' => 'This business request no longer exists.',
      'permission-denied' => 'Platform review access is no longer available.',
      _ =>
        action == PlatformTenantReviewAction.approve
            ? 'Business request could not be approved. Please try again.'
            : 'Business request could not be rejected. Please try again.',
    };
  }
  return action == PlatformTenantReviewAction.approve
      ? 'Business request could not be approved. Please try again.'
      : 'Business request could not be rejected. Please try again.';
}

Timestamp _decodeTimestamp(Object? value) {
  if (value is Timestamp) return value;
  if (value is DateTime) return Timestamp.fromDate(value.toUtc());
  throw const FormatException('Pending tenant timestamp is invalid.');
}

bool _hasControl(String value) =>
    value.runes.any((rune) => rune <= 0x1f || (rune >= 0x7f && rune <= 0x9f));

String securePlatformReviewRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'review-${base64Url.encode(bytes).replaceAll('=', '')}';
}

final platformReviewRequestIdPattern = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$',
);
