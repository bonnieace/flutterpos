import 'dart:io' show SocketException;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_application_1/inventory/inventory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;

/// A flat rectangle of [width] by [height], as PNG bytes.
TenantProductImageCandidate _photo({
  required int width,
  required int height,
  String fileName = 'shot.jpg',
}) {
  final image = img.Image(width: width, height: height, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(200, 30, 30));
  return TenantProductImageCandidate(
    bytes: Uint8List.fromList(img.encodePng(image)),
    fileName: fileName,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('framing placement', () {
    test('the whole photograph fits inside the square, centred', () {
      const framing = TenantProductFraming.whole();

      final wide = framing.placementFor(2);
      expect(wide.width, closeTo(1, 1e-9));
      expect(wide.height, closeTo(0.5, 1e-9));
      expect(wide.center, const Offset(0.5, 0.5));

      final tall = framing.placementFor(0.5);
      expect(tall.width, closeTo(0.5, 1e-9));
      expect(tall.height, closeTo(1, 1e-9));
    });

    test('filling covers the square on both axes', () {
      for (final aspect in <double>[0.4, 0.75, 1, 1.5, 3]) {
        final placement = TenantProductFraming.filling(
          aspect,
        ).placementFor(aspect);
        expect(
          placement.width,
          greaterThanOrEqualTo(1 - 1e-9),
          reason: '$aspect',
        );
        expect(
          placement.height,
          greaterThanOrEqualTo(1 - 1e-9),
          reason: '$aspect',
        );
      }
    });

    test('the middle of the photograph never leaves the square', () {
      for (final scale in <double>[0.3, 1, 2, 5]) {
        final framing = TenantProductFraming(
          scale: scale,
          center: const Offset(-4, 9),
        ).clampedTo(1.5);

        expect(framing.center, const Offset(0, 1), reason: '$scale');
      }
    });

    test('the framing that fills the square can still be moved', () {
      // The state the editor opens in, and the one an earlier rule froze: at
      // exactly cover the photograph is the canvas's size on its short axis,
      // and a rule forbidding any visible ground left nowhere to go.
      const aspect = 1.5;
      final opened = TenantProductFraming.filling(aspect);
      final dragged = TenantProductFraming(
        scale: opened.scale,
        center: opened.center + const Offset(0.2, 0.2),
      ).clampedTo(aspect);

      expect(dragged.center, isNot(opened.center));
      expect(dragged.center, const Offset(0.7, 0.7));
    });

    test('how far it can travel does not depend on the zoom', () {
      // A drag that does the same thing at every scale is the whole point of
      // one rule rather than two.
      for (final scale in <double>[0.3, 1, 2, 5]) {
        final moved = TenantProductFraming(
          scale: scale,
          center: const Offset(0.9, 0.1),
        ).clampedTo(0.75);

        expect(moved.center, const Offset(0.9, 0.1), reason: '$scale');
      }
    });

    test('a tilted photograph has to be larger to fill the square', () {
      // A square turned 45 degrees needs its sides at root two to cover.
      expect(TenantProductFraming.coverScaleFor(1, 0), closeTo(1, 1e-9));
      expect(
        TenantProductFraming.coverScaleFor(1, math.pi / 4),
        closeTo(math.sqrt2, 1e-9),
      );
      // A quarter turn asks nothing extra of a square.
      expect(
        TenantProductFraming.coverScaleFor(1, math.pi / 2),
        closeTo(1, 1e-9),
      );
    });

    test('a tilt is kept within half a turn either way', () {
      final wound = const TenantProductFraming(
        rotation: 5 * math.pi,
      ).clampedTo(1);

      expect(wound.rotation, closeTo(math.pi, 1e-9));
    });

    test('zoom is bounded at both ends', () {
      expect(
        const TenantProductFraming(scale: 99).clampedTo(1).scale,
        maximumFramingScale,
      );
      expect(
        const TenantProductFraming(scale: 0.001).clampedTo(1).scale,
        minimumFramingScale,
      );
    });
  });

  group('fetching a saved photograph', () {
    final url = Uri.parse(
      'https://firebasestorage.googleapis.com/v0/b/bucket/o/'
      'tenantProductImages%2Ft1%2Fp1%2Fabc123.png?alt=media&token=x',
    );

    test('reads the object back as something that can be framed', () async {
      final source = _photo(width: 40, height: 20);
      final fetched = await fetchProductImage(
        url,
        client: MockClient(
          (request) async => http.Response.bytes(source.bytes, 200),
        ),
      );

      expect(fetched.bytes, source.bytes);
      expect(fetched.type, TenantProductImageType.png);
      // Storage keeps the whole object path in one encoded segment; the file
      // is what comes after the last slash inside it.
      expect(fetched.fileName, 'abc123.png');
    });

    test('a refusal is reported rather than framed', () async {
      await expectLater(
        fetchProductImage(
          url,
          client: MockClient((request) async => http.Response('nope', 404)),
        ),
        throwsA(
          isA<TenantProductImageException>().having(
            (error) => error.code,
            'code',
            'image_unreachable',
          ),
        ),
      );
    });

    test('an unreachable server is reported rather than framed', () async {
      await expectLater(
        fetchProductImage(
          url,
          client: MockClient(
            (request) async => throw const SocketException(''),
          ),
        ),
        throwsA(
          isA<TenantProductImageException>().having(
            (error) => error.code,
            'code',
            'image_unreachable',
          ),
        ),
      );
    });

    test('an object that is not an image is refused', () async {
      await expectLater(
        fetchProductImage(
          url,
          client: MockClient(
            (request) async => http.Response('<html>not a photo</html>', 200),
          ),
        ),
        throwsA(isA<TenantProductImageException>()),
      );
    });
  });

  group('baking a framing', () {
    test('a filled framing is a square with nothing showing through', () async {
      final framed = await bakeProductFraming(
        source: _photo(width: 200, height: 100),
        framing: TenantProductFraming.filling(2),
      );

      final image = img.decodeImage(framed.bytes)!;
      expect(image.width, framedProductImageSide);
      expect(image.height, framedProductImageSide);
      // Opaque throughout, so it is encoded as the photograph it is.
      expect(framed.type, TenantProductImageType.jpeg);
      expect(framed.fileName, 'shot-framed.jpg');
    });

    test('zooming out leaves transparent ground and keeps it', () async {
      final framed = await bakeProductFraming(
        source: _photo(width: 200, height: 100),
        framing: const TenantProductFraming.whole(),
      );

      final image = img.decodeImage(framed.bytes)!;
      expect(image.width, framedProductImageSide);
      expect(image.height, framedProductImageSide);
      // A 2:1 photograph fitted whole leaves a band above and below it, and
      // that band has to survive the encoding or the card draws a white box.
      expect(framed.type, TenantProductImageType.png);
      expect(framed.fileName, 'shot-framed.png');
      expect(image.getPixel(framedProductImageSide ~/ 2, 2).a, 0);
      expect(
        image
            .getPixel(framedProductImageSide ~/ 2, framedProductImageSide ~/ 2)
            .a,
        255,
      );
    });

    test('a quarter turn goes the same way the preview turns', () async {
      // **The direction is the whole of this test.** The editor tilts with
      // `Transform.rotate`, which is clockwise for a positive angle because y
      // runs downwards; the baker tilts with `copyRotate`. If those two
      // disagree, every tilted photograph comes back mirrored from the one
      // that was framed, and nothing else would catch it.
      final source = img.Image(width: 100, height: 100, numChannels: 3);
      img.fill(source, color: img.ColorRgb8(255, 255, 255));
      img.fillRect(
        source,
        x1: 0,
        y1: 0,
        x2: 49,
        y2: 49,
        color: img.ColorRgb8(230, 20, 20),
      );

      final framed = await bakeProductFraming(
        source: TenantProductImageCandidate(
          bytes: Uint8List.fromList(img.encodePng(source)),
          fileName: 'corner.png',
        ),
        framing: TenantProductFraming.filling(1, rotation: math.pi / 2),
      );

      final image = img.decodeImage(framed.bytes)!;
      const quarter = framedProductImageSide ~/ 4;
      // Clockwise: the red corner starts top-left and lands top-right.
      final landed = image.getPixel(quarter * 3, quarter);
      final vacated = image.getPixel(quarter, quarter);

      expect(landed.r, greaterThan(150), reason: 'red should land top-right');
      expect(landed.g, lessThan(120));
      expect(vacated.r, greaterThan(150), reason: 'top-left should be white');
      expect(vacated.g, greaterThan(150));
    });

    test('the source is left exactly as it was', () async {
      final source = _photo(width: 120, height: 240);
      final before = Uint8List.fromList(source.bytes);

      await bakeProductFraming(
        source: source,
        framing: const TenantProductFraming(scale: 2, center: Offset(0.3, 0.7)),
      );

      expect(source.bytes, before);
    });

    test('refuses bytes that are not an image it can read', () async {
      await expectLater(
        bakeProductFraming(
          source: TenantProductImageCandidate(
            bytes: Uint8List.fromList('RIFF0000WEBP'.codeUnits),
            fileName: 'broken.webp',
          ),
          framing: const TenantProductFraming.whole(),
        ),
        throwsA(isA<TenantProductImageException>()),
      );
    });
  });
}
