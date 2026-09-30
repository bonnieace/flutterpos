import '../checkout/checkout_receipt.dart';
import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_paths.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_types.dart';
import 'sale_history.dart';

/// Raised when a receipt cannot be looked up in this business.
final class TenantReceiptLookupException implements Exception {
  const TenantReceiptLookupException(this.code);

  final String code;

  @override
  String toString() => 'TenantReceiptLookupException($code)';
}

/// A receipt number that has been proved to be well formed.
///
/// The shape, the embedded device code, the business date, and the sequence are
/// parsed by `checkout_receipt.dart`, which owns the frozen format. Nothing
/// here re-implements it, so the lookup and the issuing device can never
/// disagree about what a receipt is.
final class TenantReceiptQuery {
  factory TenantReceiptQuery.parse(String value) {
    final receipt = value.trim().toUpperCase();
    if (!checkoutReceiptNumberPattern.hasMatch(receipt)) {
      throw const TenantReceiptLookupException('invalid_receipt_number');
    }
    final parts = receipt.split('-');
    final compactDate = parts[2];
    final businessDate =
        '${compactDate.substring(0, 4)}-${compactDate.substring(4, 6)}-'
        '${compactDate.substring(6, 8)}';
    try {
      validateCheckoutBusinessDate(businessDate);
    } on ArgumentError {
      throw const TenantReceiptLookupException('invalid_receipt_number');
    }
    final sequence = int.parse(parts[3]);
    if (sequence < 1 || sequence > maximumCheckoutReceiptSequence) {
      throw const TenantReceiptLookupException('invalid_receipt_number');
    }
    return TenantReceiptQuery._(
      receiptNumber: receipt,
      deviceCode: parts[1],
      businessDate: businessDate,
      sequence: sequence,
    );
  }

  const TenantReceiptQuery._({
    required this.receiptNumber,
    required this.deviceCode,
    required this.businessDate,
    required this.sequence,
  });

  final String receiptNumber;

  /// The three-character digest of the issuing device's installation ID. It is
  /// deliberately not reversible, so it identifies no device on its own.
  final String deviceCode;
  final String businessDate;
  final int sequence;
}

/// A daily receipt sequence entered without the predictable receipt prefix.
///
/// Receipt sequences restart for every device and business day, so this query
/// always carries the selected day and may legitimately match several tills.
final class TenantReceiptEndingQuery {
  factory TenantReceiptEndingQuery.parse({
    required String businessDate,
    required String ending,
    String? maximumBusinessDate,
  }) {
    final String date;
    try {
      date = validateCheckoutBusinessDate(businessDate);
      if (maximumBusinessDate case final maximum?) {
        final upperBound = validateCheckoutBusinessDate(maximum);
        if (date.compareTo(upperBound) > 0) {
          throw const TenantReceiptLookupException('future_business_date');
        }
      }
    } on TenantReceiptLookupException {
      rethrow;
    } on ArgumentError {
      throw const TenantReceiptLookupException('invalid_business_date');
    }

    final normalized = ending.trim();
    // **The number printed on the receipt, since 2026-09-29** -
    // `JOHN-CT-7F2-001`. It carries the till's code and sequence but no date,
    // which is exactly what this query adds, so it is read here rather than
    // refused. The till's code then narrows the day's matches to one till.
    if (parsePrintedCheckoutReceipt(normalized) case final printed?) {
      return TenantReceiptEndingQuery._(
        businessDate: date,
        sequence: printed.sequence,
        deviceCode: printed.deviceCode,
        displayEnding:
            '$checkoutReceiptPrefix-${printed.deviceCode}-'
            '${printed.sequence.toString().padLeft(printedReceiptSequenceDigits, '0')}',
      );
    }
    if (!RegExp(r'^\d{1,6}$').hasMatch(normalized)) {
      throw const TenantReceiptLookupException('invalid_receipt_ending');
    }
    final sequence = int.parse(normalized);
    if (sequence < 1 || sequence > maximumCheckoutReceiptSequence) {
      throw const TenantReceiptLookupException('invalid_receipt_ending');
    }
    return TenantReceiptEndingQuery._(
      businessDate: date,
      sequence: sequence,
      displayEnding: sequence.toString().padLeft(
        checkoutReceiptSequenceDigits,
        '0',
      ),
    );
  }

  const TenantReceiptEndingQuery._({
    required this.businessDate,
    required this.sequence,
    required this.displayEnding,
    this.deviceCode,
  });

  final String businessDate;
  final int sequence;
  final String displayEnding;

  /// The till a printed number named, or null for bare digits, which may
  /// match every till's receipt of that number that day.
  final String? deviceCode;

  /// Whether [sale] was issued by the till this query names, which is every
  /// sale where it names none.
  ///
  /// A filter rather than a proof: the day's query rightly returns every
  /// till's receipt of this number, and the ones from other tills are simply
  /// not the one being looked for.
  bool isFromNamedTill(TenantSale sale) =>
      deviceCode == null ||
      sale.receiptNumber.startsWith('$checkoutReceiptPrefix-$deviceCode-');
}

/// What one receipt lookup found.
///
/// More than one sale is a real possibility rather than an error: the device
/// code is a three-character digest, so two devices can share one, and receipt
/// uniqueness is device-local. A collision is reported rather than resolved by
/// picking a sale, because only reconciliation can decide which is which.
final class TenantReceiptLookupResult {
  TenantReceiptLookupResult._({
    required this.query,
    required List<TenantSale> matches,
  }) : matches = List<TenantSale>.unmodifiable(matches);

  final TenantReceiptQuery query;
  final List<TenantSale> matches;

  bool get isFound => matches.length == 1;
  bool get isMissing => matches.isEmpty;

  /// Two devices whose codes collide issued the same receipt on the same day.
  bool get isAmbiguous => matches.length > 1;

  TenantSale get sale => matches.single;
}

/// Every authorized sale carrying one daily receipt ending.
final class TenantReceiptEndingLookupResult {
  TenantReceiptEndingLookupResult._({
    required this.query,
    required List<TenantSale> matches,
  }) : matches = List<TenantSale>.unmodifiable(matches);

  final TenantReceiptEndingQuery query;
  final List<TenantSale> matches;

  bool get isFound => matches.length == 1;
  bool get isMissing => matches.isEmpty;
  bool get isAmbiguous => matches.length > 1;
  TenantSale get sale => matches.single;
}

/// Guarded lookup from a customer's receipt to its immutable sale.
final class TenantReceiptLookupRepository extends TenantReadRepository {
  TenantReceiptLookupRepository({
    required super.session,
    required TenantDataReader reader,
  }) : _collectionReader = reader,
       super(reader: reader);

  /// Every active member may open receipt search, but the repository narrows a
  /// cashier to receipts they issued. Management may search the whole business
  /// or one selected member.
  static const List<TenantRole> allowedRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
    TenantRole.manager,
    TenantRole.cashier,
  ];

  static const List<TenantRole> managementRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
    TenantRole.manager,
  ];

  /// The most colliding sales one lookup will report before failing closed.
  ///
  /// The repository never returns a partial collision set: `hasMore` becomes a
  /// refusal so a person cannot mistake the first page for every matching till.
  static const int maximumMatches = 50;

  final TenantCollectionReader _collectionReader;

  Future<TenantReceiptLookupResult> findByReceipt(
    String receiptNumber, {
    String? soldById,
  }) async {
    final query = TenantReceiptQuery.parse(receiptNumber);
    final effectiveSoldById = _effectiveSoldById(soldById);
    final matches = await _findMatches(
      filters: <String, Object?>{
        'receiptNumber': query.receiptNumber,
        if (effectiveSoldById != null) 'soldById': effectiveSoldById,
      },
      verify: (sale) => sale.receiptNumber == query.receiptNumber,
    );
    return TenantReceiptLookupResult._(query: query, matches: matches);
  }

  Future<TenantReceiptEndingLookupResult> findByEnding({
    required String businessDate,
    required String ending,
    String? soldById,
    String? maximumBusinessDate,
  }) async {
    final query = TenantReceiptEndingQuery.parse(
      businessDate: businessDate,
      ending: ending,
      maximumBusinessDate: maximumBusinessDate,
    );
    final effectiveSoldById = _effectiveSoldById(soldById);
    final matches = await _findMatches(
      filters: <String, Object?>{
        'businessDate': query.businessDate,
        'receiptSequence': query.sequence,
        if (effectiveSoldById != null) 'soldById': effectiveSoldById,
      },
      verify: (sale) =>
          sale.businessDate == query.businessDate &&
          sale.receiptSequence == query.sequence,
    );
    return TenantReceiptEndingLookupResult._(
      query: query,
      matches: matches.where(query.isFromNamedTill).toList(growable: false),
    );
  }

  String? _effectiveSoldById(String? requested) {
    if (!session.canAccess(allowedRoles: allowedRoles)) {
      throw const TenantReceiptLookupException('receipt_lookup_forbidden');
    }
    if (!session.canAccess(allowedRoles: managementRoles)) return session.uid;
    if (requested == null) return null;
    try {
      return validateTenantDocumentId(requested, fieldName: 'soldById');
    } on ArgumentError {
      throw const TenantReceiptLookupException('invalid_receipt_scope');
    }
  }

  Future<List<TenantSale>> _findMatches({
    required Map<String, Object?> filters,
    required bool Function(TenantSale sale) verify,
  }) async {
    final page = await readCollectionPage(
      TenantCollection.sales,
      collectionReader: _collectionReader,
      pageSize: maximumMatches,
      equalityFilters: filters,
    );
    if (page.hasMore) {
      throw const TenantReceiptLookupException('too_many_matches');
    }
    final matches = <TenantSale>[];
    for (final snapshot in page.items) {
      final sale = TenantSale.fromDocument(
        path: snapshot.path,
        data: snapshot.data,
      );
      if (sale.tenantId != session.tenantId) {
        throw const TenantReceiptLookupException('cross_tenant_sale');
      }
      if (!verify(sale)) {
        throw const TenantReceiptLookupException('receipt_mismatch');
      }
      final soldById = filters['soldById'];
      if (soldById != null && sale.soldById != soldById) {
        throw const TenantReceiptLookupException('receipt_scope_mismatch');
      }
      matches.add(sale);
    }
    return matches;
  }
}
