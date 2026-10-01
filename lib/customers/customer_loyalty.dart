/// Whether customers earn points, and how much they spend for one.
///
/// **Earning only, for now.** The developer ruled on 2026-10-01 that how points
/// are spent is decided later, so this setting says nothing about redeeming and
/// no till offers to. A customer's balance grows as their sales reach the
/// server and shrinks as returns of those sales are verified; that is all.
///
/// **Counted by the server, never the till.** `processCustomerSale` awards a
/// sale its points when it arrives, at the rate this document holds then, so
/// two tills can never disagree about what a sale earned and an offline till
/// can never award points by itself.
library;

import '../tenancy/tenancy.dart';

/// The most a business may ask a customer to spend for one point, in minor
/// units: a million shillings. Above that, nobody earns anything.
const int maximumLoyaltyMinorUnitsPerPoint = 100000000;

/// Strict read model for `tenants/{tenantId}/configuration/loyalty`.
final class TenantLoyaltyPolicy {
  TenantLoyaltyPolicy({required this.enabled, required this.minorUnitsPerPoint}) {
    if (minorUnitsPerPoint < 1 ||
        minorUnitsPerPoint > maximumLoyaltyMinorUnitsPerPoint) {
      throw const FormatException('minorUnitsPerPoint is out of range.');
    }
  }

  /// What a business that has configured nothing behaves like: no points.
  static final TenantLoyaltyPolicy off = TenantLoyaltyPolicy(
    enabled: false,
    minorUnitsPerPoint: defaultMinorUnitsPerPoint,
  );

  /// One point per hundred of the currency's major unit - KES 100 - which is
  /// what the form offers before anybody has chosen.
  static const int defaultMinorUnitsPerPoint = 10000;

  /// Unknown fields are ignored and known ones must be exactly valid.
  factory TenantLoyaltyPolicy.fromMap(Map<String, Object?> map) {
    final enabled = map['enabled'];
    if (enabled is! bool) {
      throw const FormatException('enabled must be true or false.');
    }
    final rate = map['minorUnitsPerPoint'];
    if (rate is! int) {
      throw const FormatException('minorUnitsPerPoint must be a whole number.');
    }
    return TenantLoyaltyPolicy(enabled: enabled, minorUnitsPerPoint: rate);
  }

  final bool enabled;

  /// How much a customer spends, in minor units, to earn one point.
  final int minorUnitsPerPoint;

  /// The points a sale of [totalMinor] earns: whole points only, rounded down,
  /// so a customer is never told about a fraction they do not have.
  int pointsFor(int totalMinor) =>
      enabled && totalMinor > 0 ? totalMinor ~/ minorUnitsPerPoint : 0;

  Map<String, Object?> documentData({required String updatedBy}) =>
      <String, Object?>{
        'enabled': enabled,
        'minorUnitsPerPoint': minorUnitsPerPoint,
        'updatedBy': updatedBy,
      };

  @override
  bool operator ==(Object other) =>
      other is TenantLoyaltyPolicy &&
      other.enabled == enabled &&
      other.minorUnitsPerPoint == minorUnitsPerPoint;

  @override
  int get hashCode => Object.hash(enabled, minorUnitsPerPoint);
}

/// Whether this business has a loyalty setting, and whether it could be read.
enum TenantLoyaltyState { published, absent, malformed }

final class TenantPublishedLoyalty {
  const TenantPublishedLoyalty._(this.state, this._policy);

  const TenantPublishedLoyalty.published(TenantLoyaltyPolicy policy)
    : this._(TenantLoyaltyState.published, policy);

  const TenantPublishedLoyalty.absent() : this._(TenantLoyaltyState.absent, null);

  const TenantPublishedLoyalty.malformed()
    : this._(TenantLoyaltyState.malformed, null);

  final TenantLoyaltyState state;
  final TenantLoyaltyPolicy? _policy;

  /// The published policy, or no points - which is also what the server does
  /// with a document it cannot read.
  TenantLoyaltyPolicy get policy => _policy ?? TenantLoyaltyPolicy.off;

  TenantLoyaltyPolicy? get published => _policy;
}

/// Reads one business's loyalty setting.
final class TenantLoyaltyRepository extends TenantReadRepository {
  TenantLoyaltyRepository({required super.session, required super.reader});

  static const documentId = 'loyalty';

  /// Owner and administrator write it, which the `configuration/{documentId}`
  /// rule already allows; every member reads it, because the till shows points.
  static const List<TenantRole> writeRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
  ];

  Future<TenantPublishedLoyalty> load() async {
    final data = await readDocument(TenantCollection.configuration, documentId);
    if (data == null) return const TenantPublishedLoyalty.absent();
    try {
      return TenantPublishedLoyalty.published(TenantLoyaltyPolicy.fromMap(data));
    } on FormatException {
      return const TenantPublishedLoyalty.malformed();
    }
  }
}

/// Raised when a loyalty change is refused before anything is written.
final class TenantLoyaltyException implements Exception {
  const TenantLoyaltyException(this.code);

  final String code;

  @override
  String toString() => 'TenantLoyaltyException($code)';
}

/// One loyalty change, ready to be written.
final class TenantLoyaltyIntent {
  const TenantLoyaltyIntent._({
    required this.path,
    required this.policy,
    required this.updatedBy,
  });

  final String path;
  final TenantLoyaltyPolicy policy;
  final String updatedBy;

  Map<String, Object?> documentData() =>
      policy.documentData(updatedBy: updatedBy);
}

final class TenantLoyaltyPublisher extends TenantReadRepository {
  TenantLoyaltyPublisher({required super.session, required super.reader});

  static const List<TenantRole> allowedRoles = TenantLoyaltyRepository.writeRoles;

  /// Builds the one instruction the form describes. Every refusal is here.
  TenantLoyaltyIntent buildIntent({
    required bool enabled,
    required int? minorUnitsPerPoint,
    required TenantPublishedLoyalty published,
  }) {
    if (!session.canAccess(allowedRoles: allowedRoles)) {
      throw const TenantLoyaltyException('loyalty_forbidden');
    }
    final TenantLoyaltyPolicy policy;
    try {
      policy = TenantLoyaltyPolicy(
        enabled: enabled,
        minorUnitsPerPoint:
            minorUnitsPerPoint ??
            (enabled
                ? 0
                : published.policy.minorUnitsPerPoint),
      );
    } on FormatException {
      throw const TenantLoyaltyException('invalid_rate');
    }
    // Re-saving the identical document rewrites who changed it and when, for a
    // setting that did not change.
    if (published.published == policy) {
      throw const TenantLoyaltyException('loyalty_unchanged');
    }
    return TenantLoyaltyIntent._(
      path: paths.configurationDocument(TenantLoyaltyRepository.documentId),
      policy: policy,
      updatedBy: session.uid,
    );
  }
}
