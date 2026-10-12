import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:uzapay_pos/theme.dart';
import 'package:uzapay_pos/ui/status.dart';

import '../support/notices.dart';

final PrinterEndpoint _usb = PrinterEndpoint.usb('1FC9:2016:06C6ACA91073');
final PrinterEndpoint _network = PrinterEndpoint(
  host: '192.168.1.50',
  port: 9100,
);

void main() {
  group('the helper client', () {
    test('finds the helper, and only the helper', () async {
      final found = HttpPrintHelper(
        client: MockClient(
          (_) async => http.Response(
            '{"app":"uzapay-print-helper","version":"1.0.0"}',
            200,
          ),
        ),
      );
      expect(await found.version(), '1.0.0');

      final other = HttpPrintHelper(
        client: MockClient(
          (_) async => http.Response('{"app":"something-else"}', 200),
        ),
      );
      expect(await other.version(), isNull);

      final nobody = HttpPrintHelper(
        client: MockClient((_) async => throw http.ClientException('refused')),
      );
      expect(await nobody.version(), isNull);
    });

    test('sends the receipt as JSON, to the printer named', () async {
      http.Request? sent;
      await HttpPrintHelper(
        client: MockClient((request) async {
          sent = request;
          return http.Response('{"ok":true}', 200);
        }),
      ).send(_usb, const <int>[0x1B, 0x40]);

      expect(sent!.url.toString(), 'http://127.0.0.1:17919/print');
      // JSON is what makes a browser ask the helper first.
      expect(sent!.headers['content-type'], startsWith('application/json'));
      final body = jsonDecode(sent!.body) as Map<String, Object?>;
      expect(body['target'], <String, Object?>{
        'kind': 'usb',
        'key': '1FC9:2016:06C6ACA91073',
      });
      expect(base64Decode(body['data']! as String), <int>[0x1B, 0x40]);
    });

    test('a network printer goes by address', () async {
      http.Request? sent;
      await HttpPrintHelper(
        client: MockClient((request) async {
          sent = request;
          return http.Response('{"ok":true}', 200);
        }),
      ).probe(_network);

      expect(sent!.url.path, '/probe');
      expect((jsonDecode(sent!.body) as Map)['target'], <String, Object?>{
        'kind': 'network',
        'host': '192.168.1.50',
        'port': 9100,
      });
    });

    test('passes the helper’s own failure on as the app’s code', () async {
      final helper = HttpPrintHelper(
        client: MockClient(
          (_) async =>
              http.Response('{"ok":false,"code":"usb_printer_busy"}', 200),
        ),
      );

      await expectLater(
        helper.send(_usb, const <int>[1]),
        throwsA(const PrinterTransportException(PrinterTransportCode.usbBusy)),
      );
    });

    test('nothing answering is the helper not running', () async {
      final helper = HttpPrintHelper(
        client: MockClient((_) async => throw http.ClientException('refused')),
      );

      await expectLater(
        helper.send(_network, const <int>[1]),
        throwsA(
          const PrinterTransportException(
            PrinterTransportCode.printHelperUnreachable,
          ),
        ),
      );
    });

    test('a print that outlasts the wait may still come out', () async {
      final helper = HttpPrintHelper(
        client: MockClient((_) => Completer<http.Response>().future),
        printTimeout: const Duration(milliseconds: 20),
      );

      await expectLater(
        helper.send(_usb, const <int>[1]),
        throwsA(
          const PrinterTransportException(PrinterTransportCode.writeTimeout),
        ),
      );
    });

    test('asks the helper to remove itself, as JSON', () async {
      http.Request? sent;
      final removal = await HttpPrintHelper(
        client: MockClient((request) async {
          sent = request;
          return http.Response('{"ok":true}', 200);
        }),
      ).remove();

      expect(removal, PrintHelperRemoval.removed);
      expect(sent!.method, 'POST');
      expect(sent!.url.toString(), 'http://127.0.0.1:17919/uninstall');
      expect(sent!.headers['content-type'], startsWith('application/json'));
    });

    test('a helper that cannot remove itself, or none answering, is '
        'not removed', () async {
      final outdated = HttpPrintHelper(
        client: MockClient(
          (_) async => http.Response('{"ok":false,"code":"not_found"}', 404),
        ),
      );
      expect(await outdated.remove(), PrintHelperRemoval.outdated);

      final nobody = HttpPrintHelper(
        client: MockClient((_) async => throw http.ClientException('refused')),
      );
      expect(await nobody.remove(), PrintHelperRemoval.failed);

      final refused = HttpPrintHelper(
        client: MockClient(
          (_) async => http.Response('{"ok":false,"code":"bad_request"}', 400),
        ),
      );
      expect(await refused.remove(), PrintHelperRemoval.failed);
    });

    test('lists the USB printers it found', () async {
      final printers = await HttpPrintHelper(
        client: MockClient(
          (_) async => http.Response(
            '{"usb":[{"key":"1FC9:2016:06C6ACA91073","name":"Xprinter XP-365B"}]}',
            200,
          ),
        ),
      ).usbPrinters();

      expect(printers.single.key, '1FC9:2016:06C6ACA91073');
      expect(printers.single.name, 'Xprinter XP-365B');
    });
  });

  group('network printers from a browser', () {
    test('are not tried before the helper has been seen', () async {
      final helper = _FakeHelper();
      final transport = HelperNetworkPrinterTransport(
        helper: helper,
        memory: InMemoryPrintHelperMemory(),
      );

      await expectLater(
        transport.send(_network, const <int>[1]),
        throwsA(
          const PrinterTransportException(PrinterTransportCode.unsupported),
        ),
      );
      expect(helper.sent, isEmpty);
    });

    test('go through the helper once it has', () async {
      final helper = _FakeHelper();
      await HelperNetworkPrinterTransport(
        helper: helper,
        memory: InMemoryPrintHelperMemory(seen: true),
      ).send(_network, const <int>[1]);

      expect(helper.sent, <PrinterEndpoint>[_network]);
    });
  });

  group('USB printers from a browser', () {
    HelperFirstUsbPrinterTransport transport(
      _FakeHelper helper,
      _FakeWebUsb webUsb, {
      bool seen = true,
    }) => HelperFirstUsbPrinterTransport(
      helper: helper,
      memory: InMemoryPrintHelperMemory(seen: seen),
      webUsb: webUsb,
    );

    test('go through the helper when it is there', () async {
      final helper = _FakeHelper();
      final webUsb = _FakeWebUsb();
      await transport(helper, webUsb).send(_usb, const <int>[1]);

      expect(helper.sent, <PrinterEndpoint>[_usb]);
      expect(webUsb.sent, isEmpty);
    });

    test('go through WebUSB when the helper was never seen', () async {
      final helper = _FakeHelper();
      final webUsb = _FakeWebUsb();
      await transport(helper, webUsb, seen: false).send(_usb, const <int>[1]);

      expect(helper.sent, isEmpty);
      expect(webUsb.sent, <PrinterEndpoint>[_usb]);
    });

    test('fall back to WebUSB when the helper is not running, or cannot '
        'see the printer', () async {
      for (final code in <String>[
        PrinterTransportCode.printHelperUnreachable,
        PrinterTransportCode.usbNotFound,
      ]) {
        final webUsb = _FakeWebUsb();
        await transport(
          _FakeHelper(failWith: code),
          webUsb,
        ).send(_usb, const <int>[1]);
        expect(webUsb.sent, <PrinterEndpoint>[_usb], reason: code);
      }
    });

    test('never try again by WebUSB after the helper reached the printer '
        'and failed', () async {
      // Half a receipt may be on the roll already; a second route would put
      // a second half under it.
      final webUsb = _FakeWebUsb();
      await expectLater(
        transport(
          _FakeHelper(failWith: PrinterTransportCode.writeTimeout),
          webUsb,
        ).send(_usb, const <int>[1]),
        throwsA(
          const PrinterTransportException(PrinterTransportCode.writeTimeout),
        ),
      );
      expect(webUsb.sent, isEmpty);
    });
  });

  group('the card on the Printer page', () {
    Future<void> pump(
      WidgetTester tester,
      PrintHelperSetup setup, {
      ValueChanged<bool>? onLooked,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: spiritTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: PrintHelperCard(setup: setup, onLooked: onLooked),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> pressRemove(
      WidgetTester tester, {
      required bool confirm,
    }) async {
      await tester.tap(find.byKey(const ValueKey('print-helper-remove')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          ValueKey(
            confirm
                ? 'print-helper-remove-confirm'
                : 'print-helper-remove-cancel',
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('says the helper is running, and remembers finding it', (
      tester,
    ) async {
      final memory = InMemoryPrintHelperMemory();
      await pump(
        tester,
        PrintHelperSetup(
          helper: _FakeHelper(version: '1.0.0'),
          memory: memory,
          download: () async {},
        ),
      );

      expect(noticeStatus(tester, 'print-helper-running'), AppStatus.ok);
      expect(memory.seen, isTrue);
      expect(find.byKey(const ValueKey('print-helper-download')), findsNothing);
    });

    testWidgets('offers the download when it is not, then the steps', (
      tester,
    ) async {
      var downloads = 0;
      final helper = _FakeHelper();
      final memory = InMemoryPrintHelperMemory();
      await pump(
        tester,
        PrintHelperSetup(
          helper: helper,
          memory: memory,
          download: () async => downloads++,
        ),
      );
      expect(find.byKey(const ValueKey('print-helper-absent')), findsOne);
      expect(memory.seen, isFalse);

      await tester.tap(find.byKey(const ValueKey('print-helper-download')));
      await tester.pumpAndSettle();
      expect(downloads, 1);
      expect(find.byKey(const ValueKey('print-helper-steps')), findsOne);

      // Installed: Check again finds it.
      helper.versionAnswer = '1.0.0';
      await tester.tap(find.byKey(const ValueKey('print-helper-check')));
      await tester.pumpAndSettle();
      expect(noticeStatus(tester, 'print-helper-running'), AppStatus.ok);
      expect(memory.seen, isTrue);
    });

    testWidgets('after the download it notices the helper by itself', (
      tester,
    ) async {
      final helper = _FakeHelper();
      final memory = InMemoryPrintHelperMemory();
      await pump(
        tester,
        PrintHelperSetup(helper: helper, memory: memory, download: () async {}),
      );
      await tester.tap(find.byKey(const ValueKey('print-helper-download')));
      await tester.pumpAndSettle();

      // Still downloading and running it: nothing changes on screen.
      await tester.pump(PrintHelperCard.watchEvery);
      expect(find.byKey(const ValueKey('print-helper-absent')), findsOne);

      // It starts; nobody presses anything.
      helper.versionAnswer = '1.0.3';
      await tester.pump(PrintHelperCard.watchEvery);
      await tester.pump();
      expect(noticeStatus(tester, 'print-helper-running'), AppStatus.ok);
      expect(memory.seen, isTrue);
    });

    testWidgets('removes the helper once asked twice, and forgets it', (
      tester,
    ) async {
      final helper = _FakeHelper(version: '1.0.4');
      final memory = InMemoryPrintHelperMemory();
      final looked = <bool>[];
      await pump(
        tester,
        PrintHelperSetup(helper: helper, memory: memory, download: () async {}),
        onLooked: looked.add,
      );

      // Cancelled: nothing happens.
      await pressRemove(tester, confirm: false);
      expect(helper.removals, 0);
      expect(noticeStatus(tester, 'print-helper-running'), AppStatus.ok);

      await pressRemove(tester, confirm: true);
      expect(helper.removals, 1);
      expect(memory.seen, isFalse);
      expect(looked.last, isFalse);
      expect(find.byKey(const ValueKey('print-helper-absent')), findsOne);
      expect(
        find.text('The print helper was removed from this computer.'),
        findsOne,
      );
    });

    testWidgets('a helper too old to remove itself is sent to the Windows '
        'Apps list, and stays', (tester) async {
      final helper = _FakeHelper(
        version: '1.0.3',
        removal: PrintHelperRemoval.outdated,
      );
      final memory = InMemoryPrintHelperMemory();
      await pump(
        tester,
        PrintHelperSetup(helper: helper, memory: memory, download: () async {}),
      );

      await pressRemove(tester, confirm: true);
      expect(noticeStatus(tester, 'print-helper-running'), AppStatus.ok);
      expect(
        noticeStatus(tester, 'print-helper-not-removed'),
        AppStatus.attention,
      );
      expect(find.textContaining('too old to remove'), findsOne);
      expect(memory.seen, isTrue);

      // One that did not answer says so instead.
      helper.removal = PrintHelperRemoval.failed;
      await pressRemove(tester, confirm: true);
      expect(find.textContaining('did not answer'), findsOne);
      expect(memory.seen, isTrue);
    });
  });
}

final class _FakeHelper implements PrintHelper {
  _FakeHelper({
    this.failWith,
    String? version,
    this.removal = PrintHelperRemoval.removed,
  }) : versionAnswer = version;

  final String? failWith;
  String? versionAnswer;

  /// What asking it to remove itself answers.
  PrintHelperRemoval removal;
  var removals = 0;
  final List<PrinterEndpoint> sent = <PrinterEndpoint>[];

  @override
  Future<String?> version() async => versionAnswer;

  @override
  Future<List<PrintHelperPrinter>> usbPrinters() async =>
      const <PrintHelperPrinter>[
        PrintHelperPrinter(
          key: '1FC9:2016:06C6ACA91073',
          name: 'Xprinter XP-365B',
        ),
      ];

  @override
  Future<void> send(PrinterEndpoint endpoint, List<int> bytes) async {
    if (failWith case final code?) throw PrinterTransportException(code);
    sent.add(endpoint);
  }

  @override
  Future<void> probe(PrinterEndpoint endpoint) async {
    if (failWith case final code?) throw PrinterTransportException(code);
  }

  @override
  Future<PrintHelperRemoval> remove() async {
    removals++;
    if (removal == PrintHelperRemoval.removed) versionAnswer = null;
    return removal;
  }
}

final class _FakeWebUsb implements PrinterTransport {
  final List<PrinterEndpoint> sent = <PrinterEndpoint>[];

  @override
  PrinterTransportCapability get capability => const PrinterTransportCapability(
    kind: PrinterTransportKind.usb,
    endpointIsPrinter: true,
    label: 'WebUSB',
  );

  @override
  Future<void> probe(PrinterEndpoint endpoint) async {}

  @override
  Future<void> send(PrinterEndpoint endpoint, List<int> bytes) async =>
      sent.add(endpoint);

  @override
  Future<void> dispose() async {}
}
