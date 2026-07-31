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
    });

    await _pump(tester, _controller(TenantRole.manager), reader);

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('daily-summary-sales-2026-07-30')),
          )
          .data,
      'Sales: 1250.50 over 12 transactions in 2 shifts',
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

  testWidgets('incomplete cost data is named, and profit is not shown', (
    tester,
  ) async {
    final reader = _Reader(<String, Map<String, Object?>>{
      'tenants/tenant-a/daily_metrics/2026-07-31': _metrics(
        overrides: <String, Object?>{'incompleteCostLineCount': 4},
      ),
    });

    await _pump(tester, _controller(TenantRole.owner), reader);

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
