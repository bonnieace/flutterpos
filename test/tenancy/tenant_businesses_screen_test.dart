import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:uzapay_pos/theme.dart';

const Size _phone = Size(411, 891);

/// 9:00 in Nairobi on 8 October, so yesterday's business date is 2026-10-07.
DateTime _morning() => DateTime.utc(2026, 10, 8, 6);

void main() {
  testWidgets('the open business is its full card, marked open now', (
    tester,
  ) async {
    await _pump(tester, reader: _Reader());

    final open = find.byKey(const ValueKey('business-tenant-a'));
    expect(open, findsOneWidget);
    expect(
      find.descendant(of: open, matching: find.textContaining('Open now')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: open, matching: find.text('Dev Corner Shop')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: open, matching: find.text('Fresh every morning')),
      findsOneWidget,
    );
    // The currency is set small beside the figure, as on Books.
    expect(
      find.descendant(of: open, matching: find.text('KES')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: open, matching: find.text('910')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: open, matching: find.text('Owner')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: open, matching: find.text('Edit details')),
      findsOneWidget,
    );
  });

  testWidgets('the till names the one person who has it open', (tester) async {
    await _pump(
      tester,
      reader: _Reader(openShifts: {'user-amina': '2026-10-08'}),
    );

    expect(find.text('Open · Amina'), findsOneWidget);
  });

  testWidgets('a till opened yesterday and still running is open', (
    tester,
  ) async {
    // The first build read today's shifts and called a night shift closed.
    await _pump(
      tester,
      reader: _Reader(openShifts: {'user-amina': '2026-10-07'}),
    );

    expect(find.text('Open · Amina'), findsOneWidget);
  });

  testWidgets('two open tills are counted, not listed', (tester) async {
    await _pump(
      tester,
      reader: _Reader(
        openShifts: {'user-amina': '2026-10-08', 'user-juma': '2026-10-08'},
      ),
    );

    expect(find.text('2 tills open'), findsOneWidget);
  });

  testWidgets('no open shift reads as a closed till', (tester) async {
    await _pump(tester, reader: _Reader());

    expect(find.text('Closed'), findsOneWidget);
  });

  testWidgets('another business shows its last counted day, dated', (
    tester,
  ) async {
    await _pump(
      tester,
      reader: _Reader(),
      others: [_membership('tenant-b', 'Westlands Mart', TenantRole.manager)],
    );

    final other = find.byKey(const ValueKey('business-tenant-b'));
    expect(
      find.descendant(of: other, matching: find.text('Westlands Mart')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: other, matching: find.text('LAST COUNTED · 7 OCT')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: other, matching: find.text('12400')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: other, matching: find.text('Manager')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: other, matching: find.text('Switch to this shop')),
      findsOneWidget,
    );
  });

  testWidgets('a cashier elsewhere is not shown that business’s takings', (
    tester,
  ) async {
    final reader = _Reader();
    await _pump(
      tester,
      reader: reader,
      others: [_membership('tenant-b', 'Westlands Mart', TenantRole.cashier)],
    );

    final other = find.byKey(const ValueKey('business-tenant-b'));
    expect(
      find.descendant(of: other, matching: find.text('12400')),
      findsNothing,
    );
    // The rules refuse a cashier `daily_metrics`, so it is never asked for.
    expect(
      reader.requested.where((path) => path.contains('tenant-b/daily_metrics')),
      isEmpty,
    );
  });

  testWidgets('a business that cannot be opened says why, and is no button', (
    tester,
  ) async {
    await _pump(
      tester,
      reader: _Reader(),
      others: [
        _membership(
          'tenant-c',
          'Kilimani Grocers',
          TenantRole.cashier,
          tenantStatus: TenantStatus.suspended,
        ),
      ],
    );

    final other = find.byKey(const ValueKey('business-tenant-c'));
    expect(
      find.descendant(of: other, matching: find.textContaining('Suspended')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: other, matching: find.textContaining('Switch')),
      findsNothing,
    );
  });

  testWidgets('tapping another business switches to it', (tester) async {
    final switched = <String>[];
    await _pump(
      tester,
      reader: _Reader(),
      others: [_membership('tenant-b', 'Westlands Mart', TenantRole.manager)],
      onSwitch: (membership) async {
        switched.add(membership.tenantId);
        return TenantSwitchResult.switched(membership);
      },
    );

    await tester.tap(find.byKey(const ValueKey('business-tenant-b')));
    // Not settled: this page is the first route here, so nothing pops it and
    // the card keeps its *Switching…* spinner turning.
    await tester.pump();
    await tester.pump();

    expect(switched, ['tenant-b']);
  });

  testWidgets('a refused switch says why and stays on the page', (
    tester,
  ) async {
    await _pump(
      tester,
      reader: _Reader(),
      others: [_membership('tenant-b', 'Westlands Mart', TenantRole.manager)],
      onSwitch: (membership) async => const TenantSwitchResult.blocked(
        TenantSwitchBlocker.unfinishedCashCountOrShiftClose,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('business-tenant-b')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('my-businesses-switch-blocker')),
      findsOneWidget,
    );
    expect(
      find.text('Finish the cash count or shift close before switching.'),
      findsOneWidget,
    );
  });

  testWidgets('Add business heads the list, beside the count', (tester) async {
    await _pump(tester, reader: _Reader());

    expect(find.text('1 business'), findsOneWidget);
    expect(find.byKey(const ValueKey('add-business')), findsOneWidget);
    final header = tester.getTopLeft(
      find.byKey(const ValueKey('add-business')),
    );
    final card = tester.getTopLeft(
      find.byKey(const ValueKey('business-tenant-a')),
    );
    expect(header.dy, lessThan(card.dy));
  });

  testWidgets('an unverified account is told why it cannot add one', (
    tester,
  ) async {
    await _pump(tester, reader: _Reader(), emailVerified: false);

    expect(find.byKey(const ValueKey('add-business-refusal')), findsOneWidget);
    expect(find.text('Verify your email to add a business.'), findsOneWidget);
  });

  testWidgets('the add sheet previews the card as the name is typed, '
      'in the open business’s currency', (tester) async {
    final callable = _RecordingCallable();
    await _pump(tester, reader: _Reader(), callable: callable);

    await tester.tap(find.byKey(const ValueKey('add-business')));
    await tester.pumpAndSettle();

    final preview = find.byKey(const ValueKey('add-business-preview'));
    expect(preview, findsOneWidget);
    expect(
      find.descendant(of: preview, matching: find.text('KES')),
      findsOneWidget,
    );

    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('tenant-request-name')),
        matching: find.byType(EditableText),
      ),
      'Mama Mboga Kilimani',
    );
    await tester.pump();
    expect(
      find.descendant(of: preview, matching: find.text('Mama Mboga Kilimani')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('tenant-request-submit')));
    await tester.pumpAndSettle();

    expect(callable.payloads.single['currency'], 'KES');
    expect(callable.payloads.single['name'], 'Mama Mboga Kilimani');
    // Back on the list, the new business is there while the shell catches up.
    expect(find.text('2 businesses'), findsOneWidget);
    expect(find.byKey(const ValueKey('business-tenant-new')), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required _Reader reader,
  List<TenantMembership> others = const [],
  Future<TenantSwitchResult> Function(TenantMembership)? onSwitch,
  bool emailVerified = true,
  RequestTenantCallable? callable,
}) async {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final open = _membership('tenant-a', 'Dev Corner Shop', TenantRole.owner);
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: TenantBusinessesScreen(
        uid: 'user-a',
        membership: open,
        readMemberships: () => [open, ...others],
        reader: reader,
        openReceipt: TenantOpenBusinessReceipt(
          name: 'Dev Corner Shop',
          slogan: 'Fresh every morning',
          today: 'KES 910',
          sales: '3',
          currencyCode: 'KES',
        ),
        onEditDetails: () {},
        onSwitchTenant:
            onSwitch ??
            (membership) async => TenantSwitchResult.switched(membership),
        accountEmail: 'amina@devcorner.co.ke',
        requestIdentity: TenantRequestIdentity(
          uid: 'user-a',
          emailVerified: emailVerified,
          profile: const RootRoutingProfile(
            accountType: RootAccountType.tenantUser,
            globalStatus: 'active',
          ),
        ),
        requestTenantCallable: callable ?? _RecordingCallable(),
        tenantRequestIdFactory: () => 'tenant-request-1',
        clock: _morning,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

TenantMembership _membership(
  String tenantId,
  String name,
  TenantRole role, {
  TenantStatus tenantStatus = TenantStatus.active,
}) => TenantMembership(
  tenantId: tenantId,
  tenantName: name,
  tenantSlug: tenantId,
  role: role,
  membershipStatus: MembershipStatus.active,
  tenantStatus: tenantStatus,
  isOwner: role == TenantRole.owner,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 8, 1),
  updatedAt: DateTime.utc(2026, 8, 1),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);

/// Answers the reads *My businesses* makes, and records them.
final class _Reader implements TenantDataReader {
  _Reader({this.openShifts = const <String, String>{}});

  /// Open shifts by cashier UID, each with the business date it was opened on.
  final Map<String, String> openShifts;

  final List<String> requested = <String>[];

  static final Map<String, Map<String, Object?>>
  _documents = <String, Map<String, Object?>>{
    'tenants/tenant-a/staff/user-amina': {'uid': 'user-amina', 'name': 'Amina'},
    'tenants/tenant-a/staff/user-juma': {'uid': 'user-juma', 'name': 'Juma'},
    'tenants/tenant-b/configuration/branding': {
      'companyName': 'Westlands Mart',
      'slogan': 'Your neighbourhood store',
    },
    'tenants/tenant-b/configuration/checkout': {'currency': 'KES'},
    'tenants/tenant-b/daily_metrics/2026-10-07': {
      'tenantId': 'tenant-b',
      'businessDate': '2026-10-07',
      'sales': 12400,
      'profit': 3100,
      'transactions': 38,
      'transactionCount': 38,
      'shiftCount': 2,
      'incompleteCostLineCount': 0,
      'metricGeneration': 'gen-1',
      'sourceDirtyRevision': 1,
      'regeneratedAt': Timestamp.fromDate(DateTime.utc(2026, 10, 8, 0, 30)),
      'netSales': 12400,
      'netProfit': 3100,
      'netTransactions': 38,
      'netIncompleteCostLineCount': 0,
      'returnedSales': 0,
      'returnCount': 0,
      'netMetricsVersion': 1,
    },
  };

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    requested.add(path);
    final data = _documents[path];
    return data == null ? null : TenantDocumentSnapshot(path: path, data: data);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    if (query.collectionPath != 'tenants/tenant-a/shifts' ||
        query.equalityFilters['status'] != 'open') {
      return const <TenantQueryDocumentSnapshot>[];
    }
    var index = 0;
    return <TenantQueryDocumentSnapshot>[
      for (final entry in openShifts.entries)
        _openShift(entry.key, entry.value, index++),
    ];
  }

  static TenantQueryDocumentSnapshot _openShift(
    String staffId,
    String businessDate,
    int index,
  ) {
    final shiftId = 'shift-$index';
    return TenantQueryDocumentSnapshot(
      path: 'tenants/tenant-a/shifts/$shiftId',
      data: <String, Object?>{
        'shiftId': shiftId,
        'tenantId': 'tenant-a',
        'staffId': staffId,
        'deviceId': 'dev-0123456789abcdef0123456789abcde$index',
        'businessDate': businessDate,
        'status': 'open',
      },
    );
  }
}

final class _RecordingCallable implements RequestTenantCallable {
  final payloads = <Map<String, Object?>>[];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(Map<String, Object?>.from(payload));
    return <String, Object?>{
      'tenantId': 'tenant-new',
      'name': payload['name'],
      'slug': payload['slug'],
      'currency': payload['currency'],
      'status': 'active',
    };
  }
}
