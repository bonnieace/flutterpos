import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/reporting/reporting.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/status.dart';
import 'package:flutter_application_1/ui/scaffold.dart';
import 'package:flutter_application_1/ui/fields.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/notices.dart';
import '../support/text.dart';

/// The option keys the kind dropdown is offering.
List<Key?> _kindOptionKeys(WidgetTester tester) => tester
    .widget<AppSelect<TenantReconciliationAnomalyKind?>>(
      find.byKey(const ValueKey('reconciliation-anomaly-kind')),
    )
    .items
    .map((item) => item.key)
    .toList();

/// Opens the kind dropdown and chooses one option.
///
/// Taps the option's `Text`: a closed `DropdownButton` keeps an offstage copy of
/// the selected item, so the key alone can resolve to something not hit-testable.
Future<void> _chooseKind(WidgetTester tester, String wireValue) async {
  await tester.tap(find.byKey(const ValueKey('reconciliation-anomaly-kind')));
  await tester.pumpAndSettle();
  await tester.tap(
    find
        .descendant(
          of: find.byKey(ValueKey('reconciliation-anomaly-kind-$wireValue')),
          matching: find.byType(Text),
        )
        .last,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('states each difference and what it is about', (tester) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('sale_a', _saleAnomaly()),
        _snapshot('shift_b', _shiftAnomaly()),
        _snapshot('stock_c', _stockAnomaly()),
      ]);

    await _pump(tester, _controller(), reader);

    expect(
      _text(tester, 'reconciliation-anomaly-kind-sale_a'),
      'Sale lines could not be read',
    );
    expect(
      _text(tester, 'reconciliation-anomaly-subject-sale_a'),
      'Sale checkout-a',
    );
    // **The figures left the sentences in step 8.** What is left of the prose is
    // whatever the figures do not already say - the consequence here, and
    // nothing at all on a stock variance, where three labelled numbers are the
    // whole of what the sentence used to state.
    expect(
      _text(tester, 'reconciliation-anomaly-detail-sale_a'),
      'Those lines moved no stock.',
    );
    expect(
      _text(tester, 'reconciliation-anomaly-figure-invalid-lines-sale_a'),
      '2',
    );
    expect(
      _text(tester, 'reconciliation-anomaly-subject-stock_c'),
      'Product product-a',
    );
    expect(
      find.byKey(const ValueKey('reconciliation-anomaly-detail-stock_c')),
      findsNothing,
    );
    expect(
      _text(tester, 'reconciliation-anomaly-figure-expected-stock_c'),
      '10',
    );
    expect(
      _text(tester, 'reconciliation-anomaly-figure-observed-stock_c'),
      '7',
    );
    // **The sign is carried by the figure and the direction by a word beside
    // it**, so neither states it alone - the same rule §9 applies to colour.
    expect(
      _text(tester, 'reconciliation-anomaly-figure-variance-stock_c'),
      '-3',
    );
    expect(
      _text(tester, 'reconciliation-anomaly-subject-shift_b'),
      'Shift shift-a',
    );
    expect(
      _text(tester, 'reconciliation-anomaly-detail-shift_b'),
      'Its closing totals disagree with the sales recorded during it.',
    );
    expect(
      _text(tester, 'reconciliation-anomaly-figure-sales-variance-shift_b'),
      '-12.5',
    );
    expect(
      _text(
        tester,
        'reconciliation-anomaly-figure-transaction-variance-shift_b',
      ),
      '+2',
    );
  });

  testWidgets('a difference that is only a refusal to read carries no figure', (
    tester,
  ) async {
    // Three of the eight kinds report that something could not be read rather
    // than a measurement, and a `StatLine` with nothing to put in it would be a
    // label beside an empty column.
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('quantity_a', <String, Object?>{
          'tenantId': 'tenant-a',
          'productId': 'product-a',
          'anomalyType': 'invalid_product_quantity',
        }),
      ]);

    await _pump(tester, _controller(), reader);

    expect(
      _text(tester, 'reconciliation-anomaly-detail-quantity_a'),
      'This product\'s recorded quantity could not be read as a whole number, '
      'so its stock was not verified at all.',
    );
    expect(
      find.byKey(
        const ValueKey('reconciliation-anomaly-figure-expected-quantity_a'),
      ),
      findsNothing,
    );
  });

  testWidgets('says the list is business-wide, not the day you came from', (
    tester,
  ) async {
    // A record belongs to a product, a shift, or a sale and carries no business
    // date, so narrowing it to a day would silently hide open differences.
    final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader);

    await _openScope(tester);
    expect(
      _text(tester, 'reconciliation-anomalies-scope'),
      contains('covers the whole business'),
    );
    expect(reader.queries.single.equalityFilters, isEmpty);
  });

  testWidgets('the three page-wide paragraphs are one fold, not three lines', (
    tester,
  ) async {
    // §5.1: `Disclosure` replaces permanent helper paragraphs. All three are true
    // of every record this route will ever list, and the ordering note used to
    // sit *below* the records as a loose caption - the least likely place to look
    // for the reason the order surprised you.
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('sale_a', _saleAnomaly()),
      ]);

    await _pump(tester, _controller(), reader);

    expect(
      find.byKey(const ValueKey('reconciliation-anomalies-scope')),
      findsNothing,
    );
    expect(find.textContaining('not in time order'), findsNothing);

    await _openScope(tester);

    expect(
      find.byKey(const ValueKey('reconciliation-anomalies-scope')),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('reconciliation-anomalies-writes')),
      findsOne,
    );
    expect(
      _text(tester, 'reconciliation-anomalies-order'),
      contains('not in time order'),
    );
  });

  testWidgets('narrowing to one kind restarts the list', (tester) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('sale_a', _saleAnomaly()),
        _snapshot('sale_b', _saleAnomaly()),
        _snapshot('stock_c', _stockAnomaly()),
      ]);

    await _pump(tester, _controller(), reader, pageSize: 2);
    await tester.tap(
      find.byKey(const ValueKey('reconciliation-anomalies-next')),
    );
    await _settle(tester);
    expect(
      find.byKey(const ValueKey('reconciliation-anomaly-stock_c')),
      findsOneWidget,
    );

    await _chooseKind(tester, 'stock_variance');
    await _settle(tester);

    // A cursor is a position inside one exact query, so the narrowed list
    // starts again rather than resuming from a position it never established.
    expect(reader.queries.last.startAfterDocumentId, isNull);
    expect(reader.queries.last.equalityFilters, {
      'anomalyType': 'stock_variance',
    });
    expect(
      find.byKey(const ValueKey('reconciliation-anomaly-stock_c')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('reconciliation-anomaly-sale_a')),
      findsNothing,
    );
  });

  testWidgets('offers no chip for a kind it cannot ask for', (tester) async {
    final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader);

    // Read off `AppSelect.items` rather than the tree: the kind filter is a
    // dropdown, and a closed one builds only the option it is showing.
    final offered = _kindOptionKeys(tester);
    expect(
      offered,
      contains(const ValueKey('reconciliation-anomaly-kind-all')),
    );
    expect(
      offered,
      contains(const ValueKey('reconciliation-anomaly-kind-stock_variance')),
    );
    // `other` names every unmodelled kind, so it identifies no stored value.
    expect(
      offered,
      isNot(contains(const ValueKey('reconciliation-anomaly-kind-'))),
    );
  });

  testWidgets('shows an unmodelled kind verbatim rather than hiding it', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('other_a', <String, Object?>{
          'tenantId': 'tenant-a',
          'anomalyType': 'price_drift',
          'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 30)),
        }),
      ]);

    await _pump(tester, _controller(), reader);

    expect(
      _text(tester, 'reconciliation-anomaly-kind-other_a'),
      'Unrecognised difference: price_drift',
    );
    expect(
      _text(tester, 'reconciliation-anomaly-subject-other_a'),
      'This business',
    );
  });

  testWidgets('states a difference with no recorded time as such', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot(
          'sale_a',
          _saleAnomaly(overrides: <String, Object?>{'createdAt': null}),
        ),
      ]);

    await _pump(tester, _controller(), reader);

    expect(
      textAt(tester, 'reconciliation-anomaly-instants-sale_a'),
      'No run or time was recorded for this difference.',
    );
  });

  testWidgets('a broken chain is not described as a quantity disagreement', (
    tester,
  ) async {
    // **The divergence the shared vocabulary was written for.** This list used to
    // describe all three stock kinds with the stock-variance sentence, so a
    // broken checkpoint chain whose quantities happen to agree read as "0 fewer
    // than the ledger accounts for" - a record that exists because there is a
    // difference, stating that there is none. The stock route has had the right
    // words for all three since it was written.
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('chain_a', <String, Object?>{
          'tenantId': 'tenant-a',
          'productId': 'product-a',
          'anomalyType': 'checkpoint_chain_invalid',
          'expectedQuantity': 10,
          'observedQuantity': 10,
          'variance': 0,
        }),
      ]);

    await _pump(tester, _controller(), reader);

    final detail = _text(tester, 'reconciliation-anomaly-detail-chain_a');
    expect(detail, contains('does not join up'));
    expect(detail, contains('This is not a quantity disagreement.'));
    expect(detail, isNot(contains('0 fewer')));
    // The one figure it does carry is the expected quantity, and it is labelled
    // as the thing that cannot be trusted rather than as a disagreement.
    expect(
      _text(tester, 'reconciliation-anomaly-figure-expected-chain_a'),
      '10',
    );
    expect(
      find.byKey(
        const ValueKey('reconciliation-anomaly-figure-variance-chain_a'),
      ),
      findsNothing,
    );
  });

  testWidgets('an unmodelled kind states plainly that it cannot be explained', (
    tester,
  ) async {
    // It used to render the kind and the subject and then stop, so the record
    // said nothing at all about itself. The stock route's own sentence for this
    // case now reaches both surfaces.
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('other_a', <String, Object?>{
          'tenantId': 'tenant-a',
          'anomalyType': 'price_drift',
        }),
      ]);

    await _pump(tester, _controller(), reader);

    expect(
      _text(tester, 'reconciliation-anomaly-detail-other_a'),
      'What this difference means is not something this version of the app can '
      'explain.',
    );
  });

  testWidgets('says plainly when the business has none', (tester) async {
    final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader);

    expect(
      _text(tester, 'reconciliation-anomalies-empty'),
      'The server has recorded no unresolved differences for this business.',
    );
  });

  testWidgets('a cashier is denied without any read', (tester) async {
    final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(role: TenantRole.cashier), reader);

    expect(
      find.byKey(const ValueKey('reconciliation-anomalies-denied')),
      findsOneWidget,
    );
    expect(reader.queries, isEmpty);
  });

  testWidgets('a business switch discards an outstanding page', (tester) async {
    final reader = _Reader()..defer();
    final controller = _controller();

    await _pump(tester, controller, reader, settle: false);
    await tester.pump();
    controller.open(uid: 'manager-a', membership: _membership('tenant-b'));
    reader.complete(<TenantQueryDocumentSnapshot>[
      _snapshot('sale_a', _saleAnomaly()),
    ]);
    await _settle(tester);

    // Tenant A's page must never label tenant B's screen.
    expect(
      find.byKey(const ValueKey('reconciliation-anomaly-sale_a')),
      findsNothing,
    );
  });

  testWidgets('offers a correction only on a shift difference', (tester) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('sale_a', _saleAnomaly()),
        _snapshot('shift_b', _shiftAnomaly()),
        _snapshot('shift_c', _invalidShiftAnomaly()),
        _snapshot('stock_c', _stockAnomaly()),
      ]);

    await _pump(
      tester,
      _controller(role: TenantRole.owner),
      reader,
      callable: _Callable(_response()),
    );

    // A shift whose totals disagree with its sales is the one difference the
    // server can resolve. A stock figure is corrected from the product, and the
    // records of unreadable data are not a figure that can be put right at all.
    expect(_amendButton('shift_b'), findsOneWidget);
    expect(_amendButton('shift_c'), findsNothing);
    expect(_amendButton('stock_c'), findsNothing);
    expect(_amendButton('sale_a'), findsNothing);
    await _openScope(tester);
    expect(
      _text(tester, 'reconciliation-anomalies-writes'),
      contains('counted cash is never changed'),
    );
  });

  testWidgets('a build without the capability stays read-only', (tester) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('shift_b', _shiftAnomaly()),
      ]);

    await _pump(tester, _controller(role: TenantRole.owner), reader);

    // Whatever the composition root did not inject stays unavailable, so the
    // list is exactly the read-only explanation it was before.
    expect(_amendButton('shift_b'), findsNothing);
    expect(
      find.byKey(const ValueKey('reconciliation-amend-forbidden')),
      findsNothing,
    );
    await _openScope(tester);
    expect(
      _text(tester, 'reconciliation-anomalies-writes'),
      contains('nothing on this page can'),
    );
  });

  testWidgets('a manager is told why rather than shown nothing', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('shift_b', _shiftAnomaly()),
      ]);

    await _pump(
      tester,
      _controller(),
      reader,
      callable: _Callable(_response()),
    );

    // The server's roles are narrower than the roles that read this list, so a
    // manager is told about the one thing they cannot do.
    expect(_amendButton('shift_b'), findsNothing);
    // The same notice the day page has carried behind the same component since
    // step 4, at the same status: `info`, because nothing failed and nothing is
    // hidden. It is a `Callout` and not a `Disclosure` because a person meets it
    // as the answer to "why can I not press that".
    final callout = tester.widget<Callout>(
      find.byKey(const ValueKey('reconciliation-amend-forbidden')),
    );
    expect(callout.status, AppStatus.info);
    expect(callout.message, contains('owners and administrators'));
  });

  testWidgets('the explanation is absent when nothing on screen applies', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('stock_c', _stockAnomaly()),
      ]);

    await _pump(
      tester,
      _controller(),
      reader,
      callable: _Callable(_response()),
    );

    expect(
      find.byKey(const ValueKey('reconciliation-amend-forbidden')),
      findsNothing,
    );
  });

  testWidgets('correcting a shift sends the reason and re-reads the list', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('shift_b', _shiftAnomaly()),
      ]);
    // The server deletes a resolved difference, so the second read is the proof
    // that it is gone rather than a locally edited list.
    final callable = _Callable(
      _response(),
      onCall: () => reader.respond(<TenantQueryDocumentSnapshot>[]),
    );

    await _pump(
      tester,
      _controller(role: TenantRole.owner),
      reader,
      callable: callable,
    );
    await _amend(tester, 'shift_b', 'Late  offline\tsale');

    expect(callable.payloads.single, <String, Object?>{
      'tenantId': 'tenant-a',
      'shiftId': 'shift-a',
      'reason': 'Late offline sale',
      'requestId': 'amend-shift-abcdefgh',
    });
    expect(
      noticeMessage(tester, 'reconciliation-amend-notice'),
      'Shift shift-a on 2026-07-31 now records 1350.25 instead of 1200.50, '
      'over 10 transactions rather than 9. The counted cash was not changed. '
      'Recorded as sm_abc.',
    );
    expect(reader.queries.length, 2);
    expect(reader.queries.last.startAfterDocumentId, isNull);
    expect(
      find.byKey(const ValueKey('reconciliation-anomaly-shift_b')),
      findsNothing,
    );
  });

  testWidgets('a refusal names itself and leaves the list alone', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('shift_b', _shiftAnomaly()),
      ]);

    await _pump(
      tester,
      _controller(role: TenantRole.owner),
      reader,
      callable: _Callable.failing(
        FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'refused',
        ),
      ),
    );
    await _amend(tester, 'shift_b', 'Late offline sale');

    // The shift is exactly as it was, so the difference stays listed and the
    // page is not re-read to prove something that did not happen.
    expect(
      noticeMessage(tester, 'reconciliation-amend-notice'),
      contains('this shift cannot be corrected'),
    );
    expect(
      noticeStatus(tester, 'reconciliation-amend-notice'),
      AppStatus.problem,
    );
    expect(
      noticeStatus(tester, 'reconciliation-amend-notice'),
      AppStatus.problem,
    );
    expect(reader.queries.length, 1);
    expect(
      find.byKey(const ValueKey('reconciliation-anomaly-shift_b')),
      findsOneWidget,
    );
  });

  testWidgets('an unknown outcome re-reads the list and says so', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('shift_b', _shiftAnomaly()),
      ]);

    await _pump(
      tester,
      _controller(role: TenantRole.owner),
      reader,
      callable: _Callable.failing(
        FirebaseFunctionsException(code: 'unavailable', message: 'down'),
      ),
    );
    await _amend(tester, 'shift_b', 'Late offline sale');

    // The shift may or may not have been corrected, and only the server's own
    // record can settle it.
    expect(
      noticeMessage(tester, 'reconciliation-amend-notice'),
      contains('The result is unknown'),
    );
    // **Not `problem`.** The shift may well have been corrected, and the
    // sentence's own instruction is to go and look - which is what §2.1 gives
    // `attention` rather than a failure.
    expect(
      noticeStatus(tester, 'reconciliation-amend-notice'),
      AppStatus.attention,
    );
    expect(reader.queries.length, 2);
  });

  testWidgets('an untrustworthy answer is refused rather than shown', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('shift_b', _shiftAnomaly()),
      ]);

    await _pump(
      tester,
      _controller(role: TenantRole.owner),
      reader,
      // A response naming another business must never label this one's screen.
      callable: _Callable(_response(overrides: {'tenantId': 'tenant-b'})),
    );
    await _amend(tester, 'shift_b', 'Late offline sale');

    expect(
      noticeMessage(tester, 'reconciliation-amend-notice'),
      contains('could not be trusted'),
    );
    expect(find.textContaining('tenant-b'), findsNothing);
  });

  testWidgets('cancelling the dialog sends nothing', (tester) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('shift_b', _shiftAnomaly()),
      ]);
    final callable = _Callable(_response());

    await _pump(
      tester,
      _controller(role: TenantRole.owner),
      reader,
      callable: callable,
    );
    await tester.tap(_amendButton('shift_b'));
    await tester.pumpAndSettle();
    expect(
      _text(tester, 'reconciliation-amend-explanation'),
      contains('cannot choose the figure'),
    );
    await tester.tap(find.byKey(const ValueKey('reconciliation-amend-cancel')));
    await tester.pumpAndSettle();

    expect(callable.payloads, isEmpty);
    expect(
      find.byKey(const ValueKey('reconciliation-amend-notice')),
      findsNothing,
    );
  });

  testWidgets('a business switch discards an outstanding correction', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('shift_b', _shiftAnomaly()),
      ]);
    final callable = _Callable.deferred();
    final controller = _controller(role: TenantRole.owner);

    await _pump(tester, controller, reader, callable: callable);
    await tester.tap(_amendButton('shift_b'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('reconciliation-amend-reason')),
      'Late offline sale',
    );
    await tester.tap(
      find.byKey(const ValueKey('reconciliation-amend-confirm')),
    );
    await tester.pumpAndSettle();
    // Proved before the switch, so a missing notice below cannot be a
    // correction that was never sent at all.
    expect(callable.payloads, hasLength(1));
    controller.open(uid: 'owner-a', membership: _membership('tenant-b'));
    callable.complete(_response());
    await _settle(tester);

    // Tenant A's correction must never report itself on tenant B's screen.
    expect(
      find.byKey(const ValueKey('reconciliation-amend-notice')),
      findsNothing,
    );
  });

  testWidgets('a shift difference opens the trail narrowed to that shift', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('shift_b', _shiftAnomaly()),
      ])
      ..respondAt(
        'tenants/tenant-a/shift_amendments',
        <TenantQueryDocumentSnapshot>[_amendmentSnapshot()],
      );

    // A manager reads this list and the trail, and may correct nothing. The
    // narrowed trail is the read, so it is offered here exactly as it is to an
    // owner: both surfaces are granted to the same three roles.
    await _pump(tester, _controller(), reader);
    expect(
      find.byKey(const ValueKey('reconciliation-anomaly-amend-shift_b')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('reconciliation-anomaly-corrections-shift_b')),
    );
    await tester.pumpAndSettle();

    // **The claim survives and its rendering moved.** The trail used to say
    // which shift it was showing in a second heading inside the page, under an
    // `AppScaffold` already titled `Shift corrections`. It is the
    // `PageHeader.subtitle` now — §7's "Title appears once", and the slot step
    // 5a built for exactly this.
    expect(
      find.descendant(
        of: find.byType(PageHeader),
        matching: find.text('shift-a'),
      ),
      findsOne,
    );
    expect(
      reader.queries.last.collectionPath,
      'tenants/tenant-a/shift_amendments',
    );
    expect(reader.queries.last.equalityFilters, <String, Object?>{
      'shiftId': 'shift-a',
    });
    expect(find.byKey(const ValueKey('shift-amendment-sm_abc')), findsOne);
  });

  testWidgets('a difference about no shift offers no trail of its own', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('product_b', _stockAnomaly()),
        _snapshot('sale_b', _saleAnomaly()),
      ]);

    await _pump(tester, _controller(), reader);

    for (final id in <String>['product_b', 'sale_b']) {
      expect(
        find.byKey(ValueKey('reconciliation-anomaly-corrections-$id')),
        findsNothing,
        reason: id,
      );
    }
    // The business-wide trail is still reachable; only the per-row narrowing is
    // absent, because these rows name no shift to narrow to.
    expect(
      find.byKey(const ValueKey('reconciliation-anomalies-amendments')),
      findsOne,
    );
  });

  testWidgets('a shift difference nothing can correct still reaches the trail', (
    tester,
  ) async {
    // Deliberate: the trail is offered for every row that names a shift, not only
    // the one kind that can be corrected. A shift corrected at a later generation
    // can still be listed under an earlier one, so whether this has already been
    // dealt with is a real question - and the answer, including "never", comes
    // from the trail rather than from this list.
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('invalid_b', _invalidShiftAnomaly()),
      ])
      ..respondAt(
        'tenants/tenant-a/shift_amendments',
        <TenantQueryDocumentSnapshot>[],
      );

    await _pump(
      tester,
      _controller(role: TenantRole.owner),
      reader,
      callable: _Callable(_response()),
    );
    // Its totals were unreadable, so there is no figure the sales prove and no
    // correction to offer.
    expect(
      find.byKey(const ValueKey('reconciliation-anomaly-amend-invalid_b')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(
        const ValueKey('reconciliation-anomaly-corrections-invalid_b'),
      ),
    );
    await tester.pumpAndSettle();

    expect(reader.queries.last.equalityFilters, <String, Object?>{
      'shiftId': 'shift-b',
    });
    expect(
      _text(tester, 'shift-amendments-empty'),
      'This shift\'s summary has never been corrected.',
    );
  });

  testWidgets('a correction stays reachable after its row is deleted', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('shift_b', _shiftAnomaly()),
      ])
      ..respondAt(
        'tenants/tenant-a/shift_amendments',
        <TenantQueryDocumentSnapshot>[_amendmentSnapshot()],
      );
    final callable = _Callable(
      _response(),
      onCall: () => reader.respond(<TenantQueryDocumentSnapshot>[]),
    );

    await _pump(
      tester,
      _controller(role: TenantRole.owner),
      reader,
      callable: callable,
    );
    await _amend(tester, 'shift_b', 'Late offline sale');

    // The row is gone - the server deleted the difference - so without this the
    // correction just made would be reachable only by opening the whole
    // business's trail and reading down.
    expect(
      find.byKey(const ValueKey('reconciliation-anomaly-shift_b')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey('reconciliation-amend-notice-trail')),
    );
    await tester.pumpAndSettle();

    // Narrowed to the shift the server's own answer named, not to the one this
    // page asked about.
    expect(reader.queries.last.equalityFilters, <String, Object?>{
      'shiftId': 'shift-a',
    });
    expect(find.byKey(const ValueKey('shift-amendment-sm_abc')), findsOne);
  });

  testWidgets('an unknown outcome offers the trail that would settle it', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('shift_b', _shiftAnomaly()),
      ]);

    await _pump(
      tester,
      _controller(role: TenantRole.owner),
      reader,
      callable: _Callable.failing(
        FirebaseFunctionsException(code: 'unavailable', message: 'down'),
      ),
    );
    await _amend(tester, 'shift_b', 'Late offline sale');

    // Whether a correction was recorded is the open question, and the trail is
    // the only place that answers it.
    expect(
      find.byKey(const ValueKey('reconciliation-amend-notice-trail')),
      findsOne,
    );
  });

  testWidgets('a refusal that changed nothing offers nothing to look at', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('shift_b', _shiftAnomaly()),
      ]);

    await _pump(
      tester,
      _controller(role: TenantRole.owner),
      reader,
      callable: _Callable.failing(
        FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'refused',
        ),
      ),
    );
    await _amend(tester, 'shift_b', 'Late offline sale');

    expect(find.byKey(const ValueKey('reconciliation-amend-notice')), findsOne);
    expect(
      find.byKey(const ValueKey('reconciliation-amend-notice-trail')),
      findsNothing,
    );
  });

  testWidgets('a difference opens the run that found it', (tester) async {
    // The row already names the run. Until this existed that was the end of the
    // trail: the day page is addressed by business date and a difference carries
    // a product or a shift instead, so nothing could be asked about the run.
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('shift_b', _shiftAnomaly()),
      ])
      ..respondDocument('tenants/tenant-a/reconciliation_jobs/rj_abc', _job());

    await _pump(tester, _controller(), reader);
    await tester.tap(
      find.byKey(const ValueKey('reconciliation-anomaly-run-shift_b')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reconciliation run'), findsOne);
    expect(
      reader.documentPaths,
      contains('tenants/tenant-a/reconciliation_jobs/rj_abc'),
    );
    // Described by the same card the day page uses, so the two cannot disagree
    // about what the run's state means - including its badge.
    expect(
      _text(tester, 'reconciliation-status-run-state-rj_abc'),
      'Nightly sweep',
    );
    expect(
      tester
          .widget<StatusBadge>(
            find.byKey(
              const ValueKey('reconciliation-status-run-badge-rj_abc'),
            ),
          )
          .label,
      'Completed',
    );
    expect(
      _text(tester, 'reconciliation-status-run-stock-differences-rj_abc'),
      '0',
    );
    expect(
      _text(tester, 'reconciliation-status-run-shift-differences-rj_abc'),
      '1',
    );
  });

  testWidgets('a run that is no longer stored says so rather than failing', (
    tester,
  ) async {
    // A difference outlives the run that found it, so an absent run is an
    // ordinary answer and what the difference records still stands.
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('shift_b', _shiftAnomaly()),
      ]);

    await _pump(tester, _controller(), reader);
    await tester.tap(
      find.byKey(const ValueKey('reconciliation-anomaly-run-shift_b')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('reconciliation-run-missing')), findsOne);
    expect(
      find.byKey(const ValueKey('reconciliation-run-failure')),
      findsNothing,
    );
  });

  testWidgets('a difference that names no run offers nothing to open', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot(
          'shift_b',
          _shiftAnomaly(overrides: <String, Object?>{'jobId': null}),
        ),
      ]);

    await _pump(tester, _controller(), reader);

    expect(
      find.byKey(const ValueKey('reconciliation-anomaly-run-shift_b')),
      findsNothing,
    );
    // The row itself still renders, and still says the difference is real.
    expect(
      find.byKey(const ValueKey('reconciliation-anomaly-shift_b')),
      findsOne,
    );
  });

  testWidgets('a record that contradicts itself fails the page closed', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot(
          'stock_c',
          _stockAnomaly(overrides: <String, Object?>{'variance': 99}),
        ),
      ]);

    await _pump(tester, _controller(), reader);

    expect(
      find.byKey(const ValueKey('reconciliation-anomalies-failure')),
      findsOneWidget,
    );
    expect(find.textContaining('inconsistent_anomaly'), findsNothing);
  });
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

Finder _amendButton(String anomalyId) =>
    find.byKey(ValueKey('reconciliation-anomaly-amend-$anomalyId'));

/// Opens the page's own explanation, whose three paragraphs are removed from the
/// tree while it is closed so a screen reader does not read out prose nobody can
/// see.
Future<void> _openScope(WidgetTester tester) async {
  await tester.tap(find.text('What this list covers'));
  await tester.pumpAndSettle();
}

/// Opens the correction dialog for one row, states a reason, and confirms.
Future<void> _amend(
  WidgetTester tester,
  String anomalyId,
  String reason,
) async {
  await tester.tap(_amendButton(anomalyId));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('reconciliation-amend-reason')),
    reason,
  );
  await tester.tap(find.byKey(const ValueKey('reconciliation-amend-confirm')));
  await tester.pumpAndSettle();
}

Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump();
  }
}

Future<void> _pump(
  WidgetTester tester,
  TenantSessionController controller,
  _Reader reader, {
  int pageSize = 20,
  bool settle = true,
  _Callable? callable,
}) async {
  tester.view.physicalSize = const Size(1400, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: Scaffold(
          body: TenantReconciliationAnomalyPanel(
            reader: reader,
            pageSize: pageSize,
            // Whatever is absent stays unavailable, which is how a build with no
            // correction capability keeps the list read-only.
            actions: callable == null
                ? null
                : TenantReconciliationActions(
                    amendShiftSummaryCallable: callable,
                  ),
            requestIdFactory: () => 'amend-shift-abcdefgh',
          ),
        ),
      ),
    ),
  );
  if (!settle) return;
  await _settle(tester);
}

TenantSessionController _controller({TenantRole role = TenantRole.manager}) =>
    TenantSessionController()..open(
      uid: 'manager-a',
      membership: _membership('tenant-a', role: role),
    );

TenantMembership _membership(
  String tenantId, {
  TenantRole role = TenantRole.manager,
}) => TenantMembership(
  tenantId: tenantId,
  tenantName: 'Business $tenantId',
  tenantSlug: tenantId,
  role: role,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  isOwner: role == TenantRole.owner,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);

Map<String, Object?> _saleAnomaly({Map<String, Object?>? overrides}) =>
    _document(<String, Object?>{
      'tenantId': 'tenant-a',
      'sourceType': 'sale',
      'sourceId': 'checkout-a',
      'anomalyType': 'invalid_sale_lines',
      'invalidLineCount': 2,
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 30)),
    }, overrides);

Map<String, Object?> _stockAnomaly({Map<String, Object?>? overrides}) =>
    _document(<String, Object?>{
      'tenantId': 'tenant-a',
      'productId': 'product-a',
      'jobId': 'rj_abc',
      'anomalyType': 'stock_variance',
      'expectedQuantity': 10,
      'observedQuantity': 7,
      'variance': -3,
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 30)),
    }, overrides);

/// The one difference the server can resolve, and the one it cannot: with no
/// readable totals there was nothing to compare, so there is no figure the
/// sales prove the shift should hold.
Map<String, Object?> _invalidShiftAnomaly() => _document(<String, Object?>{
  'tenantId': 'tenant-a',
  'shiftId': 'shift-b',
  'jobId': 'rj_abc',
  'anomalyType': 'invalid_or_missing_shift',
  'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 30)),
}, null);

Map<String, Object?> _shiftAnomaly({Map<String, Object?>? overrides}) =>
    _document(<String, Object?>{
      'tenantId': 'tenant-a',
      'shiftId': 'shift-a',
      'jobId': 'rj_abc',
      'anomalyType': 'shift_variance',
      'salesVariance': -12.5,
      'transactionVariance': 2,
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 30)),
    }, overrides);

Map<String, Object?> _document(
  Map<String, Object?> base,
  Map<String, Object?>? overrides,
) {
  final data = Map<String, Object?>.of(base);
  if (overrides != null) data.addAll(overrides);
  data.removeWhere((key, value) => value == null);
  return data;
}

/// The run one of these differences names, in the shape `jobs.ts` writes it, so
/// the route this page opens renders rather than failing closed.
Map<String, Object?> _job() => <String, Object?>{
  'tenantId': 'tenant-a',
  'source': 'nightly',
  'sourceKey': 'nightly:2026-07-31',
  'mode': 'incremental',
  'checkpointKind': 'none',
  'checkpointKey': '2026-07-31',
  'localDate': '2026-07-31',
  'requestedBy': 'system:nightly',
  'status': 'completed',
  'phase': 'finalize',
  'generation': 0,
  'revision': 4,
  'attemptCount': 1,
  'consecutiveFailureCount': 0,
  'rerunRequested': false,
  'metricsProcessed': 1,
  'productsProcessed': 0,
  'stockVarianceCount': 0,
  'shiftsProcessed': 2,
  'shiftVarianceCount': 1,
  'authority': 'canonical_tenant_data',
  'mutatesStock': false,
  'completedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 31)),
  'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 31)),
};

/// One `shift_amendments` record the trail's own strict read model accepts, so a
/// narrowed page this surface opens renders rather than failing closed.
TenantQueryDocumentSnapshot _amendmentSnapshot({String shiftId = 'shift-a'}) =>
    TenantQueryDocumentSnapshot(
      path: 'tenants/tenant-a/shift_amendments/sm_abc',
      data: <String, Object?>{
        'amendmentId': 'sm_abc',
        'tenantId': 'tenant-a',
        'shiftId': shiftId,
        'staffId': 'cashier-a',
        'businessDate': '2026-07-31',
        'sourceType': 'reconciliation_shift_variance',
        'expectationId': 'exp-a',
        'expectationGeneration': 'generation-one',
        'previousTotalSalesMinor': 120050,
        'previousTransactionCount': 9,
        'previousRepresentationsAgreed': true,
        'totalSalesMinor': 135025,
        'transactionCount': 10,
        'salesVarianceMinor': -14975,
        'transactionVariance': -1,
        'clearedAnomalyId': null,
        'mutatesCountedCash': false,
        'reason': 'A late sale arrived after the shift closed',
        'actorUid': 'manager-a',
        'requestId': 'amend-shift-abcdefgh',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 3)),
      },
    );

TenantQueryDocumentSnapshot _snapshot(String id, Map<String, Object?> data) =>
    TenantQueryDocumentSnapshot(
      path: 'tenants/tenant-a/reconciliation_anomalies/$id',
      data: data,
    );

Map<String, Object?> _response({Map<String, Object?>? overrides}) {
  final data = <String, Object?>{
    'amendmentId': 'sm_abc',
    'tenantId': 'tenant-a',
    'shiftId': 'shift-a',
    'businessDate': '2026-07-31',
    'previousTotalSalesMinor': 120050,
    'previousTransactionCount': 9,
    'totalSalesMinor': 135025,
    'transactionCount': 10,
    'salesVarianceMinor': -14975,
    'transactionVariance': -1,
    'clearedAnomalyId': 'shift_abc',
  };
  if (overrides != null) data.addAll(overrides);
  return data;
}

final class _Callable implements AmendShiftSummaryCallable {
  _Callable(this._response, {this.onCall}) : _error = null;
  _Callable.failing(Object error)
    : _response = null,
      _error = error,
      onCall = null;

  /// Holds the call open so a business switch can happen mid-correction.
  _Callable.deferred()
    : _response = null,
      _error = null,
      onCall = null,
      _pending = Completer<Object?>();

  final Object? _response;
  final Object? _error;

  /// Runs when the call is made, so a test can arrange the server state the
  /// reload will then read.
  final void Function()? onCall;

  Completer<Object?>? _pending;
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];

  void complete(Object? response) {
    _pending?.complete(response);
    _pending = null;
  }

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(payload);
    onCall?.call();
    final pending = _pending;
    if (pending != null) return pending.future;
    final error = _error;
    if (error != null) throw error;
    return _response;
  }
}

final class _Reader implements TenantDataReader {
  List<TenantQueryDocumentSnapshot> _page =
      const <TenantQueryDocumentSnapshot>[];
  Completer<List<TenantQueryDocumentSnapshot>>? _pending;
  final List<TenantCollectionQuery> queries = <TenantCollectionQuery>[];

  /// Pages keyed by the exact collection a repository asks for, so a route this
  /// page opens reads its own collection rather than this one's documents under
  /// another name.
  final Map<String, List<TenantQueryDocumentSnapshot>> _pagesByPath =
      <String, List<TenantQueryDocumentSnapshot>>{};

  void respond(List<TenantQueryDocumentSnapshot> page) => _page = page;

  void respondAt(
    String collectionPath,
    List<TenantQueryDocumentSnapshot> page,
  ) => _pagesByPath[collectionPath] = page;

  /// Holds the next page open so a business switch can happen mid-read.
  void defer() => _pending = Completer<List<TenantQueryDocumentSnapshot>>();

  void complete(List<TenantQueryDocumentSnapshot> page) {
    _page = page;
    _pending?.complete(page);
    _pending = null;
  }

  /// Documents a route this page opens reads by exact path, keyed by that path.
  final Map<String, Map<String, Object?>> documents =
      <String, Map<String, Object?>>{};
  final List<String> documentPaths = <String>[];

  void respondDocument(String path, Map<String, Object?> data) =>
      documents[path] = data;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    documentPaths.add(path);
    final data = documents[path];
    return data == null ? null : TenantDocumentSnapshot(path: path, data: data);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    queries.add(query);
    final pending = _pending;
    if (pending != null) await pending.future;
    final cursor = query.startAfterDocumentId;
    final matches = <TenantQueryDocumentSnapshot>[];
    for (final snapshot in _pagesByPath[query.collectionPath] ?? _page) {
      final id = snapshot.path.split('/').last;
      if (cursor != null && id.compareTo(cursor) <= 0) continue;
      // A fake that ignored the repository's own filter would make a narrowed
      // page prove nothing, so the filter contract is modelled here too.
      final matchesFilters = query.equalityFilters.entries.every(
        (filter) => snapshot.data[filter.key] == filter.value,
      );
      if (!matchesFilters) continue;
      matches.add(snapshot);
      if (matches.length >= query.limit) break;
    }
    return matches;
  }
}
