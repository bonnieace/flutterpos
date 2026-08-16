/// `AppSheet`: `design.md` §5.1's row for "ad-hoc `showModalBottomSheet`", and
/// the last of the five components §11 step 7 was blocked on.
///
/// **It is small because v0.8 made it small.** §2.4 used to require a sheet that
/// settled on release *velocity*, which Flutter does not do — honouring it meant
/// a hand-written gesture recogniser and a settling simulation, and §10 says
/// outright that no test here could prove either. The product owner relaxed that
/// to *the nearest detent* on 2026-08-16, which is what `DraggableScrollableSheet`
/// already does, so what is left for this file is the part that was always the
/// point: the surface, the shape, the detents and the handle.
///
/// **What §2.4 still asks for and this still delivers**: the sheet follows the
/// finger 1:1, it rubber-bands, it has more than two positions, and it is dragged
/// rather than tapped. "A sheet that only opens and closes on tap is not the same
/// product" is the sentence that survives, and it is satisfied.
///
/// **Every value here is a §2 row.** `surface.overlay` for the sheet — §2.1's own
/// entry reads "dialogs, menus, **bottom sheets**" — `radius.lg` for its top
/// corners, which is §2.3's "dialogs, bottom sheets", and `surface.scrim` behind
/// it. The handle is `border.strong` at `radius.pill`.
///
/// **The state matrix is the detents**, because that is the only thing that
/// varies: a sheet is a container and has no hover, no focus, no disabled and no
/// error of its own. What it holds brings those.
library;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// Where a sheet is allowed to come to rest, as a fraction of the screen.
///
/// **Two resting positions plus dismissal, which is the difference §2.4 is
/// about.** A sheet with only an open and a closed state is a dialog that slid
/// up; being able to drag it taller, and have it stay there, is what makes it a
/// sheet. Dragging below [half] dismisses it, so there are three outcomes to a
/// gesture and two places it can come to rest.
enum AppSheetDetent {
  /// Enough for the sheet's first screenful — the cart's lines and its total.
  ///
  /// **0.7 is the app's own figure rather than a fresh one.** The till's sheet
  /// has opened at exactly this since it was written, and picking 0.6 here
  /// because it sounded like a half moved a working screen for no reason: the
  /// first test to run against it could no longer reach the tender chips,
  /// which had dropped below the fold.
  half(0.7),

  /// Nearly the whole screen, and deliberately not all of it: the scrim stays
  /// visible so the sheet still reads as a layer over the page rather than as a
  /// route that replaced it.
  full(0.95);

  const AppSheetDetent(this.fraction);

  /// The share of the screen's height this detent occupies.
  final double fraction;
}

/// Opens [builder] in a sheet drawn to `design.md` §2.1, §2.3 and §2.4.
///
/// The builder is handed a `ScrollController` and **must** give it to the
/// scrollable it returns, which is what couples the sheet's drag to the
/// content's scroll: without it, dragging the list scrolls the list and the
/// sheet never moves.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required Widget Function(BuildContext context, ScrollController controller)
  builder,
  AppSheetDetent initialDetent = AppSheetDetent.half,
  bool dismissible = true,
}) {
  final tokens = AppTokens.componentOf(context);
  return showModalBottomSheet<T>(
    context: context,
    // The sheet sizes itself, so the route must not cap it at half the screen -
    // which is `showModalBottomSheet`'s default and the reason a tall sheet
    // silently clips.
    isScrollControlled: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    backgroundColor: Colors.transparent,
    barrierColor: tokens.colors.surface.scrim,
    // The handle is drawn here rather than by Material, so it takes §2.1's
    // border colour and §2.3's pill instead of the theme's grey lozenge.
    showDragHandle: false,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: initialDetent.fraction,
      minChildSize: AppSheetDetent.half.fraction,
      maxChildSize: AppSheetDetent.full.fraction,
      // **The detents, and the whole of what v0.8 changed.** The sheet snaps to
      // the nearest of these on release rather than settling on the velocity of
      // the gesture that got there.
      snap: true,
      snapSizes: <double>[
        for (final detent in AppSheetDetent.values) detent.fraction,
      ],
      builder: (context, controller) =>
          _Surface(controller: controller, child: builder(context, controller)),
    ),
  );
}

/// The sheet's own chrome: the surface, the corners and the handle.
final class _Surface extends StatelessWidget {
  const _Surface({required this.controller, required this.child});

  final ScrollController controller;
  final Widget child;

  /// §2.3's row for "dialogs, bottom sheets", on the top corners only — a sheet
  /// is anchored to the bottom edge and rounding the corners it is anchored by
  /// draws a gap the page shows through.
  static BorderRadius radiusOf(AppTokens tokens) => BorderRadius.vertical(
    top: Radius.circular(tokens.radius.lg),
  );

  /// The handle: 32 x 4 at `radius.pill`.
  ///
  /// Named rather than tokenised for the reason `EmptyState.markSize` gives -
  /// `design.md` states no handle size, and inventing `size.dragHandle` would
  /// be inventing a token. 32 and 4 are what Material draws, kept so the
  /// affordance stays the one people already recognise.
  static const Size handleSize = Size(32, 4);

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        // §2.1: "dialogs, menus, bottom sheets".
        color: tokens.colors.surface.overlay,
        borderRadius: radiusOf(tokens),
      ),
      child: Column(
        children: <Widget>[
          // **The handle is outside the content's scroll**, so it stays under
          // the finger while the list moves. It is also the drag target a
          // person aims at when the content itself is scrolled to the top.
          Padding(
            padding: EdgeInsets.symmetric(vertical: tokens.spacing.s12),
            child: Semantics(
              label: 'Drag to resize',
              child: SizedBox(
                width: handleSize.width,
                height: handleSize.height,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.colors.surface.borderStrong,
                    borderRadius: BorderRadius.circular(tokens.radius.pill),
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
