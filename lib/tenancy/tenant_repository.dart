import 'package:cloud_firestore/cloud_firestore.dart';

import 'tenant_paths.dart';
import 'tenant_session.dart';

/// A Firestore document returned to a tenant-scoped repository.
final class TenantDocumentSnapshot {
  TenantDocumentSnapshot({
    required this.path,
    required Map<String, Object?> data,
  }) : data = Map<String, Object?>.unmodifiable(data);

  final String path;
  final Map<String, Object?> data;
}

/// The narrow document-read boundary used by tenant repositories.
abstract interface class TenantDocumentReader {
  Future<TenantDocumentSnapshot?> getDocument(String path);
}

/// Firebase implementation of [TenantDocumentReader].
final class FirebaseTenantDocumentReader implements TenantDocumentReader {
  FirebaseTenantDocumentReader([FirebaseFirestore? firestore])
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    final snapshot = await _firestore.doc(path).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    return TenantDocumentSnapshot(path: snapshot.reference.path, data: data);
  }
}

/// Raised when a reader returns a document outside the requested tenant scope.
final class TenantScopeViolation implements Exception {
  const TenantScopeViolation(this.message);

  final String message;

  @override
  String toString() => 'TenantScopeViolation: $message';
}

/// Base for read-only repositories bound to one live tenant session.
///
/// Callers select a known [TenantCollection] and document ID. They cannot pass
/// a root collection or an arbitrary Firestore path.
abstract base class TenantReadRepository {
  TenantReadRepository({
    required this.session,
    required this.reader,
  }) : paths = TenantPaths(session.tenantId) {
    if (!session.canAccess()) {
      throw StateError('A tenant repository requires an active session.');
    }
  }

  final TenantSession session;
  final TenantDocumentReader reader;
  final TenantPaths paths;

  Future<Map<String, Object?>?> readDocument(
    TenantCollection collection,
    String documentId,
  ) async {
    final expectedPath = paths.documentPath(collection, documentId);
    final snapshot = await reader.getDocument(expectedPath);
    if (snapshot == null) return null;
    if (snapshot.path != expectedPath || !paths.owns(snapshot.path)) {
      throw TenantScopeViolation(
        'Expected $expectedPath but received ${snapshot.path}.',
      );
    }
    return snapshot.data;
  }
}
