/// Publishing one business's own name, slogan and logo.
///
/// **The gap this closes.** `TenantBrandingRepository` has always *read*
/// `configuration/branding` - it is what titles the home and heads a printed
/// receipt - and nothing has ever written it. On a single-tenant install that
/// was a one-off seed somebody did by hand in the Firestore console. On real
/// multitenancy it means every business that signs itself up trades under a
/// blank name and prints an unbranded receipt, with no way to fix it from
/// inside the product.
///
/// **Shaped exactly like `TenantCheckoutConfigurationPublisher`**, deliberately:
/// `loadPublished` degrades a malformed document into a state rather than a
/// failure, `buildUpdateIntent` refuses a republish that would change nothing,
/// and the write answers in the four outcomes every write boundary in this app
/// answers in. The Firestore half is `TenantConfigurationDocumentWriter`, which
/// already merges any `configuration/*` document - a third copy of that
/// boilerplate would have been the thing it was written to prevent.
library;

import 'tenant_branding.dart';
import 'tenant_paths.dart';
import 'tenant_session.dart';
import 'tenant_repository.dart';
import 'tenant_types.dart';

/// What this business has published, or why it has not.
sealed class TenantPublishedBranding {
  const TenantPublishedBranding();

  const factory TenantPublishedBranding.absent() = _BrandingAbsent;
  const factory TenantPublishedBranding.malformed() = _BrandingMalformed;
  const factory TenantPublishedBranding.published(TenantBranding branding) =
      _BrandingPublished;

  /// The branding itself, where there is usable branding.
  TenantBranding? get branding => switch (this) {
    _BrandingPublished(:final value) => value,
    _ => null,
  };

  /// Whether the home and a receipt have a name to carry.
  bool get isUsable => branding != null;

  /// Whether a document is there and cannot be read.
  bool get isMalformed => this is _BrandingMalformed;
}

final class _BrandingAbsent extends TenantPublishedBranding {
  const _BrandingAbsent();
}

final class _BrandingMalformed extends TenantPublishedBranding {
  const _BrandingMalformed();
}

final class _BrandingPublished extends TenantPublishedBranding {
  const _BrandingPublished(this.value);
  final TenantBranding value;
}

final class TenantBrandingException implements Exception {
  const TenantBrandingException(this.code);

  final String code;

  @override
  String toString() => 'TenantBrandingException($code)';
}

/// One publish instruction, with the path already resolved from the session.
final class TenantBrandingUpdateIntent {
  const TenantBrandingUpdateIntent._({
    required this.path,
    required this.tenantId,
    required this.companyName,
    required this.slogan,
    required this.logoUrl,
    required this.updatedBy,
  });

  final String path;
  final String tenantId;
  final String companyName;

  /// Null clears a slogan that was published before.
  final String? slogan;

  /// Null clears a logo that was published before.
  final Uri? logoUrl;

  final String updatedBy;

  /// The exact keys written. Nulls are written as nulls rather than omitted, so
  /// clearing a slogan clears it - a merge that left the key out would leave
  /// the old one standing.
  Map<String, Object?> toDocument() => <String, Object?>{
    'companyName': companyName,
    'slogan': slogan,
    'logoUrl': logoUrl?.toString(),
    'updatedBy': updatedBy,
  };
}

/// Guarded intent boundary for publishing one business's branding.
///
/// A second class rather than a method on [TenantBrandingRepository], for the
/// reason the checkout publisher gives: every active member reads the branding -
/// the home is titled with it - and only an owner or administrator may change
/// it, so the two capabilities do not share a boundary.
final class TenantBrandingPublisher extends TenantReadRepository {
  TenantBrandingPublisher({required super.session, required super.reader});

  /// Owner and administrator, which is what the `configuration/{documentId}`
  /// rule allows. A manager runs a till; naming the business is not that.
  static const List<TenantRole> allowedRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
  ];

  static bool canPublishInSession(TenantSession session) =>
      session.canAccess(allowedRoles: allowedRoles);

  /// The longest name a receipt header can carry without wrapping oddly on the
  /// narrowest supported paper. Enforced here so the refusal happens while the
  /// field is still on screen.
  static const int maximumCompanyNameLength = 60;
  static const int maximumSloganLength = 120;

  Future<TenantPublishedBranding> loadPublished() async {
    final data = await readDocument(
      TenantCollection.configuration,
      TenantBrandingRepository.documentId,
    );
    if (data == null) return const TenantPublishedBranding.absent();
    try {
      return TenantPublishedBranding.published(TenantBranding.fromMap(data));
    } on FormatException {
      return const TenantPublishedBranding.malformed();
    }
  }

  /// Builds the one publish instruction these values describe.
  ///
  /// Normalized here rather than in the widget: trailing space in a business
  /// name is not a different business, and a receipt that printed one would be
  /// the only place anybody ever noticed.
  TenantBrandingUpdateIntent buildUpdateIntent({
    required String companyName,
    String? slogan,
    String? logoUrl,
    required TenantPublishedBranding published,
  }) {
    if (!session.canAccess(allowedRoles: allowedRoles)) {
      throw const TenantBrandingException('branding_forbidden');
    }
    final name = companyName.trim();
    if (name.isEmpty) {
      throw const TenantBrandingException('missing_company_name');
    }
    if (name.length > maximumCompanyNameLength) {
      throw const TenantBrandingException('company_name_too_long');
    }
    final trimmedSlogan = slogan?.trim();
    final normalizedSlogan =
        trimmedSlogan == null || trimmedSlogan.isEmpty ? null : trimmedSlogan;
    if (normalizedSlogan != null &&
        normalizedSlogan.length > maximumSloganLength) {
      throw const TenantBrandingException('slogan_too_long');
    }
    final normalizedLogo = _validatedLogo(logoUrl);

    // Republishing identical values would rewrite the provenance and ask every
    // device to re-read a document that cannot have changed. A malformed or
    // absent document is never "unchanged": that is the state this exists to
    // leave.
    final current = published.branding;
    if (current != null &&
        current.companyName == name &&
        current.slogan == normalizedSlogan &&
        current.logoUrl?.toString() == normalizedLogo?.toString()) {
      throw const TenantBrandingException('branding_unchanged');
    }

    return TenantBrandingUpdateIntent._(
      path: paths.configurationDocument(TenantBrandingRepository.documentId),
      tenantId: session.tenantId,
      companyName: name,
      slogan: normalizedSlogan,
      logoUrl: normalizedLogo,
      updatedBy: session.uid,
    );
  }

  /// HTTPS only, matching what [TenantBranding] will accept when it reads the
  /// document back. A logo this refused to publish but would refuse to read is
  /// worse than one refused twice.
  Uri? _validatedLogo(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const TenantBrandingException('invalid_logo_url');
    }
    return uri;
  }
}

/// The sentence shown for one refused publish.
String tenantBrandingFailureMessage(Object error) {
  if (error is! TenantBrandingException) {
    return 'The business details could not be saved. Try again.';
  }
  return switch (error.code) {
    'branding_forbidden' =>
      'An owner or an administrator changes the business details.',
    'missing_company_name' => 'Enter the name this business trades under.',
    'company_name_too_long' =>
      'That name is too long for a receipt header. Use at most '
          '${TenantBrandingPublisher.maximumCompanyNameLength} characters.',
    'slogan_too_long' =>
      'That line is too long. Use at most '
          '${TenantBrandingPublisher.maximumSloganLength} characters.',
    'invalid_logo_url' =>
      'A logo address must start with https:// and name a host.',
    'branding_unchanged' => 'These are already the published details.',
    _ => 'The business details could not be saved. Try again.',
  };
}
