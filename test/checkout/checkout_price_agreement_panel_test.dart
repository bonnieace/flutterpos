import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:uzapay_pos/ui/status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/collection_pages.dart';
import '../support/notices.dart';

const String _tenant = 'tenant-a';
const String _owner = 'owner';
const String _root = 'tenants/$_tenant';
const String _policyPath = '$_root/configuration/price_agreement';

final Map<String, Map<String, Object?>> _staff = <String, Map<String, Object?>>{
  _owner: _member(_owner, 'Asha Mwangi', role: 'owner'),
  'st-david': _member('st-david', 'David Mutiso', status: 'inactive'),
  'st-grace': _member('st-grace', 'Grace Wanjiru', role: 'manager'),
  'st-lydia': _member('st-lydia', 'Lydia Achieng', status: 'pending'),
  'st-peter': _member('st-peter', 'Peter Kamau'),
};

const Map<String, Object?> _policy = <String, Object?>{
  'allowed': <Map<String, Object?>>[
    <String, Object?>{'uid': 'st-david'},
    <String, Object?>{'uid': 'st-lydia'},
    <String, Object?>{'uid': 'st-peter'},
  ],
  'updatedBy': _owner,
};

/// The current shape: everyone, except Grace.
const Map<String, Object?> _allButGrace = <String, Object?>{
  'everyone': true,
  'blocked': <Map<String, Object?>>[
    <String, Object?>{'uid': 'st-grace'},
  ],
  'updatedBy': _owner,
};

const Map<String, Object?> _onlyGrace = <String, Object?>{
  'allowed': <Map<String, Object?>>[
    <String, Object?>{'uid': 'st-grace'},
  ],
  'updatedBy': _owner,
};

void main() {
  // **A list saved under the first rule still means only those people**: it
  // was an owner's choice, so everybody it did not name reads as switched off.
  testWidgets('a list saved under the first rule is read back, person by person', (
    tester,
  ) async {
    await _pump(tester, _Reader(policy: _policy), writer: _Writer());

    expect(_allowed(tester, 'st-peter'), isTrue);
    expect(
      _allowed(tester, _owner),
      isFalse,
      reason: 'the owner was not named on the list that was saved',
    );
    expect(_text(tester, 'price-agreement-count'), 'Off for 2 people');
    expect(
      _noteText(tester, 'st-david'),
      'Cannot sign in, so never offered it',
      reason: 'a deactivated person still allowed is the one row at fault',
    );
    expect(_noteText(tester, 'st-lydia'), 'Offered once they accept the invitation');
    expect(
      find.byKey(const ValueKey('price-agreement-note-st-grace')),
      findsNothing,
    );
  });

  testWidgets('nothing published lets everyone agree a price', (tester) async {
    await _pump(tester, _Reader(), writer: _Writer());

    expect(_text(tester, 'price-agreement-count'), 'Everyone');
    for (final uid in _staff.keys) {
      expect(_allowed(tester, uid), isTrue, reason: uid);
    }
  });

  testWidgets('switching somebody off saves who it is off for', (
    tester,
  ) async {
    final writer = _Writer();
    await _pump(tester, _Reader(policy: _policy), writer: writer);

    await _choose(tester, _owner, 'yes');
    await _choose(tester, 'st-david', 'no');
    expect(_allowed(tester, _owner), isTrue);
    expect(_text(tester, 'price-agreement-count'), 'Off for 2 people');

    await _save(tester);

    expect(writer.merges.single.path, _policyPath);
    expect(writer.merges.single.data, <String, Object?>{
      'everyone': true,
      'blocked': <Map<String, Object?>>[
        <String, Object?>{'uid': 'st-david'},
        <String, Object?>{'uid': 'st-grace'},
      ],
      // The same answers, for a build from before the change.
      'allowed': <Map<String, Object?>>[
        <String, Object?>{'uid': _owner},
        <String, Object?>{'uid': 'st-lydia'},
        <String, Object?>{'uid': 'st-peter'},
      ],
      'updatedBy': _owner,
    });
    expect(snackNotice(tester).status, AppStatus.ok);
  });

  testWidgets('saving what is already published sends nothing', (
    tester,
  ) async {
    final writer = _Writer();
    await _pump(tester, _Reader(policy: _allButGrace), writer: writer);

    await _save(tester);

    expect(writer.merges, isEmpty);
    expect(
      snackNotice(tester).message,
      'That is already what is set, so nothing was sent.',
    );
  });

  testWidgets('a document nobody can read says so, and allows nobody', (
    tester,
  ) async {
    await _pump(
      tester,
      _Reader(policy: const <String, Object?>{'allowed': 'everyone'}),
      writer: _Writer(),
    );

    expect(
      noticeAt(tester, 'price-agreement-settings-malformed').status,
      AppStatus.problem,
    );
    expect(_allowed(tester, 'st-peter'), isFalse);
  });

  testWidgets('a build with no writer shows the list and changes nothing', (
    tester,
  ) async {
    await _pump(tester, _Reader(policy: _policy));

    expect(
      find.byKey(const ValueKey('price-agreement-settings-read-only')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('price-agreement-settings-save')),
      findsNothing,
    );
    expect(_answerAsSet(tester, 'st-peter'), 'Can agree a price');
    expect(_answerAsSet(tester, 'st-grace'), 'Listed price only');
    expect(
      find.byKey(const ValueKey('price-agreement-allow-st-peter')),
      findsNothing,
      reason: 'the answer as text, not a control that looks editable',
    );
  });

  testWidgets('a manager is told the setting is not theirs', (tester) async {
    await _pump(
      tester,
      _Reader(policy: _policy),
      writer: _Writer(),
      role: TenantRole.manager,
    );

    expect(
      find.text(
        'Only an owner or administrator may decide who can agree a price.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('price-agreement-people')), findsNothing);
  });

  // The stock count page's defect, which this page copied: filled once, from
  // whichever answer came first, and this device's copy comes first.
  testWidgets('the server answer replaces an older copy on the form', (
    tester,
  ) async {
    final server = Completer<void>();
    await _pump(
      tester,
      _CachingReader(
        server: _Reader(policy: _onlyGrace, gate: server.future),
        cache: _Reader(policy: _policy),
      ),
      writer: _Writer(),
    );
    expect(_allowed(tester, 'st-peter'), isTrue);

    server.complete();
    await tester.pump();
    await tester.pump();

    expect(_allowed(tester, 'st-peter'), isFalse);
    expect(_allowed(tester, 'st-grace'), isTrue);
    expect(
      find.byKey(const ValueKey('price-agreement-settings-changed-elsewhere')),
      findsNothing,
    );
  });

  testWidgets('what the owner has changed is kept, and they are told', (
    tester,
  ) async {
    final server = Completer<void>();
    await _pump(
      tester,
      _CachingReader(
        server: _Reader(policy: _onlyGrace, gate: server.future),
        cache: _Reader(policy: _policy),
      ),
      writer: _Writer(),
    );
    await _choose(tester, _owner, 'yes');

    server.complete();
    await tester.pump();
    await tester.pump();

    expect(_allowed(tester, _owner), isTrue);
    expect(_allowed(tester, 'st-peter'), isTrue);
    expect(
      noticeAt(tester, 'price-agreement-settings-changed-elsewhere').status,
      AppStatus.attention,
    );
  });

  testWidgets('fits a phone', (tester) async {
    await _pump(
      tester,
      _Reader(policy: _policy),
      writer: _Writer(),
      size: const Size(411, 2600),
    );

    expect(tester.takeException(), isNull);
    final select = tester.getRect(
      find.byKey(const ValueKey('price-agreement-allow-st-peter')),
    );
    expect(select.right, lessThanOrEqualTo(411));
    expect(select.height, greaterThanOrEqualTo(48));
  });
}

// ---------------------------------------------------------------------------

Future<void> _pump(
  WidgetTester tester,
  TenantDataReader reader, {
  TenantConfigurationDocumentWriter? writer,
  TenantRole role = TenantRole.owner,
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
          ..open(uid: _owner, membership: _membership(role)),
        child: Scaffold(
          body: SingleChildScrollView(
            child: TenantPriceAgreementSettingsPanel(
              reader: reader,
              writer: writer,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// Opens one person's select and picks `yes` or `no`.
Future<void> _choose(WidgetTester tester, String uid, String answer) async {
  final select = find.byKey(ValueKey('price-agreement-allow-$uid'));
  await tester.ensureVisible(select);
  await tester.tap(select);
  await tester.pumpAndSettle();
  // The open menu draws its own copy of every item; the last is the menu's.
  await tester.tap(
    find.byKey(ValueKey('price-agreement-allow-$uid-$answer')).last,
    warnIfMissed: false,
  );
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  final save = find.byKey(const ValueKey('price-agreement-settings-save'));
  await tester.ensureVisible(save);
  await tester.tap(save);
  await tester.pump();
  await tester.pump();
}

/// Whether the select for [uid] currently answers yes.
bool _allowed(WidgetTester tester, String uid) => tester
    .widget<DropdownButton<bool>>(
      find.descendant(
        of: find.byKey(ValueKey('price-agreement-allow-$uid')),
        matching: find.byType(DropdownButton<bool>),
      ),
    )
    .value!;

String _answerAsSet(WidgetTester tester, String uid) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(ValueKey('price-agreement-as-set-$uid')),
        matching: find.byType(Text),
      ),
    )
    .data!;

String? _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data;

String _noteText(WidgetTester tester, String uid) {
  final texts = tester.widgetList<Text>(
    find.descendant(
      of: find.byKey(ValueKey('price-agreement-note-$uid')),
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

TenantMembership _membership(TenantRole role) => TenantMembership(
  tenantId: _tenant,
  tenantName: _tenant,
  tenantSlug: _tenant,
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

/// A reader with a copy on this device, as the Firestore-backed one has.
final class _CachingReader implements TenantCacheReadable {
  _CachingReader({required this.server, required this.cache});

  final _Reader server;
  final _Reader cache;

  @override
  TenantDataReader get cacheOnly => cache;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) =>
      server.getDocument(path);

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) => server.getCollectionPage(query);
}

final class _Reader implements TenantDataReader {
  _Reader({this.policy, this.gate});

  final Map<String, Object?>? policy;

  /// Holds the policy's answer back until it completes.
  final Future<void>? gate;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    if (path == _policyPath) await gate;
    final Map<String, Object?>? data = switch (path) {
      _root => <String, Object?>{
        'tenantId': _tenant,
        'name': _tenant,
        'status': 'active',
        'ownerUid': _owner,
      },
      _policyPath => policy,
      _ when path.startsWith('$_root/staff/') => _staff[path.split('/').last],
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
        for (final entry in _staff.entries)
          TenantQueryDocumentSnapshot(
            path: '$_root/staff/${entry.key}',
            data: entry.value,
          ),
      ],
      _ => const <TenantQueryDocumentSnapshot>[],
    };
    return tenantCollectionPageOf(query, documents);
  }
}
