import 'package:hive/hive.dart';

import 'tenant_bootstrap.dart';
import 'tenant_id.dart';
import 'tenant_selection.dart';

final class HiveTenantSelectionStore implements TenantSelectionStore {
  const HiveTenantSelectionStore(this._box);

  static const boxName = 'tenant-routing-v1';

  final Box<String> _box;

  @override
  Future<String?> readLastSelectedTenant(String uid) async =>
      _box.get(lastSelectedTenantStorageKey(uid));

  @override
  Future<void> writeLastSelectedTenant(String uid, String tenantId) =>
      _box.put(lastSelectedTenantStorageKey(uid), validateTenantId(tenantId));
}
