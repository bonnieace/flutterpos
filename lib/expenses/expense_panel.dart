/// The Expenses route: what the business spent, and recording more of it.
///
/// **The two ideas carried across from the project this came from** are the
/// per-category share bars and a detail view per category. Both read without a
/// charting library, which is why they survived: a ring chart of eight slices
/// is a legend a person has to decode, while a labelled bar with its own figure
/// beside it is read in one pass. Everything else there - free-text categories,
/// a collection scan per keystroke, a client clock - is rebuilt here against
/// this app's own contracts.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../checkout/checkout_draft.dart';
import '../reporting/reporting_currency.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../ui/buttons.dart';
import '../ui/chips.dart';
import '../ui/fields.dart';
import '../ui/press.dart';
import '../tenancy/tenant_session_controller.dart';
import '../ui/routes.dart';
import '../ui/scaffold.dart';
import '../ui/sheet.dart';
import '../ui/skeleton.dart';
import '../ui/snackbar.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'expense.dart';
import 'expense_category_panel.dart';
import 'expense_charts.dart';
import 'expense_repository.dart';
import 'expense_request.dart';

/// The stretch of trading days this route totals.
///
/// **A chip strip rather than a dropdown**, which is this app's own rule: a
/// surface carrying one filter shows its options without a tap, and only a
/// surface carrying several folds them into `AppSelect`.
enum TenantExpenseRange {
  today(1, 'Today'),
  last7Days(7, 'Last 7 days'),
  last30Days(30, 'Last 30 days');

  const TenantExpenseRange(this.days, this.label);

  /// How many business dates the range covers, including today.
  final int days;

  final String label;
}

/// The Expenses route.
final class TenantExpensesScreen extends StatelessWidget {
  const TenantExpensesScreen({
    super.key,
    required this.reader,
    this.writer,
    this.clock,
  });

  final TenantDataReader reader;

  /// The write boundary, or null on a build with no recording wired up - in
  /// which case this route reads and never offers a form it cannot submit.
  final TenantExpenseWriter? writer;

  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) =>
      TenantExpensesPanel(reader: reader, writer: writer, clock: clock);
}

/// Reads and records expenses behind [TenantRouteGuard].
final class TenantExpensesPanel extends StatefulWidget {
  const TenantExpensesPanel({
    super.key,
    required this.reader,
    this.writer,
    this.clock,
  });

  final TenantDataReader reader;
  final TenantExpenseWriter? writer;
  final DateTime Function()? clock;

  @override
  State<TenantExpensesPanel> createState() => _TenantExpensesPanelState();
}

class _TenantExpensesPanelState extends State<TenantExpensesPanel> {
  TenantExpenseRange _range = TenantExpenseRange.last30Days;
  int _generation = 0;

  String? _loaderKey;
  TenantGuardedLoader<_ExpensesView>? _loader;

  DateTime get _now => (widget.clock ?? _utcNow)().toUtc();

  /// Re-reads the period, after a record or a void changed what is in it.
  void _reload() => setState(() => _generation++);

  /// One loader per guard key. A closure rebuilt every frame would re-read on
  /// every keystroke of the form above it.
  TenantGuardedLoader<_ExpensesView> _loaderFor(String key) {
    if (key == _loaderKey && _loader != null) return _loader!;
    _loaderKey = key;
    final endDate = checkoutBusinessDate(_now);
    final startDate = checkoutBusinessDate(
      _now.subtract(Duration(days: _range.days - 1)),
    );
    return _loader = (session) async {
      // **Both are Firestore reads and both serve from the cache**, so they are
      // started together and neither waits on the other's round trip. There is
      // no callable anywhere on this page, which is why it works with no signal
      // at all - and why net profit is composed on the client from this rather
      // than asked of a server.
      final period = TenantExpenseRepository(
        session: session,
        reader: widget.reader,
      ).readRange(startDate: startDate, endDate: endDate);
      final currency = TenantReportingCurrency.read(
        session: session,
        reader: widget.reader,
      );
      return (period: await period, currency: await currency);
    };
  }

  /// Withdraws one record that should not have been there.
  ///
  /// **A void rather than a delete, and it asks why.** The record stays on the
  /// list struck through, the reason travels with it, and both are refused any
  /// further change - so a correction is a thing that happened rather than a
  /// gap where something used to be. The Firestore rule enforces every part of
  /// that; this is the surface for it.
  Future<void> _void(
    TenantSession session,
    TenantExpense record,
    TenantReportingCurrency currency,
  ) async {
    final writer = widget.writer;
    if (writer == null) return;
    final answer = await showExpenseVoidSheet(
      context,
      writer: writer,
      session: session,
      record: record,
      currency: currency,
    );
    if (!mounted || answer == null) return;
    showAppSnackBar(context, answer);
    if (answer.status == AppStatus.ok) _reload();
  }

  /// Opens one category on its own, carrying the period already read.
  void _openCategory(
    TenantExpenseCategory category,
    TenantExpensePeriod period,
    TenantReportingCurrency currency,
  ) {
    final controller = TenantSessionScope.of(context);
    Navigator.of(context).push(
      AppPageRoute<void>(
        // The same scope the route behind it runs under, so a business switch
        // invalidates this detail exactly as it invalidates the list.
        builder: (_) => TenantSessionScope(
          controller: controller,
          child: TenantExpenseCategoryScreen(
            category: category,
            period: period,
            currency: currency,
            periodLabel: _range.label.toLowerCase(),
          ),
        ),
      ),
    );
  }

  Future<void> _record(TenantSession session) async {
    final writer = widget.writer;
    if (writer == null) return;
    final answer = await showExpenseRecordSheet(
      context,
      writer: writer,
      session: session,
      businessDate: checkoutBusinessDate(_now),
    );
    if (!mounted || answer == null) return;
    showAppSnackBar(context, answer);
    if (answer.status == AppStatus.ok) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final guardKey = '${_range.name}:$_generation';
    final chips = Padding(
      padding: EdgeInsets.only(bottom: tokens.spacing.s20),
      child: FilterChipBar<TenantExpenseRange>(
        key: const ValueKey('expenses-range'),
        semanticLabel: 'The stretch of days these expenses cover.',
        options: <FilterChipOption<TenantExpenseRange>>[
          for (final range in TenantExpenseRange.values)
            FilterChipOption<TenantExpenseRange>(
              key: ValueKey('expenses-range-${range.name}'),
              value: range,
              label: range.label,
            ),
        ],
        selected: _range,
        // There is no "no period" reading of this page, so a deselection is
        // refused rather than silently mapped onto a default - the same call
        // the sales totals period chooser makes.
        onSelected: (range) {
          if (range == null || range == _range) return;
          setState(() => _range = range);
        },
      ),
    );
    return TenantRouteGuard<_ExpensesView>(
      key: ValueKey(guardKey),
      allowedRoles: TenantExpenseRepository.allowedRoles,
      load: _loaderFor(guardKey),
      // **The chooser stays on screen through every phase**, the way the sales
      // totals page keeps its own: the control that would take a person to a
      // different period must not be behind the read of this one.
      loading: _ExpensesFrame(chips: chips, child: const _ExpensesReading()),
      denied: _ExpensesFrame(
        chips: chips,
        child: const EmptyState(
          key: ValueKey('expenses-denied'),
          title: 'Expenses are not shown for this role',
          hint: 'An owner or an administrator can record and review them.',
        ),
      ),
      failure: (context, error) => _ExpensesFrame(
        chips: chips,
        child: const ErrorState(
          key: ValueKey('expenses-failure'),
          badgeLabel: 'Not read',
          statement: 'What this business spent could not be read.',
          stillTrue: 'Nothing has been recorded or changed.',
        ),
      ),
      builder: (context, session, view) => _ExpensesFrame(
        chips: chips,
        action: widget.writer == null
            ? null
            : AppIconButton(
                key: const ValueKey('expenses-record'),
                icon: Icons.add,
                semanticLabel: 'Record expense',
                // **Tertiary, not primary.** The primary tier's label is the
                // near-black ink that sits on a mint container, and an
                // unbordered icon button paints no container - so a primary `+`
                // is black on the bar's own dark surface, which is the contrast
                // failure hard rule 4 is pass/fail about. Tertiary is the mint
                // glyph on nothing, which is what this control is.
                tier: AppButtonTier.tertiary,
                bordered: false,
                onPressed: () => _record(session),
              ),
        child: _ExpensesContents(
          period: view.period,
          currency: view.currency,
          range: _range,
          canRecord: widget.writer != null,
          onVoid: widget.writer == null
              ? null
              : (record) => _void(session, record, view.currency),
          onOpenCategory: (category) =>
              _openCategory(category, view.period, view.currency),
        ),
      ),
    );
  }
}

/// The period, and the code its figures are labelled with.
typedef _ExpensesView = ({
  TenantExpensePeriod period,
  TenantReportingCurrency currency,
});

/// The page, in whatever phase the guard has it.
///
/// **The scaffold is built here rather than by the route, and that is the
/// point of the class.** The one control this page exists for - recording an
/// expense - belongs at the trailing edge of the top bar, and it may only be
/// offered to somebody the guard has already admitted. A route drawing that
/// button outside the guard would hold it out to the manager the guard is
/// about to refuse.
///
/// **A `ListView` rather than a `Column`, and that is not cosmetic.** A month
/// of a real business is hundreds of records, and the page owning the scroll is
/// what stops the list running off the bottom.
final class _ExpensesFrame extends StatelessWidget {
  const _ExpensesFrame({required this.chips, required this.child, this.action});

  final Widget chips;
  final Widget child;

  /// The top bar's own control, or null in a phase that has nothing to offer.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return AppScaffold(
      title: 'Expenses',
      subtitle: 'What the business spent, beyond the cost of its stock.',
      contentWidth: AppContentWidth.records,
      primaryAction: action,
      body: ListView(
        key: const ValueKey('expenses'),
        padding: EdgeInsets.all(tokens.spacing.s20),
        children: <Widget>[chips, child],
      ),
    );
  }
}

/// What is known once the period has been read.
final class _ExpensesContents extends StatelessWidget {
  const _ExpensesContents({
    required this.period,
    required this.currency,
    required this.range,
    required this.canRecord,
    this.onVoid,
    this.onOpenCategory,
  });

  final TenantExpensePeriod period;
  final TenantReportingCurrency currency;
  final TenantExpenseRange range;
  final bool canRecord;

  /// Withdraws one record, or null on a build that cannot write.
  final ValueChanged<TenantExpense>? onVoid;

  /// Opens one category's own records and its day-by-day chart.
  final ValueChanged<TenantExpenseCategory>? onOpenCategory;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final live = period.records.where((record) => !record.isVoided).length;
    final spent = period.spentCategories.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // The same note the daily summary and the totals page carry, in the
        // same place: a figure is why this route exists, its label is not.
        if (!currency.isKnown) ...<Widget>[
          const Callout(
            key: ValueKey('expenses-currency-unknown'),
            status: AppStatus.info,
            message: TenantReportingCurrency.unknownNotice,
          ),
          SizedBox(height: tokens.spacing.s16),
        ],
        // **The total is the middle of the ring, not a tile above it.** Two
        // headline cards over a ring said the same figure twice and pushed the
        // picture below the fold on a phone. The composition is this page's
        // headline, and the total belongs in the hole it already has.
        if (spent)
          _CategoryShares(
            period: period,
            currency: currency,
            onOpenCategory: onOpenCategory,
          )
        else
          Text(
            currency.format(period.total),
            key: const ValueKey('expenses-total'),
            textAlign: TextAlign.center,
            style: tokens.typography.numericHero.copyWith(
              color: tokens.colors.text.money,
            ),
          ),
        SizedBox(height: tokens.spacing.s12),
        Text(
          '$live ${live == 1 ? 'record' : 'records'}, '
          '${range.label.toLowerCase()}',
          key: const ValueKey('expenses-count'),
          textAlign: TextAlign.center,
          style: tokens.typography.caption.copyWith(
            color: tokens.colors.text.tertiary,
          ),
        ),
        if (period.truncated) ...<Widget>[
          SizedBox(height: tokens.spacing.s20),
          const Callout(
            key: ValueKey('expenses-truncated'),
            status: AppStatus.attention,
            title: 'This total is not the whole period',
            message:
                'More expenses were recorded than one reading holds, so what '
                'is shown above is only part of the spending. Choose a shorter '
                'stretch of days to see a complete total.',
          ),
        ],
        SizedBox(height: tokens.spacing.s32),
        if (period.records.isEmpty)
          EmptyState(
            key: const ValueKey('expenses-empty'),
            title: 'Nothing recorded ${range.label.toLowerCase()}',
            hint: canRecord
                ? 'Record rent, wages, fuel or a repair and it counts against '
                      'profit from then on.'
                : null,
          )
        else
          for (final (index, record) in period.records.indexed)
            ExpenseRow(
              key: ValueKey('expense-${record.expenseId}'),
              record: record,
              currency: currency,
              onVoid: onVoid == null || record.isVoided
                  ? null
                  : () => onVoid!(record),
              first: index == 0,
            ),
      ],
    );
  }
}

/// One expense, as a row.
///
/// **A row rather than a card, at the developer's direction on 2026-08-27.**
/// `RecordList` gives every list in this app the same bordered card with its
/// actions in a left-aligned `Wrap`, and six of those stacked reads as filing
/// rather than as a ledger. This is the shape the app this feature came from
/// used: the money on the right, where a column of figures can be scanned down;
/// what it was for on the left; and a hairline between one row and the next
/// instead of a border drawn around every one.
///
/// **The void is a trailing control, not a boxed button beneath the record.**
/// It is one destructive action on a row that has no others, so it takes the
/// trailing edge - where this app already puts a record's own control wherever
/// a table is drawn - rather than a button the width of its own label sitting
/// under the figure it withdraws.
final class ExpenseRow extends StatelessWidget {
  const ExpenseRow({
    super.key,
    required this.record,
    required this.currency,
    this.onVoid,
    this.first = false,
    this.showCategory = true,
    this.reserveAction = true,
  });

  final TenantExpense record;
  final TenantReportingCurrency currency;

  /// Withdraws this record, or null where it cannot be - a build with no
  /// writer, or a record that has already been voided.
  final VoidCallback? onVoid;

  /// Whether this is the first row, which draws no hairline above itself.
  final bool first;

  /// Whether the heading is named beside the date. False on a category's own
  /// screen, where every row is under the heading the screen is called.
  final bool showCategory;

  /// Whether to hold the trailing control's width on a row that has none.
  ///
  /// True in a list where *some* row can be withdrawn, so every figure shares
  /// one right edge. False where no row in the list has an action at all, and
  /// holding the slot would only rob the description of 48 it could have used.
  final bool reserveAction;

  /// The reference's `DateFormat.yMMMd`, in this app's order - the same face
  /// the daily chart labels its axis with, so a date means the same thing on
  /// both halves of the screen.
  static final DateFormat _dayFormat = DateFormat('d MMM yyyy');

  String get _when {
    final date = DateTime.tryParse(record.businessDate);
    final day = date == null ? record.businessDate : _dayFormat.format(date);
    return showCategory ? '${record.category.label} - $day' : day;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final voided = record.isVoided;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (!first)
          Divider(
            height: 1,
            thickness: 1,
            color: tokens.colors.surface.borderSubtle,
          ),
        Semantics(
          container: true,
          // The row's own reading, in the order a person would say it. The
          // strike-through and the muted figure are both restatements of
          // "voided", which is said here in words (hard rule 4).
          label: <String>[
            record.description,
            record.category.label,
            currency.format(record.amount),
            record.businessDate,
            if (voided) 'Voided',
            if (record.voidReason case final reason?) 'Because $reason',
          ].join(', '),
          excludeSemantics: true,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: tokens.spacing.s16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // The reference leads every record with a wallet glyph, and it
                // earns its place: it is what makes a column of rows read as a
                // ledger of money out rather than as a list of sentences.
                Padding(
                  padding: EdgeInsets.only(top: tokens.spacing.s4),
                  child: Icon(
                    Icons.account_balance_wallet_outlined,
                    size: AppButton.iconSize,
                    color: voided
                        ? tokens.colors.text.tertiary
                        : tokens.colors.action.tertiary.label,
                  ),
                ),
                SizedBox(width: tokens.spacing.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        record.description,
                        style: tokens.typography.bodyLarge.copyWith(
                          color: voided
                              ? tokens.colors.text.tertiary
                              : tokens.colors.text.primary,
                        ),
                      ),
                      SizedBox(height: tokens.spacing.s4),
                      Text(
                        _when,
                        style: tokens.typography.caption.copyWith(
                          color: tokens.colors.text.tertiary,
                        ),
                      ),
                      // **The word, not only the strike.** A struck figure is
                      // a second way of saying this, and hard rule 4 does not
                      // accept a line through a number as the only one. The
                      // reason travels with it where there is one: a withdrawn
                      // record with no explanation is a mystery rather than a
                      // correction.
                      if (voided) ...<Widget>[
                        SizedBox(height: tokens.spacing.s4),
                        Text(
                          record.voidReason == null
                              ? 'Voided'
                              : 'Voided - ${record.voidReason}',
                          style: tokens.typography.caption.copyWith(
                            color: tokens.colors.status.neutral.fg,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: tokens.spacing.s16),
                Text(
                  currency.format(record.amount),
                  key: ValueKey('expense-amount-${record.expenseId}'),
                  // **`numeric.body`, not the compact hero.** A 22pt figure on
                  // every row pushed the description into a second line and
                  // made a list of seven look like seven headlines; this is the
                  // size the role exists for - "money and counts in flow".
                  style: tokens.typography.numericBody.copyWith(
                    color: voided
                        ? tokens.colors.text.tertiary
                        : tokens.colors.text.money,
                    decoration: voided ? TextDecoration.lineThrough : null,
                  ),
                ),
                // **The slot is held whether or not it is filled.** A row that
                // simply dropped the control let its figure run to the edge,
                // and a column of money that does not share one right edge
                // cannot be scanned down - which is the whole reason the
                // figures are on this side.
                if (reserveAction) ...<Widget>[
                  SizedBox(width: tokens.spacing.s8),
                  SizedBox(
                    width: tokens.spacing.s48,
                    child: onVoid == null
                        ? null
                        : AppIconButton(
                            key: ValueKey('expense-void-${record.expenseId}'),
                            icon: Icons.remove_circle_outline,
                            semanticLabel: 'Void ${record.description}',
                            tier: AppButtonTier.destructive,
                            bordered: false,
                            onPressed: onVoid,
                          ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// What each category took of the period's spending.
///
/// **The one visual idea carried over intact.** A labelled bar with its own
/// figure beside it says which category is eating the month without a legend,
/// a colour key, or a charting library - and the figure is what makes the bar
/// legible rather than decorative. **The share is never the only signal**: it
/// is stated in words for a screen reader, drawn as a bar, and printed as money
/// on the same row, so nothing here depends on seeing a length or a colour.
final class _CategoryShares extends StatelessWidget {
  const _CategoryShares({
    required this.period,
    required this.currency,
    this.onOpenCategory,
  });

  final TenantExpensePeriod period;
  final TenantReportingCurrency currency;

  /// Opens one category's own records and its day-by-day chart.
  final ValueChanged<TenantExpenseCategory>? onOpenCategory;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final categories = period.spentCategories;
    if (categories.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ExpenseCompositionRing(period: period, currency: currency),
        SizedBox(height: tokens.spacing.s20),
        // **The rows are the ring's legend and its accessible reading.**
        // Each carries the same colour as its slice, and also the name, the
        // figure and the share in words - so nothing here is told by colour
        // alone (hard rule 4).
        for (var index = 0; index < categories.length; index++) ...<Widget>[
          if (index > 0) SizedBox(height: tokens.spacing.s16),
          _CategoryShareRow(
            category: categories[index],
            swatch: ExpenseCompositionRing.colorFor(tokens, index),
            amount: (period.totalByCategory[categories[index]] ?? 0) / 100,
            share: period.shareOf(categories[index]),
            currency: currency,
            onOpen: onOpenCategory == null
                ? null
                : () => onOpenCategory!(categories[index]),
          ),
        ],
      ],
    );
  }
}

final class _CategoryShareRow extends StatelessWidget {
  const _CategoryShareRow({
    required this.category,
    required this.swatch,
    required this.amount,
    required this.share,
    required this.currency,
    this.onOpen,
  });

  final TenantExpenseCategory category;

  /// The colour of this category's slice of the ring above.
  final Color swatch;

  final double amount;
  final double? share;
  final TenantReportingCurrency currency;

  /// Opens this category on its own, or null where there is nowhere to go.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final fraction = share ?? 0;
    final percent = (fraction * 100).toStringAsFixed(0);
    final row = Semantics(
      container: true,
      // A row that opens nothing states itself here; one that does is wrapped
      // below by a `PressSurface` that states it as a button instead.
      label: onOpen != null
          ? null
          : '${category.label}, ${currency.format(amount)}, '
                '$percent per cent of what was spent.',
      excludeSemantics: onOpen == null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              // The ring's colour, restated where the name is. This is the
              // only place the palette is decoded, and it never carries the
              // fact alone - the name is right beside it.
              Container(
                width: tokens.spacing.s8,
                height: tokens.spacing.s8,
                decoration: BoxDecoration(
                  color: swatch,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: tokens.spacing.s8),
              Expanded(
                child: Text(
                  category.label,
                  key: ValueKey('expense-share-${category.wireValue}'),
                  style: tokens.typography.labelMedium.copyWith(
                    color: tokens.colors.text.primary,
                  ),
                ),
              ),
              SizedBox(width: tokens.spacing.s12),
              Text(
                '$percent%',
                style: tokens.typography.caption.copyWith(
                  color: tokens.colors.text.tertiary,
                ),
              ),
              SizedBox(width: tokens.spacing.s12),
              Text(
                currency.format(amount),
                key: ValueKey('expense-share-amount-${category.wireValue}'),
                style: tokens.typography.numericBody.copyWith(
                  color: tokens.colors.text.money,
                ),
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.s8),
          ClipRRect(
            borderRadius: BorderRadius.circular(tokens.radius.sm),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: tokens.spacing.s8,
              backgroundColor: tokens.colors.surface.field,
              valueColor: AlwaysStoppedAnimation<Color>(swatch),
            ),
          ),
        ],
      ),
    );
    if (onOpen == null) return row;
    // `PressSurface` carries the density's own minimum tap target, so a short
    // row is still a full-sized thing to hit, and it brings the hover, focus
    // and pressed states a tappable row has to have (hard rule 5).
    return PressSurface(
      key: ValueKey('expense-open-${category.wireValue}'),
      onPressed: onOpen,
      borderRadius: BorderRadius.circular(tokens.radius.md),
      fillWidth: true,
      semanticLabel:
          'Open ${category.label}, ${currency.format(amount)}, '
          '$percent per cent of what was spent.',
      excludeSemantics: true,
      child: row,
    );
  }
}

/// The page while its own read is still running.
///
/// Shaped like what is coming - two figure tiles, a block where the shares go,
/// three record rows - rather than one grey slab, and it claims nothing: no
/// zero total, no "nothing recorded", both of which are answers this page does
/// not have yet.
final class _ExpensesReading extends StatelessWidget {
  const _ExpensesReading();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return SkeletonGroup(
      key: const ValueKey('expenses-reading'),
      semanticLabel: 'Reading what this business spent.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              for (var tile = 0; tile < 2; tile++) ...<Widget>[
                if (tile > 0) SizedBox(width: tokens.spacing.s16),
                Expanded(
                  child: SkeletonBlock(
                    height: tokens.spacing.s64 + tokens.spacing.s24,
                    radius: tokens.radius.lg,
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: tokens.spacing.s32),
          for (var row = 0; row < 3; row++) ...<Widget>[
            if (row > 0) SizedBox(height: tokens.spacing.s16),
            SkeletonLine(
              widthFactor: 0.9 - row * 0.15,
              style: tokens.typography.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

/// Opens the record form as a sheet over the list it will add to.
///
/// A sheet rather than a route, for the same reason the stock correction is
/// one: recording an expense is a short errand with one answer, and pushing a
/// screen takes a person away from the period they were reading.
Future<AppNotice?> showExpenseRecordSheet(
  BuildContext context, {
  required TenantExpenseWriter writer,
  required TenantSession session,
  required String businessDate,
}) => showAppSheet<AppNotice>(
  context,
  initialDetent: AppSheetDetent.full,
  builder: (sheetContext, scrollController) => _RecordExpenseForm(
    writer: writer,
    session: session,
    businessDate: businessDate,
    scrollController: scrollController,
    onCompleted: (notice) => Navigator.of(sheetContext).pop(notice),
    onCancel: () => Navigator.of(sheetContext).pop(),
  ),
);

/// Asks why a record is being withdrawn, then withdraws it.
///
/// **The reason is required rather than offered.** The Firestore rule refuses a
/// void without one, and that is the point of the whole mechanism: a figure
/// that changed without a stated cause is the thing a business cannot audit.
Future<AppNotice?> showExpenseVoidSheet(
  BuildContext context, {
  required TenantExpenseWriter writer,
  required TenantSession session,
  required TenantExpense record,
  required TenantReportingCurrency currency,
}) => showAppSheet<AppNotice>(
  context,
  builder: (sheetContext, scrollController) => _VoidExpenseForm(
    writer: writer,
    session: session,
    record: record,
    currency: currency,
    scrollController: scrollController,
    onCompleted: (notice) => Navigator.of(sheetContext).pop(notice),
    onCancel: () => Navigator.of(sheetContext).pop(),
  ),
);

final class _VoidExpenseForm extends StatefulWidget {
  const _VoidExpenseForm({
    required this.writer,
    required this.session,
    required this.record,
    required this.currency,
    required this.scrollController,
    required this.onCompleted,
    required this.onCancel,
  });

  final TenantExpenseWriter writer;
  final TenantSession session;
  final TenantExpense record;
  final TenantReportingCurrency currency;
  final ScrollController scrollController;
  final ValueChanged<AppNotice> onCompleted;
  final VoidCallback onCancel;

  @override
  State<_VoidExpenseForm> createState() => _VoidExpenseFormState();
}

class _VoidExpenseFormState extends State<_VoidExpenseForm> {
  final TextEditingController _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final TenantExpenseVoidIntent intent;
    try {
      intent = TenantExpenseVoidIntent(
        tenantId: widget.session.tenantId,
        expenseId: widget.record.expenseId,
        reason: _reason.text,
        voidedBy: widget.session.uid,
      );
    } on TenantExpenseException {
      setState(() => _error = 'Say in a few words why this is being removed.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.writer.voidExpense(intent);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result.kind) {
      case TenantExpenseWriteKind.committed:
        widget.onCompleted(
          const AppNotice(message: 'Expense voided.', status: AppStatus.ok),
        );
      case TenantExpenseWriteKind.unavailable:
        setState(
          () => _error =
              'This device is offline. A void is recorded on the server, so '
              'it has to wait for a connection.',
        );
      case TenantExpenseWriteKind.rejected:
        setState(
          () => _error =
              'The server refused this. A record can only be voided once.',
        );
      case TenantExpenseWriteKind.ambiguous:
        setState(
          () => _error =
              'It is not known whether this was voided. Open the list again to '
              'see where it stands.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return ListView(
      controller: widget.scrollController,
      padding: EdgeInsets.all(tokens.spacing.s24),
      children: <Widget>[
        Text(
          'Void this expense?',
          style: tokens.typography.titleMedium.copyWith(
            color: tokens.colors.text.primary,
          ),
        ),
        SizedBox(height: tokens.spacing.s8),
        Text(
          '${widget.record.description} - '
          '${widget.currency.format(widget.record.amount)} on '
          '${widget.record.businessDate}.',
          style: tokens.typography.bodyMedium.copyWith(
            color: tokens.colors.text.secondary,
          ),
        ),
        SizedBox(height: tokens.spacing.s16),
        Text(
          'It stays on the list, struck through, and stops counting against '
          'profit. It cannot be restored or edited afterwards.',
          style: tokens.typography.caption.copyWith(
            color: tokens.colors.text.tertiary,
          ),
        ),
        SizedBox(height: tokens.spacing.s24),
        AppTextField(
          key: const ValueKey('expense-void-reason'),
          label: 'Why',
          controller: _reason,
          enabled: !_busy,
          maxLength: 500,
          placeholder: 'Recorded twice',
        ),
        if (_error case final message?) ...<Widget>[
          SizedBox(height: tokens.spacing.s20),
          Callout(
            key: const ValueKey('expense-void-error'),
            status: AppStatus.problem,
            message: message,
          ),
        ],
        SizedBox(height: tokens.spacing.s32),
        AppButton(
          key: const ValueKey('expense-void-submit'),
          label: 'Void expense',
          tier: AppButtonTier.destructive,
          loading: _busy,
          expand: true,
          onPressed: _busy ? null : _submit,
        ),
        SizedBox(height: tokens.spacing.s12),
        AppButton(
          key: const ValueKey('expense-void-cancel'),
          label: 'Keep it',
          expand: true,
          onPressed: _busy ? null : widget.onCancel,
        ),
      ],
    );
  }
}

final class _RecordExpenseForm extends StatefulWidget {
  const _RecordExpenseForm({
    required this.writer,
    required this.session,
    required this.businessDate,
    required this.scrollController,
    required this.onCompleted,
    required this.onCancel,
  });

  final TenantExpenseWriter writer;
  final TenantSession session;
  final String businessDate;
  final ScrollController scrollController;
  final ValueChanged<AppNotice> onCompleted;
  final VoidCallback onCancel;

  @override
  State<_RecordExpenseForm> createState() => _RecordExpenseFormState();
}

class _RecordExpenseFormState extends State<_RecordExpenseForm> {
  final TextEditingController _description = TextEditingController();
  final TextEditingController _amount = TextEditingController();

  /// **No default category.** A chooser that opens on one makes that one the
  /// cheapest answer, and a report where most of the money sits under whatever
  /// the form opened on tells its reader nothing.
  TenantExpenseCategory? _category;

  bool _busy = false;
  String? _error;

  /// Held across an ambiguous attempt, so a retry addresses the same document
  /// rather than filing the expense twice.
  String? _token;

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final category = _category;
    if (category == null) {
      setState(() => _error = 'Choose what this expense was for.');
      return;
    }
    final amountMinor = checkoutMinorUnitsFromMajor(
      double.tryParse(_amount.text.trim()) ?? -1,
    );
    if (amountMinor == null || amountMinor <= 0) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }
    if (_description.text.trim().length < 3) {
      setState(() => _error = 'Say in a few words what this was for.');
      return;
    }

    final TenantExpenseCreateIntent intent;
    try {
      intent = TenantExpenseCreateIntent(
        tenantId: widget.session.tenantId,
        businessDate: widget.businessDate,
        token: _token ??= secureTenantExpenseToken(),
        category: category,
        description: _description.text,
        amountMinor: amountMinor,
        recordedBy: widget.session.uid,
      );
    } on TenantExpenseException {
      setState(() => _error = 'This expense could not be recorded as entered.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.writer.recordExpense(intent);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result.kind) {
      case TenantExpenseWriteKind.committed:
        widget.onCompleted(
          const AppNotice(message: 'Expense recorded.', status: AppStatus.ok),
        );
      case TenantExpenseWriteKind.unavailable:
        setState(
          () => _error =
              'This device is offline. An expense is recorded on the server, '
              'so it has to wait for a connection.',
        );
      case TenantExpenseWriteKind.rejected:
        // A rejection will not change on a retry, so the held token is dropped
        // and the next attempt is a genuinely new record.
        _token = null;
        setState(() => _error = 'The server refused this expense.');
      case TenantExpenseWriteKind.ambiguous:
        setState(
          () => _error =
              'It is not known whether this was recorded. Try again - the same '
              'entry cannot be filed twice.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return ListView(
      controller: widget.scrollController,
      padding: EdgeInsets.all(tokens.spacing.s24),
      children: <Widget>[
        Text(
          'Record an expense',
          style: tokens.typography.titleMedium.copyWith(
            color: tokens.colors.text.primary,
          ),
        ),
        SizedBox(height: tokens.spacing.s8),
        Text(
          'It counts against profit for ${widget.businessDate}.',
          style: tokens.typography.caption.copyWith(
            color: tokens.colors.text.tertiary,
          ),
        ),
        SizedBox(height: tokens.spacing.s24),
        // Typed nullable so the field can stand empty: see [_category].
        AppSelect<TenantExpenseCategory?>(
          key: const ValueKey('expense-category'),
          label: 'What for',
          value: _category,
          enabled: !_busy,
          helper: 'Rent, wages, fuel, a repair.',
          items: <AppSelectItem<TenantExpenseCategory?>>[
            for (final category in TenantExpenseCategory.values)
              AppSelectItem<TenantExpenseCategory?>(
                key: ValueKey('expense-category-${category.wireValue}'),
                value: category,
                label: category.label,
              ),
          ],
          onChanged: (category) => setState(() => _category = category),
        ),
        SizedBox(height: tokens.spacing.s20),
        AppTextField(
          key: const ValueKey('expense-description'),
          label: 'Description',
          controller: _description,
          enabled: !_busy,
          maxLength: 500,
          placeholder: 'August rent',
        ),
        SizedBox(height: tokens.spacing.s20),
        AppTextField(
          key: const ValueKey('expense-amount'),
          label: 'Amount',
          controller: _amount,
          enabled: !_busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        if (_error case final message?) ...<Widget>[
          SizedBox(height: tokens.spacing.s20),
          Callout(
            key: const ValueKey('expense-error'),
            status: AppStatus.problem,
            message: message,
          ),
        ],
        SizedBox(height: tokens.spacing.s32),
        AppButton(
          key: const ValueKey('expense-submit'),
          label: 'Record expense',
          tier: AppButtonTier.primary,
          loading: _busy,
          expand: true,
          onPressed: _busy ? null : _submit,
        ),
        SizedBox(height: tokens.spacing.s12),
        AppButton(
          key: const ValueKey('expense-cancel'),
          label: 'Cancel',
          expand: true,
          onPressed: _busy ? null : widget.onCancel,
        ),
      ],
    );
  }
}

DateTime _utcNow() => DateTime.now().toUtc();
