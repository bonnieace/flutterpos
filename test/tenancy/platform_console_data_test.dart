import 'package:flutter_test/flutter_test.dart';
import 'package:uzapay_pos/tenancy/platform_console_data.dart';
import 'package:uzapay_pos/tenancy/tenant_types.dart';

import 'support/platform_console_memory.dart';
import 'support/platform_console_world.dart';

void main() {
  late MemoryPlatformConsoleDataSource source;
  DateTime now() => platformConsoleNow;

  setUp(() => source = MemoryPlatformConsoleDataSource(platformConsoleWorld()));

  group('overview', () {
    test('counts every figure from the documents', () async {
      final overview = await PlatformOverviewReader(source, clock: now).load();
      expect(overview.trading, 14);
      expect(overview.suspended, 2);
      expect(overview.archived, 1);
      expect(overview.businesses, 17);
      expect(overview.businessesByWeek, <int>[
        0,
        1,
        3,
        3,
        4,
        2,
        0,
        1,
        0,
        1,
        1,
        1,
      ]);
      expect(overview.accountsByWeek, <int>[
        4,
        18,
        26,
        31,
        38,
        22,
        15,
        12,
        11,
        8,
        18,
        9,
      ]);
      expect(overview.accounts, 212);
      expect(overview.accountsThisWeek, 9);
      expect(overview.openedThisWeek, 1);
      expect(overview.openedThisMonth, 3);
      expect(overview.disabledAccounts, 3);
    });

    test('names the suspended longest first, and the recent alerts', () async {
      final overview = await PlatformOverviewReader(source, clock: now).load();
      expect(overview.suspensions.map((s) => s.name), <String>[
        'Kamau Butchery',
        'Coast Fresh Juices',
      ]);
      expect(overview.alerts, hasLength(2));
      expect(
        overview.alerts.map((view) => view.businessName),
        containsAll(<String>['Wairimu Salon & Spa', 'Kilimani Grocers']),
      );
      expect(overview.operations.single.uid, 'kevin');
      expect(overview.operationNames['kevin'], 'Kevin Odhiambo');
      expect(overview.administrators, hasLength(2));
      expect(overview.limits.requestsPerDay, 5);
      expect(overview.limits.businessesPerOwner, 25);
    });

    test('an alert older than seven days no longer needs anyone', () async {
      source.documents['platform_alerts/alert-wairimu']!['createdAt'] =
          DateTime(2026, 10, 1);
      final recent = await PlatformAlertsReader(source, clock: now).recent();
      expect(recent.map((alert) => alert.id), <String>['alert-kilimani']);
      final all = await PlatformAlertsReader(source, clock: now).list();
      expect(all, hasLength(2));
    });
  });

  group('businesses', () {
    test('pages newest first and resumes after its cursor', () async {
      final directory = PlatformBusinessDirectory(source, clock: now);
      final first = await directory.page(filter: PlatformBusinessFilter.all);
      expect(first.items, hasLength(8));
      expect(first.items.first.business.name, 'Ruth’s Boutique');
      expect(first.next, isNotNull);
      final second = await directory.page(
        filter: PlatformBusinessFilter.all,
        after: first.next,
        firstIndex: 8,
      );
      final firstIds = first.items.map((row) => row.business.tenantId).toSet();
      expect(
        second.items
            .map((row) => row.business.tenantId)
            .toSet()
            .intersection(firstIds),
        isEmpty,
      );
      expect(second.firstIndex, 8);
    });

    test('counts each filter and finds the businesses with an alert', () async {
      final directory = PlatformBusinessDirectory(source, clock: now);
      final counts = await directory.counts();
      expect(counts[PlatformBusinessFilter.all], 17);
      expect(counts[PlatformBusinessFilter.trading], 14);
      expect(counts[PlatformBusinessFilter.suspended], 2);
      expect(counts[PlatformBusinessFilter.archived], 1);
      expect(counts[PlatformBusinessFilter.attention], 2);
      final attention = await directory.page(
        filter: PlatformBusinessFilter.attention,
      );
      expect(
        attention.items.map((row) => row.business.tenantId),
        containsAll(<String>['wairimu-salon', 'kilimani-grocers']),
      );
      expect(attention.items.every((row) => row.alert != null), isTrue);
    });

    test('a suspended row carries the change that suspended it', () async {
      final page = await PlatformBusinessDirectory(
        source,
        clock: now,
      ).page(filter: PlatformBusinessFilter.suspended);
      final kamau = page.items.singleWhere(
        (row) => row.business.tenantId == 'kamau-butchery',
      );
      expect(kamau.lastChange?.to, TenantStatus.suspended);
      expect(
        kamau.lastChange?.reason,
        'Chargebacks under review with the bank.',
      );
      expect(kamau.lastChangeActor, 'Bonnie Master');
      expect(kamau.owner?.name, 'Daniel Kamau');
    });

    test('searches by slug prefix, spaces as hyphens', () async {
      final page = await PlatformBusinessDirectory(
        source,
        clock: now,
      ).page(filter: PlatformBusinessFilter.all, search: 'Mwangi Hard');
      expect(page.items.single.business.name, 'Mwangi Hardware');
      expect(platformSlugPrefix('  Duka la Mama '), 'duka-la-mama');
    });

    test('one business: managers, staff standings, history, audit', () async {
      final detail = await PlatformBusinessReader(
        source,
        clock: now,
      ).load('mwangi-hardware');
      expect(detail, isNotNull);
      expect(detail!.administrators.map((member) => member.role), <TenantRole>[
        TenantRole.owner,
        TenantRole.admin,
      ]);
      expect(detail.counts.total, 23);
      expect(detail.counts.needAttention, 2);
      expect(detail.counts.deactivated, 1);
      expect(
        detail.staffPreview.first.standing,
        PlatformStaffStanding.emailRejected,
      );
      expect(detail.history.map((event) => event.kind), <PlatformLifecycleKind>[
        PlatformLifecycleKind.changed,
        PlatformLifecycleKind.changed,
        PlatformLifecycleKind.created,
      ]);
      expect(detail.audit.first.eventType, 'product_updated');
      expect(detail.names['grace'], 'Grace Wanjiru');
      expect(detail.names[platformConsoleOperatorUid], 'Bonnie Master');
    });

    test('a missing business reads as null, not as an error', () async {
      expect(
        await PlatformBusinessReader(source, clock: now).load('nowhere'),
        isNull,
      );
    });
  });

  group('people', () {
    test('every filter has a count, and they add up', () async {
      final counts = await PlatformPeopleDirectory(source).counts();
      expect(counts[PlatformPeopleFilter.everyone], 212);
      expect(counts[PlatformPeopleFilter.disabled], 3);
      expect(counts[PlatformPeopleFilter.platform], 2);
      expect(
        counts[PlatformPeopleFilter.owners]! +
            counts[PlatformPeopleFilter.staff]! +
            counts[PlatformPeopleFilter.noBusiness]! +
            counts[PlatformPeopleFilter.platform]!,
        212,
      );
    });

    test(
      'a row knows what its person belongs to and what is running',
      () async {
        final page = await PlatformPeopleDirectory(
          source,
        ).page(filter: PlatformPeopleFilter.disabled);
        final kevin = page.items.singleWhere(
          (row) => row.person.uid == 'kevin',
        );
        expect(kevin.operation?.reactivating, isTrue);
        expect(kevin.memberships.single.businessName, 'Lake View Pharmacy');
        expect(kevin.memberships.single.role, TenantRole.cashier);
      },
    );

    test('searches by email prefix', () async {
      final page = await PlatformPeopleDirectory(
        source,
      ).page(filter: PlatformPeopleFilter.everyone, search: 'Esther@');
      expect(page.items.single.person.name, 'Esther Wairimu');
    });
  });

  group('activity', () {
    test('reads each kind of record and names who did it', () async {
      final page = await PlatformActivityReader(source).page(pageSize: 20);
      final kinds = page.entries.map((entry) => entry.kind).toSet();
      expect(
        kinds,
        containsAll(<PlatformActivityKind>[
          PlatformActivityKind.businessCreated,
          PlatformActivityKind.businessChanged,
          PlatformActivityKind.personStatusChanged,
          PlatformActivityKind.suppressionCleared,
          PlatformActivityKind.administratorGranted,
        ]),
      );
      final kevin = page.entries.firstWhere((e) => e.targetUid == 'kevin');
      expect(kevin.inProgress, isTrue);
      expect(kevin.reactivation, isTrue);
      expect(page.people['mercy'], 'Mercy Chebet');
      expect(page.businesses['ruths-boutique'], 'Ruth’s Boutique');
    });

    test('filters to one kind, and to one person', () async {
      final people = await PlatformActivityReader(
        source,
      ).page(filter: PlatformActivityFilter.people);
      expect(
        people.entries.every(
          (e) => e.kind == PlatformActivityKind.personStatusChanged,
        ),
        isTrue,
      );
      final esther = await PlatformActivityReader(
        source,
      ).page(aboutUid: 'esther');
      expect(esther.entries.single.reactivation, isFalse);
    });
  });

  group('email delivery', () {
    test(
      'a lookup says where it came from, and parses what came back',
      () async {
        final callable = MemoryReviewEmailSuppressionCallable(
          suppressed: platformConsoleSuppressed,
        );
        final review = await PlatformSuppressionGateway(
          callable,
          requestIdFactory: () => 'request-0001',
        ).inspect(' Samuel.Ochieng@Yahoo.com ');
        expect(callable.calls.single, <String, Object?>{
          'email': 'samuel.ochieng@yahoo.com',
          'action': 'inspect',
          'reason': PlatformSuppressionGateway.inspectReason,
          'requestId': 'request-0001',
        });
        expect(
          review.active.single.category,
          PlatformSuppressionCategory.hardBounce,
        );
        expect(review.needsSpamEvidence, isFalse);
      },
    );

    test('clearing sends the confirmation the backend asks for', () async {
      final callable = MemoryReviewEmailSuppressionCallable(
        suppressed: platformConsoleSuppressed,
      );
      final review =
          await PlatformSuppressionGateway(
            callable,
            requestIdFactory: () => 'request-0002',
          ).clear(
            email: 'samuel.ochieng@yahoo.com',
            reason: '  Spelling fixed by the owner. ',
            confirmation: PlatformClearConfirmation.addressCorrected,
          );
      expect(callable.calls.single['confirmation'], 'address_corrected');
      expect(callable.calls.single['reason'], 'Spelling fixed by the owner.');
      expect(callable.calls.single.containsKey('evidenceReference'), isFalse);
      expect(review.active, isEmpty);
      expect(review.clearedCount, 1);
    });

    test('refuses an address the backend would refuse', () {
      expect(normalizePlatformEmail('not-an-address'), isNull);
      expect(
        () => PlatformSuppressionGateway(
          MemoryReviewEmailSuppressionCallable(),
        ).inspect('nope'),
        throwsArgumentError,
      );
    });

    test('a malformed answer is an error, not an empty result', () {
      expect(
        () => PlatformSuppressionReview.fromCallable(<String, Object?>{
          'items': <Object?>[
            <String, Object?>{'category': 'mystery'},
          ],
          'clearedCount': 0,
        }),
        throwsFormatException,
      );
    });
  });

  test('limits fall back to the backend defaults outside 0 to 10000', () {
    final limits = PlatformLimits.fromRecord(
      const PlatformRecord(
        path: 'platform_config/limits',
        data: <String, Object?>{
          'maxTenantRequestsPer24Hours': 3,
          'maxOwnedActiveTenantsPerUser': 20000,
        },
      ),
    );
    expect(limits.requestsPerDay, 3);
    expect(limits.businessesPerOwner, 25);
  });

  test('a week starts on Monday', () {
    expect(
      platformWeekStart(DateTime(2026, 10, 20, 9, 40)),
      DateTime(2026, 10, 19),
    );
    expect(platformWeekStart(DateTime(2026, 10, 19)), DateTime(2026, 10, 19));
    expect(
      platformWeekStart(DateTime(2026, 10, 25, 23)),
      DateTime(2026, 10, 19),
    );
  });
}
