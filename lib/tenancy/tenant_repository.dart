import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

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

/// A reader that can also answer out of a copy this device already holds.
///
/// **Separate from [TenantDataReader] on purpose.** Being able to read is a
/// property every reader has; having a local copy is a property of the one
/// backed by Firestore's own persistence, and of any test double that wants to
/// stand in for it. Folding this into [TenantDataReader] would have obliged
/// every fake in the suite to grow a cache it has no use for.
abstract interface class TenantCacheReadable implements TenantDataReader {
  /// The same reads, answered **only** from local storage.
  ///
  /// Never fails for a path it has not seen - it answers empty. See
  /// [FirebaseTenantDocumentReader.cacheOnly] for why that is the right shape
  /// for a page filling itself in.
  TenantDataReader get cacheOnly;
}

/// Asking a sales-history reader for the copy this device holds.
///
/// **A second extension because the boundary is a second interface.** The sales
/// report reads through [TenantSalesHistoryQueryReader], which is deliberately
/// not part of [TenantDataReader] - so `cached` cannot answer for it, and this
/// asks the same question of the same object without an unchecked cast.
extension TenantCachedSalesHistoryRead on TenantSalesHistoryQueryReader {
  /// A sales-history reader over local storage only, or null where there is
  /// no local copy - or where the copy cannot answer this particular boundary.
  TenantSalesHistoryQueryReader? get cachedSalesHistory {
    // Typed as Object so the check below can promote: TenantCacheReadable is
    // a TenantDataReader, which is not a supertype of this boundary, and Dart
    // will not promote across two unrelated interfaces.
    final Object self = this;
    if (self is! TenantCacheReadable) return null;
    final Object cached = self.cacheOnly;
    return cached is TenantSalesHistoryQueryReader ? cached : null;
  }
}

/// Asking any reader for the copy this device holds.
extension TenantCachedRead on TenantDocumentReader {
  /// A reader over local storage only, or null where there is no local copy.
  ///
  /// **This is what lets a page opt into drawing early without being handed a
  /// second reader.** Threading one through would have meant widening every
  /// route typedef in the routing shell - each takes exactly one
  /// [TenantDataReader] - to carry a companion that only a handful of routes
  /// would ever name. A page asks the reader it already has instead.
  ///
  /// **Declared on [TenantDocumentReader], the narrowest of the boundaries**,
  /// so the pages holding only that one can ask it too - and answering with a
  /// [TenantDataReader] costs them nothing, since every one of those is a
  /// document reader as well.
  ///
  /// Null for every reader that is not [TenantCacheReadable], which is every
  /// test fake unless it says otherwise, so a suite keeps reading exactly the
  /// way it did before this existed.
  TenantDataReader? get cached {
    final self = this;
    return self is TenantCacheReadable ? self.cacheOnly : null;
  }
}

/// The stock range supported by the inventory product query.
///
/// This deliberately models only facts present on every product. There is no
/// client-side "low" or "overstocked" threshold to guess.
enum TenantProductStockFilter { all, aboveZero, atOrBelowZero }

/// The ordered values required to resume one product search page.
@immutable
final class TenantProductSearchPosition {
  const TenantProductSearchPosition({
    required this.searchName,
    required this.documentId,
    this.quantity,
  });

  final String searchName;
  final String documentId;
  final int? quantity;
}

/// A tenant product query that cannot be expressed through the generic reader.
///
/// Product search needs an array membership predicate, optional numeric range,
/// and a multi-field cursor. Keeping those here prevents the generic collection
/// boundary from becoming an arbitrary Firestore query escape hatch.
final class TenantProductSearchQuery {
  const TenantProductSearchQuery._({
    required this.collectionPath,
    required this.limit,
    required this.stock,
    this.searchPrefix,
    this.categoryId,
    this.startAfter,
  });

  factory TenantProductSearchQuery.forTesting({
    required String collectionPath,
    required int limit,
    TenantProductStockFilter stock = TenantProductStockFilter.all,
    String? searchPrefix,
    String? categoryId,
    TenantProductSearchPosition? startAfter,
  }) => TenantProductSearchQuery._(
    collectionPath: collectionPath,
    limit: limit,
    stock: stock,
    searchPrefix: searchPrefix,
    categoryId: categoryId,
    startAfter: startAfter,
  );

  /// Constructs the query selected by a tenant-scoped product repository.
  ///
  /// The collection path is still checked against every returned document by
  /// that repository; transports receive this value and cannot reinterpret it.
  factory TenantProductSearchQuery.scoped({
    required String collectionPath,
    required int limit,
    required TenantProductStockFilter stock,
    String? searchPrefix,
    String? categoryId,
    TenantProductSearchPosition? startAfter,
  }) => TenantProductSearchQuery._(
    collectionPath: collectionPath,
    limit: limit,
    stock: stock,
    searchPrefix: searchPrefix,
    categoryId: categoryId,
    startAfter: startAfter,
  );

  final String collectionPath;
  final int limit;
  final TenantProductStockFilter stock;
  final String? searchPrefix;
  final String? categoryId;
  final TenantProductSearchPosition? startAfter;
}

/// Dedicated transport for stable, backend-backed product search pages.
abstract interface class TenantProductSearchReader {
  Future<List<TenantQueryDocumentSnapshot>> searchTenantProducts(
    TenantProductSearchQuery query,
  );
}

/// The ordered values required to resume one canonical staff-directory page.
@immutable
final class TenantStaffDirectoryPosition {
  const TenantStaffDirectoryPosition({required this.documentId});

  final String documentId;
}

/// Dedicated tenant staff query selected by the staff repository.
///
/// Search needs array membership and the directory's role/status filters may
/// be combined with it. Those shapes deliberately do not fit through
/// [TenantCollectionQuery], whose small equality-only contract remains intact.
final class TenantStaffDirectoryQuery {
  const TenantStaffDirectoryQuery._({
    required this.collectionPath,
    required this.limit,
    this.searchPrefix,
    this.role,
    this.status,
    this.startAfter,
  });

  factory TenantStaffDirectoryQuery.forTesting({
    required String collectionPath,
    required int limit,
    String? searchPrefix,
    String? role,
    String? status,
    TenantStaffDirectoryPosition? startAfter,
  }) => TenantStaffDirectoryQuery._(
    collectionPath: collectionPath,
    limit: limit,
    searchPrefix: searchPrefix,
    role: role,
    status: status,
    startAfter: startAfter,
  );

  factory TenantStaffDirectoryQuery.scoped({
    required String collectionPath,
    required int limit,
    String? searchPrefix,
    String? role,
    String? status,
    TenantStaffDirectoryPosition? startAfter,
  }) => TenantStaffDirectoryQuery._(
    collectionPath: collectionPath,
    limit: limit,
    searchPrefix: searchPrefix,
    role: role,
    status: status,
    startAfter: startAfter,
  );

  final String collectionPath;
  final int limit;
  final String? searchPrefix;
  final String? role;
  final String? status;
  final TenantStaffDirectoryPosition? startAfter;
}

/// Narrow transport for backend-backed staff search and filtering.
abstract interface class TenantStaffDirectoryQueryReader {
  Future<List<TenantQueryDocumentSnapshot>> queryTenantStaff(
    TenantStaffDirectoryQuery query,
  );
}

/// The ordered values required to resume a newest-first sales report page.
@immutable
final class TenantSalesHistoryPosition {
  const TenantSalesHistoryPosition({
    required this.businessDate,
    required this.documentId,
  });

  final String businessDate;
  final String documentId;
}

/// Dedicated range-and-scope query selected by the sales repository.
///
/// The generic collection reader intentionally cannot express ranges or a
/// multi-field cursor. Keeping the report shape here prevents callers from
/// supplying arbitrary paths, orderings, or predicates.
final class TenantSalesHistoryQuery {
  const TenantSalesHistoryQuery._({
    required this.collectionPath,
    required this.limit,
    required this.startBusinessDate,
    required this.endBusinessDate,
    this.soldById,
    this.startAfter,
  });

  factory TenantSalesHistoryQuery.forTesting({
    required String collectionPath,
    required int limit,
    required String startBusinessDate,
    required String endBusinessDate,
    String? soldById,
    TenantSalesHistoryPosition? startAfter,
  }) => TenantSalesHistoryQuery._(
    collectionPath: collectionPath,
    limit: limit,
    startBusinessDate: startBusinessDate,
    endBusinessDate: endBusinessDate,
    soldById: soldById,
    startAfter: startAfter,
  );

  factory TenantSalesHistoryQuery.scoped({
    required String collectionPath,
    required int limit,
    required String startBusinessDate,
    required String endBusinessDate,
    String? soldById,
    TenantSalesHistoryPosition? startAfter,
  }) => TenantSalesHistoryQuery._(
    collectionPath: collectionPath,
    limit: limit,
    startBusinessDate: startBusinessDate,
    endBusinessDate: endBusinessDate,
    soldById: soldById,
    startAfter: startAfter,
  );

  final String collectionPath;
  final int limit;
  final String startBusinessDate;
  final String endBusinessDate;
  final String? soldById;
  final TenantSalesHistoryPosition? startAfter;
}

/// Narrow transport for the stable tenant sales-report query.
abstract interface class TenantSalesHistoryQueryReader {
  Future<List<TenantQueryDocumentSnapshot>> queryTenantSalesHistory(
    TenantSalesHistoryQuery query,
  );
}

/// A collection-group query that can only be constructed by
/// [TenantReadRepository].
///
/// Unlike [TenantCollectionQuery] this names no path at all: Firestore matches
/// [collectionId] wherever it appears in the database, so the tenant binding is
/// an [equalityFilters] entry the repository always adds itself. The reader may
/// not add, drop, or reinterpret one, and the page is always ordered by
/// ascending document path.
final class TenantCollectionGroupQuery {
  TenantCollectionGroupQuery._({
    required this.collectionId,
    required this.limit,
    this.startAfterDocumentPath,
    Map<String, Object?> equalityFilters = const <String, Object?>{},
  }) : equalityFilters = Map<String, Object?>.unmodifiable(equalityFilters);

  /// Lets a test transport describe a group query a repository did not build.
  factory TenantCollectionGroupQuery.forTesting({
    required String collectionId,
    required int limit,
    String? startAfterDocumentPath,
    Map<String, Object?> equalityFilters = const <String, Object?>{},
  }) => TenantCollectionGroupQuery._(
    collectionId: collectionId,
    limit: limit,
    startAfterDocumentPath: startAfterDocumentPath,
    equalityFilters: equalityFilters,
  );

  /// The last path segment of the collections this query spans.
  final String collectionId;

  final int limit;

  /// The **complete** path of the last document on the previous page.
  ///
  /// A collection-group page is ordered by the whole resource path rather than
  /// by a leaf document ID, so a bare ID could not resume it.
  final String? startAfterDocumentPath;

  final Map<String, Object?> equalityFilters;
}

/// The narrow collection-group read boundary.
///
/// It is deliberately **not** part of [TenantDataReader]. Every other read here
/// is bounded by a path this tenant owns; a group read is bounded only by the
/// filter the repository attaches and the proof it applies afterwards, so a
/// surface that needs one asks for it explicitly.
abstract interface class TenantCollectionGroupReader {
  Future<List<TenantQueryDocumentSnapshot>> getCollectionGroupPage(
    TenantCollectionGroupQuery query,
  );
}

/// Firebase implementation of the tenant document and collection boundaries.
final class FirebaseTenantDocumentReader
    implements
        TenantDataReader,
        TenantCacheReadable,
        TenantCollectionGroupReader,
        TenantProductSearchReader,
        TenantStaffDirectoryQueryReader,
        TenantSalesHistoryQueryReader {
  FirebaseTenantDocumentReader([FirebaseFirestore? firestore])
    : this._(firestore ?? FirebaseFirestore.instance, Source.serverAndCache);

  FirebaseTenantDocumentReader._(this._firestore, this._source);

  final FirebaseFirestore _firestore;

  /// Where a read is allowed to be answered from.
  ///
  /// **`serverAndCache` for the reader the app is built with**, which is the
  /// `.get()` default this class had before the source was named at all - so
  /// naming it changed nothing about the reader every route already holds.
  final Source _source;

  /// The same reader over the same project, answering **only** from what this
  /// device already holds.
  ///
  /// **This is the whole offline story, and it is short because the cache was
  /// always there.** `main.dart` turns Firestore's persistence on with no size
  /// limit, so every document a route has ever read is already on this disk.
  /// What was missing was anything that asked for it: `Source.serverAndCache`
  /// blocks on the network whenever the SDK still believes it has one, which on
  /// one bar of signal is a stall rather than a fallback. A reader that cannot
  /// wait is the other half a route needs to draw immediately and correct
  /// itself afterwards.
  ///
  /// **Nothing it returns escapes the checks the server-backed reader is under.**
  /// It is the same class over the same paths, and `TenantReadRepository` still
  /// validates every document it hands back against the tenant that asked.
  @override
  FirebaseTenantDocumentReader get cacheOnly =>
      FirebaseTenantDocumentReader._(_firestore, Source.cache);

  GetOptions get _options => GetOptions(source: _source);

  /// Runs [read], answering [empty] where this device simply holds nothing.
  ///
  /// **A cache miss is silence, not a failure.** `Source.cache` *throws* for a
  /// path it has never seen rather than returning nothing, which is the right
  /// answer for a caller that asked the cache a question and the wrong shape
  /// for a caller using the cache to fill a screen while the server catches up.
  /// A route reading ahead must not be able to turn "not downloaded yet" into
  /// an error page.
  ///
  /// **Only in cache-only mode**, so the server-backed reader's failures still
  /// reach the caller exactly as they always did. And every [FirebaseException]
  /// counts, rather than one code: there is no server in this mode to refuse
  /// anything, so the only thing the transport can be reporting is that it has
  /// no copy.
  Future<T> _heldOrEmpty<T>(Future<T> Function() read, T empty) async {
    if (_source != Source.cache) return read();
    try {
      return await read();
    } on FirebaseException {
      return empty;
    }
  }

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) =>
      _heldOrEmpty(() async {
        final snapshot = await _firestore.doc(path).get(_options);
        final data = snapshot.data();
        if (!snapshot.exists || data == null) return null;
        return TenantDocumentSnapshot(
          path: snapshot.reference.path,
          data: data,
        );
      }, null);

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
    return _pageOf(request);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionGroupPage(
    TenantCollectionGroupQuery query,
  ) async {
    Query<Map<String, dynamic>> request = _firestore.collectionGroup(
      query.collectionId,
    );
    for (final filter in query.equalityFilters.entries) {
      request = request.where(filter.key, isEqualTo: filter.value);
    }
    request = request.orderBy(FieldPath.documentId).limit(query.limit);
    final cursor = query.startAfterDocumentPath;
    // `__name__` in a collection group orders by the whole resource path, so
    // the cursor is that complete path. Firestore refuses a bare document ID
    // here - it accepts one only for a page whose collection path is known.
    if (cursor != null) request = request.startAfter(<Object>[cursor]);
    return _pageOf(request);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> searchTenantProducts(
    TenantProductSearchQuery query,
  ) async {
    Query<Map<String, dynamic>> request = _firestore.collection(
      query.collectionPath,
    );
    if (query.searchPrefix case final prefix?) {
      request = request.where('searchPrefixes', arrayContains: prefix);
    }
    if (query.categoryId case final categoryId?) {
      request = request.where('categoryId', isEqualTo: categoryId);
    }
    switch (query.stock) {
      case TenantProductStockFilter.all:
        break;
      case TenantProductStockFilter.aboveZero:
        request = request.where('quantity', isGreaterThan: 0);
        break;
      case TenantProductStockFilter.atOrBelowZero:
        request = request.where('quantity', isLessThanOrEqualTo: 0);
        break;
    }

    if (query.stock == TenantProductStockFilter.all) {
      request = request
          .orderBy('searchName')
          .orderBy(FieldPath.documentId)
          .limit(query.limit);
      if (query.startAfter case final cursor?) {
        request = request.startAfter(<Object>[
          cursor.searchName,
          cursor.documentId,
        ]);
      }
    } else {
      request = request
          .orderBy('quantity')
          .orderBy('searchName')
          .orderBy(FieldPath.documentId)
          .limit(query.limit);
      if (query.startAfter case final cursor?) {
        request = request.startAfter(<Object>[
          cursor.quantity!,
          cursor.searchName,
          cursor.documentId,
        ]);
      }
    }
    return _pageOf(request);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> queryTenantStaff(
    TenantStaffDirectoryQuery query,
  ) async {
    Query<Map<String, dynamic>> request = _firestore.collection(
      query.collectionPath,
    );
    if (query.searchPrefix case final prefix?) {
      request = request.where('searchPrefixes', arrayContains: prefix);
    }
    if (query.role case final role?) {
      request = request.where('role', isEqualTo: role);
    }
    if (query.status case final status?) {
      request = request.where('status', isEqualTo: status);
    }
    request = request.orderBy(FieldPath.documentId).limit(query.limit);
    if (query.startAfter case final cursor?) {
      request = request.startAfter(<Object>[cursor.documentId]);
    }
    return _pageOf(request);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> queryTenantSalesHistory(
    TenantSalesHistoryQuery query,
  ) async {
    Query<Map<String, dynamic>> request = _firestore
        .collection(query.collectionPath)
        .where('businessDate', isGreaterThanOrEqualTo: query.startBusinessDate)
        .where('businessDate', isLessThanOrEqualTo: query.endBusinessDate);
    if (query.soldById case final staffId?) {
      request = request.where('soldById', isEqualTo: staffId);
    }
    request = request
        .orderBy('businessDate', descending: true)
        .orderBy(FieldPath.documentId, descending: true)
        .limit(query.limit);
    if (query.startAfter case final cursor?) {
      request = request.startAfter(<Object>[
        cursor.businessDate,
        cursor.documentId,
      ]);
    }
    return _pageOf(request);
  }

  /// One page, from wherever [_source] allows, empty where nothing is held.
  Future<List<TenantQueryDocumentSnapshot>> _pageOf(
    Query<Map<String, dynamic>> request,
  ) => _heldOrEmpty(
    () async => _snapshots(await request.get(_options)),
    const <TenantQueryDocumentSnapshot>[],
  );

  static List<TenantQueryDocumentSnapshot> _snapshots(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) => snapshot.docs
      .map(
        (document) => TenantQueryDocumentSnapshot(
          path: document.reference.path,
          data: document.data(),
        ),
      )
      .toList(growable: false);
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

/// A bounded collection-group page ordered by ascending Firestore document
/// path.
final class TenantDocumentGroupPage {
  TenantDocumentGroupPage({
    required List<TenantQueryDocumentSnapshot> items,
    required this.nextCursor,
    required this.hasMore,
  }) : items = List<TenantQueryDocumentSnapshot>.unmodifiable(items);

  final List<TenantQueryDocumentSnapshot> items;

  /// The **complete** path of the last document on this page.
  ///
  /// A group page spans many parent documents, so only a whole path identifies
  /// the position the next page resumes from.
  final String? nextCursor;

  final bool hasMore;
}

/// Base for read-only repositories bound to one live tenant session.
///
/// Callers select a known [TenantCollection] and document ID. They cannot pass
/// a root collection or an arbitrary Firestore path.
abstract base class TenantReadRepository {
  TenantReadRepository({required this.session, required this.reader})
    : paths = TenantPaths(session.tenantId) {
    if (!session.canAccess()) {
      throw StateError('A tenant repository requires a readable session.');
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

  /// Reads one bounded page of an allowed product subcollection across **every**
  /// product in this tenant.
  ///
  /// A collection-group query is the one read here that Firestore does not
  /// bound by a path prefix: it matches [subcollection] wherever it appears in
  /// the database. The tenant binding is therefore an equality filter this
  /// method attaches itself - a caller may not supply, override, or drop it -
  /// and the exact-child proof is extended rather than bypassed: every returned
  /// document must be a `tenants/{tenantId}/products/{productId}/
  /// {subcollection}/{documentId}` path below **this** session's own root, with
  /// two validated document IDs, no duplicates, and ascending path order.
  ///
  /// The filter is not decoration. The matching Firestore rule authorizes the
  /// page by that exact `tenantId ==` condition, so a page issued without it is
  /// refused by the server as well as here.
  Future<TenantDocumentGroupPage> readProductSubcollectionGroupPage(
    TenantProductSubcollection subcollection, {
    required TenantCollectionGroupReader groupReader,
    int pageSize = 20,
    String? cursor,
    Map<String, Object?> equalityFilters = const <String, Object?>{},
  }) async {
    if (pageSize < 1 || pageSize > 50) {
      throw RangeError.range(pageSize, 1, 50, 'pageSize');
    }
    final callerFilters = _validatedEqualityFilters(equalityFilters);
    if (callerFilters.containsKey(tenantIdField)) {
      throw ArgumentError.value(
        equalityFilters,
        'equalityFilters',
        'The tenant binding of a group page is not a caller-supplied filter.',
      );
    }
    final validatedCursor = cursor == null
        ? null
        : _validatedGroupCursor(cursor, subcollection);
    final requestedLimit = pageSize + 1;
    final snapshots = await groupReader.getCollectionGroupPage(
      TenantCollectionGroupQuery._(
        collectionId: subcollection.segment,
        limit: requestedLimit,
        startAfterDocumentPath: validatedCursor,
        equalityFilters: <String, Object?>{
          tenantIdField: session.tenantId,
          ...callerFilters,
        },
      ),
    );
    if (snapshots.length > requestedLimit) {
      throw const TenantScopeViolation(
        'A collection group reader returned more documents than requested.',
      );
    }

    final seenPaths = <String>{};
    String? previousPath;
    for (final snapshot in snapshots) {
      _requireGroupChildPath(snapshot.path, subcollection);
      if (!seenPaths.add(snapshot.path)) {
        throw TenantScopeViolation(
          'The group reader returned duplicate document ${snapshot.path}.',
        );
      }
      if (previousPath != null &&
          compareDocumentPaths(previousPath, snapshot.path) >= 0) {
        throw const TenantScopeViolation(
          'Collection group results were not ordered by document path.',
        );
      }
      previousPath = snapshot.path;
    }

    final hasMore = snapshots.length > pageSize;
    final items = hasMore ? snapshots.take(pageSize).toList() : snapshots;
    return TenantDocumentGroupPage(
      items: items,
      nextCursor: hasMore ? items.last.path : null,
      hasMore: hasMore,
    );
  }

  /// Proves one group result really is an exact child of an allowed product
  /// subcollection inside this session's own tenant.
  void _requireGroupChildPath(
    String path,
    TenantProductSubcollection subcollection,
  ) {
    final segments = path.split('/');
    if (segments.length != 6 ||
        segments[0] != 'tenants' ||
        segments[2] != TenantCollection.products.segment ||
        segments[4] != subcollection.segment ||
        !paths.owns(path) ||
        segments[1] != session.tenantId) {
      throw TenantScopeViolation(
        'Expected a ${subcollection.segment} document below ${paths.root} but '
        'received $path.',
      );
    }
    try {
      validateTenantDocumentId(segments[3], fieldName: 'productId');
      validateTenantDocumentId(segments[5]);
    } on ArgumentError {
      throw TenantScopeViolation(
        'The returned document path is not an exact group child: $path.',
      );
    }
  }

  String _validatedGroupCursor(
    String cursor,
    TenantProductSubcollection subcollection,
  ) {
    try {
      _requireGroupChildPath(cursor, subcollection);
    } on TenantScopeViolation {
      throw ArgumentError.value(
        cursor,
        'cursor',
        'Not a ${subcollection.segment} document path in this tenant.',
      );
    }
    return cursor;
  }

  /// Compares two document paths the way Firestore orders `__name__`.
  ///
  /// The comparison is segment by segment, never over the joined string: a
  /// product `p` sorts before `p-2`, while `tenants/t/products/p/...` sorts
  /// *after* `tenants/t/products/p-2/...` as plain text, because `-` is below
  /// `/`. A string comparison would therefore reject a page Firestore ordered
  /// correctly.
  static int compareDocumentPaths(String left, String right) {
    final leftSegments = left.split('/');
    final rightSegments = right.split('/');
    final shared = leftSegments.length < rightSegments.length
        ? leftSegments.length
        : rightSegments.length;
    for (var index = 0; index < shared; index++) {
      final order = leftSegments[index].compareTo(rightSegments[index]);
      if (order != 0) return order;
    }
    return leftSegments.length.compareTo(rightSegments.length);
  }

  /// The field every tenant-scoped document repeats from its own path, and the
  /// only binding a collection-group page and its Firestore rule share.
  static const String tenantIdField = 'tenantId';

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
      final ordered =
          previousId == null ||
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
