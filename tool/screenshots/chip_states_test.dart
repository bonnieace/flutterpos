/// `FilterChipBar`'s state matrix, per `claude.md` hard rule 5 and §10.
///
/// **Captured at all three bands, unlike most component matrices in this
/// directory, and §4.3 is why.** That table gives `FilterChips` two forms —
/// *"horizontal scroll, one line"* at `compact` and *"wrap"* at `medium` and
/// `expanded` — so this is the second component after `RecordList` whose form
/// changes with the band, and a contract photographed at two of its three cases
/// is a contract reviewed at two of its three cases.
///
/// **The states are four.** `enabled` with something selected, `enabled` with
/// nothing selected — which is the till's tender chooser and is a real state
/// rather than an edge case — `disabled`, and the overflow case where more chips
/// exist than fit, which is the one §4.3's `compact` row exists for.
library;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/ui/chips.dart';
import 'package:flutter_application_1/ui/tokens.dart';

import 'harness.dart';

/// A filter bar with an "everything" chip, which is how a *filter* spells null.
const _categories = <FilterChipOption<String>>[
  FilterChipOption<String>(value: null, label: 'All categories'),
  FilterChipOption<String>(value: 'bakery', label: 'Bakery'),
  FilterChipOption<String>(value: 'drinks', label: 'Drinks'),
  FilterChipOption<String>(value: 'household', label: 'Household'),
  FilterChipOption<String>(value: 'staples', label: 'Staples'),
];

/// The till's tender chooser: no null chip, because its null means *nothing has
/// been observed yet* rather than *no filter*.
const _tenders = <FilterChipOption<String>>[
  FilterChipOption<String>(value: 'cash', label: 'Cash'),
  FilterChipOption<String>(value: 'mpesa', label: 'M-Pesa'),
  FilterChipOption<String>(value: 'card', label: 'Card'),
];

void main() {
  screenshotCase(
    '95-filterchipbar-selected',
    viewports: responsiveViewports,
    build: () => const _Bar(
      title: 'FilterChipBar - a filter, narrowed',
      options: _categories,
      selected: 'drinks',
    ),
    fullPage: false,
  );

  screenshotCase(
    '95-filterchipbar-everything',
    viewports: responsiveViewports,
    build: () => const _Bar(
      title: 'FilterChipBar - a filter, unnarrowed',
      options: _categories,
      selected: null,
    ),
    fullPage: false,
  );

  screenshotCase(
    '95-filterchipbar-nothing-chosen',
    viewports: responsiveViewports,
    build: () => const _Bar(
      title: 'FilterChipBar - nothing observed yet (the tender chooser)',
      options: _tenders,
      selected: null,
    ),
    fullPage: false,
  );

  screenshotCase(
    '95-filterchipbar-disabled',
    viewports: responsiveViewports,
    build: () => const _Bar(
      title: 'FilterChipBar - disabled, while a write is in flight',
      options: _categories,
      selected: 'drinks',
      enabled: false,
    ),
    fullPage: false,
  );
}

final class _Bar extends StatelessWidget {
  const _Bar({
    required this.title,
    required this.options,
    required this.selected,
    this.enabled = true,
  });

  final String title;
  final List<FilterChipOption<String>> options;
  final String? selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Scaffold(
      backgroundColor: tokens.colors.surface.base,
      body: Padding(
        // Only the vertical inset: §4.3's `compact` row wants the row clipped at
        // the page edge rather than inset, so a half-visible chip is the
        // affordance that says there are more. Padding it would hide exactly the
        // thing this capture exists to show.
        padding: EdgeInsets.symmetric(vertical: tokens.spacing.s24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.symmetric(horizontal: tokens.spacing.s20),
              child: Text(
                title,
                style: tokens.typography.titleMedium.copyWith(
                  color: tokens.colors.text.primary,
                ),
              ),
            ),
            SizedBox(height: tokens.spacing.s16),
            FilterChipBar<String>(
              selected: selected,
              onSelected: (_) {},
              options: <FilterChipOption<String>>[
                for (final option in options)
                  FilterChipOption<String>(
                    value: option.value,
                    label: option.label,
                    enabled: enabled,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
