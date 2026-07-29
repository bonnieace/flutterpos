import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('staff status contract', () {
    test('binds tenant and target with stable owner-as-admin intent', () async {
      final callable = _StatusCallable();
      var generatedIds = 0;
      final gateway = TenantStaffStatusGateway(
        session: _session('tenant-a', role: TenantRole.owner),
        target: _summary('tenant-a', 'staff-a'),
        callable: callable,
        requestIdFactory: () => 'status-request-${++generatedIds}',
      );
      final intent = gateway.createIntent(
        targetStatus: MembershipStatus.inactive,
      );

      final first = await gateway.submit(intent);
      final second = await gateway.submit(intent);

      expect(generatedIds, 1);
      expect(callable.payloads, hasLength(2));
      expect(callable.payloads.first, {
        'tenantId': 'tenant-a',
        'uid': 'staff-a',
        'status': 'inactive',
        'requestId': 'status-request-1',
      });
      expect(callable.payloads.last['requestId'], 'status-request-1');
      expect(first.uid, 'staff-a');
      expect(first.role, TenantRole.cashier);
      expect(second.status, MembershipStatus.inactive);
    });

    test('reactivates an accepted inactive membership', () async {
      final callable = _StatusCallable();
      final gateway = TenantStaffStatusGateway(
        session: _session('tenant-a', role: TenantRole.admin),
        target: _summary(
          'tenant-a',
          'staff-a',
          status: MembershipStatus.inactive,
        ),
        callable: callable,
        requestIdFactory: () => 'status-request-1',
      );

      final result = await gateway.submit(
        gateway.createIntent(targetStatus: MembershipStatus.active),
      );

      expect(callable.payloads.single['status'], 'active');
      expect(result.status, MembershipStatus.active);
    });

    test('rejects owner, pending, and no-op status changes', () {
      final session = _session('tenant-a', role: TenantRole.admin);
      for (final target in [
        _summary('tenant-a', 'owner-a', role: TenantRole.owner),
        _summary(
          'tenant-a',
          'pending-a',
          status: MembershipStatus.pending,
          invitationStatus: TenantStaffInvitationStatus.sent,
        ),
      ]) {
        final callable = _StatusCallable();
        final gateway = TenantStaffStatusGateway(
          session: session,
          target: target,
          callable: callable,
          requestIdFactory: () => 'status-request-1',
        );
        expect(
          () => gateway.createIntent(targetStatus: MembershipStatus.inactive),
          throwsFormatException,
        );
        expect(callable.payloads, isEmpty);
      }

      final callable = _StatusCallable();
      final gateway = TenantStaffStatusGateway(
        session: session,
        target: _summary('tenant-a', 'staff-a'),
        callable: callable,
        requestIdFactory: () => 'status-request-1',
      );
      expect(
        () => gateway.createIntent(targetStatus: MembershipStatus.active),
        throwsFormatException,
      );
      expect(
        () => gateway.createIntent(targetStatus: MembershipStatus.pending),
        throwsFormatException,
      );
      expect(callable.payloads, isEmpty);
    });

    test('denies manager and cashier sessions without callable requests', () {
      for (final role in [TenantRole.manager, TenantRole.cashier]) {
        final callable = _StatusCallable();
        final gateway = TenantStaffStatusGateway(
          session: _session('tenant-a', role: role),
          target: _summary('tenant-a', 'staff-a'),
          callable: callable,
          requestIdFactory: () => 'status-request-1',
        );
        expect(
          () => gateway.createIntent(targetStatus: MembershipStatus.inactive),
          throwsStateError,
        );
        expect(callable.payloads, isEmpty);
      }
    });

    test('strictly rejects malformed and mismatched callable responses', () {
      final valid = _statusResponse(
        'tenant-a',
        'staff-a',
        status: MembershipStatus.inactive,
      );
      final malformed = <Object?>[
        null,
        {...valid, 'tenantId': 'tenant-b'},
        {...valid, 'uid': 'staff-b'},
        {...valid, 'role': 'manager'},
        {...valid, 'status': 'active'},
        {...valid, 'unexpected': true},
        {...valid, 'uid': 'bad/uid'},
      ];

      for (final response in malformed) {
        expect(
          () => TenantStaffStatusResult.fromCallable(
            response,
            expectedTenantId: 'tenant-a',
            expectedUid: 'staff-a',
            expectedRole: TenantRole.cashier,
            expectedStatus: MembershipStatus.inactive,
          ),
          throwsFormatException,
        );
      }
    });
  });

  group('guarded staff status form', () {
    testWidgets('owner confirms deactivation and refreshes after success', (
      tester,
    ) async {
      final controller = TenantSessionController()
        ..open(
          uid: 'owner-a',
          membership: _membership('tenant-a', role: TenantRole.owner),
        );
      final callable = _StatusCallable();
      final reader = _DirectoryReader(includeStaff: true);

      await tester.pumpWidget(
        _directoryApp(
          controller: controller,
          reader: reader,
          callable: callable,
        ),
      );
      await tester.pumpAndSettle();
      expect(reader.queryCount, 1);
      expect(
        find.byKey(const ValueKey('set-staff-status-owner-a')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('set-staff-status-staff-a')));
      await tester.pump();
      expect(find.text('Deactivate Staff Person?'), findsOneWidget);
      expect(callable.payloads, isEmpty);

      await tester.tap(find.byKey(const ValueKey('set-staff-status-confirm')));
      await tester.pumpAndSettle();

      expect(callable.payloads.single, {
        'tenantId': 'tenant-a',
        'uid': 'staff-a',
        'status': 'inactive',
        'requestId': 'status-widget-request',
      });
      expect(reader.queryCount, 2);
      expect(find.text('Staff member inactive.'), findsOneWidget);
    });

    testWidgets('manager is read-only and cashier starts no calls or reads', (
      tester,
    ) async {
      final callable = _StatusCallable();
      final managerController = TenantSessionController()
        ..open(
          uid: 'manager-a',
          membership: _membership('tenant-a', role: TenantRole.manager),
        );
      final managerReader = _DirectoryReader(includeStaff: true);
      await tester.pumpWidget(
        _directoryApp(
          controller: managerController,
          reader: managerReader,
          callable: callable,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.person_off_outlined), findsNothing);
      expect(managerReader.queryCount, 1);

      final cashierController = TenantSessionController()
        ..open(
          uid: 'cashier-a',
          membership: _membership('tenant-a', role: TenantRole.cashier),
        );
      final cashierReader = _DirectoryReader();
      await tester.pumpWidget(
        _directoryApp(
          controller: cashierController,
          reader: cashierReader,
          callable: callable,
        ),
      );
      await tester.pump();
      expect(find.text('Tenant access unavailable.'), findsOneWidget);
      expect(cashierReader.documentPaths, isEmpty);
      expect(cashierReader.queryCount, 0);
      expect(callable.payloads, isEmpty);
    });

    testWidgets('confirmation cancellation makes no callable request', (
      tester,
    ) async {
      final controller = TenantSessionController()
        ..open(uid: 'admin-a', membership: _membership('tenant-a'));
      final callable = _StatusCallable();
      var cancellations = 0;
      await tester.pumpWidget(
        _formApp(
          controller: controller,
          target: _summary('tenant-a', 'staff-a'),
          callable: callable,
          onCancel: () => cancellations++,
        ),
      );

      await tester.tap(find.byKey(const ValueKey('set-staff-status-cancel')));
      await tester.pump();

      expect(cancellations, 1);
      expect(callable.payloads, isEmpty);
    });

    testWidgets('duplicate taps are single-flight and retry reuses intent', (
      tester,
    ) async {
      final controller = TenantSessionController()
        ..open(uid: 'admin-a', membership: _membership('tenant-a'));
      final first = Completer<Object?>();
      final callable = _StatusCallable(
        handler: (payload, callIndex) => callIndex == 0
            ? first.future
            : Future.value(
                _statusResponse(
                  payload['tenantId']! as String,
                  payload['uid']! as String,
                  status: MembershipStatus.fromWire(payload['status']),
                ),
              ),
      );
      var successes = 0;
      await tester.pumpWidget(
        _formApp(
          controller: controller,
          target: _summary('tenant-a', 'staff-a'),
          callable: callable,
          onSuccess: () => successes++,
        ),
      );

      final submit = find.byKey(const ValueKey('set-staff-status-confirm'));
      await tester.tap(submit);
      await tester.tap(submit);
      await tester.pump();
      expect(callable.payloads, hasLength(1));

      first.completeError(StateError('raw backend secret detail'));
      await tester.pump();
      await tester.pump();
      expect(
        find.text('Staff status could not be changed. Please try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('raw backend'), findsNothing);
      expect(successes, 0);

      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(callable.payloads, hasLength(2));
      expect(
        callable.payloads.first['requestId'],
        callable.payloads.last['requestId'],
      );
      expect(successes, 1);
    });

    testWidgets('tenant switch discards an outstanding success', (
      tester,
    ) async {
      final controller = TenantSessionController()
        ..open(uid: 'admin-a', membership: _membership('tenant-a'));
      final pending = Completer<Object?>();
      final callable = _StatusCallable(handler: (_, _) => pending.future);
      var successes = 0;
      await tester.pumpWidget(
        _formApp(
          controller: controller,
          target: _summary('tenant-a', 'staff-a'),
          callable: callable,
          onSuccess: () => successes++,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('set-staff-status-confirm')));
      await tester.pump();

      controller.open(uid: 'admin-a', membership: _membership('tenant-b'));
      await tester.pump();
      pending.complete(
        _statusResponse(
          'tenant-a',
          'staff-a',
          status: MembershipStatus.inactive,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(successes, 0);
      expect(find.text('Staff member inactive.'), findsNothing);
    });

    testWidgets('target switch discards an outstanding failure', (
      tester,
    ) async {
      final controller = TenantSessionController()
        ..open(uid: 'admin-a', membership: _membership('tenant-a'));
      final pending = Completer<Object?>();
      final callable = _StatusCallable(handler: (_, _) => pending.future);
      await tester.pumpWidget(
        _formApp(
          controller: controller,
          target: _summary('tenant-a', 'staff-a'),
          callable: callable,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('set-staff-status-confirm')));
      await tester.pump();

      await tester.pumpWidget(
        _formApp(
          controller: controller,
          target: _summary('tenant-a', 'staff-b'),
          callable: callable,
        ),
      );
      await tester.pump();
      pending.completeError(StateError('raw stale target failure'));
      await tester.pump();
      await tester.pump();

      expect(callable.payloads.single['uid'], 'staff-a');
      expect(
        find.byKey(const ValueKey('set-staff-status-error')),
        findsNothing,
      );
      expect(find.textContaining('raw stale'), findsNothing);
    });
  });
}

final class _StatusCallable implements SetStaffStatusCallable {
  _StatusCallable({this.handler});

  final Future<Object?> Function(Map<String, Object?>, int)? handler;
  final List<Map<String, Object?>> payloads = [];

  @override
  Future<Object?> call(Map<String, Object?> payload) {
    final copy = Map<String, Object?>.from(payload);
    final callIndex = payloads.length;
    payloads.add(copy);
    return handler?.call(copy, callIndex) ??
        Future<Object?>.value(
          _statusResponse(
            payload['tenantId']! as String,
            payload['uid']! as String,
            status: MembershipStatus.fromWire(payload['status']),
          ),
        );
  }
}

final class _DirectoryReader implements TenantDataReader {
  _DirectoryReader({this.includeStaff = false});

  final bool includeStaff;
  final List<String> documentPaths = [];
  int queryCount = 0;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    documentPaths.add(path);
    if (RegExp(r'^tenants/[^/]+$').hasMatch(path)) {
      return TenantDocumentSnapshot(
        path: path,
        data: const {'ownerUid': 'owner-a'},
      );
    }
    if (RegExp(r'^tenants/[^/]+/staff/owner-a$').hasMatch(path)) {
      return TenantDocumentSnapshot(
        path: path,
        data: _staffData('owner-a', role: TenantRole.owner),
      );
    }
    return null;
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    queryCount++;
    final tenantId = query.collectionPath.split('/')[1];
    return [
      _snapshot(tenantId, 'owner-a', role: TenantRole.owner),
      if (includeStaff)
        _snapshot(tenantId, 'staff-a', role: TenantRole.cashier),
    ];
  }
}

Map<String, Object?> _statusResponse(
  String tenantId,
  String uid, {
  required MembershipStatus status,
  TenantRole role = TenantRole.cashier,
}) => <String, Object?>{
  'tenantId': tenantId,
  'uid': uid,
  'role': role.wireValue,
  'status': status.wireValue,
};

TenantStaffSummary _summary(
  String tenantId,
  String uid, {
  TenantRole role = TenantRole.cashier,
  MembershipStatus status = MembershipStatus.active,
  TenantStaffInvitationStatus invitationStatus =
      TenantStaffInvitationStatus.accepted,
}) => TenantStaffSummary.fromSnapshot(
  _snapshot(
    tenantId,
    uid,
    role: role,
    status: status,
    invitationStatus: invitationStatus,
  ),
  ownerUid: role == TenantRole.owner ? uid : 'owner-a',
);

TenantQueryDocumentSnapshot _snapshot(
  String tenantId,
  String uid, {
  required TenantRole role,
  MembershipStatus status = MembershipStatus.active,
  TenantStaffInvitationStatus invitationStatus =
      TenantStaffInvitationStatus.accepted,
}) => TenantQueryDocumentSnapshot(
  path: 'tenants/$tenantId/staff/$uid',
  data: _staffData(
    uid,
    role: role,
    status: status,
    invitationStatus: invitationStatus,
  ),
);

Map<String, Object?> _staffData(
  String uid, {
  required TenantRole role,
  MembershipStatus status = MembershipStatus.active,
  TenantStaffInvitationStatus invitationStatus =
      TenantStaffInvitationStatus.accepted,
}) => <String, Object?>{
  'uid': uid,
  'email': '$uid@example.test',
  'name': role == TenantRole.owner ? 'Owner A' : 'Staff Person',
  'phone': '+254700000000',
  'role': role.wireValue,
  'status': status.wireValue,
  'invitationStatus': invitationStatus.wireValue,
};

Widget _directoryApp({
  required TenantSessionController controller,
  required TenantDataReader reader,
  required SetStaffStatusCallable callable,
}) => MaterialApp(
  home: TenantSessionScope(
    controller: controller,
    child: Scaffold(
      body: TenantStaffDirectoryPanel(
        reader: reader,
        statusCallable: callable,
        requestIdFactory: () => 'status-widget-request',
      ),
    ),
  ),
);

Widget _formApp({
  required TenantSessionController controller,
  required TenantStaffSummary target,
  required SetStaffStatusCallable callable,
  VoidCallback? onSuccess,
  VoidCallback? onCancel,
}) => MaterialApp(
  home: TenantSessionScope(
    controller: controller,
    child: Scaffold(
      body: TenantStaffStatusForm(
        session: controller.session!,
        target: target,
        callable: callable,
        requestIdFactory: () => 'status-form-request',
        onSuccess: onSuccess ?? () {},
        onCancel: onCancel ?? () {},
      ),
    ),
  ),
);

TenantSession _session(String tenantId, {required TenantRole role}) =>
    TenantSession.active(uid: 'actor-a', tenantId: tenantId, role: role);

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
