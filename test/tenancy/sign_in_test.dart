import 'package:flutter/services.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

/// The channel the Firebase Auth plugin signs in over.
///
/// Named here rather than described, because the assertion this file exists for
/// is that this string never reaches a user, and an assertion against a
/// paraphrase would prove nothing.
const String _signInChannel =
    'dev.flutter.pigeon.firebase_auth_platform_interface'
    '.FirebaseAuthHostApi.signInWithEmailAndPassword';

/// Exactly what the plugin's generated `_createConnectionError` throws when the
/// host side of that channel fails, copied from
/// `firebase_auth_platform_interface/lib/src/pigeon/messages.pigeon.dart`.
///
/// Submitting an empty password produced this, and the old screen rendered its
/// `message`. The tail of that message — the channel name in quotes, followed by
/// a full stop — is the string recorded verbatim from the device.
PlatformException _channelFailure() => PlatformException(
  code: 'channel-error',
  message: 'Unable to establish connection on channel: "$_signInChannel".',
);

void main() {
  group('what the form itself can refuse', () {
    test('an empty password is a defect, so it is never sent', () {
      expect(
        signInInputDefect(email: 'owner@example.com', password: ''),
        SignInInputDefect.missingPassword,
      );
    });

    test('an empty address is a defect', () {
      expect(
        signInInputDefect(email: '', password: 'correct horse'),
        SignInInputDefect.missingEmail,
      );
    });

    test('an address of only whitespace is empty', () {
      expect(
        signInInputDefect(email: '   \t ', password: 'correct horse'),
        SignInInputDefect.missingEmail,
      );
    });

    test('the address is judged before the password', () {
      expect(
        signInInputDefect(email: '', password: ''),
        SignInInputDefect.missingEmail,
      );
    });

    test('a password of only whitespace is the server\'s to judge', () {
      // Spaces are characters a password may contain. The only thing this app
      // knows is wrong is a password that is not there at all.
      expect(signInInputDefect(email: 'owner@example.com', password: '   '), isNull);
    });

    test('a credential with both halves has no defect', () {
      expect(
        signInInputDefect(email: ' owner@example.com ', password: 'a'),
        isNull,
      );
    });

    test('each defect names the field it is about', () {
      expect(
        signInInputDefectMessage(SignInInputDefect.missingEmail),
        'Enter the email address for this account.',
      );
      expect(
        signInInputDefectMessage(SignInInputDefect.missingPassword),
        'Enter the password for this account.',
      );
    });
  });

  group('a failure becomes a sentence somebody wrote', () {
    test('the platform channel failure renders no channel name', () {
      final message = signInSafeError(_channelFailure());

      expect(message, isNot(contains('dev.flutter.pigeon')));
      expect(message, isNot(contains(_signInChannel)));
      expect(message, isNot(contains('channel')));
      expect(
        message,
        'Sign-in could not be completed. Try again, and contact support if it '
        'keeps happening.',
      );
    });

    test('anything at all that is not a SignInException is a sentence', () {
      // The bug class is "the error is a string nobody wrote", not the one code
      // that produced it, so the boundary is the type rather than a list.
      final unknown = <Object>[
        _channelFailure(),
        PlatformException(code: 'null-error', message: _signInChannel),
        StateError(_signInChannel),
        const FormatException(_signInChannel),
        _signInChannel,
        Exception(_signInChannel),
      ];

      for (final error in unknown) {
        expect(
          signInSafeError(error),
          'Sign-in could not be completed. Try again, and contact support if it '
          'keeps happening.',
          reason: '$error must not reach a user',
        );
      }
    });

    test('a wrong password, an unknown address, and a malformed credential are '
        'one sentence', () {
      const codes = <String>[
        'wrong-password',
        'user-not-found',
        'invalid-credential',
        'invalid-login-credentials',
        'INVALID_LOGIN_CREDENTIALS',
      ];
      final answers = codes
          .map((code) => signInSafeError(SignInException(code)))
          .toSet();

      expect(answers, hasLength(1));
      expect(
        answers.single,
        'That email address and password do not match an account. Check both '
        'and try again.',
      );
    });

    test('the codes a user can act on are named individually', () {
      expect(
        signInSafeError(const SignInException('invalid-email')),
        'That is not a valid email address. Check it and try again.',
      );
      expect(
        signInSafeError(const SignInException('user-disabled')),
        'This account has been disabled. Contact your administrator.',
      );
      expect(
        signInSafeError(const SignInException('too-many-requests')),
        'Too many sign-in attempts from this device. Wait a few minutes and '
        'try again.',
      );
      expect(
        signInSafeError(const SignInException('network-request-failed')),
        'This device could not reach the server. Check the connection and try '
        'again.',
      );
      expect(
        signInSafeError(const SignInException('operation-not-allowed')),
        'Signing in with an email address and password is not enabled for this '
        'app. Contact support.',
      );
    });

    test('a missing half is worded the same whoever noticed it', () {
      expect(
        signInSafeError(const SignInException('missing-email')),
        signInInputDefectMessage(SignInInputDefect.missingEmail),
      );
      expect(
        signInSafeError(const SignInException('missing-password')),
        signInInputDefectMessage(SignInInputDefect.missingPassword),
      );
    });

    test('an unrecognised code falls back without naming a cause', () {
      final message = signInSafeError(const SignInException('a-new-code'));

      expect(message, isNot(contains('password')));
      expect(
        message,
        'Sign-in could not be completed. Try again, and contact support if it '
        'keeps happening.',
      );
    });

    test('a code that is itself the channel name is still answered safely', () {
      // The adapter copies the provider's code across verbatim, so nothing
      // stops a future plugin from putting a channel name in one.
      expect(
        signInSafeError(SignInException(_signInChannel)),
        isNot(contains('dev.flutter.pigeon')),
      );
    });

    test('every answer is a sentence', () {
      const codes = <String>[
        'invalid-email',
        'missing-email',
        'missing-password',
        'user-disabled',
        'too-many-requests',
        'network-request-failed',
        'operation-not-allowed',
        'wrong-password',
        'user-not-found',
        'invalid-credential',
        'invalid-login-credentials',
        'INVALID_LOGIN_CREDENTIALS',
        'internal-error',
        '',
      ];

      for (final code in codes) {
        final message = signInSafeError(SignInException(code));
        expect(message, isNotEmpty, reason: code);
        expect(message, endsWith('.'), reason: code);
        expect(message[0], message[0].toUpperCase(), reason: code);
        expect(message, isNot(contains('dev.flutter.pigeon')), reason: code);
      }
    });
  });

  group('a failure also says what kind of answer it is', () {
    // §11 step 9. The screen painted every one of these red, so "this device
    // has no connection" and "that password is wrong" were the same sentence in
    // the same colour on the first screen of the app.

    test('the one that is not a refusal is the one that never arrived', () {
      // The whole reason `SignInFailureKind` has two values. Nothing was
      // refused, because nothing was answered.
      expect(
        signInFailure(const SignInException('network-request-failed')).kind,
        SignInFailureKind.unreachable,
      );
    });

    test('every other named code is a refusal', () {
      const refusals = <String>[
        'invalid-email',
        'missing-email',
        'missing-password',
        'user-disabled',
        'too-many-requests',
        'operation-not-allowed',
        'wrong-password',
        'user-not-found',
        'invalid-credential',
        'invalid-login-credentials',
        'INVALID_LOGIN_CREDENTIALS',
      ];

      for (final code in refusals) {
        expect(
          signInFailure(SignInException(code)).kind,
          SignInFailureKind.refused,
          reason: code,
        );
      }
    });

    test('a failure nobody can name is refused, not left open', () {
      // The cause is unknown; the outcome is not. §2.1's `attention` means
      // "awaiting", and nothing is awaiting - the screen is still here.
      for (final error in <Object>[
        _channelFailure(),
        const SignInException('a-new-code'),
        StateError(_signInChannel),
        _signInChannel,
      ]) {
        expect(
          signInFailure(error).kind,
          SignInFailureKind.refused,
          reason: '$error',
        );
      }
    });

    test('the sentence is the same one, from one switch rather than two', () {
      // The property that makes the kind safe to add: there is no second table
      // over the same codes for the two to disagree in.
      const codes = <String>[
        'invalid-email',
        'missing-email',
        'missing-password',
        'user-disabled',
        'too-many-requests',
        'network-request-failed',
        'operation-not-allowed',
        'wrong-password',
        'a-new-code',
        '',
      ];

      for (final code in codes) {
        final error = SignInException(code);
        expect(signInFailure(error).message, signInSafeError(error), reason: code);
      }
      expect(
        signInFailure(_channelFailure()).message,
        signInSafeError(_channelFailure()),
      );
    });

    test('two readings of one failure are equal', () {
      expect(
        signInFailure(const SignInException('user-disabled')),
        signInFailure(const SignInException('user-disabled')),
      );
      expect(
        signInFailure(const SignInException('user-disabled')).hashCode,
        signInFailure(const SignInException('user-disabled')).hashCode,
      );
      expect(
        signInFailure(const SignInException('network-request-failed')),
        isNot(signInFailure(const SignInException('user-disabled'))),
      );
    });
  });

  test('the boundary carries a code and nothing else', () {
    expect(
      const SignInException('wrong-password').toString(),
      'SignInException(wrong-password)',
    );
  });
}
