import 'package:uzapay_pos/tenancy/phone_number.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('turning what is typed into E.164', () {
    const tanzania = DialCode(country: 'Tanzania', code: '+255');

    test('the trunk zero is punctuation, not part of the number', () {
      // `0712 345 678` is how the number is printed on a SIM pack and how
      // everybody writes it down. The leading zero is a domestic dialling
      // prefix; E.164 has no place for it. Somebody who types it is not making
      // a mistake and must not be refused for one.
      for (final typed in <String>[
        '0712345678',
        '0712 345 678',
        '0712-345-678',
        '(0712) 345 678',
        '712345678',
        '712 345 678',
      ]) {
        expect(
          normalizeE164(dialCode: tanzania, localNumber: typed),
          '+255712345678',
          reason: typed,
        );
      }
    });

    test('a number with nothing in it is named as empty, not as invalid', () {
      expect(
        phoneNumberDefect(dialCode: tanzania, localNumber: '   '),
        'Enter your mobile number.',
      );
    });

    test('a short number says it is short', () {
      expect(
        phoneNumberDefect(dialCode: tanzania, localNumber: '12345'),
        'That number is too short.',
      );
    });

    test('a plausible number has nothing wrong with it', () {
      expect(
        phoneNumberDefect(dialCode: tanzania, localNumber: '0712 345 678'),
        isNull,
      );
    });

    test('a number too long for E.164 is refused', () {
      expect(
        phoneNumberDefect(dialCode: tanzania, localNumber: '7123456789012345'),
        isNotNull,
      );
    });
  });

  group('recovering the two halves of a stored number', () {
    test('the longest matching code wins', () {
      // +255 must never be read as +2, which is why the candidates are sorted
      // by length rather than taken in list order.
      final split = splitE164('+255712345678');
      expect(split?.dialCode.code, '+255');
      expect(split?.localNumber, '712345678');
    });

    test('a one-digit code still resolves', () {
      final split = splitE164('+15551234567');
      expect(split?.dialCode.code, '+1');
      expect(split?.localNumber, '5551234567');
    });

    test('an unrecognised country is null rather than a wrong guess', () {
      // Answering with the wrong code would rewrite somebody's number on the
      // next save, which is worse than starting them from the default.
      expect(splitE164('+998901234567'), isNull);
      expect(splitE164('0712345678'), isNull);
      expect(splitE164(null), isNull);
    });

    test('a code with no subscriber digits is not a number', () {
      expect(splitE164('+255'), isNull);
    });

    test('every offered code round-trips', () {
      for (final code in dialCodes) {
        final e164 = normalizeE164(dialCode: code, localNumber: '712345678');
        final split = splitE164(e164);
        expect(split?.dialCode.code, code.code, reason: code.country);
      }
    });
  });
}
