import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../ui/fields.dart';
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
       _requestIdFactory = requestIdFactory ?? secureCancellationRequestId;

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
    this.tickets,
  });

  final TenantSession session;
  final TenantStaffSummary target;
  final CancelTenantInvitationCallable callable;
  final VoidCallback onSuccess;
  final VoidCallback onCancel;
  final TenantStaffRequestIdFactory? requestIdFactory;

  /// Where this device remembers the request id of an unfinished cancellation.
  final TenantStaffRequestTicketSource? tickets;

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
    // **The flag is raised before the first `await`, not after it.**
    // Reading the device's ticket is asynchronous, and a second tap landing
    // while that read was in flight would find `_submitting` still false and
    // start a second submission.
    setState(() {
      _submitting = true;
      _reasonError = null;
      _safeError = null;
    });
    final requestId = await _resolveRequestId(submittedTargetUid);
    if (!mounted) return;
    final gateway = TenantStaffInvitationCancellationGateway(
      session: widget.session,
      target: widget.target,
      callable: widget.callable,
      requestIdFactory: () => requestId,
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
        _abandonSubmission();
        return;
      }
      setState(() {
        _submitting = false;
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
        _abandonSubmission();
        return;
      }
      setState(() {
        _submitting = false;
        _reasonError = null;
        _safeError = 'This staff invitation cannot be cancelled.';
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
        _safeError = 'Invitation could not be cancelled. Please try again.';
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
      AppNotice.confirmed('Invitation for ${widget.target.email} cancelled.'),
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

  /// Fingerprinted on the fields `issuance.ts` hashes: `{targetUid, reason}`.
  Future<String> _resolveRequestId(String targetUid) async {
    final tickets = widget.tickets;
    final mint = widget.requestIdFactory ?? secureCancellationRequestId;
    if (tickets == null) return mint();
    return tickets.resolve(
      uid: widget.session.uid,
      tenantId: widget.session.tenantId,
      operation: _ticketOperation,
      target: targetUid,
      fingerprint: tenantStaffRequestFingerprint(<String, Object?>{
        'targetUid': targetUid,
        'reason': _reasonController.text.trim(),
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

  static const _ticketOperation = 'cancelTenantInvitation';

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
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading('Cancel invitation for ${widget.target.displayName}?'),
        SizedBox(height: tokens.spacing.s8),
        const Text(
          'This removes the pending membership and invalidates its invitation.',
        ),
        SizedBox(height: tokens.spacing.s12),
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
          SizedBox(height: tokens.spacing.s4),
          Callout(
            key: const ValueKey('cancel-staff-invitation-error'),
            // A refusal, named as one rather than painted red: the write
            // was attempted and nothing changed. Before this the whole of
            // the status was the colour, which is the case §9 rules out.
            status: AppNotice.refused(_safeError!).status,
            message: _safeError!,
          ),
        ],
        SizedBox(height: tokens.spacing.s12),
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
              expand: true,
              onPressed: _submit,
            ),
            SizedBox(height: tokens.spacing.s12),
            AppButton(
              key: const ValueKey('cancel-staff-invitation-dismiss'),
              label: 'Keep invitation',
              expand: true,
              onPressed: _submitting ? null : widget.onCancel,
            ),
          ],
        ),
      ],
    );
  }
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

/// Mints one request id. Public so the ticket store can use the same
/// minter the gateway would have.
String secureCancellationRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'cancel-${base64Url.encode(bytes).replaceAll('=', '')}';
}

final _cancellationRequestIdPattern = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$',
);
