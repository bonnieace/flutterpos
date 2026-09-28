import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uzapay_pos/checkout/checkout_configuration_writer.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';

import '../support/collection_pages.dart';

const String _tenant = 'tenant-a';
const String _owner = 'owner';
const String _root = 'tenants/$_tenant';

void main() {
  testWidgets('account deletion is a full-width button under the save', (
    tester,
  ) async {
    // Play asks that deleting an account be reachable inside the app.
    var requested = 0;
    await _pump(tester, onRequestAccountDeletion: () => requested++);

    final save = find.byKey(const ValueKey('branding-save'));
    final delete = find.byKey(const ValueKey('request-account-deletion'));
    expect(delete, findsOneWidget);
    expect(
      tester.getTopLeft(delete).dy,
      greaterThan(tester.getBottomLeft(save).dy),
    );
    expect(tester.getSize(delete).width, tester.getSize(save).width);

    await tester.tap(delete);
    expect(requested, 1);
  });

  testWidgets('no deletion button is drawn while none is supplied', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.byKey(const ValueKey('branding-save')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('request-account-deletion')),
      findsNothing,
    );
  });
}

Future<void> _pump(
  WidgetTester tester, {
  VoidCallback? onRequestAccountDeletion,
}) async {
  tester.view.physicalSize = const Size(420, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: TenantSessionController()
          ..open(uid: _owner, membership: _membership()),
        child: Scaffold(
          body: SingleChildScrollView(
            child: TenantBrandingPanel(
              reader: _Reader(),
              writer: _Writer(),
              onRequestAccountDeletion: onRequestAccountDeletion,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

TenantMembership _membership() => TenantMembership(
  tenantId: _tenant,
  tenantName: _tenant,
  tenantSlug: _tenant,
  role: TenantRole.owner,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  isOwner: true,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 8, 1),
  updatedAt: DateTime.utc(2026, 8, 1),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);

final class _Writer implements TenantConfigurationDocumentWriter {
  @override
  Future<TenantConfigurationWriteResult> merge({
    required String path,
    required Map<String, Object?> data,
  }) async => const TenantConfigurationWriteResult.committed();
}

/// A business with nothing published, which the panel reads as a form seeded
/// from the registered name.
final class _Reader implements TenantDataReader {
  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async =>
      path == _root
      ? TenantDocumentSnapshot(
          path: path,
          data: <String, Object?>{
            'tenantId': _tenant,
            'name': _tenant,
            'status': 'active',
            'ownerUid': _owner,
          },
        )
      : null;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async =>
      tenantCollectionPageOf(query, const <TenantQueryDocumentSnapshot>[]);
}
