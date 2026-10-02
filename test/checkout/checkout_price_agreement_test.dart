import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/collection_pages.dart';

/// Who may sell for a price agreed with the customer.
///
/// **The defaults are the important part.** Since 2026-10-02 nothing
/// configured lets everyone agree a price, and the setting is who it is
/// switched off for. Nothing *readable* still allows nobody, so a corrupt
/// setting can never become a way to sell below the listed price.
void main() {
  group('when nothing is configured', () {
    test('nothing published lets everyone agree a price', () {
      const absent = TenantPublishedPriceAgreement.absent();
      expect(absent.policy.allows('user-a'), isTrue);
      expect(absent.policy.allows('owner'), isTrue);
      expect(absent.published, isNull);
      expect(TenantPriceAgreementPolicy.everybody.allows('anyone'), isTrue);
    });

    test('a malformed document allows nobody, never a guess', () {
      const malformed = TenantPublishedPriceAgreement.malformed();
      expect(malformed.policy.allows('user-a'), isFalse);
      expect(malformed.state, TenantPriceAgreementState.malformed);
      expect(TenantPriceAgreementPolicy.none.allows('owner'), isFalse);
    });
  });

  group('reading the document', () {
    test('round-trips through the shape the server stores', () {
      final parsed = TenantPriceAgreementPolicy.fromMap(<String, Object?>{
        'allowed': <Map<String, Object?>>[
          <String, Object?>{'uid': 'user-b'},
          <String, Object?>{'uid': 'user-a'},
        ],
      });

      expect(parsed.allows('user-a'), isTrue);
      expect(parsed.allows('user-b'), isTrue);
      expect(parsed.allows('user-c'), isFalse);

      final written = parsed.documentData(updatedBy: 'owner');
      expect(
        written['allowed'],
        <Map<String, Object?>>[
          <String, Object?>{'uid': 'user-a'},
          <String, Object?>{'uid': 'user-b'},
        ],
        reason: 'sorted, so an unchanged list writes an unchanged document',
      );
      expect(written['updatedBy'], 'owner');
      expect(TenantPriceAgreementPolicy.fromMap(written), parsed);
    });

    test('the current shape names who it is switched off for', () {
      final parsed = TenantPriceAgreementPolicy.fromMap(<String, Object?>{
        'everyone': true,
        'blocked': <Map<String, Object?>>[
          <String, Object?>{'uid': 'user-b'},
        ],
        'allowed': <Map<String, Object?>>[
          <String, Object?>{'uid': 'user-a'},
        ],
      });

      expect(parsed.allows('user-a'), isTrue);
      expect(parsed.allows('user-b'), isFalse);
      // Somebody nobody has decided about yet may.
      expect(parsed.allows('user-c'), isTrue);

      final written = parsed.documentData(
        updatedBy: 'owner',
        members: const <String>['user-a', 'user-b', 'user-c'],
      );
      expect(written['everyone'], isTrue);
      expect(written['blocked'], <Map<String, Object?>>[
        <String, Object?>{'uid': 'user-b'},
      ]);
      // What a build from before the change reads: the same answer for each.
      expect(written['allowed'], <Map<String, Object?>>[
        <String, Object?>{'uid': 'user-a'},
        <String, Object?>{'uid': 'user-c'},
      ]);
      expect(TenantPriceAgreementPolicy.fromMap(written), parsed);
    });

    test('a list saved under the first rule still means only those people', () {
      final legacy = TenantPriceAgreementPolicy.fromMap(<String, Object?>{
        'allowed': <Map<String, Object?>>[
          <String, Object?>{'uid': 'user-a'},
        ],
      });
      expect(legacy.everyone, isFalse);
      expect(legacy.allows('user-a'), isTrue);
      expect(legacy.allows('user-b'), isFalse);
    });

    test('an unknown field is ignored, a known one must be right', () {
      expect(
        TenantPriceAgreementPolicy.fromMap(<String, Object?>{
          'allowed': const <Object>[],
          'somethingLaterAdded': 42,
        }).allowed,
        isEmpty,
      );

      for (final broken in <Map<String, Object?>>[
        <String, Object?>{},
        <String, Object?>{'allowed': 'user-a'},
        <String, Object?>{'everyone': true},
        <String, Object?>{'everyone': true, 'blocked': 'user-a'},
        <String, Object?>{
          'allowed': const <Object>['user-a'],
        },
        <String, Object?>{
          'allowed': const <Map<String, Object?>>[<String, Object?>{}],
        },
        <String, Object?>{
          'allowed': const <Map<String, Object?>>[
            <String, Object?>{'uid': ''},
          ],
        },
      ]) {
        expect(
          () => TenantPriceAgreementPolicy.fromMap(broken),
          throwsA(isA<FormatException>()),
          reason: '$broken',
        );
      }
    });

    test('an unbounded list is refused', () {
      expect(
        () => TenantPriceAgreementPolicy(
          allowed: <String>{
            for (var i = 0; i <= maximumPriceAgreementPeople; i++) 'user-$i',
          },
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('the repository reads a malformed document as malformed', () async {
      final session = _session(TenantRole.cashier);
      final published = await TenantPriceAgreementRepository(
        session: session,
        reader: _Reader(<String, Object?>{'allowed': 'everyone'}),
      ).load();

      expect(published.state, TenantPriceAgreementState.malformed);
      expect(published.policy.allows(session.uid), isFalse);
    });

    test('the repository reads a missing document as absent', () async {
      final published = await TenantPriceAgreementRepository(
        session: _session(TenantRole.cashier),
        reader: _Reader(null),
      ).load();

      expect(published.state, TenantPriceAgreementState.absent);
    });
  });

  group('publishing', () {
    test('only an owner or administrator may publish', () {
      expect(
        () =>
            TenantPriceAgreementPublisher(
              session: _session(TenantRole.manager),
              reader: _Reader(null),
            ).buildIntent(
              blocked: const <String>{'user-a'},
              published: const TenantPublishedPriceAgreement.absent(),
            ),
        throwsA(
          isA<TenantPriceAgreementException>().having(
            (error) => error.code,
            'code',
            'price_agreement_forbidden',
          ),
        ),
      );
    });

    test('writes the configuration document with its provenance', () {
      final intent =
          TenantPriceAgreementPublisher(
            session: _session(TenantRole.owner),
            reader: _Reader(null),
          ).buildIntent(
            blocked: const <String>{'user-b'},
            members: const <String>{'user-a', 'user-b'},
            published: const TenantPublishedPriceAgreement.absent(),
          );

      expect(intent.path, 'tenants/tenant-a/configuration/price_agreement');
      expect(intent.documentData(), <String, Object?>{
        'everyone': true,
        'blocked': <Map<String, Object?>>[
          <String, Object?>{'uid': 'user-b'},
        ],
        'allowed': <Map<String, Object?>>[
          <String, Object?>{'uid': 'user-a'},
        ],
        'updatedBy': 'owner',
      });
    });

    test('re-saving what is published is refused, in any order', () {
      expect(
        () =>
            TenantPriceAgreementPublisher(
              session: _session(TenantRole.owner),
              reader: _Reader(null),
            ).buildIntent(
              blocked: const <String>{'user-b', 'user-a'},
              published: TenantPublishedPriceAgreement.published(
                TenantPriceAgreementPolicy.everyoneExcept(
                  const <String>{'user-a', 'user-b'},
                ),
              ),
            ),
        throwsA(
          isA<TenantPriceAgreementException>().having(
            (error) => error.code,
            'code',
            'policy_unchanged',
          ),
        ),
      );
    });
  });
}

TenantSession _session(TenantRole role) => TenantSession.active(
  uid: role == TenantRole.owner ? 'owner' : 'user-a',
  tenantId: 'tenant-a',
  role: role,
);

final class _Reader implements TenantDataReader {
  _Reader(this.policy);

  final Map<String, Object?>? policy;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    final data = path == 'tenants/tenant-a/configuration/price_agreement'
        ? policy
        : null;
    return data == null ? null : TenantDocumentSnapshot(path: path, data: data);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async =>
      tenantCollectionPageOf(query, const <TenantQueryDocumentSnapshot>[]);
}
