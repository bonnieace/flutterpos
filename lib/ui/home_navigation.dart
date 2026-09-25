/// `HomeNavigation`: the landing route's destinations, as one column of rows.
///
/// **The destinations left the body on 2026-08-23, at the product owner's
/// direction.** The home used to *be* its navigation - first a `Wrap` of
/// eleven pills, then a card grid, then a column of full-width rows - and the
/// design it is now built to does none of those: `manager_dashboard` puts
/// figures, two calls to action and recent activity in the body, and reaches
/// its destinations through the top bar's `menu` button. So this component
/// draws one thing in two hosts:
///
/// - **[HomeNavigation.drawer]** at `compact` and `medium`, inside
///   `AppScaffold`'s drawer, opened from the toolbar's own hamburger.
/// - **[HomeNavigation.menu]** at `expanded`, as the persistent column the
///   export's desktop sidebar draws beside the page.
///
/// Both are the same rows, so a window dragged across 1024 changes where the
/// navigation lives and nothing about what is in it.
///
/// **A bottom bar was the other candidate and was not taken.** The export's
/// `manager_dashboard` render has one - *Sale / Orders / History / Sync* - and
/// four slots cannot hold an owner's eleven destinations without an overflow
/// bucket larger than the bar. A drawer holds all of them, named, which is the
/// property this component has had since it replaced the pills. The product
/// owner chose the drawer over the bar on 2026-08-23.
///
/// **What a row carries beyond its label is its own condition.**
/// [HomeDestination.status] is why this is a menu rather than a tab strip: it
/// can say *2 waiting to send* on the surface a person is already looking at.
///
/// **Every measurement is a role**: `radius.sm` on a row, `space.16` of inset,
/// `body.lg` for the label, `caption` / `text.tertiary` for the condition, and
/// §5.2's named 18 for the glyph. The marked row takes `surface.field` and a
/// four-pixel accent bar, which is the design system's own words for a
/// selection - "a sharp vertical bar (4px wide) ... in Primary Green".
library;

import 'package:flutter/material.dart';

import 'press.dart';
import 'tokens.dart';

/// One place the home can send a person, and what it can say about that place
/// before they go.
///
/// **[onPressed] is nullable and that is a state rather than a refusal.** The
/// home carries one control - *Default business* - which is disabled because
/// the business already is the default, so there is nothing to press. §2.1's
/// disabled row paints it; it is not an error and says nothing about
/// permission. A destination a session may not reach is not built at all,
/// which is the caller's decision and stays the caller's.
final class HomeDestination {
  const HomeDestination({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.status,
    this.isPrimary = false,
    this.badgeCount,
    this.destinationKey,
    this.group,
    this.description,
    this.accent,
  });

  /// The colour this destination's tile wears on [HomeModuleGrid].
  ///
  /// **Chosen per destination, not by position.** Until 2026-09-25 a tile took
  /// the palette colour at its place in the grid, so adding Suppliers and
  /// Production and removing Printer moved the colour of every tile after
  /// them, and a manager's home - which has fewer tiles - never matched the
  /// owner's. Null falls back to the tile's position, for a list with no
  /// colours chosen.
  final AppIdentityAccent? accent;

  /// One sentence saying what is behind this destination, for the surface that
  /// has room to say it.
  ///
  /// **Read by [HomeModuleGrid] and by nothing else.** A menu row is a label
  /// and its own condition; a module card is the old hub's shape and carries a
  /// line of description under the name — *"Process sales, manage orders, and
  /// handle customer transactions."* The two renderings share a destination
  /// list, so the sentence lives here rather than in a second list the grid
  /// would have to keep in step.
  final String? description;

  /// What the destination is called, in the shopkeeper's words. §8 rule 3: a
  /// control names its effect.
  final String label;

  /// The glyph beside the label, at 18.
  final IconData icon;

  /// What pressing it does. Null renders §2.1's disabled row and takes the
  /// press, the hover and the focus with it.
  final VoidCallback? onPressed;

  /// This destination's own condition, in words - *3 unresolved differences*,
  /// *2 waiting to send*.
  ///
  /// **Optional in the strong sense.** A status that restates the label is
  /// noise, and §8 rule 2 asks a screen to state what is true rather than what
  /// is available. Give it a line only where the destination knows something
  /// the person has not been told yet. Where it is absent the row draws a
  /// chevron instead, which is what the export does.
  final String? status;

  /// Whether this is the one `action.primary` §2.1 permits per screen region.
  ///
  /// **Exactly one destination sets it**: *New sale*. It outranks the others
  /// rather than leaving the page - a filled accent row at the top of the
  /// column, which is how the export draws it.
  final bool isPrimary;

  /// How many things are waiting behind this destination, or null where it is
  /// not the kind of destination that counts anything.
  ///
  /// **Not the same as [status], which is a sentence.** *2 waiting to send* is
  /// what a menu row has room to say; a launcher tile has room for a figure on
  /// its glyph and nothing else. A destination that sets this is also drawn in
  /// the problem colour while the figure is above zero and in grey when it is
  /// not, so the tile reads as *something needs doing here* at a glance and as
  /// ordinary the rest of the time.
  ///
  /// **Never colour alone** - §9. The count is the figure, the drawer row
  /// beside it still carries the sentence, and the tile's semantics say both.
  final int? badgeCount;

  /// A key for the rendered row, so a test and a screenshot can reach a
  /// destination by name rather than by position.
  final Key? destinationKey;

  /// The area this destination belongs to, or null for a row that stands on
  /// its own above every heading.
  ///
  /// **This is what turns a list of pages into a menu.** The destinations were
  /// twelve peers in one column, so a person reading them had to know the
  /// product to know which two were the same subject. A group is drawn once,
  /// above the first row that carries it, and every following row with the
  /// same group joins it - so the heading a role sees is derived from the
  /// destinations that role was actually given. **A group whose every
  /// destination is withheld draws no heading at all**, which is the property
  /// that keeps an empty area off a cashier's menu without anybody
  /// enumerating roles here.
  ///
  /// Rows are grouped **in the order the caller gives them**. This does not
  /// sort: a caller that interleaves two groups gets the heading twice, which
  /// is a defect in the list rather than something for this component to
  /// repair silently.
  final String? group;
}

/// Which of the two hosts is drawing this component.
///
/// Private because it is not a choice: the frame decides which host it is
/// building from the width it has. It is the constructor's own record of where
/// it was called from.
enum _HomeNavigationHost { drawer, frame }

/// The home's navigation: a drawer below 1024, a persistent column at or above.
final class HomeNavigation extends StatelessWidget {
  /// The drawer's rendering, at `compact` and `medium`.
  ///
  /// Draws at **every** width, unlike [menu], because the frame decides
  /// whether to build a drawer at all - a `Drawer` that rendered nothing would
  /// still be openable, and an empty panel sliding in is worse than no
  /// hamburger.
  const HomeNavigation.drawer({super.key, required this.destinations})
    : _host = _HomeNavigationHost.drawer;

  /// The frame's rendering: the side menu, beside the page rather than inside
  /// it, which is what puts it outside the content maximum and outside the
  /// page's scroll. `AppScaffold.navigation` is the only caller.
  ///
  /// Draws **nothing below `expanded`**, where the destinations are in the
  /// drawer instead.
  const HomeNavigation.menu({super.key, required this.destinations})
    : _host = _HomeNavigationHost.frame;

  /// Everywhere the home can go: the primary first, then by frequency.
  /// **Never alphabetically** - that is the ordering a `Wrap` of identical
  /// pills has, and it is the one this replaced.
  final List<HomeDestination> destinations;

  final _HomeNavigationHost _host;

  /// A side menu's width.
  ///
  /// **288, which is the export's `w-72`**, and it was 256 while this
  /// component had no picture to measure against. Public because the frame
  /// allocates the column and the component draws it, and two declarations of
  /// one width is the drift §4.1 spent step 6 removing.
  static const double menuWidth = 288;

  /// Whether [screenWidth] carries the persistent column rather than a drawer.
  static bool showsMenu(double screenWidth) =>
      AppLayout.contract.isAtLeast(screenWidth, AppBreakpoint.expanded);

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);

    // A role with no destinations at all draws nothing rather than an empty
    // frame.
    if (destinations.isEmpty) return const SizedBox.shrink();

    // **The persistent column is the only one the band gates.** A drawer is
    // built by the frame or it is not, so by the time this is asked the
    // question is already answered; a column beside the page at 900 would
    // simply take half the window.
    if (_host == _HomeNavigationHost.frame &&
        !showsMenu(MediaQuery.sizeOf(context).width)) {
      return const SizedBox.shrink();
    }
    return _HomeMenu(destinations: destinations, tokens: tokens);
  }

  /// The primary first, then everything else in the order it was given.
  ///
  /// Shared by both renderings so a destination cannot be hoisted in one band
  /// and not the other.
  static List<HomeDestination> _ordered(List<HomeDestination> destinations) =>
      <HomeDestination>[
        ...destinations.where((d) => d.isPrimary),
        ...destinations.where((d) => !d.isPrimary),
      ];
}

/// The column of rows, in a drawer below 1024 and beside the page above it.
///
/// **Every destination is labelled and none is hidden**, which is the whole
/// reason a menu was chosen over the export's bottom bar: a column has room to
/// name eleven things where four slots have room for three and a bucket.
final class _HomeMenu extends StatelessWidget {
  const _HomeMenu({required this.destinations, required this.tokens});

  final List<HomeDestination> destinations;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    final ordered = HomeNavigation._ordered(destinations);

    // **The heading is derived, never declared.** Walking the ordered rows and
    // opening a heading whenever the group changes means the caller supplies
    // destinations and nothing else; which headings exist, and whether one
    // exists at all, falls out of what survived the caller's role checks.
    final rows = <Widget>[];
    String? lastGroup;
    for (final destination in ordered) {
      final group = destination.group;
      if (group != null && group != lastGroup) {
        // A heading owes the group above it more air than a row owes its
        // neighbour, so the column reads as areas rather than as one run.
        if (rows.isNotEmpty) rows.add(SizedBox(height: tokens.spacing.s16));
        rows.add(_HomeMenuGroupHeading(text: group, tokens: tokens));
        rows.add(SizedBox(height: tokens.spacing.s8));
      } else if (rows.isNotEmpty) {
        rows.add(SizedBox(height: tokens.spacing.s4));
      }
      rows.add(_HomeMenuRow(destination: destination, tokens: tokens));
      lastGroup = group;
    }

    return Align(
      // **`Align` first, and it is not decoration.** A vertical scroll view
      // hands its child a *tight* width, and a `SizedBox` cannot shrink under a
      // tight constraint - the menu came out 1156 wide in its own first
      // screenshot. `Align` re-loosens the constraint so the width below is the
      // width drawn. In a drawer the panel is already this wide, so the
      // `SizedBox` is a no-op there rather than a second opinion.
      alignment: AlignmentDirectional.centerStart,
      child: SizedBox(
        width: HomeNavigation.menuWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: rows,
        ),
      ),
    );
  }
}

/// One destination as a menu row.
///
/// The export's sidebar row: `h-12 px-4 rounded-lg`, a glyph and a label at
/// `body.md`, and the current destination marked by its own surface and a
/// four-pixel accent bar at the trailing edge rather than by a filled block.
final class _HomeMenuRow extends StatelessWidget {
  const _HomeMenuRow({required this.destination, required this.tokens});

  final HomeDestination destination;
  final AppTokens tokens;

  /// The width of the accent bar on the marked row. The design system's own
  /// figure - "a sharp vertical bar (4px wide) ... in Primary Green" - and it
  /// is `space.4`.
  static double _barWidth(AppSpacing spacing) => spacing.s4;

  @override
  Widget build(BuildContext context) {
    final enabled = destination.onPressed != null;
    final colors = tokens.colors;
    final primary = destination.isPrimary;
    final role = primary ? colors.action.primary : colors.action.secondary;

    final Color container;
    final Color foreground;
    if (!enabled) {
      container = Colors.transparent;
      foreground = colors.text.disabled;
    } else if (primary) {
      container = colors.surface.field;
      foreground = role.container;
    } else {
      container = Colors.transparent;
      foreground = colors.text.secondary;
    }

    final radius = BorderRadius.circular(tokens.radius.sm);
    final row = Container(
      constraints: BoxConstraints(
        minHeight: tokens.density.minimumTapTarget.height,
      ),
      decoration: BoxDecoration(
        color: container,
        borderRadius: radius,
        border: primary && enabled
            ? BorderDirectional(
                end: BorderSide(
                  color: role.container,
                  width: _barWidth(tokens.spacing),
                ),
              )
            : null,
      ),
      padding: EdgeInsetsDirectional.only(
        start: tokens.spacing.s16,
        // The bar eats into the inset rather than adding to it, so a marked
        // row and an unmarked one are the same width.
        end: primary && enabled
            ? tokens.spacing.s16 - _barWidth(tokens.spacing)
            : tokens.spacing.s16,
        top: tokens.spacing.s8,
        bottom: tokens.spacing.s8,
      ),
      child: Row(
        children: <Widget>[
          Icon(destination.icon, size: 18, color: foreground),
          SizedBox(width: tokens.spacing.s12),
          // **Three shares to the label and two to its condition.** An even
          // split is what a bare `Expanded` and `Flexible` give, and in a
          // 288-wide panel that is about 120 each - short of what `Receipts
          // waiting` needs at `body.lg`, so the destination's own name wrapped
          // while its condition sat on one line beside it. The label is what
          // the row is for and outranks what the row has to say about it.
          Expanded(
            flex: 3,
            child: Text(
              destination.label,
              style: tokens.typography.bodyLarge.copyWith(
                color: foreground,
                fontWeight: primary ? FontWeight.w700 : null,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (destination.status case final line?) ...<Widget>[
            SizedBox(width: tokens.spacing.s8),
            Flexible(
              flex: 2,
              child: Text(
                line,
                style: tokens.typography.caption.copyWith(
                  color: enabled ? colors.text.tertiary : foreground,
                ),
                textAlign: TextAlign.end,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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
          // A row is content with an overlay stacked on it, not a container
          // the press replaces - so it takes the wash. See `pressedWash`.
          hoverOverlay: role.hoverWash(),
          pressedOverlay: role.pressedWash(),
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

/// The home's destinations as the old hub's module cards.
///
/// **The pre-multitenancy app's shape, restored 2026-08-25.** Its `MainHub`
/// was a grid of cards — a glyph in a tinted well, the module's name, and a
/// sentence saying what was behind it — and that grid *was* the navigation.
/// Existing customers know it; [HomeNavigation]'s menu is kept alongside as
/// chrome rather than replacing it, so nothing that was reachable stops being
/// reachable.
///
/// **It reads the same [HomeDestination] list the menu does.** Role gating,
/// the closures, and the conditions all stay where they were: a destination a
/// session may not reach was never built, so it cannot appear here either.
///
/// **The column count follows the band rather than the role.** The old grid
/// picked its columns from a role *and* a width — cashiers two, managers
/// three, everyone else four — which put one person's four cards in a layout
/// nobody else saw. Here the band decides and the count of cards falls out of
/// what the role was given, which is the same information without the
/// per-role branch.
final class HomeModuleGrid extends StatelessWidget {
  const HomeModuleGrid({super.key, required this.destinations});

  final List<HomeDestination> destinations;

  /// Columns at [width]. Phones use an Android-style four-across launcher;
  /// larger bands use the roomier information cards.
  static int columnsFor(double width) {
    final contract = AppLayout.contract;
    if (!contract.isAtLeast(width, AppBreakpoint.medium)) return 4;
    if (!contract.isAtLeast(width, AppBreakpoint.expanded)) return 2;
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    if (destinations.isEmpty) return const SizedBox.shrink();

    final ordered = HomeNavigation._ordered(destinations);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = !AppLayout.contract.isAtLeast(
      screenWidth,
      AppBreakpoint.medium,
    );
    final columns = columnsFor(screenWidth);
    final gap = compact ? tokens.spacing.s8 : tokens.spacing.s16;

    // **Explicit rows under an `IntrinsicHeight`, not a `Wrap`.** A `Wrap`
    // gives every card its own natural height, so a row came out ragged
    // wherever one description ran to three lines and its neighbour to one —
    // which the old hub never did, because its `GridView` gave every tile the
    // same aspect ratio. `IntrinsicHeight` restores that without pinning a
    // height nobody measured: the tallest card in a row sets the row, and the
    // rest stretch to it.
    final rows = <List<HomeDestination>>[
      for (int start = 0; start < ordered.length; start += columns)
        ordered.sublist(
          start,
          start + columns > ordered.length ? ordered.length : start + columns,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final (index, row) in rows.indexed) ...<Widget>[
          if (index > 0) SizedBox(height: gap),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final (column, destination) in row.indexed) ...<Widget>[
                  if (column > 0) SizedBox(width: gap),
                  Expanded(
                    child: _HomeModuleCard(
                      destination: destination,
                      tokens: tokens,
                      compact: compact,
                      // **The six moved into `AppTokens` on 2026-08-28.**
                      // They were a private list here until the staff cards
                      // wanted the same six for their avatars, and a palette
                      // living inside one widget is a palette the next surface
                      // has to copy.
                      accent: switch (destination.accent) {
                        final slot? => tokens.colors.accent.identityAt(slot),
                        null =>
                          tokens.colors.accent.identity[(index * columns +
                                  column) %
                              tokens.colors.accent.identity.length],
                      },
                    ),
                  ),
                ],
                // A short final row keeps its cards the width of every other
                // row's rather than stretching two cards across three columns.
                for (
                  int filler = row.length;
                  filler < columns;
                  filler++
                ) ...<Widget>[
                  SizedBox(width: gap),
                  const Expanded(child: SizedBox.shrink()),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// A launcher label that refuses to break a word in half.
///
/// **Whether it may wrap is a property of the label, not of the layout.** A
/// phrase has a place to break and reads perfectly well over two lines; a
/// single word has none, so `maxLines: 2` on *Inventory* produced *Inventor* +
/// *y* rather than a smaller *Inventory*. This asks which it is and then does
/// the right one - scale a word down to fit, let a phrase wrap.
final class _ModuleLabel extends StatelessWidget {
  const _ModuleLabel({required this.label, required this.style});

  final String label;
  final TextStyle style;

  /// Whether [label] has anywhere to break.
  static bool wraps(String label) => label.trim().contains(' ');

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      textAlign: TextAlign.center,
      style: style,
      maxLines: wraps(label) ? 2 : 1,
      // A word scaled to fit is the same word; a word cut short is a different
      // one. The ellipsis is the floor under a label no scaling can save.
      overflow: TextOverflow.ellipsis,
      softWrap: wraps(label),
    );
    if (wraps(label)) return text;
    return FittedBox(fit: BoxFit.scaleDown, child: text);
  }
}

/// The count on a launcher's glyph, as a notification badge.
///
/// The recipe is `SyncIndicator`'s: the status colour filled, the page's own
/// ground for the ring and the figure, and a tabular numeral so a two-digit
/// count does not jitter as the queue drains.
final class _ModuleBadge extends StatelessWidget {
  const _ModuleBadge({required this.count});

  final int count;

  /// The most it will print before giving up on an exact figure.
  static const int maximum = 99;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final problem = tokens.colors.status.problem;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: problem.fg,
        borderRadius: BorderRadius.circular(tokens.radius.pill),
        border: Border.all(color: tokens.colors.surface.base, width: 2),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: tokens.spacing.s4),
        child: Text(
          count > maximum ? '$maximum+' : '$count',
          style: tokens.typography.numericBody.copyWith(
            color: tokens.colors.surface.base,
          ),
        ),
      ),
    );
  }
}

/// One destination as a card.
final class _HomeModuleCard extends StatelessWidget {
  const _HomeModuleCard({
    required this.destination,
    required this.tokens,
    required this.compact,
    required this.accent,
  });

  final HomeDestination destination;
  final AppTokens tokens;
  final bool compact;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final enabled = destination.onPressed != null;
    final colors = tokens.colors;
    final primary = destination.isPrimary;
    final role = primary ? colors.action.primary : colors.action.secondary;

    // Every module is a card on the same raised surface. The till stays first
    // and keeps its strong icon and title weight, but no longer becomes a
    // bright green slab that looks selected before it has been pressed.
    final container = colors.surface.raised;
    final titleColor = enabled ? colors.text.primary : colors.text.disabled;
    final bodyColor = enabled ? colors.text.secondary : colors.text.disabled;

    final radius = BorderRadius.circular(
      compact ? tokens.radius.md : tokens.radius.lg,
    );

    if (compact) {
      // **Counted destinations colour themselves, everything else takes its
      // turn in the palette.** A queue with something in it is the one tile on
      // this page that is asking for attention, and a rotating decorative
      // accent cannot say that; a queue with nothing in it is not a problem and
      // must not be painted as one.
      final counted = destination.badgeCount;
      final glyph = counted == null
          ? accent
          : counted > 0
          ? colors.status.problem.fg
          : colors.text.tertiary;
      final launcher = Padding(
        // **No horizontal inset, since 2026-08-28.** Four columns on a 360
        // handset leave 74 per tile, and after the focus ring's own gutter this
        // padding took the label down to 58 - narrower than the word
        // *Inventory* at 14/w600, so a single word broke across two lines with
        // one letter on the second. The 56 glyph well is centred in the column
        // and never needed the inset; the label did.
        padding: EdgeInsets.symmetric(vertical: tokens.spacing.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Stack(
              // The badge sits on the corner of the well rather than inside it,
              // which is where every launcher a shopkeeper already uses puts
              // one.
              clipBehavior: Clip.none,
              children: <Widget>[
                Container(
                  key: ValueKey('home-module-icon-${destination.label}'),
                  width: _compactGlyphWell,
                  height: _compactGlyphWell,
                  decoration: BoxDecoration(
                    color: enabled
                        ? glyph.withValues(alpha: 0.14)
                        : colors.surface.sunken,
                    borderRadius: BorderRadius.circular(tokens.radius.lg),
                    border: Border.all(
                      color: enabled
                          ? glyph.withValues(alpha: 0.38)
                          : colors.surface.borderSubtle,
                    ),
                  ),
                  child: Icon(
                    destination.icon,
                    size: _compactGlyphSize,
                    color: enabled ? glyph : colors.text.disabled,
                  ),
                ),
                // **No badge at all when there is nothing waiting.** A
                // permanent zero trains a person to stop looking at the one
                // place that tells them something is stuck - the same call
                // `SyncIndicator` makes about its own badge.
                if (counted != null && counted > 0)
                  PositionedDirectional(
                    top: -tokens.spacing.s4,
                    end: -tokens.spacing.s4,
                    child: _ModuleBadge(count: counted),
                  ),
              ],
            ),
            SizedBox(height: tokens.spacing.s8),
            // **A single word is never broken.** *Inventory* and *Expenses* are
            // one word each and wrapped a letter onto a second line; a word
            // that does not fit is scaled down rather than snapped in half. A
            // phrase - *Unprinted receipts* - still takes its two lines, which
            // is what it wants.
            _ModuleLabel(
              label: destination.label,
              style: tokens.typography.bodyMedium.copyWith(
                color: titleColor,
                fontWeight: primary ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      );

      return _pressable(
        enabled: enabled,
        role: role,
        radius: radius,
        fillHeight: false,
        child: launcher,
      );
    }

    final card = Container(
      // **The whole cell, both ways.** `PressSurface.fillWidth` widens what
      // answers a tap, not what is drawn, so a card with a short sentence -
      // *Staff*, or *Logs* with none - drew narrower and shorter than its row
      // and sat centred in its column.
      constraints: const BoxConstraints.expand(),
      padding: EdgeInsets.all(tokens.spacing.s20),
      decoration: BoxDecoration(
        color: container,
        borderRadius: radius,
        border: Border.all(color: colors.surface.borderStrong),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: colors.surface.scrim.withValues(alpha: 0.42),
            blurRadius: 14,
            spreadRadius: 1,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      // **The glyph at the top and the words at the bottom**, which is the old
      // card's own arrangement — it drew the icon, then a `Spacer`, then the
      // name and its sentence. `spaceBetween` says the same thing without an
      // `Expanded` inside the `IntrinsicHeight` the grid wraps this in.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          // The glyph sits in its own well, which is the old card's shape and
          // is a surface step rather than the old screen's black wash.
          Container(
            padding: EdgeInsets.all(tokens.spacing.s12),
            decoration: BoxDecoration(
              color: enabled
                  ? accent.withValues(alpha: 0.14)
                  : colors.surface.field,
              borderRadius: BorderRadius.circular(tokens.radius.md),
              border: Border.all(
                color: enabled
                    ? accent.withValues(alpha: 0.34)
                    : colors.surface.borderSubtle,
              ),
            ),
            child: Icon(
              destination.icon,
              size: _glyphSize,
              color: enabled ? accent : colors.text.disabled,
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: tokens.spacing.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  destination.label,
                  style: tokens.typography.titleMedium.copyWith(
                    color: titleColor,
                    fontWeight: primary ? FontWeight.w700 : null,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (destination.description case final sentence?) ...<Widget>[
                  SizedBox(height: tokens.spacing.s4),
                  Text(
                    sentence,
                    style: tokens.typography.bodyMedium.copyWith(
                      color: bodyColor,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                // A destination's own condition — *2 waiting to send* — is
                // drawn here as well as in the menu, because a card a person
                // is looking at should not be the one surface that does not
                // say it.
                if (destination.status case final line?) ...<Widget>[
                  SizedBox(height: tokens.spacing.s8),
                  Text(
                    line,
                    style: tokens.typography.caption.copyWith(
                      color: enabled
                          ? colors.text.tertiary
                          : colors.text.disabled,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    return _pressable(
      enabled: enabled,
      role: role,
      radius: radius,
      fillHeight: true,
      child: card,
    );
  }

  Widget _pressable({
    required bool enabled,
    required AppActionRole role,
    required BorderRadius radius,
    required bool fillHeight,
    required Widget child,
  }) => Semantics(
    button: true,
    enabled: enabled,
    label: <String?>[
      destination.label,
      destination.description,
      destination.status,
    ].whereType<String>().join('. '),
    child: ExcludeSemantics(
      child: PressSurface(
        key: destination.destinationKey,
        borderRadius: radius,
        onPressed: destination.onPressed,
        // The card is a glyph, a name and a sentence; a solid overlay covers
        // all three. See `pressedWash` for what that looked like.
        hoverOverlay: role.hoverWash(),
        pressedOverlay: role.pressedWash(),
        minimumTapTarget: tokens.density.minimumTapTarget,
        fillWidth: true,
        fillHeight: fillHeight,
        child: child,
      ),
    ),
  );

  /// The card's glyph. Larger than a menu row's 18 because a card has room
  /// for it and the old hub drew it that way.
  static const double _glyphSize = 24;
  static const double _compactGlyphSize = 28;
  static const double _compactGlyphWell = 56;
}

/// One area's name, above the first row that belongs to it.
///
/// **`label.eyebrow` is the role, and this is the first surface in `lib/` to
/// read it.** §2.2 restricts it to "field group labels only" and it had no
/// caller outside the screenshot harness, because the app had no grouped
/// anything. A menu area is a field group in every sense the role cares about,
/// and it is also the one place §2.2 permits uppercase - so the case is
/// applied here, at the caller, exactly as that token's own note says it must
/// be.
///
/// **It is a header to a screen reader and not a destination.** A heading that
/// announced as a button would put six unreachable stops in front of somebody
/// arrowing to *New sale*.
final class _HomeMenuGroupHeading extends StatelessWidget {
  const _HomeMenuGroupHeading({required this.text, required this.tokens});

  final String text;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) => Padding(
    // The heading lines up with its rows' labels rather than with their
    // glyphs, so the column has one left edge instead of two.
    padding: EdgeInsetsDirectional.only(
      start: tokens.spacing.s16,
      end: tokens.spacing.s16,
      bottom: tokens.spacing.s4,
    ),
    child: Semantics(
      header: true,
      child: Text(
        text.toUpperCase(),
        style: tokens.typography.labelEyebrow.copyWith(
          color: tokens.colors.text.tertiary,
        ),
      ),
    ),
  );
}
