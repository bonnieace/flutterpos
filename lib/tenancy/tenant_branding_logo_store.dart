/// Where a business's own logo is kept.
///
/// **A second prefix rather than a second product.** The logo could have been
/// pushed under `tenantProductImages/{tenantId}/{some id}/` and needed no rules
/// change at all; it is not, for two reasons. A manager may write a product
/// image and may not name the business, so sharing the prefix would hand the
/// logo to a role that cannot publish it - and anything that ever tidies a
/// deleted product's pictures would take the logo with it.
///
/// **It reads the same two Firestore documents the product rule reads.**
/// Cross-service Rules allow no more than two *unique* Firestore documents per
/// evaluation and a third denies the request outright, so the block in
/// `storage.rules` is written against `tenantPath` and `staffPath` and nothing
/// else. See that file's own note - this constraint has already cost this
/// product one working feature.
///
/// **The candidate type is the product one, deliberately.** It validates the
/// magic bytes and the five-megabyte bound, which is exactly the check a logo
/// needs; a second identical class would be a second place to fix a hole in.
library;

import 'dart:math';

import 'package:firebase_storage/firebase_storage.dart';

import '../inventory/product_image_store.dart';
import 'tenant_id.dart';

/// Puts one logo in Storage and answers with the address to publish.
abstract interface class TenantBrandingLogoStore {
  Future<Uri> upload({
    required String tenantId,
    required TenantProductImageCandidate candidate,
  });

  /// Removes [logoUrl] only when it resolves inside this business's own prefix.
  ///
  /// A logo published as an external address - which is all this screen could
  /// accept before uploads existed - is left exactly where it is.
  Future<void> removeOwned({required String tenantId, required Uri logoUrl});
}

final class FirebaseTenantBrandingLogoStore implements TenantBrandingLogoStore {
  FirebaseTenantBrandingLogoStore({FirebaseStorage? storage, Random? random})
    : _storage = storage ?? FirebaseStorage.instance,
      _random = random ?? Random.secure();

  final FirebaseStorage _storage;
  final Random _random;

  @override
  Future<Uri> upload({
    required String tenantId,
    required TenantProductImageCandidate candidate,
  }) async {
    validateTenantId(tenantId);
    // **A new object per upload rather than one `logo.png` overwritten.** Every
    // device that has drawn the old logo holds it under its own URL, and a URL
    // whose bytes change underneath it is the one thing an image cache cannot
    // notice. A replaced logo appears immediately everywhere because its
    // address is new.
    final objectPath =
        '${_ownedPrefix(tenantId)}${_uniqueId()}.${candidate.type.extension}';
    try {
      final reference = _storage.ref(objectPath);
      await reference.putData(
        candidate.bytes,
        SettableMetadata(
          contentType: candidate.type.contentType,
          customMetadata: <String, String>{'tenantId': tenantId},
        ),
      );
      return Uri.parse(await reference.getDownloadURL());
    } on FirebaseException catch (error) {
      throw TenantProductImageException(error.code);
    }
  }

  @override
  Future<void> removeOwned({
    required String tenantId,
    required Uri logoUrl,
  }) async {
    validateTenantId(tenantId);
    try {
      final reference = _storage.refFromURL(logoUrl.toString());
      if (!reference.fullPath.startsWith(_ownedPrefix(tenantId))) return;
      await reference.delete();
    } on FirebaseException catch (error) {
      if (error.code != 'object-not-found') rethrow;
    } on ArgumentError {
      // An external HTTPS address is not owned by this store.
    }
  }

  String _uniqueId() => List<int>.generate(
    18,
    (_) => _random.nextInt(256),
  ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
}

String _ownedPrefix(String tenantId) => 'tenantBrandingImages/$tenantId/';
