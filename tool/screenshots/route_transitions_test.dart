/// `design.md` §6.2's two route rows, photographed **mid-flight**.
///
/// **Every other capture in this harness is of a settled frame, and these three
/// deliberately are not.** A route transition has no settled state to
/// photograph: at rest it is just the screen that arrived. What §6.2 specifies
/// is what happens in between - an incoming surface at full width, a covered one
/// parallaxed at 30%, and at expanded width neither of them moving at all - and
/// none of that exists in a picture of either end.
///
/// **This makes them the one set of images in the harness whose whole content is
/// the frame timeline**, which `PLAN.md` records as a hazard for
/// `31b-a-receipt-found`, where it is an accident. Here it is the subject: the
/// pump budget below is part of the specification of the picture, and changing
/// it changes the image on purpose. Two runs of identical code still hash
/// identically - the binding's clock is fake - so these stay attributable.
///
/// **What they still do not prove.** A photograph cannot show that a spring is
/// interruptible, and interruptibility is most of what §2.4 is asking for.
/// `test/ui/routes_test.dart` proves the handoff arithmetic; the feel of it is a
/// device check with the performance overlay on, per §10.
library;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/ui/buttons.dart';
import 'package:flutter_application_1/ui/routes.dart';
import 'package:flutter_application_1/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

/// A page with enough structure that a 30% shift is visible rather than
/// inferred.
class _Page extends StatelessWidget {
  const _Page({
    required this.title,
    required this.lines,
    this.onOpen,
  });

  final String title;
  final List<String> lines;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: EdgeInsets.all(tokens.spacing.s24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final line in lines) ...<Widget>[
              Text(line, style: tokens.typography.bodyLarge),
              SizedBox(height: tokens.spacing.s12),
            ],
            SizedBox(height: tokens.spacing.s12),
            if (onOpen != null)
              AppButton(
                key: const ValueKey('open-detail'),
                label: 'Open the record',
                tier: AppButtonTier.primary,
                onPressed: onOpen,
              ),
          ],
        ),
      ),
    );
  }
}

/// The landing surface, which pushes an [AppPageRoute] over itself.
class _Stage extends StatelessWidget {
  const _Stage();

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Shift',
    lines: const <String>[
      'Opened 08:12 by Amina',
      'Recorded sales   41',
      'Takings          KES 18,420',
      'Returns          2',
    ],
    onOpen: () => Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => const _Page(
          title: 'Sale CT-A7F-20260812-0041',
          lines: <String>[
            'Recorded 11:04 by Amina',
            'Tender           M-Pesa',
            'Lines            3',
            'Total            KES 640',
          ],
        ),
      ),
    ),
  );
}

/// Taps the trigger and stops the clock part way through the transition.
Future<void> _partWayIn(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open-detail')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 90));
}

void main() {
  screenshotCase(
    '91-route-push-compact',
    // The compact row, so the phone viewport is the one that runs it. Rendering
    // it at 1440 would photograph the fade instead and call it a slide.
    viewports: const <ScreenshotViewport>[mobileViewport],
    settle: false,
    fullPage: false,
    build: () => const _Stage(),
    afterPump: _partWayIn,
  );

  screenshotCase(
    '91-route-push-expanded',
    viewports: const <ScreenshotViewport>[webViewport],
    settle: false,
    fullPage: false,
    build: () => const _Stage(),
    afterPump: _partWayIn,
  );

  screenshotCase(
    '91-route-pop-compact',
    viewports: const <ScreenshotViewport>[mobileViewport],
    settle: false,
    fullPage: false,
    build: () => const _Stage(),
    afterPump: (tester) async {
      await tester.tap(find.byKey(const ValueKey('open-detail')));
      await tester.pumpAndSettle();
      Navigator.of(
        tester.element(find.byType(AppBar).last),
      ).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
    },
  );
}
