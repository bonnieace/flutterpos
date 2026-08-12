import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/theme.dart';
import 'package:flutter_application_1/ui/routes.dart';
import 'package:flutter_application_1/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

const _motion = AppMotion.standard;

/// Mounts an app whose landing route is the ordinary `MaterialPageRoute`
/// `MaterialApp.home` builds, at a chosen width.
///
/// **The width is set on the view rather than by wrapping in a `SizedBox`**,
/// because `AppPageRoute` resolves §4.1's breakpoint from the `MediaQuery`
/// above the navigator and a box inside the app would not move it.
Future<NavigatorState> _pumpApp(
  WidgetTester tester, {
  double width = 400,
  bool disableAnimations = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 800);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      // `builder` wraps the navigator, so this `MediaQuery` is above it and is
      // the one the route reads.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: disableAnimations),
        child: child!,
      ),
      home: const Scaffold(
        key: ValueKey('landing'),
        body: Center(child: Text('landing')),
      ),
    ),
  );
  return tester.state<NavigatorState>(find.byType(Navigator));
}

/// A page whose key is on the **`Scaffold`**, not on its label.
///
/// Every geometric assertion below reads `getTopLeft` off this key, and a
/// centred `Text` sits wherever the line-breaking puts it - which cost a round
/// of wrong diagnoses when a settled page read 151.25 rather than 0.
AppPageRoute<void> _page(String label) => AppPageRoute<void>(
  builder: (_) =>
      Scaffold(key: ValueKey(label), body: Center(child: Text(label))),
);

void main() {
  group('which of §6.2\'s two rows a route runs', () {
    testWidgets('a phone gets the compact row', (tester) async {
      final navigator = await _pumpApp(tester, width: 400);
      final route = _page('detail');
      navigator.push(route);
      await tester.pumpAndSettle();
      expect(route.transition, AppRouteTransition.slide);
    });

    testWidgets('a tablet gets the compact row too', (tester) async {
      // §6.2 names `compact` and `expanded` and not §4.1's third breakpoint.
      // §4.1 defines `expanded` as >= 1024, so the 768-1023 band is not it -
      // the same reading §4.3 takes when it leaves the sale on one pane at
      // medium. Asserted rather than left to inference, because it is the one
      // question §6.2 does not answer for itself.
      final navigator = await _pumpApp(tester, width: 900);
      final route = _page('detail');
      navigator.push(route);
      await tester.pumpAndSettle();
      expect(route.transition, AppRouteTransition.slide);
    });

    testWidgets('a desktop gets the expanded row', (tester) async {
      final navigator = await _pumpApp(tester, width: 1200);
      final route = _page('detail');
      navigator.push(route);
      await tester.pumpAndSettle();
      expect(route.transition, AppRouteTransition.fade);
    });

    testWidgets('exactly 1024 is expanded', (tester) async {
      final navigator = await _pumpApp(tester, width: 1024);
      final route = _page('detail');
      navigator.push(route);
      await tester.pumpAndSettle();
      expect(route.transition, AppRouteTransition.fade);
    });
  });

  group('the compact row is a spring - design.md §2.4', () {
    testWidgets('it is still travelling after motion.medium has elapsed', (
      tester,
    ) async {
      // The discriminator between a spring and a duration, and the whole reason
      // this could not be written as a `PageTransitionsBuilder`. The controller
      // is built with `transitionDuration` - `motion.medium`, 240ms - so a
      // duration-driven transition would be finished by now to the frame.
      // `spring.smooth` settles in about 460ms.
      final navigator = await _pumpApp(tester, width: 400);
      final route = _page('detail');
      navigator.push(route);
      await tester.pump();
      await tester.pump(_motion.medium.duration);
      expect(route.animation!.isCompleted, isFalse);
      expect(route.animation!.value, greaterThan(0.5));
      await tester.pumpAndSettle();
      expect(route.animation!.isCompleted, isTrue);
    });

    testWidgets('the expanded row finishes exactly on motion.medium', (
      tester,
    ) async {
      // The other half of the same discriminator: §6.2 gives the expanded row a
      // duration on purpose, because nothing in it travels, and §2.4 gives
      // opacity a duration.
      final navigator = await _pumpApp(tester, width: 1200);
      final route = _page('detail');
      navigator.push(route);
      await tester.pump();
      // One millisecond past it: an interpolation simulation is done when the
      // elapsed time is *greater* than its duration, not equal to it.
      await tester.pump(_motion.medium.duration + const Duration(milliseconds: 1));
      expect(route.animation!.isCompleted, isTrue);
    });

    testWidgets('it arrives at exactly 1, not within a tolerance of it', (
      tester,
    ) async {
      // `SettlingSpringSimulation`'s whole reason for existing. A plain
      // `SpringSimulation` stops within `Tolerance.distance` of the end and
      // `AnimationController` keeps whatever it last reported, which parks the
      // arrived page a fraction of a pixel off its own edge for as long as it
      // is on screen.
      final navigator = await _pumpApp(tester, width: 400);
      final route = _page('detail');
      navigator.push(route);
      await tester.pumpAndSettle();
      expect(route.animation!.value, 1.0);
      expect(tester.getTopLeft(find.byKey(const ValueKey('detail'))).dx, 0.0);
    });
  });

  group('a transition is interruptible - design.md §2.4', () {
    testWidgets('a pop mid-push leaves from the live position and velocity', (
      tester,
    ) async {
      final navigator = await _pumpApp(tester, width: 400);
      final route = _page('detail');
      navigator.push(route);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      final animation = route.animation!;
      expect(animation.value, greaterThan(0));
      expect(animation.value, lessThan(1));

      // The simulation the pop will be driven with, built the way
      // `TransitionRoute` builds it - **before** the controller is stopped,
      // which is what makes both figures below live rather than zero.
      final simulation = route.createSimulation(forward: false)!;
      expect(
        simulation.x(0),
        closeTo(animation.value, 1e-9),
        reason: 'it leaves from where the page actually is',
      );
      expect(
        simulation.dx(0),
        greaterThan(0),
        reason: 'it inherited the push velocity rather than starting at rest',
      );
      expect(simulation.x(5), 0.0, reason: 'and it still ends at 0');
    });

    testWidgets('the page does not jump when the pop takes over', (
      tester,
    ) async {
      final navigator = await _pumpApp(tester, width: 400);
      final route = _page('detail');
      navigator.push(route);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final before = route.animation!.value;

      navigator.pop();
      await tester.pump();
      // One frame later it is near where it was, rather than restarted from 1.
      expect((route.animation!.value - before).abs(), lessThan(0.1));

      // **And then it keeps going the way it was going for a moment**, because
      // the spring inherited the push's velocity along with its position. A
      // duration-driven reverse would have started walking back on the first
      // frame, which is the thing that reads as a video being scrubbed
      // backwards. This assertion is the one that would fail if the handoff
      // ever silently became a restart from rest.
      await tester.pump(const Duration(milliseconds: 60));
      expect(route.animation!.value, greaterThan(before));

      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('detail')), findsNothing);
    });
  });

  group('a popped route is finalized - the leak this chunk was scoped around', () {
    testWidgets('one hundred pushes and pops all complete', (tester) async {
      // `PLAN.md` predicted this would need hand-rolling, because
      // `AnimationController.animateWith` always reports direction *forward* -
      // so a simulation driven to 0 finishes `completed`, `_handleStatusChanged`
      // never sees `dismissed`, and `finalizeRoute` is never called. On Flutter
      // 3.44 `TransitionRoute` drives the pop with `animateBackWith`, which sets
      // the reverse direction. Verified rather than believed: `Route.completed`
      // resolves in `TransitionRoute.dispose`, which only runs if the navigator
      // finalized the route.
      final navigator = await _pumpApp(tester, width: 400);
      var completed = 0;
      for (var i = 0; i < 100; i++) {
        final route = _page('detail');
        unawaited(route.completed.then((_) => completed++));
        navigator.push(route);
        await tester.pumpAndSettle();
        navigator.pop();
        await tester.pumpAndSettle();
      }
      await tester.pump();
      expect(completed, 100);
      expect(find.byKey(const ValueKey('detail')), findsNothing);
      expect(find.byKey(const ValueKey('landing')), findsOneWidget);
    });

    testWidgets('a pop under the expanded row finalizes too', (tester) async {
      // The duration-driven row takes the other branch of `createSimulation`,
      // so it is worth its own pass rather than being assumed to share one.
      final navigator = await _pumpApp(tester, width: 1200);
      var completed = false;
      final route = _page('detail');
      unawaited(route.completed.then((_) => completed = true));
      navigator.push(route);
      await tester.pumpAndSettle();
      navigator.pop();
      await tester.pumpAndSettle();
      await tester.pump();
      expect(completed, isTrue);
    });

    testWidgets('a pop that interrupts its own push still finalizes', (
      tester,
    ) async {
      final navigator = await _pumpApp(tester, width: 400);
      var completed = false;
      final route = _page('detail');
      unawaited(route.completed.then((_) => completed = true));
      navigator.push(route);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      navigator.pop();
      await tester.pumpAndSettle();
      await tester.pump();
      expect(completed, isTrue);
      expect(find.byKey(const ValueKey('detail')), findsNothing);
    });
  });

  group('§2.4 reduced motion: a transition is instant', () {
    testWidgets('a push arrives on the first frame', (tester) async {
      final navigator = await _pumpApp(
        tester,
        width: 400,
        disableAnimations: true,
      );
      final route = _page('detail');
      navigator.push(route);
      await tester.pump();
      expect(route.animation!.value, 1.0);
      expect(tester.getTopLeft(find.byKey(const ValueKey('detail'))).dx, 0.0);
      await tester.pumpAndSettle();
    });

    testWidgets('a pop leaves on the first frame and finalizes', (
      tester,
    ) async {
      final navigator = await _pumpApp(
        tester,
        width: 400,
        disableAnimations: true,
      );
      var completed = false;
      final route = _page('detail');
      unawaited(route.completed.then((_) => completed = true));
      navigator.push(route);
      await tester.pumpAndSettle();
      navigator.pop();
      await tester.pump();
      expect(route.animation!.value, 0.0);
      await tester.pumpAndSettle();
      await tester.pump();
      expect(completed, isTrue);
    });

    testWidgets('the expanded row is instant too', (tester) async {
      final navigator = await _pumpApp(
        tester,
        width: 1200,
        disableAnimations: true,
      );
      final route = _page('detail');
      navigator.push(route);
      await tester.pump();
      expect(route.animation!.value, 1.0);
      await tester.pumpAndSettle();
    });
  });

  group('§6.2 route push (compact): incoming full, outgoing parallax', () {
    testWidgets('the arriving page comes from the trailing edge', (
      tester,
    ) async {
      final navigator = await _pumpApp(tester, width: 400);
      navigator.push(_page('detail'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final dx = tester.getTopLeft(find.byKey(const ValueKey('detail'))).dx;
      expect(dx, greaterThan(0));
      expect(dx, lessThan(400));
      await tester.pumpAndSettle();
    });

    testWidgets('a covered MaterialPageRoute holds still, and that is a known '
        'boundary rather than a bug', (tester) async {
      // The landing route is the `MaterialPageRoute` `MaterialApp.home` builds,
      // so eight of the twenty-three pushes cover one. Parallaxing it needs
      // `delegatedTransition`, and that re-parents the covered page through its
      // `GlobalKey`, which rebuilds it, which makes `TenantRouteGuard` reload -
      // an extra read per push. See the note in `lib/ui/routes.dart`.
      //
      // **Asserted rather than left unasserted**, so the day the coupling is
      // fixed and the delegated transition goes back in, this test fails and is
      // rewritten in the same change instead of the boundary being forgotten.
      final navigator = await _pumpApp(tester, width: 400);
      navigator.push(_page('detail'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.getTopLeft(find.byKey(const ValueKey('landing'))).dx, 0.0);
      await tester.pumpAndSettle();
    });

    testWidgets('and covering it costs no extra build of the page below', (
      tester,
    ) async {
      // The measurement behind the note above, in the form that would catch a
      // regression: the covered page is built once and stays built. When the
      // delegated transition was in, this read 2 - the second build being the
      // re-parent, and the second build being what reloaded the data.
      var builds = 0;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: spiritTheme,
          home: Builder(
            builder: (context) {
              builds++;
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      );
      expect(builds, 1);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(_page('detail'));
      await tester.pumpAndSettle();
      expect(builds, 1);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(builds, 1);
    });

    testWidgets('an AppPageRoute covering another one parallaxes it', (
      tester,
    ) async {
      final navigator = await _pumpApp(tester, width: 400);
      navigator.push(_page('first'));
      await tester.pumpAndSettle();
      navigator.push(_page('second'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('first'))).dx,
        lessThan(0),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('second'))).dx,
        greaterThan(0),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('the parallax settles at exactly §6.2\'s 30%', (tester) async {
      final navigator = await _pumpApp(tester, width: 400);
      navigator.push(_page('first'));
      await tester.pumpAndSettle();
      navigator.push(_page('second'));
      await tester.pumpAndSettle();
      expect(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('first'), skipOffstage: false),
            )
            .dx,
        closeTo(-400 * _motion.routeParallax, 0.001),
      );
    });

    testWidgets('a dialog does not move the page underneath it', (
      tester,
    ) async {
      // `PageRoute.canTransitionTo` answers `nextRoute is PageRoute`, and a
      // dialog is a `PopupRoute`. Asserted because the failure mode is loud and
      // silly - every page sliding 30% sideways when a confirmation opens.
      final navigator = await _pumpApp(tester, width: 400);
      navigator.push(_page('detail'));
      await tester.pumpAndSettle();
      final before = tester
          .getTopLeft(find.byKey(const ValueKey('detail')))
          .dx;
      unawaited(
        showDialog<void>(
          context: navigator.context,
          builder: (_) => const AlertDialog(content: Text('sure?')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('detail'))).dx,
        before,
      );
      await tester.pumpAndSettle();
    });
  });

  group('§6.2 route change (expanded): fade-through, no horizontal travel', () {
    testWidgets('nothing travels horizontally', (tester) async {
      final navigator = await _pumpApp(tester, width: 1200);
      navigator.push(_page('detail'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getTopLeft(find.byKey(const ValueKey('detail'))).dx, 0.0);
      expect(tester.getTopLeft(find.byKey(const ValueKey('landing'))).dx, 0.0);
      await tester.pumpAndSettle();
    });

    testWidgets('the arriving surface fades in', (tester) async {
      final navigator = await _pumpApp(tester, width: 1200);
      navigator.push(_page('detail'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final fade = tester.widget<FadeTransition>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('detail')),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(fade.opacity.value, greaterThan(0));
      expect(fade.opacity.value, lessThan(1));
      await tester.pumpAndSettle();
      expect(fade.opacity.value, 1.0);
    });
  });

  testWidgets('a page is a route semantics scope, as MaterialPageRoute is', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final navigator = await _pumpApp(tester, width: 400);
    navigator.push(_page('detail'));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.byKey(const ValueKey('detail'))),
      isNotNull,
    );
    final scopes = find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.scopesRoute == true,
    );
    expect(scopes, findsWidgets);
    handle.dispose();
  });
}
