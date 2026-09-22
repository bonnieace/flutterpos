import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../ui/fields.dart';
import '../ui/snackbar.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'tenant_id.dart';
import 'tenant_membership_labels.dart';
import 'tenant_session.dart';
import 'tenant_session_controller.dart';
import 'tenant_staff_request_ticket.dart';
import 'tenant_types.dart';

typedef TenantStaffRequestIdFactory = String Function();

/// Whether [error] is the server saying this session may not do that.
///
/// **Only `permission-denied`.** Every staff callable re-reads the actor's
/// canonical membership before it acts, so this code means the server disagreed
/// with what the session believed about itself - which is near-proof the
/// session is stale. `failed-precondition` is deliberately excluded: it is the
/// server disagreeing about the *target* (an invitation that is no longer
/// pending, a member who is no longer active), which says nothing about the
/// actor and would have a form asking for a re-read every time an operator
/// raced a colleague on one record.
bool isTenantStaffAuthorizationRefusal(Object error) =>
    error is FirebaseFunctionsException && error.code == 'permission-denied';

/// Narrow callable boundary for the one enabled staff mutation.
abstract interface class InviteStaffCallable {
  Future<Object?> call(Map<String, Object?> payload);
}

/// Firebase adapter for `inviteStaff`; response validation remains above it.
final class FirebaseInviteStaffCallable implements InviteStaffCallable {
  FirebaseInviteStaffCallable({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    final result = await _functions
        .httpsCallable('inviteStaff')
        .call<Object?>(payload);
    return result.data;
  }
}

/// Normalized client input for a new tenant staff invitation.
final class TenantStaffInviteDraft {
  TenantStaffInviteDraft({
    required String email,
    required String name,
    required String phone,
    required this.role,
  }) : email = normalizeTenantStaffInviteEmail(email),
       name = normalizeTenantStaffInviteName(name),
       phone = normalizeTenantStaffInvitePhone(phone) {
    if (role == TenantRole.owner) {
      throw const FormatException(
        'Owners cannot be invited through this form.',
      );
    }
  }

  final String email;
  final String name;
  final String phone;
  final TenantRole role;
}

/// One user intent and its stable idempotency key.
final class TenantStaffInviteIntent {
  const TenantStaffInviteIntent._({
    required this.draft,
    required this.requestId,
  });

  final TenantStaffInviteDraft draft;
  final String requestId;
}

/// Strictly decoded result from the `inviteStaff` callable.
final class TenantStaffInviteResult {
  const TenantStaffInviteResult._({
    required this.tenantId,
    required this.uid,
    required this.invitationVersion,
    required this.deliveryId,
  });

  factory TenantStaffInviteResult.fromCallable(
    Object? value, {
    required String expectedTenantId,
  }) {
    final data = _strictStringMap(
      value,
      label: 'inviteStaff response',
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
        'inviteStaff returned a result for another tenant.',
      );
    }
    if (data['invitationStatus'] != 'pending') {
      throw const FormatException('inviteStaff returned an invalid status.');
    }
    final uidValue = data['uid'];
    if (uidValue is! String) {
      throw const FormatException('inviteStaff returned an invalid uid.');
    }
    late final String uid;
    try {
      uid = validateTenantDocumentId(uidValue, fieldName: 'uid');
    } on ArgumentError {
      throw const FormatException('inviteStaff returned an invalid uid.');
    }
    final invitationVersion = data['invitationVersion'];
    if (invitationVersion is! int ||
        invitationVersion < 1 ||
        invitationVersion > 9007199254740991) {
      throw const FormatException(
        'inviteStaff returned an invalid invitation version.',
      );
    }
    final delivery = _strictStringMap(
      data['delivery'],
      label: 'inviteStaff delivery',
      keys: const {'deliveryId', 'status'},
    );
    if (delivery['status'] != 'pending_enqueue') {
      throw const FormatException('inviteStaff returned an invalid delivery.');
    }
    final deliveryIdValue = delivery['deliveryId'];
    if (deliveryIdValue is! String) {
      throw const FormatException('inviteStaff returned an invalid delivery.');
    }
    late final String deliveryId;
    try {
      deliveryId = validateTenantDocumentId(
        deliveryIdValue,
        fieldName: 'deliveryId',
      );
    } on ArgumentError {
      throw const FormatException('inviteStaff returned an invalid delivery.');
    }
    return TenantStaffInviteResult._(
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

/// Session-bound gateway. Callers cannot provide a tenant ID or raw path.
final class TenantStaffInvitationGateway {
  TenantStaffInvitationGateway({
    required TenantSession session,
    required InviteStaffCallable callable,
    TenantStaffRequestIdFactory? requestIdFactory,
  }) : _session = session,
       _callable = callable,
       _requestIdFactory = requestIdFactory ?? secureInviteRequestId;

  static const allowedRoles = <TenantRole>[TenantRole.admin];

  final TenantSession _session;
  final InviteStaffCallable _callable;
  final TenantStaffRequestIdFactory _requestIdFactory;

  TenantStaffInviteIntent createIntent(TenantStaffInviteDraft draft) {
    _requireAuthorizedSession();
    final requestId = _requestIdFactory();
    if (!_requestIdPattern.hasMatch(requestId)) {
      throw StateError('The invitation request ID generator is invalid.');
    }
    return TenantStaffInviteIntent._(draft: draft, requestId: requestId);
  }

  Future<TenantStaffInviteResult> submit(TenantStaffInviteIntent intent) async {
    _requireAuthorizedSession();
    final draft = intent.draft;
    final response = await _callable.call(<String, Object?>{
      'tenantId': _session.tenantId,
      'email': draft.email,
      'name': draft.name,
      'phone': draft.phone,
      'role': draft.role.wireValue,
      'requestId': intent.requestId,
    });
    return TenantStaffInviteResult.fromCallable(
      response,
      expectedTenantId: _session.tenantId,
    );
  }

  void _requireAuthorizedSession() {
    if (!_session.canAccess(allowedRoles: allowedRoles)) {
      throw StateError('An owner or administrator session is required.');
    }
  }
}

/// Recoverable, single-flight invitation form for an already guarded session.
final class TenantStaffInvitationForm extends StatefulWidget {
  const TenantStaffInvitationForm({
    super.key,
    required this.session,
    required this.callable,
    required this.onSuccess,
    this.onCancel,
    this.requestIdFactory,
    this.tickets,
  });

  final TenantSession session;
  final InviteStaffCallable callable;
  final VoidCallback onSuccess;

  /// Closes the form without inviting anybody.
  ///
  /// **The form draws it rather than the sheet around it**, so this ends in the
  /// same stacked pair every other form on this surface ends in. A caller that
  /// has nowhere to go back to passes null and gets the commit alone.
  final VoidCallback? onCancel;
  final TenantStaffRequestIdFactory? requestIdFactory;

  /// Where this device remembers the request id of an unfinished invitation.
  ///
  /// Null keeps the pre-2026-09-15 behaviour, which is a request id that lives
  /// and dies with this form. Every composition that can reach a real backend
  /// supplies one.
  final TenantStaffRequestTicketSource? tickets;

  @override
  State<TenantStaffInvitationForm> createState() =>
      _TenantStaffInvitationFormState();
}

final class _TenantStaffInvitationFormState
    extends State<TenantStaffInvitationForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  TenantRole _role = TenantRole.cashier;
  TenantStaffInviteIntent? _intent;
  bool _submitting = false;
  String? _safeError;

  @override
  void dispose() {
    _emailController.dispose();
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
    if (!_isCurrent(controller)) return;
    // **The draft is built before the request id, because it decides it.** Its
    // constructor is where the address, name and phone are normalized, and the
    // normalized values are what the ticket is fingerprinted on - so whitespace
    // an operator cannot see does not read as a different invitation.
    late final TenantStaffInviteDraft draft;
    try {
      draft = TenantStaffInviteDraft(
        email: _emailController.text,
        name: _nameController.text,
        phone: _phoneController.text,
        role: _role,
      );
    } catch (_) {
      if (!mounted || !_isCurrent(controller)) {
        _abandonSubmission();
        return;
      }
      setState(
        () => _safeError = 'Check the invitation details and try again.',
      );
      return;
    }
    // **The flag is raised before the first `await`, not after it.** Reading
    // the device's ticket is asynchronous, and a second tap landing while that
    // read was in flight would find `_submitting` still false and start a
    // second submission. This held by microtask timing alone until 2026-09-15,
    // which is not a thing to hold single-flight together with.
    setState(() {
      _submitting = true;
      _safeError = null;
    });
    final requestId = await _resolveRequestId(draft);
    if (!mounted || !_isCurrent(controller)) {
      _abandonSubmission();
      return;
    }
    final gateway = TenantStaffInvitationGateway(
      session: widget.session,
      callable: widget.callable,
      requestIdFactory: () => requestId,
    );
    late final TenantStaffInviteIntent intent;
    try {
      intent = _intent ??= gateway.createIntent(draft);
    } catch (_) {
      if (!mounted || !_isCurrent(controller)) {
        _abandonSubmission();
        return;
      }
      setState(() {
        _submitting = false;
        _safeError = 'Check the invitation details and try again.';
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
      if (!mounted || !_isCurrent(controller)) {
        _abandonSubmission();
        return;
      }
      setState(() {
        _submitting = false;
        _safeError = 'Invitation could not be sent. Please try again.';
      });
      return;
    }
    // **Cleared on the answer, and only on the answer.** A refusal deliberately
    // keeps its ticket: pressing again then replays the same id and is refused
    // the same way, which is the honest result, and editing the address changes
    // the fingerprint and mints a fresh id on its own. The one case that must
    // keep a ticket is the one with no answer at all.
    await _clearRequestTicket();
    if (!mounted || !_isCurrent(controller)) {
      _abandonSubmission();
      return;
    }
    setState(() => _submitting = false);
    showAppSnackBar(
      context,
      const AppNotice.confirmed('Staff invitation queued.'),
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

  /// The id this invitation should be asked under, replayed across a restart.
  Future<String> _resolveRequestId(TenantStaffInviteDraft draft) async {
    final tickets = widget.tickets;
    final mint = widget.requestIdFactory ?? secureInviteRequestId;
    if (tickets == null) return mint();
    return tickets.resolve(
      uid: widget.session.uid,
      tenantId: widget.session.tenantId,
      operation: _ticketOperation,
      // An invitation names an address rather than a member, and the address is
      // already in the fingerprint.
      target: '',
      fingerprint: tenantStaffRequestFingerprint(<String, Object?>{
        'email': draft.email,
        'name': draft.name,
        'phone': draft.phone,
        'role': draft.role.wireValue,
      }),
      mint: mint,
    );
  }

  Future<void> _clearRequestTicket() async {
    await widget.tickets?.clear(
      uid: widget.session.uid,
      tenantId: widget.session.tenantId,
      operation: _ticketOperation,
      target: '',
    );
  }

  static const _ticketOperation = 'inviteStaff';

  bool _isCurrent(TenantSessionController controller) {
    final current = controller.session;
    return current != null &&
        current.uid == widget.session.uid &&
        current.tenantId == widget.session.tenantId &&
        current.epoch == widget.session.epoch &&
        current.canAccess(
          allowedRoles: TenantStaffInvitationGateway.allowedRoles,
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
          AppTextField(
            key: const ValueKey('invite-staff-email'),
            controller: _emailController,
            enabled: !_submitting,
            keyboardType: TextInputType.emailAddress,
            label: 'Email',
            leading: Icons.email_outlined,
            onChanged: (_) => _markIntentChanged(),
            validator: (value) {
              try {
                normalizeTenantStaffInviteEmail(value ?? '');
                return null;
              } on FormatException {
                return 'Enter a valid email address.';
              }
            },
          ),
          AppTextField(
            key: const ValueKey('invite-staff-name'),
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
            key: const ValueKey('invite-staff-phone'),
            controller: _phoneController,
            enabled: !_submitting,
            keyboardType: TextInputType.phone,
            label: 'Phone (optional)',
            leading: Icons.phone_outlined,
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
            key: const ValueKey('invite-staff-role'),
            value: _role,
            label: 'Role',
            items:
                const [TenantRole.admin, TenantRole.manager, TenantRole.cashier]
                    .map(
                      (role) => AppSelectItem<TenantRole>(
                        value: role,
                        label: tenantRoleLabel(role),
                      ),
                    )
                    .toList(),
            onChanged: _submitting
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
              key: const ValueKey('invite-staff-error'),
              // A refusal, named as one rather than painted red: the write
              // was attempted and nothing changed. Before this the whole of
              // the status was the colour, which is the case §9 rules out.
              status: AppNotice.refused(_safeError!).status,
              message: _safeError!,
            ),
          ],
          SizedBox(height: tokens.spacing.s16),
          AppButton(
            key: const ValueKey('invite-staff-submit'),
            label: 'Send invitation',
            icon: Icons.person_add_alt_1_outlined,
            tier: AppButtonTier.primary,
            loading: _submitting,
            expand: true,
            onPressed: _submit,
          ),
          if (widget.onCancel case final cancel?) ...<Widget>[
            SizedBox(height: tokens.spacing.s12),
            AppButton(
              key: const ValueKey('invite-staff-cancel'),
              label: 'Cancel',
              expand: true,
              onPressed: _submitting ? null : cancel,
            ),
          ],
        ],
      ),
    );
  }
}

String normalizeTenantStaffInviteEmail(String value) {
  final email = value.trim().toLowerCase();
  if (email.isEmpty || email.length > 320 || !_emailPattern.hasMatch(email)) {
    throw const FormatException('Invalid staff invitation email.');
  }
  return email;
}

String normalizeTenantStaffInviteName(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty ||
      trimmed.length > 100 ||
      _hasControlCharacter(trimmed)) {
    throw const FormatException('Invalid staff invitation name.');
  }
  return trimmed.replaceAll(RegExp(r'\s+'), ' ');
}

String normalizeTenantStaffInvitePhone(String value) {
  final phone = value.trim();
  if (phone.length > 32 || _hasControlCharacter(phone)) {
    throw const FormatException('Invalid staff invitation phone.');
  }
  return phone;
}

Map<String, Object?> _strictStringMap(
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

/// Mints one invitation request id.
///
/// Public so `TenantStaffRequestTicketSource` can be handed the same minter the
/// gateway would have used, rather than inventing a second spelling of an id
/// the server validates.
String secureInviteRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'invite-${base64Url.encode(bytes).replaceAll('=', '')}';
}

bool _hasControlCharacter(String value) {
  for (final codeUnit in value.codeUnits) {
    if (codeUnit < 0x20 || codeUnit == 0x7f) return true;
  }
  return false;
}

final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
final _requestIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$');
