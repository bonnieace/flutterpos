import 'dart:io';

import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;
  late Box<dynamic> outboxBox;
  late Box<dynamic> cacheBox;
  late HiveCheckoutOutbox outbox;
  late HiveCheckoutCatalogCache cache;
  late TenantSessionController sessions;
  late _Clock clock;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('checkout-draft-test-');
    Hive.init(directory.path);
    outboxBox = await Hive.openBox<dynamic>(
      HiveCheckoutOutbox.boxName,
      encryptionCipher: HiveAesCipher(_encryptionKey),
      crashRecovery: false,
    );
    cacheBox = await Hive.openBox<dynamic>(
      HiveCheckoutCatalogCache.boxName,
      encryptionCipher: HiveAesCipher(_encryptionKey),
      crashRecovery: false,
    );
    clock = _Clock(DateTime.utc(2026, 7, 31, 9, 30));
    outbox = HiveCheckoutOutbox.fromBox(outboxBox, clock: clock.call);
    cache = HiveCheckoutCatalogCache.fromBox(cacheBox, clock: clock.call);
    sessions = TenantSessionController()
      ..open(uid: 'user-a', membership: _membership('tenant-a'));
    await cache.write(
      uid: 'user-a',
      tenantId: 'tenant-a',
      categories: [_category('tenant-a', 'drinks')],
      products: [
        _product('tenant-a', 'product-a', price: 120.5),
        _product('tenant-a', 'product-b', price: 7),
        _product('tenant-a', 'product-odd', price: 120.555),
      ],
      complete: true,
    );
  });

  tearDown(() async {
    sessions.dispose();
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('builds a draft the frozen submission parser accepts', () async {
    final record = await _service(
      sessions,
      cache,
      outbox,
      clock,
    ).createDraft(
      CheckoutDraftRequest(
        lines: const [
          CheckoutDraftLineRequest(productId: 'product-a', quantity: 2),
          CheckoutDraftLineRequest(productId: 'product-b', quantity: 3),
        ],
        discountMinor: 100,
        deviceId: 'device-a',
        shiftId: 'shift-a',
      ),
    );

    expect(record.state, CheckoutOutboxState.savedOffline);
    expect(record.uid, 'user-a');
    expect(record.tenantId, 'tenant-a');
    expect(record.attemptCount, 0);
    expect(record.payload['currency'], 'KES');
    expect(record.payload['businessDate'], '2026-07-31');
    expect(record.payload['subtotalMinor'], 24100 + 2100);
    expect(record.payload['totalMinor'], 26100);

    final payload = CheckoutSalePayload.fromOutboxRecord(
      record,
      session: sessions.requireSession(),
    );
    expect(payload.payloadHash, record.payloadHash);
    expect(payload.lines.map((line) => line.productId), [
      'product-a',
      'product-b',
    ]);
    expect(payload.lines.first.unitPriceMinor, 12050);
    expect(payload.lines.first.lineTotalMinor, 24100);
    expect(payload.discountMinor, 100);
    expect(payload.deviceId, 'device-a');
    expect(payload.shiftId, 'shift-a');

    final submission = payload.toSubmission();
    expect(submission.salePath, 'tenants/tenant-a/sales/${record.checkoutId}');
    expect(submission.stockDecrements.map((line) => line.quantityDelta), [
      -2,
      -3,
    ]);
  });

  test('resolves the business date in the Africa/Nairobi day', () async {
    clock.value = DateTime.utc(2026, 7, 31, 22, 30);

    final record = await _service(sessions, cache, outbox, clock).createDraft(
      CheckoutDraftRequest(
        lines: const [
          CheckoutDraftLineRequest(productId: 'product-b', quantity: 1),
        ],
      ),
    );

    expect(record.payload['businessDate'], '2026-08-01');
    expect(
      record.payload['createdAtMs'],
      DateTime.utc(2026, 7, 31, 22, 30).millisecondsSinceEpoch,
    );
  });

  test('fails closed on untrusted lines, products, and prices', () async {
    final service = _service(sessions, cache, outbox, clock);
    Future<void> expectCode(CheckoutDraftRequest request, String code) =>
        expectLater(
          service.createDraft(request),
          throwsA(
            isA<CheckoutDraftException>().having(
              (error) => error.code,
              'code',
              code,
            ),
          ),
        );

    await expectCode(CheckoutDraftRequest(lines: const []), 'invalid_line_count');
    await expectCode(
      CheckoutDraftRequest(
        lines: List<CheckoutDraftLineRequest>.generate(
          maximumCheckoutSaleLines + 1,
          (index) => CheckoutDraftLineRequest(
            productId: 'product-$index',
            quantity: 1,
          ),
        ),
      ),
      'invalid_line_count',
    );
    await expectCode(
      CheckoutDraftRequest(
        lines: const [
          CheckoutDraftLineRequest(productId: 'product-a', quantity: 1),
          CheckoutDraftLineRequest(productId: 'product-a', quantity: 1),
        ],
      ),
      'duplicate_product',
    );
    await expectCode(
      CheckoutDraftRequest(
        lines: const [
          CheckoutDraftLineRequest(productId: 'tenants/x', quantity: 1),
        ],
      ),
      'invalid_product_id',
    );
    await expectCode(
      CheckoutDraftRequest(
        lines: const [
          CheckoutDraftLineRequest(productId: 'product-a', quantity: 0),
        ],
      ),
      'invalid_quantity',
    );
    await expectCode(
      CheckoutDraftRequest(
        lines: const [
          CheckoutDraftLineRequest(productId: 'missing', quantity: 1),
        ],
      ),
      'unknown_product',
    );
    await expectCode(
      CheckoutDraftRequest(
        lines: const [
          CheckoutDraftLineRequest(productId: 'product-odd', quantity: 1),
        ],
      ),
      'price_not_representable',
    );
    await expectCode(
      CheckoutDraftRequest(
        lines: const [
          CheckoutDraftLineRequest(productId: 'product-b', quantity: 1),
        ],
        discountMinor: 701,
      ),
      'invalid_discount',
    );
    expect(outboxBox.keys, isEmpty);
  });

  test('refuses a draft without a cached catalog for this session', () async {
    sessions.open(uid: 'user-a', membership: _membership('tenant-b'));

    await expectLater(
      _service(sessions, cache, outbox, clock).createDraft(_request()),
      throwsA(
        isA<CheckoutDraftException>().having(
          (error) => error.code,
          'code',
          'catalog_cache_unavailable',
        ),
      ),
    );
    expect(outboxBox.keys, isEmpty);
  });

  test('refuses a draft when no session is selected', () async {
    sessions.clear();

    await expectLater(
      _service(sessions, cache, outbox, clock).createDraft(_request()),
      throwsA(
        isA<CheckoutDraftException>().having(
          (error) => error.code,
          'code',
          'no_selected_session',
        ),
      ),
    );
  });

  test('discards a queued draft after the session epoch advanced', () async {
    final service = _service(sessions, cache, outbox, clock);

    final stale = service.createDraft(_request());
    sessions.open(uid: 'user-a', membership: _membership('tenant-a'));
    final current = service.createDraft(_request());

    await expectLater(
      stale,
      throwsA(
        isA<CheckoutDraftException>().having(
          (error) => error.code,
          'code',
          'session_changed',
        ),
      ),
    );
    expect((await current).state, CheckoutOutboxState.savedOffline);
    expect(outboxBox.keys, hasLength(1));
  });

  test('serializes concurrent drafts so a checkout ID is never reused', () async {
    // The factory derives the next ID from durable storage, so two overlapping
    // drafts would collide unless the service holds one local lock.
    final service = _service(
      sessions,
      cache,
      outbox,
      clock,
      checkoutIdFactory: () => 'co-${outboxBox.keys.length}',
    );

    final records = await Future.wait<CheckoutOutboxRecord>([
      service.createDraft(_request()),
      service.createDraft(_request(quantity: 2)),
    ]);

    expect(records.map((record) => record.checkoutId), ['co-0', 'co-1']);
    expect(outboxBox.keys, hasLength(2));
  });

  test('rejects a reused checkout ID whose payload changed', () async {
    final service = _service(
      sessions,
      cache,
      outbox,
      clock,
      checkoutIdFactory: () => 'fixed-checkout',
    );

    final first = await service.createDraft(_request());
    final replay = await service.createDraft(_request());
    expect(replay.payloadHash, first.payloadHash);

    await expectLater(
      service.createDraft(_request(quantity: 5)),
      throwsA(
        isA<CheckoutOutboxException>().having(
          (error) => error.code,
          'code',
          'checkout_already_exists',
        ),
      ),
    );
    expect(outboxBox.keys, hasLength(1));
  });

  test('a saved draft blocks tenant switching until it is settled', () async {
    final source = CheckoutOutboxTenantSwitchStateSource(outbox);
    final session = sessions.requireSession();
    expect(
      (await source.inspect(session))!.blocker,
      isNull,
      reason: 'An empty outbox must not block switching.',
    );

    await _service(sessions, cache, outbox, clock).createDraft(_request());

    expect(
      (await source.inspect(session))!.blocker,
      TenantSwitchBlocker.unsynchronizedCheckout,
    );
  });

  test('converts only exactly representable major-unit prices', () {
    expect(checkoutMinorUnitsFromMajor(0), 0);
    expect(checkoutMinorUnitsFromMajor(120.5), 12050);
    expect(checkoutMinorUnitsFromMajor(0.07), 7);
    expect(checkoutMinorUnitsFromMajor(19.99), 1999);
    expect(checkoutMinorUnitsFromMajor(120.555), isNull);
    expect(checkoutMinorUnitsFromMajor(-1), isNull);
    expect(checkoutMinorUnitsFromMajor(double.nan), isNull);
    expect(checkoutMinorUnitsFromMajor(double.infinity), isNull);
    expect(checkoutMinorUnitsFromMajor(1e12), isNull);
  });

  test('formats the business date from a fixed Nairobi offset', () {
    expect(checkoutBusinessDate(DateTime.utc(2026, 1, 1, 20, 59)), '2026-01-01');
    expect(checkoutBusinessDate(DateTime.utc(2026, 1, 1, 21)), '2026-01-02');
    expect(checkoutBusinessDate(DateTime.utc(2026, 12, 31, 21)), '2027-01-01');
  });
}

CheckoutDraftRequest _request({int quantity = 1}) => CheckoutDraftRequest(
  lines: [CheckoutDraftLineRequest(productId: 'product-b', quantity: quantity)],
);

CheckoutDraftService _service(
  TenantSessionController sessions,
  HiveCheckoutCatalogCache cache,
  HiveCheckoutOutbox outbox,
  _Clock clock, {
  CheckoutIdFactory? checkoutIdFactory,
}) => CheckoutDraftService(
  sessionController: sessions,
  cache: cache,
  outbox: outbox,
  currency: 'KES',
  clock: clock.call,
  checkoutIdFactory: checkoutIdFactory,
);

final List<int> _encryptionKey = List<int>.generate(
  HiveCheckoutOutbox.encryptionKeyBytes,
  (index) => (index * 5) % 256,
);

TenantProduct _product(String tenantId, String productId, {double price = 10}) =>
    TenantProduct.fromSnapshot(
      TenantQueryDocumentSnapshot(
        path: 'tenants/$tenantId/products/$productId',
        data: <String, Object?>{
          'name': '$productId name',
          'SKU': 'sku-$productId',
          'price': price,
          'quantity': 12,
          'categoryId': 'drinks',
        },
      ),
    );

TenantCategory _category(String tenantId, String categoryId) =>
    TenantCategory.fromSnapshot(
      TenantQueryDocumentSnapshot(
        path: 'tenants/$tenantId/categories/$categoryId',
        data: <String, Object?>{'name': '$categoryId name'},
      ),
    );

final class _Clock {
  _Clock(this.value);

  DateTime value;

  DateTime call() => value;
}

TenantMembership _membership(String tenantId) => TenantMembership(
  tenantId: tenantId,
  tenantName: tenantId,
  tenantSlug: tenantId,
  role: TenantRole.cashier,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  isOwner: false,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);
