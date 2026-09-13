import 'package:flutter/material.dart';
import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/inventory/inventory.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/buttons.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/notices.dart';

/// The counting screen.
///
/// **The first test is the feature.** A count is worth taking only if the person
/// taking it cannot see the answer, so "no expected figure appears anywhere" is
/// not a cosmetic assertion - it is the control, and it is asserted as an
/// absence because that is the only way to assert it.
void main() {
  testWidgets('the screen never shows what the books hold', (tester) async {
    // Every product below holds a distinctive quantity. None of those numbers
    // may be on screen: seeing the target tells a counter what to write, which
    // is exactly what a blind count exists to prevent.
    final drafts = _Drafts();
    await _pump(tester, drafts: drafts);

    expect(find.byKey(const ValueKey('stock-take-line-pd-1')), findsOneWidget);
    expect(find.text('White bread loaf'), findsOneWidget);
    for (final held in <String>['40', '7', '112']) {
      expect(
        find.text(held),
        findsNothing,
        reason: 'the quantity $held is the figure the count is blind to',
      );
    }
  });

  testWidgets('what the device believed is recorded without being shown', (
    tester,
  ) async {
    // The other half of it: blind to the person, not to the record. The figure
    // travels so the window between counting and handing in stays legible to
    // somebody entitled to see both.
    final drafts = _Drafts();
    await _pump(tester, drafts: drafts);

    await _count(tester, 'pd-1', '38');

    expect(drafts.saved.last.counts['pd-1']!.counted, 38);
    expect(drafts.saved.last.counts['pd-1']!.seenQuantity, 40);
  });

  testWidgets('every number typed is durable before anything is sent', (
    tester,
  ) async {
    // The case this exists for: the app is killed mid-aisle, an hour in.
    final drafts = _Drafts();
    await _pump(tester, drafts: drafts);

    await _count(tester, 'pd-1', '38');
    await _count(tester, 'pd-2', '7');

    expect(drafts.saved, hasLength(2));
    expect(drafts.saved.last.counts.keys, <String>{'pd-1', 'pd-2'});
    expect(drafts.saved.last.takeId, startsWith('st_'));
  });

  testWidgets('an emptied box is not a count of zero', (tester) async {
    // **The distinction the whole model rests on.** Clearing a field must take
    // the line out, or "I did not get to it" silently becomes "the shelf was
    // bare" - and the second is a variance somebody will be asked about.
    final drafts = _Drafts();
    await _pump(tester, drafts: drafts);

    await _count(tester, 'pd-1', '38');
    expect(drafts.saved.last.counts.containsKey('pd-1'), isTrue);

    await _count(tester, 'pd-1', '');
    expect(drafts.saved.last.counts.containsKey('pd-1'), isFalse);

    // While a zero typed deliberately is kept.
    await _count(tester, 'pd-1', '0');
    expect(drafts.saved.last.counts['pd-1']!.counted, 0);
  });

  testWidgets('nothing can be handed in until something is counted', (
    tester,
  ) async {
    final drafts = _Drafts();
    await _pump(tester, drafts: drafts);

    expect(
      tester
          .widget<AppButton>(find.byKey(const ValueKey('stock-take-submit')))
          .onPressed,
      isNull,
    );

    await _count(tester, 'pd-1', '38');
    expect(
      tester
          .widget<AppButton>(find.byKey(const ValueKey('stock-take-submit')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('handing in queues every page and clears the draft', (
    tester,
  ) async {
    final drafts = _Drafts();
    final writer = _Writer();
    var submitted = 0;
    await _pump(
      tester,
      drafts: drafts,
      writer: writer,
      onSubmitted: () => submitted++,
    );

    await _count(tester, 'pd-1', '38');
    await _count(tester, 'pd-2', '7');
    await _handIn(tester);

    expect(writer.pages, hasLength(1));
    expect(writer.pages.single.lines, hasLength(2));
    expect(writer.pages.single.isFinalPage, isTrue);
    expect(writer.pages.single.productsInScope, 3);
    // The draft is gone, so re-entering the screen starts a new count rather
    // than offering the one that was handed in.
    expect(drafts.cleared, 1);
    expect(submitted, 1);
    expect(snackNotice(tester).message, contains('2 products recorded'));
  });

  testWidgets('the question before handing in names what is being left out', (
    tester,
  ) async {
    // A count with half the shelf blank is not wrong - somebody may have been
    // asked for one aisle - but nothing downstream can tell "not counted" from
    // "not counted yet", so it is worth being sure about.
    final drafts = _Drafts();
    final writer = _Writer();
    await _pump(tester, drafts: drafts, writer: writer);

    await _count(tester, 'pd-1', '38');
    await tester.tap(find.byKey(const ValueKey('stock-take-submit')));
    await tester.pumpAndSettle();

    expect(find.textContaining('left 2 without a number'), findsOneWidget);
    expect(
      find.textContaining('not as none on the shelf'),
      findsOneWidget,
      reason: 'the sentence that stops an empty box becoming a claim',
    );
    expect(writer.pages, isEmpty, reason: 'nothing is sent until it is answered');
  });

  testWidgets('a count resumes where it was left, on the same day', (
    tester,
  ) async {
    final drafts = _Drafts(
      existing: _draft(
        counts: <String, TenantStockTakeCount>{
          'pd-1': TenantStockTakeCount(
            counted: 22,
            seenQuantity: 40,
            countedAt: DateTime.utc(2026, 9, 13, 7),
          ),
        },
      ),
    );
    await _pump(tester, drafts: drafts);

    // The field is repopulated, so the person sees what they already wrote.
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('stock-take-line-pd-1')),
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text,
      '22',
    );
  });

  testWidgets('yesterday\'s unfinished count is not today\'s', (tester) async {
    // A half-finished count belongs to the day it was taken for. Resuming it
    // into today would file yesterday's shelf as today's.
    final drafts = _Drafts(
      existing: _draft(
        businessDate: '2026-09-12',
        counts: <String, TenantStockTakeCount>{
          'pd-1': TenantStockTakeCount(
            counted: 22,
            seenQuantity: 40,
            countedAt: DateTime.utc(2026, 9, 12, 7),
          ),
        },
      ),
    );
    await _pump(tester, drafts: drafts);

    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('stock-take-line-pd-1')),
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('a device that has never synced says so rather than showing none', (
    tester,
  ) async {
    await _pump(tester, catalog: const _Catalog.empty());

    expect(
      find.byKey(const ValueKey('stock-take-no-catalog')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('stock-take-submit')), findsNothing);
  });

  testWidgets('counting one category leaves the rest of the shelf alone', (
    tester,
  ) async {
    final drafts = _Drafts();
    await _pump(
      tester,
      drafts: drafts,
      scope: const TenantStockTakeCategory('cat-bakery'),
    );

    expect(find.byKey(const ValueKey('stock-take-line-pd-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('stock-take-line-pd-2')), findsNothing);
    expect(find.byKey(const ValueKey('stock-take-line-pd-3')), findsNothing);
  });
}

Future<void> _count(WidgetTester tester, String productId, String value) async {
  await tester.enterText(
    find.descendant(
      of: find.byKey(ValueKey('stock-take-line-$productId')),
      matching: find.byType(TextField),
    ),
    value,
  );
  await tester.pumpAndSettle();
}

Future<void> _handIn(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('stock-take-submit')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('stock-take-confirm')));
  await tester.pumpAndSettle();
}

TenantStockTakeDraft _draft({
  String businessDate = '2026-09-13',
  Map<String, TenantStockTakeCount> counts =
      const <String, TenantStockTakeCount>{},
}) => TenantStockTakeDraft(
  takeId: 'st_${'a' * 40}',
  tenantId: 'tenant-a',
  businessDate: businessDate,
  scope: const TenantStockTakeEverything(),
  productsInScope: 3,
  startedAt: DateTime.utc(2026, 9, 13, 6),
  counts: counts,
);

Future<void> _pump(
  WidgetTester tester, {
  _Drafts? drafts,
  _Writer? writer,
  CheckoutCatalogSource catalog = const _Catalog(),
  TenantStockTakeScope scope = const TenantStockTakeEverything(),
  VoidCallback? onSubmitted,
}) async {
  tester.view.physicalSize = const Size(1400, 3600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: TenantSessionController()..open(
          uid: 'user-cashier',
          membership: _membership(),
        ),
        child: Scaffold(
          body: TenantStockTakePanel(
            catalog: catalog,
            drafts: drafts ?? _Drafts(),
            writer: writer ?? _Writer(),
            scope: scope,
            onSubmitted: onSubmitted,
            businessDate: () => '2026-09-13',
            requestIdFactory: () => 'stocktake-fixed',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

TenantMembership _membership({TenantRole role = TenantRole.cashier}) =>
    TenantMembership(
      tenantId: 'tenant-a',
      tenantName: 'tenant-a',
      tenantSlug: 'tenant-a',
      role: role,
      membershipStatus: MembershipStatus.active,
      tenantStatus: TenantStatus.active,
      isOwner: false,
      mirrorVersion: 1,
      createdAt: DateTime.utc(2026, 8, 1),
      updatedAt: DateTime.utc(2026, 8, 1),
      serverCanAccess: true,
      canonicalTenantExists: true,
      canonicalMembershipExists: true,
    );

TenantProduct _product({
  required String id,
  required String name,
  required String sku,
  required int quantity,
  required String categoryId,
}) => TenantProduct.fromDocument(
  path: 'tenants/tenant-a/products/$id',
  data: <String, Object?>{
    'name': name,
    'SKU': sku,
    'price': 65,
    'quantity': quantity,
    'categoryId': categoryId,
  },
);

/// Three products, each holding a number that must never reach the screen.
final class _Catalog implements CheckoutCatalogSource {
  const _Catalog() : _empty = false;
  const _Catalog.empty() : _empty = true;

  final bool _empty;

  @override
  Future<CheckoutCatalogSnapshot?> read({
    required String uid,
    required String tenantId,
  }) async {
    if (_empty) return null;
    return CheckoutCatalogSnapshot.forTesting(
      uid: uid,
      tenantId: tenantId,
      refreshedAt: DateTime.utc(2026, 9, 13, 5),
      configuration: TenantCheckoutConfiguration.fromMap(
        const <String, Object?>{'currency': 'KES'},
      ),
      products: <TenantProduct>[
        _product(
          id: 'pd-1',
          name: 'White bread loaf',
          sku: '6161100000019',
          quantity: 40,
          categoryId: 'cat-bakery',
        ),
        _product(
          id: 'pd-2',
          name: 'Cola 500ml',
          sku: 'CL500',
          quantity: 7,
          categoryId: 'cat-drinks',
        ),
        _product(
          id: 'pd-3',
          name: 'Zebra crisps',
          sku: 'ZC001',
          quantity: 112,
          categoryId: 'cat-drinks',
        ),
      ],
    );
  }
}

final class _Drafts implements TenantStockTakeDraftSource {
  _Drafts({TenantStockTakeDraft? existing}) : _existing = existing;

  TenantStockTakeDraft? _existing;
  final List<TenantStockTakeDraft> saved = <TenantStockTakeDraft>[];
  int cleared = 0;

  @override
  TenantStockTakeDraft? draftFor({
    required String uid,
    required String tenantId,
  }) => _existing;

  @override
  Future<void> save({
    required String uid,
    required TenantStockTakeDraft draft,
  }) async {
    saved.add(draft);
    _existing = draft;
  }

  @override
  Future<void> clear({required String uid, required String tenantId}) async {
    cleared++;
    _existing = null;
  }
}

final class _Writer implements TenantStockTakeWriter {
  final List<TenantStockTakePageIntent> pages = <TenantStockTakePageIntent>[];

  @override
  Future<TenantStockTakeWriteResult> submitPage(
    TenantStockTakePageIntent intent,
  ) async {
    pages.add(intent);
    return TenantStockTakeWriteResult.queued(intent.operationId);
  }
}
