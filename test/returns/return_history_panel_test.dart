import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/checkout/checkout_receipt.dart';
import 'package:flutter_application_1/returns/returns.dart';
import 'package:flutter_application_1/sales/sales.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

const String _deviceA = 'dev-0123456789abcdef0123456789abcdef';
const String _businessDate = '2026-07-31';
const String _payloadHash =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

void main() {
  testWidgets('verified and pending returns are shown distinctly', (
    tester,
  ) async {
    final reader = _Reader(staffNames: <String, String>{'manager-a': 'Amina'})
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _verified('ret-2'),
        _pending('ret-1'),
      ]);

    await _pump(tester, _controller(), reader);

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sale-returns-counts')))
          .data,
      'On this page: 1 verified, 1 pending.',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sale-returns-status-ret-2')))
          .data,
      'Verified - stock restored',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sale-returns-status-ret-1')))
          .data,
      'Pending verification',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('sale-returns-verified-ret-2')),
          )
          .data,
      'Verified 2026-08-01 06:00 UTC by Amina (manager-a)',
    );
    // A pending return has restored nothing, so it names no verifier.
    expect(
      find.byKey(const ValueKey('sale-returns-verified-ret-1')),
      findsNothing,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sale-returns-lines-ret-1')))
          .data,
      '3 units across 2 products: 2 x Tusker, 1 x product-2',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('sale-returns-recorded-ret-1')),
          )
          .data,
      'Recorded 2026-07-31 12:00 UTC by You',
    );
  });

  testWidgets('a sale with no returns says so', (tester) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader);

    expect(find.byKey(const ValueKey('sale-returns-empty')), findsOne);
    expect(find.byKey(const ValueKey('sale-returns-counts')), findsNothing);
    expect(reader.queries.single.equalityFilters, <String, Object?>{
      'saleId': 'co-1',
    });
    expect(reader.queries.single.descending, isTrue);
  });

  testWidgets('a return that names another sale hides the whole page', (
    tester,
  ) async {
    final reader = _Reader(ignoreFilters: true)
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _pending('ret-1', overrides: <String, Object?>{'saleId': 'co-9'}),
      ]);

    await _pump(tester, _controller(), reader);

    expect(find.byKey(const ValueKey('sale-returns-failure')), findsOne);
    expect(find.byKey(const ValueKey('sale-returns-entry-ret-1')), findsNothing);
  });

  testWidgets('a return whose state contradicts itself hides the page', (
    tester,
  ) async {
    // The verification callable would refuse this document; offering it as
    // pending would invite an action that can never succeed.
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _pending('ret-1', overrides: <String, Object?>{'stockRestored': true}),
      ]);

    await _pump(tester, _controller(), reader);

    expect(find.byKey(const ValueKey('sale-returns-failure')), findsOne);
  });

  testWidgets('returns page forward and back', (tester) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _pending('ret-3'),
        _pending('ret-2'),
        _pending('ret-1'),
      ]);

    await _pump(tester, _controller(), reader, pageSize: 2);
    expect(find.byKey(const ValueKey('sale-returns-entry-ret-1')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('sale-returns-next')));
    await tester.pump();
    await tester.pump();
    expect(reader.queries.last.startAfterDocumentId, 'ret-2');
    expect(find.byKey(const ValueKey('sale-returns-entry-ret-1')), findsOne);

    await tester.tap(find.byKey(const ValueKey('sale-returns-previous')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('sale-returns-entry-ret-3')), findsOne);
  });

  testWidgets('a tenant switch discards the outstanding returns page', (
    tester,
  ) async {
    final controller = _controller();
    final reader = _Reader(deferred: true)
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _pending('ret-1'),
      ])
      ..respond('tenants/tenant-b/returns', <TenantQueryDocumentSnapshot>[
        _pending('ret-9', tenantId: 'tenant-b'),
      ]);

    await _pump(tester, controller, reader, settle: false);
    await tester.pump();
    expect(reader.pending.length, 1);

    controller.open(uid: 'user-a', membership: _membership('tenant-b'));
    await tester.pump();
    reader.completeFirst();
    await tester.pump();
    expect(find.byKey(const ValueKey('sale-returns-entry-ret-1')), findsNothing);

    reader.completeFirst();
    await tester.pump();
    // The route was opened for a sale in the previous business, so the new
    // session cannot answer it. Another business's returns are never shown
    // under that sale's receipt, even if a sale ID coincided.
    expect(find.byKey(const ValueKey('sale-returns-entry-ret-9')), findsNothing);
    expect(find.byKey(const ValueKey('sale-returns-entry-ret-1')), findsNothing);
    expect(find.byKey(const ValueKey('sale-returns-failure')), findsOne);
  });

  testWidgets('an unreadable staff record leaves the UID in place', (
    tester,
  ) async {
    final reader = _Reader(deniedStaff: true)
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _verified('ret-2'),
      ]);

    await _pump(tester, _controller(), reader);

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('sale-returns-verified-ret-2')),
          )
          .data,
      'Verified 2026-08-01 06:00 UTC by manager-a',
    );
    expect(find.byKey(const ValueKey('sale-returns-failure')), findsNothing);
  });

  testWidgets('no session renders the denied state and starts no load', (
    tester,
  ) async {
    final reader = _Reader();

    await _pump(tester, TenantSessionController(), reader);

    expect(find.byKey(const ValueKey('sale-returns-denied')), findsOne);
    expect(reader.queries, isEmpty);
  });

  testWidgets('the route names the receipt it is reversing', (tester) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[]);

    await tester.pumpWidget(
      MaterialApp(
        home: TenantSessionScope(
          controller: _controller(),
          child: TenantSaleReturnsScreen(reader: reader, request: _request()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Returns'), findsOne);
    expect(find.text('Returns against ${_receipt(1)}'), findsOne);
  });

  testWidgets('without a writer the route stays read-only', (tester) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader);

    expect(find.byKey(const ValueKey('sale-returns-form')), findsNothing);
    expect(find.byKey(const ValueKey('sale-returns-submit')), findsNothing);
  });

  testWidgets('the form states what is still available to return', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _pending('ret-1'),
      ]);

    await _pump(tester, _controller(), reader, writer: _Writer());

    // Two of product-1 and one of product-2 are already recorded as pending,
    // and pending units count against what may still be requested.
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('sale-returns-remaining-product-1')),
          )
          .data,
      'Tusker: 2 of 4 available',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('sale-returns-remaining-product-2')),
          )
          .data,
      'Water: 4 of 5 available',
    );
  });

  testWidgets('recording a return needs quantities, a reason, and a confirm', (
    tester,
  ) async {
    final writer = _Writer();
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader, writer: writer);

    // Nothing selected and no reason: the action is unavailable.
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('sale-returns-submit')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const ValueKey('sale-returns-increase-product-1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sale-returns-increase-product-1')));
    await tester.pump();
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('sale-returns-quantity-product-1')),
          )
          .data,
      '2',
    );
    // Still refused without a reason.
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('sale-returns-submit')))
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const ValueKey('sale-returns-reason')),
      'Damaged bottle',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sale-returns-submit')));
    await tester.pumpAndSettle();

    // A confirmation is required, and cancelling writes nothing.
    await tester.tap(find.byKey(const ValueKey('sale-returns-cancel-confirm')));
    await tester.pumpAndSettle();
    expect(writer.intents, isEmpty);

    await tester.tap(find.byKey(const ValueKey('sale-returns-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sale-returns-confirm')));
    await tester.pumpAndSettle();

    final intent = writer.intents.single;
    expect(intent.saleId, 'co-1');
    expect(intent.createdBy, 'user-a');
    expect(intent.reason, 'Damaged bottle');
    expect(intent.lines.single.productId, 'product-1');
    expect(intent.lines.single.quantity, 2);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('sale-returns-notice'))).data,
      startsWith('Return recorded. No stock has been restored yet'),
    );
  });

  testWidgets('the quantity can never exceed what is available', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader, writer: _Writer());

    for (var tap = 0; tap < 6; tap++) {
      await tester.tap(
        find.byKey(const ValueKey('sale-returns-increase-product-1')),
      );
      await tester.pump();
    }

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('sale-returns-quantity-product-1')),
          )
          .data,
      '4',
    );
  });

  testWidgets('an ambiguous write tells the user not to record it again', (
    tester,
  ) async {
    final writer = _Writer(
      const TenantReturnWriteResult.ambiguous('write_timeout'),
    );
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader, writer: writer);
    await tester.tap(find.byKey(const ValueKey('sale-returns-increase-product-1')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('sale-returns-reason')),
      'Damaged bottle',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sale-returns-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sale-returns-confirm')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const ValueKey('sale-returns-notice'))).data,
      startsWith('The result is unknown.'),
    );

    // The retry reuses the same deterministic document, so the create-only rule
    // refuses a replay instead of recording the reversal twice.
    await tester.tap(find.byKey(const ValueKey('sale-returns-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sale-returns-confirm')));
    await tester.pumpAndSettle();
    expect(writer.intents.length, 2);
    expect(writer.intents.last.returnId, writer.intents.first.returnId);
  });

  testWidgets('an incomplete returns page offers no record form', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _pending('ret-3'),
        _pending('ret-2'),
        _pending('ret-1'),
      ]);

    await _pump(
      tester,
      _controller(),
      reader,
      pageSize: 2,
      writer: _Writer(),
    );

    // The remaining quantity can only be derived from the complete set, and a
    // partial page would overstate it.
    expect(find.byKey(const ValueKey('sale-returns-form')), findsNothing);
    expect(
      find.byKey(const ValueKey('sale-returns-form-unavailable')),
      findsOne,
    );
  });
}

Future<void> _pump(
  WidgetTester tester,
  TenantSessionController controller,
  _Reader reader, {
  int pageSize = 20,
  bool settle = true,
  TenantReturnWriter? writer,
}) async {
  // The record form adds a text field, so the page carries more than one
  // Scrollable and `scrollUntilVisible` can no longer identify the list. A tall
  // surface builds every row instead, which is what these assertions need.
  tester.view.physicalSize = const Size(1400, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: Scaffold(
          body: TenantSaleReturnsPanel(
            reader: reader,
            request: _request(),
            pageSize: pageSize,
            writer: writer,
            requestIdFactory: () => 'return-abcdefgh',
          ),
        ),
      ),
    ),
  );
  if (!settle) return;
  await tester.pump();
  await tester.pump();
}

/// Records every intent handed to the write boundary.
final class _Writer implements TenantReturnWriter {
  _Writer([this._result = const TenantReturnWriteResult.committed()]);

  final TenantReturnWriteResult _result;
  final List<TenantReturnCreateIntent> intents = <TenantReturnCreateIntent>[];

  @override
  Future<TenantReturnWriteResult> recordReturn(
    TenantReturnCreateIntent intent,
  ) async {
    intents.add(intent);
    return _result;
  }
}

TenantSaleReturnsRequest _request() =>
    TenantSaleReturnsRequest(sale: _sale());

String _receipt(int sequence) => formatCheckoutReceiptNumber(
  deviceId: _deviceA,
  businessDate: _businessDate,
  sequence: sequence,
);

TenantSale _sale() => TenantSale.fromDocument(
  path: 'tenants/tenant-a/sales/co-1',
  data: <String, Object?>{
    'checkoutId': 'co-1',
    'tenantId': 'tenant-a',
    'soldById': 'user-a',
    'payloadHash': _payloadHash,
    'payloadSchemaVersion': 1,
    'currency': 'KES',
    'businessDate': _businessDate,
    'shiftId': 'shift-a',
    'deviceId': _deviceA,
    'receiptNumber': _receipt(1),
    'receiptSequence': 1,
    'items': <Object?>[
      <String, Object?>{
        'productId': 'product-1',
        'name': 'Tusker',
        'quantity': 4,
        'unitPriceMinor': 500,
        'lineTotalMinor': 2000,
      },
      <String, Object?>{
        'productId': 'product-2',
        'name': 'Water',
        'quantity': 5,
        'unitPriceMinor': 100,
        'lineTotalMinor': 500,
      },
    ],
    'subtotalMinor': 2500,
    'subtotal': 25.0,
    'discountMinor': 0,
    'discount': 0.0,
    'totalMinor': 2500,
    'total': 25.0,
    'createdAt': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 12)),
  },
);

TenantSessionController _controller({TenantRole role = TenantRole.cashier}) =>
    TenantSessionController()
      ..open(uid: 'user-a', membership: _membership('tenant-a', role: role));

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

TenantQueryDocumentSnapshot _pending(
  String returnId, {
  String tenantId = 'tenant-a',
  Map<String, Object?>? overrides,
}) {
  final data = <String, Object?>{
    'returnId': returnId,
    'tenantId': tenantId,
    'saleId': 'co-1',
    'createdBy': 'user-a',
    'status': 'pending',
    'reason': 'Damaged bottle',
    'itemsReturned': <Object?>[
      <String, Object?>{
        'productId': 'product-1',
        'productName': 'Tusker',
        'quantity': 2,
      },
      <String, Object?>{'productId': 'product-2', 'quantity': 1},
    ],
    'createdAt': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 12)),
  };
  if (overrides != null) data.addAll(overrides);
  return TenantQueryDocumentSnapshot(
    path: 'tenants/$tenantId/returns/$returnId',
    data: data,
  );
}

TenantQueryDocumentSnapshot _verified(String returnId) {
  final base = _pending(returnId);
  return TenantQueryDocumentSnapshot(
    path: base.path,
    data: <String, Object?>{
      ...base.data,
      'status': 'verified',
      'verified': true,
      'verifiedBy': 'manager-a',
      'verifiedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 6)),
      'stockRestored': true,
      'stockRestoredAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 6)),
      'stockRestorationId': 'rv_abc',
    },
  );
}

final class _Reader implements TenantDataReader {
  _Reader({
    this.deferred = false,
    this.deniedStaff = false,
    this.ignoreFilters = false,
    this.staffNames = const <String, String>{},
  });

  final bool deferred;

  /// Stands in for a staff record this role may not read: the row must still
  /// render, labelled by the authoritative UID.
  final bool deniedStaff;
  final bool ignoreFilters;
  final Map<String, String> staffNames;
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
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    if (deniedStaff) throw StateError('permission-denied');
    final uid = path.split('/').last;
    final name = staffNames[uid];
    return name == null
        ? null
        : TenantDocumentSnapshot(
            path: path,
            data: <String, Object?>{'uid': uid, 'name': name},
          );
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) {
    queries.add(query);
    final all = _pages[query.collectionPath] ?? const [];
    final cursor = query.startAfterDocumentId;
    final matches = <TenantQueryDocumentSnapshot>[];
    for (final snapshot in all) {
      final id = snapshot.path.split('/').last;
      if (cursor != null && id.compareTo(cursor) >= 0) continue;
      final matchesFilters =
          ignoreFilters ||
          query.equalityFilters.entries.every(
            (filter) => snapshot.data[filter.key] == filter.value,
          );
      if (!matchesFilters) continue;
      matches.add(snapshot);
      if (matches.length >= query.limit) break;
    }
    if (!deferred) return Future.value(matches);
    final completer = Completer<List<TenantQueryDocumentSnapshot>>();
    pending.add(completer);
    _deferredResults.add(matches);
    return completer.future;
  }
}
