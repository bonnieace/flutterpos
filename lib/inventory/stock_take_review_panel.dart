/// Counts waiting to be looked at, and the act of accepting one.
///
/// **This is the half of stock take where stock actually moves**, which is why
/// it is owner/admin/manager and the counting screen is everybody. A count is an
/// observation until somebody with the standing to move a quantity decides what
/// it means; that decision is the *Accept* button here, and it writes the same
/// ledger entries `adjustStock` writes.
///
/// **Only the differing lines are listed.** A count of four hundred products
/// where six disagree is a report about six products. How many agreed is stated
/// on the count itself, so nothing is hidden by leaving the rest out.
library;

import 'package:flutter/material.dart';

import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../tenancy/tenant_staff_names.dart';
import '../ui/buttons.dart';
import '../ui/dialogs.dart';
import '../ui/record_list.dart';
import '../ui/routes.dart';
import '../ui/scaffold.dart';
import '../ui/snackbar.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'stock_take_card.dart';
import 'stock_take_review.dart';

/// The reading route for this business's counts.
final class TenantStockTakeReviewScreen extends StatelessWidget {
  const TenantStockTakeReviewScreen({
    super.key,
    required this.reader,
    this.applyCallable,
    this.onApplied,
    this.countRoute,
  });

  final TenantDataReader reader;

  /// Absent in a build with no callable wired, which renders read-only.
  final ApplyStockTakeCallable? applyCallable;
  final VoidCallback? onApplied;

  /// The counting screen, started from here.
  ///
  /// **The act, on the page that holds its record.** Taking a count and reading
  /// what counts said were two tiles on the home menu differing by one letter;
  /// this is the act, put where somebody who has just read a count goes looking
  /// for it. Absent leaves the button off, which is what a role that may read
  /// counts but not take one would get - there is no such role today, and the
  /// screen should not assume there never will be.
  final WidgetBuilder? countRoute;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Stock counts',
    subtitle: 'What was counted, and how it differed from the books.',
    contentWidth: AppContentWidth.records,
    primaryAction: countRoute == null
        ? null
        : Builder(
            builder: (context) => AppButton(
              key: const ValueKey('stock-take-review-count'),
              label: 'Count stock',
              tier: AppButtonTier.primary,
              onPressed: () {
                final controller = TenantSessionScope.of(context);
                Navigator.of(context).push(
                  AppPageRoute<void>(
                    builder: (routeContext) => TenantSessionScope(
                      controller: controller,
                      child: countRoute!(routeContext),
                    ),
                  ),
                );
              },
            ),
          ),
    body: TenantStockTakeReviewPanel(
      reader: reader,
      applyCallable: applyCallable,
      onApplied: onApplied,
    ),
  );
}

final class TenantStockTakeReviewPanel extends StatefulWidget {
  const TenantStockTakeReviewPanel({
    super.key,
    required this.reader,
    this.applyCallable,
    this.onApplied,
    this.pageSize = TenantStockTakeReviewRepository.defaultPageSize,
  });

  final TenantDataReader reader;
  final ApplyStockTakeCallable? applyCallable;
  final VoidCallback? onApplied;
  final int pageSize;

  @override
  State<TenantStockTakeReviewPanel> createState() =>
      _TenantStockTakeReviewPanelState();
}

class _TenantStockTakeReviewPanelState
    extends State<TenantStockTakeReviewPanel>
    with RereadOnReturn<TenantStockTakeReviewPanel> {
  /// **Handing a count in left this list showing "No counts yet".** *Count
  /// stock* is pushed from the screen above this panel, which cannot reach
  /// [_generation], so nothing re-read when it popped - and the count a person
  /// had just handed in was missing from the only list that shows it. Opening
  /// one for review had the same shape and was fixed by hand in [_open]; this
  /// covers both, and anything else pushed from here.
  @override
  void rereadAfterReturn() => setState(() => _generation++);

  int _generation = 0;
  final TenantStaffNameResolvers _staffNames = TenantStaffNameResolvers();

  /// One resolver per session **and per pass**, so the cached pass resolves a
  /// name from this device rather than putting a network read in front of
  /// records it already holds. An unresolved name degrades to the UID.
  TenantStaffNameResolver _resolverFor(
    TenantSession session,
    TenantDocumentReader reader,
  ) => _staffNames.of(session: session, reader: reader);

  @override
  Widget build(BuildContext context) {
    // **Memoised rather than keyed.** Putting the generation in a `ValueKey` on
    // the guard would destroy its `State` and blank the page for the length of
    // every re-read; the guard already notices a changed `load` and re-reads
    // while keeping what it is drawing. `_composeLoaders` in the catalog panel
    // is the same pattern and the reason it exists.
    _composeLoaders('$_generation');
    return TenantRouteGuard<TenantNamedPage<List<TenantStockTakeRecord>>>(
      allowedRoles: TenantStockTakeReviewRepository.allowedRoles,
      load: _loader!,
      loadCached: _loaderCached,
      denied: const ErrorState(
        status: AppStatus.problem,
        badgeLabel: 'Not allowed',
        statement:
            'Only an owner, administrator or manager may read stock counts.',
      ),
      builder: _buildList,
    );
  }

  String? _loaderKey;
  TenantGuardedLoader<TenantNamedPage<List<TenantStockTakeRecord>>>? _loader;
  TenantGuardedLoader<TenantNamedPage<List<TenantStockTakeRecord>>>?
  _loaderCached;

  /// One loader per generation, cached so a `setState` for a busy flag or a
  /// notice does not restart the read.
  void _composeLoaders(String key) {
    if (key == _loaderKey && _loader != null) return;
    _loaderKey = key;
    TenantGuardedLoader<TenantNamedPage<List<TenantStockTakeRecord>>> readWith(
      TenantDataReader reader,
    ) => (session) async {
      final takes = await TenantStockTakeReviewRepository(
        session: session,
        reader: reader,
      ).loadTakes(collectionReader: reader, pageSize: widget.pageSize);
      // **Who counted it, by name.** A count is evidence about a person's
      // work, and a page of raw UIDs is unreadable to the manager the screen
      // exists for. `TenantStaffNameResolver` bounds the reads and degrades an
      // unresolvable UID to itself, so a missing staff record costs a label
      // rather than the row.
      return TenantNamedPage<List<TenantStockTakeRecord>>(
        page: takes,
        names: await _resolverFor(session, reader).resolve(takes.map((take) => take.counterUid)),
      );
    };
    _loader = readWith(widget.reader);
    final cache = widget.reader.cached;
    _loaderCached = cache == null ? null : readWith(cache);
  }

  Widget _buildList(
    BuildContext context,
    TenantSession session,
    TenantNamedPage<List<TenantStockTakeRecord>> named,
  ) {
    final takes = named.page;
    final tokens = AppTokens.componentOf(context);
    if (takes.isEmpty) {
      return const EmptyState(
        key: ValueKey('stock-take-review-empty'),
        title: 'No counts yet',
        hint:
            'A count appears here when somebody hands one in. Set the days and '
            'who counts what in Settings.',
      );
    }
    // **A `ListView`, and the scroll is still the caller's.** It was a
    // `RecordList` inside one, because that component is a bare `Column`; it is
    // now a list of `TenantStockTakeCard`, which is a bare card for the same
    // reason. Without the scroll a third count overflows the viewport instead
    // of scrolling, which is what the device run found.
    return ListView.separated(
      key: const ValueKey('stock-take-review-list'),
      padding: EdgeInsets.all(tokens.spacing.s16),
      itemCount: takes.length,
      separatorBuilder: (context, index) =>
          SizedBox(height: tokens.spacing.s12),
      itemBuilder: (context, index) {
        final take = takes[index];
        return TenantStockTakeCard(
          // The key the record card carried, kept so a test written against
          // this list keeps addressing the same count.
          key: ValueKey<String>('stock-take-${take.id}'),
          take: take,
          counterLabel: tenantStaffLabel(
            take.counterUid,
            names: named.names,
            selfUid: session.uid,
          ),
          onOpen: () => _open(session, take),
        );
      },
    );
  }

  Future<void> _open(TenantSession session, TenantStockTakeRecord take) async {
    final sessions = TenantSessionScope.of(context);
    await Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => TenantSessionScope(
          controller: sessions,
          child: _TenantStockTakeDetailScreen(
            take: take,
            reader: widget.reader,
            applyCallable: widget.applyCallable,
            onApplied: () {
              widget.onApplied?.call();
              if (mounted) setState(() => _generation++);
            },
          ),
        ),
      ),
    );
    if (mounted) setState(() => _generation++);
  }
}

/// One count's differing lines, with the names of the products they name.
final class _TenantStockTakeLines {
  const _TenantStockTakeLines({required this.lines, required this.names});

  final List<TenantStockTakeLineRecord> lines;
  final Map<String, String> names;
}

/// One count, line by line.
final class _TenantStockTakeDetailScreen extends StatefulWidget {
  const _TenantStockTakeDetailScreen({
    required this.take,
    required this.reader,
    this.applyCallable,
    this.onApplied,
  });

  final TenantStockTakeRecord take;
  final TenantDataReader reader;
  final ApplyStockTakeCallable? applyCallable;
  final VoidCallback? onApplied;

  @override
  State<_TenantStockTakeDetailScreen> createState() =>
      _TenantStockTakeDetailScreenState();
}

class _TenantStockTakeDetailScreenState
    extends State<_TenantStockTakeDetailScreen> {
  bool _applying = false;
  bool _applied = false;
  String? _loaderKey;
  TenantGuardedLoader<_TenantStockTakeLines>? _loader;
  TenantGuardedLoader<_TenantStockTakeLines>? _loaderCached;

  @override
  Widget build(BuildContext context) {
    _composeLoaders(widget.take.id);
    return AppScaffold(
      title: 'The count',
      subtitle: widget.take.businessDate,
      contentWidth: AppContentWidth.records,
      body: TenantRouteGuard<_TenantStockTakeLines>(
        allowedRoles: TenantStockTakeReviewRepository.allowedRoles,
        load: _loader!,
        loadCached: _loaderCached,
        builder: _buildLines,
      ),
    );
  }

  /// The lines, and the names of the products they name.
  ///
  /// Read together rather than drawn from the line documents, because a line
  /// carries no name - see `TenantStockTakeProductNames`.
  ///
  /// **Both passes, because the list this was opened from has both.** A count
  /// reached from a cached list is a count this device already holds, and
  /// reading its lines through the live reader alone made tapping one wait for
  /// a network the list in front of it had not needed. Product names follow the
  /// same reader and degrade to the product ID, exactly as they do on the list.
  ///
  /// One loader per count, so a closure rebuilt on `setState` cannot restart
  /// the read underneath the guard.
  void _composeLoaders(String key) {
    if (key == _loaderKey && _loader != null) return;
    _loaderKey = key;
    TenantGuardedLoader<_TenantStockTakeLines> readWith(
      TenantDataReader reader,
    ) => (session) async {
      final lines = await TenantStockTakeReviewRepository(
        session: session,
        reader: reader,
      ).loadVarianceLines(widget.take.id, collectionReader: reader);
      final names = await TenantStockTakeProductNames(
        session: session,
        reader: reader,
      ).resolve(lines.map((line) => line.productId));
      return _TenantStockTakeLines(lines: lines, names: names);
    };
    _loader = readWith(widget.reader);
    final cache = widget.reader.cached;
    _loaderCached = cache == null ? null : readWith(cache);
  }

  Widget _buildLines(
    BuildContext context,
    TenantSession session,
    _TenantStockTakeLines loaded,
  ) {
    final lines = loaded.lines;
    final tokens = AppTokens.componentOf(context);
    // Biggest difference first, which is the order somebody investigating wants
    // and the order Firestore cannot give: it sorts by the stored value, and
    // what matters here is the size of it either way.
    final sorted = lines.toList()
      ..sort(
        (left, right) =>
            (right.variance ?? 0).abs().compareTo((left.variance ?? 0).abs()),
      );
    return ListView(
      padding: EdgeInsets.all(tokens.spacing.s16),
      children: <Widget>[
        if (widget.take.status == TenantStockTakeStatus.submitting)
          Callout(
            key: const ValueKey('stock-take-detail-arriving'),
            status: AppStatus.attention,
            title: 'This count is still arriving',
            message:
                'The device that took it has not finished sending. Accepting it '
                'now would correct only the part that has arrived, so the '
                'server will refuse until the rest lands.',
          )
        else if (_applied ||
            widget.take.status == TenantStockTakeStatus.applied)
          const Callout(
            key: ValueKey('stock-take-detail-applied'),
            status: AppStatus.ok,
            title: 'Accepted',
            message:
                'Every difference below has been written to the stock ledger, '
                'where it can be read against the product it moved.',
          )
        else if (sorted.isEmpty)
          const Callout(
            key: ValueKey('stock-take-detail-agreed'),
            status: AppStatus.ok,
            title: 'Everything counted agreed with the books',
            message: 'There is nothing to correct.',
          ),
        SizedBox(height: tokens.spacing.s16),
        if (sorted.isNotEmpty)
          RecordList(
            identityLabel: 'Product',
            items: <RecordItem>[
              for (final line in sorted) _lineItem(line, loaded.names),
            ],
          ),
        if (sorted.isNotEmpty && !_applied && widget.take.canApply) ...<Widget>[
          SizedBox(height: tokens.spacing.s8),
          AppButton(
            key: const ValueKey('stock-take-accept'),
            label: 'Accept and correct the stock',
            tier: AppButtonTier.primary,
            loading: _applying,
            onPressed: widget.applyCallable == null || _applying
                ? null
                : () => _apply(session, sorted.length),
          ),
        ],
      ],
    );
  }

  RecordItem _lineItem(
    TenantStockTakeLineRecord line,
    Map<String, String> names,
  ) {
    final variance = line.variance;
    return RecordItem(
      id: line.productId,
      recordKey: ValueKey('stock-take-line-${line.productId}'),
      // **The product's name, falling back to its ID.** The ID is the only
      // thing certainly true about a line whose product this business no longer
      // holds, so it is what an unresolved name degrades to rather than a blank.
      title: names[line.productId] ?? line.productId,
      subtitle: line.matched
          ? 'Counted ${line.counted}, books said ${line.expected}'
          : 'Counted ${line.counted}, no such product on the server',
      status: variance == null
          ? const RecordStatus(label: 'Unmatched', status: AppStatus.attention)
          : RecordStatus(
              label: variance > 0 ? '+$variance' : '$variance',
              status: AppStatus.problem,
            ),
      attributes: <RecordAttribute>[
        if (line.movedWhileCounting)
          // The window `seenQuantity` exists for, said plainly: it is the
          // difference between a shortfall and a count taken while the shop was
          // still trading.
          RecordAttribute(
            label: 'On the device',
            value: '${line.seenQuantity} when counted',
          ),
        if (line.isApplied)
          const RecordAttribute(label: 'Corrected', value: 'Yes'),
      ],
    );
  }

  Future<void> _apply(TenantSession session, int differing) async {
    final callable = widget.applyCallable;
    if (callable == null || _applying) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Accept this count?',
      consequence:
          'This writes $differing ${differing == 1 ? 'correction' : 'corrections'} '
          'to the stock ledger, moving ${widget.take.absoluteVarianceUnits} '
          'units in total.',
      // §8 rule 6, and the sentence that stops somebody reading the result as a
      // bug. Sales since the count are real movements of their own.
      stillTrue:
          'Each correction is the difference the count found, not the figure it '
          'counted. Anything sold since then stays sold.',
      // One word, because the longer label was truncated to "Accept the c..."
      // on a phone - and `ConfirmDialog`'s title already asks the question.
      confirmLabel: 'Accept',
      cancelLabel: 'Not yet',
      // **Chosen, where it used to be the `destructive` default nobody passed.**
      // Accepting a count writes ledger entries; it removes and reverses
      // nothing, which is what that tier is for.
      tier: AppButtonTier.primary,
      confirmKey: const ValueKey('stock-take-accept-confirm'),
    );
    if (!confirmed || !mounted) return;

    setState(() => _applying = true);
    try {
      final outcome = await applyWholeStockTake(
        callable: callable,
        tenantId: session.tenantId,
        takeId: widget.take.id,
      );
      if (!mounted) return;
      setState(() => _applied = true);
      widget.onApplied?.call();
      showAppSnackBar(
        context,
        AppNotice.confirmed(
          'Accepted. ${outcome.applied} '
          '${outcome.applied == 1 ? 'product' : 'products'} corrected.',
        ),
      );
    } on TenantStockTakeApplyException catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, _failureNotice(error.failure));
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  AppNotice _failureNotice(TenantStockTakeApplyFailure failure) =>
      switch (failure) {
        TenantStockTakeApplyFailure.forbidden => const AppNotice.refused(
          'You are not allowed to correct stock in this business, so nothing '
          'was changed.',
        ),
        TenantStockTakeApplyFailure.stillArriving => const AppNotice.refused(
          'This count has not finished arriving, so nothing was changed. Try '
          'again once the rest of it lands.',
        ),
        TenantStockTakeApplyFailure.missing => const AppNotice.refused(
          'This count is no longer on the server, so nothing was changed.',
        ),
        TenantStockTakeApplyFailure.invalidStoredQuantity =>
          const AppNotice.refused(
            'A product in this count holds a quantity that is not a whole '
            'number, so it cannot be corrected. That needs reconciliation '
            'first.',
          ),
        // **Never "nothing happened".** A refusal partway through has already
        // written part of the count, and saying otherwise would send somebody
        // looking for corrections that are already there.
        TenantStockTakeApplyFailure.ambiguous => const AppNotice.unknown(
          'This count has not finished being accepted. Part of it may already '
          'be in the stock ledger. Open it again to see what is left.',
        ),
        TenantStockTakeApplyFailure.refused => const AppNotice.refused(
          'This count was not accepted and nothing was changed.',
        ),
      };
}
