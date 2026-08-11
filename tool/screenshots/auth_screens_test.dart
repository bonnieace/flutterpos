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
