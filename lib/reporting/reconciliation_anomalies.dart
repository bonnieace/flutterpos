import 'package:cloud_firestore/cloud_firestore.dart';

import '../checkout/checkout_tender.dart';
import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_paths.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_types.dart';
import 'reconciliation_status.dart';

/// What kind of difference reconciliation found and could not resolve.
///
/// Four writers under `functions/src/reconciliation/**` produce these, and they
/// are the only authority on the wire values: `jobs.ts` records an unusable
/// sale, and `processors.ts` records an unreadable product quantity, the three
/// stock outcomes, and the two shift outcomes.
enum TenantReconciliationAnomalyKind {
  /// A sale carried lines the server could not turn into stock movements, so
  /// that sale's stock was never applied to the products it names.
  invalidSaleLines('invalid_sale_lines', 'Sale lines could not be read'),

  /// A product's own `quantity` field could not be read as a whole number, so
  /// its stock could not be verified at all.
  invalidProductQuantity(
    'invalid_product_quantity',
    'Product quantity could not be read',
  ),

  /// The chain of stock checkpoints behind this product does not join up, so
  /// the expected quantity cannot be trusted as a starting point.
  checkpointChainInvalid(
    'checkpoint_chain_invalid',
    'Stock checkpoint chain is broken',
  ),

  /// A movement in this product's ledger could not be read, so the ledger no
  /// longer accounts for everything that moved.
  invalidStockMovement('invalid_stock_movement', 'Stock ledger entry unusable'),

  /// The product holds fewer units than its ledger accounts for.
  ///
  /// **The one worth reading first.** Units left and nothing says why. A sale
  /// whose ledger entry never landed looks exactly like this, and so does a
  /// quantity lowered outside the app - `allow update` on `products` admits a
  /// strictly decreasing quantity with no movement required, because the
  /// checkout decrement is still written by the till. Neither of those is
  /// visible anywhere else.
  stockShortOfLedger('stock_short_of_ledger', 'Stock left without a record'),

  /// The product holds more units than its ledger accounts for.
  ///
  /// Rarer, and it points somewhere else. No client write can produce it: the
  /// rule permits only a decrease. Units the books hold that no movement put
  /// there say the ledger is incomplete, not that the shelf is.
  stockOverLedger('stock_over_ledger', 'Stock arrived without a record'),

  /// A shift the sales point at is missing, or did not record the totals a
  /// comparison needs.
  invalidOrMissingShift(
    'invalid_or_missing_shift',
    'Shift totals could not be read',
  ),

  /// A shift's closing summary and the sales recorded against it disagree.
  shiftVariance('shift_variance', 'Shift totals do not match its sales'),

  /// What a cashier declared the till held disagrees with what its sales say.
  ///
  /// **Distinct from [shiftVariance], which is a bookkeeping fault.** That one
  /// says a shift's recorded total does not match its own sales, and
  /// `amendShiftSummary` corrects it to the figure the sales prove. This one
  /// says a person counted the drawer and got a different answer, and there is
  /// no figure to correct it to - only a difference to look into and accept.
  shiftTenderVariance(
    'shift_tender_variance',
    'Declared takings do not match its sales',
  ),

  /// A shift was closed without saying what the till held.
  missingTenderDeclaration(
    'missing_tender_declaration',
    'No declared takings were recorded',
  ),

  /// Any kind this client does not model. It carries no wire value; a surface
  /// shows the recorded value verbatim rather than hiding a real difference,
  /// and it cannot be filtered for.
  other('', 'Unrecognised');

  const TenantReconciliationAnomalyKind(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static TenantReconciliationAnomalyKind parse(String value) {
    for (final kind in values) {
      if (kind != other && kind.wireValue == value) return kind;
    }
    return other;
  }
}

/// Whether a recorded difference has been accepted by somebody.
///
/// **Acceptance is not correction.** `amendShiftSummary` fixes a figure that
/// was wrong; this records that a figure was right and a person looked at it
/// anyway. So the record and every number on it survive being acknowledged -
/// only the count a badge is drawn from moves.
enum TenantReconciliationResolution {
  /// Nobody has settled it, which is also what an older record with no
  /// `resolution` field at all means.
  open('open'),

  /// An owner or administrator has seen it and accepts it.
  acknowledged('acknowledged'),

  /// A state this client does not model, carried rather than guessed at. It is
  /// counted as unsettled: over-reporting an open difference is recoverable and
  /// hiding one is not.
  other('');

  const TenantReconciliationResolution(this.wireValue);

  final String wireValue;

  bool get isOpen => this != acknowledged;

  static TenantReconciliationResolution parse(Object? value) {
    if (value == null) return open;
    for (final resolution in values) {
      if (resolution != other && resolution.wireValue == value) {
        return resolution;
      }
    }
    return other;
  }
}

/// One difference reconciliation recorded against this business.
///
/// The four writers agree on very little: only the business and the kind appear
/// on every record, so only those are required. Everything else is checked
/// against the writer that produces it, and a record that contradicts the only
/// code that could have written it is refused rather than listed - a record
/// about a discrepancy that misstates the discrepancy is not evidence of
/// anything, which is the same rule the stock correction feed applies.
///
/// Nothing here changed stock or a shift. The records say so themselves through
/// `mutatesStock: false` and `mutatesShift: false`, and the frozen baseline
/// requires that reconciliation never silently changes stock.
final class TenantReconciliationAnomaly {
  const TenantReconciliationAnomaly._({
    required this.id,
    required this.tenantId,
    required this.kind,
    required this.kindValue,
    required this.productId,
    required this.shiftId,
    required this.saleId,
    required this.jobId,
    required this.invalidLineCount,
    required this.expectedQuantity,
    required this.observedQuantity,
    required this.quantityVariance,
    required this.salesVariance,
    required this.transactionVariance,
    required this.declaredMinor,
    required this.expectedMinor,
    required this.tenderVarianceMinor,
    required this.expectedUnattributedMinor,
    required this.businessDate,
    required this.staffId,
    required this.resolution,
    required this.recordedAt,
    required this.updatedAt,
  });

  factory TenantReconciliationAnomaly.fromDocument({
    required String path,
    required Map<String, Object?> data,
  }) {
    final segments = path.split('/');
    if (segments.length != 4 ||
        segments[0] != 'tenants' ||
        segments[2] != TenantCollection.reconciliationAnomalies.segment) {
      throw const TenantReconciliationException('invalid_anomaly_path');
    }
    final String tenantId;
    final String anomalyId;
    try {
      tenantId = validateTenantId(segments[1]);
      anomalyId = validateTenantDocumentId(segments[3], fieldName: 'anomalyId');
    } on ArgumentError {
      throw const TenantReconciliationException('invalid_anomaly_path');
    }
    // An anomaly does not repeat its own ID - the workers address it by the
    // digest of what it is about - so its path is the one authority on which
    // record it is. The business it names must still agree.
    if (data['tenantId'] != tenantId) {
      throw const TenantReconciliationException('anomaly_identity_mismatch');
    }

    final kindValue = _requiredString(data, 'anomalyType');
    final kind = TenantReconciliationAnomalyKind.parse(kindValue);
    final productId = _optionalDocumentId(data, 'productId');
    final shiftId = _optionalDocumentId(data, 'shiftId');
    final saleId = _optionalDocumentId(data, 'sourceId');
    final invalidLineCount = _optionalCount(data, 'invalidLineCount');
    final expectedQuantity = _optionalQuantity(data, 'expectedQuantity');
    final observedQuantity = _optionalQuantity(data, 'observedQuantity');
    final quantityVariance = _optionalQuantity(data, 'variance');
    final salesVariance = _optionalNumber(data, 'salesVariance');
    final transactionVariance = _optionalQuantity(data, 'transactionVariance');
    final declared = _tenderFigures(data, 'declared');
    final expected = _tenderFigures(data, 'expected');
    final variances = <CheckoutTender, int?>{
      for (final tender in CheckoutTender.values)
        tender: _optionalMinorUnits(data, _varianceField(tender)),
    };

    _assertDescribesItself(
      kind: kind,
      productId: productId,
      shiftId: shiftId,
      saleId: saleId,
      invalidLineCount: invalidLineCount,
      expectedQuantity: expectedQuantity,
      observedQuantity: observedQuantity,
      quantityVariance: quantityVariance,
      salesVariance: salesVariance,
      transactionVariance: transactionVariance,
      declared: declared,
      expected: expected,
      variances: variances,
    );

    return TenantReconciliationAnomaly._(
      id: anomalyId,
      tenantId: tenantId,
      kind: kind,
      kindValue: kindValue,
      productId: productId,
      shiftId: shiftId,
      saleId: saleId,
      jobId: _optionalDocumentId(data, 'jobId'),
      invalidLineCount: invalidLineCount,
      expectedQuantity: expectedQuantity,
      observedQuantity: observedQuantity,
      quantityVariance: quantityVariance,
      salesVariance: salesVariance,
      transactionVariance: transactionVariance,
      declaredMinor: declared,
      expectedMinor: expected,
      tenderVarianceMinor: variances,
      expectedUnattributedMinor: _optionalMinorUnits(
        data,
        'expectedUnattributedMinor',
      ),
      businessDate: data['businessDate'] is String
          ? data['businessDate']! as String
          : null,
      staffId: _optionalDocumentId(data, 'staffId'),
      resolution: TenantReconciliationResolution.parse(data['resolution']),
      // `createdAt` degrades rather than failing the page closed, exactly as it
      // does on the activity log: a record without a time still proves the
      // difference was found and says what it was, and denying a manager the
      // whole list over one convenience field would be strictly worse.
      recordedAt: _optionalInstant(data, 'createdAt'),
      updatedAt: _optionalInstant(data, 'updatedAt'),
    );
  }

  /// The three per-method figures written under one prefix, or nulls.
  static Map<CheckoutTender, int?> _tenderFigures(
    Map<String, Object?> data,
    String prefix,
  ) => <CheckoutTender, int?>{
    for (final tender in CheckoutTender.values)
      tender: _optionalMinorUnits(data, _tenderField(prefix, tender)),
  };

  /// `declaredCashMinor`, `expectedMpesaMinor`, and the rest.
  static String _tenderField(String prefix, CheckoutTender tender) {
    final name = tender.wireValue;
    return '$prefix${name[0].toUpperCase()}${name.substring(1)}Minor';
  }

  static String _varianceField(CheckoutTender tender) =>
      '${tender.wireValue}VarianceMinor';

  final String id;
  final String tenantId;
  final TenantReconciliationAnomalyKind kind;

  /// The recorded kind, shown verbatim when this client does not model it.
  final String kindValue;

  /// Present on every stock anomaly, absent on every shift and sale one.
  final String? productId;
  final String? shiftId;
  final String? saleId;

  /// The run that found it. Absent on a sale anomaly, which is recorded by the
  /// sale trigger rather than by a job.
  final String? jobId;

  /// How many of that sale's lines could not be read. Always at least one.
  final int? invalidLineCount;

  /// The stock this product should hold, what it holds, and the difference.
  /// Present together on the three stock anomalies and nowhere else.
  final int? expectedQuantity;
  final int? observedQuantity;
  final int? quantityVariance;

  /// Observed minus expected, in major units, for a shift whose totals could be
  /// compared at all. Null when the shift's own totals could not be read.
  final num? salesVariance;
  final int? transactionVariance;

  /// What the cashier said the till held, by method, in minor units.
  ///
  /// Present together on a tender variance and nowhere else - a
  /// `missing_tender_declaration` carries none of them, because there was
  /// nothing to record.
  final Map<CheckoutTender, int?> declaredMinor;

  /// What this shift's own sales say it took, by method, in minor units.
  final Map<CheckoutTender, int?> expectedMinor;

  /// Declared minus expected, by method. Signed: a negative figure is money the
  /// sales account for and the drawer does not.
  final Map<CheckoutTender, int?> tenderVarianceMinor;

  /// Takings the sales could not attribute to any method this app models.
  ///
  /// **Stated rather than dropped.** It is inside the shift's total but in none
  /// of the three expected figures, so a report that left it out would show
  /// three numbers that do not add up to the shift and look short by exactly
  /// this much.
  final int? expectedUnattributedMinor;

  /// The trading day the difference belongs to, where the writer recorded one.
  final String? businessDate;

  /// The cashier whose shift it is, where the writer recorded one.
  final String? staffId;

  /// Whether somebody has accepted this difference.
  final TenantReconciliationResolution resolution;

  final DateTime? recordedAt;
  final DateTime? updatedAt;

  /// True while the record describes a stock difference against one product.
  bool get isStockAnomaly =>
      kind == TenantReconciliationAnomalyKind.checkpointChainInvalid ||
      kind == TenantReconciliationAnomalyKind.invalidStockMovement ||
      kind == TenantReconciliationAnomalyKind.stockShortOfLedger ||
      kind == TenantReconciliationAnomalyKind.stockOverLedger;

  /// True while the record describes a shift whose totals were compared.
  bool get isShiftAnomaly =>
      kind == TenantReconciliationAnomalyKind.invalidOrMissingShift ||
      kind == TenantReconciliationAnomalyKind.shiftVariance ||
      isTenderAnomaly;

  /// True while the record is about what a cashier declared the till held.
  bool get isTenderAnomaly =>
      kind == TenantReconciliationAnomalyKind.shiftTenderVariance ||
      kind == TenantReconciliationAnomalyKind.missingTenderDeclaration;

  static void _assertDescribesItself({
    required TenantReconciliationAnomalyKind kind,
    required String? productId,
    required String? shiftId,
    required String? saleId,
    required int? invalidLineCount,
    required int? expectedQuantity,
    required int? observedQuantity,
    required int? quantityVariance,
    required num? salesVariance,
    required int? transactionVariance,
    required Map<CheckoutTender, int?> declared,
    required Map<CheckoutTender, int?> expected,
    required Map<CheckoutTender, int?> variances,
  }) {
    switch (kind) {
      // `jobs.ts` writes this only when `invalidLineCount > 0`, and always
      // names the sale it read.
      case TenantReconciliationAnomalyKind.invalidSaleLines:
        if (saleId == null ||
            invalidLineCount == null ||
            invalidLineCount < 1) {
          throw const TenantReconciliationException('inconsistent_anomaly');
        }
      case TenantReconciliationAnomalyKind.invalidProductQuantity:
        if (productId == null) {
          throw const TenantReconciliationException('inconsistent_anomaly');
        }
      // The stock writer reads the product inside its own transaction, so all
      // three figures are always recorded together, and `variance` is exactly
      // `observedQuantity - expectedQuantity`. A record that cannot explain its
      // own difference is refused.
      case TenantReconciliationAnomalyKind.checkpointChainInvalid:
      case TenantReconciliationAnomalyKind.invalidStockMovement:
      case TenantReconciliationAnomalyKind.stockShortOfLedger:
      case TenantReconciliationAnomalyKind.stockOverLedger:
        if (productId == null ||
            expectedQuantity == null ||
            observedQuantity == null ||
            quantityVariance == null ||
            quantityVariance != observedQuantity - expectedQuantity) {
          throw const TenantReconciliationException('inconsistent_anomaly');
        }
        // These two are chosen only once the chain is valid and every movement
        // was readable, which leaves a non-zero variance as the sole remaining
        // reason the record exists - and **the sign has to agree with the kind**,
        // because the kind is the sign. A record calling itself short while its
        // figures say the shelf is over is not a difference this can draw; it is
        // a writer and a reader that disagree, and reading it either way would
        // put a sentence in front of somebody that its own numbers contradict.
        if (kind == TenantReconciliationAnomalyKind.stockShortOfLedger &&
            quantityVariance >= 0) {
          throw const TenantReconciliationException('inconsistent_anomaly');
        }
        if (kind == TenantReconciliationAnomalyKind.stockOverLedger &&
            quantityVariance <= 0) {
          throw const TenantReconciliationException('inconsistent_anomaly');
        }
      // The shift writer computes both variances only when all four figures
      // could be read; when they could not, it records null for both and calls
      // the record `invalid_or_missing_shift`.
      case TenantReconciliationAnomalyKind.invalidOrMissingShift:
        if (shiftId == null ||
            salesVariance != null ||
            transactionVariance != null) {
          throw const TenantReconciliationException('inconsistent_anomaly');
        }
      case TenantReconciliationAnomalyKind.shiftVariance:
        if (shiftId == null ||
            salesVariance == null ||
            transactionVariance == null) {
          throw const TenantReconciliationException('inconsistent_anomaly');
        }
        // It is written only when the comparison did not match, so a shift
        // variance of nothing at all contradicts its own writer.
        if (salesVariance == 0 && transactionVariance == 0) {
          throw const TenantReconciliationException('inconsistent_anomaly');
        }
      // The verifier computes these only when all three declared and all three
      // expected figures could be read, and each variance is exactly
      // `declared - expected`. A record that cannot explain its own difference
      // is refused, which is the rule the three stock kinds are held to.
      case TenantReconciliationAnomalyKind.shiftTenderVariance:
        if (shiftId == null) {
          throw const TenantReconciliationException('inconsistent_anomaly');
        }
        for (final tender in CheckoutTender.values) {
          final declaredFigure = declared[tender];
          final expectedFigure = expected[tender];
          if (declaredFigure == null ||
              expectedFigure == null ||
              variances[tender] != declaredFigure - expectedFigure) {
            throw const TenantReconciliationException('inconsistent_anomaly');
          }
        }
        // Written only when the declaration did not match, so one that agrees
        // on all three contradicts its own writer.
        if (variances.values.every((variance) => variance == 0)) {
          throw const TenantReconciliationException('inconsistent_anomaly');
        }
      // Nothing was declared, so there is nothing to state. Figures here would
      // be a comparison the writer could not have made.
      case TenantReconciliationAnomalyKind.missingTenderDeclaration:
        if (shiftId == null ||
            declared.values.any((figure) => figure != null) ||
            variances.values.any((variance) => variance != null)) {
          throw const TenantReconciliationException('inconsistent_anomaly');
        }
      // A kind this client does not model is carried verbatim: a server deploy
      // that records a new difference is not evidence of anything wrong, and
      // hiding a real one would be far worse than naming it plainly.
      case TenantReconciliationAnomalyKind.other:
        break;
    }
  }
}

/// One bounded page of the differences recorded against this business.
final class TenantReconciliationAnomalyPage {
  TenantReconciliationAnomalyPage({
    required List<TenantReconciliationAnomaly> items,
    required this.nextCursor,
    required this.hasMore,
    required this.kind,
    this.productId,
  }) : items = List<TenantReconciliationAnomaly>.unmodifiable(items);

  final List<TenantReconciliationAnomaly> items;
  final String? nextCursor;
  final bool hasMore;

  /// The kind this page was narrowed to, or null for every kind.
  final TenantReconciliationAnomalyKind? kind;

  /// The exact product this page was narrowed to, or null for the whole
  /// business. A surface states which one it is showing rather than implying a
  /// filtered page is everything that was recorded.
  final String? productId;
}

/// Guarded read boundary over the differences reconciliation recorded.
///
/// A run already reports how many stock and shift differences it found. This
/// reports which ones, and deliberately computes no count of its own: a page is
/// bounded, so a tally over it would be a second and weaker figure that
/// disagrees with the run at every page boundary.
///
/// Every path is derived from the session's [TenantPaths] and the exact-child,
/// uniqueness, page-size, and ordering proofs of [TenantReadRepository] still
/// apply. No caller can supply a collection path, an ordering, or a raw filter.
final class TenantReconciliationAnomalyRepository extends TenantReadRepository {
  TenantReconciliationAnomalyRepository({
    required super.session,
    required TenantDataReader reader,
  }) : _collectionReader = reader,
       super(reader: reader);

  /// The same roles that read the runs whose counts this explains.
  static const List<TenantRole> allowedRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
    TenantRole.manager,
  ];

  final TenantCollectionReader _collectionReader;

  static bool canReadInSession(TenantSession session) =>
      session.canAccess(allowedRoles: allowedRoles);

  /// Reads one bounded page of this business's recorded differences.
  ///
  /// The page is business-wide and is **not** narrowed to a business date,
  /// because a record carries none: a stock anomaly is about a product and a
  /// shift anomaly is about a shift. Narrowing it to the day a caller happens to
  /// be looking at would silently hide differences that are still open.
  ///
  /// It is ordered by ascending document ID and is deliberately not presented
  /// as chronological: an ID is a prefix plus a digest of what the record is
  /// about, so document order carries no time information. Each record states
  /// its own instants instead. Ascending key order with at most one equality
  /// filter is served by Firestore's automatic single-field index, so this
  /// needs no composite index.
  Future<TenantReconciliationAnomalyPage> loadPage({
    TenantReconciliationAnomalyKind? kind,
    int pageSize = 20,
    String? cursor,
  }) => _load(kind: kind, productId: null, pageSize: pageSize, cursor: cursor);

  /// Reads the differences recorded against one product.
  ///
  /// One equality filter, on `productId`, so it is served by the same automatic
  /// single-field index every other shape here relies on. It deliberately takes
  /// no `kind`: two equality filters on this ascending key order would need a
  /// composite index, and the surface that asks about one product wants every
  /// difference listed against it rather than one kind of them.
  ///
  /// The kinds it can answer with are not all quantity disagreements. A caller
  /// must distinguish them: `invalid_product_quantity`,
  /// `invalid_stock_movement`, and `checkpoint_chain_invalid` are reports that
  /// the comparison could not be trusted, and an adjustment resolves none of
  /// them.
  Future<TenantReconciliationAnomalyPage> loadProductPage({
    required String productId,
    int pageSize = 20,
    String? cursor,
  }) => _load(
    kind: null,
    productId: productId,
    pageSize: pageSize,
    cursor: cursor,
  );

  Future<TenantReconciliationAnomalyPage> _load({
    required TenantReconciliationAnomalyKind? kind,
    required String? productId,
    required int pageSize,
    required String? cursor,
  }) async {
    if (!canReadInSession(session)) {
      throw const TenantReconciliationException('anomalies_forbidden');
    }
    // `other` names every kind this client does not model, so it identifies no
    // single stored value and cannot be asked for. The unnarrowed page still
    // lists those records.
    if (kind == TenantReconciliationAnomalyKind.other) {
      throw const TenantReconciliationException('unfilterable_anomaly_kind');
    }
    final String? filteredProductId;
    try {
      filteredProductId = productId == null
          ? null
          : validateTenantDocumentId(productId, fieldName: 'productId');
    } on ArgumentError {
      throw const TenantReconciliationException('invalid_product_filter');
    }
    final page = await readCollectionPage(
      TenantCollection.reconciliationAnomalies,
      collectionReader: _collectionReader,
      pageSize: pageSize,
      cursor: cursor,
      equalityFilters: <String, Object?>{
        if (kind != null) 'anomalyType': kind.wireValue,
        if (filteredProductId != null) 'productId': filteredProductId,
      },
    );
    final items = <TenantReconciliationAnomaly>[];
    for (final snapshot in page.items) {
      final anomaly = TenantReconciliationAnomaly.fromDocument(
        path: snapshot.path,
        data: snapshot.data,
      );
      if (anomaly.tenantId != session.tenantId) {
        throw const TenantReconciliationException('cross_tenant_anomaly');
      }
      // A filtered page that answers with another kind is a broken boundary,
      // not a row to quietly skip past.
      if (kind != null && anomaly.kind != kind) {
        throw const TenantReconciliationException('foreign_anomaly_kind');
      }
      // The same rule for the product filter. A stock figure is answered for by
      // whoever owns the product, so a record about another one appearing on
      // that page would be worse than an empty one.
      if (filteredProductId != null && anomaly.productId != filteredProductId) {
        throw const TenantReconciliationException('foreign_product_anomaly');
      }
      items.add(anomaly);
    }
    return TenantReconciliationAnomalyPage(
      items: items,
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
      kind: kind,
      productId: filteredProductId,
    );
  }
}

String _requiredString(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! String ||
      value.isEmpty ||
      value != value.trim() ||
      value.length > 200) {
    throw const TenantReconciliationException('invalid_anomaly_field');
  }
  for (final codeUnit in value.codeUnits) {
    if (codeUnit < 0x20 || codeUnit == 0x7f) {
      throw const TenantReconciliationException('invalid_anomaly_field');
    }
  }
  return value;
}

/// Absent is allowed; present but malformed is not. A writer that recorded a
/// field at all recorded a real value, so a broken one is a broken record.
String? _optionalDocumentId(Map<String, Object?> data, String field) {
  if (data[field] == null) return null;
  try {
    return validateTenantDocumentId(
      _requiredString(data, field),
      fieldName: field,
    );
  } on ArgumentError {
    throw const TenantReconciliationException('invalid_anomaly_field');
  }
}

int? _optionalCount(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value == null) return null;
  if (value is! int || value < 0 || value > _maximumCount) {
    throw const TenantReconciliationException('invalid_anomaly_field');
  }
  return value;
}

/// Stock quantities and their differences are signed: checkout may legitimately
/// drive a product below zero, and a shift may have sold fewer than expected.
int? _optionalQuantity(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value == null) return null;
  if (value is! int || value.abs() > _maximumCount) {
    throw const TenantReconciliationException('invalid_anomaly_field');
  }
  return value;
}

num? _optionalNumber(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value == null) return null;
  if (value is int) return _optionalQuantity(data, field);
  if (value is! double || !value.isFinite || value.abs() > _maximumCount) {
    throw const TenantReconciliationException('invalid_anomaly_field');
  }
  return value;
}

DateTime? _optionalInstant(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value == null) return null;
  if (value is Timestamp) return value.toDate().toUtc();
  if (value is DateTime) return value.toUtc();
  throw const TenantReconciliationException('invalid_anomaly_field');
}

/// Reads one money figure recorded in minor units.
///
/// **Bounded separately from [_optionalQuantity], and it has to be.** That one
/// bounds a count of things at a billion; a declared amount is a count of the
/// smallest coin and runs to a thousand times further, so decoding money
/// through it would refuse a large but perfectly legitimate declaration as a
/// malformed record. Signed, because a variance carries its direction.
int? _optionalMinorUnits(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value == null) return null;
  if (value is! int || value.abs() > _maximumMinorUnits) {
    throw const TenantReconciliationException('invalid_anomaly_field');
  }
  return value;
}

const int _maximumCount = 1000000000;

/// The widest money figure an anomaly may carry, in minor units.
///
/// Matches the cap a close is held to, so anything the till could record here
/// decodes and anything larger is a defect rather than a large shop.
const int _maximumMinorUnits = 1000000000000;
