/// Deciding when a count is due and who takes it.
///
/// **The smallest surface that can express both arrangements the business
/// asked for**: one person counts the whole list, or each person counts a
/// category of it. They are the same control here - a row per member whose
/// choice is *Not counting*, *Everything*, or one category - because they are
/// the same fact about that person.
///
/// **Owner and administrator only, which needs no rules change.** The existing
/// `configuration/{documentId}` rule already admits exactly those two for
/// writing and every active member for reading, and reading is what the till
/// does on the way in.
library;

import 'package:flutter/material.dart';

import '../checkout/checkout_configuration_writer.dart';
import '../tenancy/tenant_catalog.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_staff_directory.dart';
import '../ui/buttons.dart';
import '../ui/chips.dart';
import '../ui/scaffold.dart';
import '../ui/snackbar.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'stock_take_schedule.dart';

/// Everything this screen needs to draw one business's counting schedule.
final class TenantStockTakeSettingsData {
  const TenantStockTakeSettingsData({
    required this.published,
    required this.staff,
    required this.categories,
  });

  final TenantPublishedStockTakeSchedule published;
  final List<TenantStaffSummary> staff;
  final List<TenantCategory> categories;
}

final class TenantStockTakeSettingsScreen extends StatelessWidget {
  const TenantStockTakeSettingsScreen({
    super.key,
    required this.reader,
    this.writer,
    this.onChanged,
  });

  final TenantDataReader reader;
  final TenantConfigurationDocumentWriter? writer;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Stock counts',
    subtitle: 'When a count is due, and who takes it.',
    contentWidth: AppContentWidth.reading,
    body: TenantStockTakeSettingsPanel(
      reader: reader,
      writer: writer,
      onChanged: onChanged,
    ),
  );
}

final class TenantStockTakeSettingsPanel extends StatefulWidget {
  const TenantStockTakeSettingsPanel({
    super.key,
    required this.reader,
    this.writer,
    this.onChanged,
  });

  final TenantDataReader reader;

  /// Absent in a build with no writer wired, which renders read-only.
  final TenantConfigurationDocumentWriter? writer;
  final VoidCallback? onChanged;

  @override
  State<TenantStockTakeSettingsPanel> createState() =>
      _TenantStockTakeSettingsPanelState();
}

/// Monday through Sunday, in the order a week is read.
const List<({int weekday, String label})> _weekdays =
    <({int weekday, String label})>[
      (weekday: DateTime.monday, label: 'Mon'),
      (weekday: DateTime.tuesday, label: 'Tue'),
      (weekday: DateTime.wednesday, label: 'Wed'),
      (weekday: DateTime.thursday, label: 'Thu'),
      (weekday: DateTime.friday, label: 'Fri'),
      (weekday: DateTime.saturday, label: 'Sat'),
      (weekday: DateTime.sunday, label: 'Sun'),
    ];

class _TenantStockTakeSettingsPanelState
    extends State<TenantStockTakeSettingsPanel> {
  TenantStockTakeEnforcement? _enforcement;
  Set<int> _selectedWeekdays = <int>{};

  /// What each member counts. Absent or null means they are not on the rota.
  final Map<String, String?> _assigned = <String, String?>{};

  /// The sentinel a member counting the whole catalog is stored under, which is
  /// never a category ID because a category ID can never be empty.
  static const String _everything = '';

  bool _loaded = false;
  bool _saving = false;

  /// What this screen last published, so the unchanged check and the duplicate
  /// warning read the saved state rather than a read that may lag it.
  TenantPublishedStockTakeSchedule? _saved;

  @override
  Widget build(BuildContext context) {
    // Memoised for the reason `guard_retention_test.dart` gives: a key on the
    // guard destroys its `State` and blanks the page. One loader for the life of
    // this screen - a save keeps what it saved rather than re-reading.
    _composeLoaders('settings');
    return TenantRouteGuard<TenantStockTakeSettingsData>(
      allowedRoles: TenantStockTakeSchedulePublisher.allowedRoles,
      load: _loader!,
      loadCached: _loaderCached,
      denied: const ErrorState(
        status: AppStatus.problem,
        badgeLabel: 'Not allowed',
        statement:
            'Only an owner or administrator may decide when stock is counted.',
      ),
      builder: _build,
    );
  }

  String? _loaderKey;
  TenantGuardedLoader<TenantStockTakeSettingsData>? _loader;
  TenantGuardedLoader<TenantStockTakeSettingsData>? _loaderCached;

  void _composeLoaders(String key) {
    if (key == _loaderKey && _loader != null) return;
    _loaderKey = key;
    _loader = (session) => _read(session, widget.reader);
    final cache = widget.reader.cached;
    _loaderCached = cache == null ? null : (session) => _read(session, cache);
  }

  Future<TenantStockTakeSettingsData> _read(
    TenantSession session,
    TenantDataReader reader,
  ) async {
    final published = await TenantStockTakeScheduleRepository(
      session: session,
      reader: reader,
    ).load();
    final staff = await TenantStaffDirectoryRepository(
      session: session,
      reader: reader,
    ).loadPage(pageSize: 20);
    // Every category, not the first page: a category missing from this list is
    // one nobody can be put on the rota for.
    final categories = await TenantCatalogRepository(
      session: session,
      reader: reader,
    ).loadEveryCategory();
    return TenantStockTakeSettingsData(
      published: published,
      staff: staff.items,
      categories: categories.items,
    );
  }

  /// Seeds the form from what is published, once per load.
  void _seed(TenantStockTakeSettingsData data) {
    if (_loaded) return;
    _loaded = true;
    final schedule = data.published.schedule;
    _enforcement = schedule.enforcement;
    _selectedWeekdays = <int>{...schedule.weekdays};
    _assigned.clear();
    for (final assignment in schedule.assignments) {
      _assigned[assignment.uid] = assignment.categoryId ?? _everything;
    }
  }

  Widget _build(
    BuildContext context,
    TenantSession session,
    TenantStockTakeSettingsData data,
  ) {
    _seed(data);
    final tokens = AppTokens.componentOf(context);
    final enforcement = _enforcement ?? TenantStockTakeEnforcement.off;
    final readOnly = widget.writer == null;
    final published = _saved ?? data.published;
    // Only this screen writes the document, and it writes at most one row per
    // person - so more than one can only come from a hand-edited document.
    final duplicated = _duplicateAssignmentUids(published);

    // A `Column`, not a `ListView`: `TenantSettingsScreen` wraps every tab in
    // the scroll view and the page inset its own route used to supply, so a
    // second scrollable here would nest one inside another.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (published.state == TenantStockTakeScheduleState.malformed)
          Callout(
            key: const ValueKey('stock-take-settings-malformed'),
            status: AppStatus.problem,
            title: 'This setting could not be read',
            message:
                'Nobody is being asked to count while it stays that way, and '
                'the till is unaffected. Choosing below replaces it.',
          ),
        if (duplicated.isNotEmpty)
          Callout(
            key: const ValueKey('stock-take-settings-simplified'),
            status: AppStatus.attention,
            title: 'Somebody is down for more than one category',
            message:
                'This screen records one choice each. Saving here will leave '
                '${duplicated.length} '
                '${duplicated.length == 1 ? 'person' : 'people'} counting only '
                'the first category they are listed against.',
          ),
        if (readOnly)
          const Callout(
            key: ValueKey('stock-take-settings-read-only'),
            status: AppStatus.info,
            title: 'Read-only on this device',
            message: 'This build cannot publish settings changes.',
          ),
        SizedBox(height: tokens.spacing.s16),
        SectionHeading('What happens when a count is due'),
        SizedBox(height: tokens.spacing.s8),
        FilterChipBar<TenantStockTakeEnforcement>(
          semanticLabel: 'What happens when a count is due',
          selected: enforcement,
          onSelected: readOnly
              ? (_) {}
              : (value) => setState(
                  () => _enforcement = value ?? TenantStockTakeEnforcement.off,
                ),
          options: const <FilterChipOption<TenantStockTakeEnforcement>>[
            FilterChipOption<TenantStockTakeEnforcement>(
              key: ValueKey('stock-take-enforcement-off'),
              value: TenantStockTakeEnforcement.off,
              label: 'Nothing',
            ),
            FilterChipOption<TenantStockTakeEnforcement>(
              key: ValueKey('stock-take-enforcement-prompt'),
              value: TenantStockTakeEnforcement.prompt,
              label: 'Ask at the register',
            ),
            FilterChipOption<TenantStockTakeEnforcement>(
              key: ValueKey('stock-take-enforcement-block'),
              value: TenantStockTakeEnforcement.block,
              label: 'Hold the register',
            ),
          ],
        ),
        SizedBox(height: tokens.spacing.s8),
        Text(
          switch (enforcement) {
            TenantStockTakeEnforcement.off =>
              'The rota below is recorded and nobody is interrupted.',
            TenantStockTakeEnforcement.prompt =>
              'Whoever owes a count is asked once when they open the register, '
                  'and may carry on selling.',
            // The sentence that matters, because this is the setting that can
            // stop a shop trading.
            TenantStockTakeEnforcement.block =>
              'Whoever owes a count cannot sell until they have handed it in. '
                  'Handing it in is enough - they do not wait for anybody to '
                  'approve it, and it works with no connection.',
          },
          style: tokens.typography.bodyMedium,
        ),
        SizedBox(height: tokens.spacing.s24),
        SectionHeading('Which days'),
        SizedBox(height: tokens.spacing.s8),
        Wrap(
          spacing: tokens.spacing.s8,
          runSpacing: tokens.spacing.s8,
          children: <Widget>[
            for (final day in _weekdays)
              AppButton(
                key: ValueKey('stock-take-weekday-${day.weekday}'),
                label: day.label,
                size: AppButtonSize.sm,
                // `secondary`, not `tertiary`: tertiary is transparent with no
                // border, which drew the unpicked days as bare words and left
                // nothing to say they could be tapped.
                tier: _selectedWeekdays.contains(day.weekday)
                    ? AppButtonTier.primary
                    : AppButtonTier.secondary,
                onPressed: readOnly
                    ? null
                    : () => setState(() {
                        if (!_selectedWeekdays.remove(day.weekday)) {
                          _selectedWeekdays.add(day.weekday);
                        }
                      }),
              ),
          ],
        ),
        SizedBox(height: tokens.spacing.s24),
        SectionHeading('Who counts what'),
        SizedBox(height: tokens.spacing.s8),
        if (data.staff.isEmpty)
          const EmptyState(
            key: ValueKey('stock-take-settings-no-staff'),
            title: 'Nobody to ask yet',
            hint: 'Invite the people who work here, then set the rota.',
          )
        else
          for (final member in data.staff) ...<Widget>[
            _memberRow(member, data.categories, readOnly: readOnly),
            SizedBox(height: tokens.spacing.s16),
          ],
        SizedBox(height: tokens.spacing.s8),
        AppButton(
          key: const ValueKey('stock-take-settings-save'),
          label: 'Save',
          tier: AppButtonTier.primary,
          loading: _saving,
          onPressed: readOnly || _saving
              ? null
              : () => _save(session, published),
        ),
      ],
    );
  }

  Set<String> _duplicateAssignmentUids(
    TenantPublishedStockTakeSchedule published,
  ) {
    final seen = <String>{};
    final duplicated = <String>{};
    for (final assignment in published.schedule.assignments) {
      if (!seen.add(assignment.uid)) duplicated.add(assignment.uid);
    }
    return duplicated;
  }

  Widget _memberRow(
    TenantStaffSummary member,
    List<TenantCategory> categories, {
    required bool readOnly,
  }) {
    final tokens = AppTokens.componentOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          member.displayName,
          style: tokens.typography.labelLarge,
        ),
        SizedBox(height: tokens.spacing.s8),
        FilterChipBar<String>(
          semanticLabel: 'What ${member.displayName} counts',
          selected: _assigned[member.uid],
          onSelected: readOnly
              ? (_) {}
              : (value) => setState(() => _assigned[member.uid] = value),
          options: <FilterChipOption<String>>[
            FilterChipOption<String>(
              key: ValueKey('stock-take-assign-${member.uid}-none'),
              // Null rather than a word, because "not counting" is the absence
              // of an assignment and not a kind of one.
              value: null,
              label: 'Not counting',
            ),
            FilterChipOption<String>(
              key: ValueKey('stock-take-assign-${member.uid}-all'),
              value: _everything,
              label: 'Everything',
            ),
            for (final category in categories)
              FilterChipOption<String>(
                key: ValueKey(
                  'stock-take-assign-${member.uid}-${category.id}',
                ),
                value: category.id,
                label: category.name,
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _save(
    TenantSession session,
    TenantPublishedStockTakeSchedule published,
  ) async {
    final writer = widget.writer;
    if (writer == null || _saving) return;
    final assignments = <TenantStockTakeAssignment>[
      for (final entry in _assigned.entries)
        if (entry.value != null)
          TenantStockTakeAssignment(
            uid: entry.key,
            categoryId: entry.value == _everything ? null : entry.value,
          ),
    ];

    final TenantStockTakeScheduleIntent intent;
    try {
      intent = TenantStockTakeSchedulePublisher(
        session: session,
        reader: widget.reader,
      ).buildIntent(
        enforcement: _enforcement ?? TenantStockTakeEnforcement.off,
        weekdays: _selectedWeekdays,
        assignments: assignments,
        published: published,
      );
    } on TenantStockTakeScheduleException catch (error) {
      showAppSnackBar(context, _refusal(error.code));
      return;
    }

    setState(() => _saving = true);
    try {
      final result = await writer.merge(
        path: intent.path,
        data: intent.documentData(),
      );
      if (!mounted) return;
      showAppSnackBar(context, _outcome(result.kind));
      if (result.kind != TenantConfigurationWriteKind.rejected &&
          result.kind != TenantConfigurationWriteKind.unavailable) {
        widget.onChanged?.call();
        // **The form keeps what was just saved, and does not re-read.** It used
        // to clear `_loaded` and bump the generation, which re-seeded from a
        // fresh load - and the guard answers from cache first, so the cached
        // copy still holding the pre-save value won the race and the form blanked
        // itself. A save that looks discarded is worse than a stale one, and the
        // form already holds exactly what the server now has.
        setState(() => _saved = TenantPublishedStockTakeSchedule.published(
          intent.schedule,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  AppNotice _refusal(String code) => switch (code) {
    'no_days_chosen' => const AppNotice.refused(
      'Choose at least one day, or set this to Nothing. A rota with no days '
      'would read as switched on and behave as switched off.',
    ),
    'nobody_assigned' => const AppNotice.refused(
      'Choose who counts, or set this to Nothing.',
    ),
    'duplicate_assignment' => const AppNotice.refused(
      'Somebody is down for the same thing twice.',
    ),
    'schedule_unchanged' => const AppNotice.offline(
      'That is already what is set, so nothing was sent.',
    ),
    'stock_take_forbidden' => const AppNotice.refused(
      'You are not allowed to change this, so nothing was sent.',
    ),
    _ => const AppNotice.refused('This could not be saved.'),
  };

  AppNotice _outcome(TenantConfigurationWriteKind kind) => switch (kind) {
    TenantConfigurationWriteKind.committed => const AppNotice.confirmed(
      'Saved. Devices pick this up the next time they open the register.',
    ),
    TenantConfigurationWriteKind.queued => const AppNotice.confirmed(
      'Saved on this device and on its way to the others.',
    ),
    TenantConfigurationWriteKind.rejected => const AppNotice.refused(
      'The server refused this, so nothing changed.',
    ),
    TenantConfigurationWriteKind.ambiguous => const AppNotice.unknown(
      'This has not settled yet. Reopen the screen to see what is stored.',
    ),
    TenantConfigurationWriteKind.unavailable => const AppNotice.offline(
      'This device is offline, so nothing was published.',
    ),
  };
}
