import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/login_screen.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/theme.dart';
import 'package:flutter_application_1/ui/card.dart';
import 'package:flutter_application_1/ui/press.dart';
import 'package:flutter_application_1/ui/status.dart';
import 'package:flutter_application_1/ui/tokens.dart';
import 'package:flutter_application_1/widgets/pos_keyboard.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/notices.dart';

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

/// A readable invitation link, built the way the intake would parse one.
///
/// The shape matters only in that it parses; what this file is about is which
/// of two sentences the screen draws for a readable one versus a broken one.
TenantInvitationLink _link() => TenantInvitationLink.fromUriIfPresent(
  Uri.parse(
    'https://pos.example.test/staff/invitation?tenantId=tenant-a&uid=user-a'
    '&invitationVersion=4&invitationToken=${'a' * 43}',
  ),
)!;

const String _unknownFailure =
    'Sign-in could not be completed. Try again, and contact support if it '
    'keeps happening.';

void main() {
  group('the invitation notice', _invitationNoticeTests);

  testWidgets('an empty password is refused without being sent', (
    tester,
  ) async {
    final signIn = _SignIn();
    await _pump(tester, signIn);

    await tester.enterText(_field('login-email'), 'owner@example.com');
    await _submit(tester);

    expect(signIn.attempts, isEmpty);
    expect(
      _fieldError(tester, 'login-password'),
      'Enter the password for this account.',
    );
  });

  testWidgets('an empty address is refused without being sent', (tester) async {
    final signIn = _SignIn();
    await _pump(tester, signIn);

    await tester.enterText(_field('login-password'), 'correct horse');
    await _submit(tester);

    expect(signIn.attempts, isEmpty);
    expect(
      _fieldError(tester, 'login-email'),
      'Enter the email address for this account.',
    );
  });

  testWidgets('an address of only spaces is refused', (tester) async {
    final signIn = _SignIn();
    await _pump(tester, signIn);

    await tester.enterText(_field('login-email'), '    ');
    await tester.enterText(_field('login-password'), 'correct horse');
    await _submit(tester);

    expect(signIn.attempts, isEmpty);
    expect(
      _fieldError(tester, 'login-email'),
      'Enter the email address for this account.',
    );
  });

  testWidgets('a refusal by this form leaves the button usable', (
    tester,
  ) async {
    final signIn = _SignIn();
    await _pump(tester, signIn);

    await tester.enterText(_field('login-email'), 'owner@example.com');
    await _submit(tester);
    expect(_fieldError(tester, 'login-password'), isNotNull);

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
      _renderedText(
        tester,
      ).where((text) => text.contains('dev.flutter.pigeon')),
      isEmpty,
    );
    expect(
      _renderedText(tester).where((text) => text.contains(_signInChannel)),
      isEmpty,
    );
    expect(noticeMessage(tester, 'login-notice'), _unknownFailure);
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
      expect(
        noticeMessage(tester, 'login-notice'),
        _unknownFailure,
        reason: '$failure',
      );
    }
  });

  testWidgets('a refused credential names the credential', (tester) async {
    final signIn = _SignIn(
      failure: const SignInException('invalid-credential'),
    );
    await _pump(tester, signIn);

    await _signInAs(tester, 'owner@example.com', 'wrong horse');

    expect(
      noticeMessage(tester, 'login-notice'),
      'That email address and password do not match an account. Check both and '
      'try again.',
    );
  });

  group('a notice says which kind of answer it is', () {
    // §11 step 9's own finding, and the reason this screen was the eighth
    // surface of the notice model rather than none of them: a `String?` painted
    // red carried "your password is wrong" and "this device has no connection"
    // identically, on the one screen where the second is not the person's
    // fault.

    testWidgets('a refusal is §2.1\'s problem', (tester) async {
      await _pump(
        tester,
        _SignIn(failure: const SignInException('invalid-credential')),
      );
      await _signInAs(tester, 'owner@example.com', 'wrong horse');

      expect(noticeStatus(tester, 'login-notice'), AppStatus.problem);
    });

    testWidgets('a device that never reached the server is §2.1\'s info', (
      tester,
    ) async {
      await _pump(
        tester,
        _SignIn(failure: const SignInException('network-request-failed')),
      );
      await _signInAs(tester, 'owner@example.com', 'correct horse');

      expect(noticeStatus(tester, 'login-notice'), AppStatus.info);
      expect(
        noticeMessage(tester, 'login-notice'),
        'This device could not reach the server. Check the connection and try '
        'again.',
      );
    });

    testWidgets('a failure nobody can name is still a refusal', (tester) async {
      // The cause is unknown; the outcome is not. Nobody is signed in.
      await _pump(tester, _SignIn(failure: _channelFailure()));
      await _signInAs(tester, 'owner@example.com', 'correct horse');

      expect(noticeStatus(tester, 'login-notice'), AppStatus.problem);
    });
  });

  testWidgets('a failure releases the button so it can be tried again', (
    tester,
  ) async {
    final signIn = _SignIn(
      failure: const SignInException('invalid-credential'),
    );
    await _pump(tester, signIn);

    await _signInAs(tester, 'owner@example.com', 'wrong horse');
    await tester.enterText(_field('login-password'), 'correct horse');
    await _submit(tester);

    expect(signIn.attempts, hasLength(2));
  });

  testWidgets('editing the address clears the error it describes', (
    tester,
  ) async {
    final signIn = _SignIn(
      failure: const SignInException('invalid-credential'),
    );
    await _pump(tester, signIn);

    await _signInAs(tester, 'owner@example.com', 'wrong horse');
    expect(_notice(tester), isNotNull);

    await tester.enterText(_field('login-email'), 'owner@example.co');
    await tester.pump();

    expect(_notice(tester), isNull);
  });

  testWidgets('editing the password clears the error it describes', (
    tester,
  ) async {
    final signIn = _SignIn(
      failure: const SignInException('invalid-credential'),
    );
    await _pump(tester, signIn);

    await _signInAs(tester, 'owner@example.com', 'wrong horse');
    expect(_notice(tester), isNotNull);

    await tester.enterText(_field('login-password'), 'correct horse');
    await tester.pump();

    expect(_notice(tester), isNull);
  });

  testWidgets('a refusal this form made is cleared by editing too', (
    tester,
  ) async {
    final signIn = _SignIn();
    await _pump(tester, signIn);

    await tester.enterText(_field('login-email'), 'owner@example.com');
    await _submit(tester);
    expect(
      _fieldError(tester, 'login-password'),
      'Enter the password for this account.',
    );

    await tester.enterText(_field('login-password'), 'c');
    await tester.pump();

    expect(_fieldError(tester, 'login-password'), isNull);
  });

  testWidgets('moving the cursor is not editing, and keeps the error', (
    tester,
  ) async {
    final signIn = _SignIn(
      failure: const SignInException('invalid-credential'),
    );
    await _pump(tester, signIn);

    await _signInAs(tester, 'owner@example.com', 'wrong horse');
    expect(_notice(tester), isNotNull);

    // A TextEditingController notifies on a selection change as well as a text
    // change. Revealing the password moves the cursor and answers nothing the
    // refusal said, so the refusal must survive it.
    tester.widget<TextField>(_field('login-password')).controller!.selection =
        const TextSelection(baseOffset: 0, extentOffset: 3);
    await tester.pump();
    expect(_notice(tester), isNotNull);

    await tester.tap(find.byIcon(Icons.visibility_off));
    await tester.pump();
    expect(_notice(tester), isNotNull);
  });

  testWidgets('the reveal toggle announces itself, and swaps when it fires', (
    tester,
  ) async {
    // §9's icon-only row. `PillInput` drew this as a bare `GestureDetector`
    // around an `Icon`: no label, and a target the size of the glyph.
    final handle = tester.ensureSemantics();
    await _pump(tester, _SignIn());

    expect(find.bySemanticsLabel('Show the password'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.visibility_off));
    await tester.pump();

    expect(find.byIcon(Icons.visibility), findsOneWidget);
    expect(find.bySemanticsLabel('Hide the password'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the address is trimmed and the password is not', (tester) async {
    final signIn = _SignIn();
    await _pump(tester, signIn);

    await _signInAs(tester, '  owner@example.com  ', ' correct horse ');

    expect(signIn.attempts.single.email, 'owner@example.com');
    expect(signIn.attempts.single.password, ' correct horse ');
    expect(signIn.attempts.single.remember, isTrue);
  });

  // **The remember checkbox is web-only, so this suite cannot tap it.**
  // `kIsWeb` is a compile-time constant and these tests run on the VM, so the
  // control is absent here by the same mechanism it is absent on a phone. What
  // is asserted instead is the native shape: no checkbox, the boundary still
  // told `true`, and the reset link still where it was - it shares the row, and
  // hiding the row would have taken it too. See `_rememberRow`.
  testWidgets('no remember checkbox off the web, and the reset link stays', (
    tester,
  ) async {
    final signIn = _SignIn();
    await _pump(tester, signIn);

    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('Remember me'), findsNothing);
    expect(find.byKey(const ValueKey('login-go-reset')), findsOneWidget);

    await _signInAs(tester, 'owner@example.com', 'correct horse');

    expect(signIn.attempts.single.remember, isTrue);
  });

  testWidgets('a sign-in in flight is not started twice', (tester) async {
    final signIn = _SignIn()..gate = Completer<void>();
    await _pump(tester, signIn);

    await _signInAs(tester, 'owner@example.com', 'correct horse');
    expect(signIn.attempts, hasLength(1));
    expect(_notice(tester), isNull);

    await _submit(tester);
    expect(signIn.attempts, hasLength(1));

    signIn.gate!.complete();
    await tester.pump();
    await tester.pump();

    // Still busy, deliberately: the routing shell replaces this screen once the
    // session opens, and releasing the button first offers a second sign-in
    // against a session that is already being built.
    expect(_notice(tester), isNull);
    expect(find.byType(CircularProgressIndicator), findsOne);
  });

  testWidgets('a build with no boundary renders without reaching Firebase', (
    tester,
  ) async {
    await _pump(tester, null);

    expect(find.byKey(const ValueKey('login-submit')), findsOne);
    expect(_notice(tester), isNull);
  });

  testWidgets('the title appears once, in the largest type role', (
    tester,
  ) async {
    // **Reverted to the old front door on 2026-08-25.** The old screen set
    // "Welcome Back" at one size at every width rather than swapping to a
    // compact role below a band, so the title reads `display` here even at
    // 411. What is still asserted is what mattered either way: the title
    // appears once and its shape comes from a type role rather than a
    // `fontSize` literal.
    await _pump(tester, _SignIn());

    // The fallback set, not `spiritTheme`'s: `_pump` builds a bare
    // `MaterialApp` with no theme, which is the case `componentOf` exists for.
    final tokens = AppTokens.componentOf(
      tester.element(find.text('Welcome back')),
    );
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in to your account.'), findsOneWidget);

    final title = tester.widget<Text>(find.text('Welcome back')).style!;
    expect(title.fontSize, tokens.typography.display.fontSize);
    expect(title.fontWeight, tokens.typography.display.fontWeight);
    expect(title.color, tokens.colors.text.primary);
  });

  testWidgets('the form sits on the page rather than in a container', (
    tester,
  ) async {
    // The owner's preference, and the old front door's shape too: the credential
    // column stands on the page, and the only container on this screen is the
    // glass pane behind the keypad.
    await _pump(tester, _SignIn());
    expect(find.byType(AppCard), findsNothing);
  });

  testWidgets('the fields are the old front door\'s pills, from tokens', (
    tester,
  ) async {
    // **The 1:1 revert, asserted.** The fields are pill-shaped with uppercase
    // eyebrow labels again, which is what existing customers know — but every
    // value behind them is an `AppTokens` role rather than the old screen's
    // hardcoded `mutedGreen`/`accentGreen`/white literals, so a later theme
    // change still reaches them.
    await _pump(tester, _SignIn(), theme: spiritTheme);

    expect(find.text('EMAIL / USER ID'), findsOneWidget);
    expect(find.text('PASSWORD'), findsOneWidget);

    final tokens = AppTokens.componentOf(
      tester.element(find.text('PASSWORD')),
    );

    // The well is a pill in `surface.field`, which is the old shape drawn from
    // the token layer.
    final well = tester.widget<Container>(
      find
          .ancestor(
            of: _field('login-password'),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = well.decoration! as BoxDecoration;
    expect(decoration.color, tokens.colors.surface.field);
    expect(
      decoration.borderRadius,
      BorderRadius.circular(tokens.radius.pill),
    );

    // The label is `label.eyebrow`, the one role §2.2 permits uppercase on.
    final label = tester.widget<Text>(find.text('PASSWORD')).style!;
    expect(label.fontSize, tokens.typography.labelEyebrow.fontSize);
  });

  testWidgets('a field draws one border, not two', (tester) async {
    // The defect commit `1b2b13b` introduced on 2026-08-10: `InputDecorator`
    // prefers `enabledBorder` and `focusedBorder` over `border`, so a theme
    // border was painted inside the pill's own well. The pill field strips the
    // inner decoration to nothing and draws the well itself; this asserts it
    // against the real theme rather than a bare one.
    await _pump(tester, _SignIn(), theme: spiritTheme);

    final decoration = tester
        .widget<TextField>(_field('login-password'))
        .decoration!;
    expect(decoration.filled, isFalse);
    expect(decoration.isCollapsed, isTrue);
    // All six, because `InputDecorator` prefers `enabledBorder` and
    // `focusedBorder` over `border` — setting only `border` is what let the
    // theme paint a second outline inside the pill.
    for (final border in <InputBorder?>[
      decoration.border,
      decoration.enabledBorder,
      decoration.focusedBorder,
      decoration.disabledBorder,
      decoration.errorBorder,
      decoration.focusedErrorBorder,
    ]) {
      expect(border, InputBorder.none);
    }
  });

  group('the keypad appears when there is room to draw it', () {
    // **Step 9's rewiring, and it moves a boundary rather than renaming one.**
    // The screen asked §4.1 whether the window was 768 wide; the question it
    // needed answered is whether half the window can hold ten keys at §9's tap
    // target, which is a measurement `PosKeyboard` takes. At §4.1's `medium`
    // floor the old answer gave each of ten keys 24 pixels of slot and 13
    // painted, against §9's 48.

    testWidgets('one pixel below the measured floor, it is absent', (
      tester,
    ) async {
      await _pumpAt(tester, _keypadFloor - 1);
      expect(find.byType(PosKeyboard), findsNothing);
    });

    testWidgets('at it, it is drawn', (tester) async {
      await _pumpAt(tester, _keypadFloor);
      expect(find.byType(PosKeyboard), findsOneWidget);
    });

    testWidgets('and every key is at least §9\'s tap target wide', (
      tester,
    ) async {
      // The claim `minimumWidth` makes, asserted against the rendering rather
      // than against itself. This is the assertion the column-arithmetic chunk
      // of 2026-08-15 argued for: where a component publishes a number about
      // its own geometry, measure it.
      await _pumpAt(tester, _keypadFloor);

      final key = find.descendant(
        of: find.byType(PosKeyboard),
        matching: find.text('0'),
      );
      expect(key, findsOneWidget);
      // The `PressSurface`, which is the tap target rather than the painted
      // face: §9's row is about what answers a finger.
      final target = find.ancestor(
        of: key,
        matching: find.byType(PressSurface),
      );
      expect(
        tester.getSize(target.first).width,
        greaterThanOrEqualTo(AppDensity.comfortable.minimumTapTarget.width),
      );
      expect(
        tester.getSize(target.first).height,
        greaterThanOrEqualTo(AppDensity.comfortable.minimumTapTarget.height),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('§4.1\'s medium floor is not the boundary any more', (
      tester,
    ) async {
      // What the old test asserted, kept as the thing that is now false: 768 is
      // a page band and it was never a statement about a keyboard.
      expect(_keypadFloor, greaterThan(AppLayout.contract.mediumFloor));
      expect(_keypadFloor, greaterThan(AppLayout.contract.expandedFloor));
      // 10 units at 48, 9 gaps at 8, the card's inset and the pane's margin.
      expect(PosKeyboard.columns, 10);
      expect(PosKeyboard.minimumWidth(AppTokens.dark), 632);
      expect(_keypadFloor, 1264);
    });

    testWidgets('the widest row is measured, not written down', (tester) async {
      // `columns` was a hardcoded 10 until the `Caps` key arrived, at which
      // point it was one edit away from being wrong. It reads `rows` now, so a
      // key added to the busiest row widens the pane the keypad asks for rather
      // than silently shrinking every key below §9's target.
      final widest = PosKeyboard.rows
          .map(
            (row) => row.fold<int>(
              0,
              (total, key) =>
                  total +
                  switch (key) {
                    PosKeyboard.space => 4,
                    PosKeyboard.enter => 2,
                    PosKeyboard.backspace => 2,
                    _ => 1,
                  },
            ),
          )
          .reduce((a, b) => a > b ? a : b);
      expect(PosKeyboard.columns, widest);
    });
  });

  group('the keypad has a caps lock', () {
    // Asked for by the product owner on 2026-08-15. It adds a capability and
    // fixes a defect in the same key: before it, every letter key inserted its
    // upper-case identifier, so this keypad could not type a lower-case
    // password at all.

    testWidgets('letters are lower case until Caps is pressed', (tester) async {
      await _pumpAt(tester, _keypadFloor);

      expect(_keyFace(tester, 'q'), findsOneWidget);
      expect(_keyFace(tester, 'Q'), findsNothing);

      await tester.tap(_capsKey());
      await tester.pumpAndSettle();

      expect(_keyFace(tester, 'Q'), findsOneWidget);
      expect(_keyFace(tester, 'q'), findsNothing);
    });

    testWidgets('and it types the case it is showing', (tester) async {
      await _pumpAt(tester, _keypadFloor);
      // The email field takes the focus on the first frame, so the keypad is
      // already pointed at it.
      await tester.tap(_keyFace(tester, 'q'));
      await tester.pumpAndSettle();
      expect(_field('login-email').evaluate(), isNotEmpty);
      expect(
        tester.widget<TextField>(_field('login-email')).controller!.text,
        'q',
      );

      await tester.tap(_capsKey());
      await tester.pumpAndSettle();
      await tester.tap(_keyFace(tester, 'Q'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(_field('login-email')).controller!.text,
        'qQ',
      );
    });

    testWidgets('pressing it again unlocks, so it is a lock and not a shift', (
      tester,
    ) async {
      await _pumpAt(tester, _keypadFloor);
      await tester.tap(_capsKey());
      await tester.pumpAndSettle();
      await tester.tap(_keyFace(tester, 'Q'));
      await tester.pumpAndSettle();
      // A shift would clear here. A lock does not.
      expect(_keyFace(tester, 'Q'), findsOneWidget);

      await tester.tap(_capsKey());
      await tester.pumpAndSettle();
      expect(_keyFace(tester, 'q'), findsOneWidget);
    });

    testWidgets('digits and punctuation have no case to change', (
      tester,
    ) async {
      await _pumpAt(tester, _keypadFloor);
      expect(_keyFace(tester, '1'), findsOneWidget);
      expect(_keyFace(tester, '.com'), findsOneWidget);

      await tester.tap(_capsKey());
      await tester.pumpAndSettle();

      expect(_keyFace(tester, '1'), findsOneWidget);
      expect(_keyFace(tester, '.com'), findsOneWidget);
    });

    testWidgets('it announces itself, and says when it is on', (tester) async {
      // §9's icon-only row, plus the half that matters for a latch: a person
      // using a screen reader is told the state, not just the name.
      final handle = tester.ensureSemantics();
      await _pumpAt(tester, _keypadFloor);

      expect(find.bySemanticsLabel('Caps'), findsOneWidget);

      await tester.tap(_capsKey());
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Caps, on'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('and it is not signalled by hue alone', (tester) async {
      // §9: never hue alone. A locked Caps changes tier, so the key's
      // container changes with it and its announcement carries the state in
      // words. **Unlocked is `secondary`'s own container rather than
      // transparent since 2026-08-23**, when that tier was repointed onto the
      // design's `bg-surface-elevated`; what the test holds is that the two
      // states are different containers, not that one of them is nothing.
      await _pumpAt(tester, _keypadFloor);
      final tokens = spiritTheme.extension<AppTokens>()!;
      expect(_capsFill(tester), tokens.colors.action.secondary.container);
      expect(_capsFill(tester), isNot(tokens.colors.action.primary.container));

      await tester.tap(_capsKey());
      await tester.pumpAndSettle();

      expect(
        _capsFill(tester),
        spiritTheme.extension<AppTokens>()!.colors.action.primary.container,
      );
    });
  });
}

/// The key whose face reads [face], inside the keypad.
Finder _keyFace(WidgetTester tester, String face) =>
    find.descendant(of: find.byType(PosKeyboard), matching: find.text(face));

Finder _capsKey() => find.descendant(
  of: find.byType(PosKeyboard),
  matching: find.byIcon(Icons.keyboard_capslock),
);

/// The container colour of the Caps key.
Color? _capsFill(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find.ancestor(of: _capsKey(), matching: find.byType(DecoratedBox)).first,
  );
  return (box.decoration as BoxDecoration).color;
}

/// The narrowest screen this app draws the keypad on.
final double _keypadFloor = PosKeyboard.minimumWidth(AppTokens.dark) * 2;

/// Pumps sign-in at an exact width, for the two cases either side of the
/// keypad's measured floor.
///
/// Tall enough that the desktop branch's two panes both lay out; the narrow
/// branch is the one `_pump` above already covers for every other test here.
/// The sentence a signed-out invitee needs, and the reason it exists.
///
/// Following an invitation link on a phone that has the app opens the app, and
/// an invitee who has just set their password is signed out - so a working link
/// produces this screen. Without the notice it produces it with nothing on it
/// about the invitation that opened it, which reads exactly like the link
/// failing.
void _invitationNoticeTests() {
  testWidgets('says so when an invitation is waiting on a sign-in', (
    tester,
  ) async {
    await _pump(
      tester,
      _SignIn(),
      invitationArrival: ValueNotifier(
        TenantInvitationArrival.valid(_link()),
      ),
    );

    expect(
      find.byKey(const ValueKey('login-invitation-waiting')),
      findsOneWidget,
    );
    expect(find.text(invitationWaitingMessage), findsOneWidget);
  });

  testWidgets('a link that could not be read says that instead', (
    tester,
  ) async {
    // **The one reader who could not be told.** `TenantRoutingShell` draws this
    // sentence for a signed-in person, but that route needs a uid and a
    // bootstrap result - so the signed-out invitee holding the broken link was
    // the only one it could never reach. Until 2026-09-12 they were told an
    // invitation was waiting and that a business would be offered next, and
    // neither was true; an invitee sets their password by following the link,
    // so a failed one leaves an account with no password to sign in with.
    await _pump(
      tester,
      _SignIn(),
      invitationArrival: ValueNotifier(
        const TenantInvitationArrival.invalid(),
      ),
    );

    expect(
      find.byKey(const ValueKey('login-invitation-invalid')),
      findsOneWidget,
    );
    expect(find.text(invitationLinkInvalidMessage), findsOneWidget);
    expect(
      find.byKey(const ValueKey('login-invitation-waiting')),
      findsNothing,
      reason: 'nothing is waiting - the link could not be read',
    );
  });

  testWidgets('says nothing on an ordinary sign-in', (tester) async {
    await _pump(tester, _SignIn());

    expect(find.byKey(const ValueKey('login-invitation-waiting')), findsNothing);
    expect(find.byKey(const ValueKey('login-invitation-invalid')), findsNothing);
  });

  testWidgets('stops saying it the moment the invitation is settled', (
    tester,
  ) async {
    final arrival = ValueNotifier<TenantInvitationArrival?>(
      TenantInvitationArrival.valid(_link()),
    );
    await _pump(tester, _SignIn(), invitationArrival: arrival);
    expect(
      find.byKey(const ValueKey('login-invitation-waiting')),
      findsOneWidget,
    );

    arrival.value = null;
    await tester.pump();

    expect(find.byKey(const ValueKey('login-invitation-waiting')), findsNothing);
  });
}

Future<void> _pumpAt(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: LoginScreen(signIn: _SignIn()),
    ),
  );
  await tester.pump();
}

Future<void> _pump(
  WidgetTester tester,
  EmailPasswordSignIn? signIn, {
  ThemeData? theme,
  ValueListenable<TenantInvitationArrival?>? invitationArrival,
}) async {
  // Narrow enough for the screen's own single-column branch, tall enough that
  // nothing needs scrolling into view before it can be tapped.
  tester.view.physicalSize = const Size(500, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: LoginScreen(
        signIn: signIn,
        invitationArrival: invitationArrival,
      ),
    ),
  );
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

/// The notice the screen is showing, or null.
AppNotice? _notice(WidgetTester tester) {
  final finder = find.byKey(const ValueKey('login-notice'));
  if (finder.evaluate().isEmpty) return null;
  final callout = tester.widget<Callout>(finder);
  return AppNotice(message: callout.message, status: callout.status);
}

/// The error line under one field, which is where a defect this screen found
/// itself is reported.
String? _fieldError(WidgetTester tester, String key) {
  final finder = find.byKey(ValueKey('$key-error'));
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
