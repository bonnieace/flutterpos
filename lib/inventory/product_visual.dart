/// The one way a product's photograph is drawn, wherever it appears.
///
/// **It fills its box, as the chosen-image preview always has.** The catalog
/// form's well draws bytes picked off the phone with `BoxFit.cover` -
/// `_ProductImagePreview` in `catalog_management_panel.dart` - so that is what
/// a photograph looks like at the moment someone chooses it: edge to edge, the
/// subject at the size they framed it. Anything else means the picture changes
/// shape the instant it is saved, which is the one thing a preview must not
/// do. `cover` here is what keeps the two identical.
///
/// A brief attempt at `contain` on 2026-09-04 is what proved it. Nothing was
/// cropped, but a cut-out landed small in the middle of a wide field of card
/// tint on every surface at once, and a till of postage stamps is worse than a
/// till of photographs with their corners trimmed. The cropping that prompted
/// it was a **box shape** problem rather than a fit problem: the till's picture
/// band was twice as wide as it was tall, so a bottle lost its cap and its
/// base. That band is near-square now - `_productThumbnailBandHeight` in
/// `checkout_cart_panel.dart` - which is the shape a product photograph is
/// taken in, and `cover` costs it very little.
///
/// **The decode is sized to the box.** A photograph may be five megabytes; at
/// full resolution it decodes to something like forty in memory, and two of
/// them evict Flutter's entire image cache. `ResizeImage` decodes at the extent
/// this widget was actually measured at, so a grid of twenty products costs
/// about what twenty thumbnails cost. See [TenantProductVisual] on what is and
/// is not cached between runs.
library;

import 'package:flutter/material.dart';

import '../tenancy/tenant_catalog.dart';
import '../ui/records.dart';
import '../ui/tokens.dart';
import 'product_image_drafts.dart';
import 'product_image_provider.dart';

typedef TenantProductVisualBuilder = Widget Function(TenantProduct product);

/// A product photograph with a stable initials fallback.
///
/// The parent measures the square. This widget owns only the visual treatment,
/// so cards, table rows, and the product detail route can use different extents
/// without duplicating loading and error behavior.
///
/// **What is cached and what is not.** `NetworkImage` is value-equal on its
/// URL, so every surface asking for one product asks for the same key and
/// Flutter's `ImageCache` answers all of them from memory - a rebuild does not
/// refetch, and the till and the catalog share one copy. That cache is
/// **memory only and dies with the process**: there is no store on disk, so a
/// cold start downloads every photograph again. Recorded here rather than
/// fixed here, because a durable cache is a store with an eviction policy and
/// a size budget rather than a line in a widget.
final class TenantProductVisual extends StatelessWidget {
  const TenantProductVisual({
    super.key,
    required this.product,
    this.semanticLabel,
    this.imageProvider,
  });

  final TenantProduct product;
  final String? semanticLabel;

  /// Supplied by a test, or by a form previewing bytes that are not uploaded
  /// yet. A provider given here is drawn as it is - the caller has already
  /// decided its size.
  final ImageProvider<Object>? imageProvider;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(tokens.radius.md),
      child: DecoratedBox(
        decoration: BoxDecoration(color: tokens.colors.surface.overlay),
        // **The box is measured before the decode is asked for**, which is the
        // whole point of sizing the decode: a `LayoutBuilder` is the only place
        // that knows how large this instance actually is.
        child: LayoutBuilder(
          builder: (context, constraints) => _picture(context, constraints),
        ),
      ),
    );
  }

  Widget _picture(BuildContext context, BoxConstraints constraints) {
    final url = product.imageUrl;
    final fallback = _ProductInitials(product: product, box: constraints);
    // **A photograph this device is still holding wins over the stored URL.**
    // It is the newer of the two by definition - it was chosen after whatever
    // is on the server - and until 2026-09-04 a picture could not be seen at
    // all until it had finished uploading. An explicit `imageProvider` still
    // wins over both: that is a caller previewing bytes it already has.
    final staged = imageProvider != null
        ? null
        : TenantProductImageDraftScope.bytesOf(
            context,
            tenantId: product.tenantId,
            productId: product.id,
          );
    if (imageProvider == null && staged == null && url == null) return fallback;
    final provider =
        imageProvider ??
        (staged != null
            ? MemoryImage(staged)
            : _sized(context, url!, constraints));
    return Image(
      image: provider,
      // The fit the picker's preview uses, so saving a product does not change
      // how its photograph is framed. See the library note.
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      semanticLabel: semanticLabel ?? '${product.name} product image',
      // **The bare ground rather than the initials, and deliberately not a
      // skeleton.** Flashing the fallback while the bytes are in flight says
      // "this product has no picture" and then contradicts itself. A
      // `SkeletonBlock` was the obvious alternative and is the wrong one
      // here: its sweep runs on a repeating controller, so a single picture
      // still in flight holds the frame scheduler open and every
      // `pumpAndSettle` in the app's tests and in the screenshot harness
      // waits on it for ever. This is the ground the `DecoratedBox` above
      // already paints, uncovered for the moment the fetch takes.
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : const SizedBox.expand(),
      // A product whose picture cannot be fetched still has to be sellable,
      // so a failed load falls back rather than throwing a broken glyph into
      // the middle of the till.
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }

  /// The network image, decoded at the size it is drawn at.
  ///
  /// **Rounded to the box rather than to the exact pixel**, because the cache
  /// key includes the dimensions: a widget measured at 131.7 on one screen and
  /// 132.0 on another would hold two decodes of one photograph.
  ///
  /// The target is the box's *longest* side, which under `cover` is the
  /// sampling floor for every photograph at least as tall as its box is wide -
  /// which is to say every ordinary product photograph, square or portrait. A
  /// panoramic one is sampled a little under its drawn height and softens.
  /// That is the price of sizing a decode before decoding, and it is a great
  /// deal cheaper than the forty megabytes a full-resolution decode costs.
  ImageProvider<Object> _sized(
    BuildContext context,
    Uri url,
    BoxConstraints constraints,
  ) {
    // **The device's own copy first since 2026-09-05.** `NetworkImage` holds a
    // photograph in memory and only in memory, so every cold start downloaded
    // the whole catalog again and a shop with no signal drew initials over
    // products it was holding offline in full. See `product_image_cache.dart`;
    // with no store installed this is the same plain GET it always was.
    final source = TenantCachedNetworkImage(
      url,
      cache: TenantImageCacheScope.of(context),
    );
    final side = constraints.biggest.longestSide;
    if (!side.isFinite || side <= 0) return source;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return ResizeImage(
      source,
      width: (side * ratio / 32).ceil() * 32,
      policy: ResizeImagePolicy.fit,
    );
  }
}

final class _ProductInitials extends StatelessWidget {
  const _ProductInitials({required this.product, required this.box});

  final TenantProduct product;
  final BoxConstraints box;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    // A band four times the height of a row's square holds a heading rather
    // than a card title, so the initials grow with the space they are standing
    // in. `title.lg` is §2.2's section role and the largest that is not a
    // screen title.
    final roomy = box.hasBoundedHeight && box.maxHeight >= _headingFloor;
    return ColoredBox(
      color: tokens.colors.surface.overlay,
      child: Center(
        child: Text(
          TenantInitialsAvatar.initialsOf(product.name),
          key: ValueKey('product-image-fallback-${product.id}'),
          style:
              (roomy
                      ? tokens.typography.titleLarge
                      : tokens.typography.titleMedium)
                  .copyWith(color: tokens.colors.text.secondary),
        ),
      ),
    );
  }

  /// Above this the stand-in takes the section role rather than the card one.
  ///
  /// Named rather than tokenised on the grounds `EmptyState.markSize` is:
  /// `design.md` states no such value. 80 is under the till's picture band and
  /// over a cart line's square, which are the two extents this widget is drawn
  /// at.
  static const double _headingFloor = 80;
}
