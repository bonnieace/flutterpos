/// One Settings screen, opening on what is set and what is not.
///
/// **What this replaces was a strip of three words.** *Business details*,
/// *Printer*, *Stock counts*, with nothing to choose between them: each
/// setting's standing lived inside its own tab, drawn by the panel once that
/// tab had been opened, and opening a tab was what issued the read. So which
/// setting was unset, unreadable, or actively stopping the till was invisible
/// until all three had been opened, one at a time.
///
/// The currency was the worst of it. It was not a tab at all - it was the
/// second panel down inside *Business details*, below the logo well, the name
/// field and the slogan field - and what it says when nothing is published is
/// *"no sale can be rung up on any device yet"*, which is the most consequential
/// sentence on the screen under a heading that does not predict it.
///
/// **So the strip is a list, and every row states its own standing.** The
/// currency has a row of its own again; it was merged into *Business details*
/// on 2026-09-13 and the stated objection then was to a tab called *Checkout* -
/// a name for a screen rather than a subject. *Currency* names the subject, and
/// the pressure that made merging attractive was horizontal: a tab strip of
/// three-word labels on a 411-pixel phone. A row costs no horizontal space.
/// Both panels' role lists were owner and administrator already, so nothing is
/// offered to anybody new.
///
/// **This costs one read the screen did not cost before**, and that is a
/// deliberate behaviour change rather than a restyle that smuggled one in. See
/// `tenant_settings_standings.dart` for why it is one query and not four.
/// Passing no [standings] at all is supported and costs nothing: the rows then
/// name their subjects and state no standing.
///
/// **A setting's panel is still built only when that setting is opened.** The
/// lazy tab existed so a panel's document was read on opening and not before;
/// a row that pushes a page keeps that property without needing a widget to
/// enforce it.
///
/// **Nothing about what any setting does, who may change it, or what it says
/// when it refuses is decided here.** Every destination hosts the panel its own
/// route already wrapped in a scaffold, with its own guard and its own role
/// list. `CLAUDE.md` hard rule 1 holds for everything inside a row.
library;

import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../ui/press.dart';
import '../ui/scaffold.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'tenant_session.dart';
import 'tenant_session_controller.dart';
import 'tenant_settings_standings.dart';
import 'tenant_types.dart';

/// One setting on the index, and the panel behind it.
final class TenantSettingsDestination {
  const TenantSettingsDestination({
    required this.settingKey,
    required this.kind,
    required this.icon,
    required this.allowedRoles,
    required this.builder,
    this.ownsScroll = false,
  });

  /// Stable across renames, because the home links to one setting by it.
  final String settingKey;

  /// Which setting this is, which is what its standing is looked up by.
  final TenantSettingKind kind;

  /// The glyph in the row's well.
  final IconData icon;

  /// Who is offered it.
  ///
  /// **The same list the panel's own guard enforces**, and offered here only so
  /// a setting nobody may open is not drawn. The guard inside is still what
  /// decides; this is the menu layer, exactly as the home destinations are.
  final List<TenantRole> allowedRoles;

  final WidgetBuilder builder;

  /// Whether the panel scrolls itself and pads itself, rather than being
  /// scrolled and inset by the page that hosts it.
  ///
  /// **For a panel whose tabs are a `TabBarView`**, which needs a height of
  /// its own and gives each tab its own scroll - the printer's, on 2026-10-05,
  /// so its tabs follow the finger as every other tabbed page's do. A scroll
  /// view round one would hand it an unbounded height.
  final bool ownsScroll;

  /// The word on the row. The kind owns it, so the index and anything else
  /// naming this setting cannot drift apart.
  String get label => kind.label;
}

/// How the index learns each setting's standing.
///
/// Null draws the rows with no standing at all, which is the variant that costs
/// no read - see the library comment.
typedef TenantSettingsStandingsReader =
    Future<Map<TenantSettingKind, TenantSettingStanding>> Function(
      TenantSession session,
    );

final class TenantSettingsScreen extends StatelessWidget {
  const TenantSettingsScreen({
    super.key,
    required this.destinations,
    this.standings,
    this.initialSettingKey,
  });

  final List<TenantSettingsDestination> destinations;

  final TenantSettingsStandingsReader? standings;

  /// Which setting to open directly, so the home can still link to one.
  ///
  /// **It opens the setting itself, not the index scrolled to it.** The home's
  /// *Printer* tile meant "take me to the printer" when it opened a tab, and it
  /// means the same here; pushing the index underneath would put a second Back
  /// between that tile and the home it was pressed from.
  final String? initialSettingKey;

  @override
  Widget build(BuildContext context) {
    final session = TenantSessionScope.of(context).session;
    final visible = <TenantSettingsDestination>[
      for (final destination in destinations)
        if (session != null &&
            session.canAccess(allowedRoles: destination.allowedRoles))
          destination,
    ];

    if (session == null || visible.isEmpty) {
      // The reports hub's answer to the same question, and for the same reason:
      // a role with nothing here is told so, rather than shown an empty strip.
      return const AppScaffold(
        title: 'Settings',
        contentWidth: AppContentWidth.records,
        body: EmptyState(
          key: ValueKey('settings-none'),
          illustration: 'settings-access.svg',
          title: 'Settings unavailable for your role',
          hint: 'Ask an owner or administrator to change settings.',
        ),
      );
    }

    for (final destination in visible) {
      if (destination.settingKey == initialSettingKey) {
        return TenantSettingPage(destination: destination);
      }
    }

    return _TenantSettingsIndex(
      session: session,
      destinations: visible,
      standings: standings,
    );
  }
}

/// One setting, opened.
final class TenantSettingPage extends StatelessWidget {
  const TenantSettingPage({super.key, required this.destination});

  final TenantSettingsDestination destination;

  @override
  Widget build(BuildContext context) => AppScaffold(
    key: ValueKey('setting-page-${destination.settingKey}'),
    title: destination.label,
    contentWidth: AppContentWidth.records,
    // **The scroll view and the page inset are the host's, not the panel's.**
    // Every one of these panels was written to be hosted: the stock take one
    // returns a bare `Column` and says so in a comment - "a second scrollable
    // here would nest one inside another" - and none of them pads itself,
    // because each standalone `…Screen` wrapper supplies exactly this. The tab
    // strip supplied it too. Dropping it when the strip became a list is what
    // put every settings page against the edge of the screen and left a long
    // counting rota with nothing to scroll.
    body: destination.ownsScroll
        ? Builder(builder: destination.builder)
        : SingleChildScrollView(
            padding: EdgeInsets.all(
              AppScaffold.horizontalInset(
                AppTokens.componentOf(context).spacing,
              ),
            ),
            child: Builder(builder: destination.builder),
          ),
  );
}

final class _TenantSettingsIndex extends StatefulWidget {
  const _TenantSettingsIndex({
    required this.session,
    required this.destinations,
    required this.standings,
  });

  final TenantSession session;
  final List<TenantSettingsDestination> destinations;
  final TenantSettingsStandingsReader? standings;

  @override
  State<_TenantSettingsIndex> createState() => _TenantSettingsIndexState();
}

class _TenantSettingsIndexState extends State<_TenantSettingsIndex> {
  Future<Map<TenantSettingKind, TenantSettingStanding>>? _standings;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(covariant _TenantSettingsIndex oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different business is a different set of settings, and a standing read
    // for the previous one must never be drawn against this one.
    if (oldWidget.session.tenantId != widget.session.tenantId) _read();
  }

  void _read() {
    final reader = widget.standings;
    _standings = reader == null ? null : reader(widget.session);
  }

  /// Re-reads on returning from a setting that may have changed it.
  ///
  /// **Only after a push that came back**, so an index nobody has acted on
  /// costs its one read and no more. A saved setting whose row still said the
  /// old thing would be the index's own version of a stale figure.
  Future<void> _open(TenantSettingsDestination destination) async {
    // **The pushed page is given the session scope explicitly.** A route is a
    // new subtree under the `Navigator`, not a child of the widget that pushed
    // it, so the scope the landing route provides below that navigator is not
    // above the panel - and every one of these panels asks for it the moment
    // its guard mounts. `_showBusinessSwitcher` hands its dialog the same
    // controller for the same reason.
    final controller = TenantSessionScope.read(context);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TenantSessionScope(
          controller: controller,
          child: TenantSettingPage(destination: destination),
        ),
      ),
    );
    if (!mounted) return;
    setState(_read);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return AppScaffold(
      title: 'Settings',
      contentWidth: AppContentWidth.records,
      body: _standings == null
          ? _list(context, const <TenantSettingKind, TenantSettingStanding>{})
          : FutureBuilder<Map<TenantSettingKind, TenantSettingStanding>>(
              future: _standings,
              builder: (context, snapshot) {
                // **Only the first read has nothing to draw.** A re-read on
                // returning from a setting keeps the previous standings on
                // screen - `FutureBuilder` carries them while the new future
                // is pending - rather than blanking the list to a spinner and
                // losing its scroll position (#141).
                if (!snapshot.hasData && !snapshot.hasError) {
                  return const LoadingState(
                    key: ValueKey('settings-reading'),
                    message: 'Reading this business’s settings.',
                  );
                }
                // **A failed read draws the rows with no standings**, rather
                // than refusing the screen. Every setting behind them still
                // opens, still reads its own document, and still states its own
                // standing inside - so a summary that could not be read must
                // not stand between a person and the setting they came to
                // change.
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (snapshot.hasError) ...<Widget>[
                      Padding(
                        padding: EdgeInsets.only(bottom: tokens.spacing.s16),
                        child: const Callout(
                          key: ValueKey('settings-standings-unread'),
                          status: AppStatus.info,
                          message:
                              'What each setting currently says could not be '
                              'read. Opening one still shows it.',
                        ),
                      ),
                    ],
                    Expanded(
                      child: _list(
                        context,
                        snapshot.data ??
                            const <TenantSettingKind, TenantSettingStanding>{},
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _list(
    BuildContext context,
    Map<TenantSettingKind, TenantSettingStanding> standings,
  ) {
    final tokens = AppTokens.componentOf(context);
    // **Only a fault that stops the till is raised above the list.** A shop
    // with no printer still records every sale, so the printer's absence stays
    // on its own row; a shop with no currency cannot price anything on any
    // device, which is a different kind of fact and is stated where a person
    // looks first.
    TenantSettingsDestination? blocked;
    TenantSettingStanding? blocking;
    for (final destination in widget.destinations) {
      final standing = standings[destination.kind];
      if (standing != null && standing.blocksTrading) {
        blocked = destination;
        blocking = standing;
        break;
      }
    }
    return ListView(
      key: const ValueKey('settings-index'),
      // `horizontalInset`'s own note: the 20 the list screens use on all four
      // sides. `AppScaffold` pads no body, so a list that passes none sits
      // against the edge of the phone.
      padding: EdgeInsets.all(AppScaffold.horizontalInset(tokens.spacing)),
      children: <Widget>[
        if (blocked != null && blocking != null) ...<Widget>[
          Callout(
            key: const ValueKey('settings-blocking'),
            status: AppStatus.problem,
            title: 'No sale can be rung up on any device.',
            message: blocking.blockingCause ?? blocking.detail,
            action: AppButton(
              key: const ValueKey('settings-blocking-open'),
              label: 'Set the ${blocked.label.toLowerCase()}',
              // The one thing this screen is for while it says this, so it
              // wears the tier that says so.
              tier: AppButtonTier.primary,
              onPressed: () => _open(blocked!),
            ),
          ),
          SizedBox(height: tokens.spacing.s16),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final columns =
                constraints.maxWidth >=
                    tokens.layout.expandedFloor - tokens.spacing.s24 * 2
                ? 2
                : 1;
            final gap = tokens.spacing.s12;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final destination in widget.destinations)
                  SizedBox(
                    width:
                        (constraints.maxWidth - gap * (columns - 1)) / columns,
                    child: _SettingRow(
                      destination: destination,
                      standing: standings[destination.kind],
                      onPressed: () => _open(destination),
                    ),
                  ),
              ],
            );
          },
        ),
        SizedBox(height: tokens.spacing.s16),
        Text(
          key: const ValueKey('settings-audience'),
          'Only an owner or an administrator sees these.',
          style: tokens.typography.caption.copyWith(
            color: tokens.colors.text.tertiary,
          ),
        ),
      ],
    );
  }
}

/// One row: what the setting is, what it currently says, and how to change it.
final class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.destination,
    required this.standing,
    required this.onPressed,
  });

  final TenantSettingsDestination destination;

  /// Null where no standing was read - the rows then name their subjects only.
  final TenantSettingStanding? standing;

  final VoidCallback onPressed;

  /// The glyph well's side. The staff avatar's 48, which is also §9's minimum
  /// target, so the mark beside a row is never smaller than a thing a finger
  /// could be asked to hit.
  static const double wellSize = 48;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final state = standing?.state;
    final fault =
        state == TenantSettingState.awaiting ||
        state == TenantSettingState.unreadable;
    // **The well and the edge take the badge's tier, not the raw state.** An
    // unpublished currency is `awaiting` and wears `problem`, because it is
    // also the reason nothing can be sold - and a row whose badge is red inside
    // an amber edge says two different things about one fact.
    final accent = switch (standing?.status) {
      AppStatus.problem => colors.status.problem.fg,
      AppStatus.attention => colors.status.attention.fg,
      _ => colors.text.secondary,
    };
    final radius = BorderRadius.circular(tokens.radius.lg);
    return PressSurface(
      key: ValueKey('setting-row-${destination.settingKey}'),
      borderRadius: radius,
      onPressed: onPressed,
      // **The wash, not the fill.** This row is a composed surface with a
      // glyph and two lines on it, and `PressSurface` paints an overlay as a
      // `Positioned.fill` - so a container colour here would hide the row
      // completely while it was held. That is the defect
      // `AppActionRole.pressedWash` was written for, found on the home's
      // module cards.
      hoverOverlay: colors.action.secondary.hoverWash(),
      pressedOverlay: colors.action.secondary.pressedWash(),
      fillWidth: true,
      semanticLabel: <String>[
        destination.label,
        if (standing?.badgeLabel case final badge?) badge,
        if (standing?.detail case final detail?) detail,
      ].join('. '),
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.all(tokens.spacing.s16),
        decoration: BoxDecoration(
          color: colors.surface.raised,
          borderRadius: radius,
          border: Border.all(
            color: fault
                ? accent.withValues(alpha: _edge)
                : colors.surface.cardEdge,
          ),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: wellSize,
              height: wellSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.surface.field,
                borderRadius: BorderRadius.circular(tokens.radius.md),
                border: Border.all(
                  color: fault
                      ? accent.withValues(alpha: _edge)
                      : colors.surface.borderSubtle,
                ),
              ),
              child: Icon(destination.icon, size: _glyph, color: accent),
            ),
            SizedBox(width: tokens.spacing.s16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    destination.label,
                    style: tokens.typography.bodyLarge.copyWith(
                      color: colors.text.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (standing?.detail case final detail?) ...<Widget>[
                    SizedBox(height: tokens.spacing.s4),
                    Text(
                      key: ValueKey('setting-detail-${destination.settingKey}'),
                      detail,
                      style: tokens.typography.caption.copyWith(
                        // A fault's sentence is read; a set value's is
                        // referred to. The two are not the same weight.
                        color: fault
                            ? colors.text.secondary
                            : colors.text.tertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (standing?.badgeLabel case final badge?) ...<Widget>[
              SizedBox(width: tokens.spacing.s12),
              StatusBadge(
                key: ValueKey('setting-standing-${destination.settingKey}'),
                label: badge,
                status: standing!.status!,
              ),
            ],
            SizedBox(width: tokens.spacing.s8),
            Icon(
              Icons.chevron_right,
              size: _glyph,
              color: colors.text.tertiary,
            ),
          ],
        ),
      ),
    );
  }

  /// How far a fault tints the edge it marks.
  ///
  /// The status tints' own 30%, which `_ProfoundVerdant.criticalTint30` and its
  /// siblings are written at - quoted here rather than reached for, because a
  /// `const` colour cannot be tinted and these two edges are composed at build.
  static const double _edge = 0.30;

  /// §5.2's named 18 for a glyph beside a label.
  static const double _glyph = 18;
}
