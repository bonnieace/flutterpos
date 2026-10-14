import 'package:flutter/material.dart';
import 'package:uzapay_pos/inventory/inventory.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:uzapay_pos/ui/status.dart';
import 'package:flutter_test/flutter_test.dart';

/// The management side of a stock take.
///
/// **Two of these are device findings.** The list shipped reading a raw UID for
/// anybody but the viewer, and shipped as a bare `Column` that overflowed the
/// moment a third count existed. Neither was visible in a unit test because
/// there was no widget test over this panel at all; this file is it. The rest
/// pin where a count is started from, which moved here on 2026-09-13.
void main() {
  testWidgets('a count says who counted it, by name', (tester) async {
    // The manager this screen exists for knows their staff by name. A UID is
    // the identity every other record is attributed by, so it stays visible -
    // but it cannot be the whole of the label.
    //
    // **On the cards, at 800**, where the label is one string: from 1024 the
    // table sets the UID on its own line under the name, which the group
    // below asserts.
    tester.view.physicalSize = const Size(800, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pump(tester, server: _server(), sizeViewport: false);

    expect(find.textContaining('Wamweki Njoroge'), findsOneWidget);
    expect(
      find.text('staff-cashier'),
      findsNothing,
      reason: 'a resolvable name must not leave a bare UID on screen',
    );
  });

  testWidgets('the viewer is named as themselves, not as a UID', (
    tester,
  ) async {
    await _pump(tester, server: _server());

    expect(find.textContaining('You'), findsOneWidget);
  });

  testWidgets('an unresolvable counter degrades to the UID, never to blank', (
    tester,
  ) async {
    // A staff record can be missing, denied or malformed. The label is a
    // convenience; losing it must not lose who the count belongs to.
    final server = _server()..staff.remove('staff-cashier');
    await _pump(tester, server: server);

    expect(find.textContaining('staff-cashier'), findsOneWidget);
  });

  testWidgets('a count is started from the screen that records counts', (
    tester,
  ) async {
    // The act, on the page holding its record: since 2026-09-13 the home menu
    // offers *Count stock* only to somebody who cannot reach this screen.
    var opened = 0;
    await _pumpScreen(tester, server: _server(), onCount: () => opened++);

    await tester.tap(find.byKey(const ValueKey('stock-take-review-count')));
    await tester.pumpAndSettle();

    expect(opened, 1);
  });

  testWidgets('a count handed in on the pushed route is there on return', (
    tester,
  ) async {
    // **The reported defect.** *Count stock* is pushed from the screen above
    // this panel, which cannot reach the panel's generation, so nothing
    // re-read when it popped: a person handed a count in and came straight
    // back to "No counts yet", which reads as the count having been lost.
    final server = _Server();
    await _pumpScreenWithRoutes(tester, server: server);
    expect(find.textContaining('No counts yet'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('stock-take-review-count')));
    await tester.pumpAndSettle();

    // What handing a count in does, from the pushed route: the record exists
    // before this route pops.
    _seedTake(server);
    await tester.tap(find.byKey(const ValueKey('hand-it-in')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('No counts yet'),
      findsNothing,
      reason: 'the count handed in is the whole reason for coming back here',
    );
    expect(find.textContaining('Whole catalog'), findsOneWidget);
  });

  testWidgets('no count is offered where no counting route is wired', (
    tester,
  ) async {
    await _pumpScreen(tester, server: _server());

    expect(find.byKey(const ValueKey('stock-take-review-count')), findsNothing);
  });

  testWidgets('the list scrolls rather than overflowing', (tester) async {
    // The defect exactly: three counts on a phone-sized viewport rendered a
    // yellow-and-black overflow stripe, because `RecordList` is a `Column` and
    // the caller owns the scroll.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(tester, server: _server(takes: 6), sizeViewport: false);

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('stock-take-review-list')),
      findsOneWidget,
    );

    // And it really scrolls: the last count is reachable.
    await tester.drag(
      find.byKey(const ValueKey('stock-take-review-list')),
      const Offset(0, -2000),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('an owner gets the counts and the rota as two tabs', (
    tester,
  ) async {
    // The rota moved here from *Configs* on 2026-10-04. Both tabs stay alive,
    // so a half-made change to the rota survives a look at the counts.
    await _pumpTabbed(tester, server: _server());

    expect(
      find.byKey(const ValueKey('stock-take-review-tabs')),
      findsOneWidget,
    );
    expect(find.textContaining('Wamweki Njoroge'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('rota-edit')), 'Fridays');

    await tester.tap(find.text('Counts'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Wamweki Njoroge'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Fridays'), findsOneWidget);
  });

  testWidgets('a manager reads the counts with no rota tab above them', (
    tester,
  ) async {
    // Only an owner or administrator may publish the rota, and a tab that only
    // says *Not allowed* is not one worth offering.
    await _pumpTabbed(tester, server: _server(), role: TenantRole.manager);

    expect(find.byKey(const ValueKey('stock-take-review-tabs')), findsNothing);
    expect(find.byKey(const ValueKey('rota-edit')), findsNothing);
    expect(find.textContaining('Wamweki Njoroge'), findsOneWidget);
  });

  testWidgets('no tabs where no rota is wired', (tester) async {
    await _pumpScreen(tester, server: _server());

    expect(find.byKey(const ValueKey('stock-take-review-tabs')), findsNothing);
  });

  // **The large-screen version, and only it**, at the developer's direction on
  // 2026-10-12 and 13: one row per count from 1024, the cards below it. The
  // pump helpers above already run at 1400.
  group('on a screen 1024 and wider', () {
    testWidgets('the counts are one table, their figures in columns', (
      tester,
    ) async {
      await _pump(tester, server: _server());

      final sheet = find.byKey(const ValueKey('stock-take-review-sheet'));
      expect(sheet, findsOneWidget);
      expect(find.byType(TenantStockTakeCard), findsNothing);
      // Both filters are the sheet's own.
      for (final key in <String>[
        'stock-take-review-status-filter',
        'stock-take-review-counter-filter',
      ]) {
        expect(
          find.descendant(of: sheet, matching: find.byKey(ValueKey(key))),
          findsOneWidget,
          reason: key,
        );
      }
      final id = 'st_2026-09-11_${'a' * 40}';
      expect(
        tester
            .widget<Text>(find.byKey(ValueKey('stock-take-coverage-$id')))
            .data,
        '2 of 3',
      );
      expect(
        tester
            .widget<Text>(find.byKey(ValueKey('stock-take-uncounted-$id')))
            .data,
        '1 not counted',
      );
      expect(
        tester
            .widget<Text>(find.byKey(ValueKey('stock-take-variance-$id')))
            .data,
        '1',
      );
      // The counter by name, with the UID they are recorded under beneath it.
      expect(find.text('Wamweki Njoroge'), findsOneWidget);
      expect(find.text('staff-cashier'), findsOneWidget);
      // A count with differences is what a manager is looking for.
      expect(
        tester
            .widget<StatusBadge>(
              find.byKey(ValueKey('stock-take-standing-$id')),
            )
            .label,
        'Needs review',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('below 1024 the cards are unchanged', (tester) async {
      tester.view.physicalSize = const Size(1023, 3600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pump(tester, server: _server(), sizeViewport: false);

      expect(find.byType(TenantStockTakeCard), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey('stock-take-review-sheet')),
        findsNothing,
      );
    });

    testWidgets('a row opens the count', (tester) async {
      await _pump(tester, server: _server());

      final id = 'st_2026-09-11_${'a' * 40}';
      await tester.tap(find.byKey(ValueKey('stock-take-open-$id')));
      await tester.pumpAndSettle();

      expect(find.text('The count'), findsOneWidget);
    });

    testWidgets('an agreed count is a word, not a badge', (tester) async {
      final server = _Server();
      _seedTake(server);
      await _pump(tester, server: server);

      final standing = find.byKey(
        ValueKey('stock-take-standing-st_2026-09-20_${'a' * 40}'),
      );
      expect(tester.widget(standing), isNot(isA<StatusBadge>()));
      expect(
        find.descendant(of: standing, matching: find.text('All agreed')),
        findsOneWidget,
      );
    });

    testWidgets('filters that match nothing say so inside the sheet', (
      tester,
    ) async {
      await _pump(tester, server: _server());

      await tester.tap(
        find.byKey(const ValueKey('stock-take-review-status-filter')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('stock-take-review-status-accepted')).last,
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('stock-take-review-sheet')),
          matching: find.byKey(const ValueKey('stock-take-review-no-matches')),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Count stock is offered over the table at its own width', (
      tester,
    ) async {
      var opened = 0;
      await _pumpScreen(tester, server: _server(), onCount: () => opened++);

      final count = find.byKey(const ValueKey('stock-take-review-count'));
      expect(
        tester.getSize(count).width,
        lessThan(tester.getSize(find.byType(Scaffold)).width / 2),
      );
      await tester.tap(count);
      await tester.pumpAndSettle();
      expect(opened, 1);
    });
  });
}

/// The screen as the app wires it for [role], with a rota that is one field.
Future<void> _pumpTabbed(
  WidgetTester tester, {
  required _Server server,
  TenantRole role = TenantRole.owner,
}) async {
  tester.view.physicalSize = const Size(1400, 3600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: TenantSessionController()
          ..open(
            uid: 'staff-owner',
            membership: _membership(role: role),
          ),
        child: TenantStockTakeReviewScreen(
          reader: _Reader(server),
          settings: (_) => const TextField(key: ValueKey('rota-edit')),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _Server server,
  VoidCallback? onCount,
}) async {
  tester.view.physicalSize = const Size(1400, 3600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: TenantSessionController()
          ..open(uid: 'staff-owner', membership: _membership()),
        child: TenantStockTakeReviewScreen(
          reader: _Reader(server),
          countRoute: onCount == null
              ? null
              : (_) {
                  onCount();
                  return const SizedBox.shrink();
                },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// [_pumpScreen], with the observer the app registers and a count route that
/// behaves like one - a page that writes and then pops.
Future<void> _pumpScreenWithRoutes(
  WidgetTester tester, {
  required _Server server,
}) async {
  tester.view.physicalSize = const Size(1400, 3600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: <NavigatorObserver>[tenantRouteObserver],
      home: TenantSessionScope(
        controller: TenantSessionController()
          ..open(uid: 'staff-owner', membership: _membership()),
        child: TenantStockTakeReviewScreen(
          reader: _Reader(server),
          countRoute: (routeContext) => Scaffold(
            body: Center(
              child: TextButton(
                key: const ValueKey('hand-it-in'),
                onPressed: () => Navigator.of(routeContext).pop(),
                child: const Text('Hand it in'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// One handed-in count, as the server holds it.
void _seedTake(_Server server) {
  server.staff['tenants/tenant-a/staff/staff-cashier'] = <String, Object?>{
    'uid': 'staff-cashier',
    'name': 'Wamweki Njoroge',
  };
  final id = 'st_2026-09-20_${'a' * 40}';
  server.takes['tenants/tenant-a/stock_takes/$id'] = <String, Object?>{
    'tenantId': 'tenant-a',
    'counterUid': 'staff-owner',
    'businessDate': '2026-09-20',
    'status': 'submitted',
    'productsInScope': 1,
    'countedLineCount': 1,
    'varianceLineCount': 0,
    'absoluteVarianceUnits': 0,
    'unmatchedLineCount': 0,
  };
}

Future<void> _pump(
  WidgetTester tester, {
  required _Server server,
  bool sizeViewport = true,
}) async {
  if (sizeViewport) {
    tester.view.physicalSize = const Size(1400, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: TenantSessionController()
          ..open(uid: 'staff-owner', membership: _membership()),
        child: Scaffold(
          body: TenantStockTakeReviewPanel(reader: _Reader(server)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

TenantMembership _membership({TenantRole role = TenantRole.owner}) =>
    TenantMembership(
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

/// One count by the viewer and one by somebody else, plus however many more the
/// overflow case needs.
_Server _server({int takes = 2}) {
  final server = _Server();
  server.staff['tenants/tenant-a/staff/staff-cashier'] = <String, Object?>{
    'uid': 'staff-cashier',
    'name': 'Wamweki Njoroge',
  };
  for (var index = 0; index < takes; index++) {
    // The document ID carries the business date, which is what orders the page.
    final id = 'st_2026-09-1${index}_${'a' * 40}';
    server.takes['tenants/tenant-a/stock_takes/$id'] = <String, Object?>{
      'tenantId': 'tenant-a',
      'counterUid': index.isEven ? 'staff-owner' : 'staff-cashier',
      'businessDate': '2026-09-1$index',
      'status': 'submitted',
      'productsInScope': 3,
      'countedLineCount': 2,
      'varianceLineCount': 1,
      'absoluteVarianceUnits': 2,
      'unmatchedLineCount': 0,
    };
  }
  return server;
}

final class _Server {
  final Map<String, Map<String, Object?>> takes =
      <String, Map<String, Object?>>{};
  final Map<String, Map<String, Object?>> staff =
      <String, Map<String, Object?>>{};

  Map<String, Object?>? documentAt(String path) => takes[path] ?? staff[path];
}

final class _Reader implements TenantDataReader {
  const _Reader(this._server);

  final _Server _server;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    final data = _server.documentAt(path);
    if (data == null) return null;
    return TenantDocumentSnapshot(path: path, data: data);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    final paths = _server.takes.keys.toList()..sort();
    if (query.descending) {
      paths.sort((left, right) => right.compareTo(left));
    }
    final matches = <TenantQueryDocumentSnapshot>[];
    for (final path in paths) {
      if (!path.startsWith('${query.collectionPath}/')) continue;
      final data = _server.takes[path]!;
      if (!query.equalityFilters.entries.every(
        (filter) => data[filter.key] == filter.value,
      )) {
        continue;
      }
      matches.add(TenantQueryDocumentSnapshot(path: path, data: data));
      if (matches.length >= query.limit) break;
    }
    return matches;
  }
}
