import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves canonical names and reads each staff record once', () async {
    final reader = _Reader(<String, Map<String, Object?>>{
      'tenants/tenant-a/staff/user-a': _staff('user-a', 'Amina'),
      'tenants/tenant-a/staff/user-b': _staff('user-b', 'Brian'),
    });
    final resolver = _resolver(reader);

    final first = await resolver.resolve(<String>['user-a', 'user-b', 'user-a']);
    final second = await resolver.resolve(<String>['user-a', 'user-b']);

    expect(first, <String, String>{'user-a': 'Amina', 'user-b': 'Brian'});
    expect(second, first);
    expect(reader.requested, <String>[
      'tenants/tenant-a/staff/user-a',
      'tenants/tenant-a/staff/user-b',
    ]);
  });

  test('an unreadable or missing record degrades to the UID', () async {
    final reader = _Reader(<String, Map<String, Object?>>{
      'tenants/tenant-a/staff/user-a': _staff('user-a', 'Amina'),
    }, denied: <String>{'tenants/tenant-a/staff/user-b'});
    final resolver = _resolver(reader);

    final names = await resolver.resolve(<String>[
      'user-a',
      'user-b',
      'user-missing',
    ]);

    expect(names, <String, String>{'user-a': 'Amina'});
    expect(
      tenantStaffLabel('user-b', names: names),
      'user-b',
      reason: 'the UID stays the authoritative identity',
    );
    // A denied read is not retried on the next page.
    await resolver.resolve(<String>['user-b']);
    expect(
      reader.requested.where((path) => path.endsWith('user-b')).length,
      1,
    );
  });

  test('a record that names another UID or no name resolves to nothing', () async {
    final reader = _Reader(<String, Map<String, Object?>>{
      'tenants/tenant-a/staff/user-a': _staff('user-b', 'Impostor'),
      'tenants/tenant-a/staff/user-b': _staff('user-b', null),
      'tenants/tenant-a/staff/user-c': _staff('user-c', '   '),
      'tenants/tenant-a/staff/user-d': _staff('user-d', 'Bad\u0007Name'),
      'tenants/tenant-a/staff/user-e': <String, Object?>{
        'uid': 'user-e',
        // The record carries contact details; a history row never shows them.
        'email': 'e@example.test',
        'phone': '+254700000000',
      },
    });

    final names = await _resolver(reader).resolve(<String>[
      'user-a',
      'user-b',
      'user-c',
      'user-d',
      'user-e',
    ]);

    expect(names, isEmpty);
  });

  test('a cross-tenant staff response still fails closed', () async {
    final reader = _Reader(<String, Map<String, Object?>>{
      'tenants/tenant-a/staff/user-a': _staff('user-a', 'Amina'),
    }, responsePath: 'tenants/tenant-b/staff/user-a');

    await expectLater(
      _resolver(reader).resolve(<String>['user-a']),
      throwsA(isA<TenantScopeViolation>()),
    );
  });

  test('resolution is bounded and the remainder shows UIDs', () async {
    final uids = <String>[
      for (var index = 0; index < 40; index++) 'user-$index',
    ];
    final reader = _Reader(<String, Map<String, Object?>>{
      for (final uid in uids)
        'tenants/tenant-a/staff/$uid': _staff(uid, 'Name $uid'),
    });

    final names = await _resolver(reader).resolve(uids);

    expect(
      reader.requested.length,
      TenantStaffNameResolver.maximumResolvedUids,
    );
    expect(names.length, TenantStaffNameResolver.maximumResolvedUids);
  });

  test('an invalid UID is skipped rather than requested', () async {
    final reader = _Reader(const <String, Map<String, Object?>>{});

    final names = await _resolver(reader).resolve(<String>['', 'a/b', '  ']);

    expect(names, isEmpty);
    expect(reader.requested, isEmpty);
  });

  test('a label keeps the UID visible beside a resolved name', () {
    const names = <String, String>{'user-a': 'Amina', 'user-b': 'Brian'};

    expect(
      tenantStaffLabel('user-b', names: names, selfUid: 'user-a'),
      'Brian (user-b)',
    );
    expect(
      tenantStaffLabel('user-a', names: names, selfUid: 'user-a'),
      'You (Amina)',
    );
    expect(
      tenantStaffLabel('user-c', names: names, selfUid: 'user-c'),
      'You',
    );
  });
}

TenantStaffNameResolver _resolver(_Reader reader) => TenantStaffNameResolver(
  session: TenantSession.active(
    uid: 'user-a',
    tenantId: 'tenant-a',
    role: TenantRole.cashier,
  ),
  reader: reader,
);

Map<String, Object?> _staff(String uid, String? name) => <String, Object?>{
  'uid': uid,
  'role': 'cashier',
  'status': 'active',
  if (name != null) 'name': name,
};

final class _Reader implements TenantDocumentReader {
  _Reader(this._documents, {this.responsePath, this.denied = const <String>{}});

  final Map<String, Map<String, Object?>> _documents;
  final String? responsePath;
  final Set<String> denied;
  final List<String> requested = <String>[];

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    requested.add(path);
    if (denied.contains(path)) {
      throw StateError('permission-denied');
    }
    final data = _documents[path];
    return data == null
        ? null
        : TenantDocumentSnapshot(path: responsePath ?? path, data: data);
  }
}
