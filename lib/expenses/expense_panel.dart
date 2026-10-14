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
import 'package:uzapay_pos/observability/app_telemetry.dart';

import '../checkout/checkout_draft.dart';
import '../inventory/product_image_cache.dart';
import '../reporting/reporting_currency.dart';
import '../reports/analysis/expense_analysis.dart';
import '../reports/analysis/expense_report.dart';
import '../reports/report_document.dart';
import '../reports/report_file.dart';
import '../reports/report_identity_source.dart';
import '../reports/report_period.dart';
import '../reports/report_run.dart';
import '../reports/ui/report_action.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../ui/buttons.dart';
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
/// **Two business dates rather than three fixed offsets**, at the developer's
/// direction on 2026-09-22. *Today*, *Last 7 days* and *Last 30 days* answered
/// three questions and refused every other one: a shopkeeper closing off
/// August could not ask for August, and one checking a quarter could not ask
/// for it either. A range is the same read - `readRange` has always taken two
/// dates - with the choice handed to the person instead of enumerated for
/// them.
@immutable
final class TenantExpenseRange {
  const TenantExpenseRange({required this.startDate, required this.endDate});

  /// The month [now] falls in, up to [now] itself.
  ///
  /// **Month to date, not the whole month**, which is what this route opens on.
  /// A range running to the end of the month would spend its read on days that
  /// have not happened, and label a total *September* when September is three
  /// weeks from over.
  factory TenantExpenseRange.monthOf(DateTime now) {
    final today = checkoutBusinessDate(now);
    final first = DateTime.utc(now.year, now.month);
    return TenantExpenseRange(
      startDate: checkoutBusinessDate(first),
      endDate: today,
    );
  }

  /// `yyyy-MM-dd`, inclusive.
  final String startDate;
  final String endDate;

  DateTime get start => DateTime.parse('${startDate}T00:00:00Z');
  DateTime get end => DateTime.parse('${endDate}T00:00:00Z');

  /// How many business dates the range covers, including both ends.
  int get days => end.difference(start).inDays + 1;

  /// What the filter and the captions call this stretch.
  ///
  /// **The shapes a person recognises are named**, because `1 Sep - 22 Sep` is
  /// a worse answer than *this month* to somebody who asked for this month.
  /// Anything else is stated as its two ends, which is the only honest reading
  /// of a range nobody has a word for.
  String label(DateTime now) {
    final today = checkoutBusinessDate(now);
    final yesterday = checkoutBusinessDate(
      now.subtract(const Duration(days: 1)),
    );
    if (startDate == endDate) {
      if (endDate == today) return 'Today';
      if (endDate == yesterday) return 'Yesterday';
      return _dayFormat.format(start);
    }
    final month = TenantExpenseRange.monthOf(now);
    if (startDate == month.startDate && endDate == month.endDate) {
      return 'This month';
    }
    // Both ends inside one month: the month is said once rather than twice.
    if (start.year == end.year && start.month == end.month) {
      return '${start.day} - ${_dayFormat.format(end)}';
    }
    return '${_dayFormat.format(start)} - ${_dayFormat.format(end)}';
  }

  @override
  bool operator ==(Object other) =>
      other is TenantExpenseRange &&
      other.startDate == startDate &&
      other.endDate == endDate;

  @override
  int get hashCode => Object.hash(startDate, endDate);

  static final DateFormat _dayFormat = DateFormat('d MMM');
}

/// Withdraws one expense, answering whether it was withdrawn.
///
/// A `Future<bool>` rather than a `void` callback because the surface asking
/// is a pushed route holding a snapshot: it has to know whether to leave.
typedef TenantExpenseVoidRequest = Future<bool> Function(TenantExpense record);

/// The Expenses route.
final class TenantExpensesScreen extends StatelessWidget {
  const TenantExpensesScreen({
    super.key,
    required this.reader,
    this.writer,
    this.clock,
    this.reportSaver,
    this.imageCache,
  });

  final TenantDataReader reader;

  /// The write boundary, or null on a build with no recording wired up - in
  /// which case this route reads and never offers a form it cannot submit.
  final TenantExpenseWriter? writer;

  final DateTime Function()? clock;

  /// Where a generated report goes. Null renders no report control at all,
  /// which is what a build with no saver wired should show rather than a
  /// button that does nothing.
  final TenantReportSaver? reportSaver;

  /// Lets a report's branding lockup reuse the logo this device already holds.
  final TenantImageCache? imageCache;

  @override
  Widget build(BuildContext context) => TenantExpensesPanel(
    reader: reader,
    writer: writer,
    clock: clock,
    reportSaver: reportSaver,
    imageCache: imageCache,
  );
}

/// Reads and records expenses behind [TenantRouteGuard].
final class TenantExpensesPanel extends StatefulWidget {
  const TenantExpensesPanel({
    super.key,
    required this.reader,
    this.writer,
    this.clock,
    this.reportSaver,
    this.imageCache,
  });

  final TenantDataReader reader;
  final TenantExpenseWriter? writer;
  final DateTime Function()? clock;
  final TenantReportSaver? reportSaver;
  final TenantImageCache? imageCache;

  @override
  State<TenantExpensesPanel> createState() => _TenantExpensesPanelState();
}

class _TenantExpensesPanelState extends State<TenantExpensesPanel> {
  /// Set in [initState] rather than here, because it is read off the clock.
  late TenantExpenseRange _range;

  /// The type the page is narrowed to, or null for every type.
  ///
  /// **Not part of the guard key, and that is the difference between the two
  /// filters.** The period decides which documents are read, so changing it
  /// re-reads; the type only decides which of the records already in hand
  /// are counted, so changing it is a repaint. Putting it in the key would
  /// spend a read to throw records away.
  TenantExpenseCategory? _category;

  int _generation = 0;

  String? _loaderKey;
  TenantGuardedLoader<_ExpensesView>? _loader;
  TenantGuardedLoader<_ExpensesView>? _cachedLoader;

  DateTime get _now => (widget.clock ?? _utcNow)().toUtc();

  @override
  void initState() {
    super.initState();
    _range = TenantExpenseRange.monthOf(_now);
  }

  /// Opens the calendar on the range in hand and reads back whatever comes out.
  ///
  /// **`firstDate` is not the beginning of time.** A range read is bounded at
  /// [TenantExpenseRepository.maximumRangeRecords], so a person who picks five
  /// years gets a total that is quietly short - the truncation callout says so,
  /// but a picker that offers the year 2000 is inviting it. One year back is
  /// the longest stretch this page can draw a chart for anyway.
  Future<void> _pickRange() async {
    final now = _now;
    final today = DateTime.utc(now.year, now.month, now.day);
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _range.start, end: _range.end),
      firstDate: DateTime.utc(today.year - 1, today.month, today.day),
      lastDate: today,
      helpText: 'Select the days to total',
      saveText: 'Done',
    );
    if (picked == null || !mounted) return;
    final next = TenantExpenseRange(
      startDate: checkoutBusinessDate(picked.start),
      endDate: checkoutBusinessDate(picked.end),
    );
    if (next == _range) return;
    setState(() => _range = next);
  }

  /// Re-reads the period, after a record or a void changed what is in it.
  void _reload() => setState(() => _generation++);

  /// One pair of loaders per guard key. A closure rebuilt every frame would
  /// re-read on every keystroke of the form above it.
  void _composeLoaders(String key) {
    if (key == _loaderKey && _loader != null) return;
    _loaderKey = key;
    final startDate = _range.startDate;
    final endDate = _range.endDate;
    _loader = _readWith(widget.reader, startDate, endDate);
    final cache = widget.reader.cached;
    _cachedLoader = cache == null ? null : _readWith(cache, startDate, endDate);
  }

  /// The page's whole read, over whichever reader it is handed.
  ///
  /// **One body, two readers.** The guard runs this against the server and
  /// against this device's own copy at the same time; writing the read twice
  /// would be two chances for them to drift into answering different questions.
  TenantGuardedLoader<_ExpensesView> _readWith(
    TenantDataReader reader,
    String startDate,
    String endDate,
  ) => (session) async {
    // **Both are Firestore reads and both serve from the cache**, so they are
    // started together and neither waits on the other's round trip. There is
    // no callable anywhere on this page, which is why it works with no signal
    // at all - and why net profit is composed on the client from this rather
    // than asked of a server.
    final period = TenantExpenseRepository(
      session: session,
      reader: reader,
    ).readRange(startDate: startDate, endDate: endDate);
    final currency = TenantReportingCurrency.read(
      session: session,
      reader: reader,
    );
    return (period: await period, currency: await currency);
  };

  /// Withdraws one record that should not have been there, and answers whether
  /// it was withdrawn.
  ///
  /// **A void rather than a delete, and it asks why.** The record stays on the
  /// list struck through, the reason travels with it, and both are refused any
  /// further change - so a correction is a thing that happened rather than a
  /// gap where something used to be. The Firestore rule enforces every part of
  /// that; this is the surface for it.
  ///
  /// **It reports back because the surface that asks is a pushed route.** A
  /// category's screen holds the period it was handed, so once one of its
  /// records is withdrawn its own figures are stale; it leaves on a true, and
  /// the list behind it - which has re-read by then - is what the person lands
  /// back on.
  Future<bool> _void(
    TenantSession session,
    TenantExpense record,
    TenantReportingCurrency currency,
  ) async {
    final writer = widget.writer;
    if (writer == null) return false;
    final answer = await showExpenseVoidSheet(
      context,
      writer: writer,
      session: session,
      record: record,
      currency: currency,
    );
    if (!mounted || answer == null) return false;
    showAppSnackBar(context, answer);
    // Reloaded for a queued void as well as a committed one, for the reason
    // `_record` gives. The caller is told only about a void that is settled,
    // because it closes a page over a record that is now gone.
    _reload();
    return answer.status == AppStatus.ok;
  }

  /// Opens one category on its own, carrying the period already read.
  void _openCategory(
    TenantSession session,
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
            periodLabel: _range.label(_now).toLowerCase(),
            onVoid: widget.writer == null
                ? null
                : (record) => _void(session, record, currency),
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
    // **Any answer at all means a record now exists to show.** This read
    // `status == ok`, which is the *committed* write only: a queued one
    // answers `AppNotice.offline`, whose status is `info`, so recording an
    // expense with the write still in flight left the list reading "Nothing
    // recorded last 30 days" over the expense just entered - and the obvious
    // response to that is to enter it again. The outcomes that did not write
    // anything - unavailable, rejected, ambiguous - keep the sheet open and
    // never answer, so they are not reached from here.
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final guardKey = '${_range.startDate}:${_range.endDate}:$_generation';
    // **Two selects in a row, under a button the width of the page**, at the
    // developer's direction on 2026-09-22 - the shape the sales report, the
    // shift history and the catalog already open in. The page's own rule about
    // chips is answered rather than broken: a chip strip is for a surface
    // carrying *one* filter, and this one now carries two.
    final filters = Padding(
      padding: EdgeInsets.only(bottom: tokens.spacing.s20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // **A button onto the calendar, not a list of three offsets.** The
          // sales report and the shift history both put their day behind
          // exactly this control, so a date on this page is opened the way a
          // date is opened everywhere else in the app.
          Expanded(
            child: AppButton(
              key: const ValueKey('expenses-range'),
              label: _range.label(_now),
              icon: Icons.calendar_today_outlined,
              tier: AppButtonTier.secondary,
              expand: true,
              onPressed: _pickRange,
            ),
          ),
          SizedBox(width: tokens.spacing.s12),
          Expanded(
            child: AppSelect<TenantExpenseCategory?>(
              key: const ValueKey('expenses-category-filter'),
              label: 'Type',
              dense: true,
              leading: Icons.folder_outlined,
              value: _category,
              items: <AppSelectItem<TenantExpenseCategory?>>[
                const AppSelectItem<TenantExpenseCategory?>(
                  key: ValueKey('expenses-category-filter-all'),
                  value: null,
                  label: 'All types',
                ),
                // Every type, not only the ones this period spent under: a
                // list that changes length with the read would move the option
                // under a person's finger between one period and the next.
                for (final category in TenantExpenseCategory.values)
                  AppSelectItem<TenantExpenseCategory?>(
                    key: ValueKey(
                      'expenses-category-filter-${category.wireValue}',
                    ),
                    value: category,
                    label: category.label,
                  ),
              ],
              onChanged: (category) => setState(() => _category = category),
            ),
          ),
        ],
      ),
    );
    _composeLoaders(guardKey);
    return TenantRouteGuard<_ExpensesView>(
      allowedRoles: TenantExpenseRepository.allowedRoles,
      load: _loader!,
      loadCached: _cachedLoader,
      holdsNothing: (view) => view.period.records.isEmpty,
      // **The chooser stays on screen through every phase**, the way the sales
      // totals page keeps its own: the control that would take a person to a
      // different period must not be behind the read of this one.
      loading: _ExpensesFrame(
        record: _recordButton(null),
        filters: filters,
        child: const _ExpensesReading(),
      ),
      denied: _ExpensesFrame(
        filters: filters,
        child: const EmptyState(
          key: ValueKey('expenses-denied'),
          title: 'Expenses unavailable for your role',
          hint: 'Owners and administrators can manage expenses.',
          illustration: 'access-denied.svg',
        ),
      ),
      failure: (context, error) => _ExpensesFrame(
        record: _recordButton(null),
        filters: filters,
        child: const ErrorState(
          key: ValueKey('expenses-failure'),
          badgeLabel: 'Not read',
          statement: 'What this business spent could not be read.',
          stillTrue: 'Nothing has been recorded or changed.',
        ),
      ),
      builder: (context, session, view) => _ExpensesFrame(
        record: _recordButton(() => _record(session)),
        reportAction: _reportAction(session),
        filters: filters,
        child: _ExpensesContents(
          period: view.period,
          currency: view.currency,
          rangeLabel: _range.label(_now),
          category: _category,
          canRecord: widget.writer != null,
          onOpenCategory: (category) =>
              _openCategory(session, category, view.period, view.currency),
          onVoid: widget.writer == null
              ? null
              : (record) => _void(session, record, view.currency),
        ),
      ),
    );
  }

  /// The toolbar control that takes a report of a period away.
  ///
  /// **Built here because this is where the session is.** A report reads the
  /// period the person picks at the moment they ask for it, against the
  /// guarded session - not against whatever this page happens to have on
  /// screen, and not against the range in the filter row. The two are
  /// deliberately independent: somebody looking at this month may well want
  /// last quarter on paper.
  ///
  /// Null where no saver is wired, which renders no control at all.
  Widget? _reportAction(TenantSession session) {
    final saver = widget.reportSaver;
    if (saver == null) return null;

    return TenantReportAction(
      clock: () => _now,
      run: TenantReportRun(
        kind: TenantReportKind.expenses,
        support: TenantReportPeriodSupport.range,
        saver: saver,
        build: (period) async {
          final source = TenantExpenseReportSource(
            repository: TenantExpenseRepository(
              session: session,
              reader: widget.reader,
            ),
          );
          final read = await source.gather(period);
          final identity = await readTenantReportIdentity(
            session: session,
            reader: widget.reader,
            generatedAt: _now,
            imageCache: widget.imageCache,
          );
          return describeExpenseReport(
            identity: identity,
            analysis: TenantExpenseAnalysis.from(
              period: period,
              spending: read.now,
              previous: read.before,
            ),
          );
        },
      ),
    );
  }

  /// The page's own control, the width of the page.
  ///
  /// **A labelled button above the list rather than a `+` on the top bar**, at
  /// the developer's direction on 2026-09-22. It carries the word *expense*,
  /// which the glyph never did.
  ///
  /// [onPressed] is null in the phases that have no session to record against,
  /// and the button is drawn disabled rather than left out: a control that
  /// appears once the read lands moves the filters under it, which is the jump
  /// the filter row is kept out of every phase to avoid. A build with no writer
  /// has no such control at all, in any phase.
  Widget? _recordButton(VoidCallback? onPressed) {
    if (widget.writer == null) return null;
    return Builder(
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: AppTokens.componentOf(context).spacing.s12,
        ),
        // **Secondary, not primary**, at the developer's direction on
        // 2026-09-22: the mint container is the loudest thing this app paints,
        // and a full-width slab of it above the figures made the page read as
        // being about adding an expense rather than about what has been spent.
        // §2.1's outlined tier is the same control, said at the volume a page
        // of reading can carry. The sheet this opens keeps its primary - one
        // action, one screen region, which is the rule the mint is rationed by.
        child: AppButton(
          key: const ValueKey('expenses-record'),
          label: 'Add expense',
          icon: Icons.add,
          tier: AppButtonTier.secondary,
          expand: true,
          onPressed: onPressed,
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
/// expense - may only be offered to somebody the guard has already admitted. A
/// route drawing that button outside the guard would hold it out to the manager
/// the guard is about to refuse.
///
/// **A `ListView` rather than a `Column`, and that is not cosmetic.** A month
/// of a real business is hundreds of records, and the page owning the scroll is
/// what stops the list running off the bottom.
final class _ExpensesFrame extends StatelessWidget {
  const _ExpensesFrame({
    required this.filters,
    required this.child,
    this.record,
    this.reportAction,
  });

  /// The period and the type, side by side.
  final Widget filters;

  final Widget child;

  /// The full-width record button, or null where this build cannot write and
  /// on the refusal, which offers nothing.
  final Widget? record;

  /// The toolbar control that takes a copy of a period away.
  ///
  /// **`actions` rather than `primaryAction`.** This page exists to show what
  /// the business spent; taking a report of it is a second thing you may want
  /// to do, not the reason the page is here. It is also absent in every phase
  /// but the read one - there is no session to report against until the guard
  /// has one, and a control that cannot work should not be drawn.
  final Widget? reportAction;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return AppScaffold(
      title: 'Expenses',
      contentWidth: AppContentWidth.records,
      actions: <Widget>[if (reportAction != null) reportAction!],
      body: ListView(
        key: const ValueKey('expenses'),
        padding: EdgeInsets.all(tokens.spacing.s20),
        children: <Widget>[if (record != null) record!, filters, child],
      ),
    );
  }
}

/// What is known once the period has been read.
final class _ExpensesContents extends StatelessWidget {
  const _ExpensesContents({
    required this.period,
    required this.currency,
    required this.rangeLabel,
    required this.category,
    required this.canRecord,
    this.onOpenCategory,
    this.onVoid,
  });

  /// The whole period, every type. Sliced here rather than by the caller, so
  /// a type drawn on its own can still state its share of all the spending.
  final TenantExpensePeriod period;

  final TenantReportingCurrency currency;

  /// What the filter above calls the stretch of days - *This month*, *Today*,
  /// *3 - 17 Sep*. Resolved by the panel, which is what holds the clock.
  final String rangeLabel;

  /// The type the filter above is holding, or null for all of them.
  final TenantExpenseCategory? category;

  final bool canRecord;

  /// Opens one category's own records and its day-by-day chart.
  final ValueChanged<TenantExpenseCategory>? onOpenCategory;

  /// Withdraws one record, for the type drawn in place of the composition.
  final TenantExpenseVoidRequest? onVoid;

  @override
  Widget build(BuildContext context) {
    // **A type chosen above draws that type's own screen here**, at the
    // developer's direction on 2026-09-22. The composition is the answer to
    // *where did the money go*, and narrowed to one type it degenerated into
    // a single bar at 100% - a picture of the question rather than of the
    // answer. What a person wants having named a type is what tapping that
    // type already gave them: the total, the days it fell on, and the
    // records. The filters stay above it, so the next type is one tap away
    // rather than a trip back.
    final chosen = category;
    if (chosen != null) {
      return TenantExpenseCategoryDetail(
        key: ValueKey('expenses-type-${chosen.wireValue}'),
        category: chosen,
        period: period.forCategory(chosen),
        whole: period,
        currency: currency,
        periodLabel: rangeLabel.toLowerCase(),
        onVoid: onVoid,
      );
    }
    final tokens = AppTokens.componentOf(context);
    final live = period.records.where((record) => !record.isVoided).length;
    final spent = period.spentCategories.isNotEmpty;
    final reachable = period.records.isNotEmpty;
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
        // A period that took no money draws no ring, so the figure it would
        // have held goes above the types instead of inside them.
        if (!spent) ...<Widget>[
          Text(
            currency.format(period.total),
            key: const ValueKey('expenses-total'),
            textAlign: TextAlign.center,
            style: tokens.typography.numericHero.copyWith(
              color: tokens.colors.text.money,
            ),
          ),
          if (reachable) SizedBox(height: tokens.spacing.s24),
        ],
        if (reachable)
          _CategoryShares(
            period: period,
            currency: currency,
            onOpenCategory: onOpenCategory,
          ),
        SizedBox(height: tokens.spacing.s12),
        Text(
          '$live ${live == 1 ? 'record' : 'records'}, '
          '${rangeLabel.toLowerCase()}',
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
        // **The page ends at the types, at the developer's direction on
        // 2026-08-28.** The reference this feature is measured against lists no
        // records here at all: the question this screen answers is *where did
        // the money go*, and a flat list of every record underneath answers a
        // different one twice as loudly. Records - and withdrawing one - are
        // inside the type they belong to, one tap away.
        if (period.records.isEmpty) ...<Widget>[
          SizedBox(height: tokens.spacing.s32),
          EmptyState(
            key: const ValueKey('expenses-empty'),
            title: 'Nothing recorded ${rangeLabel.toLowerCase()}',
            hint: canRecord
                ? 'Record an expense to include it in profit.'
                : null,
            illustration: 'empty-wallet.svg',
          ),
        ],
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
/// An expense's business date as the record list states it: `11 Oct 2026`.
///
/// The reference's `DateFormat.yMMMd`, in this app's order - the same face the
/// daily chart labels its axis with, so a date means the same thing on both
/// halves of the screen. A date that does not parse is printed as it stands.
String expenseDayLabel(String businessDate) {
  final date = DateTime.tryParse(businessDate);
  return date == null ? businessDate : _expenseDayFormat.format(date);
}

final DateFormat _expenseDayFormat = DateFormat('d MMM yyyy');

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

  /// Whether the type is named beside the date. False on a category's own
  /// screen, where every row is under the type the screen is called.
  final bool showCategory;

  /// Whether to hold the trailing control's width on a row that has none.
  ///
  /// True in a list where *some* row can be withdrawn, so every figure shares
  /// one right edge. False where no row in the list has an action at all, and
  /// holding the slot would only rob the description of 48 it could have used.
  final bool reserveAction;

  String get _when {
    final day = expenseDayLabel(record.businessDate);
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
    // **The fallback is the reachability rule, not a cosmetic one.** A period
    // whose every record has been voided took no money and so has no
    // composition to draw - but its records still exist, and a type is the
    // only way into them now that the route lists none itself.
    final spent = period.spentCategories;
    final categories = spent.isEmpty ? period.categories : spent;
    if (categories.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ExpenseCompositionRing(period: period, currency: currency),
        if (spent.isNotEmpty) SizedBox(height: tokens.spacing.s20),
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
  // **The sheet's own opening detent, not the full screen**, at the developer's
  // direction on 2026-09-22. Two fields, a chooser and a pair of buttons do not
  // need 95% of a phone, and taking it hid the period the record is being added
  // to. It is still draggable to full.
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
    final telemetry = AppTelemetry.current;
    final operation = telemetry.start(
      'expense.void',
      screen: 'expenses',
      context: {
        'user_id': widget.session.uid,
        'tenant_id': widget.session.tenantId,
        'expense_id': widget.record.expenseId,
      },
    );
    final TenantExpenseVoidIntent intent;
    try {
      intent = TenantExpenseVoidIntent(
        tenantId: widget.session.tenantId,
        expenseId: widget.record.expenseId,
        reason: _reason.text,
        voidedBy: widget.session.uid,
      );
    } on TenantExpenseException catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        operation: operation,
        boundary: 'expense.void_validate',
      );
      setState(() => _error = 'Say in a few words why this is being removed.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await telemetry.trace(
      operation,
      'void_expense',
      () => widget.writer.voidExpense(intent),
    );
    if (result.kind == TenantExpenseWriteKind.queued) {
      telemetry.recordStep(operation, 'saved_locally');
    } else if (result.kind == TenantExpenseWriteKind.committed) {
      telemetry.recordStep(operation, 'confirmed_on_server');
    } else {
      AppTelemetry.captureHandled(
        StateError(result.reasonCode ?? result.kind.name),
        StackTrace.current,
        operation: operation,
        code: result.reasonCode ?? result.kind.name,
      );
    }
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result.kind) {
      // **Queued is every save, online or not**: the writer stores the void
      // here and the worker carries it on. Saying *waiting to sync* announced
      // an outage on a connected phone; the sync badge is what says when
      // something is genuinely stuck.
      case TenantExpenseWriteKind.queued || TenantExpenseWriteKind.committed:
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
    final telemetry = AppTelemetry.current;
    final operation = telemetry.start(
      'expense.create',
      screen: 'expenses',
      context: {
        'user_id': widget.session.uid,
        'tenant_id': widget.session.tenantId,
        'currency': 'unavailable',
      },
    );
    final category = _category;
    if (category == null) {
      AppTelemetry.captureHandled(
        ArgumentError('missing_category'),
        StackTrace.current,
        operation: operation,
        code: 'validation_missing_category',
      );
      setState(() => _error = 'Choose what this expense was for.');
      return;
    }
    final amountMinor = checkoutMinorUnitsFromMajor(
      double.tryParse(_amount.text.trim()) ?? -1,
    );
    if (amountMinor == null || amountMinor <= 0) {
      AppTelemetry.captureHandled(
        ArgumentError('invalid_amount'),
        StackTrace.current,
        operation: operation,
        code: 'validation_invalid_amount',
      );
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }
    if (_description.text.trim().length < 3) {
      AppTelemetry.captureHandled(
        ArgumentError('missing_description'),
        StackTrace.current,
        operation: operation,
        code: 'validation_missing_description',
      );
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
    } on TenantExpenseException catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        operation: operation,
        boundary: 'expense.validate',
      );
      setState(() => _error = 'This expense could not be recorded as entered.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await telemetry.trace(
      operation,
      'save_expense',
      () => widget.writer.recordExpense(intent),
    );
    if (result.kind == TenantExpenseWriteKind.queued) {
      telemetry.recordStep(
        operation,
        'saved_locally',
        data: {'amount_minor': amountMinor, 'currency': 'unavailable'},
      );
    } else if (result.kind == TenantExpenseWriteKind.committed) {
      telemetry.recordStep(operation, 'confirmed_on_server');
    } else {
      AppTelemetry.captureHandled(
        StateError(result.reasonCode ?? result.kind.name),
        StackTrace.current,
        operation: operation,
        code: result.reasonCode ?? result.kind.name,
        data: {'amount_minor': amountMinor, 'currency': 'unavailable'},
      );
    }
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result.kind) {
      // Queued is every save, online or not - see the void above.
      case TenantExpenseWriteKind.queued || TenantExpenseWriteKind.committed:
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
