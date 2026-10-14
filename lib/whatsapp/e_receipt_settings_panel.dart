/// The WhatsApp tile: whether receipts go to customers on WhatsApp, in what
/// form, when - and what became of the recent ones.
///
/// **For businesses without a printer, first.** A receipt that arrives on the
/// customer's phone is the paper they would have been handed, so the choices
/// here are the paper's: the whole receipt (a PDF laid out like the printed
/// one) or its totals in the message.
///
/// **Titles, not sentences, since 2026-10-03**, at the developer's direction:
/// format and timing are said by their titles alone, and the switch is its
/// label alone. What a format sends is shown by the preview, and the receipts
/// that went out are their own tab.
///
/// **Shaped like WhatsApp since 2026-10-04** (`docs/design/whatsapp-receipts/`):
/// the preview is the chat the customer opens, the settings are flat rows on
/// the page, and the sent tab is a chat list with WhatsApp's ticks. The shapes
/// are WhatsApp's and every colour is this app's own - a POS screen in another
/// product's colours reads as that product.
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
import '../ui/record_sheet.dart';
import 'e_receipt_settings.dart';
import 'receipt_delivery.dart';

/// Asks the server whether this deployment can send at all. Answers null where
/// it could not be asked - offline, or a build that wires no such call.
typedef WhatsappReceiptStatusCheck =
    Future<bool?> Function(TenantSession session);

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
    this.clock,
  });

  final TenantDataReader reader;

  /// Absent in a build with no writer wired, which renders read-only.
  final TenantConfigurationDocumentWriter? writer;
  final WhatsappReceiptStatusCheck? statusCheck;

  /// Reads the instant the sent list counts *today* and *Yesterday* from.
  /// Injected so a test can pin it.
  final DateTime Function()? clock;

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

  /// Whether the check has come back, whatever it said.
  ///
  /// **Separate from [_asked], which is set when the question goes out.** The
  /// *connect to the internet* note keyed on that, so any rebuild while the
  /// check was still in flight - the server's settings replacing the device's
  /// copy, for one - told a connected phone it was offline.
  bool _checked = false;

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
    if (mounted) {
      setState(() {
        _available = available;
        _checked = true;
      });
    }
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
    // **Two tabs, at the developer's direction on 2026-10-03**: the settings,
    // and the receipts that were sent, which used to sit under Save at the foot
    // of one long page. The strip stands above the guard, as the Configs
    // screen's does, so it is on screen from the first frame rather than
    // arriving with the read.
    return DefaultTabController(
      length: 2,
      child: AppScaffold(
        title: 'WhatsApp receipts',
        contentWidth: AppContentWidth.records,
        body: Column(
          children: <Widget>[
            // Two tabs draw as a switch, in the inset the tab content below
            // uses, so its edges line up with the rows.
            AppTabs(
              key: const ValueKey('e-receipts-tabs'),
              tabs: const <String>['Settings', 'Sent receipts'],
              // Over the centred settings column.
              alignment: Alignment.center,
              inset:
                  MediaQuery.sizeOf(context).width <
                      AppLayout.contract.mediumFloor
                  ? AppTokens.componentOf(context).spacing.s16
                  : AppTokens.componentOf(context).spacing.s24,
            ),
            Expanded(
              child: TenantRouteGuard<TenantEReceiptScreenData>(
                allowedRoles: TenantEReceiptPublisher.allowedRoles,
                load: _loader!,
                loadCached: _loaderCached,
                loading: const LoadingState(
                  message: 'Reading WhatsApp receipts',
                ),
                denied: const ErrorState(
                  status: AppStatus.problem,
                  badgeLabel: 'Not allowed',
                  statement:
                      'Only an owner or administrator may decide how receipts '
                      'are sent.',
                ),
                failure: (context, error) => const ErrorState(
                  key: ValueKey('e-receipts-failure'),
                  badgeLabel: 'Not read',
                  statement: 'The WhatsApp receipt settings could not be read.',
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
                      _KeptTab(
                        // Centred in the records frame, so a wide window
                        // has the column in its middle rather than against
                        // its left edge with the rest empty.
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                            width: tokens.layout.reading,
                            child: _build(context, session, data, inset),
                          ),
                        ),
                      ),
                      _KeptTab(
                        child: _sent(
                          tokens,
                          data,
                          inset,
                          // The device's copy, with the server not yet
                          // answered. An empty list in it is "not downloaded
                          // yet" as often as "none sent".
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
    TenantEReceiptScreenData data,
    double inset,
  ) {
    _seed(data.published);
    if (!_asked) Future<void>.microtask(() => _ask(session));
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final readOnly = widget.writer == null;
    final published = _saved ?? data.published;
    final settings = TenantEReceiptSettings(
      whatsappEnabled: _enabled,
      mode: _mode,
      format: _format,
    );
    // **Every pressable here stands in `PressSurface`'s ring gutter** - the
    // switch, the four rows, the disclosure and Save - and everything that is
    // not takes the same inset, so the column has one left edge. The list's
    // own padding is the screen's inset less that gutter, which puts every
    // painted edge back on the inset itself, where the design draws it.
    final ring = colors.action.focusRing;
    final gutter = ring.width + ring.offset;
    Widget aligned(Widget child) => Padding(
      padding: EdgeInsets.symmetric(horizontal: gutter),
      child: child,
    );
    final notices = <Widget>[
      ?_availability(),
      if (published.state == TenantEReceiptState.malformed)
        const Callout(
          key: ValueKey('e-receipts-malformed'),
          status: AppStatus.problem,
          title: 'This setting could not be read',
          message:
              'No receipt is sent on WhatsApp while it stays that way. '
              'Saving here replaces it.',
        ),
      if (readOnly)
        const Callout(
          key: ValueKey('e-receipts-read-only'),
          status: AppStatus.info,
          title: 'Read-only on this device',
          message: 'This build cannot publish settings changes.',
        ),
    ];
    return ListView(
      key: const ValueKey('e-receipts'),
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
        // **The preview leads**, as the chat the customer opens: it is the
        // description the titles below leave out, and choosing a format
        // changes it in place, so a choice's consequence is on screen the
        // moment it is made.
        if (_enabled) ...<Widget>[
          aligned(
            _ChatPreview(
              format: _format,
              message: eReceiptMessagePreview(settings, data.businessName),
            ),
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
        // **A switch, not a list of two**, at the developer's direction on
        // 2026-10-02: the answer is on or off, and a toggle says so in one tap.
        // Its label alone since 2026-10-03, with no heading over it - the
        // screen's title already says what the page is.
        AppSwitchRow(
          key: const ValueKey('e-receipts-enabled'),
          label: 'WhatsApp receipts',
          icon: Icons.chat_outlined,
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
          aligned(const _GroupLabel('What the customer gets')),
          SizedBox(height: tokens.spacing.s4),
          ChoiceCardGroup<EReceiptFormat>(
            key: const ValueKey('e-receipts-format'),
            semanticLabel: 'What the customer gets',
            flat: true,
            selected: _format,
            onSelected: readOnly || _saving
                ? null
                : (value) => setState(() {
                    _edited = true;
                    _format = value;
                  }),
            options: const <ChoiceCardOption<EReceiptFormat>>[
              // Titles alone, at the developer's direction on 2026-10-03; the
              // preview above shows what each one sends.
              ChoiceCardOption<EReceiptFormat>(
                key: ValueKey('e-receipts-format-pdf'),
                value: EReceiptFormat.pdf,
                icon: Icons.picture_as_pdf_outlined,
                title: 'The receipt as a PDF',
              ),
              ChoiceCardOption<EReceiptFormat>(
                key: ValueKey('e-receipts-format-summary'),
                value: EReceiptFormat.summary,
                icon: Icons.notes_outlined,
                title: 'The totals in the message',
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.s16),
          aligned(const _GroupLabel('When it is sent')),
          SizedBox(height: tokens.spacing.s4),
          ChoiceCardGroup<EReceiptMode>(
            key: const ValueKey('e-receipts-mode'),
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
                key: ValueKey('e-receipts-mode-automatic'),
                value: EReceiptMode.automatic,
                icon: Icons.bolt_outlined,
                title: 'Automatically',
              ),
              ChoiceCardOption<EReceiptMode>(
                key: ValueKey('e-receipts-mode-manual'),
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
        // **Folded away, not deleted**: the writing stays one tap off, at the
        // foot of what it explains.
        Disclosure(
          key: const ValueKey('e-receipts-explanation'),
          summary: 'Where receipts come from',
          child: Text(
            "Receipts come from UzaPay's WhatsApp number, and every message "
            'names your business. A customer can reply STOP at any time and '
            'gets no more.',
            style: tokens.density
                .body(tokens.typography)
                .copyWith(color: colors.text.secondary),
          ),
        ),
        // **Save stays**, full width at the foot, and is never disabled for
        // an unchanged form. WhatsApp applies a setting the moment it is
        // touched; this one is published to every till through a queued write.
        if (!readOnly) ...<Widget>[
          SizedBox(height: tokens.spacing.s8),
          AppButton(
            key: const ValueKey('e-receipts-save'),
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

  Widget? _availability() => switch (_available) {
    false => const Callout(
      key: ValueKey('e-receipts-unavailable'),
      status: AppStatus.attention,
      title: 'Not available yet',
      message:
          "UzaPay's WhatsApp number is not connected yet. You can choose "
          'your settings now; receipts start once it is.',
    ),
    null when _checked => const Callout(
      key: ValueKey('e-receipts-unknown'),
      status: AppStatus.info,
      message:
          'Connect to the internet to check whether WhatsApp receipts are '
          'available.',
    ),
    _ => null,
  };

  Widget _sent(
    AppTokens tokens,
    TenantEReceiptScreenData data,
    double inset, {
    required bool serverPending,
  }) {
    // The list starts a row's own padding below the strip, as a chat list
    // does, rather than a whole inset down.
    final listPadding = EdgeInsets.fromLTRB(
      inset,
      tokens.spacing.s4,
      inset,
      inset,
    );
    if (!data.deliveriesReadable) {
      return ListView(
        key: const ValueKey('e-receipts-sent'),
        padding: EdgeInsets.all(inset),
        children: const <Widget>[
          Callout(
            key: ValueKey('e-receipts-deliveries-unreadable'),
            status: AppStatus.info,
            message: 'The recent receipts could not be read on this device.',
          ),
        ],
      );
    }
    // **Placeholders for this tab only, not the screen.** The settings are
    // what this screen is opened for, and holding them back until the server
    // answers would cost every business that has sent nothing yet - which is
    // most of them - to spare this tab a false *No receipts*.
    if (data.deliveries.isEmpty && serverPending) {
      return ListView(
        key: const ValueKey('e-receipts-sent'),
        padding: listPadding,
        children: <Widget>[
          SkeletonGroup(
            key: const ValueKey('e-receipts-deliveries-reading'),
            semanticLabel: 'Reading the recent receipts.',
            child: Column(
              children: <Widget>[
                for (final (name, line) in _readingRows)
                  _DeliveryRowSkeleton(nameFactor: name, lineFactor: line),
              ],
            ),
          ),
        ],
      );
    }
    if (data.deliveries.isEmpty) {
      return LayoutBuilder(
        key: const ValueKey('e-receipts-sent'),
        builder: (context, constraints) => SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: inset),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              // Centred on the tab and lifted `space.40` off the middle, where
              // an empty chat list's words sit: the true centre of a tall
              // page reads low.
              padding: EdgeInsets.only(bottom: tokens.spacing.s40 * 2),
              child: const EmptyState(
                key: ValueKey('e-receipts-deliveries-empty'),
                illustration: 'receipt-whatsapp.svg',
                title: 'No receipts sent yet',
                hint: 'WhatsApp receipts and delivery status appear here.',
              ),
            ),
          ),
        ),
      );
    }
    final now = (widget.clock ?? DateTime.now)();
    return ListView(
      key: const ValueKey('e-receipts-sent'),
      padding: listPadding,
      children: <Widget>[
        if (RecordSheet.drawnAt(MediaQuery.sizeOf(context).width))
          RecordSheet(
            columns: const [
              SheetColumn(label: 'Customer', kind: SheetColumnKind.identity),
              SheetColumn(label: 'Recipient'),
              SheetColumn(label: 'Receipt', kind: SheetColumnKind.code),
              SheetColumn(label: 'Status'),
              SheetColumn(label: 'Sent'),
              SheetColumn(label: 'When', kind: SheetColumnKind.time),
            ],
            rows: [
              for (final delivery in data.deliveries)
                SheetRow(
                  id: delivery.id,
                  key: ValueKey('e-receipts-delivery-${delivery.id}'),
                  cells: [
                    SheetText(delivery.customerName ?? '\u2014'),
                    SheetText(delivery.phoneMasked),
                    SheetText(delivery.receiptNumber ?? 'Not numbered yet'),
                    SheetText(delivery.status.label),
                    SheetText(delivery.automatic ? 'Automatically' : 'By hand'),
                    SheetText(
                      (receiptDeliveryWhen(delivery.createdAt, now) ??
                          '\u2014'),
                    ),
                  ],
                  fold: delivery.reasonText == null
                      ? null
                      // Why, under the status it explains.
                      : SheetFold(
                          note: delivery.reasonText,
                          noteColumn: 3,
                          alwaysOpen: true,
                        ),
                ),
            ],
          )
        else
          for (final delivery in data.deliveries)
            _DeliveryRow(delivery: delivery, now: now),
        // **Where the list stops, said.** The tab reads the most recent few
        // and no more, and without this the last of them reads as the first
        // receipt the business ever sent. A shorter list is every receipt
        // there is, so it says nothing.
        if (data.deliveries.length >=
            TenantReceiptDeliveryRepository.recentPageSize)
          Padding(
            padding: EdgeInsets.only(
              top: tokens.spacing.s16,
              bottom: tokens.spacing.s8,
            ),
            child: Text(
              'The ${TenantReceiptDeliveryRepository.recentPageSize} most recent '
              'receipts',
              key: const ValueKey('e-receipts-deliveries-end'),
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

/// The words a customer's phone shows for [settings], in the templates' own
/// words.
///
/// The templates are fixed in Meta (`functions/src/whatsapp/templates.ts`), so
/// this is their text with a made-up receipt in it. **The words only**: a PDF
/// arrives as a document above them, and [eReceiptPreviewFileName] is that
/// document's name.
String eReceiptMessagePreview(
  TenantEReceiptSettings settings,
  String businessName,
) => switch (settings.format) {
  EReceiptFormat.pdf =>
    'Thank you for shopping at $businessName. Your receipt JOHN-CT-7F2-001 for '
        'KES 1,250.00 is attached. Reply STOP to stop receipts.',
  EReceiptFormat.summary =>
    'Thank you for shopping at $businessName. Receipt JOHN-CT-7F2-001 on '
        '1 Oct 2026: 3 items, total KES 1,250.00. Reply STOP to stop receipts.',
};

/// The file the made-up receipt in [eReceiptMessagePreview] arrives as, when
/// the business sends the receipt as a PDF.
const String eReceiptPreviewFileName = 'Receipt-JOHN-CT-7F2-001.pdf';

/// When a receipt went, the way WhatsApp's chat list says it: the time today,
/// *Yesterday*, the weekday within the week, then the date - with the year
/// once it is not this year's.
///
/// Null where the record carries no time; the server writes one with the
/// record, so that is a record read part-way through being written.
String? receiptDeliveryWhen(DateTime? at, DateTime now) {
  if (at == null) return null;
  final sent = at.toLocal();
  final today = now.toLocal();
  // Calendar days, counted in UTC so a day that is 23 or 25 hours long across
  // a clock change is still one day.
  final days = DateTime.utc(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime.utc(sent.year, sent.month, sent.day)).inDays;
  if (days == 0) return _timeFormat.format(sent);
  if (days == 1) return 'Yesterday';
  if (days > 1 && days < DateTime.daysPerWeek) {
    return _weekdayFormat.format(sent);
  }
  return sent.year == today.year
      ? _dayFormat.format(sent)
      : _datedFormat.format(sent);
}

final DateFormat _timeFormat = DateFormat('HH:mm');
final DateFormat _weekdayFormat = DateFormat('EEE');
final DateFormat _dayFormat = DateFormat('d MMM');
final DateFormat _datedFormat = DateFormat('d MMM y');

/// What the customer's phone shows, drawn the way WhatsApp draws a chat: the
/// day, one bubble with its tail, the PDF's tile when there is one, and the
/// time inside the bubble.
///
/// **WhatsApp's shapes in this app's colours.** The wallpaper is
/// `surface.sunken`, the bubble `surface.overlay` and the document tile
/// `surface.raised` - no WhatsApp green and no doodle wallpaper. The day and
/// the time are drawn, not data: they say *a message*, not *this message*.
final class _ChatPreview extends StatelessWidget {
  const _ChatPreview({required this.format, required this.message});

  final EReceiptFormat format;
  final String message;

  /// How much of the chat's width a bubble's words may take: WhatsApp's own
  /// proportion, so the wallpaper still shows on the side a reply would come
  /// from. Named here for the reason `ChoiceCardGroup.radioSize` is - no
  /// source this app has states a bubble.
  static const double bubbleWidthFactor = 0.88;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final spacing = tokens.spacing;
    final caption = tokens.typography.caption.copyWith(
      color: colors.text.tertiary,
    );
    final pdf = format == EReceiptFormat.pdf;
    final corner = Radius.circular(tokens.radius.md);

    final bubble = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.overlay,
        // Square at the top start, where the tail grows out of it.
        borderRadius: BorderRadiusDirectional.only(
          topEnd: corner,
          bottomStart: corner,
          bottomEnd: corner,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(spacing.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (pdf) const _DocumentTile(),
            Padding(
              // With no tile above it the message is the bubble's first line,
              // and takes the same room above as at its sides.
              padding: EdgeInsetsDirectional.only(
                start: spacing.s8,
                top: pdf ? spacing.s4 : spacing.s8,
                end: spacing.s8,
              ),
              child: Text(
                message,
                key: const ValueKey('e-receipts-preview-text'),
                style: tokens.typography.bodyMedium.copyWith(
                  color: colors.text.primary,
                ),
              ),
            ),
            ExcludeSemantics(
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: spacing.s8,
                    end: spacing.s8,
                    bottom: spacing.s4,
                  ),
                  child: Text('14:32', style: caption),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Semantics(
      container: true,
      child: DecoratedBox(
        key: const ValueKey('e-receipts-preview'),
        decoration: BoxDecoration(
          color: colors.surface.sunken,
          borderRadius: BorderRadius.circular(tokens.radius.lg),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            spacing.s12,
            spacing.s12,
            spacing.s12,
            spacing.s16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: ExcludeSemantics(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surface.raised,
                      borderRadius: BorderRadius.circular(tokens.radius.md),
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: spacing.s12,
                        vertical: spacing.s4,
                      ),
                      child: Text('Today', style: caption),
                    ),
                  ),
                ),
              ),
              SizedBox(height: spacing.s8),
              LayoutBuilder(
                builder: (context, constraints) {
                  // The factor measures the words and the bubble's padding
                  // goes outside it, as WhatsApp sizes one; the tail stands in
                  // the margin before it.
                  final width =
                      (constraints.maxWidth * bubbleWidthFactor +
                              spacing.s4 * 2)
                          .clamp(0.0, constraints.maxWidth - spacing.s8);
                  return Padding(
                    padding: EdgeInsetsDirectional.only(start: spacing.s8),
                    child: SizedBox(
                      width: width,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: <Widget>[
                          bubble,
                          PositionedDirectional(
                            start: -spacing.s8,
                            top: 0,
                            child: CustomPaint(
                              size: Size(spacing.s8, spacing.s12),
                              painter: _BubbleTail(
                                color: colors.surface.overlay,
                                textDirection: Directionality.of(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A bubble's tail: a right triangle whose upright edge is the bubble's own
/// start edge and whose top runs out along the bubble's top.
final class _BubbleTail extends CustomPainter {
  const _BubbleTail({required this.color, required this.textDirection});

  final Color color;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final edge = textDirection == TextDirection.ltr ? size.width : 0.0;
    final tip = textDirection == TextDirection.ltr ? 0.0 : size.width;
    canvas.drawPath(
      Path()
        ..moveTo(tip, 0)
        ..lineTo(edge, 0)
        ..lineTo(edge, size.height)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_BubbleTail oldDelegate) =>
      oldDelegate.color != color || oldDelegate.textDirection != textDirection;
}

/// The document a PDF receipt arrives as, in the bubble above its message.
final class _DocumentTile extends StatelessWidget {
  const _DocumentTile();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.raised,
        borderRadius: BorderRadius.circular(tokens.radius.md),
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.s12),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.picture_as_pdf_outlined,
              size: tokens.spacing.s32,
              color: colors.text.secondary,
            ),
            SizedBox(width: tokens.spacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    eReceiptPreviewFileName,
                    key: const ValueKey('e-receipts-preview-file'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.typography.labelMedium.copyWith(
                      color: colors.text.primary,
                    ),
                  ),
                  Text(
                    '1 page · PDF',
                    style: tokens.typography.caption.copyWith(
                      color: colors.text.tertiary,
                    ),
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

/// The name over a group of flat rows: `label.md` in the body colour, quieter
/// than the rows it heads, as a phone's settings list heads a section.
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

/// One receipt that was sent, or was not, as a chat list draws a chat: who and
/// when, then what became of it, then why - only when there is a reason.
///
/// **WhatsApp's ticks, and the word beside them every time.** One tick for
/// sent, two for delivered, two lit for read, and a clock for one that has not
/// left: the marks the customer reads on their own phone. Only *Read* is lit,
/// the way WhatsApp turns its ticks blue - sent and delivered are on their way,
/// read is the receipt in the customer's hand. Two ticks differ from two ticks
/// only by colour, which is why the word is never left out.
final class _DeliveryRow extends StatelessWidget {
  const _DeliveryRow({required this.delivery, required this.now});

  final TenantReceiptDelivery delivery;
  final DateTime now;

  static (IconData, Color) _mark(
    ReceiptDeliveryStatus status,
    AppColorRoles colors,
  ) => switch (status) {
    ReceiptDeliveryStatus.queued ||
    ReceiptDeliveryStatus.sending => (Icons.schedule, colors.status.info.fg),
    ReceiptDeliveryStatus.sent => (Icons.check, colors.text.secondary),
    ReceiptDeliveryStatus.delivered => (Icons.done_all, colors.text.secondary),
    ReceiptDeliveryStatus.read => (Icons.done_all, colors.status.ok.fg),
    ReceiptDeliveryStatus.failed => (
      Icons.error_outline,
      colors.status.problem.fg,
    ),
    // A customer who said STOP, or receipts switched off, is the system
    // working: the quietest ink a person is still expected to read.
    ReceiptDeliveryStatus.skipped => (
      Icons.remove_circle_outline,
      colors.text.tertiary,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final spacing = tokens.spacing;
    final (glyph, tint) = _mark(delivery.status, colors);
    final line = tokens.typography.bodyMedium.copyWith(
      color: colors.text.secondary,
    );
    final quiet = tokens.typography.caption.copyWith(
      color: colors.text.tertiary,
    );
    final when = receiptDeliveryWhen(delivery.createdAt, now);
    final number = delivery.receiptNumber;
    final reason = delivery.reasonText;

    return MergeSemantics(
      key: ValueKey('e-receipts-delivery-${delivery.id}'),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: spacing.s12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _Avatar(name: delivery.customerName),
            SizedBox(width: spacing.s16),
            Expanded(
              // Centred on the avatar while it is the taller of the two, and
              // growing down past it when a reason makes a third line.
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: spacing.s48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            delivery.customerName ?? delivery.phoneMasked,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tokens.typography.bodyLarge.copyWith(
                              color: colors.text.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (when != null) ...<Widget>[
                          SizedBox(width: spacing.s8),
                          Text(when, style: quiet),
                        ],
                      ],
                    ),
                    Row(
                      children: <Widget>[
                        Icon(glyph, size: spacing.s16, color: tint),
                        SizedBox(width: spacing.s4),
                        Text(
                          delivery.status.label,
                          style: line.copyWith(
                            color: tint,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (number != null) ...<Widget>[
                          SizedBox(width: spacing.s4),
                          Expanded(
                            child: Text(
                              '· $number',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: line,
                            ),
                          ),
                        ] else
                          const Spacer(),
                        SizedBox(width: spacing.s12),
                        // The timing rows' own glyphs, so this list and the
                        // settings say *automatically* and *by hand* alike.
                        Icon(
                          delivery.automatic
                              ? Icons.bolt_outlined
                              : Icons.touch_app_outlined,
                          size: spacing.s16,
                          color: colors.text.tertiary,
                          semanticLabel: delivery.automatic
                              ? 'Sent automatically'
                              : 'Sent by hand',
                        ),
                      ],
                    ),
                    if (reason != null) Text(reason, style: quiet),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Who a receipt went to, as a chat list's avatar: their initials, or a person
/// glyph for a number with no name - as WhatsApp draws a number it has no name
/// for. Decoration: the name beside it is what a screen reader is given.
final class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});

  final String? name;

  /// The first letter of the first two words, the way a chat list shortens a
  /// name. Empty for a name with no letters in it.
  static String initials(String name) => name
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .take(2)
      .map((word) => String.fromCharCode(word.runes.first))
      .join()
      .toUpperCase();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final letters = switch (name) {
      final name? => initials(name),
      null => '',
    };
    return ExcludeSemantics(
      child: Container(
        width: tokens.spacing.s48,
        height: tokens.spacing.s48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.surface.overlay,
        ),
        child: letters.isEmpty
            ? Icon(
                Icons.person,
                size: tokens.spacing.s24,
                color: colors.text.tertiary,
              )
            : Text(
                letters,
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
/// top of the tab without pretending to know the count. Each pair is how much
/// of the row its name line and its status line take, so the three are not
/// one shape stamped three times.
const List<(double, double)> _readingRows = <(double, double)>[
  (0.58, 0.72),
  (0.44, 0.64),
  (0.52, 0.70),
];

/// A [_DeliveryRow]'s shape with its words still arriving: a circle where the
/// avatar lands, the name and the time on one line, the status under it.
///
/// The same padding and the same avatar-high body as the row, so nothing moves
/// when the real rows land. The bars are drawn on the avatar's own surface
/// step, the one a placeholder inside a raised thing takes.
final class _DeliveryRowSkeleton extends StatelessWidget {
  const _DeliveryRowSkeleton({
    required this.nameFactor,
    required this.lineFactor,
  });

  final double nameFactor;
  final double lineFactor;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final spacing = tokens.spacing;
    const tone = SkeletonTone.onRaised;
    final bar = tokens.radius.sm;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: spacing.s12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SkeletonBlock(
            width: spacing.s48,
            height: spacing.s48,
            radius: tokens.radius.pill,
            tone: tone,
          ),
          SizedBox(width: spacing.s16),
          Expanded(
            child: SizedBox(
              height: spacing.s48,
              child: LayoutBuilder(
                builder: (context, constraints) => Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        SkeletonBlock(
                          width: constraints.maxWidth * nameFactor,
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
                    SizedBox(height: spacing.s8),
                    SkeletonBlock(
                      width: constraints.maxWidth * lineFactor,
                      height: spacing.s12,
                      radius: bar,
                      tone: tone,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One tab's list, kept alive while the other tab is shown.
///
/// The Configs screen's own arrangement: without it a swipe to *Sent receipts*
/// and back rebuilds the settings list from the top.
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
