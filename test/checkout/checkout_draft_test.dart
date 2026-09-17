import 'dart:io';
import 'dart:math';

import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;
  late Box<dynamic> outboxBox;
  late Box<dynamic> cacheBox;
  late Box<dynamic> receiptBox;
  late HiveCheckoutOutbox outbox;
  late HiveCheckoutCatalogCache cache;
  late HiveCheckoutReceiptCounters receipts;
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
    receiptBox = await Hive.openBox<dynamic>(
      HiveCheckoutReceiptCounters.boxName,
      encryptionCipher: HiveAesCipher(_encryptionKey),
      crashRecovery: false,
    );
    clock = _Clock(DateTime.utc(2026, 7, 31, 9, 30));
    outbox = HiveCheckoutOutbox.fromBox(outboxBox, clock: clock.call);
    cache = HiveCheckoutCatalogCache.fromBox(cacheBox, clock: clock.call);
    receipts = HiveCheckoutReceiptCounters.fromBox(
      receiptBox,
      clock: clock.call,
      random: Random(7),
    );
    sessions = TenantSessionController()
      ..open(uid: 'user-a', membership: _membership('tenant-a'));
    await cache.write(
      uid: 'user-a',
      tenantId: 'tenant-a',
      configuration: TenantCheckoutConfiguration(currency: 'KES'),
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
    final record = await _service(sessions, cache, outbox, receipts, clock)
        .createDraft(
          CheckoutDraftRequest(
            tender: CheckoutTender.mpesa,
            lines: const [
              CheckoutDraftLineRequest(productId: 'product-a', quantity: 2),
              CheckoutDraftLineRequest(productId: 'product-b', quantity: 3),
            ],
            discountMinor: 100,
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
    // Every new draft is v2 and names the tender the cashier chose.
    expect(record.payload['schemaVersion'], checkoutSalePayloadSchemaVersion);
    expect(record.payload['tender'], 'mpesa');

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
    expect(payload.schemaVersion, checkoutSalePayloadSchemaVersion);
    expect(payload.tender, CheckoutTender.mpesa);
    expect(payload.shiftId, 'shift-a');
    expect(payload.deviceId, await receipts.resolveDeviceId());
    expect(payload.receiptSequence, 1);
    expect(
      payload.receiptNumber,
      formatCheckoutReceiptNumber(
        deviceId: await receipts.resolveDeviceId(),
        businessDate: '2026-07-31',
        sequence: 1,
      ),
    );

    final submission = payload.toSubmission();
    expect(submission.salePath, 'tenants/tenant-a/sales/${record.checkoutId}');
    expect(submission.stockDecrements.map((line) => line.quantityDelta), [
      -2,
      -3,
    ]);
  });

  test('resolves the business date in the Africa/Nairobi day', () async {
    clock.value = DateTime.utc(2026, 7, 31, 22, 30);

    final record = await _service(sessions, cache, outbox, receipts, clock)
        .createDraft(
          CheckoutDraftRequest(
            tender: CheckoutTender.mpesa,
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

  test('records every modelled tender and refuses no valid one', () async {
    final service = _service(sessions, cache, outbox, receipts, clock);

    for (final tender in CheckoutTender.values) {
      final record = await service.createDraft(
        CheckoutDraftRequest(
          tender: tender,
          lines: const [
            CheckoutDraftLineRequest(productId: 'product-b', quantity: 1),
          ],
        ),
      );

      expect(record.payload['tender'], tender.wireValue);
      expect(
        CheckoutSalePayload.fromOutboxRecord(
          record,
          session: sessions.requireSession(),
        ).tender,
        tender,
        reason: tender.wireValue,
      );
    }
  });

  test('fails closed on untrusted lines, products, and prices', () async {
    final service = _service(sessions, cache, outbox, receipts, clock);
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

    await expectCode(
      CheckoutDraftRequest(lines: const [], tender: CheckoutTender.mpesa),
      'invalid_line_count',
    );
    await expectCode(
      CheckoutDraftRequest(
        tender: CheckoutTender.mpesa,
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
        tender: CheckoutTender.mpesa,
        lines: const [
          CheckoutDraftLineRequest(productId: 'product-a', quantity: 1),
          CheckoutDraftLineRequest(productId: 'product-a', quantity: 1),
        ],
      ),
      'duplicate_product',
    );
    await expectCode(
      CheckoutDraftRequest(
        tender: CheckoutTender.mpesa,
        lines: const [
          CheckoutDraftLineRequest(productId: 'tenants/x', quantity: 1),
        ],
      ),
      'invalid_product_id',
    );
    await expectCode(
      CheckoutDraftRequest(
        tender: CheckoutTender.mpesa,
        lines: const [
          CheckoutDraftLineRequest(productId: 'product-a', quantity: 0),
        ],
      ),
      'invalid_quantity',
    );
    await expectCode(
      CheckoutDraftRequest(
        tender: CheckoutTender.mpesa,
        lines: const [
          CheckoutDraftLineRequest(productId: 'missing', quantity: 1),
        ],
      ),
      'unknown_product',
    );
    await expectCode(
      CheckoutDraftRequest(
        tender: CheckoutTender.mpesa,
        lines: const [
          CheckoutDraftLineRequest(productId: 'product-odd', quantity: 1),
        ],
      ),
      'price_not_representable',
    );
    await expectCode(
      CheckoutDraftRequest(
        tender: CheckoutTender.mpesa,
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
      _service(
        sessions,
        cache,
        outbox,
        receipts,
        clock,
      ).createDraft(_request()),
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
      _service(
        sessions,
        cache,
        outbox,
        receipts,
        clock,
      ).createDraft(_request()),
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
    final service = _service(sessions, cache, outbox, receipts, clock);

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

  test(
    'serializes concurrent drafts so a checkout ID is never reused',
    () async {
      // The factory derives the next ID from durable storage, so two overlapping
      // drafts would collide unless the service holds one local lock.
      final service = _service(
        sessions,
        cache,
        outbox,
        receipts,
        clock,
        checkoutIdFactory: () => 'co-${outboxBox.keys.length}',
      );

      final records = await Future.wait<CheckoutOutboxRecord>([
        service.createDraft(_request()),
        service.createDraft(_request(quantity: 2)),
      ]);

      expect(records.map((record) => record.checkoutId), ['co-0', 'co-1']);
      expect(outboxBox.keys, hasLength(2));
    },
  );

  test('rejects a reused checkout ID', () async {
    // Every draft draws its own receipt, so a second draft for an existing
    // checkout ID can never describe the same immutable payload.
    final service = _service(
      sessions,
      cache,
      outbox,
      receipts,
      clock,
      checkoutIdFactory: () => 'fixed-checkout',
    );

    final first = await service.createDraft(_request());

    for (final request in [_request(), _request(quantity: 5)]) {
      await expectLater(
        service.createDraft(request),
        throwsA(
          isA<CheckoutOutboxException>().having(
            (error) => error.code,
            'code',
            'checkout_already_exists',
          ),
        ),
      );
    }
    expect(outboxBox.keys, hasLength(1));
    expect(
      (await outbox.read(
        uid: 'user-a',
        tenantId: 'tenant-a',
        checkoutId: 'fixed-checkout',
      ))!.payloadHash,
      first.payloadHash,
      reason: 'A refused reuse must not rewrite stored checkout evidence.',
    );
  });

  test('two cashiers on one device receive different receipts', () async {
    final service = _service(sessions, cache, outbox, receipts, clock);

    final first = await service.createDraft(_request());
    sessions.open(uid: 'user-b', membership: _membership('tenant-a'));
    await cache.write(
      uid: 'user-b',
      tenantId: 'tenant-a',
      configuration: TenantCheckoutConfiguration(currency: 'KES'),
      categories: const [],
      products: [_product('tenant-a', 'product-b', price: 7)],
      complete: true,
    );
    final second = await service.createDraft(_request());

    expect(first.payload['soldById'], 'user-a');
    expect(second.payload['soldById'], 'user-b');
    expect(first.payload['receiptSequence'], 1);
    expect(second.payload['receiptSequence'], 2);
    expect(
      second.payload['receiptNumber'],
      isNot(first.payload['receiptNumber']),
    );
    expect(
      second.payload['deviceId'],
      first.payload['deviceId'],
      reason: 'The counter is deliberately not scoped by cashier UID.',
    );
  });

  test('concurrent drafts never share one receipt number', () async {
    var counter = 0;
    final service = _service(
      sessions,
      cache,
      outbox,
      receipts,
      clock,
      checkoutIdFactory: () => 'co-${counter++}',
    );

    final records = await Future.wait<CheckoutOutboxRecord>([
      service.createDraft(_request()),
      service.createDraft(_request(quantity: 2)),
      service.createDraft(_request(quantity: 3)),
    ]);

    expect(records.map((record) => record.payload['receiptSequence']), [
      1,
      2,
      3,
    ]);
    expect(
      records.map((record) => record.payload['receiptNumber']).toSet(),
      hasLength(3),
    );
  });

  test('a new business date restarts the device sequence', () async {
    final service = _service(sessions, cache, outbox, receipts, clock);
    final deviceId = await receipts.resolveDeviceId();

    // 20:59 UTC is still 2026-07-31 in Africa/Nairobi; 21:00 UTC is not.
    clock.value = DateTime.utc(2026, 7, 31, 20, 59);
    final before = await service.createDraft(_request());
    clock.value = DateTime.utc(2026, 7, 31, 21);
    final after = await service.createDraft(_request(quantity: 2));

    expect(before.payload['businessDate'], '2026-07-31');
    expect(after.payload['businessDate'], '2026-08-01');
    expect(before.payload['receiptSequence'], 1);
    expect(after.payload['receiptSequence'], 1);
    expect(
      before.payload['receiptNumber'],
      formatCheckoutReceiptNumber(
        deviceId: deviceId,
        businessDate: '2026-07-31',
        sequence: 1,
      ),
    );
    expect(
      after.payload['receiptNumber'],
      formatCheckoutReceiptNumber(
        deviceId: deviceId,
        businessDate: '2026-08-01',
        sequence: 1,
      ),
    );
  });

  test('another business keeps its own device sequence', () async {
    final service = _service(sessions, cache, outbox, receipts, clock);
    await service.createDraft(_request());

    sessions.open(uid: 'user-a', membership: _membership('tenant-b'));
    await cache.write(
      uid: 'user-a',
      tenantId: 'tenant-b',
      configuration: TenantCheckoutConfiguration(currency: 'USD'),
      categories: const [],
      products: [_product('tenant-b', 'product-b', price: 7)],
      complete: true,
    );
    final other = await service.createDraft(_request());

    expect(other.payload['receiptSequence'], 1);
    expect(other.payload['currency'], 'USD');
  });

  test('a rejected draft consumes no receipt number', () async {
    final service = _service(sessions, cache, outbox, receipts, clock);

    await expectLater(
      service.createDraft(_request(quantity: 0)),
      throwsA(isA<CheckoutDraftException>()),
    );
    final record = await service.createDraft(_request());

    expect(record.payload['receiptSequence'], 1);
  });

  test('a saved draft blocks tenant switching until it is settled', () async {
    final source = CheckoutOutboxTenantSwitchStateSource(outbox);
    final session = sessions.requireSession();
    expect(
      (await source.inspect(session))!.blocker,
      isNull,
      reason: 'An empty outbox must not block switching.',
    );

    await _service(
      sessions,
      cache,
      outbox,
      receipts,
      clock,
    ).createDraft(_request());

    expect(
      (await source.inspect(session))!.blocker,
      TenantSwitchBlocker.unsynchronizedCheckout,
    );
  });

  test('records the bound shift instead of a caller-supplied one', () async {
    final binder = _Binder(receipts: receipts, clock: clock)
      ..shiftId = 'shift-evening';

    final record = await _service(
      sessions,
      cache,
      outbox,
      receipts,
      clock,
      shiftBinder: binder,
    ).createDraft(_request());

    expect(record.payload['shiftId'], 'shift-evening');
    expect(
      CheckoutSalePayload.fromOutboxRecord(
        record,
        session: sessions.requireSession(),
      ).shiftId,
      'shift-evening',
    );
  });

  test('refuses a checkout with no canonical open shift', () async {
    final binder = _Binder(receipts: receipts, clock: clock)
      ..refusal = 'no_open_shift';

    await expectLater(
      _service(
        sessions,
        cache,
        outbox,
        receipts,
        clock,
        shiftBinder: binder,
      ).createDraft(_request()),
      throwsA(
        isA<CheckoutDraftException>().having(
          (error) => error.code,
          'code',
          'no_open_shift',
        ),
      ),
    );
    expect(outboxBox.keys, isEmpty);
    // A refused checkout still consumes no receipt sequence.
    expect(
      await receipts.lastSequence(
        tenantId: 'tenant-a',
        deviceId: await receipts.resolveDeviceId(),
        businessDate: '2026-07-31',
      ),
      0,
    );
  });

  test('files a sale after midnight under the shift that is open', () async {
    // **A night's trading is one business day, and the shift says which.** A
    // club opens before midnight and sells past it; the shift froze its date
    // at open and the sale takes that date rather than resolving a new one, so
    // the whole night reconciles against the one drawer that served it. The
    // clock here has crossed into the 31st while the shift still names the
    // 30th, which used to refuse every sale from midnight until close.
    clock.value = DateTime.utc(2026, 7, 30, 22, 30);
    final binder = _Binder(receipts: receipts, clock: clock)
      ..businessDate = '2026-07-30';

    final record = await _service(
      sessions,
      cache,
      outbox,
      receipts,
      clock,
      shiftBinder: binder,
    ).createDraft(_request());

    expect(record.payload['businessDate'], '2026-07-30');
    expect(
      CheckoutSalePayload.fromOutboxRecord(
        record,
        session: sessions.requireSession(),
      ).businessDate,
      '2026-07-30',
    );
    // The receipt run belongs to the same night rather than restarting at
    // midnight, because the sequence is allocated against this same date.
    expect(
      await receipts.lastSequence(
        tenantId: 'tenant-a',
        deviceId: await receipts.resolveDeviceId(),
        businessDate: '2026-07-30',
      ),
      1,
    );
  });

  test('refuses a shift whose business date is unreadable', () async {
    final binder = _Binder(receipts: receipts, clock: clock)
      ..businessDate = 'not-a-date';

    await expectLater(
      _service(
        sessions,
        cache,
        outbox,
        receipts,
        clock,
        shiftBinder: binder,
      ).createDraft(_request()),
      throwsA(
        isA<CheckoutDraftException>().having(
          (error) => error.code,
          'code',
          'invalid_business_date',
        ),
      ),
    );
    expect(outboxBox.keys, isEmpty);
  });

  test('refuses a shift that does not describe this sale', () async {
    final foreignDevice = 'dev-${'f' * 32}';
    final cases = <String, void Function(_Binder)>{
      'shift_binding_mismatch': (binder) => binder.uid = 'user-b',
      'shift_binding_mismatch_tenant': (binder) => binder.tenantId = 'tenant-b',
      'shift_binding_mismatch_device': (binder) =>
          binder.deviceId = foreignDevice,
      'invalid_shift_id': (binder) => binder.shiftId = 'shifts/shift-a',
      'checkout_start_unavailable': (binder) =>
          binder.failure = StateError('unreadable'),
    };

    for (final entry in cases.entries) {
      final binder = _Binder(receipts: receipts, clock: clock);
      entry.value(binder);
      final expected = entry.key.startsWith('shift_binding_mismatch')
          ? 'shift_binding_mismatch'
          : entry.key;

      await expectLater(
        _service(
          sessions,
          cache,
          outbox,
          receipts,
          clock,
          shiftBinder: binder,
        ).createDraft(_request()),
        throwsA(
          isA<CheckoutDraftException>().having(
            (error) => error.code,
            'code',
            expected,
          ),
        ),
        reason: entry.key,
      );
    }
    expect(outboxBox.keys, isEmpty);
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
    expect(
      checkoutBusinessDate(DateTime.utc(2026, 1, 1, 20, 59)),
      '2026-01-01',
    );
    expect(checkoutBusinessDate(DateTime.utc(2026, 1, 1, 21)), '2026-01-02');
    expect(checkoutBusinessDate(DateTime.utc(2026, 12, 31, 21)), '2027-01-01');
  });

  group('what the business paid is frozen onto the sale', () {
    Future<void> stock(List<TenantProduct> products) => cache.write(
      uid: 'user-a',
      tenantId: 'tenant-a',
      configuration: TenantCheckoutConfiguration(currency: 'KES'),
      categories: [_category('tenant-a', 'drinks')],
      products: products,
      complete: true,
    );

    Future<CheckoutOutboxRecord> sell(String productId, {int quantity = 1}) =>
        _service(sessions, cache, outbox, receipts, clock).createDraft(
          CheckoutDraftRequest(
            tender: CheckoutTender.cash,
            lines: [
              CheckoutDraftLineRequest(
                productId: productId,
                quantity: quantity,
              ),
            ],
          ),
        );

    test('a sale records the cost the product held at that moment', () async {
      await stock([_product('tenant-a', 'p1', price: 100, cost: 60)]);

      final record = await sell('p1', quantity: 2);
      final line = CheckoutSalePayload.fromOutboxRecord(
        record,
        session: sessions.requireSession(),
      ).lines.single;

      expect(line.unitPriceMinor, 10000);
      expect(line.unitCostMinor, 6000);
      // Derived, not sent: the line total cost is what the server's profit
      // arithmetic subtracts from the line revenue.
      expect(line.lineCostMinor, 12000);
      expect(line.toSaleLineFields()['unitCost'], 60);
      expect(line.toSaleLineFields()['cost'], 120);
    });

    test(
      'correcting the buying price cannot reach a sale already recorded',
      () async {
        // The requirement in one test. A sale is rung up at a cost of 60, the
        // business then corrects the buying price to 90, and the recorded sale
        // must still say 60 - otherwise every profit figure ever reported would
        // move retrospectively whenever a price was corrected.
        await stock([_product('tenant-a', 'p1', price: 100, cost: 60)]);
        final before = await sell('p1');

        // Exactly what `updateProduct` followed by a catalog refresh leaves on
        // this device: the same product, a different cost.
        await stock([_product('tenant-a', 'p1', price: 100, cost: 90)]);
        final after = await sell('p1');

        CheckoutSaleLine lineOf(CheckoutOutboxRecord record) =>
            CheckoutSalePayload.fromOutboxRecord(
              record,
              session: sessions.requireSession(),
            ).lines.single;

        // Re-read from storage rather than from the value returned at save
        // time, because the claim is about what is durable, not about what one
        // call happened to return.
        final stored = await outbox.read(
          uid: 'user-a',
          tenantId: 'tenant-a',
          checkoutId: before.checkoutId,
        );
        expect(lineOf(stored!).unitCostMinor, 6000);
        expect(lineOf(after).unitCostMinor, 9000);
        // And the payload hash still verifies, which is what would refuse the
        // record as `malformed_record` had anything rewritten it in place.
        expect(stored.payloadHash, before.payloadHash);
      },
    );

    test('a product with no recorded cost sells and records none', () async {
      // A missing cost must never refuse a sale: that would stop a till trading
      // over a reporting field. The server counts the line instead.
      await stock([_product('tenant-a', 'p1', price: 100)]);

      final line = CheckoutSalePayload.fromOutboxRecord(
        await sell('p1'),
        session: sessions.requireSession(),
      ).lines.single;

      expect(line.unitCostMinor, isNull);
      expect(line.lineCostMinor, isNull);
      // Absent, not zero. Zero would claim the business paid nothing and report
      // the whole line as profit.
      expect(line.toSaleLineFields().containsKey('unitCost'), isFalse);
      expect(line.toSaleLineFields().containsKey('cost'), isFalse);
    });

    test('a cost the till cannot represent is refused, not dropped', () async {
      // Silently dropping it would report a 100% margin on the one product
      // somebody had actually recorded a cost for.
      await stock([_product('tenant-a', 'p1', price: 100, cost: 60.555)]);

      await expectLater(
        sell('p1'),
        throwsA(
          isA<CheckoutDraftException>().having(
            (error) => error.code,
            'code',
            'cost_not_representable',
          ),
        ),
      );
    });

    test('the encrypted catalog cache carries the cost offline', () async {
      // The till stamps the cost with no network, so the cache is the only
      // place it can come from.
      await stock([
        _product('tenant-a', 'p1', price: 100, cost: 60),
        _product('tenant-a', 'p2', price: 20),
      ]);

      final snapshot = await cache.read(uid: 'user-a', tenantId: 'tenant-a');

      expect(snapshot!.productById('p1')!.cost, 60);
      expect(snapshot.productById('p2')!.cost, isNull);
    });
  });

  group('the receipt hook', () {
    test('is called after the draft is durable, never before', () async {
      // §6.3 applied to printing: the sale is recorded first and the receipt is
      // produced over committed state. The record is already in the outbox by
      // the time the hook runs, which is the whole of the ordering guarantee.
      final seen = <String>[];
      final saved = await _service(
        sessions,
        cache,
        outbox,
        receipts,
        clock,
        onSaved: (record, session) async {
          seen.add(record.checkoutId);
          return null;
        },
      ).saveDraft(_request());

      expect(seen.single, saved.checkoutId);
      expect(saved.receiptPrintFailure, isNull);
    });

    test('a printing failure is carried back, not swallowed', () async {
      final saved = await _service(
        sessions,
        cache,
        outbox,
        receipts,
        clock,
        onSaved: (record, session) async => 'printer_unreachable',
      ).saveDraft(_request());

      expect(saved.receiptPrintFailure, 'printer_unreachable');
      // And the sale still happened, which is the point of carrying the reason
      // back rather than throwing it.
      expect(saved.checkoutId, isNotEmpty);
      expect(saved.receiptNumber, isNotNull);
    });

    test('a hook that throws never un-writes the sale', () async {
      // Anything reaching the catch is a malformed durable print record or a
      // programming error, and neither may lose a sale that is already durable.
      final saved = await _service(
        sessions,
        cache,
        outbox,
        receipts,
        clock,
        onSaved: (record, session) async => throw StateError('box is broken'),
      ).saveDraft(_request());

      expect(saved.receiptPrintFailure, 'receipt_not_queued');
      expect(saved.receiptNumber, isNotNull);
    });

    test('a build with no hook reports no printing failure', () async {
      final saved = await _service(
        sessions,
        cache,
        outbox,
        receipts,
        clock,
      ).saveDraft(_request());

      expect(saved.receiptPrintFailure, isNull);
    });
  });
}

CheckoutDraftRequest _request({int quantity = 1}) => CheckoutDraftRequest(
  tender: CheckoutTender.mpesa,
  lines: [CheckoutDraftLineRequest(productId: 'product-b', quantity: quantity)],
);

CheckoutDraftService _service(
  TenantSessionController sessions,
  HiveCheckoutCatalogCache cache,
  HiveCheckoutOutbox outbox,
  HiveCheckoutReceiptCounters receipts,
  _Clock clock, {
  CheckoutIdFactory? checkoutIdFactory,
  CheckoutShiftBinder? shiftBinder,
  CheckoutDraftReceiptHook? onSaved,
}) => CheckoutDraftService(
  sessionController: sessions,
  cache: cache,
  outbox: outbox,
  receipts: receipts,
  shiftBinder: shiftBinder ?? _Binder(receipts: receipts, clock: clock),
  clock: clock.call,
  checkoutIdFactory: checkoutIdFactory,
  onSaved: onSaved,
);

/// A stand-in for the guarded shift lifecycle that supplies the bound shift.
final class _Binder implements CheckoutShiftBinder {
  _Binder({required this.receipts, required this.clock});

  final HiveCheckoutReceiptCounters receipts;
  final _Clock clock;
  String shiftId = 'shift-a';
  String? refusal;
  String? uid;
  String? tenantId;
  String? deviceId;
  String? businessDate;
  Object? failure;

  @override
  Future<CheckoutShiftBinding> bindCheckoutShift(TenantSession session) async {
    final error = failure;
    if (error != null) throw error;
    final refused = refusal;
    if (refused != null) return CheckoutShiftBinding.refused(refused);
    return CheckoutShiftBinding.bound(
      CheckoutShiftAttribution(
        uid: uid ?? session.uid,
        tenantId: tenantId ?? session.tenantId,
        shiftId: shiftId,
        deviceId: deviceId ?? await receipts.resolveDeviceId(),
        businessDate: businessDate ?? checkoutBusinessDate(clock.value),
      ),
    );
  }
}

final List<int> _encryptionKey = List<int>.generate(
  HiveCheckoutOutbox.encryptionKeyBytes,
  (index) => (index * 5) % 256,
);

TenantProduct _product(
  String tenantId,
  String productId, {
  double price = 10,
  double? cost,
}) => TenantProduct.fromSnapshot(
  TenantQueryDocumentSnapshot(
    path: 'tenants/$tenantId/products/$productId',
    data: <String, Object?>{
      'name': '$productId name',
      'SKU': 'sku-$productId',
      'price': price,
      if (cost != null) 'cost': cost,
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

TenantMembership _membership(
  String tenantId, {
  TenantStatus tenantStatus = TenantStatus.active,
}) => TenantMembership(
  tenantId: tenantId,
  tenantName: tenantId,
  tenantSlug: tenantId,
  role: TenantRole.cashier,
  membershipStatus: MembershipStatus.active,
  tenantStatus: tenantStatus,
  isOwner: false,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);
