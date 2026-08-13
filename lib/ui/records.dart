/// Shared presentation for the surfaces that list records.
///
/// The staff directory, the stock screens, and the till all show the same two
/// shapes - a strip of headline figures, and a list of records - and before
/// this file each drew its own. The previous single-tenant app had one look for
/// both and it is the look this app is measured against, so the shapes are
/// lifted from it: a bordered card on a raised surface, and a small
/// letter-spaced caption over a large figure. **The record half has left**, to
/// `RecordList`; what is still here is the figures and the initials block.
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
/// **Three of the widgets that were here are gone, and this is what is left.**
/// `TenantRecordCard`, `TenantRecordTable` and `TenantStatusChip` were deleted
/// on 2026-08-13 when the staff directory - the only screen that ever called
/// the first two - moved onto `RecordList` in `lib/ui/record_list.dart`, which
/// is §4.3's contract: one component, one record model, and the form resolved
/// from the screen width rather than chosen by the caller. The argument
/// `TenantRecordTable` used to make in its own doc comment, that the caller
/// knows which of its columns survive the loss, **was accepted rather than
/// overruled** - it is `RecordAttribute.inNarrowForm`, and §4.3 was amended to
/// concede it. What did not survive is the other half of the position, that the
/// caller also chooses the *form*. `TenantStatusChip` went with them because
/// `StatusBadge` replaced it in step 4 and that was its last call site.
///
/// [TenantStatCard] and [TenantStatStrip] are a different story and are step
/// 8's - they are `StatTile` and `StatRow`, not records - and
/// [TenantInitialsAvatar] survives on the till, which is step 7's.
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
