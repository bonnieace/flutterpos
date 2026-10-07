import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../ui/bottom_nav.dart';
import '../ui/buttons.dart';
import '../ui/dash_tile.dart';
import '../ui/scaffold.dart';
import '../ui/tokens.dart';
import 'platform_console_activity.dart';
import 'platform_console_businesses.dart';
import 'platform_console_data.dart';
import 'platform_console_people.dart';
import 'platform_console_widgets.dart';
import 'platform_global_user_status.dart';
import 'platform_tenant_console.dart';
import 'tenant_types.dart';

/// What every console screen needs: who is operating, where to read, what to
/// call, and how to move between destinations.
final class PlatformConsoleScope extends InheritedWidget {
  const PlatformConsoleScope({
    super.key,
    required this.identity,
    required this.source,
    required this.lifecycleCallable,
    required this.globalUserDataSource,
    required this.globalUserCallable,
    required this.suppressionCallable,
    required this.clock,
    required this.requestIdFactory,
    required this.isCurrent,
    required this.onSignOut,
    required this.select,
    required this.alertCount,
    required super.child,
  });

  final PlatformAdminIdentity identity;
  final PlatformConsoleDataSource source;
  final SetTenantLifecycleCallable lifecycleCallable;
  final PlatformGlobalUserDataSource globalUserDataSource;
  final SetGlobalUserStatusCallable globalUserCallable;
  final ReviewEmailSuppressionCallable suppressionCallable;
  final DateTime Function() clock;
  final PlatformTenantRequestIdFactory? requestIdFactory;
  final bool Function() isCurrent;
  final Future<void> Function() onSignOut;

  /// Moves to a top-level destination, optionally with a filter applied.
  final void Function(PlatformDestination destination, {Object? filter}) select;

  /// The recent alerts, for the bar's count. Refreshed by whoever reads them.
  final ValueNotifier<int> alertCount;

  static PlatformConsoleScope of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<PlatformConsoleScope>();
    assert(scope != null, 'No PlatformConsoleScope above this context.');
    return scope!;
  }

  void openBusiness(BuildContext context, String tenantId) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlatformBusinessPage(tenantId: tenantId),
        ),
      );

  void openPerson(BuildContext context, String uid) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => PlatformPersonPage(uid: uid)));

  void openEmailDelivery(BuildContext context, {String? email}) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlatformEmailDeliveryPage(initialEmail: email),
        ),
      );

  @override
  bool updateShouldNotify(PlatformConsoleScope oldWidget) =>
      identity != oldWidget.identity ||
      source != oldWidget.source ||
      select != oldWidget.select;
}

enum PlatformDestination { overview, businesses, people, alerts, activity }

/// The platform console: five destinations on a floating bottom bar.
///
/// **Detail screens are pushed on a navigator of the console's own**, so they
/// cannot outlive it: when the routing shell swaps the console out - sign-out,
/// a revoked claim - every pushed business and person page goes with it rather
/// than staying on the app's root stack above whatever replaced it.
final class PlatformConsoleScreen extends StatefulWidget {
  const PlatformConsoleScreen({
    super.key,
    required this.identity,
    required this.source,
    required this.lifecycleCallable,
    required this.globalUserDataSource,
    required this.globalUserCallable,
    required this.suppressionCallable,
    required this.onSignOut,
    this.requestIdFactory,
    this.isCurrent,
    this.clock,
    this.initialDestination = PlatformDestination.overview,
  });

  final PlatformAdminIdentity identity;
  final PlatformConsoleDataSource source;
  final SetTenantLifecycleCallable lifecycleCallable;
  final PlatformGlobalUserDataSource globalUserDataSource;
  final SetGlobalUserStatusCallable globalUserCallable;
  final ReviewEmailSuppressionCallable suppressionCallable;
  final Future<void> Function() onSignOut;
  final PlatformTenantRequestIdFactory? requestIdFactory;
  final PlatformTenantCurrentCheck? isCurrent;
  final DateTime Function()? clock;
  final PlatformDestination initialDestination;

  @override
  State<PlatformConsoleScreen> createState() => _PlatformConsoleScreenState();
}

final class _PlatformConsoleScreenState extends State<PlatformConsoleScreen> {
  final _navigator = GlobalKey<NavigatorState>();
  late final ValueNotifier<PlatformDestination> _destination = ValueNotifier(
    widget.initialDestination,
  );
  final ValueNotifier<int> _alertCount = ValueNotifier(0);
  final ValueNotifier<Object?> _filter = ValueNotifier(null);

  @override
  void initState() {
    super.initState();
    _readAlertCount();
  }

  @override
  void dispose() {
    _destination.dispose();
    _alertCount.dispose();
    _filter.dispose();
    super.dispose();
  }

  DateTime _now() => (widget.clock ?? DateTime.now)();

  bool _isCurrent() =>
      mounted &&
      widget.identity.canAdminister &&
      (widget.isCurrent?.call() ?? true);

  Future<void> _readAlertCount() async {
    try {
      final recent = await PlatformAlertsReader(
        widget.source,
        clock: _now,
      ).recent();
      if (_isCurrent()) _alertCount.value = recent.length;
    } catch (error, stackTrace) {
      reportPlatformRead(error, stackTrace, 'platform.alert_count_read');
    }
  }

  void _select(PlatformDestination destination, {Object? filter}) {
    _navigator.currentState?.popUntil((route) => route.isFirst);
    _filter.value = filter;
    _destination.value = destination;
  }

  @override
  Widget build(BuildContext context) {
    return PlatformConsoleScope(
      identity: widget.identity,
      source: widget.source,
      lifecycleCallable: widget.lifecycleCallable,
      globalUserDataSource: widget.globalUserDataSource,
      globalUserCallable: widget.globalUserCallable,
      suppressionCallable: widget.suppressionCallable,
      clock: _now,
      requestIdFactory: widget.requestIdFactory,
      isCurrent: _isCurrent,
      onSignOut: widget.onSignOut,
      select: _select,
      alertCount: _alertCount,
      child: NavigatorPopHandler(
        onPopWithResult: (_) => _navigator.currentState?.maybePop(),
        child: Navigator(
          key: _navigator,
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => _Destinations(
              destination: _destination,
              filter: _filter,
              alertCount: _alertCount,
            ),
          ),
        ),
      ),
    );
  }
}

final class _Destinations extends StatefulWidget {
  const _Destinations({
    required this.destination,
    required this.filter,
    required this.alertCount,
  });

  final ValueNotifier<PlatformDestination> destination;
  final ValueNotifier<Object?> filter;
  final ValueNotifier<int> alertCount;

  @override
  State<_Destinations> createState() => _DestinationsState();
}

final class _DestinationsState extends State<_Destinations> {
  /// A destination is built the first time it is visited and kept after, so
  /// coming back to a list keeps its filter and its page.
  final Set<PlatformDestination> _visited = {};

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        widget.destination,
        widget.alertCount,
      ]),
      builder: (context, _) {
        final current = widget.destination.value;
        _visited.add(current);
        final scope = PlatformConsoleScope.of(context);
        final bar = AppBottomNav(
          key: const ValueKey('platform-bottom-nav'),
          currentIndex: current.index,
          onSelected: (index) =>
              scope.select(PlatformDestination.values[index]),
          destinations: <AppBottomDestination>[
            const AppBottomDestination(
              label: 'Overview',
              icon: Icons.grid_view_outlined,
              destinationKey: ValueKey('platform-nav-overview'),
            ),
            const AppBottomDestination(
              label: 'Businesses',
              icon: Icons.storefront_outlined,
              destinationKey: ValueKey('platform-nav-businesses'),
            ),
            const AppBottomDestination(
              label: 'People',
              icon: Icons.group_outlined,
              destinationKey: ValueKey('platform-nav-people'),
            ),
            AppBottomDestination(
              label: 'Alerts',
              icon: Icons.notifications_none,
              badgeCount: widget.alertCount.value,
              destinationKey: const ValueKey('platform-nav-alerts'),
            ),
            const AppBottomDestination(
              label: 'Activity',
              icon: Icons.timeline,
              destinationKey: ValueKey('platform-nav-activity'),
            ),
          ],
        );
        Widget page(PlatformDestination destination) => switch (destination) {
          PlatformDestination.overview => const PlatformOverviewPage(),
          PlatformDestination.businesses => PlatformBusinessesPage(
            filterRequest: widget.filter,
          ),
          PlatformDestination.people => PlatformPeoplePage(
            filterRequest: widget.filter,
          ),
          PlatformDestination.alerts => const PlatformAlertsPage(),
          PlatformDestination.activity => const PlatformActivityLogPage(),
        };
        return AppBottomNavFrame(
          bar: bar,
          child: IndexedStack(
            index: current.index,
            children: <Widget>[
              for (final destination in PlatformDestination.values)
                _visited.contains(destination)
                    ? TickerMode(
                        enabled: destination == current,
                        child: page(destination),
                      )
                    : const SizedBox.shrink(),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// The overview.
// ---------------------------------------------------------------------------

final class PlatformOverviewPage extends StatelessWidget {
  const PlatformOverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = PlatformConsoleScope.of(context);
    final tokens = AppTokens.componentOf(context);
    final compact = platformCompact(context);
    final now = scope.clock();
    return AppScaffold(
      title: 'Overview',
      contentWidth: AppContentWidth.records,
      automaticallyImplyLeading: false,
      actions: <Widget>[
        if (!compact)
          Center(
            child: Padding(
              padding: EdgeInsets.only(right: tokens.spacing.s8),
              child: Text(
                DateFormat('EEE d MMM, HH:mm').format(now),
                key: const ValueKey('platform-overview-read-at'),
                style: tokens.typography.bodyMedium.copyWith(
                  color: tokens.colors.text.secondary,
                ),
              ),
            ),
          ),
        AppIconButton(
          key: const ValueKey('platform-sign-out'),
          icon: Icons.logout,
          semanticLabel: 'Sign out',
          bordered: false,
          iconSize: tokens.icons.card,
          glyphColor: tokens.colors.action.primary.container,
          onPressed: scope.onSignOut,
        ),
        SizedBox(width: tokens.spacing.s8),
      ],
      body: PlatformLoader<PlatformOverview>(
        load: () async {
          final overview = await PlatformOverviewReader(
            scope.source,
            clock: scope.clock,
          ).load();
          scope.alertCount.value = overview.alerts.length;
          return overview;
        },
        isCurrent: scope.isCurrent,
        loadingMessage: 'Reading the platform.',
        failure: 'The platform figures could not be read.',
        boundary: 'platform.overview_read',
        builder: (context, overview, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              AppScaffold.horizontalInset(tokens.spacing),
              tokens.spacing.s8,
              AppScaffold.horizontalInset(tokens.spacing),
              AppBottomNav.clearanceOf(tokens, compact: compact),
            ),
            children: <Widget>[PlatformOverviewGrid(overview: overview)],
          ),
        ),
      ),
    );
  }
}

/// The overview's nine tiles. Public so a test can pump it with a fixed
/// [PlatformOverview].
final class PlatformOverviewGrid extends StatelessWidget {
  const PlatformOverviewGrid({super.key, required this.overview});

  final PlatformOverview overview;

  @override
  Widget build(BuildContext context) {
    final scope = PlatformConsoleScope.of(context);
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final status = colors.status;
    final identity = colors.accent;
    final now = overview.readAt;
    final o = overview;

    String weekLabel(int index) {
      final start = platformWeekStart(now).subtract(
        Duration(days: 7 * (PlatformOverviewReader.weeks - 1 - index)),
      );
      return index == PlatformOverviewReader.weeks - 1
          ? 'This week'
          : DateFormat('d MMM').format(start);
    }

    final longest = o.suspensions.isEmpty ? null : o.suspensions.first;
    final longestDays = longest?.since == null
        ? null
        : platformDaysBetween(longest!.since!, now);

    final alertItems = <AppDashListItem>[
      for (final view in o.alerts.take(2))
        AppDashListItem(
          icon: Icons.error_outline,
          color: status.problem.fg,
          problem: true,
          tall: true,
          title: TextSpan(text: platformAlertTitle(view)),
          meta:
              'Raised ${platformStamp(view.alert.createdAt)} · ${platformAlertCause(view)}',
        ),
    ];

    final activityItems = <AppDashListItem>[
      for (final entry in o.activity.entries.take(4))
        AppDashListItem(
          icon: platformActivityIcon(entry),
          color: platformToneColors(tokens, platformActivityTone(entry)).fg,
          title: platformActivitySentence(
            context,
            entry,
            o.activity,
            short: true,
          ),
          trailing: platformWhen(entry.createdAt, now),
        ),
    ];

    final operationItems = <AppDashListItem>[
      for (final operation in o.operations.take(4))
        AppDashListItem(
          icon: Icons.sync,
          color: status.attention.fg,
          title: TextSpan(
            children: <InlineSpan>[
              platformBold(
                context,
                o.operationNames[operation.uid] ?? 'An account',
              ),
              TextSpan(
                text: operation.reactivating
                    ? ' · reactivating'
                    : ' · disabling',
              ),
            ],
          ),
          trailing: 'Attempt ${operation.attemptCount}',
        ),
    ];

    final administrators = [...o.administrators]
      ..sort(
        (a, b) => a.uid == scope.identity.uid
            ? -1
            : b.uid == scope.identity.uid
            ? 1
            : a.name.compareTo(b.name),
      );
    final adminItems = <AppDashListItem>[
      for (final admin in administrators.take(3))
        AppDashListItem(
          icon: Icons.shield_outlined,
          color: identity.privileged,
          title: TextSpan(
            children: <InlineSpan>[platformBold(context, admin.name)],
          ),
          trailing: admin.uid == scope.identity.uid ? 'You' : null,
        ),
    ];

    final quiet = tokens.typography.bodyMedium.copyWith(
      color: colors.text.secondary,
    );

    final tiles = <AppDashTile>[
      AppDashTile(
        key: const ValueKey('platform-tile-trading'),
        icon: Icons.storefront_outlined,
        accent: status.ok.fg,
        label: 'Trading',
        value: '${o.trading}',
        detail: 'of ${o.businesses}',
        visual: AppSegmentBar(
          segments: <AppSegment>[
            AppSegment(
              count: o.trading,
              color: status.ok.fg,
              icon: Icons.check_circle_outline,
              label: 'trading',
            ),
            AppSegment(
              count: o.suspended,
              color: status.attention.fg,
              icon: Icons.pause_circle_outline,
              label: 'suspended',
            ),
            AppSegment(
              count: o.archived,
              color: status.neutral.fg,
              icon: Icons.inventory_2_outlined,
              label: 'archived',
            ),
          ],
        ),
        footnote:
            '${platformPlural(o.businesses, 'business', 'businesses')} in all',
        onPressed: () => scope.select(
          PlatformDestination.businesses,
          filter: PlatformBusinessFilter.trading,
        ),
      ),
      AppDashTile(
        key: const ValueKey('platform-tile-suspended'),
        icon: Icons.pause_circle_outline,
        accent: status.attention.fg,
        label: 'Suspended',
        value: '${o.suspended}',
        detail: o.suspended == 1 ? 'business' : 'businesses',
        visual: o.suspensions.isEmpty
            ? Align(
                alignment: Alignment.topLeft,
                child: Text('None suspended.', style: quiet),
              )
            : AppDashLines(
                lines: <AppDashLine>[
                  for (final suspension in o.suspensions.take(2))
                    AppDashLine(
                      icon: Icons.pause_circle_outline,
                      color: status.attention.fg,
                      text: suspension.name,
                      meta: suspension.since == null
                          ? null
                          : '${platformDaysBetween(suspension.since!, now)} d',
                    ),
                ],
              ),
        footnote: longestDays == null
            ? 'Nothing suspended'
            : 'Longest ${platformPlural(longestDays, 'day')}',
        onPressed: () => scope.select(
          PlatformDestination.businesses,
          filter: PlatformBusinessFilter.suspended,
        ),
      ),
      AppDashTile(
        key: const ValueKey('platform-tile-opened'),
        icon: Icons.calendar_today_outlined,
        accent: identity.identityAt(AppIdentityAccent.blue),
        label: 'Opened',
        value: '${o.openedThisMonth}',
        detail: 'this month',
        visual: AppSparkBars(
          values: o.businessesByWeek,
          semanticLabel:
              'New businesses per week for ${o.businessesByWeek.length} weeks: ${o.businessesByWeek.join(', ')}',
        ),
        footnote: 'Businesses · ${o.openedThisWeek} this week',
        onPressed: () => scope.select(PlatformDestination.businesses),
      ),
      AppDashTile(
        key: const ValueKey('platform-tile-accounts'),
        icon: Icons.group_outlined,
        accent: identity.identityAt(AppIdentityAccent.pink),
        label: 'Accounts',
        value: '${o.accounts}',
        detail: '+${o.accountsThisWeek} this week',
        visual: AppSparkBars(
          values: o.accountsByWeek,
          semanticLabel:
              'New accounts per week for ${o.accountsByWeek.length} weeks: ${o.accountsByWeek.join(', ')}',
        ),
        footnote: '${o.disabledAccounts} disabled',
        onPressed: () => scope.select(PlatformDestination.people),
      ),
      AppDashTile(
        key: const ValueKey('platform-tile-needs-you'),
        fitsContentOnPhone: true,
        icon: Icons.error_outline,
        accent: status.problem.fg,
        problem: o.alerts.isNotEmpty,
        label: 'Needs you',
        value: '${o.alerts.length}',
        detail: o.alerts.length == 1
            ? 'alert raised this week'
            : 'alerts raised this week',
        span: AppDashSpan.two,
        tall: true,
        visual: alertItems.isEmpty
            ? Align(
                alignment: Alignment.topLeft,
                child: Text(
                  'Nothing needs you. No alert was raised in the last seven days.',
                  style: quiet,
                ),
              )
            : AppDashList(items: alertItems),
        footnote: o.alerts.isEmpty
            ? 'Alerts are emailed to every platform administrator'
            : o.alerts.every((view) => view.alert.notified)
            ? 'Emailed to the platform administrators'
            : 'Email to the platform administrators is on its way',
        onPressed: () => scope.select(PlatformDestination.alerts),
      ),
      AppDashTile(
        key: const ValueKey('platform-tile-growth'),
        icon: Icons.trending_up,
        accent: identity.identityAt(AppIdentityAccent.blue),
        label: 'Growth',
        value: '${o.accounts}',
        detail:
            'accounts · ${platformPlural(o.businesses, 'business', 'businesses')}',
        span: AppDashSpan.two,
        tall: true,
        visual: AppGrowthChart(
          bars: o.accountsByWeek,
          line: o.businessesByWeek,
          weekLabels: <int, String>{
            0: weekLabel(0),
            4: weekLabel(4),
            8: weekLabel(8),
            PlatformOverviewReader.weeks - 1: weekLabel(
              PlatformOverviewReader.weeks - 1,
            ),
          },
          semanticLabel:
              'New accounts per week: ${o.accountsByWeek.join(', ')}. New businesses per week: ${o.businessesByWeek.join(', ')}.',
        ),
        footer: const AppGrowthLegend(
          barsLabel: 'New accounts',
          lineLabel: 'New businesses, right scale',
        ),
        onPressed: () => scope.select(PlatformDestination.businesses),
      ),
      AppDashTile(
        key: const ValueKey('platform-tile-activity'),
        fitsContentOnPhone: true,
        icon: Icons.timeline,
        accent: identity.identityAt(AppIdentityAccent.teal),
        label: 'Activity',
        value: '${o.activityLastWeek}',
        detail: o.activityLastWeek == 1
            ? 'action in the last 7 days'
            : 'actions in the last 7 days',
        span: AppDashSpan.two,
        tall: true,
        visual: activityItems.isEmpty
            ? Align(
                alignment: Alignment.topLeft,
                child: Text('Nothing has happened yet.', style: quiet),
              )
            : AppDashList(items: activityItems),
        footnote: 'Every action carries the reason given',
        onPressed: () => scope.select(PlatformDestination.activity),
      ),
      AppDashTile(
        key: const ValueKey('platform-tile-in-progress'),
        fitsContentOnPhone: true,
        icon: Icons.sync,
        accent: status.attention.fg,
        label: 'In progress',
        value: '${o.operations.length}',
        detail: o.operations.length == 1 ? 'operation' : 'operations',
        tall: true,
        visual: operationItems.isEmpty
            ? Align(
                alignment: Alignment.topLeft,
                child: Text('Nothing is running.', style: quiet),
              )
            : AppDashList(items: operationItems),
        footnote: 'They retry on their own',
        onPressed: () => scope.select(PlatformDestination.people),
      ),
      AppDashTile(
        key: const ValueKey('platform-tile-platform'),
        fitsContentOnPhone: true,
        icon: Icons.shield_outlined,
        accent: identity.privileged,
        label: 'Platform',
        value: '${o.administrators.length}',
        detail: o.administrators.length == 1
            ? 'administrator'
            : 'administrators',
        tall: true,
        visual: AppDashList(
          items: <AppDashListItem>[
            ...adminItems,
            AppDashListItem(
              icon: Icons.tune,
              color: identity.identityAt(AppIdentityAccent.green),
              title: TextSpan(
                text:
                    '${o.limits.requestsPerDay} requests a day · ${o.limits.businessesPerOwner} per owner',
              ),
            ),
          ].take(4).toList(),
        ),
        footnote: 'Granted from the command line',
        onPressed: () => scope.select(
          PlatformDestination.people,
          filter: PlatformPeopleFilter.platform,
        ),
      ),
    ];
    return AppDashGrid(
      tiles: <AppDashTile>[
        for (final tile in tiles)
          if (!_quietlyEmpty(tile, o)) _readOrSay(tile, o.unread, quiet),
      ],
    );
  }

  /// **A tile with nothing to report is not drawn**: *Needs you* with no
  /// alert this week, *In progress* with nothing running. Developer's call,
  /// 2026-10-06. One whose part could not be read stays, saying so - an empty
  /// list and an unread one are different news.
  static bool _quietlyEmpty(AppDashTile tile, PlatformOverview o) {
    final key = tile.key;
    if (key is! ValueKey<String>) return false;
    return switch (key.value) {
      'platform-tile-needs-you' =>
        o.alerts.isEmpty && !o.unread.contains(PlatformOverviewPart.alerts),
      'platform-tile-in-progress' =>
        o.operations.isEmpty &&
            !o.unread.contains(PlatformOverviewPart.operations),
      _ => false,
    };
  }

  /// Which parts of the overview each tile is drawn from.
  static const Map<String, List<PlatformOverviewPart>> _parts = {
    'platform-tile-trading': [PlatformOverviewPart.businesses],
    'platform-tile-suspended': [
      PlatformOverviewPart.businesses,
      PlatformOverviewPart.suspensions,
    ],
    'platform-tile-opened': [PlatformOverviewPart.opened],
    'platform-tile-accounts': [PlatformOverviewPart.accounts],
    'platform-tile-needs-you': [PlatformOverviewPart.alerts],
    'platform-tile-growth': [
      PlatformOverviewPart.opened,
      PlatformOverviewPart.accounts,
    ],
    'platform-tile-activity': [PlatformOverviewPart.activity],
    'platform-tile-in-progress': [PlatformOverviewPart.operations],
    'platform-tile-platform': [PlatformOverviewPart.administrators],
  };

  /// [tile] as drawn, or - when a part it is drawn from could not be read - the
  /// same tile saying so, with a dash for its figure rather than a zero that
  /// would read as a fact.
  static AppDashTile _readOrSay(
    AppDashTile tile,
    Set<PlatformOverviewPart> unread,
    TextStyle quiet,
  ) {
    final key = tile.key;
    final parts = key is ValueKey<String> ? _parts[key.value] : null;
    if (parts == null || !parts.any(unread.contains)) return tile;
    return AppDashTile(
      key: tile.key,
      icon: tile.icon,
      accent: tile.accent,
      label: tile.label,
      value: '–',
      detail: 'not read',
      span: tile.span,
      tall: tile.tall,
      fitsContentOnPhone: tile.fitsContentOnPhone,
      visual: Align(
        alignment: Alignment.topLeft,
        child: Text(
          'This could not be read. Pull down to try again.',
          style: quiet,
        ),
      ),
      footnote: '',
      onPressed: tile.onPressed,
    );
  }
}

// ---------------------------------------------------------------------------
// Sentences the overview, the alerts and the activity log share.
// ---------------------------------------------------------------------------

/// `Mwangi Hardware’s`, `Kilimani Grocers’`.
String platformPossessive(String name) =>
    name.endsWith('s') ? '$name’' : '$name’s';

String platformAlertTitle(PlatformAlertView view) {
  final business = view.businessName ?? 'A business';
  return switch (view.alert.type) {
    PlatformAlertType.ownerUnavailable =>
      '$business has no owner who can sign in',
    PlatformAlertType.noActiveAdministrator =>
      '$business has no active administrator',
    PlatformAlertType.reconciliationQuarantined =>
      '${platformPossessive(business)} reconciliation stopped retrying',
    PlatformAlertType.unknown => 'An alert was raised for $business',
  };
}

String platformAlertCause(PlatformAlertView view) {
  final alert = view.alert;
  return switch (alert.type) {
    PlatformAlertType.ownerUnavailable ||
    PlatformAlertType.noActiveAdministrator =>
      '${view.personName ?? 'An account'} disabled',
    PlatformAlertType.reconciliationQuarantined =>
      '${alert.failureCount ?? 8} failures in a row${alert.errorCode == null ? '' : ', ${alert.errorCode}'}',
    PlatformAlertType.unknown => 'See the alert',
  };
}

IconData platformActivityIcon(PlatformActivityEntry entry) =>
    switch (entry.kind) {
      PlatformActivityKind.businessCreated => Icons.storefront_outlined,
      PlatformActivityKind.businessChanged => switch (entry.to) {
        TenantStatus.suspended => Icons.pause_circle_outline,
        TenantStatus.archived => Icons.inventory_2_outlined,
        _ => Icons.play_circle_outline,
      },
      PlatformActivityKind.personStatusChanged =>
        entry.reactivation == true
            ? Icons.how_to_reg_outlined
            : Icons.person_off_outlined,
      PlatformActivityKind.suppressionInspected => Icons.mail_outline,
      PlatformActivityKind.suppressionCleared => Icons.mark_email_read_outlined,
      PlatformActivityKind.ownerRecovered => Icons.key_outlined,
      PlatformActivityKind.administratorGranted => Icons.key_outlined,
      PlatformActivityKind.administratorRevoked => Icons.key_off_outlined,
      PlatformActivityKind.unknown => Icons.history,
    };

PlatformTone platformActivityTone(PlatformActivityEntry entry) =>
    switch (entry.kind) {
      PlatformActivityKind.businessCreated => PlatformTone.ok,
      PlatformActivityKind.businessChanged => switch (entry.to) {
        TenantStatus.suspended => PlatformTone.attention,
        TenantStatus.archived => PlatformTone.neutral,
        _ => PlatformTone.ok,
      },
      PlatformActivityKind.personStatusChanged =>
        entry.inProgress
            ? PlatformTone.attention
            : entry.reactivation == true
            ? PlatformTone.ok
            : PlatformTone.problem,
      PlatformActivityKind.administratorGranted ||
      PlatformActivityKind.administratorRevoked ||
      PlatformActivityKind.ownerRecovered => PlatformTone.privileged,
      _ => PlatformTone.neutral,
    };

/// The sentence for one platform audit record, with the names in bold.
InlineSpan platformActivitySentence(
  BuildContext context,
  PlatformActivityEntry entry,
  PlatformActivityPage page, {
  bool short = false,
}) {
  final actor = page.people[entry.actorUid] ?? 'An administrator';
  final target = page.people[entry.targetUid] ?? 'an account';
  final business = page.businesses[entry.tenantId] ?? 'a business';
  InlineSpan b(String text) => platformBold(context, text);
  InlineSpan t(String text) => TextSpan(text: text);
  final reactivating = entry.reactivation == true;
  return TextSpan(
    children: switch (entry.kind) {
      PlatformActivityKind.businessCreated => <InlineSpan>[
        b(page.people[entry.actorUid] ?? 'Someone'),
        t(' created '),
        b(business),
      ],
      PlatformActivityKind.businessChanged => <InlineSpan>[
        b(actor),
        t(switch (entry.to) {
          TenantStatus.suspended => ' suspended ',
          TenantStatus.archived => ' archived ',
          _ => ' reactivated ',
        }),
        b(business),
      ],
      PlatformActivityKind.personStatusChanged => <InlineSpan>[
        b(actor),
        t(
          entry.inProgress
              ? (reactivating ? ' is reactivating ' : ' is disabling ')
              : (reactivating ? ' reactivated ' : ' disabled '),
        ),
        b(target),
        if (!short && entry.inProgress && entry.attemptCount != null)
          t('. Attempt ${entry.attemptCount} is waiting to retry.')
        else if (!short && (entry.affectedTenants ?? 0) > 0)
          t(
            '. ${platformPlural(entry.affectedTenants!, 'business', 'businesses')} affected.',
          ),
      ],
      PlatformActivityKind.suppressionInspected => <InlineSpan>[
        b(actor),
        t(' looked up an email address'),
      ],
      PlatformActivityKind.suppressionCleared => <InlineSpan>[
        b(actor),
        t(' cleared an email suppression'),
      ],
      PlatformActivityKind.ownerRecovered => <InlineSpan>[
        b(actor),
        t(' recovered ownership of '),
        b(business),
      ],
      PlatformActivityKind.administratorGranted => <InlineSpan>[
        b(actor),
        t(' granted platform administrator to '),
        b(target),
      ],
      PlatformActivityKind.administratorRevoked => <InlineSpan>[
        b(actor),
        t(' revoked platform administrator from '),
        b(target),
      ],
      PlatformActivityKind.unknown => <InlineSpan>[
        b(actor),
        t(' made a platform change'),
      ],
    },
  );
}
