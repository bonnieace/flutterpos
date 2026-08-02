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

  testWidgets('one category is totalled from its lines and says so', (
    tester,
  ) async {
    final callable = _Callable(<Object?>[
      _response(),
      _response(overrides: <String, Object?>{
        'sales': 812.0,
        'transactions': 12,
      }),
    ]);

    await _pump(
      tester,
      _controller(TenantRole.manager),
      callable,
      reader: _Reader(categories: <String, List<String>>{
        'tenant-a': <String>['drinks', 'bread'],
      }),
    );
    await tester.tap(
      find.byKey(const ValueKey('sales-totals-category-drinks')),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(callable.payloads.last['categoryId'], 'drinks');
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sales-totals-range')))
          .data,
      '2026-07-31 • drinks shelf',
    );
    // A category figure sums matching lines only; saying so is the whole point.
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('sales-totals-category-basis')),
          )
          .data,
      'This adds up only the lines in this category, not the whole of each '
      'sale. 25 of the 37 sales read held nothing in it.',
    );
  });

  testWidgets('the whole-catalog total states no such basis', (tester) async {
    final callable = _Callable(<Object?>[_response()]);

    await _pump(
      tester,
      _controller(TenantRole.manager),
      callable,
      reader: _Reader(categories: <String, List<String>>{
        'tenant-a': <String>['drinks'],
      }),
    );

    expect(
      find.byKey(const ValueKey('sales-totals-category-basis')),
      findsNothing,
    );
    expect(callable.payloads.single.containsKey('categoryId'), isFalse);
  });

  testWidgets('a category survives a period change', (tester) async {
    final callable = _Callable(<Object?>[
      _response(),
      _response(overrides: <String, Object?>{'transactions': 12}),
      _response(overrides: <String, Object?>{'transactions': 12}),
    ]);

    await _pump(
      tester,
      _controller(TenantRole.owner),
      callable,
      reader: _Reader(categories: <String, List<String>>{
        'tenant-a': <String>['drinks'],
      }),
    );
    await tester.tap(
      find.byKey(const ValueKey('sales-totals-category-drinks')),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('sales-totals-period-last7Days')),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(callable.payloads.last['categoryId'], 'drinks');
    expect(callable.payloads.last['previousStartDate'], '2026-07-25');
  });

  testWidgets('an unreadable category list leaves the total working', (
    tester,
  ) async {
    final callable = _Callable(<Object?>[_response()]);

    await _pump(
      tester,
      _controller(TenantRole.manager),
      callable,
      reader: _Reader(throws: true),
    );

    // The figure a manager came for does not depend on the filter list.
    expect(find.byKey(const ValueKey('sales-totals-amount')), findsOne);
    expect(find.byKey(const ValueKey('sales-totals-category')), findsNothing);
    expect(
      find.byKey(const ValueKey('sales-totals-categories-unavailable')),
      findsOne,
    );
  });

  testWidgets('a reader answering outside the business fails the route', (
    tester,
  ) async {
    final callable = _Callable(<Object?>[_response()]);

    await _pump(
      tester,
      _controller(TenantRole.manager),
      callable,
      reader: _Reader(
        categories: <String, List<String>>{
          'tenant-a': <String>['drinks'],
        },
        answersOutsideTenant: true,
      ),
    );

    // A broken tenant boundary is not an unavailable label. It must not be
    // swallowed into the quiet degrade an unreadable list gets: the route
    // fails and no figure is shown at all.
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sales-totals-failure')))
          .data,
      'The totals could not be read.',
    );
    expect(find.byKey(const ValueKey('sales-totals-amount')), findsNothing);
    expect(find.byKey(const ValueKey('sales-totals-category')), findsNothing);
    expect(find.text('tenant-z'), findsNothing);
  });

  testWidgets('a business with no categories is offered no filter', (
    tester,
  ) async {
    final callable = _Callable(<Object?>[_response()]);

    await _pump(tester, _controller(TenantRole.manager), callable);

    expect(find.byKey(const ValueKey('sales-totals-category')), findsNothing);
    expect(
      find.byKey(const ValueKey('sales-totals-categories-unavailable')),
      findsNothing,
    );
  });

  testWidgets('a category this business does not have is never applied', (
    tester,
  ) async {
    final callable = _Callable(<Object?>[_response(), _response()]);
    final reader = _Reader(
      categories: <String, List<String>>{
        'tenant-a': <String>['drinks'],
      },
    );
    final controller = _controller(TenantRole.manager);

    await _pump(tester, controller, callable, reader: reader);
    await tester.tap(
      find.byKey(const ValueKey('sales-totals-category-drinks')),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(callable.payloads.last['categoryId'], 'drinks');

    // Tenant B has no such category. The selection is dropped rather than sent,
    // so one business's ID can never filter another's sales.
    controller.open(
      uid: 'user-a',
      membership: _membership('tenant-b', TenantRole.manager),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(callable.payloads.last['tenantId'], 'tenant-b');
    expect(callable.payloads.last.containsKey('categoryId'), isFalse);
    expect(
      find.byKey(const ValueKey('sales-totals-category-basis')),
      findsNothing,
    );
  });

  testWidgets('a tenant switch discards the outstanding read', (tester) async {
    final controller = _controller(TenantRole.manager);
    final callable = _Callable(<Object?>[
      _response(),
      _response(overrides: <String, Object?>{'sales': 7.5}),
    ], deferred: true);

    await _pump(tester, controller, callable, settle: false);
    await tester.pump();
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
  _Reader? reader,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: Scaffold(
          body: TenantSalesTotalsPanel(
            callable: callable,
            reader: reader ?? _Reader(),
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
  await tester.pump();
}

/// Answers the canonical category page, or refuses to.
final class _Reader implements TenantDataReader {
  _Reader({
    Map<String, List<String>> categories = const <String, List<String>>{},
    this.throws = false,
    this.answersOutsideTenant = false,
  }) : categories = Map<String, List<String>>.of(categories);

  /// Category IDs by tenant, named `<id> shelf` so a label is provable.
  final Map<String, List<String>> categories;
  final bool throws;

  /// Answers with a document belonging to another business.
  final bool answersOutsideTenant;
  final List<TenantCollectionQuery> queries = <TenantCollectionQuery>[];

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) =>
      Future<TenantDocumentSnapshot?>.value();

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) {
    queries.add(query);
    if (throws) {
      return Future<List<TenantQueryDocumentSnapshot>>.error(
        StateError('categories unavailable'),
      );
    }
    final tenantId = query.collectionPath.split('/')[1];
    // Firestore pages a collection in ascending document-ID order and the
    // repository proves it, so the fake has to answer in that order too.
    final ids = <String>[...?categories[tenantId]]..sort();
    final collectionPath = answersOutsideTenant
        ? 'tenants/tenant-z/categories'
        : query.collectionPath;
    return Future<List<TenantQueryDocumentSnapshot>>.value(<
      TenantQueryDocumentSnapshot
    >[
      for (final id in ids.take(query.limit))
        TenantQueryDocumentSnapshot(
          path: '$collectionPath/$id',
          data: <String, Object?>{'name': '$id shelf'},
        ),
    ]);
  }
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
