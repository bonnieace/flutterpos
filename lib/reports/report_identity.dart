/// Whose business this is, and how its money is written.
///
/// **Everything here is passed in, never read here.** This is the shape
/// `CheckoutReceiptBody` already uses: it takes a business name, a slogan and
/// logo bytes and does no I/O of its own, so the thing that lays out a document
/// can be exercised without a network, a tenant or a Firebase project. The
/// composition root reads the branding document and fetches the logo; this
/// object is what it hands over.
///
/// It carries only what the tenant model actually holds. `TenantBranding` is a
/// company name, an optional slogan and an optional logo URL - there is no
/// address, no telephone number, no tax or VAT registration and no configurable
/// footer anywhere in the model. A report prints what exists. It does not
/// invent a letterhead the business never gave it.
library;

import 'dart:typed_data';

import '../reporting/reporting_currency.dart';
import '../tenancy/tenant_types.dart';

/// The business a report is about, and who asked for it.
final class TenantReportIdentity {
  const TenantReportIdentity({
    required this.businessName,
    required this.currency,
    required this.generatedAt,
    required this.generatedByName,
    required this.generatedByRole,
    this.slogan,
    this.logo,
  });

  /// `TenantBranding.companyName`, or a stand-in where none was published.
  final String businessName;

  final String? slogan;

  /// The logo, already fetched.
  ///
  /// Null where the business published none, where the fetch timed out, or
  /// where the device is offline - all three are ordinary, and a report simply
  /// sets its name in type instead. `loadTenantImageBytes` answers null rather
  /// than throwing for exactly this reason.
  final Uint8List? logo;

  final TenantReportingCurrency currency;

  final DateTime generatedAt;

  /// Who asked for the report, printed so a document found later can be traced
  /// to the person who took it off the device.
  ///
  /// **Nullable, because the session does not carry one.** A `TenantSession`
  /// holds a uid and a role; a person's name lives in the staff directory,
  /// which is a separate read a report does not always make. Printing the uid
  /// would be worse than printing nothing - it identifies nobody a reader
  /// knows - so an absent name falls back to the role alone.
  final String? generatedByName;

  final TenantRole generatedByRole;

  /// How the cover attributes the report.
  ///
  /// The article is picked rather than hardcoded, because *a owner* and *a
  /// admin* are two of the four roles and both read as a typo on a document
  /// somebody is about to send their accountant.
  String get generatedBy {
    final role = generatedByRole.name;
    if (generatedByName case final name?) return '$name ($role)';
    final article = _vowels.contains(role[0]) ? 'an' : 'a';
    return '$article $role';
  }

  static const String _vowels = 'aeiou';

  /// Money as this business writes it.
  ///
  /// **One formatter, used by both renderers and by every analysis.** The rule
  /// `TenantReportingCurrency` sets is that reporting never guesses a currency:
  /// a business with no published code gets a bare figure and a sentence saying
  /// why, never a symbol and never a default. Routing every figure through here
  /// is what keeps a PDF and a workbook from disagreeing about that.
  String money(int minorUnits) => currency.format(minorUnits / 100);

  /// A signed figure, for a variance that reads differently above and below
  /// zero.
  String signedMoney(int minorUnits) {
    final written = money(minorUnits.abs());
    if (minorUnits > 0) return '+$written';
    if (minorUnits < 0) return '-$written';
    return written;
  }

  /// The sentence to print where the business has published no currency.
  ///
  /// Null when there is a code, so a cover page can print it or not without
  /// asking a second question.
  String? get currencyNotice =>
      currency.isKnown ? null : TenantReportingCurrency.unknownNotice;

  /// The business name reduced to something safe in a filename.
  ///
  /// ASCII only, because the file crosses a share sheet into whatever
  /// filesystem the person picked, and a name that arrives mangled is worse
  /// than one that arrives plain.
  String get slug {
    final ascii = businessName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (ascii.isEmpty) return 'report';
    return ascii.length <= _slugLimit ? ascii : ascii.substring(0, _slugLimit);
  }

  static const int _slugLimit = 40;
}
