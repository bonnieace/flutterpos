/// What one production batch cost, on a screen of its own.
///
/// **A screen rather than rows that open under the card**, at the developer's
/// direction on 2026-09-27. The rows used to unfold inside the list, which put
/// the one breakdown a person came to read between two other batches. Here it
/// has the room to say what a batch cost, what each unit cost against the batch
/// before, and which costs made up the total.
///
/// It reads nothing: the batch the list already holds is the whole of it.
library;

import 'package:flutter/material.dart';

import '../checkout/checkout_draft.dart';
import '../reports/analysis/report_prose.dart';
import '../ui/card.dart';
import '../ui/meter.dart';
import '../ui/routes.dart';
import '../ui/scaffold.dart';
import '../ui/stats.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'production_batch.dart';

/// Opens [batch]'s cost of production over the current route.
Future<void> openProductionCostScreen(
  BuildContext context, {
  required TenantProductionBatch batch,
  required String Function(int minor) money,
}) => Navigator.of(context).push(
  AppPageRoute<void>(
    builder: (_) => TenantProductionCostScreen(batch: batch, money: money),
  ),
);

final class TenantProductionCostScreen extends StatelessWidget {
  const TenantProductionCostScreen({
    super.key,
    required this.batch,
    required this.money,
  });

  final TenantProductionBatch batch;
  final String Function(int minor) money;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final made = batch.occurredAt == null
        ? 'Not recorded'
        : reportShortDate(checkoutBusinessDate(batch.occurredAt!));
    // Largest first: the breakdown is read for what drove the total.
    final lines = <TenantProductionExpense>[...batch.expenses]
      ..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
    return AppScaffold(
      key: const ValueKey('production-cost-screen'),
      title: 'Cost of production',
      subtitle: '${batch.productName} · ${batch.batchNumber}',
      contentWidth: AppContentWidth.reading,
      body: ListView(
        padding: EdgeInsets.all(tokens.spacing.s16),
        children: <Widget>[
          StatRow(
            tiles: <StatTile>[
              StatTile(
                label: 'Total cost',
                value: money(batch.totalCostMinor),
                detail: batch.quantity == 1
                    ? 'For 1 unit made'
                    : 'For ${batch.quantity} units made',
                valueKey: const ValueKey('production-cost-total'),
                money: true,
              ),
              _unitCostTile(),
            ],
          ),
          SizedBox(height: tokens.spacing.s24),
          const SectionHeading('What it cost'),
          SizedBox(height: tokens.spacing.s8),
          AppCard(
            key: const ValueKey('production-cost-breakdown'),
            child: lines.isEmpty
                ? Text(
                    'No costs were recorded for this batch.',
                    style: tokens.density
                        .body(tokens.typography)
                        .copyWith(color: tokens.colors.text.secondary),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (final (index, line) in lines.indexed) ...<Widget>[
                        if (index > 0)
                          Divider(
                            height: tokens.spacing.s24,
                            color: tokens.colors.surface.borderSubtle,
                          ),
                        _CostLine(
                          key: ValueKey('production-cost-line-$index'),
                          line: line,
                          totalMinor: batch.totalCostMinor,
                          money: money,
                        ),
                      ],
                      Divider(
                        height: tokens.spacing.s24,
                        color: tokens.colors.surface.borderStrong,
                      ),
                      StatLine(
                        label: 'Total',
                        value: money(batch.totalCostMinor),
                        money: true,
                        emphasis: true,
                      ),
                    ],
                  ),
          ),
          SizedBox(height: tokens.spacing.s24),
          const SectionHeading('Batch'),
          SizedBox(height: tokens.spacing.s8),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                StatLine(label: 'Made', value: made),
                StatLine(label: 'Units made', value: '${batch.quantity}'),
                StatLine(label: 'Batch number', value: batch.batchNumber),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Cost per unit, and which way it moved against the cost before the batch.
  ///
  /// The direction is a badge - a word and an icon - never the colour alone,
  /// and a cost that went up is `attention` rather than `problem`: making
  /// something dearer is a fact to notice, not a fault.
  StatTile _unitCostTile() {
    final previous = batch.previousCostMinor;
    final unit = batch.unitCostMinor;
    final (AppStatus?, String?, IconData?, String) standing =
        switch (previous) {
          null => (null, null, null, 'No earlier cost recorded'),
          final before when before < unit => (
            AppStatus.attention,
            'Up',
            Icons.trending_up,
            'Was ${money(before)} before this batch',
          ),
          final before when before > unit => (
            AppStatus.ok,
            'Down',
            Icons.trending_down,
            'Was ${money(before)} before this batch',
          ),
          _ => (null, null, null, 'Same as before this batch'),
        };
    return StatTile(
      label: 'Cost per unit',
      value: money(unit),
      detail: standing.$4,
      status: standing.$1,
      statusLabel: standing.$2,
      statusIcon: standing.$3,
      valueKey: const ValueKey('production-cost-unit'),
      money: true,
    );
  }
}

/// One cost, its amount, and its share of the batch's total.
final class _CostLine extends StatelessWidget {
  const _CostLine({
    super.key,
    required this.line,
    required this.totalMinor,
    required this.money,
  });

  final TenantProductionExpense line;
  final int totalMinor;
  final String Function(int minor) money;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final share = totalMinor <= 0
        ? null
        : (line.amountMinor * 100 / totalMinor).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Text(
                line.description,
                style: tokens.typography.labelMedium.copyWith(
                  color: tokens.colors.text.primary,
                ),
              ),
            ),
            SizedBox(width: tokens.spacing.s12),
            Text(
              money(line.amountMinor),
              style: tokens.typography.numericBody.copyWith(
                color: tokens.colors.text.money,
              ),
            ),
          ],
        ),
        if (share != null) ...<Widget>[
          SizedBox(height: tokens.spacing.s8),
          Row(
            children: <Widget>[
              Expanded(
                child: AppMeter(
                  filled: line.amountMinor,
                  of: totalMinor,
                  status: AppStatus.info,
                  semanticLabel: '$share percent of the total cost',
                ),
              ),
              SizedBox(width: tokens.spacing.s12),
              // The share in words beside the bar: a meter alone says nothing.
              Text(
                '$share%',
                style: tokens.typography.caption.copyWith(
                  color: tokens.colors.text.secondary,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
