import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_application_1/inventory/product_image_cache.dart';

/// Draws a deterministic product photograph used by the screenshot catalog.
Future<Uint8List> screenshotProductImage() async {
  const logicalSize = 96.0;
  const pixelSize = 512;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.scale(pixelSize / logicalSize);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 96, 96),
    ui.Paint()
      ..shader = ui.Gradient.linear(
        const ui.Offset(0, 0),
        const ui.Offset(96, 96),
        const <ui.Color>[ui.Color(0xffe0eee9), ui.Color(0xff9fc9c3)],
      ),
  );
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
      const ui.Rect.fromLTWH(16, 24, 64, 50),
      const ui.Radius.circular(14),
    ),
    ui.Paint()..color = const ui.Color(0xff1f5260),
  );
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
      const ui.Rect.fromLTWH(20, 27, 56, 42),
      const ui.Radius.circular(11),
    ),
    ui.Paint()
      ..shader = ui.Gradient.linear(
        const ui.Offset(20, 27),
        const ui.Offset(76, 69),
        const <ui.Color>[ui.Color(0xff49a9b7), ui.Color(0xff2c6b84)],
      ),
  );
  final score = ui.Paint()
    ..color = const ui.Color(0x99dff9f5)
    ..strokeWidth = 4
    ..strokeCap = ui.StrokeCap.round;
  for (final x in <double>[37, 48, 59]) {
    canvas.drawLine(ui.Offset(x - 5, 36), ui.Offset(x + 2, 48), score);
  }
  final image = await recorder.endRecording().toImage(pixelSize, pixelSize);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) {
    throw StateError('Could not encode screenshot product image.');
  }
  return data.buffer.asUint8List();
}

/// Answers every `NetworkImage` in a capture with [screenshotProductImage].
///
/// **Without this the catalog is a grid of initials.** `NetworkImage` reaches
/// for a real socket, which a widget test answers with a 400 - so every
/// photograph in every capture fell back to its stand-in, and the one thing the
/// pictures were supposed to show could not be seen in them. The inventory
/// route worked around it by injecting a `MemoryImage` through
/// `productVisualBuilder`; the till has no such seam, and adding one to the
/// sale path so that a screenshot could be taken would be the test shaping the
/// app.
///
/// **`debugNetworkImageHttpClientProvider` rather than `HttpOverrides`.**
/// `NetworkImage` holds one `HttpClient` in a static field, built the first
/// time any image is fetched and never rebuilt - so an override installed
/// afterwards is an override it never asks. This hook is the seam Flutter
/// provides for exactly that, and it is the one `flutter_test` documents.
///
/// It answers nothing but image bytes: a capture that reached the network for
/// anything else gets a picture and fails loudly rather than quietly talking to
/// a server.
Future<void> loadScreenshotProductImages() async {
  final bytes = _bytes ??= await screenshotProductImage();
  debugNetworkImageHttpClientProvider = () => _ImageHttpClient(bytes);
}

Uint8List? _bytes;

/// A store that answers every picture with the screenshot photograph.
///
/// **The catalog does not fetch through `NetworkImage`.**
/// `TenantCachedNetworkImage` reads its store first and falls back to a plain
/// `package:http` GET, and `debugNetworkImageHttpClientProvider` above is a seam
/// `NetworkImage` alone consults - so the operations captures went to a real
/// socket, got nothing, and raised `image_unreachable`. `precacheImage` reports
/// that to `FlutterError.onError` as well as throwing it, and `flutter_test`
/// fails a test on any reported error, so the harness's own `catch` around the
/// precache could not swallow it.
///
/// Answering from the store instead means the fetch never happens. It also
/// matches what a device does on the second run, which is the state these
/// pictures should show.
final class ScreenshotImageCache implements TenantImageCache {
  const ScreenshotImageCache(this.bytes);

  final Uint8List bytes;

  @override
  Future<Uint8List?> read(Uri url) async => bytes;

  /// The harness keeps nothing: every read is already a hit.
  @override
  Future<void> write(Uri url, Uint8List bytes) async {}
}

/// The store to install over a capture, once [loadScreenshotProductImages] has
/// drawn the photograph. Null before then, which installs no scope at all.
ScreenshotImageCache? screenshotImageCache() {
  final bytes = _bytes;
  return bytes == null ? null : ScreenshotImageCache(bytes);
}

final class _ImageHttpClient implements io.HttpClient {
  _ImageHttpClient(this.bytes);

  final Uint8List bytes;

  @override
  Future<io.HttpClientRequest> getUrl(Uri url) async =>
      _ImageHttpRequest(url, bytes);

  @override
  Future<io.HttpClientRequest> openUrl(String method, Uri url) async =>
      _ImageHttpRequest(url, bytes);

  @override
  void close({bool force = false}) {}

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('The screenshot harness serves images only.');
}

final class _ImageHttpRequest implements io.HttpClientRequest {
  _ImageHttpRequest(this.uri, this.bytes);

  @override
  final Uri uri;

  final Uint8List bytes;

  @override
  final io.HttpHeaders headers = _ImageHttpHeaders();

  @override
  Future<io.HttpClientResponse> close() async => _ImageHttpResponse(bytes);

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('The screenshot harness serves images only.');
}

final class _ImageHttpResponse extends Stream<List<int>>
    implements io.HttpClientResponse {
  _ImageHttpResponse(this.bytes);

  final Uint8List bytes;

  @override
  int get statusCode => io.HttpStatus.ok;

  @override
  int get contentLength => bytes.length;

  @override
  io.HttpClientResponseCompressionState get compressionState =>
      io.HttpClientResponseCompressionState.notCompressed;

  @override
  final io.HttpHeaders headers = _ImageHttpHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('The screenshot harness serves images only.');
}

final class _ImageHttpHeaders implements io.HttpHeaders {
  @override
  List<String>? operator [](String name) => null;

  @override
  String? value(String name) => null;

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  void removeAll(String name) {}

  @override
  int get contentLength => -1;

  @override
  set contentLength(int value) {}

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('The screenshot harness serves images only.');
}
