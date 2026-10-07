import 'package:flutter/material.dart';

import '../ui/bottom_nav.dart';
import '../ui/buttons.dart';
import '../ui/chips.dart';
import '../ui/scaffold.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'platform_console.dart';
import 'platform_console_data.dart';
import 'platform_console_widgets.dart';

// ---------------------------------------------------------------------------
// Alerts.
// ---------------------------------------------------------------------------

final class PlatformAlertsPage extends StatelessWidget {
  const PlatformAlertsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = PlatformConsoleScope.of(context);
    final tokens = AppTokens.componentOf(context);
    final compact = platformCompact(context);
    final inset = AppScaffold.horizontalInset(tokens.spacing);
    return AppScaffold(
      title: 'Alerts',
      contentWidth: AppContentWidth.records,
      automaticallyImplyLeading: false,
      body: PlatformLoader<List<PlatformAlertView>>(
        load: () async {
          final reader = PlatformAlertsReader(scope.source, clock: scope.clock);
          final alerts = await reader.list();
          final since = scope.clock().subtract(
            PlatformAlertsReader.recentWindow,
          );
          scope.alertCount.value = alerts
              .where((alert) => alert.createdAt.isAfter(since))
              .length;
          return reader.views(alerts);
        },
        isCurrent: scope.isCurrent,
        loadingMessage: 'Reading the alerts.',
        failure: 'The alerts could not be read.',
        boundary: 'platform.alerts_read',
        builder: (context, views, reload) {
          final since = scope.clock().subtract(
            PlatformAlertsReader.recentWindow,
          );
          final recent = views
              .where((view) => view.alert.createdAt.isAfter(since))
              .toList();
          final earlier = views
              .where((view) => !view.alert.createdAt.isAfter(since))
              .toList();
          Widget group(String title, List<PlatformAlertView> items) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: EdgeInsets.only(bottom: tokens.spacing.s12),
                child: Text(
                  title.toUpperCase(),
                  style: tokens.typography.labelEyebrow.copyWith(
                    color: tokens.colors.text.secondary,
                  ),
                ),
              ),
              for (final view in items) ...[
                PlatformAlertCard(view: view, recent: identical(items, recent)),
                SizedBox(height: tokens.spacing.s8),
              ],
              SizedBox(height: tokens.spacing.s16),
            ],
          );
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                inset,
                tokens.spacing.s8,
                inset,
                AppBottomNav.clearanceOf(tokens, compact: compact),
              ),
              children: <Widget>[
                if (views.isEmpty)
                  const EmptyState(
                    icon: Icons.notifications_none,
                    title: 'No alerts',
                    hint:
                        'An alert is raised when a business is left without an owner or an administrator, or its reconciliation stops retrying.',
                  )
                else ...[
                  if (recent.isNotEmpty) group('Raised this week', recent),
                  if (earlier.isNotEmpty) group('Earlier', earlier),
                  const Callout(
                    status: AppStatus.info,
                    message:
                        'Raising an alert does not change the business: it keeps trading. An alert counts as needing you for the seven days after it is raised.',
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

final class PlatformAlertCard extends StatelessWidget {
  const PlatformAlertCard({
    super.key,
    required this.view,
    required this.recent,
  });

  final PlatformAlertView view;
  final bool recent;

  @override
  Widget build(BuildContext context) {
    final scope = PlatformConsoleScope.of(context);
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final compact = platformCompact(context);
    final alert = view.alert;
    final person = view.personName ?? 'an account';
    final body = switch (alert.type) {
      PlatformAlertType.ownerUnavailable =>
        'Disabling $person left the business without an owner who can sign in, and nobody else there is an active administrator.',
      PlatformAlertType.noActiveAdministrator =>
        'Disabling $person left the business with no active administrator.',
      PlatformAlertType.reconciliationQuarantined =>
        'The nightly reconciliation failed ${alert.failureCount ?? 8} times in a row. It is quarantined and will not run again until someone looks.',
      PlatformAlertType.unknown =>
        'The platform raised an alert of a kind this console does not know.',
    };
    final facts = <(String, String)>[
      ('Raised', platformStamp(alert.createdAt)),
      if (alert.type == PlatformAlertType.reconciliationQuarantined)
        (
          'Last error',
          '${alert.errorCode ?? 'unknown'} · ${alert.failureCount ?? 8} failures in a row',
        )
      else if (alert.uid != null)
        (
          'Caused by',
          'Disabling $person${view.requesterName == null ? '' : ', by ${view.requesterName}'}',
        ),
      (
        'Email',
        alert.notified
            ? 'Sent to the platform administrators'
            : 'Being sent to the platform administrators',
      ),
    ];
    final labelWidth = tokens.spacing.s64 + tokens.spacing.s48;
    return DecoratedBox(
      key: ValueKey('platform-alert-${alert.id}'),
      decoration: BoxDecoration(
        color: colors.surface.raised,
        border: Border.all(
          color: recent
              ? colors.status.problem.border
              : colors.surface.cardEdge,
        ),
        borderRadius: BorderRadius.circular(tokens.radius.lg),
      ),
      child: Padding(
        padding: EdgeInsets.all(
          compact ? tokens.spacing.s12 : tokens.spacing.s16,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            PlatformToneWell(
              icon: Icons.error_outline,
              status: recent ? AppStatus.problem : AppStatus.neutral,
              small: compact,
            ),
            SizedBox(width: tokens.spacing.s16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  PlatformRowTitle(name: platformAlertTitle(view)),
                  SizedBox(height: tokens.spacing.s8),
                  Text(
                    body,
                    style: tokens.typography.bodyMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                  SizedBox(height: tokens.spacing.s8),
                  for (final fact in facts)
                    Padding(
                      padding: EdgeInsets.only(top: tokens.spacing.s4),
                      child: compact
                          ? Text.rich(
                              TextSpan(
                                children: <InlineSpan>[
                                  TextSpan(
                                    text: '${fact.$1}  ',
                                    style: TextStyle(
                                      color: colors.text.tertiary,
                                    ),
                                  ),
                                  TextSpan(text: fact.$2),
                                ],
                              ),
                              style: tokens.typography.caption.copyWith(
                                color: colors.text.primary,
                              ),
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                SizedBox(
                                  width: labelWidth,
                                  child: Text(
                                    fact.$1,
                                    style: tokens.typography.caption.copyWith(
                                      color: colors.text.tertiary,
                                      height:
                                          tokens.typography.bodyMedium.height! *
                                          tokens
                                              .typography
                                              .bodyMedium
                                              .fontSize! /
                                          tokens.typography.caption.fontSize!,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    fact.$2,
                                    style: tokens.typography.bodyMedium
                                        .copyWith(color: colors.text.primary),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  SizedBox(height: tokens.spacing.s12),
                  Wrap(
                    spacing: tokens.spacing.s8,
                    runSpacing: tokens.spacing.s8,
                    children: <Widget>[
                      if (alert.tenantId != null)
                        AppButton(
                          label: 'Open business',
                          size: AppButtonSize.md,
                          onPressed: () =>
                              scope.openBusiness(context, alert.tenantId!),
                        ),
                      if (alert.uid != null && view.personName != null)
                        AppButton(
                          label: 'Open ${view.personName}',
                          size: AppButtonSize.md,
                          onPressed: () =>
                              scope.openPerson(context, alert.uid!),
                        ),
                    ],
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

// ---------------------------------------------------------------------------
// Activity.
// ---------------------------------------------------------------------------

final class PlatformActivityLogPage extends StatefulWidget {
  const PlatformActivityLogPage({super.key});

  @override
  State<PlatformActivityLogPage> createState() =>
      _PlatformActivityLogPageState();
}

final class _PlatformActivityLogPageState
    extends State<PlatformActivityLogPage> {
  PlatformActivityFilter _filter = PlatformActivityFilter.everything;
  final List<PlatformActivityEntry> _entries = <PlatformActivityEntry>[];
  final Map<String, String> _people = <String, String>{};
  final Map<String, String> _businesses = <String, String>{};
  PlatformCursor? _next;
  bool _loading = true;
  bool _failed = false;
  bool _read = false;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(reset: true));
  }

  Future<void> _load({required bool reset}) async {
    final scope = PlatformConsoleScope.of(context);
    final epoch = ++_epoch;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page = await PlatformActivityReader(
        scope.source,
      ).page(filter: _filter, after: reset ? null : _next);
      if (!mounted || epoch != _epoch || !scope.isCurrent()) return;
      setState(() {
        if (reset) _entries.clear();
        _entries.addAll(page.entries);
        _people.addAll(page.people);
        _businesses.addAll(page.businesses);
        _next = page.next;
        _loading = false;
        _read = true;
      });
    } catch (error, stackTrace) {
      reportPlatformRead(error, stackTrace, 'platform.activity_read');
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _select(PlatformActivityFilter? filter) {
    final next = filter ?? PlatformActivityFilter.everything;
    if (next == _filter) return;
    setState(() => _filter = next);
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final scope = PlatformConsoleScope.of(context);
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final compact = platformCompact(context);
    final inset = AppScaffold.horizontalInset(tokens.spacing);
    final now = scope.clock();
    final page = PlatformActivityPage(
      entries: _entries,
      next: _next,
      people: _people,
      businesses: _businesses,
    );

    final groups = <(String, List<PlatformActivityEntry>)>[];
    for (final entry in _entries) {
      final days = platformDaysBetween(entry.createdAt, now);
      final heading = days >= 7
          ? 'Earlier'
          : platformDayHeading(entry.createdAt, now);
      if (groups.isEmpty || groups.last.$1 != heading) {
        groups.add((heading, <PlatformActivityEntry>[]));
      }
      groups.last.$2.add(entry);
    }

    Widget content;
    if (_failed && !_read) {
      content = ErrorState(
        badgeLabel: 'Not read',
        statement: 'The activity could not be read.',
        stillTrue: 'Nothing was changed.',
        actions: <Widget>[
          AppButton(
            label: 'Try again',
            icon: Icons.refresh,
            tier: AppButtonTier.primary,
            onPressed: () => _load(reset: true),
          ),
        ],
      );
    } else if (!_read) {
      content = const LoadingState(message: 'Reading the activity.');
    } else if (_entries.isEmpty) {
      content = const EmptyState(
        icon: Icons.timeline,
        title: 'Nothing here yet',
        hint: 'Every platform action lands here, with the reason it was given.',
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface.raised,
              border: Border.all(color: colors.surface.cardEdge),
              borderRadius: BorderRadius.circular(tokens.radius.lg),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? tokens.spacing.s16 : tokens.spacing.s20,
                tokens.spacing.s4,
                compact ? tokens.spacing.s16 : tokens.spacing.s20,
                tokens.spacing.s8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final (heading, entries) in groups) ...[
                    Padding(
                      padding: EdgeInsets.only(
                        top: tokens.spacing.s16,
                        bottom: tokens.spacing.s4,
                      ),
                      child: Text(
                        heading.toUpperCase(),
                        style: tokens.typography.labelEyebrow.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                    ),
                    for (var index = 0; index < entries.length; index++)
                      PlatformLine(
                        key: ValueKey('platform-activity-${entries[index].id}'),
                        first: index == 0,
                        icon: platformActivityIcon(entries[index]),
                        tone: platformActivityTone(entries[index]),
                        sentence: platformActivitySentence(
                          context,
                          entries[index],
                          page,
                        ),
                        detail: entries[index].reason == null
                            ? null
                            : '“${entries[index].reason}”',
                        time: heading == 'Earlier'
                            ? platformShortDate(entries[index].createdAt, now)
                            : platformWhen(
                                entries[index].createdAt,
                                now,
                              ).split(' ').last,
                      ),
                  ],
                ],
              ),
            ),
          ),
          if (_next != null) ...[
            SizedBox(height: tokens.spacing.s16),
            Center(
              child: AppButton(
                key: const ValueKey('platform-activity-older'),
                label: 'Load older',
                loading: _loading,
                onPressed: _loading ? null : () => _load(reset: false),
              ),
            ),
          ],
        ],
      );
    }

    return AppScaffold(
      title: 'Activity',
      contentWidth: AppContentWidth.records,
      automaticallyImplyLeading: false,
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            inset,
            tokens.spacing.s8,
            inset,
            AppBottomNav.clearanceOf(tokens, compact: compact),
          ),
          children: <Widget>[
            FilterChipBar<PlatformActivityFilter>(
              semanticLabel: 'Which activity',
              selected: _filter,
              onSelected: _select,
              options: const <FilterChipOption<PlatformActivityFilter>>[
                FilterChipOption(
                  value: PlatformActivityFilter.everything,
                  label: 'Everything',
                ),
                FilterChipOption(
                  value: PlatformActivityFilter.businesses,
                  label: 'Businesses',
                ),
                FilterChipOption(
                  value: PlatformActivityFilter.people,
                  label: 'People',
                ),
                FilterChipOption(
                  value: PlatformActivityFilter.administrators,
                  label: 'Administrators',
                ),
                FilterChipOption(
                  value: PlatformActivityFilter.email,
                  label: 'Email',
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
