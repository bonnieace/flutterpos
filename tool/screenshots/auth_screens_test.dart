/// Every screen an identity sees before it is inside a business.
///
/// All but the sign-in screen are rendered through the real
/// [TenantRoutingShell], because they are its phases rather than routes anyone
/// can construct: two of them are private classes inside that file. Driving the
/// shell means the picture is of the screen the app actually shows, including
/// which panels the phase decides to offer.
library;

import 'package:flutter/material.dart';
import 'package:uzapay_pos/login_screen.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:uzapay_pos/widgets/pos_keyboard.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'harness.dart';

/// A token in the exact shape `fromUriIfPresent` accepts: 43 URL-safe
/// characters, which is a base64url-encoded 32-byte proof.
const String _token = 'JsX2mQ7pR4vT9bN1cK5wY8aZ0dL3eF6gH2iO4uP7sV1';

TenantInvitationLink _invitationLink() => TenantInvitationLink.fromUriIfPresent(
  Uri.parse(
    'https://devcorner.test/invite'
    '?tenantId=$seedTenantId'
    '&uid=$cashierUid'
    '&invitationVersion=4'
    '&invitationToken=$_token',
  ),
)!;

Widget _shell({
  required List<TenantMembership> memberships,
  RootRoutingProfile profile = seedTenantProfile,
  int rootFailures = 0,
  bool emailVerified = true,
  TenantInvitationLink? invitationLink,
  bool invalidInvitationLink = false,
  bool platformClaim = false,
  String uid = ownerUid,
}) {
  final gateway = FakeRoutingGateway(
    memberships: memberships,
    profile: profile,
    rootFailures: rootFailures,
  );
  final callable = FakeTenancyCallable();
  return TenantRoutingShell(
    authUidChanges: Stream<String?>.value(uid),
    bootstrapService: fakeBootstrapService(gateway),
    tenantSwitchStateSources: safeLandingTenantSwitchStateSources(),
    tenantSwitchOnlineCheck: () async => true,
    signOut: () async {},
    signedOut: const LoginScreen(),
    isEmailVerified: (_) => emailVerified,
    reloadIdentity: () async {},
    invitationLink: invitationLink,
    invalidInvitationLink: invalidInvitationLink,
    acceptTenantInvitationCallable: callable,
    acceptVisibleInvitationCallable: callable,
    requestTenantCallable: callable,
    sendAccountVerificationCallable: callable,
    setDefaultTenantCallable: callable,
    emailDeliveryStatusCallable: FakeEmailDeliveryStatusCallable(),
    hasPlatformSuperAdminClaim: (_) async => platformClaim,
    platformLifecycleTenantDataSource: FakePlatformDataSource(),
    platformGlobalUserDataSource: FakePlatformDataSource(),
    setTenantLifecycleCallable: callable,
    setGlobalUserStatusCallable: callable,
    tenantDataReader: FakeTenantReader.business(),
  );
}

/// A sign-in boundary that always refuses, so the screen's answer can be
/// photographed.
///
/// **`FakeCallable`'s lesson one screen along**: a capture whose subject is what
/// a screen says *after* an action needs a boundary that can answer, and the
/// real one reaches `FirebaseAuth.instance`.
final class _FailingSignIn implements EmailPasswordSignIn {
  const _FailingSignIn(this.failure);

  final Object failure;

  @override
  Future<void> call({
    required String email,
    required String password,
    required bool remember,
  }) async => throw failure;
}

/// Fills the form, submits it, and lets the refusal land.
Future<void> _signInAndFail(WidgetTester tester) async {
  await tester.enterText(
    find.descendant(
      of: find.byKey(const ValueKey('login-email')),
      matching: find.byType(TextField),
    ),
    'owner@example.com',
  );
  await tester.enterText(
    find.descendant(
      of: find.byKey(const ValueKey('login-password')),
      matching: find.byType(TextField),
    ),
    'wrong horse',
  );
  await tester.tap(find.byKey(const ValueKey('login-submit')));
  // Two pumps: one to send, one for the `setState` the refusal lands in.
  await tester.pump();
  await tester.pump();
}

/// Two accessible businesses and one whose invitation is still open, which is
/// what makes the selector show all three of its row states at once.
List<TenantMembership> _selectorMemberships() => <TenantMembership>[
  seedMembership(),
  seedMembership(
    tenantId: 'westlands-mart',
    tenantName: 'Westlands Mart',
    role: TenantRole.manager,
  ),
  seedMembership(
    tenantId: 'kilimani-grocers',
    tenantName: 'Kilimani Grocers',
    role: TenantRole.cashier,
    membershipStatus: MembershipStatus.pending,
    canAccess: false,
  ),
];

void main() {
  onboardingScreenshots();
  screenshotCase(
    '01-sign-in',
    build: () => const LoginScreen(),
    // The email field takes focus after the first frame and its caret blinks
    // forever, so there is no quiet frame to settle on.
    settle: false,
  );

  // **The three states of this screen that only exist after somebody presses
  // something**, which is the class of thing `PLAN.md` records as having no
  // harness coverage at all: the notice chunk of 2026-08-15 changed what seven
  // surfaces say about every write in the app and moved zero images, because a
  // notice appears only after a write and no capture performed one.
  //
  // The first needs no boundary: an empty form refuses itself, which is the
  // §5.2 error line under the field it is about.
  screenshotCase(
    '01b-sign-in-refused-here',
    settle: false,
    build: () => const LoginScreen(),
    afterPump: (tester) async {
      await tester.tap(find.byKey(const ValueKey('login-submit')));
      await tester.pump();
    },
  );

  // The second is what the identity provider answered, which is the page notice
  // rather than a field. `invalid-credential` is the branch a wrong password
  // actually reaches.
  screenshotCase(
    '01c-sign-in-refused-there',
    settle: false,
    build: () => LoginScreen(
      signIn: _FailingSignIn(const SignInException('invalid-credential')),
    ),
    afterPump: _signInAndFail,
  );

  // The third is the branch this chunk found: a device that never reached the
  // server is `status.info`, not a refusal, and it had been drawn identically to
  // a wrong password since the screen was written.
  screenshotCase(
    '01d-sign-in-unreachable',
    settle: false,
    build: () => LoginScreen(
      signIn: _FailingSignIn(const SignInException('network-request-failed')),
    ),
    afterPump: _signInAndFail,
  );

  // **The keypad with its caps lock on**, which is the only state of this screen
  // that a picture of the resting screen cannot show: every letter face changes,
  // and the key itself moves to §2.1's `primary` tier. `web` only - the keypad
  // does not appear below 1264, so a phone capture would be the form again.
  screenshotCase(
    '01e-sign-in-caps-locked',
    settle: false,
    viewports: const <ScreenshotViewport>[webViewport],
    build: () => const LoginScreen(),
    afterPump: (tester) async {
      await tester.tap(
        find.descendant(
          of: find.byType(PosKeyboard),
          matching: find.byIcon(Icons.keyboard_capslock),
        ),
      );
      await tester.pump();
    },
  );

  screenshotCase(
    '02-choose-business',
    build: () => _shell(memberships: _selectorMemberships()),
  );

  screenshotCase(
    '03-verify-email-address',
    build: () =>
        _shell(memberships: _selectorMemberships(), emailVerified: false),
  );

  screenshotCase(
    '04-request-a-business',
    build: () => _shell(memberships: _selectorMemberships()),
    afterPump: (tester) async {
      await tester.tap(find.byKey(const ValueKey('show-tenant-request')));
    },
  );

  screenshotCase(
    '05-no-businesses',
    build: () => _shell(memberships: const <TenantMembership>[]),
  );

  screenshotCase(
    '06-accept-an-invitation',
    build: () => _shell(
      memberships: _selectorMemberships(),
      invitationLink: _invitationLink(),
    ),
  );

  screenshotCase(
    '07-invalid-invitation-link',
    build: () => _shell(
      memberships: _selectorMemberships(),
      invalidInvitationLink: true,
    ),
  );

  screenshotCase(
    '08-cannot-open-your-account',
    build: () => _shell(memberships: _selectorMemberships(), rootFailures: 1),
  );

  Widget platform() => _shell(
    memberships: const <TenantMembership>[],
    profile: seedPlatformProfile,
    platformClaim: true,
    uid: 'platform-admin',
  );

  screenshotCase(
    '09b-platform-active-and-suspended',
    build: platform,
    viewports: responsiveViewports,
  );

  // The other tab, reached the way an operator reaches it. A tab is a screen
  // here: they have different data sources, different callables, and different
  // roles behind them.
  screenshotCase(
    '09d-platform-global-user-status',
    build: platform,
    afterPump: (tester) async => tester.tap(find.text('Global user status')),
    viewports: responsiveViewports,
  );
}

// ---------------------------------------------------------------------------
// Signing up
// ---------------------------------------------------------------------------
//
// **Four pictures of one flow**, which is the point of it. Before 2026-09-02
// these states were spread across the login screen's register mode and two
// panels bolted to the business selector, and the harness had a picture of
// none of them. What the images can show is each step's layout, its progress
// header and the states its controls can be in. What they cannot show is the
// thing the flow is actually about: that leaving for a mailbox and coming back
// advances it without a tap. That needs a device.

final class _CaptureComplete implements CompleteSelfSignupCallable {
  const _CaptureComplete();

  @override
  Future<Object?> call(Map<String, Object?> payload) async => <String, Object?>{
    'displayName': payload['displayName'],
    'phone': payload['phone'],
  };
}

final class _CaptureChangeEmail implements ChangeSignupEmailCallable {
  const _CaptureChangeEmail();

  @override
  Future<Object?> call(Map<String, Object?> payload) async => <String, Object?>{
    'email': payload['email'],
  };
}

final class _CaptureRequestTenant implements RequestTenantCallable {
  const _CaptureRequestTenant();

  @override
  Future<Object?> call(Map<String, Object?> payload) async => <String, Object?>{
    'tenantId': 'tenant-generated',
    'name': payload['name'],
    'slug': payload['slug'],
    'currency': payload['currency'],
    'status': 'active',
  };
}

/// **No `MaterialApp` of its own.** `captureScreen` already wraps what it is
/// given in one - with `screenshotTheme()` and the debug banner off - so a
/// second one nested inside took `spiritTheme` instead of the capture theme and
/// painted the checked-mode stripe across the corner of every onboarding frame.
Widget _onboarding(OnboardingIdentity identity, {bool reachable = true}) =>
    OnboardingFlow(
  readIdentity: () => identity,
  // What the SDK does offline. The verify step's whole mechanism is this call
  // on a timer, so a host that cannot make it is the one state the step has
  // that nothing about the identity can produce.
  reloadIdentity: () async {
    if (!reachable) throw StateError('unreachable');
  },
  onSignOut: () async {},
  onOpenBusiness: (_) {},
  completeSelfSignupCallable: const _CaptureComplete(),
  changeSignupEmailCallable: const _CaptureChangeEmail(),
  requestTenantCallable: const _CaptureRequestTenant(),
  accountProfileRequestIdFactory: () => 'profile-capture-000000',
  tenantRequestIdFactory: () => 'tenant-capture-000000',
  clock: () => DateTime.utc(2026, 8, 30, 16, 45),
);

const OnboardingIdentity _namedIdentity = OnboardingIdentity(
  uid: 'user-a',
  email: 'boniface@example.com',
  displayName: 'Boniface Masota',
  phone: '+255712345678',
  profile: RootRoutingProfile(
    accountType: RootAccountType.tenantUser,
    globalStatus: 'active',
  ),
);

void onboardingScreenshots() {
  screenshotCase(
    '10-onboarding-about-you',
    settle: false,
    build: () => _onboarding(const OnboardingIdentity()),
  );

  screenshotCase(
    '11-onboarding-verify',
    settle: false,
    build: () => _onboarding(_namedIdentity),
  );

  // The one state that only exists after somebody presses something, which is
  // the class the harness has historically had no picture of.
  screenshotCase(
    '11b-onboarding-verify-wrong-address',
    settle: false,
    build: () => _onboarding(_namedIdentity),
    afterPump: (tester) async {
      // The step scrolls at the narrow viewports, so the control has to be
      // brought into view before it can be pressed - otherwise the tap lands
      // on whatever is painted at that point and the capture is of the
      // unopened state.
      final reveal = find.byKey(
        const ValueKey('onboarding-verify-change-email'),
      );
      await tester.ensureVisible(reveal);
      await tester.pump();
      await tester.tap(reveal);
      await tester.pump();
    },
  );

  // **The wait when it cannot check.** Hard rule 5: a component ships with the
  // states it can be in, and this one is reachable by nothing the identity says
  // - only by the watch failing three times running. Without a picture it is
  // the state most likely to be drawn once and never looked at.
  screenshotCase(
    '11c-onboarding-verify-unreachable',
    settle: false,
    build: () => _onboarding(_namedIdentity, reachable: false),
    afterPump: (tester) async {
      // Three eager ticks, which is `onboardingRefreshFailuresBeforeNotice`.
      // Pumped rather than settled: the watch reschedules itself, so there is
      // no quiet frame to settle to.
      for (var tick = 0; tick < onboardingRefreshFailuresBeforeNotice; tick++) {
        await tester.pump(onboardingEagerPollInterval + const Duration(seconds: 1));
      }
      await tester.pump();
    },
  );

  screenshotCase(
    '12-onboarding-business',
    settle: false,
    build: () => _onboarding(
      const OnboardingIdentity(
        uid: 'user-a',
        email: 'boniface@example.com',
        emailVerified: true,
        displayName: 'Boniface Masota',
        phone: '+255712345678',
        profile: RootRoutingProfile(
          accountType: RootAccountType.tenantUser,
          globalStatus: 'active',
        ),
      ),
    ),
  );
}
