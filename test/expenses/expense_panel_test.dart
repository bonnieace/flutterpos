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
import 'package:flutter_application_1/expenses/expense_panel.dart';
import 'package:flutter_application_1/expenses/expense_request.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
      find.descendant(
        of: find.byKey(const ValueKey('expenses-total')),
        matching: find.text('KES 400.00'),
      ),
      findsOne,
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

    expect(find.text('Voided'), findsOne);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('expenses-total')),
        matching: find.text('KES 100.00'),
      ),
      findsOne,
      reason: 'Money that did not leave the business counts towards nothing.',
    );
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
  ) async => result;
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
