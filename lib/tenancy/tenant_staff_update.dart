import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../ui/fields.dart';
import '../ui/scaffold.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'tenant_id.dart';
import 'tenant_membership_labels.dart';
import 'tenant_session.dart';
import 'tenant_session_controller.dart';
import 'tenant_staff_request_ticket.dart';
import 'tenant_staff_directory.dart';
import 'tenant_staff_invitation.dart';
import 'tenant_types.dart';
import '../observability/app_telemetry.dart';

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
    final result = await traceServerCall(
      'updateStaffUser',
      () => _functions.httpsCallable('updateStaffUser').call<Object?>(payload),
    );
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

  /// Decodes one `updateStaffUser` response.
  ///
  /// **Only the field this mutation set is checked against an expectation.**
  /// Until 2026-09-15 this also required the returned `status` to equal the one
  /// on the directory row the form opened with - a field `updateStaffUser` does
  /// not write and returns fresh from the transaction. So an administrator
  /// correcting a phone number while a colleague deactivated the same person
  /// got a committed write reported as *Staff details could not be updated*,
  /// and retrying replayed the same request id against the server's idempotency
  /// record, which returned the same fresh status and failed identically -
  /// forever. The status is still decoded and carried; it is simply not
  /// evidence of anything having gone wrong.
  factory TenantStaffUpdateResult.fromCallable(
    Object? value, {
    required String expectedTenantId,
    required String expectedUid,
    required TenantRole expectedRole,
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
    if (role != expectedRole) {
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
       _requestIdFactory = requestIdFactory ?? secureUpdateRequestId;

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
    this.tickets,
  });

  final TenantSession session;
  final TenantStaffSummary target;
  final UpdateStaffUserCallable callable;
  final VoidCallback onSuccess;
  final VoidCallback onCancel;
  final TenantStaffRequestIdFactory? requestIdFactory;

  /// Where this device remembers the request id of an unfinished edit.
  final TenantStaffRequestTicketSource? tickets;

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
    // **The flag is raised before the first `await`, not after it.**
    // Reading the device's ticket is asynchronous, and a second tap landing
    // while that read was in flight would find `_submitting` still false and
    // start a second submission.
    setState(() {
      _submitting = true;
      _safeError = null;
    });
    final requestId = await _resolveRequestId(submittedTargetUid);
    if (!mounted || !_isCurrent(controller, submittedTargetUid)) {
      _abandonSubmission();
      return;
    }
    final gateway = TenantStaffUpdateGateway(
      session: widget.session,
      target: widget.target,
      callable: widget.callable,
      requestIdFactory: () => requestId,
    );
    late final TenantStaffUpdateIntent intent;
    try {
      intent = _intent ??= gateway.createIntent(
        name: _nameController.text,
        phone: _phoneController.text,
        role: _role,
      );
    } catch (_) {
      if (!mounted || !_isCurrent(controller, submittedTargetUid)) {
        _abandonSubmission();
        return;
      }
      setState(() {
        _submitting = false;
        _safeError = 'Check the staff details and try again.';
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
      if (!mounted || !_isCurrent(controller, submittedTargetUid)) {
        _abandonSubmission();
        return;
      }
      setState(() {
        _submitting = false;
        _safeError = 'Staff details could not be updated. Please try again.';
      });
      return;
    }
    await _clearRequestTicket(submittedTargetUid);
    if (!mounted || !_isCurrent(controller, submittedTargetUid)) {
      _abandonSubmission();
      return;
    }
    setState(() => _submitting = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Staff details updated.')));
    widget.onSuccess();
  }

  /// The id this edit should be asked under, replayed across a restart.
  ///
  /// **Fingerprinted on the same fields the server hashes**
  /// (`membership.ts` records `{targetUid, name, phone, role}`), so the two
  /// agree on what counts as the same request. Where they disagree the server
  /// wins safely: a replayed id carrying different input is refused as
  /// `already-exists` rather than quietly answering with the first attempt's
  /// result.
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

  Future<String> _resolveRequestId(String targetUid) async {
    final tickets = widget.tickets;
    final mint = widget.requestIdFactory ?? secureUpdateRequestId;
    if (tickets == null) return mint();
    return tickets.resolve(
      uid: widget.session.uid,
      tenantId: widget.session.tenantId,
      operation: _ticketOperation,
      target: targetUid,
      fingerprint: tenantStaffRequestFingerprint(<String, Object?>{
        'targetUid': targetUid,
        'name': normalizeTenantStaffInviteName(_nameController.text),
        'phone': normalizeTenantStaffInvitePhone(_phoneController.text),
        'role': _role.wireValue,
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

  static const _ticketOperation = 'updateStaffUser';

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
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // **§8 rule 4: the verb persists.** The action that opens this form
          // and this heading say the same thing, as this route's other four
          // forms already do: `Resend invitation to ...`, `Cancel invitation
          // for ...`, `Replace invitation email for ...`, `Deactivate ...`.
          //
          // Both were `Correct` until 2026-09-15, which named a third of what
          // the form does. A person correcting a phone number is also
          // submitting the role on screen, and `Correct` is precisely the word
          // that stops them noticing.
          SectionHeading('Edit ${widget.target.displayName}'),
          SizedBox(height: tokens.spacing.s8),
          AppTextField(
            key: const ValueKey('update-staff-name'),
            controller: _nameController,
            enabled: !_submitting,
            label: 'Name',
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
          AppTextField(
            key: const ValueKey('update-staff-phone'),
            controller: _phoneController,
            enabled: !_submitting,
            keyboardType: TextInputType.phone,
            label: 'Phone (optional)',
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
          SizedBox(height: tokens.spacing.s12),
          AppSelect<TenantRole>(
            key: const ValueKey('update-staff-role'),
            value: _role,
            label: 'Role',
            items:
                (widget.target.isOwner
                        ? const [TenantRole.owner]
                        : const [
                            TenantRole.admin,
                            TenantRole.manager,
                            TenantRole.cashier,
                          ])
                    .map(
                      (role) => AppSelectItem<TenantRole>(
                        value: role,
                        label: tenantRoleLabel(role),
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
            SizedBox(height: tokens.spacing.s12),
            Callout(
              key: const ValueKey('update-staff-error'),
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
                key: const ValueKey('update-staff-submit'),
                label: 'Save changes',
                icon: Icons.save_outlined,
                tier: AppButtonTier.primary,
                loading: _submitting,
                expand: true,
                onPressed: _submit,
              ),
              SizedBox(height: tokens.spacing.s12),
              AppButton(
                key: const ValueKey('update-staff-cancel'),
                label: 'Cancel',
                expand: true,
                onPressed: _submitting ? null : widget.onCancel,
              ),
            ],
          ),
        ],
      ),
    );
  }
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

/// Mints one staff-update request id. Public so the ticket store can use the
/// same minter the gateway would have.
String secureUpdateRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'update-${base64Url.encode(bytes).replaceAll('=', '')}';
}

final _updateRequestIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$');
