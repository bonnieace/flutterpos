/// Every screen an identity sees before it is inside a business.
///
/// All but the sign-in screen are rendered through the real
/// [TenantRoutingShell], because they are its phases rather than routes anyone
/// can construct: two of them are private classes inside that file. Driving the
/// shell means the picture is of the screen the app actually shows, including
/// which panels the phase decides to offer.
library;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/login_screen.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/widgets/pos_keyboard.dart';
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
    platformPendingTenantDataSource: FakePlatformDataSource(),
    platformLifecycleTenantDataSource: FakePlatformDataSource(),
    platformRejectedTenantDataSource: FakePlatformDataSource(),
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

  screenshotCase('09a-platform-pending-reviews', build: platform);

  // The other three tabs, each reached the way an operator reaches it. A tab is
  // a screen here: they have different data sources, different callables, and
  // different roles behind them.
  for (final (name, label) in const <(String, String)>[
    ('09b-platform-active-and-suspended', 'Active & suspended'),
    ('09c-platform-rejected-archive', 'Rejected archive'),
    ('09d-platform-global-user-status', 'Global user status'),
  ]) {
    screenshotCase(
      name,
      build: platform,
      afterPump: (tester) async => tester.tap(find.text(label)),
    );
  }
}
