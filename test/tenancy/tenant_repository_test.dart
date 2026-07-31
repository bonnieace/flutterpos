import 'package:flutter/material.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('branding repository derives the exact path from its session', () async {
    final reader = _FakeReader(
      response: TenantDocumentSnapshot(
        path: 'tenants/tenant-a/configuration/branding',
        data: const {
          'companyName': 'ChillTent Westlands',
          'slogan': 'Stay chilled',
          'logoUrl': 'https://example.test/logo.png',
        },
      ),
    );
    final branding = await TenantBrandingRepository(
      session: TenantSession.active(
        uid: 'user-a',
        tenantId: 'tenant-a',
        role: TenantRole.cashier,
      ),
      reader: reader,
    ).load();

    expect(reader.requestedPath, 'tenants/tenant-a/configuration/branding');
    expect(branding?.companyName, 'ChillTent Westlands');
    expect(branding?.slogan, 'Stay chilled');
    expect(branding?.logoUrl, Uri.parse('https://example.test/logo.png'));
  });

  test('a cross-tenant document response fails closed', () async {
    final repository = TenantBrandingRepository(
      session: TenantSession.active(
        uid: 'user-a',
        tenantId: 'tenant-a',
        role: TenantRole.admin,
      ),
      reader: _FakeReader(
        response: TenantDocumentSnapshot(
          path: 'tenants/tenant-b/configuration/branding',
          data: const {'companyName': 'Wrong tenant'},
        ),
      ),
    );

    await expectLater(repository.load(), throwsA(isA<TenantScopeViolation>()));
  });

  testWidgets('branding slice renders through the tenant route guard', (
    tester,
  ) async {
    final controller = TenantSessionController()
      ..open(uid: 'user-a', membership: _membership('tenant-a'));
    final reader = _FakeReader(
      response: TenantDocumentSnapshot(
        path: 'tenants/tenant-a/configuration/branding',
        data: const {
          'companyName': 'Tenant A Bar',
          'slogan': 'Cold drinks, warm welcome',
        },
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TenantSessionScope(
          controller: controller,
          child: Scaffold(
            body: TenantBrandingPanel(
              reader: reader,
              fallbackName: 'Fallback name',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Tenant A Bar'), findsOneWidget);
    expect(find.text('Cold drinks, warm welcome'), findsOneWidget);
    expect(find.text('Signed in as admin'), findsOneWidget);
  });

  group('bounded collection filters', () {
    test('passes only simple field equality to the reader', () async {
      final reader = _FakeCollectionReader();

      await _FilteredRepository().page(reader, <String, Object?>{
        'staffId': 'user-a',
        'status': 'open',
      });

      expect(reader.query!.collectionPath, 'tenants/tenant-a/shifts');
      expect(reader.query!.equalityFilters, <String, Object?>{
        'staffId': 'user-a',
        'status': 'open',
      });
      expect(reader.query!.limit, 21);
    });

    test('refuses a filter that is not a bounded document field', () async {
      final reader = _FakeCollectionReader();
      final repository = _FilteredRepository();
      final refused = <String, Map<String, Object?>>{
        'nested-path': <String, Object?>{'shift.staffId': 'user-a'},
        'document-id': <String, Object?>{'__name__': 'shift-a'},
        'path-escape': <String, Object?>{'tenants/x': 'user-a'},
        'empty-value': <String, Object?>{'staffId': ''},
        'unbounded-value': <String, Object?>{'staffId': <String>['user-a']},
        'too-many': <String, Object?>{
          'a': 1,
          'b': 2,
          'c': 3,
          'd': 4,
          'e': 5,
        },
      };

      for (final entry in refused.entries) {
        await expectLater(
          repository.page(reader, entry.value),
          throwsArgumentError,
          reason: entry.key,
        );
      }
      expect(reader.query, isNull);
    });
  });
}

/// Exposes the guarded collection boundary so its filter contract can be
/// proved directly; production repositories choose their own filters.
final class _FilteredRepository extends TenantReadRepository {
  _FilteredRepository()
    : super(
        session: TenantSession.active(
          uid: 'user-a',
          tenantId: 'tenant-a',
          role: TenantRole.cashier,
        ),
        reader: _FakeReader(response: null),
      );

  Future<TenantDocumentPage> page(
    TenantCollectionReader reader,
    Map<String, Object?> filters,
  ) => readCollectionPage(
    TenantCollection.shifts,
    collectionReader: reader,
    equalityFilters: filters,
  );
}

final class _FakeCollectionReader implements TenantCollectionReader {
  TenantCollectionQuery? query;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery request,
  ) async {
    query = request;
    return const <TenantQueryDocumentSnapshot>[];
  }
}

final class _FakeReader implements TenantDocumentReader {
  _FakeReader({required this.response});

  final TenantDocumentSnapshot? response;
  String? requestedPath;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    requestedPath = path;
    return response;
  }
}

TenantMembership _membership(String tenantId) => TenantMembership(
  tenantId: tenantId,
  tenantName: tenantId,
  tenantSlug: tenantId,
  role: TenantRole.admin,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  isOwner: false,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 7, 29),
  updatedAt: DateTime.utc(2026, 7, 29),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);
