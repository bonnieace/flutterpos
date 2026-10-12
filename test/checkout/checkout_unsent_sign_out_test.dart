import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:uzapay_pos/checkout/checkout_unsent_sign_out.dart';
import 'package:uzapay_pos/theme.dart';

void main() {
  test('counts only this person’s unsent sales in this business', () async {
    // In memory: Hive's disk writes never settle inside a widget test's
    // clock, and the count only reads.
    final outbox = HiveCheckoutOutbox.fromBox(
      await Hive.openBox<dynamic>('unsent-sign-out', bytes: Uint8List(0)),
    );
    addTearDown(outbox.close);
    Future<void> sell(String uid, String tenantId, int index) =>
        outbox.saveOffline(
          uid: uid,
          tenantId: tenantId,
          checkoutId: 'checkout-$index',
          payload: _sale(
            checkoutId: 'checkout-$index',
            uid: uid,
            tenantId: tenantId,
            sequence: index,
          ),
        );
    await sell('user-a', 'tenant-a', 1);
    await sell('user-a', 'tenant-a', 2);
    await sell('user-a', 'tenant-b', 3);
    await sell('user-b', 'tenant-a', 4);

    expect(
      await unsentSalesFor(outbox, uid: 'user-a', tenantId: 'tenant-a'),
      2,
    );
    expect(
      await unsentSalesFor(outbox, uid: 'user-c', tenantId: 'tenant-a'),
      0,
    );
  });

  group('the question', () {
    Future<bool?> ask(WidgetTester tester, {required int unsent}) async {
      bool? answer;
      await tester.pumpWidget(
        MaterialApp(
          theme: spiritTheme,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => answer =
                  await confirmSignOutWithUnsentSales(context, unsent: unsent),
              child: const Text('Sign out'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      return answer;
    }

    testWidgets('says how many, and staying is the default', (tester) async {
      await ask(tester, unsent: 3);

      expect(find.text('Sign out with 3 sales not sent?'), findsOneWidget);
      expect(find.textContaining('they are lost'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sign-out-unsent-stay')));
      await tester.pumpAndSettle();
      expect(find.text('Sign out with 3 sales not sent?'), findsNothing);
    });

    testWidgets('one sale is a sale, not "1 sales"', (tester) async {
      await ask(tester, unsent: 1);

      expect(find.text('Sign out with a sale not sent?'), findsOneWidget);
      expect(find.textContaining('it is lost'), findsOneWidget);
    });

    testWidgets('answers yes only for "Sign out anyway"', (tester) async {
      bool? answer;
      await tester.pumpWidget(
        MaterialApp(
          theme: spiritTheme,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => answer =
                  await confirmSignOutWithUnsentSales(context, unsent: 2),
              child: const Text('Sign out'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sign-out-unsent-stay')));
      await tester.pumpAndSettle();
      expect(answer, isFalse);

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      // A tap outside is a stay, never a sign-out.
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(answer, isFalse);

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sign-out-unsent-confirm')));
      await tester.pumpAndSettle();
      expect(answer, isTrue);
    });
  });
}

Map<String, Object?> _sale({
  required String checkoutId,
  required String uid,
  required String tenantId,
  required int sequence,
}) {
  const deviceId = 'dev-0123456789abcdef0123456789abcdef';
  final soldAt = DateTime.utc(2026, 10, 10, 9);
  final businessDate = checkoutBusinessDate(soldAt);
  return <String, Object?>{
    'schemaVersion': checkoutSalePayloadSchemaVersion,
    'checkoutId': checkoutId,
    'tenantId': tenantId,
    'soldById': uid,
    'currency': 'KES',
    'businessDate': businessDate,
    'createdAtMs': soldAt.millisecondsSinceEpoch,
    'shiftId': 'shift-a',
    'deviceId': deviceId,
    'receiptNumber': formatCheckoutReceiptNumber(
      deviceId: deviceId,
      businessDate: businessDate,
      sequence: sequence,
    ),
    'receiptSequence': sequence,
    'tender': 'cash',
    'items': <Object?>[
      <String, Object?>{
        'productId': 'product-$checkoutId',
        'name': 'Item',
        'categoryId': 'category-a',
        'quantity': 1,
        'unitPriceMinor': 6000,
        'unitCostMinor': 0,
      },
    ],
    'subtotalMinor': 6000,
    'discountMinor': 0,
    'totalMinor': 6000,
  };
}
