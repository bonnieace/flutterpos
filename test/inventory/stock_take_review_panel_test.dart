import 'package:flutter/material.dart';
import 'package:flutter_application_1/inventory/inventory.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
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
    await _pump(tester, server: _server());

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
    expect(find.byKey(const ValueKey('stock-take-review-list')), findsOneWidget);

    // And it really scrolls: the last count is reachable.
    await tester.drag(
      find.byKey(const ValueKey('stock-take-review-list')),
      const Offset(0, -2000),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
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
        controller: TenantSessionController()..open(
          uid: 'staff-owner',
          membership: _membership(),
        ),
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
        controller: TenantSessionController()..open(
          uid: 'staff-owner',
          membership: _membership(),
        ),
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
        controller: TenantSessionController()..open(
          uid: 'staff-owner',
          membership: _membership(),
        ),
        child: Scaffold(
          body: TenantStockTakeReviewPanel(reader: _Reader(server)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

TenantMembership _membership() => TenantMembership(
  tenantId: 'tenant-a',
  tenantName: 'tenant-a',
  tenantSlug: 'tenant-a',
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

  Map<String, Object?>? documentAt(String path) =>
      takes[path] ?? staff[path];
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
