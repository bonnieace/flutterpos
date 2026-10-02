/// Configs → Loyalty: whether customers earn points, and for how much.
///
/// **Two questions, each answered as a sentence.** On or off is the agreed
/// prices tab's select rather than a toggle, for the reason that tab gives: a
/// toggle labelled *Earn points* says so even when the answer is no. The rate
/// is one amount in the business's own money - *one point for every KES 100* -
/// because that is how a shopkeeper would say it to a customer.
library;

import 'package:flutter/material.dart';

import '../checkout/checkout_configuration.dart';
import '../checkout/checkout_configuration_writer.dart';
import '../checkout/checkout_draft.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../ui/buttons.dart';
import '../ui/fields.dart';
import '../ui/money_text.dart';
import '../ui/scaffold.dart';
import '../ui/snackbar.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'customer_loyalty.dart';

/// Everything this panel draws from.
final class TenantLoyaltySettingsData {
  const TenantLoyaltySettingsData({
    required this.published,
    required this.currency,
  });

  final TenantPublishedLoyalty published;

  /// The business's currency code, or null where it could not be read.
  final String? currency;
}

final class TenantLoyaltySettingsPanel extends StatefulWidget {
  const TenantLoyaltySettingsPanel({
    super.key,
    required this.reader,
    this.writer,
  });

  final TenantDataReader reader;

  /// Absent in a build with no writer wired, which renders read-only.
  final TenantConfigurationDocumentWriter? writer;

  @override
  State<TenantLoyaltySettingsPanel> createState() =>
      _TenantLoyaltySettingsPanelState();
}

class _TenantLoyaltySettingsPanelState
    extends State<TenantLoyaltySettingsPanel> {
  final TextEditingController _rate = TextEditingController();
  bool _enabled = false;
  TenantPublishedLoyalty? _seededFrom;
  bool _edited = false;
  bool _saving = false;
  String? _rateError;
  TenantPublishedLoyalty? _saved;

  String? _loaderKey;
  TenantGuardedLoader<TenantLoyaltySettingsData>? _loader;
  TenantGuardedLoader<TenantLoyaltySettingsData>? _loaderCached;

  @override
  void dispose() {
    _rate.dispose();
    super.dispose();
  }

  void _composeLoaders() {
    if (_loaderKey == 'loyalty' && _loader != null) return;
    _loaderKey = 'loyalty';
    _loader = (session) => _read(session, widget.reader);
    final cache = widget.reader.cached;
    _loaderCached = cache == null ? null : (session) => _read(session, cache);
  }

  Future<TenantLoyaltySettingsData> _read(
    TenantSession session,
    TenantDataReader reader,
  ) async {
    final published = await TenantLoyaltyRepository(
      session: session,
      reader: reader,
    ).load();
    String? currency;
    try {
      currency = (await TenantCheckoutConfigurationRepository(
        session: session,
        reader: reader,
      ).load())?.currency;
    } on FormatException {
      currency = null;
    }
    return TenantLoyaltySettingsData(published: published, currency: currency);
  }

  /// Fills the form from what is published until the owner changes something,
  /// as the agreed prices tab does.
  void _seed(TenantPublishedLoyalty published) {
    if (_edited) return;
    final seeded = _seededFrom;
    if (seeded != null &&
        seeded.state == published.state &&
        seeded.published == published.published) {
      return;
    }
    _seededFrom = published;
    _enabled = published.policy.enabled;
    _rate.text = moneyTextOfMinor(published.policy.minorUnitsPerPoint);
  }

  @override
  Widget build(BuildContext context) {
    _composeLoaders();
    return TenantRouteGuard<TenantLoyaltySettingsData>(
      allowedRoles: TenantLoyaltyPublisher.allowedRoles,
      load: _loader!,
      loadCached: _loaderCached,
      denied: const ErrorState(
        status: AppStatus.problem,
        badgeLabel: 'Not allowed',
        statement:
            'Only an owner or administrator may decide how customers earn '
            'points.',
      ),
      builder: _build,
    );
  }

  Widget _build(
    BuildContext context,
    TenantSession session,
    TenantLoyaltySettingsData data,
  ) {
    _seed(data.published);
    final tokens = AppTokens.componentOf(context);
    final readOnly = widget.writer == null;
    final published = _saved ?? data.published;
    final currency = data.currency ?? '';
    final ring = tokens.colors.action.focusRing;
    Widget aligned(Widget child) => Padding(
      padding: EdgeInsets.symmetric(horizontal: ring.width + ring.offset),
      child: child,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (published.state == TenantLoyaltyState.malformed) ...<Widget>[
          aligned(
            const Callout(
              key: ValueKey('loyalty-settings-malformed'),
              status: AppStatus.problem,
              title: 'This setting could not be read',
              message:
                  'Nobody earns points while it stays that way. Saving here '
                  'replaces it.',
            ),
          ),
          SizedBox(height: tokens.density.sectionGap),
        ],
        if (readOnly) ...<Widget>[
          aligned(
            const Callout(
              key: ValueKey('loyalty-settings-read-only'),
              status: AppStatus.info,
              title: 'Read-only on this device',
              message: 'This build cannot publish settings changes.',
            ),
          ),
          SizedBox(height: tokens.density.sectionGap),
        ],
        aligned(const SectionHeading('Loyalty points')),
        SizedBox(height: tokens.spacing.s8),
        aligned(
          Disclosure(
            key: const ValueKey('loyalty-explanation'),
            summary: 'How customers earn points',
            child: Text(
              'A customer chosen at the till earns points on what they spend, '
              'counted when the sale reaches the server. A verified return '
              'takes back what that sale earned. Points cannot be spent yet.',
              style: tokens.density
                  .body(tokens.typography)
                  .copyWith(color: tokens.colors.text.secondary),
            ),
          ),
        ),
        SizedBox(height: tokens.spacing.s16),
        AppSelect<bool>(
          key: const ValueKey('loyalty-enabled'),
          label: 'Customers earn points',
          leading: Icons.loyalty_outlined,
          value: _enabled,
          enabled: !readOnly && !_saving,
          items: const <AppSelectItem<bool>>[
            AppSelectItem<bool>(
              key: ValueKey('loyalty-enabled-no'),
              value: false,
              label: 'No points',
            ),
            AppSelectItem<bool>(
              key: ValueKey('loyalty-enabled-yes'),
              value: true,
              label: 'Earn points on every purchase',
            ),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _edited = true;
              _enabled = value;
            });
          },
        ),
        if (_enabled) ...<Widget>[
          SizedBox(height: tokens.spacing.s12),
          AppTextField(
            key: const ValueKey('loyalty-rate'),
            controller: _rate,
            enabled: !readOnly && !_saving,
            label: currency.isEmpty
                ? 'Spend for one point'
                : 'Spend for one point ($currency)',
            leading: Icons.payments_outlined,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            error: _rateError,
            helper: _rateHelper(currency),
            onChanged: (_) => setState(() {
              _edited = true;
              _rateError = null;
            }),
          ),
        ],
        if (!readOnly) ...<Widget>[
          SizedBox(height: tokens.density.sectionGap),
          AppButton(
            key: const ValueKey('loyalty-settings-save'),
            label: 'Save',
            tier: AppButtonTier.primary,
            loading: _saving,
            expand: true,
            onPressed: _saving ? null : () => _save(session, published),
          ),
        ],
      ],
    );
  }

  String _rateHelper(String currency) {
    final minor = _typedMinor();
    if (minor == null || minor < 1) return 'How much a customer spends to earn one point.';
    final amount = moneyTextOfMinor(minor);
    final money = currency.isEmpty ? amount : '$currency $amount';
    return 'One point for every $money spent.';
  }

  int? _typedMinor() {
    final value = double.tryParse(_rate.text.trim().replaceAll(',', ''));
    if (value == null) return null;
    return checkoutMinorUnitsFromMajor(value);
  }

  Future<void> _save(
    TenantSession session,
    TenantPublishedLoyalty published,
  ) async {
    final writer = widget.writer;
    if (writer == null || _saving) return;
    final minor = _enabled ? _typedMinor() : null;
    if (_enabled && (minor == null || minor < 1)) {
      setState(() => _rateError = 'Enter an amount more than zero.');
      return;
    }
    final TenantLoyaltyIntent intent;
    try {
      intent = TenantLoyaltyPublisher(
        session: session,
        reader: widget.reader,
      ).buildIntent(
        enabled: _enabled,
        minorUnitsPerPoint: minor,
        published: published,
      );
    } on TenantLoyaltyException catch (error) {
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
        setState(() {
          _saved = TenantPublishedLoyalty.published(intent.policy);
          _seededFrom = _saved;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  AppNotice _refusal(String code) => switch (code) {
    'loyalty_unchanged' => const AppNotice.offline(
      'That is already what is set, so nothing was sent.',
    ),
    'loyalty_forbidden' => const AppNotice.refused(
      'You are not allowed to change this, so nothing was sent.',
    ),
    'invalid_rate' => const AppNotice.refused(
      'Enter an amount more than zero for one point.',
    ),
    _ => const AppNotice.refused('This could not be saved.'),
  };

  AppNotice _outcome(TenantConfigurationWriteKind kind) => switch (kind) {
    TenantConfigurationWriteKind.committed => const AppNotice.confirmed(
      'Saved. Sales that reach the server from now on earn at this rate.',
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
