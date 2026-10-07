import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:uzapay_pos/reporting/reporting.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:uzapay_pos/ui/fields.dart';
import 'package:uzapay_pos/ui/card.dart';
import 'package:uzapay_pos/ui/status.dart';
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

/// Chooses one option from an [AppSelect], opening it first.
///
/// **The three sales-totals filters became dropdowns on 2026-08-23**, at the
/// product owner's direction that a surface carrying more than one filter uses
/// them. Every option kept the key its chip had, through `AppSelectItem.key`, so
/// what changed for these tests is only that an option has to be *reached*: a
/// closed `DropdownButton` builds every item into itself to display the selected
/// one, so the key resolves while the menu is shut and the widget behind it is
/// not hit-testable. That is the same shape as the trap above - a tap that lands
/// on nothing without failing - which is why this opens the control first and
/// takes the overlay's copy of the key rather than the button's.
Future<void> _choose(WidgetTester tester, String select, String option) async {
  final control = find.byKey(ValueKey(select));
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  await tester.tap(control);
  await tester.pumpAndSettle();
  // **Tap the option's own `Text`, not the `DropdownMenuItem`.** A closed
  // `DropdownButton` keeps a copy of the *selected* item so it can display
  // it, and that copy is offstage - so a bare `.last` on the key sometimes
  // picked the button's copy over the menu's, and tapping an offstage widget
  // warns instead of failing, which left the test asserting against a filter
  // nobody had changed. `hitTestable()` does not help: the menu item is not
  // its own hit target. The `Text` inside it is what the menu's `InkWell`
  // wraps, and `.last` on that is the menu's copy rather than the button's.
  await tester.tap(
    find
        .descendant(
          of: find.byKey(ValueKey(option)),
          matching: find.byType(Text),
        )
        .last,
  );
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
      await _pump(
        tester,
        _controller(TenantRole.manager),
        _Callable(<Object?>[_response()]),
      );

      expect(find.text('Sales totals'), findsNothing);
    });

    testWidgets('the card carries no folds at all', (tester) async {
      // **All three went on 2026-09-21**, on the product owner's call: the
      // basis fold above the figures and the two tender explanations. What
      // each guarded is now either a badge on the figure it qualifies or the
      // row's own label, so this asserts the absence rather than measuring a
      // summary that no longer exists.
      await _pump(
        tester,
        _controller(TenantRole.owner),
        _Callable(<Object?>[_response(byTender: _byTender())]),
        width: 411,
      );

      expect(find.byType(Disclosure), findsNothing);
    });

    testWidgets('the unpublished-currency notice is a §2.1 status', (
      tester,
    ) async {
      await _pump(
        tester,
        _controller(TenantRole.manager),
        _Callable(<Object?>[_response()]),
      );

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

      // **The painted box, not the `Text`'s own.** The figure is inside a
      // `FittedBox` that scales it down rather than letting it ellipsise - a
      // truncated amount is a wrong amount - so the `Text` keeps its unscaled
      // width and the box around it is what lands on the screen.
      final figure = tester.renderObject<RenderBox>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('sales-totals-amount')),
              matching: find.byType(FittedBox),
            )
            .first,
      );
      // **Measured against the card, not a tile.** The headline stopped being
      // a `StatTile` when this screen became a card per question; the property
      // the assertion protects is unchanged, so it is the container that
      // changed rather than the rule.
      final card = tester.renderObject<RenderBox>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('sales-totals-amount')),
              matching: find.byType(AppCard),
            )
            .first,
      );
      expect(figure.size.width, lessThanOrEqualTo(card.size.width));
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
    await _stepPeriod(
      tester,
      TenantSalesPeriod.today,
      TenantSalesPeriod.last30Days,
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
    expect(find.textContaining('61200'), findsOne);
  });

  testWidgets('only mine filters by the signed-in member', (tester) async {
    final callable = _Callable(<Object?>[_response(), _response()]);

    await _pump(tester, _controller(TenantRole.manager), callable);
    await _choose(tester, 'sales-totals-member', 'sales-totals-member-self');
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

  testWidgets('one day compares its cashiers, a longer period does not', (
    tester,
  ) async {
    // **The card is absent rather than wrong for a longer period.** A shift
    // belongs to one business date and its summary is a per-shift total, so
    // summing them over a stretch would put one cashier in several columns.
    await _pump(
      tester,
      _controller(TenantRole.owner),
      _Callable(<Object?>[_response(), _response()]),
      reader: _Reader(
        currency: 'KES',
        staff: <String, Map<String, String?>>{
          'tenant-a': <String, String?>{'cashier-a': 'Amina Njoki'},
        },
        shifts: <Map<String, Object?>>[
          _shiftDocument(
            id: 'shift-100',
            staffId: 'owner-a',
            salesMinor: 90000,
          ),
          _shiftDocument(
            id: 'shift-200',
            staffId: 'cashier-a',
            salesMinor: 210000,
            hour: 14,
          ),
        ],
      ),
    );

    expect(find.byKey(const ValueKey('sales-totals-shifts')), findsOne);
    // The given name under each bar, and the figure above it.
    expect(find.text('Amina'), findsOne);
    expect(find.text('2.1k'), findsOne);

    // Choosing a longer period takes the comparison away with it.
    await _stepPeriod(
      tester,
      TenantSalesPeriod.today,
      TenantSalesPeriod.last30Days,
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('sales-totals-shifts')), findsNothing);
  });

  testWidgets('a running shift is drawn without inventing its takings', (
    tester,
  ) async {
    // Its totals are written by the close, so there is no figure to give the
    // column a height.
    await _pump(
      tester,
      _controller(TenantRole.owner),
      _Callable(<Object?>[_response(), _response()]),
      reader: _Reader(
        currency: 'KES',
        shifts: <Map<String, Object?>>[
          _shiftDocument(
            id: 'shift-100',
            staffId: 'owner-a',
            salesMinor: 90000,
          ),
          _shiftDocument(id: 'shift-200', staffId: 'owner-a', hour: 18),
        ],
      ),
    );

    expect(find.text('Open'), findsOne);
    expect(
      _calloutOrText(tester, 'sales-totals-shifts-open'),
      contains('still running'),
    );
  });

  testWidgets('a shift read that fails costs the page nothing', (tester) async {
    // The figure a manager came for is the takings; a comparison that could
    // not be read is one card absent, never a lost page.
    await _pump(
      tester,
      _controller(TenantRole.owner),
      _Callable(<Object?>[_response(), _response()]),
      reader: _Reader(currency: 'KES'),
    );

    expect(find.byKey(const ValueKey('sales-totals-shifts')), findsNothing);
    expect(_figure(tester, 'sales-totals-amount'), 'KES 4820.75');
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
    await _choose(
      tester,
      'sales-totals-member',
      'sales-totals-member-cashier-b',
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
    final members = _optionLabels(tester, 'sales-totals-member');
    expect(
      members[const ValueKey('sales-totals-member-self')],
      'You (The Manager)',
    );
    // The signed-in member is offered once, as itself. It must not also
    // appear among the colleagues under its own UID - which is a claim about
    // the option list and is asserted against the list, because an
    // unselected option is absent from a closed dropdown's tree either way.
    expect(
      members.keys,
      isNot(contains(const ValueKey('sales-totals-member-user-a'))),
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
      _optionLabels(tester, 'sales-totals-member')[const ValueKey(
        'sales-totals-member-cashier-b',
      )],
      'cashier-b',
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
    await _choose(tester, 'sales-totals-member', 'sales-totals-member-self');
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(callable.payloads.last['soldById'], 'user-a');
  });

  testWidgets('a member this business does not have is never sent', (
    tester,
  ) async {
    final callable = _Callable(<Object?>[
      _response(),
      _response(),
      _response(),
    ]);
    final reader = _Reader(
      staff: const <String, Map<String, String?>>{
        'tenant-a': <String, String?>{'cashier-b': 'Otieno'},
        // Tenant B has its own roster, and this colleague is not on it.
        'tenant-b': <String, String?>{'cashier-c': 'Wanjiru'},
      },
    );
    final controller = _controller(TenantRole.manager);

    await _pump(tester, controller, callable, reader: reader);
    await _choose(
      tester,
      'sales-totals-member',
      'sales-totals-member-cashier-b',
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
    await _stepPeriod(
      tester,
      TenantSalesPeriod.today,
      TenantSalesPeriod.last7Days,
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
    // **The categories and the roster are read once each and cached**, which
    // is what this case is actually about. Asserting on the paths rather than
    // on a count keeps it about that: the expense range is read again on the
    // second period because it genuinely depends on the period, and a bare
    // count would have hidden a cached read leaking out as easily as it hid
    // this one.
    //
    // **The shift read is the third and is not cached, deliberately.** The
    // per-cashier comparison is one day's shifts, so it belongs to the period
    // rather than to the session - and unlike the categories and the roster it
    // has to be asked again when the day changes. It is listed here rather
    // than filtered out so that a *second* shift read on one period would
    // still fail this case.
    expect(
      reader.queries
          .map((query) => query.collectionPath)
          .where((path) => !path.endsWith('/expenses'))
          .toList(),
      <String>[
        'tenants/tenant-a/categories',
        'tenants/tenant-a/staff',
        'tenants/tenant-a/shifts',
      ],
    );
    // **Asserted against the takings tile rather than counted across the
    // page.** The point here is that the currency was read and applied, and
    // counting occurrences made that hostage to how many other figures happen
    // to share the number - the profit is drawn now, and it is the same 4820.75
    // because nothing was subtracted from it.
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sales-totals-amount')))
          .data,
      contains('KES 4820.75'),
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
      _notice(tester, 'sales-totals-failure'),
      contains('Choose a shorter period'),
    );
    // The whole point of that sentence is that a shorter period can be picked,
    // so the chooser must survive the refusal.
    await _stepPeriod(
      tester,
      TenantSalesPeriod.last90Days,
      TenantSalesPeriod.today,
    );
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
      tester.widget<Text>(find.byKey(const ValueKey('sales-totals-cost'))).data,
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
      tester.widget<Text>(find.byKey(const ValueKey('sales-totals-cost'))).data,
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

  testWidgets('an owner is told which way an incomplete period is wrong', (
    tester,
  ) async {
    // The default response is the shape every period before products carried
    // costs produces: profit equals takings because nothing was subtracted.
    final callable = _Callable(<Object?>[_response()]);

    await _pump(tester, _controller(TenantRole.owner), callable);

    // Drawn as a bound rather than withheld, with the note saying which way it
    // is wrong. The margin, which carries no such warning, stays absent.
    expect(find.byKey(const ValueKey('sales-totals-profit')), findsOneWidget);
    expect(find.byKey(const ValueKey('sales-totals-margin')), findsNothing);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sales-totals-profit-note')))
          .data,
      'Profit is at most this figure: 96 sale lines have no cost recorded, '
      'and counting them as free overstates it. The margin is not shown.',
    );
    // The takings are unaffected either way: this was always about the profit,
    // not the total the manager and the owner both came for.
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
    await _choose(
      tester,
      'sales-totals-category',
      'sales-totals-category-drinks',
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // The server sums the matching lines and counts only their costs, so the
    // figure is that category's margin and the basis sentence beside it says
    // what the takings themselves are.
    expect(_figure(tester, 'sales-totals-profit'), 'KES 100');
    expect(_figure(tester, 'sales-totals-margin'), '25.0%');
    expect(find.byKey(const ValueKey('sales-totals-category-basis')), findsOne);
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
    expect(rowFor('card'), 'KES 900');
    expect(rowFor('unrecorded'), 'KES 100');
    expect(rowFor('other'), 'KES 20');
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
      'Recorded by the cashier at the register; the payment itself is not '
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
    expect(
      find.byKey(const ValueKey('sales-totals-tender-card')),
      findsNothing,
    );
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
      find.byKey(const ValueKey('sales-totals-tender-unrecorded-disclosure')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('sales-totals-tender-other-disclosure')),
      findsNothing,
    );
  });

  testWidgets('a sale with no method is never called unpaid', (tester) async {
    final callable = _Callable(<Object?>[
      _response(
        // Every sale in the period names no method - some old, some simply
        // never answered at the counter.
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

    // **The fold is gone, and the fact it guarded is not.** The product owner
    // removed the two explanatory tips from this card on 2026-09-21; what had
    // to survive is that a sale naming no method is never called unpaid, which
    // is the row's own label and the reason it is listed at all.
    expect(_figure(tester, 'sales-totals-tender-unrecorded'), '4800.75');
    expect(find.text('Not recorded'), findsOne);
    expect(find.textContaining('unpaid'), findsNothing);
    // Nothing modelled was recorded, so the verification disclaimer would be
    // about nothing that is on screen.
    expect(
      find.byKey(const ValueKey('sales-totals-tender-disclaimer')),
      findsNothing,
    );
  });

  testWidgets('an unrecognised method is reported, not hidden', (tester) async {
    final callable = _Callable(<Object?>[_response(byTender: _byTender())]);

    await _pump(tester, _controller(TenantRole.owner), callable);

    // Its own row, its own figure, and its takings still inside the total -
    // which is the whole of what the removed fold explained.
    expect(find.text('Unrecognised'), findsOne);
    expect(_figure(tester, 'sales-totals-tender-other'), '20');
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
      _response(
        overrides: <String, Object?>{'sales': 812.0, 'transactions': 12},
      ),
    ]);

    await _pump(
      tester,
      _controller(TenantRole.manager),
      callable,
      reader: _Reader(
        categories: <String, List<String>>{
          'tenant-a': <String>['drinks', 'bread'],
        },
      ),
    );
    await _choose(
      tester,
      'sales-totals-category',
      'sales-totals-category-drinks',
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

  testWidgets('a single sale read is described in the singular', (
    tester,
  ) async {
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
      reader: _Reader(
        categories: <String, List<String>>{
          'tenant-a': <String>['drinks'],
        },
      ),
    );
    await _choose(
      tester,
      'sales-totals-category',
      'sales-totals-category-drinks',
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
      reader: _Reader(
        categories: <String, List<String>>{
          'tenant-a': <String>['drinks'],
        },
      ),
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
      reader: _Reader(
        categories: <String, List<String>>{
          'tenant-a': <String>['drinks'],
        },
      ),
    );
    await _choose(
      tester,
      'sales-totals-category',
      'sales-totals-category-drinks',
    );
    await tester.pump();
    await tester.pump();
    await _stepPeriod(
      tester,
      TenantSalesPeriod.today,
      TenantSalesPeriod.last7Days,
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

  testWidgets('a category list cut short says so', (tester) async {
    // One bounded page is read. Before this, a business past that bound had
    // valid categories simply absent from the chooser with nothing on the page
    // to say so - a filter that looks complete and is not. The staff chooser
    // has said this since it was written; the categories never did.
    final callable = _Callable(<Object?>[_response()]);
    final reader = _Reader(
      categories: <String, List<String>>{
        'tenant-a': <String>[
          for (var index = 0; index < 51; index++)
            'cat-${index.toString().padLeft(3, '0')}',
        ],
      },
    );

    await _pump(
      tester,
      _controller(TenantRole.manager),
      callable,
      reader: reader,
    );

    expect(find.byKey(const ValueKey('sales-totals-category')), findsOne);
    expect(
      find.byKey(const ValueKey('sales-totals-categories-truncated')),
      findsOne,
    );
  });

  testWidgets('a category list that fits says nothing about being cut', (
    tester,
  ) async {
    final callable = _Callable(<Object?>[_response()]);
    final reader = _Reader(
      categories: <String, List<String>>{
        'tenant-a': <String>['drinks', 'food'],
      },
    );

    await _pump(
      tester,
      _controller(TenantRole.manager),
      callable,
      reader: reader,
    );

    expect(find.byKey(const ValueKey('sales-totals-category')), findsOne);
    expect(
      find.byKey(const ValueKey('sales-totals-categories-truncated')),
      findsNothing,
      reason: 'A complete list that announces itself as partial is a new lie.',
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
    await _choose(
      tester,
      'sales-totals-category',
      'sales-totals-category-drinks',
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

  testWidgets('device totals render before a held server and are replaced', (
    tester,
  ) async {
    final callable = _Callable(<Object?>[_response()], deferred: true);
    await _pump(
      tester,
      _controller(TenantRole.owner),
      callable,
      reader: _DeviceReader(),
      settle: false,
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(_figure(tester, 'sales-totals-amount'), 'KES 9');
    // **No badge while the server is still being asked.** The device read
    // nearly always lands first, so a badge here went up on every open and
    // came down a moment later.
    expect(
      find.byKey(const ValueKey('sales-totals-device-basis')),
      findsNothing,
    );
    expect(callable.pending, hasLength(1));

    callable.completeFirst();
    await tester.pump();
    await tester.pump();
    expect(_figure(tester, 'sales-totals-amount'), 'KES 4820.75');
    // The server answered, so it is no longer this device's figure.
    expect(
      find.byKey(const ValueKey('sales-totals-device-basis')),
      findsNothing,
    );
  });

  testWidgets('a device copy with no sales waits for the server', (
    tester,
  ) async {
    final callable = _Callable(<Object?>[_response()], deferred: true);
    await _pump(
      tester,
      _controller(TenantRole.owner),
      callable,
      reader: _EmptyDeviceReader(),
      settle: false,
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // A device that has never read these sales holds none of them, which is
    // not a day that took nothing.
    expect(find.byKey(const ValueKey('sales-totals-amount')), findsNothing);

    callable.completeFirst();
    await tester.pump();
    await tester.pump();
    expect(_figure(tester, 'sales-totals-amount'), 'KES 4820.75');
  });

  testWidgets('device totals carry their badge once the server has failed', (
    tester,
  ) async {
    final callable = _Callable(<Object?>[
      FirebaseFunctionsException(code: 'unavailable', message: 'no'),
    ]);
    await _pump(
      tester,
      _controller(TenantRole.owner),
      callable,
      reader: _DeviceReader(),
    );

    expect(_figure(tester, 'sales-totals-amount'), 'KES 9');
    // **The badge carries what the removed fold carried.** Whose count this is
    // is not a footnote on a device answer - it is the difference between the
    // whole business and this till - so it sits on the figure.
    expect(find.byKey(const ValueKey('sales-totals-device-basis')), findsOne);
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
  // **Tall enough to build the whole page, since it became a card per
  // question.** The default 800x600 test surface stopped short of the profit
  // note and the cards under it, and a `ListView` does not build what it
  // cannot show - so `find.byKey` reported them missing when they were only
  // unbuilt. A case that is specifically about a narrow screen still says so
  // with `width`.
  tester.view.physicalSize = Size(width ?? 800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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
class _Reader implements TenantDataReader {
  _Reader({
    Map<String, List<String>> categories = const <String, List<String>>{},
    Map<String, Map<String, String?>> staff =
        const <String, Map<String, String?>>{},
    this.currency,
    List<Map<String, Object?>> shifts = const <Map<String, Object?>>[],
    this.throws = false,
    this.staffUnreadable = false,
    this.answersOutsideTenant = false,
  }) : categories = Map<String, List<String>>.of(categories),
       staff = Map<String, Map<String, String?>>.of(staff),
       shifts = List<Map<String, Object?>>.of(shifts);

  /// The code published in `configuration/checkout`, or none at all.
  final String? currency;

  /// Category IDs by tenant, named `<id> shelf` so a label is provable.
  final Map<String, List<String>> categories;

  /// Staff UIDs to display names, by business. A `null` name is a member whose
  /// canonical record records none. Every business always has its owner,
  /// because the directory reads that record before anything else.
  final Map<String, Map<String, String?>> staff;

  /// The shift documents one day holds, for the per-cashier comparison.
  final List<Map<String, Object?>> shifts;

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
    if (query.collectionPath.endsWith('/shifts')) {
      return Future<List<TenantQueryDocumentSnapshot>>.value(
        <TenantQueryDocumentSnapshot>[
          for (final shift in shifts)
            TenantQueryDocumentSnapshot(
              path: '${query.collectionPath}/${shift['shiftId']}',
              data: shift,
            ),
        ],
      );
    }
    // Firestore pages a collection in ascending document-ID order and the
    // repository proves it, so the fake has to answer in that order too.
    if (isStaff) {
      final uids = _roster(tenantId).keys.toList()..sort();
      return Future<List<TenantQueryDocumentSnapshot>>.value(
        <TenantQueryDocumentSnapshot>[
          for (final uid in uids.take(query.limit))
            TenantQueryDocumentSnapshot(
              path: '${query.collectionPath}/$uid',
              data: _staffData(tenantId, uid),
            ),
        ],
      );
    }
    final ids = <String>[...?categories[tenantId]]..sort();
    final collectionPath = answersOutsideTenant
        ? 'tenants/tenant-z/categories'
        : query.collectionPath;
    return Future<List<TenantQueryDocumentSnapshot>>.value(
      <TenantQueryDocumentSnapshot>[
        for (final id in ids.take(query.limit))
          TenantQueryDocumentSnapshot(
            path: '$collectionPath/$id',
            data: <String, Object?>{'name': '$id shelf'},
          ),
      ],
    );
  }
}

final class _DeviceReader extends _Reader
    implements TenantCacheReadable, TenantSalesHistoryQueryReader {
  _DeviceReader() : super(currency: 'KES');

  @override
  TenantDataReader get cacheOnly => this;

  @override
  Future<List<TenantQueryDocumentSnapshot>> queryTenantSalesHistory(
    TenantSalesHistoryQuery query,
  ) async => <TenantQueryDocumentSnapshot>[
    TenantQueryDocumentSnapshot(
      path: 'tenants/tenant-a/sales/checkout-device-a',
      data: <String, Object?>{
        'checkoutId': 'checkout-device-a',
        'tenantId': 'tenant-a',
        'soldById': 'owner-a',
        'payloadHash': 'a'.padRight(64, 'a'),
        'payloadSchemaVersion': 2,
        'tender': 'cash',
        'currency': 'KES',
        'businessDate': '2026-07-31',
        'shiftId': 'shift-a',
        'deviceId': _deviceId,
        'receiptNumber': formatCheckoutReceiptNumber(
          deviceId: _deviceId,
          businessDate: '2026-07-31',
          sequence: 1,
        ),
        'receiptSequence': 1,
        'items': <Object?>[
          <String, Object?>{
            'productId': 'product-a',
            'name': 'Item',
            'quantity': 1,
            'unitPriceMinor': 1000,
            'lineTotalMinor': 1000,
            'unitCostMinor': 400,
            'costMinor': 400,
          },
        ],
        'subtotalMinor': 1000,
        'subtotal': 10.0,
        'discountMinor': 100,
        'discount': 1.0,
        'totalMinor': 900,
        'total': 9.0,
        'createdAt': DateTime.utc(2026, 7, 31, 8),
      },
    ),
  ];
}

/// A device copy that holds no sales at all.
final class _EmptyDeviceReader extends _Reader
    implements TenantCacheReadable, TenantSalesHistoryQueryReader {
  _EmptyDeviceReader() : super(currency: 'KES');

  @override
  TenantDataReader get cacheOnly => this;

  @override
  Future<List<TenantQueryDocumentSnapshot>> queryTenantSalesHistory(
    TenantSalesHistoryQuery query,
  ) async => const <TenantQueryDocumentSnapshot>[];
}

const String _deviceId = 'dev-0123456789abcdef0123456789abcdef';

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
    // **The canonical answer carries `net`.** `SalesComparison.net` is not
    // optional in `reports.ts`, so every answer has one; a period nothing
    // came back from nets to its own gross figures.
    'net': Map<String, Object?>.of(previous),
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

  Object? _next() =>
      _outcomes[_index < _outcomes.length ? _index++ : _outcomes.length - 1];

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
/// The options one of the member/category dropdowns is offering, by key.
///
/// **Read off the widget rather than off the rendering, which is the reverse
/// of what this file used to do and for the same underlying reason.** While
/// the filters were a `FilterChipBar` the chip was private, so the only way
/// to see a label was to find its `Text`. As dropdowns the model is public -
/// `AppSelect.items` is a list of `AppSelectItem` - and the rendering is the
/// part that is now unavailable: a closed `DropdownButton` builds only the
/// selected option, so an unselected one has no `Text` in the tree at all.
/// Reading the model also means these assertions no longer depend on whether
/// a menu happens to be open.
Map<Key?, String> _optionLabels(WidgetTester tester, String select) {
  final control = tester.widget<AppSelect<String?>>(
    find.byKey(ValueKey(select)),
  );
  return <Key?, String>{for (final item in control.items) item.key: item.label};
}

/// One shift document as the close writes it, or as an open shift stands.
Map<String, Object?> _shiftDocument({
  required String id,
  required String staffId,
  int? salesMinor,
  int hour = 9,
}) => <String, Object?>{
  'shiftId': id,
  'tenantId': 'tenant-a',
  'staffId': staffId,
  'deviceId': 'dev-0123456789abcdef01234567deadbeef',
  // **The pinned clock's business date, not the real one.** The query answers
  // with the day it read, and `loadDayShifts` refuses a document belonging to
  // another day - so a fixture dated "now" is rejected by the guard rather
  // than drawn.
  'businessDate': checkoutBusinessDate(DateTime.utc(2026, 7, 31, 9)),
  'status': salesMinor == null ? 'open' : 'closed',
  'startTime': Timestamp.fromDate(DateTime.utc(2026, 7, 31, hour)),
  if (salesMinor != null) ...<String, Object?>{
    'closingCashMinor': salesMinor,
    'totalSalesMinor': salesMinor,
    'totalSales': salesMinor / 100,
    'transactionCount': 4,
  },
};

/// The sentence a keyed plain `Text` carries.
String _calloutOrText(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

/// Walks the period stepper, which replaced the period menu, until [to] is
/// showing.
///
/// Named by the period rather than by a number of taps, so a case says which
/// reading it wants and not how many chevrons that happens to be.
Future<void> _stepPeriod(
  WidgetTester tester,
  TenantSalesPeriod from,
  TenantSalesPeriod to,
) async {
  final steps =
      TenantSalesPeriod.values.indexOf(to) -
      TenantSalesPeriod.values.indexOf(from);
  final label = steps > 0 ? 'Earlier period' : 'Shorter period';
  for (var step = 0; step < steps.abs(); step++) {
    await tester.tap(find.bySemanticsLabel(label));
    await tester.pumpAndSettle();
  }
}
