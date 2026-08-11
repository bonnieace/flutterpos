import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import 'tenant_id.dart';
import 'tenant_session.dart';
import 'tenant_session_controller.dart';
import 'tenant_staff_directory.dart';
import 'tenant_staff_invitation.dart';
import 'tenant_types.dart';

/// Narrow callable boundary for the enabled `resendStaffInvitation` mutation.
abstract interface class ResendStaffInvitationCallable {
  Future<Object?> call(Map<String, Object?> payload);
}

/// Firebase adapter for `resendStaffInvitation`; validation remains above it.
final class FirebaseResendStaffInvitationCallable
    implements ResendStaffInvitationCallable {
  FirebaseResendStaffInvitationCallable({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    final result = await _functions
        .httpsCallable('resendStaffInvitation')
        .call<Object?>(payload);
    return result.data;
  }
}

/// One resend intent and its stable idempotency key.
final class TenantStaffInvitationResendIntent {
  const TenantStaffInvitationResendIntent._({
    required this.targetUid,
    required this.requestId,
  });

  final String targetUid;
  final String requestId;
}

/// Strictly decoded result from the `resendStaffInvitation` callable.
final class TenantStaffInvitationResendResult {
  const TenantStaffInvitationResendResult._({
    required this.tenantId,
    required this.uid,
    required this.invitationVersion,
    required this.deliveryId,
  });

  factory TenantStaffInvitationResendResult.fromCallable(
    Object? value, {
    required String expectedTenantId,
    required String expectedUid,
  }) {
    final data = _strictResendMap(
      value,
      label: 'resendStaffInvitation response',
      keys: const {
        'tenantId',
        'uid',
        'invitationStatus',
        'invitationVersion',
        'delivery',
      },
    );
    if (data['tenantId'] != expectedTenantId || data['uid'] != expectedUid) {
      throw const FormatException(
        'resendStaffInvitation returned an unexpected identity.',
      );
    }
    try {
      validateTenantId(data['tenantId']! as String);
      validateTenantDocumentId(data['uid']! as String, fieldName: 'uid');
    } on ArgumentError {
      throw const FormatException(
        'resendStaffInvitation returned an invalid identity.',
      );
    }
    if (data['invitationStatus'] != 'pending') {
      throw const FormatException(
        'resendStaffInvitation returned an invalid invitation state.',
      );
    }
    final invitationVersion = data['invitationVersion'];
    if (invitationVersion is! int ||
        invitationVersion < 1 ||
        invitationVersion > 9007199254740991) {
      throw const FormatException(
        'resendStaffInvitation returned an invalid invitation version.',
      );
    }
    final delivery = _strictResendMap(
      data['delivery'],
      label: 'resendStaffInvitation delivery',
      keys: const {'deliveryId', 'status'},
    );
    if (delivery['status'] != 'pending_enqueue') {
      throw const FormatException(
        'resendStaffInvitation returned invalid delivery metadata.',
      );
    }
    final deliveryIdValue = delivery['deliveryId'];
    if (deliveryIdValue is! String) {
      throw const FormatException(
        'resendStaffInvitation returned invalid delivery metadata.',
      );
    }
    late final String deliveryId;
    try {
      deliveryId = validateTenantDocumentId(
        deliveryIdValue,
        fieldName: 'deliveryId',
      );
    } on ArgumentError {
      throw const FormatException(
        'resendStaffInvitation returned invalid delivery metadata.',
      );
    }
    return TenantStaffInvitationResendResult._(
      tenantId: expectedTenantId,
      uid: expectedUid,
      invitationVersion: invitationVersion,
      deliveryId: deliveryId,
    );
  }

  final String tenantId;
  final String uid;
  final int invitationVersion;
  final String deliveryId;
}

/// Session- and target-bound gateway with no tenant or UID input surface.
final class TenantStaffInvitationResendGateway {
  TenantStaffInvitationResendGateway({
    required TenantSession session,
    required TenantStaffSummary target,
    required ResendStaffInvitationCallable callable,
    TenantStaffRequestIdFactory? requestIdFactory,
  }) : _session = session,
       _target = target,
       _callable = callable,
       _requestIdFactory = requestIdFactory ?? _secureResendRequestId;

  static const allowedRoles = <TenantRole>[TenantRole.admin];

  final TenantSession _session;
  final TenantStaffSummary _target;
  final ResendStaffInvitationCallable _callable;
  final TenantStaffRequestIdFactory _requestIdFactory;

  static bool canResendTo(TenantStaffSummary target) =>
      !target.isOwner &&
      target.status == MembershipStatus.pending &&
      (target.invitationStatus == TenantStaffInvitationStatus.pending ||
          target.invitationStatus == TenantStaffInvitationStatus.sent);

  TenantStaffInvitationResendIntent createIntent() {
    _requireAuthorizedSession();
    if (!canResendTo(_target)) {
      throw const FormatException('This staff invitation cannot be resent.');
    }
    final requestId = _requestIdFactory();
    if (!_resendRequestIdPattern.hasMatch(requestId)) {
      throw StateError('The invitation resend request ID generator is invalid.');
    }
    return TenantStaffInvitationResendIntent._(
      targetUid: _target.uid,
      requestId: requestId,
    );
  }

  Future<TenantStaffInvitationResendResult> submit(
    TenantStaffInvitationResendIntent intent,
  ) async {
    _requireAuthorizedSession();
    if (intent.targetUid != _target.uid) {
      throw StateError('The resend intent belongs to another staff member.');
    }
    if (!canResendTo(_target)) {
      throw StateError('This staff invitation cannot be resent.');
    }
    final response = await _callable.call(<String, Object?>{
      'tenantId': _session.tenantId,
      'uid': _target.uid,
      'requestId': intent.requestId,
    });
    return TenantStaffInvitationResendResult.fromCallable(
      response,
      expectedTenantId: _session.tenantId,
      expectedUid: _target.uid,
    );
  }

  void _requireAuthorizedSession() {
    if (!_session.canAccess(allowedRoles: allowedRoles)) {
      throw StateError('An owner or administrator session is required.');
    }
  }
}

/// Explicit, recoverable confirmation for one pending invitation row.
final class TenantStaffInvitationResendForm extends StatefulWidget {
  const TenantStaffInvitationResendForm({
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
  final ResendStaffInvitationCallable callable;
  final VoidCallback onSuccess;
  final VoidCallback onCancel;
  final TenantStaffRequestIdFactory? requestIdFactory;

  @override
  State<TenantStaffInvitationResendForm> createState() =>
      _TenantStaffInvitationResendFormState();
}

final class _TenantStaffInvitationResendFormState
    extends State<TenantStaffInvitationResendForm> {
  TenantStaffInvitationResendIntent? _intent;
  bool _submitting = false;
  String? _safeError;

  @override
  void didUpdateWidget(covariant TenantStaffInvitationResendForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target.uid == widget.target.uid &&
        oldWidget.target.status == widget.target.status &&
        oldWidget.target.invitationStatus == widget.target.invitationStatus) {
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
    final submittedStatus = widget.target.status;
    final submittedInvitationStatus = widget.target.invitationStatus;
    if (!_isCurrent(
      controller,
      submittedTargetUid,
      submittedStatus,
      submittedInvitationStatus,
    )) {
      return;
    }
    final gateway = TenantStaffInvitationResendGateway(
      session: widget.session,
      target: widget.target,
      callable: widget.callable,
      requestIdFactory: widget.requestIdFactory,
    );
    late final TenantStaffInvitationResendIntent intent;
    try {
      intent = _intent ??= gateway.createIntent();
    } catch (_) {
      if (!mounted ||
          !_isCurrent(
            controller,
            submittedTargetUid,
            submittedStatus,
            submittedInvitationStatus,
          )) {
        return;
      }
      setState(() => _safeError = 'This staff invitation cannot be resent.');
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
          !_isCurrent(
            controller,
            submittedTargetUid,
            submittedStatus,
            submittedInvitationStatus,
          )) {
        return;
      }
      setState(() {
        _submitting = false;
        _safeError = 'Invitation could not be resent. Please try again.';
      });
      return;
    }
    if (!mounted ||
        !_isCurrent(
          controller,
          submittedTargetUid,
          submittedStatus,
          submittedInvitationStatus,
        )) {
      return;
    }
    setState(() => _submitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Invitation resent to ${widget.target.email}.')),
    );
    widget.onSuccess();
  }

  bool _isCurrent(
    TenantSessionController controller,
    String expectedTargetUid,
    MembershipStatus expectedStatus,
    TenantStaffInvitationStatus expectedInvitationStatus,
  ) {
    final current = controller.session;
    return widget.target.uid == expectedTargetUid &&
        widget.target.status == expectedStatus &&
        widget.target.invitationStatus == expectedInvitationStatus &&
        current != null &&
        current.uid == widget.session.uid &&
        current.tenantId == widget.session.tenantId &&
        current.epoch == widget.session.epoch &&
        current.canAccess(
          allowedRoles: TenantStaffInvitationResendGateway.allowedRoles,
        );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Resend invitation to ${widget.target.displayName}?',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      Text('A new invitation will be queued for ${widget.target.email}.'),
      if (_safeError != null) ...[
        const SizedBox(height: 12),
        Text(
          _safeError!,
          key: const ValueKey('resend-staff-invitation-error'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
      const SizedBox(height: 16),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
            key: const ValueKey('resend-staff-invitation-cancel'),
            label: 'Cancel',
            tier: AppButtonTier.tertiary,
            onPressed: _submitting ? null : widget.onCancel,
          ),
          const SizedBox(width: 8),
          AppButton(
            key: const ValueKey('resend-staff-invitation-confirm'),
            label: 'Confirm resend',
            icon: Icons.forward_to_inbox_outlined,
            tier: AppButtonTier.primary,
            loading: _submitting,
            onPressed: _submit,
          ),
        ],
      ),
    ],
  );
}

Map<String, Object?> _strictResendMap(
  Object? value, {
  required String label,
  required Set<String> keys,
}) {
  if (value is! Map || value.length != keys.length) {
    throw FormatException('$label must contain the expected fields.');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String || !keys.contains(key)) {
      throw FormatException('$label must contain the expected fields.');
    }
    result[key] = entry.value;
  }
  return result;
}

String _secureResendRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'resend-${base64Url.encode(bytes).replaceAll('=', '')}';
}

final _resendRequestIdPattern = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$',
);
