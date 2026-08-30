import 'dart:async';

import 'package:flutter/material.dart';

import '../checkout/checkout_draft.dart';
import '../expenses/expense.dart';
import '../expenses/expense_repository.dart';
import '../reporting/daily_metrics.dart';
import '../reporting/net_profit.dart';
import '../reporting/reporting_currency.dart';
import '../reporting/profit_report.dart';
import '../reporting/sales_totals.dart';
import '../ui/buttons.dart';
import '../ui/dialogs.dart';
import '../ui/home_navigation.dart';
import '../ui/measure.dart';
import '../ui/routes.dart';
import '../ui/scaffold.dart';
import '../ui/states.dart';
import '../ui/stats.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'account_verification.dart';
import 'email_delivery_status.dart';
import 'platform_tenant_review.dart';
import 'platform_tenant_lifecycle.dart';
import 'platform_tenant_archival.dart';
import 'platform_global_user_status.dart';
import 'tenant_access.dart';
import 'tenant_bootstrap.dart';
import 'tenant_setup_checklist.dart';
import 'tenant_standing_banner.dart';
import 'tenant_branding.dart';
import 'tenant_catalog.dart';
import 'tenant_default_tenant.dart';
import 'tenant_directory.dart';
import 'tenant_invitation_acceptance.dart';
import 'tenant_membership.dart';
import 'tenant_membership_labels.dart';
import 'tenant_repository.dart';
import 'tenant_request.dart';
import 'tenant_route_guard.dart';
import 'tenant_session.dart';
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
    this.brandingRoute,
    this.brandingRoles = const <TenantRole>[],
    this.setupChecklist,
    this.printerConfigurationRoute,
    this.printerConfigurationRoles = const <TenantRole>[],
    this.printQueueRoute,
    this.printQueueStatus,
    this.printQueueCount,
    this.catalogManagementRoute,
    this.catalogManagementRoles = const <TenantRole>[],
    this.memberName,
    this.salesTotalsCallable,
    this.pendingCheckoutPanel,
    this.shiftPanel,
    this.dailySummaryRoute,
    this.dailySummaryRoles = const <TenantRole>[],
    this.expensesRoute,
    this.expensesRoles = const <TenantRole>[],
    this.receiptLookupRoute,
    this.receiptLookupRoles = const <TenantRole>[],
    this.returnFeedRoute,
    this.returnFeedRoles = const <TenantRole>[],
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

  /// Totals the home's comparison line is built from. See
  /// `TenantSafeLandingScreen.salesTotalsCallable`.
  final SalesTotalsCallable? salesTotalsCallable;

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

  /// Optional guarded printer settings route, injected for the same reason.
  ///
  /// It is the only surface that can say where this business prints, and
  /// `docs/printer_transport.md` §6 forbids guessing an address — so until it
  /// has been used once, every receipt queues with `printer_not_configured`.
  /// Reads what a new business still has to do before it can sell, from the
  /// catalog cache this device already keeps. Absent, the card is never drawn.
  final TenantSetupChecklist? setupChecklist;

  /// Opens the guarded screen a business names itself on.
  final Widget Function(TenantDataReader reader)? brandingRoute;

  /// The roles that route is offered to, decided by the tenancy domain.
  final List<TenantRole> brandingRoles;

  final Widget Function(TenantDataReader reader)? printerConfigurationRoute;

  /// The roles that route is offered to, decided by the checkout domain. Owner
  /// and administrator: a manager runs a till, but deciding what hardware the
  /// business owns is not an operational act.
  final List<TenantRole> printerConfigurationRoles;

  /// Optional route onto this device's unsent receipts.
  ///
  /// **No role list, for the same reason [checkoutRoute] carries none.** The
  /// queue is device-local, and the person who needs to know a receipt did not
  /// come out is whoever is standing at the till.
  final Widget Function()? printQueueRoute;

  /// This device's queue depth, in words, for the destination card. §4.4: *"a
  /// card states its own condition ... queue depth"*, and one that carries none
  /// is a button. Null draws no line, which is the honest rendering when
  /// nothing is waiting.
  final String? Function()? printQueueStatus;

  /// How many receipts are waiting, for the launcher tile's badge.
  ///
  /// **A figure beside the sentence, not instead of it.** A tile has room for
  /// a number on its glyph and a menu row has room for *2 waiting to send*, so
  /// both are read from the same listing. Null where the queue cannot be
  /// listed at all, which is not the same as a queue that is empty.
  final int? Function()? printQueueCount;

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
  /// Built with the business's currency, because the shift's own figures are
  /// money and this is the only layer that knows what the money is called.
  final Widget Function(TenantReportingCurrency currency)? shiftPanel;

  /// Optional read-only reporting route, injected for the same reason.
  final Widget Function(TenantDataReader reader)? dailySummaryRoute;

  /// The roles the reporting route is offered to.
  final List<TenantRole> dailySummaryRoles;

  /// Optional expenses route, injected for the same reason.
  final Widget Function(TenantDataReader reader)? expensesRoute;

  /// The roles the expenses route is offered to.
  final List<TenantRole> expensesRoles;

  /// Optional guarded receipt-lookup route, injected for the same reason.
  final Widget Function(TenantDataReader reader)? receiptLookupRoute;

  /// The roles that route is offered to, decided by the sales domain.
  final List<TenantRole> receiptLookupRoles;

  /// Optional business-wide returns record shown from the home.
  final Widget Function(TenantDataReader reader)? returnFeedRoute;

  /// The roles that may review the business-wide returns record.
  final List<TenantRole> returnFeedRoles;

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
    if (uid == null || !membership.canRead()) return;
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
    // **Logged, never shown.** The screen states a sentence this app wrote and
    // deliberately prints no exception at a shopkeeper - §8 rule 1. That left a
    // device run with nothing to read at all, and on 2026-08-18 six distinct
    // faults in a row - a cleartext refusal, a missing functions emulator, an
    // App Check token, a short HMAC secret, a stale session - every one of them
    // rendered as the same "check your connection". One line in the log costs
    // nothing and is the difference between a diagnosis and a guess.
    debugPrint('Tenant bootstrap failed: ${error.runtimeType}: $error');
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
      salesTotalsCallable: widget.salesTotalsCallable,
      checkoutRoute: widget.checkoutRoute,
      checkoutConfigurationRoute: widget.checkoutConfigurationRoute,
      checkoutConfigurationRoles: widget.checkoutConfigurationRoles,
      brandingRoute: widget.brandingRoute,
      brandingRoles: widget.brandingRoles,
      setupChecklist: widget.setupChecklist,
      printerConfigurationRoute: widget.printerConfigurationRoute,
      printerConfigurationRoles: widget.printerConfigurationRoles,
      printQueueRoute: widget.printQueueRoute,
      printQueueStatus: widget.printQueueStatus,
      printQueueCount: widget.printQueueCount,
      catalogManagementRoute: widget.catalogManagementRoute,
      catalogManagementRoles: widget.catalogManagementRoles,
      pendingCheckoutPanel: widget.pendingCheckoutPanel,
      shiftPanel: widget.shiftPanel,
      dailySummaryRoute: widget.dailySummaryRoute,
      dailySummaryRoles: widget.dailySummaryRoles,
      expensesRoute: widget.expensesRoute,
      expensesRoles: widget.expensesRoles,
      receiptLookupRoute: widget.receiptLookupRoute,
      receiptLookupRoles: widget.receiptLookupRoles,
      returnFeedRoute: widget.returnFeedRoute,
      returnFeedRoles: widget.returnFeedRoles,
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
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return AppScaffold(
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
                padding: EdgeInsets.all(tokens.spacing.s20),
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
}

final class _InvalidTenantInvitationScreen extends StatelessWidget {
  const _InvalidTenantInvitationScreen({
    required this.onContinue,
    required this.onSignOut,
  });

  final VoidCallback onContinue;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return AppScaffold(
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
              SizedBox(height: tokens.spacing.s16),
              // §8 rule 6 - say what is still true - and it is the shape the
              // invitation refusal already took: name what will actually work
              // rather than leave a person on a dead end with one button.
              const Text(
                'This invitation link is invalid or incomplete. Ask whoever '
                'invited you to send it again.',
                textAlign: TextAlign.center,
              ),
              SizedBox(height: tokens.spacing.s16),
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
    final tokens = AppTokens.componentOf(context);
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
          padding: EdgeInsets.fromLTRB(
            tokens.spacing.s20,
            tokens.spacing.s20,
            tokens.spacing.s20,
            0,
          ),
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
          padding: EdgeInsets.fromLTRB(
            tokens.spacing.s20,
            tokens.spacing.s20,
            tokens.spacing.s20,
            0,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(tokens.spacing.s20),
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
          // **A cap, not a flex share, since 2026-08-30.** This was a
          // `Flexible`, which defaults to `flex: 1` - the same flex the list
          // below has - so the panels were given exactly half the viewport
          // whether they needed it or not. The request form then scrolled
          // inside that half with its own fields clipped, under an empty list
          // occupying the other half. `Flexible` reads like "take what you
          // need"; in a `Column` it means "take your share".
          //
          // Natural height up to three quarters, so a tall form on a short
          // window still scrolls rather than overflowing, and a short one takes
          // only what it uses.
          if (panels.isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) => ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight.isFinite
                      ? constraints.maxHeight * 0.75
                      : double.infinity,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: panels,
                  ),
                ),
              ),
            ),
          Expanded(
            child: widget.memberships.isEmpty
                ? _EmptyBusinessList(onRetry: widget.onRetry)
                : ListView.separated(
                    padding: EdgeInsets.all(tokens.spacing.s20),
                    itemCount: widget.memberships.length,
                    separatorBuilder: (_, _) =>
                        SizedBox(height: tokens.spacing.s12),
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
                              trailing: membership.canRead()
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
                              // **`canRead`, not `canAccess`.** A request whose
                              // provisional week ran out still opens: it holds
                              // a week of real trading its owner needs to see,
                              // and every write inside is refused on its own.
                              enabled: membership.canRead() || canAccept,
                              onTap: membership.canRead()
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
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.storefront_outlined, size: 48),
              SizedBox(height: tokens.spacing.s16),
              const Text('No business memberships are available.'),
              SizedBox(height: tokens.spacing.s16),
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
}

/// Pushes a route that takes this landing screen's reader, under the session
/// scope it was opened in - the same shape every destination on this screen
/// uses, factored out because the setup card opens two of them too.
void _openReaderRoute(
  BuildContext context,
  TenantDataReader reader,
  Widget Function(TenantDataReader reader) route,
) {
  final controller = TenantSessionScope.of(context);
  Navigator.of(context).push(
    AppPageRoute<void>(
      builder: (_) =>
          TenantSessionScope(controller: controller, child: route(reader)),
    ),
  );
}

/// Draws the setup card once the cache has answered, and nothing before then.
///
/// **Nothing while it is reading**, deliberately: a card that appeared a beat
/// after the home had settled would shift the grid under a finger already on
/// its way to a destination.
final class _SetupChecklistSlot extends StatefulWidget {
  const _SetupChecklistSlot({
    required this.checklist,
    this.onOpenCurrency,
    this.onOpenProducts,
  });

  final TenantSetupChecklist checklist;
  final VoidCallback? onOpenCurrency;
  final VoidCallback? onOpenProducts;

  @override
  State<_SetupChecklistSlot> createState() => _SetupChecklistSlotState();
}

class _SetupChecklistSlotState extends State<_SetupChecklistSlot> {
  Future<TenantSetupState>? _reading;
  TenantSession? _readFor;

  @override
  Widget build(BuildContext context) {
    final session = TenantSessionScope.of(context).session;
    if (session == null) return const SizedBox.shrink();
    if (!TenantSetupChecklist.showsInSession(session)) {
      return const SizedBox.shrink();
    }
    // One read per session rather than one per build: a `FutureBuilder` handed
    // a fresh future every frame reads Hive every frame.
    if (!identical(_readFor, session)) {
      _readFor = session;
      _reading = widget.checklist.read(session);
    }
    return FutureBuilder<TenantSetupState>(
      future: _reading,
      builder: (context, snapshot) {
        final state = snapshot.data;
        if (state == null || state.isComplete) return const SizedBox.shrink();
        return TenantSetupChecklistCard(
          state: state,
          onOpenCurrency: widget.onOpenCurrency,
          onOpenProducts: widget.onOpenProducts,
        );
      },
    );
  }
}

enum TenantMembershipDisplayStatus {
  accessible('Accessible'),

  /// A self-serve request inside its provisional window: trading, on a
  /// deadline. Named for what it is rather than for the deadline, because the
  /// row is a list of businesses and the countdown belongs on the business.
  provisional('Trial'),

  /// A request whose window has shut. Opens, and cannot be traded in.
  lapsed('Read-only'),

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
  // Asked before `canAccess`, because a provisional business *can* trade and
  // would otherwise read as plainly accessible - which is true and is not the
  // thing somebody choosing a business needs to know about it.
  switch (membership.standing) {
    case TenantStanding.provisional:
      return TenantMembershipDisplayStatus.provisional;
    case TenantStanding.lapsed:
      return TenantMembershipDisplayStatus.lapsed;
    case TenantStanding.approved:
    case TenantStanding.closed:
      break;
  }
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
          //
          // **Top-aligned since 2026-08-23, and it was `Center`.** Nothing
          // about this route wants its content in the middle of the window,
          // and at `expanded` - where the destinations are in the frame's menu
          // and the body is three short sections - centring left roughly 270
          // pixels of ground between the business name and the first thing
          // under it. Below `expanded` the content overflows, so the two
          // alignments were identical and the difference never showed.
          Align(
            alignment: Alignment.topCenter,
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

/// What the landing route reads for its own body.
///
/// **Three reads where there was one, at the product owner's direction on
/// 2026-08-23.** The home was one branding document and nothing else, and the
/// design it is now built to opens on figures: `manager_dashboard` leads with a
/// grid of them and a list of recent activity. There is no honest way to draw
/// that from a page that reads nothing, so the page reads.
///
/// **Every part degrades on its own.** A home that went blank because the day
/// had not reconciled, or because a cashier may not read revenue, would be a
/// worse page than the one this replaces - so each field is null or empty on
/// failure and the sections that depend on it simply do not draw. The branding
/// read keeps exactly the behaviour it had.
final class _HomeOverview {
  const _HomeOverview({
    this.branding,
    this.today,
    this.trend,
    this.currency,
    this.expenses,
    this.showProfit = false,
  });

  /// Today's takings and the day before's, as the server currently adds them
  /// up - **still in flight, not resolved.**
  ///
  /// **The one read on this page that is not awaited before it renders.** Every
  /// other figure here is a Firestore read and serves from its cache; this is
  /// two callable round trips and cannot be served offline at all. Awaiting it
  /// with the rest held the business name, the day's reconciled figures and the
  /// currency behind the slowest and least important line on the screen - which
  /// is the defect the product owner reported on 2026-08-27: *the online data
  /// makes the offline data come late*.
  ///
  /// Null where no totals callable was supplied or where the session may not
  /// read revenue. It resolves to null where the read failed, and the greeting
  /// then states no comparison - the same as before.
  final Future<({double today, double previous})?>? trend;

  final TenantBranding? branding;

  /// Today's business day, reconciled or not. Null where the session may not
  /// read business revenue - `TenantDailyMetricsRepository.allowedRoles` is
  /// owner, admin and manager - or where the read failed.
  final TenantDailyMetricsDay? today;

  /// What the business prices in, read only when [today] was.
  final TenantReportingCurrency? currency;

  /// Today's recorded spending, or null where this member may not read it or
  /// the read failed.
  ///
  /// **Awaited with the rest rather than handed on like [trend].** This is a
  /// Firestore read and serves from the cache, so it costs the page nothing to
  /// wait for and the net figure lands with the gross one instead of after it.
  /// It is also why net profit works with no signal at all: both halves of the
  /// subtraction are cached reads.
  final TenantExpensePeriod? expenses;

  /// Whether this member may be shown the margin at all.
  ///
  /// **The home was the one surface that never asked.** `daily_metrics` is
  /// readable by owner, administrator *and* manager, so a manager's overview
  /// arrives carrying `profitReport` - and this grid printed it. But
  /// `TenantProfitReport.allowedRoles` is owner and administrator only, and
  /// says in as many words that what the cost tier buys is that no manager is
  /// shown the margin. `daily_metrics_panel.dart` and `sales_totals_panel.dart`
  /// both gate on `canSeeInSession`; this now does too.
  final bool showProfit;
}

/// The old hub's greeting: the time of day, who is signed in, and what the
/// screen is for.
///
/// **Restored 2026-08-25.** The pre-multitenancy app opened with *"Good
/// Morning, {Name}"* over *"Select a module to begin."*, and that pair is what
/// existing customers read first. The old screen's second line — a
/// today-against-yesterday sales percentage with a trend arrow — is
/// deliberately **not** rebuilt here: it came from an unscoped `shifts` query
/// this screen has no tenant-safe equivalent for, and inventing one would be a
/// behaviour change in a visual revert. The figures under the grid say what
/// this app can honestly say about the day.
///
/// **The name is optional and the sentence does not depend on it.** A session
/// whose member name has not resolved greets the business rather than printing
/// a gap or the word `null`, which is what the old screen did when its `staff`
/// document was slow.
///
/// **Centred, which is the old hub's own arrangement.** Its `_GreetingSection`
/// was a `Column` at the default `crossAxisAlignment.center` with its
/// performance row centred inside that, so the whole block sat in the middle of
/// the page rather than against its left edge.
final class _LandingGreeting extends StatelessWidget {
  const _LandingGreeting({
    required this.memberName,
    required this.businessName,
    this.trend,
    this.isOwnFigures = false,
  });

  final String? memberName;
  final String businessName;

  /// Today's takings and the day before's, on their own clock. Absent, or
  /// resolving to null, means there is no comparison to state - and the line is
  /// simply not drawn, which is what this greeting has always done when it had
  /// nothing to compare.
  ///
  /// **No placeholder while it is in flight, deliberately.** The line is one
  /// sentence that either exists or does not; a shimmer where it will maybe go
  /// would reserve space for something that frequently never comes, and make
  /// the greeting jump when it does not.
  final Future<({double today, double previous})?>? trend;

  /// Whether the figures being compared are this member's own rather than the
  /// whole business's. The old screen said *Shift performance* to a cashier
  /// and *Store performance* to an admin, and the distinction is real: the two
  /// sentences are about different money.
  final bool isOwnFigures;

  /// The old screen's three bands, at its own boundaries.
  ///
  /// **Static and given the time rather than reading it**, so a test asserts
  /// the boundaries without waiting for an hour to come round.
  static String greetingAt(DateTime now) {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  /// How much narrower each line is than the one above it.
  ///
  /// **One constant applied twice, rather than three widths.** The product
  /// owner asked for a block that trickles down - greeting widest, the
  /// performance line inside it, the prompt inside that - and three chosen
  /// numbers would be three things to keep in step. This is a ratio, so the
  /// funnel holds its proportions at every width instead of only at the one it
  /// was tuned on.
  ///
  /// Named here rather than tokenised, for the reason `EmptyState.markSize`
  /// gives: no source this app has states a heading funnel, and inventing
  /// `layout.funnelStep` would be inventing a token, which `CLAUDE.md` forbids
  /// one rule before it forbids magic numbers.
  static const double funnelStep = 0.8;

  /// The old hub's second line, verbatim.
  static const String _prompt = 'Select a module to begin.';

  /// The greeting, shortened only as far as it has to be to stay on one line.
  ///
  /// **A ladder, not a truncation.** The old hub put the greeting on one line
  /// and a wrapped one reads as a mistake rather than as a long name, so this
  /// tries the full sentence, then the first name, then the smaller display
  /// role, and only ellipsises when a single name will not fit a phone. That is
  /// the product owner's *"first name only if suitable"*: suitable means the
  /// full one did not fit, measured rather than guessed.
  ///
  /// **This is [fitToOneLine] with the greeting's three rungs named** —
  /// `display` (32) → `displayCompact` (28) → `titleLarge` (22), all roles this
  /// app already sets headings in. The measuring, the ordering, and the reason
  /// none of it is a scale factor, are all written on that function.
  ///
  /// **`titleLarge` is the floor and it earns its place.** Without it a business
  /// name long enough to overflow `displayCompact` fell straight to the
  /// ellipsis, and the first capture showed the result: *Good morning, Dev
  /// Corner…* on a shop called Dev Corner Shop. A greeting that cannot name the
  /// business is worse than a slightly smaller one.
  static ({String text, TextStyle style}) _fit({
    required String full,
    required String? shortened,
    required TextStyle display,
    required TextStyle compact,
    required TextStyle floor,
    required double maxWidth,
    required TextScaler scaler,
    required TextStyle ambient,
  }) => fitToOneLine(
    // Shortening the name is preferred to shrinking the type at each size,
    // which is the product owner's ordering: *first name only if suitable*
    // comes before making the whole line smaller.
    texts: <String>[full, if (shortened != null) shortened],
    styles: <TextStyle>[display, compact, floor],
    maxWidth: maxWidth,
    scaler: scaler,
    ambient: ambient,
  );

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final now = DateTime.now();
    final who = memberName?.trim();
    final salutation = greetingAt(now);
    final subject = who == null || who.isEmpty ? businessName : who;
    final greeting = '$salutation, $subject';
    // The first word of a name, where there is more than one. A business name
    // is never cut down this way - "Good morning, Chill" for *Chill Tent
    // Supplies* names nothing a shopkeeper would recognise.
    final firstName = who == null || who.isEmpty
        ? null
        : switch (who.split(RegExp(r'\s+'))) {
            [final first, _, ...] => '$salutation, $first',
            _ => null,
          };
    final wide = PageHeader.showsDisplayTitle(MediaQuery.sizeOf(context).width);
    final display =
        (wide ? tokens.typography.display : tokens.typography.displayCompact)
            .copyWith(color: tokens.colors.text.primary);
    final compact = tokens.typography.displayCompact.copyWith(
      color: tokens.colors.text.primary,
    );
    final floor = tokens.typography.titleLarge.copyWith(
      color: tokens.colors.text.primary,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        // The funnel: each line inside the one above it.
        final trendWidth = available * funnelStep;
        final promptWidth = trendWidth * funnelStep;
        final fitted = _fit(
          full: greeting,
          shortened: firstName,
          display: display,
          compact: compact,
          floor: floor,
          maxWidth: available,
          scaler: MediaQuery.textScalerOf(context),
          ambient: DefaultTextStyle.of(context).style,
        );
        return Column(
          // The old hub's own alignment - its `Column` took the default.
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Semantics(
              header: true,
              // **The whole greeting, whatever the line ended up saying.**
              // Shortening for width must not shorten what a blind person is
              // told: the visible text may be *Good morning, Amina* where the
              // sentence is *Good morning, Amina Wanjiru*, and the second is
              // what is read out.
              label: greeting,
              // **The painted text is excluded, or it would win.** A `Text`
              // under a labelled `Semantics` contributes its own string as
              // well, so the node would announce the shortened line - which is
              // the opposite of the point.
              child: ExcludeSemantics(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: available),
                  child: Text(
                    fitted.text,
                    key: const ValueKey('home-greeting'),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: fitted.style,
                  ),
                ),
              ),
            ),
            SizedBox(height: tokens.spacing.s8),
            if (trend case final pending?)
              FutureBuilder<({double today, double previous})?>(
                future: pending,
                builder: (context, snapshot) {
                  final comparison = snapshot.data;
                  final reading = _TrendReading.from(
                    today: comparison?.today,
                    previous: comparison?.previous,
                  );
                  if (reading == null) return const SizedBox.shrink();
                  return Padding(
                    padding: EdgeInsets.only(bottom: tokens.spacing.s4),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: trendWidth),
                      child: _LandingTrendLine(
                        reading: reading,
                        isOwnFigures: isOwnFigures,
                        maxWidth: trendWidth,
                      ),
                    ),
                  );
                },
              ),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: promptWidth),
              // The narrowest of the three, so it is the likeliest to have to
              // give ground - and it takes the same ladder as the two above it
              // rather than a rule of its own.
              child: Text(
                _prompt,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: fitToOneLine(
                  texts: const <String>[_prompt],
                  styles: <TextStyle>[
                    tokens.typography.bodyLarge,
                    tokens.typography.bodyMedium,
                    tokens.typography.caption,
                  ],
                  maxWidth: promptWidth,
                  scaler: MediaQuery.textScalerOf(context),
                  ambient: DefaultTextStyle.of(context).style,
                ).style.copyWith(color: tokens.colors.text.secondary),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The largest text and type role from [texts] and [styles] that fits one line.
///
/// **All three lines of the home header use this, which is the point of it
/// being one function.** The product owner asked for a block where every line
/// sits on a single row and each is narrower than the one above; that only
/// works if every line can give ground the same way, and three separate
/// implementations of "make it fit" would give ground differently.
///
/// **[styles] are type roles, largest first, and never a scale factor.** A
/// `FittedBox` fits any string by inventing a font size, which is hard rule 2's
/// own complaint: 26.4 is not on §2.2's scale and nothing else on the page would
/// share it. Every rung here is a role this app already sets text in.
///
/// **[texts] are alternative wordings, preferred first.** Only the greeting has
/// one - a person's first name in place of their full one - and the ordering is
/// text-inside-style, so a shorter wording is tried before a smaller size.
///
/// **[reserved] is room this line needs for something that is not text**: the
/// trend line's arrow, which sits inside the same row and is measured in
/// nothing this function can see.
///
/// **The measurement passes the ambient style**, which `measure.dart` is
/// emphatic about: this app's `ThemeData` carries Material's `letterSpacing` on
/// roles the token layer does not set one for, and a string measured without it
/// comes out a quarter of a pixel per character too narrow - which is how a line
/// calculated to fit wraps anyway.
({String text, TextStyle style}) fitToOneLine({
  required List<String> texts,
  required List<TextStyle> styles,
  required double maxWidth,
  required TextScaler scaler,
  required TextStyle ambient,
  double reserved = 0,
}) {
  final room = maxWidth - reserved;
  for (final style in styles) {
    for (final text in texts) {
      final width = measureTextWidth(
        text,
        style,
        textScaler: scaler,
        ambient: ambient,
      );
      if (width <= room) return (text: text, style: style);
    }
  }
  // Nothing fits even at the smallest rung, so the shortest wording takes the
  // ellipsis. A string this long on a screen this narrow has to lose something;
  // it loses the least.
  return (text: texts.last, style: styles.last);
}

/// Today's takings against yesterday's, as a direction and a percentage.
///
/// **Built only where both days are reconciled**, which is the honest reading
/// of the figures this app holds: today is normally unreconciled, and a
/// comparison against a day that has not been added up is a number nobody
/// should act on. `null` means the greeting says nothing rather than printing
/// a plausible zero - the same rule the stat tiles follow with their em dash.
@immutable
final class _TrendReading {
  const _TrendReading({required this.percent, required this.direction});

  /// The size of the change, never negative. The sign is in [direction].
  final double percent;
  final _TrendDirection direction;

  static _TrendReading? from({
    required double? today,
    required double? previous,
  }) {
    final now = today;
    final before = previous;
    if (now == null || before == null) return null;
    if (before == 0) {
      // **No percentage against a day that took nothing.** Dividing by it
      // yields either infinity or an arbitrary 100%, and the old screen printed
      // the arbitrary one. A day that went from nothing to something is level
      // as far as a *percentage* is concerned; the figure itself is in the tile.
      return now == 0
          ? const _TrendReading(percent: 0, direction: _TrendDirection.level)
          : null;
    }
    final change = ((now - before) / before) * 100;
    return _TrendReading(
      percent: change.abs(),
      direction: change == 0
          ? _TrendDirection.level
          : change > 0
          ? _TrendDirection.up
          : _TrendDirection.down,
    );
  }
}

enum _TrendDirection { up, down, level }

/// The old hub's second greeting line: *Store performance is up 12% today.*
///
/// **The percentage animates in and the sentence around it does not**, which is
/// what the old screen did: an `AnimatedSwitcher` slid the figure in from below
/// when it rose and from above when it fell, so the direction was legible
/// before the arrow was read. That motion is kept and its duration and curve
/// come from `tokens.motion` rather than the old hardcoded 400ms.
///
/// **Direction is never colour alone.** §9 and `DESIGN_RULES.md` both require
/// it: the arrow glyph points, the word says *up* or *down*, and the semantic
/// label reads the whole sentence. Colour is the third signal, not the only
/// one.
final class _LandingTrendLine extends StatelessWidget {
  const _LandingTrendLine({
    required this.reading,
    required this.isOwnFigures,
    required this.maxWidth,
  });

  final _TrendReading reading;
  final bool isOwnFigures;

  /// The funnel's second step, so this line can size itself to fit it.
  ///
  /// **It has to fit on one row, which is the product owner's direction of
  /// 2026-08-27.** Sitting inside the funnel makes this line narrower than the
  /// greeting above it, and at `body.lg` on a phone the sentence did not fit -
  /// the words wrapped and left the arrow and the percentage stranded on the
  /// first line's right edge. So it takes the same ladder the greeting takes,
  /// down the body roles rather than the display ones.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final subject = isOwnFigures ? 'Shift performance' : 'Store performance';
    final (word, glyph, colour) = switch (reading.direction) {
      _TrendDirection.up => (
        'up',
        Icons.trending_up,
        tokens.colors.status.ok.fg,
      ),
      _TrendDirection.down => (
        'down',
        Icons.trending_down,
        tokens.colors.status.problem.fg,
      ),
      _TrendDirection.level => (
        'level with',
        Icons.trending_flat,
        tokens.colors.text.tertiary,
      ),
    };
    final figure = '${reading.percent.toStringAsFixed(0)}%';
    final sentence = reading.direction == _TrendDirection.level
        ? '$subject is level with yesterday.'
        : '$subject is $word $figure today.';

    // The whole sentence is measured, not the fragment this row starts with:
    // the arrow, the figure and the trailing `today.` are all on the same line
    // and all have to fit beside it.
    final body = fitToOneLine(
      texts: <String>[sentence],
      styles: <TextStyle>[
        tokens.typography.bodyLarge,
        tokens.typography.bodyMedium,
        tokens.typography.caption,
      ],
      maxWidth: maxWidth,
      scaler: MediaQuery.textScalerOf(context),
      ambient: DefaultTextStyle.of(context).style,
      // The arrow and the gap after it, which are not text and so are invisible
      // to a measurement of one.
      reserved: _glyphSize + tokens.spacing.s4,
    ).style.copyWith(color: tokens.colors.text.secondary);

    return Semantics(
      label: sentence,
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // **One line, and an ellipsis rather than an overflow if the ladder
          // ran out.** The prose is what gives way; the figure beside it never
          // does, because a truncated percentage is a wrong number rather than
          // a shortened sentence.
          Flexible(
            child: Text(
              '$subject is $word ',
              style: body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (reading.direction != _TrendDirection.level) ...<Widget>[
            ClipRect(
              child: AnimatedSwitcher(
                duration: tokens.motion.short.duration,
                switchInCurve: tokens.motion.short.curve,
                transitionBuilder: (child, animation) => SlideTransition(
                  // Rising figures arrive from below and falling ones from
                  // above, so the motion itself carries the direction.
                  position:
                      Tween<Offset>(
                        begin: Offset(
                          0,
                          reading.direction == _TrendDirection.up ? 1 : -1,
                        ),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: tokens.motion.short.curve,
                        ),
                      ),
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Row(
                  key: ValueKey<String>('$word$figure'),
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(glyph, size: _glyphSize, color: colour),
                    SizedBox(width: tokens.spacing.s4),
                    Text(
                      figure,
                      style: tokens.typography.numericBody.copyWith(
                        color: colour,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Text(' today.', style: body),
          ] else
            Text('yesterday.', style: body),
        ],
      ),
    );
  }

  /// Matches the trend figure's cap height beside `body.lg`.
  static const double _glyphSize = 18;
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
    this.brandingRoute,
    this.brandingRoles = const <TenantRole>[],
    this.setupChecklist,
    this.printerConfigurationRoute,
    this.printerConfigurationRoles = const <TenantRole>[],
    this.printQueueRoute,
    this.printQueueStatus,
    this.printQueueCount,
    this.catalogManagementRoute,
    this.catalogManagementRoles = const <TenantRole>[],
    this.memberName,
    this.pendingCheckoutPanel,
    this.shiftPanel,
    this.salesTotalsCallable,
    this.dailySummaryRoute,
    this.dailySummaryRoles = const <TenantRole>[],
    this.expensesRoute,
    this.expensesRoles = const <TenantRole>[],
    this.receiptLookupRoute,
    this.receiptLookupRoles = const <TenantRole>[],
    this.returnFeedRoute,
    this.returnFeedRoles = const <TenantRole>[],
    this.productStockRoute,
    this.productStockRoles = const <TenantRole>[],
    this.stockAdjustmentFeedRoute,
    this.stockAdjustmentFeedRoles = const <TenantRole>[],
    this.stockMovementFeedRoute,
    this.stockMovementFeedRoles = const <TenantRole>[],
    this.auditLogRoute,
    this.auditLogRoles = const <TenantRole>[],
  });

  /// Totals the greeting's comparison line is built from, supplied by the
  /// composition root. Absent, the home simply states no comparison - the
  /// route is never gated on it.
  final SalesTotalsCallable? salesTotalsCallable;

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

  /// Optional guarded printer settings route, supplied by the composition root.
  /// See `TenantRoutingShell.printerConfigurationRoute`.
  /// Reads what a new business still has to do before it can sell, from the
  /// catalog cache this device already keeps. Absent, the card is never drawn.
  final TenantSetupChecklist? setupChecklist;

  /// Opens the guarded screen a business names itself on.
  final Widget Function(TenantDataReader reader)? brandingRoute;

  /// The roles that route is offered to, decided by the tenancy domain.
  final List<TenantRole> brandingRoles;

  final Widget Function(TenantDataReader reader)? printerConfigurationRoute;

  /// The roles that route is offered to. Owner and administrator only.
  final List<TenantRole> printerConfigurationRoles;

  /// Optional route onto this device's unsent receipts, carrying no role list.
  final Widget Function()? printQueueRoute;

  /// This device's queue depth, in words. See
  /// `TenantRoutingShell.printQueueStatus`.
  final String? Function()? printQueueStatus;

  /// The same depth as a figure. See `TenantRoutingShell.printQueueCount`.
  final int? Function()? printQueueCount;

  /// Optional guarded catalog-management route, supplied by the composition
  /// root. It is the one surface that can put a product in the catalog, which
  /// is what every other operational route on this screen already assumed.
  final Widget Function(TenantDataReader reader)? catalogManagementRoute;

  /// The roles that route is offered to, decided by the inventory domain.
  final List<TenantRole> catalogManagementRoles;

  /// Built with the business's currency, because the shift's own figures are
  /// money and this is the only layer that knows what the money is called.
  final Widget Function(TenantReportingCurrency currency)? shiftPanel;

  /// Builds the read-only reporting route. Supplied by the composition root so
  /// tenancy code keeps owning routing rather than the reporting domain; the
  /// route stays unreachable while it is absent.
  final Widget Function(TenantDataReader reader)? dailySummaryRoute;

  /// The roles that route is offered to, decided by the reporting domain.
  final List<TenantRole> dailySummaryRoles;

  /// Builds the expenses route, supplied by the composition root like every
  /// other one here; it stays unreachable while it is absent.
  final Widget Function(TenantDataReader reader)? expensesRoute;

  /// The roles that route is offered to, decided by the expenses domain.
  final List<TenantRole> expensesRoles;

  /// Optional guarded receipt-lookup route, injected for the same reason.
  final Widget Function(TenantDataReader reader)? receiptLookupRoute;

  /// The roles that route is offered to, decided by the sales domain.
  final List<TenantRole> receiptLookupRoles;

  /// Optional business-wide returns record shown as its own home module.
  final Widget Function(TenantDataReader reader)? returnFeedRoute;

  final List<TenantRole> returnFeedRoles;

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
  Widget build(BuildContext context) => TenantRouteGuard<_HomeOverview>(
    load: (session) => _readOverviewWith(reader, session),
    // **The front door draws from this device's own copy first.** Every read
    // below already degrades to nothing on its own, so the home never showed an
    // error - it showed a shop its own name and four blank figures until the
    // network answered. The figures were on this disk the whole time.
    loadCached: switch (reader.cached) {
      final cached? => (session) => _readOverviewWith(cached, session),
      null => null,
    },
    // **The page is never gated on any of it, and that is the point of giving
    // every phase the same builder.** A business that has published no
    // branding, a read that failed, a read still in flight and a denied session
    // all draw the home with `membership.tenantName` and no figures - which is
    // the behaviour this page had before it read anything. The worst case is
    // the previous page rather than a spinner where a shop expects its own
    // front door.
    loading: _page(context, const _HomeOverview()),
    denied: _page(context, const _HomeOverview()),
    failure: (context, _) => _page(context, const _HomeOverview()),
    builder: (context, session, overview) => _page(context, overview),
  );

  /// Reads the three documents the body draws from, concurrently.
  ///
  /// **Each is swallowed on its own.** `Future.wait` would fail the set on the
  /// first refusal, and the refusals here are ordinary: a day is normally
  /// unreconciled, a cashier may not read revenue at all, and a business with
  /// no published currency answers `unknown`. None of those is a reason for a
  /// shop to open on an error.
  Future<_HomeOverview> _readOverviewWith(
    TenantDataReader reader,
    TenantSession session,
  ) async {
    final branding = _quiet(
      () => TenantBrandingRepository(session: session, reader: reader).load(),
    );
    // The repository enforces this itself and throws `metrics_forbidden`; the
    // gate is here as well so a cashier's home does not spend a read finding
    // out. The currency is read on the same condition, because it exists only
    // to format the figures that read produces.
    final mayReadRevenue = session.canAccess(
      allowedRoles: TenantDailyMetricsRepository.allowedRoles,
    );
    final recentDays = mayReadRevenue
        ? _quiet(
            () => TenantDailyMetricsRepository(
              session: session,
              reader: reader,
            ).loadRecentDays(days: 1),
          )
        : Future<List<TenantDailyMetricsDay>?>.value();
    // **The greeting's comparison comes from the totals callable, not from
    // these days.** `TenantDailyMetricsRepository` reports what nightly
    // reconciliation regenerated, and today is normally unreconciled - so a
    // trend built on it would say nothing on exactly the day somebody is
    // asking about, which is what the first attempt at this line did. The
    // totals gateway adds up the sales the server currently holds, which is
    // the live figure the old hub summed out of open shifts.
    final trend = mayReadRevenue && salesTotalsCallable != null
        ? _quiet(() async {
            final gateway = TenantSalesTotalsGateway(
              session: session,
              callable: salesTotalsCallable!,
            );
            final today = await gateway.load(
              gateway.createQuery(period: TenantSalesPeriod.today),
            );
            final before = await gateway.load(gateway.createPreviousDayQuery());
            return (today: today.sales, previous: before.sales);
          })
        : Future<({double today, double previous})?>.value();
    final currency = mayReadRevenue
        ? _quiet(
            () =>
                TenantReportingCurrency.read(session: session, reader: reader),
          )
        : Future<TenantReportingCurrency?>.value();
    // What the business spent today, which is the other half of a profit
    // figure. Narrower than the takings above - `TenantExpenseRepository`
    // is owner and administrator, matching the roles a margin is shown to -
    // and a Firestore read, so it is cached like the rest of this set.
    final expenses = TenantExpenseRepository.canSeeInSession(session)
        ? _quiet(() {
            final today = checkoutBusinessDate(DateTime.now().toUtc());
            return TenantExpenseRepository(
              session: session,
              reader: reader,
            ).readDay(today);
          })
        : Future<TenantExpensePeriod?>.value();
    final days = await recentDays ?? const <TenantDailyMetricsDay>[];
    // **The trend is handed on rather than awaited**, for the reason
    // `_HomeOverview.trend` gives. It is already in flight; what changes is
    // that the rest of the home no longer waits on it.
    return _HomeOverview(
      branding: await branding,
      today: days.isEmpty ? null : days.first,
      trend: trend,
      currency: await currency,
      expenses: await expenses,
      showProfit: TenantProfitReport.canSeeInSession(session),
    );
  }

  // **No recent-sales read since 2026-08-27.** The product owner removed the
  // section: the same sales are the whole subject of the Sales route, and a
  // three-row copy of its first page cost a query on every home load to repeat
  // what a tap away already said in full.

  static Future<T?> _quiet<T>(Future<T> Function() read) async {
    try {
      return await read();
    } catch (_) {
      return null;
    }
  }

  /// The home, titled by the branding where the business has published one.
  Widget _page(BuildContext context, _HomeOverview overview) {
    final branding = overview.branding;
    final tokens = AppTokens.componentOf(context);
    final inset = AppScaffold.horizontalInset(tokens.spacing);
    // **One navigation, and it is the grid.** The destinations had two hosts
    // — the body's cards and the frame's drawer/side menu — until 2026-08-25,
    // when the old hub's card grid came back as the body. Keeping both put
    // every destination on the screen twice at `expanded` (and two widgets
    // under one key), which is duplication a person sees rather than only a
    // test. The old app navigated by its grid alone, so the frame's menu is
    // withdrawn here; `AppScaffold` still offers it to any other screen that
    // wants one.
    final destinations = _destinations(context);
    return AppScaffold(
      title: branding?.companyName ?? membership.tenantName,
      // §4.2's record row rather than its reading row: the grid wants the
      // wider measure, and 720 would narrow the page under the shift panel it
      // sits below.
      contentWidth: AppContentWidth.records,
      // §4.4's top bar, in the two slots that need no data the home is not
      // given. The queue button is `CheckoutPendingEvidencePanel` itself,
      // moved rather than rebuilt: it already held the counts, so restyling it
      // into `SyncIndicator` put the badge in reach of the bar without the
      // number being hoisted anywhere. See `PLAN.md` for the two slots of the
      // mockup that are still short - the member's name and the switcher.
      // **Two glyphs, and no words.** The bar carries the hamburger, the
      // screen's own name, and the two controls that are true of every screen:
      // what this device still has to send, and the way out. *Sign out* was a
      // text button, and on a 360 handset the words left nothing for the title
      // beside them.
      actions: [
        if (pendingCheckoutPanel != null) pendingCheckoutPanel!,
        AppIconButton(
          key: const ValueKey('sign-out'),
          icon: Icons.logout,
          semanticLabel: 'Sign out',
          tier: AppButtonTier.tertiary,
          bordered: false,
          onPressed: () => unawaited(onSignOut()),
        ),
      ],
      // **No subtitle, since 2026-08-23.** It said `Dev Owner - Owner` under
      // a title that already named the business, and between them they cost
      // about 130 logical pixels of every route before a single figure. The
      // signed-in member is named in the drawer, which is where the account
      // controls are.
      // **The body is the dashboard the design draws, and the destinations
      // are not in it any more.** `manager_dashboard` opens on a grid of
      // figures, then the two things a person came to do, then what has
      // happened recently; its navigation is behind the top bar's `menu`
      // button. So the eleven destinations moved into `AppScaffold`'s drawer -
      // and at `expanded` into its persistent column - and what is left here is
      // the page itself.
      //
      // Everything in it scrolls together.
      // **The old hub's body, restored 2026-08-25.** The pre-multitenancy app
      // opened on a greeting, a grid of module cards, and a bar of figures,
      // and that grid was how a person got anywhere. The Stitch pass moved
      // the destinations behind a hamburger and opened on figures instead;
      // existing customers found the result unfamiliar, so the cards are back
      // in the body. The drawer stays as chrome — an addition rather than a
      // replacement — so nothing that was reachable stops being reachable.
      //
      // Everything in it scrolls together.
      body: Padding(
        padding: EdgeInsets.fromLTRB(inset, 0, inset, tokens.spacing.s24),
        child: _LandingScrollArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _LandingGreeting(
                memberName: memberName,
                businessName: branding?.companyName ?? membership.tenantName,
                trend: overview.trend,
                // The figures come from `TenantDailyMetricsRepository`, whose
                // allowed roles are the business-wide ones - so whenever there
                // is a comparison to state at all, it is the store's. A
                // cashier is never given these days in the first place, which
                // is why this is false rather than derived from the role.
                isOwnFigures: false,
              ),
              SizedBox(height: tokens.spacing.s32),
              // Above the grid rather than below it: a business that cannot
              // trade should say so before somebody taps *Register* and finds
              // out from a refusal.
              TenantStandingBanner(access: membership.access),
              // Reads Hive, not Firestore: see `tenant_setup_checklist.dart`.
              // A `FutureBuilder` rather than a guarded load because there is
              // nothing to authorize - the session was authorized to reach this
              // screen, and the answer comes off this device.
              if (setupChecklist case final checklist?)
                _SetupChecklistSlot(
                  checklist: checklist,
                  onOpenCurrency: checkoutConfigurationRoute == null
                      ? null
                      : () => _openReaderRoute(
                          context,
                          reader,
                          checkoutConfigurationRoute!,
                        ),
                  onOpenProducts: catalogManagementRoute == null
                      ? null
                      : () => _openReaderRoute(
                          context,
                          reader,
                          catalogManagementRoute!,
                        ),
                ),
              HomeModuleGrid(destinations: destinations),
              if (_figures(context, overview) case final grid?) ...[
                SizedBox(height: tokens.spacing.s32),
                grid,
              ],
              if (shiftPanel != null) ...[
                SizedBox(height: tokens.spacing.s24),
                shiftPanel!(
                  overview.currency ?? TenantReportingCurrency.unknown,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The grid of figures the design opens on, or null where there are none.
  ///
  /// **Only figures this app actually holds.** The export's fourth tile is
  /// *Low stock — 5 items*, and there is no low-stock reading anywhere in this
  /// product: `test/dev/reachable_lib_test.dart` records the reorder model as
  /// unreachable and `DESIGN_RULES.md` forbids drawing a control the code does
  /// not support. Receipts waiting is a real count this page already held, so
  /// it takes the fourth slot.
  ///
  /// **A cashier gets the print queue and nothing else.** Business revenue is
  /// owner, admin and manager by `TenantDailyMetricsRepository.allowedRoles`,
  /// so a cashier's overview carries no day at all and three of the four tiles
  /// have nothing honest to say.
  Widget? _figures(BuildContext context, _HomeOverview overview) {
    final tokens = AppTokens.componentOf(context);
    final day = overview.today;
    final metrics = day?.metrics;
    final report = metrics?.profitReport;
    final currency = overview.currency ?? TenantReportingCurrency.unknown;
    // Composed here rather than on the server: `daily_metrics.profit` is
    // revenue minus the cost of the goods sold and stays that way, so nothing
    // already written changes meaning. Null where either half is missing.
    final net = report == null || overview.expenses == null
        ? null
        : TenantNetProfitReport.from(
            gross: report,
            expenses: overview.expenses,
          );
    final tiles = <StatTile>[
      if (day != null) ...<StatTile>[
        StatTile(
          key: const ValueKey('home-today-sales'),
          label: "Today's sales",
          // **An em dash, not a zero.** An unreconciled day is not a day with
          // no takings in it - today is normally unreconciled, and printing
          // `KES 0.00` over a morning's trade would be the worst kind of
          // wrong figure: a plausible one.
          value: metrics == null ? '—' : currency.format(metrics.sales),
          money: metrics != null,
          icon: Icons.payments_outlined,
          detail: metrics == null
              ? 'Not reconciled yet'
              : 'Reconciled ${day.businessDate}',
        ),
        StatTile(
          key: const ValueKey('home-today-transactions'),
          label: 'Transactions',
          value: metrics == null ? '—' : '${metrics.transactions}',
          icon: Icons.receipt_long_outlined,
          detail: metrics == null ? 'Not reconciled yet' : 'Counted today',
        ),
        StatTile(
          key: const ValueKey('home-today-shifts'),
          label: 'Shifts',
          value: metrics == null ? '—' : '${metrics.shiftCount}',
          icon: Icons.schedule_outlined,
          detail: metrics == null ? 'Not reconciled yet' : 'Closed today',
        ),
        // **Profit, which is the fourth figure this app actually holds.** The
        // export's fourth tile is *Low stock — 5 items* and there is no
        // low-stock reading anywhere in this product;
        // `test/dev/reachable_lib_test.dart` records the reorder model as
        // unreachable and `DESIGN_RULES.md` forbids drawing a control the code
        // does not support.
        //
        // **`isShowable` is the reason it is not simply `metrics.profit`.** A
        // day whose sale lines are missing their cost produces a profit figure
        // the server did compute and nobody should read; `TenantProfitReport`
        // is what decides that, and the daily summary already defers to it.
        // An unshowable profit says so rather than printing a number.
        if (overview.showProfit)
          StatTile(
            key: const ValueKey('home-today-profit'),
            // Renamed only when a net figure stands beside it. Where no
            // spending could be read this is the only profit the home shows,
            // and calling it gross would imply a second figure that is absent.
            label: net == null ? 'Profit' : 'Gross profit',
            value: report == null || !report.isShowable
                ? '—'
                : currency.format(report.profit),
            money: report != null && report.isShowable,
            icon: Icons.trending_up,
            detail: metrics == null
                ? 'Not reconciled yet'
                : report != null && report.isShowable
                ? 'After cost of goods'
                : 'Some lines carry no cost',
          ),
        // **A second tile rather than one relabelled figure.** A tile whose
        // meaning changes with whether a read succeeded is worse than a tile
        // that is simply absent: a person who glanced at *Profit* yesterday
        // and *Profit* today would have no way to tell that one of them
        // counted the rent and the other did not.
        if (overview.showProfit && net != null)
          StatTile(
            key: const ValueKey('home-today-net-profit'),
            label: 'Net profit',
            value: net.isShowable ? currency.format(net.netProfit) : '—',
            money: net.isShowable,
            icon: Icons.account_balance_wallet_outlined,
            // A loss is the one reading this whole feature exists to make
            // possible, so it is marked rather than left to the minus sign.
            status: net.isLoss ? AppStatus.problem : null,
            statusLabel: net.isLoss ? 'Loss' : null,
            detail: metrics == null
                ? 'Not reconciled yet'
                : net.isShowable
                ? 'After cost of goods and expenses'
                : 'Some spending is not counted',
          ),
      ],
      // **Receipts waiting is not a tile, and that is a measurement rather
      // than a preference.** `printQueueStatus` answers a *sentence* -
      // `2 waiting to send` - and a tile's value slot is a figure: the
      // sentence set at the figure role was 300 pixels wide and forced the
      // whole grid into one column. The count itself is not exposed, so there
      // is no honest figure to put here. The queue keeps the toolbar badge it
      // already had and its own row in the drawer, both of which carry the
      // same sentence in a slot shaped for one.
    ];
    if (tiles.isEmpty) return null;
    // **One bar around the figures, which is the old hub's shape.** Its
    // `_StatsBar` was a single bordered panel holding every tile, not four
    // cards standing apart - so the figures read as one row of the day's
    // numbers rather than as four unrelated things. `StatRow` still lays the
    // tiles out and still does its own width arithmetic; this only supplies
    // the container it used to sit inside.
    //
    // **No drop shadow.** The old panel had a 30-blur black one;
    // `AppSurfaceRoles` is explicit that depth here is a surface step, and on
    // a near-black ground the shadow costs raster time to be invisible.
    return Padding(
      padding: EdgeInsets.only(top: tokens.spacing.s8),
      child: Container(
        // **`space.8`, not `space.16`, and the difference is a defect rather
        // than taste.** A `StatTile` already carries its own `space.16`
        // horizontal inset - `StatRow.minimumTileWidth` composes its
        // arithmetic from it - so a panel that added another 16 a side was
        // insetting every figure twice and taking 32 pixels out of the width
        // the labels were measured against. On a 360 handset that truncated
        // them to "TODAY'S S…" and "TRANSACTI…".
        padding: EdgeInsets.all(tokens.spacing.s8),
        decoration: BoxDecoration(
          color: tokens.colors.surface.raised,
          borderRadius: BorderRadius.circular(tokens.radius.lg),
          border: Border.all(color: tokens.colors.surface.borderSubtle),
        ),
        child: StatRow(tiles: tiles),
      ),
    );
  }

  // **`_startSale` was retired 2026-08-25 with the return of the old hub.**
  // *New sale* is the primary card at the head of the grid, which is where
  // the old app put the register, so a second full-width copy of it under the
  // figures would be the same destination drawn twice on one screen. The
  // argument for the full-width button, kept because it is what has to be
  // answered if anyone puts it back: the Stitch export gives *Start New Sale*
  // the width of the page because it is what the screen is for, and a till
  // behind a hamburger is a till nobody reaches in a hurry. The card grid
  // answers it — the till is not behind a hamburger any more.

  /// Everywhere this session may go from the home: the primary first, then
  /// five areas, **never alphabetically**, with the two account controls last.
  ///
  /// **The list became a menu on 2026-08-23, and only its order and its
  /// groups changed.** Every condition, every role check and every closure
  /// below is still byte-for-byte what it was when these were eleven pills in
  /// a `Wrap`. What moved: *Find a receipt* came up beside *Receipts waiting*
  /// and *View staff directory* came up beside *View activity log*, because
  /// [HomeDestination.group] draws a heading once and then joins every
  /// following row to it - so two rows of one area separated by three rows of
  /// another would print that area's heading twice. Clustering here is what
  /// keeps the headings honest; the component deliberately does not sort.
  ///
  /// **The areas are the five the redesign's shell names**, and they are the
  /// order a shop uses them in rather than the order the code grew in: the
  /// till, then *Sales*, *Inventory*, *Reports*, *Settings*, and *Business*
  /// last. *New sale* carries no group at all - it is the one primary, and it
  /// sits above every heading rather than inside one.
  ///
  /// **Nothing here decides what a role may see.** A group's heading exists
  /// only where that role was given a row that carries it, so a cashier's menu
  /// simply has no *Settings* heading rather than an empty one. The order
  /// below is what `tool/screenshots/home_navigation_test.dart` photographs.
  List<HomeDestination> _destinations(
    BuildContext context,
  ) => <HomeDestination>[
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
        label: 'Register',
        description:
            'Process sales, manage orders, and handle customer transactions.',
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
    if (receiptLookupRoute != null &&
        membership.role.canAccess(receiptLookupRoles))
      HomeDestination(
        destinationKey: const ValueKey('sales'),
        label: 'Sales',
        description:
            'View sales reports, payment breakdowns, and transaction history.',
        group: 'Sales',
        icon: Icons.bar_chart_outlined,
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
    if (returnFeedRoute != null && membership.role.canAccess(returnFeedRoles))
      HomeDestination(
        destinationKey: const ValueKey('returns'),
        label: 'Returns',
        description: 'Review pending and verified returns across every sale.',
        group: 'Sales',
        icon: Icons.assignment_return_outlined,
        onPressed: () {
          final controller = TenantSessionScope.of(context);
          Navigator.of(context).push(
            AppPageRoute<void>(
              builder: (_) => TenantSessionScope(
                controller: controller,
                child: returnFeedRoute!(reader),
              ),
            ),
          );
        },
      ),
    // In *Sales* rather than in *Settings*, and carrying no role list: a
    // receipt that did not come out is discovered by whoever is standing
    // at the counter, and the queue is this device's own. It sits under
    // the receipt lookup because both are somebody asking what happened to
    // a receipt - one that exists, and one that has not printed yet.
    if (printQueueRoute != null)
      HomeDestination(
        destinationKey: const ValueKey('receipts-waiting'),
        label: 'Unprinted receipts',
        description: 'Receipts this device has not sent to the printer yet.',
        group: 'Sales',
        icon: Icons.receipt_long_outlined,
        status: printQueueStatus?.call(),
        // The figure for the tile's badge, beside the sentence for the row.
        badgeCount: printQueueCount?.call(),
        onPressed: () {
          final controller = TenantSessionScope.of(context);
          Navigator.of(context).push(
            AppPageRoute<void>(
              builder: (_) => TenantSessionScope(
                controller: controller,
                child: printQueueRoute!(),
              ),
            ),
          );
        },
      ),
    // One inventory destination for every active member. The route derives
    // write actions from the guarded live session.
    if (catalogManagementRoute != null)
      HomeDestination(
        destinationKey: const ValueKey('inventory'),
        label: 'Inventory',
        description: 'View all products, manage SKUs, pricing, and categories.',
        group: 'Inventory',
        icon: Icons.inventory_2_outlined,
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
    // Beside Reports, because it is the other half of the same question. A
    // report says what came in and what the stock cost; this says what else
    // went out, and the two together are the only way the profit on those
    // reports is the whole story.
    if (expensesRoute != null && membership.role.canAccess(expensesRoles))
      HomeDestination(
        destinationKey: const ValueKey('expenses'),
        label: 'Expenses',
        description:
            'Record rent, wages and running costs, and see what profit is '
            'left after them.',
        group: 'Reports',
        icon: Icons.account_balance_wallet_outlined,
        onPressed: () {
          final controller = TenantSessionScope.of(context);
          Navigator.of(context).push(
            AppPageRoute<void>(
              builder: (_) => TenantSessionScope(
                controller: controller,
                child: expensesRoute!(reader),
              ),
            ),
          );
        },
      ),
    if (dailySummaryRoute != null &&
        membership.role.canAccess(dailySummaryRoles))
      HomeDestination(
        destinationKey: const ValueKey('view-daily-summary'),
        // **Renamed on 2026-08-27, and the route behind it changed with the
        // name.** The daily figures it used to open are the whole subject of
        // the Sales route, so this said the same thing twice; it now opens the
        // weekly report the old app had, which nothing else in this product
        // shows.
        label: 'Reports',
        description:
            'Weekly sales, profit and best sellers, against the week before.',
        group: 'Reports',
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
    // Beside the catalog rather than beside the till: this decides what
    // every price in that catalog means, and the person who opens it is not
    // the person standing at the till.
    if (checkoutConfigurationRoute != null &&
        membership.role.canAccess(checkoutConfigurationRoles))
      HomeDestination(
        destinationKey: const ValueKey('checkout-configuration'),
        label: 'Settings',
        description: 'Decide what every price in the catalog means.',
        group: 'Settings',
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
    // First in *Settings*, because it is the first thing a business that has
    // just been approved has to fix: until it is set the home carries no name
    // and every receipt prints an unbranded header.
    if (brandingRoute != null && membership.role.canAccess(brandingRoles))
      HomeDestination(
        destinationKey: const ValueKey('business-details'),
        label: 'Business details',
        description:
            'The name, slogan and logo the home and every receipt carry.',
        group: 'Settings',
        icon: Icons.storefront_outlined,
        onPressed: () {
          final controller = TenantSessionScope.of(context);
          Navigator.of(context).push(
            AppPageRoute<void>(
              builder: (_) => TenantSessionScope(
                controller: controller,
                child: brandingRoute!(reader),
              ),
            ),
          );
        },
      ),
    // Beside the checkout settings it sits next to in Firestore, and
    // guarded by the same roles: both decide something about the business
    // rather than about a sale, and neither is an operational act.
    if (printerConfigurationRoute != null &&
        membership.role.canAccess(printerConfigurationRoles))
      HomeDestination(
        destinationKey: const ValueKey('printer-configuration'),
        label: 'Printer',
        description: 'Choose the hardware receipts are printed on.',
        group: 'Settings',
        icon: Icons.print_outlined,
        onPressed: () {
          final controller = TenantSessionScope.of(context);
          Navigator.of(context).push(
            AppPageRoute<void>(
              builder: (_) => TenantSessionScope(
                controller: controller,
                child: printerConfigurationRoute!(reader),
              ),
            ),
          );
        },
      ),
    if (membership.role.canAccess(TenantStaffDirectoryScreen.allowedRoles))
      HomeDestination(
        destinationKey: const ValueKey('staff'),
        label: 'Staff',
        description:
            'Manage employee profiles, permissions, and access control.',
        group: 'Settings',
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
    if (auditLogRoute != null && membership.role.canAccess(auditLogRoles))
      HomeDestination(
        destinationKey: const ValueKey('view-audit-log'),
        label: 'Logs',
        group: 'Settings',
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
        group: 'Business',
        icon: Icons.swap_horiz,
        onPressed: () => _showBusinessSwitcher(context),
      ),
    if (isDefaultTenant)
      // The one disabled control on this route, and it is a state rather
      // than a refusal: this business already is the default, so there is
      // nothing to press.
      const HomeDestination(
        label: 'Default business',
        group: 'Business',
        icon: Icons.star,
        onPressed: null,
      )
    else
      HomeDestination(
        destinationKey: const ValueKey('make-default-tenant'),
        label: 'Make default',
        group: 'Business',
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
  /// Whether the server could not be reached, as opposed to refusing.
  ///
  /// **The two need different words and used to get the same ones.** A device
  /// with no signal was told "we could not open your business account", which
  /// names a fault in the account and sends a shopkeeper looking for one that
  /// does not exist. `TenantDirectoryUnavailable` reaching this screen means
  /// the opposite: the account is presumably fine and this device has simply
  /// never been online with it, so there is nothing saved here to open.
  bool get _isUnreachable => error is TenantDirectoryUnavailable;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: _isUnreachable
          ? ErrorState(
              // `attention`, not `problem`: nothing is broken and nothing is
              // lost - §2.1 reserves `problem` for a difference found or a
              // record unreadable, and this is neither.
              status: AppStatus.attention,
              badgeLabel: 'Offline',
              statement: 'This device cannot reach your business account.',
              detail:
                  'It has not been online with this account yet, so there is '
                  'nothing saved here to open.',
              stillTrue:
                  'You are still signed in. Connect once and this device will '
                  'open on its own afterwards.',
              actions: <Widget>[
                AppButton(
                  label: 'Retry',
                  tier: AppButtonTier.primary,
                  onPressed: onRetry,
                ),
                AppButton(label: 'Sign out', onPressed: onSignOut),
              ],
            )
          : ErrorState(
              badgeLabel: 'Not opened',
              statement: 'We could not open your business account.',
              detail: _safeBootstrapError(error),
              // §8 rule 6, and the reason *Sign out* is offered beside
              // *Retry*: the sign-in survived, so the failure is about the
              // account rather than about the person, and there is something
              // to retry.
              stillTrue:
                  'You are still signed in, and nothing has been changed.',
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
