/// One count, as the review list draws it.
///
/// **The card leads with the difference, because that is the question the screen
/// is opened with.** The list this replaces drew every fact as an equal
/// key-value row - `Counted 118 of 240`, `Differences 6, 31 units`, `Not counted
/// 122` - so the figure a manager opens the screen for sat in a stack with the
/// figures they do not. Here the two difference figures are the card's own block
/// and coverage is a bar underneath, which is the order the facts are wanted in.
///
/// **No fact the old rendering showed has been dropped.** Coverage moved onto a
/// meter and keeps its figures in words beside it; uncounted lines are the
/// unfilled part of that meter *and* a line of their own, because "nobody looked"
/// is not a smaller version of "it was counted"; unmatched lines keep a line of
/// their own too. `test/inventory/stock_take_card_test.dart` holds that to it.
///
/// **A count still arriving keeps its figures and gains a warning.** The
/// temptation is to hide them - they are computed from the pages that have
/// landed and they will change - but a screen that blanks a number somebody read
/// five minutes ago is a screen that looks broken. So they stay, and the card
/// says plainly that they are not final.
library;

import 'package:flutter/material.dart';

import '../ui/meter.dart';
import '../ui/press.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'stock_take_review.dart';

/// A count's standing, as one of §2.1's five statuses.
///
/// **Lifted out of the panel so the badge and the meter cannot disagree.** The
/// card colours both from this one answer, which is what makes it read as one
/// object rather than as two signals that happen to be near each other.
@immutable
final class TenantStockTakeStanding {
  const TenantStockTakeStanding({required this.label, required this.status});

  final String label;
  final AppStatus status;

  /// The same four-way switch the review panel has always made, unchanged.
  static TenantStockTakeStanding of(TenantStockTakeRecord take) =>
      switch (take.status) {
        // Not an error. It means the device that counted has not finished
        // sending, and the server refuses to apply a count it has only part of.
        TenantStockTakeStatus.submitting => const TenantStockTakeStanding(
          label: 'Still arriving',
          status: AppStatus.attention,
        ),
        TenantStockTakeStatus.applied => const TenantStockTakeStanding(
          label: 'Accepted',
          status: AppStatus.ok,
        ),
        TenantStockTakeStatus.submitted when take.varianceLineCount == 0 =>
          const TenantStockTakeStanding(
            label: 'All agreed',
            status: AppStatus.ok,
          ),
        TenantStockTakeStatus.submitted => const TenantStockTakeStanding(
          label: 'Needs review',
          status: AppStatus.info,
        ),
      };
}

/// One count in the review list.
final class TenantStockTakeCard extends StatelessWidget {
  const TenantStockTakeCard({
    super.key,
    required this.take,
    required this.counterLabel,
    required this.onOpen,
  });

  final TenantStockTakeRecord take;

  /// Who counted it, already resolved to a name by the panel.
  ///
  /// **Passed in rather than looked up**, so this widget reads nothing and a
  /// list of twenty cards cannot become twenty document reads.
  final String counterLabel;

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final standing = TenantStockTakeStanding.of(take);
    final radius = BorderRadius.circular(tokens.radius.md);
    return PressSurface(
      borderRadius: radius,
      fillWidth: true,
      onPressed: onOpen,
      // **Washes, not fills.** `AppActionRole.pressedWash`'s own note: a card is
      // composed content with an overlay stacked on top of it, and the opaque
      // container the fill would paint hides the whole card while the tap is
      // held. The home's module cards shipped that bug.
      hoverOverlay: tokens.colors.action.primary.hoverWash(),
      pressedOverlay: tokens.colors.action.primary.pressedWash(),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.colors.surface.raised,
          border: Border.all(color: tokens.colors.surface.cardEdge),
          borderRadius: radius,
        ),
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _identity(tokens, standing),
              SizedBox(height: tokens.spacing.s4),
              Text(
                '${take.businessDate} · $counterLabel',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens.typography.caption.copyWith(
                  color: tokens.colors.text.tertiary,
                ),
              ),
              SizedBox(height: tokens.spacing.s12),
              _difference(tokens, standing),
              SizedBox(height: tokens.spacing.s12),
              _coverage(tokens, standing),
              if (take.unmatchedLineCount > 0) ...<Widget>[
                SizedBox(height: tokens.spacing.s12),
                _unmatched(tokens),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The scope, the standing and the affordance that says the card opens.
  Widget _identity(AppTokens tokens, TenantStockTakeStanding standing) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Expanded(
        child: Text(
          take.categoryId == null ? 'Whole catalog' : 'One category',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: tokens.typography.titleMedium.copyWith(
            color: tokens.colors.text.primary,
          ),
        ),
      ),
      SizedBox(width: tokens.spacing.s8),
      StatusBadge(
        key: ValueKey<String>('stock-take-standing-${take.id}'),
        status: standing.status,
        label: standing.label,
      ),
      SizedBox(width: tokens.spacing.s4),
      Icon(
        Icons.chevron_right,
        size: _chevron,
        color: tokens.colors.text.tertiary,
      ),
    ],
  );

  /// The two difference figures, or the sentence that says there are none.
  Widget _difference(AppTokens tokens, TenantStockTakeStanding standing) {
    final well = BoxDecoration(
      color: tokens.colors.surface.sunken,
      borderRadius: BorderRadius.circular(tokens.radius.md),
    );
    if (take.varianceLineCount == 0 &&
        take.status != TenantStockTakeStatus.submitting) {
      return DecoratedBox(
        decoration: well,
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.s12),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.check_circle_outline,
                size: _glyph,
                color: tokens.colors.status.ok.fg,
              ),
              SizedBox(width: tokens.spacing.s8),
              Expanded(
                child: Text(
                  'Every product counted matched the books.',
                  style: tokens.density
                      .body(tokens.typography)
                      .copyWith(color: tokens.colors.text.secondary),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        DecoratedBox(
          decoration: well,
          child: Padding(
            padding: EdgeInsets.all(tokens.spacing.s12),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    child: _figure(
                      tokens,
                      value: '${take.varianceLineCount}',
                      caption: take.varianceLineCount == 1
                          ? 'product differs'
                          : 'products differ',
                      valueKey: ValueKey<String>(
                        'stock-take-variance-${take.id}',
                      ),
                    ),
                  ),
                  SizedBox(width: tokens.spacing.s12),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: tokens.colors.surface.borderSubtle,
                  ),
                  SizedBox(width: tokens.spacing.s12),
                  Expanded(
                    child: _figure(
                      tokens,
                      value: '${take.absoluteVarianceUnits}',
                      caption: take.absoluteVarianceUnits == 1
                          ? 'unit apart in total'
                          : 'units apart in total',
                      valueKey: ValueKey<String>('stock-take-units-${take.id}'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // **The figures stay and the warning joins them.** They are computed
        // from the pages that have landed, so they will move; blanking them
        // would make a screen somebody read five minutes ago look broken.
        if (take.status == TenantStockTakeStatus.submitting) ...<Widget>[
          SizedBox(height: tokens.spacing.s8),
          _note(
            tokens,
            status: AppStatus.attention,
            icon: Icons.schedule,
            message:
                'The device that took this has not finished sending, so these '
                'figures are not final and nothing can be accepted yet.',
            noteKey: ValueKey<String>('stock-take-arriving-${take.id}'),
          ),
        ],
      ],
    );
  }

  /// One figure and the words that say what it counts.
  Widget _figure(
    AppTokens tokens, {
    required String value,
    required String caption,
    required Key valueKey,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Text(
        value,
        key: valueKey,
        // `numeric.compact`: the design's own pairing for a figure a card is
        // built around, at a size a card has room for.
        style: tokens.typography.numericCompact.copyWith(
          color: tokens.colors.text.primary,
        ),
      ),
      SizedBox(height: tokens.spacing.s4),
      Text(
        caption,
        style: tokens.typography.caption.copyWith(
          color: tokens.colors.text.tertiary,
        ),
      ),
    ],
  );

  /// How much of the scope has a number against it.
  Widget _coverage(AppTokens tokens, TenantStockTakeStanding standing) {
    final uncounted = take.uncountedLineCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                take.status == TenantStockTakeStatus.submitting
                    ? 'Counted so far'
                    : 'Counted',
                style: tokens.typography.labelMedium.copyWith(
                  color: tokens.colors.text.secondary,
                ),
              ),
            ),
            SizedBox(width: tokens.spacing.s8),
            Text(
              '${take.countedLineCount} of ${take.productsInScope}',
              key: ValueKey<String>('stock-take-coverage-${take.id}'),
              style: tokens.typography.numericBody.copyWith(
                color: tokens.colors.text.secondary,
              ),
            ),
          ],
        ),
        SizedBox(height: tokens.spacing.s8),
        AppMeter(
          filled: take.countedLineCount,
          of: take.productsInScope,
          status: standing.status,
          semanticLabel:
              '${take.countedLineCount} of ${take.productsInScope} counted',
        ),
        // **Its own line as well as the empty part of the bar.** Nothing is
        // known about an uncounted product one way or the other, and a gap in a
        // bar is not a statement - `TenantStockTakeRecord.uncountedLineCount`
        // makes the same point about never folding these into a variance.
        if (uncounted > 0) ...<Widget>[
          SizedBox(height: tokens.spacing.s8),
          Text(
            '$uncounted not counted',
            key: ValueKey<String>('stock-take-uncounted-${take.id}'),
            style: tokens.typography.caption.copyWith(
              color: tokens.colors.text.tertiary,
            ),
          ),
        ],
      ],
    );
  }

  Widget _unmatched(AppTokens tokens) => _note(
    tokens,
    status: AppStatus.attention,
    icon: Icons.help_outline,
    message: take.unmatchedLineCount == 1
        ? '1 line names a product this business does not hold.'
        : '${take.unmatchedLineCount} lines name products this business does '
              'not hold.',
    noteKey: ValueKey<String>('stock-take-unmatched-${take.id}'),
  );

  /// A tinted aside inside the card.
  ///
  /// Not a [Callout]: that component is a screen-level notice paragraph with its
  /// own title, and one nested inside a record card reads as a second card.
  Widget _note(
    AppTokens tokens, {
    required AppStatus status,
    required IconData icon,
    required String message,
    required Key noteKey,
  }) {
    final role = status.role(tokens);
    return DecoratedBox(
      key: noteKey,
      decoration: BoxDecoration(
        color: role.bg,
        border: Border.all(color: role.border),
        borderRadius: BorderRadius.circular(tokens.radius.md),
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.s12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: _glyph, color: role.fg),
            SizedBox(width: tokens.spacing.s8),
            Expanded(
              child: Text(
                message,
                style: tokens.typography.caption.copyWith(
                  color: tokens.colors.text.secondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// §5.2 names two icon sizes in the whole document - `AppButton`'s leading
  /// glyph at 18 and `StatusBadge`'s at 14. These are those two, borrowed rather
  /// than a third size being invented, which is the same borrowing
  /// `RecordActionSet.glyphSize` records.
  static const double _chevron = 18;
  static const double _glyph = 18;
}
