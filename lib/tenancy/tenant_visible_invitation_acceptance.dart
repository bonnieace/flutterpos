import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../ui/scaffold.dart';
import '../ui/snackbar.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'invitation_acceptance_failure.dart';
import 'tenant_id.dart';
import 'tenant_membership.dart';
import 'tenant_membership_labels.dart';
import 'tenant_staff_directory.dart';
import 'tenant_types.dart';

typedef TenantVisibleInvitationRequestIdFactory = String Function();
typedef TenantVisibleInvitationCurrentCheck = bool Function();

/// The narrow callable boundary for accepting an already visible invitation.
abstract interface class AcceptVisibleTenantInvitationCallable {
  Future<Object?> call(Map<String, Object?> payload);
}

/// Firebase adapter for `acceptVisibleTenantInvitation`; response validation
/// remains above it.
final class FirebaseAcceptVisibleTenantInvitationCallable
    implements AcceptVisibleTenantInvitationCallable {
  FirebaseAcceptVisibleTenantInvitationCallable({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    try {
      final result = await _functions
          .httpsCallable('acceptVisibleTenantInvitation')
          .call<Object?>(payload);
      return result.data;
    } on FirebaseFunctionsException catch (error) {
      throw InvitationAcceptanceException(
        error.code,
        violation: invitationAcceptanceViolationFromDetails(error.details),
      );
    }
  }
}

/// Caller identity facts available to the visible invitation flow.
final class TenantVisibleInvitationIdentity {
  factory TenantVisibleInvitationIdentity({
    required String uid,
    required bool emailVerified,
    required bool globallyActive,
  }) {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      throw ArgumentError.value(uid, 'uid', 'Cannot be empty.');
    }
    return TenantVisibleInvitationIdentity._(
      uid: normalizedUid,
      emailVerified: emailVerified,
      globallyActive: globallyActive,
    );
  }

  const TenantVisibleInvitationIdentity._({
    required this.uid,
    required this.emailVerified,
    required this.globallyActive,
  });

  final String uid;
  final bool emailVerified;
  final bool globallyActive;

  bool get canAcceptVisibleInvitation => emailVerified && globallyActive;
}

/// One acceptance intent and its stable idempotency key.
final class TenantVisibleInvitationAcceptanceIntent {
  const TenantVisibleInvitationAcceptanceIntent._({
    required this.tenantId,
    required this.uid,
    required this.requestId,
  });

  final String tenantId;
  final String uid;
  final String requestId;
}

/// Strictly decoded result from `acceptVisibleTenantInvitation`.
final class TenantVisibleInvitationAcceptanceResult {
  const TenantVisibleInvitationAcceptanceResult._({
    required this.tenantId,
    required this.uid,
    required this.role,
    required this.membershipStatus,
    required this.invitationStatus,
  });

  factory TenantVisibleInvitationAcceptanceResult.fromCallable(
    Object? value, {
    required String expectedTenantId,
    required String expectedUid,
    required TenantRole expectedRole,
  }) {
    final data = _strictAcceptanceMap(
      value,
      label: 'acceptVisibleTenantInvitation response',
      keys: const {
        'tenantId',
        'uid',
        'membershipStatus',
        'invitationStatus',
        'role',
      },
    );
    if (data['tenantId'] != expectedTenantId) {
      throw const FormatException(
        'acceptVisibleTenantInvitation returned another tenant.',
      );
    }
    if (data['uid'] != expectedUid) {
      throw const FormatException(
        'acceptVisibleTenantInvitation returned another user.',
      );
    }
    late final String tenantId;
    late final String uid;
    late final TenantRole role;
    late final MembershipStatus membershipStatus;
    try {
      tenantId = validateTenantId(data['tenantId']! as String);
      uid = validateTenantDocumentId(data['uid']! as String, fieldName: 'uid');
      role = TenantRole.fromWire(data['role']);
      membershipStatus = MembershipStatus.fromWire(data['membershipStatus']);
    } on ArgumentError {
      throw const FormatException(
        'acceptVisibleTenantInvitation returned invalid identifiers.',
      );
    }
    if (role != expectedRole) {
      throw const FormatException(
        'acceptVisibleTenantInvitation returned another role.',
      );
    }
    if (membershipStatus != MembershipStatus.active ||
        data['invitationStatus'] !=
            TenantStaffInvitationStatus.accepted.wireValue) {
      throw const FormatException(
        'acceptVisibleTenantInvitation returned an invalid accepted state.',
      );
    }
    return TenantVisibleInvitationAcceptanceResult._(
      tenantId: tenantId,
      uid: uid,
      role: role,
      membershipStatus: membershipStatus,
      invitationStatus: TenantStaffInvitationStatus.accepted,
    );
  }

  final String tenantId;
  final String uid;
  final TenantRole role;
  final MembershipStatus membershipStatus;
  final TenantStaffInvitationStatus invitationStatus;
}

/// Identity- and membership-bound gateway with no arbitrary tenant input.
final class TenantVisibleInvitationAcceptanceGateway {
  TenantVisibleInvitationAcceptanceGateway({
    required TenantVisibleInvitationIdentity identity,
    required TenantMembership membership,
    required AcceptVisibleTenantInvitationCallable callable,
    TenantVisibleInvitationRequestIdFactory? requestIdFactory,
  }) : _identity = identity,
       _membership = membership,
       _callable = callable,
       _requestIdFactory =
           requestIdFactory ?? _secureVisibleAcceptanceRequestId;

  final TenantVisibleInvitationIdentity _identity;
  final TenantMembership _membership;
  final AcceptVisibleTenantInvitationCallable _callable;
  final TenantVisibleInvitationRequestIdFactory _requestIdFactory;

  static bool canAccept({
    required TenantVisibleInvitationIdentity identity,
    required TenantMembership membership,
  }) {
    if (!identity.canAcceptVisibleInvitation) return false;
    if (membership.isOwner || membership.role == TenantRole.owner) {
      return false;
    }
    return membership.canonicalTenantExists &&
        membership.canonicalMembershipExists &&
        membership.tenantStatus == TenantStatus.active &&
        membership.membershipStatus == MembershipStatus.pending &&
        (membership.invitationStatus ==
                TenantStaffInvitationStatus.pending.wireValue ||
            membership.invitationStatus ==
                TenantStaffInvitationStatus.sent.wireValue);
  }

  TenantVisibleInvitationAcceptanceIntent createIntent() {
    if (!canAccept(identity: _identity, membership: _membership)) {
      throw const FormatException(
        'This visible tenant invitation cannot be accepted.',
      );
    }
    final requestId = _requestIdFactory();
    if (!_visibleAcceptanceRequestIdPattern.hasMatch(requestId)) {
      throw StateError(
        'The visible invitation acceptance request ID generator is invalid.',
      );
    }
    return TenantVisibleInvitationAcceptanceIntent._(
      tenantId: _membership.tenantId,
      uid: _identity.uid,
      requestId: requestId,
    );
  }

  Future<TenantVisibleInvitationAcceptanceResult> submit(
    TenantVisibleInvitationAcceptanceIntent intent,
  ) async {
    if (intent.tenantId != _membership.tenantId ||
        intent.uid != _identity.uid) {
      throw StateError(
        'The visible invitation acceptance intent belongs elsewhere.',
      );
    }
    if (!canAccept(identity: _identity, membership: _membership)) {
      throw StateError('This visible tenant invitation cannot be accepted.');
    }
    final response = await _callable.call(<String, Object?>{
      'tenantId': _membership.tenantId,
      'requestId': intent.requestId,
    });
    return TenantVisibleInvitationAcceptanceResult.fromCallable(
      response,
      expectedTenantId: _membership.tenantId,
      expectedUid: _identity.uid,
      expectedRole: _membership.role,
    );
  }
}

/// Explicit in-app confirmation for one visible pending tenant invitation.
final class TenantVisibleInvitationAcceptanceForm extends StatefulWidget {
  const TenantVisibleInvitationAcceptanceForm({
    super.key,
    required this.identity,
    required this.membership,
    required this.callable,
    required this.onSuccess,
    required this.onCancel,
    this.requestIdFactory,
    this.isCurrent,
  });

  final TenantVisibleInvitationIdentity identity;
  final TenantMembership membership;
  final AcceptVisibleTenantInvitationCallable callable;
  final VoidCallback onSuccess;
  final VoidCallback onCancel;
  final TenantVisibleInvitationRequestIdFactory? requestIdFactory;
  final TenantVisibleInvitationCurrentCheck? isCurrent;

  @override
  State<TenantVisibleInvitationAcceptanceForm> createState() =>
      _TenantVisibleInvitationAcceptanceFormState();
}

final class _TenantVisibleInvitationAcceptanceFormState
    extends State<TenantVisibleInvitationAcceptanceForm> {
  TenantVisibleInvitationAcceptanceIntent? _intent;
  bool _submitting = false;
  String? _safeError;

  @override
  void didUpdateWidget(
    covariant TenantVisibleInvitationAcceptanceForm oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity.uid == widget.identity.uid &&
        oldWidget.identity.emailVerified == widget.identity.emailVerified &&
        oldWidget.identity.globallyActive == widget.identity.globallyActive &&
        oldWidget.membership.tenantId == widget.membership.tenantId &&
        oldWidget.membership.membershipStatus ==
            widget.membership.membershipStatus &&
        oldWidget.membership.invitationStatus ==
            widget.membership.invitationStatus) {
      return;
    }
    _intent = null;
    _submitting = false;
    _safeError = null;
  }

  Future<void> _submit() async {
    if (_submitting || !_isCurrent()) return;
    final submittedUid = widget.identity.uid;
    final submittedTenantId = widget.membership.tenantId;
    final submittedMembershipStatus = widget.membership.membershipStatus;
    final submittedInvitationStatus = widget.membership.invitationStatus;
    final gateway = TenantVisibleInvitationAcceptanceGateway(
      identity: widget.identity,
      membership: widget.membership,
      callable: widget.callable,
      requestIdFactory: widget.requestIdFactory,
    );
    late final TenantVisibleInvitationAcceptanceIntent intent;
    try {
      intent = _intent ??= gateway.createIntent();
    } catch (_) {
      if (!mounted ||
          !_isStillSubmitted(
            submittedUid,
            submittedTenantId,
            submittedMembershipStatus,
            submittedInvitationStatus,
          )) {
        return;
      }
      setState(() => _safeError = 'This invitation cannot be accepted here.');
      return;
    }
    setState(() {
      _submitting = true;
      _safeError = null;
    });
    try {
      await gateway.submit(intent);
    } catch (error) {
      if (!mounted ||
          !_isStillSubmitted(
            submittedUid,
            submittedTenantId,
            submittedMembershipStatus,
            submittedInvitationStatus,
          )) {
        return;
      }
      setState(() {
        _submitting = false;
        // The refusal is carried here rather than discarded. `catch (_)` was
        // the defect: it threw away a code that says whether retrying can ever
        // work, leaving one sentence that told every refused user to try again.
        _safeError = invitationAcceptanceSafeError(
          error,
          mode: InvitationAcceptanceMode.visible,
        );
      });
      return;
    }
    if (!mounted ||
        !_isStillSubmitted(
          submittedUid,
          submittedTenantId,
          submittedMembershipStatus,
          submittedInvitationStatus,
        )) {
      return;
    }
    setState(() => _submitting = false);
    showAppSnackBar(
      context,
      AppNotice.confirmed(
        'Invitation accepted for ${widget.membership.tenantName}.',
      ),
    );
    widget.onSuccess();
  }

  bool _isStillSubmitted(
    String expectedUid,
    String expectedTenantId,
    MembershipStatus expectedMembershipStatus,
    String? expectedInvitationStatus,
  ) =>
      widget.identity.uid == expectedUid &&
      widget.membership.tenantId == expectedTenantId &&
      widget.membership.membershipStatus == expectedMembershipStatus &&
      widget.membership.invitationStatus == expectedInvitationStatus &&
      _isCurrent();

  bool _isCurrent() => widget.isCurrent?.call() ?? true;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading('Accept invitation to ${widget.membership.tenantName}?'),
        SizedBox(height: tokens.spacing.s8),
        Text('Invited role: ${tenantRoleLabel(widget.membership.role)}'),
        if (_safeError != null) ...[
          SizedBox(height: tokens.spacing.s12),
          Callout(
            key: const ValueKey('accept-visible-invitation-error'),
            // A refusal, named as one rather than painted red: the write
            // was attempted and nothing changed. Before this the whole of
            // the status was the colour, which is the case §9 rules out.
            status: AppNotice.refused(_safeError!).status,
            message: _safeError!,
          ),
        ],
        SizedBox(height: tokens.spacing.s16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              key: const ValueKey('accept-visible-invitation-cancel'),
              label: 'Cancel',
              tier: AppButtonTier.tertiary,
              onPressed: _submitting ? null : widget.onCancel,
            ),
            SizedBox(width: tokens.spacing.s8),
            AppButton(
              key: const ValueKey('accept-visible-invitation-confirm'),
              label: 'Accept invitation',
              icon: Icons.check_circle_outline,
              tier: AppButtonTier.primary,
              loading: _submitting,
              onPressed: _submit,
            ),
          ],
        ),
      ],
    );
  }
}

Map<String, Object?> _strictAcceptanceMap(
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

String _secureVisibleAcceptanceRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'accept-visible-${base64Url.encode(bytes).replaceAll('=', '')}';
}

final _visibleAcceptanceRequestIdPattern = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$',
);
