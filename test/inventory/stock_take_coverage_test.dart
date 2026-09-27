import 'package:uzapay_pos/inventory/stock_take_coverage.dart';
import 'package:uzapay_pos/inventory/stock_take_schedule.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:uzapay_pos/ui/status.dart';
import 'package:flutter_test/flutter_test.dart';

const String _tenant = 'tenant-a';
const String _owner = 'owner';

void main() {
  // The artboards' shop: six categories, and a rota with one gap and one
  // category down to somebody who has been deactivated.
  final categories = <TenantCategory>[
    _category('cat-electrical', 'Electrical'),
    _category('cat-fasteners', 'Fasteners'),
    _category('cat-hand-tools', 'Hand tools'),
    _category('cat-paint', 'Paint'),
    _category('cat-plumbing', 'Plumbing'),
    _category('cat-power-tools', 'Power tools'),
  ];
  final staff = <TenantStaffSummary>[
    _member(_owner, 'Asha Mwangi', role: 'owner'),
    _member('st-boniface', 'Boniface Otieno', role: 'admin'),
    _member('st-david', 'David Mutiso', status: 'inactive'),
    _member('st-grace', 'Grace Wanjiru', role: 'manager'),
    _member('st-lydia', 'Lydia Achieng', status: 'pending'),
    _member('st-peter', 'Peter Kamau'),
  ];

  StockTakeCoverage coverageOf(
    List<TenantStockTakeAssignment> rota, {
    TenantStockTakeEnforcement enforcement = TenantStockTakeEnforcement.prompt,
    List<TenantCategory>? catalog,
  }) => StockTakeCoverage.of(
    enforcement: enforcement,
    categories: catalog ?? categories,
    staff: staff,
    assignments: rota,
  );

  final hero = <TenantStockTakeAssignment>[
    _to('st-boniface', 'cat-paint'),
    _to('st-david', 'cat-plumbing'),
    _to('st-grace', 'cat-power-tools'),
    _to('st-lydia', 'cat-electrical'),
    _to('st-peter', 'cat-hand-tools'),
  ];

  test('a category down only to a deactivated person is the one fault', () {
    final coverage = coverageOf(hero);

    expect(coverage.kind, StockTakeCoverageKind.unreachable);
    expect(coverage.status, AppStatus.attention);
    expect(coverage.title, 'Two categories will not be counted');
    expect(
      coverage.message,
      'Nobody is down for Fasteners, and Plumbing is down to David Mutiso, '
      'who is deactivated and cannot sign in to count it.',
    );
    // Lydia has not accepted her invitation yet, and her category still counts:
    // putting a new starter on the rota is a choice, not a fault.
    expect(coverage.countLabel, '4 of 6 categories counted');
    expect(coverage.showsCount, isTrue);
  });

  test('categories nobody is down for are information, not a warning', () {
    final coverage = coverageOf(<TenantStockTakeAssignment>[
      _to('st-boniface', 'cat-paint'),
      _to('st-grace', 'cat-power-tools'),
      _to('st-lydia', 'cat-electrical'),
      _to('st-peter', 'cat-hand-tools'),
    ]);

    expect(coverage.kind, StockTakeCoverageKind.gaps);
    expect(coverage.status, AppStatus.info);
    expect(coverage.title, 'Nobody is down for Fasteners or Plumbing');
    expect(
      coverage.message,
      'They are not counted on any day. The other four categories each have '
      'somebody.',
    );
  });

  test('past two gaps the title counts them and the message names five', () {
    final wide = <TenantCategory>[
      for (final name in <String>[
        'Adhesives',
        'Building',
        'Electrical',
        'Fasteners',
        'Garden',
        'Hand tools',
        'Paint',
        'Plumbing',
        'Power tools',
        'Roofing',
        'Safety wear',
        'Timber',
      ])
        _category('cat-${name.toLowerCase().replaceAll(' ', '-')}', name),
    ];
    final coverage = coverageOf(<TenantStockTakeAssignment>[
      _to('st-boniface', 'cat-adhesives'),
      _to('st-grace', 'cat-building'),
      _to('st-lydia', 'cat-electrical'),
      _to('st-peter', 'cat-hand-tools'),
      _to(_owner, 'cat-paint'),
    ], catalog: wide);

    expect(coverage.title, 'Nobody is down for 7 of 12 categories');
    expect(
      coverage.message,
      'Fasteners, Garden, Plumbing, Power tools, Roofing and 2 more are not '
      'counted on any day.',
    );
  });

  test('somebody who can sign in counting the whole list covers it all', () {
    final coverage = coverageOf(<TenantStockTakeAssignment>[
      _to('st-grace', 'cat-paint'),
      const TenantStockTakeAssignment(uid: 'st-peter'),
    ]);

    expect(coverage.kind, StockTakeCoverageKind.wholeList);
    expect(coverage.status, AppStatus.ok);
    expect(coverage.title, 'Peter Kamau counts the whole list');
    expect(coverage.countLabel, '6 of 6 categories counted');
  });

  test('a deactivated person on the whole list covers none of it', () {
    final coverage = coverageOf(<TenantStockTakeAssignment>[
      const TenantStockTakeAssignment(uid: 'st-david'),
    ], catalog: categories.take(2).toList());

    expect(coverage.kind, StockTakeCoverageKind.unreachable);
    expect(coverage.title, 'Two categories will not be counted');
    expect(
      coverage.message,
      'Electrical and Fasteners are down to David Mutiso, who is deactivated '
      'and cannot sign in to count them.',
    );
  });

  test('every category covered says so, and how many', () {
    final coverage = coverageOf(<TenantStockTakeAssignment>[
      for (final category in categories) _to('st-grace', category.id),
    ]);

    expect(coverage.kind, StockTakeCoverageKind.everyCategory);
    expect(coverage.status, AppStatus.ok);
    expect(coverage.title, 'Every category has somebody counting it');
    expect(
      coverage.message,
      'Each of the 6 categories is down to somebody who can sign in.',
    );
  });

  test('nobody on the rota is a working state, not a warning', () {
    final coverage = coverageOf(const <TenantStockTakeAssignment>[]);

    expect(coverage.kind, StockTakeCoverageKind.nobodyOnRota);
    expect(coverage.status, AppStatus.neutral);
    expect(coverage.showsCount, isFalse);
  });

  test('under Nothing the rota is recorded and nobody is asked', () {
    final coverage = coverageOf(
      hero,
      enforcement: TenantStockTakeEnforcement.off,
    );

    // The deactivated person is not raised: nobody is being asked anything.
    expect(coverage.kind, StockTakeCoverageKind.recordedOnly);
    expect(coverage.status, AppStatus.neutral);
    expect(coverage.showsCount, isFalse);
  });

  test('a catalog with no categories says a count is all or nothing', () {
    final coverage = coverageOf(<TenantStockTakeAssignment>[
      const TenantStockTakeAssignment(uid: 'st-peter'),
    ], catalog: const <TenantCategory>[]);

    expect(coverage.kind, StockTakeCoverageKind.noCategories);
    expect(coverage.showsCount, isFalse);
  });

  test('somebody past the staff page is not assumed to be a fault', () {
    // The screen reads one bounded page of staff. A person it does not hold is
    // of unknown standing, and unknown is not deactivated.
    final coverage = coverageOf(<TenantStockTakeAssignment>[
      for (final category in categories) _to('st-unseen', category.id),
    ]);

    expect(coverage.kind, StockTakeCoverageKind.everyCategory);
  });

  test('an assignment to a category not listed here covers nothing listed', () {
    final coverage = coverageOf(<TenantStockTakeAssignment>[
      _to('st-grace', 'cat-gone'),
      for (final category in categories.skip(1)) _to('st-peter', category.id),
    ]);

    expect(coverage.kind, StockTakeCoverageKind.gaps);
    expect(coverage.uncovered, <String>['Electrical']);
    expect(
      coverage.message,
      'It is not counted on any day. The other five categories each have '
      'somebody.',
    );
  });
}

TenantStockTakeAssignment _to(String uid, String categoryId) =>
    TenantStockTakeAssignment(uid: uid, categoryId: categoryId);

TenantCategory _category(String id, String name) => TenantCategory.fromSnapshot(
  TenantQueryDocumentSnapshot(
    path: 'tenants/$_tenant/categories/$id',
    data: <String, Object?>{'name': name},
  ),
);

TenantStaffSummary _member(
  String uid,
  String name, {
  String role = 'cashier',
  String status = 'active',
}) => TenantStaffSummary.fromSnapshot(
  TenantQueryDocumentSnapshot(
    path: 'tenants/$_tenant/staff/$uid',
    data: <String, Object?>{
      'uid': uid,
      'email': '$uid@shop.test',
      'name': name,
      'role': role,
      'status': status,
      'invitationStatus': status == 'pending' ? 'pending' : 'accepted',
    },
  ),
  ownerUid: _owner,
);
