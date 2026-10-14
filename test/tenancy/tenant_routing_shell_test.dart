import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/landing_drawer.dart';
import 'support/platform_console_memory.dart';

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

  testWidgets('coming back to the app re-reads the open session', (
    tester,
  ) async {
    // **M1.** A role change or a deactivation reaches this device through no
    // channel of its own: `listMyTenants` is a callable rather than a document,
    // and a deactivated member loses the right to read the record that says so.
    // What the app can do is ask again when somebody picks their phone back up.
    TenantSessionController? sessions;
    final fixture = _ShellFixture(
      memberships: [_membership('tenant-only')],
      tenantSessionRecoveryFactory: (controller) {
        sessions = controller;
        return (_) async => null;
      },
    );
    await fixture.pump(tester);

    fixture.auth.add('user-a');
    await _pumpRouting(tester);
    final settledCalls = fixture.gateway.listCalls;
    final settledEpoch = sessions!.session!.epoch;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    // The refresh is debounced by a second before it is asked for at all.
    await tester.pump(const Duration(seconds: 2));
    await _pumpRouting(tester);

    expect(fixture.gateway.listCalls, greaterThan(settledCalls));
    // **And it cost nothing on screen.** The access decision came back
    // unchanged, so the session kept its epoch - no guard re-read, no form
    // mid-submit told its own result was stale. This is what makes refreshing
    // on every resume a reasonable thing to do at all.
    expect(sessions!.session!.epoch, settledEpoch);
    expect(find.text('Business tenant-only'), findsOneWidget);
    await fixture.dispose(tester);
  });

  testWidgets('losing access hands over what the device still holds', (
    tester,
  ) async {
    // **M5.** A sale is durable in this device's outbox before it reaches the
    // server, and every path that would send it stops the moment the membership
    // ends - the workers require a session that can access the business, and
    // `allow create` requires `activeStaff` in any case. So the money was taken
    // and the only record is on a phone nobody can act through.
    //
    // The one opening is here: the refresh that discovers the deactivation came
    // back *from the server*, so the connection is real, and the identity the
    // work needs is still in hand until the session is cleared.
    final handedOver = <String>[];
    TenantSession? sessionAtHandover;
    TenantSessionController? sessions;
    final fixture = _ShellFixture(
      memberships: [_membership('tenant-only')],
      tenantSessionRecoveryFactory: (controller) {
        sessions = controller;
        return (_) async => null;
      },
      onTenantAccessLost: (uid, tenantId) async {
        handedOver.add('$uid:$tenantId');
        // Recorded rather than asserted here: a failed expectation inside this
        // callback would be swallowed by the shell's own guard and read as the
        // callback never running at all.
        sessionAtHandover = sessions!.session;
      },
    );
    await fixture.pump(tester);

    fixture.auth.add('user-a');
    await _pumpRouting(tester);
    expect(sessions!.session, isNotNull);

    // Somebody deactivated this member while the app was in the background.
    // The membership is still listed and simply cannot be accessed, which is
    // what a deactivation looks like from here.
    fixture.gateway.memberships[0] = _membership(
      'tenant-only',
      membershipStatus: MembershipStatus.inactive,
      canAccess: false,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 2));
    await _pumpRouting(tester);

    expect(handedOver, <String>['user-a:tenant-only']);
    // **The session is still open when the hand-over runs**, which is the whole
    // reason the hook sits before the clear rather than after it: clearing is
    // what takes away the identity the work needs.
    expect(sessionAtHandover, isNotNull);
    // And the till is gone all the same: handing work over is not a reason to
    // keep a sellable screen for a business this person cannot sell for.
    expect(sessions!.session, isNull);
    await fixture.dispose(tester);
  });

  testWidgets('a hand-over that fails still shuts the till down', (
    tester,
  ) async {
    TenantSessionController? sessions;
    final fixture = _ShellFixture(
      memberships: [_membership('tenant-only')],
      tenantSessionRecoveryFactory: (controller) {
        sessions = controller;
        return (_) async => null;
      },
      onTenantAccessLost: (_, _) async => throw StateError('no connection'),
    );
    await fixture.pump(tester);

    fixture.auth.add('user-a');
    await _pumpRouting(tester);

    fixture.gateway.memberships[0] = _membership(
      'tenant-only',
      membershipStatus: MembershipStatus.inactive,
      canAccess: false,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 2));
    await _pumpRouting(tester);

    expect(sessions!.session, isNull);
    await fixture.dispose(tester);
  });

  testWidgets('a demotion made elsewhere reaches a live session on resume', (
    tester,
  ) async {
    // The half that has to actually work: somebody else changed this member's
    // role while the app was in the background, and the re-read on resume is
    // where the app finds out. Here the epoch *must* advance - every guard and
    // every form holding a result from the old session has to be told.
    TenantSessionController? sessions;
    final fixture = _ShellFixture(
      memberships: [_membership('tenant-only')],
      tenantSessionRecoveryFactory: (controller) {
        sessions = controller;
        return (_) async => null;
      },
    );
    await fixture.pump(tester);

    fixture.auth.add('user-a');
    await _pumpRouting(tester);
    final settledEpoch = sessions!.session!.epoch;
    expect(sessions!.session!.role, TenantRole.admin);

    fixture.gateway.memberships[0] = _membership(
      'tenant-only',
      role: TenantRole.cashier,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 2));
    await _pumpRouting(tester);

    expect(sessions!.session!.role, TenantRole.cashier);
    expect(sessions!.session!.epoch, greaterThan(settledEpoch));
    await fixture.dispose(tester);
  });

  testWidgets(
    'opens cached tenant before a degraded network answers and then refreshes',
    (tester) async {
      final liveProfile = Completer<RootRoutingProfile>();
      final cachedAt = DateTime.utc(2026, 8, 30, 9);
      final fixture = _ShellFixture(
        memberships: [_membership('tenant-a')],
        localTenantId: 'tenant-a',
        profileFuture: liveProfile.future,
        rootCache: _MemoryRootCache(
          CachedRootRoutingProfile(profile: _activeProfile, cachedAt: cachedAt),
        ),
        directoryCache: _MemoryDirectoryCache(
          CachedTenantDirectory(
            memberships: [_membership('tenant-a')],
            cachedAt: cachedAt,
          ),
        ),
      );
      await fixture.pump(tester);

      fixture.auth.add('user-a');
      await _pumpRouting(tester);

      expect(find.text('Business tenant-a'), findsOneWidget);
      // **Silent while the answer is outstanding.** The till is drawn from the
      // device, which is the whole point of the cache-first open - but the
      // network has not been asked yet, so there is nothing truthful to say
      // about it. This used to announce an outage here, on every cold start,
      // and take it back a second later.
      expect(
        find.byKey(const ValueKey('offline-bootstrap-banner')),
        findsNothing,
      );
      expect(fixture.gateway.rootCalls, 1);
      expect(fixture.gateway.listCalls, 0);

      liveProfile.complete(_activeProfile);
      await _pumpRouting(tester);

      expect(fixture.gateway.listCalls, 1);
      expect(
        find.byKey(const ValueKey('offline-bootstrap-banner')),
        findsNothing,
      );
      expect(find.text('Business tenant-a'), findsOneWidget);
      await fixture.dispose(tester);
    },
  );

  testWidgets('says it is working from saved data once the refresh fails', (
    tester,
  ) async {
    // **The other half of the same rule.** Silence is right while the answer is
    // outstanding; it would be wrong once the answer is in. A refusal leaves
    // the cached result standing, and that is the one case the sentence was
    // written for - a person settling a drawer is owed the knowledge that the
    // figures in front of them came off this phone.
    final liveProfile = Completer<RootRoutingProfile>();
    final cachedAt = DateTime.utc(2026, 8, 30, 9);
    final fixture = _ShellFixture(
      memberships: [_membership('tenant-a')],
      localTenantId: 'tenant-a',
      profileFuture: liveProfile.future,
      rootCache: _MemoryRootCache(
        CachedRootRoutingProfile(profile: _activeProfile, cachedAt: cachedAt),
      ),
      directoryCache: _MemoryDirectoryCache(
        CachedTenantDirectory(
          memberships: [_membership('tenant-a')],
          cachedAt: cachedAt,
        ),
      ),
    );
    await fixture.pump(tester);

    fixture.auth.add('user-a');
    await _pumpRouting(tester);

    expect(
      find.byKey(const ValueKey('offline-bootstrap-banner')),
      findsNothing,
    );

    liveProfile.completeError(const TenantBootstrapUnavailable('unavailable'));
    await _pumpRouting(tester);

    expect(
      find.byKey(const ValueKey('offline-bootstrap-banner')),
      findsOneWidget,
    );
    // The till is still open on the cached business: a refused refresh reports
    // where the data came from, it does not take the shop off the air.
    expect(find.text('Business tenant-a'), findsOneWidget);
    await fixture.dispose(tester);
  });

  testWidgets('the offline card sits under the page, not over it', (
    tester,
  ) async {
    // **Moved on 2026-09-03.** It was the first thing in the column, above the
    // app bar, so a standing condition pushed every screen down and sat where
    // the business's own name belongs.
    // **Offline is a refusal, not a silence.** This fixture used to hand the
    // shell a future that never completed, which is *no answer yet* rather
    // than *no network* - and the card is now owed only once the network has
    // actually been asked and has failed.
    final liveProfile = Completer<RootRoutingProfile>();
    final fixture = _ShellFixture(
      memberships: [_membership('tenant-a')],
      localTenantId: 'tenant-a',
      profileFuture: liveProfile.future,
      rootCache: _MemoryRootCache(
        CachedRootRoutingProfile(
          profile: _activeProfile,
          cachedAt: DateTime.utc(2026, 8, 30, 9),
        ),
      ),
      directoryCache: _MemoryDirectoryCache(
        CachedTenantDirectory(
          memberships: [_membership('tenant-a')],
          cachedAt: DateTime.utc(2026, 8, 30, 9),
        ),
      ),
    );
    await fixture.pump(tester);
    fixture.auth.add('user-a');
    await _pumpRouting(tester);
    liveProfile.completeError(const TenantBootstrapUnavailable('unavailable'));
    await _pumpRouting(tester);

    final card = find.byKey(const ValueKey('offline-bootstrap-banner'));
    expect(card, findsOneWidget);
    expect(
      tester.getRect(card).top,
      greaterThan(tester.getRect(find.text('Business tenant-a')).bottom),
      reason: 'the card is a footnote about the data, not a header over it',
    );
    await fixture.dispose(tester);
  });

  testWidgets('the offline card clears once the device is back on a network', (
    tester,
  ) async {
    // `fromCache` was decided once at bootstrap and never revisited, so a
    // device that started up with no signal said *Working from data saved on
    // this device* for the rest of the session.
    final reconnects = StreamController<Object?>.broadcast();
    addTearDown(reconnects.close);
    final liveProfile = Completer<RootRoutingProfile>();
    final fixture = _ShellFixture(
      memberships: [_membership('tenant-a')],
      localTenantId: 'tenant-a',
      profileFuture: liveProfile.future,
      reconnectSignals: reconnects.stream,
      rootCache: _MemoryRootCache(
        CachedRootRoutingProfile(
          profile: _activeProfile,
          cachedAt: DateTime.utc(2026, 8, 30, 9),
        ),
      ),
      directoryCache: _MemoryDirectoryCache(
        CachedTenantDirectory(
          memberships: [_membership('tenant-a')],
          cachedAt: DateTime.utc(2026, 8, 30, 9),
        ),
      ),
    );
    await fixture.pump(tester);
    fixture.auth.add('user-a');
    await _pumpRouting(tester);

    // The first ask fails, which is what earns the card in the first place.
    liveProfile.completeError(const TenantBootstrapUnavailable('unavailable'));
    await _pumpRouting(tester);

    final card = find.byKey(const ValueKey('offline-bootstrap-banner'));
    expect(card, findsOneWidget);

    // The radio comes back, and the refresh the reconnect asks for is what
    // replaces the cached bootstrap with a live one.
    fixture.gateway.profileFuture = null;
    fixture.gateway.profile = _activeProfile;
    reconnects.add(null);
    await _pumpRouting(tester);

    expect(card, findsNothing);
    expect(find.text('Business tenant-a'), findsOneWidget);
    await fixture.dispose(tester);
  });

  testWidgets(
    'a launch refresh that runs out its deadline leaves the card up until '
    'the network changes',
    (tester) async {
      // **What a connected phone showed on 2026-09-28, on Wi-Fi and on 4G.**
      // The users read at launch did not answer inside the gateway's 8 seconds
      // - Firestore was waiting on an App Check token, which Play Integrity
      // took 10-15 seconds to refuse - so the gateway reported
      // `deadline-exceeded`, the cached bootstrap stood, and the card said the
      // device was offline while it was not. Nothing asks the server again on
      // its own: the card stays until a connectivity change, which is why
      // switching networks in either direction looked like the fix.
      //
      // This pins the shell's half of that as it stands. A retry while the
      // cached bootstrap is up would change the middle expectation, and would
      // be a decision of its own.
      final reconnects = StreamController<Object?>.broadcast();
      addTearDown(reconnects.close);
      final launchRead = Completer<RootRoutingProfile>();
      final fixture = _ShellFixture(
        memberships: [_membership('tenant-a')],
        localTenantId: 'tenant-a',
        profileFuture: launchRead.future,
        reconnectSignals: reconnects.stream,
        rootCache: _MemoryRootCache(
          CachedRootRoutingProfile(
            profile: _activeProfile,
            cachedAt: DateTime.utc(2026, 9, 28, 13),
          ),
        ),
        directoryCache: _MemoryDirectoryCache(
          CachedTenantDirectory(
            memberships: [_membership('tenant-a')],
            cachedAt: DateTime.utc(2026, 9, 28, 13),
          ),
        ),
      );
      await fixture.pump(tester);
      fixture.auth.add('user-a');
      await _pumpRouting(tester);

      final card = find.byKey(const ValueKey('offline-bootstrap-banner'));
      expect(card, findsNothing, reason: 'nothing to say while it is asking');

      // The gateway's own deadline, as `FirebaseTenantGateway` reports it.
      launchRead.completeError(
        const TenantBootstrapUnavailable('deadline-exceeded'),
      );
      await _pumpRouting(tester);
      expect(card, findsOneWidget);
      expect(fixture.gateway.rootCalls, 1);

      // A minute later, with a network that has been working all along, the
      // card is still up and the server has not been asked again.
      fixture.gateway.profileFuture = null;
      fixture.gateway.profile = _activeProfile;
      await tester.pump(const Duration(minutes: 1));
      await _pumpRouting(tester);
      expect(card, findsOneWidget);
      expect(fixture.gateway.rootCalls, 1);

      // Any connectivity change asks again, and a read that answers clears it.
      reconnects.add(null);
      await _pumpRouting(tester);
      expect(fixture.gateway.rootCalls, 2);
      expect(card, findsNothing);
      await fixture.dispose(tester);
    },
  );

  testWidgets('the offline card belongs to the home and to nothing else', (
    tester,
  ) async {
    // **The arrangement is what guarantees it, so the arrangement is what is
    // asserted.** The card is drawn by the shell, and the shell is
    // `MaterialApp.home` - every destination is a push on the root
    // `Navigator`, which sits above it. A pushed page therefore covers the
    // card completely, and no destination carries one of its own.
    final liveProfile = Completer<RootRoutingProfile>();
    final fixture = _ShellFixture(
      memberships: [_membership('tenant-a')],
      localTenantId: 'tenant-a',
      profileFuture: liveProfile.future,
      rootCache: _MemoryRootCache(
        CachedRootRoutingProfile(
          profile: _activeProfile,
          cachedAt: DateTime.utc(2026, 8, 30, 9),
        ),
      ),
      directoryCache: _MemoryDirectoryCache(
        CachedTenantDirectory(
          memberships: [_membership('tenant-a')],
          cachedAt: DateTime.utc(2026, 8, 30, 9),
        ),
      ),
    );
    await fixture.pump(tester);
    fixture.auth.add('user-a');
    await _pumpRouting(tester);
    // Earned by a refusal, as everywhere else.
    liveProfile.completeError(const TenantBootstrapUnavailable('unavailable'));
    await _pumpRouting(tester);
    expect(find.byKey(const ValueKey('offline-bootstrap-banner')), findsOne);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Center(child: Text('Pushed'))),
        ),
      ),
    );
    await _pumpRouting(tester);

    expect(find.text('Pushed'), findsOneWidget);
    // Still exactly one, and it belongs to the shell rather than to the page:
    // no destination carries a card of its own, so the one on screen is the
    // home's and the pushed route is drawn over it.
    final banner = find.byKey(const ValueKey('offline-bootstrap-banner'));
    expect(banner, findsOneWidget);
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('Pushed'),
          matching: find.byType(Scaffold),
        ),
        matching: banner,
      ),
      findsNothing,
    );
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
        // **Two businesses, because the default control moved into the
        // business switcher on 2026-09-16** and the switcher only opens where
        // there is somewhere else to go. A default is only worth setting when
        // there is more than one to choose between, so that is the same
        // condition rather than an extra one.
        memberships: [_membership('tenant-a'), _membership('tenant-b')],
        // Remembered locally, so the run opens tenant-a rather than stopping
        // at the selector - which is what two businesses and no default yet
        // would otherwise do.
        localTenantId: 'tenant-a',
        useDefaultRoute: true,
        setDefaultTenantCallable: callable,
      );
      await fixture.pump(tester);

      fixture.auth.add('user-a');
      await _pumpRouting(tester);
      expect(fixture.gateway.rootCalls, 1);

      await openLandingDrawer(tester);
      await tester.tap(find.byKey(const ValueKey('screen-title-action')));
      await tester.pumpAndSettle();
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
      // **And the offer withdraws itself.** This business is the default now,
      // so the switcher has nothing left to ask about it - which is the same
      // fact the grid used to state with a disabled *Default business* tile,
      // read from where the control actually lives.
      await openLandingDrawer(tester);
      await tester.tap(find.byKey(const ValueKey('screen-title-action')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('make-default-tenant')), findsNothing);
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
    // Each membership is a business card: the role as its fact, and an
    // Open action because both can be opened.
    expect(find.text('Administrator'), findsNWidgets(2));
    expect(find.text('Open this business'), findsNWidgets(2));

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
      await tester.tap(find.byKey(const ValueKey('screen-title-action')));
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
      // Startup reuses the directory projection it already loaded; switching
      // performs the only second authoritative directory read.
      expect(fixture.gateway.listCalls, 2);

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
    await tester.tap(find.byKey(const ValueKey('screen-title-action')));
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
    await tester.tap(find.byKey(const ValueKey('screen-title-action')));
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
    await tester.tap(find.byKey(const ValueKey('screen-title-action')));
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

  testWidgets('an account with no business is taken through signing up', (
    tester,
  ) async {
    // **The selector is not where signing up happens any more.** It used to be
    // the one screen an unverified identity could reach, so the verification
    // card was drawn on it - on a screen about choosing between businesses, to
    // somebody who has none. An account with no membership and no invitation
    // has not finished signing up, and goes to the flow that finishes it.
    final fixture = _ShellFixture(
      memberships: [],
      sendAccountVerificationCallable: _ShellVerificationCallable(),
      reloadIdentity: () async {},
    );
    await fixture.pump(tester);

    fixture.auth.add('user-a');
    await _pumpRouting(tester);

    expect(find.byKey(const ValueKey('routing-onboarding')), findsOneWidget);
    // This profile has no name, so the flow asks for one before anything else.
    expect(
      find.byKey(const ValueKey('onboarding-account-step')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('account-verification')), findsNothing);
    expect(find.byKey(const ValueKey('show-tenant-request')), findsNothing);
    await fixture.dispose(tester);
  });

  testWidgets(
    'a business created above the shell is opened without a relaunch',
    (tester) async {
      // **The bug behind *Almost there* after opening for business.** The
      // sign-in screen pushes its own copy of the wizard over this shell, so
      // when that copy creates the tenant the shell knows nothing about it:
      // the Auth UID never changed, `_handleAuthUid` returns early on the same
      // one, and popping the wizard revealed the shell exactly as it resolved
      // before the tenant existed. Only a relaunch fixed it, which is how the
      // remote state was proved right all along.
      final memberships = <TenantMembership>[];
      final refreshes = StreamController<Object?>.broadcast();
      addTearDown(refreshes.close);
      final fixture = _ShellFixture(
        memberships: memberships,
        sendAccountVerificationCallable: _ShellVerificationCallable(),
        reloadIdentity: () async {},
        bootstrapRefreshRequests: refreshes.stream,
      );
      await fixture.pump(tester);

      fixture.auth.add('user-a');
      await _pumpRouting(tester);
      expect(find.byKey(const ValueKey('routing-onboarding')), findsOneWidget);
      expect(find.text('Business tenant-a'), findsNothing);

      // What the pushed wizard's `requestTenant` did on the server, and could
      // not tell this shell about.
      memberships.add(_membership('tenant-a'));
      refreshes.add(const TenantBusinessCreatedRefreshRequest());
      await _pumpRouting(tester);

      expect(find.text('Business tenant-a'), findsOneWidget);
      expect(find.byKey(const ValueKey('routing-onboarding')), findsNothing);
      await fixture.dispose(tester);
    },
  );

  testWidgets('a refresh request before any identity does nothing', (
    tester,
  ) async {
    // The signal is a broadcast stream the composition root owns for the life
    // of the app, so it outlives every sign-in. Asking with nobody signed in
    // must not bootstrap a null UID.
    final refreshes = StreamController<Object?>.broadcast();
    addTearDown(refreshes.close);
    final fixture = _ShellFixture(
      memberships: [_membership('tenant-a')],
      bootstrapRefreshRequests: refreshes.stream,
    );
    await fixture.pump(tester);

    refreshes.add(const TenantBusinessCreatedRefreshRequest());
    await _pumpRouting(tester);
    expect(fixture.gateway.rootCalls, 0);

    fixture.auth.add('user-a');
    await _pumpRouting(tester);
    expect(find.text('Business tenant-a'), findsOneWidget);
    await fixture.dispose(tester);
  });

  testWidgets('a named but unverified account waits on the verify step', (
    tester,
  ) async {
    final fixture = _ShellFixture(
      memberships: [],
      profile: _signedUpProfile,
      sendAccountVerificationCallable: _ShellVerificationCallable(),
      reloadIdentity: () async {},
    );
    await fixture.pump(tester);

    fixture.auth.add('user-a');
    await _pumpRouting(tester);

    expect(
      find.byKey(const ValueKey('onboarding-verify-step')),
      findsOneWidget,
    );
    // Nothing was pressed to get here and nothing needs to be: the first email
    // was enqueued by `completeSelfSignup`.
    expect(
      find.byKey(const ValueKey('onboarding-verify-resend')),
      findsOneWidget,
    );
    await fixture.dispose(tester);
  });

  testWidgets('a verified account with no business is asked to create one', (
    tester,
  ) async {
    final fixture = _ShellFixture(
      memberships: [],
      profile: _signedUpProfile,
      emailVerified: true,
      reloadIdentity: () async {},
      // The form builds its own Firebase callable when none is supplied, and
      // there is no Firebase in a widget test.
      requestTenantCallable: _ShellRequestCallable((_, _) {}),
    );
    await fixture.pump(tester);

    fixture.auth.add('user-a');
    await _pumpRouting(tester);

    expect(
      find.byKey(const ValueKey('onboarding-business-step')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('tenant-request-name')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('tenant-request-currency')),
      findsOneWidget,
    );
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

  testWidgets('creates an active business from onboarding without opening it', (
    tester,
  ) async {
    late final _ShellFixture fixture;
    final callable = _ShellRequestCallable((name, slug) {
      fixture.gateway.memberships.add(
        _membership(
          'tenant-requested',
          membershipStatus: MembershipStatus.active,
        ),
      );
    });
    fixture = _ShellFixture(
      memberships: [],
      profile: _signedUpProfile,
      emailVerified: true,
      reloadIdentity: () async {},
      requestTenantCallable: callable,
    );
    await fixture.pump(tester);

    fixture.auth.add('user-a');
    await _pumpRouting(tester);
    expect(
      find.byKey(const ValueKey('onboarding-business-step')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('tenant-request-name')),
      '  New   Business ',
    );
    // The step scrolls, so a tap at a control's centre would otherwise land
    // on whatever is painted at that point instead.
    await tester.ensureVisible(
      find.byKey(const ValueKey('tenant-request-submit')),
    );
    await tester.tap(find.byKey(const ValueKey('tenant-request-submit')));
    await _pumpRouting(tester);

    final payload = callable.payloads.single;
    expect(payload['name'], 'New Business');
    expect(payload['requestId'], 'routing-tenant-request');
    // The currency the select offers first, published at
    // `configuration/checkout` by the same transaction that creates the
    // business - so a new till can price a sale before anybody opens
    // Settings.
    expect(payload['currency'], 'KES');
    // The slug is the name plus a random suffix, so its shape is what can be
    // asserted, not its value. The exact derivation is pinned in
    // `tenant_request_test.dart`.
    expect(payload['slug'], matches(RegExp(r'^new-business-[0-9a-f]{6}$')));
    expect(payload.keys.toSet(), <String>{
      'name',
      'slug',
      'currency',
      'requestId',
    });

    // The flow ends on a statement rather than dropping somebody back onto a
    // list of one, and nothing has been opened yet.
    expect(
      find.byKey(const ValueKey('onboarding-complete-step')),
      findsOneWidget,
    );
    expect(fixture.openedController, isNull);

    // **And it opens.** A business is active from the moment it is created,
    // so the till is available immediately rather than after somebody has
    // approved the request - which is the whole of what this change was for.
    await tester.tap(find.byKey(const ValueKey('onboarding-open-business')));
    await _pumpRouting(tester);

    expect(find.text('Business tenant-requested'), findsOneWidget);
    expect(fixture.openedController, isNotNull);
    await fixture.dispose(tester);
  });

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

  testWidgets('gates the platform console on both root and superAdmin claim', (
    tester,
  ) async {
    MemoryPlatformConsoleDataSource console() =>
        MemoryPlatformConsoleDataSource(<String, Map<String, Object?>>{
          'users/platform-user': <String, Object?>{
            'email': 'platform@example.test',
            'displayName': 'Platform User',
            'accountType': 'platform_admin',
            'globalStatus': 'active',
            'createdAt': DateTime.utc(2026, 7, 1),
          },
          'users/routing-target-user': <String, Object?>{
            'email': 'routing-target-user@example.test',
            'displayName': 'Routing Target User',
            'accountType': 'tenant_user',
            'globalStatus': 'active',
            'membershipCount': 0,
            'ownedTenantCount': 0,
            'createdAt': DateTime.utc(2026, 7, 30),
          },
          'tenants/routing-active-tenant': <String, Object?>{
            'name': 'Routing Active Business',
            'slug': 'routing-active-tenant',
            'ownerUid': 'routing-target-user',
            'status': 'active',
            'createdAt': DateTime.utc(2026, 7, 30),
            'updatedAt': DateTime.utc(2026, 7, 30),
          },
        });
    final deniedConsole = console();
    final denied = _ShellFixture(
      memberships: [],
      profile: const RootRoutingProfile(
        accountType: RootAccountType.platformAdmin,
        globalStatus: 'active',
      ),
      platformDataSource: _ShellPlatformDataSource(),
      platformConsoleSource: deniedConsole,
    );
    await denied.pump(tester);
    denied.auth.add('platform-user');
    await _pumpRouting(tester);
    expect(
      find.text('Platform administrator access is not available.'),
      findsOneWidget,
    );
    expect(deniedConsole.queries, isEmpty);
    expect(deniedConsole.counts, 0);
    await denied.dispose(tester);

    final allowedConsole = console();
    final allowed = _ShellFixture(
      memberships: [],
      profile: const RootRoutingProfile(
        accountType: RootAccountType.platformAdmin,
        globalStatus: 'active',
      ),
      platformClaim: true,
      platformDataSource: _ShellPlatformDataSource(),
      platformConsoleSource: allowedConsole,
    );
    await allowed.pump(tester);
    allowed.auth.add('platform-user');
    await _pumpRouting(tester);
    expect(find.byKey(const ValueKey('platform-bottom-nav')), findsOneWidget);
    expect(find.byKey(const ValueKey('platform-tile-trading')), findsOneWidget);
    expect(allowedConsole.counts, greaterThan(0));
    await tester.tap(find.byKey(const ValueKey('platform-nav-businesses')));
    await tester.pumpAndSettle();
    expect(find.text('Routing Active Business'), findsOneWidget);
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

    // The standing is the card's status line, in My businesses' words.
    expect(find.textContaining('Invited'), findsOneWidget);
    expect(find.textContaining('Deactivated'), findsOneWidget);
    expect(find.textContaining('Suspended'), findsOneWidget);
    expect(find.textContaining('Archived'), findsOneWidget);
    expect(find.text('Administrator'), findsNWidgets(4));
    // None of them can be opened, so none offers to.
    expect(find.text('Open this business'), findsNothing);
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

  testWidgets('an invitation followed while the app is up reaches the shell', (
    tester,
  ) async {
    // The arrival Android delivers to a running `singleTop` activity. Before
    // the launch link had anywhere to arrive at all this was unreachable, and
    // the only invitation the shell could see was one passed at construction.
    final fixture = _ShellFixture(
      memberships: [
        _membership(
          'tenant-a',
          membershipStatus: MembershipStatus.pending,
          canAccess: false,
          invitationStatus: 'sent',
        ),
      ],
      acceptTenantInvitationCallable: _TokenAcceptCallable(),
    );
    await fixture.pump(tester);

    fixture.auth.add('user-a');
    await _pumpRouting(tester);
    expect(find.text('Business invitation'), findsNothing);

    fixture.invitations.add(
      TenantInvitationArrival.valid(_tokenInvitationLink()),
    );
    await _pumpRouting(tester);

    expect(find.text('Business invitation'), findsOneWidget);
    expect(
      find.text('Accept invitation to Business tenant-a?'),
      findsOneWidget,
    );
    await fixture.dispose(tester);
  });

  testWidgets('a malformed arrival says so rather than being dropped', (
    tester,
  ) async {
    final fixture = _ShellFixture(memberships: [_membership('tenant-a')]);
    await fixture.pump(tester);

    fixture.auth.add('user-a');
    await _pumpRouting(tester);

    fixture.invitations.add(const TenantInvitationArrival.invalid());
    await _pumpRouting(tester);

    expect(
      find.textContaining('This invitation link is invalid or incomplete.'),
      findsOneWidget,
    );
    await fixture.dispose(tester);
  });

  testWidgets('dismissing an invitation reports it settled', (tester) async {
    // What stops the sign-in screen saying an invitation is waiting once it is
    // not. The composition root owns that sentence and cannot see this state.
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
      acceptTenantInvitationCallable: _TokenAcceptCallable(),
    );
    await fixture.pump(tester);

    fixture.auth.add('user-a');
    await _pumpRouting(tester);
    expect(fixture.settled, 0);

    await tester.tap(find.text('Not now'));
    await _pumpRouting(tester);

    expect(fixture.settled, 1);
    await fixture.dispose(tester);
  });

  testWidgets('an unverified invitee is offered verification on the list', (
    tester,
  ) async {
    // The second lockout, and the narrower one: an account that started signing
    // up and never verified has a visible membership the moment it is invited,
    // so the shell keeps it out of `OnboardingFlow` - and the selector had
    // stopped offering the verification its invitation is waiting on.
    final fixture = _ShellFixture(
      memberships: [
        _membership(
          'tenant-a',
          membershipStatus: MembershipStatus.pending,
          canAccess: false,
          invitationStatus: 'sent',
        ),
      ],
      profile: _signedUpProfile,
      emailVerified: false,
      sendAccountVerificationCallable: _ShellVerificationCallable(),
      reloadIdentity: () async {},
    );
    await fixture.pump(tester);

    fixture.auth.add('user-a');
    await _pumpRouting(tester);

    expect(find.byKey(const ValueKey('account-verification')), findsOneWidget);
    await fixture.dispose(tester);
  });

  testWidgets('somebody merely choosing between businesses is not asked', (
    tester,
  ) async {
    // The reason the panel is conditioned on an open invitation rather than on
    // an unverified address: this account has nothing waiting on verification,
    // and a card about their email would be about something else.
    final fixture = _ShellFixture(
      memberships: [_membership('tenant-a'), _membership('tenant-b')],
      profile: _signedUpProfile,
      emailVerified: false,
      reloadIdentity: () async {},
    );
    await fixture.pump(tester);

    fixture.auth.add('user-a');
    await _pumpRouting(tester);

    expect(find.text('Choose a business'), findsOneWidget);
    expect(find.byKey(const ValueKey('account-verification')), findsNothing);
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

/// An account that answered the first onboarding step and stopped.
///
/// The onboarding route reads the name and the phone off the root profile, so
/// the difference between this and [_activeProfile] is the difference between
/// somebody who has to be asked who they are and somebody who does not.
const _signedUpProfile = RootRoutingProfile(
  accountType: RootAccountType.tenantUser,
  globalStatus: 'active',
  displayName: 'Boniface Masota',
  phone: '+255712345678',
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
    this.platformConsoleSource,
    this.tenantSwitchStateSources,
    this.tenantSwitchOnlineCheck,
    this.tenantDataReader,
    this.tenantSessionRecoveryFactory,
    this.tenantRecoveryTriggers,
    this.onTenantAccessLost,
    this.bootstrapRefreshRequests,
    this.pendingCheckoutPanel,
    this.checkoutRoute,
    this.reconnectSignals,
    String? failSelectionWriteFor,
    RootRoutingProfileCache rootCache = const NullRootRoutingProfileCache(),
    TenantDirectoryCache directoryCache = const NullTenantDirectoryCache(),
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
      rootCache: rootCache,
      directory: TenantDirectory(gateway, cache: directoryCache),
      selectionStore: store,
    );
  }

  final StreamController<String?> auth = StreamController<String?>();

  /// Invitations followed while the app is already up, which is what an App
  /// Link delivers to a running activity.
  final StreamController<TenantInvitationArrival> invitations =
      StreamController<TenantInvitationArrival>.broadcast();

  /// How often the shell reported the pending invitation done with.
  int settled = 0;
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
  final MemoryPlatformConsoleDataSource? platformConsoleSource;
  final List<TenantSwitchStateSource>? tenantSwitchStateSources;
  final TenantSwitchOnlineCheck? tenantSwitchOnlineCheck;
  final TenantDataReader? tenantDataReader;
  final TenantSessionRecoveryFactory? tenantSessionRecoveryFactory;
  final Stream<Object?>? tenantRecoveryTriggers;
  final Future<void> Function(String uid, String tenantId)? onTenantAccessLost;
  final Stream<Object?>? bootstrapRefreshRequests;
  final Widget? pendingCheckoutPanel;
  final Widget Function(TenantSessionController sessions)? checkoutRoute;
  final Stream<Object?>? reconnectSignals;
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
        onTenantAccessLost: onTenantAccessLost,
        bootstrapRefreshRequests: bootstrapRefreshRequests,
        signOut: () async => auth.add(null),
        signedOut: const Scaffold(body: Center(child: Text('Signed out'))),
        isEmailVerified: (_) => emailVerified,
        invitationLink: invitationLink,
        invitationArrivals: invitations.stream,
        onInvitationLinkSettled: () => settled++,
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
        platformConsoleDataSource: platformConsoleSource,
        platformGlobalUserDataSource: platformDataSource,
        setTenantLifecycleCallable: _ShellLifecycleCallable(),
        setGlobalUserStatusCallable: _ShellGlobalStatusCallable(),
        platformTenantReviewRequestIdFactory: () => 'routing-platform-review',
        tenantDataReader: useDefaultRoute
            ? (tenantDataReader ?? _RoutingReader())
            : null,
        pendingCheckoutPanel: pendingCheckoutPanel,
        checkoutRoute: checkoutRoute,
        reconnectSignals: reconnectSignals,
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
    await invitations.close();
    await tester.pumpWidget(const SizedBox());
  }
}

final class _MemoryRootCache implements RootRoutingProfileCache {
  _MemoryRootCache(this.value);

  CachedRootRoutingProfile? value;

  @override
  Future<CachedRootRoutingProfile?> read(String uid) async => value;

  @override
  Future<void> write(String uid, RootRoutingProfile profile) async {
    value = CachedRootRoutingProfile(
      profile: profile,
      cachedAt: DateTime.now().toUtc(),
    );
  }
}

final class _MemoryDirectoryCache implements TenantDirectoryCache {
  _MemoryDirectoryCache(this.value);

  CachedTenantDirectory? value;

  @override
  Future<CachedTenantDirectory?> read(String uid) async => value;

  @override
  Future<void> write(String uid, Iterable<TenantMembership> memberships) async {
    value = CachedTenantDirectory(
      memberships: List<TenantMembership>.from(memberships),
      cachedAt: DateTime.now().toUtc(),
    );
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

  /// The answer the next root read gives, or null to answer from [profile].
  ///
  /// **Mutable, so a test can let the radio come back.** A device that is
  /// offline and then is not gives one answer and then a different one; a
  /// gateway pinned to a single future can only ever be one or the other,
  /// which cannot express the case the offline card exists for.
  Future<RootRoutingProfile>? profileFuture;
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
      'currency': payload['currency']! as String,
      'status': 'active',
    };
  }
}

final class _ShellPlatformDataSource
    implements PlatformLifecycleTenantDataSource, PlatformGlobalUserDataSource {
  int lifecycleCalls = 0;
  int globalUserStaffCalls = 0;

  @override
  Future<void> prepareExactReview(String uid) async {}

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
}

final class _ShellLifecycleCallable implements SetTenantLifecycleCallable {
  @override
  Future<Object?> call(Map<String, Object?> payload) async => {
    'tenantId': payload['tenantId'],
    'previousStatus': 'active',
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
  TenantRole role = TenantRole.admin,
}) => TenantMembership(
  tenantId: tenantId,
  tenantName: 'Business $tenantId',
  tenantSlug: tenantId,
  role: role,
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
