import 'tenant_directory.dart';
import 'tenant_id.dart';
import 'tenant_membership.dart';
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
}

abstract interface class RootRoutingGateway {
  Future<RootRoutingProfile> getRootRoutingProfile(String uid);
}

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
  });

  final TenantBootstrapKind kind;
  final RootRoutingProfile profile;
  final TenantSelectionDecision selection;
}

final class TenantBootstrapService {
  TenantBootstrapService({
    required RootRoutingGateway rootGateway,
    required TenantDirectory directory,
    required TenantSelectionStore selectionStore,
  }) : _rootGateway = rootGateway,
       _directory = directory,
       _selectionStore = selectionStore;

  final RootRoutingGateway _rootGateway;
  final TenantDirectory _directory;
  final TenantSelectionStore _selectionStore;

  Future<TenantBootstrapResult> load(String uid) async {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      throw ArgumentError.value(uid, 'uid', 'Cannot be empty.');
    }
    final profile = await _rootGateway.getRootRoutingProfile(normalizedUid);
    if (!profile.isActive) {
      throw StateError('The signed-in account is disabled.');
    }
    if (profile.accountType == RootAccountType.platformAdmin) {
      return TenantBootstrapResult(
        kind: TenantBootstrapKind.platform,
        profile: profile,
        selection: resolveTenantSelection(memberships: const []),
      );
    }

    final results = await Future.wait<Object?>([
      _directory.loadAll(),
      _selectionStore.readLastSelectedTenant(normalizedUid),
    ]);
    final memberships = results[0]! as List<TenantMembership>;
    final lastSelectedTenantId = results[1] as String?;
    final selection = resolveTenantSelection(
      memberships: memberships,
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
    );
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
    final membership = await revalidateTenant(normalizedTenantId);
    await _selectionStore.writeLastSelectedTenant(
      normalizedUid,
      normalizedTenantId,
    );
    return membership;
  }

  Future<TenantMembership> revalidateTenant(String tenantId) async {
    final normalizedTenantId = validateTenantId(tenantId);
    final memberships = await _directory.loadAll();
    final matches = memberships.where(
      (membership) => membership.tenantId == normalizedTenantId,
    );
    if (matches.length != 1 || !matches.single.canAccess()) {
      throw StateError('The selected tenant is no longer accessible.');
    }
    return matches.single;
  }
}
