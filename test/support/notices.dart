/// Reading the notice a panel shows after a write.
///
/// Seven surfaces held a `String? _notice` and drew it as a bare `Text`, so
/// every test asserting one read `tester.widget<Text>(...).data` — which is
/// exactly as much as the *screen* said: the sentence, and nothing about whether
/// what the person pressed had happened. They carry an [AppNotice] now, drawn in
/// a [Callout], and a test can ask both questions.
///
/// **Unlike `buttons.dart` and `fields.dart`, this is not a migration seam and
/// should not be deleted.** Those two exist only because `lib/` holds two button
/// systems and two field systems at once; this one reads a component that is the
/// destination rather than a stop on the way to it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/ui/status.dart';
import 'package:flutter_test/flutter_test.dart';

/// The `Callout` a panel drew its notice in.
Callout noticeAt(WidgetTester tester, String key) =>
    tester.widget<Callout>(find.byKey(ValueKey(key)));

/// What the notice says.
String noticeMessage(WidgetTester tester, String key) =>
    noticeAt(tester, key).message;

/// What kind of answer the notice is.
///
/// This is the assertion the old `String?` could not carry, and it is the point
/// of the model: a test that only checks the sentence would pass just as
/// happily if every outcome on the screen were painted as a failure.
AppStatus noticeStatus(WidgetTester tester, String key) =>
    noticeAt(tester, key).status;
