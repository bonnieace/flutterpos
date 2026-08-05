/// The sentences both movement surfaces describe one ledger entry with.
///
/// The business-wide feed and the per-product ledger render the same documents,
/// so the wording lives here rather than in either of them: two copies of
/// "Before and after were not recorded" is two chances to change one and not
/// the other. They are in the same domain and describe the same record, which
/// is what makes sharing right here and wrong between domains.
library;

import '../tenancy/tenant_staff_names.dart';
import 'stock_movements.dart';

/// An unmodelled source has no label of its own, so the stored value is shown
/// rather than a guess at what it meant.
String stockMovementSourceLabel(TenantStockMovement movement) =>
    movement.source == TenantStockMovementSource.other
    ? movement.sourceType
    : movement.source.label;

/// Only the writers that read the product inside their own transaction record a
/// before and after. A reconciled sale carries neither, which this names rather
/// than filling in with a figure nobody recorded.
String stockMovementFiguresLabel(TenantStockMovement movement) {
  final previousQuantity = movement.previousQuantity;
  if (previousQuantity == null) return 'Before and after were not recorded';
  return '$previousQuantity to ${movement.quantityAfter}';
}

String? stockMovementDetailLabel(TenantStockMovement movement) {
  if (movement.reason case final reason?) return 'Reason: $reason';
  if (movement.sourceId case final sourceId?) return 'From $sourceId';
  return null;
}

/// Nightly reconciliation writes a sale's movement, so it names no member of
/// the business. Attributing it to a missing colleague would be a fiction.
String stockMovementActorLabel(
  TenantStockMovement movement, {
  required Map<String, String> names,
  required String selfUid,
}) {
  final actorUid = movement.actorUid;
  if (actorUid == null) return 'the server';
  return tenantStaffLabel(actorUid, names: names, selfUid: selfUid);
}

String stockMovementRecordedLabel(
  TenantStockMovement movement,
  String actorLabel,
) {
  final recordedAt = movement.recordedAt ?? movement.occurredAt;
  final when = recordedAt == null
      ? 'Recorded instant unavailable'
      : 'Recorded ${stockMovementInstant(recordedAt)}';
  return '$when by $actorLabel';
}

String stockMovementInstant(DateTime value) {
  final utc = value.toUtc();
  String pad(int part) => part.toString().padLeft(2, '0');
  return '${utc.year}-${pad(utc.month)}-${pad(utc.day)} '
      '${pad(utc.hour)}:${pad(utc.minute)} UTC';
}
