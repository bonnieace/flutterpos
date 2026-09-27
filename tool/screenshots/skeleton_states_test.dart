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
import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:uzapay_pos/inventory/inventory.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:uzapay_pos/ui/skeleton.dart';
import 'package:uzapay_pos/ui/tokens.dart';

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

  // The three routes that were still on the guard's spinner until 2026-08-28,
  // at the developer's report. Each is captured in every band, because each
  // changes shape across §4.1: the catalog draws cards on a phone and a table
  // on a desk, the ledger's placeholder asks `RecordList` the same question its
  // content will, and both filter rows fold from a row into a column.
  screenshotCase(
    '97-inventory-reading-its-catalog',
    build: () => _still(
      inSession(
        TenantCatalogManagementScreen(
          reader: const _NeverReads(),
          // Wired because `main.dart` wires it, and it decides the shape of the
          // action header a phone draws: one full-width control over a pair,
          // rather than a pair on its own.
          bulkRoute: (_) => const SizedBox.shrink(),
        ),
      ),
    ),
    viewports: responsiveViewports,
  );

  screenshotCase(
    '97-product-stock-reading',
    // Almost all of this screen is page rather than read, which is the point of
    // the picture: both explanations, the heading and the SKU row are drawn for
    // real while the two figures and the ledger are still outstanding.
    build: () => _still(
      inSession(
        TenantProductStockScreen(
          reader: const _NeverReads(),
          product: seedProduct('pd-bar-soap-blue'),
        ),
      ),
    ),
    viewports: responsiveViewports,
  );

  screenshotCase(
    '97-staff-reading-its-directory',
    // **The one that was reported as a jitter rather than as a spinner.** This
    // route builds its `AppScaffold` below the guard, so the loading phase used
    // to have no toolbar, no title and no way back; what this frame proves is
    // that the chrome is now there before the directory is.
    build: () => _still(
      inSession(
        const TenantStaffDirectoryScreen(reader: _NeverReads()),
        controller: seedSession(role: TenantRole.admin, uid: adminUid),
      ),
    ),
    viewports: responsiveViewports,
  );
}

/// A tenant read that never answers, so a guarded route holds its loading state
/// for the camera.
///
/// **The same trick [_NeverAnswers] plays on the till, at the boundary the rest
/// of the app reads through.** `FakeTenantReader` resolves in a microtask, which
/// is the right behaviour for every other capture and makes this frame
/// impossible to photograph.
final class _NeverReads
    implements TenantDataReader, TenantStaffDirectoryQueryReader {
  const _NeverReads();

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) =>
      Completer<TenantDocumentSnapshot?>().future;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) => Completer<List<TenantQueryDocumentSnapshot>>().future;

  @override
  Future<List<TenantQueryDocumentSnapshot>> queryTenantStaff(
    TenantStaffDirectoryQuery query,
  ) => Completer<List<TenantQueryDocumentSnapshot>>().future;
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
