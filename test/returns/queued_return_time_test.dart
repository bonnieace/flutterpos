import 'dart:io';

import 'package:flutter_application_1/returns/returns.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// **A return waiting on this device shows when it was taken, 2026-09-25** -
/// the moment it was queued, which is also the time the gateway sends beside it
/// - so the row a cashier sees offline is the row the server will hold.
void main() {
  late Directory directory;
  late Box<dynamic> box;
  late TenantPendingMutationStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('queued-return-');
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>('queued-return-test');
    store = TenantPendingMutationStore.fromBox(box);
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('a queued return is listed at the moment it was taken', () async {
    await store.enqueue(
      uid: 'user-a',
      tenantId: 'tenant-a',
      operationId: 'return-create-rt_1',
      kind: TenantPendingMutationKind.pendingReturnCreate,
      targetPath: 'tenants/tenant-a/returns/rt_1',
      payload: const <String, Object?>{
        'returnId': 'rt_1',
        'tenantId': 'tenant-a',
        'saleId': 'co-1',
        'businessDate': '2026-09-24',
        'recordedOn': '2026-09-24',
        'createdBy': 'user-a',
        'status': 'pending',
        'reason': 'Customer returned a damaged bottle',
        'itemsReturned': <Object?>[
          <String, Object?>{'productId': 'product-1', 'quantity': 1},
        ],
      },
    );

    // As stored, which is to the millisecond, and as the gateway sends it.
    final record = (await store.recordsForSession(
      uid: 'user-a',
      tenantId: 'tenant-a',
    )).single;
    final drawn = await TenantPendingMutationOverlayReader(
      base: const _Empty(),
      store: store,
      currentUid: () => 'user-a',
    ).getDocument('tenants/tenant-a/returns/rt_1');

    expect(drawn!.data['occurredAt'], record.createdAt);
    expect(
      TenantReturn.fromDocument(path: drawn.path, data: drawn.data).recordedAt,
      record.createdAt,
    );
  });
}

final class _Empty implements TenantCacheReadable {
  const _Empty();

  @override
  TenantDataReader get cacheOnly => this;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async => null;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async => const <TenantQueryDocumentSnapshot>[];
}
