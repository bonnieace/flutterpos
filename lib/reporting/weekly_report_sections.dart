/// The weekly report's body: the cards, the filters, the chart and the lists.
///
/// **Split from `weekly_report_panel.dart` so the route and the composition are
/// separately readable**, the way the totals page splits its choosers out. The
/// panel decides what to load and who may see it; everything here draws.
///
/// Every value is an `AppTokens` role. Where the old screen had a raw number -
/// a 200-tall chart, a 48-square item tile, a 32-wide bar - the figure is named
/// here as a composition constant with the reason it is not a token, exactly as
/// `sheet.dart` names its drag handle.
library;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_staff_names.dart';
import '../ui/buttons.dart';
import '../ui/fields.dart';
import '../ui/scaffold.dart';
import '../ui/press.dart';
import '../ui/status.dart';
import '../ui/rolling_number.dart';
import '../ui/skeleton.dart';
import '../ui/tokens.dart';
import 'net_profit.dart';
import 'profit_statement.dart';
import 'reporting_currency.dart';
import 'sales_totals.dart';
import 'sales_totals_session_context.dart';
import 'weekly_report.dart';
import 'weekly_report_charts.dart';
import 'weekly_report_panel.dart';

/// Figures this composition fixes, which `design.md` states no token for.
///
/// Named rather than inlined for the reason `AppSheetMasthead` gives: a literal
/// in a widget is a defect, and inventing `size.chartHeight` would be inventing
/// a token the design system never defined. These are the old screen's own
/// proportions, kept so the page reads as it did.
abstract final class WeeklyReportMetrics {
  /// The revenue chart's plot height. The old screen's `SizedBox(height: 200)`.
  static const double chartHeight = 200;

  /// One bar's width. The old screen's `width: 32`.
  static const double barWidth = 32;

  /// Room for the money labels down the left axis.
  static const double axisReserve = 60;

  /// How many gridlines sit behind the bars.
  static const int gridDivisions = 4;

  /// The heights a reading chart draws its seven bars at, as fractions of the
  /// plot.
  ///
  /// **Uneven on purpose.** Seven bars of one height is a placeholder that
  /// reads as a table; a week's takings are never level, and the shape of the
  /// thing being waited for is the only reason to draw bars rather than one
  /// grey slab.
  static const List<double> readingBarHeights = <double>[
    0.45,
    0.7,
    0.35,
    0.85,
    0.6,
    0.5,
    0.25,
  ];

  /// How wide a figure reads while it is still being read.
  ///
  /// A fraction rather than a width, so the placeholder scales with the
  /// card it sits in. Short of the full line because a money figure never
  /// fills one, and a placeholder that did would settle noticeably narrower
  /// than it started.
  static const double readingWidthFactor = 0.55;

  /// The floor the chart scales to, so an empty week still draws an axis
  /// rather than collapsing to a flat line at zero.
  static const double emptyWeekCeiling = 1000;

  /// Headroom above the tallest bar, so it never touches the top rule.
  static const double ceilingHeadroom = 1.2;

  /// The rank number's column in the top-items list, wide enough for two
  /// digits so a tenth row does not shunt the names right.
  static const double rankColumn = 24;

  /// The share bar under one top item.
  static const double shareBarHeight = 4;

  /// The square holding a top item's glyph. The old screen's 48.
  static const double itemGlyph = 48;

  /// The square holding a transaction's payment glyph. The old screen's 40.
  static const double saleGlyph = 40;

  /// A metric card's own glyph, and the arrow beside its percentage. The old
  /// screen's 20 and 14.
  static const double cardGlyph = 20;
  static const double deltaGlyph = 14;

  /// A tile's glyph, which is smaller than a card's because a tile is.
  static const double tileGlyph = 14;

  /// The height every tile in the grid draws to, caption or no caption.
  ///
  /// **A floor rather than a fixed height, and it is what makes this a grid.**
  /// `IntrinsicHeight` already matched the two tiles in a *row*, so the row
  /// holding NET PROFIT and its *After expenses* line came out taller than the
  /// row under it and the four read as two pairs rather than as one block. A
  /// tile grows past this where its figure wraps; what it may not do is be
  /// shorter than its neighbours for want of a caveat to print.
  ///
  /// Measured from the tile's ordinary parts at the size they are set in: the
  /// eyebrow line, the figure in `numericCompact`, and one caption. **Not from
  /// its largest possible self** - sized for a tile carrying a comparison chip
  /// *and* a detail *and* a caveat, every ordinary tile stood half empty, which
  /// is a worse fault than an uneven row. A tile that does carry all three
  /// grows, and its row grows with it.
  static const double tileHeight = 76;

  // -- the week strip under the takings --------------------------------------

  /// The strip's whole height, bars and day letters together.
  static const double stripHeight = 92;

  /// The tallest a bar is drawn, leaving the letters their line.
  static const double stripBarHeight = 64;

  /// A day that took nothing: a rule rather than a bar, so the week reads as
  /// seven days and not as four.
  static const double stripFloor = 4;

  /// The shortest a day that *did* trade may be drawn. Below this a real
  /// day's takings are indistinguishable from none at all, which is the one
  /// thing a shape like this must not say.
  static const double stripTraded = 8;

  /// How far a quiet day's bar is let back towards the card behind it, and how
  /// far the cents recede behind the shillings. Both are a step of emphasis
  /// rather than a fade: `Color.lerp` towards the surface, never an opacity, so
  /// the value stays a colour the contrast rules can be checked against.
  static const double quietBarRecession = 0.55;
  static const double decimalRecession = 0.35;
}

/// The whole page under the header.
final class WeeklyReportContents extends StatelessWidget {
  const WeeklyReportContents({
    super.key,
    required this.week,
    required this.report,
    required this.sessionContext,
    required this.soldById,
    required this.selfUid,
    required this.categoryId,
    required this.showProfit,
    this.reading = false,
    required this.onChooseWeek,
    required this.onChooseMember,
    required this.onChooseCategory,
    required this.onRetry,
    this.currency,
    this.failureMessage,
    this.destinations = const WeeklyReportDestinations(),
  });

  /// The reports the cards on this grid open. See [WeeklyReportDestinations].
  final WeeklyReportDestinations destinations;

  final TenantReportWeek week;

  /// Null while the week could not be read. The filters still draw, which is
  /// the point of keeping them out of the failure state.
  final TenantWeeklyReport? report;

  /// Whether [report] is null because the read is still running.
  ///
  /// **An em dash is a claim and a placeholder is not**, which is the whole
  /// reason this flag exists rather than the sections reading `report == null`
  /// and drawing the same thing either way. `—` in a figure card says *this
  /// week has no such figure* - the right thing to say about a week that could
  /// not be read, and a lie about one that has not answered yet. Before
  /// 2026-08-27 this page showed a centred spinner instead, which said nothing
  /// untrue but also replaced the week picker and the filters while it did it.
  final bool reading;

  final SalesTotalsSessionContext sessionContext;
  final String? soldById;
  final String? selfUid;
  final String? categoryId;
  final bool showProfit;
  final TenantReportingCurrency? currency;
  final ValueChanged<int> onChooseWeek;
  final ValueChanged<String?> onChooseMember;
  final ValueChanged<String?> onChooseCategory;
  final VoidCallback onRetry;
  final String? failureMessage;

  /// Whether the server has been asked for this week and could not answer.
  ///
  /// **A cache hit is not evidence of an outage**, and the callout below used
  /// to treat it as though it were. The guard runs the device read beside the
  /// server read so the page draws immediately; the device read usually wins,
  /// because a disk beats a network. So on every single open this page raised
  /// a banner announcing that it was working from this device, and withdrew it
  /// half a second later when the server answered - an outage it had no
  /// grounds for, taken back before anybody finished reading it.
  ///
  /// `TenantRouteGuard` already draws exactly this distinction and publishes
  /// it: `fromCache` without `stale` is *the server has not answered yet*,
  /// which is a moment, and `stale` is *the server was asked and could not be
  /// reached*, which is the standing condition the sentence was written for.
  /// The shell's own offline card learned this in the same words - see
  /// `_worksFromSavedData` - and this page was never brought into line with it.
  ///
  /// Outside a guard there is nothing to ask, and the figures on screen really
  /// were counted here, so the callout stands.
  static bool serverCouldNotBeReached(BuildContext context) =>
      TenantReadFreshness.maybeOf(context)?.stale ?? true;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final wide = AppLayout.contract.isAtLeast(
      MediaQuery.sizeOf(context).width,
      AppBreakpoint.expanded,
    );
    final medium = AppLayout.contract.isAtLeast(
      MediaQuery.sizeOf(context).width,
      AppBreakpoint.medium,
    );
    return ListView(
      key: const ValueKey('weekly-report-body'),
      // **The horizontal inset was missing, and only here.** `AppScaffold` pads
      // no body - `horizontalInset`'s note names the 20 the list screens use on
      // all four sides, and every other route in this app supplies it - so this
      // one drew its cards, its chart and its rows hard against the edge of the
      // phone while the rest of the app kept a margin. The vertical 8 is
      // unchanged; it is the gap under the toolbar, not the page inset.
      padding: EdgeInsets.symmetric(
        horizontal: AppScaffold.horizontalInset(tokens.spacing),
        vertical: tokens.spacing.s8,
      ),
      children: <Widget>[
        if (report?.totals?.basis == TenantSalesTotalsBasis.device &&
            serverCouldNotBeReached(context)) ...<Widget>[
          const Callout(
            key: ValueKey('weekly-report-device-basis'),
            status: AppStatus.info,
            title: 'On this device',
            message:
                'The server could not be reached, so this is counted from the '
                'sales saved here, less the returns this device holds. Sales '
                'or returns from other devices, and comparison percentages, '
                'are not in it.',
          ),
          SizedBox(height: tokens.spacing.s24),
        ],
        if (failureMessage case final message?) ...<Widget>[
          Callout(
            key: const ValueKey('weekly-report-failure'),
            status: AppStatus.problem,
            message: message,
            action: AppButton(
              label: 'Try again',
              tier: AppButtonTier.tertiary,
              size: AppButtonSize.sm,
              onPressed: onRetry,
            ),
          ),
          SizedBox(height: tokens.spacing.s24),
        ],
        // **The week and the filters, before any figure.** They were below
        // the whole grid until 2026-09-20: on a 390-wide handset the week
        // picker sat three screens down, so somebody opening this page to look
        // at *last* week had to scroll past the whole of *this* one to reach
        // the control that would take them there. Nothing above them now.
        _FilterBar(
          week: week,
          sessionContext: sessionContext,
          soldById: soldById,
          selfUid: selfUid,
          categoryId: categoryId,
          onChooseWeek: onChooseWeek,
          onChooseMember: onChooseMember,
          onChooseCategory: onChooseCategory,
          stacked: !medium,
        ),
        SizedBox(height: tokens.spacing.s24),
        // **One figure at the top rather than six of equal weight.** The
        // takings are the question this page is opened with; the rest qualify
        // the answer. Six full-width cards in a column said they were all the
        // same question.
        if (wide)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: _TakingsHero(
                    report: report,
                    reading: reading,
                    currency: currency,
                    week: week,
                  ),
                ),
                SizedBox(width: tokens.spacing.s24),
                Expanded(
                  flex: 2,
                  child: WeeklyRevenueChart(
                    week: week,
                    report: report,
                    reading: reading,
                    currency: currency,
                  ),
                ),
              ],
            ),
          )
        else
          // **One reading of the week's shape, not two.** The hero carries the
          // strip; drawing the measured chart under it as well put the same
          // seven days on the screen twice, the second time with an axis
          // nobody had scrolled to ask for. `WeeklyRevenueChart` is the wide
          // screen's, where there is room to set it beside the figure.
          _TakingsHero(
            report: report,
            reading: reading,
            currency: currency,
            week: week,
          ),
        SizedBox(height: tokens.spacing.s16),
        _MetricGrid(
          report: report,
          reading: reading,
          showProfit: showProfit,
          wide: wide,
          week: week,
          destinations: destinations,
        ),
        SizedBox(height: tokens.spacing.s32),
        WeeklyTopItems(report: report, reading: reading, currency: currency),
        SizedBox(height: tokens.spacing.s32),
        WeeklyRecentTransactions(
          report: report,
          currency: currency,
          onRefresh: onRetry,
        ),
        // **No "More reports" tiles under it since 2026-09-29**, removed by
        // the product owner along with the tap on *Total sales*. The page is
        // the week and nothing else; the destinations are still wired in
        // `main.dart`, so another surface can open them.
      ],
    );
  }
}

/// The card every section of this page is drawn on. The old screen's
/// `bgMid` box with a `mutedGreen` edge at radius 12.
final class WeeklyReportCard extends StatelessWidget {
  const WeeklyReportCard({required this.child, this.padding, super.key});

  final Widget child;
  final double? padding;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.colors.surface.raised,
        // The panel shape, not the row shape. See `AppRadii.xl`.
        borderRadius: BorderRadius.circular(tokens.radius.xl),
        border: Border.all(color: tokens.colors.surface.borderSubtle),
      ),
      child: Padding(
        padding: EdgeInsets.all(padding ?? tokens.spacing.s24),
        child: child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Metric cards
// ---------------------------------------------------------------------------

/// The figures that qualify the takings, two across on a phone.
///
/// **Two across, and the type scale is what makes it possible.**
/// `numericCompact` is 22 in the mono face - the role whose own note says it
/// exists for the band where `numericHero` at 30 would force a grid of figures
/// into one column - and the tiles drop the currency code, which the hero above
/// them states once. Six full-width cards became one screen.
final class _MetricGrid extends StatelessWidget {
  const _MetricGrid({
    required this.report,
    required this.reading,
    required this.showProfit,
    required this.wide,
    required this.week,
    required this.destinations,
  });

  /// Only the takings page is reached from here; the rest are [_ReportLinks].
  /// Transactions elaborates into the same surface the hero figure does,
  /// because it is the same reading counted a different way.
  final WeeklyReportDestinations destinations;

  final TenantWeeklyReport? report;

  /// See `WeeklyReportContents.reading`. A card that is reading draws a
  /// placeholder where its figure will be, rather than an em dash saying the
  /// figure does not exist.
  final bool reading;
  final bool showProfit;
  final bool wide;
  final TenantReportWeek week;

  String get _comparisonLabel => _weeklyComparisonLabel(week);

  /// The count spread over the days that have actually traded.
  ///
  /// **Elapsed days, not seven.** A Wednesday divided by a whole week reports a
  /// shop doing half the business it is doing, which is the kind of plausible
  /// wrong figure this page is most able to do damage with.
  String _perDay(TenantWeeklyReport data) {
    final days = data.revenueByWeekday.where((value) => value > 0).length;
    if (days < 2) return days == 1 ? 'On one day' : '';
    final each = data.transactions / days;
    return '${each.toStringAsFixed(1)} a day over $days days';
  }

  /// Whether the takings on screen were counted here rather than served.
  ///
  /// **Said out loud rather than left to be noticed.** These figures normally
  /// come from the server, which counts sales this device may never have held;
  /// when they come from the sale records on the device instead, that is a
  /// different claim about the same week and a shopkeeper is entitled to know
  /// which one they are reading.
  ///
  /// **Not while the server is still answering, which is the whole of the
  /// 2026-09-20 report.** The guard draws the device figures first on purpose,
  /// so on every open three cards grew an amber label and the callout above
  /// them a paragraph, and half a second later all four went away again. The
  /// same rule as the callout: see [WeeklyReportContents.serverCouldNotBeReached].
  static bool _countedHere(BuildContext context, TenantWeeklyReport? data) =>
      _weeklyCountedHere(context, data);

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final data = report;
    final previous = data?.previousTotals;
    // Net of returns where the server sent them, so this card and TOTAL SALES
    // describe the same money.
    final profit = data?.totals?.netOrGrossProfitReport;
    final net = data?.netProfitReport;
    // Both money questions elaborate into the same place: it is the only
    // surface that can answer either.
    final cards = <Widget>[
      // **Only where the session may see cost.** `TenantProfitReport` puts the
      // margin behind owner and administrator everywhere else in this app, and
      // a report page is not the place it stops being true.
      if (showProfit)
        _MetricCard(
          cardKey: const ValueKey('weekly-report-profit'),
          title: 'GROSS PROFIT',
          reading: reading,
          // Drawn as a ceiling where it is not exact, and refused only where
          // the arithmetic is impossible - see `TenantProfitReport.isDrawable`.
          // The comparison below stays on `isShowable`: a bound may be read,
          // but it may not become a percentage.
          value: profit == null || !profit.isDrawable
              ? '—'
              : weeklyReportAmount(profit.profit),
          subtitle: profit != null && !profit.isShowable
              ? tenantProfitCeilingNote(profit)
              : null,
          detail: switch (profit?.marginPercent) {
            null => null,
            final margin => '${margin.toStringAsFixed(1)}% margin',
          },
          // Both weeks, never one of each: a week whose profit may not be
          // shown may not be the denominator of an arrow either.
          change:
              profit != null &&
                  profit.isShowable &&
                  (previous?.netOrGrossProfitReport.isShowable ?? false)
              ? TenantWeeklyReport.change(
                  profit.profit,
                  previous?.netOrGrossProfitReport.profit,
                )
              : null,
          comparisonLabel: _comparisonLabel,
          icon: Icons.trending_up,
          emphasis: (profit?.profit ?? 0) >= 0,
        ),
      // **A card of its own rather than a changed GROSS PROFIT.** The two
      // answer different questions - what the stock earned, and what the
      // business kept - and a week where they diverge sharply is exactly the
      // week somebody needs to see both. It appears only where the spending
      // was read; a week with no expense reading shows gross alone, as this
      // page always did.
      if (showProfit && net != null)
        _MetricCard(
          cardKey: const ValueKey('weekly-report-net-profit'),
          title: 'NET PROFIT',
          reading: reading,
          value: net.isDrawable ? weeklyReportAmount(net.netProfit) : '—',
          subtitle: net.isShowable
              ? 'After expenses'
              : net.basis == TenantNetProfitBasis.expensesUnread
              ? 'At most: some spending is not counted'
              : tenantProfitCeilingNote(net.gross),
          // **No comparison arrow.** The week before was not read for
          // spending, so there is no prior net profit to compare against, and
          // an arrow drawn from the gross figures would describe a different
          // quantity than the one above it.
          comparisonLabel: _comparisonLabel,
          icon: Icons.account_balance_wallet_outlined,
          emphasis: !net.isLoss,
        ),
      _MetricCard(
        cardKey: const ValueKey('weekly-report-transactions'),
        title: 'TRANSACTIONS',
        reading: reading,
        value: data == null || !data.hasTakings
            ? _noFigure
            : '${data.transactions}',
        subtitle: _weeklyCountedHere(context, data) ? _countedLabel : null,
        change: TenantWeeklyReport.change(
          (data?.transactions ?? 0).toDouble(),
          previous?.netOrGrossTransactions.toDouble(),
        ),
        comparisonLabel: _comparisonLabel,
        detail: data == null || !data.hasTakings || data.transactions == 0
            ? null
            : _perDay(data),
        icon: Icons.receipt_long,
        emphasis: true,
      ),
      // **What the week cost, beside what it took.** Spending reached this page
      // only inside NET PROFIT, which is the two of them already subtracted -
      // so a week whose margin fell said nothing about whether the takings
      // dropped or the costs rose, which is the first question anybody asks of
      // it.
      //
      // Drawn on the same terms as the net figure it feeds: only where the
      // session may be shown cost, and only where the week was read whole.
      // `_weekExpenses` refuses a filtered week outright, because a colleague
      // and a category each own none of the rent.
      if (showProfit) ...<Widget>[
        if (data?.expenses case final spend?)
          _MetricCard(
            cardKey: const ValueKey('weekly-report-expenses'),
            title: 'EXPENSES',
            reading: reading,
            value: weeklyReportAmount(spend.total),
            detail: switch (spend.records.length) {
              0 => 'Nothing recorded',
              1 => '1 payment',
              final count => '$count payments',
            },
            subtitle: spend.truncated
                ? 'Counted from the newest records only'
                : null,
            // **`emphasis: true`, after seeing it on a device.** The card's
            // other setting paints the glyph in the problem colour, which was
            // written for a profit card showing a loss - and spending is not a
            // loss. A red mark beside an ordinary week's rent reads as
            // something being wrong when nothing is.
            icon: Icons.account_balance_wallet_outlined,
            emphasis: true,
          ),
      ],
      // **Where the old page's *Low stock* card was.** This product has no
      // reorder level to read - see `weekly_report.dart` - and a card is not
      // worth inventing a number for.
      _MetricCard(
        cardKey: const ValueKey('weekly-report-average'),
        title: 'AVERAGE SALE',
        reading: reading,
        value: data == null || !data.hasTakings || data.transactions == 0
            ? '—'
            : weeklyReportAmount(data.averageSale),
        subtitle: _countedHere(context, data) ? _countedLabel : null,
        change: data == null
            ? null
            : TenantWeeklyReport.change(
                data.averageSale,
                data.previousAverageSale,
              ),
        comparisonLabel: _comparisonLabel,
        // **What it is an average of.** Every other tile carries a supporting
        // line and this one had none, so it sat visibly emptier than the tile
        // beside it - and a mean with no count under it is the one figure on
        // this grid a person is entitled to distrust.
        detail: data == null || !data.hasTakings || data.transactions == 0
            ? null
            : data.transactions == 1
            ? 'Over 1 sale'
            : 'Over ${data.transactions} sales',
        icon: Icons.receipt,
        emphasis: true,
      ),
      // Where *Shifts today* was, for the reason given in `weekly_report.dart`.
      _MetricCard(
        cardKey: const ValueKey('weekly-report-items'),
        title: 'ITEMS SOLD',
        value: data == null ? '—' : '${data.itemsSold}',
        // **What came back, beside what stayed sold.** `17` net of four
        // returns is a different week from `17` with nothing returned, and the
        // count alone printed the same figure for both.
        detail: switch (data?.returnedUnits) {
          null => null,
          0 => 'None returned',
          1 => '1 returned',
          final units => '$units returned',
        },
        // **Truncation first, because it is the larger caveat**, and then the
        // basis. This card counted every unit that crossed the counter while
        // every figure around it had its returns taken off, so a week with
        // returns read more items than its takings implied and said nothing
        // about why. It nets now; where the returns could not be read it is
        // still gross, and that is what the second line is for.
        subtitle: data == null
            ? null
            : data.scanWasTruncated
            ? 'Counted from the newest sales only'
            : data.netsItemsSold
            ? null
            : 'Before returns',
        icon: Icons.inventory_2_outlined,
        emphasis: true,
      ),
    ];

    // **Two across on a phone as well, which is the change.** Below `medium`
    // this was a `Column` of full-width cards, so six figures were six
    // screenfuls. `numericCompact` is sized for exactly this - see its note in
    // the type scale - and the tiles drop the currency code the hero states.
    final perRow = wide ? 4 : 2;
    final rows = <Widget>[];
    for (var start = 0; start < cards.length; start += perRow) {
      final row = cards.sublist(start, (start + perRow).clamp(0, cards.length));
      rows.add(
        // **`IntrinsicHeight` so the cards in a row match**, which is what the
        // old grid got for free from a `Row` inside a bounded column. Inside a
        // `ListView` the height is unbounded, and `CrossAxisAlignment.stretch`
        // against an unbounded height is an assertion rather than a layout.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (var index = 0; index < perRow; index++) ...<Widget>[
                if (index > 0) SizedBox(width: tokens.spacing.s16),
                Expanded(
                  child: index < row.length ? row[index] : const SizedBox(),
                ),
              ],
            ],
          ),
        ),
      );
      if (start + perRow < cards.length) {
        rows.add(SizedBox(height: tokens.spacing.s16));
      }
    }
    return Column(children: rows);
  }
}

/// What a card prints where it has no figure at all.
const String _noFigure = '\u2014';

// ---------------------------------------------------------------------------
// Shared between the hero, the grid and the links
// ---------------------------------------------------------------------------

/// The old screen's `vs last week` / `vs prior week`.
String _weeklyComparisonLabel(TenantReportWeek week) =>
    week.isCurrent ? 'vs last week' : 'vs prior week';

/// Whether the takings on screen were counted here rather than served.
bool _weeklyCountedHere(BuildContext context, TenantWeeklyReport? data) =>
    data?.totals?.basis == TenantSalesTotalsBasis.device &&
    WeeklyReportContents.serverCouldNotBeReached(context);

const String _countedLabel = 'On this device';

final class _TakingsHero extends StatelessWidget {
  const _TakingsHero({
    required this.report,
    required this.reading,
    required this.currency,
    required this.week,
  });

  final TenantWeeklyReport? report;
  final bool reading;
  final TenantReportingCurrency? currency;
  final TenantReportWeek week;

  /// The week's shape, in major units, seven entries.
  List<double> get _bars =>
      report?.revenueByWeekday ?? List<double>.filled(7, 0);

  /// The subline: the code, the basis and the count, in that order.
  ///
  /// **The transaction count lives here rather than in a tile of its own.** It
  /// is the divisor of the average sale two rows down, not a seventh figure of
  /// equal standing, and a card that states takings without saying how many
  /// sales made them is half an answer.
  String? _subline() {
    final data = report;
    if (data == null || !data.hasTakings) return null;
    final parts = <String>[
      if (currency?.code case final code?) code,
      if (data.netsReturns) 'net of returns',
      data.transactions == 1 ? '1 sale' : '${data.transactions} sales',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final data = report;
    final delta = TenantWeeklyReport.change(
      data?.sales ?? 0,
      data?.previousTotals?.netOrGrossSales,
    );
    final caveat = _weeklyCountedHere(context, data) ? _countedLabel : null;
    // **`hasTakings`, not `data != null`, and zero is why.** A week whose
    // server totals never landed and whose own sales could not be counted has
    // takings of *unknown*; printing `KES 0.00` over a week of trade would be
    // the plausible wrong figure this page is most able to do damage with.
    final figure = data == null || !data.hasTakings
        ? _noFigure
        // **No code on the figure: the subline under it carries one.** Printing
        // `KES` twice a line apart is the page talking over itself.
        : weeklyReportHeroMoney(null, data.sales);
    final split = _splitDecimals(figure);
    // **Not a door since 2026-09-29.** It opened the sales totals page, and the
    // product owner took that away so a tap on the card's bars can show a
    // day's figure instead of leaving the page. A `PressSurface` with a null
    // `onPressed` is inert - the figure cards below are drawn the same way -
    // and it keeps the card filling its row beside the wide chart.
    final role = tokens.colors.action.secondary;
    return PressSurface(
      borderRadius: BorderRadius.circular(tokens.radius.xl),
      onPressed: null,
      hoverOverlay: role.hoverWash(),
      pressedOverlay: role.pressedWash(),
      minimumTapTarget: tokens.density.minimumTapTarget,
      fillWidth: true,
      fillHeight: true,
      child: WeeklyReportCard(
        key: const ValueKey('weekly-report-sales'),
        padding: tokens.spacing.s20,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Text(
                    'TOTAL SALES',
                    style: tokens.typography.labelEyebrow.copyWith(
                      color: tokens.colors.text.tertiary,
                    ),
                  ),
                ),
                // **The comparison takes the corner a decorative glyph had.**
                // On the one card whose whole job is a single number, an icon
                // and a figure competing for the same corner is one thing too
                // many, and the figure is what a person came for.
                if (delta != null && !reading)
                  _DeltaChip(delta: delta, rising: delta >= 0),
              ],
            ),
            SizedBox(height: tokens.spacing.s12),
            if (reading)
              SkeletonGroup(
                semanticLabel: 'Reading this week’s takings.',
                child: SkeletonLine(
                  widthFactor: WeeklyReportMetrics.readingWidthFactor,
                  style: tokens.typography.numericHero,
                  tone: SkeletonTone.onRaised,
                ),
              )
            else
              // **The decimals are set down, not dropped.** Two of the five
              // characters in `17000.00` carry a hundredth of the information
              // and a fifth of the width; a shopkeeper reads the shillings.
              // They stay legible - one step of emphasis, not a fade - because
              // a figure whose end is unreadable is a figure to double-check.
              Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(text: split.$1),
                    if (split.$2 case final decimals?)
                      TextSpan(
                        text: decimals,
                        style: tokens.typography.numericBody.copyWith(
                          color: Color.lerp(
                            tokens.colors.status.ok.fg,
                            tokens.colors.surface.raised,
                            WeeklyReportMetrics.decimalRecession,
                          ),
                        ),
                      ),
                  ],
                ),
                key: const ValueKey('weekly-report-sales-figure'),
                style: tokens.typography.numericHero.copyWith(
                  color: figure == _noFigure
                      ? tokens.colors.text.primary
                      : tokens.colors.status.ok.fg,
                ),
              ),
            if (_subline() case final line?) ...<Widget>[
              SizedBox(height: tokens.spacing.s4),
              Text(
                line,
                key: const ValueKey('weekly-report-sales-subline'),
                style: tokens.typography.caption.copyWith(
                  color: tokens.colors.text.secondary,
                ),
              ),
            ],
            if (caveat case final note?) ...<Widget>[
              SizedBox(height: tokens.spacing.s8),
              Text(
                note,
                style: tokens.typography.caption.copyWith(
                  color: tokens.colors.status.attention.fg,
                ),
              ),
            ],
            SizedBox(height: tokens.spacing.s8),
            // **The week's shape inside the card that states its total.** It
            // was a separate card with an axis, five screens further down; a
            // reader asking "how did the week go" wants the total and the
            // shape in one glance, and the axis was never what answered that.
            _WeekStrip(
              week: week,
              values: _bars,
              reading: reading,
              currency: currency,
              comparison: _weeklyComparisonLabel(week),
            ),
          ],
        ),
      ),
    );
  }
}

/// The seven bars under the takings: a week's shape, no axis.
///
/// **No gridlines and no money rule, deliberately.** This is a sparkline with
/// days on it, read for its silhouette rather than measured against - the
/// figure it belongs to is printed directly above it, which is where a person
/// looks for the amount. `WeeklyRevenueChart` is still the measured reading,
/// and still what a screen with room for it draws.
///
/// **A tapped day says what it took, since 2026-09-29.** The product owner took
/// the card's tap to the sales totals page away and asked for this instead: a
/// tap on a bar reads that day's figure out above the strip, and a second tap
/// on the same bar puts it away. The whole strip is the target and the day is
/// the one under the finger - seven bars across a phone are narrower than a
/// tap target each, and a strip-wide one is not.
final class _WeekStrip extends StatefulWidget {
  const _WeekStrip({
    required this.week,
    required this.values,
    required this.reading,
    required this.currency,
    required this.comparison,
  });

  final TenantReportWeek week;
  final List<double> values;
  final bool reading;
  final TenantReportingCurrency? currency;
  final String comparison;

  @override
  State<_WeekStrip> createState() => _WeekStripState();
}

final class _WeekStripState extends State<_WeekStrip> {
  static const List<String> _days = <String>['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  /// The day whose figure is read out, or null where none has been tapped.
  int? _chosen;

  @override
  void didUpdateWidget(_WeekStrip old) {
    super.didUpdateWidget(old);
    // Another week, or the same week filtered differently: the figure read
    // out belonged to the bars that were there before.
    if (old.week.monday != widget.week.monday ||
        !listEquals(old.values, widget.values)) {
      _chosen = null;
    }
  }

  /// The day under [dx], measured against the strip's own width at the moment
  /// of the tap.
  ///
  /// **Not a `LayoutBuilder`**: on a wide screen this card sits beside the
  /// chart under an `IntrinsicHeight`, and a `LayoutBuilder` cannot answer the
  /// intrinsic measurement that asks for - it throws. The strip is as wide as
  /// its bars, so its own box is the measure.
  void _choose(double dx) {
    final width = (context.findRenderObject() as RenderBox?)?.size.width ?? 0;
    if (widget.reading || width <= 0) return;
    final index = (dx / (width / _days.length)).floor().clamp(
      0,
      _days.length - 1,
    );
    setState(() => _chosen = _chosen == index ? null : index);
  }

  /// `Wed 30 Sep · KES 4500.00`: the day, and what it took.
  String _readout(int index) =>
      '${DateFormat('EEE d MMM').format(widget.week.monday.add(Duration(days: index)))}'
      ' · ${weeklyReportMoney(widget.currency, widget.values[index])}';

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final values = widget.values;
    final reading = widget.reading;
    final peak = values.fold<double>(0, (high, v) => v > high ? v : high);
    final dim = Color.lerp(
      tokens.colors.status.ok.fg,
      tokens.colors.surface.raised,
      WeeklyReportMetrics.quietBarRecession,
    )!;
    // The last elapsed day of the week in progress, so the bar a person is
    // adding to is the one picked out. A finished week picks out its best day.
    // A day somebody tapped outranks either.
    final chosen = reading ? null : _chosen;
    final picked =
        chosen ??
        (widget.week.isCurrent
            ? values.lastIndexWhere((value) => value > 0)
            : values.indexWhere((value) => value == peak && value > 0));
    return Semantics(
      // Every day's figure, because a screen reader cannot point at a bar.
      label:
          'The week by day, ${widget.comparison}. '
          '${<String>[for (var index = 0; index < _days.length; index++) _readout(index)].join(', ')}.',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // **Always laid out, empty or not**, so choosing a day never moves
          // the card under the finger that chose it.
          Text(
            chosen == null ? '' : _readout(chosen),
            key: const ValueKey('weekly-report-day-value'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tokens.typography.caption.copyWith(
              color: tokens.colors.text.primary,
            ),
          ),
          SizedBox(height: tokens.spacing.s8),
          GestureDetector(
            key: const ValueKey('weekly-report-day-bars'),
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => _choose(details.localPosition.dx),
            child: SizedBox(
              height: WeeklyReportMetrics.stripHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  for (
                    var index = 0;
                    index < _days.length;
                    index++
                  ) ...<Widget>[
                    if (index > 0) SizedBox(width: tokens.spacing.s8),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: <Widget>[
                          SizedBox(
                            height: reading
                                ? WeeklyReportMetrics.stripBarHeight *
                                      WeeklyReportMetrics
                                          .readingBarHeights[index]
                                : _height(values[index], peak),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: reading
                                    ? tokens.colors.surface.field
                                    : values[index] <= 0
                                    ? tokens.colors.surface.field
                                    : index == picked
                                    ? tokens.colors.status.ok.fg
                                    : dim,
                                borderRadius: BorderRadius.circular(
                                  tokens.radius.sm,
                                ),
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                          SizedBox(height: tokens.spacing.s8),
                          Text(
                            _days[index],
                            style: tokens.typography.caption.copyWith(
                              color: index == picked && !reading
                                  ? tokens.colors.status.ok.fg
                                  : tokens.colors.text.tertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A day's height, with a floor so a day that traded is never invisible and
  /// a day that did not is never mistaken for one that barely did.
  double _height(double value, double peak) {
    if (value <= 0) return WeeklyReportMetrics.stripFloor;
    if (peak <= 0) return WeeklyReportMetrics.stripFloor;
    final share = value / peak;
    final drawn = WeeklyReportMetrics.stripBarHeight * share;
    return drawn < WeeklyReportMetrics.stripTraded
        ? WeeklyReportMetrics.stripTraded
        : drawn;
  }
}

/// Splits a formatted amount into its shillings and its cents.
///
/// Returns the whole string and a null tail where there is no decimal point at
/// all - an em dash, or a count rather than money.
(String, String?) _splitDecimals(String figure) {
  final at = figure.lastIndexOf('.');
  if (at < 0 || at == figure.length - 1) return (figure, null);
  return (figure.substring(0, at), figure.substring(at));
}

final class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.cardKey,
    required this.title,
    required this.value,
    required this.icon,
    required this.emphasis,
    this.reading = false,
    this.change,
    this.comparisonLabel,
    this.detail,
    this.subtitle,
  });

  /// One supporting fact under the figure, in the ordinary text colour.
  ///
  /// **Every tile carries one, and that is what makes this a grid.** A tile
  /// with a comparison and a tile without were two different heights, so a row
  /// holding one of each came out ragged and four tiles read as two unrelated
  /// pairs. More than that: a figure on its own is rarely the answer - `17` is
  /// a different week from `17, with 4 back` - and the room was there.
  ///
  /// Distinct from [subtitle], which is drawn in the attention colour because
  /// it is always a caveat. This one is not: it is the rest of the reading.
  final String? detail;

  final Key cardKey;
  final String title;
  final String value;

  /// Whether the figure is still being read. See `WeeklyReportContents`.
  final bool reading;
  final IconData icon;

  /// Whether the glyph is drawn in the accent or in the problem colour. The old
  /// screen turned the profit card's icon red on a loss.
  final bool emphasis;

  /// Percentage difference against the week before, or null where there is
  /// nothing to compare with.
  final double? change;

  final String? comparisonLabel;
  final String? subtitle;

  /// **No tile leads anywhere now, and that is deliberate.** The one figure
  /// that elaborated into another page was the takings, and the takings are
  /// the hero above this grid. A tile that opened a route while the three
  /// beside it did nothing was a grid where a third of the cards were doors
  /// and nothing on them said which; `PressSurface` with a null `onPressed` is
  /// inert, so every one of them is now plainly a figure.

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final delta = change;
    final rising = (delta ?? 0) >= 0;
    final role = tokens.colors.action.secondary;
    return PressSurface(
      borderRadius: BorderRadius.circular(tokens.radius.xl),
      onPressed: null,
      hoverOverlay: role.hoverWash(),
      pressedOverlay: role.pressedWash(),
      minimumTapTarget: tokens.density.minimumTapTarget,
      // A card is as wide as its grid cell and as tall as what it says.
      fillWidth: true,
      // **The painted surface fills the row, not just its hit area.**
      // These sit two across under an `IntrinsicHeight`, and without this
      // the card with the shorter caption drew a shorter box inside a cell
      // of the right height - so a grid of four read as four unrelated
      // sizes.
      fillHeight: true,
      child: WeeklyReportCard(
        key: cardKey,
        // **Back to `s20` on 2026-09-20.** At `s16` the tiles were squat: the
        // figures sat close to four edges and the grid read as a table of
        // cells rather than as cards with something on them. This app draws
        // depth as a surface step rather than a shadow, so the room inside a
        // card is most of what makes it read as a card at all.
        padding: tokens.spacing.s20,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: WeeklyReportMetrics.tileHeight,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // **The glyph leads the label rather than facing it across the
              // card.** At two across there is not a card's width to put them at
              // opposite ends of, and a 14-point mark against its own caption
              // reads as one thing where a 20-point one across a gap reads as
              // two.
              Row(
                children: <Widget>[
                  Icon(
                    icon,
                    size: WeeklyReportMetrics.tileGlyph,
                    color: emphasis
                        ? tokens.colors.status.ok.fg
                        : tokens.colors.status.problem.fg,
                  ),
                  SizedBox(width: tokens.spacing.s8),
                  Expanded(
                    child: Text(
                      title,
                      style: tokens.typography.labelEyebrow.copyWith(
                        color: tokens.colors.text.tertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              SizedBox(height: tokens.spacing.s8),
              // The title and the glyph above are the same whether or not the
              // figure has arrived, so they are drawn for real and only the figure
              // is a placeholder - decision 35, on one card.
              if (reading)
                SkeletonGroup(
                  semanticLabel: 'Reading $title.',
                  child: SkeletonLine(
                    widthFactor: WeeklyReportMetrics.readingWidthFactor,
                    style: tokens.typography.numericCompact,
                    tone: SkeletonTone.onRaised,
                  ),
                )
              // **A roll rather than a swap, because this figure is expected to
              // change under a reader's eyes.** The takings are drawn from what
              // this device counted and then corrected when the server answers; a
              // number that silently becomes a different number is the kind of
              // thing somebody notices afterwards and does not trust. `numeric`
              // roles are tabular, so the digits that did not change hold still.
              //
              // An em dash is not a figure and cannot roll to one, so it stays a
              // plain `Text` until there is something to count.
              else if (value == _noFigure)
                Text(
                  value,
                  style: tokens.typography.numericCompact.copyWith(
                    color: tokens.colors.text.primary,
                  ),
                )
              else
                RollingNumber(
                  value: value,
                  style: tokens.typography.numericCompact.copyWith(
                    color: tokens.colors.text.primary,
                  ),
                ),
              if (detail case final line?) ...<Widget>[
                SizedBox(height: tokens.spacing.s4),
                Text(
                  line,
                  style: tokens.typography.caption.copyWith(
                    color: tokens.colors.text.secondary,
                  ),
                ),
              ],
              // **The same chip the hero wears, not a second dialect.** The
              // comparison label that used to trail it (`vs last week`) is said
              // once on the week stepper at the top of the page rather than five
              // times down it.
              if (delta != null && !reading) ...<Widget>[
                SizedBox(height: tokens.spacing.s8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _DeltaChip(delta: delta, rising: rising),
                ),
              ],
              if (subtitle case final note?) ...<Widget>[
                SizedBox(height: tokens.spacing.s8),
                Text(
                  note,
                  style: tokens.typography.caption.copyWith(
                    color: tokens.colors.status.attention.fg,
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

/// The comparison against the week before, as a chip beside a hero figure.
///
/// **DESIGN RULES 4: never colour alone.** The arrow states the direction and
/// the sign states it a second time, so the chip survives a colourblind reader
/// and a monochrome receipt printer. The tint is a third telling, not the only
/// one.
final class _DeltaChip extends StatelessWidget {
  const _DeltaChip({required this.delta, required this.rising});

  final double delta;
  final bool rising;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final status = rising
        ? tokens.colors.status.ok
        : tokens.colors.status.problem;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: status.bg,
        borderRadius: BorderRadius.circular(tokens.radius.pill),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.s8,
          vertical: tokens.spacing.s4,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              rising ? Icons.arrow_upward : Icons.arrow_downward,
              size: WeeklyReportMetrics.deltaGlyph,
              color: status.fg,
            ),
            SizedBox(width: tokens.spacing.s4),
            Text(
              '${rising ? '+' : '\u2212'}'
              '${delta.abs().toStringAsFixed(1)}%',
              style: tokens.typography.numericBody.copyWith(color: status.fg),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filters
// ---------------------------------------------------------------------------

final class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.week,
    required this.sessionContext,
    required this.soldById,
    required this.selfUid,
    required this.categoryId,
    required this.onChooseWeek,
    required this.onChooseMember,
    required this.onChooseCategory,
    required this.stacked,
  });

  final TenantReportWeek week;
  final SalesTotalsSessionContext sessionContext;
  final String? soldById;
  final String? selfUid;
  final String? categoryId;
  final ValueChanged<int> onChooseWeek;
  final ValueChanged<String?> onChooseMember;
  final ValueChanged<String?> onChooseCategory;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final navigator = _WeekNavigator(
      week: week,
      onChoose: onChooseWeek,
      fillWidth: stacked,
    );
    final category = AppSelect<String?>(
      key: const ValueKey('weekly-report-category'),
      label: 'Category',
      // **The label goes into the control rather than above it on a phone.**
      // Two stacked captions over two stacked wells is four lines to say
      // *these are the filters*, which the icons in them already say. The label
      // is still the control's accessible name; see `AppSelect.dense`.
      dense: stacked,
      leading: Icons.category_outlined,
      value: sessionContext.categories.nameOf(categoryId ?? '') == null
          ? null
          : categoryId,
      enabled: sessionContext.categories.readable,
      onChanged: onChooseCategory,
      items: <AppSelectItem<String?>>[
        const AppSelectItem<String?>(
          key: ValueKey('weekly-report-category-all'),
          value: null,
          label: 'All categories',
        ),
        for (final option in sessionContext.categories.items)
          AppSelectItem<String?>(
            key: ValueKey('weekly-report-category-${option.id}'),
            value: option.id,
            label: option.name,
          ),
      ],
    );
    final member = AppSelect<String?>(
      key: const ValueKey('weekly-report-member'),
      label: 'Sold by',
      dense: stacked,
      leading: Icons.person_outline,
      value: sessionContext.staff.contains(soldById ?? '') ? soldById : null,
      enabled: sessionContext.staff.readable,
      onChanged: onChooseMember,
      items: <AppSelectItem<String?>>[
        const AppSelectItem<String?>(
          key: ValueKey('weekly-report-member-all'),
          value: null,
          label: 'All staff',
        ),
        for (final uid in sessionContext.staff.uids)
          AppSelectItem<String?>(
            key: ValueKey('weekly-report-member-$uid'),
            value: uid,
            label: tenantStaffLabel(
              uid,
              names: sessionContext.staff.names,
              selfUid: selfUid,
            ),
          ),
      ],
    );

    // **A filter that lists part of a business must say so.** Both lists are
    // one bounded page; the totals page has always told a reader when there are
    // more, and this bar - which offers the same two filters over the same
    // session context - told them neither. A chooser that looks complete and is
    // not is worse than one that is plainly partial.
    final categoryField = _FilterField(
      field: category,
      notice: sessionContext.categories.truncated
          ? 'This business has more categories than are listed here.'
          : null,
      noticeKey: const ValueKey('weekly-report-categories-truncated'),
    );
    final memberField = _FilterField(
      field: member,
      notice: sessionContext.staff.truncated
          ? 'This business has more members than are listed here.'
          : null,
      noticeKey: const ValueKey('weekly-report-staff-truncated'),
    );

    if (stacked) {
      // **No card around it, and that is the point.** The bar was a panel of
      // its own with two labelled wells inside it, which came to most of a
      // phone screen - on a page that had just been reordered to put the
      // figures where they could be seen. The stepper is the panel now, and the
      // two filters are chips under it.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          navigator,
          SizedBox(height: tokens.spacing.s8),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: categoryField),
                SizedBox(width: tokens.spacing.s8),
                Expanded(child: memberField),
              ],
            ),
          ),
        ],
      );
    }
    return WeeklyReportCard(
      padding: tokens.spacing.s20,
      child: Row(
        // Top rather than centre, since either field can now carry a second
        // line and a row of two unequal heights should align on the control
        // they share, not on the middle of whichever grew.
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          navigator,
          SizedBox(width: tokens.spacing.s16),
          Expanded(child: categoryField),
          SizedBox(width: tokens.spacing.s16),
          Expanded(child: memberField),
        ],
      ),
    );
  }
}

/// One filter control, and what is known about the list behind it.
final class _FilterField extends StatelessWidget {
  const _FilterField({
    required this.field,
    required this.notice,
    required this.noticeKey,
  });

  final Widget field;
  final String? notice;
  final Key noticeKey;

  @override
  Widget build(BuildContext context) {
    final notice = this.notice;
    if (notice == null) return field;
    final tokens = AppTokens.componentOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        field,
        SizedBox(height: tokens.spacing.s8),
        Text(
          notice,
          key: noticeKey,
          style: tokens.typography.caption.copyWith(
            color: tokens.colors.text.secondary,
          ),
        ),
      ],
    );
  }
}

/// [Expanded] where the row has a width to give, and the child alone where it
/// does not. Exists so [_WeekNavigator] states its two layouts once each
/// rather than twice over.
final class _Span extends StatelessWidget {
  const _Span({required this.fill, required this.child});

  final bool fill;
  final Widget child;

  @override
  Widget build(BuildContext context) => fill ? Expanded(child: child) : child;
}

/// The old screen's week stepper: back a week, forward a week, never past the
/// week in progress.
final class _WeekNavigator extends StatelessWidget {
  const _WeekNavigator({
    required this.week,
    required this.onChoose,
    this.fillWidth = false,
  });

  final TenantReportWeek week;
  final ValueChanged<int> onChoose;

  /// Whether the stepper spans the bar or sits at its own width.
  ///
  /// **On a phone it is the bar.** Centred at its intrinsic width it left dead
  /// space either side and put the two chevrons a thumb's width apart in the
  /// middle; spanning, each sits at an edge a thumb already reaches. Beside
  /// two filter fields on a wider screen it is one control among three and
  /// takes only what it needs - and an `Expanded` inside a row that is itself
  /// shrink-wrapping is an assertion rather than a layout, which is what made
  /// this a flag rather than a constant.
  final bool fillWidth;

  String get _label {
    if (week.offset == 0) return 'This week';
    if (week.offset == -1) return 'Last week';
    return '${weeklyReportDayFormat.format(week.monday)} – '
        '${weeklyReportDayFormat.format(week.sunday)}';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.colors.surface.field,
        // The panel shape, because on a phone this *is* the bar rather than a
        // control sitting inside one.
        borderRadius: BorderRadius.circular(tokens.radius.lg),
        border: Border.all(color: tokens.colors.surface.borderSubtle),
      ),
      child: Row(
        mainAxisSize: fillWidth ? MainAxisSize.max : MainAxisSize.min,
        children: <Widget>[
          IconButton(
            key: const ValueKey('weekly-report-previous-week'),
            tooltip: 'Previous week',
            icon: const Icon(Icons.chevron_left),
            color: tokens.colors.text.secondary,
            onPressed: () => onChoose(week.offset - 1),
          ),
          _Span(
            fill: fillWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  _label,
                  key: const ValueKey('weekly-report-week-label'),
                  style: tokens.typography.labelMedium.copyWith(
                    color: tokens.colors.text.primary,
                  ),
                ),
                Text(
                  '${weeklyReportDayFormat.format(week.monday)} – '
                  '${weeklyReportDayFormat.format(week.sunday)}',
                  style: tokens.typography.caption.copyWith(
                    color: tokens.colors.text.tertiary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('weekly-report-next-week'),
            tooltip: 'Next week',
            icon: const Icon(Icons.chevron_right),
            color: tokens.colors.text.secondary,
            // Disabled rather than hidden on the current week, so the control
            // does not move as a person steps through the weeks.
            onPressed: week.isCurrent ? null : () => onChoose(week.offset + 1),
          ),
        ],
      ),
    );
  }
}
