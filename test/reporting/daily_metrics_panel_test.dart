import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/reporting/reporting.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reconciled days are reported exactly as recorded', (
    tester,
  ) async {
    final reader = _Reader(<String, Map<String, Object?>>{
      'tenants/tenant-a/daily_metrics/2026-07-30': _metrics(
        businessDate: '2026-07-30',
      ),
      'tenants/tenant-a/configuration/checkout': <String, Object?>{
        'currency': 'KES',
      },
    });

    await _pump(tester, _controller(TenantRole.manager), reader);

    // The code the business published, never one this app assumed.
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('daily-summary-sales-2026-07-30')),
          )
          .data,
      'Sales: KES 1250.50 over 12 transactions in 2 shifts',
    );
    expect(
      find.byKey(const ValueKey('daily-summary-currency-unknown')),
      findsNothing,
    );
    // Today has no document yet and must still be listed as pending.
    expect(
      find.byKey(const ValueKey('daily-summary-pending-2026-07-31')),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('daily-summary-cost-2026-07-30')),
      findsNothing,
    );
  });

  testWidgets('a manager is told cost data is incomplete, and no more', (
    tester,
  ) async {
    final reader = _Reader(<String, Map<String, Object?>>{
      'tenants/tenant-a/daily_metrics/2026-07-31': _metrics(
        overrides: <String, Object?>{'incompleteCostLineCount': 4},
      ),
    });

    await _pump(tester, _controller(TenantRole.manager), reader);

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('daily-summary-cost-2026-07-31')),
          )
          .data,
      '4 sale lines have no cost recorded.',
    );
    expect(find.textContaining('430.25'), findsNothing);
    expect(find.textContaining('Profit'), findsNothing);
  });

  testWidgets('an owner reads the day\'s profit and its margin', (
    tester,
  ) async {
    final reader = _Reader(<String, Map<String, Object?>>{
      'tenants/tenant-a/daily_metrics/2026-07-30': _metrics(
        businessDate: '2026-07-30',
      ),
      'tenants/tenant-a/configuration/checkout': <String, Object?>{
        'currency': 'KES',
      },
    });

    await _pump(tester, _controller(TenantRole.owner), reader);

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('daily-summary-2026-07-30-profit')),
          )
          .data,
      'Profit: KES 430.25, a margin of 34.4%.',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('daily-summary-2026-07-30-profit-note')),
          )
          .data,
      'Every sale line behind it carries a cost.',
    );
  });

  testWidgets('an owner is told why an incomplete day has no figure', (
    tester,
  ) async {
    final reader = _Reader(<String, Map<String, Object?>>{
      'tenants/tenant-a/daily_metrics/2026-07-31': _metrics(
        overrides: <String, Object?>{'incompleteCostLineCount': 4},
      ),
    });

    await _pump(tester, _controller(TenantRole.owner), reader);

    // One statement, not two: the count lives inside the reason rather than
    // beside it, so nothing reads as a second finding.
    expect(
      find.byKey(const ValueKey('daily-summary-cost-2026-07-31')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('daily-summary-2026-07-31-profit')),
      findsNothing,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('daily-summary-2026-07-31-profit-note')),
          )
          .data,
      'Profit and margin are not shown: 4 sale lines have no cost recorded, '
      'and counting them as free would overstate both.',
    );
    expect(find.textContaining('430.25'), findsNothing);
  });

  testWidgets('a day with one of everything reads in the singular', (
    tester,
  ) async {
    // The transaction count sat beside an already-singularised shift count in
    // the same sentence, which is how "12 transactions in 1 shift" and "1
    // transactions in 2 shifts" could both be produced by one line.
    final reader = _Reader(<String, Map<String, Object?>>{
      'tenants/tenant-a/daily_metrics/2026-07-31': _metrics(
        overrides: <String, Object?>{
          'transactions': 1,
          'transactionCount': 1,
          'shiftCount': 1,
          'incompleteCostLineCount': 1,
        },
      ),
    });

    await _pump(tester, _controller(TenantRole.manager), reader);

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('daily-summary-sales-2026-07-31')),
          )
          .data,
      'Sales: 1250.50 over 1 transaction in 1 shift',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('daily-summary-cost-2026-07-31')),
          )
          .data,
      '1 sale line has no cost recorded.',
    );
  });

  testWidgets('an unpublished currency is stated, never guessed', (
    tester,
  ) async {
    final reader = _Reader(<String, Map<String, Object?>>{
      'tenants/tenant-a/daily_metrics/2026-07-31': _metrics(),
    });

    await _pump(tester, _controller(TenantRole.manager), reader);

    expect(
      find.byKey(const ValueKey('daily-summary-currency-unknown')),
      findsOne,
    );
    // A bare figure, not an assumed code. The figure itself still arrives.
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('daily-summary-sales-2026-07-31')),
          )
          .data,
      'Sales: 1250.50 over 12 transactions in 2 shifts',
    );
  });

  testWidgets('a malformed currency loses the label, not the figures', (
    tester,
  ) async {
    final reader = _Reader(<String, Map<String, Object?>>{
      'tenants/tenant-a/daily_metrics/2026-07-31': _metrics(),
      'tenants/tenant-a/configuration/checkout': <String, Object?>{
        'currency': 'shillings',
      },
    });

    await _pump(tester, _controller(TenantRole.manager), reader);

    expect(
      find.byKey(const ValueKey('daily-summary-currency-unknown')),
      findsOne,
    );
    expect(find.textContaining('1250.50'), findsOne);
    expect(find.textContaining('shillings'), findsNothing);
  });

  testWidgets('a cashier is denied and starts no read', (tester) async {
    final reader = _Reader(const <String, Map<String, Object?>>{});

    await _pump(tester, _controller(TenantRole.cashier), reader);

    expect(find.byKey(const ValueKey('daily-summary-denied')), findsOne);
    expect(reader.requested, isEmpty);
  });

  testWidgets('a malformed day fails closed and can be retried', (
    tester,
  ) async {
    final reader = _Reader(<String, Map<String, Object?>>{
      'tenants/tenant-a/daily_metrics/2026-07-31': _metrics(
        overrides: <String, Object?>{'transactionCount': 99},
      ),
    });

    await _pump(tester, _controller(TenantRole.manager), reader);

    expect(find.byKey(const ValueKey('daily-summary-failure')), findsOne);
    expect(find.textContaining('transactionCount'), findsNothing);

    reader.documents.remove('tenants/tenant-a/daily_metrics/2026-07-31');
    await tester.tap(find.byKey(const ValueKey('daily-summary-retry')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('daily-summary')), findsOne);
  });

  testWidgets('each day can open why it is in its state', (tester) async {
    final reader = _Reader(<String, Map<String, Object?>>{
      'tenants/tenant-a/daily_metrics/2026-07-30': _metrics(
        businessDate: '2026-07-30',
      ),
    });

    await _pump(
      tester,
      _controller(TenantRole.manager),
      reader,
      reconciliationRoute: (businessDate) =>
          Scaffold(body: Text('why $businessDate')),
      reconciliationRoles: const <TenantRole>[
        TenantRole.owner,
        TenantRole.admin,
        TenantRole.manager,
      ],
    );

    // A reconciled day and an unreconciled one both have an explanation.
    expect(
      find.byKey(const ValueKey('daily-summary-reconciliation-2026-07-30')),
      findsOne,
    );
    await tester.tap(
      find.byKey(const ValueKey('daily-summary-reconciliation-2026-07-31')),
    );
    await tester.pumpAndSettle();

    // The exact day is carried into the route, and the route runs under the
    // same session scope, so a tenant switch invalidates it too.
    expect(find.text('why 2026-07-31'), findsOne);
    expect(find.byType(TenantSessionScope), findsWidgets);
  });

  testWidgets('a role the route is not offered to never sees it', (
    tester,
  ) async {
    final reader = _Reader(const <String, Map<String, Object?>>{});

    await _pump(
      tester,
      _controller(TenantRole.manager),
      reader,
      reconciliationRoute: (businessDate) => const Scaffold(),
      // The summary is readable by a manager; the explanation, in this
      // configuration, is not. The action disappears rather than failing.
      reconciliationRoles: const <TenantRole>[TenantRole.owner],
    );

    expect(
      find.byKey(const ValueKey('daily-summary-reconciliation-2026-07-31')),
      findsNothing,
    );
  });

  testWidgets('the summary can open the totals for a period', (tester) async {
    final reader = _Reader(const <String, Map<String, Object?>>{});

    await _pump(
      tester,
      _controller(TenantRole.manager),
      reader,
      salesTotalsRoute: () => const Scaffold(body: Text('period totals')),
      salesTotalsRoles: const <TenantRole>[
        TenantRole.owner,
        TenantRole.admin,
        TenantRole.manager,
      ],
    );

    await tester.tap(
      find.byKey(const ValueKey('daily-summary-sales-totals')),
    );
    await tester.pumpAndSettle();

    // The route runs under the same session scope, so a tenant switch
    // invalidates it exactly as it does every other guarded route.
    expect(find.text('period totals'), findsOne);
    expect(find.byType(TenantSessionScope), findsWidgets);
  });

  testWidgets('a role the totals route is not offered to never sees it', (
    tester,
  ) async {
    final reader = _Reader(const <String, Map<String, Object?>>{});

    await _pump(
      tester,
      _controller(TenantRole.manager),
      reader,
      salesTotalsRoute: () => const Scaffold(),
      salesTotalsRoles: const <TenantRole>[TenantRole.owner],
    );

    expect(
      find.byKey(const ValueKey('daily-summary-sales-totals')),
      findsNothing,
    );
  });

  testWidgets('a tenant switch discards the outstanding load', (tester) async {
    final controller = _controller(TenantRole.manager);
    final reader = _Reader(<String, Map<String, Object?>>{
      'tenants/tenant-a/daily_metrics/2026-07-31': _metrics(),
      'tenants/tenant-b/daily_metrics/2026-07-31': _metrics(
        tenantId: 'tenant-b',
        overrides: <String, Object?>{'sales': 7.5, 'transactions': 1,
          'transactionCount': 1},
      ),
    }, deferred: true);

    await _pump(tester, controller, reader, settle: false);
    await tester.pump();
    // Days are read one document at a time, so exactly one read is in flight.
    expect(reader.pending.length, 1);

    controller.open(
      uid: 'user-a',
      membership: _membership('tenant-b', TenantRole.manager),
    );
    await tester.pump();

    // The first business answers after the switch; its load must be discarded.
    await _drain(tester, reader, 'tenants/tenant-a/');
    expect(find.textContaining('1250.50'), findsNothing);

    await _drain(tester, reader, 'tenants/tenant-b/');
    expect(find.textContaining('7.50'), findsOne);
    expect(find.textContaining('1250.50'), findsNothing);
  });
}

/// Completes every read a sequential day-by-day load issues under [prefix].
Future<void> _drain(
  WidgetTester tester,
  _Reader reader,
  String prefix,
) async {
  for (var pass = 0; pass < 4; pass++) {
    reader.completeAllFor(prefix);
    await tester.pump();
  }
}

Future<void> _pump(
  WidgetTester tester,
  TenantSessionController controller,
  _Reader reader, {
  bool settle = true,
  TenantReconciliationRouteBuilder? reconciliationRoute,
  List<TenantRole> reconciliationRoles = const <TenantRole>[],
  TenantSalesTotalsRouteBuilder? salesTotalsRoute,
  List<TenantRole> salesTotalsRoles = const <TenantRole>[],
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: Scaffold(
          body: TenantDailySummaryPanel(
            reader: reader,
            days: 2,
            clock: () => DateTime.utc(2026, 7, 31, 9),
            reconciliationRoute: reconciliationRoute,
            reconciliationRoles: reconciliationRoles,
            salesTotalsRoute: salesTotalsRoute,
            salesTotalsRoles: salesTotalsRoles,
          ),
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
      ..open(uid: 'user-a', membership: _membership('tenant-a', role));

TenantMembership _membership(String tenantId, TenantRole role) =>
    TenantMembership(
      tenantId: tenantId,
      tenantName: tenantId,
      tenantSlug: tenantId,
      role: role,
      membershipStatus: MembershipStatus.active,
      tenantStatus: TenantStatus.active,
      isOwner: role == TenantRole.owner,
      mirrorVersion: 1,
      createdAt: DateTime.utc(2026, 7, 31),
      updatedAt: DateTime.utc(2026, 7, 31),
      serverCanAccess: true,
      canonicalTenantExists: true,
      canonicalMembershipExists: true,
    );

Map<String, Object?> _metrics({
  String tenantId = 'tenant-a',
  String businessDate = '2026-07-31',
  Map<String, Object?>? overrides,
}) {
  final data = <String, Object?>{
    'tenantId': tenantId,
    'businessDate': businessDate,
    'sales': 1250.5,
    'profit': 430.25,
    'transactions': 12,
    'transactionCount': 12,
    'shiftCount': 2,
    'incompleteCostLineCount': 0,
    'metricGeneration': 'gen-1',
    'sourceDirtyRevision': 3,
    'regeneratedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 30)),
  };
  if (overrides != null) data.addAll(overrides);
  return data;
}

final class _Reader implements TenantDocumentReader {
  _Reader(Map<String, Map<String, Object?>> documents, {this.deferred = false})
    : documents = Map<String, Map<String, Object?>>.of(documents);

  final Map<String, Map<String, Object?>> documents;
  final bool deferred;
  final List<String> requested = <String>[];
  final List<(String, Completer<TenantDocumentSnapshot?>)> pending =
      <(String, Completer<TenantDocumentSnapshot?>)>[];

  /// Completes every outstanding read whose path is under [prefix].
  void completeAllFor(String prefix) {
    for (final entry in pending.where((entry) => entry.$1.startsWith(prefix))) {
      final data = documents[entry.$1];
      entry.$2.complete(
        data == null
            ? null
            : TenantDocumentSnapshot(path: entry.$1, data: data),
      );
    }
    pending.removeWhere((entry) => entry.$1.startsWith(prefix));
  }

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) {
    requested.add(path);
    final data = documents[path];
    final snapshot = data == null
        ? null
        : TenantDocumentSnapshot(path: path, data: data);
    if (!deferred) return Future.value(snapshot);
    final completer = Completer<TenantDocumentSnapshot?>();
    pending.add((path, completer));
    return completer.future;
  }
}
