import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../ui/records.dart';
import '../ui/status.dart';

import 'tenant_id.dart';
import 'tenant_paths.dart';
import 'tenant_repository.dart';
import 'tenant_route_guard.dart';
import 'tenant_session.dart';
import 'tenant_staff_invitation.dart';
import 'tenant_staff_invitation_cancellation.dart';
import 'tenant_staff_invitation_email_replacement.dart';
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
    this.cancelInvitationCallable,
    this.inviteCallable,
    this.replaceEmailCallable,
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
  final CancelTenantInvitationCallable? cancelInvitationCallable;
  final InviteStaffCallable? inviteCallable;
  final ReplacePendingStaffEmailCallable? replaceEmailCallable;
  final ResendStaffInvitationCallable? resendCallable;
  final SetStaffStatusCallable? statusCallable;
  final UpdateStaffUserCallable? updateCallable;
  final TenantStaffRequestIdFactory? requestIdFactory;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Staff directory')),
    body: TenantStaffDirectoryPanel(
      reader: reader,
      cancelInvitationCallable: cancelInvitationCallable,
      inviteCallable: inviteCallable,
      replaceEmailCallable: replaceEmailCallable,
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
    this.cancelInvitationCallable,
    this.inviteCallable,
    this.replaceEmailCallable,
    this.resendCallable,
    this.statusCallable,
    this.updateCallable,
    this.requestIdFactory,
  });

  final TenantDataReader reader;
  final CancelTenantInvitationCallable? cancelInvitationCallable;
  final InviteStaffCallable? inviteCallable;
  final ReplacePendingStaffEmailCallable? replaceEmailCallable;
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
      cancelInvitationCallable: widget.cancelInvitationCallable,
      inviteCallable: widget.inviteCallable,
      replaceEmailCallable: widget.replaceEmailCallable,
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
    required this.cancelInvitationCallable,
    required this.inviteCallable,
    required this.replaceEmailCallable,
    required this.resendCallable,
    required this.statusCallable,
    required this.updateCallable,
    required this.requestIdFactory,
    required this.onMutationSuccess,
  });

  final TenantSession session;
  final TenantStaffPage page;
  final CancelTenantInvitationCallable? cancelInvitationCallable;
  final InviteStaffCallable? inviteCallable;
  final ReplacePendingStaffEmailCallable? replaceEmailCallable;
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
  TenantStaffSummary? _cancellingInvitation;
  TenantStaffSummary? _editingStaff;
  TenantStaffSummary? _replacingInvitationEmail;
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
      _staffStrip(context),
      const SizedBox(height: 20),
      if (widget.session.canAccess(
        allowedRoles: TenantStaffInvitationGateway.allowedRoles,
      )) ...[
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
                   key: const ValueKey('invite-staff-open'),
                   label: _showInvitationForm ? 'Close invitation' : 'Invite staff',
                   icon: Icons.person_add_alt_1_outlined,
                   tier: AppButtonTier.primary,
                   onPressed: () =>
                setState(() => _showInvitationForm = !_showInvitationForm),
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
        LayoutBuilder(
          builder: (context, constraints) => tenantLayoutFitsTable(constraints)
              ? _staffTable(context)
              : _staffCards(context),
        ),
      if (widget.page.hasMore)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('More staff memberships are available.'),
        ),
      const SizedBox(height: 12),
      const Text('Invitation acceptance routes remain unavailable.'),
    ],
  );

  /// The headline figures for this page of the directory.
  ///
  /// Every figure is counted from [TenantStaffPage.items], so each one is
  /// explicitly *this page* rather than the business. Saying "24 staff" from a
  /// page of three would be a number this screen cannot know.
  Widget _staffStrip(BuildContext context) {
    final items = widget.page.items;
    final active = items
        .where((staff) => staff.status == MembershipStatus.active)
        .length;
    final pending = items
        .where((staff) => staff.status == MembershipStatus.pending)
        .length;
    final privileged = items
        .where(
          (staff) =>
              staff.isOwner ||
              staff.role == TenantRole.owner ||
              staff.role == TenantRole.admin,
        )
        .length;
    final page = widget.page.hasMore ? 'on this page, more to load' : 'on this page';
    return TenantStatStrip(
      cards: [
        TenantStatCard(
          key: const ValueKey('staff-stat-total'),
          label: 'Staff',
          value: '${items.length}',
          icon: Icons.people_outline,
          detail: page,
        ),
        TenantStatCard(
          key: const ValueKey('staff-stat-active'),
          label: 'Active',
          value: '$active',
          icon: Icons.check_circle_outline,
          detail: 'can sign in and sell',
        ),
        TenantStatCard(
          key: const ValueKey('staff-stat-pending'),
          label: 'Pending',
          value: '$pending',
          icon: Icons.hourglass_empty,
          detail: 'invited, not yet accepted',
          emphasis: pending > 0
              ? Theme.of(context).colorScheme.onSurfaceVariant
              : null,
        ),
        TenantStatCard(
          key: const ValueKey('staff-stat-privileged'),
          label: 'Owners & admins',
          value: '$privileged',
          icon: Icons.workspace_premium_outlined,
          detail: 'full access',
        ),
      ],
    );
  }

  /// Role and standing, as words rather than as one hyphenated string.
  List<Widget> _staffChips(BuildContext context, TenantStaffSummary staff) {
    final colors = Theme.of(context).colorScheme;
    return <Widget>[
      TenantStatusChip(
        key: ValueKey('staff-role-${staff.uid}'),
        label: staff.role.wireValue,
        icon: staff.isOwner || staff.role == TenantRole.owner
            ? Icons.workspace_premium_outlined
            : staff.role == TenantRole.admin
            ? Icons.admin_panel_settings_outlined
            : staff.role == TenantRole.manager
            ? Icons.people_outline
            : Icons.point_of_sale_outlined,
        tone: staff.role == TenantRole.owner || staff.role == TenantRole.admin
            ? colors.primary
            : null,
      ),
      // §2.1's five statuses, each with exactly one meaning. Standing used to
      // be a chip whose colour was `colors.error` or nothing, which is the one
      // green doing several jobs that §1 is about.
      StatusBadge(
        key: ValueKey('staff-status-${staff.uid}'),
        label: staff.status.wireValue,
        status: switch (staff.status) {
          MembershipStatus.active => AppStatus.ok,
          MembershipStatus.pending => AppStatus.attention,
          // Inactive is the one standing that changes what a person can do.
          // `neutral` rather than `problem`: a deactivated member is closed,
          // not a difference found, and §2.1 gives "closed" to neutral.
          MembershipStatus.inactive => AppStatus.neutral,
        },
        semanticLabel: 'Membership ${staff.status.wireValue}',
      ),
      if (staff.status == MembershipStatus.pending)
        StatusBadge(
          key: ValueKey('staff-invitation-${staff.uid}'),
          label: staff.invitationStatus.wireValue,
          // An envelope says more here than any of the five default glyphs,
          // which is what the override exists for.
          icon: Icons.mail_outline,
          status: switch (staff.invitationStatus) {
            TenantStaffInvitationStatus.accepted => AppStatus.ok,
            TenantStaffInvitationStatus.pending ||
            TenantStaffInvitationStatus.sent => AppStatus.attention,
            TenantStaffInvitationStatus.cancelled ||
            TenantStaffInvitationStatus.expired => AppStatus.neutral,
          },
          semanticLabel: 'Invitation ${staff.invitationStatus.wireValue}',
        ),
    ];
  }

  Widget _staffCards(BuildContext context) => Column(
    children: [
      for (final staff in widget.page.items)
        TenantRecordCard(
          key: ValueKey('staff-card-${staff.uid}'),
          title: staff.displayName,
          subtitle: staff.email,
          leading: TenantInitialsAvatar(
            source: staff.displayName,
            icon: staff.isOwner ? Icons.workspace_premium_outlined : null,
          ),
          chips: _staffChips(context, staff),
          actions: _staffActions(context, staff),
          details: _staffDetails(context, staff),
        ),
    ],
  );

  Widget _staffTable(BuildContext context) => TenantRecordTable(
    columns: const [
      TenantTableColumn(label: 'Member', flex: 3),
      TenantTableColumn(label: 'Standing', flex: 2),
      TenantTableColumn(label: '', flex: 2),
    ],
    rows: [
      for (final staff in widget.page.items)
        TenantTableRow(
          key: ValueKey('staff-row-${staff.uid}'),
          cells: [
            Row(
              children: [
                TenantInitialsAvatar(
                  source: staff.displayName,
                  icon: staff.isOwner
                      ? Icons.workspace_premium_outlined
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        staff.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        staff.email,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _staffChips(context, staff),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: _staffActions(context, staff) ?? const SizedBox.shrink(),
            ),
          ],
          details: _staffDetails(context, staff),
        ),
    ],
  );

  /// The forms a row opens, rendered beneath it in either layout.
  List<Widget> _staffDetails(BuildContext context, TenantStaffSummary staff) =>
      <Widget>[
        if (_editingStaff?.uid == staff.uid)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TenantStaffUpdateForm(
              session: widget.session,
              target: staff,
              callable:
                  widget.updateCallable ?? FirebaseUpdateStaffUserCallable(),
              requestIdFactory: widget.requestIdFactory,
              onSuccess: widget.onMutationSuccess,
              onCancel: () => setState(() => _editingStaff = null),
            ),
          ),
        if (_statusChangingStaff?.uid == staff.uid)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TenantStaffStatusForm(
              session: widget.session,
              target: staff,
              callable:
                  widget.statusCallable ?? FirebaseSetStaffStatusCallable(),
              requestIdFactory: widget.requestIdFactory,
              onSuccess: widget.onMutationSuccess,
              onCancel: () => setState(() => _statusChangingStaff = null),
            ),
          ),
        if (_resendingInvitation?.uid == staff.uid)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TenantStaffInvitationResendForm(
              session: widget.session,
              target: staff,
              callable:
                  widget.resendCallable ??
                  FirebaseResendStaffInvitationCallable(),
              requestIdFactory: widget.requestIdFactory,
              onSuccess: widget.onMutationSuccess,
              onCancel: () => setState(() => _resendingInvitation = null),
            ),
          ),
        if (_cancellingInvitation?.uid == staff.uid)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TenantStaffInvitationCancellationForm(
              session: widget.session,
              target: staff,
              callable:
                  widget.cancelInvitationCallable ??
                  FirebaseCancelTenantInvitationCallable(),
              requestIdFactory: widget.requestIdFactory,
              onSuccess: widget.onMutationSuccess,
              onCancel: () => setState(() => _cancellingInvitation = null),
            ),
          ),
        if (_replacingInvitationEmail?.uid == staff.uid)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TenantStaffInvitationEmailReplacementForm(
              session: widget.session,
              target: staff,
              callable:
                  widget.replaceEmailCallable ??
                  FirebaseReplacePendingStaffEmailCallable(),
              requestIdFactory: widget.requestIdFactory,
              onSuccess: widget.onMutationSuccess,
              onCancel: () =>
                  setState(() => _replacingInvitationEmail = null),
            ),
          ),
      ];

  /// The record's own controls. Null where this session may not use any of
  /// them, which is the same check the old trailing slot made.
  Widget? _staffActions(BuildContext context, TenantStaffSummary staff) =>
      widget.session.canAccess(
        allowedRoles: TenantStaffUpdateGateway.allowedRoles,
      )
      ? Wrap(
          children: [
                            IconButton(
                              key: ValueKey('edit-staff-${staff.uid}'),
                              tooltip: 'Edit ${staff.displayName}',
                              onPressed: () => setState(() {
                                _cancellingInvitation = null;
                                _replacingInvitationEmail = null;
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
                                  _cancellingInvitation = null;
                                  _editingStaff = null;
                                  _replacingInvitationEmail = null;
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
                            if (TenantStaffInvitationCancellationGateway.canCancel(
                              staff,
                            ))
                              IconButton(
                                key: ValueKey(
                                  'cancel-staff-invitation-${staff.uid}',
                                ),
                                tooltip:
                                    'Cancel invitation for ${staff.displayName}',
                                onPressed: () => setState(() {
                                  _editingStaff = null;
                                  _replacingInvitationEmail = null;
                                  _resendingInvitation = null;
                                  _statusChangingStaff = null;
                                  _cancellingInvitation =
                                      _cancellingInvitation?.uid == staff.uid
                                      ? null
                                      : staff;
                                }),
                                icon: const Icon(Icons.person_remove_outlined),
                              ),
                            if (TenantStaffInvitationEmailReplacementGateway.canReplaceEmailFor(
                              staff,
                            ))
                              IconButton(
                                key: ValueKey(
                                  'replace-staff-email-${staff.uid}',
                                ),
                                tooltip:
                                    'Replace invitation email for ${staff.displayName}',
                                onPressed: () => setState(() {
                                  _cancellingInvitation = null;
                                  _editingStaff = null;
                                  _resendingInvitation = null;
                                  _statusChangingStaff = null;
                                  _replacingInvitationEmail =
                                      _replacingInvitationEmail?.uid ==
                                          staff.uid
                                      ? null
                                      : staff;
                                }),
                                icon: const Icon(
                                  Icons.alternate_email_outlined,
                                ),
                              ),
                            if (TenantStaffStatusGateway.canChangeTarget(staff))
                              IconButton(
                                key: ValueKey('set-staff-status-${staff.uid}'),
                                tooltip: staff.status == MembershipStatus.active
                                    ? 'Deactivate ${staff.displayName}'
                                    : 'Activate ${staff.displayName}',
                                onPressed: () => setState(() {
                                  _cancellingInvitation = null;
                                  _editingStaff = null;
                                  _replacingInvitationEmail = null;
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
      : null;
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
