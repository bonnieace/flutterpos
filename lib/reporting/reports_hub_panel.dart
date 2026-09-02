/// The reports hub: one landing page whose cards each open a deeper report.
///
/// **Why this exists.** `lib/pos/reports.dart` - the pre-multitenancy app, read
/// only - was a hub: five metric cards, each an entry point to a report behind
/// it. The multitenant rebuild migrated the *content* of one of those reports
/// (`TenantWeeklyReportScreen`) and dropped the hub, so the migrated screen
/// became a leaf with no route builders and nothing to link to.
///
/// That left five finished screens with no entrance. `TenantDailySummaryScreen`
/// already declares `reconciliationRoute` and `salesTotalsRoute`; those open
/// `TenantReconciliationStatusScreen`, which opens the anomalies feed, which
/// opens one run. Every one of them is built, tested, and was reachable from
/// the home until the *Reports* slot was repointed at the weekly report on
/// 2026-08-27. Nightly reconciliation has been writing anomalies that nobody
/// could look at ever since.
///
/// **This screen reads nothing.** It is navigation and role arithmetic only, so
/// it makes no repository call and holds no loader - which is what lets it sit
/// on the route between the home and four reports without adding a read to
/// either. The session comes from [TenantSessionScope], an `InheritedNotifier`,
/// so a business switch rebuilds the hub and empties it rather than leaving a
/// card that would open another business's figures.
///
/// **The grid is `HomeModuleGrid`, not a second card grid.** It already lays
/// destinations out per band, orders the primary first, draws group headings
/// only where a role was given a row that carries one, and handles badges and
/// descriptions. A hub that drew its own cards would be the same component
/// twice with two sets of arithmetic to keep agreeing.
library;

import 'package:flutter/material.dart';

import '../tenancy/tenant_session_controller.dart';
import '../tenancy/tenant_types.dart';
import '../ui/home_navigation.dart';
import '../ui/routes.dart';
import '../ui/scaffold.dart';
import '../ui/states.dart';
import '../ui/tokens.dart';

/// Builds one report route.
///
/// Reports take no argument: each one already holds the reader and the callable
/// it needs, bound by the composition root when the builder was made. The
/// signature matches `TenantSalesTotalsRouteBuilder` in `daily_metrics_panel`
/// for the same reason.
typedef TenantReportRouteBuilder = Widget Function();

/// One card on the hub, before a role has been asked about it.
final class _HubEntry {
  const _HubEntry({
    required this.key,
    required this.label,
    required this.description,
    required this.icon,
    required this.route,
    required this.roles,
  });

  final String key;
  final String label;
  final String description;
  final IconData icon;
  final TenantReportRouteBuilder? route;
  final List<TenantRole> roles;
}

/// The hub every report is reached from.
///
/// Each route is nullable and each carries its own role list, decided by the
/// domain that owns the surface rather than here. A card whose builder is
/// absent, or whose roles this session does not satisfy, is **not built** -
/// `HomeModuleGrid` then simply has one fewer card, which is the same rule the
/// home's own destination list follows.
final class TenantReportsHubScreen extends StatelessWidget {
  const TenantReportsHubScreen({
    super.key,
    this.dailySummaryRoute,
    this.dailySummaryRoles = const <TenantRole>[],
    this.weeklyReportRoute,
    this.weeklyReportRoles = const <TenantRole>[],
    this.monthlyReportRoute,
    this.monthlyReportRoles = const <TenantRole>[],
    this.salesTotalsRoute,
    this.salesTotalsRoles = const <TenantRole>[],
  });

  /// The reconciled figures for recent business days, and the entrance to the
  /// reconciliation chain behind them.
  final TenantReportRouteBuilder? dailySummaryRoute;
  final List<TenantRole> dailySummaryRoles;

  /// The old app's *Reports & Analytics* week, against the week before.
  final TenantReportRouteBuilder? weeklyReportRoute;
  final List<TenantRole> weeklyReportRoles;

  /// The same reading over a chosen month.
  final TenantReportRouteBuilder? monthlyReportRoute;
  final List<TenantRole> monthlyReportRoles;

  /// What the server currently holds for a chosen period, split by how each
  /// sale was paid for.
  ///
  /// **A card of its own rather than a row inside the daily summary**, which is
  /// where it was reached from before. `TenantSalesTotalsScreen` is the only
  /// surface that can answer *how much have we taken today*, and the summary it
  /// used to hide behind reports only what nightly reconciliation has already
  /// settled - so today, the day somebody at a counter actually asks about, is
  /// normally blank there. Both entrances are kept: this one for the question,
  /// the summary's for the person who has just learned today is not reconciled
  /// yet.
  final TenantReportRouteBuilder? salesTotalsRoute;
  final List<TenantRole> salesTotalsRoles;

  /// The cards, in the order a shop asks the questions rather than the order
  /// the code grew in: the settled figures first, then the two periods, then
  /// the live takings and how they were paid.
  List<_HubEntry> _entries() => <_HubEntry>[
    _HubEntry(
      key: 'report-daily-summary',
      label: 'Daily summary',
      description:
          'What reconciliation settled for each recent day, and why a day is '
          'in the state it is.',
      icon: Icons.today_outlined,
      route: dailySummaryRoute,
      roles: dailySummaryRoles,
    ),
    _HubEntry(
      key: 'report-weekly',
      label: 'This week',
      description: 'Sales, profit and best sellers, against the week before.',
      icon: Icons.insights_outlined,
      route: weeklyReportRoute,
      roles: weeklyReportRoles,
    ),
    _HubEntry(
      key: 'report-monthly',
      label: 'This month',
      description: 'The same reading over a month you choose.',
      icon: Icons.calendar_month_outlined,
      route: monthlyReportRoute,
      roles: monthlyReportRoles,
    ),
    _HubEntry(
      key: 'report-sales-totals',
      label: 'Takings',
      description:
          'What the server holds for a period you choose, and how it split '
          'across the ways customers paid.',
      icon: Icons.payments_outlined,
      route: salesTotalsRoute,
      roles: salesTotalsRoles,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    // `of` rather than a read: this is an `InheritedNotifier`, so depending on
    // it is what rebuilds the hub when the session changes. A hub that kept its
    // cards after a business switch would offer a route into figures the new
    // session may not read.
    final controller = TenantSessionScope.of(context);
    final session = controller.session;

    final destinations = session == null
        ? const <HomeDestination>[]
        : <HomeDestination>[
            for (final entry in _entries())
              if (entry.route != null &&
                  session.canAccess(allowedRoles: entry.roles))
                HomeDestination(
                  destinationKey: ValueKey(entry.key),
                  label: entry.label,
                  description: entry.description,
                  icon: entry.icon,
                  onPressed: () => _open(context, controller, entry.route!),
                ),
          ];

    return AppScaffold(
      title: 'Reports',
      contentWidth: AppContentWidth.records,
      body: destinations.isEmpty
          ? const Center(
              child: EmptyState(
                key: ValueKey('reports-hub-empty'),
                title: 'No reports are shown for this role',
                hint: 'An owner, an administrator or a manager can read them.',
                illustration: 'access-denied.svg',
              ),
            )
          : SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  vertical: AppTokens.componentOf(context).spacing.s8,
                ),
                child: HomeModuleGrid(destinations: destinations),
              ),
            ),
    );
  }

  /// Opens one report under the session scope the hub itself was opened in.
  ///
  /// The scope is re-established around the child for the same reason the home
  /// re-establishes it around every destination it pushes: a route is a new
  /// subtree under the navigator, not under this widget, so it would otherwise
  /// have no session above it at all.
  void _open(
    BuildContext context,
    TenantSessionController controller,
    TenantReportRouteBuilder route,
  ) {
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) =>
            TenantSessionScope(controller: controller, child: route()),
      ),
    );
  }
}
