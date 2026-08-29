import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('what this app refuses before asking the server', () {
    test('an empty field is named as the field it is', () {
      expect(
        registrationInputDefect(email: '', password: 'hunter22', confirmation: 'hunter22'),
        RegistrationInputDefect.missingEmail,
      );
      expect(
        registrationInputDefect(email: 'a@b.co', password: '', confirmation: ''),
        RegistrationInputDefect.missingPassword,
      );
      expect(
        registrationInputDefect(email: 'a@b.co', password: 'hunter22', confirmation: ''),
        RegistrationInputDefect.missingConfirmation,
      );
    });

    test('a mistyped confirmation is caught here and never sent', () {
      // The server never sees the second field, so this is the only place the
      // check can happen at all.
      expect(
        registrationInputDefect(
          email: 'a@b.co',
          password: 'hunter22',
          confirmation: 'hunter2',
        ),
        RegistrationInputDefect.confirmationMismatch,
      );
    });

    test('a password under the platform minimum is answered instantly', () {
      expect(
        registrationInputDefect(
          email: 'a@b.co',
          password: 'short',
          confirmation: 'short',
        ),
        RegistrationInputDefect.passwordTooShort,
      );
      // The minimum itself is met, so the server decides from here.
      expect(
        registrationInputDefect(
          email: 'a@b.co',
          password: 'six666',
          confirmation: 'six666',
        ),
        isNull,
      );
    });

    test('a password of spaces is the server\'s to judge, not this app\'s', () {
      // The same rule sign-in takes: a space is a character a password may
      // contain, and only its absence is something this app knows is wrong.
      expect(
        registrationInputDefect(
          email: 'a@b.co',
          password: '      ',
          confirmation: '      ',
        ),
        isNull,
      );
    });

    test('every defect has a sentence', () {
      for (final defect in RegistrationInputDefect.values) {
        expect(registrationInputDefectMessage(defect), isNotEmpty);
      }
    });
  });

  group('what the server refused', () {
    test('an address already in use says so, and says what to do next', () {
      // Deliberately not collapsed the way sign-in collapses a bad credential:
      // Firebase discloses this code itself even with enumeration protection
      // on, and refusing to explain would leave somebody with no way forward.
      final failure = registrationFailure(
        const RegistrationException('email-already-in-use'),
      );

      expect(failure.kind, SignInFailureKind.refused);
      expect(failure.message, contains('already uses'));
      expect(failure.message, contains('Sign in'));
    });

    test('an unreachable server is not a refusal', () {
      final failure = registrationFailure(
        const RegistrationException('network-request-failed'),
      );

      expect(failure.kind, SignInFailureKind.unreachable);
    });

    test('a blocked creation names no cause', () {
      // `bootstrapSelfSignupIdentity` aborts creation by throwing, and the
      // client is handed a generic code rather than the reason. What matters is
      // that no account was made, which the sentence conveys without guessing.
      for (final code in <String>[
        'internal-error',
        'blocking-function-error-response',
      ]) {
        final failure = registrationFailure(RegistrationException(code));
        expect(failure.kind, SignInFailureKind.refused);
        expect(failure.message, contains('could not be set up'));
      }
    });

    test('nothing this app did not write can reach a person', () {
      // The property the whole boundary exists for: anything that is not a
      // `RegistrationException` - a platform channel error, a plugin defect -
      // answers with the written fallback rather than printing itself.
      for (final error in <Object>[
        StateError('dev.flutter.pigeon.FirebaseAuthHostApi.createUser'),
        'a bare string',
        Exception('raw'),
      ]) {
        expect(
          registrationFailure(error).message,
          contains('could not be created'),
        );
      }
    });

    test('an unrecognised code is a refusal rather than an open question', () {
      final failure = registrationFailure(
        const RegistrationException('some-code-firebase-added-later'),
      );

      expect(failure.kind, SignInFailureKind.refused);
      expect(failure.message, isNotEmpty);
    });

    test('the sentence helper agrees with the failure it summarises', () {
      const error = RegistrationException('weak-password');

      expect(registrationSafeError(error), registrationFailure(error).message);
    });
  });
}
