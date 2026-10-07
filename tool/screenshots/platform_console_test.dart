/// The platform console, against the sample world its design draws
/// (`docs/design/platform-console`): Tuesday 20 October 2026, 09:40.
///
/// Built directly rather than through the routing shell, with a fixed clock,
/// so every figure, date and "this week" on a capture is the board's.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uzapay_pos/tenancy/platform_console.dart';
import 'package:uzapay_pos/tenancy/platform_global_user_status.dart';
import 'package:uzapay_pos/tenancy/platform_tenant_console.dart';
import 'package:uzapay_pos/tenancy/tenant_bootstrap.dart';

import '../../test/tenancy/support/platform_console_memory.dart';
import '../../test/tenancy/support/platform_console_world.dart';
import 'harness.dart';

final class _GlobalStatusCallable implements SetGlobalUserStatusCallable {
  @override
  Future<Object?> call(Map<String, Object?> payload) async => <String, Object?>{
    'operationId': payload['requestId'],
    'uid': payload['uid'],
    'status': 'completed',
    'targetStatus': payload['status'],
    'affectedTenantIds': <String>[],
    'attemptCount': 1,
  };
}

Widget _console({PlatformDestination start = PlatformDestination.overview}) {
  final memory = MemoryPlatformConsoleDataSource(platformConsoleWorld());
  return PlatformConsoleScreen(
    identity: PlatformAdminIdentity(
      uid: platformConsoleOperatorUid,
      profile: const RootRoutingProfile(
        accountType: RootAccountType.platformAdmin,
        globalStatus: 'active',
      ),
      hasSuperAdminClaim: true,
    ),
    source: memory,
    globalUserDataSource: MemoryPlatformGlobalUserDataSource(memory),
    lifecycleCallable: MemorySetTenantLifecycleCallable(),
    globalUserCallable: _GlobalStatusCallable(),
    suppressionCallable: MemoryReviewEmailSuppressionCallable(
      suppressed: platformConsoleSuppressed,
    ),
    onSignOut: () async {},
    clock: () => platformConsoleNow,
    requestIdFactory: () => 'platform-console-request',
    initialDestination: start,
  );
}

/// The console's scope, from inside its own navigator.
PlatformConsoleScope _scope(WidgetTester tester) =>
    PlatformConsoleScope.of(tester.element(find.byType(PlatformOverviewPage)));

BuildContext _inside(WidgetTester tester) =>
    tester.element(find.byType(PlatformOverviewPage));

/// Scrolls the page's list until [finder] is built and on screen, then taps
/// it: on a phone the action sits at the end of a lazily built list.
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find
        .descendant(
          of: find.byType(ListView).last,
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

void main() {
  screenshotCase('p01-platform-overview', build: _console);

  screenshotCase(
    'p02-platform-businesses',
    build: () => _console(start: PlatformDestination.businesses),
  );

  screenshotCase(
    'p03-platform-business',
    build: _console,
    afterPump: (tester) async {
      _scope(tester).openBusiness(_inside(tester), 'mwangi-hardware');
      await tester.pumpAndSettle();
    },
  );

  screenshotCase(
    'p04-platform-people',
    build: () => _console(start: PlatformDestination.people),
  );

  screenshotCase(
    'p05-platform-person',
    build: _console,
    afterPump: (tester) async {
      _scope(tester).openPerson(_inside(tester), 'esther');
      await tester.pumpAndSettle();
    },
  );

  screenshotCase(
    'p06-platform-alerts',
    build: () => _console(start: PlatformDestination.alerts),
  );

  screenshotCase(
    'p07-platform-activity',
    build: () => _console(start: PlatformDestination.activity),
  );

  screenshotCase(
    'p08-platform-email-delivery',
    build: _console,
    afterPump: (tester) async {
      _scope(
        tester,
      ).openEmailDelivery(_inside(tester), email: 'samuel.ochieng@yahoo.com');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('platform-email-look-up')));
    },
  );

  screenshotCase(
    'p09-platform-suspend',
    build: _console,
    fullPage: false,
    afterPump: (tester) async {
      _scope(tester).openBusiness(_inside(tester), 'mwangi-hardware');
      await tester.pumpAndSettle();
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('platform-business-suspend')),
      );
    },
  );

  screenshotCase(
    'p10-platform-disable',
    build: _console,
    fullPage: false,
    afterPump: (tester) async {
      _scope(tester).openPerson(_inside(tester), 'asha');
      await tester.pumpAndSettle();
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('platform-person-disable')),
      );
    },
  );
}
