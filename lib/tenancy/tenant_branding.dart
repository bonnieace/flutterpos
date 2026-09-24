import 'tenant_paths.dart';
import 'tenant_repository.dart';

/// Read-only branding fields stored in `configuration/branding`.
final class TenantBranding {
  const TenantBranding({required this.companyName, this.slogan, this.logoUrl});

  factory TenantBranding.fromMap(Map<String, Object?> map) {
    final companyName = _requiredString(map, 'companyName');
    return TenantBranding(
      companyName: companyName,
      slogan: _optionalString(map, 'slogan'),
      logoUrl: _optionalHttpsUrl(map, 'logoUrl'),
    );
  }

  final String companyName;
  final String? slogan;
  final Uri? logoUrl;
}

final class TenantBrandingRepository extends TenantReadRepository {
  TenantBrandingRepository({required super.session, required super.reader});

  static const documentId = 'branding';

  Future<TenantBranding?> load() async {
    final data = await readDocument(TenantCollection.configuration, documentId);
    return data == null ? null : TenantBranding.fromMap(data);
  }

  /// [load], or the name this business registered under where nothing has
  /// been published.
  ///
  /// **The registered name is fixed at signup and is what Business details
  /// shows, read-only**, so a business that never saved that screen is not
  /// unnamed - it simply has no slogan or logo yet. Null only where neither
  /// document can be read, which a cache-only reader on a device that has
  /// never opened the home can still be.
  Future<TenantBranding?> loadOrRegistered() async {
    final published = await load();
    if (published != null) return published;
    final name = registeredTenantName(await readTenantRoot());
    return name == null ? null : TenantBranding(companyName: name);
  }
}

/// The name on the tenant document, written once at signup.
String? registeredTenantName(Map<String, Object?>? tenant) {
  final name = tenant?['name'];
  return name is String && name.trim().isNotEmpty ? name.trim() : null;
}

String _requiredString(Map<String, Object?> map, String field) {
  final value = map[field];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$field must be a non-empty string.');
  }
  return value.trim();
}

String? _optionalString(Map<String, Object?> map, String field) {
  final value = map[field];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$field must be a non-empty string when present.');
  }
  return value.trim();
}

Uri? _optionalHttpsUrl(Map<String, Object?> map, String field) {
  final value = _optionalString(map, field);
  if (value == null) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    throw FormatException('$field must be an HTTPS URL when present.');
  }
  return uri;
}
