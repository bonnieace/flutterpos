/// The record vocabulary the four stock surfaces state one ledger entry with.
///
/// The business-wide movement feed, the per-product ledger, and the stock route
/// render the same `stock_movements` documents, and the adjustment feed renders
/// the third record the same server transaction writes - so the wording lives
/// here rather than in any of them: two copies of "Before and after were not
/// recorded" is two chances to change one and not the other. They are in the
/// same domain and describe the same record, which is what makes sharing right
/// here and wrong between domains.
///
/// **It became a record model on 2026-08-13**, with `design.md` §11 step 6's
/// sweep. It used to hold four sentence builders and three screens each assembled
/// their own `Card` from them; §5.2 says a record is an identity, attributes, a
/// status, a provenance line and actions, so what is shared is now the whole
/// [RecordItem] and not only the strings inside it. The four screens differ in
/// what they can *do* to a record and in what identifies it on their own page -
/// which is what [stockMovementRecord]'s `subtitle` and `actions` are - and in
/// nothing else.
library;

import 'package:flutter/widgets.dart';

import '../tenancy/tenant_staff_names.dart';
import '../ui/record_list.dart';
import 'stock_adjustment_feed.dart';
import 'stock_movements.dart';

/// §5.2's attribute keys, declared once because four surfaces state them.
///
/// A label is a column header in [RecordForm.table] and the key half of a
/// key-value line on a card, so two screens spelling one fact differently is two
/// columns where a person expects one.
const String stockBeforeAndAfterLabel = 'Before and after';

/// The typed `adjustStock` category - `damage`, `restock`, `waste`.
///
/// **An attribute rather than part of the identity, and that is a decision this
/// sweep made.** The stock route used to fold it into the record's own title as
/// `Adjustment: damage` while the two feeds beside it said `Manual adjustment`
/// for the same document; a typed category is a fact *about* a record rather
/// than what the record is, so it is stated where the other facts are and all
/// three surfaces now agree. Nothing is lost and the two feeds gain it.
const String stockAdjustmentTypeLabel = 'Adjustment type';

const String stockReasonLabel = 'Reason';

/// The sale or return a movement came from.
const String stockSourceLabel = 'Source';

/// An unmodelled source has no label of its own, so the stored value is shown
/// rather than a guess at what it meant.
String stockMovementSourceLabel(TenantStockMovement movement) =>
    movement.source == TenantStockMovementSource.other
    ? movement.sourceType
    : movement.source.label;

/// Only the writers that read the product inside their own transaction record a
/// before and after. A reconciled sale carries neither, which this names rather
/// than filling in with a figure nobody recorded.
///
/// **The absent case is two words now rather than a sentence**, because the
/// sentence has become a key and a value: three surfaces each wrote their own
/// version of "the before and after were not recorded" and every one of them
/// repeated the label it now sits under.
String stockFiguresValue(int? previousQuantity, int? quantityAfter) =>
    previousQuantity == null
    ? 'Not recorded'
    : '$previousQuantity to $quantityAfter';

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

/// One ledger entry as §5.2's rows.
///
/// **No status, and that is the same decision the activity log made.** §2.1's
/// five statuses each mean exactly one thing and "stock moved" is not among
/// them; a ledger where every row wears a badge is a ledger with no signal in
/// it. The direction is carried by the sign on the delta, which is in the
/// identity - so it survives the arrow glyph that used to sit beside it, and it
/// was never held by colour alone.
///
/// [rowKey] is the caller's own record identifier, because one movement ID is
/// unique only below its own product: a sale of two items writes `sale_{saleId}`
/// under each. Every key this record carries is built from it and from
/// [keyPrefix], so a screen's tests address the same widgets they did before the
/// form change.
RecordItem stockMovementRecord(
  TenantStockMovement movement, {
  required String keyPrefix,
  required String rowKey,
  required Map<String, String> names,
  required String selfUid,
  String? subtitle,
  Key? subtitleKey,
  List<RecordAction> actions = const <RecordAction>[],
}) => RecordItem(
  id: rowKey,
  recordKey: ValueKey<String>('$keyPrefix-entry-$rowKey'),
  title:
      '${movement.increasesStock ? '+' : ''}${movement.quantityDelta} • '
      '${stockMovementSourceLabel(movement)}',
  titleKey: ValueKey<String>('$keyPrefix-delta-$rowKey'),
  subtitle: subtitle,
  subtitleKey: subtitleKey,
  attributes: <RecordAttribute>[
    RecordAttribute(
      label: stockBeforeAndAfterLabel,
      value: stockFiguresValue(
        movement.previousQuantity,
        movement.quantityAfter,
      ),
      valueKey: ValueKey<String>('$keyPrefix-figures-$rowKey'),
    ),
    if (movement.adjustmentType case final adjustmentType?)
      RecordAttribute(
        label: stockAdjustmentTypeLabel,
        value: adjustmentType,
        valueKey: ValueKey<String>('$keyPrefix-adjustment-type-$rowKey'),
      ),
    // **Twice an ordinary column**, for the reason the catalog's barcode is: a
    // reason is free text a person wrote at a till and is the longest thing on
    // any of these four screens, where a quantity is two characters.
    if (movement.reason case final reason?)
      RecordAttribute(
        label: stockReasonLabel,
        value: reason,
        valueKey: ValueKey<String>('$keyPrefix-reason-$rowKey'),
        flex: 2,
      ),
    // **Both, where a record carries both.** The two feeds used to show a reason
    // *or* a source and the stock route showed both; a table has one column per
    // label, so precedence would file one document under different columns
    // depending on which screen drew it.
    //
    // An ordinary share, unlike the reason above it: a source is a checkout or
    // return ID and is four or five characters. It took twice a column by
    // symmetry with the reason in the first draft, and the first render is what
    // said so - the identity column beside it is the one short of width.
    if (movement.sourceId case final sourceId?)
      RecordAttribute(
        label: stockSourceLabel,
        value: sourceId,
        valueKey: ValueKey<String>('$keyPrefix-source-$rowKey'),
      ),
  ],
  provenance: stockMovementRecordedLabel(
    movement,
    stockMovementActorLabel(movement, names: names, selfUid: selfUid),
  ),
  provenanceKey: ValueKey<String>('$keyPrefix-recorded-$rowKey'),
  actions: actions,
);

/// One manual correction as §5.2's rows.
///
/// The same transaction writes this record and the movement above it, so it is
/// stated in the same words: the delta and the category identify it, the figures
/// and the reason are its attributes, and who recorded it is provenance. What it
/// does not share is the *type* vocabulary - an adjustment record carries a
/// modelled [TenantStockAdjustmentType] where a movement carries the raw string
/// its writer stored - so the label is resolved here and the raw value is shown
/// when this client does not model it.
RecordItem stockAdjustmentRecord(
  TenantStockAdjustmentRecord record, {
  required String keyPrefix,
  required Map<String, String> names,
  required String selfUid,
}) => RecordItem(
  id: record.id,
  recordKey: ValueKey<String>('$keyPrefix-entry-${record.id}'),
  title:
      '${record.increasesStock ? '+' : ''}${record.quantityDelta} • '
      '${stockAdjustmentTypeName(record)}',
  titleKey: ValueKey<String>('$keyPrefix-delta-${record.id}'),
  subtitle: 'Product ${record.productId}',
  subtitleKey: ValueKey<String>('$keyPrefix-product-${record.id}'),
  attributes: <RecordAttribute>[
    RecordAttribute(
      label: stockBeforeAndAfterLabel,
      value: stockFiguresValue(record.previousQuantity, record.quantityAfter),
      valueKey: ValueKey<String>('$keyPrefix-figures-${record.id}'),
    ),
    RecordAttribute(
      label: stockReasonLabel,
      value: record.reason,
      valueKey: ValueKey<String>('$keyPrefix-reason-${record.id}'),
      flex: 2,
    ),
  ],
  provenance: stockAdjustmentRecordedLabel(
    record,
    tenantStaffLabel(record.actorUid, names: names, selfUid: selfUid),
  ),
  provenanceKey: ValueKey<String>('$keyPrefix-recorded-${record.id}'),
);

/// An unmodelled category is shown as itself: a server deploy adding one is not
/// evidence of anything wrong, and hiding the row would hide a real correction.
String stockAdjustmentTypeName(TenantStockAdjustmentRecord record) =>
    record.type?.label ?? record.adjustmentType;

String stockAdjustmentRecordedLabel(
  TenantStockAdjustmentRecord record,
  String actorLabel,
) {
  final recordedAt = record.recordedAt;
  final when = recordedAt == null
      ? 'Recorded instant unavailable'
      : 'Recorded ${stockMovementInstant(recordedAt)}';
  return '$when by $actorLabel';
}
