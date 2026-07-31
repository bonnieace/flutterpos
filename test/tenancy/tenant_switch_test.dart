import 'dart:async';

import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TenantSwitchCoordinator blockers', () {
    for (final entry in <TenantSwitchBlocker, TenantSwitchStateArea>{
      TenantSwitchBlocker.unsynchronizedCheckout:
          TenantSwitchStateArea.checkout,
      TenantSwitchBlocker.submissionInFlight: TenantSwitchStateArea.checkout,
      TenantSwitchBlocker.pendingWrites: TenantSwitchStateArea.pendingWrites,
      TenantSwitchBlocker.unfinishedCashCountOrShiftClose:
          TenantSwitchStateArea.cashClose,
      TenantSwitchBlocker.unsavedTenantWorkflow: TenantSwitchStateArea.workflow,
    }.entries) {
      test('${entry.key.name} retains the current session', () async {
        final fixture = _SwitchFixture();
        final oldEpoch = fixture.controller.requireSession().epoch;
        final result = await fixture
            .coordinator(
              overrides: {
                entry.value: (session) async => TenantSwitchInspection.blocked(
                  area: entry.value,
                  session: session,
                  blocker: entry.key,
                ),
              },
            )
            .switchTenant('tenant-b');

        expect(result.blocker, entry.key);
        expect(fixture.controller.requireSession().tenantId, 'tenant-a');
        expect(fixture.controller.requireSession().epoch, oldEpoch);
        expect(fixture.gateway.calls, 0);
        expect(fixture.store.writes, isEmpty);
      });
    }

    test('a server-confirmed open shift alone does not block', () async {
      final fixture = _SwitchFixture();
      final result = await fixture
          .coordinator(
            overrides: {
              TenantSwitchStateArea.cashClose: (session) async =>
                  TenantSwitchInspection.clean(
                    area: TenantSwitchStateArea.cashClose,
                    session: session,
                    hasServerConfirmedOpenShift: true,
                  ),
            },
          )
          .switchTenant('tenant-b');

      expect(result.switched, isTrue);
      expect(fixture.controller.requireSession().tenantId, 'tenant-b');
    });

    test('missing inspection area fails closed', () async {
      final fixture = _SwitchFixture();
      final sources = _cleanSources()..removeLast();
      final result = await fixture
          .coordinator(sources: sources)
          .switchTenant('tenant-b');

      expect(result.blocker, TenantSwitchBlocker.stateInspectionUnavailable);
      expect(fixture.controller.requireSession().tenantId, 'tenant-a');
    });

    test('duplicate inspection area fails closed', () async {
      final fixture = _SwitchFixture();
      final sources = _cleanSources()
        ..add(_Source(TenantSwitchStateArea.checkout, _clean));
      final result = await fixture
          .coordinator(sources: sources)
          .switchTenant('tenant-b');

      expect(result.blocker, TenantSwitchBlocker.stateInspectionUnavailable);
    });

    test('null, mismatched, and failed inspections fail closed', () async {
      for (final handler in <_Inspect>[
        (_) async => null,
        (session) async => TenantSwitchInspection.clean(
          area: TenantSwitchStateArea.workflow,
          session: session,
        ),
        (_) async => throw StateError('inspection failed'),
      ]) {
        final fixture = _SwitchFixture();
        final result = await fixture
            .coordinator(overrides: {TenantSwitchStateArea.checkout: handler})
            .switchTenant('tenant-b');
        expect(result.blocker, TenantSwitchBlocker.stateInspectionUnavailable);
        expect(fixture.controller.requireSession().tenantId, 'tenant-a');
      }
    });

    test('offline validation fails closed before directory access', () async {
      final fixture = _SwitchFixture(online: false);
      final result = await fixture.coordinator().switchTenant('tenant-b');

      expect(
        result.blocker,
        TenantSwitchBlocker.onlineTargetValidationUnavailable,
      );
      expect(fixture.gateway.calls, 0);
      expect(fixture.controller.requireSession().tenantId, 'tenant-a');
    });
  });

  group('TenantSwitchCoordinator transition', () {
    test('stale canonical target access retains the current session', () async {
      final fixture = _SwitchFixture(includeTarget: false);
      final result = await fixture.coordinator().switchTenant('tenant-b');

      expect(result.blocker, TenantSwitchBlocker.targetAccessDenied);
      expect(fixture.controller.requireSession().tenantId, 'tenant-a');
      expect(fixture.store.writes, isEmpty);
    });

    test('directory failure is an unavailable online validation', () async {
      final fixture = _SwitchFixture(directoryFailure: true);
      final result = await fixture.coordinator().switchTenant('tenant-b');

      expect(
        result.blocker,
        TenantSwitchBlocker.onlineTargetValidationUnavailable,
      );
      expect(fixture.controller.requireSession().tenantId, 'tenant-a');
    });

    test(
      'failed persistence restores current tenant with a fresh epoch',
      () async {
        final fixture = _SwitchFixture(persistenceFailure: true);
        final oldSession = fixture.controller.requireSession();
        final changes = <String>[];
        final result = await fixture
            .coordinator(
              onSessionChanged: (membership) =>
                  changes.add(membership.tenantId),
            )
            .switchTenant('tenant-b');

        expect(result.blocker, TenantSwitchBlocker.persistenceFailed);
        expect(fixture.controller.requireSession().tenantId, 'tenant-a');
        expect(
          fixture.controller.requireSession().epoch,
          greaterThan(oldSession.epoch),
        );
        expect(fixture.controller.ownsEpoch(oldSession.epoch), isFalse);
        expect(changes, ['tenant-b', 'tenant-a']);
        expect(fixture.store.writes, ['tenant-b']);
      },
    );

    test(
      'success opens the target before persisting and advances epoch',
      () async {
        final fixture = _SwitchFixture();
        final oldSession = fixture.controller.requireSession();
        String? openTenantObservedByStore;
        fixture.store.beforeWrite = () {
          openTenantObservedByStore = fixture.controller
              .requireSession()
              .tenantId;
        };

        final result = await fixture.coordinator().switchTenant('tenant-b');

        expect(result.switched, isTrue);
        expect(openTenantObservedByStore, 'tenant-b');
        expect(fixture.controller.requireSession().tenantId, 'tenant-b');
        expect(fixture.controller.ownsEpoch(oldSession.epoch), isFalse);
        expect(fixture.store.writes, ['tenant-b']);
      },
    );

    test(
      'a current-session change during inspection aborts the switch',
      () async {
        final fixture = _SwitchFixture();
        final inspection = Completer<TenantSwitchInspection?>();
        final future = fixture
            .coordinator(
              overrides: {
                TenantSwitchStateArea.checkout: (_) => inspection.future,
              },
            )
            .switchTenant('tenant-b');
        await Future<void>.delayed(Duration.zero);
        fixture.controller.open(
          uid: 'user-a',
          membership: _membership('tenant-c'),
        );
        inspection.complete(
          TenantSwitchInspection.clean(
            area: TenantSwitchStateArea.checkout,
            session: TenantSession.active(
              uid: 'user-a',
              tenantId: 'tenant-a',
              role: TenantRole.admin,
            ),
          ),
        );

        final result = await future;
        expect(result.blocker, TenantSwitchBlocker.sessionChanged);
        expect(fixture.controller.requireSession().tenantId, 'tenant-c');
      },
    );

    test(
      'an Auth clear during persistence never reopens the old tenant',
      () async {
        final fixture = _SwitchFixture();
        fixture.store.writeGate = Completer<void>();
        final future = fixture.coordinator().switchTenant('tenant-b');
        while (fixture.controller.session?.tenantId != 'tenant-b') {
          await Future<void>.delayed(Duration.zero);
        }

        fixture.controller.clear();
        fixture.store.writeGate!.complete();
        final result = await future;

        expect(result.blocker, TenantSwitchBlocker.sessionChanged);
        expect(fixture.controller.session, isNull);
      },
    );

    test(
      'duplicate concurrent attempts do not start a second switch',
      () async {
        final fixture = _SwitchFixture();
        final inspection = Completer<TenantSwitchInspection?>();
        late TenantSession captured;
        final coordinator = fixture.coordinator(
          overrides: {
            TenantSwitchStateArea.checkout: (session) {
              captured = session;
              return inspection.future;
            },
          },
        );
        final first = coordinator.switchTenant('tenant-b');
        await Future<void>.delayed(Duration.zero);
        final second = await coordinator.switchTenant('tenant-b');

        expect(second.blocker, TenantSwitchBlocker.switchInProgress);
        inspection.complete(
          TenantSwitchInspection.clean(
            area: TenantSwitchStateArea.checkout,
            session: captured,
          ),
        );
        expect((await first).switched, isTrue);
        expect(fixture.gateway.calls, 1);
      },
    );
  });
}

typedef _Inspect =
    Future<TenantSwitchInspection?> Function(TenantSession session);

Future<TenantSwitchInspection?> _clean(TenantSession session) async =>
    TenantSwitchInspection.clean(
      area: TenantSwitchStateArea.checkout,
      session: session,
    );

List<TenantSwitchStateSource> _cleanSources({
  Map<TenantSwitchStateArea, _Inspect> overrides = const {},
}) => TenantSwitchStateArea.values
    .map(
      (area) => _Source(
        area,
        overrides[area] ??
            (session) async =>
                TenantSwitchInspection.clean(area: area, session: session),
      ),
    )
    .toList();

final class _Source implements TenantSwitchStateSource {
  const _Source(this.area, this.handler);

  @override
  final TenantSwitchStateArea area;
  final _Inspect handler;

  @override
  Future<TenantSwitchInspection?> inspect(TenantSession session) =>
      handler(session);
}

final class _SwitchFixture {
  _SwitchFixture({
    this.online = true,
    bool includeTarget = true,
    bool directoryFailure = false,
    bool persistenceFailure = false,
  }) : gateway = _Gateway(
         memberships: [
           _membership('tenant-a'),
           if (includeTarget) _membership('tenant-b'),
           _membership('tenant-c'),
         ],
         fail: directoryFailure,
       ),
       store = _Store(fail: persistenceFailure) {
    controller.open(uid: 'user-a', membership: _membership('tenant-a'));
    bootstrap = TenantBootstrapService(
      rootGateway: gateway,
      directory: TenantDirectory(gateway),
      selectionStore: store,
    );
  }

  final bool online;
  final TenantSessionController controller = TenantSessionController();
  final _Gateway gateway;
  final _Store store;
  late final TenantBootstrapService bootstrap;

  TenantSwitchCoordinator coordinator({
    List<TenantSwitchStateSource>? sources,
    Map<TenantSwitchStateArea, _Inspect> overrides = const {},
    TenantSwitchSessionChanged? onSessionChanged,
  }) => TenantSwitchCoordinator(
    sessionController: controller,
    bootstrapService: bootstrap,
    stateSources: sources ?? _cleanSources(overrides: overrides),
    isOnline: () async => online,
    onSessionChanged: onSessionChanged,
  );
}

final class _Gateway implements TenantDirectoryGateway, RootRoutingGateway {
  _Gateway({required this.memberships, this.fail = false});

  final List<TenantMembership> memberships;
  final bool fail;
  int calls = 0;

  @override
  Future<RootRoutingProfile> getRootRoutingProfile(String uid) async =>
      const RootRoutingProfile(
        accountType: RootAccountType.tenantUser,
        globalStatus: 'active',
      );

  @override
  Future<TenantListPage> listMyTenants({
    required int pageSize,
    String? cursor,
  }) async {
    calls++;
    if (fail) throw Exception('network unavailable');
    return TenantListPage(items: memberships, nextCursor: null, hasMore: false);
  }
}

final class _Store implements TenantSelectionStore {
  _Store({this.fail = false});

  final bool fail;
  final List<String> writes = [];
  void Function()? beforeWrite;
  Completer<void>? writeGate;

  @override
  Future<String?> readLastSelectedTenant(String uid) async => null;

  @override
  Future<void> writeLastSelectedTenant(String uid, String tenantId) async {
    writes.add(tenantId);
    beforeWrite?.call();
    await writeGate?.future;
    if (fail) throw StateError('write failed');
  }
}

TenantMembership _membership(String tenantId) => TenantMembership(
  tenantId: tenantId,
  tenantName: 'Business $tenantId',
  tenantSlug: tenantId,
  role: TenantRole.admin,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  isOwner: false,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 7, 31),
  updatedAt: DateTime.utc(2026, 7, 31),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);
