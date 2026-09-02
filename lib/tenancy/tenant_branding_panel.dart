/// The screen a business names itself on.
///
/// **What it decides.** The title on the home, and the header printed at the
/// top of every receipt. Both have read `configuration/branding` since the
/// beginning and neither has ever had anything to read, because nothing in this
/// product could write it.
///
/// **A logo is an address, not an upload, in this pass.** `storage.rules`
/// permits exactly one path - `tenantProductImages/{tenantId}/{productId}/…` -
/// so uploading a logo needs a rules change and a second image store, and
/// neither is worth holding the name and the receipt header hostage to. An
/// HTTPS address is accepted and validated to the same rule `TenantBranding`
/// applies when it reads the document back, so a logo that publishes is a logo
/// that loads.
library;

import 'package:flutter/material.dart';

import '../checkout/checkout_configuration_writer.dart';
import '../ui/buttons.dart';
import '../ui/fields.dart';
import '../ui/scaffold.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'tenant_branding_writer.dart';
import 'tenant_repository.dart';
import 'tenant_route_guard.dart';
import 'tenant_session.dart';

/// The guarded route.
final class TenantBrandingScreen extends StatelessWidget {
  const TenantBrandingScreen({super.key, required this.reader, this.writer});

  final TenantDataReader reader;

  /// Absent, the screen reads and refuses to publish - which is what a build
  /// with no Firestore behind it, and a test, both want.
  final TenantConfigurationDocumentWriter? writer;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Business details',
    contentWidth: AppContentWidth.reading,
    body: TenantBrandingPanel(reader: reader, writer: writer),
  );
}

final class TenantBrandingPanel extends StatefulWidget {
  const TenantBrandingPanel({super.key, required this.reader, this.writer});

  final TenantDataReader reader;
  final TenantConfigurationDocumentWriter? writer;

  @override
  State<TenantBrandingPanel> createState() => _TenantBrandingPanelState();
}

class _TenantBrandingPanelState extends State<TenantBrandingPanel> {
  final _companyName = TextEditingController();
  final _slogan = TextEditingController();
  final _logoUrl = TextEditingController();

  /// Whether the fields have been filled from what is published.
  ///
  /// **Once per load, not on every build.** Overwriting the fields underneath
  /// somebody who is typing is the defect this flag exists to prevent.
  bool _seeded = false;

  AppNotice? _notice;
  bool _saving = false;
  int _generation = 0;

  @override
  void dispose() {
    _companyName.dispose();
    _slogan.dispose();
    _logoUrl.dispose();
    super.dispose();
  }

  void _seed(TenantPublishedBranding published) {
    if (_seeded) return;
    _seeded = true;
    final branding = published.branding;
    if (branding == null) return;
    _companyName.text = branding.companyName;
    _slogan.text = branding.slogan ?? '';
    _logoUrl.text = branding.logoUrl?.toString() ?? '';
  }

  Future<void> _publish(
    TenantSession session,
    TenantPublishedBranding published,
  ) async {
    final writer = widget.writer;
    if (_saving || writer == null) return;

    final TenantBrandingUpdateIntent intent;
    try {
      intent = TenantBrandingPublisher(session: session, reader: widget.reader)
          .buildUpdateIntent(
            companyName: _companyName.text,
            slogan: _slogan.text,
            logoUrl: _logoUrl.text,
            published: published,
          );
    } on TenantBrandingException catch (error) {
      setState(
        () => _notice = AppNotice.refused(tenantBrandingFailureMessage(error)),
      );
      return;
    }

    setState(() {
      _saving = true;
      _notice = null;
    });
    final result = await writer.merge(
      path: intent.path,
      data: intent.toDocument(),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _notice = switch (result.kind) {
        TenantConfigurationWriteKind.queued => const AppNotice.offline(
          'Saved on this device; waiting to sync.',
        ),
        TenantConfigurationWriteKind.committed => const AppNotice.confirmed(
          'Saved. The home and every receipt printed from now on carry these '
          'details.',
        ),
        TenantConfigurationWriteKind.rejected => const AppNotice.refused(
          'The server refused the change, so nothing was saved.',
        ),
        // §2.1's `attention` is "awaiting", which an unknown write is. The page
        // re-reads rather than guessing which way it went.
        TenantConfigurationWriteKind.ambiguous => const AppNotice.unknown(
          'It is not certain whether that saved. The details below have been '
          'read again.',
        ),
        TenantConfigurationWriteKind.unavailable => const AppNotice.offline(
          'This device is offline, so nothing was sent. The details are '
          'unchanged.',
        ),
      };
      if (result.kind != TenantConfigurationWriteKind.rejected) {
        // Re-read after anything that may have landed, including the ambiguous
        // case: the document decides what is published, not this screen.
        _seeded = false;
        _generation++;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final cache = widget.reader.cached;
    return TenantRouteGuard<TenantPublishedBranding>(
      key: ValueKey('branding-$_generation'),
      allowedRoles: TenantBrandingPublisher.allowedRoles,
      load: (session) => TenantBrandingPublisher(
        session: session,
        reader: widget.reader,
      ).loadPublished(),
      loadCached: cache == null
          ? null
          : (session) => TenantBrandingPublisher(
              session: session,
              reader: cache,
            ).loadPublished(),
      denied: const Center(
        child: EmptyState(
          key: ValueKey('branding-denied'),
          title: 'Business details are not shown for this role',
          hint: 'An owner or an administrator can change them.',
        ),
      ),
      loading: const Center(
        child: LoadingState(message: 'Reading the business details'),
      ),
      failure: (context, error) => Center(
        child: ErrorState(
          key: const ValueKey('branding-failure'),
          badgeLabel: 'Not read',
          statement: 'The business details could not be read.',
          stillTrue: 'Nothing has been changed.',
          actions: <Widget>[
            AppButton(
              label: 'Try again',
              tier: AppButtonTier.secondary,
              onPressed: () => setState(() => _generation++),
            ),
          ],
        ),
      ),
      builder: (context, session, published) {
        _seed(published);
        final canPublish =
            TenantBrandingPublisher.canPublishInSession(session) &&
            widget.writer != null;
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (!published.isUsable)
                Padding(
                  padding: EdgeInsets.only(bottom: tokens.spacing.s16),
                  child: const Callout(
                    key: ValueKey('branding-absent'),
                    status: AppStatus.attention,
                    message:
                        'This business has published no details, so the home '
                        'and its receipts carry no name yet.',
                  ),
                ),
              AppTextField(
                key: const ValueKey('branding-company-name'),
                label: 'Business name',
                controller: _companyName,
                placeholder: 'What customers know this shop as',
                helper: 'Printed at the top of every receipt.',
                maxLength: TenantBrandingPublisher.maximumCompanyNameLength,
                textCapitalization: TextCapitalization.words,
                enabled: canPublish && !_saving,
              ),
              SizedBox(height: tokens.spacing.s16),
              AppTextField(
                key: const ValueKey('branding-slogan'),
                label: 'Slogan',
                controller: _slogan,
                placeholder: 'Optional',
                helper: 'One line under the name on a receipt.',
                maxLength: TenantBrandingPublisher.maximumSloganLength,
                enabled: canPublish && !_saving,
              ),
              SizedBox(height: tokens.spacing.s16),
              AppTextField(
                key: const ValueKey('branding-logo-url'),
                label: 'Logo address',
                controller: _logoUrl,
                placeholder: 'https://…',
                helper:
                    'Optional. An https address the app can load the logo '
                    'from.',
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                enabled: canPublish && !_saving,
              ),
              if (_notice case final notice?) ...<Widget>[
                SizedBox(height: tokens.spacing.s16),
                Callout(
                  key: const ValueKey('branding-notice'),
                  status: notice.status,
                  message: notice.message,
                ),
              ],
              SizedBox(height: tokens.spacing.s24),
              AppButton(
                key: const ValueKey('branding-save'),
                label: 'Save details',
                loading: _saving,
                onPressed: canPublish
                    ? () => _publish(session, published)
                    : null,
              ),
            ],
          ),
        );
      },
    );
  }
}
