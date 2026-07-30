import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('staff invitation email replacement contract', () {
    test('normalizes email and rejects unchanged or invalid emails', () {
      final draft = TenantStaffInvitationEmailReplacementDraft.normalized(
        oldTargetUid: 'staff-a',
        email: '  NEW@Example.Test  ',
        existingEmail: 'old@example.test',
      );

      expect(draft.oldTargetUid, 'staff-a');
      expect(draft.email, 'new@example.test');

      for (final email in [
        'not-an-email',
        'old@example.test',
        '  OLD@EXAMPLE.TEST  ',
      ]) {
        expect(
          () => TenantStaffInvitationEmailReplacementDraft.normalized(
            oldTargetUid: 'staff-a',
            email: email,
            existingEmail: 'old@example.test',
          ),
          throwsFormatException,
        );
      }
    });

    test(
      'binds tenant, old target, and corrected email to a stable intent',
      () async {
        final callable = _ReplacementCallable();
        var generatedIds = 0;
        final gateway = TenantStaffInvitationEmailReplacementGateway(
          session: _session('tenant-a', role: TenantRole.owner),
          target: _pendingSummary('tenant-a', 'staff-a'),
          callable: callable,
          requestIdFactory: () => 'replace-request-${++generatedIds}',
        );
        final intent = gateway.createIntent(email: ' NEW@EXAMPLE.TEST ');

        final first = await gateway.submit(intent);
        final second = await gateway.submit(intent);

        expect(generatedIds, 1);
        expect(callable.payloads, hasLength(2));
        expect(callable.payloads.first, {
          'tenantId': 'tenant-a',
          'uid': 'staff-a',
          'email': 'new@example.test',
          'requestId': 'replace-request-1',
        });
        expect(callable.payloads.last['requestId'], 'replace-request-1');
        expect(first.uid, 'replacement-staff-a');
        expect(first.invitationVersion, 4);
        expect(second.deliveryId, 'delivery-staff-a');
      },
    );

    test('accepts pending and sent non-owner invitations only', () async {
      for (final invitationStatus in [
        TenantStaffInvitationStatus.pending,
        TenantStaffInvitationStatus.sent,
      ]) {
        final callable = _ReplacementCallable();
        final gateway = TenantStaffInvitationEmailReplacementGateway(
          session: _session('tenant-a', role: TenantRole.admin),
          target: _pendingSummary(
            'tenant-a',
            'staff-a',
            invitationStatus: invitationStatus,
          ),
          callable: callable,
          requestIdFactory: () => 'replace-request-1',
        );

        await gateway.submit(gateway.createIntent(email: 'new@example.test'));

        expect(callable.payloads, hasLength(1));
      }
    });

    test(
      'rejects owners, accepted memberships, and unchanged email without calls',
      () {
        final session = _session('tenant-a', role: TenantRole.admin);
        for (final target in [
          _acceptedSummary('tenant-a', 'owner-a', role: TenantRole.owner),
          _acceptedSummary('tenant-a', 'active-a'),
          _acceptedSummary(
            'tenant-a',
            'inactive-a',
            status: MembershipStatus.inactive,
          ),
          _pendingSummary('tenant-a', 'staff-a'),
        ]) {
          final callable = _ReplacementCallable();
          final gateway = TenantStaffInvitationEmailReplacementGateway(
            session: session,
            target: target,
            callable: callable,
            requestIdFactory: () => 'replace-request-1',
          );

          expect(
            () => gateway.createIntent(email: target.email),
            throwsFormatException,
          );
          expect(callable.payloads, isEmpty);
        }
      },
    );

    test('denies manager and cashier sessions without calls', () {
      for (final role in [TenantRole.manager, TenantRole.cashier]) {
        final callable = _ReplacementCallable();
        final gateway = TenantStaffInvitationEmailReplacementGateway(
          session: _session('tenant-a', role: role),
          target: _pendingSummary('tenant-a', 'staff-a'),
          callable: callable,
          requestIdFactory: () => 'replace-request-1',
        );

        expect(
          () => gateway.createIntent(email: 'new@example.test'),
          throwsStateError,
        );
        expect(callable.payloads, isEmpty);
      }
    });

    test('strictly rejects malformed responses and old UID reuse', () {
      final valid = _replacementResponse('tenant-a', 'staff-a');
      final malformed = <Object?>[
        null,
        {...valid, 'tenantId': 'tenant-b'},
        {...valid, 'uid': 'staff-a'},
        {...valid, 'uid': 'bad/uid'},
        {...valid, 'invitationStatus': 'sent'},
        {...valid, 'invitationVersion': 0},
        {...valid, 'invitationVersion': 4.0},
        {...valid, 'invitationVersion': 9007199254740992},
        {...valid, 'delivery': null},
        {
          ...valid,
          'delivery': {'deliveryId': 'delivery-staff-a', 'status': 'queued'},
        },
        {
          ...valid,
          'delivery': {'deliveryId': 'bad/id', 'status': 'pending_enqueue'},
        },
        {...valid, 'unexpected': true},
      ];

      for (final response in malformed) {
        expect(
          () => TenantStaffInvitationEmailReplacementResult.fromCallable(
            response,
            expectedTenantId: 'tenant-a',
            oldUid: 'staff-a',
          ),
          throwsFormatException,
        );
      }
    });
  });

  group('guarded invitation email replacement form', () {
    testWidgets('owner confirms replacement and refreshes the first page', (
      tester,
    ) async {
      final controller = TenantSessionController()
        ..open(
          uid: 'owner-a',
          membership: _membership('tenant-a', role: TenantRole.owner),
        );
      final callable = _ReplacementCallable();
      final reader = _DirectoryReader(includePendingStaff: true);

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
        find.byKey(const ValueKey('replace-staff-email-owner-a')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('replace-staff-email-staff-a')),
      );
      await tester.pump();
      expect(
        find.text('Replace invitation email for Staff Person?'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('replace-staff-email-input')),
        ' corrected@example.test ',
      );
      await tester.tap(
        find.byKey(const ValueKey('replace-staff-email-confirm')),
      );
      await tester.pumpAndSettle();

      expect(callable.payloads.single, {
        'tenantId': 'tenant-a',
        'uid': 'staff-a',
        'email': 'corrected@example.test',
        'requestId': 'replace-widget-request',
      });
      expect(reader.queryCount, 2);
      expect(find.text('Invitation email replacement queued.'), findsOneWidget);
    });

    testWidgets('manager is read-only and cashier starts no calls or reads', (
      tester,
    ) async {
      final callable = _ReplacementCallable();
      final managerController = TenantSessionController()
        ..open(
          uid: 'manager-a',
          membership: _membership('tenant-a', role: TenantRole.manager),
        );
      final managerReader = _DirectoryReader(includePendingStaff: true);
      await tester.pumpWidget(
        _directoryApp(
          controller: managerController,
          reader: managerReader,
          callable: callable,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.alternate_email_outlined), findsNothing);
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

    testWidgets('invalid email and dismissed confirmation make no calls', (
      tester,
    ) async {
      final controller = TenantSessionController()
        ..open(uid: 'admin-a', membership: _membership('tenant-a'));
      final callable = _ReplacementCallable();
      var dismissals = 0;
      await tester.pumpWidget(
        _formApp(
          controller: controller,
          target: _pendingSummary('tenant-a', 'staff-a'),
          callable: callable,
          onCancel: () => dismissals++,
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('replace-staff-email-input')),
        'staff-a@example.test',
      );
      await tester.tap(
        find.byKey(const ValueKey('replace-staff-email-confirm')),
      );
      await tester.pump();
      expect(
        find.text('Enter a different valid email address.'),
        findsOneWidget,
      );
      expect(callable.payloads, isEmpty);

      await tester.tap(
        find.byKey(const ValueKey('replace-staff-email-cancel')),
      );
      await tester.pump();
      expect(dismissals, 1);
      expect(callable.payloads, isEmpty);
    });

    testWidgets('duplicate taps are single-flight and retry reuses intent', (
      tester,
    ) async {
      final controller = TenantSessionController()
        ..open(uid: 'admin-a', membership: _membership('tenant-a'));
      final first = Completer<Object?>();
      final callable = _ReplacementCallable(
        handler: (payload, callIndex) => callIndex == 0
            ? first.future
            : Future.value(
                _replacementResponse(
                  payload['tenantId']! as String,
                  payload['uid']! as String,
                ),
              ),
      );
      var successes = 0;
      await tester.pumpWidget(
        _formApp(
          controller: controller,
          target: _pendingSummary('tenant-a', 'staff-a'),
          callable: callable,
          onSuccess: () => successes++,
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('replace-staff-email-input')),
        'new@example.test',
      );

      final submit = find.byKey(const ValueKey('replace-staff-email-confirm'));
      await tester.tap(submit);
      await tester.tap(submit);
      await tester.pump();
      expect(callable.payloads, hasLength(1));

      first.completeError(StateError('raw backend secret detail'));
      await tester.pump();
      await tester.pump();
      expect(
        find.text('Invitation email could not be replaced. Please try again.'),
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
      final callable = _ReplacementCallable(handler: (_, _) => pending.future);
      var successes = 0;
      await tester.pumpWidget(
        _formApp(
          controller: controller,
          target: _pendingSummary('tenant-a', 'staff-a'),
          callable: callable,
          onSuccess: () => successes++,
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('replace-staff-email-input')),
        'new@example.test',
      );
      await tester.tap(
        find.byKey(const ValueKey('replace-staff-email-confirm')),
      );
      await tester.pump();

      controller.open(uid: 'admin-a', membership: _membership('tenant-b'));
      await tester.pump();
      pending.complete(_replacementResponse('tenant-a', 'staff-a'));
      await tester.pump();
      await tester.pump();

      expect(successes, 0);
      expect(find.text('Invitation email replacement queued.'), findsNothing);
    });

    testWidgets('target switch discards an outstanding failure', (
      tester,
    ) async {
      final controller = TenantSessionController()
        ..open(uid: 'admin-a', membership: _membership('tenant-a'));
      final pending = Completer<Object?>();
      final callable = _ReplacementCallable(handler: (_, _) => pending.future);
      await tester.pumpWidget(
        _formApp(
          controller: controller,
          target: _pendingSummary('tenant-a', 'staff-a'),
          callable: callable,
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('replace-staff-email-input')),
        'new@example.test',
      );
      await tester.tap(
        find.byKey(const ValueKey('replace-staff-email-confirm')),
      );
      await tester.pump();

      await tester.pumpWidget(
        _formApp(
          controller: controller,
          target: _pendingSummary('tenant-a', 'staff-b'),
          callable: callable,
        ),
      );
      await tester.pump();
      pending.completeError(StateError('raw stale target failure'));
      await tester.pump();
      await tester.pump();

      expect(callable.payloads.single['uid'], 'staff-a');
      expect(
        find.byKey(const ValueKey('replace-staff-email-error')),
        findsNothing,
      );
      expect(find.textContaining('raw stale'), findsNothing);
    });
  });
}

final class _ReplacementCallable implements ReplacePendingStaffEmailCallable {
  _ReplacementCallable({this.handler});

  final Future<Object?> Function(Map<String, Object?>, int)? handler;
  final List<Map<String, Object?>> payloads = [];

  @override
  Future<Object?> call(Map<String, Object?> payload) {
    final copy = Map<String, Object?>.from(payload);
    final callIndex = payloads.length;
    payloads.add(copy);
    return handler?.call(copy, callIndex) ??
        Future<Object?>.value(
          _replacementResponse(
            payload['tenantId']! as String,
            payload['uid']! as String,
          ),
        );
  }
}

final class _DirectoryReader implements TenantDataReader {
  _DirectoryReader({this.includePendingStaff = false});

  final bool includePendingStaff;
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
      if (includePendingStaff)
        _snapshot(
          tenantId,
          'staff-a',
          role: TenantRole.cashier,
          status: MembershipStatus.pending,
          invitationStatus: TenantStaffInvitationStatus.sent,
        ),
    ];
  }
}

Map<String, Object?> _replacementResponse(
  String tenantId,
  String oldUid,
) => <String, Object?>{
  'tenantId': tenantId,
  'uid': 'replacement-$oldUid',
  'invitationStatus': 'pending',
  'invitationVersion': 4,
  'delivery': {'deliveryId': 'delivery-$oldUid', 'status': 'pending_enqueue'},
};

TenantStaffSummary _pendingSummary(
  String tenantId,
  String uid, {
  TenantStaffInvitationStatus invitationStatus =
      TenantStaffInvitationStatus.sent,
}) => TenantStaffSummary.fromSnapshot(
  _snapshot(
    tenantId,
    uid,
    role: TenantRole.cashier,
    status: MembershipStatus.pending,
    invitationStatus: invitationStatus,
  ),
  ownerUid: 'owner-a',
);

TenantStaffSummary _acceptedSummary(
  String tenantId,
  String uid, {
  TenantRole role = TenantRole.cashier,
  MembershipStatus status = MembershipStatus.active,
}) => TenantStaffSummary.fromSnapshot(
  _snapshot(tenantId, uid, role: role, status: status),
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
  required ReplacePendingStaffEmailCallable callable,
}) => MaterialApp(
  home: TenantSessionScope(
    controller: controller,
    child: Scaffold(
      body: TenantStaffDirectoryPanel(
        reader: reader,
        replaceEmailCallable: callable,
        requestIdFactory: () => 'replace-widget-request',
      ),
    ),
  ),
);

Widget _formApp({
  required TenantSessionController controller,
  required TenantStaffSummary target,
  required ReplacePendingStaffEmailCallable callable,
  VoidCallback? onSuccess,
  VoidCallback? onCancel,
}) => MaterialApp(
  home: TenantSessionScope(
    controller: controller,
    child: Scaffold(
      body: TenantStaffInvitationEmailReplacementForm(
        session: controller.session!,
        target: target,
        callable: callable,
        requestIdFactory: () => 'replace-form-request',
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
