import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/reporting/reporting.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sales-totals-amount')))
          .data,
      'Sales: KES 4820.75 over 37 sales',
    );
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
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('sales-totals-member-self')),
          )
          .label,
      isA<Text>().having((text) => text.data, 'label', 'You (The Manager)'),
    );
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
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('sales-totals-member-cashier-b')),
          )
          .label,
      isA<Text>().having((text) => text.data, 'label', 'cashier-b'),
    );
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
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sales-totals-amount')))
          .data,
      'Sales: 4820.75 over 37 sales',
    );
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

    String rowFor(String key) => tester
        .widget<Text>(find.byKey(ValueKey('sales-totals-tender-$key')))
        .data!;

    expect(rowFor('cash'), 'Cash: KES 2000.25 over 20 sales');
    expect(rowFor('mpesa'), 'M-Pesa: KES 1800.50 over 10 sales');
    expect(rowFor('card'), 'Card: KES 900.00 over 5 sales');
    expect(rowFor('unrecorded'), 'Not recorded: KES 100.00 over 1 sale');
    expect(rowFor('other'), 'Unrecognised: KES 20.00 over 1 sale');
    // Nothing here has confirmed any money arrived, and the surface says so in
    // the one shared sentence every tender surface uses.
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('sales-totals-tender-disclaimer')),
          )
          .data,
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
    // No unrecorded sales means no note about them either.
    expect(
      find.byKey(const ValueKey('sales-totals-tender-unrecorded-note')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('sales-totals-tender-other-note')),
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
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sales-totals-amount')))
          .data,
      'Sales: KES 4820.75 over 37 sales',
    );
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
      tester
          .widget<Text>(find.byKey(const ValueKey('sales-totals-failure')))
          .data,
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
  int staffPageSize = 25,
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
    'scannedTransactions': 37,
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
