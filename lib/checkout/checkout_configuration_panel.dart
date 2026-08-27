import 'package:flutter/material.dart';

import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../ui/buttons.dart';
import '../ui/dialogs.dart';
import '../ui/fields.dart';
import '../ui/scaffold.dart';
import '../ui/snackbar.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'checkout_configuration.dart';

/// Read-and-publish checkout settings route for the selected tenant.
///
/// This is the one surface in the app that writes `configuration/checkout`, and
/// the till cannot price a draft at all until it has been used once: the catalog
/// cache refresher refuses with `configurationUnavailable` while no usable
/// currency is published, so a business that has never opened this route cannot
/// sell.
final class TenantCheckoutConfigurationScreen extends StatelessWidget {
  const TenantCheckoutConfigurationScreen({
    super.key,
    required this.reader,
    this.writer,
    this.onPublished,
  });

  final TenantDocumentReader reader;

  /// Supplied by the composition root. While it is absent this route is exactly
  /// the read-only statement of what is published, as every other injected
  /// capability in this app behaves.
  final TenantCheckoutConfigurationWriter? writer;

  /// Called after the server acknowledged a change, so the composition root can
  /// ask the sync pass to re-read what this device caches.
  final VoidCallback? onPublished;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Checkout settings',
    contentWidth: AppContentWidth.reading,
    body: SingleChildScrollView(
      // 24 until step 6, which is 4 more than the page header above it uses
      // and read as a form that did not line up with its own title.
      padding: EdgeInsets.all(
        AppScaffold.horizontalInset(AppTokens.componentOf(context).spacing),
      ),
      child: TenantCheckoutConfigurationPanel(
        reader: reader,
        writer: writer,
        onPublished: onPublished,
      ),
    ),
  );
}

/// Shows what a business trades in and publishes a replacement.
///
/// The guard owns authorization and stale-session rejection: a tenant switch
/// during an outstanding read or write discards it before it can update the UI,
/// and the role list is the *write* role list rather than the read one. Every
/// active member may read this document - a till cannot price a sale without it -
/// but a manager has no business deciding its contents, so the whole route is
/// denied rather than shown read-only.
final class TenantCheckoutConfigurationPanel extends StatefulWidget {
  const TenantCheckoutConfigurationPanel({
    super.key,
    required this.reader,
    this.writer,
    this.onPublished,
  });

  final TenantDocumentReader reader;
  final TenantCheckoutConfigurationWriter? writer;
  final VoidCallback? onPublished;

  @override
  State<TenantCheckoutConfigurationPanel> createState() =>
      _TenantCheckoutConfigurationPanelState();
}

final class _TenantCheckoutConfigurationPanelState
    extends State<TenantCheckoutConfigurationPanel> {
  int _generation = 0;
  bool _busy = false;
  AppNotice? _notice;

  /// Reports one write outcome, on the surface its kind belongs to.
  ///
  /// See `noticeIsTransient`: a confirmation withdraws itself, and everything
  /// that names a next step stays where it was drawn.
  void _report(AppNotice notice) {
    if (noticeIsTransient(notice)) {
      showAppSnackBar(context, notice);
      return;
    }
    setState(() => _notice = notice);
  }


  /// Restarts the guarded read, so what is shown is the server's own document
  /// rather than the value that was just typed.
  void _reload() => setState(() => _generation++);

  static String _sessionKey(TenantSession session) =>
      '${session.uid}:${session.tenantId}:${session.epoch}';

  /// Whether the session this work was authorized against is still selected.
  bool _stillCurrent(String capturedKey) {
    if (!mounted) return false;
    final current = TenantSessionScope.of(context).session;
    return current != null && _sessionKey(current) == capturedKey;
  }

  Future<void> _publish(
    TenantSession session,
    TenantPublishedCheckoutConfiguration published,
    String currency,
  ) async {
    final writer = widget.writer;
    if (writer == null || _busy) return;
    final capturedKey = _sessionKey(session);

    // The intent is built before anything is confirmed, so a code this boundary
    // would refuse is reported instead of being asked about, and the sentence in
    // the confirmation describes the write that would actually be issued rather
    // than the text that was typed.
    final TenantCheckoutConfigurationUpdateIntent intent;
    try {
      intent = TenantCheckoutConfigurationPublisher(
        session: session,
        reader: widget.reader,
      ).buildUpdateIntent(currency: currency, published: published);
    } on TenantCheckoutConfigurationException catch (error) {
      _report(_refusalNotice(error.code));
      return;
    }
    if (!await _confirmed(intent) || !_stillCurrent(capturedKey)) return;

    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final result = await writer.publish(intent);
      if (!_stillCurrent(capturedKey)) return;
      _report(_resultNotice(result));
      // A committed change and an unknown one are both re-read: the second
      // because only the server can say what is published, and the first because
      // the document is what a till will price with, not the typed value.
      if (result.kind != TenantCheckoutConfigurationWriteKind.rejected) {
        _reload();
      }
      if (result.kind == TenantCheckoutConfigurationWriteKind.committed) {
        widget.onPublished?.call();
      }
    } on TenantCheckoutConfigurationException catch (error) {
      if (!_stillCurrent(capturedKey)) return;
      _report(_refusalNotice(error.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmed(
    TenantCheckoutConfigurationUpdateIntent intent,
  ) async {
    final replacing = intent.changesPublishedCurrency;
    final previous = intent.replaces.currency;
    final confirmed = await showConfirmDialog(
      context,
      title: replacing ? 'Change the currency?' : 'Publish this currency?',
      consequence: replacing
          ? 'This business trades in $previous today. Sales priced after each '
                'device syncs record ${intent.currency}.'
          : 'Every sale priced after this is published records '
                '${intent.currency}. Until it is published no sale can be '
                'rung up in this business at all.',
      // The one case with something to warn about, and it is §8 rule 6
      // exactly: what is *not* affected. Nothing is converted and nothing is
      // re-priced - a sale carries the code it was priced with inside its own
      // hashed payload, and a device that has not synced keeps pricing with
      // the code it still holds.
      stillTrue: replacing
          ? 'Every sale already recorded keeps that code, no amount is '
                'converted, and a device that has not synced keeps pricing '
                'new sales in $previous until it does.'
          : null,
      confirmLabel: replacing ? 'Change currency' : 'Publish',
      tier: AppButtonTier.primary,
      confirmKey: const ValueKey('checkout-configuration-confirm'),
      cancelKey: const ValueKey('checkout-configuration-cancel'),
    );
    return confirmed && mounted;
  }

  /// One loader per guard key, cached so a `setState` for the busy flag or a
  /// notice does not restart the read and discard the half-typed form.
  TenantGuardedLoader<TenantPublishedCheckoutConfiguration> _loaderFor(
    String key,
  ) {
    if (key == _loaderKey && _loader != null) return _loader!;
    _loaderKey = key;
    return _loader = (session) => TenantCheckoutConfigurationPublisher(
      session: session,
      reader: widget.reader,
    ).loadPublished();
  }

  String? _loaderKey;
  TenantGuardedLoader<TenantPublishedCheckoutConfiguration>? _loader;

  @override
  Widget build(BuildContext context) {
    final guardKey = 'checkout-configuration:$_generation';
    return TenantRouteGuard<TenantPublishedCheckoutConfiguration>(
      key: ValueKey(guardKey),
      allowedRoles: TenantCheckoutConfigurationPublisher.allowedRoles,
      load: _loaderFor(guardKey),
      denied: const Center(
        key: ValueKey('checkout-configuration-denied'),
        child: Text(
          'Only an owner or administrator may change the checkout settings.',
        ),
      ),
      failure: (context, error) => const Center(
        key: ValueKey('checkout-configuration-failure'),
        child: Text('The checkout settings could not be read.'),
      ),
      builder: (context, session, published) => _ConfigurationContents(
        published: published,
        busy: _busy,
        notice: _notice,
        canPublish: widget.writer != null,
        onPublish: (currency) => _publish(session, published, currency),
      ),
    );
  }
}

AppNotice _resultNotice(
  TenantCheckoutConfigurationWriteResult result,
) => switch (result.kind) {
  TenantCheckoutConfigurationWriteKind.committed => const AppNotice.confirmed(
    'Published. This device re-reads it on its next sync, and every other '
    'device picks it up when it syncs.',
  ),
  TenantCheckoutConfigurationWriteKind.rejected => const AppNotice.refused(
    'The change was refused and nothing was published. Only an owner or '
    'administrator may change this.',
  ),
  TenantCheckoutConfigurationWriteKind.ambiguous => const AppNotice.unknown(
    'The result is unknown. This page has been re-read; publishing the same '
    'code again is safe, because this change names one setting and one '
    'value.',
  ),
  TenantCheckoutConfigurationWriteKind.unavailable => const AppNotice.offline(
    'This device is offline, so nothing was published. The checkout '
    'settings can only be changed while online.',
  ),
};

/// **`currency_unchanged` is not a refusal**, and this surface is the one where
/// the difference matters most: the currency the operator wanted published *is*
/// published, so the intent is satisfied. Every other branch is the client
/// refusing before anything was sent.
AppNotice _refusalNotice(String code) => switch (code) {
  'invalid_currency' => const AppNotice.refused(
    'Enter a three-letter ISO 4217 currency code, such as KES or UGX.',
  ),
  'currency_unchanged' => const AppNotice.offline(
    'That is already the published currency.',
  ),
  'configuration_forbidden' => const AppNotice.refused(
    'Only an owner or administrator may change the checkout settings.',
  ),
  _ => const AppNotice.refused('The checkout settings could not be changed.'),
};

/// What every state of this route says about selling.
///
/// The distinction the surface is built around is not whether a document exists
/// but whether a till can price a sale with it. An absent document and a
/// malformed one both stop every sale in the business, and both are cleared by
/// the same act, so they are stated in the same place and in the same terms.
final class _ConfigurationContents extends StatefulWidget {
  const _ConfigurationContents({
    required this.published,
    required this.busy,
    required this.notice,
    required this.canPublish,
    required this.onPublish,
  });

  final TenantPublishedCheckoutConfiguration published;
  final bool busy;
  final AppNotice? notice;
  final bool canPublish;
  final void Function(String currency) onPublish;

  @override
  State<_ConfigurationContents> createState() => _ConfigurationContentsState();
}

final class _ConfigurationContentsState extends State<_ConfigurationContents> {
  final TextEditingController _currency = TextEditingController();

  @override
  void dispose() {
    _currency.dispose();
    super.dispose();
  }

  /// Deliberately only a length check. Which three letters are acceptable is the
  /// publisher's decision, and a refusal from it is reported as a sentence -
  /// disabling the button on the same rule would leave a typo unexplained.
  bool get _canSubmit =>
      widget.canPublish && !widget.busy && _currency.text.trim().length == 3;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final published = widget.published;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading('Currency'),
        SizedBox(height: tokens.spacing.s4),
        Text(
          key: const ValueKey('checkout-configuration-current'),
          switch (published.state) {
            TenantPublishedConfigurationState.published =>
              'This business trades in ${published.currency}.',
            TenantPublishedConfigurationState.absent =>
              'This business has published no currency, so no sale can be rung '
                  'up on any device yet.',
            TenantPublishedConfigurationState.malformed =>
              'The published checkout settings cannot be read, so no sale can '
                  'be rung up on any device. Publishing a currency here '
                  'replaces them.',
          },
        ),
        SizedBox(height: tokens.spacing.s12),
        const Text(
          key: ValueKey('checkout-configuration-scope'),
          'The code is recorded on every sale priced with it and labels every '
          'reported figure. It converts nothing: this app runs no exchange '
          'rate, and no recorded sale is ever re-priced.',
        ),
        if (!widget.canPublish) ...[
          SizedBox(height: tokens.spacing.s12),
          // **A notice, not a sentence, and it was a sentence until 2026-08-22.**
          // This is the state of the build rather than a line of the page's
          // prose, and §2.1 gives `info` the meaning "offline, read-only,
          // informational" - so it wears the container and the glyph its four
          // siblings wear. Untitled, because the two-tier pattern the other five
          // sites already follow reserves a title for the standing of a whole
          // page: `catalog-read-only` and `staff-directory-read-only` carry one,
          // and a single control that is unavailable here does not.
          //
          // It rendered as a bare `Text` for as long as it did because **no
          // capture contained it** - `16-checkout-settings` injects a writer, so
          // the branch never drew in a picture at all.
          // `16b-checkout-settings-read-only` is the repair for that half, and
          // `test/ui/status_test.dart` scans for the pattern so a seventh site
          // cannot invent a seventh rendering.
          const Callout(
            key: ValueKey('checkout-configuration-read-only'),
            status: AppStatus.info,
            message: 'This build cannot change the setting from here.',
          ),
        ] else ...[
          SizedBox(height: tokens.spacing.s16),
          AppTextField(
            key: const ValueKey('checkout-configuration-currency'),
            controller: _currency,
            maxLength: 3,
            enabled: !widget.busy,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() {}),
            label: 'ISO 4217 currency code',
            leading: Icons.payments_outlined,
            helper: 'Three letters, such as KES, UGX, or TZS.',
          ),
          SizedBox(height: tokens.spacing.s12),
          AppButton(
            key: const ValueKey('checkout-configuration-submit'),
            label: published.canSell ? 'Change currency' : 'Publish',
            tier: AppButtonTier.primary,
            onPressed: _canSubmit
                ? () => widget.onPublish(_currency.text)
                : null,
          ),
        ],
        if (widget.notice case final answer?) ...[
          SizedBox(height: tokens.spacing.s16),
          Callout(
            key: const ValueKey('checkout-configuration-notice'),
            status: answer.status,
            message: answer.message,
          ),
        ],
      ],
    );
  }
}
