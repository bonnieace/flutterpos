import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uzapay_pos/checkout/checkout_draft.dart';
import 'package:uzapay_pos/checkout/checkout_receipt.dart';
import 'package:uzapay_pos/checkout/checkout_tender.dart';
import 'package:uzapay_pos/returns/returns.dart';
import 'package:uzapay_pos/sales/sales.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';

/// Money handed back over the counter for a return.
///
/// A return already says what came back; it never said what money went out,
/// or from which drawer, so the drawer that paid was always counted short by
/// it. These pin what the till suggests handing back, what it refuses, and
/// the four fields a return records about it.

const String _deviceA = 'dev-0123456789abcdef0123456789abcdef';
const String _businessDate = '2026-10-08';
const String _payloadHash =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const String _customerId = 'cu_0123456789abcdef0123456789abcdef01234567';

void main() {
  group('what the till suggests handing back', () {
    test(
      'the returned goods, at what was charged, by how the sale was paid',
      () {
        final returnable = _returnable(_sale(tender: 'cash'));

        expect(returnable.refundTender, CheckoutTender.cash);
        expect(returnable.refundableMinor, 2500);
        expect(
          returnable.suggestedRefundMinor(<String, int>{'product-1': 1}),
          500,
        );
        expect(
          returnable.suggestedRefundMinor(<String, int>{
            'product-1': 4,
            'product-2': 5,
          }),
          2500,
        );
        expect(returnable.suggestedRefundMinor(const <String, int>{}), 0);
      },
    );

    test('a discounted sale hands back its share of the discounted total', () {
      // 2500 listed, 500 off: every shilling of goods was sold at 80 cents.
      final returnable = _returnable(
        _sale(tender: 'mpesa', discountMinor: 500),
      );

      expect(returnable.refundTender, CheckoutTender.mpesa);
      expect(
        returnable.suggestedRefundMinor(<String, int>{'product-1': 1}),
        400,
      );
      // The whole sale back is exactly what was charged, whatever rounding
      // does to the parts.
      expect(
        returnable.suggestedRefundMinor(<String, int>{
          'product-1': 4,
          'product-2': 5,
        }),
        2000,
      );
    });

    test('what earlier returns handed back is not handed back again', () {
      final returnable = _returnable(
        _sale(tender: 'cash'),
        recorded: <TenantReturn>[
          _record('ret-1', <String, int>{'product-1': 2}, refundMinor: 1000),
        ],
      );

      expect(returnable.refundableMinor, 1500);
      expect(
        returnable.suggestedRefundMinor(<String, int>{'product-1': 1}),
        500,
      );
    });

    test(
      'a credit sale cancels what is owed before handing any money back',
      () {
        // 2500 sold, 1500 left owing, 1000 paid at the counter by M-Pesa. The
        // server cancels debt first when the return is verified, so the goods
        // pay for themselves before the shop hands over a shilling.
        final returnable = _returnable(
          _sale(tender: 'credit', owedMinor: 1500, paidTender: 'mpesa'),
        );

        expect(returnable.refundTender, CheckoutTender.mpesa);
        expect(returnable.refundableMinor, 1000);
        // 1000 of goods back: all of it comes off the 1500 still owed.
        expect(
          returnable.suggestedRefundMinor(<String, int>{'product-1': 2}),
          0,
        );
        // All of it back: 1500 cancels the debt, 1000 is handed back.
        expect(
          returnable.suggestedRefundMinor(<String, int>{
            'product-1': 4,
            'product-2': 5,
          }),
          1000,
        );
      },
    );

    test(
      "a second credit return hands back what the first one's debt left",
      () {
        final returnable = _returnable(
          _sale(tender: 'credit', owedMinor: 1500, paidTender: 'mpesa'),
          recorded: <TenantReturn>[
            _record('ret-1', <String, int>{'product-1': 2}),
          ],
        );

        // The first 1000 cancelled 1000 of the debt; this 1000 cancels the last
        // 500 of it and hands back the other 500.
        expect(
          returnable.suggestedRefundMinor(<String, int>{'product-1': 2}),
          500,
        );
      },
    );

    test('a sale owed in full has nothing to hand back', () {
      final returnable = _returnable(_sale(tender: 'credit', owedMinor: 2500));

      expect(returnable.refundTender, isNull);
      expect(returnable.refundableMinor, 0);
      expect(returnable.suggestedRefundMinor(<String, int>{'product-1': 4}), 0);
    });

    test('a sale nobody said how was paid suggests no method', () {
      final returnable = _returnable(_sale());

      expect(returnable.refundTender, isNull);
      expect(returnable.refundableMinor, 2500);
      expect(
        returnable.suggestedRefundMinor(<String, int>{'product-1': 1}),
        500,
      );
    });
  });

  group('the return records the refund', () {
    test('all four fields, from the shift that paid it', () {
      final intent = _intent(
        refundMinor: 500,
        refundTender: CheckoutTender.cash,
        refundShift: _shift(),
      );

      expect(intent.refund?.amountMinor, 500);
      expect(intent.documentData(), containsPair('refundMinor', 500));
      expect(intent.documentData(), containsPair('refundTender', 'cash'));
      expect(intent.documentData(), containsPair('refundShiftId', 'shift-b'));
      // The day the drawer was trading, not the sale's day: last week's goods
      // handed back this morning come out of this morning's till.
      expect(
        intent.documentData(),
        containsPair('refundBusinessDate', '2026-10-09'),
      );
      expect(intent.businessDate, _businessDate);
    });

    test('nothing handed back writes nothing, as every return did before', () {
      final intent = _intent(refundShift: _shift());

      expect(intent.refund, isNull);
      expect(
        intent.documentData().keys.where((key) => key.startsWith('refund')),
        isEmpty,
      );
    });

    test('refuses a refund it cannot account for', () {
      expect(
        () => _intent(refundMinor: -1, refundShift: _shift()),
        _code('invalid_return_refund'),
      );
      expect(
        () => _intent(refundMinor: 500, refundTender: CheckoutTender.cash),
        _code('refund_needs_shift'),
      );
      expect(
        () => _intent(refundMinor: 500, refundShift: _shift()),
        _code('refund_needs_tender'),
      );
      expect(
        () => _intent(
          refundMinor: 2501,
          refundTender: CheckoutTender.cash,
          refundShift: _shift(),
        ),
        _code('refund_exceeds_paid'),
      );
      expect(
        () => _intent(
          refundMinor: 500,
          refundTender: CheckoutTender.cash,
          refundShift: _shift(uid: 'user-b'),
        ),
        _code('return_forbidden'),
      );
    });
  });

  group('reading a refund back', () {
    test('a return with a refund carries it, and one without carries none', () {
      final refunded = _record('ret-1', <String, int>{
        'product-1': 1,
      }, refundMinor: 500);
      expect(refunded.refund?.amountMinor, 500);
      expect(refunded.refund?.tender, CheckoutTender.cash);
      expect(refunded.refund?.shiftId, 'shift-b');
      expect(refunded.refund?.businessDate, '2026-10-09');

      expect(_record('ret-2', <String, int>{'product-1': 1}).refund, isNull);
    });

    test('half a refund is refused rather than read as none', () {
      expect(
        () => TenantReturn.fromDocument(
          path: 'tenants/tenant-a/returns/ret-1',
          data: <String, Object?>{
            ..._returnData('ret-1', <String, int>{'product-1': 1}),
            'refundMinor': 500,
          },
        ),
        _code('invalid_return_refund'),
      );
    });
  });
}

TenantReturnRequestRepository _repository() => TenantReturnRequestRepository(
  session: TenantSession.active(
    uid: 'user-a',
    tenantId: 'tenant-a',
    role: TenantRole.cashier,
  ),
  reader: _Reader(),
);

TenantReturnableSale _returnable(
  TenantSale sale, {
  List<TenantReturn> recorded = const <TenantReturn>[],
}) => _repository().describeReturnable(
  sale: sale,
  recorded: TenantReturnPage(items: recorded, nextCursor: null, hasMore: false),
);

TenantReturnCreateIntent _intent({
  int refundMinor = 0,
  CheckoutTender? refundTender,
  CheckoutShiftAttribution? refundShift,
}) {
  final repository = _repository();
  return repository.buildCreateIntent(
    returnable: _returnable(_sale(tender: 'cash')),
    quantities: <String, int>{'product-1': 1},
    reason: 'Damaged bottle',
    requestId: 'return-abcdefgh',
    now: DateTime.utc(2026, 10, 9, 6),
    refundMinor: refundMinor,
    refundTender: refundTender,
    refundShift: refundShift,
  );
}

CheckoutShiftAttribution _shift({String uid = 'user-a'}) =>
    CheckoutShiftAttribution(
      uid: uid,
      tenantId: 'tenant-a',
      shiftId: 'shift-b',
      deviceId: _deviceA,
      businessDate: '2026-10-09',
    );

Map<String, Object?> _returnData(
  String returnId,
  Map<String, int> quantities,
) => <String, Object?>{
  'returnId': returnId,
  'tenantId': 'tenant-a',
  'saleId': 'co-1',
  'businessDate': _businessDate,
  'recordedOn': _businessDate,
  'createdBy': 'user-a',
  'status': 'pending',
  'reason': 'Earlier return',
  'itemsReturned': <Object?>[
    for (final entry in quantities.entries)
      <String, Object?>{'productId': entry.key, 'quantity': entry.value},
  ],
};

TenantReturn _record(
  String returnId,
  Map<String, int> quantities, {
  int? refundMinor,
}) => TenantReturn.fromDocument(
  path: 'tenants/tenant-a/returns/$returnId',
  data: <String, Object?>{
    ..._returnData(returnId, quantities),
    if (refundMinor != null) ...<String, Object?>{
      'refundMinor': refundMinor,
      'refundTender': 'cash',
      'refundShiftId': 'shift-b',
      'refundBusinessDate': '2026-10-09',
    },
  },
);

TenantSale _sale({
  String? tender,
  int discountMinor = 0,
  int? owedMinor,
  String? paidTender,
}) => TenantSale.fromDocument(
  path: 'tenants/tenant-a/sales/co-1',
  data: <String, Object?>{
    'checkoutId': 'co-1',
    'tenantId': 'tenant-a',
    'soldById': 'user-a',
    'payloadHash': _payloadHash,
    'payloadSchemaVersion': 2,
    'currency': 'KES',
    'businessDate': _businessDate,
    'shiftId': 'shift-a',
    'deviceId': _deviceA,
    'receiptNumber': formatCheckoutReceiptNumber(
      deviceId: _deviceA,
      businessDate: _businessDate,
      sequence: 1,
    ),
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
    'discountMinor': discountMinor,
    'discount': discountMinor / 100,
    'totalMinor': 2500 - discountMinor,
    'total': (2500 - discountMinor) / 100,
    if (tender != null) 'tender': tender,
    if (owedMinor != null) ...<String, Object?>{
      'creditOwedMinor': owedMinor,
      'customerId': _customerId,
      'customerName': 'OfflineTest',
    },
    if (paidTender != null) 'creditPaidTender': paidTender,
    'createdAt': Timestamp.fromDate(DateTime.utc(2026, 10, 8, 16)),
  },
);

Matcher _code(String code) => throwsA(
  isA<TenantReturnException>().having((error) => error.code, 'code', code),
);

final class _Reader implements TenantDataReader {
  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async => null;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async => const <TenantQueryDocumentSnapshot>[];
}
