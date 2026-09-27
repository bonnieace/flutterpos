import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tenant invitation link', () {
    test('parses the exact versioned proof fields', () {
      final link = TenantInvitationLink.fromUriIfPresent(_invitationUri());

      expect(link, isNotNull);
      expect(link!.tenantId, 'tenant-a');
      expect(link.invitedUid, 'user-a');
      expect(link.invitationVersion, 4);
      expect(link.invitationToken, _tokenA);
      expect(
        TenantInvitationLink.fromUriIfPresent(
          Uri.parse('https://pos.example.test/invitations'),
        ),
        isNull,
      );
    });

    test(
      'fails closed for partial, duplicate, insecure, and invalid fields',
      () {
        final malformed = <Uri>[
          Uri.parse('https://pos.example.test/?tenantId=tenant-a'),
          _invitationUri(scheme: 'http'),
          _invitationUri(version: '0'),
          _invitationUri(version: '9007199254740992'),
          _invitationUri(token: 'short'),
          _invitationUri(tenantId: 'tenant/a'),
          _invitationUri(uid: 'user/a'),
          Uri.parse(
            'https://pos.example.test/?tenantId=tenant-a&tenantId=tenant-b'
            '&uid=user-a&invitationVersion=4&invitationToken=$_tokenA',
          ),
        ];

        for (final uri in malformed) {
          expect(
            () => TenantInvitationLink.fromUriIfPresent(uri),
            throwsFormatException,
            reason: uri.toString(),
          );
        }
      },
    );
  });

  group('token invitation acceptance contract', () {
    test('derives the exact callable payload and reuses one intent', () async {
      final callable = _AcceptCallable();
      var generatedIds = 0;
      final gateway = TenantInvitationAcceptanceGateway(
        currentUid: 'user-a',
        invitationLink: _link(),
        callable: callable,
        expectedRole: TenantRole.cashier,
        requestIdFactory: () => 'accept-request-${++generatedIds}',
      );
      final intent = gateway.createIntent();

      final first = await gateway.submit(intent);
      final second = await gateway.submit(intent);

      expect(generatedIds, 1);
      expect(callable.payloads, hasLength(2));
      expect(callable.payloads.first, {
        'tenantId': 'tenant-a',
        'invitationVersion': 4,
        'invitationToken': _tokenA,
        'requestId': 'accept-request-1',
      });
      expect(callable.payloads.last['requestId'], 'accept-request-1');
      expect(first.uid, 'user-a');
      expect(first.membershipStatus, MembershipStatus.active);
      expect(second.invitationStatus, 'accepted');
    });

    test('rejects another authenticated user without a callable request', () {
      final callable = _AcceptCallable();
      final gateway = TenantInvitationAcceptanceGateway(
        currentUid: 'user-b',
        invitationLink: _link(),
        callable: callable,
        requestIdFactory: () => 'accept-request-1',
      );

      expect(gateway.belongsToCurrentUser, isFalse);
      expect(gateway.createIntent, throwsFormatException);
      expect(callable.payloads, isEmpty);
    });

    test('strictly rejects malformed, mismatched, and owner responses', () {
      final valid = _acceptedResponse('tenant-a', 'user-a');
      final malformed = <Object?>[
        null,
        {...valid, 'tenantId': 'tenant-b'},
        {...valid, 'uid': 'user-b'},
        {...valid, 'uid': 'bad/uid'},
        {...valid, 'role': 'owner'},
        {...valid, 'role': 'manager'},
        {...valid, 'membershipStatus': 'pending'},
        {...valid, 'invitationStatus': 'sent'},
        {...valid, 'unexpected': true},
      ];

      for (final response in malformed) {
        expect(
          () => TenantInvitationAcceptanceResult.fromCallable(
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

  group('token invitation acceptance UI', () {
    testWidgets('shows available business metadata and accepts explicitly', (
      tester,
    ) async {
      final callable = _AcceptCallable();
      var accepted = 0;
      await tester.pumpWidget(
        _formApp(
          currentUid: 'user-a',
          link: _link(),
          callable: callable,
          tenantName: 'Chilltent West',
          invitedRole: TenantRole.cashier,
          onSuccess: () => accepted++,
        ),
      );

      expect(find.text('Accept invitation to Chilltent West?'), findsOneWidget);
      expect(find.text('Invited role: cashier'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('accept-token-invitation-confirm')),
      );
      await tester.pumpAndSettle();

      expect(callable.payloads, hasLength(1));
      expect(accepted, 1);
      expect(find.text('Invitation accepted.'), findsOneWidget);
    });

    testWidgets('confirmation dismissal performs no mutation', (tester) async {
      final callable = _AcceptCallable();
      var cancelled = 0;
      await tester.pumpWidget(
        _formApp(
          currentUid: 'user-a',
          link: _link(),
          callable: callable,
          onCancel: () => cancelled++,
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('accept-token-invitation-cancel')),
      );
      await tester.pump();

      expect(cancelled, 1);
      expect(callable.payloads, isEmpty);
    });

    testWidgets('duplicate taps are single-flight and retry reuses intent', (
      tester,
    ) async {
      final first = Completer<Object?>();
      final callable = _AcceptCallable(
        handler: (payload, callIndex) => callIndex == 0
            ? first.future
            : Future.value(_acceptedResponse('tenant-a', 'user-a')),
      );
      var accepted = 0;
      await tester.pumpWidget(
        _formApp(
          currentUid: 'user-a',
          link: _link(),
          callable: callable,
          onSuccess: () => accepted++,
        ),
      );
      final submit = find.byKey(
        const ValueKey('accept-token-invitation-confirm'),
      );

      await tester.tap(submit);
      await tester.tap(submit);
      await tester.pump();
      expect(callable.payloads, hasLength(1));

      first.completeError(StateError('raw backend proof detail'));
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

      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(callable.payloads, hasLength(2));
      expect(
        callable.payloads.first['requestId'],
        callable.payloads.last['requestId'],
      );
      expect(accepted, 1);
    });

    testWidgets('a rejected proof is not a refusal a retry can fix', (
      tester,
    ) async {
      // The other half of finding 3. This form threw the code away with
      // `catch (_)` too, so a link the server had rejected outright still said
      // "Please try again."
      final callable = _AcceptCallable(
        handler: (_, _) => Future<Object?>.error(
          const InvitationAcceptanceException('permission-denied'),
        ),
      );
      var accepted = 0;
      await tester.pumpWidget(
        _formApp(
          currentUid: 'user-a',
          link: _link(),
          callable: callable,
          onSuccess: () => accepted++,
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('accept-token-invitation-confirm')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'This invitation link is no longer valid. Ask your administrator to '
          'send a new invitation.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('try again'), findsNothing);
      expect(find.textContaining('permission-denied'), findsNothing);
      expect(accepted, 0);
    });

    testWidgets('a cancelled invitation names the person who can reissue it', (
      tester,
    ) async {
      final callable = _AcceptCallable(
        handler: (_, _) => Future<Object?>.error(
          const InvitationAcceptanceException(
            'permission-denied',
            violation: InvitationAcceptanceViolation.invitationNotPending,
          ),
        ),
      );
      await tester.pumpWidget(
        _formApp(currentUid: 'user-a', link: _link(), callable: callable),
      );

      await tester.tap(
        find.byKey(const ValueKey('accept-token-invitation-confirm')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'This invitation is no longer open. Ask your administrator to invite '
          'you again.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('try again'), findsNothing);
    });

    testWidgets('an unreachable server is the one case that says try again', (
      tester,
    ) async {
      // The rule stated from the other side: a retry is offered exactly when a
      // retry can work.
      final callable = _AcceptCallable(
        handler: (_, _) => Future<Object?>.error(
          const InvitationAcceptanceException('unavailable'),
        ),
      );
      await tester.pumpWidget(
        _formApp(currentUid: 'user-a', link: _link(), callable: callable),
      );

      await tester.tap(
        find.byKey(const ValueKey('accept-token-invitation-confirm')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'This device could not reach the server. Check the connection and '
          'try again.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('authenticated-user switch discards an outstanding success', (
      tester,
    ) async {
      final pending = Completer<Object?>();
      final callable = _AcceptCallable(handler: (_, _) => pending.future);
      var accepted = 0;
      await tester.pumpWidget(
        _formApp(
          currentUid: 'user-a',
          link: _link(),
          callable: callable,
          onSuccess: () => accepted++,
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('accept-token-invitation-confirm')),
      );
      await tester.pump();

      await tester.pumpWidget(
        _formApp(
          currentUid: 'user-b',
          link: _link(uid: 'user-b'),
          callable: callable,
          onSuccess: () => accepted++,
        ),
      );
      pending.complete(_acceptedResponse('tenant-a', 'user-a'));
      await tester.pump();
      await tester.pump();

      expect(accepted, 0);
      expect(find.textContaining('Invitation accepted'), findsNothing);
    });

    testWidgets('link switch discards an outstanding failure', (tester) async {
      final pending = Completer<Object?>();
      final callable = _AcceptCallable(handler: (_, _) => pending.future);
      await tester.pumpWidget(
        _formApp(currentUid: 'user-a', link: _link(), callable: callable),
      );
      await tester.tap(
        find.byKey(const ValueKey('accept-token-invitation-confirm')),
      );
      await tester.pump();

      await tester.pumpWidget(
        _formApp(
          currentUid: 'user-a',
          link: _link(tenantId: 'tenant-b', token: _tokenB),
          callable: callable,
        ),
      );
      pending.completeError(StateError('raw stale proof failure'));
      await tester.pump();
      await tester.pump();

      expect(callable.payloads.single['tenantId'], 'tenant-a');
      expect(
        find.byKey(const ValueKey('accept-token-invitation-error')),
        findsNothing,
      );
      expect(find.textContaining('raw stale'), findsNothing);
    });
  });
}

final class _AcceptCallable implements AcceptTenantInvitationCallable {
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

Widget _formApp({
  required String currentUid,
  required TenantInvitationLink link,
  required AcceptTenantInvitationCallable callable,
  String? tenantName,
  TenantRole? invitedRole,
  VoidCallback? onSuccess,
  VoidCallback? onCancel,
}) => MaterialApp(
  home: Scaffold(
    body: TenantInvitationAcceptanceForm(
      currentUid: currentUid,
      invitationLink: link,
      callable: callable,
      tenantName: tenantName,
      invitedRole: invitedRole,
      requestIdFactory: () => 'accept-form-request',
      onSuccess: onSuccess ?? () {},
      onCancel: onCancel ?? () {},
    ),
  ),
);

TenantInvitationLink _link({
  String tenantId = 'tenant-a',
  String uid = 'user-a',
  String token = _tokenA,
}) => TenantInvitationLink.fromUriIfPresent(
  _invitationUri(tenantId: tenantId, uid: uid, token: token),
)!;

Uri _invitationUri({
  String scheme = 'https',
  String tenantId = 'tenant-a',
  String uid = 'user-a',
  String version = '4',
  String token = _tokenA,
}) => Uri(
  scheme: scheme,
  host: 'pos.example.test',
  path: '/invitations',
  queryParameters: {
    'tenantId': tenantId,
    'uid': uid,
    'invitationVersion': version,
    'invitationToken': token,
  },
);

Map<String, Object?> _acceptedResponse(String tenantId, String uid) =>
    <String, Object?>{
      'tenantId': tenantId,
      'uid': uid,
      'role': 'cashier',
      'membershipStatus': 'active',
      'invitationStatus': 'accepted',
    };

const _tokenA = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const _tokenB = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';
