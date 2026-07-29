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
  auditLogs('audit_logs');

  const TenantCollection(this.segment);

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

  String product(String productId) =>
      documentPath(TenantCollection.products, productId);
  String category(String categoryId) =>
      documentPath(TenantCollection.categories, categoryId);
  String sale(String saleId) => documentPath(TenantCollection.sales, saleId);
  String shift(String shiftId) =>
      documentPath(TenantCollection.shifts, shiftId);
  String returnRecord(String returnId) =>
      documentPath(TenantCollection.returns, returnId);
  String staffMember(String uid) => documentPath(TenantCollection.staff, uid);
  String configurationDocument(String documentId) =>
      documentPath(TenantCollection.configuration, documentId);
  String subscriptionDocument(String documentId) =>
      documentPath(TenantCollection.subscription, documentId);
  String auditRecord(String auditId) =>
      documentPath(TenantCollection.auditLogs, auditId);

  String get currentSubscription => subscriptionDocument('current');

  /// Whether [path] belongs to this exact tenant root.
  bool owns(String path) => path == root || path.startsWith('$root/');
}
