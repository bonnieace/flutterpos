import 'package:flutter_application_1/tenancy/account_profile.dart';
import 'package:flutter_application_1/tenancy/sign_in.dart' show SignInFailureKind;
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

  group('the round trip', () {
    test('sends a trimmed name, the phone, and one idempotency key', () {
      final complete = _CompleteCallable();
      final gateway = AccountProfileGateway(
        completeCallable: complete,
        changeEmailCallable: _ChangeEmailCallable(),
        requestIdFactory: () => 'profile-fixed-key',
      );

      gateway.completeSignup(
        displayName: '  Boniface Masota  ',
        phone: '+255712345678',
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
        gateway.completeSignup(displayName: 'Boniface', phone: '+255712345678'),
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

      expect(gateway.changeEmail('  OWNER@Example.com '), completion('owner@example.com'));
      expect(changeEmail.payloads.single['email'], 'OWNER@Example.com');
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
