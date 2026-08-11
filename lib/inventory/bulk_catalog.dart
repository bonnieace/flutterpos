import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';

import '../checkout/checkout_draft.dart';
import '../tenancy/tenant_catalog.dart';
import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_types.dart';
import 'catalog_management.dart';

/// Correcting many products at once, and creating many from a spreadsheet.
///
/// Two callables, one surface, and that is a decision rather than a
/// convenience: `updateProducts` and `importProducts` want the same four things
/// - hold rows, ask what they would do, read a per-row report, then commit -
/// and building either against its own screen would design the preview twice.
///
/// Four properties are forced by the server rather than chosen here, and every
/// one of them shows through into this file:
///
/// - **A page is fifty rows and the caller chains.** There is no server-side
///   cursor because there is no server-side collection to walk: this side holds
///   the rows. Four hundred rows is eight previews and then eight commits.
/// - **A page keeps one request ID across its own preview and its own commit.**
///   That is exactly what the server's decision to write no idempotency record
///   for a preview exists to allow, and it is why a page is immutable once
///   built: order is part of the request fingerprint, so a commit whose rows
///   moved between the preview and the commit is refused as `already-exists`
///   rather than quietly applied as something other than what was shown.
/// - **The per-row report is the product, not a byproduct.** The server names
///   every broken row at once; a surface that collapsed that into "12 rows
///   failed" would throw away the reason the callables report per row at all.
/// - **The two callables authorize differently and both rules must be
///   honoured.** A correction naming a price or a cost *anywhere* refuses the
///   whole request for a manager, so those corrections are not offered to one.
///   An import may take a price from a manager - setting a first price is
///   creation, and the add-product form beside it already accepts one - and must
///   still refuse a cost. Two rules, one screen.
///
/// What this file deliberately does not do is decide what a product may hold.
/// Every row is normalized and priced through the catalog surface's own helpers
/// - [tenantCatalogNormalizedName], [tenantCatalogNormalizedSku],
/// [tenantCatalogPriceMinorUnits] - so a product created by an import, created
/// by the add-product form, and corrected one at a time cannot differ in what
/// this client will write.

/// The most rows one request carries, matching the server's
/// `MAXIMUM_PRODUCT_BATCH_ROWS` and `MAXIMUM_PRODUCT_IMPORT_ROWS`.
///
/// One constant for both callables because the server chose one figure for both,
/// and for the reason it gave: two different page sizes on one screen would be a
/// trap. A request carrying more is refused by the server outright rather than
/// truncated, so this side never sends one.
const int maximumBulkCatalogRows = 50;

/// The most rows one pasted sheet may describe, which bounds the chain.
///
/// The server bounds a request; nothing bounds how many requests a client will
/// make, and a pasted ten-thousand-row sheet is two hundred sequential round
/// trips nobody can watch finish. Ten pages is a chain a person can see the end
/// of, and a larger sheet is split by whoever pasted it - which also gives them
/// ten smaller reports instead of one nobody reads.
const int maximumBulkCatalogSheetRows = maximumBulkCatalogRows * 10;

/// The largest opening balance one imported row may carry, matching the server's
/// `MAXIMUM_IMPORT_OPENING_STOCK`.
///
/// The same bound `adjustStock` puts on a single adjustment, because an imported
/// unit and an adjusted unit are the same unit recorded through the same ledger.
const int maximumBulkOpeningQuantity = 1000000;

/// Whether a request is asking what would happen or asking for it to happen.
///
/// There is no default, on this side either. The server refuses a payload that
/// omits the mode rather than assuming a preview, and the reason is worth
/// repeating where the payload is built: a preview mistaken for a commit is a
/// report nobody acts on, and a commit mistaken for a preview changes four
/// hundred products nobody agreed to.
enum TenantBulkCatalogMode {
  preview,
  commit;

  String get wireValue => name;
}

/// Raised when bulk work is refused before anything is sent.
final class TenantBulkCatalogException implements Exception {
  const TenantBulkCatalogException(this.code, [this.detail]);

  final String code;

  /// What the refusal is about, when the code alone cannot say - the offending
  /// column of a pasted sheet, for instance. Never a server message.
  final String? detail;

  @override
  String toString() =>
      'TenantBulkCatalogException($code${detail == null ? '' : ': $detail'})';
}

/// The one correction a bulk change applies across every product it names.
///
/// One field, not a form. Three reasons, and the first is the shape of the
/// input: these rows come from products already on this device rather than from a
/// file, so there is no column to read a per-product value out of. The second is
/// that a name and a code have no bulk meaning - two products cannot share a
/// corrected name, and a shared code is what the till refuses to resolve. The
/// third is authorization: the server decides permission over the *union* of
/// every row's requested fields, so folding a price into a category move would
/// refuse the whole request for a manager who never asked to change money.
final class TenantBulkCatalogEdit {
  const TenantBulkCatalogEdit._(this.field, this.value, this.clearsCost);

  /// Files every named product under one category.
  const TenantBulkCatalogEdit.category(String categoryId)
    : this._(TenantProductField.categoryId, categoryId, false);

  /// Prices every named product the same, as typed.
  const TenantBulkCatalogEdit.price(String price)
    : this._(TenantProductField.price, price, false);

  /// Records the same unit cost against every named product.
  const TenantBulkCatalogEdit.cost(String cost)
    : this._(TenantProductField.cost, cost, false);

  /// Removes the recorded unit cost from every named product.
  ///
  /// Its own case rather than an empty [cost], because omitting `cost` leaves a
  /// recorded figure alone and `cost: null` clears it - the one field in this
  /// system where sending nothing and sending null mean different things.
  const TenantBulkCatalogEdit.clearCost()
    : this._(TenantProductField.cost, '', true);

  final TenantProductField field;

  /// What was typed, unvalidated. The repository proves it.
  final String value;

  final bool clearsCost;

  /// Whether this correction changes money, and therefore needs an owner or an
  /// administrator for every row at once.
  bool get changesMoney => field.isMonetary;
}

/// One product named by one page of a bulk correction.
///
/// It carries what the product held for the report's sake and nothing else: the
/// value being written is the page's, identical across every row, which is what
/// makes the union of requested fields a single field.
final class TenantProductBatchRow {
  const TenantProductBatchRow._({
    required this.index,
    required this.position,
    required this.productId,
    required this.productName,
    required this.previous,
  });

  /// Where this row sits in its own page, which is what every server outcome is
  /// indexed by.
  final int index;

  /// Where it sits in the whole selection, one-based. This is what the report
  /// shows, because a page-local index is meaningless to the person who picked
  /// four hundred products.
  final int position;

  final String productId;
  final String productName;

  /// What the field being corrected held when the product was read, as the
  /// report states it. A stored figure the till cannot convert has no typed
  /// form, so this is a display string rather than a value.
  final String previous;
}

/// One request of a bulk correction: immutable, and its own idempotency key.
///
/// Immutable because [requestId] is held across this page's preview and its
/// commit, and the server's fingerprint covers the rows *in order*. A page whose
/// rows were rebuilt between the two would be refused as `already-exists`, which
/// is the honest answer and a useless one - so the pages a commit sends are the
/// same objects the preview sent.
final class TenantProductBatchPage {
  const TenantProductBatchPage._({
    required this.tenantId,
    required this.requestId,
    required this.number,
    required this.pageCount,
    required this.field,
    required this.clearsCost,
    required this.wireValue,
    required this.valueLabel,
    required this.rows,
  });

  final String tenantId;
  final String requestId;

  /// One-based, for a report that has to say which pages landed.
  final int number;
  final int pageCount;

  final TenantProductField field;
  final bool clearsCost;

  /// The corrected value exactly as it goes on the wire: a major-unit amount
  /// derived from minor units, a category ID, or null when a cost is cleared.
  final Object? wireValue;

  /// The same value as the report states it - a category's own name rather than
  /// its document ID, which is what a person recognises.
  ///
  /// Safe to display as what a row now holds because the decoder proves it: an
  /// outcome is refused unless the product came back holding exactly
  /// [wireValue], for a corrected row and an unchanged one alike.
  final String valueLabel;

  final List<TenantProductBatchRow> rows;

  Map<String, Object?> payload(TenantBulkCatalogMode mode) =>
      <String, Object?>{
        'tenantId': tenantId,
        'mode': mode.wireValue,
        'requestId': requestId,
        'rows': <Map<String, Object?>>[
          for (final row in rows)
            <String, Object?>{
              'productId': row.productId,
              // Named on every row even when it is null, because a cleared cost
              // is `cost: null` and an omitted key is "leave it alone".
              field.wireKey: wireValue,
            },
        ],
      };
}

/// Every request one bulk correction needs, in the order they must be sent.
final class TenantProductBatchPlan {
  const TenantProductBatchPlan._({
    required this.field,
    required this.clearsCost,
    required this.valueLabel,
    required this.pages,
  });

  final TenantProductField field;
  final bool clearsCost;

  /// What the correction sets, as the confirmation states it.
  final String valueLabel;

  final List<TenantProductBatchPage> pages;

  int get rowCount =>
      pages.fold(0, (total, page) => total + page.rows.length);
}

/// One product one page of an import will create.
final class TenantProductImportRow {
  const TenantProductImportRow._({
    required this.index,
    required this.line,
    required this.name,
    required this.sku,
    required this.priceMinor,
    required this.costMinor,
    required this.quantity,
    required this.categoryId,
    required this.categoryName,
  });

  /// Where this row sits in its own page, which is what the server indexes its
  /// outcome by - **and** what the product's document ID is derived from, so a
  /// page's rows can never be reordered.
  final int index;

  /// The line of the pasted sheet this row came from, one-based and counting the
  /// header. This is what the report shows: a person fixing a refusal is looking
  /// at their own file, where a page-local index names the wrong line.
  final int line;

  final String name;
  final String sku;
  final int priceMinor;

  /// Null when the sheet recorded no cost, which is not the same as zero.
  final int? costMinor;

  /// The opening balance, zero when the sheet named none. This is the only
  /// product payload in this app that may carry a quantity at all, and it may
  /// because the server writes the ledger entry that says where those units came
  /// from in the same transaction.
  final int quantity;

  /// Exactly one of these two is set, which is what the server requires.
  final String? categoryId;
  final String? categoryName;

  Map<String, Object?> payload() => <String, Object?>{
    'name': name,
    'sku': sku,
    // Derived from the minor units rather than from the cell, so the figure the
    // server converts back is the one the report showed.
    'price': priceMinor / 100,
    if (costMinor != null) 'cost': costMinor! / 100,
    if (quantity > 0) 'quantity': quantity,
    if (categoryId != null) 'categoryId': categoryId,
    // `categoryName` and never `category`: a stored product's `category` is the
    // legacy alias for `categoryId` and holds an ID. Writing a display name into
    // a field of that name is the exact drift the previous app's uploader
    // shipped, and it is invisible rather than broken.
    if (categoryName != null) 'categoryName': categoryName,
  };
}

/// One request of an import: immutable, and its own idempotency key, for the
/// reason [TenantProductBatchPage] is.
///
/// Order matters more here than anywhere else in this app. Each row's product ID
/// is a digest of the request identity and the row's *position*, so a reordered
/// retry answered off the stored record would report IDs belonging to different
/// products, and one not answered off it would create the whole page again.
final class TenantProductImportPage {
  const TenantProductImportPage._({
    required this.tenantId,
    required this.requestId,
    required this.number,
    required this.pageCount,
    required this.rows,
  });

  final String tenantId;
  final String requestId;
  final int number;
  final int pageCount;
  final List<TenantProductImportRow> rows;

  Map<String, Object?> payload(TenantBulkCatalogMode mode) =>
      <String, Object?>{
        'tenantId': tenantId,
        'mode': mode.wireValue,
        'requestId': requestId,
        'rows': <Map<String, Object?>>[
          for (final row in rows) row.payload(),
        ],
      };
}

/// Every request one import needs, plus the rows that never became one.
final class TenantProductImportPlan {
  const TenantProductImportPlan._({
    required this.pages,
    required this.refused,
    required this.lineCount,
  });

  final List<TenantProductImportPage> pages;

  /// Rows this client refused before anything was sent, already in report shape.
  ///
  /// Refused here rather than forwarded, because a cell this boundary would not
  /// write is a round trip that teaches nobody anything - and the server's own
  /// refusal for the same cell would be worded for a payload rather than for a
  /// spreadsheet. They still appear in the report beside the server's outcomes,
  /// so nothing is silently dropped.
  final List<TenantBulkCatalogRowReport> refused;

  /// How many data rows the sheet described, refusals included.
  final int lineCount;

  int get rowCount => pages.fold(0, (total, page) => total + page.rows.length);
}

/// What happened to one row, across both callables.
///
/// `unchanged` belongs to a correction and `created` to an import; neither
/// callable produces the other's, and one enum is used because the report shows
/// them in one list and a reader does not care which callable answered.
enum TenantBulkCatalogRowStatus {
  created('Created'),
  updated('Corrected'),
  unchanged('Unchanged'),
  failed('Refused');

  const TenantBulkCatalogRowStatus(this.label);

  final String label;

  static TenantBulkCatalogRowStatus? fromWire(String value) => switch (value) {
    'created' => created,
    'updated' => updated,
    'unchanged' => unchanged,
    'failed' => failed,
    _ => null,
  };
}

/// One row as the report states it.
final class TenantBulkCatalogRowReport {
  const TenantBulkCatalogRowReport({
    required this.position,
    required this.subject,
    required this.status,
    required this.detail,
  });

  /// Where the row came from: a sheet line for an import, a position in the
  /// selection for a correction.
  final int position;

  /// What the row is about - the product's name - so a refusal can be found.
  final String subject;

  final TenantBulkCatalogRowStatus status;

  /// What the row holds or would hold, or why it was refused.
  final String detail;
}

/// What a chain of requests did, whichever callable it drove.
///
/// A half-answered chain is the ordinary case rather than an error: fifty rows
/// per request means eight commits for four hundred rows, and the fourth can be
/// refused while the first three have already been written. So the report counts
/// pages as well as rows, and [complete] is the only thing that means "all of
/// it".
final class TenantBulkCatalogReport {
  const TenantBulkCatalogReport({
    required this.mode,
    required this.pageCount,
    required this.pagesAnswered,
    required this.rows,
    this.failure,
    this.failureDetail,
  });

  final TenantBulkCatalogMode mode;
  final int pageCount;

  /// How many pages the server answered. Under [pageCount] means the chain
  /// stopped, and in a commit means the rest was never written.
  final int pagesAnswered;

  final List<TenantBulkCatalogRowReport> rows;

  /// Why the chain stopped, and null when it did not.
  final TenantBulkCatalogFailure? failure;
  final String? failureDetail;

  bool get complete => failure == null && pagesAnswered == pageCount;

  int _count(TenantBulkCatalogRowStatus status) =>
      rows.where((row) => row.status == status).length;

  int get createdCount => _count(TenantBulkCatalogRowStatus.created);
  int get updatedCount => _count(TenantBulkCatalogRowStatus.updated);
  int get unchangedCount => _count(TenantBulkCatalogRowStatus.unchanged);
  int get failedCount => _count(TenantBulkCatalogRowStatus.failed);
}

/// What a row's product holds, or - in a preview - would hold.
final class TenantBulkCatalogRowProduct {
  const TenantBulkCatalogRowProduct._({
    required this.name,
    required this.sku,
    required this.price,
    required this.priceMinor,
    required this.cost,
    required this.costMinor,
    required this.categoryId,
    required this.quantity,
  });

  final String name;
  final String sku;
  final double price;
  final int priceMinor;
  final double? cost;
  final int? costMinor;
  final String categoryId;

  /// The opening balance an imported product is created holding. Null for a
  /// correction, which never names a quantity and never reports one.
  final int? quantity;
}

/// One row's outcome from `updateProducts`, decoded strictly.
final class TenantProductBatchRowOutcome {
  const TenantProductBatchRowOutcome._({
    required this.index,
    required this.productId,
    required this.status,
    required this.changedFields,
    required this.updateId,
    required this.code,
    required this.message,
    required this.product,
  });

  final int index;
  final String? productId;
  final TenantBulkCatalogRowStatus status;
  final List<TenantProductField> changedFields;

  /// The audit entry this row wrote, and null in a preview even for a row that
  /// would be corrected - which is where "did it happen" is answered.
  final String? updateId;

  final String? code;
  final String? message;
  final TenantBulkCatalogRowProduct? product;
}

/// One row's outcome from `importProducts`, decoded strictly.
final class TenantProductImportRowOutcome {
  const TenantProductImportRowOutcome._({
    required this.index,
    required this.status,
    required this.productId,
    required this.adjustmentId,
    required this.code,
    required this.message,
    required this.product,
  });

  final int index;
  final TenantBulkCatalogRowStatus status;

  /// The product this row created, and null in a preview - the ID is derivable
  /// before the write, and reporting it would be reporting a document that is
  /// not there.
  final String? productId;

  /// The ledger entry the opening units came in through. Null in a preview, and
  /// null for a row that opened holding nothing.
  final String? adjustmentId;

  final String? code;
  final String? message;
  final TenantBulkCatalogRowProduct? product;
}

/// Strictly decoded answer from `updateProducts`, reconciled against its page.
///
/// The response is not read as a report; it is checked against what was asked
/// for. It must name the same business and the same mode, carry one outcome per
/// row in order, and every corrected or unchanged row must come back holding the
/// value that page requested. Anything else is a `FormatException`, because this
/// is the surface that states what a business now sells and at what price.
final class TenantProductBatchResult {
  const TenantProductBatchResult._({
    required this.batchId,
    required this.mode,
    required this.rowCount,
    required this.updatedCount,
    required this.unchangedCount,
    required this.failedCount,
    required this.rows,
  });

  factory TenantProductBatchResult.fromCallable(
    Object? value, {
    required TenantProductBatchPage page,
    required TenantBulkCatalogMode mode,
  }) {
    const source = 'updateProducts';
    final data = _strictMap(value, source);
    _requireEnvelope(data, source, tenantId: page.tenantId, mode: mode);
    final rawRows = _requireRows(data, source, page.rows.length);
    final commits = mode == TenantBulkCatalogMode.commit;
    final outcomes = <TenantProductBatchRowOutcome>[];
    for (var index = 0; index < rawRows.length; index++) {
      final row = _strictMap(rawRows[index], source);
      final expected = page.rows[index];
      if (row['index'] != index) {
        throw const FormatException(
          'updateProducts answered rows out of order.',
        );
      }
      final status = _requireStatus(row, source, const <
        TenantBulkCatalogRowStatus
      >{
        TenantBulkCatalogRowStatus.updated,
        TenantBulkCatalogRowStatus.unchanged,
        TenantBulkCatalogRowStatus.failed,
      });
      final productId = row['productId'];
      // A refused row may name no product - the server reports one only when the
      // row got far enough to identify one - but a row it acted on must name the
      // product this page asked about and no other.
      if (status != TenantBulkCatalogRowStatus.failed &&
          productId != expected.productId) {
        throw const FormatException(
          'updateProducts answered for another product.',
        );
      }
      if (status == TenantBulkCatalogRowStatus.failed) {
        outcomes.add(
          TenantProductBatchRowOutcome._(
            index: index,
            productId: productId is String ? productId : null,
            status: status,
            changedFields: const <TenantProductField>[],
            updateId: null,
            code: _requiredString(row, 'code', source),
            message: _requiredString(row, 'message', source),
            product: null,
          ),
        );
        continue;
      }
      final changed = _requireChangedFields(row, source);
      if (status == TenantBulkCatalogRowStatus.updated) {
        // Exactly the one field this page names. A page corrects a single field
        // across every row, so a response naming a second one is describing a
        // write this correction never asked for.
        if (changed.length != 1 || changed.single != page.field) {
          throw const FormatException(
            'updateProducts reported a field this correction did not name.',
          );
        }
      } else if (changed.isNotEmpty) {
        throw const FormatException(
          'updateProducts reported an unchanged row as having changed.',
        );
      }
      final updateId = row['updateId'];
      final expectsUpdateId =
          commits && status == TenantBulkCatalogRowStatus.updated;
      if (expectsUpdateId) {
        if (updateId is! String || updateId.isEmpty) {
          throw const FormatException(
            'updateProducts committed a row without an audit entry.',
          );
        }
      } else if (updateId != null) {
        throw const FormatException(
          'updateProducts reported an audit entry for a row that wrote none.',
        );
      }
      final product = _requireProduct(row, source, withQuantity: false);
      _requireBatchValueApplied(page, product);
      outcomes.add(
        TenantProductBatchRowOutcome._(
          index: index,
          productId: expected.productId,
          status: status,
          changedFields: List<TenantProductField>.unmodifiable(changed),
          updateId: expectsUpdateId ? updateId as String : null,
          code: null,
          message: null,
          product: product,
        ),
      );
    }
    final result = TenantProductBatchResult._(
      batchId: _requiredString(data, 'batchId', source),
      mode: mode,
      rowCount: page.rows.length,
      updatedCount: _requiredCount(data, 'updatedCount', source),
      unchangedCount: _requiredCount(data, 'unchangedCount', source),
      failedCount: _requiredCount(data, 'failedCount', source),
      rows: List<TenantProductBatchRowOutcome>.unmodifiable(outcomes),
    );
    _requireCountsAgree(source, result.rowCount, <int>[
      result.updatedCount,
      result.unchangedCount,
      result.failedCount,
    ]);
    return result;
  }

  final String batchId;
  final TenantBulkCatalogMode mode;
  final int rowCount;
  final int updatedCount;
  final int unchangedCount;
  final int failedCount;
  final List<TenantProductBatchRowOutcome> rows;
}

/// Strictly decoded answer from `importProducts`, reconciled against its page.
final class TenantProductImportResult {
  const TenantProductImportResult._({
    required this.importId,
    required this.mode,
    required this.rowCount,
    required this.createdCount,
    required this.failedCount,
    required this.rows,
  });

  factory TenantProductImportResult.fromCallable(
    Object? value, {
    required TenantProductImportPage page,
    required TenantBulkCatalogMode mode,
  }) {
    const source = 'importProducts';
    final data = _strictMap(value, source);
    _requireEnvelope(data, source, tenantId: page.tenantId, mode: mode);
    final rawRows = _requireRows(data, source, page.rows.length);
    final commits = mode == TenantBulkCatalogMode.commit;
    final outcomes = <TenantProductImportRowOutcome>[];
    for (var index = 0; index < rawRows.length; index++) {
      final row = _strictMap(rawRows[index], source);
      final expected = page.rows[index];
      if (row['index'] != index) {
        throw const FormatException(
          'importProducts answered rows out of order.',
        );
      }
      final status = _requireStatus(row, source, const <
        TenantBulkCatalogRowStatus
      >{
        TenantBulkCatalogRowStatus.created,
        TenantBulkCatalogRowStatus.failed,
      });
      if (status == TenantBulkCatalogRowStatus.failed) {
        outcomes.add(
          TenantProductImportRowOutcome._(
            index: index,
            status: status,
            productId: null,
            adjustmentId: null,
            code: _requiredString(row, 'code', source),
            message: _requiredString(row, 'message', source),
            product: null,
          ),
        );
        continue;
      }
      final product = _requireProduct(row, source, withQuantity: true);
      _requireImportRowApplied(expected, product);
      final productId = row['productId'];
      final adjustmentId = row['adjustmentId'];
      if (commits) {
        if (productId is! String) {
          throw const FormatException(
            'importProducts created a row without a product.',
          );
        }
        _requireDocumentId(productId, source, 'productId');
        // A ledger entry exists exactly when units arrived. A row that opened
        // holding nothing writes none, and a row that opened holding something
        // without one would be stock with no recorded origin - the single defect
        // accepting a quantity at all was justified by preventing.
        if (expected.quantity > 0) {
          if (adjustmentId is! String) {
            throw const FormatException(
              'importProducts created opening stock with no ledger entry.',
            );
          }
          _requireDocumentId(adjustmentId, source, 'adjustmentId');
        } else if (adjustmentId != null) {
          throw const FormatException(
            'importProducts reported a ledger entry for a row that opened '
            'holding nothing.',
          );
        }
      } else if (productId != null || adjustmentId != null) {
        throw const FormatException(
          'importProducts named a document a preview did not write.',
        );
      }
      outcomes.add(
        TenantProductImportRowOutcome._(
          index: index,
          status: status,
          productId: commits ? productId as String : null,
          adjustmentId: commits && expected.quantity > 0
              ? adjustmentId as String
              : null,
          code: null,
          message: null,
          product: product,
        ),
      );
    }
    final result = TenantProductImportResult._(
      importId: _requiredString(data, 'importId', source),
      mode: mode,
      rowCount: page.rows.length,
      createdCount: _requiredCount(data, 'createdCount', source),
      failedCount: _requiredCount(data, 'failedCount', source),
      rows: List<TenantProductImportRowOutcome>.unmodifiable(outcomes),
    );
    _requireCountsAgree(source, result.rowCount, <int>[
      result.createdCount,
      result.failedCount,
    ]);
    return result;
  }

  final String importId;
  final TenantBulkCatalogMode mode;
  final int rowCount;
  final int createdCount;
  final int failedCount;
  final List<TenantProductImportRowOutcome> rows;
}

/// Why a whole request was refused, as opposed to one of its rows.
///
/// Every case here takes the page down. A row's own defect is never one of
/// these: it comes back as an outcome, which is the whole contract these two
/// callables keep.
enum TenantBulkCatalogFailure {
  /// The session may not change the catalog, or its membership ended.
  forbidden,

  /// A price or a cost needs an owner or an administrator, and one row naming
  /// either refuses every row. The surface does not offer those corrections to
  /// anybody else, so this is reachable only if the role changed.
  moneyForbidden,

  /// This request ID already settled a different request - the rows changed, or
  /// were reordered, between a preview and its commit.
  duplicateRequest,

  /// This business holds more categories than an import will resolve names
  /// against. Naming each row's category by ID needs no scan.
  tooManyCategories,

  /// The payload was refused as malformed, which means this client and the
  /// server disagree about what a row may hold.
  invalidRequest,

  /// Refused for a reason this client does not model.
  refused,

  /// The outcome is unknown. In a commit the page may have been written.
  ambiguous,
}

/// Raised when a whole request was refused or its outcome is unknown.
final class TenantBulkCatalogRequestException implements Exception {
  const TenantBulkCatalogRequestException(this.failure, [this.detail]);

  final TenantBulkCatalogFailure failure;

  /// The server's own sentence, when it names something this client cannot -
  /// which rows carried a price, which column was not understood.
  final String? detail;

  /// Whether a commit may have been written despite the refusal.
  ///
  /// Only an unknown outcome may have landed. Every other case is proof the
  /// page was not written, which is what makes it safe to say so.
  bool get mayHaveCommitted => failure == TenantBulkCatalogFailure.ambiguous;

  @override
  String toString() => 'TenantBulkCatalogRequestException(${failure.name})';
}

/// Narrow callable boundary for `updateProducts`.
abstract interface class UpdateProductsCallable {
  Future<Object?> call(Map<String, Object?> payload);
}

/// Narrow callable boundary for `importProducts`.
abstract interface class ImportProductsCallable {
  Future<Object?> call(Map<String, Object?> payload);
}

/// Firebase adapter for `updateProducts`.
final class FirebaseUpdateProductsCallable implements UpdateProductsCallable {
  FirebaseUpdateProductsCallable({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    final result = await _functions
        .httpsCallable('updateProducts')
        .call<Object?>(payload);
    return result.data;
  }
}

/// Firebase adapter for `importProducts`.
final class FirebaseImportProductsCallable implements ImportProductsCallable {
  FirebaseImportProductsCallable({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    final result = await _functions
        .httpsCallable('importProducts')
        .call<Object?>(payload);
    return result.data;
  }
}

/// Guarded intent boundary for changing many products at once.
///
/// It builds plans and nothing else: no caller can name an arbitrary business, an
/// arbitrary product, or a field the session may not change, because the session
/// is captured here and every product comes from a record this surface already
/// read and decoded from that same business.
final class TenantBulkCatalogRepository {
  const TenantBulkCatalogRepository({required this.session});

  final TenantSession session;

  /// The same operational three the catalog's own create form admits, and the
  /// same trio the server's `PRODUCT_UPDATE_ROLES` names for both callables.
  static const List<TenantRole> allowedRoles =
      TenantCatalogManagementRepository.allowedRoles;

  /// Whether this member may name money.
  ///
  /// It decides two different things, because the two callables differ. For a
  /// **correction** it decides whether a price or a cost may be corrected at
  /// all: the server authorizes over the union of every row's fields, so one row
  /// naming money refuses the whole request. For an **import** it decides only
  /// whether a cost column may be sent - a price is creation, and the
  /// add-product form beside it already accepts one from a manager.
  static bool canChangeMoneyInSession(TenantSession session) =>
      TenantCatalogManagementRepository.canRecordCostInSession(session);

  /// Builds every request one bulk correction needs.
  ///
  /// [products] are records this surface already read from this business, so the
  /// correction can only address products the operator was actually shown.
  /// [categories] are the categories it offered, for the same reason the
  /// add-product form takes them: a product may only be filed under a grouping
  /// read from this same business.
  TenantProductBatchPlan buildBatchPlan({
    required Iterable<TenantProduct> products,
    required TenantBulkCatalogEdit edit,
    required Iterable<TenantCategory> categories,
    required TenantCatalogRequestIdFactory requestIds,
  }) {
    _requireRole();
    if (edit.changesMoney && !canChangeMoneyInSession(session)) {
      throw TenantBulkCatalogException(
        edit.field == TenantProductField.price
            ? 'price_forbidden'
            : 'cost_forbidden',
      );
    }
    final selected = products.toList();
    if (selected.isEmpty) {
      throw const TenantBulkCatalogException('no_products_selected');
    }
    if (selected.length > maximumBulkCatalogSheetRows) {
      throw const TenantBulkCatalogException('too_many_products');
    }

    final Object? wireValue;
    final String valueLabel;
    TenantCategory? category;
    switch (edit.field) {
      case TenantProductField.categoryId:
        for (final candidate in categories) {
          if (candidate.id == edit.value) {
            category = candidate;
            break;
          }
        }
        if (category == null) {
          throw const TenantBulkCatalogException('unknown_category');
        }
        wireValue = category.id;
        valueLabel = category.name;
      case TenantProductField.price:
        final minor = _shared(
          () => tenantCatalogPriceMinorUnits(edit.value),
        );
        wireValue = minor / 100;
        valueLabel = tenantCatalogMajorUnits(minor);
      case TenantProductField.cost:
        if (edit.clearsCost) {
          wireValue = null;
          valueLabel = 'not recorded';
        } else {
          final minor = _shared(
            () => tenantCatalogPriceMinorUnits(
              edit.value,
              invalidCode: 'invalid_cost',
              unrepresentableCode: 'cost_not_representable',
            ),
          );
          wireValue = minor / 100;
          valueLabel = tenantCatalogMajorUnits(minor);
        }
      case TenantProductField.name:
      case TenantProductField.sku:
        // Unreachable through [TenantBulkCatalogEdit], whose four constructors
        // are the only way to name a field. Refused rather than asserted,
        // because a name or a code shared across many products is a state the
        // till cannot resolve by scan.
        throw const TenantBulkCatalogException('field_not_bulk_editable');
    }

    final categoryNames = tenantCategoryNames(categories);
    final rows = <TenantProductBatchRow>[];
    final seen = <String>{};
    for (final product in selected) {
      // A product decoded while another business was open can never be
      // corrected from this one, even though both payloads would be well-formed.
      if (product.tenantId != session.tenantId) {
        throw const TenantBulkCatalogException('edit_forbidden');
      }
      // The server refuses a product named twice outright - two rows for one
      // document are two conflicting intents with no honest outcome to report
      // for either - so it is refused here, where it can still be explained.
      if (!seen.add(product.id)) {
        throw const TenantBulkCatalogException('product_named_twice');
      }
      rows.add(
        TenantProductBatchRow._(
          index: rows.length % maximumBulkCatalogRows,
          position: rows.length + 1,
          productId: product.id,
          productName: product.name,
          previous: _describePrevious(edit.field, product, categoryNames),
        ),
      );
    }

    final pageCount = (rows.length + maximumBulkCatalogRows - 1) ~/
        maximumBulkCatalogRows;
    final pages = <TenantProductBatchPage>[];
    for (var start = 0; start < rows.length; start += maximumBulkCatalogRows) {
      final requestId = requestIds();
      _shared(() => requireTenantCatalogRequestId(requestId));
      pages.add(
        TenantProductBatchPage._(
          tenantId: session.tenantId,
          requestId: requestId,
          number: pages.length + 1,
          pageCount: pageCount,
          field: edit.field,
          clearsCost: edit.clearsCost,
          wireValue: wireValue,
          valueLabel: valueLabel,
          rows: List<TenantProductBatchRow>.unmodifiable(
            rows.skip(start).take(maximumBulkCatalogRows),
          ),
        ),
      );
    }
    return TenantProductBatchPlan._(
      field: edit.field,
      clearsCost: edit.clearsCost,
      valueLabel: valueLabel,
      pages: List<TenantProductBatchPage>.unmodifiable(pages),
    );
  }

  /// Parses one pasted sheet and builds every request its rows need.
  ///
  /// Defects are split the way the server splits them, and for the same reason.
  /// A defect belonging to the **sheet** - no header, a column nobody reads, one
  /// column twice, more rows than the chain will hold - is thrown, because
  /// reporting it per row would make the report itself wrong. A defect belonging
  /// to a **row** is that row's refusal, carried in
  /// [TenantProductImportPlan.refused] so every one of them is named at once
  /// rather than found one round trip at a time.
  TenantProductImportPlan buildImportPlan({
    required String sheet,
    required TenantCatalogRequestIdFactory requestIds,
  }) {
    _requireRole();
    final table = _parseDelimitedSheet(sheet);
    // Decided over the whole sheet before any row is read, because that is where
    // the server decides it: `assertProductImportAuthorized` refuses the request
    // rather than the rows, so a manager who got a green preview and then a
    // commit-time refusal would learn only that the app guesses. A price is
    // deliberately *not* gated - setting a first price is creation, and the
    // add-product form beside this one already accepts one from a manager.
    if (!canChangeMoneyInSession(session) &&
        table.columns.containsKey(_SheetColumn.cost)) {
      throw const TenantBulkCatalogException('cost_forbidden');
    }
    final rows = <TenantProductImportRow>[];
    final refused = <TenantBulkCatalogRowReport>[];
    for (final line in table.lines) {
      try {
        rows.add(
          _readImportRow(
            cells: line.cells,
            columns: table.columns,
            line: line.number,
            index: rows.length % maximumBulkCatalogRows,
          ),
        );
      } on TenantBulkCatalogException catch (error) {
        refused.add(
          TenantBulkCatalogRowReport(
            position: line.number,
            subject: _subjectOf(line, table.columns),
            status: TenantBulkCatalogRowStatus.failed,
            detail: bulkCatalogRefusalMessage(error),
          ),
        );
      }
    }
    if (rows.isEmpty && refused.isEmpty) {
      throw const TenantBulkCatalogException('sheet_has_no_rows');
    }

    final pageCount = (rows.length + maximumBulkCatalogRows - 1) ~/
        maximumBulkCatalogRows;
    final pages = <TenantProductImportPage>[];
    for (var start = 0; start < rows.length; start += maximumBulkCatalogRows) {
      final requestId = requestIds();
      _shared(() => requireTenantCatalogRequestId(requestId));
      pages.add(
        TenantProductImportPage._(
          tenantId: session.tenantId,
          requestId: requestId,
          number: pages.length + 1,
          pageCount: pageCount,
          rows: List<TenantProductImportRow>.unmodifiable(
            rows.skip(start).take(maximumBulkCatalogRows),
          ),
        ),
      );
    }
    return TenantProductImportPlan._(
      pages: List<TenantProductImportPage>.unmodifiable(pages),
      refused: List<TenantBulkCatalogRowReport>.unmodifiable(refused),
      lineCount: table.lines.length,
    );
  }

  void _requireRole() {
    if (!session.canAccess(allowedRoles: allowedRoles)) {
      throw const TenantBulkCatalogException('catalog_forbidden');
    }
  }

  TenantProductImportRow _readImportRow({
    required List<String> cells,
    required Map<_SheetColumn, int> columns,
    required int line,
    required int index,
  }) {
    String cell(_SheetColumn column) {
      final position = columns[column];
      if (position == null || position >= cells.length) return '';
      return cells[position].trim();
    }

    if (cells.length != columns.length) {
      throw TenantBulkCatalogException(
        'row_column_count',
        '${cells.length} of ${columns.length}',
      );
    }
    final name = _shared(
      () => tenantCatalogNormalizedName(
        cell(_SheetColumn.productName),
        'invalid_product_name',
      ),
    );
    final sku = _shared(
      () => tenantCatalogNormalizedSku(cell(_SheetColumn.sku)),
    );
    final priceMinor = _shared(
      () => tenantCatalogPriceMinorUnits(cell(_SheetColumn.price)),
    );
    final rawCost = cell(_SheetColumn.cost);
    int? costMinor;
    if (rawCost.isNotEmpty) {
      // The role was decided over the whole sheet before this row was read, so
      // what is left here is only whether the figure is recordable.
      costMinor = _shared(
        () => tenantCatalogPriceMinorUnits(
          rawCost,
          invalidCode: 'invalid_cost',
          unrepresentableCode: 'cost_not_representable',
        ),
      );
    }
    final quantity = _readOpeningQuantity(cell(_SheetColumn.quantity));
    final rawCategoryId = cell(_SheetColumn.categoryId);
    final rawCategoryName = cell(_SheetColumn.categoryName);
    if (rawCategoryId.isEmpty == rawCategoryName.isEmpty) {
      throw TenantBulkCatalogException(
        rawCategoryId.isEmpty ? 'row_needs_category' : 'row_category_twice',
      );
    }
    String? categoryId;
    if (rawCategoryId.isNotEmpty) {
      try {
        categoryId = validateTenantDocumentId(
          rawCategoryId,
          fieldName: 'categoryId',
        );
      } on ArgumentError {
        throw const TenantBulkCatalogException('invalid_category_id');
      }
    }
    return TenantProductImportRow._(
      index: index,
      line: line,
      name: name,
      sku: sku,
      priceMinor: priceMinor,
      costMinor: costMinor,
      quantity: quantity,
      categoryId: categoryId,
      categoryName: categoryId == null
          ? _shared(
              () => tenantCatalogNormalizedName(
                rawCategoryName,
                'invalid_category_name',
              ),
            )
          : null,
    );
  }
}

/// Runs one of the catalog surface's own validators and re-raises its refusal
/// as this boundary's.
///
/// The code is carried through unchanged, because the two boundaries share a
/// vocabulary for exactly the reason they share the validators: a product
/// created by an import, created by the add-product form, and corrected one at a
/// time cannot differ in what this client will write, so they cannot differ in
/// what they refuse either. This converts the exception type and nothing else.
T _shared<T>(T Function() validate) {
  try {
    return validate();
  } on TenantCatalogManagementException catch (error) {
    throw TenantBulkCatalogException(error.code);
  }
}

/// What the field being corrected holds now, as the report states it.
String _describePrevious(
  TenantProductField field,
  TenantProduct product,
  Map<String, String> categoryNames,
) {
  switch (field) {
    case TenantProductField.categoryId:
      // A product may sit in a category this page did not read, and its
      // document ID is not a name for it - one wording for that, in
      // [tenantCategoryLabel], rather than one per surface.
      return tenantCategoryLabel(product.categoryId, names: categoryNames);
    case TenantProductField.price:
      final minor = checkoutMinorUnitsFromMajor(product.price);
      return minor == null
          ? '${product.price} (unusable)'
          : tenantCatalogMajorUnits(minor);
    case TenantProductField.cost:
      final cost = product.cost;
      if (cost == null) return 'not recorded';
      final minor = checkoutMinorUnitsFromMajor(cost);
      return minor == null ? '$cost (unusable)' : tenantCatalogMajorUnits(minor);
    case TenantProductField.name:
      return product.name;
    case TenantProductField.sku:
      return product.sku;
  }
}

int _readOpeningQuantity(String value) {
  if (value.isEmpty) return 0;
  final quantity = int.tryParse(value);
  if (quantity == null ||
      quantity < 0 ||
      quantity > maximumBulkOpeningQuantity) {
    throw const TenantBulkCatalogException('invalid_quantity');
  }
  return quantity;
}

/// A column one sheet may carry, with every spelling accepted for it.
///
/// Aliases exist because the header is whatever the spreadsheet already called
/// the column, and refusing "Barcode" for a column of barcodes would be a rule
/// about vocabulary rather than about products. What is **not** accepted is a
/// column this client does not read: a header nobody understands is refused for
/// the whole sheet, because dropping it silently drops data a person supplied.
enum _SheetColumn {
  // `productName` rather than `name`, and `categoryName` rather than `category`:
  // an enum cannot declare a constant called `name`, because every enum already
  // has one.
  productName('name', <String>['name', 'product', 'product name'], required: true),
  sku('sku', <String>['sku', 'code', 'barcode'], required: true),
  price('price', <String>['price', 'unit price', 'selling price'], required: true),
  cost('cost', <String>['cost', 'unit cost', 'buying price']),
  quantity('quantity', <String>['quantity', 'qty', 'stock', 'opening stock']),
  categoryName('category', <String>['category', 'category name']),
  categoryId('categoryId', <String>['categoryid', 'category id']);

  const _SheetColumn(this.label, this.headers, {this.required = false});

  /// What a refusal calls this column, which is the header a person should type.
  final String label;

  final List<String> headers;

  /// Whether a sheet without this column can describe a product at all. The
  /// three that are required are the three the server requires of every row.
  final bool required;

  static _SheetColumn? fromHeader(String value) {
    for (final column in values) {
      if (column.headers.contains(value)) return column;
    }
    return null;
  }
}

final class _SheetLine {
  const _SheetLine(this.number, this.cells);

  /// The line of the pasted text this row came from, one-based and counting the
  /// header, so it is the line number the person's own editor shows.
  final int number;
  final List<String> cells;
}

final class _SheetTable {
  const _SheetTable(this.columns, this.lines);

  final Map<_SheetColumn, int> columns;
  final List<_SheetLine> lines;
}

/// Reads pasted delimited text into a header and its rows.
///
/// Delimited text rather than a picked `.xlsx`, deliberately, and it is the
/// input a person already has: every spreadsheet exports it, it survives a
/// copy-and-paste out of one, and it needs no package and no file picker. A
/// binary format is a different chunk and buys nothing until this one is used.
///
/// Quoting is the minimum a spreadsheet actually emits: a double-quoted cell may
/// hold the delimiter, and `""` inside one is a literal quote. Without it a
/// product called `Bread, sliced` would silently become two cells and shift every
/// column after it - a wrong import that looks like a valid one.
_SheetTable _parseDelimitedSheet(String sheet) {
  final lines = sheet.split(RegExp('\r\n|\r|\n'));
  var headerIndex = -1;
  for (var index = 0; index < lines.length; index++) {
    if (lines[index].trim().isNotEmpty) {
      headerIndex = index;
      break;
    }
  }
  if (headerIndex < 0) {
    throw const TenantBulkCatalogException('sheet_empty');
  }
  final delimiter = _detectDelimiter(lines[headerIndex]);
  final headers = _splitDelimited(lines[headerIndex], delimiter);
  final columns = <_SheetColumn, int>{};
  for (var position = 0; position < headers.length; position++) {
    final header = headers[position]
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
    if (header.isEmpty) {
      throw TenantBulkCatalogException('sheet_blank_column', '${position + 1}');
    }
    final column = _SheetColumn.fromHeader(header);
    if (column == null) {
      throw TenantBulkCatalogException('sheet_unknown_column', headers[position]);
    }
    if (columns.containsKey(column)) {
      throw TenantBulkCatalogException('sheet_repeated_column', headers[position]);
    }
    columns[column] = position;
  }
  for (final column in _SheetColumn.values) {
    if (column.required && !columns.containsKey(column)) {
      throw TenantBulkCatalogException('sheet_missing_column', column.label);
    }
  }
  // Exactly one of the two ways to name a category, checked for the sheet rather
  // than per row: a sheet carrying both columns cannot say which it means for a
  // row that fills both, and a sheet carrying neither files nothing at all.
  final hasId = columns.containsKey(_SheetColumn.categoryId);
  final hasName = columns.containsKey(_SheetColumn.categoryName);
  if (!hasId && !hasName) {
    throw const TenantBulkCatalogException('sheet_missing_category');
  }

  final rows = <_SheetLine>[];
  for (var index = headerIndex + 1; index < lines.length; index++) {
    if (lines[index].trim().isEmpty) continue;
    rows.add(_SheetLine(index + 1, _splitDelimited(lines[index], delimiter)));
    if (rows.length > maximumBulkCatalogSheetRows) {
      throw TenantBulkCatalogException(
        'sheet_too_many_rows',
        '$maximumBulkCatalogSheetRows',
      );
    }
  }
  return _SheetTable(columns, rows);
}

/// Decides the delimiter from the header alone, so every row is split the same.
///
/// Deciding it per row would let one row with a stray tab be split differently
/// from its neighbours, which is the kind of wrong that reaches the catalog.
String _detectDelimiter(String header) {
  if (header.contains('\t')) return '\t';
  if (header.contains(',')) return ',';
  // A semicolon is what a spreadsheet exports where the decimal separator is a
  // comma, so it is a real export rather than an exotic one.
  if (header.contains(';')) return ';';
  throw const TenantBulkCatalogException('sheet_no_delimiter');
}

List<String> _splitDelimited(String line, String delimiter) {
  final cells = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var index = 0; index < line.length; index++) {
    final character = line[index];
    if (quoted) {
      if (character != '"') {
        cell.write(character);
      } else if (index + 1 < line.length && line[index + 1] == '"') {
        cell.write('"');
        index++;
      } else {
        quoted = false;
      }
      continue;
    }
    if (character == '"' && cell.isEmpty) {
      quoted = true;
    } else if (character == delimiter) {
      cells.add(cell.toString());
      cell.clear();
    } else {
      cell.write(character);
    }
  }
  cells.add(cell.toString());
  return cells;
}

/// Session-bound gateway for `updateProducts`, with no business input surface.
final class TenantProductBatchGateway {
  const TenantProductBatchGateway({
    required TenantSession session,
    required UpdateProductsCallable callable,
  }) : _session = session,
       _callable = callable;

  final TenantSession _session;
  final UpdateProductsCallable _callable;

  static bool canChangeInSession(TenantSession session) => session.canAccess(
    allowedRoles: TenantBulkCatalogRepository.allowedRoles,
  );

  /// Sends one page in one mode. A page keeps its request ID across both, so a
  /// commit following its own preview is one request the server has never
  /// recorded, and a repeated commit is answered off the record it made.
  Future<TenantProductBatchResult> send(
    TenantProductBatchPage page,
    TenantBulkCatalogMode mode,
  ) async {
    if (!canChangeInSession(_session) || page.tenantId != _session.tenantId) {
      throw const TenantBulkCatalogRequestException(
        TenantBulkCatalogFailure.forbidden,
      );
    }
    final response = await _invoke(_callable.call, page.payload(mode));
    return TenantProductBatchResult.fromCallable(
      response,
      page: page,
      mode: mode,
    );
  }
}

/// Session-bound gateway for `importProducts`, with no business input surface.
final class TenantProductImportGateway {
  const TenantProductImportGateway({
    required TenantSession session,
    required ImportProductsCallable callable,
  }) : _session = session,
       _callable = callable;

  final TenantSession _session;
  final ImportProductsCallable _callable;

  static bool canImportInSession(TenantSession session) => session.canAccess(
    allowedRoles: TenantBulkCatalogRepository.allowedRoles,
  );

  Future<TenantProductImportResult> send(
    TenantProductImportPage page,
    TenantBulkCatalogMode mode,
  ) async {
    if (!canImportInSession(_session) || page.tenantId != _session.tenantId) {
      throw const TenantBulkCatalogRequestException(
        TenantBulkCatalogFailure.forbidden,
      );
    }
    final response = await _invoke(_callable.call, page.payload(mode));
    return TenantProductImportResult.fromCallable(
      response,
      page: page,
      mode: mode,
    );
  }
}

Future<Object?> _invoke(
  Future<Object?> Function(Map<String, Object?>) callable,
  Map<String, Object?> payload,
) async {
  try {
    return await callable(payload);
  } on FirebaseFunctionsException catch (error) {
    throw TenantBulkCatalogRequestException(
      classifyBulkCatalogFailure(error),
      error.message,
    );
  } on TimeoutException {
    throw const TenantBulkCatalogRequestException(
      TenantBulkCatalogFailure.ambiguous,
    );
  } catch (_) {
    throw const TenantBulkCatalogRequestException(
      TenantBulkCatalogFailure.ambiguous,
    );
  }
}

/// Classifies a whole-request refusal from either bulk callable.
///
/// The code decides the outcome. `permission-denied` and `failed-precondition`
/// each cover several distinct server conditions, so those are separated by the
/// exact wording `productUpdate.ts`, `productBatch.ts`, and `productImport.ts`
/// raise. If that wording ever changes the case degrades to a broader failure in
/// the same family, which still reports truthfully whether anything was written -
/// the classification only ever words a message and decides whether a page may be
/// re-sent, never whether it silently is.
TenantBulkCatalogFailure classifyBulkCatalogFailure(
  FirebaseFunctionsException error,
) {
  final message = error.message ?? '';
  return switch (error.code) {
    'permission-denied'
        when message.contains("product's price") ||
            message.contains('what a product costs') =>
      TenantBulkCatalogFailure.moneyForbidden,
    'permission-denied' ||
    'unauthenticated' => TenantBulkCatalogFailure.forbidden,
    'already-exists' => TenantBulkCatalogFailure.duplicateRequest,
    'failed-precondition' when message.contains('categories') =>
      TenantBulkCatalogFailure.tooManyCategories,
    'invalid-argument' => TenantBulkCatalogFailure.invalidRequest,
    'unavailable' ||
    'deadline-exceeded' ||
    'internal' ||
    'aborted' ||
    'unknown' => TenantBulkCatalogFailure.ambiguous,
    _ => TenantBulkCatalogFailure.refused,
  };
}

/// The report lines one answered page of a bulk correction produces.
///
/// The server's index is page-local; the position a person recognises is the one
/// in their selection. Translating here rather than in the widget is what keeps
/// the two from drifting once a chain is more than one page long.
List<TenantBulkCatalogRowReport> describeBatchOutcomes(
  TenantProductBatchPage page,
  TenantProductBatchResult result,
) => <TenantBulkCatalogRowReport>[
  for (final outcome in result.rows)
    TenantBulkCatalogRowReport(
      position: page.rows[outcome.index].position,
      subject: page.rows[outcome.index].productName,
      status: outcome.status,
      detail: switch (outcome.status) {
        TenantBulkCatalogRowStatus.failed => outcome.message ?? 'Refused.',
        TenantBulkCatalogRowStatus.unchanged =>
          'Already ${page.valueLabel}. Nothing was written for this row.',
        _ => '${page.rows[outcome.index].previous} → ${page.valueLabel}',
      },
    ),
];

/// The report lines one answered page of an import produces.
///
/// [names] are the categories this surface read. The server echoes the
/// `categoryId` it wrote, which is correct of the server and is exactly what a
/// person did not type: a sheet says `Bakery`, and a preview answering
/// `cat-bakery` names the row by something nobody typed and nobody reads.
List<TenantBulkCatalogRowReport> describeImportOutcomes(
  TenantProductImportPage page,
  TenantProductImportResult result, {
  required Map<String, String> names,
}) => <TenantBulkCatalogRowReport>[
  for (final outcome in result.rows)
    TenantBulkCatalogRowReport(
      position: page.rows[outcome.index].line,
      subject: page.rows[outcome.index].name,
      status: outcome.status,
      detail: switch (outcome.status) {
        TenantBulkCatalogRowStatus.failed => outcome.message ?? 'Refused.',
        _ => _describeImportedProduct(
          outcome.product!,
          page.rows[outcome.index],
          names,
        ),
      },
    ),
];

String _describeImportedProduct(
  TenantBulkCatalogRowProduct product,
  TenantProductImportRow row,
  Map<String, String> names,
) {
  final cost = product.costMinor;
  return '${product.sku} • ${tenantCatalogMajorUnits(product.priceMinor)} '
      '• ${cost == null ? 'no unit cost' : 'costs ${tenantCatalogMajorUnits(cost)}'} '
      '• opens holding ${product.quantity ?? 0} '
      '• filed under ${_importedCategory(product.categoryId, row, names)}';
}

/// What an imported row is reported as filed under, in descending certainty.
///
/// The categories this surface read come first, because they are the list every
/// other catalog surface names a category from. The sheet's own `categoryName`
/// is next and is a true name: the server matched it against a real category in
/// order to accept the row at all. It is second because the fold is
/// case-insensitive and a business may hold more categories than one page, so
/// what somebody typed can differ in case from what is stored. **The document
/// ID is not a third degree** - it is not shown at all.
String _importedCategory(
  String categoryId,
  TenantProductImportRow row,
  Map<String, String> names,
) => names[categoryId] ?? row.categoryName ?? unlistedTenantCategoryPhrase;

/// What a locally refused row says, in the words the person who pasted it needs.
String bulkCatalogRefusalMessage(TenantBulkCatalogException error) =>
    switch (error.code) {
      'catalog_forbidden' =>
        'Only an owner, administrator, or manager may change the catalog.',
      'no_products_selected' =>
        'Choose at least one product before previewing a correction.',
      'too_many_products' =>
        'At most $maximumBulkCatalogSheetRows products can be corrected in one '
            'pass. Correct some of them, then the rest.',
      'product_named_twice' =>
        'One product is named twice, and two corrections for one product have '
            'no order. Nothing was sent.',
      'field_not_bulk_editable' =>
        'A name and a code belong to one product each and cannot be corrected '
            'across many.',
      'unknown_category' =>
        'Choose one of the categories read from this business.',
      'edit_forbidden' =>
        'One of those products belongs to another business, so nothing was '
            'sent.',
      'price_forbidden' =>
        'Only an owner or administrator may change a price, and one row naming '
            'money refuses every row.',
      'cost_forbidden' =>
        'Only an owner or administrator may record what a product costs. Remove '
            'the cost column, or ask one of them to import it.',
      'invalid_price' =>
        'The price must be a plain amount with at most two decimal places, such '
            'as 65 or 19.99.',
      'price_not_representable' =>
        'That price is larger than a sale in this app can record, so it is '
            'refused here rather than at the till.',
      'invalid_cost' =>
        'The unit cost must be a plain amount with at most two decimal places, '
            'or blank.',
      'cost_not_representable' =>
        'That unit cost is larger than a sale in this app can record.',
      'invalid_product_name' =>
        'The product name must not be blank and must be at most '
            '$maximumCatalogNameLength characters.',
      'invalid_category_name' =>
        'The category name must not be blank and must be at most '
            '$maximumCatalogNameLength characters.',
      'invalid_sku' =>
        'The code must not be blank, must have no spaces, and must be at most '
            '$maximumCatalogSkuLength characters - it is what the till matches '
            'a scan against.',
      'invalid_quantity' =>
        'The opening quantity must be a whole number of units between 0 and '
            '$maximumBulkOpeningQuantity, or blank.',
      'invalid_category_id' => 'That category ID is not a usable document ID.',
      'row_needs_category' =>
        'Every product is filed under a category, so this row needs one.',
      'row_category_twice' =>
        'This row names a category twice, by name and by ID, and there is no '
            'honest way to decide which was meant.',
      'row_column_count' =>
        'This row has ${error.detail} cells the header names.',
      'sheet_empty' => 'Paste the rows, starting with a header line.',
      'sheet_no_delimiter' =>
        'The header line must separate its columns with a comma, a tab, or a '
            'semicolon.',
      'sheet_blank_column' =>
        'Column ${error.detail} of the header has no name.',
      'sheet_unknown_column' =>
        '"${error.detail}" is not a column this import reads. Remove it, or '
            'rename it - nothing is dropped silently.',
      'sheet_repeated_column' =>
        '"${error.detail}" appears twice in the header.',
      'sheet_missing_column' =>
        'The header must name a ${error.detail} column.',
      'sheet_missing_category' =>
        'The header must name a category column, or a categoryId column.',
      'sheet_too_many_rows' =>
        'At most ${error.detail} rows can be imported in one pass. Split the '
            'sheet and import each part.',
      'sheet_has_no_rows' =>
        'The header was read and no rows followed it.',
      'invalid_catalog_request_id' =>
        'This build produced an unusable request identifier, so nothing was '
            'sent.',
      _ => 'That row could not be read.',
    };

Map<String, Object?> _strictMap(Object? value, String source) {
  if (value is! Map) {
    throw FormatException('$source returned an invalid response.');
  }
  return <String, Object?>{
    for (final key in value.keys)
      if (key is String) key: value[key],
  };
}

void _requireEnvelope(
  Map<String, Object?> data,
  String source, {
  required String tenantId,
  required TenantBulkCatalogMode mode,
}) {
  if (data['tenantId'] != tenantId) {
    throw FormatException('$source answered for another business.');
  }
  // A commit answered as a preview would report writes that never happened, and
  // a preview answered as a commit would report a catalog nobody agreed to.
  if (data['mode'] != mode.wireValue) {
    throw FormatException('$source answered in the wrong mode.');
  }
}

List<Object?> _requireRows(
  Map<String, Object?> data,
  String source,
  int expected,
) {
  final rows = data['rows'];
  if (rows is! List || rows.length != expected) {
    throw FormatException('$source answered for a different set of rows.');
  }
  if (data['rowCount'] != expected) {
    throw FormatException('$source disagreed about how many rows it read.');
  }
  return rows;
}

TenantBulkCatalogRowStatus _requireStatus(
  Map<String, Object?> row,
  String source,
  Set<TenantBulkCatalogRowStatus> allowed,
) {
  final raw = row['status'];
  final status = raw is String
      ? TenantBulkCatalogRowStatus.fromWire(raw)
      : null;
  if (status == null || !allowed.contains(status)) {
    throw FormatException('$source reported an unknown row outcome.');
  }
  return status;
}

List<TenantProductField> _requireChangedFields(
  Map<String, Object?> row,
  String source,
) {
  final raw = row['changedFields'];
  if (raw is! List) {
    throw FormatException('$source returned invalid changed fields.');
  }
  final fields = <TenantProductField>[];
  for (final entry in raw) {
    final field = entry is String
        ? TenantProductField.fromWireKey(entry)
        : null;
    if (field == null) {
      throw FormatException('$source named a field this client cannot read.');
    }
    fields.add(field);
  }
  return fields;
}

TenantBulkCatalogRowProduct _requireProduct(
  Map<String, Object?> row,
  String source, {
  required bool withQuantity,
}) {
  final product = _strictMap(row['product'], source);
  final price = product['price'];
  final priceMinor = product['priceMinor'];
  if (price is! num || priceMinor is! int) {
    throw FormatException('$source returned an invalid price.');
  }
  if (checkoutMinorUnitsFromMajor(price) != priceMinor) {
    throw FormatException('$source returned inconsistent price figures.');
  }
  final (cost, costMinor) = tenantCatalogOptionalMoney(
    product,
    'cost',
    'costMinor',
    source: source,
  );
  int? quantity;
  if (withQuantity) {
    final raw = product['quantity'];
    if (raw is! int) {
      throw FormatException('$source returned an invalid opening quantity.');
    }
    quantity = raw;
  }
  return TenantBulkCatalogRowProduct._(
    name: _requiredString(product, 'name', source),
    sku: _requiredString(product, 'sku', source),
    price: price.toDouble(),
    priceMinor: priceMinor,
    cost: cost,
    costMinor: costMinor,
    categoryId: _requireDocumentId(
      _requiredString(product, 'categoryId', source),
      source,
      'categoryId',
    ),
    quantity: quantity,
  );
}

/// Proves the row came back holding the value the page asked for.
///
/// Not decoration: a response that reported `updated` while the product held
/// something else would put a figure on this screen that no device will read.
void _requireBatchValueApplied(
  TenantProductBatchPage page,
  TenantBulkCatalogRowProduct product,
) {
  final applied = switch (page.field) {
    TenantProductField.categoryId => product.categoryId == page.wireValue,
    TenantProductField.price =>
      product.priceMinor == checkoutMinorUnitsFromMajor(page.wireValue as num),
    TenantProductField.cost => page.clearsCost
        ? product.costMinor == null
        : product.costMinor ==
              checkoutMinorUnitsFromMajor(page.wireValue as num),
    TenantProductField.name || TenantProductField.sku => false,
  };
  if (!applied) {
    throw const FormatException(
      'updateProducts did not apply the correction it reported.',
    );
  }
}

/// Proves an imported row came back describing the product the row asked for.
///
/// The category is the one field that legitimately differs from the request: a
/// row naming "Bakery" is answered with the ID that name resolved to, which is
/// the whole reason names are resolved on the server.
void _requireImportRowApplied(
  TenantProductImportRow row,
  TenantBulkCatalogRowProduct product,
) {
  final matches =
      product.name == row.name &&
      product.sku == row.sku &&
      product.priceMinor == row.priceMinor &&
      product.costMinor == row.costMinor &&
      product.quantity == row.quantity &&
      (row.categoryId == null || product.categoryId == row.categoryId);
  if (!matches) {
    throw const FormatException(
      'importProducts described a product this row did not ask for.',
    );
  }
}

String _requiredString(
  Map<String, Object?> data,
  String field,
  String source,
) {
  final value = data[field];
  if (value is! String || value.isEmpty || value != value.trim()) {
    throw FormatException('$source returned an invalid $field.');
  }
  return value;
}

int _requiredCount(Map<String, Object?> data, String field, String source) {
  final value = data[field];
  if (value is! int || value < 0) {
    throw FormatException('$source returned an invalid $field.');
  }
  return value;
}

void _requireCountsAgree(String source, int rowCount, List<int> counts) {
  if (counts.fold(0, (total, count) => total + count) != rowCount) {
    throw FormatException('$source returned counts that do not add up.');
  }
}

String _requireDocumentId(String value, String source, String field) {
  try {
    return validateTenantDocumentId(value, fieldName: field);
  } on ArgumentError {
    throw FormatException('$source returned an invalid $field.');
  }
}

String _subjectOf(_SheetLine line, Map<_SheetColumn, int> columns) {
  final position = columns[_SheetColumn.productName];
  if (position == null || position >= line.cells.length) return 'This row';
  final name = line.cells[position].trim();
  return name.isEmpty ? 'This row' : name;
}
