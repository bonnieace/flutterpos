import 'dart:async';

import 'package:flutter/material.dart';

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
import 'tenant_repository.dart';
import 'tenant_request.dart';
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
        _RoutingPhase.waitingForAuth ||
        _RoutingPhase.bootstrapping ||
        _RoutingPhase.openingTenant ||
        _RoutingPhase.signingOut => const _RoutingProgress(),
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
      checkoutRoute: widget.checkoutRoute,
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
    this.switchCandidates = const [],
    this.onSwitchTenant,
    this.checkoutRoute,
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
  final Widget? pendingCheckoutPanel;
  final Widget Function(TenantSessionController sessions)? checkoutRoute;
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
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TenantBrandingPanel(
                      reader: reader,
                      fallbackName: membership.tenantName,
                    ),
                    if (shiftPanel != null) ...[
                      const SizedBox(height: 24),
                      shiftPanel!,
                    ],
                    if (pendingCheckoutPanel != null) ...[
                      const SizedBox(height: 24),
                      pendingCheckoutPanel!,
                    ],
                  ],
                ),
              ),
            ),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              if (onSwitchTenant != null &&
                  switchCandidates.any(
                    (candidate) =>
                        candidate.canAccess() &&
                        candidate.tenantId != membership.tenantId,
                  ))
                OutlinedButton.icon(
                  key: const ValueKey('change-business'),
                  onPressed: () => _showBusinessSwitcher(context),
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Change business'),
                ),
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
              // The till. It is the only write-capable operational route on
              // this screen, and it opens under the same session scope as every
              // other one, so a business switch invalidates a sale in progress
              // exactly as it invalidates a read.
              if (checkoutRoute != null)
                FilledButton.icon(
                  key: const ValueKey('start-checkout'),
                  onPressed: () {
                    final controller = TenantSessionScope.of(context);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TenantSessionScope(
                          controller: controller,
                          child: checkoutRoute!(controller),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.point_of_sale),
                  label: const Text('New sale'),
                ),
              OutlinedButton.icon(
                onPressed: () {
                  final controller = TenantSessionScope.of(context);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
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
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('View read-only catalog'),
              ),
              if (dailySummaryRoute != null &&
                  membership.role.canAccess(dailySummaryRoles))
                OutlinedButton.icon(
                  key: const ValueKey('view-daily-summary'),
                  onPressed: () {
                    final controller = TenantSessionScope.of(context);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TenantSessionScope(
                          controller: controller,
                          child: dailySummaryRoute!(reader),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.insights_outlined),
                  label: const Text('View daily summary'),
                ),
              if (receiptLookupRoute != null &&
                  membership.role.canAccess(receiptLookupRoles))
                OutlinedButton.icon(
                  key: const ValueKey('find-receipt'),
                  onPressed: () {
                    final controller = TenantSessionScope.of(context);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TenantSessionScope(
                          controller: controller,
                          child: receiptLookupRoute!(reader),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Find a receipt'),
                ),
              if (auditLogRoute != null &&
                  membership.role.canAccess(auditLogRoles))
                OutlinedButton.icon(
                  key: const ValueKey('view-audit-log'),
                  onPressed: () {
                    final controller = TenantSessionScope.of(context);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TenantSessionScope(
                          controller: controller,
                          child: auditLogRoute!(reader),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('View activity log'),
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

  Future<void> _showBusinessSwitcher(BuildContext context) async {
    final controller = TenantSessionScope.read(context);
    final session = controller.session;
    if (session == null ||
        !session.canAccess() ||
        session.tenantId != membership.tenantId ||
        onSwitchTenant == null) {
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
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

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Change business'),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Choose another accessible business.'),
          const SizedBox(height: 12),
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
            const SizedBox(height: 12),
            Text(
              tenantSwitchBlockerMessage(_blocker!),
              key: const ValueKey('tenant-switch-blocker'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (_switching) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _switching ? null : widget.onCancel,
        child: const Text('Cancel'),
      ),
    ],
  );
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
