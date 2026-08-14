/// What is left of the shared presentation for the surfaces that list records:
/// one initials block.
///
/// The staff directory, the stock screens, and the till all showed the same two
/// shapes - a strip of headline figures, and a list of records - and before this
/// file each drew its own. The previous single-tenant app had one look for both
/// and it is the look this app is measured against, so the shapes were lifted
/// from it: a bordered card on a raised surface, and a small letter-spaced
/// caption over a large figure. **Both halves have now left** - the records to
/// `RecordList` in step 6, the figures to `StatTile` in step 8.
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
/// **Five of the widgets that were here are gone.** `TenantRecordCard`,
/// `TenantRecordTable` and `TenantStatusChip` went on 2026-08-13, when the staff
/// directory - the only screen that ever called the first two - moved onto
/// `RecordList` in `lib/ui/record_list.dart`, which is §4.3's contract: one
/// component, one record model, and the form resolved from the screen width
/// rather than chosen by the caller. The argument `TenantRecordTable` used to
/// make in its own doc comment, that the caller knows which of its columns
/// survive the loss, **was accepted rather than overruled** - it is
/// `RecordAttribute.inNarrowForm`, and §4.3 was amended to concede it. What did
/// not survive is the other half of the position, that the caller also chooses
/// the *form*. `TenantStatusChip` went with them because `StatusBadge` replaced
/// it in step 4 and that was its last call site.
///
/// **`TenantStatCard` and `TenantStatStrip` went on 2026-08-14, in step 8**, and
/// they were the last two. They are `StatTile` and `StatRow` in
/// `lib/ui/stats.dart`, which is §5.1's own naming of them - they were never
/// records - and the two things that changed in the move are recorded there: the
/// caption stopped being uppercase, which §2.2 permits only on `label.eyebrow`,
/// and the `emphasis` colour became a `StatusBadge`, because a figure that is
/// red and says nothing is a failure §9 already lists.
///
/// [TenantInitialsAvatar] is what is left. It survives on the till, which is
/// step 7's, and this file now exists for it alone.
library;

import 'package:flutter/material.dart';

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
