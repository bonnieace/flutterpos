/// One page of an instant-ordered period read, for any tenant collection whose
/// documents carry `createdAt`.
///
/// **The proof `TenantAuditLogRepository.loadRecordedRange` makes, for any such
/// collection**: every row is a direct child of the collection asked for, none
/// is repeated, and each carries an instant inside the window - a row without
/// one was never in the index this asked of, and putting it in a period it
/// cannot claim would be an invention.
library;

import 'tenant_repository.dart';

Future<
  ({List<TenantQueryDocumentSnapshot> items, TenantInstantRangePosition? next})
>
tenantInstantRangePage({
  required TenantCollectionReader reader,
  required String collectionPath,
  required DateTime startAt,
  required DateTime endAt,
  required int pageSize,
  TenantInstantRangePosition? startAfter,
}) async {
  if (pageSize < 1 || pageSize > 50) {
    throw RangeError.range(pageSize, 1, 50, 'pageSize');
  }
  if (startAt.isAfter(endAt)) {
    throw ArgumentError.value(startAt, 'startAt', 'Must not follow endAt.');
  }
  final Object candidate = reader;
  if (candidate is! TenantReportRangeReader) {
    throw StateError('This reader cannot read a period.');
  }
  final requested = pageSize + 1;
  final snapshots = await candidate.queryTenantInstantRange(
    TenantInstantRangeQuery.scoped(
      collectionPath: collectionPath,
      limit: requested,
      startAt: startAt.toUtc(),
      endAt: endAt.toUtc(),
      startAfter: startAfter,
    ),
  );
  if (snapshots.length > requested) {
    throw const TenantScopeViolation(
      'A period read returned more documents than requested.',
    );
  }
  final items = <TenantQueryDocumentSnapshot>[];
  final seen = <String>{};
  for (final snapshot in snapshots) {
    if (!snapshot.path.startsWith('$collectionPath/') ||
        snapshot.path.substring(collectionPath.length + 1).contains('/')) {
      throw TenantScopeViolation(
        'A period read escaped $collectionPath with ${snapshot.path}.',
      );
    }
    if (!seen.add(snapshot.path)) {
      throw const TenantScopeViolation(
        'A period read returned a duplicate document.',
      );
    }
    // Ordered by the instant, so every row must carry one inside the window;
    // a row without one was never in the index this asked of.
    final at = tenantStoredInstant(snapshot.data['createdAt']);
    if (at == null ||
        at.isBefore(startAt.toUtc()) ||
        at.isAfter(endAt.toUtc())) {
      throw const TenantScopeViolation(
        'A period read returned a document outside its window.',
      );
    }
    items.add(snapshot);
  }
  final hasMore = items.length > pageSize;
  final visible = hasMore ? items.take(pageSize).toList() : items;
  return (
    items: visible,
    next: hasMore
        ? TenantInstantRangePosition(
            at: tenantStoredInstant(visible.last.data['createdAt'])!,
            documentId: visible.last.path.split('/').last,
          )
        : null,
  );
}

