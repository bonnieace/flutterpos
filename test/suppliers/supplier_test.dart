import 'package:uzapay_pos/suppliers/supplier.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a supplier form may send, and how the directory reads back.
///
/// Every refusal here mirrors one `functions/src/operations/suppliers.ts` makes,
/// so the cases are the server suite's cases: a supplier the device queues is
/// never refused for something the device could have caught.
void main() {
  group('the read model', () {
    test('a supplier with no standing recorded is active', () {
      final supplier = _supplier('sp_abc', name: 'ABC Distributors');

      expect(supplier.active, isTrue);
      expect(supplier.phone, isNull);
      expect(supplier.tenantId, 'tenant-a');
    });

    test('a contact field that is not text reads as nothing, not a refusal', () {
      // One malformed row must not empty a whole directory.
      final supplier = TenantSupplier.fromDocument(
        path: 'tenants/tenant-a/suppliers/sp_abc',
        data: const <String, Object?>{'name': 'ABC', 'phone': 712345678},
      );

      expect(supplier.phone, isNull);
    });

    test('a supplier with no name is refused, because nothing can list it', () {
      expect(
        () => TenantSupplier.fromDocument(
          path: 'tenants/tenant-a/suppliers/sp_abc',
          data: const <String, Object?>{'name': '  '},
        ),
        throwsFormatException,
      );
    });
  });

  group('normalizing what was typed', () {
    test('fields are trimmed and collapsed as the server stores them', () {
      final fields = const TenantSupplierDraft(
        name: '  ABC   Distributors ',
        phone: ' 0712 345 678 ',
        email: 'orders@abc.example',
        notes: '  Deliveries   Tuesdays \r\n ask for Peter  ',
      ).normalized();

      expect(fields[TenantSupplierField.name], 'ABC Distributors');
      expect(fields[TenantSupplierField.phone], '0712 345 678');
      expect(fields[TenantSupplierField.notes], 'Deliveries Tuesdays\nask for Peter');
      // Empty optional fields come back as nothing to store.
      expect(fields[TenantSupplierField.address], isNull);
    });

    test('what the server refuses is refused here, naming the field', () {
      final cases = <TenantSupplierField, String>{
        TenantSupplierField.name: '   ',
        TenantSupplierField.phone: 'call me',
        TenantSupplierField.email: 'not an address',
        TenantSupplierField.address: 'a' * 301,
        TenantSupplierField.taxReference: 'r' * 65,
        TenantSupplierField.notes: 'n' * 1001,
      };
      for (final entry in cases.entries) {
        expect(
          () => normalizeSupplierField(entry.key, entry.value),
          throwsA(isA<TenantSupplierException>()),
          reason: entry.key.name,
        );
      }
    });
  });

  group('adding a supplier', () {
    test('writes the document the server will hold, keyed by a digest', () {
      final intent = _repository().buildCreateIntent(
        draft: const TenantSupplierDraft(name: 'ABC Distributors', phone: '0712'),
        directory: _directory(const <TenantSupplier>[]),
        requestId: 'supplier-request-1',
      );

      expect(intent.supplierId, startsWith('sp_'));
      expect(intent.path, 'tenants/tenant-a/suppliers/${intent.supplierId}');
      expect(intent.documentData(), <String, Object?>{
        'name': 'ABC Distributors',
        'phone': '0712',
        'active': true,
        'createdBy': 'user-a',
      });
      // The same request names the same supplier, which is what lets a retry
      // answer off the server's own record.
      expect(
        _repository()
            .buildCreateIntent(
              draft: const TenantSupplierDraft(name: 'ABC Distributors'),
              directory: _directory(const <TenantSupplier>[]),
              requestId: 'supplier-request-1',
            )
            .supplierId,
        intent.supplierId,
      );
    });

    test('a name another supplier folds to is refused before it is queued', () {
      expect(
        () => _repository().buildCreateIntent(
          draft: const TenantSupplierDraft(name: 'abc  distributors'),
          directory: _directory(<TenantSupplier>[
            _supplier('sp_abc', name: 'ABC Distributors', active: false),
          ]),
          requestId: 'supplier-request-1',
        ),
        throwsA(_code('duplicate_supplier_name')),
      );
    });

    test('a cashier may not add one', () {
      expect(
        () => _repository(role: TenantRole.cashier).buildCreateIntent(
          draft: const TenantSupplierDraft(name: 'ABC'),
          directory: _directory(const <TenantSupplier>[]),
          requestId: 'supplier-request-1',
        ),
        throwsA(_code('supplier_forbidden')),
      );
    });
  });

  group('correcting a supplier', () {
    final stored = _supplier(
      'sp_abc',
      name: 'ABC Distributors',
      phone: '0712 345 678',
    );

    test('carries only what moves, and a cleared field as null', () {
      final intent = _repository().buildUpdateIntent(
        supplier: stored,
        draft: const TenantSupplierDraft(
          name: 'ABC Distributors',
          email: 'orders@abc.example',
        ),
        directory: _directory(<TenantSupplier>[stored]),
      );

      expect(intent.documentData(), <String, Object?>{
        'phone': null,
        'email': 'orders@abc.example',
      });
      expect(intent.operationId, startsWith('supplier-update-sp_abc-'));
    });

    test('its own capitalisation is not a duplicate of itself', () {
      final intent = _repository().buildUpdateIntent(
        supplier: stored,
        draft: const TenantSupplierDraft(
          name: 'abc distributors',
          phone: '0712 345 678',
        ),
        directory: _directory(<TenantSupplier>[stored]),
      );

      expect(intent.name, 'abc distributors');
    });

    test('another supplier\'s name is refused', () {
      expect(
        () => _repository().buildUpdateIntent(
          supplier: stored,
          draft: const TenantSupplierDraft(name: 'XYZ Wholesale'),
          directory: _directory(<TenantSupplier>[
            stored,
            _supplier('sp_xyz', name: 'XYZ Wholesale'),
          ]),
        ),
        throwsA(_code('duplicate_supplier_name')),
      );
    });

    test('a correction that moves nothing is refused', () {
      expect(
        () => _repository().buildUpdateIntent(
          supplier: stored,
          draft: TenantSupplierDraft.of(stored),
          directory: _directory(<TenantSupplier>[stored]),
        ),
        throwsA(_code('supplier_unchanged')),
      );
    });

    test('marking inactive sends the standing and nothing else', () {
      final intent = _repository().buildStandingIntent(
        supplier: stored,
        active: false,
      );

      expect(intent.documentData(), <String, Object?>{'active': false});
      expect(
        () => _repository().buildStandingIntent(supplier: stored, active: true),
        throwsA(_code('supplier_unchanged')),
      );
    });
  });

  group('the directory', () {
    test('reads alphabetically, and filters by standing and by name', () {
      final directory = _directory(<TenantSupplier>[
        _supplier('sp_3', name: 'mama njeri flour'),
        _supplier('sp_1', name: 'XYZ Wholesale', active: false),
        _supplier('sp_2', name: 'ABC Distributors'),
      ]);

      expect(directory.suppliers.map((supplier) => supplier.id), <String>[
        'sp_2',
        'sp_3',
        'sp_1',
      ]);
      expect(
        directory
            .filtered(standing: TenantSupplierStanding.active)
            .map((supplier) => supplier.id),
        <String>['sp_2', 'sp_3'],
      );
      expect(
        directory
            .filtered(standing: TenantSupplierStanding.all, search: 'FLOUR')
            .single
            .id,
        'sp_3',
      );
    });
  });
}

TenantSupplierRepository _repository({TenantRole role = TenantRole.owner}) =>
    TenantSupplierRepository(
      session: TenantSession.active(uid: 'user-a', tenantId: 'tenant-a', role: role),
      reader: const _NoReader(),
    );

TenantSupplierDirectory _directory(List<TenantSupplier> suppliers) =>
    TenantSupplierDirectory(suppliers: suppliers, truncated: false);

TenantSupplier _supplier(
  String id, {
  required String name,
  String? phone,
  bool active = true,
}) => TenantSupplier.fromDocument(
  path: 'tenants/tenant-a/suppliers/$id',
  data: <String, Object?>{
    'name': name,
    if (phone != null) 'phone': phone,
    if (!active) 'active': false,
  },
);

Matcher _code(String code) => isA<TenantSupplierException>().having(
  (error) => error.code,
  'code',
  code,
);

final class _NoReader implements TenantDataReader {
  const _NoReader();

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async => null;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async => const <TenantQueryDocumentSnapshot>[];
}
