/// The printer page's USB tab, in a browser: choose the USB printer plugged
/// into this computer.
///
/// **It decides where *this browser* prints, and nothing else** - the network
/// tab beside it sets the business's printer for every till, and this one
/// stores a USB printer in the browser it is opened in. See
/// `checkout_usb_printer.dart` for why.
///
/// **Choosing is the browser's own picker**, which lists the USB printers it
/// can see; a page cannot list them itself. A printer is stored only once it
/// has answered: choosing opens it, claims it and lets it go through the same
/// transport a receipt uses. *Test print* puts the test page on the roll.
///
/// **Nothing is asked of the browser until a person presses something**, and
/// the browser insists on that: its picker opens for a press and for nothing
/// else.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uzapay_pos/observability/app_telemetry.dart';

import '../ui/buttons.dart';
import '../ui/card.dart';
import '../ui/fields.dart';
import '../ui/snackbar.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'checkout_print_configuration.dart';
import 'checkout_print_failures.dart';
import 'checkout_print_helper.dart';
import 'checkout_print_helper_panel.dart';
import 'checkout_print_transport_base.dart';
import 'checkout_usb_printer.dart';

/// Everything the USB tab needs from the composition root.
final class UsbPrinterSetup {
  const UsbPrinterSetup({
    required this.chooser,
    required this.store,
    required this.probe,
    this.onChosen,
    this.helper,
  });

  final UsbPrinterChooser chooser;
  final DeviceUsbPrinterStore store;

  /// The transport's `probe`: opens and lets go of a printer without
  /// printing. Injected so a test never touches a browser.
  final Future<void> Function(PrinterEndpoint endpoint) probe;

  /// Called once a printer is chosen here, so the print dialog - the other
  /// way this device can print on its own - is forgotten and one choice
  /// stands. Absent where there is no print dialog to forget.
  final Future<void> Function(String tenantId)? onChosen;

  /// The print helper, on a web till on Windows: the USB printers it finds
  /// are offered above the browser's own picker, because they need no
  /// driver changed. Null everywhere else.
  final PrintHelperSetup? helper;
}

/// What the tab is doing, so one control at a time is busy.
enum _Step { idle, choosing, connecting, testing, forgetting }

final class UsbPrinterTab extends StatefulWidget {
  const UsbPrinterTab({
    super.key,
    required this.setup,
    required this.tenantId,
    required this.onChanged,
    this.testPrint,
  });

  final UsbPrinterSetup setup;

  /// The business this browser's choice is stored under.
  final String tenantId;

  /// Prints the test page - the network tab's own. Null hides *Test print*.
  final Future<void> Function(TenantPrinterConfiguration configuration)?
  testPrint;

  /// Called after this browser's printer is chosen or forgotten, so the page
  /// around the tab can restate where receipts go.
  final VoidCallback onChanged;

  @override
  State<UsbPrinterTab> createState() => _UsbPrinterTabState();
}

class _UsbPrinterTabState extends State<UsbPrinterTab> {
  DeviceUsbPrinter? _current;
  bool _currentUnreadable = false;

  /// Printers this site was allowed to use before, which can be chosen again
  /// without the picker.
  List<UsbPrinterDevice> _permitted = const <UsbPrinterDevice>[];

  /// Printers the print helper can reach through Windows' own driver.
  List<UsbPrinterDevice> _helperPrinters = const <UsbPrinterDevice>[];

  /// Whether the print helper answered the last look.
  bool _helperRunning = false;

  /// Asking the helper again while it finds no printer, so plugging one in
  /// is all anybody has to do.
  Timer? _printerWatch;

  /// How often, and for how long, the tab asks again.
  static const Duration _watchEvery = Duration(seconds: 3);
  static const Duration _watchFor = Duration(minutes: 10);

  /// **80mm with a cutter by default**, the network form's own defaults: a
  /// printer on a cable is the counter-top kind, not the portable one.
  PrinterPaperWidth _paperWidth = PrinterPaperWidth.columns48;
  bool _hasCutter = true;

  _Step _step = _Step.idle;

  /// The last answer to a press, shown in the tab.
  AppNotice? _answer;

  UsbPrinterChooser get _chooser => widget.setup.chooser;

  @override
  void initState() {
    super.initState();
    _readCurrent();
    unawaited(_readPermitted());
  }

  @override
  void dispose() {
    _printerWatch?.cancel();
    super.dispose();
  }

  void _readCurrent() {
    try {
      _current = widget.setup.store.read(widget.tenantId);
      _currentUnreadable = false;
    } on FormatException {
      _current = null;
      _currentUnreadable = true;
    }
    if (_current case final current?) {
      _paperWidth = current.paperWidth;
      _hasCutter = current.hasCutter;
    }
  }

  Future<void> _readPermitted() async {
    // With the helper there is no browser picker to have allowed anything.
    if (!_chooser.isSupported || widget.setup.helper != null) return;
    try {
      final devices = await _chooser.permitted();
      if (mounted) setState(() => _permitted = devices);
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'printing.usb_permitted',
      );
    }
  }

  /// What the helper card found: when the helper is running, what it can
  /// print to.
  void _onHelperLooked(bool running) {
    setState(() => _helperRunning = running);
    if (running) {
      unawaited(_readHelperPrinters());
    } else {
      _printerWatch?.cancel();
    }
  }

  /// Asks the print helper which USB printers it can print to, and keeps
  /// asking while it finds none and none is chosen.
  Future<void> _readHelperPrinters() async {
    final helper = widget.setup.helper;
    if (helper == null) return;
    try {
      final printers = await helper.helper.usbPrinters();
      if (!mounted) return;
      setState(
        () => _helperPrinters = <UsbPrinterDevice>[
          for (final printer in printers)
            if (_deviceFrom(printer) case final device?) device,
        ],
      );
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'printing.helper_printers',
      );
    }
    _keepWatching();
  }

  void _keepWatching() {
    final waiting =
        widget.setup.helper != null &&
        _helperRunning &&
        _helperPrinters.isEmpty &&
        _current == null;
    if (!waiting) {
      _printerWatch?.cancel();
      _printerWatch = null;
      return;
    }
    if (_printerWatch != null) return;
    final until = DateTime.now().add(_watchFor);
    _printerWatch = Timer.periodic(_watchEvery, (timer) {
      if (!mounted || DateTime.now().isAfter(until)) {
        timer.cancel();
        return;
      }
      unawaited(_readHelperPrinters());
    });
  }

  /// The helper's printer as the device the browser would have reported:
  /// the same key, so it is stored and found the same way.
  static UsbPrinterDevice? _deviceFrom(PrintHelperPrinter printer) {
    final parts = printer.key.split(':');
    if (parts.length < 2) return null;
    final vendor = int.tryParse(parts[0], radix: 16);
    final product = int.tryParse(parts[1], radix: 16);
    if (vendor == null || product == null) return null;
    return UsbPrinterDevice(
      vendorId: vendor,
      productId: product,
      serialNumber: parts.length > 2 ? parts.sublist(2).join(':') : null,
      productName: printer.name,
    );
  }

  /// Opens the browser's picker, then connects what was chosen.
  Future<void> _choose({bool anyDevice = false}) async {
    if (_step != _Step.idle) return;
    setState(() {
      _step = _Step.choosing;
      _answer = null;
    });
    UsbPrinterDevice? device;
    try {
      device = await _chooser.choose(anyDevice: anyDevice);
    } on PrinterTransportException catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'printing.usb_choose',
      );
      if (mounted) {
        setState(() {
          _step = _Step.idle;
          _answer = PrinterFailureNotice.of(error.code);
        });
      }
      return;
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'printing.usb_choose',
      );
      if (mounted) setState(() => _step = _Step.idle);
      return;
    }
    if (!mounted) return;
    setState(() => _step = _Step.idle);
    // Closing the picker without choosing is not a failure: nothing changed.
    if (device == null) return;
    await _connect(device);
  }

  /// Connects [device] and stores it once it has answered.
  Future<void> _connect(UsbPrinterDevice device) async {
    if (_step != _Step.idle) return;
    final printer = DeviceUsbPrinter(
      key: device.key,
      name: device.label,
      paperWidth: _paperWidth,
      hasCutter: _hasCutter,
    );
    final telemetry = AppTelemetry.current;
    final operation = telemetry.start(
      'configuration.usb_printer',
      screen: 'printer_configuration',
      context: {
        'tenant_id': widget.tenantId,
        'paper_width': printer.paperWidth.wireValue,
      },
    );
    setState(() {
      _step = _Step.connecting;
      _answer = null;
    });
    try {
      await telemetry.trace(
        operation,
        'connect_printer',
        () => widget.setup.probe(printer.endpoint),
      );
      await widget.setup.store.save(widget.tenantId, printer);
      await _forgetPrintDialog(widget.setup.onChosen, widget.tenantId);
      telemetry.finishOperation(operation);
      if (!mounted) return;
      setState(() {
        _readCurrent();
        _answer = AppNotice.confirmed(
          'Connected to ${printer.name}. Receipts from this browser now print '
          'on it.',
        );
      });
      _keepWatching();
      widget.onChanged();
      unawaited(_readPermitted());
    } on PrinterTransportException catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        operation: operation,
        boundary: 'printing.usb_connect',
      );
      if (mounted) {
        setState(() => _answer = PrinterFailureNotice.of(error.code));
      }
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        operation: operation,
        boundary: 'printing.usb_connect',
      );
      if (mounted) {
        setState(
          () => _answer = const AppNotice.refused(
            'The printer could not be saved in this browser. Try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _step = _Step.idle);
    }
  }

  /// Stores a new paper width or cutter setting for the printer in use.
  Future<void> _update({PrinterPaperWidth? paperWidth, bool? hasCutter}) async {
    setState(() {
      if (paperWidth != null) _paperWidth = paperWidth;
      if (hasCutter != null) _hasCutter = hasCutter;
    });
    final current = _current;
    if (current == null) return;
    try {
      await widget.setup.store.save(
        widget.tenantId,
        DeviceUsbPrinter(
          key: current.key,
          name: current.name,
          paperWidth: _paperWidth,
          hasCutter: _hasCutter,
        ),
      );
      if (mounted) setState(_readCurrent);
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'printing.usb_update',
      );
      if (mounted) {
        showAppSnackBar(
          context,
          const AppNotice.refused('The setting could not be saved. Try again.'),
        );
      }
    }
  }

  Future<void> _test() async {
    final testPrint = widget.testPrint;
    final current = _current;
    if (testPrint == null || current == null || _step != _Step.idle) return;
    final telemetry = AppTelemetry.current;
    final operation = telemetry.start(
      'printing.test_page',
      screen: 'printer_configuration',
      context: {'transport': PrinterTransportKind.usb.name},
    );
    setState(() {
      _step = _Step.testing;
      _answer = null;
    });
    try {
      await telemetry.trace(
        operation,
        'send_test_page',
        () => testPrint(current.configuration),
      );
      telemetry.finishOperation(operation);
      if (mounted) {
        // The network tab's sentence: sent, never printed.
        setState(
          () => _answer = const AppNotice.confirmed(
            'A test page was sent to the printer. Check that what comes out '
            'fills the width of the roll.',
          ),
        );
      }
    } on PrinterTransportException catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        operation: operation,
        boundary: 'printing.test_send',
      );
      if (mounted) {
        setState(() => _answer = PrinterFailureNotice.of(error.code));
      }
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        operation: operation,
        boundary: 'printing.test_send',
      );
      if (mounted) {
        setState(
          () =>
              _answer = PrinterFailureNotice.of(PrinterTransportCode.usbFailed),
        );
      }
    } finally {
      if (mounted) setState(() => _step = _Step.idle);
    }
  }

  Future<void> _forget() async {
    if (_step != _Step.idle) return;
    final name = _current?.name;
    setState(() => _step = _Step.forgetting);
    try {
      await widget.setup.store.forget(widget.tenantId);
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'printing.usb_forget',
      );
      if (mounted) {
        setState(() {
          _step = _Step.idle;
          _answer = const AppNotice.refused(
            'This browser could not stop using the printer. Try again.',
          );
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _readCurrent();
      _step = _Step.idle;
      _answer = AppNotice.confirmed(
        name == null
            ? 'This browser no longer prints on a USB printer.'
            : 'This browser no longer prints on $name.',
      );
    });
    _keepWatching();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final helper = widget.setup.helper;
    // **A web till on Windows gets the helper and nothing else.** There the
    // browser's own way to a USB printer needs its driver swapped first,
    // which is not a thing to ask of a shop.
    if (helper != null) return _throughHelper(context, helper);
    return _throughBrowser(context);
  }

  /// The USB tab on Windows, one step at a time: install the helper, plug
  /// the printer in, use it.
  Widget _throughHelper(BuildContext context, PrintHelperSetup helper) {
    final tokens = AppTokens.componentOf(context);
    final busy = _step != _Step.idle;
    final current = _current;
    final found = <UsbPrinterDevice>[
      for (final device in _helperPrinters)
        if (device.key.toUpperCase() != current?.key.toUpperCase()) device,
    ];
    final choosing = current == null;
    final answer = _answer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PrintHelperCard(setup: helper, onLooked: _onHelperLooked),
        if (_currentUnreadable) ...<Widget>[
          SizedBox(height: tokens.spacing.s16),
          const Callout(
            key: ValueKey('printer-usb-unreadable'),
            status: AppStatus.problem,
            message:
                'This browser’s USB printer could not be read, so receipts '
                'from it are not sent anywhere. Choose the printer again.',
          ),
        ] else if (current != null) ...<Widget>[
          SizedBox(height: tokens.spacing.s16),
          _ChosenPrinterCard(
            printer: current,
            paperWidth: _paperWidth,
            hasCutter: _hasCutter,
            busy: busy,
            testing: _step == _Step.testing,
            forgetting: _step == _Step.forgetting,
            canTest: widget.testPrint != null,
            onPaperWidth: (value) => _update(paperWidth: value),
            onCutter: (value) => _update(hasCutter: value),
            onTest: _test,
            onForget: _forget,
          ),
        ],
        if (answer != null) ...<Widget>[
          SizedBox(height: tokens.spacing.s12),
          Callout(
            key: const ValueKey('printer-usb-answer'),
            status: answer.status,
            message: answer.message,
          ),
        ],
        if (_helperRunning && choosing && found.isEmpty) ...<Widget>[
          SizedBox(height: tokens.spacing.s16),
          const Callout(
            key: ValueKey('printer-usb-helper-none'),
            status: AppStatus.info,
            icon: Icons.usb,
            message:
                'Plug the printer into this computer and switch it on. It '
                'appears here by itself.',
          ),
        ],
        if (_helperRunning && found.isNotEmpty) ...<Widget>[
          SizedBox(height: tokens.spacing.s24),
          Text(
            choosing ? 'CHOOSE THE PRINTER' : 'OTHER PRINTERS',
            style: tokens.typography.labelEyebrow.copyWith(
              color: tokens.colors.text.tertiary,
            ),
          ),
          SizedBox(height: tokens.spacing.s8),
          for (final device in found) ...<Widget>[
            _PermittedRow(
              device: device,
              keyPrefix: 'printer-usb-helper',
              primary: choosing,
              enabled: !busy,
              onUse: () => _connect(device),
            ),
            SizedBox(height: tokens.spacing.s8),
          ],
        ],
      ],
    );
  }

  /// The USB tab everywhere else: the browser's own picker, which needs
  /// nothing installed on an Android tablet or a Chromebook.
  Widget _throughBrowser(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    if (!_chooser.isSupported) {
      return const Callout(
        key: ValueKey('printer-usb-unsupported'),
        status: AppStatus.attention,
        icon: Icons.usb_off,
        title: 'This browser cannot use USB printers',
        message:
            'Open UzaPay in Google Chrome or Microsoft Edge on the computer '
            'the printer is plugged into, then choose it here.',
      );
    }
    final busy = _step != _Step.idle;
    final current = _current;
    final others = <UsbPrinterDevice>[
      for (final device in _permitted)
        if (device.key.toUpperCase() != current?.key.toUpperCase()) device,
    ];
    final answer = _answer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (_currentUnreadable)
          const Callout(
            key: ValueKey('printer-usb-unreadable'),
            status: AppStatus.problem,
            message:
                'This browser’s USB printer could not be read, so receipts '
                'from it are not sent anywhere. Choose the printer again.',
          )
        else if (current != null)
          _ChosenPrinterCard(
            printer: current,
            paperWidth: _paperWidth,
            hasCutter: _hasCutter,
            busy: busy,
            testing: _step == _Step.testing,
            forgetting: _step == _Step.forgetting,
            canTest: widget.testPrint != null,
            onPaperWidth: (value) => _update(paperWidth: value),
            onCutter: (value) => _update(hasCutter: value),
            onTest: _test,
            onForget: _forget,
          )
        else
          const Callout(
            key: ValueKey('printer-usb-none'),
            status: AppStatus.info,
            icon: Icons.usb,
            message:
                'No USB printer is chosen in this browser, so its receipts '
                'are not printed. Plug the printer into this computer, switch '
                'it on, and choose it below.',
          ),
        if (answer != null) ...<Widget>[
          SizedBox(height: tokens.spacing.s12),
          Callout(
            key: const ValueKey('printer-usb-answer'),
            status: answer.status,
            message: answer.message,
          ),
        ],
        SizedBox(height: tokens.spacing.s24),
        AppButton(
          key: const ValueKey('printer-usb-choose'),
          label: current == null ? 'Choose USB printer' : 'Choose another',
          icon: Icons.usb,
          tier: current == null
              ? AppButtonTier.primary
              : AppButtonTier.secondary,
          loading: _step == _Step.choosing || _step == _Step.connecting,
          expand: true,
          onPressed: busy ? null : () => _choose(),
        ),
        SizedBox(height: tokens.spacing.s4),
        AppButton(
          key: const ValueKey('printer-usb-choose-any'),
          label: 'My printer is not listed',
          tier: AppButtonTier.tertiary,
          expand: true,
          onPressed: busy ? null : () => _choose(anyDevice: true),
        ),
        if (others.isNotEmpty) ...<Widget>[
          SizedBox(height: tokens.spacing.s24),
          Text(
            'ALLOWED IN THIS BROWSER',
            style: tokens.typography.labelEyebrow.copyWith(
              color: tokens.colors.text.tertiary,
            ),
          ),
          SizedBox(height: tokens.spacing.s8),
          for (final device in others) ...<Widget>[
            _PermittedRow(
              device: device,
              keyPrefix: 'printer-usb-permitted',
              enabled: !busy,
              onUse: () => _connect(device),
            ),
            SizedBox(height: tokens.spacing.s8),
          ],
        ],
        SizedBox(height: tokens.spacing.s16),
        const Disclosure(
          key: ValueKey('printer-usb-windows-help'),
          summary: 'The printer is listed but will not print',
          child: _WindowsHelp(),
        ),
      ],
    );
  }
}

/// Forgets the print dialog once a printer is chosen here.
///
/// **A failure does not unsave the printer**: a USB printer chosen here is
/// already what this device prints on, ahead of the print dialog, so the cost
/// is a stale choice on another tab - reported, and nothing more.
Future<void> _forgetPrintDialog(
  Future<void> Function(String tenantId)? onChosen,
  String tenantId,
) async {
  if (onChosen == null) return;
  try {
    await onChosen(tenantId);
  } catch (error, stackTrace) {
    AppTelemetry.captureHandled(
      error,
      stackTrace,
      boundary: 'printing.usb_forget_print_dialog',
    );
  }
}

/// The USB printer in use: its name, its paper and cutter, and the two things
/// a person does with it.
final class _ChosenPrinterCard extends StatelessWidget {
  const _ChosenPrinterCard({
    required this.printer,
    required this.paperWidth,
    required this.hasCutter,
    required this.busy,
    required this.testing,
    required this.forgetting,
    required this.canTest,
    required this.onPaperWidth,
    required this.onCutter,
    required this.onTest,
    required this.onForget,
  });

  final DeviceUsbPrinter printer;
  final PrinterPaperWidth paperWidth;
  final bool hasCutter;
  final bool busy;
  final bool testing;
  final bool forgetting;
  final bool canTest;
  final ValueChanged<PrinterPaperWidth> onPaperWidth;
  final ValueChanged<bool> onCutter;
  final VoidCallback onTest;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return AppCard(
      key: const ValueKey('printer-usb-current'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.usb,
                size: tokens.icons.card,
                color: tokens.colors.status.ok.fg,
              ),
              SizedBox(width: tokens.spacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      printer.name,
                      style: tokens.typography.titleMedium.copyWith(
                        color: tokens.colors.text.primary,
                      ),
                    ),
                    Text(
                      'Receipts from this browser print here · USB '
                      '${printer.key}',
                      style: tokens.typography.bodyMedium.copyWith(
                        color: tokens.colors.text.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.s16),
          AppSelect<PrinterPaperWidth>(
            key: const ValueKey('printer-usb-paper'),
            value: paperWidth,
            enabled: !busy,
            label: 'Paper width',
            items: <AppSelectItem<PrinterPaperWidth>>[
              for (final width in PrinterPaperWidth.values)
                AppSelectItem<PrinterPaperWidth>(
                  value: width,
                  label: width.label,
                ),
            ],
            onChanged: (value) => onPaperWidth(value ?? paperWidth),
          ),
          SizedBox(height: tokens.spacing.s4),
          // **Its own transparent surface**, because the card's fill would
          // otherwise hide the tile's press and hover feedback: a list tile
          // paints them on the nearest `Material`, which is under the card.
          Material(
            type: MaterialType.transparency,
            child: CheckboxListTile(
              key: const ValueKey('printer-usb-cutter'),
              value: hasCutter,
              contentPadding: EdgeInsets.zero,
              title: const Text('This printer cuts the paper'),
              onChanged: busy ? null : (value) => onCutter(value ?? false),
            ),
          ),
          SizedBox(height: tokens.spacing.s12),
          AppActionRow(
            expandActions: true,
            actions: <Widget>[
              if (canTest)
                AppButton(
                  key: const ValueKey('printer-usb-test'),
                  label: 'Test print',
                  icon: Icons.print_outlined,
                  loading: testing,
                  expand: true,
                  onPressed: busy ? null : onTest,
                ),
              AppButton(
                key: const ValueKey('printer-usb-forget'),
                label: 'Stop using',
                tier: AppButtonTier.destructive,
                loading: forgetting,
                expand: true,
                onPressed: busy ? null : onForget,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A printer this site may already use, offered without the picker.
final class _PermittedRow extends StatelessWidget {
  const _PermittedRow({
    required this.device,
    required this.keyPrefix,
    required this.enabled,
    required this.onUse,
    this.primary = false,
  });

  /// The row's action as the page's main one: the printer to choose when
  /// none is chosen yet.
  final bool primary;

  final UsbPrinterDevice device;

  /// Which list the row is in, for its key.
  final String keyPrefix;
  final bool enabled;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return AppCard(
      key: ValueKey('$keyPrefix-${device.key}'),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  device.label,
                  style: tokens.typography.bodyLarge.copyWith(
                    color: tokens.colors.text.primary,
                  ),
                ),
                Text(
                  'USB ${device.key}',
                  style: tokens.typography.caption.copyWith(
                    color: tokens.colors.text.tertiary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: tokens.spacing.s12),
          AppButton(
            label: 'Use this printer',
            tier: primary ? AppButtonTier.primary : AppButtonTier.secondary,
            onPressed: enabled ? onUse : null,
          ),
        ],
      ),
    );
  }
}

/// Why a USB printer the browser lists may still refuse it, and what to do.
///
/// **Windows is the usual reason**: when a printer's own driver is installed,
/// Windows holds the device for its printing and a browser cannot claim it.
final class _WindowsHelp extends StatelessWidget {
  const _WindowsHelp();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final style = tokens.typography.bodyMedium.copyWith(
      color: tokens.colors.text.secondary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'On Windows, a printer whose own driver is installed is held by '
          'Windows, and a browser cannot use it. Either:',
          style: style,
        ),
        SizedBox(height: tokens.spacing.s8),
        Text(
          '• Switch the printer to its USB serial (virtual COM) mode, if its '
          'settings offer one; or',
          style: style,
        ),
        SizedBox(height: tokens.spacing.s4),
        Text(
          '• Replace its driver with WinUSB, using a tool such as Zadig. '
          'Other Windows programs then cannot print to it.',
          style: style,
        ),
        SizedBox(height: tokens.spacing.s8),
        Text(
          'Close other browser tabs that use the printer too: only one can '
          'hold it at a time.',
          style: style,
        ),
      ],
    );
  }
}
