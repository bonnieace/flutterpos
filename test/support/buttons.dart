/// Reading a button's state while the migration to `AppButton` runs.
///
/// `design.md` §11 step 3 replaces every Material button in the migrated tree,
/// and it does not do so in one commit. For as long as that is true a test that
/// asks "can this be pressed" has to answer for both kinds, or every partially
/// migrated screen breaks tests that are still correct about the behaviour they
/// describe.
///
/// **This file is temporary and should be deleted with the last
/// `ButtonStyleButton` in `lib/`.** It is not a permanent abstraction over two
/// button systems - it is the seam that lets the sweep land screen by screen.
///
/// **`PillButton` left on 2026-08-15 with §11 step 9**, so the remaining
/// non-`AppButton` controls in the migrated tree are all in
/// `checkout_cart_panel.dart`, which is step 7's.
library;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/ui/buttons.dart';
import 'package:flutter_test/flutter_test.dart';

/// Whether the control under [key] can be pressed.
///
/// An [AppButton] is pressable only when it has a callback **and** is not
/// loading, because §2.1's loading row is a press that has already been
/// accepted. A `ButtonStyle` button has no such state and answers on
/// `onPressed` alone.
bool pressable(WidgetTester tester, String key) =>
    pressableFinder(tester, find.byKey(ValueKey(key)));

/// [pressable], for a caller that already has a finder.
bool pressableFinder(WidgetTester tester, Finder finder) {
  final widget = tester.widget(finder);
  return switch (widget) {
    AppButton(:final onPressed, :final loading) =>
      onPressed != null && !loading,
    ButtonStyleButton(:final onPressed) => onPressed != null,
    _ => throw StateError(
      'Expected a button at $finder, found a ${widget.runtimeType}.',
    ),
  };
}
