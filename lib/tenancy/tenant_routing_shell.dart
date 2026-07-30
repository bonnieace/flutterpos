import 'dart:async';

import 'package:flutter/material.dart';

import 'platform_tenant_review.dart';
import 'tenant_bootstrap.dart';
import 'tenant_branding.dart';
import 'tenant_catalog.dart';
import 'tenant_default_tenant.dart';
import 'tenant_invitation_acceptance.dart';
import 'tenant_membership.dart';
import 'tenant_repository.dart';
import 'tenant_request.dart';
import 'tenant_session_controller.dart';
import 'tenant_staff_directory.dart';
import 'tenant_types.dart';
import 'tenant_visible_invitation_acceptance.dart';

typedef TenantRouteBuilder =
    Widget Function(
      BuildContext context,
      TenantSessionController controller,
      TenantMembership membership,
    );

/// Connects one Firebase Auth identity to one canonically revalidated tenant.
///
/// The shell owns the session controller and invalidates every pending async
/// result when the Auth UID changes, the user signs out, or bootstrap retries.
final class TenantRoutingShell extends StatefulWidget {
  const TenantRoutingShell({
    super.key,
    required this.authUidChanges,
    required this.bootstrapService,
    required this.signOut,
    required this.signedOut,
    this.isEmailVerified,
    this.invitationLink,
    this.invalidInvitationLink = false,
    this.acceptTenantInvitationCallable,
    this.invitationAcceptanceRequestIdFactory,
    this.acceptVisibleInvitationCallable,
    this.visibleInvitationRequestIdFactory,
    this.setDefaultTenantCallable,
    this.defaultTenantRequestIdFactory,
    this.requestTenantCallable,
    this.tenantRequestIdFactory,
    this.hasPlatformSuperAdminClaim,
    this.platformPendingTenantDataSource,
    this.setTenantLifecycleCallable,
    this.platformTenantReviewRequestIdFactory,
    this.tenantDataReader,
    this.tenantRouteBuilder,
  });

  final Stream<String?> authUidChanges;
  final TenantBootstrapService bootstrapService;
  final Future<void> Function() signOut;
  final Widget signedOut;
  final bool Function(String uid)? isEmailVerified;
  final TenantInvitationLink? invitationLink;
  final bool invalidInvitationLink;
  final AcceptTenantInvitationCallable? acceptTenantInvitationCallable;
  final TenantInvitationAcceptanceRequestIdFactory?
  invitationAcceptanceRequestIdFactory;
  final AcceptVisibleTenantInvitationCallable? acceptVisibleInvitationCallable;
  final TenantVisibleInvitationRequestIdFactory?
  visibleInvitationRequestIdFactory;
  final SetDefaultTenantCallable? setDefaultTenantCallable;
  final TenantDefaultRequestIdFactory? defaultTenantRequestIdFactory;
  final RequestTenantCallable? requestTenantCallable;
  final TenantRequestIdFactory? tenantRequestIdFactory;
  final Future<bool> Function(String uid)? hasPlatformSuperAdminClaim;
  final PlatformPendingTenantDataSource? platformPendingTenantDataSource;
  final SetTenantLifecycleCallable? setTenantLifecycleCallable;
  final PlatformTenantReviewRequestIdFactory?
  platformTenantReviewRequestIdFactory;
  final TenantDataReader? tenantDataReader;
  final TenantRouteBuilder? tenantRouteBuilder;

  @override
  State<TenantRoutingShell> createState() => _TenantRoutingShellState();
}

enum _RoutingPhase {
  waitingForAuth,
  signedOut,
  bootstrapping,
  selector,
  openingTenant,
  tenant,
  noAccessibleTenant,
  platform,
  failure,
  signingOut,
}

final class _TenantRoutingShellState extends State<TenantRoutingShell> {
  final TenantSessionController _sessionController = TenantSessionController();
  StreamSubscription<String?>? _authSubscription;
  _RoutingPhase _phase = _RoutingPhase.waitingForAuth;
  String? _uid;
  int _flowToken = 0;
  TenantBootstrapResult? _bootstrapResult;
  TenantMembership? _membership;
  Object? _error;
  TenantInvitationLink? _pendingInvitationLink;
  bool _hasInvalidInvitationLink = false;
  PlatformReviewIdentity? _platformIdentity;
  PlatformPendingTenantDataSource? _defaultPlatformDataSource;
  SetTenantLifecycleCallable? _defaultTenantLifecycleCallable;

  @override
  void initState() {
    super.initState();
    _pendingInvitationLink = widget.invitationLink;
    _hasInvalidInvitationLink = widget.invalidInvitationLink;
    _subscribeToAuth();
  }

  @override
  void didUpdateWidget(covariant TenantRoutingShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.invitationLink != widget.invitationLink) {
      _pendingInvitationLink = widget.invitationLink;
    }
    if (oldWidget.invalidInvitationLink != widget.invalidInvitationLink) {
      _hasInvalidInvitationLink = widget.invalidInvitationLink;
    }
    if (!identical(oldWidget.authUidChanges, widget.authUidChanges)) {
      _authSubscription?.cancel();
      _subscribeToAuth();
    }
  }

  void _subscribeToAuth() {
    _authSubscription = widget.authUidChanges.listen(
      _handleAuthUid,
      onError: (Object error, StackTrace stackTrace) {
        final token = ++_flowToken;
        _sessionController.clear();
        if (!mounted || token != _flowToken) return;
        setState(() {
          _phase = _RoutingPhase.failure;
          _error = error;
        });
      },
    );
  }

  void _handleAuthUid(String? value) {
    final nextUid = value?.trim();
    if (nextUid != null && nextUid.isEmpty) {
      ++_flowToken;
      _sessionController.clear();
      _uid = null;
      _showFailure(StateError('Authentication returned an empty user ID.'));
      return;
    }
    if (_uid == nextUid && _phase != _RoutingPhase.waitingForAuth) return;

    final token = ++_flowToken;
    _sessionController.clear();
    _uid = nextUid;
    _bootstrapResult = null;
    _membership = null;
    _platformIdentity = null;
    _error = null;
    if (nextUid == null) {
      if (!mounted) return;
      setState(() => _phase = _RoutingPhase.signedOut);
      return;
    }
    if (mounted) setState(() => _phase = _RoutingPhase.bootstrapping);
    unawaited(_bootstrap(nextUid, token));
  }

  Future<void> _bootstrap(String uid, int token) async {
    try {
      final result = await widget.bootstrapService.load(uid);
      if (!_isCurrent(uid, token)) return;
      _bootstrapResult = result;
      switch (result.kind) {
        case TenantBootstrapKind.tenant:
          final selected = result.selection.selected;
          if (selected == null) {
            throw StateError('Tenant bootstrap omitted its selected tenant.');
          }
          await _openTenant(uid, selected.tenantId, token);
          return;
        case TenantBootstrapKind.selector:
          setState(() => _phase = _RoutingPhase.selector);
          return;
        case TenantBootstrapKind.noAccessibleTenant:
          setState(() => _phase = _RoutingPhase.noAccessibleTenant);
          return;
        case TenantBootstrapKind.platform:
          final hasClaim =
              await (widget.hasPlatformSuperAdminClaim?.call(uid) ??
                  Future<bool>.value(false));
          if (!_isCurrent(uid, token)) return;
          _platformIdentity = PlatformReviewIdentity(
            uid: uid,
            profile: result.profile,
            hasSuperAdminClaim: hasClaim,
          );
          setState(() => _phase = _RoutingPhase.platform);
          return;
      }
    } catch (error) {
      if (!_isCurrent(uid, token)) return;
      _showFailure(error);
    }
  }

  Future<void> _openTenant(String uid, String tenantId, int token) async {
    if (_isCurrent(uid, token)) {
      setState(() {
        _phase = _RoutingPhase.openingTenant;
        _error = null;
      });
    }
    try {
      final membership = await widget.bootstrapService.openTenant(
        uid: uid,
        tenantId: tenantId,
      );
      if (!_isCurrent(uid, token)) return;
      _sessionController.open(uid: uid, membership: membership);
      setState(() {
        _membership = membership;
        _phase = _RoutingPhase.tenant;
      });
    } catch (error) {
      if (!_isCurrent(uid, token)) return;
      _showFailure(error);
    }
  }

  void _selectTenant(TenantMembership membership) {
    final uid = _uid;
    if (uid == null || !membership.canAccess()) return;
    final token = ++_flowToken;
    unawaited(_openTenant(uid, membership.tenantId, token));
  }

  void _refreshAfterVisibleInvitationAcceptance() => _retry();

  void _refreshAfterTenantRequest(TenantRequestResult _) => _retry();

  void _completeTokenInvitationAcceptance() {
    setState(() => _pendingInvitationLink = null);
    _retry();
  }

  void _dismissInvitationLink() {
    setState(() {
      _pendingInvitationLink = null;
      _hasInvalidInvitationLink = false;
    });
  }

  void _retry() {
    final uid = _uid;
    if (uid == null) return;
    final token = ++_flowToken;
    _sessionController.clear();
    setState(() {
      _bootstrapResult = null;
      _membership = null;
      _platformIdentity = null;
      _error = null;
      _phase = _RoutingPhase.bootstrapping;
    });
    unawaited(_bootstrap(uid, token));
  }

  Future<void> _signOut() async {
    ++_flowToken;
    _sessionController.clear();
    setState(() {
      _membership = null;
      _phase = _RoutingPhase.signingOut;
      _error = null;
    });
    try {
      await widget.signOut();
    } catch (error) {
      if (!mounted) return;
      _showFailure(error);
    }
  }

  bool _isCurrent(String uid, int token) =>
      mounted && _uid == uid && _flowToken == token;

  void _showFailure(Object error) {
    if (!mounted) return;
    setState(() {
      _phase = _RoutingPhase.failure;
      _error = error;
    });
  }

  @override
  void dispose() {
    _flowToken++;
    _authSubscription?.cancel();
    _sessionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_phase == _RoutingPhase.signedOut) return widget.signedOut;

    final invitationRoute = _buildInvitationRoute();
    if (invitationRoute != null) {
      return TenantSessionScope(
        controller: _sessionController,
        child: invitationRoute,
      );
    }

    return TenantSessionScope(
      controller: _sessionController,
      child: switch (_phase) {
        _RoutingPhase.waitingForAuth ||
        _RoutingPhase.bootstrapping ||
        _RoutingPhase.openingTenant ||
        _RoutingPhase.signingOut => const _RoutingProgress(),
        _RoutingPhase.selector ||
        _RoutingPhase.noAccessibleTenant => TenantBusinessSelector(
          identity: _visibleInvitationIdentity(),
          requestIdentity: _tenantRequestIdentity(),
          memberships: _bootstrapResult?.selection.visible ?? const [],
          onOpen: _selectTenant,
          onAccepted: _refreshAfterVisibleInvitationAcceptance,
          onRetry: _retry,
          onSignOut: _signOut,
          acceptVisibleInvitationCallable:
              widget.acceptVisibleInvitationCallable,
          visibleInvitationRequestIdFactory:
              widget.visibleInvitationRequestIdFactory,
          requestTenantCallable: widget.requestTenantCallable,
          tenantRequestIdFactory: widget.tenantRequestIdFactory,
          onTenantRequested: _refreshAfterTenantRequest,
          isCurrent: () =>
              mounted &&
              _uid != null &&
              _bootstrapResult != null &&
              (_phase == _RoutingPhase.selector ||
                  _phase == _RoutingPhase.noAccessibleTenant),
        ),
        _RoutingPhase.tenant => _buildTenantRoute(context),
        _RoutingPhase.platform => _buildPlatformRoute(),
        _RoutingPhase.failure => TenantBootstrapFailure(
          error: _error,
          onRetry: _retry,
          onSignOut: _signOut,
        ),
        _RoutingPhase.signedOut => widget.signedOut,
      },
    );
  }

  Widget _buildPlatformRoute() {
    final identity = _platformIdentity;
    if (identity == null || !identity.canReview) {
      return PlatformRouteUnavailable(onSignOut: _signOut);
    }
    return PlatformPendingTenantReviewScreen(
      identity: identity,
      dataSource:
          widget.platformPendingTenantDataSource ??
          (_defaultPlatformDataSource ??=
              FirebasePlatformPendingTenantDataSource()),
      callable:
          widget.setTenantLifecycleCallable ??
          (_defaultTenantLifecycleCallable ??=
              FirebaseSetTenantLifecycleCallable()),
      requestIdFactory: widget.platformTenantReviewRequestIdFactory,
      isCurrent: () =>
          mounted &&
          _phase == _RoutingPhase.platform &&
          _uid == identity.uid &&
          identical(_platformIdentity, identity),
      onSignOut: _signOut,
    );
  }

  Widget? _buildInvitationRoute() {
    final uid = _uid;
    final profile = _bootstrapResult?.profile;
    final canShow =
        uid != null &&
        profile != null &&
        profile.isActive &&
        profile.accountType == RootAccountType.tenantUser &&
        (_phase == _RoutingPhase.selector ||
            _phase == _RoutingPhase.noAccessibleTenant ||
            _phase == _RoutingPhase.tenant);
    if (!canShow) return null;
    if (_hasInvalidInvitationLink) {
      return _InvalidTenantInvitationScreen(
        onContinue: _dismissInvitationLink,
        onSignOut: _signOut,
      );
    }
    final link = _pendingInvitationLink;
    if (link == null) return null;
    final matches = _bootstrapResult!.selection.visible.where(
      (membership) => membership.tenantId == link.tenantId,
    );
    final membership = matches.length == 1 ? matches.single : null;
    return _TenantInvitationAcceptanceScreen(
      currentUid: uid,
      invitationLink: link,
      tenantName: membership?.tenantName,
      invitedRole: membership?.role,
      callable:
          widget.acceptTenantInvitationCallable ??
          FirebaseAcceptTenantInvitationCallable(),
      requestIdFactory: widget.invitationAcceptanceRequestIdFactory,
      isCurrent: () =>
          mounted &&
          _uid == uid &&
          identical(_pendingInvitationLink, link) &&
          _bootstrapResult?.profile.isActive == true,
      onSuccess: _completeTokenInvitationAcceptance,
      onCancel: _dismissInvitationLink,
      onSignOut: _signOut,
    );
  }

  TenantVisibleInvitationIdentity? _visibleInvitationIdentity() {
    final uid = _uid;
    final profile = _bootstrapResult?.profile;
    if (uid == null || profile == null) return null;
    return TenantVisibleInvitationIdentity(
      uid: uid,
      emailVerified: widget.isEmailVerified?.call(uid) ?? false,
      globallyActive: profile.isActive,
    );
  }

  TenantRequestIdentity? _tenantRequestIdentity() {
    final uid = _uid;
    final profile = _bootstrapResult?.profile;
    if (uid == null || profile == null) return null;
    return TenantRequestIdentity(
      uid: uid,
      emailVerified: widget.isEmailVerified?.call(uid) ?? false,
      profile: profile,
    );
  }

  Widget _buildTenantRoute(BuildContext context) {
    final membership = _membership!;
    final builder = widget.tenantRouteBuilder;
    if (builder != null) {
      return builder(context, _sessionController, membership);
    }
    return TenantSafeLandingScreen(
      membership: membership,
      reader: widget.tenantDataReader ?? FirebaseTenantDocumentReader(),
      onSignOut: _signOut,
      isDefaultTenant:
          _bootstrapResult?.profile.defaultTenantId == membership.tenantId,
      setDefaultTenantCallable: widget.setDefaultTenantCallable,
      defaultTenantRequestIdFactory: widget.defaultTenantRequestIdFactory,
      onDefaultTenantChanged: _retry,
    );
  }
}

final class _TenantInvitationAcceptanceScreen extends StatelessWidget {
  const _TenantInvitationAcceptanceScreen({
    required this.currentUid,
    required this.invitationLink,
    required this.callable,
    required this.onSuccess,
    required this.onCancel,
    required this.onSignOut,
    this.tenantName,
    this.invitedRole,
    this.requestIdFactory,
    this.isCurrent,
  });

  final String currentUid;
  final TenantInvitationLink invitationLink;
  final AcceptTenantInvitationCallable callable;
  final VoidCallback onSuccess;
  final VoidCallback onCancel;
  final Future<void> Function() onSignOut;
  final String? tenantName;
  final TenantRole? invitedRole;
  final TenantInvitationAcceptanceRequestIdFactory? requestIdFactory;
  final TenantInvitationAcceptanceCurrentCheck? isCurrent;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Business invitation'),
      actions: [
        TextButton(onPressed: onSignOut, child: const Text('Sign out')),
      ],
    ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: TenantInvitationAcceptanceForm(
                currentUid: currentUid,
                invitationLink: invitationLink,
                callable: callable,
                tenantName: tenantName,
                invitedRole: invitedRole,
                requestIdFactory: requestIdFactory,
                isCurrent: isCurrent,
                onSuccess: onSuccess,
                onCancel: onCancel,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

final class _InvalidTenantInvitationScreen extends StatelessWidget {
  const _InvalidTenantInvitationScreen({
    required this.onContinue,
    required this.onSignOut,
  });

  final VoidCallback onContinue;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Business invitation'),
      actions: [
        TextButton(onPressed: onSignOut, child: const Text('Sign out')),
      ],
    ),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.link_off_outlined, size: 48),
            const SizedBox(height: 16),
            const Text('This invitation link is invalid or incomplete.'),
            const SizedBox(height: 16),
            FilledButton(onPressed: onContinue, child: const Text('Continue')),
          ],
        ),
      ),
    ),
  );
}

final class _RoutingProgress extends StatelessWidget {
  const _RoutingProgress();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

final class TenantBusinessSelector extends StatefulWidget {
  const TenantBusinessSelector({
    super.key,
    required this.identity,
    required this.requestIdentity,
    required this.memberships,
    required this.onOpen,
    required this.onAccepted,
    required this.onRetry,
    required this.onSignOut,
    required this.onTenantRequested,
    this.acceptVisibleInvitationCallable,
    this.visibleInvitationRequestIdFactory,
    this.requestTenantCallable,
    this.tenantRequestIdFactory,
    this.isCurrent,
  });

  final TenantVisibleInvitationIdentity? identity;
  final TenantRequestIdentity? requestIdentity;
  final List<TenantMembership> memberships;
  final ValueChanged<TenantMembership> onOpen;
  final VoidCallback onAccepted;
  final VoidCallback onRetry;
  final Future<void> Function() onSignOut;
  final ValueChanged<TenantRequestResult> onTenantRequested;
  final AcceptVisibleTenantInvitationCallable? acceptVisibleInvitationCallable;
  final TenantVisibleInvitationRequestIdFactory?
  visibleInvitationRequestIdFactory;
  final RequestTenantCallable? requestTenantCallable;
  final TenantRequestIdFactory? tenantRequestIdFactory;
  final TenantVisibleInvitationCurrentCheck? isCurrent;

  @override
  State<TenantBusinessSelector> createState() => _TenantBusinessSelectorState();
}

final class _TenantBusinessSelectorState extends State<TenantBusinessSelector> {
  String? _acceptingTenantId;
  bool _requestingTenant = false;

  @override
  void didUpdateWidget(covariant TenantBusinessSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requestIdentity?.uid != widget.requestIdentity?.uid ||
        widget.requestIdentity?.canRequestTenant != true) {
      _requestingTenant = false;
    }
  }

  void _toggleAcceptance(TenantMembership membership) {
    setState(() {
      _acceptingTenantId = _acceptingTenantId == membership.tenantId
          ? null
          : membership.tenantId;
    });
  }

  void _accepted() {
    setState(() => _acceptingTenantId = null);
    widget.onAccepted();
  }

  void _tenantRequested(TenantRequestResult result) {
    setState(() => _requestingTenant = false);
    widget.onTenantRequested(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose a business'),
        actions: [
          if (widget.requestIdentity?.canRequestTenant == true)
            TextButton.icon(
              key: const ValueKey('show-tenant-request'),
              onPressed: () =>
                  setState(() => _requestingTenant = !_requestingTenant),
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('Request business'),
            ),
          TextButton(
            onPressed: widget.onSignOut,
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_requestingTenant && widget.requestIdentity != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: TenantRequestForm(
                      identity: widget.requestIdentity!,
                      callable:
                          widget.requestTenantCallable ??
                          FirebaseRequestTenantCallable(),
                      requestIdFactory: widget.tenantRequestIdFactory,
                      isCurrent: widget.isCurrent,
                      onSuccess: _tenantRequested,
                      onCancel: () => setState(() => _requestingTenant = false),
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            child: widget.memberships.isEmpty
                ? _EmptyBusinessList(onRetry: widget.onRetry)
                : ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: widget.memberships.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final membership = widget.memberships[index];
                      final status = tenantMembershipDisplayStatus(membership);
                      final identity = widget.identity;
                      final canAccept =
                          identity != null &&
                          TenantVisibleInvitationAcceptanceGateway.canAccept(
                            identity: identity,
                            membership: membership,
                          );
                      return Card(
                        child: Column(
                          children: [
                            ListTile(
                              title: Text(membership.tenantName),
                              subtitle: Text(
                                '${membership.role.wireValue} - ${status.label}',
                              ),
                              trailing: membership.canAccess()
                                  ? const Icon(Icons.chevron_right)
                                  : canAccept
                                  ? IconButton(
                                      key: ValueKey(
                                        'accept-visible-invitation-${membership.tenantId}',
                                      ),
                                      tooltip:
                                          'Accept invitation to ${membership.tenantName}',
                                      onPressed: () =>
                                          _toggleAcceptance(membership),
                                      icon: const Icon(
                                        Icons.mark_email_read_outlined,
                                      ),
                                    )
                                  : const Icon(Icons.lock_outline),
                              enabled: membership.canAccess() || canAccept,
                              onTap: membership.canAccess()
                                  ? () => widget.onOpen(membership)
                                  : canAccept
                                  ? () => _toggleAcceptance(membership)
                                  : null,
                            ),
                            if (_acceptingTenantId == membership.tenantId &&
                                identity != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  16,
                                ),
                                child: TenantVisibleInvitationAcceptanceForm(
                                  identity: identity,
                                  membership: membership,
                                  callable:
                                      widget.acceptVisibleInvitationCallable ??
                                      FirebaseAcceptVisibleTenantInvitationCallable(),
                                  requestIdFactory:
                                      widget.visibleInvitationRequestIdFactory,
                                  isCurrent: widget.isCurrent,
                                  onSuccess: _accepted,
                                  onCancel: () =>
                                      setState(() => _acceptingTenantId = null),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

final class _EmptyBusinessList extends StatelessWidget {
  const _EmptyBusinessList({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.storefront_outlined, size: 48),
            const SizedBox(height: 16),
            const Text('No business memberships are available.'),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    ),
  );
}

enum TenantMembershipDisplayStatus {
  accessible('Accessible'),
  pending('Pending'),
  inactive('Inactive'),
  rejected('Rejected'),
  suspended('Suspended'),
  archived('Archived'),
  unavailable('Unavailable');

  const TenantMembershipDisplayStatus(this.label);

  final String label;
}

TenantMembershipDisplayStatus tenantMembershipDisplayStatus(
  TenantMembership membership,
) {
  if (membership.canAccess()) return TenantMembershipDisplayStatus.accessible;
  return switch (membership.tenantStatus) {
    TenantStatus.rejected => TenantMembershipDisplayStatus.rejected,
    TenantStatus.suspended => TenantMembershipDisplayStatus.suspended,
    TenantStatus.archived => TenantMembershipDisplayStatus.archived,
    TenantStatus.pending => TenantMembershipDisplayStatus.pending,
    TenantStatus.active => switch (membership.membershipStatus) {
      MembershipStatus.pending => TenantMembershipDisplayStatus.pending,
      MembershipStatus.inactive => TenantMembershipDisplayStatus.inactive,
      MembershipStatus.active => TenantMembershipDisplayStatus.unavailable,
    },
  };
}

final class TenantSafeLandingScreen extends StatelessWidget {
  const TenantSafeLandingScreen({
    super.key,
    required this.membership,
    required this.reader,
    required this.onSignOut,
    this.isDefaultTenant = false,
    this.setDefaultTenantCallable,
    this.defaultTenantRequestIdFactory,
    this.onDefaultTenantChanged,
  });

  final TenantMembership membership;
  final TenantDataReader reader;
  final Future<void> Function() onSignOut;
  final bool isDefaultTenant;
  final SetDefaultTenantCallable? setDefaultTenantCallable;
  final TenantDefaultRequestIdFactory? defaultTenantRequestIdFactory;
  final VoidCallback? onDefaultTenantChanged;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(membership.tenantName),
      actions: [
        TextButton(onPressed: onSignOut, child: const Text('Sign out')),
      ],
    ),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: TenantBrandingPanel(
                reader: reader,
                fallbackName: membership.tenantName,
              ),
            ),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              if (isDefaultTenant)
                OutlinedButton.icon(
                  onPressed: null,
                  icon: Icon(Icons.star),
                  label: Text('Default business'),
                )
              else
                OutlinedButton.icon(
                  key: const ValueKey('make-default-tenant'),
                  onPressed: () => _showDefaultConfirmation(context),
                  icon: const Icon(Icons.star_outline),
                  label: const Text('Make default'),
                ),
              FilledButton.icon(
                onPressed: () {
                  final controller = TenantSessionScope.of(context);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => TenantSessionScope(
                        controller: controller,
                        child: TenantCatalogScreen(reader: reader),
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('View read-only catalog'),
              ),
              if (membership.role.canAccess(
                TenantStaffDirectoryScreen.allowedRoles,
              ))
                OutlinedButton.icon(
                  onPressed: () {
                    final controller = TenantSessionScope.of(context);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TenantSessionScope(
                          controller: controller,
                          child: TenantStaffDirectoryScreen(reader: reader),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.people_outline),
                  label: const Text('View staff directory'),
                ),
            ],
          ),
        ],
      ),
    ),
  );

  Future<void> _showDefaultConfirmation(BuildContext context) async {
    final controller = TenantSessionScope.read(context);
    final session = controller.session;
    if (session == null ||
        !session.canAccess() ||
        session.tenantId != membership.tenantId) {
      return;
    }
    final navigator = Navigator.of(context);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => TenantSessionScope(
        controller: controller,
        child: AlertDialog(
          content: TenantDefaultForm(
            session: session,
            membership: membership,
            callable:
                setDefaultTenantCallable ?? FirebaseSetDefaultTenantCallable(),
            requestIdFactory: defaultTenantRequestIdFactory,
            onCancel: () => Navigator.of(dialogContext).pop(),
            onSuccess: () {
              navigator.pop();
              onDefaultTenantChanged?.call();
            },
          ),
        ),
      ),
    );
  }
}

final class TenantBootstrapFailure extends StatelessWidget {
  const TenantBootstrapFailure({
    super.key,
    required this.error,
    required this.onRetry,
    required this.onSignOut,
  });

  final Object? error;
  final VoidCallback onRetry;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 16),
            const Text('We could not open your business account.'),
            const SizedBox(height: 8),
            Text(_safeBootstrapError(error), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              children: [
                FilledButton(onPressed: onRetry, child: const Text('Retry')),
                OutlinedButton(
                  onPressed: onSignOut,
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

String _safeBootstrapError(Object? error) {
  final message = error.toString();
  if (message.contains('disabled')) return 'This account is disabled.';
  if (message.contains('no root profile')) {
    return 'This account has not been provisioned.';
  }
  return 'Check your connection and try again.';
}

final class PlatformRouteUnavailable extends StatelessWidget {
  const PlatformRouteUnavailable({super.key, required this.onSignOut});

  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.admin_panel_settings_outlined, size: 52),
            const SizedBox(height: 16),
            const Text('Platform administrator access is not available.'),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onSignOut, child: const Text('Sign out')),
          ],
        ),
      ),
    ),
  );
}
