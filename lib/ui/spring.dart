/// The spring substrate: `design.md` §2.4's "anything spatial is a spring".
///
/// **This file exists because there were zero `AnimationController`s in the
/// migrated tree.** §2.4 splits animation in two - a duration for opacity and
/// colour, a spring for anything that moves in space - and the second half had
/// nowhere to run. `DESIGN-AUDIT.md` §6 decision 4 put the substrate in step 3
/// with `AppButton` rather than in step 2, because building springs and then
/// touching every call site twice costs a whole pass for nothing.
///
/// **The rule this file is here to make unbreakable** is §2.4's first one, which
/// `claude.md` repeats: *a spring retargets from its current position and
/// velocity; it never restarts from zero and never has to finish.* That is not
/// something a caller can be trusted to remember at each site, so [SpringDrive]
/// has no method that starts from zero. [SpringDrive.animateTo] is the only way
/// to move it, and it always reads the live value and the live velocity out of
/// the controller it is retargeting.
///
/// **`AnimationController.forward()` is deliberately not wrapped and not
/// exposed.** It is the API that would satisfy a spring-shaped call site while
/// doing the one thing §2.4 forbids.
///
/// **The `vsync` a [SpringDrive] is given comes from
/// [SingleTickerProviderStateMixin], never from a hand-rolled
/// [TickerProvider].** The hand-rolled version compiles and looks right:
/// implementing `createTicker` and returning a `Ticker` skips [TickerMode]
/// entirely, so every spring on an inactive route - a screen the navigator is
/// holding behind another one - keeps ticking, off-screen, for the life of the
/// route. The SDK mixins subscribe to the `TickerMode` notifier and mute their
/// ticker, and that is the part worth inheriting.
library;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// An interruptible spring, driving one value.
///
/// Wraps an unbounded [AnimationController] because a spring overshoots: a
/// bounded controller clamps at its bounds and the clamp, not the physics,
/// would decide what `spring.bouncy` looks like. The three damped springs do not
/// overshoot enough to notice, and the one that is supposed to would have been
/// silently flattened.
///
/// The value it drives is a **normalized 0-to-1 progress**, not the quantity a
/// widget paints. [PressSurface] runs this from 0 to 1 and lerps a scale
/// between `1.0` and `motion.pressScale` from it, rather than springing the
/// scale itself between `1.0` and `0.97`: [SpringSimulation] decides it is done
/// against [Tolerance], whose defaults are absolute, and a 0.03-wide journey
/// finishes inside the tolerance it is measured with. A 1.0-wide one does not.
final class SpringDrive {
  SpringDrive({
    required TickerProvider vsync,
    required this.spring,
    double value = 0,
  }) : _target = value,
       _controller = AnimationController.unbounded(vsync: vsync, value: value);

  /// The physics. One of the four in `design.md` §2.4, read from the token
  /// layer by the widget that owns this drive.
  final SpringDescription spring;

  final AnimationController _controller;

  double _target;

  /// The value, for a widget that rebuilds on it.
  Animation<double> get animation => _controller;

  /// Where it is now.
  double get value => _controller.value;

  /// How fast it is going, in units per second. Zero when it is at rest, which
  /// is what makes [animateTo] safe to call on a surface that is not moving.
  double get velocity => _controller.velocity;

  /// Where it is heading. Equal to [value] once it has arrived.
  double get target => _target;

  /// Whether a simulation is running.
  bool get isAnimating => _controller.isAnimating;

  /// Retargets the spring, **from wherever it is and however fast it is
  /// going**.
  ///
  /// This is the whole point of the class. A second press arriving mid-release
  /// does not restart a scale animation from 1.0; it hands the current position
  /// and the current velocity to a new simulation, so the surface reads as
  /// something with weight rather than as a video being scrubbed backwards.
  ///
  /// [immediately] is §2.4's reduced-motion clause - "springs collapse to
  /// instant" under [MediaQueryData.disableAnimations] - expressed as a
  /// parameter rather than as a [MediaQuery] read, because this class has no
  /// [BuildContext] and the widget that owns it does.
  void animateTo(double target, {bool immediately = false}) {
    _target = target;
    if (immediately) {
      _controller
        ..stop()
        ..value = target;
      return;
    }
    // Already there and at rest: starting a simulation would schedule a ticker
    // for one frame to discover the same thing.
    if (value == target && velocity == 0) return;
    _controller.animateWith(
      SpringSimulation(spring, value, target, velocity),
    );
  }

  void dispose() => _controller.dispose();
}

/// A [SpringSimulation] that finishes **exactly** where it was asked to.
///
/// [SpringSimulation] decides it is done against [Tolerance], whose defaults
/// are absolute, so the last position it reports is within `1e-3` of the end
/// rather than at it - and [AnimationController] keeps whatever the simulation
/// last reported rather than snapping. Nothing rounds it away afterwards.
///
/// **On a press that residue is invisible and on a route it is not.** A press
/// spring drives a 0-to-1 progress that a scale is lerped from, so `1e-3` of it
/// is three hundred-thousandths of a scale factor. A route transition drives a
/// whole screen across a whole screen width, so the same `1e-3` parks the
/// arrived page a fraction of a pixel off its own edge **for as long as it is
/// on screen** - and a page on a fractional offset renders every glyph on one.
///
/// **[SpringDrive] deliberately does not use this**, and the reason is
/// evidence rather than taste: the 114 screenshots were captured against the
/// plain simulation, and swapping it under them would move a set of images for
/// a difference no one can see. When a chunk has a reason to regenerate them
/// anyway, this is a safe change to make there.
final class SettlingSpringSimulation extends Simulation {
  SettlingSpringSimulation(
    SpringDescription spring,
    double start,
    double end,
    double velocity,
  ) : _spring = SpringSimulation(spring, start, end, velocity),
      _end = end;

  final SpringSimulation _spring;
  final double _end;

  @override
  double x(double time) => isDone(time) ? _end : _spring.x(time);

  @override
  double dx(double time) => isDone(time) ? 0 : _spring.dx(time);

  @override
  bool isDone(double time) => _spring.isDone(time);
}

