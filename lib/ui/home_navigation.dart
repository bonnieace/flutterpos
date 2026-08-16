/// `HomeNavigation`: `design.md` §11 step **5b**, first half.
///
/// **This is §4.4 after v0.5 replaced it, and the replacement is why the
/// component exists at all.** The section opened by objecting to a `Wrap` of
/// eleven identical pills, and its original answer was a bottom bar with four
/// destinations. That answer was drawn before it was rejected: mapping this
/// route's eleven controls onto *Sell / Stock / Money / More* put **five of them
/// in `More`**, which made the overflow bucket the largest destination in the
/// app against one control in *Sell*. v0.5 replaced it with a card grid below
/// 1024 and a side menu at or above it, and **no overflow bucket at any band**
/// is the property it exists to hold.
///
/// **One component, two renderings, chosen by band** - §4.3's own construction,
/// the same one `RecordList` is built on. The route stack is identical either
/// side of the boundary, so a window dragged across 1024 changes the shape of
/// the navigation and nothing about where a person is.
///
/// **What a card does that a pill could not is carry its own condition.**
/// [HomeDestination.status] is the whole argument for this model over a tab bar:
/// a badge counts, where a line of words can say *3 unresolved differences* or
/// *shift open, 17 sales* on the surface a person is already looking at. A card
/// with no status is a button, and eleven of those is what §4.4 opened by
/// objecting to.
///
/// **Every measurement here is read from a §2 row written for something else**,
/// which is the treatment `AppSelect` and `Callout` already take and which
/// `PLAN.md` carries as an open question against §5.2 rather than this file:
/// `radius.md`, `surface.raised` and a `border.subtle` hairline from §2.3's and
/// §2.1's "cards, rows, sheets" rows, which is what a card is made of everywhere
/// else in this app; `space.16` for padding and for the gutter §4.4 names;
/// `title.md` for the label, which §2.2 gives to "card title"; `caption` /
/// `text.tertiary` for the status line. The glyph is **18**, which is §5.2's
/// leading-icon row and the nearest named size - the same borrowing `Callout`,
/// `Disclosure` and `RecordActionSet` each made.
///
/// **The one figure with no row anywhere is the menu's width.** §4.2 states
/// content maxima and §2.3's scale stops at 64; neither describes a navigation
/// column. [_menuWidth] is a component decision on that scale and is recorded in
/// `PLAN.md` beside `AppScaffold.horizontalInset`, which is the same gap and was
/// answered the same way.
///
/// **What this half does not do is make the menu persistent.** §4.4 puts it in
/// `AppScaffold` so it draws on every route without a nested `Navigator`; here
/// it draws on the home only. Lifting it is step 5b's second half, and it is a
/// sweep across every migrated route's expanded screenshot rather than a
/// component change.
library;

import 'package:flutter/material.dart';

import 'press.dart';
import 'tokens.dart';

/// One place the home can send a person, and what it can say about that place
/// before they go.
///
/// **[onPressed] is nullable and that is a state rather than a refusal.** The
/// home carries one control - *Default business* - which is disabled because the
/// business already is the default, so there is nothing to press. §2.1's
/// disabled row paints it; it is not an error and says nothing about permission.
/// A destination a session may not reach is not built at all, which is the
/// caller's decision and stays the caller's.
final class HomeDestination {
  const HomeDestination({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.status,
    this.isPrimary = false,
    this.destinationKey,
  });

  /// What the destination is called, in the shopkeeper's words. §8 rule 3: a
  /// control names its effect.
  final String label;

  /// The glyph beside the label, at 18.
  final IconData icon;

  /// What pressing it does. Null renders §2.1's disabled row and takes the
  /// press, the hover and the focus with it.
  final VoidCallback? onPressed;

  /// This destination's own condition, in words - *3 unresolved differences*,
  /// *shift open, 17 sales*, *2 waiting to send*.
  ///
  /// **Optional in the strong sense.** A status that restates the label is
  /// noise, and §8 rule 2 asks a screen to state what is true rather than what
  /// is available. Give it a line only where the destination knows something the
  /// person has not been told yet.
  final String? status;

  /// Whether this is the one `action.primary` §2.1 permits per screen region.
  ///
  /// **Exactly one destination sets it, and §4.4 names which**: *New sale*. It
  /// ceases to be a button among eleven by outranking them rather than by
  /// leaving the page, which is the half of the original model v0.5 kept.
  final bool isPrimary;

  /// A key for the rendered card or menu row, so a test and a screenshot can
  /// reach a destination by name rather than by position.
  final Key? destinationKey;
}

/// The home's navigation: a card grid below 1024, a side menu at or above it.
final class HomeNavigation extends StatelessWidget {
  const HomeNavigation({super.key, required this.destinations});

  /// Everywhere the home can go, in the order §4.4 asks for: the primary first,
  /// then by frequency. **Never alphabetically** - that is the ordering a `Wrap`
  /// of identical pills has, and it is the one this section replaced.
  final List<HomeDestination> destinations;

  /// A side menu's width. See the library note: a component decision, not a
  /// token, because no section of `design.md` describes a navigation column.
  static const double _menuWidth = 256;

  /// How many columns a band's card grid has. §4.4's table.
  ///
  /// Exposed so a test can ask the question the widget asks rather than
  /// asserting a pixel width and hoping the two agree - the same reason
  /// `PageHeader.showsDisplayTitle` is a static.
  static int columnsFor(AppBreakpoint band) =>
      band == AppBreakpoint.compact ? 2 : 3;

  /// Whether [screenWidth] draws the menu instead of the grid.
  static bool showsMenu(double screenWidth) =>
      AppLayout.contract.isAtLeast(screenWidth, AppBreakpoint.expanded);

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final width = MediaQuery.sizeOf(context).width;
    // A screen's width, not this widget's box. §4.1's bands describe the
    // surface a person is looking at, and resolving them inside an already
    // padded page invents a fourth boundary by arithmetic - `PageHeader` says
    // the same thing at more length and for the same reason.
    final band = tokens.layout.breakpointOf(width);

    // A role with no destinations at all draws nothing rather than an empty
    // frame. §5.1 gives that case to `EmptyState`, which does not exist; a
    // bordered box containing nothing would be a fourth implementation of one.
    if (destinations.isEmpty) return const SizedBox.shrink();

    if (band == AppBreakpoint.expanded) {
      return _HomeMenu(destinations: destinations, tokens: tokens);
    }
    return _HomeGrid(
      destinations: destinations,
      columns: columnsFor(band),
      tokens: tokens,
    );
  }
}

/// The card grid, at `compact` and `medium`.
final class _HomeGrid extends StatelessWidget {
  const _HomeGrid({
    required this.destinations,
    required this.columns,
    required this.tokens,
  });

  final List<HomeDestination> destinations;
  final int columns;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    final gutter = tokens.spacing.s16;
    final primary = destinations.where((d) => d.isPrimary).toList();
    final rest = destinations.where((d) => !d.isPrimary).toList();
    final rows = <Widget>[];

    // The primary spans the row it is on, at every band. §4.4: it outranks the
    // others rather than leaving the page, and a mint card the width of two is
    // how that reads on a phone.
    for (final destination in primary) {
      rows.add(_HomeCard(destination: destination, tokens: tokens));
    }

    // **Rows of `Expanded`, not a `Wrap`.** A `Wrap` sizes each child to its own
    // content, so a row of cards whose labels differ in length comes out ragged
    // and the grid stops being a grid. Building the rows explicitly is what
    // makes every column the same width, and padding the last row with an empty
    // slot is what stops a lone trailing card stretching across the page.
    for (var start = 0; start < rest.length; start += columns) {
      final slice = rest.skip(start).take(columns).toList();
      rows.add(
        // **`IntrinsicHeight`, because a grid whose cards are different heights
        // is not a grid.** `CrossAxisAlignment.stretch` alone asks the `Row` for
        // its own height, and this column sits inside a scroll view, so that
        // height is unbounded - which is an infinite-constraint crash rather
        // than a ragged row. Wrapping bounds it to the tallest card, which is
        // what "the same width and the same height" needs. It is an O(n) layout
        // pass over at most three children.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (var column = 0; column < columns; column++) ...<Widget>[
                if (column > 0) SizedBox(width: gutter),
                Expanded(
                  child: column < slice.length
                      ? _HomeCard(
                          destination: slice[column],
                          tokens: tokens,
                          stretchHeight: true,
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var index = 0; index < rows.length; index++) ...<Widget>[
          if (index > 0) SizedBox(height: gutter),
          rows[index],
        ],
      ],
    );
  }
}

/// One destination as a card.
///
/// **The states are `PressSurface`'s, deliberately.** Hover, pressed and
/// focus-visible are §2.1's overlay rows and §9's ring, and every other
/// pressable surface in this app gets them from the same widget. Painting them
/// here would be a second opinion about what a press looks like. `disabled` is
/// this component's, because `PressSurface` refuses it on the stated grounds
/// that a component knows what its own disabled label looks like.
final class _HomeCard extends StatelessWidget {
  const _HomeCard({
    required this.destination,
    required this.tokens,
    this.stretchHeight = false,
  });

  final HomeDestination destination;
  final AppTokens tokens;

  /// Whether this card fills the height it is offered.
  ///
  /// **True inside a row, false for the primary, and the asymmetry is a
  /// constraint rather than a preference.** A row is wrapped in
  /// `IntrinsicHeight`, so its maximum height is bounded and `double.infinity`
  /// resolves to the tallest card in that row - which is what makes the pair
  /// match. The primary sits directly in a `Column`, where the main axis is
  /// unbounded and asking for infinite height is a crash rather than a stretch.
  final bool stretchHeight;

  @override
  Widget build(BuildContext context) {
    final enabled = destination.onPressed != null;
    final colors = tokens.colors;
    final role = destination.isPrimary
        ? colors.action.primary
        : colors.action.secondary;

    final Color container;
    final Color foreground;
    final Color? edge;
    if (!enabled) {
      // §2.1's disabled row, both tiers: container `#1E3A2B`, label `#5D7468`.
      container = colors.surface.field;
      foreground = colors.text.disabled;
      edge = colors.surface.borderSubtle;
    } else if (destination.isPrimary) {
      container = role.container;
      foreground = role.label;
      edge = null;
    } else {
      // The ordinary card is `surface.raised` with a hairline, which is what a
      // card is made of everywhere else here - not `action.secondary`'s
      // transparent container, because this is a card that is pressable rather
      // than a button that is card-shaped.
      container = colors.surface.raised;
      foreground = colors.text.primary;
      edge = colors.surface.borderSubtle;
    }

    final radius = BorderRadius.circular(tokens.radius.md);
    final body = Container(
      // **`PressSurface.fillWidth` fills the hit area, not the paint.** Its
      // `Align` hands the child loose constraints, so without this the card
      // shrink-wraps its label and floats in the middle of a slot that is the
      // right width - which measures correctly and looks wrong, and is exactly
      // what the first screenshot of this component showed.
      width: double.infinity,
      height: stretchHeight ? double.infinity : null,
      decoration: BoxDecoration(
        color: container,
        borderRadius: radius,
        border: edge == null ? null : Border.all(color: edge),
      ),
      padding: EdgeInsets.all(tokens.spacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(destination.icon, size: 18, color: foreground),
          SizedBox(height: tokens.spacing.s12),
          Text(
            destination.label,
            style: tokens.typography.titleMedium.copyWith(color: foreground),
          ),
          if (destination.status case final line?) ...<Widget>[
            SizedBox(height: tokens.spacing.s4),
            Text(
              line,
              style: tokens.typography.caption.copyWith(
                // On the mint card the caption reads against `action.primary`'s
                // own label colour; `text.tertiary` is a page colour and would
                // be close to invisible there.
                color: destination.isPrimary
                    ? foreground
                    : enabled
                    ? colors.text.tertiary
                    : foreground,
              ),
            ),
          ],
        ],
      ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: destination.status == null
          ? destination.label
          : '${destination.label}. ${destination.status}',
      child: ExcludeSemantics(
        child: PressSurface(
          key: destination.destinationKey,
          borderRadius: radius,
          onPressed: destination.onPressed,
          hoverOverlay: role.hoverFill(),
          pressedOverlay: role.pressedFill(),
          minimumTapTarget: tokens.density.minimumTapTarget,
          // **Both, and neither is cosmetic.** Without `fillWidth` the primary
          // card shrink-wraps its label and floats in the middle of the row it
          // is supposed to span; without `fillHeight` two cards beside each
          // other are centred at different heights inside slots that *are* the
          // same height, which is a grid that only measures like a grid.
          fillWidth: true,
          fillHeight: true,
          child: body,
        ),
      ),
    );
  }
}

/// The side menu, at `expanded`.
///
/// **Every destination is labelled and none is hidden**, which is the whole
/// reason §4.4 chose a menu here rather than carrying the grid up: a column has
/// room to name eleven things where a bottom bar has room for four and a bucket.
final class _HomeMenu extends StatelessWidget {
  const _HomeMenu({required this.destinations, required this.tokens});

  final List<HomeDestination> destinations;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) => Align(
    // **`Align` first, and it is not decoration.** A vertical scroll view hands
    // its child a *tight* width, and a `SizedBox` cannot shrink under a tight
    // constraint - the menu came out 1156 wide in its own first screenshot.
    // `Align` re-loosens the constraint so the width below is the width drawn,
    // and starts the column at the leading edge rather than centring a
    // navigation column in the middle of the page.
    alignment: AlignmentDirectional.centerStart,
    child: SizedBox(
      width: HomeNavigation._menuWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var index = 0; index < destinations.length; index++) ...<Widget>[
            if (index > 0) SizedBox(height: tokens.spacing.s8),
            _HomeMenuRow(destination: destinations[index], tokens: tokens),
          ],
        ],
      ),
    ),
  );
}

/// One destination as a menu row.
final class _HomeMenuRow extends StatelessWidget {
  const _HomeMenuRow({required this.destination, required this.tokens});

  final HomeDestination destination;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    final enabled = destination.onPressed != null;
    final colors = tokens.colors;
    final role = destination.isPrimary
        ? colors.action.primary
        : colors.action.secondary;

    final Color container;
    final Color foreground;
    if (!enabled) {
      container = colors.surface.field;
      foreground = colors.text.disabled;
    } else if (destination.isPrimary) {
      container = role.container;
      foreground = role.label;
    } else {
      container = Colors.transparent;
      foreground = colors.text.secondary;
    }

    final radius = BorderRadius.circular(tokens.radius.md);
    final row = Container(
      decoration: BoxDecoration(color: container, borderRadius: radius),
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.s16,
        vertical: tokens.spacing.s12,
      ),
      child: Row(
        children: <Widget>[
          Icon(destination.icon, size: 18, color: foreground),
          SizedBox(width: tokens.spacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  destination.label,
                  style: tokens.density
                      .body(tokens.typography)
                      .copyWith(color: foreground),
                ),
                if (destination.status case final line?)
                  Text(
                    line,
                    style: tokens.typography.caption.copyWith(
                      color: destination.isPrimary || !enabled
                          ? foreground
                          : colors.text.tertiary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: destination.status == null
          ? destination.label
          : '${destination.label}. ${destination.status}',
      child: ExcludeSemantics(
        child: PressSurface(
          key: destination.destinationKey,
          borderRadius: radius,
          onPressed: destination.onPressed,
          hoverOverlay: role.hoverFill(),
          pressedOverlay: role.pressedFill(),
          minimumTapTarget: tokens.density.minimumTapTarget,
          // A menu row spans the column it is in. It does not fill height -
          // rows are as tall as what they say.
          fillWidth: true,
          child: row,
        ),
      ),
    );
  }
}
