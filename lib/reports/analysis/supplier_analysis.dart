/// What a period's supplier deliveries add up to - pure Dart, no Flutter and no
/// I/O, so every figure the supplier report prints is tested directly.
library;

import '../../checkout/checkout_draft.dart';
import '../../suppliers/supplier_delivery.dart';
import '../../tenancy/tenant_catalog.dart';
import '../report_period.dart';
import '../report_run.dart';

/// One supplier's deliveries over the period.
final class TenantSupplierTotals {
  TenantSupplierTotals._(this.supplierId, this.supplierName);

  final String supplierId;
  String supplierName;
  int deliveries = 0;
  int units = 0;
  int valueMinor = 0;
  int costlessLines = 0;
  final Set<String> products = <String>{};
}

/// How one product's unit cost moved across the deliveries of the period.
final class TenantUnitCostChange {
  const TenantUnitCostChange({
    required this.productName,
    required this.supplierName,
    required this.firstMinor,
    required this.latestMinor,
    required this.firstOn,
    required this.latestOn,
  });

  final String productName;

  /// Who delivered it at the latest cost.
  final String supplierName;
  final int firstMinor;
  final int latestMinor;
  final String firstOn;
  final String latestOn;

  /// The move as a fraction of the first cost.
  double get change => (latestMinor - firstMinor) / firstMinor;
}

/// One delivery, as a row of the report.
final class TenantSupplierDeliveryRow {
  const TenantSupplierDeliveryRow({
    required this.businessDate,
    required this.delivery,
  });

  final String businessDate;
  final TenantSupplierDelivery delivery;
}

/// Everything the supplier report says about one period.
final class TenantSupplierAnalysis {
  TenantSupplierAnalysis._({
    required this.period,
    required this.subject,
    required this.totals,
    required this.costChanges,
    required this.rows,
    required this.lineCount,
    required this.costlessLineCount,
    required this.restocksWithoutSupplier,
    required this.restocksTruncated,
    required this.truncated,
    required this.reachedTo,
    required this.recordsRead,
  });

  /// Reads [deliveries] - already narrowed to [subject] when there is one.
  ///
  /// [reachedTo] is the last business day the read reached when it was
  /// [truncated]; the report states that day rather than the period asked for.
  ///
  /// [sizes] is each product's size by ID, which a delivery does not save; a
  /// product missing from it is named alone. See `TenantProductSizes`.
  factory TenantSupplierAnalysis.from({
    required TenantReportPeriod period,
    required List<TenantSupplierDelivery> deliveries,
    Map<String, String> sizes = const <String, String>{},
    TenantReportSubjectOption? subject,
    int? restocksWithoutSupplier,
    bool restocksTruncated = false,
    bool truncated = false,
    String? reachedTo,
    int? recordsRead,
  }) {
    final ordered = <TenantSupplierDelivery>[...deliveries]
      ..sort((left, right) {
        final byTime = (left.occurredAt ?? DateTime.utc(0)).compareTo(
          right.occurredAt ?? DateTime.utc(0),
        );
        return byTime != 0 ? byTime : left.id.compareTo(right.id);
      });
    final bySupplier = <String, TenantSupplierTotals>{};
    final costs = <String, List<({int minor, String on, String supplier, String name})>>{};
    var lines = 0;
    var costless = 0;
    final rows = <TenantSupplierDeliveryRow>[];
    for (final delivery in ordered) {
      final on = delivery.occurredAt == null
          ? period.startDate
          : checkoutBusinessDate(delivery.occurredAt!.toUtc());
      final name = delivery.supplierName ?? delivery.supplierId;
      final totals = bySupplier.putIfAbsent(
        delivery.supplierId,
        () => TenantSupplierTotals._(delivery.supplierId, name),
      );
      totals.deliveries++;
      for (final line in delivery.lines) {
        lines++;
        final label = tenantProductLabel(
          line.productName,
          sizes[line.productId],
        );
        totals.units += line.quantity;
        totals.products.add(label);
        final cost = line.unitCostMinor;
        if (cost == null) {
          costless++;
          totals.costlessLines++;
        } else {
          totals.valueMinor += line.quantity * cost;
          costs.putIfAbsent(line.productId, () => []).add((
            minor: cost,
            on: on,
            supplier: name,
            name: label,
          ));
        }
      }
      rows.add(TenantSupplierDeliveryRow(businessDate: on, delivery: delivery));
    }
    final changes = <TenantUnitCostChange>[
      for (final entries in costs.values)
        if (entries.first.minor != entries.last.minor)
          TenantUnitCostChange(
            productName: entries.last.name,
            supplierName: entries.last.supplier,
            firstMinor: entries.first.minor,
            latestMinor: entries.last.minor,
            firstOn: entries.first.on,
            latestOn: entries.last.on,
          ),
    ]..sort((left, right) => right.change.abs().compareTo(left.change.abs()));
    final totals = bySupplier.values.toList()
      ..sort((left, right) {
        final byValue = right.valueMinor.compareTo(left.valueMinor);
        return byValue != 0
            ? byValue
            : left.supplierName.compareTo(right.supplierName);
      });
    return TenantSupplierAnalysis._(
      period: period,
      subject: subject,
      totals: List<TenantSupplierTotals>.unmodifiable(totals),
      costChanges: List<TenantUnitCostChange>.unmodifiable(changes),
      rows: List<TenantSupplierDeliveryRow>.unmodifiable(rows.reversed),
      lineCount: lines,
      costlessLineCount: costless,
      restocksWithoutSupplier: subject == null ? restocksWithoutSupplier : null,
      restocksTruncated: restocksTruncated,
      truncated: truncated,
      reachedTo: reachedTo,
      recordsRead: recordsRead ?? deliveries.length,
    );
  }

  final TenantReportPeriod period;

  /// The one supplier this was narrowed to, or null for every supplier.
  final TenantReportSubjectOption? subject;

  /// Largest value received first.
  final List<TenantSupplierTotals> totals;

  /// Largest move first.
  final List<TenantUnitCostChange> costChanges;

  /// Newest delivery first, the order a person reads a list in.
  final List<TenantSupplierDeliveryRow> rows;

  final int lineCount;
  final int costlessLineCount;

  /// Restocks recorded with no supplier named, only when the report covers
  /// every supplier - one supplier's report has nothing to say about them.
  final int? restocksWithoutSupplier;
  final bool restocksTruncated;
  final bool truncated;
  final String? reachedTo;

  /// How many deliveries the read covered, before any narrowing to one
  /// supplier - the figure a capped read's caveat states.
  final int recordsRead;

  int get deliveryCount => rows.length;

  int get unitCount => totals.fold(0, (sum, row) => sum + row.units);

  int get valueMinor => totals.fold(0, (sum, row) => sum + row.valueMinor);
}
