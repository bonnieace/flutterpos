import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../ui/scaffold.dart';
import '../ui/stats.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import '../checkout/checkout_tender.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session_controller.dart';
import '../tenancy/tenant_staff_names.dart';
import 'profit_report.dart';
import 'profit_statement.dart';
import 'reporting_currency.dart';
import 'sales_totals.dart';
import 'sales_totals_choosers.dart';
import 'sales_totals_session_context.dart';

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
    this.clock,
  });

  final SalesTotalsCallable callable;

  /// Reads the canonical categories the breakdown can filter by. Nothing else
  /// on this route touches Firestore; the figures come from the callable.
  final TenantDataReader reader;

  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Sales totals',
    contentWidth: AppContentWidth.records,
    body: TenantSalesTotalsPanel(
      callable: callable,
      reader: reader,
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
    this.clock,
    this.period = TenantSalesPeriod.today,
    this.categoryPageSize = 50,
    this.staffPageSize = 25,
  });

  final SalesTotalsCallable callable;
  final TenantDataReader reader;
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

  /// The category list, staff list, and currency for one session, so none of
  /// them can label - or filter - another business's figures. All three are
  /// cached because the filters change often and none of them depends on the
  /// period, the member, or the category.
  late final SalesTotalsSessionContextLoader _sessionContext =
      SalesTotalsSessionContextLoader(
        reader: widget.reader,
        categoryPageSize: widget.categoryPageSize,
        staffPageSize: widget.staffPageSize,
      );

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
  TenantGuardedLoader<SalesTotalsView> _loaderFor(String key) {
    if (key == _loaderKey && _loader != null) return _loader!;
    _loaderKey = key;
    final period = _period;
    final chosenMember = _soldById;
    final chosenCategory = _categoryId;
    return _loader = (session) async {
      final context = await _sessionContext.load(session);
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
      return SalesTotalsView(
        totals: await gateway.load(
          gateway.createQuery(
            period: period,
            soldById: soldById,
            categoryId: categoryId,
          ),
        ),
        context: context,
      );
    };
  }

  @override
  Widget build(BuildContext context) {
    final guardKey =
        '${_period.name}:${_soldById ?? '-'}:${_categoryId ?? '-'}:'
        '$_generation';
    return TenantRouteGuard<SalesTotalsView>(
      key: ValueKey(guardKey),
      allowedRoles: TenantSalesTotalsGateway.allowedRoles,
      load: _loaderFor(guardKey),
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
            _sessionContext.cached ?? SalesTotalsSessionContext.empty,
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
    this.failureMessage,
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
  final String? failureMessage;

  TenantReportingCurrency get _currency => sessionContext.currency;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return ListView(
      key: const ValueKey('sales-totals'),
      padding: const EdgeInsets.all(20),
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
        // Permanent, and true of every answer this route will ever give: what
        // these figures are counted from, and which other screen's figures they
        // are not.
        const Disclosure(
          key: ValueKey('sales-totals-basis-disclosure'),
          summary: 'What these totals include',
          child: Text(
            key: ValueKey('sales-totals-basis'),
            'The server adds these up from the sales it holds right now, so a '
            'sale still waiting on a device is not in them. They are not the '
            'reconciled figures the daily summary reports.',
          ),
        ),
        SizedBox(height: tokens.spacing.s16),
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
          Card(
            child: Padding(
              padding: EdgeInsets.all(tokens.spacing.s16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    key: const ValueKey('sales-totals-range'),
                    _range(answer.query),
                    style: tokens.typography.titleMedium.copyWith(
                      color: tokens.colors.text.primary,
                    ),
                  ),
                  SizedBox(height: tokens.spacing.s12),
                  // **The one figure a stat tile exists for**, §2.2's own words
                  // for `numeric.hero`, and the reason this screen rather than
                  // the daily summary gets tiles: it answers one question with
                  // one pair of figures, where a summary lists seven days and is
                  // money in flow.
                  StatRow(
                    tiles: [
                      StatTile(
                        label: 'Sales',
                        value: _currency.format(answer.sales),
                        icon: Icons.payments_outlined,
                        detail: _salesDetail(answer),
                        valueKey: const ValueKey('sales-totals-amount'),
                      ),
                      // **`Transactions`, which is the daily summary's word for
                      // the same count.** The sentence this replaces said
                      // "over 37 sales", and two adjacent tiles both captioned
                      // `Sales` - one money, one a count - is the first picture
                      // of this screen finding a copy defect the sentence had
                      // hidden. The two money surfaces now use one vocabulary,
                      // which is the lesson three chunks in a row have paid for.
                      StatTile(
                        label: 'Transactions',
                        value: '${answer.transactions}',
                        icon: Icons.receipt_long_outlined,
                        detail: 'counted in this total',
                        valueKey: const ValueKey('sales-totals-transactions'),
                      ),
                    ],
                  ),
                  // A category total is a different figure, not a smaller one of
                  // the same kind: the server sums the matching lines and leaves
                  // the rest of each sale out. Showing it under the same label
                  // as a whole-business total would be lying by omission - which
                  // is a notice about *this* read, so it is a `Callout` and does
                  // not fold.
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
                  // The whole statement about profit, or - for a session that may
                  // not be shown one - the cost-data fact on its own. Never both:
                  // the statement carries the same count inside it, and saying it
                  // twice reads as two different findings. The sentence is now
                  // word for word the daily summary's, because it is the same
                  // fact about the same sale lines over a different stretch.
                  if (showProfit) ...[
                    SizedBox(height: tokens.spacing.s8),
                    TenantProfitStatement(
                      report: answer.profitReport,
                      currency: _currency,
                      keyPrefix: 'sales-totals',
                    ),
                  ] else if (!answer.hasCompleteCostData) ...[
                    SizedBox(height: tokens.spacing.s8),
                    Text(
                      key: const ValueKey('sales-totals-cost'),
                      '${answer.incompleteCostLineCount} sale '
                      '${answer.incompleteCostLineCount == 1 ? 'line has' : 'lines have'} '
                      'no cost recorded.',
                      style: tokens.typography.caption.copyWith(
                        color: tokens.colors.text.tertiary,
                      ),
                    ),
                  ],
                  if (answer.tenderBreakdown case final breakdown?) ...[
                    SizedBox(height: tokens.spacing.s12),
                    _TenderBreakdown(breakdown: breakdown, currency: _currency),
                  ],
                ],
              ),
            ),
          ),
          SizedBox(height: tokens.spacing.s12),
          AppButton(
            key: const ValueKey('sales-totals-refresh'),
            label: 'Read again',
            onPressed: onRetry,
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
    return Column(
      key: const ValueKey('sales-totals-tender'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Paid by',
          style: tokens.typography.titleMedium.copyWith(
            color: tokens.colors.text.primary,
          ),
        ),
        SizedBox(height: tokens.spacing.s4),
        // **Five sentences became five figures in a column**, which is what §2.2
        // makes mandatory "anywhere numbers stack vertically" and what
        // `Cash: KES 2000.25 over 20 sales` could not do: the amounts started at
        // a different column on every row, so nothing could be compared by eye.
        // The count each amount is over is the line under its own label.
        for (final entry in breakdown.recorded.entries)
          if (!entry.value.isEmpty)
            _line(
              entry.key.label,
              entry.value,
              ValueKey('sales-totals-tender-${entry.key.wireValue}'),
            ),
        if (!breakdown.unrecorded.isEmpty)
          _line(
            'Not recorded',
            breakdown.unrecorded,
            const ValueKey('sales-totals-tender-unrecorded'),
          ),
        if (!breakdown.unrecognised.isEmpty)
          _line(
            'Unrecognised',
            breakdown.unrecognised,
            const ValueKey('sales-totals-tender-other'),
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
        // These two are helper paragraphs rather than notices: each explains
        // what a row above it means and is true of that row every time it
        // appears, which is §5.1's `Disclosure` and the rule the reconciliation
        // sweep set. Deliberately a different sentence from the one a single
        // sale carries: `checkoutTenderUnrecordedMessage` says "This sale",
        // which is a claim about one record and would be wrong over a period.
        if (!breakdown.unrecorded.isEmpty) ...[
          SizedBox(height: tokens.spacing.s8),
          const Disclosure(
            key: ValueKey('sales-totals-tender-unrecorded-disclosure'),
            summary: 'Why a sale names no method',
            child: Text(
              key: ValueKey('sales-totals-tender-unrecorded-note'),
              'Sales recorded before payment methods were captured name none, '
              'so they are listed separately rather than as unpaid.',
            ),
          ),
        ],
        if (!breakdown.unrecognised.isEmpty) ...[
          SizedBox(height: tokens.spacing.s8),
          const Disclosure(
            key: ValueKey('sales-totals-tender-other-disclosure'),
            summary: 'An unrecognised method',
            child: Text(
              key: ValueKey('sales-totals-tender-other-note'),
              'Some sales name a payment method this app does not recognise. '
              'Their takings are still inside the total above.',
            ),
          ),
        ],
      ],
    );
  }

  Widget _line(String label, TenantSalesTenderTotals totals, Key valueKey) =>
      StatLine(
        label: label,
        detail:
            '${totals.transactions} '
            '${totals.transactions == 1 ? 'sale' : 'sales'}',
        value: currency.format(totals.sales),
        valueKey: valueKey,
      );
}
