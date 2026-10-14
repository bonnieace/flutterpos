import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/bottom_nav.dart';
import '../ui/buttons.dart';
import '../ui/chips.dart';
import '../ui/dialogs.dart';
import '../ui/fields.dart';
import '../ui/pagination.dart';
import '../ui/scaffold.dart';
import '../ui/snackbar.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'platform_console.dart';
import 'platform_console_data.dart';
import 'platform_console_widgets.dart';
import 'platform_global_user_status.dart';
import 'tenant_bootstrap.dart';
import 'tenant_types.dart';

// ---------------------------------------------------------------------------
// The directory.
// ---------------------------------------------------------------------------

final class PlatformPeoplePage extends StatefulWidget {
  const PlatformPeoplePage({super.key, required this.filterRequest});
  final ValueListenable<Object?> filterRequest;

  @override
  State<PlatformPeoplePage> createState() => _PlatformPeoplePageState();
}

final class _PlatformPeoplePageState extends State<PlatformPeoplePage> {
  final _search = TextEditingController();
  PlatformPeopleFilter _filter = PlatformPeopleFilter.everyone;
  Map<PlatformPeopleFilter, int?>? _counts;
  PlatformPage<PlatformPersonRow>? _page;
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
    if (requested is! PlatformPeopleFilter || requested == _filter) return;
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
      final counts = await PlatformPeopleDirectory(_scope.source).counts();
      if (mounted) setState(() => _counts = counts);
    } catch (error, stackTrace) {
      reportPlatformRead(error, stackTrace, 'platform.people_counts_read');
    }
  }

  Future<void> _load(PlatformCursor? after, int firstIndex) async {
    final epoch = ++_epoch;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page = await PlatformPeopleDirectory(_scope.source).page(
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
      reportPlatformRead(error, stackTrace, 'platform.people_page_read');
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _select(PlatformPeopleFilter? filter) {
    final next = filter ?? PlatformPeopleFilter.everyone;
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
    String label(String name, PlatformPeopleFilter filter) =>
        counts?[filter] == null ? name : '$name ${counts![filter]}';
    final inset = AppScaffold.horizontalInset(tokens.spacing);

    Widget content;
    if (_failed && page == null) {
      content = ErrorState(
        badgeLabel: 'Not read',
        statement: 'The people could not be read.',
        stillTrue: 'Nobody’s standing was changed.',
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
      content = const LoadingState(message: 'Reading the people.');
    } else if (page.items.isEmpty) {
      content = _query.isNotEmpty
          ? EmptyState(
              illustration: 'people-search.svg',
              title: 'Nobody matches “$_query”',
              hint: 'Search by the start of an email.',
              action: AppButton(
                label: 'Clear search',
                onPressed: () {
                  _search.clear();
                  _submitSearch('');
                },
              ),
            )
          : const EmptyState(
              illustration: 'platform-accounts.svg',
              title: 'No matching accounts',
              hint: 'Try another filter.',
            );
    } else {
      final pageNumber = _starts.length;
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final row in page.items) ...[
            PlatformPersonListRow(row: row),
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
      title: 'People',
      contentWidth: AppContentWidth.records,
      automaticallyImplyLeading: false,
      actions: <Widget>[
        AppIconButton(
          key: const ValueKey('platform-people-email-delivery'),
          icon: Icons.mark_email_unread_outlined,
          semanticLabel: 'Email delivery',
          bordered: false,
          onPressed: () => _scope.openEmailDelivery(context),
        ),
        SizedBox(width: tokens.spacing.s8),
      ],
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            inset,
            tokens.spacing.s8,
            inset,
            AppBottomNav.clearanceOf(tokens, compact: compact),
          ),
          children: <Widget>[
            AppTextField(
              key: const ValueKey('platform-people-search'),
              label: 'Search people',
              dense: true,
              controller: _search,
              placeholder: 'Search by email',
              leading: Icons.search,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.search,
              onSubmitted: _submitSearch,
            ),
            SizedBox(height: tokens.spacing.s16),
            FilterChipBar<PlatformPeopleFilter>(
              semanticLabel: 'Who to show',
              selected: _filter,
              onSelected: _select,
              options: <FilterChipOption<PlatformPeopleFilter>>[
                FilterChipOption(
                  value: PlatformPeopleFilter.everyone,
                  label: label('Everyone', PlatformPeopleFilter.everyone),
                ),
                FilterChipOption(
                  value: PlatformPeopleFilter.owners,
                  label: label('Owners', PlatformPeopleFilter.owners),
                ),
                FilterChipOption(
                  value: PlatformPeopleFilter.staff,
                  label: label('Staff', PlatformPeopleFilter.staff),
                ),
                FilterChipOption(
                  value: PlatformPeopleFilter.noBusiness,
                  label: label('No business', PlatformPeopleFilter.noBusiness),
                ),
                FilterChipOption(
                  value: PlatformPeopleFilter.disabled,
                  label: label('Disabled', PlatformPeopleFilter.disabled),
                ),
                FilterChipOption(
                  value: PlatformPeopleFilter.platform,
                  label: label('Platform', PlatformPeopleFilter.platform),
                ),
              ],
            ),
            SizedBox(height: tokens.spacing.s16),
            content,
          ],
        ),
      ),
    );
  }
}

final class PlatformPersonListRow extends StatelessWidget {
  const PlatformPersonListRow({super.key, required this.row});

  final PlatformPersonRow row;

  @override
  Widget build(BuildContext context) {
    final scope = PlatformConsoleScope.of(context);
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final compact = platformCompact(context);
    final person = row.person;
    final now = scope.clock();
    final you = person.uid == scope.identity.uid;
    final operation = row.operation;
    final disabled = person.standing == PlatformPersonStanding.disabled;

    final tags = <Widget>[
      if (person.isPlatformAdmin) PlatformPill.platformAdministrator,
      for (final membership in row.memberships.take(compact ? 1 : 2)) ...[
        PlatformPill.role(membership.role),
        PlatformRowText(membership.businessName),
      ],
      if (!person.isPlatformAdmin && !row.membershipsKnown)
        PlatformRowText(
          person.ownedTenantCount > 0
              ? 'Owns ${platformPlural(person.ownedTenantCount, 'business', 'businesses')}'
              : person.membershipCount > 0
              ? 'Works at ${platformPlural(person.membershipCount, 'business', 'businesses')}'
              : 'No business yet',
          color: person.membershipCount > 0 || person.ownedTenantCount > 0
              ? null
              : colors.text.tertiary,
        )
      else if (!person.isPlatformAdmin && row.memberships.isEmpty)
        PlatformRowText('No business yet', color: colors.text.tertiary),
    ];

    final (String note, AppStatus? noteStatus) = operation != null
        ? (
            'Attempt ${operation.attemptCount}${operation.nextAttemptAt == null ? '' : ' retries at ${platformWhen(operation.nextAttemptAt!, now)}'}',
            AppStatus.attention,
          )
        : (
            person.isPlatformAdmin
                ? (person.createdAt == null
                      ? 'Platform'
                      : 'Since ${platformShortDate(person.createdAt!, now)}')
                : platformJoined(person.createdAt, now),
            disabled ? AppStatus.problem : null,
          );

    return PlatformRecordRow(
      key: ValueKey('platform-person-${person.uid}'),
      problem: disabled,
      onPressed: () => scope.openPerson(context, person.uid),
      leading: PlatformAvatar(
        label: person.name,
        seed: person.uid,
        small: compact,
        color: person.isPlatformAdmin ? colors.accent.privileged : null,
      ),
      title: PlatformRowTitle(
        name: person.name,
        after: <Widget>[
          if (you) const PlatformYouMarker(),
          if (!compact && person.displayName != null)
            Text(
              person.email,
              style: tokens.typography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
        ],
      ),
      subtitle: Wrap(
        spacing: tokens.spacing.s8,
        runSpacing: tokens.spacing.s4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: tags,
      ),
      badge: platformPersonBadge(person, operation: operation),
      note: note,
      noteStatus: noteStatus,
      actions: <Widget>[
        if (disabled && operation == null)
          AppButton(
            label: 'Reactivate',
            tier: AppButtonTier.primary,
            size: AppButtonSize.md,
            onPressed: () => scope.openPerson(context, person.uid),
          ),
        AppIconButton(
          icon: Icons.chevron_right,
          semanticLabel: 'Open ${person.name}',
          bordered: false,
          onPressed: () => scope.openPerson(context, person.uid),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// One person.
// ---------------------------------------------------------------------------

final class PlatformPersonDetail {
  const PlatformPersonDetail({
    required this.lookup,
    required this.person,
    required this.history,
    required this.operation,
  });

  final PlatformGlobalUserLookupResult lookup;
  final PlatformPerson? person;
  final PlatformActivityPage history;
  final PlatformOperation? operation;

  /// The change that left this person where they are, when there is one.
  PlatformActivityEntry? get lastStatusChange => history.entries
      .where(
        (entry) =>
            entry.kind == PlatformActivityKind.personStatusChanged &&
            !entry.inProgress,
      )
      .firstOrNull;
}

Future<PlatformPersonDetail?> loadPlatformPerson(
  PlatformConsoleScope scope,
  String uid,
) async {
  final results = await Future.wait<Object?>([
    PlatformGlobalUserLookup(
      identity: scope.identity,
      dataSource: scope.globalUserDataSource,
    ).load(uid),
    scope.source.get('users/$uid'),
    PlatformActivityReader(scope.source).page(aboutUid: uid, pageSize: 10),
    loadPlatformOperationsInFlight(scope.source),
  ]);
  final lookup = results[0] as PlatformGlobalUserLookupResult?;
  if (lookup == null) return null;
  final root = results[1] as PlatformRecord?;
  return PlatformPersonDetail(
    lookup: lookup,
    person: root == null ? null : PlatformPerson.fromRecord(root),
    history: results[2]! as PlatformActivityPage,
    operation: (results[3]! as List<PlatformOperation>)
        .where((operation) => operation.uid == uid)
        .firstOrNull,
  );
}

final class PlatformPersonPage extends StatefulWidget {
  const PlatformPersonPage({super.key, required this.uid});

  final String uid;

  @override
  State<PlatformPersonPage> createState() => _PlatformPersonPageState();
}

final class _PlatformPersonPageState extends State<PlatformPersonPage> {
  final _loader = GlobalKey<PlatformLoaderState<PlatformPersonDetail?>>();
  PlatformPersonDetail? _detail;

  Future<void> _change() async {
    final detail = _detail;
    if (detail == null) return;
    final scope = PlatformConsoleScope.of(context);
    final result = await showAppDialog<PlatformGlobalUserStatusResult>(
      context,
      builder: (_) =>
          PlatformPersonStatusDialog(scope: scope, target: detail.lookup),
    );
    if (result == null || !mounted) return;
    if (result.uid == scope.identity.uid) {
      unawaited(scope.onSignOut());
      return;
    }
    showAppSnackBar(
      context,
      AppNotice.confirmed(
        result.targetStatus == PlatformGlobalStatus.disabled
            ? '${detail.person?.name ?? 'The account'} is disabled.'
            : '${detail.person?.name ?? 'The account'} can sign in again.',
      ),
    );
    await _loader.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final scope = PlatformConsoleScope.of(context);
    final tokens = AppTokens.componentOf(context);
    final compact = platformCompact(context);
    final detail = _detail;
    final active = detail?.lookup.user.status == PlatformGlobalStatus.active;
    final name =
        detail?.person?.name ?? detail?.lookup.user.displayName ?? 'Person';
    return AppScaffold(
      title: name,
      contentWidth: AppContentWidth.records,
      actions: <Widget>[
        if (detail != null && !compact && detail.operation == null)
          active
              ? AppButton(
                  key: const ValueKey('platform-person-disable'),
                  label: 'Disable',
                  icon: Icons.person_off_outlined,
                  tier: AppButtonTier.destructive,
                  onPressed: _change,
                )
              : AppButton(
                  key: const ValueKey('platform-person-reactivate'),
                  label: 'Reactivate',
                  icon: Icons.how_to_reg_outlined,
                  tier: AppButtonTier.primary,
                  onPressed: _change,
                ),
        SizedBox(width: tokens.spacing.s16),
      ],
      body: PlatformLoader<PlatformPersonDetail?>(
        key: _loader,
        load: () async {
          final loaded = await loadPlatformPerson(scope, widget.uid);
          if (mounted) setState(() => _detail = loaded);
          return loaded;
        },
        isCurrent: scope.isCurrent,
        loadingMessage: 'Reading this person.',
        failure: 'This person could not be read.',
        boundary: 'platform.person_read',
        builder: (context, detail, reload) {
          if (detail == null) {
            return const EmptyState(
              illustration: 'people-search.svg',
              title: 'No account has this ID',
            );
          }
          return RefreshIndicator(
            onRefresh: reload,
            child: _PersonBody(detail: detail, onChange: _change),
          );
        },
      ),
    );
  }
}

final class _PersonBody extends StatelessWidget {
  const _PersonBody({required this.detail, required this.onChange});

  final PlatformPersonDetail detail;
  final Future<void> Function() onChange;

  @override
  Widget build(BuildContext context) {
    final scope = PlatformConsoleScope.of(context);
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final compact = platformCompact(context);
    final user = detail.lookup.user;
    final person = detail.person;
    final disabled = user.status == PlatformGlobalStatus.disabled;
    final change = detail.lastStatusChange;
    final changedBy = detail.history.people[change?.actorUid];
    final inset = AppScaffold.horizontalInset(tokens.spacing);

    final standing = detail.operation != null
        ? StatusBadge(
            status: AppStatus.attention,
            label: detail.operation!.reactivating
                ? 'Reactivating'
                : 'Disabling',
            icon: Icons.sync,
          )
        : disabled
        ? const StatusBadge(
            status: AppStatus.problem,
            label: 'Disabled',
            icon: Icons.person_off_outlined,
          )
        : const StatusBadge(
            status: AppStatus.ok,
            label: 'Active',
            icon: Icons.check_circle_outline,
          );

    final callout = disabled && change != null
        ? Callout(
            key: const ValueKey('platform-person-disabled'),
            status: AppStatus.problem,
            icon: Icons.person_off_outlined,
            title:
                'Disabled ${platformStamp(change.createdAt)}${changedBy == null ? '' : ' by $changedBy'}.',
            message:
                '${change.reason == null ? '' : '“${change.reason}” '}They are signed out everywhere and cannot sign in.',
          )
        : detail.operation != null
        ? Callout(
            status: AppStatus.attention,
            icon: Icons.sync,
            title: detail.operation!.reactivating
                ? 'Reactivation is part-way through.'
                : 'Disabling is part-way through.',
            message:
                'Attempt ${detail.operation!.attemptCount}${detail.operation!.lastErrorCode == null ? '' : ' stopped on ${detail.operation!.lastErrorCode}'}. It retries on its own; nothing needs redoing.',
          )
        : null;

    final joined = person?.createdAt == null
        ? 'Unknown'
        : '${platformLongDate(person!.createdAt!)}${compact ? '' : (person.signedUp ? ' · signed up' : ' · invited')}';

    final facts = PlatformFacts(
      facts: <(String, Widget)>[
        ('Standing', standing),
        ('Email', PlatformFactText(user.email)),
        ('Joined', PlatformFactText(joined)),
        (
          'User ID',
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(child: PlatformFactText(user.uid, mono: true)),
              AppIconButton(
                icon: Icons.copy_outlined,
                semanticLabel: 'Copy user ID',
                bordered: false,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: user.uid));
                  if (context.mounted) {
                    showAppSnackBar(
                      context,
                      const AppNotice.confirmed('User ID copied.'),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );

    final tenants = detail.lookup.affectedTenants;
    final businesses = PlatformPanel(
      title: 'Businesses',
      trailing: PlatformCaption(platformPlural(tenants.length, 'relationship')),
      children: <Widget>[
        if (tenants.isEmpty)
          Text(
            user.accountType == RootAccountType.platformAdmin
                ? 'A platform administrator belongs to no business.'
                : 'Not part of any business yet.',
            style: tokens.typography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        for (final tenant in tenants)
          _TenantRelationship(tenant: tenant, disabled: disabled),
      ],
    );

    final email = _EmailCheckPanel(email: user.email);

    final history = PlatformPanel(
      title: 'History',
      trailing: PlatformLink(
        label: 'In Activity',
        onPressed: () => scope.select(PlatformDestination.activity),
      ),
      children: <Widget>[
        PlatformTimeline(
          entries: <PlatformTimelineEntry>[
            for (final entry in detail.history.entries)
              if (entry.kind == PlatformActivityKind.personStatusChanged)
                PlatformTimelineEntry(
                  tone: entry.inProgress
                      ? PlatformTone.attention
                      : entry.reactivation == true
                      ? PlatformTone.ok
                      : PlatformTone.problem,
                  icon: entry.reactivation == true
                      ? Icons.how_to_reg_outlined
                      : Icons.person_off_outlined,
                  title: entry.inProgress
                      ? (entry.reactivation == true
                            ? 'Reactivating'
                            : 'Disabling')
                      : (entry.reactivation == true
                            ? 'Reactivated'
                            : 'Disabled'),
                  meta: [
                    platformStamp(entry.createdAt),
                    ?detail.history.people[entry.actorUid],
                    if (entry.attemptCount != null && !entry.inProgress)
                      'done in ${platformPlural(entry.attemptCount!, 'attempt')}',
                    if (entry.affectedTenants != null)
                      '${platformPlural(entry.affectedTenants!, 'business', 'businesses')} checked',
                  ].join(' · '),
                  reason: entry.reason,
                ),
            if (person?.createdAt != null)
              PlatformTimelineEntry(
                tone: PlatformTone.neutral,
                icon: Icons.person_outline,
                title: person!.signedUp ? 'Signed up' : 'Invited',
                meta: platformStamp(person.createdAt!),
              ),
          ],
        ),
      ],
    );

    final gap = SizedBox(height: tokens.spacing.s16, width: tokens.spacing.s16);
    final action = detail.operation != null
        ? null
        : disabled
        ? AppButton(
            key: const ValueKey('platform-person-reactivate'),
            label: 'Reactivate ${person?.name ?? 'this account'}',
            icon: Icons.how_to_reg_outlined,
            tier: AppButtonTier.primary,
            expand: true,
            onPressed: onChange,
          )
        : AppButton(
            key: const ValueKey('platform-person-disable'),
            label: 'Disable ${person?.name ?? 'this account'}',
            icon: Icons.person_off_outlined,
            tier: AppButtonTier.destructive,
            expand: true,
            onPressed: onChange,
          );

    return ListView(
      padding: EdgeInsets.fromLTRB(
        inset,
        tokens.spacing.s8,
        inset,
        tokens.spacing.s40,
      ),
      children: <Widget>[
        if (callout != null) ...[callout, gap],
        facts,
        SizedBox(height: tokens.spacing.s24),
        if (compact) ...[
          businesses,
          gap,
          history,
          gap,
          email,
          if (action != null) ...[gap, action],
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(children: <Widget>[businesses, gap, email]),
              ),
              gap,
              Expanded(child: history),
            ],
          ),
      ],
    );
  }
}

final class _TenantRelationship extends StatelessWidget {
  const _TenantRelationship({required this.tenant, required this.disabled});

  final PlatformAffectedTenantSummary tenant;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final scope = PlatformConsoleScope.of(context);
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final impact = switch (tenant.impact) {
      PlatformAdministrativeImpact.ownerUnavailable =>
        disabled
            ? 'Its owner cannot sign in, and nobody else there is an active administrator.'
            : 'Disabling this account leaves it without an owner who can sign in.',
      PlatformAdministrativeImpact.noActiveAdministrator =>
        disabled
            ? 'No other active administrator.'
            : 'Disabling this account leaves it with no active administrator.',
      PlatformAdministrativeImpact.none =>
        tenant.remainingActiveAdministrators == 0
            ? null
            : '${platformPlural(tenant.remainingActiveAdministrators, 'other active administrator')}.',
    };
    final problem = tenant.impact != PlatformAdministrativeImpact.none;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: problem
              ? colors.status.problem.border
              : colors.surface.cardEdge,
        ),
        borderRadius: BorderRadius.circular(tokens.radius.lg),
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.s16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            PlatformAvatar(
              label: tenant.name,
              seed: tenant.tenantId,
              small: true,
            ),
            SizedBox(width: tokens.spacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  PlatformRowTitle(
                    name: tenant.name,
                    after: <Widget>[
                      if (tenant.targetRole != null)
                        PlatformPill.role(tenant.targetRole!),
                      platformBusinessBadge(tenant.status),
                    ],
                  ),
                  if (impact != null) ...[
                    SizedBox(height: tokens.spacing.s4),
                    Text(
                      impact,
                      style: tokens.typography.bodyMedium.copyWith(
                        color: problem
                            ? colors.status.problem.fg
                            : colors.text.secondary,
                      ),
                    ),
                  ],
                  SizedBox(height: tokens.spacing.s12),
                  AppButton(
                    label: 'Open business',
                    size: AppButtonSize.md,
                    onPressed: () =>
                        scope.openBusiness(context, tenant.tenantId),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Checks one address on a button, never on opening: a lookup is itself
/// recorded in Activity.
final class _EmailCheckPanel extends StatefulWidget {
  const _EmailCheckPanel({required this.email});

  final String email;

  @override
  State<_EmailCheckPanel> createState() => _EmailCheckPanelState();
}

final class _EmailCheckPanelState extends State<_EmailCheckPanel> {
  PlatformSuppressionReview? _review;
  bool _checking = false;
  bool _failed = false;

  Future<void> _check() async {
    final scope = PlatformConsoleScope.of(context);
    setState(() {
      _checking = true;
      _failed = false;
    });
    try {
      final review = await PlatformSuppressionGateway(
        scope.suppressionCallable,
        requestIdFactory: scope.requestIdFactory,
      ).inspect(widget.email);
      if (!mounted) return;
      setState(() {
        _review = review;
        _checking = false;
      });
    } catch (error, stackTrace) {
      reportPlatformRead(error, stackTrace, 'platform.person_email_check');
      if (!mounted) return;
      setState(() {
        _checking = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = PlatformConsoleScope.of(context);
    final tokens = AppTokens.componentOf(context);
    final review = _review;
    final style = tokens.typography.bodyMedium.copyWith(
      color: tokens.colors.text.secondary,
    );
    return PlatformPanel(
      title: 'Email delivery',
      children: <Widget>[
        if (review == null)
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _failed
                      ? 'The check did not reach the platform. Nothing was recorded.'
                      : 'Not checked. Looking an address up is itself recorded in Activity, so it waits to be asked.',
                  style: style,
                ),
              ),
              SizedBox(width: tokens.spacing.s12),
              AppButton(
                key: const ValueKey('platform-person-check-email'),
                label: 'Check delivery',
                icon: Icons.mail_outline,
                size: AppButtonSize.md,
                loading: _checking,
                onPressed: _check,
              ),
            ],
          )
        else
          Row(
            children: <Widget>[
              review.active.isEmpty
                  ? const StatusBadge(
                      status: AppStatus.ok,
                      label: 'Delivering',
                      icon: Icons.mail_outline,
                    )
                  : const StatusBadge(
                      status: AppStatus.problem,
                      label: 'Not delivering',
                      icon: Icons.unsubscribe_outlined,
                    ),
              SizedBox(width: tokens.spacing.s12),
              Expanded(
                child: Text(
                  review.active.isEmpty
                      ? 'No suppression on this address.'
                      : '${platformSuppressionReason(review.active.first.category)}.',
                  style: style,
                ),
              ),
              if (review.active.isNotEmpty)
                AppButton(
                  label: 'Open',
                  size: AppButtonSize.md,
                  onPressed: () =>
                      scope.openEmailDelivery(context, email: widget.email),
                ),
            ],
          ),
      ],
    );
  }
}

/// Disables or reactivates one account, through the gateway the console has
/// always used. Pops with the result when the change completed.
final class PlatformPersonStatusDialog extends StatefulWidget {
  const PlatformPersonStatusDialog({
    super.key,
    required this.scope,
    required this.target,
  });

  final PlatformConsoleScope scope;
  final PlatformGlobalUserLookupResult target;

  @override
  State<PlatformPersonStatusDialog> createState() =>
      _PlatformPersonStatusDialogState();
}

final class _PlatformPersonStatusDialogState
    extends State<PlatformPersonStatusDialog> {
  final _reason = TextEditingController();
  final _confirmation = TextEditingController();
  PlatformGlobalUserStatusIntent? _intent;
  bool _submitting = false;
  String? _failure;
  bool _partial = false;

  bool get _disabling =>
      widget.target.user.status == PlatformGlobalStatus.active;

  @override
  void initState() {
    super.initState();
    _reason.addListener(_changed);
    _confirmation.addListener(_changed);
  }

  @override
  void dispose() {
    _reason.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  bool get _ready {
    final reason = _reason.text.trim();
    return reason.length >= 3 &&
        (!_disabling || _confirmation.text.trim() == widget.target.user.uid);
  }

  Future<void> _submit() async {
    if (_submitting || !_ready) return;
    final gateway = PlatformGlobalUserStatusGateway(
      identity: widget.scope.identity,
      target: widget.target,
      callable: widget.scope.globalUserCallable,
      requestIdFactory: widget.scope.requestIdFactory,
    );
    late final PlatformGlobalUserStatusIntent intent;
    try {
      final reason = normalizeGlobalUserStatusReason(_reason.text);
      final confirmation = _disabling ? _confirmation.text.trim() : null;
      final current = _intent;
      intent =
          current != null &&
              current.reason == reason &&
              current.confirmation == confirmation
          ? current
          : gateway.createIntent(
              action: _disabling
                  ? PlatformGlobalUserAction.disable
                  : PlatformGlobalUserAction.reactivate,
              reason: _reason.text,
              confirmation: _confirmation.text,
            );
      _intent = intent;
    } catch (_) {
      setState(
        () => _failure =
            'Give a reason of at least 3 characters'
            '${_disabling ? ' and the exact user ID' : ''}.',
      );
      return;
    }
    setState(() {
      _submitting = true;
      _failure = null;
      _partial = false;
    });
    try {
      final result = await gateway.submit(intent);
      if (!mounted || !widget.scope.isCurrent()) return;
      if (result.isCompleted) {
        Navigator.of(context).pop(result);
        return;
      }
      setState(() {
        _submitting = false;
        _partial = true;
        _failure = platformGlobalUserPartialFailureText;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _failure = platformGlobalUserStatusSafeError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final user = widget.target.user;
    final name = user.displayName ?? user.email;
    final warnings = widget.target.administrativeWarnings;
    final confirmation = _confirmation.text.trim();
    return AppDialog(
      title: _disabling ? 'Disable $name?' : 'Reactivate $name?',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            _disabling
                ? 'They are signed out everywhere and cannot sign in. Their businesses keep trading.'
                : 'They can sign in again, to every business they still belong to.',
            style: tokens.typography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          if (_disabling && warnings.isNotEmpty) ...[
            SizedBox(height: tokens.spacing.s16),
            Callout(
              key: const ValueKey('platform-person-dialog-impact'),
              status: AppStatus.attention,
              icon: Icons.warning_amber_outlined,
              title: warnings.length > 1
                  ? '${warnings.length} businesses are affected'
                  : warnings.single.impact ==
                        PlatformAdministrativeImpact.ownerUnavailable
                  ? '${warnings.single.name} is left without an owner who can sign in'
                  : '${warnings.single.name} is left with no active administrator',
              message: warnings.length > 1
                  ? '${warnings.map((tenant) => tenant.name).join(', ')}. An alert will be raised for each.'
                  : 'An alert will be raised and emailed to the platform administrators.',
            ),
          ],
          if (_failure != null) ...[
            SizedBox(height: tokens.spacing.s16),
            Callout(
              key: const ValueKey('platform-person-dialog-failure'),
              status: _partial ? AppStatus.attention : AppStatus.problem,
              message: _failure!,
            ),
          ],
          SizedBox(height: tokens.spacing.s16),
          AppTextField(
            key: const ValueKey('platform-person-dialog-reason'),
            label: 'Reason',
            controller: _reason,
            enabled: !_submitting,
            minLines: 3,
            maxLines: 4,
            maxLength: 1000,
            placeholder: _disabling
                ? 'Why they can no longer sign in'
                : 'Why they can sign in again',
            helper: 'Recorded in Activity with your name.',
          ),
          if (_disabling) ...[
            SizedBox(height: tokens.spacing.s16),
            AppTextField(
              key: const ValueKey('platform-person-dialog-confirmation'),
              label: 'Type their user ID to confirm',
              controller: _confirmation,
              enabled: !_submitting,
              autocorrect: false,
              enableSuggestions: false,
              helper: confirmation == user.uid ? 'Matches.' : user.uid,
              error:
                  confirmation.isNotEmpty &&
                      confirmation != user.uid &&
                      confirmation.length >= user.uid.length
                  ? 'Doesn’t match.'
                  : null,
            ),
          ],
        ],
      ),
      actions: <Widget>[
        AppButton(
          key: const ValueKey('platform-person-dialog-cancel'),
          label: 'Cancel',
          tier: AppButtonTier.tertiary,
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
        ),
        AppButton(
          key: const ValueKey('platform-person-dialog-confirm'),
          label: _failure != null && !_partial
              ? 'Try again'
              : _partial
              ? 'Retry now'
              : (_disabling ? 'Disable' : 'Reactivate'),
          tier: _disabling ? AppButtonTier.destructive : AppButtonTier.primary,
          loading: _submitting,
          onPressed: _ready ? _submit : null,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Email delivery.
// ---------------------------------------------------------------------------

String platformSuppressionReason(PlatformSuppressionCategory category) =>
    switch (category) {
      PlatformSuppressionCategory.hardBounce => 'Hard bounce',
      PlatformSuppressionCategory.invalidRecipient => 'Invalid recipient',
      PlatformSuppressionCategory.spamComplaint => 'Spam complaint',
      PlatformSuppressionCategory.providerBlock => 'Blocked by the provider',
    };

String platformSuppressionExplanation(PlatformSuppressionCategory category) =>
    switch (category) {
      PlatformSuppressionCategory.hardBounce => 'The mailbox does not exist',
      PlatformSuppressionCategory.invalidRecipient =>
        'The address cannot receive mail',
      PlatformSuppressionCategory.spamComplaint =>
        'The person marked a message as spam',
      PlatformSuppressionCategory.providerBlock =>
        'The mail provider refuses this address',
    };

final class PlatformEmailDeliveryPage extends StatefulWidget {
  const PlatformEmailDeliveryPage({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<PlatformEmailDeliveryPage> createState() =>
      _PlatformEmailDeliveryPageState();
}

final class _PlatformEmailDeliveryPageState
    extends State<PlatformEmailDeliveryPage> {
  late final _email = TextEditingController(text: widget.initialEmail);
  final _reason = TextEditingController();
  final _evidence = TextEditingController();
  PlatformClearConfirmation _confirmation =
      PlatformClearConfirmation.addressCorrected;
  PlatformSuppressionReview? _review;
  String? _lookedUp;
  bool _busy = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    _reason.addListener(() => setState(() {}));
    _evidence.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _email.dispose();
    _reason.dispose();
    _evidence.dispose();
    super.dispose();
  }

  PlatformSuppressionGateway _gateway() {
    final scope = PlatformConsoleScope.of(context);
    return PlatformSuppressionGateway(
      scope.suppressionCallable,
      requestIdFactory: scope.requestIdFactory,
    );
  }

  Future<void> _lookUp() async {
    final email = normalizePlatformEmail(_email.text);
    if (email == null) {
      setState(() => _failure = 'Enter a whole email address.');
      return;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final review = await _gateway().inspect(email);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _review = review;
        _lookedUp = email;
        _confirmation = review.needsSpamEvidence
            ? PlatformClearConfirmation.spamComplaint
            : PlatformClearConfirmation.addressCorrected;
      });
    } catch (error, stackTrace) {
      reportPlatformRead(error, stackTrace, 'platform.email_lookup');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure =
            'The lookup did not reach the platform. Nothing was recorded.';
      });
    }
  }

  bool get _canClear {
    final review = _review;
    if (review == null || review.active.isEmpty) return false;
    if (_reason.text.trim().isEmpty) return false;
    if (_confirmation == PlatformClearConfirmation.spamComplaint &&
        _evidence.text.trim().length < 8) {
      return false;
    }
    return true;
  }

  Future<void> _clear() async {
    final email = _lookedUp;
    if (email == null || !_canClear) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final review = await _gateway().clear(
        email: email,
        reason: _reason.text,
        confirmation: _confirmation,
        evidenceReference:
            _confirmation == PlatformClearConfirmation.spamComplaint
            ? _evidence.text
            : null,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _review = review;
      });
      _reason.clear();
      _evidence.clear();
      showAppSnackBar(
        context,
        AppNotice.confirmed('$email can receive email again.'),
      );
    } catch (error, stackTrace) {
      reportPlatformRead(error, stackTrace, 'platform.email_clear');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure =
            error is PlatformSuppressionCallableException &&
                error.code == 'failed-precondition'
            ? 'The platform refused it: this suppression needs a different confirmation.'
            : 'It was not cleared: the request did not reach the platform.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final compact = platformCompact(context);
    final review = _review;
    final inset = AppScaffold.horizontalInset(tokens.spacing);
    final body = tokens.typography.bodyLarge.copyWith(
      color: colors.text.secondary,
    );
    final active = review?.active ?? const <PlatformSuppression>[];
    final first = active.isEmpty ? null : active.first;
    final now = PlatformConsoleScope.of(context).clock();

    Widget fact(String label, String value, String detail) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label.toUpperCase(),
          style: tokens.typography.labelEyebrow.copyWith(
            color: colors.text.secondary,
          ),
        ),
        SizedBox(height: tokens.spacing.s8),
        Text(
          value,
          style: tokens.typography.bodyLarge.copyWith(
            color: colors.text.primary,
          ),
        ),
        Text(
          detail,
          style: tokens.typography.caption.copyWith(
            color: colors.text.tertiary,
          ),
        ),
      ],
    );

    final lookUpButton = AppButton(
      key: const ValueKey('platform-email-look-up'),
      label: 'Look up',
      icon: Icons.search,
      tier: AppButtonTier.primary,
      loading: _busy && review == null,
      onPressed: _busy ? null : _lookUp,
    );

    return AppScaffold(
      title: 'Email delivery',
      contentWidth: AppContentWidth.records,
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          inset,
          tokens.spacing.s8,
          inset,
          tokens.spacing.s40,
        ),
        children: <Widget>[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: tokens.layout.reading),
              child: Text(
                'When an address bounces or someone reports spam, the mail provider stops sending to it, and every receipt and invitation to that address is dropped. Look an address up to see why, and clear it once the address is fixed.',
                style: body,
              ),
            ),
          ),
          SizedBox(height: tokens.spacing.s24),
          if (compact) ...[
            AppTextField(
              key: const ValueKey('platform-email-address'),
              label: 'Email address',
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              onSubmitted: (_) => _lookUp(),
            ),
            SizedBox(height: tokens.spacing.s12),
            lookUpButton,
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Expanded(
                  child: AppTextField(
                    key: const ValueKey('platform-email-address'),
                    label: 'Email address',
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    onSubmitted: (_) => _lookUp(),
                  ),
                ),
                SizedBox(width: tokens.spacing.s12),
                lookUpButton,
              ],
            ),
          if (_failure != null) ...[
            SizedBox(height: tokens.spacing.s16),
            Callout(status: AppStatus.problem, message: _failure!),
          ],
          if (review != null) ...[
            SizedBox(height: tokens.spacing.s16),
            if (first == null)
              Callout(
                key: const ValueKey('platform-email-delivering'),
                status: AppStatus.ok,
                icon: Icons.mark_email_read_outlined,
                title: '$_lookedUp is receiving email.',
                message: review.clearedCount > 0
                    ? 'Its suppression is cleared.'
                    : 'No suppression on this address.',
              )
            else
              DecoratedBox(
                key: const ValueKey('platform-email-suppressed'),
                decoration: BoxDecoration(
                  color: colors.surface.raised,
                  border: Border.all(color: colors.surface.cardEdge),
                  borderRadius: BorderRadius.circular(tokens.radius.lg),
                ),
                child: Padding(
                  padding: EdgeInsets.all(
                    compact ? tokens.spacing.s16 : tokens.spacing.s20,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const PlatformToneWell(
                            icon: Icons.unsubscribe_outlined,
                            status: AppStatus.problem,
                          ),
                          SizedBox(width: tokens.spacing.s12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                PlatformRowTitle(
                                  name: '$_lookedUp is not receiving email',
                                ),
                                PlatformRowText(
                                  'The provider marked it a ${platformSuppressionReason(first.category).toLowerCase()}. Nothing has been sent to it since.',
                                ),
                              ],
                            ),
                          ),
                          if (!compact) ...[
                            SizedBox(width: tokens.spacing.s12),
                            const StatusBadge(
                              status: AppStatus.problem,
                              label: 'Not delivering',
                              icon: Icons.unsubscribe_outlined,
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: tokens.spacing.s16),
                      Divider(height: 1, color: colors.surface.cardEdge),
                      SizedBox(height: tokens.spacing.s16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: fact(
                              'Why',
                              platformSuppressionReason(first.category),
                              platformSuppressionExplanation(first.category),
                            ),
                          ),
                          Expanded(
                            child: fact(
                              'Since',
                              first.since == null
                                  ? 'Unknown'
                                  : platformShortDate(first.since!, now),
                              first.since == null
                                  ? ''
                                  : platformPlural(
                                      platformDaysBetween(first.since!, now),
                                      'day',
                                    ),
                            ),
                          ),
                          Expanded(
                            child: fact(
                              'Found',
                              platformPlural(review.items.length, 'record'),
                              '${active.length} active',
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: tokens.spacing.s16),
                      Divider(height: 1, color: colors.surface.cardEdge),
                      SizedBox(height: tokens.spacing.s16),
                      AppSelect<PlatformClearConfirmation>(
                        key: const ValueKey('platform-email-confirmation'),
                        label: 'What changed',
                        value: _confirmation,
                        onChanged: _busy
                            ? null
                            : (value) => setState(
                                () => _confirmation = value ?? _confirmation,
                              ),
                        items: <AppSelectItem<PlatformClearConfirmation>>[
                          if (review.needsSpamEvidence)
                            const AppSelectItem(
                              value: PlatformClearConfirmation.spamComplaint,
                              label: 'The spam complaint is withdrawn',
                            )
                          else ...const <
                            AppSelectItem<PlatformClearConfirmation>
                          >[
                            AppSelectItem(
                              value: PlatformClearConfirmation.addressCorrected,
                              label: 'The address was corrected',
                            ),
                            AppSelectItem(
                              value: PlatformClearConfirmation.addressVerified,
                              label: 'The address was verified another way',
                            ),
                          ],
                        ],
                      ),
                      if (review.needsSpamEvidence) ...[
                        SizedBox(height: tokens.spacing.s16),
                        AppTextField(
                          key: const ValueKey('platform-email-evidence'),
                          label: 'Evidence reference',
                          controller: _evidence,
                          enabled: !_busy,
                          maxLength: 256,
                          helper:
                              'A ticket or message that shows the complaint was withdrawn.',
                        ),
                      ],
                      SizedBox(height: tokens.spacing.s16),
                      AppTextField(
                        key: const ValueKey('platform-email-reason'),
                        label: 'Reason for clearing',
                        controller: _reason,
                        enabled: !_busy,
                        minLines: 3,
                        maxLines: 4,
                        maxLength: 1000,
                        placeholder: 'Why the address will work now',
                        helper: 'Recorded in Activity with your name.',
                      ),
                      SizedBox(height: tokens.spacing.s16),
                      if (compact) ...[
                        AppButton(
                          key: const ValueKey('platform-email-clear'),
                          label: 'Clear suppression',
                          expand: true,
                          loading: _busy,
                          onPressed: _canClear ? _clear : null,
                        ),
                        SizedBox(height: tokens.spacing.s8),
                        const PlatformCaption(
                          'If the next message bounces too, the provider suppresses the address again.',
                        ),
                      ] else
                        Row(
                          children: <Widget>[
                            const Expanded(
                              child: PlatformCaption(
                                'If the next message bounces too, the provider suppresses the address again.',
                              ),
                            ),
                            SizedBox(width: tokens.spacing.s12),
                            AppButton(
                              key: const ValueKey('platform-email-clear'),
                              label: 'Clear suppression',
                              loading: _busy,
                              onPressed: _canClear ? _clear : null,
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// The role a person holds, for a test.
String platformRoleLabel(TenantRole role) => PlatformPill.role(role).label;
