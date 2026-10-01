import 'tenant_id.dart';

/// Every business-data collection allowed by the tenant path contract.
enum TenantCollection {
  products('products'),
  categories('categories'),
  sales('sales'),
  shifts('shifts'),
  returns('returns'),
  staff('staff'),
  configuration('configuration'),
  subscription('subscription'),
  auditLogs('audit_logs'),

  /// Every stock count taken in this business. `submitStockTake` and
  /// `applyStockTake` are the only writers; a counter reads their own and
  /// management reads all of them.
  stockTakes('stock_takes'),

  /// The business-wide immutable record of every manual `adjustStock`
  /// correction. `adjustStock` is the only writer; the client reads it and can
  /// never append, amend, or undo one.
  stockAdjustments('stock_adjustments'),

  /// Server-regenerated daily reporting. Nightly reconciliation is the only
  /// writer; the client reads it and never aggregates a replacement.
  dailyMetrics('daily_metrics'),

  /// The server's own record of every reconciliation run queued for this
  /// business. `functions/src/reconciliation/**` is the only writer; the client
  /// reads it to explain how a day reached the state [dailyMetrics] reports.
  reconciliationJobs('reconciliation_jobs'),

  /// One record per business day stating whether that day's sales are still
  /// waiting to be regenerated. Written by the same reconciliation code and
  /// keyed by the business date itself, so a day is read by exact path.
  reconciliationDirtyDays('reconciliation_dirty_days'),

  /// The differences reconciliation found and could not resolve: a sale with
  /// unusable lines, a product whose stock disagrees with its ledger, a shift
  /// whose totals disagree with its sales. The same workers are the only
  /// writers, and nothing here changes stock or a shift.
  reconciliationAnomalies('reconciliation_anomalies'),

  /// One document, recomputed by every completed reconciliation run: how many
  /// recorded differences are still open. It exists so a launcher can carry a
  /// badge without listing [reconciliationAnomalies] to count it - those are
  /// keyed by digest, so they can be neither ordered nor counted cheaply.
  reconciliationSummary('reconciliation_summary'),

  /// The immutable trail of every closed shift whose summary was corrected.
  /// `amendShiftSummary` is the only writer, and it appends only: a client can
  /// never create, amend, or erase one. Each record states what the shift said
  /// before, what it says now, why, and who asked - and that the counted cash
  /// was left alone.
  shiftAmendments('shift_amendments'),

  /// What the business spent that no sale line accounts for - rent, wages,
  /// fuel, a repair. The client is the only writer, and a record is immutable
  /// once written: a mistake is voided, never edited away.
  ///
  /// **A document ID here begins with the business date it belongs to**, which
  /// is not decoration. [TenantReadRepository] orders a page by document ID and
  /// takes only equality filters, so a date *range* is reachable only if the
  /// ordering key already carries the date. See `tenantExpenseId`.
  expenses('expenses'),

  /// Who stock is bought from. Server-written by `createSupplier` and
  /// `updateSupplier`, which keep names unique across the business; a supplier
  /// is never deleted, only marked inactive, because deliveries name it.
  suppliers('suppliers'),

  /// What each supplier delivery brought in: one supplier, one reference, many
  /// product lines. Written only by `receiveSupplierDelivery`, in the same
  /// transaction that moves the stock and sets each product's cost.
  supplierDeliveries('supplier_deliveries'),

  /// What each production batch made and cost to make. Written only by
  /// `completeProduction`, in the same transaction that adds the stock and sets
  /// the product's cost. A completed batch is never edited.
  productionBatches('production_batches'),

  /// Who the business sells to. Server-written by `createCustomer` and
  /// `updateCustomer`, which keep one phone number per customer; read by every
  /// member, because the till is where a customer is chosen. Never deleted,
  /// only marked inactive, because sales name them.
  customers('customers'),

  /// Every receipt the server tried to send on WhatsApp and what became of it.
  /// Written by the delivery worker and the webhook alone; read by management.
  receiptDeliveries('receipt_deliveries'),

  /// What customers paid back on credit. Written only by
  /// `recordCustomerPayment`, which moves the balance in the same
  /// transaction; read by management, and by the cashier who took each one.
  customerPayments('customer_payments');

  const TenantCollection(this.segment);

  final String segment;
}

/// Every subcollection of one tenant product allowed by the path contract.
/// The subcollections a stock take owns.
enum TenantStockTakeSubcollection {
  /// One document per counted product, keyed by the product's own ID. Carries
  /// `expected`, so it is readable by management alone - see `firestore.rules`.
  lines('lines');

  const TenantStockTakeSubcollection(this.segment);

  final String segment;
}

/// The subcollections a customer owns.
enum TenantCustomerSubcollection {
  /// The customer's ledger: one entry per sale counted, per return that gave
  /// something back, and per repayment. Server-written; read by management.
  activity('activity');

  const TenantCustomerSubcollection(this.segment);

  final String segment;
}

enum TenantProductSubcollection {
  /// The immutable per-product stock ledger. Sales, verified returns, and
  /// manual adjustments all append to it, and only server code writes it.
  stockMovements('stock_movements');

  const TenantProductSubcollection(this.segment);

  final String segment;
}

/// Constructs business Firestore paths rooted below one validated tenant.
///
/// This class intentionally returns strings and has no Firebase dependency.
final class TenantPaths {
  factory TenantPaths(String tenantId) =>
      TenantPaths._(validateTenantId(tenantId));

  factory TenantPaths.forTenant(String tenantId) => TenantPaths(tenantId);

  const TenantPaths._(this.tenantId);

  static const List<TenantCollection> businessCollections = <TenantCollection>[
    TenantCollection.products,
    TenantCollection.categories,
    TenantCollection.sales,
    TenantCollection.shifts,
    TenantCollection.returns,
    TenantCollection.staff,
    TenantCollection.configuration,
    TenantCollection.subscription,
    TenantCollection.auditLogs,
    TenantCollection.stockAdjustments,
    TenantCollection.dailyMetrics,
    TenantCollection.reconciliationJobs,
    TenantCollection.reconciliationDirtyDays,
    TenantCollection.reconciliationAnomalies,
    TenantCollection.reconciliationSummary,
    TenantCollection.shiftAmendments,
    TenantCollection.expenses,
    TenantCollection.suppliers,
    TenantCollection.supplierDeliveries,
    TenantCollection.productionBatches,
    TenantCollection.customers,
    TenantCollection.receiptDeliveries,
    TenantCollection.customerPayments,
  ];

  final String tenantId;

  String get root => 'tenants/$tenantId';

  String collectionPath(TenantCollection collection) =>
      '$root/${collection.segment}';

  String documentPath(TenantCollection collection, String documentId) =>
      '${collectionPath(collection)}/${validateTenantDocumentId(documentId)}';

  String get products => collectionPath(TenantCollection.products);
  String get categories => collectionPath(TenantCollection.categories);
  String get sales => collectionPath(TenantCollection.sales);
  String get shifts => collectionPath(TenantCollection.shifts);
  String get returns => collectionPath(TenantCollection.returns);
  String get staff => collectionPath(TenantCollection.staff);
  String get configuration => collectionPath(TenantCollection.configuration);
  String get subscription => collectionPath(TenantCollection.subscription);
  String get auditLogs => collectionPath(TenantCollection.auditLogs);
  String get stockAdjustments =>
      collectionPath(TenantCollection.stockAdjustments);
  String get dailyMetrics => collectionPath(TenantCollection.dailyMetrics);
  String get reconciliationAnomalies =>
      collectionPath(TenantCollection.reconciliationAnomalies);
  String get reconciliationJobs =>
      collectionPath(TenantCollection.reconciliationJobs);
  String get reconciliationDirtyDays =>
      collectionPath(TenantCollection.reconciliationDirtyDays);
  String get shiftAmendments =>
      collectionPath(TenantCollection.shiftAmendments);
  String get expenses => collectionPath(TenantCollection.expenses);
  String get suppliers => collectionPath(TenantCollection.suppliers);
  String get supplierDeliveries =>
      collectionPath(TenantCollection.supplierDeliveries);
  String get productionBatches =>
      collectionPath(TenantCollection.productionBatches);
  String get customers => collectionPath(TenantCollection.customers);
  String get receiptDeliveries =>
      collectionPath(TenantCollection.receiptDeliveries);

  String product(String productId) =>
      documentPath(TenantCollection.products, productId);
  String category(String categoryId) =>
      documentPath(TenantCollection.categories, categoryId);
  String sale(String saleId) => documentPath(TenantCollection.sales, saleId);
  String shift(String shiftId) =>
      documentPath(TenantCollection.shifts, shiftId);
  String returnRecord(String returnId) =>
      documentPath(TenantCollection.returns, returnId);
  String expenseRecord(String expenseId) =>
      documentPath(TenantCollection.expenses, expenseId);
  String supplier(String supplierId) =>
      documentPath(TenantCollection.suppliers, supplierId);
  String supplierDelivery(String deliveryId) =>
      documentPath(TenantCollection.supplierDeliveries, deliveryId);
  String productionBatch(String batchId) =>
      documentPath(TenantCollection.productionBatches, batchId);
  String customer(String customerId) =>
      documentPath(TenantCollection.customers, customerId);
  String receiptDelivery(String deliveryId) =>
      documentPath(TenantCollection.receiptDeliveries, deliveryId);
  String customerPayment(String paymentId) =>
      documentPath(TenantCollection.customerPayments, paymentId);
  String staffMember(String uid) => documentPath(TenantCollection.staff, uid);
  String configurationDocument(String documentId) =>
      documentPath(TenantCollection.configuration, documentId);
  String subscriptionDocument(String documentId) =>
      documentPath(TenantCollection.subscription, documentId);
  String auditRecord(String auditId) =>
      documentPath(TenantCollection.auditLogs, auditId);
  String stockAdjustment(String adjustmentId) => documentPath(
    TenantCollection.stockAdjustments,
    adjustmentId,
  );
  String dailyMetric(String businessDate) =>
      documentPath(TenantCollection.dailyMetrics, businessDate);
  String reconciliationJob(String jobId) =>
      documentPath(TenantCollection.reconciliationJobs, jobId);
  String shiftAmendment(String amendmentId) =>
      documentPath(TenantCollection.shiftAmendments, amendmentId);

  /// The intake record for one business day. Its document ID **is** the
  /// business date, so a day is addressed rather than searched for.
  String reconciliationDirtyDay(String businessDate) =>
      documentPath(TenantCollection.reconciliationDirtyDays, businessDate);

  /// The path of one allowed subcollection below one product.
  ///
  /// Both segments are validated document IDs, so no caller can walk out of
  /// `tenants/{tenantId}/products/{productId}` by naming a path.
  String productSubcollectionPath(
    String productId,
    TenantProductSubcollection subcollection,
  ) => '${product(productId)}/${subcollection.segment}';

  /// The path of one allowed subcollection below one customer.
  String customerSubcollectionPath(
    String customerId,
    TenantCustomerSubcollection subcollection,
  ) => '${customer(customerId)}/${subcollection.segment}';

  String stockTakeSubcollectionPath(
    String takeId,
    TenantStockTakeSubcollection subcollection,
  ) =>
      '${documentPath(TenantCollection.stockTakes, takeId)}/'
      '${subcollection.segment}';

  String stockTakeLines(String takeId) => stockTakeSubcollectionPath(
    takeId,
    TenantStockTakeSubcollection.lines,
  );

  String productStockMovements(String productId) => productSubcollectionPath(
    productId,
    TenantProductSubcollection.stockMovements,
  );

  String productStockMovement(String productId, String movementId) =>
      '${productStockMovements(productId)}/'
      '${validateTenantDocumentId(movementId, fieldName: 'movementId')}';

  String get currentSubscription => subscriptionDocument('current');

  /// Whether [path] belongs to this exact tenant root.
  bool owns(String path) => path == root || path.startsWith('$root/');
}
