import 'package:flutter/material.dart';
import 'package:flutter_application_1/theme.dart';
import 'package:flutter_application_1/ui/buttons.dart';
import 'package:flutter_application_1/ui/record_list.dart';
import 'package:flutter_application_1/ui/status.dart';
import 'package:flutter_application_1/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

const _tokens = AppTokens.dark;

/// A screen width inside each of §4.1's three bands.
///
/// Stated as figures rather than as `AppLayout.mediumFloor - 1`, so a test that
/// disagrees with the contract is a failure rather than an arithmetic identity
/// that can never fail.
const Size _compact = Size(411, 891);
const Size _medium = Size(834, 1000);
const Size _expanded = Size(1440, 900);

/// Mounts [child] at [size], under the app's own theme.
///
/// The size is set on the view rather than on a `MediaQuery` around the child,
/// because `RecordList` resolves its form from the *screen* and a nested
/// `MediaQuery` would be exactly the fourth boundary the component refuses to
/// invent.
Future<void> _pumpAt(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(20), child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

RecordItem _item({
  String id = 'r1',
  String title = 'Fresh whole milk 500ml',
  String? subtitle,
  RecordStatus? status,
  List<RecordAttribute> attributes = const <RecordAttribute>[],
  String? provenance,
  List<RecordAction> actions = const <RecordAction>[],
}) => RecordItem(
  id: id,
  title: title,
  subtitle: subtitle,
  status: status,
  attributes: attributes,
  provenance: provenance,
  actions: actions,
);

List<RecordAction> _actions(int count, {void Function(String)? onPressed}) => <
  RecordAction
>[
  for (var index = 0; index < count; index++)
    RecordAction(
      label: 'Action $index',
      actionKey: ValueKey<String>('action-$index'),
      onPressed: () => onPressed?.call('Action $index'),
    ),
];

void main() {
  group('§4.3 resolves one form per band, from the screen', () {
    test('the three bands map to the three renderings', () {
      // The whole contract in one assertion set: §4.3's `RecordList` row is
      // stacked cards / two-column cards / data table, in that order.
      expect(RecordList.formFor(0), RecordForm.stackedCards);
      expect(RecordList.formFor(767), RecordForm.stackedCards);
      expect(RecordList.formFor(768), RecordForm.twoColumnCards);
      expect(RecordList.formFor(1023), RecordForm.twoColumnCards);
      expect(RecordList.formFor(1024), RecordForm.table);
      expect(RecordList.formFor(2560), RecordForm.table);
    });

    test('the boundaries are §4.1\'s and are not a second declaration', () {
      // A form flips exactly where `AppLayout` says a band does. Written
      // against the contract rather than against 768 and 1024, so moving a
      // floor moves this test with it instead of leaving it asserting an
      // orphaned number.
      final layout = _tokens.layout;
      expect(RecordList.formFor(layout.mediumFloor), RecordForm.twoColumnCards);
      expect(RecordList.formFor(layout.mediumFloor - 1), RecordForm.stackedCards);
      expect(RecordList.formFor(layout.expandedFloor), RecordForm.table);
      expect(
        RecordList.formFor(layout.expandedFloor - 1),
        RecordForm.twoColumnCards,
      );
    });

    testWidgets('a phone stacks one card per record', (tester) async {
      await _pumpAt(
        tester,
        _compact,
        RecordList(
          identityLabel: 'Product',
          items: <RecordItem>[_item(id: 'a'), _item(id: 'b', title: 'Sugar 1kg')],
        ),
      );
      expect(find.byKey(const ValueKey<String>('record-a')), findsOne);
      expect(find.byKey(const ValueKey<String>('record-b')), findsOne);
      // One above the other, which is what "stacked" is.
      final first = tester.getRect(find.byKey(const ValueKey<String>('record-a')));
      final second = tester.getRect(
        find.byKey(const ValueKey<String>('record-b')),
      );
      expect(second.top, greaterThanOrEqualTo(first.bottom));
      expect(second.left, first.left);
    });

    testWidgets('a tablet puts two cards on a row, in reading order', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        _medium,
        RecordList(
          identityLabel: 'Product',
          items: <RecordItem>[
            _item(id: 'a'),
            _item(id: 'b'),
            _item(id: 'c'),
          ],
        ),
      );
      final a = tester.getRect(find.byKey(const ValueKey<String>('record-a')));
      final b = tester.getRect(find.byKey(const ValueKey<String>('record-b')));
      final c = tester.getRect(find.byKey(const ValueKey<String>('record-c')));
      // Second record to the right of the first, not below it: a list is read
      // in order and the second record belongs where the second record goes.
      expect(b.left, greaterThan(a.left));
      expect(b.top, a.top);
      expect(c.top, greaterThan(a.top));
      expect(c.left, a.left);
      // The odd one out keeps a column's width rather than stretching across
      // the row, which would read as a record that matters more.
      expect(c.width, closeTo(a.width, 0.5));
    });

    testWidgets('a desktop window draws one table with one header', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        _expanded,
        RecordList(
          identityLabel: 'Event',
          items: <RecordItem>[
            _item(
              id: 'a',
              attributes: const <RecordAttribute>[
                RecordAttribute(label: 'Change', value: 'pending to active'),
              ],
            ),
            _item(
              id: 'b',
              attributes: const <RecordAttribute>[
                RecordAttribute(label: 'Change', value: 'active to inactive'),
              ],
            ),
          ],
        ),
      );
      expect(find.text('Event'), findsOne);
      expect(find.text('Change'), findsOne);
      // Both records on one surface: a table, not two cards wearing a header.
      final a = tester.getRect(find.byKey(const ValueKey<String>('record-a')));
      final b = tester.getRect(find.byKey(const ValueKey<String>('record-b')));
      expect(a.left, b.left);
      expect(a.width, b.width);
      expect(b.top, greaterThanOrEqualTo(a.bottom - 1));
    });
  });

  group('the caller decides what a narrow form loses', () {
    testWidgets('an attribute marked out of the narrow form is dropped there', (
      tester,
    ) async {
      const item = RecordItem(
        id: 'a',
        title: 'Fresh whole milk 500ml',
        attributes: <RecordAttribute>[
          RecordAttribute(label: 'Price', value: 'KES 65.00'),
          RecordAttribute(
            label: 'Recorded cost',
            value: 'KES 48.00',
            inNarrowForm: false,
          ),
        ],
      );
      await _pumpAt(
        tester,
        _compact,
        const RecordList(identityLabel: 'Product', items: <RecordItem>[item]),
      );
      expect(find.text('KES 65.00'), findsOne);
      expect(find.text('KES 48.00'), findsNothing);

      // The table has a column for it, so nothing is lost where there is room.
      await _pumpAt(
        tester,
        _expanded,
        const RecordList(identityLabel: 'Product', items: <RecordItem>[item]),
      );
      expect(find.text('KES 65.00'), findsOne);
      expect(find.text('KES 48.00'), findsOne);
      expect(find.text('Recorded cost'), findsOne);
    });

    testWidgets('identity, status, provenance and actions are never dropped', (
      tester,
    ) async {
      // The limit of the concession. §4.3 concedes attributes and nothing else,
      // so all four survive the narrowest band.
      await _pumpAt(
        tester,
        _compact,
        RecordList(
          identityLabel: 'Member',
          items: <RecordItem>[
            _item(
              title: 'Amina Odhiambo',
              subtitle: 'amina@example.com',
              status: const RecordStatus(
                status: AppStatus.attention,
                label: 'Pending',
              ),
              provenance: 'Recorded 2026-08-01 09:00 UTC by You',
              actions: _actions(1),
            ),
          ],
        ),
      );
      expect(find.text('Amina Odhiambo'), findsOne);
      expect(find.text('amina@example.com'), findsOne);
      expect(find.byType(StatusBadge), findsOne);
      expect(find.text('Recorded 2026-08-01 09:00 UTC by You'), findsOne);
      expect(find.byKey(const ValueKey<String>('action-0')), findsOne);
    });
  });

  group('a table is the list\'s shape, not its first record\'s', () {
    testWidgets('a column exists for every label any record carries', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        _expanded,
        RecordList(
          identityLabel: 'Event',
          items: <RecordItem>[
            // The first record is the silent one deliberately: taking its
            // attributes as the columns would drop the other two entirely.
            _item(id: 'a', title: 'Business reviewed'),
            _item(
              id: 'b',
              title: 'Staff invited',
              attributes: const <RecordAttribute>[
                RecordAttribute(label: 'About', value: 'Amina (cashier-a)'),
              ],
            ),
            _item(
              id: 'c',
              title: 'Staff status set',
              attributes: const <RecordAttribute>[
                RecordAttribute(label: 'Change', value: 'pending to active'),
              ],
            ),
          ],
        ),
      );
      expect(find.text('About'), findsOne);
      expect(find.text('Change'), findsOne);
      expect(find.text('Amina (cashier-a)'), findsOne);
      expect(find.text('pending to active'), findsOne);
    });

    test('the column order is first appearance across the whole list', () {
      final columns = RecordList.columnsOf(<RecordItem>[
        _item(id: 'a'),
        _item(
          id: 'b',
          attributes: const <RecordAttribute>[
            RecordAttribute(label: 'Change', value: 'x'),
          ],
        ),
        _item(
          id: 'c',
          attributes: const <RecordAttribute>[
            RecordAttribute(label: 'About', value: 'y'),
            RecordAttribute(label: 'Change', value: 'z'),
          ],
        ),
      ]);
      expect(
        columns.map((column) => column.label).toList(),
        <String>['Change', 'About'],
      );
    });

    test('a list with no records has no columns', () {
      expect(RecordList.columnsOf(const <RecordItem>[]), isEmpty);
    });

    testWidgets('a record that says nothing about a column gets an empty cell', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        _expanded,
        RecordList(
          identityLabel: 'Event',
          items: <RecordItem>[
            _item(
              id: 'a',
              attributes: const <RecordAttribute>[
                RecordAttribute(label: 'Change', value: 'pending to active'),
              ],
            ),
            _item(id: 'b', title: 'Business reviewed'),
          ],
        ),
      );
      // Not a dash, and not the word "unknown": a dash is a value, and "no
      // status change was recorded" is not "the status changed to nothing".
      expect(find.text('pending to active'), findsOne);
      expect(find.text('-'), findsNothing);
      expect(find.text('unknown'), findsNothing);
    });

    testWidgets('one record carrying a label twice is a caller defect', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        _expanded,
        RecordList(
          identityLabel: 'Event',
          items: <RecordItem>[
            _item(
              attributes: const <RecordAttribute>[
                RecordAttribute(label: 'Change', value: 'a to b'),
                RecordAttribute(label: 'Change', value: 'b to c'),
              ],
            ),
          ],
        ),
      );
      expect(tester.takeException(), isAssertionError);
    });
  });

  group('§4.3\'s ActionSet row, including the (>3) in its own name', () {
    test('three or fewer are inline at every band', () {
      // The qualifier in §4.3's row name is honoured rather than ignored: it is
      // the only reading under which §5.2's "on compact, an overflow menu" does
      // not hide a record's single action behind a menu on a phone.
      for (final form in RecordForm.values) {
        for (var count = 0; count <= RecordActionSet.inlineLimit; count++) {
          expect(
            RecordActionSet.inlineCountFor(form, count),
            count,
            reason: '$count actions in $form',
          );
        }
      }
    });

    test('past three, each band takes §4.3\'s own rule', () {
      expect(RecordActionSet.inlineCountFor(RecordForm.stackedCards, 5), 0);
      expect(RecordActionSet.inlineCountFor(RecordForm.twoColumnCards, 5), 3);
      expect(RecordActionSet.inlineCountFor(RecordForm.table, 5), 5);
    });

    testWidgets('a phone puts all five behind one menu', (tester) async {
      await _pumpAt(
        tester,
        _compact,
        RecordList(
          identityLabel: 'Member',
          items: <RecordItem>[_item(actions: _actions(5))],
        ),
      );
      expect(find.byType(AppButton), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsOne);
    });

    testWidgets('a tablet keeps three and overflows the rest', (tester) async {
      await _pumpAt(
        tester,
        _medium,
        RecordList(
          identityLabel: 'Member',
          items: <RecordItem>[_item(actions: _actions(5))],
        ),
      );
      expect(find.byType(AppButton), findsExactly(3));
      expect(find.byIcon(Icons.more_vert), findsOne);
    });

    testWidgets('a desktop window draws all five and no menu', (tester) async {
      await _pumpAt(
        tester,
        _expanded,
        RecordList(
          identityLabel: 'Member',
          items: <RecordItem>[_item(actions: _actions(5))],
        ),
      );
      expect(find.byType(AppButton), findsExactly(5));
      expect(find.byIcon(Icons.more_vert), findsNothing);
    });

    testWidgets('an overflowed action still does what it does', (tester) async {
      final pressed = <String>[];
      await _pumpAt(
        tester,
        _compact,
        RecordList(
          identityLabel: 'Member',
          items: <RecordItem>[
            _item(actions: _actions(5, onPressed: pressed.add)),
          ],
        ),
      );
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Action 4'));
      await tester.pumpAndSettle();
      expect(pressed, <String>['Action 4']);
    });

    testWidgets('an inline action is a 48dp target whatever the band', (
      tester,
    ) async {
      // §5.2's other complaint about the catalog's Correct / Retire pair, and
      // the one §9 makes pass/fail: 20px targets on a touch surface. This
      // component resolves no density, so nothing here may assume a pointer.
      for (final size in <Size>[_compact, _medium, _expanded]) {
        await _pumpAt(
          tester,
          size,
          RecordList(
            identityLabel: 'Member',
            items: <RecordItem>[_item(actions: _actions(1))],
          ),
        );
        expect(
          tester.getSize(find.byKey(const ValueKey<String>('action-0'))).height,
          greaterThanOrEqualTo(_tokens.density.minimumTapTarget.height),
          reason: 'at $size',
        );
      }
    });

    testWidgets('a destructive action does not look like its neighbour', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        _expanded,
        RecordList(
          identityLabel: 'Product',
          items: <RecordItem>[
            _item(
              actions: <RecordAction>[
                RecordAction(label: 'Correct', onPressed: () {}),
                RecordAction(
                  label: 'Retire',
                  destructive: true,
                  onPressed: () {},
                ),
              ],
            ),
          ],
        ),
      );
      final correct = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Correct'),
      );
      final retire = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Retire'),
      );
      expect(correct.tier, AppButtonTier.secondary);
      expect(retire.tier, AppButtonTier.destructive);
    });

    testWidgets('a disabled action in the menu cannot be chosen', (
      tester,
    ) async {
      final pressed = <String>[];
      await _pumpAt(
        tester,
        _compact,
        RecordList(
          identityLabel: 'Member',
          items: <RecordItem>[
            _item(
              actions: <RecordAction>[
                ..._actions(3, onPressed: pressed.add),
                const RecordAction(label: 'Retire', onPressed: null),
              ],
            ),
          ],
        ),
      );
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retire'));
      await tester.pumpAndSettle();
      expect(pressed, isEmpty);
    });
  });

  group('what a record is made of', () {
    testWidgets('every value comes from the token layer', (tester) async {
      await _pumpAt(
        tester,
        _compact,
        RecordList(
          identityLabel: 'Member',
          items: <RecordItem>[
            _item(
              title: 'Amina Odhiambo',
              subtitle: 'amina@example.com',
              attributes: const <RecordAttribute>[
                RecordAttribute(label: 'Role', value: 'manager'),
              ],
              provenance: 'Recorded 2026-08-01 09:00 UTC by You',
            ),
          ],
        ),
      );
      TextStyle styleOf(String text) => tester.widget<Text>(find.text(text)).style!;
      // §5.2's five rows, each in the role the document gives it.
      expect(styleOf('Amina Odhiambo').fontSize, _tokens.typography.titleMedium.fontSize);
      expect(styleOf('Amina Odhiambo').color, _tokens.colors.text.primary);
      expect(styleOf('manager').color, _tokens.colors.text.secondary);
      expect(
        styleOf('Recorded 2026-08-01 09:00 UTC by You').fontSize,
        _tokens.typography.caption.fontSize,
      );
      expect(
        styleOf('Recorded 2026-08-01 09:00 UTC by You').color,
        _tokens.colors.text.tertiary,
      );
      final card = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey<String>('record-r1')),
      );
      final decoration = card.decoration as BoxDecoration;
      expect(decoration.color, _tokens.colors.surface.raised);
      expect(
        (decoration.border! as Border).top.color,
        _tokens.colors.surface.borderSubtle,
      );
      expect(
        decoration.borderRadius,
        BorderRadius.circular(_tokens.radius.md),
      );
    });

    testWidgets('a table header is sentence case in label.md', (tester) async {
      // §2.2 gives `label.md` "chips, tabs, table headers" and permits
      // uppercase on `label.eyebrow` alone, which is the conformance item
      // `DESIGN-AUDIT.md` §4.9 raises against `TenantRecordTable`.
      await _pumpAt(
        tester,
        _expanded,
        RecordList(
          identityLabel: 'Event',
          items: <RecordItem>[
            _item(
              attributes: const <RecordAttribute>[
                RecordAttribute(label: 'Change', value: 'pending to active'),
              ],
            ),
          ],
        ),
      );
      final header = tester.widget<Text>(find.text('Change'));
      expect(header.data, 'Change');
      expect(header.style!.fontSize, _tokens.typography.labelMedium.fontSize);
      expect(header.style!.color, _tokens.colors.text.secondary);
    });

    testWidgets('a table row is at least the density\'s row height', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        _expanded,
        RecordList(
          identityLabel: 'Event',
          items: <RecordItem>[_item(title: 'x')],
        ),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey<String>('record-r1'))).height,
        greaterThanOrEqualTo(_tokens.density.minimumRowHeight),
      );
    });

    testWidgets('a status is a badge, and a record without one has none', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        _compact,
        RecordList(
          identityLabel: 'Event',
          items: <RecordItem>[
            _item(
              id: 'a',
              status: const RecordStatus(
                status: AppStatus.problem,
                label: 'Critical',
              ),
            ),
            _item(id: 'b'),
          ],
        ),
      );
      expect(find.byType(StatusBadge), findsOne);
      expect(find.text('Critical'), findsOne);
    });

    testWidgets('the status leads the record, above its identity', (
      tester,
    ) async {
      // §5.2's "leading position", read as first in the record: it is what a
      // person scans a list of records for.
      await _pumpAt(
        tester,
        _compact,
        RecordList(
          identityLabel: 'Event',
          items: <RecordItem>[
            _item(
              title: 'Staff status set',
              status: const RecordStatus(
                status: AppStatus.problem,
                label: 'Critical',
              ),
            ),
          ],
        ),
      );
      expect(
        tester.getTopLeft(find.byType(StatusBadge)).dy,
        lessThan(tester.getTopLeft(find.text('Staff status set')).dy),
      );
    });

    testWidgets('the status is the first column of a table', (tester) async {
      await _pumpAt(
        tester,
        _expanded,
        RecordList(
          identityLabel: 'Event',
          items: <RecordItem>[
            _item(
              title: 'Staff status set',
              status: const RecordStatus(
                status: AppStatus.problem,
                label: 'Critical',
              ),
            ),
          ],
        ),
      );
      expect(find.text('Status'), findsOne);
      expect(
        tester.getTopLeft(find.byType(StatusBadge)).dx,
        lessThan(tester.getTopLeft(find.text('Staff status set')).dx),
      );
    });

    testWidgets('a table of long status phrases lays out without overflowing', (
      tester,
    ) async {
      // The case that found `StatusBadge`'s constrained-overflow defect: a
      // status column is a share of the row, and §2.1's statuses attract
      // phrases rather than words.
      await _pumpAt(
        tester,
        _expanded,
        RecordList(
          identityLabel: 'Return',
          items: <RecordItem>[
            _item(
              id: 'a',
              status: const RecordStatus(
                status: AppStatus.attention,
                label: 'Awaiting verification',
              ),
              attributes: const <RecordAttribute>[
                RecordAttribute(label: 'Sale', value: 'R-000412'),
                RecordAttribute(label: 'Value', value: 'KES 1,240.00'),
                RecordAttribute(label: 'Lines', value: '3'),
                RecordAttribute(label: 'Reason', value: 'Damaged in transit'),
              ],
              actions: _actions(2),
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a list where nothing has a standing has no status column', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        _expanded,
        RecordList(
          identityLabel: 'Event',
          items: <RecordItem>[_item(id: 'a'), _item(id: 'b')],
        ),
      );
      expect(find.text('Status'), findsNothing);
    });

    testWidgets('an identity gets two lines before it ellipsises', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        _compact,
        RecordList(
          identityLabel: 'Product',
          items: <RecordItem>[
            _item(
              title:
                  'Fresh whole pasteurised milk in a 500 millilitre carton, '
                  'chilled',
            ),
          ],
        ),
      );
      final title = tester.widget<Text>(find.textContaining('Fresh whole'));
      expect(title.maxLines, 2);
      expect(title.overflow, TextOverflow.ellipsis);
    });

    testWidgets('a caller\'s key addresses a record in either form', (
      tester,
    ) async {
      const key = ValueKey<String>('audit-log-entry-aud_001');
      const items = <RecordItem>[
        RecordItem(id: 'aud_001', recordKey: key, title: 'Staff invited'),
      ];
      for (final size in <Size>[_compact, _medium, _expanded]) {
        await _pumpAt(
          tester,
          size,
          const RecordList(identityLabel: 'Event', items: items),
        );
        expect(find.byKey(key), findsOne, reason: 'at $size');
      }
    });
  });

  group('empty', () {
    testWidgets('the caller\'s own words stand in for the rows', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        _compact,
        const RecordList(
          identityLabel: 'Event',
          items: <RecordItem>[],
          empty: Text('No event has been recorded for this business.'),
        ),
      );
      expect(find.text('No event has been recorded for this business.'), findsOne);
    });

    testWidgets('an empty list with nothing to say draws nothing', (
      tester,
    ) async {
      // Not a placeholder and not an invented `EmptyState`: §5.1 has that as
      // its own component and it does not exist yet.
      await _pumpAt(
        tester,
        _expanded,
        const RecordList(identityLabel: 'Event', items: <RecordItem>[]),
      );
      expect(find.text('Event'), findsNothing);
      expect(find.byType(StatusBadge), findsNothing);
    });
  });
}
