import 'dart:io';
import 'dart:typed_data';

import 'package:uzapay_pos/inventory/inventory.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;
  late Box<dynamic> draftsBox;
  late Box<dynamic> mutationsBox;
  late HiveTenantProductImageDrafts drafts;
  late TenantPendingMutationStore mutations;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('image-drafts-');
    Hive.init(directory.path);
    draftsBox = await Hive.openBox<dynamic>('image-drafts-test');
    mutationsBox = await Hive.openBox<dynamic>('image-mutations-test');
    drafts = HiveTenantProductImageDrafts.fromBox(draftsBox);
    mutations = TenantPendingMutationStore.fromBox(mutationsBox);
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    'a staged photograph is readable at once and survives a reopen',
    () async {
      await drafts.stage(
        tenantId: 'tenant-a',
        productId: 'pd-1',
        candidate: _candidate(),
      );

      expect(
        drafts.bytesFor(tenantId: 'tenant-a', productId: 'pd-1'),
        _jpegBytes,
      );
      // A second store over the same box is what a cold start is.
      expect(
        HiveTenantProductImageDrafts.fromBox(
          draftsBox,
        ).bytesFor(tenantId: 'tenant-a', productId: 'pd-1'),
        _jpegBytes,
      );
      expect(drafts.bytesFor(tenantId: 'tenant-a', productId: 'pd-2'), isNull);
    },
  );

  test(
    'a photograph waits for the product its creation is still queued for',
    () async {
      await mutations.enqueue(
        uid: 'user-a',
        tenantId: 'tenant-a',
        operationId: 'product-create-pd-1',
        kind: TenantPendingMutationKind.productCreate,
        targetPath: 'tenants/tenant-a/products/pd-1',
        payload: const <String, Object?>{'name': 'Mandazi'},
      );
      await drafts.stage(
        tenantId: 'tenant-a',
        productId: 'pd-1',
        candidate: _candidate(),
      );
      final store = _Store();

      final result = await _worker(drafts, store, mutations).run(_session());

      // `updateProduct` would answer `not-found`, and that refusal is permanent -
      // so a create that is merely slow must not cost the photograph.
      expect(result.kind, TenantProductImageUploadRunKind.deferred);
      expect(store.uploads, isEmpty);
      expect(
        drafts.bytesFor(tenantId: 'tenant-a', productId: 'pd-1'),
        isNotNull,
      );
    },
  );

  test('a confirmed product lets its photograph go, as a correction', () async {
    final record = await mutations.enqueue(
      uid: 'user-a',
      tenantId: 'tenant-a',
      operationId: 'product-create-pd-1',
      kind: TenantPendingMutationKind.productCreate,
      targetPath: 'tenants/tenant-a/products/pd-1',
      payload: const <String, Object?>{'name': 'Mandazi'},
    );
    await mutations.markConfirmed(record);
    await drafts.stage(
      tenantId: 'tenant-a',
      productId: 'pd-1',
      candidate: _candidate(),
    );
    final store = _Store();
    final queued = <Map<String, Object?>>[];

    final result = await _worker(
      drafts,
      store,
      mutations,
      onQueued: queued.add,
    ).run(_session());

    expect(result.kind, TenantProductImageUploadRunKind.uploaded);
    expect(store.uploads, <String>['pd-1']);
    // Only the URL reaches the queue. The bytes never do.
    expect(queued.single['image'], 'https://example.test/pd-1.jpg');
    expect(queued.single['productId'], 'pd-1');
    expect(queued.single['requestId'], isA<String>());
    // The draft is gone, so every surface returns to the stored URL.
    expect(drafts.bytesFor(tenantId: 'tenant-a', productId: 'pd-1'), isNull);
  });

  test('a transport refusal keeps the photograph for the next pass', () async {
    await drafts.stage(
      tenantId: 'tenant-a',
      productId: 'pd-1',
      candidate: _candidate(),
    );
    final store = _Store(failure: 'retry-limit-exceeded');

    final result = await _worker(drafts, store, mutations).run(_session());

    expect(result.kind, TenantProductImageUploadRunKind.unavailable);
    expect(
      drafts.bytesFor(tenantId: 'tenant-a', productId: 'pd-1'),
      isNotNull,
      reason: 'a timeout is worth another attempt',
    );
  });

  test(
    'a photograph Storage can never take is dropped rather than retried',
    () async {
      await drafts.stage(
        tenantId: 'tenant-a',
        productId: 'pd-1',
        candidate: _candidate(),
      );
      final store = _Store(failure: 'unsupported_image_type');

      await _worker(drafts, store, mutations).run(_session());

      expect(
        drafts.bytesFor(tenantId: 'tenant-a', productId: 'pd-1'),
        isNull,
        reason: 'retrying it for ever would hold up every photograph behind it',
      );
    },
  );
}

TenantProductImageUploadWorker _worker(
  HiveTenantProductImageDrafts drafts,
  _Store store,
  TenantPendingMutationStore mutations, {
  void Function(Map<String, Object?>)? onQueued,
}) {
  var next = 0;
  return TenantProductImageUploadWorker(
    drafts: drafts,
    store: store,
    mutations: mutations,
    requestId: () => 'image-request-${next++}',
    queue:
        ({
          required tenantId,
          required productId,
          required requestId,
          required payload,
        }) async => onQueued?.call(payload),
  );
}

TenantSession _session() => TenantSession.active(
  uid: 'user-a',
  tenantId: 'tenant-a',
  role: TenantRole.owner,
);

/// The smallest byte string [TenantProductImageCandidate] accepts as a JPEG.
final Uint8List _jpegBytes = Uint8List.fromList(<int>[
  0xff,
  0xd8,
  0xff,
  0x00,
  0x01,
  0x02,
]);

TenantProductImageCandidate _candidate() =>
    TenantProductImageCandidate(bytes: _jpegBytes, fileName: 'mandazi.jpg');

final class _Store implements TenantProductImageStore {
  _Store({this.failure});

  final String? failure;
  final List<String> uploads = <String>[];

  @override
  Future<TenantProductImageUpload> upload({
    required String tenantId,
    required String productId,
    required TenantProductImageCandidate candidate,
  }) async {
    if (failure case final code?) throw TenantProductImageException(code);
    uploads.add(productId);
    return TenantProductImageUpload(
      url: Uri.parse('https://example.test/$productId.jpg'),
      objectPath: 'tenantProductImages/$tenantId/$productId/one.jpg',
    );
  }

  @override
  Future<void> removeOwned({
    required String tenantId,
    required String productId,
    required Uri imageUrl,
  }) async {}
}
