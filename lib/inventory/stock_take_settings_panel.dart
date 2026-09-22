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
///
/// **Drawn to `docs/design/stock-counts/`, on 2026-09-21.** The screen is
/// opened to answer one question - on a count day, who gets asked, what
/// happens if they don't count, and is the whole shop covered - and it used to
/// leave the reader to assemble that from three stacked controls:
///
/// - The three choices were a chip strip that stated only the selected one's
///   consequence, and at `compact` it scrolled sideways, so *Hold the
///   register* - the one setting here that can stop a shop trading - could be
///   past the edge of a phone. They are cards now, each stating what it does.
/// - Each person's row was a chip strip of every category, so on a phone what
///   a person counted could be scrolled out of view inside their own row. It
///   is one [AppSelect] now, with the answer always in view.
/// - Nothing said whether the whole shop was covered, and a deactivated
///   member still down for a category looked exactly like anyone else.
///   `stock_take_coverage.dart` reads the rota back category by category.
///
/// **What did not change**: the three reads, the seed, the publisher, the
/// refusals, the outcomes, and every key a test addresses. The option keys
/// moved from the chips onto the cards and the select's items; they are the
/// same strings.
library;

import 'package:flutter/material.dart';

import '../checkout/checkout_configuration_writer.dart';
import '../tenancy/tenant_catalog.dart';
import '../tenancy/tenant_membership_labels.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_staff_directory.dart';
import '../tenancy/tenant_types.dart';
import '../ui/buttons.dart';
import '../ui/choice.dart';
import '../ui/fields.dart';
import '../ui/scaffold.dart';
import '../ui/snackbar.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'stock_take_coverage.dart';
import 'stock_take_schedule.dart';

/// Everything this screen needs to draw one business's counting schedule.
final class TenantStockTakeSettingsData {
  const TenantStockTakeSettingsData({
    required this.published,
    required this.staff,
    required this.categories,
    this.staffHasMore = false,
  });

  final TenantPublishedStockTakeSchedule published;
  final List<TenantStaffSummary> staff;
  final List<TenantCategory> categories;

  /// Whether the staff page stopped short of everybody.
  ///
  /// **Kept, not newly read.** `loadPage` has always answered it; the screen
  /// used to throw it away, so a business with more people than the page holds
  /// could not put the rest on the rota and was never told so.
  final bool staffHasMore;
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

  /// How many staff one read of the rota holds.
  static const int staffPageSize = 20;

  @override
  State<TenantStockTakeSettingsPanel> createState() =>
      _TenantStockTakeSettingsPanelState();
}

/// Monday through Sunday, in the order a week is read.
const List<({int weekday, String label, String name})> _weekdays =
    <({int weekday, String label, String name})>[
      (weekday: DateTime.monday, label: 'Mon', name: 'Monday'),
      (weekday: DateTime.tuesday, label: 'Tue', name: 'Tuesday'),
      (weekday: DateTime.wednesday, label: 'Wed', name: 'Wednesday'),
      (weekday: DateTime.thursday, label: 'Thu', name: 'Thursday'),
      (weekday: DateTime.friday, label: 'Fri', name: 'Friday'),
      (weekday: DateTime.saturday, label: 'Sat', name: 'Saturday'),
      (weekday: DateTime.sunday, label: 'Sun', name: 'Sunday'),
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

  /// The select's value for *Not counting*.
  ///
  /// **Not null, although not counting is the absence of an assignment.** A
  /// `DropdownButton` reads a null value as *nothing selected* and draws its
  /// hint instead of the item, so the absence needs a value the menu can show.
  /// A slash can never be in a document ID, so this can never be a category.
  static const String _notCounting = '/';

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
    ).loadPage(pageSize: TenantStockTakeSettingsPanel.staffPageSize);
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
      staffHasMore: staff.hasMore,
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

  /// The form's rota, in the shape the publisher and the coverage line read.
  List<TenantStockTakeAssignment> get _formAssignments =>
      <TenantStockTakeAssignment>[
        for (final entry in _assigned.entries)
          if (entry.value != null)
            TenantStockTakeAssignment(
              uid: entry.key,
              categoryId: entry.value == _everything ? null : entry.value,
            ),
      ];

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
    final wide = tokens.layout.isAtLeast(
      MediaQuery.sizeOf(context).width,
      AppBreakpoint.medium,
    );

    final notices = <Widget>[
      if (published.state == TenantStockTakeScheduleState.malformed)
        const Callout(
          key: ValueKey('stock-take-settings-malformed'),
          status: AppStatus.problem,
          title: 'This setting could not be read',
          message:
              'Nobody is being asked to count while it stays that way, and '
              'the register is unaffected. Choosing below replaces it.',
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
    ];

    // A `Column`, not a `ListView`: `TenantSettingPage` wraps every setting in
    // the scroll view and the page inset its own route used to supply, so a
    // second scrollable here would nest one inside another.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final (index, notice) in notices.indexed) ...<Widget>[
          if (index > 0) SizedBox(height: tokens.spacing.s12),
          _aligned(tokens, notice),
        ],
        if (notices.isNotEmpty) SizedBox(height: tokens.density.sectionGap),
        ..._enforcementSection(tokens, enforcement, readOnly: readOnly),
        SizedBox(height: tokens.density.sectionGap),
        ..._daysSection(tokens, readOnly: readOnly),
        SizedBox(height: tokens.density.sectionGap),
        ..._rotaSection(
          tokens,
          data,
          published,
          enforcement,
          readOnly: readOnly,
          wide: wide,
        ),
        if (!readOnly) ...<Widget>[
          SizedBox(height: tokens.density.sectionGap),
          _saveRow(tokens, session, published, wide: wide),
        ],
      ],
    );
  }

  // -------------------------------------------------------------------------
  // What happens when a count is due
  // -------------------------------------------------------------------------

  List<Widget> _enforcementSection(
    AppTokens tokens,
    TenantStockTakeEnforcement enforcement, {
    required bool readOnly,
  }) => <Widget>[
    _aligned(tokens, const SectionHeading('What happens when a count is due')),
    SizedBox(height: tokens.spacing.s12),
    _aligned(
      tokens,
      enabled: readOnly,
      ChoiceCardGroup<TenantStockTakeEnforcement>(
        key: const ValueKey('stock-take-enforcement'),
        semanticLabel: 'What happens when a count is due',
        selected: enforcement,
        onSelected: readOnly
            ? null
            : (value) => setState(() => _enforcement = value),
        options: const <ChoiceCardOption<TenantStockTakeEnforcement>>[
          ChoiceCardOption<TenantStockTakeEnforcement>(
            key: ValueKey('stock-take-enforcement-off'),
            value: TenantStockTakeEnforcement.off,
            title: 'Nothing',
            description:
                'The rota below is recorded and nobody is interrupted.',
            detailIcon: Icons.point_of_sale_outlined,
            detail: <ChoiceDetailRun>[
              ChoiceDetailRun(
                'At the register: the till opens as it always does.',
              ),
            ],
          ),
          // The two register lines quote `stock_take_gate.dart`: what a person
          // who owes a count actually meets, in the words they meet it in.
          ChoiceCardOption<TenantStockTakeEnforcement>(
            key: ValueKey('stock-take-enforcement-prompt'),
            value: TenantStockTakeEnforcement.prompt,
            title: 'Ask at the register',
            description:
                'Whoever owes a count is asked once when they open the '
                'register, and may carry on selling.',
            detailIcon: Icons.point_of_sale_outlined,
            detail: <ChoiceDetailRun>[
              ChoiceDetailRun('At the register: '),
              ChoiceDetailRun('A stock count is due', emphasis: true),
              ChoiceDetailRun(', with '),
              ChoiceDetailRun('Not now', emphasis: true),
              ChoiceDetailRun(' and '),
              ChoiceDetailRun('Start counting', emphasis: true),
              ChoiceDetailRun('.'),
            ],
          ),
          // The sentence that matters, because this is the setting that can
          // stop a shop trading.
          ChoiceCardOption<TenantStockTakeEnforcement>(
            key: ValueKey('stock-take-enforcement-block'),
            value: TenantStockTakeEnforcement.block,
            title: 'Hold the register',
            description:
                'Whoever owes a count cannot sell until they have handed it in. '
                'Handing it in is enough - they do not wait for anybody to '
                'approve it, and it works with no connection.',
            detailIcon: Icons.point_of_sale_outlined,
            detail: <ChoiceDetailRun>[
              ChoiceDetailRun('At the register: '),
              ChoiceDetailRun('Count first, then sell', emphasis: true),
              ChoiceDetailRun(', in place of the till.'),
            ],
          ),
        ],
      ),
    ),
  ];

  // -------------------------------------------------------------------------
  // Which days
  // -------------------------------------------------------------------------

  List<Widget> _daysSection(AppTokens tokens, {required bool readOnly}) {
    if (readOnly) {
      final chosen = <String>[
        for (final day in _weekdays)
          if (_selectedWeekdays.contains(day.weekday)) day.name,
      ];
      return <Widget>[
        _aligned(tokens, const SectionHeading('Which days')),
        SizedBox(height: tokens.spacing.s8),
        _aligned(
          tokens,
          Text(
            chosen.isEmpty ? 'No days chosen' : _joined(chosen, 'and'),
            key: const ValueKey('stock-take-days-as-set'),
            style: tokens.density
                .body(tokens.typography)
                .copyWith(color: tokens.colors.text.primary),
          ),
        ),
      ];
    }
    return <Widget>[
      _aligned(tokens, const SectionHeading('Which days')),
      SizedBox(height: tokens.spacing.s12),
      // **No gap is added between the toggles.** Each carries the focus-ring
      // gutter `PressSurface` reserves on every side, so two neighbours already
      // stand `space.8` apart - and on a phone, seven across with any more than
      // that would take the width their labels need.
      Semantics(
        container: true,
        label: 'Which days',
        explicitChildNodes: true,
        child: Row(
          children: <Widget>[
            for (final day in _weekdays)
              Expanded(
                child: AppToggleButton(
                  key: ValueKey('stock-take-weekday-${day.weekday}'),
                  label: day.label,
                  semanticLabel: day.name,
                  selected: _selectedWeekdays.contains(day.weekday),
                  onChanged: (_) => setState(() {
                    if (!_selectedWeekdays.remove(day.weekday)) {
                      _selectedWeekdays.add(day.weekday);
                    }
                  }),
                ),
              ),
          ],
        ),
      ),
    ];
  }

  // -------------------------------------------------------------------------
  // Who counts what
  // -------------------------------------------------------------------------

  List<Widget> _rotaSection(
    AppTokens tokens,
    TenantStockTakeSettingsData data,
    TenantPublishedStockTakeSchedule published,
    TenantStockTakeEnforcement enforcement, {
    required bool readOnly,
    required bool wide,
  }) {
    final coverage = StockTakeCoverage.of(
      enforcement: enforcement,
      categories: data.categories,
      staff: data.staff,
      assignments: _formAssignments,
    );
    final heading = Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        const Expanded(child: SectionHeading('Who counts what')),
        if (coverage.showsCount && data.staff.isNotEmpty) ...<Widget>[
          SizedBox(width: tokens.spacing.s12),
          Text(
            coverage.countLabel,
            key: const ValueKey('stock-take-coverage-count'),
            style: tokens.typography.caption.copyWith(
              color: tokens.colors.text.tertiary,
            ),
          ),
        ],
      ],
    );
    if (data.staff.isEmpty) {
      return <Widget>[
        _aligned(tokens, heading),
        SizedBox(height: tokens.spacing.s12),
        _aligned(
          tokens,
          const EmptyState(
            key: ValueKey('stock-take-settings-no-staff'),
            title: 'Nobody to ask yet',
            hint: 'Invite the people who work here, then set the rota.',
          ),
        ),
      ];
    }
    final colors = tokens.colors;
    final names = tenantCategoryNames(data.categories);
    final listings = _listingsByUid(published);
    return <Widget>[
      _aligned(tokens, heading),
      SizedBox(height: tokens.spacing.s12),
      _aligned(
        tokens,
        Callout(
          key: const ValueKey('stock-take-coverage'),
          status: coverage.status,
          // `attention`'s own glyph is a clock, which means *waiting*. Nothing
          // here is waiting: a category is down to somebody who will never be
          // asked, and the warning glyph says that.
          icon: coverage.kind == StockTakeCoverageKind.unreachable
              ? Icons.warning_amber_rounded
              : null,
          title: coverage.title,
          message: coverage.message,
        ),
      ),
      SizedBox(height: tokens.spacing.s12),
      _aligned(
        tokens,
        DecoratedBox(
          key: const ValueKey('stock-take-rota'),
          decoration: BoxDecoration(
            color: colors.surface.raised,
            borderRadius: BorderRadius.circular(tokens.radius.lg),
            border: Border.all(color: colors.surface.cardEdge),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final (index, member) in data.staff.indexed) ...<Widget>[
                if (index > 0)
                  Divider(height: 1, color: colors.surface.borderSubtle),
                _RotaRow(
                  key: ValueKey('stock-take-row-${member.uid}'),
                  member: member,
                  wide: wide,
                  note: _noteFor(member, names, listings),
                  control: readOnly
                      ? _assignedAsSet(tokens, member, names)
                      : _choiceFor(member, data.categories, names),
                ),
              ],
            ],
          ),
        ),
      ),
      if (data.staffHasMore) ...<Widget>[
        SizedBox(height: tokens.spacing.s12),
        _aligned(
          tokens,
          Callout(
            key: const ValueKey('stock-take-staff-truncated'),
            status: AppStatus.info,
            message:
                'The first ${TenantStockTakeSettingsPanel.staffPageSize} '
                'people are listed. Anybody after them cannot be put on the '
                'rota from here, and whatever they are down for now is kept '
                'when you save.',
          ),
        ),
      ],
    ];
  }

  /// One person's select: *Not counting*, *Everything*, then every category.
  Widget _choiceFor(
    TenantStaffSummary member,
    List<TenantCategory> categories,
    Map<String, String> names,
  ) {
    final current = _assigned[member.uid];
    final value = current ?? _notCounting;
    // **A category this screen cannot list still has to be a choice.** A
    // `DropdownButton` asserts that exactly one item carries its value, so an
    // assignment to a category past the scan - or one that cannot be read -
    // would throw here. It is shown in the catalog's own words for that case,
    // and saving keeps it, exactly as the chip strip silently did.
    final unlisted =
        current != null &&
        current != _everything &&
        !names.containsKey(current);
    return AppSelect<String>(
      key: ValueKey('stock-take-assign-${member.uid}'),
      label: 'What ${member.displayName} counts',
      dense: true,
      leading: Icons.assignment_outlined,
      value: value,
      items: <AppSelectItem<String>>[
        AppSelectItem<String>(
          key: ValueKey('stock-take-assign-${member.uid}-none'),
          value: _notCounting,
          label: 'Not counting',
        ),
        AppSelectItem<String>(
          key: ValueKey('stock-take-assign-${member.uid}-all'),
          value: _everything,
          label: 'Everything',
        ),
        for (final category in categories)
          AppSelectItem<String>(
            key: ValueKey('stock-take-assign-${member.uid}-${category.id}'),
            value: category.id,
            label: category.name,
          ),
        if (unlisted)
          AppSelectItem<String>(
            key: ValueKey('stock-take-assign-${member.uid}-$current'),
            value: current,
            label: unlistedTenantCategoryLabel,
          ),
      ],
      onChanged: (choice) {
        if (choice == null) return;
        setState(
          () => _assigned[member.uid] = choice == _notCounting ? null : choice,
        );
      },
    );
  }

  /// One person's answer, for a build that cannot change it.
  Widget _assignedAsSet(
    AppTokens tokens,
    TenantStaffSummary member,
    Map<String, String> names,
  ) {
    final current = _assigned[member.uid];
    final counting = current != null;
    return Row(
      key: ValueKey('stock-take-assigned-${member.uid}'),
      children: <Widget>[
        Icon(
          Icons.assignment_outlined,
          size: AppButton.iconSize,
          color: tokens.colors.text.tertiary,
        ),
        SizedBox(width: tokens.spacing.s12),
        Expanded(
          child: Text(
            _scopeLabel(current, names) ?? 'Not counting',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tokens.density
                .body(tokens.typography)
                .copyWith(
                  color: counting
                      ? tokens.colors.text.primary
                      : tokens.colors.text.secondary,
                ),
          ),
        ),
      ],
    );
  }

  /// What a row says under the name when the role line is not the point.
  _RotaNote? _noteFor(
    TenantStaffSummary member,
    Map<String, String> names,
    Map<String, List<String?>> listings,
  ) {
    final current = _assigned[member.uid];
    final counting = current != null;
    // A deactivated person still on the rota is the one fault a row carries.
    if (member.status == MembershipStatus.inactive && counting) {
      return const _RotaNote(
        status: AppStatus.attention,
        icon: Icons.warning_amber_rounded,
        text: 'Never asked - cannot sign in',
      );
    }
    // Only a hand-edited document lists a person twice. Name what saving will
    // drop, which is every listing but the one this form now holds.
    final listed = listings[member.uid];
    if (listed != null && listed.length > 1) {
      final dropped = <String>[
        for (final listing in listed)
          if ((listing ?? _everything) != current)
            _scopeLabel(listing ?? _everything, names) ?? '',
      ];
      if (dropped.isNotEmpty) {
        return _RotaNote(
          status: AppStatus.attention,
          icon: Icons.warning_amber_rounded,
          text:
              '${counting ? 'Also listed' : 'Listed'} for '
              '${_joined(dropped, 'and')} - saving drops '
              '${dropped.length == 1 ? 'it' : 'them'}',
        );
      }
    }
    if (member.status == MembershipStatus.pending && counting) {
      return const _RotaNote(
        status: AppStatus.info,
        icon: Icons.info_outline,
        text: 'Asked once they accept the invitation',
      );
    }
    if (current != null &&
        current != _everything &&
        !names.containsKey(current)) {
      return const _RotaNote(
        status: AppStatus.info,
        icon: Icons.info_outline,
        text: 'Kept as it is when you save',
      );
    }
    return null;
  }

  /// Every listing the published document holds, by person, in order.
  Map<String, List<String?>> _listingsByUid(
    TenantPublishedStockTakeSchedule published,
  ) {
    final listings = <String, List<String?>>{};
    for (final assignment in published.schedule.assignments) {
      listings
          .putIfAbsent(assignment.uid, () => <String?>[])
          .add(assignment.categoryId);
    }
    return listings;
  }

  /// A scope in the words the select uses for it, or null for not counting.
  static String? _scopeLabel(String? scope, Map<String, String> names) {
    if (scope == null) return null;
    if (scope == _everything) return 'Everything';
    return names[scope] ?? unlistedTenantCategoryLabel;
  }

  // -------------------------------------------------------------------------
  // Save
  // -------------------------------------------------------------------------

  Widget _saveRow(
    AppTokens tokens,
    TenantSession session,
    TenantPublishedStockTakeSchedule published, {
    required bool wide,
  }) {
    // The committed notice's own second half, stated before the tap: a change
    // made now does not free somebody the register is already holding.
    final when = Text(
      'Devices pick this up the next time they open the register.',
      style: tokens.typography.caption.copyWith(
        color: tokens.colors.text.tertiary,
      ),
    );
    final save = AppButton(
      key: const ValueKey('stock-take-settings-save'),
      label: 'Save',
      tier: AppButtonTier.primary,
      loading: _saving,
      expand: !wide,
      onPressed: _saving ? null : () => _save(session, published),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _aligned(
          tokens,
          Divider(height: 1, color: tokens.colors.surface.borderSubtle),
        ),
        SizedBox(height: tokens.spacing.s16),
        if (wide)
          Row(
            children: <Widget>[
              Expanded(child: _aligned(tokens, when)),
              SizedBox(width: tokens.spacing.s16),
              save,
            ],
          )
        else ...<Widget>[
          _aligned(tokens, when),
          SizedBox(height: tokens.spacing.s12),
          save,
        ],
      ],
    );
  }

  /// Lines a block up with the pressable controls around it.
  ///
  /// **Every pressable surface stands `focusRing.width + offset` inside its
  /// slot**, because `PressSurface` reserves the ring's gutter whether it is
  /// drawn or not. The cards, the day toggles and Save therefore sit that far
  /// in from the column, and a heading, callout or card that did not would
  /// start that far out from them - the left edges of one column on two lines.
  /// Everything that is not pressable takes the same inset instead.
  ///
  /// [enabled] false returns [child] unchanged, for a block that is pressable
  /// in one state and not another.
  static Widget _aligned(
    AppTokens tokens,
    Widget child, {
    bool enabled = true,
  }) {
    if (!enabled) return child;
    final ring = tokens.colors.action.focusRing;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: ring.width + ring.offset),
      child: child,
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

  Future<void> _save(
    TenantSession session,
    TenantPublishedStockTakeSchedule published,
  ) async {
    final writer = widget.writer;
    if (writer == null || _saving) return;
    final assignments = _formAssignments;

    final TenantStockTakeScheduleIntent intent;
    try {
      intent =
          TenantStockTakeSchedulePublisher(
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
        setState(
          () => _saved = TenantPublishedStockTakeSchedule.published(
            intent.schedule,
          ),
        );
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

/// `Monday and Thursday`; `Paint, Plumbing and Electrical`.
String _joined(List<String> items, String conjunction) {
  if (items.length <= 1) return items.join();
  return '${items.take(items.length - 1).join(', ')} $conjunction '
      '${items.last}';
}

/// A line under a person's name that is about their place on the rota.
@immutable
final class _RotaNote {
  const _RotaNote({
    required this.status,
    required this.icon,
    required this.text,
  });

  final AppStatus status;
  final IconData icon;
  final String text;
}

/// One person on the rota: who they are, whether they can be asked, and what
/// they count.
///
/// **Wide, the control ends the row; compact, it goes under the name.** Seven
/// people down a phone with a select squeezed beside each name would cut the
/// names or the categories, and both are the answer. Under the name, aligned
/// with it, the select has the row's whole width.
final class _RotaRow extends StatelessWidget {
  const _RotaRow({
    super.key,
    required this.member,
    required this.wide,
    required this.control,
    this.note,
  });

  final TenantStaffSummary member;
  final bool wide;
  final Widget control;
  final _RotaNote? note;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final deactivated = member.status == MembershipStatus.inactive;
    final standing = switch (member.status) {
      MembershipStatus.pending => (label: 'Invited', icon: Icons.mail_outline),
      MembershipStatus.inactive => (label: 'Deactivated', icon: Icons.block),
      MembershipStatus.active => null,
    };
    final caption = tokens.typography.caption;
    final line = note;

    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Flexible(
              child: Text(
                member.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens.typography.bodyLarge.copyWith(
                  // Stepped back, not hidden: who is listed does not change.
                  color: deactivated
                      ? colors.text.secondary
                      : colors.text.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (standing != null) ...<Widget>[
              SizedBox(width: tokens.spacing.s8),
              // Neutral: whether an invitation is in trouble is the Staff
              // screen's question. Here it only matters that it is one.
              StatusBadge(
                key: ValueKey('stock-take-standing-${member.uid}'),
                status: AppStatus.neutral,
                icon: standing.icon,
                label: standing.label,
              ),
            ],
          ],
        ),
        SizedBox(height: tokens.spacing.s4),
        if (line != null)
          Row(
            key: ValueKey('stock-take-note-${member.uid}'),
            children: <Widget>[
              Icon(
                line.icon,
                size: StatusBadge.iconSize,
                color: line.status.role(tokens).fg,
              ),
              SizedBox(width: tokens.spacing.s4),
              Flexible(
                child: Text(
                  line.text,
                  style: caption.copyWith(color: line.status.role(tokens).fg),
                ),
              ),
            ],
          )
        else
          Text(
            tenantRoleLabel(member.role),
            style: caption.copyWith(color: colors.text.tertiary),
          ),
      ],
    );

    final who = Row(
      children: <Widget>[
        _RotaAvatar(member: member),
        SizedBox(width: tokens.spacing.s12),
        Expanded(child: identity),
      ],
    );

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.s16,
        vertical: tokens.spacing.s12,
      ),
      child: wide
          ? Row(
              children: <Widget>[
                // Three to two: the name and its line get the larger share,
                // and the select gets what a category name needs.
                Expanded(flex: 3, child: who),
                SizedBox(width: tokens.spacing.s12),
                Expanded(flex: 2, child: control),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                who,
                SizedBox(height: tokens.spacing.s8),
                Padding(
                  padding: EdgeInsets.only(
                    left: _RotaAvatar.size + tokens.spacing.s12,
                  ),
                  child: control,
                ),
              ],
            ),
    );
  }
}

/// A member's initials inside their identity ring.
///
/// **The Staff list's own treatment and figures**, redrawn rather than shared
/// because that avatar is private to `tenant_staff_directory.dart`: initials in
/// primary ink on `surface.field`, with `accent.identity` as a two-pixel ring,
/// which is what passes §9 where a filled block did not. A deactivated member's
/// ring steps down to `border.strong`, the one change a row makes to say they
/// have left.
final class _RotaAvatar extends StatelessWidget {
  const _RotaAvatar({required this.member});

  final TenantStaffSummary member;

  /// The Staff list's row size.
  static const double size = 40;

  /// The Staff list's ring.
  static const double ringWidth = 2;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final ring = member.status == MembershipStatus.inactive
        ? tokens.colors.surface.borderStrong
        : tokens.colors.accent.identityFor(member.uid);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tokens.colors.surface.field,
          borderRadius: BorderRadius.circular(tokens.radius.lg),
          border: Border.all(color: ring, width: ringWidth),
        ),
        child: Text(
          _initials(member.displayName),
          style: tokens.typography.labelLarge.copyWith(
            color: tokens.colors.text.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  static String _initials(String name) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    final first = words.first.characters.first;
    final last = words.length > 1 ? words.last.characters.first : '';
    return '$first$last'.toUpperCase();
  }
}
