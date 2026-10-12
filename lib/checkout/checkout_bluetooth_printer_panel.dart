/// The printer page's Bluetooth tab: find a printer, pair it, connect to it.
///
/// **It decides where *this device* prints, and nothing else.** The network
/// tab beside it sets the business's printer for every till; this one stores a
/// paired printer on the phone it is opened on - see
/// `checkout_bluetooth_printer.dart` for why. Once a printer is connected here,
/// every receipt rung up on this device is queued for it and printed, retried
/// and reprinted exactly as a network receipt is.
///
/// **Connect is a real connection, not a save.** The printer is paired if it
/// needs to be, then the link is opened and closed through the same transport
/// a receipt uses; only a printer that answered is stored. *Test print* goes a
/// step further and puts the test page on the roll, as the network tab's does.
///
/// **Nothing is asked of the system until a person presses something.** The
/// permission prompt, the switch-Bluetooth-on prompt and the pairing prompt
/// each follow a button, so opening the page never throws a dialog at anyone.
///
/// **Drawn to `docs/design/bluetooth-printer/` since 2026-10-04.** The tab
/// opens on a card saying where this device's receipts go *now* - the Bluetooth
/// printer, the business's network printer, or nowhere - in every state. The
/// devices found are rows in two groups, paired and nearby, with the ones that
/// broadcast no name folded away. A row opens the printer in a sheet holding
/// its paper width, its cutter, *Test print* and *Connect*: nothing is chosen
/// until a printer has answered, so a row opens a printer rather than
/// selecting one, and the controls arrive under the thumb however far down the
/// list it was.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uzapay_pos/observability/app_telemetry.dart';

import '../ui/buttons.dart';
import '../ui/card.dart';
import '../ui/fields.dart';
import '../ui/press.dart';
import '../ui/scaffold.dart';
import '../ui/sheet.dart';
import '../ui/snackbar.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'checkout_bluetooth_printer.dart';
import 'checkout_print_configuration.dart';
import 'checkout_print_failures.dart';
import 'checkout_print_transport_base.dart';

/// Opens and closes a link to a printer without printing - the transport's
/// `probe`. Injected so a test never touches a radio.
typedef PrinterProbe = Future<void> Function(PrinterEndpoint endpoint);

/// Everything the Bluetooth tab needs from the composition root.
final class BluetoothPrinterSetup {
  const BluetoothPrinterSetup({
    required this.discovery,
    required this.store,
    required this.probe,
    this.onChosen,
  });

  final BluetoothPrinterDiscovery discovery;
  final DeviceBluetoothPrinterStore store;
  final PrinterProbe probe;

  /// Called once a printer is chosen here, so the print dialog - the other
  /// way this device can print on its own - is forgotten and one choice
  /// stands. Absent where there is no print dialog to forget.
  final Future<void> Function(String tenantId)? onChosen;
}

/// What the tab is doing, so one control at a time is busy and the rest wait.
enum _Step { idle, preparing, pairing, connecting, testing }

final class BluetoothPrinterTab extends StatefulWidget {
  const BluetoothPrinterTab({
    super.key,
    required this.setup,
    required this.tenantId,
    required this.business,
    required this.onChanged,
    this.testPrint,
  });

  final BluetoothPrinterSetup setup;

  /// The business this device's choice is stored under.
  final String tenantId;

  /// The business's network printer, as the page around this tab already read
  /// it, so the card at the top can say where receipts go before a Bluetooth
  /// printer is connected. Nothing here reads it again.
  final TenantConfiguredPrinter business;

  /// Prints the test page - the network tab's own, so both tabs put the same
  /// page on the roll. Null hides *Test print*.
  final Future<void> Function(TenantPrinterConfiguration configuration)?
  testPrint;

  /// Called after this device's printer is connected or forgotten, so the page
  /// around the tab can restate where receipts go.
  final VoidCallback onChanged;

  @override
  State<BluetoothPrinterTab> createState() => _BluetoothPrinterTabState();
}

class _BluetoothPrinterTabState extends State<BluetoothPrinterTab> {
  DeviceBluetoothPrinter? _current;
  bool _currentUnreadable = false;

  BluetoothReadiness? _readiness;

  /// Every device seen, by address, in the order first seen.
  final Map<String, BluetoothPrinterDevice> _devices =
      <String, BluetoothPrinterDevice>{};
  StreamSubscription<BluetoothPrinterDevice>? _search;
  bool _searching = false;
  bool _searched = false;

  /// The printer whose sheet is open, or null when none is.
  String? _selected;

  /// **58mm by default**, unlike the network form's 80mm: nearly every
  /// Bluetooth receipt printer sold here is the narrow, portable kind.
  static const PrinterPaperWidth _defaultPaperWidth =
      PrinterPaperWidth.columns32;
  static const bool _defaultHasCutter = false;
  PrinterPaperWidth _paperWidth = _defaultPaperWidth;
  bool _hasCutter = _defaultHasCutter;

  _Step _step = _Step.idle;

  /// Which printer a running test is for, so only its own button spins.
  String? _testing;

  /// The last answer to a press in the open sheet - see [_report].
  AppNotice? _answer;

  /// Bumped by every [setState], so the open sheet rebuilds with this state.
  final ValueNotifier<int> _sheetRevision = ValueNotifier<int>(0);

  BluetoothPrinterDiscovery get _discovery => widget.setup.discovery;

  @override
  void initState() {
    super.initState();
    _readCurrent();
  }

  @override
  void dispose() {
    unawaited(_search?.cancel());
    _sheetRevision.dispose();
    super.dispose();
  }

  /// Every change here also rebuilds the open sheet.
  ///
  /// **The sheet is a route of its own**, so it does not rebuild with this
  /// widget - and what it shows is this state: the step, the paper width,
  /// whether the printer has paired yet, and the answer. One override rather
  /// than a second call beside each `setState`, any one of which could be
  /// missed and leave a spinner turning in the sheet after the work was done.
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _sheetRevision.value++;
  }

  void _readCurrent() {
    try {
      _current = widget.setup.store.read(widget.tenantId);
      _currentUnreadable = false;
    } on FormatException {
      _current = null;
      _currentUnreadable = true;
    }
  }

  /// Says what a press came to: inside the sheet while one is open, and in a
  /// snack bar otherwise.
  ///
  /// **Not a snack bar over a sheet**, because it would not be over it. A snack
  /// bar is drawn by the page's scaffold, the sheet is a route above the page,
  /// and the bottom of the screen - where a snack bar floats - is the sheet. So
  /// an answer about the printer in the sheet is shown in the sheet, in the
  /// place the before-pairing note was, as every other sheet in this app shows
  /// a refusal.
  void _report(AppNotice notice) {
    if (_selected != null) {
      setState(() => _answer = notice);
    } else {
      showAppSnackBar(context, notice);
    }
  }

  /// Permission, then the radio, then the paired list and a search.
  Future<void> _find() async {
    if (_step != _Step.idle) return;
    setState(() => _step = _Step.preparing);
    final BluetoothReadiness readiness;
    try {
      readiness = await _discovery.prepare();
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'printing.bluetooth_prepare',
      );
      if (mounted) setState(() => _step = _Step.idle);
      return;
    }
    if (!mounted) return;
    setState(() {
      _readiness = readiness;
      _step = _Step.idle;
    });
    if (readiness != BluetoothReadiness.ready) return;
    try {
      final paired = await _discovery.paired();
      if (!mounted) return;
      setState(() {
        for (final device in paired) {
          _remember(device);
        }
      });
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'printing.bluetooth_paired',
      );
    }
    if (mounted) _startSearch();
  }

  void _startSearch() {
    unawaited(_search?.cancel());
    setState(() {
      _searching = true;
      _searched = true;
    });
    _search = _discovery.search().listen(
      (device) {
        if (mounted) setState(() => _remember(device));
      },
      onError: (Object error, StackTrace stackTrace) {
        AppTelemetry.captureHandled(
          error,
          stackTrace,
          boundary: 'printing.bluetooth_search',
        );
      },
      onDone: () {
        if (mounted) setState(() => _searching = false);
      },
    );
  }

  void _stopSearch() {
    unawaited(_search?.cancel());
    _search = null;
    if (mounted) setState(() => _searching = false);
  }

  /// Adds [device], keeping what is already known: a paired device stays
  /// paired, and a name that arrived once is not lost to a later report
  /// without one.
  void _remember(BluetoothPrinterDevice device) {
    final known = _devices[device.address];
    _devices[device.address] = known == null
        ? device
        : BluetoothPrinterDevice(
            address: device.address,
            paired: known.paired || device.paired,
            name: device.hasName ? device.name : known.name,
          );
  }

  Future<void> _turnOn() async {
    if (_step != _Step.idle) return;
    final on = await _discovery.turnOn();
    if (!mounted) return;
    if (on) {
      await _find();
    } else {
      setState(() => _readiness = BluetoothReadiness.off);
    }
  }

  /// Opens [device] in its sheet. The paper width and the cutter start from
  /// what is stored when it is the printer already in use, and from the
  /// defaults otherwise - never from the last printer's sheet, which would
  /// save a 58mm printer as the 80mm one opened before it.
  Future<void> _open(BluetoothPrinterDevice device) async {
    if (_step != _Step.idle) return;
    final current = _current;
    setState(() {
      _selected = device.address;
      _answer = null;
      final inUse = current != null && current.address == device.address;
      _paperWidth = inUse ? current.paperWidth : _defaultPaperWidth;
      _hasCutter = inUse ? current.hasCutter : _defaultHasCutter;
    });
    await showAppSheet<void>(
      context,
      builder: (sheetContext, controller) => ListenableBuilder(
        listenable: _sheetRevision,
        builder: (context, _) => _PrinterSheet(
          // The live record, so a printer that pairs while its sheet is open
          // stops saying it is not paired yet.
          device: _devices[device.address] ?? device,
          inUse: _current?.address == device.address,
          paperWidth: _paperWidth,
          hasCutter: _hasCutter,
          step: _step,
          testing: _step == _Step.testing && _testing == device.address,
          answer: _answer,
          canTest: widget.testPrint != null,
          scrollController: controller,
          onPaperWidth: (value) => setState(() => _paperWidth = value),
          onCutter: (value) => setState(() => _hasCutter = value),
          onTest: () {
            if (_chosen case final chosen?) _test(chosen);
          },
          // **The sheet closes on an answer, never on a press**: only a
          // printer that answered and was stored takes it away.
          onConnect: () async {
            if (await _connect() && sheetContext.mounted) {
              Navigator.of(sheetContext).pop();
            }
          },
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _selected = null;
      _answer = null;
    });
  }

  DeviceBluetoothPrinter? get _chosen {
    final device = _devices[_selected];
    if (device == null) return null;
    return DeviceBluetoothPrinter(
      address: device.address,
      name: device.label,
      paperWidth: _paperWidth,
      hasCutter: _hasCutter,
    );
  }

  /// Pairs [printer] if it needs it. False, with the reason reported, when it
  /// did not pair.
  Future<bool> _pair(DeviceBluetoothPrinter printer) async {
    setState(() {
      _step = _Step.pairing;
      _answer = null;
    });
    final paired = await _discovery.pair(printer.address);
    if (!mounted) return false;
    if (!paired) {
      _report(
        const AppNotice.refused(
          'The printer did not pair. Check it is switched on and close by, '
          'and accept the pairing request if the phone shows one.',
        ),
      );
      return false;
    }
    setState(() {
      final known = _devices[printer.address];
      if (known != null) {
        _devices[printer.address] = BluetoothPrinterDevice(
          address: known.address,
          name: known.name,
          paired: true,
        );
      }
    });
    return true;
  }

  /// Connects the printer in the open sheet. True once it answered and was
  /// stored.
  Future<bool> _connect() async {
    final printer = _chosen;
    if (printer == null || _step != _Step.idle) return false;
    // Discovery and a connect share one radio; Android connects slowly, or
    // not at all, while a search is still running.
    _stopSearch();
    final telemetry = AppTelemetry.current;
    final operation = telemetry.start(
      'configuration.bluetooth_printer',
      screen: 'printer_configuration',
      context: {
        'tenant_id': widget.tenantId,
        'paper_width': printer.paperWidth.wireValue,
      },
    );
    try {
      if (!await _pair(printer)) return false;
      telemetry.recordStep(operation, 'paired');
      setState(() => _step = _Step.connecting);
      await telemetry.trace(
        operation,
        'connect_printer',
        () => widget.setup.probe(printer.endpoint),
      );
      await widget.setup.store.save(widget.tenantId, printer);
      telemetry.recordStep(operation, 'saved');
      // A failure here does not unsave the printer: it already takes this
      // device's receipts ahead of the print dialog.
      if (widget.setup.onChosen case final onChosen?) {
        try {
          await onChosen(widget.tenantId);
        } catch (error, stackTrace) {
          AppTelemetry.captureHandled(
            error,
            stackTrace,
            operation: operation,
            boundary: 'printing.bluetooth_forget_print_dialog',
          );
        }
      }
      telemetry.finishOperation(operation);
      if (!mounted) return false;
      setState(() {
        _readCurrent();
        _selected = null;
      });
      widget.onChanged();
      _report(
        AppNotice.confirmed(
          'Connected to ${printer.name}. Receipts from this device now print '
          'on it.',
        ),
      );
      return true;
    } on PrinterTransportException catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        operation: operation,
        boundary: 'printing.bluetooth_connect',
      );
      if (mounted) _report(PrinterFailureNotice.of(error.code));
      return false;
    } catch (error, stackTrace) {
      // Pairing or saving, which are the phone's and not the printer's: said
      // rather than lost, so the press always comes to an answer.
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        operation: operation,
        boundary: 'printing.bluetooth_connect',
      );
      if (mounted) _report(_bluetoothFault);
      return false;
    } finally {
      if (mounted) setState(() => _step = _Step.idle);
    }
  }

  /// Prints the test page on [printer], pairing it first if it is not yet.
  ///
  /// Against what is chosen, not what is stored, for the network tab's
  /// reason: the point is to check a printer before relying on it.
  Future<void> _test(DeviceBluetoothPrinter printer) async {
    final testPrint = widget.testPrint;
    if (testPrint == null || _step != _Step.idle) return;
    _stopSearch();
    final telemetry = AppTelemetry.current;
    final operation = telemetry.start(
      'printing.test_page',
      screen: 'printer_configuration',
      context: {'transport': PrinterTransportKind.bluetooth.name},
    );
    try {
      if (!await _pair(printer)) return;
      setState(() {
        _step = _Step.testing;
        _testing = printer.address;
      });
      await telemetry.trace(
        operation,
        'send_test_page',
        () => testPrint(printer.configuration),
      );
      telemetry.finishOperation(operation);
      if (!mounted) return;
      // The network tab's sentence: sent, never printed.
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
      if (mounted) _report(PrinterFailureNotice.of(error.code));
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        operation: operation,
        boundary: 'printing.test_send',
      );
      if (mounted) _report(_bluetoothFault);
    } finally {
      if (mounted) {
        setState(() {
          _step = _Step.idle;
          _testing = null;
        });
      }
    }
  }

  Future<void> _forget() async {
    if (_step != _Step.idle) return;
    final name = _current?.name;
    try {
      await widget.setup.store.forget(widget.tenantId);
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'printing.bluetooth_forget',
      );
      if (mounted) {
        _report(
          const AppNotice.refused(
            'This device could not stop using the printer. Try again.',
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(_readCurrent);
    widget.onChanged();
    _report(
      AppNotice.confirmed(
        '${name ?? 'The Bluetooth printer'} is no longer used, so receipts '
        'from this device are not printed until another printer is chosen.',
      ),
    );
  }

  /// What a press says when the phone, not the printer, fails it: pairing
  /// that throws, or a choice that cannot be saved.
  static const AppNotice _bluetoothFault = AppNotice.refused(
    'Bluetooth on this device did not finish that. Try again; if it keeps '
    'happening, turn Bluetooth off and on.',
  );

  /// The devices found, in the three places the list puts them - each in the
  /// order found. A paired device is paired whatever it is called; of the
  /// rest, the ones with no name fold away, because a receipt printer always
  /// broadcasts one.
  ({
    List<BluetoothPrinterDevice> paired,
    List<BluetoothPrinterDevice> nearby,
    List<BluetoothPrinterDevice> nameless,
  })
  get _grouped {
    final paired = <BluetoothPrinterDevice>[];
    final nearby = <BluetoothPrinterDevice>[];
    final nameless = <BluetoothPrinterDevice>[];
    for (final device in _devices.values) {
      (device.paired
              ? paired
              : device.hasName
              ? nearby
              : nameless)
          .add(device);
    }
    return (paired: paired, nearby: nearby, nameless: nameless);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    if (!_discovery.isSupported) {
      return const Callout(
        key: ValueKey('printer-bluetooth-unsupported'),
        status: AppStatus.info,
        message:
            'Bluetooth printers are set up in the Android app. This device '
            'prints to the network printer.',
      );
    }
    final current = _current;
    final busy = _step != _Step.idle;
    final groups = _grouped;

    Widget list(List<BluetoothPrinterDevice> devices) => _DeviceList(
      devices: devices,
      inUse: current?.address,
      onOpen: busy ? null : _open,
    );

    return Column(
      key: const ValueKey('printer-bluetooth'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Disclosure(
          key: ValueKey('printer-bluetooth-scope'),
          summary: 'How Bluetooth printing works',
          child: Text(
            'A Bluetooth printer is paired with this device only. Receipts '
            'rung up here print on it, and the business’s other devices keep '
            'using the network printer. Each receipt connects, prints and lets '
            'go, so the printer is free for the next one.',
          ),
        ),
        // `s8` plus the disclosure's focus-ring gutter is the boards' `s12`.
        SizedBox(height: tokens.spacing.s8),
        // **Where this device prints, in every state**, so the tab opens on
        // the question it is opened with. A saved printer this device cannot
        // read is the one answer that is a fault rather than a place, and it
        // keeps the callout it has always had.
        if (_currentUnreadable)
          Callout(
            key: const ValueKey('printer-bluetooth-unreadable'),
            status: AppStatus.problem,
            message:
                'The Bluetooth printer saved on this device cannot be read, so '
                'receipts from this device are not sent anywhere. Connect a '
                'printer below, or stop using Bluetooth.',
            action: AppButton(
              label: 'Stop using Bluetooth',
              tier: AppButtonTier.secondary,
              onPressed: busy ? null : _forget,
            ),
          )
        else if (current != null)
          _CurrentPrinterCard(
            printer: current,
            canTest: widget.testPrint != null,
            testing:
                _step == _Step.testing &&
                _testing == current.address &&
                _selected != current.address,
            onTest: busy ? null : () => _test(current),
            onForget: busy ? null : _forget,
          )
        else
          _BusinessPrinterCard(business: widget.business),
        SizedBox(height: tokens.spacing.s24),
        SectionHeading(
          current == null ? 'Find a printer' : 'Use a different printer',
        ),
        SizedBox(height: tokens.spacing.s8),
        Text(
          'Switch the printer on and keep it close. Printers usually show '
          'their model name, such as MPT-II or XP-P300.',
          style: tokens.typography.bodyMedium.copyWith(
            color: tokens.colors.text.secondary,
          ),
        ),
        if (_readiness == BluetoothReadiness.off) ...<Widget>[
          SizedBox(height: tokens.spacing.s12),
          Callout(
            key: const ValueKey('printer-bluetooth-off'),
            status: AppStatus.attention,
            // Nothing is waiting, a switch is off: the radio's own glyph
            // rather than `attention`'s clock.
            icon: Icons.bluetooth_disabled,
            message: 'Bluetooth is off on this device.',
            action: AppButton(
              key: const ValueKey('printer-bluetooth-turn-on'),
              label: 'Turn on Bluetooth',
              onPressed: busy ? null : _turnOn,
            ),
          ),
        ],
        if (_readiness == BluetoothReadiness.permissionDenied) ...<Widget>[
          SizedBox(height: tokens.spacing.s12),
          Callout(
            key: const ValueKey('printer-bluetooth-denied'),
            status: AppStatus.problem,
            message:
                'UzaPay is not allowed to use Bluetooth, so it cannot find '
                'printers. Allow Nearby devices in the phone settings, then '
                'search again.',
            action: AppButton(
              key: const ValueKey('printer-bluetooth-settings'),
              label: 'Open settings',
              onPressed: _discovery.openPermissionSettings,
            ),
          ),
        ],
        if (_readiness == BluetoothReadiness.unsupported) ...<Widget>[
          SizedBox(height: tokens.spacing.s12),
          const Callout(
            key: ValueKey('printer-bluetooth-no-radio'),
            status: AppStatus.info,
            message: 'This device has no Bluetooth.',
          ),
        ],
        SizedBox(height: tokens.spacing.s12),
        AppActionRow(
          alignment: MainAxisAlignment.start,
          actions: <Widget>[
            if (_searching)
              AppButton(
                key: const ValueKey('printer-bluetooth-stop'),
                label: 'Stop searching',
                icon: Icons.stop_circle_outlined,
                onPressed: _stopSearch,
              )
            else
              AppButton(
                key: const ValueKey('printer-bluetooth-search'),
                label: _searched ? 'Search again' : 'Search for printers',
                icon: Icons.bluetooth_searching,
                // Primary only while it is the one thing to do: with a printer
                // in use, or one open in its sheet, it is not.
                tier: current == null && _selected == null
                    ? AppButtonTier.primary
                    : AppButtonTier.secondary,
                loading: _step == _Step.preparing,
                onPressed: busy ? null : _find,
              ),
            if (_searching)
              const StatusBadge(
                key: ValueKey('printer-bluetooth-searching'),
                status: AppStatus.info,
                label: 'Searching',
                icon: Icons.bluetooth_searching,
              ),
          ],
        ),
        if (_devices.isNotEmpty) ...<Widget>[
          if (groups.paired.isNotEmpty) ...<Widget>[
            SizedBox(height: tokens.spacing.s16),
            _DeviceGroup(
              key: const ValueKey('printer-bluetooth-paired'),
              label: 'Paired with this device',
              count: groups.paired.length,
              list: list(groups.paired),
            ),
          ],
          if (groups.nearby.isNotEmpty) ...<Widget>[
            SizedBox(height: tokens.spacing.s16),
            _DeviceGroup(
              key: const ValueKey('printer-bluetooth-nearby'),
              label: 'Nearby',
              count: groups.nearby.length,
              list: list(groups.nearby),
            ),
          ],
          if (groups.nameless.isNotEmpty) ...<Widget>[
            // The disclosure's line sits in its focus-ring gutter, so the
            // smaller step lands it a gap of `s8` under the list above.
            SizedBox(
              height: groups.paired.isEmpty && groups.nearby.isEmpty
                  ? tokens.spacing.s16
                  : tokens.spacing.s4,
            ),
            Disclosure(
              key: const ValueKey('printer-bluetooth-nameless'),
              summary:
                  '${groups.nameless.length} '
                  '${groups.nameless.length == 1 ? 'device' : 'devices'} '
                  'with no name',
              indentChild: false,
              child: list(groups.nameless),
            ),
          ],
        ] else if (_searched && !_searching) ...<Widget>[
          SizedBox(height: tokens.spacing.s12),
          const Callout(
            key: ValueKey('printer-bluetooth-none-found'),
            status: AppStatus.info,
            message:
                'No Bluetooth devices were found. Check the printer is '
                'switched on and close by, then search again.',
          ),
        ],
      ],
    );
  }
}

/// The card at the top of the tab: where this device's receipts go now.
///
/// **One shape for every answer**, so the place a person looks never moves: a
/// name, what it is, a status, and one sentence. Only the printer in use here
/// carries controls.
final class _DestinationCard extends StatelessWidget {
  const _DestinationCard({
    super.key,
    required this.name,
    required this.detail,
    required this.badge,
    required this.sentence,
    this.nameKey,
    this.actions,
  });

  final String name;
  final Key? nameKey;
  final String detail;
  final StatusBadge badge;
  final String sentence;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final quiet = tokens.typography.bodyMedium.copyWith(
      color: tokens.colors.text.secondary,
    );
    // `radius.lg`, with the device list under it: the two read as one set,
    // and the staff directory's surfaces took the same corner for the same
    // reason.
    return AppCard(
      radius: tokens.radius.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      name,
                      key: nameKey,
                      style: tokens.typography.titleMedium.copyWith(
                        color: tokens.colors.text.primary,
                      ),
                    ),
                    SizedBox(height: tokens.spacing.s4),
                    Text(detail, style: quiet),
                  ],
                ),
              ),
              SizedBox(width: tokens.spacing.s8),
              // Container, glyph and word - never the colour alone.
              badge,
            ],
          ),
          SizedBox(height: tokens.spacing.s8),
          Text(sentence, style: quiet),
          if (actions case final controls?) ...<Widget>[
            SizedBox(height: tokens.spacing.s8),
            controls,
          ],
        ],
      ),
    );
  }
}

/// The printer this device is using now.
final class _CurrentPrinterCard extends StatelessWidget {
  const _CurrentPrinterCard({
    required this.printer,
    required this.canTest,
    required this.testing,
    required this.onTest,
    required this.onForget,
  });

  final DeviceBluetoothPrinter printer;

  /// Whether this build can print a test page at all. Separate from [onTest],
  /// which is null only while something else is busy - so the button waits
  /// disabled rather than vanishing and moving the card under a thumb.
  final bool canTest;
  final bool testing;
  final VoidCallback? onTest;
  final VoidCallback? onForget;

  @override
  Widget build(BuildContext context) => _DestinationCard(
    key: const ValueKey('printer-bluetooth-current'),
    name: printer.name,
    nameKey: const ValueKey('printer-bluetooth-current-name'),
    detail: _rollDetail(printer.address, printer.configuration),
    badge: const StatusBadge(
      status: AppStatus.ok,
      label: 'In use',
      icon: Icons.check_circle_outline,
    ),
    sentence: 'Receipts from this device print here.',
    actions: AppActionRow(
      actions: <Widget>[
        AppButton(
          key: const ValueKey('printer-bluetooth-forget'),
          label: 'Stop using',
          tier: AppButtonTier.destructive,
          onPressed: onForget,
        ),
        if (canTest)
          AppButton(
            key: const ValueKey('printer-bluetooth-current-test'),
            // Shorter than *Test this printer*: inside the card's padding,
            // beside *Stop using*, the long label is cut off on a phone.
            label: 'Test print',
            icon: Icons.print_outlined,
            loading: testing,
            onPressed: onTest,
          ),
      ],
    ),
  );
}

/// Where this device prints with no Bluetooth printer chosen: the business's
/// network printer, exactly as every other till does.
final class _BusinessPrinterCard extends StatelessWidget {
  const _BusinessPrinterCard({required this.business});

  final TenantConfiguredPrinter business;

  @override
  Widget build(BuildContext context) => switch (business.state) {
    TenantPrinterConfigurationState.configured => _DestinationCard(
      key: const ValueKey('printer-bluetooth-network'),
      name: 'Network printer',
      detail: _rollDetail(
        business.configuration!.endpoint.toString(),
        business.configuration!,
      ),
      badge: const StatusBadge(
        status: AppStatus.neutral,
        label: 'Network',
        icon: Icons.lan,
      ),
      sentence:
          'Receipts from this device go to the business’s network printer. '
          'Connect one below to print here instead.',
    ),
    // `attention`, the network tab's own reading of a printer nobody has set
    // up: a step not taken yet, not a fault.
    TenantPrinterConfigurationState.absent => const _DestinationCard(
      key: ValueKey('printer-bluetooth-no-printer'),
      name: 'No printer',
      detail: 'Sales are recorded as normal',
      badge: StatusBadge(status: AppStatus.attention, label: 'Not set up'),
      sentence:
          'Receipts from this device are not sent anywhere. Connect a '
          'Bluetooth printer below, or switch on the network printer.',
    ),
    // Not *Not set up*: a business that has a printer must not be invited to
    // set one up again. The network tab's own word for settings it cannot
    // trust, which is the route guard's too.
    TenantPrinterConfigurationState.malformed => const _DestinationCard(
      key: ValueKey('printer-bluetooth-network-unreadable'),
      name: 'Network printer',
      detail: 'Sales are recorded as normal',
      badge: StatusBadge(status: AppStatus.problem, label: 'Not read'),
      sentence:
          'Its settings cannot be read, so receipts from this device are not '
          'sent anywhere. Connect a Bluetooth printer below, or switch on the '
          'network printer and save it again.',
    ),
  };
}

/// `DC:0D:30:9A:4E:21 · 58mm roll`, and whether it cuts.
String _rollDetail(String where, TenantPrinterConfiguration configuration) =>
    '$where · ${configuration.paperWidth.roll} roll'
    '${configuration.hasCutter ? ' · cuts the paper' : ''}';

/// What a device's row and its sheet say it is.
String _standing(BluetoothPrinterDevice device, {required bool inUse}) => inUse
    ? 'In use on this device'
    : device.paired
    ? 'Paired'
    : 'Not paired yet';

/// One group of the list: its name and count, over its card of rows.
final class _DeviceGroup extends StatelessWidget {
  const _DeviceGroup({
    super.key,
    required this.label,
    required this.count,
    required this.list,
  });

  final String label;
  final int count;
  final Widget list;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final style = tokens.typography.labelMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          header: true,
          label: '$label, $count',
          excludeSemantics: true,
          child: Padding(
            // In the focus-ring gutter, so the words line up with the rows'
            // and the fields' rather than with the card's edge.
            padding: EdgeInsets.symmetric(horizontal: tokens.spacing.s4),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    label,
                    style: style.copyWith(color: tokens.colors.text.secondary),
                  ),
                ),
                Text(
                  '$count',
                  style: style.copyWith(
                    color: tokens.colors.text.tertiary,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: tokens.spacing.s8),
        list,
      ],
    );
  }
}

/// A card of device rows, a hairline between each.
final class _DeviceList extends StatelessWidget {
  const _DeviceList({
    required this.devices,
    required this.inUse,
    required this.onOpen,
  });

  final List<BluetoothPrinterDevice> devices;

  /// The address of the printer this device uses, if any.
  final String? inUse;

  /// Null while something else is busy, which draws every row disabled.
  final ValueChanged<BluetoothPrinterDevice>? onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final open = onOpen;
    final edge = BorderSide(color: colors.surface.cardEdge);
    final hairline = BorderSide(color: colors.surface.borderSubtle);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.raised,
        borderRadius: BorderRadius.circular(tokens.radius.lg),
        border: Border.fromBorderSide(edge),
      ),
      // **The edge and the hairlines are laid out, not only painted**, so a
      // row's wash and its focus ring sit inside the card's edge rather than
      // over it, and a long list does not drift a pixel a row from the boards.
      child: Padding(
        padding: EdgeInsets.all(edge.width),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final (index, device) in devices.indexed) ...<Widget>[
              if (index > 0)
                SizedBox(
                  height: hairline.width,
                  child: ColoredBox(color: hairline.color),
                ),
              _DeviceRow(
                key: ValueKey('printer-bluetooth-device-${device.address}'),
                device: device,
                inUse: device.address == inUse,
                // Inside the edge, so the card's corner less its width.
                outerRadius: tokens.radius.lg - edge.width,
                first: index == 0,
                last: index == devices.length - 1,
                onPressed: open == null ? null : () => open(device),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One device: its glyph, its name, what it is, and a chevron to its sheet.
///
/// **States:** enabled; hover and pressed as the action green's wash and
/// [PressSurface]'s spring; focus-visible as the ring, inside the card; in use
/// as the print glyph in `action.primary` *and* the words - never the colour
/// alone; disabled in the disabled ink while another printer connects.
final class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    super.key,
    required this.device,
    required this.inUse,
    required this.outerRadius,
    required this.first,
    required this.last,
    required this.onPressed,
  });

  final BluetoothPrinterDevice device;
  final bool inUse;

  /// The corner the row takes where it meets the card's edge.
  final double outerRadius;
  final bool first;
  final bool last;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final actions = colors.action;
    final enabled = onPressed != null;
    final ink = enabled ? colors.text.tertiary : actions.disabledLabel;
    final standing = _standing(device, inUse: inUse);

    // The card's corners on the card's own edge, and the smallest corner
    // between rows, so the wash and the ring follow the card where they meet
    // it and stay square-cut against a hairline.
    final outer = Radius.circular(outerRadius);
    final inner = Radius.circular(tokens.radius.sm);
    final radius = BorderRadius.vertical(
      top: first ? outer : inner,
      bottom: last ? outer : inner,
    );

    // The row is transparent: the card behind it is the surface, and
    // [_DeviceList] lays the hairline between rows.
    final row = Padding(
      padding: EdgeInsets.fromLTRB(
        tokens.spacing.s16,
        tokens.spacing.s12,
        tokens.spacing.s8,
        tokens.spacing.s12,
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: tokens.spacing.s40,
            height: tokens.spacing.s40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.surface.base,
              borderRadius: BorderRadius.circular(tokens.radius.md),
            ),
            child: Icon(
              inUse ? Icons.print_outlined : Icons.bluetooth,
              size: tokens.spacing.s20,
              color: !enabled
                  ? actions.disabledLabel
                  : inUse
                  ? actions.primary.container
                  : colors.text.tertiary,
            ),
          ),
          SizedBox(width: tokens.spacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  device.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.typography.bodyLarge.copyWith(
                    color: enabled
                        ? colors.text.primary
                        : actions.disabledLabel,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text.rich(
                  TextSpan(
                    style: tokens.typography.caption.copyWith(color: ink),
                    children: <InlineSpan>[
                      TextSpan(
                        text: standing,
                        style: inUse && enabled
                            ? TextStyle(color: actions.primary.container)
                            : null,
                      ),
                      // A device with no name shows its address as its
                      // name, so it is not said twice.
                      if (device.hasName)
                        TextSpan(text: ' · ${device.address}'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: tokens.spacing.s12),
          SizedBox.square(
            dimension: tokens.spacing.s48,
            child: Icon(
              Icons.chevron_right,
              size: tokens.spacing.s24,
              color: ink,
            ),
          ),
        ],
      ),
    );

    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: device.label,
      value: device.hasName ? '$standing, ${device.address}' : standing,
      onTap: onPressed,
      excludeSemantics: true,
      child: PressSurface(
        borderRadius: radius,
        onPressed: onPressed,
        fillWidth: true,
        excludeSemantics: true,
        ringInside: true,
        hoverOverlay: actions.tertiary.hoverWash(),
        pressedOverlay: actions.tertiary.pressedWash(),
        child: row,
      ),
    );
  }
}

/// One printer, opened from its row: its paper width, its cutter, *Test print*
/// and *Connect*.
///
/// **It holds nothing of its own.** Every value is the tab's, handed in again
/// whenever the tab changes, so the sheet and the page can never disagree
/// about which step is running.
///
/// **It cannot be closed while it is working**, by the scrim or by the back
/// key: a pairing prompt is up, or a link is open, and closing the sheet would
/// leave the answer nowhere to go. It goes quiet instead and says what is
/// happening.
final class _PrinterSheet extends StatelessWidget {
  const _PrinterSheet({
    required this.device,
    required this.inUse,
    required this.paperWidth,
    required this.hasCutter,
    required this.step,
    required this.testing,
    required this.answer,
    required this.canTest,
    required this.scrollController,
    required this.onPaperWidth,
    required this.onCutter,
    required this.onTest,
    required this.onConnect,
  });

  final BluetoothPrinterDevice device;
  final bool inUse;
  final PrinterPaperWidth paperWidth;
  final bool hasCutter;
  final _Step step;
  final bool testing;
  final AppNotice? answer;
  final bool canTest;
  final ScrollController scrollController;
  final ValueChanged<PrinterPaperWidth> onPaperWidth;
  final ValueChanged<bool> onCutter;
  final VoidCallback onTest;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final busy = step != _Step.idle;
    final standing = _standing(device, inUse: inUse);
    final inset = tokens.spacing.s20;

    // One slot under the title for what the sheet has to say: what is
    // happening, then how the last press came out, then - for a printer that
    // has never paired - what *Connect* is about to do.
    final Widget? notice = step == _Step.pairing
        ? const Callout(
            key: ValueKey('printer-bluetooth-pairing'),
            status: AppStatus.attention,
            message:
                'Pairing. If the phone asks, accept the request - a printer '
                'that asks for a PIN usually uses 0000 or 1234.',
          )
        : answer != null
        ? Callout(
            key: const ValueKey('printer-bluetooth-answer'),
            status: answer!.status,
            message: answer!.message,
          )
        : !device.paired
        ? const Callout(
            key: ValueKey('printer-bluetooth-before-pairing'),
            status: AppStatus.info,
            message:
                'Connecting pairs it first. If the phone asks, accept — a '
                'printer that asks for a PIN usually uses 0000 or 1234.',
          )
        : null;

    return PopScope(
      canPop: !busy,
      child: Column(
        key: const ValueKey('printer-bluetooth-sheet'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: ListView(
              controller: scrollController,
              // The handle's strip above is `s12` deep; `s4` more puts the
              // title `s16` under the handle.
              padding: EdgeInsets.fromLTRB(inset, tokens.spacing.s4, inset, 0),
              children: <Widget>[
                Text(
                  device.label,
                  style: tokens.typography.titleLarge.copyWith(
                    color: tokens.colors.text.primary,
                  ),
                ),
                SizedBox(height: tokens.spacing.s4),
                Text(
                  device.hasName ? '$standing · ${device.address}' : standing,
                  style: tokens.typography.bodyMedium.copyWith(
                    color: tokens.colors.text.secondary,
                  ),
                ),
                if (notice != null) ...<Widget>[
                  SizedBox(height: tokens.spacing.s16),
                  notice,
                ],
                SizedBox(height: tokens.spacing.s16),
                AppSelect<PrinterPaperWidth>(
                  key: const ValueKey('printer-bluetooth-paper'),
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
                // The field stands in its focus-ring gutter, so `s4` more is
                // the boards' `s8` to the cutter row.
                SizedBox(height: tokens.spacing.s4),
                CheckboxListTile(
                  key: const ValueKey('printer-bluetooth-cutter'),
                  value: hasCutter,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('This printer cuts the paper'),
                  onChanged: busy ? null : (value) => onCutter(value ?? false),
                ),
              ],
            ),
          ),
          // **Anchored to the bottom of the sheet**, outside the scroll, so
          // they land under the thumb at the half detent and stay there.
          Padding(
            padding: EdgeInsets.fromLTRB(
              inset,
              tokens.spacing.s16,
              inset,
              inset,
            ),
            child: AppActionRow(
              expandActions: true,
              actions: <Widget>[
                if (canTest)
                  AppButton(
                    key: const ValueKey('printer-bluetooth-test'),
                    label: 'Test print',
                    icon: Icons.print_outlined,
                    loading: testing,
                    expand: true,
                    onPressed: busy ? null : onTest,
                  ),
                AppButton(
                  key: const ValueKey('printer-bluetooth-connect'),
                  label: 'Connect',
                  icon: Icons.bluetooth_connected,
                  tier: AppButtonTier.primary,
                  loading: step == _Step.pairing || step == _Step.connecting,
                  expand: true,
                  onPressed: busy ? null : onConnect,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
