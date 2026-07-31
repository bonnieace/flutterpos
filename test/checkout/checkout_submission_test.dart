import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;
  late CheckoutSaleSubmission submission;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('submission-test-');
    Hive.init(directory.path);
    final box = await Hive.openBox<dynamic>('submission-test');
    final outbox = HiveCheckoutOutbox.fromBox(
      box,
      clock: () => DateTime.utc(2026, 7, 31, 9),
    );
    final record = await outbox.saveOffline(
      uid: 'user-a',
      tenantId: 'tenant-a',
      checkoutId: 'checkout-a',
      payload: _payload,
    );
    submission = CheckoutSalePayload.fromOutboxRecord(
      record,
      session: TenantSession.active(
        uid: 'user-a',
        tenantId: 'tenant-a',
        role: TenantRole.cashier,
      ),
    ).toSubmission();
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('commits one atomic tenant-scoped batch while online', () async {
    final committed = <CheckoutSaleSubmission>[];
    final gateway = FirebaseCheckoutSubmissionGateway.forTesting(
      isOnline: () async => true,
      commit: (attempt) async => committed.add(attempt),
    );

    final result = await gateway.submit(submission);

    expect(result.kind, CheckoutSubmissionKind.committed);
    expect(committed.length, 1);
    expect(committed.single.salePath, 'tenants/tenant-a/sales/checkout-a');
    expect(
      committed.single.stockDecrements
          .map((decrement) => (decrement.productPath, decrement.quantityDelta))
          .toList(),
      [
        ('tenants/tenant-a/products/product-a', -2),
        ('tenants/tenant-a/products/product-b', -3),
      ],
    );
    expect(committed.single.saleServerTimestampFields, <String>['createdAt']);
    expect(committed.single.saleFields['payloadHash'], isA<String>());
  });

  test('never attempts a write while offline', () async {
    var commits = 0;
    final gateway = FirebaseCheckoutSubmissionGateway.forTesting(
      isOnline: () async => false,
      commit: (_) async => commits++,
    );

    expect(
      (await gateway.submit(submission)).kind,
      CheckoutSubmissionKind.unavailable,
    );
    expect(commits, 0);

    final failingCheck = FirebaseCheckoutSubmissionGateway.forTesting(
      isOnline: () async => throw StateError('connectivity unavailable'),
      commit: (_) async => commits++,
    );
    expect(
      (await failingCheck.submit(submission)).kind,
      CheckoutSubmissionKind.unavailable,
    );
    expect(commits, 0);
  });

  test('classifies definitive server refusals as rejected', () async {
    for (final code in [
      'permission-denied',
      'unauthenticated',
      'invalid-argument',
      'not-found',
      'already-exists',
      'failed-precondition',
    ]) {
      final result = await _failing(code).submit(submission);
      expect(result.kind, CheckoutSubmissionKind.rejected, reason: code);
      expect(result.reasonCode, code);
    }
  });

  test('classifies uncertain outcomes as ambiguous', () async {
    for (final code in [
      'unavailable',
      'deadline-exceeded',
      'aborted',
      'internal',
      'cancelled',
      'resource-exhausted',
      'unknown',
    ]) {
      final result = await _failing(code).submit(submission);
      expect(result.kind, CheckoutSubmissionKind.ambiguous, reason: code);
      expect(result.reasonCode, code);
    }

    final nonFirebase = FirebaseCheckoutSubmissionGateway.forTesting(
      isOnline: () async => true,
      commit: (_) async => throw StateError('transport closed'),
    );
    final result = await nonFirebase.submit(submission);
    expect(result.kind, CheckoutSubmissionKind.ambiguous);
    expect(result.reasonCode, 'unknown_error');
  });

  test('an unacknowledged commit is ambiguous, never rejected', () async {
    final pending = Completer<void>();
    final gateway = FirebaseCheckoutSubmissionGateway.forTesting(
      isOnline: () async => true,
      commit: (_) => pending.future,
      commitTimeout: const Duration(milliseconds: 5),
    );

    final result = await gateway.submit(submission);

    expect(result.kind, CheckoutSubmissionKind.ambiguous);
    expect(result.reasonCode, 'commit_timeout');
  });
}

FirebaseCheckoutSubmissionGateway _failing(String code) =>
    FirebaseCheckoutSubmissionGateway.forTesting(
      isOnline: () async => true,
      commit: (_) async =>
          throw FirebaseException(plugin: 'cloud_firestore', code: code),
    );

const Map<String, Object?> _payload = <String, Object?>{
  'schemaVersion': checkoutSalePayloadSchemaVersion,
  'checkoutId': 'checkout-a',
  'tenantId': 'tenant-a',
  'soldById': 'user-a',
  'currency': 'KES',
  'businessDate': '2026-07-31',
  'createdAtMs': 1785484800000,
  'items': <Map<String, Object?>>[
    {
      'productId': 'product-a',
      'name': 'Coffee',
      'quantity': 2,
      'unitPriceMinor': 25000,
    },
    {
      'productId': 'product-b',
      'name': 'Tea',
      'quantity': 3,
      'unitPriceMinor': 10000,
    },
  ],
  'subtotalMinor': 80000,
  'discountMinor': 0,
  'totalMinor': 80000,
};
