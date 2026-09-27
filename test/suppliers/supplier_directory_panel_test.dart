import 'package:flutter/material.dart';
import 'package:uzapay_pos/suppliers/suppliers.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:uzapay_pos/ui/status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/notices.dart';

/// The Suppliers route, from the home tile to a supplier's record.
void main() {
  testWidgets(
    'active suppliers are listed alphabetically, inactive ones on ask',
    (tester) async {
      await _pump(tester, _Reader.seeded());

      expect(_names(tester), <String>['ABC Distributors', 'Mama Njeri Flour']);

      await _choose(
        tester,
        'suppliers-standing-filter',
        'suppliers-standing-all',
      );

      expect(_names(tester), <String>[
        'ABC Distributors',
        'Mama Njeri Flour',
        'XYZ Wholesale',
      ]);
      // The exception wears a badge, the ordinary case does not.
      expect(
        find.byKey(const ValueKey('supplier-inactive-badge-sp_xyz')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('supplier-inactive-badge-sp_abc')),
        findsNothing,
      );
    },
  );

  testWidgets('search narrows the list by name, whatever the case', (
    tester,
  ) async {
    await _pump(tester, _Reader.seeded());

    await tester.enterText(
      find.byKey(const ValueKey('suppliers-search')),
      'FLOUR',
    );
    await tester.pumpAndSettle();

    expect(_names(tester), <String>['Mama Njeri Flour']);
  });

  testWidgets('a business with no suppliers is told what they are for', (
    tester,
  ) async {
    await _pump(tester, _Reader(const <String, Map<String, Object?>>{}));

    expect(find.byKey(const ValueKey('suppliers-empty')), findsOneWidget);
  });

  testWidgets('a supplier is added, queued, and the list read again', (
    tester,
  ) async {
    final reader = _Reader.seeded();
    final writer = _Writer();
    await _pump(tester, reader, writer: writer);
    final readsBefore = reader.reads;

    await tester.tap(find.byKey(const ValueKey('suppliers-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('supplier-form-name')),
      'Fresh Farms',
    );
    await tester.enterText(
      find.byKey(const ValueKey('supplier-form-phone')),
      '0712 000 111',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('supplier-form-submit')));
    await tester.pumpAndSettle();

    final created = writer.created.single;
    expect(created.name, 'Fresh Farms');
    expect(created.documentData()['phone'], '0712 000 111');
    expect(snackNotice(tester).status, AppStatus.ok);
    expect(snackNotice(tester).message, contains('Fresh Farms added'));
    expect(reader.reads, greaterThan(readsBefore));
  });

  testWidgets(
    'a name another supplier already answers to is refused on the form',
    (tester) async {
      final writer = _Writer();
      await _pump(tester, _Reader.seeded(), writer: writer);

      await tester.tap(find.byKey(const ValueKey('suppliers-add')));
      await tester.pumpAndSettle();
      // Inactive, and still the name: its history would split in two.
      await tester.enterText(
        find.byKey(const ValueKey('supplier-form-name')),
        'xyz  wholesale',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('supplier-form-submit')));
      await tester.pumpAndSettle();

      expect(writer.created, isEmpty);
      expect(find.byKey(const ValueKey('supplier-form-error')), findsOneWidget);
      expect(find.textContaining('already has a supplier'), findsOneWidget);
    },
  );

  testWidgets('marking a supplier inactive asks first, then says what it did', (
    tester,
  ) async {
    final writer = _Writer();
    await _pump(tester, _Reader.seeded(), writer: writer);

    await tester.tap(find.byKey(const ValueKey('supplier-actions-sp_abc')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('supplier-inactive-sp_abc')));
    await tester.pumpAndSettle();
    expect(find.textContaining('stays on record'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('supplier-inactive-confirm')));
    await tester.pumpAndSettle();

    expect(writer.updated.single.documentData(), <String, Object?>{
      'active': false,
    });
    expect(snackNotice(tester).message, contains('is inactive'));
  });

  testWidgets('declining the question changes nothing', (tester) async {
    final writer = _Writer();
    await _pump(tester, _Reader.seeded(), writer: writer);

    await tester.tap(find.byKey(const ValueKey('supplier-actions-sp_abc')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('supplier-inactive-sp_abc')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('supplier-inactive-cancel')));
    await tester.pumpAndSettle();

    expect(writer.updated, isEmpty);
  });

  testWidgets('a supplier record states how to reach them, and corrects them', (
    tester,
  ) async {
    final writer = _Writer();
    await _pump(tester, _Reader.seeded(), writer: writer);

    await tester.tap(find.byKey(const ValueKey('supplier-view-sp_abc')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('supplier-record')), findsOneWidget);
    expect(find.text('0712 345 678'), findsOneWidget);
    expect(find.text('orders@abc.example'), findsOneWidget);
    expect(find.text('None yet'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('supplier-record-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('supplier-form-email')),
      '',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('supplier-form-submit')));
    await tester.pumpAndSettle();

    expect(writer.updated.single.documentData(), <String, Object?>{
      'email': null,
    });
  });

  testWidgets('a cashier is not shown the directory', (tester) async {
    await _pump(tester, _Reader.seeded(), role: TenantRole.cashier);

    expect(find.byKey(const ValueKey('supplier-row-sp_abc')), findsNothing);
  });
}

List<String> _names(WidgetTester tester) => <String>[
  for (final element
      in find
          .byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'supplier-name-',
                ),
          )
          .evaluate())
    (element.widget as Text).data!,
];

Future<void> _choose(WidgetTester tester, String select, String item) async {
  await tester.tap(find.byKey(ValueKey(select)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey(item)).last);
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester,
  _Reader reader, {
  TenantSupplierWriter? writer,
  TenantRole role = TenantRole.manager,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = TenantSessionController()
    ..open(uid: 'user-a', membership: _membership(role));
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: TenantSuppliersScreen(
          reader: reader,
          writer: writer ?? _Writer(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

TenantMembership _membership(TenantRole role) => TenantMembership(
  tenantId: 'tenant-a',
  tenantName: 'tenant-a',
  tenantSlug: 'tenant-a',
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

final class _Writer implements TenantSupplierWriter {
  final List<TenantSupplierCreateIntent> created =
      <TenantSupplierCreateIntent>[];
  final List<TenantSupplierUpdateIntent> updated =
      <TenantSupplierUpdateIntent>[];

  @override
  Future<TenantSupplierWriteResult> createSupplier(
    TenantSupplierCreateIntent intent,
  ) async {
    created.add(intent);
    return TenantSupplierWriteResult.queued(
      'supplier-create-${intent.supplierId}',
    );
  }

  @override
  Future<TenantSupplierWriteResult> updateSupplier(
    TenantSupplierUpdateIntent intent,
  ) async {
    updated.add(intent);
    return TenantSupplierWriteResult.queued(intent.operationId);
  }
}

final class _Reader implements TenantDataReader {
  _Reader(this.suppliers);

  factory _Reader.seeded() => _Reader(const <String, Map<String, Object?>>{
    'sp_abc': <String, Object?>{
      'name': 'ABC Distributors',
      'phone': '0712 345 678',
      'email': 'orders@abc.example',
      'active': true,
    },
    'sp_mama': <String, Object?>{'name': 'Mama Njeri Flour', 'active': true},
    'sp_xyz': <String, Object?>{'name': 'XYZ Wholesale', 'active': false},
  });

  final Map<String, Map<String, Object?>> suppliers;
  int reads = 0;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async => null;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    reads++;
    if (!query.collectionPath.endsWith('/suppliers')) {
      return const <TenantQueryDocumentSnapshot>[];
    }
    final ids = suppliers.keys.toList()..sort();
    final cursor = query.startAfterDocumentId;
    return <TenantQueryDocumentSnapshot>[
      for (final id in ids)
        if (cursor == null || id.compareTo(cursor) > 0)
          TenantQueryDocumentSnapshot(
            path: '${query.collectionPath}/$id',
            data: suppliers[id]!,
          ),
    ].take(query.limit).toList();
  }
}
