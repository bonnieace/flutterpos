/// Reads a text field's value through whichever widget carries its key.
///
/// The same seam `test/support/buttons.dart` is, and for the same reason: while
/// `design.md` §11 step 3's second half is landing, `lib/` holds more than one
/// field implementation. ~~Most keys are now an [AppTextField]; the sale path's
/// are still a bare `TextField` because `checkout_cart_panel.dart` is step 7's,
/// and sign-in's are still a `PillInput` because §4.4 is step 9's.~~ **Step 9
/// landed 2026-08-15 and `PillInput` is gone**, so what is left is two fields in
/// `checkout_cart_panel.dart` and nothing else.
///
/// **A test that casts to a concrete field type is asserting which component
/// drew the screen, which is not what any of these tests are about.** Every one
/// of them wants the text a person would see in the box. Going through here
/// means the last migration changes no test that was already asking the right
/// question.
///
/// Delete this when `checkout_cart_panel.dart` is migrated and every field in
/// `lib/` is an [AppTextField]; at that point
/// `tester.widget<AppTextField>(...).controller` says it plainly enough. **Step
/// 7 is now the only thing keeping this file and `buttons.dart` alive.**
library;

import 'package:flutter/material.dart';
import 'package:uzapay_pos/ui/fields.dart';
import 'package:flutter_test/flutter_test.dart';

/// The text held by the field keyed [key].
String fieldText(WidgetTester tester, String key) =>
    fieldController(tester, key).text;

/// The controller behind the field keyed [key].
TextEditingController fieldController(WidgetTester tester, String key) {
  final finder = find.byKey(ValueKey<String>(key));
  final widget = tester.widget(finder);
  final controller = switch (widget) {
    AppTextField(:final controller) => controller,
    TextField(:final controller) => controller,
    TextFormField() => tester
        .widget<TextField>(
          find.descendant(of: finder, matching: find.byType(TextField)),
        )
        .controller,
    _ => throw StateError(
      'The widget keyed "$key" is a ${widget.runtimeType}, which is not a '
      'field this helper knows how to read.',
    ),
  };
  if (controller == null) {
    throw StateError('The field keyed "$key" has no controller to read.');
  }
  return controller;
}
