import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_paths.dart';
import '../tenancy/tenant_session.dart';
import 'checkout_outbox.dart';
import 'checkout_receipt.dart';
import 'checkout_tender.dart';

/// Schema version every new local checkout payload is built at.
const int checkoutSalePayloadSchemaVersion = 2;

/// The first schema version that records how the customer paid.
const int checkoutSaleTenderSchemaVersion = 2;

/// Every payload version this client can still parse and submit.
///
/// Version 1 predates the tender decision and stays supported on purpose. The
/// payload hash is a SHA-256 over the *whole* payload, so migrating a stored
/// draft to v2 would change its hash - and an outbox record already in
/// `awaiting_confirmation` was hashed under v1 and is waiting on a server sale
/// that carries exactly that hash. Rewriting it would break the only evidence
/// that can settle it. So a v1 payload is never rewritten, never re-versioned,
/// and submits unchanged; only new drafts are v2.
const Set<int> supportedCheckoutSalePayloadSchemaVersions = <int>{1, 2};

/// Firestore Rules validate at most sixteen explicit sale lines.
const int maximumCheckoutSaleLines = 16;

/// The largest quantity accepted on one immutable sale line.
const int maximumCheckoutLineQuantity = 1000000;

/// The largest sale amount, in integer minor currency units.
const int maximumCheckoutMinorAmount = 100000000000;

const int _maximumLineQuantity = maximumCheckoutLineQuantity;
const int _maximumMinorAmount = maximumCheckoutMinorAmount;
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
  'receiptNumber',
  'receiptSequence',
  'tender',
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
    required this.schemaVersion,
    required this.tender,
    required this.currency,
    required this.businessDate,
    required this.clientCreatedAtMs,
    required this.shiftId,
    required this.deviceId,
    required this.receiptNumber,
    required this.receiptSequence,
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
    DateTime? now,
  }) {
    if (!session.canAccess(now: now)) {
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
    return CheckoutSalePayload.fromLocalPayload(
      session: session,
      checkoutId: record.checkoutId,
      payload: record.payload,
      payloadHash: record.payloadHash,
      now: now,
    );
  }

  /// Parses a locally constructed payload before it becomes durable evidence.
  ///
  /// Draft builders use this to prove the frozen contract holds while the
  /// checkout can still be refused, rather than after it has been persisted.
  factory CheckoutSalePayload.fromLocalPayload({
    required TenantSession session,
    required String checkoutId,
    required Map<String, Object?> payload,
    required String payloadHash,
    /// The instant the session's standing is judged against.
    ///
    /// **Threaded rather than read from the wall clock**, because a provisional
    /// trading window turned "is this session usable" into a question with a
    /// time in it. The draft builder stamps a business date and a receipt
    /// sequence from its own clock and must judge the session from the same one,
    /// or it can refuse a sale the rest of the same method would have built.
    /// Absent, this is the wall clock, which is what every production caller
    /// wants and what every caller had before the window existed.
    DateTime? now,
  }) {
    if (!session.canAccess(now: now)) {
      throw const CheckoutSaleFormatException(
        'An active canonical session is required to parse a checkout.',
      );
    }
    final String safeCheckoutId;
    try {
      safeCheckoutId = validateTenantDocumentId(
        checkoutId,
        fieldName: 'checkoutId',
      );
    } on ArgumentError {
      throw const CheckoutSaleFormatException(
        'checkoutId must be a document ID.',
      );
    }
    if (checkoutPayloadHash(payload) != payloadHash) {
      throw const CheckoutSaleFormatException(
        'The payload hash does not describe this exact payload.',
      );
    }

    for (final key in payload.keys) {
      if (!_allowedPayloadKeys.contains(key)) {
        throw CheckoutSaleFormatException('Unsupported payload field $key.');
      }
    }
    final schemaVersion = payload['schemaVersion'];
    if (schemaVersion is! int ||
        !supportedCheckoutSalePayloadSchemaVersions.contains(schemaVersion)) {
      throw const CheckoutSaleFormatException(
        'Unsupported checkout payload schema version.',
      );
    }
    final tender = _requiredTender(payload, schemaVersion);
    if (payload['checkoutId'] != safeCheckoutId) {
      throw const CheckoutSaleFormatException(
        'The payload checkout ID is not the immutable outbox checkout ID.',
      );
    }
    if (payload['tenantId'] != session.tenantId) {
      throw const CheckoutSaleFormatException(
        'The payload tenant ID is not the immutable outbox tenant ID.',
      );
    }
    if (payload['soldById'] != session.uid) {
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
    // Every sale is attributed to exactly one shift. Reconciliation compares
    // sale-derived totals against the shift document, so an unattributed sale
    // could never be reconciled and is refused before it becomes evidence.
    final shiftId = _requiredDocumentId(payload, 'shiftId');
    final deviceId = _requiredDeviceId(payload);
    final receiptSequence = _requiredInt(
      payload,
      'receiptSequence',
      minimum: 1,
      maximum: maximumCheckoutReceiptSequence,
    );
    final receiptNumber = _requiredReceiptNumber(
      payload,
      deviceId: deviceId,
      businessDate: businessDate,
      sequence: receiptSequence,
    );
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
      uid: session.uid,
      tenantId: session.tenantId,
      checkoutId: safeCheckoutId,
      payloadHash: payloadHash,
      schemaVersion: schemaVersion,
      tender: tender,
      currency: currency,
      businessDate: businessDate,
      clientCreatedAtMs: clientCreatedAtMs,
      shiftId: shiftId,
      deviceId: deviceId,
      receiptNumber: receiptNumber,
      receiptSequence: receiptSequence,
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

  /// The version this exact payload was written at, not the current constant.
  ///
  /// The sale document repeats it, so a v1 draft submitted after the upgrade
  /// describes itself honestly instead of claiming a contract it never met.
  final int schemaVersion;

  /// How the cashier said the customer paid, absent on a schema v1 payload.
  ///
  /// See [CheckoutTender]: this is an assertion made at the till, and no
  /// payment was authorized, queried, or reconciled anywhere.
  final CheckoutTender? tender;

  final String currency;
  final String businessDate;
  final int clientCreatedAtMs;

  /// The canonical shift this sale belongs to, in this tenant and business day.
  final String shiftId;

  /// The durable installation identity that issued [receiptNumber].
  final String deviceId;

  /// The customer-facing receipt, unique per device and business date.
  final String receiptNumber;

  /// The device-local daily sequence embedded in [receiptNumber].
  final int receiptSequence;

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
    'payloadSchemaVersion': schemaVersion,
    if (tender != null) 'tender': tender!.wireValue,
    'currency': currency,
    'businessDate': businessDate,
    'clientCreatedAtMs': clientCreatedAtMs,
    'shiftId': shiftId,
    'deviceId': deviceId,
    'receiptNumber': receiptNumber,
    'receiptSequence': receiptSequence,
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

/// Reads the tender exactly as the payload's own schema version requires it.
///
/// A v2 payload must name one of the three modelled methods; anything else -
/// absent, misspelled, differently cased, or a type that is not a string - is
/// refused rather than recorded as an unknown payment. A v1 payload must not
/// carry the key at all: it was hashed without one, and a v1 draft that grew a
/// tender locally would be a payload nobody agreed to.
CheckoutTender? _requiredTender(Map<String, Object?> payload, int schemaVersion) {
  if (schemaVersion < checkoutSaleTenderSchemaVersion) {
    if (payload.containsKey('tender')) {
      throw const CheckoutSaleFormatException(
        'A schema v1 checkout cannot record a tender.',
      );
    }
    return null;
  }
  final tender = CheckoutTender.tryParse(payload['tender']);
  if (tender == null) {
    throw const CheckoutSaleFormatException(
      'tender must name one of the recorded payment methods.',
    );
  }
  return tender;
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
  try {
    return validateCheckoutBusinessDate(value);
  } on ArgumentError {
    throw CheckoutSaleFormatException(
      '$field must be a calendar date in yyyy-MM-dd format.',
    );
  }
}

/// The durable installation identity is mandatory: a receipt is meaningless
/// without the device whose sequence issued it.
String _requiredDeviceId(Map<String, Object?> map) {
  final value = _requiredDocumentId(map, 'deviceId');
  try {
    return validateCheckoutDeviceId(value);
  } on ArgumentError {
    throw const CheckoutSaleFormatException(
      'deviceId must be a durable installation identifier.',
    );
  }
}

/// Proves the receipt was derived from this exact device, date, and sequence.
///
/// A locally altered receipt therefore fails before submission, and Firestore
/// Rules independently reject a receipt that disagrees with the sale envelope.
String _requiredReceiptNumber(
  Map<String, Object?> map, {
  required String deviceId,
  required String businessDate,
  required int sequence,
}) {
  final value = _requiredString(map, 'receiptNumber');
  if (!checkoutReceiptNumberPattern.hasMatch(value)) {
    throw const CheckoutSaleFormatException(
      'receiptNumber must use the frozen CT-<device>-<date>-<sequence> shape.',
    );
  }
  final expected = formatCheckoutReceiptNumber(
    deviceId: deviceId,
    businessDate: businessDate,
    sequence: sequence,
  );
  if (value != expected) {
    throw const CheckoutSaleFormatException(
      'receiptNumber does not describe this device, business date, and '
      'sequence.',
    );
  }
  return value;
}
