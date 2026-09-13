import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/checkout/checkout_receipt.dart';
import 'package:flutter_application_1/returns/returns.dart';
import 'package:flutter_application_1/sales/sales.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

const String _deviceA = 'dev-0123456789abcdef0123456789abcdef';
const String _businessDate = '2026-07-31';
const String _payloadHash =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const String _requestId = 'return-abcdefgh';

void main() {
  group('returnable sale', () {
    test('subtracts every recorded return, verified and pending alike', () {
      // The server's own bound counts only verified returns. Subtracting
      // pending ones too is deliberately tighter: two pending returns that each
      // fit can jointly exceed the sale, and the second verification fails.
      final returnable = _repository().describeReturnable(
        sale: _sale(),
        recorded: _page(<TenantReturn>[
          _record('ret-1', <String, int>{'product-1': 1}),
          _record('ret-2', <String, int>{'product-2': 3}, verified: true),
        ]),
      );

      expect(returnable.saleId, 'co-1');
      expect(returnable.receiptNumber, _receipt(1));
      expect(_remaining(returnable), <String, int>{
        'product-1': 3,
        'product-2': 2,
      });
      expect(returnable.hasReturnableLines, isTrue);
    });

    test('a fully returned sale has nothing left', () {
      final returnable = _repository().describeReturnable(
        sale: _sale(),
        recorded: _page(<TenantReturn>[
          _record('ret-1', <String, int>{'product-1': 4, 'product-2': 5}),
        ]),
      );

      expect(returnable.hasReturnableLines, isFalse);
      expect(returnable.returnable, isEmpty);
    });

    test('an incomplete returns page is refused outright', () {
      // A partial list would overstate the remaining quantity, which is the one
      // number this surface exists to state.
      expect(
        () => _repository().describeReturnable(
          sale: _sale(),
          recorded: _page(<TenantReturn>[], hasMore: true),
        ),
        _code('incomplete_return_history'),
      );
    });

    test('recorded evidence that contradicts the sale is reported', () {
      expect(
        () => _repository().describeReturnable(
          sale: _sale(),
          recorded: _page(<TenantReturn>[
            _record('ret-1', <String, int>{'product-1': 9}),
          ]),
        ),
        _code('return_exceeds_sale'),
      );
      expect(
        () => _repository().describeReturnable(
          sale: _sale(),
          recorded: _page(<TenantReturn>[
            _record('ret-1', <String, int>{'product-9': 1}),
          ]),
        ),
        _code('return_exceeds_sale'),
      );
      expect(
        () => _repository().describeReturnable(
          sale: _sale(),
          recorded: _page(<TenantReturn>[
            _record('ret-1', <String, int>{'product-1': 1}, saleId: 'co-2'),
          ]),
        ),
        _code('return_sale_mismatch'),
      );
    });

    test('a sale from another business is refused', () {
      expect(
        () => _repository().describeReturnable(
          sale: _sale(tenantId: 'tenant-b'),
          recorded: _page(const <TenantReturn>[]),
        ),
        _code('cross_tenant_sale'),
      );
    });
  });

  group('return create intent', () {
    test('freezes exactly the key set the create rule allows', () {
      final intent = _intent(<String, int>{'product-1': 2, 'product-2': 1});

      expect(intent.path, 'tenants/tenant-a/returns/${intent.returnId}');
      expect(intent.returnId, startsWith('rt_'));
      expect(intent.tenantId, 'tenant-a');
      expect(intent.saleId, 'co-1');
      expect(intent.createdBy, 'user-a');
      expect(intent.requestedUnits, 3);
      // Copied off the immutable sale, not off a clock: it is the day the sale
      // traded, which is the day the money comes back out of.
      expect(intent.businessDate, _businessDate);
      final data = intent.documentData();
      expect(data.keys.toSet(), <String>{
        'returnId',
        'tenantId',
        'saleId',
        'businessDate',
        'recordedOn',
        'createdBy',
        'status',
        'reason',
        'itemsReturned',
      });
      expect(data['status'], 'pending');
      // Two different days, and the difference is the point: the sale traded on
      // one, the customer came back on the other.
      expect(data['businessDate'], _businessDate);
      expect(data['recordedOn'], '2026-08-04');
      expect(data['returnId'], intent.returnId);
      // The server-owned instant is added by the writer, never by the intent.
      expect(data.containsKey('createdAt'), isFalse);
      // Ordered by product, so an identical request is byte-identical.
      //
      // **The name is written beside the ID**, taken from the sale rather than
      // the catalog, so no returns screen ever has to show a document ID for
      // want of a label. `validSaleLine` checks `productId` and `quantity` and
      // forbids no other key, so this is inside the rule as it stands.
      expect(data['itemsReturned'], <Object?>[
        <String, Object?>{
          'productId': 'product-1',
          'productName': 'Tusker',
          'quantity': 2,
        },
        <String, Object?>{
          'productId': 'product-2',
          'productName': 'Water',
          'quantity': 1,
        },
      ]);
    });

    test('the document ID is deterministic for one request ID', () {
      final first = _intent(<String, int>{'product-1': 1});
      final same = _intent(<String, int>{'product-1': 1});
      final other = _intent(<String, int>{'product-1': 1}, requestId: 'return-zzzzzzzz');

      // A retry of one confirmation intent addresses the same document, so the
      // create-only rule refuses the replay instead of recording it twice.
      expect(same.returnId, first.returnId);
      expect(other.returnId, isNot(first.returnId));
    });

    test('refuses more than the sale still has available', () {
      expect(
        () => _intent(<String, int>{'product-1': 5}),
        _code('return_exceeds_sale'),
      );
      // One unit already returned leaves three.
      expect(
        () => _intent(
          <String, int>{'product-1': 4},
          recorded: <TenantReturn>[
            _record('ret-1', <String, int>{'product-1': 1}),
          ],
        ),
        _code('return_exceeds_sale'),
      );
      expect(
        () => _intent(<String, int>{'product-9': 1}),
        _code('invalid_return_quantities'),
      );
      expect(
        () => _intent(<String, int>{'product-1': -1}),
        _code('invalid_return_quantities'),
      );
    });

    test('refuses an empty request', () {
      expect(
        () => _intent(<String, int>{}),
        _code('invalid_return_quantities'),
      );
      expect(
        () => _intent(<String, int>{'product-1': 0}),
        _code('invalid_return_quantities'),
      );
    });

    test('normalizes and bounds the audit reason', () {
      final intent = _intent(
        <String, int>{'product-1': 1},
        reason: '  Damaged   in   transit \n',
      );
      expect(intent.reason, 'Damaged in transit');

      for (final reason in <String>['', ' a ', 'x' * 501]) {
        expect(
          () => _intent(<String, int>{'product-1': 1}, reason: reason),
          _code('invalid_return_reason'),
        );
      }
    });

    test('refuses a request ID the server contract would not accept', () {
      for (final id in <String>['', 'short', 'has space', 'x' * 200]) {
        expect(
          () => _intent(<String, int>{'product-1': 1}, requestId: id),
          _code('invalid_return_request_id'),
        );
      }
    });
  });

  group('return writer', () {
    test('adds the server instant and reports a commit', () async {
      final writes = <String, Map<String, Object?>>{};
      final writer = FirebaseTenantReturnWriter.forTesting(
        create: (path, data) async => writes[path] = data,
        isOnline: () async => true,
      );
      final intent = _intent(<String, int>{'product-1': 1});

      final result = await writer.recordReturn(intent);

      expect(result.kind, TenantReturnWriteKind.committed);
      expect(writes[intent.path]!['createdAt'], isA<FieldValue>());
      expect(writes[intent.path]!['status'], 'pending');
    });

    test('an offline device attempts nothing', () async {
      var attempts = 0;
      final writer = FirebaseTenantReturnWriter.forTesting(
        create: (path, data) async => attempts++,
        isOnline: () async => false,
      );

      final result = await writer.recordReturn(
        _intent(<String, int>{'product-1': 1}),
      );

      expect(result.kind, TenantReturnWriteKind.unavailable);
      expect(attempts, 0);
    });

    test('a denied write is rejected and an unknown one is ambiguous', () async {
      Future<TenantReturnWriteResult> attempt(String code) {
        final writer = FirebaseTenantReturnWriter.forTesting(
          create: (path, data) async =>
              throw FirebaseException(plugin: 'test', code: code),
          isOnline: () async => true,
        );
        return writer.recordReturn(_intent(<String, int>{'product-1': 1}));
      }

      expect(
        (await attempt('permission-denied')).kind,
        TenantReturnWriteKind.rejected,
      );
      // A replay of the deterministic ID is an update the Rules refuse.
      expect(
        (await attempt('already-exists')).kind,
        TenantReturnWriteKind.rejected,
      );
      expect(
        (await attempt('unavailable')).kind,
        TenantReturnWriteKind.ambiguous,
      );
    });

    test('the written path is always derived from the session tenant', () {
      // `TenantReturnCreateIntent` is final and only the repository builds one,
      // so no caller can hand the writer a foreign path. The writer still
      // re-derives it before writing; this pins the invariant it checks.
      final intent = _intent(<String, int>{'product-1': 1});

      expect(
        intent.path,
        TenantPaths('tenant-a').returnRecord(intent.returnId),
      );
      expect(intent.path, startsWith('tenants/tenant-a/returns/'));
    });
  });

  group('return settlement read', () {
    test('reads the deterministic document by exact path', () async {
      final intent = _intent(<String, int>{'product-1': 1});
      final reader = _Reader(<String, Map<String, Object?>>{
        'tenants/tenant-a/returns/${intent.returnId}': <String, Object?>{
          ...intent.documentData(),
          'createdAt': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 12)),
        },
      });

      final settled = await TenantReturnRequestRepository(
        session: _session(),
        reader: reader,
      ).readReturn(intent.returnId);

      expect(settled!.id, intent.returnId);
      expect(settled.status, TenantReturnStatus.pending);
      expect(reader.requested.single, intent.path);
    });

    test('an absent document is the answer, not a failure', () async {
      final reader = _Reader(const <String, Map<String, Object?>>{});

      final settled = await TenantReturnRequestRepository(
        session: _session(),
        reader: reader,
      ).readReturn('rt_missing');

      expect(settled, isNull);
    });

    test('a cross-tenant response fails closed', () async {
      final intent = _intent(<String, int>{'product-1': 1});
      final reader = _Reader(<String, Map<String, Object?>>{
        'tenants/tenant-a/returns/${intent.returnId}': intent.documentData(),
      }, responsePath: 'tenants/tenant-b/returns/${intent.returnId}');

      await expectLater(
        TenantReturnRequestRepository(
          session: _session(),
          reader: reader,
        ).readReturn(intent.returnId),
        throwsA(isA<TenantScopeViolation>()),
      );
    });
  });
}

TenantReturnRequestRepository _repository({
  TenantRole role = TenantRole.cashier,
}) => TenantReturnRequestRepository(
  session: _session(role: role),
  reader: _Reader(const <String, Map<String, Object?>>{}),
);

TenantSession _session({TenantRole role = TenantRole.cashier}) =>
    TenantSession.active(uid: 'user-a', tenantId: 'tenant-a', role: role);

TenantReturnCreateIntent _intent(
  Map<String, int> quantities, {
  String reason = 'Damaged bottle',
  String requestId = _requestId,
  List<TenantReturn> recorded = const <TenantReturn>[],
  TenantRole role = TenantRole.cashier,
}) {
  final repository = _repository(role: role);
  return repository.buildCreateIntent(
    returnable: repository.describeReturnable(
      sale: _sale(),
      recorded: _page(recorded),
    ),
    quantities: quantities,
    reason: reason,
    requestId: requestId,
    // Fixed, so the recording day is a fact this test states rather than
    // whatever day it happens to run on.
    now: DateTime.utc(2026, 8, 4, 9),
  );
}

Map<String, int> _remaining(TenantReturnableSale returnable) =>
    <String, int>{
      for (final line in returnable.lines) line.productId: line.remainingQuantity,
    };

TenantReturnPage _page(List<TenantReturn> items, {bool hasMore = false}) =>
    TenantReturnPage(items: items, nextCursor: null, hasMore: hasMore);

TenantReturn _record(
  String returnId,
  Map<String, int> quantities, {
  bool verified = false,
  String saleId = 'co-1',
}) => TenantReturn.fromDocument(
  path: 'tenants/tenant-a/returns/$returnId',
  data: <String, Object?>{
    'returnId': returnId,
    'tenantId': 'tenant-a',
    'saleId': saleId,
    'createdBy': 'user-a',
    'status': verified ? 'verified' : 'pending',
    'reason': 'Earlier return',
    'itemsReturned': <Object?>[
      for (final entry in quantities.entries)
        <String, Object?>{'productId': entry.key, 'quantity': entry.value},
    ],
    if (verified) ...<String, Object?>{
      'verified': true,
      'verifiedBy': 'manager-a',
      'verifiedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 6)),
      'stockRestored': true,
      'stockRestorationId': 'rv_abc',
    },
  },
);

TenantSale _sale({String tenantId = 'tenant-a'}) => TenantSale.fromDocument(
  path: 'tenants/$tenantId/sales/co-1',
  data: <String, Object?>{
    'checkoutId': 'co-1',
    'tenantId': tenantId,
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

String _receipt(int sequence) => formatCheckoutReceiptNumber(
  deviceId: _deviceA,
  businessDate: _businessDate,
  sequence: sequence,
);

Matcher _code(String code) => throwsA(
  isA<TenantReturnException>().having((error) => error.code, 'code', code),
);

final class _Reader implements TenantDataReader {
  _Reader(this._documents, {this.responsePath});

  final Map<String, Map<String, Object?>> _documents;
  final String? responsePath;
  final List<String> requested = <String>[];

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    requested.add(path);
    final data = _documents[path];
    return data == null
        ? null
        : TenantDocumentSnapshot(path: responsePath ?? path, data: data);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async => const <TenantQueryDocumentSnapshot>[];
}
