import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/audit/audit.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/text.dart';

void main() {
  testWidgets('the trail is listed as the server recorded it', (tester) async {
    final reader = _Reader(staffNames: <String, String>{'cashier-a': 'Amina'})
      ..respond(<TenantQueryDocumentSnapshot>[_staffEvent(), _platformEvent()]);

    await _pump(tester, _controller(), reader);

    expect(
      tester.widget<Text>(find.byKey(const ValueKey('audit-log-scope'))).data,
      startsWith('Every event this business recorded'),
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('audit-log-event-aud_001')))
          .data,
      TenantAuditEventType.staffInvited.label,
    );
    // The invited colleague is named beside the authoritative UID.
    //
    // The word "About" left this string in step 6: it is the *label* of a
    // `RecordAttribute` now, which is what the table draws as a column header
    // and the card draws as the key half of a key-value line. The value is the
    // colleague, which is what it always meant.
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('audit-log-target-aud_001')))
          .data,
      'Amina (cashier-a)',
    );
    expect(find.text('About'), findsOne);
    // The signed-in admin caused this one, so the row says so rather than
    // repeating their own UID back at them.
    expect(
      textAt(tester, 'audit-log-recorded-aud_001'),
      'Recorded 2026-08-01 09:00 UTC by You',
    );
    // The platform is not a member of the business it acted on, so its events
    // are attributed to the platform rather than to a missing colleague.
    expect(
      textAt(tester, 'audit-log-recorded-aud_002'),
      'Recorded 2026-08-01 09:00 UTC by the platform_admin operator',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('audit-log-status-aud_002')))
          .data,
      'pending to active',
    );
    expect(reader.queries.single.descending, isFalse);
    expect(reader.queries.single.equalityFilters, isEmpty);
  });

  testWidgets('a business whose trail has not started says so', (tester) async {
    final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader);

    expect(
      tester.widget<Text>(find.byKey(const ValueKey('audit-log-empty'))).data,
      'No event has been recorded for this business.',
    );
  });

  testWidgets('an unmodelled event is shown as itself', (tester) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _staffEvent(
          overrides: <String, Object?>{'eventType': 'subscription_renewed'},
        ),
      ]);

    await _pump(tester, _controller(), reader);

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('audit-log-event-aud_001')))
          .data,
      'subscription_renewed',
    );
  });

  testWidgets('the filter narrows the page and restarts it', (tester) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _staffEvent(),
        _platformEvent(),
        _staffEvent(
          auditId: 'aud_003',
          overrides: <String, Object?>{'eventType': 'staff_status_set'},
        ),
      ]);

    await _pump(tester, _controller(), reader, pageSize: 2);
    expect(find.byKey(const ValueKey('audit-log-entry-aud_001')), findsOne);

    await tester.tap(find.byKey(const ValueKey('audit-log-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(TenantAuditEventType.staffStatusSet.label).last);
    await tester.pumpAndSettle();

    expect(reader.queries.last.equalityFilters, <String, Object?>{
      'eventType': 'staff_status_set',
    });
    // A cursor is a document ID inside one exact query, so narrowing the trail
    // pages from the start rather than from a position the new query never
    // established.
    expect(reader.queries.last.startAfterDocumentId, isNull);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('audit-log-scope'))).data,
      startsWith('Every "${TenantAuditEventType.staffStatusSet.label}" event'),
    );
    expect(find.byKey(const ValueKey('audit-log-entry-aud_003')), findsOne);
    expect(find.byKey(const ValueKey('audit-log-entry-aud_001')), findsNothing);
  });

  testWidgets('a caller may open the trail already narrowed', (tester) async {
    final controller = _controller();
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _staffEvent(),
        _staffEvent(
          auditId: 'aud_003',
          overrides: <String, Object?>{'eventType': 'staff_status_set'},
        ),
      ]);

    await _pump(
      tester,
      controller,
      reader,
      eventType: TenantAuditEventType.staffStatusSet,
    );

    expect(reader.queries.single.equalityFilters, <String, Object?>{
      'eventType': 'staff_status_set',
    });
    expect(find.byKey(const ValueKey('audit-log-entry-aud_003')), findsOne);
    expect(find.byKey(const ValueKey('audit-log-entry-aud_001')), findsNothing);

    // Rebuilding the same panel with another event must re-narrow it. The
    // element survives the rebuild, so a filter left in state would silently
    // keep showing the previous event's page.
    await _pump(
      tester,
      controller,
      reader,
      eventType: TenantAuditEventType.staffInvited,
    );

    expect(reader.queries.last.equalityFilters, <String, Object?>{
      'eventType': 'staff_invited',
    });
    expect(find.byKey(const ValueKey('audit-log-entry-aud_001')), findsOne);
  });

  testWidgets('a manager is denied and issues no read at all', (tester) async {
    final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(role: TenantRole.manager), reader);

    expect(find.byKey(const ValueKey('audit-log-denied')), findsOne);
    expect(reader.queries, isEmpty);
    expect(reader.documentPaths, isEmpty);
  });

  testWidgets('a cashier is denied and issues no read at all', (tester) async {
    final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(role: TenantRole.cashier), reader);

    expect(find.byKey(const ValueKey('audit-log-denied')), findsOne);
    expect(reader.queries, isEmpty);
  });

  testWidgets('the trail pages forward and back', (tester) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _staffEvent(auditId: 'aud_1'),
        _staffEvent(auditId: 'aud_2'),
        _staffEvent(auditId: 'aud_3'),
      ]);

    await _pump(tester, _controller(), reader, pageSize: 2);

    expect(find.byKey(const ValueKey('audit-log-entry-aud_1')), findsOne);
    expect(find.byKey(const ValueKey('audit-log-entry-aud_3')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('audit-log-next')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('audit-log-entry-aud_3')), findsOne);
    expect(reader.queries.last.startAfterDocumentId, 'aud_2');

    await tester.tap(find.byKey(const ValueKey('audit-log-previous')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('audit-log-entry-aud_1')), findsOne);
  });

  testWidgets('a record that names nobody hides the page', (tester) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _staffEvent(
          overrides: <String, Object?>{'actorUid': null, 'targetUid': null},
        ),
      ]);

    await _pump(tester, _controller(), reader);

    expect(find.byKey(const ValueKey('audit-log-failure')), findsOne);
    expect(find.byKey(const ValueKey('audit-log-entry-aud_001')), findsNothing);
  });

  testWidgets('a record that contradicts its own path hides the page', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _staffEvent(overrides: <String, Object?>{'tenantId': 'tenant-b'}),
      ]);

    await _pump(tester, _controller(), reader);

    expect(find.byKey(const ValueKey('audit-log-failure')), findsOne);
  });

  testWidgets('a tenant switch discards an outstanding page', (tester) async {
    final controller = _controller();
    final reader = _Reader.deferred();

    await _pump(tester, controller, reader, settle: false);
    expect(reader.queries.single.collectionPath, 'tenants/tenant-a/audit_logs');

    controller.open(uid: 'admin-a', membership: _membership('tenant-b'));
    await tester.pump();
    expect(reader.queries.last.collectionPath, 'tenants/tenant-b/audit_logs');

    // The first business's page arrives after the switch and is discarded
    // before it can label another business's screen.
    reader.completeFirst(<TenantQueryDocumentSnapshot>[_staffEvent()]);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('audit-log-entry-aud_001')), findsNothing);

    reader.completeFirst(<TenantQueryDocumentSnapshot>[
      _staffEvent(auditId: 'aud_009', tenantId: 'tenant-b'),
    ]);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('audit-log-entry-aud_009')), findsOne);
  });

  group('safe landing entry point', () {
    testWidgets('an owner opens the activity log from the safe landing route', (
      tester,
    ) async {
      final reader = _Reader()
        ..respond(<TenantQueryDocumentSnapshot>[_staffEvent()]);

      await _pumpLanding(tester, reader, role: TenantRole.owner);
      await tester.tap(find.byKey(const ValueKey('view-audit-log')));
      await tester.pumpAndSettle();

      expect(find.text('Activity log'), findsOneWidget);
      expect(find.byKey(const ValueKey('audit-log-entry-aud_001')), findsOne);
    });

    testWidgets('a manager is never offered the route', (tester) async {
      final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);

      await _pumpLanding(tester, reader, role: TenantRole.manager);

      expect(find.byKey(const ValueKey('view-audit-log')), findsNothing);
      // The catalog is still offered, so the absence is the role boundary and
      // not a screen that failed to build.
      expect(find.text('View read-only catalog'), findsOneWidget);
      expect(reader.queries, isEmpty);
    });

    testWidgets('the route stays unreachable while none is supplied', (
      tester,
    ) async {
      final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);

      await _pumpLanding(
        tester,
        reader,
        role: TenantRole.owner,
        supplyRoute: false,
      );

      expect(find.byKey(const ValueKey('view-audit-log')), findsNothing);
    });
  });
}

/// Pumps the production safe landing route exactly as the composition root
/// configures it: tenancy owns routing and the audit domain decides the roles.
Future<void> _pumpLanding(
  WidgetTester tester,
  _Reader reader, {
  required TenantRole role,
  bool supplyRoute = true,
}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: _controller(role: role),
        child: TenantSafeLandingScreen(
          membership: _membership('tenant-a', role: role),
          reader: reader,
          onSignOut: () async {},
          auditLogRoute: supplyRoute
              ? (reader) => TenantAuditLogScreen(reader: reader)
              : null,
          auditLogRoles: TenantAuditLogRepository.allowedRoles,
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pump(
  WidgetTester tester,
  TenantSessionController controller,
  _Reader reader, {
  int pageSize = 20,
  TenantAuditEventType? eventType,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(1400, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: Scaffold(
          body: TenantAuditLogPanel(
            reader: reader,
            eventType: eventType,
            pageSize: pageSize,
          ),
        ),
      ),
    ),
  );
  if (!settle) return;
  await tester.pump();
  await tester.pump();
}

/// The exact envelope `functions/src/staff/shared.ts` `auditData` creates.
TenantQueryDocumentSnapshot _staffEvent({
  String auditId = 'aud_001',
  String tenantId = 'tenant-a',
  Map<String, Object?>? overrides,
}) {
  final data = <String, Object?>{
    'tenantId': tenantId,
    'eventType': 'staff_invited',
    'actorUid': 'admin-a',
    'targetUid': 'cashier-a',
    'requestId': 'invite-staff-abcdefgh',
    'role': 'cashier',
    'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 9)),
  };
  if (overrides != null) data.addAll(overrides);
  return TenantQueryDocumentSnapshot(
    path: 'tenants/$tenantId/audit_logs/$auditId',
    data: data,
  );
}

/// The exact envelope `functions/src/lifecycle/tenantLifecycle.ts` records for
/// the business to read.
TenantQueryDocumentSnapshot _platformEvent({String auditId = 'aud_002'}) =>
    TenantQueryDocumentSnapshot(
      path: 'tenants/tenant-a/audit_logs/$auditId',
      data: <String, Object?>{
        'tenantId': 'tenant-a',
        'eventType': 'tenant_lifecycle_changed',
        'fromStatus': 'pending',
        'toStatus': 'active',
        'actorType': 'platform_admin',
        'fanoutOperationId': 'op-1',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 9)),
      },
    );

TenantSessionController _controller({TenantRole role = TenantRole.admin}) =>
    TenantSessionController()..open(
      uid: 'admin-a',
      membership: _membership('tenant-a', role: role),
    );

TenantMembership _membership(
  String tenantId, {
  TenantRole role = TenantRole.admin,
}) => TenantMembership(
  tenantId: tenantId,
  tenantName: tenantId,
  tenantSlug: tenantId,
  role: role,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  isOwner: role == TenantRole.owner,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 8, 1),
  updatedAt: DateTime.utc(2026, 8, 1),
  serverCanAccess: true,
  canonicalMembershipExists: true,
  canonicalTenantExists: true,
);

final class _Reader implements TenantDataReader {
  _Reader({this.staffNames = const <String, String>{}}) : _defer = false;
  _Reader.deferred() : staffNames = const <String, String>{}, _defer = true;

  final Map<String, String> staffNames;
  final bool _defer;
  List<TenantQueryDocumentSnapshot> _page =
      const <TenantQueryDocumentSnapshot>[];
  final List<Completer<List<TenantQueryDocumentSnapshot>>> _pending =
      <Completer<List<TenantQueryDocumentSnapshot>>>[];
  final List<TenantCollectionQuery> queries = <TenantCollectionQuery>[];
  final List<String> documentPaths = <String>[];

  void respond(List<TenantQueryDocumentSnapshot> page) => _page = page;

  void completeFirst(List<TenantQueryDocumentSnapshot> page) {
    if (_pending.isEmpty) return;
    _pending.removeAt(0).complete(page);
  }

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    documentPaths.add(path);
    final uid = path.split('/').last;
    final name = staffNames[uid];
    return name == null
        ? null
        : TenantDocumentSnapshot(
            path: path,
            data: <String, Object?>{'uid': uid, 'name': name},
          );
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) {
    queries.add(query);
    if (_defer) {
      final completer = Completer<List<TenantQueryDocumentSnapshot>>();
      _pending.add(completer);
      return completer.future;
    }
    final cursor = query.startAfterDocumentId;
    final matches = <TenantQueryDocumentSnapshot>[];
    for (final snapshot in _page) {
      final id = snapshot.path.split('/').last;
      if (cursor != null && id.compareTo(cursor) <= 0) continue;
      if (query.equalityFilters.entries.any(
        (filter) => snapshot.data[filter.key] != filter.value,
      )) {
        continue;
      }
      matches.add(snapshot);
      if (matches.length >= query.limit) break;
    }
    return Future<List<TenantQueryDocumentSnapshot>>.value(matches);
  }
}
