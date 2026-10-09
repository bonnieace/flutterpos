/// One closed shift, drawn as the card the shift history screen is built out of.
///
/// **This replaces a `RecordItem`, and the reason is that a shift is not a
/// record like the other twenty.** `RecordList` lays a record out as identity,
/// attributes, provenance and actions, every attribute at the same weight -
/// which is right for a catalog row, where the six facts are six facts. A closed
/// shift has one fact that the screen exists to settle (do the takings agree
/// with the sales) and three or four that are the working behind it. Drawn as
/// equal key-value lines, the answer was the fifth line down and looked exactly
/// like the four around it.
///
/// So the card states the answer twice, in the two places a person looks: the
/// [StatusBadge] carries it as a word at the top, and - where there is a
/// difference at all - the amount is restated at the bottom in
/// `numeric.compact` under a label that names the direction. Between them sit
/// the two figures that were compared, quietly.
///
/// **Colour is never the carrier and this file is careful about it**, because
/// `stats.dart` records the same trap from the other side: a figure painted red
/// for a negative stock count is §9's "out of stock signalled by red text
/// alone". Here the difference amount does take `status.problem`'s foreground,
/// and it is permitted because by then the row has already said it three times
/// without colour - the badge's container, the badge's glyph, the badge's word,
/// and the label beside the figure. The colour is emphasis on a fact that is
/// legible without it.
///
/// **Every value is a role.** `surface.raised` and `surface.cardEdge` through
/// [AppCard]; `radius.md`; `space.16` padding and `space.12` between the blocks;
/// `body.lg` at 600 for the identity, which is the weight `RecordList` settled
/// on for the same line; the density's body role for the labels; `mono` at
/// `text.money` for the figures; `numeric.compact` for the difference, which is
/// §2.2's own "a card's own figure"; and `label.eyebrow` at `text.tertiary` for
/// the day a group of these sits under.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../reporting/reporting_currency.dart';
import '../ui/buttons.dart';
import '../ui/card.dart';
import '../ui/money_text.dart';
import '../ui/press.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'shift_history.dart';

/// What a closed shift's drawer had to say about its own sales.
///
/// **Five, where the screen used to draw four**, and the fifth is the split
/// `shift_history.dart` already makes and the badge used to collapse: a shift
/// closed before summaries existed and a shift somebody ended from a device
/// holding none of its sales both have no variance, and they are not the same
/// event. One is an old record. The other is a shift whose money nobody can
/// account for, and it is the one a manager has to chase.
enum ShiftStanding {
  /// The declaration and the sales agree. §2.1's `ok`.
  settled(AppStatus.ok, 'Settled', Icons.check_circle_outline),

  /// The declaration is over the sales. §2.1's `problem`.
  over(AppStatus.problem, 'Over', Icons.trending_up),

  /// The declaration is under the sales. §2.1's `problem`.
  short(AppStatus.problem, 'Short', Icons.trending_down),

  /// Ended by a device that held none of this shift's sales, so there is
  /// nothing to compare the cash with. §2.1's `attention`.
  unaccounted(AppStatus.attention, 'Unaccounted', Icons.help_outline),

  /// Closed before this app recorded closing summaries. §2.1's `attention`.
  noSummary(AppStatus.attention, 'No summary', Icons.history_toggle_off);

  const ShiftStanding(this.status, this.label, this.icon);

  final AppStatus status;

  /// The word on the badge. Sentence case, §8 rule 7.
  ///
  /// **One word where the screen used to write four.** `Takings match` /
  /// `Takings over` / `Takings short` named the subject on every row, and the
  /// subject is the same on every row of a screen called shift history. What
  /// varies is the direction, and that is what a person scanning a column of
  /// badges is scanning for.
  final String label;

  final IconData icon;

  /// Whether this standing is one somebody has to do something about.
  ///
  /// The filter reads this, so what *Needs attention* means is stated once here
  /// rather than as a set of cases repeated at the call site.
  bool get needsAttention => this != ShiftStanding.settled;

  /// The standing of one closed shift.
  ///
  /// **A lookup over three recorded facts and never a recomputation**, which is
  /// the property the whole surface is built on: `cashVarianceMinor` is a
  /// subtraction of two figures the server holds, and this only reads its sign.
  static ShiftStanding of(TenantShiftHistoryEntry entry) {
    final variance = entry.cashVarianceMinor;
    if (variance == null) {
      return entry.closedWithoutEvidence
          ? ShiftStanding.unaccounted
          : ShiftStanding.noSummary;
    }
    if (variance == 0) return ShiftStanding.settled;
    return variance > 0 ? ShiftStanding.over : ShiftStanding.short;
  }
}

/// The sentence a screen reader hears in place of the badge's one word.
///
/// The badge says `Short`; without this it would announce `Short` and nothing
/// about what is short of what. Kept here beside the word it stands in for.
String shiftStandingSemantics(TenantShiftHistoryEntry entry) {
  final standing = ShiftStanding.of(entry);
  return switch (standing) {
    ShiftStanding.unaccounted =>
      'This shift was ended from a device holding none of its sales, so its '
          'figures are not known.',
    ShiftStanding.noSummary =>
      'No closing summary was recorded for this shift.',
    ShiftStanding.settled => 'Declared takings match recorded sales.',
    ShiftStanding.over =>
      'Declared takings are over the recorded sales by '
          '${_plainAmount(entry.cashVarianceMinor!.abs())}.',
    ShiftStanding.short =>
      'Declared takings are short of the recorded sales by '
          '${_plainAmount(entry.cashVarianceMinor!.abs())}.',
  };
}

/// One closed shift.
final class ShiftHistoryCard extends StatelessWidget {
  const ShiftHistoryCard({
    super.key,
    required this.entry,
    required this.title,
    required this.subtitle,
    required this.currency,
    required this.onViewSales,
    this.onViewCorrections,
  });

  final TenantShiftHistoryEntry entry;

  /// What names this shift on the card: the cashier, where the list spans
  /// several, and the shift's own hours where every row is the same person.
  /// Resolved by the panel, which is the only thing that knows the scope.
  final String title;

  /// The second line - whatever [title] did not say. Composed by the panel from
  /// [shiftWindowLabel] and [shiftSalesLabel] for the same reason.
  final String subtitle;

  /// What this business calls its money. An unpublished currency leaves the
  /// figures bare rather than guessing a code - see [TenantReportingCurrency].
  final TenantReportingCurrency currency;

  /// Opens the Sales report on the shift's day, narrowed to the member who ran
  /// it. **The whole card body is this control**: it is the one thing there is
  /// to do with a row here, and a card carrying a `View sales` button on every
  /// one of twenty rows spends a 48-high band of the screen saying the same
  /// word twenty times.
  final VoidCallback onViewSales;

  /// Opens the corrections trail narrowed to this shift. Null where the shift
  /// was never corrected, and null where this session may not read the trail -
  /// the two are different facts and the panel owns both.
  final VoidCallback? onViewCorrections;

  /// The gap between the blocks inside a card, and between the cards
  /// themselves. `space.12`, which is what `RecordList` puts between records.
  static double blockGap(AppSpacing spacing) => spacing.s12;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final standing = ShiftStanding.of(entry);
    final corrections = onViewCorrections;
    final body = Padding(
      padding: EdgeInsets.all(tokens.spacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      title,
                      key: ValueKey<String>(
                        'shift-history-subject-${entry.id}',
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.typography.bodyLarge.copyWith(
                        color: tokens.colors.text.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: tokens.spacing.s4),
                    Text(
                      subtitle,
                      key: ValueKey<String>('shift-history-window-${entry.id}'),
                      maxLines: 2,
                      style: tokens.density
                          .body(tokens.typography)
                          .copyWith(color: tokens.colors.text.secondary),
                    ),
                  ],
                ),
              ),
              SizedBox(width: tokens.spacing.s12),
              StatusBadge(
                key: ValueKey<String>('shift-history-status-${entry.id}'),
                status: standing.status,
                label: standing.label,
                icon: standing.icon,
                semanticLabel: shiftStandingSemantics(entry),
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.s12),
          Divider(
            height: 1,
            thickness: 1,
            color: tokens.colors.surface.borderSubtle,
          ),
          SizedBox(height: tokens.spacing.s12),
          ..._figures(tokens, standing),
        ],
      ),
    );

    return AppCard(
      key: ValueKey<String>('shift-history-entry-${entry.id}'),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PressSurface(
            key: ValueKey<String>('shift-history-sales-link-${entry.id}'),
            // The card's own corners, so the press wash stops where the card
            // does. Square at the bottom where a footer follows it, or the wash
            // would round away from an edge that is still there.
            borderRadius: corrections == null
                ? BorderRadius.circular(tokens.radius.md)
                : BorderRadius.vertical(top: Radius.circular(tokens.radius.md)),
            onPressed: onViewSales,
            fillWidth: true,
            semanticLabel:
                '$title. ${standing.label}. Open the sales report for this '
                "shift's day and cashier.",
            excludeSemantics: true,
            hoverOverlay: tokens.colors.action.secondary.hoverWash(),
            pressedOverlay: tokens.colors.action.secondary.pressedWash(),
            child: body,
          ),
          if (corrections != null) ...<Widget>[
            Divider(
              height: 1,
              thickness: 1,
              color: tokens.colors.surface.borderSubtle,
            ),
            // **A footer strip rather than a button inside the pressable
            // body.** Nesting one control in another leaves a person who cannot
            // see the card guessing which of the two a tap lands on; here the
            // two targets do not overlap at all.
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppButton(
                key: ValueKey<String>(
                  'shift-history-corrections-link-${entry.id}',
                ),
                label: "This shift's corrections",
                icon: Icons.history,
                tier: AppButtonTier.tertiary,
                onPressed: corrections,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The figures, in the order the comparison is made in.
  List<Widget> _figures(AppTokens tokens, ShiftStanding standing) {
    final summary = entry.summary;
    final variance = entry.cashVarianceMinor;
    final rows = <Widget>[];

    void gap() {
      if (rows.isNotEmpty) rows.add(SizedBox(height: tokens.spacing.s8));
    }

    // **The sentence comes first where there is one**, because it is the reason
    // the figures below it are short of the figures on every other card.
    if (standing == ShiftStanding.unaccounted ||
        standing == ShiftStanding.noSummary) {
      rows.add(
        Text(
          standing == ShiftStanding.unaccounted
              ? "Ended from another device, which held none of this shift's "
                    'sales. Nothing can be compared with the cash.'
              : 'This shift closed before the app recorded closing summaries, '
                    'so there is nothing to compare the cash with.',
          key: ValueKey<String>('shift-history-silence-${entry.id}'),
          style: tokens.density
              .body(tokens.typography)
              .copyWith(color: tokens.colors.text.secondary),
        ),
      );
    }

    gap();
    rows.add(
      _FigureLine(
        label: 'Counted cash',
        value: shiftMoney(currency, entry.closingCashMinor),
        valueKey: ValueKey<String>('shift-history-counted-${entry.id}'),
      ),
    );

    // **Shown only where there was one.** A row reading `Opening float 0.00` on
    // every shift in a shop that never floats a till is noise on the screen a
    // cashier settles cash from; where there was one it is subtracted from the
    // difference below, and a figure that moves the answer has to be visible
    // beside it.
    if (entry.openingFloatMinor > 0) {
      gap();
      rows.add(
        _FigureLine(
          label: 'Opening float',
          value: shiftMoney(currency, entry.openingFloatMinor),
          valueKey: ValueKey<String>('shift-history-float-${entry.id}'),
        ),
      );
    }

    if (summary != null) {
      gap();
      rows.add(
        _FigureLine(
          label: 'Recorded sales',
          value: shiftMoney(currency, summary.totalSalesMinor),
          valueKey: ValueKey<String>('shift-history-sales-${entry.id}'),
          // **The marker rides on the figure it is about.** A corrected shift's
          // recorded sales *are* the rewritten ones, and the screen used to say
          // so on a line of its own two rows further down, where nothing tied
          // the claim to the number it was a claim about.
          badge: entry.amendment == null
              ? null
              : StatusBadge(
                  key: ValueKey<String>('shift-history-amended-${entry.id}'),
                  status: AppStatus.attention,
                  label: _correctedLabel(entry.amendment!),
                  icon: Icons.history,
                  semanticLabel: _correctedSemantics(entry.amendment!),
                ),
        ),
      );
    }

    // **What explains a drawer that holds less than the sales, and more.** A
    // shift that sold on credit counted less cash than it recorded in sales,
    // and one that took repayments counted more; both are subtracted or added
    // in the difference below, so both are shown beside it - and only where
    // there was one, as the float is.
    if (summary != null && summary.creditOwedMinor > 0) {
      gap();
      rows.add(
        _FigureLine(
          label: 'Sold on credit',
          value: shiftMoney(currency, summary.creditOwedMinor),
          valueKey: ValueKey<String>('shift-history-credit-${entry.id}'),
        ),
      );
    }
    if (summary != null && summary.repaidMinor > 0) {
      gap();
      rows.add(
        _FigureLine(
          label: 'Paid back by customers',
          value: shiftMoney(currency, summary.repaidMinor),
          valueKey: ValueKey<String>('shift-history-repaid-${entry.id}'),
        ),
      );
    }
    // Why a drawer that holds less than its sales is not short: the money went
    // back to customers who returned goods.
    if (summary != null && summary.refundedMinor > 0) {
      gap();
      rows.add(
        _FigureLine(
          label: 'Handed back for returns',
          value: shiftMoney(currency, summary.refundedMinor),
          valueKey: ValueKey<String>('shift-history-refunded-${entry.id}'),
        ),
      );
    }

    // Silent where the two figures agree: the badge has already said so, and a
    // difference of nothing is not a difference.
    if (variance != null && variance != 0) {
      rows
        ..add(SizedBox(height: tokens.spacing.s12))
        ..add(
          Divider(
            height: 1,
            thickness: 1,
            color: tokens.colors.surface.borderSubtle,
          ),
        )
        ..add(SizedBox(height: tokens.spacing.s12))
        ..add(
          _DifferenceLine(
            label: variance > 0 ? 'Over by' : 'Short by',
            value: shiftMoney(currency, variance.abs()),
            valueKey: ValueKey<String>('shift-history-variance-${entry.id}'),
          ),
        );
    }
    return rows;
  }
}

/// One figure and what it is, on a line. §5.2's key-value attribute.
final class _FigureLine extends StatelessWidget {
  const _FigureLine({
    required this.label,
    required this.value,
    required this.valueKey,
    this.badge,
  });

  final String label;
  final String value;
  final Key valueKey;

  /// Something to say about this figure, between the label and the value.
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: tokens.density
                .body(tokens.typography)
                .copyWith(color: tokens.colors.text.secondary),
          ),
        ),
        if (badge case final marker?) ...<Widget>[
          SizedBox(width: tokens.spacing.s8),
          marker,
        ],
        SizedBox(width: tokens.spacing.s8),
        Text(
          value,
          key: valueKey,
          style: tokens.typography.mono.copyWith(
            color: tokens.colors.text.money,
          ),
        ),
      ],
    );
  }
}

/// The answer: the amount the drawer and the sales disagree by.
final class _DifferenceLine extends StatelessWidget {
  const _DifferenceLine({
    required this.label,
    required this.value,
    required this.valueKey,
  });

  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final problem = tokens.colors.status.problem;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: tokens.density
                .body(tokens.typography)
                .copyWith(color: problem.fg, fontWeight: FontWeight.w600),
          ),
        ),
        SizedBox(width: tokens.spacing.s8),
        // `numeric.compact` is §2.2's "a card's own figure" - the same role the
        // reporting tiles use - and `FittedBox` keeps a six-figure difference an
        // amount rather than an ellipsis.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerEnd,
            child: Text(
              value,
              key: valueKey,
              maxLines: 1,
              style: tokens.typography.numericCompact.copyWith(
                color: problem.fg,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The day a group of cards sits under, with a rule to its trailing edge.
///
/// `label.eyebrow` uppercased at `text.tertiary`, which is §2.2's one permitted
/// uppercase role, over `surface.borderSubtle`.
final class ShiftHistoryDayHeading extends StatelessWidget {
  const ShiftHistoryDayHeading({
    super.key,
    required this.businessDate,
    required this.count,
  });

  /// The shift's own `YYYY-MM-DD`, which is the business's day rather than the
  /// device's.
  final String businessDate;

  /// How many shifts closed on it, out of what this page holds.
  final int count;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final style = tokens.typography.labelEyebrow.copyWith(
      color: tokens.colors.text.tertiary,
    );
    return Semantics(
      header: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Text(shiftBusinessDayLabel(businessDate).toUpperCase(), style: style),
          SizedBox(width: tokens.spacing.s8),
          Expanded(
            child: Divider(
              height: 1,
              thickness: 1,
              color: tokens.colors.surface.borderSubtle,
            ),
          ),
          SizedBox(width: tokens.spacing.s8),
          ExcludeSemantics(
            child: Text(
              '$count',
              style: tokens.typography.mono.copyWith(
                color: tokens.colors.text.tertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Labels
// ---------------------------------------------------------------------------

/// `Fri 20 Sep`, from the shift's own `YYYY-MM-DD` business date.
///
/// **Not parsed into an instant and not shifted into a zone.** A business date
/// is the shop's own day, chosen by whatever opened the shift; turning it into
/// midnight UTC and rendering that locally is how a Friday becomes a Thursday
/// west of Greenwich. A string that is not a date is printed as it stands.
String shiftBusinessDayLabel(String businessDate) {
  final parts = businessDate.split('-');
  if (parts.length != 3) return businessDate;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return businessDate;
  if (month < 1 || month > 12 || day < 1 || day > 31) return businessDate;
  return _dayFormat.format(DateTime(year, month, day));
}

/// `06:04 → 14:12`, in the shop's own clock.
///
/// **Local, where this screen printed UTC.** A cashier who closed a till at ten
/// past nine in Nairobi read `18:10 UTC` on the row they are answerable from.
/// The instant is unchanged - both ends are still the recorded server times -
/// and only the clock it is stated on has moved to the one the person was
/// standing in.
///
/// It is also the *title* of a card in a list of one person's own shifts, where
/// naming the cashier on every row names nothing: the day is the group heading
/// above it and the hours are what tells two of that day's shifts apart.
String shiftWindowLabel(TenantShiftHistoryEntry entry) =>
    switch ((entry.startedAt, entry.endedAt)) {
      (final from?, final to?) => '${_clock(from)} → ${_clock(to)}',
      (null, final to?) => 'Closed ${_clock(to)}',
      (final from?, null) => 'Opened ${_clock(from)}, close time not confirmed',
      _ => 'Close time not confirmed',
    };

/// `63 sales`, or what stands in for it where the close recorded none.
String shiftSalesLabel(TenantShiftHistoryEntry entry) {
  final summary = entry.summary;
  if (summary == null) return 'sales not known';
  final count = summary.transactionCount;
  return '$count ${count == 1 ? 'sale' : 'sales'}';
}

/// `Corrected ×2`, which is what differs between one corrected row and another.
String _correctedLabel(ShiftSummaryAmendment amendment) =>
    'Corrected ×${amendment.count}';

String _correctedSemantics(ShiftSummaryAmendment amendment) {
  final times = amendment.count == 1 ? 'once' : '${amendment.count} times';
  final at = amendment.amendedAt;
  final when = at == null
      ? 'the time of the last correction was not recorded'
      : 'the last was ${_stampFormat.format(at.toLocal())}';
  return 'The recorded sales on this shift were corrected $times, and $when.';
}

/// An amount, grouped in thousands, with the business's code where it has one.
///
/// **Grouped, where `TenantReportingCurrency.format` is not.** That method is
/// shared by every reporting surface and is deliberately left alone; the reason
/// to group here is the reason `weeklyReportHeroMoney` groups the takings.
/// `55400.00` is read digit by digit and `55,400.00` is read at a glance, and
/// this is the screen where two amounts a hundred apart have to be told apart
/// by eye, in a column, under pressure.
///
/// **No code where the business has published none.** Reporting never assumes a
/// currency; see [TenantReportingCurrency], and the notice the panel prints once
/// when this returns bare figures.
String shiftMoney(TenantReportingCurrency currency, int minorUnits) {
  final grouped = moneyTextGroupedOfMinor(minorUnits);
  final code = currency.code;
  return code == null ? grouped : '$code $grouped';
}

/// An amount with no currency code, for a sentence a screen reader hears.
String _plainAmount(int minorUnits) => moneyTextGroupedOfMinor(minorUnits);

String _clock(DateTime instant) => _clockFormat.format(instant.toLocal());

final DateFormat _dayFormat = DateFormat('EEE d MMM');
final DateFormat _clockFormat = DateFormat('HH:mm');
final DateFormat _stampFormat = DateFormat('d MMM yyyy, HH:mm');
