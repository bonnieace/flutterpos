/// Deciding who may sell for a price agreed with the customer.
///
/// **One control per person, and nothing else.** The developer's rulings of
/// 2026-09-29 leave exactly one thing to configure - who - and settle the rest
/// in code: the cashier types the agreed total, a reason is required, and the
/// sale keeps the listed prices beside what was agreed. A setting for any of
/// those would be a way to turn one of them off.
///
/// **Owner and administrator only, which needs no rules change.** The existing
/// `configuration/{documentId}` rule admits exactly those two for writing and
/// every active member for reading, and reading is what the till does.
///
/// **The rows are the stock count rota's**, from `tenant_staff_roster.dart`,
/// so the two settings a business sets per person look and read the same.
library;

import 'package:flutter/material.dart';

import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_staff_directory.dart';
import '../tenancy/tenant_staff_roster.dart';
import '../tenancy/tenant_types.dart';
import '../ui/buttons.dart';
import '../ui/fields.dart';
import '../ui/scaffold.dart';
import '../ui/snackbar.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'checkout_configuration_writer.dart';
import 'checkout_price_agreement.dart';

/// Everything this screen needs to draw one business's policy.
final class TenantPriceAgreementSettingsData {
  const TenantPriceAgreementSettingsData({
    required this.published,
    required this.staff,
    this.staffHasMore = false,
  });

  final TenantPublishedPriceAgreement published;
  final List<TenantStaffSummary> staff;

  /// Whether the staff page stopped short of everybody.
  final bool staffHasMore;
}

final class TenantPriceAgreementSettingsPanel extends StatefulWidget {
  const TenantPriceAgreementSettingsPanel({
    super.key,
    required this.reader,
    this.writer,
    this.onChanged,
  });

  final TenantDataReader reader;

  /// Absent in a build with no writer wired, which renders read-only.
  final TenantConfigurationDocumentWriter? writer;
  final VoidCallback? onChanged;

  /// How many staff one read holds - the stock count rota's figure.
  static const int staffPageSize = 20;

  @override
  State<TenantPriceAgreementSettingsPanel> createState() =>
      _TenantPriceAgreementSettingsPanelState();
}

class _TenantPriceAgreementSettingsPanelState
    extends State<TenantPriceAgreementSettingsPanel> {
  /// Who the form allows, which is what Save publishes.
  final Set<String> _allowed = <String>{};

  /// What the form was last filled from. See [_seed].
  TenantPublishedPriceAgreement? _seededFrom;

  /// Whether the owner has changed anybody's answer, after which the form is
  /// never replaced under them.
  bool _edited = false;
  bool _saving = false;

  /// What this screen last published, so the unchanged check reads the saved
  /// state rather than a read that may lag it.
  TenantPublishedPriceAgreement? _saved;

  @override
  Widget build(BuildContext context) {
    // Memoised for the reason `guard_retention_test.dart` gives: a key on the
    // guard destroys its `State` and blanks the page.
    _composeLoaders('settings');
    return TenantRouteGuard<TenantPriceAgreementSettingsData>(
      allowedRoles: TenantPriceAgreementPublisher.allowedRoles,
      load: _loader!,
      loadCached: _loaderCached,
      denied: const ErrorState(
        status: AppStatus.problem,
        badgeLabel: 'Not allowed',
        statement:
            'Only an owner or administrator may decide who can agree a price.',
      ),
      builder: _build,
    );
  }

  String? _loaderKey;
  TenantGuardedLoader<TenantPriceAgreementSettingsData>? _loader;
  TenantGuardedLoader<TenantPriceAgreementSettingsData>? _loaderCached;

  void _composeLoaders(String key) {
    if (key == _loaderKey && _loader != null) return;
    _loaderKey = key;
    _loader = (session) => _read(session, widget.reader);
    final cache = widget.reader.cached;
    _loaderCached = cache == null ? null : (session) => _read(session, cache);
  }

  Future<TenantPriceAgreementSettingsData> _read(
    TenantSession session,
    TenantDataReader reader,
  ) async {
    final published = await TenantPriceAgreementRepository(
      session: session,
      reader: reader,
    ).load();
    final staff = await TenantStaffDirectoryRepository(
      session: session,
      reader: reader,
    ).loadPage(pageSize: TenantPriceAgreementSettingsPanel.staffPageSize);
    return TenantPriceAgreementSettingsData(
      published: published,
      staff: staff.items,
      staffHasMore: staff.hasMore,
    );
  }

  /// Fills the form from what is published, and again when a newer answer
  /// arrives - until the owner changes something.
  ///
  /// **Not seeded once**, for the reason the stock count page records: the
  /// guard draws this device's copy first and the server's second, and a form
  /// that kept the first would offer an old list back to Save.
  void _seed(TenantPriceAgreementSettingsData data) {
    if (_edited) return;
    final seeded = _seededFrom;
    if (seeded != null && _samePublished(seeded, data.published)) return;
    _seededFrom = data.published;
    _allowed
      ..clear()
      ..addAll(data.published.policy.allowed);
  }

  static bool _samePublished(
    TenantPublishedPriceAgreement a,
    TenantPublishedPriceAgreement b,
  ) => a.state == b.state && a.published == b.published;

  Widget _build(
    BuildContext context,
    TenantSession session,
    TenantPriceAgreementSettingsData data,
  ) {
    _seed(data);
    final tokens = AppTokens.componentOf(context);
    final readOnly = widget.writer == null;
    final published = _saved ?? data.published;
    final seeded = _seededFrom;
    final changedElsewhere =
        _edited && seeded != null && !_samePublished(seeded, published);
    final wide = tokens.layout.isAtLeast(
      MediaQuery.sizeOf(context).width,
      AppBreakpoint.medium,
    );

    final notices = <Widget>[
      if (changedElsewhere)
        const Callout(
          key: ValueKey('price-agreement-settings-changed-elsewhere'),
          status: AppStatus.attention,
          title: 'Changed on another device',
          message:
              'Somebody saved this setting after this page opened. Saving here '
              'replaces what they saved with what is on this page.',
        ),
      if (published.state == TenantPriceAgreementState.malformed)
        const Callout(
          key: ValueKey('price-agreement-settings-malformed'),
          status: AppStatus.problem,
          title: 'This setting could not be read',
          message:
              'Nobody can agree a price while it stays that way, and every '
              'till sells at the listed price. Saving here replaces it.',
        ),
      if (readOnly)
        const Callout(
          key: ValueKey('price-agreement-settings-read-only'),
          status: AppStatus.info,
          title: 'Read-only on this device',
          message: 'This build cannot publish settings changes.',
        ),
    ];

    // A `Column`, not a `ListView`: the Configs tab already scrolls.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final (index, notice) in notices.indexed) ...<Widget>[
          if (index > 0) SizedBox(height: tokens.spacing.s12),
          _aligned(tokens, notice),
        ],
        if (notices.isNotEmpty) SizedBox(height: tokens.density.sectionGap),
        ..._peopleSection(tokens, data, readOnly: readOnly, wide: wide),
        if (!readOnly) ...<Widget>[
          SizedBox(height: tokens.density.sectionGap),
          _saveRow(tokens, session, published, wide: wide),
        ],
      ],
    );
  }

  List<Widget> _peopleSection(
    AppTokens tokens,
    TenantPriceAgreementSettingsData data, {
    required bool readOnly,
    required bool wide,
  }) {
    final colors = tokens.colors;
    final count = _allowed.length;
    final heading = Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        const Expanded(child: SectionHeading('Who can agree a price')),
        SizedBox(width: tokens.spacing.s12),
        Text(
          count == 0
              ? 'Nobody'
              : '$count ${count == 1 ? 'person' : 'people'}',
          key: const ValueKey('price-agreement-count'),
          style: tokens.typography.caption.copyWith(
            color: colors.text.tertiary,
          ),
        ),
      ],
    );
    // What the person chosen here meets at the till, in the till's own words,
    // and what everybody else does - which is the half that makes it safe.
    final explanation = Text(
      'At the register, the people chosen here can press Agree a price, type '
      'the total the customer agreed to and say why. Everybody else sells at '
      'the listed price. The sale keeps the listed prices, the agreed total '
      'and the reason.',
      key: const ValueKey('price-agreement-explanation'),
      style: tokens.density
          .body(tokens.typography)
          .copyWith(color: colors.text.secondary),
    );
    if (data.staff.isEmpty) {
      return <Widget>[
        _aligned(tokens, heading),
        SizedBox(height: tokens.spacing.s8),
        _aligned(tokens, explanation),
        SizedBox(height: tokens.spacing.s12),
        _aligned(
          tokens,
          const EmptyState(
            key: ValueKey('price-agreement-settings-no-staff'),
            title: 'Nobody to choose yet',
            hint: 'Invite the people who work here, then choose who can agree '
                'a price.',
          ),
        ),
      ];
    }
    return <Widget>[
      _aligned(tokens, heading),
      SizedBox(height: tokens.spacing.s8),
      _aligned(tokens, explanation),
      SizedBox(height: tokens.spacing.s12),
      _aligned(
        tokens,
        DecoratedBox(
          key: const ValueKey('price-agreement-people'),
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
                TenantStaffRosterRow(
                  key: ValueKey('price-agreement-row-${member.uid}'),
                  keyPrefix: 'price-agreement',
                  member: member,
                  wide: wide,
                  note: _noteFor(member),
                  control: readOnly
                      ? _answerAsSet(tokens, member)
                      : _choiceFor(member),
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
            key: const ValueKey('price-agreement-staff-truncated'),
            status: AppStatus.info,
            message:
                'The first ${TenantPriceAgreementSettingsPanel.staffPageSize} '
                'people are listed. Anybody after them cannot be chosen from '
                'here, and whether they can agree a price now is kept when you '
                'save.',
          ),
        ),
      ],
    ];
  }

  /// One person's answer, in words either way.
  ///
  /// **A select, not a toggle, and that was measured.** A toggle labelled *Can
  /// agree a price* says so on every row, including the rows where the answer
  /// is no - only its fill and a check mark disagree - and its *on* state is a
  /// full-width mint block, several of them over one Save. The stock count
  /// rota's select states the answer as a sentence, which is what this row is.
  Widget _choiceFor(TenantStaffSummary member) => AppSelect<bool>(
    key: ValueKey('price-agreement-allow-${member.uid}'),
    label: 'Whether ${member.displayName} can agree a price',
    dense: true,
    leading: Icons.handshake_outlined,
    value: _allowed.contains(member.uid),
    items: <AppSelectItem<bool>>[
      AppSelectItem<bool>(
        key: ValueKey('price-agreement-allow-${member.uid}-no'),
        value: false,
        label: _listedPriceOnly,
      ),
      AppSelectItem<bool>(
        key: ValueKey('price-agreement-allow-${member.uid}-yes'),
        value: true,
        label: _canAgree,
      ),
    ],
    onChanged: (value) {
      if (value == null) return;
      setState(() {
        _edited = true;
        if (value) {
          _allowed.add(member.uid);
        } else {
          _allowed.remove(member.uid);
        }
      });
    },
  );

  /// One person's answer, for a build that cannot change it.
  Widget _answerAsSet(AppTokens tokens, TenantStaffSummary member) {
    final allowed = _allowed.contains(member.uid);
    return Row(
      key: ValueKey('price-agreement-as-set-${member.uid}'),
      children: <Widget>[
        Icon(
          Icons.handshake_outlined,
          size: AppButton.iconSize,
          color: tokens.colors.text.tertiary,
        ),
        SizedBox(width: tokens.spacing.s12),
        Expanded(
          child: Text(
            allowed ? _canAgree : _listedPriceOnly,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tokens.density
                .body(tokens.typography)
                .copyWith(
                  color: allowed
                      ? tokens.colors.text.primary
                      : tokens.colors.text.secondary,
                ),
          ),
        ),
      ],
    );
  }

  static const String _canAgree = 'Can agree a price';
  static const String _listedPriceOnly = 'Listed price only';

  /// What a row says under the name when the role line is not the point.
  TenantStaffRosterNote? _noteFor(TenantStaffSummary member) {
    if (!_allowed.contains(member.uid)) return null;
    return switch (member.status) {
      MembershipStatus.inactive => const TenantStaffRosterNote(
        status: AppStatus.attention,
        icon: Icons.warning_amber_rounded,
        text: 'Cannot sign in, so never offered it',
      ),
      MembershipStatus.pending => const TenantStaffRosterNote(
        status: AppStatus.info,
        icon: Icons.info_outline,
        text: 'Offered once they accept the invitation',
      ),
      MembershipStatus.active => null,
    };
  }

  Widget _saveRow(
    AppTokens tokens,
    TenantSession session,
    TenantPublishedPriceAgreement published, {
    required bool wide,
  }) {
    final when = Text(
      'Devices pick this up the next time they open the register.',
      style: tokens.typography.caption.copyWith(
        color: tokens.colors.text.tertiary,
      ),
    );
    final save = AppButton(
      key: const ValueKey('price-agreement-settings-save'),
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
  /// The stock count panel's own arithmetic: every pressable surface stands
  /// `focusRing.width + offset` inside its slot, so everything that is not
  /// pressable takes the same inset and the left edges stay one column.
  static Widget _aligned(AppTokens tokens, Widget child) {
    final ring = tokens.colors.action.focusRing;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: ring.width + ring.offset),
      child: child,
    );
  }

  Future<void> _save(
    TenantSession session,
    TenantPublishedPriceAgreement published,
  ) async {
    final writer = widget.writer;
    if (writer == null || _saving) return;

    final TenantPriceAgreementIntent intent;
    try {
      intent = TenantPriceAgreementPublisher(
        session: session,
        reader: widget.reader,
      ).buildIntent(allowed: _allowed, published: published);
    } on TenantPriceAgreementException catch (error) {
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
        // The form keeps what was just saved and does not re-read, for the
        // reason the stock count panel gives: the guard answers from cache
        // first, and a stale cached copy would blank a save that succeeded.
        setState(() {
          _saved = TenantPublishedPriceAgreement.published(intent.policy);
          _seededFrom = _saved;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  AppNotice _refusal(String code) => switch (code) {
    'policy_unchanged' => const AppNotice.offline(
      'That is already what is set, so nothing was sent.',
    ),
    'price_agreement_forbidden' => const AppNotice.refused(
      'You are not allowed to change this, so nothing was sent.',
    ),
    'invalid_policy' => AppNotice.refused(
      'At most $maximumPriceAgreementPeople people can agree a price.',
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
