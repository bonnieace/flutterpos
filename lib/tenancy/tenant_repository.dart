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
/// One stored instant, however the reader that answered spells it.
///
/// **Both spellings, because both are real.** Firestore answers a timestamp as
/// its own `Timestamp`; every test double, every cached projection, and every
/// record this device composed answers a `DateTime`. Anything else - including
/// a server timestamp a local write has not had filled in yet - is null, and
/// the caller decides whether that is a refusal or a fallback.
DateTime? tenantStoredInstant(Object? value) {
  if (value is DateTime) return value.toUtc();
  if (value is Timestamp) return value.toDate().toUtc();
  return null;
}

/// How a page of a collection is ordered, and by what.
///
/// **A typed enum, never a caller-supplied field name**, for the reason every
/// other narrowing on this boundary is one: a repository decides what a surface
/// may sort by, and a string would let a caller ask for an ordering no index
/// serves and no proof below checks.
///
/// [documentId] is what every read here used until 2026-09-14 and what most of
/// them still use. It is not a weaker choice - for a collection whose IDs are
/// sequential or date-prefixed it *is* the chronological order, and it needs no
/// composite index. The two time orderings exist for the stock ledger alone,
/// where an ID is a digest and carries no time information whatever.
enum TenantCollectionOrder {
  /// By document ID, ascending or descending. Needs no composite index.
  documentId(null),

  /// By when the record was written, then by document ID to break ties.
  createdAt('createdAt'),

  /// By when the stock actually moved, then by document ID.
  ///
  /// Distinct from `recordedAt` deliberately: a sale reconciled hours later
  /// moved its units when the sale happened, and "what happened most recently"
  /// is a question about the shop, not about the server's write log.
  occurredAt('occurredAt');

  const TenantCollectionOrder(this.field);

  /// The document field this orders by, or null to order by document ID.
  final String? field;

  bool get isByDocumentId => field == null;
}

/// The cursor a time-ordered page resumes after.
///
/// **Two values, because one is not enough.** Firestore orders by the named
/// field and then by document ID, so resuming needs both: two movements
/// recorded in the same millisecond are separated only by their IDs, and a
/// cursor carrying just the instant would either repeat one or skip one.
///
/// Written as `<microseconds>|<document>` so it stays the opaque string every
/// paginated surface in this app already passes around.
final class TenantPageCursor {
  const TenantPageCursor({required this.at, required this.document});

  final DateTime at;

  /// The document ID for a collection page, or the whole resource path for a
  /// collection-group page - whichever that page is ordered by after the field.
  final String document;

  static const String separator = '|';

  String encode() => '${at.toUtc().microsecondsSinceEpoch}$separator$document';

  /// Reads one back, refusing anything this boundary did not write.
  static TenantPageCursor decode(String cursor, {String fieldName = 'cursor'}) {
    final at = cursor.indexOf(separator);
    if (at <= 0 || at == cursor.length - 1) {
      throw ArgumentError.value(cursor, fieldName, 'is not a page cursor');
    }
    final micros = int.tryParse(cursor.substring(0, at));
    if (micros == null) {
      throw ArgumentError.value(cursor, fieldName, 'is not a page cursor');
    }
    return TenantPageCursor(
      at: DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true),
      document: cursor.substring(at + 1),
    );
  }
}

final class TenantCollectionQuery {
  TenantCollectionQuery._({
    required this.collectionPath,
    required this.limit,
    this.startAfterDocumentId,
    this.startAfterOrderValue,
    this.descending = false,
    this.order = TenantCollectionOrder.documentId,
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
    DateTime? startAfterOrderValue,
    bool descending = false,
    TenantCollectionOrder order = TenantCollectionOrder.documentId,
    Map<String, Object?> equalityFilters = const <String, Object?>{},
  }) => TenantCollectionQuery._(
    collectionPath: collectionPath,
    limit: limit,
    startAfterDocumentId: startAfterDocumentId,
    startAfterOrderValue: startAfterOrderValue,
    descending: descending,
    order: order,
    equalityFilters: equalityFilters,
  );

  final String collectionPath;
  final int limit;
  final String? startAfterDocumentId;

  /// The ordering field's value on the last document of the previous page, for
  /// a time-ordered page. Null for one ordered by document ID, which needs no
  /// second cursor component.
  final DateTime? startAfterOrderValue;

  /// Whether the page runs from the largest ordering value downwards.
  final bool descending;

  /// What the page is ordered by. See [TenantCollectionOrder].
  final TenantCollectionOrder order;

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

/// A reader that can also be made to ignore the copy this device holds.
///
/// **The mirror of [TenantCacheReadable], and it exists for the opposite
/// reason.** `cacheOnly` is for a surface that wants an answer now and will
/// correct it later; this is for the few questions where an answer out of local
/// storage is not an answer at all - where the caller is deciding whether the
/// *server* has something, and a copy of the device's own unsent write would
/// answer *yes* to a question that was really about the server.
///
/// See `TenantShiftController._settle`: promoting a shift record to
/// `serverConfirmedOpen` on a cache-answered read is what let a rejected create
/// take a trading day's sales down with it.
abstract interface class TenantServerReadable implements TenantDataReader {
  /// The same reads, answered **only** by the server.
  ///
  /// Unlike [TenantCacheReadable.cacheOnly] this one *fails* rather than
  /// answering empty when it cannot be served - being unable to reach the
  /// server is precisely the case the caller has to tell apart, so it must not
  /// be flattened into "nothing there".
  TenantDataReader get serverOnly;
}

/// Asking any reader to leave this device's own copy out of it.
extension TenantServerRead on TenantDocumentReader {
  /// A reader that only the server may answer, or null where this reader has no
  /// such mode - which is every test fake unless it says otherwise, so a suite
  /// keeps reading exactly the way it did before this existed.
  ///
  /// **A null answer must fail closed at the call site**, not fall back to this
  /// reader: the whole point of asking is that a local answer will not do.
  TenantDataReader? get serverBacked {
    final self = this;
    return self is TenantServerReadable ? self.serverOnly : null;
  }
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

/// Asking a product-search reader for the copy this device holds.
///
/// **A third extension, for the same reason as the one above.** The catalog
/// searches through [TenantProductSearchReader], which is not part of
/// [TenantDataReader] either - so a panel that pairs `reader.cached` with the
/// live search reader reads its categories off the disk and its products off
/// the network, which is the whole page waiting for a network it has already
/// decided it does not need.
extension TenantCachedProductSearchRead on TenantProductSearchReader {
  /// A product-search reader over local storage only, or null where there is
  /// no local copy - or where the copy cannot answer this particular boundary.
  TenantProductSearchReader? get cachedProductSearch {
    // Typed as Object to promote across two unrelated interfaces, exactly as
    // [TenantCachedSalesHistoryRead.cachedSalesHistory] does.
    final Object self = this;
    if (self is! TenantCacheReadable) return null;
    final Object cached = self.cacheOnly;
    return cached is TenantProductSearchReader ? cached : null;
  }
}

/// Asking a collection-group reader for the copy this device holds.
///
/// The stock movement feed reads across every product's `stock_movements` at
/// once, which is a [TenantCollectionGroupReader] and so a fourth boundary
/// `cached` cannot answer for.
extension TenantCachedCollectionGroupRead on TenantCollectionGroupReader {
  /// A collection-group reader over local storage only, or null where there is
  /// no local copy - or where the copy cannot answer this particular boundary.
  TenantCollectionGroupReader? get cachedCollectionGroup {
    final Object self = this;
    if (self is! TenantCacheReadable) return null;
    final Object cached = self.cacheOnly;
    return cached is TenantCollectionGroupReader ? cached : null;
  }
}

/// Asking a staff-directory reader for the copy this device holds.
///
/// Nothing wires a companion directory reader today - the staff screen hands
/// over one reader and the repository resolves the boundary off it - so this
/// exists to keep that true the day something does.
extension TenantCachedStaffDirectoryRead on TenantStaffDirectoryQueryReader {
  /// A staff-directory reader over local storage only, or null where there is
  /// no local copy - or where the copy cannot answer this particular boundary.
  TenantStaffDirectoryQueryReader? get cachedStaffDirectory {
    final Object self = this;
    if (self is! TenantCacheReadable) return null;
    final Object cached = self.cacheOnly;
    return cached is TenantStaffDirectoryQueryReader ? cached : null;
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

/// The ordered values required to resume one customer search page.
@immutable
final class TenantCustomerSearchPosition {
  const TenantCustomerSearchPosition({
    required this.searchName,
    required this.documentId,
  });

  final String searchName;
  final String documentId;
}

/// A tenant customer query that cannot be expressed through the generic reader.
///
/// **The product search's shape, narrowed to what a customer has**: an array
/// membership predicate on the name and number prefixes, an optional standing,
/// and a cursor ordered by name. Kept out of [TenantCollectionQuery] for the
/// reason [TenantProductSearchQuery] is.
final class TenantCustomerSearchQuery {
  const TenantCustomerSearchQuery._({
    required this.collectionPath,
    required this.limit,
    this.searchPrefix,
    this.active,
    this.startAfter,
  });

  factory TenantCustomerSearchQuery.forTesting({
    required String collectionPath,
    required int limit,
    String? searchPrefix,
    bool? active,
    TenantCustomerSearchPosition? startAfter,
  }) => TenantCustomerSearchQuery._(
    collectionPath: collectionPath,
    limit: limit,
    searchPrefix: searchPrefix,
    active: active,
    startAfter: startAfter,
  );

  /// Constructs the query selected by a tenant-scoped customer repository.
  factory TenantCustomerSearchQuery.scoped({
    required String collectionPath,
    required int limit,
    String? searchPrefix,
    bool? active,
    TenantCustomerSearchPosition? startAfter,
  }) => TenantCustomerSearchQuery._(
    collectionPath: collectionPath,
    limit: limit,
    searchPrefix: searchPrefix,
    active: active,
    startAfter: startAfter,
  );

  final String collectionPath;
  final int limit;
  final String? searchPrefix;

  /// Only customers of this standing, or both when null.
  final bool? active;
  final TenantCustomerSearchPosition? startAfter;
}

/// Dedicated transport for stable, backend-backed customer search pages.
abstract interface class TenantCustomerSearchReader {
  Future<List<TenantQueryDocumentSnapshot>> searchTenantCustomers(
    TenantCustomerSearchQuery query,
  );
}

/// Asking a customer-search reader for the copy this device holds.
///
/// **The till's picker draws from this first**, so a cashier with no signal
/// still finds every customer this device has seen, and the server corrects
/// the list when it answers.
extension TenantCachedCustomerSearchRead on TenantCustomerSearchReader {
  /// A customer-search reader over local storage only, or null where there is
  /// no local copy - or where the copy cannot answer this particular boundary.
  TenantCustomerSearchReader? get cachedCustomerSearch {
    final Object self = this;
    if (self is! TenantCacheReadable) return null;
    final Object cached = self.cacheOnly;
    return cached is TenantCustomerSearchReader ? cached : null;
  }
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

/// The business-date field a period read ranges over.
///
/// **An enum rather than a field name**, for the reason no query here takes a
/// caller-supplied predicate: a range is the one shape that can walk off the
/// end of an index, and a free string would let a caller ask for a scan no
/// index serves and no rule anticipated. Two collections, two fields, both
/// named here.
enum TenantBusinessDateRangeField {
  /// `returns.recordedOn` - the day the reversal was taken.
  ///
  /// **Not `businessDate`, which is the day of the *sale* being reversed.** A
  /// returns report answers what came back over a period, so it is keyed to
  /// when the return happened. Netting a day's takings is the other question
  /// and `loadDayReturns` already answers it.
  recordedOn('recordedOn'),

  /// `shifts.businessDate` - the trading day a shift belongs to.
  businessDate('businessDate');

  const TenantBusinessDateRangeField(this.field);

  final String field;
}

/// Where a business-date range page resumes.
///
/// Two components for the reason [TenantPageCursor] carries two: the page is
/// ordered by the date and then by document ID, and a cursor holding only the
/// date would either repeat a record or skip one wherever a day holds more
/// than one.
final class TenantBusinessDateRangePosition {
  const TenantBusinessDateRangePosition({
    required this.businessDate,
    required this.documentId,
  });

  final String businessDate;
  final String documentId;
}

/// A period read over a collection keyed by a business-date string.
///
/// **No equality filter, deliberately.** A single-field inequality plus
/// `__name__` is served by Firestore's *automatic* index; joining an equality
/// to it needs a composite one per combination. A report covers the whole
/// business over a period and narrows nothing, so it asks for nothing that
/// needs an index to be deployed before it will run.
final class TenantBusinessDateRangeQuery {
  const TenantBusinessDateRangeQuery._({
    required this.collectionPath,
    required this.orderBy,
    required this.limit,
    required this.startBusinessDate,
    required this.endBusinessDate,
    this.startAfter,
  });

  /// Built by a repository, which owns the path and the field.
  factory TenantBusinessDateRangeQuery.scoped({
    required String collectionPath,
    required TenantBusinessDateRangeField orderBy,
    required int limit,
    required String startBusinessDate,
    required String endBusinessDate,
    TenantBusinessDateRangePosition? startAfter,
  }) => TenantBusinessDateRangeQuery._(
    collectionPath: collectionPath,
    orderBy: orderBy,
    limit: limit,
    startBusinessDate: startBusinessDate,
    endBusinessDate: endBusinessDate,
    startAfter: startAfter,
  );

  /// Lets a test transport describe a query a repository did not build.
  factory TenantBusinessDateRangeQuery.forTesting({
    required String collectionPath,
    required TenantBusinessDateRangeField orderBy,
    required int limit,
    required String startBusinessDate,
    required String endBusinessDate,
    TenantBusinessDateRangePosition? startAfter,
  }) => TenantBusinessDateRangeQuery._(
    collectionPath: collectionPath,
    orderBy: orderBy,
    limit: limit,
    startBusinessDate: startBusinessDate,
    endBusinessDate: endBusinessDate,
    startAfter: startAfter,
  );

  final String collectionPath;
  final TenantBusinessDateRangeField orderBy;
  final int limit;

  /// Inclusive, both ends: a period report covers the days it names.
  final String startBusinessDate;
  final String endBusinessDate;

  final TenantBusinessDateRangePosition? startAfter;
}

/// A period read over a collection whose **document IDs** carry the date.
///
/// **`stock_takes` and nothing else, and it needs no index at all.** A take's
/// ID is `st_<businessDate>_<digest>` - see `tenantStockTakeId` - so a range
/// over the key itself selects a span of trading days, and Firestore serves a
/// `__name__` range without any index being declared. The alternative was a
/// `businessDate` field range, which would have been a second copy of a fact
/// the ID already states.
final class TenantDocumentIdRangeQuery {
  const TenantDocumentIdRangeQuery._({
    required this.collectionPath,
    required this.limit,
    required this.startAtDocumentId,
    required this.endAtDocumentId,
    this.startAfterDocumentId,
  });

  factory TenantDocumentIdRangeQuery.scoped({
    required String collectionPath,
    required int limit,
    required String startAtDocumentId,
    required String endAtDocumentId,
    String? startAfterDocumentId,
  }) => TenantDocumentIdRangeQuery._(
    collectionPath: collectionPath,
    limit: limit,
    startAtDocumentId: startAtDocumentId,
    endAtDocumentId: endAtDocumentId,
    startAfterDocumentId: startAfterDocumentId,
  );

  factory TenantDocumentIdRangeQuery.forTesting({
    required String collectionPath,
    required int limit,
    required String startAtDocumentId,
    required String endAtDocumentId,
    String? startAfterDocumentId,
  }) => TenantDocumentIdRangeQuery._(
    collectionPath: collectionPath,
    limit: limit,
    startAtDocumentId: startAtDocumentId,
    endAtDocumentId: endAtDocumentId,
    startAfterDocumentId: startAfterDocumentId,
  );

  final String collectionPath;
  final int limit;

  /// Inclusive bounds on the document key, ascending.
  final String startAtDocumentId;
  final String endAtDocumentId;

  final String? startAfterDocumentId;
}

/// Where an instant-ordered range page resumes.
final class TenantInstantRangePosition {
  const TenantInstantRangePosition({
    required this.at,
    required this.documentId,
  });

  final DateTime at;
  final String documentId;
}

/// A period read over a collection whose only time is a recorded instant.
///
/// **`audit_logs`, where the ID is a digest.** An audit ID is the operation,
/// request or delivery ID the event belongs to, so the key order carries no
/// time information whatever and the existing feed says so outright. Ordering
/// by `createdAt` is what lets a period be asked for at all - it is the same
/// move `TenantCollectionOrder.createdAt` already made for the stock ledger,
/// and it is why the logs report could not be built before.
final class TenantInstantRangeQuery {
  TenantInstantRangeQuery._({
    required this.collectionPath,
    required this.limit,
    required this.startAt,
    required this.endAt,
    required this.order,
    this.startAfter,
  }) {
    if (order.field == null) {
      throw ArgumentError.value(order, 'order', 'Must name an instant field.');
    }
  }

  factory TenantInstantRangeQuery.scoped({
    required String collectionPath,
    required int limit,
    required DateTime startAt,
    required DateTime endAt,
    TenantCollectionOrder order = TenantCollectionOrder.createdAt,
    TenantInstantRangePosition? startAfter,
  }) => TenantInstantRangeQuery._(
    collectionPath: collectionPath,
    limit: limit,
    startAt: startAt,
    endAt: endAt,
    order: order,
    startAfter: startAfter,
  );

  factory TenantInstantRangeQuery.forTesting({
    required String collectionPath,
    required int limit,
    required DateTime startAt,
    required DateTime endAt,
    TenantCollectionOrder order = TenantCollectionOrder.createdAt,
    TenantInstantRangePosition? startAfter,
  }) => TenantInstantRangeQuery._(
    collectionPath: collectionPath,
    limit: limit,
    startAt: startAt,
    endAt: endAt,
    order: order,
    startAfter: startAfter,
  );

  final String collectionPath;
  final int limit;

  /// Which instant the window bounds. `createdAt`, when the server wrote the
  /// record, for the audit log; `occurredAt`, when it happened on the device
  /// that made it, for anything a device can make offline and send later.
  final TenantCollectionOrder order;

  /// Inclusive at both ends, in UTC.
  final DateTime startAt;
  final DateTime endAt;

  final TenantInstantRangePosition? startAfter;
}

/// Narrow transport for the three period reads a report can need.
///
/// **One interface rather than three**, which is a departure from the one
/// narrow reader per query this file otherwise keeps. The three exist for a
/// single purpose - reading a named period so a document can state it - they
/// are implemented by the same transport, and a fake that supports one
/// invariably has to support the others. Splitting them would have put three
/// `is` casts at every call site to buy nothing.
abstract interface class TenantReportRangeReader {
  /// A span of trading days over a collection carrying a business-date field.
  Future<List<TenantQueryDocumentSnapshot>> queryTenantBusinessDateRange(
    TenantBusinessDateRangeQuery query,
  );

  /// A span of document keys, for a collection whose IDs carry the date.
  Future<List<TenantQueryDocumentSnapshot>> queryTenantDocumentIdRange(
    TenantDocumentIdRangeQuery query,
  );

  /// A span of recorded instants, for a collection whose IDs carry no time.
  Future<List<TenantQueryDocumentSnapshot>> queryTenantInstantRange(
    TenantInstantRangeQuery query,
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
    this.startAfterOrderValue,
    this.descending = false,
    this.order = TenantCollectionOrder.documentId,
    Map<String, Object?> equalityFilters = const <String, Object?>{},
  }) : equalityFilters = Map<String, Object?>.unmodifiable(equalityFilters);

  /// Lets a test transport describe a group query a repository did not build.
  factory TenantCollectionGroupQuery.forTesting({
    required String collectionId,
    required int limit,
    String? startAfterDocumentPath,
    DateTime? startAfterOrderValue,
    bool descending = false,
    TenantCollectionOrder order = TenantCollectionOrder.documentId,
    Map<String, Object?> equalityFilters = const <String, Object?>{},
  }) => TenantCollectionGroupQuery._(
    collectionId: collectionId,
    limit: limit,
    startAfterDocumentPath: startAfterDocumentPath,
    startAfterOrderValue: startAfterOrderValue,
    descending: descending,
    order: order,
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

  /// The ordering field's value on the last document of the previous page, for
  /// a time-ordered page. Null for one ordered by resource path.
  final DateTime? startAfterOrderValue;

  /// Whether the page runs from the largest ordering value downwards.
  final bool descending;

  /// What the page is ordered by. See [TenantCollectionOrder].
  final TenantCollectionOrder order;

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
        TenantServerReadable,
        TenantCollectionGroupReader,
        TenantProductSearchReader,
        TenantCustomerSearchReader,
        TenantStaffDirectoryQueryReader,
        TenantSalesHistoryQueryReader,
        TenantReportRangeReader {
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

  /// The same reader over the same project, answering **only** from the server.
  ///
  /// **`Source.server` is the whole of it, and it is the half of H2's fix that
  /// had to exist somewhere.** A `serverAndCache` read falls back to local
  /// storage whenever the server cannot be reached, and local storage contains
  /// this device's own writes the instant they are made - so a caller asking
  /// *does the server have this* could be shown its own unsent `set` and
  /// believe the answer. This mode cannot be: it reaches the server or it
  /// throws, and the throw is the honest answer.
  @override
  FirebaseTenantDocumentReader get serverOnly =>
      FirebaseTenantDocumentReader._(_firestore, Source.server);

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
  Future<TenantDocumentSnapshot?> getDocument(String path) => _heldOrEmpty(
    () async {
      final snapshot = await _firestore.doc(path).get(_options);
      final data = snapshot.data();
      if (!snapshot.exists || data == null) return null;
      return TenantDocumentSnapshot(path: snapshot.reference.path, data: data);
    },
    null,
  );

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
    // The field first and the document ID second, exactly as the ordering proof
    // in [TenantReadRepository] checks: the ID is what separates two records
    // written in the same millisecond, and a page ordered on the field alone
    // could repeat one or skip one across a page boundary.
    final orderField = query.order.field;
    if (orderField != null) {
      request = request.orderBy(orderField, descending: query.descending);
    }
    request = request
        .orderBy(FieldPath.documentId, descending: query.descending)
        .limit(query.limit);
    final cursor = query.startAfterDocumentId;
    if (cursor != null) {
      final orderValue = query.startAfterOrderValue;
      request = request.startAfter(<Object>[
        if (orderField != null && orderValue != null)
          Timestamp.fromDate(orderValue),
        cursor,
      ]);
    }
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
    final orderField = query.order.field;
    if (orderField != null) {
      request = request.orderBy(orderField, descending: query.descending);
    }
    request = request
        .orderBy(FieldPath.documentId, descending: query.descending)
        .limit(query.limit);
    final cursor = query.startAfterDocumentPath;
    // `__name__` in a collection group orders by the whole resource path, so
    // the cursor is that complete path. Firestore refuses a bare document ID
    // here - it accepts one only for a page whose collection path is known.
    if (cursor != null) {
      final orderValue = query.startAfterOrderValue;
      request = request.startAfter(<Object>[
        if (orderField != null && orderValue != null)
          Timestamp.fromDate(orderValue),
        cursor,
      ]);
    }
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
  Future<List<TenantQueryDocumentSnapshot>> searchTenantCustomers(
    TenantCustomerSearchQuery query,
  ) async {
    Query<Map<String, dynamic>> request = _firestore.collection(
      query.collectionPath,
    );
    if (query.active case final active?) {
      request = request.where('active', isEqualTo: active);
    }
    if (query.searchPrefix case final prefix?) {
      request = request.where('searchPrefixes', arrayContains: prefix);
    }
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

  @override
  Future<List<TenantQueryDocumentSnapshot>> queryTenantBusinessDateRange(
    TenantBusinessDateRangeQuery query,
  ) async {
    final field = query.orderBy.field;
    // **Ascending, unlike the sales report.** A report reads a period from its
    // first day forward, and the pages are assembled into one document rather
    // than shown a screenful at a time, so newest-first would only oblige the
    // analysis to reverse what it was handed.
    Query<Map<String, dynamic>> request = _firestore
        .collection(query.collectionPath)
        .where(field, isGreaterThanOrEqualTo: query.startBusinessDate)
        .where(field, isLessThanOrEqualTo: query.endBusinessDate)
        .orderBy(field)
        .orderBy(FieldPath.documentId)
        .limit(query.limit);
    if (query.startAfter case final cursor?) {
      request = request.startAfter(<Object>[
        cursor.businessDate,
        cursor.documentId,
      ]);
    }
    return _pageOf(request);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> queryTenantDocumentIdRange(
    TenantDocumentIdRangeQuery query,
  ) async {
    Query<Map<String, dynamic>> request = _firestore
        .collection(query.collectionPath)
        .where(
          FieldPath.documentId,
          isGreaterThanOrEqualTo: query.startAtDocumentId,
        )
        .where(FieldPath.documentId, isLessThanOrEqualTo: query.endAtDocumentId)
        .orderBy(FieldPath.documentId)
        .limit(query.limit);
    if (query.startAfterDocumentId case final cursor?) {
      request = request.startAfter(<Object>[cursor]);
    }
    return _pageOf(request);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> queryTenantInstantRange(
    TenantInstantRangeQuery query,
  ) async {
    // The ordering the stock ledger already added, reused rather than a second
    // spelling of the same field name.
    final field = query.order.field!;
    Query<Map<String, dynamic>> request = _firestore
        .collection(query.collectionPath)
        .where(field, isGreaterThanOrEqualTo: Timestamp.fromDate(query.startAt))
        .where(field, isLessThanOrEqualTo: Timestamp.fromDate(query.endAt))
        .orderBy(field)
        .orderBy(FieldPath.documentId)
        .limit(query.limit);
    if (query.startAfter case final cursor?) {
      request = request.startAfter(<Object>[
        Timestamp.fromDate(cursor.at),
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
  /// [descending] reverses the ordering so a history surface can page from the
  /// newest record; the ordering proof reverses with it. [order] chooses what
  /// that ordering is over - the document ID by default, or one of the two
  /// instants [TenantCollectionOrder] names, which is a typed choice and never
  /// a caller-supplied field.
  Future<TenantDocumentPage> readCollectionPage(
    TenantCollection collection, {
    required TenantCollectionReader collectionReader,
    int pageSize = 20,
    String? cursor,
    bool descending = false,
    TenantCollectionOrder order = TenantCollectionOrder.documentId,
    Map<String, Object?> equalityFilters = const <String, Object?>{},
  }) => _readPage(
    paths.collectionPath(collection),
    collectionReader: collectionReader,
    pageSize: pageSize,
    cursor: cursor,
    descending: descending,
    order: order,
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
  /// Pages one stock take's lines, proved to be children of that take.
  ///
  /// The same shape as [readProductSubcollectionPage] and for the same reason:
  /// a subcollection is reachable only through a named enum, so no caller can
  /// hand this a path of its own devising.
  Future<TenantDocumentPage> readStockTakeSubcollectionPage(
    TenantStockTakeSubcollection subcollection, {
    required String takeId,
    required TenantCollectionReader collectionReader,
    int pageSize = 20,
    String? cursor,
    bool descending = false,
    Map<String, Object?> equalityFilters = const <String, Object?>{},
  }) async => _readPage(
    paths.stockTakeSubcollectionPath(takeId, subcollection),
    collectionReader: collectionReader,
    pageSize: pageSize,
    cursor: cursor,
    descending: descending,
    equalityFilters: equalityFilters,
  );

  /// Pages one customer's ledger, proved to be children of that customer.
  Future<TenantDocumentPage> readCustomerSubcollectionPage(
    TenantCustomerSubcollection subcollection, {
    required String customerId,
    required TenantCollectionReader collectionReader,
    int pageSize = 20,
    String? cursor,
    bool descending = false,
    TenantCollectionOrder order = TenantCollectionOrder.documentId,
    Map<String, Object?> equalityFilters = const <String, Object?>{},
  }) async => _readPage(
    paths.customerSubcollectionPath(customerId, subcollection),
    collectionReader: collectionReader,
    pageSize: pageSize,
    cursor: cursor,
    descending: descending,
    order: order,
    equalityFilters: equalityFilters,
  );

  Future<TenantDocumentPage> readProductSubcollectionPage(
    TenantProductSubcollection subcollection, {
    required String productId,
    required TenantCollectionReader collectionReader,
    int pageSize = 20,
    String? cursor,
    bool descending = false,
    TenantCollectionOrder order = TenantCollectionOrder.documentId,
    Map<String, Object?> equalityFilters = const <String, Object?>{},
  }) async => _readPage(
    paths.productSubcollectionPath(productId, subcollection),
    collectionReader: collectionReader,
    pageSize: pageSize,
    cursor: cursor,
    descending: descending,
    order: order,
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
    bool descending = false,
    TenantCollectionOrder order = TenantCollectionOrder.documentId,
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
    // The resource path alone for a path-ordered page, an instant and the path
    // for a time-ordered one - the same pair a single-collection page carries,
    // over the whole path because that is what `__name__` orders in a group.
    final String? validatedCursor;
    final DateTime? cursorOrderValue;
    if (cursor == null) {
      validatedCursor = null;
      cursorOrderValue = null;
    } else if (order.isByDocumentId) {
      validatedCursor = _validatedGroupCursor(cursor, subcollection);
      cursorOrderValue = null;
    } else {
      final decoded = TenantPageCursor.decode(cursor);
      validatedCursor = _validatedGroupCursor(decoded.document, subcollection);
      cursorOrderValue = decoded.at;
    }
    final requestedLimit = pageSize + 1;
    final snapshots = await groupReader.getCollectionGroupPage(
      TenantCollectionGroupQuery._(
        collectionId: subcollection.segment,
        limit: requestedLimit,
        startAfterDocumentPath: validatedCursor,
        startAfterOrderValue: cursorOrderValue,
        descending: descending,
        order: order,
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
    DateTime? previousOrderValue;
    for (final snapshot in snapshots) {
      _requireGroupChildPath(snapshot.path, subcollection);
      if (!seenPaths.add(snapshot.path)) {
        throw TenantScopeViolation(
          'The group reader returned duplicate document ${snapshot.path}.',
        );
      }
      final orderValue = order.isByDocumentId
          ? null
          : _requireOrderValue(snapshot, order);
      if (previousPath != null) {
        // The field first and the path second, which is the order Firestore
        // itself applies. `compareDocumentPaths` rather than a string compare,
        // for the reason it documents.
        var comparison = 0;
        if (previousOrderValue != null && orderValue != null) {
          comparison = previousOrderValue.compareTo(orderValue);
        }
        if (comparison == 0) {
          comparison = compareDocumentPaths(previousPath, snapshot.path);
        }
        if (comparison * (descending ? -1 : 1) >= 0) {
          throw TenantScopeViolation(
            order.isByDocumentId
                ? 'Collection group results were not ordered by document path.'
                : 'Collection group results were not ordered by '
                      '${order.field}.',
          );
        }
      }
      previousPath = snapshot.path;
      previousOrderValue = orderValue;
    }

    final hasMore = snapshots.length > pageSize;
    final items = hasMore ? snapshots.take(pageSize).toList() : snapshots;
    return TenantDocumentGroupPage(
      items: items,
      nextCursor: !hasMore
          ? null
          : order.isByDocumentId
          ? items.last.path
          : TenantPageCursor(
              at: _requireOrderValue(items.last, order),
              document: items.last.path,
            ).encode(),
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

  /// The ordering field of one returned document, as an instant.
  ///
  /// **A document that does not carry it is a broken page, not a row to sort
  /// last.** Firestore excludes such a document from an ordered query
  /// altogether, so one arriving here means the reader ignored the ordering -
  /// and a page that quietly dropped records would be the worst possible answer
  /// to "what happened most recently".
  static DateTime _requireOrderValue(
    TenantQueryDocumentSnapshot snapshot,
    TenantCollectionOrder order,
  ) {
    final value = tenantStoredInstant(snapshot.data[order.field]);
    if (value == null) {
      throw TenantScopeViolation(
        'A document ordered by ${order.field} does not carry it as an instant: '
        '${snapshot.path}.',
      );
    }
    return value;
  }

  /// Orders two page keys the way Firestore orders a field then `__name__`.
  static int _comparePageKeys(
    DateTime? leftValue,
    String leftDocument,
    DateTime? rightValue,
    String rightDocument,
  ) {
    if (leftValue != null && rightValue != null) {
      final byValue = leftValue.compareTo(rightValue);
      if (byValue != 0) return byValue;
    }
    return leftDocument.compareTo(rightDocument);
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
    TenantCollectionOrder order = TenantCollectionOrder.documentId,
  }) async {
    if (pageSize < 1 || pageSize > 50) {
      throw RangeError.range(pageSize, 1, 50, 'pageSize');
    }
    final safeFilters = _validatedEqualityFilters(equalityFilters);
    // Firestore refuses a descending scan of a whole collection by key
    // ("Firestore does not support descending key scans"), so a newest-first
    // page must always be narrowed by at least one equality filter. A page
    // ordered by a *field* is exempt: that is an ordinary descending index
    // scan, which is the whole reason the time orderings exist.
    if (descending && order.isByDocumentId && safeFilters.isEmpty) {
      throw ArgumentError.value(
        descending,
        'descending',
        'A descending page requires at least one equality filter.',
      );
    }
    // A page ordered by document ID resumes after an ID; a time-ordered one
    // resumes after an instant *and* an ID, because two records written in the
    // same millisecond are separated only by the second. Both arrive here as
    // the one opaque string every paginated surface passes around.
    final String? validatedCursor;
    final DateTime? cursorOrderValue;
    if (cursor == null) {
      validatedCursor = null;
      cursorOrderValue = null;
    } else if (order.isByDocumentId) {
      validatedCursor = validateTenantDocumentId(cursor, fieldName: 'cursor');
      cursorOrderValue = null;
    } else {
      final decoded = TenantPageCursor.decode(cursor);
      validatedCursor = validateTenantDocumentId(
        decoded.document,
        fieldName: 'cursor',
      );
      cursorOrderValue = decoded.at;
    }
    final requestedLimit = pageSize + 1;
    final snapshots = await collectionReader.getCollectionPage(
      TenantCollectionQuery._(
        collectionPath: expectedCollectionPath,
        limit: requestedLimit,
        startAfterDocumentId: validatedCursor,
        startAfterOrderValue: cursorOrderValue,
        descending: descending,
        order: order,
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
    DateTime? previousOrderValue;
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
      // **The proof did not weaken; it took a second component.** For a page
      // ordered by document ID it is exactly what it always was. For a
      // time-ordered one it is the pair Firestore itself orders by - the field,
      // then the ID - so a reader that returned the right documents in the
      // wrong order is still caught, and so is one that ignored the ordering
      // and answered by key.
      final orderValue = order.isByDocumentId
          ? null
          : _requireOrderValue(snapshot, order);
      final ordered =
          previousId == null ||
          _comparePageKeys(
                    previousOrderValue,
                    previousId,
                    orderValue,
                    documentId,
                  ) *
                  (descending ? -1 : 1) <
              0;
      if (!ordered) {
        throw TenantScopeViolation(
          order.isByDocumentId
              ? 'Collection results were not ordered by document ID.'
              : 'Collection results were not ordered by ${order.field}.',
        );
      }
      previousId = documentId;
      previousOrderValue = orderValue;
    }

    final hasMore = snapshots.length > pageSize;
    final items = hasMore ? snapshots.take(pageSize).toList() : snapshots;
    final String? nextCursor;
    if (!hasMore) {
      nextCursor = null;
    } else {
      final lastId = items.last.path.substring(
        '$expectedCollectionPath/'.length,
      );
      nextCursor = order.isByDocumentId
          ? lastId
          : TenantPageCursor(
              at: _requireOrderValue(items.last, order),
              document: lastId,
            ).encode();
    }
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
