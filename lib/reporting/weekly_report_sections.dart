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

import 'package:flutter/material.dart';

import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session_controller.dart';
import '../tenancy/tenant_staff_names.dart';
import '../ui/buttons.dart';
import '../ui/routes.dart';
import '../ui/fields.dart';
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

  /// The square holding a top item's glyph. The old screen's 48.
  static const double itemGlyph = 48;

  /// The square holding a transaction's payment glyph. The old screen's 40.
  static const double saleGlyph = 40;

  /// A metric card's own glyph, and the arrow beside its percentage. The old
  /// screen's 20 and 14.
  static const double cardGlyph = 20;
  static const double deltaGlyph = 14;
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
      padding: EdgeInsets.symmetric(vertical: tokens.spacing.s8),
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
        _MetricGrid(
          report: report,
          reading: reading,
          currency: currency,
          showProfit: showProfit,
          week: week,
          wide: wide,
          medium: medium,
          destinations: destinations,
        ),
        SizedBox(height: tokens.spacing.s32),
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
        SizedBox(height: tokens.spacing.s32),
        if (wide)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  flex: 2,
                  child: WeeklyRevenueChart(
                    week: week,
                    report: report,
                    reading: reading,
                    currency: currency,
                  ),
                ),
                SizedBox(width: tokens.spacing.s24),
                Expanded(
                  child: WeeklyTopItems(
                    report: report,
                    reading: reading,
                    currency: currency,
                  ),
                ),
              ],
            ),
          )
        else ...<Widget>[
          WeeklyRevenueChart(
            week: week,
            report: report,
            reading: reading,
            currency: currency,
          ),
          SizedBox(height: tokens.spacing.s24),
          WeeklyTopItems(report: report, reading: reading, currency: currency),
        ],
        SizedBox(height: tokens.spacing.s32),
        WeeklyRecentTransactions(
          report: report,
          currency: currency,
          onRefresh: onRetry,
        ),
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
        borderRadius: BorderRadius.circular(tokens.radius.md),
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

final class _MetricGrid extends StatelessWidget {
  const _MetricGrid({
    required this.report,
    required this.reading,
    required this.currency,
    required this.showProfit,
    required this.week,
    required this.wide,
    required this.medium,
    required this.destinations,
  });

  final WeeklyReportDestinations destinations;

  final TenantWeeklyReport? report;

  /// See `WeeklyReportContents.reading`. A card that is reading draws a
  /// placeholder where its figure will be, rather than an em dash saying the
  /// figure does not exist.
  final bool reading;
  final TenantReportingCurrency? currency;
  final bool showProfit;
  final TenantReportWeek week;
  final bool wide;
  final bool medium;

  /// The old screen's `vs last week` / `vs prior week`.
  String get _comparisonLabel =>
      week.isCurrent ? 'vs last week' : 'vs prior week';

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
      data?.totals?.basis == TenantSalesTotalsBasis.device &&
      WeeklyReportContents.serverCouldNotBeReached(context);

  static const String _countedLabel = 'On this device';

  /// The tap for a destination this session may open, or null.
  ///
  /// **`of` rather than a read, for the reason the hub gave**: the scope is an
  /// `InheritedNotifier`, so depending on it is what redraws this grid when the
  /// business changes. A card that survived a switch would be a door into
  /// figures the new session may not read. And the push re-establishes the
  /// scope around the child, because a route is a new subtree under the
  /// navigator rather than under this widget.
  VoidCallback? _open(BuildContext context, WeeklyReportDestination? to) {
    if (to == null) return null;
    final controller = TenantSessionScope.of(context);
    final session = controller.session;
    if (session == null || !session.canAccess(allowedRoles: to.roles)) {
      return null;
    }
    return () => Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) =>
            TenantSessionScope(controller: controller, child: to.build()),
      ),
    );
  }

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
    final takings = _open(context, destinations.salesTotals);
    final cards = <Widget>[
      _MetricCard(
        cardKey: const ValueKey('weekly-report-sales'),
        title: 'TOTAL SALES',
        reading: reading,
        // **`hasTakings`, not `data != null`, and zero is why.** A week whose
        // server totals never landed and whose own sales could not be counted
        // has takings of *unknown*; printing `KES 0.00` over a week of trade
        // would be the plausible wrong figure this page is most able to do
        // damage with.
        value: data == null || !data.hasTakings
            ? '—'
            : weeklyReportMoney(currency, data.sales),
        subtitle: _countedHere(context, data) ? _countedLabel : null,
        change: TenantWeeklyReport.change(
          data?.sales ?? 0,
          previous?.netOrGrossSales,
        ),
        comparisonLabel: _comparisonLabel,
        icon: Icons.attach_money,
        emphasis: true,
        onTap: takings,
      ),
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
              : weeklyReportMoney(currency, profit.profit),
          subtitle: profit != null && !profit.isShowable
              ? tenantProfitCeilingNote(profit)
              : null,
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
          value: net.isDrawable
              ? weeklyReportMoney(currency, net.netProfit)
              : '—',
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
        value: data == null || !data.hasTakings ? '—' : '${data.transactions}',
        subtitle: _countedHere(context, data) ? _countedLabel : null,
        change: TenantWeeklyReport.change(
          (data?.transactions ?? 0).toDouble(),
          previous?.netOrGrossTransactions.toDouble(),
        ),
        comparisonLabel: _comparisonLabel,
        icon: Icons.receipt_long,
        emphasis: true,
        onTap: takings,
      ),
      // **Where the old page's *Low stock* card was.** This product has no
      // reorder level to read - see `weekly_report.dart` - and a card is not
      // worth inventing a number for.
      _MetricCard(
        cardKey: const ValueKey('weekly-report-average'),
        title: 'AVERAGE SALE',
        reading: reading,
        value: data == null || !data.hasTakings || data.transactions == 0
            ? '—'
            : weeklyReportMoney(currency, data.averageSale),
        subtitle: _countedHere(context, data) ? _countedLabel : null,
        change: data == null
            ? null
            : TenantWeeklyReport.change(
                data.averageSale,
                data.previousAverageSale,
              ),
        comparisonLabel: _comparisonLabel,
        icon: Icons.receipt,
        emphasis: true,
      ),
      // Where *Shifts today* was, for the reason given in `weekly_report.dart`.
      _MetricCard(
        cardKey: const ValueKey('weekly-report-items'),
        title: 'ITEMS SOLD',
        value: data == null ? '—' : '${data.itemsSold}',
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
      // **The rest of the reports, as cards in the same grid.** They used to be
      // a menu in front of this page; a menu whose only job is to name six
      // things is a step between somebody and all six. Each is drawn only where
      // the session may open it, so a grid with no reconciliation rights is
      // simply the six figures.
      if (_open(context, destinations.dailySummary) case final open?)
        _ReportCard(
          cardKey: const ValueKey('weekly-report-daily-summary'),
          title: 'DAILY SUMMARY',
          description:
              'What reconciliation settled for each recent day, and why a day '
              'is in the state it is.',
          icon: Icons.today_outlined,
          onTap: open,
        ),
      if (_open(context, destinations.monthlyReport) case final open?)
        _ReportCard(
          cardKey: const ValueKey('weekly-report-monthly'),
          title: 'MONTHLY REPORT',
          description:
              'The same reading over a chosen calendar month, which no '
              'standing period can name once the month has ended.',
          icon: Icons.calendar_month_outlined,
          onTap: open,
        ),
      if (_open(context, destinations.differences) case final open?)
        _ReportCard(
          cardKey: const ValueKey('weekly-report-differences'),
          title: 'DIFFERENCES',
          // **A figure, because the home tile's badge is one.** §9: a figure
          // alone is not a status, so the count is said in words here rather
          // than left as a number beside a label.
          description: switch (destinations.openDifferenceCount?.call(
            TenantSessionScope.of(context),
          )) {
            null =>
              'Every difference reconciliation recorded and could not resolve.',
            0 => 'Nothing is open. Every difference has been resolved.',
            1 => 'One difference is open and has not been resolved.',
            final count =>
              '$count differences are open and have not been resolved.',
          },
          icon: Icons.rule_folder_outlined,
          onTap: open,
        ),
      if (_open(context, destinations.stockMovements) case final open?)
        _ReportCard(
          cardKey: const ValueKey('weekly-report-stock-movements'),
          title: 'STOCK MOVEMENTS',
          description:
              'Everything that moved stock across the business - sales, '
              'returns and corrections - newest first.',
          icon: Icons.swap_vert_outlined,
          onTap: open,
        ),
    ];

    if (!medium) {
      return Column(
        children: <Widget>[
          for (final card in cards) ...<Widget>[
            card,
            if (card != cards.last) SizedBox(height: tokens.spacing.s16),
          ],
        ],
      );
    }
    // Four across on a wide screen and two on a tablet, which is exactly the
    // old screen's grid; the trailing card fills the row it starts.
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

/// A report in the grid: a door with a sentence instead of a figure.
///
/// **The same box as [_MetricCard], deliberately.** These sit in one grid with
/// the figures, so a different container would read as a different kind of
/// thing on a page whose whole argument is that they are not. What differs is
/// what fills it: a metric states a number and may lead somewhere, a report
/// states what is behind it and always does. Neither invents a figure it would
/// have to read the server to know.
final class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.cardKey,
    required this.title,
    required this.description,
    required this.icon,
    required this.onTap,
  });

  final Key cardKey;
  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final role = tokens.colors.action.secondary;
    return PressSurface(
      borderRadius: BorderRadius.circular(tokens.radius.md),
      onPressed: onTap,
      hoverOverlay: role.hoverWash(),
      pressedOverlay: role.pressedWash(),
      minimumTapTarget: tokens.density.minimumTapTarget,
      fillWidth: true,
      child: WeeklyReportCard(
        key: cardKey,
        padding: tokens.spacing.s20,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    style: tokens.typography.labelEyebrow.copyWith(
                      color: tokens.colors.text.tertiary,
                    ),
                  ),
                ),
                Icon(
                  icon,
                  size: WeeklyReportMetrics.cardGlyph,
                  color: tokens.colors.status.ok.fg,
                ),
              ],
            ),
            SizedBox(height: tokens.spacing.s12),
            Text(
              description,
              style: tokens.typography.bodyMedium.copyWith(
                color: tokens.colors.text.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
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
    this.subtitle,
    this.onTap,
  });

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

  /// Where this figure is elaborated, or null where nothing elaborates it.
  ///
  /// **Null is a first-class answer, and the layout does not change for it.**
  /// The old app's grid mixed both - *Total sales* opened its report and *Low
  /// stock* opened nothing - so a card that leads somewhere and a card that
  /// only states a figure have to sit in one grid without one of them looking
  /// broken. `PressSurface` takes a null `onPressed` as inert: no hover, no
  /// pressed overlay, no focus ring, no spring, and the same box. So both
  /// kinds are built by the same code path and neither is a special case.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final delta = change;
    final rising = (delta ?? 0) >= 0;
    final deltaColor = rising
        ? tokens.colors.status.ok.fg
        : tokens.colors.status.problem.fg;
    final role = tokens.colors.action.secondary;
    return PressSurface(
      borderRadius: BorderRadius.circular(tokens.radius.md),
      onPressed: onTap,
      hoverOverlay: role.hoverWash(),
      pressedOverlay: role.pressedWash(),
      minimumTapTarget: tokens.density.minimumTapTarget,
      // A card is as wide as its grid cell and as tall as what it says.
      fillWidth: true,
      child: WeeklyReportCard(
        key: cardKey,
        padding: tokens.spacing.s20,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    style: tokens.typography.labelEyebrow.copyWith(
                      color: tokens.colors.text.tertiary,
                    ),
                  ),
                ),
                Icon(
                  icon,
                  size: WeeklyReportMetrics.cardGlyph,
                  color: emphasis
                      ? tokens.colors.status.ok.fg
                      : tokens.colors.status.problem.fg,
                ),
              ],
            ),
            SizedBox(height: tokens.spacing.s12),
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
            if (delta != null && !reading) ...<Widget>[
              SizedBox(height: tokens.spacing.s8),
              Row(
                children: <Widget>[
                  // §9: never colour alone. The arrow states the direction and
                  // the sign states it again in the figure.
                  Icon(
                    rising ? Icons.arrow_upward : Icons.arrow_downward,
                    size: WeeklyReportMetrics.deltaGlyph,
                    color: deltaColor,
                  ),
                  SizedBox(width: tokens.spacing.s4),
                  Text(
                    '${delta.abs().toStringAsFixed(1)}%',
                    style: tokens.typography.caption.copyWith(
                      color: deltaColor,
                    ),
                  ),
                  SizedBox(width: tokens.spacing.s4),
                  Expanded(
                    child: Text(
                      comparisonLabel ?? '',
                      style: tokens.typography.caption.copyWith(
                        color: tokens.colors.text.tertiary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
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
    final navigator = _WeekNavigator(week: week, onChoose: onChooseWeek);
    final category = AppSelect<String?>(
      key: const ValueKey('weekly-report-category'),
      label: 'Category',
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
      return WeeklyReportCard(
        padding: tokens.spacing.s16,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(child: navigator),
            SizedBox(height: tokens.spacing.s16),
            categoryField,
            SizedBox(height: tokens.spacing.s16),
            memberField,
          ],
        ),
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

/// The old screen's week stepper: back a week, forward a week, never past the
/// week in progress.
final class _WeekNavigator extends StatelessWidget {
  const _WeekNavigator({required this.week, required this.onChoose});

  final TenantReportWeek week;
  final ValueChanged<int> onChoose;

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
        borderRadius: BorderRadius.circular(tokens.radius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            key: const ValueKey('weekly-report-previous-week'),
            tooltip: 'Previous week',
            icon: const Icon(Icons.chevron_left),
            color: tokens.colors.text.secondary,
            onPressed: () => onChoose(week.offset - 1),
          ),
          Column(
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
