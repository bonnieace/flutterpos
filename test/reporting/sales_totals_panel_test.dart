import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/reporting/reporting.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('today is totalled from what the server holds', (tester) async {
    final callable = _Callable(<Object?>[_response()]);

    await _pump(tester, _controller(TenantRole.manager), callable);

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sales-totals-range')))
          .data,
      '2026-07-31',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sales-totals-amount')))
          .data,
      'Sales: 4820.75 over 37 sales',
    );
    expect(callable.payloads.single, <String, Object?>{
      'tenantId': 'tenant-a',
      'previousStartDate': '2026-07-31',
      'previousEndDate': '2026-07-31',
    });
  });

  testWidgets('choosing a longer period reads the new range', (tester) async {
    final callable = _Callable(<Object?>[
      _response(),
      _response(overrides: <String, Object?>{'sales': 61200.0}),
    ]);

    await _pump(tester, _controller(TenantRole.owner), callable);
    await tester.tap(
      find.byKey(const ValueKey('sales-totals-period-last30Days')),
    );
    await tester.pump();
    await tester.pump();

    expect(callable.payloads.last['previousStartDate'], '2026-07-02');
    expect(callable.payloads.last['previousEndDate'], '2026-07-31');
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sales-totals-range')))
          .data,
      '2026-07-02 to 2026-07-31',
    );
    expect(find.textContaining('61200.00'), findsOne);
  });

  testWidgets('only mine filters by the signed-in member', (tester) async {
    final callable = _Callable(<Object?>[_response(), _response()]);

    await _pump(tester, _controller(TenantRole.manager), callable);
    await tester.tap(find.byKey(const ValueKey('sales-totals-scope-mine')));
    await tester.pump();
    await tester.pump();

    // The UID comes from the guarded session, never from the surface.
    expect(callable.payloads.last['soldById'], 'user-a');
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sales-totals-range')))
          .data,
      '2026-07-31 • your sales only',
    );
  });

  testWidgets('a cashier is denied and nothing is asked for', (tester) async {
    final callable = _Callable(<Object?>[_response()]);

    await _pump(tester, _controller(TenantRole.cashier), callable);

    expect(find.byKey(const ValueKey('sales-totals-denied')), findsOne);
    expect(callable.payloads, isEmpty);
  });

  testWidgets('a period holding too many sales leaves the chooser', (
    tester,
  ) async {
    final callable = _Callable(<Object?>[
      FirebaseFunctionsException(code: 'resource-exhausted', message: 'no'),
      _response(),
    ]);

    await _pump(
      tester,
      _controller(TenantRole.owner),
      callable,
      period: TenantSalesPeriod.last90Days,
    );

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sales-totals-failure')))
          .data,
      contains('Choose a shorter period'),
    );
    // The whole point of that sentence is that a shorter period can be picked,
    // so the chooser must survive the refusal.
    await tester.tap(find.byKey(const ValueKey('sales-totals-period-today')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('sales-totals-failure')), findsNothing);
    expect(callable.payloads.last['previousStartDate'], '2026-07-31');
  });

  testWidgets('a refused read can be tried again unchanged', (tester) async {
    final callable = _Callable(<Object?>[
      FirebaseFunctionsException(code: 'unavailable', message: 'no'),
      _response(),
    ]);

    await _pump(tester, _controller(TenantRole.manager), callable);
    expect(find.textContaining('Nothing was changed'), findsOne);

    await tester.tap(find.byKey(const ValueKey('sales-totals-retry')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('sales-totals-amount')), findsOne);
    expect(callable.payloads, hasLength(2));
  });

  testWidgets('incomplete cost lines are named and no profit is shown', (
    tester,
  ) async {
    final callable = _Callable(<Object?>[_response()]);

    await _pump(tester, _controller(TenantRole.owner), callable);

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sales-totals-cost')))
          .data,
      '96 sale lines have no cost recorded, so no profit figure is shown.',
    );
    expect(find.textContaining('Profit'), findsNothing);
  });

  testWidgets('a complete day says nothing about cost', (tester) async {
    final callable = _Callable(<Object?>[
      _response(overrides: <String, Object?>{'incompleteCostLineCount': 0}),
    ]);

    await _pump(tester, _controller(TenantRole.owner), callable);

    expect(find.byKey(const ValueKey('sales-totals-cost')), findsNothing);
  });

  testWidgets('an answer that cannot be trusted shows no figure', (
    tester,
  ) async {
    // The server counted a different number of sales than it read, so the
    // answer describes some other request.
    final callable = _Callable(<Object?>[
      _response(overrides: <String, Object?>{'transactions': 4}),
    ]);

    await _pump(tester, _controller(TenantRole.manager), callable);

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sales-totals-failure')))
          .data,
      'The server answer could not be trusted, so no total is shown.',
    );
    expect(find.textContaining('4820.75'), findsNothing);
  });

  testWidgets('a tenant switch discards the outstanding read', (tester) async {
    final controller = _controller(TenantRole.manager);
    final callable = _Callable(<Object?>[
      _response(),
      _response(overrides: <String, Object?>{'sales': 7.5}),
    ], deferred: true);

    await _pump(tester, controller, callable, settle: false);
    await tester.pump();
    expect(callable.pending, hasLength(1));

    controller.open(
      uid: 'user-a',
      membership: _membership('tenant-b', TenantRole.manager),
    );
    await tester.pump();

    // The first business answers after the switch; that answer must never
    // reach a screen now labelled with another business.
    callable.completeFirst();
    await tester.pump();
    expect(find.textContaining('4820.75'), findsNothing);

    callable.completeFirst();
    await tester.pump();
    expect(find.textContaining('7.50'), findsOne);
    expect(callable.payloads.last['tenantId'], 'tenant-b');
  });
}

Future<void> _pump(
  WidgetTester tester,
  TenantSessionController controller,
  _Callable callable, {
  bool settle = true,
  TenantSalesPeriod period = TenantSalesPeriod.today,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: Scaffold(
          body: TenantSalesTotalsPanel(
            callable: callable,
            clock: () => DateTime.utc(2026, 7, 31, 9),
            period: period,
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

Map<String, Object?> _response({Map<String, Object?>? overrides}) {
  final previous = <String, Object?>{
    'sales': 4820.75,
    'profit': 4820.75,
    'transactions': 37,
    'incompleteCostLineCount': 96,
  };
  if (overrides != null) previous.addAll(overrides);
  return <String, Object?>{
    'previous': previous,
    'scannedTransactions': 37,
  };
}

/// Answers each call with the next scripted outcome; a thrown entry is thrown.
final class _Callable implements SalesTotalsCallable {
  _Callable(this._outcomes, {this.deferred = false});

  final List<Object?> _outcomes;
  final bool deferred;
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];
  final List<Completer<Object?>> pending = <Completer<Object?>>[];
  int _index = 0;

  void completeFirst() {
    if (pending.isEmpty) return;
    pending.removeAt(0).complete(_next());
  }

  Object? _next() => _outcomes[_index < _outcomes.length
      ? _index++
      : _outcomes.length - 1];

  @override
  Future<Object?> call(Map<String, Object?> payload) {
    payloads.add(payload);
    if (deferred) {
      final completer = Completer<Object?>();
      pending.add(completer);
      return completer.future;
    }
    final outcome = _next();
    return outcome is Exception
        ? Future<Object?>.error(outcome)
        : Future<Object?>.value(outcome);
  }
}
