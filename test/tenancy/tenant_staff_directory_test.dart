import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('strict staff summaries', () {
    test('decodes canonical active, pending, and optional display fields', () {
      final owner = TenantStaffSummary.fromSnapshot(
        _staffSnapshot(
          'tenant-a',
          'owner-a',
          role: TenantRole.owner,
          name: '',
          phone: '',
        ),
        ownerUid: 'owner-a',
      );
      final pending = TenantStaffSummary.fromSnapshot(
        _staffSnapshot(
          'tenant-a',
          'cashier-a',
          status: MembershipStatus.pending,
          invitationStatus: TenantStaffInvitationStatus.sent,
        ),
        ownerUid: 'owner-a',
      );

      expect(owner.isOwner, isTrue);
      expect(owner.displayName, 'owner-a@example.test');
      expect(owner.name, isNull);
      expect(owner.phone, isNull);
      expect(pending.status, MembershipStatus.pending);
      expect(pending.invitationStatus, TenantStaffInvitationStatus.sent);
    });

    test('rejects mismatched UIDs and malformed owner projections', () {
      expect(
        () => TenantStaffSummary.fromSnapshot(
          _staffSnapshot('tenant-a', 'staff-a', projectedUid: 'staff-b'),
          ownerUid: 'owner-a',
        ),
        throwsFormatException,
      );
      expect(
        () => TenantStaffSummary.fromSnapshot(
          _staffSnapshot('tenant-a', 'staff-a', role: TenantRole.owner),
          ownerUid: 'owner-a',
        ),
        throwsFormatException,
      );
      expect(
        () => TenantStaffSummary.fromSnapshot(
          _staffSnapshot('tenant-a', 'owner-a', role: TenantRole.admin),
          ownerUid: 'owner-a',
        ),
        throwsFormatException,
      );
    });

    test('rejects unknown fields and inconsistent invitation state', () {
      final unknownRole = _staffData('staff-a')..['role'] = 'supervisor';
      final badEmail = _staffData('staff-a')
        ..['email'] = 'Staff-A@Example.test';
      final badInvitation = _staffData('staff-a')
        ..['status'] = 'inactive'
        ..['invitationStatus'] = 'sent';

      for (final data in [unknownRole, badEmail, badInvitation]) {
        expect(
          () => TenantStaffSummary.fromSnapshot(
            TenantQueryDocumentSnapshot(
              path: 'tenants/tenant-a/staff/staff-a',
              data: data,
            ),
            ownerUid: 'owner-a',
          ),
          throwsFormatException,
        );
      }
    });
  });

  group('staff repository pagination', () {
    test(
      'derives bounded staff pages and advances the document cursor',
      () async {
        final reader = _StaffReader(
          queryHandler: (_) async => [
            _staffSnapshot('tenant-a', 'owner-a', role: TenantRole.owner),
            _staffSnapshot('tenant-a', 'staff-a'),
            _staffSnapshot('tenant-a', 'staff-b'),
          ],
        );
        final repository = TenantStaffDirectoryRepository(
          session: _session('tenant-a'),
          reader: reader,
        );

        final page = await repository.loadPage(pageSize: 2);

        expect(reader.documentPaths, [
          'tenants/tenant-a',
          'tenants/tenant-a/staff/owner-a',
        ]);
        expect(reader.queries.single.collectionPath, 'tenants/tenant-a/staff');
        expect(reader.queries.single.limit, 3);
        expect(page.items.map((staff) => staff.uid), ['owner-a', 'staff-a']);
        expect(page.hasMore, isTrue);
        expect(page.nextCursor, 'staff-a');

        reader.queryHandler = (query) async {
          expect(query.startAfterDocumentId, 'staff-a');
          return [_staffSnapshot('tenant-a', 'staff-b')];
        };
        final lastPage = await repository.loadPage(
          pageSize: 2,
          cursor: page.nextCursor,
        );
        expect(lastPage.items.single.uid, 'staff-b');
        expect(lastPage.hasMore, isFalse);
        expect(lastPage.nextCursor, isNull);
      },
    );

    test('rejects malformed roots and cross-tenant staff results', () async {
      final badRootReader = _StaffReader(
        rootPathOverride: 'tenants/tenant-b',
        queryHandler: (_) async => const [],
      );
      await expectLater(
        TenantStaffDirectoryRepository(
          session: _session('tenant-a'),
          reader: badRootReader,
        ).loadPage(),
        throwsA(isA<TenantScopeViolation>()),
      );

      final crossTenantReader = _StaffReader(
        queryHandler: (_) async => [_staffSnapshot('tenant-b', 'staff-a')],
      );
      await expectLater(
        TenantStaffDirectoryRepository(
          session: _session('tenant-a'),
          reader: crossTenantReader,
        ).loadPage(),
        throwsA(isA<TenantScopeViolation>()),
      );
    });
  });

  group('guarded staff directory', () {
    testWidgets('an owner inherits admin access through the safe landing', (
      tester,
    ) async {
      final controller = TenantSessionController()
        ..open(
          uid: 'owner-a',
          membership: _membership('tenant-a', role: TenantRole.owner),
        );
      final reader = _StaffReader(
        queryHandler: (_) async => [
          _staffSnapshot(
            'tenant-a',
            'owner-a',
            role: TenantRole.owner,
            name: 'Owner Person',
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: TenantSessionScope(
            controller: controller,
            child: TenantSafeLandingScreen(
              membership: _membership('tenant-a', role: TenantRole.owner),
              reader: reader,
              onSignOut: () async {},
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('View staff directory'));
      await tester.pumpAndSettle();

      expect(find.text('Staff directory'), findsOneWidget);
      expect(find.text('Owner Person'), findsOneWidget);
      expect(find.textContaining('owner - active'), findsOneWidget);
      expect(find.text('Invite staff'), findsOneWidget);
    });

    testWidgets('a cashier is denied without starting any reads', (
      tester,
    ) async {
      final controller = TenantSessionController()
        ..open(
          uid: 'cashier-a',
          membership: _membership('tenant-a', role: TenantRole.cashier),
        );
      final reader = _StaffReader(queryHandler: (_) async => const []);

      await tester.pumpWidget(
        _staffApp(controller: controller, reader: reader),
      );

      expect(find.text('Tenant access unavailable.'), findsOneWidget);
      expect(reader.documentPaths, isEmpty);
      expect(reader.queries, isEmpty);
    });

    testWidgets('a tenant switch discards an outstanding staff page', (
      tester,
    ) async {
      final controller = TenantSessionController()
        ..open(uid: 'admin-a', membership: _membership('tenant-a'));
      final pending = <String, Completer<List<TenantQueryDocumentSnapshot>>>{};
      final reader = _StaffReader(
        queryHandler: (query) {
          final completer = Completer<List<TenantQueryDocumentSnapshot>>();
          pending[query.collectionPath] = completer;
          return completer.future;
        },
      );
      await tester.pumpWidget(
        _staffApp(controller: controller, reader: reader),
      );
      expect(pending, contains('tenants/tenant-a/staff'));

      controller.open(uid: 'admin-a', membership: _membership('tenant-b'));
      await tester.pump();
      expect(pending, contains('tenants/tenant-b/staff'));

      pending['tenants/tenant-a/staff']!.complete([
        _staffSnapshot('tenant-a', 'staff-a', name: 'Stale Staff'),
      ]);
      await tester.pump();
      expect(find.text('Stale Staff'), findsNothing);

      pending['tenants/tenant-b/staff']!.complete([
        _staffSnapshot('tenant-b', 'staff-b', name: 'Current Staff'),
      ]);
      await tester.pump();
      await tester.pump();
      expect(find.text('Business: tenant-b'), findsOneWidget);
      expect(find.text('Current Staff'), findsOneWidget);
      expect(find.text('Stale Staff'), findsNothing);
    });
  });
}

final class _StaffReader implements TenantDataReader {
  _StaffReader({required this.queryHandler, this.rootPathOverride});

  Future<List<TenantQueryDocumentSnapshot>> Function(TenantCollectionQuery)
  queryHandler;
  final String? rootPathOverride;
  final List<String> documentPaths = [];
  final List<TenantCollectionQuery> queries = [];

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    documentPaths.add(path);
    if (RegExp(r'^tenants/[^/]+$').hasMatch(path)) {
      final tenantId = path.split('/').last;
      return TenantDocumentSnapshot(
        path: rootPathOverride ?? path,
        data: {'ownerUid': 'owner-${tenantId.split('-').last}'},
      );
    }
    final ownerMatch = RegExp(
      r'^tenants/[^/]+/staff/(owner-[^/]+)$',
    ).firstMatch(path);
    if (ownerMatch == null) return null;
    final ownerUid = ownerMatch.group(1)!;
    return TenantDocumentSnapshot(
      path: path,
      data: _staffData(ownerUid)
        ..['role'] = TenantRole.owner.wireValue
        ..['status'] = MembershipStatus.active.wireValue
        ..['invitationStatus'] = TenantStaffInvitationStatus.accepted.wireValue
        ..['name'] = 'Owner Person'
        ..['email'] = '$ownerUid@example.test',
    );
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) {
    queries.add(query);
    return queryHandler(query);
  }
}

Widget _staffApp({
  required TenantSessionController controller,
  required TenantDataReader reader,
}) => MaterialApp(
  home: TenantSessionScope(
    controller: controller,
    child: Scaffold(body: TenantStaffDirectoryPanel(reader: reader)),
  ),
);

TenantSession _session(String tenantId) => TenantSession.active(
  uid: 'admin-a',
  tenantId: tenantId,
  role: TenantRole.admin,
);

TenantQueryDocumentSnapshot _staffSnapshot(
  String tenantId,
  String uid, {
  String? projectedUid,
  TenantRole role = TenantRole.cashier,
  MembershipStatus status = MembershipStatus.active,
  TenantStaffInvitationStatus invitationStatus =
      TenantStaffInvitationStatus.accepted,
  String name = 'Staff Person',
  String phone = '+254700000000',
}) => TenantQueryDocumentSnapshot(
  path: 'tenants/$tenantId/staff/$uid',
  data: _staffData(projectedUid ?? uid)
    ..['role'] = role.wireValue
    ..['status'] = status.wireValue
    ..['invitationStatus'] = invitationStatus.wireValue
    ..['name'] = name
    ..['phone'] = phone,
);

Map<String, Object?> _staffData(String uid) => <String, Object?>{
  'uid': uid,
  'email': '$uid@example.test',
  'name': 'Staff Person',
  'phone': '+254700000000',
  'role': 'cashier',
  'status': 'active',
  'invitationStatus': 'accepted',
};

TenantMembership _membership(
  String tenantId, {
  TenantRole role = TenantRole.admin,
}) => TenantMembership(
  tenantId: tenantId,
  tenantName: tenantId,
  tenantSlug: tenantId,
  role: role,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  isOwner: role == TenantRole.owner,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 7, 29),
  updatedAt: DateTime.utc(2026, 7, 29),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);
