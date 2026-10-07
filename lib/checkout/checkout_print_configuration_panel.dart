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
///
/// **Two tabs since 2026-10-03, at the developer's direction:** *Network* is
/// everything above, the business's printer for every till; *Bluetooth* finds,
/// pairs and connects a printer for this device alone -
/// `checkout_bluetooth_printer_panel.dart`. The page opens on whichever this
/// device is printing with.
library;

import 'package:uzapay_pos/observability/app_telemetry.dart';

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
import '../ui/tabs.dart';
import '../ui/tokens.dart';
import 'checkout_bluetooth_printer.dart';
import 'checkout_bluetooth_printer_panel.dart';
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
    this.bluetooth,
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

  /// While absent the page is the network form alone, with no tabs.
  final BluetoothPrinterSetup? bluetooth;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Printer',
    // §4.2's "reading and forms" row. This is a form.
    contentWidth: AppContentWidth.reading,
    // The panel scrolls and insets itself: its tabs are a `TabBarView`, which
    // needs the page's height rather than a scroll view's unbounded one.
    body: TenantPrinterConfigurationPanel(
      reader: reader,
      writer: writer,
      testPrint: testPrint,
      onPublished: onPublished,
      bluetooth: bluetooth,
    ),
  );
}

/// The printer settings, scrolled and inset by the panel itself.
///
/// **Host it with no scroll view round it** - `ownsScroll` on a settings
/// destination. With Bluetooth it is two tabs in a `TabBarView`, which needs a
/// height of its own and scrolls each tab separately; without, it is the
/// network form in a scroll view of its own, so both read the same to a host.
final class TenantPrinterConfigurationPanel extends StatefulWidget {
  const TenantPrinterConfigurationPanel({
    super.key,
    required this.reader,
    this.writer,
    this.testPrint,
    this.onPublished,
    this.bluetooth,
  });

  final TenantDocumentReader reader;
  final TenantConfigurationDocumentWriter? writer;
  final PrinterTestPrint? testPrint;
  final VoidCallback? onPublished;

  /// See [TenantPrinterConfigurationScreen.bluetooth].
  final BluetoothPrinterSetup? bluetooth;

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
    final telemetry = AppTelemetry.current;
    final operation = telemetry.start(
      'configuration.printer',
      screen: 'printer_configuration',
      context: {
        'user_id': session.uid,
        'tenant_id': session.tenantId,
        'transport': values.transport.name,
        'printer_host': values.host,
        'printer_port': values.port,
      },
    );
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
    } on TenantPrinterConfigurationException catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        operation: operation,
        boundary: 'configuration.printer_validate',
      );
      _report(_refusalNotice(error.code));
      return;
    }
    telemetry.recordStep(operation, 'validated');
    if (!await _confirmed(intent) || !_stillCurrent(capturedKey)) {
      telemetry.recordStep(operation, 'cancelled');
      return;
    }
    telemetry.recordStep(operation, 'confirmed');

    setState(() {
      _busy = true;
    });
    try {
      final result = await telemetry.trace(
        operation,
        'save_printer_configuration',
        () => writer.merge(path: intent.path, data: intent.documentData()),
      );
      if (result.kind == TenantConfigurationWriteKind.committed) {
        telemetry.recordStep(operation, 'confirmed_on_server');
      } else if (result.kind == TenantConfigurationWriteKind.queued) {
        telemetry.recordStep(operation, 'saved_locally');
      } else {
        AppTelemetry.captureHandled(
          StateError(result.kind.name),
          StackTrace.current,
          operation: operation,
          code: result.kind.name,
        );
      }
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
    final telemetry = AppTelemetry.current;
    final operation = telemetry.start(
      'printing.test_page',
      screen: 'printer_configuration',
      context: {'printer_host': values.host, 'printer_port': values.port},
    );
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
    } on ArgumentError catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        operation: operation,
        boundary: 'printing.test_validate',
      );
      _report(_refusalNotice('invalid_address'));
      return;
    } on FormatException catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        operation: operation,
        boundary: 'printing.test_validate',
      );
      _report(_refusalNotice('invalid_address'));
      return;
    }
    setState(() {
      _busy = true;
    });
    try {
      telemetry.recordStep(operation, 'submitted');
      await telemetry.trace(
        operation,
        'send_test_page',
        () => testPrint(configuration),
      );
      telemetry.recordStep(operation, 'confirmed');
      telemetry.finishOperation(operation);
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
    } on PrinterTransportException catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        operation: operation,
        boundary: 'printing.test_send',
      );
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
    // The inset the hosts used to pad this panel with, now applied inside it.
    final inset = AppScaffold.horizontalInset(
      AppTokens.componentOf(context).spacing,
    );
    Widget scrolled(Widget child) =>
        SingleChildScrollView(padding: EdgeInsets.all(inset), child: child);
    return TenantRouteGuard<TenantConfiguredPrinter>(
      allowedRoles: TenantPrinterConfigurationPublisher.allowedRoles,
      load: _loader!,
      loadCached: _loaderCached,
      loading: scrolled(
        const LoadingState(message: 'Reading the printer settings.'),
      ),
      denied: scrolled(
        const ErrorState(
          key: ValueKey('printer-configuration-denied'),
          badgeLabel: 'No access',
          statement: 'Only an owner or administrator may set up the printer.',
          stillTrue: 'Receipts still print on whatever is already set up.',
        ),
      ),
      failure: (context, error) => scrolled(
        const ErrorState(
          key: ValueKey('printer-configuration-failure'),
          badgeLabel: 'Not read',
          statement: 'The printer settings could not be read.',
          stillTrue: 'Nothing was changed.',
        ),
      ),
      builder: (context, session, configured) {
        final bluetooth = widget.bluetooth;
        // Read on every build, which is cheap - one key in a small box - and
        // means the network tab restates where receipts go the moment the
        // Bluetooth tab changes it.
        DeviceBluetoothPrinter? inUse;
        var bluetoothChosen = false;
        if (bluetooth != null) {
          try {
            inUse = bluetooth.store.read(session.tenantId);
            bluetoothChosen = inUse != null;
          } on FormatException {
            // Unreadable is still *chosen*: the Bluetooth tab owns saying so,
            // and this device is not printing on the network printer.
            bluetoothChosen = true;
          }
        }
        final network = _PrinterContents(
          configured: configured,
          bluetoothInUse: inUse,
          busy: _busy,
          canPublish: widget.writer != null,
          canTest: widget.testPrint != null,
          onPublish: (values) => _publish(session, configured, values),
          onTest: _test,
        );
        if (bluetooth == null) return scrolled(network);
        return _PrinterTabs(
          inset: inset,
          startOnBluetooth: bluetoothChosen,
          network: network,
          bluetooth: BluetoothPrinterTab(
            setup: bluetooth,
            tenantId: session.tenantId,
            // Already read for the network tab; the Bluetooth tab says where
            // this device prints from it rather than reading it again.
            business: configured,
            testPrint: widget.testPrint,
            onChanged: () => setState(() {}),
          ),
        );
      },
    );
  }
}

/// *Network* and *Bluetooth*, as two tabs of one page.
///
/// **A `TabBarView`, as every other tabbed page is**, at the developer's
/// direction on 2026-10-05. Until then the two were shown one at a time inside
/// the host's scroll view, so a swipe moved nothing under the finger - and the
/// first fix, a swipe that changed tab on release, still did not. Here a tab
/// follows the finger, springs back from a short drag, and keeps its own
/// scroll position. Both stay alive once opened, so switching never loses
/// what was typed or found.
final class _PrinterTabs extends StatelessWidget {
  const _PrinterTabs({
    required this.inset,
    required this.startOnBluetooth,
    required this.network,
    required this.bluetooth,
  });

  /// The page's own inset, which the strip and each tab's scroll take.
  final double inset;

  /// Open on the tab this device is printing with.
  final bool startOnBluetooth;
  final Widget network;
  final Widget bluetooth;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    // Both tabs open on a `Disclosure`, whose line sits in its focus-ring
    // gutter: `s12` here puts it `s16` under the tabs, where
    // `docs/design/bluetooth-printer/` draws it.
    Widget tab(Widget child) => AppKeptTab(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(inset, tokens.spacing.s12, inset, inset),
        child: child,
      ),
    );
    return DefaultTabController(
      length: 2,
      initialIndex: startOnBluetooth ? 1 : 0,
      child: Column(
        key: const ValueKey('printer-configuration-tabs'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppTabs(tabs: const <String>['Network', 'Bluetooth'], inset: inset),
          Expanded(
            child: TabBarView(children: <Widget>[tab(network), tab(bluetooth)]),
          ),
        ],
      ),
    );
  }
}

AppNotice _resultNotice(TenantConfigurationWriteResult result) =>
    switch (result.kind) {
      // Every save is queued, online or not, so this is the settings pages'
      // own sentence rather than one that announces an outage.
      TenantConfigurationWriteKind.queued => const AppNotice.confirmed(
        'Saved on this device and on its way to the others.',
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
    required this.bluetoothInUse,
    required this.busy,
    required this.canPublish,
    required this.canTest,
    required this.onPublish,
    required this.onTest,
  });

  final TenantConfiguredPrinter configured;

  /// The Bluetooth printer this device prints on instead, or null.
  final DeviceBluetoothPrinter? bluetoothInUse;
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
      PrinterPaperWidth.columns48;
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
            'somebody sends it again.',
          ),
        ),
        // **The paragraph that was the subtitle, as the status it always
        // was.** Whether receipts are going anywhere at all is not prose about
        // the screen, it is the screen's standing - and §2.1 wants a container,
        // a glyph and a word for that, which a grey sentence is not. §9's rule
        // that a status is never carried by text alone is the same point.
        //
        // `problem` for settings that cannot be read is §2.1's own
        // *"unreadable"*; `attention` for none set up is its *"awaiting"*,
        // because that is a setup step nobody has taken yet.
        //
        // **This device's exception, stated where the business setting is.**
        // A Bluetooth printer chosen here takes this device's receipts, so the
        // form below no longer describes them - only the other tills'.
        if (widget.bluetoothInUse case final inUse?) ...<Widget>[
          SizedBox(height: tokens.spacing.s12),
          Callout(
            key: const ValueKey('printer-configuration-bluetooth-in-use'),
            status: AppStatus.info,
            icon: Icons.bluetooth_connected,
            message:
                'This device prints its receipts on the Bluetooth printer '
                '${inUse.name}. The network printer here is for this '
                'business’s other devices.',
          ),
        ],
        // **Only when receipts are going nowhere**, since 2026-09-23: a working
        // printer is already stated by the filled fields under it. Not on a
        // device printing over Bluetooth, where it would not be true.
        if (!configured.canPrint && widget.bluetoothInUse == null) ...<Widget>[
          SizedBox(height: tokens.spacing.s12),
          Callout(
            key: const ValueKey('printer-configuration-current'),
            status: configured.state == TenantPrinterConfigurationState.absent
                ? AppStatus.attention
                : AppStatus.problem,
            message: configured.state == TenantPrinterConfigurationState.absent
                ? 'No printer is set up, so receipts are not sent anywhere. '
                      'Sales are recorded as normal.'
                : 'The saved printer settings cannot be read, so receipts are '
                      'not sent anywhere. Saving a printer here replaces them.',
          ),
        ],
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
          ),
          SizedBox(height: tokens.spacing.s8),
          AppTextField(
            key: const ValueKey('printer-configuration-port'),
            controller: _port,
            enabled: !widget.busy,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            label: 'Port',
          ),
          SizedBox(height: tokens.spacing.s12),
          AppSelect<PrinterPaperWidth>(
            key: const ValueKey('printer-configuration-paper'),
            value: _paperWidth,
            enabled: !widget.busy,
            label: 'Paper width',
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
