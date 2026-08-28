import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/states.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('missing session fails closed without loading', (tester) async {
    final controller = TenantSessionController();
    var loadCalls = 0;

    await tester.pumpWidget(
      _guardedApp(
        controller: controller,
        guard: TenantRouteGuard<String>(
          load: (_) async {
            loadCalls++;
            return 'unexpected';
          },
          builder: (_, _, value) => Text(value),
        ),
      ),
    );

    // §5.1's `ErrorState`, which is what the guard's `denied` default became
    // on 2026-08-16. The sentence it replaces named a *tenant* to a shopkeeper,
    // which is §8 rule 1, and it carried no status at all.
    expect(find.text('You do not have access to this page.'), findsOneWidget);
    expect(find.byType(ErrorState), findsOneWidget);
    expect(loadCalls, 0);
  });

  testWidgets('wrong role fails closed without loading', (tester) async {
    final controller = TenantSessionController()
      ..open(
        uid: 'user-a',
        membership: _membership('tenant-a', role: TenantRole.cashier),
      );
    var loadCalls = 0;

    await tester.pumpWidget(
      _guardedApp(
        controller: controller,
        guard: TenantRouteGuard<String>(
          allowedRoles: const [TenantRole.admin],
          load: (_) async {
            loadCalls++;
            return 'unexpected';
          },
          builder: (_, _, value) => Text(value),
        ),
      ),
    );

    // §5.1's `ErrorState`, which is what the guard's `denied` default became
    // on 2026-08-16. The sentence it replaces named a *tenant* to a shopkeeper,
    // which is §8 rule 1, and it carried no status at all.
    expect(find.text('You do not have access to this page.'), findsOneWidget);
    expect(find.byType(ErrorState), findsOneWidget);
    expect(loadCalls, 0);
  });

  testWidgets('tenant switch rejects a stale async completion', (tester) async {
    final controller = TenantSessionController()
      ..open(uid: 'user-a', membership: _membership('tenant-a'));
    final loads = <String, Completer<String>>{};

    await tester.pumpWidget(
      _guardedApp(
        controller: controller,
        guard: TenantRouteGuard<String>(
          load: (session) {
            final completer = Completer<String>();
            loads[session.tenantId] = completer;
            return completer.future;
          },
          builder: (_, session, value) => Text('${session.tenantId}:$value'),
        ),
      ),
    );

    expect(loads.keys, contains('tenant-a'));
    controller.open(uid: 'user-a', membership: _membership('tenant-b'));
    await tester.pump();
    expect(loads.keys, contains('tenant-b'));

    loads['tenant-a']!.complete('stale');
    await tester.pump();
    expect(find.textContaining('stale'), findsNothing);

    loads['tenant-b']!.complete('current');
    await tester.pump();
    expect(find.text('tenant-b:current'), findsOneWidget);
  });

  // ------------------------------------------------------------------------
  // What this device already holds.
  //
  // **These are the whole of the offline behaviour, and every one of them is a
  // race.** Two reads are in flight at once and either can land first, so the
  // interesting cases are not "does the cache work" but *what happens when the
  // wrong one wins*. Each test below drives both completers by hand rather
  // than letting timing decide, because a suite that passes on whichever order
  // the machine happened to produce is a suite that proves nothing.
  // ------------------------------------------------------------------------

  testWidgets('what this device holds is drawn before the server answers', (
    tester,
  ) async {
    final controller = _openController();
    final server = Completer<String>();

    await tester.pumpWidget(
      _guardedApp(
        controller: controller,
        guard: TenantRouteGuard<String>(
          load: (_) => server.future,
          loadCached: (_) async => 'held',
          loading: const Text('reading'),
          builder: (context, _, value) => _Freshness(value: value),
        ),
      ),
    );

    // The spinner was on screen for one frame and then the disk answered.
    await tester.pump();
    expect(find.text('held from-cache'), findsOneWidget);
    expect(find.text('reading'), findsNothing);
    expect(server.isCompleted, isFalse, reason: 'The server is still out.');
  });

  testWidgets('the server replaces what the device held', (tester) async {
    final controller = _openController();
    final server = Completer<String>();

    await tester.pumpWidget(
      _guardedApp(
        controller: controller,
        guard: TenantRouteGuard<String>(
          load: (_) => server.future,
          loadCached: (_) async => 'held',
          builder: (context, _, value) => _Freshness(value: value),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('held from-cache'), findsOneWidget);

    server.complete('fresh');
    await tester.pump();
    expect(find.text('fresh from-server'), findsOneWidget);
  });

  testWidgets('a server value that lands first is not overwritten by a late '
      'cache read', (tester) async {
    final controller = _openController();
    final cache = Completer<String>();

    await tester.pumpWidget(
      _guardedApp(
        controller: controller,
        guard: TenantRouteGuard<String>(
          load: (_) async => 'fresh',
          loadCached: (_) => cache.future,
          builder: (context, _, value) => _Freshness(value: value),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('fresh from-server'), findsOneWidget);

    // The disk was slow. What it holds is older than what is on screen, and
    // drawing it now would walk a correct figure backwards.
    cache.complete('held');
    await tester.pump();
    expect(find.text('fresh from-server'), findsOneWidget);
    expect(find.textContaining('held'), findsNothing);
  });

  testWidgets('a server refusal over a held copy keeps the page and says so', (
    tester,
  ) async {
    final controller = _openController();
    final server = Completer<String>();

    await tester.pumpWidget(
      _guardedApp(
        controller: controller,
        guard: TenantRouteGuard<String>(
          load: (_) => server.future,
          loadCached: (_) async => 'held',
          failure: (_, _) => const Text('could not be read'),
          builder: (context, _, value) => _Freshness(value: value),
        ),
      ),
    );
    await tester.pump();

    server.completeError(StateError('offline'));
    await tester.pump();

    // The read failed; what is on screen did not stop being what this device
    // holds. The failure page would have taken the figures and the controls.
    expect(find.text('held from-cache stale'), findsOneWidget);
    expect(find.text('could not be read'), findsNothing);
  });

  testWidgets('a server refusal with nothing held still fails the page', (
    tester,
  ) async {
    final controller = _openController();

    await tester.pumpWidget(
      _guardedApp(
        controller: controller,
        guard: TenantRouteGuard<String>(
          load: (_) async => throw StateError('offline'),
          loadCached: (_) async => throw StateError('nothing here'),
          failure: (_, _) => const Text('could not be read'),
          builder: (context, _, value) => _Freshness(value: value),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('could not be read'), findsOneWidget);
  });

  testWidgets('a cache that holds nothing is never the page\'s failure', (
    tester,
  ) async {
    final controller = _openController();
    final server = Completer<String>();

    await tester.pumpWidget(
      _guardedApp(
        controller: controller,
        guard: TenantRouteGuard<String>(
          load: (_) => server.future,
          loadCached: (_) async => throw StateError('nothing here'),
          loading: const Text('reading'),
          failure: (_, _) => const Text('could not be read'),
          builder: (context, _, value) => _Freshness(value: value),
        ),
      ),
    );
    await tester.pump();

    // "Not downloaded yet" is not something to put in front of a shopkeeper.
    expect(find.text('reading'), findsOneWidget);
    expect(find.text('could not be read'), findsNothing);

    // **Two frames, and only where the page was still on its loading widget.**
    // Completing outside a pump schedules the loader's continuation behind the
    // frame this pump draws, so the `setState` it makes lands in the next one.
    // Sixteen milliseconds in a running app; two lines in a test that controls
    // its own clock.
    server.complete('fresh');
    await tester.pump();
    await tester.pump();
    expect(find.text('fresh from-server'), findsOneWidget);
  });

  testWidgets('a held copy is adopted even after the server has refused', (
    tester,
  ) async {
    final controller = _openController();
    final cache = Completer<String>();

    await tester.pumpWidget(
      _guardedApp(
        controller: controller,
        guard: TenantRouteGuard<String>(
          load: (_) async => throw StateError('offline'),
          loadCached: (_) => cache.future,
          failure: (_, _) => const Text('could not be read'),
          builder: (context, _, value) => _Freshness(value: value),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('could not be read'), findsOneWidget);

    // The network failed fast and the disk was busy. Landing on a failure page
    // first is not a reason to keep a copy back - it is the reason to show one.
    cache.complete('held');
    await tester.pump();
    expect(find.text('held from-cache stale'), findsOneWidget);
    expect(find.text('could not be read'), findsNothing);
  });

  testWidgets('a tenant switch discards a stale cached completion', (
    tester,
  ) async {
    final controller = TenantSessionController()
      ..open(uid: 'user-a', membership: _membership('tenant-a'));
    final caches = <String, Completer<String>>{};

    await tester.pumpWidget(
      _guardedApp(
        controller: controller,
        guard: TenantRouteGuard<String>(
          load: (_) => Completer<String>().future,
          loadCached: (session) {
            final completer = Completer<String>();
            caches[session.tenantId] = completer;
            return completer.future;
          },
          loading: const Text('reading'),
          builder: (context, session, value) =>
              Text('${session.tenantId}:$value'),
        ),
      ),
    );

    controller.open(uid: 'user-a', membership: _membership('tenant-b'));
    await tester.pump();

    // One business's copy is not the other's, and the cache is no more allowed
    // to cross that line than the server is.
    caches['tenant-a']!.complete('stale');
    await tester.pump();
    expect(find.textContaining('stale'), findsNothing);

    // Two frames for the reason given above: this page is still on its
    // loading widget when the copy lands.
    caches['tenant-b']!.complete('current');
    await tester.pump();
    await tester.pump();
    expect(find.text('tenant-b:current'), findsOneWidget);
  });
}

TenantSessionController _openController() => TenantSessionController()
  ..open(uid: 'user-a', membership: _membership('tenant-a'));

/// Prints the value beside where the guard says it came from, so one `find.text`
/// asserts the whole state rather than three.
final class _Freshness extends StatelessWidget {
  const _Freshness({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final freshness = TenantReadFreshness.maybeOf(context);
    final origin = freshness == null
        ? 'unknown'
        : freshness.fromCache
        ? 'from-cache'
        : 'from-server';
    final stale = freshness?.stale ?? false;
    return Text('$value $origin${stale ? ' stale' : ''}');
  }
}

Widget _guardedApp({
  required TenantSessionController controller,
  required Widget guard,
}) => MaterialApp(
  home: TenantSessionScope(
    controller: controller,
    child: Scaffold(body: guard),
  ),
);

TenantMembership _membership(
  String tenantId, {
  TenantRole role = TenantRole.admin,
}) => TenantMembership(
  tenantId: tenantId,
  tenantName: tenantId,
  tenantSlug: tenantId,
  role: role,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  isOwner: role == TenantRole.owner,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 7, 29),
  updatedAt: DateTime.utc(2026, 7, 29),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);
