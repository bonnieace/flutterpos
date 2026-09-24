/// What each delivery from one supplier brought in, newest first.
library;

import 'package:flutter/material.dart';

import '../checkout/checkout_draft.dart';
import '../reporting/reporting_currency.dart';
import '../reports/analysis/report_prose.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_session.dart';
import '../ui/buttons.dart';
import '../ui/record_list.dart';
import '../ui/scaffold.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'supplier.dart';
import 'supplier_delivery.dart';

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
  final Set<String> _expanded = <String>{};
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
      final page = await TenantSupplierDeliveryRepository(
        session: widget.session,
        reader: widget.reader,
      ).loadForSupplier(
        widget.supplier.id,
        pageSize: TenantSupplierDeliveryHistory.pageSize,
        cursor: first ? null : _cursor,
      );
      if (!mounted) return;
      setState(() {
        if (first) _deliveries.clear();
        _deliveries.addAll(page.items);
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  String _money(int minor) => _currency.format(minor / 100);

  RecordItem _record(TenantSupplierDelivery delivery) {
    final day = delivery.createdAt == null
        ? 'Date not recorded'
        : reportShortDate(checkoutBusinessDate(delivery.createdAt!));
    final products = delivery.lines.length;
    final open = _expanded.contains(delivery.id);
    return RecordItem(
      id: delivery.id,
      recordKey: ValueKey('delivery-row-${delivery.id}'),
      title: delivery.reference == null ? day : '$day · ${delivery.reference}',
      subtitle:
          '$products ${products == 1 ? 'product' : 'products'} · '
          '${delivery.unitCount} ${delivery.unitCount == 1 ? 'unit' : 'units'}',
      // **Only a delivery still arriving says anything about its standing.**
      status: delivery.complete
          ? null
          : RecordStatus(
              status: AppStatus.attention,
              label: 'Still arriving',
              badgeKey: ValueKey('delivery-arriving-${delivery.id}'),
            ),
      attributes: <RecordAttribute>[
        RecordAttribute(
          label: 'Value received',
          value: delivery.lines.isEmpty
              ? 'Not recorded'
              : delivery.costlessLineCount == delivery.lines.length
              ? 'No costs recorded'
              : delivery.costlessLineCount == 0
              ? _money(delivery.valueMinor)
              : '${_money(delivery.valueMinor)} (${delivery.costlessLineCount} '
                    'without a cost)',
          kind: RecordValueKind.money,
          valueKey: ValueKey('delivery-value-${delivery.id}'),
        ),
      ],
      actions: <RecordAction>[
        RecordAction(
          label: open ? 'Hide lines' : 'Show lines',
          icon: open ? Icons.expand_less : Icons.expand_more,
          actionKey: ValueKey('delivery-lines-${delivery.id}'),
          onPressed: () => setState(() {
            if (!_expanded.remove(delivery.id)) _expanded.add(delivery.id);
          }),
        ),
      ],
      details: open ? _DeliveryLines(delivery: delivery, money: _money) : null,
    );
  }

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
          RecordList(
            identityLabel: 'Delivery',
            items: <RecordItem>[
              for (final delivery in _deliveries) _record(delivery),
            ],
            empty: const EmptyState(
              key: ValueKey('supplier-deliveries-empty'),
              title: 'No deliveries yet',
              hint: 'Each delivery received from this supplier is listed here.',
              illustration: 'logistics.svg',
            ),
          ),
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

/// The product lines of one delivery.
final class _DeliveryLines extends StatelessWidget {
  const _DeliveryLines({required this.delivery, required this.money});

  final TenantSupplierDelivery delivery;
  final String Function(int minor) money;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Column(
      key: ValueKey('delivery-lines-open-${delivery.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final line in delivery.lines)
          Padding(
            padding: EdgeInsets.only(top: tokens.spacing.s8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${line.productName} × ${line.quantity}',
                    style: tokens.typography.bodyMedium.copyWith(
                      color: tokens.colors.text.primary,
                    ),
                  ),
                ),
                SizedBox(width: tokens.spacing.s12),
                Text(
                  line.unitCostMinor == null
                      ? 'No cost'
                      : '${money(line.unitCostMinor!)} each',
                  style: tokens.typography.numericBody.copyWith(
                    color: tokens.colors.text.money,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
