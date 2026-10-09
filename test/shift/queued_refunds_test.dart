import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:uzapay_pos/shift/shift_sales_ledger.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';

/// **A refund handed over with no signal has already left the drawer.** The
/// return waits on this phone's queue, so the server cannot count it at close;
/// the close reads it from here, by the shift that paid it.
void main() {
  late Directory directory;
  late TenantPendingMutationStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('queued-refund-');
    Hive.init(directory.path);
    store = TenantPendingMutationStore.fromBox(
      await Hive.openBox<dynamic>('queued-refund-test'),
    );
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Future<void> queue(String returnId, {Map<String, Object?>? refund}) =>
      store.enqueue(
        uid: 'user-a',
        tenantId: 'tenant-a',
        operationId: 'return-create-$returnId',
        kind: TenantPendingMutationKind.pendingReturnCreate,
        targetPath: 'tenants/tenant-a/returns/$returnId',
        payload: <String, Object?>{
          'returnId': returnId,
          'tenantId': 'tenant-a',
          'saleId': 'co-1',
          'businessDate': '2026-10-08',
          'recordedOn': '2026-10-09',
          'createdBy': 'user-a',
          'status': 'pending',
          'reason': 'Customer returned a damaged bottle',
          'itemsReturned': <Object?>[
            <String, Object?>{'productId': 'product-1', 'quantity': 1},
          ],
          ...?refund,
        },
      );

  test("reads the refunds this phone paid out of one shift's drawer", () async {
    await queue(
      'rt_1',
      refund: <String, Object?>{
        'refundMinor': 500,
        'refundTender': 'cash',
        'refundShiftId': 'shift-b',
        'refundBusinessDate': '2026-10-09',
      },
    );
    await queue(
      'rt_2',
      refund: <String, Object?>{
        'refundMinor': 900,
        'refundTender': 'mpesa',
        'refundShiftId': 'shift-other',
        'refundBusinessDate': '2026-10-09',
      },
    );
    // An exchange: goods back, nothing handed over.
    await queue('rt_3');

    final refunds = await PendingMutationShiftRefunds(
      store,
    ).forShift(uid: 'user-a', tenantId: 'tenant-a', shiftId: 'shift-b');

    expect(refunds, <String, int>{'rt_1': 500});
  });
}
