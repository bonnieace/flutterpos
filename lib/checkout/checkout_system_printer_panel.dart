/// The printer page's *Print dialog* section: print this device's receipts
/// through its own print window.
///
/// **Its switch on the Printer page turns it on and off**, one kind of
/// printer at a time - see `checkout_print_mode.dart`. What is left here is
/// what the window cannot decide for itself: the width of the roll the page
/// is laid out for, and a test page. See `checkout_system_printer.dart` for
/// what the route costs.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../observability/app_telemetry.dart';
import '../ui/buttons.dart';
import '../ui/fields.dart';
import '../ui/snackbar.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import '../ui/workspace.dart';
import 'checkout_print_configuration.dart';
import 'checkout_print_failures.dart';
import 'checkout_print_transport_base.dart';
import 'checkout_system_printer.dart';

/// Everything the print-dialog section needs from the composition root.
final class SystemPrinterSetup {
  const SystemPrinterSetup({required this.store, required this.probe});

  final DeviceSystemPrinterStore store;

  /// The transport's `probe`: whether this device has a print window to
  /// open. Injected so a test never opens one.
  final Future<void> Function(PrinterEndpoint endpoint) probe;
}

final class SystemPrinterTab extends StatefulWidget {
  const SystemPrinterTab({
    super.key,
    required this.setup,
    required this.tenantId,
    required this.onChanged,
    this.testPrint,
  });

  final SystemPrinterSetup setup;

  /// The business this device's choice is stored under.
  final String tenantId;

  /// Prints the test page through the window. Null hides *Test print*.
  final Future<void> Function(TenantPrinterConfiguration configuration)?
  testPrint;

  /// Called after the paper width is saved.
  final VoidCallback onChanged;

  @override
  State<SystemPrinterTab> createState() => _SystemPrinterTabState();
}

class _SystemPrinterTabState extends State<SystemPrinterTab> {
  bool _unreadable = false;

  /// **80mm by default**, the network form's own default roll.
  PrinterPaperWidth _paperWidth = PrinterPaperWidth.columns48;

  bool _testing = false;

  /// The last answer to a press, shown in the section.
  AppNotice? _answer;

  @override
  void initState() {
    super.initState();
    try {
      final current = widget.setup.store.read(widget.tenantId);
      if (current != null) _paperWidth = current.paperWidth;
    } on FormatException {
      _unreadable = true;
    }
  }

  /// Saves [paperWidth] - which also puts right a record that could not be
  /// read.
  Future<void> _update(PrinterPaperWidth paperWidth) async {
    setState(() => _paperWidth = paperWidth);
    try {
      await widget.setup.store.save(
        widget.tenantId,
        DeviceSystemPrinter(paperWidth: paperWidth),
      );
      if (!mounted) return;
      setState(() => _unreadable = false);
      widget.onChanged();
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'printing.system_update',
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
    if (testPrint == null || _testing) return;
    final telemetry = AppTelemetry.current;
    final operation = telemetry.start(
      'printing.test_page',
      screen: 'printer_configuration',
      context: {'transport': PrinterTransportKind.system.name},
    );
    setState(() {
      _testing = true;
      _answer = null;
    });
    try {
      await telemetry.trace(
        operation,
        'send_test_page',
        () => testPrint(
          DeviceSystemPrinter(paperWidth: _paperWidth).configuration,
        ),
      );
      telemetry.finishOperation(operation);
      if (mounted) {
        // The other sections' sentence: sent, never printed - and here the
        // device's window has the last word on whether it was.
        setState(
          () => _answer = const AppNotice.confirmed(
            'The test page went to the print window. Check that what comes '
            'out fills the width of the roll.',
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
          () => _answer = PrinterFailureNotice.of(
            PrinterTransportCode.printDialogFailed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final answer = _answer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppWorkspace(
          leading: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (_unreadable)
                const Callout(
                  key: ValueKey('printer-system-unreadable'),
                  status: AppStatus.problem,
                  message:
                      'This device’s print dialog setting could not be read. Choose '
                      'the paper width again.',
                )
              else
                const Callout(
                  key: ValueKey('printer-system-in-use'),
                  status: AppStatus.info,
                  icon: Icons.print_outlined,
                  message:
                      'Each receipt opens this device’s print window, and the '
                      'printer is chosen there.',
                ),
              SizedBox(height: tokens.spacing.s16),
            ],
          ),
          trailing: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AppSelect<PrinterPaperWidth>(
                key: const ValueKey('printer-system-paper'),
                value: _paperWidth,
                enabled: !_testing,
                label: 'Paper width',
                items: _paperItems,
                onChanged: (value) => _update(value ?? _paperWidth),
              ),
              if (widget.testPrint != null) ...<Widget>[
                SizedBox(height: tokens.spacing.s16),
                AppButton(
                  key: const ValueKey('printer-system-test'),
                  label: 'Test print',
                  icon: Icons.print_outlined,
                  loading: _testing,
                  expand: true,
                  onPressed: _testing ? null : _test,
                ),
              ],
              if (answer != null) ...<Widget>[
                SizedBox(height: tokens.spacing.s12),
                Callout(
                  key: const ValueKey('printer-system-answer'),
                  status: answer.status,
                  message: answer.message,
                ),
              ],
              SizedBox(height: tokens.spacing.s16),
              const Disclosure(
                key: ValueKey('printer-system-help'),
                summary: 'Which printers work this way',
                child: _Help(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The rolls, named by width alone: a page laid out by the device has no
/// column count for the person to check.
final List<AppSelectItem<PrinterPaperWidth>> _paperItems =
    <AppSelectItem<PrinterPaperWidth>>[
      for (final width in PrinterPaperWidth.values)
        AppSelectItem<PrinterPaperWidth>(
          value: width,
          label: '${width.roll} roll',
        ),
    ];

/// What it takes for a printer to appear in the print window, per device.
final class _Help extends StatelessWidget {
  const _Help();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final style = tokens.typography.bodyMedium.copyWith(
      color: tokens.colors.text.secondary,
    );
    Widget point(String text) => Padding(
      padding: EdgeInsets.only(top: tokens.spacing.s4),
      child: Text(text, style: style),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Any printer the device can already print to appears in its print '
          'window:',
          style: style,
        ),
        SizedBox(height: tokens.spacing.s4),
        point(
          '• On a computer, install the printer’s own driver from its maker, '
          'then pick it in the window.',
        ),
        point(
          '• On an Android phone or tablet, a receipt printer needs a printing '
          'app, such as RawBT, to appear in the window.',
        ),
        point('• On an iPhone, only printers with AirPrint appear.'),
        SizedBox(height: tokens.spacing.s8),
        Text(
          'Cutting and opening the cash drawer happen only if the printer’s '
          'own settings do them.',
          style: style,
        ),
      ],
    );
  }
}
