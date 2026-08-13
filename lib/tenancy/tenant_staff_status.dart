import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../ui/tokens.dart';
import 'tenant_id.dart';
import 'tenant_session.dart';
import 'tenant_session_controller.dart';
import 'tenant_staff_directory.dart';
import 'tenant_staff_invitation.dart';
import 'tenant_types.dart';

/// Narrow callable boundary for the enabled `setStaffStatus` mutation.
abstract interface class SetStaffStatusCallable {
  Future<Object?> call(Map<String, Object?> payload);
}

/// Firebase adapter for `setStaffStatus`; validation remains above it.
final class FirebaseSetStaffStatusCallable implements SetStaffStatusCallable {
  FirebaseSetStaffStatusCallable({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    final result = await _functions
        .httpsCallable('setStaffStatus')
        .call<Object?>(payload);
    return result.data;
  }
}

/// One status-change intent and its stable idempotency key.
final class TenantStaffStatusIntent {
  const TenantStaffStatusIntent._({
    required this.targetUid,
    required this.targetStatus,
    required this.requestId,
  });

  final String targetUid;
  final MembershipStatus targetStatus;
  final String requestId;
}

/// Strictly decoded result from the `setStaffStatus` callable.
final class TenantStaffStatusResult {
  const TenantStaffStatusResult._({
    required this.tenantId,
    required this.uid,
    required this.role,
    required this.status,
  });

  factory TenantStaffStatusResult.fromCallable(
    Object? value, {
    required String expectedTenantId,
    required String expectedUid,
    required TenantRole expectedRole,
    required MembershipStatus expectedStatus,
  }) {
    final data = _strictStatusMap(value);
    if (data['tenantId'] != expectedTenantId) {
      throw const FormatException(
        'setStaffStatus returned a result for another tenant.',
      );
    }
    if (data['uid'] != expectedUid) {
      throw const FormatException(
        'setStaffStatus returned a result for another staff member.',
      );
    }
    try {
      validateTenantId(data['tenantId']! as String);
      validateTenantDocumentId(data['uid']! as String, fieldName: 'uid');
    } on ArgumentError {
      throw const FormatException('setStaffStatus returned invalid identity.');
    }
    final role = TenantRole.fromWire(data['role']);
    final status = MembershipStatus.fromWire(data['status']);
    if (role != expectedRole || status != expectedStatus) {
      throw const FormatException(
        'setStaffStatus returned an unexpected staff state.',
      );
    }
    return TenantStaffStatusResult._(
      tenantId: expectedTenantId,
      uid: expectedUid,
      role: role,
      status: status,
    );
  }

  final String tenantId;
  final String uid;
  final TenantRole role;
  final MembershipStatus status;
}

/// Session- and target-bound gateway with no tenant or UID input surface.
final class TenantStaffStatusGateway {
  TenantStaffStatusGateway({
    required TenantSession session,
    required TenantStaffSummary target,
    required SetStaffStatusCallable callable,
    TenantStaffRequestIdFactory? requestIdFactory,
  }) : _session = session,
       _target = target,
       _callable = callable,
       _requestIdFactory = requestIdFactory ?? _secureStatusRequestId;

  static const allowedRoles = <TenantRole>[TenantRole.admin];

  final TenantSession _session;
  final TenantStaffSummary _target;
  final SetStaffStatusCallable _callable;
  final TenantStaffRequestIdFactory _requestIdFactory;

  static bool canChangeTarget(TenantStaffSummary target) =>
      !target.isOwner &&
      target.invitationStatus == TenantStaffInvitationStatus.accepted &&
      (target.status == MembershipStatus.active ||
          target.status == MembershipStatus.inactive);

  TenantStaffStatusIntent createIntent({
    required MembershipStatus targetStatus,
  }) {
    _requireAuthorizedSession();
    if (!canChangeTarget(_target) ||
        (targetStatus != MembershipStatus.active &&
            targetStatus != MembershipStatus.inactive) ||
        targetStatus == _target.status) {
      throw const FormatException('The requested staff status is invalid.');
    }
    final requestId = _requestIdFactory();
    if (!_statusRequestIdPattern.hasMatch(requestId)) {
      throw StateError('The staff status request ID generator is invalid.');
    }
    return TenantStaffStatusIntent._(
      targetUid: _target.uid,
      targetStatus: targetStatus,
      requestId: requestId,
    );
  }

  Future<TenantStaffStatusResult> submit(TenantStaffStatusIntent intent) async {
    _requireAuthorizedSession();
    if (intent.targetUid != _target.uid) {
      throw StateError('The status intent belongs to another staff member.');
    }
    if (!canChangeTarget(_target) || intent.targetStatus == _target.status) {
      throw StateError('The staff membership cannot change to that status.');
    }
    final response = await _callable.call(<String, Object?>{
      'tenantId': _session.tenantId,
      'uid': _target.uid,
      'status': intent.targetStatus.wireValue,
      'requestId': intent.requestId,
    });
    return TenantStaffStatusResult.fromCallable(
      response,
      expectedTenantId: _session.tenantId,
      expectedUid: _target.uid,
      expectedRole: _target.role,
      expectedStatus: intent.targetStatus,
    );
  }

  void _requireAuthorizedSession() {
    if (!_session.canAccess(allowedRoles: allowedRoles)) {
      throw StateError('An owner or administrator session is required.');
    }
  }
}

/// Explicit, recoverable confirmation for one decoded staff directory row.
final class TenantStaffStatusForm extends StatefulWidget {
  const TenantStaffStatusForm({
    super.key,
    required this.session,
    required this.target,
    required this.callable,
    required this.onSuccess,
    required this.onCancel,
    this.requestIdFactory,
  });

  final TenantSession session;
  final TenantStaffSummary target;
  final SetStaffStatusCallable callable;
  final VoidCallback onSuccess;
  final VoidCallback onCancel;
  final TenantStaffRequestIdFactory? requestIdFactory;

  @override
  State<TenantStaffStatusForm> createState() => _TenantStaffStatusFormState();
}

final class _TenantStaffStatusFormState extends State<TenantStaffStatusForm> {
  TenantStaffStatusIntent? _intent;
  bool _submitting = false;
  String? _safeError;

  MembershipStatus get _targetStatus =>
      widget.target.status == MembershipStatus.active
      ? MembershipStatus.inactive
      : MembershipStatus.active;

  @override
  void didUpdateWidget(covariant TenantStaffStatusForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target.uid == widget.target.uid &&
        oldWidget.target.status == widget.target.status) {
      return;
    }
    _intent = null;
    _submitting = false;
    _safeError = null;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final controller = TenantSessionScope.read(context);
    final submittedTargetUid = widget.target.uid;
    final submittedCurrentStatus = widget.target.status;
    if (!_isCurrent(controller, submittedTargetUid, submittedCurrentStatus)) {
      return;
    }
    final gateway = TenantStaffStatusGateway(
      session: widget.session,
      target: widget.target,
      callable: widget.callable,
      requestIdFactory: widget.requestIdFactory,
    );
    late final TenantStaffStatusIntent intent;
    try {
      intent = _intent ??= gateway.createIntent(targetStatus: _targetStatus);
    } catch (_) {
      if (!mounted ||
          !_isCurrent(controller, submittedTargetUid, submittedCurrentStatus)) {
        return;
      }
      setState(() => _safeError = 'This staff status cannot be changed.');
      return;
    }
    setState(() {
      _submitting = true;
      _safeError = null;
    });
    try {
      await gateway.submit(intent);
    } catch (_) {
      if (!mounted ||
          !_isCurrent(controller, submittedTargetUid, submittedCurrentStatus)) {
        return;
      }
      setState(() {
        _submitting = false;
        _safeError = 'Staff status could not be changed. Please try again.';
      });
      return;
    }
    if (!mounted ||
        !_isCurrent(controller, submittedTargetUid, submittedCurrentStatus)) {
      return;
    }
    setState(() => _submitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Staff member ${_targetStatus.wireValue}.')),
    );
    widget.onSuccess();
  }

  bool _isCurrent(
    TenantSessionController controller,
    String expectedTargetUid,
    MembershipStatus expectedCurrentStatus,
  ) {
    final current = controller.session;
    return widget.target.uid == expectedTargetUid &&
        widget.target.status == expectedCurrentStatus &&
        current != null &&
        current.uid == widget.session.uid &&
        current.tenantId == widget.session.tenantId &&
        current.epoch == widget.session.epoch &&
        current.canAccess(allowedRoles: TenantStaffStatusGateway.allowedRoles);
  }

  @override
  Widget build(BuildContext context) {
    final action = _targetStatus == MembershipStatus.active
        ? 'Activate'
        : 'Deactivate';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$action ${widget.target.displayName}?',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          _targetStatus == MembershipStatus.active
              ? 'This restores the staff member\'s access to this business.'
              : 'This removes the staff member\'s access to this business.',
        ),
        if (_safeError != null) ...[
          const SizedBox(height: 12),
          Text(
            _safeError!,
            key: const ValueKey('set-staff-status-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        // A `Wrap` rather than a `Row`, because this form is now laid out
        // inside a record - and a record at §4.1's `medium` band is half a
        // page wide. Two 48-high pills with verb phrases on them do not fit
        // 342 logical pixels, and a `Row` answers that by overflowing. It
        // answered the same way on a phone before this form was ever in a
        // `RecordList`; nothing had opened it there.
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AppTokens.componentOf(context).spacing.s8,
          runSpacing: AppTokens.componentOf(context).spacing.s8,
          children: [
            AppButton(
              key: const ValueKey('set-staff-status-cancel'),
              label: 'Cancel',
              tier: AppButtonTier.tertiary,
              onPressed: _submitting ? null : widget.onCancel,
            ),
            AppButton(
              key: const ValueKey('set-staff-status-confirm'),
              label: 'Confirm $action',
              icon: _targetStatus == MembershipStatus.active
                  ? Icons.person_add_alt_outlined
                  : Icons.person_off_outlined,
              // Deactivating a member removes their access; reactivating
              // restores it. §2.1's destructive tier is decided by what the
              // press does, not by which screen it is on.
              tier: _targetStatus == MembershipStatus.active
                  ? AppButtonTier.primary
                  : AppButtonTier.destructive,
              loading: _submitting,
              onPressed: _submit,
            ),
          ],
        ),
      ],
    );
  }
}

Map<String, Object?> _strictStatusMap(Object? value) {
  const keys = {'tenantId', 'uid', 'role', 'status'};
  if (value is! Map || value.length != keys.length) {
    throw const FormatException(
      'setStaffStatus response must contain the expected fields.',
    );
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String || !keys.contains(key)) {
      throw const FormatException(
        'setStaffStatus response must contain the expected fields.',
      );
    }
    result[key] = entry.value;
  }
  if (result['tenantId'] is! String || result['uid'] is! String) {
    throw const FormatException('setStaffStatus returned invalid identity.');
  }
  return result;
}

String _secureStatusRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'status-${base64Url.encode(bytes).replaceAll('=', '')}';
}

final _statusRequestIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$');
