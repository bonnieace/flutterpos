import 'dart:io';

import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/expenses/expenses.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;
  late Box<dynamic> box;
  late TenantPendingMutationStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('queued-writers-');
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>('queued-writers-test');
    store = TenantPendingMutationStore.fromBox(box);
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('offline expense create and void appear in the local overlay', () async {
    final writer = QueuedTenantExpenseWriter(
      remote: const _ExpenseWriter(),
      store: store,
    );
    final create = _expenseIntent();

    expect(
      (await writer.recordExpense(create)).kind,
      TenantExpenseWriteKind.queued,
    );
    expect(
      (await writer.voidExpense(
        TenantExpenseVoidIntent(
          tenantId: 'tenant-a',
          expenseId: create.expenseId,
          reason: 'Entered twice',
          voidedBy: 'owner-a',
        ),
      )).kind,
      TenantExpenseWriteKind.queued,
    );

    final reader = TenantPendingMutationOverlayReader(
      base: const _EmptyReader(),
      store: store,
      currentUid: () => 'owner-a',
    );
    final page = await reader.getCollectionPage(
      TenantCollectionQuery.forTesting(
        collectionPath: 'tenants/tenant-a/expenses',
        limit: 20,
      ),
    );

    expect(page, hasLength(1));
    expect(page.single.data['amountMinor'], 12345);
    expect(page.single.data['voidReason'], 'Entered twice');
    expect(page.single.data['createdAt'], isA<DateTime>());
    expect(page.single.data['voidedAt'], isA<DateTime>());
  });

  test(
    'safe configuration queues even when its cache projection is absent',
    () async {
      final writer = QueuedTenantConfigurationWriter(
        remote: const _ConfigurationWriter(),
        store: store,
        cacheReader: const _EmptyReader(throwDocuments: true),
        currentUid: () => 'owner-a',
      );

      final result = await writer.merge(
        path: 'tenants/tenant-a/configuration/branding',
        data: const <String, Object?>{'companyName': 'Device name'},
      );

      expect(result.kind, TenantConfigurationWriteKind.queued);
      final overlay = TenantPendingMutationOverlayReader(
        base: const _EmptyReader(),
        store: store,
        currentUid: () => 'owner-a',
      );
      expect(
        (await overlay.getDocument(
          'tenants/tenant-a/configuration/branding',
        ))!.data['companyName'],
        'Device name',
      );
    },
  );

  test(
    'checkout configuration remains excluded from the mutation queue',
    () async {
      final writer = QueuedTenantConfigurationWriter(
        remote: const _ConfigurationWriter(),
        store: store,
        cacheReader: const _EmptyReader(),
        currentUid: () => 'owner-a',
      );

      final result = await writer.merge(
        path: 'tenants/tenant-a/configuration/checkout',
        data: const <String, Object?>{'currency': 'KES'},
      );

      expect(result.kind, TenantConfigurationWriteKind.unavailable);
      expect(
        await store.recordsForSession(uid: 'owner-a', tenantId: 'tenant-a'),
        isEmpty,
      );
    },
  );
}

TenantExpenseCreateIntent _expenseIntent() => TenantExpenseCreateIntent(
  tenantId: 'tenant-a',
  businessDate: '2026-09-01',
  token: 'offline-a',
  category: TenantExpenseCategory.rent,
  description: 'September rent',
  amountMinor: 12345,
  recordedBy: 'owner-a',
);

final class _ExpenseWriter implements TenantExpenseWriter {
  const _ExpenseWriter();

  @override
  Future<TenantExpenseWriteResult> recordExpense(
    TenantExpenseCreateIntent intent,
  ) async => const TenantExpenseWriteResult.unavailable();

  @override
  Future<TenantExpenseWriteResult> voidExpense(
    TenantExpenseVoidIntent intent,
  ) async => const TenantExpenseWriteResult.unavailable();
}

final class _ConfigurationWriter implements TenantConfigurationDocumentWriter {
  const _ConfigurationWriter();

  @override
  Future<TenantConfigurationWriteResult> merge({
    required String path,
    required Map<String, Object?> data,
  }) async => const TenantConfigurationWriteResult.unavailable();
}

final class _EmptyReader implements TenantCacheReadable {
  const _EmptyReader({this.throwDocuments = false});

  final bool throwDocuments;

  @override
  TenantDataReader get cacheOnly => this;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    if (throwDocuments) throw StateError('missing cache');
    return null;
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async => const <TenantQueryDocumentSnapshot>[];
}
