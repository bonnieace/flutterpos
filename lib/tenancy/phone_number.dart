/// Turning what somebody types into the one form E.164 allows.
///
/// **Why a country code beside the digits rather than one free field.** A number
/// written down in Tanzania is `0712 345 678`, and the same number in E.164 is
/// `+255712345678` - the leading zero is a domestic dialling prefix that is not
/// part of the number and the country code is not written at all. A single field
/// asks a person to perform that conversion themselves, and most will type what
/// is printed on their own SIM pack. Splitting the control means the app does the
/// conversion and the person answers the question they can answer.
///
/// Pure, so every rule here is testable without a widget. The server applies the
/// same shape in `normalizePhoneNumber`; these two must agree, and the test suite
/// is where that is pinned.
library;

/// One row of the dialling-code selector.
final class DialCode {
  const DialCode({required this.country, required this.code});

  /// The country as somebody would name it, not its ISO letters.
  final String country;

  /// The dialling code including its plus, as it is displayed.
  final String code;

  /// Just the digits, which is what E.164 wants.
  String get digits => code.replaceAll(_nonDigits, '');

  @override
  String toString() => '$country ($code)';
}

/// The codes offered, East Africa first.
///
/// **Ordered by who is actually signing up rather than alphabetically.** The
/// list is short on purpose; it is not a world atlas, and a country missing from
/// it is a line to add here rather than a defect in the control.
const List<DialCode> dialCodes = <DialCode>[
  DialCode(country: 'Kenya', code: '+254'),
  DialCode(country: 'Tanzania', code: '+255'),
  DialCode(country: 'Uganda', code: '+256'),
  DialCode(country: 'Rwanda', code: '+250'),
  DialCode(country: 'Burundi', code: '+257'),
  DialCode(country: 'DR Congo', code: '+243'),
  DialCode(country: 'Zambia', code: '+260'),
  DialCode(country: 'Malawi', code: '+265'),
  DialCode(country: 'Mozambique', code: '+258'),
  DialCode(country: 'South Africa', code: '+27'),
  DialCode(country: 'Ethiopia', code: '+251'),
  DialCode(country: 'Somalia', code: '+252'),
  DialCode(country: 'United Kingdom', code: '+44'),
  DialCode(country: 'United States', code: '+1'),
  DialCode(country: 'India', code: '+91'),
  DialCode(country: 'China', code: '+86'),
  DialCode(country: 'United Arab Emirates', code: '+971'),
];

/// The one offered by default.
///
/// **Kenya since 2026-10-08**, at the developer's direction: signing up opened
/// on Tanzania, and the people signing up are in Kenya.
const DialCode defaultDialCode = DialCode(country: 'Kenya', code: '+254');

final _nonDigits = RegExp(r'[^0-9]');
final _leadingZeroes = RegExp(r'^0+');

/// E.164: a plus, a non-zero country digit, then seven to fourteen more.
final _e164Pattern = RegExp(r'^\+[1-9]\d{7,14}$');

/// The subscriber digits, with the punctuation and the trunk prefix removed.
///
/// **The leading zero goes.** `0712 345 678` and `712 345 678` are the same
/// number written for two different dialling contexts, and E.164 has only the
/// second. Somebody who types the zero out of habit is not making a mistake and
/// must not be told they are.
String localSubscriberDigits(String value) =>
    value.replaceAll(_nonDigits, '').replaceFirst(_leadingZeroes, '');

/// Joins a dialling code and a local number into one E.164 string.
///
/// Returns the string whether or not it is valid; [phoneNumberDefect] is what
/// judges it, so a caller can show the number it is about to send while it is
/// still being typed.
String normalizeE164({required DialCode dialCode, required String localNumber}) =>
    '+${dialCode.digits}${localSubscriberDigits(localNumber)}';

/// What is wrong with this number, or null when nothing is.
///
/// One sentence per case, and never "invalid": a person who has typed their own
/// number correctly and been refused needs to know which part this disagrees
/// with.
String? phoneNumberDefect({
  required DialCode dialCode,
  required String localNumber,
}) {
  final local = localSubscriberDigits(localNumber);
  if (local.isEmpty) return 'Enter your mobile number.';
  if (local.length < 6) return 'That number is too short.';
  final e164 = normalizeE164(dialCode: dialCode, localNumber: localNumber);
  if (!_e164Pattern.hasMatch(e164)) {
    return 'That does not look like a mobile number.';
  }
  return null;
}

/// Recovers the two halves of a stored E.164 number, for resuming a signup.
///
/// Returns null where nothing in [dialCodes] prefixes it - a number saved before
/// this list carried its country. The caller then starts from the default rather
/// than showing a code that would rewrite somebody's number on the next save.
({DialCode dialCode, String localNumber})? splitE164(String? stored) {
  if (stored == null || !stored.startsWith('+')) return null;
  final digits = stored.replaceAll(_nonDigits, '');
  // Longest first, so +255 is never read as +2.
  final ordered = [...dialCodes]
    ..sort((a, b) => b.digits.length.compareTo(a.digits.length));
  for (final candidate in ordered) {
    if (digits.startsWith(candidate.digits) &&
        digits.length > candidate.digits.length) {
      return (
        dialCode: candidate,
        localNumber: digits.substring(candidate.digits.length),
      );
    }
  }
  return null;
}
