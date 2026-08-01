import '../checkout/checkout_receipt.dart';
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

/// Guarded lookup from a customer's receipt to its immutable sale.
final class TenantReceiptLookupRepository extends TenantReadRepository {
  TenantReceiptLookupRepository({
    required super.session,
    required TenantDataReader reader,
  }) : _collectionReader = reader,
       super(reader: reader);

  /// Every active member may look up a receipt.
  ///
  /// The sale read rule is already business-wide, and a receipt lookup is the
  /// counter operation a customer initiates: whoever is at the till must be
  /// able to find it. Recording a return from it is open to the same roles;
  /// restoring stock stays management-only.
  static const List<TenantRole> allowedRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
    TenantRole.manager,
    TenantRole.cashier,
  ];

  /// The most colliding sales one lookup will report before giving up.
  static const int maximumMatches = 5;

  final TenantCollectionReader _collectionReader;

  Future<TenantReceiptLookupResult> findByReceipt(String receiptNumber) async {
    final query = TenantReceiptQuery.parse(receiptNumber);
    if (!session.canAccess(allowedRoles: allowedRoles)) {
      throw const TenantReceiptLookupException('receipt_lookup_forbidden');
    }
    // An equality filter on one field with the default ascending key order is
    // served by Firestore's automatic single-field index, so this page needs no
    // composite index. A descending page would need one, and would buy nothing.
    final page = await readCollectionPage(
      TenantCollection.sales,
      collectionReader: _collectionReader,
      pageSize: maximumMatches,
      equalityFilters: <String, Object?>{'receiptNumber': query.receiptNumber},
    );

    final matches = <TenantSale>[];
    for (final snapshot in page.items) {
      final sale = TenantSale.fromDocument(
        path: snapshot.path,
        data: snapshot.data,
      );
      if (sale.tenantId != session.tenantId) {
        throw const TenantReceiptLookupException('cross_tenant_sale');
      }
      // The sale model already re-derives the receipt from the sale's own
      // device, business date, and sequence. Comparing it to the requested one
      // proves a transport that ignored the filter cannot answer with a
      // different customer's sale.
      if (sale.receiptNumber != query.receiptNumber) {
        throw const TenantReceiptLookupException('receipt_mismatch');
      }
      matches.add(sale);
    }
    return TenantReceiptLookupResult._(query: query, matches: matches);
  }
}
