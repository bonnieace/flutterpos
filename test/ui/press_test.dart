import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uzapay_pos/theme.dart';
import 'package:uzapay_pos/ui/press.dart';
import 'package:uzapay_pos/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

final AppTokens _tokens = spiritTheme.extension<AppTokens>()!;
final AppFocusRing _ring = _tokens.colors.action.focusRing;

/// A press surface under the app's own theme.
Widget _surface({
  VoidCallback? onPressed,
  Color? hover,
  Color? pressed,
  bool autofocus = false,
  FocusNode? focusNode,
  Size? minimumTapTarget,
  bool repeatsWhileHeld = false,
}) => MaterialApp(
  theme: spiritTheme,
  home: Scaffold(
    body: Center(
      child: PressSurface(
        borderRadius: BorderRadius.circular(_tokens.radius.pill),
        onPressed: onPressed,
        hoverOverlay: hover,
        pressedOverlay: pressed,
        autofocus: autofocus,
        focusNode: focusNode,
        minimumTapTarget: minimumTapTarget,
        repeatsWhileHeld: repeatsWhileHeld,
        semanticLabel: 'Press me',
        child: const SizedBox(
          key: ValueKey('press-child'),
          width: 120,
          height: 48,
        ),
      ),
    ),
  ),
);

/// The scale the press spring currently holds, read off the widget tree rather
/// than off the controller - which is what a person actually sees.
///
/// **Read from the matrix's x column, not from `getMaxScaleOnAxis`.** That
/// method takes the largest scale across all three axes, and `Transform.scale`
/// leaves **z at 1.0**, so it answers 1.0 for every press this widget can
/// perform and would have reported a completely static button as correct.
double _scaleOf(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find.descendant(
      of: find.byType(PressSurface),
      matching: find.byType(Transform),
    ),
  );
  return transform.transform.storage[0];
}

bool _hasTransform(WidgetTester tester) => find
    .descendant(of: find.byType(PressSurface), matching: find.byType(Transform))
    .evaluate()
    .isNotEmpty;

/// Every [DecoratedBox] the surface draws, for finding the overlay or the ring.
Iterable<BoxDecoration> _decorations(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(
      find.descendant(
        of: find.byType(PressSurface),
        matching: find.byType(DecoratedBox),
      ),
    )
    .map((box) => box.decoration)
    .whereType<BoxDecoration>();

bool _paints(WidgetTester tester, Color color) =>
    _decorations(tester).any((d) => d.color == color);

bool _hasRing(WidgetTester tester) => _decorations(tester).any(
  (d) =>
      d.border?.top.color == _ring.color && d.border?.top.width == _ring.width,
);

void main() {
  const hover = Color(0x14FFFFFF);
  const pressed = Color(0x1FFFFFFF);

  group('a press scales on a spring - design.md §2.4', () {
    testWidgets('it starts unscaled and never builds a Transform until '
        'something happens', (tester) async {
      // The spring is created on first press rather than on first build, so a
      // screen full of buttons nobody has touched holds no tickers at all.
      await tester.pumpWidget(_surface(onPressed: () {}));
      expect(_hasTransform(tester), isFalse);
    });

    testWidgets(
      'a press drives the scale toward 0.97 and a release returns it',
      (tester) async {
        await tester.pumpWidget(_surface(onPressed: () {}, pressed: pressed));

        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(PressSurface)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(_scaleOf(tester), closeTo(_tokens.motion.pressScale, 0.002));
        expect(_tokens.motion.pressScale, 0.97);

        await gesture.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(_scaleOf(tester), closeTo(1, 0.002));
      },
    );

    testWidgets(
      'a second press takes over mid-release rather than restarting',
      (tester) async {
        // §2.4: "If a person taps twice, the second tap takes over mid-flight."
        // A `forward()`-from-zero implementation would jump the scale back to 1
        // here, which is the visible symptom of the rule `claude.md` names.
        await tester.pumpWidget(_surface(onPressed: () {}, pressed: pressed));
        final centre = tester.getCenter(find.byType(PressSurface));

        final first = await tester.startGesture(centre);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await first.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 30));

        final midRelease = _scaleOf(tester);
        expect(midRelease, greaterThan(_tokens.motion.pressScale));
        expect(midRelease, lessThan(1));

        final second = await tester.startGesture(centre);
        await tester.pump();
        expect(
          _scaleOf(tester),
          closeTo(midRelease, 0.01),
          reason: 'the second press begins where the release had got to',
        );
        await second.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      },
    );

    testWidgets('and under disableAnimations it arrives without a journey', (
      tester,
    ) async {
      // §2.4's last line and §9's Motion row, which is pass/fail.
      await tester.pumpWidget(
        MaterialApp(
          theme: spiritTheme,
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: Center(
                child: PressSurface(
                  borderRadius: BorderRadius.circular(_tokens.radius.pill),
                  onPressed: () {},
                  pressedOverlay: pressed,
                  child: const SizedBox(width: 120, height: 48),
                ),
              ),
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PressSurface)),
      );
      await tester.pump();
      expect(_scaleOf(tester), _tokens.motion.pressScale);
      await gesture.up();
      await tester.pump();
      expect(_scaleOf(tester), 1);
    });

    testWidgets('a disabled surface does not move at all', (tester) async {
      await tester.pumpWidget(_surface(pressed: pressed));
      await tester.tap(find.byType(PressSurface), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 250));
      expect(_hasTransform(tester), isFalse);
    });
  });

  group('the state overlays are §2.1\'s rows and nothing else', () {
    testWidgets('hover paints the hover fill', (tester) async {
      await tester.pumpWidget(_surface(onPressed: () {}, hover: hover));
      expect(_paints(tester, hover), isFalse);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byType(PressSurface)));
      await tester.pump();

      expect(_paints(tester, hover), isTrue);
    });

    testWidgets('pressed supersedes hover', (tester) async {
      await tester.pumpWidget(
        _surface(onPressed: () {}, hover: hover, pressed: pressed),
      );
      final centre = tester.getCenter(find.byType(PressSurface));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(centre);
      await tester.pump();

      final gesture = await tester.startGesture(centre);
      await tester.pump();
      expect(_paints(tester, pressed), isTrue);
      expect(_paints(tester, hover), isFalse);

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('a disabled surface paints neither', (tester) async {
      await tester.pumpWidget(_surface(hover: hover, pressed: pressed));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byType(PressSurface)));
      await tester.pump();
      expect(_paints(tester, hover), isFalse);
      expect(_paints(tester, pressed), isFalse);
    });
  });

  group('the focus ring is §9\'s, and §9 is pass/fail', () {
    testWidgets('it is 2px mint at a 2px offset when focus is visible', (
      tester,
    ) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );

      await tester.pumpWidget(_surface(onPressed: () {}, autofocus: true));
      await tester.pump();

      expect(_hasRing(tester), isTrue);
      expect(_ring.width, 2);
      expect(_ring.offset, 2);
      // The ring's colour is the palette's; that it is *the ring's* colour and
      // 2px at 2px is this test's. `OPEN_QUESTIONS.md` item 18 kept the geometry
      // and moved the hue.
      expect(
        _ring.color,
        spiritTheme.extension<AppTokens>()!.colors.action.focusRing.color,
      );
    });

    testWidgets('a touch that happens to focus draws no ring', (tester) async {
      // The distinction between `focused` and `focus-visible`. Material's own
      // `InkResponse` reads the same highlight mode from the same place, so a
      // migrated control and an unmigrated one agree about when a ring shows.
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTouch;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );

      await tester.pumpWidget(_surface(onPressed: () {}, autofocus: true));
      await tester.pump();
      expect(_hasRing(tester), isFalse);
    });

    testWidgets('focusing does not move the surface, because the gutter is '
        'always reserved', (tester) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );

      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(_surface(onPressed: () {}, focusNode: node));
      await tester.pumpAndSettle();

      const child = ValueKey('press-child');
      final before = tester.getRect(find.byType(PressSurface));
      final childBefore = tester.getRect(find.byKey(child));
      expect(_hasRing(tester), isFalse);

      node.requestFocus();
      await tester.pumpAndSettle();
      expect(_hasRing(tester), isTrue);

      expect(tester.getRect(find.byType(PressSurface)), before);
      expect(
        tester.getRect(find.byKey(child)),
        childBefore,
        reason: 'a ring appearing must not reflow the row it is in',
      );
    });

    testWidgets('a ring inside sits on the surface\'s own edge, with no '
        'gutter', (tester) async {
      // A row filling a card has no room outside itself: the ring is drawn on
      // its edge, and the row keeps the card's whole width.
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );

      const child = ValueKey('press-child');
      await tester.pumpWidget(
        MaterialApp(
          theme: spiritTheme,
          home: Scaffold(
            body: Center(
              child: PressSurface(
                borderRadius: BorderRadius.circular(_tokens.radius.lg),
                onPressed: () {},
                autofocus: true,
                ringInside: true,
                child: const SizedBox(key: child, width: 320, height: 72),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final ring = find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).border?.top.color ==
                _ring.color,
      );
      expect(ring, findsOne);
      expect(tester.getRect(ring), tester.getRect(find.byKey(child)));
      expect(
        tester.getSize(find.byType(PressSurface)),
        tester.getSize(find.byKey(child)),
        reason: 'no gutter is reserved round a ring drawn inside',
      );
      expect(
        (tester.widget<DecoratedBox>(ring).decoration as BoxDecoration)
            .borderRadius,
        BorderRadius.circular(_tokens.radius.lg),
      );
    });

    testWidgets('a disabled surface cannot take focus at all', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(_surface(focusNode: node));
      node.requestFocus();
      await tester.pump();
      expect(node.hasFocus, isFalse);
    });

    testWidgets('space and enter activate a focused surface', (tester) async {
      var presses = 0;
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        _surface(onPressed: () => presses++, focusNode: node),
      );
      node.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump(const Duration(milliseconds: 400));
      expect(presses, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 400));
      expect(presses, 2);
    });
  });

  group('a surface that repeats while held, as a backspace does', () {
    final repeat = _tokens.motion.keyRepeat;

    Future<TestGesture> holdDown(WidgetTester tester) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PressSurface)),
      );
      await tester.pump();
      return gesture;
    }

    testWidgets('it fires as the press lands, waits, then repeats', (
      tester,
    ) async {
      var presses = 0;
      await tester.pumpWidget(
        _surface(onPressed: () => presses++, repeatsWhileHeld: true),
      );
      final gesture = await holdDown(tester);
      expect(presses, 1);

      await tester.pump(repeat.delay - const Duration(milliseconds: 1));
      expect(presses, 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(presses, 2);
      await tester.pump(repeat.slowest);
      expect(presses, 3);

      await gesture.up();
      await tester.pump(const Duration(seconds: 2));
      expect(presses, 3);
    });

    testWidgets('the repeats speed up, then hold at the fastest gap', (
      tester,
    ) async {
      var presses = 0;
      await tester.pumpWidget(
        _surface(onPressed: () => presses++, repeatsWhileHeld: true),
      );
      final gesture = await holdDown(tester);
      await tester.pump(repeat.delay);

      var before = presses;
      await tester.pump(repeat.ramp.duration);
      final ramping = presses - before;
      before = presses;
      await tester.pump(repeat.ramp.duration);
      final settled = presses - before;

      expect(settled, greaterThan(ramping));
      expect(
        settled,
        closeTo(
          repeat.ramp.duration.inMicroseconds / repeat.fastest.inMicroseconds,
          1,
        ),
      );
      await gesture.up();
    });

    testWidgets('a tap fires once, and not again on the way up', (
      tester,
    ) async {
      var presses = 0;
      await tester.pumpWidget(
        _surface(onPressed: () => presses++, repeatsWhileHeld: true),
      );
      await tester.tap(find.byType(PressSurface));
      await tester.pump(const Duration(seconds: 2));
      expect(presses, 1);
    });

    testWidgets('sliding off it stops the repeats', (tester) async {
      var presses = 0;
      await tester.pumpWidget(
        _surface(onPressed: () => presses++, repeatsWhileHeld: true),
      );
      final gesture = await holdDown(tester);
      await gesture.moveBy(const Offset(300, 0));
      await tester.pump(const Duration(seconds: 2));
      expect(presses, 1);
      await gesture.up();
    });

    testWidgets('a held Space repeats on the platform\'s own key repeat', (
      tester,
    ) async {
      var presses = 0;
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        _surface(
          onPressed: () => presses++,
          focusNode: node,
          repeatsWhileHeld: true,
        ),
      );
      node.requestFocus();
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      expect(presses, 1);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
      expect(presses, 2);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      expect(presses, 2);
    });

    testWidgets('a surface that does not repeat still fires once, on '
        'release', (tester) async {
      var presses = 0;
      await tester.pumpWidget(_surface(onPressed: () => presses++));
      final gesture = await holdDown(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(presses, 0);
      await gesture.up();
      await tester.pump();
      expect(presses, 1);
    });
  });

  group('the tap target is §9\'s 48dp, whatever is painted', () {
    testWidgets('a 20px child still answers a 48dp area, at its edges', (
      tester,
    ) async {
      // §9's touch target is pass/fail and `design.md` §5.2 gives `AppButton`
      // a 32-high size, so the painted box and the hit area cannot be the same
      // thing. The catalog's 20px `Correct` / `Retire` links are named in §9 as
      // a current failure for exactly this.
      //
      // **The taps are the assertion; the size is only corroboration.** An
      // earlier build of this widget reserved the area and left the gesture
      // detector inside it, so the box measured 48 and a finger landing 2px
      // inside its edge hit nothing at all. A size-only test passed against
      // that.
      var presses = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: spiritTheme,
          home: Scaffold(
            body: Center(
              child: PressSurface(
                borderRadius: BorderRadius.circular(_tokens.radius.sm),
                onPressed: () => presses++,
                child: const SizedBox(
                  key: ValueKey('press-child'),
                  width: 20,
                  height: 20,
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.byKey(const ValueKey('press-child'))),
        const Size(20, 20),
      );

      final target = tester.getRect(find.byType(PressSurface));
      expect(target.width, greaterThanOrEqualTo(48));
      expect(target.height, greaterThanOrEqualTo(48));

      for (final point in <Offset>[
        Offset(target.center.dx, target.top + 1),
        Offset(target.center.dx, target.bottom - 1),
        Offset(target.left + 1, target.center.dy),
        Offset(target.right - 1, target.center.dy),
      ]) {
        await tester.tapAt(point);
        await tester.pumpAndSettle();
      }
      expect(presses, 4, reason: 'every corner of the target must answer');
    });

    testWidgets('and the density decides it, so compact gets §3\'s 32', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: spiritTheme,
          home: Builder(
            builder: (context) => Theme(
              data: Theme.of(context).copyWith(
                extensions: <ThemeExtension<dynamic>>[
                  AppTokens.dark.withDensity(AppDensity.compact),
                ],
              ),
              child: Scaffold(
                body: Center(
                  child: PressSurface(
                    borderRadius: BorderRadius.circular(_tokens.radius.sm),
                    onPressed: () {},
                    child: const SizedBox(width: 20, height: 20),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final target = tester.getSize(find.byType(PressSurface));
      expect(target.width, 32);
      expect(target.height, 32);
    });
  });

  group('it announces itself as one button', () {
    testWidgets('enabled', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_surface(onPressed: () {}));
      expect(
        tester.getSemantics(find.byType(PressSurface)),
        matchesSemantics(
          label: 'Press me',
          isButton: true,
          isEnabled: true,
          hasEnabledState: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('and a disabled one says so rather than going quiet', (
      tester,
    ) async {
      // §9 does not list this, but a control that is merely inert reads to a
      // screen reader as a control that is missing.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_surface());
      expect(
        tester.getSemantics(find.byType(PressSurface)),
        matchesSemantics(
          label: 'Press me',
          isButton: true,
          isEnabled: false,
          hasEnabledState: true,
        ),
      );
      handle.dispose();
    });
  });
}
