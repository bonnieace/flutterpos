import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../ui/scaffold.dart';
import '../ui/snackbar.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'tenant_id.dart';
import 'tenant_session.dart';
import 'tenant_session_controller.dart';
import 'tenant_staff_request_ticket.dart';
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
       _requestIdFactory = requestIdFactory ?? secureResendRequestId;

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
      throw StateError(
        'The invitation resend request ID generator is invalid.',
      );
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
    this.tickets,
  });

  final TenantSession session;
  final TenantStaffSummary target;
  final ResendStaffInvitationCallable callable;
  final VoidCallback onSuccess;
  final VoidCallback onCancel;
  final TenantStaffRequestIdFactory? requestIdFactory;

  /// Where this device remembers the request id of an unfinished resend.
  final TenantStaffRequestTicketSource? tickets;

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
    // **The flag is raised before the first `await`, not after it.**
    // Reading the device's ticket is asynchronous, and a second tap landing
    // while that read was in flight would find `_submitting` still false and
    // start a second submission.
    setState(() {
      _submitting = true;
      _safeError = null;
    });
    final requestId = await _resolveRequestId(submittedTargetUid);
    if (!mounted) return;
    final gateway = TenantStaffInvitationResendGateway(
      session: widget.session,
      target: widget.target,
      callable: widget.callable,
      requestIdFactory: () => requestId,
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
        _abandonSubmission();
        return;
      }
      setState(() {
        _submitting = false;
        _safeError = 'This staff invitation cannot be resent.';
      });
      return;
    }
    try {
      await gateway.submit(intent);
    } catch (error) {
      // The server re-read this actor's membership and disagreed with what
      // this session believes about itself. Ask for the session to be
      // re-read, so the next look at this screen shows what is actually
      // permitted rather than offering the same refused control again.
      if (isTenantStaffAuthorizationRefusal(error)) {
        controller.requestRevalidation();
      }
      if (!mounted ||
          !_isCurrent(
            controller,
            submittedTargetUid,
            submittedStatus,
            submittedInvitationStatus,
          )) {
        _abandonSubmission();
        return;
      }
      setState(() {
        _submitting = false;
        _safeError = 'Invitation could not be resent. Please try again.';
      });
      return;
    }
    // Cleared on the answer, and only on the answer: a request with no
    // reply keeps its ticket so the next press finishes it.
    await _clearRequestTicket(submittedTargetUid);
    if (!mounted ||
        !_isCurrent(
          controller,
          submittedTargetUid,
          submittedStatus,
          submittedInvitationStatus,
        )) {
      _abandonSubmission();
      return;
    }
    setState(() => _submitting = false);
    showAppSnackBar(
      context,
      AppNotice.confirmed('Invitation resent to ${widget.target.email}.'),
    );
    widget.onSuccess();
  }

  /// Ends the submission locally when its result is no longer this form's to
  /// apply.
  ///
  /// **A discarded result must still release the button.** These guards existed
  /// to stop a stale answer being applied after the session moved under it, and
  /// they returned without clearing `_submitting` - so the form kept its
  /// spinner for as long as it stayed on screen, over a submission that was
  /// never coming back. Harmless while a session only changed on a switch that
  /// tore the route down anyway; reachable the moment anything refreshes a live
  /// session, which is what noticing a remote role change is for.
  void _abandonSubmission() {
    if (!mounted || !_submitting) return;
    setState(() => _submitting = false);
  }

  /// Fingerprinted on the field `issuance.ts` hashes: `{targetUid}`.
  ///
  /// **A resend is meant to be repeatable, and still is.** The ticket is
  /// cleared the moment the server answers, so reopening the form and pressing
  /// again is a second email. What it stops is the other case: an answer that
  /// never arrived, where pressing again should finish the first send rather
  /// than start a second.
  Future<String> _resolveRequestId(String targetUid) async {
    final tickets = widget.tickets;
    final mint = widget.requestIdFactory ?? secureResendRequestId;
    if (tickets == null) return mint();
    return tickets.resolve(
      uid: widget.session.uid,
      tenantId: widget.session.tenantId,
      operation: _ticketOperation,
      target: targetUid,
      fingerprint: tenantStaffRequestFingerprint(<String, Object?>{
        'targetUid': targetUid,
      }),
      mint: mint,
    );
  }

  Future<void> _clearRequestTicket(String targetUid) async {
    await widget.tickets?.clear(
      uid: widget.session.uid,
      tenantId: widget.session.tenantId,
      operation: _ticketOperation,
      target: targetUid,
    );
  }

  static const _ticketOperation = 'resendStaffInvitation';

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
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading('Resend invitation to ${widget.target.displayName}?'),
        SizedBox(height: tokens.spacing.s8),
        Text('A new invitation will be queued for ${widget.target.email}.'),
        if (_safeError != null) ...[
          SizedBox(height: tokens.spacing.s12),
          Callout(
            key: const ValueKey('resend-staff-invitation-error'),
            // A refusal, named as one rather than painted red: the write
            // was attempted and nothing changed. Before this the whole of
            // the status was the colour, which is the case §9 rules out.
            status: AppNotice.refused(_safeError!).status,
            message: _safeError!,
          ),
        ],
        SizedBox(height: tokens.spacing.s16),
        // **Two buttons, stacked, each the width of the sheet**, at the
        // developer's direction on 2026-09-22. Every form on this surface now
        // ends the same way the record-expense sheet always has: the committing
        // action on top, the way out under it. `AppActionRow`'s horizontal pair
        // is for a record inside a page; a sheet is one errand with one answer,
        // and a thumb reaching the bottom of a phone should not have to pick a
        // half of the row.
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AppButton(
              key: const ValueKey('resend-staff-invitation-confirm'),
              label: 'Confirm resend',
              icon: Icons.forward_to_inbox_outlined,
              tier: AppButtonTier.primary,
              loading: _submitting,
              expand: true,
              onPressed: _submit,
            ),
            SizedBox(height: tokens.spacing.s12),
            AppButton(
              key: const ValueKey('resend-staff-invitation-cancel'),
              label: 'Cancel',
              expand: true,
              onPressed: _submitting ? null : widget.onCancel,
            ),
          ],
        ),
      ],
    );
  }
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

/// Mints one request id. Public so the ticket store can use the same
/// minter the gateway would have.
String secureResendRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'resend-${base64Url.encode(bytes).replaceAll('=', '')}';
}

final _resendRequestIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$');
