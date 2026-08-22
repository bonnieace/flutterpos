import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../ui/fields.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'tenant_id.dart';
import 'tenant_session.dart';
import 'tenant_session_controller.dart';
import 'tenant_staff_directory.dart';
import 'tenant_staff_invitation.dart';
import 'tenant_types.dart';

/// Narrow callable boundary for the enabled `replacePendingStaffEmail` mutation.
abstract interface class ReplacePendingStaffEmailCallable {
  Future<Object?> call(Map<String, Object?> payload);
}

/// Firebase adapter for `replacePendingStaffEmail`; validation remains above it.
final class FirebaseReplacePendingStaffEmailCallable
    implements ReplacePendingStaffEmailCallable {
  FirebaseReplacePendingStaffEmailCallable({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    final result = await _functions
        .httpsCallable('replacePendingStaffEmail')
        .call<Object?>(payload);
    return result.data;
  }
}

/// Normalized replacement email for one pending invitation.
final class TenantStaffInvitationEmailReplacementDraft {
  factory TenantStaffInvitationEmailReplacementDraft.normalized({
    required String oldTargetUid,
    required String email,
    required String existingEmail,
  }) => TenantStaffInvitationEmailReplacementDraft._(
    oldTargetUid: oldTargetUid,
    email: email,
    existingEmail: existingEmail,
  );

  TenantStaffInvitationEmailReplacementDraft._({
    required this.oldTargetUid,
    required String email,
    required String existingEmail,
  }) : email = normalizeTenantStaffInviteEmail(email) {
    if (this.email == existingEmail) {
      throw const FormatException(
        'The corrected email must differ from the pending invitation email.',
      );
    }
  }

  final String oldTargetUid;
  final String email;
}

/// One replacement intent and its stable idempotency key.
final class TenantStaffInvitationEmailReplacementIntent {
  const TenantStaffInvitationEmailReplacementIntent._({
    required this.draft,
    required this.requestId,
  });

  final TenantStaffInvitationEmailReplacementDraft draft;
  final String requestId;
}

/// Strictly decoded result from the `replacePendingStaffEmail` callable.
final class TenantStaffInvitationEmailReplacementResult {
  const TenantStaffInvitationEmailReplacementResult._({
    required this.tenantId,
    required this.uid,
    required this.invitationVersion,
    required this.deliveryId,
  });

  factory TenantStaffInvitationEmailReplacementResult.fromCallable(
    Object? value, {
    required String expectedTenantId,
    required String oldUid,
  }) {
    final data = _strictReplacementMap(
      value,
      label: 'replacePendingStaffEmail response',
      keys: const {
        'tenantId',
        'uid',
        'invitationStatus',
        'invitationVersion',
        'delivery',
      },
    );
    if (data['tenantId'] != expectedTenantId) {
      throw const FormatException(
        'replacePendingStaffEmail returned a result for another tenant.',
      );
    }
    final uidValue = data['uid'];
    if (uidValue is! String || uidValue == oldUid) {
      throw const FormatException(
        'replacePendingStaffEmail returned an invalid replacement identity.',
      );
    }
    late final String uid;
    try {
      validateTenantId(data['tenantId']! as String);
      uid = validateTenantDocumentId(uidValue, fieldName: 'uid');
    } on ArgumentError {
      throw const FormatException(
        'replacePendingStaffEmail returned an invalid replacement identity.',
      );
    }
    if (data['invitationStatus'] != 'pending') {
      throw const FormatException(
        'replacePendingStaffEmail returned an invalid invitation state.',
      );
    }
    final invitationVersion = data['invitationVersion'];
    if (invitationVersion is! int ||
        invitationVersion < 1 ||
        invitationVersion > 9007199254740991) {
      throw const FormatException(
        'replacePendingStaffEmail returned an invalid invitation version.',
      );
    }
    final delivery = _strictReplacementMap(
      data['delivery'],
      label: 'replacePendingStaffEmail delivery',
      keys: const {'deliveryId', 'status'},
    );
    if (delivery['status'] != 'pending_enqueue') {
      throw const FormatException(
        'replacePendingStaffEmail returned invalid delivery metadata.',
      );
    }
    final deliveryIdValue = delivery['deliveryId'];
    if (deliveryIdValue is! String) {
      throw const FormatException(
        'replacePendingStaffEmail returned invalid delivery metadata.',
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
        'replacePendingStaffEmail returned invalid delivery metadata.',
      );
    }
    return TenantStaffInvitationEmailReplacementResult._(
      tenantId: expectedTenantId,
      uid: uid,
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
final class TenantStaffInvitationEmailReplacementGateway {
  TenantStaffInvitationEmailReplacementGateway({
    required TenantSession session,
    required TenantStaffSummary target,
    required ReplacePendingStaffEmailCallable callable,
    TenantStaffRequestIdFactory? requestIdFactory,
  }) : _session = session,
       _target = target,
       _callable = callable,
       _requestIdFactory = requestIdFactory ?? _secureReplacementRequestId;

  static const allowedRoles = <TenantRole>[TenantRole.admin];

  final TenantSession _session;
  final TenantStaffSummary _target;
  final ReplacePendingStaffEmailCallable _callable;
  final TenantStaffRequestIdFactory _requestIdFactory;

  static bool canReplaceEmailFor(TenantStaffSummary target) =>
      !target.isOwner &&
      target.status == MembershipStatus.pending &&
      (target.invitationStatus == TenantStaffInvitationStatus.pending ||
          target.invitationStatus == TenantStaffInvitationStatus.sent);

  TenantStaffInvitationEmailReplacementIntent createIntent({
    required String email,
  }) {
    _requireAuthorizedSession();
    if (!canReplaceEmailFor(_target)) {
      throw const FormatException(
        'This staff invitation email cannot be replaced.',
      );
    }
    final requestId = _requestIdFactory();
    if (!_replacementRequestIdPattern.hasMatch(requestId)) {
      throw StateError(
        'The invitation email replacement request ID generator is invalid.',
      );
    }
    return TenantStaffInvitationEmailReplacementIntent._(
      draft: TenantStaffInvitationEmailReplacementDraft._(
        oldTargetUid: _target.uid,
        email: email,
        existingEmail: _target.email,
      ),
      requestId: requestId,
    );
  }

  Future<TenantStaffInvitationEmailReplacementResult> submit(
    TenantStaffInvitationEmailReplacementIntent intent,
  ) async {
    _requireAuthorizedSession();
    final draft = intent.draft;
    if (draft.oldTargetUid != _target.uid) {
      throw StateError(
        'The email replacement intent belongs to another staff member.',
      );
    }
    if (!canReplaceEmailFor(_target)) {
      throw StateError('This staff invitation email cannot be replaced.');
    }
    final response = await _callable.call(<String, Object?>{
      'tenantId': _session.tenantId,
      'uid': _target.uid,
      'email': draft.email,
      'requestId': intent.requestId,
    });
    return TenantStaffInvitationEmailReplacementResult.fromCallable(
      response,
      expectedTenantId: _session.tenantId,
      oldUid: _target.uid,
    );
  }

  void _requireAuthorizedSession() {
    if (!_session.canAccess(allowedRoles: allowedRoles)) {
      throw StateError('An owner or administrator session is required.');
    }
  }
}

/// Explicit confirmation for replacing one pending invitation email address.
final class TenantStaffInvitationEmailReplacementForm extends StatefulWidget {
  const TenantStaffInvitationEmailReplacementForm({
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
  final ReplacePendingStaffEmailCallable callable;
  final VoidCallback onSuccess;
  final VoidCallback onCancel;
  final TenantStaffRequestIdFactory? requestIdFactory;

  @override
  State<TenantStaffInvitationEmailReplacementForm> createState() =>
      _TenantStaffInvitationEmailReplacementFormState();
}

final class _TenantStaffInvitationEmailReplacementFormState
    extends State<TenantStaffInvitationEmailReplacementForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  TenantStaffInvitationEmailReplacementIntent? _intent;
  bool _submitting = false;
  String? _safeError;

  @override
  void didUpdateWidget(
    covariant TenantStaffInvitationEmailReplacementForm oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target.uid == widget.target.uid &&
        oldWidget.target.email == widget.target.email &&
        oldWidget.target.status == widget.target.status &&
        oldWidget.target.invitationStatus == widget.target.invitationStatus) {
      return;
    }
    _emailController.clear();
    _intent = null;
    _submitting = false;
    _safeError = null;
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _markIntentChanged() {
    if (_intent == null && _safeError == null) return;
    setState(() {
      _intent = null;
      _safeError = null;
    });
  }

  Future<void> _submit() async {
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) return;
    final controller = TenantSessionScope.read(context);
    final submittedTargetUid = widget.target.uid;
    final submittedEmail = widget.target.email;
    final submittedStatus = widget.target.status;
    final submittedInvitationStatus = widget.target.invitationStatus;
    if (!_isCurrent(
      controller,
      submittedTargetUid,
      submittedEmail,
      submittedStatus,
      submittedInvitationStatus,
    )) {
      return;
    }
    final gateway = TenantStaffInvitationEmailReplacementGateway(
      session: widget.session,
      target: widget.target,
      callable: widget.callable,
      requestIdFactory: widget.requestIdFactory,
    );
    late final TenantStaffInvitationEmailReplacementIntent intent;
    try {
      intent = _intent ??= gateway.createIntent(email: _emailController.text);
    } catch (_) {
      if (!mounted ||
          !_isCurrent(
            controller,
            submittedTargetUid,
            submittedEmail,
            submittedStatus,
            submittedInvitationStatus,
          )) {
        return;
      }
      setState(() => _safeError = 'Check the corrected email and try again.');
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
            submittedEmail,
            submittedStatus,
            submittedInvitationStatus,
          )) {
        return;
      }
      setState(() {
        _submitting = false;
        _safeError =
            'Invitation email could not be replaced. Please try again.';
      });
      return;
    }
    if (!mounted ||
        !_isCurrent(
          controller,
          submittedTargetUid,
          submittedEmail,
          submittedStatus,
          submittedInvitationStatus,
        )) {
      return;
    }
    setState(() => _submitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invitation email replacement queued.')),
    );
    widget.onSuccess();
  }

  bool _isCurrent(
    TenantSessionController controller,
    String expectedTargetUid,
    String expectedEmail,
    MembershipStatus expectedStatus,
    TenantStaffInvitationStatus expectedInvitationStatus,
  ) {
    final current = controller.session;
    return widget.target.uid == expectedTargetUid &&
        widget.target.email == expectedEmail &&
        widget.target.status == expectedStatus &&
        widget.target.invitationStatus == expectedInvitationStatus &&
        current != null &&
        current.uid == widget.session.uid &&
        current.tenantId == widget.session.tenantId &&
        current.epoch == widget.session.epoch &&
        current.canAccess(
          allowedRoles:
              TenantStaffInvitationEmailReplacementGateway.allowedRoles,
        );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Replace invitation email for ${widget.target.displayName}?',
            style: tokens.typography.titleMedium.copyWith(
              color: tokens.colors.text.primary,
            ),
          ),
          SizedBox(height: tokens.spacing.s8),
          Text(
            'The pending membership for ${widget.target.email} will be cancelled and a new invitation will be queued.',
          ),
          SizedBox(height: tokens.spacing.s12),
          AppTextField(
            key: const ValueKey('replace-staff-email-input'),
            controller: _emailController,
            enabled: !_submitting,
            keyboardType: TextInputType.emailAddress,
            label: 'Corrected email',
            leading: Icons.email_outlined,
            onChanged: (_) => _markIntentChanged(),
            validator: (value) {
              try {
                TenantStaffInvitationEmailReplacementDraft._(
                  oldTargetUid: widget.target.uid,
                  email: value ?? '',
                  existingEmail: widget.target.email,
                );
                return null;
              } on FormatException {
                return 'Enter a different valid email address.';
              }
            },
          ),
          if (_safeError != null) ...[
            SizedBox(height: tokens.spacing.s12),
            Callout(
              key: const ValueKey('replace-staff-email-error'),
              // A refusal, named as one rather than painted red: the write
              // was attempted and nothing changed. Before this the whole of
              // the status was the colour, which is the case §9 rules out.
              status: AppNotice.refused(_safeError!).status,
              message: _safeError!,
            ),
          ],
          SizedBox(height: tokens.spacing.s16),
          // A `Wrap`, for the reason recorded in `tenant_staff_status.dart`: this
          // form is laid out inside a record now, and a record at §4.1's `medium`
          // band is half a page wide.
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AppTokens.componentOf(context).spacing.s8,
            runSpacing: AppTokens.componentOf(context).spacing.s8,
            children: [
              AppButton(
                key: const ValueKey('replace-staff-email-cancel'),
                label: 'Cancel',
                tier: AppButtonTier.tertiary,
                onPressed: _submitting ? null : widget.onCancel,
              ),
              AppButton(
                key: const ValueKey('replace-staff-email-confirm'),
                label: 'Replace email',
                icon: Icons.alternate_email_outlined,
                tier: AppButtonTier.primary,
                loading: _submitting,
                onPressed: _submit,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Map<String, Object?> _strictReplacementMap(
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

String _secureReplacementRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'replace-email-${base64Url.encode(bytes).replaceAll('=', '')}';
}

final _replacementRequestIdPattern = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$',
);
