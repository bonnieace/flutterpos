import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:uzapay_print_helper/print_helper.dart';

void main() {
  late _FakeBackend backend;
  late HttpServer server;
  late HttpClient client;
  var quit = 0;
  var uninstalled = 0;

  setUp(() async {
    backend = _FakeBackend();
    quit = 0;
    uninstalled = 0;
    server = await HelperServer(
      backend: backend,
      onQuit: () => quit++,
      onUninstall: () async => uninstalled++,
    ).bind(port: 0);
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await server.close(force: true);
  });

  Future<({int status, Map<String, Object?> body, HttpHeaders headers})> call(
    String method,
    String path, {
    String? origin,
    Object? json,
    String? contentType,
  }) async {
    final request = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:${server.port}$path'),
    );
    if (origin != null) request.headers.set('origin', origin);
    if (json != null) {
      request.headers.contentType = contentType == null
          ? ContentType.json
          : ContentType.parse(contentType);
      request.write(jsonEncode(json));
    }
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    return (
      status: response.statusCode,
      body: text.isEmpty
          ? <String, Object?>{}
          : (jsonDecode(text) as Map).cast<String, Object?>(),
      headers: response.headers,
    );
  }

  const till = 'https://app.uzapay.co.ke';
  final receipt = <String, Object?>{
    'target': <String, Object?>{'kind': 'usb', 'key': '1FC9:2016:06C6ACA91073'},
    'data': base64Encode(<int>[0x1B, 0x40, 0x41]),
  };

  test('says who it is, to UzaPay’s pages, with CORS', () async {
    final answer = await call('GET', '/status', origin: till);

    expect(answer.status, HttpStatus.ok);
    expect(answer.body['app'], helperApp);
    expect(answer.body['version'], helperVersion);
    expect(answer.headers.value('access-control-allow-origin'), till);
  });

  test('another site is refused, and told nothing it could use', () async {
    final answer = await call(
      'POST',
      '/print',
      origin: 'https://evil.example',
      json: receipt,
    );

    expect(answer.status, HttpStatus.forbidden);
    expect(answer.headers.value('access-control-allow-origin'), isNull);
    expect(backend.printed, isEmpty);
  });

  test('a preflight from the till is answered, and from Chrome’s private '
      'network check too', () async {
    final answer = await call('OPTIONS', '/print', origin: till);

    expect(answer.status, HttpStatus.noContent);
    expect(
      answer.headers.value('access-control-allow-headers'),
      'content-type',
    );
    expect(
      answer.headers.value('access-control-allow-private-network'),
      'true',
    );
  });

  test('prints the bytes to the printer named, and says it did', () async {
    final answer = await call('POST', '/print', origin: till, json: receipt);

    expect(answer.body, <String, Object?>{'ok': true});
    expect(backend.printed.single.$1, isA<UsbTarget>());
    expect(backend.printed.single.$2, <int>[0x1B, 0x40, 0x41]);
  });

  test('passes on the printer’s own failure as the app’s code', () async {
    backend.answer = HelperCode.usbBusy;

    final answer = await call('POST', '/print', origin: till, json: receipt);

    expect(answer.body, <String, Object?>{
      'ok': false,
      'code': HelperCode.usbBusy,
    });
  });

  test('a body that is not JSON is never read as a job', () async {
    // What an ordinary form on another page could send without asking.
    final answer = await call(
      'POST',
      '/print',
      json: receipt,
      contentType: 'text/plain',
    );

    expect(answer.status, HttpStatus.badRequest);
    expect(backend.printed, isEmpty);
  });

  test('lists the USB printers it has', () async {
    final answer = await call('GET', '/printers', origin: till);

    expect(answer.body['usb'], <Object?>[
      <String, Object?>{
        'key': '1FC9:2016:06C6ACA91073',
        'name': 'Xprinter XP-365B',
      },
    ]);
  });

  test('probes without printing', () async {
    final answer = await call(
      'POST',
      '/probe',
      origin: till,
      json: <String, Object?>{'target': receipt['target']},
    );

    expect(answer.body, <String, Object?>{'ok': true});
    expect(backend.probed, hasLength(1));
    expect(backend.printed, isEmpty);
  });

  test('stops when a newer copy asks', () async {
    final answer = await call('POST', '/quit');

    expect(answer.body, <String, Object?>{'ok': true});
    // Asked to stop just after the answer is on its way.
    for (var wait = 0; quit == 0 && wait < 50; wait++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(quit, 1);
  });

  test('removes itself when UzaPay’s Printer page asks', () async {
    final answer = await call(
      'POST',
      '/uninstall',
      origin: till,
      json: <String, Object?>{},
    );

    expect(answer.body, <String, Object?>{'ok': true});
    for (var wait = 0; uninstalled == 0 && wait < 50; wait++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(uninstalled, 1);
  });

  test('is not removed by another site, nor by a request that is not '
      'JSON', () async {
    final refused = await call(
      'POST',
      '/uninstall',
      origin: 'https://evil.example',
      json: <String, Object?>{},
    );
    final plain = await call('POST', '/uninstall', origin: till);

    expect(refused.status, HttpStatus.forbidden);
    expect(plain.status, HttpStatus.badRequest);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(uninstalled, 0);
  });
}

final class _FakeBackend implements PrinterBackend {
  final List<(PrintTarget, Uint8List)> printed = <(PrintTarget, Uint8List)>[];
  final List<PrintTarget> probed = <PrintTarget>[];
  String? answer;

  @override
  Future<List<UsbPrinterInfo>> usbPrinters() async => const <UsbPrinterInfo>[
    UsbPrinterInfo(
      key: '1FC9:2016:06C6ACA91073',
      name: 'Xprinter XP-365B',
      path: r'\\?\usb#vid_1fc9&pid_2016#06c6aca91073#{guid}',
    ),
  ];

  @override
  Future<String?> print(PrintTarget target, Uint8List bytes) async {
    printed.add((target, bytes));
    return answer;
  }

  @override
  Future<String?> probe(PrintTarget target) async {
    probed.add(target);
    return answer;
  }
}
