import 'package:flutter/material.dart';

import '../tenancy/tenant_catalog.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import 'sales_totals.dart';

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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sales totals')),
    body: TenantSalesTotalsPanel(
      callable: callable,
      reader: reader,
      clock: clock,
    ),
  );
}

/// The categories one session may filter by, and whether they could be read.
///
/// An unreadable list is not a failure of this route: the whole-business figure
/// does not depend on it, so the filter disappears and the total stays.
final class _CategoryOptions {
  const _CategoryOptions({required this.items, required this.readable});

  const _CategoryOptions.unreadable()
    : items = const <TenantCategory>[],
      readable = false;

  final List<TenantCategory> items;
  final bool readable;

  String? nameOf(String categoryId) {
    for (final category in items) {
      if (category.id == categoryId) return category.name;
    }
    return null;
  }
}

/// One period's totals with the categories the surface offers alongside them.
final class _SalesTotalsView {
  const _SalesTotalsView({required this.totals, required this.categories});

  final TenantSalesTotals totals;
  final _CategoryOptions categories;
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

  @override
  State<TenantSalesTotalsPanel> createState() => _TenantSalesTotalsPanelState();
}

final class _TenantSalesTotalsPanelState
    extends State<TenantSalesTotalsPanel> {
  late TenantSalesPeriod _period = widget.period;
  TenantSalesScope _scope = TenantSalesScope.everyone;
  String? _categoryId;
  int _generation = 0;

  String? _loaderKey;
  TenantGuardedLoader<_SalesTotalsView>? _loader;

  /// One category list per session, so a list read for one business can never
  /// label - or filter - another's figures.
  _CategoryOptions? _categories;
  String? _categoriesSessionKey;

  static String _sessionKey(TenantSession session) =>
      '${session.uid}:${session.tenantId}:${session.epoch}';

  void _choosePeriod(TenantSalesPeriod period) {
    if (period == _period) return;
    setState(() => _period = period);
  }

  void _chooseScope(TenantSalesScope scope) {
    if (scope == _scope) return;
    setState(() => _scope = scope);
  }

  void _chooseCategory(String? categoryId) {
    if (categoryId == _categoryId) return;
    setState(() => _categoryId = categoryId);
  }

  /// Asks again for the same period, scope, and category.
  ///
  /// Safe without qualification: reading totals writes nothing, so a retry can
  /// never duplicate anything the way a reconciliation request could.
  void _retry() => setState(() => _generation++);

  /// Reads this session's categories once, and never fails the route with them.
  ///
  /// The figure a manager came for does not depend on the filter list, so an
  /// unreadable list removes the filter and says so rather than replacing the
  /// total with an error.
  Future<_CategoryOptions> _categoriesFor(TenantSession session) async {
    final key = _sessionKey(session);
    final cached = _categories;
    if (cached != null && key == _categoriesSessionKey) return cached;
    _CategoryOptions options;
    try {
      final page = await TenantCatalogRepository(
        session: session,
        reader: widget.reader,
      ).loadCategories(pageSize: widget.categoryPageSize);
      options = _CategoryOptions(items: page.items, readable: true);
    } on TenantScopeViolation {
      // A reader answering outside this tenant is a broken boundary, not an
      // unavailable label, and it must not be swallowed into a quiet degrade.
      rethrow;
    } catch (_) {
      options = const _CategoryOptions.unreadable();
    }
    _categoriesSessionKey = key;
    return _categories = options;
  }

  /// One loader per guard key, so a closure rebuilt every frame cannot spend
  /// another callable invocation on an unrelated `setState`.
  TenantGuardedLoader<_SalesTotalsView> _loaderFor(String key) {
    if (key == _loaderKey && _loader != null) return _loader!;
    _loaderKey = key;
    final period = _period;
    final scope = _scope;
    final chosenCategory = _categoryId;
    return _loader = (session) async {
      final categories = await _categoriesFor(session);
      // A category filters the figures only while this business's own canonical
      // list still contains it. A selection carried across a tenant switch, or
      // one that has since been deleted, silently reverts to the whole catalog
      // rather than filtering by an ID this business never had.
      final categoryId =
          chosenCategory != null && categories.nameOf(chosenCategory) != null
          ? chosenCategory
          : null;
      final gateway = TenantSalesTotalsGateway(
        session: session,
        callable: widget.callable,
        clock: widget.clock,
      );
      return _SalesTotalsView(
        totals: await gateway.load(
          gateway.createQuery(
            period: period,
            scope: scope,
            categoryId: categoryId,
          ),
        ),
        categories: categories,
      );
    };
  }

  @override
  Widget build(BuildContext context) {
    final guardKey =
        '${_period.name}:${_scope.name}:${_categoryId ?? '-'}:$_generation';
    return TenantRouteGuard<_SalesTotalsView>(
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
        scope: _scope,
        categoryId: _categoryId,
        categories: _categories ?? const _CategoryOptions.unreadable(),
        onChoosePeriod: _choosePeriod,
        onChooseScope: _chooseScope,
        onChooseCategory: _chooseCategory,
        onRetry: _retry,
        failureMessage: _failureMessage(error),
      ),
      builder: (context, session, view) => _SalesTotalsContents(
        period: _period,
        scope: _scope,
        // Taken from the answer rather than from the selection, so the chip
        // shown selected is always the filter the figure was actually read
        // with - including when a stale selection was dropped.
        categoryId: view.totals.query.categoryId,
        categories: view.categories,
        onChoosePeriod: _choosePeriod,
        onChooseScope: _chooseScope,
        onChooseCategory: _chooseCategory,
        onRetry: _retry,
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
    required this.scope,
    required this.categoryId,
    required this.categories,
    required this.onChoosePeriod,
    required this.onChooseScope,
    required this.onChooseCategory,
    required this.onRetry,
    this.totals,
    this.failureMessage,
  });

  final TenantSalesPeriod period;
  final TenantSalesScope scope;
  final String? categoryId;
  final _CategoryOptions categories;
  final ValueChanged<TenantSalesPeriod> onChoosePeriod;
  final ValueChanged<TenantSalesScope> onChooseScope;
  final ValueChanged<String?> onChooseCategory;
  final VoidCallback onRetry;
  final TenantSalesTotals? totals;
  final String? failureMessage;

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('sales-totals'),
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Sales totals',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 4),
      const Text(
        'The server adds these up from the sales it holds right now, so a sale '
        'still waiting on a device is not in them. They are not the reconciled '
        'figures the daily summary reports.',
      ),
      const SizedBox(height: 16),
      // Chips rather than a segmented button: four periods do not fit across a
      // phone, and a chooser that overflows is a chooser that cannot be used.
      Wrap(
        key: const ValueKey('sales-totals-period'),
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final option in TenantSalesPeriod.values)
            ChoiceChip(
              key: ValueKey('sales-totals-period-${option.name}'),
              label: Text(option.label),
              selected: option == period,
              onSelected: (_) => onChoosePeriod(option),
            ),
        ],
      ),
      const SizedBox(height: 12),
      Wrap(
        key: const ValueKey('sales-totals-scope'),
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final option in TenantSalesScope.values)
            ChoiceChip(
              key: ValueKey('sales-totals-scope-${option.name}'),
              label: Text(option.label),
              selected: option == scope,
              onSelected: (_) => onChooseScope(option),
            ),
        ],
      ),
      if (!categories.readable) ...[
        const SizedBox(height: 12),
        const Text(
          key: ValueKey('sales-totals-categories-unavailable'),
          'The category list could not be read, so only the whole-catalog '
          'total is available.',
        ),
      ] else if (categories.items.isNotEmpty) ...[
        const SizedBox(height: 12),
        Wrap(
          key: const ValueKey('sales-totals-category'),
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              key: const ValueKey('sales-totals-category-all'),
              label: const Text('All categories'),
              selected: categoryId == null,
              onSelected: (_) => onChooseCategory(null),
            ),
            for (final category in categories.items)
              ChoiceChip(
                key: ValueKey('sales-totals-category-${category.id}'),
                label: Text(category.name),
                selected: category.id == categoryId,
                onSelected: (_) => onChooseCategory(category.id),
              ),
          ],
        ),
      ],
      const SizedBox(height: 20),
      if (totals case final answer?) ...[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  key: const ValueKey('sales-totals-range'),
                  _range(answer.query),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  key: const ValueKey('sales-totals-amount'),
                  'Sales: ${answer.sales.toStringAsFixed(2)} over '
                  '${answer.transactions} '
                  '${answer.transactions == 1 ? 'sale' : 'sales'}',
                ),
                // A category total is a different figure, not a smaller one of
                // the same kind: the server sums the matching lines and leaves
                // the rest of each sale out. Showing it under the same label as
                // a whole-business total would be lying by omission.
                if (answer.query.isCategoryFiltered) ...[
                  const SizedBox(height: 8),
                  Text(
                    key: const ValueKey('sales-totals-category-basis'),
                    'This adds up only the lines in this category, not the '
                    'whole of each sale. '
                    '${answer.scannedTransactions - answer.transactions} of '
                    'the ${answer.scannedTransactions} sales read held nothing '
                    'in it.',
                  ),
                ],
                if (!answer.hasCompleteCostData) ...[
                  const SizedBox(height: 8),
                  Text(
                    key: const ValueKey('sales-totals-cost'),
                    '${answer.incompleteCostLineCount} sale lines have no cost '
                    'recorded, so no profit figure is shown.',
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          key: const ValueKey('sales-totals-refresh'),
          onPressed: onRetry,
          child: const Text('Read again'),
        ),
      ],
      if (failureMessage case final message?) ...[
        Text(key: const ValueKey('sales-totals-failure'), message),
        const SizedBox(height: 12),
        OutlinedButton(
          key: const ValueKey('sales-totals-retry'),
          onPressed: onRetry,
          child: const Text('Try again'),
        ),
      ],
    ],
  );

  /// Names the exact days, whose sales were counted, and which category, so a
  /// figure is never shown without the question it answers.
  String _range(TenantSalesTotalsQuery query) {
    final parts = <String>[
      query.startDate == query.endDate
          ? query.endDate
          : '${query.startDate} to ${query.endDate}',
      if (query.scope == TenantSalesScope.mine) 'your sales only',
      // The name comes from the same canonical list the filter was chosen from;
      // an ID with no name is not shown as a label of its own.
      if (query.categoryId case final id?)
        categories.nameOf(id) ?? 'one category',
    ];
    return parts.join(' • ');
  }
}
