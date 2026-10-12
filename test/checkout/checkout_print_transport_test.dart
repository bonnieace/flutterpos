import 'dart:async';
import 'dart:io';

import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:uzapay_pos/checkout/checkout_print_transport_io.dart';
import 'package:uzapay_pos/checkout/checkout_print_transport_unsupported.dart';
import 'package:uzapay_pos/ui/status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PrinterEndpoint', () {
    test('accepts a bare host and an IPv4 address', () {
      expect(PrinterEndpoint(host: 'printer-01', port: 9100).host, 'printer-01');
      expect(PrinterEndpoint(host: '192.168.1.50', port: 9100).port, 9100);
      expect(
        PrinterEndpoint(host: 'till.shop.local', port: 515).toString(),
        'till.shop.local:515',
      );
    });

    test('refuses every host this app will not dial', () {
      // `docs/printer_transport.md` §9: "PrinterEndpoint validation, including
      // hosts we must refuse." Each of these is a real shape somebody types
      // into a settings field.
      for (final host in const <String>[
        '',
        '   ',
        ' printer ', // padded, and the padding is invisible in a form
        'http://printer', // a URL, not a socket address
        'printer/print', // a path
        'user:pass@printer', // credentials
        'printer:9100', // a port, which is a second source for one number
        'prin ter', // whitespace
        '0.0.0.0', // means "listen on everything", never a printer
        '-printer', // not a legal label
        'printer-', // not a legal label
      ]) {
        expect(
          () => PrinterEndpoint(host: host, port: 9100),
          throwsA(isA<ArgumentError>()),
          reason: 'host: "$host"',
        );
      }
    });

    test('refuses a port outside 1-65535', () {
      for (final port in const <int>[0, -1, 65536, 70000]) {
        expect(
          () => PrinterEndpoint(host: 'printer', port: port),
          throwsA(isA<ArgumentError>()),
          reason: 'port: $port',
        );
      }
    });

    test('is a value, so two of the same address are the same endpoint', () {
      expect(
        PrinterEndpoint(host: 'printer', port: 9100),
        PrinterEndpoint(host: 'printer', port: 9100),
      );
      expect(
        PrinterEndpoint(host: 'printer', port: 9100),
        isNot(PrinterEndpoint(host: 'printer', port: 9101)),
      );
    });
  });

  group('the unsupported stub', () {
    test('throws rather than silently no-oping', () async {
      // §1.1: "so a new platform target fails loudly at first print instead of
      // quietly dropping receipts". A receipt that was never printed and never
      // complained is the worst outcome available.
      const transport = UnsupportedPrinterTransport();
      final endpoint = PrinterEndpoint(host: 'printer', port: 9100);

      await expectLater(
        transport.send(endpoint, const <int>[27, 64]),
        throwsA(
          const PrinterTransportException(PrinterTransportCode.unsupported),
        ),
      );
      await expectLater(
        transport.probe(endpoint),
        throwsA(
          const PrinterTransportException(PrinterTransportCode.unsupported),
        ),
      );
      expect(transport.capability.kind, PrinterTransportKind.none);
    });
  });

  group('the dart:io transport, against a real ServerSocket', () {
    test('accepts a connection and delivers every byte', () async {
      final received = <int>[];
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final done = Completer<void>();
      server.listen((socket) {
        socket.listen(received.addAll, onDone: () {
          if (!done.isCompleted) done.complete();
        });
      });
      addTearDown(server.close);

      final transport = IoPrinterTransport();
      const payload = <int>[27, 64, 27, 97, 1, 72, 105, 10];
      await transport.send(
        PrinterEndpoint(host: '127.0.0.1', port: server.port),
        payload,
      );
      await done.future.timeout(const Duration(seconds: 5));

      expect(received, payload);
      expect(transport.capability.kind, PrinterTransportKind.directTcp);
      expect(transport.capability.endpointIsPrinter, isTrue);
    });

    test('probes without writing a byte', () async {
      final received = <int>[];
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((socket) => socket.listen(received.addAll));
      addTearDown(server.close);

      await IoPrinterTransport().probe(
        PrinterEndpoint(host: '127.0.0.1', port: server.port),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Onboarding needs "is this printer reachable?" without wasting paper.
      expect(received, isEmpty);
    });

    test('reports a refused connection as unreachable', () async {
      // Bind and close, so the port is certainly nobody's.
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      await server.close();

      await expectLater(
        IoPrinterTransport().send(
          PrinterEndpoint(host: '127.0.0.1', port: port),
          const <int>[27, 64],
        ),
        throwsA(
          const PrinterTransportException(PrinterTransportCode.unreachable),
        ),
      );
    });

    test('reports a connect that runs out of time as a connect timeout', () async {
      // **The elapsed clock decides, not an errno**, because `Socket.connect`
      // reports a timeout as a `SocketException` whose `osError` differs per
      // platform — which is the dead `on TimeoutException` branch
      // `docs/printer_transport.md` §2 records in the borrowed repo.
      final transport = IoPrinterTransport(
        connectTimeout: const Duration(milliseconds: 20),
        connect: (host, port, {timeout}) async {
          await Future<void>.delayed(const Duration(milliseconds: 60));
          throw const SocketException('timed out');
        },
      );

      await expectLater(
        transport.send(
          PrinterEndpoint(host: '127.0.0.1', port: 9100),
          const <int>[27, 64],
        ),
        throwsA(
          const PrinterTransportException(PrinterTransportCode.connectTimeout),
        ),
      );
    });

    test('reports a printer that accepts and then stalls as a write timeout', () async {
      // A paper jam or an open cover: the socket is accepted and the payload
      // never drains. Different fault, different operator guidance.
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final held = <Socket>[];
      server.listen((socket) {
        // Never read, and never close: the send buffer fills and `flush`
        // never completes.
        held.add(socket);
      });
      addTearDown(() async {
        for (final socket in held) {
          socket.destroy();
        }
        await server.close();
      });

      final transport = IoPrinterTransport(
        writeTimeout: const Duration(milliseconds: 80),
        connect: (host, port, {timeout}) async {
          final socket = await Socket.connect(host, port, timeout: timeout);
          return _StallingSocket(socket);
        },
      );

      await expectLater(
        transport.send(
          PrinterEndpoint(host: '127.0.0.1', port: server.port),
          const <int>[27, 64],
        ),
        throwsA(
          const PrinterTransportException(PrinterTransportCode.writeTimeout),
        ),
      );
    });
  });

  group('the failure vocabulary', () {
    test('every code maps to a sentence and a status', () {
      // "Mapping happens at the UI edge. The transport never builds a
      // sentence." Asserted by code, never by message — which is why the codes
      // are enumerable in the first place.
      // §8's eight, the three Bluetooth added on 2026-10-03, USB's three on
      // 2026-10-10, the print window's two the same day, and the print
      // helper's two on 2026-10-11.
      expect(PrinterTransportCode.all, hasLength(18));
      for (final code in PrinterTransportCode.all) {
        final notice = PrinterFailureNotice.of(code);
        expect(notice.message, isNotEmpty, reason: code);
        expect(notice.message, isNot(contains(code)), reason: code);
      }
    });

    test('a stall is attention rather than problem, and setup is info', () {
      // The one judgement in that file: a stalled printer may yet produce the
      // receipt, and an unconfigured one has not failed at all.
      expect(
        PrinterFailureNotice.of(PrinterTransportCode.writeTimeout).status,
        AppStatus.attention,
      );
      expect(
        PrinterFailureNotice.of(PrinterTransportCode.notConfigured).status,
        AppStatus.info,
      );
      expect(
        PrinterFailureNotice.of(PrinterTransportCode.unreachable).status,
        AppStatus.problem,
      );
    });

    test('names an unknown code rather than swallowing it', () {
      // A code this build has never heard of means a durable record written by
      // a newer one, and saying so beats a generic apology.
      final notice = PrinterFailureNotice.of('printer_on_fire');

      expect(notice.message, contains('printer_on_fire'));
      expect(notice.status, AppStatus.attention);
    });

    test('offers a retry only where one could work', () {
      expect(
        PrinterFailureNotice.isRetryable(PrinterTransportCode.notConfigured),
        isFalse,
      );
      expect(
        PrinterFailureNotice.isRetryable(PrinterTransportCode.unsupported),
        isFalse,
      );
      expect(
        PrinterFailureNotice.isRetryable(PrinterTransportCode.unreachable),
        isTrue,
      );
    });

    test('says sent, never printed', () {
      // `send` returning normally means the transport handed every byte off.
      // It does not prove paper moved, and no string here may claim it did.
      expect(PrinterFailureNotice.sent.message, contains('sent'));
      for (final notice in <AppNotice>[
        PrinterFailureNotice.sent,
        PrinterFailureNotice.queued,
        for (final code in PrinterTransportCode.all)
          PrinterFailureNotice.of(code),
      ]) {
        expect(
          notice.message.toLowerCase(),
          isNot(contains('printed')),
          reason: notice.message,
        );
      }
    });
  });
}

/// A socket whose `flush` never completes, so a write timeout can be driven
/// without depending on how large the platform's send buffer happens to be.
final class _StallingSocket implements Socket {
  _StallingSocket(this._inner);

  final Socket _inner;

  @override
  Future<void> flush() => Completer<void>().future;

  @override
  void destroy() => _inner.destroy();

  @override
  Future<void> close() => _inner.close();

  @override
  void add(List<int> data) => _inner.add(data);

  @override
  noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}
