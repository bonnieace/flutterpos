/// Who may sell for a price agreed with the customer, rather than the listed one.
///
/// **Everyone, unless switched off - since 2026-10-02.** The developer ruled on
/// 2026-09-29 that only people named here could agree a price, and turned it
/// round on 2026-10-02: agreeing a price is on for everybody by default, and
/// this setting is the list of people it is switched off for. A business that
/// has never opened the setting lets every till agree a price.
///
/// **A list saved under the first rule keeps meaning what it meant.** A
/// document naming only `allowed` people was written by an owner who chose
/// those people, so it is read as that choice - only them - until this screen
/// saves it again in the new shape. The new shape also writes `allowed`, the
/// people it leaves on, so a build from before the change reads every person's
/// answer the same way this one does.
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
  /// Only [allowed] may agree a price: the shape saved before 2026-10-02.
  TenantPriceAgreementPolicy({required Set<String> allowed})
    : this._(
        everyone: false,
        allowed: allowed,
        blocked: const <String>{},
      );

  /// Everyone may agree a price except [blocked].
  TenantPriceAgreementPolicy.everyoneExcept(Set<String> blocked)
    : this._(everyone: true, allowed: const <String>{}, blocked: blocked);

  TenantPriceAgreementPolicy._({
    required this.everyone,
    required Set<String> allowed,
    required Set<String> blocked,
  }) : allowed = Set<String>.unmodifiable(allowed),
       blocked = Set<String>.unmodifiable(blocked) {
    for (final people in <Set<String>>[allowed, blocked]) {
      if (people.length > maximumPriceAgreementPeople) {
        throw const FormatException('too many people are named.');
      }
      for (final uid in people) {
        if (uid.isEmpty) {
          throw const FormatException('a named person must be a member.');
        }
      }
    }
  }

  /// What an unreadable document behaves like: nobody, so a corrupt setting
  /// can never become a way to sell below the listed price.
  static final TenantPriceAgreementPolicy none = TenantPriceAgreementPolicy(
    allowed: const <String>{},
  );

  /// What a business that has configured nothing behaves like: everyone.
  static final TenantPriceAgreementPolicy everybody =
      TenantPriceAgreementPolicy.everyoneExcept(const <String>{});

  /// Unknown fields are ignored and known ones must be exactly valid, which is
  /// the asymmetry every configuration document here uses.
  ///
  /// **A person is an object, not a bare ID**, so a later limit per person - a
  /// largest discount, say - is a field beside `uid` rather than a new shape.
  factory TenantPriceAgreementPolicy.fromMap(Map<String, Object?> map) {
    if (map['everyone'] == true) {
      return TenantPriceAgreementPolicy.everyoneExcept(
        _people(map['blocked'], 'blocked'),
      );
    }
    return TenantPriceAgreementPolicy(
      allowed: _people(map['allowed'], 'allowed'),
    );
  }

  static Set<String> _people(Object? value, String field) {
    if (value is! List) throw FormatException('$field must be a list.');
    return <String>{
      for (final entry in value)
        if (entry is Map)
          _uid(entry)
        else
          throw FormatException('a $field person must be an object.'),
    };
  }

  static String _uid(Map<Object?, Object?> entry) {
    final uid = entry['uid'];
    if (uid is! String || uid.isEmpty) {
      throw const FormatException('an allowed person must name a member.');
    }
    return uid;
  }

  /// Whether everyone is allowed but [blocked], rather than only [allowed].
  final bool everyone;

  /// Under the earlier shape, the only people who may.
  final Set<String> allowed;

  /// Under the current shape, the people it is switched off for.
  final Set<String> blocked;

  /// Whether [uid] may agree a price at the till.
  bool allows(String uid) =>
      everyone ? !blocked.contains(uid) : allowed.contains(uid);

  /// The document this policy is saved as.
  ///
  /// [members] are the people the screen showed. The current shape also
  /// writes the ones it leaves on as `allowed`, which is the only field a
  /// build from before 2026-10-02 reads - so a tester on an older build is
  /// told the same answer for each of them.
  Map<String, Object?> documentData({
    required String updatedBy,
    Iterable<String> members = const <String>[],
  }) => <String, Object?>{
    if (everyone) ...<String, Object?>{
      'everyone': true,
      'blocked': _objects(blocked),
      'allowed': _objects(<String>{
        for (final uid in members)
          if (!blocked.contains(uid)) uid,
      }),
    } else
      'allowed': _objects(allowed),
    'updatedBy': updatedBy,
  };

  static List<Map<String, Object?>> _objects(Set<String> uids) =>
      <Map<String, Object?>>[
        for (final uid in uids.toList()..sort()) <String, Object?>{'uid': uid},
      ];

  @override
  bool operator ==(Object other) =>
      other is TenantPriceAgreementPolicy &&
      other.everyone == everyone &&
      other.allowed.length == allowed.length &&
      other.allowed.containsAll(allowed) &&
      other.blocked.length == blocked.length &&
      other.blocked.containsAll(blocked);

  @override
  int get hashCode => Object.hash(
    everyone,
    Object.hashAllUnordered(allowed),
    Object.hashAllUnordered(blocked),
  );
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

  /// The published policy, or what its absence means.
  ///
  /// **A missing document allows everyone**, which is the default since
  /// 2026-10-02. **A malformed one allows nobody, never a guess**: an
  /// unreadable document must not become a way to sell below the listed
  /// price.
  TenantPriceAgreementPolicy get policy =>
      _policy ??
      (state == TenantPriceAgreementState.absent
          ? TenantPriceAgreementPolicy.everybody
          : TenantPriceAgreementPolicy.none);

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
    this.members = const <String>{},
  });

  final String path;
  final String tenantId;
  final TenantPriceAgreementPolicy policy;
  final String updatedBy;

  /// The people the screen showed, so older builds are told the same answers.
  final Set<String> members;

  Map<String, Object?> documentData() =>
      policy.documentData(updatedBy: updatedBy, members: members);
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
    required Set<String> blocked,
    required TenantPublishedPriceAgreement published,
    Set<String> members = const <String>{},
  }) {
    if (!session.canAccess(allowedRoles: allowedRoles)) {
      throw const TenantPriceAgreementException('price_agreement_forbidden');
    }
    final TenantPriceAgreementPolicy policy;
    try {
      policy = TenantPriceAgreementPolicy.everyoneExcept(blocked);
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
      members: Set<String>.unmodifiable(members),
    );
  }
}
