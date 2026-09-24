import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/checkout/checkout_receipt.dart';
import 'package:flutter_application_1/checkout/checkout_tender.dart';
import 'package:flutter_application_1/sales/sales.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/scaffold.dart';
import 'package:flutter_test/flutter_test.dart';

const String _deviceA = 'dev-0123456789abcdef0123456789abcdef';
const String _businessDate = '2026-07-31';
const String _payloadHash =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

void main() {
  testWidgets('opening the route issues no read at all', (tester) async {
    final reader = _Reader();

    await _pump(tester, _controller(), reader);

    expect(reader.queries, isEmpty);
    expect(find.byKey(const ValueKey('receipt-lookup-input')), findsOne);
  });

  testWidgets('a malformed receipt is refused before any read', (tester) async {
    final reader = _Reader();

    await _pump(tester, _controller(), reader);
    await _lookUp(tester, 'not a receipt');

    expect(find.byKey(const ValueKey('receipt-lookup-invalid')), findsOne);
    expect(reader.queries, isEmpty);
  });

  testWidgets('a found receipt shows its sale and opens returns', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/sales', <TenantQueryDocumentSnapshot>[
        _snapshot('co-1', sequence: 42),
      ])
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader);
    await _lookUp(tester, _receipt(42));

    expect(reader.queries.single.equalityFilters, <String, Object?>{
      'receiptNumber': _receipt(42),
      'soldById': 'user-a',
    });
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('receipt-lookup-total-co-1')))
          .data,
      'Total: KES 10',
    );

    await tester.tap(find.byKey(const ValueKey('receipt-lookup-returns-co-1')));
    await tester.pumpAndSettle();
    // The return surface is a sheet since 2026-08-26, so the receipt it names
    // sits in the sheet's own header rather than in an `AppBar`.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('sale-returns-header')),
        matching: find.text(_receipt(42)),
      ),
      findsOne,
    );
  });

  testWidgets('a recorded tender is shown as an unverified assertion', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/sales', <TenantQueryDocumentSnapshot>[
        _snapshot('co-1', sequence: 42, tender: CheckoutTender.mpesa),
      ]);

    await _pump(tester, _controller(), reader);
    await _lookUp(tester, _receipt(42));

    final label = tester
        .widget<Text>(find.byKey(const ValueKey('receipt-lookup-tender-co-1')))
        .data;
    expect(label, contains('M-Pesa'));
    // A return starts from this screen, so the payment must never read as
    // confirmed just because a method is named.
    expect(label, contains(checkoutTenderDisclaimer));
  });

  testWidgets('a sale whose tender went unanswered says so plainly', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/sales', <TenantQueryDocumentSnapshot>[
        _snapshot('co-1', sequence: 42),
      ]);

    await _pump(tester, _controller(), reader);
    await _lookUp(tester, _receipt(42));

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('receipt-lookup-tender-co-1')),
          )
          .data,
      checkoutTenderUnrecordedMessage,
    );
  });

  testWidgets('a receipt with no sale says so', (tester) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/sales', <TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader);
    await _lookUp(tester, _receipt(9));

    expect(find.byKey(const ValueKey('receipt-lookup-missing')), findsOne);
  });

  testWidgets('a colliding receipt lists every candidate', (tester) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/sales', <TenantQueryDocumentSnapshot>[
        _snapshot('co-1', sequence: 7),
        _snapshot('co-2', sequence: 7),
      ]);

    await _pump(tester, _controller(), reader);
    await _lookUp(tester, _receipt(7));

    expect(find.byKey(const ValueKey('receipt-lookup-ambiguous')), findsOne);
    expect(find.byKey(const ValueKey('receipt-lookup-sale-co-1')), findsOne);
    expect(find.byKey(const ValueKey('receipt-lookup-sale-co-2')), findsOne);
  });

  testWidgets('a sale from another business fails the lookup closed', (
    tester,
  ) async {
    final reader = _Reader(responsePrefix: 'tenants/tenant-b/sales')
      ..respond('tenants/tenant-a/sales', <TenantQueryDocumentSnapshot>[
        _snapshot('co-1', sequence: 42),
      ]);

    await _pump(tester, _controller(), reader);
    await _lookUp(tester, _receipt(42));

    expect(find.byKey(const ValueKey('receipt-lookup-failure')), findsOne);
    expect(
      find.byKey(const ValueKey('receipt-lookup-sale-co-1')),
      findsNothing,
    );
  });

  testWidgets('no session renders the denied state and starts no read', (
    tester,
  ) async {
    final reader = _Reader();

    await _pump(tester, TenantSessionController(), reader);
    await _lookUp(tester, _receipt(42));

    expect(find.byKey(const ValueKey('receipt-lookup-denied')), findsOne);
    expect(reader.queries, isEmpty);
  });

  testWidgets('a tenant switch discards the outstanding lookup', (
    tester,
  ) async {
    final controller = _controller();
    final reader = _Reader(deferred: true)
      ..respond('tenants/tenant-a/sales', <TenantQueryDocumentSnapshot>[
        _snapshot('co-1', sequence: 42),
      ])
      ..respond('tenants/tenant-b/sales', <TenantQueryDocumentSnapshot>[
        _snapshot('co-9', sequence: 42, tenantId: 'tenant-b'),
      ]);

    await _pump(tester, controller, reader);
    await _lookUp(tester, _receipt(42), settle: false);
    await tester.pump();
    expect(reader.pending.length, 1);

    controller.open(uid: 'user-a', membership: _membership('tenant-b'));
    await tester.pump();
    reader.completeFirst();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('receipt-lookup-sale-co-1')),
      findsNothing,
    );

    // The new business answers the same receipt with its own sale, which is
    // correct: a receipt is only ever looked up inside one business.
    reader.completeFirst();
    await tester.pump();
    expect(find.byKey(const ValueKey('receipt-lookup-sale-co-9')), findsOne);
  });
}

Future<void> _lookUp(
  WidgetTester tester,
  String receipt, {
  bool settle = true,
}) async {
  await tester.enterText(
    find.byKey(const ValueKey('receipt-lookup-input')),
    receipt,
  );
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('receipt-lookup-submit')));
  if (!settle) {
    await tester.pump();
    return;
  }
  await tester.pump();
  await tester.pump();
}

Future<void> _pump(
  WidgetTester tester,
  TenantSessionController controller,
  _Reader reader,
) async {
  tester.view.physicalSize = const Size(1400, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: TenantReceiptLookupScreen(reader: reader),
      ),
    ),
  );
  await tester.pump();
}

String _receipt(int sequence) => formatCheckoutReceiptNumber(
  deviceId: _deviceA,
  businessDate: _businessDate,
  sequence: sequence,
);

TenantSessionController _controller({TenantRole role = TenantRole.cashier}) =>
    TenantSessionController()..open(
      uid: 'user-a',
      membership: _membership('tenant-a', role: role),
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
  isOwner: role == TenantRole.owner,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 7, 31),
  updatedAt: DateTime.utc(2026, 7, 31),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);

TenantQueryDocumentSnapshot _snapshot(
  String saleId, {
  int sequence = 1,
  String tenantId = 'tenant-a',
  CheckoutTender? tender,
}) => TenantQueryDocumentSnapshot(
  path: 'tenants/$tenantId/sales/$saleId',
  data: <String, Object?>{
    'checkoutId': saleId,
    'tenantId': tenantId,
    'soldById': 'user-a',
    'payloadHash': _payloadHash,
    // #105: v1 is gone, and an absent tender no longer implies it. A v2 sale
    // may carry no tender - that is the question going unanswered, which
    // `setSaleTender` fills in later.
    'payloadSchemaVersion': 2,
    if (tender != null) 'tender': tender.wireValue,
    'currency': 'KES',
    'businessDate': _businessDate,
    'shiftId': 'shift-a',
    'deviceId': _deviceA,
    'receiptNumber': _receipt(sequence),
    'receiptSequence': sequence,
    'items': <Object?>[
      <String, Object?>{
        'productId': 'product-1',
        'name': 'Tusker',
        'quantity': 2,
        'unitPriceMinor': 500,
        'lineTotalMinor': 1000,
      },
    ],
    'subtotalMinor': 1000,
    'subtotal': 10.0,
    'discountMinor': 0,
    'discount': 0.0,
    'totalMinor': 1000,
    'total': 10.0,
    'createdAt': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 12)),
  },
);

final class _Reader implements TenantDataReader {
  _Reader({this.deferred = false, this.responsePrefix});

  final bool deferred;

  /// Stands in for a transport that answered outside the requested tenant.
  final String? responsePrefix;
  final Map<String, List<TenantQueryDocumentSnapshot>> _pages =
      <String, List<TenantQueryDocumentSnapshot>>{};
  final List<TenantCollectionQuery> queries = <TenantCollectionQuery>[];
  final List<Completer<List<TenantQueryDocumentSnapshot>>> pending =
      <Completer<List<TenantQueryDocumentSnapshot>>>[];
  final List<List<TenantQueryDocumentSnapshot>> _deferredResults =
      <List<TenantQueryDocumentSnapshot>>[];

  void respond(String path, List<TenantQueryDocumentSnapshot> page) =>
      _pages[path] = page;

  void completeFirst() {
    if (pending.isEmpty) return;
    pending.removeAt(0).complete(_deferredResults.removeAt(0));
  }

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async => null;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) {
    queries.add(query);
    final all = _pages[query.collectionPath] ?? const [];
    final matches = <TenantQueryDocumentSnapshot>[];
    for (final snapshot in all) {
      final matchesFilters = query.equalityFilters.entries.every(
        (filter) => snapshot.data[filter.key] == filter.value,
      );
      if (!matchesFilters) continue;
      final prefix = responsePrefix;
      matches.add(
        prefix == null
            ? snapshot
            : TenantQueryDocumentSnapshot(
                path: '$prefix/${snapshot.path.split('/').last}',
                data: snapshot.data,
              ),
      );
      if (matches.length >= query.limit) break;
    }
    if (!deferred) return Future.value(matches);
    final completer = Completer<List<TenantQueryDocumentSnapshot>>();
    pending.add(completer);
    _deferredResults.add(matches);
    return completer.future;
  }
}
