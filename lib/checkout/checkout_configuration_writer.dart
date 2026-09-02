/// One merge writer for any `tenants/{tenantId}/configuration/*` document.
///
/// **Written generic rather than copied, and the copy it was nearly a copy of
/// is named here.** `FirebaseTenantCheckoutConfigurationWriter` in
/// `checkout_configuration.dart` does exactly this for `configuration/checkout`
/// — the same merge, the same four outcomes, the same seven rejected codes, the
/// same online check and the same timeout. Writing a second one for
/// `configuration/printer` would have been sixty lines of Firestore boilerplate
/// duplicated for a different path.
///
/// **The checkout writer is deliberately not refactored onto this**, and that is
/// a scope decision rather than an oversight: it is shipped, tested, and its
/// intent type is the public shape its own screen is built around. Folding it in
/// is a small, safe, separate chunk — see `PLAN.md`. What matters is that the
/// *second* configuration document did not double the code.
///
/// **The merge is the load-bearing part.** `configuration/{documentId}` is a
/// shared home: a strict read model ignores fields it does not know, so a
/// whole-document `set` from this build would silently delete a setting a later
/// build added. This writes exactly the keys the intent names, and `updatedAt`
/// is always a server timestamp so a device clock cannot decide when a business
/// changed something.
///
/// **There is no request ID and no deterministic document ID**, unlike every
/// other write in this app. Each of these names one fixed path and one fixed set
/// of values, so a retry after an unknown outcome converges on the same document
/// instead of writing a second one.
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

/// The outcome of one attempted configuration write.
///
/// The same four this app's every write boundary answers in, so a surface maps
/// them to `AppNotice` once rather than inventing a fifth.
enum TenantConfigurationWriteKind {
  /// Saved durably on this device and waiting for synchronization.
  queued,

  /// The server acknowledged the write.
  committed,

  /// The server refused it; nothing was written.
  rejected,

  /// The outcome is unknown; only a canonical re-read decides what is stored.
  ambiguous,

  /// No attempt was made, because the device was offline.
  unavailable,
}

final class TenantConfigurationWriteResult {
  const TenantConfigurationWriteResult._(this.kind, [this.reasonCode]);

  const TenantConfigurationWriteResult.committed()
    : this._(TenantConfigurationWriteKind.committed);

  const TenantConfigurationWriteResult.queued()
    : this._(TenantConfigurationWriteKind.queued);

  const TenantConfigurationWriteResult.rejected(String reasonCode)
    : this._(TenantConfigurationWriteKind.rejected, reasonCode);

  const TenantConfigurationWriteResult.ambiguous(String reasonCode)
    : this._(TenantConfigurationWriteKind.ambiguous, reasonCode);

  const TenantConfigurationWriteResult.unavailable()
    : this._(TenantConfigurationWriteKind.unavailable);

  final TenantConfigurationWriteKind kind;
  final String? reasonCode;
}

/// The narrow write boundary a configuration surface depends on.
abstract interface class TenantConfigurationDocumentWriter {
  /// Merges [data] into the document at [path].
  ///
  /// [path] comes from a validated intent, never from a widget: a writer that
  /// accepted a typed path would be a writer that could be pointed at another
  /// tenant.
  Future<TenantConfigurationWriteResult> merge({
    required String path,
    required Map<String, Object?> data,
  });
}

typedef TenantConfigurationOnlineCheck = Future<bool> Function();
typedef TenantConfigurationDocumentMerger =
    Future<void> Function(String path, Map<String, Object?> data);

final class FirebaseTenantConfigurationDocumentWriter
    implements TenantConfigurationDocumentWriter {
  FirebaseTenantConfigurationDocumentWriter({
    FirebaseFirestore? firestore,
    required TenantConfigurationOnlineCheck isOnline,
    Duration writeTimeout = const Duration(seconds: 20),
  }) : this._(
         merge: _firestoreMerger(firestore ?? FirebaseFirestore.instance),
         isOnline: isOnline,
         writeTimeout: writeTimeout,
       );

  FirebaseTenantConfigurationDocumentWriter.forTesting({
    required TenantConfigurationDocumentMerger merge,
    required TenantConfigurationOnlineCheck isOnline,
    Duration writeTimeout = const Duration(seconds: 20),
  }) : this._(merge: merge, isOnline: isOnline, writeTimeout: writeTimeout);

  FirebaseTenantConfigurationDocumentWriter._({
    required TenantConfigurationDocumentMerger merge,
    required TenantConfigurationOnlineCheck isOnline,
    required Duration writeTimeout,
  }) : _merge = merge,
       _isOnline = isOnline,
       _writeTimeout = writeTimeout {
    if (writeTimeout <= Duration.zero) {
      throw ArgumentError.value(writeTimeout, 'writeTimeout');
    }
  }

  /// The Firestore codes that mean the server **decided**, as opposed to the
  /// ones that mean nobody knows. Copied from the checkout writer because the
  /// distinction is Firestore's rather than this app's.
  static const Set<String> _rejectedCodes = <String>{
    'permission-denied',
    'unauthenticated',
    'invalid-argument',
    'not-found',
    'already-exists',
    'failed-precondition',
    'out-of-range',
  };

  final TenantConfigurationDocumentMerger _merge;
  final TenantConfigurationOnlineCheck _isOnline;
  final Duration _writeTimeout;

  @override
  Future<TenantConfigurationWriteResult> merge({
    required String path,
    required Map<String, Object?> data,
  }) async {
    if (!await _online()) {
      return const TenantConfigurationWriteResult.unavailable();
    }
    try {
      await _merge(path, <String, Object?>{
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      }).timeout(_writeTimeout);
      return const TenantConfigurationWriteResult.committed();
    } on TimeoutException {
      // **Ambiguous, not rejected.** A timed-out write may still land; only a
      // canonical re-read says what is stored.
      return const TenantConfigurationWriteResult.ambiguous('write_timeout');
    } on FirebaseException catch (error) {
      return _rejectedCodes.contains(error.code)
          ? TenantConfigurationWriteResult.rejected(error.code)
          : TenantConfigurationWriteResult.ambiguous(error.code);
    } catch (_) {
      return const TenantConfigurationWriteResult.ambiguous('unknown_error');
    }
  }

  Future<bool> _online() async {
    try {
      return await _isOnline();
    } catch (_) {
      // A connectivity check that itself failed is not evidence of being
      // online, and guessing yes would send a write into the dark.
      return false;
    }
  }

  static TenantConfigurationDocumentMerger _firestoreMerger(
    FirebaseFirestore firestore,
  ) =>
      (path, data) => firestore.doc(path).set(data, SetOptions(merge: true));
}
