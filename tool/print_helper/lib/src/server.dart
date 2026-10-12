/// The helper's few endpoints, on `127.0.0.1` only.
///
/// - `GET /status` - who this is and which version.
/// - `GET /printers` - the USB printers Windows has now.
/// - `POST /print` - `{target, data}`, the bytes in base64.
/// - `POST /probe` - `{target}`: is it there, without printing.
/// - `POST /quit` - stop, so a newer copy can take its place.
/// - `POST /uninstall` - stop, and remove this helper from the computer: the
///   Printer page's *Remove print helper*. JSON, like a print, so a page has
///   to ask first.
///
/// **An `Origin` that is not UzaPay's is refused before the body is read**,
/// with no CORS headers, so the page behind it learns nothing either. A
/// `POST` must be JSON, which a browser cannot send to another site without
/// asking first - and the asking is answered only for UzaPay's own pages.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'backend.dart';
import 'protocol.dart';

final class HelperServer {
  HelperServer({
    required this.backend,
    this.onQuit,
    this.onUninstall,
    this.log,
  });

  final PrinterBackend backend;

  /// Called once `/quit` has been answered.
  final void Function()? onQuit;

  /// Called once `/uninstall` has been answered.
  final Future<void> Function()? onUninstall;

  /// Where a request that failed is written down.
  final void Function(String line)? log;

  /// Listens on `127.0.0.1:[port]`. Throws [SocketException] when the port is
  /// taken - by another copy of the helper, as a rule.
  Future<HttpServer> bind({int port = helperPort}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    server.listen((request) => unawaited(handle(request)));
    return server;
  }

  Future<void> handle(HttpRequest request) async {
    final response = request.response;
    try {
      final origin = request.headers.value('origin');
      if (origin != null) {
        if (!isAllowedOrigin(origin)) {
          log?.call('refused origin $origin ${request.uri.path}');
          return _json(response, HttpStatus.forbidden, <String, Object?>{
            'ok': false,
            'code': 'origin_refused',
          });
        }
        response.headers
          ..set('Access-Control-Allow-Origin', origin)
          ..set('Vary', 'Origin')
          ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
          ..set('Access-Control-Allow-Headers', 'content-type')
          // Chrome's older rule for a public page calling this computer.
          ..set('Access-Control-Allow-Private-Network', 'true')
          ..set('Access-Control-Max-Age', '600');
      }
      final path = request.uri.path;
      switch ((request.method, path)) {
        case ('OPTIONS', _):
          response.statusCode = HttpStatus.noContent;
          await response.close();
        case ('GET', '/status'):
          await _json(response, HttpStatus.ok, <String, Object?>{
            'app': helperApp,
            'version': helperVersion,
          });
        case ('GET', '/printers'):
          final printers = await backend.usbPrinters();
          await _json(response, HttpStatus.ok, <String, Object?>{
            'usb': <Object?>[for (final printer in printers) printer.toJson()],
          });
        case ('POST', '/print'):
          final body = await _body(request);
          if (body == null) return _badRequest(response);
          final ({PrintTarget target, Uint8List bytes}) job;
          try {
            job = parsePrint(body);
          } on FormatException {
            return _badRequest(response);
          }
          await _outcome(response, await backend.print(job.target, job.bytes));
        case ('POST', '/probe'):
          final body = await _body(request);
          if (body is! Map) return _badRequest(response);
          final PrintTarget target;
          try {
            target = parseTarget(body['target']);
          } on FormatException {
            return _badRequest(response);
          }
          await _outcome(response, await backend.probe(target));
        case ('POST', '/quit'):
          await _json(response, HttpStatus.ok, <String, Object?>{'ok': true});
          onQuit?.call();
        case ('POST', '/uninstall'):
          if (await _body(request) is! Map) return _badRequest(response);
          await _json(response, HttpStatus.ok, <String, Object?>{'ok': true});
          await onUninstall?.call();
        default:
          await _json(response, HttpStatus.notFound, <String, Object?>{
            'ok': false,
            'code': 'not_found',
          });
      }
    } catch (error, stackTrace) {
      log?.call('request failed: $error\n$stackTrace');
      try {
        await _json(response, HttpStatus.internalServerError, <String, Object?>{
          'ok': false,
          'code': HelperCode.badRequest,
        });
      } catch (_) {
        // The response was already on its way; nothing more to say.
      }
    }
  }

  /// The JSON body, or null for one that is not JSON, too large, or unreadable.
  Future<Object?> _body(HttpRequest request) async {
    final type = request.headers.contentType;
    if (type == null || type.mimeType != ContentType.json.mimeType) {
      return null;
    }
    final bytes = <int>[];
    await for (final chunk in request) {
      bytes.addAll(chunk);
      if (bytes.length > maximumBodyBytes) return null;
    }
    try {
      return jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return null;
    }
  }

  Future<void> _outcome(HttpResponse response, String? code) => _json(
    response,
    HttpStatus.ok,
    <String, Object?>{'ok': code == null, if (code != null) 'code': code},
  );

  Future<void> _badRequest(HttpResponse response) => _json(
    response,
    HttpStatus.badRequest,
    <String, Object?>{'ok': false, 'code': HelperCode.badRequest},
  );

  Future<void> _json(
    HttpResponse response,
    int status,
    Map<String, Object?> body,
  ) async {
    response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..headers.set('Cache-Control', 'no-store')
      ..write(jsonEncode(body));
    await response.close();
  }
}
