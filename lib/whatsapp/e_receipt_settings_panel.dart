/// The WhatsApp tile: whether receipts go to customers on WhatsApp, in what
/// form, when - and what became of the recent ones.
///
/// **For businesses without a printer, first.** A receipt that arrives on the
/// customer's phone is the paper they would have been handed, so the choices
/// here are the paper's: the whole receipt (a PDF laid out like the printed
/// one) or its totals in the message.
///
/// **Every choice states what it does before it is chosen**, as the stock
/// count settings do: format and timing are `ChoiceCardGroup`s, because
/// "automatically" sends messages to people and that consequence belongs on
/// screen next to the button that does it.
library;

import 'package:flutter/material.dart';

import '../checkout/checkout_configuration_writer.dart';
import '../observability/app_telemetry.dart';
import '../tenancy/tenancy.dart';
import '../ui/buttons.dart';
import '../ui/card.dart';
import '../ui/choice.dart';
import '../ui/fields.dart';
import '../ui/scaffold.dart';
import '../ui/snackbar.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'e_receipt_settings.dart';
import 'receipt_delivery.dart';

/// Asks the server whether this deployment can send at all. Answers null where
/// it could not be asked - offline, or a build that wires no such call.
typedef WhatsappReceiptStatusCheck = Future<bool?> Function(TenantSession session);

/// Everything the screen draws from.
final class TenantEReceiptScreenData {
  const TenantEReceiptScreenData({
    required this.published,
    required this.businessName,
    required this.deliveries,
    required this.deliveriesReadable,
  });

  final TenantPublishedEReceipts published;

  /// The name every message carries, for the preview.
  final String businessName;
  final List<TenantReceiptDelivery> deliveries;

  /// False where the recent receipts could not be read; the settings still can.
  final bool deliveriesReadable;
}

final class TenantWhatsappReceiptsScreen extends StatefulWidget {
  const TenantWhatsappReceiptsScreen({
    super.key,
    required this.reader,
    this.writer,
    this.statusCheck,
  });

  final TenantDataReader reader;

  /// Absent in a build with no writer wired, which renders read-only.
  final TenantConfigurationDocumentWriter? writer;
  final WhatsappReceiptStatusCheck? statusCheck;

  @override
  State<TenantWhatsappReceiptsScreen> createState() =>
      _TenantWhatsappReceiptsScreenState();
}

class _TenantWhatsappReceiptsScreenState
    extends State<TenantWhatsappReceiptsScreen> {
  bool _enabled = false;
  EReceiptFormat _format = EReceiptFormat.pdf;
  EReceiptMode _mode = EReceiptMode.manual;
  TenantPublishedEReceipts? _seededFrom;
  TenantPublishedEReceipts? _saved;
  bool _edited = false;
  bool _saving = false;

  /// The server's answer to "can this deployment send", or null until asked.
  bool? _available;
  bool _asked = false;

  String? _loaderKey;
  TenantGuardedLoader<TenantEReceiptScreenData>? _loader;
  TenantGuardedLoader<TenantEReceiptScreenData>? _loaderCached;

  void _composeLoaders() {
    if (_loaderKey == 'e-receipts' && _loader != null) return;
    _loaderKey = 'e-receipts';
    _loader = (session) => _read(session, widget.reader);
    final cache = widget.reader.cached;
    _loaderCached = cache == null ? null : (session) => _read(session, cache);
  }

  Future<TenantEReceiptScreenData> _read(
    TenantSession session,
    TenantDataReader reader,
  ) async {
    final published = await TenantEReceiptRepository(
      session: session,
      reader: reader,
    ).load();
    final name = await _BusinessName(session: session, reader: reader).load();
    var deliveries = const <TenantReceiptDelivery>[];
    var readable = true;
    try {
      deliveries = await TenantReceiptDeliveryRepository(
        session: session,
        reader: reader,
      ).loadRecent();
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'whatsapp.deliveries_read',
      );
      readable = false;
    }
    return TenantEReceiptScreenData(
      published: published,
      businessName: name,
      deliveries: deliveries,
      deliveriesReadable: readable,
    );
  }

  Future<void> _ask(TenantSession session) async {
    if (_asked) return;
    _asked = true;
    final check = widget.statusCheck;
    if (check == null) return;
    bool? available;
    try {
      available = await check(session);
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'whatsapp.status_check',
      );
      available = null;
    }
    if (mounted) setState(() => _available = available);
  }

  void _seed(TenantPublishedEReceipts published) {
    if (_edited) return;
    final seeded = _seededFrom;
    if (seeded != null &&
        seeded.state == published.state &&
        seeded.published == published.published) {
      return;
    }
    _seededFrom = published;
    final settings = published.settings;
    _enabled = settings.whatsappEnabled;
    _format = settings.format;
    _mode = settings.mode;
  }

  @override
  Widget build(BuildContext context) {
    _composeLoaders();
    return AppScaffold(
      title: 'WhatsApp receipts',
      contentWidth: AppContentWidth.reading,
      body: TenantRouteGuard<TenantEReceiptScreenData>(
        allowedRoles: TenantEReceiptPublisher.allowedRoles,
        load: _loader!,
        loadCached: _loaderCached,
        loading: const LoadingState(message: 'Reading WhatsApp receipts'),
        denied: const ErrorState(
          status: AppStatus.problem,
          badgeLabel: 'Not allowed',
          statement:
              'Only an owner or administrator may decide how receipts are sent.',
        ),
        failure: (context, error) => const ErrorState(
          key: ValueKey('e-receipts-failure'),
          badgeLabel: 'Not read',
          statement: 'The WhatsApp receipt settings could not be read.',
          stillTrue: 'Nothing has been changed.',
        ),
        builder: _build,
      ),
    );
  }

  Widget _build(
    BuildContext context,
    TenantSession session,
    TenantEReceiptScreenData data,
  ) {
    _seed(data.published);
    if (!_asked) Future<void>.microtask(() => _ask(session));
    final tokens = AppTokens.componentOf(context);
    final readOnly = widget.writer == null;
    final published = _saved ?? data.published;
    final width = MediaQuery.sizeOf(context).width;
    final inset = width < AppLayout.contract.mediumFloor
        ? tokens.spacing.s16
        : tokens.spacing.s24;
    final settings = TenantEReceiptSettings(
      whatsappEnabled: _enabled,
      mode: _mode,
      format: _format,
    );
    return ListView(
      key: const ValueKey('e-receipts'),
      padding: EdgeInsets.all(inset),
      children: <Widget>[
        ..._availability(tokens),
        if (published.state == TenantEReceiptState.malformed) ...<Widget>[
          const Callout(
            key: ValueKey('e-receipts-malformed'),
            status: AppStatus.problem,
            title: 'This setting could not be read',
            message:
                'No receipt is sent on WhatsApp while it stays that way. '
                'Saving here replaces it.',
          ),
          SizedBox(height: tokens.spacing.s16),
        ],
        if (readOnly) ...<Widget>[
          const Callout(
            key: ValueKey('e-receipts-read-only'),
            status: AppStatus.info,
            title: 'Read-only on this device',
            message: 'This build cannot publish settings changes.',
          ),
          SizedBox(height: tokens.spacing.s16),
        ],
        const SectionHeading('Send receipts on WhatsApp'),
        SizedBox(height: tokens.spacing.s8),
        Text(
          "Receipts come from UzaPay's WhatsApp number, and every message "
          'names your business. A customer can reply STOP at any time and gets '
          'no more.',
          key: const ValueKey('e-receipts-explanation'),
          style: tokens.density
              .body(tokens.typography)
              .copyWith(color: tokens.colors.text.secondary),
        ),
        SizedBox(height: tokens.spacing.s16),
        AppSelect<bool>(
          key: const ValueKey('e-receipts-enabled'),
          label: 'WhatsApp receipts',
          leading: Icons.chat_outlined,
          value: _enabled,
          enabled: !readOnly && !_saving,
          items: const <AppSelectItem<bool>>[
            AppSelectItem<bool>(
              key: ValueKey('e-receipts-enabled-no'),
              value: false,
              label: 'Off - no receipts on WhatsApp',
            ),
            AppSelectItem<bool>(
              key: ValueKey('e-receipts-enabled-yes'),
              value: true,
              label: 'On - send receipts on WhatsApp',
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
          SizedBox(height: tokens.density.sectionGap),
          const SectionHeading('What the customer gets'),
          SizedBox(height: tokens.spacing.s8),
          ChoiceCardGroup<EReceiptFormat>(
            key: const ValueKey('e-receipts-format'),
            semanticLabel: 'What the customer gets',
            selected: _format,
            onSelected: readOnly || _saving
                ? null
                : (value) => setState(() {
                    _edited = true;
                    _format = value;
                  }),
            options: const <ChoiceCardOption<EReceiptFormat>>[
              ChoiceCardOption<EReceiptFormat>(
                key: ValueKey('e-receipts-format-pdf'),
                value: EReceiptFormat.pdf,
                icon: Icons.picture_as_pdf_outlined,
                title: 'The receipt as a PDF',
                description:
                    'Laid out like the printed receipt: every item, the totals '
                    'and how it was paid.',
              ),
              ChoiceCardOption<EReceiptFormat>(
                key: ValueKey('e-receipts-format-summary'),
                value: EReceiptFormat.summary,
                icon: Icons.notes_outlined,
                title: 'The totals in the message',
                description:
                    'The receipt number, the date, how many items and the '
                    'total, in the message itself.',
              ),
            ],
          ),
          SizedBox(height: tokens.density.sectionGap),
          const SectionHeading('When it is sent'),
          SizedBox(height: tokens.spacing.s8),
          ChoiceCardGroup<EReceiptMode>(
            key: const ValueKey('e-receipts-mode'),
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
                key: ValueKey('e-receipts-mode-automatic'),
                value: EReceiptMode.automatic,
                icon: Icons.bolt_outlined,
                title: 'Automatically',
                description:
                    'To every customer who agreed, as soon as their sale '
                    'reaches the server. A cashier can still send one by hand.',
              ),
              ChoiceCardOption<EReceiptMode>(
                key: ValueKey('e-receipts-mode-manual'),
                value: EReceiptMode.manual,
                icon: Icons.touch_app_outlined,
                title: 'Only when a cashier sends one',
                description:
                    'After each sale the till offers Send on WhatsApp, to the '
                    'customer or to a number the cashier types.',
              ),
            ],
          ),
          SizedBox(height: tokens.density.sectionGap),
          AppCard(
            key: const ValueKey('e-receipts-preview'),
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
                  eReceiptMessagePreview(settings, data.businessName),
                  key: const ValueKey('e-receipts-preview-text'),
                  style: tokens.typography.bodyMedium.copyWith(
                    color: tokens.colors.text.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (!readOnly) ...<Widget>[
          SizedBox(height: tokens.density.sectionGap),
          AppButton(
            key: const ValueKey('e-receipts-save'),
            label: 'Save',
            tier: AppButtonTier.primary,
            loading: _saving,
            expand: true,
            onPressed: _saving ? null : () => _save(session, published, settings),
          ),
        ],
        SizedBox(height: tokens.density.sectionGap),
        const SectionHeading('Recent receipts'),
        SizedBox(height: tokens.spacing.s8),
        ..._deliveries(tokens, data),
      ],
    );
  }

  List<Widget> _availability(AppTokens tokens) {
    final notice = switch (_available) {
      false => const Callout(
        key: ValueKey('e-receipts-unavailable'),
        status: AppStatus.attention,
        title: 'Not available yet',
        message:
            "UzaPay's WhatsApp number is not connected yet. You can choose "
            'your settings now; receipts start once it is.',
      ),
      null when _asked && widget.statusCheck != null => const Callout(
        key: ValueKey('e-receipts-unknown'),
        status: AppStatus.info,
        message:
            'Connect to the internet to check whether WhatsApp receipts are '
            'available.',
      ),
      _ => null,
    };
    if (notice == null) return const <Widget>[];
    return <Widget>[notice, SizedBox(height: tokens.spacing.s16)];
  }

  List<Widget> _deliveries(AppTokens tokens, TenantEReceiptScreenData data) {
    if (!data.deliveriesReadable) {
      return const <Widget>[
        Callout(
          key: ValueKey('e-receipts-deliveries-unreadable'),
          status: AppStatus.info,
          message: 'The recent receipts could not be read on this device.',
        ),
      ];
    }
    if (data.deliveries.isEmpty) {
      return const <Widget>[
        EmptyState(
          key: ValueKey('e-receipts-deliveries-empty'),
          title: 'No receipts sent yet',
          hint: 'Each receipt sent on WhatsApp is listed here with what became '
              'of it.',
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
    TenantPublishedEReceipts published,
    TenantEReceiptSettings settings,
  ) async {
    final writer = widget.writer;
    if (writer == null || _saving) return;
    final TenantEReceiptIntent intent;
    try {
      intent = TenantEReceiptPublisher(
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
          settings.whatsappEnabled
              ? 'Saved. Tills offer WhatsApp receipts the next time they open '
                    'the register.'
              : 'Saved. No receipts are sent on WhatsApp.',
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
          _saved = TenantPublishedEReceipts.published(settings);
          _seededFrom = _saved;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// What a customer's phone shows for [settings], in the templates' own words.
///
/// The templates are fixed in Meta (`functions/src/whatsapp/templates.ts`), so
/// this is their text with a made-up receipt in it.
String eReceiptMessagePreview(
  TenantEReceiptSettings settings,
  String businessName,
) => switch (settings.format) {
  EReceiptFormat.pdf =>
    'Thank you for shopping at $businessName. Your receipt JOHN-CT-7F2-001 for '
        'KES 1,250.00 is attached. Reply STOP to stop receipts.\n\n'
        '[Receipt-JOHN-CT-7F2-001.pdf]',
  EReceiptFormat.summary =>
    'Thank you for shopping at $businessName. Receipt JOHN-CT-7F2-001 on '
        '1 Oct 2026: 3 items, total KES 1,250.00. Reply STOP to stop receipts.',
};

/// One receipt that was sent, or was not, and why.
final class _DeliveryRow extends StatelessWidget {
  const _DeliveryRow({required this.delivery});

  final TenantReceiptDelivery delivery;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final status = switch (delivery.status) {
      ReceiptDeliveryStatus.sent ||
      ReceiptDeliveryStatus.delivered ||
      ReceiptDeliveryStatus.read => AppStatus.ok,
      ReceiptDeliveryStatus.queued ||
      ReceiptDeliveryStatus.sending => AppStatus.info,
      ReceiptDeliveryStatus.skipped => AppStatus.neutral,
      ReceiptDeliveryStatus.failed => AppStatus.problem,
    };
    final who = delivery.customerName ?? delivery.phoneMasked;
    final subject = delivery.receiptNumber == null
        ? who
        : '${delivery.receiptNumber} · $who';
    return DecoratedBox(
      key: ValueKey('e-receipts-delivery-${delivery.id}'),
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
                        (delivery.automatic ? 'Sent automatically' : 'Sent by hand'),
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

/// The business's name as its messages carry it.
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
        boundary: 'whatsapp.business_name',
      );
    }
    return 'your business';
  }
}
