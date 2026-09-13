/// Drawing a published picture from the disk cache, and filling that cache
/// from the network when it misses.
///
/// **A provider rather than a widget, because that is the seam Flutter's own
/// image cache keys on.** `ResizeImage` wraps it, the memory cache dedupes it
/// by URL exactly as it does `NetworkImage`, and every surface that already
/// asks for a photograph keeps asking in the same words. What changes is only
/// where the bytes come from: this device first, the network second.
///
/// **A miss on the store is never a failure.** No cache installed, a corrupt
/// box, a URL nobody has fetched yet - all of them fall through to the same
/// plain GET the app made before this existed. What the cache adds is that the
/// second time is free, and the second time works with the aeroplane mode on.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'product_image_cache.dart';
import 'product_image_store.dart';

/// How long a picture has to arrive before the draw gives up on it.
///
/// The same bound `fetchProductImage` uses, and for the same reason: a dead
/// network should report rather than hang a grid of tiles for ever.
const Duration _fetchTimeout = Duration(seconds: 30);

/// The bytes behind [url], from [cache] where it holds them and from the
/// network where it does not.
///
/// **Deliberately not `fetchProductImage`, and the difference matters.** That
/// one runs what it downloads through `TenantProductImageCandidate`, which
/// admits JPEG, PNG and WebP and refuses everything else - the right gate for
/// bytes on their way *to* Storage, and the wrong one for bytes on their way to
/// a print head. A logo published as a GIF draws perfectly well in the app and
/// would be silently dropped from the paper by that check, which is exactly the
/// shape of fault this exists to remove: nothing here is uploaded, and
/// `package:image` decodes a good deal more than three formats.
///
/// Null means *no bytes*, for any reason at all: the caller decides whether
/// that is worth a sentence.
Future<Uint8List?> loadTenantImageBytes(
  Uri url, {
  TenantImageCache? cache,
  Duration timeout = _fetchTimeout,
}) async {
  final held = await cache?.read(url);
  if (held != null) return held;
  try {
    final response = await http.get(url).timeout(timeout);
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;
    unawaited(cache?.write(url, response.bodyBytes) ?? Future<void>.value());
    return response.bodyBytes;
  } on Object {
    return null;
  }
}

/// One published picture, drawn from [cache] where it holds it.
@immutable
final class TenantCachedNetworkImage
    extends ImageProvider<TenantCachedNetworkImage> {
  const TenantCachedNetworkImage(this.url, {this.cache, this.scale = 1.0});

  final Uri url;

  /// Null where no store is installed, which draws from the network exactly as
  /// `NetworkImage` did.
  final TenantImageCache? cache;

  final double scale;

  @override
  Future<TenantCachedNetworkImage> obtainKey(
    ImageConfiguration configuration,
  ) => SynchronousFuture<TenantCachedNetworkImage>(this);

  @override
  ImageStreamCompleter loadImage(
    TenantCachedNetworkImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: key._load(decode),
    scale: key.scale,
    debugLabel: key.url.toString(),
    informationCollector: () => <DiagnosticsNode>[
      DiagnosticsProperty<ImageProvider<Object>>('Image provider', this),
      DiagnosticsProperty<Uri>('Image URL', key.url),
    ],
  );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await _bytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  Future<Uint8List> _bytes() async {
    final held = await cache?.read(url);
    if (held != null) return held;
    final http.Response response;
    try {
      response = await http.get(url).timeout(_fetchTimeout);
    } on Object {
      throw const TenantProductImageException('image_unreachable');
    }
    if (response.statusCode != 200) {
      throw const TenantProductImageException('image_unreachable');
    }
    final bytes = response.bodyBytes;
    // **Not awaited.** The picture is on screen the moment it has arrived; what
    // it costs to keep is the next start's problem, not this frame's.
    unawaited(cache?.write(url, bytes) ?? Future<void>.value());
    return bytes;
  }

  /// **Equal on the URL alone, deliberately.** Two surfaces asking for one
  /// product - the till's tile and the cart's line - must share Flutter's own
  /// decoded copy, and they would not if the store instance were part of the
  /// key. There is one store per process in any case.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TenantCachedNetworkImage &&
          other.url == url &&
          other.scale == scale;

  @override
  int get hashCode => Object.hash(url, scale);

  @override
  String toString() => 'TenantCachedNetworkImage("$url", scale: $scale)';
}

/// Makes the picture store reachable from wherever a product is drawn.
///
/// A plain [InheritedWidget] rather than the drafts' [InheritedNotifier]: the
/// store never changes for the life of the process, and nothing repaints
/// because it wrote something.
final class TenantImageCacheScope extends InheritedWidget {
  const TenantImageCacheScope({
    super.key,
    required this.cache,
    required super.child,
  });

  final TenantImageCache? cache;

  /// The installed store, or null - including where no scope is installed at
  /// all, which is every test that does not care about caching.
  static TenantImageCache? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<TenantImageCacheScope>()
      ?.cache;

  @override
  bool updateShouldNotify(TenantImageCacheScope oldWidget) =>
      !identical(cache, oldWidget.cache);
}
