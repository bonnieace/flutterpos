/// Where a photograph sits inside the square a product image is stored as, and
/// how that placement is baked into bytes.
///
/// **Asked for on 2026-09-04.** The catalog could already cut a photograph's
/// background out and could not move it a single pixel, so a subject that was
/// off to one side, or too small in its frame, or too large for it, had no
/// remedy but taking the photograph again. This is the missing half: drag to
/// place, pinch to zoom, and - the part that has no equivalent in most crop
/// tools - zoom *out*, so a subject can sit small on the card's own ground
/// rather than being pushed to the edges of it.
///
/// **The placement is baked into the uploaded bytes rather than stored beside
/// them.** The alternative - keeping a scale and an offset on the product and
/// applying them at draw time - cannot work here, because the surfaces that
/// draw a product are not one shape: the till's band, a cart line's square and
/// a catalog row's square would each need their own answer, and a person
/// framing a photograph would be framing none of them in particular. One
/// square image, framed once, is a thing they can actually see while they make
/// it. It also costs nothing at read time, which matters on a phone holding
/// twenty of them.
///
/// **The canvas is square** because that is the shape every surface but one
/// draws, and the shape the form's own well previews. The till's picture band
/// is slightly wider than tall and will still trim a little off the top and
/// bottom of a square; leaving room for that is what zooming out is for.
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect, Size;
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import 'product_image_store.dart';
import '../observability/app_telemetry.dart';

/// The side of the square that framing produces, in pixels.
///
/// Named rather than tokenised because it is a property of the stored asset
/// rather than of any layout: no screen draws 1024 of anything. It is the
/// largest extent any surface asks for - the form's own well is capped at 350
/// logical pixels, which is 1050 on a three-times screen - rounded to a power
/// of two, and it encodes to well under [maximumTenantProductImageBytes] for
/// any photograph.
const int framedProductImageSide = 1024;

/// The largest source the baker will work from, per side.
///
/// A five-megabyte JPEG can be twenty megapixels, which decodes to eighty
/// megabytes of pixels; two of those in one isolate is how a phone with two
/// gigabytes of RAM kills the app. Nothing above this is ever visible in a
/// [framedProductImageSide] square, so the detail thrown away here is detail
/// that could not have been kept.
const int _sourceCeiling = 2048;

/// How far a photograph may be zoomed, as a multiple of the scale at which the
/// whole of it just fits the square.
///
/// The floor is not 1: **zooming out past "the whole photograph" is a stated
/// requirement**, and it is what puts a small subject on open ground. The
/// ceiling is where an ordinary phone photograph starts to show its pixels in
/// a 1024 square.
const double minimumFramingScale = 0.25;
const double maximumFramingScale = 6;

/// A photograph's placement inside the unit square.
///
/// Both fields are in canvas fractions rather than pixels, so one framing
/// describes the same picture whether it is being previewed at 350 logical
/// pixels or baked at 1024 real ones. That is the whole reason this is a value
/// rather than a rectangle: the preview and the baker must not be able to
/// disagree, and they cannot disagree about a fraction.
final class TenantProductFraming {
  const TenantProductFraming({
    this.scale = 1,
    this.center = const Offset(0.5, 0.5),
    this.rotation = 0,
  });

  /// The whole photograph, centred, with ground around it on its short axis.
  ///
  /// This is `BoxFit.contain` expressed as a framing, and it is what the
  /// *Whole photo* preset gives.
  const TenantProductFraming.whole({double rotation = 0})
    : this(rotation: rotation);

  /// The photograph filling the square, centred, with its long axis trimmed.
  ///
  /// This is `BoxFit.cover` expressed as a framing. **It is also the framing
  /// the editor opens at**, which is deliberate: it is exactly what every
  /// surface already draws, so opening the editor and pressing *Use this
  /// framing* changes nothing. An editor whose initial state is not the
  /// current state is an editor that edits by being opened.
  ///
  /// **A tilted photograph has to be bigger to fill the same square**, which
  /// is why [rotation] is taken here rather than assumed to be nothing. A
  /// rectangle turned by θ contains the unit square only once each of its
  /// sides reaches `|cos θ| + |sin θ|` - half again at 45° - and *Fill the
  /// frame* is precisely the button somebody presses after tilting.
  TenantProductFraming.filling(double aspect, {double rotation = 0})
    : this(scale: coverScaleFor(aspect, rotation), rotation: rotation);

  /// A multiple of the scale at which the whole photograph just fits.
  final double scale;

  /// Where the photograph's middle sits, in canvas fractions.
  final Offset center;

  /// The tilt, in radians, clockwise, about the photograph's own middle.
  ///
  /// Rotating about the middle rather than about the canvas is what lets this
  /// be one more field instead of a second placement system: [center] and
  /// [placementFor] are untouched by it, because a rotation about a
  /// rectangle's own centre moves the centre nowhere.
  final double rotation;

  /// The scale at which a photograph of [aspect] tilted by [rotation] just
  /// covers the square.
  static double coverScaleFor(double aspect, double rotation) {
    final size = _wholeSize(aspect);
    final reach = rotation.abs() < _flat
        ? 1.0
        : math.cos(rotation).abs() + math.sin(rotation).abs();
    return reach / math.min(size.width, size.height);
  }

  // Compared by value so a drag that ends where it started rebuilds nothing.
  @override
  bool operator ==(Object other) =>
      other is TenantProductFraming &&
      other.scale == scale &&
      other.center == center &&
      other.rotation == rotation;

  @override
  int get hashCode => Object.hash(scale, center, rotation);

  /// The photograph's rectangle in canvas fractions.
  Rect placementFor(double aspect) {
    final size = _wholeSize(aspect);
    return Rect.fromCenter(
      center: center,
      width: size.width * scale,
      height: size.height * scale,
    );
  }

  /// The same framing with impossible states removed.
  ///
  /// **One rule: the middle of the photograph stays inside the square.** At
  /// most half of it can travel off any edge, and that is true at every zoom.
  ///
  /// The first version had two rules instead, chosen per axis by whether the
  /// photograph was bigger than the canvas: bigger meant it could not be
  /// dragged far enough to show ground, smaller meant it could not leave the
  /// frame at all. Both are defensible and together they were unusable,
  /// because **the editor opens at the exact scale where the first rule
  /// permits nothing**. Filling the frame makes the photograph precisely the
  /// canvas's size on its short axis, the legal range there collapses to a
  /// single point, and a squarish photograph was frozen on both axes at once.
  /// Zooming in *or* out widened the range from zero, so it came alive after a
  /// pinch and was dead on arrival - which is exactly how it was reported.
  ///
  /// A rule whose freedom varies with zoom cannot feel like anything, because
  /// the same drag does something different every time. This one gives the
  /// same room at 25% as at 600%, and lets a subject be pushed deliberately
  /// off an edge, which the old rule forbade in the name of an accident nobody
  /// was having.
  TenantProductFraming clampedTo(double aspect) => TenantProductFraming(
    scale: scale.clamp(minimumFramingScale, maximumFramingScale),
    center: Offset(center.dx.clamp(0, 1), center.dy.clamp(0, 1)),
    // Wrapped rather than bounded: a tilt has no end a person can hit, and an
    // angle that grew without limit would eventually lose its precision in
    // the low bits and start to judder.
    rotation: _wrapped(rotation),
  );

  /// The same angle, expressed within half a turn either way.
  static double _wrapped(double angle) {
    const turn = 2 * math.pi;
    final within = angle.remainder(turn);
    if (within > math.pi) return within - turn;
    if (within <= -math.pi) return within + turn;
    return within;
  }

  /// Below this a tilt is treated as no tilt at all.
  ///
  /// A hundredth of a radian is a little over half a degree - under what a
  /// hand can hold steady and under what a 1024-pixel square can show.
  static const double _flat = 0.01;

  /// The largest box of this aspect that fits the unit square.
  static Size _wholeSize(double aspect) =>
      aspect >= 1 ? Size(1, 1 / aspect) : Size(aspect, 1);
}

/// Fetches a photograph the catalog has already saved, so it can be framed
/// without being chosen again.
typedef TenantProductImageFetcher =
    Future<TenantProductImageCandidate> Function(Uri url);

/// How long a saved photograph has to come back before the form gives up.
///
/// Long enough for a slow shop connection and a couple of megabytes, short
/// enough that a dead network is reported rather than waited on.
const Duration _fetchTimeout = Duration(seconds: 30);

/// Downloads a saved photograph as bytes that can be framed.
///
/// **A plain GET rather than the Storage SDK**, because it is the same request
/// `TenantProductVisual` already makes to draw the picture - the download URL
/// carries its own token - and going through `refFromURL` instead would refuse
/// the legacy external images `TenantProductImageStore.removeOwned` already
/// has a branch for.
///
/// The bytes go through [TenantProductImageCandidate], so a saved object that
/// is somehow not an image, or is larger than the catalog allows, is refused
/// here rather than halfway through a bake.
Future<TenantProductImageCandidate> fetchProductImage(
  Uri url, {
  http.Client? client,
}) async {
  final http.Response response;
  try {
    response = await (client?.get(url) ?? http.get(url)).timeout(_fetchTimeout);
  } on TimeoutException {
    throw const TenantProductImageException('image_unreachable');
  } catch (error, stackTrace) {
    AppTelemetry.captureHandled(
      error,
      stackTrace,
      boundary: 'inventory.image_fetch',
    );
    throw const TenantProductImageException('image_unreachable');
  }
  if (response.statusCode != 200) {
    throw const TenantProductImageException('image_unreachable');
  }
  return TenantProductImageCandidate(
    bytes: response.bodyBytes,
    fileName: savedImageFileName(url),
  );
}

/// A name for a photograph that arrived as a URL.
///
/// Storage puts the whole object path in one encoded path segment, which `Uri`
/// hands back decoded and still full of slashes, so the last of those is what
/// a person would call the file.
String savedImageFileName(Uri url) {
  final segment = url.pathSegments.isEmpty ? '' : url.pathSegments.last;
  final name = segment.substring(segment.lastIndexOf('/') + 1).trim();
  return name.isEmpty ? 'saved-image.jpg' : name;
}

/// Renames a photograph to the framing that replaced it.
///
/// The extension follows the bytes for the reason `cutOutFileName` gives: a
/// name saying `.jpg` over PNG bytes is a small lie discovered by somebody
/// debugging something else.
String framedFileName(String original, {required bool png}) {
  final extension = png ? 'png' : 'jpg';
  final trimmed = original.trim();
  if (trimmed.isEmpty) return 'framed.$extension';
  final dot = trimmed.lastIndexOf('.');
  final stem = dot <= 0 ? trimmed : trimmed.substring(0, dot);
  return '$stem-framed.$extension';
}

/// The longest side a chosen picture is kept at, before anything else is done
/// to it.
///
/// **What this is for.** A phone camera produces a four-thousand-pixel JPEG of
/// three to five megabytes. Nothing in this app draws a picture larger than a
/// 350-logical-pixel well - 1050 on a three-times screen - so every one of
/// those megabytes is paid twice: once by the shopkeeper uploading it on a
/// shop connection, and again by every till that downloads it to draw a
/// forty-pixel thumbnail.
///
/// **1600 rather than [framedProductImageSide]'s 1024**, because this is not a
/// framing: the whole photograph is kept, at its own shape, so *Position and
/// zoom* still has something to zoom out of. It is comfortably more than a
/// 1024 square needs from any crop of it.
const int storedTenantImageSide = 1600;

/// The size under which a picture is left exactly as it was chosen.
///
/// Re-encoding is lossy, and re-encoding a picture that is already small buys
/// nothing for the quality it spends.
const int _storedTenantImageBytes = 512 * 1024;

/// [source] re-encoded no larger than [storedTenantImageSide] on its longest
/// side, or [source] itself where it is already small enough.
///
/// **The one place bytes are bounded, and it runs before anything is staged or
/// uploaded.** Everything downstream is then working on a picture of a known
/// order of magnitude: the draft box on the phone, Storage, and every device
/// that draws it later.
///
/// **Never larger than what it was given.** A modest PNG re-encoded as PNG can
/// come back bigger; when it does, the original is kept. The check is on bytes
/// because bytes are the whole point.
///
/// Transparency survives, for the reason `_encode` gives: a cut-out is a
/// picture whose background is meant to show through.
Future<TenantProductImageCandidate> normalizeTenantImage(
  TenantProductImageCandidate source,
) async {
  if (await _isAlreadySmall(source.bytes)) return source;
  final decoded = await _decode(source.bytes, ceiling: storedTenantImageSide);
  final width = decoded.width;
  final height = decoded.height;
  final Uint8List pixels;
  try {
    final data = await decoded.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) {
      throw const TenantProductImageException('unsupported_image_type');
    }
    pixels = data.buffer.asUint8List();
  } finally {
    decoded.dispose();
  }
  // Only bytes cross into the isolate, as the baker's note explains.
  final encoded = await Isolate.run(
    () => _encode(pixels, width: width, height: height),
  );
  if (encoded.length >= source.bytes.length) return source;
  return TenantProductImageCandidate(
    bytes: encoded,
    fileName: storedImageFileName(source.fileName, png: _isPng(encoded)),
  );
}

/// Whether [bytes] are already within both bounds, read from the header alone.
///
/// The dimensions are checked as well as the length because the two fail in
/// different ways: a heavily compressed twelve-megapixel photograph is small on
/// the wire and enormous once decoded, which is the cost every surface drawing
/// it pays in memory.
Future<bool> _isAlreadySmall(Uint8List bytes) async {
  if (bytes.length > _storedTenantImageBytes) return false;
  final ui.ImmutableBuffer buffer;
  final ui.ImageDescriptor descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
  } catch (_) {
    throw const TenantProductImageException('unsupported_image_type');
  }
  final longest = math.max(descriptor.width, descriptor.height);
  descriptor.dispose();
  buffer.dispose();
  return longest <= storedTenantImageSide;
}

/// A name for a picture that was re-encoded smaller, keeping its own stem.
///
/// The extension follows the bytes for the reason [framedFileName] gives.
String storedImageFileName(String original, {required bool png}) {
  final extension = png ? 'png' : 'jpg';
  final trimmed = original.trim();
  if (trimmed.isEmpty) return 'image.$extension';
  final dot = trimmed.lastIndexOf('.');
  final stem = dot <= 0 ? trimmed : trimmed.substring(0, dot);
  return '$stem.$extension';
}

/// The seam the editor presses, so a widget test never starts an isolate.
typedef TenantProductFramingBaker =
    Future<TenantProductImageCandidate> Function({
      required TenantProductImageCandidate source,
      required TenantProductFraming framing,
    });

/// Redraws [source] as a square with [framing] applied.
///
/// **Skia does the pixels; Dart only encodes the result.** This was pure Dart
/// once - `package:image` decoded the JPEG, resampled it and rotated it - and
/// it was measured on 2026-09-04 at about two seconds for a twelve-megapixel
/// photograph on a desktop, three and a half if it was tilted, and several
/// times that on the handset this ships to. The breakdown was decode 971ms,
/// downscale 527ms, rotate 1385ms, everything else under 200. None of it was
/// the isolate, which spawns in six.
///
/// So the work moved to the engine that was already drawing the preview one
/// screen away:
///
/// - **Decoding goes through `ui.ImageDescriptor`**, which is Skia's codec in
///   C++, and `instantiateCodec` takes the target size, so the twelve
///   megapixels are never materialised at all - the decode and the downscale
///   become one native step instead of 1.5 seconds of Dart.
/// - **Placing goes through a `Canvas`**, so the translate, the tilt and the
///   resample are one composited draw. It is also, being literally the same
///   engine and the same geometry as the preview's `Positioned` and
///   `Transform.rotate`, the strongest guarantee available that what was
///   framed is what is saved.
/// - **Only the encode stays in Dart**, on 1024 squared rather than on twelve
///   megapixels, in the isolate where it cannot touch a frame.
///
/// The one thing this gives up is `bakeOrientation`: Skia's codec applies a
/// JPEG's EXIF rotation itself, which is why `Image.memory` has always shown
/// these photographs the right way up. That is now a property of the decoder
/// rather than a step that could be forgotten.
///
/// Never mutates [source]: the person can press *Cancel* and still have the
/// photograph they chose, the rule background removal already follows.
Future<TenantProductImageCandidate> bakeProductFraming({
  required TenantProductImageCandidate source,
  required TenantProductFraming framing,
}) async {
  final decoded = await _decode(source.bytes);
  final Uint8List pixels;
  try {
    final aspect = decoded.width / decoded.height;
    pixels = await _draw(decoded, framing.clampedTo(aspect), aspect);
  } finally {
    decoded.dispose();
  }
  // Only bytes cross into the isolate. Sending anything the engine owns would
  // not survive the trip.
  final framed = await Isolate.run(() => _encode(pixels));
  return TenantProductImageCandidate(
    bytes: framed,
    fileName: framedFileName(source.fileName, png: _isPng(framed)),
  );
}

/// The photograph, decoded no larger than it can usefully be drawn.
///
/// [_sourceCeiling] is handed to the codec rather than applied afterwards, so
/// a twenty-megapixel JPEG never exists as pixels. The bound goes on whichever
/// side is longer *before* orientation is applied, because that is the space
/// the codec is working in; which of the two it lands on does not matter, only
/// that neither exceeds it.
Future<ui.Image> _decode(
  Uint8List bytes, {
  int ceiling = _sourceCeiling,
}) async {
  final ui.ImmutableBuffer buffer;
  final ui.ImageDescriptor descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
  } catch (_) {
    throw const TenantProductImageException('unsupported_image_type');
  }
  final landscape = descriptor.width >= descriptor.height;
  final longest = math.max(descriptor.width, descriptor.height);
  final codec = await descriptor.instantiateCodec(
    targetWidth: longest > ceiling && landscape ? ceiling : null,
    targetHeight: longest > ceiling && !landscape ? ceiling : null,
  );
  final frame = await codec.getNextFrame();
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  return frame.image;
}

/// The square, as raw RGBA.
///
/// The three transforms are applied in the order the preview applies them, and
/// about the same origin: the photograph's own middle, which is where
/// [TenantProductFraming.placementFor] centres its rectangle and where
/// `Transform.rotate` turns. Everything the photograph does not reach stays at
/// zero - fully transparent - so a zoomed-out subject picks up each surface's
/// own ground rather than a white box.
Future<Uint8List> _draw(
  ui.Image image,
  TenantProductFraming framing,
  double aspect,
) async {
  const side = framedProductImageSide;
  final placement = framing.placementFor(aspect);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(
    recorder,
    Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
  );
  canvas.translate(placement.center.dx * side, placement.center.dy * side);
  canvas.rotate(framing.rotation);
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    Rect.fromCenter(
      center: Offset.zero,
      width: placement.width * side,
      height: placement.height * side,
    ),
    ui.Paint()
      ..filterQuality = ui.FilterQuality.high
      ..isAntiAlias = true,
  );
  final picture = recorder.endRecording();
  final drawn = await picture.toImage(side, side);
  picture.dispose();
  final data = await drawn.toByteData(format: ui.ImageByteFormat.rawRgba);
  drawn.dispose();
  if (data == null) {
    throw const TenantProductImageException('unsupported_image_type');
  }
  return data.buffer.asUint8List();
}

/// PNG when anything shows through, JPEG when nothing does.
///
/// Transparency is not incidental here - a cut-out is the whole point of the
/// button next to this one, and zooming out creates transparency on purpose -
/// so it cannot be flattened away. But a fully covered square is a photograph,
/// and a photograph is several times smaller as JPEG, which is bandwidth every
/// till pays for on every read.
///
/// **Measured rather than reasoned**, unlike the version this replaces. Every
/// fourth byte of a raw RGBA square is an alpha, so this is one strided pass
/// over a megabyte - a few milliseconds - and it is exact for any combination
/// of tilt, zoom and cut-out, where the geometric argument needed a case for
/// each.
Uint8List _encode(
  Uint8List pixels, {
  int width = framedProductImageSide,
  int? height,
}) {
  var opaque = true;
  for (var alpha = 3; alpha < pixels.length; alpha += 4) {
    if (pixels[alpha] != 255) {
      opaque = false;
      break;
    }
  }
  final image = img.Image.fromBytes(
    width: width,
    height: height ?? width,
    bytes: pixels.buffer,
    numChannels: 4,
  );
  return opaque
      ? img.encodeJpg(image, quality: 88)
      : img.encodePng(image, level: 6);
}

bool _isPng(Uint8List bytes) =>
    bytes.length >= 4 &&
    bytes[0] == 0x89 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x4e &&
    bytes[3] == 0x47;
