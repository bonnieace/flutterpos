/// One supplier, as the directory draws it, and the pieces the record route
/// shares with it.
///
/// **Built the way the stock count card is**, not from `RecordList`. The whole
/// card is the way into the record; the overflow menu the sale cards use holds
/// *View* and *Receive delivery* first, then the corrections a person makes
/// less often - *Edit*, *Mark inactive*; and the one fact the directory
/// is scanned for, when stock last came in, has a recessed well of its own
/// rather than a key-value row among equals.
library;

import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../ui/press.dart';
import '../ui/records.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'supplier.dart';

/// One correction offered from a supplier's overflow menu.
@immutable
final class SupplierMenuAction {
  const SupplierMenuAction({
    required this.label,
    required this.icon,
    required this.itemKey,
    required this.onSelected,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final Key itemKey;
  final VoidCallback onSelected;
  final bool destructive;
}

/// One supplier in the directory.
final class TenantSupplierCard extends StatelessWidget {
  const TenantSupplierCard({
    super.key,
    required this.supplier,
    required this.lastDeliveryLabel,
    required this.onOpen,
    required this.actions,
  });

  final TenantSupplier supplier;

  /// When stock last came in from this supplier, already in the shop's own day.
  final String lastDeliveryLabel;

  final VoidCallback onOpen;

  /// Empty on a read-only build, which then draws no menu at all.
  final List<SupplierMenuAction> actions;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final radius = BorderRadius.circular(tokens.radius.md);
    final target = tokens.density.minimumTapTarget;
    // **The menu sits beside the card's press surface, not inside it.** Inside,
    // holding the menu would also press the card - the card's recogniser
    // reports its tap-down once the press timeout passes, before the arena
    // settles - and a screen reader would meet one button nested in another.
    // So the menu is stacked over the corner and the heading row leaves it
    // room.
    final menuInset = tokens.spacing.s4;
    final menuRoom = target.width + menuInset - tokens.spacing.s16;
    final contact = supplier.phone ?? supplier.email;
    return Stack(
      children: <Widget>[
        PressSurface(
          key: ValueKey('supplier-view-${supplier.id}'),
          borderRadius: radius,
          fillWidth: true,
          onPressed: onOpen,
          semanticLabel: 'Open ${supplier.name}',
          // Washes, not fills: see `TenantStockTakeCard`, whose note this is.
          hoverOverlay: tokens.colors.action.primary.hoverWash(),
          pressedOverlay: tokens.colors.action.primary.pressedWash(),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.colors.surface.raised,
              border: Border.all(color: tokens.colors.surface.cardEdge),
              borderRadius: radius,
            ),
            child: Padding(
              padding: EdgeInsets.all(tokens.spacing.s16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      SupplierMonogram(name: supplier.name),
                      SizedBox(width: tokens.spacing.s12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              supplier.name,
                              key: ValueKey('supplier-name-${supplier.id}'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: tokens.typography.titleMedium.copyWith(
                                color: tokens.colors.text.primary,
                              ),
                            ),
                            SizedBox(height: tokens.spacing.s4),
                            Text(
                              contact ?? 'No phone or email recorded',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tokens.typography.caption.copyWith(
                                color: tokens.colors.text.tertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // **Only the exception wears a badge.** An active
                      // supplier is the ordinary case, and a list where every
                      // card is badged has no signal in it.
                      if (!supplier.active) ...<Widget>[
                        SizedBox(width: tokens.spacing.s8),
                        StatusBadge(
                          key: ValueKey(
                            'supplier-inactive-badge-${supplier.id}',
                          ),
                          status: AppStatus.neutral,
                          label: 'Inactive',
                        ),
                      ],
                      if (actions.isNotEmpty)
                        SizedBox(width: menuRoom)
                      else ...<Widget>[
                        SizedBox(width: tokens.spacing.s4),
                        Icon(
                          Icons.chevron_right,
                          size: AppButton.iconSize,
                          color: tokens.colors.text.tertiary,
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: tokens.spacing.s12),
                  SupplierLastDeliveryWell(
                    label: lastDeliveryLabel,
                    delivered: supplier.lastDeliveryAt != null,
                    valueKey: ValueKey('supplier-last-delivery-${supplier.id}'),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (actions.isNotEmpty)
          PositionedDirectional(
            top:
                tokens.spacing.s16 +
                SupplierMonogram.extent(tokens) / 2 -
                target.height / 2,
            end: menuInset,
            child: SupplierMenu(
              menuKey: ValueKey('supplier-actions-${supplier.id}'),
              tooltip: 'Actions for ${supplier.name}',
              actions: actions,
            ),
          ),
      ],
    );
  }
}

/// A supplier's initials on the tile the catalog draws for a product without a
/// photograph: `surface.overlay`, `title.md`, `text.secondary`.
final class SupplierMonogram extends StatelessWidget {
  const SupplierMonogram({super.key, required this.name});

  final String name;

  /// The tile's side: §9's target, so a row of these lines up with the menu
  /// beside it.
  static double extent(AppTokens tokens) => tokens.spacing.s48;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: extent(tokens),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.colors.surface.overlay,
            borderRadius: BorderRadius.circular(tokens.radius.md),
          ),
          child: Center(
            child: Text(
              TenantInitialsAvatar.initialsOf(name),
              style: tokens.typography.titleMedium.copyWith(
                color: tokens.colors.text.secondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// When stock last came in, in the recessed well the stock count card keeps its
/// difference figures in.
final class SupplierLastDeliveryWell extends StatelessWidget {
  const SupplierLastDeliveryWell({
    super.key,
    required this.label,
    required this.delivered,
    required this.valueKey,
  });

  final String label;

  /// False for *None yet*, which is words rather than a date and is set in the
  /// interface face rather than the figures' one.
  final bool delivered;

  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.colors.surface.sunken,
        borderRadius: BorderRadius.circular(tokens.radius.md),
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.s12),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.local_shipping_outlined,
              size: AppButton.iconSize,
              color: delivered
                  ? tokens.colors.action.primary.container
                  : tokens.colors.text.tertiary,
            ),
            SizedBox(width: tokens.spacing.s8),
            Expanded(
              child: Text(
                'Last delivery',
                style: tokens.typography.labelMedium.copyWith(
                  color: tokens.colors.text.secondary,
                ),
              ),
            ),
            SizedBox(width: tokens.spacing.s8),
            Text(
              label,
              key: valueKey,
              style: delivered
                  ? tokens.typography.numericBody.copyWith(
                      color: tokens.colors.text.primary,
                    )
                  : tokens.typography.bodyMedium.copyWith(
                      color: tokens.colors.text.tertiary,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The overflow menu a supplier's corrections sit behind.
///
/// **Drawn like the sale card's**, for the reason that one records: depth here
/// is a surface step and never a shadow, and a menu at `surface.overlay` over a
/// `surface.raised` card has no findable edge without the `borderStrong`
/// hairline.
final class SupplierMenu extends StatelessWidget {
  const SupplierMenu({
    super.key,
    required this.menuKey,
    required this.tooltip,
    required this.actions,
  });

  final Key menuKey;
  final String tooltip;
  final List<SupplierMenuAction> actions;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final target = tokens.density.minimumTapTarget;
    return PopupMenuButton<int>(
      key: menuKey,
      tooltip: tooltip,
      icon: Icon(
        Icons.more_vert,
        size: tokens.spacing.s20,
        color: tokens.colors.text.secondary,
      ),
      iconSize: tokens.spacing.s20,
      color: tokens.colors.surface.overlay,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius.md),
        side: BorderSide(color: tokens.colors.surface.borderStrong),
      ),
      constraints: BoxConstraints(minHeight: target.height),
      onSelected: (index) => actions[index].onSelected(),
      itemBuilder: (context) => <PopupMenuEntry<int>>[
        for (final (index, action) in actions.indexed)
          PopupMenuItem<int>(
            key: action.itemKey,
            value: index,
            height: target.height,
            child: Row(
              children: <Widget>[
                Icon(
                  action.icon,
                  size: tokens.spacing.s20,
                  color: action.destructive
                      ? tokens.colors.action.destructive.label
                      : tokens.colors.text.secondary,
                ),
                SizedBox(width: tokens.spacing.s12),
                Expanded(
                  child: Text(
                    action.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.typography.labelLarge.copyWith(
                      color: action.destructive
                          ? tokens.colors.action.destructive.label
                          : tokens.colors.text.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
