import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'tenant_id.dart';
import 'tenant_session.dart';
import 'tenant_session_controller.dart';
import 'tenant_staff_directory.dart';
import 'tenant_staff_invitation.dart';
import 'tenant_types.dart';

/// Narrow callable boundary for the enabled `updateStaffUser` mutation.
abstract interface class UpdateStaffUserCallable {
  Future<Object?> call(Map<String, Object?> payload);
}

/// Firebase adapter for `updateStaffUser`; validation remains above it.
final class FirebaseUpdateStaffUserCallable implements UpdateStaffUserCallable {
  FirebaseUpdateStaffUserCallable({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    final result = await _functions
        .httpsCallable('updateStaffUser')
        .call<Object?>(payload);
    return result.data;
  }
}

/// Normalized client input for editing one decoded canonical staff summary.
final class TenantStaffUpdateDraft {
  TenantStaffUpdateDraft._({
    required this.targetUid,
    required String name,
    required String phone,
    required this.role,
    required bool targetIsOwner,
  }) : name = normalizeTenantStaffInviteName(name),
       phone = normalizeTenantStaffInvitePhone(phone) {
    if (targetIsOwner ? role != TenantRole.owner : role == TenantRole.owner) {
      throw const FormatException('The requested staff role is invalid.');
    }
  }

  final String targetUid;
  final String name;
  final String phone;
  final TenantRole role;
}

/// One edit intent and its stable idempotency key.
final class TenantStaffUpdateIntent {
  const TenantStaffUpdateIntent._({
    required this.draft,
    required this.requestId,
  });

  final TenantStaffUpdateDraft draft;
  final String requestId;
}

/// Strictly decoded result from the `updateStaffUser` callable.
final class TenantStaffUpdateResult {
  const TenantStaffUpdateResult._({
    required this.tenantId,
    required this.uid,
    required this.role,
    required this.status,
  });

  factory TenantStaffUpdateResult.fromCallable(
    Object? value, {
    required String expectedTenantId,
    required String expectedUid,
    required TenantRole expectedRole,
    required MembershipStatus expectedStatus,
  }) {
    final data = _strictUpdateMap(value);
    if (data['tenantId'] != expectedTenantId) {
      throw const FormatException(
        'updateStaffUser returned a result for another tenant.',
      );
    }
    if (data['uid'] != expectedUid) {
      throw const FormatException(
        'updateStaffUser returned a result for another staff member.',
      );
    }
    try {
      validateTenantId(data['tenantId']! as String);
      validateTenantDocumentId(data['uid']! as String, fieldName: 'uid');
    } on ArgumentError {
      throw const FormatException('updateStaffUser returned invalid identity.');
    }
    final role = TenantRole.fromWire(data['role']);
    final status = MembershipStatus.fromWire(data['status']);
    if (role != expectedRole || status != expectedStatus) {
      throw const FormatException(
        'updateStaffUser returned an unexpected staff state.',
      );
    }
    return TenantStaffUpdateResult._(
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
final class TenantStaffUpdateGateway {
  TenantStaffUpdateGateway({
    required TenantSession session,
    required TenantStaffSummary target,
    required UpdateStaffUserCallable callable,
    TenantStaffRequestIdFactory? requestIdFactory,
  }) : _session = session,
       _target = target,
       _callable = callable,
       _requestIdFactory = requestIdFactory ?? _secureUpdateRequestId;

  static const allowedRoles = <TenantRole>[TenantRole.admin];

  final TenantSession _session;
  final TenantStaffSummary _target;
  final UpdateStaffUserCallable _callable;
  final TenantStaffRequestIdFactory _requestIdFactory;

  TenantStaffUpdateIntent createIntent({
    required String name,
    required String phone,
    required TenantRole role,
  }) {
    _requireAuthorizedSession();
    final requestId = _requestIdFactory();
    if (!_updateRequestIdPattern.hasMatch(requestId)) {
      throw StateError('The staff update request ID generator is invalid.');
    }
    return TenantStaffUpdateIntent._(
      draft: TenantStaffUpdateDraft._(
        targetUid: _target.uid,
        name: name,
        phone: phone,
        role: role,
        targetIsOwner: _target.isOwner,
      ),
      requestId: requestId,
    );
  }

  Future<TenantStaffUpdateResult> submit(TenantStaffUpdateIntent intent) async {
    _requireAuthorizedSession();
    final draft = intent.draft;
    if (draft.targetUid != _target.uid) {
      throw StateError('The edit intent belongs to another staff member.');
    }
    final response = await _callable.call(<String, Object?>{
      'tenantId': _session.tenantId,
      'uid': _target.uid,
      'name': draft.name,
      'phone': draft.phone,
      'role': draft.role.wireValue,
      'requestId': intent.requestId,
    });
    return TenantStaffUpdateResult.fromCallable(
      response,
      expectedTenantId: _session.tenantId,
      expectedUid: _target.uid,
      expectedRole: draft.role,
      expectedStatus: _target.status,
    );
  }

  void _requireAuthorizedSession() {
    if (!_session.canAccess(allowedRoles: allowedRoles)) {
      throw StateError('An owner or administrator session is required.');
    }
  }
}

/// Recoverable, single-flight editor for one decoded staff directory row.
final class TenantStaffUpdateForm extends StatefulWidget {
  const TenantStaffUpdateForm({
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
  final UpdateStaffUserCallable callable;
  final VoidCallback onSuccess;
  final VoidCallback onCancel;
  final TenantStaffRequestIdFactory? requestIdFactory;

  @override
  State<TenantStaffUpdateForm> createState() => _TenantStaffUpdateFormState();
}

final class _TenantStaffUpdateFormState extends State<TenantStaffUpdateForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late TenantRole _role;
  TenantStaffUpdateIntent? _intent;
  bool _submitting = false;
  String? _safeError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.target.name ?? '');
    _phoneController = TextEditingController(text: widget.target.phone ?? '');
    _role = widget.target.role;
  }

  @override
  void didUpdateWidget(covariant TenantStaffUpdateForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target.uid == widget.target.uid) return;
    _nameController.text = widget.target.name ?? '';
    _phoneController.text = widget.target.phone ?? '';
    _role = widget.target.role;
    _intent = null;
    _submitting = false;
    _safeError = null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
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
    if (!_isCurrent(controller, submittedTargetUid)) return;
    final gateway = TenantStaffUpdateGateway(
      session: widget.session,
      target: widget.target,
      callable: widget.callable,
      requestIdFactory: widget.requestIdFactory,
    );
    late final TenantStaffUpdateIntent intent;
    try {
      intent = _intent ??= gateway.createIntent(
        name: _nameController.text,
        phone: _phoneController.text,
        role: _role,
      );
    } catch (_) {
      if (!mounted || !_isCurrent(controller, submittedTargetUid)) return;
      setState(() => _safeError = 'Check the staff details and try again.');
      return;
    }
    setState(() {
      _submitting = true;
      _safeError = null;
    });
    try {
      await gateway.submit(intent);
    } catch (_) {
      if (!mounted || !_isCurrent(controller, submittedTargetUid)) return;
      setState(() {
        _submitting = false;
        _safeError = 'Staff details could not be updated. Please try again.';
      });
      return;
    }
    if (!mounted || !_isCurrent(controller, submittedTargetUid)) return;
    setState(() => _submitting = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Staff details updated.')));
    widget.onSuccess();
  }

  bool _isCurrent(
    TenantSessionController controller,
    String expectedTargetUid,
  ) {
    final current = controller.session;
    return widget.target.uid == expectedTargetUid &&
        current != null &&
        current.uid == widget.session.uid &&
        current.tenantId == widget.session.tenantId &&
        current.epoch == widget.session.epoch &&
        current.canAccess(allowedRoles: TenantStaffUpdateGateway.allowedRoles);
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _formKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Edit ${widget.target.displayName}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        TextFormField(
          key: const ValueKey('update-staff-name'),
          controller: _nameController,
          enabled: !_submitting,
          decoration: const InputDecoration(labelText: 'Name'),
          onChanged: (_) => _markIntentChanged(),
          validator: (value) {
            try {
              normalizeTenantStaffInviteName(value ?? '');
              return null;
            } on FormatException {
              return 'Enter a name of 100 characters or fewer.';
            }
          },
        ),
        TextFormField(
          key: const ValueKey('update-staff-phone'),
          controller: _phoneController,
          enabled: !_submitting,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Phone (optional)'),
          onChanged: (_) => _markIntentChanged(),
          validator: (value) {
            try {
              normalizeTenantStaffInvitePhone(value ?? '');
              return null;
            } on FormatException {
              return 'Enter a phone number of 32 characters or fewer.';
            }
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<TenantRole>(
          key: const ValueKey('update-staff-role'),
          initialValue: _role,
          decoration: const InputDecoration(labelText: 'Role'),
          items:
              (widget.target.isOwner
                      ? const [TenantRole.owner]
                      : const [
                          TenantRole.admin,
                          TenantRole.manager,
                          TenantRole.cashier,
                        ])
                  .map(
                    (role) => DropdownMenuItem<TenantRole>(
                      value: role,
                      child: Text(role.wireValue),
                    ),
                  )
                  .toList(),
          onChanged: _submitting || widget.target.isOwner
              ? null
              : (role) {
                  if (role == null || role == _role) return;
                  setState(() {
                    _role = role;
                    _intent = null;
                    _safeError = null;
                  });
                },
        ),
        if (_safeError != null) ...[
          const SizedBox(height: 12),
          Text(
            _safeError!,
            key: const ValueKey('update-staff-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              key: const ValueKey('update-staff-cancel'),
              onPressed: _submitting ? null : widget.onCancel,
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              key: const ValueKey('update-staff-submit'),
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_submitting ? 'Saving...' : 'Save changes'),
            ),
          ],
        ),
      ],
    ),
  );
}

Map<String, Object?> _strictUpdateMap(Object? value) {
  const keys = {'tenantId', 'uid', 'role', 'status'};
  if (value is! Map || value.length != keys.length) {
    throw const FormatException(
      'updateStaffUser response must contain the expected fields.',
    );
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String || !keys.contains(key)) {
      throw const FormatException(
        'updateStaffUser response must contain the expected fields.',
      );
    }
    result[key] = entry.value;
  }
  if (result['tenantId'] is! String || result['uid'] is! String) {
    throw const FormatException('updateStaffUser returned invalid identity.');
  }
  return result;
}

String _secureUpdateRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'update-${base64Url.encode(bytes).replaceAll('=', '')}';
}

final _updateRequestIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$');
