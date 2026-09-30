/// Who may sell for a price agreed with the customer, rather than the listed one.
///
/// **A list of people, and nobody by default - the owner included.** The
/// developer ruled on 2026-09-29 that anybody may be allowed to agree a price,
/// but only by being named here, set up the way the stock count rota is. A
/// business that has never opened this setting sells at the listed price on
/// every till, which is what the till did before the setting existed.
///
/// **It guards the till, not the server, and that was ruled on too.** Firestore
/// Rules do not read a sale's prices at all - a sale line is checked for a
/// product and a quantity - so a check here could only ever stop the honest
/// app. The same ruling says that is enough: what makes an agreed price
/// answerable is that the sale keeps the listed prices, the agreed total and
/// the reason, and the reports already show each person's discount rate.
library;

import '../tenancy/tenancy.dart';

/// The most people one business may allow to agree a price.
///
/// Bounded because the document is read by every till on the way in, and the
/// stock count rota's bound is the same for the same reason.
const int maximumPriceAgreementPeople = 50;

/// Strict read model for `tenants/{tenantId}/configuration/price_agreement`.
final class TenantPriceAgreementPolicy {
  TenantPriceAgreementPolicy({required Set<String> allowed})
    : allowed = Set<String>.unmodifiable(allowed) {
    if (allowed.length > maximumPriceAgreementPeople) {
      throw const FormatException('too many people are allowed.');
    }
    for (final uid in allowed) {
      if (uid.isEmpty) {
        throw const FormatException('an allowed person must be a member.');
      }
    }
  }

  /// What a business that has configured nothing behaves like: nobody.
  static final TenantPriceAgreementPolicy none = TenantPriceAgreementPolicy(
    allowed: const <String>{},
  );

  /// Unknown fields are ignored and known ones must be exactly valid, which is
  /// the asymmetry every configuration document here uses.
  ///
  /// **A person is an object, not a bare ID**, so a later limit per person - a
  /// largest discount, say - is a field beside `uid` rather than a new shape.
  factory TenantPriceAgreementPolicy.fromMap(Map<String, Object?> map) {
    final allowed = map['allowed'];
    if (allowed is! List) {
      throw const FormatException('allowed must be a list.');
    }
    return TenantPriceAgreementPolicy(
      allowed: <String>{
        for (final entry in allowed)
          if (entry is Map)
            _uid(entry)
          else
            throw const FormatException('an allowed person must be an object.'),
      },
    );
  }

  static String _uid(Map<Object?, Object?> entry) {
    final uid = entry['uid'];
    if (uid is! String || uid.isEmpty) {
      throw const FormatException('an allowed person must name a member.');
    }
    return uid;
  }

  final Set<String> allowed;

  /// Whether [uid] may agree a price at the till.
  bool allows(String uid) => allowed.contains(uid);

  Map<String, Object?> documentData({required String updatedBy}) =>
      <String, Object?>{
        'allowed': <Map<String, Object?>>[
          for (final uid in allowed.toList()..sort())
            <String, Object?>{'uid': uid},
        ],
        'updatedBy': updatedBy,
      };

  @override
  bool operator ==(Object other) =>
      other is TenantPriceAgreementPolicy &&
      other.allowed.length == allowed.length &&
      other.allowed.containsAll(allowed);

  @override
  int get hashCode => Object.hashAllUnordered(allowed);
}

/// Whether this business has a policy, and whether it could be read.
enum TenantPriceAgreementState { published, absent, malformed }

final class TenantPublishedPriceAgreement {
  const TenantPublishedPriceAgreement._(this.state, this._policy);

  const TenantPublishedPriceAgreement.published(
    TenantPriceAgreementPolicy policy,
  ) : this._(TenantPriceAgreementState.published, policy);

  const TenantPublishedPriceAgreement.absent()
    : this._(TenantPriceAgreementState.absent, null);

  const TenantPublishedPriceAgreement.malformed()
    : this._(TenantPriceAgreementState.malformed, null);

  final TenantPriceAgreementState state;
  final TenantPriceAgreementPolicy? _policy;

  /// The published policy, or the one that allows nobody.
  ///
  /// **A malformed or missing document allows nobody, never a guess.** It is
  /// the opposite way round from the stock count rota, which fails open, and
  /// for the same reason: each fails towards the till selling normally. Here
  /// that is at the listed price, and an unreadable document must not become
  /// a way to sell below it.
  TenantPriceAgreementPolicy get policy =>
      _policy ?? TenantPriceAgreementPolicy.none;

  TenantPriceAgreementPolicy? get published => _policy;
}

/// Reads one business's policy for one session.
///
/// **[cached] true answers from this device alone**, which is how the till
/// opens with no signal. False asks the server as well, which is how a policy
/// reaches a cashier's phone in the first place: nothing else on the till's
/// path reads this document, so a cache-only read would never see it change.
typedef CheckoutPriceAgreementLoader =
    Future<TenantPublishedPriceAgreement> Function(
      TenantSession session, {
      required bool cached,
    });

/// Guarded read-only repository for one business's price agreement policy.
final class TenantPriceAgreementRepository extends TenantReadRepository {
  TenantPriceAgreementRepository({
    required super.session,
    required super.reader,
  });

  static const documentId = 'price_agreement';

  /// Owner and administrator write it, which the existing
  /// `configuration/{documentId}` rule already allows. **Every active member
  /// reads it**, because the till reads it and a cashier is who it is about.
  static const List<TenantRole> writeRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
  ];

  Future<TenantPublishedPriceAgreement> load() async {
    final data = await readDocument(TenantCollection.configuration, documentId);
    if (data == null) return const TenantPublishedPriceAgreement.absent();
    try {
      return TenantPublishedPriceAgreement.published(
        TenantPriceAgreementPolicy.fromMap(data),
      );
    } on FormatException {
      return const TenantPublishedPriceAgreement.malformed();
    }
  }
}

/// Raised when a policy change is refused before anything is written.
final class TenantPriceAgreementException implements Exception {
  const TenantPriceAgreementException(this.code);

  final String code;

  @override
  String toString() => 'TenantPriceAgreementException($code)';
}

/// One policy change, ready to be written.
final class TenantPriceAgreementIntent {
  const TenantPriceAgreementIntent._({
    required this.path,
    required this.tenantId,
    required this.policy,
    required this.updatedBy,
  });

  final String path;
  final String tenantId;
  final TenantPriceAgreementPolicy policy;
  final String updatedBy;

  Map<String, Object?> documentData() =>
      policy.documentData(updatedBy: updatedBy);
}

final class TenantPriceAgreementPublisher extends TenantReadRepository {
  TenantPriceAgreementPublisher({
    required super.session,
    required super.reader,
  });

  static const List<TenantRole> allowedRoles =
      TenantPriceAgreementRepository.writeRoles;

  /// Builds the one instruction these people describe.
  ///
  /// **Every refusal happens here**, before anything is sent, exactly as the
  /// stock count publisher does.
  TenantPriceAgreementIntent buildIntent({
    required Set<String> allowed,
    required TenantPublishedPriceAgreement published,
  }) {
    if (!session.canAccess(allowedRoles: allowedRoles)) {
      throw const TenantPriceAgreementException('price_agreement_forbidden');
    }
    final TenantPriceAgreementPolicy policy;
    try {
      policy = TenantPriceAgreementPolicy(allowed: allowed);
    } on FormatException {
      throw const TenantPriceAgreementException('invalid_policy');
    }
    // Re-saving the identical document is refused for the reason the stock
    // count publisher gives: it rewrites the provenance and asks every device
    // to re-read a setting that cannot have changed.
    if (published.published == policy) {
      throw const TenantPriceAgreementException('policy_unchanged');
    }
    return TenantPriceAgreementIntent._(
      path: paths.configurationDocument(
        TenantPriceAgreementRepository.documentId,
      ),
      tenantId: session.tenantId,
      policy: policy,
      updatedBy: session.uid,
    );
  }
}
