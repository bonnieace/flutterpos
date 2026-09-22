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

  /// Decodes one `setStaffStatus` response.
  ///
  /// **Only the field this mutation set is checked against an expectation.**
  /// The mirror image of the defect in `TenantStaffUpdateResult`: this required
  /// the returned `role` to equal the one on the directory row, and
  /// `setStaffStatus` neither writes the role nor promises it has not moved. A
  /// colleague changing somebody's role while this confirmation was open turned
  /// a committed deactivation into a permanent failure message.
  factory TenantStaffStatusResult.fromCallable(
    Object? value, {
    required String expectedTenantId,
    required String expectedUid,
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
    if (status != expectedStatus) {
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
       _requestIdFactory = requestIdFactory ?? secureStatusRequestId;

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
    this.tickets,
  });

  final TenantSession session;
  final TenantStaffSummary target;
  final SetStaffStatusCallable callable;
  final VoidCallback onSuccess;
  final VoidCallback onCancel;
  final TenantStaffRequestIdFactory? requestIdFactory;

  /// Where this device remembers the request id of an unfinished change.
  final TenantStaffRequestTicketSource? tickets;

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
    // **The flag is raised before the first `await`, not after it.**
    // Reading the device's ticket is asynchronous, and a second tap landing
    // while that read was in flight would find `_submitting` still false and
    // start a second submission.
    setState(() {
      _submitting = true;
      _safeError = null;
    });
    final requestId = await _resolveRequestId(submittedTargetUid);
    if (!mounted ||
        !_isCurrent(controller, submittedTargetUid, submittedCurrentStatus)) {
      _abandonSubmission();
      return;
    }
    final gateway = TenantStaffStatusGateway(
      session: widget.session,
      target: widget.target,
      callable: widget.callable,
      requestIdFactory: () => requestId,
    );
    late final TenantStaffStatusIntent intent;
    try {
      intent = _intent ??= gateway.createIntent(targetStatus: _targetStatus);
    } catch (_) {
      if (!mounted ||
          !_isCurrent(controller, submittedTargetUid, submittedCurrentStatus)) {
        _abandonSubmission();
        return;
      }
      setState(() {
        _submitting = false;
        _safeError = 'This staff status cannot be changed.';
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
          !_isCurrent(controller, submittedTargetUid, submittedCurrentStatus)) {
        _abandonSubmission();
        return;
      }
      setState(() {
        _submitting = false;
        _safeError = 'Staff status could not be changed. Please try again.';
      });
      return;
    }
    await _clearRequestTicket(submittedTargetUid);
    if (!mounted ||
        !_isCurrent(controller, submittedTargetUid, submittedCurrentStatus)) {
      _abandonSubmission();
      return;
    }
    setState(() => _submitting = false);
    showAppSnackBar(
      context,
      AppNotice.confirmed('Staff member ${_targetStatus.wireValue}.'),
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

  /// Fingerprinted on the fields `membership.ts` hashes: `{targetUid, status}`.
  Future<String> _resolveRequestId(String targetUid) async {
    final tickets = widget.tickets;
    final mint = widget.requestIdFactory ?? secureStatusRequestId;
    if (tickets == null) return mint();
    return tickets.resolve(
      uid: widget.session.uid,
      tenantId: widget.session.tenantId,
      operation: _ticketOperation,
      target: targetUid,
      fingerprint: tenantStaffRequestFingerprint(<String, Object?>{
        'targetUid': targetUid,
        'status': _targetStatus.wireValue,
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

  static const _ticketOperation = 'setStaffStatus';

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
    final tokens = AppTokens.componentOf(context);
    final action = _targetStatus == MembershipStatus.active
        ? 'Activate'
        : 'Deactivate';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading('$action ${widget.target.displayName}?'),
        SizedBox(height: tokens.spacing.s8),
        Text(
          _targetStatus == MembershipStatus.active
              ? 'This restores the staff member\'s access to this business.'
              : 'This removes the staff member\'s access to this business.',
        ),
        if (_safeError != null) ...[
          SizedBox(height: tokens.spacing.s12),
          Callout(
            key: const ValueKey('set-staff-status-error'),
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
              expand: true,
              onPressed: _submit,
            ),
            SizedBox(height: tokens.spacing.s12),
            AppButton(
              key: const ValueKey('set-staff-status-cancel'),
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

/// Mints one staff-status request id. Public so the ticket store can use the
/// same minter the gateway would have.
String secureStatusRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'status-${base64Url.encode(bytes).replaceAll('=', '')}';
}

final _statusRequestIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$');
