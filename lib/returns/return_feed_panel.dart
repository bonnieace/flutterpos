import 'package:flutter/material.dart';

import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../tenancy/tenant_staff_names.dart';
import '../ui/buttons.dart';
import '../ui/card.dart';
import '../ui/dialogs.dart';
import '../ui/pagination.dart';
import '../ui/routes.dart';
import '../ui/scaffold.dart';
import '../ui/snackbar.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'return_actions.dart';
import 'return_history.dart';
import 'return_journal.dart';
import 'return_verification.dart';

/// Business-wide return history reached from the home screen.
final class TenantReturnFeedScreen extends StatelessWidget {
  const TenantReturnFeedScreen({super.key, required this.reader, this.actions});

  final TenantDataReader reader;
  final TenantReturnActions? actions;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Returns',
    subtitle: 'All returns recorded by this business',
    contentWidth: AppContentWidth.records,
    body: TenantReturnFeedPanel(reader: reader, actions: actions),
  );
}

final class _ReturnFeedView {
  const _ReturnFeedView({required this.page, required this.names});

  final TenantReturnPage page;
  final Map<String, String> names;
}

/// Tenant-scoped, paged history of returns across every sale.
final class TenantReturnFeedPanel extends StatefulWidget {
  const TenantReturnFeedPanel({
    super.key,
    required this.reader,
    this.actions,
    this.pageSize = 20,
    this.requestIdFactory,
  });

  final TenantDataReader reader;
  final TenantReturnActions? actions;
  final int pageSize;
  final String Function()? requestIdFactory;

  @override
  State<TenantReturnFeedPanel> createState() => _TenantReturnFeedPanelState();
}

final class _TenantReturnFeedPanelState extends State<TenantReturnFeedPanel> {
  List<String?> _cursors = <String?>[null];
  int _pageIndex = 0;
  int _generation = 0;
  bool _busy = false;

  /// Reports one write outcome, over the screen rather than inside the page.
  ///
  /// See `showAppSnackBar`: since 2026-09-03 every outcome goes there, and
  /// inline text is left to the one thing it is still right for - a field
  /// saying what is wrong with what was typed into it.
  void _report(AppNotice notice) => showAppSnackBar(context, notice);

  TenantStaffNameResolver? _staffNames;
  String? _staffNamesSessionKey;
  String? _loaderKey;
  TenantGuardedLoader<_ReturnFeedView>? _loader;
  TenantGuardedLoader<_ReturnFeedView>? _loaderCached;

  static String _sessionKey(TenantSession session) =>
      '${session.uid}:${session.tenantId}:${session.epoch}';

  TenantStaffNameResolver _resolverFor(TenantSession session) {
    final key = _sessionKey(session);
    if (key != _staffNamesSessionKey || _staffNames == null) {
      _staffNamesSessionKey = key;
      _staffNames = TenantStaffNameResolver(
        session: session,
        reader: widget.reader,
      );
    }
    return _staffNames!;
  }

  bool _stillCurrent(String capturedKey) {
    if (!mounted) return false;
    final current = TenantSessionScope.of(context).session;
    return current != null && _sessionKey(current) == capturedKey;
  }

  void _next(String? cursor) {
    if (cursor == null) return;
    setState(() {
      _cursors = <String?>[..._cursors.take(_pageIndex + 1), cursor];
      _pageIndex++;
    });
  }

  void _previous() {
    if (_pageIndex == 0) return;
    setState(() => _pageIndex--);
  }

  void _reload() {
    setState(() {
      _cursors = <String?>[null];
      _pageIndex = 0;
      _generation++;
    });
  }

  void _composeLoaders(String key) {
    if (_loaderKey == key && _loader != null) return;
    _loaderKey = key;
    final cursor = _cursors[_pageIndex];
    TenantGuardedLoader<_ReturnFeedView> readWith(TenantDataReader reader) =>
        (session) async {
          final page = await TenantReturnHistoryRepository(
            session: session,
            reader: reader,
          ).loadReturns(pageSize: widget.pageSize, cursor: cursor);
          final names = await _resolverFor(session).resolve(
            page.items.expand(
              (record) => <String>[
                record.createdBy,
                if (record.verification case final verification?)
                  verification.verifiedBy,
              ],
            ),
          );
          return _ReturnFeedView(page: page, names: names);
        };
    _loader = readWith(widget.reader);
    final cache = widget.reader.cached;
    _loaderCached = cache == null ? null : readWith(cache);
  }

  Future<void> _verify(TenantSession session, TenantReturn record) async {
    final callable = widget.actions?.verifyCallable;
    if (callable == null || _busy) return;
    final capturedKey = _sessionKey(session);
    setState(() {
      _busy = true;
    });
    try {
      final gateway = TenantReturnVerificationGateway(
        session: session,
        target: record,
        callable: callable,
        requestIdFactory: widget.requestIdFactory,
      );
      final result = await gateway.submit(gateway.createIntent());
      if (!_stillCurrent(capturedKey)) return;
      _report(
        AppNotice.confirmed(
          'Verified this return and restored ${result.restoredUnits} '
          '${result.restoredUnits == 1 ? 'unit' : 'units'}.',
        ),
      );
      _reload();
    } on TenantReturnVerificationException catch (error) {
      if (!_stillCurrent(capturedKey)) return;
      _report(_verificationFailureNotice(error.failure));
      if (error.mayHaveCommitted) _reload();
    } on FormatException {
      if (!_stillCurrent(capturedKey)) return;
      _report(
        const AppNotice.unknown(
          'The verification response could not be trusted. The returns list '
          'has been reloaded so the server can show what happened.',
        ),
      );
      _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cursor = _cursors[_pageIndex];
    final guardKey = 'return-feed:$_generation:$_pageIndex:$cursor';
    _composeLoaders(guardKey);
    return TenantRouteGuard<_ReturnFeedView>(
      key: ValueKey(guardKey),
      load: _loader!,
      loadCached: _loaderCached,
      denied: const Center(
        key: ValueKey('return-feed-denied'),
        child: Text('Returns are unavailable for this business.'),
      ),
      failure: (context, error) => const Center(
        key: ValueKey('return-feed-failure'),
        child: Text('Returns could not be loaded.'),
      ),
      builder: (context, session, view) => _ReturnFeedContents(
        view: view,
        selfUid: session.uid,
        pageIndex: _pageIndex,
        busy: _busy,
        canVerify:
            widget.actions?.verifyCallable != null &&
            TenantReturnVerificationGateway.canVerifyInSession(session),
        onPrevious: _previous,
        onNext: () => _next(view.page.nextCursor),
        onVerify: (record) => _verify(session, record),
      ),
    );
  }
}

final class _ReturnFeedContents extends StatelessWidget {
  const _ReturnFeedContents({
    required this.view,
    required this.selfUid,
    required this.pageIndex,
    required this.busy,
    required this.canVerify,
    required this.onPrevious,
    required this.onNext,
    required this.onVerify,
  });

  final _ReturnFeedView view;
  final String selfUid;
  final int pageIndex;
  final bool busy;
  final bool canVerify;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<TenantReturn> onVerify;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final page = view.page;
    return ListView(
      key: const ValueKey('return-feed'),
      padding: EdgeInsets.all(tokens.spacing.s20),
      children: <Widget>[
        const Text(
          'Review every recorded return here. Pending returns have not changed '
          'stock; verified returns have restored their recorded units.',
        ),
        if (!canVerify) ...<Widget>[
          SizedBox(height: tokens.spacing.s12),
          const Callout(
            key: ValueKey('return-feed-verification-unavailable'),
            status: AppStatus.info,
            message:
                'Only an owner, administrator, or manager can verify a return '
                'and restore stock.',
          ),
        ],
        if (page.items.isNotEmpty) ...<Widget>[
          SizedBox(height: tokens.spacing.s16),
          Text(
            'On this page: ${page.verified.length} verified, '
            '${page.pending.length} pending.',
            key: const ValueKey('return-feed-counts'),
          ),
        ],
        SizedBox(height: tokens.spacing.s12),
        // **Day headings and cards, not a record table, since 2026-08-26.**
        // The old till grouped its returns under *Today*, *Yesterday* and then
        // a date, and drew each one as a card with a tinted glyph for its
        // standing. A `RecordList` states the same facts in the same order and
        // reads as a ledger: nothing on the row is louder than anything else,
        // so a person scanning for the odd return has to read every one.
        if (page.items.isEmpty)
          const Text(
            key: ValueKey('return-feed-empty'),
            'No returns have been recorded for this business.',
          )
        else
          for (final day in _byDay(page.items)) ...<Widget>[
            Padding(
              padding: EdgeInsets.symmetric(vertical: tokens.spacing.s12),
              child: Text(
                day.label,
                key: ValueKey('return-feed-day-${day.key}'),
                style: tokens.typography.titleMedium.copyWith(
                  color: tokens.colors.action.primary.container,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final record in day.records) ...<Widget>[
              _ReturnCard(
                record: record,
                who: _label(record.createdBy),
                onOpen: () => _openJournal(context, record),
                onVerify: !record.isVerified && canVerify && !busy
                    ? () => _confirmVerification(context, record)
                    : null,
              ),
              SizedBox(height: tokens.spacing.s12),
            ],
          ],
        SizedBox(height: tokens.spacing.s16),
        Pagination(
          pageNumber: pageIndex + 1,
          previousKey: const ValueKey('return-feed-previous'),
          nextKey: const ValueKey('return-feed-next'),
          onPrevious: pageIndex > 0 ? onPrevious : null,
          onNext: page.hasMore ? onNext : null,
        ),
      ],
    );
  }

  /// Opens the journal page for one return.
  ///
  /// **No session travels with it and none is needed.** The page is handed the
  /// record it draws and reads nothing, so it takes a plain route rather than a
  /// `TenantSessionScope` - the guard that produced this row is the guard.
  ///
  /// Verifying from the page comes back here rather than acting there: the
  /// confirmation, the callable and the refresh all already live on this panel,
  /// and a second copy on the journal would be a second place for them to
  /// disagree.
  Future<void> _openJournal(BuildContext context, TenantReturn record) =>
      Navigator.of(context).push<void>(
        AppPageRoute<void>(
          builder: (routeContext) => TenantReturnJournalScreen(
            record: record,
            staffNames: view.names,
            selfUid: selfUid,
            onVerify: !record.isVerified && canVerify && !busy
                ? () {
                    Navigator.of(routeContext).pop();
                    _confirmVerification(context, record);
                  }
                : null,
          ),
        ),
      );

  Future<void> _confirmVerification(
    BuildContext context,
    TenantReturn record,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Restore this stock?',
      consequence:
          'This verifies the return and adds '
          '${record.lines.map(_lineLabel).join(', ')} back to stock.',
      stillTrue: 'It cannot be undone from this app.',
      confirmLabel: 'Verify and restore',
      confirmKey: const ValueKey('return-feed-confirm-verify'),
      cancelKey: const ValueKey('return-feed-cancel-verify'),
    );
    if (confirmed) onVerify(record);
  }

  String _label(String uid) =>
      tenantStaffLabel(uid, names: view.names, selfUid: selfUid);
}

AppNotice _verificationFailureNotice(TenantReturnVerificationFailure failure) =>
    switch (failure) {
      TenantReturnVerificationFailure.forbidden => const AppNotice.refused(
        'Only an owner, administrator, or manager may restore stock.',
      ),
      TenantReturnVerificationFailure.notFound => const AppNotice.refused(
        'This return no longer exists in this business.',
      ),
      TenantReturnVerificationFailure.alreadyVerified =>
        const AppNotice.offline(
          'This return was already verified, so stock was not restored twice.',
        ),
      TenantReturnVerificationFailure.exceedsSale => const AppNotice.refused(
        'This return exceeds what the original sale allows.',
      ),
      TenantReturnVerificationFailure.missingProduct => const AppNotice.refused(
        'A returned product no longer exists, so stock cannot be restored.',
      ),
      TenantReturnVerificationFailure.missingSale => const AppNotice.refused(
        'The original sale is missing, so stock cannot be restored.',
      ),
      TenantReturnVerificationFailure.tooManyVerifications =>
        const AppNotice.refused('This sale needs a manual stock adjustment.'),
      TenantReturnVerificationFailure.refused => const AppNotice.refused(
        'The return was refused and no stock was restored.',
      ),
      TenantReturnVerificationFailure.ambiguous => const AppNotice.unknown(
        'The result is unknown. The returns list has been reloaded.',
      ),
      TenantReturnVerificationFailure.unavailable => const AppNotice.offline(
        'The server could not be reached, so no stock was restored.',
      ),
    };

String _lineLabel(TenantReturnLine line) =>
    '${line.quantity} x ${line.productName ?? line.productId}';

/// One return, as the old till drew one.
///
/// A tinted glyph for its standing, the units it took back, its reason, and
/// who recorded it when. §9 keeps the standing a **word** in the trailing
/// column as well as a colour on the glyph.
final class _ReturnCard extends StatelessWidget {
  const _ReturnCard({
    required this.record,
    required this.who,
    required this.onOpen,
    required this.onVerify,
  });

  final TenantReturn record;
  final String who;
  final VoidCallback onOpen;
  final VoidCallback? onVerify;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final status = record.isVerified
        ? tokens.colors.status.ok
        : tokens.colors.status.attention;
    final recordedAt = record.recordedAt;
    return AppCard(
      key: ValueKey('return-feed-entry-${record.id}'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _StandingTile(record: record, tokens: tokens),
          SizedBox(width: tokens.spacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '${record.returnedUnits} '
                  '${record.returnedUnits == 1 ? 'unit' : 'units'} returned',
                  key: ValueKey('return-feed-subject-${record.id}'),
                  style: tokens.typography.bodyLarge.copyWith(
                    color: tokens.colors.text.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: tokens.spacing.s4),
                // Which sale this came off. The old till's card did not carry
                // it because a single-tenant shop had one till and one book;
                // here it is how a return is traced back.
                Text(
                  record.saleId,
                  key: ValueKey('return-feed-sale-${record.id}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.typography.mono.copyWith(
                    color: tokens.colors.text.tertiary,
                    fontSize: tokens.typography.caption.fontSize,
                  ),
                ),
                SizedBox(height: tokens.spacing.s4),
                Text(
                  record.reason,
                  key: ValueKey('return-feed-reason-${record.id}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.typography.bodyMedium.copyWith(
                    color: tokens.colors.text.secondary,
                  ),
                ),
                SizedBox(height: tokens.spacing.s4),
                Text(
                  recordedAt == null
                      ? 'By $who; awaiting server time'
                      : 'By $who at ${_clock(recordedAt)}',
                  key: ValueKey('return-feed-recorded-${record.id}'),
                  style: tokens.typography.caption.copyWith(
                    color: tokens.colors.text.tertiary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: tokens.spacing.s8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                record.isVerified ? 'VERIFIED' : 'PENDING',
                key: ValueKey('return-feed-status-${record.id}'),
                style: tokens.typography.labelEyebrow.copyWith(
                  color: status.fg,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: tokens.spacing.s8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (onVerify case final verify?) ...<Widget>[
                    AppIconButton(
                      key: ValueKey('return-feed-verify-${record.id}'),
                      icon: Icons.verified_outlined,
                      semanticLabel: 'Verify this return and restore its stock',
                      onPressed: verify,
                    ),
                    SizedBox(width: tokens.spacing.s8),
                  ],
                  AppIconButton(
                    key: ValueKey('return-feed-open-${record.id}'),
                    icon: Icons.visibility_outlined,
                    semanticLabel: 'View this return',
                    onPressed: onOpen,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The old card's tinted glyph square.
final class _StandingTile extends StatelessWidget {
  const _StandingTile({required this.record, required this.tokens});

  final TenantReturn record;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    final status = record.isVerified
        ? tokens.colors.status.ok
        : tokens.colors.status.attention;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: status.bg,
        borderRadius: BorderRadius.circular(tokens.radius.md),
        border: Border.all(color: status.border),
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.s8),
        child: Icon(
          record.isVerified
              ? Icons.assignment_turned_in_outlined
              : Icons.assignment_return_outlined,
          size: tokens.typography.titleLarge.fontSize,
          color: status.fg,
        ),
      ),
    );
  }
}

/// One day's returns, under the heading the old screen gave them.
final class _ReturnDay {
  const _ReturnDay({
    required this.key,
    required this.label,
    required this.records,
  });

  final String key;
  final String label;
  final List<TenantReturn> records;
}

/// Groups a page by the day each return was recorded, newest day first.
///
/// **The reader's own day, not UTC.** A return recorded at 01:00 local belongs
/// to the day the person remembers it on, which is what makes *Today* mean
/// anything. A return the server has not stamped yet cannot be filed under a
/// day at all, so it keeps its own heading rather than being guessed into one.
List<_ReturnDay> _byDay(List<TenantReturn> items) {
  final undated = <TenantReturn>[];
  final days = <DateTime, List<TenantReturn>>{};
  for (final record in items) {
    final recordedAt = record.recordedAt;
    if (recordedAt == null) {
      undated.add(record);
      continue;
    }
    final local = recordedAt.toLocal();
    days
        .putIfAbsent(
          DateTime(local.year, local.month, local.day),
          () => <TenantReturn>[],
        )
        .add(record);
  }
  final ordered = days.keys.toList()..sort((a, b) => b.compareTo(a));
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return <_ReturnDay>[
    for (final day in ordered)
      _ReturnDay(
        key: _dayKey(day),
        label: _dayLabel(day, today),
        records: days[day]!,
      ),
    if (undated.isNotEmpty)
      _ReturnDay(
        key: 'undated',
        label: 'Awaiting server time',
        records: undated,
      ),
  ];
}

String _dayKey(DateTime day) =>
    '${day.year}-${_pad(day.month)}-${_pad(day.day)}';

String _dayLabel(DateTime day, DateTime today) {
  final difference = today.difference(day).inDays;
  if (difference == 0) return 'Today';
  if (difference == 1) return 'Yesterday';
  return _dayKey(day);
}

String _clock(DateTime value) {
  final local = value.toLocal();
  return '${_pad(local.hour)}:${_pad(local.minute)}';
}

String _pad(int part) => part.toString().padLeft(2, '0');
