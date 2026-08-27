import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/inventory/inventory.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/record_list.dart';
import 'package:flutter_application_1/ui/status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/notices.dart';
import '../support/text.dart';

void main() {
  testWidgets('the adjustment explanation is kept, and starts out of the way', (
    tester,
  ) async {
    // §5.2 names this paragraph by name as prose to keep and move inside a
    // `Disclosure`. The words are unchanged.
    const explanation =
        'An adjustment is recorded permanently with its reason and cannot be '
        'deleted. Correcting a mistake means recording another adjustment.';
    final reader = _Reader()..respondMovements(<TenantQueryDocumentSnapshot>[]);

    await _pump(
      tester,
      _controller(),
      reader,
      callable: _Callable(_response()),
    );

    expect(find.text(explanation), findsNothing);
    await tester.tap(find.text('What an adjustment records'));
    await tester.pumpAndSettle();
    expect(find.text(explanation), findsOneWidget);
  });
  testWidgets('the recorded quantity and the ledger are stated as read', (
    tester,
  ) async {
    final reader = _Reader(staffNames: <String, String>{'manager-a': 'Amina'})
      ..respondMovements(<TenantQueryDocumentSnapshot>[
        _adjustment('sa_abc'),
        _sale('sale_chk-1'),
      ]);

    await _pump(tester, _controller(), reader);

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('product-stock-quantity')))
          .data,
      '7',
    );
    // A sale is never blocked by a stock count, so the surface says so instead
    // of presenting a negative quantity as an error - behind the fold now, with
    // the two other permanent explanations on this route.
    expect(find.textContaining('may legitimately be negative'), findsNothing);
    await _openQuantityScope(tester);
    expect(find.textContaining('may legitimately be negative'), findsOne);
    // This route used to be the third description of one document: it said
    // `Adjustment: damage` where the two feeds beside it said `Manual
    // adjustment`, and it wrote its own figures sentence and its own
    // attribution. All three now come from the shared record vocabulary, and
    // the typed category is stated where the other facts are.
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('product-stock-delta-sa_abc')),
          )
          .data,
      '-3 • ${TenantStockMovementSource.manualAdjustment.label}',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('product-stock-adjustment-type-sa_abc')),
          )
          .data,
      'damage',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('product-stock-figures-sa_abc')),
          )
          .data,
      '10 to 7',
    );
    expect(
      textAt(tester, 'product-stock-recorded-sa_abc'),
      // The adjustment was recorded by the signed-in manager, so the row says
      // so rather than repeating their own UID back at them.
      'Recorded 2026-08-01 09:00 UTC by You (Amina)',
    );
    // A reconciled sale carries no before/after pair, which is named rather
    // than filled in with a locally derived figure. It is two words now
    // because the sentence has become a key and a value.
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('product-stock-figures-sale_chk-1')),
          )
          .data,
      'Not recorded',
    );
    // A sale movement names no member of the business, so it names the server
    // rather than dropping the attribution half of §5.2's provenance line -
    // which is what this route used to do and neither feed beside it did.
    expect(
      textAt(tester, 'product-stock-recorded-sale_chk-1'),
      endsWith('by the server'),
    );
  });

  testWidgets('the ledger states the same facts on a phone', (tester) async {
    // The class of defect the staff directory found a step earlier: a screen
    // that has only ever been laid out wide. This is the widest of the four
    // stock screens - a stat strip, an exception report, a ledger and a form
    // on one page - and nothing had drawn its ledger below 768.
    final reader = _Reader()
      ..respondMovements(<TenantQueryDocumentSnapshot>[_adjustment('sa_abc')]);

    await _pump(tester, _controller(), reader, width: 411);

    expect(
      RecordList.formFor(tester.view.physicalSize.width),
      RecordForm.stackedCards,
    );
    for (final key in <String>[
      'product-stock-entry-sa_abc',
      'product-stock-delta-sa_abc',
      'product-stock-figures-sa_abc',
      'product-stock-adjustment-type-sa_abc',
      'product-stock-reason-sa_abc',
      'product-stock-recorded-sa_abc',
    ]) {
      expect(find.byKey(ValueKey<String>(key)), findsOne, reason: key);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a ledger entry carries no standing and nothing to do', (
    tester,
  ) async {
    // §2.1's five each mean one thing and "stock moved" is not among them, so
    // no row wears a badge. The tinted arrow block that used to lead each entry
    // said only what the sign on the delta says, and it said it in colour.
    final reader = _Reader()
      ..respondMovements(<TenantQueryDocumentSnapshot>[
        _adjustment('sa_abc'),
        _sale('sale_chk-1'),
      ]);

    await _pump(tester, _controller(), reader);

    final list = tester.widget<RecordList>(find.byType(RecordList));
    expect(list.identityLabel, 'Movement');
    expect(list.items.map((item) => item.status), everyElement(isNull));
    expect(list.items.map((item) => item.actions), everyElement(isEmpty));
  });

  testWidgets('a product with an empty ledger says so', (tester) async {
    final reader = _Reader()..respondMovements(<TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader);

    expect(find.byKey(const ValueKey('product-stock-empty')), findsOne);
    expect(reader.movementQueries.single.descending, isFalse);
    expect(reader.movementQueries.single.equalityFilters, isEmpty);
  });

  testWidgets('a cashier is denied and issues no read at all', (tester) async {
    final reader = _Reader()..respondMovements(<TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(role: TenantRole.cashier), reader);

    expect(find.byKey(const ValueKey('product-stock-denied')), findsOne);
    expect(reader.queries, isEmpty);
    expect(reader.documentPaths, isEmpty);
  });

  testWidgets('the adjustment form is absent without a callable', (
    tester,
  ) async {
    final reader = _Reader()..respondMovements(<TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader);

    expect(find.byKey(const ValueKey('product-stock-form')), findsNothing);
  });

  testWidgets('an adjustment sends the typed payload and re-reads', (
    tester,
  ) async {
    final reader = _Reader()..respondMovements(<TenantQueryDocumentSnapshot>[]);
    final callable = _Callable(_response());

    await _pump(tester, _controller(), reader, callable: callable);
    await _submit(tester, units: '4', reason: 'Delivery  received');

    expect(callable.payloads.single, <String, Object?>{
      'tenantId': 'tenant-a',
      'productId': 'product-1',
      'quantityDelta': 4,
      'type': 'restock',
      'reason': 'Delivery received',
      'requestId': 'adjust-stock-abcdefgh',
    });
    expect(
      noticeMessage(tester, 'product-stock-notice'),
      'Stock changed from 7 to 11.',
    );
    // **This notice sits directly above the "Reconciliation found" section**,
    // which draws every recorded difference as a red `Callout`. A bare sentence
    // there read as part of the problem rather than as the answer to it.
    expect(noticeStatus(tester, 'product-stock-notice'), AppStatus.ok);
    // The quantity is re-read, so what is shown is the server's evidence rather
    // than an optimistic local figure.
    expect(reader.productReads, 2);
    // **And the ledger is not read at all, which is the change of
    // 2026-08-26.** The correction sheet draws no ledger and no reconciliation
    // report, so reading either would spend a query per open on nothing.
    expect(reader.movementQueries, isEmpty);
    expect(
      reader.queries.where(
        (query) =>
            query.collectionPath == 'tenants/tenant-a/reconciliation_anomalies',
      ),
      isEmpty,
    );
  });

  testWidgets('a removal-only type never offers the add direction', (
    tester,
  ) async {
    final reader = _Reader()..respondMovements(<TenantQueryDocumentSnapshot>[]);
    final callable = _Callable(
      _response(
        overrides: <String, Object?>{'quantityDelta': -4, 'quantity': 3},
      ),
    );

    await _pump(tester, _controller(), reader, callable: callable);
    // A correction may go either way, so the segmented control exists.
    await tester.tap(find.byKey(const ValueKey('product-stock-type')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(TenantStockAdjustmentType.correction.label).last,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('product-stock-direction')), findsOne);

    // Damage may only remove, so the direction is stated rather than chosen.
    await tester.tap(find.byKey(const ValueKey('product-stock-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(TenantStockAdjustmentType.damage.label).last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('product-stock-direction')), findsNothing);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('product-stock-fixed-direction')),
          )
          .data,
      'This type always removes stock.',
    );

    await _submit(tester, units: '4', reason: 'Broken in transit');
    expect(callable.payloads.single['quantityDelta'], -4);
    expect(callable.payloads.single['type'], 'damage');
  });

  testWidgets('only an unknown outcome keeps the request ID', (tester) async {
    final reader = _Reader()..respondMovements(<TenantQueryDocumentSnapshot>[]);
    final callable = _Callable.failing(
      FirebaseFunctionsException(
        code: 'unavailable',
        message: 'The service is unavailable.',
      ),
    );

    await _pump(tester, _controller(), reader, callable: callable);
    await _submit(tester, units: '4', reason: 'Delivery received');

    expect(
      noticeMessage(tester, 'product-stock-notice'),
      startsWith('The result is unknown.'),
    );
    // The quantity is re-read after an unknown outcome, because only the server
    // can say whether stock moved.
    expect(reader.productReads, 2);

    await _submit(tester, units: '4', reason: 'Delivery received');
    expect(callable.payloads.map((payload) => payload['requestId']), <String>[
      'adjust-stock-abcdefgh',
      'adjust-stock-abcdefgh',
    ]);
  });

  testWidgets('a refusal that proves nothing moved releases the ID', (
    tester,
  ) async {
    // Reusing the ID of an attempt that provably left nothing behind would
    // make an edited retry fail as a duplicate.
    final reader = _Reader()..respondMovements(<TenantQueryDocumentSnapshot>[]);
    final callable = _Callable.failing(
      FirebaseFunctionsException(
        code: 'not-found',
        message: 'The product does not exist in this tenant.',
      ),
    );

    await _pump(
      tester,
      _controller(),
      reader,
      callable: callable,
      requestIds: <String>['adjust-stock-first11', 'adjust-stock-second2'],
    );
    await _submit(tester, units: '4', reason: 'Delivery received');
    await _submit(tester, units: '5', reason: 'Delivery received');

    expect(callable.payloads.map((payload) => payload['requestId']), <String>[
      'adjust-stock-first11',
      'adjust-stock-second2',
    ]);
    expect(
      noticeMessage(tester, 'product-stock-notice'),
      startsWith('This product no longer exists'),
    );
    expect(noticeStatus(tester, 'product-stock-notice'), AppStatus.problem);
  });

  testWidgets('a response that cannot be trusted is reported, not shown', (
    tester,
  ) async {
    final reader = _Reader()..respondMovements(<TenantQueryDocumentSnapshot>[]);
    final callable = _Callable(
      _response(overrides: <String, Object?>{'quantity': 99}),
    );

    await _pump(tester, _controller(), reader, callable: callable);
    await _submit(tester, units: '4', reason: 'Delivery received');

    expect(
      noticeMessage(tester, 'product-stock-notice'),
      startsWith('The adjustment response could not be trusted.'),
    );
  });

  testWidgets('a tenant switch discards an outstanding adjustment', (
    tester,
  ) async {
    final reader = _Reader()..respondMovements(<TenantQueryDocumentSnapshot>[]);
    final callable = _Callable.deferred();
    final controller = _controller();

    await _pump(tester, controller, reader, callable: callable);
    await _submit(
      tester,
      units: '4',
      reason: 'Delivery received',
      settle: false,
    );
    expect(callable.payloads.single['tenantId'], 'tenant-a');

    controller.open(uid: 'manager-a', membership: _membership('tenant-b'));
    await tester.pump();
    callable.complete(_response());
    await tester.pump();
    await tester.pump();

    // The result belonged to a session that is no longer selected.
    expect(find.byKey(const ValueKey('product-stock-notice')), findsNothing);
  });

  testWidgets('the ledger pages forward and back', (tester) async {
    final reader = _Reader()
      ..respondMovements(<TenantQueryDocumentSnapshot>[
        _sale('mv-1'),
        _sale('mv-2'),
        _sale('mv-3'),
      ]);

    await _pump(tester, _controller(), reader, pageSize: 2);

    expect(find.byKey(const ValueKey('product-stock-entry-mv-1')), findsOne);
    expect(
      find.byKey(const ValueKey('product-stock-entry-mv-3')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('product-stock-next')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('product-stock-entry-mv-3')), findsOne);
    expect(reader.movementQueries.last.startAfterDocumentId, 'mv-2');

    await tester.tap(find.byKey(const ValueKey('product-stock-previous')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('product-stock-entry-mv-1')), findsOne);
  });

  testWidgets('the ledger opens this product\'s manual corrections', (
    tester,
  ) async {
    // Both surfaces belong to the inventory domain, so the route needs no
    // injection; it opens under this route's own session scope.
    final reader = _Reader()..respondMovements(<TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader);
    await tester.tap(find.byKey(const ValueKey('product-stock-adjustments')));
    await tester.pumpAndSettle();

    expect(find.text('Adjustments: Cold lager'), findsOne);
    expect(
      reader.queries.last.collectionPath,
      'tenants/tenant-a/stock_adjustments',
    );
    expect(reader.queries.last.equalityFilters, <String, Object?>{
      'productId': 'product-1',
    });
  });

  testWidgets('a stock difference is stated where the correction is made', (
    tester,
  ) async {
    final reader = _Reader()
      ..respondMovements(<TenantQueryDocumentSnapshot>[_sale('mv-1')])
      ..respondAnomalies(<TenantQueryDocumentSnapshot>[
        _stockAnomaly('stock_a'),
      ]);

    await _pump(tester, _controller(), reader);

    // Narrowed to this exact product, by one equality filter so Firestore's
    // automatic single-field index still serves it.
    expect(
      reader.anomalyQuery.collectionPath,
      'tenants/tenant-a/reconciliation_anomalies',
    );
    expect(reader.anomalyQuery.equalityFilters, <String, Object?>{
      'productId': 'product-1',
    });
    expect(reader.anomalyQuery.limit, 6, reason: 'a bounded page of five');

    // §5.1's `Callout`, whose container is how §2.1's status is rendered here: a
    // badge on every row of a list where every row is a difference found would be
    // a list with no signal in it.
    final callout = tester.widget<Callout>(
      find.byKey(const ValueKey('product-stock-difference-stock_a')),
    );
    expect(callout.status, AppStatus.problem);
    expect(callout.title, 'Stock does not match its ledger');
    // The figures come from the vocabulary the differences list shares; the
    // resolution sentence is this screen's own, because it names the form three
    // inches below. The provenance is one instant format across the family now,
    // where a difference used to carry an ISO string and a run a UTC minute.
    expect(
      callout.message,
      'Its ledger expects 10, and the product records 7: 3 fewer than the '
      'ledger accounts for. An adjustment recorded below is how this is put '
      'right.\n'
      'First recorded 2026-08-01 02:30 UTC, found by run rj_abc.',
    );
    // Nothing deletes one of these, so the surface says so rather than letting
    // an old record read as a live one - now behind the fold, because it is true
    // of every difference this screen will ever show.
    expect(
      find.textContaining('may already have been put right'),
      findsNothing,
    );
    await _openDifferenceScope(tester);
    expect(find.textContaining('may already have been put right'), findsOne);
    expect(
      find.byKey(const ValueKey('product-stock-differences-truncated')),
      findsNothing,
    );
  });

  testWidgets('this route folds three explanations, not one of three', (
    tester,
  ) async {
    // Step 4 put the adjustment explanation behind a `Disclosure` and left the
    // other two as loose body text, so this screen has carried one folded
    // explanation and two unfolded ones ever since. All three are permanent
    // helper paragraphs by §5.1's own row, and the quantity note carried the last
    // raw `colorScheme` read on this route.
    final reader = _Reader()
      ..respondMovements(<TenantQueryDocumentSnapshot>[_sale('mv-1')])
      ..respondAnomalies(<TenantQueryDocumentSnapshot>[
        _stockAnomaly('stock_a'),
      ]);

    // **All three describing the figure now live on the reading route, and the
    // correcting sheet carries exactly one.** 2026-08-25 split the four across
    // two routes and left the quantity note and the differences note on both
    // halves; 2026-08-26 took the sheet down to the form it is for, so the two
    // notes about what a stock figure *is* belong to the surface that exists to
    // explain one. Each is still folded, which is what this test is about.
    await _pump(tester, _controller(), reader);

    for (final key in <String>[
      'product-stock-quantity-disclosure',
      'product-stock-differences-scope-disclosure',
      'product-stock-ledger-disclosure',
    ]) {
      expect(find.byKey(ValueKey<String>(key)), findsOne, reason: key);
    }
    expect(
      find.byKey(const ValueKey('product-stock-adjustment-disclosure')),
      findsNothing,
      reason: 'the adjustment explanation belongs to the correction sheet',
    );
    // Closed means gone from the tree rather than clipped to nothing.
    for (final key in <String>[
      'product-stock-quantity-scope',
      'product-stock-differences-scope',
      'product-stock-ledger-scope',
    ]) {
      expect(find.byKey(ValueKey<String>(key)), findsNothing, reason: key);
    }
    await _open(tester, 'What the ledger holds');
    expect(
      _text(tester, 'product-stock-ledger-scope'),
      startsWith('Every sale, verified return, and manual adjustment'),
    );

    // And the correcting sheet carries its own and nothing else: the three
    // above are what *View stock* is for, and repeating them over a form was
    // the redundancy this sheet was cut down to remove.
    await _pump(
      tester,
      _controller(),
      reader,
      callable: _Callable(_response()),
    );
    expect(
      find.byKey(const ValueKey('product-stock-adjustment-disclosure')),
      findsOne,
    );
    for (final key in <String>[
      'product-stock-quantity-disclosure',
      'product-stock-differences-scope-disclosure',
      'product-stock-ledger-disclosure',
    ]) {
      expect(
        find.byKey(ValueKey<String>(key)),
        findsNothing,
        reason: '$key belongs to the reading route',
      );
    }
  });

  testWidgets('every explanation on this route fits its one line on a phone', (
    tester,
  ) async {
    // **Found by a picture rather than by a test.** §5.2 gives `Disclosure` one
    // collapsed line and the widget will not wrap it, so a long summary silently
    // ellipsises - which is what step 4 shipped on the reconciliation day page,
    // unseen for two days because no capture had ever put a `Disclosure` on a
    // phone. This route has four of them, which makes it the right place for the
    // guard.
    //
    // A character count and not a render measurement, deliberately: `flutter
    // test` has no Material fonts, so `didExceedMaxLines` here reports a fallback
    // font's advance widths and calls a 25-character summary too long. The budget
    // was measured in the harness, where the fonts are real.
    final reader = _Reader()
      ..respondMovements(<TenantQueryDocumentSnapshot>[_sale('mv-1')])
      ..respondAnomalies(<TenantQueryDocumentSnapshot>[
        _stockAnomaly('stock_a'),
      ]);

    await _pump(
      tester,
      _controller(),
      reader,
      callable: _Callable(_response()),
      width: 411,
    );

    // **Both halves are measured, since the four are split across two routes.**
    // Pinning a count to one route would let a summary added to the other slip
    // past the guard, which is the opposite of what this test is for.
    final summaries = <String>{
      ...tester
          .widgetList<Disclosure>(find.byType(Disclosure))
          .map((disclosure) => disclosure.summary),
    };

    await _pump(tester, _controller(), reader, width: 411);
    summaries.addAll(
      tester
          .widgetList<Disclosure>(find.byType(Disclosure))
          .map((disclosure) => disclosure.summary),
    );

    expect(summaries, hasLength(4));
    for (final summary in summaries) {
      expect(
        summary.length,
        lessThanOrEqualTo(Disclosure.summaryCharacterBudget),
        reason: summary,
      );
    }
  });

  testWidgets('a product with nothing recorded against it says nothing', (
    tester,
  ) async {
    // An exception report: a permanent "no differences" line on every product
    // would make the one that matters easier to miss rather than harder.
    final reader = _Reader()
      ..respondMovements(<TenantQueryDocumentSnapshot>[_sale('mv-1')])
      ..respondAnomalies(<TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader);

    expect(
      find.byKey(const ValueKey('product-stock-differences-scope-disclosure')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('product-stock-differences-unreadable')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('product-stock-quantity')), findsOne);
  });

  testWidgets('a difference an adjustment cannot resolve says so', (
    tester,
  ) async {
    final reader = _Reader()
      ..respondMovements(<TenantQueryDocumentSnapshot>[])
      // Ascending document ID: the repository proves its own page ordering, so a
      // fixture listed in any other order fails the read rather than the
      // assertion it was written for.
      ..respondAnomalies(<TenantQueryDocumentSnapshot>[
        _stockAnomaly(
          'chain_a',
          overrides: <String, Object?>{
            'anomalyType': 'checkpoint_chain_invalid',
          },
        ),
        _stockAnomaly(
          'movement_a',
          overrides: <String, Object?>{'anomalyType': 'invalid_stock_movement'},
        ),
        _snapshot('quantity_a', <String, Object?>{
          'tenantId': 'tenant-a',
          'productId': 'product-1',
          'jobId': 'rj_abc',
          'anomalyType': 'invalid_product_quantity',
        }),
      ]);

    await _pump(tester, _controller(), reader);

    // Three of the four kinds a product can hold are reports that the comparison
    // could not be trusted. Offering "correct this" for them would be wrong.
    expect(
      _difference(tester, 'movement_a').message,
      contains('An adjustment will not resolve this'),
    );
    expect(
      _difference(tester, 'chain_a').message,
      contains('An adjustment will not resolve it'),
    );
    expect(
      _difference(tester, 'quantity_a').message,
      contains('could not be read as a whole number'),
    );
    // And no time at all is a real answer rather than a blank.
    expect(
      _difference(tester, 'quantity_a').message,
      endsWith('\nFound by run rj_abc.'),
    );
  });

  testWidgets('a bounded page names what it is not showing', (tester) async {
    final reader = _Reader()
      ..respondMovements(<TenantQueryDocumentSnapshot>[])
      ..respondAnomalies(<TenantQueryDocumentSnapshot>[
        for (var index = 0; index < 6; index++) _stockAnomaly('stock_$index'),
      ]);

    await _pump(tester, _controller(), reader);

    expect(
      find.byKey(const ValueKey('product-stock-difference-stock_4')),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('product-stock-difference-stock_5')),
      findsNothing,
    );
    // A notice about this page rather than a standing explanation - it is here
    // only because this product holds more than the page read - so it does not
    // fold.
    final truncated = tester.widget<Callout>(
      find.byKey(const ValueKey('product-stock-differences-truncated')),
    );
    expect(truncated.status, AppStatus.info);
    expect(truncated.message, contains('not a list in time order'));
  });

  testWidgets('an unreadable difference leaves the stock and ledger readable', (
    tester,
  ) async {
    // The recorded quantity is what this route exists for. A reconciliation read
    // that fails must never take it off the screen.
    final reader = _Reader(failAnomalies: true)
      ..respondMovements(<TenantQueryDocumentSnapshot>[_sale('mv-1')]);

    await _pump(tester, _controller(), reader);

    // **`info` rather than `problem`, and the deciding word is "refused".** The
    // same sentence covers a session permitted to read stock and not differences,
    // so calling a permission boundary a fault would invent an answer the code
    // refuses to invent in words.
    final unreadable = tester.widget<Callout>(
      find.byKey(const ValueKey('product-stock-differences-unreadable')),
    );
    expect(unreadable.status, AppStatus.info);
    expect(
      unreadable.message,
      'Whether reconciliation recorded a difference for this product could not '
      'be read. The stock and ledger below are unaffected.',
    );
    expect(find.byKey(const ValueKey('product-stock-failure')), findsNothing);
    _expectText(tester, 'product-stock-quantity', '7');
    expect(find.byKey(const ValueKey('product-stock-entry-mv-1')), findsOne);
  });

  testWidgets('a difference about another product is never shown here', (
    tester,
  ) async {
    // A stock figure is answered for by whoever owns the product, so a record
    // about a different one appearing on this page would be worse than none.
    final reader = _Reader(ignoreFilters: true)
      ..respondMovements(<TenantQueryDocumentSnapshot>[])
      ..respondAnomalies(<TenantQueryDocumentSnapshot>[
        _stockAnomaly(
          'stock_b',
          overrides: <String, Object?>{'productId': 'product-9'},
        ),
      ]);

    await _pump(tester, _controller(), reader);

    expect(find.textContaining('product-9'), findsNothing);
    expect(
      find.byKey(const ValueKey('product-stock-difference-stock_b')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('product-stock-differences-unreadable')),
      findsOne,
    );
    _expectText(tester, 'product-stock-quantity', '7');
  });

  testWidgets('a ledger entry outside this product hides the page', (
    tester,
  ) async {
    final reader = _Reader()
      ..respondMovements(<TenantQueryDocumentSnapshot>[
        _sale('mv-1', overrides: <String, Object?>{'productId': 'product-9'}),
      ]);

    await _pump(tester, _controller(), reader);

    expect(find.byKey(const ValueKey('product-stock-failure')), findsOne);
    expect(
      find.byKey(const ValueKey('product-stock-entry-mv-1')),
      findsNothing,
    );
  });
}

Future<void> _pump(
  WidgetTester tester,
  TenantSessionController controller,
  _Reader reader, {
  int pageSize = 20,
  AdjustStockCallable? callable,
  List<String> requestIds = const <String>['adjust-stock-abcdefgh'],
  double width = 1400,
}) async {
  // The adjustment form adds text fields, so the page carries more than one
  // Scrollable and `scrollUntilVisible` can no longer identify the list. A tall
  // surface builds every row instead, which is what these assertions need.
  tester.view.physicalSize = Size(width, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  var index = 0;
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        // **Two panels since 2026-08-26, not one with a mode.** A test that
        // supplies a callable is a test about correcting stock, and correcting
        // is its own panel now - the one the sheet holds. The rest read the
        // ledger, which is the panel that no longer corrects anything.
        //
        // Neither is pumped inside a sheet here: `onCompleted` is left null so
        // every outcome renders in place, which is what these assertions read.
        // The sheet's own closing behaviour is asserted separately.
        child: Scaffold(
          body: callable == null
              ? TenantProductStockPanel(
                  reader: reader,
                  product: _product(),
                  pageSize: pageSize,
                )
              : TenantProductStockAdjustmentPanel(
                  reader: reader,
                  product: _product(),
                  actions: TenantStockActions(adjustCallable: callable),
                  requestIdFactory: () =>
                      requestIds[index++ < requestIds.length
                          ? index - 1
                          : requestIds.length - 1],
                ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// Fills the form and confirms, which is the only way stock ever moves.
Future<void> _submit(
  WidgetTester tester, {
  required String units,
  required String reason,
  bool settle = true,
}) async {
  await tester.enterText(
    find.byKey(const ValueKey('product-stock-units')),
    units,
  );
  await tester.enterText(
    find.byKey(const ValueKey('product-stock-reason')),
    reason,
  );
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('product-stock-submit')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('product-stock-confirm')));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

/// One `reconciliation_anomalies` record about this product, in the shape
/// `processors.ts` writes it: `variance` is exactly observed minus expected, and
/// the read model refuses a record where it is not.
TenantQueryDocumentSnapshot _stockAnomaly(
  String anomalyId, {
  Map<String, Object?>? overrides,
}) => _snapshot(anomalyId, <String, Object?>{
  'tenantId': 'tenant-a',
  'productId': 'product-1',
  'jobId': 'rj_abc',
  'anomalyType': 'stock_variance',
  'expectedQuantity': 10,
  'observedQuantity': 7,
  'variance': -3,
  'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 30)),
  ...?overrides,
});

TenantQueryDocumentSnapshot _snapshot(
  String anomalyId,
  Map<String, Object?> data,
) => TenantQueryDocumentSnapshot(
  path: 'tenants/tenant-a/reconciliation_anomalies/$anomalyId',
  data: data,
);

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

void _expectText(WidgetTester tester, String key, String value) {
  expect(_text(tester, key), value);
}

/// Opens one of the three permanent explanations on this route, whose prose is
/// removed from the tree while it is closed so a screen reader does not read out
/// what nobody can see.
/// The 4000-high test surface builds every row, so no scroll is needed - and
/// `scrollUntilVisible` cannot be used on this route anyway: the adjustment form
/// puts a second `Scrollable` on the page.
Future<void> _open(WidgetTester tester, String summary) async {
  await tester.tap(find.text(summary));
  await tester.pumpAndSettle();
}

/// One recorded difference, as the notice §5.1 makes it.
Callout _difference(WidgetTester tester, String anomalyId) =>
    tester.widget<Callout>(
      find.byKey(ValueKey('product-stock-difference-$anomalyId')),
    );

Future<void> _openDifferenceScope(WidgetTester tester) =>
    _open(tester, 'Why old differences stay listed');

Future<void> _openQuantityScope(WidgetTester tester) =>
    _open(tester, 'Why stock can be negative');

TenantProduct _product() => TenantProduct.fromDocument(
  path: 'tenants/tenant-a/products/product-1',
  data: _productData(),
);

Map<String, Object?> _productData() => <String, Object?>{
  'name': 'Cold lager',
  'SKU': 'LAGER-001',
  'price': 120.5,
  'quantity': 7,
  'categoryId': 'drinks',
};

Map<String, Object?> _response({Map<String, Object?>? overrides}) {
  final data = <String, Object?>{
    'adjustmentId': 'sa_abc',
    'productId': 'product-1',
    'previousQuantity': 7,
    'quantity': 11,
    'quantityDelta': 4,
  };
  if (overrides != null) data.addAll(overrides);
  return data;
}

TenantQueryDocumentSnapshot _adjustment(String movementId) =>
    TenantQueryDocumentSnapshot(
      path: 'tenants/tenant-a/products/product-1/stock_movements/$movementId',
      data: <String, Object?>{
        'movementId': movementId,
        'tenantId': 'tenant-a',
        'productId': 'product-1',
        'sourceType': 'manual_adjustment',
        'adjustmentType': 'damage',
        'quantityDelta': -3,
        'previousQuantity': 10,
        'quantityAfter': 7,
        'reason': 'Broken in transit',
        'actorUid': 'manager-a',
        'recordedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 9)),
      },
    );

TenantQueryDocumentSnapshot _sale(
  String movementId, {
  Map<String, Object?>? overrides,
}) {
  final data = <String, Object?>{
    'movementId': movementId,
    'tenantId': 'tenant-a',
    'productId': 'product-1',
    'sourceType': 'sale',
    'sourceId': 'chk-1',
    'quantityDelta': -2,
    'recordedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 11)),
  };
  if (overrides != null) data.addAll(overrides);
  return TenantQueryDocumentSnapshot(
    path: 'tenants/tenant-a/products/product-1/stock_movements/$movementId',
    data: data,
  );
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

final class _Callable implements AdjustStockCallable {
  _Callable(this._response) : _error = null, _defer = false;
  _Callable.failing(Object error)
    : _response = null,
      _error = error,
      _defer = false;
  _Callable.deferred() : _response = null, _error = null, _defer = true;

  final Object? _response;
  final Object? _error;
  final bool _defer;
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];
  final List<Completer<Object?>> _pending = <Completer<Object?>>[];

  void complete(Object? response) {
    if (_pending.isEmpty) return;
    _pending.removeAt(0).complete(response);
  }

  @override
  Future<Object?> call(Map<String, Object?> payload) {
    payloads.add(payload);
    if (_defer) {
      final completer = Completer<Object?>();
      _pending.add(completer);
      return completer.future;
    }
    final error = _error;
    if (error != null) return Future<Object?>.error(error);
    return Future<Object?>.value(_response);
  }
}

final class _Reader implements TenantDataReader {
  _Reader({
    this.staffNames = const <String, String>{},
    this.failAnomalies = false,
    this.ignoreFilters = false,
  });

  final Map<String, String> staffNames;

  /// Stands in for a difference read this session cannot make or that fails.
  /// The stock figure and the ledger must still be readable.
  final bool failAnomalies;

  /// Stands in for a transport that answers outside the filter it was given.
  final bool ignoreFilters;

  List<TenantQueryDocumentSnapshot> _movements =
      const <TenantQueryDocumentSnapshot>[];
  List<TenantQueryDocumentSnapshot> _anomalies =
      const <TenantQueryDocumentSnapshot>[];
  final List<TenantCollectionQuery> queries = <TenantCollectionQuery>[];
  final List<String> documentPaths = <String>[];

  void respondMovements(List<TenantQueryDocumentSnapshot> page) =>
      _movements = page;

  void respondAnomalies(List<TenantQueryDocumentSnapshot> page) =>
      _anomalies = page;

  /// Only the ledger's own queries. This route also reads the differences
  /// recorded against the product, so an assertion about the ledger has to say
  /// which query it means.
  List<TenantCollectionQuery> get movementQueries => queries
      .where((query) => query.collectionPath.endsWith('/stock_movements'))
      .toList();

  /// How many times the canonical product document was read.
  ///
  /// **This is what "re-reads" means on the correction sheet.** That surface
  /// shows no ledger and no differences, so it reads neither: the only read it
  /// makes is the quantity its form is about, and counting movement queries
  /// there would be counting a read that correctly no longer happens.
  int get productReads => documentPaths
      .where((path) => path == 'tenants/tenant-a/products/product-1')
      .length;

  TenantCollectionQuery get anomalyQuery => queries
      .where(
        (query) =>
            query.collectionPath == 'tenants/tenant-a/reconciliation_anomalies',
      )
      .single;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    documentPaths.add(path);
    if (path == 'tenants/tenant-a/products/product-1') {
      return TenantDocumentSnapshot(path: path, data: _productData());
    }
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
  ) async {
    queries.add(query);
    final isMovements = query.collectionPath.endsWith('/stock_movements');
    if (!isMovements && failAnomalies) {
      throw StateError('permission-denied');
    }
    // The ledger comes from `respondMovements`; every other collection this route
    // or a route it opens reads must be registered, so a page can never be served
    // another collection's documents under its own name.
    final page = isMovements
        ? _movements
        : query.collectionPath == 'tenants/tenant-a/reconciliation_anomalies'
        ? _anomalies
        : const <TenantQueryDocumentSnapshot>[];
    final cursor = query.startAfterDocumentId;
    final matches = <TenantQueryDocumentSnapshot>[];
    for (final snapshot in page) {
      final id = snapshot.path.split('/').last;
      if (cursor != null && id.compareTo(cursor) <= 0) continue;
      final matchesFilters =
          ignoreFilters ||
          query.equalityFilters.entries.every(
            (filter) => snapshot.data[filter.key] == filter.value,
          );
      if (!matchesFilters) continue;
      matches.add(snapshot);
      if (matches.length >= query.limit) break;
    }
    return matches;
  }
}
