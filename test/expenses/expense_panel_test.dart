/// The Expenses route.
///
/// **What the cases below are mostly about is what the page refuses to say.** A
/// spending figure that is short reads exactly like a spending figure that is
/// right, so the page has to state the difference; and a page still reading has
/// to avoid claiming a total of nothing, which is the one wrong answer that
/// looks completely ordinary.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/expenses/expense.dart';
import 'package:flutter_application_1/expenses/expense_charts.dart';
import 'package:flutter_application_1/expenses/expense_panel.dart';
import 'package:flutter_application_1/expenses/expense_request.dart';
import 'package:flutter_application_1/ui/buttons.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  _rangeCases();

  testWidgets('the period chooser draws before the figures do', (tester) async {
    // The control that would take a person to a different stretch of days must
    // not sit behind the read of this one.
    final held = Completer<void>();
    addTearDown(() {
      if (!held.isCompleted) held.complete();
    });
    await _pump(tester, reader: _Reader(gate: held), settle: false);

    expect(find.byKey(const ValueKey('expenses-range')), findsOne);
    expect(find.byKey(const ValueKey('expenses-reading')), findsOne);

    held.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a page still reading claims no total', (tester) async {
    // `KES 0.00` over a month of spending is the worst kind of wrong figure: a
    // plausible one.
    final held = Completer<void>();
    addTearDown(() {
      if (!held.isCompleted) held.complete();
    });
    await _pump(tester, reader: _Reader(gate: held), settle: false);

    expect(find.byKey(const ValueKey('expenses-total')), findsNothing);
    expect(find.byKey(const ValueKey('expenses-empty')), findsNothing);

    held.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a business that recorded nothing is told so', (tester) async {
    await _pump(tester, reader: _Reader());

    expect(find.byKey(const ValueKey('expenses-empty')), findsOne);
    expect(find.byKey(const ValueKey('expenses-total')), findsOne);
  });

  testWidgets('what was spent is totalled and split by category', (
    tester,
  ) async {
    await _pump(
      tester,
      reader: _Reader(
        records: <Map<String, Object?>>[
          _record(token: 'aaa', amountMinor: 30000),
          _record(
            token: 'bbb',
            amountMinor: 10000,
            category: TenantExpenseCategory.transport,
          ),
        ],
      ),
    );

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('expenses-ring-total')))
          .data,
      'KES 400.00',
      reason: 'The period total is the middle of the ring.',
    );
    // Largest first, and each row carries its own figure rather than leaving
    // the share to the length of a bar.
    expect(find.byKey(const ValueKey('expense-share-rent')), findsOne);
    expect(find.byKey(const ValueKey('expense-share-amount-rent')), findsOne);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('expense-share-amount-rent')))
          .data,
      'KES 300.00',
    );
    expect(find.text('75%'), findsOne);
  });

  testWidgets('a voided record is listed and left out of the total', (
    tester,
  ) async {
    await _pump(
      tester,
      reader: _Reader(
        records: <Map<String, Object?>>[
          _record(token: 'aaa', amountMinor: 10000),
          _record(token: 'bbb', amountMinor: 90000, voided: true),
        ],
      ),
    );

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('expenses-ring-total')))
          .data,
      'KES 100.00',
      reason: 'Money that did not leave the business counts towards nothing.',
    );

    // It is still listed - under the type it was spent on, which is the
    // only place this app lists records now.
    await tester.tap(find.byKey(const ValueKey('expense-open-rent')));
    await tester.pumpAndSettle();
    // The word, beside the reason it was withdrawn for - not the strike
    // through the figure on its own.
    expect(find.textContaining('Voided'), findsOne);
  });

  testWidgets('a part-read period says the total is not the whole of it', (
    tester,
  ) async {
    await _pump(
      tester,
      reader: _Reader(
        records: <Map<String, Object?>>[
          for (var index = 0; index < 300; index++)
            _record(
              token: 'tok${index.toString().padLeft(4, '0')}',
              amountMinor: 100,
            ),
        ],
      ),
    );

    expect(find.byKey(const ValueKey('expenses-truncated')), findsOne);
  });

  testWidgets('a manager is refused, and told who is not', (tester) async {
    await _pump(tester, reader: _Reader(), role: TenantRole.manager);

    expect(find.byKey(const ValueKey('expenses-denied')), findsOne);
    expect(find.byKey(const ValueKey('expenses-record')), findsNothing);
  });

  testWidgets('a build with no writer offers no form it cannot submit', (
    tester,
  ) async {
    await _pump(tester, reader: _Reader(), writer: null);

    expect(find.byKey(const ValueKey('expenses-record')), findsNothing);
  });

  testWidgets('a business with no published currency says so once', (
    tester,
  ) async {
    await _pump(tester, reader: _Reader(currency: null));

    expect(find.byKey(const ValueKey('expenses-currency-unknown')), findsOne);
  });

  testWidgets('the record sheet takes every character typed into it', (
    tester,
  ) async {
    // **`enterText` would not catch this.** It replaces the whole value in one
    // call, so a field that has lost its platform input connection still ends
    // up holding the right string. This types the way a keyboard does - one
    // `updateEditingValue` per character, through whatever connection the field
    // is holding at that moment - and then reads the field back. A sheet that
    // re-parents its `TextField` when the first character lands, or when the
    // keyboard takes its share of the screen, fails here and nowhere else.
    final writer = _Writer();
    await _pump(tester, reader: _Reader(), writer: writer);

    await tester.tap(find.byKey(const ValueKey('expenses-record')));
    await tester.pumpAndSettle();

    await _typeCharacterByCharacter(
      tester,
      const ValueKey('expense-description'),
      'August rent',
    );
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const ValueKey('expense-description')),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      'August rent',
    );

    // The keyboard arriving is what re-pads the sheet. A field re-parented by
    // that pass would go dead mid-word, which is the shape of the defect
    // `_AboveTheKeyboard` exists for - so the amount is typed after it.
    tester.view.viewInsets = const FakeViewPadding(bottom: 800);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    await _typeCharacterByCharacter(
      tester,
      const ValueKey('expense-amount'),
      '1250',
    );
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const ValueKey('expense-amount')),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      '1250',
    );
  });

  testWidgets('recording an expense writes it and re-reads the period', (
    tester,
  ) async {
    final writer = _Writer();
    final reader = _Reader();
    await _pump(tester, reader: reader, writer: writer);

    await tester.tap(find.byKey(const ValueKey('expenses-record')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('expense-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expense-category-rent')).last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('expense-description')),
      'August rent',
    );
    await tester.enterText(find.byKey(const ValueKey('expense-amount')), '300');
    await tester.tap(find.byKey(const ValueKey('expense-submit')));
    await tester.pumpAndSettle();

    expect(writer.recorded, hasLength(1));
    expect(writer.recorded.single.amountMinor, 30000);
    expect(writer.recorded.single.category, TenantExpenseCategory.rent);
    expect(
      reader.reads,
      greaterThan(1),
      reason: 'The period is re-read so the total is the record, not a guess.',
    );
  });

  testWidgets('an expense still in flight re-reads the period too', (
    tester,
  ) async {
    // **The reported defect.** This re-read only on `AppStatus.ok`, which is
    // the committed write alone - a queued one answers `AppNotice.offline`,
    // whose status is `info`. So an expense recorded while the write was still
    // going left the list reading "Nothing recorded last 30 days" over the
    // expense just entered, and the obvious response to that is to enter it a
    // second time.
    final writer = _Writer(result: const TenantExpenseWriteResult.queued());
    final reader = _Reader();
    await _pump(tester, reader: reader, writer: writer);
    final before = reader.reads;

    await tester.tap(find.byKey(const ValueKey('expenses-record')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expense-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expense-category-rent')).last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('expense-description')),
      'August rent',
    );
    await tester.enterText(find.byKey(const ValueKey('expense-amount')), '300');
    await tester.tap(find.byKey(const ValueKey('expense-submit')));
    await tester.pumpAndSettle();

    expect(
      reader.reads,
      greaterThan(before),
      reason: 'A queued expense is a record this list has to show.',
    );
  });

  testWidgets('an expense with no category chosen is not submitted', (
    tester,
  ) async {
    final writer = _Writer();
    await _pump(tester, reader: _Reader(), writer: writer);

    await tester.tap(find.byKey(const ValueKey('expenses-record')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('expense-description')),
      'August rent',
    );
    await tester.enterText(find.byKey(const ValueKey('expense-amount')), '300');
    await tester.tap(find.byKey(const ValueKey('expense-submit')));
    await tester.pumpAndSettle();

    expect(writer.recorded, isEmpty);
    expect(find.byKey(const ValueKey('expense-error')), findsOne);
  });

  testWidgets('an offline device is told why nothing was recorded', (
    tester,
  ) async {
    final writer = _Writer(
      result: const TenantExpenseWriteResult.unavailable(),
    );
    await _pump(tester, reader: _Reader(), writer: writer);

    await tester.tap(find.byKey(const ValueKey('expenses-record')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expense-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expense-category-rent')).last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('expense-description')),
      'August rent',
    );
    await tester.enterText(find.byKey(const ValueKey('expense-amount')), '300');
    await tester.tap(find.byKey(const ValueKey('expense-submit')));
    await tester.pumpAndSettle();

    // The form stays open with the entry still in it, so nothing is retyped.
    expect(find.byKey(const ValueKey('expense-error')), findsOne);
    expect(find.byKey(const ValueKey('expense-submit')), findsOne);
  });

  testWidgets('the composition ring is drawn with its legend', (tester) async {
    await _pump(
      tester,
      reader: _Reader(
        records: <Map<String, Object?>>[
          _record(token: 'aaa', amountMinor: 30000),
          _record(
            token: 'bbb',
            amountMinor: 10000,
            category: TenantExpenseCategory.transport,
          ),
        ],
      ),
    );

    expect(find.byType(ExpenseCompositionRing), findsOne);
    // The total sits in the hole in the middle, which is what the ring is for.
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('expenses-ring-total')))
          .data,
      'KES 400.00',
    );
    // **The legend is the accessible reading of the same data.** Every slice
    // has a labelled row carrying its name and figure, so no fact here is
    // told by colour alone.
    expect(find.byKey(const ValueKey('expense-share-rent')), findsOne);
    expect(find.byKey(const ValueKey('expense-share-transport')), findsOne);
  });

  testWidgets('a period that spent nothing draws no ring', (tester) async {
    // A ring of one grey slice says a business had one expense, which is a
    // different fact from none.
    await _pump(tester, reader: _Reader());

    expect(find.byType(ExpenseCompositionRing), findsNothing);
  });

  testWidgets('a category opens its own records and chart', (tester) async {
    await _pump(
      tester,
      reader: _Reader(
        records: <Map<String, Object?>>[
          _record(token: 'aaa', amountMinor: 30000),
          _record(
            token: 'bbb',
            amountMinor: 10000,
            category: TenantExpenseCategory.transport,
          ),
        ],
      ),
    );

    await tester.tap(find.byKey(const ValueKey('expense-open-rent')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('expense-category')), findsOne);
    expect(find.byKey(const ValueKey('expense-category-chart')), findsOne);
    // Only this category, and its share of everything.
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('expense-category-total')))
          .data,
      'KES 300.00',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('expense-category-summary')))
          .data,
      contains('75% of all spending'),
    );
  });

  testWidgets('voiding a record asks why, writes it, and re-reads', (
    tester,
  ) async {
    final writer = _Writer();
    final reader = _Reader(
      records: <Map<String, Object?>>[
        _record(token: 'aaa', amountMinor: 30000),
      ],
    );
    await _pump(tester, reader: reader, writer: writer);
    final readsBefore = reader.reads;

    await tester.tap(find.byKey(const ValueKey('expense-open-rent')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expense-void-2026-08-27-aaa')));
    await tester.pumpAndSettle();

    // A void with no reason is refused before it reaches the network, because
    // the Firestore rule refuses it too.
    await tester.tap(find.byKey(const ValueKey('expense-void-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('expense-void-error')), findsOne);
    expect(writer.voided, isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey('expense-void-reason')),
      'Recorded twice',
    );
    await tester.tap(find.byKey(const ValueKey('expense-void-submit')));
    await tester.pumpAndSettle();

    expect(writer.voided, hasLength(1));
    expect(writer.voided.single.expenseId, '2026-08-27-aaa');
    expect(writer.voided.single.reason, 'Recorded twice');
    expect(reader.reads, greaterThan(readsBefore));
    // **And the type's own screen is gone.** It holds the period it was
    // handed, so every figure on it went stale the moment the write landed;
    // the list behind it has re-read by the time a person lands back on it.
    expect(find.byKey(const ValueKey('expense-category')), findsNothing);
    expect(find.byKey(const ValueKey('expenses')), findsOne);
  });

  testWidgets('an already voided record offers no second void', (tester) async {
    await _pump(
      tester,
      reader: _Reader(
        records: <Map<String, Object?>>[
          _record(token: 'aaa', amountMinor: 30000, voided: true),
        ],
      ),
    );

    await tester.tap(find.byKey(const ValueKey('expense-open-rent')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('expense-void-2026-08-27-aaa')),
      findsNothing,
    );
    // The reason it went travels with it, so a struck-through row is a
    // correction rather than a mystery.
    expect(find.textContaining('Recorded twice'), findsOne);
  });

  testWidgets('a period of nothing but voided records still reaches them', (
    tester,
  ) async {
    await _pump(
      tester,
      reader: _Reader(
        records: <Map<String, Object?>>[
          _record(token: 'aaa', amountMinor: 30000, voided: true),
        ],
      ),
    );

    // Nothing was taken, so there is no composition to draw - but the record
    // exists, and a type is the only way into it now that this route lists
    // none itself.
    expect(find.byKey(const ValueKey('expenses-total')), findsOne);
    await tester.tap(find.byKey(const ValueKey('expense-open-rent')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('expense-category')), findsOne);
    expect(find.textContaining('Recorded twice'), findsOne);
  });

  testWidgets('a build with no writer offers no void', (tester) async {
    await _pump(
      tester,
      reader: _Reader(
        records: <Map<String, Object?>>[
          _record(token: 'aaa', amountMinor: 30000),
        ],
      ),
      writer: null,
    );

    await tester.tap(find.byKey(const ValueKey('expense-open-rent')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('expense-category')), findsOne);
    expect(
      find.byKey(const ValueKey('expense-void-2026-08-27-aaa')),
      findsNothing,
      reason: 'A build that cannot write offers no control that writes.',
    );
  });
}

/// Types [value] one character at a time, against whatever input connection the
/// field holds at that moment. See the case that calls it for why.
Future<void> _typeCharacterByCharacter(
  WidgetTester tester,
  Key field,
  String value,
) async {
  await tester.tap(find.byKey(field));
  await tester.pumpAndSettle();
  var soFar = '';
  for (final character in value.split('')) {
    soFar += character;
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: soFar,
        selection: TextSelection.collapsed(offset: soFar.length),
      ),
    );
    await tester.pump();
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required _Reader reader,
  TenantExpenseWriter? writer = const _NoWriter(),
  TenantRole role = TenantRole.owner,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = TenantSessionController()
    ..open(uid: 'owner-a', membership: _membership(role));
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: TenantExpensesScreen(
          reader: reader,
          writer: writer is _NoWriter ? _Writer() : writer,
          clock: () => DateTime.utc(2026, 8, 27, 12),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }
}

/// Distinguishes "no writer was passed" from "the default writer".
final class _NoWriter implements TenantExpenseWriter {
  const _NoWriter();

  @override
  Future<TenantExpenseWriteResult> recordExpense(
    TenantExpenseCreateIntent intent,
  ) async => const TenantExpenseWriteResult.committed();

  @override
  Future<TenantExpenseWriteResult> voidExpense(
    TenantExpenseVoidIntent intent,
  ) async => const TenantExpenseWriteResult.committed();
}

final class _Writer implements TenantExpenseWriter {
  _Writer({this.result = const TenantExpenseWriteResult.committed()});

  final TenantExpenseWriteResult result;
  final List<TenantExpenseCreateIntent> recorded =
      <TenantExpenseCreateIntent>[];
  final List<TenantExpenseVoidIntent> voided = <TenantExpenseVoidIntent>[];

  @override
  Future<TenantExpenseWriteResult> recordExpense(
    TenantExpenseCreateIntent intent,
  ) async {
    if (result.kind == TenantExpenseWriteKind.committed) recorded.add(intent);
    return result;
  }

  @override
  Future<TenantExpenseWriteResult> voidExpense(
    TenantExpenseVoidIntent intent,
  ) async {
    if (result.kind == TenantExpenseWriteKind.committed) voided.add(intent);
    return result;
  }
}

/// The range filter, which replaced three fixed offsets on 2026-09-22.
void _rangeCases() {
  testWidgets('the page opens on the month so far, not a fixed 30 days', (
    tester,
  ) async {
    // The clock is 27 August, so the range is the 1st to the 27th. A record on
    // 20 July is inside the old *Last 30 days* and outside this month, which is
    // what makes it the case that tells the two apart.
    final reader = _Reader(
      records: <Map<String, Object?>>[
        _record(token: 'aaa', amountMinor: 30000, date: '2026-07-20'),
        _record(token: 'bbb', amountMinor: 10000, date: '2026-08-05'),
      ],
    );
    await _pump(tester, reader: reader);

    expect(
      reader.cursors.first,
      '2026-08-01',
      reason: 'The read opens at the first of the month the clock is in.',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('expenses-ring-total')))
          .data,
      'KES 100.00',
      reason: 'July is before this month and is not in the total.',
    );
  });

  testWidgets('the filter names the stretch it is holding', (tester) async {
    await _pump(tester, reader: _Reader());

    expect(
      tester
          .widget<AppButton>(find.byKey(const ValueKey('expenses-range')))
          .label,
      'This month',
      reason: 'A range a person has a word for is said in that word.',
    );
  });

  testWidgets('the filter opens a calendar over two dates', (tester) async {
    await _pump(tester, reader: _Reader());

    await tester.tap(find.byKey(const ValueKey('expenses-range')));
    await tester.pumpAndSettle();

    expect(
      find.byType(DateRangePickerDialog),
      findsOne,
      reason:
          'A range is picked on the platform calendar, not from a list of '
          'offsets somebody guessed at.',
    );
  });

  testWidgets('the count and the empty state say what the range is called', (
    tester,
  ) async {
    await _pump(tester, reader: _Reader());

    expect(find.text('Nothing recorded this month'), findsOne);
  });
}

Map<String, Object?> _record({
  required String token,
  required int amountMinor,
  String date = '2026-08-27',
  TenantExpenseCategory category = TenantExpenseCategory.rent,
  bool voided = false,
}) => <String, Object?>{
  'expenseId': '$date-$token',
  'tenantId': 'tenant-a',
  'businessDate': date,
  'category': category.wireValue,
  'description': 'Something the business paid for',
  'amountMinor': amountMinor,
  'amount': amountMinor / 100,
  'recordedBy': 'owner-a',
  'createdAt': DateTime.utc(2026, 8, 27, 9),
  if (voided) ...<String, Object?>{
    'voidedAt': DateTime.utc(2026, 8, 27, 10),
    'voidedBy': 'owner-a',
    'voidReason': 'Recorded twice.',
  },
};

final class _Reader implements TenantDataReader {
  _Reader({
    this.records = const <Map<String, Object?>>[],
    this.currency = 'KES',
    this.gate,
  });

  final List<Map<String, Object?>> records;
  final String? currency;

  /// Holds the collection read open so a case can watch the page before it.
  final Completer<void>? gate;

  int reads = 0;

  /// Every cursor the repository has opened a page at. The first of these is
  /// the range's own start date - see `TenantExpenseRepository.readRange`,
  /// which uses the start date itself as the opening cursor.
  final List<String?> cursors = <String?>[];

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    if (path.endsWith('/configuration/checkout') && currency != null) {
      return TenantDocumentSnapshot(
        path: path,
        data: <String, Object?>{'currency': currency},
      );
    }
    return null;
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    reads++;
    cursors.add(query.startAfterDocumentId);
    if (gate != null) await gate!.future;
    final byId = <String, Map<String, Object?>>{
      for (final record in records) record['expenseId']! as String: record,
    };
    final ids = byId.keys.toList()..sort();
    final cursor = query.startAfterDocumentId;
    final page = <TenantQueryDocumentSnapshot>[];
    for (final id in ids) {
      if (cursor != null && id.compareTo(cursor) <= 0) continue;
      if (page.length >= query.limit) break;
      page.add(
        TenantQueryDocumentSnapshot(
          path: 'tenants/tenant-a/expenses/$id',
          data: byId[id]!,
        ),
      );
    }
    return page;
  }
}

TenantMembership _membership(TenantRole role) => TenantMembership(
  tenantId: 'tenant-a',
  tenantName: 'Chilltent Lounge',
  tenantSlug: 'chilltent-lounge',
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
