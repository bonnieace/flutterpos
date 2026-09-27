import 'package:uzapay_pos/tenancy/account_profile.dart';
import 'package:uzapay_pos/tenancy/sign_in.dart' show SignInFailureKind;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('what this app refuses before asking the server', () {
    test('an empty name is named as missing', () {
      expect(accountNameDefect('   '), AccountProfileInputDefect.missingName);
    });

    test('a one-character name is too short', () {
      expect(accountNameDefect('B'), AccountProfileInputDefect.nameTooShort);
    });

    test('an over-long name is refused with its own sentence', () {
      expect(
        accountNameDefect('B' * (maximumAccountNameLength + 1)),
        AccountProfileInputDefect.nameTooLong,
      );
      expect(
        accountProfileInputDefectMessage(
          AccountProfileInputDefect.nameTooLong,
        ),
        contains('$maximumAccountNameLength'),
      );
    });

    test('an ordinary name has nothing wrong with it', () {
      expect(accountNameDefect('  Boniface Masota  '), isNull);
    });
  });

  // **H3, both halves.** The client holds one key for the attempt, and the
  // server reads its own record before the guard that would refuse a replay of
  // its own work. Either alone leaves the defect standing, which is what the
  // middle two tests pin.
  //
  // Every other test in this file injects a constant `requestIdFactory`. That
  // hands the gateway a stability the real one used to lack, and is why the
  // suite never caught this - so the test that matters most here injects
  // nothing and runs the shipped generator.
  group('an ambiguous timeout while changing a mistaken address', () {
    test('one intent, reused, reconciles to the change that worked', () async {
      final server = _ReplayAwareChangeEmailCallable(
        currentEmail: 'typo@example.com',
        replayBeforePrecondition: true,
      )..loseNextResponse = true;
      var minted = 0;
      final gateway = AccountProfileGateway(
        completeCallable: _CompleteCallable(),
        changeEmailCallable: server,
        requestIdFactory: () => 'profile-key-${++minted}',
      );

      // What the person did once, and what the flow holds for its retries.
      final intent = gateway.createAddressChangeIntent('owner@example.com');

      // The attempt. The server applies it and the reply is lost.
      await expectLater(
        gateway.changeEmail(intent),
        throwsA(isA<AccountProfileException>()),
      );
      expect(server.currentEmail, 'owner@example.com');

      // The same person, pressing the same button again, on the same intent.
      final change = await gateway.changeEmail(intent);

      expect(change.email, 'owner@example.com');
      expect(minted, 1, reason: 'One attempt is one key.');
      expect(server.payloads.map((p) => p['requestId']).toSet(), hasLength(1));
    });

    test('the shipped generator is stable across a retry of one intent', () async {
      final server = _ReplayAwareChangeEmailCallable(
        currentEmail: 'typo@example.com',
        replayBeforePrecondition: true,
      )..loseNextResponse = true;
      // No injected factory: this is `_secureAccountProfileRequestId`, which is
      // what ships. A constant factory would prove nothing here.
      final gateway = AccountProfileGateway(
        completeCallable: _CompleteCallable(),
        changeEmailCallable: server,
      );
      final intent = gateway.createAddressChangeIntent('owner@example.com');

      await expectLater(
        gateway.changeEmail(intent),
        throwsA(isA<AccountProfileException>()),
      );
      await gateway.changeEmail(intent);

      expect(server.payloads.map((p) => p['requestId']).toSet(), hasLength(1));
    });

    test('a new intent per retry is refused, which is why one is held', () async {
      final server = _ReplayAwareChangeEmailCallable(
        currentEmail: 'typo@example.com',
        replayBeforePrecondition: true,
      )..loseNextResponse = true;
      final gateway = AccountProfileGateway(
        completeCallable: _CompleteCallable(),
        changeEmailCallable: server,
      );

      await expectLater(
        gateway.changeEmail(gateway.createAddressChangeIntent('owner@example.com')),
        throwsA(isA<AccountProfileException>()),
      );

      Object? raised;
      try {
        // A second intent is a second attempt, and the server has never seen it.
        await gateway.changeEmail(
          gateway.createAddressChangeIntent('owner@example.com'),
        );
      } catch (error) {
        raised = error;
      }

      expect((raised! as AccountProfileException).code, 'failed-precondition');
      expect(
        accountProfileFailure(raised).message,
        'That address cannot be changed here.',
        reason:
            'The sentence the person used to be shown for a change that had '
            'already worked. Holding the intent is what stops it.',
      );
    });

    test('a held intent alone is not enough: the server must peek first', () async {
      // The deployed ordering before this change - guard ahead of the replay.
      final server = _ReplayAwareChangeEmailCallable(
        currentEmail: 'typo@example.com',
      )..loseNextResponse = true;
      final gateway = AccountProfileGateway(
        completeCallable: _CompleteCallable(),
        changeEmailCallable: server,
      );
      final intent = gateway.createAddressChangeIntent('owner@example.com');

      await expectLater(
        gateway.changeEmail(intent),
        throwsA(isA<AccountProfileException>()),
      );

      Object? raised;
      try {
        await gateway.changeEmail(intent);
      } catch (error) {
        raised = error;
      }

      expect(server.payloads.map((p) => p['requestId']).toSet(), hasLength(1));
      expect(
        (raised! as AccountProfileException).code,
        'failed-precondition',
        reason:
            'One key, and still refused. This is the server half: without the '
            'peek in `changeSignupEmail`, the guard throws before the recorded '
            'replay is ever read, and the client fix buys nothing.',
      );
    });

    test('a different address mints a different key', () async {
      final server = _ReplayAwareChangeEmailCallable(
        currentEmail: 'typo@example.com',
        replayBeforePrecondition: true,
      );
      final gateway = AccountProfileGateway(
        completeCallable: _CompleteCallable(),
        changeEmailCallable: server,
      );

      await gateway.changeEmail(
        gateway.createAddressChangeIntent('first@example.com'),
      );
      await gateway.changeEmail(
        gateway.createAddressChangeIntent('second@example.com'),
      );

      expect(server.currentEmail, 'second@example.com');
      expect(
        server.payloads.map((p) => p['requestId']).toSet(),
        hasLength(2),
        reason:
            'A re-typed address is a different attempt. Reusing the key would '
            'make the server answer for the address it recorded, not this one.',
      );
    });
  });

  group('the round trip', () {
    test('sends a trimmed name, the phone, and one idempotency key', () {
      final complete = _CompleteCallable();
      final gateway = AccountProfileGateway(
        completeCallable: complete,
        changeEmailCallable: _ChangeEmailCallable(),
        requestIdFactory: () => 'profile-fixed-key',
      );

      gateway.completeSignup(
        gateway.createSignupIntent(displayName: '  Boniface Masota  ', phone: '+255712345678'),
      );

      expect(complete.payloads.single, <String, Object?>{
        'displayName': 'Boniface Masota',
        'phone': '+255712345678',
        'requestId': 'profile-fixed-key',
      });
    });

    test('a response missing a field is a format failure, not a silent pass', () {
      final gateway = AccountProfileGateway(
        completeCallable: _CompleteCallable(response: <String, Object?>{}),
        changeEmailCallable: _ChangeEmailCallable(),
      );

      expect(
        gateway.completeSignup(
        gateway.createSignupIntent(displayName: 'Boniface', phone: '+255712345678'),
      ),
        throwsA(isA<FormatException>()),
      );
    });

    test('the changed address comes back from the server, not from the field', () {
      // The server normalizes; echoing what was typed would let the client and
      // the Auth record disagree about the same address.
      final changeEmail = _ChangeEmailCallable(
        response: <String, Object?>{'email': 'owner@example.com'},
      );
      final gateway = AccountProfileGateway(
        completeCallable: _CompleteCallable(),
        changeEmailCallable: changeEmail,
        requestIdFactory: () => 'profile-fixed-key',
      );

      expect(
        gateway.changeEmail(gateway.createAddressChangeIntent('  OWNER@Example.com ')),
        completion(
          isA<AccountAddressChange>()
              .having((c) => c.email, 'email', 'owner@example.com')
              // A server that minted nothing sends no field at all, which is a
              // documented outcome rather than a malformed reply.
              .having((c) => c.sessionToken, 'sessionToken', isNull),
        ),
      );
      expect(changeEmail.payloads.single['email'], 'OWNER@Example.com');
    });

    test('a minted session is carried back with the address', () {
      // The address change rebinds the password credential and kills the
      // refresh token on the device. This is the replacement the flow exchanges
      // before that lands, so it has to survive the round trip.
      final changeEmail = _ChangeEmailCallable(
        response: <String, Object?>{
          'email': 'owner@example.com',
          'sessionToken': 'custom-token-abc',
        },
      );
      final gateway = AccountProfileGateway(
        completeCallable: _CompleteCallable(),
        changeEmailCallable: changeEmail,
        requestIdFactory: () => 'profile-fixed-key',
      );

      expect(
        gateway.changeEmail(gateway.createAddressChangeIntent('owner@example.com')),
        completion(
          isA<AccountAddressChange>().having(
            (c) => c.sessionToken,
            'sessionToken',
            'custom-token-abc',
          ),
        ),
      );
    });

    test('an empty token is read as no token at all', () {
      // Defensive rather than asserted: an empty string is not a credential,
      // and treating it as one would have the flow exchange nothing and call
      // the failure a success.
      final changeEmail = _ChangeEmailCallable(
        response: <String, Object?>{'email': 'owner@example.com', 'sessionToken': ''},
      );
      final gateway = AccountProfileGateway(
        completeCallable: _CompleteCallable(),
        changeEmailCallable: changeEmail,
        requestIdFactory: () => 'profile-fixed-key',
      );

      expect(
        gateway.changeEmail(gateway.createAddressChangeIntent('owner@example.com')),
        completion(
          isA<AccountAddressChange>()
              .having((c) => c.sessionToken, 'sessionToken', isNull),
        ),
      );
    });
  });

  group('turning a code into a sentence', () {
    test('an unreachable server is not the person\'s fault', () {
      for (final code in <String>['unavailable', 'deadline-exceeded']) {
        final failure = accountProfileFailure(AccountProfileException(code));
        expect(failure.kind, SignInFailureKind.unreachable, reason: code);
        expect(failure.message, contains('could not be reached'));
      }
    });

    test('a missing callable says the server is behind, not "went wrong"', () {
      // Seen on a device on 2026-09-02: the app shipped ahead of the backend,
      // the callable answered `not-found`, and the flow showed the one sentence
      // that tells neither the person nor support anything.
      final failure = accountProfileFailure(
        const AccountProfileException('not-found'),
      );
      expect(failure.kind, SignInFailureKind.unreachable);
      expect(failure.message, contains('newer than the server'));
    });

    test('a taken address points at signing in instead', () {
      final failure = accountProfileFailure(
        const AccountProfileException('already-exists'),
      );
      expect(failure.kind, SignInFailureKind.refused);
      expect(failure.message, contains('signing in'));
    });

    test('no sentence ever repeats the raw code', () {
      for (final code in <String>[
        'unauthenticated',
        'already-exists',
        'invalid-argument',
        'resource-exhausted',
        'failed-precondition',
        'permission-denied',
        'not-found',
        'internal',
      ]) {
        final failure = accountProfileFailure(AccountProfileException(code));
        expect(failure.message, isNot(contains(code)), reason: code);
        expect(failure.message, isNotEmpty);
      }
    });

    test('anything that is not one of ours still gets a sentence', () {
      final failure = accountProfileFailure(StateError('boom'));
      expect(failure.kind, SignInFailureKind.refused);
      expect(failure.message, isNotEmpty);
    });
  });
}

final class _CompleteCallable implements CompleteSelfSignupCallable {
  _CompleteCallable({this.response});

  final Map<String, Object?>? response;
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(Map<String, Object?>.from(payload));
    return response ??
        <String, Object?>{
          'displayName': payload['displayName'],
          'phone': payload['phone'],
        };
  }
}

final class _ChangeEmailCallable implements ChangeSignupEmailCallable {
  _ChangeEmailCallable({this.response});

  final Map<String, Object?>? response;
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(Map<String, Object?>.from(payload));
    return response ?? <String, Object?>{'email': payload['email']};
  }
}

/// `changeSignupEmail` as the server actually behaves, replay cache included.
///
/// Modelled on `functions/src/auth/selfSignupProfile.ts`:
///
/// - a `requestId` seen before returns the recorded answer, which is the whole
///   point of the key;
/// - an address that is already the account's current one is refused with
///   `failed-precondition` - see `selfSignupProfile.ts:327`;
/// - otherwise the address moves and the answer is recorded against the key.
///
/// [loseNextResponse] drops the reply *after* the change has been applied,
/// which is the ambiguous timeout H3 is about.
///
/// **[replayBeforePrecondition] is the whole of the server-side half.** It is
/// now true of the deployed callable, and false models what shipped before.
///
/// The old order was precondition first: `caller.identity` is read live from the
/// Auth record (`getAuth().getUser`, `selfSignupProfile.ts:91`), so on a retry it
/// already holds the new address and the guard threw before
/// `runIdempotentFirestoreTransaction` was ever reached - a stable key bought
/// nothing on its own. `changeSignupEmail` now peeks for a completed record under
/// the same request id and input first, and runs the guard only when there is
/// none. False is kept so one test can still say why the server half was needed.
final class _ReplayAwareChangeEmailCallable
    implements ChangeSignupEmailCallable {
  _ReplayAwareChangeEmailCallable({
    required this.currentEmail,
    this.replayBeforePrecondition = false,
  });

  String currentEmail;
  final bool replayBeforePrecondition;
  bool loseNextResponse = false;

  final Map<String, Map<String, Object?>> _recorded =
      <String, Map<String, Object?>>{};
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(Map<String, Object?>.from(payload));
    final requestId = payload['requestId']! as String;
    final requested = (payload['email']! as String).trim();

    if (replayBeforePrecondition) {
      final replayed = _recorded[requestId];
      if (replayed != null) return replayed;
    }

    // `selfSignupProfile.ts:327`, which now stands down for a replay.
    if (requested.toLowerCase() == currentEmail.toLowerCase()) {
      throw const AccountProfileException('failed-precondition');
    }

    if (!replayBeforePrecondition) {
      final replayed = _recorded[requestId];
      if (replayed != null) return replayed;
    }

    currentEmail = requested;
    final answer = <String, Object?>{'email': requested};
    _recorded[requestId] = answer;

    if (loseNextResponse) {
      loseNextResponse = false;
      throw const AccountProfileException('unavailable');
    }
    return answer;
  }
}
