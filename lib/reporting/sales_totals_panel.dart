import 'package:flutter/material.dart';

import '../tenancy/tenant_catalog.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../tenancy/tenant_staff_directory.dart';
import '../tenancy/tenant_staff_names.dart';
import 'reporting_currency.dart';
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

/// The colleagues one session may total separately, and their display names.
///
/// A member who has left the business is deliberately still offered: their
/// sales are still in the period, and hiding them would make the per-member
/// figures fail to add up to the whole-business one.
final class _StaffOptions {
  const _StaffOptions({
    required this.uids,
    required this.names,
    required this.readable,
    required this.truncated,
  });

  const _StaffOptions.unreadable()
    : uids = const <String>[],
      names = const <String, String>{},
      readable = false,
      truncated = false;

  final List<String> uids;

  /// Display names by UID. A member with no recorded name is deliberately
  /// absent so the label degrades to the authoritative UID; a staff record also
  /// carries an email and a phone number, and a report label is not the place
  /// to disclose either.
  final Map<String, String> names;

  final bool readable;

  /// Whether the business has more staff than one page offers.
  final bool truncated;

  bool contains(String uid) => uids.contains(uid);
}

/// One period's totals with the choosers and the code they are labelled with.
final class _SalesTotalsView {
  const _SalesTotalsView({
    required this.totals,
    required this.categories,
    required this.staff,
    required this.currency,
  });

  final TenantSalesTotals totals;
  final _CategoryOptions categories;
  final _StaffOptions staff;
  final TenantReportingCurrency currency;
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

final class _TenantSalesTotalsPanelState
    extends State<TenantSalesTotalsPanel> {
  late TenantSalesPeriod _period = widget.period;
  String? _soldById;
  String? _categoryId;
  int _generation = 0;

  String? _loaderKey;
  TenantGuardedLoader<_SalesTotalsView>? _loader;

  /// The category list, staff list, and currency for one session, so none of
  /// them can label - or filter - another business's figures. All three are
  /// cached because the filters change often and none of them depends on the
  /// period, the member, or the category.
  _CategoryOptions? _categories;
  _StaffOptions? _staff;
  TenantReportingCurrency? _currency;
  String? _sessionCacheKey;

  static String _sessionKey(TenantSession session) =>
      '${session.uid}:${session.tenantId}:${session.epoch}';

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

  /// Reads this session's categories, colleagues, and currency once, and never
  /// fails the route with any of them.
  ///
  /// The figure a manager came for depends on none of the three, so an
  /// unreadable one removes that affordance and says so rather than replacing
  /// the total with an error.
  Future<void> _loadSessionContext(TenantSession session) async {
    final key = _sessionKey(session);
    if (key == _sessionCacheKey &&
        _categories != null &&
        _staff != null &&
        _currency != null) {
      return;
    }
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
    final staff = await _readStaff(session);
    final currency = await TenantReportingCurrency.read(
      session: session,
      reader: widget.reader,
    );
    _sessionCacheKey = key;
    _categories = options;
    _staff = staff;
    _currency = currency;
  }

  /// Reads one bounded page of this business's canonical staff.
  ///
  /// Only management may read the whole roster, and only management reaches this
  /// route, so the two agree. A page that cannot be read leaves "everyone" and
  /// "only mine" working, because both are answerable from the session alone.
  Future<_StaffOptions> _readStaff(TenantSession session) async {
    try {
      final page = await TenantStaffDirectoryRepository(
        session: session,
        reader: widget.reader,
      ).loadPage(pageSize: widget.staffPageSize);
      return _StaffOptions(
        uids: <String>[for (final member in page.items) member.uid],
        names: <String, String>{
          for (final member in page.items)
            if (member.name case final name?) member.uid: name,
        },
        readable: true,
        truncated: page.hasMore,
      );
    } on TenantScopeViolation {
      rethrow;
    } catch (_) {
      return const _StaffOptions.unreadable();
    }
  }

  /// One loader per guard key, so a closure rebuilt every frame cannot spend
  /// another callable invocation on an unrelated `setState`.
  TenantGuardedLoader<_SalesTotalsView> _loaderFor(String key) {
    if (key == _loaderKey && _loader != null) return _loader!;
    _loaderKey = key;
    final period = _period;
    final chosenMember = _soldById;
    final chosenCategory = _categoryId;
    return _loader = (session) async {
      await _loadSessionContext(session);
      final categories = _categories!;
      final staff = _staff!;
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
      // The same rule for a member, with one addition: the signed-in member is
      // always answerable from the session itself, so "only mine" survives a
      // directory this role could not read.
      final soldById =
          chosenMember != null &&
              (chosenMember == gateway.selfUid || staff.contains(chosenMember))
          ? chosenMember
          : null;
      return _SalesTotalsView(
        totals: await gateway.load(
          gateway.createQuery(
            period: period,
            soldById: soldById,
            categoryId: categoryId,
          ),
        ),
        categories: categories,
        staff: staff,
        currency: _currency!,
      );
    };
  }

  @override
  Widget build(BuildContext context) {
    final guardKey =
        '${_period.name}:${_soldById ?? '-'}:${_categoryId ?? '-'}:'
        '$_generation';
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
        soldById: _soldById,
        selfUid: TenantSessionScope.of(context).session?.uid,
        staff: _staff ?? const _StaffOptions.unreadable(),
        categoryId: _categoryId,
        categories: _categories ?? const _CategoryOptions.unreadable(),
        currency: _currency ?? TenantReportingCurrency.unknown,
        onChoosePeriod: _choosePeriod,
        onChooseMember: _chooseMember,
        onChooseCategory: _chooseCategory,
        onRetry: _retry,
        failureMessage: _failureMessage(error),
      ),
      builder: (context, session, view) => _SalesTotalsContents(
        period: _period,
        // Taken from the answer rather than from the selection, so the chips
        // shown selected are always the filters the figure was actually read
        // with - including when a stale selection was dropped.
        soldById: view.totals.query.soldById,
        selfUid: session.uid,
        staff: view.staff,
        categoryId: view.totals.query.categoryId,
        categories: view.categories,
        currency: view.currency,
        onChoosePeriod: _choosePeriod,
        onChooseMember: _chooseMember,
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
    required this.soldById,
    required this.selfUid,
    required this.staff,
    required this.categoryId,
    required this.categories,
    required this.currency,
    required this.onChoosePeriod,
    required this.onChooseMember,
    required this.onChooseCategory,
    required this.onRetry,
    this.totals,
    this.failureMessage,
  });

  final TenantSalesPeriod period;
  final String? soldById;

  /// The signed-in member, so its own chip reads "You" rather than a UID.
  final String? selfUid;

  final _StaffOptions staff;
  final String? categoryId;
  final _CategoryOptions categories;
  final TenantReportingCurrency currency;
  final ValueChanged<TenantSalesPeriod> onChoosePeriod;
  final ValueChanged<String?> onChooseMember;
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
      if (!currency.isKnown) ...[
        const SizedBox(height: 8),
        const Text(
          key: ValueKey('sales-totals-currency-unknown'),
          TenantReportingCurrency.unknownNotice,
        ),
      ],
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
        key: const ValueKey('sales-totals-member'),
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(
            key: const ValueKey('sales-totals-member-all'),
            label: const Text('Whole business'),
            selected: soldById == null,
            onSelected: (_) => onChooseMember(null),
          ),
          // The signed-in member is always offered, directory or not: its UID
          // comes from the session, which no read can make unavailable.
          if (selfUid case final uid?)
            ChoiceChip(
              key: const ValueKey('sales-totals-member-self'),
              label: Text(
                tenantStaffLabel(uid, names: staff.names, selfUid: uid),
              ),
              selected: soldById == uid,
              onSelected: (_) => onChooseMember(uid),
            ),
          for (final uid in staff.uids)
            if (uid != selfUid)
              ChoiceChip(
                key: ValueKey('sales-totals-member-$uid'),
                label: Text(
                  tenantStaffLabel(uid, names: staff.names, selfUid: selfUid),
                ),
                selected: soldById == uid,
                onSelected: (_) => onChooseMember(uid),
              ),
        ],
      ),
      if (!staff.readable) ...[
        const SizedBox(height: 8),
        const Text(
          key: ValueKey('sales-totals-staff-unavailable'),
          'The staff list could not be read, so only your own sales can be '
          'separated out.',
        ),
      ] else if (staff.truncated) ...[
        const SizedBox(height: 8),
        const Text(
          key: ValueKey('sales-totals-staff-truncated'),
          'This business has more members than are listed here.',
        ),
      ],
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
                  'Sales: ${currency.format(answer.sales)} over '
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
          names: staff.names,
          selfUid: selfUid,
        ),
      },
      // The name comes from the same canonical list the filter was chosen from;
      // an ID with no name is not shown as a label of its own.
      if (query.categoryId case final id?)
        categories.nameOf(id) ?? 'one category',
    ].nonNulls;
    return parts.join(' • ');
  }
}
