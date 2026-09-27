import 'tenant_directory_cache.dart';
import 'tenant_membership.dart';
import '../observability/app_telemetry.dart';

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

/// The directory could not be reached, as opposed to refusing to answer.
///
/// **The distinction is the whole safety property of the offline fallback.**
/// A device may fall back to what it last knew when it *could not ask*; it may
/// never fall back when the server answered and the answer was no. So the
/// gateway raises this only for transport failures, and an authorization
/// refusal keeps propagating as itself.
final class TenantDirectoryUnavailable implements Exception {
  const TenantDirectoryUnavailable(this.code);

  /// The transport's own code, kept for the failure surface to name.
  final String code;

  @override
  String toString() => 'TenantDirectoryUnavailable($code)';
}

abstract interface class TenantDirectoryGateway {
  Future<TenantListPage> listMyTenants({required int pageSize, String? cursor});
}

/// A directory load, and whether it came from the server or from memory.
final class TenantDirectoryLoad {
  const TenantDirectoryLoad({
    required this.memberships,
    required this.fromCache,
    this.cachedAt,
  });

  final List<TenantMembership> memberships;

  /// True where the server could not be reached and this device answered from
  /// its own last copy. Carried all the way to the shell so the app can say so
  /// rather than quietly presenting stale routing as live.
  final bool fromCache;

  /// When that copy was written, or null where this came from the server.
  final DateTime? cachedAt;
}

/// Loads every page before applying sole-tenant or selector routing logic.
final class TenantDirectory {
  TenantDirectory(
    this._gateway, {
    this.pageSize = 50,
    this.maximumPages = 200,
    TenantDirectoryCache cache = const NullTenantDirectoryCache(),
  }) : _cache = cache {
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
  final TenantDirectoryCache _cache;

  /// Reads only the UID-bound projection already stored on this device.
  Future<TenantDirectoryLoad?> loadCached({required String uid}) async {
    final cached = await _cache.read(uid);
    if (cached == null) return null;
    return TenantDirectoryLoad(
      memberships: cached.memberships,
      fromCache: true,
      cachedAt: cached.cachedAt,
    );
  }

  /// Reads the authoritative directory once and refreshes the device copy.
  Future<TenantDirectoryLoad> refresh({required String uid}) async {
    final memberships = await _loadEveryPage();
    try {
      await _cache.write(uid, memberships);
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'tenancy.directory_cache_write',
      );
    }
    return TenantDirectoryLoad(memberships: memberships, fromCache: false);
  }

  /// Every page, from the server, falling back to this device's last copy.
  ///
  /// **The fallback needs a [uid] and silently declines without one**, because
  /// the cache is keyed by account and answering the wrong one would be worse
  /// than answering nothing. The one caller that passes none is the tenant
  /// switcher, which is already online-gated and must not be rescued by a
  /// cache anyway.
  Future<TenantDirectoryLoad> load({String? uid}) async {
    try {
      if (uid != null) return await refresh(uid: uid);
      final memberships = await _loadEveryPage();
      return TenantDirectoryLoad(memberships: memberships, fromCache: false);
    } on TenantDirectoryUnavailable {
      if (uid == null) rethrow;
      final cached = await loadCached(uid: uid);
      if (cached == null) rethrow;
      return cached;
    }
  }

  /// The server's answer, with no fallback. Kept because a caller that wants
  /// the canonical list and nothing else should not have to ask twice.
  Future<List<TenantMembership>> loadAll() => _loadEveryPage();

  Future<List<TenantMembership>> _loadEveryPage() async {
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
