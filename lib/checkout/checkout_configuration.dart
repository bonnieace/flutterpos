import '../tenancy/tenant_paths.dart';
import '../tenancy/tenant_repository.dart';

final RegExp _currencyPattern = RegExp(r'^[A-Z]{3}$');

/// Strict read model for `tenants/{tenantId}/configuration/checkout`.
///
/// Checkout configuration is tenant-owned operational data, so it is read
/// through the guarded tenant repository boundary rather than hard-coded in a
/// composition root. A missing or malformed document fails closed: the offline
/// cache is left untouched and no draft can be priced from a guessed default.
final class TenantCheckoutConfiguration {
  TenantCheckoutConfiguration({required String currency})
    : currency = _validatedCurrency(currency);

  /// Parses the canonical configuration document.
  ///
  /// Unknown fields are ignored so later configuration settings do not break
  /// this slice, but every field checkout depends on must be exactly valid.
  factory TenantCheckoutConfiguration.fromMap(Map<String, Object?> map) {
    final currency = map['currency'];
    if (currency is! String) {
      throw const FormatException('currency must be an ISO 4217 code.');
    }
    return TenantCheckoutConfiguration(currency: currency);
  }

  /// The ISO 4217 code recorded on every sale priced with this configuration.
  final String currency;

  /// The minimal projection persisted in the encrypted offline cache.
  Map<String, Object?> toCacheEntry() => <String, Object?>{
    'currency': currency,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TenantCheckoutConfiguration && currency == other.currency;

  @override
  int get hashCode => currency.hashCode;
}

/// Guarded read-only repository for one tenant's checkout configuration.
final class TenantCheckoutConfigurationRepository extends TenantReadRepository {
  TenantCheckoutConfigurationRepository({
    required super.session,
    required super.reader,
  });

  static const documentId = 'checkout';

  /// Returns the configuration, or `null` when the document does not exist.
  Future<TenantCheckoutConfiguration?> load() async {
    final data = await readDocument(TenantCollection.configuration, documentId);
    return data == null ? null : TenantCheckoutConfiguration.fromMap(data);
  }
}

String _validatedCurrency(String currency) {
  if (!_currencyPattern.hasMatch(currency)) {
    throw const FormatException(
      'currency must be a three-letter ISO 4217 code.',
    );
  }
  return currency;
}
