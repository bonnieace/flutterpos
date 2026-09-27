import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('visible tenant invitation acceptance contract', () {
    test('binds tenant and verified caller to a stable intent', () async {
      final callable = _AcceptCallable();
      var generatedIds = 0;
      final gateway = TenantVisibleInvitationAcceptanceGateway(
        identity: _identity(),
        membership: _pendingMembership('tenant-a'),
        callable: callable,
        requestIdFactory: () => 'accept-request-${++generatedIds}',
      );
      final intent = gateway.createIntent();

      final first = await gateway.submit(intent);
      final second = await gateway.submit(intent);

      expect(generatedIds, 1);
      expect(callable.payloads, hasLength(2));
      expect(callable.payloads.first, {
        'tenantId': 'tenant-a',
        'requestId': 'accept-request-1',
      });
      expect(callable.payloads.last['requestId'], 'accept-request-1');
      expect(first.uid, 'user-a');
      expect(first.membershipStatus, MembershipStatus.active);
      expect(second.invitationStatus, TenantStaffInvitationStatus.accepted);
    });

    test('accepts pending and sent visible memberships only', () async {
      for (final invitationStatus in ['pending', 'sent']) {
        final callable = _AcceptCallable();
        final gateway = TenantVisibleInvitationAcceptanceGateway(
          identity: _identity(),
          membership: _pendingMembership(
            'tenant-a',
            invitationStatus: invitationStatus,
          ),
          callable: callable,
          requestIdFactory: () => 'accept-request-1',
        );

        await gateway.submit(gateway.createIntent());

        expect(callable.payloads, hasLength(1));
      }
    });

    test('rejects ineligible users and memberships without calls', () {
      final ineligible = [
        (_identity(emailVerified: false), _pendingMembership('tenant-a')),
        (_identity(globallyActive: false), _pendingMembership('tenant-a')),
        (
          _identity(),
          _membership('tenant-a', membershipStatus: MembershipStatus.active),
        ),
        (
          _identity(),
          _pendingMembership('tenant-a', invitationStatus: 'accepted'),
        ),
        (
          _identity(),
          _pendingMembership('tenant-a', tenantStatus: TenantStatus.suspended),
        ),
        (
          _identity(),
          _pendingMembership('tenant-a', role: TenantRole.owner, isOwner: true),
        ),
      ];

      for (final (identity, membership) in ineligible) {
        final callable = _AcceptCallable();
        final gateway = TenantVisibleInvitationAcceptanceGateway(
          identity: identity,
          membership: membership,
          callable: callable,
          requestIdFactory: () => 'accept-request-1',
        );

        expect(gateway.createIntent, throwsFormatException);
        expect(callable.payloads, isEmpty);
      }
    });

    test('strictly rejects malformed and mismatched responses', () {
      final valid = _acceptedResponse('tenant-a', 'user-a');
      final malformed = <Object?>[
        null,
        {...valid, 'tenantId': 'tenant-b'},
        {...valid, 'uid': 'user-b'},
        {...valid, 'uid': 'bad/uid'},
        {...valid, 'role': 'manager'},
        {...valid, 'membershipStatus': 'pending'},
        {...valid, 'invitationStatus': 'sent'},
        {...valid, 'unexpected': true},
      ];

      for (final response in malformed) {
        expect(
          () => TenantVisibleInvitationAcceptanceResult.fromCallable(
            response,
            expectedTenantId: 'tenant-a',
            expectedUid: 'user-a',
            expectedRole: TenantRole.cashier,
          ),
          throwsFormatException,
        );
      }
    });
  });

  group('visible tenant invitation acceptance UI', () {
    testWidgets('verified user confirms acceptance and refreshes memberships', (
      tester,
    ) async {
      final callable = _AcceptCallable();
      var accepted = 0;
      await tester.pumpWidget(
        _selectorApp(
          identity: _identity(),
          memberships: [_pendingMembership('tenant-a')],
          callable: callable,
          onAccepted: () => accepted++,
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('accept-visible-invitation-tenant-a')),
      );
      await tester.pump();
      expect(
        find.text('Accept invitation to Business tenant-a?'),
        findsOneWidget,
      );
      expect(find.text('Invited role: Cashier'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('accept-visible-invitation-confirm')),
      );
      await tester.pumpAndSettle();

      expect(callable.payloads.single, {
        'tenantId': 'tenant-a',
        'requestId': 'accept-widget-request',
      });
      expect(accepted, 1);
      expect(
        find.text('Invitation accepted for Business tenant-a.'),
        findsOneWidget,
      );
    });

    testWidgets('unverified user sees no acceptance action', (tester) async {
      final callable = _AcceptCallable();
      await tester.pumpWidget(
        _selectorApp(
          identity: _identity(emailVerified: false),
          memberships: [_pendingMembership('tenant-a')],
          callable: callable,
        ),
      );

      expect(find.byIcon(Icons.mark_email_read_outlined), findsNothing);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(callable.payloads, isEmpty);
    });

    testWidgets('confirmation cancellation makes no callable request', (
      tester,
    ) async {
      final callable = _AcceptCallable();
      var cancellations = 0;
      await tester.pumpWidget(
        _formApp(
          identity: _identity(),
          membership: _pendingMembership('tenant-a'),
          callable: callable,
          onCancel: () => cancellations++,
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('accept-visible-invitation-cancel')),
      );
      await tester.pump();

      expect(cancellations, 1);
      expect(callable.payloads, isEmpty);
    });

    testWidgets('duplicate taps are single-flight and retry reuses intent', (
      tester,
    ) async {
      final first = Completer<Object?>();
      final callable = _AcceptCallable(
        handler: (payload, callIndex) => callIndex == 0
            ? first.future
            : Future.value(
                _acceptedResponse(payload['tenantId']! as String, 'user-a'),
              ),
      );
      var accepted = 0;
      await tester.pumpWidget(
        _formApp(
          identity: _identity(),
          membership: _pendingMembership('tenant-a'),
          callable: callable,
          onSuccess: () => accepted++,
        ),
      );

      final submit = find.byKey(
        const ValueKey('accept-visible-invitation-confirm'),
      );
      await tester.tap(submit);
      await tester.tap(submit);
      await tester.pump();
      expect(callable.payloads, hasLength(1));

      first.completeError(StateError('raw backend secret detail'));
      await tester.pump();
      await tester.pump();
      expect(
        find.text(
          'This invitation could not be accepted. Ask your administrator to '
          'send it again if this keeps happening.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('raw backend'), findsNothing);
      expect(accepted, 0);

      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(callable.payloads, hasLength(2));
      expect(
        callable.payloads.first['requestId'],
        callable.payloads.last['requestId'],
      );
      expect(accepted, 1);
    });

    testWidgets('a permanently refused invitation is sent to the emailed link', (
      tester,
    ) async {
      // Finding 3 from the 2026-08-08 Android run, against a server that
      // decided `visibleAcceptanceAllowed` once at invite time: the old
      // "Please try again." was advice that could never work. Nothing emits
      // this violation since 2026-09-08, and the sentence it maps to is at
      // last true - the emailed link opens the app on the invitation.
      final callable = _AcceptCallable(
        handler: (_, _) => Future<Object?>.error(
          const InvitationAcceptanceException(
            'permission-denied',
            violation: InvitationAcceptanceViolation.versionedProofRequired,
          ),
        ),
      );
      var accepted = 0;
      await tester.pumpWidget(
        _formApp(
          identity: _identity(),
          membership: _pendingMembership('tenant-a'),
          callable: callable,
          onSuccess: () => accepted++,
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('accept-visible-invitation-confirm')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'This invitation has to be opened from the link in your invitation '
          'email, so it cannot be accepted here. Ask your administrator to '
          'send the invitation again if you no longer have that email.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('try again'), findsNothing);
      expect(find.textContaining('permission-denied'), findsNothing);
      expect(find.textContaining('versioned_proof_required'), findsNothing);
      expect(accepted, 0);
    });

    testWidgets('an unexplained refusal is worded for the in-app path', (
      tester,
    ) async {
      // The same code with no violation beside it means something else here
      // than it does on the emailed-link form, so the mode has to reach the
      // mapping for either sentence to be true.
      final callable = _AcceptCallable(
        handler: (_, _) => Future<Object?>.error(
          const InvitationAcceptanceException('permission-denied'),
        ),
      );
      await tester.pumpWidget(
        _formApp(
          identity: _identity(),
          membership: _pendingMembership('tenant-a'),
          callable: callable,
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('accept-visible-invitation-confirm')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'This account cannot accept invitations yet. Check that your email '
          'address is verified, and ask your administrator if it still fails.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('try again'), findsNothing);
    });

    testWidgets('a stale session is told how to make the next attempt work', (
      tester,
    ) async {
      final callable = _AcceptCallable(
        handler: (_, _) => Future<Object?>.error(
          const InvitationAcceptanceException('failed-precondition'),
        ),
      );
      await tester.pumpWidget(
        _formApp(
          identity: _identity(),
          membership: _pendingMembership('tenant-a'),
          callable: callable,
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('accept-visible-invitation-confirm')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'For your security, sign out and sign in again, then accept the '
          'invitation within five minutes.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('user switch discards an outstanding success', (tester) async {
      final pending = Completer<Object?>();
      var current = true;
      final callable = _AcceptCallable(handler: (_, _) => pending.future);
      var accepted = 0;
      await tester.pumpWidget(
        _formApp(
          identity: _identity(),
          membership: _pendingMembership('tenant-a'),
          callable: callable,
          isCurrent: () => current,
          onSuccess: () => accepted++,
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('accept-visible-invitation-confirm')),
      );
      await tester.pump();

      current = false;
      pending.complete(_acceptedResponse('tenant-a', 'user-a'));
      await tester.pump();
      await tester.pump();

      expect(accepted, 0);
      expect(find.textContaining('Invitation accepted'), findsNothing);
    });

    testWidgets('tenant membership switch discards an outstanding failure', (
      tester,
    ) async {
      final pending = Completer<Object?>();
      final callable = _AcceptCallable(handler: (_, _) => pending.future);
      await tester.pumpWidget(
        _formApp(
          identity: _identity(),
          membership: _pendingMembership('tenant-a'),
          callable: callable,
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('accept-visible-invitation-confirm')),
      );
      await tester.pump();

      await tester.pumpWidget(
        _formApp(
          identity: _identity(),
          membership: _pendingMembership('tenant-b'),
          callable: callable,
        ),
      );
      await tester.pump();
      pending.completeError(StateError('raw stale target failure'));
      await tester.pump();
      await tester.pump();

      expect(callable.payloads.single['tenantId'], 'tenant-a');
      expect(
        find.byKey(const ValueKey('accept-visible-invitation-error')),
        findsNothing,
      );
      expect(find.textContaining('raw stale'), findsNothing);
    });
  });
}

final class _AcceptCallable implements AcceptVisibleTenantInvitationCallable {
  _AcceptCallable({this.handler});

  final Future<Object?> Function(Map<String, Object?>, int)? handler;
  final List<Map<String, Object?>> payloads = [];

  @override
  Future<Object?> call(Map<String, Object?> payload) {
    final copy = Map<String, Object?>.from(payload);
    final callIndex = payloads.length;
    payloads.add(copy);
    return handler?.call(copy, callIndex) ??
        Future<Object?>.value(
          _acceptedResponse(payload['tenantId']! as String, 'user-a'),
        );
  }
}

Map<String, Object?> _acceptedResponse(String tenantId, String uid) =>
    <String, Object?>{
      'tenantId': tenantId,
      'uid': uid,
      'membershipStatus': 'active',
      'invitationStatus': 'accepted',
      'role': 'cashier',
    };

TenantVisibleInvitationIdentity _identity({
  bool emailVerified = true,
  bool globallyActive = true,
}) => TenantVisibleInvitationIdentity(
  uid: 'user-a',
  emailVerified: emailVerified,
  globallyActive: globallyActive,
);

Widget _selectorApp({
  required TenantVisibleInvitationIdentity identity,
  required List<TenantMembership> memberships,
  required AcceptVisibleTenantInvitationCallable callable,
  VoidCallback? onAccepted,
}) => MaterialApp(
  home: TenantBusinessSelector(
    identity: identity,
    requestIdentity: null,
    memberships: memberships,
    onOpen: (_) {},
    onAccepted: onAccepted ?? () {},
    onRetry: () {},
    onSignOut: () async {},
    onTenantRequested: (_) {},
    acceptVisibleInvitationCallable: callable,
    visibleInvitationRequestIdFactory: () => 'accept-widget-request',
  ),
);

Widget _formApp({
  required TenantVisibleInvitationIdentity identity,
  required TenantMembership membership,
  required AcceptVisibleTenantInvitationCallable callable,
  VoidCallback? onSuccess,
  VoidCallback? onCancel,
  TenantVisibleInvitationCurrentCheck? isCurrent,
}) => MaterialApp(
  home: Scaffold(
    body: TenantVisibleInvitationAcceptanceForm(
      identity: identity,
      membership: membership,
      callable: callable,
      requestIdFactory: () => 'accept-form-request',
      isCurrent: isCurrent,
      onSuccess: onSuccess ?? () {},
      onCancel: onCancel ?? () {},
    ),
  ),
);

TenantMembership _pendingMembership(
  String tenantId, {
  TenantRole role = TenantRole.cashier,
  TenantStatus tenantStatus = TenantStatus.active,
  String invitationStatus = 'sent',
  bool isOwner = false,
}) => _membership(
  tenantId,
  role: role,
  tenantStatus: tenantStatus,
  membershipStatus: MembershipStatus.pending,
  invitationStatus: invitationStatus,
  isOwner: isOwner,
);

TenantMembership _membership(
  String tenantId, {
  TenantRole role = TenantRole.cashier,
  MembershipStatus membershipStatus = MembershipStatus.active,
  TenantStatus tenantStatus = TenantStatus.active,
  String? invitationStatus = 'accepted',
  bool isOwner = false,
}) => TenantMembership(
  tenantId: tenantId,
  tenantName: 'Business $tenantId',
  tenantSlug: tenantId,
  role: role,
  membershipStatus: membershipStatus,
  tenantStatus: tenantStatus,
  invitationStatus: invitationStatus,
  isOwner: isOwner,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 7, 30),
  updatedAt: DateTime.utc(2026, 7, 30),
  serverCanAccess: membershipStatus == MembershipStatus.active,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);
