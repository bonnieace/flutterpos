/// Reading a sentence off a screen by its key, whichever component draws it.
///
/// **This exists because `§5.2`'s provenance row became a component on
/// 2026-08-22.** Before that, every line of text on every surface was a `Text`,
/// so eleven test files each carried their own
/// `tester.widget<Text>(find.byKey(...)).data!` and every one of them was
/// correct. `ProvenanceLine` made a `-recorded-` key name the component rather
/// than the `Text` inside it, which turns each of those casts into a type error
/// rather than a comparison — and a type error says *this cast is wrong*, not
/// *this screen says the wrong thing*, which is the failure a reader has to
/// decode before they can act on it.
///
/// So a provenance assertion asks this instead. It is deliberately **not** a
/// replacement for the local `_text` helpers those files keep: those say "the
/// `Text` at this key", which is still exactly what they want everywhere else.
library;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/ui/states.dart';
import 'package:flutter_test/flutter_test.dart';

/// The sentence at [key], read off whichever widget states it.
///
/// Handles `Text` and [ProvenanceLine]. Anything else throws with the type it
/// found, because "expected X, got null" from a silently-unmatched widget is the
/// hardest kind of test failure to read.
String textAt(WidgetTester tester, String key) {
  final found = tester.widget(find.byKey(ValueKey<String>(key)));
  return switch (found) {
    Text(:final String? data) when data != null => data,
    ProvenanceLine(:final String label) => label,
    Text() => throw StateError(
      'The Text at "$key" has no `data` — it was built from a `TextSpan`, so '
      'read the span rather than asking for a string.',
    ),
    _ => throw StateError(
      'The widget at "$key" is a ${found.runtimeType}, which states no text. '
      'If it is a component with a message of its own, read that property.',
    ),
  };
}
