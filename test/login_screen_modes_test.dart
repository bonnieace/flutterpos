import 'package:flutter/material.dart';
import 'package:flutter_application_1/login_screen.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the ways out of sign in', () {
    testWidgets('both are offered, and only from sign in', (tester) async {
      await _pump(tester);

      expect(find.byKey(const ValueKey('login-go-register')), findsOneWidget);
      expect(find.byKey(const ValueKey('login-go-reset')), findsOneWidget);
      expect(find.byKey(const ValueKey('login-go-sign-in')), findsNothing);
    });

    testWidgets('the address survives a mode change and the password does not', (
      tester,
    ) async {
      // Somebody told an address is already in use is about to sign in with it,
      // and somebody who has forgotten a password is about to ask for a reset
      // for the same address. Retyping it is the one thing this must not ask.
      await _pump(tester);
      await tester.enterText(
        find.byKey(const ValueKey('login-email')),
        'owner@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('login-password')),
        'hunter22',
      );

      await _tap(tester, 'login-go-reset');

      expect(find.text('owner@example.com'), findsOneWidget);
      expect(find.text('hunter22'), findsNothing);
    });

    testWidgets('every mode can get back to sign in', (tester) async {
      await _pump(tester);

      for (final key in <String>['login-go-register', 'login-go-reset']) {
        await _tap(tester, key);
        expect(find.byKey(const ValueKey('login-go-sign-in')), findsOneWidget);
        await _tap(tester, 'login-go-sign-in');
        expect(find.byKey(const ValueKey('login-go-register')), findsOneWidget);
      }
    });
  });

  group('creating an account', () {
    testWidgets('asks for the password twice', (tester) async {
      await _pump(tester);
      await _tap(tester, 'login-go-register');

      expect(find.byKey(const ValueKey('login-password')), findsOneWidget);
      expect(find.byKey(const ValueKey('login-confirm')), findsOneWidget);
      expect(find.text('Create account'), findsOneWidget);
    });

    testWidgets('a mistyped confirmation never reaches the boundary', (
      tester,
    ) async {
      final registration = _Registration();
      await _pump(tester, registration: registration);
      await _tap(tester, 'login-go-register');
      await _fill(tester, password: 'hunter22', confirmation: 'hunter2');

      await _tap(tester, 'login-submit');

      expect(registration.attempts, isEmpty);
      expect(find.text('The two passwords are not the same.'), findsOneWidget);
    });

    testWidgets('a password under the minimum never reaches it either', (
      tester,
    ) async {
      final registration = _Registration();
      await _pump(tester, registration: registration);
      await _tap(tester, 'login-go-register');
      await _fill(tester, password: 'short', confirmation: 'short');

      await _tap(tester, 'login-submit');

      expect(registration.attempts, isEmpty);
      expect(find.textContaining('at least'), findsOneWidget);
    });

    testWidgets('a good pair reaches the boundary with a trimmed address', (
      tester,
    ) async {
      final registration = _Registration();
      await _pump(tester, registration: registration);
      await _tap(tester, 'login-go-register');
      await _fill(
        tester,
        email: '  owner@example.com  ',
        password: 'hunter22',
        confirmation: 'hunter22',
      );

      await _tapWithoutSettling(tester, 'login-submit');

      expect(registration.attempts, hasLength(1));
      expect(registration.attempts.single.email, 'owner@example.com');
      // Not trimmed: a space is a character a password may contain.
      expect(registration.attempts.single.password, 'hunter22');
    });

    testWidgets('an address already in use says what to do next', (
      tester,
    ) async {
      await _pump(
        tester,
        registration: _Registration(
          failure: const RegistrationException('email-already-in-use'),
        ),
      );
      await _tap(tester, 'login-go-register');
      await _fill(tester, password: 'hunter22', confirmation: 'hunter22');

      await _tap(tester, 'login-submit');
      await tester.pump();

      expect(find.textContaining('already uses'), findsOneWidget);
    });

    testWidgets('no raw channel error can reach the screen', (tester) async {
      // The property the boundary exists for, asserted at the screen: anything
      // that is not a `RegistrationException` becomes a written sentence.
      await _pump(
        tester,
        registration: _Registration(
          failure: StateError(
            'dev.flutter.pigeon.FirebaseAuthHostApi.createUser',
          ),
        ),
      );
      await _tap(tester, 'login-go-register');
      await _fill(tester, password: 'hunter22', confirmation: 'hunter22');

      await _tap(tester, 'login-submit');
      await tester.pump();

      expect(find.textContaining('dev.flutter.pigeon'), findsNothing);
      expect(find.textContaining('could not be created'), findsOneWidget);
    });
  });

  group('asking for a reset link', () {
    testWidgets('asks for an address and nothing else', (tester) async {
      await _pump(tester);
      await _tap(tester, 'login-go-reset');

      expect(find.byKey(const ValueKey('login-email')), findsOneWidget);
      expect(find.byKey(const ValueKey('login-password')), findsNothing);
      expect(find.byKey(const ValueKey('login-confirm')), findsNothing);
    });

    testWidgets('an empty address is refused before the server is asked', (
      tester,
    ) async {
      final callable = _ResetCallable();
      await _pump(tester, passwordReset: callable);
      await _tap(tester, 'login-go-reset');

      await _tap(tester, 'login-submit');

      expect(callable.payloads, isEmpty);
      expect(find.textContaining('Enter the email address'), findsOneWidget);
    });

    testWidgets('an accepted request promises nothing about an account', (
      tester,
    ) async {
      // The server answers identically for an address it knows and one it does
      // not, so that this endpoint cannot be used to discover who has an
      // account. The screen must not undo that.
      final callable = _ResetCallable();
      await _pump(tester, passwordReset: callable);
      await _tap(tester, 'login-go-reset');
      await _fill(tester, email: 'owner@example.com');

      await _tap(tester, 'login-submit');
      await tester.pump();

      expect(callable.payloads, hasLength(1));
      expect(
        find.byKey(const ValueKey('login-reset-accepted')),
        findsOneWidget,
      );
      expect(find.textContaining('If that address'), findsOneWidget);
    });

    testWidgets('the submit goes once the request is accepted', (tester) async {
      // Nothing left to ask for, and a live button beside "a link is on its
      // way" invites a second request the server would throttle.
      await _pump(tester, passwordReset: _ResetCallable());
      await _tap(tester, 'login-go-reset');
      await _fill(tester, email: 'owner@example.com');

      await _tap(tester, 'login-submit');
      await tester.pump();

      expect(find.byKey(const ValueKey('login-submit')), findsNothing);
      // The way back is still there.
      expect(find.byKey(const ValueKey('login-go-sign-in')), findsOneWidget);
    });

    testWidgets('a refused request is a notice, not an accepted state', (
      tester,
    ) async {
      await _pump(
        tester,
        passwordReset: _ResetCallable(
          failure: const PasswordResetCallableException('unauthenticated'),
        ),
      );
      await _tap(tester, 'login-go-reset');
      await _fill(tester, email: 'owner@example.com');

      await _tap(tester, 'login-submit');
      await tester.pump();

      expect(find.byKey(const ValueKey('login-reset-accepted')), findsNothing);
      expect(find.byKey(const ValueKey('login-notice')), findsOneWidget);
      expect(find.textContaining('could not prove itself'), findsOneWidget);
    });
  });
}

Future<void> _pump(
  WidgetTester tester, {
  EmailPasswordRegistration? registration,
  RequestPasswordResetCallable? passwordReset,
}) async {
  tester.view.physicalSize = const Size(500, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: LoginScreen(
        signIn: _SignIn(),
        registration: registration ?? _Registration(),
        passwordReset: passwordReset ?? _ResetCallable(),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

/// Taps without settling.
///
/// **A successful submit never settles, deliberately.** Both sign-in and
/// registration stay loading on success, because the routing shell replaces
/// this screen once the session opens and releasing the button first would
/// offer a second attempt against one already in flight. So the spinner is
/// still turning when the assertion runs, and `pumpAndSettle` would wait for a
/// screen that is meant never to come back.
Future<void> _tapWithoutSettling(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pump();
}

Future<void> _fill(
  WidgetTester tester, {
  String email = 'owner@example.com',
  String? password,
  String? confirmation,
}) async {
  await tester.enterText(find.byKey(const ValueKey('login-email')), email);
  if (password != null) {
    await tester.enterText(
      find.byKey(const ValueKey('login-password')),
      password,
    );
  }
  if (confirmation != null) {
    await tester.enterText(
      find.byKey(const ValueKey('login-confirm')),
      confirmation,
    );
  }
  await tester.pump();
}

final class _SignIn implements EmailPasswordSignIn {
  @override
  Future<void> call({
    required String email,
    required String password,
    required bool remember,
  }) async {}
}

final class _RegistrationAttempt {
  const _RegistrationAttempt({required this.email, required this.password});

  final String email;
  final String password;
}

final class _Registration implements EmailPasswordRegistration {
  _Registration({this.failure});

  final Object? failure;
  final List<_RegistrationAttempt> attempts = <_RegistrationAttempt>[];

  @override
  Future<void> call({required String email, required String password}) async {
    attempts.add(_RegistrationAttempt(email: email, password: password));
    final thrown = failure;
    if (thrown != null) throw thrown;
  }
}

final class _ResetCallable implements RequestPasswordResetCallable {
  _ResetCallable({this.failure});

  final Object? failure;
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(payload);
    final thrown = failure;
    if (thrown != null) throw thrown;
    return <String, Object?>{'accepted': true};
  }
}
