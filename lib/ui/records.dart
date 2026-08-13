/// Shared presentation for the surfaces that list records.
///
/// The staff directory, the stock screens, and the till all show the same two
/// shapes - a strip of headline figures, and a list of records - and before
/// this file each drew its own. The previous single-tenant app had one look for
/// both and it is the look this app is measured against, so the shapes are
/// lifted from it: a bordered card on a raised surface, a small letter-spaced
/// caption over a large figure, and a record row that leads with something to
/// aim at rather than with text.
///
/// **What is not lifted is its colour.** That app hardcoded `bgMid`,
/// `Colors.white54`, and a fixed border in every widget, so a palette change
/// meant editing every screen. Everything here reads [ColorScheme], which is
/// why these compose with the app theme instead of sitting on top of it.
///
/// Nothing in this file decides what a record *is*. It takes strings and
/// widgets and lays them out; every caller keeps its own rules about what may
/// be shown and to whom.
///
/// **The two breakpoints this file used to declare have moved**, in `design.md`
/// §11 step 6. `tenantWideLayoutBreakpoint` (768) and `tenantTableBreakpoint`
/// (1024) are now `AppLayout.mediumFloor` and `AppLayout.expandedFloor` in
/// `lib/ui/tokens.dart`, under §4.1's names, with the same numbers - which is
/// what §4.1 asks for in so many words. Their two readers,
/// `tenantLayoutIsWide` and `tenantLayoutFitsTable`, are `AppLayout.isAtLeast`
/// and took a `BoxConstraints`; the replacement takes a screen width, because
/// §4.1's bands describe the surface a person is looking at rather than
/// whatever box a widget happens to be inside.
///
/// **Two of the widgets here are superseded and are on their way out.**
/// `design.md` §11 step 6's second half built `RecordList` in
/// `lib/ui/record_list.dart`, which is §4.3's contract: one component, one
/// record model, and the form resolved from the screen width rather than chosen
/// by the caller. [TenantRecordCard] and [TenantRecordTable] are the two halves
/// it replaces, and the argument [TenantRecordTable] makes below - that the
/// caller knows which columns survive the loss - **was accepted rather than
/// overruled**: it is now `RecordAttribute.inNarrowForm`, and §4.3 was amended
/// to concede it. What did not survive is the other half of the position, that
/// the caller also chooses the *form*.
///
/// They stay until the screens still calling them are swept onto `RecordList`.
/// That is one screen, the staff directory, which is the only consumer either
/// has ever had. [TenantStatCard] and [TenantStatStrip] are a different story
/// and are step 8's - they are `StatTile` and `StatRow`, not records - and
/// [TenantStatusChip] is superseded by `StatusBadge` from step 4.
library;

import 'package:flutter/material.dart';

/// One headline figure with its caption.
///
/// The caption sits above the figure rather than below it, because a column of
/// these is read by scanning the captions and stopping at the relevant one.
final class TenantStatCard extends StatelessWidget {
  const TenantStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.detail,
    this.emphasis,
    this.valueKey,
  });

  /// Key for the figure itself, for a caller whose tests address the number
  /// rather than the card around it.
  final Key? valueKey;

  /// The short caption, rendered in caps.
  final String label;

  /// The figure itself, already formatted by the caller.
  final String value;

  final IconData icon;

  /// An optional line under the figure, for what it is a proportion of or
  /// where it came from.
  final String? detail;

  /// Overrides the icon and figure colour, for a figure that is a problem
  /// rather than a fact. Left null for an ordinary figure.
  final Color? emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tone = emphasis ?? colors.primary;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Icon(icon, size: 18, color: tone),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              key: valueKey,
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: emphasis ?? colors.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (detail case final line?) ...[
              const SizedBox(height: 4),
              Text(
                line,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A row of [TenantStatCard]s that wraps rather than overflows.
///
/// A `Row` of four on a phone gives each about ninety pixels, which is not a
/// card; this lays them out at a readable minimum and takes as many rows as
/// that needs.
final class TenantStatStrip extends StatelessWidget {
  const TenantStatStrip({super.key, required this.cards, this.minimumWidth = 168});

  final List<TenantStatCard> cards;

  /// The narrowest a card may be before the strip takes another row.
  final double minimumWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const spacing = 12.0;
      final available = constraints.maxWidth;
      // At least one per row, however narrow the surface is.
      final perRow = available < minimumWidth
          ? 1
          : ((available + spacing) / (minimumWidth + spacing)).floor().clamp(
              1,
              cards.isEmpty ? 1 : cards.length,
            );
      final width = perRow == 1
          ? available
          : (available - spacing * (perRow - 1)) / perRow;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final card in cards) SizedBox(width: width, child: card),
        ],
      );
    },
  );
}

/// A short status word, shown as a chip.
///
/// Status is carried by a word and, where it matters, a colour - never by
/// colour alone, which is unreadable to a colourblind reader and does not
/// survive a printed rota.
final class TenantStatusChip extends StatelessWidget {
  const TenantStatusChip({
    super.key,
    required this.label,
    this.icon,
    this.tone,
  });

  final String label;
  final IconData? icon;

  /// Null for an ordinary state, which takes the surface's own outline.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = tone ?? theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colour.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon case final glyph?) ...[
            Icon(glyph, size: 13, color: colour),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colour,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A square, rounded initials block.
///
/// The previous app keyed a colour per person from a fixed table, which cannot
/// survive real staff lists. This takes the surface's own accent for everyone:
/// the block is there to give the eye something to land on down a column, not
/// to identify anybody by hue.
final class TenantInitialsAvatar extends StatelessWidget {
  const TenantInitialsAvatar({super.key, required this.source, this.icon});

  /// The name the initials are taken from.
  final String source;

  /// Shown instead of initials when the record is better identified by a
  /// symbol than by a name.
  final IconData? icon;

  static String initialsOf(String source) {
    final words = source
        .trim()
        .split(RegExp(r'[\s@._-]+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      final word = words.single;
      return (word.length == 1 ? word : word.substring(0, 2)).toUpperCase();
    }
    return '${words.first[0]}${words[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: icon == null
          ? Text(
              initialsOf(source),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: colors.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            )
          : Icon(icon, size: 22, color: colors.onPrimaryContainer),
    );
  }
}

/// One record, as a card.
///
/// The compact half of every list here. It leads with the avatar so a column
/// of these can be scanned by position, states the two lines that identify the
/// record, and carries its status as chips rather than as a hyphenated string.
final class TenantRecordCard extends StatelessWidget {
  const TenantRecordCard({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.chips = const <Widget>[],
    this.actions,
    this.details = const <Widget>[],
  });

  final String title;
  final String? subtitle;
  final Widget? leading;

  /// Status words. Rendered under the title on a phone, where there is no
  /// column to put them in.
  final List<Widget> chips;

  /// The record's own controls, kept at the top right where a thumb reaches.
  final Widget? actions;

  /// Anything the caller wants under the record, such as an expanded form.
  final List<Widget> details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (leading case final lead?) ...[
                  lead,
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle case final line?) ...[
                        const SizedBox(height: 2),
                        Text(
                          line,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (chips.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(spacing: 6, runSpacing: 6, children: chips),
                      ],
                    ],
                  ),
                ),
                if (actions case final controls?) controls,
              ],
            ),
            ...details,
          ],
        ),
      ),
    );
  }
}

/// One column of a [TenantRecordTable].
final class TenantTableColumn {
  const TenantTableColumn({required this.label, this.flex = 1});

  final String label;
  final int flex;
}

/// The wide form of a record list.
///
/// A table earns its place only where there is width for every column at once;
/// below that it is a card list, which is what [TenantRecordTable] leaves to
/// the caller rather than deciding here - the caller knows which of its columns
/// survive the loss.
final class TenantRecordTable extends StatelessWidget {
  const TenantRecordTable({
    super.key,
    required this.columns,
    required this.rows,
  });

  final List<TenantTableColumn> columns;

  /// One list of cells per row, in column order, plus nothing else: a row that
  /// disagrees with [columns] in length is a caller defect and is asserted
  /// rather than padded, because a silently short row misaligns every column
  /// after it.
  final List<TenantTableRow> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                for (final column in columns)
                  Expanded(
                    flex: column.flex,
                    child: Text(
                      column.label.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          for (final row in rows) _TenantRecordTableRow(columns: columns, row: row),
        ],
      ),
    );
  }
}

/// One row of a [TenantRecordTable], with anything it wants to expand under it.
final class TenantTableRow {
  const TenantTableRow({
    required this.cells,
    this.details = const <Widget>[],
    this.key,
  });

  final List<Widget> cells;

  /// Rendered full width beneath the row, for a form the row opens.
  final List<Widget> details;

  final Key? key;
}

final class _TenantRecordTableRow extends StatelessWidget {
  const _TenantRecordTableRow({required this.columns, required this.row});

  final List<TenantTableColumn> columns;
  final TenantTableRow row;

  @override
  Widget build(BuildContext context) {
    assert(
      row.cells.length == columns.length,
      'A table row carries ${row.cells.length} cells for '
      '${columns.length} columns, which would misalign every column after the '
      'short one.',
    );
    return Container(
      key: row.key,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var index = 0; index < columns.length; index++)
                Expanded(flex: columns[index].flex, child: row.cells[index]),
            ],
          ),
          ...row.details,
        ],
      ),
    );
  }
}
