/// One production batch: what the form holds, the arithmetic, and the record it
/// becomes.
///
/// **Every rule mirrors `functions/src/operations/production.ts`**, and the
/// arithmetic is the server's to the cent, so the cost per unit a person reads
/// while typing is the cost the product is given. A refused batch is stranded on
/// the device that queued it, so nothing the form could catch may reach the
/// server.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../checkout/checkout_draft.dart';
import '../inventory/catalog_management.dart';
import '../tenancy/tenant_catalog.dart';
import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_paths.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_types.dart';

/// The server's `MAXIMUM_PRODUCTION_EXPENSES`.
const int maximumProductionExpenses = 20;

/// The server's `MAXIMUM_IMPORT_OPENING_STOCK`: the most one batch may make.
const int maximumProductionQuantity = 1000000;

/// The server's `MAXIMUM_PRODUCT_NAME_LENGTH`, which a cost's description shares.
const int maximumProductionDescriptionLength = 120;

/// The server's `MAXIMUM_PRODUCT_PRICE_MINOR_UNITS`: the largest cost a sale
/// can record.
const int maximumProductionUnitCostMinor = 100000000000;

/// Raised when a batch is refused before anything is queued.
final class TenantProductionException implements Exception {
  const TenantProductionException(this.code, {this.row});

  final String code;

  /// The 1-based expense row a row-level refusal is about.
  final int? row;

  @override
  String toString() => 'TenantProductionException($code)';
}

/// What one unit cost to make, in minor units, rounded half up - the server's
/// `productionUnitCostMinor`, integer for integer.
int productionUnitCostMinor(int totalCostMinor, int quantity) =>
    (2 * totalCostMinor + quantity) ~/ (2 * quantity);

/// One expense row as the form holds it, typed.
final class TenantProductionRowDraft {
  const TenantProductionRowDraft({this.description = '', this.amount = ''});

  final String description;
  final String amount;

  /// Whether nothing at all has been typed into the row. A blank row is
  /// ignored rather than refused, so an accidental *Add cost* never blocks the
  /// form.
  bool get isBlank => description.trim().isEmpty && amount.trim().isEmpty;
}

/// One validated expense row.
final class TenantProductionExpense {
  const TenantProductionExpense({
    required this.description,
    required this.amountMinor,
  });

  final String description;
  final int amountMinor;
}

/// What the rows add up to so far, for the figures the form shows while it is
/// being filled in - or null when they do not yet add up to anything.
final class TenantProductionPreview {
  const TenantProductionPreview._({
    required this.totalCostMinor,
    required this.unitCostMinor,
  });

  /// Reads the typed rows and quantity without refusing anything: a row that is
  /// not yet a figure simply does not count.
  static TenantProductionPreview? of({
    required String quantity,
    required List<TenantProductionRowDraft> rows,
  }) {
    var total = 0;
    for (final row in rows) {
      final minor = _amountOrNull(row.amount);
      if (minor != null && minor > 0) total += minor;
    }
    if (total == 0) return null;
    final units = int.tryParse(quantity.trim());
    return TenantProductionPreview._(
      totalCostMinor: total,
      unitCostMinor: units == null || units < 1
          ? null
          : productionUnitCostMinor(total, units),
    );
  }

  final int totalCostMinor;

  /// Null until a quantity has been typed.
  final int? unitCostMinor;
}

/// A validated batch, ready to queue.
final class TenantProductionIntent {
  const TenantProductionIntent._({
    required this.tenantId,
    required this.batchId,
    required this.batchNumber,
    required this.path,
    required this.product,
    required this.quantity,
    required this.expenses,
    required this.totalCostMinor,
    required this.unitCostMinor,
  });

  final String tenantId;
  final String batchId;
  final String batchNumber;
  final String path;
  final TenantProduct product;
  final int quantity;
  final List<TenantProductionExpense> expenses;
  final int totalCostMinor;
  final int unitCostMinor;

  int get quantityAfter => product.quantity + quantity;

  /// The cost the product holds now, in minor units, or null.
  int? get previousCostMinor =>
      product.cost == null ? null : checkoutMinorUnitsFromMajor(product.cost!);

  /// The request `completeProduction` reads, which is also what the queue
  /// replays. The totals are this device's arithmetic, carried for the
  /// overlay; the server works them out again.
  Map<String, Object?> payload() => <String, Object?>{
    'tenantId': tenantId,
    'batchId': batchId,
    'batchNumber': batchNumber,
    'productId': product.id,
    'productName': product.name,
    'quantity': quantity,
    'expenses': <Map<String, Object?>>[
      for (final row in expenses)
        <String, Object?>{
          'description': row.description,
          'amount': row.amountMinor / 100,
        },
    ],
    'totalCostMinor': totalCostMinor,
    'unitCostMinor': unitCostMinor,
  };

  String get operationId => 'production-complete-$batchId';
}

/// One batch as `production_batches/{batchId}` holds it.
final class TenantProductionBatch {
  TenantProductionBatch.fromDocument({
    required String path,
    required Map<String, Object?> data,
  }) : id = _batchId(path),
       tenantId = validateTenantId(path.split('/')[1]),
       batchNumber = _string(data['batchNumber']) ?? _batchId(path),
       productId = _string(data['productId']) ?? '',
       productName = _string(data['productName']) ?? 'Product',
       quantity = data['quantity'] is int ? data['quantity'] as int : 0,
       expenses = _expenses(data['expenses']),
       totalCostMinor = data['totalCostMinor'] is int
           ? data['totalCostMinor'] as int
           : 0,
       unitCostMinor = data['unitCostMinor'] is int
           ? data['unitCostMinor'] as int
           : 0,
       previousCostMinor = data['previousCostMinor'] is int
           ? data['previousCostMinor'] as int
           : null,
       actorUid = _string(data['actorUid']),
       createdAt = tenantStoredInstant(data['createdAt']);

  factory TenantProductionBatch.fromSnapshot(
    TenantQueryDocumentSnapshot snapshot,
  ) => TenantProductionBatch.fromDocument(
    path: snapshot.path,
    data: snapshot.data,
  );

  final String id;
  final String tenantId;
  final String batchNumber;
  final String productId;
  final String productName;
  final int quantity;
  final List<TenantProductionExpense> expenses;
  final int totalCostMinor;
  final int unitCostMinor;

  /// What one unit cost before this batch, when a cost was recorded.
  final int? previousCostMinor;
  final String? actorUid;
  final DateTime? createdAt;

  static String _batchId(String path) {
    final parts = path.split('/');
    if (parts.length != 4 ||
        parts[0] != 'tenants' ||
        parts[2] != TenantCollection.productionBatches.segment) {
      throw const FormatException('Not a production batch.');
    }
    return validateTenantDocumentId(parts[3], fieldName: 'batchId');
  }

  static String? _string(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  static List<TenantProductionExpense> _expenses(Object? value) {
    if (value is! List) return const <TenantProductionExpense>[];
    return List<TenantProductionExpense>.unmodifiable(<TenantProductionExpense>[
      for (final row in value)
        if (row is Map &&
            row['description'] is String &&
            row['amountMinor'] is int)
          TenantProductionExpense(
            description: row['description'] as String,
            amountMinor: row['amountMinor'] as int,
          ),
    ]);
  }
}

/// One page of the batch list, newest first.
final class TenantProductionPage {
  const TenantProductionPage({
    required this.items,
    required this.hasMore,
    required this.nextCursor,
  });

  final List<TenantProductionBatch> items;
  final bool hasMore;
  final String? nextCursor;
}

/// Reads batches and builds the one a form may send.
final class TenantProductionRepository extends TenantReadRepository {
  TenantProductionRepository({
    required super.session,
    required TenantDataReader reader,
  }) : _collectionReader = reader,
       super(reader: reader);

  final TenantCollectionReader _collectionReader;

  /// The roles that receive and produce stock - `completeProduction`'s own
  /// list, and the rule's for reading batches.
  static const List<TenantRole> allowedRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
    TenantRole.manager,
  ];

  static bool canProduceInSession(TenantSession session) =>
      session.canAccess(allowedRoles: allowedRoles);

  /// Every batch, newest first.
  Future<TenantProductionPage> loadBatches({
    int pageSize = 20,
    String? cursor,
  }) async {
    _requireRole();
    final page = await readCollectionPage(
      TenantCollection.productionBatches,
      collectionReader: _collectionReader,
      pageSize: pageSize,
      cursor: cursor,
      descending: true,
      order: TenantCollectionOrder.createdAt,
    );
    return TenantProductionPage(
      items: <TenantProductionBatch>[
        for (final snapshot in page.items)
          TenantProductionBatch.fromSnapshot(snapshot),
      ],
      hasMore: page.hasMore,
      nextCursor: page.nextCursor,
    );
  }

  /// The last batch made of [productId], which the form starts the next one
  /// from - a baker records the same rows every morning.
  Future<TenantProductionBatch?> lastBatchOf(String productId) async {
    _requireRole();
    final page = await readCollectionPage(
      TenantCollection.productionBatches,
      collectionReader: _collectionReader,
      pageSize: 1,
      descending: true,
      order: TenantCollectionOrder.createdAt,
      equalityFilters: <String, Object?>{'productId': productId},
    );
    return page.items.isEmpty
        ? null
        : TenantProductionBatch.fromSnapshot(page.items.first);
  }

  /// Builds the one batch the typed form describes.
  TenantProductionIntent buildIntent({
    required TenantProduct product,
    required String quantity,
    required List<TenantProductionRowDraft> rows,
    required String requestId,
    required String businessDate,
  }) {
    _requireRole();
    if (product.tenantId != session.tenantId) {
      throw const TenantProductionException('production_forbidden');
    }
    if (product.retired) {
      throw const TenantProductionException('retired_product');
    }
    if (product.costType != TenantProductCostType.produced) {
      throw const TenantProductionException('not_made_here');
    }
    if (!_requestIdPattern.hasMatch(requestId)) {
      throw const TenantProductionException('invalid_request_id');
    }
    final units = int.tryParse(quantity.trim());
    if (units == null || units < 1 || units > maximumProductionQuantity) {
      throw const TenantProductionException('invalid_quantity');
    }
    final expenses = <TenantProductionExpense>[];
    for (final (index, row) in rows.indexed) {
      if (row.isBlank) continue;
      final description = row.description.trim().replaceAll(_whitespaceRun, ' ');
      if (description.isEmpty ||
          description.length > maximumProductionDescriptionLength ||
          _hasControl(description)) {
        throw TenantProductionException('invalid_description', row: index + 1);
      }
      final amountMinor = _amountOrNull(row.amount);
      if (amountMinor == null || amountMinor <= 0) {
        throw TenantProductionException('invalid_amount', row: index + 1);
      }
      expenses.add(
        TenantProductionExpense(
          description: description,
          amountMinor: amountMinor,
        ),
      );
    }
    if (expenses.isEmpty) {
      throw const TenantProductionException('no_costs');
    }
    if (expenses.length > maximumProductionExpenses) {
      throw const TenantProductionException('too_many_costs');
    }
    final total = expenses.fold(0, (sum, row) => sum + row.amountMinor);
    final unit = productionUnitCostMinor(total, units);
    if (unit < 1) {
      throw const TenantProductionException('cost_rounds_to_nothing');
    }
    if (unit > maximumProductionUnitCostMinor) {
      throw const TenantProductionException('cost_too_large');
    }
    final batchId = _deterministicBatchId(
      tenantId: session.tenantId,
      actorUid: session.uid,
      requestId: requestId,
    );
    return TenantProductionIntent._(
      tenantId: session.tenantId,
      batchId: batchId,
      batchNumber: productionBatchNumber(
        batchId: batchId,
        businessDate: businessDate,
      ),
      path: paths.productionBatch(batchId),
      product: product,
      quantity: units,
      expenses: List<TenantProductionExpense>.unmodifiable(expenses),
      totalCostMinor: total,
      unitCostMinor: unit,
    );
  }

  void _requireRole() {
    if (!canProduceInSession(session)) {
      throw const TenantProductionException('production_forbidden');
    }
  }
}

/// `PB-20260924-7F3A2C`: the business date, and six characters of the batch.
///
/// **Not a running sequence**, because batches are recorded on devices with no
/// connection and no two of those can share a counter. Six hexadecimal
/// characters of the batch's own digest make two batches on one day
/// practically impossible to confuse, with nothing stored on the device.
String productionBatchNumber({
  required String batchId,
  required String businessDate,
}) {
  final digest = batchId.startsWith('pb_') ? batchId.substring(3) : batchId;
  return 'PB-${businessDate.replaceAll('-', '')}-'
      '${digest.substring(0, 6).toUpperCase()}';
}

/// How a batch left this device.
final class TenantProductionWriteResult {
  const TenantProductionWriteResult.queued(this.operationId);

  final String operationId;
}

/// Where a batch is queued.
abstract interface class TenantProductionWriter {
  Future<TenantProductionWriteResult> complete(TenantProductionIntent intent);
}

/// A fresh request ID for one batch.
String secureTenantProductionRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'production-${base64Url.encode(bytes).replaceAll('=', '')}';
}

int? _amountOrNull(String value) {
  if (value.trim().isEmpty) return null;
  try {
    return tenantCatalogPriceMinorUnits(
      value,
      invalidCode: 'invalid_amount',
      unrepresentableCode: 'invalid_amount',
    );
  } on TenantCatalogManagementException {
    return null;
  }
}

String _deterministicBatchId({
  required String tenantId,
  required String actorUid,
  required String requestId,
}) {
  final digest = sha256.convert(
    utf8.encode(
      <String>['completeProduction', tenantId, actorUid, requestId].join(' '),
    ),
  );
  return 'pb_${digest.toString().substring(0, 40)}';
}

bool _hasControl(String value) {
  for (final codeUnit in value.codeUnits) {
    if (codeUnit < 0x20 || (codeUnit >= 0x7f && codeUnit <= 0x9f)) return true;
  }
  return false;
}

final RegExp _whitespaceRun = RegExp(r'\s+');
final RegExp _requestIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$');
