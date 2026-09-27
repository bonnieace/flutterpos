import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:uzapay_pos/reporting/reporting.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:uzapay_pos/ui/record_list.dart';
import 'package:uzapay_pos/ui/scaffold.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/text.dart';

void main() {
  testWidgets('a correction is reported as the server recorded it', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[_amendment('amend_abc')]);

    await _pump(tester, _controller(), reader);

    expect(
      _text(tester, 'shift-amendment-subject-amend_abc'),
      'Shift shift-1 on 2026-08-04',
    );
    // The record is the correction, so the correction's own document ID is its
    // second identifying line. It used to be the last clause of the evidence
    // sentence.
    expect(
      _text(tester, 'shift-amendment-record-amend_abc'),
      'Recorded as amend_abc',
    );
    // Two figures, two columns. One assembled sentence used to name whichever
    // of them moved, which is a heading that changes per record.
    expect(
      _text(tester, 'shift-amendment-sales-amend_abc'),
      '115 to 345',
    );
    expect(_text(tester, 'shift-amendment-transactions-amend_abc'), '1 to 3');
    // The direction is the server's own: observed minus expected, so a negative
    // variance is a shift that recorded less than its sales prove. The cleared
    // difference rides in the same column because it is the same disagreement.
    expect(
      _text(tester, 'shift-amendment-difference-amend_abc'),
      'The shift had recorded 230 less than its sales prove, and counted 2 '
      'transactions fewer. This removed difference sv_shift-1_gen-9 from the '
      'unresolved list.',
    );
    expect(
      _text(tester, 'shift-amendment-reason-amend_abc'),
      'Late sales arrived after the close.',
    );
    // The signed-in owner made this one, so the row says so rather than
    // repeating their own UID back at them.
    expect(
      textAt(tester, 'shift-amendment-actor-amend_abc'),
      'Corrected by You, recorded 2026-08-04 15:30 UTC.',
    );
    expect(
      _text(tester, 'shift-amendment-evidence-amend_abc'),
      'Shift belonged to cashier-a. Corrected from expectation '
      'se_2026-08-04_shift-1 at generation gen-9.',
    );
    // §2.1's five each mean one thing and "a correction was recorded" is not
    // among them, so no row wears a badge and the table draws no status column.
    expect(
      tester
          .widget<RecordList>(find.byType(RecordList))
          .items
          .map((item) => item.status),
      everyElement(isNull),
    );
    // The one guarantee this whole surface rests on is stated on the page, not
    // only enforced in the read model.
    expect(
      _text(tester, 'shift-amendments-cash'),
      startsWith('No correction here changed a drawer count.'),
    );
    expect(reader.queries.single.descending, isFalse);
    expect(reader.queries.single.equalityFilters, isEmpty);
    // The trail resolves no staff names, so it stays readable when the staff
    // directory is not.
    expect(reader.documentPaths, isEmpty);
  });

  testWidgets('a colleague is named by the UID every record uses', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _amendment(
          'amend_abc',
          overrides: <String, Object?>{'actorUid': 'admin-b'},
        ),
      ]);

    await _pump(tester, _controller(), reader);

    expect(
      textAt(tester, 'shift-amendment-actor-amend_abc'),
      'Corrected by admin-b, recorded 2026-08-04 15:30 UTC.',
    );
  });

  testWidgets('a correction that moved only the count says exactly that', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _amendment(
          'amend_abc',
          overrides: <String, Object?>{
            'totalSalesMinor': 11500,
            'totalSales': 115.0,
            'salesVarianceMinor': 0,
            'transactionCount': 2,
            'transactionVariance': -1,
          },
        ),
      ]);

    await _pump(tester, _controller(), reader);

    // The figure that did not move says so rather than going silent: an empty
    // cell in this column would read as a figure nobody recorded.
    expect(_text(tester, 'shift-amendment-sales-amend_abc'), 'Unchanged');
    expect(_text(tester, 'shift-amendment-transactions-amend_abc'), '1 to 2');
    // Singular, because one transaction is one transaction.
    expect(
      _text(tester, 'shift-amendment-difference-amend_abc'),
      'The shift had counted 1 transaction fewer. This removed difference '
      'sv_shift-1_gen-9 from the unresolved list.',
    );
  });

  testWidgets('a shift that disagreed with itself is reported as such', (
    tester,
  ) async {
    // Nothing else in the app reports an internally inconsistent shift, so the
    // correction trail is the only place it surfaces.
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _amendment(
          'amend_abc',
          overrides: <String, Object?>{
            'previousRepresentationsAgreed': false,
            'salesVarianceMinor': -22999,
          },
        ),
      ]);

    await _pump(tester, _controller(), reader);

    // It is one clause of the difference this correction settled rather than a
    // column of its own: it is silent on almost every record, and a table
    // spends a whole column on a heading whether or not any row fills it.
    expect(
      _text(tester, 'shift-amendment-difference-amend_abc'),
      contains(
        'Before this, the shift\'s two records of the same money did not agree '
        'with each other. Both were rewritten.',
      ),
    );
  });

  testWidgets('a correction that cleared no listed difference omits the line', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _amendment(
          'amend_abc',
          overrides: <String, Object?>{'clearedAnomalyId': null},
        ),
      ]);

    await _pump(tester, _controller(), reader);

    expect(
      _text(tester, 'shift-amendment-difference-amend_abc'),
      isNot(contains('unresolved list')),
    );
  });

  testWidgets('a correction states the same facts on a phone', (tester) async {
    // The class of defect the staff directory found: a screen that has only
    // ever been laid out wide. This one has no actions at all, so what a phone
    // has to fit is six facts and a provenance line.
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[_amendment('amend_abc')]);

    await _pump(tester, _controller(), reader, width: 411);

    expect(
      RecordList.formFor(tester.view.physicalSize.width),
      RecordForm.stackedCards,
    );
    for (final key in <String>[
      'shift-amendment-amend_abc',
      'shift-amendment-subject-amend_abc',
      'shift-amendment-record-amend_abc',
      'shift-amendment-sales-amend_abc',
      'shift-amendment-transactions-amend_abc',
      'shift-amendment-difference-amend_abc',
      'shift-amendment-reason-amend_abc',
      'shift-amendment-evidence-amend_abc',
      'shift-amendment-actor-amend_abc',
    ]) {
      expect(find.byKey(ValueKey<String>(key)), findsOne, reason: key);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a business with no corrections says so', (tester) async {
    final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader);

    expect(
      _text(tester, 'shift-amendments-empty'),
      'No shift summary has been corrected in this business.',
    );
  });

  testWidgets('a shift-scoped trail states its scope and filters', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[_amendment('amend_abc')]);

    await _pump(tester, _controller(), reader, shiftId: 'shift-1');

    expect(reader.queries.single.equalityFilters, <String, Object?>{
      'shiftId': 'shift-1',
    });
    // The scope claim moved to `PageHeader.subtitle`, which this panel-level
    // pump does not build; the screen-level test below asserts it.
    expect(find.byKey(const ValueKey('shift-amendment-amend_abc')), findsOne);

    // Widening the page starts the list again rather than resuming from a cursor
    // the new query never established.
    await tester.tap(find.byKey(const ValueKey('shift-amendments-show-all')));
    await tester.pump();
    await tester.pump();
    expect(reader.queries.last.equalityFilters, isEmpty);
    expect(reader.queries.last.startAfterDocumentId, isNull);
  });

  testWidgets('the route names which shift it is scoped to, in the header', (
    tester,
  ) async {
    // **§7's "Title appears once".** This route drew `Corrections to shift
    // shift-1` as a heading inside a page whose `AppScaffold` was already
    // titled `Shift corrections`. The claim survives as the header's subtitle,
    // which is the slot step 5a built for "which slice of something this is"
    // and left empty at every call site until now.
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[_amendment('amend_abc')]);

    await tester.pumpWidget(
      MaterialApp(
        home: TenantSessionScope(
          controller: _controller(),
          child: TenantShiftAmendmentScreen(reader: reader, shiftId: 'shift-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Shift corrections'),
      ),
      findsOne,
    );
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('shift-1')),
      findsOne,
    );
  });

  testWidgets('the unscoped trail carries no subtitle at all', (tester) async {
    // A page showing the whole business is not a slice of anything, so the slot
    // stays empty rather than being filled with a word meaning "everything".
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[_amendment('amend_abc')]);

    await tester.pumpWidget(
      MaterialApp(
        home: TenantSessionScope(
          controller: _controller(),
          child: TenantShiftAmendmentScreen(reader: reader),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<AppScaffold>(find.byType(AppScaffold)).subtitle,
      isNull,
    );
  });

  testWidgets('an empty scoped trail says it is about one shift', (
    tester,
  ) async {
    final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader, shiftId: 'shift-9');

    expect(
      _text(tester, 'shift-amendments-empty'),
      'This shift\'s summary has never been corrected.',
    );
  });

  testWidgets('a manager reads the trail they may not write to', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[_amendment('amend_abc')]);

    await _pump(tester, _controller(role: TenantRole.manager), reader);

    expect(find.byKey(const ValueKey('shift-amendment-amend_abc')), findsOne);
    expect(find.byKey(const ValueKey('shift-amendments-denied')), findsNothing);
  });

  testWidgets('a cashier is denied and issues no read at all', (tester) async {
    final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(role: TenantRole.cashier), reader);

    expect(find.byKey(const ValueKey('shift-amendments-denied')), findsOne);
    expect(reader.queries, isEmpty);
    expect(reader.documentPaths, isEmpty);
  });

  testWidgets('a record that claims it touched the cash hides the page', (
    tester,
  ) async {
    // The failure is deliberate and total. A record that contradicts the one
    // guarantee this surface states would otherwise be shown as an ordinary
    // correction beside truthful ones.
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _amendment(
          'amend_abc',
          overrides: <String, Object?>{'mutatesCountedCash': true},
        ),
      ]);

    await _pump(tester, _controller(), reader);

    expect(find.byKey(const ValueKey('shift-amendments-failure')), findsOne);
    expect(
      find.byKey(const ValueKey('shift-amendment-amend_abc')),
      findsNothing,
    );
  });

  testWidgets('a record that contradicts its own figures hides the page', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _amendment(
          'amend_abc',
          overrides: <String, Object?>{'transactionVariance': -1},
        ),
      ]);

    await _pump(tester, _controller(), reader);

    expect(find.byKey(const ValueKey('shift-amendments-failure')), findsOne);
  });

  testWidgets('the trail pages forward and back', (tester) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _amendment('amend_1'),
        _amendment('amend_2'),
        _amendment('amend_3'),
      ]);

    await _pump(tester, _controller(), reader, pageSize: 2);

    expect(find.byKey(const ValueKey('shift-amendment-amend_1')), findsOne);
    expect(find.byKey(const ValueKey('shift-amendment-amend_3')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('shift-amendments-next')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('shift-amendment-amend_3')), findsOne);
    expect(reader.queries.last.startAfterDocumentId, 'amend_2');

    await tester.tap(find.byKey(const ValueKey('shift-amendments-previous')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('shift-amendment-amend_1')), findsOne);
  });

  testWidgets('a tenant switch discards an outstanding page', (tester) async {
    final controller = _controller();
    final reader = _Reader.deferred();

    await _pump(tester, controller, reader, settle: false);
    expect(
      reader.queries.single.collectionPath,
      'tenants/tenant-a/shift_amendments',
    );

    controller.open(uid: 'owner-a', membership: _membership('tenant-b'));
    await tester.pump();
    expect(
      reader.queries.last.collectionPath,
      'tenants/tenant-b/shift_amendments',
    );

    // The first business's page arrives after the switch and is discarded
    // before it can label another business's screen.
    reader.completeFirst(<TenantQueryDocumentSnapshot>[
      _amendment('amend_abc'),
    ]);
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('shift-amendment-amend_abc')),
      findsNothing,
    );

    reader.completeFirst(<TenantQueryDocumentSnapshot>[
      _amendment('amend_xyz', tenantId: 'tenant-b'),
    ]);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('shift-amendment-amend_xyz')), findsOne);
  });
}

String? _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data;

Future<void> _pump(
  WidgetTester tester,
  TenantSessionController controller,
  _Reader reader, {
  int pageSize = 20,
  String? shiftId,
  bool settle = true,
  double width = 1400,
}) async {
  tester.view.physicalSize = Size(width, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: Scaffold(
          body: TenantShiftAmendmentPanel(
            reader: reader,
            shiftId: shiftId,
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

/// The exact immutable record `functions/src/reconciliation/amendments.ts`
/// creates, with the figures from the first real correction this app made.
TenantQueryDocumentSnapshot _amendment(
  String amendmentId, {
  String tenantId = 'tenant-a',
  Map<String, Object?>? overrides,
}) {
  final data = <String, Object?>{
    'amendmentId': amendmentId,
    'tenantId': tenantId,
    'shiftId': 'shift-1',
    'staffId': 'cashier-a',
    'businessDate': '2026-08-04',
    'sourceType': 'reconciliation_shift_variance',
    'expectationId': 'se_2026-08-04_shift-1',
    'expectationGeneration': 'gen-9',
    'previousTotalSales': 115.0,
    'previousTotalSalesMinor': 11500,
    'previousTransactionCount': 1,
    'previousRepresentationsAgreed': true,
    'totalSales': 345.0,
    'totalSalesMinor': 34500,
    'transactionCount': 3,
    'salesVarianceMinor': -23000,
    'transactionVariance': -2,
    'clearedAnomalyId': 'sv_shift-1_gen-9',
    'mutatesCountedCash': false,
    'reason': 'Late sales arrived after the close.',
    'actorUid': 'owner-a',
    'requestId': 'amend-shift-abcdefgh',
    'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 4, 15, 30)),
  };
  if (overrides != null) data.addAll(overrides);
  return TenantQueryDocumentSnapshot(
    path: 'tenants/$tenantId/shift_amendments/$amendmentId',
    data: data,
  );
}

TenantSessionController _controller({TenantRole role = TenantRole.owner}) =>
    TenantSessionController()..open(
      uid: 'owner-a',
      membership: _membership('tenant-a', role: role),
    );

TenantMembership _membership(
  String tenantId, {
  TenantRole role = TenantRole.owner,
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
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);

final class _Reader implements TenantDataReader {
  _Reader() : _defer = false;
  _Reader.deferred() : _defer = true;

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
    return null;
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
