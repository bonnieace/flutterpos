import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'image_http.dart';

void main() {
  test('the screenshot product fixture is an opaque rendered PNG', () async {
    final codec = await ui.instantiateImageCodec(
      await screenshotProductImage(),
    );
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 512);
    expect(frame.image.height, 512);
    final data = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    frame.image.dispose();
    codec.dispose();

    expect(data, isNotNull);
    final pixels = data!.buffer.asUint8List();
    expect(pixels[3], 255);
    expect(pixels[0] + pixels[1] + pixels[2], greaterThan(200));
  });
}
