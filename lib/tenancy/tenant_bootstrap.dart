import 'tenant_directory.dart';
import 'tenant_id.dart';
import 'tenant_membership.dart';
import 'root_routing_profile_cache.dart';
import 'tenant_selection.dart';

enum RootAccountType { tenantUser, platformAdmin }

final class RootRoutingProfile {
  const RootRoutingProfile({
    required this.accountType,
    required this.globalStatus,
    this.defaultTenantId,
  });

  factory RootRoutingProfile.fromJson(Map<String, Object?> json) {
    final accountType = switch (json['accountType']) {
      'tenant_user' => RootAccountType.tenantUser,
      'platform_admin' => RootAccountType.platformAdmin,
      final value => throw FormatException('Invalid accountType: $value'),
    };
    final globalStatus = json['globalStatus'];
    if (globalStatus != 'active' && globalStatus != 'disabled') {
      throw FormatException('Invalid globalStatus: $globalStatus');
    }
    final rawDefaultTenantId = json['defaultTenantId'];
    if (rawDefaultTenantId != null && rawDefaultTenantId is! String) {
      throw const FormatException('defaultTenantId must be a nullable string.');
    }
    String? defaultTenantId;
    if (rawDefaultTenantId is String) {
      try {
        defaultTenantId = validateTenantId(rawDefaultTenantId);
      } on ArgumentError catch (error) {
        throw FormatException('Invalid defaultTenantId: ${error.message}');
      }
    }
    return RootRoutingProfile(
      accountType: accountType,
      globalStatus: globalStatus as String,
      defaultTenantId: defaultTenantId,
    );
  }

  final RootAccountType accountType;
  final String globalStatus;
  final String? defaultTenantId;

  bool get isActive => globalStatus == 'active';

  Map<String, Object?> toJson() => <String, Object?>{
    'accountType': switch (accountType) {
      RootAccountType.tenantUser => 'tenant_user',
      RootAccountType.platformAdmin => 'platform_admin',
    },
    'globalStatus': globalStatus,
    if (defaultTenantId != null) 'defaultTenantId': defaultTenantId,
  };
}

abstract interface class RootRoutingGateway {
  Future<RootRoutingProfile> getRootRoutingProfile(String uid);
}

/// Optional migration seam over Firestore's already-persisted device cache.
abstract interface class CachedRootRoutingGateway {
  Future<RootRoutingProfile?> getCachedRootRoutingProfile(String uid);
}

final class TenantBootstrapUnavailable implements Exception {
  const TenantBootstrapUnavailable(this.code);

  final String code;

  @override
  String toString() => 'TenantBootstrapUnavailable($code)';
}

enum TenantBootstrapTraceKind {
  cacheHit,
  cacheMiss,
  refreshSucceeded,
  refreshUnavailable,
  refreshFailed,
}

final class TenantBootstrapTrace {
  const TenantBootstrapTrace({
    required this.kind,
    this.elapsedMilliseconds,
    this.cacheAgeSeconds,
  });

  final TenantBootstrapTraceKind kind;
  final int? elapsedMilliseconds;
  final int? cacheAgeSeconds;

  Map<String, Object?> toData() => <String, Object?>{
    'kind': kind.name,
    if (elapsedMilliseconds != null) 'elapsedMilliseconds': elapsedMilliseconds,
    if (cacheAgeSeconds != null) 'cacheAgeSeconds': cacheAgeSeconds,
  };
}

typedef TenantBootstrapObserver = void Function(TenantBootstrapTrace event);

abstract interface class TenantSelectionStore {
  Future<String?> readLastSelectedTenant(String uid);
  Future<void> writeLastSelectedTenant(String uid, String tenantId);
}

enum TenantBootstrapKind { tenant, selector, noAccessibleTenant, platform }

final class TenantBootstrapResult {
  const TenantBootstrapResult({
    required this.kind,
    required this.profile,
    required this.selection,
    this.fromCache = false,
    this.cachedAt,
  });

  final TenantBootstrapKind kind;
  final RootRoutingProfile profile;
  final TenantSelectionDecision selection;

  /// True where the businesses were read from this device rather than from the
  /// server, because the server could not be reached.
  ///
  /// **Carried so the app can say so.** Routing from a cache is the difference
  /// between a till that opens in a basement and one that does not, but a
  /// screen presenting remembered state as live state is the untruthfulness
  /// `DESIGN_RULES.md` rules out. The shell owes the person a sentence.
  final bool fromCache;

  /// When that copy was written, or null where this came from the server.
  final DateTime? cachedAt;
}

final class TenantBootstrapService {
  TenantBootstrapService({
    required RootRoutingGateway rootGateway,
    required TenantDirectory directory,
    required TenantSelectionStore selectionStore,
    RootRoutingProfileCache rootCache = const NullRootRoutingProfileCache(),
    TenantBootstrapObserver? observer,
  }) : _rootGateway = rootGateway,
       _directory = directory,
       _selectionStore = selectionStore,
       _rootCache = rootCache,
       _observer = observer;

  final RootRoutingGateway _rootGateway;
  final TenantDirectory _directory;
  final TenantSelectionStore _selectionStore;
  final RootRoutingProfileCache _rootCache;
  final TenantBootstrapObserver? _observer;

  /// Opens only from device state. Null means this account has not been primed.
  Future<TenantBootstrapResult?> loadCached(String uid) async {
    final normalizedUid = _uid(uid);
    var root = await _rootCache.read(normalizedUid);
    if (root == null && _rootGateway is CachedRootRoutingGateway) {
      final cache = _rootGateway as CachedRootRoutingGateway;
      try {
        final migrated = await cache.getCachedRootRoutingProfile(normalizedUid);
        if (migrated != null) {
          root = CachedRootRoutingProfile(
            profile: migrated,
            cachedAt: DateTime.now().toUtc(),
          );
          try {
            await _rootCache.write(normalizedUid, migrated);
          } catch (_) {}
        }
      } catch (_) {}
    }
    final directory = await _directory.loadCached(uid: normalizedUid);
    if (root == null || directory == null) {
      _observer?.call(
        const TenantBootstrapTrace(kind: TenantBootstrapTraceKind.cacheMiss),
      );
      return null;
    }
    final profile = root.profile;
    // A stale disabled or platform projection may never grant tenant access.
    if (!profile.isActive ||
        profile.accountType == RootAccountType.platformAdmin) {
      _observer?.call(
        const TenantBootstrapTrace(kind: TenantBootstrapTraceKind.cacheMiss),
      );
      return null;
    }
    final cachedAt = root.cachedAt.isBefore(directory.cachedAt!)
        ? root.cachedAt
        : directory.cachedAt!;
    _observer?.call(
      TenantBootstrapTrace(
        kind: TenantBootstrapTraceKind.cacheHit,
        cacheAgeSeconds: DateTime.now().toUtc().difference(cachedAt).inSeconds,
      ),
    );
    return _resolve(
      uid: normalizedUid,
      profile: profile,
      directory: directory,
      fromCache: true,
      cachedAt: cachedAt,
    );
  }

  /// Reads the authoritative routing projection and refreshes both caches.
  Future<TenantBootstrapResult> refresh(String uid) async {
    final stopwatch = Stopwatch()..start();
    try {
      final result = await _refreshAuthoritative(uid);
      _observer?.call(
        TenantBootstrapTrace(
          kind: TenantBootstrapTraceKind.refreshSucceeded,
          elapsedMilliseconds: stopwatch.elapsedMilliseconds,
        ),
      );
      return result;
    } catch (error) {
      final unavailable =
          error is TenantBootstrapUnavailable ||
          error is TenantDirectoryUnavailable;
      _observer?.call(
        TenantBootstrapTrace(
          kind: unavailable
              ? TenantBootstrapTraceKind.refreshUnavailable
              : TenantBootstrapTraceKind.refreshFailed,
          elapsedMilliseconds: stopwatch.elapsedMilliseconds,
        ),
      );
      rethrow;
    }
  }

  Future<TenantBootstrapResult> _refreshAuthoritative(String uid) async {
    final normalizedUid = _uid(uid);
    final RootRoutingProfile profile;
    try {
      profile = await _rootGateway.getRootRoutingProfile(normalizedUid);
    } on TenantBootstrapUnavailable {
      rethrow;
    }
    if (!profile.isActive) {
      throw StateError('The signed-in account is disabled.');
    }
    if (profile.accountType == RootAccountType.platformAdmin) {
      try {
        await _rootCache.write(normalizedUid, profile);
      } catch (_) {}
      return TenantBootstrapResult(
        kind: TenantBootstrapKind.platform,
        profile: profile,
        selection: resolveTenantSelection(memberships: const []),
      );
    }

    final results = await Future.wait<Object?>([
      _directory.refresh(uid: normalizedUid),
      _selectionStore.readLastSelectedTenant(normalizedUid),
    ]);
    final directory = results[0]! as TenantDirectoryLoad;
    try {
      await _rootCache.write(normalizedUid, profile);
    } catch (_) {}
    return _resolve(
      uid: normalizedUid,
      profile: profile,
      directory: directory,
      lastSelectedTenantId: results[1] as String?,
    );
  }

  /// Compatibility name for callers that explicitly want a live bootstrap.
  Future<TenantBootstrapResult> load(String uid) => refresh(uid);

  Future<TenantBootstrapResult> _resolve({
    required String uid,
    required RootRoutingProfile profile,
    required TenantDirectoryLoad directory,
    String? lastSelectedTenantId,
    bool fromCache = false,
    DateTime? cachedAt,
  }) async {
    lastSelectedTenantId ??= await _selectionStore.readLastSelectedTenant(uid);
    final selection = resolveTenantSelection(
      memberships: directory.memberships,
      lastSelectedTenantId: lastSelectedTenantId,
      defaultTenantId: profile.defaultTenantId,
    );
    final kind = switch (selection.source) {
      TenantSelectionSource.lastSelected ||
      TenantSelectionSource.accountDefault ||
      TenantSelectionSource.soleAccessible => TenantBootstrapKind.tenant,
      TenantSelectionSource.selector => TenantBootstrapKind.selector,
      TenantSelectionSource.none => TenantBootstrapKind.noAccessibleTenant,
    };
    return TenantBootstrapResult(
      kind: kind,
      profile: profile,
      selection: selection,
      fromCache: fromCache,
      cachedAt: cachedAt,
    );
  }

  String _uid(String uid) {
    final normalized = uid.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(uid, 'uid', 'Cannot be empty.');
    }
    return normalized;
  }

  /// Revalidates the canonical projection before persisting a device-local
  /// selection. Callers should open the returned membership in the session
  /// controller; an inaccessible or stale tenant is never remembered.
  Future<TenantMembership> openTenant({
    required String uid,
    required String tenantId,
  }) async {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      throw ArgumentError.value(uid, 'uid', 'Cannot be empty.');
    }
    final normalizedTenantId = validateTenantId(tenantId);
    final membership = await revalidateTenant(
      normalizedTenantId,
      uid: normalizedUid,
    );
    await _selectionStore.writeLastSelectedTenant(
      normalizedUid,
      normalizedTenantId,
    );
    return membership;
  }

  Future<TenantMembership> revalidateTenant(
    String tenantId, {
    String? uid,
  }) async {
    final membership = await findAccessibleTenant(tenantId, uid: uid);
    if (membership == null) {
      throw StateError('The selected tenant is no longer accessible.');
    }
    return membership;
  }

  /// Returns the exact accessible canonical projection, while allowing
  /// directory transport/format failures to remain distinguishable.
  Future<TenantMembership?> findAccessibleTenant(
    String tenantId, {
    String? uid,
  }) async {
    final normalizedTenantId = validateTenantId(tenantId);
    final memberships = (await _directory.load(uid: uid)).memberships;
    final matches = memberships.where(
      (membership) => membership.tenantId == normalizedTenantId,
    );
    if (matches.length != 1 || !matches.single.canAccess()) {
      return null;
    }
    return matches.single;
  }

  /// Remembers a tenant only after its authorized session has been opened.
  Future<void> rememberOpenedTenant({
    required String uid,
    required String tenantId,
  }) async {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      throw ArgumentError.value(uid, 'uid', 'Cannot be empty.');
    }
    await _selectionStore.writeLastSelectedTenant(
      normalizedUid,
      validateTenantId(tenantId),
    );
  }
}
