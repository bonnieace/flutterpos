import 'dart:convert';
import 'dart:math';

import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SecureCheckoutOutboxEncryptionKeyProvider', () {
    test('creates, stores, and memoizes one 32-byte key', () async {
      final storage = _MemorySecureStore();
      final provider = SecureCheckoutOutboxEncryptionKeyProvider(
        storage: storage,
        random: Random(7),
      );

      final results = await Future.wait([
        provider.loadOrCreateKey(),
        provider.loadOrCreateKey(),
      ]);

      expect(results.first, hasLength(HiveCheckoutOutbox.encryptionKeyBytes));
      expect(results.last, results.first);
      expect(storage.writes, 1);
      expect(base64Url.decode(storage.values.values.single), results.first);
    });

    test('loads an existing key without replacing it', () async {
      final expected = List<int>.generate(32, (index) => 255 - index);
      final storage = _MemorySecureStore()
        ..values[SecureCheckoutOutboxEncryptionKeyProvider.storageKey] =
            base64UrlEncode(expected);
      final provider = SecureCheckoutOutboxEncryptionKeyProvider(
        storage: storage,
      );

      expect(await provider.loadOrCreateKey(), expected);
      expect(storage.writes, 0);
    });

    for (final invalid in <String>[
      'not-base64***',
      base64UrlEncode([1, 2]),
    ]) {
      test('fails closed for malformed stored key $invalid', () async {
        final storage = _MemorySecureStore()
          ..values[SecureCheckoutOutboxEncryptionKeyProvider.storageKey] =
              invalid;
        final provider = SecureCheckoutOutboxEncryptionKeyProvider(
          storage: storage,
        );

        await expectLater(
          provider.loadOrCreateKey(),
          throwsA(
            isA<CheckoutOutboxException>().having(
              (error) => error.code,
              'code',
              'invalid_stored_encryption_key',
            ),
          ),
        );
        expect(storage.writes, 0);
      });
    }

    test('propagates secure-storage write failure', () async {
      final storage = _MemorySecureStore()..writeError = StateError('locked');
      final provider = SecureCheckoutOutboxEncryptionKeyProvider(
        storage: storage,
        random: Random(1),
      );

      await expectLater(provider.loadOrCreateKey(), throwsStateError);
      expect(storage.values, isEmpty);
    });
  });
}

final class _MemorySecureStore implements CheckoutOutboxSecureValueStore {
  final Map<String, String> values = <String, String>{};
  int writes = 0;
  Object? writeError;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    writes += 1;
    if (writeError case final error?) throw error;
    values[key] = value;
  }
}
