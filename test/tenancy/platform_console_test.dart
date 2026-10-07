import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uzapay_pos/tenancy/platform_console.dart';
import 'package:uzapay_pos/tenancy/platform_console_data.dart';
import 'package:uzapay_pos/tenancy/platform_global_user_status.dart';
import 'package:uzapay_pos/tenancy/platform_tenant_console.dart';
import 'package:uzapay_pos/tenancy/tenant_bootstrap.dart';
import 'package:uzapay_pos/theme.dart';
import 'package:uzapay_pos/ui/bottom_nav.dart';
import 'package:uzapay_pos/ui/chips.dart';

import 'support/platform_console_memory.dart';
import 'support/platform_console_world.dart';

final class _GlobalStatusCallable implements SetGlobalUserStatusCallable {
  final List<Map<String, Object?>> calls = <Map<String, Object?>>[];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    calls.add(payload);
    return <String, Object?>{
      'operationId': payload['requestId'],
      'uid': payload['uid'],
      'status': 'completed',
      'targetStatus': payload['status'],
      'affectedTenantIds': <String>[],
      'attemptCount': 1,
    };
  }
}

/// Answers as [inner] does, except that queries [refuse] picks are refused,
/// as SIT refuses a query its rules or its indexes do not cover.
final class _Refusing implements PlatformConsoleDataSource {
  _Refusing(this.inner, this.refuse);

  final PlatformConsoleDataSource inner;
  final bool Function(PlatformQuery query) refuse;

  @override
  Future<List<PlatformRecord>> query(PlatformQuery query) =>
      refuse(query) ? Future.error(StateError('refused')) : inner.query(query);

  @override
  Future<int> count(PlatformQuery query) =>
      refuse(query) ? Future.error(StateError('refused')) : inner.count(query);

  @override
  Future<PlatformRecord?> get(String path) => inner.get(path);
}

final class _Harness {
  _Harness({bool Function(PlatformQuery query)? refuse})
    : memory = MemoryPlatformConsoleDataSource(platformConsoleWorld()),
      refuse = refuse,
      lifecycle = MemorySetTenantLifecycleCallable(),
      global = _GlobalStatusCallable(),
      suppression = MemoryReviewEmailSuppressionCallable(
        suppressed: platformConsoleSuppressed,
      );

  final MemoryPlatformConsoleDataSource memory;
  final bool Function(PlatformQuery query)? refuse;
  final MemorySetTenantLifecycleCallable lifecycle;
  final _GlobalStatusCallable global;
  final MemoryReviewEmailSuppressionCallable suppression;
  var requests = 0;

  Future<void> pump(
    WidgetTester tester, {
    PlatformDestination start = PlatformDestination.overview,
  }) async {
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: spiritTheme,
        home: PlatformConsoleScreen(
          identity: PlatformAdminIdentity(
            uid: platformConsoleOperatorUid,
            profile: const RootRoutingProfile(
              accountType: RootAccountType.platformAdmin,
              globalStatus: 'active',
            ),
            hasSuperAdminClaim: true,
          ),
          source: refuse == null ? memory : _Refusing(memory, refuse!),
          globalUserDataSource: MemoryPlatformGlobalUserDataSource(memory),
          lifecycleCallable: lifecycle,
          globalUserCallable: global,
          suppressionCallable: suppression,
          onSignOut: () async {},
          clock: () => platformConsoleNow,
          requestIdFactory: () => 'platform-request-${++requests}',
          initialDestination: start,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  BuildContext inside(WidgetTester tester) =>
      tester.element(find.byType(PlatformOverviewPage, skipOffstage: false));
}

Future<void> _openBusiness(WidgetTester tester, _Harness harness) async {
  final context = harness.inside(tester);
  PlatformConsoleScope.of(context).openBusiness(context, 'mwangi-hardware');
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a tile opens its destination with its filter applied', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.pump(tester);
    expect(find.text('14'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('platform-tile-suspended')));
    await tester.pumpAndSettle();
    final chips = tester.widget<FilterChipBar<Object>>(
      find.byWidgetPredicate((w) => w is FilterChipBar),
    );
    expect(chips.selected.toString(), contains('suspended'));
    expect(find.text('Kamau Butchery'), findsOneWidget);
    expect(find.text('Ruth’s Boutique'), findsNothing);
  });

  testWidgets('a destination keeps its place when you come back', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.pump(tester, start: PlatformDestination.businesses);
    await tester.tap(find.text('Archived 1'));
    await tester.pumpAndSettle();
    expect(find.text('Nyeri Agrovet'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('platform-nav-people')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('platform-nav-businesses')));
    await tester.pumpAndSettle();
    expect(find.text('Nyeri Agrovet'), findsOneWidget);
    expect(find.text('Ruth’s Boutique'), findsNothing);
  });

  testWidgets('suspending needs a reason, and a retry reuses its request', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.pump(tester);
    await _openBusiness(tester, harness);
    await tester.tap(find.byKey(const ValueKey('platform-business-suspend')));
    await tester.pumpAndSettle();

    final confirm = find.byKey(
      const ValueKey('platform-lifecycle-dialog-confirm'),
    );
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(harness.lifecycle.calls, isEmpty);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('platform-lifecycle-dialog-reason')),
        matching: find.byType(EditableText),
      ),
      'ok',
    );
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.text('Give at least 3 characters.'), findsOneWidget);
    expect(harness.lifecycle.calls, isEmpty);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('platform-lifecycle-dialog-reason')),
        matching: find.byType(EditableText),
      ),
      'Owner asked to pause trading.',
    );
    harness.lifecycle.failWith = const PlatformTenantCallableException(
      'unavailable',
    );
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('platform-lifecycle-dialog-failure')),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);

    harness.lifecycle.failWith = null;
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(harness.lifecycle.calls, hasLength(2));
    expect(harness.lifecycle.calls.first, <String, Object?>{
      'tenantId': 'mwangi-hardware',
      'status': 'suspended',
      'reason': 'Owner asked to pause trading.',
      'requestId': 'platform-request-1',
    });
    expect(
      harness.lifecycle.calls.last['requestId'],
      harness.lifecycle.calls.first['requestId'],
    );
    expect(find.text('Mwangi Hardware is suspended.'), findsOneWidget);
  });

  testWidgets('archiving waits for the slug, typed exactly', (tester) async {
    final harness = _Harness();
    await harness.pump(tester);
    await _openBusiness(tester, harness);
    await tester.tap(find.byKey(const ValueKey('platform-business-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('platform-business-archive')));
    await tester.pumpAndSettle();
    expect(find.text('This cannot be undone.'), findsOneWidget);

    Future<void> type(String key, String text) async {
      await tester.enterText(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(EditableText),
        ),
        text,
      );
      await tester.pumpAndSettle();
    }

    await type('platform-lifecycle-dialog-reason', 'Closed for good.');
    await type('platform-lifecycle-dialog-slug', 'mwangi-hardwar');
    expect(find.text('Doesn’t match mwangi-hardware.'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('platform-lifecycle-dialog-confirm')),
    );
    await tester.pumpAndSettle();
    expect(harness.lifecycle.calls, isEmpty);

    await type('platform-lifecycle-dialog-slug', 'mwangi-hardware');
    await tester.tap(
      find.byKey(const ValueKey('platform-lifecycle-dialog-confirm')),
    );
    await tester.pumpAndSettle();
    expect(harness.lifecycle.calls.single['status'], 'archived');
  });

  testWidgets('disabling a person needs their exact user ID', (tester) async {
    final harness = _Harness();
    await harness.pump(tester);
    final context = harness.inside(tester);
    PlatformConsoleScope.of(context).openPerson(context, 'asha');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('platform-person-disable')));
    await tester.pumpAndSettle();
    expect(
      find.text('Mwangi Hardware is left without an owner who can sign in'),
      findsOneWidget,
    );

    Future<void> type(String key, String text) async {
      await tester.enterText(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(EditableText),
        ),
        text,
      );
      await tester.pumpAndSettle();
    }

    await type(
      'platform-person-dialog-reason',
      'Owner asked to be locked out.',
    );
    await type('platform-person-dialog-confirmation', 'esther');
    await tester.tap(
      find.byKey(const ValueKey('platform-person-dialog-confirm')),
    );
    await tester.pumpAndSettle();
    expect(harness.global.calls, isEmpty);

    await type('platform-person-dialog-confirmation', 'asha');
    await tester.tap(
      find.byKey(const ValueKey('platform-person-dialog-confirm')),
    );
    await tester.pumpAndSettle();
    expect(harness.global.calls.single['uid'], 'asha');
    expect(harness.global.calls.single['status'], 'disabled');
    expect(find.text('Asha Mwangi is disabled.'), findsOneWidget);
  });

  testWidgets('a person page checks email delivery only when asked', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.pump(tester);
    final context = harness.inside(tester);
    PlatformConsoleScope.of(context).openPerson(context, 'esther');
    await tester.pumpAndSettle();
    expect(harness.suppression.calls, isEmpty);
    await tester.ensureVisible(
      find.byKey(const ValueKey('platform-person-check-email')),
    );
    await tester.tap(find.byKey(const ValueKey('platform-person-check-email')));
    await tester.pumpAndSettle();
    expect(harness.suppression.calls.single['action'], 'inspect');
    expect(find.text('Delivering'), findsOneWidget);
  });

  testWidgets('one bar for every destination, there and back', (tester) async {
    final harness = _Harness();
    await harness.pump(tester);
    for (final key in <String>[
      'platform-nav-people',
      'platform-nav-activity',
      'platform-nav-overview',
      'platform-nav-people',
    ]) {
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
      expect(find.byType(AppBottomNav), findsOneWidget);
    }
    expect(find.text('People'), findsWidgets);
    expect(find.text('Overview'), findsNothing);
  });

  testWidgets('a part that cannot be read costs only its own tile', (
    tester,
  ) async {
    final harness = _Harness(
      refuse: (query) =>
          query.collection == 'tenants' && query.orderBy == 'updatedAt',
    );
    await harness.pump(tester);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('platform-tile-suspended')),
        matching: find.text('not read'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('platform-tile-trading')),
        matching: find.text('14'),
      ),
      findsWidgets,
    );
  });

  testWidgets('nothing to report hides Needs you and In progress', (
    tester,
  ) async {
    final harness = _Harness();
    harness.memory.documents.removeWhere(
      (path, _) =>
          path.startsWith('platform_alerts/') ||
          path.startsWith('platform_user_operations/'),
    );
    await harness.pump(tester);
    expect(find.byKey(const ValueKey('platform-tile-needs-you')), findsNothing);
    expect(
      find.byKey(const ValueKey('platform-tile-in-progress')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('platform-tile-growth')), findsOneWidget);
  });

  testWidgets('people still list when where they work is refused', (
    tester,
  ) async {
    final harness = _Harness(refuse: (query) => query.collectionGroup);
    await harness.pump(tester, start: PlatformDestination.people);
    expect(find.text('Ruth Achieng'), findsOneWidget);
    expect(find.text('Owns 1 business'), findsWidgets);
  });
}
