import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'checkout_outbox.dart';

abstract interface class CheckoutOutboxSecureValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);
}

final class FlutterSecureCheckoutOutboxValueStore
    implements CheckoutOutboxSecureValueStore {
  const FlutterSecureCheckoutOutboxValueStore(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

/// Loads one device-local AES key from platform secure storage.
///
/// A corrupt stored key fails closed and is never silently replaced, because
/// replacement would make existing encrypted checkout evidence unreadable.
final class SecureCheckoutOutboxEncryptionKeyProvider
    implements CheckoutOutboxEncryptionKeyProvider {
  SecureCheckoutOutboxEncryptionKeyProvider({
    required CheckoutOutboxSecureValueStore storage,
    Random? random,
    String storageKey = SecureCheckoutOutboxEncryptionKeyProvider.storageKey,
  }) : _storage = storage,
       _random = random ?? Random.secure(),
       _storageKey = storageKey {
    if (storageKey.isEmpty || storageKey != storageKey.trim()) {
      throw ArgumentError.value(storageKey, 'storageKey');
    }
  }

  /// Versioned secure-storage name of the checkout outbox key.
  static const storageKey = 'checkout-outbox-aes-key-v1';

  /// Versioned secure-storage name of the offline catalog cache key.
  ///
  /// The cache is derived, replaceable data while the outbox holds sale
  /// evidence, so the two boxes deliberately never share one key.
  static const catalogCacheStorageKey = 'checkout-catalog-cache-aes-key-v1';

  /// Versioned secure-storage name of the durable print job key.
  ///
  /// **Its own key for the same reason the catalog cache has one.** A print job
  /// is derived data: the bytes are rebuilt from a sale that is already durable,
  /// and the job is keyed on the receipt number that sale carries, so losing
  /// this key costs a re-queue rather than a record of a sale. Sharing the
  /// outbox's key would tie evidence's fate to a receipt's.
  static const printJobsStorageKey = 'checkout-print-jobs-aes-key-v1';

  final CheckoutOutboxSecureValueStore _storage;
  final Random _random;
  final String _storageKey;
  Future<List<int>>? _pending;

  @override
  Future<List<int>> loadOrCreateKey() => _pending ??= _loadOrCreate();

  Future<List<int>> _loadOrCreate() async {
    final encoded = await _storage.read(_storageKey);
    if (encoded != null) {
      try {
        final key = base64Url.decode(encoded);
        if (key.length != HiveCheckoutOutbox.encryptionKeyBytes) {
          throw const FormatException();
        }
        return List<int>.unmodifiable(key);
      } catch (_) {
        throw const CheckoutOutboxException('invalid_stored_encryption_key');
      }
    }

    final key = List<int>.generate(
      HiveCheckoutOutbox.encryptionKeyBytes,
      (_) => _random.nextInt(256),
      growable: false,
    );
    await _storage.write(_storageKey, base64UrlEncode(key));
    return List<int>.unmodifiable(key);
  }
}
