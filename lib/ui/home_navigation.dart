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

import 'brand_icon.dart';
import 'press.dart';
import 'tokens.dart';

export 'brand_icon.dart' show AppBrandIcon;

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
    this.brandIcon,
    this.cardIcon,
  });

  /// The glyph a wider screen's module card draws in place of [icon], where
  /// the old hub drew that module with a different one.
  ///
  /// **Wider screens only, and that is the point of it being separate.** The
  /// cards on a tablet or a desktop came back as the old hub drew them on
  /// 2026-10-10 - its *Book Keeping* was a book, its *Inventory* a warehouse -
  /// while the phone's launcher stays exactly as it is. A destination the old
  /// hub never had leaves this null and draws [icon], filled.
  final IconData? cardIcon;

  /// Another app's own icon, drawn in place of [icon] and the well around it,
  /// for a destination that sends through that app - *WhatsApp*, *Email*.
  ///
  /// **The well becomes the app icon** rather than holding it: a tinted square
  /// with a logo inside is not the icon a shopkeeper taps on their phone. A
  /// disabled destination draws [icon] in grey as every other one does,
  /// because an app icon has no disabled colour of its own.
  final AppBrandIcon? brandIcon;

  /// The colour this destination's tile wears on wider [HomeModuleGrid] layouts.
  ///
  /// Phone launchers use the six-colour position sequence so adjacent tiles
  /// remain distinct. Wider layouts keep each destination's chosen colour.
  /// Null falls back to its position in those layouts too.
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
          if (destination.brandIcon case final brand? when enabled)
            AppBrandIconMark(
              icon: brand,
              size: tokens.icons.row,
              radius: tokens.radius.sm,
            )
          else
            _DestinationGlyph(
              destination: destination,
              tokens: tokens,
              size: tokens.icons.row,
              color: foreground,
            ),
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
/// **On a tablet or a desktop the cards are the old hub's**, restored on
/// 2026-10-10 - its card, its 20 between cards and its 1.4 shape. **The column
/// count is not its table any more**: the old hub chose columns by role, which
/// sat a cashier's six cards two across at 600 wide each. Every role now gets
/// as many columns as the width holds without a card passing
/// [AppLayout.moduleCardMaxWidth] - four across at every width the old hub's
/// screenshots were taken at, so its look holds where it was measured. **A
/// phone keeps its four-across launcher**, unless [stackedOnPhone] asks for
/// the old hub's phone layout instead.
final class HomeModuleGrid extends StatelessWidget {
  const HomeModuleGrid({
    super.key,
    required this.destinations,
    this.stackedOnPhone = false,
  });

  final List<HomeDestination> destinations;

  /// The old hub's phone layout rather than the launcher: one card to a row,
  /// full width, in its 1.8 shape, 12 apart.
  ///
  /// **For a session with few destinations**, which is the developer's reason
  /// for asking (2026-10-10): a cashier's handful of cards fills a phone as
  /// stacked cards, where the launcher leaves a short row of glyphs at the top
  /// of an empty screen. The caller decides who, because who has few cards is
  /// the caller's to know. Wider than a phone it changes nothing.
  final bool stackedOnPhone;

  /// Columns on a screen [width] wide, with [available] of it for the grid.
  ///
  /// Phones use an Android-style four-across launcher. Wider than a phone it
  /// is the fewest columns that keep every card within
  /// [AppLayout.moduleCardMaxWidth], and never fewer than two. [available]
  /// defaults to the home's own: the screen less its 32 a side.
  static int columnsFor(double width, {double? available}) {
    final contract = AppLayout.contract;
    if (!contract.isAtLeast(width, AppBreakpoint.medium)) return 4;
    const spacing = AppSpacing.scale;
    final room = available ?? width - 2 * spacing.s32;
    final gap = spacing.s20;
    final columns = ((room + gap) / (contract.moduleCardMaxWidth + gap)).ceil();
    return columns < 2 ? 2 : columns;
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
    // The launcher is the phone's unless this session stacks its cards.
    final launcher = compact && !stackedOnPhone;
    final stacked = compact && stackedOnPhone;
    // The old hub's 20 between cards wider than a phone, and its 12 on one.
    final gap = launcher
        ? tokens.spacing.s8
        : stacked
        ? tokens.spacing.s12
        : tokens.spacing.s20;

    return LayoutBuilder(
      builder: (context, constraints) {
        // **Measured against the grid, not the screen**, so the count answers
        // the width the cards actually share.
        final columns = stacked
            ? 1
            : columnsFor(screenWidth, available: constraints.maxWidth);
        // **Explicit rows under an `IntrinsicHeight`, not a `Wrap`.** A `Wrap`
        // gives every card its own natural height, so a row came out ragged
        // wherever one description ran to three lines and its neighbour to
        // one — which the old hub never did, because its `GridView` gave every
        // tile the same aspect ratio. `IntrinsicHeight` restores that without
        // pinning a height nobody measured: the tallest card in a row sets the
        // row, and the rest stretch to it.
        final rows = <List<HomeDestination>>[
          for (int start = 0; start < ordered.length; start += columns)
            ordered.sublist(
              start,
              start + columns > ordered.length
                  ? ordered.length
                  : start + columns,
            ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final (index, row) in rows.indexed) ...<Widget>[
              if (index > 0) SizedBox(height: gap),
              _row(
                context,
                tokens: tokens,
                row: row,
                index: index,
                columns: columns,
                gap: gap,
                compact: launcher,
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _row(
    BuildContext context, {
    required AppTokens tokens,
    required List<HomeDestination> row,
    required int index,
    required int columns,
    required double gap,
    required bool compact,
  }) => IntrinsicHeight(
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
              // Six colours across four phone columns repeat two
              // places to the right on the next row. On larger layouts
              // the destination keeps its named colour.
              accent: compact || destination.accent == null
                  ? tokens.colors.accent.identity[(index * columns + column) %
                        tokens.colors.accent.identity.length]
                  : tokens.colors.accent.identityAt(destination.accent!),
            ),
          ),
        ],
        // A short final row keeps its cards the width of every other
        // row's rather than stretching two cards across three columns.
        for (int filler = row.length; filler < columns; filler++) ...<Widget>[
          SizedBox(width: gap),
          const Expanded(child: SizedBox.shrink()),
        ],
      ],
    ),
  );
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

    // The old hub's card was 16 round; the phone launcher keeps its own.
    final radius = BorderRadius.circular(
      compact ? tokens.radius.md : tokens.radius.xl,
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
                _tile(
                      key: ValueKey('home-module-icon-${destination.label}'),
                      size: tokens.icons.launcherWell,
                      radius: tokens.radius.lg,
                    ) ??
                    Container(
                      key: ValueKey('home-module-icon-${destination.label}'),
                      width: tokens.icons.launcherWell,
                      height: tokens.icons.launcherWell,
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
                      child: _DestinationGlyph(
                        destination: destination,
                        tokens: tokens,
                        size: tokens.icons.launcher,
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

    // **The old hub's card, as it drew on a tablet or a desktop**, restored at
    // the developer's direction on 2026-10-10 - "pixel perfect to how they
    // looked". Every figure below is measured off that screen: the card's fill
    // with no edge and a soft black shadow under it, a 44 well of black wash
    // with a solid glyph in it, and the name and its sentence in the same pale
    // sage. Where the old figure is not on the scale the token says why.
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
        // No edge: the old card was lifted by its shadow, not outlined.
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: colors.surface.scrim.withValues(
              alpha: tokens.effects.cardShadowOpacity,
            ),
            blurRadius: tokens.effects.cardShadowBlur,
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
          // An app's own icon takes the well's place, at the well's size.
          _tile(size: tokens.icons.cardWell, radius: tokens.radius.lg) ??
              Container(
                width: tokens.icons.cardWell,
                height: tokens.icons.cardWell,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: enabled
                      ? colors.surface.scrim.withValues(
                          alpha: tokens.effects.cardWellWashOpacity,
                        )
                      : colors.surface.field,
                  borderRadius: BorderRadius.circular(tokens.radius.lg),
                ),
                child: _DestinationGlyph(
                  destination: destination,
                  tokens: tokens,
                  size: tokens.icons.card,
                  color: enabled ? accent : colors.text.disabled,
                  icon: destination.cardIcon,
                  // Every glyph on the old cards was solid, not only the
                  // till's.
                  filled: true,
                ),
              ),
          // **The one gap that sets the card's height**, the same at every
          // width - see `AppLayout.moduleCardGlyphGap`. A card in a row with
          // a taller neighbour is stretched, and `spaceBetween` keeps its
          // words at the bottom so the names still line up.
          Padding(
            padding: EdgeInsets.only(top: tokens.layout.moduleCardGlyphGap),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  destination.label,
                  // The old card's name was the same sage as its sentence -
                  // it inherited the theme's body colour - and the same weight
                  // on every card, the till's included.
                  style: tokens.typography.moduleTitle.copyWith(
                    color: bodyColor,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                // The old gap was 6, between `space.4` and `space.8`. Measured
                // against the old screen, 8 puts the name 1.4 from where it sat
                // and 4 puts it 2.6 off, because Roboto 3's glyphs sit a little
                // lower in the line than the old face's did.
                SizedBox(height: tokens.spacing.s8),
                // **Always two lines, at the developer's direction on
                // 2026-10-10, so every card in a row is the same shape**: the
                // names line up, and so do the sentences under them. A
                // one-line sentence keeps its second line empty, and a card
                // with none - *Logs* - keeps both. Every sentence the home
                // carries is written to fit two lines at the narrowest card a
                // tablet or a desktop draws, and
                // `test/tenancy/home_card_descriptions_test.dart` holds each
                // one to it; the ellipsis is for a text size a person has
                // raised past that.
                SizedBox(
                  height:
                      MediaQuery.textScalerOf(
                        context,
                      ).scale(tokens.typography.moduleBody.fontSize!) *
                      tokens.typography.moduleBody.height! *
                      2,
                  child: destination.description == null
                      ? null
                      : Text(
                          destination.description!,
                          style: tokens.typography.moduleBody.copyWith(
                            color: bodyColor,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
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
      // **The ring is drawn outside the card rather than given a gutter**, so
      // the card fills its cell and the old hub's 20 between cards is the 20
      // a person sees. A gutter took 4 off every side: 268 wide where the old
      // card measured 277, and 28 between them. The ring still has its room -
      // half of each 20 and most of the page's 32.
      reservesRingGutter: false,
      child: card,
    );
  }

  /// An app's own icon where this destination is that app's channel, and null
  /// where it draws the glyph's well.
  ///
  /// **A disabled destination always draws the well**, because an app icon has
  /// no disabled colour of its own.
  Widget? _tile({Key? key, required double size, required double radius}) {
    if (destination.onPressed == null) return null;
    if (destination.brandIcon case final brand?) {
      return AppBrandIconMark(
        key: key,
        icon: brand,
        size: size,
        radius: radius,
      );
    }
    return null;
  }

  Widget _pressable({
    required bool enabled,
    required AppActionRole role,
    required BorderRadius radius,
    required bool fillHeight,
    required Widget child,
    bool reservesRingGutter = true,
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
        reservesRingGutter: reservesRingGutter,
        child: child,
      ),
    ),
  );
}

/// A destination's glyph at [size], drawn with the Material Symbols axes
/// [AppIconography] names.
///
/// **One widget for all three hosts** - the menu row, the card and the
/// launcher - so a destination is the same drawing at every size, and the one
/// primary destination is solid everywhere it appears rather than only where
/// somebody remembered to ask for it.
final class _DestinationGlyph extends StatelessWidget {
  const _DestinationGlyph({
    required this.destination,
    required this.tokens,
    required this.size,
    required this.color,
    this.icon,
    this.filled = false,
  });

  final HomeDestination destination;
  final AppTokens tokens;
  final double size;
  final Color color;

  /// A different glyph for this host - [HomeDestination.cardIcon] - or null for
  /// the destination's own.
  final IconData? icon;

  /// Solid whatever the destination is. The wider screens' cards ask for it,
  /// because every glyph on the old hub's cards was solid.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final icons = tokens.icons;
    return Icon(
      icon ?? destination.icon,
      size: size,
      color: color,
      fill: filled || destination.isPrimary ? icons.primaryFill : icons.fill,
      weight: icons.weight,
      grade: icons.grade,
      opticalSize: icons.opticalSizeFor(size),
    );
  }
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
