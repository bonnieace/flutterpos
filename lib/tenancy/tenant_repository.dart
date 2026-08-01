import 'package:cloud_firestore/cloud_firestore.dart';

import 'tenant_id.dart';
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

/// One document returned by a tenant-derived collection query.
final class TenantQueryDocumentSnapshot {
  TenantQueryDocumentSnapshot({
    required this.path,
    required Map<String, Object?> data,
  }) : data = Map<String, Object?>.unmodifiable(data);

  final String path;
  final Map<String, Object?> data;
}

/// A query that can only be constructed by [TenantReadRepository].
///
/// [equalityFilters] carries the exact `field == value` conditions the
/// repository chose. Callers cannot supply them, and the reader may not add,
/// drop, or reinterpret one. [descending] reverses the document-ID ordering
/// only; the reader may not order by any other field.
final class TenantCollectionQuery {
  TenantCollectionQuery._({
    required this.collectionPath,
    required this.limit,
    this.startAfterDocumentId,
    this.descending = false,
    Map<String, Object?> equalityFilters = const <String, Object?>{},
  }) : equalityFilters = Map<String, Object?>.unmodifiable(equalityFilters);

  /// Lets a test transport describe a query a repository did not build.
  ///
  /// This constructs no path of its own for production code: every real query
  /// still comes from [TenantReadRepository], which owns the collection path
  /// and validates every returned document against it.
  factory TenantCollectionQuery.forTesting({
    required String collectionPath,
    required int limit,
    String? startAfterDocumentId,
    bool descending = false,
    Map<String, Object?> equalityFilters = const <String, Object?>{},
  }) => TenantCollectionQuery._(
    collectionPath: collectionPath,
    limit: limit,
    startAfterDocumentId: startAfterDocumentId,
    descending: descending,
    equalityFilters: equalityFilters,
  );

  final String collectionPath;
  final int limit;
  final String? startAfterDocumentId;

  /// Whether the page is ordered by descending document ID.
  final bool descending;
  final Map<String, Object?> equalityFilters;
}

/// The narrow collection-read boundary used by tenant repositories.
abstract interface class TenantCollectionReader {
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  );
}

/// Reader required by screens that use both document and collection slices.
abstract interface class TenantDataReader
    implements TenantDocumentReader, TenantCollectionReader {}

/// Firebase implementation of the tenant document and collection boundaries.
final class FirebaseTenantDocumentReader implements TenantDataReader {
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

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    Query<Map<String, dynamic>> request = _firestore.collection(
      query.collectionPath,
    );
    for (final filter in query.equalityFilters.entries) {
      request = request.where(filter.key, isEqualTo: filter.value);
    }
    request = request
        .orderBy(FieldPath.documentId, descending: query.descending)
        .limit(query.limit);
    final cursor = query.startAfterDocumentId;
    if (cursor != null) request = request.startAfter(<Object>[cursor]);
    final snapshot = await request.get();
    return snapshot.docs
        .map(
          (document) => TenantQueryDocumentSnapshot(
            path: document.reference.path,
            data: document.data(),
          ),
        )
        .toList(growable: false);
  }
}

/// Raised when a reader returns a document outside the requested tenant scope.
final class TenantScopeViolation implements Exception {
  const TenantScopeViolation(this.message);

  final String message;

  @override
  String toString() => 'TenantScopeViolation: $message';
}

/// A bounded page ordered by Firestore document ID.
final class TenantDocumentPage {
  TenantDocumentPage({
    required List<TenantQueryDocumentSnapshot> items,
    required this.nextCursor,
    required this.hasMore,
    this.descending = false,
  }) : items = List<TenantQueryDocumentSnapshot>.unmodifiable(items);

  final List<TenantQueryDocumentSnapshot> items;
  final String? nextCursor;
  final bool hasMore;

  /// Whether this page was ordered by descending document ID.
  final bool descending;
}

/// Base for read-only repositories bound to one live tenant session.
///
/// Callers select a known [TenantCollection] and document ID. They cannot pass
/// a root collection or an arbitrary Firestore path.
abstract base class TenantReadRepository {
  TenantReadRepository({required this.session, required this.reader})
    : paths = TenantPaths(session.tenantId) {
    if (!session.canAccess()) {
      throw StateError('A tenant repository requires an active session.');
    }
  }

  final TenantSession session;
  final TenantDocumentReader reader;
  final TenantPaths paths;

  /// Reads the canonical tenant root derived from this repository's session.
  Future<Map<String, Object?>?> readTenantRoot() async {
    final expectedPath = paths.root;
    final snapshot = await reader.getDocument(expectedPath);
    if (snapshot == null) return null;
    if (snapshot.path != expectedPath) {
      throw TenantScopeViolation(
        'Expected $expectedPath but received ${snapshot.path}.',
      );
    }
    return snapshot.data;
  }

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

  /// Reads one deterministic, bounded page from a known tenant collection.
  ///
  /// One extra document is requested so [TenantDocumentPage.hasMore] is exact.
  /// Neither callers nor repository subclasses can supply a collection path.
  /// [equalityFilters] narrows the page to exact field values; every returned
  /// document is still proved to be a direct child of this tenant collection.
  /// [descending] reverses the document-ID ordering so a history surface can
  /// page from the newest record; the ordering proof reverses with it, and no
  /// other sort field is reachable from here.
  Future<TenantDocumentPage> readCollectionPage(
    TenantCollection collection, {
    required TenantCollectionReader collectionReader,
    int pageSize = 20,
    String? cursor,
    bool descending = false,
    Map<String, Object?> equalityFilters = const <String, Object?>{},
  }) => _readPage(
    paths.collectionPath(collection),
    collectionReader: collectionReader,
    pageSize: pageSize,
    cursor: cursor,
    descending: descending,
    equalityFilters: equalityFilters,
  );

  /// Reads one bounded page from an allowed subcollection of one product.
  ///
  /// The product ID and the subcollection are both derived from this session's
  /// [TenantPaths], so a caller still cannot supply a collection path, and every
  /// returned document is proved to be an exact child of that subcollection.
  /// The same page-size bound, uniqueness, and ordering proofs apply.
  ///
  /// It is deliberately `async` so a product ID that is not a document ID is
  /// reported the same way every other refusal here is - as a failed future,
  /// never as a synchronous throw an awaiting caller would have to guard
  /// separately.
  Future<TenantDocumentPage> readProductSubcollectionPage(
    TenantProductSubcollection subcollection, {
    required String productId,
    required TenantCollectionReader collectionReader,
    int pageSize = 20,
    String? cursor,
    bool descending = false,
    Map<String, Object?> equalityFilters = const <String, Object?>{},
  }) async => _readPage(
    paths.productSubcollectionPath(productId, subcollection),
    collectionReader: collectionReader,
    pageSize: pageSize,
    cursor: cursor,
    descending: descending,
    equalityFilters: equalityFilters,
  );

  Future<TenantDocumentPage> _readPage(
    String expectedCollectionPath, {
    required TenantCollectionReader collectionReader,
    required int pageSize,
    required String? cursor,
    required bool descending,
    required Map<String, Object?> equalityFilters,
  }) async {
    if (pageSize < 1 || pageSize > 50) {
      throw RangeError.range(pageSize, 1, 50, 'pageSize');
    }
    final safeFilters = _validatedEqualityFilters(equalityFilters);
    // Firestore refuses a descending scan of a whole collection by key
    // ("Firestore does not support descending key scans"), so a newest-first
    // page must always be narrowed by at least one equality filter. Refusing it
    // here turns a runtime query failure into an immediate programming error.
    if (descending && safeFilters.isEmpty) {
      throw ArgumentError.value(
        descending,
        'descending',
        'A descending page requires at least one equality filter.',
      );
    }
    final validatedCursor = cursor == null
        ? null
        : validateTenantDocumentId(cursor, fieldName: 'cursor');
    final requestedLimit = pageSize + 1;
    final snapshots = await collectionReader.getCollectionPage(
      TenantCollectionQuery._(
        collectionPath: expectedCollectionPath,
        limit: requestedLimit,
        startAfterDocumentId: validatedCursor,
        descending: descending,
        equalityFilters: safeFilters,
      ),
    );
    if (snapshots.length > requestedLimit) {
      throw const TenantScopeViolation(
        'A collection reader returned more documents than requested.',
      );
    }

    final seenIds = <String>{};
    String? previousId;
    for (final snapshot in snapshots) {
      final prefix = '$expectedCollectionPath/';
      if (!snapshot.path.startsWith(prefix)) {
        throw TenantScopeViolation(
          'Expected a document below $expectedCollectionPath but received '
          '${snapshot.path}.',
        );
      }
      final documentId = snapshot.path.substring(prefix.length);
      try {
        validateTenantDocumentId(documentId);
      } on ArgumentError {
        throw TenantScopeViolation(
          'The returned document path is not an exact collection child: '
          '${snapshot.path}.',
        );
      }
      if (!seenIds.add(documentId)) {
        throw TenantScopeViolation(
          'The collection reader returned duplicate document $documentId.',
        );
      }
      final ordered = previousId == null ||
          (descending
              ? previousId.compareTo(documentId) > 0
              : previousId.compareTo(documentId) < 0);
      if (!ordered) {
        throw const TenantScopeViolation(
          'Collection results were not ordered by document ID.',
        );
      }
      previousId = documentId;
    }

    final hasMore = snapshots.length > pageSize;
    final items = hasMore ? snapshots.take(pageSize).toList() : snapshots;
    final nextCursor = hasMore
        ? items.last.path.substring('$expectedCollectionPath/'.length)
        : null;
    return TenantDocumentPage(
      items: items,
      nextCursor: nextCursor,
      hasMore: hasMore,
      descending: descending,
    );
  }

  /// Accepts only simple, bounded `field == value` conditions.
  ///
  /// A field path with a dot or a slash could reach outside the intended
  /// document shape, and an unbounded value type could not be reasoned about,
  /// so both are refused before any query is issued.
  static Map<String, Object?> _validatedEqualityFilters(
    Map<String, Object?> filters,
  ) {
    if (filters.length > _maximumEqualityFilters) {
      throw ArgumentError.value(
        filters.length,
        'equalityFilters',
        'At most $_maximumEqualityFilters equality filters are supported.',
      );
    }
    for (final entry in filters.entries) {
      if (!_queryFieldPattern.hasMatch(entry.key)) {
        throw ArgumentError.value(
          entry.key,
          'equalityFilters',
          'Not a simple tenant document field name.',
        );
      }
      final value = entry.value;
      final isBounded =
          (value is String && value.isNotEmpty && value.length <= 256) ||
          value is int ||
          value is bool;
      if (!isBounded) {
        throw ArgumentError.value(
          value,
          'equalityFilters',
          'Only bounded string, integer, and boolean values are supported.',
        );
      }
    }
    return Map<String, Object?>.unmodifiable(filters);
  }
}

const int _maximumEqualityFilters = 4;
final RegExp _queryFieldPattern = RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,63}$');
