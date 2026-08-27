/// Opening the landing route's navigation drawer, for a test that reaches a
/// destination.
///
/// **The destinations left the home's body on 2026-08-23.** The landing route
/// is the design's dashboard now - figures, the two things a person came to
/// do, recent activity - and every destination is behind the toolbar's
/// hamburger below `expanded`, or in the frame's persistent column at and
/// above it. A test that taps *Change business* or *Manage catalog* therefore
/// has to open the drawer first, exactly as a person does.
///
/// It lives here rather than in each file because six suites reach a
/// destination and a private copy in each is how the six come to disagree
/// about what opening one means.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opens the frame's drawer, if this surface has one.
///
/// **A no-op at `expanded`**, where the destinations are already on screen in
/// the persistent column and there is no hamburger to press. That is what lets
/// one call site serve a test that runs at more than one width.
Future<void> openLandingDrawer(WidgetTester tester) async {
  // `Scaffold`'s own tooltip for the control it adds when a route has a drawer
  // and no way back. Matching on it rather than on an icon keeps this working
  // if the glyph ever changes.
  final hamburger = find.byTooltip(
    const DefaultMaterialLocalizations().openAppDrawerTooltip,
  );
  if (hamburger.evaluate().isEmpty) return;
  await tester.tap(hamburger);
  await tester.pumpAndSettle();
}
