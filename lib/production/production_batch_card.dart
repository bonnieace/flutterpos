/// One batch, as the Production route lists it.
///
/// **Built the way a supplier's delivery card is**, not from `RecordList`: what
/// was made and how many in the heading, the two costs a person opens the
/// screen to compare in a recessed well of their own, what the money went on
/// as the rows under it, and when it was made in the foot beside the control
/// that opens those rows.
library;

import 'package:flutter/material.dart';

import '../checkout/checkout_draft.dart';
import '../reports/analysis/report_prose.dart';
import '../ui/buttons.dart';
import '../ui/tokens.dart';
import 'production_batch.dart';

final class TenantProductionBatchCard extends StatelessWidget {
  const TenantProductionBatchCard({
    super.key,
    required this.batch,
    required this.open,
    required this.money,
    required this.onToggle,
  });

  final TenantProductionBatch batch;

  /// Whether the cost rows are shown.
  final bool open;

  final String Function(int minor) money;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final radius = BorderRadius.circular(tokens.radius.md);
    final previous = batch.previousCostMinor;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.colors.surface.raised,
        border: Border.all(color: tokens.colors.surface.cardEdge),
        borderRadius: radius,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.all(tokens.spacing.s16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.factory_outlined,
                        size: AppButton.iconSize,
                        color: tokens.colors.action.primary.container,
                      ),
                      SizedBox(width: tokens.spacing.s8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              '${batch.productName} · ${batch.quantity} made',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: tokens.typography.titleMedium.copyWith(
                                color: tokens.colors.text.primary,
                              ),
                            ),
                            SizedBox(height: tokens.spacing.s4),
                            Text(
                              batch.batchNumber,
                              key: ValueKey('production-number-${batch.id}'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tokens.typography.mono.copyWith(
                                color: tokens.colors.text.tertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: tokens.spacing.s12),
                  _CostWell(batch: batch, money: money),
                ],
              ),
            ),
            if (open)
              Column(
                key: ValueKey('production-costs-open-${batch.id}'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final (index, row)
                      in batch.expenses.indexed) ...<Widget>[
                    Divider(
                      height: 1,
                      indent: index == 0 ? 0 : tokens.spacing.s16,
                      endIndent: index == 0 ? 0 : tokens.spacing.s16,
                      color: tokens.colors.surface.borderSubtle,
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: tokens.spacing.s16,
                        vertical: tokens.spacing.s12,
                      ),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              row.description,
                              style: tokens.typography.labelMedium.copyWith(
                                color: tokens.colors.text.primary,
                              ),
                            ),
                          ),
                          SizedBox(width: tokens.spacing.s12),
                          Text(
                            money(row.amountMinor),
                            style: tokens.typography.numericBody.copyWith(
                              color: tokens.colors.text.money,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (previous != null && previous != batch.unitCostMinor)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        tokens.spacing.s16,
                        0,
                        tokens.spacing.s16,
                        tokens.spacing.s12,
                      ),
                      child: Text(
                        'Cost per unit went from ${money(previous)} to '
                        '${money(batch.unitCostMinor)} with this batch.',
                        style: tokens.typography.caption.copyWith(
                          color: tokens.colors.text.tertiary,
                        ),
                      ),
                    ),
                ],
              ),
            Container(
              color: tokens.colors.surface.overlay,
              padding: EdgeInsetsDirectional.only(
                start: tokens.spacing.s16,
                end: tokens.spacing.s4,
                top: tokens.spacing.s4,
                bottom: tokens.spacing.s4,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      batch.occurredAt == null
                          ? 'Date not recorded'
                          : 'Made '
                                '${reportShortDate(checkoutBusinessDate(batch.occurredAt!))}',
                      key: ValueKey('production-made-${batch.id}'),
                      style: tokens.typography.caption.copyWith(
                        color: tokens.colors.text.secondary,
                      ),
                    ),
                  ),
                  SizedBox(width: tokens.spacing.s8),
                  AppButton(
                    key: ValueKey('production-costs-${batch.id}'),
                    label: open ? 'Hide costs' : 'Show costs',
                    icon: open ? Icons.expand_less : Icons.expand_more,
                    tier: AppButtonTier.tertiary,
                    size: AppButtonSize.sm,
                    onPressed: onToggle,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The batch's two costs, in the recessed well the stock count card keeps its
/// difference figures in.
final class _CostWell extends StatelessWidget {
  const _CostWell({required this.batch, required this.money});

  final TenantProductionBatch batch;
  final String Function(int minor) money;

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
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: _figure(
                  tokens,
                  value: money(batch.unitCostMinor),
                  caption: 'cost per unit',
                  valueKey: ValueKey('production-unit-${batch.id}'),
                ),
              ),
              SizedBox(width: tokens.spacing.s12),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: tokens.colors.surface.borderSubtle,
              ),
              SizedBox(width: tokens.spacing.s12),
              Expanded(
                child: _figure(
                  tokens,
                  value: money(batch.totalCostMinor),
                  caption: 'total cost',
                  valueKey: ValueKey('production-total-${batch.id}'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _figure(
    AppTokens tokens, {
    required String value,
    required String caption,
    required Key valueKey,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      // Drawn smaller rather than cut: a truncated amount is a wrong amount.
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          value,
          key: valueKey,
          maxLines: 1,
          style: tokens.typography.numericCompact.copyWith(
            color: tokens.colors.text.money,
          ),
        ),
      ),
      SizedBox(height: tokens.spacing.s4),
      Text(
        caption,
        style: tokens.typography.caption.copyWith(
          color: tokens.colors.text.tertiary,
        ),
      ),
    ],
  );
}
