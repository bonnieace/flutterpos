import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uzapay_pos/checkout/checkout_configuration.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

const String _configurationPath = 'tenants/tenant-a/configuration/checkout';

void main() {
  group('published configuration', () {
    test('a usable document is what lets a till price a sale', () async {
      final reader = _Reader(<String, Map<String, Object?>>{
        _configurationPath: <String, Object?>{'currency': 'KES'},
      });

      final published = await _publisher(reader: reader).loadPublished();

      expect(published.state, TenantPublishedConfigurationState.published);
      expect(published.currency, 'KES');
      expect(published.canSell, isTrue);
      // The exact document, addressed by path. Nothing here searches the
      // configuration collection.
      expect(reader.requested.single, _configurationPath);
    });

    test('an absent document is a state, not a failure', () async {
      final published = await _publisher(
        reader: _Reader(const <String, Map<String, Object?>>{}),
      ).loadPublished();

      expect(published.state, TenantPublishedConfigurationState.absent);
      expect(published.currency, isNull);
      expect(published.canSell, isFalse);
    });

    test('a malformed document is readable here and nowhere else', () async {
      // The strict read model the till uses refuses this document outright, so
      // the business cannot sell at all. The one person who can correct it must
      // still be able to see it rather than be shown the cashier's refusal.
      final reader = _Reader(<String, Map<String, Object?>>{
        _configurationPath: <String, Object?>{'currency': 42},
      });

      final published = await _publisher(reader: reader).loadPublished();

      expect(published.state, TenantPublishedConfigurationState.malformed);
      expect(published.canSell, isFalse);
      await expectLater(
        TenantCheckoutConfigurationRepository(
          session: _session(),
          reader: reader,
        ).load(),
        throwsA(isA<FormatException>()),
      );
    });

    test('a lowercase stored code is malformed rather than corrected', () async {
      // Reading is never a repair: the till would otherwise price a sale with a
      // code no rule and no report agrees about.
      final published = await _publisher(
        reader: _Reader(<String, Map<String, Object?>>{
          _configurationPath: <String, Object?>{'currency': 'kes'},
        }),
      ).loadPublished();

      expect(published.state, TenantPublishedConfigurationState.malformed);
    });

    test('a response outside this business fails closed', () async {
      final reader = _Reader(<String, Map<String, Object?>>{
        _configurationPath: <String, Object?>{'currency': 'KES'},
      }, responsePath: 'tenants/tenant-b/configuration/checkout');

      await expectLater(
        _publisher(reader: reader).loadPublished(),
        throwsA(isA<TenantScopeViolation>()),
      );
    });
  });

  group('publish intent', () {
    test('writes exactly the currency and its provenance', () {
      final intent = _intent(currency: 'KES');

      expect(intent.path, _configurationPath);
      expect(intent.tenantId, 'tenant-a');
      expect(intent.currency, 'KES');
      // `updatedAt` is deliberately absent: the writer adds a server timestamp,
      // so a device clock never decides when this changed.
      expect(intent.documentData(), <String, Object?>{
        'currency': 'KES',
        'updatedBy': 'user-a',
      });
    });

    test('an ISO code has one casing, so a spelling is normalized', () {
      expect(_intent(currency: ' kes ').currency, 'KES');
      expect(_intent(currency: 'Ugx').currency, 'UGX');
    });

    test('anything that is not three letters is refused', () {
      for (final value in <String>['', 'KE', 'KESH', 'K1S', 'KE-', 'K S']) {
        expect(
          () => _intent(currency: value),
          _code('invalid_currency'),
          reason: value,
        );
      }
    });

    test('only an owner or administrator may publish', () {
      for (final role in <TenantRole>[TenantRole.owner, TenantRole.admin]) {
        expect(_intent(currency: 'KES', role: role).currency, 'KES');
      }
      // A manager runs a till and corrects stock. Deciding what the business
      // trades in is not an operational act, and the Firestore rule agrees.
      for (final role in <TenantRole>[TenantRole.manager, TenantRole.cashier]) {
        expect(
          () => _intent(currency: 'KES', role: role),
          _code('configuration_forbidden'),
          reason: role.name,
        );
      }
    });

    test('republishing the identical published code is refused', () {
      expect(
        () => _intent(
          currency: 'kes',
          published: TenantPublishedCheckoutConfiguration.published(_kes),
        ),
        _code('currency_unchanged'),
      );
    });

    test('a malformed or absent document is never "unchanged"', () {
      // Both states stop every sale in the business, and republishing is exactly
      // how each is cleared.
      for (final published in <TenantPublishedCheckoutConfiguration>[
        const TenantPublishedCheckoutConfiguration.absent(),
        const TenantPublishedCheckoutConfiguration.malformed(),
      ]) {
        final intent = _intent(currency: 'KES', published: published);
        expect(intent.currency, 'KES');
        // Nothing usable is being replaced, so there is nothing to warn about.
        expect(intent.changesPublishedCurrency, isFalse);
      }
    });

    test('replacing a usable code is the one case that warns', () {
      final intent = _intent(
        currency: 'UGX',
        published: TenantPublishedCheckoutConfiguration.published(_kes),
      );

      expect(intent.changesPublishedCurrency, isTrue);
      expect(intent.replaces.currency, 'KES');
    });
  });

  group('configuration writer', () {
    test('merges the named keys and a server timestamp', () async {
      final writer = _RecordingWriter();

      final result = await writer.build().publish(_intent(currency: 'KES'));

      expect(result.kind, TenantCheckoutConfigurationWriteKind.committed);
      expect(writer.paths.single, _configurationPath);
      // A whole-document write from this build would delete a later setting this
      // one knows nothing about, which the strict read model deliberately
      // ignores rather than refuses.
      expect(writer.merged.single.keys, <String>[
        'currency',
        'updatedBy',
        'updatedAt',
      ]);
      expect(writer.merged.single['currency'], 'KES');
      expect(writer.merged.single['updatedAt'], isA<FieldValue>());
    });

    test('an offline device attempts nothing at all', () async {
      final writer = _RecordingWriter();

      final result = await writer
          .build(online: false)
          .publish(_intent(currency: 'KES'));

      expect(result.kind, TenantCheckoutConfigurationWriteKind.unavailable);
      expect(writer.paths, isEmpty);
    });

    test('a failing connectivity check counts as offline', () async {
      final writer = _RecordingWriter();

      final result = await writer
          .build(onlineCheck: () => Future<bool>.error(StateError('no radio')))
          .publish(_intent(currency: 'KES'));

      expect(result.kind, TenantCheckoutConfigurationWriteKind.unavailable);
      expect(writer.paths, isEmpty);
    });

    test('a refusal the server proved is rejected, not retried', () async {
      for (final code in <String>[
        'permission-denied',
        'unauthenticated',
        'invalid-argument',
        'failed-precondition',
      ]) {
        final result = await _RecordingWriter()
            .build(
              error: FirebaseException(plugin: 'firestore', code: code),
            )
            .publish(_intent(currency: 'KES'));

        expect(
          result.kind,
          TenantCheckoutConfigurationWriteKind.rejected,
          reason: code,
        );
        expect(result.reasonCode, code);
      }
    });

    test('an unproven outcome is ambiguous, never rejected', () async {
      final unavailable = await _RecordingWriter()
          .build(
            error: FirebaseException(plugin: 'firestore', code: 'unavailable'),
          )
          .publish(_intent(currency: 'KES'));
      expect(unavailable.kind, TenantCheckoutConfigurationWriteKind.ambiguous);
      expect(unavailable.reasonCode, 'unavailable');

      final unknown = await _RecordingWriter()
          .build(error: StateError('transport closed'))
          .publish(_intent(currency: 'KES'));
      expect(unknown.kind, TenantCheckoutConfigurationWriteKind.ambiguous);
      expect(unknown.reasonCode, 'unknown_error');
    });

    test('a write that never answers is ambiguous', () async {
      final result = await FirebaseTenantCheckoutConfigurationWriter.forTesting(
        merge: (_, _) => Completer<void>().future,
        isOnline: () async => true,
        writeTimeout: const Duration(milliseconds: 20),
      ).publish(_intent(currency: 'KES'));

      expect(result.kind, TenantCheckoutConfigurationWriteKind.ambiguous);
      expect(result.reasonCode, 'write_timeout');
    });

    test('the write path is re-derived from the intent\'s own business', () async {
      // The writer never trusts the path it was handed: it rebuilds it from the
      // intent's tenant and refuses a disagreement. Only the publisher can build
      // an intent, and it takes both from one session, so the two can only ever
      // agree - which is what this proves for a second business.
      final writer = _RecordingWriter();

      final result = await writer.build().publish(_otherTenantIntent());

      expect(result.kind, TenantCheckoutConfigurationWriteKind.committed);
      expect(writer.paths.single, 'tenants/tenant-b/configuration/checkout');
    });

    test('a non-positive write timeout is a programming error', () {
      expect(
        () => FirebaseTenantCheckoutConfigurationWriter.forTesting(
          merge: (_, _) async {},
          isOnline: () async => true,
          writeTimeout: Duration.zero,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

final TenantCheckoutConfiguration _kes = TenantCheckoutConfiguration(
  currency: 'KES',
);

TenantCheckoutConfigurationPublisher _publisher({
  required TenantDocumentReader reader,
  TenantRole role = TenantRole.owner,
}) => TenantCheckoutConfigurationPublisher(
  session: _session(role: role),
  reader: reader,
);

TenantSession _session({TenantRole role = TenantRole.owner}) =>
    TenantSession.active(uid: 'user-a', tenantId: 'tenant-a', role: role);

TenantCheckoutConfigurationUpdateIntent _intent({
  required String currency,
  TenantRole role = TenantRole.owner,
  TenantPublishedCheckoutConfiguration published =
      const TenantPublishedCheckoutConfiguration.absent(),
}) => _publisher(
  reader: _Reader(const <String, Map<String, Object?>>{}),
  role: role,
).buildUpdateIntent(currency: currency, published: published);

/// An intent built from a second business's session, used to prove the writer
/// derives its path from the intent rather than from anything ambient.
TenantCheckoutConfigurationUpdateIntent _otherTenantIntent() =>
    TenantCheckoutConfigurationPublisher(
      session: TenantSession.active(
        uid: 'user-a',
        tenantId: 'tenant-b',
        role: TenantRole.owner,
      ),
      reader: _Reader(const <String, Map<String, Object?>>{}),
    ).buildUpdateIntent(
      currency: 'KES',
      published: const TenantPublishedCheckoutConfiguration.absent(),
    );

Matcher _code(String code) => throwsA(
  isA<TenantCheckoutConfigurationException>().having(
    (error) => error.code,
    'code',
    code,
  ),
);

final class _RecordingWriter {
  final List<String> paths = <String>[];
  final List<Map<String, Object?>> merged = <Map<String, Object?>>[];

  FirebaseTenantCheckoutConfigurationWriter build({
    bool online = true,
    Object? error,
    Future<bool> Function()? onlineCheck,
  }) => FirebaseTenantCheckoutConfigurationWriter.forTesting(
    merge: (path, data) {
      paths.add(path);
      merged.add(data);
      return error == null ? Future<void>.value() : Future<void>.error(error);
    },
    isOnline: onlineCheck ?? () async => online,
  );
}

final class _Reader implements TenantDocumentReader {
  _Reader(this._documents, {this.responsePath});

  final Map<String, Map<String, Object?>> _documents;

  /// Stands in for a transport that answers with another business's document.
  final String? responsePath;

  final List<String> requested = <String>[];

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    requested.add(path);
    final data = _documents[path];
    return data == null
        ? null
        : TenantDocumentSnapshot(path: responsePath ?? path, data: data);
  }
}
