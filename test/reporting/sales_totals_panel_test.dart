import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/reporting/reporting.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/stats.dart';
import 'package:flutter_application_1/ui/status.dart';
import 'package:flutter_test/flutter_test.dart';

/// The figure a keyed `StatTile` or `StatLine` is showing.
String _figure(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

/// The message a keyed [Callout] carries.
///
/// The sentences this reads used to be loose `Text`; `design.md` §11 step 8 put
/// each of them in the component §5.1 names for a permanent notice, so the fact
/// is read off the notice rather than off a paragraph.
String _notice(WidgetTester tester, String key) =>
    tester.widget<Callout>(find.byKey(ValueKey(key))).message;

/// Opens a [Disclosure] by its summary. Its child is out of the tree until then.
///
/// **`ensureVisible` and not `scrollUntilVisible`**, which is the trap
/// `PLAN.md` records from 2026-08-14: the latter stops when a widget has been
/// *built*, and a tap on something below the fold lands on nothing without
/// failing. The tender folds sit under a card, a chooser and five figures, so on
/// an 800 x 600 test surface they are past the bottom of the page.
Future<void> _open(WidgetTester tester, String summary) async {
  await tester.ensureVisible(find.text(summary));
  await tester.pumpAndSettle();
  await tester.tap(find.text(summary));
  await tester.pumpAndSettle();
}

void main() {
  group('design.md §11 step 8: the money surface', () {
    testWidgets('the screen\'s title is the header\'s and is not drawn twice', (
      tester,
    ) async {
      // §7: "Title appears once." Step 5a put the title in a `PageHeader` and
      // this panel kept drawing its own `headlineSmall` copy underneath, which
      // is the exact defect §7 names. The panel now draws none - and this test
      // pumps the panel *without* its screen, so a title found here is a second
      // one by construction.
      await _pump(tester, _controller(TenantRole.manager), _Callable(<Object?>[
        _response(),
      ]));

      expect(find.text('Sales totals'), findsNothing);
    });

    testWidgets('every fold on the page fits one line on a phone', (
      tester,
    ) async {
      await _pump(
        tester,
        _controller(TenantRole.owner),
        _Callable(<Object?>[_response(byTender: _byTender())]),
        width: 411,
      );

      final summaries = tester
          .widgetList<Disclosure>(find.byType(Disclosure))
          .map((disclosure) => disclosure.summary)
          .toList();
      // The page's own basis, and the two explanations the tender breakdown
      // carries when it has an unrecorded and an unrecognised bucket.
      expect(summaries, hasLength(3));
      for (final summary in summaries) {
        expect(
          summary.length,
          lessThanOrEqualTo(Disclosure.summaryCharacterBudget),
          reason: summary,
        );
      }
    });

    testWidgets('the unpublished-currency notice is a §2.1 status', (
      tester,
    ) async {
      await _pump(tester, _controller(TenantRole.manager), _Callable(<Object?>[
        _response(),
      ]));

      final callout = tester.widget<Callout>(
        find.byKey(const ValueKey('sales-totals-currency-unknown')),
      );
      // `info` is "offline, read-only, informational" in §2.1's own words:
      // nothing failed and no figure is missing, only its label.
      expect(callout.status, AppStatus.info);
      expect(callout.message, contains('published no currency'));
    });

    testWidgets('the headline figures are not truncated on a phone', (
      tester,
    ) async {
      // §4.1's `compact` band, which is where a fixed minimum tile width put
      // two money tiles side by side and ellipsised both.
      await _pump(
        tester,
        _controller(TenantRole.manager),
        _Callable(<Object?>[_response()]),
        reader: _Reader(currency: 'KES'),
        width: 411,
      );

      final figure = tester.renderObject<RenderBox>(
        find.byKey(const ValueKey('sales-totals-amount')),
      );
      final tile = tester.renderObject<RenderBox>(
        find.ancestor(
          of: find.byKey(const ValueKey('sales-totals-amount')),
          matching: find.byType(StatTile),
        ),
      );
      expect(figure.size.width, lessThanOrEqualTo(tile.size.width));
      expect(_figure(tester, 'sales-totals-amount'), 'KES 4820.75');
    });

    testWidgets('a failed read is a problem notice with its retry inside it', (
      tester,
    ) async {
      final callable = _Callable(<Object?>[
        FirebaseFunctionsException(code: 'unavailable', message: 'no'),
        _response(),
      ]);

      await _pump(tester, _controller(TenantRole.manager), callable);

      final callout = tester.widget<Callout>(
        find.byKey(const ValueKey('sales-totals-failure')),
      );
      // §2.1 gives `problem` the meaning "difference found, unreadable", and a
      // read that produced no figure is unreadable. The action stays the
      // caller's: `Callout` decides where it sits and nothing about what it
      // does.
      expect(callout.status, AppStatus.problem);
      expect(find.byKey(const ValueKey('sales-totals-retry')), findsOne);

      await tester.tap(find.byKey(const ValueKey('sales-totals-retry')));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('sales-totals-failure')), findsNothing);
    });
  });

  testWidgets('today is totalled from what the server holds', (tester) async {
    final callable = _Callable(<Object?>[_response()]);

    await _pump(
      tester,
      _controller(TenantRole.manager),
      callable,
      reader: _Reader(currency: 'KES'),
    );

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sales-totals-range')))
          .data,
      '2026-07-31',
    );
    // **Two figures where there was one sentence**, `design.md` §11 step 8:
    // the takings and the count of sales they were taken over, each in its own
    // `StatTile` at `numeric.hero`.
    expect(_figure(tester, 'sales-totals-amount'), 'KES 4820.75');
    expect(_figure(tester, 'sales-totals-transactions'), '37');
    expect(
      find.byKey(const ValueKey('sales-totals-currency-unknown')),
      findsNothing,
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
    await tester.tap(find.byKey(const ValueKey('sales-totals-member-self')));
    await tester.pump();
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

  testWidgets('one colleague can be totalled separately', (tester) async {
    final callable = _Callable(<Object?>[_response(), _response()]);

    await _pump(
      tester,
      _controller(TenantRole.manager),
      callable,
      reader: _Reader(
        staff: const <String, Map<String, String?>>{
          'tenant-a': <String, String?>{
            'owner-a': 'Amina',
            'user-a': 'The Manager',
            'cashier-b': 'Otieno',
          },
        },
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('sales-totals-member-cashier-b')),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(callable.payloads.last['soldById'], 'cashier-b');
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sales-totals-range')))
          .data,
      '2026-07-31 • Otieno (cashier-b)',
    );
    // The signed-in member reads as itself, not as a UID among colleagues.
    // **Read off the rendering rather than off the widget**: the chips are a
    // `FilterChipBar` as of §11 step 7, whose chip is private, and what this
    // test is about is the word a person sees either way.
    expect(_chipLabel(tester, 'sales-totals-member-self'), 'You (The Manager)');
    expect(
      find.byKey(const ValueKey('sales-totals-member-user-a')),
      findsNothing,
    );
  });

  testWidgets('a member with no recorded name shows its UID', (tester) async {
    final callable = _Callable(<Object?>[_response()]);

    await _pump(
      tester,
      _controller(TenantRole.owner),
      callable,
      reader: _Reader(
        staff: const <String, Map<String, String?>>{
          'tenant-a': <String, String?>{'cashier-b': null},
        },
      ),
    );

    // A staff record also carries an email and a phone number, and a report
    // label is not the place to disclose either.
    expect(_chipLabel(tester, 'sales-totals-member-cashier-b'), 'cashier-b');
    expect(find.textContaining('@example.test'), findsNothing);
  });

  testWidgets('an unreadable staff list still separates my own sales', (
    tester,
  ) async {
    final callable = _Callable(<Object?>[_response(), _response()]);

    await _pump(
      tester,
      _controller(TenantRole.manager),
      callable,
      reader: _Reader(staffUnreadable: true),
    );

    expect(
      find.byKey(const ValueKey('sales-totals-staff-unavailable')),
      findsOne,
    );
    // "Only mine" is answerable from the session alone, so no read can take it
    // away - and the whole-business figure is untouched.
    expect(find.byKey(const ValueKey('sales-totals-amount')), findsOne);
    await tester.tap(find.byKey(const ValueKey('sales-totals-member-self')));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(callable.payloads.last['soldById'], 'user-a');
  });

  testWidgets('a member this business does not have is never sent', (
    tester,
  ) async {
    final callable = _Callable(<Object?>[_response(), _response(), _response()]);
    final reader = _Reader(
      staff: const <String, Map<String, String?>>{
        'tenant-a': <String, String?>{'cashier-b': 'Otieno'},
        // Tenant B has its own roster, and this colleague is not on it.
        'tenant-b': <String, String?>{'cashier-c': 'Wanjiru'},
      },
    );
    final controller = _controller(TenantRole.manager);

    await _pump(tester, controller, callable, reader: reader);
    await tester.tap(
      find.byKey(const ValueKey('sales-totals-member-cashier-b')),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(callable.payloads.last['soldById'], 'cashier-b');

    // Tenant B has its own directory and this UID is not in it.
    controller.open(
      uid: 'user-a',
      membership: _membership('tenant-b', TenantRole.manager),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(callable.payloads.last['tenantId'], 'tenant-b');
    expect(callable.payloads.last.containsKey('soldById'), isFalse);
  });

  testWidgets('a roster longer than one page says so', (tester) async {
    final callable = _Callable(<Object?>[_response()]);

    await _pump(
      tester,
      _controller(TenantRole.owner),
      callable,
      reader: _Reader(
        staff: <String, Map<String, String?>>{
          'tenant-a': <String, String?>{
            for (var index = 0; index < 5; index++)
              'cashier-$index': 'Cashier $index',
          },
        },
      ),
      staffPageSize: 3,
    );

    expect(
      find.byKey(const ValueKey('sales-totals-staff-truncated')),
      findsOne,
    );
  });

  testWidgets('an unpublished currency is stated, never guessed', (
    tester,
  ) async {
    final callable = _Callable(<Object?>[_response()]);

    await _pump(tester, _controller(TenantRole.manager), callable);

    expect(
      find.byKey(const ValueKey('sales-totals-currency-unknown')),
      findsOne,
    );
    expect(_figure(tester, 'sales-totals-amount'), '4820.75');
  });

  testWidgets('the currency is read once, not once per filter', (tester) async {
    final callable = _Callable(<Object?>[_response(), _response()]);
    final reader = _Reader(currency: 'KES');

    await _pump(
      tester,
      _controller(TenantRole.owner),
      callable,
      reader: reader,
    );
    await tester.tap(
      find.byKey(const ValueKey('sales-totals-period-last7Days')),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // None of the code, the category list, or the roster depends on the
    // filters, so a second period must spend no further read on any of them.
    expect(reader.documentPaths, <String>[
      'tenants/tenant-a',
      'tenants/tenant-a/staff/owner-a',
      'tenants/tenant-a/configuration/checkout',
    ]);
    expect(reader.queries, hasLength(2));
    expect(find.textContaining('KES 4820.75'), findsOne);
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
      _notice(tester, 'sales-totals-failure'),
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

  testWidgets('a manager is told cost lines are missing, and no more', (
    tester,
  ) async {
    final callable = _Callable(<Object?>[_response()]);

    await _pump(tester, _controller(TenantRole.manager), callable);

    // Word for word the daily summary's sentence: the same fact about the same
    // sale lines over a different stretch of days.
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sales-totals-cost')))
          .data,
      '96 sale lines have no cost recorded.',
    );
    expect(find.textContaining('Profit'), findsNothing);
  });

  testWidgets('one incomplete cost line is named in the singular', (
    tester,
  ) async {
    // The same agreement rule every count on every reporting surface holds.
    final callable = _Callable(<Object?>[
      _response(overrides: <String, Object?>{'incompleteCostLineCount': 1}),
    ]);

    await _pump(tester, _controller(TenantRole.manager), callable);

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sales-totals-cost')))
          .data,
      '1 sale line has no cost recorded.',
    );
  });

  testWidgets('a complete period says nothing about cost to a manager', (
    tester,
  ) async {
    final callable = _Callable(<Object?>[
      _response(overrides: <String, Object?>{'incompleteCostLineCount': 0}),
    ]);

    await _pump(tester, _controller(TenantRole.manager), callable);

    expect(find.byKey(const ValueKey('sales-totals-cost')), findsNothing);
    expect(find.byKey(const ValueKey('sales-totals-profit')), findsNothing);
  });

  testWidgets('an owner reads the period\'s profit and its margin', (
    tester,
  ) async {
    final callable = _Callable(<Object?>[
      _response(
        overrides: <String, Object?>{
          'profit': 1205.25,
          'incompleteCostLineCount': 0,
        },
      ),
    ]);

    await _pump(
      tester,
      _controller(TenantRole.owner),
      callable,
      reader: _Reader(currency: 'KES'),
    );

    expect(_figure(tester, 'sales-totals-profit'), 'KES 1205.25');
    expect(_figure(tester, 'sales-totals-margin'), '25.0%');
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sales-totals-profit-note')))
          .data,
      'Every sale line behind it carries a cost.',
    );
    // The withheld sentence is gone rather than doubled: the statement above
    // carries the whole of what is known about cost.
    expect(find.byKey(const ValueKey('sales-totals-cost')), findsNothing);
  });

  testWidgets('an owner is told why an incomplete period has no figure', (
    tester,
  ) async {
    // The default response is the shape every period before products carried
    // costs produces: profit equals takings because nothing was subtracted.
    final callable = _Callable(<Object?>[_response()]);

    await _pump(tester, _controller(TenantRole.owner), callable);

    expect(find.byKey(const ValueKey('sales-totals-profit')), findsNothing);
    expect(find.byKey(const ValueKey('sales-totals-cost')), findsNothing);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sales-totals-profit-note')))
          .data,
      'Profit and margin are not shown: 96 sale lines have no cost recorded, '
      'and counting them as free would overstate both.',
    );
    // The takings are unaffected: what is refused is the profit, not the total
    // the manager and the owner both came for.
    expect(find.byKey(const ValueKey('sales-totals-amount')), findsOne);
  });

  testWidgets('a category filter profits from its own lines', (tester) async {
    final callable = _Callable(<Object?>[
      _response(),
      _response(
        overrides: <String, Object?>{
          'sales': 400.0,
          'profit': 100.0,
          'transactions': 12,
          'incompleteCostLineCount': 0,
        },
      ),
    ]);

    await _pump(
      tester,
      _controller(TenantRole.owner),
      callable,
      reader: _Reader(
        currency: 'KES',
        categories: <String, List<String>>{
          'tenant-a': <String>['drinks'],
        },
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('sales-totals-category-drinks')),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // The server sums the matching lines and counts only their costs, so the
    // figure is that category's margin and the basis sentence beside it says
    // what the takings themselves are.
    expect(_figure(tester, 'sales-totals-profit'), 'KES 100.00');
    expect(_figure(tester, 'sales-totals-margin'), '25.0%');
    expect(
      find.byKey(const ValueKey('sales-totals-category-basis')),
      findsOne,
    );
  });

  testWidgets('the takings are split by how they were paid for', (
    tester,
  ) async {
    final callable = _Callable(<Object?>[_response(byTender: _byTender())]);

    await _pump(
      tester,
      _controller(TenantRole.owner),
      callable,
      reader: _Reader(currency: 'KES'),
    );

    // **Five sentences became five figures in a column**, `design.md` §11 step
    // 8: the amount is the figure, its label names the method, and the count it
    // is over sits under the label. Every fact the sentences carried survives.
    String rowFor(String key) => _figure(tester, 'sales-totals-tender-$key');

    expect(rowFor('cash'), 'KES 2000.25');
    expect(rowFor('mpesa'), 'KES 1800.50');
    expect(rowFor('card'), 'KES 900.00');
    expect(rowFor('unrecorded'), 'KES 100.00');
    expect(rowFor('other'), 'KES 20.00');
    for (final method in const <String>[
      'Cash',
      'M-Pesa',
      'Card',
      'Not recorded',
      'Unrecognised',
    ]) {
      expect(find.text(method), findsOne, reason: method);
    }
    expect(find.text('20 sales'), findsOne);
    // The one row of the five that has a single sale behind it still says so in
    // the singular, which is the sentence's own rule kept.
    expect(find.text('1 sale'), findsExactly(2));
    // Nothing here has confirmed any money arrived, and the surface says so in
    // the one shared sentence every tender surface uses. It is a `Callout` and
    // deliberately not a `Disclosure`: `checkout_tender.dart` requires every
    // surface showing a tender to carry it, and a fold is a sentence a person
    // can finish the screen without reading.
    expect(
      _notice(tester, 'sales-totals-tender-disclaimer'),
      'Recorded by the cashier at the till; the payment itself is not '
      'verified.',
    );
  });

  testWidgets('a method nobody used is not listed as zero', (tester) async {
    final callable = _Callable(<Object?>[
      _response(
        // Cash and M-Pesa only, still summing to 4820.75 over 37 sales.
        byTender: _byTender(
          cashSales: 3020.25,
          cashTransactions: 27,
          cardSales: 0,
          cardTransactions: 0,
          unrecordedSales: 0,
          unrecordedTransactions: 0,
          otherSales: 0,
          otherTransactions: 0,
        ),
      ),
    ]);

    await _pump(tester, _controller(TenantRole.owner), callable);

    expect(find.byKey(const ValueKey('sales-totals-tender-cash')), findsOne);
    expect(find.byKey(const ValueKey('sales-totals-tender-mpesa')), findsOne);
    expect(find.byKey(const ValueKey('sales-totals-tender-card')), findsNothing);
    expect(
      find.byKey(const ValueKey('sales-totals-tender-unrecorded')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('sales-totals-tender-other')),
      findsNothing,
    );
    // No unrecorded sales means no note about them either - and the fold itself
    // is absent, not merely its contents.
    expect(
      find.byKey(
        const ValueKey('sales-totals-tender-unrecorded-disclosure'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('sales-totals-tender-other-disclosure')),
      findsNothing,
    );
  });

  testWidgets('an old sale with no method is never called unpaid', (
    tester,
  ) async {
    final callable = _Callable(<Object?>[
      _response(
        // Every sale in the period predates the tender field.
        byTender: _byTender(
          cashSales: 0,
          cashTransactions: 0,
          mpesaSales: 0,
          mpesaTransactions: 0,
          cardSales: 0,
          cardTransactions: 0,
          unrecordedSales: 4800.75,
          unrecordedTransactions: 36,
          otherSales: 20,
          otherTransactions: 1,
        ),
      ),
    ]);

    await _pump(tester, _controller(TenantRole.owner), callable);

    // The explanation is a `Disclosure` now, so it is out of the tree until it
    // is opened - which is also the assertion that it is not permanently in the
    // way of the figures it explains.
    expect(
      find.byKey(const ValueKey('sales-totals-tender-unrecorded-note')),
      findsNothing,
    );
    await _open(tester, 'Why a sale names no method');
    expect(
      tester
          .widget<Text>(
            find.byKey(
              const ValueKey('sales-totals-tender-unrecorded-note'),
            ),
          )
          .data,
      'Sales recorded before payment methods were captured name none, so they '
      'are listed separately rather than as unpaid.',
    );
    expect(find.textContaining('unpaid sale'), findsNothing);
    // Nothing modelled was recorded, so the verification disclaimer would be
    // about nothing that is on screen.
    expect(
      find.byKey(const ValueKey('sales-totals-tender-disclaimer')),
      findsNothing,
    );
  });

  testWidgets('an unrecognised method is reported, not hidden', (
    tester,
  ) async {
    final callable = _Callable(<Object?>[_response(byTender: _byTender())]);

    await _pump(tester, _controller(TenantRole.owner), callable);

    await _open(tester, 'An unrecognised method');
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('sales-totals-tender-other-note')),
          )
          .data,
      'Some sales name a payment method this app does not recognise. Their '
      'takings are still inside the total above.',
    );
  });

  testWidgets('a server that reports no split still reports the total', (
    tester,
  ) async {
    final callable = _Callable(<Object?>[_response()]);

    await _pump(
      tester,
      _controller(TenantRole.owner),
      callable,
      reader: _Reader(currency: 'KES'),
    );

    expect(find.byKey(const ValueKey('sales-totals-tender')), findsNothing);
    expect(_figure(tester, 'sales-totals-amount'), 'KES 4820.75');
  });

  testWidgets('a split that does not add up costs the whole answer', (
    tester,
  ) async {
    // Deliberately harsher than a missing split: a breakdown that disagrees
    // with the figure it accompanies means the answer is not internally
    // consistent, and this is the surface an owner reads takings from.
    final callable = _Callable(<Object?>[
      _response(byTender: _byTender(cashSales: 1999.25)),
    ]);

    await _pump(tester, _controller(TenantRole.owner), callable);

    expect(
      _notice(tester, 'sales-totals-failure'),
      'The server answer could not be trusted, so no total is shown.',
    );
    expect(find.textContaining('4820.75'), findsNothing);
    expect(find.byKey(const ValueKey('sales-totals-tender')), findsNothing);
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
      _notice(tester, 'sales-totals-failure'),
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
      _notice(tester, 'sales-totals-category-basis'),
      'This adds up only the lines in this category, not the whole of each '
      'sale. 25 of the 37 sales read held nothing in it.',
    );
  });

  testWidgets('a single sale read is described in the singular', (tester) async {
    final callable = _Callable(<Object?>[
      _response(
        overrides: <String, Object?>{'transactions': 1},
        scannedTransactions: 1,
      ),
    ]);

    await _pump(
      tester,
      _controller(TenantRole.manager),
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
    await tester.pump();

    expect(
      _notice(tester, 'sales-totals-category-basis'),
      'This adds up only the lines in this category, not the whole of each '
      'sale. 0 of the 1 sale read held nothing in it.',
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
      _notice(tester, 'sales-totals-failure'),
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
  int staffPageSize = 25,
  double? width,
}) async {
  if (width != null) {
    tester.view.physicalSize = Size(width, 891);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
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
            staffPageSize: staffPageSize,
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

/// Answers the canonical category, staff, and configuration reads, or refuses.
final class _Reader implements TenantDataReader {
  _Reader({
    Map<String, List<String>> categories = const <String, List<String>>{},
    Map<String, Map<String, String?>> staff =
        const <String, Map<String, String?>>{},
    this.currency,
    this.throws = false,
    this.staffUnreadable = false,
    this.answersOutsideTenant = false,
  }) : categories = Map<String, List<String>>.of(categories),
       staff = Map<String, Map<String, String?>>.of(staff);

  /// The code published in `configuration/checkout`, or none at all.
  final String? currency;

  /// Category IDs by tenant, named `<id> shelf` so a label is provable.
  final Map<String, List<String>> categories;

  /// Staff UIDs to display names, by business. A `null` name is a member whose
  /// canonical record records none. Every business always has its owner,
  /// because the directory reads that record before anything else.
  final Map<String, Map<String, String?>> staff;

  final bool throws;

  /// Refuses only the staff page, leaving categories readable.
  final bool staffUnreadable;

  /// Answers with a document belonging to another business.
  final bool answersOutsideTenant;
  final List<TenantCollectionQuery> queries = <TenantCollectionQuery>[];
  final List<String> documentPaths = <String>[];

  static const String ownerUid = 'owner-a';

  /// The roster of one business, always including its owner.
  Map<String, String?> _roster(String tenantId) => <String, String?>{
    ownerUid: null,
    ...?staff[tenantId],
  };

  Map<String, Object?> _staffData(String tenantId, String uid) =>
      <String, Object?>{
        'uid': uid,
        'email': '$uid@example.test',
        if (_roster(tenantId)[uid] case final name?) 'name': name,
        'role': uid == ownerUid ? 'owner' : 'cashier',
        'status': 'active',
        'invitationStatus': 'accepted',
      };

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) {
    documentPaths.add(path);
    final segments = path.split('/');
    if (segments.length == 2) {
      // The canonical tenant root, which the staff directory reads to learn
      // which member is the owner.
      return Future<TenantDocumentSnapshot?>.value(
        TenantDocumentSnapshot(
          path: path,
          data: const <String, Object?>{'ownerUid': ownerUid},
        ),
      );
    }
    if (segments.length == 4 && segments[2] == 'staff') {
      final tenantId = segments[1];
      final uid = segments[3];
      return Future<TenantDocumentSnapshot?>.value(
        _roster(tenantId).containsKey(uid)
            ? TenantDocumentSnapshot(
                path: path,
                data: _staffData(tenantId, uid),
              )
            : null,
      );
    }
    final code = currency;
    if (code == null || !path.endsWith('/configuration/checkout')) {
      return Future<TenantDocumentSnapshot?>.value();
    }
    return Future<TenantDocumentSnapshot?>.value(
      TenantDocumentSnapshot(
        path: path,
        data: <String, Object?>{'currency': code},
      ),
    );
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) {
    queries.add(query);
    final isStaff = query.collectionPath.endsWith('/staff');
    if (throws || (isStaff && staffUnreadable)) {
      return Future<List<TenantQueryDocumentSnapshot>>.error(
        StateError('unavailable'),
      );
    }
    final tenantId = query.collectionPath.split('/')[1];
    // Firestore pages a collection in ascending document-ID order and the
    // repository proves it, so the fake has to answer in that order too.
    if (isStaff) {
      final uids = _roster(tenantId).keys.toList()..sort();
      return Future<List<TenantQueryDocumentSnapshot>>.value(<
        TenantQueryDocumentSnapshot
      >[
        for (final uid in uids.take(query.limit))
          TenantQueryDocumentSnapshot(
            path: '${query.collectionPath}/$uid',
            data: _staffData(tenantId, uid),
          ),
      ]);
    }
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

Map<String, Object?> _response({
  Map<String, Object?>? overrides,
  Object? byTender,
  int scannedTransactions = 37,
}) {
  final previous = <String, Object?>{
    'sales': 4820.75,
    'profit': 4820.75,
    'transactions': 37,
    'incompleteCostLineCount': 96,
  };
  if (overrides != null) previous.addAll(overrides);
  return <String, Object?>{
    'previous': previous,
    // Named separately from `overrides`, which only reaches the inner figures.
    'scannedTransactions': scannedTransactions,
    if (byTender != null) 'byTender': byTender,
  };
}

/// The five buckets the handler returns, summing to `_response`.
Map<String, Object?> _byTender({
  double cashSales = 2000.25,
  int cashTransactions = 20,
  double mpesaSales = 1800.5,
  int mpesaTransactions = 10,
  double cardSales = 900,
  int cardTransactions = 5,
  double unrecordedSales = 100,
  int unrecordedTransactions = 1,
  double otherSales = 20,
  int otherTransactions = 1,
}) => <String, Object?>{
  'cash': <String, Object?>{
    'sales': cashSales,
    'transactions': cashTransactions,
  },
  'mpesa': <String, Object?>{
    'sales': mpesaSales,
    'transactions': mpesaTransactions,
  },
  'card': <String, Object?>{
    'sales': cardSales,
    'transactions': cardTransactions,
  },
  'unrecorded': <String, Object?>{
    'sales': unrecordedSales,
    'transactions': unrecordedTransactions,
  },
  'other': <String, Object?>{
    'sales': otherSales,
    'transactions': otherTransactions,
  },
};

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

/// The word a filter chip is drawing, addressed by the key its screen gave it.
String _chipLabel(WidgetTester tester, String key) => tester
    .widget<Text>(
      find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text)),
    )
    .data!;
