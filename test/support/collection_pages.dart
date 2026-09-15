import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';

/// Answers a collection page the way Firestore would, out of a fixed list.
///
/// **Why a fake has to do this at all.** `TenantReadRepository` proves the order
/// of every page it is handed, and since 2026-09-14 that order can be a
/// timestamp field rather than the document ID - which is what makes the stock
/// ledger chronological. A double that answers one fixed list whatever it is
/// asked is no longer standing in for the transport: it is answering a query it
/// was not given, and the proof catches it, exactly as it would catch a real
/// reader that ignored the ordering.
///
/// So the ordering, the cursor and the equality filters are applied here, once,
/// rather than re-spelled in every fake that needs them.
List<TenantQueryDocumentSnapshot> tenantCollectionPageOf(
  TenantCollectionQuery query,
  List<TenantQueryDocumentSnapshot> documents,
) => _pageOf(
  documents: documents,
  order: query.order,
  descending: query.descending,
  limit: query.limit,
  equalityFilters: query.equalityFilters,
  cursorDocument: query.startAfterDocumentId,
  cursorValue: query.startAfterOrderValue,
  keyOf: (snapshot) => snapshot.path.split('/').last,
  compareKeys: (left, right) => left.compareTo(right),
);

/// The same, for a collection-group page - which orders by the whole resource
/// path rather than by a leaf document ID.
List<TenantQueryDocumentSnapshot> tenantCollectionGroupPageOf(
  TenantCollectionGroupQuery query,
  List<TenantQueryDocumentSnapshot> documents,
) => _pageOf(
  documents: documents,
  order: query.order,
  descending: query.descending,
  limit: query.limit,
  equalityFilters: query.equalityFilters,
  cursorDocument: query.startAfterDocumentPath,
  cursorValue: query.startAfterOrderValue,
  keyOf: (snapshot) => snapshot.path,
  compareKeys: TenantReadRepository.compareDocumentPaths,
);

List<TenantQueryDocumentSnapshot> _pageOf({
  required List<TenantQueryDocumentSnapshot> documents,
  required TenantCollectionOrder order,
  required bool descending,
  required int limit,
  required Map<String, Object?> equalityFilters,
  required String? cursorDocument,
  required DateTime? cursorValue,
  required String Function(TenantQueryDocumentSnapshot) keyOf,
  required int Function(String, String) compareKeys,
}) {
  DateTime? valueOf(TenantQueryDocumentSnapshot snapshot) {
    final field = order.field;
    if (field == null) return null;
    final value = snapshot.data[field];
    if (value is DateTime) return value.toUtc();
    if (value is Timestamp) return value.toDate().toUtc();
    return null;
  }

  int compare(
    TenantQueryDocumentSnapshot left,
    TenantQueryDocumentSnapshot right,
  ) {
    final leftValue = valueOf(left);
    final rightValue = valueOf(right);
    if (leftValue != null && rightValue != null) {
      final byValue = leftValue.compareTo(rightValue);
      if (byValue != 0) return descending ? -byValue : byValue;
    }
    final byKey = compareKeys(keyOf(left), keyOf(right));
    return descending ? -byKey : byKey;
  }

  final matching = <TenantQueryDocumentSnapshot>[
    for (final snapshot in documents)
      if (equalityFilters.entries.every(
        (filter) => snapshot.data[filter.key] == filter.value,
      ))
        snapshot,
  ]..sort(compare);

  if (cursorDocument == null) return matching.take(limit).toList();
  final at = matching.indexWhere((snapshot) {
    if (keyOf(snapshot) != cursorDocument) return false;
    if (cursorValue == null) return true;
    return valueOf(snapshot) == cursorValue;
  });
  final after = at < 0 ? matching : matching.skip(at + 1).toList();
  return after.take(limit).toList();
}
