/// The Email tile: whether receipts go to customers by email, when - and what
/// became of the recent ones.
///
/// **The WhatsApp screen's layout, one choice shorter**
/// (`lib/whatsapp/e_receipt_settings_panel.dart`): the same two tabs, the same
/// switch and timing cards, titles rather than sentences. There is no format
/// to choose - an email carries the whole receipt and the PDF beside it - and
/// no availability check, because email goes through the Brevo account every
/// UzaPay account email already uses.
library;

import 'package:flutter/material.dart';

import '../checkout/checkout_configuration_writer.dart';
import '../observability/app_telemetry.dart';
import '../tenancy/tenancy.dart';
import '../ui/buttons.dart';
import '../ui/card.dart';
import '../ui/choice.dart';
import '../ui/scaffold.dart';
import '../ui/skeleton.dart';
import '../ui/snackbar.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tabs.dart';
import '../ui/tokens.dart';
import '../whatsapp/e_receipt_settings.dart';
import 'email_receipt_delivery.dart';
import 'email_receipt_settings.dart';

/// Everything the screen draws from.
final class TenantEmailReceiptScreenData {
  const TenantEmailReceiptScreenData({
    required this.published,
    required this.businessName,
    required this.deliveries,
    required this.deliveriesReadable,
  });

  final TenantPublishedEmailReceipts published;

  /// The name every receipt comes from, for the preview.
  final String businessName;
  final List<TenantEmailReceiptDelivery> deliveries;

  /// False where the recent receipts could not be read; the settings still can.
  final bool deliveriesReadable;
}

final class TenantEmailReceiptsScreen extends StatefulWidget {
  const TenantEmailReceiptsScreen({
    super.key,
    required this.reader,
    this.writer,
  });

  final TenantDataReader reader;

  /// Absent in a build with no writer wired, which renders read-only.
  final TenantConfigurationDocumentWriter? writer;

  @override
  State<TenantEmailReceiptsScreen> createState() =>
      _TenantEmailReceiptsScreenState();
}

class _TenantEmailReceiptsScreenState extends State<TenantEmailReceiptsScreen> {
  bool _enabled = false;
  EReceiptMode _mode = EReceiptMode.manual;
  TenantPublishedEmailReceipts? _seededFrom;
  TenantPublishedEmailReceipts? _saved;
  bool _edited = false;
  bool _saving = false;

  TenantGuardedLoader<TenantEmailReceiptScreenData>? _loader;
  TenantGuardedLoader<TenantEmailReceiptScreenData>? _loaderCached;

  void _composeLoaders() {
    if (_loader != null) return;
    _loader = (session) => _read(session, widget.reader);
    final cache = widget.reader.cached;
    _loaderCached = cache == null ? null : (session) => _read(session, cache);
  }

  Future<TenantEmailReceiptScreenData> _read(
    TenantSession session,
    TenantDataReader reader,
  ) async {
    final published = await TenantEmailReceiptRepository(
      session: session,
      reader: reader,
    ).load();
    final name = await _BusinessName(session: session, reader: reader).load();
    var deliveries = const <TenantEmailReceiptDelivery>[];
    var readable = true;
    try {
      deliveries = await TenantEmailReceiptDeliveryRepository(
        session: session,
        reader: reader,
      ).loadRecent();
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'email_receipt.deliveries_read',
      );
      readable = false;
    }
    return TenantEmailReceiptScreenData(
      published: published,
      businessName: name,
      deliveries: deliveries,
      deliveriesReadable: readable,
    );
  }

  void _seed(TenantPublishedEmailReceipts published) {
    if (_edited) return;
    final seeded = _seededFrom;
    if (seeded != null &&
        seeded.state == published.state &&
        seeded.published == published.published) {
      return;
    }
    _seededFrom = published;
    final settings = published.settings;
    _enabled = settings.emailEnabled;
    _mode = settings.mode;
  }

  @override
  Widget build(BuildContext context) {
    _composeLoaders();
    return DefaultTabController(
      length: 2,
      child: AppScaffold(
        title: 'Email receipts',
        contentWidth: AppContentWidth.reading,
        body: Column(
          children: <Widget>[
            const AppTabs(
              key: ValueKey('email-receipts-tabs'),
              tabs: <String>['Settings', 'Sent receipts'],
              isScrollable: false,
            ),
            Expanded(
              child: TenantRouteGuard<TenantEmailReceiptScreenData>(
                allowedRoles: TenantEmailReceiptPublisher.allowedRoles,
                load: _loader!,
                loadCached: _loaderCached,
                loading: const LoadingState(message: 'Reading email receipts'),
                denied: const ErrorState(
                  status: AppStatus.problem,
                  badgeLabel: 'Not allowed',
                  statement:
                      'Only an owner or administrator may decide how receipts '
                      'are sent.',
                ),
                failure: (context, error) => const ErrorState(
                  key: ValueKey('email-receipts-failure'),
                  badgeLabel: 'Not read',
                  statement: 'The email receipt settings could not be read.',
                  stillTrue: 'Nothing has been changed.',
                ),
                builder: (context, session, data) {
                  final tokens = AppTokens.componentOf(context);
                  final inset =
                      MediaQuery.sizeOf(context).width <
                          AppLayout.contract.mediumFloor
                      ? tokens.spacing.s16
                      : tokens.spacing.s24;
                  return TabBarView(
                    children: <Widget>[
                      _KeptTab(child: _build(context, session, data, inset)),
                      _KeptTab(
                        child: ListView(
                          key: const ValueKey('email-receipts-sent'),
                          padding: EdgeInsets.all(inset),
                          children: _deliveries(
                            tokens,
                            data,
                            serverPending: switch (TenantReadFreshness.maybeOf(
                              context,
                            )) {
                              final freshness? =>
                                freshness.fromCache && !freshness.stale,
                              null => false,
                            },
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _build(
    BuildContext context,
    TenantSession session,
    TenantEmailReceiptScreenData data,
    double inset,
  ) {
    _seed(data.published);
    final tokens = AppTokens.componentOf(context);
    final readOnly = widget.writer == null;
    final published = _saved ?? data.published;
    final settings = TenantEmailReceiptSettings(
      emailEnabled: _enabled,
      mode: _mode,
    );
    final preview = emailReceiptPreview(data.businessName);
    return ListView(
      key: const ValueKey('email-receipts'),
      padding: EdgeInsets.all(inset),
      children: <Widget>[
        if (published.state == TenantEReceiptState.malformed) ...<Widget>[
          const Callout(
            key: ValueKey('email-receipts-malformed'),
            status: AppStatus.problem,
            title: 'This setting could not be read',
            message:
                'No receipt is sent by email while it stays that way. Saving '
                'here replaces it.',
          ),
          SizedBox(height: tokens.spacing.s16),
        ],
        if (readOnly) ...<Widget>[
          const Callout(
            key: ValueKey('email-receipts-read-only'),
            status: AppStatus.info,
            title: 'Read-only on this device',
            message: 'This build cannot publish settings changes.',
          ),
          SizedBox(height: tokens.spacing.s16),
        ],
        AppSwitchRow(
          key: const ValueKey('email-receipts-enabled'),
          label: 'Email receipts',
          icon: Icons.mail_outline,
          value: _enabled,
          onChanged: readOnly || _saving
              ? null
              : (value) => setState(() {
                  _edited = true;
                  _enabled = value;
                }),
        ),
        SizedBox(height: tokens.spacing.s8),
        Disclosure(
          key: const ValueKey('email-receipts-explanation'),
          summary: 'Where receipts come from',
          child: Text(
            "Receipts come from UzaPay's email address under your business's "
            'name, with the whole receipt in the message and a PDF copy '
            'attached. Every receipt has a link that stops them, and a '
            'customer who uses it gets no more.',
            style: tokens.density
                .body(tokens.typography)
                .copyWith(color: tokens.colors.text.secondary),
          ),
        ),
        if (_enabled) ...<Widget>[
          SizedBox(height: tokens.density.sectionGap),
          const SectionHeading('When it is sent'),
          SizedBox(height: tokens.spacing.s8),
          ChoiceCardGroup<EReceiptMode>(
            key: const ValueKey('email-receipts-mode'),
            semanticLabel: 'When a receipt is sent',
            selected: _mode,
            onSelected: readOnly || _saving
                ? null
                : (value) => setState(() {
                    _edited = true;
                    _mode = value;
                  }),
            options: const <ChoiceCardOption<EReceiptMode>>[
              ChoiceCardOption<EReceiptMode>(
                key: ValueKey('email-receipts-mode-automatic'),
                value: EReceiptMode.automatic,
                icon: Icons.bolt_outlined,
                title: 'Automatically',
              ),
              ChoiceCardOption<EReceiptMode>(
                key: ValueKey('email-receipts-mode-manual'),
                value: EReceiptMode.manual,
                icon: Icons.touch_app_outlined,
                title: 'Only when a cashier sends one',
              ),
            ],
          ),
          SizedBox(height: tokens.density.sectionGap),
          AppCard(
            key: const ValueKey('email-receipts-preview'),
            padding: EdgeInsets.all(tokens.spacing.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'What the customer sees',
                  style: tokens.typography.labelMedium.copyWith(
                    color: tokens.colors.text.secondary,
                  ),
                ),
                SizedBox(height: tokens.spacing.s8),
                Text(
                  preview.from,
                  key: const ValueKey('email-receipts-preview-from'),
                  style: tokens.typography.labelLarge.copyWith(
                    color: tokens.colors.text.primary,
                  ),
                ),
                SizedBox(height: tokens.spacing.s4),
                Text(
                  preview.subject,
                  key: const ValueKey('email-receipts-preview-subject'),
                  style: tokens.typography.bodyMedium.copyWith(
                    color: tokens.colors.text.primary,
                  ),
                ),
                SizedBox(height: tokens.spacing.s8),
                Text(
                  preview.body,
                  key: const ValueKey('email-receipts-preview-text'),
                  style: tokens.typography.bodyMedium.copyWith(
                    color: tokens.colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (!readOnly) ...<Widget>[
          SizedBox(height: tokens.density.sectionGap),
          AppButton(
            key: const ValueKey('email-receipts-save'),
            label: 'Save',
            tier: AppButtonTier.primary,
            loading: _saving,
            expand: true,
            onPressed: _saving
                ? null
                : () => _save(session, published, settings),
          ),
        ],
      ],
    );
  }

  List<Widget> _deliveries(
    AppTokens tokens,
    TenantEmailReceiptScreenData data, {
    required bool serverPending,
  }) {
    if (!data.deliveriesReadable) {
      return const <Widget>[
        Callout(
          key: ValueKey('email-receipts-deliveries-unreadable'),
          status: AppStatus.info,
          message: 'The recent receipts could not be read on this device.',
        ),
      ];
    }
    if (data.deliveries.isEmpty && serverPending) {
      return <Widget>[
        SkeletonGroup(
          key: const ValueKey('email-receipts-deliveries-reading'),
          semanticLabel: 'Reading the recent receipts.',
          child: Column(
            children: <Widget>[
              for (var row = 0; row < _readingRows; row++) ...<Widget>[
                if (row > 0) SizedBox(height: tokens.spacing.s8),
                const _DeliveryRowSkeleton(),
              ],
            ],
          ),
        ),
      ];
    }
    if (data.deliveries.isEmpty) {
      return const <Widget>[
        EmptyState(
          key: ValueKey('email-receipts-deliveries-empty'),
          title: 'No receipts sent yet',
          hint:
              'Each receipt sent by email is listed here with what became of '
              'it.',
          illustration: 'file-search.svg',
        ),
      ];
    }
    return <Widget>[
      for (final (index, delivery) in data.deliveries.indexed) ...<Widget>[
        if (index > 0) SizedBox(height: tokens.spacing.s8),
        _DeliveryRow(delivery: delivery),
      ],
    ];
  }

  Future<void> _save(
    TenantSession session,
    TenantPublishedEmailReceipts published,
    TenantEmailReceiptSettings settings,
  ) async {
    final writer = widget.writer;
    if (writer == null || _saving) return;
    final TenantEmailReceiptSettingsIntent intent;
    try {
      intent = TenantEmailReceiptPublisher(
        session: session,
        reader: widget.reader,
      ).buildIntent(settings: settings, published: published);
    } on TenantEReceiptException catch (error) {
      showAppSnackBar(context, switch (error.code) {
        'e_receipts_unchanged' => const AppNotice.offline(
          'That is already what is set, so nothing was sent.',
        ),
        _ => const AppNotice.refused(
          'You are not allowed to change this, so nothing was sent.',
        ),
      });
      return;
    }
    setState(() => _saving = true);
    try {
      final result = await writer.merge(
        path: intent.path,
        data: intent.documentData(),
      );
      if (!mounted) return;
      showAppSnackBar(context, switch (result.kind) {
        TenantConfigurationWriteKind.committed => AppNotice.confirmed(
          settings.emailEnabled
              ? 'Saved. Tills offer email receipts the next time they open '
                    'the register.'
              : 'Saved. No receipts are sent by email.',
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
      });
      if (result.kind != TenantConfigurationWriteKind.rejected &&
          result.kind != TenantConfigurationWriteKind.unavailable) {
        setState(() {
          _saved = TenantPublishedEmailReceipts.published(settings);
          _seededFrom = _saved;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// What a customer's inbox shows, in the email's own words
/// (`functions/src/emailReceipts/template.ts`), with a made-up receipt.
({String from, String subject, String body}) emailReceiptPreview(
  String businessName,
) => (
  from: '$businessName via UzaPay',
  subject: 'Receipt JOHN-CT-7F2-001 from $businessName',
  body:
      'Thank you for shopping at $businessName. Here is your receipt for '
      'KES 1,250.00. A PDF copy is attached to keep.\n\n'
      '[Receipt-JOHN-CT-7F2-001.pdf]',
);

/// One receipt that was emailed, or was not, and why.
final class _DeliveryRow extends StatelessWidget {
  const _DeliveryRow({required this.delivery});

  final TenantEmailReceiptDelivery delivery;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final status = switch (delivery.status) {
      EmailReceiptDeliveryStatus.sent ||
      EmailReceiptDeliveryStatus.delivered => AppStatus.ok,
      EmailReceiptDeliveryStatus.queued ||
      EmailReceiptDeliveryStatus.sending => AppStatus.info,
      EmailReceiptDeliveryStatus.skipped => AppStatus.neutral,
      EmailReceiptDeliveryStatus.failed => AppStatus.problem,
    };
    final who = delivery.customerName ?? delivery.emailMasked;
    final subject = delivery.receiptNumber == null
        ? who
        : '${delivery.receiptNumber} · $who';
    return DecoratedBox(
      key: ValueKey('email-receipts-delivery-${delivery.id}'),
      decoration: BoxDecoration(
        color: tokens.colors.surface.raised,
        border: Border.all(color: tokens.colors.surface.cardEdge),
        borderRadius: BorderRadius.circular(tokens.radius.md),
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.s12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.typography.labelLarge.copyWith(
                      color: tokens.colors.text.primary,
                    ),
                  ),
                  SizedBox(height: tokens.spacing.s4),
                  Text(
                    delivery.reasonText ??
                        (delivery.automatic
                            ? 'Sent automatically'
                            : 'Sent by hand'),
                    style: tokens.typography.caption.copyWith(
                      color: tokens.colors.text.tertiary,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: tokens.spacing.s8),
            StatusBadge(status: status, label: delivery.status.label),
          ],
        ),
      ),
    );
  }
}

/// Placeholder rows while the recent receipts are read, as on WhatsApp's.
const int _readingRows = 3;

/// A [_DeliveryRow]'s frame with its two lines still arriving.
final class _DeliveryRowSkeleton extends StatelessWidget {
  const _DeliveryRowSkeleton();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.colors.surface.raised,
        border: Border.all(color: tokens.colors.surface.cardEdge),
        borderRadius: BorderRadius.circular(tokens.radius.md),
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SkeletonLine(
              widthFactor: 0.6,
              style: tokens.typography.labelLarge,
              tone: SkeletonTone.onRaised,
            ),
            SizedBox(height: tokens.spacing.s4),
            SkeletonLine(
              widthFactor: 0.35,
              style: tokens.typography.caption,
              tone: SkeletonTone.onRaised,
            ),
          ],
        ),
      ),
    );
  }
}

/// One tab's list, kept alive while the other tab is shown.
final class _KeptTab extends StatefulWidget {
  const _KeptTab({required this.child});

  final Widget child;

  @override
  State<_KeptTab> createState() => _KeptTabState();
}

final class _KeptTabState extends State<_KeptTab>
    with AutomaticKeepAliveClientMixin<_KeptTab> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// The business's name as its receipts carry it.
final class _BusinessName extends TenantReadRepository {
  _BusinessName({required super.session, required super.reader});

  Future<String> load() async {
    try {
      final branding = await readDocument(
        TenantCollection.configuration,
        'branding',
      );
      final name = branding?['companyName'];
      if (name is String && name.trim().isNotEmpty) return name.trim();
      final root = await readTenantRoot();
      final registered = root?['name'];
      if (registered is String && registered.trim().isNotEmpty) {
        return registered.trim();
      }
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'email_receipt.business_name',
      );
    }
    return 'your business';
  }
}
