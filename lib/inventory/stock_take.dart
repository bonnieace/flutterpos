/// One stock take: what a person counted, before anybody decides what it means.
///
/// **A count moves no stock.** Everything here records an observation and
/// nothing corrects the books - that is a separate act, taken by somebody with
/// the standing to move a quantity, against a count they can see. The separation
/// is the control: if the person counting could also adjust, a shortfall could be
/// counted away by whoever caused it. It is also what lets a cashier do the
/// counting at all, which is the whole point of the feature.
///
/// **Counting happens on the floor, with no signal.** So a take lives in a
/// durable local draft while it is being entered - see `TenantStockTakeDraft` -
/// and reaches the server through the mutation outbox like every other queued
/// change. Nothing about the count depends on being online at the time.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../tenancy/tenancy.dart';

/// The most lines one page of a submission carries.
///
/// **Mirrors `MAXIMUM_STOCK_TAKE_LINES` on the server**, which is itself
/// `importProducts`' bound: one document per line inside one transaction is what
/// both paths do, so they are limited by the same thing. A page over this is
/// refused there, so splitting to it here is not a courtesy.
const int maximumStockTakeLinesPerPage = 50;

/// The largest number of units a line may be counted at.
///
/// Mirrors `MAXIMUM_IMPORT_OPENING_STOCK`. A figure over it is a typo, and the
/// server refuses it.
const int maximumStockTakeCount = 1000000;

/// What a count covered.
///
/// Two shapes rather than a nullable category, because "the whole catalog" and
/// "one category" are different statements about what was looked at - and a take
/// that covered everything is not a take of a category nobody named.
sealed class TenantStockTakeScope {
  const TenantStockTakeScope();

  /// Reads a scope back, refusing anything that is neither shape.
  factory TenantStockTakeScope.fromMap(Map<String, Object?> data) {
    final kind = data['kind'];
    if (kind == 'all') return const TenantStockTakeEverything();
    if (kind == 'category') {
      final categoryId = data['categoryId'];
      if (categoryId is String && categoryId.isNotEmpty) {
        return TenantStockTakeCategory(categoryId);
      }
    }
    throw const TenantStockTakeException(TenantStockTakeFailure.invalidScope);
  }

  Map<String, Object?> toMap();

  /// A stable, storable name for this scope.
  ///
  /// Used as the key a satisfied obligation is recorded under, so it must not
  /// change shape once anything has been written with it.
  String get scopeKey;
}

/// Every product the till can sell.
final class TenantStockTakeEverything extends TenantStockTakeScope {
  const TenantStockTakeEverything();

  @override
  Map<String, Object?> toMap() => const <String, Object?>{'kind': 'all'};

  @override
  String get scopeKey => 'all';

  @override
  bool operator ==(Object other) => other is TenantStockTakeEverything;

  @override
  int get hashCode => 'all'.hashCode;
}

/// One category of it, which is how a long catalog is split between people.
final class TenantStockTakeCategory extends TenantStockTakeScope {
  const TenantStockTakeCategory(this.categoryId);

  final String categoryId;

  @override
  Map<String, Object?> toMap() => <String, Object?>{
    'kind': 'category',
    'categoryId': categoryId,
  };

  @override
  String get scopeKey => 'category:$categoryId';

  @override
  bool operator ==(Object other) =>
      other is TenantStockTakeCategory && other.categoryId == categoryId;

  @override
  int get hashCode => Object.hash('category', categoryId);
}

/// What a device recorded against one product.
final class TenantStockTakeCount {
  const TenantStockTakeCount({
    required this.counted,
    required this.seenQuantity,
    required this.countedAt,
  });

  /// Units on the shelf. Zero is a real answer and means "I looked, there were
  /// none" - which is why a product nobody counted has no entry at all rather
  /// than an entry of zero.
  final int counted;

  /// What this device's catalog held when the number was typed.
  ///
  /// **Recorded, never shown.** The counter works blind: seeing the expected
  /// figure tells them what to write, which is most of what a blind count exists
  /// to prevent. This is here so the gap between counting and submitting can be
  /// read afterwards by somebody who is allowed to see both.
  final int? seenQuantity;

  /// When it was typed, by this device's clock.
  final DateTime countedAt;

  Map<String, Object?> toStorage() => <String, Object?>{
    'counted': counted,
    'seenQuantity': seenQuantity,
    'countedAt': countedAt.toUtc().toIso8601String(),
  };

  static TenantStockTakeCount fromStorage(Map<Object?, Object?> raw) {
    final counted = raw['counted'];
    final seen = raw['seenQuantity'];
    final at = raw['countedAt'];
    if (counted is! int || at is! String) {
      throw const TenantStockTakeException(
        TenantStockTakeFailure.draftUnreadable,
      );
    }
    final countedAt = DateTime.tryParse(at);
    if (countedAt == null) {
      throw const TenantStockTakeException(
        TenantStockTakeFailure.draftUnreadable,
      );
    }
    return TenantStockTakeCount(
      counted: counted,
      seenQuantity: seen is int ? seen : null,
      countedAt: countedAt,
    );
  }
}

/// A count in progress on this device.
///
/// **Durable before anything is sent, which is what makes paging safe.** The
/// take's ID is minted once, here, and the page a line falls in is positional -
/// so a submission interrupted halfway can be resumed by sending the pages again,
/// and every one of them lands on the documents it landed on before. That is the
/// trap the bulk import fell into by minting a request ID per page at the moment
/// it planned and holding the plan in memory.
final class TenantStockTakeDraft {
  const TenantStockTakeDraft({
    required this.takeId,
    required this.tenantId,
    required this.businessDate,
    required this.scope,
    required this.productsInScope,
    required this.startedAt,
    required this.counts,
  });

  final String takeId;
  final String tenantId;
  final String businessDate;
  final TenantStockTakeScope scope;

  /// How many products the list offered, which is not how many were counted.
  final int productsInScope;
  final DateTime startedAt;

  /// Counted products, by product ID. A product nobody typed a number against is
  /// absent, and stays absent all the way to the server.
  final Map<String, TenantStockTakeCount> counts;

  bool get isEmpty => counts.isEmpty;
  int get countedLineCount => counts.length;

  /// Records one number, replacing whatever this product last held.
  TenantStockTakeDraft withCount(
    String productId,
    TenantStockTakeCount count,
  ) => _copyWith(<String, TenantStockTakeCount>{...counts, productId: count});

  /// Takes a product back out, which is how a number typed by mistake is undone.
  ///
  /// Clearing the field must remove the entry rather than store zero, or a
  /// product nobody managed to count becomes a claim that the shelf was empty.
  TenantStockTakeDraft withoutCount(String productId) =>
      _copyWith(<String, TenantStockTakeCount>{...counts}..remove(productId));

  TenantStockTakeDraft _copyWith(Map<String, TenantStockTakeCount> next) =>
      TenantStockTakeDraft(
        takeId: takeId,
        tenantId: tenantId,
        businessDate: businessDate,
        scope: scope,
        productsInScope: productsInScope,
        startedAt: startedAt,
        counts: next,
      );

  Map<String, Object?> toStorage() => <String, Object?>{
    'takeId': takeId,
    'tenantId': tenantId,
    'businessDate': businessDate,
    'scope': scope.toMap(),
    'productsInScope': productsInScope,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'counts': <String, Object?>{
      for (final entry in counts.entries) entry.key: entry.value.toStorage(),
    },
  };

  static TenantStockTakeDraft fromStorage(Map<Object?, Object?> raw) {
    final takeId = raw['takeId'];
    final tenantId = raw['tenantId'];
    final businessDate = raw['businessDate'];
    final productsInScope = raw['productsInScope'];
    final startedAt = raw['startedAt'];
    final scope = raw['scope'];
    final counts = raw['counts'];
    if (takeId is! String ||
        tenantId is! String ||
        businessDate is! String ||
        productsInScope is! int ||
        startedAt is! String ||
        scope is! Map ||
        counts is! Map) {
      throw const TenantStockTakeException(
        TenantStockTakeFailure.draftUnreadable,
      );
    }
    final started = DateTime.tryParse(startedAt);
    if (started == null) {
      throw const TenantStockTakeException(
        TenantStockTakeFailure.draftUnreadable,
      );
    }
    return TenantStockTakeDraft(
      takeId: takeId,
      tenantId: tenantId,
      businessDate: businessDate,
      scope: TenantStockTakeScope.fromMap(
        Map<String, Object?>.from(scope.cast<String, Object?>()),
      ),
      productsInScope: productsInScope,
      startedAt: started,
      counts: <String, TenantStockTakeCount>{
        for (final entry in counts.entries)
          entry.key.toString(): TenantStockTakeCount.fromStorage(
            Map<Object?, Object?>.from(entry.value! as Map),
          ),
      },
    );
  }
}

/// One page of a submission, as the outbox carries it.
final class TenantStockTakePageIntent {
  const TenantStockTakePageIntent({
    required this.tenantId,
    required this.takeId,
    required this.businessDate,
    required this.scope,
    required this.productsInScope,
    required this.page,
    required this.isFinalPage,
    required this.lines,
  });

  final String tenantId;
  final String takeId;
  final String businessDate;
  final TenantStockTakeScope scope;
  final int productsInScope;
  final int page;
  final bool isFinalPage;

  /// Product ID to what was counted against it, in this page's order.
  final List<MapEntry<String, TenantStockTakeCount>> lines;

  /// The take, not any product counted in it.
  ///
  /// **Every page of one count shares this**, which is what keeps them in order:
  /// the outbox drains one target path strictly in sequence and different paths
  /// concurrently, so one person's pages queue behind each other and nobody
  /// else's count waits for them.
  String get path => 'tenants/$tenantId/stock_takes/$takeId';

  /// Distinct per page, because each is a separate durable record.
  String get operationId => 'stock-take-$takeId-$page';

  Map<String, Object?> payload() => <String, Object?>{
    'tenantId': tenantId,
    'takeId': takeId,
    'businessDate': businessDate,
    'scope': scope.toMap(),
    'productsInScope': productsInScope,
    'page': page,
    'isFinalPage': isFinalPage,
    'lines': <Map<String, Object?>>[
      for (final line in lines)
        <String, Object?>{
          'productId': line.key,
          'counted': line.value.counted,
          'seenQuantity': line.value.seenQuantity,
          'countedAt': line.value.countedAt.toUtc().toIso8601String(),
        },
    ],
  };
}

/// Splits a draft into the pages it will be sent as.
///
/// **Ordered by product ID, deterministically.** The server tolerates a line
/// arriving in a different page than last time - it keys lines by product and
/// counts each once - but a stable split means a resent submission is the same
/// submission, which is a far easier thing to reason about than one that merely
/// converges.
List<TenantStockTakePageIntent> tenantStockTakePages(
  TenantStockTakeDraft draft, {
  int pageSize = maximumStockTakeLinesPerPage,
}) {
  if (pageSize < 1 || pageSize > maximumStockTakeLinesPerPage) {
    throw const TenantStockTakeException(
      TenantStockTakeFailure.invalidPageSize,
    );
  }
  if (draft.counts.isEmpty) {
    throw const TenantStockTakeException(TenantStockTakeFailure.nothingCounted);
  }
  final ordered = draft.counts.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  final pages = <TenantStockTakePageIntent>[];
  for (var start = 0; start < ordered.length; start += pageSize) {
    final end = min(start + pageSize, ordered.length);
    pages.add(
      TenantStockTakePageIntent(
        tenantId: draft.tenantId,
        takeId: draft.takeId,
        businessDate: draft.businessDate,
        scope: draft.scope,
        productsInScope: draft.productsInScope,
        page: pages.length,
        isFinalPage: end == ordered.length,
        lines: ordered.sublist(start, end),
      ),
    );
  }
  return pages;
}

/// Reads a typed figure, refusing anything a shelf cannot have held.
///
/// Returns null for an empty field, which is *not* a count of zero: a blank line
/// is one nobody got to, and the difference has to survive all the way to the
/// server or an uncounted product becomes a claim that the shelf was empty.
int? tenantStockTakeCountOf(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final counted = int.tryParse(trimmed);
  if (counted == null || counted < 0 || counted > maximumStockTakeCount) {
    throw const TenantStockTakeException(TenantStockTakeFailure.invalidCount);
  }
  return counted;
}

/// A fresh request ID for one take, reused across every retry of it.
String secureTenantStockTakeRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'stocktake-${base64Url.encode(bytes).replaceAll('=', '')}';
}

/// Derives the take's permanent ID from the identity the count is scoped by.
///
/// The digest half is a product ID's, and for the same reason: it is the
/// idempotency key every page of the submission is recognised by, so it must be
/// stable across the retries of one count and different for a genuinely
/// different one.
///
/// **The business date is on the front of it, and that is load-bearing.** The
/// tenant repositories page by document ID and by nothing else - a deliberate
/// constraint, because the ordering proof is what stops a reader handing back
/// documents from somewhere else. A digest alone would make a review list
/// arbitrary, exactly as the `stock_adjustments` feed's own tests record of
/// `sa_` IDs. Putting the day first makes document order chronological, so
/// management reads newest-first through the primitive that already exists
/// rather than through a new sort field and a composite index.
String tenantStockTakeId({
  required String tenantId,
  required String counterUid,
  required String requestId,
  required String businessDate,
}) {
  final digest = sha256.convert(
    utf8.encode(
      <String>['stockTake', tenantId, counterUid, requestId].join(' '),
    ),
  );
  return 'st_${businessDate}_${digest.toString().substring(0, 40)}';
}

/// Why a count could not be recorded.
enum TenantStockTakeFailure {
  /// There is no session, or it may not count in this business.
  forbidden,

  /// The figure typed is not a whole, non-negative, bounded number.
  invalidCount,

  /// Nothing was counted, so there is nothing to send.
  nothingCounted,

  /// The draft on this device cannot be read back.
  draftUnreadable,

  /// The scope stored with a draft is neither shape.
  invalidScope,

  /// A page size outside what one transaction accepts.
  invalidPageSize,

  /// The count could not be stored on this device, so it was never queued and
  /// nothing anywhere recorded it.
  notRecorded,
}

final class TenantStockTakeException implements Exception {
  const TenantStockTakeException(this.failure);

  final TenantStockTakeFailure failure;

  @override
  String toString() => 'TenantStockTakeException(${failure.name})';
}

/// What queuing one page produced.
final class TenantStockTakeWriteResult {
  const TenantStockTakeWriteResult.queued(this.operationId);

  final String operationId;
}

/// Where a page of a count goes.
abstract interface class TenantStockTakeWriter {
  Future<TenantStockTakeWriteResult> submitPage(
    TenantStockTakePageIntent intent,
  );
}

/// The guarded boundary a count is handed in through.
///
/// The shape `TenantStockAdjustmentGateway` takes, and for the same reason: the
/// roles that may do a thing belong beside the thing, and the check happens
/// before anything is built rather than after something is sent.
final class TenantStockTakeGateway {
  const TenantStockTakeGateway(this.session);

  final TenantSession session;

  /// The roles that may take a count.
  ///
  /// **Every role, which is the widest list in this surface and the point of
  /// it.** Counting is the one inventory act a cashier performs, and it is safe
  /// to open because it moves no stock: the figures land as an observation and
  /// somebody with the standing to adjust decides what follows.
  /// `firestore.rules` and `submitStockTake` agree with this list.
  static const List<TenantRole> allowedRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
    TenantRole.manager,
    TenantRole.cashier,
  ];

  /// The pages this draft will be handed in as, refusing a session that may not.
  List<TenantStockTakePageIntent> pagesFor(
    TenantStockTakeDraft draft, {
    int pageSize = maximumStockTakeLinesPerPage,
  }) {
    if (!session.canAccess(allowedRoles: allowedRoles)) {
      throw const TenantStockTakeException(TenantStockTakeFailure.forbidden);
    }
    return tenantStockTakePages(draft, pageSize: pageSize);
  }
}
