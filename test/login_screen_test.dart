import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/login_screen.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/tokens.dart';
import 'package:flutter_application_1/widgets/pos_keyboard.dart';
import 'package:flutter_test/flutter_test.dart';

/// The channel the Firebase Auth plugin signs in over.
///
/// The whole point of this file is that this string never reaches the screen, so
/// it is spelled out rather than described.
const String _signInChannel =
    'dev.flutter.pigeon.firebase_auth_platform_interface'
    '.FirebaseAuthHostApi.signInWithEmailAndPassword';

/// What the plugin throws when the host side of that channel fails, which is
/// what an empty password reached before this screen refused one.
PlatformException _channelFailure() => PlatformException(
  code: 'channel-error',
  message: 'Unable to establish connection on channel: "$_signInChannel".',
);

const String _unknownFailure =
    'Sign-in could not be completed. Try again, and contact support if it '
    'keeps happening.';

void main() {
  testWidgets('an empty password is refused without being sent', (tester) async {
    final signIn = _SignIn();
    await _pump(tester, signIn);

    await tester.enterText(_field('login-email'), 'owner@example.com');
    await _submit(tester);

    expect(signIn.attempts, isEmpty);
    expect(_error(tester), 'Enter the password for this account.');
  });

  testWidgets('an empty address is refused without being sent', (tester) async {
    final signIn = _SignIn();
    await _pump(tester, signIn);

    await tester.enterText(_field('login-password'), 'correct horse');
    await _submit(tester);

    expect(signIn.attempts, isEmpty);
    expect(_error(tester), 'Enter the email address for this account.');
  });

  testWidgets('an address of only spaces is refused', (tester) async {
    final signIn = _SignIn();
    await _pump(tester, signIn);

    await tester.enterText(_field('login-email'), '    ');
    await tester.enterText(_field('login-password'), 'correct horse');
    await _submit(tester);

    expect(signIn.attempts, isEmpty);
    expect(_error(tester), 'Enter the email address for this account.');
  });

  testWidgets('a refusal by this form leaves the button usable', (tester) async {
    final signIn = _SignIn();
    await _pump(tester, signIn);

    await tester.enterText(_field('login-email'), 'owner@example.com');
    await _submit(tester);
    expect(_error(tester), isNotNull);

    // Nothing was sent, so nothing is in flight, and a second attempt after
    // typing a password must be possible without leaving the screen.
    await tester.enterText(_field('login-password'), 'correct horse');
    await _submit(tester);

    expect(signIn.attempts, hasLength(1));
  });

  testWidgets('a platform channel failure renders a sentence, never itself', (
    tester,
  ) async {
    final signIn = _SignIn(failure: _channelFailure());
    await _pump(tester, signIn);

    await _signInAs(tester, 'owner@example.com', 'correct horse');

    // The assertion that would have caught this in 2026-08-04: no string on
    // screen anywhere is one that nobody wrote.
    expect(
      _renderedText(tester).where((text) => text.contains('dev.flutter.pigeon')),
      isEmpty,
    );
    expect(
      _renderedText(tester).where((text) => text.contains(_signInChannel)),
      isEmpty,
    );
    expect(_error(tester), _unknownFailure);
  });

  testWidgets('an error of any other shape renders a sentence too', (
    tester,
  ) async {
    for (final failure in <Object>[
      StateError(_signInChannel),
      const FormatException(_signInChannel),
      Exception(_signInChannel),
    ]) {
      final signIn = _SignIn(failure: failure);
      await _pump(tester, signIn);

      await _signInAs(tester, 'owner@example.com', 'correct horse');

      expect(
        _renderedText(
          tester,
        ).where((text) => text.contains('dev.flutter.pigeon')),
        isEmpty,
        reason: '$failure',
      );
      expect(_error(tester), _unknownFailure, reason: '$failure');
    }
  });

  testWidgets('a refused credential names the credential', (tester) async {
    final signIn = _SignIn(failure: const SignInException('invalid-credential'));
    await _pump(tester, signIn);

    await _signInAs(tester, 'owner@example.com', 'wrong horse');

    expect(
      _error(tester),
      'That email address and password do not match an account. Check both and '
      'try again.',
    );
  });

  testWidgets('a failure releases the button so it can be tried again', (
    tester,
  ) async {
    final signIn = _SignIn(failure: const SignInException('invalid-credential'));
    await _pump(tester, signIn);

    await _signInAs(tester, 'owner@example.com', 'wrong horse');
    await tester.enterText(_field('login-password'), 'correct horse');
    await _submit(tester);

    expect(signIn.attempts, hasLength(2));
  });

  testWidgets('editing the address clears the error it describes', (
    tester,
  ) async {
    final signIn = _SignIn(failure: const SignInException('invalid-credential'));
    await _pump(tester, signIn);

    await _signInAs(tester, 'owner@example.com', 'wrong horse');
    expect(_error(tester), isNotNull);

    await tester.enterText(_field('login-email'), 'owner@example.co');
    await tester.pump();

    expect(_error(tester), isNull);
  });

  testWidgets('editing the password clears the error it describes', (
    tester,
  ) async {
    final signIn = _SignIn(failure: const SignInException('invalid-credential'));
    await _pump(tester, signIn);

    await _signInAs(tester, 'owner@example.com', 'wrong horse');
    expect(_error(tester), isNotNull);

    await tester.enterText(_field('login-password'), 'correct horse');
    await tester.pump();

    expect(_error(tester), isNull);
  });

  testWidgets('a refusal this form made is cleared by editing too', (
    tester,
  ) async {
    final signIn = _SignIn();
    await _pump(tester, signIn);

    await tester.enterText(_field('login-email'), 'owner@example.com');
    await _submit(tester);
    expect(_error(tester), 'Enter the password for this account.');

    await tester.enterText(_field('login-password'), 'c');
    await tester.pump();

    expect(_error(tester), isNull);
  });

  testWidgets('moving the cursor is not editing, and keeps the error', (
    tester,
  ) async {
    final signIn = _SignIn(failure: const SignInException('invalid-credential'));
    await _pump(tester, signIn);

    await _signInAs(tester, 'owner@example.com', 'wrong horse');
    expect(_error(tester), isNotNull);

    // A TextEditingController notifies on a selection change as well as a text
    // change. Revealing the password moves the cursor and answers nothing the
    // refusal said, so the refusal must survive it.
    tester
        .widget<TextField>(_field('login-password'))
        .controller!
        .selection = const TextSelection(baseOffset: 0, extentOffset: 3);
    await tester.pump();
    expect(_error(tester), isNotNull);

    await tester.tap(find.byIcon(Icons.visibility_off));
    await tester.pump();
    expect(_error(tester), isNotNull);
  });

  testWidgets('the address is trimmed and the password is not', (tester) async {
    final signIn = _SignIn();
    await _pump(tester, signIn);

    await _signInAs(tester, '  owner@example.com  ', ' correct horse ');

    expect(signIn.attempts.single.email, 'owner@example.com');
    expect(signIn.attempts.single.password, ' correct horse ');
    expect(signIn.attempts.single.remember, isTrue);
  });

  testWidgets('the remember choice reaches the boundary', (tester) async {
    final signIn = _SignIn();
    await _pump(tester, signIn);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await _signInAs(tester, 'owner@example.com', 'correct horse');

    expect(signIn.attempts.single.remember, isFalse);
  });

  testWidgets('a sign-in in flight is not started twice', (tester) async {
    final signIn = _SignIn()..gate = Completer<void>();
    await _pump(tester, signIn);

    await _signInAs(tester, 'owner@example.com', 'correct horse');
    expect(signIn.attempts, hasLength(1));
    expect(_error(tester), isNull);

    await _submit(tester);
    expect(signIn.attempts, hasLength(1));

    signIn.gate!.complete();
    await tester.pump();
    await tester.pump();

    // Still busy, deliberately: the routing shell replaces this screen once the
    // session opens, and releasing the button first offers a second sign-in
    // against a session that is already being built.
    expect(_error(tester), isNull);
    expect(find.byType(CircularProgressIndicator), findsOne);
  });

  testWidgets('a build with no boundary renders without reaching Firebase', (
    tester,
  ) async {
    await _pump(tester, null);

    expect(find.byKey(const ValueKey('login-submit')), findsOne);
    expect(_error(tester), isNull);
  });

  group('the screen splits at §4.1\'s medium floor, and nowhere else', () {
    // **Step 6's rewiring, from the outside.** `isMobile` was `width < 768`
    // with a comment - the third of three declarations of that boundary, and
    // the only one that was not even a named constant. It reads `AppLayout`
    // now. These pin the behaviour to the declared floor rather than to 768,
    // so a future move of §4.1's number moves this screen with it. **Nothing
    // about sign-in's visual design is asserted here**: that is step 9's, and
    // the on-screen keyboard is only the cheapest observable difference
    // between the two branches.

    testWidgets('one pixel below it, the desktop keyboard is absent', (
      tester,
    ) async {
      await _pumpAt(tester, AppLayout.contract.mediumFloor - 1);
      expect(find.byType(PosKeyboard), findsNothing);
    });

    testWidgets('at it, the desktop keyboard is drawn', (tester) async {
      await _pumpAt(tester, AppLayout.contract.mediumFloor);
      expect(find.byType(PosKeyboard), findsOneWidget);
    });

    testWidgets('the boundary is the one §4.1 declares, not a literal', (
      tester,
    ) async {
      // The claim the step actually makes. If `AppLayout.mediumFloor` moved and
      // this screen kept its own 768, one of the two tests above would still
      // pass and the app would have two boundaries again.
      expect(AppLayout.contract.mediumFloor, 768);
      expect(
        AppLayout.contract.breakpointOf(AppLayout.contract.mediumFloor - 1),
        AppBreakpoint.compact,
      );
      expect(
        AppLayout.contract.breakpointOf(AppLayout.contract.mediumFloor),
        AppBreakpoint.medium,
      );
    });
  });
}

/// Pumps sign-in at an exact width, for the two cases either side of §4.1's
/// `medium` floor.
///
/// Tall enough that the desktop branch's two panes both lay out; the narrow
/// branch is the one `_pump` above already covers for every other test here.
Future<void> _pumpAt(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(home: LoginScreen(signIn: _SignIn())));
  await tester.pump();
}

Future<void> _pump(WidgetTester tester, EmailPasswordSignIn? signIn) async {
  // Narrow enough for the screen's own mobile branch, tall enough that nothing
  // needs scrolling into view before it can be tapped.
  tester.view.physicalSize = const Size(500, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(home: LoginScreen(signIn: signIn)));
  await tester.pump();
}

Finder _field(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(TextField),
);

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('login-submit')));
  await tester.pump();
}

Future<void> _signInAs(
  WidgetTester tester,
  String email,
  String password,
) async {
  await tester.enterText(_field('login-email'), email);
  await tester.enterText(_field('login-password'), password);
  await _submit(tester);
}

String? _error(WidgetTester tester) {
  final finder = find.byKey(const ValueKey('login-error'));
  if (finder.evaluate().isEmpty) return null;
  return tester.widget<Text>(finder).data;
}

Iterable<String> _renderedText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((text) => text.data)
    .whereType<String>();

final class _Attempt {
  const _Attempt({
    required this.email,
    required this.password,
    required this.remember,
  });

  final String email;
  final String password;
  final bool remember;
}

final class _SignIn implements EmailPasswordSignIn {
  _SignIn({this.failure});

  final Object? failure;
  final List<_Attempt> attempts = <_Attempt>[];
  Completer<void>? gate;

  @override
  Future<void> call({
    required String email,
    required String password,
    required bool remember,
  }) async {
    attempts.add(
      _Attempt(email: email, password: password, remember: remember),
    );
    final held = gate;
    if (held != null) await held.future;
    final thrown = failure;
    if (thrown != null) throw thrown;
  }
}
