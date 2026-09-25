import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/inventory/inventory.dart';
import 'package:flutter_test/flutter_test.dart';

/// **A stock change is labelled when it was made, since 2026-09-25**, not when
/// the server heard of it. A manager offline in the stockroom at 18:02 and back
/// in signal at 08:10 the next morning made the change at 18:02.
void main() {
  final madeAt = DateTime.utc(2026, 9, 24, 18, 2);
  final arrivedAt = DateTime.utc(2026, 9, 25, 8, 10);

  test('a ledger entry says when the stock moved', () {
    final movement = TenantStockMovement.fromDocument(
      path: 'tenants/tenant-a/products/product-1/stock_movements/sa_abc',
      data: <String, Object?>{
        'movementId': 'sa_abc',
        'tenantId': 'tenant-a',
        'productId': 'product-1',
        'sourceType': 'manual_adjustment',
        'adjustmentType': 'restock',
        'quantityDelta': 6,
        'previousQuantity': 4,
        'quantityAfter': 10,
        'reason': 'Counted the back room',
        'actorUid': 'manager-a',
        'occurredAt': Timestamp.fromDate(madeAt),
        'recordedAt': Timestamp.fromDate(arrivedAt),
      },
    );

    expect(
      stockMovementRecordedLabel(movement, 'Juma'),
      'Recorded 2026-09-24 18:02 UTC by Juma',
    );
  });

  test('an adjustment says when it was made', () {
    final record = TenantStockAdjustmentRecord.fromDocument(
      path: 'tenants/tenant-a/stock_adjustments/sa_abc',
      data: <String, Object?>{
        'tenantId': 'tenant-a',
        'productId': 'product-1',
        'sourceType': 'manual_adjustment',
        'adjustmentType': 'restock',
        'quantityDelta': 6,
        'previousQuantity': 4,
        'quantityAfter': 10,
        'reason': 'Counted the back room',
        'actorUid': 'manager-a',
        'requestId': 'adjust-stock-abcdefgh',
        'occurredAt': Timestamp.fromDate(madeAt),
        'createdAt': Timestamp.fromDate(arrivedAt),
      },
    );

    expect(record.occurredAt, madeAt);
    expect(record.recordedAt, arrivedAt);
    expect(
      stockAdjustmentRecordedLabel(record, 'Juma'),
      'Recorded 2026-09-24 18:02 UTC by Juma',
    );
  });
}
