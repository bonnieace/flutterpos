import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('staff invitation contract', () {
    test('normalizes fields and rejects invalid input or owner roles', () {
      final draft = TenantStaffInviteDraft(
        email: '  PERSON@Example.Test ',
        name: '  Person   Name  ',
        phone: '  +254 700 000 000 ',
        role: TenantRole.manager,
      );

      expect(draft.email, 'person@example.test');
      expect(draft.name, 'Person Name');
      expect(draft.phone, '+254 700 000 000');
      expect(draft.role, TenantRole.manager);

      expect(
        () => TenantStaffInviteDraft(
          email: 'not-an-email',
          name: 'Person',
          phone: '',
          role: TenantRole.cashier,
        ),
        throwsFormatException,
      );
      expect(
        () => TenantStaffInviteDraft(
          email: 'person@example.test',
          name: 'Person',
          phone: '',
          role: TenantRole.owner,
        ),
        throwsFormatException,
      );
      expect(
        () => TenantStaffInviteDraft(
          email: 'person@example.test',
          name: 'Person\nName',
          phone: '',
          role: TenantRole.admin,
        ),
        throwsFormatException,
      );
    });

    test(
      'derives the tenant payload and retains one request ID per intent',
      () async {
        final callable = _InviteCallable();
        var generatedIds = 0;
        final gateway = TenantStaffInvitationGateway(
          session: _session('tenant-a', role: TenantRole.owner),
          callable: callable,
          requestIdFactory: () => 'invite-request-${++generatedIds}',
        );
        final intent = gateway.createIntent(
          TenantStaffInviteDraft(
            email: ' PERSON@EXAMPLE.TEST ',
            name: ' Person ',
            phone: ' +254700000000 ',
            role: TenantRole.admin,
          ),
        );

        final first = await gateway.submit(intent);
        final second = await gateway.submit(intent);

        expect(generatedIds, 1);
        expect(callable.payloads, hasLength(2));
        expect(callable.payloads[0], {
          'tenantId': 'tenant-a',
          'email': 'person@example.test',
          'name': 'Person',
          'phone': '+254700000000',
          'role': 'admin',
          'requestId': 'invite-request-1',
        });
        expect(callable.payloads[1]['requestId'], 'invite-request-1');
        expect(first.tenantId, 'tenant-a');
        expect(first.uid, 'staff-a');
        expect(second.invitationVersion, 1);
      },
    );

    test('denies manager and cashier sessions without callable requests', () {
      for (final role in [TenantRole.manager, TenantRole.cashier]) {
        final callable = _InviteCallable();
        final gateway = TenantStaffInvitationGateway(
          session: _session('tenant-a', role: role),
          callable: callable,
          requestIdFactory: () => 'invite-request-1',
        );
        expect(
          () => gateway.createIntent(
            TenantStaffInviteDraft(
              email: 'person@example.test',
              name: 'Person',
              phone: '',
              role: TenantRole.cashier,
            ),
          ),
          throwsStateError,
        );
        expect(callable.payloads, isEmpty);
      }
    });

    test('strictly rejects malformed and cross-tenant callable responses', () {
      final valid = _inviteResponse('tenant-a');
      final malformed = <Object?>[
        null,
        {...valid, 'tenantId': 'tenant-b'},
        {...valid, 'unexpected': true},
        {...valid, 'uid': 'bad/uid'},
        {...valid, 'invitationStatus': 'sent'},
        {...valid, 'invitationVersion': 0},
        {
          ...valid,
          'delivery': {'deliveryId': 'delivery-a', 'status': 'sent'},
        },
      ];

      for (final response in malformed) {
        expect(
          () => TenantStaffInviteResult.fromCallable(
            response,
            expectedTenantId: 'tenant-a',
          ),
          throwsFormatException,
        );
      }
    });
  });

  group('guarded staff invitation form', () {
    testWidgets('owner submission refreshes only after a successful response', (
      tester,
    ) async {
      final controller = TenantSessionController()
        ..open(
          uid: 'owner-a',
          membership: _membership('tenant-a', role: TenantRole.owner),
        );
      final callable = _InviteCallable();
      final reader = _DirectoryReader();

      await tester.pumpWidget(
        _directoryApp(
          controller: controller,
          reader: reader,
          callable: callable,
        ),
      );
      await tester.pumpAndSettle();
      expect(reader.queryCount, 1);

      await _tapVisibleThenPump(tester, 'invite-staff-open');
      await tester.enterText(
        find.byKey(const ValueKey('invite-staff-email')),
        ' NEW@EXAMPLE.TEST ',
      );
      await tester.enterText(
        find.byKey(const ValueKey('invite-staff-name')),
        ' New Person ',
      );
      await tester.enterText(
        find.byKey(const ValueKey('invite-staff-phone')),
        ' +254700000001 ',
      );
      await _tapVisible(tester, 'invite-staff-submit');

      expect(callable.payloads, hasLength(1));
      expect(callable.payloads.single['tenantId'], 'tenant-a');
      expect(callable.payloads.single['email'], 'new@example.test');
      expect(callable.payloads.single['role'], 'cashier');
      expect(reader.queryCount, 2);
      expect(find.text('Staff invitation queued.'), findsOneWidget);
    });

    testWidgets('manager is read-only and cashier starts no directory reads', (
      tester,
    ) async {
      final callable = _InviteCallable();
      final managerController = TenantSessionController()
        ..open(
          uid: 'manager-a',
          membership: _membership('tenant-a', role: TenantRole.manager),
        );
      final managerReader = _DirectoryReader();
      await tester.pumpWidget(
        _directoryApp(
          controller: managerController,
          reader: managerReader,
          callable: callable,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Invite staff'), findsNothing);
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
      expect(find.text('You do not have access to this page.'), findsOneWidget);
      expect(cashierReader.documentPaths, isEmpty);
      expect(cashierReader.queryCount, 0);
      expect(callable.payloads, isEmpty);
    });

    testWidgets(
      'duplicate taps are single-flight and retry reuses the intent',
      (tester) async {
        final controller = TenantSessionController()
          ..open(
            uid: 'owner-a',
            membership: _membership('tenant-a', role: TenantRole.owner),
          );
        final first = Completer<Object?>();
        final callable = _InviteCallable(
          handler: (payload, callIndex) => callIndex == 0
              ? first.future
              : Future.value(_inviteResponse('tenant-a')),
        );
        var successes = 0;

        await tester.pumpWidget(
          _formApp(
            controller: controller,
            callable: callable,
            onSuccess: () => successes++,
          ),
        );
        await _fillValidForm(tester);

        final submit = find.byKey(const ValueKey('invite-staff-submit'));
        await tester.tap(submit);
        await tester.tap(submit);
        await tester.pump();
        expect(callable.payloads, hasLength(1));

        first.completeError(StateError('raw backend secret detail'));
        await tester.pump();
        await tester.pump();
        expect(
          find.text('Invitation could not be sent. Please try again.'),
          findsOneWidget,
        );
        expect(find.textContaining('raw backend'), findsNothing);
        expect(successes, 0);

        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(callable.payloads, hasLength(2));
        expect(
          callable.payloads[0]['requestId'],
          callable.payloads[1]['requestId'],
        );
        expect(successes, 1);
      },
    );

    testWidgets('tenant switch discards an outstanding success', (
      tester,
    ) async {
      final controller = TenantSessionController()
        ..open(
          uid: 'owner-a',
          membership: _membership('tenant-a', role: TenantRole.owner),
        );
      final pending = Completer<Object?>();
      final callable = _InviteCallable(handler: (_, _) => pending.future);
      var successes = 0;
      await tester.pumpWidget(
        _formApp(
          controller: controller,
          callable: callable,
          onSuccess: () => successes++,
        ),
      );
      await _fillValidForm(tester);
      await _tapVisibleThenPump(tester, 'invite-staff-submit');

      controller.open(
        uid: 'owner-a',
        membership: _membership('tenant-b', role: TenantRole.owner),
      );
      await tester.pump();
      pending.complete(_inviteResponse('tenant-a'));
      await tester.pump();
      await tester.pump();

      expect(successes, 0);
      expect(find.text('Staff invitation queued.'), findsNothing);
    });

    testWidgets('UID switch discards an outstanding failure', (tester) async {
      final controller = TenantSessionController()
        ..open(
          uid: 'owner-a',
          membership: _membership('tenant-a', role: TenantRole.owner),
        );
      final pending = Completer<Object?>();
      final callable = _InviteCallable(handler: (_, _) => pending.future);
      await tester.pumpWidget(
        _formApp(controller: controller, callable: callable),
      );
      await _fillValidForm(tester);
      await _tapVisibleThenPump(tester, 'invite-staff-submit');

      controller.open(
        uid: 'owner-b',
        membership: _membership('tenant-a', role: TenantRole.owner),
      );
      await tester.pump();
      pending.completeError(StateError('raw stale failure'));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('invite-staff-error')), findsNothing);
      expect(find.textContaining('raw stale'), findsNothing);
    });
  });
}

final class _InviteCallable implements InviteStaffCallable {
  _InviteCallable({this.handler});

  final Future<Object?> Function(Map<String, Object?>, int)? handler;
  final List<Map<String, Object?>> payloads = [];

  @override
  Future<Object?> call(Map<String, Object?> payload) {
    final copy = Map<String, Object?>.from(payload);
    final callIndex = payloads.length;
    payloads.add(copy);
    return handler?.call(copy, callIndex) ??
        Future<Object?>.value(_inviteResponse(payload['tenantId']! as String));
  }
}

final class _DirectoryReader implements TenantDataReader {
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
      final tenantId = path.split('/')[1];
      return TenantDocumentSnapshot(path: path, data: _ownerData(tenantId));
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
      TenantQueryDocumentSnapshot(
        path: 'tenants/$tenantId/staff/owner-a',
        data: _ownerData(tenantId),
      ),
    ];
  }
}

Map<String, Object?> _ownerData(String tenantId) => <String, Object?>{
  'uid': 'owner-a',
  'email': 'owner-a@example.test',
  'name': 'Owner A',
  'phone': '',
  'role': 'owner',
  'status': 'active',
  'invitationStatus': 'accepted',
  'tenantIdForTest': tenantId,
};

Map<String, Object?> _inviteResponse(String tenantId) => <String, Object?>{
  'tenantId': tenantId,
  'uid': 'staff-a',
  'invitationStatus': 'pending',
  'invitationVersion': 1,
  'delivery': <String, Object?>{
    'deliveryId': 'delivery-a',
    'status': 'pending_enqueue',
  },
};

Future<void> _fillValidForm(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('invite-staff-email')),
    'person@example.test',
  );
  await tester.enterText(
    find.byKey(const ValueKey('invite-staff-name')),
    'Person',
  );
  await tester.enterText(
    find.byKey(const ValueKey('invite-staff-phone')),
    '+254700000000',
  );
}

Widget _directoryApp({
  required TenantSessionController controller,
  required TenantDataReader reader,
  required InviteStaffCallable callable,
}) => MaterialApp(
  home: TenantSessionScope(
    controller: controller,
    child: Scaffold(
      body: TenantStaffDirectoryPanel(
        reader: reader,
        inviteCallable: callable,
        requestIdFactory: () => 'invite-widget-request',
      ),
    ),
  ),
);

Widget _formApp({
  required TenantSessionController controller,
  required InviteStaffCallable callable,
  VoidCallback? onSuccess,
}) => MaterialApp(
  home: TenantSessionScope(
    controller: controller,
    child: Scaffold(
      body: TenantStaffInvitationForm(
        session: controller.session!,
        callable: callable,
        requestIdFactory: () => 'invite-form-request',
        onSuccess: onSuccess ?? () {},
      ),
    ),
  ),
);

TenantSession _session(String tenantId, {required TenantRole role}) =>
    TenantSession.active(uid: 'actor-a', tenantId: tenantId, role: role);

TenantMembership _membership(String tenantId, {required TenantRole role}) =>
    TenantMembership(
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

/// Scrolls [key] into view, then taps it with a single pump.
///
/// The directory now carries a strip of headline figures above the list, so a
/// form can sit below the fold of a short viewport - which is where a real user
/// scrolls to it. The scroll settles *before* the tap and the tap itself only
/// pumps once, because the tests that use this deliberately inspect the frame
/// while the resulting call is still outstanding; settling after the tap would
/// wait for the very thing they are asserting is not finished.
Future<void> _tapVisibleThenPump(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

/// Scrolls [key] into view, taps it, and settles.
Future<void> _tapVisible(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
