/// `StatTile`, `StatRow` and `StatLine`: `design.md` §11 step **8**, the money
/// surfaces.
///
/// **What §11 step 8 asks for is three things and this file is two of them**:
/// `StatTile` and tabular figures. The third, tables, is `RecordList`'s
/// `RecordForm.table`, which step 6 built and which the reporting screens
/// already reach.
///
/// **The figure is the whole point and it is a type role, not a widget.** §2.2
/// is unusually specific here: `numeric.hero` 28 / 32, 700, tabular is "the one
/// figure a stat tile exists for", `numeric.body` 14 / 20, 500, tabular is
/// "money and counts in flow", and tabular figures are **mandatory** anywhere
/// numbers stack vertically. §2.2 names this app's daily summary by name as the
/// place where proportional figures in a column of currency make the amounts
/// look ragged. So the two roles are what these widgets are for, and everything
/// else here is the container around them.
///
/// **Three widgets, and only the first is in §5.1's inventory.** That is stated
/// rather than smuggled, the way `RecordItem.details` was:
///
/// - [StatTile] is §5.1's `StatTile`, which replaces the "recorded stock" /
///   "ledger entries" tiles - `TenantStatCard` in `lib/ui/records.dart`, now
///   deleted.
/// - [StatRow] is the name §7 uses in passing - "the checkout queue counts
///   belong in a `StatRow`, not a five-line list" - and is what `TenantStatStrip`
///   was. §5.1 gives it no row of its own.
/// - [StatLine] is in neither section. It is one label and one figure on a line,
///   for money **in flow** rather than money as a headline, and it exists
///   because two reporting surfaces render exactly that shape - the daily
///   summary's per-day figures and the period totals' tender breakdown - and
///   both were sentences with a number inside them. §2.2's `numeric.body` row
///   is the specification it is built from; the widget is this file's.
///
/// **§5.1 specifies no measurement for any of the three.** §5.2 covers five
/// components and none of these is among them, so - exactly as `Callout` did in
/// step 4 - every value below is read off a §2 row that already exists and named
/// in the doc comment where it is used. Nothing here invents a token, and
/// `PLAN.md` carries the specification gap.
///
/// **A status on a tile is §2.1's container plus icon plus word, never a
/// coloured number.** `TenantStatCard` took an `emphasis` colour and painted the
/// figure red for a negative stock count, which is precisely §9's "out of stock
/// signalled by red text alone" failure in another place. A tile with something
/// to say about its own figure carries a [StatusBadge] under it instead, which
/// is the same repair the catalog sweep made on 2026-08-14.
library;

import 'package:flutter/material.dart';

import 'status.dart';
import 'tokens.dart';

/// One headline figure with its caption. §5.1's `StatTile`.
///
/// **The caption sits above the figure**, because a row of these is read by
/// scanning the captions and stopping at the relevant one. That ordering is
/// inherited from `TenantStatCard`, which this replaces, and is the one thing
/// about it that was already right.
///
/// Measurements, each read off a named row: `radius.md` from §2.3, which is the
/// row for "cards, rows, sheets"; `space.16` padding, also §2.3; `surface.raised`
/// with a `border.subtle` hairline from §2.1, which is what a card is made of
/// everywhere else in this app; `label.md` / `text.secondary` for the caption;
/// `numeric.hero` / `text.primary` for the figure; `caption` / `text.tertiary`
/// for the detail line, which is §2.2's own row for metadata.
///
/// **The caption is sentence case and that is a decision this component makes.**
/// `TenantStatCard` uppercased it. §2.2 restricts uppercase to `label.eyebrow`
/// and restricts `label.eyebrow` itself to "field group labels only", and a stat
/// caption is neither - so both halves of that rule point the same way and the
/// uppercase goes. It is the last uppercase surface in the migrated tree; see
/// the note on [AppTypeRoles.labelEyebrow], which named this component as the
/// one left.
final class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.detail,
    this.status,
    this.statusLabel,
    this.valueKey,
  }) : assert(
         (status == null) == (statusLabel == null),
         'A status is a container, an icon and a word (design.md §2.1). Give '
         'both or neither.',
       );

  /// The caption. Sentence case, per §8 rule 7 - this widget does not case it.
  final String label;

  /// The figure itself, already formatted by the caller, including its currency
  /// code where it has one. §8 rule 8 is the caller's to keep: this component
  /// decides nothing about what a figure says.
  final String value;

  /// An optional glyph in the caption row, at §5.2's only named leading-icon
  /// size.
  final IconData? icon;

  /// One line under the figure: what it is a proportion of, or where it came
  /// from.
  final String? detail;

  /// What this figure's own standing is, where it has one.
  ///
  /// **Optional, and an absent status is not a neutral one** - the same rule
  /// `RecordStatus` carries, for the same reason. A row of tiles that all wear a
  /// badge is a row with no signal in it.
  final AppStatus? status;

  /// The word the badge carries. Required with [status] and refused without it.
  final String? statusLabel;

  /// Key on the figure's own `Text`, for a caller whose tests address the number
  /// rather than the tile around it.
  final Key? valueKey;

  /// The glyph size, borrowed rather than invented.
  ///
  /// The same gap `Callout.glyphSize` and `Disclosure.glyphSize` record: §5.2
  /// names exactly two icon sizes in the whole document - `AppButton`'s leading
  /// icon at 18 and `StatusBadge`'s at 14 - and names none for this component.
  /// 18 is the nearest named row rather than a third size.
  static const double glyphSize = 18;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.colors.surface.raised,
          border: Border.all(color: tokens.colors.surface.borderSubtle),
          borderRadius: BorderRadius.circular(tokens.radius.md),
        ),
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.typography.labelMedium.copyWith(
                        color: tokens.colors.text.secondary,
                      ),
                    ),
                  ),
                  if (icon case final glyph?) ...<Widget>[
                    SizedBox(width: tokens.spacing.s8),
                    Icon(
                      glyph,
                      size: glyphSize,
                      color: tokens.colors.text.tertiary,
                    ),
                  ],
                ],
              ),
              SizedBox(height: tokens.spacing.s8),
              Text(
                key: valueKey,
                value,
                maxLines: 1,
                // A figure that does not fit is a layout this component could
                // not honour, and [StatRow] exists so that it does not happen:
                // it measures the widest figure it holds and gives every tile
                // room for it. This is the floor under that, not the plan.
                overflow: TextOverflow.ellipsis,
                style: tokens.typography.numericHero.copyWith(
                  color: tokens.colors.text.primary,
                ),
              ),
              if (status case final standing?) ...<Widget>[
                SizedBox(height: tokens.spacing.s8),
                StatusBadge(status: standing, label: statusLabel!),
              ],
              if (detail case final line?) ...<Widget>[
                SizedBox(height: tokens.spacing.s4),
                Text(
                  line,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.typography.caption.copyWith(
                    color: tokens.colors.text.tertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A row of [StatTile]s that takes another run rather than overflowing.
///
/// **How many fit is measured, not guessed, and that is the one decision in this
/// widget.** `TenantStatStrip` carried a `minimumWidth` of 168 - a number
/// `design.md` does not contain, which every caller was free to override, and
/// which was set when every figure in the app was a count of two or three
/// digits. `numeric.hero` is 28px at weight 700, so `KES 3810.25` is about 190
/// logical pixels of glyphs before the tile's own padding, and a 168-wide tile
/// would have ellipsised the money on the two screens step 8 is about.
///
/// So the minimum is derived from what the row actually holds: every figure is
/// measured at `numeric.hero` with a [TextPainter], the widest one plus the
/// tile's padding is the narrowest a tile may be, and the row takes as many
/// columns as fit. No constant, no caller knob, and no figure ellipsised. It is
/// the same answer `PLAN.md` calls honest for `RecordList`'s column shares -
/// derived from content rather than fixed - reached here first because a stat
/// row is four boxes rather than a twelve-screen contract.
///
/// The gap between tiles is `space.12` from §2.3, in both directions.
final class StatRow extends StatelessWidget {
  const StatRow({super.key, required this.tiles});

  final List<StatTile> tiles;

  /// How wide a tile must be for [figures] not to be truncated in one.
  ///
  /// Exposed so a test can ask the same question the widget asks, and so the
  /// arithmetic is checkable without reading pixels out of a screenshot.
  static double minimumTileWidth({
    required Iterable<String> figures,
    required AppTokens tokens,
    required double textScaleFactor,
  }) {
    var widest = 0.0;
    for (final figure in figures) {
      final painter = TextPainter(
        text: TextSpan(text: figure, style: tokens.typography.numericHero),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.linear(textScaleFactor),
      )..layout();
      if (painter.width > widest) widest = painter.width;
      painter.dispose();
    }
    // The tile's own horizontal padding, on both sides. Composed from the token
    // [StatTile] pads with rather than restated as one number, so the two cannot
    // drift.
    return widest + tokens.spacing.s16 * 2;
  }

  /// How many tiles fit across [available], given the widest figure.
  ///
  /// At least one, however narrow the surface is: a tile that has to be
  /// truncated is better than a row that overflows, and [StatTile] ellipsises
  /// as its floor.
  static int columnsFor({
    required double available,
    required double minimumTileWidth,
    required double gap,
    required int tiles,
  }) {
    if (tiles <= 1) return 1;
    final fits = ((available + gap) / (minimumTileWidth + gap)).floor();
    return fits.clamp(1, tiles);
  }

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty) return const SizedBox.shrink();
    final tokens = AppTokens.componentOf(context);
    final gap = tokens.spacing.s12;
    final minimum = minimumTileWidth(
      figures: tiles.map((tile) => tile.value),
      tokens: tokens,
      // A figure at 200% text scale needs 200% of the room, and §9 requires it
      // to stay legible there.
      textScaleFactor: MediaQuery.textScalerOf(context).scale(1),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = columnsFor(
          available: constraints.maxWidth,
          minimumTileWidth: minimum,
          gap: gap,
          tiles: tiles.length,
        );
        final width = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - gap * (columns - 1)) / columns;
        // **Rows rather than a `Wrap`, so tiles in a run are the same height.**
        // A `Wrap` gives each child its own height, and one tile carrying a
        // badge or a two-line detail then stands taller than the one beside it -
        // which reads as an unfinished layout rather than as a difference that
        // means anything. `IntrinsicHeight` is cheap at four tiles and is the
        // only way to say "as tall as the tallest of you".
        final runs = <List<StatTile>>[
          for (var start = 0; start < tiles.length; start += columns)
            tiles.sublist(
              start,
              start + columns > tiles.length ? tiles.length : start + columns,
            ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (var run = 0; run < runs.length; run++) ...<Widget>[
              if (run > 0) SizedBox(height: gap),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (var index = 0; index < runs[run].length; index++) ...[
                      if (index > 0) SizedBox(width: gap),
                      SizedBox(width: width, child: runs[run][index]),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// One label and one figure on a line, with the figures aligned down a column.
///
/// **Money in flow, which is §2.2's `numeric.body` row and not `numeric.hero`'s
/// job.** A stat tile is for "the one figure a stat tile exists for"; a list of
/// seven days, or of four ways a period was paid for, is a column of numbers,
/// and §2.2's rule about that column is the one this widget exists to keep -
/// tabular figures, so the amounts stop looking ragged.
///
/// **It is a `Row`, not a table, and the figure is right-aligned.** Digits line
/// up down the column because they are tabular *and* because every figure ends
/// at the same edge; a left-aligned column of tabular figures still staggers
/// wherever the amounts have different lengths.
///
/// `label.md` / `text.secondary` for the key, `numeric.body` / `text.primary`
/// for the figure, `space.12` between them, and `space.4` above and below so a
/// column of them has a rhythm without every caller repeating a gap. All four
/// are named §2 rows; see the note on [StatTile].
///
/// **§3's 64-pixel minimum row height is deliberately not applied.** That row is
/// about a *list* row - something a person aims at and reads one of - and these
/// are lines inside a card. Applying it would make a seven-day summary three
/// times taller than the sentences it replaces, which is the failure §5.2
/// describes for the catalog form in the other direction.
final class StatLine extends StatelessWidget {
  const StatLine({
    super.key,
    required this.label,
    required this.value,
    this.detail,
    this.valueKey,
    this.emphasis = false,
  });

  /// The key. Sentence case, per §8 rule 7.
  final String label;

  /// The figure, already formatted by the caller.
  final String value;

  /// A second, smaller line under [label] - what the figure is over, or what it
  /// was counted from. `caption` / `text.tertiary`, §2.2's row for metadata.
  final String? detail;

  /// Key on the figure's own `Text`.
  final Key? valueKey;

  /// Whether this line is the one the others add up to.
  ///
  /// A total is the same role at the same size in `text.primary` on both halves,
  /// so it reads as the answer rather than as another entry. It is deliberately
  /// **not** a colour and not a larger size: a surface with a hero figure uses
  /// [StatTile] for it.
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: tokens.spacing.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  style: tokens.typography.labelMedium.copyWith(
                    color: emphasis
                        ? tokens.colors.text.primary
                        : tokens.colors.text.secondary,
                  ),
                ),
                if (detail case final line?)
                  Text(
                    line,
                    style: tokens.typography.caption.copyWith(
                      color: tokens.colors.text.tertiary,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(width: tokens.spacing.s12),
          Text(
            key: valueKey,
            value,
            textAlign: TextAlign.right,
            style: tokens.typography.numericBody.copyWith(
              color: tokens.colors.text.primary,
            ),
          ),
        ],
      ),
    );
  }
}
