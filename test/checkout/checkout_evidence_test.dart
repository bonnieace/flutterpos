import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  group('outbox evidence counts', () {
    late Directory directory;
    late Box<dynamic> box;
    late HiveCheckoutOutbox outbox;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'checkout-evidence-test-',
      );
      Hive.init(directory.path);
      box = await Hive.openBox<dynamic>(
        HiveCheckoutOutbox.boxName,
        encryptionCipher: HiveAesCipher(_encryptionKey),
        crashRecovery: false,
      );
      outbox = HiveCheckoutOutbox.fromBox(box);
    });

    tearDown(() async {
      await Hive.close();
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test('counts only the exact session UID and tenant', () async {
      await _save(outbox, 'checkout-a');
      await _save(outbox, 'checkout-b');
      await _save(outbox, 'other-tenant', tenantId: 'tenant-b');
      await _save(outbox, 'other-user', uid: 'user-b');
      await outbox.beginSubmission(
        uid: 'user-a',
        tenantId: 'tenant-a',
        checkoutId: 'checkout-b',
        leaseOwner: 'worker-a',
        leaseDuration: const Duration(minutes: 2),
      );

      final counts = await CheckoutOutboxEvidenceSource(
        outbox,
      ).summarize(_session());

      expect(counts.savedOffline, 1);
      expect(counts.submitting, 1);
      expect(counts.awaitingConfirmation, 0);
      expect(counts.confirmed, 0);
      expect(counts.needsAttention, 0);
      expect(counts.total, 2);
      expect(counts.unsettled, 2);
    });
  });

  group('pending evidence panel', () {
    testWidgets('renders read-only counts for the live session', (
      tester,
    ) async {
      await _pumpPanel(
        tester,
        const _FakeSource(
          CheckoutEvidenceSummary(
            savedOffline: 2,
            submitting: 1,
            awaitingConfirmation: 3,
            needsAttention: 1,
            confirmed: 4,
          ),
        ),
      );

      expect(find.text('Saved offline: 2'), findsOneWidget);
      expect(find.text('Submitting: 1'), findsOneWidget);
      expect(find.text('Awaiting confirmation: 3'), findsOneWidget);
      expect(find.text('Needs attention: 1'), findsOneWidget);
      expect(find.text('Confirmed: 4'), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets('states plainly when no checkout is stored', (tester) async {
      await _pumpPanel(tester, const _FakeSource(CheckoutEvidenceSummary()));

      expect(
        find.text('No checkouts are stored on this device.'),
        findsOneWidget,
      );
    });

    testWidgets('renders nothing without an authorized session', (
      tester,
    ) async {
      final controller = TenantSessionController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: TenantSessionScope(
            controller: controller,
            child: const Scaffold(
              body: CheckoutPendingEvidencePanel(
                source: _FakeSource(CheckoutEvidenceSummary(savedOffline: 9)),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Saved offline: 9'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('reports unavailable local evidence without details', (
      tester,
    ) async {
      await _pumpPanel(tester, const _FailingSource());

      expect(
        find.text('Local checkout evidence is unavailable.'),
        findsOneWidget,
      );
      expect(find.textContaining('malformed_record'), findsNothing);
    });
  });
}

Future<void> _pumpPanel(
  WidgetTester tester,
  CheckoutEvidenceSource source,
) async {
  final controller = TenantSessionController()
    ..open(uid: 'user-a', membership: _membership('tenant-a'));
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: Scaffold(body: CheckoutPendingEvidencePanel(source: source)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<CheckoutOutboxRecord> _save(
  HiveCheckoutOutbox outbox,
  String checkoutId, {
  String uid = 'user-a',
  String tenantId = 'tenant-a',
}) => outbox.saveOffline(
  uid: uid,
  tenantId: tenantId,
  checkoutId: checkoutId,
  payload: <String, Object?>{'checkoutId': checkoutId},
);

TenantSession _session() =>
    TenantSession.fromMembership(uid: 'user-a', membership: _membership('tenant-a'));

final List<int> _encryptionKey = List<int>.generate(
  HiveCheckoutOutbox.encryptionKeyBytes,
  (index) => (index * 3) % 256,
);

final class _FakeSource implements CheckoutEvidenceSource {
  const _FakeSource(this._summary);

  final CheckoutEvidenceSummary _summary;

  @override
  Future<CheckoutEvidenceSummary> summarize(TenantSession session) async =>
      _summary;
}

final class _FailingSource implements CheckoutEvidenceSource {
  const _FailingSource();

  @override
  Future<CheckoutEvidenceSummary> summarize(TenantSession session) async =>
      throw const CheckoutOutboxException('malformed_record');
}

TenantMembership _membership(String tenantId) => TenantMembership(
  tenantId: tenantId,
  tenantName: tenantId,
  tenantSlug: tenantId,
  role: TenantRole.cashier,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  isOwner: false,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);
