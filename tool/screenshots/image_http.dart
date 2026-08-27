import 'dart:typed_data';
import 'dart:ui' as ui;

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
