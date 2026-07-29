import 'package:flutter/material.dart';

import 'tenant_paths.dart';
import 'tenant_repository.dart';
import 'tenant_route_guard.dart';

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
}

/// The first migrated read-only tenant slice used by the safe landing route.
final class TenantBrandingPanel extends StatelessWidget {
  const TenantBrandingPanel({
    super.key,
    required this.reader,
    required this.fallbackName,
  });

  final TenantDocumentReader reader;
  final String fallbackName;

  @override
  Widget build(BuildContext context) => TenantRouteGuard<TenantBranding?>(
    load: (session) =>
        TenantBrandingRepository(session: session, reader: reader).load(),
    builder: (context, session, branding) {
      final name = branding?.companyName ?? fallbackName;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified_user_outlined, size: 52),
          const SizedBox(height: 16),
          Text(name, style: Theme.of(context).textTheme.headlineSmall),
          if (branding?.slogan != null) ...[
            const SizedBox(height: 6),
            Text(branding!.slogan!, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 8),
          Text('Signed in as ${session.role.wireValue}'),
          const SizedBox(height: 16),
          const Text(
            'Operational screens remain locked until their data access is '
            'migrated to tenant-scoped repositories.',
            textAlign: TextAlign.center,
          ),
        ],
      );
    },
  );
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
