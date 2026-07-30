import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'platform_tenant_review.dart';
import 'tenant_id.dart';
import 'tenant_request.dart';
import 'tenant_types.dart';

final class PlatformRejectedTenantCursor {
  const PlatformRejectedTenantCursor({
    required this.updatedAt,
    required this.tenantId,
  });

  final Timestamp updatedAt;
  final String tenantId;
}

abstract interface class PlatformRejectedTenantDataSource {
  Future<List<PlatformTenantDocument>> loadRejectedTenantDocuments({
    required int limit,
    PlatformRejectedTenantCursor? cursor,
  });

  Future<PlatformTenantDocument?> loadRootUser(String uid);
}

final class FirebasePlatformRejectedTenantDataSource
    implements PlatformRejectedTenantDataSource {
  FirebasePlatformRejectedTenantDataSource({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<List<PlatformTenantDocument>> loadRejectedTenantDocuments({
    required int limit,
    PlatformRejectedTenantCursor? cursor,
  }) async {
    Query<Map<String, dynamic>> query = _firestore
        .collection('tenants')
        .where('status', isEqualTo: 'rejected')
        .orderBy('updatedAt', descending: true)
        .orderBy(FieldPath.documentId)
        .limit(limit);
    if (cursor != null) {
      query = query.startAfter(<Object>[cursor.updatedAt, cursor.tenantId]);
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

final class PlatformRejectedTenant {
  const PlatformRejectedTenant._({
    required this.tenantId,
    required this.name,
    required this.slug,
    required this.owner,
    required this.status,
    required this.updatedAt,
    required this.updatedAtCursor,
  });

  factory PlatformRejectedTenant.fromDocuments({
    required PlatformTenantDocument tenant,
    required PlatformTenantDocument owner,
  }) {
    late final String tenantId;
    late final String name;
    late final String slug;
    late final String ownerUid;
    late final TenantStatus status;
    try {
      tenantId = validateTenantId(tenant.id);
      if (tenant.data['name'] is! String ||
          tenant.data['slug'] is! String ||
          tenant.data['ownerUid'] is! String ||
          tenant.data['status'] is! String) {
        throw const FormatException('Rejected tenant fields are invalid.');
      }
      name = normalizeTenantRequestName(tenant.data['name']! as String);
      slug = normalizeTenantRequestSlug(tenant.data['slug']! as String);
      ownerUid = validateTenantDocumentId(
        tenant.data['ownerUid']! as String,
        fieldName: 'ownerUid',
      );
      status = TenantStatus.fromWire(tenant.data['status']);
    } on (ArgumentError, FormatException) {
      throw const FormatException('Rejected tenant fields are invalid.');
    }
    if (status != TenantStatus.rejected) {
      throw const FormatException(
        'Archive queue returned an unsupported tenant status.',
      );
    }
    final updatedAtCursor = _decodeRejectedTimestamp(tenant.data['updatedAt']);
    return PlatformRejectedTenant._(
      tenantId: tenantId,
      name: name,
      slug: slug,
      owner: PlatformTenantOwnerSummary.fromDocument(
        owner,
        expectedUid: ownerUid,
      ),
      status: status,
      updatedAt: updatedAtCursor.toDate().toUtc(),
      updatedAtCursor: updatedAtCursor,
    );
  }

  final String tenantId;
  final String name;
  final String slug;
  final PlatformTenantOwnerSummary owner;
  final TenantStatus status;
  final DateTime updatedAt;
  final Timestamp updatedAtCursor;

  String get archiveConfirmation => '$name ($slug)';

  PlatformRejectedTenantCursor get cursor => PlatformRejectedTenantCursor(
    updatedAt: updatedAtCursor,
    tenantId: tenantId,
  );
}

final class PlatformRejectedTenantPage {
  const PlatformRejectedTenantPage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<PlatformRejectedTenant> items;
  final PlatformRejectedTenantCursor? nextCursor;
  final bool hasMore;
}

final class PlatformRejectedTenantQueue {
  PlatformRejectedTenantQueue({
    required PlatformReviewIdentity identity,
    required PlatformRejectedTenantDataSource dataSource,
  }) : _identity = identity,
       _dataSource = dataSource;

  final PlatformReviewIdentity _identity;
  final PlatformRejectedTenantDataSource _dataSource;

  Future<PlatformRejectedTenantPage> load({
    int pageSize = 20,
    PlatformRejectedTenantCursor? cursor,
  }) async {
    if (!_identity.canReview) {
      throw StateError('Platform archival access is required.');
    }
    if (pageSize < 1 || pageSize > 50) {
      throw RangeError.range(pageSize, 1, 50, 'pageSize');
    }
    final documents = await _dataSource.loadRejectedTenantDocuments(
      limit: pageSize + 1,
      cursor: cursor,
    );
    final hasMore = documents.length > pageSize;
    final selected = documents.take(pageSize).toList(growable: false);
    final items = await Future.wait(
      selected.map((tenant) async {
        final rawOwnerUid = tenant.data['ownerUid'];
        if (rawOwnerUid is! String) {
          throw const FormatException('Rejected tenant owner is missing.');
        }
        late final String ownerUid;
        try {
          ownerUid = validateTenantDocumentId(
            rawOwnerUid,
            fieldName: 'ownerUid',
          );
        } on ArgumentError {
          throw const FormatException('Rejected tenant owner is invalid.');
        }
        final owner = await _dataSource.loadRootUser(ownerUid);
        if (owner == null) {
          throw const FormatException('Rejected tenant owner is missing.');
        }
        return PlatformRejectedTenant.fromDocuments(
          tenant: tenant,
          owner: owner,
        );
      }),
    );
    return PlatformRejectedTenantPage(
      items: List<PlatformRejectedTenant>.unmodifiable(items),
      nextCursor: hasMore && items.isNotEmpty ? items.last.cursor : null,
      hasMore: hasMore,
    );
  }
}

final class PlatformTenantArchivalIntent {
  const PlatformTenantArchivalIntent._({
    required this.actorUid,
    required this.tenantId,
    required this.recordStatus,
    required this.recordUpdatedAt,
    required this.reason,
    required this.confirmation,
    required this.requestId,
  });

  final String actorUid;
  final String tenantId;
  final TenantStatus recordStatus;
  final DateTime recordUpdatedAt;
  final String reason;
  final String confirmation;
  final String requestId;
}

final class PlatformTenantArchivalResult {
  const PlatformTenantArchivalResult._({
    required this.tenantId,
    required this.previousStatus,
    required this.status,
    required this.fanoutOperationId,
  });

  factory PlatformTenantArchivalResult.fromCallable(
    Object? value, {
    required PlatformTenantArchivalIntent intent,
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
        data['previousStatus'] != TenantStatus.rejected.wireValue ||
        data['status'] != TenantStatus.archived.wireValue) {
      throw const FormatException(
        'setTenantLifecycle returned an invalid archival result.',
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
        'setTenantLifecycle returned an invalid archival result.',
      );
    }
    if (tenantId != intent.tenantId) {
      throw const FormatException(
        'setTenantLifecycle returned another tenant.',
      );
    }
    return PlatformTenantArchivalResult._(
      tenantId: tenantId,
      previousStatus: TenantStatus.rejected,
      status: TenantStatus.archived,
      fanoutOperationId: fanoutOperationId,
    );
  }

  final String tenantId;
  final TenantStatus previousStatus;
  final TenantStatus status;
  final String fanoutOperationId;
}

final class PlatformTenantArchivalGateway {
  PlatformTenantArchivalGateway({
    required PlatformReviewIdentity identity,
    required PlatformRejectedTenant tenant,
    required SetTenantLifecycleCallable callable,
    PlatformTenantReviewRequestIdFactory? requestIdFactory,
  }) : _identity = identity,
       _tenant = tenant,
       _callable = callable,
       _requestIdFactory = requestIdFactory;

  final PlatformReviewIdentity _identity;
  final PlatformRejectedTenant _tenant;
  final SetTenantLifecycleCallable _callable;
  final PlatformTenantReviewRequestIdFactory? _requestIdFactory;

  PlatformTenantArchivalIntent createIntent({
    required String reason,
    required String confirmation,
  }) {
    if (!_identity.canReview) {
      throw StateError('Platform archival access is required.');
    }
    if (_tenant.status != TenantStatus.rejected) {
      throw StateError('Only rejected businesses can be archived here.');
    }
    final normalizedReason = normalizeTenantArchivalReason(reason);
    final normalizedConfirmation = confirmation.trim();
    if (normalizedConfirmation != _tenant.archiveConfirmation) {
      throw ArgumentError.value(
        confirmation,
        'confirmation',
        'Must exactly match the canonical business name and slug.',
      );
    }
    final requestId = (_requestIdFactory ?? securePlatformReviewRequestId)();
    if (!platformReviewRequestIdPattern.hasMatch(requestId)) {
      throw StateError('The platform review request ID generator is invalid.');
    }
    return PlatformTenantArchivalIntent._(
      actorUid: _identity.uid,
      tenantId: _tenant.tenantId,
      recordStatus: _tenant.status,
      recordUpdatedAt: _tenant.updatedAt,
      reason: normalizedReason,
      confirmation: normalizedConfirmation,
      requestId: requestId,
    );
  }

  Future<PlatformTenantArchivalResult> submit(
    PlatformTenantArchivalIntent intent,
  ) async {
    if (!_identity.canReview ||
        intent.actorUid != _identity.uid ||
        intent.tenantId != _tenant.tenantId ||
        intent.recordStatus != _tenant.status ||
        intent.recordUpdatedAt != _tenant.updatedAt ||
        intent.confirmation != _tenant.archiveConfirmation) {
      throw StateError('The platform archival intent belongs elsewhere.');
    }
    final response = await _callable.call(<String, Object?>{
      'tenantId': _tenant.tenantId,
      'status': TenantStatus.archived.wireValue,
      'reason': intent.reason,
      'requestId': intent.requestId,
    });
    return PlatformTenantArchivalResult.fromCallable(response, intent: intent);
  }
}

final class PlatformTenantArchivalForm extends StatefulWidget {
  const PlatformTenantArchivalForm({
    super.key,
    required this.identity,
    required this.tenant,
    required this.callable,
    required this.onSuccess,
    required this.onCancel,
    this.requestIdFactory,
    this.isCurrent,
  });

  final PlatformReviewIdentity identity;
  final PlatformRejectedTenant tenant;
  final SetTenantLifecycleCallable callable;
  final ValueChanged<PlatformTenantArchivalResult> onSuccess;
  final VoidCallback onCancel;
  final PlatformTenantReviewRequestIdFactory? requestIdFactory;
  final PlatformTenantReviewCurrentCheck? isCurrent;

  @override
  State<PlatformTenantArchivalForm> createState() =>
      _PlatformTenantArchivalFormState();
}

final class _PlatformTenantArchivalFormState
    extends State<PlatformTenantArchivalForm> {
  final _reasonController = TextEditingController();
  final _confirmationController = TextEditingController();
  PlatformTenantArchivalIntent? _intent;
  bool _submitting = false;
  String? _safeError;

  @override
  void didUpdateWidget(covariant PlatformTenantArchivalForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity.uid == widget.identity.uid &&
        oldWidget.tenant.tenantId == widget.tenant.tenantId &&
        oldWidget.tenant.status == widget.tenant.status &&
        oldWidget.tenant.updatedAt == widget.tenant.updatedAt) {
      return;
    }
    _intent = null;
    _submitting = false;
    _safeError = null;
    _reasonController.clear();
    _confirmationController.clear();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  void _intentFieldChanged(String _) {
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
    final gateway = PlatformTenantArchivalGateway(
      identity: identity,
      tenant: tenant,
      callable: widget.callable,
      requestIdFactory: widget.requestIdFactory,
    );
    late final PlatformTenantArchivalIntent intent;
    try {
      intent = _intent ??= gateway.createIntent(
        reason: _reasonController.text,
        confirmation: _confirmationController.text,
      );
    } catch (_) {
      if (!mounted || !_isStillCurrent(identity, tenant)) return;
      setState(
        () => _safeError =
            'Enter a 3-1000 character reason and the exact confirmation text.',
      );
      return;
    }
    setState(() {
      _submitting = true;
      _safeError = null;
    });
    late final PlatformTenantArchivalResult result;
    try {
      result = await gateway.submit(intent);
    } catch (error) {
      if (!mounted ||
          !_isStillCurrent(identity, tenant) ||
          !identical(_intent, intent)) {
        return;
      }
      setState(() {
        _submitting = false;
        _safeError = platformTenantArchivalSafeError(error);
      });
      return;
    }
    if (!mounted ||
        !_isStillCurrent(identity, tenant) ||
        !identical(_intent, intent)) {
      return;
    }
    setState(() => _submitting = false);
    widget.onSuccess(result);
  }

  bool _isStillCurrent(
    PlatformReviewIdentity identity,
    PlatformRejectedTenant tenant,
  ) =>
      widget.identity.uid == identity.uid &&
      widget.tenant.tenantId == tenant.tenantId &&
      widget.tenant.status == tenant.status &&
      widget.tenant.updatedAt == tenant.updatedAt &&
      _isCurrent();

  bool _isCurrent() =>
      widget.identity.canReview && (widget.isCurrent?.call() ?? true);

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Archive ${widget.tenant.name} (${widget.tenant.slug})?',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      const Text(
        'This permanently removes the business from active ownership counts. '
        'It cannot be reopened through tenant management.',
      ),
      const SizedBox(height: 16),
      TextField(
        key: const ValueKey('platform-archival-reason'),
        controller: _reasonController,
        enabled: !_submitting,
        minLines: 2,
        maxLines: 4,
        maxLength: 1000,
        onChanged: _intentFieldChanged,
        decoration: const InputDecoration(labelText: 'Archival reason'),
      ),
      Text('Type ${widget.tenant.archiveConfirmation} to confirm.'),
      const SizedBox(height: 8),
      TextField(
        key: const ValueKey('platform-archival-confirmation'),
        controller: _confirmationController,
        enabled: !_submitting,
        autocorrect: false,
        onChanged: _intentFieldChanged,
        decoration: const InputDecoration(labelText: 'Confirmation'),
      ),
      if (_safeError != null) ...[
        const SizedBox(height: 12),
        Text(
          _safeError!,
          key: const ValueKey('platform-archival-error'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
      const SizedBox(height: 16),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            key: const ValueKey('platform-archival-cancel'),
            onPressed: _submitting ? null : widget.onCancel,
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            key: const ValueKey('platform-archival-confirm'),
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.archive_outlined),
            label: Text(_submitting ? 'Archiving...' : 'Archive business'),
          ),
        ],
      ),
    ],
  );
}

final class PlatformRejectedTenantScreen extends StatefulWidget {
  const PlatformRejectedTenantScreen({
    super.key,
    required this.identity,
    required this.dataSource,
    required this.callable,
    this.requestIdFactory,
    this.isCurrent,
    this.pageSize = 20,
  });

  final PlatformReviewIdentity identity;
  final PlatformRejectedTenantDataSource dataSource;
  final SetTenantLifecycleCallable callable;
  final PlatformTenantReviewRequestIdFactory? requestIdFactory;
  final PlatformTenantReviewCurrentCheck? isCurrent;
  final int pageSize;

  @override
  State<PlatformRejectedTenantScreen> createState() =>
      _PlatformRejectedTenantScreenState();
}

final class _PlatformRejectedTenantScreenState
    extends State<PlatformRejectedTenantScreen> {
  final List<PlatformRejectedTenant> _items = [];
  PlatformRejectedTenantCursor? _cursor;
  bool _hasMore = false;
  bool _loading = false;
  String? _safeError;
  int _queueEpoch = 0;
  String? _archivingTenantId;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant PlatformRejectedTenantScreen oldWidget) {
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
      _archivingTenantId = null;
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
      final page = await PlatformRejectedTenantQueue(
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
        _safeError = 'Rejected businesses could not be loaded.';
      });
    }
  }

  bool _isCurrent(int epoch) =>
      mounted &&
      epoch == _queueEpoch &&
      widget.identity.canReview &&
      (widget.isCurrent?.call() ?? true);

  void _archive(PlatformRejectedTenant tenant) {
    if (_loading) return;
    setState(() => _archivingTenantId = tenant.tenantId);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_safeError != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _safeError!,
              key: const ValueKey('platform-archival-queue-error'),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _reload, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(child: Text('No rejected businesses.'));
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: _items.length + (_hasMore || _loading ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == _items.length) {
            return Center(
              child: _loading
                  ? const CircularProgressIndicator()
                  : OutlinedButton(
                      key: const ValueKey('platform-archival-load-more'),
                      onPressed: _loadMore,
                      child: const Text('Load more'),
                    ),
            );
          }
          final tenant = _items[index];
          final archiving = _archivingTenantId == tenant.tenantId;
          final epoch = _queueEpoch;
          return Card(
            key: ValueKey('platform-archival-tenant-${tenant.tenantId}'),
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
                  Text('${tenant.owner.email} - rejected'),
                  if (!tenant.owner.globallyActive)
                    const Text('Owner account disabled'),
                  const SizedBox(height: 12),
                  if (!archiving)
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        key: ValueKey('platform-archive-${tenant.tenantId}'),
                        onPressed: () => _archive(tenant),
                        icon: const Icon(Icons.archive_outlined),
                        label: const Text('Archive'),
                      ),
                    )
                  else
                    PlatformTenantArchivalForm(
                      identity: widget.identity,
                      tenant: tenant,
                      callable: widget.callable,
                      requestIdFactory: widget.requestIdFactory,
                      isCurrent: () =>
                          _isCurrent(epoch) &&
                          _archivingTenantId == tenant.tenantId,
                      onSuccess: (_) => _reload(),
                      onCancel: () => setState(() => _archivingTenantId = null),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

String normalizeTenantArchivalReason(String value) {
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

String platformTenantArchivalSafeError(Object error) {
  if (error is PlatformTenantReviewCallableException) {
    return switch (error.code) {
      'failed-precondition' =>
        'This business changed or no longer satisfies archival requirements.',
      'not-found' => 'This business no longer exists.',
      'permission-denied' => 'Platform archival access is no longer available.',
      _ => 'Business could not be archived. Please try again.',
    };
  }
  return 'Business could not be archived. Please try again.';
}

Timestamp _decodeRejectedTimestamp(Object? value) {
  if (value is Timestamp) return value;
  if (value is DateTime) return Timestamp.fromDate(value.toUtc());
  throw const FormatException('Rejected tenant timestamp is invalid.');
}
