import 'package:flutter/material.dart';
import 'package:flutter_application_1/theme.dart';
import 'package:flutter_application_1/ui/buttons.dart';
import 'package:flutter_application_1/ui/measure.dart';
import 'package:flutter_application_1/ui/record_list.dart';
import 'package:flutter_application_1/ui/status.dart';
import 'package:flutter_application_1/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

final _tokens = spiritTheme.extension<AppTokens>()!;

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
  Widget? details,
}) => RecordItem(
  id: id,
  title: title,
  subtitle: subtitle,
  status: status,
  attributes: attributes,
  provenance: provenance,
  actions: actions,
  details: details,
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

  group('a form a record opens', () {
    // The one slot here that §5.2 does not name. It arrived with the staff
    // directory, whose five actions each open a form against one member, and
    // it is the component's own addition rather than a specification row - so
    // what these assert is the two rules the component *did* choose: it appears
    // in every form, and it takes the full width beneath the record.

    testWidgets('it is drawn at every band', (tester) async {
      // Not a card-only slot. An action that opens a form on a phone and does
      // nothing visible on a desktop window would be a behaviour that differs
      // by band, which is the opposite of what §4.3 is for.
      for (final size in <Size>[_compact, _medium, _expanded]) {
        await _pumpAt(
          tester,
          size,
          RecordList(
            identityLabel: 'Member',
            items: <RecordItem>[
              _item(details: const Text('Change this member’s role')),
            ],
          ),
        );
        expect(
          find.text('Change this member’s role'),
          findsOne,
          reason: 'at $size',
        );
      }
    });

    testWidgets('only the record that opened one has one', (tester) async {
      await _pumpAt(
        tester,
        _compact,
        RecordList(
          identityLabel: 'Member',
          items: <RecordItem>[
            _item(id: 'a', details: const Text('Change this member’s role')),
            _item(id: 'b'),
          ],
        ),
      );
      expect(find.text('Change this member’s role'), findsOne);
      final form = tester.getRect(find.text('Change this member’s role'));
      final opened = tester.getRect(
        find.byKey(const ValueKey<String>('record-a')),
      );
      final other = tester.getRect(find.byKey(const ValueKey<String>('record-b')));
      // Inside the record that opened it, and above the next one.
      expect(form.top, greaterThan(opened.top));
      expect(form.bottom, lessThanOrEqualTo(opened.bottom));
      expect(form.bottom, lessThanOrEqualTo(other.top));
    });

    testWidgets('it sits below the actions that opened it', (tester) async {
      await _pumpAt(
        tester,
        _expanded,
        RecordList(
          identityLabel: 'Member',
          items: <RecordItem>[
            _item(
              actions: _actions(1),
              details: const Text('Change this member’s role'),
            ),
          ],
        ),
      );
      // A form that appeared between the record and the control that revealed
      // it would push that control down the page as it opened.
      expect(
        tester.getTopLeft(find.text('Change this member’s role')).dy,
        greaterThan(
          tester.getBottomLeft(
            find.byKey(const ValueKey<String>('action-0')),
          ).dy,
        ),
      );
    });

    testWidgets('in a table it takes the row rather than a column', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        _expanded,
        RecordList(
          identityLabel: 'Member',
          items: <RecordItem>[
            _item(
              attributes: const <RecordAttribute>[
                RecordAttribute(label: 'Role', value: 'manager'),
              ],
              actions: _actions(2),
              details: const Text('Change this member’s role'),
            ),
          ],
        ),
      );
      final form = tester.getRect(find.text('Change this member’s role'));
      final identity = tester.getRect(find.text('Fresh whole milk 500ml'));
      // Beneath the cells and starting where the row's content starts: a form
      // is a form, and a column of a table is not where a form goes.
      expect(form.top, greaterThan(identity.bottom));
      expect(form.left, closeTo(identity.left, 0.5));
      expect(form.width, greaterThan(identity.width));
    });

    testWidgets('a table of ordinary rows is unchanged by the slot existing', (
      tester,
    ) async {
      // The regression this could have been. `details` is null on every record
      // in twelve of the thirteen screens step 6 covers, so a row without one
      // has to lay out exactly as it did before the slot was added: the row
      // height is the density's and nothing else.
      await _pumpAt(
        tester,
        _expanded,
        RecordList(
          identityLabel: 'Event',
          items: <RecordItem>[_item(id: 'a', title: 'x'), _item(id: 'b', title: 'y')],
        ),
      );
      final first = tester.getRect(find.byKey(const ValueKey<String>('record-a')));
      final second = tester.getRect(
        find.byKey(const ValueKey<String>('record-b')),
      );
      expect(first.height, _tokens.density.minimumRowHeight);
      expect(second.height, first.height);
    });
  });

  group('a table divides its row by measuring what it holds', () {
    // The four observations `PLAN.md` carried against step 6b's three
    // constants, one group. Every test here names the one it is about, because
    // the arithmetic is one mechanism and the evidence for it is four separate
    // screens.
    //
    // **The strings here are shorter than the ones on the screens they are
    // about, and that is the test font rather than a softened case.** A widget
    // test paints in `FlutterTest`, whose every glyph is one font-size wide, so
    // a 58-character provenance line measures 696 pixels here against roughly
    // 300 in Roboto - wide enough that a fixture copied from a real screen
    // leaves no slack to allocate and every one of these tests would be
    // asserting the over-subscribed case. What is under test is the arithmetic;
    // what the columns come out at on a real screen is what the harness
    // photographs.

    /// The width [RecordTableColumns.resolve] is given on a full-width table at
    /// §4.2's maximum, inside the row's own `space.16` padding.
    const available = 1200.0 - 32;

    RecordTableColumns resolve(
      List<RecordItem> items, {
      double width = available,
      String identityLabel = 'Product',
      TextScaler textScaler = TextScaler.noScaling,
    }) => RecordTableColumns.resolve(
      tokens: _tokens,
      identityLabel: identityLabel,
      columns: RecordList.columnsOf(items),
      items: items,
      available: width,
      textScaler: textScaler,
    );

    double total(RecordTableColumns widths) =>
        (widths.statusWidth ?? 0) +
        widths.identityWidth +
        widths.attributeWidths.fold<double>(0, (sum, w) => sum + w) +
        (widths.actionsWidth ?? 0);

    int cellCount(RecordTableColumns widths) =>
        (widths.statusWidth == null ? 0 : 1) +
        1 +
        widths.attributeWidths.length +
        (widths.actionsWidth == null ? 0 : 1);

    test('the columns and their gutters fill the row exactly', () {
      // The property that makes this safe to put on twelve screens at once:
      // the allocation cannot overflow, at any width, however many columns.
      for (final width in <double>[320, 640, 992, 1168, 2400]) {
        final widths = resolve(<RecordItem>[
          _item(
            id: 'a',
            subtitle: 'Dairy and chilled',
            status: const RecordStatus(status: AppStatus.ok, label: 'In stock'),
            attributes: const <RecordAttribute>[
              RecordAttribute(label: 'Price', value: 'KES 65.00'),
              RecordAttribute(label: 'Code', value: 'MLK-500'),
              RecordAttribute(
                label: 'Reason',
                value: 'Counted short at the close of the Friday shift',
                flex: 2,
              ),
            ],
            provenance: 'Recorded 2026-08-10 08:30 UTC by Grace Wanjiru',
            actions: _actions(4),
          ),
        ], width: width);
        expect(
          total(widths) + widths.gap * (cellCount(widths) - 1),
          closeTo(width, 0.01),
          reason: 'at $width',
        );
      }
    });

    test('a status column is as wide as its widest badge, not a share', () {
      // Observation 2: `web-full/18-manage-catalog` has a standing on two rows
      // of seven, and the column took two shares of the row on all seven - so a
      // catalog read as a wide left margin.
      final items = <RecordItem>[
        _item(
          id: 'a',
          status: const RecordStatus(status: AppStatus.ok, label: 'In stock'),
          attributes: const <RecordAttribute>[
            RecordAttribute(label: 'Price', value: 'KES 65.00'),
          ],
        ),
        _item(id: 'b', title: 'Sugar 1kg'),
      ];
      final widths = resolve(items);
      expect(
        widths.statusWidth,
        closeTo(StatusBadge.measureWidth(_tokens, 'In stock'), 0.01),
      );
      // And it is smaller than the share it used to be given, which is the
      // observation itself rather than a restatement of the line above.
      final share =
          (available - widths.gap * 2) *
          RecordTableColumns.statusShare /
          (RecordTableColumns.statusShare +
              RecordTableColumns.identityShare +
              1);
      expect(widths.statusWidth, lessThan(share));
    });

    test('no column but the identity is given more than it asked for', () {
      // The invariant that makes the whole thing readable: a column of
      // two-character quantities is two characters wide however much room the
      // table has, and the width that would have padded it out goes to the one
      // column that can use it.
      final items = <RecordItem>[
        _item(
          id: 'a',
          title: 'Milk',
          status: const RecordStatus(status: AppStatus.ok, label: 'In stock'),
          attributes: const <RecordAttribute>[
            RecordAttribute(label: 'Qty', value: '18'),
          ],
          actions: _actions(1),
        ),
      ];
      final widths = resolve(items);
      final body = _tokens.density.body(_tokens.typography);
      expect(
        widths.statusWidth,
        closeTo(StatusBadge.measureWidth(_tokens, 'In stock'), 0.01),
      );
      expect(
        widths.attributeWidths.single,
        closeTo(
          measureTextWidth('Qty', _tokens.typography.labelMedium),
          0.01,
        ),
        reason: 'the header is wider than 18, so the header is the demand',
      );
      expect(
        widths.actionsWidth,
        closeTo(
          RecordActionSet.measureWidth(
            _tokens,
            _actions(1),
            RecordForm.table,
          ),
          0.01,
        ),
      );
      expect(
        measureTextWidth('18', body),
        lessThan(widths.attributeWidths.single),
      );
    });

    test('a header too long for its own values keeps the column', () {
      // `Before and after` over `10 to 7` is the stock family's, and a column
      // measured from its values alone would ellipsise its own heading.
      final items = <RecordItem>[
        _item(
          id: 'a',
          attributes: const <RecordAttribute>[
            RecordAttribute(label: 'Before and after', value: '10 to 7'),
          ],
        ),
      ];
      final widths = resolve(items);
      expect(
        widths.attributeWidths.single,
        greaterThanOrEqualTo(
          measureTextWidth('Before and after', _tokens.typography.labelMedium),
        ),
      );
    });

    test('what nobody claimed goes to the identity', () {
      // Something has to absorb the difference, and §5.2's "never truncated
      // below two lines" row is the one column where more room is always worth
      // having.
      final items = <RecordItem>[
        _item(
          id: 'a',
          attributes: const <RecordAttribute>[
            RecordAttribute(label: 'On hand', value: '18'),
          ],
        ),
      ];
      final widths = resolve(items);
      final share =
          (available - widths.gap) *
          RecordTableColumns.identityShare /
          (RecordTableColumns.identityShare + 1);
      expect(widths.identityWidth, greaterThan(share));
    });

    test('an identity wide enough for its provenance line', () {
      // Observation 3: `Recorded 2026-08-10 08:30 UTC by Grace Wanjiru
      // (owner-dev)` wrapped to two lines on every row of
      // `web/23-stock-movements`, because the identity had three shares of a
      // row with four attribute columns and an actions column in it.
      const provenance = 'Recorded 2026-08-10 by Grace';
      final items = <RecordItem>[
        for (var index = 0; index < 3; index++)
          _item(
            id: 'r$index',
            provenance: provenance,
            attributes: const <RecordAttribute>[
              RecordAttribute(label: 'Type', value: 'Sale'),
              RecordAttribute(label: 'Source', value: 'adj-119'),
            ],
          ),
      ];
      expect(
        resolve(items, identityLabel: 'Movement').identityWidth,
        greaterThanOrEqualTo(
          measureTextWidth(provenance, _tokens.typography.caption),
        ),
      );
    });

    test('an action set that fits on one line gets the width to do it', () {
      // Observation 1, as arithmetic. The rendering half is below.
      final actions = _actions(4);
      final items = <RecordItem>[
        _item(
          id: 'a',
          title: 'Faith Njeri',
          attributes: const <RecordAttribute>[
            RecordAttribute(label: 'Role', value: 'cashier'),
          ],
          actions: actions,
        ),
        _item(id: 'b', title: 'Brian Kimani', actions: _actions(2)),
      ];
      final needed = RecordActionSet.measureWidth(
        _tokens,
        actions,
        RecordForm.table,
      );
      final widths = resolve(items, identityLabel: 'Member');
      expect(widths.actionsWidth, greaterThanOrEqualTo(needed));
      // It took more than its own share to get there, which is the half of the
      // repair a constant could not do: three shares of a five-share row is
      // where the four-action record wrapped.
      final share =
          (available - widths.gap * 2) *
          RecordTableColumns.actionsShare /
          (RecordTableColumns.actionsShare +
              RecordTableColumns.identityShare +
              1);
      expect(widths.actionsWidth, greaterThan(share));
    });

    test('the pool fills the shallowest need first', () {
      // The decision most worth arguing with. A column forty pixels short and a
      // column nine hundred short are not two claims of the same kind:
      // satisfying the first removes a wrapped line, and part-satisfying the
      // second removes nothing. Under a share of the pool proportional to what
      // each asked for, `Code` would get a fifteenth of what it needs and
      // `MLK-500` would still wrap after four characters.
      final items = <RecordItem>[
        _item(
          id: 'a',
          title: 'Sugar 1kg',
          attributes: const <RecordAttribute>[
            RecordAttribute(label: 'Qty', value: '18'),
            RecordAttribute(label: 'Code', value: 'MLK-500'),
            RecordAttribute(
              label: 'Reason',
              value:
                  'Counted short at the close of the Friday shift, and '
                  'corrected against the till roll the following morning',
            ),
          ],
        ),
      ];
      final widths = resolve(items, width: 436);
      expect(
        widths.attributeWidths[1],
        greaterThanOrEqualTo(
          measureTextWidth('MLK-500', _tokens.density.body(_tokens.typography)),
        ),
        reason: 'a short claim is satisfied before a long one is topped up',
      );
      // And the deep one still got everything that was left, rather than the
      // pool being held back.
      expect(
        widths.attributeWidths[2],
        greaterThan(widths.attributeWidths[1]),
      );
    });

    test('a caller\'s flex is a ceiling on a column that wants more', () {
      // `RecordAttribute.flex` keeps working and keeps meaning what its call
      // sites set it for: two columns of prose, one twice the other.
      const long =
          'Counted short at the close of the Friday shift, and corrected '
          'against the till roll the following morning by the duty manager';
      final items = <RecordItem>[
        _item(
          id: 'a',
          attributes: const <RecordAttribute>[
            RecordAttribute(label: 'Reason', value: long, flex: 2),
            RecordAttribute(label: 'Evidence', value: long),
          ],
        ),
      ];
      final widths = resolve(items, width: 400);
      expect(widths.attributeWidths[0], greaterThan(widths.attributeWidths[1]));
    });

    test('a column measured at 200% text is wider than at 100%', () {
      // §9 reaches this: a person reading at twice the size has strings twice
      // as wide, and a column measured at one scale ellipsises at the other.
      final items = <RecordItem>[
        _item(
          id: 'a',
          status: const RecordStatus(status: AppStatus.ok, label: 'In stock'),
        ),
      ];
      expect(
        resolve(items, textScaler: const TextScaler.linear(2))
            .statusWidth,
        greaterThan(resolve(items).statusWidth!),
      );
    });

    testWidgets('a record with four actions is as tall as its neighbours', (
      tester,
    ) async {
      // Observation 1, rendered. `web-full/13-staff-directory` had one row
      // three times the height of the three above it, because four actions in
      // a third of the width they need is three runs of 48.
      await _pumpAt(
        tester,
        _expanded,
        RecordList(
          identityLabel: 'Member',
          items: <RecordItem>[
            _item(
              id: 'a',
              title: 'Peter Otieno',
              subtitle: 'peter@devcorner.test',
              attributes: const <RecordAttribute>[
                RecordAttribute(label: 'Role', value: 'admin'),
              ],
              actions: _actions(2),
            ),
            _item(
              id: 'b',
              title: 'Faith Njeri',
              subtitle: 'newhire@devcorner.test',
              attributes: const <RecordAttribute>[
                RecordAttribute(label: 'Role', value: 'cashier'),
              ],
              actions: _actions(4),
            ),
          ],
        ),
      );
      final two = tester.getRect(find.byKey(const ValueKey<String>('record-a')));
      final four = tester.getRect(
        find.byKey(const ValueKey<String>('record-b')),
      );
      // One run, not three, which is the whole of observation 1: the height of
      // a row is the height of its tallest cell, and a wrapped action set makes
      // that cell three buttons deep.
      expect(four.height, two.height);
    });

    testWidgets('two values never meet: there is a gutter between cells', (
      tester,
    ) async {
      // Observation 4. `web/30-shift-corrections` read `A late sale arrived
      // after|Corrected from expectation` across the `Reason` / `Evidence`
      // boundary, and `web/23-stock-movements` did the same in its header row.
      await _pumpAt(
        tester,
        _expanded,
        RecordList(
          identityLabel: 'Correction',
          items: <RecordItem>[
            _item(
              id: 'a',
              attributes: const <RecordAttribute>[
                RecordAttribute(
                  label: 'Reason',
                  value: 'A late sale arrived after the shift was closed',
                  valueKey: ValueKey<String>('reason'),
                ),
                RecordAttribute(
                  label: 'Evidence',
                  value: 'Corrected from expectation, three sales',
                  valueKey: ValueKey<String>('evidence'),
                ),
              ],
            ),
          ],
        ),
      );
      final reason = tester.getRect(find.byKey(const ValueKey<String>('reason')));
      final evidence = tester.getRect(
        find.byKey(const ValueKey<String>('evidence')),
      );
      expect(
        evidence.left - reason.right,
        greaterThanOrEqualTo(_tokens.spacing.s12),
      );
      // The headers too, which is where the stock family's ran together.
      expect(
        tester.getRect(find.text('Evidence')).left -
            tester.getRect(find.text('Reason')).right,
        greaterThanOrEqualTo(_tokens.spacing.s12),
      );
    });

    testWidgets('the header and the rows agree on where a column is', (
      tester,
    ) async {
      // One resolution for the whole table, which is what makes it a table.
      await _pumpAt(
        tester,
        _expanded,
        RecordList(
          identityLabel: 'Product',
          items: <RecordItem>[
            _item(
              id: 'a',
              attributes: const <RecordAttribute>[
                RecordAttribute(
                  label: 'Price',
                  value: 'KES 65.00',
                  valueKey: ValueKey<String>('price-a'),
                ),
              ],
              actions: _actions(2),
            ),
            _item(
              id: 'b',
              title: 'Sugar 1kg',
              attributes: const <RecordAttribute>[
                RecordAttribute(
                  label: 'Price',
                  value: 'KES 180.00',
                  valueKey: ValueKey<String>('price-b'),
                ),
              ],
            ),
          ],
        ),
      );
      final header = tester.getRect(find.text('Price')).left;
      expect(tester.getRect(find.byKey(const ValueKey<String>('price-a'))).left, header);
      expect(tester.getRect(find.byKey(const ValueKey<String>('price-b'))).left, header);
    });

    testWidgets('a six-column table at the narrowest expanded width fits', (
      tester,
    ) async {
      // The width the arithmetic is most likely to fail at: §4.1's
      // `expanded` floor, six columns, a standing and an action set.
      await _pumpAt(
        tester,
        const Size(1024, 900),
        RecordList(
          identityLabel: 'Movement',
          items: <RecordItem>[
            _item(
              id: 'a',
              subtitle: 'Dairy and chilled',
              status: const RecordStatus(
                status: AppStatus.attention,
                label: 'Difference found',
              ),
              provenance:
                  'Recorded 2026-08-10 08:30 UTC by Grace Wanjiru (owner-dev)',
              attributes: const <RecordAttribute>[
                RecordAttribute(label: 'Before and after', value: '24 to 18'),
                RecordAttribute(label: 'Adjustment type', value: 'Sale'),
                RecordAttribute(
                  label: 'Reason',
                  value: 'Sold on receipt R-000482',
                  flex: 2,
                ),
                RecordAttribute(label: 'Source', value: 'sale-000482'),
                RecordAttribute(label: 'On hand', value: '18'),
              ],
              actions: _actions(2),
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
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
