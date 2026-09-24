/// Reads the branding a report is headed with.
///
/// **The composition root's job, done once per report.** The renderers take an
/// identity and read nothing; this is what fills one in. It is the same shape
/// `main.dart` already uses for a receipt - read the branding document, fetch
/// the logo bytes, hand both to a builder that does no I/O of its own.
library;

import 'dart:typed_data';

import '../inventory/product_image_cache.dart';
import '../inventory/product_image_provider.dart';
import '../reporting/reporting_currency.dart';
import '../tenancy/tenant_branding.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_session.dart';
import 'report_identity.dart';

/// How long a report waits for a logo before going without one.
///
/// The receipt path allows five seconds for the same fetch. A report is not
/// being held over a till while somebody waits for change, so it can afford a
/// little longer - but not so long that an offline device makes the person
/// think the button did nothing.
const Duration tenantReportLogoTimeout = Duration(seconds: 8);

/// Composes the identity a report is headed with.
Future<TenantReportIdentity> readTenantReportIdentity({
  required TenantSession session,
  required TenantDataReader reader,
  required DateTime generatedAt,
  TenantImageCache? imageCache,
  String? generatedByName,
}) async {
  // Both are ordinary Firestore reads served from the offline copy when there
  // is one, so they are started together rather than one waiting on the other.
  final brandingRead = TenantBrandingRepository(
    session: session,
    reader: reader,
  ).loadOrRegistered();
  final currencyRead = TenantReportingCurrency.read(
    session: session,
    reader: reader,
  );

  TenantBranding? branding;
  try {
    branding = await brandingRead;
  } on Object {
    // A business whose branding cannot be read still gets its report. The
    // cover falls back to a plain heading rather than refusing.
    branding = null;
  }
  final currency = await currencyRead;

  Uint8List? logo;
  if (branding?.logoUrl case final url?) {
    logo = await loadTenantImageBytes(
      url,
      cache: imageCache,
      timeout: tenantReportLogoTimeout,
    );
  }

  return TenantReportIdentity(
    businessName: branding?.companyName.trim().isNotEmpty ?? false
        ? branding!.companyName
        : unnamedTenantReportBusiness,
    slogan: branding?.slogan,
    logo: logo,
    currency: currency,
    generatedAt: generatedAt,
    generatedByName: generatedByName,
    generatedByRole: session.role,
  );
}

/// What a report calls a business that has published no name.
///
/// **Never left blank.** A cover page with an empty lockup reads as a broken
/// document rather than an unconfigured one, and the person holding it cannot
/// tell which.
const String unnamedTenantReportBusiness = 'This business';
