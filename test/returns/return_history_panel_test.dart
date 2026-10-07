import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:uzapay_pos/checkout/checkout_receipt.dart';
import 'package:uzapay_pos/returns/returns.dart';
import 'package:uzapay_pos/sales/sales.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:uzapay_pos/ui/record_list.dart';
import 'package:uzapay_pos/ui/snackbar.dart';
import 'package:uzapay_pos/ui/status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/notices.dart';

import '../support/buttons.dart';
import '../support/text.dart';

const String _deviceA = 'dev-0123456789abcdef0123456789abcdef';
const String _businessDate = '2026-07-31';
const String _payloadHash =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

/// The word on a record's standing and its status role together, because §9
/// refuses a standing carried by colour and asserting only one half would let
/// the other drift.
void _expectStatus(
  WidgetTester tester,
  String key,
  String label,
  AppStatus status,
) {
  final badge = tester.widget<StatusBadge>(find.byKey(ValueKey(key)));
  expect(badge.label, label);
  expect(badge.status, status);
}

void main() {
  testWidgets('verified and pending returns are shown distinctly', (
    tester,
  ) async {
    final reader = _Reader(staffNames: <String, String>{'manager-a': 'Amina'})
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _verified('ret-2'),
        _pending('ret-1'),
      ]);

    await _pump(tester, _controller(), reader);

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sale-returns-counts')))
          .data,
      'On this page: 1 verified, 1 pending.',
    );
    // The standing was already the first thing on this record; it is a badge
    // now rather than a glyph beside a heading, so §2.1 decides its colour and
    // §9's icon-and-word requirement is the component's rather than this
    // screen's. "Stock restored" leaves the badge and stays on the record: the
    // `Verified` attribute names when and by whom.
    _expectStatus(
      tester,
      'sale-returns-status-ret-2',
      'Verified',
      AppStatus.ok,
    );
    _expectStatus(
      tester,
      'sale-returns-status-ret-1',
      'Pending verification',
      AppStatus.attention,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('sale-returns-verified-ret-2')),
          )
          .data,
      '2026-08-01 06:00 UTC by Amina (manager-a)',
    );
    // A pending return has restored nothing, so it names no verifier.
    expect(
      find.byKey(const ValueKey('sale-returns-verified-ret-1')),
      findsNothing,
    );
    // The units and the products they came from are what one return is on a
    // page about one sale; the itemisation is a fact about it.
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('sale-returns-subject-ret-1')),
          )
          .data,
      '3 units across 2 products',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sale-returns-lines-ret-1')))
          .data,
      '2 x Tusker, 1 x product-2',
    );
    expect(
      textAt(tester, 'sale-returns-recorded-ret-1'),
      'Recorded 2026-07-31 12:00 UTC by You',
    );
  });

  testWidgets('a sale with no returns says so', (tester) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader);

    expect(find.byKey(const ValueKey('sale-returns-empty')), findsOne);
    expect(find.byKey(const ValueKey('sale-returns-counts')), findsNothing);
    expect(reader.queries.single.equalityFilters, <String, Object?>{
      'saleId': 'co-1',
    });
    expect(reader.queries.single.descending, isTrue);
  });

  testWidgets('a return that names another sale hides the whole page', (
    tester,
  ) async {
    final reader = _Reader(ignoreFilters: true)
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _pending('ret-1', overrides: <String, Object?>{'saleId': 'co-9'}),
      ]);

    await _pump(tester, _controller(), reader);

    expect(find.byKey(const ValueKey('sale-returns-failure')), findsOne);
    expect(
      find.byKey(const ValueKey('sale-returns-entry-ret-1')),
      findsNothing,
    );
  });

  testWidgets('a return whose state contradicts itself hides the page', (
    tester,
  ) async {
    // The verification callable would refuse this document; offering it as
    // pending would invite an action that can never succeed.
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _pending('ret-1', overrides: <String, Object?>{'stockRestored': true}),
      ]);

    await _pump(tester, _controller(), reader);

    expect(find.byKey(const ValueKey('sale-returns-failure')), findsOne);
  });

  testWidgets('returns page forward and back', (tester) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _pending('ret-3'),
        _pending('ret-2'),
        _pending('ret-1'),
      ]);

    await _pump(tester, _controller(), reader, pageSize: 2);
    expect(
      find.byKey(const ValueKey('sale-returns-entry-ret-1')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('sale-returns-next')));
    await tester.pump();
    await tester.pump();
    expect(reader.queries.last.startAfterDocumentId, 'ret-2');
    expect(find.byKey(const ValueKey('sale-returns-entry-ret-1')), findsOne);

    await tester.tap(find.byKey(const ValueKey('sale-returns-previous')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('sale-returns-entry-ret-3')), findsOne);
  });

  testWidgets('a tenant switch discards the outstanding returns page', (
    tester,
  ) async {
    final controller = _controller();
    final reader = _Reader(deferred: true)
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _pending('ret-1'),
      ])
      ..respond('tenants/tenant-b/returns', <TenantQueryDocumentSnapshot>[
        _pending('ret-9', tenantId: 'tenant-b'),
      ]);

    await _pump(tester, controller, reader, settle: false);
    await tester.pump();
    expect(reader.pending.length, 1);

    controller.open(uid: 'user-a', membership: _membership('tenant-b'));
    await tester.pump();
    reader.completeFirst();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('sale-returns-entry-ret-1')),
      findsNothing,
    );

    reader.completeFirst();
    await tester.pump();
    // The route was opened for a sale in the previous business, so the new
    // session cannot answer it. Another business's returns are never shown
    // under that sale's receipt, even if a sale ID coincided.
    expect(
      find.byKey(const ValueKey('sale-returns-entry-ret-9')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('sale-returns-entry-ret-1')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('sale-returns-failure')), findsOne);
  });

  testWidgets('an unreadable staff record leaves the UID in place', (
    tester,
  ) async {
    final reader = _Reader(deniedStaff: true)
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _verified('ret-2'),
      ]);

    await _pump(tester, _controller(), reader);

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('sale-returns-verified-ret-2')),
          )
          .data,
      '2026-08-01 06:00 UTC by manager-a',
    );
    expect(find.byKey(const ValueKey('sale-returns-failure')), findsNothing);
  });

  testWidgets('no session renders the denied state and starts no load', (
    tester,
  ) async {
    final reader = _Reader();

    await _pump(tester, TenantSessionController(), reader);

    expect(find.byKey(const ValueKey('sale-returns-denied')), findsOne);
    expect(reader.queries, isEmpty);
  });

  testWidgets('the sheet names the receipt it is reversing', (tester) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[]);

    await _pumpSheet(tester, _controller(), reader);

    // §7's "Title appears once". **The header is the sheet's own since
    // 2026-08-26**, where it used to be an `AppBar`'s: a sheet is a route with
    // no app bar, so the title and the receipt it names moved into a
    // `PageHeader` inside the sheet. The two facts are unchanged.
    final header = find.byKey(const ValueKey('sale-returns-header'));
    expect(header, findsOne);
    expect(
      find.descendant(of: header, matching: find.text('Return')),
      findsOne,
    );
    expect(
      find.descendant(of: header, matching: find.text(_receipt(1))),
      findsOne,
    );
    // And there is no app bar to repeat either of them.
    expect(find.byType(AppBar), findsNothing);
  });

  testWidgets('the sale route shows only the return process', (tester) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _pending('ret-1'),
      ]);

    await _pumpSheet(
      tester,
      _controller(),
      reader,
      writer: _Writer(),
      width: 411,
    );

    expect(find.byKey(const ValueKey('sale-returns-form')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('sale-returns-entry-ret-1')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('sale-returns-next')), findsNothing);
    // The sheet opens on the form: no heading repeating the header, and no
    // explanation above the first control.
    expect(find.text('Record a return'), findsNothing);
    expect(find.text('What a return does'), findsNothing);
    expect(find.byKey(const ValueKey('sale-returns-scope')), findsNothing);
  });

  testWidgets('without a writer the route stays read-only', (tester) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader);

    expect(find.byKey(const ValueKey('sale-returns-form')), findsNothing);
    expect(find.byKey(const ValueKey('sale-returns-submit')), findsNothing);
  });

  testWidgets('the form states what is still available to return', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _pending('ret-1'),
      ]);

    await _pump(tester, _controller(), reader, writer: _Writer());

    // Two of product-1 and one of product-2 are already recorded as pending,
    // and pending units count against what may still be requested.
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('sale-returns-remaining-product-1')),
          )
          .data,
      'Tusker: 2 of 4 available',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('sale-returns-remaining-product-2')),
          )
          .data,
      'Water: 4 of 5 available',
    );
  });

  testWidgets('recording a return needs quantities, a reason, and a confirm', (
    tester,
  ) async {
    final writer = _Writer();
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader, writer: writer);

    // Nothing selected and no reason: the action is unavailable.
    expect(pressable(tester, 'sale-returns-submit'), isFalse);

    await tester.tap(
      find.byKey(const ValueKey('sale-returns-increase-product-1')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('sale-returns-increase-product-1')),
    );
    await tester.pump();
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('sale-returns-quantity-product-1')),
          )
          .data,
      '2',
    );
    // Still refused without a reason.
    expect(pressable(tester, 'sale-returns-submit'), isFalse);

    // **Through *Other*, which is the free-text fallback.** The list cannot
    // name every way a bottle comes back, and a list that cannot say what
    // happened makes people pick the nearest wrong entry.
    await tester.tap(find.byKey(const ValueKey('sale-returns-reason-choice')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other').last);
    await tester.pumpAndSettle();
    // Choosing *Other* is not itself a reason: the field behind it is still
    // empty, so the control stays refused.
    expect(pressable(tester, 'sale-returns-submit'), isFalse);
    await tester.enterText(
      find.byKey(const ValueKey('sale-returns-reason')),
      'Damaged bottle',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sale-returns-submit')));
    await tester.pumpAndSettle();

    // A confirmation is required, and cancelling writes nothing.
    await tester.tap(find.byKey(const ValueKey('sale-returns-cancel-confirm')));
    await tester.pumpAndSettle();
    expect(writer.intents, isEmpty);

    await tester.tap(find.byKey(const ValueKey('sale-returns-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sale-returns-confirm')));
    await tester.pumpAndSettle();

    final intent = writer.intents.single;
    expect(intent.saleId, 'co-1');
    expect(intent.createdBy, 'user-a');
    expect(intent.reason, 'Damaged bottle');
    expect(intent.lines.single.productId, 'product-1');
    expect(intent.lines.single.quantity, 2);
    expect(
      snackNotice(tester).message,
      startsWith('Return recorded. No stock has been restored yet'),
    );
    // **`ok` is a claim about the record, not about the stock**, and the
    // sentence beside it is what keeps that honest: the return exists, and
    // nothing has moved until a manager verifies it.
    expect(snackNotice(tester).status, AppStatus.ok);
  });

  testWidgets('a queued return closes the sheet it was recorded in', (
    tester,
  ) async {
    // **The result the product actually produces.** The composition root wires
    // `QueuedTenantReturnWriter`, which makes every return durable on the device
    // and replays it, so `queued` - never `committed` - is what this sheet sees
    // on a phone. Gating the close on the notice's status left it open on every
    // real return.
    final writer = _Writer(const TenantReturnWriteResult.queued());
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[]);

    await _pumpSheet(tester, _controller(), reader, writer: writer);

    await tester.tap(
      find.byKey(const ValueKey('sale-returns-increase-product-1')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sale-returns-reason-choice')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Damaged or broken').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sale-returns-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sale-returns-confirm')));
    await tester.pumpAndSettle();

    expect(writer.intents, hasLength(1));
    expect(find.byKey(const ValueKey('sale-returns-form')), findsNothing);
    // Recorded, and not restored: nothing here claims the server has it, and
    // nothing announces an outage either - `queued` is every return on a
    // connected phone too.
    expect(
      snackNotice(tester).message,
      startsWith('Return recorded. No stock has been restored yet'),
    );
    expect(snackNotice(tester).status, AppStatus.ok);
  });

  testWidgets('the quantity can never exceed what is available', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader, writer: _Writer());

    for (var tap = 0; tap < 6; tap++) {
      await tester.tap(
        find.byKey(const ValueKey('sale-returns-increase-product-1')),
      );
      await tester.pump();
    }

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('sale-returns-quantity-product-1')),
          )
          .data,
      '4',
    );
  });

  testWidgets('an ambiguous write tells the user not to record it again', (
    tester,
  ) async {
    final writer = _Writer(
      const TenantReturnWriteResult.ambiguous('write_timeout'),
    );
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader, writer: writer);
    await tester.tap(
      find.byKey(const ValueKey('sale-returns-increase-product-1')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sale-returns-reason-choice')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Damaged or broken').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sale-returns-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sale-returns-confirm')));
    await tester.pumpAndSettle();

    expect(snackNotice(tester).message, startsWith('The result is unknown.'));

    // The retry reuses the same deterministic document, so the create-only rule
    // refuses a replay instead of recording the reversal twice.
    await tester.tap(find.byKey(const ValueKey('sale-returns-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sale-returns-confirm')));
    await tester.pumpAndSettle();
    expect(writer.intents.length, 2);
    expect(writer.intents.last.returnId, writer.intents.first.returnId);
  });

  testWidgets('a manager verifies a pending return and sees what moved', (
    tester,
  ) async {
    final callable = _VerifyCallable(<String, Object?>{
      'returnId': 'ret-1',
      'verificationId': 'rv_abc',
      'restoredProducts': <Object?>[
        <String, Object?>{
          'productId': 'product-1',
          'quantityRestored': 2,
          'previousQuantity': 10,
          'quantity': 12,
        },
        <String, Object?>{
          'productId': 'product-2',
          'quantityRestored': 1,
          'previousQuantity': 4,
          'quantity': 5,
        },
      ],
    });
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _pending('ret-1'),
      ]);

    await _pump(
      tester,
      _controller(role: TenantRole.manager),
      reader,
      verifyCallable: callable,
    );

    // A confirmation naming the exact units is required first.
    await tester.tap(find.byKey(const ValueKey('sale-returns-verify-ret-1')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('adds 2 x Tusker, 1 x product-2 back to stock'),
      findsOne,
    );
    await tester.tap(find.byKey(const ValueKey('sale-returns-cancel-verify')));
    await tester.pumpAndSettle();
    expect(callable.payloads, isEmpty);

    await tester.tap(find.byKey(const ValueKey('sale-returns-verify-ret-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sale-returns-confirm-verify')));
    await tester.pumpAndSettle();

    expect(callable.payloads.single, <String, Object?>{
      'tenantId': 'tenant-a',
      'returnId': 'ret-1',
      'requestId': 'verify-return-abcdefgh',
    });
    expect(snackNotice(tester).message, 'Restored 3 units across 2 products.');
  });

  testWidgets('a cashier is never offered the restore action', (tester) async {
    final callable = _VerifyCallable(const <String, Object?>{});
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _pending('ret-1'),
      ]);

    await _pump(tester, _controller(), reader, verifyCallable: callable);

    expect(
      find.byKey(const ValueKey('sale-returns-verify-ret-1')),
      findsNothing,
    );
    expect(callable.payloads, isEmpty);
  });

  testWidgets('a verified return is terminal on screen', (tester) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _verified('ret-2'),
      ]);

    await _pump(
      tester,
      _controller(role: TenantRole.manager),
      reader,
      verifyCallable: _VerifyCallable(const <String, Object?>{}),
    );

    expect(
      find.byKey(const ValueKey('sale-returns-verify-ret-2')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('sale-returns-verified-ret-2')), findsOne);
  });

  testWidgets('a return states the same facts on a phone', (tester) async {
    // The class of defect the staff directory found: a screen that has only
    // ever been laid out wide. One action is under §4.3's threshold, so it is
    // still a 48dp button here rather than something behind a menu.
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _pending('ret-1'),
      ]);

    await _pump(
      tester,
      _controller(role: TenantRole.manager),
      reader,
      verifyCallable: _VerifyCallable(const <String, Object?>{}),
      width: 411,
    );

    expect(
      RecordList.formFor(tester.view.physicalSize.width),
      RecordForm.stackedCards,
    );
    for (final key in <String>[
      'sale-returns-entry-ret-1',
      'sale-returns-subject-ret-1',
      'sale-returns-status-ret-1',
      'sale-returns-lines-ret-1',
      'sale-returns-reason-ret-1',
      'sale-returns-recorded-ret-1',
      'sale-returns-verify-ret-1',
    ]) {
      expect(find.byKey(ValueKey<String>(key)), findsOne, reason: key);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('each refusal is reported as its own outcome', (tester) async {
    // **The status is part of the outcome now, and the first row is why.** A
    // return that had already been verified is not a failure: the stock the
    // manager wanted restored *is* restored, so the intent is satisfied and the
    // sentence's own point is that nothing needed doing. Painting it the same
    // red as "only an owner may restore stock" would report a fault where there
    // is none, which is the §1 failure this model ends.
    final refusals = <List<String>, (String, AppStatus)>{
      <String>[
        'failed-precondition',
        'This return has already been verified.',
      ]: (
        'This return had already been verified, so nothing was restored '
            'again.',
        AppStatus.info,
      ),
      <String>[
        'failed-precondition',
        'The return quantity for product product-1 exceeds the immutable sale.',
      ]: (
        'This return covers more than the original sale still allows. It '
            'cannot be verified; record a corrected return instead.',
        AppStatus.problem,
      ),
      <String>['permission-denied', 'Denied.']: (
        'Only an owner, administrator, or manager may restore stock.',
        AppStatus.problem,
      ),
    };

    for (final entry in refusals.entries) {
      final reader = _Reader()
        ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
          _pending('ret-1'),
        ]);

      await _pump(
        tester,
        _controller(role: TenantRole.manager),
        reader,
        verifyCallable: _VerifyCallable.failing(
          FirebaseFunctionsException(
            code: entry.key.first,
            message: entry.key.last,
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('sale-returns-verify-ret-1')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('sale-returns-confirm-verify')),
      );
      await tester.pumpAndSettle();

      expect(
        snackNotice(tester).message,
        entry.value.$1,
        reason: entry.key.first,
      );
      expect(
        snackNotice(tester).status,
        entry.value.$2,
        reason: entry.key.first,
      );
    }
  });

  testWidgets('a response naming another return is not believed', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _pending('ret-1'),
      ]);

    await _pump(
      tester,
      _controller(role: TenantRole.manager),
      reader,
      verifyCallable: _VerifyCallable(<String, Object?>{
        'returnId': 'ret-9',
        'verificationId': 'rv_abc',
        'restoredProducts': <Object?>[
          <String, Object?>{
            'productId': 'product-1',
            'quantityRestored': 2,
            'previousQuantity': 10,
            'quantity': 12,
          },
        ],
      }),
    );

    await tester.tap(find.byKey(const ValueKey('sale-returns-verify-ret-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sale-returns-confirm-verify')));
    await tester.pumpAndSettle();

    expect(
      snackNotice(tester).message,
      startsWith('The verification response could not be trusted.'),
    );
  });

  testWidgets('a tenant switch discards an outstanding verification', (
    tester,
  ) async {
    final controller = _controller(role: TenantRole.manager);
    final callable = _VerifyCallable.deferred();
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _pending('ret-1'),
      ]);

    await _pump(tester, controller, reader, verifyCallable: callable);
    await tester.tap(find.byKey(const ValueKey('sale-returns-verify-ret-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sale-returns-confirm-verify')));
    await tester.pump();

    controller.open(
      uid: 'user-a',
      membership: _membership('tenant-b', role: TenantRole.manager),
    );
    await tester.pump();
    callable.complete(<String, Object?>{
      'returnId': 'ret-1',
      'verificationId': 'rv_abc',
      'restoredProducts': <Object?>[
        <String, Object?>{
          'productId': 'product-1',
          'quantityRestored': 2,
          'previousQuantity': 10,
          'quantity': 12,
        },
        <String, Object?>{
          'productId': 'product-2',
          'quantityRestored': 1,
          'previousQuantity': 4,
          'quantity': 5,
        },
      ],
    });
    await tester.pumpAndSettle();

    // The previous business's result may never surface in the new session.
    expect(find.byType(AppSnackBar), findsNothing);
  });

  testWidgets('an incomplete returns page offers no record form', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _pending('ret-3'),
        _pending('ret-2'),
        _pending('ret-1'),
      ]);

    await _pump(tester, _controller(), reader, pageSize: 2, writer: _Writer());

    // The remaining quantity can only be derived from the complete set, and a
    // partial page would overstate it.
    expect(find.byKey(const ValueKey('sale-returns-form')), findsNothing);
    expect(
      find.byKey(const ValueKey('sale-returns-form-unavailable')),
      findsOne,
    );
  });

  testWidgets('the feed opens on today and on every standing', (tester) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _verified('ret-2'),
        _pending('ret-1'),
      ]);

    await _pumpFeed(tester, _controller(role: TenantRole.manager), reader);

    // **The default is a query, not a sieve.** The day reaches the read
    // boundary as an exact filter; the standing is absent, because "every
    // standing" is the absence of one rather than a third value.
    final query = reader.queries.last;
    expect(query.equalityFilters['recordedOn'], _businessDate);
    expect(query.equalityFilters.containsKey('status'), isFalse);
    expect(find.byKey(const ValueKey('return-feed-entry-ret-1')), findsOne);
    expect(find.byKey(const ValueKey('return-feed-entry-ret-2')), findsOne);
  });

  testWidgets('the standing filter narrows to what is waiting', (tester) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _verified('ret-2'),
        _pending('ret-1'),
      ]);

    await _pumpFeed(tester, _controller(role: TenantRole.manager), reader);
    await tester.tap(find.byKey(const ValueKey('return-feed-standing-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pending').last);
    await tester.pumpAndSettle();

    expect(reader.queries.last.equalityFilters['status'], 'pending');
    expect(find.byKey(const ValueKey('return-feed-entry-ret-1')), findsOne);
    expect(find.byKey(const ValueKey('return-feed-entry-ret-2')), findsNothing);
  });

  testWidgets('the day filter always narrows to exactly one day', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _pending('ret-1'),
      ]);

    await _pumpFeed(tester, _controller(role: TenantRole.manager), reader);

    // **There is no "every day" reading any more.** The control was three fixed
    // options - today, yesterday, all dates - and is a date picker, so every
    // query from this screen names a day. The escape the removed option existed
    // for expired when `recordedOn` became required (#110).
    expect(reader.queries.last.equalityFilters['recordedOn'], '2026-07-31');
    expect(
      find.byKey(const ValueKey('return-feed-day-picker')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('return-feed-entry-ret-1')), findsOne);
  });

  testWidgets('picking a day re-reads against that day', (tester) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _pending('ret-1'),
      ]);

    await _pumpFeed(tester, _controller(role: TenantRole.manager), reader);
    await tester.tap(find.byKey(const ValueKey('return-feed-day-picker')));
    await tester.pumpAndSettle();

    // The picker names what it is choosing, rather than leaving the caption
    // that used to sit above the control to say it.
    expect(find.text('Returns recorded on'), findsOneWidget);

    await tester.tap(find.text('29'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // A day the old three options could not reach at all.
    expect(reader.queries.last.equalityFilters['recordedOn'], '2026-07-29');
  });

  testWidgets('a day with no returns says the filter matched nothing', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(
        'tenants/tenant-a/returns',
        const <TenantQueryDocumentSnapshot>[],
      );

    await _pumpFeed(tester, _controller(role: TenantRole.manager), reader);

    // Not "no returns yet": the business may have hundreds on another day, and
    // a screen that says otherwise is lying about its own controls. With a day
    // always applied there is no longer any state in which it could say it, so
    // the empty state names the day instead.
    expect(find.byKey(const ValueKey('return-feed-no-matches')), findsOne);
    expect(find.text('No returns on 2026-07-31'), findsOneWidget);
  });

  testWidgets('a narrow card never cuts the receipt off', (tester) async {
    // **The reported defect.** The receipt, the unit count and the amount were
    // one `Row` in which only the receipt could shrink, so on a phone it was
    // the receipt that lost - a card reading `#0` and an ellipsis, which is
    // the one fact on the line somebody holding the paper is matching against.
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _pending('ret-1'),
      ])
      ..documents['tenants/tenant-a/sales/co-1'] = _expensiveSale;

    await _pumpFeed(
      tester,
      _controller(role: TenantRole.manager),
      reader,
      width: 360,
    );

    final receipt = tester.renderObject<RenderParagraph>(
      find.byKey(const ValueKey('return-feed-sale-ret-1')),
    );
    expect(receipt.didExceedMaxLines, isFalse);
    // Still the receipt rather than the document ID, so the assertion above is
    // about the line that was breaking and not about a fallback.
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('return-feed-sale-ret-1')))
          .data,
      '#0001',
    );
    // And the amount it was competing with is still drawn in full.
    expect(find.byKey(const ValueKey('return-feed-value-ret-1')), findsOne);
  });

  testWidgets('a pending return says the stock has not moved yet', (
    tester,
  ) async {
    // The takings net a return as soon as it is filed; the server restores
    // stock only on verification. The card has to carry both halves, or a
    // person reads the amount coming off as the shelf coming back.
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _verified('ret-2'),
        _pending('ret-1'),
      ]);

    await _pumpFeed(tester, _controller(role: TenantRole.manager), reader);

    expect(
      find.byKey(const ValueKey('return-feed-stock-note-ret-1')),
      findsOne,
    );
    // A verified return has already put the stock back, so saying it has not
    // would be the same defect pointing the other way.
    expect(
      find.byKey(const ValueKey('return-feed-stock-note-ret-2')),
      findsNothing,
    );
  });

  testWidgets('the home feed displays returns from every sale', (tester) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _verified('ret-2'),
        _pending('ret-1', overrides: <String, Object?>{'saleId': 'co-9'}),
      ]);

    await _pumpFeed(tester, _controller(role: TenantRole.manager), reader);

    expect(find.byKey(const ValueKey('return-feed-entry-ret-2')), findsOne);
    expect(find.byKey(const ValueKey('return-feed-entry-ret-1')), findsOne);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('return-feed-sale-ret-1')))
          .data,
      'co-9',
    );
    // The day the screen opens on is part of the query; the standing is not,
    // because "every standing" is the absence of a filter.
    expect(reader.queries.single.equalityFilters, <String, Object?>{
      'tenantId': 'tenant-a',
      'recordedOn': _businessDate,
    });
  });
}

/// The screen opens on today and on every standing, and both narrow.
Future<void> _pumpFeed(
  WidgetTester tester,
  TenantSessionController controller,
  _Reader reader, {
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
        child: TenantReturnFeedScreen(
          reader: reader,
          // The day the fixtures were recorded on, so the screen opens on the
          // filter's default and shows them.
          clock: () => DateTime.utc(2026, 7, 31, 15),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _pump(
  WidgetTester tester,
  TenantSessionController controller,
  _Reader reader, {
  int pageSize = 20,
  bool settle = true,
  TenantReturnWriter? writer,
  VerifyReturnCallable? verifyCallable,
  double width = 1400,
}) async {
  // The record form adds a text field, so the page carries more than one
  // Scrollable and `scrollUntilVisible` can no longer identify the list. A tall
  // surface builds every row instead, which is what these assertions need.
  tester.view.physicalSize = Size(width, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: Scaffold(
          body: TenantSaleReturnsPanel(
            reader: reader,
            request: _request(),
            pageSize: pageSize,
            actions: writer == null && verifyCallable == null
                ? null
                : TenantReturnActions(
                    writer: writer,
                    verifyCallable: verifyCallable,
                  ),
            requestIdFactory: () => 'return-abcdefgh',
          ),
        ),
      ),
    ),
  );
  if (!settle) return;
  await tester.pump();
  await tester.pump();
}

/// Opens the return sheet the way the sales surfaces do, and settles it.
///
/// **It goes through `openTenantSaleReturnSheet` rather than pumping the panel
/// bare**, so what these tests read is the composition a person actually gets:
/// the sheet's own header, its drag controller reaching the list, and the
/// cancel control that only exists when something can close the sheet.
Future<void> _pumpSheet(
  WidgetTester tester,
  TenantSessionController controller,
  _Reader reader, {
  TenantReturnWriter? writer,
  VerifyReturnCallable? verifyCallable,
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
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openTenantSaleReturnSheet(
                context,
                reader: reader,
                request: _request(),
                actions: writer == null && verifyCallable == null
                    ? null
                    : TenantReturnActions(
                        writer: writer,
                        verifyCallable: verifyCallable,
                      ),
                requestIdFactory: () => 'return-abcdefgh',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// Records every payload handed to the verification callable.
final class _VerifyCallable implements VerifyReturnCallable {
  _VerifyCallable(this._response) : _error = null, _defer = false;

  _VerifyCallable.failing(Object error)
    : _response = null,
      _error = error,
      _defer = false;

  _VerifyCallable.deferred() : _response = null, _error = null, _defer = true;

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

/// Records every intent handed to the write boundary.
final class _Writer implements TenantReturnWriter {
  _Writer([this._result = const TenantReturnWriteResult.committed()]);

  final TenantReturnWriteResult _result;
  final List<TenantReturnCreateIntent> intents = <TenantReturnCreateIntent>[];

  @override
  Future<TenantReturnWriteResult> recordReturn(
    TenantReturnCreateIntent intent,
  ) async {
    intents.add(intent);
    return _result;
  }
}

TenantSaleReturnsRequest _request() => TenantSaleReturnsRequest(sale: _sale());

String _receipt(int sequence) => formatCheckoutReceiptNumber(
  deviceId: _deviceA,
  businessDate: _businessDate,
  sequence: sequence,
);

TenantSale _sale() => TenantSale.fromDocument(
  path: 'tenants/tenant-a/sales/co-1',
  data: <String, Object?>{
    'checkoutId': 'co-1',
    'tenantId': 'tenant-a',
    'soldById': 'user-a',
    'payloadHash': _payloadHash,
    'payloadSchemaVersion': 2,
    'currency': 'KES',
    'businessDate': _businessDate,
    'shiftId': 'shift-a',
    'deviceId': _deviceA,
    'receiptNumber': _receipt(1),
    'receiptSequence': 1,
    'items': <Object?>[
      <String, Object?>{
        'productId': 'product-1',
        'name': 'Tusker',
        'quantity': 4,
        'unitPriceMinor': 500,
        'lineTotalMinor': 2000,
      },
      <String, Object?>{
        'productId': 'product-2',
        'name': 'Water',
        'quantity': 5,
        'unitPriceMinor': 100,
        'lineTotalMinor': 500,
      },
    ],
    'subtotalMinor': 2500,
    'subtotal': 25.0,
    'discountMinor': 0,
    'discount': 0.0,
    'totalMinor': 2500,
    'total': 25.0,
    'createdAt': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 12)),
  },
);

/// The same sale, priced so its returned value is a long string. The facts
/// line only misbehaves when the amount beside the receipt is wide.
final Map<String, Object?> _expensiveSale = <String, Object?>{
  'checkoutId': 'co-1',
  'tenantId': 'tenant-a',
  'soldById': 'user-a',
  'payloadHash': _payloadHash,
  'payloadSchemaVersion': 2,
  'currency': 'KES',
  'businessDate': _businessDate,
  'shiftId': 'shift-a',
  'deviceId': _deviceA,
  'receiptNumber': _receipt(1),
  'receiptSequence': 1,
  'items': <Object?>[
    <String, Object?>{
      'productId': 'product-1',
      'name': 'Tusker',
      'quantity': 4,
      'unitPriceMinor': 6225000,
      'lineTotalMinor': 24900000,
    },
    <String, Object?>{
      'productId': 'product-2',
      'name': 'Water',
      'quantity': 5,
      'unitPriceMinor': 100,
      'lineTotalMinor': 500,
    },
  ],
  'subtotalMinor': 24900500,
  'subtotal': 249005.0,
  'discountMinor': 0,
  'discount': 0.0,
  'totalMinor': 24900500,
  'total': 249005.0,
  'createdAt': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 12)),
};

TenantSessionController _controller({TenantRole role = TenantRole.cashier}) =>
    TenantSessionController()..open(
      uid: 'user-a',
      membership: _membership('tenant-a', role: role),
    );

TenantMembership _membership(
  String tenantId, {
  TenantRole role = TenantRole.cashier,
}) => TenantMembership(
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

TenantQueryDocumentSnapshot _pending(
  String returnId, {
  String tenantId = 'tenant-a',
  Map<String, Object?>? overrides,
}) {
  final data = <String, Object?>{
    'returnId': returnId,
    'tenantId': tenantId,
    'saleId': 'co-1',
    'businessDate': _businessDate,
    'recordedOn': _businessDate,
    'createdBy': 'user-a',
    'status': 'pending',
    'reason': 'Damaged bottle',
    'itemsReturned': <Object?>[
      <String, Object?>{
        'productId': 'product-1',
        'productName': 'Tusker',
        'quantity': 2,
      },
      <String, Object?>{'productId': 'product-2', 'quantity': 1},
    ],
    'createdAt': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 12)),
  };
  if (overrides != null) data.addAll(overrides);
  return TenantQueryDocumentSnapshot(
    path: 'tenants/$tenantId/returns/$returnId',
    data: data,
  );
}

TenantQueryDocumentSnapshot _verified(String returnId) {
  final base = _pending(returnId);
  return TenantQueryDocumentSnapshot(
    path: base.path,
    data: <String, Object?>{
      ...base.data,
      'status': 'verified',
      'verified': true,
      'verifiedBy': 'manager-a',
      'verifiedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 6)),
      'stockRestored': true,
      'stockRestoredAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 6)),
      'stockRestorationId': 'rv_abc',
    },
  );
}

final class _Reader implements TenantDataReader {
  _Reader({
    this.deferred = false,
    this.deniedStaff = false,
    this.ignoreFilters = false,
    this.staffNames = const <String, String>{},
  });

  final bool deferred;

  /// Stands in for a staff record this role may not read: the row must still
  /// render, labelled by the authoritative UID.
  final bool deniedStaff;
  final bool ignoreFilters;
  final Map<String, String> staffNames;
  final Map<String, List<TenantQueryDocumentSnapshot>> _pages =
      <String, List<TenantQueryDocumentSnapshot>>{};
  final List<TenantCollectionQuery> queries = <TenantCollectionQuery>[];
  final List<Completer<List<TenantQueryDocumentSnapshot>>> pending =
      <Completer<List<TenantQueryDocumentSnapshot>>>[];
  final List<List<TenantQueryDocumentSnapshot>> _deferredResults =
      <List<TenantQueryDocumentSnapshot>>[];

  void respond(String path, List<TenantQueryDocumentSnapshot> page) =>
      _pages[path] = page;

  void completeFirst() {
    if (pending.isEmpty) return;
    pending.removeAt(0).complete(_deferredResults.removeAt(0));
  }

  /// Documents this reader serves outright, by path. Used for the sale
  /// behind a return, which is what puts a receipt and an amount on the card.
  final Map<String, Map<String, Object?>> documents =
      <String, Map<String, Object?>>{};

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    if (documents[path] case final data?) {
      return TenantDocumentSnapshot(path: path, data: data);
    }
    if (deniedStaff) throw StateError('permission-denied');
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
    final all = _pages[query.collectionPath] ?? const [];
    final cursor = query.startAfterDocumentId;
    final matches = <TenantQueryDocumentSnapshot>[];
    for (final snapshot in all) {
      final id = snapshot.path.split('/').last;
      if (cursor != null && id.compareTo(cursor) >= 0) continue;
      final matchesFilters =
          ignoreFilters ||
          query.equalityFilters.entries.every(
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
