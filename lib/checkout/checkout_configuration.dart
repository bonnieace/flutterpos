import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../tenancy/tenant_paths.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_types.dart';

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

/// Raised when a configuration change is refused before anything is written.
final class TenantCheckoutConfigurationException implements Exception {
  const TenantCheckoutConfigurationException(this.code);

  final String code;

  @override
  String toString() => 'TenantCheckoutConfigurationException($code)';
}

/// What one business has published, as the surface that may replace it sees it.
///
/// [malformed] is deliberately a state rather than a failure. The strict read
/// model refuses a document whose `currency` is not an ISO 4217 code, and the
/// till therefore refuses to sell at all - so the one person who can correct it
/// must be able to see it and overwrite it, not be shown the same refusal the
/// cashier is.
enum TenantPublishedConfigurationState { published, absent, malformed }

final class TenantPublishedCheckoutConfiguration {
  const TenantPublishedCheckoutConfiguration._(this.state, this.configuration);

  const TenantPublishedCheckoutConfiguration.published(
    TenantCheckoutConfiguration configuration,
  ) : this._(TenantPublishedConfigurationState.published, configuration);

  const TenantPublishedCheckoutConfiguration.absent()
    : this._(TenantPublishedConfigurationState.absent, null);

  const TenantPublishedCheckoutConfiguration.malformed()
    : this._(TenantPublishedConfigurationState.malformed, null);

  final TenantPublishedConfigurationState state;

  /// Present only when the stored document parsed through the strict read model.
  final TenantCheckoutConfiguration? configuration;

  /// The published ISO 4217 code, or `null` when there is no usable one.
  String? get currency => configuration?.currency;

  /// Whether a till in this business can price a draft at all today.
  bool get canSell => state == TenantPublishedConfigurationState.published;
}

/// A validated instruction to publish exactly one tenant's checkout settings.
///
/// Only [TenantCheckoutConfigurationPublisher] can build one, so no caller can
/// name an arbitrary Firestore path or an unvalidated currency. The server-owned
/// `updatedAt` is deliberately not part of the data: the writer adds it, so a
/// device clock cannot decide when the business changed what it trades in.
final class TenantCheckoutConfigurationUpdateIntent {
  const TenantCheckoutConfigurationUpdateIntent._({
    required this.path,
    required this.tenantId,
    required this.currency,
    required this.updatedBy,
    required this.replaces,
  });

  final String path;
  final String tenantId;

  /// The ISO 4217 code every sale priced after this change will record.
  final String currency;

  final String updatedBy;

  /// The state this change replaces, read immediately before it was built.
  final TenantPublishedCheckoutConfiguration replaces;

  /// Whether a usable code is being replaced by a different usable code.
  ///
  /// This is the only case a confirmation has anything to warn about: sales
  /// already recorded keep the code they were priced with, and a device that has
  /// not synced keeps pricing new sales with the previous one.
  bool get changesPublishedCurrency =>
      replaces.canSell && replaces.currency != currency;

  /// Exactly the keys this client writes, and nothing else.
  ///
  /// `updatedBy` is provenance: nothing in the app or on the server reads it,
  /// and the strict read model ignores it, but it is the only record of who last
  /// decided what this business trades in.
  Map<String, Object?> documentData() => <String, Object?>{
    'currency': currency,
    'updatedBy': updatedBy,
  };
}

/// Guarded intent boundary for publishing one tenant's checkout configuration.
///
/// This is deliberately a second class rather than a method on
/// [TenantCheckoutConfigurationRepository]: every active member reads the
/// configuration - a till cannot price a sale without it - and only an owner or
/// administrator may change it, so the two capabilities do not share a boundary.
final class TenantCheckoutConfigurationPublisher extends TenantReadRepository {
  TenantCheckoutConfigurationPublisher({
    required super.session,
    required super.reader,
  });

  /// Owner and administrator only, which is exactly what the Firestore rule for
  /// `configuration/{documentId}` allows. A manager runs a till and corrects
  /// stock; deciding what the business trades in is not an operational act.
  static const List<TenantRole> allowedRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
  ];

  /// Reads what this business has published, degrading a malformed document
  /// into a state rather than a failure.
  ///
  /// A [TenantScopeViolation] is the one exception and is rethrown: a reader
  /// answering outside this tenant is a broken boundary, not a missing setting,
  /// and it must never be reported as "nothing is published".
  Future<TenantPublishedCheckoutConfiguration> loadPublished() async {
    // A scope violation from here is deliberately not caught: only the parse is.
    final data = await readDocument(
      TenantCollection.configuration,
      TenantCheckoutConfigurationRepository.documentId,
    );
    if (data == null) {
      return const TenantPublishedCheckoutConfiguration.absent();
    }
    try {
      return TenantPublishedCheckoutConfiguration.published(
        TenantCheckoutConfiguration.fromMap(data),
      );
    } on FormatException {
      return const TenantPublishedCheckoutConfiguration.malformed();
    }
  }

  /// Builds the one publish instruction [currency] describes.
  ///
  /// [currency] is accepted as typed and normalized here rather than in the
  /// widget: an ISO 4217 code has exactly one casing, so `kes` is a spelling of
  /// `KES` and not a different setting.
  TenantCheckoutConfigurationUpdateIntent buildUpdateIntent({
    required String currency,
    required TenantPublishedCheckoutConfiguration published,
  }) {
    if (!session.canAccess(allowedRoles: allowedRoles)) {
      throw const TenantCheckoutConfigurationException(
        'configuration_forbidden',
      );
    }
    final normalized = currency.trim().toUpperCase();
    if (!_currencyPattern.hasMatch(normalized)) {
      throw const TenantCheckoutConfigurationException('invalid_currency');
    }
    // Republishing the identical code would rewrite the provenance fields and
    // ask every device to re-read a catalog that cannot have changed, so it is
    // refused. A malformed or absent document is never "unchanged": that is
    // exactly the state this surface exists to leave.
    if (published.canSell && published.currency == normalized) {
      throw const TenantCheckoutConfigurationException('currency_unchanged');
    }
    return TenantCheckoutConfigurationUpdateIntent._(
      path: paths.configurationDocument(
        TenantCheckoutConfigurationRepository.documentId,
      ),
      tenantId: session.tenantId,
      currency: normalized,
      updatedBy: session.uid,
      replaces: published,
    );
  }
}

/// The outcome of one attempted configuration write.
enum TenantCheckoutConfigurationWriteKind {
  /// The server acknowledged the write.
  committed,

  /// The server refused the write; nothing was published.
  rejected,

  /// The outcome is unknown; only a canonical re-read decides what is published.
  ambiguous,

  /// No attempt was made because the device was offline.
  unavailable,
}

final class TenantCheckoutConfigurationWriteResult {
  const TenantCheckoutConfigurationWriteResult._(this.kind, [this.reasonCode]);

  const TenantCheckoutConfigurationWriteResult.committed()
    : this._(TenantCheckoutConfigurationWriteKind.committed);

  const TenantCheckoutConfigurationWriteResult.rejected(String reasonCode)
    : this._(TenantCheckoutConfigurationWriteKind.rejected, reasonCode);

  const TenantCheckoutConfigurationWriteResult.ambiguous(String reasonCode)
    : this._(TenantCheckoutConfigurationWriteKind.ambiguous, reasonCode);

  const TenantCheckoutConfigurationWriteResult.unavailable()
    : this._(TenantCheckoutConfigurationWriteKind.unavailable);

  final TenantCheckoutConfigurationWriteKind kind;
  final String? reasonCode;
}

/// The narrow write boundary used to publish checkout configuration.
abstract interface class TenantCheckoutConfigurationWriter {
  Future<TenantCheckoutConfigurationWriteResult> publish(
    TenantCheckoutConfigurationUpdateIntent intent,
  );
}

typedef TenantCheckoutConfigurationOnlineCheck = Future<bool> Function();
typedef TenantCheckoutConfigurationDocumentMerger =
    Future<void> Function(String path, Map<String, Object?> data);

/// Firestore implementation of the configuration write boundary.
///
/// The write **merges**. `configuration/checkout` is the shared home of every
/// later checkout setting and the strict read model deliberately ignores fields
/// it does not know, so a whole-document `set` from this build would silently
/// delete a setting a later one added. Merging writes exactly the keys the
/// intent names. `updatedAt` is always a server timestamp.
///
/// There is no request ID and no deterministic document ID to derive, unlike
/// every other write in this app: this one names one fixed path and one fixed
/// value, so a retry after an unknown outcome converges on the same document
/// instead of publishing a second time.
final class FirebaseTenantCheckoutConfigurationWriter
    implements TenantCheckoutConfigurationWriter {
  FirebaseTenantCheckoutConfigurationWriter({
    FirebaseFirestore? firestore,
    required TenantCheckoutConfigurationOnlineCheck isOnline,
    Duration writeTimeout = const Duration(seconds: 20),
  }) : this._(
         merge: _firestoreMerger(firestore ?? FirebaseFirestore.instance),
         isOnline: isOnline,
         writeTimeout: writeTimeout,
       );

  FirebaseTenantCheckoutConfigurationWriter.forTesting({
    required TenantCheckoutConfigurationDocumentMerger merge,
    required TenantCheckoutConfigurationOnlineCheck isOnline,
    Duration writeTimeout = const Duration(seconds: 20),
  }) : this._(merge: merge, isOnline: isOnline, writeTimeout: writeTimeout);

  FirebaseTenantCheckoutConfigurationWriter._({
    required TenantCheckoutConfigurationDocumentMerger merge,
    required TenantCheckoutConfigurationOnlineCheck isOnline,
    required Duration writeTimeout,
  }) : _merge = merge,
       _isOnline = isOnline,
       _writeTimeout = writeTimeout {
    if (writeTimeout <= Duration.zero) {
      throw ArgumentError.value(writeTimeout, 'writeTimeout');
    }
  }

  static const Set<String> _rejectedCodes = <String>{
    'permission-denied',
    'unauthenticated',
    'invalid-argument',
    'not-found',
    'already-exists',
    'failed-precondition',
    'out-of-range',
  };

  final TenantCheckoutConfigurationDocumentMerger _merge;
  final TenantCheckoutConfigurationOnlineCheck _isOnline;
  final Duration _writeTimeout;

  @override
  Future<TenantCheckoutConfigurationWriteResult> publish(
    TenantCheckoutConfigurationUpdateIntent intent,
  ) async {
    if (TenantPaths(intent.tenantId).configurationDocument(
          TenantCheckoutConfigurationRepository.documentId,
        ) !=
        intent.path) {
      throw const TenantCheckoutConfigurationException(
        'configuration_path_escaped_tenant',
      );
    }
    if (!await _online()) {
      return const TenantCheckoutConfigurationWriteResult.unavailable();
    }
    try {
      await _merge(intent.path, <String, Object?>{
        ...intent.documentData(),
        'updatedAt': FieldValue.serverTimestamp(),
      }).timeout(_writeTimeout);
      return const TenantCheckoutConfigurationWriteResult.committed();
    } on TimeoutException {
      return const TenantCheckoutConfigurationWriteResult.ambiguous(
        'write_timeout',
      );
    } on FirebaseException catch (error) {
      return _rejectedCodes.contains(error.code)
          ? TenantCheckoutConfigurationWriteResult.rejected(error.code)
          : TenantCheckoutConfigurationWriteResult.ambiguous(error.code);
    } catch (_) {
      return const TenantCheckoutConfigurationWriteResult.ambiguous(
        'unknown_error',
      );
    }
  }

  Future<bool> _online() async {
    try {
      return await _isOnline();
    } catch (_) {
      return false;
    }
  }

  static TenantCheckoutConfigurationDocumentMerger _firestoreMerger(
    FirebaseFirestore firestore,
  ) =>
      (path, data) => firestore.doc(path).set(data, SetOptions(merge: true));
}

String _validatedCurrency(String currency) {
  if (!_currencyPattern.hasMatch(currency)) {
    throw const FormatException(
      'currency must be a three-letter ISO 4217 code.',
    );
  }
  return currency;
}
