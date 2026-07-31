import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_paths.dart';
import '../tenancy/tenant_session.dart';
import 'checkout_outbox.dart';

/// Frozen schema version of the immutable local checkout payload.
const int checkoutSalePayloadSchemaVersion = 1;

/// Firestore Rules validate at most sixteen explicit sale lines.
const int maximumCheckoutSaleLines = 16;

const int _maximumLineQuantity = 1000000;
const int _maximumMinorAmount = 100000000000;
const int _minorUnitsPerMajorUnit = 100;
const int _maximumClientCreatedAtMs = 4102444800000; // 2100-01-01T00:00:00Z.

const Set<String> _allowedPayloadKeys = <String>{
  'schemaVersion',
  'checkoutId',
  'tenantId',
  'soldById',
  'currency',
  'businessDate',
  'createdAtMs',
  'shiftId',
  'deviceId',
  'items',
  'subtotalMinor',
  'discountMinor',
  'totalMinor',
};

const Set<String> _allowedLineKeys = <String>{
  'productId',
  'name',
  'categoryId',
  'quantity',
  'unitPriceMinor',
  'unitCostMinor',
};

final RegExp _currencyPattern = RegExp(r'^[A-Z]{3}$');
final RegExp _isoDatePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// Raised when frozen local checkout evidence cannot be trusted for a write.
final class CheckoutSaleFormatException implements Exception {
  const CheckoutSaleFormatException(this.message);

  final String message;

  @override
  String toString() => 'CheckoutSaleFormatException: $message';
}

/// One immutable sale line captured when the checkout was saved offline.
///
/// Monetary values are integer minor currency units so the payload hash stays
/// deterministic. Major-unit numbers are derived only for the written document.
final class CheckoutSaleLine {
  const CheckoutSaleLine._({
    required this.productId,
    required this.name,
    required this.categoryId,
    required this.quantity,
    required this.unitPriceMinor,
    required this.lineTotalMinor,
    required this.unitCostMinor,
    required this.lineCostMinor,
  });

  final String productId;
  final String name;
  final String? categoryId;
  final int quantity;
  final int unitPriceMinor;
  final int lineTotalMinor;
  final int? unitCostMinor;
  final int? lineCostMinor;

  Map<String, Object?> toSaleLineFields() => <String, Object?>{
    'productId': productId,
    'name': name,
    if (categoryId != null) 'categoryId': categoryId,
    'quantity': quantity,
    'unitPriceMinor': unitPriceMinor,
    'unitPrice': _majorUnits(unitPriceMinor),
    'lineTotalMinor': lineTotalMinor,
    'lineTotal': _majorUnits(lineTotalMinor),
    if (unitCostMinor != null) 'unitCostMinor': unitCostMinor,
    if (unitCostMinor != null) 'unitCost': _majorUnits(unitCostMinor!),
    if (lineCostMinor != null) 'costMinor': lineCostMinor,
    if (lineCostMinor != null) 'cost': _majorUnits(lineCostMinor!),
  };
}

/// One product stock decrement derived from an immutable sale line.
final class CheckoutStockDecrement {
  const CheckoutStockDecrement._({
    required this.productPath,
    required this.productId,
    required this.quantityDelta,
  });

  final String productPath;
  final String productId;

  /// Always negative; positive stock changes require trusted server logic.
  final int quantityDelta;
}

/// The exact atomic write set produced by one checkout submission attempt.
///
/// The description is pure data: server sentinels are named rather than
/// constructed so the contract can be asserted without a Firebase dependency.
final class CheckoutSaleSubmission {
  CheckoutSaleSubmission._({
    required this.tenantId,
    required this.checkoutId,
    required this.salePath,
    required Map<String, Object?> saleFields,
    required List<String> saleServerTimestampFields,
    required List<CheckoutStockDecrement> stockDecrements,
    required this.stockServerTimestampFields,
  }) : saleFields = Map<String, Object?>.unmodifiable(saleFields),
       saleServerTimestampFields = List<String>.unmodifiable(
         saleServerTimestampFields,
       ),
       stockDecrements = List<CheckoutStockDecrement>.unmodifiable(
         stockDecrements,
       );

  final String tenantId;
  final String checkoutId;
  final String salePath;
  final Map<String, Object?> saleFields;
  final List<String> saleServerTimestampFields;
  final List<CheckoutStockDecrement> stockDecrements;
  final List<String> stockServerTimestampFields;
}

/// Strict read model for the frozen `saved_offline` checkout payload.
///
/// Parsing proves the immutable checkout identity, the authenticated UID, the
/// selected tenant, bounded positive integer quantities, unique tenant-local
/// product IDs, and an internally consistent monetary snapshot before any
/// Firestore write is attempted.
final class CheckoutSalePayload {
  CheckoutSalePayload._({
    required this.uid,
    required this.tenantId,
    required this.checkoutId,
    required this.payloadHash,
    required this.currency,
    required this.businessDate,
    required this.clientCreatedAtMs,
    required this.shiftId,
    required this.deviceId,
    required List<CheckoutSaleLine> lines,
    required this.subtotalMinor,
    required this.discountMinor,
    required this.totalMinor,
  }) : lines = List<CheckoutSaleLine>.unmodifiable(lines),
       _paths = TenantPaths(tenantId);

  /// Parses [record] against the live [session] that owns the submission.
  factory CheckoutSalePayload.fromOutboxRecord(
    CheckoutOutboxRecord record, {
    required TenantSession session,
  }) {
    if (!session.canAccess()) {
      throw const CheckoutSaleFormatException(
        'An active canonical session is required to parse a checkout.',
      );
    }
    if (record.uid != session.uid) {
      throw const CheckoutSaleFormatException(
        'The checkout belongs to another authenticated user.',
      );
    }
    if (record.tenantId != session.tenantId) {
      throw const CheckoutSaleFormatException(
        'The checkout belongs to another tenant.',
      );
    }

    final payload = record.payload;
    for (final key in payload.keys) {
      if (!_allowedPayloadKeys.contains(key)) {
        throw CheckoutSaleFormatException('Unsupported payload field $key.');
      }
    }
    if (payload['schemaVersion'] != checkoutSalePayloadSchemaVersion) {
      throw const CheckoutSaleFormatException(
        'Unsupported checkout payload schema version.',
      );
    }
    if (payload['checkoutId'] != record.checkoutId) {
      throw const CheckoutSaleFormatException(
        'The payload checkout ID is not the immutable outbox checkout ID.',
      );
    }
    if (payload['tenantId'] != record.tenantId) {
      throw const CheckoutSaleFormatException(
        'The payload tenant ID is not the immutable outbox tenant ID.',
      );
    }
    if (payload['soldById'] != record.uid) {
      throw const CheckoutSaleFormatException(
        'The payload cashier is not the authenticated outbox user.',
      );
    }

    final currency = _requiredString(payload, 'currency');
    if (!_currencyPattern.hasMatch(currency)) {
      throw const CheckoutSaleFormatException(
        'currency must be a three-letter ISO 4217 code.',
      );
    }
    final businessDate = _requiredIsoDate(payload, 'businessDate');
    final clientCreatedAtMs = _requiredInt(
      payload,
      'createdAtMs',
      minimum: 1,
      maximum: _maximumClientCreatedAtMs,
    );
    final shiftId = _optionalDocumentId(payload, 'shiftId');
    final deviceId = _optionalDocumentId(payload, 'deviceId');
    final lines = _parseLines(payload['items']);

    var subtotalMinor = 0;
    for (final line in lines) {
      subtotalMinor += line.lineTotalMinor;
      if (subtotalMinor > _maximumMinorAmount) {
        throw const CheckoutSaleFormatException(
          'The checkout subtotal exceeds the supported monetary bound.',
        );
      }
    }
    if (_requiredInt(payload, 'subtotalMinor', minimum: 0) != subtotalMinor) {
      throw const CheckoutSaleFormatException(
        'subtotalMinor must equal the sum of the immutable line totals.',
      );
    }
    final discountMinor = _requiredInt(
      payload,
      'discountMinor',
      minimum: 0,
      maximum: subtotalMinor,
    );
    final totalMinor = _requiredInt(payload, 'totalMinor', minimum: 0);
    if (totalMinor != subtotalMinor - discountMinor) {
      throw const CheckoutSaleFormatException(
        'totalMinor must equal subtotalMinor minus discountMinor.',
      );
    }

    return CheckoutSalePayload._(
      uid: record.uid,
      tenantId: record.tenantId,
      checkoutId: record.checkoutId,
      payloadHash: record.payloadHash,
      currency: currency,
      businessDate: businessDate,
      clientCreatedAtMs: clientCreatedAtMs,
      shiftId: shiftId,
      deviceId: deviceId,
      lines: lines,
      subtotalMinor: subtotalMinor,
      discountMinor: discountMinor,
      totalMinor: totalMinor,
    );
  }

  final String uid;
  final String tenantId;
  final String checkoutId;
  final String payloadHash;
  final String currency;
  final String businessDate;
  final int clientCreatedAtMs;
  final String? shiftId;
  final String? deviceId;
  final List<CheckoutSaleLine> lines;
  final int subtotalMinor;
  final int discountMinor;
  final int totalMinor;
  final TenantPaths _paths;

  /// The deterministic canonical sale document path for this checkout.
  String get salePath => _paths.sale(checkoutId);

  /// The exact atomic write set for one submission attempt.
  CheckoutSaleSubmission toSubmission() => CheckoutSaleSubmission._(
    tenantId: tenantId,
    checkoutId: checkoutId,
    salePath: salePath,
    saleFields: _saleFields(),
    saleServerTimestampFields: const <String>['createdAt'],
    stockDecrements: <CheckoutStockDecrement>[
      for (final line in lines)
        CheckoutStockDecrement._(
          productPath: _paths.product(line.productId),
          productId: line.productId,
          quantityDelta: -line.quantity,
        ),
    ],
    stockServerTimestampFields: const <String>['updatedAt'],
  );

  Map<String, Object?> _saleFields() => <String, Object?>{
    'checkoutId': checkoutId,
    'tenantId': tenantId,
    'soldById': uid,
    'payloadHash': payloadHash,
    'payloadSchemaVersion': checkoutSalePayloadSchemaVersion,
    'currency': currency,
    'businessDate': businessDate,
    'clientCreatedAtMs': clientCreatedAtMs,
    if (shiftId != null) 'shiftId': shiftId,
    if (deviceId != null) 'deviceId': deviceId,
    'items': <Map<String, Object?>>[
      for (final line in lines) line.toSaleLineFields(),
    ],
    'subtotalMinor': subtotalMinor,
    'subtotal': _majorUnits(subtotalMinor),
    'discountMinor': discountMinor,
    'discount': _majorUnits(discountMinor),
    'totalMinor': totalMinor,
    'total': _majorUnits(totalMinor),
  };
}

List<CheckoutSaleLine> _parseLines(Object? raw) {
  if (raw is! List) {
    throw const CheckoutSaleFormatException('items must be a list.');
  }
  if (raw.isEmpty || raw.length > maximumCheckoutSaleLines) {
    throw CheckoutSaleFormatException(
      'items must contain between 1 and $maximumCheckoutSaleLines lines.',
    );
  }
  final lines = <CheckoutSaleLine>[];
  final productIds = <String>{};
  for (final entry in raw) {
    if (entry is! Map) {
      throw const CheckoutSaleFormatException('Each sale line must be a map.');
    }
    final line = <String, Object?>{};
    for (final key in entry.keys) {
      if (key is! String || !_allowedLineKeys.contains(key)) {
        throw CheckoutSaleFormatException('Unsupported sale line field $key.');
      }
      line[key] = entry[key];
    }
    final productId = _requiredDocumentId(line, 'productId');
    if (!productIds.add(productId)) {
      throw CheckoutSaleFormatException(
        'Product $productId appears in more than one sale line.',
      );
    }
    final quantity = _requiredInt(
      line,
      'quantity',
      minimum: 1,
      maximum: _maximumLineQuantity,
    );
    final unitPriceMinor = _requiredInt(
      line,
      'unitPriceMinor',
      minimum: 0,
      maximum: _maximumMinorAmount,
    );
    final unitCostMinor = _optionalInt(
      line,
      'unitCostMinor',
      minimum: 0,
      maximum: _maximumMinorAmount,
    );
    final lineTotalMinor = unitPriceMinor * quantity;
    if (lineTotalMinor > _maximumMinorAmount) {
      throw const CheckoutSaleFormatException(
        'A sale line total exceeds the supported monetary bound.',
      );
    }
    final lineCostMinor = unitCostMinor == null
        ? null
        : unitCostMinor * quantity;
    if (lineCostMinor != null && lineCostMinor > _maximumMinorAmount) {
      throw const CheckoutSaleFormatException(
        'A sale line cost exceeds the supported monetary bound.',
      );
    }
    lines.add(
      CheckoutSaleLine._(
        productId: productId,
        name: _requiredString(line, 'name'),
        categoryId: _optionalDocumentId(line, 'categoryId'),
        quantity: quantity,
        unitPriceMinor: unitPriceMinor,
        lineTotalMinor: lineTotalMinor,
        unitCostMinor: unitCostMinor,
        lineCostMinor: lineCostMinor,
      ),
    );
  }
  return lines;
}

double _majorUnits(int minorUnits) => minorUnits / _minorUnitsPerMajorUnit;

String _requiredString(Map<String, Object?> map, String field) {
  final value = map[field];
  if (value is! String || value.isEmpty || value != value.trim()) {
    throw CheckoutSaleFormatException(
      '$field must be a non-empty trimmed string.',
    );
  }
  for (final codeUnit in value.codeUnits) {
    if (codeUnit < 0x20 || codeUnit == 0x7f) {
      throw CheckoutSaleFormatException(
        '$field cannot contain control characters.',
      );
    }
  }
  return value;
}

String _requiredDocumentId(Map<String, Object?> map, String field) {
  final value = _requiredString(map, field);
  try {
    return validateTenantDocumentId(value, fieldName: field);
  } on ArgumentError {
    throw CheckoutSaleFormatException('$field must be a document ID.');
  }
}

String? _optionalDocumentId(Map<String, Object?> map, String field) {
  if (map[field] == null) return null;
  return _requiredDocumentId(map, field);
}

int _requiredInt(
  Map<String, Object?> map,
  String field, {
  required int minimum,
  int maximum = _maximumMinorAmount,
}) {
  final value = map[field];
  if (value is! int || value < minimum || value > maximum) {
    throw CheckoutSaleFormatException(
      '$field must be an integer between $minimum and $maximum.',
    );
  }
  return value;
}

int? _optionalInt(
  Map<String, Object?> map,
  String field, {
  required int minimum,
  required int maximum,
}) {
  if (map[field] == null) return null;
  return _requiredInt(map, field, minimum: minimum, maximum: maximum);
}

String _requiredIsoDate(Map<String, Object?> map, String field) {
  final value = _requiredString(map, field);
  final match = _isoDatePattern.firstMatch(value);
  if (match == null) {
    throw CheckoutSaleFormatException('$field must use yyyy-MM-dd format.');
  }
  final date = DateTime.utc(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
  if (date.toIso8601String().substring(0, 10) != value) {
    throw CheckoutSaleFormatException('$field is not a calendar date.');
  }
  return value;
}
