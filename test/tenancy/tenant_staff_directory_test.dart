import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/status.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/landing_drawer.dart';

void main() {
  group('strict staff summaries', () {
    test('decodes canonical active, pending, and optional display fields', () {
      final owner = TenantStaffSummary.fromSnapshot(
        _staffSnapshot(
          'tenant-a',
          'owner-a',
          role: TenantRole.owner,
          name: '',
          phone: '',
        ),
        ownerUid: 'owner-a',
      );
      final pending = TenantStaffSummary.fromSnapshot(
        _staffSnapshot(
          'tenant-a',
          'cashier-a',
          status: MembershipStatus.pending,
          invitationStatus: TenantStaffInvitationStatus.sent,
        ),
        ownerUid: 'owner-a',
      );

      expect(owner.isOwner, isTrue);
      expect(owner.displayName, 'owner-a@example.test');
      expect(owner.name, isNull);
      expect(owner.phone, isNull);
      expect(pending.status, MembershipStatus.pending);
      expect(pending.invitationStatus, TenantStaffInvitationStatus.sent);
    });

    test('rejects mismatched UIDs and malformed owner projections', () {
      expect(
        () => TenantStaffSummary.fromSnapshot(
          _staffSnapshot('tenant-a', 'staff-a', projectedUid: 'staff-b'),
          ownerUid: 'owner-a',
        ),
        throwsFormatException,
      );
      expect(
        () => TenantStaffSummary.fromSnapshot(
          _staffSnapshot('tenant-a', 'staff-a', role: TenantRole.owner),
          ownerUid: 'owner-a',
        ),
        throwsFormatException,
      );
      expect(
        () => TenantStaffSummary.fromSnapshot(
          _staffSnapshot('tenant-a', 'owner-a', role: TenantRole.admin),
          ownerUid: 'owner-a',
        ),
        throwsFormatException,
      );
    });

    test('rejects unknown fields and inconsistent invitation state', () {
      final unknownRole = _staffData('staff-a')..['role'] = 'supervisor';
      final badEmail = _staffData('staff-a')
        ..['email'] = 'Staff-A@Example.test';
      final badInvitation = _staffData('staff-a')
        ..['status'] = 'inactive'
        ..['invitationStatus'] = 'sent';

      for (final data in [unknownRole, badEmail, badInvitation]) {
        expect(
          () => TenantStaffSummary.fromSnapshot(
            TenantQueryDocumentSnapshot(
              path: 'tenants/tenant-a/staff/staff-a',
              data: data,
            ),
            ownerUid: 'owner-a',
          ),
          throwsFormatException,
        );
      }
    });
  });

  group('staff repository pagination', () {
    test(
      'derives bounded staff pages and advances the document cursor',
      () async {
        final reader = _StaffReader(
          queryHandler: (_) async => [
            _staffSnapshot('tenant-a', 'owner-a', role: TenantRole.owner),
            _staffSnapshot('tenant-a', 'staff-a'),
            _staffSnapshot('tenant-a', 'staff-b'),
          ],
        );
        final repository = TenantStaffDirectoryRepository(
          session: _session('tenant-a'),
          reader: reader,
        );

        final page = await repository.loadPage(pageSize: 2);

        expect(reader.documentPaths, [
          'tenants/tenant-a',
          'tenants/tenant-a/staff/owner-a',
        ]);
        expect(reader.queries.single.collectionPath, 'tenants/tenant-a/staff');
        expect(reader.queries.single.limit, 3);
        expect(page.items.map((staff) => staff.uid), ['owner-a', 'staff-a']);
        expect(page.hasMore, isTrue);
        expect(page.nextCursor, 'staff-a');

        reader.queryHandler = (query) async {
          expect(query.startAfterDocumentId, 'staff-a');
          return [_staffSnapshot('tenant-a', 'staff-b')];
        };
        final lastPage = await repository.loadPage(
          pageSize: 2,
          cursor: page.nextCursor,
        );
        expect(lastPage.items.single.uid, 'staff-b');
        expect(lastPage.hasMore, isFalse);
        expect(lastPage.nextCursor, isNull);
      },
    );

    test('rejects malformed roots and cross-tenant staff results', () async {
      final badRootReader = _StaffReader(
        rootPathOverride: 'tenants/tenant-b',
        queryHandler: (_) async => const [],
      );
      await expectLater(
        TenantStaffDirectoryRepository(
          session: _session('tenant-a'),
          reader: badRootReader,
        ).loadPage(),
        throwsA(isA<TenantScopeViolation>()),
      );

      final crossTenantReader = _StaffReader(
        queryHandler: (_) async => [_staffSnapshot('tenant-b', 'staff-a')],
      );
      await expectLater(
        TenantStaffDirectoryRepository(
          session: _session('tenant-a'),
          reader: crossTenantReader,
        ).loadPage(),
        throwsA(isA<TenantScopeViolation>()),
      );
    });

    test(
      'search and filters use the dedicated typed query and opaque cursor',
      () async {
        late TenantStaffDirectoryQuery captured;
        final reader = _StaffReader(
          queryHandler: (_) async => const [],
          staffQueryHandler: (query) async {
            captured = query;
            return <TenantQueryDocumentSnapshot>[
              _staffSnapshot('tenant-a', 'staff-a'),
              _staffSnapshot('tenant-a', 'staff-b'),
            ];
          },
        );
        final page =
            await TenantStaffDirectoryRepository(
              session: _session('tenant-a'),
              reader: reader,
              queryReader: reader,
            ).queryPage(
              pageSize: 1,
              search: 'Staff',
              role: TenantRole.cashier,
              status: MembershipStatus.active,
            );

        expect(captured.collectionPath, 'tenants/tenant-a/staff');
        expect(captured.searchPrefix, 'staff');
        expect(captured.role, 'cashier');
        expect(captured.status, 'active');
        expect(captured.limit, 2);
        expect(page.items.single.uid, 'staff-a');
        expect(page.nextCursor, isNot(anyOf(isNull, 'staff-a')));
      },
    );
  });

  group('guarded staff directory', () {
    testWidgets('an owner inherits admin access through the safe landing', (
      tester,
    ) async {
      final controller = TenantSessionController()
        ..open(
          uid: 'owner-a',
          membership: _membership('tenant-a', role: TenantRole.owner),
        );
      final reader = _StaffReader(
        queryHandler: (_) async => [
          _staffSnapshot(
            'tenant-a',
            'owner-a',
            role: TenantRole.owner,
            name: 'Owner Person',
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: TenantSessionScope(
            controller: controller,
            child: TenantSafeLandingScreen(
              membership: _membership('tenant-a', role: TenantRole.owner),
              reader: reader,
              onSignOut: () async {},
            ),
          ),
        ),
      );
      await tester.pump();

      await openLandingDrawer(tester);
      await tester.tap(find.text('Staff'));
      await tester.pumpAndSettle();

      expect(find.text('User Management'), findsOneWidget);
      expect(find.text('Owner Person'), findsOneWidget);
      // Role and standing used to be one hyphenated string, `owner - active`,
      // then a chip each. Step 6's sweep makes standing the record's one
      // `RecordStatus` and role a `RecordAttribute` beside it. The facts
      // asserted are the same two; only the rendering moved, twice.
      expect(find.byKey(const ValueKey('staff-role-owner-a')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('staff-status-owner-a')),
        findsOneWidget,
      );
      expect(find.text('Owner'), findsWidgets);
      expect(find.text('Active'), findsWidgets);
      // **The key rather than the words, since 2026-08-28.** Inviting moved to
      // the toolbar as a glyph, so its label is a semantic one now; what is
      // being asserted here is unchanged - that an owner is offered it.
      expect(
        find.byKey(const ValueKey('invite-staff-open')),
        findsOneWidget,
      );
      // Role is a labelled key-value line rather than a badge, because it is
      // not one of §2.1's five statuses and a list where two things wear a
      // badge has neither of them meaning anything.
      //
      // **Uppercased since 2026-08-23**: a record's attribute key is
      // `label.eyebrow` now, which is the export's own treatment and §2.2's
      // one permitted uppercase role. The word is unchanged.
      expect(find.text('Role'), findsWidgets);

      // Step 4: standing is one of design.md §2.1's five statuses rather than a
      // chip whose colour was `colors.error` or nothing. Active is `ok`.
      final standing = tester.widget<StatusBadge>(
        find.byKey(const ValueKey('staff-status-owner-a')),
      );
      expect(standing.status, AppStatus.ok);
      // The badge announces a sentence and shows a word, because "Active" on
      // its own is not what a screen reader should read out of a staff row.
      // Step 11: the word is the shopkeeper's rather than the wire's, and the
      // announcement names the record it is a standing of.
      expect(standing.semanticLabel, 'Membership: Active');
      // Step 6: one key addresses the record whichever of §4.3's three forms
      // the band resolved to, where this screen used to key a card and a table
      // row separately.
      expect(
        find.byKey(const ValueKey('staff-record-owner-a')),
        findsOneWidget,
      );
    });

    testWidgets('a pending member states an invitation, and others do not', (
      tester,
    ) async {
      // The screen used to draw a second `StatusBadge` for the invitation. A
      // record carries one standing, and the one that survives is the one that
      // decides what a person can do - so the invitation is an attribute, and
      // only a pending member has one to state.
      final controller = TenantSessionController()
        ..open(uid: 'admin-a', membership: _membership('tenant-a'));
      final reader = _StaffReader(
        queryHandler: (_) async => [
          _staffSnapshot('tenant-a', 'owner-a', role: TenantRole.owner),
          _staffSnapshot(
            'tenant-a',
            'staff-a',
            name: 'Pending Person',
            status: MembershipStatus.pending,
            invitationStatus: TenantStaffInvitationStatus.sent,
          ),
        ],
      );
      await tester.pumpWidget(
        _staffApp(controller: controller, reader: reader),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('staff-invitation-staff-a')),
        findsOneWidget,
      );
      expect(find.text('Invitation: Sent'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('staff-invitation-owner-a')),
        findsNothing,
      );
      // Exactly one badge per member, and never two.
      expect(find.byType(StatusBadge), findsExactly(2));
    });

    testWidgets('a member with nothing to do carries no actions at all', (
      tester,
    ) async {
      // A manager may read this directory and change nothing, so `ActionSet`
      // gets an empty list rather than a control that does nothing - which is
      // the same check the old trailing slot made by returning null.
      final controller = TenantSessionController()
        ..open(
          uid: 'manager-a',
          membership: _membership('tenant-a', role: TenantRole.manager),
        );
      final reader = _StaffReader(
        queryHandler: (_) async => [
          _staffSnapshot(
            'tenant-a',
            'owner-a',
            role: TenantRole.owner,
            name: 'Owner Person',
          ),
        ],
      );
      await tester.pumpWidget(
        _staffApp(controller: controller, reader: reader),
      );
      await tester.pumpAndSettle();

      expect(find.text('Owner Person'), findsOneWidget);
      expect(find.byKey(const ValueKey('edit-staff-owner-a')), findsNothing);
      expect(find.byTooltip('More actions'), findsNothing);
      // **And the page says so, which it did not before.** The heading read
      // `Read-only staff directory` for every role, including the owner it then
      // offered `Invite staff` to. A page's standing is §2.1's, and a manager
      // who can change nothing here is the case it is true of.
      final notice = tester.widget<Callout>(
        find.byKey(const ValueKey('staff-directory-read-only')),
      );
      expect(notice.status, AppStatus.info);
      expect(notice.title, 'Read-only staff directory');
    });

    testWidgets('a session that can change something is told nothing', (
      tester,
    ) async {
      // The other half, and the defect this replaced: an owner was told the
      // directory was read-only and then offered an invitation form two lines
      // under it. A standing that is true of every session is not a standing.
      final controller = TenantSessionController()
        ..open(
          uid: 'owner-a',
          membership: _membership('tenant-a', role: TenantRole.owner),
        );
      final reader = _StaffReader(
        queryHandler: (_) async => [
          _staffSnapshot(
            'tenant-a',
            'owner-a',
            role: TenantRole.owner,
            name: 'Owner Person',
          ),
        ],
      );
      await tester.pumpWidget(
        _staffApp(controller: controller, reader: reader),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('staff-directory-read-only')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('invite-staff-open')), findsOne);
    });

    testWidgets('a cashier is denied without starting any reads', (
      tester,
    ) async {
      final controller = TenantSessionController()
        ..open(
          uid: 'cashier-a',
          membership: _membership('tenant-a', role: TenantRole.cashier),
        );
      final reader = _StaffReader(queryHandler: (_) async => const []);

      await tester.pumpWidget(
        _staffApp(controller: controller, reader: reader),
      );

      expect(find.text('You do not have access to this page.'), findsOneWidget);
      expect(reader.documentPaths, isEmpty);
      expect(reader.queries, isEmpty);
    });

    testWidgets('a tenant switch discards an outstanding staff page', (
      tester,
    ) async {
      final controller = TenantSessionController()
        ..open(uid: 'admin-a', membership: _membership('tenant-a'));
      final pending = <String, Completer<List<TenantQueryDocumentSnapshot>>>{};
      final reader = _StaffReader(
        queryHandler: (query) {
          final completer = Completer<List<TenantQueryDocumentSnapshot>>();
          pending[query.collectionPath] = completer;
          return completer.future;
        },
      );
      await tester.pumpWidget(
        _staffApp(controller: controller, reader: reader),
      );
      expect(pending, contains('tenants/tenant-a/staff'));

      controller.open(uid: 'admin-a', membership: _membership('tenant-b'));
      await tester.pump();
      expect(pending, contains('tenants/tenant-b/staff'));

      pending['tenants/tenant-a/staff']!.complete([
        _staffSnapshot('tenant-a', 'staff-a', name: 'Stale Staff'),
      ]);
      await tester.pump();
      expect(find.text('Stale Staff'), findsNothing);

      pending['tenants/tenant-b/staff']!.complete([
        _staffSnapshot('tenant-b', 'staff-b', name: 'Current Staff'),
      ]);
      await tester.pump();
      await tester.pump();
      expect(find.text('Current Staff'), findsOneWidget);
      expect(find.text('Stale Staff'), findsNothing);
    });
  });
}

final class _StaffReader
    implements TenantDataReader, TenantStaffDirectoryQueryReader {
  _StaffReader({
    required this.queryHandler,
    this.staffQueryHandler,
    this.rootPathOverride,
  });

  Future<List<TenantQueryDocumentSnapshot>> Function(TenantCollectionQuery)
  queryHandler;
  final Future<List<TenantQueryDocumentSnapshot>> Function(
    TenantStaffDirectoryQuery,
  )?
  staffQueryHandler;
  final String? rootPathOverride;
  final List<String> documentPaths = [];
  final List<TenantCollectionQuery> queries = [];
  final List<TenantStaffDirectoryQuery> staffQueries = [];

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    documentPaths.add(path);
    if (RegExp(r'^tenants/[^/]+$').hasMatch(path)) {
      final tenantId = path.split('/').last;
      return TenantDocumentSnapshot(
        path: rootPathOverride ?? path,
        data: {'ownerUid': 'owner-${tenantId.split('-').last}'},
      );
    }
    final ownerMatch = RegExp(
      r'^tenants/[^/]+/staff/(owner-[^/]+)$',
    ).firstMatch(path);
    if (ownerMatch == null) return null;
    final ownerUid = ownerMatch.group(1)!;
    return TenantDocumentSnapshot(
      path: path,
      data: _staffData(ownerUid)
        ..['role'] = TenantRole.owner.wireValue
        ..['status'] = MembershipStatus.active.wireValue
        ..['invitationStatus'] = TenantStaffInvitationStatus.accepted.wireValue
        ..['name'] = 'Owner Person'
        ..['email'] = '$ownerUid@example.test',
    );
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) {
    queries.add(query);
    return queryHandler(query);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> queryTenantStaff(
    TenantStaffDirectoryQuery query,
  ) {
    staffQueries.add(query);
    final handler = staffQueryHandler;
    if (handler != null) return handler(query);
    return queryHandler(
      TenantCollectionQuery.forTesting(
        collectionPath: query.collectionPath,
        limit: query.limit,
        startAfterDocumentId: query.startAfter?.documentId,
        equalityFilters: <String, Object?>{
          if (query.role != null) 'role': query.role,
          if (query.status != null) 'status': query.status,
        },
      ),
    );
  }
}

Widget _staffApp({
  required TenantSessionController controller,
  required TenantDataReader reader,
}) => MaterialApp(
  home: TenantSessionScope(
    controller: controller,
    child: Scaffold(body: TenantStaffDirectoryPanel(reader: reader)),
  ),
);

TenantSession _session(String tenantId) => TenantSession.active(
  uid: 'admin-a',
  tenantId: tenantId,
  role: TenantRole.admin,
);

TenantQueryDocumentSnapshot _staffSnapshot(
  String tenantId,
  String uid, {
  String? projectedUid,
  TenantRole role = TenantRole.cashier,
  MembershipStatus status = MembershipStatus.active,
  TenantStaffInvitationStatus invitationStatus =
      TenantStaffInvitationStatus.accepted,
  String name = 'Staff Person',
  String phone = '+254700000000',
}) => TenantQueryDocumentSnapshot(
  path: 'tenants/$tenantId/staff/$uid',
  data: _staffData(projectedUid ?? uid)
    ..['role'] = role.wireValue
    ..['status'] = status.wireValue
    ..['invitationStatus'] = invitationStatus.wireValue
    ..['name'] = name
    ..['phone'] = phone,
);

Map<String, Object?> _staffData(String uid) => <String, Object?>{
  'uid': uid,
  'email': '$uid@example.test',
  'name': 'Staff Person',
  'phone': '+254700000000',
  'role': 'cashier',
  'status': 'active',
  'invitationStatus': 'accepted',
  'searchName': 'staff person',
  'searchPrefixes': <String>['st', 'sta', 'staf', 'staff'],
};

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
  createdAt: DateTime.utc(2026, 7, 29),
  updatedAt: DateTime.utc(2026, 7, 29),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);
