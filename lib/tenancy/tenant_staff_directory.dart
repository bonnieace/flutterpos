import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../ui/dialogs.dart';
import '../ui/fields.dart';
import '../ui/pagination.dart';
import '../ui/scaffold.dart';
import '../ui/sheet.dart';
import '../ui/skeleton.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';

import 'tenant_id.dart';
import 'tenant_membership_labels.dart';
import 'tenant_paths.dart';
import 'tenant_repository.dart';
import 'tenant_route_guard.dart';
import 'tenant_session.dart';
import 'tenant_session_controller.dart';
import 'tenant_staff_invitation.dart';
import 'tenant_staff_invitation_cancellation.dart';
import 'tenant_staff_invitation_email_replacement.dart';
import 'tenant_staff_invitation_resend.dart';
import 'tenant_staff_request_ticket.dart';
import 'tenant_staff_status.dart';
import 'tenant_staff_update.dart';
import 'tenant_types.dart';

/// Where this person's *membership* invitation stands.
///
/// **Every value here is one the server actually writes.** This carried an
/// `expired` until 2026-09-15 and nothing had ever produced it: expiry is
/// derived from a deadline on both sides of the wire rather than stored as a
/// state. Worse, the strict projection below refuses a pending member carrying
/// anything but `pending` or `sent` - and that refusal fails the whole
/// directory page rather than the one row - so the value could only ever have
/// arrived as an outage.
///
/// **This is not where an email's fate is recorded**; see
/// [TenantStaffInvitationDelivery]. Four server gates read this field -
/// `requirePendingStaffInvitation`, `acceptancePolicy`,
/// `isEligibleStaffInvitationRecipient` and the projection below - so a
/// delivery outcome folded into it would refuse the recipient's acceptance and
/// the administrator's replace-the-address, which are the two recoveries a
/// failed delivery exists to prompt.
enum TenantStaffInvitationStatus {
  pending('pending'),
  sent('sent'),
  accepted('accepted'),
  cancelled('cancelled');

  const TenantStaffInvitationStatus(this.wireValue);

  final String wireValue;

  static TenantStaffInvitationStatus fromWire(Object? value) => switch (value) {
    'pending' => TenantStaffInvitationStatus.pending,
    'sent' => TenantStaffInvitationStatus.sent,
    'accepted' => TenantStaffInvitationStatus.accepted,
    'cancelled' => TenantStaffInvitationStatus.cancelled,
    _ => throw FormatException('Invalid staff invitation status: $value'),
  };
}

/// What became of the invitation email itself.
///
/// Absent on a record whose first delivery has not been claimed, and on every
/// record written before 2026-09-15 - both read as [notSent], which is what
/// they were.
enum TenantStaffInvitationDelivery {
  /// Nothing has been emailed for the current link yet.
  notSent('pending'),

  /// It went out.
  sent('sent'),

  /// It cannot reach that address and retrying will not change that: the
  /// provider refused it permanently, the attempts ran out, or the recipient is
  /// suppressed. The recovery is a different address.
  failed('failed');

  const TenantStaffInvitationDelivery(this.wireValue);

  final String wireValue;

  static TenantStaffInvitationDelivery fromWire(Object? value) =>
      switch (value) {
        null => TenantStaffInvitationDelivery.notSent,
        'pending' => TenantStaffInvitationDelivery.notSent,
        'sent' => TenantStaffInvitationDelivery.sent,
        'failed' => TenantStaffInvitationDelivery.failed,
        _ => throw FormatException('Invalid invitation delivery: $value'),
      };
}

/// What the directory should say about an invitation, deadline included.
///
/// **Expiry is derived, never stored**, which is how the server treats it too:
/// `acceptancePolicy` compares the deadline against the clock at the moment
/// somebody tries to accept, and no process anywhere writes an expired state. A
/// stored one would need a scheduled writer walking every pending member of
/// every business to keep a label honest, and it would still be wrong either
/// side of the boundary minute.
enum TenantStaffInvitationState {
  /// Nothing has been emailed yet, or a fresh link has been minted and its
  /// delivery has not gone out.
  notSent,

  /// Emailed, and the link still opens.
  sent,

  /// Emailed, and the link has passed its deadline. Resend is the recovery.
  expired,

  /// Undeliverable to that address. A different address is the recovery.
  undeliverable,
  accepted,
  cancelled,
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
      invitationDelivery: TenantStaffInvitationDelivery.fromWire(
        snapshot.data['invitationDeliveryState'],
      ),
      invitationExpiresAt: tenantStoredInstant(
        snapshot.data['invitationExpiresAt'],
      ),
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
    required this.invitationDelivery,
    required this.invitationExpiresAt,
    required this.isOwner,
  });

  final String uid;
  final String email;
  final String? name;
  final String? phone;
  final TenantRole role;
  final MembershipStatus status;
  final TenantStaffInvitationStatus invitationStatus;

  /// What became of the invitation email, as the delivery worker last left it.
  final TenantStaffInvitationDelivery invitationDelivery;

  /// When the emailed link stops opening, in UTC.
  ///
  /// **Null is not "never".** The deadline is minted with the token, which
  /// happens when a delivery is claimed - so an invitation whose first delivery
  /// has not been dispatched has no deadline yet, and neither has a record
  /// written before this field existed. Both read as *not expired*, which is
  /// the safe direction: the server refuses an expired proof regardless, so the
  /// cost of being wrong here is a label, not an admission.
  final DateTime? invitationExpiresAt;
  final bool isOwner;

  String get displayName => name ?? email;

  /// What to say about this invitation at [now], deadline applied.
  ///
  /// **The membership's standing outranks the email's.** An accepted member is
  /// accepted however their invitation was delivered, and reading the two
  /// fields the other way round would let a stale delivery label speak over a
  /// membership that has already moved on.
  TenantStaffInvitationState invitationState(DateTime now) {
    switch (invitationStatus) {
      case TenantStaffInvitationStatus.accepted:
        return TenantStaffInvitationState.accepted;
      case TenantStaffInvitationStatus.cancelled:
        return TenantStaffInvitationState.cancelled;
      case TenantStaffInvitationStatus.pending:
      case TenantStaffInvitationStatus.sent:
        switch (invitationDelivery) {
          case TenantStaffInvitationDelivery.failed:
            return TenantStaffInvitationState.undeliverable;
          case TenantStaffInvitationDelivery.notSent:
            // Nothing has gone out for the current link, so the deadline on the
            // *previous* one says nothing an operator can act on.
            return TenantStaffInvitationState.notSent;
          case TenantStaffInvitationDelivery.sent:
            final deadline = invitationExpiresAt;
            return deadline != null && !deadline.isAfter(now.toUtc())
                ? TenantStaffInvitationState.expired
                : TenantStaffInvitationState.sent;
        }
    }
  }
}

/// What a person's access to this business amounts to right now.
///
/// **Membership status and invitation state, resolved to one word.** A row
/// carried both - a `StatusBadge` for the membership and a right-aligned
/// caption for the invitation - so *this person cannot sign in and nothing is
/// going to change that on its own* had to be assembled by a reader out of two
/// separate marks at two weights. These seven are what those two fields
/// actually produce between them, and a row states one of them.
///
/// **The membership outranks the invitation**, for the reason
/// [TenantStaffSummary.invitationState] gives about its own two fields: an
/// active member is active however their invitation was delivered.
///
/// **Nothing here reads anything new.** Every value is computed from
/// `status`, `invitationStatus`, `invitationDelivery` and `invitationExpiresAt`,
/// which the directory document already carries and the row already held.
enum StaffStanding {
  active,
  invited,
  notSent,
  linkExpired,
  emailRejected,
  invitationCancelled,
  deactivated;

  /// The standing [staff] is in at [now].
  static StaffStanding of(TenantStaffSummary staff, DateTime now) =>
      resolved(staff.status, staff.invitationState(now));

  /// The standing, from a membership status and an invitation state that has
  /// already had a clock applied to it.
  ///
  /// **Separate from [of] so the row does not need a second clock.** The
  /// directory resolves every invitation against one `now` before it builds a
  /// card; asking the card for its own would let two rows in one list disagree
  /// about the same deadline.
  static StaffStanding resolved(
    MembershipStatus status,
    TenantStaffInvitationState invitation,
  ) => switch (status) {
    MembershipStatus.active => StaffStanding.active,
    MembershipStatus.inactive => StaffStanding.deactivated,
    MembershipStatus.pending => switch (invitation) {
      // An accepted invitation against a membership that has not been
      // activated yet is still somebody waiting to be let in, which is what
      // *Invited* says.
      TenantStaffInvitationState.accepted => StaffStanding.invited,
      TenantStaffInvitationState.sent => StaffStanding.invited,
      TenantStaffInvitationState.notSent => StaffStanding.notSent,
      TenantStaffInvitationState.expired => StaffStanding.linkExpired,
      TenantStaffInvitationState.undeliverable => StaffStanding.emailRejected,
      TenantStaffInvitationState.cancelled => StaffStanding.invitationCancelled,
    },
  };

  /// Whether this is an invitation that will not arrive without somebody acting.
  ///
  /// **The same split `TenantStockTakeSchedule` and the shift standings make.**
  /// A link that has run out and an address that bounced are both dead ends.
  /// *Not sent yet* is deliberately excluded: delivery has not run, and it
  /// usually runs.
  bool get needsAttention =>
      this == StaffStanding.linkExpired || this == StaffStanding.emailRejected;

  /// The word on the badge. Sentence case, §8 rule 7.
  String get label => switch (this) {
    StaffStanding.active => 'Active',
    StaffStanding.invited => 'Invited',
    StaffStanding.notSent => 'Not sent yet',
    StaffStanding.linkExpired => 'Link expired',
    StaffStanding.emailRejected => 'Email rejected',
    StaffStanding.invitationCancelled => 'Invitation cancelled',
    StaffStanding.deactivated => 'Deactivated',
  };

  /// The tier the badge wears. §2.1's own vocabulary: `attention` is awaiting,
  /// `problem` is a dead end, `neutral` is a standing nobody has to act on.
  AppStatus get status => switch (this) {
    StaffStanding.active => AppStatus.ok,
    StaffStanding.invited => AppStatus.attention,
    StaffStanding.notSent => AppStatus.attention,
    StaffStanding.linkExpired => AppStatus.problem,
    StaffStanding.emailRejected => AppStatus.problem,
    StaffStanding.invitationCancelled => AppStatus.neutral,
    StaffStanding.deactivated => AppStatus.neutral,
  };

  /// The glyph, so §9's rule holds: container, icon and word, never hue alone.
  IconData get icon => switch (this) {
    StaffStanding.active => Icons.check_circle_outline,
    StaffStanding.invited => Icons.mail_outline,
    StaffStanding.notSent => Icons.schedule_send_outlined,
    StaffStanding.linkExpired => Icons.timer_off_outlined,
    StaffStanding.emailRejected => Icons.report_gmailerrorred_outlined,
    StaffStanding.invitationCancelled => Icons.block_outlined,
    StaffStanding.deactivated => Icons.do_not_disturb_on_outlined,
  };

  /// What a screen reader is told, where the word alone is not a sentence.
  String get semanticLabel => switch (this) {
    StaffStanding.active => 'Active, can sign in',
    StaffStanding.invited => 'Invited, waiting to be accepted',
    StaffStanding.notSent => 'Invitation not sent yet',
    StaffStanding.linkExpired => 'Invitation link has expired',
    StaffStanding.emailRejected => 'Invitation email was rejected',
    StaffStanding.invitationCancelled => 'Invitation was cancelled',
    StaffStanding.deactivated => 'Deactivated, cannot sign in',
  };

  /// The key of the row action this standing promotes out of the kebab, or null
  /// where it promotes none.
  ///
  /// **The two dead ends promote different actions, and that is the point.**
  /// Resending to an address the mail server already rejected bounces again, so
  /// *Email rejected* reaches for the replacement and never the resend.
  ///
  /// This names an action the row has already built and gated; it does not add
  /// one. A standing whose action is absent - because this session may not take
  /// it - simply draws no button.
  String? promotedActionKeyFor(String uid) => switch (this) {
    StaffStanding.notSent => 'resend-staff-invitation-$uid',
    StaffStanding.linkExpired => 'resend-staff-invitation-$uid',
    StaffStanding.emailRejected => 'replace-staff-email-$uid',
    _ => null,
  };

  /// The word on that button, where there is one.
  String? get promotedActionLabel => switch (this) {
    StaffStanding.notSent => 'Send now',
    StaffStanding.linkExpired => 'Resend',
    StaffStanding.emailRejected => 'Replace email',
    _ => null,
  };
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
    TenantStaffDirectoryQueryReader? queryReader,
  }) : _collectionReader = reader,
       _queryReader = queryReader,
       super(reader: reader);

  final TenantCollectionReader _collectionReader;
  final TenantStaffDirectoryQueryReader? _queryReader;

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

  /// Loads one backend-filtered staff page with an opaque stable cursor.
  ///
  /// The generic collection reader stays equality-only. Search's array
  /// membership and the combined role/status filters use the dedicated reader,
  /// and every result is re-proved against this live session before decoding.
  Future<TenantStaffPage> queryPage({
    int pageSize = 20,
    String? cursor,
    String? search,
    TenantRole? role,
    MembershipStatus? status,
  }) async {
    if (pageSize < 1 || pageSize > 50) {
      throw RangeError.range(pageSize, 1, 50, 'pageSize');
    }
    final prefix = search == null || search.trim().isEmpty
        ? null
        : tenantStaffSearchTerm(search);
    if (prefix != null && prefix.length < 2) {
      throw const FormatException(
        'Staff search requires at least two characters.',
      );
    }
    final queryReader =
        _queryReader ??
        (_collectionReader is TenantStaffDirectoryQueryReader
            ? _collectionReader as TenantStaffDirectoryQueryReader
            : null);
    if (queryReader == null) {
      if (prefix == null && role == null && status == null) {
        return loadPage(pageSize: pageSize, cursor: cursor);
      }
      throw StateError('Backend staff search is unavailable.');
    }

    final ownerUid = await _validatedOwnerUid();
    final position = cursor == null
        ? null
        : _decodeStaffCursor(
            cursor,
            search: prefix,
            role: role,
            status: status,
          );
    final requestedLimit = pageSize + 1;
    final snapshots = await queryReader.queryTenantStaff(
      TenantStaffDirectoryQuery.scoped(
        collectionPath: paths.collectionPath(TenantCollection.staff),
        limit: requestedLimit,
        searchPrefix: prefix,
        role: role?.wireValue,
        status: status?.wireValue,
        startAfter: position,
      ),
    );
    if (snapshots.length > requestedLimit) {
      throw const TenantScopeViolation(
        'The staff query returned more documents than requested.',
      );
    }
    final seen = <String>{};
    String? previousId;
    for (final snapshot in snapshots) {
      final id = _staffDocumentId(snapshot.path);
      if (!paths.owns(snapshot.path) || !seen.add(id)) {
        throw const TenantScopeViolation(
          'The staff query escaped its canonical tenant scope.',
        );
      }
      if (previousId != null && previousId.compareTo(id) >= 0) {
        throw const TenantScopeViolation(
          'Staff query results were not stably ordered.',
        );
      }
      if (role != null && snapshot.data['role'] != role.wireValue ||
          status != null && snapshot.data['status'] != status.wireValue ||
          prefix != null && !_hasStaffSearchPrefix(snapshot.data, prefix)) {
        throw const TenantScopeViolation(
          'The staff query returned a record outside its filters.',
        );
      }
      previousId = id;
    }
    final hasMore = snapshots.length > pageSize;
    final visible = hasMore
        ? snapshots.take(pageSize).toList(growable: false)
        : snapshots;
    return TenantStaffPage(
      items: <TenantStaffSummary>[
        for (final snapshot in visible)
          TenantStaffSummary.fromSnapshot(snapshot, ownerUid: ownerUid),
      ],
      nextCursor: hasMore
          ? _encodeStaffCursor(
              TenantStaffDirectoryPosition(
                documentId: _staffDocumentId(visible.last.path),
              ),
              search: prefix,
              role: role,
              status: status,
            )
          : null,
      hasMore: hasMore,
    );
  }

  Future<String> _validatedOwnerUid() async {
    final tenant = await readTenantRoot();
    final value = tenant?['ownerUid'];
    if (value is! String) {
      throw const FormatException('The canonical tenant owner is invalid.');
    }
    late final String ownerUid;
    try {
      ownerUid = validateTenantDocumentId(value, fieldName: 'ownerUid');
    } on ArgumentError {
      throw const FormatException('The canonical tenant owner is invalid.');
    }
    final ownerData = await readDocument(TenantCollection.staff, ownerUid);
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
    return ownerUid;
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
    this.queryReader,
    this.clock,
    this.tickets,
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
  final TenantStaffDirectoryQueryReader? queryReader;

  /// The clock the invitation deadline is read against.
  ///
  /// Injectable for the same reason `requestIdFactory` beside it is: *Expired*
  /// is a statement about a moment, and a test that cannot move the moment can
  /// only ever assert the unexpired half of it.
  final DateTime Function()? clock;

  /// Where this device remembers the request id of an unfinished staff
  /// mutation, so a second press after a restart is the same request.
  final TenantStaffRequestTicketSource? tickets;

  /// **The scaffold is built below the guard, not above it.** *Invite staff* is
  /// a page action and belongs at the trailing edge of the toolbar, and whether
  /// this session may invite at all is decided from the guarded session - which
  /// only exists inside the guard. Keeping the bar up here meant the control
  /// could never reach it. Same move the expenses route made for the same
  /// reason.
  @override
  Widget build(BuildContext context) => TenantStaffDirectoryPanel(
    reader: reader,
    cancelInvitationCallable: cancelInvitationCallable,
    inviteCallable: inviteCallable,
    replaceEmailCallable: replaceEmailCallable,
    resendCallable: resendCallable,
    statusCallable: statusCallable,
    updateCallable: updateCallable,
    requestIdFactory: requestIdFactory,
    queryReader: queryReader,
    clock: clock,
    tickets: tickets,
  );
}

/// The staff page's chrome, drawn in every phase of the read.
///
/// The toolbar is the same whether the directory has arrived or not, so it is
/// drawn for real and only the body changes - the rule the skeleton work
/// settled on for every other route here. It carries no action of its own:
/// *Invite staff* is a button at the head of the body now.
final class _StaffFrame extends StatelessWidget {
  const _StaffFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AppScaffold(
    // **One vocabulary, from the drawer to the row.** The destination said
    // `Staff`, this said `User Management`, and the row action said `Correct` -
    // three names for one screen, and the operator was left to work out that
    // all three were the same place. `Staff` is the one the drawer already
    // uses and the one a shopkeeper would say, so the other two moved to it.
    title: 'Staff',
    // **Short enough to survive a phone.** The first attempt at this ran to
    // *Manage your team, their roles, and their access to this business.* and
    // was ellipsised at `their acces...` on a Pixel 6 - longer than the
    // `User Management` line it replaced, and so a readability regression
    // rather than the clarification it was meant to be. Same three nouns, one
    // line that fits.
    subtitle: 'Manage your team, their roles and access.',
    contentWidth: AppContentWidth.records,
    body: child,
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
    this.queryReader,
    this.clock,
    this.tickets,
    this.pageSize = 20,
  });

  final TenantDataReader reader;
  final CancelTenantInvitationCallable? cancelInvitationCallable;
  final InviteStaffCallable? inviteCallable;
  final ReplacePendingStaffEmailCallable? replaceEmailCallable;
  final ResendStaffInvitationCallable? resendCallable;
  final SetStaffStatusCallable? statusCallable;
  final UpdateStaffUserCallable? updateCallable;
  final TenantStaffRequestIdFactory? requestIdFactory;
  final TenantStaffDirectoryQueryReader? queryReader;
  final DateTime Function()? clock;
  final TenantStaffRequestTicketSource? tickets;
  final int pageSize;

  @override
  State<TenantStaffDirectoryPanel> createState() =>
      _TenantStaffDirectoryPanelState();
}

final class _TenantStaffDirectoryPanelState
    extends State<TenantStaffDirectoryPanel> {
  @override
  Widget build(BuildContext context) => _TenantStaffManagementPanel(
    reader: widget.reader,
    cancelInvitationCallable: widget.cancelInvitationCallable,
    inviteCallable: widget.inviteCallable,
    replaceEmailCallable: widget.replaceEmailCallable,
    resendCallable: widget.resendCallable,
    statusCallable: widget.statusCallable,
    updateCallable: widget.updateCallable,
    requestIdFactory: widget.requestIdFactory,
    queryReader: widget.queryReader,
    clock: widget.clock,
    tickets: widget.tickets,
    pageSize: widget.pageSize,
  );
}

/// The familiar staff-directory hierarchy on the canonical typed model.
final class _TenantStaffManagementPanel extends StatefulWidget {
  const _TenantStaffManagementPanel({
    required this.reader,
    required this.cancelInvitationCallable,
    required this.inviteCallable,
    required this.replaceEmailCallable,
    required this.resendCallable,
    required this.statusCallable,
    required this.updateCallable,
    required this.requestIdFactory,
    required this.queryReader,
    required this.clock,
    required this.tickets,
    required this.pageSize,
  });

  final TenantDataReader reader;
  final CancelTenantInvitationCallable? cancelInvitationCallable;
  final InviteStaffCallable? inviteCallable;
  final ReplacePendingStaffEmailCallable? replaceEmailCallable;
  final ResendStaffInvitationCallable? resendCallable;
  final SetStaffStatusCallable? statusCallable;
  final UpdateStaffUserCallable? updateCallable;
  final TenantStaffRequestIdFactory? requestIdFactory;
  final TenantStaffDirectoryQueryReader? queryReader;
  final DateTime Function()? clock;
  final TenantStaffRequestTicketSource? tickets;
  final int pageSize;

  @override
  State<_TenantStaffManagementPanel> createState() =>
      _TenantStaffManagementPanelState();
}

final class _TenantStaffManagementPanelState
    extends State<_TenantStaffManagementPanel> {
  TenantRole? _role;
  MembershipStatus? _status;
  List<String?> _cursors = <String?>[null];
  int _pageIndex = 0;
  int _generation = 0;
  String? _loaderKey;
  TenantGuardedLoader<TenantStaffPage>? _loader;
  TenantGuardedLoader<TenantStaffPage>? _loaderCached;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  void _resetPage() {
    _cursors = <String?>[null];
    _pageIndex = 0;
    _generation++;
  }

  void _reload() {
    if (!mounted) return;
    setState(_resetPage);
  }

  void _setRole(TenantRole? role) {
    if (role == _role) return;
    setState(() {
      _role = role;
      _resetPage();
    });
  }

  void _setStatus(MembershipStatus? status) {
    if (status == _status) return;
    setState(() {
      _status = status;
      _resetPage();
    });
  }

  void _next(String? cursor) {
    if (cursor == null) return;
    setState(() {
      _cursors = <String?>[..._cursors.take(_pageIndex + 1), cursor];
      _pageIndex++;
    });
  }

  void _previous() {
    if (_pageIndex == 0) return;
    setState(() => _pageIndex--);
  }

  void _composeLoaders(String key) {
    if (_loaderKey == key && _loader != null) return;
    _loaderKey = key;
    final cursor = _cursors[_pageIndex];
    final role = _role;
    final status = _status;
    // Both readers per pass. Nothing supplies a `queryReader` today, so the
    // repository resolves the boundary off `reader` and the cached pass is
    // already correct - but naming the live one here is the defect that cost
    // the catalog its offline read, and it would cost this one the same the
    // day a companion is wired.
    TenantGuardedLoader<TenantStaffPage> readWith(
      TenantDataReader reader,
      TenantStaffDirectoryQueryReader? queryReader,
    ) =>
        (session) =>
            TenantStaffDirectoryRepository(
              session: session,
              reader: reader,
              queryReader: queryReader,
            ).queryPage(
              pageSize: widget.pageSize,
              cursor: cursor,
              role: role,
              status: status,
            );
    _loader = readWith(widget.reader, widget.queryReader);
    final cache = widget.reader.cached;
    _loaderCached = cache == null
        ? null
        : readWith(cache, widget.queryReader?.cachedStaffDirectory);
  }

  Future<void> _openForm(
    TenantSession session,
    _StaffActionKind kind, [
    TenantStaffSummary? staff,
  ]) async {
    final sessionController = TenantSessionScope.read(context);
    final compact =
        MediaQuery.sizeOf(context).width < AppLayout.contract.mediumFloor;
    Widget form(BuildContext overlayContext) {
      void close() => Navigator.of(overlayContext).pop();
      // **The confirmation belongs to the form, not to this.** Each of the six
      // already announces its own outcome - and did so before 2026-08-26,
      // through a raw Material `SnackBar` that bypassed the token layer. Those
      // are `showAppSnackBar` now, so they carry §2.1's container and glyph;
      // what did not change is *who* says it. A sentence added here as well
      // would replace the form's, because `showAppSnackBar` deliberately
      // replaces rather than queues - and the form's names the email, which is
      // the more useful half.
      void success() {
        close();
        _reload();
      }

      return switch (kind) {
        _StaffActionKind.invite => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SectionHeading('Invite staff'),
            SizedBox(height: AppTokens.componentOf(context).spacing.s12),
            // The way out is the form's own now, so this form ends in the same
            // stacked pair as every other one on this surface.
            TenantStaffInvitationForm(
              session: session,
              callable: widget.inviteCallable ?? FirebaseInviteStaffCallable(),
              requestIdFactory: widget.requestIdFactory,
              tickets: widget.tickets,
              onSuccess: success,
              onCancel: close,
            ),
          ],
        ),
        _StaffActionKind.correct => TenantStaffUpdateForm(
          session: session,
          target: staff!,
          callable: widget.updateCallable ?? FirebaseUpdateStaffUserCallable(),
          requestIdFactory: widget.requestIdFactory,
          tickets: widget.tickets,
          onSuccess: success,
          onCancel: close,
        ),
        _StaffActionKind.resend => TenantStaffInvitationResendForm(
          session: session,
          target: staff!,
          callable:
              widget.resendCallable ?? FirebaseResendStaffInvitationCallable(),
          requestIdFactory: widget.requestIdFactory,
          tickets: widget.tickets,
          onSuccess: success,
          onCancel: close,
        ),
        _StaffActionKind.cancelInvitation =>
          TenantStaffInvitationCancellationForm(
            session: session,
            target: staff!,
            callable:
                widget.cancelInvitationCallable ??
                FirebaseCancelTenantInvitationCallable(),
            requestIdFactory: widget.requestIdFactory,
            tickets: widget.tickets,
            onSuccess: success,
            onCancel: close,
          ),
        _StaffActionKind.replaceEmail =>
          TenantStaffInvitationEmailReplacementForm(
            session: session,
            target: staff!,
            callable:
                widget.replaceEmailCallable ??
                FirebaseReplacePendingStaffEmailCallable(),
            requestIdFactory: widget.requestIdFactory,
            tickets: widget.tickets,
            onSuccess: success,
            onCancel: close,
          ),
        _StaffActionKind.changeStatus => TenantStaffStatusForm(
          session: session,
          target: staff!,
          callable: widget.statusCallable ?? FirebaseSetStaffStatusCallable(),
          requestIdFactory: widget.requestIdFactory,
          tickets: widget.tickets,
          onSuccess: success,
          onCancel: close,
        ),
      };
    }

    if (compact) {
      await showAppSheet<void>(
        context,
        // **The sheet's own opening detent, not the full screen**, at the
        // developer's direction on 2026-09-22. These forms are three or four
        // fields and a pair of buttons; opening at 0.95 made every one of them
        // read as a route that had replaced the directory rather than a sheet
        // over it, and left the page behind invisible. It is still draggable to
        // full for a form that needs the room.
        dismissible: false,
        builder: (sheetContext, sheetController) => TenantSessionScope(
          controller: sessionController,
          child: ListView(
            controller: sheetController,
            padding: EdgeInsets.fromLTRB(
              AppTokens.componentOf(sheetContext).spacing.s16,
              0,
              AppTokens.componentOf(sheetContext).spacing.s16,
              AppTokens.componentOf(sheetContext).spacing.s24,
            ),
            children: <Widget>[form(sheetContext)],
          ),
        ),
      );
    } else {
      await showAppDialog<void>(
        context,
        builder: (dialogContext) => TenantSessionScope(
          controller: sessionController,
          child: AppDialog(content: form(dialogContext)),
        ),
      );
    }
  }

  List<_StaffMenuAction> _actionsFor(
    TenantSession session,
    TenantStaffSummary staff,
  ) {
    if (!session.canAccess(
      allowedRoles: TenantStaffUpdateGateway.allowedRoles,
    )) {
      return const <_StaffMenuAction>[];
    }
    return <_StaffMenuAction>[
      _StaffMenuAction(
        // **`Correct` was the most dangerous word on this screen.** The form it
        // opens submits name, phone *and* role, so an administrator who
        // believed they were fixing a mistyped phone number was also
        // resubmitting the role their form had loaded - which is the whole of
        // what makes a stale edit able to reinstate a role somebody else has
        // just removed. Naming the role in the verb is what lets a person see
        // that before they press Save rather than afterwards.
        label: 'Edit',
        icon: Icons.edit_outlined,
        key: ValueKey('edit-staff-${staff.uid}'),
        onPressed: () => _openForm(session, _StaffActionKind.correct, staff),
      ),
      if (TenantStaffInvitationResendGateway.canResendTo(staff))
        _StaffMenuAction(
          label: 'Resend invitation',
          icon: Icons.forward_to_inbox_outlined,
          key: ValueKey('resend-staff-invitation-${staff.uid}'),
          onPressed: () => _openForm(session, _StaffActionKind.resend, staff),
        ),
      if (TenantStaffInvitationCancellationGateway.canCancel(staff))
        _StaffMenuAction(
          label: 'Cancel invitation',
          icon: Icons.person_remove_outlined,
          key: ValueKey('cancel-staff-invitation-${staff.uid}'),
          destructive: true,
          onPressed: () =>
              _openForm(session, _StaffActionKind.cancelInvitation, staff),
        ),
      if (TenantStaffInvitationEmailReplacementGateway.canReplaceEmailFor(
        staff,
      ))
        _StaffMenuAction(
          label: 'Replace email',
          icon: Icons.alternate_email_outlined,
          key: ValueKey('replace-staff-email-${staff.uid}'),
          onPressed: () =>
              _openForm(session, _StaffActionKind.replaceEmail, staff),
        ),
      if (TenantStaffStatusGateway.canChangeTarget(staff))
        _StaffMenuAction(
          label: staff.status == MembershipStatus.active
              ? 'Deactivate'
              : 'Activate',
          icon: staff.status == MembershipStatus.active
              ? Icons.person_off_outlined
              : Icons.person_add_alt_outlined,
          key: ValueKey('set-staff-status-${staff.uid}'),
          destructive: staff.status == MembershipStatus.active,
          onPressed: () =>
              _openForm(session, _StaffActionKind.changeStatus, staff),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final key =
        'staff:$_generation:$_pageIndex:'
        '${_role?.wireValue ?? '-'}:${_status?.wireValue ?? '-'}';
    _composeLoaders(key);
    return TenantRouteGuard<TenantStaffPage>(
      allowedRoles: TenantStaffDirectoryScreen.allowedRoles,
      load: _loader!,
      loadCached: _loaderCached,
      // **The loading phase wears the page's own chrome, and that is the
      // jitter of 2026-08-28.** The guard's default is a bare centred spinner
      // which is not inside an `AppScaffold` - and on this route the scaffold
      // is built *below* the guard, so opening staff drew a spinner on a blank
      // screen with no toolbar, no title and no way back, and then snapped the
      // whole page in underneath a route transition that was still running.
      // Nothing was being "checked": the chrome simply did not exist yet.
      //
      // `denied` is deliberately still the guard's own, unframed: this route's
      // home tile is already role-gated, so that phase is a defence-in-depth
      // path a person does not navigate to and does not see jump.
      loading: const _StaffFrame(child: _StaffDirectoryReading()),
      failure: (context, error) => const _StaffFrame(
        child: Center(
          key: ValueKey('staff-directory-failure'),
          child: Text('The staff directory could not be read.'),
        ),
      ),
      builder: (context, session, page) => _StaffFrame(
        child: _StaffManagementContents(
          session: session,
          page: page,
          role: _role,
          status: _status,
          pageIndex: _pageIndex,
          onInvite: _canInvite(session)
              ? () => _openForm(session, _StaffActionKind.invite)
              : null,
          onRoleChanged: _setRole,
          onStatusChanged: _setStatus,
          canInvite: _canInvite(session),
          actionsFor: (staff) => _actionsFor(session, staff),
          invitationStateFor: (staff) => staff.invitationState(_now()),
          selfUid: session.uid,
          onPrevious: _pageIndex == 0 ? null : _previous,
          onNext: page.hasMore ? () => _next(page.nextCursor) : null,
        ),
      ),
    );
  }

  /// Whether this session may invite at all, which is what puts the button at
  /// the head of the page or leaves it out.
  static bool _canInvite(TenantSession session) => session.canAccess(
    allowedRoles: TenantStaffInvitationGateway.allowedRoles,
  );
}

enum _StaffActionKind {
  invite,
  correct,
  resend,
  cancelInvitation,
  replaceEmail,
  changeStatus,
}

@immutable
final class _StaffMenuAction {
  const _StaffMenuAction({
    required this.label,
    required this.icon,
    required this.key,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final Key key;
  final VoidCallback onPressed;
  final bool destructive;
}

final class _StaffManagementContents extends StatelessWidget {
  const _StaffManagementContents({
    required this.session,
    required this.page,
    required this.role,
    required this.status,
    required this.pageIndex,
    required this.onInvite,
    required this.onRoleChanged,
    required this.onStatusChanged,
    required this.canInvite,
    required this.actionsFor,
    required this.invitationStateFor,
    required this.selfUid,
    required this.onPrevious,
    required this.onNext,
  });

  final TenantSession session;
  final TenantStaffPage page;
  final TenantRole? role;
  final MembershipStatus? status;
  final int pageIndex;

  /// Opens the invitation form, or null for a session that may not invite - in
  /// which case the button is not drawn at all rather than drawn disabled. A
  /// control a role can never use is not a state of that control.
  final VoidCallback? onInvite;

  final ValueChanged<TenantRole?> onRoleChanged;
  final ValueChanged<MembershipStatus?> onStatusChanged;

  /// Whether this session may invite. It decides whether the read-only notice
  /// is drawn; [onInvite] decides the button.
  final bool canInvite;
  final List<_StaffMenuAction> Function(TenantStaffSummary) actionsFor;
  final TenantStaffInvitationState Function(TenantStaffSummary)
  invitationStateFor;

  /// The signed-in Auth UID, so one row can be marked as the reader's own.
  final String selfUid;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  /// How wide each of the two filters is once the page is wider than a phone.
  ///
  /// **Named so the placeholder can read it**, and not on §2.3's scale because
  /// it is not a spacing: it is how much room *All statuses* needs beside a
  /// label. A skeleton that guessed it would draw the filter row at one width
  /// and then shuffle it sideways the moment the directory landed.
  static const double filterWidth = 190;

  bool get _hasQuery => role != null || status != null;

  /// The people on this page whose invitation has reached a dead end.
  ///
  /// **Deliberately this page and not the business.** Both conditions are
  /// computed rather than stored - *expired* is a deadline compared to now,
  /// *rejected* is a delivery state - so neither is a field a bounded query
  /// could filter or count on the server. A figure assembled from the rows
  /// currently on screen is exactly the claim the four counters were removed
  /// for making, which is why this names people and states no total.
  List<({TenantStaffSummary staff, StaffStanding standing})>
  get _invitationsInTrouble =>
      <({TenantStaffSummary staff, StaffStanding standing})>[
        for (final member in page.items)
          if (StaffStanding.resolved(
            member.status,
            invitationStateFor(member),
          ).needsAttention)
            (
              staff: member,
              standing: StaffStanding.resolved(
                member.status,
                invitationStateFor(member),
              ),
            ),
      ];

  /// How many people the callout names before it stops naming them.
  ///
  /// Named rather than tokenised, for the reason `EmptyState.markSize` gives:
  /// this is how long a sentence may get before it stops being read, and no
  /// source this app has states one.
  static const int namedInCallout = 3;

  /// One sentence per person, and no count.
  String _troubleMessage(
    List<({TenantStaffSummary staff, StaffStanding standing})> trouble,
  ) {
    final named = trouble.take(namedInCallout);
    final sentences = <String>[
      for (final entry in named)
        switch (entry.standing) {
          StaffStanding.linkExpired =>
            "${entry.staff.displayName}'s invitation link has expired.",
          // The distinction that decides which button the row promotes, said
          // in the words it will be said in there: resending to an address the
          // mail server already refused bounces again.
          StaffStanding.emailRejected =>
            "${entry.staff.displayName}'s email was rejected by the mail "
                'server.',
          _ => '',
        },
    ];
    if (trouble.length > namedInCallout) {
      sentences.add('The rest are marked in the list below.');
    }
    return sentences.join(' ');
  }

  bool get _readOnly =>
      !session.canAccess(
        allowedRoles: TenantStaffInvitationGateway.allowedRoles,
      ) &&
      !session.canAccess(allowedRoles: TenantStaffUpdateGateway.allowedRoles);

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < AppLayout.contract.mediumFloor;
    final inset = width < AppLayout.contract.mediumFloor
        ? tokens.spacing.s16
        : width < AppLayout.contract.expandedFloor
        ? tokens.spacing.s20
        : tokens.spacing.s24;
    return PagedListView(
      listKey: const ValueKey('staff-management'),
      padding: EdgeInsets.all(inset),
      pagination: Pagination(
        pageNumber: pageIndex + 1,
        previousKey: const ValueKey('staff-directory-previous-page'),
        nextKey: const ValueKey('staff-directory-next-page'),
        pageKey: const ValueKey('staff-directory-page'),
        onPrevious: onPrevious,
        onNext: onNext,
        endOfList: !page.hasMore,
      ),
      children: <Widget>[
        // **The page opens on the search field, at the developer's direction on
        // 2026-08-28.** *Invite staff* used to be the first thing in this list,
        // full width on a phone; it is a page action and now sits at the
        // trailing edge of the toolbar, which is where every other route in
        // this app puts the one thing its page is for.
        if (_readOnly) ...<Widget>[
          const Callout(
            key: ValueKey('staff-directory-read-only'),
            status: AppStatus.info,
            title: 'Read-only staff list',
            message:
                'You can see your team and their roles. Only the owner and '
                'administrators can change them.',
          ),
          SizedBox(height: tokens.spacing.s16),
        ],
        // **The four counters are gone, at the developer's direction on
        // 2026-08-28.** They were `Staff`, `Active`, `Invited` and
        // `Owners & admins`, every one of them counted from the page currently
        // on screen rather than from the business - so *Staff 20* on a shop
        // with sixty staff, and four different figures on page two. A block of
        // cards above a list, saying less than the list does.
        //
        // **What is here instead names people rather than counting them**, and
        // that is the whole of why it is allowed to exist where the counters
        // were not. A name read off this page is exact whatever page it is;
        // *2 need attention* over a paginated query is the same claim that was
        // removed. See [_invitationsInTrouble].
        if (_invitationsInTrouble case final trouble
            when trouble.isNotEmpty) ...<Widget>[
          Callout(
            key: const ValueKey('staff-invitations-in-trouble'),
            status: AppStatus.problem,
            title: 'These invitations will not arrive on their own',
            message: _troubleMessage(trouble),
          ),
          SizedBox(height: tokens.spacing.s16),
        ],
        _filters(context, compact: compact),
        SizedBox(height: tokens.spacing.s16),
        _StaffDirectoryList(
          staff: page.items,
          empty: EmptyState(
            key: ValueKey(
              _hasQuery
                  ? 'staff-directory-no-matches'
                  : 'staff-directory-empty',
            ),
            title: _hasQuery ? 'No matching staff' : 'No staff yet',
            hint: _hasQuery
                ? 'Try a different role or status.'
                : 'Invite somebody to give them access to this business.',
            illustration: _hasQuery ? 'file-search.svg' : 'team.svg',
          ),
          actionsFor: actionsFor,
          invitationStateFor: invitationStateFor,
          selfUid: selfUid,
        ),
      ],
    );
  }

  Widget _filters(BuildContext context, {required bool compact}) {
    final tokens = AppTokens.componentOf(context);
    // **The head of the page is the invitation, not a search well**, at the
    // developer's direction on 2026-09-22: the same shape expenses and stock
    // counts now open in - one button the width of the page, with the filters
    // under it. The search field that stood here is gone, and with it the only
    // way to find a colleague by name; the two filters and the pager are what
    // narrow the directory now.
    final invite = onInvite == null
        ? null
        : AppButton(
            key: const ValueKey('invite-staff-open'),
            label: 'Invite staff',
            icon: Icons.person_add_alt_1_outlined,
            tier: AppButtonTier.primary,
            expand: true,
            onPressed: onInvite,
          );
    // **The two filters wear their captions inside themselves.** *Role* over a
    // control reading *All roles* and *Status* over one reading *All statuses*
    // is the same word twice, and on a phone those label rows cost more height
    // than a staff card. Each keeps its label as its accessible name and its
    // leading glyph as the mark that names it, which is the contract
    // `AppSelect.dense` states.
    final roleFilter = AppSelect<String>(
      key: const ValueKey('staff-role-filter'),
      value: role?.wireValue ?? '',
      label: 'Role',
      dense: true,
      leading: Icons.badge_outlined,
      items: <AppSelectItem<String>>[
        const AppSelectItem<String>(value: '', label: 'All roles'),
        for (final item in TenantRole.values)
          AppSelectItem<String>(
            value: item.wireValue,
            label: tenantRoleLabel(item),
          ),
      ],
      onChanged: (value) => onRoleChanged(
        value == null || value.isEmpty ? null : TenantRole.fromWire(value),
      ),
    );
    final statusFilter = AppSelect<String>(
      key: const ValueKey('staff-status-filter'),
      value: status?.wireValue ?? '',
      label: 'Status',
      dense: true,
      leading: Icons.filter_alt_outlined,
      items: <AppSelectItem<String>>[
        const AppSelectItem<String>(value: '', label: 'All statuses'),
        for (final item in MembershipStatus.values)
          AppSelectItem<String>(
            value: item.wireValue,
            label: membershipStatusLabel(item),
          ),
      ],
      onChanged: (value) => onStatusChanged(
        value == null || value.isEmpty
            ? null
            : MembershipStatus.fromWire(value),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (invite != null) ...<Widget>[
          invite,
          SizedBox(height: tokens.spacing.s12),
        ],
        // **The filters stay at their own width past a phone rather than
        // stretching to the page.** Two selects spread across a desktop column
        // put *All roles* and *All statuses* a hand's width apart for no
        // reason; the pair reads as a pair at the width the row already had
        // them at.
        if (compact)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: roleFilter),
              SizedBox(width: tokens.spacing.s8),
              Expanded(child: statusFilter),
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(width: filterWidth, child: roleFilter),
              SizedBox(width: tokens.spacing.s12),
              SizedBox(width: filterWidth, child: statusFilter),
            ],
          ),
      ],
    );
  }
}

/// The staff page while its directory is still being read.
///
/// **Shaped like the page that replaces it**: the filter row is drawn in its
/// real wells with its real labels, and only the records shimmer. Decision 35's
/// argument, and on this route it is the one that matters - the two filters
/// under real wells tell a person they have arrived at the right screen a beat
/// before the list can.
///
/// **The invite button is a block, not a real button.** Whether this session
/// may invite is read off the session the guard has not produced yet, so a real
/// button here would either lie to a manager who cannot invite or be drawn
/// disabled for an owner who can. A block holds its height and claims nothing,
/// and the row below it does not move when the answer lands.
///
/// **It claims nothing about what is coming.** No count, no "no staff yet" -
/// both are answers this state does not have, and the second is the one a
/// shopkeeper would act on.
final class _StaffDirectoryReading extends StatelessWidget {
  const _StaffDirectoryReading();

  /// Four cards, which fills a phone without pretending to know how many people
  /// work here. The same figure `RecordListSkeleton` defends for the same
  /// reason.
  static const int _cards = 4;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < AppLayout.contract.mediumFloor;
    // The same three-way inset `_StaffManagementContents` takes, because a
    // placeholder indented differently from its content moves the whole page
    // sideways the moment the read lands.
    final inset = width < AppLayout.contract.mediumFloor
        ? tokens.spacing.s16
        : width < AppLayout.contract.expandedFloor
        ? tokens.spacing.s20
        : tokens.spacing.s24;
    // The controls exactly as they will be: the invitation's block, and the
    // two filters holding the everything-selected option they open on.
    // **No captions here either, and that is load-bearing rather than tidy.**
    // This state exists so the filter row is drawn in its real wells at its
    // real height before the directory lands; a skeleton that still reserved
    // label rows would drop the whole page by their height the moment it did.
    // `SkeletonField` draws no label row for an empty one, exactly as
    // `AppFieldWell` does.
    final invite = SkeletonBlock(height: AppButtonSize.lg.height);
    const role = SkeletonField(
      label: '',
      leading: Icons.badge_outlined,
      value: 'All roles',
      trailing: Icons.arrow_drop_down,
    );
    const status = SkeletonField(
      label: '',
      leading: Icons.filter_alt_outlined,
      value: 'All statuses',
      trailing: Icons.arrow_drop_down,
    );
    return SkeletonGroup(
      semanticLabel: 'Reading the staff directory.',
      child: ListView(
        key: const ValueKey('staff-directory-reading'),
        padding: EdgeInsets.all(inset),
        children: <Widget>[
          invite,
          SizedBox(height: tokens.spacing.s12),
          if (compact)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Expanded(child: role),
                SizedBox(width: tokens.spacing.s8),
                const Expanded(child: status),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SizedBox(
                  width: _StaffManagementContents.filterWidth,
                  child: role,
                ),
                SizedBox(width: tokens.spacing.s12),
                const SizedBox(
                  width: _StaffManagementContents.filterWidth,
                  child: status,
                ),
              ],
            ),
          SizedBox(height: tokens.spacing.s16),
          for (var card = 0; card < _cards; card++) const _StaffCardSkeleton(),
        ],
      ),
    );
  }
}

/// One placeholder staff card, arranged like the card it stands in for.
///
/// **The card's own frame is real and only its facts are blocks.** A featureless
/// slab reserves the right space and says nothing; this says, before the read
/// lands, that a staff record is a person's block, their name and address, a
/// menu, and a role beside a status - which is the whole argument for a
/// skeleton over a spinner.
final class _StaffCardSkeleton extends StatelessWidget {
  const _StaffCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    // Everything sits inside a `surface.raised` card, so every block steps up
    // from that rather than matching it.
    const tone = SkeletonTone.onRaised;
    return Container(
      margin: EdgeInsets.only(bottom: tokens.spacing.s12),
      padding: EdgeInsets.all(tokens.spacing.s16),
      decoration: BoxDecoration(
        color: tokens.colors.surface.raised,
        borderRadius: BorderRadius.circular(tokens.radius.lg),
        border: Border.all(color: tokens.colors.surface.cardEdge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SkeletonBlock(
                width: _StaffAvatar.cardSize,
                height: _StaffAvatar.cardSize,
                radius: tokens.radius.lg,
                tone: tone,
              ),
              SizedBox(width: tokens.spacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // The name, then the address, at the two roles
                    // `_StaffIdentity` gives them.
                    SkeletonLine(
                      widthFactor: 0.52,
                      style: tokens.typography.bodyLarge,
                      tone: tone,
                    ),
                    SizedBox(height: tokens.spacing.s4),
                    SkeletonLine(
                      widthFactor: 0.78,
                      style: tokens.typography.bodyMedium,
                      tone: tone,
                    ),
                  ],
                ),
              ),
              SizedBox(width: tokens.spacing.s8),
              SkeletonBlock(
                width: tokens.spacing.s24,
                height: tokens.spacing.s24,
                radius: tokens.radius.sm,
                tone: tone,
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.s16),
          Row(
            children: <Widget>[
              // The role pill and the membership badge, which are both rounded
              // containers rather than lines - so they are blocks at the pill's
              // own corner rather than text placeholders.
              SkeletonBlock(
                width: tokens.spacing.s64,
                height: tokens.spacing.s24,
                radius: tokens.radius.md,
                tone: tone,
              ),
              SizedBox(width: tokens.spacing.s12),
              SkeletonBlock(
                width: tokens.spacing.s48,
                height: tokens.spacing.s24,
                radius: tokens.radius.md,
                tone: tone,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

final class _StaffDirectoryList extends StatelessWidget {
  const _StaffDirectoryList({
    required this.staff,
    required this.empty,
    required this.actionsFor,
    required this.invitationStateFor,
    required this.selfUid,
  });

  final List<TenantStaffSummary> staff;
  final Widget empty;
  final List<_StaffMenuAction> Function(TenantStaffSummary) actionsFor;

  /// The deadline applied to one row, resolved against the screen's clock.
  ///
  /// A function rather than a `DateTime` threaded through four widgets, for the
  /// reason [actionsFor] beside it is one: the row asks what to say about this
  /// member, and the screen - which owns the clock - answers.
  final TenantStaffInvitationState Function(TenantStaffSummary)
  invitationStateFor;
  final String selfUid;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final table = width >= AppLayout.contract.mediumFloor;
    final contents = staff.isEmpty
        ? Padding(padding: EdgeInsets.all(tokens.spacing.s32), child: empty)
        : table
        ? _StaffTable(
            staff: staff,
            showInvitation: width >= 1200,
            actionsFor: actionsFor,
            invitationStateFor: invitationStateFor,
            selfUid: selfUid,
          )
        : Padding(
            padding: EdgeInsets.all(tokens.spacing.s8),
            child: Column(
              children: <Widget>[
                for (final member in staff)
                  _StaffCard(
                    staff: member,
                    actions: actionsFor(member),
                    invitationState: invitationStateFor(member),
                    isSelf: member.uid == selfUid,
                  ),
              ],
            ),
          );
    // **The frame is the table's, not the cards'.** A table is one object with
    // rows in it and wants an edge around the whole; cards each carry their own
    // now, and a box around a column of boxes is a second frame saying nothing
    // the first did not - which is what the old app's list did *not* do.
    if (!table) {
      return KeyedSubtree(
        key: const ValueKey('staff-directory-cards'),
        child: contents,
      );
    }
    return Container(
      key: const ValueKey('staff-directory-table'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: tokens.colors.surface.raised,
        // See [_StaffCard]: the surfaces of this directory take `radius.lg`
        // together since 2026-08-26, so the container, the cards inside it and
        // the avatars on them stay one shape.
        borderRadius: BorderRadius.circular(tokens.radius.lg),
        border: Border.all(color: tokens.colors.surface.cardEdge),
      ),
      child: contents,
    );
  }
}

/// One staff member, on the surface too narrow for the table.
///
/// **`radius.lg` since 2026-08-26, where §2.3 gives a card `md`.** The product
/// owner's call: these read as rigid at 8, and `lg` is the largest corner this
/// app has that is not a capsule. It is taken as a set — this card, the
/// container that holds the list, and the avatar square on each row — because a
/// card rounder than the box around it looks like a mistake rather than a
/// choice. Recorded in `docs/stitch/OPEN_QUESTIONS.md` beside decision 26a,
/// which this deliberately departs from.
final class _StaffCard extends StatelessWidget {
  const _StaffCard({
    required this.staff,
    required this.actions,
    required this.invitationState,
    required this.isSelf,
  });

  final TenantStaffSummary staff;
  final List<_StaffMenuAction> actions;
  final TenantStaffInvitationState invitationState;
  final bool isSelf;

  /// This row's one standing, from the two fields it already held.
  StaffStanding get standing =>
      StaffStanding.resolved(staff.status, invitationState);

  /// The action this standing promotes, where the row has one to promote.
  ///
  /// **Found among the actions already built for the kebab, by key.** It is the
  /// same action in a second place, not a second action: if this session may
  /// not take it, `actionsFor` never built it and nothing is drawn. That is
  /// what keeps a promoted button from becoming a permission of its own.
  _StaffMenuAction? get _promoted {
    final key = standing.promotedActionKeyFor(staff.uid);
    if (key == null) return null;
    for (final action in actions) {
      if (action.key == ValueKey<String>(key)) return action;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    // **The old app's card, rebuilt on this app's tokens.** `screens/users.dart`
    // drew a bordered `bgMid` block: a 48 avatar in the person's own colour, the
    // name and address beside it, the overflow menu on the same line, then one
    // metadata row carrying a tinted role pill, a status dot and its word. What
    // this had instead was an unbordered block painted `surface.base` - the page
    // colour - so a column of them read as one slab, and a pair of labelled
    // key-value lines where the old card had the pill and the dot.
    return Container(
      key: ValueKey('staff-record-${staff.uid}'),
      margin: EdgeInsets.only(bottom: tokens.spacing.s12),
      padding: EdgeInsets.all(tokens.spacing.s16),
      decoration: BoxDecoration(
        color: tokens.colors.surface.raised,
        borderRadius: BorderRadius.circular(tokens.radius.lg),
        border: Border.all(color: tokens.colors.surface.cardEdge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _StaffAvatar(staff: staff, size: _StaffAvatar.cardSize),
              SizedBox(width: tokens.spacing.s12),
              Expanded(
                child: _StaffIdentity(
                  staff: staff,
                  showPhone: true,
                  invitationState: invitationState,
                  isSelf: isSelf,
                ),
              ),
              if (actions.isNotEmpty)
                _StaffActionMenu(staff: staff, actions: actions),
            ],
          ),
          SizedBox(height: tokens.spacing.s16),
          // **One standing, where the membership badge and the invitation
          // caption used to be two marks.** `StaffStanding` resolves the two
          // fields into the one word this screen is opened to find out, and
          // `_promoted` lifts the action that word implies out of the kebab.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              _StaffRolePill(
                key: ValueKey('staff-role-${staff.uid}'),
                staff: staff,
              ),
              SizedBox(width: tokens.spacing.s12),
              Flexible(child: _standingBadge(staff, standing)),
              if (_promoted case final promoted?) ...<Widget>[
                const Spacer(),
                AppButton(
                  key: ValueKey('staff-promoted-${staff.uid}'),
                  label: standing.promotedActionLabel!,
                  tier: AppButtonTier.secondary,
                  size: AppButtonSize.sm,
                  onPressed: promoted.onPressed,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// A member's role, as the tinted pill the old card wore.
///
/// **A pill again, at the developer's direction on 2026-08-28.** It had been
/// demoted to a labelled key-value line under a rule about badges - that a list
/// where two things wear a badge has neither of them meaning anything. The rule
/// holds for *statuses*; a role is not one. It is who somebody is, it does not
/// change while anyone is looking at it, and the old app's readers recognised
/// their administrators by the violet before they read the word.
final class _StaffRolePill extends StatelessWidget {
  const _StaffRolePill({super.key, required this.staff});

  final TenantStaffSummary staff;

  /// The glyph beside the word, per role. The old card's own three.
  static IconData iconFor(TenantRole role) => switch (role) {
    TenantRole.owner => Icons.workspace_premium_outlined,
    TenantRole.admin => Icons.admin_panel_settings_outlined,
    TenantRole.manager => Icons.people_outline,
    TenantRole.cashier => Icons.receipt_long_outlined,
  };

  /// How far the pill's fill is tinted from its own ink.
  static const double fill = 0.16;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    // Owners and administrators wear the privileged colour; everybody else
    // wears the brand's own, exactly as the old card split them.
    final privileged =
        staff.isOwner ||
        staff.role == TenantRole.owner ||
        staff.role == TenantRole.admin;
    // **A role stops wearing the action green.** Everybody below an
    // administrator was tinted with `action.primary.container` - the same green
    // as the *Active* badge and the *Invite staff* button, three jobs for one
    // colour on one row, so a manager's pill read as a standing. The privileged
    // violet stays: it is the one identity colour the token layer documents as
    // carrying meaning, and the old app's readers recognised an administrator
    // by it before they read the word.
    final ink = privileged
        ? tokens.colors.accent.privileged
        : tokens.colors.text.secondary;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.s8,
        vertical: tokens.spacing.s4,
      ),
      decoration: BoxDecoration(
        color: privileged
            ? tokens.colors.accent.privileged.withValues(alpha: fill)
            : tokens.colors.surface.field,
        borderRadius: BorderRadius.circular(tokens.radius.md),
        border: privileged
            ? null
            : Border.all(color: tokens.colors.surface.borderStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(iconFor(staff.role), size: StatusBadge.iconSize, color: ink),
          SizedBox(width: tokens.spacing.s4),
          Text(
            tenantRoleLabel(staff.role),
            style: tokens.typography.labelMedium.copyWith(
              color: ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Marks the signed-in person's own row.
///
/// **Because every action on this screen is one they can aim at themselves.**
/// An administrator may change their own role or deactivate their own
/// membership, and the row offering that was drawn exactly like the twenty
/// employee rows around it. The backend protects the *owner* from self-demotion
/// and nothing else, so for an admin the only thing between them and locking
/// themselves out of their own business was noticing which row they were on.
///
/// A word rather than a tint, per §9: the one thing that must not convey a
/// status is colour on its own.
final class _SelfMarker extends StatelessWidget {
  const _SelfMarker();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final ink = tokens.colors.text.secondary;
    return Container(
      key: const ValueKey('staff-self-marker'),
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.s8,
        vertical: tokens.spacing.s4,
      ),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: _StaffRolePill.fill),
        borderRadius: BorderRadius.circular(tokens.radius.md),
      ),
      child: Text(
        'You',
        style: tokens.typography.labelMedium.copyWith(
          color: ink,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

final class _StaffTable extends StatelessWidget {
  const _StaffTable({
    required this.staff,
    required this.showInvitation,
    required this.actionsFor,
    required this.invitationStateFor,
    required this.selfUid,
  });

  final List<TenantStaffSummary> staff;
  final bool showInvitation;
  final List<_StaffMenuAction> Function(TenantStaffSummary) actionsFor;
  final TenantStaffInvitationState Function(TenantStaffSummary)
  invitationStateFor;
  final String selfUid;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Column(
      children: <Widget>[
        _StaffTableRow(
          header: true,
          showInvitation: showInvitation,
          identity: const Text('Staff member'),
          role: const Text('Role'),
          status: const Text('Status'),
          invitation: const Text('Invitation'),
          actions: const Text('Actions'),
        ),
        for (final (index, member) in staff.indexed) ...<Widget>[
          if (index > 0)
            Divider(height: 1, color: tokens.colors.surface.borderSubtle),
          _StaffTableRow(
            key: ValueKey('staff-record-${member.uid}'),
            showInvitation: showInvitation,
            identity: Row(
              children: <Widget>[
                _StaffAvatar(staff: member, size: 40),
                SizedBox(width: tokens.spacing.s12),
                Expanded(
                  child: _StaffIdentity(
                    staff: member,
                    invitationState: invitationStateFor(member),
                    isSelf: member.uid == selfUid,
                    invitationInIdentity:
                        !showInvitation &&
                        member.status == MembershipStatus.pending,
                  ),
                ),
              ],
            ),
            role: Text(
              tenantRoleLabel(member.role),
              key: ValueKey('staff-role-${member.uid}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            status: _standingBadge(
              member,
              StaffStanding.resolved(member.status, invitationStateFor(member)),
            ),
            invitation: Text(
              member.status == MembershipStatus.pending
                  ? staffInvitationStatusLabel(invitationStateFor(member))
                  : '—',
              key: ValueKey('staff-invitation-${member.uid}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: Align(
              alignment: Alignment.centerRight,
              child: _StaffActionMenu(
                staff: member,
                actions: actionsFor(member),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

final class _StaffTableRow extends StatelessWidget {
  const _StaffTableRow({
    super.key,
    required this.showInvitation,
    required this.identity,
    required this.role,
    required this.status,
    required this.invitation,
    required this.actions,
    this.header = false,
  });

  final bool showInvitation;
  final Widget identity;
  final Widget role;
  final Widget status;
  final Widget invitation;
  final Widget actions;
  final bool header;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final style = header
        ? tokens.typography.labelMedium.copyWith(
            color: tokens.colors.text.secondary,
            fontWeight: FontWeight.w700,
          )
        : tokens.typography.bodyMedium.copyWith(
            color: tokens.colors.text.primary,
          );
    return DefaultTextStyle(
      style: style,
      child: Container(
        color: header ? tokens.colors.surface.sunken : null,
        constraints: BoxConstraints(minHeight: header ? 48 : 72),
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.s16,
          vertical: tokens.spacing.s8,
        ),
        child: Row(
          children: <Widget>[
            Expanded(flex: 4, child: identity),
            SizedBox(width: tokens.spacing.s12),
            Expanded(flex: 2, child: role),
            SizedBox(width: tokens.spacing.s12),
            Expanded(flex: 2, child: status),
            if (showInvitation) ...<Widget>[
              SizedBox(width: tokens.spacing.s12),
              Expanded(flex: 2, child: invitation),
            ],
            SizedBox(width: tokens.spacing.s8),
            SizedBox(width: tokens.spacing.s64, child: actions),
          ],
        ),
      ),
    );
  }
}

final class _StaffIdentity extends StatelessWidget {
  const _StaffIdentity({
    required this.staff,
    required this.invitationState,
    required this.isSelf,
    this.showPhone = false,
    this.invitationInIdentity = false,
  });

  final TenantStaffSummary staff;
  final TenantStaffInvitationState invitationState;

  /// Whether this row is the signed-in person's own membership.
  final bool isSelf;
  final bool showPhone;
  final bool invitationInIdentity;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Flexible(
              child: Text(
                staff.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: tokens.typography.bodyLarge.copyWith(
                  color: tokens.colors.text.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (isSelf) ...<Widget>[
              SizedBox(width: tokens.spacing.s8),
              const _SelfMarker(),
            ],
          ],
        ),
        SizedBox(height: tokens.spacing.s4),
        Text(
          staff.email,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: tokens.typography.bodyMedium.copyWith(
            color: tokens.colors.text.secondary,
          ),
        ),
        if (showPhone && staff.phone != null) ...<Widget>[
          SizedBox(height: tokens.spacing.s4),
          Text(
            staff.phone!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tokens.typography.caption.copyWith(
              color: tokens.colors.text.tertiary,
            ),
          ),
        ],
        if (invitationInIdentity) ...<Widget>[
          SizedBox(height: tokens.spacing.s4),
          Text(
            'Invitation: ${staffInvitationStatusLabel(invitationState)}',
            key: ValueKey('staff-invitation-${staff.uid}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tokens.typography.caption.copyWith(
              color: tokens.colors.text.tertiary,
            ),
          ),
        ],
      ],
    );
  }
}

/// A member's initials in a block.
///
/// **No identity hue since 2026-09-22**, at the developer's direction. The
/// block used to carry a two-pixel ring in one of six colours keyed off the
/// member's uid, on the argument that a recognisable face makes a scrolling
/// list scannable. Six hues cycling down a directory of twenty is not a face,
/// and the row already carries the name, the role and the standing - so the
/// ring was colour that meant nothing, on the one element of the row that had
/// nothing else to say. What is left is the well the initials always sat on,
/// with the page's own subtle edge.
final class _StaffAvatar extends StatelessWidget {
  const _StaffAvatar({required this.staff, required this.size});

  final TenantStaffSummary staff;
  final double size;

  /// The old card's 48, which is also §9's minimum target - so the block is
  /// never smaller than a thing a finger could be asked to hit.
  static const double cardSize = 48;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Semantics(
      label: '${staff.displayName} initials',
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        // **The initials go on `surface.field` in ordinary primary ink**, which
        // measures 11.8:1. That much is unchanged and is why the block was
        // never a filled colour: `text.onAccent` on `#FFA726` is 1.94:1 against
        // §9's 4.5, and tinting the fill does not rescue it either - `#AB47BC`
        // on its own 16% tint is 3.12:1. What has gone is the identity ring
        // that used to edge it; the block keeps the page's own hairline so it
        // still reads as a block.
        decoration: BoxDecoration(
          color: tokens.colors.surface.field,
          borderRadius: BorderRadius.circular(tokens.radius.lg),
          border: Border.all(color: tokens.colors.surface.borderSubtle),
        ),
        child: Text(
          _initials(staff.displayName),
          style: tokens.typography.labelLarge.copyWith(
            color: tokens.colors.text.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

final class _StaffActionMenu extends StatelessWidget {
  const _StaffActionMenu({required this.staff, required this.actions});

  final TenantStaffSummary staff;
  final List<_StaffMenuAction> actions;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    if (actions.isEmpty) {
      return SizedBox(width: tokens.spacing.s48, height: tokens.spacing.s48);
    }
    return PopupMenuButton<int>(
      key: ValueKey('staff-actions-${staff.uid}'),
      tooltip: 'Actions for ${staff.displayName}',
      icon: const Icon(Icons.more_vert),
      onSelected: (index) => actions[index].onPressed(),
      itemBuilder: (context) => <PopupMenuEntry<int>>[
        for (final (index, action) in actions.indexed)
          PopupMenuItem<int>(
            key: action.key,
            value: index,
            height: 48,
            child: Semantics(
              label: '${action.label} ${staff.displayName}',
              child: Row(
                children: <Widget>[
                  Icon(
                    action.icon,
                    size: 20,
                    color: action.destructive
                        ? tokens.colors.status.problem.fg
                        : tokens.colors.text.secondary,
                  ),
                  SizedBox(width: tokens.spacing.s12),
                  Expanded(
                    child: Text(
                      action.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.typography.bodyMedium.copyWith(
                        color: action.destructive
                            ? tokens.colors.status.problem.fg
                            : tokens.colors.text.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// One row's standing, as the badge both renderings wear.
///
/// **This replaces `_membershipBadge`.** That one labelled the membership
/// alone - *Pending* - which is the field, not the answer: three of the five
/// things a pending membership can be are somebody's problem and two are not,
/// and the word *Pending* separates none of them.
StatusBadge _standingBadge(TenantStaffSummary staff, StaffStanding standing) =>
    StatusBadge(
      key: ValueKey('staff-standing-${staff.uid}'),
      label: standing.label,
      status: standing.status,
      icon: standing.icon,
      semanticLabel: standing.semanticLabel,
    );

String _initials(String value) {
  final words = value
      .trim()
      .split(RegExp(r'[\s@._-]+'))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) return '?';
  final first = words.first.characters.first;
  final second = words.length > 1 ? words[1].characters.first : '';
  return '$first$second'.toUpperCase();
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

/// Normalizes a name/email term exactly as the server's staff projections do.
String tenantStaffSearchTerm(String value) {
  final normalized = value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty || normalized.length > 120) {
    throw const FormatException('Invalid staff search term.');
  }
  for (final codeUnit in normalized.codeUnits) {
    if (codeUnit < 0x20 || codeUnit == 0x7f) {
      throw const FormatException('Invalid staff search term.');
    }
  }
  return normalized;
}

bool _hasStaffSearchPrefix(Map<String, Object?> data, String prefix) {
  final values = data['searchPrefixes'];
  return values is List<Object?> && values.contains(prefix);
}

String _encodeStaffCursor(
  TenantStaffDirectoryPosition position, {
  required String? search,
  required TenantRole? role,
  required MembershipStatus? status,
}) => base64Url
    .encode(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'v': 1,
          'id': position.documentId,
          'q': search,
          'r': role?.wireValue,
          's': status?.wireValue,
        }),
      ),
    )
    .replaceAll('=', '');

TenantStaffDirectoryPosition _decodeStaffCursor(
  String cursor, {
  required String? search,
  required TenantRole? role,
  required MembershipStatus? status,
}) {
  try {
    final padded = cursor.padRight((cursor.length + 3) ~/ 4 * 4, '=');
    final value = jsonDecode(utf8.decode(base64Url.decode(padded)));
    if (value is! Map<String, dynamic> ||
        value.length != 5 ||
        value['v'] != 1 ||
        value['q'] != search ||
        value['r'] != role?.wireValue ||
        value['s'] != status?.wireValue ||
        value['id'] is! String) {
      throw const FormatException('Invalid staff cursor.');
    }
    return TenantStaffDirectoryPosition(
      documentId: validateTenantDocumentId(
        value['id'] as String,
        fieldName: 'cursor',
      ),
    );
  } catch (_) {
    throw const FormatException('Invalid staff cursor.');
  }
}
