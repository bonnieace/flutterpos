import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/landing_drawer.dart';

void main() {
  group('TenantDefaultGateway', () {
    for (final role in TenantRole.values) {
      test(
        '${role.wireValue} uses the captured active tenant session',
        () async {
          final callable = _RecordingCallable();
          final gateway = TenantDefaultGateway(
            session: _session('tenant-a', role: role),
            callable: callable,
            requestIdFactory: () => 'default-request-${role.wireValue}',
          );

          final result = await gateway.submit(gateway.createIntent());

          expect(callable.payloads, [
            {
              'tenantId': 'tenant-a',
              'requestId': 'default-request-${role.wireValue}',
            },
          ]);
          expect(result.tenantId, 'tenant-a');
          expect(result.defaultTenantId, 'tenant-a');
        },
      );
    }

    test(
      'rejects an intent captured from another session without a call',
      () async {
        final callable = _RecordingCallable();
        final first = TenantDefaultGateway(
          session: _session('tenant-a'),
          callable: callable,
          requestIdFactory: () => 'default-request-a',
        );
        final second = TenantDefaultGateway(
          session: _session('tenant-b'),
          callable: callable,
        );

        await expectLater(
          second.submit(first.createIntent()),
          throwsA(isA<StateError>()),
        );
        expect(callable.payloads, isEmpty);
      },
    );

    test(
      'strictly rejects malformed and mismatched callable responses',
      () async {
        for (final response in <Object?>[
          null,
          {'tenantId': 'tenant-a'},
          {
            'tenantId': 'tenant-a',
            'defaultTenantId': 'tenant-a',
            'extra': true,
          },
          {'tenantId': 'tenant-b', 'defaultTenantId': 'tenant-b'},
          {'tenantId': 'tenant-a', 'defaultTenantId': 'tenant-b'},
          {'tenantId': 'escape/path', 'defaultTenantId': 'escape/path'},
        ]) {
          final gateway = TenantDefaultGateway(
            session: _session('tenant-a'),
            callable: _FixedCallable(response),
            requestIdFactory: () => 'default-request-a',
          );
          await expectLater(
            gateway.submit(gateway.createIntent()),
            throwsA(isA<FormatException>()),
          );
        }
      },
    );
  });

  testWidgets('landing action requires explicit confirmation', (tester) async {
    final callable = _RecordingCallable();
    final controller = TenantSessionController()
      ..open(uid: 'user-a', membership: _membership('tenant-a'));
    var refreshes = 0;
    await tester.pumpWidget(
      _landingHarness(
        controller: controller,
        callable: callable,
        onSuccess: () => refreshes++,
      ),
    );
    await tester.pump();

    await _openDefaultForm(tester);
    expect(
      find.text('Make Business tenant-a your default business?'),
      findsOneWidget,
    );
    expect(callable.payloads, isEmpty);

    await tester.tap(find.byKey(const ValueKey('set-default-tenant-cancel')));
    await tester.pumpAndSettle();
    expect(callable.payloads, isEmpty);
    expect(refreshes, 0);

    await _openDefaultForm(tester);
    await tester.tap(find.byKey(const ValueKey('set-default-tenant-confirm')));
    await tester.pumpAndSettle();

    expect(callable.payloads.single, {
      'tenantId': 'tenant-a',
      'requestId': 'default-widget-request',
    });
    expect(refreshes, 1);
  });

  testWidgets('duplicate taps are single-flight', (tester) async {
    final completion = Completer<Object?>();
    final callable = _CompletingCallable(completion);
    final fixture = _FormFixture(callable: callable);
    await fixture.pump(tester);

    final confirm = find.byKey(const ValueKey('set-default-tenant-confirm'));
    await tester.tap(confirm);
    await tester.tap(confirm);
    await tester.pump();

    expect(callable.payloads, hasLength(1));
    completion.complete(_success('tenant-a'));
    await tester.pumpAndSettle();
    expect(fixture.successes, 1);
  });

  testWidgets('retry reuses the same idempotency key and hides raw errors', (
    tester,
  ) async {
    final callable = _FailOnceCallable();
    final fixture = _FormFixture(callable: callable);
    await fixture.pump(tester);

    final confirm = find.byKey(const ValueKey('set-default-tenant-confirm'));
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(find.textContaining('sensitive-backend-detail'), findsNothing);
    expect(
      find.text('Default business could not be changed. Please try again.'),
      findsOneWidget,
    );
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(callable.payloads, hasLength(2));
    expect(callable.payloads[0], callable.payloads[1]);
    expect(fixture.successes, 1);
  });

  testWidgets('discards completion after a tenant session switch', (
    tester,
  ) async {
    final completion = Completer<Object?>();
    final callable = _CompletingCallable(completion);
    final fixture = _FormFixture(callable: callable);
    await fixture.pump(tester);

    await tester.tap(find.byKey(const ValueKey('set-default-tenant-confirm')));
    await tester.pump();
    fixture.controller.open(uid: 'user-a', membership: _membership('tenant-b'));
    await tester.pump();
    completion.complete(_success('tenant-a'));
    await tester.pump();
    await tester.pump();

    expect(fixture.successes, 0);
    expect(find.textContaining('is now default'), findsNothing);
  });

  testWidgets('discards completion after the same tenant gets a new epoch', (
    tester,
  ) async {
    final completion = Completer<Object?>();
    final callable = _CompletingCallable(completion);
    final fixture = _FormFixture(callable: callable);
    await fixture.pump(tester);

    await tester.tap(find.byKey(const ValueKey('set-default-tenant-confirm')));
    await tester.pump();
    fixture.controller.open(uid: 'user-a', membership: _membership('tenant-a'));
    await tester.pump();
    completion.complete(_success('tenant-a'));
    await tester.pump();
    await tester.pump();

    expect(fixture.successes, 0);
  });
}

final class _FormFixture {
  _FormFixture({required this.callable}) {
    controller.open(uid: 'user-a', membership: membership);
    session = controller.requireSession();
  }

  final SetDefaultTenantCallable callable;
  final TenantSessionController controller = TenantSessionController();
  final TenantMembership membership = _membership('tenant-a');
  late final TenantSession session;
  int successes = 0;

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: Scaffold(
          body: TenantDefaultForm(
            session: session,
            membership: membership,
            callable: callable,
            requestIdFactory: () => 'default-widget-request',
            onSuccess: () => successes++,
            onCancel: () {},
          ),
        ),
      ),
    ),
  );
}

/// Opens the default-business form the way a person does: through the business
/// switcher on the title, which is where it moved on 2026-09-16.
Future<void> _openDefaultForm(WidgetTester tester) async {
  await openLandingDrawer(tester);
  await tester.tap(find.byKey(const ValueKey('screen-title-action')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('make-default-tenant')));
  await tester.pumpAndSettle();
}

Widget _landingHarness({
  required TenantSessionController controller,
  required SetDefaultTenantCallable callable,
  required VoidCallback onSuccess,
}) => MaterialApp(
  home: TenantSessionScope(
    controller: controller,
    child: TenantSafeLandingScreen(
      membership: _membership('tenant-a'),
      reader: _EmptyReader(),
      onSignOut: () async {},
      setDefaultTenantCallable: callable,
      defaultTenantRequestIdFactory: () => 'default-widget-request',
      onDefaultTenantChanged: onSuccess,
      // **The default control lives in the business switcher since
      // 2026-09-16**, and the switcher only opens where there is another
      // business to go to - so reaching it needs both of these.
      onSwitchTenant: (target) async => TenantSwitchResult.switched(target),
      switchCandidates: <TenantMembership>[
        _membership('tenant-a'),
        _membership('tenant-b'),
      ],
    ),
  ),
);

final class _RecordingCallable implements SetDefaultTenantCallable {
  final List<Map<String, Object?>> payloads = [];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(Map<String, Object?>.from(payload));
    return _success(payload['tenantId']! as String);
  }
}

final class _FixedCallable implements SetDefaultTenantCallable {
  const _FixedCallable(this.value);

  final Object? value;

  @override
  Future<Object?> call(Map<String, Object?> payload) async => value;
}

final class _CompletingCallable implements SetDefaultTenantCallable {
  _CompletingCallable(this.completion);

  final Completer<Object?> completion;
  final List<Map<String, Object?>> payloads = [];

  @override
  Future<Object?> call(Map<String, Object?> payload) {
    payloads.add(Map<String, Object?>.from(payload));
    return completion.future;
  }
}

final class _FailOnceCallable implements SetDefaultTenantCallable {
  final List<Map<String, Object?>> payloads = [];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(Map<String, Object?>.from(payload));
    if (payloads.length == 1) {
      throw StateError('sensitive-backend-detail');
    }
    return _success(payload['tenantId']! as String);
  }
}

final class _EmptyReader implements TenantDataReader {
  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async => null;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async => const [];
}

Map<String, Object?> _success(String tenantId) => {
  'tenantId': tenantId,
  'defaultTenantId': tenantId,
};

TenantSession _session(String tenantId, {TenantRole role = TenantRole.admin}) =>
    TenantSession.active(uid: 'user-a', tenantId: tenantId, role: role);

TenantMembership _membership(
  String tenantId, {
  TenantRole role = TenantRole.admin,
}) => TenantMembership(
  tenantId: tenantId,
  tenantName: 'Business $tenantId',
  tenantSlug: tenantId,
  role: role,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  invitationStatus: 'accepted',
  isOwner: role == TenantRole.owner,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 7, 30),
  updatedAt: DateTime.utc(2026, 7, 30),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);
