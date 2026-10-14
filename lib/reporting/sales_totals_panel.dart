import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../ui/card.dart';
import '../ui/scaffold.dart';
import '../ui/stats.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import '../ui/workspace.dart';
import '../checkout/checkout_tender.dart';
import '../checkout/checkout_outbox.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../shift/shift_history.dart';
import '../tenancy/tenant_staff_names.dart';
import 'profit_report.dart';
import 'profit_statement.dart';
import 'reporting_currency.dart';
import '../expenses/expense.dart';
import '../expenses/expense_repository.dart';
import 'net_profit.dart';
import 'sales_totals.dart';
import 'shift_comparison_chart.dart';
import 'sales_totals_choosers.dart';
import 'sales_totals_session_context.dart';
import 'device_sales_totals.dart';
import '../observability/app_telemetry.dart';

/// Route showing what a business has taken over a chosen stretch of days.
///
/// This is the one surface that can answer "how much have we taken today?".
/// The daily summary reports only what nightly reconciliation has regenerated,
/// so today - the day anybody at a counter actually asks about - is normally
/// blank there. These figures are added up by the server from the sales it
/// currently holds, which is a different question and is labelled as one.
final class TenantSalesTotalsScreen extends StatelessWidget {
  const TenantSalesTotalsScreen({
    super.key,
    required this.callable,
    required this.reader,
    this.checkoutOutbox,
    this.clock,
  });

  final SalesTotalsCallable callable;

  /// Reads the canonical categories the breakdown can filter by. Nothing else
  /// on this route touches Firestore; the figures come from the callable.
  final TenantDataReader reader;
  final HiveCheckoutOutbox? checkoutOutbox;

  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Sales totals',
    contentWidth: AppContentWidth.records,
    body: TenantSalesTotalsPanel(
      callable: callable,
      reader: reader,
      checkoutOutbox: checkoutOutbox,
      clock: clock,
    ),
  );
}

/// Reads one period's totals for the selected tenant session.
///
/// The route guard owns authorization and stale-session rejection: a tenant
/// switch during an outstanding read discards it before it can report one
/// business's takings under another's name.
final class TenantSalesTotalsPanel extends StatefulWidget {
  const TenantSalesTotalsPanel({
    super.key,
    required this.callable,
    required this.reader,
    this.checkoutOutbox,
    this.clock,
    this.period = TenantSalesPeriod.today,
    this.categoryPageSize = 50,
    this.staffPageSize = 25,
  });

  final SalesTotalsCallable callable;
  final TenantDataReader reader;
  final HiveCheckoutOutbox? checkoutOutbox;
  final DateTime Function()? clock;

  /// The period the surface opens on. Today, because that is the figure the
  /// daily summary cannot give.
  final TenantSalesPeriod period;

  /// The most categories offered as filters, in one page. The same bound the
  /// checkout uses for the chips it filters its catalog by.
  final int categoryPageSize;

  /// The most colleagues offered as filters, in one page. The same bound
  /// `TenantStaffNameResolver` puts on the names it will resolve for one page.
  final int staffPageSize;

  @override
  State<TenantSalesTotalsPanel> createState() => _TenantSalesTotalsPanelState();
}

final class _TenantSalesTotalsPanelState extends State<TenantSalesTotalsPanel> {
  late TenantSalesPeriod _period = widget.period;
  String? _soldById;
  String? _categoryId;
  int _generation = 0;

  String? _loaderKey;
  TenantGuardedLoader<SalesTotalsView>? _loader;
  TenantGuardedLoader<SalesTotalsView>? _loaderCached;

  late final SalesTotalsSessionContextLoader _serverSessionContext =
      SalesTotalsSessionContextLoader(
        reader: widget.reader,
        categoryPageSize: widget.categoryPageSize,
        staffPageSize: widget.staffPageSize,
      );
  SalesTotalsSessionContextLoader? _deviceSessionContext;

  /// What the business spent over the same days, or null.
  ///
  /// Swallowed into a null on failure, like every other qualifier on this page:
  /// an expense read that did not answer must remove the net figure, never the
  /// takings a manager came here for.
  /// The day's shifts, for the per-cashier comparison, or empty.
  ///
  /// **Asked only when the period is one day**, for the reason
  /// `SalesTotalsView.shifts` gives: a shift belongs to a business date, so
  /// summing them over a longer stretch would put one cashier in several
  /// columns.
  ///
  /// **Its failure is silent and costs the screen nothing.** The figure a
  /// manager came for is the takings, and a comparison that could not be read
  /// is one card absent rather than a page lost - the same posture the expense
  /// read takes directly above.
  Future<List<TenantShiftDaySlice>> _readDayShifts(
    TenantSession session,
    TenantSalesPeriod period,
    TenantSalesTotalsQuery query,
    TenantDataReader reader,
  ) async {
    if (period != TenantSalesPeriod.today) {
      return const <TenantShiftDaySlice>[];
    }
    try {
      final repository = TenantShiftHistoryRepository(
        session: session,
        reader: reader,
      );
      return await repository.loadDayShifts(
        // The answered query's own date, not the clock's: the takings above
        // were counted over exactly this day.
        businessDate: query.startDate,
        scope: TenantShiftHistoryRepository.canReadEveryCashier(session)
            ? TenantShiftHistoryScope.everyCashier
            : TenantShiftHistoryScope.ownShifts,
      );
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'reporting.shift_slices_read',
      );
      return const <TenantShiftDaySlice>[];
    }
  }

  Future<TenantExpensePeriod?> _readExpenses(
    TenantSession session,
    TenantSalesTotalsQuery query,
    TenantDataReader reader,
  ) async {
    if (query.soldById != null ||
        query.categoryId != null ||
        !TenantExpenseRepository.canSeeInSession(session)) {
      return null;
    }
    try {
      return await TenantExpenseRepository(
        session: session,
        reader: reader,
      ).readRange(startDate: query.startDate, endDate: query.endDate);
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'reporting.expenses_range_read',
      );
      return null;
    }
  }

  void _choosePeriod(TenantSalesPeriod period) {
    if (period == _period) return;
    setState(() => _period = period);
  }

  void _chooseMember(String? soldById) {
    if (soldById == _soldById) return;
    setState(() => _soldById = soldById);
  }

  void _chooseCategory(String? categoryId) {
    if (categoryId == _categoryId) return;
    setState(() => _categoryId = categoryId);
  }

  /// Asks again for the same period, member, and category.
  ///
  /// Safe without qualification: reading totals writes nothing, so a retry can
  /// never duplicate anything the way a reconciliation request could.
  void _retry() => setState(() => _generation++);

  /// One loader per guard key, so a closure rebuilt every frame cannot spend
  /// another callable invocation on an unrelated `setState`.
  void _composeLoaders(String key) {
    if (key == _loaderKey && _loader != null) return;
    _loaderKey = key;
    final period = _period;
    final chosenMember = _soldById;
    final chosenCategory = _categoryId;
    TenantGuardedLoader<SalesTotalsView> serverLoader(
      TenantDataReader reader,
    ) => (session) async {
      final context = await _serverSessionContext.load(session);
      // A category filters the figures only while this business's own canonical
      // list still contains it. A selection carried across a tenant switch, or
      // one that has since been deleted, silently reverts to the whole catalog
      // rather than filtering by an ID this business never had.
      final categoryId =
          chosenCategory != null &&
              context.categories.nameOf(chosenCategory) != null
          ? chosenCategory
          : null;
      final gateway = TenantSalesTotalsGateway(
        session: session,
        callable: widget.callable,
        clock: widget.clock,
      );
      // The same rule for a member, with one addition: the signed-in member is
      // always answerable from the session itself, so "only mine" survives a
      // directory this role could not read.
      final soldById =
          chosenMember != null &&
              (chosenMember == gateway.selfUid ||
                  context.staff.contains(chosenMember))
          ? chosenMember
          : null;
      final totals = await gateway.load(
        gateway.createQuery(
          period: period,
          soldById: soldById,
          categoryId: categoryId,
        ),
      );
      return SalesTotalsView(
        totals: totals,
        context: context,
        // Only for the whole business over the whole period - see
        // `SalesTotalsView.expenses` for why a filtered view gets none. The
        // dates come from the answered query rather than the selection, so the
        // spending covers exactly the days the takings above it were counted
        // over.
        expenses: await _readExpenses(session, totals.query, reader),
        // Only when the period is one day, for the reason
        // `SalesTotalsView.shifts` gives.
        shifts: await _readDayShifts(session, period, totals.query, reader),
      );
    };
    _loader = serverLoader(widget.reader);
    final cache = widget.reader.cached;
    final deviceContext = cache == null
        ? null
        : _deviceSessionContext ??= SalesTotalsSessionContextLoader(
            reader: cache,
            categoryPageSize: widget.categoryPageSize,
            staffPageSize: widget.staffPageSize,
            cacheOnly: true,
          );
    _loaderCached = cache == null
        ? null
        : (session) async {
            final context = await deviceContext!.load(session);
            final categoryId =
                chosenCategory != null &&
                    context.categories.nameOf(chosenCategory) != null
                ? chosenCategory
                : null;
            final aggregator = TenantDeviceSalesAggregator(
              session: session,
              cacheReader: cache,
              outbox: widget.checkoutOutbox,
              clock: widget.clock,
            );
            final soldById =
                chosenMember != null &&
                    (chosenMember == session.uid ||
                        context.staff.contains(chosenMember))
                ? chosenMember
                : null;
            final result = await aggregator.load(
              aggregator.createQuery(
                period: period,
                soldById: soldById,
                categoryId: categoryId,
              ),
            );
            final totals = result.totals;
            if (totals == null) {
              throw StateError(
                result.truncated
                    ? 'device_sales_truncated'
                    : 'device_sales_conflicting_evidence',
              );
            }
            return SalesTotalsView(
              totals: totals,
              context: context,
              expenses: await _readExpenses(session, totals.query, cache),
            );
          };
  }

  @override
  Widget build(BuildContext context) {
    final guardKey =
        '${_period.name}:${_soldById ?? '-'}:${_categoryId ?? '-'}:'
        '$_generation';
    _composeLoaders(guardKey);
    return TenantRouteGuard<SalesTotalsView>(
      allowedRoles: TenantSalesTotalsGateway.allowedRoles,
      load: _loader!,
      loadCached: _loaderCached,
      holdsNothing: (view) => view.totals.transactions == 0,
      denied: const Center(
        key: ValueKey('sales-totals-denied'),
        child: Text('Sales totals are available to managers and owners.'),
      ),
      // The chooser stays on screen through a failure. A period that holds too
      // many sales is refused precisely so a shorter one can be picked, and
      // replacing the whole surface with an error would take that away.
      failure: (context, error) => _SalesTotalsContents(
        period: _period,
        soldById: _soldById,
        selfUid: TenantSessionScope.of(context).session?.uid,
        categoryId: _categoryId,
        sessionContext:
            _serverSessionContext.cached ?? SalesTotalsSessionContext.empty,
        onChoosePeriod: _choosePeriod,
        onChooseMember: _chooseMember,
        onChooseCategory: _chooseCategory,
        onRetry: _retry,
        // There is no answer to describe, so there is nothing to withhold. The
        // guarded session decides it wherever a figure actually exists.
        showProfit: false,
        failureMessage: _failureMessage(error),
      ),
      builder: (context, session, view) => _SalesTotalsContents(
        period: _period,
        // Taken from the answer rather than from the selection, so the chips
        // shown selected are always the filters the figure was actually read
        // with - including when a stale selection was dropped.
        soldById: view.totals.query.soldById,
        selfUid: session.uid,
        categoryId: view.totals.query.categoryId,
        sessionContext: view.context,
        onChoosePeriod: _choosePeriod,
        onChooseMember: _chooseMember,
        onChooseCategory: _chooseCategory,
        onRetry: _retry,
        // Profit is cost, and cost is owner/admin everywhere else. Read from
        // the guarded session rather than from the caller, exactly as the
        // filters above are read from the answer rather than the selection.
        showProfit: TenantProfitReport.canSeeInSession(session),
        totals: view.totals,
        net: view.netProfitReport,
        shifts: view.shifts,
      ),
    );
  }
}

/// The sentence shown for one failed read.
///
/// A `FormatException` is the strict decoder refusing an answer it could not
/// reconcile with the request. It is reported as an untrustworthy answer rather
/// than as an unavailable server, because the server did reply - and reporting
/// a figure from that reply is exactly what must not happen.
String _failureMessage(Object error) => switch (error) {
  TenantSalesTotalsException(:final failure) => switch (failure) {
    TenantSalesTotalsFailure.forbidden =>
      'This business no longer allows you to read its sales totals.',
    TenantSalesTotalsFailure.periodTooLarge =>
      'That period holds more than ${TenantSalesTotals.maximumTransactions} '
          'sales, which is more than the server will add up at once. Choose a '
          'shorter period, or read the daily summary instead.',
    TenantSalesTotalsFailure.invalidRequest =>
      'The server rejected this request, so no total was produced.',
    TenantSalesTotalsFailure.unusableSaleData =>
      'The server found a stored sale amount it could not add up, so it '
          'produced no total. Asking again will not change it.',
    TenantSalesTotalsFailure.unavailable =>
      'The totals could not be read. Nothing was changed; try again.',
    TenantSalesTotalsFailure.refused =>
      'The server refused this request, so no total was produced.',
  },
  FormatException() =>
    'The server answer could not be trusted, so no total is shown.',
  _ => 'The totals could not be read.',
};

final class _SalesTotalsContents extends StatelessWidget {
  const _SalesTotalsContents({
    required this.period,
    required this.soldById,
    required this.selfUid,
    required this.categoryId,
    required this.sessionContext,
    required this.onChoosePeriod,
    required this.onChooseMember,
    required this.onChooseCategory,
    required this.onRetry,
    required this.showProfit,
    this.totals,
    this.net,
    this.failureMessage,
    this.shifts = const <TenantShiftDaySlice>[],
  });

  final TenantSalesPeriod period;
  final String? soldById;

  /// The signed-in member, so its own chip reads "You" rather than a UID.
  final String? selfUid;

  final String? categoryId;
  final SalesTotalsSessionContext sessionContext;
  final ValueChanged<TenantSalesPeriod> onChoosePeriod;
  final ValueChanged<String?> onChooseMember;
  final ValueChanged<String?> onChooseCategory;
  final VoidCallback onRetry;

  /// Whether this session may be shown what the business made, rather than
  /// only what it took.
  final bool showProfit;

  final TenantSalesTotals? totals;

  /// The same period after what the business spent, or null where it was not
  /// read - including every filtered view.
  final TenantNetProfitReport? net;

  /// The day's shifts, for the per-cashier comparison. Empty unless the period
  /// is a single day.
  final List<TenantShiftDaySlice> shifts;
  final String? failureMessage;

  TenantReportingCurrency get _currency => sessionContext.currency;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return ListView(
      key: const ValueKey('sales-totals'),
      padding: EdgeInsets.all(tokens.spacing.s20),
      children: [
        // The screen's title is the `PageHeader`'s and is not drawn twice; see
        // the same note on the daily summary. §7's order from here: optional
        // `Callout`, filters, content.
        if (!_currency.isKnown) ...[
          const Callout(
            key: ValueKey('sales-totals-currency-unknown'),
            status: AppStatus.info,
            message: TenantReportingCurrency.unknownNotice,
          ),
          SizedBox(height: tokens.spacing.s12),
        ],
        SalesTotalsChoosers(
          period: period,
          soldById: soldById,
          selfUid: selfUid,
          categoryId: categoryId,
          sessionContext: sessionContext,
          onChoosePeriod: onChoosePeriod,
          onChooseMember: onChooseMember,
          onChooseCategory: onChooseCategory,
        ),
        SizedBox(height: tokens.spacing.s20),
        if (totals case final answer?) ...[
          AppWorkspace(
            leadingFlex: 1,
            trailingFlex: 1,
            leading: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // **Takings.** The figure this screen is opened for, and the
                // standing of that figure in the same block - which is why the range
                // and the basis sit on this card rather than above the page.
                _TotalsCard(
                  cardKey: const ValueKey('sales-totals-takings'),
                  title: _range(answer.query),
                  titleKey: const ValueKey('sales-totals-range'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // **Scaled down, never ellipsised.** A truncated amount is a
                      // wrong amount - the rule `StatTile` already enforces for the
                      // tiles below, restated here because the headline is no longer
                      // one of them. `KES 1,234,567.00` at `numericHero` is wider
                      // than a 390 phone.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _currency.format(answer.netOrGrossSales),
                          key: const ValueKey('sales-totals-amount'),
                          maxLines: 1,
                          style: tokens.typography.numericHero.copyWith(
                            color: tokens.colors.text.primary,
                          ),
                        ),
                      ),
                      SizedBox(height: tokens.spacing.s4),
                      Text(
                        _salesDetail(answer),
                        style: tokens.typography.bodyMedium.copyWith(
                          color: tokens.colors.text.tertiary,
                        ),
                      ),
                      // **The one fact the removed fold was carrying.** It said what
                      // these figures are counted from, and for a device answer that
                      // is not a footnote - it is the difference between the whole
                      // business and this till. A badge states it where the figure
                      // is, which is the shape the artboards used.
                      //
                      // **Once the server has failed, not while it is being asked.**
                      // The device read runs beside the server's and nearly always
                      // lands first, so this badge went up on every open and came
                      // down a moment later - the weekly report's mistake, fixed
                      // there the same way (`serverCouldNotBeReached`).
                      if (answer.basis == TenantSalesTotalsBasis.device &&
                          (TenantReadFreshness.maybeOf(context)?.stale ??
                              true)) ...[
                        SizedBox(height: tokens.spacing.s8),
                        StatusBadge(
                          key: const ValueKey('sales-totals-device-basis'),
                          status: AppStatus.attention,
                          icon: Icons.phone_android_outlined,
                          label: 'Counted on this device',
                        ),
                      ],
                      SizedBox(height: tokens.spacing.s12),
                      StatRow(
                        tiles: [
                          // **`Transactions`, which is the daily summary's word for
                          // the same count.** The two money surfaces use one
                          // vocabulary; that was settled before this layout and is
                          // unchanged by it.
                          StatTile(
                            label: 'Transactions',
                            value: '${answer.netOrGrossTransactions}',
                            icon: Icons.receipt_long_outlined,
                            detail: 'counted in this total',
                            valueKey: const ValueKey(
                              'sales-totals-transactions',
                            ),
                          ),
                          if (_averageSale(answer) case final average?)
                            StatTile(
                              label: 'Average sale',
                              money: true,
                              value: _currency.format(average),
                              icon: Icons.payments_outlined,
                              valueKey: const ValueKey('sales-totals-average'),
                            ),
                        ],
                      ),
                      // **Said out loud, because the headline figure changed
                      // meaning.** Takings net of returns and takings gross of them
                      // are different numbers, and a reader comparing this against a
                      // till roll needs to know which one this is.
                      if (answer.net case final net?
                          when net.returnsScanned > 0)
                        Padding(
                          padding: EdgeInsets.only(top: tokens.spacing.s12),
                          child: Text(
                            key: const ValueKey('sales-totals-returns'),
                            '${net.returnsScanned} '
                            '${net.returnsScanned == 1 ? 'return has' : 'returns have'} '
                            'been taken back out of these figures.',
                            style: tokens.typography.bodyMedium.copyWith(
                              color: tokens.colors.text.tertiary,
                            ),
                          ),
                        ),
                      // A category total is a different figure, not a smaller one of
                      // the same kind: the server sums the matching lines and leaves
                      // the rest of each sale out. Showing it under the same label as
                      // a whole-business total would be lying by omission - which is
                      // a notice about *this* read, so it is a `Callout` and does not
                      // fold.
                      if (answer.query.isCategoryFiltered) ...[
                        SizedBox(height: tokens.spacing.s12),
                        Callout(
                          key: const ValueKey('sales-totals-category-basis'),
                          status: AppStatus.info,
                          message:
                              'This adds up only the lines in this category, not '
                              'the whole of each sale. '
                              '${answer.scannedTransactions - answer.transactions} '
                              'of the ${answer.scannedTransactions} '
                              '${answer.scannedTransactions == 1 ? 'sale' : 'sales'} '
                              'read held nothing in it.',
                        ),
                      ],
                    ],
                  ),
                ),
                // **How it was paid**, on its own card because it answers its own
                // question. The bars take the *categorical* palette rather than one
                // bar colour repeated: these are three ways of paying, not three
                // positions on an axis, and a single colour left the eye nothing to
                // tell them apart by. The figures are still printed beside every
                // label, which is what §2.2 requires and what hard rule 4 requires.
              ],
            ),
            trailing: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (answer.net?.tenderBreakdown ?? answer.tenderBreakdown
                    case final breakdown?) ...[
                  SizedBox(height: tokens.spacing.s12),
                  _TotalsCard(
                    cardKey: const ValueKey('sales-totals-tender'),
                    title: 'How it was paid',
                    child: _TenderBreakdown(
                      breakdown: breakdown,
                      currency: _currency,
                    ),
                  ),
                ],
                // **The per-cashier comparison, and only for a single day.** Empty
                // for every longer period by construction - see
                // `SalesTotalsView.shifts` - so this card is absent rather than
                // showing a comparison that would put one cashier in several columns.
                if (shifts.isNotEmpty) ...[
                  SizedBox(height: tokens.spacing.s12),
                  _TotalsCard(
                    cardKey: const ValueKey('sales-totals-shifts'),
                    title: 'Across the day',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShiftComparisonChart(
                          shifts: comparedShifts(shifts),
                          currency: _currency,
                          nameFor: (shift) => tenantStaffLabel(
                            shift.staffId,
                            names: sessionContext.staff.names,
                            selfUid: selfUid,
                          ),
                        ),
                        if (shifts.length > maximumComparedShifts) ...[
                          SizedBox(height: tokens.spacing.s12),
                          Text(
                            key: const ValueKey('sales-totals-shifts-capped'),
                            '${shifts.length - maximumComparedShifts} more '
                            '${shifts.length - maximumComparedShifts == 1 ? 'shift is' : 'shifts are'} '
                            'not on the chart. Shift history lists every one.',
                            style: tokens.typography.bodyMedium.copyWith(
                              color: tokens.colors.text.tertiary,
                            ),
                          ),
                        ],
                        if (shifts.any((shift) => shift.isOpen)) ...[
                          SizedBox(height: tokens.spacing.s12),
                          Text(
                            key: const ValueKey('sales-totals-shifts-open'),
                            // Not "in the chart": below two comparable shifts
                            // there is no chart, and the sentence has to be true of
                            // both presentations. What it is really saying is that
                            // the close writes the figure.
                            'A shift is still running. Its takings are written when '
                            'it is closed, so they are not shown here yet.',
                            style: tokens.typography.bodyMedium.copyWith(
                              color: tokens.colors.text.tertiary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                // **Profit, as a figure with its basis on it.** What this replaced
                // was `TenantProfitStatement`'s five stacked rows - the block every
                // other reporting surface uses and the one the product owner called
                // overloaded here. The *wording* is unchanged and still comes from
                // `tenantProfitCeilingNote` and `tenantProfitNote`, which is what
                // keeps one rule: a second wording would be a second rule. Only the
                // arrangement is this screen's.
                if (showProfit && answer.netOrGrossProfitReport.isDrawable) ...[
                  SizedBox(height: tokens.spacing.s12),
                  _TotalsCard(
                    cardKey: const ValueKey('sales-totals-profit-card'),
                    title: net == null ? 'Profit' : 'Gross profit',
                    child: _ProfitFigure(
                      report: answer.netOrGrossProfitReport,
                      currency: _currency,
                      figureKey: const ValueKey('sales-totals-profit'),
                      marginKey: const ValueKey('sales-totals-margin'),
                      marginLabel: net == null ? 'Margin' : 'Gross margin',
                    ),
                  ),
                ],
                // **Net profit on its own card, because it is its own question.**
                // Gross profit answers *what did the goods make*; this answers *what
                // was left*, and they were two lines of one block.
                if (net case final spending?
                    when showProfit && spending.isDrawable) ...[
                  SizedBox(height: tokens.spacing.s12),
                  _TotalsCard(
                    cardKey: const ValueKey('sales-totals-net-card'),
                    title: 'Net profit',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currency.format(spending.netProfit),
                          key: const ValueKey('sales-totals-net-profit'),
                          style: tokens.typography.numericHero.copyWith(
                            fontSize: 26,
                            color: tokens.colors.text.primary,
                          ),
                        ),
                        if (!spending.isShowable) ...[
                          SizedBox(height: tokens.spacing.s8),
                          StatusBadge(
                            status: AppStatus.attention,
                            icon: Icons.pending_outlined,
                            label:
                                spending.basis ==
                                    TenantNetProfitBasis.expensesUnread
                                ? 'At most: some spending is not counted'
                                : tenantProfitCeilingNote(spending.gross),
                          ),
                        ],
                        SizedBox(height: tokens.spacing.s12),
                        StatRow(
                          tiles: [
                            StatTile(
                              label: 'Expenses',
                              money: true,
                              value: _currency.format(spending.expenses),
                              icon: Icons.account_balance_wallet_outlined,
                              detail: 'Rent, wages and the rest',
                              valueKey: const ValueKey('sales-totals-expenses'),
                            ),
                            if (spending.netMarginPercent case final margin?)
                              StatTile(
                                label: 'Net margin',
                                value: '${margin.toStringAsFixed(1)}%',
                                icon: Icons.percent_outlined,
                                valueKey: const ValueKey(
                                  'sales-totals-net-margin',
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                // **The rule this whole block exists to satisfy**, on its own line
                // under the figures it qualifies: no profit figure is ever shown
                // without, nearby, what is known about the cost data behind it.
                if (showProfit) ...[
                  SizedBox(height: tokens.spacing.s12),
                  Text(
                    key: const ValueKey('sales-totals-profit-note'),
                    tenantProfitNote(answer.netOrGrossProfitReport),
                    style: tokens.typography.bodyMedium.copyWith(
                      color: tokens.colors.text.tertiary,
                    ),
                  ),
                ] else if (!answer.hasCompleteCostData) ...[
                  SizedBox(height: tokens.spacing.s12),
                  Text(
                    key: const ValueKey('sales-totals-cost'),
                    '${answer.incompleteCostLineCount} sale '
                    '${answer.incompleteCostLineCount == 1 ? 'line has' : 'lines have'} '
                    'no cost recorded.',
                    style: tokens.typography.bodyMedium.copyWith(
                      color: tokens.colors.text.tertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (failureMessage case final message?) ...[
          Callout(
            key: const ValueKey('sales-totals-failure'),
            status: AppStatus.problem,
            message: message,
            action: AppButton(
              key: const ValueKey('sales-totals-retry'),
              label: 'Try again',
              onPressed: onRetry,
            ),
          ),
        ],
      ],
    );
  }

  /// What the headline figure is over, in the words the sentence used to carry.
  ///
  /// The count itself is the second tile; this line is what it is a count *of*,
  /// which is the fact "over 37 sales" was really stating.
  /// The average sale, or null where either side of the division is unknown.
  ///
  /// Not drawn for a category filter: the divisor there is the number of sales
  /// that held something in the category, and dividing the category's takings
  /// by it is an average of two different things.
  double? _averageSale(TenantSalesTotals answer) {
    if (answer.query.isCategoryFiltered) return null;
    final count = answer.netOrGrossTransactions;
    if (count <= 0) return null;
    return answer.netOrGrossSales / count;
  }

  String _salesDetail(TenantSalesTotals answer) =>
      answer.query.isCategoryFiltered
      ? 'the lines in this category'
      : 'taken over this period';

  /// Names the exact days, whose sales were counted, and which category, so a
  /// figure is never shown without the question it answers.
  String _range(TenantSalesTotalsQuery query) {
    final parts = <String?>[
      query.startDate == query.endDate
          ? query.endDate
          : '${query.startDate} to ${query.endDate}',
      switch (query.scope) {
        TenantSalesScope.everyone => null,
        TenantSalesScope.mine => 'your sales only',
        // Named from the same canonical directory the filter was chosen from,
        // degrading to the authoritative UID exactly as every other surface
        // that labels a colleague does.
        TenantSalesScope.oneMember => tenantStaffLabel(
          query.soldById!,
          names: sessionContext.staff.names,
          selfUid: selfUid,
        ),
      },
      // The name comes from the same canonical list the filter was chosen from;
      // an ID with no name is not shown as a label of its own.
      if (query.categoryId case final id?)
        sessionContext.categories.nameOf(id) ?? 'one category',
    ].nonNulls;
    return parts.join(' • ');
  }
}

/// How the takings above split across the ways they were paid for.
///
/// Only buckets that hold something are listed. A period with no card sales is
/// better described by their absence than by a row of zeroes, and the figures
/// above already say what the whole is.
final class _TenderBreakdown extends StatelessWidget {
  const _TenderBreakdown({required this.breakdown, required this.currency});

  final TenantSalesTenderBreakdown breakdown;
  final TenantReportingCurrency currency;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    // Every row this breakdown will draw, in one list, so each can be given
    // its own palette entry and measured against the largest of them.
    final rows = <({String label, TenantSalesTenderTotals totals, Key key})>[
      for (final entry in breakdown.recorded.entries)
        if (!entry.value.isEmpty)
          (
            label: entry.key.label,
            totals: entry.value,
            key: ValueKey('sales-totals-tender-${entry.key.wireValue}'),
          ),
      if (!breakdown.unrecorded.isEmpty)
        (
          label: 'Not recorded',
          totals: breakdown.unrecorded,
          key: const ValueKey('sales-totals-tender-unrecorded'),
        ),
      if (!breakdown.unrecognised.isEmpty)
        (
          label: 'Unrecognised',
          totals: breakdown.unrecognised,
          key: const ValueKey('sales-totals-tender-other'),
        ),
    ]..sort((a, b) => b.totals.sales.compareTo(a.totals.sales));
    final largest = rows.isEmpty
        ? 0.0
        : rows.map((row) => row.totals.sales).reduce((a, b) => a > b ? a : b);
    final palette = tokens.colors.chart.series;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // **Five sentences became five figures in a column**, which is what §2.2
        // makes mandatory "anywhere numbers stack vertically" and what
        // `Cash: KES 2000.25 over 20 sales` could not do. The bar beside each
        // figure is what the column of digits could not do either: say which
        // is largest without being read one row at a time.
        for (final (index, row) in rows.indexed)
          _TenderRow(
            label: row.label,
            totals: row.totals,
            share: largest == 0 ? 0 : row.totals.sales / largest,
            colour: palette[index % palette.length],
            currency: currency,
            valueKey: row.key,
          ),
        // **A notice rather than a fold, and that is a decision.** Every other
        // permanent explanation on this screen went behind a `Disclosure`; this
        // one may not, because `checkout_tender.dart` requires that every
        // surface showing a tender says the payment is unverified, and a
        // sentence behind a chevron is one a person can finish reading the
        // screen without. §2.1's `info` is "informational" in its own words.
        if (breakdown.hasRecordedTenders) ...[
          SizedBox(height: tokens.spacing.s8),
          const Callout(
            key: ValueKey('sales-totals-tender-disclaimer'),
            status: AppStatus.info,
            message: checkoutTenderDisclaimer,
          ),
        ],
      ],
    );
  }
}

/// One section of this screen, on its own card.
///
/// **What this replaced was a single card holding everything.** The range, the
/// two tiles, the returns note, the category notice, the whole profit statement
/// and the payment split were one column inside one border - which is how a
/// screen that answers five questions comes to read as one wall. A card per
/// question is the shape the day artboards used, and the product owner asked
/// for it here.
final class _TotalsCard extends StatelessWidget {
  const _TotalsCard({
    required this.child,
    this.title,
    this.titleKey,
    this.cardKey,
  });

  final Widget child;

  /// Null where the child writes its own heading.
  final String? title;

  /// A handle on the heading, for a title that states a fact rather than
  /// naming a section - the takings card's heading is the period.
  final Key? titleKey;
  final Key? cardKey;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return AppCard(
      key: cardKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (title case final heading?) ...<Widget>[
            Text(heading, key: titleKey, style: tokens.typography.labelMedium),
            SizedBox(height: tokens.spacing.s8),
          ],
          child,
        ],
      ),
    );
  }
}

/// A profit figure with what is known about its cost data attached.
///
/// **The badge is the rule, not decoration.** `profit_statement.dart` holds
/// that no profit figure is ever rendered without, in the same block, what is
/// known about the cost behind it - and takes its words from
/// `tenantProfitCeilingNote`, which this reads too so the two cannot drift.
final class _ProfitFigure extends StatelessWidget {
  const _ProfitFigure({
    required this.report,
    required this.currency,
    required this.figureKey,
    required this.marginKey,
    required this.marginLabel,
  });

  final TenantProfitReport report;
  final TenantReportingCurrency currency;
  final Key figureKey;
  final Key marginKey;
  final String marginLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final margin = report.marginPercent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          currency.format(report.profit),
          key: figureKey,
          style: tokens.typography.numericHero.copyWith(
            fontSize: 26,
            color: tokens.colors.text.primary,
          ),
        ),
        if (!report.isShowable) ...<Widget>[
          SizedBox(height: tokens.spacing.s8),
          StatusBadge(
            status: AppStatus.attention,
            icon: Icons.pending_outlined,
            label: tenantProfitCeilingNote(report),
          ),
        ],
        if (margin != null) ...<Widget>[
          SizedBox(height: tokens.spacing.s12),
          StatRow(
            tiles: <StatTile>[
              StatTile(
                label: marginLabel,
                value: '${margin.toStringAsFixed(1)}%',
                icon: Icons.percent_outlined,
                valueKey: marginKey,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// One payment method's share of the period.
///
/// **A bar was added beside the figure, and the figure did not move.** §2.2
/// makes tabular figures mandatory anywhere numbers stack vertically, and the
/// column of amounts on the right is still that column. What the bar adds is
/// the comparison the column could not make: five amounts in a row of digits
/// tell you which is largest only by being read, one at a time.
///
/// **Each row takes its own colour from the *categorical* palette.** These are
/// ways of paying, not positions on an axis, which is exactly what
/// `AppChartRoles.series` is kept for - ordered for separation rather than by
/// shade. One colour repeated made the rows read as a single series.
///
/// **The colour is never the only thing identifying a row**, hard rule 4: the
/// method's name is on its left and its amount on its right, and both are there
/// whether or not the bar renders.
final class _TenderRow extends StatelessWidget {
  const _TenderRow({
    required this.label,
    required this.totals,
    required this.share,
    required this.colour,
    required this.currency,
    required this.valueKey,
  });

  final String label;
  final TenantSalesTenderTotals totals;

  /// This row's amount against the largest row's, for the bar's length.
  final double share;
  final Color colour;
  final TenantReportingCurrency currency;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final sales =
        '${totals.transactions} '
        '${totals.transactions == 1 ? 'sale' : 'sales'}';
    return Semantics(
      container: true,
      label: '$label, ${currency.format(totals.sales)}, over $sales',
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.only(bottom: tokens.spacing.s12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 92,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.typography.bodyMedium,
                  ),
                  Text(
                    sales,
                    maxLines: 1,
                    style: tokens.typography.caption.copyWith(
                      color: tokens.colors.text.tertiary,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: tokens.spacing.s8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(tokens.radius.sm),
                child: LinearProgressIndicator(
                  value: share.clamp(0, 1),
                  minHeight: tokens.spacing.s8,
                  backgroundColor: tokens.colors.chart.gridLine,
                  valueColor: AlwaysStoppedAnimation<Color>(colour),
                ),
              ),
            ),
            SizedBox(width: tokens.spacing.s8),
            Text(
              currency.format(totals.sales),
              key: valueKey,
              style: tokens.typography.numericBody,
            ),
          ],
        ),
      ),
    );
  }
}
