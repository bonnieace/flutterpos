import 'package:flutter/material.dart';

import '../tenancy/tenant_catalog.dart';
import '../ui/records.dart';
import '../ui/tokens.dart';

typedef TenantProductVisualBuilder = Widget Function(TenantProduct product);

/// A product photograph with a stable initials fallback.
///
/// The parent measures the square. This widget owns only the visual treatment,
/// so cards, table rows, and the product detail route can use different extents
/// without duplicating loading and error behavior.
final class TenantProductVisual extends StatelessWidget {
  const TenantProductVisual({
    super.key,
    required this.product,
    this.semanticLabel,
    this.imageProvider,
  });

  final TenantProduct product;
  final String? semanticLabel;
  final ImageProvider<Object>? imageProvider;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final fallback = _ProductInitials(product: product);
    final provider =
        imageProvider ??
        (product.imageUrl == null
            ? null
            : NetworkImage(product.imageUrl.toString()));
    final image = provider == null
        ? fallback
        : Image(
            image: provider,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            semanticLabel: semanticLabel ?? '${product.name} product image',
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : fallback,
            errorBuilder: (context, error, stackTrace) => fallback,
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(tokens.radius.md),
      child: DecoratedBox(
        decoration: BoxDecoration(color: tokens.colors.surface.overlay),
        child: image,
      ),
    );
  }
}

final class _ProductInitials extends StatelessWidget {
  const _ProductInitials({required this.product});

  final TenantProduct product;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return ColoredBox(
      color: tokens.colors.surface.overlay,
      child: Center(
        child: Text(
          TenantInitialsAvatar.initialsOf(product.name),
          key: ValueKey('product-image-fallback-${product.id}'),
          style: tokens.typography.titleMedium.copyWith(
            color: tokens.colors.text.secondary,
          ),
        ),
      ),
    );
  }
}
