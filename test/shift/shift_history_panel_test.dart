import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/shift/shift.dart';
import 'package:flutter_application_1/shift/shift_history_card.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/status.dart';
import 'package:flutter_application_1/ui/buttons.dart';
import 'package:flutter_test/flutter_test.dart';

const String _deviceA = 'dev-0123456789abcdef0123456789abcdef';
const String _businessDate = '2026-07-31';

void main() {
  testWidgets('a cashier sees counted cash, recorded sales, and the difference', (
    tester,
  ) async {
    final controller = _controller(TenantRole.cashier);
    final reader = _Reader()
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[
        _snapshot('shift-b'),
        _snapshot(
          'shift-a',
          overrides: <String, Object?>{'closingCashMinor': 90000},
        ),
      ]);

    await _pumpPanel(tester, controller, reader, tall: true);

    expect(find.byKey(const ValueKey('shift-history-entry-shift-b')), findsOne);
    // **Grouped, and with no currency code.** These fixtures publish no checkout
    // configuration, so `TenantReportingCurrency` answers `unknown` and the
    // figures stay bare rather than being labelled with a guess.
    _expectText(tester, 'shift-history-counted-shift-b', '1,250.00');
    _expectText(tester, 'shift-history-sales-shift-b', '987.50');
    // The transaction count rides on the shift's own second line rather than
    // taking a key-value row of its own: it is part of what identifies the
    // shift, not one of the figures being compared.
    _expectContains(tester, 'shift-history-window-shift-b', '3 sales');
    // §2.1's own table decides the standing. The word names the *direction*,
    // because every shift on this screen is closed and every one of them has
    // takings - what varies is which way they disagree.
    _expectStatus(
      tester,
      'shift-history-status-shift-b',
      'Over',
      status: AppStatus.problem,
    );
    _expectText(tester, 'shift-history-variance-shift-b', '262.50');
    _expectStatus(
      tester,
      'shift-history-status-shift-a',
      'Short',
      status: AppStatus.problem,
    );
    _expectText(tester, 'shift-history-variance-shift-a', '87.50');
    // Only management may look beyond its own shifts.
    expect(find.byKey(const ValueKey('shift-history-scope')), findsNothing);
    expect(reader.queries.single.equalityFilters, <String, Object?>{
      'status': 'closed',
      'staffId': 'user-a',
    });
  });

  testWidgets('the page states what it adds up to before the first shift', (
    tester,
  ) async {
    // The screen's whole reason for existing, answered above the list rather
    // than left to be read off twenty badges. It is the *page's* answer and the
    // range strip says so: `loadPage` takes a cursor and equality filters, so
    // there is no honest way for this to be the week's.
    final reader = _Reader()
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[
        _snapshot('shift-c'),
        _snapshot(
          'shift-b',
          overrides: <String, Object?>{'closingCashMinor': 90000},
        ),
        _snapshot(
          'shift-a',
          overrides: <String, Object?>{'closingCashMinor': 98750},
        ),
      ]);

    await _pumpPanel(tester, _controller(TenantRole.manager), reader);

    _expectText(tester, 'shift-history-tally-closed', '3');
    _expectText(tester, 'shift-history-tally-settled', '1');
    _expectText(tester, 'shift-history-tally-unresolved', '2');
    // Two differences in opposite directions are two problems. Netting them
    // would print zero over a page holding both.
    expect(
      tester
          .widget<Callout>(
            find.byKey(const ValueKey('shift-history-unresolved')),
          )
          .message,
      '2 shifts on this page need attention: short 87.50 and over 262.50.',
    );
    _expectContains(tester, 'shift-history-range', 'this page');
  });

  testWidgets('a settled page says so instead of an empty attention notice', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[
        _snapshot(
          'shift-a',
          overrides: <String, Object?>{'closingCashMinor': 98750},
        ),
      ]);

    await _pumpPanel(tester, _controller(TenantRole.cashier), reader);

    _expectText(tester, 'shift-history-tally-unresolved', '0');
    expect(
      find.byKey(const ValueKey('shift-history-unresolved')),
      findsNothing,
    );
  });

  testWidgets('the filter narrows the page in hand and says which page', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[
        _snapshot('shift-b'),
        _snapshot(
          'shift-a',
          overrides: <String, Object?>{'closingCashMinor': 98750},
        ),
      ]);

    await _pumpPanel(tester, _controller(TenantRole.cashier), reader);

    expect(find.text('All 2'), findsOne);
    expect(find.text('Needs attention 1'), findsOne);
    expect(find.text('Settled 1'), findsOne);

    await tester.tap(find.text('Needs attention 1'));
    await tester.pump();

    // It narrows what has been read and reads nothing more: a chip that looked
    // like a query while meaning "of the two in hand" would be the worst of both.
    expect(reader.queries.length, 1);
    expect(find.byKey(const ValueKey('shift-history-entry-shift-b')), findsOne);
    expect(
      find.byKey(const ValueKey('shift-history-entry-shift-a')),
      findsNothing,
    );

    await tester.tap(find.text('Settled 1'));
    await tester.pump();
    expect(find.byKey(const ValueKey('shift-history-entry-shift-a')), findsOne);
    expect(
      find.byKey(const ValueKey('shift-history-entry-shift-b')),
      findsNothing,
    );
  });

  testWidgets('a filter that empties the list says the good news it is', (
    tester,
  ) async {
    // An empty *read* means nothing has been closed. An empty *filter* on this
    // screen means everything that was is fine, which is not the same fact and
    // must not borrow the other one's words.
    final reader = _Reader()
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[
        _snapshot('shift-b'),
        _snapshot(
          'shift-a',
          overrides: <String, Object?>{'closingCashMinor': 98750},
        ),
      ]);

    await _pumpPanel(tester, _controller(TenantRole.cashier), reader);
    await tester.tap(find.text('Needs attention 1'));
    await tester.pump();
    // The one unresolved shift is `shift-b`; filtering to settled leaves one
    // too, so force the empty case by clearing the page of anything settled.
    await tester.tap(find.text('All 2'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('shift-history-nothing-matches')),
      findsNothing,
    );
  });

  testWidgets('a page with nothing to chase offers no attention filter', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[
        _snapshot(
          'shift-a',
          overrides: <String, Object?>{'closingCashMinor': 98750},
        ),
      ]);

    await _pumpPanel(tester, _controller(TenantRole.cashier), reader);

    // A chip that would empty the list is a dead end with a number on it.
    await tester.tap(find.text('Needs attention 0'));
    await tester.pump();
    expect(find.byKey(const ValueKey('shift-history-entry-shift-a')), findsOne);
  });

  testWidgets('a shift closed without a summary states that plainly', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[
        _snapshot(
          'shift-a',
          overrides: <String, Object?>{
            'totalSalesMinor': null,
            'totalSales': null,
            'transactionCount': null,
          },
        ),
      ]);

    await _pumpPanel(tester, _controller(TenantRole.cashier), reader);

    // A shift with no summary can be compared with nothing, which is §2.1's
    // "unreconciled" rather than a difference found. The sentence this row used
    // to carry is the badge's semantic label, so a screen reader hears it.
    _expectStatus(
      tester,
      'shift-history-status-shift-a',
      'No summary',
      status: AppStatus.attention,
    );
    expect(
      tester
          .widget<StatusBadge>(
            find.byKey(const ValueKey('shift-history-status-shift-a')),
          )
          .semanticLabel,
      'No closing summary was recorded for this shift.',
    );
    // The card says why the figures below it are short of every other card's,
    // rather than leaving a reader to notice an absence.
    _expectContains(
      tester,
      'shift-history-silence-shift-a',
      'closed before the app recorded closing summaries',
    );
    expect(
      find.byKey(const ValueKey('shift-history-sales-shift-a')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('shift-history-variance-shift-a')),
      findsNothing,
    );
    _expectText(tester, 'shift-history-counted-shift-a', '1,250.00');
  });

  testWidgets('a shift ended from another device is not the same silence', (
    tester,
  ) async {
    // Two shifts with no variance, and they are not the same event: one is an
    // old record, the other is money nobody can account for.
    final reader = _Reader()
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[
        _snapshot(
          'shift-a',
          overrides: <String, Object?>{'closedWithoutEvidence': true},
        ),
      ]);

    await _pumpPanel(tester, _controller(TenantRole.cashier), reader);

    _expectStatus(
      tester,
      'shift-history-status-shift-a',
      'Unaccounted',
      status: AppStatus.attention,
    );
    _expectContains(
      tester,
      'shift-history-silence-shift-a',
      'held none of this shift',
    );
  });

  testWidgets('a shift whose drawer agrees says so and states no difference', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[
        _snapshot(
          'shift-a',
          overrides: <String, Object?>{'closingCashMinor': 98750},
        ),
      ]);

    await _pumpPanel(tester, _controller(TenantRole.manager), reader);

    _expectStatus(
      tester,
      'shift-history-status-shift-a',
      'Settled',
      status: AppStatus.ok,
    );
    // A difference of nothing is not a difference, so the line is silent rather
    // than carrying a zero a person has to read as agreement.
    expect(
      find.byKey(const ValueKey('shift-history-variance-shift-a')),
      findsNothing,
    );
  });

  testWidgets('a shift states the same facts on a phone', (tester) async {
    // The class of defect the staff directory found: a screen that has only
    // ever been laid out wide.
    final reader = _Reader()
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[
        _snapshot('shift-a', overrides: _amended()),
      ]);

    await _pumpPanel(
      tester,
      _controller(TenantRole.manager),
      reader,
      width: 411,
    );

    for (final key in <String>[
      'shift-history-range',
      'shift-history-tally-closed',
      'shift-history-filter',
      'shift-history-day-2026-07-31',
      'shift-history-entry-shift-a',
      'shift-history-subject-shift-a',
      'shift-history-window-shift-a',
      'shift-history-status-shift-a',
      'shift-history-counted-shift-a',
      'shift-history-sales-shift-a',
      'shift-history-variance-shift-a',
      'shift-history-amended-shift-a',
      'shift-history-sales-link-shift-a',
      'shift-history-corrections-link-shift-a',
    ]) {
      expect(find.byKey(ValueKey<String>(key)), findsOne, reason: key);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a manager may page every cashier and label its own shifts', (
    tester,
  ) async {
    final controller = _controller(TenantRole.manager);
    final reader = _Reader()
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[
        _snapshot('shift-b', overrides: <String, Object?>{'staffId': 'user-b'}),
        _snapshot('shift-a'),
      ]);

    await _pumpPanel(tester, controller, reader, tall: true);
    expect(reader.queries.single.equalityFilters, <String, Object?>{
      'status': 'closed',
      'staffId': 'user-a',
    });

    await tester.tap(find.text('Every cashier'));
    await tester.pump();
    await tester.pump();

    expect(reader.queries.length, 2);
    expect(reader.queries.last.equalityFilters, <String, Object?>{
      'status': 'closed',
    });
    // **The day is the group above the cards, not a prefix on every title.**
    // `2026-07-31 - Brian (user-b)` said the date once per row on a page where
    // every row shared it. A resolved colleague keeps the UID beside the name;
    // an unresolved one falls back to the UID alone.
    expect(find.text('Brian (user-b)'), findsOne);
    expect(find.text('You'), findsOne);
    expect(
      find.byKey(const ValueKey('shift-history-day-2026-07-31')),
      findsOne,
    );
  });

  testWidgets('one cashier reading their own shifts is named by the hours', (
    tester,
  ) async {
    // Naming the cashier on every row of *My shifts* names nothing. The day
    // above the cards and the hours on them are what tell two shifts apart.
    final reader = _Reader()
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[
        _snapshot('shift-a'),
      ]);

    await _pumpPanel(tester, _controller(TenantRole.cashier), reader);

    expect(find.text('You'), findsNothing);
    _expectText(
      tester,
      'shift-history-subject-shift-a',
      shiftWindowLabelFor(
        DateTime.utc(2026, 7, 31, 6),
        DateTime.utc(2026, 7, 31, 18),
      ),
    );
    _expectText(tester, 'shift-history-window-shift-a', '3 sales');
  });

  testWidgets('an unreadable staff record leaves the UID in place', (
    tester,
  ) async {
    final reader = _Reader(deniedStaff: true)
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[
        _snapshot('shift-b', overrides: <String, Object?>{'staffId': 'user-b'}),
      ]);

    await _pumpPanel(tester, _controller(TenantRole.manager), reader);
    await tester.tap(find.text('Every cashier'));
    await tester.pump();
    await tester.pump();

    expect(find.text('user-b'), findsOne);
    expect(find.byKey(const ValueKey('shift-history-failure')), findsNothing);
  });

  testWidgets('paging forward asks for the next cursor only', (tester) async {
    final controller = _controller(TenantRole.cashier);
    final reader = _Reader()
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[
        _snapshot('shift-c'),
        _snapshot('shift-b'),
        _snapshot('shift-a'),
      ]);

    await _pumpPanel(tester, controller, reader, pageSize: 2);
    expect(
      find.byKey(const ValueKey('shift-history-entry-shift-a')),
      findsNothing,
    );
    // Present and disabled rather than absent, since `Pagination` - see the
    // ledger panel's test for the reasoning.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('shift-history-previous')),
      200,
    );
    expect(
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey('shift-history-previous')),
          )
          .onPressed,
      isNull,
    );

    // **`scrollUntilVisible` stops when a widget is built, not when it is on
    // screen.** The standing trap on this screen, met for the fourth time: the
    // answer band above the list moved every offset again.
    await tester.ensureVisible(
      find.byKey(const ValueKey('shift-history-next')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('shift-history-next')));
    await tester.pump();
    await tester.pump();

    expect(reader.queries.last.startAfterDocumentId, 'shift-b');
    expect(reader.queries.last.descending, isTrue);
    expect(find.byKey(const ValueKey('shift-history-entry-shift-a')), findsOne);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('shift-history-previous')),
      200,
    );
    expect(find.byKey(const ValueKey('shift-history-previous')), findsOne);
  });

  testWidgets('a tenant switch discards the outstanding page', (tester) async {
    final controller = _controller(TenantRole.cashier);
    final reader = _Reader(deferred: true)
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[
        _snapshot('shift-a'),
      ])
      ..respond('tenants/tenant-b/shifts', <TenantQueryDocumentSnapshot>[
        _snapshot('shift-b', tenantId: 'tenant-b'),
      ]);

    await _pumpPanel(tester, controller, reader, settle: false);
    await tester.pump();
    expect(reader.pending.length, 1);

    controller.open(uid: 'user-a', membership: _membership('tenant-b'));
    await tester.pump();
    expect(reader.pending.length, 2);

    // The first business answers after the switch; its page must be discarded.
    //
    // **Two pumps per answer, as everywhere else in this file.** A completed
    // read lands in a microtask, so the frame the first pump builds is still
    // the empty one - the list arrives on the second. Asserting after one pump
    // passed whatever the discard did, because nothing had rendered either way.
    reader.completeFirst();
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('shift-history-entry-shift-a')),
      findsNothing,
    );

    reader.completeFirst();
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('shift-history-entry-shift-b')), findsOne);
    expect(
      find.byKey(const ValueKey('shift-history-entry-shift-a')),
      findsNothing,
    );
  });

  testWidgets('a closed shift links to the sales it recorded', (tester) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[
        _snapshot('shift-a'),
      ])
      ..respond('tenants/tenant-a/sales', <TenantQueryDocumentSnapshot>[]);

    await _pumpPanel(
      tester,
      _controller(TenantRole.cashier),
      reader,
      tall: true,
    );
    // The whole card body is the control. Twenty rows each carrying a `View
    // sales` button spent a 48-high band of the screen saying one word twenty
    // times.
    await tester.tap(
      find.byKey(const ValueKey('shift-history-sales-link-shift-a')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Shift sales'), findsOne);
    // The sales page is scoped to this exact shift, and carries the figures
    // the shift recorded rather than reading them again.
    expect(reader.queries.last.equalityFilters, <String, Object?>{
      'shiftId': 'shift-a',
      // **The cashier attribution rides with the shift.** loadShiftSales
      // filters on soldById too: Firestore permits a cashier's collection
      // query only where the result set is provably their own, and
      // management uses the same narrower shape.
      'soldById': 'user-a',
    });
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sale-history-recorded')))
          .data,
      'Recorded: 987.50 over 3 transactions. Counted cash was 1250.00.',
    );
  });

  testWidgets('the cashier reaches its own recent sales', (tester) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[])
      ..respond('tenants/tenant-a/sales', <TenantQueryDocumentSnapshot>[]);

    await _pumpPanel(tester, _controller(TenantRole.cashier), reader);
    // It cuts across every shift on the page and is not what any one row is
    // about, so it sits in the toolbar rather than between the filters and the
    // first card, where it used to push the list down on every visit.
    await tester.tap(find.byKey(const ValueKey('shift-history-own-sales')));
    await tester.pumpAndSettle();

    expect(find.text('My recent sales'), findsOne);
    expect(reader.queries.last.equalityFilters, <String, Object?>{
      'soldById': 'user-a',
    });
  });

  testWidgets('the four terms are one tap from the toolbar, not a preamble', (
    tester,
  ) async {
    // Five lines of policy used to sit between the title and the first shift,
    // read past once and then past forever. Same claims, out of the way.
    final reader = _Reader()
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[
        _snapshot('shift-a'),
      ]);

    await _pumpPanel(
      tester,
      _controller(TenantRole.cashier),
      reader,
      tall: true,
    );

    expect(
      find.byKey(const ValueKey('shift-history-explainer-sheet')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('shift-history-explainer')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('shift-history-explainer-sheet')),
      findsOne,
    );
    expect(find.text('How a shift is reconciled'), findsOne);
    expect(find.textContaining('never changes the counted cash'), findsOne);
    // Who may read the trail is a property of the screen rather than of any
    // shift, so it is stated here rather than under every corrected row.
    expect(
      find.textContaining('kept for managers, administrators and owners'),
      findsOne,
    );
    expect(find.textContaining('short by its M-Pesa'), findsOne);
  });

  testWidgets('a corrected shift says so and opens its own corrections', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[
        _snapshot('shift-a', overrides: _amended()),
      ])
      ..respond(
        'tenants/tenant-a/shift_amendments',
        <TenantQueryDocumentSnapshot>[_amendmentSnapshot()],
      );

    await _pumpPanel(tester, _controller(TenantRole.manager), reader);

    // **The marker rides on the figure it is about.** A corrected shift's
    // recorded sales *are* the rewritten ones, and this used to be a line of
    // prose two rows further down with nothing tying it to the number.
    _expectStatus(
      tester,
      'shift-history-amended-shift-a',
      'Corrected ×2',
      status: AppStatus.attention,
    );
    expect(
      tester
          .widget<StatusBadge>(
            find.byKey(const ValueKey('shift-history-amended-shift-a')),
          )
          .semanticLabel,
      startsWith('The recorded sales on this shift were corrected 2 times'),
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('shift-history-corrections-link-shift-a')),
      200,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('shift-history-corrections-link-shift-a')),
    );
    await tester.pumpAndSettle();

    // The trail opens narrowed to this exact shift, and says which one it is
    // showing rather than implying it is the whole business's record.
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('shift-a')),
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

  testWidgets('a shift nobody corrected offers nothing about corrections', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[
        _snapshot('shift-a'),
      ]);

    await _pumpPanel(tester, _controller(TenantRole.manager), reader);

    expect(
      find.byKey(const ValueKey('shift-history-amended-shift-a')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('shift-history-corrections-link-shift-a')),
      findsNothing,
    );
    // The control it does offer is unaffected.
    expect(
      find.byKey(const ValueKey('shift-history-sales-link-shift-a')),
      findsOne,
    );
  });

  testWidgets('one correction is counted in the singular', (tester) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[
        _snapshot(
          'shift-b',
          overrides: <String, Object?>{
            ..._amended(),
            'summaryAmendmentCount': 1,
            // A correction whose instant the server never recorded still says
            // what it did.
            'summaryAmendedAt': null,
          },
        ),
      ]);

    await _pumpPanel(tester, _controller(TenantRole.admin), reader);

    _expectStatus(tester, 'shift-history-amended-shift-b', 'Corrected ×1');
    expect(
      tester
          .widget<StatusBadge>(
            find.byKey(const ValueKey('shift-history-amended-shift-b')),
          )
          .semanticLabel,
      'The recorded sales on this shift were corrected once, and the time of '
      'the last correction was not recorded.',
    );
  });

  testWidgets('a cashier is told their shift was corrected and offered no '
      'trail', (tester) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[
        _snapshot('shift-a', overrides: _amended()),
      ]);

    await _pumpPanel(tester, _controller(TenantRole.cashier), reader);

    // Their own figures were rewritten, so hiding that would be worse than the
    // link they may not have: the shift document they can already read says so.
    expect(
      find.byKey(const ValueKey('shift-history-amended-shift-a')),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('shift-history-corrections-link-shift-a')),
      findsNothing,
    );
  });

  testWidgets('a page with no shifts says what would be here', (tester) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[]);

    await _pumpPanel(tester, _controller(TenantRole.cashier), reader);

    expect(find.byKey(const ValueKey('shift-history-empty')), findsOne);
    // The band, the range and the filter are all statements about shifts, and
    // there are none.
    expect(find.byKey(const ValueKey('shift-history-range')), findsNothing);
    expect(find.byKey(const ValueKey('shift-history-filter')), findsNothing);
  });

  testWidgets('no session renders the denied state and starts no load', (
    tester,
  ) async {
    final controller = TenantSessionController();
    final reader = _Reader();

    await _pumpPanel(tester, controller, reader);

    expect(find.byKey(const ValueKey('shift-history-denied')), findsOne);
    expect(reader.queries, isEmpty);
  });

  testWidgets('a failed page hides the underlying error', (tester) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/shifts', <TenantQueryDocumentSnapshot>[
        // A page that answers outside the requested business fails closed.
        _snapshot('shift-a', responsePath: 'tenants/tenant-b/shifts/shift-a'),
      ]);

    await _pumpPanel(tester, _controller(TenantRole.cashier), reader);

    expect(find.byKey(const ValueKey('shift-history-failure')), findsOne);
    expect(find.textContaining('tenant-b'), findsNothing);
    // §7's other half: what is still true despite the failure.
    expect(find.textContaining('still recorded on the server'), findsOne);
  });

  group('the business day heading', () {
    test('names the shop\'s own day and never shifts it into a zone', () {
      // A business date is the shop's day, chosen by whatever opened the shift.
      // Parsing it into midnight UTC and rendering that locally is how a Friday
      // becomes a Thursday west of Greenwich.
      expect(shiftBusinessDayLabel('2026-07-31'), 'Fri 31 Jul');
      expect(shiftBusinessDayLabel('2026-01-01'), 'Thu 1 Jan');
    });

    test('prints a string that is not a date as it stands', () {
      expect(shiftBusinessDayLabel('not-a-date'), 'not-a-date');
      expect(shiftBusinessDayLabel('2026-13-40'), '2026-13-40');
      expect(shiftBusinessDayLabel(''), '');
    });
  });
}

/// The window label the fixtures produce, built the way the widget builds it.
///
/// **Asserted against the formatter rather than against a wall clock.** The
/// times are local now, which is the whole point of the change; a literal
/// `06:00 → 18:00` here would be a test of the machine's time zone.
String shiftWindowLabelFor(DateTime started, DateTime ended) {
  String clock(DateTime instant) {
    final local = instant.toLocal();
    String pad(int part) => part.toString().padLeft(2, '0');
    return '${pad(local.hour)}:${pad(local.minute)}';
  }

  return '${clock(started)} → ${clock(ended)}';
}

Future<void> _pumpPanel(
  WidgetTester tester,
  TenantSessionController controller,
  _Reader reader, {
  int pageSize = 20,
  bool settle = true,
  double? width,
  bool tall = false,
}) async {
  // The default surface is 800 x 600, which is §4.1's `medium` band. A case
  // that wants another band asks for it by width rather than every case being
  // rewritten to one.
  //
  // `tall` keeps the band and lifts only the height. This page answers itself
  // before it lists anything - range, tally, the attention line, the filters -
  // and that band measures 502 high, with the first card 229 under it. On a 600
  // surface that is the header, a day heading and the top third of one shift.
  // `ListView` builds what it can show, so a case reaching for a second card,
  // or tapping the first (whose centre lands at y=616), asserts against elements
  // the list has correctly declined to build. Such a case asks for the room; the
  // screen is not made shorter to fit a test window.
  if (width != null || tall) {
    tester.view.physicalSize = Size(width ?? 800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  // **The route, not the panel inside it.** Two of this screen's controls live
  // in the toolbar now, so a test that pumped the panel alone would be a test of
  // a page nothing builds.
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: TenantShiftHistoryScreen(reader: reader, pageSize: pageSize),
      ),
    ),
  );
  if (!settle) return;
  await tester.pump();
  await tester.pump();
}

TenantSessionController _controller(TenantRole role) =>
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
  isOwner: false,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 7, 31),
  updatedAt: DateTime.utc(2026, 7, 31),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);

void _expectText(WidgetTester tester, String key, String value) {
  expect(tester.widget<Text>(find.byKey(ValueKey(key))).data, value);
}

void _expectContains(WidgetTester tester, String key, String fragment) {
  expect(
    tester.widget<Text>(find.byKey(ValueKey(key))).data,
    contains(fragment),
    reason: key,
  );
}

/// The word on a record's standing, and its status role with it: §9 refuses a
/// standing carried by colour, so both halves are asserted together.
void _expectStatus(
  WidgetTester tester,
  String key,
  String label, {
  AppStatus? status,
}) {
  final badge = tester.widget<StatusBadge>(find.byKey(ValueKey(key)));
  expect(badge.label, label);
  if (status != null) expect(badge.status, status);
}

TenantQueryDocumentSnapshot _snapshot(
  String shiftId, {
  String tenantId = 'tenant-a',
  String? responsePath,
  Map<String, Object?>? overrides,
}) {
  final data = <String, Object?>{
    'shiftId': shiftId,
    'tenantId': tenantId,
    'staffId': 'user-a',
    'deviceId': _deviceA,
    'businessDate': _businessDate,
    'status': 'closed',
    'startTime': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 6)),
    'endTime': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 18)),
    'closingCashMinor': 125000,
    'closingCash': 1250,
    'totalSalesMinor': 98750,
    'totalSales': 987.5,
    'transactionCount': 3,
  };
  if (overrides != null) data.addAll(overrides);
  // **The declaration mirrors the counted cash unless a case says otherwise.**
  // The difference this surface names is the whole declaration against the whole
  // takings, so a fixture without one states no difference at all - which is
  // right for a shift closed before the triple existed and wrong for every case
  // here, all of which are about the difference itself.
  // All three or none: a partial triple is refused by the read model, which is
  // right, and would make every case here fail for the wrong reason.
  if (data['closingCashMinor'] != null &&
      !data.containsKey('declaredCashMinor')) {
    data['declaredCashMinor'] = data['closingCashMinor'];
    data.putIfAbsent('declaredMpesaMinor', () => 0);
    data.putIfAbsent('declaredCardMinor', () => 0);
  }
  data.removeWhere((key, value) => value == null);
  return TenantQueryDocumentSnapshot(
    path: responsePath ?? 'tenants/$tenantId/shifts/$shiftId',
    data: data,
  );
}

/// The four fields `amendShiftSummary` leaves on a shift it corrected. The count
/// is 2 so the plural cannot pass by accident.
Map<String, Object?> _amended() => <String, Object?>{
  'summaryAmendmentId': 'sm_abc',
  'summaryAmendedGeneration': 'generation-one',
  'summaryAmendmentCount': 2,
  'summaryAmendedAt': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 19)),
};

/// One `shift_amendments` record the trail's own strict read model accepts, so
/// the narrowed page this panel opens renders rather than failing closed.
TenantQueryDocumentSnapshot _amendmentSnapshot() => TenantQueryDocumentSnapshot(
  path: 'tenants/tenant-a/shift_amendments/sm_abc',
  data: <String, Object?>{
    'amendmentId': 'sm_abc',
    'tenantId': 'tenant-a',
    'shiftId': 'shift-a',
    'staffId': 'user-a',
    'businessDate': _businessDate,
    'sourceType': 'reconciliation_shift_variance',
    'expectationId': 'exp-a',
    'expectationGeneration': 'generation-one',
    'previousTotalSalesMinor': 98750,
    'previousTransactionCount': 3,
    'previousRepresentationsAgreed': true,
    'totalSalesMinor': 98250,
    'transactionCount': 3,
    'salesVarianceMinor': 500,
    'transactionVariance': 0,
    'clearedAnomalyId': null,
    'mutatesCountedCash': false,
    'reason': 'A late sale arrived after the shift closed',
    'actorUid': 'user-a',
    'requestId': 'amend-shift-abcdefgh',
    'createdAt': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 19)),
  },
);

final class _Reader implements TenantDataReader {
  _Reader({this.deferred = false, this.deniedStaff = false});

  final bool deferred;

  /// Stands in for the narrowed canonical staff read: a cashier, and any role
  /// the rule refuses, gets no name and must still see the page.
  final bool deniedStaff;
  final Map<String, List<TenantQueryDocumentSnapshot>> _pages =
      <String, List<TenantQueryDocumentSnapshot>>{};
  final List<TenantCollectionQuery> queries = <TenantCollectionQuery>[];
  final List<Completer<List<TenantQueryDocumentSnapshot>>> pending =
      <Completer<List<TenantQueryDocumentSnapshot>>>[];
  final List<List<TenantQueryDocumentSnapshot>> _deferredResults =
      <List<TenantQueryDocumentSnapshot>>[];

  void respond(String path, List<TenantQueryDocumentSnapshot> page) =>
      _pages[path] = page;

  /// Completes the oldest outstanding page, mimicking a slow first business.
  void completeFirst() {
    if (pending.isEmpty) return;
    pending.removeAt(0).complete(_deferredResults.removeAt(0));
  }

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    if (deniedStaff) throw StateError('permission-denied');
    final uid = path.split('/').last;
    return path.startsWith('tenants/tenant-a/staff/') && uid != 'user-a'
        ? TenantDocumentSnapshot(
            path: path,
            data: <String, Object?>{'uid': uid, 'name': 'Brian'},
          )
        : null;
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
      final matchesFilters = query.equalityFilters.entries.every(
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
