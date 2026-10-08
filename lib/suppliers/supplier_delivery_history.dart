/// What each delivery from one supplier brought in, newest first.
library;

import 'package:flutter/material.dart';

import '../checkout/checkout_draft.dart';
import '../reporting/reporting_currency.dart';
import '../reports/analysis/report_prose.dart';
import '../tenancy/tenant_catalog.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_session.dart';
import '../ui/buttons.dart';
import '../ui/scaffold.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'supplier.dart';
import 'supplier_delivery.dart';
import '../observability/app_telemetry.dart';

/// One supplier's deliveries, as a section of its record.
///
/// **Its own read, not the record's**, so a history that cannot be read - an
/// index still building, a device with nothing cached - costs this section and
/// never the contact details above it.
final class TenantSupplierDeliveryHistory extends StatefulWidget {
  const TenantSupplierDeliveryHistory({
    super.key,
    required this.reader,
    required this.session,
    required this.supplier,
  });

  final TenantDataReader reader;
  final TenantSession session;
  final TenantSupplier supplier;

  /// How many deliveries one read shows before *Show older deliveries*.
  static const int pageSize = 10;

  @override
  State<TenantSupplierDeliveryHistory> createState() =>
      _TenantSupplierDeliveryHistoryState();
}

final class _TenantSupplierDeliveryHistoryState
    extends State<TenantSupplierDeliveryHistory> {
  final List<TenantSupplierDelivery> _deliveries = <TenantSupplierDelivery>[];

  /// Each delivered product's size, read from the product: a delivery saves
  /// the name it was received under and not the size. See [TenantProductSizes].
  final Map<String, String> _sizes = <String, String>{};
  TenantReportingCurrency _currency = TenantReportingCurrency.unknown;
  String? _cursor;
  bool _hasMore = false;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load(first: true);
  }

  Future<void> _load({bool first = false}) async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      if (first) {
        _currency = await TenantReportingCurrency.read(
          session: widget.session,
          reader: widget.reader,
        );
      }
      final page =
          await TenantSupplierDeliveryRepository(
            session: widget.session,
            reader: widget.reader,
          ).loadForSupplier(
            widget.supplier.id,
            pageSize: TenantSupplierDeliveryHistory.pageSize,
            cursor: first ? null : _cursor,
          );
      final sizes =
          await TenantProductSizes(
            session: widget.session,
            reader: widget.reader,
          ).read(<String>{
            for (final delivery in page.items)
              for (final line in delivery.lines)
                if (!_sizes.containsKey(line.productId)) line.productId,
          });
      if (!mounted) return;
      setState(() {
        _sizes.addAll(sizes);
        if (first) _deliveries.clear();
        _deliveries.addAll(page.items);
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'suppliers.delivery_history_read',
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  String _money(int minor) => _currency.format(minor / 100);

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Column(
      key: const ValueKey('supplier-deliveries'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SectionHeading('Deliveries'),
        SizedBox(height: tokens.spacing.s8),
        if (_failed)
          ErrorState(
            key: const ValueKey('supplier-deliveries-failure'),
            badgeLabel: 'Not read',
            statement: 'The deliveries from this supplier could not be read.',
            stillTrue: 'Nothing has been recorded or changed.',
            actions: <Widget>[
              AppButton(
                key: const ValueKey('supplier-deliveries-retry'),
                label: 'Try again',
                onPressed: () => _load(first: _deliveries.isEmpty),
              ),
            ],
          )
        else if (_loading && _deliveries.isEmpty)
          const LoadingState(message: 'Reading deliveries')
        else ...<Widget>[
          if (_deliveries.isEmpty)
            const EmptyState(
              key: ValueKey('supplier-deliveries-empty'),
              title: 'No deliveries yet',
              hint: 'Each delivery received from this supplier is listed here.',
              illustration: 'logistics.svg',
            )
          else
            for (final (index, delivery) in _deliveries.indexed) ...<Widget>[
              if (index > 0) SizedBox(height: tokens.spacing.s12),
              _DeliveryCard(
                key: ValueKey('delivery-row-${delivery.id}'),
                delivery: delivery,
                sizes: _sizes,
                money: _money,
              ),
            ],
          if (_hasMore) ...<Widget>[
            SizedBox(height: tokens.spacing.s12),
            AppButton(
              key: const ValueKey('supplier-deliveries-more'),
              label: 'Show older deliveries',
              loading: _loading,
              expand: true,
              onPressed: _loading ? null : () => _load(),
            ),
          ],
        ],
      ],
    );
  }
}

/// One delivery, drawn the way a sale card is: when and what it was worth in
/// the heading, what came in as the rows under it, and the counts in the foot.
///
/// **Every line is on the card, with nothing to open**, at the developer's
/// direction on 2026-09-27. The lines used to sit behind *Show lines*, so the
/// one thing a person opens a supplier's deliveries to read took a tap per
/// delivery. The rows are compact instead - name and quantity over cost, no
/// icon tile - so a delivery of several products stays a readable height.
final class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard({
    super.key,
    required this.delivery,
    required this.sizes,
    required this.money,
  });

  final TenantSupplierDelivery delivery;
  final Map<String, String> sizes;
  final String Function(int minor) money;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final radius = BorderRadius.circular(tokens.radius.md);
    final day = delivery.occurredAt == null
        ? 'Date not recorded'
        : reportShortDate(checkoutBusinessDate(delivery.occurredAt!));
    final products = delivery.lines.length;
    final costed =
        delivery.lines.isNotEmpty &&
        delivery.costlessLineCount < delivery.lines.length;
    final valueKey = ValueKey('delivery-value-${delivery.id}');
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
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.local_shipping_outlined,
                    size: AppButton.iconSize,
                    color: tokens.colors.action.primary.container,
                  ),
                  SizedBox(width: tokens.spacing.s8),
                  Expanded(
                    child: Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            day,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            // The figures' face at the title size, as a sale
                            // card's time is: the day is what the list is
                            // scanned by.
                            style: tokens.typography.numericBody.copyWith(
                              color: tokens.colors.text.primary,
                              fontSize: tokens.typography.titleMedium.fontSize,
                            ),
                          ),
                        ),
                        if (delivery.reference
                            case final reference?) ...<Widget>[
                          SizedBox(width: tokens.spacing.s8),
                          Flexible(
                            child: Text(
                              reference,
                              key: ValueKey(
                                'delivery-reference-${delivery.id}',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tokens.typography.caption.copyWith(
                                color: tokens.colors.text.tertiary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(width: tokens.spacing.s8),
                  // **The figure alone in the money face.** Where there is no
                  // figure the words say why, in the interface face, so
                  // *No costs recorded* is never read as an amount.
                  if (costed)
                    Text(
                      money(delivery.valueMinor),
                      key: valueKey,
                      style: tokens.typography.numericBody.copyWith(
                        color: tokens.colors.text.money,
                        fontSize: tokens.typography.bodyLarge.fontSize,
                      ),
                    )
                  else
                    Text(
                      delivery.lines.isEmpty
                          ? 'Not recorded'
                          : 'No costs recorded',
                      key: valueKey,
                      style: tokens.typography.caption.copyWith(
                        color: tokens.colors.text.secondary,
                      ),
                    ),
                ],
              ),
            ),
            if (delivery.lines.isNotEmpty)
              Column(
                key: ValueKey('delivery-lines-${delivery.id}'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final (index, line)
                      in delivery.lines.indexed) ...<Widget>[
                    Divider(
                      height: 1,
                      indent: index == 0 ? 0 : tokens.spacing.s16,
                      endIndent: index == 0 ? 0 : tokens.spacing.s16,
                      color: tokens.colors.surface.borderSubtle,
                    ),
                    _DeliveryLineRow(
                      key: ValueKey('delivery-line-${delivery.id}-$index'),
                      line: line,
                      size: sizes[line.productId],
                      money: money,
                    ),
                  ],
                ],
              ),
            Container(
              color: tokens.colors.surface.overlay,
              padding: EdgeInsets.symmetric(
                horizontal: tokens.spacing.s16,
                vertical: tokens.spacing.s8,
              ),
              child: Wrap(
                spacing: tokens.spacing.s12,
                runSpacing: tokens.spacing.s4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  _FootFact(
                    label:
                        '$products '
                        '${products == 1 ? 'product' : 'products'} · '
                        '${delivery.unitCount} '
                        '${delivery.unitCount == 1 ? 'unit' : 'units'}',
                  ),
                  // **The figure and the words about it are apart.** One
                  // value in the money face read *(1 without a cost)* as
                  // part of the amount.
                  if (costed && delivery.costlessLineCount > 0)
                    _FootFact(
                      textKey: ValueKey('delivery-costless-${delivery.id}'),
                      label:
                          '${delivery.costlessLineCount} '
                          '${delivery.costlessLineCount == 1 ? 'line' : 'lines'}'
                          ' without a cost, not in the value',
                    ),
                  // **Only a delivery still arriving says anything about
                  // its standing**, and it says it in words.
                  if (!delivery.complete)
                    StatusBadge(
                      key: ValueKey('delivery-arriving-${delivery.id}'),
                      status: AppStatus.attention,
                      icon: Icons.schedule,
                      label: 'Still arriving',
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

/// One product line of a delivery, as a sale card draws one of its lines.
final class _DeliveryLineRow extends StatelessWidget {
  const _DeliveryLineRow({
    super.key,
    required this.line,
    required this.size,
    required this.money,
  });

  final TenantSupplierDeliveryRecordLine line;
  final String? size;
  final String Function(int minor) money;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final cost = line.unitCostMinor;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.s16,
        vertical: tokens.spacing.s8,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  tenantProductLabel(line.productName, size),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.typography.labelMedium.copyWith(
                    color: tokens.colors.text.primary,
                  ),
                ),
                Text(
                  cost == null
                      ? '${line.quantity} × no cost recorded'
                      : '${line.quantity} × ${money(cost)}',
                  style: tokens.typography.caption.copyWith(
                    color: tokens.colors.text.tertiary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: tokens.spacing.s12),
          // Words in the interface face, a figure in the money one - the same
          // split the heading makes.
          if (cost == null)
            Text(
              'No cost',
              style: tokens.typography.caption.copyWith(
                color: tokens.colors.text.secondary,
              ),
            )
          else
            Text(
              money(cost * line.quantity),
              style: tokens.typography.numericBody.copyWith(
                color: tokens.colors.text.money,
              ),
            ),
        ],
      ),
    );
  }
}

/// One fact in a delivery card's foot: `caption` at `text.secondary`, the sale
/// card's foot exactly.
final class _FootFact extends StatelessWidget {
  const _FootFact({required this.label, this.textKey});

  final String label;
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Text(
      label,
      key: textKey,
      style: tokens.typography.caption.copyWith(
        color: tokens.colors.text.secondary,
      ),
    );
  }
}
