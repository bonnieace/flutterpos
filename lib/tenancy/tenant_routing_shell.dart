import 'dart:async';

import 'package:flutter/material.dart';

import 'tenant_bootstrap.dart';
import 'tenant_branding.dart';
import 'tenant_catalog.dart';
import 'tenant_membership.dart';
import 'tenant_repository.dart';
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
    this.acceptVisibleInvitationCallable,
    this.visibleInvitationRequestIdFactory,
    this.tenantRouteBuilder,
  });

  final Stream<String?> authUidChanges;
  final TenantBootstrapService bootstrapService;
  final Future<void> Function() signOut;
  final Widget signedOut;
  final bool Function(String uid)? isEmailVerified;
  final AcceptVisibleTenantInvitationCallable? acceptVisibleInvitationCallable;
  final TenantVisibleInvitationRequestIdFactory?
  visibleInvitationRequestIdFactory;
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

  @override
  void initState() {
    super.initState();
    _subscribeToAuth();
  }

  @override
  void didUpdateWidget(covariant TenantRoutingShell oldWidget) {
    super.didUpdateWidget(oldWidget);
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

  void _retry() {
    final uid = _uid;
    if (uid == null) return;
    final token = ++_flowToken;
    _sessionController.clear();
    setState(() {
      _bootstrapResult = null;
      _membership = null;
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
          memberships: _bootstrapResult?.selection.visible ?? const [],
          onOpen: _selectTenant,
          onAccepted: _refreshAfterVisibleInvitationAcceptance,
          onRetry: _retry,
          onSignOut: _signOut,
          acceptVisibleInvitationCallable:
              widget.acceptVisibleInvitationCallable,
          visibleInvitationRequestIdFactory:
              widget.visibleInvitationRequestIdFactory,
          isCurrent: () => mounted && _uid != null && _bootstrapResult != null,
        ),
        _RoutingPhase.tenant => _buildTenantRoute(context),
        _RoutingPhase.platform => PlatformRouteUnavailable(onSignOut: _signOut),
        _RoutingPhase.failure => TenantBootstrapFailure(
          error: _error,
          onRetry: _retry,
          onSignOut: _signOut,
        ),
        _RoutingPhase.signedOut => widget.signedOut,
      },
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

  Widget _buildTenantRoute(BuildContext context) {
    final membership = _membership!;
    final builder = widget.tenantRouteBuilder;
    if (builder != null) {
      return builder(context, _sessionController, membership);
    }
    return TenantSafeLandingScreen(
      membership: membership,
      reader: FirebaseTenantDocumentReader(),
      onSignOut: _signOut,
    );
  }
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
    required this.memberships,
    required this.onOpen,
    required this.onAccepted,
    required this.onRetry,
    required this.onSignOut,
    this.acceptVisibleInvitationCallable,
    this.visibleInvitationRequestIdFactory,
    this.isCurrent,
  });

  final TenantVisibleInvitationIdentity? identity;
  final List<TenantMembership> memberships;
  final ValueChanged<TenantMembership> onOpen;
  final VoidCallback onAccepted;
  final VoidCallback onRetry;
  final Future<void> Function() onSignOut;
  final AcceptVisibleTenantInvitationCallable? acceptVisibleInvitationCallable;
  final TenantVisibleInvitationRequestIdFactory?
  visibleInvitationRequestIdFactory;
  final TenantVisibleInvitationCurrentCheck? isCurrent;

  @override
  State<TenantBusinessSelector> createState() => _TenantBusinessSelectorState();
}

final class _TenantBusinessSelectorState extends State<TenantBusinessSelector> {
  String? _acceptingTenantId;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose a business'),
        actions: [
          TextButton(
            onPressed: widget.onSignOut,
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: widget.memberships.isEmpty
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
                                onPressed: () => _toggleAcceptance(membership),
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
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
    );
  }
}

final class _EmptyBusinessList extends StatelessWidget {
  const _EmptyBusinessList({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
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
  });

  final TenantMembership membership;
  final TenantDataReader reader;
  final Future<void> Function() onSignOut;

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
            const Text('Platform administration is not available in this app.'),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onSignOut, child: const Text('Sign out')),
          ],
        ),
      ),
    ),
  );
}
