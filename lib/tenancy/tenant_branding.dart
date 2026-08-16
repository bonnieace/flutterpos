import 'package:flutter/material.dart';

import '../ui/status.dart';
import 'tenant_paths.dart';
import 'tenant_repository.dart';
import 'tenant_types.dart';

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
///
/// **It no longer draws the business's name, and no longer loads it.** §11 step
/// 5b made `branding.companyName` the home's *title*, and §7's "title appears
/// once" makes drawing it again here a duplicate rather than a heading. The
/// route resolves the document once, above its own header, and hands the result
/// down - which also removes the second read this panel used to make of a
/// document the route had already fetched.
///
/// **What is left is what was never the title**: the slogan, which is the one
/// branding field with nowhere else to go, and the session's own standing.
final class TenantBrandingPanel extends StatelessWidget {
  const TenantBrandingPanel({
    super.key,
    required this.branding,
  });

  /// The resolved document, or null where the business has published none.
  final TenantBranding? branding;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.verified_user_outlined, size: 52),
      const SizedBox(height: 16),
      if (branding?.slogan case final slogan?) ...[
        Text(slogan, textAlign: TextAlign.center),
        const SizedBox(height: 8),
      ],
      // **The role line left this panel on 2026-08-16 and did not lose a
      // reader.** `design.md` v0.7 gives the home's top bar "the signed-in
      // member and their role", so `AppScaffold.subtitle` states it one line
      // under the business name - and the first picture of that showed
      // "Signed in as Owner" twice on one screen, which is §7's "title appears
      // once" failing for the identity rather than for the title.
      //
      // v0.7 predicted exactly this and said what to do: the panel "stops
      // drawing the name, because a title appears once". The same argument
      // reaches the role, one line down.
      const SizedBox(height: 16),
      // §5.1 sends a permanent notice paragraph to a `Callout`, and this is
      // one. It stayed a `Text` until now only because the landing route was
      // step 5b's and step 4's notice sweep could not touch it; this is step
      // 5b, so the container it was waiting for is no longer blocked.
      //
      // The wording is §8 rule 1's, settled by step 11 - the rule quotes the
      // sentence this replaced as its own worked example of "a commit message
      // on a production screen".
      const Callout(
        status: AppStatus.info,
        message: "Some screens aren't available yet.",
      ),
    ],
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
