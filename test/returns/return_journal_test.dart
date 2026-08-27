import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/returns/returns.dart';
import 'package:flutter_application_1/theme.dart';
import 'package:flutter_application_1/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

final _tokens = spiritTheme.extension<AppTokens>()!;

void main() {
  testWidgets('the reason is the page, set larger than anything else', (
    tester,
  ) async {
    await _pump(tester, _record());

    final reason = tester.widget<Text>(
      find.byKey(const ValueKey('return-journal-reason')),
    );
    final recorded = tester.widget<Text>(
      find.byKey(const ValueKey('return-journal-recorded')),
    );
    expect(reason.data, 'Bottle was corked');
    expect(
      reason.style!.fontSize,
      greaterThan(recorded.style!.fontSize!),
    );
    expect(reason.textAlign, TextAlign.center);
  });

  testWidgets('the figure counts every unit across the lines', (tester) async {
    await _pump(tester, _record());

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('return-journal-units')))
          .data,
      '5 units',
    );
  });

  testWidgets('one unit is not called units', (tester) async {
    await _pump(
      tester,
      _record(
        lines: <Map<String, Object?>>[
          <String, Object?>{
            'productId': 'pd-1',
            'productName': 'Cold lager',
            'quantity': 1,
          },
        ],
      ),
    );

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('return-journal-units')))
          .data,
      '1 unit',
    );
  });

  testWidgets('every returned line is named, not summarised', (tester) async {
    await _pump(tester, _record());

    expect(find.byKey(const ValueKey('return-journal-line-pd-1')), findsOne);
    expect(find.byKey(const ValueKey('return-journal-line-pd-2')), findsOne);
    expect(find.text('Cold lager'), findsOne);
    expect(find.text('Qty 2'), findsOne);
  });

  testWidgets('a line with no name falls back to the id it is filed under', (
    tester,
  ) async {
    await _pump(
      tester,
      _record(
        lines: <Map<String, Object?>>[
          <String, Object?>{'productId': 'pd-9', 'quantity': 1},
        ],
      ),
    );

    expect(find.text('pd-9'), findsOne);
  });

  testWidgets('§9: the standing is a word, not only a colour', (tester) async {
    await _pump(tester, _record());
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('return-journal-status')))
          .data,
      'UNVERIFIED',
    );

    await _pump(tester, _verified());
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('return-journal-status')))
          .data,
      'VERIFIED',
    );
  });

  testWidgets('a verified return names who verified it and when', (
    tester,
  ) async {
    await _pump(tester, _verified());

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('return-journal-verified-by')))
          .data,
      // `tenantStaffLabel`'s canonical shape: the name a person knows, and the
      // uid the audit trail knows, so the two are never confused.
      'Ada M (user-a)',
    );
    expect(find.byKey(const ValueKey('return-journal-verified')), findsOne);
    expect(find.byKey(const ValueKey('return-journal-verify')), findsNothing);
  });

  testWidgets('an unverified return with nobody to verify it says so', (
    tester,
  ) async {
    await _pump(tester, _record());

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('return-journal-verified-by')))
          .data,
      'Nobody yet',
    );
    expect(find.byKey(const ValueKey('return-journal-awaiting')), findsOne);
    expect(find.byKey(const ValueKey('return-journal-verify')), findsNothing);
  });

  testWidgets('the verify action appears only where one was handed in', (
    tester,
  ) async {
    var pressed = 0;
    await _pump(tester, _record(), onVerify: () => pressed++);

    final verify = find.byKey(const ValueKey('return-journal-verify'));
    expect(verify, findsOne);
    expect(find.byKey(const ValueKey('return-journal-awaiting')), findsNothing);
    await tester.tap(verify);
    await tester.pump();
    expect(pressed, 1);
  });

  testWidgets('a return with no server time says so rather than inventing one', (
    tester,
  ) async {
    await _pump(tester, _record(omitRecordedAt: true));

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('return-journal-recorded')))
          .data,
      'Awaiting server time',
    );
  });

  testWidgets('the recorded instant is the reader\'s own time, not UTC', (
    tester,
  ) async {
    await _pump(tester, _record());

    final shown = tester
        .widget<Text>(find.byKey(const ValueKey('return-journal-recorded')))
        .data!;
    final local = DateTime.utc(2026, 8, 26, 11, 5).toLocal();
    expect(shown, contains('${local.hour.toString().padLeft(2, '0')}:05'));
    expect(shown, isNot(contains('UTC')));
  });

  testWidgets('the particulars are two columns wide and one column narrow', (
    tester,
  ) async {
    await _pump(tester, _record(), width: 1200);
    final wideInventory = tester.getRect(
      find.byKey(const ValueKey('return-journal-line-pd-1')),
    );
    final widePeople = tester.getRect(
      find.byKey(const ValueKey('return-journal-recorded-by')),
    );
    expect(widePeople.left, greaterThan(wideInventory.right));

    await _pump(tester, _record(), width: 411);
    final narrowInventory = tester.getRect(
      find.byKey(const ValueKey('return-journal-line-pd-1')),
    );
    final narrowPeople = tester.getRect(
      find.byKey(const ValueKey('return-journal-recorded-by')),
    );
    expect(narrowPeople.top, greaterThan(narrowInventory.bottom));
  });

  testWidgets('the quote glyph is set from the type it opens', (tester) async {
    await _pump(tester, _record(), width: 411);
    final compact = tester.widget<Icon>(find.byIcon(Icons.format_quote)).size;
    expect(compact, _tokens.typography.displayCompact.fontSize);

    await _pump(tester, _record(), width: 1200);
    final wide = tester.widget<Icon>(find.byIcon(Icons.format_quote)).size;
    expect(wide, _tokens.typography.display.fontSize);
    expect(wide, greaterThan(compact!));
  });
}

Future<void> _pump(
  WidgetTester tester,
  TenantReturn record, {
  VoidCallback? onVerify,
  double width = 411,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: TenantReturnJournalScreen(
        record: record,
        staffNames: const <String, String>{'user-a': 'Ada M', 'user-b': 'Ben O'},
        selfUid: 'user-z',
        onVerify: onVerify,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

TenantReturn _record({
  List<Map<String, Object?>>? lines,
  DateTime? recordedAt,
  bool omitRecordedAt = false,
  bool verified = false,
}) {
  final data = <String, Object?>{
    'returnId': 'rt-1',
    'tenantId': 'tenant-a',
    'saleId': 'sale-1',
    'createdBy': 'user-b',
    'status': verified ? 'verified' : 'pending',
    'reason': 'Bottle was corked',
    'itemsReturned':
        lines ??
        <Object?>[
          <String, Object?>{
            'productId': 'pd-1',
            'productName': 'Cold lager',
            'quantity': 2,
          },
          <String, Object?>{
            'productId': 'pd-2',
            'productName': 'Long-life milk',
            'quantity': 3,
          },
        ],
    if (!omitRecordedAt)
      'createdAt': Timestamp.fromDate(recordedAt ?? _recordedAt),
    if (verified) ...<String, Object?>{
      'verified': true,
      'verifiedBy': 'user-a',
      'verifiedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 26, 12, 30)),
      'stockRestored': true,
      'stockRestorationId': 'rq-1',
    },
  };
  return TenantReturn.fromDocument(
    path: 'tenants/tenant-a/returns/rt-1',
    data: data,
  );
}

TenantReturn _verified() => _record(verified: true);

final DateTime _recordedAt = DateTime.utc(2026, 8, 26, 11, 5);
