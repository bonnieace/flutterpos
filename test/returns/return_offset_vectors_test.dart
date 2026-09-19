/// The Dart half of the shared return-offset vectors.
///
/// **Why a fixture file rather than inline cases.** The same money rule now
/// exists twice - `describeReturnOffset` here and `describeSaleReturn` in
/// `functions/src/operations/domain.ts` - because a period is read online
/// through the callable and offline through the device aggregator. Two
/// implementations of one rule drift. `functions/src/operations/
/// returnOffsetVectors.test.ts` reads this same file and asserts the same
/// numbers, so a divergent rounding or a re-parenthesised multiply fails on
/// one side and not the other.
///
/// The vectors are also the reason the sale documents in the file are fully
/// formed: they go through `TenantSale.fromDocument`, so a vector cannot
/// describe a sale the app itself would refuse.
library;

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/checkout/checkout_receipt.dart';
import 'package:flutter_application_1/returns/return_offsets.dart';
import 'package:flutter_application_1/sales/sale_history.dart';
import 'package:flutter_test/flutter_test.dart';

const String _tenant = 'tenant-a';
const String _uid = 'user-a';
const String _device = 'dev-0123456789abcdef0123456789abcdef';
const String _businessDate = '2026-08-26';

void main() {
  final vectors =
      (jsonDecode(
                File('test/fixtures/return_offset_vectors.json').readAsStringSync(),
              )
              as Map<String, Object?>)['vectors']!
          as List<Object?>;

  test('the fixture is not silently empty', () {
    // A runner that reads nothing passes, and a passing runner over no vectors
    // is worse than no runner: it reports agreement that was never checked.
    expect(vectors.length, greaterThanOrEqualTo(9));
  });

  for (final entry in vectors) {
    final vector = entry! as Map<String, Object?>;
    test(vector['name']! as String, () {
      final sale = _saleOf(vector['sale']! as Map<String, Object?>);
      final returned = <String, int>{
        for (final unit in (vector['returnedUnits']! as Map<String, Object?>)
            .entries)
          unit.key: unit.value! as int,
      };
      final offset = describeReturnOffset(
        sale,
        returned,
        categoryId: vector['categoryId'] as String?,
      );
      final expected = vector['expect']! as Map<String, Object?>;

      expect(
        offset.returnedMinor,
        expected['revenueMinor'],
        reason: 'revenue',
      );
      expect(offset.returnedCostMinor, expected['costMinor'], reason: 'cost');
      expect(
        offset.fullyReturnedCostlessLines,
        expected['fullyReturnedCostlessLines'],
        reason: 'costless lines fully back',
      );
      expect(
        offset.isFullyReturned,
        expected['fullyReturned'],
        reason: 'fully returned',
      );
    });
  }
}

/// Builds the sale a vector describes, through the real decoder.
TenantSale _saleOf(Map<String, Object?> spec) {
  final subtotalMinor = spec['subtotalMinor']! as int;
  final discountMinor = spec['discountMinor']! as int;
  final totalMinor = spec['totalMinor']! as int;
  return TenantSale.fromDocument(
    path: 'tenants/$_tenant/sales/co-vector',
    data: <String, Object?>{
      'checkoutId': 'co-vector',
      'tenantId': _tenant,
      'soldById': _uid,
      'payloadHash': 'a' * 64,
      'payloadSchemaVersion': 2,
      'currency': 'KES',
      'businessDate': _businessDate,
      'clientCreatedAtMs': 1785484800000,
      'shiftId': 'shift-a',
      'deviceId': _device,
      'receiptNumber': formatCheckoutReceiptNumber(
        deviceId: _device,
        businessDate: _businessDate,
        sequence: 1,
      ),
      'receiptSequence': 1,
      'items': spec['items'],
      'subtotalMinor': subtotalMinor,
      'subtotal': subtotalMinor / 100,
      'discountMinor': discountMinor,
      'discount': discountMinor / 100,
      'totalMinor': totalMinor,
      'total': totalMinor / 100,
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 26, 12)),
    },
  );
}
