import '../checkout/checkout_configuration.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_session.dart';
import '../ui/money_text.dart';

/// The ISO 4217 code a reported figure is labelled with, or nothing at all.
///
/// Reporting never *assumes* a currency. A business trading in one and reported
/// in another is a worse error than an unlabelled number, and there is no
/// defensible default: the app targets no single country, and the frozen model
/// records the code per business in `configuration/checkout` precisely so that
/// nothing has to guess. So a missing, unreadable, or malformed configuration
/// produces a bare amount and a sentence saying why, never a guessed code.
///
/// A business that has never published that document cannot use the till at
/// all - `CheckoutCatalogCacheRefresher` refuses with `configurationUnavailable`
/// - so a business with sales to report has a currency, and the unlabelled case
/// is genuinely the unconfigured one.
final class TenantReportingCurrency {
  const TenantReportingCurrency._(this.code);

  /// No usable currency was published for this business.
  static const TenantReportingCurrency unknown = TenantReportingCurrency._(
    null,
  );

  /// Reads the business's published code, degrading rather than failing.
  ///
  /// A figure is the reason a reporting route exists; its label is not. So an
  /// absent or unreadable configuration removes the label and keeps the figure.
  /// A [TenantScopeViolation] is the one exception and is rethrown: a reader
  /// answering outside this tenant is a broken boundary rather than a missing
  /// label, and it must not be degraded into a quiet one.
  static Future<TenantReportingCurrency> read({
    required TenantSession session,
    required TenantDocumentReader reader,
  }) async {
    try {
      final configuration = await TenantCheckoutConfigurationRepository(
        session: session,
        reader: reader,
      ).load();
      return configuration == null
          ? unknown
          : TenantReportingCurrency._(configuration.currency);
    } on TenantScopeViolation {
      rethrow;
    } catch (_) {
      return unknown;
    }
  }

  /// Lets a test state a currency this business never published.
  ///
  /// **The `TenantCollectionQuery.forTesting` bargain, for the same reason.**
  /// [read] is the only way production code gets a code, and it needs a session
  /// and a reader to do it - which meant that until this existed, every test
  /// touching a reported figure had to use [unknown], and the labelled path
  /// (`KES 1234.50`) was the one a suite could not reach. A report is mostly
  /// columns of money, so that gap was the wrong one to carry.
  ///
  /// This constructs nothing production code can reach by accident: [read] is
  /// still the only caller that turns a configuration document into a code, and
  /// it still degrades to [unknown] rather than guessing.
  factory TenantReportingCurrency.forTesting(String code) =>
      TenantReportingCurrency._(code);

  final String? code;

  bool get isKnown => code != null;

  /// Formats one major-unit amount, with the code when there is one.
  String format(num amount) {
    final figure = moneyText(amount);
    final code = this.code;
    return code == null ? figure : '$code $figure';
  }

  /// The sentence shown once on a surface whose figures carry no code.
  static const String unknownNotice =
      'This business has published no currency, so the amounts below carry no '
      'code.';
}
