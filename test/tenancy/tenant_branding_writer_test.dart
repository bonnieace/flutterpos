import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';


const String _path = 'tenants/tenant-a/configuration/branding';

TenantSession _session({TenantRole role = TenantRole.owner}) =>
    TenantSession.active(uid: 'user-a', tenantId: 'tenant-a', role: role);

TenantBrandingPublisher _publisher({
  Map<String, Object?>? stored,
  TenantRole role = TenantRole.owner,
}) => TenantBrandingPublisher(
  session: _session(role: role),
  reader: _Reader(
    stored == null
        ? const <String, Map<String, Object?>>{}
        : <String, Map<String, Object?>>{_path: stored},
  ),
);

Map<String, Object?> _stored({
  String companyName = 'Chilltent West',
  String? slogan = 'Cold things, fair prices',
  String? logoUrl = 'https://example.test/logo.png',
}) => <String, Object?>{
  'companyName': companyName,
  if (slogan != null) 'slogan': slogan,
  if (logoUrl != null) 'logoUrl': logoUrl,
};

void main() {
  group('reading what is published', () {
    test('an absent document is a state, not a failure', () async {
      expect(await _publisher().loadPublished(), isA<TenantPublishedBranding>());
      expect((await _publisher().loadPublished()).isUsable, isFalse);
    });

    test('a malformed document degrades rather than throwing', () async {
      // The home is titled from this. A business whose branding cannot be
      // parsed still has to open.
      final published = await _publisher(
        stored: <String, Object?>{'companyName': ''},
      ).loadPublished();

      expect(published.isUsable, isFalse);
      expect(published.branding, isNull);
    });

    test('a good document reads back whole', () async {
      final published = await _publisher(stored: _stored()).loadPublished();

      expect(published.isUsable, isTrue);
      expect(published.branding!.companyName, 'Chilltent West');
      expect(published.branding!.slogan, 'Cold things, fair prices');
      expect(published.branding!.logoUrl.toString(), contains('logo.png'));
    });
  });

  group('building a publish', () {
    test('normalizes what was typed', () async {
      final publisher = _publisher();
      final intent = publisher.buildUpdateIntent(
        companyName: '  Chilltent West  ',
        slogan: '   ',
        logoUrl: '  ',
        published: const TenantPublishedBranding.absent(),
      );

      expect(intent.companyName, 'Chilltent West');
      // Blank is not a slogan; it is the absence of one.
      expect(intent.slogan, isNull);
      expect(intent.logoUrl, isNull);
      expect(intent.path, _path);
    });

    test('writes nulls rather than omitting them, so clearing clears', () {
      // The write merges. A key left out of a merge leaves the old value
      // standing, which would make a slogan impossible to remove.
      final intent = _publisher().buildUpdateIntent(
        companyName: 'Chilltent West',
        published: const TenantPublishedBranding.absent(),
      );

      final document = intent.toDocument();
      expect(document.containsKey('slogan'), isTrue);
      expect(document['slogan'], isNull);
      expect(document.containsKey('logoUrl'), isTrue);
      expect(document['logoUrl'], isNull);
      expect(document['updatedBy'], 'user-a');
    });

    test('a nameless business is refused', () {
      expect(
        () => _publisher().buildUpdateIntent(
          companyName: '   ',
          published: const TenantPublishedBranding.absent(),
        ),
        throwsA(
          isA<TenantBrandingException>().having(
            (e) => e.code,
            'code',
            'missing_company_name',
          ),
        ),
      );
    });

    test('a name too long for a receipt header is refused here', () {
      expect(
        () => _publisher().buildUpdateIntent(
          companyName: 'a' * 61,
          published: const TenantPublishedBranding.absent(),
        ),
        throwsA(
          isA<TenantBrandingException>().having(
            (e) => e.code,
            'code',
            'company_name_too_long',
          ),
        ),
      );
    });

    test('a logo must be https, matching what the reader will accept', () {
      // A logo this published but `TenantBranding` refused to read would be
      // worse than one refused twice.
      for (final url in <String>[
        'http://example.test/logo.png',
        'ftp://example.test/logo.png',
        'https:///nohost',
        'not a url at all',
      ]) {
        expect(
          () => _publisher().buildUpdateIntent(
            companyName: 'Chilltent West',
            logoUrl: url,
            published: const TenantPublishedBranding.absent(),
          ),
          throwsA(
            isA<TenantBrandingException>().having(
              (e) => e.code,
              'code',
              'invalid_logo_url',
            ),
          ),
          reason: url,
        );
      }
    });

    test('republishing the identical details is refused', () {
      // It would rewrite the provenance and ask every device to re-read a
      // document that cannot have changed.
      expect(
        () => _publisher().buildUpdateIntent(
          companyName: 'Chilltent West',
          slogan: 'Cold things, fair prices',
          logoUrl: 'https://example.test/logo.png',
          published: TenantPublishedBranding.published(
            TenantBranding.fromMap(_stored()),
          ),
        ),
        throwsA(
          isA<TenantBrandingException>().having(
            (e) => e.code,
            'code',
            'branding_unchanged',
          ),
        ),
      );
    });

    test('a malformed document is never "unchanged"', () {
      // That is exactly the state this screen exists to leave.
      final intent = _publisher().buildUpdateIntent(
        companyName: 'Chilltent West',
        published: const TenantPublishedBranding.malformed(),
      );

      expect(intent.companyName, 'Chilltent West');
    });

    test('a manager may read the details and not publish them', () {
      expect(
        TenantBrandingPublisher.canPublishInSession(
          _session(role: TenantRole.manager),
        ),
        isFalse,
      );
      expect(
        () => _publisher(role: TenantRole.manager).buildUpdateIntent(
          companyName: 'Chilltent West',
          published: const TenantPublishedBranding.absent(),
        ),
        throwsA(
          isA<TenantBrandingException>().having(
            (e) => e.code,
            'code',
            'branding_forbidden',
          ),
        ),
      );
    });

    test('an owner and an administrator may publish', () {
      for (final role in <TenantRole>[TenantRole.owner, TenantRole.admin]) {
        expect(
          TenantBrandingPublisher.canPublishInSession(_session(role: role)),
          isTrue,
          reason: role.name,
        );
      }
    });
  });

  group('what a refusal says', () {
    test('every code has a sentence somebody wrote', () {
      for (final code in <String>[
        'branding_forbidden',
        'missing_company_name',
        'company_name_too_long',
        'slogan_too_long',
        'invalid_logo_url',
        'branding_unchanged',
        'something-unmapped',
      ]) {
        final message = tenantBrandingFailureMessage(
          TenantBrandingException(code),
        );
        expect(message, isNotEmpty, reason: code);
        expect(message, isNot(contains(code)), reason: code);
      }
    });

    test('anything that is not a branding refusal still gets a sentence', () {
      expect(
        tenantBrandingFailureMessage(StateError('raw')),
        contains('could not be saved'),
      );
    });
  });
}


/// The document reader the publisher reads through.
final class _Reader implements TenantDocumentReader {
  _Reader(this._documents);

  final Map<String, Map<String, Object?>> _documents;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    final data = _documents[path];
    return data == null ? null : TenantDocumentSnapshot(path: path, data: data);
  }
}
