import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uzapay_pos/tenancy/account_profile.dart';
import 'package:uzapay_pos/tenancy/account_registration.dart';
import 'package:uzapay_pos/tenancy/account_verification.dart';
import 'package:uzapay_pos/tenancy/email_delivery_status.dart';
import 'package:uzapay_pos/tenancy/onboarding_flow.dart';
import 'package:uzapay_pos/tenancy/tenant_bootstrap.dart';
import 'package:uzapay_pos/ui/buttons.dart';
import 'package:uzapay_pos/tenancy/tenant_request.dart';
import 'package:uzapay_pos/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('deriving the step from the account', () {
    test('no account is the first step', () {
      expect(
        deriveOnboardingStep(
          accountExists: false,
          displayName: null,
          phone: null,
          emailVerified: false,
        ),
        OnboardingStep.account,
      );
    });

    test('an account with no name is the first step again', () {
      // **This is the whole of resuming.** A signup that died between creating
      // the identity and naming it leaves an account that can sign in and do
      // nothing; reading the step from state rather than from a counter sends
      // that person back to the one question that is still unanswered, in the
      // shape that no longer asks for a password.
      for (final (name, phone) in <(String?, String?)>[
        (null, '+255712345678'),
        ('', '+255712345678'),
        ('   ', '+255712345678'),
        ('Boniface', null),
        ('Boniface', ''),
      ]) {
        expect(
          deriveOnboardingStep(
            accountExists: true,
            displayName: name,
            phone: phone,
            emailVerified: true,
          ),
          OnboardingStep.account,
          reason: 'name=$name phone=$phone',
        );
      }
    });

    test('a named but unverified account is the verify step', () {
      expect(
        deriveOnboardingStep(
          accountExists: true,
          displayName: 'Boniface',
          phone: '+255712345678',
          emailVerified: false,
        ),
        OnboardingStep.verify,
      );
    });

    test('a verified account with a name is the business step', () {
      expect(
        deriveOnboardingStep(
          accountExists: true,
          displayName: 'Boniface',
          phone: '+255712345678',
          emailVerified: true,
        ),
        OnboardingStep.business,
      );
    });
  });

  group('the first step', () {
    testWidgets('creates the account and then names it, in that order', (
      tester,
    ) async {
      // The blocking function that writes the root document runs *inside*
      // account creation, so there is no identity to name until creation has
      // returned. A reversed order would name nothing.
      final fixture = _Fixture();
      await fixture.pump(tester);

      await _fillAccount(tester);
      await _tap(tester, 'onboarding-account-submit');

      expect(fixture.registration.attempts, hasLength(1));
      expect(fixture.registration.attempts.single.email, 'owner@example.com');
      expect(fixture.complete.payloads, hasLength(1));
      expect(fixture.order, <String>['register', 'complete']);
    });

    testWidgets('sends the typed number as E.164', (tester) async {
      final fixture = _Fixture();
      await fixture.pump(tester);

      // Written the way it is printed on a SIM pack, trunk zero and all.
      await _fillAccount(tester, phone: '0712 345 678');
      await _tap(tester, 'onboarding-account-submit');

      // Kenya is the code offered by default since 2026-10-08.
      expect(fixture.complete.payloads.single['phone'], '+254712345678');
      expect(fixture.complete.payloads.single['displayName'], 'Boniface Masota');
    });

    testWidgets('a mistyped confirmation never reaches the boundary', (
      tester,
    ) async {
      final fixture = _Fixture();
      await fixture.pump(tester);

      await _fillAccount(tester, password: 'hunter22', confirmation: 'hunter2');
      await _tap(tester, 'onboarding-account-submit');

      expect(fixture.registration.attempts, isEmpty);
      expect(fixture.complete.payloads, isEmpty);
    });

    testWidgets('an account that exists is asked for a name, not a password', (
      tester,
    ) async {
      final fixture = _Fixture(
        identity: const OnboardingIdentity(
          uid: 'user-a',
          email: 'owner@example.com',
        ),
      );
      await fixture.pump(tester);

      expect(find.byKey(const ValueKey('onboarding-name')), findsOneWidget);
      expect(find.byKey(const ValueKey('onboarding-phone')), findsOneWidget);
      expect(find.byKey(const ValueKey('onboarding-password')), findsNothing);
      expect(find.byKey(const ValueKey('onboarding-confirm')), findsNothing);

      await _fillAccount(tester, credentials: false);
      await _tap(tester, 'onboarding-account-submit');

      expect(fixture.registration.attempts, isEmpty);
      expect(fixture.complete.payloads, hasLength(1));
    });

    testWidgets('naming the account moves straight on to verifying it', (
      tester,
    ) async {
      final fixture = _Fixture(
        identity: const OnboardingIdentity(
          uid: 'user-a',
          email: 'owner@example.com',
        ),
      );
      await fixture.pump(tester);

      await _fillAccount(tester, credentials: false);
      await _tap(tester, 'onboarding-account-submit');

      // Without waiting for a bootstrap to re-read the root document: what the
      // flow just saved, it knows.
      expect(
        find.byKey(const ValueKey('onboarding-verify-step')),
        findsOneWidget,
      );
    });
  });

  group('the verify step', () {
    testWidgets('offers no send button, because nothing needs sending', (
      tester,
    ) async {
      // `completeSelfSignup` enqueued the first email. What is offered here is
      // a *re*send, which is a different question.
      final fixture = _Fixture(identity: _named());
      await fixture.pump(tester);

      expect(
        find.byKey(const ValueKey('onboarding-verify-step')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('onboarding-verify-resend')),
        findsOneWidget,
      );
      expect(
        _screenText(tester).where(
          (String text) => text.contains('owner@example.com'),
        ),
        hasLength(1),
      );
    });

    testWidgets('advances by itself once the address verifies', (tester) async {
      final fixture = _Fixture(identity: _named());
      await fixture.pump(tester);
      expect(
        find.byKey(const ValueKey('onboarding-verify-step')),
        findsOneWidget,
      );

      // What a return from the mailbox looks like: the address is already
      // verified on the server, and the reload is the moment this app observes
      // a verification it did not itself perform.
      fixture.verifiesOnReload = true;
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();

      expect(fixture.reloads, greaterThan(0));
      expect(
        find.byKey(const ValueKey('onboarding-business-step')),
        findsOneWidget,
      );
    });

    testWidgets('an undeliverable address is said to be one, not resent to', (
      tester,
    ) async {
      // **The failure this closes.** The server accepts a verification request
      // for a suppressed address and sends nothing, so the step's own notice -
      // "Another email has been requested" - is true and useless. Somebody
      // whose address bounced reads it, waits, presses again, and is told the
      // same thing forever. Observed on SIT on 2026-09-07: two sends, two
      // accepted requests, no mail, and nothing on the screen to explain it.
      final fixture = _Fixture(
        identity: _named(),
        deliveryStatusAnswer: emailDeliveryUnavailableSentinel,
      );
      await fixture.pump(tester);

      expect(
        find.byKey(const ValueKey('onboarding-verify-undeliverable')),
        findsNothing,
        reason: 'nothing has been sent yet, so nothing is known',
      );

      await _tap(tester, 'onboarding-verify-resend');

      expect(fixture.send.calls, 1);
      expect(
        find.byKey(const ValueKey('onboarding-verify-undeliverable')),
        findsOneWidget,
      );
      // The accepted notice stays: the request *was* accepted. The two say
      // different things and both are true.
      expect(
        find.textContaining('sending again will not help'),
        findsOneWidget,
      );
    });

    testWidgets('a resend retried after a refusal replays one intent', (
      tester,
    ) async {
      // *Send again* used to mint a key per tap - `gateway.send(gateway
      // .createIntent())`. The server deduplicates the message on a task id
      // derived from that key and spends a slot of the daily cap per distinct
      // one, so a refused resend followed by a retry charged twice for the one
      // request the person made.
      //
      // The shipped generator runs here, so this asserts the flow holds the
      // intent rather than that the fixture handed it a constant.
      final fixture = _Fixture(identity: _named())..realRequestIds = true;
      await fixture.pump(tester);
      fixture.send.refusals.add('unavailable');

      await _tap(tester, 'onboarding-verify-resend');
      await _tap(tester, 'onboarding-verify-resend');

      expect(fixture.send.calls, 2);
      expect(
        fixture.send.requestIds.first,
        fixture.send.requestIds.last,
        reason: 'one request the person made is one key the server sees',
      );
      expect(find.textContaining('Another email has been requested'), findsOne);
    });

    testWidgets('a resend after the address moves does not reuse its key', (
      tester,
    ) async {
      // The delivery id the server deduplicates on is derived from the address
      // as well as the key, so a key minted for the old address no longer
      // describes this request. Holding it would be holding it past its input.
      final fixture = _Fixture(identity: _named())..realRequestIds = true;
      await fixture.pump(tester);

      await _tap(tester, 'onboarding-verify-resend');

      await _tap(tester, 'onboarding-verify-change-email');
      await tester.enterText(
        find.byKey(const ValueKey('onboarding-verify-new-email')),
        'moved@example.com',
      );
      await _tap(tester, 'onboarding-verify-change-submit');

      await _tap(tester, 'onboarding-verify-resend');

      expect(fixture.send.calls, 2);
      expect(
        fixture.send.requestIds.first,
        isNot(fixture.send.requestIds.last),
      );
    });


    testWidgets('a notice does not follow the step it was raised on', (
      tester,
    ) async {
      // **The banner that outlived its own step.** `_notice` was one field
      // cleared only at the start of the next action, so *Another email has
      // been requested* - true of the verify step - was still on screen after
      // verification landed and the flow had moved to *Your business*, where it
      // asserted something about a step the person had already left. Seen on
      // SIT on 2026-09-10.
      final fixture = _Fixture(identity: _named());
      await fixture.pump(tester);

      await _tap(tester, 'onboarding-verify-resend');
      expect(find.textContaining('Another email has been requested'), findsOne);

      fixture.verifiesOnReload = true;
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('onboarding-business-step')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('onboarding-notice')),
        findsNothing,
        reason: 'the notice belonged to the step that has just been left',
      );
    });

    testWidgets('a stale sign-in asks for a password, not a sign-out', (
      tester,
    ) async {
      // The server wants an `auth_time` under five minutes old, and only a real
      // re-authentication moves one. Doing it here keeps the session - and so
      // keeps this wizard, which is pushed above the routing shell and cannot
      // survive a trip through the sign-in screen.
      final fixture = _Fixture(identity: _named());
      fixture.send.refusals.add('failed-precondition');
      await fixture.pump(tester);

      await _tap(tester, 'onboarding-verify-resend');

      expect(
        find.byKey(const ValueKey('onboarding-verify-reauth-password')),
        findsOneWidget,
      );
      expect(find.textContaining('confirm your password'), findsOne);
      expect(
        find.textContaining('sign out'),
        findsNothing,
        reason: 'the sign-out was never what the server asked for',
      );
    });

    testWidgets('confirming the password sends without ending the session', (
      tester,
    ) async {
      final fixture = _Fixture(identity: _named());
      fixture.send.refusals.add('failed-precondition');
      await fixture.pump(tester);
      await _tap(tester, 'onboarding-verify-resend');

      await tester.enterText(
        find.byKey(const ValueKey('onboarding-verify-reauth-password')),
        'SitOwner2026',
      );
      await _tap(tester, 'onboarding-verify-reauth-submit');
      await tester.pumpAndSettle();

      expect(fixture.reauthentications, 1);
      expect(fixture.passwords, <String>['SitOwner2026']);
      expect(fixture.send.calls, 2, reason: 'refused once, then sent');
      expect(find.textContaining('Another email has been requested'), findsOne);
      expect(
        find.byKey(const ValueKey('onboarding-verify-reauth-password')),
        findsNothing,
        reason: 'the password was wanted for one send, not kept around',
      );
    });

    testWidgets('a password that is not accepted is said so plainly', (
      tester,
    ) async {
      final fixture = _Fixture(
        identity: _named(),
        reauthenticationSucceeds: false,
      );
      fixture.send.refusals.add('failed-precondition');
      await fixture.pump(tester);
      await _tap(tester, 'onboarding-verify-resend');

      await tester.enterText(
        find.byKey(const ValueKey('onboarding-verify-reauth-password')),
        'wrong',
      );
      await _tap(tester, 'onboarding-verify-reauth-submit');
      await tester.pumpAndSettle();

      expect(find.textContaining('was not accepted'), findsOne);
      expect(fixture.send.calls, 1, reason: 'nothing was sent');
      expect(
        find.byKey(const ValueKey('onboarding-verify-reauth-password')),
        findsOneWidget,
        reason: 'the field stays open for another go',
      );
    });

    testWidgets('a host that cannot re-authenticate still says what to do', (
      tester,
    ) async {
      final fixture = _Fixture(
        identity: _named(),
        canReauthenticate: false,
      );
      fixture.send.refusals.add('failed-precondition');
      await fixture.pump(tester);

      await _tap(tester, 'onboarding-verify-resend');

      expect(
        find.byKey(const ValueKey('onboarding-verify-reauth-password')),
        findsNothing,
      );
      expect(find.textContaining('sign out and sign in again'), findsOne);
    });

    testWidgets('a token left behind by an address change is cured quietly', (
      tester,
    ) async {
      // `changeSignupEmail` writes the address to Auth and the token's claim
      // lags by up to an hour, so the server refuses with its own code. The
      // remedy is a newer token, which the gateway takes on itself - the person
      // never learns there was a problem.
      final fixture = _Fixture(identity: _named());
      fixture.send.refusals.add('aborted');
      await fixture.pump(tester);

      await _tap(tester, 'onboarding-verify-resend');
      await tester.pumpAndSettle();

      expect(fixture.refreshes, 1);
      expect(fixture.send.calls, 2);
      expect(
        fixture.send.requestIds.first,
        fixture.send.requestIds.last,
        reason: 'one intent replayed, so the server sends and charges once',
      );
      expect(find.textContaining('Another email has been requested'), findsOne);
      expect(find.textContaining('address has just changed'), findsNothing);
    });

    testWidgets('signing up keeps saying it is creating, not finishing', (
      tester,
    ) async {
      // **The window between the two calls signing up makes.** The Auth account
      // exists before the name and phone are saved, and reading the identity
      // live in there retitles the screen *Almost there / Finish the account
      // you already started* and drops the email and password fields - two
      // seconds after the person pressed the button, while that submission is
      // still running. Right for somebody who abandoned signup and came back;
      // a lie mid-flight.
      final fixture = _Fixture();
      fixture.complete.gate = Completer<void>();
      await fixture.pump(tester);

      await _fillAccount(tester);
      // Not `_tap`: it settles, and nothing settles while the gate holds the
      // submission open under a spinner.
      await tester.ensureVisible(
        find.byKey(const ValueKey('onboarding-account-submit')),
      );
      await tester.tap(find.byKey(const ValueKey('onboarding-account-submit')));
      await tester.pump();
      await tester.pump();

      // Mid-flight: the account exists now, with neither name nor phone.
      expect(fixture.registration.attempts, hasLength(1));
      expect(fixture.identity.uid, isNotNull);
      expect(find.text('Create your account'), findsOne);
      expect(find.text('Almost there'), findsNothing);
      expect(find.text('Finish the account you already started.'), findsNothing);
      expect(
        find.byKey(const ValueKey('onboarding-email')),
        findsOneWidget,
        reason: 'the form must not lose fields while it is being submitted',
      );

      fixture.releaseCompleteSignup();
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('onboarding-verify-step')),
        findsOneWidget,
      );
    });

    testWidgets('a genuinely abandoned account is still told to finish', (
      tester,
    ) async {
      // The other side of the same coin: arriving with an account that has no
      // name or phone, without having just pressed anything, is exactly what
      // the *Almost there* wording was written for.
      final fixture = _Fixture(
        identity: const OnboardingIdentity(uid: 'uid-1', email: 'a@b.com'),
      );
      await fixture.pump(tester);

      expect(find.text('Almost there'), findsOne);
      expect(find.text('Finish the account you already started.'), findsOne);
    });

    testWidgets('a minted session carries the address change without a lapse', (
      tester,
    ) async {
      // **The point of the token.** Rewriting the Auth email rebinds the
      // password credential, so the refresh token on the device stops working
      // and the SDK signs out moments later. A credential minted against the
      // uid is indifferent to that, so exchanging one before the old session
      // lapses means the person never leaves the step they were on.
      final fixture = _Fixture(
        identity: _named(),
        mintedSessionToken: 'custom-token-abc',
      );
      await fixture.pump(tester);

      await _tap(tester, 'onboarding-verify-change-email');
      await tester.enterText(
        find.byKey(const ValueKey('onboarding-verify-new-email')),
        'moved@example.com',
      );
      await _tap(tester, 'onboarding-verify-change-submit');

      expect(fixture.resumed, <String>['custom-token-abc']);
      expect(
        find.byKey(const ValueKey('onboarding-verify-step')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('onboarding-session-ended')),
        findsNothing,
        reason: 'the session was replaced before it could lapse',
      );
      expect(
        _screenText(tester).where(
          (String text) => text.contains('We sent a link to moved@example.com'),
        ),
        hasLength(1),
      );
    });

    testWidgets('a server that mints nothing still changes the address', (
      tester,
    ) async {
      // The mint is allowed to fail without failing the change: by the time it
      // runs the address has moved, the mirror is written and the mail is
      // queued. What is left is a session about to end, which the flow says
      // plainly rather than hiding.
      final fixture = _Fixture(identity: _named());
      await fixture.pump(tester);

      await _tap(tester, 'onboarding-verify-change-email');
      await tester.enterText(
        find.byKey(const ValueKey('onboarding-verify-new-email')),
        'moved@example.com',
      );
      await _tap(tester, 'onboarding-verify-change-submit');

      expect(fixture.resumed, isEmpty);
      expect(find.textContaining('Your address has been changed'), findsOne);

      fixture.loseSession();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('onboarding-session-ended')),
        findsOneWidget,
      );
      expect(find.textContaining('Your address is now moved@example.com'), findsOne);
    });

    testWidgets(
      'duplicate taps are single-flight and retry reuses intent',
      (tester) async {
        // **The ambiguous timeout, from the screen.** The server applies the
        // change and then fails to answer for it. What the person does next is
        // press the same button again, and the request that goes out must be
        // the replay of the one that worked - not a second attempt the server
        // will refuse with the address the first one set.
        //
        // No injected request-id factory: this runs the shipped generator, so
        // the assertion is about the flow holding one intent rather than about
        // a constant the fixture handed it.
        final fixture = _Fixture(identity: _named())..realRequestIds = true;
        await fixture.pump(tester);
        final gate = Completer<void>();
        fixture.changeEmail
          ..gate = gate
          ..refusals.add('unavailable');

        await _tap(tester, 'onboarding-verify-change-email');
        await tester.enterText(
          find.byKey(const ValueKey('onboarding-verify-new-email')),
          'moved@example.com',
        );

        // Not `_tap`: that settles between taps, and the second press has to
        // land while the first is still held open for this to say anything.
        final submit = find.byKey(
          const ValueKey('onboarding-verify-change-submit'),
        );
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.tap(submit);
        await tester.pump();
        expect(
          fixture.changeEmail.payloads,
          hasLength(1),
          reason: 'a second tap while one is in flight is not a second request',
        );

        gate.complete();
        await tester.pumpAndSettle();
        await _tap(tester, 'onboarding-verify-change-submit');

        expect(fixture.changeEmail.payloads, hasLength(2));
        expect(
          fixture.changeEmail.payloads.first['requestId'],
          fixture.changeEmail.payloads.last['requestId'],
          reason:
              'One attempt, one key. A fresh key here is what made the server '
              'refuse a change that had already worked.',
        );
        expect(find.textContaining('Your address has been changed'), findsOne);
      },
    );

    testWidgets('a re-typed address does not inherit the previous key', (
      tester,
    ) async {
      // The other half of holding an intent: it must not outlive the input it
      // was minted for. The server records a hash of the payload against the
      // key and refuses a replay whose input has moved, so reusing it here
      // would turn an edit into a refusal.
      final fixture = _Fixture(identity: _named())..realRequestIds = true;
      await fixture.pump(tester);
      fixture.changeEmail.refusals.add('unavailable');

      await _tap(tester, 'onboarding-verify-change-email');
      await tester.enterText(
        find.byKey(const ValueKey('onboarding-verify-new-email')),
        'typo@example.com',
      );
      await _tap(tester, 'onboarding-verify-change-submit');

      await tester.enterText(
        find.byKey(const ValueKey('onboarding-verify-new-email')),
        'moved@example.com',
      );
      await _tap(tester, 'onboarding-verify-change-submit');

      expect(fixture.changeEmail.payloads, hasLength(2));
      expect(
        fixture.changeEmail.payloads.first['requestId'],
        isNot(fixture.changeEmail.payloads.last['requestId']),
      );
      expect(fixture.changeEmail.payloads.last['email'], 'moved@example.com');
    });


    testWidgets('an exchange that fails is not reported as a failed change', (
      tester,
    ) async {
      // The address did move. Reporting the exchange's failure as the change's
      // would be a lie about work that succeeded, and would send somebody to
      // retype an address the account already holds.
      final fixture = _Fixture(
        identity: _named(),
        mintedSessionToken: 'custom-token-abc',
        resumeSucceeds: false,
      );
      await fixture.pump(tester);

      await _tap(tester, 'onboarding-verify-change-email');
      await tester.enterText(
        find.byKey(const ValueKey('onboarding-verify-new-email')),
        'moved@example.com',
      );
      await _tap(tester, 'onboarding-verify-change-submit');

      expect(fixture.resumed, <String>['custom-token-abc']);
      expect(find.textContaining('Your address has been changed'), findsOne);
      expect(find.textContaining('could not'), findsNothing);
    });

    testWidgets('a session lost under the flow is said so, not redrawn', (
      tester,
    ) async {
      // **The defect this closes, seen on a device on 2026-09-11.** Changing
      // the address rewrites the Auth email, which rebinds the password
      // credential; the refresh token dies with it and the SDK signs out. The
      // flow read its identity during build and nothing rebuilt, so the verify
      // step stayed on screen - enabled controls, a live-looking wait - for an
      // account the session no longer reached.
      final fixture = _Fixture(identity: _named());
      await fixture.pump(tester);
      expect(
        find.byKey(const ValueKey('onboarding-verify-step')),
        findsOneWidget,
      );

      fixture.loseSession();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('onboarding-session-ended')),
        findsOneWidget,
      );
      expect(find.text('Your session has ended'), findsOne);
      expect(
        find.byKey(const ValueKey('onboarding-verify-step')),
        findsNothing,
        reason: 'the step belonged to an identity that no longer exists',
      );
      // The step derivation would answer 'account' for a null uid, which asks
      // somebody who already has an account to create one. That is a different
      // wrong answer, not a right one.
      expect(
        find.byKey(const ValueKey('onboarding-account-step')),
        findsNothing,
      );
    });

    testWidgets('the ended session names the address the flow just set', (
      tester,
    ) async {
      // The address change is the likely reason the session ended, and the new
      // address is what they must now sign in with. Naming the old one would
      // send them round in a circle.
      final fixture = _Fixture(identity: _named());
      await fixture.pump(tester);
      await _tap(tester, 'onboarding-verify-change-email');
      await tester.enterText(
        find.byKey(const ValueKey('onboarding-verify-new-email')),
        'moved@example.com',
      );
      await _tap(tester, 'onboarding-verify-change-submit');

      fixture.loseSession();
      await tester.pumpAndSettle();

      expect(find.textContaining('Your address is now moved@example.com'), findsOne);
    });

    testWidgets('the changed address is the one the verify step names', (
      tester,
    ) async {
      // **The subheading read the identity, which a server-side change does not
      // touch.** The client's cached user record still reported the old address
      // until something reloaded it, so the screen said a link had gone to an
      // address the account had already stopped using.
      final fixture = _Fixture(identity: _named());
      await fixture.pump(tester);
      expect(
        _screenText(tester).where(
          (String text) => text.contains('owner@example.com'),
        ),
        hasLength(1),
      );

      await _tap(tester, 'onboarding-verify-change-email');
      await tester.enterText(
        find.byKey(const ValueKey('onboarding-verify-new-email')),
        'moved@example.com',
      );
      await _tap(tester, 'onboarding-verify-change-submit');

      expect(
        _screenText(tester).where(
          (String text) => text.contains('We sent a link to moved@example.com'),
        ),
        hasLength(1),
      );
      expect(
        _screenText(tester).any(
          (String text) => text.contains('owner@example.com'),
        ),
        isFalse,
        reason: 'the identity still reports it, and the identity is now stale',
      );
    });

    testWidgets('an unanswered change stops naming an address it cannot vouch for', (
      tester,
    ) async {
      // **The third outcome.** The change may have been applied on the far side
      // of an unreachable server, so neither the identity's cached copy nor this
      // flow's own note can say where the link went. Naming one would point
      // somebody at a mailbox with nothing in it.
      final fixture = _Fixture(
        identity: _named(),
        changeEmailFailure: const AccountProfileException('unavailable'),
      );
      await fixture.pump(tester);

      await _tap(tester, 'onboarding-verify-change-email');
      await tester.enterText(
        find.byKey(const ValueKey('onboarding-verify-new-email')),
        'moved@example.com',
      );
      await _tap(tester, 'onboarding-verify-change-submit');

      expect(
        _screenText(tester).any((String t) => t.contains('owner@example.com')),
        isFalse,
        reason: 'the address may already have moved away from this one',
      );
      expect(
        _screenText(tester).where(
          (String t) => t.contains('We sent a link to your address'),
        ),
        hasLength(1),
      );
    });

    testWidgets('a reload outranks what the flow remembers changing', (
      tester,
    ) async {
      // `_changedEmail` was written once on a success and never cleared, so a
      // later change whose answer went missing left the earlier address
      // shadowing an identity that had since been reloaded with the right one.
      final fixture = _Fixture(identity: _named());
      await fixture.pump(tester);

      await _tap(tester, 'onboarding-verify-change-email');
      await tester.enterText(
        find.byKey(const ValueKey('onboarding-verify-new-email')),
        'first@example.com',
      );
      await _tap(tester, 'onboarding-verify-change-submit');
      expect(
        _screenText(tester).where(
          (String t) => t.contains('We sent a link to first@example.com'),
        ),
        hasLength(1),
      );

      // The server says the address is something else now. It is the authority.
      fixture.reloadsAddress = 'second@example.com';
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();

      expect(
        _screenText(tester).where(
          (String t) => t.contains('We sent a link to second@example.com'),
        ),
        hasLength(1),
      );
      expect(
        _screenText(tester).any((String t) => t.contains('first@example.com')),
        isFalse,
        reason: 'the flow note was stale and the reload settled it',
      );
    });

    testWidgets('signing out on purpose is not reported as a surprise', (
      tester,
    ) async {
      // Somebody who pressed *Sign out* does not need to be told their session
      // ended. Only a loss they did not ask for is news.
      final fixture = _Fixture(identity: _named());
      await fixture.pump(tester);

      await _tap(tester, 'onboarding-sign-out');
      fixture.loseSession();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('onboarding-session-ended')),
        findsNothing,
      );
    });

    testWidgets('send again on a lost identity says so instead of nothing', (
      tester,
    ) async {
      // The backstop for a loss no stream announced. This guard used to return
      // in silence, so the button swallowed every press without a word - which
      // is how the defect above stayed hidden through a whole device session.
      final fixture = _Fixture(identity: _named());
      await fixture.pump(tester);

      fixture.identity = const OnboardingIdentity();
      await _tap(tester, 'onboarding-verify-resend');

      expect(fixture.send.calls, 0);
      expect(
        find.byKey(const ValueKey('onboarding-session-ended')),
        findsOneWidget,
      );
    });

    testWidgets('a deliverable address makes no claim about delivery', (
      tester,
    ) async {
      final fixture = _Fixture(
        identity: _named(),
        deliveryStatusAnswer: emailDeliveryAvailableSentinel,
      );
      await fixture.pump(tester);
      await _tap(tester, 'onboarding-verify-resend');

      expect(fixture.send.calls, 1);
      expect(
        find.byKey(const ValueKey('onboarding-verify-undeliverable')),
        findsNothing,
      );
    });

    testWidgets('a host that cannot ask about delivery says nothing at all', (
      tester,
    ) async {
      // The parameter is optional, and its absence must leave the step exactly
      // as it was rather than failing closed into a warning.
      final fixture = _Fixture(identity: _named());
      await fixture.pump(tester);
      await _tap(tester, 'onboarding-verify-resend');

      expect(fixture.send.calls, 1);
      expect(
        find.byKey(const ValueKey('onboarding-verify-undeliverable')),
        findsNothing,
      );
    });

    testWidgets('a route opened over the wait does not end it', (tester) async {
      // **The defect that justified a manual check.** `_syncPolling` cancelled
      // the watch whenever the flow was not the current route and nothing
      // re-armed it, because `_refreshIdentity` returns early on the same
      // condition without rescheduling. So a dialog opened over the verify step
      // and dismissed left the flow with no watch for the rest of its life -
      // and *I have verified* was the only way back, on a screen whose own
      // subheading promises nobody has to press anything.
      final fixture = _Fixture(identity: _named());
      await fixture.pump(tester);

      await tester.pump(const Duration(seconds: 6));
      final whileVisible = fixture.reloads;
      expect(whileVisible, greaterThan(0), reason: 'the watch never started');

      // Something is pushed over the flow. The tick keeps firing and is right
      // to do nothing with it: this screen is not the one being read.
      fixture.current = false;
      await tester.pump(const Duration(seconds: 30));
      expect(
        fixture.reloads,
        whileVisible,
        reason: 'a covered step must not spend the battery or the quota',
      );

      // And it is dismissed. Nothing else happens - no resume, no rebuild from
      // above, no press - because in the case this covers there is nothing else
      // to happen.
      fixture.current = true;
      await tester.pump(const Duration(seconds: 6));

      expect(
        fixture.reloads,
        greaterThan(whileVisible),
        reason:
            'the watch did not come back, so this step can no longer notice a '
            'verification and has nothing left to offer the person waiting',
      );
    });

    testWidgets('a wait that cannot check says so, and can be retried', (
      tester,
    ) async {
      // **Silence is right for one dropped request and wrong for a quarter of a
      // minute of them.** The reload failure is swallowed deliberately - it says
      // nothing about whether the address is verified - but a screen promising
      // to move on by itself, while it has no way to find out whether it should,
      // is making a claim it cannot currently keep.
      final fixture = _Fixture(identity: _named());
      await fixture.pump(tester);

      fixture.reloadFails = true;
      await tester.pump(const Duration(seconds: 6));
      expect(
        find.byKey(const ValueKey('onboarding-verify-unreachable')),
        findsNothing,
        reason: 'one failure is the ordinary condition of a phone on the move',
      );

      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 6));

      expect(
        fixture.reloads,
        greaterThanOrEqualTo(onboardingRefreshFailuresBeforeNotice),
      );
      expect(
        find.byKey(const ValueKey('onboarding-verify-unreachable')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('onboarding-verify-retry')),
        findsOneWidget,
        reason: 'the one state where pressing something is worth offering',
      );

      // Back on a network. The retry is worth having precisely here: it saves
      // the person who just reconnected from waiting out another tick.
      fixture.reloadFails = false;
      final beforeRetry = fixture.reloads;
      await _tap(tester, 'onboarding-verify-retry');

      expect(fixture.reloads, beforeRetry + 1);
      expect(
        find.byKey(const ValueKey('onboarding-verify-unreachable')),
        findsNothing,
        reason: 'the reload answered, so there is nothing left to qualify',
      );
      expect(
        find.byKey(const ValueKey('onboarding-verify-retry')),
        findsNothing,
      );
    });

    testWidgets('a retry that fails again shows that it tried', (tester) async {
      // **The control that replaced *I have verified* was itself silent.** The
      // failure counter stops at the threshold and the counter is what redraws
      // this screen, so once the notice was up, pressing *Try again* changed no
      // number, rebuilt nothing, and was indistinguishable from a dead button -
      // on the one screen where the app has already admitted it is stuck.
      final fixture = _Fixture(identity: _named());
      await fixture.pump(tester);

      fixture.reloadFails = true;
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 6));
      }
      final retry = find.byKey(const ValueKey('onboarding-verify-retry'));
      expect(retry, findsOneWidget);

      // Hold the reload open so the pending frame can be observed at all.
      final held = Completer<void>();
      fixture.holdReload = held;
      final before = fixture.reloads;

      // Not `_tap`: it settles, and the pending frame has to be read before the
      // held reload is allowed to finish.
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pump();

      expect(
        tester.widget<AppButton>(retry).loading,
        isTrue,
        reason: 'the press has to show something for itself',
      );
      expect(
        tester.widget<AppButton>(retry).onPressed,
        isNull,
        reason: 'and must not start a second check while the first runs',
      );

      held.completeError(StateError('unreachable'));
      await tester.pumpAndSettle();

      expect(fixture.reloads, before + 1);
      expect(
        tester.widget<AppButton>(retry).loading,
        isFalse,
        reason: 'the attempt is over, and it failed',
      );
      expect(
        tester.widget<AppButton>(retry).onPressed,
        isNotNull,
        reason: 'so it can be pressed again',
      );
      expect(
        find.byKey(const ValueKey('onboarding-verify-unreachable')),
        findsOneWidget,
        reason: 'still cannot check, and still says so',
      );
    });

    testWidgets('the wait offers no way to assert a verification', (
      tester,
    ) async {
      // *I have verified* called the same reload the watch calls, on the same
      // guards, so it could never do anything the app was not already doing
      // five seconds later. What it did do was sit as the one mint button on
      // the screen, directly under a sentence telling the person this screen
      // moves on by itself - and give no feedback at all when pressed, because
      // it set no busy flag and raised no notice on an unverified answer.
      final fixture = _Fixture(identity: _named());
      await fixture.pump(tester);

      expect(find.text('I have verified'), findsNothing);
      expect(
        find.byKey(const ValueKey('onboarding-verify-retry')),
        findsNothing,
        reason: 'nothing has failed, so there is nothing to retry',
      );
      for (final key in <String>[
        'onboarding-verify-resend',
        'onboarding-verify-change-email',
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget);
      }
    });

    testWidgets('changing the address asks the server, not the client', (
      tester,
    ) async {
      final fixture = _Fixture(identity: _named());
      await fixture.pump(tester);

      await _tap(tester, 'onboarding-verify-change-email');
      await tester.enterText(
        find.byKey(const ValueKey('onboarding-verify-new-email')),
        'correct@example.com',
      );
      await _tap(tester, 'onboarding-verify-change-submit');

      expect(fixture.changeEmail.payloads.single['email'], 'correct@example.com');
    });

    testWidgets('a refused change is a sentence, not a raw code', (
      tester,
    ) async {
      final fixture = _Fixture(
        identity: _named(),
        changeEmailFailure: const AccountProfileException('already-exists'),
      );
      await fixture.pump(tester);

      await _tap(tester, 'onboarding-verify-change-email');
      await tester.enterText(
        find.byKey(const ValueKey('onboarding-verify-new-email')),
        'taken@example.com',
      );
      await _tap(tester, 'onboarding-verify-change-submit');

      expect(find.textContaining('already-exists'), findsNothing);
      expect(find.textContaining('already uses that address'), findsOneWidget);
    });
  });

  group('the last step', () {
    testWidgets('states what was created before opening it', (tester) async {
      final fixture = _Fixture(identity: _named(verified: true));
      await fixture.pump(tester);

      await tester.enterText(
        find.byKey(const ValueKey('tenant-request-name')),
        'Chill Tent Bar',
      );
      await _tap(tester, 'tenant-request-submit');

      expect(
        find.byKey(const ValueKey('onboarding-complete-step')),
        findsOneWidget,
      );
      expect(find.textContaining('Chill Tent Bar is ready'), findsOneWidget);
      expect(find.text('KES'), findsOneWidget);
      expect(fixture.opened, isEmpty);

      // **Wait the submission snack bar out before pressing anything.** The
      // step gained its drawing on 2026-09-03, which pushes *Open your
      // business* down to where the snack bar sits on an 800x600 test surface -
      // and a
      // snack bar is a real widget that really does take the tap. It goes on
      // its own after four seconds; the button is under it until then.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      await _tap(tester, 'onboarding-open-business');
      expect(fixture.opened, hasLength(1));
    });
  });
}

// ---------------------------------------------------------------------------

OnboardingIdentity _named({
  bool verified = false,
  String email = 'owner@example.com',
}) => OnboardingIdentity(
  uid: 'user-a',
  email: email,
  emailVerified: verified,
  displayName: 'Boniface Masota',
  phone: '+255712345678',
  profile: const RootRoutingProfile(
    accountType: RootAccountType.tenantUser,
    globalStatus: 'active',
  ),
);

/// Every `Text` on screen, as it reads rather than as it is stored.
///
/// The verify subheading carries a zero-width space inside the address so the
/// sentence has somewhere legal to wrap - see `_breakableVerifyingAddress`. It
/// puts nothing on the screen, so a test asking what the screen says should not
/// have to spell it, and `find.textContaining` would otherwise both miss an
/// address that is shown and pass an assertion that one is not.
Iterable<String> _screenText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((Text text) => (text.data ?? '').replaceAll('\u200b', ''));

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

Future<void> _fillAccount(
  WidgetTester tester, {
  String name = 'Boniface Masota',
  String phone = '712345678',
  String password = 'hunter22',
  String? confirmation,
  bool credentials = true,
}) async {
  await tester.enterText(find.byKey(const ValueKey('onboarding-name')), name);
  await tester.enterText(find.byKey(const ValueKey('phone-local-number')), phone);
  if (credentials) {
    await tester.enterText(
      find.byKey(const ValueKey('onboarding-email')),
      'owner@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('onboarding-password')),
      password,
    );
    await tester.enterText(
      find.byKey(const ValueKey('onboarding-confirm')),
      confirmation ?? password,
    );
  }
  await tester.pump();
}

final class _Fixture {
  _Fixture({
    OnboardingIdentity? identity,
    Object? changeEmailFailure,
    this.deliveryStatusAnswer,
    this.canReauthenticate = true,
    this.reauthenticationSucceeds = true,
    this.mintedSessionToken,
    this.resumeSucceeds = true,
  }) : identity = identity ?? const OnboardingIdentity() {
    registration = _Registration(
      order,
      onCreated: (email) {
        // The account exists; the name and phone are the next call's job.
        this.identity = OnboardingIdentity(uid: 'uid-new', email: email);
        identityChanges.add(this.identity);
      },
    );
    complete = _CompleteCallable(order);
    changeEmail = _ChangeEmailCallable(
      changeEmailFailure,
      sessionToken: mintedSessionToken,
    );
  }

  /// What `getMyEmailDeliveryStatus` answers, or null for a host that cannot
  /// ask - which is the shape every caller had before it was wired through.
  final Object? deliveryStatusAnswer;

  /// Whether this host can re-authenticate, and whether doing so works.
  final bool canReauthenticate;
  final bool reauthenticationSucceeds;

  /// Whether this flow is the route on top, which is what a dialog or a pushed
  /// screen takes away from it. Mutable, because the whole question is what the
  /// watch does when it is taken away and then given back.
  bool current = true;

  /// Whether a reload can reach the server at all.
  ///
  /// What the SDK does offline: `reload()` throws, and says nothing about
  /// whether the address is verified - which is exactly why the flow cannot
  /// treat it as an answer.
  bool reloadFails = false;

  /// Whether the flow runs the shipped request-id generators instead of the
  /// constants below.
  ///
  /// **A constant factory cannot see the bug these ids exist to prevent.** It
  /// hands the flow a stability the real generator does not have, so a surface
  /// that mints per call still looks stable under test. Every fixture in this
  /// suite injected one, which is why H3 and its two siblings went uncaught.
  /// `account_verification_test.dart` is the precedent for leaving them out.
  bool realRequestIds = false;

  /// Releases a `completeSelfSignup` held open so the window between signing
  /// up's two calls could be inspected rather than raced.
  void releaseCompleteSignup() {
    complete.gate?.complete();
    complete.gate = null;
  }

  /// What `changeSignupEmail` hands back to outlive the address change.
  final String? mintedSessionToken;
  final bool resumeSucceeds;

  /// Every token the flow tried to exchange for a live session.
  final List<String> resumed = <String>[];

  /// Ticks the flow watches for a session ending underneath it.
  final StreamController<Object?> identityChanges =
      StreamController<Object?>.broadcast();

  /// What the SDK does when a credential is rebound underneath the app: the
  /// current user becomes nobody, and the auth-state stream says so.
  void loseSession() {
    identity = const OnboardingIdentity();
    identityChanges.add(null);
  }

  /// How often each seam was reached.
  int refreshes = 0;
  int reauthentications = 0;
  final List<String> passwords = <String>[];

  OnboardingIdentity identity;

  /// Whether the next reload discovers a verified address, which is the only
  /// way this app ever learns of one.
  bool verifiesOnReload = false;

  /// Held open to keep a reload in flight, so a pending frame can be observed.
  Completer<void>? holdReload;

  /// The address a successful reload reports, or null to leave it alone.
  ///
  /// The server is the authority on this: a change applied on its side does not
  /// touch the client's cached user record until something reloads it.
  String? reloadsAddress;
  final List<String> order = <String>[];
  final List<TenantRequestResult> opened = <TenantRequestResult>[];
  int reloads = 0;

  late final _Registration registration;
  late final _CompleteCallable complete;
  late final _ChangeEmailCallable changeEmail;
  final _SendVerificationCallable send = _SendVerificationCallable();

  Future<void> pump(WidgetTester tester) async {
    addTearDown(identityChanges.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: spiritTheme,
        home: OnboardingFlow(
          readIdentity: () => identity,
          isCurrent: () => current,
          reloadIdentity: () async {
            reloads++;
            final held = holdReload;
            if (held != null) {
              holdReload = null;
              await held.future;
            }
            if (reloadFails) throw StateError('unreachable');
            if (verifiesOnReload || reloadsAddress != null) {
              identity = _named(
                verified: verifiesOnReload,
                email: reloadsAddress ?? identity.email!,
              );
            }
          },
          onSignOut: () async {},
          onOpenBusiness: opened.add,
          registration: registration,
          completeSelfSignupCallable: complete,
          changeSignupEmailCallable: changeEmail,
          sendAccountVerificationCallable: send,
          emailDeliveryStatusCallable: deliveryStatusAnswer == null
              ? null
              : _DeliveryStatusCallable(deliveryStatusAnswer!),
          requestTenantCallable: _RequestCallable(),
          accountProfileRequestIdFactory: realRequestIds
              ? null
              : () => 'profile-request-000000',
          accountVerificationRequestIdFactory: realRequestIds
              ? null
              : () => 'verify-request-000000',
          tenantRequestIdFactory: () => 'tenant-request-000000',
          identityChanges: identityChanges.stream,
          resumeSession: (token) async {
            resumed.add(token);
            if (!resumeSucceeds) throw StateError('exchange refused');
            // What the SDK does on a successful exchange: a live session again,
            // for the same account, under its new address.
            this.identity = _named();
            identityChanges.add(this.identity);
          },
          refreshSession: () async => refreshes++,
          reauthenticate: canReauthenticate
              ? (password) async {
                  reauthentications++;
                  passwords.add(password);
                  if (!reauthenticationSucceeds) {
                    throw StateError('wrong password');
                  }
                }
              : null,
          clock: () => DateTime.utc(2026, 8, 30, 16, 45),
        ),
      ),
    );
    await tester.pump();
  }
}

final class _SendVerificationCallable implements SendAccountVerificationCallable {
  int calls = 0;

  /// The codes to refuse with, one per call, before accepting any.
  final List<String> refusals = <String>[];

  /// Every `requestId` the server was asked with, so a retry can be shown to
  /// be the replay of one intent rather than a second request.
  final List<Object?> requestIds = <Object?>[];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    calls++;
    requestIds.add(payload['requestId']);
    if (refusals.isNotEmpty) {
      throw AccountVerificationCallableException(refusals.removeAt(0));
    }
    return <String, Object?>{'accepted': true};
  }
}

final class _DeliveryStatusCallable implements EmailDeliveryStatusCallable {
  _DeliveryStatusCallable(this.answer);

  final Object answer;

  @override
  Future<Object?> call() async => answer;
}

final class _RegistrationAttempt {
  const _RegistrationAttempt({required this.email, required this.password});

  final String email;
  final String password;
}

final class _Registration implements EmailPasswordRegistration {
  _Registration(this.order, {this.onCreated});

  final List<String> order;
  final List<_RegistrationAttempt> attempts = <_RegistrationAttempt>[];

  /// What the SDK does the instant the account exists: an identity with a uid
  /// and nothing else, because the name and phone are a later call.
  final void Function(String email)? onCreated;

  @override
  Future<void> call({required String email, required String password}) async {
    order.add('register');
    attempts.add(_RegistrationAttempt(email: email, password: password));
    onCreated?.call(email);
  }
}

final class _CompleteCallable implements CompleteSelfSignupCallable {
  _CompleteCallable(this.order);

  final List<String> order;
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];

  /// Held open to inspect the window between the two calls signing up makes.
  Completer<void>? gate;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    order.add('complete');
    payloads.add(Map<String, Object?>.from(payload));
    final held = gate;
    if (held != null) await held.future;
    return <String, Object?>{
      'displayName': payload['displayName'],
      'phone': payload['phone'],
    };
  }
}

final class _ChangeEmailCallable implements ChangeSignupEmailCallable {
  _ChangeEmailCallable(this.failure, {this.sessionToken});

  final Object? failure;

  /// Codes to refuse with, one per call, before [failure] or success applies.
  ///
  /// The shape `_SendVerificationCallable.refusals` already uses. It exists so a
  /// test can script the ambiguous outcome this file is about: a call the server
  /// applied and then failed to answer for.
  final List<String> refusals = <String>[];

  /// Held open to keep one call in flight, so a second tap has something to be
  /// single-flighted against. The idiom `_SignIn.gate` uses in
  /// `login_screen_test.dart`; without it the fake answers inside the first
  /// `await` and there is never a moment when two taps overlap.
  Completer<void>? gate;

  /// What the server minted to outlive the change, or null for a server that
  /// could not mint one - which is a documented outcome, not a malformed reply.
  final String? sessionToken;
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(Map<String, Object?>.from(payload));
    final held = gate;
    if (held != null) {
      gate = null;
      await held.future;
    }
    if (refusals.isNotEmpty) {
      throw AccountProfileException(refusals.removeAt(0));
    }
    final thrown = failure;
    if (thrown != null) throw thrown;
    return <String, Object?>{
      'email': payload['email'],
      if (sessionToken != null) 'sessionToken': sessionToken,
    };
  }
}

final class _RequestCallable implements RequestTenantCallable {
  @override
  Future<Object?> call(Map<String, Object?> payload) async => <String, Object?>{
    'tenantId': 'tenant-generated',
    'name': payload['name'],
    'slug': payload['slug'],
    'currency': payload['currency'],
    'status': 'active',
  };
}
