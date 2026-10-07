/// `AppTabs`'s matrix, per `claude.md` hard rule 5 and §10, in both of its
/// shapes. `docs/design/tabs/` is the design these are measured against.
///
/// **Two tabs are the switch and three or more are icon tabs**, so each shape
/// gets its own rows: a selection either side, then hover, press and the
/// keyboard's focus ring, which the cells now draw themselves and a capture
/// can photograph. `loading`, `error`, `read-only` and `empty` mean nothing for
/// a tab strip, and `TabBar` has no disabled tab.
///
/// **The phone capture is the one worth reading for icon tabs.** Four tabs
/// with glyphs are wider than 411, so the strip scrolls and its far end fades;
/// this is the picture of what a person actually sees first.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uzapay_pos/ui/tabs.dart';
import 'package:uzapay_pos/ui/tokens.dart';

import 'harness.dart';

/// The platform route's own two, verbatim.
const List<String> _two = <String>['Active & suspended', 'Global user status'];

/// Configs' four, with the glyphs its panels lead with.
const List<String> _four = <String>[
  'Currency',
  'Stock counts',
  'Agreed prices',
  'Loyalty',
];
const List<IconData> _glyphs = <IconData>[
  Icons.payments_outlined,
  Icons.assignment_outlined,
  Icons.handshake_outlined,
  Icons.loyalty_outlined,
];

void main() {
  screenshotCase(
    '95-apptabs-switch-first-selected',
    build: () => const _Host(tabs: _two),
    fullPage: false,
  );

  screenshotCase(
    '95-apptabs-switch-second-selected',
    build: () => const _Host(tabs: _two, initialIndex: 1),
    fullPage: false,
  );

  screenshotCase(
    '95-apptabs-switch-hover',
    build: () => const _Host(tabs: _two),
    fullPage: false,
    afterPump: (tester) => _hover(tester, _two[1]),
  );

  screenshotCase(
    '95-apptabs-switch-pressed',
    build: () => const _Host(tabs: _two),
    fullPage: false,
    afterPump: (tester) => _press(tester, _two[1]),
  );

  screenshotCase(
    '95-apptabs-switch-focus',
    build: () => const _Host(tabs: _two),
    fullPage: false,
    afterPump: (tester) => _focus(tester, presses: 2),
  );

  screenshotCase(
    '95-apptabs-icons-first-selected',
    build: () => const _Host(tabs: _four, icons: _glyphs),
    fullPage: false,
  );

  screenshotCase(
    '95-apptabs-icons-third-selected',
    build: () => const _Host(tabs: _four, icons: _glyphs, initialIndex: 2),
    fullPage: false,
  );

  screenshotCase(
    '95-apptabs-icons-hover',
    build: () => const _Host(tabs: _four, icons: _glyphs),
    fullPage: false,
    afterPump: (tester) => _hover(tester, _four[1]),
  );

  screenshotCase(
    '95-apptabs-icons-focus',
    build: () => const _Host(tabs: _four, icons: _glyphs),
    fullPage: false,
    afterPump: (tester) => _focus(tester, presses: 1),
  );
}

Future<void> _hover(WidgetTester tester, String label) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await mouse.moveTo(tester.getCenter(find.text(label)));
  await tester.pumpAndSettle();
}

Future<void> _press(WidgetTester tester, String label) async {
  final press = await tester.startGesture(tester.getCenter(find.text(label)));
  await tester.pump(const Duration(milliseconds: 400));
  addTearDown(press.up);
}

Future<void> _focus(WidgetTester tester, {required int presses}) async {
  // A test binding reports a touch platform, where the ring is correctly
  // suppressed; the keyboard is what this capture is of.
  FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional;
  addTearDown(
    () => FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.automatic,
  );
  for (var i = 0; i < presses; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  }
  await tester.pumpAndSettle();
}

/// One strip under where a toolbar would be, at a page's inset.
final class _Host extends StatelessWidget {
  const _Host({required this.tabs, this.icons, this.initialIndex = 0});

  final List<String> tabs;
  final List<IconData>? icons;
  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return DefaultTabController(
      length: tabs.length,
      initialIndex: initialIndex,
      child: Scaffold(
        backgroundColor: tokens.colors.surface.base,
        body: Padding(
          padding: EdgeInsets.only(top: tokens.spacing.s8),
          child: Column(
            children: <Widget>[
              AppTabs(tabs: tabs, icons: icons, inset: tokens.spacing.s20),
            ],
          ),
        ),
      ),
    );
  }
}
