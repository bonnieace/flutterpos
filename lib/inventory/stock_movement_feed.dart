import '../tenancy/tenant_paths.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_types.dart';
import 'stock_movements.dart';

/// One bounded page of everything that moved this business's stock.
final class TenantStockMovementFeedPage {
  TenantStockMovementFeedPage({
    required List<TenantStockMovement> items,
    required this.nextCursor,
    required this.hasMore,
    required this.source,
  }) : items = List<TenantStockMovement>.unmodifiable(items);

  final List<TenantStockMovement> items;

  /// The complete document path the next page resumes after.
  ///
  /// A group page spans every product, so its cursor is a whole path rather
  /// than the leaf document ID a single-collection page carries.
  final String? nextCursor;

  final bool hasMore;

  /// The exact source this page was narrowed to, or null for every movement.
  /// A surface states which one it is showing rather than implying a filtered
  /// page is everything that moved.
  final TenantStockMovementSource? source;

  bool get isSourceScoped => source != null;
}

/// Guarded read boundary over every product's stock ledger at once.
///
/// The per-product repository answers "why is this product's figure what it
/// is". This one answers "what moved this week", which no path-bounded page can
/// serve: the ledger lives below each product, so the only read that spans the
/// business is a Firestore collection group.
///
/// That is a genuinely wider boundary than every other read in this app, and it
/// is narrowed in three independent places rather than one. The repository
/// attaches the `tenantId ==` filter itself, so no caller can issue an
/// unfiltered group page. The Firestore rule authorizes the page by that same
/// condition, so a page without it is refused by the server too. And
/// [TenantReadRepository.readProductSubcollectionGroupPage] still proves every
/// returned path is an exact child of a product below this session's own tenant
/// root.
final class TenantStockMovementFeedRepository extends TenantReadRepository {
  TenantStockMovementFeedRepository({
    required super.session,
    required super.reader,
    required TenantCollectionGroupReader groupReader,
  }) : _groupReader = groupReader;

  /// The same roles the per-product ledger, the correction feed, and
  /// `adjustStock` itself use. A cashier reads a product's current quantity
  /// because that is operational information at the till; what moved it - and
  /// who recorded the damage, waste, and corrections - stays management
  /// information.
  static const List<TenantRole> allowedRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
    TenantRole.manager,
  ];

  final TenantCollectionGroupReader _groupReader;

  static bool canReadInSession(TenantSession session) =>
      session.canAccess(allowedRoles: allowedRoles);

  /// Pages every movement recorded against every product in the business.
  Future<TenantStockMovementFeedPage> loadMovements({
    int pageSize = 20,
    String? cursor,
  }) => _load(pageSize: pageSize, cursor: cursor, source: null);

  /// Pages the movements one modelled source recorded.
  ///
  /// The filter is a typed enum, never a caller-supplied string, so no caller
  /// can name an arbitrary field value. The consequence is deliberate: a source
  /// this client does not model cannot be filtered for, and the unnarrowed page
  /// still lists it.
  Future<TenantStockMovementFeedPage> loadMovementsOfSource({
    required TenantStockMovementSource source,
    int pageSize = 20,
    String? cursor,
  }) => _load(pageSize: pageSize, cursor: cursor, source: source);

  /// Reads one bounded page newest first, optionally narrowed to one source.
  ///
  /// **Ordered by `occurredAt` since 2026-09-14.** A group page used to sort by
  /// product first and then by movement ID, which put every movement of one
  /// product together and every product in ID order - so "what moved this week"
  /// was answerable only by reading the whole ledger. Ordering by when the
  /// stock moved is what makes this page the business's own timeline.
  ///
  /// It needs a composite index, because the tenant binding is an equality
  /// filter the repository attaches itself. That index is in
  /// `firestore.indexes.json` beside the one the source filter already needed.
  Future<TenantStockMovementFeedPage> _load({
    required int pageSize,
    required String? cursor,
    required TenantStockMovementSource? source,
  }) async {
    if (!canReadInSession(session)) {
      throw const TenantStockException('stock_movement_feed_forbidden');
    }
    if (source == TenantStockMovementSource.other) {
      throw const TenantStockException('unfilterable_movement_source');
    }
    final page = await readProductSubcollectionGroupPage(
      TenantProductSubcollection.stockMovements,
      groupReader: _groupReader,
      pageSize: pageSize,
      cursor: cursor,
      descending: true,
      order: TenantCollectionOrder.occurredAt,
      equalityFilters: source == null
          ? const <String, Object?>{}
          : <String, Object?>{'sourceType': source.wireValue},
    );
    final items = <TenantStockMovement>[];
    for (final snapshot in page.items) {
      final movement = TenantStockMovement.fromDocument(
        path: snapshot.path,
        data: snapshot.data,
      );
      if (movement.tenantId != session.tenantId) {
        throw const TenantStockException('cross_tenant_movement');
      }
      // A narrowed page that answers with another source is a broken boundary,
      // not a row to skip past: this surface exists to state what a given kind
      // of movement did to the business's stock.
      if (source != null && movement.source != source) {
        throw const TenantStockException('foreign_movement_source');
      }
      items.add(movement);
    }
    return TenantStockMovementFeedPage(
      items: items,
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
      source: source,
    );
  }
}
