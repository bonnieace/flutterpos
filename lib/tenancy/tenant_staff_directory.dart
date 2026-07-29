import 'package:flutter/material.dart';

import 'tenant_id.dart';
import 'tenant_paths.dart';
import 'tenant_repository.dart';
import 'tenant_route_guard.dart';
import 'tenant_session.dart';
import 'tenant_staff_invitation.dart';
import 'tenant_staff_invitation_resend.dart';
import 'tenant_staff_status.dart';
import 'tenant_staff_update.dart';
import 'tenant_types.dart';

/// Invitation state safe to expose from a canonical staff summary.
enum TenantStaffInvitationStatus {
  pending('pending'),
  sent('sent'),
  accepted('accepted'),
  cancelled('cancelled'),
  expired('expired');

  const TenantStaffInvitationStatus(this.wireValue);

  final String wireValue;

  static TenantStaffInvitationStatus fromWire(Object? value) => switch (value) {
    'pending' => TenantStaffInvitationStatus.pending,
    'sent' => TenantStaffInvitationStatus.sent,
    'accepted' => TenantStaffInvitationStatus.accepted,
    'cancelled' => TenantStaffInvitationStatus.cancelled,
    'expired' => TenantStaffInvitationStatus.expired,
    _ => throw FormatException('Invalid staff invitation status: $value'),
  };
}

/// Strict projection of `tenants/{tenantId}/staff/{uid}` for management lists.
final class TenantStaffSummary {
  factory TenantStaffSummary.fromSnapshot(
    TenantQueryDocumentSnapshot snapshot, {
    required String ownerUid,
  }) {
    late final String validatedOwnerUid;
    try {
      validatedOwnerUid = validateTenantDocumentId(
        ownerUid,
        fieldName: 'ownerUid',
      );
    } on ArgumentError {
      throw const FormatException('The canonical tenant owner is invalid.');
    }
    final uid = _staffDocumentId(snapshot.path);
    final projectedUid = snapshot.data['uid'];
    if (projectedUid is! String || projectedUid != uid) {
      throw const FormatException(
        'The staff uid must exactly match its canonical document ID.',
      );
    }
    final role = TenantRole.fromWire(snapshot.data['role']);
    final status = MembershipStatus.fromWire(snapshot.data['status']);
    final invitationStatus = TenantStaffInvitationStatus.fromWire(
      snapshot.data['invitationStatus'],
    );
    final isOwner = uid == validatedOwnerUid;
    final ownerProjectionIsValid = isOwner
        ? role == TenantRole.owner &&
              status == MembershipStatus.active &&
              invitationStatus == TenantStaffInvitationStatus.accepted
        : role != TenantRole.owner;
    if (!ownerProjectionIsValid) {
      throw const FormatException('The canonical owner projection is invalid.');
    }
    final invitationProjectionIsValid = switch (status) {
      MembershipStatus.pending =>
        invitationStatus == TenantStaffInvitationStatus.pending ||
            invitationStatus == TenantStaffInvitationStatus.sent,
      MembershipStatus.active || MembershipStatus.inactive =>
        invitationStatus == TenantStaffInvitationStatus.accepted,
    };
    if (!invitationProjectionIsValid) {
      throw const FormatException(
        'The staff membership and invitation states are inconsistent.',
      );
    }
    return TenantStaffSummary._(
      uid: uid,
      email: _normalizedEmail(snapshot.data['email']),
      name: _optionalTrimmedString(snapshot.data, 'name'),
      phone: _optionalTrimmedString(snapshot.data, 'phone'),
      role: role,
      status: status,
      invitationStatus: invitationStatus,
      isOwner: isOwner,
    );
  }

  const TenantStaffSummary._({
    required this.uid,
    required this.email,
    required this.name,
    required this.phone,
    required this.role,
    required this.status,
    required this.invitationStatus,
    required this.isOwner,
  });

  final String uid;
  final String email;
  final String? name;
  final String? phone;
  final TenantRole role;
  final MembershipStatus status;
  final TenantStaffInvitationStatus invitationStatus;
  final bool isOwner;

  String get displayName => name ?? email;
}

/// One bounded page of canonical tenant staff.
final class TenantStaffPage {
  TenantStaffPage({
    required List<TenantStaffSummary> items,
    required this.nextCursor,
    required this.hasMore,
  }) : items = List<TenantStaffSummary>.unmodifiable(items);

  final List<TenantStaffSummary> items;
  final String? nextCursor;
  final bool hasMore;
}

/// Read-only staff repository bound to one live canonical tenant session.
final class TenantStaffDirectoryRepository extends TenantReadRepository {
  TenantStaffDirectoryRepository({
    required super.session,
    required TenantDataReader reader,
  }) : _collectionReader = reader,
       super(reader: reader);

  final TenantCollectionReader _collectionReader;

  Future<TenantStaffPage> loadPage({int pageSize = 20, String? cursor}) async {
    final tenant = await readTenantRoot();
    if (tenant == null) {
      throw const FormatException('The canonical tenant does not exist.');
    }
    final ownerUidValue = tenant['ownerUid'];
    if (ownerUidValue is! String) {
      throw const FormatException('The canonical tenant owner is invalid.');
    }
    late final String ownerUid;
    try {
      ownerUid = validateTenantDocumentId(ownerUidValue, fieldName: 'ownerUid');
    } on ArgumentError {
      throw const FormatException('The canonical tenant owner is invalid.');
    }

    final values = await Future.wait<Object?>([
      readDocument(TenantCollection.staff, ownerUid),
      readCollectionPage(
        TenantCollection.staff,
        collectionReader: _collectionReader,
        pageSize: pageSize,
        cursor: cursor,
      ),
    ]);
    final ownerData = values[0] as Map<String, Object?>?;
    if (ownerData == null) {
      throw const FormatException(
        'The canonical tenant owner membership does not exist.',
      );
    }
    TenantStaffSummary.fromSnapshot(
      TenantQueryDocumentSnapshot(
        path: paths.staffMember(ownerUid),
        data: ownerData,
      ),
      ownerUid: ownerUid,
    );

    final page = values[1] as TenantDocumentPage;
    return TenantStaffPage(
      items: page.items
          .map(
            (snapshot) =>
                TenantStaffSummary.fromSnapshot(snapshot, ownerUid: ownerUid),
          )
          .toList(),
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
    );
  }
}

/// Temporary management route with bounded typed staff actions.
final class TenantStaffDirectoryScreen extends StatelessWidget {
  const TenantStaffDirectoryScreen({
    super.key,
    required this.reader,
    this.inviteCallable,
    this.resendCallable,
    this.statusCallable,
    this.updateCallable,
    this.requestIdFactory,
  });

  static const allowedRoles = <TenantRole>[
    TenantRole.admin,
    TenantRole.manager,
  ];

  final TenantDataReader reader;
  final InviteStaffCallable? inviteCallable;
  final ResendStaffInvitationCallable? resendCallable;
  final SetStaffStatusCallable? statusCallable;
  final UpdateStaffUserCallable? updateCallable;
  final TenantStaffRequestIdFactory? requestIdFactory;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Staff directory')),
    body: TenantStaffDirectoryPanel(
      reader: reader,
      inviteCallable: inviteCallable,
      resendCallable: resendCallable,
      statusCallable: statusCallable,
      updateCallable: updateCallable,
      requestIdFactory: requestIdFactory,
    ),
  );
}

/// Guarded staff content with owner/admin-only typed mutations.
final class TenantStaffDirectoryPanel extends StatefulWidget {
  const TenantStaffDirectoryPanel({
    super.key,
    required this.reader,
    this.inviteCallable,
    this.resendCallable,
    this.statusCallable,
    this.updateCallable,
    this.requestIdFactory,
  });

  final TenantDataReader reader;
  final InviteStaffCallable? inviteCallable;
  final ResendStaffInvitationCallable? resendCallable;
  final SetStaffStatusCallable? statusCallable;
  final UpdateStaffUserCallable? updateCallable;
  final TenantStaffRequestIdFactory? requestIdFactory;

  @override
  State<TenantStaffDirectoryPanel> createState() =>
      _TenantStaffDirectoryPanelState();
}

final class _TenantStaffDirectoryPanelState
    extends State<TenantStaffDirectoryPanel> {
  int _refreshGeneration = 0;

  void _refreshFirstPage() => setState(() => _refreshGeneration++);

  @override
  Widget build(BuildContext context) => TenantRouteGuard<TenantStaffPage>(
    key: ValueKey(_refreshGeneration),
    allowedRoles: TenantStaffDirectoryScreen.allowedRoles,
    load: (session) => TenantStaffDirectoryRepository(
      session: session,
      reader: widget.reader,
    ).loadPage(),
    builder: (context, session, page) => _StaffContents(
      session: session,
      page: page,
      inviteCallable: widget.inviteCallable,
      resendCallable: widget.resendCallable,
      statusCallable: widget.statusCallable,
      updateCallable: widget.updateCallable,
      requestIdFactory: widget.requestIdFactory,
      onMutationSuccess: _refreshFirstPage,
    ),
  );
}

final class _StaffContents extends StatefulWidget {
  const _StaffContents({
    required this.session,
    required this.page,
    required this.inviteCallable,
    required this.resendCallable,
    required this.statusCallable,
    required this.updateCallable,
    required this.requestIdFactory,
    required this.onMutationSuccess,
  });

  final TenantSession session;
  final TenantStaffPage page;
  final InviteStaffCallable? inviteCallable;
  final ResendStaffInvitationCallable? resendCallable;
  final SetStaffStatusCallable? statusCallable;
  final UpdateStaffUserCallable? updateCallable;
  final TenantStaffRequestIdFactory? requestIdFactory;
  final VoidCallback onMutationSuccess;

  @override
  State<_StaffContents> createState() => _StaffContentsState();
}

final class _StaffContentsState extends State<_StaffContents> {
  bool _showInvitationForm = false;
  TenantStaffSummary? _editingStaff;
  TenantStaffSummary? _resendingInvitation;
  TenantStaffSummary? _statusChangingStaff;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Read-only staff directory',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 4),
      Text('Business: ${widget.session.tenantId}'),
      const SizedBox(height: 20),
      if (widget.session.canAccess(
        allowedRoles: TenantStaffInvitationGateway.allowedRoles,
      )) ...[
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey('invite-staff-open'),
            onPressed: () =>
                setState(() => _showInvitationForm = !_showInvitationForm),
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: Text(
              _showInvitationForm ? 'Close invitation' : 'Invite staff',
            ),
          ),
        ),
        if (_showInvitationForm) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TenantStaffInvitationForm(
                session: widget.session,
                callable:
                    widget.inviteCallable ?? FirebaseInviteStaffCallable(),
                requestIdFactory: widget.requestIdFactory,
                onSuccess: widget.onMutationSuccess,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
      if (widget.page.items.isEmpty)
        const Text('No staff memberships found.')
      else
        for (final staff in widget.page.items) ...[
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    staff.isOwner
                        ? Icons.workspace_premium_outlined
                        : Icons.person_outline,
                  ),
                  title: Text(staff.displayName),
                  subtitle: Text(
                    '${staff.email}\n'
                    '${staff.role.wireValue} - ${staff.status.wireValue}'
                    '${staff.status == MembershipStatus.pending ? ' - ${staff.invitationStatus.wireValue}' : ''}',
                  ),
                  trailing:
                      widget.session.canAccess(
                        allowedRoles: TenantStaffUpdateGateway.allowedRoles,
                      )
                      ? Wrap(
                          children: [
                            IconButton(
                              key: ValueKey('edit-staff-${staff.uid}'),
                              tooltip: 'Edit ${staff.displayName}',
                              onPressed: () => setState(() {
                                _resendingInvitation = null;
                                _statusChangingStaff = null;
                                _editingStaff = _editingStaff?.uid == staff.uid
                                    ? null
                                    : staff;
                              }),
                              icon: const Icon(Icons.edit_outlined),
                              ),
                            if (TenantStaffInvitationResendGateway.canResendTo(
                              staff,
                            ))
                              IconButton(
                                key: ValueKey(
                                  'resend-staff-invitation-${staff.uid}',
                                ),
                                tooltip:
                                    'Resend invitation to ${staff.displayName}',
                                onPressed: () => setState(() {
                                  _editingStaff = null;
                                  _statusChangingStaff = null;
                                  _resendingInvitation =
                                      _resendingInvitation?.uid == staff.uid
                                      ? null
                                      : staff;
                                }),
                                icon: const Icon(
                                  Icons.forward_to_inbox_outlined,
                                ),
                              ),
                            if (TenantStaffStatusGateway.canChangeTarget(staff))
                              IconButton(
                                key: ValueKey('set-staff-status-${staff.uid}'),
                                tooltip: staff.status == MembershipStatus.active
                                    ? 'Deactivate ${staff.displayName}'
                                    : 'Activate ${staff.displayName}',
                                onPressed: () => setState(() {
                                  _editingStaff = null;
                                  _resendingInvitation = null;
                                  _statusChangingStaff =
                                      _statusChangingStaff?.uid == staff.uid
                                      ? null
                                      : staff;
                                }),
                                icon: Icon(
                                  staff.status == MembershipStatus.active
                                      ? Icons.person_off_outlined
                                      : Icons.person_add_alt_outlined,
                                ),
                              ),
                          ],
                        )
                      : null,
                  isThreeLine: true,
                ),
                if (_editingStaff?.uid == staff.uid)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: TenantStaffUpdateForm(
                      session: widget.session,
                      target: staff,
                      callable:
                          widget.updateCallable ??
                          FirebaseUpdateStaffUserCallable(),
                      requestIdFactory: widget.requestIdFactory,
                      onSuccess: widget.onMutationSuccess,
                      onCancel: () => setState(() => _editingStaff = null),
                    ),
                  ),
                if (_statusChangingStaff?.uid == staff.uid)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: TenantStaffStatusForm(
                      session: widget.session,
                      target: staff,
                      callable:
                          widget.statusCallable ??
                          FirebaseSetStaffStatusCallable(),
                      requestIdFactory: widget.requestIdFactory,
                      onSuccess: widget.onMutationSuccess,
                      onCancel: () =>
                          setState(() => _statusChangingStaff = null),
                    ),
                  ),
                if (_resendingInvitation?.uid == staff.uid)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: TenantStaffInvitationResendForm(
                      session: widget.session,
                      target: staff,
                      callable:
                          widget.resendCallable ??
                          FirebaseResendStaffInvitationCallable(),
                      requestIdFactory: widget.requestIdFactory,
                      onSuccess: widget.onMutationSuccess,
                      onCancel: () =>
                          setState(() => _resendingInvitation = null),
                    ),
                  ),
              ],
            ),
          ),
        ],
      if (widget.page.hasMore)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('More staff memberships are available.'),
        ),
      const SizedBox(height: 12),
      const Text(
        'Invitation cancellation and email replacement remain unavailable.',
      ),
    ],
  );
}

String _staffDocumentId(String path) {
  final segments = path.split('/');
  if (segments.length != 4 ||
      segments[0] != 'tenants' ||
      segments[2] != TenantCollection.staff.segment) {
    throw const FormatException('Invalid canonical staff document path.');
  }
  try {
    validateTenantId(segments[1]);
    return validateTenantDocumentId(segments[3], fieldName: 'uid');
  } on ArgumentError {
    throw const FormatException('Invalid canonical staff document path.');
  }
}

String _normalizedEmail(Object? value) {
  if (value is! String ||
      value.isEmpty ||
      value != value.trim() ||
      value != value.toLowerCase() ||
      value.contains(' ') ||
      !value.contains('@')) {
    throw const FormatException('Staff email must be normalized.');
  }
  return value;
}

String? _optionalTrimmedString(Map<String, Object?> map, String field) {
  final value = map[field];
  if (value == null || value == '') return null;
  if (value is! String || value != value.trim()) {
    throw FormatException('$field must be a trimmed string when present.');
  }
  for (final codeUnit in value.codeUnits) {
    if (codeUnit < 0x20 || codeUnit == 0x7f) {
      throw FormatException('$field cannot contain control characters.');
    }
  }
  return value;
}
