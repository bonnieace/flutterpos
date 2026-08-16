/// `RollingNumber`'s two rows, per `claude.md` hard rule 5 — and the clearest
/// case in this repository of §10's warning that "the harness cannot see
/// motion".
///
/// **What these prove is layout, and layout is where this component's one real
/// defect was.** A roll between two figures of *different length* is wider than
/// the figure it covers — `KES 120.50` → `KES 0.00` pads to ten positions over
/// an eight-character box — and five checkout tests went red with a 57-pixel
/// `RenderFlex` overflow before the overlay was clipped. The mid-roll capture
/// is the picture of that box.
///
/// **What they do not prove is the roll**: not the spring, not the direction,
/// not that a second change retargets from where the first one was. Those are
/// `test/ui/rolling_number_test.dart` and a device.
library;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/ui/stats.dart';
import 'package:flutter_application_1/ui/tokens.dart';

import 'harness.dart';

void main() {
  screenshotCase(
    '98-rollingnumber-at-rest',
    // At rest the component is exactly the `Text` it replaced, which is the
    // property that let every existing call site keep its own assertions.
    build: () => const _Host(),
    fullPage: false,
  );

  screenshotCase(
    '98-rollingnumber-mid-roll',
    build: () => const _Host(rolls: true),
    settle: false,
    afterPump: (tester) async {
      // Far enough in for both glyphs to be on screen and neither to have
      // arrived. The exact frame is arbitrary and this image moving between
      // runs means nothing — see the library note.
      await tester.pump(const Duration(milliseconds: 60));
    },
    fullPage: false,
  );

  screenshotCase(
    '98-rollingnumber-lengthened',
    // The case that produced the overflow: the figure grows a digit, so the
    // roll is two positions wider than the box it is drawn in.
    build: () => const _Host(rolls: true, to: 'KES 1 235.00'),
    settle: false,
    afterPump: (tester) async {
      await tester.pump(const Duration(milliseconds: 60));
    },
    fullPage: false,
  );
}

final class _Host extends StatefulWidget {
  const _Host({this.rolls = false, this.to = 'KES 185.00'});

  final bool rolls;
  final String to;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  String _value = 'KES 135.00';

  @override
  void initState() {
    super.initState();
    if (!widget.rolls) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _value = widget.to);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Scaffold(
      backgroundColor: tokens.colors.surface.base,
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.s24),
          child: SizedBox(
            width: 320,
            child: StatTile(label: 'Total', value: _value, rolling: true),
          ),
        ),
      ),
    );
  }
}
