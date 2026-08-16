import 'dart:async';

import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../ui/dialogs.dart';
import '../ui/home_navigation.dart';
import '../ui/routes.dart';
import '../ui/scaffold.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'account_verification.dart';
import 'email_delivery_status.dart';
import 'platform_tenant_review.dart';
import 'platform_tenant_lifecycle.dart';
import 'platform_tenant_archival.dart';
import 'platform_global_user_status.dart';
import 'tenant_bootstrap.dart';
import 'tenant_branding.dart';
import 'tenant_catalog.dart';
import 'tenant_default_tenant.dart';
import 'tenant_invitation_acceptance.dart';
import 'tenant_membership.dart';
import 'tenant_membership_labels.dart';
import 'tenant_repository.dart';
import 'tenant_request.dart';
import 'tenant_route_guard.dart';
import 'tenant_session_controller.dart';
import 'tenant_staff_directory.dart';
import 'tenant_switch.dart';
import 'tenant_types.dart';
import 'tenant_visible_invitation_acceptance.dart';

typedef TenantRouteBuilder =
    Widget Function(
      BuildContext context,
      TenantSessionController controller,
      TenantMembership membership,
    );

/// Runs the composition root's per-session background work.
///
/// The argument is the event that asked for the run, forwarded verbatim from
/// [TenantRoutingShell.tenantRecoveryTriggers] and `null` when the shell itself
/// asked because a session opened. The shell attaches no meaning to it; it
/// exists so the composition root can decide what a particular reason justifies
/// - a sale saved at the till needs submitting, and does not need every derived
/// read the shell performs when a session opens.
typedef TenantSessionRecovery = Future<Object?> Function(Object? trigger);
typedef TenantSessionRecoveryFactory =
    TenantSessionRecovery Function(TenantSessionController controller);

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
    required this.tenantSwitchStateSources,
    required this.tenantSwitchOnlineCheck,
    this.tenantSessionRecoveryFactory,
    this.tenantRecoveryTriggers,
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
    this.sendAccountVerificationCallable,
    this.emailDeliveryStatusCallable,
    this.accountVerificationRequestIdFactory,
    this.reloadIdentity,
    this.hasPlatformSuperAdminClaim,
    this.platformPendingTenantDataSource,
    this.platformLifecycleTenantDataSource,
    this.platformRejectedTenantDataSource,
    this.platformGlobalUserDataSource,
    this.setTenantLifecycleCallable,
    this.setGlobalUserStatusCallable,
    this.platformTenantReviewRequestIdFactory,
    this.tenantDataReader,
    this.tenantRouteBuilder,
    this.checkoutRoute,
    this.checkoutConfigurationRoute,
    this.checkoutConfigurationRoles = const <TenantRole>[],
    this.catalogManagementRoute,
    this.catalogManagementRoles = const <TenantRole>[],
    this.memberName,
    this.pendingCheckoutPanel,
    this.shiftPanel,
    this.dailySummaryRoute,
    this.dailySummaryRoles = const <TenantRole>[],
    this.receiptLookupRoute,
    this.receiptLookupRoles = const <TenantRole>[],
    this.productStockRoute,
    this.productStockRoles = const <TenantRole>[],
    this.stockAdjustmentFeedRoute,
    this.stockAdjustmentFeedRoles = const <TenantRole>[],
    this.stockMovementFeedRoute,
    this.stockMovementFeedRoles = const <TenantRole>[],
    this.auditLogRoute,
    this.auditLogRoles = const <TenantRole>[],
  });

  final Stream<String?> authUidChanges;
  final TenantBootstrapService bootstrapService;
  final Future<void> Function() signOut;
  final Widget signedOut;
  final List<TenantSwitchStateSource> tenantSwitchStateSources;
  final TenantSwitchOnlineCheck tenantSwitchOnlineCheck;
  final TenantSessionRecoveryFactory? tenantSessionRecoveryFactory;
  final Stream<Object?>? tenantRecoveryTriggers;
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
  final SendAccountVerificationCallable? sendAccountVerificationCallable;

  /// Reads whether the caller's own address can receive mail. Optional: while
  /// it is absent the verification panel simply does not make that claim.
  final EmailDeliveryStatusCallable? emailDeliveryStatusCallable;

  final AccountVerificationRequestIdFactory?
  accountVerificationRequestIdFactory;

  /// Re-reads the signed-in identity so a completed verification is observed.
  ///
  /// While it is absent the verification panel stays unreachable, exactly as
  /// every other injected route does: a "check again" that could never observe
  /// the change would be worse than no action at all.
  final AccountVerificationReload? reloadIdentity;

  final Future<bool> Function(String uid)? hasPlatformSuperAdminClaim;
  final PlatformPendingTenantDataSource? platformPendingTenantDataSource;
  final PlatformLifecycleTenantDataSource? platformLifecycleTenantDataSource;
  final PlatformRejectedTenantDataSource? platformRejectedTenantDataSource;
  final PlatformGlobalUserDataSource? platformGlobalUserDataSource;
  final SetTenantLifecycleCallable? setTenantLifecycleCallable;
  final SetGlobalUserStatusCallable? setGlobalUserStatusCallable;
  final PlatformTenantReviewRequestIdFactory?
  platformTenantReviewRequestIdFactory;
  final TenantDataReader? tenantDataReader;
  final TenantRouteBuilder? tenantRouteBuilder;

  /// Optional read-only local-work evidence rendered on the safe landing
  /// route. It is supplied by the composition root so tenancy code stays
  /// independent of the checkout domain.
  /// What to call the signed-in person in the home's top bar.
  ///
  /// **A callback rather than a `String`, and already-loaded state rather than
  /// a read.** `design.md` v0.7 gives the bar "the signed-in member and their
  /// role"; the role is on the membership and the name is not on any tenant
  /// record this route holds — the staff directory is the only surface that
  /// reads names. What *is* to hand is the identity the person signed in with,
  /// whose display name Firebase has already loaded, so this asks the
  /// composition root for it instead of adding a read to the home.
  ///
  /// Null wherever it is unset, which is common: an identity created by an
  /// emailed invitation has no display name until somebody types one. The bar
  /// falls back to the role alone rather than to a placeholder.
  final String? Function()? memberName;

  final Widget? pendingCheckoutPanel;

  /// Optional point-of-sale route, injected for the same reason. It takes no
  /// reader: a sale is built from the device's own offline catalog, not from a
  /// live read, which is the whole point of the offline checkout design.
  ///
  /// Every active member may sell - the same set Firestore Rules allow to
  /// create a sale - so it carries no role list. It receives the live session
  /// controller because saving a draft must be bound to the exact session it
  /// was started in.
  final Widget Function(TenantSessionController sessions)? checkoutRoute;

  /// Optional guarded checkout settings route, injected for the same reason.
  ///
  /// It is the only surface that publishes what a till prices in, and until it
  /// has been used once the till above it cannot sell at all.
  final Widget Function(TenantDataReader reader)? checkoutConfigurationRoute;

  /// The roles that route is offered to, decided by the checkout domain. It is
  /// deliberately narrower than the roles that may sell.
  final List<TenantRole> checkoutConfigurationRoles;

  /// Optional guarded catalog-management route, injected for the same reason.
  ///
  /// It is the only surface that puts a product in the catalog, and every other
  /// operational route in this app already assumed one was there.
  final Widget Function(TenantDataReader reader)? catalogManagementRoute;

  /// The roles that route is offered to, decided by the inventory domain.
  /// Retiring is narrower still and is decided inside the route itself.
  final List<TenantRole> catalogManagementRoles;

  /// Optional shift lifecycle surface rendered on the safe landing route. It is
  /// injected for the same reason: tenancy code owns routing, not operations.
  final Widget? shiftPanel;

  /// Optional read-only reporting route, injected for the same reason.
  final Widget Function(TenantDataReader reader)? dailySummaryRoute;

  /// The roles the reporting route is offered to.
  final List<TenantRole> dailySummaryRoles;

  /// Optional guarded receipt-lookup route, injected for the same reason.
  final Widget Function(TenantDataReader reader)? receiptLookupRoute;

  /// The roles that route is offered to, decided by the sales domain.
  final List<TenantRole> receiptLookupRoles;

  /// Optional guarded per-product stock route, reached from the read-only
  /// catalog and injected for the same reason.
  final Widget Function(TenantDataReader reader, TenantProduct product)?
  productStockRoute;

  /// The roles that route is offered to, decided by the inventory domain.
  final List<TenantRole> productStockRoles;

  /// Optional guarded business-wide stock adjustment feed, reached from the
  /// read-only catalog and injected for the same reason.
  final Widget Function(TenantDataReader reader)? stockAdjustmentFeedRoute;

  /// The roles that route is offered to, decided by the inventory domain.
  final List<TenantRole> stockAdjustmentFeedRoles;

  /// Optional guarded business-wide stock movement feed, reached from the
  /// read-only catalog and injected for the same reason.
  final Widget Function(TenantDataReader reader)? stockMovementFeedRoute;

  /// The roles that route is offered to, decided by the inventory domain.
  final List<TenantRole> stockMovementFeedRoles;

  /// Optional guarded business-wide activity log, injected for the same reason.
  final Widget Function(TenantDataReader reader)? auditLogRoute;

  /// The roles that route is offered to, decided by the audit domain.
  final List<TenantRole> auditLogRoles;

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
  StreamSubscription<Object?>? _tenantRecoverySubscription;
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
  PlatformLifecycleTenantDataSource? _defaultPlatformLifecycleDataSource;
  PlatformRejectedTenantDataSource? _defaultPlatformRejectedDataSource;
  PlatformGlobalUserDataSource? _defaultPlatformGlobalUserDataSource;
  SetTenantLifecycleCallable? _defaultTenantLifecycleCallable;
  SetGlobalUserStatusCallable? _defaultGlobalUserStatusCallable;
  TenantSwitchCoordinator? _tenantSwitchCoordinator;
  TenantSessionRecovery? _tenantSessionRecovery;

  @override
  void initState() {
    super.initState();
    _pendingInvitationLink = widget.invitationLink;
    _hasInvalidInvitationLink = widget.invalidInvitationLink;
    _subscribeToAuth();
    _subscribeToTenantRecoveryTriggers();
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
    if (!identical(
      oldWidget.tenantRecoveryTriggers,
      widget.tenantRecoveryTriggers,
    )) {
      _tenantRecoverySubscription?.cancel();
      _subscribeToTenantRecoveryTriggers();
    }
    if (!identical(
      oldWidget.tenantSessionRecoveryFactory,
      widget.tenantSessionRecoveryFactory,
    )) {
      _tenantSessionRecovery = null;
    }
    if (!identical(oldWidget.bootstrapService, widget.bootstrapService) ||
        !identical(
          oldWidget.tenantSwitchStateSources,
          widget.tenantSwitchStateSources,
        ) ||
        !identical(
          oldWidget.tenantSwitchOnlineCheck,
          widget.tenantSwitchOnlineCheck,
        )) {
      _tenantSwitchCoordinator = null;
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

  void _subscribeToTenantRecoveryTriggers() {
    _tenantRecoverySubscription = widget.tenantRecoveryTriggers?.listen(
      _triggerTenantRecovery,
      onError: (Object _, StackTrace _) {},
    );
  }

  void _triggerTenantRecovery([Object? trigger]) {
    if (_sessionController.session == null) return;
    final factory = widget.tenantSessionRecoveryFactory;
    if (factory == null) return;
    final recovery = _tenantSessionRecovery ??= factory(_sessionController);
    unawaited(recovery(trigger));
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
      _triggerTenantRecovery();
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

  Future<TenantSwitchResult> _switchTenant(TenantMembership membership) async {
    final coordinator = _tenantSwitchCoordinator ??= TenantSwitchCoordinator(
      sessionController: _sessionController,
      bootstrapService: widget.bootstrapService,
      stateSources: widget.tenantSwitchStateSources,
      isOnline: widget.tenantSwitchOnlineCheck,
      onSessionChanged: (next) {
        if (!mounted || _phase != _RoutingPhase.tenant) return;
        setState(() => _membership = next);
        _triggerTenantRecovery();
      },
    );
    return coordinator.switchTenant(membership.tenantId);
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
    _tenantRecoverySubscription?.cancel();
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
        _RoutingPhase.waitingForAuth => const _RoutingProgress(
          message: 'Checking whether you are signed in.',
        ),
        _RoutingPhase.bootstrapping => const _RoutingProgress(
          message: 'Opening your account.',
        ),
        _RoutingPhase.openingTenant => const _RoutingProgress(
          message: 'Opening the business.',
        ),
        _RoutingPhase.signingOut => const _RoutingProgress(
          message: 'Signing you out.',
        ),
        _RoutingPhase.selector ||
        _RoutingPhase.noAccessibleTenant => TenantBusinessSelector(
          identity: _visibleInvitationIdentity(),
          requestIdentity: _tenantRequestIdentity(),
          verificationIdentity: _accountVerificationIdentity(),
          sendAccountVerificationCallable:
              widget.sendAccountVerificationCallable,
          emailDeliveryStatusCallable: widget.emailDeliveryStatusCallable,
          accountVerificationRequestIdFactory:
              widget.accountVerificationRequestIdFactory,
          onReloadIdentity: widget.reloadIdentity == null
              ? null
              : _reloadIdentity,
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
    return PlatformTenantManagementScreen(
      identity: identity,
      pendingDataSource:
          widget.platformPendingTenantDataSource ??
          (_defaultPlatformDataSource ??=
              FirebasePlatformPendingTenantDataSource()),
      lifecycleDataSource:
          widget.platformLifecycleTenantDataSource ??
          (_defaultPlatformLifecycleDataSource ??=
              FirebasePlatformLifecycleTenantDataSource()),
      rejectedDataSource:
          widget.platformRejectedTenantDataSource ??
          (_defaultPlatformRejectedDataSource ??=
              FirebasePlatformRejectedTenantDataSource()),
      globalUserDataSource:
          widget.platformGlobalUserDataSource ??
          (_defaultPlatformGlobalUserDataSource ??=
              FirebasePlatformGlobalUserDataSource()),
      callable:
          widget.setTenantLifecycleCallable ??
          (_defaultTenantLifecycleCallable ??=
              FirebaseSetTenantLifecycleCallable()),
      globalUserCallable:
          widget.setGlobalUserStatusCallable ??
          (_defaultGlobalUserStatusCallable ??=
              FirebaseSetGlobalUserStatusCallable()),
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

  /// The identity offered the verification panel, or null while the route is
  /// not supplied. `emailVerified` gates requesting a business and accepting an
  /// invitation, so an unverified identity has no way forward without it.
  AccountVerificationIdentity? _accountVerificationIdentity() {
    final uid = _uid;
    final profile = _bootstrapResult?.profile;
    if (uid == null || profile == null || widget.reloadIdentity == null) {
      return null;
    }
    return AccountVerificationIdentity(
      uid: uid,
      emailVerified: widget.isEmailVerified?.call(uid) ?? false,
      profile: profile,
    );
  }

  /// Re-reads the identity, then restarts bootstrap so the refreshed
  /// `emailVerified` claim is consulted again.
  Future<void> _reloadIdentity() async {
    final uid = _uid;
    await widget.reloadIdentity!.call();
    if (!mounted || _uid != uid) return;
    _retry();
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
      switchCandidates: _bootstrapResult?.selection.visible ?? const [],
      onSwitchTenant: _switchTenant,
      memberName: widget.memberName?.call(),
      checkoutRoute: widget.checkoutRoute,
      checkoutConfigurationRoute: widget.checkoutConfigurationRoute,
      checkoutConfigurationRoles: widget.checkoutConfigurationRoles,
      catalogManagementRoute: widget.catalogManagementRoute,
      catalogManagementRoles: widget.catalogManagementRoles,
      pendingCheckoutPanel: widget.pendingCheckoutPanel,
      shiftPanel: widget.shiftPanel,
      dailySummaryRoute: widget.dailySummaryRoute,
      dailySummaryRoles: widget.dailySummaryRoles,
      receiptLookupRoute: widget.receiptLookupRoute,
      receiptLookupRoles: widget.receiptLookupRoles,
      productStockRoute: widget.productStockRoute,
      productStockRoles: widget.productStockRoles,
      stockAdjustmentFeedRoute: widget.stockAdjustmentFeedRoute,
      stockAdjustmentFeedRoles: widget.stockAdjustmentFeedRoles,
      stockMovementFeedRoute: widget.stockMovementFeedRoute,
      stockMovementFeedRoles: widget.stockMovementFeedRoles,
      auditLogRoute: widget.auditLogRoute,
      auditLogRoles: widget.auditLogRoles,
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
  Widget build(BuildContext context) => AppScaffold(
    title: 'Business invitation',
    contentWidth: AppContentWidth.reading,
    actions: <Widget>[
      AppButton(
        label: 'Sign out',
        tier: AppButtonTier.tertiary,
        onPressed: onSignOut,
      ),
    ],
    body: Center(
      child: SingleChildScrollView(
        // 24 until step 6; see the page inset's own note in `AppScaffold`.
        padding: EdgeInsets.all(
          AppScaffold.horizontalInset(AppTokens.componentOf(context).spacing),
        ),
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
  Widget build(BuildContext context) => AppScaffold(
    title: 'Business invitation',
    contentWidth: AppContentWidth.reading,
    actions: <Widget>[
      AppButton(
        label: 'Sign out',
        tier: AppButtonTier.tertiary,
        onPressed: onSignOut,
      ),
    ],
    body: Center(
      child: Padding(
        // 24 until step 6; see the page inset's own note in `AppScaffold`.
        padding: EdgeInsets.all(
          AppScaffold.horizontalInset(AppTokens.componentOf(context).spacing),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.link_off_outlined, size: 48),
            const SizedBox(height: 16),
            // §8 rule 6 - say what is still true - and it is the shape the
            // invitation refusal already took: name what will actually work
            // rather than leave a person on a dead end with one button.
            const Text(
              'This invitation link is invalid or incomplete. Ask whoever '
              'invited you to send it again.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            AppButton(
              // §8 rule 3: a control names its effect. This one discards the
              // link and goes on to whatever this identity can already reach,
              // which `Continue` named not at all.
              label: 'Continue without this invitation',
              tier: AppButtonTier.primary,
              onPressed: onContinue,
            ),
          ],
        ),
      ),
    ),
  );
}

/// The shell's own waiting screen, one sentence per phase.
///
/// **The sentence varies because the four phases behind it are not the same
/// wait.** `waitingForAuth`, `bootstrapping`, `openingTenant` and `signingOut`
/// all drew the identical bare spinner, and §5.1's row for that widget is the
/// whole reason `LoadingState` exists: a person watching this screen wants to
/// know whether their business is opening or their session is ending, and the
/// spinner answered neither.
///
/// **It stays a `Scaffold` rather than becoming an `AppScaffold`**, and that is
/// a decision rather than an unfinished migration. `AppScaffold` requires a
/// title and draws a `PageHeader` for it; this is not a page and has no name.
/// Giving it one would put a heading above a centred state and break §7's
/// "title appears once" in the only way that section did not anticipate —
/// by inventing the title.
final class _RoutingProgress extends StatelessWidget {
  const _RoutingProgress({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: LoadingState(message: message)),
  );
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
    this.verificationIdentity,
    this.sendAccountVerificationCallable,
    this.emailDeliveryStatusCallable,
    this.accountVerificationRequestIdFactory,
    this.onReloadIdentity,
    this.acceptVisibleInvitationCallable,
    this.visibleInvitationRequestIdFactory,
    this.requestTenantCallable,
    this.tenantRequestIdFactory,
    this.isCurrent,
  });

  final TenantVisibleInvitationIdentity? identity;
  final TenantRequestIdentity? requestIdentity;

  /// The identity offered the verification panel. This screen is exactly where
  /// an unverified identity is stuck: it can neither request a business nor
  /// accept an invitation until the address is verified.
  final AccountVerificationIdentity? verificationIdentity;

  final SendAccountVerificationCallable? sendAccountVerificationCallable;
  final EmailDeliveryStatusCallable? emailDeliveryStatusCallable;
  final AccountVerificationRequestIdFactory?
  accountVerificationRequestIdFactory;

  /// Supplied together with [verificationIdentity]; the panel stays unreachable
  /// without it.
  final AccountVerificationReload? onReloadIdentity;
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
    // The two transient panels above the list - verify your address, request a
    // business - used to be laid out at their natural height with the list
    // taking whatever was left. **Step 5a's page header costs this route 72
    // logical pixels of body**, and at 800 x 600 with the request form open
    // that was 16 pixels more than there was, so the form overflowed its
    // column.
    //
    // They are collected and given a scrollable `Flexible` instead, which is
    // the smallest arrangement that cannot overflow at any height. It changes
    // no behaviour and it is an improvement rather than a concession: at the
    // height where this first broke, the old layout had already crushed the
    // membership list to 56 pixels to make room for the form.
    final panels = <Widget>[
      if (widget.verificationIdentity?.canSendVerification == true &&
          widget.onReloadIdentity != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: AccountVerificationPanel(
              identity: widget.verificationIdentity!,
              callable:
                  widget.sendAccountVerificationCallable ??
                  FirebaseSendAccountVerificationCallable(),
              onReload: widget.onReloadIdentity!,
              deliveryStatusCallable: widget.emailDeliveryStatusCallable,
              requestIdFactory: widget.accountVerificationRequestIdFactory,
              isCurrent: widget.isCurrent,
            ),
          ),
        ),
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
    ];
    return AppScaffold(
      title: 'Choose a business',
      contentWidth: AppContentWidth.records,
      actions: <Widget>[
        if (widget.requestIdentity?.canRequestTenant == true)
          AppButton(
            key: const ValueKey('show-tenant-request'),
            label: 'Request business',
            icon: Icons.add_business_outlined,
            tier: AppButtonTier.tertiary,
            onPressed: () =>
                setState(() => _requestingTenant = !_requestingTenant),
          ),
        AppButton(
          label: 'Sign out',
          tier: AppButtonTier.tertiary,
          onPressed: widget.onSignOut,
        ),
      ],
      body: Column(
        children: [
          if (panels.isNotEmpty)
            Flexible(
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: panels),
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
                                '${tenantRoleLabel(membership.role)} - ${status.label}',
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
            AppButton(
              label: 'Retry',
              tier: AppButtonTier.primary,
              onPressed: onRetry,
            ),
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

/// The landing route's scrollable region, which says when it has more below it.
///
/// The centring is deliberate and is kept: a mostly-empty landing screen looks
/// right with its one panel in the middle, and when the content is short it is
/// exactly what a reader sees.
///
/// What it never did was say anything when the content was **taller** than the
/// space. `Center` passes loose constraints down, so a scroll view whose content
/// overflows sizes to the full height and starts at offset zero - centred and
/// top-aligned are the same layout in that case, and the only visible result was
/// a line of text sliced through mid-glyph at the bottom edge with no indication
/// that four more lines followed it. A cashier looking for the sale they had just
/// rung up saw a heading and no counts.
///
/// So the fix is not an alignment. It is saying that there is more, which this
/// does with a fade into the surface the screen is already drawn on, shown only
/// while something is actually below the fold.
final class _LandingScrollArea extends StatefulWidget {
  const _LandingScrollArea({required this.child});

  final Widget child;

  @override
  State<_LandingScrollArea> createState() => _LandingScrollAreaState();
}

final class _LandingScrollAreaState extends State<_LandingScrollArea> {
  /// Ignore a sub-pixel remainder: a viewport that is a rounding error short of
  /// its content has nothing to tell anybody about.
  static const double _foldTolerance = 1;
  static const double _fadeHeight = 32;

  final ScrollController _controller = ScrollController();
  bool _moreBelow = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_readPosition);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Whether anything is below the viewport, asked of the position itself.
  ///
  /// Read after the frame rather than from a notification. A
  /// `ScrollMetricsNotification` is dispatched when the metrics *change*, and the
  /// first layout of this route does not reliably produce one - which is exactly
  /// the case that matters, because a screen is over the fold from the moment it
  /// opens or not at all. Asking the position after layout answers for every
  /// frame, including the first.
  void _readPosition() {
    if (!_controller.hasClients) return;
    _apply(_controller.position.extentAfter > _foldTolerance);
  }

  void _apply(bool moreBelow) {
    if (!mounted || moreBelow == _moreBelow) return;
    setState(() => _moreBelow = moreBelow);
  }

  /// The content of this route changes height on its own - the checkout counts
  /// are re-read on every sync signal - and that relayout rebuilds the panel
  /// rather than this widget, so its own build never runs. A metrics change is
  /// the only signal for it, and it arrives outside layout.
  bool _handle(Notification notification) {
    if (notification is ScrollMetricsNotification) {
      _apply(notification.metrics.extentAfter > _foldTolerance);
    }
    // Never absorbed: an ancestor may be listening for its own reasons.
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).scaffoldBackgroundColor;
    // Whether the content overflows is decided by the layout this build is part
    // of, which has not happened yet, so the answer is read once it has.
    WidgetsBinding.instance.addPostFrameCallback((_) => _readPosition());
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: _handle,
      child: Stack(
        children: [
          // The scroll view is the only unpositioned child, so it sizes the
          // stack and the fade is measured against it.
          Center(
            child: SingleChildScrollView(
              controller: _controller,
              child: widget.child,
            ),
          ),
          if (_moreBelow)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              // The fade is decoration. It must never eat the drag that scrolls
              // the content it is drawn over.
              child: IgnorePointer(
                child: Container(
                  key: const ValueKey('landing-more-below'),
                  height: _fadeHeight,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[surface.withValues(alpha: 0), surface],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
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
    this.switchCandidates = const [],
    this.onSwitchTenant,
    this.checkoutRoute,
    this.checkoutConfigurationRoute,
    this.checkoutConfigurationRoles = const <TenantRole>[],
    this.catalogManagementRoute,
    this.catalogManagementRoles = const <TenantRole>[],
    this.memberName,
    this.pendingCheckoutPanel,
    this.shiftPanel,
    this.dailySummaryRoute,
    this.dailySummaryRoles = const <TenantRole>[],
    this.receiptLookupRoute,
    this.receiptLookupRoles = const <TenantRole>[],
    this.productStockRoute,
    this.productStockRoles = const <TenantRole>[],
    this.stockAdjustmentFeedRoute,
    this.stockAdjustmentFeedRoles = const <TenantRole>[],
    this.stockMovementFeedRoute,
    this.stockMovementFeedRoles = const <TenantRole>[],
    this.auditLogRoute,
    this.auditLogRoles = const <TenantRole>[],
  });

  final TenantMembership membership;
  final TenantDataReader reader;
  final Future<void> Function() onSignOut;
  final bool isDefaultTenant;
  final SetDefaultTenantCallable? setDefaultTenantCallable;
  final TenantDefaultRequestIdFactory? defaultTenantRequestIdFactory;
  final VoidCallback? onDefaultTenantChanged;
  final List<TenantMembership> switchCandidates;
  final Future<TenantSwitchResult> Function(TenantMembership membership)?
  onSwitchTenant;

  /// What to call the signed-in person. See `TenantRoutingShell.memberName`.
  final String? memberName;

  final Widget? pendingCheckoutPanel;
  final Widget Function(TenantSessionController sessions)? checkoutRoute;

  /// Optional guarded checkout settings route, supplied by the composition root.
  ///
  /// It is the one surface that publishes what a till prices in. The till beside
  /// it refuses to sell until this has been used once, which is why the two are
  /// offered from the same screen.
  final Widget Function(TenantDataReader reader)? checkoutConfigurationRoute;

  /// The roles that route is offered to, decided by the checkout domain. It is
  /// deliberately narrower than the roles that may sell.
  final List<TenantRole> checkoutConfigurationRoles;

  /// Optional guarded catalog-management route, supplied by the composition
  /// root. It is the one surface that can put a product in the catalog, which
  /// is what every other operational route on this screen already assumed.
  final Widget Function(TenantDataReader reader)? catalogManagementRoute;

  /// The roles that route is offered to, decided by the inventory domain.
  final List<TenantRole> catalogManagementRoles;

  final Widget? shiftPanel;

  /// Builds the read-only reporting route. Supplied by the composition root so
  /// tenancy code keeps owning routing rather than the reporting domain; the
  /// route stays unreachable while it is absent.
  final Widget Function(TenantDataReader reader)? dailySummaryRoute;

  /// The roles that route is offered to, decided by the reporting domain.
  final List<TenantRole> dailySummaryRoles;

  /// Optional guarded receipt-lookup route, injected for the same reason.
  final Widget Function(TenantDataReader reader)? receiptLookupRoute;

  /// The roles that route is offered to, decided by the sales domain.
  final List<TenantRole> receiptLookupRoles;

  /// Optional guarded per-product stock route, opened from the read-only
  /// catalog rather than from this screen.
  final Widget Function(TenantDataReader reader, TenantProduct product)?
  productStockRoute;

  /// The roles that route is offered to, decided by the inventory domain.
  final List<TenantRole> productStockRoles;

  /// Optional guarded business-wide stock adjustment feed, opened from the
  /// read-only catalog rather than from this screen.
  final Widget Function(TenantDataReader reader)? stockAdjustmentFeedRoute;

  /// The roles that route is offered to, decided by the inventory domain.
  final List<TenantRole> stockAdjustmentFeedRoles;

  /// Optional guarded business-wide stock movement feed, opened from the
  /// read-only catalog rather than from this screen.
  final Widget Function(TenantDataReader reader)? stockMovementFeedRoute;

  /// The roles that route is offered to, decided by the inventory domain.
  final List<TenantRole> stockMovementFeedRoles;

  /// Optional guarded business-wide activity log, opened from this screen as a
  /// sibling of the daily summary. It stays unreachable while it is absent.
  final Widget Function(TenantDataReader reader)? auditLogRoute;

  /// The roles that route is offered to, decided by the audit domain. It is
  /// deliberately narrower than every other route offered here.
  final List<TenantRole> auditLogRoles;

  @override
  Widget build(BuildContext context) => TenantRouteGuard<TenantBranding?>(
    // **The read `TenantBrandingPanel` used to make, one level up.** §11 step 5b
    // titles this page `branding.companyName`, and a title cannot be resolved
    // below the header that draws it. Nothing new is fetched and no call site
    // moved: the panel no longer loads the document it used to load, so this
    // route makes exactly the one read it always made.
    load: (session) =>
        TenantBrandingRepository(session: session, reader: reader).load(),
    // **The page is never gated on the document, and that is the point of
    // giving every phase the same builder.** A business that has published no
    // branding, a read that failed, a read still in flight and a denied session
    // all draw the home with `membership.tenantName` - which is the fallback
    // §4.4 names and the string this toolbar carried before this step. The
    // worst case is the previous behaviour rather than a spinner where a shop
    // expects its own front page.
    loading: _page(context, null),
    denied: _page(context, null),
    failure: (context, _) => _page(context, null),
    builder: (context, session, branding) => _page(context, branding),
  );

  /// The home, titled by [branding] where the business has published one.
  Widget _page(BuildContext context, TenantBranding? branding) {
    final tokens = AppTokens.componentOf(context);
    final inset = AppScaffold.horizontalInset(tokens.spacing);
    // §4.4's two renderings have two hosts as of step 5b's second half: the
    // cards are content and stay in the body, the menu is chrome and belongs to
    // the frame. The list is built once and handed to both, so a destination
    // cannot appear in one band and not the other.
    final destinations = _destinations(context);
    return AppScaffold(
      navigation: destinations,
      title: branding?.companyName ?? membership.tenantName,
      // §4.2's record row rather than its reading row: this page is a grid of
      // destinations at two of its three bands, and 720 would put a
      // three-column grid on a tablet into a column narrower than the screen.
      contentWidth: AppContentWidth.records,
      // §4.4's top bar, in the two slots that need no data the home is not
      // given. The queue button is `CheckoutPendingEvidencePanel` itself,
      // moved rather than rebuilt: it already held the counts, so restyling it
      // into `SyncIndicator` put the badge in reach of the bar without the
      // number being hoisted anywhere. See `PLAN.md` for the two slots of the
      // mockup that are still short - the member's name and the switcher.
      actions: [
        if (pendingCheckoutPanel != null) pendingCheckoutPanel!,
        AppButton(
          label: 'Sign out',
          tier: AppButtonTier.tertiary,
          onPressed: onSignOut,
        ),
      ],
      // §4.4: "the signed-in member and their role". The role is what this page
      // holds - a member's *name* is read by the staff directory and by nothing
      // else - so the subtitle states what is true rather than what the mockup
      // draws, and `PLAN.md` carries the difference.
      // §4.4 v0.7: "the signed-in member and their role". Both where the
      // identity has a display name, and the role alone where it does not -
      // which is common, since an identity created by an emailed invitation
      // carries none until somebody types one. A placeholder would be worse
      // than the shorter sentence.
      subtitle: memberName == null
          ? 'Signed in as ${tenantRoleLabel(membership.role)}'
          : '$memberName - ${tenantRoleLabel(membership.role)}',
      // Everything in the *body* scrolls together, the cards included.
      //
      // The destinations used to be pinned outside the scrollable, and on a
      // phone that was measured rather than argued about: an owner sees eight of
      // them, they did not pair up at 411 logical pixels wide, and the row took
      // **288 of the 631** pixels the body has. The scrollable was left 339,
      // which put "Open shift" - the thing somebody about to trade came here for
      // - below the fold, behind seven navigation buttons. A cashier lost 108 to
      // the same row.
      //
      // **§11 step 5b changed what is in that space and not this decision.** A
      // two-column grid pairs where a `Wrap` of pills would not, so the same
      // eleven destinations cost fewer rows than they did; they are still below
      // the shift, because what a person came here to do outranks where they
      // might go next.
      //
      // **The menu is the exception and it is a different surface rather than
      // an exception to this argument.** At `expanded` the destinations are not
      // in the body at all - the frame draws them in a column of its own, with
      // its own scroll - and the reason a phone must not pin them is a phone's
      // 631 pixels of height, which a 1024-wide window is not short of.
      body: Padding(
        padding: EdgeInsets.fromLTRB(inset, 0, inset, tokens.spacing.s24),
        child: _LandingScrollArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TenantBrandingPanel(branding: branding),
              if (shiftPanel != null) ...[
                const SizedBox(height: 24),
                shiftPanel!,
              ],

              // **The cards, and only below 1024**, where the frame is drawing
              // no menu. §4.4: at `expanded` the home "keeps its content and
              // loses its cards", so the gap above them goes with them - a page
              // whose last section is absent should not end on the space that
              // used to separate it.
              if (!HomeNavigation.showsMenu(
                MediaQuery.sizeOf(context).width,
              )) ...[
                const SizedBox(height: 24),
                HomeNavigation.cards(destinations: destinations),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Everywhere this session may go from the home, in the order §4.4 asks for:
  /// the primary first, then by frequency, **never alphabetically**, with the
  /// two account controls last.
  ///
  /// **The order is the only thing step 5b's second half changed here.** Every
  /// condition, every role check and every closure below is byte-for-byte what
  /// it was when these were eleven pills in a `Wrap` - and source order is
  /// exactly what a `Wrap` renders, which is why the ordering §4.4 asks for had
  /// to be applied to this list rather than to a layout. The order below is the
  /// one `tool/screenshots/home_navigation_test.dart` has been photographing
  /// since the first half, so the pictures and the route now agree.
  List<HomeDestination> _destinations(BuildContext context) =>
      <HomeDestination>[
        // The till. It is the only write-capable operational route on this
        // screen, and it opens under the same session scope as every other one,
        // so a business switch invalidates a sale in progress exactly as it
        // invalidates a read.
        if (checkoutRoute != null)
          // §2.1 permits exactly one primary action per screen region, and on
          // the landing route this is it: everything else here opens something
          // to read, and this one sells.
          HomeDestination(
            destinationKey: const ValueKey('start-checkout'),
            label: 'New sale',
            icon: Icons.point_of_sale,
            isPrimary: true,
            onPressed: () {
              final controller = TenantSessionScope.of(context);
              Navigator.of(context).push(
                AppPageRoute<void>(
                  builder: (_) => TenantSessionScope(
                    controller: controller,
                    child: checkoutRoute!(controller),
                  ),
                ),
              );
            },
          ),
        HomeDestination(
          label: 'View read-only catalog',
          icon: Icons.inventory_2_outlined,
          onPressed: () {
            final controller = TenantSessionScope.of(context);
            Navigator.of(context).push(
              AppPageRoute<void>(
                builder: (_) => TenantSessionScope(
                  controller: controller,
                  child: TenantCatalogScreen(
                    reader: reader,
                    productStockRoute: productStockRoute == null
                        ? null
                        : (product) => productStockRoute!(reader, product),
                    productStockRoles: productStockRoles,
                    adjustmentFeedRoute: stockAdjustmentFeedRoute == null
                        ? null
                        : () => stockAdjustmentFeedRoute!(reader),
                    adjustmentFeedRoles: stockAdjustmentFeedRoles,
                    movementFeedRoute: stockMovementFeedRoute == null
                        ? null
                        : () => stockMovementFeedRoute!(reader),
                    movementFeedRoles: stockMovementFeedRoles,
                  ),
                ),
              ),
            );
          },
        ),
        // Beside the read-only catalog, because it is the same catalog seen by
        // the one person who may change it. Nothing else in the app can put a
        // product in, so a business with an empty catalog reaches its till
        // through here first.
        if (catalogManagementRoute != null &&
            membership.role.canAccess(catalogManagementRoles))
          HomeDestination(
            destinationKey: const ValueKey('manage-catalog'),
            label: 'Manage catalog',
            icon: Icons.edit_note_outlined,
            onPressed: () {
              final controller = TenantSessionScope.of(context);
              Navigator.of(context).push(
                AppPageRoute<void>(
                  builder: (_) => TenantSessionScope(
                    controller: controller,
                    child: catalogManagementRoute!(reader),
                  ),
                ),
              );
            },
          ),
        if (dailySummaryRoute != null &&
            membership.role.canAccess(dailySummaryRoles))
          HomeDestination(
            destinationKey: const ValueKey('view-daily-summary'),
            label: 'View daily summary',
            icon: Icons.insights_outlined,
            onPressed: () {
              final controller = TenantSessionScope.of(context);
              Navigator.of(context).push(
                AppPageRoute<void>(
                  builder: (_) => TenantSessionScope(
                    controller: controller,
                    child: dailySummaryRoute!(reader),
                  ),
                ),
              );
            },
          ),
        if (receiptLookupRoute != null &&
            membership.role.canAccess(receiptLookupRoles))
          HomeDestination(
            destinationKey: const ValueKey('find-receipt'),
            label: 'Find a receipt',
            icon: Icons.receipt_long_outlined,
            onPressed: () {
              final controller = TenantSessionScope.of(context);
              Navigator.of(context).push(
                AppPageRoute<void>(
                  builder: (_) => TenantSessionScope(
                    controller: controller,
                    child: receiptLookupRoute!(reader),
                  ),
                ),
              );
            },
          ),
        // Beside the catalog rather than beside the till: this decides what
        // every price in that catalog means, and the person who opens it is not
        // the person standing at the till.
        if (checkoutConfigurationRoute != null &&
            membership.role.canAccess(checkoutConfigurationRoles))
          HomeDestination(
            destinationKey: const ValueKey('checkout-configuration'),
            label: 'Checkout settings',
            icon: Icons.tune_outlined,
            onPressed: () {
              final controller = TenantSessionScope.of(context);
              Navigator.of(context).push(
                AppPageRoute<void>(
                  builder: (_) => TenantSessionScope(
                    controller: controller,
                    child: checkoutConfigurationRoute!(reader),
                  ),
                ),
              );
            },
          ),
        if (auditLogRoute != null && membership.role.canAccess(auditLogRoles))
          HomeDestination(
            destinationKey: const ValueKey('view-audit-log'),
            label: 'View activity log',
            icon: Icons.fact_check_outlined,
            onPressed: () {
              final controller = TenantSessionScope.of(context);
              Navigator.of(context).push(
                AppPageRoute<void>(
                  builder: (_) => TenantSessionScope(
                    controller: controller,
                    child: auditLogRoute!(reader),
                  ),
                ),
              );
            },
          ),
        if (membership.role.canAccess(TenantStaffDirectoryScreen.allowedRoles))
          HomeDestination(
            label: 'View staff directory',
            icon: Icons.people_outline,
            onPressed: () {
              final controller = TenantSessionScope.of(context);
              Navigator.of(context).push(
                AppPageRoute<void>(
                  builder: (_) => TenantSessionScope(
                    controller: controller,
                    child: TenantStaffDirectoryScreen(reader: reader),
                  ),
                ),
              );
            },
          ),
        // **The two account controls are last, and §4.4 says so by name.**
        // Neither of them is where a shop goes to trade; they are where a
        // person goes once, to change which business this is.
        if (onSwitchTenant != null &&
            switchCandidates.any(
              (candidate) =>
                  candidate.canAccess() &&
                  candidate.tenantId != membership.tenantId,
            ))
          HomeDestination(
            destinationKey: const ValueKey('change-business'),
            label: 'Change business',
            icon: Icons.swap_horiz,
            onPressed: () => _showBusinessSwitcher(context),
          ),
        if (isDefaultTenant)
          // The one disabled control on this route, and it is a state rather
          // than a refusal: this business already is the default, so there is
          // nothing to press.
          const HomeDestination(
            label: 'Default business',
            icon: Icons.star,
            onPressed: null,
          )
        else
          HomeDestination(
            destinationKey: const ValueKey('make-default-tenant'),
            label: 'Make default',
            icon: Icons.star_outline,
            onPressed: () => _showDefaultConfirmation(context),
          ),
      ];

  Future<void> _showDefaultConfirmation(BuildContext context) async {
    final controller = TenantSessionScope.read(context);
    final session = controller.session;
    if (session == null ||
        !session.canAccess() ||
        session.tenantId != membership.tenantId) {
      return;
    }
    final navigator = Navigator.of(context);
    await showAppDialog<void>(
      context,
      builder: (dialogContext) => TenantSessionScope(
        controller: controller,
        // No title: `TenantDefaultForm` carries its own heading and its own two
        // controls, so `AppDialog` here is the surface and nothing else. §7's
        // "title appears once" is the rule, and a dialog is not exempt from it.
        child: AppDialog(
          actions: const <Widget>[],
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

  Future<void> _showBusinessSwitcher(BuildContext context) async {
    final controller = TenantSessionScope.read(context);
    final session = controller.session;
    if (session == null ||
        !session.canAccess() ||
        session.tenantId != membership.tenantId ||
        onSwitchTenant == null) {
      return;
    }
    await showAppDialog<void>(
      context,
      builder: (dialogContext) => TenantBusinessSwitcher(
        currentMembership: membership,
        candidates: switchCandidates,
        onSwitchTenant: onSwitchTenant!,
        onCancel: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }
}

final class TenantBusinessSwitcher extends StatefulWidget {
  const TenantBusinessSwitcher({
    super.key,
    required this.currentMembership,
    required this.candidates,
    required this.onSwitchTenant,
    required this.onCancel,
  });

  final TenantMembership currentMembership;
  final List<TenantMembership> candidates;
  final Future<TenantSwitchResult> Function(TenantMembership membership)
  onSwitchTenant;
  final VoidCallback onCancel;

  @override
  State<TenantBusinessSwitcher> createState() => _TenantBusinessSwitcherState();
}

final class _TenantBusinessSwitcherState extends State<TenantBusinessSwitcher> {
  bool _switching = false;
  TenantSwitchBlocker? _blocker;

  List<TenantMembership> get _available => widget.candidates
      .where(
        (candidate) =>
            candidate.canAccess() &&
            candidate.tenantId != widget.currentMembership.tenantId,
      )
      .toList(growable: false);

  Future<void> _switch(TenantMembership target) async {
    if (_switching) return;
    setState(() {
      _switching = true;
      _blocker = null;
    });
    final result = await widget.onSwitchTenant(target);
    if (!mounted) return;
    if (result.switched) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _switching = false;
      _blocker = result.blocker;
    });
  }

  /// **The `SizedBox(width: 440)` this had is gone and is not replaced by
  /// another number.** 440 was the only width any dialog in this app ever
  /// stated and no section of `design.md` contains it; `AppDialog` takes §4.3's
  /// `Form` row - "single column, 720 max" - so the maximum is the system's and
  /// a narrow window shrinks the dialog rather than clipping it.
  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return AppDialog(
      title: 'Change business',
      actions: <Widget>[
        AppButton(
          label: 'Cancel',
          tier: AppButtonTier.tertiary,
          onPressed: _switching ? null : widget.onCancel,
        ),
      ],
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Choose another accessible business.',
            style: tokens.density
                .body(tokens.typography)
                .copyWith(color: tokens.colors.text.secondary),
          ),
          SizedBox(height: tokens.spacing.s12),
          for (final membership in _available)
            ListTile(
              key: ValueKey('switch-business-${membership.tenantId}'),
              enabled: !_switching,
              title: Text(membership.tenantName),
              subtitle: Text(membership.role.toJson()),
              trailing: _switching ? null : const Icon(Icons.chevron_right),
              onTap: _switching ? null : () => _switch(membership),
            ),
          if (_blocker != null) ...[
            SizedBox(height: tokens.spacing.s12),
            Callout(
              key: const ValueKey('tenant-switch-blocker'),
              // A refusal, named as one rather than painted red: the write
              // was attempted and nothing changed. Before this the whole of
              // the status was the colour, which is the case §9 rules out.
              status: AppNotice.refused(
                tenantSwitchBlockerMessage(_blocker!),
              ).status,
              message: tenantSwitchBlockerMessage(_blocker!),
            ),
          ],
          if (_switching) ...[
            SizedBox(height: tokens.spacing.s12),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }
}

String tenantSwitchBlockerMessage(
  TenantSwitchBlocker blocker,
) => switch (blocker) {
  TenantSwitchBlocker.unsynchronizedCheckout =>
    'Finish or discard the unsynchronized checkout before switching.',
  TenantSwitchBlocker.submissionInFlight =>
    'Wait for the checkout submission to finish before switching.',
  TenantSwitchBlocker.pendingWrites =>
    'Wait for pending business changes to synchronize before switching.',
  TenantSwitchBlocker.unfinishedCashCountOrShiftClose =>
    'Finish the cash count or shift close before switching.',
  TenantSwitchBlocker.unsavedTenantWorkflow =>
    'Save or discard the current business workflow before switching.',
  TenantSwitchBlocker.onlineTargetValidationUnavailable =>
    'Connect to the internet so this business can be revalidated.',
  TenantSwitchBlocker.stateInspectionUnavailable =>
    'Business state could not be checked safely. Try again.',
  TenantSwitchBlocker.targetAccessDenied =>
    'That business is no longer accessible.',
  TenantSwitchBlocker.sessionChanged =>
    'The current business changed. Open the switcher again.',
  TenantSwitchBlocker.persistenceFailed =>
    'The business selection could not be saved. The current business remains open.',
  TenantSwitchBlocker.switchInProgress =>
    'A business switch is already in progress.',
};

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

  /// §7's *failure to read a record*, in the component §5.1 names.
  ///
  /// **What this replaces is worth naming, because three of the four parts of
  /// §7's pattern were missing.** It was a 48px `Icons.error_outline` - hue and
  /// a glyph, no word, which is exactly what §9 rules out - two unstyled
  /// `Text`s at Material's defaults, and four hardcoded numbers. It had no
  /// badge, no identifier and nothing at all about what is still true.
  ///
  /// **The identifier slot stays empty here on purpose.** §7 asks for "the
  /// record's identifier in `mono`" and the record that would not open is a
  /// business this person has not been shown yet; the only string available is
  /// a UID, and printing one at somebody is §8 rule 1's worked example of what
  /// not to do.
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ErrorState(
        badgeLabel: 'Not opened',
        statement: 'We could not open your business account.',
        detail: _safeBootstrapError(error),
        // §8 rule 6, and the reason *Sign out* is offered beside *Retry*: the
        // sign-in survived, so the failure is about the account rather than
        // about the person, and there is something to retry.
        stillTrue: 'You are still signed in, and nothing has been changed.',
        actions: <Widget>[
          AppButton(
            label: 'Retry',
            tier: AppButtonTier.primary,
            onPressed: onRetry,
          ),
          AppButton(label: 'Sign out', onPressed: onSignOut),
        ],
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

  /// **`neutral`, not `problem`, and that is the one decision on this screen.**
  /// §7's pattern is written for a read that failed and §2.1's `problem` is
  /// "difference found, unreadable, out of stock"; none of that happened here.
  /// This build simply has no platform console, which §2.1's `neutral` -
  /// "archived, retired, closed" - describes exactly. Painting it red would
  /// send somebody looking for a fault that does not exist, and that is why
  /// [ErrorState.status] is a parameter at all.
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ErrorState(
        status: AppStatus.neutral,
        badgeLabel: 'Unavailable',
        statement: 'Platform administrator access is not available.',
        stillTrue: 'Your businesses are unaffected.',
        actions: <Widget>[AppButton(label: 'Sign out', onPressed: onSignOut)],
      ),
    ),
  );
}
