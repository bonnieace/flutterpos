import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';
import 'package:uzapay_pos/ui/spring.dart';
import 'package:uzapay_pos/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

/// A ticker provider for a drive under test, with no widget above it.
class _Vsync extends StatefulWidget {
  const _Vsync({super.key, required this.onReady});

  final void Function(TickerProvider vsync) onReady;

  @override
  State<_Vsync> createState() => _VsyncState();
}

class _VsyncState extends State<_Vsync> with SingleTickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
    widget.onReady(this);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Mounts a drive and hands it to [body].
///
/// **The [UniqueKey] is load-bearing.** A second `pumpWidget` of the same
/// widget type with no key updates the existing element rather than replacing
/// it, so `initState` never runs again and `onReady` is never called - which is
/// the same trap `PLAN.md` records against `TenantRouteGuard`, and here it
/// shows up as a null drive on the second call inside one test rather than as
/// a stale answer.
Future<void> _withDrive(
  WidgetTester tester,
  SpringDescription spring,
  Future<void> Function(SpringDrive drive) body,
) async {
  SpringDrive? drive;
  await tester.pumpWidget(
    _Vsync(
      key: UniqueKey(),
      onReady: (vsync) => drive = SpringDrive(vsync: vsync, spring: spring),
    ),
  );
  try {
    await body(drive!);
  } finally {
    drive!.dispose();
  }
}

void main() {
  const motion = AppMotion.standard;

  group('a spring retargets and never restarts - design.md §2.4', () {
    testWidgets('it arrives at its target and stops', (tester) async {
      await _withDrive(tester, motion.snappy, (drive) async {
        expect(drive.value, 0);
        expect(drive.target, 0);

        drive.animateTo(1);
        expect(drive.target, 1);
        expect(drive.isAnimating, isTrue);

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(drive.value, closeTo(1, 0.01));
        expect(drive.isAnimating, isFalse);
      });
    });

    testWidgets(
      'a retarget mid-flight starts from where it is, not from zero',
      (tester) async {
        // This is §2.4's first rule and `claude.md`'s motion rule, and it is
        // the whole reason this class exists rather than an
        // `AnimationController.forward()`. The assertion is deliberately about
        // the *value at the moment of retargeting*: a `forward()`-shaped
        // implementation passes every other test in this file.
        await _withDrive(tester, motion.snappy, (drive) async {
          drive.animateTo(1);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 40));

          final caught = drive.value;
          expect(
            caught,
            greaterThan(0.05),
            reason: 'the probe has to land mid-flight or it proves nothing',
          );
          expect(caught, lessThan(0.95));

          drive.animateTo(0);
          // Not 1, and not 0: the new simulation begins at the position the
          // old one had reached.
          expect(drive.value, caught);
          expect(drive.target, 0);

          await tester.pump();
          await tester.pump(const Duration(seconds: 2));
          expect(drive.value, closeTo(0, 0.01));
        });
      },
    );

    testWidgets('and it carries its velocity across the retarget', (
      tester,
    ) async {
      // The half of interruptibility a position check cannot see. A spring
      // reversed while it is still travelling outward keeps going outward for
      // a moment, because it has momentum. An implementation that read the
      // position and dropped the velocity would turn round instantly.
      await _withDrive(tester, motion.snappy, (drive) async {
        drive.animateTo(1);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));

        final outward = drive.velocity;
        expect(outward, greaterThan(0), reason: 'still travelling outward');

        final caught = drive.value;
        drive.animateTo(0);
        expect(
          drive.velocity,
          closeTo(outward, 0.001),
          reason: 'the velocity survives the retarget',
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 8));
        expect(
          drive.value,
          greaterThan(caught),
          reason: 'momentum carries it past the point it turned at',
        );
      });
    });

    testWidgets('retargeting to where it already is does nothing at all', (
      tester,
    ) async {
      await _withDrive(tester, motion.snappy, (drive) async {
        drive.animateTo(0);
        expect(drive.isAnimating, isFalse);
        expect(drive.value, 0);
      });
    });

    testWidgets('an immediate move skips the physics, for §2.4\'s last line', (
      tester,
    ) async {
      // "Under `MediaQuery.disableAnimations`: springs collapse to instant."
      // §9 makes that pass/fail rather than a preference.
      await _withDrive(tester, motion.smooth, (drive) async {
        drive.animateTo(1, immediately: true);
        expect(drive.value, 1);
        expect(drive.isAnimating, isFalse);

        drive.animateTo(0, immediately: true);
        expect(drive.value, 0);
        expect(drive.isAnimating, isFalse);
      });
    });

    testWidgets('an immediate move stops a simulation already running', (
      tester,
    ) async {
      // The case that matters: motion is switched off *while* something is
      // moving. Setting the value without stopping the ticker leaves the
      // simulation to overwrite it on the next frame.
      await _withDrive(tester, motion.gentle, (drive) async {
        drive.animateTo(1);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        expect(drive.isAnimating, isTrue);

        drive.animateTo(1, immediately: true);
        expect(drive.isAnimating, isFalse);
        expect(drive.value, 1);

        await tester.pump(const Duration(milliseconds: 100));
        expect(drive.value, 1);
      });
    });
  });

  group('the four springs behave the way §2.4 says they do', () {
    /// The peak value a spring reaches on its way to 1.
    Future<double> peakOf(
      WidgetTester tester,
      SpringDescription spring,
    ) async {
      var peak = 0.0;
      await _withDrive(tester, spring, (drive) async {
        drive.animateTo(1);
        await tester.pump();
        for (var frame = 0; frame < 240; frame++) {
          await tester.pump(const Duration(milliseconds: 8));
          if (drive.value > peak) peak = drive.value;
        }
      });
      return peak;
    }

    test('two of the operational three are damped past critical, and snappy '
        'is not', () {
      // **Measured rather than assumed, and it corrects a reading of §2.4.**
      // That section says "All are critically or near-critically damped except
      // `spring.bouncy`", which is true of `smooth` and `gentle` - both are a
      // shade *past* critical - and generous about `snappy`, whose damping
      // ratio is 0.82. The figures are asserted here so the word
      // "near-critically" cannot quietly cover a different spring later.
      double zeta(SpringDescription s) =>
          s.damping / (2 * math.sqrt(s.stiffness * s.mass));

      expect(zeta(motion.snappy), closeTo(0.821, 0.001));
      expect(zeta(motion.smooth), closeTo(1.012, 0.001));
      expect(zeta(motion.gentle), closeTo(1.014, 0.001));
      expect(zeta(motion.bouncy), closeTo(0.558, 0.001));
    });

    testWidgets('so the operational springs settle without a visible bounce', (
      tester,
    ) async {
      // What §2.4 is actually protecting: "Overshoot is a reward signal; on an
      // operational surface it reads as instability."
      //
      // `snappy`'s 0.82 damping ratio does overshoot, by **1.1%** of the
      // journey, and that is not instability at the size it is used: a press
      // travels from scale 1.0 to 0.97, so 1.1% of it is 0.0003 of scale -
      // three ten-thousandths, on a 48px button, for one frame. `smooth` and
      // `gentle` do not overshoot at all.
      expect(await peakOf(tester, motion.snappy), closeTo(1.011, 0.005));
      expect(await peakOf(tester, motion.smooth), lessThanOrEqualTo(1.0005));
      expect(await peakOf(tester, motion.gentle), lessThanOrEqualTo(1.0005));
    });

    testWidgets('and spring.bouncy overshoots by an order of magnitude more', (
      tester,
    ) async {
      // Which is the distinction §6.2 rests on. A reward layer that bounced as
      // little as `snappy` does would not read as a reward at all.
      final bouncy = await peakOf(tester, motion.bouncy);
      expect(bouncy, greaterThan(1.10));
      expect(bouncy, greaterThan(await peakOf(tester, motion.snappy) + 0.1));
    });

    testWidgets('snappy settles faster than smooth, which settles faster than '
        'gentle', (tester) async {
      final settled = <String, int>{};
      for (final entry in <String, SpringDescription>{
        'snappy': motion.snappy,
        'smooth': motion.smooth,
        'gentle': motion.gentle,
      }.entries) {
        await _withDrive(tester, entry.value, (drive) async {
          drive.animateTo(1);
          await tester.pump();
          var frames = 0;
          while (drive.isAnimating && frames < 600) {
            await tester.pump(const Duration(milliseconds: 16));
            frames++;
          }
          settled[entry.key] = frames;
        });
      }
      expect(settled['snappy']!, lessThan(settled['smooth']!));
      expect(settled['smooth']!, lessThan(settled['gentle']!));
    });
  });

  group('a settling spring ends where it was asked to', () {
    /// The first time a simulation reports itself done, to the millisecond.
    double doneAt(Simulation simulation) {
      for (var ms = 0; ms < 5000; ms++) {
        if (simulation.isDone(ms / 1000)) return ms / 1000;
      }
      return double.nan;
    }

    test('a plain SpringSimulation stops short of its end', () {
      // The defect this class exists for, measured rather than asserted in
      // prose: `SpringSimulation` is done when it is within
      // `Tolerance.distance` of the end, and it reports that near-miss as its
      // position. On a route that is a whole page parked off its own edge.
      final plain = SpringSimulation(motion.smooth, 0, 1, 0);
      final at = doneAt(plain);
      expect(at, isNot(isNaN));
      expect(plain.x(at), isNot(1.0));
      expect(plain.x(at), closeTo(1.0, 1e-3));
    });

    test('the settling one reports the end exactly', () {
      final settling = SettlingSpringSimulation(motion.smooth, 0, 1, 0);
      final at = doneAt(settling);
      expect(at, isNot(isNaN));
      expect(settling.x(at), 1.0);
      expect(settling.dx(at), 0.0);
      // And it is still the same spring everywhere before that.
      expect(settling.x(at * 10), 1.0);
    });

    test('it agrees with the plain simulation while both are still moving', () {
      // The wrapper must not become a second set of physics. Every frame up to
      // the last one is the spring `design.md` §2.4 specifies, unchanged.
      final plain = SpringSimulation(motion.smooth, 0, 1, 0);
      final settling = SettlingSpringSimulation(motion.smooth, 0, 1, 0);
      final stops = doneAt(settling);
      for (var ms = 0; ms < (stops * 1000).floor(); ms += 8) {
        final t = ms / 1000;
        expect(settling.x(t), plain.x(t), reason: 'position at ${t}s');
        expect(settling.dx(t), plain.dx(t), reason: 'velocity at ${t}s');
      }
    });

    test('it settles at 0 as exactly as it settles at 1', () {
      // The pop direction, which is the one where a residue would be a page
      // that never quite leaves.
      final settling = SettlingSpringSimulation(motion.smooth, 1, 0, 0);
      expect(settling.x(doneAt(settling)), 0.0);
    });

    test('a velocity it inherits still carries it', () {
      // Interruptibility is the whole point of the substrate, and it is worth
      // one assertion that wrapping the simulation did not quietly drop the
      // initial velocity on the floor.
      final settling = SettlingSpringSimulation(motion.smooth, 0.4, 0, 2.5);
      expect(settling.x(0), closeTo(0.4, 1e-9));
      expect(settling.dx(0), closeTo(2.5, 1e-9));
      expect(settling.x(0.02), greaterThan(0.4), reason: 'momentum carries on');
      expect(settling.x(doneAt(settling)), 0.0);
    });
  });
}
