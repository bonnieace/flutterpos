import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/landing_drawer.dart';

void main() {
  testWidgets('opens the UID-local selected business', (tester) async {
    final fixture = _ShellFixture(
      memberships: [_membership('tenant-a'), _membership('tenant-b')],
      localTenantId: 'tenant-b',
    );
    await fixture.pump(tester);

    fixture.auth.add('user-a');
    await _pumpRouting(tester);

    expect(find.text('Business tenant-b'), findsOneWidget);
    expect(fixture.store.value, 'tenant-b');
    await fixture.dispose(tester);
  });

  testWidgets('opens the account default when no local choice is valid', (
    tester,
  ) async {
    final fixture = _ShellFixture(
      memberships: [_membership('tenant-a'), _membership('tenant-b')],
      profile: const RootRoutingProfile(
        accountType: RootAccountType.tenantUser,
        globalStatus: 'active',
        defaultTenantId: 'tenant-a',
      ),
    );
    await fixture.pump(tester);

    fixture.auth.add('user-a');
    await _pumpRouting(tester);

    expect(find.text('Business tenant-a'), findsOneWidget);
    expect(fixture.store.value, 'tenant-a');
    await fixture.dispose(tester);
  });

  testWidgets('opens the sole accessible business automatically', (
    tester,
  ) async {
    final fixture = _ShellFixture(memberships: [_membership('tenant-only')]);
    await fixture.pump(tester);

    fixture.auth.add('user-a');
    await _pumpRouting(tester);

    expect(find.text('Business tenant-only'), findsOneWidget);
    await fixture.dispose(tester);
  });

  testWidgets(
    'refreshes the routing profile only after making a tenant default',
    (tester) async {
      late final _ShellFixture fixture;
      final callable = _ShellDefaultCallable((tenantId) {
        fixture.gateway.profile = RootRoutingProfile(
          accountType: RootAccountType.tenantUser,
          globalStatus: 'active',
          defaultTenantId: tenantId,
        );
      });
      fixture = _ShellFixture(
        memberships: [_membership('tenant-a')],
        useDefaultRoute: true,
        setDefaultTenantCallable: callable,
      );
      await fixture.pump(tester);

      fixture.auth.add('user-a');
      await _pumpRouting(tester);
      expect(fixture.gateway.rootCalls, 1);

      await openLandingDrawer(tester);
      await tester.tap(find.byKey(const ValueKey('make-default-tenant')));
      await tester.pumpAndSettle();
      expect(fixture.gateway.rootCalls, 1);
      await tester.tap(
        find.byKey(const ValueKey('set-default-tenant-confirm')),
      );
      await _pumpRouting(tester);

      expect(callable.payloads.single, {
        'tenantId': 'tenant-a',
        'requestId': 'routing-default-request',
      });
      expect(fixture.gateway.rootCalls, 2);
      // The drawer shut itself when the destination was pressed, which is what
      // stops a panel sitting open under the route it just opened. Re-opening
      // it is how a person would check the label changed.
      await openLandingDrawer(tester);
      expect(find.text('Default business'), findsOneWidget);
      await fixture.dispose(tester);
    },
  );

  testWidgets('shows read-only pending local work on the safe landing route', (
    tester,
  ) async {
    final fixture = _ShellFixture(
      memberships: [_membership('tenant-a')],
      useDefaultRoute: true,
      pendingCheckoutPanel: const Padding(
        padding: EdgeInsets.zero,
        child: Text('Saved offline: 2'),
      ),
    );
    await fixture.pump(tester);

    fixture.auth.add('user-a');
    await _pumpRouting(tester);

    expect(find.text('Saved offline: 2'), findsOneWidget);
    await fixture.dispose(tester);
  });

  testWidgets('opens the till under the same session scope', (tester) async {
    TenantSessionController? given;
    final fixture = _ShellFixture(
      memberships: [_membership('tenant-a')],
      useDefaultRoute: true,
      checkoutRoute: (sessions) {
        given = sessions;
        return const Scaffold(body: Text('Till open'));
      },
    );
    await fixture.pump(tester);

    fixture.auth.add('user-a');
    await _pumpRouting(tester);
    await openLandingDrawer(tester);
    await tester.tap(find.byKey(const ValueKey('start-checkout')));
    await _pumpRouting(tester);

    expect(find.text('Till open'), findsOneWidget);
    // The route is handed the live controller, so a draft saved from it binds
    // to the session the shell revalidated rather than to a captured copy.
    expect(given, isNotNull);
    expect(given!.session?.tenantId, 'tenant-a');
    await fixture.dispose(tester);
  });

  // The write-capable route must never appear merely because the shell is on
  // the safe landing screen; it appears only when a till was actually injected.
  testWidgets('offers no till when the composition root supplies none', (
    tester,
  ) async {
    final fixture = _ShellFixture(
      memberships: [_membership('tenant-a')],
      useDefaultRoute: true,
    );
    await fixture.pump(tester);

    fixture.auth.add('user-a');
    await _pumpRouting(tester);

    expect(find.byKey(const ValueKey('start-checkout')), findsNothing);
    await fixture.dispose(tester);
  });

  testWidgets('shows a selector and revalidates the chosen business', (
    tester,
  ) async {
    final fixture = _ShellFixture(
      memberships: [_membership('tenant-a'), _membership('tenant-b')],
    );
    await fixture.pump(tester);

    fixture.auth.add('user-a');
    await _pumpRouting(tester);

    expect(find.text('Choose a business'), findsOneWidget);
    expect(find.text('Administrator - Accessible'), findsNWidgets(2));

    await tester.tap(find.text('Business tenant-b'));
    await _pumpRouting(tester);

    expect(find.text('Business tenant-b'), findsOneWidget);
    expect(fixture.gateway.listCalls, 2);
    expect(fixture.store.value, 'tenant-b');
    await fixture.dispose(tester);
  });

  testWidgets(
    'changes business only after safe inspection and discards stale tenant work',
    (tester) async {
      final reader = _SwitchRoutingReader();
      final fixture = _ShellFixture(
        memberships: [_membership('tenant-a'), _membership('tenant-b')],
        localTenantId: 'tenant-a',
        useDefaultRoute: true,
        tenantDataReader: reader,
      );
      await fixture.pump(tester);
      fixture.auth.add('user-a');
      await _pumpRouting(tester);

      expect(find.text('Business tenant-a'), findsOneWidget);
      expect(reader.tenantARequest, isNotNull);
      await openLandingDrawer(tester);
      await tester.tap(find.byKey(const ValueKey('change-business')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const ValueKey('switch-business-tenant-b')));
      await _pumpRouting(tester);
      await tester.pump(const Duration(milliseconds: 500));

      // **§11 step 5b made `branding.companyName` the home's title**, so once
      // tenant-b's document arrives the fallback stops being drawn at all.
      // Before this step both were on screen - `membership.tenantName` in the
      // toolbar and the company name in the panel below it - and that duplicate
      // is what §7's "title appears once" was about. The line above still
      // asserts the fallback, because tenant-a's read is deliberately left
      // hanging and a title has to say something while one is in flight.
      expect(find.text('Tenant B current'), findsOneWidget);
      expect(find.text('Business tenant-b'), findsNothing);
      expect(fixture.store.value, 'tenant-b');
      expect(fixture.gateway.listCalls, 3);

      reader.tenantARequest!.complete(
        TenantDocumentSnapshot(
          path: 'tenants/tenant-a/configuration/branding',
          data: const {'companyName': 'Tenant A stale'},
        ),
      );
      await _pumpRouting(tester);
      expect(find.text('Tenant A stale'), findsNothing);
      expect(find.text('Tenant B current'), findsOneWidget);
      await fixture.dispose(tester);
    },
  );

  testWidgets(
    'runs recovery for the selected session on startup and connectivity restoration',
    (tester) async {
      final recoveryTriggers = StreamController<Object?>();
      final recovered = <TenantSession>[];
      final fixture = _ShellFixture(
        memberships: [_membership('tenant-a')],
        tenantSessionRecoveryFactory: (controller) => (_) async {
          recovered.add(controller.requireSession());
          return null;
        },
        tenantRecoveryTriggers: recoveryTriggers.stream,
      );
      await fixture.pump(tester);
      fixture.auth.add('user-a');
      await _pumpRouting(tester);

      expect(recovered, hasLength(1));
      expect(recovered.single.tenantId, 'tenant-a');
      final startupEpoch = recovered.single.epoch;

      recoveryTriggers.add(null);
      await _pumpRouting(tester);
      expect(recovered, hasLength(2));
      expect(recovered.last.epoch, startupEpoch);

      fixture.auth.add(null);
      await _pumpRouting(tester);
      recoveryTriggers.add(null);
      await _pumpRouting(tester);
      expect(recovered, hasLength(2));
      await recoveryTriggers.close();
      await fixture.dispose(tester);
    },
  );

  testWidgets('forwards why a recovery run was asked for', (tester) async {
    // The composition root decides what each reason justifies: a sale saved at
    // the till needs submitting and must not also re-read the whole catalog.
    // The shell attaches no meaning to the event, so it must arrive verbatim.
    final recoveryTriggers = StreamController<Object?>();
    final triggers = <Object?>[];
    final fixture = _ShellFixture(
      memberships: [_membership('tenant-a')],
      tenantSessionRecoveryFactory: (controller) => (trigger) async {
        triggers.add(trigger);
        return null;
      },
      tenantRecoveryTriggers: recoveryTriggers.stream,
    );
    await fixture.pump(tester);
    fixture.auth.add('user-a');
    await _pumpRouting(tester);

    // Opening a session is the shell's own reason, and carries none.
    expect(triggers, [null]);

    const saved = Object();
    recoveryTriggers.add(saved);
    await _pumpRouting(tester);
    expect(triggers, [null, same(saved)]);

    recoveryTriggers.add(null);
    await _pumpRouting(tester);
    expect(triggers, hasLength(3));
    expect(triggers.last, isNull);

    await recoveryTriggers.close();
    await fixture.dispose(tester);
  });

  testWidgets('shows a typed blocker and retains the current business', (
    tester,
  ) async {
    final fixture = _ShellFixture(
      memberships: [_membership('tenant-a'), _membership('tenant-b')],
      localTenantId: 'tenant-a',
      useDefaultRoute: true,
      tenantSwitchStateSources: _shellSwitchSources(
        blocker: TenantSwitchBlocker.unsynchronizedCheckout,
      ),
    );
    await fixture.pump(tester);
    fixture.auth.add('user-a');
    await _pumpRouting(tester);

    await openLandingDrawer(tester);
    await tester.tap(find.byKey(const ValueKey('change-business')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('switch-business-tenant-b')));
    await _pumpRouting(tester);

    expect(
      find.text(
        'Finish or discard the unsynchronized checkout before switching.',
      ),
      findsOneWidget,
    );
    expect(find.text('Business tenant-a'), findsWidgets);
    expect(fixture.store.value, 'tenant-a');
    await fixture.dispose(tester);
  });

  testWidgets('offline target validation retains the current business', (
    tester,
  ) async {
    final fixture = _ShellFixture(
      memberships: [_membership('tenant-a'), _membership('tenant-b')],
      localTenantId: 'tenant-a',
      useDefaultRoute: true,
      tenantSwitchOnlineCheck: () async => false,
    );
    await fixture.pump(tester);
    fixture.auth.add('user-a');
    await _pumpRouting(tester);

    await openLandingDrawer(tester);
    await tester.tap(find.byKey(const ValueKey('change-business')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('switch-business-tenant-b')));
    await _pumpRouting(tester);

    expect(
      find.text('Connect to the internet so this business can be revalidated.'),
      findsOneWidget,
    );
    expect(find.text('Business tenant-a'), findsWidgets);
    expect(fixture.store.value, 'tenant-a');
    await fixture.dispose(tester);
  });

  testWidgets('failed switch persistence restores the current business', (
    tester,
  ) async {
    final fixture = _ShellFixture(
      memberships: [_membership('tenant-a'), _membership('tenant-b')],
      localTenantId: 'tenant-a',
      failSelectionWriteFor: 'tenant-b',
      useDefaultRoute: true,
    );
    await fixture.pump(tester);
    fixture.auth.add('user-a');
    await _pumpRouting(tester);

    await openLandingDrawer(tester);
    await tester.tap(find.byKey(const ValueKey('change-business')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('switch-business-tenant-b')));
    await _pumpRouting(tester);

    expect(
      find.text(
        'The business selection could not be saved. The current business remains open.',
      ),
      findsOneWidget,
    );
    expect(find.text('Business tenant-a'), findsWidgets);
    expect(fixture.store.value, 'tenant-a');
    await fixture.dispose(tester);
  });

  testWidgets('an unverified identity is offered the one way forward', (
    tester,
  ) async {
    final callable = _ShellVerificationCallable();
    final fixture = _ShellFixture(
      memberships: [],
      sendAccountVerificationCallable: callable,
      reloadIdentity: () async {},
    );
    await fixture.pump(tester);

    fixture.auth.add('user-a');
    await _pumpRouting(tester);

    // Requesting a business and accepting an invitation both require a
    // verified address, so without this panel the selector is a dead end.
    expect(find.byKey(const ValueKey('show-tenant-request')), findsNothing);
    expect(find.byKey(const ValueKey('account-verification')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('account-verification-send')));
    await tester.pump();
    await tester.pump();
    expect(callable.payloads.single, <String, Object?>{
      'requestId': 'routing-verify-request',
    });
    await fixture.dispose(tester);
  });

  testWidgets('a verified identity is never offered verification', (
    tester,
  ) async {
    final fixture = _ShellFixture(
      memberships: [],
      emailVerified: true,
      sendAccountVerificationCallable: _ShellVerificationCallable(),
      reloadIdentity: () async {},
    );
    await fixture.pump(tester);

    fixture.auth.add('user-a');
    await _pumpRouting(tester);

    expect(find.byKey(const ValueKey('account-verification')), findsNothing);
    expect(find.byKey(const ValueKey('show-tenant-request')), findsOneWidget);
    await fixture.dispose(tester);
  });

  testWidgets('without an identity reload the panel stays unreachable', (
    tester,
  ) async {
    final fixture = _ShellFixture(
      memberships: [],
      sendAccountVerificationCallable: _ShellVerificationCallable(),
    );
    await fixture.pump(tester);

    fixture.auth.add('user-a');
    await _pumpRouting(tester);

    // A "check again" that could never observe the change would be worse than
    // no action, so the composition root must supply the reload to enable it.
    expect(find.byKey(const ValueKey('account-verification')), findsNothing);
    await fixture.dispose(tester);
  });

  testWidgets(
    'requests a pending business from no-access routing without opening it',
    (tester) async {
      late final _ShellFixture fixture;
      final callable = _ShellRequestCallable((name, slug) {
        fixture.gateway.memberships.add(
          _membership(
            'tenant-requested',
            membershipStatus: MembershipStatus.active,
            tenantStatus: TenantStatus.pending,
            canAccess: false,
          ),
        );
      });
      fixture = _ShellFixture(
        memberships: [],
        emailVerified: true,
        requestTenantCallable: callable,
      );
      await fixture.pump(tester);

      fixture.auth.add('user-a');
      await _pumpRouting(tester);
      expect(find.byKey(const ValueKey('show-tenant-request')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('show-tenant-request')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('tenant-request-name')),
        '  New   Business ',
      );
      await tester.enterText(
        find.byKey(const ValueKey('tenant-request-slug')),
        ' New-Business ',
      );
      // The form scrolls now. Step 5a's page header costs this route 72
      // logical pixels of body, so at the 800 x 600 test surface the review
      // control sits below the fold of the panel's own scroll view, and a tap
      // at its centre lands on whatever is painted there instead.
      await tester.ensureVisible(
        find.byKey(const ValueKey('tenant-request-review')),
      );
      await tester.tap(find.byKey(const ValueKey('tenant-request-review')));
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey('tenant-request-confirm')),
      );
      await tester.tap(find.byKey(const ValueKey('tenant-request-confirm')));
      await _pumpRouting(tester);

      expect(callable.payloads.single, {
        'name': 'New Business',
        'slug': 'new-business',
        'requestId': 'routing-tenant-request',
      });
      expect(fixture.gateway.rootCalls, 2);
      expect(fixture.gateway.listCalls, 2);
      expect(find.text('Business tenant-requested'), findsOneWidget);
      expect(find.text('Administrator - Pending'), findsOneWidget);
      expect(fixture.openedController, isNull);
      await fixture.dispose(tester);
    },
  );

  testWidgets('shows tenant requests only to verified tenant identities', (
    tester,
  ) async {
    final unverified = _ShellFixture(memberships: []);
    await unverified.pump(tester);
    unverified.auth.add('user-a');
    await _pumpRouting(tester);
    expect(find.byKey(const ValueKey('show-tenant-request')), findsNothing);
    await unverified.dispose(tester);

    final platform = _ShellFixture(
      memberships: [],
      emailVerified: true,
      profile: const RootRoutingProfile(
        accountType: RootAccountType.platformAdmin,
        globalStatus: 'active',
      ),
    );
    await platform.pump(tester);
    platform.auth.add('platform-user');
    await _pumpRouting(tester);
    expect(find.byKey(const ValueKey('show-tenant-request')), findsNothing);
    await platform.dispose(tester);
  });

  testWidgets('gates the platform queue on both root and superAdmin claim', (
    tester,
  ) async {
    final deniedSource = _ShellPlatformDataSource();
    final denied = _ShellFixture(
      memberships: [],
      profile: const RootRoutingProfile(
        accountType: RootAccountType.platformAdmin,
        globalStatus: 'active',
      ),
      platformDataSource: deniedSource,
    );
    await denied.pump(tester);
    denied.auth.add('platform-user');
    await _pumpRouting(tester);
    expect(
      find.text('Platform administrator access is not available.'),
      findsOneWidget,
    );
    expect(deniedSource.pageCalls, 0);
    await denied.dispose(tester);

    final allowedSource = _ShellPlatformDataSource();
    final allowed = _ShellFixture(
      memberships: [],
      profile: const RootRoutingProfile(
        accountType: RootAccountType.platformAdmin,
        globalStatus: 'active',
      ),
      platformClaim: true,
      platformDataSource: allowedSource,
    );
    await allowed.pump(tester);
    allowed.auth.add('platform-user');
    await _pumpRouting(tester);
    expect(find.text('Pending business reviews'), findsOneWidget);
    expect(find.text('Routing Review Business'), findsOneWidget);
    expect(allowedSource.pageCalls, 1);
    await tester.tap(find.text('Active & suspended'));
    await tester.pumpAndSettle();
    expect(find.text('Routing Active Business'), findsOneWidget);
    expect(allowedSource.lifecycleCalls, 1);
    await tester.tap(find.text('Rejected archive'));
    await tester.pumpAndSettle();
    expect(find.text('Routing Rejected Business'), findsOneWidget);
    expect(allowedSource.archivalCalls, 1);
    await tester.tap(find.text('Global user status'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('platform-global-user-uid')),
      'routing-target-user',
    );
    await tester.tap(find.byKey(const ValueKey('platform-global-user-lookup')));
    await tester.pumpAndSettle();
    expect(find.text('Routing Target User'), findsOneWidget);
    expect(allowedSource.globalUserStaffCalls, 1);
    await allowed.dispose(tester);
  });

  testWidgets('labels every inaccessible membership state', (tester) async {
    final fixture = _ShellFixture(
      memberships: [
        _membership(
          'pending',
          membershipStatus: MembershipStatus.pending,
          canAccess: false,
        ),
        _membership(
          'inactive',
          membershipStatus: MembershipStatus.inactive,
          canAccess: false,
        ),
        _membership(
          'rejected',
          tenantStatus: TenantStatus.rejected,
          canAccess: false,
        ),
        _membership(
          'suspended',
          tenantStatus: TenantStatus.suspended,
          canAccess: false,
        ),
        _membership(
          'archived',
          tenantStatus: TenantStatus.archived,
          canAccess: false,
        ),
      ],
    );
    await fixture.pump(tester);

    fixture.auth.add('user-a');
    await _pumpRouting(tester);

    expect(find.text('Administrator - Pending'), findsOneWidget);
    expect(find.text('Administrator - Inactive'), findsOneWidget);
    expect(find.text('Administrator - Rejected'), findsOneWidget);
    expect(find.text('Administrator - Suspended'), findsOneWidget);
    expect(find.text('Administrator - Archived'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsNWidgets(5));
    await fixture.dispose(tester);
  });

  testWidgets('accepts a parsed proof link then refreshes tenant routing', (
    tester,
  ) async {
    final callable = _TokenAcceptCallable();
    final fixture = _ShellFixture(
      memberships: [
        _membership(
          'tenant-a',
          membershipStatus: MembershipStatus.pending,
          canAccess: false,
          invitationStatus: 'sent',
        ),
      ],
      invitationLink: _tokenInvitationLink(),
      acceptTenantInvitationCallable: callable,
    );
    await fixture.pump(tester);

    fixture.auth.add('user-a');
    await _pumpRouting(tester);

    expect(find.text('Business invitation'), findsOneWidget);
    expect(
      find.text('Accept invitation to Business tenant-a?'),
      findsOneWidget,
    );
    expect(find.text('Invited role: admin'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('accept-token-invitation-confirm')),
    );
    await _pumpRouting(tester);

    expect(callable.payloads.single, {
      'tenantId': 'tenant-a',
      'invitationVersion': 4,
      'invitationToken': _invitationToken,
      'requestId': 'routing-accept-request',
    });
    expect(fixture.gateway.listCalls, 2);
    expect(find.text('Choose a business'), findsOneWidget);
    await fixture.dispose(tester);
  });

  testWidgets('ignores a stale bootstrap completion after sign-out', (
    tester,
  ) async {
    final profile = Completer<RootRoutingProfile>();
    final fixture = _ShellFixture(
      memberships: [_membership('tenant-a')],
      profileFuture: profile.future,
    );
    await fixture.pump(tester);

    fixture.auth.add('user-a');
    await tester.pump();
    fixture.auth.add(null);
    await tester.pump();
    profile.complete(_activeProfile);
    await _pumpRouting(tester);

    expect(find.text('Signed out'), findsOneWidget);
    expect(fixture.openedController, isNull);
    await fixture.dispose(tester);
  });

  testWidgets('clears the selected session on an Auth UID transition', (
    tester,
  ) async {
    final fixture = _ShellFixture(memberships: [_membership('tenant-a')]);
    await fixture.pump(tester);
    fixture.auth.add('user-a');
    await _pumpRouting(tester);
    final controller = fixture.openedController!;
    expect(controller.hasSession, isTrue);

    fixture.auth.add(null);
    await _pumpRouting(tester);

    expect(controller.hasSession, isFalse);
    expect(find.text('Signed out'), findsOneWidget);
    await fixture.dispose(tester);
  });

  testWidgets('offers retry and sign-out when bootstrap fails', (tester) async {
    final fixture = _ShellFixture(
      memberships: [_membership('tenant-a')],
      rootFailures: 1,
    );
    await fixture.pump(tester);
    fixture.auth.add('user-a');
    await _pumpRouting(tester);

    expect(
      find.text('We could not open your business account.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await _pumpRouting(tester);

    expect(find.text('Business tenant-a'), findsOneWidget);
    await fixture.dispose(tester);
  });
}

Future<void> _pumpRouting(WidgetTester tester) async {
  for (var index = 0; index < 8; index++) {
    await tester.pump();
  }
}

const _activeProfile = RootRoutingProfile(
  accountType: RootAccountType.tenantUser,
  globalStatus: 'active',
);

final class _ShellFixture {
  _ShellFixture({
    required List<TenantMembership> memberships,
    RootRoutingProfile profile = _activeProfile,
    Future<RootRoutingProfile>? profileFuture,
    String? localTenantId,
    int rootFailures = 0,
    this.invitationLink,
    this.acceptTenantInvitationCallable,
    this.useDefaultRoute = false,
    this.setDefaultTenantCallable,
    this.emailVerified = false,
    this.requestTenantCallable,
    this.sendAccountVerificationCallable,
    this.reloadIdentity,
    this.platformClaim = false,
    this.platformDataSource,
    this.tenantSwitchStateSources,
    this.tenantSwitchOnlineCheck,
    this.tenantDataReader,
    this.tenantSessionRecoveryFactory,
    this.tenantRecoveryTriggers,
    this.pendingCheckoutPanel,
    this.checkoutRoute,
    String? failSelectionWriteFor,
  }) : gateway = _FakeGateway(
         memberships: memberships,
         profile: profile,
         profileFuture: profileFuture,
         rootFailures: rootFailures,
       ),
       store = _MemorySelectionStore(
         localTenantId,
         failForTenantId: failSelectionWriteFor,
       ) {
    service = TenantBootstrapService(
      rootGateway: gateway,
      directory: TenantDirectory(gateway),
      selectionStore: store,
    );
  }

  final StreamController<String?> auth = StreamController<String?>();
  final _FakeGateway gateway;
  final _MemorySelectionStore store;
  final TenantInvitationLink? invitationLink;
  final AcceptTenantInvitationCallable? acceptTenantInvitationCallable;
  final bool useDefaultRoute;
  final SetDefaultTenantCallable? setDefaultTenantCallable;
  final bool emailVerified;
  final RequestTenantCallable? requestTenantCallable;
  final SendAccountVerificationCallable? sendAccountVerificationCallable;
  final AccountVerificationReload? reloadIdentity;
  final bool platformClaim;
  final _ShellPlatformDataSource? platformDataSource;
  final List<TenantSwitchStateSource>? tenantSwitchStateSources;
  final TenantSwitchOnlineCheck? tenantSwitchOnlineCheck;
  final TenantDataReader? tenantDataReader;
  final TenantSessionRecoveryFactory? tenantSessionRecoveryFactory;
  final Stream<Object?>? tenantRecoveryTriggers;
  final Widget? pendingCheckoutPanel;
  final Widget Function(TenantSessionController sessions)? checkoutRoute;
  late final TenantBootstrapService service;
  TenantSessionController? openedController;

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: TenantRoutingShell(
        authUidChanges: auth.stream,
        bootstrapService: service,
        tenantSwitchStateSources:
            tenantSwitchStateSources ?? safeLandingTenantSwitchStateSources(),
        tenantSwitchOnlineCheck: tenantSwitchOnlineCheck ?? (() async => true),
        tenantSessionRecoveryFactory: tenantSessionRecoveryFactory,
        tenantRecoveryTriggers: tenantRecoveryTriggers,
        signOut: () async => auth.add(null),
        signedOut: const Scaffold(body: Center(child: Text('Signed out'))),
        isEmailVerified: (_) => emailVerified,
        invitationLink: invitationLink,
        acceptTenantInvitationCallable: acceptTenantInvitationCallable,
        invitationAcceptanceRequestIdFactory: () => 'routing-accept-request',
        setDefaultTenantCallable: setDefaultTenantCallable,
        defaultTenantRequestIdFactory: () => 'routing-default-request',
        requestTenantCallable: requestTenantCallable,
        tenantRequestIdFactory: () => 'routing-tenant-request',
        sendAccountVerificationCallable: sendAccountVerificationCallable,
        accountVerificationRequestIdFactory: () => 'routing-verify-request',
        reloadIdentity: reloadIdentity,
        hasPlatformSuperAdminClaim: (_) async => platformClaim,
        platformPendingTenantDataSource: platformDataSource,
        platformLifecycleTenantDataSource: platformDataSource,
        platformRejectedTenantDataSource: platformDataSource,
        platformGlobalUserDataSource: platformDataSource,
        setTenantLifecycleCallable: _ShellLifecycleCallable(),
        setGlobalUserStatusCallable: _ShellGlobalStatusCallable(),
        platformTenantReviewRequestIdFactory: () => 'routing-platform-review',
        tenantDataReader: useDefaultRoute
            ? (tenantDataReader ?? _RoutingReader())
            : null,
        pendingCheckoutPanel: pendingCheckoutPanel,
        checkoutRoute: checkoutRoute,
        tenantRouteBuilder: useDefaultRoute
            ? null
            : (context, controller, membership) {
                openedController = controller;
                return Scaffold(body: Text('Business ${membership.tenantId}'));
              },
      ),
    ),
  );

  Future<void> dispose(WidgetTester tester) async {
    await auth.close();
    await tester.pumpWidget(const SizedBox());
  }
}

final class _FakeGateway implements TenantDirectoryGateway, RootRoutingGateway {
  _FakeGateway({
    required this.memberships,
    required this.profile,
    this.profileFuture,
    this.rootFailures = 0,
  });

  final List<TenantMembership> memberships;
  RootRoutingProfile profile;
  final Future<RootRoutingProfile>? profileFuture;
  int rootFailures;
  int listCalls = 0;
  int rootCalls = 0;

  @override
  Future<RootRoutingProfile> getRootRoutingProfile(String uid) async {
    rootCalls++;
    if (rootFailures > 0) {
      rootFailures--;
      throw StateError('Temporary bootstrap failure.');
    }
    return profileFuture ?? profile;
  }

  @override
  Future<TenantListPage> listMyTenants({
    required int pageSize,
    String? cursor,
  }) async {
    listCalls++;
    return TenantListPage(items: memberships, nextCursor: null, hasMore: false);
  }
}

final class _ShellDefaultCallable implements SetDefaultTenantCallable {
  _ShellDefaultCallable(this.onCall);

  final void Function(String tenantId) onCall;
  final List<Map<String, Object?>> payloads = [];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(Map<String, Object?>.from(payload));
    final tenantId = payload['tenantId']! as String;
    onCall(tenantId);
    return {'tenantId': tenantId, 'defaultTenantId': tenantId};
  }
}

final class _ShellVerificationCallable
    implements SendAccountVerificationCallable {
  final List<Map<String, Object?>> payloads = [];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(Map<String, Object?>.from(payload));
    return <String, Object?>{'accepted': true};
  }
}

final class _ShellRequestCallable implements RequestTenantCallable {
  _ShellRequestCallable(this.onCall);

  final void Function(String name, String slug) onCall;
  final List<Map<String, Object?>> payloads = [];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(Map<String, Object?>.from(payload));
    final name = payload['name']! as String;
    final slug = payload['slug']! as String;
    onCall(name, slug);
    return {
      'tenantId': 'tenant-requested',
      'name': name,
      'slug': slug,
      'status': 'pending',
      // The provisional trading window the server opens for a self-serve
      // request. 2026-09-05 09:00 UTC.
      'provisionalUntil': 1788339600000,
    };
  }
}

final class _ShellPlatformDataSource
    implements
        PlatformPendingTenantDataSource,
        PlatformLifecycleTenantDataSource,
        PlatformRejectedTenantDataSource,
        PlatformGlobalUserDataSource {
  int pageCalls = 0;
  int lifecycleCalls = 0;
  int archivalCalls = 0;
  int globalUserStaffCalls = 0;

  @override
  Future<void> prepareExactReview(String uid) async {}

  @override
  Future<List<PlatformTenantDocument>> loadPendingTenantDocuments({
    required int limit,
    PlatformPendingTenantCursor? cursor,
  }) async {
    pageCalls++;
    if (cursor != null) return const [];
    return [
      PlatformTenantDocument(
        id: 'routing-review-tenant',
        data: {
          'name': 'Routing Review Business',
          'slug': 'routing-review-tenant',
          'ownerUid': 'routing-review-owner',
          'status': 'pending',
          'createdAt': DateTime.utc(2026, 7, 30),
        },
      ),
    ];
  }

  @override
  Future<PlatformTenantDocument?> loadRootUser(String uid) async =>
      PlatformTenantDocument(
        id: uid,
        data: {
          'email': '$uid@example.test',
          'displayName': uid == 'routing-target-user'
              ? 'Routing Target User'
              : 'Routing Owner',
          'accountType': 'tenant_user',
          'globalStatus': 'active',
          'updatedAt': DateTime.utc(2026, 7, 30),
        },
      );

  @override
  Future<List<PlatformCanonicalStaffDocument>> loadTargetStaffDocuments(
    String uid,
  ) async {
    globalUserStaffCalls++;
    return const [];
  }

  @override
  Future<List<PlatformTenantDocument>> loadOwnedTenantDocuments(
    String uid,
  ) async => const [];

  @override
  Future<PlatformTenantDocument?> loadTenant(String tenantId) async => null;

  @override
  Future<List<PlatformCanonicalStaffDocument>> loadAdministrativeStaffDocuments(
    String tenantId,
  ) async => const [];

  @override
  Future<List<PlatformTenantDocument>> loadLifecycleTenantDocuments({
    required int limit,
    PlatformLifecycleTenantCursor? cursor,
  }) async {
    lifecycleCalls++;
    if (cursor != null) return const [];
    return [
      PlatformTenantDocument(
        id: 'routing-active-tenant',
        data: {
          'name': 'Routing Active Business',
          'slug': 'routing-active-tenant',
          'ownerUid': 'routing-review-owner',
          'status': 'active',
          'updatedAt': DateTime.utc(2026, 7, 30),
        },
      ),
    ];
  }

  @override
  Future<List<PlatformTenantDocument>> loadRejectedTenantDocuments({
    required int limit,
    PlatformRejectedTenantCursor? cursor,
  }) async {
    archivalCalls++;
    if (cursor != null) return const [];
    return [
      PlatformTenantDocument(
        id: 'routing-rejected-tenant',
        data: {
          'name': 'Routing Rejected Business',
          'slug': 'routing-rejected-tenant',
          'ownerUid': 'routing-review-owner',
          'status': 'rejected',
          'updatedAt': DateTime.utc(2026, 7, 30),
        },
      ),
    ];
  }
}

final class _ShellLifecycleCallable implements SetTenantLifecycleCallable {
  @override
  Future<Object?> call(Map<String, Object?> payload) async => {
    'tenantId': payload['tenantId'],
    'previousStatus': 'pending',
    'status': payload['status'],
    'fanoutOperationId': 'routing-fanout-operation',
  };
}

final class _ShellGlobalStatusCallable implements SetGlobalUserStatusCallable {
  @override
  Future<Object?> call(Map<String, Object?> payload) async => {
    'operationId': payload['requestId'],
    'uid': payload['uid'],
    'status': 'completed',
    'targetStatus': payload['status'],
    'affectedTenantIds': <String>[],
    'attemptCount': 1,
  };
}

final class _RoutingReader implements TenantDataReader {
  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async => null;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async => const [];
}

final class _MemorySelectionStore implements TenantSelectionStore {
  _MemorySelectionStore(this.value, {this.failForTenantId});

  String? value;
  final String? failForTenantId;

  @override
  Future<String?> readLastSelectedTenant(String uid) async => value;

  @override
  Future<void> writeLastSelectedTenant(String uid, String tenantId) async {
    if (tenantId == failForTenantId) {
      throw StateError('Selection persistence failed.');
    }
    value = tenantId;
  }
}

final class _SwitchRoutingReader implements TenantDataReader {
  Completer<TenantDocumentSnapshot?>? tenantARequest;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) {
    if (path.startsWith('tenants/tenant-a/')) {
      return (tenantARequest ??= Completer<TenantDocumentSnapshot?>()).future;
    }
    return Future.value(
      TenantDocumentSnapshot(
        path: path,
        data: const {'companyName': 'Tenant B current'},
      ),
    );
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async => const [];
}

List<TenantSwitchStateSource> _shellSwitchSources({
  TenantSwitchBlocker? blocker,
}) => TenantSwitchStateArea.values
    .map(
      (area) => _ShellSwitchSource(
        area,
        blocker != null && area == TenantSwitchStateArea.checkout
            ? blocker
            : null,
      ),
    )
    .toList();

final class _ShellSwitchSource implements TenantSwitchStateSource {
  const _ShellSwitchSource(this.area, this.blocker);

  @override
  final TenantSwitchStateArea area;
  final TenantSwitchBlocker? blocker;

  @override
  Future<TenantSwitchInspection?> inspect(TenantSession session) async =>
      blocker == null
      ? TenantSwitchInspection.clean(area: area, session: session)
      : TenantSwitchInspection.blocked(
          area: area,
          session: session,
          blocker: blocker!,
        );
}

TenantMembership _membership(
  String tenantId, {
  MembershipStatus membershipStatus = MembershipStatus.active,
  TenantStatus tenantStatus = TenantStatus.active,
  bool canAccess = true,
  String? invitationStatus,
}) => TenantMembership(
  tenantId: tenantId,
  tenantName: 'Business $tenantId',
  tenantSlug: tenantId,
  role: TenantRole.admin,
  membershipStatus: membershipStatus,
  tenantStatus: tenantStatus,
  invitationStatus: invitationStatus,
  isOwner: false,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 7, 29),
  updatedAt: DateTime.utc(2026, 7, 29),
  serverCanAccess: canAccess,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);

final class _TokenAcceptCallable implements AcceptTenantInvitationCallable {
  final List<Map<String, Object?>> payloads = [];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(Map<String, Object?>.from(payload));
    return <String, Object?>{
      'tenantId': payload['tenantId'],
      'uid': 'user-a',
      'role': 'admin',
      'membershipStatus': 'active',
      'invitationStatus': 'accepted',
    };
  }
}

TenantInvitationLink _tokenInvitationLink() =>
    TenantInvitationLink.fromUriIfPresent(
      Uri.parse(
        'https://pos.example.test/invitations?tenantId=tenant-a&uid=user-a'
        '&invitationVersion=4&invitationToken=$_invitationToken',
      ),
    )!;

const _invitationToken = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
