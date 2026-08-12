import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../ui/fields.dart';
import '../ui/scaffold.dart';
import '../ui/tokens.dart';
import 'platform_tenant_archival.dart';
import 'platform_global_user_status.dart';
import 'platform_tenant_review.dart';
import 'tenant_id.dart';
import 'tenant_request.dart';
import 'tenant_types.dart';

final class PlatformLifecycleTenantCursor {
  const PlatformLifecycleTenantCursor({
    required this.status,
    required this.updatedAt,
    required this.tenantId,
  });

  final TenantStatus status;
  final Timestamp updatedAt;
  final String tenantId;
}

abstract interface class PlatformLifecycleTenantDataSource {
  Future<List<PlatformTenantDocument>> loadLifecycleTenantDocuments({
    required int limit,
    PlatformLifecycleTenantCursor? cursor,
  });

  Future<PlatformTenantDocument?> loadRootUser(String uid);
}

final class FirebasePlatformLifecycleTenantDataSource
    implements PlatformLifecycleTenantDataSource {
  FirebasePlatformLifecycleTenantDataSource({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<List<PlatformTenantDocument>> loadLifecycleTenantDocuments({
    required int limit,
    PlatformLifecycleTenantCursor? cursor,
  }) async {
    Query<Map<String, dynamic>> query = _firestore
        .collection('tenants')
        .where('status', whereIn: const ['active', 'suspended'])
        .orderBy('status')
        .orderBy('updatedAt', descending: true)
        .orderBy(FieldPath.documentId)
        .limit(limit);
    if (cursor != null) {
      query = query.startAfter(<Object>[
        cursor.status.wireValue,
        cursor.updatedAt,
        cursor.tenantId,
      ]);
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

final class PlatformLifecycleTenant {
  const PlatformLifecycleTenant._({
    required this.tenantId,
    required this.name,
    required this.slug,
    required this.owner,
    required this.status,
    required this.updatedAt,
    required this.updatedAtCursor,
  });

  factory PlatformLifecycleTenant.fromDocuments({
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
        throw const FormatException('Managed tenant fields are invalid.');
      }
      name = normalizeTenantRequestName(tenant.data['name']! as String);
      slug = normalizeTenantRequestSlug(tenant.data['slug']! as String);
      ownerUid = validateTenantDocumentId(
        tenant.data['ownerUid']! as String,
        fieldName: 'ownerUid',
      );
      status = TenantStatus.fromWire(tenant.data['status']);
    } on (ArgumentError, FormatException) {
      throw const FormatException('Managed tenant fields are invalid.');
    }
    if (status != TenantStatus.active && status != TenantStatus.suspended) {
      throw const FormatException(
        'Lifecycle queue returned an unsupported tenant status.',
      );
    }
    final updatedAtCursor = _decodeLifecycleTimestamp(tenant.data['updatedAt']);
    return PlatformLifecycleTenant._(
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

  PlatformLifecycleTenantCursor get cursor => PlatformLifecycleTenantCursor(
    status: status,
    updatedAt: updatedAtCursor,
    tenantId: tenantId,
  );
}

final class PlatformLifecycleTenantPage {
  const PlatformLifecycleTenantPage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<PlatformLifecycleTenant> items;
  final PlatformLifecycleTenantCursor? nextCursor;
  final bool hasMore;
}

final class PlatformLifecycleTenantQueue {
  PlatformLifecycleTenantQueue({
    required PlatformReviewIdentity identity,
    required PlatformLifecycleTenantDataSource dataSource,
  }) : _identity = identity,
       _dataSource = dataSource;

  final PlatformReviewIdentity _identity;
  final PlatformLifecycleTenantDataSource _dataSource;

  Future<PlatformLifecycleTenantPage> load({
    int pageSize = 20,
    PlatformLifecycleTenantCursor? cursor,
  }) async {
    if (!_identity.canReview) {
      throw StateError('Platform lifecycle access is required.');
    }
    if (pageSize < 1 || pageSize > 50) {
      throw RangeError.range(pageSize, 1, 50, 'pageSize');
    }
    final documents = await _dataSource.loadLifecycleTenantDocuments(
      limit: pageSize + 1,
      cursor: cursor,
    );
    final hasMore = documents.length > pageSize;
    final selected = documents.take(pageSize).toList(growable: false);
    final items = await Future.wait(
      selected.map((tenant) async {
        final rawOwnerUid = tenant.data['ownerUid'];
        if (rawOwnerUid is! String) {
          throw const FormatException('Managed tenant owner is missing.');
        }
        late final String ownerUid;
        try {
          ownerUid = validateTenantDocumentId(
            rawOwnerUid,
            fieldName: 'ownerUid',
          );
        } on ArgumentError {
          throw const FormatException('Managed tenant owner is invalid.');
        }
        final owner = await _dataSource.loadRootUser(ownerUid);
        if (owner == null) {
          throw const FormatException('Managed tenant owner is missing.');
        }
        return PlatformLifecycleTenant.fromDocuments(
          tenant: tenant,
          owner: owner,
        );
      }),
    );
    return PlatformLifecycleTenantPage(
      items: List<PlatformLifecycleTenant>.unmodifiable(items),
      nextCursor: hasMore && items.isNotEmpty ? items.last.cursor : null,
      hasMore: hasMore,
    );
  }
}

enum PlatformTenantLifecycleAction {
  suspend(
    currentStatus: TenantStatus.active,
    targetStatus: TenantStatus.suspended,
  ),
  reactivate(
    currentStatus: TenantStatus.suspended,
    targetStatus: TenantStatus.active,
  );

  const PlatformTenantLifecycleAction({
    required this.currentStatus,
    required this.targetStatus,
  });

  final TenantStatus currentStatus;
  final TenantStatus targetStatus;
}

final class PlatformTenantLifecycleIntent {
  const PlatformTenantLifecycleIntent._({
    required this.actorUid,
    required this.tenantId,
    required this.recordStatus,
    required this.recordUpdatedAt,
    required this.action,
    required this.reason,
    required this.requestId,
  });

  final String actorUid;
  final String tenantId;
  final TenantStatus recordStatus;
  final DateTime recordUpdatedAt;
  final PlatformTenantLifecycleAction action;
  final String? reason;
  final String requestId;
}

final class PlatformTenantLifecycleResult {
  const PlatformTenantLifecycleResult._({
    required this.tenantId,
    required this.previousStatus,
    required this.status,
    required this.fanoutOperationId,
  });

  factory PlatformTenantLifecycleResult.fromCallable(
    Object? value, {
    required PlatformTenantLifecycleIntent intent,
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
        data['previousStatus'] != intent.recordStatus.wireValue ||
        data['status'] != intent.action.targetStatus.wireValue) {
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
    return PlatformTenantLifecycleResult._(
      tenantId: tenantId,
      previousStatus: intent.recordStatus,
      status: intent.action.targetStatus,
      fanoutOperationId: fanoutOperationId,
    );
  }

  final String tenantId;
  final TenantStatus previousStatus;
  final TenantStatus status;
  final String fanoutOperationId;
}

final class PlatformTenantLifecycleGateway {
  PlatformTenantLifecycleGateway({
    required PlatformReviewIdentity identity,
    required PlatformLifecycleTenant tenant,
    required SetTenantLifecycleCallable callable,
    PlatformTenantReviewRequestIdFactory? requestIdFactory,
  }) : _identity = identity,
       _tenant = tenant,
       _callable = callable,
       _requestIdFactory = requestIdFactory;

  final PlatformReviewIdentity _identity;
  final PlatformLifecycleTenant _tenant;
  final SetTenantLifecycleCallable _callable;
  final PlatformTenantReviewRequestIdFactory? _requestIdFactory;

  PlatformTenantLifecycleIntent createIntent({
    required PlatformTenantLifecycleAction action,
    String? reason,
  }) {
    if (!_identity.canReview) {
      throw StateError('Platform lifecycle access is required.');
    }
    if (_tenant.status != action.currentStatus) {
      throw StateError('The lifecycle action does not match this record.');
    }
    final normalizedReason = action == PlatformTenantLifecycleAction.suspend
        ? normalizeTenantSuspensionReason(reason ?? '')
        : null;
    final requestId = (_requestIdFactory ?? securePlatformReviewRequestId)();
    if (!platformReviewRequestIdPattern.hasMatch(requestId)) {
      throw StateError('The platform review request ID generator is invalid.');
    }
    return PlatformTenantLifecycleIntent._(
      actorUid: _identity.uid,
      tenantId: _tenant.tenantId,
      recordStatus: _tenant.status,
      recordUpdatedAt: _tenant.updatedAt,
      action: action,
      reason: normalizedReason,
      requestId: requestId,
    );
  }

  Future<PlatformTenantLifecycleResult> submit(
    PlatformTenantLifecycleIntent intent,
  ) async {
    if (!_identity.canReview ||
        intent.actorUid != _identity.uid ||
        intent.tenantId != _tenant.tenantId ||
        intent.recordStatus != _tenant.status ||
        intent.recordUpdatedAt != _tenant.updatedAt ||
        intent.action.currentStatus != _tenant.status) {
      throw StateError('The platform lifecycle intent belongs elsewhere.');
    }
    final response = await _callable.call(<String, Object?>{
      'tenantId': _tenant.tenantId,
      'status': intent.action.targetStatus.wireValue,
      if (intent.reason != null) 'reason': intent.reason,
      'requestId': intent.requestId,
    });
    return PlatformTenantLifecycleResult.fromCallable(response, intent: intent);
  }
}

final class PlatformTenantLifecycleForm extends StatefulWidget {
  const PlatformTenantLifecycleForm({
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
  final PlatformLifecycleTenant tenant;
  final PlatformTenantLifecycleAction action;
  final SetTenantLifecycleCallable callable;
  final ValueChanged<PlatformTenantLifecycleResult> onSuccess;
  final VoidCallback onCancel;
  final PlatformTenantReviewRequestIdFactory? requestIdFactory;
  final PlatformTenantReviewCurrentCheck? isCurrent;

  @override
  State<PlatformTenantLifecycleForm> createState() =>
      _PlatformTenantLifecycleFormState();
}

final class _PlatformTenantLifecycleFormState
    extends State<PlatformTenantLifecycleForm> {
  final _reasonController = TextEditingController();
  PlatformTenantLifecycleIntent? _intent;
  bool _submitting = false;
  String? _safeError;

  @override
  void didUpdateWidget(covariant PlatformTenantLifecycleForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity.uid == widget.identity.uid &&
        oldWidget.tenant.tenantId == widget.tenant.tenantId &&
        oldWidget.tenant.status == widget.tenant.status &&
        oldWidget.tenant.updatedAt == widget.tenant.updatedAt &&
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
    final gateway = PlatformTenantLifecycleGateway(
      identity: identity,
      tenant: tenant,
      callable: widget.callable,
      requestIdFactory: widget.requestIdFactory,
    );
    late final PlatformTenantLifecycleIntent intent;
    try {
      intent = _intent ??= gateway.createIntent(
        action: action,
        reason: _reasonController.text,
      );
    } catch (_) {
      if (!mounted || !_isStillCurrent(identity, tenant, action)) return;
      setState(
        () => _safeError = action == PlatformTenantLifecycleAction.suspend
            ? 'Enter a suspension reason between 3 and 1000 characters.'
            : 'This business cannot be reactivated.',
      );
      return;
    }
    setState(() {
      _submitting = true;
      _safeError = null;
    });
    late final PlatformTenantLifecycleResult result;
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
        _safeError = platformTenantLifecycleSafeError(error, action: action);
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

  bool _isStillCurrent(
    PlatformReviewIdentity identity,
    PlatformLifecycleTenant tenant,
    PlatformTenantLifecycleAction action,
  ) =>
      widget.identity.uid == identity.uid &&
      widget.tenant.tenantId == tenant.tenantId &&
      widget.tenant.status == tenant.status &&
      widget.tenant.updatedAt == tenant.updatedAt &&
      widget.action == action &&
      _isCurrent();

  bool _isCurrent() =>
      widget.identity.canReview && (widget.isCurrent?.call() ?? true);

  @override
  Widget build(BuildContext context) {
    final suspending = widget.action == PlatformTenantLifecycleAction.suspend;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          suspending
              ? 'Suspend ${widget.tenant.name}?'
              : 'Reactivate ${widget.tenant.name}?',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          suspending
              ? 'Operational access will be blocked until reactivation.'
              : 'Operational access will be restored if all checks pass.',
        ),
        if (suspending) ...[
          const SizedBox(height: 16),
          AppTextField(
            key: const ValueKey('platform-lifecycle-reason'),
            controller: _reasonController,
            enabled: !_submitting,
            minLines: 2,
            maxLines: 4,
            maxLength: 1000,
            onChanged: _reasonChanged,
            label: 'Suspension reason',
          ),
        ],
        if (_safeError != null) ...[
          const SizedBox(height: 12),
          Text(
            _safeError!,
            key: const ValueKey('platform-lifecycle-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              key: const ValueKey('platform-lifecycle-cancel'),
              label: 'Cancel',
              tier: AppButtonTier.tertiary,
              onPressed: _submitting ? null : widget.onCancel,
            ),
            const SizedBox(width: 8),
            AppButton(
              key: ValueKey(
                suspending
                    ? 'platform-lifecycle-suspend-confirm'
                    : 'platform-lifecycle-reactivate-confirm',
              ),
              label: suspending ? 'Suspend business' : 'Reactivate business',
              icon: suspending ? Icons.pause : Icons.play_arrow,
              // Suspending stops a business trading; reactivating restores it.
              // One control, two tiers, decided by which it currently is.
              tier: suspending
                  ? AppButtonTier.destructive
                  : AppButtonTier.primary,
              loading: _submitting,
              onPressed: _submit,
            ),
          ],
        ),
      ],
    );
  }
}

final class PlatformLifecycleTenantScreen extends StatefulWidget {
  const PlatformLifecycleTenantScreen({
    super.key,
    required this.identity,
    required this.dataSource,
    required this.callable,
    this.requestIdFactory,
    this.isCurrent,
    this.pageSize = 20,
  });

  final PlatformReviewIdentity identity;
  final PlatformLifecycleTenantDataSource dataSource;
  final SetTenantLifecycleCallable callable;
  final PlatformTenantReviewRequestIdFactory? requestIdFactory;
  final PlatformTenantReviewCurrentCheck? isCurrent;
  final int pageSize;

  @override
  State<PlatformLifecycleTenantScreen> createState() =>
      _PlatformLifecycleTenantScreenState();
}

final class PlatformTenantManagementScreen extends StatelessWidget {
  const PlatformTenantManagementScreen({
    super.key,
    required this.identity,
    required this.pendingDataSource,
    required this.lifecycleDataSource,
    required this.rejectedDataSource,
    required this.globalUserDataSource,
    required this.callable,
    required this.globalUserCallable,
    required this.onSignOut,
    this.requestIdFactory,
    this.isCurrent,
  });

  final PlatformReviewIdentity identity;
  final PlatformPendingTenantDataSource pendingDataSource;
  final PlatformLifecycleTenantDataSource lifecycleDataSource;
  final PlatformRejectedTenantDataSource rejectedDataSource;
  final PlatformGlobalUserDataSource globalUserDataSource;
  final SetTenantLifecycleCallable callable;
  final SetGlobalUserStatusCallable globalUserCallable;
  final Future<void> Function() onSignOut;
  final PlatformTenantReviewRequestIdFactory? requestIdFactory;
  final PlatformTenantReviewCurrentCheck? isCurrent;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    child: AppScaffold(
      title: 'Platform tenant management',
      contentWidth: AppContentWidth.records,
      actions: <Widget>[
        AppButton(
          label: 'Sign out',
          tier: AppButtonTier.tertiary,
          onPressed: onSignOut,
        ),
      ],
      // **The tabs moved out of the toolbar and under the header**, which is
      // the one ordering change step 5a makes to an existing screen. §7's page
      // pattern is *header → callout → filters → content*, and a tab strip is
      // the filter row of this page: leaving it in `AppBar.bottom` would have
      // put it above the title it filters. Nothing about what a tab does
      // changed - the `DefaultTabController` above still owns the selection.
      body: Column(
        children: <Widget>[
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Pending business reviews'),
              Tab(text: 'Active & suspended'),
              Tab(text: 'Rejected archive'),
              Tab(text: 'Global user status'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
          PlatformPendingTenantReviewScreen(
            identity: identity,
            dataSource: pendingDataSource,
            callable: callable,
            requestIdFactory: requestIdFactory,
            isCurrent: isCurrent,
            onSignOut: onSignOut,
            embedded: true,
          ),
          PlatformLifecycleTenantScreen(
            identity: identity,
            dataSource: lifecycleDataSource,
            callable: callable,
            requestIdFactory: requestIdFactory,
            isCurrent: isCurrent,
          ),
          PlatformRejectedTenantScreen(
            identity: identity,
            dataSource: rejectedDataSource,
            callable: callable,
            requestIdFactory: requestIdFactory,
            isCurrent: isCurrent,
          ),
          PlatformGlobalUserStatusScreen(
            identity: identity,
            dataSource: globalUserDataSource,
            callable: globalUserCallable,
            requestIdFactory: requestIdFactory,
            isCurrent: isCurrent,
            onCurrentOperatorAffected: onSignOut,
          ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

final class _PlatformLifecycleTenantScreenState
    extends State<PlatformLifecycleTenantScreen> {
  final List<PlatformLifecycleTenant> _items = [];
  PlatformLifecycleTenantCursor? _cursor;
  bool _hasMore = false;
  bool _loading = false;
  String? _safeError;
  int _queueEpoch = 0;
  String? _changingTenantId;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant PlatformLifecycleTenantScreen oldWidget) {
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
      _changingTenantId = null;
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
      final page = await PlatformLifecycleTenantQueue(
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
        _safeError = 'Active and suspended businesses could not be loaded.';
      });
    }
  }

  bool _isCurrent(int epoch) =>
      mounted &&
      epoch == _queueEpoch &&
      widget.identity.canReview &&
      (widget.isCurrent?.call() ?? true);

  void _change(PlatformLifecycleTenant tenant) {
    if (_loading) return;
    setState(() => _changingTenantId = tenant.tenantId);
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
              key: const ValueKey('platform-lifecycle-queue-error'),
            ),
            const SizedBox(height: 12),
            AppButton(
              label: 'Retry',
              tier: AppButtonTier.primary,
              onPressed: _reload,
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(child: Text('No active or suspended businesses.'));
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
                  : AppButton(
                      key: const ValueKey('platform-lifecycle-load-more'),
                      label: 'Load more',
                      onPressed: _loadMore,
                    ),
            );
          }
          final tenant = _items[index];
          final changing = _changingTenantId == tenant.tenantId;
          final action = tenant.status == TenantStatus.active
              ? PlatformTenantLifecycleAction.suspend
              : PlatformTenantLifecycleAction.reactivate;
          final epoch = _queueEpoch;
          return Card(
            key: ValueKey('platform-lifecycle-tenant-${tenant.tenantId}'),
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
                  Text('${tenant.owner.email} - ${tenant.status.wireValue}'),
                  if (!tenant.owner.globallyActive)
                    const Text('Owner account disabled'),
                  const SizedBox(height: 12),
                  if (!changing)
                    Align(
                      alignment: Alignment.centerRight,
                      child: action == PlatformTenantLifecycleAction.suspend
                          ? AppButton(
                              key: ValueKey(
                                'platform-suspend-${tenant.tenantId}',
                              ),
                              label: 'Suspend',
                              onPressed: () => _change(tenant),
                            )
                          : AppButton(
                              key: ValueKey(
                                'platform-reactivate-${tenant.tenantId}',
                              ),
                              label: 'Reactivate',
                              tier: AppButtonTier.primary,
                              onPressed: () => _change(tenant),
                            ),
                    )
                  else
                    PlatformTenantLifecycleForm(
                      identity: widget.identity,
                      tenant: tenant,
                      action: action,
                      callable: widget.callable,
                      requestIdFactory: widget.requestIdFactory,
                      isCurrent: () =>
                          _isCurrent(epoch) &&
                          _changingTenantId == tenant.tenantId,
                      onSuccess: (_) => _reload(),
                      onCancel: () => setState(() => _changingTenantId = null),
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

String normalizeTenantSuspensionReason(String value) {
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

String platformTenantLifecycleSafeError(
  Object error, {
  required PlatformTenantLifecycleAction action,
}) {
  if (error is PlatformTenantReviewCallableException) {
    return switch (error.code) {
      'resource-exhausted' =>
        'The owner has reached the active business limit.',
      'failed-precondition' =>
        'This business changed or no longer satisfies lifecycle requirements.',
      'not-found' => 'This business no longer exists.',
      'permission-denied' =>
        'Platform lifecycle access is no longer available.',
      _ =>
        action == PlatformTenantLifecycleAction.suspend
            ? 'Business could not be suspended. Please try again.'
            : 'Business could not be reactivated. Please try again.',
    };
  }
  return action == PlatformTenantLifecycleAction.suspend
      ? 'Business could not be suspended. Please try again.'
      : 'Business could not be reactivated. Please try again.';
}

Timestamp _decodeLifecycleTimestamp(Object? value) {
  if (value is Timestamp) return value;
  if (value is DateTime) return Timestamp.fromDate(value.toUtc());
  throw const FormatException('Managed tenant timestamp is invalid.');
}
