/// The Email tile: whether receipts go to customers by email, when - and what
/// became of the recent ones.
///
/// **The WhatsApp screen's layout, one choice shorter**
/// (`lib/whatsapp/e_receipt_settings_panel.dart`): the same two tabs, the same
/// flat switch and timing rows, titles rather than sentences. There is no
/// format to choose - an email carries the whole receipt and the PDF beside it
/// - and no availability check, because email goes through the Brevo account
/// every UzaPay account email already uses.
///
/// **Shaped like an inbox since 2026-10-04** (`docs/design/email-receipts/`):
/// the preview is the unread message the customer sees before they open
/// anything, and the sent tab is a list of messages with Gmail's three lines -
/// who and when, the subject, the snippet. The arrangement is Gmail's and every
/// colour is this app's own - a POS screen in another product's colours reads
/// as that product.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../checkout/checkout_configuration_writer.dart';
import '../observability/app_telemetry.dart';
import '../tenancy/tenancy.dart';
import '../ui/buttons.dart';
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
    this.clock,
  });

  final TenantDataReader reader;

  /// Absent in a build with no writer wired, which renders read-only.
  final TenantConfigurationDocumentWriter? writer;

  /// Reads the instant the sent list counts *today* and *this year* from.
  /// Injected so a test can pin it.
  final DateTime Function()? clock;

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
            // Two tabs draw as a switch, in the inset the tab content below
            // uses, so its edges line up with the rows.
            AppTabs(
              key: const ValueKey('email-receipts-tabs'),
              tabs: const <String>['Settings', 'Sent receipts'],
              inset:
                  MediaQuery.sizeOf(context).width <
                      AppLayout.contract.mediumFloor
                  ? AppTokens.componentOf(context).spacing.s16
                  : AppTokens.componentOf(context).spacing.s24,
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
                        child: _sent(
                          tokens,
                          data,
                          inset,
                          serverPending: switch (TenantReadFreshness.maybeOf(
                            context,
                          )) {
                            final freshness? =>
                              freshness.fromCache && !freshness.stale,
                            null => false,
                          },
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
    final colors = tokens.colors;
    final readOnly = widget.writer == null;
    final published = _saved ?? data.published;
    final settings = TenantEmailReceiptSettings(
      emailEnabled: _enabled,
      mode: _mode,
    );
    // **Every pressable here stands in `PressSurface`'s ring gutter** - the
    // switch, the two rows, the disclosure and Save - and everything that is
    // not takes the same inset, so the column has one left edge, as on the
    // WhatsApp tab.
    final ring = colors.action.focusRing;
    final gutter = ring.width + ring.offset;
    Widget aligned(Widget child) => Padding(
      padding: EdgeInsets.symmetric(horizontal: gutter),
      child: child,
    );
    final notices = <Widget>[
      if (published.state == TenantEReceiptState.malformed)
        const Callout(
          key: ValueKey('email-receipts-malformed'),
          status: AppStatus.problem,
          title: 'This setting could not be read',
          message:
              'No receipt is sent by email while it stays that way. Saving '
              'here replaces it.',
        ),
      if (readOnly)
        const Callout(
          key: ValueKey('email-receipts-read-only'),
          status: AppStatus.info,
          title: 'Read-only on this device',
          message: 'This build cannot publish settings changes.',
        ),
    ];
    return ListView(
      key: const ValueKey('email-receipts'),
      padding: EdgeInsets.fromLTRB(
        inset - gutter,
        inset,
        inset - gutter,
        inset - gutter,
      ),
      children: <Widget>[
        for (final notice in notices) ...<Widget>[
          aligned(notice),
          SizedBox(height: tokens.spacing.s16),
        ],
        // **The preview leads**, as the line in the customer's inbox: who it
        // is from, the subject, the preheader and the PDF, before they open
        // anything.
        if (_enabled) ...<Widget>[
          aligned(
            _InboxPreview(preview: emailReceiptPreview(data.businessName)),
          ),
          SizedBox(height: tokens.spacing.s8),
          aligned(
            Text(
              'What the customer sees',
              textAlign: TextAlign.center,
              style: tokens.typography.caption.copyWith(
                color: colors.text.tertiary,
              ),
            ),
          ),
          SizedBox(height: tokens.spacing.s16),
        ],
        AppSwitchRow(
          key: const ValueKey('email-receipts-enabled'),
          label: 'Email receipts',
          icon: Icons.mail_outline,
          value: _enabled,
          flat: true,
          onChanged: readOnly || _saving
              ? null
              : (value) => setState(() {
                  _edited = true;
                  _enabled = value;
                }),
        ),
        if (_enabled) ...<Widget>[
          SizedBox(height: tokens.spacing.s16),
          aligned(const _GroupLabel('When it is sent')),
          SizedBox(height: tokens.spacing.s4),
          ChoiceCardGroup<EReceiptMode>(
            key: const ValueKey('email-receipts-mode'),
            semanticLabel: 'When a receipt is sent',
            flat: true,
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
        ],
        SizedBox(height: tokens.spacing.s8),
        aligned(Divider(height: 1, color: colors.surface.borderSubtle)),
        // The disclosure's own gutter makes up the rest of the rule's space.
        SizedBox(height: tokens.spacing.s4),
        // At the foot of what it explains, after the rule, as on WhatsApp's.
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
                .copyWith(color: colors.text.secondary),
          ),
        ),
        // **Save stays**, full width at the foot, and is never disabled for
        // an unchanged form.
        if (!readOnly) ...<Widget>[
          SizedBox(height: tokens.spacing.s8),
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

  Widget _sent(
    AppTokens tokens,
    TenantEmailReceiptScreenData data,
    double inset, {
    required bool serverPending,
  }) {
    // The list starts a row's own padding below the strip, as an inbox does,
    // rather than a whole inset down.
    final listPadding = EdgeInsets.fromLTRB(
      inset,
      tokens.spacing.s4,
      inset,
      inset,
    );
    if (!data.deliveriesReadable) {
      return ListView(
        key: const ValueKey('email-receipts-sent'),
        padding: EdgeInsets.all(inset),
        children: const <Widget>[
          Callout(
            key: ValueKey('email-receipts-deliveries-unreadable'),
            status: AppStatus.info,
            message: 'The recent receipts could not be read on this device.',
          ),
        ],
      );
    }
    if (data.deliveries.isEmpty && serverPending) {
      return ListView(
        key: const ValueKey('email-receipts-sent'),
        padding: listPadding,
        children: <Widget>[
          SkeletonGroup(
            key: const ValueKey('email-receipts-deliveries-reading'),
            semanticLabel: 'Reading the recent receipts.',
            child: Column(
              children: <Widget>[
                for (final (who, subject, snippet) in _readingRows)
                  _DeliveryRowSkeleton(
                    whoFactor: who,
                    subjectFactor: subject,
                    snippetFactor: snippet,
                  ),
              ],
            ),
          ),
        ],
      );
    }
    if (data.deliveries.isEmpty) {
      return LayoutBuilder(
        key: const ValueKey('email-receipts-sent'),
        builder: (context, constraints) => SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: inset),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              // Centred on the tab and lifted off the middle, as WhatsApp's
              // empty tab is: the true centre of a tall page reads low.
              padding: EdgeInsets.only(bottom: tokens.spacing.s40 * 2),
              child: const EmptyState(
                key: ValueKey('email-receipts-deliveries-empty'),
                title: 'No receipts sent yet',
                hint:
                    'Each receipt sent by email is listed here with what '
                    'became of it.',
                icon: Icons.mail_outline,
              ),
            ),
          ),
        ),
      );
    }
    final now = (widget.clock ?? DateTime.now)();
    return ListView(
      key: const ValueKey('email-receipts-sent'),
      padding: listPadding,
      children: <Widget>[
        for (final delivery in data.deliveries)
          _DeliveryRow(delivery: delivery, now: now),
        // **Where the list stops, said.** The tab reads the most recent few
        // and no more, and without this the last of them reads as the first
        // receipt the business ever sent. A shorter list is every receipt
        // there is, so it says nothing.
        if (data.deliveries.length >=
            TenantEmailReceiptDeliveryRepository.recentPageSize)
          Padding(
            padding: EdgeInsets.only(
              top: tokens.spacing.s16,
              bottom: tokens.spacing.s8,
            ),
            child: Text(
              'The ${TenantEmailReceiptDeliveryRepository.recentPageSize} most '
              'recent receipts',
              key: const ValueKey('email-receipts-deliveries-end'),
              textAlign: TextAlign.center,
              style: tokens.typography.caption.copyWith(
                color: tokens.colors.text.tertiary,
              ),
            ),
          ),
      ],
    );
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

/// What a customer's inbox shows for a receipt, in the email's own words
/// (`functions/src/emailReceipts/template.ts`), with a made-up receipt: the
/// sender name, the subject, the preheader an inbox shows as the snippet, and
/// the name of the PDF it carries.
({String from, String subject, String snippet, String file})
emailReceiptPreview(String businessName) => (
  from: '$businessName via UzaPay',
  subject: 'Receipt JOHN-CT-7F2-001 from $businessName',
  snippet:
      'KES 1,250.00 at $businessName, 1 Oct 2026. The receipt is below and '
      'attached as a PDF.',
  file: 'Receipt-JOHN-CT-7F2-001.pdf',
);

/// When a receipt went, the way Gmail's inbox says it: the time today, then
/// the date - with the year once it is not this year's. No *Yesterday* and no
/// weekday, as Gmail does without them.
///
/// Null where the record carries no time; the server writes one with the
/// record, so that is a record read part-way through being written.
String? emailReceiptDeliveryWhen(DateTime? at, DateTime now) {
  if (at == null) return null;
  final sent = at.toLocal();
  final today = now.toLocal();
  if (sent.year == today.year &&
      sent.month == today.month &&
      sent.day == today.day) {
    return _timeFormat.format(sent);
  }
  return sent.year == today.year
      ? _dayFormat.format(sent)
      : _datedFormat.format(sent);
}

final DateFormat _timeFormat = DateFormat('HH:mm');
final DateFormat _dayFormat = DateFormat('d MMM');
final DateFormat _datedFormat = DateFormat('d MMM y');

/// The one letter an inbox draws for a sender: the first of the name, or of
/// the address when there is no name. Empty for an empty name.
String emailReceiptAvatarLetter(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '';
  return String.fromCharCode(trimmed.runes.first).toUpperCase();
}

/// The customer's inbox with the receipt in it, unread: a list label, then one
/// message - the letter, who it is from and when, the subject, the snippet,
/// and the PDF as a chip.
///
/// **Gmail's arrangement in this app's colours.** The inbox is
/// `surface.sunken`, the avatar `surface.overlay` and the chip's edge
/// `cardEdge` - no Gmail red and no per-sender colour. Unread is the bold
/// sender and subject, because the customer's receipt arrives unread. The
/// *Inbox* label and the time are drawn, not data: they say *a message*, not
/// *this message*.
final class _InboxPreview extends StatelessWidget {
  const _InboxPreview({required this.preview});

  final ({String from, String subject, String snippet, String file}) preview;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final spacing = tokens.spacing;
    final type = tokens.typography;
    final unread = type.bodyMedium.copyWith(
      color: colors.text.primary,
      fontWeight: FontWeight.w700,
    );
    return Semantics(
      container: true,
      child: DecoratedBox(
        key: const ValueKey('email-receipts-preview'),
        decoration: BoxDecoration(
          color: colors.surface.sunken,
          borderRadius: BorderRadius.circular(tokens.radius.lg),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            spacing.s16,
            spacing.s12,
            spacing.s16,
            spacing.s16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ExcludeSemantics(
                child: Text(
                  'Inbox',
                  style: type.caption.copyWith(
                    color: colors.text.tertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(height: spacing.s8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _Avatar(letter: emailReceiptAvatarLetter(preview.from)),
                  SizedBox(width: spacing.s16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                preview.from,
                                key: const ValueKey(
                                  'email-receipts-preview-from',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: type.bodyLarge.copyWith(
                                  color: colors.text.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            SizedBox(width: spacing.s8),
                            ExcludeSemantics(
                              child: Text(
                                '14:32',
                                style: type.caption.copyWith(
                                  color: colors.text.secondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          preview.subject,
                          key: const ValueKey('email-receipts-preview-subject'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: unread,
                        ),
                        // One line, as an inbox clips it.
                        Text(
                          preview.snippet,
                          key: const ValueKey('email-receipts-preview-text'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: type.bodyMedium.copyWith(
                            color: colors.text.secondary,
                          ),
                        ),
                        SizedBox(height: spacing.s8),
                        _AttachmentChip(file: preview.file),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The PDF an email receipt carries, as an inbox shows it under the snippet:
/// a chip with the file's glyph and name.
final class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({required this.file});

  final String file;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final spacing = tokens.spacing;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        height: spacing.s32,
        // The decoration's edge is inside the padding, as a border-box chip
        // draws it.
        padding: EdgeInsetsDirectional.only(
          start: spacing.s8,
          end: spacing.s12,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: colors.surface.cardEdge),
          borderRadius: BorderRadius.circular(tokens.radius.lg),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.picture_as_pdf_outlined,
              size: spacing.s20,
              color: colors.text.secondary,
            ),
            SizedBox(width: spacing.s8),
            Flexible(
              child: Text(
                file,
                key: const ValueKey('email-receipts-preview-file'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens.typography.labelMedium.copyWith(
                  color: colors.text.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The name over a group of flat rows: `label.md` in the body colour, quieter
/// than the rows it heads, as on WhatsApp's tab.
final class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Semantics(
      header: true,
      child: Padding(
        // The rows' own inset, so the label starts over their glyphs.
        padding: EdgeInsets.symmetric(horizontal: tokens.spacing.s8),
        child: Text(
          text,
          style: tokens.typography.labelMedium.copyWith(
            color: tokens.colors.text.secondary,
          ),
        ),
      ),
    );
  }
}

/// One receipt that was emailed, or was not, as an inbox draws a message: who,
/// with the time; *Receipt* and its number, with how it was sent at the edge
/// where Gmail keeps its star; then what became of it, and why after a dot.
///
/// **Mail's own marks, and the word beside them every time**: a clock for one
/// still going out, the paper plane of a Sent folder, and the inbox tray it
/// lands in. Only *Delivered* is lit - an email has no *Read*, so the
/// customer's mail server taking it is as far as a receipt is ever known to
/// get.
///
/// A receipt the server has not numbered yet has no subject, so its row is
/// two lines, and the bolt or hand moves to the end of the second.
final class _DeliveryRow extends StatelessWidget {
  const _DeliveryRow({required this.delivery, required this.now});

  final TenantEmailReceiptDelivery delivery;
  final DateTime now;

  static (IconData, Color) _mark(
    EmailReceiptDeliveryStatus status,
    AppColorRoles colors,
  ) => switch (status) {
    EmailReceiptDeliveryStatus.queued || EmailReceiptDeliveryStatus.sending => (
      Icons.schedule,
      colors.status.info.fg,
    ),
    EmailReceiptDeliveryStatus.sent => (
      Icons.send_outlined,
      colors.text.secondary,
    ),
    EmailReceiptDeliveryStatus.delivered => (
      Icons.move_to_inbox_outlined,
      colors.status.ok.fg,
    ),
    EmailReceiptDeliveryStatus.failed => (
      Icons.error_outline,
      colors.status.problem.fg,
    ),
    // A customer who stopped receipts, or receipts switched off, is the
    // system working: the quietest ink a person is still expected to read.
    EmailReceiptDeliveryStatus.skipped => (
      Icons.remove_circle_outline,
      colors.text.tertiary,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final spacing = tokens.spacing;
    final type = tokens.typography;
    final (glyph, tint) = _mark(delivery.status, colors);
    final line = type.bodyMedium.copyWith(color: colors.text.secondary);
    final who = delivery.customerName ?? delivery.emailMasked;
    final when = emailReceiptDeliveryWhen(delivery.createdAt, now);
    final number = delivery.receiptNumber;
    final reason = delivery.reasonText;

    // The timing rows' own glyphs, so this list and the settings say
    // *automatically* and *by hand* alike. A line high, so it sits on
    // whichever line it ends.
    final trigger = SizedBox(
      height: _lineHeight(line),
      child: Center(
        child: Icon(
          delivery.automatic ? Icons.bolt_outlined : Icons.touch_app_outlined,
          size: spacing.s16,
          color: colors.text.tertiary,
          semanticLabel: delivery.automatic
              ? 'Sent automatically'
              : 'Sent by hand',
        ),
      ),
    );

    // Wraps rather than clipping, unlike Gmail's snippet: a reason is the one
    // thing on the row a manager may need to act on.
    final snippet = Text.rich(
      TextSpan(
        children: <InlineSpan>[
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: EdgeInsetsDirectional.only(end: spacing.s4),
              child: Icon(glyph, size: spacing.s16, color: tint),
            ),
          ),
          TextSpan(
            text: delivery.status.label,
            style: TextStyle(color: tint, fontWeight: FontWeight.w600),
          ),
          if (reason != null) TextSpan(text: ' · $reason'),
        ],
      ),
      style: line,
    );

    return MergeSemantics(
      key: ValueKey('email-receipts-delivery-${delivery.id}'),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: spacing.s12),
        child: Row(
          // At the top of the row, as Gmail sets it, not centred.
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _Avatar(letter: emailReceiptAvatarLetter(who)),
            SizedBox(width: spacing.s16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          who,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: type.bodyLarge.copyWith(
                            color: colors.text.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (when != null) ...<Widget>[
                        SizedBox(width: spacing.s8),
                        Text(
                          when,
                          style: type.caption.copyWith(
                            color: colors.text.tertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (number != null)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            'Receipt $number',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: type.bodyMedium.copyWith(
                              color: colors.text.primary,
                            ),
                          ),
                        ),
                        SizedBox(width: spacing.s8),
                        trigger,
                      ],
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(child: snippet),
                      if (number == null) ...<Widget>[
                        SizedBox(width: spacing.s8),
                        trigger,
                      ],
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

/// The height of one line of [style]: its size times its leading.
double _lineHeight(TextStyle style) =>
    (style.fontSize ?? 0) * (style.height ?? 1);

/// Who a receipt went to, as an inbox draws a sender: one letter in a circle.
/// Decoration: the name beside it is what a screen reader is given.
final class _Avatar extends StatelessWidget {
  const _Avatar({required this.letter});

  final String letter;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    return ExcludeSemantics(
      child: Container(
        width: tokens.spacing.s40,
        height: tokens.spacing.s40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.surface.overlay,
        ),
        child: Text(
          letter,
          style: tokens.typography.bodyLarge.copyWith(
            color: colors.text.secondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Placeholder rows while the recent receipts are read: three, which fills the
/// top of the tab without pretending to know the count. Each triple is how
/// much of the row its who, subject and snippet lines take, so the three are
/// not one shape stamped three times.
const List<(double, double, double)> _readingRows = <(double, double, double)>[
  (0.52, 0.74, 0.30),
  (0.40, 0.70, 0.24),
  (0.48, 0.72, 0.36),
];

/// A [_DeliveryRow]'s shape with its words still arriving: a circle where the
/// letter lands, and a bar centred in each of the three line boxes.
///
/// The same padding and the same line boxes as the row, so nothing moves when
/// the real rows land. The bars are drawn on the avatar's own surface step,
/// the one a placeholder inside a raised thing takes.
final class _DeliveryRowSkeleton extends StatelessWidget {
  const _DeliveryRowSkeleton({
    required this.whoFactor,
    required this.subjectFactor,
    required this.snippetFactor,
  });

  final double whoFactor;
  final double subjectFactor;
  final double snippetFactor;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final spacing = tokens.spacing;
    final type = tokens.typography;
    const tone = SkeletonTone.onRaised;
    final bar = tokens.radius.sm;
    final lineBox = _lineHeight(type.bodyMedium);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: spacing.s12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SkeletonBlock(
            width: spacing.s40,
            height: spacing.s40,
            radius: tokens.radius.pill,
            tone: tone,
          ),
          SizedBox(width: spacing.s16),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                Widget line(double factor) => SizedBox(
                  height: lineBox,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: SkeletonBlock(
                      width: constraints.maxWidth * factor,
                      height: spacing.s12,
                      radius: bar,
                      tone: tone,
                    ),
                  ),
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      height: _lineHeight(type.bodyLarge),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          SkeletonBlock(
                            width: constraints.maxWidth * whoFactor,
                            height: spacing.s16,
                            radius: bar,
                            tone: tone,
                          ),
                          SkeletonBlock(
                            width: spacing.s32,
                            height: spacing.s12,
                            radius: bar,
                            tone: tone,
                          ),
                        ],
                      ),
                    ),
                    line(subjectFactor),
                    line(snippetFactor),
                  ],
                );
              },
            ),
          ),
        ],
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
