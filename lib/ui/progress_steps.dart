/// `AppProgressSteps`: where somebody is in a flow that has a middle.
///
/// **The gap this closes.** Signing up is three questions asked across two
/// screens with a mailbox in between, and nothing has ever said how many there
/// are or which one this is. A person who leaves for their email and comes back
/// cannot tell whether they are nearly finished or nearly starting, and the one
/// thing that would tell them - a position - was never drawn.
///
/// **Status is never the colour alone**, which is hard rule 4. A completed step
/// carries a check glyph, the current step carries a filled marker *and* the
/// only bold label, and the whole control is preceded by "Step 2 of 3" in text.
/// Turn the colour off and every one of those still reads.
///
/// **The bar is spatial, so it is a spring** and it is retargeted rather than
/// restarted: somebody who taps back and then forward again mid-slide hands the
/// current position and velocity to the next simulation, which is what
/// [SpringDrive] is for. It never runs `forward()` from zero.
library;

import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'spring.dart';
import 'tokens.dart';

/// One step's identity, as the header draws it.
@immutable
final class AppProgressStep {
  const AppProgressStep({required this.label, this.semanticLabel});

  /// The short name under the marker. Two words at most; this is a position,
  /// not an instruction.
  final String label;

  /// What a screen reader says instead, where [label] is too terse to stand
  /// alone out of context.
  final String? semanticLabel;
}

final class AppProgressSteps extends StatefulWidget {
  const AppProgressSteps({
    super.key,
    required this.steps,
    required this.currentIndex,
  });

  final List<AppProgressStep> steps;

  /// The zero-based step being answered now. Everything before it is complete.
  final int currentIndex;

  @override
  State<AppProgressSteps> createState() => _AppProgressStepsState();
}

class _AppProgressStepsState extends State<AppProgressSteps>
    with SingleTickerProviderStateMixin {
  SpringDrive? _drive;

  double get _target => widget.steps.length < 2
      ? 1
      : widget.currentIndex / (widget.steps.length - 1);

  @override
  void didUpdateWidget(covariant AppProgressSteps oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex == widget.currentIndex &&
        oldWidget.steps.length == widget.steps.length) {
      return;
    }
    _drive?.animateTo(
      _target,
      immediately: MediaQuery.maybeDisableAnimationsOf(context) ?? false,
    );
  }

  @override
  void dispose() {
    _drive?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final drive = _drive ??= SpringDrive(
      vsync: this,
      spring: tokens.motion.smooth,
      value: _target,
    );
    final total = widget.steps.length;
    final current = widget.currentIndex.clamp(0, total - 1);

    return Semantics(
      container: true,
      label: 'Step ${current + 1} of $total, '
          '${widget.steps[current].semanticLabel ?? widget.steps[current].label}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Step ${current + 1} of $total',
              style: tokens.typography.caption.copyWith(
                color: colors.text.tertiary,
              ),
            ),
            SizedBox(height: tokens.spacing.s8),
            SizedBox(
              height: tokens.spacing.s4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(tokens.radius.sm),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    ColoredBox(color: colors.surface.borderStrong),
                    AnimatedBuilder(
                      animation: drive.animation,
                      builder: (context, _) => FractionallySizedBox(
                        alignment: AlignmentDirectional.centerStart,
                        widthFactor: lerpDouble(0, 1, drive.value)!.clamp(
                          0.0,
                          1.0,
                        ),
                        child: ColoredBox(color: colors.action.focusRing.color),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: tokens.spacing.s8),
            Row(
              children: <Widget>[
                for (var index = 0; index < total; index++)
                  Expanded(
                    child: _StepLabel(
                      step: widget.steps[index],
                      done: index < current,
                      here: index == current,
                      // The first and last labels sit under the ends of the
                      // bar rather than centred in their own third, so the
                      // text lines up with the marker it names.
                      alignment: index == 0
                          ? AlignmentDirectional.centerStart
                          : index == total - 1
                          ? AlignmentDirectional.centerEnd
                          : AlignmentDirectional.center,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

final class _StepLabel extends StatelessWidget {
  const _StepLabel({
    required this.step,
    required this.done,
    required this.here,
    required this.alignment,
  });

  final AppProgressStep step;
  final bool done;
  final bool here;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final style = tokens.typography.caption.copyWith(
      color: here
          ? colors.text.primary
          : done
          ? colors.text.secondary
          : colors.text.tertiary,
      fontWeight: here ? FontWeight.w600 : FontWeight.w400,
    );
    return Align(
      alignment: alignment,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (done) ...[
            Icon(
              Icons.check_circle,
              size: tokens.typography.caption.fontSize,
              color: colors.status.ok.fg,
            ),
            SizedBox(width: tokens.spacing.s4),
          ],
          Flexible(
            child: Text(
              step.label,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
