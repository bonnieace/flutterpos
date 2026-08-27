/// `SkeletonGroup`, `SkeletonBlock` and `RecordListSkeleton`, per
/// `docs/stitch/OPEN_QUESTIONS.md` decision 35.
///
/// **Four of these assert properties nothing else can catch.** The delay is
/// invisible in a picture; the single ticker is invisible in a picture; reduced
/// motion looks identical to a paused sweep in a still frame; and "no group
/// above it" is a case that only arises when somebody refactors. The screenshot
/// harness photographs what these look like and none of it proves any of the
/// four.
library;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/theme.dart';
import 'package:flutter_application_1/ui/record_list.dart';
import 'package:flutter_application_1/ui/skeleton.dart';
import 'package:flutter_application_1/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final delay = AppMotion.standard.skeletonDelay.duration;

  group('a skeleton waits before it appears', () {
    testWidgets('paints nothing at all inside the threshold', (tester) async {
      // The whole reason the till stopped flashing: a Hive read resolves in a
      // frame or two, and a placeholder drawn and torn down inside that is the
      // jitter this was added to remove.
      await _pump(tester, const SkeletonBlock(height: 40));

      expect(_sweep(tester).visible, isFalse);
      expect(find.byType(DecoratedBox), findsNothing);
    });

    testWidgets('holds its space while it is invisible', (tester) async {
      // Holding the space rather than collapsing is deliberate: a scroll extent
      // that grows when the skeleton appears is the same jolt in miniature.
      await _pump(tester, const SkeletonBlock(height: 40, width: 120));

      expect(tester.getSize(find.byType(SkeletonBlock)), const Size(120, 40));
    });

    testWidgets('paints once the threshold has passed', (tester) async {
      await _pump(tester, const SkeletonBlock(height: 40));

      await tester.pump(delay);
      await tester.pump();

      expect(_sweep(tester).visible, isTrue);
      expect(find.byType(DecoratedBox), findsWidgets);
    });
  });

  group('a group owns one sweep for everything below it', () {
    testWidgets('every block reads the same animation', (tester) async {
      // One ticker per group, not one per block: a forty-tile grid with forty
      // controllers is how a cheap phone drops frames while appearing idle.
      await _pump(
        tester,
        const Column(
          children: <Widget>[
            SkeletonBlock(height: 20),
            SkeletonBlock(height: 20),
            SkeletonBlock(height: 20),
          ],
        ),
      );

      expect(find.byType(SkeletonSweep), findsOne);
      expect(find.byType(SkeletonBlock), findsNWidgets(3));
    });

    testWidgets('a block with no group above it still paints', (tester) async {
      // **The assertion is that something is drawn, not merely that nothing
      // threw.** A review found this branch returning a bare `SizedBox`, which
      // is a block that renders as empty space forever - a screen silently
      // showing nothing, which is worse than a placeholder that looks dull. An
      // exception would at least be noticed.
      await tester.pumpWidget(
        MaterialApp(
          theme: spiritTheme,
          home: const Scaffold(body: SkeletonBlock(height: 40)),
        ),
      );
      await tester.pump(delay);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byType(SkeletonBlock),
          matching: find.byType(DecoratedBox),
        ),
        findsOne,
      );
    });

    testWidgets('announces what is being read, once, for the whole region', (
      tester,
    ) async {
      // Rule 6: a shimmer says *this is loading* with movement and colour and
      // nothing else, which is exactly the signal §9 forbids leaving to colour
      // alone. The region speaks; the blocks inside it are silent.
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const Column(
          children: <Widget>[
            SkeletonBlock(height: 20),
            SkeletonBlock(height: 20),
          ],
        ),
      );
      await tester.pump(delay);
      await tester.pump();

      expect(find.bySemanticsLabel('Reading the products.'), findsOne);
      handle.dispose();
    });
  });

  group('reduced motion', () {
    testWidgets('renders flat and lets the tree settle', (tester) async {
      // §2.4's rule for every animated thing in this app, and the property that
      // keeps `pumpAndSettle` working: a loop that never ends is a test that
      // never finishes. `pumpAndSettle` returning at all is the assertion.
      await _pump(
        tester,
        const SkeletonBlock(height: 40),
        disableAnimations: true,
      );

      await tester.pump(delay);
      await tester.pumpAndSettle();

      expect(_sweep(tester).animated, isFalse);
      expect(_sweep(tester).visible, isTrue);
    });

    testWidgets('the threshold is not shortened by it', (tester) async {
      // The delay is a threshold rather than an animation: a person who has
      // turned animation off still should not see a placeholder flash for a
      // read that had already finished.
      await _pump(
        tester,
        const SkeletonBlock(height: 40),
        disableAnimations: true,
      );

      expect(_sweep(tester).visible, isFalse);
    });
  });

  group('a record placeholder takes the shape the real list will take', () {
    testWidgets('stacked cards below the medium floor', (tester) async {
      await _pumpAtWidth(tester, 400);

      expect(
        RecordList.formFor(400),
        RecordForm.stackedCards,
        reason: 'the fixture width has to be the band being asserted',
      );
      expect(find.byType(SkeletonBlock), findsNWidgets(4));
    });

    testWidgets('a table, with its header rule, at expanded', (tester) async {
      await _pumpAtWidth(tester, 1400);

      expect(RecordList.formFor(1400), RecordForm.table);
      // Four rows plus the header rule a table has and a card list does not.
      expect(find.byType(SkeletonBlock), findsNWidgets(5));
    });
  });
}

SkeletonSweep _sweep(WidgetTester tester) =>
    tester.widget<SkeletonSweep>(find.byType(SkeletonSweep));

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool disableAnimations = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      // **Copied rather than replaced.** A bare `MediaQueryData` here wipes the
      // viewport size along with everything else, and `RecordListSkeleton` asks
      // `RecordList.formFor` which band it is in - so the band under test would
      // silently become `compact` at every width.
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: disableAnimations),
          child: Scaffold(
            body: SkeletonGroup(
              semanticLabel: 'Reading the products.',
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _pumpAtWidth(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await _pump(tester, const RecordListSkeleton());
  await tester.pump(AppMotion.standard.skeletonDelay.duration);
  await tester.pump();
}
