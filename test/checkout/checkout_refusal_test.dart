import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every refusal a cashier can actually reach while saving a draft.
///
/// The list is the contract, kept deliberately explicit rather than derived:
/// the codes arrive from four different files, and a new one appearing without
/// a message is exactly the regression this test exists to catch.
const Map<String, bool> _codes = <String, bool>{
  // code: whether the person at the till can clear it themselves.
  'no_selected_session': true,
  'session_changed': true,
  'checkout_start_unavailable': true,
  'no_open_shift': true,
  'other_tenant_shift_open': true,
  'shift_not_confirmed': true,
  'shift_closing': true,
  'invalid_shift_id': false,
  'shift_binding_mismatch': false,
  'catalog_cache_unavailable': true,
  'unknown_product': true,
  'price_not_representable': false,
  'invalid_line_count': true,
  'duplicate_product': true,
  'invalid_quantity': true,
  'invalid_discount': true,
  'invalid_product_id': false,
  'invalid_business_date': false,
  'invalid_checkout_id': false,
  'draft_contract_violation': false,
  'device_identity_unavailable': false,
  'malformed_device_identity': false,
  'receipt_sequence_exhausted': false,
  'malformed_receipt_counter': false,
  'invalid_encryption_key': false,
};

void main() {
  final fallback = CheckoutRefusal.forCode('not-a-real-code');

  test('every reachable refusal has its own cashier-facing sentence', () {
    final seen = <String, String>{};

    for (final code in _codes.keys) {
      final refusal = CheckoutRefusal.forCode(code);

      expect(refusal.code, code);
      expect(
        refusal.message,
        isNot(fallback.message),
        reason: '$code fell through to the generic message',
      );
      expect(
        seen.containsKey(refusal.message),
        isFalse,
        reason:
            '$code repeats the message already used by ${seen[refusal.message]}',
      );
      seen[refusal.message] = code;
    }

    expect(seen, hasLength(_codes.length));
  });

  test('no message leaks a machine code to the till', () {
    for (final code in <String>[..._codes.keys, 'not-a-real-code']) {
      final message = CheckoutRefusal.forCode(code).message;

      expect(message, isNotEmpty);
      // Every code in this system is lower_snake_case, so an underscore in the
      // displayed sentence means a raw code reached the cashier.
      expect(message, isNot(contains('_')), reason: code);
      expect(message.trim(), message, reason: code);
      // Displayed text in this app stays plain ASCII and avoids possessives,
      // so a smart quote pasted in later is caught here rather than at a till.
      expect(
        message.codeUnits.every((unit) => unit >= 0x20 && unit < 0x7f),
        isTrue,
        reason: code,
      );
      expect(message, isNot(contains('  ')), reason: code);
      expect(message, endsWith('.'), reason: code);
      // Long enough to say what to do next, short enough to read at a till.
      expect(message.length, greaterThan(20), reason: code);
      expect(message.length, lessThan(220), reason: code);
    }
  });

  test('states who can clear each refusal', () {
    _codes.forEach((code, cashierCanFix) {
      expect(
        CheckoutRefusal.forCode(code).cashierCanFix,
        cashierCanFix,
        reason: code,
      );
    });
  });

  // Retrying a damaged receipt counter cannot succeed: it is refused rather
  // than restarted, because restarting it would reissue a receipt number a
  // committed sale already carries. The till must not offer that retry.
  test('never invites a retry that cannot succeed', () {
    const unfixable = <String>[
      'malformed_receipt_counter',
      'malformed_device_identity',
      'receipt_sequence_exhausted',
      'invalid_encryption_key',
      'draft_contract_violation',
    ];

    for (final code in unfixable) {
      expect(
        CheckoutRefusal.forCode(code).cashierCanFix,
        isFalse,
        reason: code,
      );
    }
  });

  test('an unrecognised code fails closed but keeps its identity', () {
    expect(fallback.code, 'not-a-real-code');
    expect(fallback.cashierCanFix, isFalse);
    expect(fallback.message, contains('could not be saved'));
  });

  test('maps a thrown draft exception to its own refusal', () {
    for (final code in _codes.keys) {
      final refusal = CheckoutRefusal.forError(CheckoutDraftException(code));

      expect(refusal.code, code);
      expect(refusal.message, CheckoutRefusal.forCode(code).message);
    }
  });

  test('a failure that is not a draft exception still reaches the till', () {
    for (final error in <Object>[
      StateError('hive is closed'),
      const FormatException('corrupt'),
      'a bare string',
    ]) {
      final refusal = CheckoutRefusal.forError(error);

      expect(refusal.code, 'unknown_error');
      expect(refusal.message, fallback.message);
      expect(refusal.cashierCanFix, isFalse);
    }
  });
}
