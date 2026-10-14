import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/bottom_nav.dart';
import '../ui/buttons.dart';
import '../ui/chips.dart';
import '../ui/dialogs.dart';
import '../ui/fields.dart';
import '../ui/money_text.dart';
import '../ui/pagination.dart';
import '../ui/scaffold.dart';
import '../ui/snackbar.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'platform_console.dart';
import 'platform_console_data.dart';
import 'platform_console_widgets.dart';
import 'platform_tenant_console.dart';
import 'tenant_id.dart';
import 'tenant_types.dart';

// ---------------------------------------------------------------------------
// The list.
// ---------------------------------------------------------------------------

final class PlatformBusinessesPage extends StatefulWidget {
  const PlatformBusinessesPage({super.key, required this.filterRequest});

  /// A filter another destination asked for, applied when it changes.
  final ValueListenable<Object?> filterRequest;

  @override
  State<PlatformBusinessesPage> createState() => _PlatformBusinessesPageState();
}

final class _PlatformBusinessesPageState extends State<PlatformBusinessesPage> {
  final _search = TextEditingController();
  PlatformBusinessFilter _filter = PlatformBusinessFilter.all;
  Map<PlatformBusinessFilter, int?>? _counts;
  PlatformPage<PlatformBusinessRow>? _page;

  /// The cursor each visited page started from, so Previous can go back.
  final List<PlatformCursor?> _starts = <PlatformCursor?>[null];
  bool _loading = true;
  bool _failed = false;
  int _epoch = 0;
  String _query = '';

  static const int _pageSize = 8;

  @override
  void initState() {
    super.initState();
    _applyRequest();
    widget.filterRequest.addListener(_applyRequest);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    widget.filterRequest.removeListener(_applyRequest);
    _search.dispose();
    super.dispose();
  }

  void _applyRequest() {
    final requested = widget.filterRequest.value;
    if (requested is! PlatformBusinessFilter || requested == _filter) return;
    _filter = requested;
    if (mounted && _page != null) _reload();
  }

  PlatformConsoleScope get _scope => PlatformConsoleScope.of(context);

  Future<void> _reload() async {
    _starts
      ..clear()
      ..add(null);
    await Future.wait(<Future<void>>[_readCounts(), _load(null, 0)]);
  }

  Future<void> _readCounts() async {
    try {
      final counts = await PlatformBusinessDirectory(
        _scope.source,
        clock: _scope.clock,
      ).counts();
      if (mounted) setState(() => _counts = counts);
    } catch (error, stackTrace) {
      reportPlatformRead(error, stackTrace, 'platform.business_counts_read');
    }
  }

  Future<void> _load(PlatformCursor? after, int firstIndex) async {
    final epoch = ++_epoch;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page =
          await PlatformBusinessDirectory(
            _scope.source,
            clock: _scope.clock,
          ).page(
            filter: _filter,
            search: _query,
            after: after,
            firstIndex: firstIndex,
            pageSize: _pageSize,
          );
      if (!mounted || epoch != _epoch || !_scope.isCurrent()) return;
      setState(() {
        _page = page;
        _loading = false;
      });
    } catch (error, stackTrace) {
      reportPlatformRead(error, stackTrace, 'platform.business_page_read');
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _select(PlatformBusinessFilter? filter) {
    final next = filter ?? PlatformBusinessFilter.all;
    if (next == _filter) return;
    setState(() => _filter = next);
    _starts
      ..clear()
      ..add(null);
    _load(null, 0);
  }

  void _submitSearch(String value) {
    _query = value;
    _starts
      ..clear()
      ..add(null);
    _load(null, 0);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final compact = platformCompact(context);
    final counts = _counts;
    final page = _page;
    final attention = counts?[PlatformBusinessFilter.attention] ?? 0;
    String label(String name, PlatformBusinessFilter filter) =>
        counts?[filter] == null ? name : '$name ${counts![filter]}';
    final inset = AppScaffold.horizontalInset(tokens.spacing);

    final header = <Widget>[
      if (attention > 0 && _filter != PlatformBusinessFilter.attention) ...[
        Callout(
          key: const ValueKey('platform-businesses-attention'),
          status: AppStatus.problem,
          title: attention == 1
              ? 'One business has an open alert.'
              : '${platformPlural(attention, 'business', 'businesses')} have an open alert.',
          message: compact
              ? 'Raised in the last seven days.'
              : 'Raised in the last seven days, and emailed to every platform administrator.',
          action: AppButton(
            label: attention == 1 ? 'Show it' : 'Show the $attention',
            onPressed: () => _select(PlatformBusinessFilter.attention),
          ),
        ),
        SizedBox(height: tokens.spacing.s16),
      ],
      AppTextField(
        key: const ValueKey('platform-businesses-search'),
        label: 'Search businesses',
        dense: true,
        controller: _search,
        placeholder: compact ? 'Search by name' : 'Search by name or slug',
        leading: Icons.search,
        textInputAction: TextInputAction.search,
        onSubmitted: _submitSearch,
      ),
      SizedBox(height: tokens.spacing.s16),
      FilterChipBar<PlatformBusinessFilter>(
        semanticLabel: 'Business status',
        selected: _filter,
        onSelected: _select,
        options: <FilterChipOption<PlatformBusinessFilter>>[
          FilterChipOption(
            value: PlatformBusinessFilter.all,
            label: label('All', PlatformBusinessFilter.all),
          ),
          FilterChipOption(
            value: PlatformBusinessFilter.trading,
            label: label('Trading', PlatformBusinessFilter.trading),
          ),
          FilterChipOption(
            value: PlatformBusinessFilter.suspended,
            label: label('Suspended', PlatformBusinessFilter.suspended),
          ),
          FilterChipOption(
            value: PlatformBusinessFilter.archived,
            label: label('Archived', PlatformBusinessFilter.archived),
          ),
          FilterChipOption(
            value: PlatformBusinessFilter.attention,
            label: label('Needs attention', PlatformBusinessFilter.attention),
          ),
        ],
      ),
      SizedBox(height: tokens.spacing.s16),
    ];

    Widget content;
    if (_failed && page == null) {
      content = ErrorState(
        badgeLabel: 'Not read',
        statement: 'The businesses could not be read.',
        stillTrue: 'No business was changed.',
        actions: <Widget>[
          AppButton(
            label: 'Try again',
            icon: Icons.refresh,
            tier: AppButtonTier.primary,
            onPressed: _reload,
          ),
        ],
      );
    } else if (page == null) {
      content = const LoadingState(message: 'Reading the businesses.');
    } else if (page.items.isEmpty) {
      content = _emptyFor(_filter, _query);
    } else {
      final pageNumber = _starts.length;
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final row in page.items) ...[
            PlatformBusinessListRow(row: row, now: _scope.clock()),
            SizedBox(height: tokens.spacing.s8),
          ],
          SizedBox(height: tokens.spacing.s8),
          Pagination(
            pageNumber: pageNumber,
            range: (
              first: page.firstIndex + 1,
              last: page.firstIndex + page.items.length,
            ),
            loading: _loading ? PaginationDirection.next : null,
            onPrevious: pageNumber > 1 && !_loading
                ? () {
                    _starts.removeLast();
                    _load(_starts.last, page.firstIndex - _pageSize);
                  }
                : null,
            onNext: page.next != null && !_loading
                ? () {
                    _starts.add(page.next);
                    _load(page.next, page.firstIndex + page.items.length);
                  }
                : null,
            endOfList: page.next == null,
          ),
        ],
      );
    }

    return AppScaffold(
      title: 'Businesses',
      contentWidth: AppContentWidth.records,
      automaticallyImplyLeading: false,
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            inset,
            tokens.spacing.s8,
            inset,
            AppBottomNav.clearanceOf(tokens, compact: compact),
          ),
          children: <Widget>[...header, content],
        ),
      ),
    );
  }

  Widget _emptyFor(PlatformBusinessFilter filter, String query) {
    if (query.isNotEmpty) {
      return EmptyState(
        illustration: 'business-search.svg',
        title: 'No business matches “$query”',
        hint: 'Search by the start of a business name.',
        action: AppButton(
          label: 'Clear search',
          onPressed: () {
            _search.clear();
            _submitSearch('');
          },
        ),
      );
    }
    return switch (filter) {
      PlatformBusinessFilter.archived => const EmptyState(
        illustration: 'business-archived.svg',
        title: 'No archived businesses',
        hint: 'Archived businesses appear here.',
      ),
      PlatformBusinessFilter.suspended => const EmptyState(
        illustration: 'business-paused.svg',
        title: 'No suspended businesses',
        hint: 'Active businesses can keep trading.',
      ),
      PlatformBusinessFilter.attention => const EmptyState(
        illustration: 'businesses.svg',
        title: 'Nothing needs attention',
        hint: 'No alert was raised in the last seven days.',
      ),
      _ => const EmptyState(
        illustration: 'businesses.svg',
        title: 'No businesses yet',
        hint: 'New businesses appear here.',
      ),
    };
  }
}

/// One business in the list.
final class PlatformBusinessListRow extends StatelessWidget {
  const PlatformBusinessListRow({
    super.key,
    required this.row,
    required this.now,
  });

  final PlatformBusinessRow row;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final scope = PlatformConsoleScope.of(context);
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final compact = platformCompact(context);
    final business = row.business;
    final owner = row.owner;
    final ownerDisabled = owner?.standing == PlatformPersonStanding.disabled;
    final ownerName = owner?.name ?? 'Owner unknown';

    final change = row.lastChange;
    final (String note, AppStatus? noteStatus) = switch (business.status) {
      _ when row.alert != null => (
        platformAlertNote(row.alert!, ownerDisabled),
        AppStatus.problem,
      ),
      TenantStatus.active => (
        '${business.createdAt == null
            ? 'Created'
            : platformDaysBetween(business.createdAt!, now) == 0
            ? 'Created today, ${platformWhen(business.createdAt!, now)}'
            : 'Created ${platformShortDate(business.createdAt!, now)}'} · ${platformPlural(row.staffCount, 'person', 'people')}',
        null,
      ),
      TenantStatus.suspended => (
        [
          if (change != null)
            'Since ${platformShortDate(change.createdAt, now)}',
          if (change?.reason != null) '“${change!.reason}”',
        ].join(' · '),
        null,
      ),
      TenantStatus.archived => (
        change == null
            ? 'Archived'
            : 'Archived ${platformShortDate(change.createdAt, now)}${row.lastChangeActor == null ? '' : ' by ${row.lastChangeActor}'}',
        null,
      ),
    };

    final subtitle = Text.rich(
      TextSpan(
        children: <InlineSpan>[
          TextSpan(text: compact ? ownerName : 'Owner $ownerName'),
          if (ownerDisabled)
            TextSpan(
              text: ' · disabled',
              style: TextStyle(color: colors.status.problem.fg),
            ),
          if (!compact && owner != null) TextSpan(text: ' · ${owner.email}'),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: tokens.typography.bodyMedium.copyWith(
        color: colors.text.secondary,
      ),
    );

    return PlatformRecordRow(
      key: ValueKey('platform-business-${business.tenantId}'),
      problem: row.alert != null,
      onPressed: () => scope.openBusiness(context, business.tenantId),
      leading: PlatformAvatar(
        label: business.name,
        seed: business.tenantId,
        small: compact,
        muted: business.status == TenantStatus.archived,
      ),
      title: PlatformRowTitle(
        name: business.name,
        after: <Widget>[
          if (!compact)
            Text(
              business.slug,
              style: tokens.typography.monoCaption.copyWith(
                color: colors.text.tertiary,
              ),
            ),
        ],
      ),
      subtitle: subtitle,
      badge: platformBusinessBadge(business.status),
      note: note.isEmpty ? null : note,
      noteStatus: noteStatus,
      actions: <Widget>[
        if (row.alert != null)
          AppButton(
            label: 'View alert',
            size: AppButtonSize.md,
            onPressed: () => scope.select(PlatformDestination.alerts),
          ),
        _BusinessMenu(row: row),
      ],
    );
  }
}

String platformAlertNote(PlatformAlert alert, bool ownerDisabled) =>
    switch (alert.type) {
      PlatformAlertType.ownerUnavailable =>
        'Owner can’t sign in · no other administrator',
      PlatformAlertType.noActiveAdministrator => 'No active administrator',
      PlatformAlertType.reconciliationQuarantined =>
        'Reconciliation stopped retrying',
      PlatformAlertType.unknown => 'An alert is open',
    };

final class _BusinessMenu extends StatelessWidget {
  const _BusinessMenu({required this.row});

  final PlatformBusinessRow row;

  @override
  Widget build(BuildContext context) {
    final scope = PlatformConsoleScope.of(context);
    final business = row.business;
    return MenuAnchor(
      builder: (context, controller, _) => AppIconButton(
        key: ValueKey('platform-business-menu-${business.tenantId}'),
        icon: Icons.more_vert,
        semanticLabel: 'More for ${business.name}',
        bordered: false,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: <Widget>[
        MenuItemButton(
          onPressed: () => scope.openBusiness(context, business.tenantId),
          child: const Text('Open business'),
        ),
        if (business.status != TenantStatus.archived)
          MenuItemButton(
            onPressed: () => showPlatformLifecycleDialog(
              context,
              business: business,
              ownerName: row.owner?.name,
              target: business.status == TenantStatus.active
                  ? TenantStatus.suspended
                  : TenantStatus.active,
            ),
            child: Text(
              business.status == TenantStatus.active ? 'Suspend' : 'Reactivate',
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// One business.
// ---------------------------------------------------------------------------

final class PlatformBusinessPage extends StatefulWidget {
  const PlatformBusinessPage({super.key, required this.tenantId});

  final String tenantId;

  @override
  State<PlatformBusinessPage> createState() => _PlatformBusinessPageState();
}

final class _PlatformBusinessPageState extends State<PlatformBusinessPage> {
  final _loader = GlobalKey<PlatformLoaderState<PlatformBusinessDetail?>>();
  PlatformBusinessDetail? _detail;

  @override
  Widget build(BuildContext context) {
    final scope = PlatformConsoleScope.of(context);
    final tokens = AppTokens.componentOf(context);
    final compact = platformCompact(context);
    final detail = _detail;
    final business = detail?.business;

    Future<void> change(TenantStatus target) async {
      if (business == null) return;
      final changed = await showPlatformLifecycleDialog(
        context,
        business: business,
        ownerName: detail?.owner?.name,
        target: target,
      );
      if (changed) await _loader.currentState?.reload();
    }

    final actions = <Widget>[
      if (business != null &&
          !compact &&
          business.status != TenantStatus.archived)
        business.status == TenantStatus.active
            ? AppButton(
                key: const ValueKey('platform-business-suspend'),
                label: 'Suspend',
                icon: Icons.pause_circle_outline,
                tier: AppButtonTier.destructive,
                onPressed: () => change(TenantStatus.suspended),
              )
            : AppButton(
                key: const ValueKey('platform-business-reactivate'),
                label: 'Reactivate',
                icon: Icons.play_circle_outline,
                tier: AppButtonTier.primary,
                onPressed: () => change(TenantStatus.active),
              ),
      if (business != null && business.status != TenantStatus.archived)
        MenuAnchor(
          builder: (context, controller, _) => AppIconButton(
            key: const ValueKey('platform-business-more'),
            icon: Icons.more_vert,
            semanticLabel: 'More actions',
            bordered: false,
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
          ),
          menuChildren: <Widget>[
            MenuItemButton(
              key: const ValueKey('platform-business-archive'),
              onPressed: () => change(TenantStatus.archived),
              child: const Text('Archive for good'),
            ),
          ],
        ),
      SizedBox(width: tokens.spacing.s8),
    ];

    return AppScaffold(
      title: business?.name ?? 'Business',
      contentWidth: AppContentWidth.records,
      actions: actions,
      body: PlatformLoader<PlatformBusinessDetail?>(
        key: _loader,
        load: () async {
          final loaded = await PlatformBusinessReader(
            scope.source,
            clock: scope.clock,
          ).load(widget.tenantId);
          if (mounted) setState(() => _detail = loaded);
          return loaded;
        },
        isCurrent: scope.isCurrent,
        loadingMessage: 'Reading the business.',
        failure: 'This business could not be read.',
        boundary: 'platform.business_detail_read',
        builder: (context, detail, reload) {
          if (detail == null) {
            return const EmptyState(
              illustration: 'business-search.svg',
              title: 'This business no longer exists',
            );
          }
          return RefreshIndicator(
            onRefresh: reload,
            child: _BusinessDetailBody(detail: detail, onChange: change),
          );
        },
      ),
    );
  }
}

final class _BusinessDetailBody extends StatelessWidget {
  const _BusinessDetailBody({required this.detail, required this.onChange});

  final PlatformBusinessDetail detail;
  final Future<void> Function(TenantStatus target) onChange;

  @override
  Widget build(BuildContext context) {
    final scope = PlatformConsoleScope.of(context);
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final compact = platformCompact(context);
    final now = scope.clock();
    final business = detail.business;
    final inset = AppScaffold.horizontalInset(tokens.spacing);
    final since = detail.history.isEmpty
        ? null
        : detail.history.first.createdAt;

    final facts = PlatformFacts(
      facts: <(String, Widget)>[
        (
          'Status',
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              platformBusinessBadge(business.status),
              if (since != null && !compact) ...[
                SizedBox(width: tokens.spacing.s8),
                Flexible(
                  child: PlatformCaption(
                    'since ${platformShortDate(since, now)}',
                  ),
                ),
              ],
            ],
          ),
        ),
        (
          'Created',
          PlatformFactText(
            business.createdAt == null
                ? 'Unknown'
                : platformLongDate(business.createdAt!),
          ),
        ),
        ('Slug', PlatformFactText(business.slug, mono: true)),
        (
          'Business ID',
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(child: PlatformFactText(business.tenantId, mono: true)),
              AppIconButton(
                icon: Icons.copy_outlined,
                semanticLabel: 'Copy business ID',
                bordered: false,
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: business.tenantId),
                  );
                  if (context.mounted) {
                    showAppSnackBar(
                      context,
                      const AppNotice.confirmed('Business ID copied.'),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );

    final managers = PlatformPanel(
      title: 'Owner & administrators',
      trailing: compact
          ? null
          : PlatformCaption(
              '${detail.administrators.where((m) => m.standing == PlatformStaffStanding.active).length} can manage it',
            ),
      children: <Widget>[
        for (final member in detail.administrators)
          _PersonLine(
            member: member,
            badge: compact ? null : platformStaffBadge(member.standing),
            onPressed: () => scope.openPerson(context, member.uid),
          ),
        if (detail.administrators.isEmpty)
          Text(
            'Nobody holds the owner or administrator role.',
            style: tokens.typography.bodyMedium.copyWith(
              color: colors.status.problem.fg,
            ),
          ),
      ],
    );

    final counts = detail.counts;
    final staff = PlatformPanel(
      title: 'Staff',
      trailing: PlatformCaption(
        platformPlural(counts.total, 'person', 'people'),
      ),
      children: <Widget>[
        Wrap(
          spacing: tokens.spacing.s8,
          runSpacing: tokens.spacing.s8,
          children: <Widget>[
            StatusBadge(
              status: AppStatus.ok,
              label: '${counts.active} active',
              icon: Icons.check_circle_outline,
            ),
            if (counts.invited > 0)
              StatusBadge(
                status: AppStatus.attention,
                label: '${counts.invited} invited',
                icon: Icons.schedule,
              ),
            if (counts.needAttention > 0)
              StatusBadge(
                status: AppStatus.problem,
                label: '${counts.needAttention} need attention',
                icon: Icons.error_outline,
              ),
            if (counts.deactivated > 0)
              StatusBadge(
                status: AppStatus.neutral,
                label: '${counts.deactivated} deactivated',
                icon: Icons.inventory_2_outlined,
              ),
          ],
        ),
        for (final member in detail.staffPreview)
          _PersonLine(
            member: member,
            badge: platformStaffBadge(member.standing),
            onPressed: () => scope.openPerson(context, member.uid),
          ),
      ],
    );

    final history = PlatformPanel(
      title: 'History',
      trailing: compact
          ? null
          : const PlatformCaption('Who changed its status, and why'),
      children: <Widget>[
        PlatformTimeline(
          entries: <PlatformTimelineEntry>[
            for (final event in detail.history)
              platformLifecycleEntry(event, detail.names),
          ],
        ),
      ],
    );

    final audit = PlatformPanel(
      title: 'Business audit log',
      gap: tokens.spacing.s8,
      children: <Widget>[
        if (detail.audit.isEmpty)
          Text(
            'Nothing recorded yet.',
            style: tokens.typography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          )
        else
          Column(
            children: <Widget>[
              for (var index = 0; index < detail.audit.length; index++)
                Builder(
                  builder: (context) {
                    final line = platformAuditLine(
                      context,
                      detail.audit[index],
                      detail.names,
                    );
                    return PlatformLine(
                      first: index == 0,
                      icon: line.icon,
                      sentence: line.sentence,
                      detail: line.detail,
                      time: platformWhen(detail.audit[index].createdAt, now),
                    );
                  },
                ),
            ],
          ),
        const Callout(
          status: AppStatus.info,
          icon: Icons.lock_outline,
          message:
              'Platform administrators read this log, not the business’s sales, stock or reports. A figure here is the one a change recorded.',
        ),
      ],
    );

    final gap = SizedBox(height: tokens.spacing.s16, width: tokens.spacing.s16);
    final columns = compact
        ? <Widget>[
            managers,
            gap,
            history,
            gap,
            audit,
            gap,
            staff,
            if (business.status != TenantStatus.archived) ...[
              gap,
              business.status == TenantStatus.active
                  ? AppButton(
                      key: const ValueKey('platform-business-suspend'),
                      label: 'Suspend ${business.name}',
                      icon: Icons.pause_circle_outline,
                      tier: AppButtonTier.destructive,
                      expand: true,
                      onPressed: () => onChange(TenantStatus.suspended),
                    )
                  : AppButton(
                      key: const ValueKey('platform-business-reactivate'),
                      label: 'Reactivate ${business.name}',
                      icon: Icons.play_circle_outline,
                      tier: AppButtonTier.primary,
                      expand: true,
                      onPressed: () => onChange(TenantStatus.active),
                    ),
            ],
          ]
        : <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(children: <Widget>[managers, gap, staff]),
                ),
                gap,
                Expanded(
                  child: Column(children: <Widget>[history, gap, audit]),
                ),
              ],
            ),
          ];

    return ListView(
      padding: EdgeInsets.fromLTRB(
        inset,
        tokens.spacing.s8,
        inset,
        tokens.spacing.s40,
      ),
      children: <Widget>[
        facts,
        SizedBox(height: tokens.spacing.s24),
        ...columns,
      ],
    );
  }
}

final class _PersonLine extends StatelessWidget {
  const _PersonLine({required this.member, this.badge, this.onPressed});

  final PlatformStaffMember member;
  final Widget? badge;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final compact = platformCompact(context);
    final contact = [
      member.email,
      if (!compact && member.phone != null) member.phone!,
    ].join(' · ');
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(tokens.radius.md),
      child: Row(
        children: <Widget>[
          PlatformAvatar(label: member.name, seed: member.uid, small: true),
          SizedBox(width: tokens.spacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                PlatformRowTitle(
                  name: member.name,
                  after: <Widget>[PlatformPill.role(member.role)],
                ),
                PlatformRowText(contact),
              ],
            ),
          ),
          if (badge != null) ...[SizedBox(width: tokens.spacing.s8), badge!],
        ],
      ),
    );
  }
}

PlatformTimelineEntry platformLifecycleEntry(
  PlatformLifecycleEvent event,
  Map<String, String> names,
) {
  final actor = names[event.actorUid];
  final when = platformStamp(event.createdAt);
  return switch (event.kind) {
    PlatformLifecycleKind.created => PlatformTimelineEntry(
      tone: PlatformTone.neutral,
      icon: Icons.storefront_outlined,
      title: 'Created',
      meta: actor == null ? when : '$when · by $actor',
    ),
    PlatformLifecycleKind.ownerRecovered => PlatformTimelineEntry(
      tone: PlatformTone.privileged,
      icon: Icons.key_outlined,
      title: 'Ownership recovered',
      meta: actor == null ? when : '$when · $actor',
      reason: event.reason,
    ),
    PlatformLifecycleKind.changed => switch (event.to) {
      TenantStatus.suspended => PlatformTimelineEntry(
        tone: PlatformTone.attention,
        icon: Icons.pause_circle_outline,
        title: 'Suspended',
        meta: actor == null ? when : '$when · $actor',
        reason: event.reason,
      ),
      TenantStatus.archived => PlatformTimelineEntry(
        tone: PlatformTone.neutral,
        icon: Icons.inventory_2_outlined,
        title: 'Archived',
        meta: actor == null ? when : '$when · $actor',
        reason: event.reason,
      ),
      _ => PlatformTimelineEntry(
        tone: PlatformTone.ok,
        icon: Icons.check_circle_outline,
        title: 'Reactivated',
        meta: actor == null ? when : '$when · $actor',
        reason: event.reason,
      ),
    },
    PlatformLifecycleKind.unknown => PlatformTimelineEntry(
      tone: PlatformTone.neutral,
      icon: Icons.history,
      title: 'Changed',
      meta: when,
      reason: event.reason,
    ),
  };
}

String _humanize(String value) {
  final words = value.replaceAll('_', ' ').trim();
  return words.isEmpty ? value : words[0].toUpperCase() + words.substring(1);
}

String _money(Object? value) => switch (value) {
  final num amount => 'KES ${moneyText(amount)}',
  _ => '–',
};

/// One business audit record as a sentence, with what can be said about it.
({IconData icon, InlineSpan sentence, String? detail}) platformAuditLine(
  BuildContext context,
  PlatformAuditEntry entry,
  Map<String, String> names,
) {
  final data = entry.data;
  final actor =
      names[entry.actorUid] ??
      (data['actorType'] != null ? 'The platform' : 'Someone');
  final target = names[entry.targetUid] ?? 'a member of staff';
  InlineSpan b(String text) => platformBold(context, text);
  InlineSpan t(String text) => TextSpan(text: text);
  InlineSpan say(List<InlineSpan> parts) => TextSpan(children: parts);
  String? role(Object? value) {
    try {
      return switch (TenantRole.fromWire(value)) {
        TenantRole.owner => 'the owner',
        TenantRole.admin => 'an administrator',
        TenantRole.manager => 'a manager',
        TenantRole.cashier => 'a cashier',
      };
    } on FormatException {
      return null;
    }
  }

  switch (entry.eventType) {
    case 'product_created' || 'product_imported':
      final created = data['created'];
      final name = created is Map ? platformText(created['name']) : null;
      return (
        icon: Icons.add_box_outlined,
        sentence: say(<InlineSpan>[
          b(actor),
          t(entry.eventType == 'product_imported' ? ' imported ' : ' added '),
          b(name ?? 'a product'),
        ]),
        detail: created is Map
            ? 'Price ${_money(created['price'])}${created['cost'] is num ? ' · cost ${_money(created['cost'])}' : ''}'
            : null,
      );
    case 'product_updated':
      final changes = data['changes'] is List
          ? (data['changes']! as List).whereType<Map>().toList()
          : const <Map>[];
      final money = changes
          .where((c) => c['field'] == 'price' || c['field'] == 'cost')
          .map(
            (c) =>
                '${c['field'] == 'price' ? 'Price' : 'Cost'} ${_money(c['previous'])} → ${_money(c['next'])}',
          )
          .toList();
      final renamed = changes
          .where((c) => c['field'] == 'name')
          .map((c) => platformText(c['next']))
          .whereType<String>()
          .firstOrNull;
      final fields = changes
          .map((c) => c['field'])
          .whereType<String>()
          .map((f) => f == 'categoryId' ? 'category' : f)
          .toList();
      return (
        icon: Icons.sell_outlined,
        sentence: say(<InlineSpan>[
          b(actor),
          t(' changed '),
          if (renamed != null) ...<InlineSpan>[
            t('a product to '),
            b(renamed),
          ] else
            t('a product’s ${fields.isEmpty ? 'details' : fields.join(', ')}'),
        ]),
        detail: money.isEmpty ? null : money.join(' · '),
      );
    case 'stock_adjusted':
      final delta = platformInt(data['quantityDelta']);
      return (
        icon: Icons.inventory_2_outlined,
        sentence: say(<InlineSpan>[b(actor), t(' adjusted stock')]),
        detail: [
          if (delta != null) '${delta > 0 ? '+' : '−'}${delta.abs()}',
          if (platformText(data['adjustmentType']) case final type?)
            _humanize(type),
        ].join(' · '),
      );
    case 'shift_summary_amended':
      final variance = platformInt(data['salesVarianceMinor']);
      return (
        icon: Icons.balance_outlined,
        sentence: say(<InlineSpan>[b(actor), t(' amended a shift summary')]),
        detail: variance == null
            ? null
            : 'Sales variance KES ${variance < 0 ? '−' : ''}${moneyTextOfMinor(variance.abs())}',
      );
    case 'sale_tender_recorded' || 'sale_tender_changed':
      final changed = entry.eventType == 'sale_tender_changed';
      return (
        icon: Icons.payments_outlined,
        sentence: say(<InlineSpan>[
          b(actor),
          t(
            changed
                ? ' changed how a sale was paid'
                : ' recorded how a sale was paid',
          ),
        ]),
        detail: changed
            ? '${_humanize('${data['previousTender'] ?? ''}')} → ${_humanize('${data['tender'] ?? ''}')}'
            : _humanize('${data['tender'] ?? ''}'),
      );
    case 'receipt_reprinted':
      return (
        icon: Icons.receipt_long_outlined,
        sentence: say(<InlineSpan>[b(actor), t(' reprinted a receipt')]),
        detail: platformText(data['receiptNumber']),
      );
    case 'supplier_delivery_received':
      final units = platformInt(data['unitCount']);
      final costs = data['costChanges'] is List
          ? (data['costChanges']! as List).length
          : 0;
      return (
        icon: Icons.local_shipping_outlined,
        sentence: say(<InlineSpan>[b(actor), t(' received a delivery')]),
        detail: [
          if (units != null) platformPlural(units, 'unit'),
          if (costs > 0) '${platformPlural(costs, 'cost price')} changed',
        ].join(' · '),
      );
    case 'production_completed':
      final quantity = platformInt(data['quantity']);
      final unit = platformInt(data['unitCostMinor']);
      return (
        icon: Icons.precision_manufacturing_outlined,
        sentence: say(<InlineSpan>[
          b(actor),
          t(' completed a production batch'),
        ]),
        detail: [
          if (quantity != null) '$quantity made',
          if (unit != null) 'unit cost KES ${moneyTextOfMinor(unit)}',
        ].join(' · '),
      );
    case 'staff_invited':
      return (
        icon: Icons.person_add_alt,
        sentence: say(<InlineSpan>[
          b(actor),
          t(' invited '),
          b(target),
          t(' as ${role(data['role']) ?? 'staff'}'),
        ]),
        detail: null,
      );
    case 'staff_invitation_resent':
      return (
        icon: Icons.forward_to_inbox_outlined,
        sentence: say(<InlineSpan>[
          b(actor),
          t(' resent an invitation to '),
          b(target),
        ]),
        detail: null,
      );
    case 'tenant_invitation_accepted' || 'visible_tenant_invitation_accepted':
      return (
        icon: Icons.how_to_reg_outlined,
        sentence: say(<InlineSpan>[b(target), t(' accepted an invitation')]),
        detail: null,
      );
    case 'staff_status_set':
      final active = data['status'] == 'active';
      return (
        icon: active ? Icons.how_to_reg_outlined : Icons.person_off_outlined,
        sentence: say(<InlineSpan>[
          b(actor),
          t(active ? ' reactivated ' : ' deactivated '),
          b(target),
        ]),
        detail: null,
      );
    case 'staff_updated':
      return (
        icon: Icons.manage_accounts_outlined,
        sentence: say(<InlineSpan>[
          b(actor),
          t(' made '),
          b(target),
          t(' ${role(data['role']) ?? 'a member of staff'}'),
        ]),
        detail: null,
      );
    case 'tenant_lifecycle_changed':
      return (
        icon: Icons.storefront_outlined,
        sentence: say(<InlineSpan>[
          t('The platform '),
          t(switch (data['toStatus']) {
            'suspended' => 'suspended the business',
            'archived' => 'archived the business',
            _ => 'reactivated the business',
          }),
        ]),
        detail: null,
      );
    case 'tenant_requested':
      return (
        icon: Icons.storefront_outlined,
        sentence: say(<InlineSpan>[b(actor), t(' created the business')]),
        detail: null,
      );
    default:
      return (
        icon: Icons.history,
        sentence: say(<InlineSpan>[
          b(actor),
          t(' · ${_humanize(entry.eventType)}'),
        ]),
        detail: null,
      );
  }
}

// ---------------------------------------------------------------------------
// Suspend, reactivate, archive.
// ---------------------------------------------------------------------------

/// Opens the dialog that moves [business] to [target]. True when it moved.
Future<bool> showPlatformLifecycleDialog(
  BuildContext context, {
  required PlatformBusiness business,
  required TenantStatus target,
  String? ownerName,
}) async {
  final scope = PlatformConsoleScope.of(context);
  final changed = await showAppDialog<bool>(
    context,
    builder: (_) => PlatformLifecycleDialog(
      scope: scope,
      business: business,
      target: target,
      ownerName: ownerName,
    ),
  );
  if (changed == true && context.mounted) {
    showAppSnackBar(
      context,
      AppNotice.confirmed(switch (target) {
        TenantStatus.suspended => '${business.name} is suspended.',
        TenantStatus.archived => '${business.name} is archived.',
        TenantStatus.active => '${business.name} is trading again.',
      }),
    );
  }
  return changed == true;
}

final class PlatformLifecycleDialog extends StatefulWidget {
  const PlatformLifecycleDialog({
    super.key,
    required this.scope,
    required this.business,
    required this.target,
    this.ownerName,
  });

  final PlatformConsoleScope scope;
  final PlatformBusiness business;
  final TenantStatus target;
  final String? ownerName;

  @override
  State<PlatformLifecycleDialog> createState() =>
      _PlatformLifecycleDialogState();
}

final class _PlatformLifecycleDialogState
    extends State<PlatformLifecycleDialog> {
  final _reason = TextEditingController();
  final _slug = TextEditingController();
  bool _submitting = false;
  String? _reasonError;
  String? _failure;

  /// One request id per reason: a retry after a dropped answer reuses it,
  /// which is what makes trying again safe.
  String? _requestId;
  String? _requestReason;

  @override
  void initState() {
    super.initState();
    _reason.addListener(_changed);
    _slug.addListener(_changed);
  }

  @override
  void dispose() {
    _reason.dispose();
    _slug.dispose();
    super.dispose();
  }

  void _changed() => setState(() => _reasonError = null);

  bool get _reasonRequired => widget.target != TenantStatus.active;

  bool get _slugMatches =>
      widget.target != TenantStatus.archived ||
      _slug.text.trim() == widget.business.slug;

  Future<void> _submit() async {
    if (_submitting) return;
    final raw = _reason.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if ((_reasonRequired || raw.isNotEmpty) &&
        (raw.length < 3 || raw.length > 1000 || platformTextHasControl(raw))) {
      setState(() => _reasonError = 'Give at least 3 characters.');
      return;
    }
    if (!_slugMatches) return;
    if (_requestReason != raw || _requestId == null) {
      _requestId = (widget.scope.requestIdFactory ?? securePlatformRequestId)();
      _requestReason = raw;
    }
    setState(() {
      _submitting = true;
      _failure = null;
    });
    try {
      final response = await widget.scope.lifecycleCallable
          .call(<String, Object?>{
            'tenantId': widget.business.tenantId,
            'status': widget.target.wireValue,
            if (raw.isNotEmpty) 'reason': raw,
            'requestId': _requestId,
          });
      if (response is! Map ||
          response['tenantId'] != widget.business.tenantId ||
          response['status'] != widget.target.wireValue) {
        throw const FormatException('setTenantLifecycle answered elsewhere.');
      }
      if (!mounted || !widget.scope.isCurrent()) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _failure = platformLifecycleFailure(error, widget.target);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final name = widget.business.name;
    final title = switch (widget.target) {
      TenantStatus.suspended => 'Suspend $name?',
      TenantStatus.archived => 'Archive $name for good?',
      TenantStatus.active => 'Reactivate $name?',
    };
    final consequence = switch (widget.target) {
      TenantStatus.suspended =>
        'Nobody at $name can open it, owner included, until it is reactivated. Every record is kept.',
      TenantStatus.archived => null,
      TenantStatus.active =>
        'Everyone at $name can open it again, with every record as it was.',
    };
    final confirm = switch (widget.target) {
      TenantStatus.suspended => 'Suspend',
      TenantStatus.archived => 'Archive',
      TenantStatus.active => 'Reactivate',
    };
    final slugEntered = _slug.text.trim();
    return AppDialog(
      title: title,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_failure != null) ...[
            Callout(
              key: const ValueKey('platform-lifecycle-dialog-failure'),
              status: AppStatus.problem,
              message: _failure!,
            ),
            SizedBox(height: tokens.spacing.s16),
          ] else if (consequence != null) ...[
            Text(
              consequence,
              style: tokens.typography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
            SizedBox(height: tokens.spacing.s16),
          ],
          if (widget.target == TenantStatus.archived) ...[
            Callout(
              status: AppStatus.problem,
              icon: Icons.warning_amber_outlined,
              title: 'This cannot be undone.',
              message:
                  'An archived business can never trade or be opened again. Its records are kept${widget.ownerName == null ? '' : ', and ${widget.ownerName} can create another business'}.',
            ),
            SizedBox(height: tokens.spacing.s16),
            AppTextField(
              key: const ValueKey('platform-lifecycle-dialog-slug'),
              label: 'Type the slug to confirm',
              controller: _slug,
              enabled: !_submitting,
              autocorrect: false,
              enableSuggestions: false,
              error: slugEntered.isNotEmpty && !_slugMatches
                  ? 'Doesn’t match ${widget.business.slug}.'
                  : null,
            ),
            SizedBox(height: tokens.spacing.s16),
          ],
          AppTextField(
            key: const ValueKey('platform-lifecycle-dialog-reason'),
            label: _reasonRequired ? 'Reason' : 'Reason (optional)',
            controller: _reason,
            enabled: !_submitting,
            minLines: 3,
            maxLines: 4,
            maxLength: 1000,
            placeholder: switch (widget.target) {
              TenantStatus.suspended => 'Why it is being suspended',
              TenantStatus.archived => 'Why it is being closed for good',
              TenantStatus.active => 'Why it can trade again',
            },
            helper: 'Recorded in Activity and the business history.',
            error: _reasonError,
          ),
        ],
      ),
      actions: <Widget>[
        AppButton(
          key: const ValueKey('platform-lifecycle-dialog-cancel'),
          label: 'Cancel',
          tier: AppButtonTier.tertiary,
          onPressed: _submitting
              ? null
              : () => Navigator.of(context).pop(false),
        ),
        AppButton(
          key: const ValueKey('platform-lifecycle-dialog-confirm'),
          label: _failure == null ? confirm : 'Try again',
          icon: _failure == null ? null : Icons.refresh,
          tier: widget.target == TenantStatus.active
              ? AppButtonTier.primary
              : AppButtonTier.destructive,
          loading: _submitting,
          onPressed:
              (_reasonRequired && _reason.text.trim().isEmpty) || !_slugMatches
              ? null
              : _submit,
        ),
      ],
    );
  }
}

String platformLifecycleFailure(Object error, TenantStatus target) {
  final verb = switch (target) {
    TenantStatus.suspended => 'suspended',
    TenantStatus.archived => 'archived',
    TenantStatus.active => 'reactivated',
  };
  if (error is PlatformTenantCallableException) {
    return switch (error.code) {
      'resource-exhausted' =>
        'The owner already has as many trading businesses as the limit allows.',
      'failed-precondition' =>
        'This business changed while you were looking. Nothing was $verb.',
      'not-found' => 'This business no longer exists.',
      'permission-denied' => 'Platform access is no longer available.',
      _ =>
        'It was not $verb: the request did not reach the platform. Trying again is safe; it cannot happen twice.',
    };
  }
  return 'It was not $verb: the request did not reach the platform. Trying again is safe; it cannot happen twice.';
}

/// For a test: whether a string is a tenant id the console would open.
bool platformIsBusinessId(String value) {
  try {
    validateTenantId(value);
    return true;
  } on ArgumentError {
    return false;
  }
}
