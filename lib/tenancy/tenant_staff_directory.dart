import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../ui/dialogs.dart';
import '../ui/fields.dart';
import '../ui/pagination.dart';
import '../ui/scaffold.dart';
import '../ui/sheet.dart';
import '../ui/states.dart';
import '../ui/stats.dart';
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
  );
}

/// The staff page's chrome, drawn in every phase of the read.
///
/// The toolbar and its action are the same whether the directory has arrived
/// or not, so they are drawn for real and only the body changes - the rule the
/// skeleton work settled on for every other route here.
final class _StaffFrame extends StatelessWidget {
  const _StaffFrame({required this.child, this.action});

  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'User Management',
    subtitle: 'Manage user accounts and permissions.',
    contentWidth: AppContentWidth.records,
    primaryAction: action,
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
  final int pageSize;

  @override
  State<_TenantStaffManagementPanel> createState() =>
      _TenantStaffManagementPanelState();
}

final class _TenantStaffManagementPanelState
    extends State<_TenantStaffManagementPanel> {
  final TextEditingController _search = TextEditingController();
  Timer? _searchDebounce;
  String _searchTerm = '';
  TenantRole? _role;
  MembershipStatus? _status;
  List<String?> _cursors = <String?>[null];
  int _pageIndex = 0;
  int _generation = 0;
  String? _loaderKey;
  TenantGuardedLoader<TenantStaffPage>? _loader;
  TenantGuardedLoader<TenantStaffPage>? _loaderCached;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _resetPage() {
    _cursors = <String?>[null];
    _pageIndex = 0;
    _generation++;
  }

  void _reload() {
    if (!mounted) return;
    setState(_resetPage);
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(AppMotion.standard.long.duration, () {
      if (!mounted) return;
      final trimmed = value.trim();
      final next = trimmed.length < 2 ? '' : tenantStaffSearchTerm(trimmed);
      if (next == _searchTerm) {
        setState(() {});
        return;
      }
      setState(() {
        _searchTerm = next;
        _resetPage();
      });
    });
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
    final search = _searchTerm;
    final role = _role;
    final status = _status;
    TenantGuardedLoader<TenantStaffPage> readWith(TenantDataReader reader) =>
        (session) =>
        TenantStaffDirectoryRepository(
          session: session,
          reader: reader,
          queryReader: widget.queryReader,
        ).queryPage(
          pageSize: widget.pageSize,
          cursor: cursor,
          search: search.isEmpty ? null : search,
          role: role,
          status: status,
        );
    _loader = readWith(widget.reader);
    final cache = widget.reader.cached;
    _loaderCached = cache == null ? null : readWith(cache);
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
            TenantStaffInvitationForm(
              session: session,
              callable: widget.inviteCallable ?? FirebaseInviteStaffCallable(),
              requestIdFactory: widget.requestIdFactory,
              onSuccess: success,
            ),
            SizedBox(height: AppTokens.componentOf(context).spacing.s8),
            AppButton(
              key: const ValueKey('invite-staff-cancel'),
              label: 'Cancel',
              tier: AppButtonTier.tertiary,
              onPressed: close,
            ),
          ],
        ),
        _StaffActionKind.correct => TenantStaffUpdateForm(
          session: session,
          target: staff!,
          callable: widget.updateCallable ?? FirebaseUpdateStaffUserCallable(),
          requestIdFactory: widget.requestIdFactory,
          onSuccess: success,
          onCancel: close,
        ),
        _StaffActionKind.resend => TenantStaffInvitationResendForm(
          session: session,
          target: staff!,
          callable:
              widget.resendCallable ?? FirebaseResendStaffInvitationCallable(),
          requestIdFactory: widget.requestIdFactory,
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
            onSuccess: success,
            onCancel: close,
          ),
        _StaffActionKind.changeStatus => TenantStaffStatusForm(
          session: session,
          target: staff!,
          callable: widget.statusCallable ?? FirebaseSetStaffStatusCallable(),
          requestIdFactory: widget.requestIdFactory,
          onSuccess: success,
          onCancel: close,
        ),
      };
    }

    if (compact) {
      await showAppSheet<void>(
        context,
        initialDetent: AppSheetDetent.full,
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
        label: 'Correct',
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
        'staff:$_generation:$_pageIndex:$_searchTerm:'
        '${_role?.wireValue ?? '-'}:${_status?.wireValue ?? '-'}';
    _composeLoaders(key);
    return TenantRouteGuard<TenantStaffPage>(
      key: ValueKey(key),
      allowedRoles: TenantStaffDirectoryScreen.allowedRoles,
      load: _loader!,
      loadCached: _loaderCached,
      failure: (context, error) => const _StaffFrame(
        child: Center(
          key: ValueKey('staff-directory-failure'),
          child: Text('The staff directory could not be read.'),
        ),
      ),
      builder: (context, session, page) => _StaffFrame(
        action: _canInvite(session)
            ? AppIconButton(
                key: const ValueKey('invite-staff-open'),
                icon: Icons.person_add_alt_1_outlined,
                iconSize: AppButton.prominentIconSize,
                semanticLabel: 'Invite staff',
                // Tertiary and unbordered: the primary tier's label is the
                // near-black ink meant for a mint container, and an unbordered
                // icon button paints no container - so a primary glyph here
                // would be black on the bar's own dark surface.
                tier: AppButtonTier.tertiary,
                bordered: false,
                onPressed: () => _openForm(session, _StaffActionKind.invite),
              )
            : null,
        child: _StaffManagementContents(
          session: session,
          page: page,
          search: _search,
          searchTerm: _searchTerm,
          role: _role,
          status: _status,
          pageIndex: _pageIndex,
          onSearchChanged: _onSearchChanged,
          onRoleChanged: _setRole,
          onStatusChanged: _setStatus,
          canInvite: _canInvite(session),
          actionsFor: (staff) => _actionsFor(session, staff),
          onPrevious: _pageIndex == 0 ? null : _previous,
          onNext: page.hasMore ? () => _next(page.nextCursor) : null,
        ),
      ),
    );
  }

  /// Whether this session may invite at all, which is what puts the control in
  /// the toolbar or leaves it out.
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
    required this.search,
    required this.searchTerm,
    required this.role,
    required this.status,
    required this.pageIndex,
    required this.onSearchChanged,
    required this.onRoleChanged,
    required this.onStatusChanged,
    required this.canInvite,
    required this.actionsFor,
    required this.onPrevious,
    required this.onNext,
  });

  final TenantSession session;
  final TenantStaffPage page;
  final TextEditingController search;
  final String searchTerm;
  final TenantRole? role;
  final MembershipStatus? status;
  final int pageIndex;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<TenantRole?> onRoleChanged;
  final ValueChanged<MembershipStatus?> onStatusChanged;
  /// Whether this session may invite. It decides only whether the read-only
  /// notice is drawn - the control itself is in the toolbar now.
  final bool canInvite;
  final List<_StaffMenuAction> Function(TenantStaffSummary) actionsFor;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  bool get _hasQuery => searchTerm.isNotEmpty || role != null || status != null;

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
    return ListView(
      key: const ValueKey('staff-management'),
      padding: EdgeInsets.all(inset),
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
            title: 'Read-only staff directory',
            message:
                'You can review staff accounts and permissions. Account '
                'changes are available to owners and administrators.',
          ),
          SizedBox(height: tokens.spacing.s16),
        ],
        // **The four counters are gone, at the developer's direction on
        // 2026-08-28.** They were `Staff`, `Active`, `Invited` and
        // `Owners & admins`, every one of them counted from the page currently
        // on screen rather than from the business - so *Staff 20* on a shop
        // with sixty staff, and four different figures on page two. A block of
        // cards above a list, saying less than the list does.
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
                ? 'Try a different name, email, role, or status.'
                : 'Invite somebody to give them access to this business.',
          ),
          actionsFor: actionsFor,
        ),
        SizedBox(height: tokens.spacing.s16),
        Pagination(
          pageNumber: pageIndex + 1,
          previousKey: const ValueKey('staff-directory-previous-page'),
          nextKey: const ValueKey('staff-directory-next-page'),
          pageKey: const ValueKey('staff-directory-page'),
          onPrevious: onPrevious,
          onNext: onNext,
        ),
      ],
    );
  }
  Widget _filters(BuildContext context, {required bool compact}) {
    final tokens = AppTokens.componentOf(context);
    final searchField = AppTextField(
      key: const ValueKey('staff-search'),
      controller: search,
      label: 'Search staff',
      placeholder: 'Name or email',
      leading: Icons.search,
      onChanged: onSearchChanged,
      helper: search.text.trim().length == 1
          ? 'Type at least 2 characters to search.'
          : null,
    );
    final roleFilter = AppSelect<String>(
      key: const ValueKey('staff-role-filter'),
      value: role?.wireValue ?? '',
      label: 'Role',
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
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          searchField,
          SizedBox(height: tokens.spacing.s12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: roleFilter),
              SizedBox(width: tokens.spacing.s8),
              Expanded(child: statusFilter),
            ],
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: searchField),
        SizedBox(width: tokens.spacing.s12),
        SizedBox(width: 190, child: roleFilter),
        SizedBox(width: tokens.spacing.s12),
        SizedBox(width: 190, child: statusFilter),
      ],
    );
  }
}

final class _StaffDirectoryList extends StatelessWidget {
  const _StaffDirectoryList({
    required this.staff,
    required this.empty,
    required this.actionsFor,
  });

  final List<TenantStaffSummary> staff;
  final Widget empty;
  final List<_StaffMenuAction> Function(TenantStaffSummary) actionsFor;

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
          )
        : Padding(
            padding: EdgeInsets.all(tokens.spacing.s8),
            child: Column(
              children: <Widget>[
                for (final member in staff)
                  _StaffCard(staff: member, actions: actionsFor(member)),
              ],
            ),
          );
    return Container(
      key: ValueKey(table ? 'staff-directory-table' : 'staff-directory-cards'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: tokens.colors.surface.raised,
        // See [_StaffCard]: the three surfaces of this directory take
        // `radius.lg` together since 2026-08-26, so the container, the cards
        // inside it and the avatars on them stay one shape.
        borderRadius: BorderRadius.circular(tokens.radius.lg),
        border: Border.all(color: tokens.colors.surface.borderSubtle),
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
  const _StaffCard({required this.staff, required this.actions});

  final TenantStaffSummary staff;
  final List<_StaffMenuAction> actions;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Container(
      key: ValueKey('staff-record-${staff.uid}'),
      margin: EdgeInsets.symmetric(vertical: tokens.spacing.s4),
      padding: EdgeInsets.all(tokens.spacing.s12),
      decoration: BoxDecoration(
        color: tokens.colors.surface.base,
        borderRadius: BorderRadius.circular(tokens.radius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _StaffAvatar(staff: staff, size: 48),
              SizedBox(width: tokens.spacing.s12),
              Expanded(child: _StaffIdentity(staff: staff, showPhone: true)),
              if (actions.isNotEmpty)
                _StaffActionMenu(staff: staff, actions: actions),
            ],
          ),
          SizedBox(height: tokens.spacing.s12),
          Divider(height: 1, color: tokens.colors.surface.borderSubtle),
          SizedBox(height: tokens.spacing.s12),
          Wrap(
            spacing: tokens.spacing.s16,
            runSpacing: tokens.spacing.s8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              _StaffFact(
                key: ValueKey('staff-role-${staff.uid}'),
                label: 'Role',
                value: tenantRoleLabel(staff.role),
              ),
              _membershipBadge(staff),
              if (staff.status == MembershipStatus.pending)
                _StaffFact(
                  key: ValueKey('staff-invitation-${staff.uid}'),
                  label: 'Invitation',
                  value: staffInvitationStatusLabel(staff.invitationStatus),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

final class _StaffTable extends StatelessWidget {
  const _StaffTable({
    required this.staff,
    required this.showInvitation,
    required this.actionsFor,
  });

  final List<TenantStaffSummary> staff;
  final bool showInvitation;
  final List<_StaffMenuAction> Function(TenantStaffSummary) actionsFor;

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
            status: _membershipBadge(member),
            invitation: Text(
              member.status == MembershipStatus.pending
                  ? staffInvitationStatusLabel(member.invitationStatus)
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
            SizedBox(width: 72, child: actions),
          ],
        ),
      ),
    );
  }
}

final class _StaffIdentity extends StatelessWidget {
  const _StaffIdentity({
    required this.staff,
    this.showPhone = false,
    this.invitationInIdentity = false,
  });

  final TenantStaffSummary staff;
  final bool showPhone;
  final bool invitationInIdentity;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          staff.displayName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: tokens.typography.bodyLarge.copyWith(
            color: tokens.colors.text.primary,
            fontWeight: FontWeight.w700,
          ),
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
            'Invitation: ${staffInvitationStatusLabel(staff.invitationStatus)}',
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

final class _StaffAvatar extends StatelessWidget {
  const _StaffAvatar({required this.staff, required this.size});

  final TenantStaffSummary staff;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Semantics(
      label: '${staff.displayName} initials',
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tokens.colors.surface.overlay,
          borderRadius: BorderRadius.circular(tokens.radius.lg),
          border: Border.all(color: tokens.colors.surface.borderSubtle),
        ),
        child: Text(
          _initials(staff.displayName),
          style: tokens.typography.labelLarge.copyWith(
            color: tokens.colors.status.ok.fg,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

final class _StaffFact extends StatelessWidget {
  const _StaffFact({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label.toUpperCase(),
          style: tokens.typography.labelEyebrow.copyWith(
            color: tokens.colors.text.tertiary,
          ),
        ),
        SizedBox(height: tokens.spacing.s4),
        Text(
          value,
          style: tokens.typography.bodyMedium.copyWith(
            color: tokens.colors.text.primary,
          ),
        ),
      ],
    );
  }
}

final class _StaffActionMenu extends StatelessWidget {
  const _StaffActionMenu({required this.staff, required this.actions});

  final TenantStaffSummary staff;
  final List<_StaffMenuAction> actions;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox(width: 48, height: 48);
    final tokens = AppTokens.componentOf(context);
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

StatusBadge _membershipBadge(TenantStaffSummary staff) => StatusBadge(
  key: ValueKey('staff-status-${staff.uid}'),
  label: membershipStatusLabel(staff.status),
  status: switch (staff.status) {
    MembershipStatus.active => AppStatus.ok,
    MembershipStatus.pending => AppStatus.attention,
    MembershipStatus.inactive => AppStatus.neutral,
  },
  semanticLabel: membershipStatusSemanticLabel(staff.status),
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
