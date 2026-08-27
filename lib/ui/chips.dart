/// `FilterChipBar`: `design.md` §5.1's row for "hand-built chip `Wrap`", §4.3's
/// `FilterChips` contract, and the second of the five components §11 step 7 was
/// blocked on.
///
/// **Five screens each built the same `Wrap` of `ChoiceChip`s.** Twenty chips
/// across the catalog, the bulk route, the till, sales totals and the differences
/// list, every one of them a nullable single selection with an "everything" option
/// in front of it — and every one of them arranged by hand, which is why none of
/// them honoured §4.3.
///
/// **§4.3 is the part that was missing, not the styling.** That table gives
/// `FilterChips` *"horizontal scroll, one line"* at `compact` and *"wrap"* at
/// `medium` and `expanded`. **No screen did this**: all five wrapped at every band,
/// so a phone showing eight categories spent four rows of a small screen on
/// filters before the list they filter began. The component owns that now, and a
/// screen cannot opt out — §4.3's own rule.
///
/// **A chip is a pill, as of `design.md` v0.7.** §2.3 said `radius.sm` and
/// `lib/theme.dart`'s `chipTheme` has drawn `StadiumBorder` since before the
/// migration began; the product owner closed that on 2026-08-16 in the theme's
/// favour. The rule that survives is *a control is a pill, a container is not* —
/// so this takes `radius.pill` and `StatusBadge`, which is read rather than
/// pressed, keeps `radius.sm`.
///
/// **Selection carries a glyph, not only a fill.** §9: status is never conveyed by
/// hue alone, and a selected filter is a status — it is the difference between
/// "you are seeing everything" and "you are seeing a slice", which is the single
/// most consequential thing a filter bar says. A fill alone fails that for the one
/// reader in twelve §2.1 is written about, and fails it completely in a
/// photocopied training sheet.
///
/// **A null selection is meaningful, and the two kinds of null are the caller's to
/// distinguish.** A filter's null is *"no filter"* and is normally given an
/// explicit "Every kind" chip so the state is visible rather than implied. The
/// till's tender chooser also has a null, and it means the opposite: **nothing has
/// been observed yet**, deliberately, because "a pre-selected payment method would
/// be indistinguishable from an observed one". That is why this component refuses
/// to invent a default and takes the selection as given.
library;

import 'package:flutter/material.dart';

import 'press.dart';
import 'status.dart';
import 'tokens.dart';

/// One chip in a [FilterChipBar].
@immutable
final class FilterChipOption<T> {
  const FilterChipOption({
    required this.value,
    required this.label,
    this.key,
    this.enabled = true,
  });

  /// What selecting this chip means. **Null is a legitimate value** — see the
  /// library note on the two kinds of null.
  final T? value;

  /// The word. Sentence case per §8 rule 7; this widget does not case it, for
  /// the reason [StatusBadge] gives.
  final String label;

  /// The chip's own key, so a screen's existing tests keep addressing it.
  final Key? key;

  final bool enabled;
}

/// A single-select row of filters that changes form with the band.
final class FilterChipBar<T> extends StatelessWidget {
  const FilterChipBar({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.semanticLabel,
  });

  final List<FilterChipOption<T>> options;

  /// The selected value, or null. Compared by `==`, so a `T` with value
  /// semantics behaves and an identity type behaves the way its own `==` does.
  final T? selected;

  final ValueChanged<T?> onSelected;

  /// What the row as a whole is for — "Filter by category". Announced on the
  /// group rather than repeated onto every chip.
  final String? semanticLabel;

  /// §5.2 gives `AppButton` three heights and this is none of them.
  ///
  /// **32 is `AppButton.sm`'s height and that is where it comes from** rather
  /// than being invented: a chip is a small control, §2.3 supplies no chip
  /// height, and reusing a named figure beats a new one. The *tap target* stays
  /// §9's 48 — [PressSurface] expands the area that answers a press to the
  /// density's minimum, exactly as it does for a `sm` button.
  static const double height = 32;

  /// The check glyph's size. `StatusBadge`'s, which is the only icon size
  /// `design.md` names for something read at this scale.
  static const double glyphSize = StatusBadge.iconSize;

  /// Whether [screenWidth] gets the scrolling single line rather than a wrap.
  ///
  /// §4.3: `FilterChips` is "horizontal scroll, one line" at `compact` and
  /// "wrap" at `medium` and `expanded`. Exposed so a test asks the same question
  /// the widget asks, as `PageHeader` and `TenantCheckoutPanel` both do.
  static bool scrollsInOneLine(double screenWidth) =>
      !AppLayout.contract.isAtLeast(screenWidth, AppBreakpoint.medium);

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final chips = <Widget>[
      for (final option in options)
        _Chip<T>(
          key: option.key,
          option: option,
          selected: option.value == selected,
          onSelected: option.enabled ? () => onSelected(option.value) : null,
        ),
    ];
    // §4.3's own words for the two forms. The gap is `space.8` from §2.3 in both
    // directions, which is what all five hand-built `Wrap`s already used.
    final Widget row = scrollsInOneLine(MediaQuery.sizeOf(context).width)
        ? SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            // **Clipped to the page edge rather than inset**, so a half-visible
            // chip at the trailing edge is the affordance that says there are
            // more. A padded scroller hides that and looks like a short wrap.
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (var i = 0; i < chips.length; i++) ...<Widget>[
                  if (i > 0) SizedBox(width: tokens.spacing.s8),
                  chips[i],
                ],
              ],
            ),
          )
        : Wrap(
            spacing: tokens.spacing.s8,
            runSpacing: tokens.spacing.s8,
            children: chips,
          );
    return Semantics(container: true, label: semanticLabel, child: row);
  }
}

final class _Chip<T> extends StatelessWidget {
  const _Chip({
    super.key,
    required this.option,
    required this.selected,
    required this.onSelected,
  });

  final FilterChipOption<T> option;
  final bool selected;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final disabled = onSelected == null;
    // **A selected chip wears §2.1's `ok` triple.** Not the accent on its own:
    // §2.1 notes that `status.ok` and the brand accent are deliberately the same
    // mint and that what disambiguates them is the *container*, which is exactly
    // what a chip has. An unselected chip is `border.strong` on nothing, which
    // is `action.secondary`'s own outline.
    final ok = tokens.colors.status.ok;
    final Color labelColor;
    final Color borderColor;
    final Color containerColor;
    if (disabled) {
      labelColor = tokens.colors.text.disabled;
      borderColor = tokens.colors.surface.borderSubtle;
      containerColor = Colors.transparent;
    } else if (selected) {
      labelColor = ok.fg;
      borderColor = ok.border;
      containerColor = ok.bg;
    } else {
      labelColor = tokens.colors.text.secondary;
      borderColor = tokens.colors.surface.borderStrong;
      containerColor = Colors.transparent;
    }
    // **`radius.lg`, which is the design's `rounded-full` and is 12 rather
    // than a pill.** A selectable chip in the export is
    // `px-3 py-1.5 rounded-full`, and the served config resolves `full` to
    // `0.75rem` - so 12 on a ~30-high chip is a soft rectangle, not a capsule.
    // `StatusBadge` keeps `radius.sm`, which is the bare `rounded` the export
    // gives a badge in 78 of the 82 places one appears.
    final radius = BorderRadius.circular(tokens.radius.lg);

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      enabled: !disabled,
      label: option.label,
      excludeSemantics: true,
      child: PressSurface(
        borderRadius: radius,
        onPressed: onSelected,
        hoverOverlay: tokens.colors.action.secondary.hoverFill(),
        pressedOverlay: tokens.colors.action.secondary.pressedFill(),
        excludeSemantics: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: containerColor,
            borderRadius: radius,
            border: Border.all(color: borderColor),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: FilterChipBar.height),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: tokens.spacing.s12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // §9, and the reason is in the library note: a fill alone is
                  // hue alone, and whether a list is filtered is the most
                  // consequential thing this row says.
                  if (selected) ...<Widget>[
                    Icon(
                      Icons.check,
                      size: FilterChipBar.glyphSize,
                      color: labelColor,
                    ),
                    SizedBox(width: tokens.spacing.s4),
                  ],
                  Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.typography.labelMedium.copyWith(
                      color: labelColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
