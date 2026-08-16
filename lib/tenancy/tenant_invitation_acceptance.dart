import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'invitation_acceptance_failure.dart';
import 'tenant_id.dart';
import 'tenant_types.dart';

typedef TenantInvitationAcceptanceRequestIdFactory = String Function();
typedef TenantInvitationAcceptanceCurrentCheck = bool Function();

/// A validated invitation proof carried by a staff invitation action URL.
final class TenantInvitationLink {
  const TenantInvitationLink._({
    required this.tenantId,
    required this.invitedUid,
    required this.invitationVersion,
    required this.invitationToken,
  });

  /// Returns `null` only when the URI contains no invitation fields at all.
  /// A partial or malformed invitation URI fails closed.
  static TenantInvitationLink? fromUriIfPresent(Uri uri) {
    const fields = {'tenantId', 'uid', 'invitationVersion', 'invitationToken'};
    final present = fields.where(uri.queryParametersAll.containsKey).length;
    if (present == 0) return null;
    if (present != fields.length || uri.scheme.toLowerCase() != 'https') {
      throw const FormatException('The invitation link is invalid.');
    }

    String singleValue(String field) {
      final values = uri.queryParametersAll[field];
      if (values == null || values.length != 1 || values.single.isEmpty) {
        throw const FormatException('The invitation link is invalid.');
      }
      return values.single;
    }

    final rawTenantId = singleValue('tenantId');
    final rawUid = singleValue('uid');
    final rawVersion = singleValue('invitationVersion');
    final token = singleValue('invitationToken');
    final version = int.tryParse(rawVersion);
    if (version == null ||
        version < 1 ||
        version > 9007199254740991 ||
        !_invitationTokenPattern.hasMatch(token)) {
      throw const FormatException('The invitation link is invalid.');
    }
    try {
      return TenantInvitationLink._(
        tenantId: validateTenantId(rawTenantId),
        invitedUid: validateTenantDocumentId(rawUid, fieldName: 'uid'),
        invitationVersion: version,
        invitationToken: token,
      );
    } on ArgumentError {
      throw const FormatException('The invitation link is invalid.');
    }
  }

  final String tenantId;
  final String invitedUid;
  final int invitationVersion;
  final String invitationToken;

  bool hasSameProof(TenantInvitationLink other) =>
      tenantId == other.tenantId &&
      invitedUid == other.invitedUid &&
      invitationVersion == other.invitationVersion &&
      invitationToken == other.invitationToken;
}

/// The narrow callable boundary for versioned invitation-proof acceptance.
abstract interface class AcceptTenantInvitationCallable {
  Future<Object?> call(Map<String, Object?> payload);
}

/// Firebase adapter for `acceptTenantInvitation`; response validation remains
/// above it.
final class FirebaseAcceptTenantInvitationCallable
    implements AcceptTenantInvitationCallable {
  FirebaseAcceptTenantInvitationCallable({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    try {
      final result = await _functions
          .httpsCallable('acceptTenantInvitation')
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

/// One acceptance intent and its stable idempotency key.
final class TenantInvitationAcceptanceIntent {
  const TenantInvitationAcceptanceIntent._({
    required this.tenantId,
    required this.uid,
    required this.invitationVersion,
    required this.invitationToken,
    required this.requestId,
  });

  final String tenantId;
  final String uid;
  final int invitationVersion;
  final String invitationToken;
  final String requestId;
}

/// Strictly decoded result from `acceptTenantInvitation`.
final class TenantInvitationAcceptanceResult {
  const TenantInvitationAcceptanceResult._({
    required this.tenantId,
    required this.uid,
    required this.role,
    required this.membershipStatus,
    required this.invitationStatus,
  });

  factory TenantInvitationAcceptanceResult.fromCallable(
    Object? value, {
    required String expectedTenantId,
    required String expectedUid,
    TenantRole? expectedRole,
  }) {
    final data = _strictInvitationAcceptanceMap(value);
    if (data['tenantId'] != expectedTenantId || data['uid'] != expectedUid) {
      throw const FormatException(
        'acceptTenantInvitation returned another invitation target.',
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
    } on (ArgumentError, FormatException) {
      throw const FormatException(
        'acceptTenantInvitation returned invalid membership data.',
      );
    }
    if (role == TenantRole.owner ||
        (expectedRole != null && role != expectedRole) ||
        membershipStatus != MembershipStatus.active ||
        data['invitationStatus'] != 'accepted') {
      throw const FormatException(
        'acceptTenantInvitation returned an invalid accepted state.',
      );
    }
    return TenantInvitationAcceptanceResult._(
      tenantId: tenantId,
      uid: uid,
      role: role,
      membershipStatus: membershipStatus,
      invitationStatus: 'accepted',
    );
  }

  final String tenantId;
  final String uid;
  final TenantRole role;
  final MembershipStatus membershipStatus;
  final String invitationStatus;
}

/// Auth- and proof-bound gateway with no arbitrary tenant or target input.
final class TenantInvitationAcceptanceGateway {
  TenantInvitationAcceptanceGateway({
    required String currentUid,
    required TenantInvitationLink invitationLink,
    required AcceptTenantInvitationCallable callable,
    TenantRole? expectedRole,
    TenantInvitationAcceptanceRequestIdFactory? requestIdFactory,
  }) : _currentUid = validateTenantDocumentId(
         currentUid.trim(),
         fieldName: 'currentUid',
       ),
       _invitationLink = invitationLink,
       _callable = callable,
       _expectedRole = expectedRole,
       _requestIdFactory =
           requestIdFactory ?? _secureInvitationAcceptanceRequestId;

  final String _currentUid;
  final TenantInvitationLink _invitationLink;
  final AcceptTenantInvitationCallable _callable;
  final TenantRole? _expectedRole;
  final TenantInvitationAcceptanceRequestIdFactory _requestIdFactory;

  bool get belongsToCurrentUser => _currentUid == _invitationLink.invitedUid;

  TenantInvitationAcceptanceIntent createIntent() {
    if (!belongsToCurrentUser) {
      throw const FormatException(
        'This invitation belongs to another authenticated user.',
      );
    }
    final requestId = _requestIdFactory();
    if (!_invitationAcceptanceRequestIdPattern.hasMatch(requestId)) {
      throw StateError('The invitation acceptance request ID is invalid.');
    }
    return TenantInvitationAcceptanceIntent._(
      tenantId: _invitationLink.tenantId,
      uid: _currentUid,
      invitationVersion: _invitationLink.invitationVersion,
      invitationToken: _invitationLink.invitationToken,
      requestId: requestId,
    );
  }

  Future<TenantInvitationAcceptanceResult> submit(
    TenantInvitationAcceptanceIntent intent,
  ) async {
    if (!belongsToCurrentUser ||
        intent.tenantId != _invitationLink.tenantId ||
        intent.uid != _currentUid ||
        intent.invitationVersion != _invitationLink.invitationVersion ||
        intent.invitationToken != _invitationLink.invitationToken) {
      throw StateError('The invitation acceptance intent belongs elsewhere.');
    }
    final response = await _callable.call(<String, Object?>{
      'tenantId': _invitationLink.tenantId,
      'invitationVersion': _invitationLink.invitationVersion,
      'invitationToken': _invitationLink.invitationToken,
      'requestId': intent.requestId,
    });
    return TenantInvitationAcceptanceResult.fromCallable(
      response,
      expectedTenantId: _invitationLink.tenantId,
      expectedUid: _currentUid,
      expectedRole: _expectedRole,
    );
  }
}

/// Explicit confirmation for one parsed versioned invitation proof.
final class TenantInvitationAcceptanceForm extends StatefulWidget {
  const TenantInvitationAcceptanceForm({
    super.key,
    required this.currentUid,
    required this.invitationLink,
    required this.callable,
    required this.onSuccess,
    required this.onCancel,
    this.tenantName,
    this.invitedRole,
    this.requestIdFactory,
    this.isCurrent,
  });

  final String currentUid;
  final TenantInvitationLink invitationLink;
  final AcceptTenantInvitationCallable callable;
  final VoidCallback onSuccess;
  final VoidCallback onCancel;
  final String? tenantName;
  final TenantRole? invitedRole;
  final TenantInvitationAcceptanceRequestIdFactory? requestIdFactory;
  final TenantInvitationAcceptanceCurrentCheck? isCurrent;

  @override
  State<TenantInvitationAcceptanceForm> createState() =>
      _TenantInvitationAcceptanceFormState();
}

final class _TenantInvitationAcceptanceFormState
    extends State<TenantInvitationAcceptanceForm> {
  TenantInvitationAcceptanceIntent? _intent;
  bool _submitting = false;
  String? _safeError;

  @override
  void didUpdateWidget(covariant TenantInvitationAcceptanceForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUid == widget.currentUid &&
        oldWidget.invitationLink.hasSameProof(widget.invitationLink) &&
        oldWidget.invitedRole == widget.invitedRole) {
      return;
    }
    _intent = null;
    _submitting = false;
    _safeError = null;
  }

  Future<void> _submit() async {
    if (_submitting || !_isCurrent()) return;
    final submittedUid = widget.currentUid;
    final submittedLink = widget.invitationLink;
    final gateway = TenantInvitationAcceptanceGateway(
      currentUid: submittedUid,
      invitationLink: submittedLink,
      callable: widget.callable,
      expectedRole: widget.invitedRole,
      requestIdFactory: widget.requestIdFactory,
    );
    late final TenantInvitationAcceptanceIntent intent;
    try {
      intent = _intent ??= gateway.createIntent();
    } catch (_) {
      if (!mounted || !_isStillSubmitted(submittedUid, submittedLink)) return;
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
      if (!mounted || !_isStillSubmitted(submittedUid, submittedLink)) return;
      setState(() {
        _submitting = false;
        // See the visible acceptance form: `catch (_)` discarded the one thing
        // that decides whether a retry can ever succeed.
        _safeError = invitationAcceptanceSafeError(
          error,
          mode: InvitationAcceptanceMode.token,
        );
      });
      return;
    }
    if (!mounted || !_isStillSubmitted(submittedUid, submittedLink)) return;
    setState(() => _submitting = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Invitation accepted.')));
    widget.onSuccess();
  }

  bool _isStillSubmitted(String expectedUid, TenantInvitationLink expected) =>
      widget.currentUid == expectedUid &&
      widget.invitationLink.hasSameProof(expected) &&
      _isCurrent();

  bool _isCurrent() => widget.isCurrent?.call() ?? true;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final tenantLabel = widget.tenantName?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tenantLabel == null || tenantLabel.isEmpty
              ? 'Accept this business invitation?'
              : 'Accept invitation to $tenantLabel?',
          style: tokens.typography.titleMedium.copyWith(
            color: tokens.colors.text.primary,
          ),
        ),
        if (widget.invitedRole != null) ...[
          const SizedBox(height: 8),
          Text('Invited role: ${widget.invitedRole!.wireValue}'),
        ],
        const SizedBox(height: 8),
        const Text(
          'Continue only if you expected this invitation. The link can be used '
          'only by the invited account.',
        ),
        if (_safeError != null) ...[
          const SizedBox(height: 12),
          Callout(
            key: const ValueKey('accept-token-invitation-error'),
            // A refusal, named as one rather than painted red: the write
            // was attempted and nothing changed. Before this the whole of
            // the status was the colour, which is the case §9 rules out.
            status: AppNotice.refused(_safeError!).status,
            message: _safeError!,
          ),
        ],
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              key: const ValueKey('accept-token-invitation-cancel'),
              label: 'Not now',
              tier: AppButtonTier.tertiary,
              onPressed: _submitting ? null : widget.onCancel,
            ),
            const SizedBox(width: 8),
            AppButton(
              key: const ValueKey('accept-token-invitation-confirm'),
              label: 'Accept invitation',
              icon: Icons.mark_email_read_outlined,
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

Map<String, Object?> _strictInvitationAcceptanceMap(Object? value) {
  const keys = {
    'tenantId',
    'uid',
    'role',
    'membershipStatus',
    'invitationStatus',
  };
  if (value is! Map || value.length != keys.length) {
    throw const FormatException(
      'acceptTenantInvitation must return the expected fields.',
    );
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String || !keys.contains(entry.key)) {
      throw const FormatException(
        'acceptTenantInvitation must return the expected fields.',
      );
    }
    result[entry.key! as String] = entry.value;
  }
  return result;
}

String _secureInvitationAcceptanceRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'accept-token-${base64Url.encode(bytes).replaceAll('=', '')}';
}

final _invitationTokenPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');
final _invitationAcceptanceRequestIdPattern = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$',
);
