/// Step 4's state matrices, which `claude.md` hard rule 5 and `design.md` §10
/// both require before a component is finished.
///
/// **Two of the three components have no interaction states at all, and that is
/// not a gap in the matrix.** §5's nine states are the states of a *control*.
/// A [StatusBadge] and a [Callout] are readouts: they have no hover, no focus,
/// no press, no disabled and no loading, because there is nothing to do to
/// them. What varies is the thing they exist to say, so their matrix is the
/// five statuses of §2.1 - which is also the assertion that matters, because
/// the defect being replaced is one green doing seven jobs and the only way to
/// see that it is fixed is to see all five at once.
///
/// **[Disclosure] is a control and gets the full treatment.** Collapsed and
/// expanded are its two real states; hover, focus-visible and pressed are
/// driven for real rather than painted, the same way `AppButton`'s are, and
/// disabled is a property.
///
/// **The expanded capture is a photograph of a settled spring and proves
/// nothing about the motion.** §2.4 makes the reveal a spring and §10 makes
/// motion a device check; what these pictures show is the two ends, not the
/// journey between them.
library;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:uzapay_pos/ui/status.dart';
import 'package:uzapay_pos/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

/// A sentence per status, in this app's own vocabulary rather than in lorem.
///
/// The words are the ones §2.1 gives each status as its meaning, put into the
/// kind of line a shop would actually read, so the picture doubles as a check
/// that the five meanings stay separable in prose.
const Map<AppStatus, ({String badge, String title, String message})> _copy =
    <AppStatus, ({String badge, String title, String message})>{
      AppStatus.ok: (
        badge: 'Reconciled',
        title: 'The day balances',
        message:
            'Yesterday\'s takings and the counted cash agree. Nothing needs '
            'correcting.',
      ),
      AppStatus.attention: (
        badge: 'Pending',
        title: 'Waiting on a manager',
        message:
            'This return is recorded and the stock has not moved yet. A '
            'manager verifies it before the count changes.',
      ),
      AppStatus.problem: (
        badge: 'Difference found',
        title: 'The day does not balance',
        message:
            'The takings and the counted cash disagree by KES 400. Open the '
            'differences list to see which shift it came from.',
      ),
      AppStatus.info: (
        badge: 'Offline',
        title: 'This sale is queued',
        message:
            'The sale is saved on this device and will be sent when the '
            'connection returns. Nothing is lost by closing the app.',
      ),
      AppStatus.neutral: (
        badge: 'Retired',
        title: 'This product is retired',
        message:
            'It no longer appears on the till and every sale that already '
            'names it keeps its history.',
      ),
    };

/// Every status, as a badge and as a callout, at one density.
class _StatusMatrix extends StatelessWidget {
  const _StatusMatrix({required this.title, required this.density});

  final String title;
  final AppDensity density;

  @override
  Widget build(BuildContext context) => Builder(
    builder: (context) {
      final tokens = AppTokens.componentOf(context).withDensity(density);
      return Theme(
        data: Theme.of(
          context,
        ).copyWith(extensions: <ThemeExtension<dynamic>>[tokens]),
        child: Scaffold(
          appBar: AppBar(title: Text(title)),
          body: SingleChildScrollView(
            padding: EdgeInsets.all(tokens.spacing.s24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'StatusBadge',
                  style: tokens.typography.labelEyebrow.copyWith(
                    color: tokens.colors.text.tertiary,
                  ),
                ),
                SizedBox(height: tokens.spacing.s12),
                Wrap(
                  spacing: tokens.spacing.s8,
                  runSpacing: tokens.spacing.s8,
                  children: <Widget>[
                    for (final status in AppStatus.values)
                      StatusBadge(status: status, label: _copy[status]!.badge),
                  ],
                ),
                SizedBox(height: tokens.density.sectionGap),
                Text(
                  'Callout',
                  style: tokens.typography.labelEyebrow.copyWith(
                    color: tokens.colors.text.tertiary,
                  ),
                ),
                SizedBox(height: tokens.spacing.s12),
                for (final status in AppStatus.values) ...<Widget>[
                  Callout(
                    status: status,
                    title: _copy[status]!.title,
                    message: _copy[status]!.message,
                  ),
                  SizedBox(height: tokens.spacing.s12),
                ],
                SizedBox(height: tokens.density.sectionGap),
                Text(
                  'Callout - untitled, and one with an action',
                  style: tokens.typography.labelEyebrow.copyWith(
                    color: tokens.colors.text.tertiary,
                  ),
                ),
                SizedBox(height: tokens.spacing.s12),
                Callout(
                  status: AppStatus.info,
                  message: _copy[AppStatus.info]!.message,
                ),
                SizedBox(height: tokens.spacing.s12),
                Callout(
                  status: AppStatus.problem,
                  message: 'The catalog could not be read.',
                  action: TextButton(
                    onPressed: () {},
                    child: const Text('Try again'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// The four permanent explanations this app already carries, as disclosures.
///
/// **The prose is this app's own, verbatim**, because §5.2's argument for the
/// component is specifically about this writing: it is good and it should be
/// kept, and what makes the catalog form three times taller than it needs to be
/// is that it is all permanently on screen.
class _DisclosureMatrix extends StatelessWidget {
  const _DisclosureMatrix({
    required this.title,
    this.expanded = false,
    this.disabled = false,
    this.focused = false,
  });

  final String title;
  final bool expanded;
  final bool disabled;
  final bool focused;

  static const List<({String summary, String body})> _entries =
      <({String summary, String body})>[
        (
          summary: 'How one correction reaches many products',
          body:
              'One correction can be applied across many products, and a '
              'catalog that is wrong in one field is corrected in one pass. '
              'Nothing is written until the whole chain has been previewed.',
        ),
        (
          summary: 'What an adjustment does to the count',
          body:
              'An adjustment moves the recorded count and records why. It '
              'never edits a sale, and every movement keeps the member who '
              'made it and the moment it happened.',
        ),
        (
          summary: 'Why a profit figure is sometimes not shown',
          body:
              'A profit figure appears only when every sale line behind it '
              'carries a cost. Where some do not, the count of those lines is '
              'shown instead of a number that would be wrong.',
        ),
      ];

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
            for (var index = 0; index < _entries.length; index++) ...<Widget>[
              Disclosure(
                key: ValueKey('disclosure-$index'),
                summary: _entries[index].summary,
                initiallyExpanded: expanded,
                enabled: !disabled,
                // One node at a time, because only one can hold the primary
                // focus - the same reason `AppButton`'s matrix takes one
                // capture per tier.
                autofocus: focused && index == 0,
                child: Text(_entries[index].body),
              ),
              SizedBox(height: tokens.spacing.s12),
            ],
          ],
        ),
      ),
    );
  }
}

Finder _firstDisclosure() => find.byKey(const ValueKey('disclosure-0'));

void main() {
  for (final density in <({String name, AppDensity value})>[
    (name: 'comfortable', value: AppDensity.comfortable),
    (name: 'compact', value: AppDensity.compact),
  ]) {
    screenshotCase(
      '93-status-${density.name}',
      build: () => _StatusMatrix(
        title: 'StatusBadge and Callout - ${density.name}',
        density: density.value,
      ),
    );
  }

  for (final state in <({String name, bool expanded, bool disabled})>[
    (name: 'collapsed', expanded: false, disabled: false),
    (name: 'expanded', expanded: true, disabled: false),
    (name: 'disabled', expanded: false, disabled: true),
  ]) {
    screenshotCase(
      '93-disclosure-${state.name}',
      build: () => _DisclosureMatrix(
        title: 'Disclosure - ${state.name}',
        expanded: state.expanded,
        disabled: state.disabled,
      ),
    );
  }

  // A pointer state, so the desktop viewport only - the same reason
  // `AppButton`'s hover matrix is web-only.
  screenshotCase(
    '93-disclosure-hover',
    viewports: const <ScreenshotViewport>[webViewport],
    build: () => const _DisclosureMatrix(title: 'Disclosure - hover'),
    afterPump: (tester) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(_firstDisclosure()));
      await tester.pumpAndSettle();
    },
  );

  screenshotCase(
    '93-disclosure-pressed',
    viewports: const <ScreenshotViewport>[webViewport],
    build: () => const _DisclosureMatrix(title: 'Disclosure - pressed'),
    afterPump: (tester) async {
      final gesture = await tester.startGesture(
        tester.getCenter(_firstDisclosure()),
      );
      // Let the press spring reach its settled scale before the shutter. A
      // screenshot cannot show a spring mid-flight honestly.
      await tester.pump(const Duration(milliseconds: 400));
      addTearDown(gesture.up);
    },
  );

  screenshotCase(
    '93-disclosure-focus',
    viewports: const <ScreenshotViewport>[webViewport],
    build: () => const _DisclosureMatrix(
      title: 'Disclosure - focus-visible',
      focused: true,
    ),
    afterPump: (tester) async {
      // §9's ring is for a keyboard user, and `PressSurface` reads the platform
      // highlight mode. A test binding reports a touch platform, so without
      // this the ring is correctly suppressed and the capture would show its
      // absence.
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      // Not a tap: a tap would open it, and this capture is of a *collapsed*
      // disclosure holding the focus. The node is autofocused instead.
      await tester.pumpAndSettle();
    },
  );
}
