import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  _provisionalWindowTests();
  group('TenantRequestGateway', () {
    test('normalizes input and derives an identity-bound payload', () async {
      final callable = _RecordingCallable();
      final gateway = TenantRequestGateway(
        identity: _identity('user-a'),
        callable: callable,
        requestIdFactory: () => 'tenant-request-1',
      );

      final result = await gateway.submit(
        gateway.createIntent(name: '  Chilltent   West  ', slug: ' WEST-Shop '),
      );

      expect(callable.payloads, [
        {
          'name': 'Chilltent West',
          'slug': 'west-shop',
          'requestId': 'tenant-request-1',
        },
      ]);
      expect(result.tenantId, 'tenant-generated');
      expect(result.name, 'Chilltent West');
      expect(result.slug, 'west-shop');
      expect(result.status, TenantStatus.pending);
    });

    test('rejects invalid names and slugs before calling', () {
      final callable = _RecordingCallable();
      final gateway = TenantRequestGateway(
        identity: _identity('user-a'),
        callable: callable,
      );
      for (final input in <({String name, String slug})>[
        (name: 'A', slug: 'valid-slug'),
        (name: 'A\u0000B', slug: 'valid-slug'),
        (name: 'Valid name', slug: 'AB'),
        (name: 'Valid name', slug: '-invalid'),
        (name: 'Valid name', slug: 'two--hyphens'),
      ]) {
        expect(
          () => gateway.createIntent(name: input.name, slug: input.slug),
          throwsArgumentError,
        );
      }
      expect(callable.payloads, isEmpty);
    });

    test('blocks unverified, disabled, and platform identities', () {
      for (final identity in [
        _identity('unverified', emailVerified: false),
        _identity('disabled', globallyActive: false),
        _identity('platform', accountType: RootAccountType.platformAdmin),
      ]) {
        final gateway = TenantRequestGateway(
          identity: identity,
          callable: _RecordingCallable(),
        );
        expect(
          () => gateway.createIntent(name: 'Valid name', slug: 'valid-slug'),
          throwsStateError,
        );
      }
    });

    test('rejects an intent created for another identity without a call', () {
      final first = TenantRequestGateway(
        identity: _identity('user-a'),
        callable: _RecordingCallable(),
        requestIdFactory: () => 'tenant-request-a',
      );
      final callable = _RecordingCallable();
      final second = TenantRequestGateway(
        identity: _identity('user-b'),
        callable: callable,
      );

      expect(
        second.submit(
          first.createIntent(name: 'Business A', slug: 'business-a'),
        ),
        throwsStateError,
      );
      expect(callable.payloads, isEmpty);
    });

    test('strictly rejects malformed or mismatched responses', () async {
      for (final response in <Object?>[
        null,
        {'tenantId': 'tenant-a'},
        {
          'tenantId': 'tenant-a',
          'name': 'Business A',
          'slug': 'business-a',
          'status': 'active',
        },
        {
          'tenantId': 'tenant-a',
          'name': 'Another business',
          'slug': 'business-a',
          'status': 'pending',
          'provisionalUntil': _provisionalUntilMillis,
        },
        {
          'tenantId': 'tenant-a',
          'name': 'Business A',
          'slug': 'another-slug',
          'status': 'pending',
          'provisionalUntil': _provisionalUntilMillis,
        },
        {
          'tenantId': 'escape/path',
          'name': 'Business A',
          'slug': 'business-a',
          'status': 'pending',
          'provisionalUntil': _provisionalUntilMillis,
        },
        {
          'tenantId': 'tenant-a',
          'name': 'Business A',
          'slug': 'business-a',
          'status': 'pending',
          'extra': true,
        },
      ]) {
        final gateway = TenantRequestGateway(
          identity: _identity('user-a'),
          callable: _FixedCallable(response),
          requestIdFactory: () => 'tenant-request-a',
        );
        await expectLater(
          gateway.submit(
            gateway.createIntent(name: 'Business A', slug: 'business-a'),
          ),
          throwsA(isA<FormatException>()),
        );
      }
    });
  });

  testWidgets('requires review and confirmation before submission', (
    tester,
  ) async {
    final callable = _RecordingCallable();
    final fixture = _FormFixture(callable: callable);
    await fixture.pump(tester);
    await _enterRequest(tester);

    await tester.tap(find.byKey(const ValueKey('tenant-request-review')));
    await tester.pump();
    expect(
      find.text('Submit Chilltent West (chilltent-west) for platform review?'),
      findsOneWidget,
    );
    expect(callable.payloads, isEmpty);

    await tester.tap(find.byKey(const ValueKey('tenant-request-cancel')));
    await tester.pump();
    expect(callable.payloads, isEmpty);
    expect(fixture.successes, isEmpty);

    await tester.tap(find.byKey(const ValueKey('tenant-request-review')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tenant-request-confirm')));
    await tester.pumpAndSettle();

    expect(callable.payloads.single, {
      'name': 'Chilltent West',
      'slug': 'chilltent-west',
      'requestId': 'tenant-widget-request',
    });
    expect(fixture.successes.single.tenantId, 'tenant-generated');
  });

  testWidgets('duplicate taps are single-flight', (tester) async {
    final completion = Completer<Object?>();
    final callable = _CompletingCallable(completion);
    final fixture = _FormFixture(callable: callable);
    await fixture.pump(tester);
    await _enterRequest(tester);
    await tester.tap(find.byKey(const ValueKey('tenant-request-review')));
    await tester.pump();

    final confirm = find.byKey(const ValueKey('tenant-request-confirm'));
    await tester.tap(confirm);
    await tester.tap(confirm);
    await tester.pump();
    expect(callable.payloads, hasLength(1));

    completion.complete(_success());
    await tester.pumpAndSettle();
    expect(fixture.successes, hasLength(1));
  });

  testWidgets('retry reuses the idempotency key and maps safe errors', (
    tester,
  ) async {
    final callable = _FailOnceCallable();
    final fixture = _FormFixture(callable: callable);
    await fixture.pump(tester);
    await _enterRequest(tester);
    await tester.tap(find.byKey(const ValueKey('tenant-request-review')));
    await tester.pump();
    final confirm = find.byKey(const ValueKey('tenant-request-confirm'));

    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.textContaining('sensitive'), findsNothing);
    expect(
      find.text('That business slug is already in use. Choose another slug.'),
      findsOneWidget,
    );

    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(callable.payloads, hasLength(2));
    expect(callable.payloads[0], callable.payloads[1]);
    expect(fixture.successes, hasLength(1));
  });

  testWidgets('discards completion after an Auth UID change', (tester) async {
    final completion = Completer<Object?>();
    final callable = _CompletingCallable(completion);
    var identity = _identity('user-a');
    final successes = <TenantRequestResult>[];

    Future<void> pump() => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TenantRequestForm(
            identity: identity,
            callable: callable,
            requestIdFactory: () => 'tenant-widget-request',
            onSuccess: successes.add,
            onCancel: () {},
          ),
        ),
      ),
    );

    await pump();
    await _enterRequest(tester);
    await tester.tap(find.byKey(const ValueKey('tenant-request-review')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tenant-request-confirm')));
    await tester.pump();

    identity = _identity('user-b');
    await pump();
    completion.complete(_success());
    await tester.pumpAndSettle();

    expect(successes, isEmpty);
    expect(find.textContaining('submitted for review'), findsNothing);
  });

  test('safe limit and generic errors never expose backend details', () {
    expect(
      tenantRequestSafeError(
        const TenantRequestCallableException('resource-exhausted'),
      ),
      'Your business request limit has been reached. Please try again later.',
    );
    expect(
      tenantRequestSafeError(StateError('sensitive-backend-detail')),
      'Business request could not be submitted. Please try again.',
    );
  });
}

Future<void> _enterRequest(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('tenant-request-name')),
    '  Chilltent   West  ',
  );
  await tester.enterText(
    find.byKey(const ValueKey('tenant-request-slug')),
    ' Chilltent-West ',
  );
  await tester.pump();
}

final class _FormFixture {
  _FormFixture({required this.callable});

  final RequestTenantCallable callable;
  final successes = <TenantRequestResult>[];

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TenantRequestForm(
          identity: _identity('user-a'),
          callable: callable,
          requestIdFactory: () => 'tenant-widget-request',
          onSuccess: successes.add,
          onCancel: () {},
        ),
      ),
    ),
  );
}

final class _RecordingCallable implements RequestTenantCallable {
  final payloads = <Map<String, Object?>>[];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(Map<String, Object?>.from(payload));
    return _success(
      name: payload['name']! as String,
      slug: payload['slug']! as String,
    );
  }
}

final class _FixedCallable implements RequestTenantCallable {
  const _FixedCallable(this.value);

  final Object? value;

  @override
  Future<Object?> call(Map<String, Object?> payload) async => value;
}

final class _CompletingCallable implements RequestTenantCallable {
  _CompletingCallable(this.completion);

  final Completer<Object?> completion;
  final payloads = <Map<String, Object?>>[];

  @override
  Future<Object?> call(Map<String, Object?> payload) {
    payloads.add(Map<String, Object?>.from(payload));
    return completion.future;
  }
}

final class _FailOnceCallable implements RequestTenantCallable {
  final payloads = <Map<String, Object?>>[];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(Map<String, Object?>.from(payload));
    if (payloads.length == 1) {
      throw const TenantRequestCallableException('already-exists');
    }
    return _success(
      name: payload['name']! as String,
      slug: payload['slug']! as String,
    );
  }
}

TenantRequestIdentity _identity(
  String uid, {
  bool emailVerified = true,
  bool globallyActive = true,
  RootAccountType accountType = RootAccountType.tenantUser,
}) => TenantRequestIdentity(
  uid: uid,
  emailVerified: emailVerified,
  profile: RootRoutingProfile(
    accountType: accountType,
    globalStatus: globallyActive ? 'active' : 'disabled',
  ),
);

/// 2026-09-05 09:00 UTC: a week after the request the fixtures represent.
const int _provisionalUntilMillis = 1788339600000;

TenantRequestGateway _gatewayWith(RequestTenantCallable callable) =>
    TenantRequestGateway(
      identity: _identity('user-a'),
      callable: callable,
      requestIdFactory: () => 'tenant-request-1',
    );

void _provisionalWindowTests() {
  group('the provisional window the response carries', () {
    test('is decoded as the instant the server computed', () async {
      final gateway = _gatewayWith(_FixedCallable(_success()));
      final result = await gateway.submit(
        gateway.createIntent(name: 'Chilltent West', slug: 'chilltent-west'),
      );

      expect(
        result.provisionalUntil,
        DateTime.fromMillisecondsSinceEpoch(
          _provisionalUntilMillis,
          isUtc: true,
        ),
      );
      expect(result.provisionalUntil.isUtc, isTrue);
    });

    test('a response without one is refused rather than assumed', () async {
      // The window is the only thing that says how long this business may
      // trade. A response that omits it is a server this client does not
      // understand, not a business with no deadline.
      final gateway = _gatewayWith(
        const _FixedCallable(<String, Object?>{
          'tenantId': 'tenant-generated',
          'name': 'Chilltent West',
          'slug': 'chilltent-west',
          'status': 'pending',
        }),
      );

      await expectLater(
        gateway.submit(
          gateway.createIntent(name: 'Chilltent West', slug: 'chilltent-west'),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('a window that is not a whole number of millis is refused', () async {
      for (final value in <Object?>['soon', 1788339600000.5, null]) {
        final gateway = _gatewayWith(
          _FixedCallable(<String, Object?>{
            ..._success(),
            'provisionalUntil': value,
          }),
        );

        await expectLater(
          gateway.submit(
            gateway.createIntent(
              name: 'Chilltent West',
              slug: 'chilltent-west',
            ),
          ),
          throwsA(isA<FormatException>()),
        );
      }
    });
  });
}

Map<String, Object?> _success({
  String name = 'Chilltent West',
  String slug = 'chilltent-west',
}) => {
  'tenantId': 'tenant-generated',
  'name': name,
  'slug': slug,
  'status': 'pending',
  'provisionalUntil': _provisionalUntilMillis,
};
