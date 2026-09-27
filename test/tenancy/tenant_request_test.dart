import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  _slugDerivationTests();
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
      expect(result.status, TenantStatus.active);
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
          'status': 'active',
        },
        {
          'tenantId': 'tenant-a',
          'name': 'Business A',
          'slug': 'another-slug',
          'currency': 'TZS',
          'status': 'active',
        },
        {
          'tenantId': 'escape/path',
          'name': 'Business A',
          'slug': 'business-a',
          'currency': 'TZS',
          'status': 'active',
        },
        {
          'tenantId': 'tenant-a',
          'name': 'Business A',
          'slug': 'business-a',
          'currency': 'TZS',
          'status': 'active',
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

  testWidgets('submits what the form shows, in one step', (
    tester,
  ) async {
    final callable = _RecordingCallable();
    final fixture = _FormFixture(callable: callable);
    await fixture.pump(tester);
    await _enterRequest(tester);

    // **One step since 2026-09-12.** There is no review to pass through and no
    // confirmation sentence to read: the form submits what it shows.
    expect(find.byKey(const ValueKey('tenant-request-confirmation')), findsNothing);
    expect(callable.payloads, isEmpty);

    await tester.tap(find.byKey(const ValueKey('tenant-request-cancel')));
    await tester.pump();
    expect(callable.payloads, isEmpty);
    expect(fixture.successes, isEmpty);

    await tester.tap(find.byKey(const ValueKey('tenant-request-submit')));
    await tester.pumpAndSettle();
    // The derived slug is still sent; it is simply never read back to somebody
    // who cannot change it. See `deriveTenantRequestSlug`.
    expect(
      (callable.payloads.single['slug']! as String).startsWith('chilltent-west-'),
      isTrue,
    );

    expect(callable.payloads.single, {
      'name': 'Chilltent West',
      // Derived from the name plus a random suffix, not typed. Asserted by
      // shape above rather than by value, because it is random by design.
      'slug': callable.payloads.single['slug'],
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
    final submit = find.byKey(const ValueKey('tenant-request-submit'));
    await tester.tap(submit);
    await tester.tap(submit);
    await tester.pump();
    expect(callable.payloads, hasLength(1));

    // The response must echo the *derived* slug, or the strict decoder
    // rejects it as another business - which is what it is there to do.
    completion.complete(
      _success(slug: callable.payloads.single['slug']! as String),
    );
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
    final confirm = find.byKey(const ValueKey('tenant-request-submit'));

    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.textContaining('sensitive'), findsNothing);
    expect(
      find.text('That business name is already taken. Try a different name.'),
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
    await tester.tap(find.byKey(const ValueKey('tenant-request-submit')));
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

TenantRequestGateway _gatewayWith(RequestTenantCallable callable) =>
    TenantRequestGateway(
      identity: _identity('user-a'),
      callable: callable,
      requestIdFactory: () => 'tenant-request-1',
    );

Map<String, Object?> _success({
  String name = 'Chilltent West',
  String slug = 'chilltent-west',
  String currency = 'TZS',
}) => {
  'tenantId': 'tenant-generated',
  'name': name,
  'slug': slug,
  'currency': currency,
  'status': 'active',
};

// ---------------------------------------------------------------------------
// The slug is derived rather than asked for
// ---------------------------------------------------------------------------

/// A fixed suffix, so a test can assert an exact slug. Production uses
/// `Random.secure()`; see `deriveTenantRequestSlug`.
String _fixedSuffix() => 'a3f9c2';

void _slugDerivationTests() {
  group('deriving a slug from the name', () {
    test('is the name, then a random suffix', () {
      expect(
        deriveTenantRequestSlug('Chilltent', suffix: _fixedSuffix),
        'chilltent-a3f9c2',
      );
    });

    test('folds spaces and punctuation into single hyphens', () {
      expect(
        deriveTenantRequestSlug("Bob & Sons' Shop", suffix: _fixedSuffix),
        'bob-sons-shop-a3f9c2',
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
        final slug = deriveTenantRequestSlug(name, suffix: _fixedSuffix);
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
      expect(deriveTenantRequestSlug('!!!', suffix: _fixedSuffix), 'shop-a3f9c2');
      expect(
        deriveTenantRequestSlug('日本語', suffix: _fixedSuffix),
        'shop-a3f9c2',
      );
    });

    test('a very long name is truncated to fit the 48-character limit', () {
      final slug = deriveTenantRequestSlug('a' * 200, suffix: _fixedSuffix);

      expect(slug.length, lessThanOrEqualTo(maximumTenantSlugLength));
      expect(slug.endsWith('-a3f9c2'), isTrue);
      expect(() => normalizeTenantRequestSlug(slug), returnsNormally);
    });

    test('truncation never leaves a hyphen against the suffix', () {
      // Cutting mid-word can land exactly on a separator, which would produce
      // the `--` the server refuses.
      final slug = deriveTenantRequestSlug(
        '${'ab ' * 40}tail',
        suffix: _fixedSuffix,
      );

      expect(slug.contains('--'), isFalse);
      expect(() => normalizeTenantRequestSlug(slug), returnsNormally);
    });

    test('two shops may share a name and still get different slugs', () {
      // The point of the change on 2026-09-12: the suffix is random, not a
      // minute stamp, so naming your shop the obvious thing is no longer a way
      // to collide with somebody who named theirs the same thing at the same
      // time.
      final slugs = <String>{
        for (var i = 0; i < 200; i++) deriveTenantRequestSlug('Chilltent'),
      };

      expect(slugs, hasLength(200));
      for (final slug in slugs) {
        expect(slug.startsWith('chilltent-'), isTrue);
        expect(() => normalizeTenantRequestSlug(slug), returnsNormally);
      }
    });

    test('the shipped suffix is hex and the server accepts it', () {
      final slug = deriveTenantRequestSlug('Chilltent');

      expect(RegExp(r'^chilltent-[0-9a-f]{6}$').hasMatch(slug), isTrue,
          reason: slug);
      expect(() => normalizeTenantRequestSlug(slug), returnsNormally);
    });
  });
}
