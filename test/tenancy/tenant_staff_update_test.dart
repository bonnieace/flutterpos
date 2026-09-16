import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/buttons.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('staff update contract', () {
    test('binds tenant and target while preserving owner role', () async {
      final callable = _UpdateCallable();
      var generatedIds = 0;
      final gateway = TenantStaffUpdateGateway(
        session: _session('tenant-a', role: TenantRole.owner),
        target: _summary('tenant-a', 'owner-a', role: TenantRole.owner),
        callable: callable,
        requestIdFactory: () => 'update-request-${++generatedIds}',
      );
      final intent = gateway.createIntent(
        name: '  Owner   Person  ',
        phone: ' +254 700 000 001 ',
        role: TenantRole.owner,
      );

      final first = await gateway.submit(intent);
      final second = await gateway.submit(intent);

      expect(generatedIds, 1);
      expect(callable.payloads, hasLength(2));
      expect(callable.payloads.first, {
        'tenantId': 'tenant-a',
        'uid': 'owner-a',
        'name': 'Owner Person',
        'phone': '+254 700 000 001',
        'role': 'owner',
        'requestId': 'update-request-1',
      });
      expect(callable.payloads.last['requestId'], 'update-request-1');
      expect(first.uid, 'owner-a');
      expect(first.role, TenantRole.owner);
      expect(second.status, MembershipStatus.active);
    });

    test('allows non-owner role changes and rejects owner reassignment', () {
      final callable = _UpdateCallable();
      final gateway = TenantStaffUpdateGateway(
        session: _session('tenant-a', role: TenantRole.admin),
        target: _summary('tenant-a', 'staff-a'),
        callable: callable,
        requestIdFactory: () => 'update-request-1',
      );

      expect(
        gateway
            .createIntent(
              name: 'Staff Person',
              phone: '',
              role: TenantRole.manager,
            )
            .draft
            .role,
        TenantRole.manager,
      );
      expect(
        () => gateway.createIntent(
          name: 'Staff Person',
          phone: '',
          role: TenantRole.owner,
        ),
        throwsFormatException,
      );
      expect(
        () => gateway.createIntent(
          name: 'Staff\nPerson',
          phone: '',
          role: TenantRole.cashier,
        ),
        throwsFormatException,
      );
    });

    test('denies manager and cashier sessions without callable requests', () {
      for (final role in [TenantRole.manager, TenantRole.cashier]) {
        final callable = _UpdateCallable();
        final gateway = TenantStaffUpdateGateway(
          session: _session('tenant-a', role: role),
          target: _summary('tenant-a', 'staff-a'),
          callable: callable,
          requestIdFactory: () => 'update-request-1',
        );
        expect(
          () => gateway.createIntent(
            name: 'Staff Person',
            phone: '',
            role: TenantRole.cashier,
          ),
          throwsStateError,
        );
        expect(callable.payloads, isEmpty);
      }
    });

    test('strictly rejects malformed and mismatched callable responses', () {
      final valid = _updateResponse(
        'tenant-a',
        'staff-a',
        role: TenantRole.manager,
      );
      final malformed = <Object?>[
        null,
        {...valid, 'tenantId': 'tenant-b'},
        {...valid, 'uid': 'staff-b'},
        {...valid, 'role': 'cashier'},
        {...valid, 'unexpected': true},
        {...valid, 'uid': 'bad/uid'},
      ];

      for (final response in malformed) {
        expect(
          () => TenantStaffUpdateResult.fromCallable(
            response,
            expectedTenantId: 'tenant-a',
            expectedUid: 'staff-a',
            expectedRole: TenantRole.manager,
          ),
          throwsFormatException,
        );
      }
    });

    test('accepts a status this mutation did not set and did not expect', () {
      // **The committed write that reported itself as a failure.** An
      // administrator opens Correct against an active member; a colleague
      // deactivates that member; the correction commits and the server returns
      // the fresh `inactive`. Requiring it to match the row the form opened
      // with turned that into *Staff details could not be updated*, and the
      // retry replayed the same request id into the same idempotency record for
      // the same fresh status - so it could never succeed.
      final result = TenantStaffUpdateResult.fromCallable(
        {
          ..._updateResponse('tenant-a', 'staff-a', role: TenantRole.manager),
          'status': 'inactive',
        },
        expectedTenantId: 'tenant-a',
        expectedUid: 'staff-a',
        expectedRole: TenantRole.manager,
      );

      expect(result.status, MembershipStatus.inactive);
      expect(result.role, TenantRole.manager);
    });
  });

  group('guarded staff update form', () {
    testWidgets('owner profile edit preserves owner and refreshes on success', (
      tester,
    ) async {
      final controller = TenantSessionController()
        ..open(
          uid: 'owner-a',
          membership: _membership('tenant-a', role: TenantRole.owner),
        );
      final callable = _UpdateCallable();
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

      await _chooseDirectoryAction(
        tester,
        targetUid: 'owner-a',
        actionKey: 'edit-staff-owner-a',
      );
      expect(find.text('Owner'), findsWidgets);
      await tester.enterText(
        find.byKey(const ValueKey('update-staff-name')),
        ' Updated Owner ',
      );
      await _tapVisible(tester, 'update-staff-submit');

      expect(callable.payloads.single['tenantId'], 'tenant-a');
      expect(callable.payloads.single['uid'], 'owner-a');
      expect(callable.payloads.single['name'], 'Updated Owner');
      expect(callable.payloads.single['role'], 'owner');
      expect(reader.queryCount, 2);
      expect(find.text('Staff details updated.'), findsOneWidget);
    });

    testWidgets('admin can change a non-owner role', (tester) async {
      final controller = TenantSessionController()
        ..open(uid: 'admin-a', membership: _membership('tenant-a'));
      final callable = _UpdateCallable();
      final reader = _DirectoryReader(includeStaff: true);
      await tester.pumpWidget(
        _directoryApp(
          controller: controller,
          reader: reader,
          callable: callable,
        ),
      );
      await tester.pumpAndSettle();

      await _chooseDirectoryAction(
        tester,
        targetUid: 'staff-a',
        actionKey: 'edit-staff-staff-a',
      );
      await _tapVisible(tester, 'update-staff-role');
      await tester.tap(find.text('Manager').last);
      await tester.pumpAndSettle();
      await _tapVisible(tester, 'update-staff-submit');

      expect(callable.payloads.single['uid'], 'staff-a');
      expect(callable.payloads.single['role'], 'manager');
    });

    testWidgets('the form fits the narrowest record it is opened inside', (
      tester,
    ) async {
      // The defect this found, which predates `RecordList` and was reachable
      // without it: the form's Cancel / Save pair was a `Row` at
      // `MainAxisAlignment.end`, and a `Row` answers a column narrower than its
      // children by overflowing. §4.1's `compact` band is 411 and §4.3's
      // `medium` gives a record half a page, so both are narrower than the
      // ~760 this form has only ever been driven at. Nothing had opened it on a
      // phone.
      tester.view.physicalSize = const Size(411, 891);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = TenantSessionController()
        ..open(uid: 'admin-a', membership: _membership('tenant-a'));
      final reader = _DirectoryReader(includeStaff: true);
      await tester.pumpWidget(
        _directoryApp(
          controller: controller,
          reader: reader,
          callable: _UpdateCallable(),
        ),
      );
      await tester.pumpAndSettle();

      // An active accepted member carries two actions - edit and deactivate -
      // so both are inline at every band and no menu is involved. It is the
      // *card* that is narrow here, not the action set.
      await _chooseDirectoryAction(
        tester,
        targetUid: 'staff-a',
        actionKey: 'edit-staff-staff-a',
      );

      expect(find.byKey(const ValueKey('update-staff-submit')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('manager is read-only and cashier starts no calls or reads', (
      tester,
    ) async {
      final callable = _UpdateCallable();
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
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
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

    testWidgets('duplicate taps are single-flight and retry reuses intent', (
      tester,
    ) async {
      final controller = TenantSessionController()
        ..open(
          uid: 'owner-a',
          membership: _membership('tenant-a', role: TenantRole.owner),
        );
      final first = Completer<Object?>();
      final callable = _UpdateCallable(
        handler: (payload, callIndex) => callIndex == 0
            ? first.future
            : Future.value(
                _updateResponse(
                  payload['tenantId']! as String,
                  payload['uid']! as String,
                  role: TenantRole.owner,
                ),
              ),
      );
      var successes = 0;
      await tester.pumpWidget(
        _formApp(
          controller: controller,
          target: _summary('tenant-a', 'owner-a', role: TenantRole.owner),
          callable: callable,
          onSuccess: () => successes++,
        ),
      );

      final submit = find.byKey(const ValueKey('update-staff-submit'));
      await tester.tap(submit);
      await tester.tap(submit);
      await tester.pump();
      expect(callable.payloads, hasLength(1));

      first.completeError(StateError('raw backend secret detail'));
      await tester.pump();
      await tester.pump();
      expect(
        find.text('Staff details could not be updated. Please try again.'),
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

    testWidgets('a discarded result releases the button it was spinning', (
      tester,
    ) async {
      // **N3.** These guards exist to stop a stale answer being applied after
      // the session moved under it, and they returned without clearing
      // `_submitting` - so the form kept spinning over a submission that was
      // never coming back. Latent while a session only changed on a switch that
      // tore the route down; reachable the moment a live session can refresh.
      final controller = TenantSessionController()
        ..open(uid: 'admin-a', membership: _membership('tenant-a'));
      final pending = Completer<Object?>();
      final callable = _UpdateCallable(handler: (_, _) => pending.future);

      await tester.pumpWidget(
        _formApp(
          controller: controller,
          target: _summary('tenant-a', 'staff-a'),
          callable: callable,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('update-staff-submit')));
      await tester.pump();
      await tester.pump();
      expect(
        tester
            .widget<AppButton>(
              find.byKey(const ValueKey('update-staff-submit')),
            )
            .loading,
        isTrue,
      );

      // The session moves under the form while its answer is outstanding.
      controller.open(
        uid: 'admin-a',
        membership: _membership('tenant-b', role: TenantRole.owner),
      );
      await tester.pump();
      pending.completeError(StateError('discarded'));
      await tester.pump();
      await tester.pump();

      expect(
        tester
            .widget<AppButton>(
              find.byKey(const ValueKey('update-staff-submit')),
            )
            .loading,
        isFalse,
        reason: 'a result this form may no longer apply must still free it',
      );
    });

    testWidgets('a refused edit asks for the session to be re-read', (
      tester,
    ) async {
      // **M1's own scenario, from the other end.** The session still believes
      // this actor is an administrator; the server re-read their canonical
      // membership and disagrees. Nothing pushes that decision to this device -
      // `listMyTenants` is a callable, and a deactivated member loses the right
      // to read the record saying they were deactivated - so the refusal itself
      // is the notification, and acting on it is what turns *press it again and
      // be refused again* into a screen that corrects itself.
      final controller = TenantSessionController()
        ..open(uid: 'admin-a', membership: _membership('tenant-a'));
      var revalidations = 0;
      controller.onRevalidationRequested = () => revalidations++;
      final callable = _UpdateCallable(
        handler: (_, _) => Future<Object?>.error(
          FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'not an administrator',
          ),
        ),
      );

      await tester.pumpWidget(
        _formApp(
          controller: controller,
          target: _summary('tenant-a', 'staff-a'),
          callable: callable,
        ),
      );
      await _tapVisible(tester, 'update-staff-submit');

      expect(revalidations, 1);
      expect(
        find.text('Staff details could not be updated. Please try again.'),
        findsOneWidget,
      );
    });

    testWidgets('a refusal about the target does not ask for a re-read', (
      tester,
    ) async {
      // `failed-precondition` is the server disagreeing about the *member*, not
      // about the actor - a colleague got there first. Asking for a session
      // re-read on that would have every raced record trigger one, and it would
      // say nothing about what this session may do.
      final controller = TenantSessionController()
        ..open(uid: 'admin-a', membership: _membership('tenant-a'));
      var revalidations = 0;
      controller.onRevalidationRequested = () => revalidations++;
      final callable = _UpdateCallable(
        handler: (_, _) => Future<Object?>.error(
          FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'the target is not active',
          ),
        ),
      );

      await tester.pumpWidget(
        _formApp(
          controller: controller,
          target: _summary('tenant-a', 'staff-a'),
          callable: callable,
        ),
      );
      await _tapVisible(tester, 'update-staff-submit');

      expect(revalidations, 0);
    });

    testWidgets('tenant switch discards an outstanding success', (
      tester,
    ) async {
      final controller = TenantSessionController()
        ..open(
          uid: 'owner-a',
          membership: _membership('tenant-a', role: TenantRole.owner),
        );
      final pending = Completer<Object?>();
      final callable = _UpdateCallable(handler: (_, _) => pending.future);
      var successes = 0;
      await tester.pumpWidget(
        _formApp(
          controller: controller,
          target: _summary('tenant-a', 'owner-a', role: TenantRole.owner),
          callable: callable,
          onSuccess: () => successes++,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('update-staff-submit')));
      await tester.pump();

      controller.open(
        uid: 'owner-a',
        membership: _membership('tenant-b', role: TenantRole.owner),
      );
      await tester.pump();
      pending.complete(
        _updateResponse('tenant-a', 'owner-a', role: TenantRole.owner),
      );
      await tester.pump();
      await tester.pump();

      expect(successes, 0);
      expect(find.text('Staff details updated.'), findsNothing);
    });

    testWidgets('target UID switch discards an outstanding failure', (
      tester,
    ) async {
      final controller = TenantSessionController()
        ..open(uid: 'admin-a', membership: _membership('tenant-a'));
      final pending = Completer<Object?>();
      final callable = _UpdateCallable(handler: (_, _) => pending.future);
      await tester.pumpWidget(
        _formApp(
          controller: controller,
          target: _summary('tenant-a', 'staff-a'),
          callable: callable,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('update-staff-submit')));
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
      expect(find.byKey(const ValueKey('update-staff-error')), findsNothing);
      expect(find.textContaining('raw stale'), findsNothing);
    });
  });
}

final class _UpdateCallable implements UpdateStaffUserCallable {
  _UpdateCallable({this.handler});

  final Future<Object?> Function(Map<String, Object?>, int)? handler;
  final List<Map<String, Object?>> payloads = [];

  @override
  Future<Object?> call(Map<String, Object?> payload) {
    final copy = Map<String, Object?>.from(payload);
    final callIndex = payloads.length;
    payloads.add(copy);
    final role = TenantRole.fromWire(payload['role']);
    return handler?.call(copy, callIndex) ??
        Future<Object?>.value(
          _updateResponse(
            payload['tenantId']! as String,
            payload['uid']! as String,
            role: role,
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

Map<String, Object?> _updateResponse(
  String tenantId,
  String uid, {
  required TenantRole role,
  MembershipStatus status = MembershipStatus.active,
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
}) => TenantStaffSummary.fromSnapshot(
  _snapshot(tenantId, uid, role: role),
  ownerUid: role == TenantRole.owner ? uid : 'owner-a',
);

TenantQueryDocumentSnapshot _snapshot(
  String tenantId,
  String uid, {
  required TenantRole role,
}) => TenantQueryDocumentSnapshot(
  path: 'tenants/$tenantId/staff/$uid',
  data: _staffData(uid, role: role),
);

Map<String, Object?> _staffData(String uid, {required TenantRole role}) =>
    <String, Object?>{
      'uid': uid,
      'email': '$uid@example.test',
      'name': role == TenantRole.owner ? 'Owner A' : 'Staff Person',
      'phone': '+254700000000',
      'role': role.wireValue,
      'status': MembershipStatus.active.wireValue,
      'invitationStatus': TenantStaffInvitationStatus.accepted.wireValue,
    };

Widget _directoryApp({
  required TenantSessionController controller,
  required TenantDataReader reader,
  required UpdateStaffUserCallable callable,
}) => MaterialApp(
  home: TenantSessionScope(
    controller: controller,
    child: Scaffold(
      body: TenantStaffDirectoryPanel(
        reader: reader,
        updateCallable: callable,
        requestIdFactory: () => 'update-widget-request',
      ),
    ),
  ),
);

Widget _formApp({
  required TenantSessionController controller,
  required TenantStaffSummary target,
  required UpdateStaffUserCallable callable,
  VoidCallback? onSuccess,
}) => MaterialApp(
  home: TenantSessionScope(
    controller: controller,
    child: Scaffold(
      body: TenantStaffUpdateForm(
        session: controller.session!,
        target: target,
        callable: callable,
        requestIdFactory: () => 'update-form-request',
        onSuccess: onSuccess ?? () {},
        onCancel: () {},
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

/// Taps [key] after scrolling it into view.
///
/// The directory now carries a strip of headline figures above the list, so a
/// form opened from a row can sit below the fold of a short viewport - which is
/// exactly where a real user scrolls to it. `ensureVisible` on an already
/// visible control is a no-op, so this is safe everywhere.
Future<void> _tapVisible(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _chooseDirectoryAction(
  WidgetTester tester, {
  required String targetUid,
  required String actionKey,
}) async {
  await _tapVisible(tester, 'staff-actions-$targetUid');
  await tester.tap(find.byKey(ValueKey(actionKey)));
  await tester.pumpAndSettle();
}
