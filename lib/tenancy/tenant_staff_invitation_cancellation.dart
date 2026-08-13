import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../ui/fields.dart';
import '../ui/tokens.dart';
import 'tenant_id.dart';
import 'tenant_session.dart';
import 'tenant_session_controller.dart';
import 'tenant_staff_directory.dart';
import 'tenant_staff_invitation.dart';
import 'tenant_types.dart';

/// Narrow callable boundary for the enabled `cancelTenantInvitation` mutation.
abstract interface class CancelTenantInvitationCallable {
  Future<Object?> call(Map<String, Object?> payload);
}

/// Firebase adapter for `cancelTenantInvitation`; validation remains above it.
final class FirebaseCancelTenantInvitationCallable
    implements CancelTenantInvitationCallable {
  FirebaseCancelTenantInvitationCallable({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    final result = await _functions
        .httpsCallable('cancelTenantInvitation')
        .call<Object?>(payload);
    return result.data;
  }
}

/// Normalized, client-validated reason for one cancellation intent.
final class TenantStaffInvitationCancellationDraft {
  const TenantStaffInvitationCancellationDraft._({required this.reason});

  factory TenantStaffInvitationCancellationDraft.normalized(String reason) {
    final normalizedReason = reason.trim();
    if (normalizedReason.length < 3 || normalizedReason.length > 500) {
      throw const FormatException(
        'Cancellation reason must be between 3 and 500 characters.',
      );
    }
    return TenantStaffInvitationCancellationDraft._(reason: normalizedReason);
  }

  final String reason;
}

/// One cancellation intent and its stable idempotency key.
final class TenantStaffInvitationCancellationIntent {
  const TenantStaffInvitationCancellationIntent._({
    required this.targetUid,
    required this.reason,
    required this.requestId,
  });

  final String targetUid;
  final String reason;
  final String requestId;
}

/// Strictly decoded result from the `cancelTenantInvitation` callable.
final class TenantStaffInvitationCancellationResult {
  const TenantStaffInvitationCancellationResult._({
    required this.tenantId,
    required this.uid,
    required this.invitationVersion,
  });

  factory TenantStaffInvitationCancellationResult.fromCallable(
    Object? value, {
    required String expectedTenantId,
    required String expectedUid,
  }) {
    final data = _strictCancellationMap(value);
    if (data['tenantId'] != expectedTenantId || data['uid'] != expectedUid) {
      throw const FormatException(
        'cancelTenantInvitation returned an unexpected identity.',
      );
    }
    try {
      validateTenantId(data['tenantId']! as String);
      validateTenantDocumentId(data['uid']! as String, fieldName: 'uid');
    } on ArgumentError {
      throw const FormatException(
        'cancelTenantInvitation returned an invalid identity.',
      );
    }
    if (data['invitationStatus'] != 'cancelled') {
      throw const FormatException(
        'cancelTenantInvitation returned an invalid invitation state.',
      );
    }
    final invitationVersion = data['invitationVersion'];
    if (invitationVersion is! int ||
        invitationVersion < 1 ||
        invitationVersion > 9007199254740991) {
      throw const FormatException(
        'cancelTenantInvitation returned an invalid invitation version.',
      );
    }
    if (data['delivery'] != null) {
      throw const FormatException(
        'cancelTenantInvitation returned invalid delivery metadata.',
      );
    }
    return TenantStaffInvitationCancellationResult._(
      tenantId: expectedTenantId,
      uid: expectedUid,
      invitationVersion: invitationVersion,
    );
  }

  final String tenantId;
  final String uid;
  final int invitationVersion;
}

/// Session- and target-bound gateway with no tenant or UID input surface.
final class TenantStaffInvitationCancellationGateway {
  TenantStaffInvitationCancellationGateway({
    required TenantSession session,
    required TenantStaffSummary target,
    required CancelTenantInvitationCallable callable,
    TenantStaffRequestIdFactory? requestIdFactory,
  }) : _session = session,
       _target = target,
       _callable = callable,
       _requestIdFactory = requestIdFactory ?? _secureCancellationRequestId;

  static const allowedRoles = <TenantRole>[TenantRole.admin];

  final TenantSession _session;
  final TenantStaffSummary _target;
  final CancelTenantInvitationCallable _callable;
  final TenantStaffRequestIdFactory _requestIdFactory;

  static bool canCancel(TenantStaffSummary target) =>
      !target.isOwner &&
      target.status == MembershipStatus.pending &&
      (target.invitationStatus == TenantStaffInvitationStatus.pending ||
          target.invitationStatus == TenantStaffInvitationStatus.sent);

  TenantStaffInvitationCancellationIntent createIntent({
    required String reason,
  }) {
    _requireAuthorizedSession();
    if (!canCancel(_target)) {
      throw const FormatException('This staff invitation cannot be cancelled.');
    }
    final draft = TenantStaffInvitationCancellationDraft.normalized(reason);
    final requestId = _requestIdFactory();
    if (!_cancellationRequestIdPattern.hasMatch(requestId)) {
      throw StateError(
        'The invitation cancellation request ID generator is invalid.',
      );
    }
    return TenantStaffInvitationCancellationIntent._(
      targetUid: _target.uid,
      reason: draft.reason,
      requestId: requestId,
    );
  }

  Future<TenantStaffInvitationCancellationResult> submit(
    TenantStaffInvitationCancellationIntent intent,
  ) async {
    _requireAuthorizedSession();
    if (intent.targetUid != _target.uid) {
      throw StateError(
        'The cancellation intent belongs to another staff member.',
      );
    }
    if (!canCancel(_target)) {
      throw StateError('This staff invitation cannot be cancelled.');
    }
    final response = await _callable.call(<String, Object?>{
      'tenantId': _session.tenantId,
      'uid': _target.uid,
      'reason': intent.reason,
      'requestId': intent.requestId,
    });
    return TenantStaffInvitationCancellationResult.fromCallable(
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

/// Explicit destructive confirmation for one pending invitation row.
final class TenantStaffInvitationCancellationForm extends StatefulWidget {
  const TenantStaffInvitationCancellationForm({
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
  final CancelTenantInvitationCallable callable;
  final VoidCallback onSuccess;
  final VoidCallback onCancel;
  final TenantStaffRequestIdFactory? requestIdFactory;

  @override
  State<TenantStaffInvitationCancellationForm> createState() =>
      _TenantStaffInvitationCancellationFormState();
}

final class _TenantStaffInvitationCancellationFormState
    extends State<TenantStaffInvitationCancellationForm> {
  final TextEditingController _reasonController = TextEditingController();
  TenantStaffInvitationCancellationIntent? _intent;
  bool _submitting = false;
  String? _reasonError;
  String? _safeError;

  @override
  void didUpdateWidget(
    covariant TenantStaffInvitationCancellationForm oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target.uid == widget.target.uid &&
        oldWidget.target.status == widget.target.status &&
        oldWidget.target.invitationStatus == widget.target.invitationStatus) {
      return;
    }
    _reasonController.clear();
    _intent = null;
    _submitting = false;
    _reasonError = null;
    _safeError = null;
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  void _reasonChanged(String _) {
    if (_intent == null && _reasonError == null && _safeError == null) return;
    setState(() {
      _intent = null;
      _reasonError = null;
      _safeError = null;
    });
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
    final gateway = TenantStaffInvitationCancellationGateway(
      session: widget.session,
      target: widget.target,
      callable: widget.callable,
      requestIdFactory: widget.requestIdFactory,
    );
    late final TenantStaffInvitationCancellationIntent intent;
    try {
      intent = _intent ??= gateway.createIntent(reason: _reasonController.text);
    } on FormatException {
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
        _reasonError = 'Enter a reason between 3 and 500 characters.';
        _safeError = null;
      });
      return;
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
        _reasonError = null;
        _safeError = 'This staff invitation cannot be cancelled.';
      });
      return;
    }
    setState(() {
      _submitting = true;
      _reasonError = null;
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
        _safeError = 'Invitation could not be cancelled. Please try again.';
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
      SnackBar(
        content: Text('Invitation for ${widget.target.email} cancelled.'),
      ),
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
          allowedRoles: TenantStaffInvitationCancellationGateway.allowedRoles,
        );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Cancel invitation for ${widget.target.displayName}?',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      const Text(
        'This removes the pending membership and invalidates its invitation.',
      ),
      const SizedBox(height: 12),
      AppTextField(
        key: const ValueKey('cancel-staff-invitation-reason'),
        controller: _reasonController,
        enabled: !_submitting,
        minLines: 2,
        maxLines: 4,
        maxLength: 500,
        onChanged: _reasonChanged,
        label: 'Cancellation reason',
        placeholder: 'Required for the tenant audit log',
        error: _reasonError,
      ),
      if (_safeError != null) ...[
        const SizedBox(height: 4),
        Text(
          _safeError!,
          key: const ValueKey('cancel-staff-invitation-error'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
      const SizedBox(height: 12),
      // A `Wrap`, for the reason recorded in `tenant_staff_status.dart`: this
      // form is laid out inside a record now, and a record at §4.1's `medium`
      // band is half a page wide.
      Wrap(
        alignment: WrapAlignment.end,
        spacing: AppTokens.componentOf(context).spacing.s8,
        runSpacing: AppTokens.componentOf(context).spacing.s8,
        children: [
          AppButton(
            key: const ValueKey('cancel-staff-invitation-dismiss'),
            label: 'Keep invitation',
            tier: AppButtonTier.tertiary,
            onPressed: _submitting ? null : widget.onCancel,
          ),
          // This is the clearest case in the sweep for the destructive tier
          // existing at all: the old call site reached past the theme for
          // `colorScheme.error` and `onError` to build a red slab by hand,
          // which is `claude.md` hard rule 2 being broken because there was no
          // role to reach for. There is one now.
          AppButton(
            key: const ValueKey('cancel-staff-invitation-confirm'),
            label: 'Cancel invitation',
            icon: Icons.person_remove_outlined,
            tier: AppButtonTier.destructive,
            loading: _submitting,
            onPressed: _submit,
          ),
        ],
      ),
    ],
  );
}

Map<String, Object?> _strictCancellationMap(Object? value) {
  const keys = {
    'tenantId',
    'uid',
    'invitationStatus',
    'invitationVersion',
    'delivery',
  };
  if (value is! Map || value.length != keys.length) {
    throw const FormatException(
      'cancelTenantInvitation response must contain the expected fields.',
    );
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String || !keys.contains(key)) {
      throw const FormatException(
        'cancelTenantInvitation response must contain the expected fields.',
      );
    }
    result[key] = entry.value;
  }
  return result;
}

String _secureCancellationRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'cancel-${base64Url.encode(bytes).replaceAll('=', '')}';
}

final _cancellationRequestIdPattern = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$',
);
