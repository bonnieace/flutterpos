import 'dart:math';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import '../tenancy/tenant_id.dart';

const int maximumTenantProductImageBytes = 5 * 1024 * 1024;

enum TenantProductImageType {
  jpeg('image/jpeg', 'jpg'),
  png('image/png', 'png'),
  webp('image/webp', 'webp');

  const TenantProductImageType(this.contentType, this.extension);

  final String contentType;
  final String extension;
}

final class TenantProductImageCandidate {
  TenantProductImageCandidate({
    required Uint8List bytes,
    required this.fileName,
  }) : bytes = Uint8List.fromList(bytes),
       type = _validatedType(bytes);

  final Uint8List bytes;
  final String fileName;
  final TenantProductImageType type;
}

final class TenantProductImageUpload {
  const TenantProductImageUpload({required this.url, required this.objectPath});

  final Uri url;
  final String objectPath;
}

final class TenantProductImageException implements Exception {
  const TenantProductImageException(this.code);

  final String code;

  @override
  String toString() => 'TenantProductImageException($code)';
}

abstract interface class TenantProductImageStore {
  Future<TenantProductImageUpload> upload({
    required String tenantId,
    required String productId,
    required TenantProductImageCandidate candidate,
  });

  /// Removes [imageUrl] only when it resolves inside this product's owned path.
  Future<void> removeOwned({
    required String tenantId,
    required String productId,
    required Uri imageUrl,
  });
}

final class FirebaseTenantProductImageStore implements TenantProductImageStore {
  FirebaseTenantProductImageStore({FirebaseStorage? storage, Random? random})
    : _storage = storage ?? FirebaseStorage.instance,
      _random = random ?? Random.secure();

  final FirebaseStorage _storage;
  final Random _random;

  @override
  Future<TenantProductImageUpload> upload({
    required String tenantId,
    required String productId,
    required TenantProductImageCandidate candidate,
  }) async {
    validateTenantId(tenantId);
    validateTenantDocumentId(productId, fieldName: 'productId');
    final objectPath =
        '${_ownedPrefix(tenantId, productId)}${_uniqueId()}.${candidate.type.extension}';
    try {
      final reference = _storage.ref(objectPath);
      await reference.putData(
        candidate.bytes,
        SettableMetadata(
          contentType: candidate.type.contentType,
          customMetadata: <String, String>{
            'tenantId': tenantId,
            'productId': productId,
          },
        ),
      );
      return TenantProductImageUpload(
        url: Uri.parse(await reference.getDownloadURL()),
        objectPath: objectPath,
      );
    } on FirebaseException catch (error) {
      throw TenantProductImageException(error.code);
    }
  }

  @override
  Future<void> removeOwned({
    required String tenantId,
    required String productId,
    required Uri imageUrl,
  }) async {
    validateTenantId(tenantId);
    validateTenantDocumentId(productId, fieldName: 'productId');
    try {
      final reference = _storage.refFromURL(imageUrl.toString());
      if (!reference.fullPath.startsWith(_ownedPrefix(tenantId, productId))) {
        return;
      }
      await reference.delete();
    } on FirebaseException catch (error) {
      if (error.code != 'object-not-found') rethrow;
    } on ArgumentError {
      // A legacy external HTTPS image is not owned by this store.
    }
  }

  String _uniqueId() => List<int>.generate(
    18,
    (_) => _random.nextInt(256),
  ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
}

String _ownedPrefix(String tenantId, String productId) =>
    'tenantProductImages/$tenantId/$productId/';

TenantProductImageType _typeOf(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return TenantProductImageType.jpeg;
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0d &&
      bytes[5] == 0x0a &&
      bytes[6] == 0x1a &&
      bytes[7] == 0x0a) {
    return TenantProductImageType.png;
  }
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
    return TenantProductImageType.webp;
  }
  throw const TenantProductImageException('unsupported_image_type');
}

TenantProductImageType _validatedType(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > maximumTenantProductImageBytes) {
    throw const TenantProductImageException('invalid_image_size');
  }
  return _typeOf(bytes);
}
