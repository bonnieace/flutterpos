import 'package:flutter_test/flutter_test.dart';
import 'package:uzapay_pos/observability/app_telemetry.dart';
import 'package:uzapay_pos/reporting/reporting.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';

void main() {
  // The owner's staff document is one this device never downloaded, so a
  // cache-only reader answers it as absent and the directory's owner check
  // fails. That is what reached SIT as a `staff_options_read` error.
  var loads = 0;
  Future<(SalesTotalsSessionContext, RecordingAppTelemetry)> load({
    required bool cacheOnly,
  }) async {
    // The exception is `const`, and telemetry drops the same object reported
    // twice within two seconds, so each load reports at its own instant.
    final at = DateTime.utc(2026).add(Duration(days: ++loads));
    final telemetry = RecordingAppTelemetry(clock: () => at, retain: true);
    final context = await AppTelemetry.withInstance(
      telemetry,
      () => SalesTotalsSessionContextLoader(
        reader: _Reader({
          'tenants/tenant-a': {'ownerUid': 'owner-a'},
        }),
        cacheOnly: cacheOnly,
      ).load(_session),
    );
    return (context, telemetry);
  }

  test('a cache-only pass that cannot read the staff does not report', () async {
    final (context, telemetry) = await load(cacheOnly: true);
    expect(context.staff.readable, isFalse);
    expect(telemetry.failures, isEmpty);
  });

  test('the server pass still reports it', () async {
    final (context, telemetry) = await load(cacheOnly: false);
    expect(context.staff.readable, isFalse);
    final failure = telemetry.failures.single;
    expect(failure.operation.name, 'reporting.staff_options_read');
    expect(failure.message, contains('owner membership does not exist'));
  });
}

final _session = TenantSession.active(
  uid: 'owner-a',
  tenantId: 'tenant-a',
  role: TenantRole.owner,
);

final class _Reader implements TenantDataReader {
  _Reader(this._documents);

  final Map<String, Map<String, Object?>> _documents;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    final data = _documents[path];
    return data == null ? null : TenantDocumentSnapshot(path: path, data: data);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async => const [];
}
