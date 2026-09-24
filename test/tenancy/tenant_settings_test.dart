import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('settings standings', () {
    // The table is the whole of the mapping from a published document to what
    // a row says about it, so a setting that grows a state cannot be added
    // without one of these failing.
    test('an absent document is awaiting, except the counting rota', () {
      expect(
        TenantSettingsStandingsRepository.standingFor(
          TenantSettingKind.printer,
          null,
        ).state,
        TenantSettingState.awaiting,
      );
      // **No published schedule is a working state, not a missing step.** It
      // is `TenantStockTakeSchedule.none`, which the till already treats as
      // "no count is due", so it is `set` and says so.
      final counts = TenantSettingsStandingsRepository.standingFor(
        TenantSettingKind.stockCounts,
        null,
      );
      expect(counts.state, TenantSettingState.set);
      expect(counts.detail, 'Nobody is interrupted.');
    });

    test('only an unpublished or unreadable currency blocks trading', () {
      expect(
        TenantSettingsStandingsRepository.standingFor(
          TenantSettingKind.currency,
          null,
        ).blocksTrading,
        isTrue,
      );
      expect(
        TenantSettingsStandingsRepository.standingFor(
          TenantSettingKind.currency,
          <String, Object?>{'currency': 'not-a-code'},
        ).blocksTrading,
        isTrue,
      );
      // **A shop with no printer still records every sale**, which is why its
      // absence never raises the callout above the list.
      expect(
        TenantSettingsStandingsRepository.standingFor(
          TenantSettingKind.printer,
          null,
        ).blocksTrading,
        isFalse,
      );
    });

    test('a document that cannot be parsed is unreadable, not a failure', () {
      // Precisely the `FormatException` the panel's own model throws, so the
      // index and the panel can never disagree about whether a document reads.
      for (final kind in TenantSettingKind.values) {
        final standing = TenantSettingsStandingsRepository.standingFor(
          kind,
          <String, Object?>{'currency': 42, 'host': 7, 'enforcement': 'no'},
        );
        expect(
          standing.state,
          TenantSettingState.unreadable,
          reason: '$kind should not accept a malformed document',
        );
        expect(standing.status, AppStatus.problem);
        expect(standing.badgeLabel, 'Unreadable');
      }
    });

    test('a set value states itself and wears no badge', () {
      final currency = TenantSettingsStandingsRepository.standingFor(
        TenantSettingKind.currency,
        <String, Object?>{'currency': 'KES'},
      );
      expect(currency.state, TenantSettingState.set);
      expect(currency.detail, startsWith('KES'));
      // Colour marks a fault. A value that is set is simply stated.
      expect(currency.status, isNull);
      expect(currency.badgeLabel, isNull);
    });

    test(
      'a setting that stops the till wears the problem tier, not awaiting',
      () {
        // Both are "a step nobody has taken". Only one of them is also the
        // reason nothing can be sold, and that is what the colour has to say.
        expect(
          TenantSettingsStandingsRepository.standingFor(
            TenantSettingKind.currency,
            null,
          ).status,
          AppStatus.problem,
        );
        expect(
          TenantSettingsStandingsRepository.standingFor(
            TenantSettingKind.printer,
            null,
          ).status,
          AppStatus.attention,
        );
      },
    );

    test('the callout says the cause, where the row said the consequence', () {
      final currency = TenantSettingsStandingsRepository.standingFor(
        TenantSettingKind.currency,
        null,
      );
      // The title above the list already states the consequence, so repeating
      // `detail` there would print the same sentence twice.
      expect(currency.detail, 'No sale can be rung up on any device.');
      expect(currency.blockingCause, isNot(currency.detail));
      expect(currency.blockingCause, contains('has published no currency'));
      // Nothing that does not stop the till has one at all.
      expect(
        TenantSettingsStandingsRepository.standingFor(
          TenantSettingKind.printer,
          null,
        ).blockingCause,
        isNull,
      );
    });

    test('the currency and the others name their absence differently', () {
      expect(
        TenantSettingsStandingsRepository.standingFor(
          TenantSettingKind.currency,
          null,
        ).badgeLabel,
        'Not published',
      );
      expect(
        TenantSettingsStandingsRepository.standingFor(
          TenantSettingKind.printer,
          null,
        ).badgeLabel,
        'Not set up',
      );
    });
  });

  group('settings index', () {
    testWidgets('states every setting before any of them is opened', (
      tester,
    ) async {
      final reader = _ConfigurationReader(
        documents: <String, Map<String, Object?>>{
          'branding': <String, Object?>{'companyName': 'Mwangi Hardware'},
          'checkout': <String, Object?>{'currency': 'KES'},
        },
      );
      await tester.pumpWidget(_settingsApp(reader: reader));
      await tester.pumpAndSettle();

      // **One query, not four.** The whole point of the index.
      expect(reader.queries, hasLength(1));
      // **No *Business details* row since 2026-09-23**: the receipt branding
      // is on the *Printer* page.
      expect(
        find.byKey(const ValueKey('setting-row-business-details')),
        findsNothing,
      );
      expect(find.textContaining('KES'), findsOneWidget);
      // The printer was never published, so its row says what that costs.
      expect(
        find.text('Receipts are not sent anywhere. Sales are still recorded.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('setting-standing-printer')),
        findsOneWidget,
      );
    });

    testWidgets('an unpublished currency is raised above the list', (
      tester,
    ) async {
      final reader = _ConfigurationReader(
        documents: <String, Map<String, Object?>>{
          'branding': <String, Object?>{'companyName': 'Mwangi Hardware'},
        },
      );
      await tester.pumpWidget(_settingsApp(reader: reader));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('settings-blocking')), findsOneWidget);
      expect(find.text('No sale can be rung up on any device.'), findsWidgets);
    });

    testWidgets('a published currency raises nothing, though the printer is '
        'still unset', (tester) async {
      final reader = _ConfigurationReader(
        documents: <String, Map<String, Object?>>{
          'checkout': <String, Object?>{'currency': 'KES'},
        },
      );
      await tester.pumpWidget(_settingsApp(reader: reader));
      await tester.pumpAndSettle();

      // The printer is absent and says so on its own row - and raises nothing,
      // because no paper is an inconvenience and not a stoppage.
      expect(find.byKey(const ValueKey('settings-blocking')), findsNothing);
      expect(
        find.byKey(const ValueKey('setting-standing-printer')),
        findsOneWidget,
      );
    });

    testWidgets('opening a row builds that panel and no other', (tester) async {
      final built = <String>[];
      final reader = _ConfigurationReader(
        documents: <String, Map<String, Object?>>{
          'checkout': <String, Object?>{'currency': 'KES'},
        },
      );
      await tester.pumpWidget(_settingsApp(reader: reader, built: built));
      await tester.pumpAndSettle();

      // **Nothing behind a row is built while the index is drawn.** The lazy
      // tab existed to keep a panel's document from being read before its tab
      // was opened; a row that pushes a page keeps that property.
      expect(built, isEmpty);

      await tester.tap(find.byKey(const ValueKey('setting-row-printer')));
      await tester.pumpAndSettle();

      expect(built, <String>['printer']);
    });

    testWidgets('a linked setting opens directly, with no index under it', (
      tester,
    ) async {
      final built = <String>[];
      final reader = _ConfigurationReader(documents: const {});
      await tester.pumpWidget(
        _settingsApp(
          reader: reader,
          built: built,
          initialSettingKey: 'printer',
        ),
      );
      await tester.pumpAndSettle();

      // The home's *Printer* tile means "take me to the printer". Pushing the
      // index underneath would put a second Back between that tile and home.
      expect(built, <String>['printer']);
      expect(find.byKey(const ValueKey('settings-index')), findsNothing);
      // And it costs no standings read at all, because no index is drawn.
      expect(reader.queries, isEmpty);
    });

    testWidgets('no standings reader draws the rows and issues no query', (
      tester,
    ) async {
      final reader = _ConfigurationReader(documents: const {});
      await tester.pumpWidget(_settingsApp(reader: reader, standings: false));
      await tester.pumpAndSettle();

      expect(reader.queries, isEmpty);
      expect(find.byKey(const ValueKey('setting-row-printer')), findsOneWidget);
      // No standing was read, so none is claimed.
      expect(
        find.byKey(const ValueKey('setting-standing-printer')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('settings-blocking')), findsNothing);
    });

    testWidgets('a role with nothing here is told so', (tester) async {
      final reader = _ConfigurationReader(documents: const {});
      await tester.pumpWidget(
        _settingsApp(reader: reader, role: TenantRole.cashier),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('settings-none')), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-index')), findsNothing);
      // A refusal costs no read either.
      expect(reader.queries, isEmpty);
    });

    testWidgets('returning from a setting keeps the list while it re-reads', (
      tester,
    ) async {
      // #141: the re-read on return blanked the index to a full-screen
      // spinner and lost its scroll position, on every return from anything.
      final reader = _ConfigurationReader(documents: const {});
      var reads = 0;
      final stalled =
          Completer<Map<TenantSettingKind, TenantSettingStanding>>();
      await tester.pumpWidget(
        _settingsApp(
          reader: reader,
          standingsReader: (session) {
            reads++;
            if (reads > 1) return stalled.future;
            return TenantSettingsStandingsRepository(
              session: session,
              reader: reader,
            ).read(collectionReader: reader);
          },
        ),
      );
      await tester.pumpAndSettle();

      final row = find.byKey(const ValueKey('setting-row-printer'));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(reads, 2, reason: 'a return still re-reads');
      expect(find.byKey(const ValueKey('settings-reading')), findsNothing);
      expect(find.byKey(const ValueKey('setting-row-printer')), findsOneWidget);
    });

    testWidgets('a failed standings read still opens every setting', (
      tester,
    ) async {
      final reader = _ConfigurationReader(documents: const {}, fails: true);
      await tester.pumpWidget(_settingsApp(reader: reader));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('settings-standings-unread')),
        findsOneWidget,
      );
      // **The rows are still there.** A summary that could not be read must not
      // stand between a person and the setting they came to change.
      expect(find.byKey(const ValueKey('setting-row-printer')), findsOneWidget);
    });
  });
}

Widget _settingsApp({
  required _ConfigurationReader reader,
  List<String>? built,
  String? initialSettingKey,
  bool standings = true,
  Future<Map<TenantSettingKind, TenantSettingStanding>> Function(
    TenantSession session,
  )?
  standingsReader,
  TenantRole role = TenantRole.owner,
}) {
  final controller = TenantSessionController()
    ..open(
      uid: 'owner-a',
      membership: TenantMembership(
        tenantId: 'tenant-a',
        tenantName: 'Mwangi Hardware',
        tenantSlug: 'tenant-a',
        role: role,
        membershipStatus: MembershipStatus.active,
        tenantStatus: TenantStatus.active,
        isOwner: role == TenantRole.owner,
        mirrorVersion: 1,
        createdAt: DateTime.utc(2026, 9, 20),
        updatedAt: DateTime.utc(2026, 9, 20),
        serverCanAccess: true,
        canonicalTenantExists: true,
        canonicalMembershipExists: true,
      ),
    );
  return MaterialApp(
    home: TenantSessionScope(
      controller: controller,
      child: TenantSettingsScreen(
        initialSettingKey: initialSettingKey,
        standings:
            standingsReader ??
            (standings
                ? (session) => TenantSettingsStandingsRepository(
                    session: session,
                    reader: reader,
                  ).read(collectionReader: reader)
                : null),
        destinations: <TenantSettingsDestination>[
          for (final (key, kind) in const <(String, TenantSettingKind)>[
            ('currency', TenantSettingKind.currency),
            ('printer', TenantSettingKind.printer),
            ('stock-take', TenantSettingKind.stockCounts),
          ])
            TenantSettingsDestination(
              settingKey: key,
              kind: kind,
              icon: Icons.settings_outlined,
              allowedRoles: const <TenantRole>[
                TenantRole.owner,
                TenantRole.admin,
              ],
              builder: (_) {
                built?.add(key);
                return Text('panel-$key');
              },
            ),
        ],
      ),
    ),
  );
}

/// Answers one `configuration` collection page out of a map.
final class _ConfigurationReader implements TenantDataReader {
  _ConfigurationReader({required this.documents, this.fails = false});

  final Map<String, Map<String, Object?>> documents;
  final bool fails;
  final List<TenantCollectionQuery> queries = <TenantCollectionQuery>[];

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async => null;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    queries.add(query);
    if (fails) throw StateError('unreachable');
    return <TenantQueryDocumentSnapshot>[
      for (final entry in documents.entries)
        TenantQueryDocumentSnapshot(
          path: '${query.collectionPath}/${entry.key}',
          data: entry.value,
        ),
    ];
  }
}
