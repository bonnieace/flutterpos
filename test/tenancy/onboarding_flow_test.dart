import 'package:flutter/material.dart';
import 'package:flutter_application_1/tenancy/account_profile.dart';
import 'package:flutter_application_1/tenancy/account_registration.dart';
import 'package:flutter_application_1/tenancy/onboarding_flow.dart';
import 'package:flutter_application_1/tenancy/tenant_bootstrap.dart';
import 'package:flutter_application_1/tenancy/tenant_request.dart';
import 'package:flutter_application_1/theme.dart';
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

      expect(fixture.complete.payloads.single['phone'], '+255712345678');
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
      expect(find.textContaining('owner@example.com'), findsOneWidget);
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
      await _tap(tester, 'tenant-request-review');
      await _tap(tester, 'tenant-request-confirm');

      expect(
        find.byKey(const ValueKey('onboarding-complete-step')),
        findsOneWidget,
      );
      expect(find.textContaining('Chill Tent Bar is ready'), findsOneWidget);
      expect(find.text('TZS'), findsOneWidget);
      expect(fixture.opened, isEmpty);

      // **Wait the submission snack bar out before pressing anything.** The
      // step gained its drawing on 2026-09-03, which pushes *Open the till*
      // down to where the snack bar sits on an 800x600 test surface - and a
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

OnboardingIdentity _named({bool verified = false}) => OnboardingIdentity(
  uid: 'user-a',
  email: 'owner@example.com',
  emailVerified: verified,
  displayName: 'Boniface Masota',
  phone: '+255712345678',
  profile: const RootRoutingProfile(
    accountType: RootAccountType.tenantUser,
    globalStatus: 'active',
  ),
);

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
  _Fixture({OnboardingIdentity? identity, Object? changeEmailFailure})
    : identity = identity ?? const OnboardingIdentity() {
    registration = _Registration(order);
    complete = _CompleteCallable(order);
    changeEmail = _ChangeEmailCallable(changeEmailFailure);
  }

  OnboardingIdentity identity;

  /// Whether the next reload discovers a verified address, which is the only
  /// way this app ever learns of one.
  bool verifiesOnReload = false;
  final List<String> order = <String>[];
  final List<TenantRequestResult> opened = <TenantRequestResult>[];
  int reloads = 0;

  late final _Registration registration;
  late final _CompleteCallable complete;
  late final _ChangeEmailCallable changeEmail;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: spiritTheme,
        home: OnboardingFlow(
          readIdentity: () => identity,
          reloadIdentity: () async {
            reloads++;
            if (verifiesOnReload) identity = _named(verified: true);
          },
          onSignOut: () async {},
          onOpenBusiness: opened.add,
          registration: registration,
          completeSelfSignupCallable: complete,
          changeSignupEmailCallable: changeEmail,
          requestTenantCallable: _RequestCallable(),
          accountProfileRequestIdFactory: () => 'profile-request-000000',
          tenantRequestIdFactory: () => 'tenant-request-000000',
          clock: () => DateTime.utc(2026, 8, 30, 16, 45),
        ),
      ),
    );
    await tester.pump();
  }
}

final class _RegistrationAttempt {
  const _RegistrationAttempt({required this.email, required this.password});

  final String email;
  final String password;
}

final class _Registration implements EmailPasswordRegistration {
  _Registration(this.order);

  final List<String> order;
  final List<_RegistrationAttempt> attempts = <_RegistrationAttempt>[];

  @override
  Future<void> call({required String email, required String password}) async {
    order.add('register');
    attempts.add(_RegistrationAttempt(email: email, password: password));
  }
}

final class _CompleteCallable implements CompleteSelfSignupCallable {
  _CompleteCallable(this.order);

  final List<String> order;
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    order.add('complete');
    payloads.add(Map<String, Object?>.from(payload));
    return <String, Object?>{
      'displayName': payload['displayName'],
      'phone': payload['phone'],
    };
  }
}

final class _ChangeEmailCallable implements ChangeSignupEmailCallable {
  _ChangeEmailCallable(this.failure);

  final Object? failure;
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(Map<String, Object?>.from(payload));
    final thrown = failure;
    if (thrown != null) throw thrown;
    return <String, Object?>{'email': payload['email']};
  }
}

final class _RequestCallable implements RequestTenantCallable {
  @override
  Future<Object?> call(Map<String, Object?> payload) async => <String, Object?>{
    'tenantId': 'tenant-generated',
    'name': payload['name'],
    'slug': payload['slug'],
    'currency': payload['currency'],
    'status': 'pending',
    'provisionalUntil': 1788339600000,
  };
}
