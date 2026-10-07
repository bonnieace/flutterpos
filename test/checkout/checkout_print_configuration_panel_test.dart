import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:uzapay_pos/checkout/checkout_print_configuration_panel.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:uzapay_pos/ui/buttons.dart';
import 'package:uzapay_pos/ui/snackbar.dart';
import 'package:uzapay_pos/ui/states.dart';
import 'package:uzapay_pos/ui/tabs.dart';
import 'package:uzapay_pos/ui/status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/notices.dart';

const String _printerPath = 'tenants/tenant-a/configuration/printer';

Map<String, Object?> _stored({
  String host = '192.168.1.50',
  int port = 9100,
  String paperWidth = 'columns_32',
  bool hasCutter = true,
}) => <String, Object?>{
  'transport': 'direct_tcp',
  'host': host,
  'port': port,
  'paperWidth': paperWidth,
  'hasCutter': hasCutter,
};

void main() {
  testWidgets('a business with no printer is told receipts go nowhere', (
    tester,
  ) async {
    // **And that sales are unaffected**, which is §8 rule 6 and the whole
    // reason printing is allowed to fail: a printer that is not set up must
    // never read as a till that is broken.
    final reader = _Reader();

    await _pump(tester, _controller(), reader, writer: _Writer());

    // **A `Callout` since 2026-08-26, where this was a loose grey paragraph.**
    // Whether receipts are going anywhere is the screen's standing rather than
    // prose about it, and §2.1 wants a container, a glyph and a word for that.
    // `attention` is its "awaiting": a setup step nobody has taken.
    expect(
      noticeMessage(tester, 'printer-configuration-current'),
      'No printer is set up, so receipts are not sent anywhere. Sales are '
      'recorded as normal.',
    );
    expect(
      noticeStatus(tester, 'printer-configuration-current'),
      AppStatus.attention,
    );
    expect(reader.requested.single, _printerPath);
    // Nothing to replace, so the button says what it does rather than what it
    // changes.
    expect(
      _buttonLabel(tester, 'printer-configuration-submit'),
      'Save printer',
    );
  });

  testWidgets('a configured printer draws no status card, only its fields', (
    tester,
  ) async {
    final reader = _Reader(stored: _stored(paperWidth: 'columns_48'));

    await _pump(tester, _controller(), reader, writer: _Writer());

    // The filled fields already say where receipts go.
    expect(
      find.byKey(const ValueKey('printer-configuration-current')),
      findsNothing,
    );
    expect(
      _buttonLabel(tester, 'printer-configuration-submit'),
      'Change printer',
    );
  });

  testWidgets('a malformed document says so and offers to replace it', (
    tester,
  ) async {
    // The strict read model refuses it and printing stops, so the one person
    // who can correct it must see it rather than be shown the cashier's
    // refusal.
    final reader = _Reader(stored: _stored(host: 'http://printer'));

    await _pump(tester, _controller(), reader);

    expect(
      noticeMessage(tester, 'printer-configuration-current'),
      'The saved printer settings cannot be read, so receipts are not sent '
      'anywhere. Saving a printer here replaces them.',
    );
    // §2.1 gives `problem` the meaning "difference found, **unreadable**, out
    // of stock", and settings that cannot be read is exactly that.
    expect(
      noticeStatus(tester, 'printer-configuration-current'),
      AppStatus.problem,
    );
  });

  testWidgets('the form is prefilled from what is stored', (tester) async {
    await _pump(
      tester,
      _controller(),
      _Reader(stored: _stored(host: 'till.shop.local', port: 515)),
      writer: _Writer(),
    );

    expect(find.text('till.shop.local'), findsOne);
    expect(find.text('515'), findsOne);
  });

  testWidgets('an unconfigured form still defaults the port', (tester) async {
    // The port is the half of an address that is safe to guess; the host is
    // not, and is left empty.
    await _pump(tester, _controller(), _Reader(), writer: _Writer());

    expect(find.text('${PrinterEndpoint.rawEscPosPort}'), findsOne);
  });

  group('saving', () {
    testWidgets('writes exactly the printer keys, merged, and re-reads', (
      tester,
    ) async {
      final writer = _Writer();
      final reader = _Reader();

      await _pump(tester, _controller(), reader, writer: writer);
      // A new printer defaults to an 80mm roll, the one most shops buy.
      await _save(tester, host: '192.168.1.50');

      expect(writer.merges.single.path, _printerPath);
      expect(writer.merges.single.data, <String, Object?>{
        'transport': 'direct_tcp',
        'host': '192.168.1.50',
        'port': 9100,
        'paperWidth': 'columns_48',
        'hasCutter': true,
        'updatedBy': 'owner-a',
      });
      expect(snackNotice(tester).status, AppStatus.ok);
      // Re-read, because the document is what a receipt is dialled at rather
      // than the value that was typed.
      expect(reader.requested, hasLength(2));
    });

    testWidgets('refuses an address this app would not dial', (tester) async {
      // The same validation that guards the durable job record and the socket.
      // The refusal a person reads is the refusal the socket would have given.
      final writer = _Writer();

      await _pump(tester, _controller(), _Reader(), writer: writer);
      await _save(tester, host: 'http://printer', confirm: false);

      expect(writer.merges, isEmpty);
      expect(
        snackNotice(tester).message,
        startsWith('Enter the printer address as a name or an IP'),
      );
    });

    testWidgets('refuses a port that is not a number', (tester) async {
      final writer = _Writer();

      await _pump(tester, _controller(), _Reader(), writer: writer);
      await tester.enterText(
        find.byKey(const ValueKey('printer-configuration-port')),
        'nine thousand',
      );
      await _save(tester, host: '192.168.1.50', confirm: false);

      expect(writer.merges, isEmpty);
      expect(
        snackNotice(tester).message,
        startsWith('Enter the port as a number'),
      );
    });

    testWidgets('re-saving the identical printer is not a refusal', (
      tester,
    ) async {
      // The printer the operator wanted saved *is* what is saved, so the
      // intent is satisfied - `info`, not `problem`.
      final writer = _Writer();

      await _pump(
        tester,
        _controller(),
        _Reader(stored: _stored()),
        writer: writer,
      );
      await _save(tester, host: '192.168.1.50', confirm: false);

      expect(writer.merges, isEmpty);
      expect(snackNotice(tester).status, AppStatus.info);
    });

    testWidgets('warns that queued receipts keep the old address', (
      tester,
    ) async {
      // §8 rule 6, and the one thing this change has to warn about: a job
      // carries its own address, so a receipt already waiting still goes where
      // it was queued to go.
      await _pump(
        tester,
        _controller(),
        _Reader(stored: _stored()),
        writer: _Writer(),
      );
      await tester.enterText(
        find.byKey(const ValueKey('printer-configuration-host')),
        '192.168.1.99',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('printer-configuration-submit')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Point receipts at a different printer?'), findsOne);
      expect(find.textContaining('still goes to 192.168.1.50:9100'), findsOne);
    });

    testWidgets('an offline write says nothing was saved', (tester) async {
      final writer = _Writer(
        result: const TenantConfigurationWriteResult.unavailable(),
      );

      await _pump(tester, _controller(), _Reader(), writer: writer);
      await _save(tester, host: '192.168.1.50');

      expect(snackNotice(tester).status, AppStatus.info);
    });

    testWidgets('a rejected write does not re-read', (tester) async {
      // Nothing changed, so re-reading would only discard the form.
      final reader = _Reader();
      final writer = _Writer(
        result: const TenantConfigurationWriteResult.rejected(
          'permission-denied',
        ),
      );

      await _pump(tester, _controller(), reader, writer: writer);
      await _save(tester, host: '192.168.1.50');

      expect(reader.requested, hasLength(1));
      expect(snackNotice(tester).status, AppStatus.problem);
    });
  });

  group('testing a printer', () {
    testWidgets('prints what is typed, not what is stored', (tester) async {
      // The whole use is checking a printer before committing to it.
      final printed = <TenantPrinterConfiguration>[];

      await _pump(
        tester,
        _controller(),
        _Reader(stored: _stored()),
        writer: _Writer(),
        testPrint: (configuration) async => printed.add(configuration),
      );
      await tester.enterText(
        find.byKey(const ValueKey('printer-configuration-host')),
        '192.168.1.99',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('printer-configuration-test')),
      );
      await tester.pumpAndSettle();

      expect(printed.single.endpoint.host, '192.168.1.99');
      // **The whole configuration, not an address.** The page prints the paper
      // width and is laid out to it, so a width set to the wrong roll is a
      // fault this control can show and a bare host could not carry.
      expect(printed.single.paperWidth, PrinterPaperWidth.columns32);
      // **A snack bar since 2026-08-26.** The answer belongs to the button that
      // was just pressed, not to the record of a save.
      expect(
        snackNotice(tester).message,
        startsWith('A test page was sent to the printer.'),
      );
    });

    testWidgets('says sent, and asks somebody to look at the roll', (
      tester,
    ) async {
      // `PrinterTransport.send` returning means the bytes were handed off and
      // never that paper moved, so the sentence must not claim it did - and the
      // one person who can see the roll is asked to check the width on it.
      await _pump(
        tester,
        _controller(),
        _Reader(stored: _stored()),
        writer: _Writer(),
        testPrint: (_) async {},
      );
      await tester.tap(
        find.byKey(const ValueKey('printer-configuration-test')),
      );
      await tester.pumpAndSettle();

      expect(snackNotice(tester).message, contains('was sent to the printer'));
      expect(snackNotice(tester).message, contains('width of the roll'));
      expect(snackNotice(tester).status, AppStatus.ok);
    });

    testWidgets('maps a failure through the transports own vocabulary', (
      tester,
    ) async {
      // This screen invents no sentence of its own; the eight codes are mapped
      // once, in `checkout_print_failures.dart`.
      await _pump(
        tester,
        _controller(),
        _Reader(stored: _stored()),
        writer: _Writer(),
        testPrint: (_) async => throw const PrinterTransportException(
          PrinterTransportCode.connectTimeout,
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('printer-configuration-test')),
      );
      await tester.pumpAndSettle();

      expect(
        snackNotice(tester).message,
        PrinterFailureNotice.of(PrinterTransportCode.connectTimeout).message,
      );
    });

    testWidgets('is not offered where there is no transport to print with', (
      tester,
    ) async {
      // A control that cannot work is worse than a missing one.
      await _pump(tester, _controller(), _Reader(), writer: _Writer());

      expect(
        find.byKey(const ValueKey('printer-configuration-test')),
        findsNothing,
      );
    });
  });

  group('who may change it', () {
    testWidgets('a manager is denied the whole route, not shown it read-only', (
      tester,
    ) async {
      // Every active member reads this document - a till cannot send a receipt
      // without it - but deciding what hardware the business owns is not an
      // operational act.
      for (final role in const <TenantRole>[
        TenantRole.manager,
        TenantRole.cashier,
      ]) {
        await _pump(
          tester,
          _controller(role: role),
          _Reader(stored: _stored()),
          writer: _Writer(),
        );

        expect(
          find.byKey(const ValueKey('printer-configuration-denied')),
          findsOne,
          reason: role.name,
        );
        // And it says what is still true, rather than only refusing.
        expect(
          find.textContaining('Receipts still print on whatever'),
          findsOne,
          reason: role.name,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('a build with no writer states it rather than pretending', (
      tester,
    ) async {
      await _pump(tester, _controller(), _Reader(stored: _stored()));

      expect(
        find.byKey(const ValueKey('printer-configuration-read-only')),
        findsOne,
      );
      expect(
        find.byKey(const ValueKey('printer-configuration-submit')),
        findsNothing,
      );
    });
  });

  testWidgets('a failed read is an ErrorState that says nothing changed', (
    tester,
  ) async {
    await _pump(tester, _controller(), _Reader.failing(), writer: _Writer());

    expect(
      find.byKey(const ValueKey('printer-configuration-failure')),
      findsOne,
    );
    expect(find.byType(ErrorState), findsOne);
  });

  group('the Bluetooth tab', () {
    testWidgets('without Bluetooth the page is the network form alone', (
      tester,
    ) async {
      await _pump(tester, _controller(), _Reader(), writer: _Writer());

      expect(
        find.byKey(const ValueKey('printer-configuration-tabs')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('printer-configuration-host')),
        findsOne,
      );
    });

    testWidgets('a sideways swipe changes tab, and a short drag does not', (
      tester,
    ) async {
      await _pump(
        tester,
        _controller(),
        _Reader(stored: _stored()),
        writer: _Writer(),
        bluetooth: _bluetooth(),
      );
      final search = find.byKey(const ValueKey('printer-bluetooth-search'));
      final field = find.byKey(const ValueKey('printer-configuration-host'));
      // Just under the strip, on the tab's own content. A swipe that starts on
      // a text field is the field's, as it is in a `TabBarView`.
      Offset content() =>
          tester.getBottomLeft(find.byType(AppTabs)) + const Offset(200, 24);

      await tester.dragFrom(content(), const Offset(-40, 0));
      await tester.pumpAndSettle();
      expect(search, findsNothing);

      await tester.flingFrom(content(), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(search, findsOne);

      // Past the last tab there is nowhere to go.
      await tester.flingFrom(content(), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(search, findsOne);

      await tester.flingFrom(content(), const Offset(300, 0), 1000);
      await tester.pumpAndSettle();
      expect(search, findsNothing);
      expect(field, findsOne);
    });

    testWidgets('opens on Network and asks the phone nothing until Search', (
      tester,
    ) async {
      // A permission prompt follows a press, never the opening of a page.
      final discovery = _FakeDiscovery();
      await _pump(
        tester,
        _controller(),
        _Reader(stored: _stored()),
        writer: _Writer(),
        bluetooth: _bluetooth(discovery: discovery),
      );

      expect(
        find.byKey(const ValueKey('printer-configuration-tabs')),
        findsOne,
      );
      expect(
        find.byKey(const ValueKey('printer-configuration-host')),
        findsOne,
      );
      expect(
        find.byKey(const ValueKey('printer-bluetooth-search')),
        findsNothing,
      );

      await _openBluetoothTab(tester);

      expect(find.byKey(const ValueKey('printer-bluetooth-search')), findsOne);
      expect(discovery.prepareCalls, 0);
    });

    testWidgets('finds paired and nearby devices, and connects the chosen one', (
      tester,
    ) async {
      final discovery = _FakeDiscovery(
        pairedDevices: const <BluetoothPrinterDevice>[
          BluetoothPrinterDevice(
            address: _speakerAddress,
            name: 'Counter speaker',
            paired: true,
          ),
        ],
      );
      final store = _MemoryStore();
      final probe = _Probe();
      await _pump(
        tester,
        _controller(),
        _Reader(stored: _stored()),
        writer: _Writer(),
        bluetooth: _bluetooth(discovery: discovery, store: store, probe: probe),
      );
      await _openBluetoothTab(tester);

      await _search(
        tester,
        discovery,
        found: const <BluetoothPrinterDevice>[
          BluetoothPrinterDevice(address: _printerAddress, paired: false),
          // The same printer again, now with its name: the list keeps one row.
          BluetoothPrinterDevice(
            address: _printerAddress,
            name: 'MPT-II',
            paired: false,
          ),
        ],
      );

      expect(discovery.prepareCalls, 1);
      expect(
        find.byKey(const ValueKey('printer-bluetooth-device-$_speakerAddress')),
        findsOne,
      );
      expect(
        find.byKey(const ValueKey('printer-bluetooth-device-$_printerAddress')),
        findsOne,
      );
      expect(find.text('MPT-II'), findsOne);

      await _connect(tester, _printerAddress);

      // Paired, then a real connection through the transport, then stored -
      // and only a printer that answered is stored.
      expect(discovery.pairCalls, <String>[_printerAddress]);
      expect(probe.probes.single, PrinterEndpoint.bluetooth(_printerAddress));
      // 58mm is the Bluetooth default: the narrow, portable kind.
      expect(store.read('tenant-a'), _mpt());
      // The sheet closes on the answer, and the answer is the page's.
      expect(
        find.byKey(const ValueKey('printer-bluetooth-sheet')),
        findsNothing,
      );
      expect(snackNotice(tester).status, AppStatus.ok);
      expect(
        snackNotice(tester).message,
        'Connected to MPT-II. Receipts from this device now print on it.',
      );
      expect(find.byKey(const ValueKey('printer-bluetooth-current')), findsOne);
    });

    testWidgets(
      "a second printer opens on the defaults, not the last sheet's",
      (tester) async {
        final discovery = _FakeDiscovery(
          pairedDevices: const <BluetoothPrinterDevice>[
            BluetoothPrinterDevice(
              address: _speakerAddress,
              name: 'Counter speaker',
              paired: true,
            ),
            BluetoothPrinterDevice(
              address: _printerAddress,
              name: 'MPT-II',
              paired: true,
            ),
          ],
        );
        await _pump(
          tester,
          _controller(),
          _Reader(stored: _stored()),
          writer: _Writer(),
          bluetooth: _bluetooth(discovery: discovery, store: _MemoryStore()),
        );
        await _openBluetoothTab(tester);
        await _search(tester, discovery);

        await tester.tap(
          find.byKey(
            const ValueKey('printer-bluetooth-device-$_speakerAddress'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('printer-bluetooth-cutter')),
        );
        await tester.pumpAndSettle();
        Navigator.of(
          tester.element(
            find.byKey(const ValueKey('printer-bluetooth-cutter')),
          ),
        ).pop();
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(
            const ValueKey('printer-bluetooth-device-$_printerAddress'),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<CheckboxListTile>(
                find.byKey(const ValueKey('printer-bluetooth-cutter')),
              )
              .value,
          isFalse,
        );
      },
    );

    testWidgets('a choice that cannot be saved is said, and nothing is kept', (
      tester,
    ) async {
      final discovery = _FakeDiscovery(
        pairedDevices: const <BluetoothPrinterDevice>[
          BluetoothPrinterDevice(
            address: _printerAddress,
            name: 'MPT-II',
            paired: true,
          ),
        ],
      );
      final store = _MemoryStore()..broken = true;
      await _pump(
        tester,
        _controller(),
        _Reader(stored: _stored()),
        writer: _Writer(),
        bluetooth: _bluetooth(
          discovery: discovery,
          store: store,
          probe: _Probe(),
        ),
      );
      await _openBluetoothTab(tester);
      await _search(tester, discovery);

      await _connect(tester, _printerAddress);

      expect(store.printers, isEmpty);
      expect(
        find.textContaining('Bluetooth on this device did not finish that'),
        findsOne,
      );
    });

    testWidgets('a printer that does not answer is not stored', (tester) async {
      final discovery = _FakeDiscovery(
        pairedDevices: const <BluetoothPrinterDevice>[
          BluetoothPrinterDevice(
            address: _printerAddress,
            name: 'MPT-II',
            paired: true,
          ),
        ],
      );
      final store = _MemoryStore();
      await _pump(
        tester,
        _controller(),
        _Reader(),
        writer: _Writer(),
        bluetooth: _bluetooth(
          discovery: discovery,
          store: store,
          probe: _Probe(failWith: PrinterTransportCode.bluetoothUnreachable),
        ),
      );
      await _openBluetoothTab(tester);
      await _search(tester, discovery);

      await _connect(tester, _printerAddress);

      expect(store.printers, isEmpty);
      // The sheet stays open with the reason, in the sheet: a snack bar would
      // be drawn underneath it.
      expect(find.byKey(const ValueKey('printer-bluetooth-sheet')), findsOne);
      expect(
        noticeMessage(tester, 'printer-bluetooth-answer'),
        PrinterFailureNotice.of(
          PrinterTransportCode.bluetoothUnreachable,
        ).message,
      );
      expect(
        noticeStatus(tester, 'printer-bluetooth-answer'),
        AppStatus.problem,
      );
    });

    testWidgets('a pairing that is refused connects nothing', (tester) async {
      final discovery = _FakeDiscovery(pairs: false);
      final store = _MemoryStore();
      final probe = _Probe();
      await _pump(
        tester,
        _controller(),
        _Reader(),
        writer: _Writer(),
        bluetooth: _bluetooth(discovery: discovery, store: store, probe: probe),
      );
      await _openBluetoothTab(tester);
      await _search(
        tester,
        discovery,
        found: const <BluetoothPrinterDevice>[
          BluetoothPrinterDevice(
            address: _printerAddress,
            name: 'MPT-II',
            paired: false,
          ),
        ],
      );

      await _connect(tester, _printerAddress);

      expect(discovery.pairCalls, <String>[_printerAddress]);
      expect(probe.probes, isEmpty);
      expect(store.printers, isEmpty);
      expect(
        noticeStatus(tester, 'printer-bluetooth-answer'),
        AppStatus.problem,
      );
    });

    testWidgets('a refused permission says where to grant it', (tester) async {
      final discovery = _FakeDiscovery(
        readiness: BluetoothReadiness.permissionDenied,
      );
      await _pump(
        tester,
        _controller(),
        _Reader(),
        writer: _Writer(),
        bluetooth: _bluetooth(discovery: discovery),
      );
      await _openBluetoothTab(tester);
      await _search(tester, discovery);

      expect(discovery.search$, isNull);
      expect(
        noticeStatus(tester, 'printer-bluetooth-denied'),
        AppStatus.problem,
      );

      await tester.tap(
        find.byKey(const ValueKey('printer-bluetooth-settings')),
      );
      await tester.pump();
      expect(discovery.settingsCalls, 1);
    });

    testWidgets('Bluetooth off is offered on, and then searched', (
      tester,
    ) async {
      final discovery = _FakeDiscovery(readiness: BluetoothReadiness.off);
      await _pump(
        tester,
        _controller(),
        _Reader(),
        writer: _Writer(),
        bluetooth: _bluetooth(discovery: discovery),
      );
      await _openBluetoothTab(tester);
      await _search(tester, discovery);

      expect(discovery.search$, isNull);
      expect(
        noticeStatus(tester, 'printer-bluetooth-off'),
        AppStatus.attention,
      );

      await tester.tap(find.byKey(const ValueKey('printer-bluetooth-turn-on')));
      await tester.pump();
      await tester.pump();

      expect(discovery.turnOnCalls, 1);
      expect(discovery.prepareCalls, 2);
      expect(discovery.search$, isNotNull);
      expect(find.byKey(const ValueKey('printer-bluetooth-off')), findsNothing);
      await discovery.search$!.close();
      await tester.pumpAndSettle();
    });

    testWidgets(
      'a device on Bluetooth opens on that tab and says so on Network',
      (tester) async {
        final store = _MemoryStore(<String, DeviceBluetoothPrinter>{
          'tenant-a': _mpt(),
        });
        await _pump(
          tester,
          _controller(),
          _Reader(),
          writer: _Writer(),
          bluetooth: _bluetooth(store: store),
        );

        expect(
          find.byKey(const ValueKey('printer-bluetooth-current')),
          findsOne,
        );

        await _openNetworkTab(tester);

        // The business has no network printer, but this device is not going
        // nowhere - so the "receipts are not sent anywhere" notice would be
        // untrue here, and this one replaces it.
        expect(
          noticeMessage(tester, 'printer-configuration-bluetooth-in-use'),
          contains('MPT-II'),
        );
        expect(
          find.byKey(const ValueKey('printer-configuration-current')),
          findsNothing,
        );
      },
    );

    testWidgets('stop using returns this device to the network printer', (
      tester,
    ) async {
      final store = _MemoryStore(<String, DeviceBluetoothPrinter>{
        'tenant-a': _mpt(),
      });
      await _pump(
        tester,
        _controller(),
        _Reader(stored: _stored()),
        writer: _Writer(),
        bluetooth: _bluetooth(store: store),
      );

      await tester.tap(find.byKey(const ValueKey('printer-bluetooth-forget')));
      await tester.pumpAndSettle();

      expect(store.printers, isEmpty);
      expect(
        find.byKey(const ValueKey('printer-bluetooth-current')),
        findsNothing,
      );
      expect(snackNotice(tester).status, AppStatus.ok);

      await _openNetworkTab(tester);
      expect(
        find.byKey(const ValueKey('printer-configuration-bluetooth-in-use')),
        findsNothing,
      );
    });

    testWidgets('stop using that cannot be written says so and keeps it', (
      tester,
    ) async {
      final store = _MemoryStore(<String, DeviceBluetoothPrinter>{
        'tenant-a': _mpt(),
      })..broken = true;
      await _pump(
        tester,
        _controller(),
        _Reader(stored: _stored()),
        writer: _Writer(),
        bluetooth: _bluetooth(store: store),
      );

      await tester.tap(find.byKey(const ValueKey('printer-bluetooth-forget')));
      await tester.pumpAndSettle();

      expect(store.printers, isNotEmpty);
      expect(snackNotice(tester).status, AppStatus.problem);
      expect(
        snackNotice(tester).message,
        'This device could not stop using the printer. Try again.',
      );
    });

    testWidgets('the test page goes to the chosen Bluetooth printer', (
      tester,
    ) async {
      final printed = <TenantPrinterConfiguration>[];
      final discovery = _FakeDiscovery(
        pairedDevices: const <BluetoothPrinterDevice>[
          BluetoothPrinterDevice(
            address: _printerAddress,
            name: 'MPT-II',
            paired: true,
          ),
        ],
      );
      await _pump(
        tester,
        _controller(),
        _Reader(),
        writer: _Writer(),
        testPrint: (configuration) async => printed.add(configuration),
        bluetooth: _bluetooth(discovery: discovery),
      );
      await _openBluetoothTab(tester);
      await _search(tester, discovery);
      await tester.tap(
        find.byKey(const ValueKey('printer-bluetooth-device-$_printerAddress')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('printer-bluetooth-test')));
      await tester.pumpAndSettle();

      expect(printed.single, _mpt().configuration);
      // Sent, not connected: the sheet stays open on the answer.
      expect(noticeStatus(tester, 'printer-bluetooth-answer'), AppStatus.ok);
      expect(find.byKey(const ValueKey('printer-bluetooth-sheet')), findsOne);
    });

    testWidgets('the tab opens on where this device prints now', (
      tester,
    ) async {
      await _pump(
        tester,
        _controller(),
        _Reader(stored: _stored(paperWidth: 'columns_48', hasCutter: false)),
        writer: _Writer(),
        bluetooth: _bluetooth(),
      );
      await _openBluetoothTab(tester);

      expect(find.byKey(const ValueKey('printer-bluetooth-network')), findsOne);
      expect(find.text('192.168.1.50:9100 · 80mm roll'), findsOne);
      expect(
        find.byKey(const ValueKey('printer-bluetooth-no-printer')),
        findsNothing,
      );
    });

    testWidgets('with no printer anywhere, the card says so', (tester) async {
      await _pump(
        tester,
        _controller(),
        _Reader(),
        writer: _Writer(),
        bluetooth: _bluetooth(),
      );
      await _openBluetoothTab(tester);

      expect(
        find.byKey(const ValueKey('printer-bluetooth-no-printer')),
        findsOne,
      );
      expect(find.text('Not set up'), findsOne);
    });

    testWidgets('lists paired and nearby apart, and folds nameless ones', (
      tester,
    ) async {
      final discovery = _FakeDiscovery(
        pairedDevices: const <BluetoothPrinterDevice>[
          BluetoothPrinterDevice(
            address: _speakerAddress,
            name: 'Counter speaker',
            paired: true,
          ),
        ],
      );
      await _pump(
        tester,
        _controller(),
        _Reader(),
        writer: _Writer(),
        bluetooth: _bluetooth(discovery: discovery),
      );
      await _openBluetoothTab(tester);
      await _search(
        tester,
        discovery,
        found: const <BluetoothPrinterDevice>[
          BluetoothPrinterDevice(
            address: _printerAddress,
            name: 'MPT-II',
            paired: false,
          ),
          BluetoothPrinterDevice(address: _namelessAddress, paired: false),
        ],
      );

      Finder inGroup(String group, String address) => find.descendant(
        of: find.byKey(ValueKey(group)),
        matching: find.byKey(ValueKey('printer-bluetooth-device-$address')),
      );
      expect(inGroup('printer-bluetooth-paired', _speakerAddress), findsOne);
      expect(inGroup('printer-bluetooth-nearby', _printerAddress), findsOne);
      expect(find.text('1 device with no name'), findsOne);
      // Folded: out of the tree until it is opened.
      expect(
        find.byKey(
          const ValueKey('printer-bluetooth-device-$_namelessAddress'),
        ),
        findsNothing,
      );

      await tester.tap(find.text('1 device with no name'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          const ValueKey('printer-bluetooth-device-$_namelessAddress'),
        ),
        findsOne,
      );
    });

    testWidgets('an unpaired printer says Connect pairs it, then goes quiet', (
      tester,
    ) async {
      final pairing = Completer<bool>();
      final discovery = _FakeDiscovery(pairing: pairing);
      final store = _MemoryStore();
      await _pump(
        tester,
        _controller(),
        _Reader(),
        writer: _Writer(),
        testPrint: (_) async {},
        bluetooth: _bluetooth(discovery: discovery, store: store),
      );
      await _openBluetoothTab(tester);
      await _search(
        tester,
        discovery,
        found: const <BluetoothPrinterDevice>[
          BluetoothPrinterDevice(
            address: _printerAddress,
            name: 'MPT-II',
            paired: false,
          ),
        ],
      );
      await tester.tap(
        find.byKey(const ValueKey('printer-bluetooth-device-$_printerAddress')),
      );
      await tester.pumpAndSettle();

      expect(
        noticeStatus(tester, 'printer-bluetooth-before-pairing'),
        AppStatus.info,
      );

      await tester.tap(find.byKey(const ValueKey('printer-bluetooth-connect')));
      await tester.pump();

      // Pairing: the sentence changes, Connect spins and the rest wait.
      expect(
        noticeStatus(tester, 'printer-bluetooth-pairing'),
        AppStatus.attention,
      );
      expect(
        tester
            .widget<AppButton>(
              find.byKey(const ValueKey('printer-bluetooth-connect')),
            )
            .loading,
        isTrue,
      );
      expect(
        tester
            .widget<AppButton>(
              find.byKey(const ValueKey('printer-bluetooth-test')),
            )
            .onPressed,
        isNull,
      );

      // The back key cannot take the sheet away while the prompt is up.
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byKey(const ValueKey('printer-bluetooth-sheet')), findsOne);

      pairing.complete(true);
      await tester.pumpAndSettle();

      expect(store.read('tenant-a'), _mpt());
      expect(
        find.byKey(const ValueKey('printer-bluetooth-sheet')),
        findsNothing,
      );
    });

    testWidgets('a platform without Bluetooth says where to set it up', (
      tester,
    ) async {
      await _pump(
        tester,
        _controller(),
        _Reader(),
        writer: _Writer(),
        bluetooth: _bluetooth(discovery: _FakeDiscovery(supported: false)),
      );
      await _openBluetoothTab(tester);

      expect(
        noticeStatus(tester, 'printer-bluetooth-unsupported'),
        AppStatus.info,
      );
      expect(
        find.byKey(const ValueKey('printer-bluetooth-search')),
        findsNothing,
      );
    });
  });
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

String _buttonLabel(WidgetTester tester, String key) =>
    tester.widget<AppButton>(find.byKey(ValueKey(key))).label;

/// Types a host and saves, which is the only way anything is written.
Future<void> _save(
  WidgetTester tester, {
  required String host,
  bool confirm = true,
}) async {
  await tester.enterText(
    find.byKey(const ValueKey('printer-configuration-host')),
    host,
  );
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('printer-configuration-submit')));
  await tester.pumpAndSettle();
  if (!confirm) return;
  await tester.tap(find.byKey(const ValueKey('printer-configuration-confirm')));
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester,
  TenantSessionController controller,
  _Reader reader, {
  TenantConfigurationDocumentWriter? writer,
  PrinterTestPrint? testPrint,
  BluetoothPrinterSetup? bluetooth,
}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: Scaffold(
          body: TenantPrinterConfigurationPanel(
            reader: reader,
            writer: writer,
            testPrint: testPrint,
            bluetooth: bluetooth,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

const String _printerAddress = 'EC:8E:77:5B:A1:4D';
const String _speakerAddress = '08:E4:DF:FC:B2:5F';
const String _namelessAddress = '5C:F3:70:12:9A:01';

BluetoothPrinterSetup _bluetooth({
  _FakeDiscovery? discovery,
  _MemoryStore? store,
  _Probe? probe,
}) => BluetoothPrinterSetup(
  discovery: discovery ?? _FakeDiscovery(),
  store: store ?? _MemoryStore(),
  probe: (probe ?? _Probe()).call,
);

Future<void> _openBluetoothTab(WidgetTester tester) async {
  await tester.tap(find.text('Bluetooth'));
  await tester.pumpAndSettle();
}

/// The tab, not the word: the Bluetooth tab's card wears a *Network* badge.
Future<void> _openNetworkTab(WidgetTester tester) async {
  await tester.tap(
    find.descendant(of: find.byType(AppTabs), matching: find.text('Network')),
  );
  await tester.pumpAndSettle();
}

/// Presses Search, reports [found] from discovery, and lets discovery end.
Future<void> _search(
  WidgetTester tester,
  _FakeDiscovery discovery, {
  List<BluetoothPrinterDevice> found = const <BluetoothPrinterDevice>[],
}) async {
  await tester.tap(find.byKey(const ValueKey('printer-bluetooth-search')));
  await tester.pump();
  await tester.pump();
  final search = discovery.search$;
  if (search == null) return;
  for (final device in found) {
    search.add(device);
  }
  await tester.pump();
  await search.close();
  await tester.pumpAndSettle();
}

Future<void> _connect(WidgetTester tester, String address) async {
  await tester.tap(find.byKey(ValueKey('printer-bluetooth-device-$address')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('printer-bluetooth-connect')));
  await tester.pumpAndSettle();
}

DeviceBluetoothPrinter _mpt({
  PrinterPaperWidth paperWidth = PrinterPaperWidth.columns32,
}) => DeviceBluetoothPrinter(
  address: _printerAddress,
  name: 'MPT-II',
  paperWidth: paperWidth,
  hasCutter: false,
);

final class _FakeDiscovery implements BluetoothPrinterDiscovery {
  _FakeDiscovery({
    this.supported = true,
    this.readiness = BluetoothReadiness.ready,
    this.pairedDevices = const <BluetoothPrinterDevice>[],
    this.pairs = true,
    this.pairing,
  });

  final bool supported;
  BluetoothReadiness readiness;
  final List<BluetoothPrinterDevice> pairedDevices;
  final bool pairs;

  /// Holds a pairing open until a test completes it, as the phone's prompt
  /// does. Null answers [pairs] at once.
  final Completer<bool>? pairing;

  int prepareCalls = 0;
  int turnOnCalls = 0;
  int settingsCalls = 0;
  final List<String> pairCalls = <String>[];

  /// The running search, so a test can report devices and end it.
  StreamController<BluetoothPrinterDevice>? search$;

  @override
  bool get isSupported => supported;

  @override
  Future<BluetoothReadiness> prepare() async {
    prepareCalls++;
    return readiness;
  }

  @override
  Future<bool> turnOn() async {
    turnOnCalls++;
    readiness = BluetoothReadiness.ready;
    return true;
  }

  @override
  Future<void> openPermissionSettings() async => settingsCalls++;

  @override
  Future<List<BluetoothPrinterDevice>> paired() async => pairedDevices;

  @override
  Stream<BluetoothPrinterDevice> search() =>
      (search$ = StreamController<BluetoothPrinterDevice>()).stream;

  @override
  Future<bool> pair(String address) async {
    pairCalls.add(address);
    return pairing?.future ?? pairs;
  }
}

final class _MemoryStore implements DeviceBluetoothPrinterStore {
  _MemoryStore([Map<String, DeviceBluetoothPrinter>? printers])
    : printers = printers ?? <String, DeviceBluetoothPrinter>{};

  final Map<String, DeviceBluetoothPrinter> printers;

  /// Whether writing fails, as a box that cannot be written does.
  bool broken = false;

  @override
  DeviceBluetoothPrinter? read(String tenantId) => printers[tenantId];

  @override
  Future<void> save(String tenantId, DeviceBluetoothPrinter printer) async {
    if (broken) throw StateError('box would not write');
    printers[tenantId] = printer;
  }

  @override
  Future<void> forget(String tenantId) async {
    if (broken) throw StateError('box would not write');
    printers.remove(tenantId);
  }
}

final class _Probe {
  _Probe({this.failWith});

  final String? failWith;
  final List<PrinterEndpoint> probes = <PrinterEndpoint>[];

  Future<void> call(PrinterEndpoint endpoint) async {
    probes.add(endpoint);
    if (failWith case final code?) throw PrinterTransportException(code);
  }
}

TenantSessionController _controller({TenantRole role = TenantRole.owner}) =>
    TenantSessionController()..open(
      uid: 'owner-a',
      membership: _membership(role: role),
    );

TenantMembership _membership({TenantRole role = TenantRole.owner}) =>
    TenantMembership(
      tenantId: 'tenant-a',
      tenantName: 'tenant-a',
      tenantSlug: 'tenant-a',
      role: role,
      membershipStatus: MembershipStatus.active,
      tenantStatus: TenantStatus.active,
      isOwner: role == TenantRole.owner,
      mirrorVersion: 1,
      createdAt: DateTime.utc(2026, 8, 1),
      updatedAt: DateTime.utc(2026, 8, 1),
      serverCanAccess: true,
      canonicalTenantExists: true,
      canonicalMembershipExists: true,
    );

final class _Merge {
  const _Merge(this.path, this.data);

  final String path;
  final Map<String, Object?> data;
}

final class _Writer implements TenantConfigurationDocumentWriter {
  _Writer({this.result = const TenantConfigurationWriteResult.committed()});

  final TenantConfigurationWriteResult result;
  final List<_Merge> merges = <_Merge>[];

  @override
  Future<TenantConfigurationWriteResult> merge({
    required String path,
    required Map<String, Object?> data,
  }) async {
    merges.add(_Merge(path, data));
    return result;
  }
}

final class _Reader implements TenantDataReader {
  _Reader({Map<String, Object?>? stored}) : _stored = stored, _fails = false;

  _Reader.failing() : _stored = null, _fails = true;

  final Map<String, Object?>? _stored;
  final bool _fails;
  final List<String> requested = <String>[];

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    requested.add(path);
    if (_fails) throw StateError('unavailable');
    final stored = _stored;
    return stored == null
        ? null
        : TenantDocumentSnapshot(path: path, data: stored);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async => const <TenantQueryDocumentSnapshot>[];
}
