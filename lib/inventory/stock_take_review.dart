/// Counts as management reads them, and the act of applying one.
///
/// **Everything here is on the other side of the control.** The counting screen
/// shows no expected figure because the count must be blind; this shows nothing
/// but figures, because reviewing one is exactly the act of comparing them. The
/// two surfaces have different audiences and `firestore.rules` enforces the
/// difference - a counter may read that they counted, and only
/// owner/admin/manager may read the lines under it.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../tenancy/tenancy.dart';

/// How far a count has got.
enum TenantStockTakeStatus {
  /// Some pages have landed and the rest are still in somebody's outbox.
  ///
  /// A real state, not an error: it means the device that counted has not
  /// finished sending. Applying one would correct only the part that arrived,
  /// so the server refuses it.
  submitting,

  /// Every page has landed. This is what a count waiting for review looks like.
  submitted,

  /// The variances have been written to the stock ledger.
  applied,
}

TenantStockTakeStatus _statusOf(Object? raw) => switch (raw) {
  'submitted' => TenantStockTakeStatus.submitted,
  'applied' => TenantStockTakeStatus.applied,
  // Anything unrecognised reads as still arriving, which is the state that
  // refuses to be applied. Failing towards "do not touch the books" is the only
  // safe direction for a value this surface did not write.
  _ => TenantStockTakeStatus.submitting,
};

int _intOf(Object? raw) => raw is int ? raw : 0;

/// One count, as the review list draws it.
final class TenantStockTakeRecord {
  const TenantStockTakeRecord({
    required this.id,
    required this.counterUid,
    required this.businessDate,
    required this.status,
    required this.productsInScope,
    required this.countedLineCount,
    required this.varianceLineCount,
    required this.absoluteVarianceUnits,
    required this.unmatchedLineCount,
    required this.categoryId,
    required this.submittedAt,
  });

  factory TenantStockTakeRecord.fromSnapshot(
    TenantQueryDocumentSnapshot snapshot,
  ) {
    final data = snapshot.data;
    final scope = data['scope'];
    final submittedAt = data['submittedAt'];
    return TenantStockTakeRecord(
      id: snapshot.path.split('/').last,
      counterUid: data['counterUid'] is String
          ? data['counterUid']! as String
          : '',
      businessDate: data['businessDate'] is String
          ? data['businessDate']! as String
          : '',
      status: _statusOf(data['status']),
      productsInScope: _intOf(data['productsInScope']),
      countedLineCount: _intOf(data['countedLineCount']),
      varianceLineCount: _intOf(data['varianceLineCount']),
      absoluteVarianceUnits: _intOf(data['absoluteVarianceUnits']),
      unmatchedLineCount: _intOf(data['unmatchedLineCount']),
      categoryId: scope is Map && scope['kind'] == 'category'
          ? scope['categoryId'] as String?
          : null,
      submittedAt: submittedAt is Timestamp ? submittedAt.toDate() : null,
    );
  }

  final String id;
  final String counterUid;
  final String businessDate;
  final TenantStockTakeStatus status;
  final int productsInScope;
  final int countedLineCount;
  final int varianceLineCount;
  final int absoluteVarianceUnits;

  /// Lines naming a product this business does not hold.
  ///
  /// Usually because the product was added on a device with no connection and
  /// the count reached the server first. It resolves itself when the create
  /// drains; until then the line records what was counted and nothing else.
  final int unmatchedLineCount;

  /// The category counted, or null for the whole catalog.
  final String? categoryId;
  final DateTime? submittedAt;

  /// Products in scope that nobody wrote a number against.
  ///
  /// **Not a variance.** Nothing is known about these one way or the other, and
  /// saying otherwise would be inventing a fact about a shelf nobody looked at.
  int get uncountedLineCount {
    final uncounted = productsInScope - countedLineCount;
    return uncounted > 0 ? uncounted : 0;
  }

  bool get canApply =>
      status == TenantStockTakeStatus.submitted && varianceLineCount > 0;
}

/// One counted product, with both figures.
final class TenantStockTakeLineRecord {
  const TenantStockTakeLineRecord({
    required this.productId,
    required this.counted,
    required this.expected,
    required this.variance,
    required this.seenQuantity,
    required this.matched,
    required this.appliedAdjustmentId,
    required this.countedAt,
  });

  factory TenantStockTakeLineRecord.fromSnapshot(
    TenantQueryDocumentSnapshot snapshot,
  ) {
    final data = snapshot.data;
    final countedAt = data['countedAt'];
    return TenantStockTakeLineRecord(
      productId: snapshot.path.split('/').last,
      counted: _intOf(data['counted']),
      expected: data['expected'] is int ? data['expected']! as int : null,
      variance: data['variance'] is int ? data['variance']! as int : null,
      seenQuantity: data['seenQuantity'] is int
          ? data['seenQuantity']! as int
          : null,
      matched: data['matched'] == true,
      appliedAdjustmentId: data['appliedAdjustmentId'] is String
          ? data['appliedAdjustmentId']! as String
          : null,
      countedAt: countedAt is String ? DateTime.tryParse(countedAt) : null,
    );
  }

  final String productId;
  final int counted;

  /// What the server held when the count was submitted. Null when the product
  /// was not matched.
  final int? expected;
  final int? variance;

  /// What the counting device believed at the moment the number was typed.
  ///
  /// **Read this against [expected] when a variance looks wrong.** They differ
  /// exactly when the books moved between counting and submitting - a sale in
  /// the gap, most often - which is the difference between a shortfall and a
  /// count taken during trading.
  final int? seenQuantity;
  final bool matched;
  final String? appliedAdjustmentId;
  final DateTime? countedAt;

  bool get isApplied => appliedAdjustmentId != null;

  /// Whether the books moved between the count being taken and it arriving.
  bool get movedWhileCounting =>
      matched && seenQuantity != null && seenQuantity != expected;
}

/// Guarded reads of this business's counts.
final class TenantStockTakeReviewRepository extends TenantReadRepository {
  TenantStockTakeReviewRepository({required super.session, required super.reader});

  /// Who may look at a count and the lines under it.
  ///
  /// Owner, administrator and manager - the set that reads `stock_adjustments`
  /// and the set that may apply one, because reviewing a count and correcting
  /// the books from it are the same job.
  static const List<TenantRole> allowedRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
    TenantRole.manager,
  ];

  static const int defaultPageSize = 20;

  /// Counts, newest first.
  ///
  /// **Newest-first comes from the document ID**, which carries the business
  /// date - see `tenantStockTakeId`. These repositories page by document ID and
  /// by nothing else, so a take whose ID were a bare digest could only be listed
  /// in an arbitrary order, exactly as the `stock_adjustments` feed is.
  ///
  /// The tenant filter is not redundant: Firestore refuses a descending key scan
  /// of a whole collection, so a newest-first page must be narrowed by at least
  /// one equality filter, and every take carries its own `tenantId`.
  Future<TenantDocumentPage> loadTakePage({
    required TenantCollectionReader collectionReader,
    int pageSize = defaultPageSize,
    String? cursor,
  }) => readCollectionPage(
    TenantCollection.stockTakes,
    collectionReader: collectionReader,
    pageSize: pageSize,
    cursor: cursor,
    descending: true,
    equalityFilters: <String, Object?>{'tenantId': session.tenantId},
  );

  /// Counts, newest first, as records.
  Future<List<TenantStockTakeRecord>> loadTakes({
    required TenantCollectionReader collectionReader,
    int pageSize = defaultPageSize,
    String? cursor,
  }) async {
    final page = await loadTakePage(
      collectionReader: collectionReader,
      pageSize: pageSize,
      cursor: cursor,
    );
    return page.items.map(TenantStockTakeRecord.fromSnapshot).toList();
  }

  /// The lines of one count that differ from the books.
  ///
  /// **Only the differing ones, deliberately.** A count of four hundred products
  /// where six disagree is a report about six products; listing the other three
  /// hundred and ninety-four would bury them. How many agreed is on the take
  /// itself, so nothing is hidden by leaving them out.
  Future<TenantDocumentPage> loadVarianceLinePage(
    String takeId, {
    required TenantCollectionReader collectionReader,
    int pageSize = defaultPageSize,
    String? cursor,
  }) => readStockTakeSubcollectionPage(
    TenantStockTakeSubcollection.lines,
    takeId: takeId,
    collectionReader: collectionReader,
    pageSize: pageSize,
    cursor: cursor,
    equalityFilters: const <String, Object?>{'needsApply': true},
  );

  /// The differing lines of one count, as records.
  Future<List<TenantStockTakeLineRecord>> loadVarianceLines(
    String takeId, {
    required TenantCollectionReader collectionReader,
    int pageSize = defaultPageSize,
    String? cursor,
  }) async {
    final page = await loadVarianceLinePage(
      takeId,
      collectionReader: collectionReader,
      pageSize: pageSize,
      cursor: cursor,
    );
    return page.items.map(TenantStockTakeLineRecord.fromSnapshot).toList();
  }
}

/// Resolves the names of the products a count's lines name.
///
/// **A line carries no product name, and should not.** It is keyed by the
/// product ID and the name belongs to the product: freezing a copy into every
/// line would make a renamed product read under two names depending on which
/// count you opened. So the review screen reads the products its lines name,
/// bounded the way `TenantStaffNameResolver` bounds a page of UIDs - a document
/// per row is the cost of a label, so it is capped and the remainder falls back
/// to the ID.
final class TenantStockTakeProductNames extends TenantReadRepository {
  TenantStockTakeProductNames({required super.session, required super.reader});

  /// The most products one page resolves. A review page is twenty lines.
  static const int maximumResolved = 25;

  final Map<String, String?> _cache = <String, String?>{};

  Future<Map<String, String>> resolve(Iterable<String> productIds) async {
    final requested = <String>{};
    for (final productId in productIds) {
      try {
        requested.add(validateTenantDocumentId(productId, fieldName: 'productId'));
      } on ArgumentError {
        continue;
      }
    }

    var lookups = 0;
    for (final productId in requested) {
      if (_cache.containsKey(productId)) continue;
      if (lookups >= maximumResolved) break;
      lookups++;
      _cache[productId] = await _readName(productId);
    }

    return <String, String>{
      for (final productId in requested)
        if (_cache[productId] case final name?) productId: name,
    };
  }

  Future<String?> _readName(String productId) async {
    final Map<String, Object?>? data;
    try {
      data = await readDocument(TenantCollection.products, productId);
    } on TenantScopeViolation {
      rethrow;
    } catch (_) {
      // A product a count names may genuinely not be there - the unmatched case
      // `submitStockTake` records rather than refuses. The caller falls back to
      // the ID, which is the only thing that is certainly true about it.
      return null;
    }
    final name = data?['name'];
    if (name is! String) return null;
    final trimmed = name.trim();
    return trimmed.isEmpty || trimmed.length > 120 ? null : trimmed;
  }
}

/// Applies one page of a count's corrections.
abstract interface class ApplyStockTakeCallable {
  Future<Object?> call(Map<String, Object?> payload);
}

/// Firebase adapter for `applyStockTake`.
final class FirebaseApplyStockTakeCallable implements ApplyStockTakeCallable {
  FirebaseApplyStockTakeCallable({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    final result = await _functions
        .httpsCallable('applyStockTake')
        .call<Object?>(payload);
    return result.data;
  }
}

/// Why applying a count did not correct the books.
enum TenantStockTakeApplyFailure {
  /// The session may not move stock, or its membership ended.
  forbidden,

  /// The count has not finished arriving, so applying it would correct only
  /// the part that has.
  stillArriving,

  /// The count is gone, or was never on this server.
  missing,

  /// A product's stored quantity is not a whole number, so nothing can be
  /// added to it. Only reconciliation can settle that.
  invalidStoredQuantity,

  /// The correction was refused for a reason this client does not model.
  refused,

  /// The call did not complete, so some of the count may have been applied.
  ambiguous,
}

final class TenantStockTakeApplyException implements Exception {
  const TenantStockTakeApplyException(this.failure);

  final TenantStockTakeApplyFailure failure;

  @override
  String toString() => 'TenantStockTakeApplyException(${failure.name})';
}

/// What applying a whole count did.
final class TenantStockTakeApplyOutcome {
  const TenantStockTakeApplyOutcome({required this.applied});

  /// Lines corrected, across every page.
  final int applied;
}

/// Applies every page of one count, in order, until the server says it is done.
///
/// **Looping here rather than on the server** is what keeps each call inside one
/// Firestore transaction. Each page is idempotent on the cursor it started from
/// and each line is skipped once it carries an adjustment, so an interrupted
/// loop is resumed by running it again - it cannot move the same units twice.
Future<TenantStockTakeApplyOutcome> applyWholeStockTake({
  required ApplyStockTakeCallable callable,
  required String tenantId,
  required String takeId,
}) async {
  var applied = 0;
  String? cursor;
  // Bounded so a server that kept returning a cursor could not spin here for
  // ever. One page is a third of a submission page, so this covers a catalog
  // far larger than the till can hold.
  for (var page = 0; page < 500; page++) {
    final Object? raw;
    try {
      raw = await callable.call(<String, Object?>{
        'tenantId': tenantId,
        'takeId': takeId,
        if (cursor != null) 'cursor': cursor,
      });
    } on FirebaseFunctionsException catch (error) {
      throw TenantStockTakeApplyException(_failureOf(error, applied));
    } catch (_) {
      throw TenantStockTakeApplyException(
        applied > 0
            ? TenantStockTakeApplyFailure.ambiguous
            : TenantStockTakeApplyFailure.refused,
      );
    }
    final data = raw is Map ? raw : const <Object?, Object?>{};
    applied += data['applied'] is int ? data['applied']! as int : 0;
    final next = data['nextCursor'];
    if (next is! String || next.isEmpty) {
      return TenantStockTakeApplyOutcome(applied: applied);
    }
    cursor = next;
  }
  // Every page said there was another. Something is wrong on the server rather
  // than here, and the honest report is that part of it may have been applied.
  throw const TenantStockTakeApplyException(
    TenantStockTakeApplyFailure.ambiguous,
  );
}

TenantStockTakeApplyFailure _failureOf(
  FirebaseFunctionsException error,
  int appliedSoFar,
) {
  final message = error.message ?? '';
  return switch (error.code) {
    'permission-denied' || 'unauthenticated' =>
      TenantStockTakeApplyFailure.forbidden,
    'not-found' => TenantStockTakeApplyFailure.missing,
    'failed-precondition' when message.contains('not finished arriving') =>
      TenantStockTakeApplyFailure.stillArriving,
    'failed-precondition' => TenantStockTakeApplyFailure.invalidStoredQuantity,
    'deadline-exceeded' || 'unavailable' || 'aborted' || 'internal' =>
      TenantStockTakeApplyFailure.ambiguous,
    // A refusal partway through a loop has already corrected part of the count,
    // so it is never simply "nothing happened".
    _ => appliedSoFar > 0
        ? TenantStockTakeApplyFailure.ambiguous
        : TenantStockTakeApplyFailure.refused,
  };
}
