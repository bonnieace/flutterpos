/// One supplier delivery: what the form holds, the pages it is sent in, and the
/// record it becomes.
///
/// **Every rule mirrors `functions/src/operations/supplierDeliveries.ts`**, so a
/// page is never refused for something the form could have caught - a refused
/// page strands every later page of the same delivery on this device, and
/// nothing in the app can clear it.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../checkout/checkout_draft.dart';
import '../inventory/catalog_management.dart';
import '../tenancy/tenant_catalog.dart';
import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_instant_range.dart';
import '../tenancy/tenant_paths.dart';
import '../tenancy/tenant_repository.dart';
import 'supplier.dart';

/// The server's `MAXIMUM_DELIVERY_PAGE_LINES`: three writes a line, fifty a
/// transaction.
const int maximumDeliveryPageLines = 16;

/// The most lines one delivery holds: the server's thirteen pages, rounded
/// down to a figure a form can state.
const int maximumDeliveryLines = 200;

/// The server's `MAXIMUM_IMPORT_OPENING_STOCK`, the most one line may bring in.
const int maximumDeliveryLineQuantity = 1000000;

const int maximumDeliveryReferenceLength = 64;

/// Raised when a delivery is refused before anything is queued.
final class TenantSupplierDeliveryException implements Exception {
  const TenantSupplierDeliveryException(this.code, {this.productName});

  final String code;

  /// The product a line-level refusal is about, so the form can name it.
  final String? productName;

  @override
  String toString() => 'TenantSupplierDeliveryException($code)';
}

/// One product line as the form holds it, typed.
final class TenantDeliveryLineDraft {
  const TenantDeliveryLineDraft({
    required this.product,
    this.quantity = '',
    this.unitCost = '',
  });

  final TenantProduct product;
  final String quantity;
  final String unitCost;

  TenantDeliveryLineDraft copyWith({String? quantity, String? unitCost}) =>
      TenantDeliveryLineDraft(
        product: product,
        quantity: quantity ?? this.quantity,
        unitCost: unitCost ?? this.unitCost,
      );
}

/// One validated line, and what it will do to its product.
final class TenantDeliveryLine {
  const TenantDeliveryLine._({
    required this.product,
    required this.quantity,
    required this.unitCostMinor,
  });

  final TenantProduct product;
  final int quantity;

  /// Null when the line names no cost, which leaves the product's cost alone.
  final int? unitCostMinor;

  int get quantityAfter => product.quantity + quantity;

  /// The cost the product holds now, in minor units, or null when none is
  /// recorded or it cannot be represented.
  int? get previousCostMinor =>
      product.cost == null ? null : checkoutMinorUnitsFromMajor(product.cost!);

  /// Whether receiving this line changes what the product costs.
  bool get changesCost =>
      unitCostMinor != null && unitCostMinor != previousCostMinor;

  Map<String, Object?> toPayload() => <String, Object?>{
    'productId': product.id,
    'productName': product.name,
    'quantity': quantity,
    if (unitCostMinor != null) 'unitCost': unitCostMinor! / 100,
  };
}

/// A validated delivery, and the pages it is sent in.
final class TenantSupplierDeliveryIntent {
  const TenantSupplierDeliveryIntent._({
    required this.tenantId,
    required this.deliveryId,
    required this.path,
    required this.supplier,
    required this.reference,
    required this.lines,
  });

  final String tenantId;
  final String deliveryId;
  final String path;
  final TenantSupplier supplier;
  final String? reference;
  final List<TenantDeliveryLine> lines;

  int get unitCount => lines.fold(0, (sum, line) => sum + line.quantity);

  /// The lines cut into pages of [maximumDeliveryPageLines], in the order they
  /// were entered. Every page shares the delivery's path, so the queue carries
  /// them in order.
  List<TenantSupplierDeliveryPageIntent> pages() {
    final pages = <TenantSupplierDeliveryPageIntent>[];
    for (var start = 0; start < lines.length; start += maximumDeliveryPageLines) {
      final page = start ~/ maximumDeliveryPageLines;
      final end = min(start + maximumDeliveryPageLines, lines.length);
      pages.add(
        TenantSupplierDeliveryPageIntent._(
          tenantId: tenantId,
          deliveryId: deliveryId,
          path: path,
          page: page,
          payload: <String, Object?>{
            'tenantId': tenantId,
            'deliveryId': deliveryId,
            'supplierId': supplier.id,
            'reference': reference,
            'page': page,
            'isFinalPage': end == lines.length,
            'lines': <Map<String, Object?>>[
              for (final line in lines.sublist(start, end)) line.toPayload(),
            ],
          },
        ),
      );
    }
    return pages;
  }
}

/// One page, as the queue carries it.
final class TenantSupplierDeliveryPageIntent {
  const TenantSupplierDeliveryPageIntent._({
    required this.tenantId,
    required this.deliveryId,
    required this.path,
    required this.page,
    required this.payload,
  });

  final String tenantId;
  final String deliveryId;
  final String path;
  final int page;
  final Map<String, Object?> payload;

  /// **Zero-padded, and that is load-bearing.** The queue orders one path's
  /// records by when they were queued and then by operation ID as a string,
  /// and every page of a delivery is queued in the same instant - so without
  /// the padding page ten would drain before page two.
  String get operationId =>
      'supplier-delivery-$deliveryId-p${page.toString().padLeft(3, '0')}';
}

/// One delivery as `supplier_deliveries/{deliveryId}` holds it.
final class TenantSupplierDelivery {
  TenantSupplierDelivery.fromDocument({
    required String path,
    required Map<String, Object?> data,
  }) : id = _deliveryId(path),
       tenantId = validateTenantId(path.split('/')[1]),
       supplierId = _requiredString(data, 'supplierId'),
       supplierName = _optionalString(data['supplierName']),
       reference = _optionalString(data['reference']),
       actorUid = _optionalString(data['actorUid']),
       createdAt = tenantStoredInstant(data['createdAt']),
       lines = _lines(data['lines']),
       complete = data['complete'] == true;

  factory TenantSupplierDelivery.fromSnapshot(
    TenantQueryDocumentSnapshot snapshot,
  ) => TenantSupplierDelivery.fromDocument(
    path: snapshot.path,
    data: snapshot.data,
  );

  final String id;
  final String tenantId;
  final String supplierId;

  /// The supplier's name as it stood when the stock arrived.
  final String? supplierName;
  final String? reference;
  final String? actorUid;
  final DateTime? createdAt;
  final List<TenantSupplierDeliveryRecordLine> lines;

  /// Whether every page of the delivery has landed on the server.
  final bool complete;

  int get unitCount => lines.fold(0, (sum, line) => sum + line.quantity);

  /// What the delivered stock cost, over the lines that named a cost.
  int get valueMinor => lines.fold(
    0,
    (sum, line) =>
        line.unitCostMinor == null ? sum : sum + line.quantity * line.unitCostMinor!,
  );

  int get costlessLineCount =>
      lines.where((line) => line.unitCostMinor == null).length;

  static String _deliveryId(String path) {
    final parts = path.split('/');
    if (parts.length != 4 ||
        parts[0] != 'tenants' ||
        parts[2] != TenantCollection.supplierDeliveries.segment) {
      throw const FormatException('Not a supplier delivery.');
    }
    return validateTenantDocumentId(parts[3], fieldName: 'deliveryId');
  }

  static String _requiredString(Map<String, Object?> data, String field) {
    final value = data[field];
    if (value is! String || value.isEmpty) {
      throw FormatException('A delivery must carry $field.');
    }
    return value;
  }

  static String? _optionalString(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  static List<TenantSupplierDeliveryRecordLine> _lines(Object? value) {
    if (value is! List) return const <TenantSupplierDeliveryRecordLine>[];
    return List<TenantSupplierDeliveryRecordLine>.unmodifiable(<
      TenantSupplierDeliveryRecordLine
    >[
      for (final line in value)
        if (line is Map &&
            line['productId'] is String &&
            line['quantity'] is int)
          TenantSupplierDeliveryRecordLine(
            productId: line['productId'] as String,
            productName: line['productName'] is String
                ? line['productName'] as String
                : line['productId'] as String,
            quantity: line['quantity'] as int,
            unitCostMinor: line['unitCostMinor'] is int
                ? line['unitCostMinor'] as int
                : null,
            previousCostMinor: line['previousCostMinor'] is int
                ? line['previousCostMinor'] as int
                : null,
          ),
    ]);
  }
}

/// One product line of a recorded delivery.
final class TenantSupplierDeliveryRecordLine {
  const TenantSupplierDeliveryRecordLine({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitCostMinor,
    required this.previousCostMinor,
  });

  final String productId;
  final String productName;
  final int quantity;
  final int? unitCostMinor;
  final int? previousCostMinor;
}

/// One page of one supplier's delivery history, newest first.
final class TenantSupplierDeliveryPage {
  const TenantSupplierDeliveryPage({
    required this.items,
    required this.hasMore,
    required this.nextCursor,
  });

  final List<TenantSupplierDelivery> items;
  final bool hasMore;
  final String? nextCursor;
}

/// Reads deliveries and builds the one a form may send.
final class TenantSupplierDeliveryRepository extends TenantReadRepository {
  TenantSupplierDeliveryRepository({
    required super.session,
    required TenantDataReader reader,
  }) : _collectionReader = reader,
       super(reader: reader);

  final TenantCollectionReader _collectionReader;

  /// One supplier's deliveries, newest first.
  ///
  /// Served by the `supplierId` + `createdAt` composite index; offline, by the
  /// device's own copy, with a queued delivery drawn over it.
  Future<TenantSupplierDeliveryPage> loadForSupplier(
    String supplierId, {
    int pageSize = 10,
    String? cursor,
  }) async {
    _requireRole();
    final page = await readCollectionPage(
      TenantCollection.supplierDeliveries,
      collectionReader: _collectionReader,
      pageSize: pageSize,
      cursor: cursor,
      descending: true,
      order: TenantCollectionOrder.createdAt,
      equalityFilters: <String, Object?>{'supplierId': supplierId},
    );
    return TenantSupplierDeliveryPage(
      items: <TenantSupplierDelivery>[
        for (final snapshot in page.items)
          TenantSupplierDelivery.fromSnapshot(snapshot),
      ],
      hasMore: page.hasMore,
      nextCursor: page.nextCursor,
    );
  }

  /// Every delivery recorded between [startAt] and [endAt], a page at a time,
  /// ordered by when it was recorded.
  ///
  /// **Forwarded past the overlay, never drawn from it**, like every period
  /// read: a report states what the server holds, and a delivery still on this
  /// device is not yet something the business's records say.
  Future<
    ({List<TenantSupplierDelivery> items, TenantInstantRangePosition? next})
  >
  loadRange({
    required DateTime startAt,
    required DateTime endAt,
    int pageSize = 50,
    TenantInstantRangePosition? startAfter,
  }) async {
    _requireRole();
    final page = await tenantInstantRangePage(
      reader: _collectionReader,
      collectionPath: paths.collectionPath(TenantCollection.supplierDeliveries),
      startAt: startAt,
      endAt: endAt,
      pageSize: pageSize,
      startAfter: startAfter,
    );
    return (
      items: <TenantSupplierDelivery>[
        for (final snapshot in page.items)
          TenantSupplierDelivery.fromSnapshot(snapshot),
      ],
      next: page.next,
    );
  }

  /// How many restocks were recorded between [startAt] and [endAt] with no
  /// supplier named - stock that arrived through *Adjust stock* rather than as
  /// a delivery - read up to [maximumPages] pages.
  Future<({int count, bool truncated})> countRestocksWithoutSupplier({
    required DateTime startAt,
    required DateTime endAt,
    int maximumPages = 12,
  }) async {
    _requireRole();
    var count = 0;
    TenantInstantRangePosition? position;
    for (var page = 0; page < maximumPages; page++) {
      final read = await tenantInstantRangePage(
        reader: _collectionReader,
        collectionPath: paths.collectionPath(TenantCollection.stockAdjustments),
        startAt: startAt,
        endAt: endAt,
        pageSize: 50,
        startAfter: position,
      );
      for (final snapshot in read.items) {
        if (snapshot.data['sourceType'] == 'manual_adjustment' &&
            snapshot.data['adjustmentType'] == 'restock') {
          count++;
        }
      }
      position = read.next;
      if (position == null) return (count: count, truncated: false);
    }
    return (count: count, truncated: true);
  }

  /// An earlier delivery from [supplierId] under [reference], or null.
  ///
  /// **A warning, never a refusal.** Product decided against duplicate-invoice
  /// protection; this only lets the form say "ABC already has a delivery with
  /// that reference" so a person can check before stocking the shelf twice.
  Future<TenantSupplierDelivery?> findByReference({
    required String supplierId,
    required String reference,
  }) async {
    _requireRole();
    final page = await readCollectionPage(
      TenantCollection.supplierDeliveries,
      collectionReader: _collectionReader,
      pageSize: 1,
      equalityFilters: <String, Object?>{
        'supplierId': supplierId,
        'reference': reference,
      },
    );
    return page.items.isEmpty
        ? null
        : TenantSupplierDelivery.fromSnapshot(page.items.first);
  }

  /// Builds the one delivery the typed form describes.
  TenantSupplierDeliveryIntent buildIntent({
    required TenantSupplier supplier,
    required String reference,
    required List<TenantDeliveryLineDraft> lines,
    required String requestId,
  }) {
    _requireRole();
    if (supplier.tenantId != session.tenantId) {
      throw const TenantSupplierDeliveryException('delivery_forbidden');
    }
    if (!supplier.active) {
      throw const TenantSupplierDeliveryException('inactive_supplier');
    }
    if (!_requestIdPattern.hasMatch(requestId)) {
      throw const TenantSupplierDeliveryException('invalid_request_id');
    }
    final safeReference = normalizeDeliveryReference(reference);
    if (lines.isEmpty) {
      throw const TenantSupplierDeliveryException('no_lines');
    }
    if (lines.length > maximumDeliveryLines) {
      throw const TenantSupplierDeliveryException('too_many_lines');
    }
    final seen = <String>{};
    final validated = <TenantDeliveryLine>[];
    for (final line in lines) {
      final product = line.product;
      if (product.tenantId != session.tenantId) {
        throw const TenantSupplierDeliveryException('delivery_forbidden');
      }
      if (!seen.add(product.id)) {
        throw TenantSupplierDeliveryException(
          'duplicate_product',
          productName: product.name,
        );
      }
      if (product.retired) {
        throw TenantSupplierDeliveryException(
          'retired_product',
          productName: product.name,
        );
      }
      final quantity = int.tryParse(line.quantity.trim());
      if (quantity == null ||
          quantity < 1 ||
          quantity > maximumDeliveryLineQuantity) {
        throw TenantSupplierDeliveryException(
          'invalid_quantity',
          productName: product.name,
        );
      }
      int? unitCostMinor;
      if (line.unitCost.trim().isNotEmpty) {
        try {
          unitCostMinor = tenantCatalogPriceMinorUnits(
            line.unitCost,
            invalidCode: 'invalid_cost',
            unrepresentableCode: 'cost_not_representable',
          );
        } on TenantCatalogManagementException {
          throw TenantSupplierDeliveryException(
            'invalid_unit_cost',
            productName: product.name,
          );
        }
        if (unitCostMinor <= 0) {
          throw TenantSupplierDeliveryException(
            'invalid_unit_cost',
            productName: product.name,
          );
        }
      }
      // Stock at the edge of the safe range cannot take more; the server would
      // refuse the page, so the form does first.
      if (product.quantity + quantity > maximumStockQuantity) {
        throw TenantSupplierDeliveryException(
          'quantity_out_of_range',
          productName: product.name,
        );
      }
      validated.add(
        TenantDeliveryLine._(
          product: product,
          quantity: quantity,
          unitCostMinor: unitCostMinor,
        ),
      );
    }
    final deliveryId = _deterministicDeliveryId(
      tenantId: session.tenantId,
      actorUid: session.uid,
      requestId: requestId,
    );
    return TenantSupplierDeliveryIntent._(
      tenantId: session.tenantId,
      deliveryId: deliveryId,
      path: paths.supplierDelivery(deliveryId),
      supplier: supplier,
      reference: safeReference,
      lines: List<TenantDeliveryLine>.unmodifiable(validated),
    );
  }

  void _requireRole() {
    if (!TenantSupplierRepository.canManageInSession(session)) {
      throw const TenantSupplierDeliveryException('delivery_forbidden');
    }
  }
}

/// The largest stock figure a product may hold, the till's safe bound.
const int maximumStockQuantity = 9007199254740991;

/// A reference trimmed and collapsed as the server stores it, null when blank.
String? normalizeDeliveryReference(String value) {
  final reference = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (reference.isEmpty) return null;
  if (reference.length > maximumDeliveryReferenceLength) {
    throw const TenantSupplierDeliveryException('invalid_reference');
  }
  for (final codeUnit in reference.codeUnits) {
    if (codeUnit < 0x20 || (codeUnit >= 0x7f && codeUnit <= 0x9f)) {
      throw const TenantSupplierDeliveryException('invalid_reference');
    }
  }
  return reference;
}

/// How a delivery left this device.
final class TenantSupplierDeliveryWriteResult {
  const TenantSupplierDeliveryWriteResult.queued(this.operationIds);

  final List<String> operationIds;
}

/// Where a delivery's pages are queued.
abstract interface class TenantSupplierDeliveryWriter {
  Future<TenantSupplierDeliveryWriteResult> receive(
    TenantSupplierDeliveryIntent intent,
  );
}

/// A fresh request ID for one delivery.
String secureTenantDeliveryRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'delivery-${base64Url.encode(bytes).replaceAll('=', '')}';
}

String _deterministicDeliveryId({
  required String tenantId,
  required String actorUid,
  required String requestId,
}) {
  final digest = sha256.convert(
    utf8.encode(
      <String>['receiveSupplierDelivery', tenantId, actorUid, requestId].join(' '),
    ),
  );
  return 'sd_${digest.toString().substring(0, 40)}';
}

final RegExp _requestIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$');
