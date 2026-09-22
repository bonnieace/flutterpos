import 'dart:ui' show CheckedState, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/checkout/checkout_configuration_writer.dart';
import 'package:flutter_application_1/inventory/stock_take_settings_panel.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/collection_pages.dart';
import '../support/notices.dart';

const String _tenant = 'tenant-a';
const String _owner = 'owner';
const String _root = 'tenants/$_tenant';
const String _schedulePath = '$_root/configuration/stock_take';

/// The artboards' shop, as `docs/design/stock-counts/` draws it.
const Map<String, String> _categories = <String, String>{
  'cat-electrical': 'Electrical',
  'cat-fasteners': 'Fasteners',
  'cat-hand-tools': 'Hand tools',
  'cat-paint': 'Paint',
  'cat-plumbing': 'Plumbing',
  'cat-power-tools': 'Power tools',
};

final Map<String, Map<String, Object?>> _staff = <String, Map<String, Object?>>{
  _owner: _member(_owner, 'Asha Mwangi', role: 'owner'),
  'st-boniface': _member('st-boniface', 'Boniface Otieno', role: 'admin'),
  'st-david': _member('st-david', 'David Mutiso', status: 'inactive'),
  'st-grace': _member('st-grace', 'Grace Wanjiru', role: 'manager'),
  'st-lydia': _member('st-lydia', 'Lydia Achieng', status: 'pending'),
  'st-njeri': _member('st-njeri', 'Njeri Kariuki', status: 'pending'),
  'st-peter': _member('st-peter', 'Peter Kamau'),
  'st-samuel': _member('st-samuel', 'Samuel Ochieng', status: 'pending'),
};

const Map<String, Object?> _heroSchedule = <String, Object?>{
  'enforcement': 'prompt',
  'weekdays': <int>[DateTime.monday, DateTime.thursday],
  'assignments': <Map<String, Object?>>[
    <String, Object?>{'uid': 'st-boniface', 'categoryId': 'cat-paint'},
    <String, Object?>{'uid': 'st-david', 'categoryId': 'cat-plumbing'},
    <String, Object?>{'uid': 'st-grace', 'categoryId': 'cat-power-tools'},
    <String, Object?>{'uid': 'st-lydia', 'categoryId': 'cat-electrical'},
    <String, Object?>{'uid': 'st-peter', 'categoryId': 'cat-hand-tools'},
  ],
  'updatedBy': _owner,
};

void main() {
  testWidgets('the published rota is read back, category by category', (
    tester,
  ) async {
    await _pump(tester, _Reader(schedule: _heroSchedule), writer: _Writer());

    expect(_checked(tester, 'stock-take-enforcement-prompt'), isTrue);
    expect(_checked(tester, 'stock-take-enforcement-block'), isFalse);
    expect(_toggled(tester, 'stock-take-weekday-${DateTime.monday}'), isTrue);
    expect(_toggled(tester, 'stock-take-weekday-${DateTime.tuesday}'), isFalse);

    // Every consequence is on screen at once, not only the selected one's.
    expect(find.textContaining('cannot sell until'), findsOneWidget);
    expect(find.textContaining('may carry on selling'), findsOneWidget);

    expect(_selected(tester, 'st-peter'), 'Hand tools');
    expect(_selected(tester, _owner), 'Not counting');

    final coverage = noticeAt(tester, 'stock-take-coverage');
    expect(coverage.status, AppStatus.attention);
    expect(coverage.title, 'Two categories will not be counted');
    expect(
      coverage.message,
      'Nobody is down for Fasteners, and Plumbing is down to David Mutiso, '
      'who is deactivated and cannot sign in to count it.',
    );
    expect(
      _text(tester, 'stock-take-coverage-count'),
      '4 of 6 categories counted',
    );

    expect(
      _noteText(tester, 'st-david'),
      'Never asked - cannot sign in',
      reason: 'the one row that is a fault says so',
    );
    expect(
      _noteText(tester, 'st-lydia'),
      'Asked once they accept the invitation',
    );
    expect(
      find.byKey(const ValueKey('stock-take-note-st-samuel')),
      findsNothing,
      reason: 'an invited person nobody has put on the rota needs no note',
    );
  });

  testWidgets('choosing a card and saving publishes that choice', (
    tester,
  ) async {
    final writer = _Writer();
    await _pump(tester, _Reader(schedule: _heroSchedule), writer: writer);

    await tester.tap(
      find.byKey(const ValueKey('stock-take-enforcement-block')),
    );
    await tester.pump();
    expect(_checked(tester, 'stock-take-enforcement-block'), isTrue);

    await _save(tester);

    expect(writer.merges.single.path, _schedulePath);
    expect(writer.merges.single.data['enforcement'], 'block');
    expect(snackNotice(tester).status, AppStatus.ok);
  });

  testWidgets('a day toggles and is published with the rest', (tester) async {
    final writer = _Writer();
    await _pump(tester, _Reader(schedule: _heroSchedule), writer: writer);

    await tester.tap(
      find.byKey(ValueKey('stock-take-weekday-${DateTime.tuesday}')),
    );
    await tester.pump();
    expect(_toggled(tester, 'stock-take-weekday-${DateTime.tuesday}'), isTrue);

    await _save(tester);

    expect(writer.merges.single.data['weekdays'], <int>[1, 2, 4]);
  });

  testWidgets('choosing what a person counts moves the coverage line at once', (
    tester,
  ) async {
    final writer = _Writer();
    await _pump(tester, _Reader(schedule: _heroSchedule), writer: writer);

    await _choose(tester, 'st-grace', 'cat-fasteners');

    expect(_selected(tester, 'st-grace'), 'Fasteners');
    // Before Save: the line reads the rota as drawn.
    expect(
      noticeAt(tester, 'stock-take-coverage').title,
      'Two categories will not be counted',
    );
    expect(
      noticeAt(tester, 'stock-take-coverage').message,
      'Nobody is down for Power tools, and Plumbing is down to David Mutiso, '
      'who is deactivated and cannot sign in to count it.',
    );

    await _choose(tester, 'st-david', 'none');
    await _choose(tester, 'st-peter', 'all');

    expect(
      noticeAt(tester, 'stock-take-coverage').title,
      'Peter Kamau counts the whole list',
    );
    expect(
      find.byKey(const ValueKey('stock-take-note-st-david')),
      findsNothing,
      reason: 'off the rota, a deactivated person is no longer a fault',
    );

    await _save(tester);

    final assignments =
        (writer.merges.single.data['assignments']! as List<Object?>)
            .cast<Map<String, Object?>>();
    expect(
      assignments,
      containsAll(<Map<String, Object?>>[
        <String, Object?>{'uid': 'st-grace', 'categoryId': 'cat-fasteners'},
        <String, Object?>{'uid': 'st-peter'},
      ]),
    );
    expect(
      assignments.where((a) => a['uid'] == 'st-david'),
      isEmpty,
      reason: 'Not counting is the absence of an assignment',
    );
  });

  testWidgets('a category this screen cannot list is shown and kept', (
    tester,
  ) async {
    // A `DropdownButton` asserts on a value no item carries, so this is the
    // record that would throw if the select did not carry it.
    final writer = _Writer();
    await _pump(
      tester,
      _Reader(
        schedule: <String, Object?>{
          ..._heroSchedule,
          'assignments': <Map<String, Object?>>[
            <String, Object?>{'uid': 'st-boniface', 'categoryId': 'cat-gone'},
          ],
        },
      ),
      writer: writer,
    );

    expect(tester.takeException(), isNull);
    expect(_selected(tester, 'st-boniface'), unlistedTenantCategoryLabel);
    expect(_noteText(tester, 'st-boniface'), 'Kept as it is when you save');

    await tester.tap(
      find.byKey(ValueKey('stock-take-weekday-${DateTime.friday}')),
    );
    await tester.pump();
    await _save(tester);

    expect(writer.merges.single.data['assignments'], <Map<String, Object?>>[
      <String, Object?>{'uid': 'st-boniface', 'categoryId': 'cat-gone'},
    ]);
  });

  testWidgets('a person listed twice is told which listing saving drops', (
    tester,
  ) async {
    await _pump(
      tester,
      _Reader(
        schedule: <String, Object?>{
          ..._heroSchedule,
          'assignments': <Map<String, Object?>>[
            <String, Object?>{'uid': 'st-peter', 'categoryId': 'cat-fasteners'},
            <String, Object?>{
              'uid': 'st-peter',
              'categoryId': 'cat-hand-tools',
            },
          ],
        },
      ),
      writer: _Writer(),
    );

    // The form keeps the last listing, so the first is the one saving drops.
    expect(_selected(tester, 'st-peter'), 'Hand tools');
    expect(
      _noteText(tester, 'st-peter'),
      'Also listed for Fasteners - saving drops it',
    );
    expect(
      find.byKey(const ValueKey('stock-take-settings-simplified')),
      findsOneWidget,
    );
  });

  testWidgets('a build that cannot write draws answers, not controls', (
    tester,
  ) async {
    await _pump(tester, _Reader(schedule: _heroSchedule));

    expect(
      noticeAt(tester, 'stock-take-settings-read-only').status,
      AppStatus.info,
    );
    // Only the chosen card, and no radio group to press.
    expect(find.text('Ask at the register'), findsOneWidget);
    expect(find.text('Hold the register'), findsNothing);
    expect(_text(tester, 'stock-take-days-as-set'), 'Monday and Thursday');
    expect(
      find.byKey(const ValueKey('stock-take-assign-st-peter')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('stock-take-assigned-st-peter')),
        matching: find.text('Hand tools'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('stock-take-settings-save')),
      findsNothing,
    );
  });

  testWidgets('more people than one page holds are said to exist', (
    tester,
  ) async {
    final crowd = <String, Map<String, Object?>>{
      _owner: _member(_owner, 'Asha Mwangi', role: 'owner'),
      for (var i = 0; i < 24; i++)
        'st-${i.toString().padLeft(2, '0')}': _member(
          'st-${i.toString().padLeft(2, '0')}',
          'Person $i',
        ),
    };
    await _pump(tester, _Reader(staff: crowd), writer: _Writer());

    expect(
      noticeMessage(tester, 'stock-take-staff-truncated'),
      startsWith('The first 20 people are listed.'),
    );
  });

  testWidgets('with nothing published nobody is on the rota', (tester) async {
    await _pump(tester, _Reader(), writer: _Writer());

    expect(_checked(tester, 'stock-take-enforcement-off'), isTrue);
    final coverage = noticeAt(tester, 'stock-take-coverage');
    expect(coverage.status, AppStatus.neutral);
    expect(coverage.title, 'Nobody is on the rota');
    expect(
      find.byKey(const ValueKey('stock-take-coverage-count')),
      findsNothing,
    );
  });

  testWidgets('on a phone the choice sits under the name, not beside it', (
    tester,
  ) async {
    await _pump(
      tester,
      _Reader(schedule: _heroSchedule),
      writer: _Writer(),
      size: const Size(411, 2600),
    );

    final name = tester.getRect(find.text('Samuel Ochieng'));
    final select = tester.getRect(
      find.byKey(const ValueKey('stock-take-assign-st-samuel')),
    );
    expect(select.top, greaterThan(name.bottom));
    // And every choice is on the screen: nothing scrolls sideways any more.
    final hold = tester.getRect(
      find.byKey(const ValueKey('stock-take-enforcement-block')),
    );
    expect(hold.right, lessThanOrEqualTo(411));
  });
}

// ---------------------------------------------------------------------------

Future<void> _pump(
  WidgetTester tester,
  _Reader reader, {
  TenantConfigurationDocumentWriter? writer,
  Size size = const Size(1280, 2600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: TenantSessionController()
          ..open(uid: _owner, membership: _membership()),
        child: Scaffold(
          body: SingleChildScrollView(
            child: TenantStockTakeSettingsPanel(reader: reader, writer: writer),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _save(WidgetTester tester) async {
  final save = find.byKey(const ValueKey('stock-take-settings-save'));
  await tester.ensureVisible(save);
  await tester.tap(save);
  await tester.pump();
  await tester.pump();
}

/// Opens one person's select and picks [suffix]: `none`, `all`, or a category.
Future<void> _choose(WidgetTester tester, String uid, String suffix) async {
  final select = find.byKey(ValueKey('stock-take-assign-$uid'));
  await tester.ensureVisible(select);
  await tester.tap(select);
  await tester.pumpAndSettle();
  // The open menu draws its own copy of every item; the last is the menu's.
  // It lays each one under the menu's own ink layer, which answers the tap -
  // so the hit lands on an ancestor of the keyed item, and that is the point.
  await tester.tap(
    find.byKey(ValueKey('stock-take-assign-$uid-$suffix')).last,
    warnIfMissed: false,
  );
  await tester.pumpAndSettle();
}

bool _checked(WidgetTester tester, String key) =>
    tester
        .getSemantics(find.byKey(ValueKey(key)))
        .getSemanticsData()
        .flagsCollection
        .isChecked ==
    CheckedState.isTrue;

bool _toggled(WidgetTester tester, String key) =>
    tester
        .getSemantics(find.byKey(ValueKey(key)))
        .getSemanticsData()
        .flagsCollection
        .isToggled ==
    Tristate.isTrue;

String? _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data;

/// The label the select is showing for [uid], read from its closed button.
String _selected(WidgetTester tester, String uid) {
  final button = tester.widget<DropdownButton<String>>(
    find.descendant(
      of: find.byKey(ValueKey('stock-take-assign-$uid')),
      matching: find.byType(DropdownButton<String>),
    ),
  );
  final item = button.items!.firstWhere((item) => item.value == button.value);
  return (item.child as Text).data!;
}

String _noteText(WidgetTester tester, String uid) {
  final texts = tester.widgetList<Text>(
    find.descendant(
      of: find.byKey(ValueKey('stock-take-note-$uid')),
      matching: find.byType(Text),
    ),
  );
  return texts.single.data!;
}

Map<String, Object?> _member(
  String uid,
  String name, {
  String role = 'cashier',
  String status = 'active',
}) => <String, Object?>{
  'uid': uid,
  'email': '$uid@shop.test',
  'name': name,
  'role': role,
  'status': status,
  'invitationStatus': status == 'pending' ? 'pending' : 'accepted',
};

TenantMembership _membership() => TenantMembership(
  tenantId: _tenant,
  tenantName: _tenant,
  tenantSlug: _tenant,
  role: TenantRole.owner,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  isOwner: true,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 8, 1),
  updatedAt: DateTime.utc(2026, 8, 1),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);

final class _Merge {
  const _Merge(this.path, this.data);

  final String path;
  final Map<String, Object?> data;
}

final class _Writer implements TenantConfigurationDocumentWriter {
  final List<_Merge> merges = <_Merge>[];

  @override
  Future<TenantConfigurationWriteResult> merge({
    required String path,
    required Map<String, Object?> data,
  }) async {
    merges.add(_Merge(path, data));
    return const TenantConfigurationWriteResult.committed();
  }
}

final class _Reader implements TenantDataReader {
  _Reader({this.schedule, Map<String, Map<String, Object?>>? staff})
    : staff = staff ?? _staff;

  final Map<String, Object?>? schedule;
  final Map<String, Map<String, Object?>> staff;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    final Map<String, Object?>? data = switch (path) {
      _root => <String, Object?>{
        'tenantId': _tenant,
        'name': _tenant,
        'status': 'active',
        'ownerUid': _owner,
      },
      _schedulePath => schedule,
      _ when path.startsWith('$_root/staff/') => staff[path.split('/').last],
      _ => null,
    };
    return data == null ? null : TenantDocumentSnapshot(path: path, data: data);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    final documents = switch (query.collectionPath) {
      '$_root/staff' => <TenantQueryDocumentSnapshot>[
        for (final entry in staff.entries)
          TenantQueryDocumentSnapshot(
            path: '$_root/staff/${entry.key}',
            data: entry.value,
          ),
      ],
      '$_root/categories' => <TenantQueryDocumentSnapshot>[
        for (final entry in _categories.entries)
          TenantQueryDocumentSnapshot(
            path: '$_root/categories/${entry.key}',
            data: <String, Object?>{'name': entry.value},
          ),
      ],
      _ => const <TenantQueryDocumentSnapshot>[],
    };
    return tenantCollectionPageOf(query, documents);
  }
}
