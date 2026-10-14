/// One customer, as the directory draws them.
///
/// **The supplier card's shape**, because a customer is the same kind of
/// record - a name, how to reach them, one fact the list is scanned for - and
/// two cards for two directories that differed only in their words would be a
/// second design for one thing. The monogram and the overflow menu are the
/// supplier card's own, reused rather than copied.
library;

import 'package:flutter/material.dart';

import '../checkout/checkout_draft.dart';
import '../reports/analysis/report_prose.dart';
import '../suppliers/supplier_card.dart';
import '../ui/buttons.dart';
import '../ui/money_text.dart';
import '../ui/press.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'customer.dart';

/// When a customer last bought anything, in the shop's own day: `22 Sep`.
String customerLastBoughtLabel(TenantCustomer customer) {
  final at = customer.lastSaleAt;
  if (at == null) return 'Not yet';
  return reportShortDate(checkoutBusinessDate(at.toUtc()));
}

/// How a customer is reached, in one line: the masked number, and whether
/// their receipts go to it on WhatsApp or by email - said in words, never by a
/// colour.
String customerContactLine(TenantCustomer customer) {
  final masked = customer.maskedPhone;
  final whatsapp = masked != null && customer.whatsappOptIn;
  final email = customer.email != null && customer.emailOptIn;
  final receipts = whatsapp && email
      ? 'WhatsApp and email receipts'
      : whatsapp
      ? 'WhatsApp receipts'
      : email
      ? 'Email receipts'
      : null;
  final contact = masked ?? customer.email ?? 'No number recorded';
  return receipts == null ? contact : '$contact · $receipts';
}

/// `Owes 1,200 · since 22 Sep`: what a customer owes and how long for.
String customerOwingLabel(TenantCustomer customer) {
  final since = customer.owingSince;
  final owes = 'Owes ${moneyTextOfMinor(customer.owedMinor)}';
  if (since == null) return owes;
  return '$owes · since ${reportShortDate(checkoutBusinessDate(since.toUtc()))}';
}

/// `since 22 Sep`: how long a customer has owed, or null where they owe
/// nothing or the date was not recorded. The table's caption under the amount.
String? customerOwingSinceLabel(TenantCustomer customer) {
  final since = customer.owingSince;
  if (customer.owedMinor <= 0 || since == null) return null;
  return 'since ${reportShortDate(checkoutBusinessDate(since.toUtc()))}';
}

/// `1 point`, `40 points`.
String customerPointsLabel(int points) =>
    points == 1 ? '1 point' : '$points points';

/// One customer in the directory.
final class TenantCustomerCard extends StatelessWidget {
  const TenantCustomerCard({
    super.key,
    required this.customer,
    required this.onOpen,
    required this.actions,
  });

  final TenantCustomer customer;
  final VoidCallback onOpen;

  /// Empty on a read-only build, which then draws no menu at all.
  final List<SupplierMenuAction> actions;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final radius = BorderRadius.circular(tokens.radius.md);
    final target = tokens.density.minimumTapTarget;
    // Beside the press surface, not inside it - the supplier card's note says
    // why: holding a nested menu would also press the card.
    final menuInset = tokens.spacing.s4;
    final menuRoom = target.width + menuInset - tokens.spacing.s16;
    return Stack(
      children: <Widget>[
        PressSurface(
          key: ValueKey('customer-view-${customer.id}'),
          borderRadius: radius,
          fillWidth: true,
          onPressed: onOpen,
          semanticLabel: 'Open ${customer.name}',
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
                      SupplierMonogram(name: customer.name),
                      SizedBox(width: tokens.spacing.s12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              customer.name,
                              key: ValueKey('customer-name-${customer.id}'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: tokens.typography.titleMedium.copyWith(
                                color: tokens.colors.text.primary,
                              ),
                            ),
                            SizedBox(height: tokens.spacing.s4),
                            Text(
                              customerContactLine(customer),
                              key: ValueKey('customer-contact-${customer.id}'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tokens.typography.caption.copyWith(
                                color: tokens.colors.text.tertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Only the exception wears a badge, as on a supplier.
                      if (!customer.active) ...<Widget>[
                        SizedBox(width: tokens.spacing.s8),
                        StatusBadge(
                          key: ValueKey(
                            'customer-inactive-badge-${customer.id}',
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
                  CustomerFactsWell(customer: customer),
                  if (customer.owedMinor > 0 || customer.creditBlocked) ...<Widget>[
                    SizedBox(height: tokens.spacing.s8),
                    Wrap(
                      spacing: tokens.spacing.s8,
                      runSpacing: tokens.spacing.s4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        if (customer.owedMinor > 0)
                          Text(
                            customerOwingLabel(customer),
                            key: ValueKey('customer-owes-${customer.id}'),
                            style: tokens.typography.bodyMedium.copyWith(
                              color: tokens.colors.text.primary,
                            ),
                          ),
                        if (customer.creditBlocked)
                          StatusBadge(
                            key: ValueKey(
                              'customer-credit-blocked-${customer.id}',
                            ),
                            status: AppStatus.neutral,
                            label: 'No credit',
                          ),
                      ],
                    ),
                  ],
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
              menuKey: ValueKey('customer-actions-${customer.id}'),
              tooltip: 'Actions for ${customer.name}',
              actions: actions,
            ),
          ),
      ],
    );
  }
}

/// When a customer last bought and the points they hold, in the recessed well
/// the supplier card keeps its last delivery in.
final class CustomerFactsWell extends StatelessWidget {
  const CustomerFactsWell({super.key, required this.customer});

  final TenantCustomer customer;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final bought = customer.lastSaleAt != null;
    TextStyle figure(bool isFigure) => isFigure
        ? tokens.typography.numericBody.copyWith(
            color: tokens.colors.text.primary,
          )
        : tokens.typography.bodyMedium.copyWith(
            color: tokens.colors.text.tertiary,
          );
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
              Icons.shopping_bag_outlined,
              size: AppButton.iconSize,
              color: bought
                  ? tokens.colors.action.primary.container
                  : tokens.colors.text.tertiary,
            ),
            SizedBox(width: tokens.spacing.s8),
            Text(
              'Last bought',
              style: tokens.typography.labelMedium.copyWith(
                color: tokens.colors.text.secondary,
              ),
            ),
            SizedBox(width: tokens.spacing.s8),
            Expanded(
              child: Text(
                customerLastBoughtLabel(customer),
                key: ValueKey('customer-last-bought-${customer.id}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: figure(bought),
              ),
            ),
            if (customer.points > 0) ...<Widget>[
              SizedBox(width: tokens.spacing.s8),
              Text(
                customerPointsLabel(customer.points),
                key: ValueKey('customer-points-${customer.id}'),
                style: figure(true),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
