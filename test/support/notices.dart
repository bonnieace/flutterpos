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
import 'package:uzapay_pos/ui/dialogs.dart';
import 'package:uzapay_pos/ui/snackbar.dart';
import 'package:uzapay_pos/ui/status.dart';
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

/// The [AppNotice] in the snack bar currently up, whoever put it there.
///
/// **Found by type rather than by key, and that is a property of the
/// component.** A snack bar is a route of the `ScaffoldMessenger`'s rather than
/// part of the panel that asked for it, so it carries no key of that panel's to
/// look it up by. There is only ever one: `showAppSnackBar` replaces rather
/// than queues, precisely so a till never shows a stale sentence about money.
AppNotice snackNotice(WidgetTester tester) =>
    tester.widget<AppSnackBar>(find.byType(AppSnackBar)).notice;

/// The [AppNotice] in the [NoticeDialog] currently up.
///
/// The third of the app's three notice surfaces. A `Callout` is found by the
/// key its page gave it, a snack bar by type because it belongs to the
/// messenger rather than the page - and this by type for the same reason: it is
/// a route of its own, and only one can be up at a time.
AppNotice dialogNotice(WidgetTester tester) =>
    tester.widget<NoticeDialog>(find.byType(NoticeDialog)).notice;
