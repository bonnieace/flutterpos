/// The component state matrix, which `claude.md` hard rule 5 and `design.md`
/// §10 both require before a component is finished.
///
/// > "Every component lands with its full state matrix in the screenshot
/// > harness. A component with an unrepresented state is incomplete."
///
/// **`AppButton`'s matrix is six of §5's nine states, and the other three are
/// absent on purpose.** `enabled`, `hover`, `focus-visible`, `pressed`,
/// `disabled` and `loading` all apply to a button. `error` belongs to
/// `AppTextField`, where §5.2 puts it - a button has no value to be wrong
/// about; a button that may not be used is `disabled` rather than read-only;
/// and there is no such thing as an empty button.
///
/// **How the states are produced matters, because a faked state proves
/// nothing.** `enabled`, `disabled` and `loading` are properties, so a whole
/// grid of them is one capture. The other three are things a person does to
/// one control at a time, and they are driven for real:
///
/// - **pressed** by holding twelve simultaneous pointers, one per cell, so the
///   grid is genuinely mid-press rather than painted to look like it.
/// - **hover** by a mouse pointer per cell, the same way.
/// - **focus-visible** one tier at a time, because only one node can hold the
///   primary focus. It also needs
///   [FocusHighlightStrategy.alwaysTraditional]: the highlight mode follows the
///   platform, a test binding reports a touch platform, and a ring that only a
///   keyboard user ever sees would otherwise never appear in a picture.
///
/// **The press captures are the one place in this harness where a spring is
/// visible at all, and they still are not evidence about motion.** They are a
/// photograph of the scale at a settled moment. Whether the spring is
/// interruptible, and whether it drops a frame, is a device check with the
/// performance overlay on, per `design.md` §10.
library;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_application_1/ui/buttons.dart';
import 'package:flutter_application_1/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

/// The state a row of the grid is rendered in.
enum _State { enabled, disabled, loading }

/// A page rendering one state across all four tiers and all three sizes.
class _ButtonMatrix extends StatelessWidget {
  const _ButtonMatrix({required this.title, required this.state, this.focused});

  final String title;
  final _State state;

  /// The tier whose `lg` button holds the focus, for the focus-visible
  /// captures. Only one, because only one node can hold the primary focus.
  final AppButtonTier? focused;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(tokens.spacing.s24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final tier in AppButtonTier.values) ...<Widget>[
              Text(
                'action.${tier.name}',
                style: tokens.typography.labelEyebrow.copyWith(
                  color: tokens.colors.text.tertiary,
                ),
              ),
              SizedBox(height: tokens.spacing.s8),
              Wrap(
                spacing: tokens.spacing.s16,
                runSpacing: tokens.spacing.s12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  for (final size in AppButtonSize.values)
                    AppButton(
                      key: ValueKey('${tier.name}-${size.name}'),
                      label: 'Save sale',
                      icon: size == AppButtonSize.lg
                          ? Icons.point_of_sale
                          : null,
                      tier: tier,
                      size: size,
                      loading: state == _State.loading,
                      autofocus: focused == tier && size == AppButtonSize.lg,
                      onPressed: state == _State.disabled ? null : () {},
                    ),
                ],
              ),
              SizedBox(height: tokens.spacing.s24),
            ],
          ],
        ),
      ),
    );
  }
}

/// The `lg` button of one tier, which is what the pointer states drive.
Finder _large(AppButtonTier tier) =>
    find.byKey(ValueKey('${tier.name}-${AppButtonSize.lg.name}'));

void main() {
  // `sm` and `md` are pointer sizes, so the matrix is a desktop viewport only.
  // Rendering them at 411 would be a picture of three sizes nobody may use
  // there - §5.2 gives a touch surface `lg` and nothing else.
  const viewports = <ScreenshotViewport>[webViewport];

  for (final state in _State.values) {
    screenshotCase(
      '90-appbutton-${state.name}',
      viewports: viewports,
      // The loading grid never reaches a quiet frame: twelve indeterminate
      // spinners never stop, so `pumpAndSettle` would time out rather than
      // settle.
      settle: state != _State.loading,
      build: () =>
          _ButtonMatrix(title: 'AppButton - ${state.name}', state: state),
    );
  }

  // **One capture per tier for hover, rather than one hovering all four.**
  // `MouseTracker` asserts on the ordering of add/remove across devices, so a
  // second simultaneous mouse pointer fails outright - and because the tracker
  // lives on the binding rather than on the test, the failure poisons the next
  // capture in this file too. One pointer per capture is the shape the
  // framework supports.
  for (final tier in AppButtonTier.values) {
    screenshotCase(
      '90-appbutton-hover-${tier.name}',
      viewports: viewports,
      build: () => _ButtonMatrix(
        title: 'AppButton - hover, action.${tier.name}',
        state: _State.enabled,
      ),
      afterPump: (tester) async {
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(_large(tier)));
        await tester.pumpAndSettle();
      },
    );
  }

  screenshotCase(
    '90-appbutton-pressed',
    viewports: viewports,
    build: () => const _ButtonMatrix(
      title: 'AppButton - pressed',
      state: _State.enabled,
    ),
    afterPump: (tester) async {
      // Touch, not mouse, so four simultaneous pointers are exactly what the
      // framework is built for - this is multi-touch, and all four tiers can
      // be photographed mid-press at once.
      var pointer = 200;
      final gestures = <TestGesture>[];
      for (final tier in AppButtonTier.values) {
        gestures.add(
          await tester.startGesture(
            tester.getCenter(_large(tier)),
            pointer: pointer++,
          ),
        );
      }
      // Let every press spring reach 0.97 before the shutter. The picture is
      // of the settled press, not of a spring mid-flight - a screenshot cannot
      // show the second thing honestly.
      await tester.pump(const Duration(milliseconds: 400));
      addTearDown(() async {
        for (final gesture in gestures) {
          await gesture.up();
        }
      });
    },
  );

  for (final tier in AppButtonTier.values) {
    screenshotCase(
      '90-appbutton-focus-${tier.name}',
      viewports: viewports,
      build: () => _ButtonMatrix(
        title: 'AppButton - focus-visible, action.${tier.name}',
        state: _State.enabled,
        focused: tier,
      ),
      afterPump: (tester) async {
        // §9's ring is for a keyboard user, and `PressSurface` reads the same
        // highlight mode Material's own controls do. A test binding reports a
        // touch platform, so without this the ring is correctly suppressed and
        // the capture would show its absence.
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTraditional;
        addTearDown(
          () => FocusManager.instance.highlightStrategy =
              FocusHighlightStrategy.automatic,
        );
        await tester.pumpAndSettle();
      },
    );
  }
}
