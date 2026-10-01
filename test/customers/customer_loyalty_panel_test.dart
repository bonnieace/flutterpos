import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uzapay_pos/checkout/checkout_configuration_writer.dart';
import 'package:uzapay_pos/customers/customers.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';

import '../support/notices.dart';

/// Configs → Loyalty: whether customers earn points, and for how much.
void main() {
  testWidgets('a business that never set loyalty earns no points', (
    tester,
  ) async {
    await _pump(tester, const _Reader());

    expect(find.text('No points'), findsOneWidget);
    expect(find.byKey(const ValueKey('loyalty-rate')), findsNothing);
  });

  testWidgets('turning points on publishes the rate in minor units', (
    tester,
  ) async {
    final writer = _Writer();
    await _pump(tester, const _Reader(), writer: writer);

    await tester.tap(find.byKey(const ValueKey('loyalty-enabled')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('loyalty-enabled-yes')).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('loyalty-rate')), '50');
    await tester.pumpAndSettle();
    // A whole amount reads without `.00`, as money does on every screen.
    expect(find.text('One point for every KES 50 spent.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('loyalty-settings-save')));
    await tester.pumpAndSettle();

    expect(writer.path, 'tenants/tenant-a/configuration/loyalty');
    expect(writer.data?['enabled'], isTrue);
    expect(writer.data?['minorUnitsPerPoint'], 5000);
    expect(snackNotice(tester).message, contains('earn at this rate'));
  });

  testWidgets('a rate of nothing is refused on the form', (tester) async {
    final writer = _Writer();
    await _pump(tester, const _Reader(), writer: writer);

    await tester.tap(find.byKey(const ValueKey('loyalty-enabled')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('loyalty-enabled-yes')).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('loyalty-rate')), '0');
    await tester.tap(find.byKey(const ValueKey('loyalty-settings-save')));
    await tester.pumpAndSettle();

    expect(writer.path, isNull);
    expect(find.text('Enter an amount more than zero.'), findsOneWidget);
  });

  testWidgets('a manager is told it is not theirs to decide', (tester) async {
    await _pump(tester, const _Reader(), role: TenantRole.manager);

    expect(find.textContaining('Only an owner or administrator'), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester,
  _Reader reader, {
  TenantConfigurationDocumentWriter? writer,
  TenantRole role = TenantRole.owner,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = TenantSessionController()
    ..open(
      uid: 'user-a',
      membership: TenantMembership(
        tenantId: 'tenant-a',
        tenantName: 'tenant-a',
        tenantSlug: 'tenant-a',
        role: role,
        membershipStatus: MembershipStatus.active,
        tenantStatus: TenantStatus.active,
        isOwner: role == TenantRole.owner,
        mirrorVersion: 1,
        createdAt: DateTime.utc(2026, 8, 1),
        updatedAt: DateTime.utc(2026, 8, 1),
        serverCanAccess: true,
        canonicalTenantExists: true,
        canonicalMembershipExists: true,
      ),
    );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: Scaffold(
          body: SingleChildScrollView(
            child: TenantLoyaltySettingsPanel(
              reader: reader,
              writer: writer ?? _Writer(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _Writer implements TenantConfigurationDocumentWriter {
  String? path;
  Map<String, Object?>? data;

  @override
  Future<TenantConfigurationWriteResult> merge({
    required String path,
    required Map<String, Object?> data,
  }) async {
    this.path = path;
    this.data = data;
    return const TenantConfigurationWriteResult.committed();
  }
}

final class _Reader implements TenantDataReader {
  const _Reader();

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    if (path == 'tenants/tenant-a/configuration/checkout') {
      return TenantDocumentSnapshot(
        path: path,
        data: const <String, Object?>{'currency': 'KES'},
      );
    }
    return null;
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async => const <TenantQueryDocumentSnapshot>[];
}
