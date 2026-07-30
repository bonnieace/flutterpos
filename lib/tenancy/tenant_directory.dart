import 'tenant_membership.dart';

final class TenantListPage {
  TenantListPage({
    required Iterable<TenantMembership> items,
    required this.nextCursor,
    required this.hasMore,
  }) : items = List<TenantMembership>.unmodifiable(items) {
    if (hasMore && (nextCursor == null || nextCursor!.isEmpty)) {
      throw const FormatException(
        'A paginated tenant response needs a cursor.',
      );
    }
  }

  factory TenantListPage.fromJson(Map<String, Object?> json) {
    final rawItems = json['items'];
    final rawCursor = json['nextCursor'];
    final rawHasMore = json['hasMore'];
    if (rawItems is! List<Object?> || rawHasMore is! bool) {
      throw const FormatException('Invalid listMyTenants response.');
    }
    if (rawCursor != null && rawCursor is! String) {
      throw const FormatException('nextCursor must be a nullable string.');
    }
    return TenantListPage(
      items: rawItems.map((item) {
        if (item is! Map) {
          throw const FormatException('A tenant item must be an object.');
        }
        return TenantMembership.fromJson(
          item.map<String, Object?>(
            (key, value) => MapEntry(key.toString(), value),
          ),
        );
      }),
      nextCursor: rawCursor as String?,
      hasMore: rawHasMore,
    );
  }

  final List<TenantMembership> items;
  final String? nextCursor;
  final bool hasMore;
}

abstract interface class TenantDirectoryGateway {
  Future<TenantListPage> listMyTenants({required int pageSize, String? cursor});
}

/// Loads every page before applying sole-tenant or selector routing logic.
final class TenantDirectory {
  TenantDirectory(
    this._gateway, {
    this.pageSize = 50,
    this.maximumPages = 200,
  }) {
    if (pageSize < 1 || pageSize > 50) {
      throw ArgumentError.value(pageSize, 'pageSize', 'Must be from 1 to 50.');
    }
    if (maximumPages < 1) {
      throw ArgumentError.value(
        maximumPages,
        'maximumPages',
        'Must be positive.',
      );
    }
  }

  final TenantDirectoryGateway _gateway;
  final int pageSize;
  final int maximumPages;

  Future<List<TenantMembership>> loadAll() async {
    final memberships = <TenantMembership>[];
    final seenTenantIds = <String>{};
    final seenCursors = <String>{};
    String? cursor;
    for (var pageNumber = 0; pageNumber < maximumPages; pageNumber++) {
      final page = await _gateway.listMyTenants(
        pageSize: pageSize,
        cursor: cursor,
      );
      for (final membership in page.items) {
        if (!seenTenantIds.add(membership.tenantId)) {
          throw StateError(
            'listMyTenants returned duplicate tenant ${membership.tenantId}.',
          );
        }
        memberships.add(membership);
      }
      if (!page.hasMore) return List.unmodifiable(memberships);
      final nextCursor = page.nextCursor!;
      if (!seenCursors.add(nextCursor)) {
        throw StateError('listMyTenants returned a repeated cursor.');
      }
      cursor = nextCursor;
    }
    throw StateError('Tenant pagination exceeded the safety limit.');
  }
}
