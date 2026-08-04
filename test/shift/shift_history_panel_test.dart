import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/shift/shift.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

const String _deviceA = 'dev-0123456789abcdef0123456789abcdef';
const String _businessDate = '2026-07-31';

void main() {
  testWidgets('a cashier sees counted cash, recorded sales, and the difference', (
    tester,
  ) async {
    final controller = _controller(TenantRole.cashier);
    final reader = _Reader()
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[
        _snapshot('shift-b'),
        _snapshot(
          'shift-a',
          overrides: <String, Object?>{'closingCashMinor': 90000},
        ),
      ]);

    await _pumpPanel(tester, controller, reader);

    expect(find.byKey(const ValueKey('shift-history-entry-shift-b')), findsOne);
    _expectText(tester, 'shift-history-counted-shift-b', 'Counted cash: 1250.00');
    _expectText(
      tester,
      'shift-history-sales-shift-b',
      'Recorded sales: 987.50 over 3 transactions',
    );
    _expectText(
      tester,
      'shift-history-variance-shift-b',
      'Counted cash is over by 262.50.',
    );
    _expectText(
      tester,
      'shift-history-variance-shift-a',
      'Counted cash is short by 87.50.',
    );
    // Only management may look beyond its own shifts.
    expect(find.byKey(const ValueKey('shift-history-scope')), findsNothing);
    expect(
      reader.queries.single.equalityFilters,
      <String, Object?>{'status': 'closed', 'staffId': 'user-a'},
    );
  });

  testWidgets('a shift that sold once is counted in the singular', (
    tester,
  ) async {
    // The same agreement rule the shift panel and every reporting surface hold.
    final reader = _Reader()
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[
        _snapshot(
          'shift-a',
          overrides: <String, Object?>{'transactionCount': 1},
        ),
      ]);

    await _pumpPanel(tester, _controller(TenantRole.manager), reader);

    _expectText(
      tester,
      'shift-history-sales-shift-a',
      'Recorded sales: 987.50 over 1 transaction',
    );
  });

  testWidgets('a shift closed without a summary states that plainly', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[
        _snapshot(
          'shift-a',
          overrides: <String, Object?>{
            'totalSalesMinor': null,
            'totalSales': null,
            'transactionCount': null,
          },
        ),
      ]);

    await _pumpPanel(tester, _controller(TenantRole.cashier), reader);

    _expectText(
      tester,
      'shift-history-no-summary-shift-a',
      'No closing summary was recorded for this shift.',
    );
    expect(
      find.byKey(const ValueKey('shift-history-variance-shift-a')),
      findsNothing,
    );
    _expectText(tester, 'shift-history-counted-shift-a', 'Counted cash: 1250.00');
  });

  testWidgets('a manager may page every cashier and label its own shifts', (
    tester,
  ) async {
    final controller = _controller(TenantRole.manager);
    final reader = _Reader()
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[
        _snapshot('shift-b', overrides: <String, Object?>{'staffId': 'user-b'}),
        _snapshot('shift-a'),
      ]);

    await _pumpPanel(tester, controller, reader);
    expect(
      reader.queries.single.equalityFilters,
      <String, Object?>{'status': 'closed', 'staffId': 'user-a'},
    );

    await tester.tap(find.text('Every cashier'));
    await tester.pump();
    await tester.pump();

    expect(reader.queries.length, 2);
    expect(reader.queries.last.equalityFilters, <String, Object?>{
      'status': 'closed',
    });
    // A resolved colleague keeps the UID beside the name; an unresolved one
    // falls back to the UID alone.
    expect(find.text('2026-07-31 - Brian (user-b)'), findsOne);
    expect(find.text('2026-07-31 - You'), findsOne);
  });

  testWidgets('an unreadable staff record leaves the UID in place', (
    tester,
  ) async {
    final reader = _Reader(deniedStaff: true)
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[
        _snapshot('shift-b', overrides: <String, Object?>{'staffId': 'user-b'}),
      ]);

    await _pumpPanel(tester, _controller(TenantRole.manager), reader);
    await tester.tap(find.text('Every cashier'));
    await tester.pump();
    await tester.pump();

    expect(find.text('2026-07-31 - user-b'), findsOne);
    expect(find.byKey(const ValueKey('shift-history-failure')), findsNothing);
  });

  testWidgets('paging forward asks for the next cursor only', (tester) async {
    final controller = _controller(TenantRole.cashier);
    final reader = _Reader()
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[
        _snapshot('shift-c'),
        _snapshot('shift-b'),
        _snapshot('shift-a'),
      ]);

    await _pumpPanel(tester, controller, reader, pageSize: 2);
    expect(find.byKey(const ValueKey('shift-history-entry-shift-a')), findsNothing);
    expect(find.byKey(const ValueKey('shift-history-previous')), findsNothing);

    // The paging controls sit below the cards, so the list must scroll to
    // them before they are built.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('shift-history-next')),
      200,
    );
    await tester.tap(find.byKey(const ValueKey('shift-history-next')));
    await tester.pump();
    await tester.pump();

    expect(reader.queries.last.startAfterDocumentId, 'shift-b');
    expect(reader.queries.last.descending, isTrue);
    expect(find.byKey(const ValueKey('shift-history-entry-shift-a')), findsOne);
    expect(find.byKey(const ValueKey('shift-history-previous')), findsOne);
  });

  testWidgets('a tenant switch discards the outstanding page', (tester) async {
    final controller = _controller(TenantRole.cashier);
    final reader = _Reader(deferred: true)
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[
        _snapshot('shift-a'),
      ])
      ..respond('tenants/tenant-b/shifts', <TenantQueryDocumentSnapshot>[
        _snapshot('shift-b', tenantId: 'tenant-b'),
      ]);

    await _pumpPanel(tester, controller, reader, settle: false);
    await tester.pump();
    expect(reader.pending.length, 1);

    controller.open(uid: 'user-a', membership: _membership('tenant-b'));
    await tester.pump();
    expect(reader.pending.length, 2);

    // The first business answers after the switch; its page must be discarded.
    reader.completeFirst();
    await tester.pump();
    expect(find.byKey(const ValueKey('shift-history-entry-shift-a')), findsNothing);

    reader.completeFirst();
    await tester.pump();
    expect(find.byKey(const ValueKey('shift-history-entry-shift-b')), findsOne);
    expect(find.byKey(const ValueKey('shift-history-entry-shift-a')), findsNothing);
  });

  testWidgets('a closed shift links to the sales it recorded', (tester) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[
        _snapshot('shift-a'),
      ])
      ..respond('tenants/tenant-a/sales', <TenantQueryDocumentSnapshot>[]);

    await _pumpPanel(tester, _controller(TenantRole.cashier), reader);
    await tester.tap(
      find.byKey(const ValueKey('shift-history-sales-link-shift-a')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Shift sales'), findsOne);
    // The sales page is scoped to this exact shift, and carries the figures
    // the shift recorded rather than reading them again.
    expect(reader.queries.last.equalityFilters, <String, Object?>{
      'shiftId': 'shift-a',
    });
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sale-history-recorded')))
          .data,
      'Recorded: 987.50 over 3 transactions. Counted cash was 1250.00.',
    );
  });

  testWidgets('the cashier reaches its own recent sales', (tester) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[])
      ..respond('tenants/tenant-a/sales', <TenantQueryDocumentSnapshot>[]);

    await _pumpPanel(tester, _controller(TenantRole.cashier), reader);
    await tester.tap(find.byKey(const ValueKey('shift-history-own-sales')));
    await tester.pumpAndSettle();

    expect(find.text('My recent sales'), findsOne);
    expect(reader.queries.last.equalityFilters, <String, Object?>{
      'soldById': 'user-a',
    });
  });

  testWidgets('a corrected shift says so and opens its own corrections', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[
        _snapshot('shift-a', overrides: _amended()),
      ])
      ..respond(
        'tenants/tenant-a/shift_amendments',
        <TenantQueryDocumentSnapshot>[_amendmentSnapshot()],
      );

    await _pumpPanel(tester, _controller(TenantRole.manager), reader);

    // Said before the link, and about the figures on this row rather than in
    // general: the recorded sales above are the corrected ones.
    _expectText(
      tester,
      'shift-history-amended-shift-a',
      'The recorded sales above were corrected 2 times after this shift '
          'closed, to the total its own sales prove. The counted cash was not '
          'changed. Last corrected 2026-07-31 19:00 UTC.',
    );
    expect(
      find.byKey(const ValueKey('shift-history-corrections-denied-shift-a')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('shift-history-corrections-link-shift-a')),
    );
    await tester.pumpAndSettle();

    // The trail opens narrowed to this exact shift, and says which one it is
    // showing rather than implying it is the whole business's record.
    expect(find.text('Corrections to shift shift-a'), findsOne);
    expect(
      reader.queries.last.collectionPath,
      'tenants/tenant-a/shift_amendments',
    );
    expect(reader.queries.last.equalityFilters, <String, Object?>{
      'shiftId': 'shift-a',
    });
    expect(find.byKey(const ValueKey('shift-amendment-sm_abc')), findsOne);
  });

  testWidgets('a shift nobody corrected offers nothing about corrections', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[
        _snapshot('shift-a'),
      ]);

    await _pumpPanel(tester, _controller(TenantRole.manager), reader);

    expect(
      find.byKey(const ValueKey('shift-history-amended-shift-a')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('shift-history-corrections-link-shift-a')),
      findsNothing,
    );
    // The row it does offer is unaffected.
    expect(
      find.byKey(const ValueKey('shift-history-sales-link-shift-a')),
      findsOne,
    );
  });

  testWidgets('one correction is counted in the singular', (tester) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[
        _snapshot(
          'shift-b',
          overrides: <String, Object?>{
            ..._amended(),
            'summaryAmendmentCount': 1,
            // A correction whose instant the server never recorded still says
            // what it did.
            'summaryAmendedAt': null,
          },
        ),
      ]);

    await _pumpPanel(tester, _controller(TenantRole.admin), reader);

    _expectText(
      tester,
      'shift-history-amended-shift-b',
      'The recorded sales above were corrected once after this shift closed, '
          'to the total its own sales prove. The counted cash was not changed. '
          'The time of the last correction was not recorded.',
    );
  });

  testWidgets('a cashier is told their shift was corrected and why they cannot '
      'read the trail', (tester) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[
        _snapshot('shift-a', overrides: _amended()),
      ]);

    await _pumpPanel(tester, _controller(TenantRole.cashier), reader);

    // Their own figures were rewritten, so hiding that would be worse than the
    // link they may not have: the shift document they can already read says so.
    expect(
      find.byKey(const ValueKey('shift-history-amended-shift-a')),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('shift-history-corrections-link-shift-a')),
      findsNothing,
    );
    _expectText(
      tester,
      'shift-history-corrections-denied-shift-a',
      'The record of who corrected it, and why, is available to managers, '
          'administrators, and owners.',
    );
  });

  testWidgets('no session renders the denied state and starts no load', (
    tester,
  ) async {
    final controller = TenantSessionController();
    final reader = _Reader();

    await _pumpPanel(tester, controller, reader);

    expect(find.byKey(const ValueKey('shift-history-denied')), findsOne);
    expect(reader.queries, isEmpty);
  });

  testWidgets('a failed page hides the underlying error', (tester) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[
        // A page that answers outside the requested business fails closed.
        _snapshot('shift-a', responsePath: 'tenants/tenant-b/shifts/shift-a'),
      ]);

    await _pumpPanel(tester, _controller(TenantRole.cashier), reader);

    expect(find.byKey(const ValueKey('shift-history-failure')), findsOne);
    expect(find.textContaining('tenant-b'), findsNothing);
  });

}

Future<void> _pumpPanel(
  WidgetTester tester,
  TenantSessionController controller,
  _Reader reader, {
  int pageSize = 20,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: Scaffold(
          body: TenantShiftHistoryPanel(reader: reader, pageSize: pageSize),
        ),
      ),
    ),
  );
  if (!settle) return;
  await tester.pump();
  await tester.pump();
}

TenantSessionController _controller(TenantRole role) =>
    TenantSessionController()
      ..open(uid: 'user-a', membership: _membership('tenant-a', role: role));

TenantMembership _membership(String tenantId, {TenantRole role = TenantRole.cashier}) =>
    TenantMembership(
      tenantId: tenantId,
      tenantName: tenantId,
      tenantSlug: tenantId,
      role: role,
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

void _expectText(WidgetTester tester, String key, String value) {
  expect(tester.widget<Text>(find.byKey(ValueKey(key))).data, value);
}

TenantQueryDocumentSnapshot _snapshot(
  String shiftId, {
  String tenantId = 'tenant-a',
  String? responsePath,
  Map<String, Object?>? overrides,
}) {
  final data = <String, Object?>{
    'shiftId': shiftId,
    'tenantId': tenantId,
    'staffId': 'user-a',
    'deviceId': _deviceA,
    'businessDate': _businessDate,
    'status': 'closed',
    'startTime': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 6)),
    'endTime': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 18)),
    'closingCashMinor': 125000,
    'closingCash': 1250,
    'totalSalesMinor': 98750,
    'totalSales': 987.5,
    'transactionCount': 3,
  };
  if (overrides != null) data.addAll(overrides);
  data.removeWhere((key, value) => value == null);
  return TenantQueryDocumentSnapshot(
    path: responsePath ?? 'tenants/$tenantId/shifts/$shiftId',
    data: data,
  );
}

/// The four fields `amendShiftSummary` leaves on a shift it corrected. The count
/// is 2 so the plural cannot pass by accident.
Map<String, Object?> _amended() => <String, Object?>{
  'summaryAmendmentId': 'sm_abc',
  'summaryAmendedGeneration': 'generation-one',
  'summaryAmendmentCount': 2,
  'summaryAmendedAt': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 19)),
};

/// One `shift_amendments` record the trail's own strict read model accepts, so
/// the narrowed page this panel opens renders rather than failing closed.
TenantQueryDocumentSnapshot _amendmentSnapshot() => TenantQueryDocumentSnapshot(
  path: 'tenants/tenant-a/shift_amendments/sm_abc',
  data: <String, Object?>{
    'amendmentId': 'sm_abc',
    'tenantId': 'tenant-a',
    'shiftId': 'shift-a',
    'staffId': 'user-a',
    'businessDate': _businessDate,
    'sourceType': 'reconciliation_shift_variance',
    'expectationId': 'exp-a',
    'expectationGeneration': 'generation-one',
    'previousTotalSalesMinor': 98750,
    'previousTransactionCount': 3,
    'previousRepresentationsAgreed': true,
    'totalSalesMinor': 98250,
    'transactionCount': 3,
    'salesVarianceMinor': 500,
    'transactionVariance': 0,
    'clearedAnomalyId': null,
    'mutatesCountedCash': false,
    'reason': 'A late sale arrived after the shift closed',
    'actorUid': 'user-a',
    'requestId': 'amend-shift-abcdefgh',
    'createdAt': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 19)),
  },
);

final class _Reader implements TenantDataReader {
  _Reader({this.deferred = false, this.deniedStaff = false});

  final bool deferred;

  /// Stands in for the narrowed canonical staff read: a cashier, and any role
  /// the rule refuses, gets no name and must still see the page.
  final bool deniedStaff;
  final Map<String, List<TenantQueryDocumentSnapshot>> _pages =
      <String, List<TenantQueryDocumentSnapshot>>{};
  final List<TenantCollectionQuery> queries = <TenantCollectionQuery>[];
  final List<Completer<List<TenantQueryDocumentSnapshot>>> pending =
      <Completer<List<TenantQueryDocumentSnapshot>>>[];
  final List<List<TenantQueryDocumentSnapshot>> _deferredResults =
      <List<TenantQueryDocumentSnapshot>>[];

  void respond(String path, List<TenantQueryDocumentSnapshot> page) =>
      _pages[path] = page;

  /// Completes the oldest outstanding page, mimicking a slow first business.
  void completeFirst() {
    if (pending.isEmpty) return;
    pending.removeAt(0).complete(_deferredResults.removeAt(0));
  }

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    if (deniedStaff) throw StateError('permission-denied');
    final uid = path.split('/').last;
    return path.startsWith('tenants/tenant-a/staff/') && uid != 'user-a'
        ? TenantDocumentSnapshot(
            path: path,
            data: <String, Object?>{'uid': uid, 'name': 'Brian'},
          )
        : null;
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) {
    queries.add(query);
    final all = _pages[query.collectionPath] ?? const [];
    final cursor = query.startAfterDocumentId;
    final matches = <TenantQueryDocumentSnapshot>[];
    for (final snapshot in all) {
      final id = snapshot.path.split('/').last;
      if (cursor != null && id.compareTo(cursor) >= 0) continue;
      final matchesFilters = query.equalityFilters.entries.every(
        (filter) => snapshot.data[filter.key] == filter.value,
      );
      if (!matchesFilters) continue;
      matches.add(snapshot);
      if (matches.length >= query.limit) break;
    }
    if (!deferred) return Future.value(matches);
    final completer = Completer<List<TenantQueryDocumentSnapshot>>();
    pending.add(completer);
    _deferredResults.add(matches);
    return completer.future;
  }
}
