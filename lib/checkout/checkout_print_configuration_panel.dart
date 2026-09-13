/// The route that tells this business where its printer is.
///
/// **This is the surface that makes printing reachable at all.** Everything
/// under it has been built and tested since 2026-08-17 — the transport, the
/// durable queue, the receipt body, the dispatcher — and none of it could run,
/// because `docs/printer_transport.md` §6 forbids guessing an address and
/// nobody could supply one.
///
/// **It is built on `checkout_configuration_panel.dart`**, which writes the
/// sibling document, and follows it deliberately: the same guard on the *write*
/// roles rather than the read ones, the same intent-before-confirmation order,
/// the same four write outcomes mapped to `AppNotice`, and the same re-read on
/// anything that is not a flat refusal.
///
/// **The test print is why this is a screen rather than a settings row.**
/// *Test this printer* puts a page on the roll — the mark, the settings and a
/// ruler one row wide — which is the first thing worth having when a shop
/// phones in. It runs against what is **typed**, not what is stored, so a
/// printer can be checked before it is saved.
library;

import 'package:flutter/material.dart';

import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../ui/buttons.dart';
import '../ui/dialogs.dart';
import '../ui/fields.dart';
import '../ui/scaffold.dart';
import '../ui/states.dart';
import '../ui/snackbar.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'checkout_configuration_writer.dart';
import 'checkout_print_configuration.dart';
import 'checkout_print_failures.dart';
import 'checkout_print_transport_base.dart';

/// Prints one test page against what is **typed**. Injected so a test never
/// opens a socket, and so a build with no transport simply cannot offer it.
///
/// **It takes the whole configuration rather than an address**, because the
/// page prints the paper width and the cutter setting and is laid out to that
/// width: testing an 80mm roll with a 58mm setting is one of the two faults
/// this control exists to catch, and a function handed only a host could not
/// catch it.
typedef PrinterTestPrint =
    Future<void> Function(TenantPrinterConfiguration configuration);

final class TenantPrinterConfigurationScreen extends StatelessWidget {
  const TenantPrinterConfigurationScreen({
    super.key,
    required this.reader,
    this.writer,
    this.testPrint,
    this.onPublished,
  });

  final TenantDocumentReader reader;

  /// Supplied by the composition root. While it is absent this route is exactly
  /// a read-only statement of what is configured, as every other injected
  /// capability in this app behaves.
  final TenantConfigurationDocumentWriter? writer;

  /// While absent, *Test this printer* is not offered. A control that cannot
  /// work is worse than a missing one.
  final PrinterTestPrint? testPrint;

  final VoidCallback? onPublished;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Printer',
    // §4.2's "reading and forms" row. This is a form.
    contentWidth: AppContentWidth.reading,
    body: SingleChildScrollView(
      padding: EdgeInsets.all(
        AppScaffold.horizontalInset(AppTokens.componentOf(context).spacing),
      ),
      child: TenantPrinterConfigurationPanel(
        reader: reader,
        writer: writer,
        testPrint: testPrint,
        onPublished: onPublished,
      ),
    ),
  );
}

final class TenantPrinterConfigurationPanel extends StatefulWidget {
  const TenantPrinterConfigurationPanel({
    super.key,
    required this.reader,
    this.writer,
    this.testPrint,
    this.onPublished,
  });

  final TenantDocumentReader reader;
  final TenantConfigurationDocumentWriter? writer;
  final PrinterTestPrint? testPrint;
  final VoidCallback? onPublished;

  @override
  State<TenantPrinterConfigurationPanel> createState() =>
      _TenantPrinterConfigurationPanelState();
}

final class _TenantPrinterConfigurationPanelState
    extends State<TenantPrinterConfigurationPanel> {
  int _generation = 0;
  bool _busy = false;

  void _reload() => setState(() => _generation++);

  static String _sessionKey(TenantSession session) =>
      '${session.uid}:${session.tenantId}:${session.epoch}';

  bool _stillCurrent(String capturedKey) {
    if (!mounted) return false;
    final current = TenantSessionScope.of(context).session;
    return current != null && _sessionKey(current) == capturedKey;
  }

  Future<void> _publish(
    TenantSession session,
    TenantConfiguredPrinter configured,
    _PrinterFormValues values,
  ) async {
    final writer = widget.writer;
    if (writer == null || _busy) return;
    final capturedKey = _sessionKey(session);

    // The intent is built before anything is confirmed, so an address this
    // boundary would refuse is reported rather than asked about, and the
    // sentence in the confirmation describes the write that would be issued.
    final TenantPrinterUpdateIntent intent;
    try {
      intent =
          TenantPrinterConfigurationPublisher(
            session: session,
            reader: widget.reader,
          ).buildUpdateIntent(
            transport: values.transport,
            host: values.host,
            port: values.port,
            paperWidth: values.paperWidth,
            hasCutter: values.hasCutter,
            bridgeToken: values.bridgeToken,
            configured: configured,
          );
    } on TenantPrinterConfigurationException catch (error) {
      _report(_refusalNotice(error.code));
      return;
    }
    if (!await _confirmed(intent) || !_stillCurrent(capturedKey)) return;

    setState(() {
      _busy = true;
    });
    try {
      final result = await writer.merge(
        path: intent.path,
        data: intent.documentData(),
      );
      if (!_stillCurrent(capturedKey)) return;
      _report(_resultNotice(result));
      // A committed change and an unknown one are both re-read: the second
      // because only the server says what is stored, and the first because the
      // document is what a receipt will be dialled at, not the typed value.
      if (result.kind != TenantConfigurationWriteKind.rejected) _reload();
      if (result.kind == TenantConfigurationWriteKind.committed) {
        widget.onPublished?.call();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Prints a test page on what is **typed**.
  ///
  /// Deliberately not against what is stored: the whole use is checking a
  /// printer before committing to it. It builds its own
  /// `TenantPrinterConfiguration`, so the same validation that guards the
  /// document guards this.
  ///
  /// **It prints rather than probes, at the product owner's direction on
  /// 2026-09-03.** A connect-and-close answered *is that address reachable*,
  /// and the question a shopkeeper is actually asking is whether a receipt will
  /// come out and be readable. Only paper answers that, and the paper is also
  /// the only thing that can show a width set to the wrong roll.
  Future<void> _test(_PrinterFormValues values) async {
    final testPrint = widget.testPrint;
    if (testPrint == null || _busy) return;
    final parsedPort = int.tryParse(values.port.trim());
    final TenantPrinterConfiguration configuration;
    try {
      if (parsedPort == null) throw ArgumentError('port');
      configuration = TenantPrinterConfiguration(
        transport: values.transport,
        endpoint: PrinterEndpoint(host: values.host.trim(), port: parsedPort),
        paperWidth: values.paperWidth,
        hasCutter: values.hasCutter,
        bridgeToken: values.bridgeToken,
      );
    } on ArgumentError {
      _report(_refusalNotice('invalid_address'));
      return;
    } on FormatException {
      _report(_refusalNotice('invalid_address'));
      return;
    }
    setState(() {
      _busy = true;
    });
    try {
      await testPrint(configuration);
      if (!mounted) return;
      // **"Sent", never "printed".** `PrinterTransport.send` returning means
      // the bytes were handed off, and this app has no status read-back to
      // prove paper moved - so the sentence names what was sent and asks the
      // one person who can see the roll to look at it.
      _report(
        const AppNotice.confirmed(
          'A test page was sent to the printer. Check that what comes out '
          'fills the width of the roll.',
        ),
      );
    } on PrinterTransportException catch (error) {
      if (!mounted) return;
      // The transport's own vocabulary, mapped once at the UI edge exactly as
      // a failed receipt is. This screen invents no sentence of its own.
      _report(PrinterFailureNotice.of(error.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Announces a test print's answer over the screen rather than inside the
  /// form.
  ///
  /// **A snack bar rather than the `Callout` this used until 2026-08-26**: the
  /// answer belongs to the control that was just pressed, and inside the form
  /// it sat below the buttons - so on a phone the answer to a button appeared
  /// off the bottom of the screen.
  void _report(AppNotice notice) => showAppSnackBar(context, notice);

  Future<bool> _confirmed(TenantPrinterUpdateIntent intent) async {
    final moving = intent.movesAWorkingPrinter;
    final previous = intent.replaces.configuration?.endpoint;
    final confirmed = await showConfirmDialog(
      context,
      title: moving
          ? 'Point receipts at a different printer?'
          : 'Save this printer?',
      consequence: moving
          ? 'Receipts printed after this go to ${intent.configuration.endpoint} '
                'instead of $previous.'
          : 'Receipts are sent to ${intent.configuration.endpoint} on '
                '${intent.configuration.paperWidth.columns}-column paper.',
      // §8 rule 6, and it is the one thing worth warning about: a queued job
      // carries its own address, so a receipt already waiting still goes where
      // it was queued to go.
      stillTrue: moving
          ? 'Any receipt already waiting to print keeps the address it was '
                'queued with, so it still goes to $previous.'
          : null,
      confirmLabel: moving ? 'Change printer' : 'Save',
      tier: AppButtonTier.primary,
      confirmKey: const ValueKey('printer-configuration-confirm'),
      cancelKey: const ValueKey('printer-configuration-cancel'),
    );
    return confirmed && mounted;
  }

  void _composeLoaders(String key) {
    if (key == _loaderKey && _loader != null) return;
    _loaderKey = key;
    TenantGuardedLoader<TenantConfiguredPrinter> readWith(
      TenantDocumentReader reader,
    ) =>
        (session) => TenantPrinterConfigurationPublisher(
          session: session,
          reader: reader,
        ).loadConfigured();
    _loader = readWith(widget.reader);
    final cache = widget.reader.cached;
    _loaderCached = cache == null ? null : readWith(cache);
  }

  String? _loaderKey;
  TenantGuardedLoader<TenantConfiguredPrinter>? _loader;
  TenantGuardedLoader<TenantConfiguredPrinter>? _loaderCached;

  @override
  Widget build(BuildContext context) {
    final guardKey = 'printer-configuration:$_generation';
    _composeLoaders(guardKey);
    return TenantRouteGuard<TenantConfiguredPrinter>(
      allowedRoles: TenantPrinterConfigurationPublisher.allowedRoles,
      load: _loader!,
      loadCached: _loaderCached,
      loading: const LoadingState(message: 'Reading the printer settings.'),
      denied: const ErrorState(
        key: ValueKey('printer-configuration-denied'),
        badgeLabel: 'No access',
        statement: 'Only an owner or administrator may set up the printer.',
        stillTrue: 'Receipts still print on whatever is already set up.',
      ),
      failure: (context, error) => const ErrorState(
        key: ValueKey('printer-configuration-failure'),
        badgeLabel: 'Not read',
        statement: 'The printer settings could not be read.',
        stillTrue: 'Nothing was changed.',
      ),
      builder: (context, session, configured) => _PrinterContents(
        configured: configured,
        busy: _busy,
        canPublish: widget.writer != null,
        canTest: widget.testPrint != null,
        onPublish: (values) => _publish(session, configured, values),
        onTest: _test,
      ),
    );
  }
}

AppNotice _resultNotice(TenantConfigurationWriteResult result) =>
    switch (result.kind) {
      TenantConfigurationWriteKind.queued => const AppNotice.offline(
        'Saved on this device; waiting to sync.',
      ),
      TenantConfigurationWriteKind.committed => const AppNotice.confirmed(
        'Saved. Receipts from this device go there from the next sale.',
      ),
      TenantConfigurationWriteKind.rejected => const AppNotice.refused(
        'The change was refused and nothing was saved. Only an owner or '
        'administrator may change this.',
      ),
      TenantConfigurationWriteKind.ambiguous => const AppNotice.unknown(
        'The result is unknown. This page has been re-read; saving the same '
        'printer again is safe, because this names one setting and one value.',
      ),
      TenantConfigurationWriteKind.unavailable => const AppNotice.offline(
        'This device is offline, so nothing was saved. The printer can only '
        'be set up while online.',
      ),
    };

/// **`printer_unchanged` is not a refusal**, and this is the surface where the
/// difference matters: the printer the operator wanted saved *is* what is
/// saved, so the intent is satisfied. Every other branch is the client refusing
/// before anything was sent.
AppNotice _refusalNotice(String code) => switch (code) {
  'invalid_address' => const AppNotice.refused(
    'Enter the printer address as a name or an IP, with no http:// and no '
    'port after it, such as 192.168.1.50.',
  ),
  'invalid_port' => const AppNotice.refused(
    'Enter the port as a number between 1 and 65535. Most network printers '
    'use 9100.',
  ),
  'printer_unchanged' => const AppNotice.offline(
    'That is already the printer this business uses.',
  ),
  'printer_forbidden' => const AppNotice.refused(
    'Only an owner or administrator may set up the printer.',
  ),
  _ => const AppNotice.refused('The printer could not be saved.'),
};

/// Everything the form holds, as one value rather than six arguments.
final class _PrinterFormValues {
  const _PrinterFormValues({
    required this.transport,
    required this.host,
    required this.port,
    required this.paperWidth,
    required this.hasCutter,
  });

  final PrinterTransportKind transport;
  final String host;
  final String port;
  final PrinterPaperWidth paperWidth;
  final bool hasCutter;

  /// **Phase 2's bridge token is not collected and the field is not here.**
  /// The token belongs to the HTTP bridge, the bridge is unbuilt, and a form
  /// asking for a credential nothing checks would be a form teaching somebody
  /// that it does something. `TenantPrinterConfiguration` carries the field so
  /// the document is ready; the *form* gains it with the bridge.
  String? get bridgeToken => null;
}

final class _PrinterContents extends StatefulWidget {
  const _PrinterContents({
    required this.configured,
    required this.busy,
    required this.canPublish,
    required this.canTest,
    required this.onPublish,
    required this.onTest,
  });

  final TenantConfiguredPrinter configured;
  final bool busy;
  final bool canPublish;
  final bool canTest;
  final void Function(_PrinterFormValues values) onPublish;
  final void Function(_PrinterFormValues values) onTest;

  @override
  State<_PrinterContents> createState() => _PrinterContentsState();
}

class _PrinterContentsState extends State<_PrinterContents> {
  late final TextEditingController _host = TextEditingController(
    text: widget.configured.configuration?.endpoint.host ?? '',
  );
  late final TextEditingController _port = TextEditingController(
    text:
        widget.configured.configuration?.endpoint.port.toString() ??
        PrinterEndpoint.rawEscPosPort.toString(),
  );
  late PrinterPaperWidth _paperWidth =
      widget.configured.configuration?.paperWidth ??
      PrinterPaperWidth.columns32;
  late bool _hasCutter = widget.configured.configuration?.hasCutter ?? true;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  /// **Only a presence check.** Which addresses are acceptable is the
  /// publisher's decision and a refusal from it is reported as a sentence —
  /// disabling the button on the same rule would leave a typo unexplained,
  /// which is the argument `checkout_configuration_panel.dart` already records.
  bool get _hasSomethingToSubmit =>
      !widget.busy &&
      _host.text.trim().isNotEmpty &&
      _port.text.trim().isNotEmpty;

  _PrinterFormValues get _values => _PrinterFormValues(
    // **Phase 1 is direct TCP and the form does not offer a choice.** The
    // bridge is Phase 2 and unbuilt, so a transport selector would offer a
    // mode that resolves to a stub that throws. It becomes a field when there
    // is a second thing to pick.
    transport: PrinterTransportKind.directTcp,
    host: _host.text,
    port: _port.text,
    paperWidth: _paperWidth,
    hasCutter: _hasCutter,
  );

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final configured = widget.configured;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // **This screen opens on the fold since 2026-08-26.** It used to begin
        // with `SectionHeading('Where receipts print')` under an app bar and a
        // page header both already reading *Printer* - §7's "title appears
        // once", stated three times - and then a loose grey paragraph before
        // anything a person could act on.
        //
        // §7's *Long copy*: policy rather than current state, so it folds.
        const Disclosure(
          key: ValueKey('printer-configuration-scope'),
          summary: 'How printing works',
          child: Text(
            key: ValueKey('printer-configuration-scope-body'),
            'A sale is recorded before its receipt is sent, so a printer that '
            'is off or jammed never stops a sale. Each receipt waits its turn '
            'and is sent once; if it fails it is kept, with the reason, until '
            'somebody sends it again. Nothing here proves paper came out - the '
            'app can only say the receipt reached the printer.',
          ),
        ),
        SizedBox(height: tokens.spacing.s12),
        // **The paragraph that was the subtitle, as the status it always
        // was.** Whether receipts are going anywhere at all is not prose about
        // the screen, it is the screen's standing - and §2.1 wants a container,
        // a glyph and a word for that, which a grey sentence is not. §9's rule
        // that a status is never carried by text alone is the same point.
        //
        // `problem` for settings that cannot be read is §2.1's own
        // *"unreadable"*; `attention` for none set up is its *"awaiting"*,
        // because that is a setup step nobody has taken yet.
        Callout(
          key: const ValueKey('printer-configuration-current'),
          status: switch (configured.state) {
            TenantPrinterConfigurationState.configured => AppStatus.info,
            TenantPrinterConfigurationState.absent => AppStatus.attention,
            TenantPrinterConfigurationState.malformed => AppStatus.problem,
          },
          message: switch (configured.state) {
            TenantPrinterConfigurationState.configured =>
              'Receipts go to ${configured.configuration!.endpoint} on '
                  '${configured.configuration!.paperWidth.columns}-column '
                  'paper.',
            TenantPrinterConfigurationState.absent =>
              'No printer is set up, so receipts are not sent anywhere. Sales '
                  'are recorded as normal.',
            TenantPrinterConfigurationState.malformed =>
              'The saved printer settings cannot be read, so receipts are not '
                  'sent anywhere. Saving a printer here replaces them.',
          },
        ),
        if (!widget.canPublish) ...<Widget>[
          SizedBox(height: tokens.spacing.s12),
          const Callout(
            key: ValueKey('printer-configuration-read-only'),
            status: AppStatus.info,
            message: 'This build cannot change the printer from here.',
          ),
        ] else ...<Widget>[
          SizedBox(height: tokens.spacing.s16),
          AppTextField(
            key: const ValueKey('printer-configuration-host'),
            controller: _host,
            enabled: !widget.busy,
            onChanged: (_) => setState(() {}),
            label: 'Printer address',
            leading: Icons.print_outlined,
            helper:
                'The name or IP the printer shows on its own test page, '
                'such as 192.168.1.50.',
          ),
          SizedBox(height: tokens.spacing.s8),
          AppTextField(
            key: const ValueKey('printer-configuration-port'),
            controller: _port,
            enabled: !widget.busy,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            label: 'Port',
            helper: 'Almost always ${PrinterEndpoint.rawEscPosPort}.',
          ),
          SizedBox(height: tokens.spacing.s12),
          AppSelect<PrinterPaperWidth>(
            key: const ValueKey('printer-configuration-paper'),
            value: _paperWidth,
            enabled: !widget.busy,
            label: 'Paper width',
            helper:
                'The roll this printer takes. It decides how the receipt '
                'is laid out.',
            items: <AppSelectItem<PrinterPaperWidth>>[
              for (final width in PrinterPaperWidth.values)
                AppSelectItem<PrinterPaperWidth>(
                  value: width,
                  label: width.label,
                ),
            ],
            onChanged: (value) =>
                setState(() => _paperWidth = value ?? _paperWidth),
          ),
          SizedBox(height: tokens.spacing.s8),
          CheckboxListTile(
            key: const ValueKey('printer-configuration-cutter'),
            value: _hasCutter,
            contentPadding: EdgeInsets.zero,
            title: const Text('This printer cuts the paper'),
            subtitle: const Text(
              'Without a cutter the receipt ends with blank paper to tear '
              'against instead.',
            ),
            onChanged: widget.busy
                ? null
                : (value) => setState(() => _hasCutter = value ?? false),
          ),
          SizedBox(height: tokens.spacing.s12),
          // Right-aligned since 2026-08-26, with the two sheets and for the
          // same reason: the control a right-handed thumb reaches should be
          // the one it presses. `AppActionRow` defaults to `end`, so this
          // stopped needing to say anything.
          AppActionRow(
            actions: <Widget>[
              AppButton(
                key: const ValueKey('printer-configuration-submit'),
                label: configured.canPrint ? 'Change printer' : 'Save printer',
                tier: AppButtonTier.primary,
                onPressed: _hasSomethingToSubmit
                    ? () => widget.onPublish(_values)
                    : null,
              ),
              // Offered only where a transport exists to probe with. It checks
              // what is typed, so an address can be tested before it is saved.
              if (widget.canTest)
                AppButton(
                  key: const ValueKey('printer-configuration-test'),
                  label: 'Test this printer',
                  icon: Icons.wifi_tethering,
                  onPressed: _hasSomethingToSubmit
                      ? () => widget.onTest(_values)
                      : null,
                ),
            ],
          ),
        ],
      ],
    );
  }
}
