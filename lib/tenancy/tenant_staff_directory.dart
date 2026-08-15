import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../ui/record_list.dart';
import '../ui/scaffold.dart';
import '../ui/stats.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';

import 'tenant_id.dart';
import 'tenant_membership_labels.dart';
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
  Widget build(BuildContext context) => AppScaffold(
    title: 'Staff directory',
    contentWidth: AppContentWidth.records,
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

  /// Whether this session can change anything on this page at all.
  ///
  /// The two capabilities the route offers are inviting somebody and editing an
  /// existing member; a session holding neither is reading. Both conditions are
  /// the ones the affordances below already ask, so this states what the page
  /// is rather than deciding it.
  bool get _readOnly =>
      !widget.session.canAccess(
        allowedRoles: TenantStaffInvitationGateway.allowedRoles,
      ) &&
      !widget.session.canAccess(
        allowedRoles: TenantStaffUpdateGateway.allowedRoles,
      );

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      // **§7's "Title appears once", and the survey found this one was also
      // saying something false.** The heading read `Read-only staff directory`
      // *unconditionally*, under an `AppScaffold` titled `Staff directory` — so
      // an owner was told the page was read-only and then offered `Invite
      // staff` two lines below it. A page's standing is §2.1's, not a heading's,
      // and `info` is "offline, read-only, informational" in the document's own
      // words. This is the same repair the read-only catalog already carries,
      // reached from the other direction: there the fact was true and stated
      // twice; here it was stated once and true only sometimes.
      if (_readOnly) ...[
        const Callout(
          key: ValueKey('staff-directory-read-only'),
          status: AppStatus.info,
          title: 'Read-only staff directory',
          message:
              'Inviting somebody, correcting a member, and deactivating one '
              'are available to owners and administrators. Nothing here is '
              'hidden from you except those.',
        ),
        const SizedBox(height: 12),
      ],
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
      // §4.3's responsive contract. This screen used to *make* that choice
      // itself - a `Builder` reading `AppLayout.contract` and two entirely
      // separate builders under it, which presented different information to
      // the two bands - and §4.3 says in as many words that a screen cannot opt
      // out of the form. So the choice moves into `RecordList`, which knows
      // three renderings rather than two, and this screen states its records
      // once.
      RecordList(
        identityLabel: 'Member',
        items: <RecordItem>[
          for (final staff in widget.page.items) _record(staff),
        ],
        empty: const Text('No staff memberships found.'),
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
    return StatRow(
      tiles: [
        StatTile(
          key: const ValueKey('staff-stat-total'),
          label: 'Staff',
          value: '${items.length}',
          icon: Icons.people_outline,
          detail: page,
        ),
        StatTile(
          key: const ValueKey('staff-stat-active'),
          label: 'Active',
          value: '$active',
          icon: Icons.check_circle_outline,
          detail: 'can sign in and sell',
        ),
        StatTile(
          key: const ValueKey('staff-stat-pending'),
          // §8 rule 4, the verb persists: the badge on every row this tile
          // counts says `Invited`, so the tile counting them cannot say
          // `Pending`. Step 11 moved the badge and this followed it - one screen
          // spelling one standing two ways is what a tile row makes obvious.
          label: 'Invited',
          value: '$pending',
          icon: Icons.hourglass_empty,
          detail: 'not yet accepted',
          // **It used to dim the figure to `onSurfaceVariant` when the count was
          // above zero, and it now says nothing.** That was a colour meaning
          // "look here", which is §2.1's complaint exactly - but the honest
          // replacement is not a badge either: every pending member in the list
          // below already wears one, and a second `attention` on the count of
          // them is the same signal twice. A count is a fact; the standing
          // belongs to the records. The stock route's negative-quantity tile is
          // the other way round and does carry one, because nothing else on
          // that screen states it.
        ),
        StatTile(
          key: const ValueKey('staff-stat-privileged'),
          label: 'Owners & admins',
          value: '$privileged',
          icon: Icons.workspace_premium_outlined,
          detail: 'full access',
        ),
      ],
    );
  }

  /// One member as §5.2's five rows, plus the form their own actions open.
  ///
  /// **A record carries one standing, and this screen used to show two badges.**
  /// Membership status is the one that survives as the [RecordStatus], because
  /// it is the one that decides what a person can do; the invitation state is an
  /// attribute beside the role. Nothing is dropped - both are still a labelled
  /// word rather than a colour, which is what §9 requires - and a pending member
  /// is the only one who has an invitation state to state at all.
  ///
  /// **Two things this screen used to draw are gone, and both are the model
  /// being obeyed rather than an oversight.** The initials block was
  /// `TenantRecordCard`'s `leading` slot; §5.2 names five rows and no leading
  /// one, so adding an avatar to `RecordList` would be inventing a
  /// specification row for one caller. And the role's glyph and its primary
  /// tint for owners and admins go with the chip: role is not one of §2.1's five
  /// statuses, so it cannot be a badge, and a colour that carried "this person
  /// is privileged" on its own is the exact drift §1 is about. The word is what
  /// carried it and the word is still there.
  ///
  /// **Nothing is marked out of the narrow form.** Two attributes fit a card;
  /// `RecordAttribute.inNarrowForm` is for the six-column catalog that comes
  /// later in this sweep, and using it here would drop a fact for no gain.
  RecordItem _record(TenantStaffSummary staff) => RecordItem(
    id: staff.uid,
    // One key for whichever form the band resolves to, where this screen used
    // to have `staff-card-` and `staff-row-`. That the two had to be addressed
    // separately is what made every test here a test of one layout.
    recordKey: ValueKey('staff-record-${staff.uid}'),
    title: staff.displayName,
    subtitle: staff.email,
    // §2.1's five statuses, each with exactly one meaning. Standing used to
    // be a chip whose colour was `colors.error` or nothing, which is the one
    // green doing several jobs that §1 is about.
    status: RecordStatus(
      badgeKey: ValueKey('staff-status-${staff.uid}'),
      label: membershipStatusLabel(staff.status),
      status: switch (staff.status) {
        MembershipStatus.active => AppStatus.ok,
        MembershipStatus.pending => AppStatus.attention,
        // Inactive is the one standing that changes what a person can do.
        // `neutral` rather than `problem`: a deactivated member is closed,
        // not a difference found, and §2.1 gives "closed" to neutral.
        MembershipStatus.inactive => AppStatus.neutral,
      },
      semanticLabel: membershipStatusSemanticLabel(staff.status),
    ),
    attributes: <RecordAttribute>[
      RecordAttribute(
        label: 'Role',
        value: tenantRoleLabel(staff.role),
        valueKey: ValueKey('staff-role-${staff.uid}'),
      ),
      if (staff.status == MembershipStatus.pending)
        RecordAttribute(
          label: 'Invitation',
          value: staffInvitationStatusLabel(staff.invitationStatus),
          valueKey: ValueKey('staff-invitation-${staff.uid}'),
        ),
    ],
    actions: _staffActions(staff),
    details: _staffDetails(staff),
  );

  /// The form this member's own actions opened, or null where none is open.
  ///
  /// At most one is open at a time, which is what every action's `setState`
  /// enforces by clearing the other four - so this returns the one rather than
  /// a list, and `RecordItem.details` is a single slot for the same reason.
  Widget? _staffDetails(TenantStaffSummary staff) {
    if (_editingStaff?.uid == staff.uid) {
      return TenantStaffUpdateForm(
        session: widget.session,
        target: staff,
        callable: widget.updateCallable ?? FirebaseUpdateStaffUserCallable(),
        requestIdFactory: widget.requestIdFactory,
        onSuccess: widget.onMutationSuccess,
        onCancel: () => setState(() => _editingStaff = null),
      );
    }
    if (_statusChangingStaff?.uid == staff.uid) {
      return TenantStaffStatusForm(
        session: widget.session,
        target: staff,
        callable: widget.statusCallable ?? FirebaseSetStaffStatusCallable(),
        requestIdFactory: widget.requestIdFactory,
        onSuccess: widget.onMutationSuccess,
        onCancel: () => setState(() => _statusChangingStaff = null),
      );
    }
    if (_resendingInvitation?.uid == staff.uid) {
      return TenantStaffInvitationResendForm(
        session: widget.session,
        target: staff,
        callable:
            widget.resendCallable ?? FirebaseResendStaffInvitationCallable(),
        requestIdFactory: widget.requestIdFactory,
        onSuccess: widget.onMutationSuccess,
        onCancel: () => setState(() => _resendingInvitation = null),
      );
    }
    if (_cancellingInvitation?.uid == staff.uid) {
      return TenantStaffInvitationCancellationForm(
        session: widget.session,
        target: staff,
        callable:
            widget.cancelInvitationCallable ??
            FirebaseCancelTenantInvitationCallable(),
        requestIdFactory: widget.requestIdFactory,
        onSuccess: widget.onMutationSuccess,
        onCancel: () => setState(() => _cancellingInvitation = null),
      );
    }
    if (_replacingInvitationEmail?.uid == staff.uid) {
      return TenantStaffInvitationEmailReplacementForm(
        session: widget.session,
        target: staff,
        callable:
            widget.replaceEmailCallable ??
            FirebaseReplacePendingStaffEmailCallable(),
        requestIdFactory: widget.requestIdFactory,
        onSuccess: widget.onMutationSuccess,
        onCancel: () => setState(() => _replacingInvitationEmail = null),
      );
    }
    return null;
  }

  /// The record's own controls. Empty where this session may not use any of
  /// them, which is the same check the old trailing slot made.
  ///
  /// **The order is the order this screen already had**, so which of them a
  /// narrow band folds into §4.3's overflow menu is inherited rather than newly
  /// decided: on a pending member that is "Replace email", and on a phone it is
  /// all of them. Reordering them would be a product decision about which
  /// action a small screen hides, and this chunk is a restyle.
  ///
  /// **A member can never have five.** Resend, cancel and replace all require a
  /// pending membership with an unaccepted invitation, and a status change
  /// requires an accepted one, so the two groups are mutually exclusive: the
  /// most any record carries is four - edit, resend, cancel, replace - or two,
  /// edit and activate/deactivate.
  ///
  /// Each of these was a 40dp `IconButton` with the member's name in a tooltip
  /// and no visible label. §5.2 makes them an `ActionSet`, which is §9's 48dp
  /// target with the verb written on it.
  List<RecordAction> _staffActions(TenantStaffSummary staff) {
    if (!widget.session.canAccess(
      allowedRoles: TenantStaffUpdateGateway.allowedRoles,
    )) {
      return const <RecordAction>[];
    }
    return <RecordAction>[
      RecordAction(
        // §8 rule 10: never imply mutation. `Correct` is the word the catalog's
        // own row already uses for the same shape of action, on the same icon
        // and with the same key - the key is a test contract rather than copy,
        // so it stays `edit-staff-...` exactly as the catalog's stays
        // `catalog-management-edit-...`.
        label: 'Correct',
        actionKey: ValueKey('edit-staff-${staff.uid}'),
        icon: Icons.edit_outlined,
        onPressed: () => _open(
          staff,
          current: () => _editingStaff,
          assign: (target) => _editingStaff = target,
        ),
      ),
      if (TenantStaffInvitationResendGateway.canResendTo(staff))
        RecordAction(
          label: 'Resend invitation',
          actionKey: ValueKey('resend-staff-invitation-${staff.uid}'),
          icon: Icons.forward_to_inbox_outlined,
          onPressed: () => _open(
            staff,
            current: () => _resendingInvitation,
            assign: (target) => _resendingInvitation = target,
          ),
        ),
      if (TenantStaffInvitationCancellationGateway.canCancel(staff))
        RecordAction(
          label: 'Cancel invitation',
          actionKey: ValueKey('cancel-staff-invitation-${staff.uid}'),
          icon: Icons.person_remove_outlined,
          // Withdraws an invitation that was issued, which is §2.1's
          // destructive tier rather than a control that looks like its
          // neighbour - half of what §5.2 says the catalog gets wrong.
          destructive: true,
          onPressed: () => _open(
            staff,
            current: () => _cancellingInvitation,
            assign: (target) => _cancellingInvitation = target,
          ),
        ),
      if (TenantStaffInvitationEmailReplacementGateway.canReplaceEmailFor(
        staff,
      ))
        RecordAction(
          label: 'Replace email',
          actionKey: ValueKey('replace-staff-email-${staff.uid}'),
          icon: Icons.alternate_email_outlined,
          onPressed: () => _open(
            staff,
            current: () => _replacingInvitationEmail,
            assign: (target) => _replacingInvitationEmail = target,
          ),
        ),
      if (TenantStaffStatusGateway.canChangeTarget(staff))
        RecordAction(
          label: staff.status == MembershipStatus.active
              ? 'Deactivate'
              : 'Activate',
          actionKey: ValueKey('set-staff-status-${staff.uid}'),
          icon: staff.status == MembershipStatus.active
              ? Icons.person_off_outlined
              : Icons.person_add_alt_outlined,
          // Only one direction removes access, and only that one is
          // destructive: activating a member gives them their till back.
          destructive: staff.status == MembershipStatus.active,
          onPressed: () => _open(
            staff,
            current: () => _statusChangingStaff,
            assign: (target) => _statusChangingStaff = target,
          ),
        ),
    ];
  }

  /// Opens one form against [staff], closing whichever was open.
  ///
  /// The five actions each cleared the other four by hand before this, five
  /// times over; the behaviour is unchanged and the repetition is not.
  ///
  /// **The toggle is per form rather than per member**, which is what the five
  /// copies each did: pressing an action whose own form is already open on this
  /// member closes it, and pressing a *different* action on the same member
  /// replaces the open form rather than closing everything. [current] is read
  /// inside the `setState` so it answers for the press rather than for the frame
  /// the closure was built in.
  void _open(
    TenantStaffSummary staff, {
    required TenantStaffSummary? Function() current,
    required void Function(TenantStaffSummary? target) assign,
  }) {
    setState(() {
      final wasOpen = current()?.uid == staff.uid;
      _cancellingInvitation = null;
      _editingStaff = null;
      _replacingInvitationEmail = null;
      _resendingInvitation = null;
      _statusChangingStaff = null;
      if (!wasOpen) assign(staff);
    });
  }
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
