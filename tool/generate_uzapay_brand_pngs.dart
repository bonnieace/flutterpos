// Converts the exact UzaPay landing assets to PNG for native icon generators.
// Sources: github.com/bonnieace/uzapay-landing/assets/brand
import 'dart:io';

import 'package:image/image.dart' as image;

void main() {
  image.Image? mark;
  for (final name in <String>['uzapay-app-icon', 'uzapay-mark']) {
    final source = File('assets/brand/$name.webp');
    final decoded = image.decodeWebP(source.readAsBytesSync());
    if (decoded == null) throw StateError('Could not decode ${source.path}');
    File('images/$name.png').writeAsBytesSync(image.encodePng(decoded));
    if (name == 'uzapay-mark') mark = decoded;
  }

  // Android 12 masks its splash icon to a 768px circle inside 1152px. The
  // artwork's diagonal fits inside that circle, including its pointed tips.
  final source = mark!;
  final scaled = image.copyResize(source, height: 540);
  final canvas = image.Image(width: 1152, height: 1152, numChannels: 4);
  image.compositeImage(
    canvas,
    scaled,
    dstX: (canvas.width - scaled.width) ~/ 2,
    dstY: (canvas.height - scaled.height) ~/ 2,
  );
  File('images/uzapay-android12.png').writeAsBytesSync(image.encodePng(canvas));
}
