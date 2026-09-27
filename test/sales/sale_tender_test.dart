import 'package:cloud_functions/cloud_functions.dart';
import 'package:uzapay_pos/checkout/checkout_receipt.dart';
import 'package:uzapay_pos/checkout/checkout_tender.dart';
import 'package:uzapay_pos/sales/sale_history.dart';
import 'package:uzapay_pos/sales/sale_tender.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

const String _deviceA = 'dev-0123456789abcdef0123456789abcdef';
const String _businessDate = '2026-07-31';
const String _payloadHash =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

/// The one write a sale ever takes after it is created, and its guards.
///
/// **Why this exists.** The register stopped preselecting a payment method, so
/// a cashier who was never told how the customer paid saves a sale naming none.
/// That is honest and useless unless the question can be answered afterwards,
/// and this is the only path that answers it. The direction and the caller are
/// both pinned down here because everything downstream of a sale - the payload
/// hash, the confirmation, the nightly reconciliation - leans on the record not
/// moving under it.
void main() {
  test('sends the tenant, the sale, the method and a request ID', () async {
    final callable = _FakeCallable();

    await TenantSaleTenderGateway(
      session: _session(),
      target: _sale(),
      callable: callable,
      requestIdFactory: () => 'set-sale-tender-fixed-value',
    ).record(CheckoutTender.mpesa);

    expect(callable.payloads.single, <String, Object?>{
      'tenantId': 'tenant-a',
      'saleId': 'co-1',
      'tender': 'mpesa',
      'requestId': 'set-sale-tender-fixed-value',
    });
  });

  test('a recorded method can be corrected, and says it replaces', () async {
    // **A mis-tap is noticed at the counter.** With no way back the split stays
    // wrong for ever and silently, because reconciliation agrees on the total
    // alone. Whether the correction is still allowed depends on the shift,
    // which this surface cannot see - the server decides and says so.
    final callable = _FakeCallable();

    await TenantSaleTenderGateway(
      session: _session(),
      target: _sale(tender: 'cash'),
      callable: callable,
    ).record(CheckoutTender.mpesa);

    expect(callable.payloads.single['tender'], 'mpesa');
    expect(TenantSaleTenderGateway.replaces(_sale(tender: 'cash')), isTrue);
    expect(TenantSaleTenderGateway.replaces(_sale()), isFalse);
  });

  test('choosing the method it already names is not sent', () async {
    final callable = _FakeCallable();

    await expectLater(
      TenantSaleTenderGateway(
        session: _session(),
        target: _sale(tender: 'cash'),
        callable: callable,
      ).record(CheckoutTender.cash),
      throwsA(
        isA<TenantSaleTenderException>().having(
          (error) => error.failure,
          'failure',
          TenantSaleTenderFailure.alreadyRecorded,
        ),
      ),
    );
    expect(callable.payloads, isEmpty);
  });

  test('only the cashier who sold it may answer for it', () async {
    final callable = _FakeCallable();

    await expectLater(
      TenantSaleTenderGateway(
        session: _session(uid: 'user-b'),
        target: _sale(),
        callable: callable,
      ).record(CheckoutTender.cash),
      throwsA(
        isA<TenantSaleTenderException>().having(
          (error) => error.failure,
          'failure',
          TenantSaleTenderFailure.forbidden,
        ),
      ),
    );
    expect(callable.payloads, isEmpty);
  });

  test('classifies what the server said', () async {
    final cases = <FirebaseFunctionsException, TenantSaleTenderFailure>{
      FirebaseFunctionsException(code: 'permission-denied', message: 'no'):
          TenantSaleTenderFailure.forbidden,
      FirebaseFunctionsException(code: 'not-found', message: 'no'):
          TenantSaleTenderFailure.notFound,
      FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'This sale already names that payment method.',
      ): TenantSaleTenderFailure.alreadyRecorded,
      // The bound on a correction: past the close the split has been counted
      // against, and moving it would reach back into settled books.
      FirebaseFunctionsException(
        code: 'failed-precondition',
        message:
            'This shift has been counted off, so the payment method '
            'recorded on its sales can no longer be changed.',
      ): TenantSaleTenderFailure.shiftClosed,
      // A `failed-precondition` this app does not model still reports
      // truthfully that nothing was recorded, rather than guessing.
      FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'something else entirely',
      ): TenantSaleTenderFailure.refused,
      FirebaseFunctionsException(code: 'unavailable', message: 'no'):
          TenantSaleTenderFailure.ambiguous,
    };

    for (final entry in cases.entries) {
      final callable = _FakeCallable()..failure = entry.key;
      await expectLater(
        TenantSaleTenderGateway(
          session: _session(),
          target: _sale(),
          callable: callable,
        ).record(CheckoutTender.card),
        throwsA(
          isA<TenantSaleTenderException>().having(
            (error) => error.failure,
            'failure',
            entry.value,
          ),
        ),
        reason: entry.key.code,
      );
    }
  });

  test('an answer that never arrived is ambiguous, not refused', () async {
    // It may or may not have been recorded, and saying either would be a guess
    // about money. The surface re-reads the row rather than asserting.
    final callable = _FakeCallable()..failure = StateError('socket');

    await expectLater(
      TenantSaleTenderGateway(
        session: _session(),
        target: _sale(),
        callable: callable,
      ).record(CheckoutTender.cash),
      throwsA(
        isA<TenantSaleTenderException>().having(
          (error) => error.failure,
          'failure',
          TenantSaleTenderFailure.ambiguous,
        ),
      ),
    );
  });

  test('every failure has something to say', () {
    for (final failure in TenantSaleTenderFailure.values) {
      expect(
        tenantSaleTenderFailureMessage(failure),
        isNotEmpty,
        reason: failure.name,
      );
    }
  });
}

final class _FakeCallable implements SetSaleTenderCallable {
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];
  Object? failure;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    final error = failure;
    if (error != null) throw error;
    payloads.add(payload);
    return <String, Object?>{'saleId': payload['saleId']};
  }
}

TenantSession _session({String uid = 'user-a'}) => TenantSession.active(
  uid: uid,
  tenantId: 'tenant-a',
  role: TenantRole.cashier,
);

TenantSale _sale({String? tender}) => TenantSale.fromDocument(
  path: 'tenants/tenant-a/sales/co-1',
  data: <String, Object?>{
    'checkoutId': 'co-1',
    'tenantId': 'tenant-a',
    'soldById': 'user-a',
    'payloadHash': _payloadHash,
    'payloadSchemaVersion': 2,
    if (tender != null) 'tender': tender,
    'currency': 'KES',
    'businessDate': _businessDate,
    'clientCreatedAtMs': 1785484800000,
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
        'quantity': 2,
        'unitPriceMinor': 500,
        'lineTotalMinor': 1000,
      },
    ],
    'subtotalMinor': 1000,
    'subtotal': 10.0,
    'discountMinor': 100,
    'discount': 1.0,
    'totalMinor': 900,
    'total': 9.0,
  },
);
