/// What a screen looks like while its data is still being read, per
/// `claude.md` hard rule 5 and `docs/stitch/OPEN_QUESTIONS.md` decision 35.
///
/// **Every one of these is captured with animation disabled, and that is a
/// decision rather than a shortcut.** `page_states_test.dart` records the
/// problem next door: `CircularProgressIndicator` rotates forever, so its
/// captures are one arbitrary frame and "a loading image moving between runs
/// means nothing". A sweeping skeleton has exactly that property. Under
/// `MediaQuery.disableAnimations` the blocks render flat, which is a real state
/// the app ships - it is what a person who has turned animation off actually
/// sees - and it is the same picture every run, so a diff in one of these is a
/// diff worth reading.
///
/// **Two states are therefore deliberately not photographed**, and no picture
/// here should be read as covering them:
///
/// - **The sweep itself.** It is motion, and `claude.md` says outright that the
///   harness "cannot show motion at all".
/// - **The first `motion.skeletonDelay`**, during which a block holds its space
///   and paints nothing. A picture of it is a blank rectangle, which proves
///   neither that the space was reserved nor that the threshold was honoured.
///   `test/ui/skeleton_test.dart` asserts both.
///
/// **What these do prove** is the thing decision 35 is actually about: which
/// parts of each screen are drawn for real while the read is outstanding. The
/// till's search field, the sales report's receipt search, its date button and
/// its pagination are all in these frames as themselves.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/skeleton.dart';
import 'package:flutter_application_1/ui/tokens.dart';

import 'fakes.dart';
import 'harness.dart';

void main() {
  screenshotCase(
    '97-till-reading-its-catalog',
    // The screen the whole change was reported against. Captured in every band
    // for the reason the till's own cases are: `showsTwoPanes` decides whether
    // the cart sits beside the products, and the placeholder grid has to reserve
    // the same room the real one takes in both arrangements.
    build: () => _still(
      inSession(
        const TenantCheckoutScreen(cache: _NeverAnswers(), drafts: null),
        controller: seedSession(role: TenantRole.cashier, uid: cashierUid),
      ),
    ),
    viewports: responsiveViewports,
  );

  screenshotCase(
    '97-records-reading-cards',
    // §4.3's compact and medium bands: one card per record, stacked or two to
    // a row.
    build: () => _still(const _RecordHost()),
    viewports: <ScreenshotViewport>[mobileViewport, tabletViewport],
    fullPage: false,
  );

  screenshotCase(
    '97-records-reading-table',
    // §4.3's expanded band, where the same read draws a table instead - header
    // rule included, because a table has one and a card list does not.
    build: () => _still(const _RecordHost()),
    viewports: <ScreenshotViewport>[webViewport],
    fullPage: false,
  );
}

/// Renders [child] with animation switched off.
///
/// **Copied from the ambient `MediaQuery` rather than replaced.** A bare
/// `MediaQueryData` here would wipe the viewport size along with everything
/// else, and both of these subjects ask which §4.1 band they are in - so every
/// capture would silently come out at `compact`.
Widget _still(Widget child) => Builder(
  builder: (context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: true),
    child: child,
  ),
);

/// A catalog read that never answers, so the till holds its loading state for
/// the camera. Nothing else in the app can produce that frame on demand: the
/// real cache reads a Hive box and resolves in one microtask.
final class _NeverAnswers implements CheckoutCatalogSource {
  const _NeverAnswers();

  @override
  Future<CheckoutCatalogSnapshot?> read({
    required String uid,
    required String tenantId,
  }) => Completer<CheckoutCatalogSnapshot?>().future;
}

final class _RecordHost extends StatelessWidget {
  const _RecordHost();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Scaffold(
      backgroundColor: tokens.colors.surface.base,
      body: Padding(
        padding: EdgeInsets.all(tokens.spacing.s20),
        child: const SkeletonGroup(
          semanticLabel: 'Reading the records.',
          child: RecordListSkeleton(),
        ),
      ),
    );
  }
}
