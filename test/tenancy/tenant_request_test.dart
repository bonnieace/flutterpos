import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  _slugDerivationTests();
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
        gateway.createIntent(
          name: '  Chilltent   West  ',
          slug: ' WEST-Shop ',
          currency: ' tzs ',
        ),
      );

      expect(callable.payloads, [
        {
          'name': 'Chilltent West',
          'slug': 'west-shop',
          // Normalized to one casing on the way out, the way the name and the
          // slug already are.
          'currency': 'TZS',
          'requestId': 'tenant-request-1',
        },
      ]);
      expect(result.tenantId, 'tenant-generated');
      expect(result.name, 'Chilltent West');
      expect(result.slug, 'west-shop');
      expect(result.currency, 'TZS');
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
          () => gateway.createIntent(
            name: input.name,
            slug: input.slug,
            currency: 'TZS',
          ),
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
          () => gateway.createIntent(
            name: 'Valid name',
            slug: 'valid-slug',
            currency: 'TZS',
          ),
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
          first.createIntent(
            name: 'Business A',
            slug: 'business-a',
            currency: 'TZS',
          ),
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
          'currency': 'TZS',
          'status': 'pending',
          'provisionalUntil': _provisionalUntilMillis,
        },
        {
          'tenantId': 'tenant-a',
          'name': 'Business A',
          'slug': 'another-slug',
          'currency': 'TZS',
          'status': 'pending',
          'provisionalUntil': _provisionalUntilMillis,
        },
        {
          'tenantId': 'escape/path',
          'name': 'Business A',
          'slug': 'business-a',
          'currency': 'TZS',
          'status': 'pending',
          'provisionalUntil': _provisionalUntilMillis,
        },
        {
          'tenantId': 'tenant-a',
          'name': 'Business A',
          'slug': 'business-a',
          'currency': 'TZS',
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
            gateway.createIntent(
            name: 'Business A',
            slug: 'business-a',
            currency: 'TZS',
          ),
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
      find.text(
        'Submit Chilltent West (chilltent-west-20260830-1645), trading in '
        'TZS, for platform review?',
      ),
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
      // Derived from the name and the clock, not typed.
      'slug': 'chilltent-west-20260830-1645',
      // The select's default, which is the first offered currency.
      'currency': 'TZS',
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

    // The response must echo the *derived* slug, or the strict decoder
    // rejects it as another business - which is what it is there to do.
    completion.complete(_success(slug: 'chilltent-west-20260830-1645'));
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
            clock: () => _slugNow,
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

  test('a refusal says so rather than inviting a retry that cannot work', () {
    expect(
      tenantRequestSafeError(
        const TenantRequestCallableException('permission-denied'),
      ),
      'This account cannot request a business. Check that your email is '
      'verified and that you are signed in with the right account.',
    );
  });
}

Future<void> _enterRequest(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('tenant-request-name')),
    '  Chilltent   West  ',
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
          // Fixed, so the derived slug is a value these tests can name.
          clock: () => _slugNow,
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
      currency: payload['currency']! as String,
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
        gateway.createIntent(
          name: 'Chilltent West',
          slug: 'chilltent-west',
          currency: 'TZS',
        ),
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
          'currency': 'TZS',
          'status': 'pending',
        }),
      );

      await expectLater(
        gateway.submit(
          gateway.createIntent(
          name: 'Chilltent West',
          slug: 'chilltent-west',
          currency: 'TZS',
        ),
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
              currency: 'TZS',
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
  String currency = 'TZS',
}) => {
  'tenantId': 'tenant-generated',
  'name': name,
  'slug': slug,
  'currency': currency,
  'status': 'pending',
  'provisionalUntil': _provisionalUntilMillis,
};

// ---------------------------------------------------------------------------
// The slug is derived rather than asked for
// ---------------------------------------------------------------------------

final DateTime _slugNow = DateTime.utc(2026, 8, 30, 16, 45);

void _slugDerivationTests() {
  group('deriving a slug from the name', () {
    test('is the name, then when it was asked for', () {
      expect(
        deriveTenantRequestSlug('Chilltent', _slugNow),
        'chilltent-20260830-1645',
      );
    });

    test('folds spaces and punctuation into single hyphens', () {
      expect(
        deriveTenantRequestSlug("Bob & Sons' Shop", _slugNow),
        'bob-sons-shop-20260830-1645',
      );
    });

    test('never produces a leading, trailing or doubled hyphen', () {
      // All three are refused by `normalizeTenantRequestSlug`, so a derivation
      // that produced one would fail the same request it was meant to simplify.
      for (final name in <String>[
        '  Chilltent  ',
        '---Chilltent---',
        'Chill   tent',
        '!!!',
        'a',
      ]) {
        final slug = deriveTenantRequestSlug(name, _slugNow);
        expect(slug.startsWith('-'), isFalse, reason: name);
        expect(slug.endsWith('-'), isFalse, reason: name);
        expect(slug.contains('--'), isFalse, reason: name);
        // The real proof: the server's own normalizer accepts it.
        expect(() => normalizeTenantRequestSlug(slug), returnsNormally,
            reason: name);
      }
    });

    test('a name with nothing usable in it still yields a slug', () {
      // Punctuation only, or a script this transliterates nothing of. It still
      // has to produce something the server accepts rather than a refusal.
      expect(deriveTenantRequestSlug('!!!', _slugNow), 'shop-20260830-1645');
      expect(deriveTenantRequestSlug('日本語', _slugNow), 'shop-20260830-1645');
    });

    test('a very long name is truncated to fit the 48-character limit', () {
      final slug = deriveTenantRequestSlug('a' * 200, _slugNow);

      expect(slug.length, lessThanOrEqualTo(maximumTenantSlugLength));
      expect(slug.endsWith('-20260830-1645'), isTrue);
      expect(() => normalizeTenantRequestSlug(slug), returnsNormally);
    });

    test('truncation never leaves a hyphen against the timestamp', () {
      // Cutting mid-word can land exactly on a separator, which would produce
      // the `--` the server refuses.
      final slug = deriveTenantRequestSlug('${'ab ' * 40}tail', _slugNow);

      expect(slug.contains('--'), isFalse);
      expect(() => normalizeTenantRequestSlug(slug), returnsNormally);
    });

    test('two shops of the same name a minute apart differ', () {
      expect(
        deriveTenantRequestSlug('Chilltent', _slugNow),
        isNot(
          deriveTenantRequestSlug(
            'Chilltent',
            _slugNow.add(const Duration(minutes: 1)),
          ),
        ),
      );
    });

    test('the timestamp is read in UTC, not the device zone', () {
      // The same instant expressed in another zone must derive the same slug,
      // or two devices would disagree about one business.
      expect(
        deriveTenantRequestSlug(
          'Chilltent',
          _slugNow.toLocal(),
        ),
        deriveTenantRequestSlug('Chilltent', _slugNow),
      );
    });
  });
}
