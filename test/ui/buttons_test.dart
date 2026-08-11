import 'package:flutter/material.dart';
import 'package:flutter_application_1/theme.dart';
import 'package:flutter_application_1/ui/buttons.dart';
import 'package:flutter_application_1/ui/press.dart';
import 'package:flutter_application_1/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

const AppTokens _tokens = AppTokens.dark;
final AppActionRoles _actions = _tokens.colors.action;

Widget _app(Widget child) => MaterialApp(
  theme: spiritTheme,
  home: Scaffold(body: Center(child: child)),
);

/// The button's own container - the first [DecoratedBox] under it, which is
/// the surface [PressSurface] wraps rather than one of the overlays it paints
/// over the top.
BoxDecoration _container(WidgetTester tester) =>
    tester
            .widgetList<DecoratedBox>(
              find.descendant(
                of: find.byType(AppButton),
                matching: find.byType(DecoratedBox),
              ),
            )
            .first
            .decoration
        as BoxDecoration;

Size _paintedSize(WidgetTester tester) => tester.getSize(
  find
      .descendant(
        of: find.byType(AppButton),
        matching: find.byType(DecoratedBox),
      )
      .first,
);

TextStyle _labelStyle(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label)).style!;

void main() {
  group('the four tiers are §2.1\'s action table', () {
    testWidgets('enabled, each carries its own container, label and border', (
      tester,
    ) async {
      for (final tier in AppButtonTier.values) {
        final role = tier.of(_actions);
        await tester.pumpWidget(
          _app(AppButton(label: 'Do it', tier: tier, onPressed: () {})),
        );
        await tester.pumpAndSettle();

        expect(_container(tester).color, role.container, reason: '$tier');
        expect(_labelStyle(tester, 'Do it').color, role.label, reason: '$tier');
        expect(
          _container(tester).border?.top.color,
          role.border,
          reason: '$tier',
        );
      }
    });

    testWidgets('the ordinary tier is sage and the primary label is ink', (
      tester,
    ) async {
      // The two values step 3 moved, pinned at the widget rather than only at
      // the theme, because this is where a call site actually reads them.
      await tester.pumpWidget(
        _app(
          const AppButton(
            label: 'Ordinary',
            tier: AppButtonTier.secondary,
            onPressed: null,
          ),
        ),
      );
      expect(_actions.secondary.label, const Color(0xFFB8D6C5));
      expect(_actions.primary.label, const Color(0xFF0A0F0C));
      expect(_actions.secondary.border, const Color(0xFF2C5340));
    });

    testWidgets('destructive is the tier that had nowhere to live before', (
      tester,
    ) async {
      // `action.destructive` has no Material button theme to attach to, so
      // until `AppButton` existed there was no way to render it at all.
      await tester.pumpWidget(
        _app(
          AppButton(
            label: 'Retire this product',
            tier: AppButtonTier.destructive,
            onPressed: () {},
          ),
        ),
      );
      expect(
        _labelStyle(tester, 'Retire this product').color,
        const Color(0xFFFF5C6C),
      );
      expect(_container(tester).border?.top.color, const Color(0xFFFF5C6C));
    });

    testWidgets('disabled follows §2.1\'s two different rules', (tester) async {
      // The primary tier takes a container; the three overlay tiers keep a
      // transparent one and move only their label and border.
      await tester.pumpWidget(
        _app(
          const AppButton(
            label: 'Off',
            tier: AppButtonTier.primary,
            onPressed: null,
          ),
        ),
      );
      expect(_container(tester).color, _actions.disabledContainer);
      expect(_labelStyle(tester, 'Off').color, _actions.disabledLabel);

      for (final tier in <AppButtonTier>[
        AppButtonTier.secondary,
        AppButtonTier.tertiary,
        AppButtonTier.destructive,
      ]) {
        await tester.pumpWidget(
          _app(AppButton(label: 'Off', tier: tier, onPressed: null)),
        );
        expect(_container(tester).color, Colors.transparent, reason: '$tier');
        expect(
          _labelStyle(tester, 'Off').color,
          _actions.disabledLabel,
          reason: '$tier',
        );
        if (tier.of(_actions).border != null) {
          expect(
            _container(tester).border?.top.color,
            _actions.disabledBorder,
            reason: '$tier',
          );
        }
      }
    });

    testWidgets('a disabled button does not answer a tap', (tester) async {
      var presses = 0;
      await tester.pumpWidget(
        _app(const AppButton(label: 'Off', onPressed: null)),
      );
      await tester.tap(find.byType(AppButton), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(presses, 0);
    });
  });

  group('the three sizes are §5.2\'s, and §9\'s target is not one of them', () {
    testWidgets('each paints the height §5.2 gives it', (tester) async {
      for (final size in AppButtonSize.values) {
        await tester.pumpWidget(
          _app(AppButton(label: 'Go', size: size, onPressed: () {})),
        );
        expect(_paintedSize(tester).height, size.height, reason: '$size');
      }
      expect(AppButtonSize.sm.height, 32);
      expect(AppButtonSize.md.height, 40);
      expect(AppButtonSize.lg.height, 48);
    });

    testWidgets('and every one of them answers a 48dp tap, including sm', (
      tester,
    ) async {
      // `claude.md` hard rule 6: §9 is pass/fail. A component that matches
      // §5.2's table by shrinking a touch target is a defect, so the painted
      // box and the hit area are separate things.
      for (final size in AppButtonSize.values) {
        await tester.pumpWidget(
          _app(AppButton(label: 'Go', size: size, onPressed: () {})),
        );
        final target = tester.getSize(find.byType(AppButton));
        expect(target.height, greaterThanOrEqualTo(48), reason: '$size');
        expect(target.width, greaterThanOrEqualTo(48), reason: '$size');
      }
    });

    testWidgets('a tap near the edge of a small button still lands', (
      tester,
    ) async {
      var presses = 0;
      await tester.pumpWidget(
        _app(
          AppButton(
            label: 'Go',
            size: AppButtonSize.sm,
            onPressed: () => presses++,
          ),
        ),
      );
      final rect = tester.getRect(find.byType(AppButton));
      // Two pixels inside the top edge of the hit area, which is above the
      // 32-high painted surface.
      await tester.tapAt(Offset(rect.center.dx, rect.top + 2));
      await tester.pumpAndSettle();
      expect(presses, 1);
    });
  });

  group('the loading row of §2.1', () {
    testWidgets('the label is replaced by a spinner in the label colour', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          AppButton(
            label: 'Save sale',
            tier: AppButtonTier.primary,
            loading: true,
            onPressed: () {},
          ),
        ),
      );
      await tester.pump();

      final spinner = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(spinner.valueColor!.value, _actions.primary.label);

      final box = tester.getSize(find.byType(CircularProgressIndicator));
      expect(box.width, _actions.loadingIndicatorSize);
      expect(box.height, _actions.loadingIndicatorSize);
      expect(_actions.loadingIndicatorSize, 16);
    });

    testWidgets('the width is frozen, so the button does not resize mid-press', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          AppButton(
            label: 'Submit this correction',
            onPressed: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final resting = _paintedSize(tester);

      await tester.pumpWidget(
        _app(
          AppButton(
            label: 'Submit this correction',
            loading: true,
            onPressed: () {},
          ),
        ),
      );
      await tester.pump();

      expect(
        _paintedSize(tester),
        resting,
        reason: 'the label is still laid out, just not painted',
      );
    });

    testWidgets('and it cannot be pressed twice', (tester) async {
      var presses = 0;
      await tester.pumpWidget(
        _app(
          AppButton(
            label: 'Save sale',
            loading: true,
            onPressed: () => presses++,
          ),
        ),
      );
      await tester.tap(find.byType(AppButton), warnIfMissed: false);
      await tester.pump();
      expect(presses, 0);
    });

    testWidgets('a screen reader is told it is working', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          AppButton(label: 'Save sale', loading: true, onPressed: () {}),
        ),
      );
      await tester.pump();
      expect(
        tester.getSemantics(find.byType(AppButton)),
        matchesSemantics(
          label: 'Save sale, working',
          isButton: true,
          isEnabled: false,
          hasEnabledState: true,
        ),
      );
      handle.dispose();
    });
  });

  group('the label and the icon are §5.2\'s', () {
    testWidgets('the label is label.lg in every size', (tester) async {
      for (final size in AppButtonSize.values) {
        await tester.pumpWidget(
          _app(AppButton(label: 'Go', size: size, onPressed: () {})),
        );
        final style = _labelStyle(tester, 'Go');
        expect(style.fontSize, _tokens.typography.labelLarge.fontSize);
        expect(style.fontWeight, _tokens.typography.labelLarge.fontWeight);
        expect(style.height, _tokens.typography.labelLarge.height);
      }
      expect(_tokens.typography.labelLarge.fontSize, 15);
    });

    testWidgets('a leading icon is 18px and takes the label colour', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          AppButton(
            label: 'New sale',
            icon: Icons.point_of_sale,
            tier: AppButtonTier.primary,
            onPressed: () {},
          ),
        ),
      );
      final icon = tester.widget<Icon>(find.byIcon(Icons.point_of_sale));
      expect(icon.size, 18);
      expect(icon.color, _actions.primary.label);
    });

    testWidgets('horizontal padding is space.20, or space.16 with an icon', (
      tester,
    ) async {
      expect(
        AppButtonSize.lg.horizontalPadding(_tokens.spacing, hasIcon: false),
        _tokens.spacing.s20,
      );
      expect(
        AppButtonSize.lg.horizontalPadding(_tokens.spacing, hasIcon: true),
        _tokens.spacing.s16,
      );

      await tester.pumpWidget(_app(AppButton(label: 'Go', onPressed: () {})));
      await tester.pumpAndSettle();
      final without = _paintedSize(tester).width;

      await tester.pumpWidget(
        _app(AppButton(label: 'Go', icon: Icons.star, onPressed: () {})),
      );
      await tester.pumpAndSettle();
      final with_ = _paintedSize(tester).width;

      // 8 less padding, plus an 18px icon and an 8px gap.
      expect(with_ - without, 18 + _tokens.spacing.s8 - _tokens.spacing.s8);
    });

    testWidgets('a pill, and pills are buttons only - §2.3', (tester) async {
      await tester.pumpWidget(_app(AppButton(label: 'Go', onPressed: () {})));
      final radius = _container(tester).borderRadius! as BorderRadius;
      expect(radius.topLeft.x, _tokens.radius.pill);
      expect(_tokens.radius.pill, 999);
    });
  });

  group('layout', () {
    testWidgets('it shrink-wraps by default, so a Wrap is not one button wide', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Wrap(
            children: <Widget>[
              AppButton(label: 'One', onPressed: () {}),
              AppButton(label: 'Two', onPressed: () {}),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final first = tester.getSize(find.byType(AppButton).first);
      expect(first.width, lessThan(200));
    });

    testWidgets('expand fills the width it is offered', (tester) async {
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 400,
            child: AppButton(label: 'Go', expand: true, onPressed: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(AppButton)).width, 400);
    });

    testWidgets('a label too long for its slot ellipsizes inside the button', (
      tester,
    ) async {
      // Found on the landing route at phone width: a `Wrap` hands the button a
      // real, narrow width, and a label with nothing to flex against overflows
      // its own pill by however many pixels it is too long.
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 120,
            child: AppButton(
              label: 'View read-only catalog',
              icon: Icons.inventory_2_outlined,
              onPressed: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_paintedSize(tester).width, lessThanOrEqualTo(120));
    });

    testWidgets('it lays out where a parent measures intrinsics, which is '
        'every AlertDialog action bar', (tester) async {
      // `AlertDialog` puts its actions in an `OverflowBar`, which asks each
      // child for its intrinsic width. A `LayoutBuilder` cannot answer that,
      // so a button built on one fails with a bare `hasSize` assertion naming
      // the dialog rather than the button - which is a long way from the
      // cause.
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => AppButton(
              label: 'Open',
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Change business'),
                  actions: <Widget>[
                    AppButton(
                      label: 'Cancel',
                      tier: AppButtonTier.tertiary,
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(AppButton));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('and inside an IntrinsicWidth, for the same reason', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          IntrinsicWidth(
            child: AppButton(label: 'Make default', onPressed: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('it survives an unbounded Row, which is where an AppBar puts '
        'it', (tester) async {
      // A `Row` lays a non-flexible child out with an unbounded main axis, so
      // a button that used `Flexible` unconditionally would fail here - and
      // "here" is every `AppBar.actions` list in the app.
      await tester.pumpWidget(
        _app(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AppButton(
                label: 'Sign out',
                tier: AppButtonTier.tertiary,
                onPressed: () {},
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(AppButton)).width, lessThan(300));
    });
  });

  group('it presses like a PressSurface, because it is one', () {
    testWidgets('a tap runs the callback and the scale springs', (
      tester,
    ) async {
      var presses = 0;
      await tester.pumpWidget(
        _app(
          AppButton(
            label: 'New sale',
            tier: AppButtonTier.primary,
            onPressed: () => presses++,
          ),
        ),
      );
      expect(find.byType(PressSurface), findsOneWidget);

      await tester.tap(find.byType(AppButton));
      await tester.pumpAndSettle();
      expect(presses, 1);
    });

    testWidgets('and it announces itself once, not twice', (tester) async {
      // `PressSurface` builds its own gesture detector, which contributes a
      // tappable semantics node. Without the exclusion this button is two
      // nodes deep and reads as two controls.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(AppButton(label: 'Find a receipt', onPressed: () {})),
      );
      expect(
        find.bySemanticsLabel('Find a receipt'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.byType(AppButton)),
        matchesSemantics(
          label: 'Find a receipt',
          isButton: true,
          isEnabled: true,
          hasEnabledState: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });
  });
}
