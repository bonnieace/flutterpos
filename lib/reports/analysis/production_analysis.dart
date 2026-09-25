/// What a period's production batches add up to - pure Dart, no Flutter and no
/// I/O, so every figure the production report prints is tested directly.
library;

import '../../checkout/checkout_draft.dart';
import '../../production/production_batch.dart';
import '../report_period.dart';
import '../report_run.dart';

/// One product's batches over the period.
final class TenantProductionProductTotals {
  TenantProductionProductTotals._(this.productId, this.productName);

  final String productId;
  final String productName;
  int batches = 0;
  int units = 0;
  int spentMinor = 0;

  /// The first and latest cost per unit, in the order the batches were made.
  int? firstUnitCostMinor;
  int? latestUnitCostMinor;

  /// How the cost per unit moved from the first batch to the latest, or null
  /// when there is only one or the first cost was nothing.
  double? get change {
    final first = firstUnitCostMinor;
    final latest = latestUnitCostMinor;
    if (batches < 2 || first == null || latest == null || first == 0) {
      return null;
    }
    return (latest - first) / first;
  }
}

/// One batch, as a row of the report.
final class TenantProductionBatchRow {
  const TenantProductionBatchRow({
    required this.businessDate,
    required this.batch,
  });

  final String businessDate;
  final TenantProductionBatch batch;
}

/// Everything the production report says about one period.
final class TenantProductionAnalysis {
  TenantProductionAnalysis._({
    required this.period,
    required this.subject,
    required this.products,
    required this.rows,
    required this.truncated,
    required this.reachedTo,
    required this.recordsRead,
  });

  /// Reads [batches] - already narrowed to [subject] when there is one.
  factory TenantProductionAnalysis.from({
    required TenantReportPeriod period,
    required List<TenantProductionBatch> batches,
    TenantReportSubjectOption? subject,
    bool truncated = false,
    String? reachedTo,
    int? recordsRead,
  }) {
    final ordered = <TenantProductionBatch>[...batches]
      ..sort((left, right) {
        final byTime = (left.occurredAt ?? DateTime.utc(0)).compareTo(
          right.occurredAt ?? DateTime.utc(0),
        );
        return byTime != 0 ? byTime : left.id.compareTo(right.id);
      });
    final byProduct = <String, TenantProductionProductTotals>{};
    final rows = <TenantProductionBatchRow>[];
    for (final batch in ordered) {
      final totals = byProduct.putIfAbsent(
        batch.productId,
        () => TenantProductionProductTotals._(batch.productId, batch.productName),
      );
      totals.batches++;
      totals.units += batch.quantity;
      totals.spentMinor += batch.totalCostMinor;
      totals.firstUnitCostMinor ??= batch.unitCostMinor;
      totals.latestUnitCostMinor = batch.unitCostMinor;
      rows.add(
        TenantProductionBatchRow(
          businessDate: batch.occurredAt == null
              ? period.startDate
              : checkoutBusinessDate(batch.occurredAt!.toUtc()),
          batch: batch,
        ),
      );
    }
    final products = byProduct.values.toList()
      ..sort((left, right) {
        final bySpend = right.spentMinor.compareTo(left.spentMinor);
        return bySpend != 0
            ? bySpend
            : left.productName.compareTo(right.productName);
      });
    return TenantProductionAnalysis._(
      period: period,
      subject: subject,
      products: List<TenantProductionProductTotals>.unmodifiable(products),
      rows: List<TenantProductionBatchRow>.unmodifiable(rows),
      truncated: truncated,
      reachedTo: reachedTo,
      recordsRead: recordsRead ?? batches.length,
    );
  }

  final TenantReportPeriod period;

  /// The one product this was narrowed to, or null for every product.
  final TenantReportSubjectOption? subject;

  /// Largest spend first.
  final List<TenantProductionProductTotals> products;

  /// Oldest batch first: the order the cost per unit is read in.
  final List<TenantProductionBatchRow> rows;

  final bool truncated;
  final String? reachedTo;
  final int recordsRead;

  int get batchCount => rows.length;

  int get unitCount => products.fold(0, (sum, row) => sum + row.units);

  int get spentMinor => products.fold(0, (sum, row) => sum + row.spentMinor);

  /// The products whose cost per unit moved across their batches, largest move
  /// first.
  List<TenantProductionProductTotals> get moved =>
      products.where((product) => product.change != null && product.change != 0)
          .toList()
        ..sort((left, right) => right.change!.abs().compareTo(left.change!.abs()));
}
