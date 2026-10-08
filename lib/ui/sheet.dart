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
/// error of its own. What it holds brings those - and its close control, which
/// is an [AppIconButton] and brings that component's.
///
/// **Every sheet carries a close control at its top right**, at the
/// developer's direction on 2026-10-05. No drag dismisses a sheet and a form's
/// scrim may not either, so without it the way out was whatever button the
/// content happened to end on, sometimes a scroll away.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'buttons.dart';
import 'tokens.dart';

/// Where a sheet is allowed to come to rest, as a fraction of the screen.
///
/// **Two resting positions, which is the difference §2.4 is about.** A sheet
/// with only an open and a closed state is a dialog that slid up; being able to
/// drag it taller, and have it stay there, is what makes it a sheet.
///
/// **A drag settles, it never dismisses**, at the developer's direction on
/// 2026-09-23. Up reaches [full], down returns to [half], and that is the whole
/// of what the gesture can do — see [showAppSheet] for why.
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
///
/// **[masthead] fills the sheet's own top corners**, and is for a sheet whose
/// subject is a picture: a product photograph, not a form field about one. See
/// [AppSheetMasthead] for why it is drawn by this component rather than by the
/// caller.
///
/// **No drag dismisses a sheet**, at the developer's direction on 2026-09-23.
/// The two mechanisms overlapped: the inner [DraggableScrollableSheet] owns the
/// span between the detents, and the route's own drag owned everything below
/// [AppSheetDetent.half]. So a flick down that was meant to return a sheet from
/// full to half ran out of detent halfway through and carried straight on into
/// the route's handler, throwing away whatever had been filled in. The inner
/// drag is what a person is aiming at, and it is now the only one: up for
/// [AppSheetDetent.full], down for [AppSheetDetent.half], and nothing further.
///
/// [dismissible] is therefore about the scrim alone — whether a tap outside the
/// sheet closes it. A sheet holding a form people can lose work in passes
/// false and offers a cancel control of its own; a sheet holding a paragraph
/// leaves it true, because making someone hunt for a control to dismiss a
/// glossary is its own kind of trap.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required Widget Function(BuildContext context, ScrollController controller)
  builder,
  WidgetBuilder? masthead,
  double mastheadFraction = AppSheetMasthead.fraction,
  bool mastheadSquare = false,
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
    // The route's own drag, and the one that used to cancel the sheet out from
    // under a half-finished form. See this function's doc comment.
    enableDrag: false,
    backgroundColor: Colors.transparent,
    barrierColor: tokens.colors.surface.scrim,
    // The handle is drawn here rather than by Material, so it takes §2.1's
    // border colour and §2.3's pill instead of the theme's grey lozenge.
    showDragHandle: false,
    builder: (context) => _AboveTheKeyboard(
      child: DraggableScrollableSheet(
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
        // **The second way a drag could close a sheet, and the one that
        // survived turning `enableDrag` off.** This defaults to true, and it
        // is not about the route's gesture detector at all: reaching
        // [minChildSize] makes the inner sheet emit a
        // `DraggableScrollableNotification` asking its parent to close, which
        // `showModalBottomSheet` obeys. So the sheet still went away on a drag
        // down from full, and on the far commoner gesture of scrolling the
        // content up and then back down - the scrollable takes that one, so it
        // never touches the route's own detector and turning that off did
        // nothing to it. Reported from a device on 2026-09-23.
        //
        // False makes [minChildSize] what it reads as: the bottom of the
        // sheet's travel, not a trapdoor at the end of it.
        shouldCloseOnMinExtent: false,
        builder: (context, controller) => _Surface(
          controller: controller,
          masthead: masthead,
          mastheadFraction: mastheadFraction,
          mastheadSquare: mastheadSquare,
          child: builder(context, controller),
        ),
      ),
    ),
  );
}

/// Gives the sheet the screen that is left once the keyboard has taken its
/// share, rather than the screen the keyboard is sitting on top of.
///
/// **The defect this fixes, reported on a device on 2026-09-02**: a sheet is
/// anchored to the bottom of the *screen*, and the keyboard covers the bottom
/// of the screen. Every detent is a fraction of a height that does not account
/// for it, so the pinned action bar and the last field or two of any form
/// were underneath the keys - and the amount someone was typing was one of the
/// things they could not see while typing it.
///
/// **A plain [Padding], deliberately not an animated one.** `viewInsets.bottom`
/// is reported progressively while the keyboard travels, so tracking it
/// directly makes the sheet move *with* the keys rather than chasing them. An
/// animation on top of that would be a second, slower opinion about a movement
/// the platform is already driving - and the motion rule's demand that a
/// spatial change be interruptible from its current position is met exactly by
/// having no animation of our own to interrupt.
///
/// **The inset is removed from what the sheet sees**, the way `Scaffold` does
/// when `resizeToAvoidBottomInset` consumes it: it has been spent here, and a
/// descendant that padded by it again would leave a second keyboard's worth of
/// empty space above the real one.
///
/// **The shape of this tree never changes, and that is the whole of the
/// 2026-09-03 fix.** The first version of this returned `child` unchanged while
/// there was no keyboard and a `Padding` once there was one, so the moment
/// `viewInsets.bottom` crossed zero the child's `runtimeType` changed,
/// `Widget.canUpdate` refused, and Flutter deactivated and re-inflated the
/// entire sheet - the `DraggableScrollableSheet`, the list, and every field in
/// it. A field disposed the instant it is focused takes its `FocusNode` and its
/// `EditableText`'s platform input connection with it, so the keyboard rose,
/// the subtree died, the keyboard fell, and the sheet snapped back to its
/// opening detent. Nothing could be typed into a sheet at all.
///
/// It is the same defect `AppFieldWell` already carries a paragraph about - see
/// `fields.dart`, "a field that changed the shape of the tree above its
/// `TextField` the instant it was focused would re-parent that `TextField` ...
/// and drop the platform input connection" - one layer further up. The cure is
/// the same one: emit the wrapper unconditionally and let it be a no-op. A
/// `Padding` of zero pads nothing and a `removeViewInsets` over an inset that
/// is already zero removes nothing, so a sheet with no keyboard in front of it
/// renders exactly as it did before.
final class _AboveTheKeyboard extends StatelessWidget {
  const _AboveTheKeyboard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: MediaQuery.removeViewInsets(
      context: context,
      removeBottom: true,
      child: child,
    ),
  );
}

/// A band that fills the top of a sheet, under its own corners.
///
/// **It is the component's rather than the caller's, because the corners are.**
/// A caller drawing its own picture at the top of a sheet would have to know
/// [_Surface.radiusOf] to clip to it, and would then own a copy of §2.3's row
/// that goes stale the first time the radius moves. So the sheet clips, and the
/// caller supplies only what goes inside.
///
/// **The drag handle moves on top of it**, which is the other half of why this
/// is here. The handle normally sits in a strip of its own above the content;
/// over a masthead that strip would be a bar of surface colour between the
/// sheet's edge and the picture, which is exactly the "double card" this exists
/// to avoid. It is overlaid instead, on a scrim, so it stays visible over a
/// photograph of any brightness — §9's contrast rule does not stop applying
/// because the background is an image.
abstract final class AppSheetMasthead {
  /// What share of the sheet's height a masthead takes.
  ///
  /// **A fraction of the sheet rather than an aspect ratio of its width**, at
  /// the product owner's direction on 2026-08-26, and the reason is what it
  /// must not do: an aspect ratio grows with the sheet, so on a wide surface
  /// the picture pushes the fields it belongs to off the bottom. A fraction
  /// cannot — the form always starts in the same place, whatever the screen.
  ///
  /// 0.3 leaves the majority of the sheet to the form, which is what the form
  /// is for.
  static const double fraction = 0.3;

  /// The scrim behind the drag handle, so it reads against a light photograph.
  ///
  /// Named here rather than tokenised for the reason [_Surface.handleSize] is:
  /// `design.md` states no such value, and inventing one would be inventing a
  /// token. It is the surface scrim at a third of its strength — enough to
  /// separate a 4px bar from a photograph, not enough to read as a band.
  static const double handleScrimOpacity = 0.2;

  /// The most of the sheet a square masthead may take, so the rows under a
  /// photograph keep a third of it on a short or a wide screen.
  ///
  /// **For a sheet whose subject is the photograph itself**, the product photo
  /// sheet, where the picture is drawn as wide as the sheet and as tall as it is
  /// wide. On a phone at [AppSheetDetent.half] that is the whole width, square;
  /// on a tablet, where the sheet is wider than it is tall, this caps it.
  static const double squareCeiling = 2 / 3;
}

/// The sheet's own chrome: the surface, the corners and the handle.
final class _Surface extends StatelessWidget {
  const _Surface({
    required this.controller,
    required this.child,
    this.masthead,
    this.mastheadFraction = AppSheetMasthead.fraction,
    this.mastheadSquare = false,
  });

  final ScrollController controller;
  final Widget child;

  /// See [AppSheetMasthead]. Null draws the ordinary handle-above-content
  /// arrangement, which is what every sheet in the app had before 2026-08-26.
  final WidgetBuilder? masthead;

  final double mastheadFraction;

  /// Whether the masthead is as tall as the sheet is wide, with
  /// [mastheadFraction] as its ceiling rather than its height.
  final bool mastheadSquare;

  /// §2.3's row for "dialogs, bottom sheets", on the top corners only — a sheet
  /// is anchored to the bottom edge and rounding the corners it is anchored by
  /// draws a gap the page shows through.
  static BorderRadius radiusOf(AppTokens tokens) =>
      BorderRadius.vertical(top: Radius.circular(tokens.radius.lg));

  /// The handle: 32 x 4 at `radius.pill`.
  ///
  /// Named rather than tokenised for the reason `EmptyState.markSize` gives -
  /// `design.md` states no handle size, and inventing `size.dragHandle` would
  /// be inventing a token. 32 and 4 are what Material draws, kept so the
  /// affordance stays the one people already recognise.
  static const Size handleSize = Size(32, 4);

  /// Where ink and `ListTile` backgrounds are painted.
  ///
  /// **A sheet had no `Material` in it until 2026-08-26, and nothing noticed
  /// because nothing in one needed it.** The sheets this component was written
  /// for hold buttons and text, and `AppButton` draws its own press states
  /// through `PressSurface`. Moving the product forms in brought `ListTile`,
  /// which paints its background and its splash on the nearest `Material`
  /// ancestor - and finding none above a `DecoratedBox`, Flutter asserts that
  /// both will be invisible.
  ///
  /// `MaterialType.transparency` rather than a surface: the colour is already
  /// painted by the box around this, and a second opaque layer would be a
  /// second card. It provides the ink target and nothing else.
  static Widget _inkable(Widget child) =>
      Material(type: MaterialType.transparency, child: child);

  /// The close control, at the top right of every sheet.
  ///
  /// **`maybePop`, so it is a back gesture and not a trapdoor**: a sheet that
  /// guards itself with a `PopScope` - mid-save, say - refuses it the way it
  /// refuses the system back. It answers null, which every caller already reads
  /// as cancelled, because the scrim has always answered the same.
  ///
  /// **The headings' ink, not the tier's green**, at the developer's direction
  /// on 2026-10-05: green is the colour of an action that does something, and
  /// closing a sheet does nothing to anything.
  Widget _close(BuildContext context) => AppIconButton(
    key: const ValueKey('app-sheet-close'),
    icon: Icons.close,
    semanticLabel: 'Close',
    tier: AppButtonTier.tertiary,
    bordered: false,
    glyphColor: AppTokens.componentOf(context).colors.text.primary,
    onPressed: () => Navigator.of(context).maybePop(),
  );

  /// The bar itself, without the strip it normally sits in.
  Widget _handle(AppTokens tokens) => Semantics(
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
  );

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final banner = masthead;
    if (banner == null) {
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
            //
            // The close control shares its strip rather than floating over the
            // content, where it would sit on the end of a long title. The strip
            // is the control's own height, and the handle keeps its place at
            // the top of it.
            Stack(
              alignment: Alignment.topCenter,
              children: <Widget>[
                Padding(
                  padding: EdgeInsets.only(top: tokens.spacing.s12),
                  child: _handle(tokens),
                ),
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: tokens.spacing.s4,
                      right: tokens.spacing.s8,
                    ),
                    child: _close(context),
                  ),
                ),
              ],
            ),
            Expanded(child: _inkable(child)),
          ],
        ),
      );
    }

    // **`ClipRRect` rather than a `DecoratedBox`'s own radius**, because the
    // masthead paints to the sheet's edge and a decoration only rounds what it
    // draws itself - a picture inside it would square off the corners again.
    //
    // **`LayoutBuilder` for the height, and it is the honest measure.** These
    // constraints are the sheet's current extent, which is what a fraction of
    // "the sheet" has to mean while it is being dragged between detents.
    return ClipRRect(
      borderRadius: radiusOf(tokens),
      child: ColoredBox(
        color: tokens.colors.surface.overlay,
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            children: <Widget>[
              SizedBox(
                height: mastheadSquare
                    ? math.min(
                        constraints.maxWidth,
                        constraints.maxHeight * mastheadFraction,
                      )
                    : constraints.maxHeight * mastheadFraction,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    banner(context),
                    // The handle over the picture rather than above it: a strip
                    // of surface between the sheet's edge and the image is the
                    // second card this arrangement exists to remove.
                    Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: EdgeInsets.only(top: tokens.spacing.s12),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: tokens.colors.surface.scrim.withValues(
                              alpha: AppSheetMasthead.handleScrimOpacity,
                            ),
                            borderRadius: BorderRadius.circular(
                              tokens.radius.pill,
                            ),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(tokens.spacing.s4),
                            child: _handle(tokens),
                          ),
                        ),
                      ),
                    ),
                    // **On the sheet's own surface, not the handle's scrim.** A
                    // glyph has to hold §9's contrast over a photograph of any
                    // brightness, and a fifth of the scrim does that for a bar,
                    // not for a cross someone has to read.
                    Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: EdgeInsets.only(
                          top: tokens.spacing.s4,
                          right: tokens.spacing.s8,
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: tokens.colors.surface.overlay,
                            borderRadius: BorderRadius.circular(
                              tokens.radius.md,
                            ),
                          ),
                          child: _close(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: _inkable(child)),
            ],
          ),
        ),
      ),
    );
  }
}
