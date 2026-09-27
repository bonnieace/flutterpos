import 'dart:io';
import 'dart:math';

import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:uzapay_pos/shift/shift.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

const String _businessDate = '2026-07-31';

void main() {
  late Directory directory;
  late Box<dynamic> shiftBox;
  late Box<dynamic> outboxBox;
  late Box<dynamic> cacheBox;
  late Box<dynamic> receiptBox;
  late HiveTenantShiftState shiftState;
  late HiveCheckoutOutbox outbox;
  late HiveCheckoutCatalogCache cache;
  late HiveCheckoutReceiptCounters receipts;
  late TenantSessionController sessions;
  late String deviceId;

  DateTime clock() => DateTime.utc(2026, 7, 31, 9, 30);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('shift-binder-test-');
    Hive.init(directory.path);
    shiftBox = await _open(HiveTenantShiftState.boxName);
    outboxBox = await _open(HiveCheckoutOutbox.boxName);
    cacheBox = await _open(HiveCheckoutCatalogCache.boxName);
    receiptBox = await _open(HiveCheckoutReceiptCounters.boxName);
    shiftState = HiveTenantShiftState.fromBox(shiftBox, clock: clock);
    outbox = HiveCheckoutOutbox.fromBox(outboxBox, clock: clock);
    cache = HiveCheckoutCatalogCache.fromBox(cacheBox, clock: clock);
    receipts = HiveCheckoutReceiptCounters.fromBox(
      receiptBox,
      clock: clock,
      random: Random(11),
    );
    // Every shift and receipt this device records names the same installation.
    deviceId = await receipts.resolveDeviceId();
    sessions = TenantSessionController()
      ..open(uid: 'user-a', membership: _membership('tenant-a'));
    await cache.write(
      uid: 'user-a',
      tenantId: 'tenant-a',
      configuration: TenantCheckoutConfiguration(currency: 'KES'),
      categories: [_category('tenant-a', 'drinks')],
      products: [_product('tenant-a', 'product-a')],
      complete: true,
    );
  });

  tearDown(() async {
    sessions.dispose();
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('binds a checkout to the confirmed open shift', () async {
    await shiftState.save(_record(deviceId: deviceId));

    final record = await _service(
      sessions,
      cache,
      outbox,
      receipts,
      shiftState,
      clock,
    ).createDraft(_request());

    expect(record.state, CheckoutOutboxState.savedOffline);
    expect(record.payload['shiftId'], 'shift-a');
    expect(
      CheckoutSalePayload.fromOutboxRecord(
        record,
        session: sessions.requireSession(),
      ).shiftId,
      'shift-a',
    );
  });

  test('refuses a checkout with no shift for this business', () async {
    await expectLater(
      _service(
        sessions,
        cache,
        outbox,
        receipts,
        shiftState,
        clock,
      ).createDraft(_request()),
      throwsA(_draftCode('no_open_shift')),
    );

    expect(
      await outbox.recordsForSession(uid: 'user-a', tenantId: 'tenant-a'),
      isEmpty,
    );
    // The refused checkout consumed no receipt sequence.
    expect(
      await receipts.lastSequence(
        tenantId: 'tenant-a',
        deviceId: deviceId,
        businessDate: _businessDate,
      ),
      0,
    );
  });

  test('a cashier cannot start a checkout in a second business', () async {
    await shiftState.save(_record(deviceId: deviceId));
    await shiftState.save(
      _record(tenantId: 'tenant-b', shiftId: 'shift-b', deviceId: deviceId),
    );

    await expectLater(
      _service(
        sessions,
        cache,
        outbox,
        receipts,
        shiftState,
        clock,
      ).createDraft(_request()),
      throwsA(_draftCode('other_tenant_shift_open')),
    );
    expect(
      await outbox.recordsForSession(uid: 'user-a', tenantId: 'tenant-a'),
      isEmpty,
    );
  });

  test('a manager may still check out while inspecting elsewhere', () async {
    await shiftState.save(_record(deviceId: deviceId));
    await shiftState.save(
      _record(tenantId: 'tenant-b', shiftId: 'shift-b', deviceId: deviceId),
    );
    sessions.open(
      uid: 'user-a',
      membership: _membership('tenant-a', role: TenantRole.manager),
    );

    final record = await _service(
      sessions,
      cache,
      outbox,
      receipts,
      shiftState,
      clock,
    ).createDraft(_request());

    expect(record.state, CheckoutOutboxState.savedOffline);
  });

  test('another identity on the device never blocks this cashier', () async {
    await shiftState.save(_record(deviceId: deviceId));
    await shiftState.save(
      _record(
        uid: 'user-b',
        tenantId: 'tenant-b',
        shiftId: 'shift-b',
        deviceId: deviceId,
      ),
    );

    final record = await _service(
      sessions,
      cache,
      outbox,
      receipts,
      shiftState,
      clock,
    ).createDraft(_request());

    expect(record.state, CheckoutOutboxState.savedOffline);
  });

  test('an unreadable shift state refuses the checkout', () async {
    await shiftBox.put('user-a:tenant-b', <String, Object?>{
      'schemaVersion': 99,
    });

    await expectLater(
      _service(
        sessions,
        cache,
        outbox,
        receipts,
        shiftState,
        clock,
      ).createDraft(_request()),
      throwsA(_draftCode('checkout_start_unavailable')),
    );
    expect(
      await outbox.recordsForSession(uid: 'user-a', tenantId: 'tenant-a'),
      isEmpty,
    );
  });

  test('sells against a shift the server has not confirmed yet', () async {
    await shiftState.save(
      _record(deviceId: deviceId, serverConfirmedOpen: false),
    );

    // **The offline till's whole reason for existing.** A shift opened with no
    // network is never server-confirmed, so requiring confirmation here shut
    // the till for the length of the outage. The sale names the same shift ID
    // the replayed open will carry, so the two meet at the server whichever
    // lands first.
    final saved = await _service(
      sessions,
      cache,
      outbox,
      receipts,
      shiftState,
      clock,
    ).createDraft(_request());

    expect(saved.payload['shiftId'], 'shift-a');
  });

  test('refuses a checkout on a shift closed here and not yet sent', () async {
    await shiftState.save(
      _record(
        deviceId: deviceId,
        closeInProgress: true,
        closedAt: DateTime.utc(2026, 9, 5, 18),
      ),
    );

    // The count is over and its figures are fixed. A sale after them would be
    // a variance the shop has to explain.
    await expectLater(
      _service(
        sessions,
        cache,
        outbox,
        receipts,
        shiftState,
        clock,
      ).createDraft(_request()),
      throwsA(_draftCode('shift_closed_pending')),
    );
  });

  test('refuses a checkout once the cash count started', () async {
    await shiftState.save(_record(deviceId: deviceId, closeInProgress: true));

    await expectLater(
      _service(
        sessions,
        cache,
        outbox,
        receipts,
        shiftState,
        clock,
      ).createDraft(_request()),
      throwsA(_draftCode('shift_closing')),
    );
  });

  test('sells across midnight under the day the shift named', () async {
    // The shift stayed open across the Africa/Nairobi day boundary, which is
    // what a night's trading looks like. Nightly reconciliation aggregates per
    // shift and business date, and the sale carries the shift's date, so the
    // whole night lands on the day that drawer was opened for.
    await shiftState.save(
      _record(deviceId: deviceId, businessDate: '2026-07-30'),
    );

    final record = await _service(
      sessions,
      cache,
      outbox,
      receipts,
      shiftState,
      clock,
    ).createDraft(_request());

    expect(record.payload['businessDate'], '2026-07-30');
    expect(
      await outbox.recordsForSession(uid: 'user-a', tenantId: 'tenant-a'),
      hasLength(1),
    );
  });

  test('refuses a shift opened on another device', () async {
    await shiftState.save(
      _record(deviceId: 'dev-fedcba9876543210fedcba9876543210'),
    );

    await expectLater(
      _service(
        sessions,
        cache,
        outbox,
        receipts,
        shiftState,
        clock,
      ).createDraft(_request()),
      throwsA(_draftCode('shift_binding_mismatch')),
    );
  });

  test('a shift past the cap no longer binds a sale', () async {
    // **N4.** The 24-hour cap used to be a property of the screen and of
    // nothing else: `TenantShiftPhase.expired` stopped the gate drawing a till,
    // and the binder - the one thing every sale goes through - never asked. So
    // the picture refused and the till accepted, and since nothing recomputes
    // expiry while a till is open, a device left running kept selling past it.
    await shiftState.save(_record(deviceId: deviceId));
    final binder = TenantShiftCheckoutBinder(
      shiftState,
      // One minute past a day after the shift opened.
      clock: () => DateTime.utc(2026, 8, 1, 9, 1),
    );

    final binding = await binder.bindCheckoutShift(
      _session(TenantRole.cashier),
    );

    expect(binding.refusalCode, 'shift_expired');
  });

  test('a shift inside the cap still binds', () async {
    await shiftState.save(_record(deviceId: deviceId));
    final binder = TenantShiftCheckoutBinder(
      shiftState,
      // One minute short of a day, which is still a trading shift.
      clock: () => DateTime.utc(2026, 8, 1, 8, 59),
    );

    final binding = await binder.bindCheckoutShift(
      _session(TenantRole.cashier),
    );

    expect(binding.refusalCode, isNull);
  });

  test('the binder itself answers only for this exact session', () async {
    await shiftState.save(_record(deviceId: deviceId));
    await shiftState.save(
      _record(tenantId: 'tenant-b', shiftId: 'shift-b', deviceId: deviceId),
    );
    // The fixtures open their shifts on the same morning the suite's clock
    // reads, so the binder measures the cap against that rather than against
    // a wall clock months later.
    final binder = TenantShiftCheckoutBinder(shiftState, clock: clock);

    expect(
      (await binder.bindCheckoutShift(
        _session(TenantRole.cashier),
      )).refusalCode,
      'other_tenant_shift_open',
    );
    for (final role in <TenantRole>[
      TenantRole.owner,
      TenantRole.admin,
      TenantRole.manager,
    ]) {
      final binding = await binder.bindCheckoutShift(_session(role));
      expect(binding.refusalCode, isNull);
      expect(binding.attribution!.shiftId, 'shift-a');
      expect(binding.attribution!.tenantId, 'tenant-a');
      expect(binding.attribution!.uid, 'user-a');
    }
  });
}

Future<Box<dynamic>> _open(String name) => Hive.openBox<dynamic>(
  name,
  encryptionCipher: HiveAesCipher(_encryptionKey),
  crashRecovery: false,
);

final List<int> _encryptionKey = List<int>.generate(
  HiveCheckoutOutbox.encryptionKeyBytes,
  (index) => (index * 3) % 256,
);

CheckoutDraftService _service(
  TenantSessionController sessions,
  HiveCheckoutCatalogCache cache,
  HiveCheckoutOutbox outbox,
  HiveCheckoutReceiptCounters receipts,
  HiveTenantShiftState shiftState,
  DateTime Function() clock,
) => CheckoutDraftService(
  sessionController: sessions,
  cache: cache,
  outbox: outbox,
  receipts: receipts,
  shiftBinder: TenantShiftCheckoutBinder(shiftState, clock: clock),
  clock: clock,
);

CheckoutDraftRequest _request() => CheckoutDraftRequest(
  tender: CheckoutTender.cash,
  lines: const [CheckoutDraftLineRequest(productId: 'product-a', quantity: 1)],
);

Matcher _draftCode(String code) =>
    isA<CheckoutDraftException>().having((error) => error.code, 'code', code);

TenantSession _session(TenantRole role) =>
    TenantSession.active(uid: 'user-a', tenantId: 'tenant-a', role: role);

TenantShiftLocalRecord _record({
  required String deviceId,
  String uid = 'user-a',
  String tenantId = 'tenant-a',
  String shiftId = 'shift-a',
  String businessDate = _businessDate,
  bool serverConfirmedOpen = true,
  bool closeInProgress = false,
  DateTime? closedAt,
  DateTime? openedAt,
}) => TenantShiftLocalRecord(
  uid: uid,
  tenantId: tenantId,
  shiftId: shiftId,
  businessDate: businessDate,
  deviceId: deviceId,
  serverConfirmedOpen: serverConfirmedOpen,
  closeInProgress: closeInProgress,
  closedAt: closedAt,
  updatedAt: DateTime.utc(2026, 7, 31, 9),
  openedAt: openedAt ?? DateTime.utc(2026, 7, 31, 9),
);

TenantProduct _product(String tenantId, String productId) =>
    TenantProduct.fromSnapshot(
      TenantQueryDocumentSnapshot(
        path: 'tenants/$tenantId/products/$productId',
        data: <String, Object?>{
          'name': '$productId name',
          'SKU': 'sku-$productId',
          'price': 10.0,
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

TenantMembership _membership(
  String tenantId, {
  TenantRole role = TenantRole.cashier,
}) => TenantMembership(
  tenantId: tenantId,
  tenantName: tenantId,
  tenantSlug: tenantId,
  role: role,
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
