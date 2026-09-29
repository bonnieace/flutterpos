/// A product photograph held on this device until Storage can take it.
///
/// **Why this exists.** Until 2026-09-04 adding a product with a picture meant
/// waiting on `putData` for up to five megabytes and then on `getDownloadURL`,
/// *before* the product was written at all - two round trips with no timeout
/// between a shopkeeper pressing *Add product* and anything appearing. Offline
/// it could not succeed at all, because Firebase Storage has no offline queue in
/// any state: the product was simply refused.
///
/// So the bytes are staged here instead. The product is written immediately
/// without a picture, [TenantProductVisual] draws these bytes wherever that
/// product appears, and [TenantProductImageUploadWorker] uploads them and files
/// the resulting URL as an ordinary queued correction. The photograph is on
/// screen from the moment it is chosen and never blocks the sale catalog.
///
/// **A draft is not evidence.** If the upload is refused for good, the draft is
/// discarded and the card falls back to the initials it already draws for every
/// product that has no picture. Nothing about the product itself is lost.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';

import '../checkout/checkout_outbox.dart';
import '../tenancy/tenant_id.dart';
import 'product_image_store.dart';
import '../observability/app_telemetry.dart';
import '../storage/device_storage.dart';

/// One photograph waiting to be uploaded.
final class TenantProductImageDraft {
  const TenantProductImageDraft({
    required this.tenantId,
    required this.productId,
    required this.bytes,
    required this.fileName,
    required this.createdAt,
  });

  static const int schemaVersion = 1;

  final String tenantId;
  final String productId;
  final Uint8List bytes;
  final String fileName;
  final DateTime createdAt;

  /// The candidate this draft was staged from, re-validated on the way out.
  ///
  /// Re-validating rather than trusting the record is what keeps a damaged box
  /// from reaching Storage: [TenantProductImageCandidate] re-reads the magic
  /// bytes and the size bound, exactly as it did when the picture was chosen.
  TenantProductImageCandidate toCandidate() =>
      TenantProductImageCandidate(bytes: bytes, fileName: fileName);

  Map<String, Object?> toStorage() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'tenantId': tenantId,
    'productId': productId,
    'bytes': bytes,
    'fileName': fileName,
    'createdAtMs': createdAt.millisecondsSinceEpoch,
  };
}

String tenantProductImageDraftKey({
  required String tenantId,
  required String productId,
}) =>
    '${validateTenantId(tenantId)}:'
    '${validateTenantDocumentId(productId, fieldName: 'productId')}';

/// Reads staged photographs. The narrow half every drawing surface depends on.
abstract interface class TenantProductImageDraftSource implements Listenable {
  /// The staged bytes for one product, or null when there are none.
  ///
  /// **Synchronous, because it is read during `build`.** Hive answers an open
  /// box from memory, which is what makes this possible and is the reason the
  /// box is opened once at startup rather than per read.
  Uint8List? bytesFor({required String tenantId, required String productId});
}

/// Encrypted Hive store of photographs this device has not uploaded yet.
final class HiveTenantProductImageDrafts extends ChangeNotifier
    implements TenantProductImageDraftSource {
  HiveTenantProductImageDrafts._(this._box, this._clock);

  static const String boxName = 'tenant-product-image-drafts-v1';

  final Box<dynamic> _box;
  final DateTime Function() _clock;

  static Future<HiveTenantProductImageDrafts> open({
    required CheckoutOutboxEncryptionKeyProvider keyProvider,
    HiveInterface? hive,
    DateTime Function()? clock,
  }) async {
    final key = await keyProvider.loadOrCreateKey();
    if (key.length != HiveCheckoutOutbox.encryptionKeyBytes) {
      throw const TenantProductImageException('invalid_encryption_key');
    }
    final box = await openBoxRepairingTornTail<dynamic>(
      hive ?? Hive,
      boxName,
      cipher: HiveAesCipher(List<int>.from(key)),
    );
    return HiveTenantProductImageDrafts._(box, clock ?? _utcNow);
  }

  factory HiveTenantProductImageDrafts.fromBox(
    Box<dynamic> box, {
    DateTime Function()? clock,
  }) => HiveTenantProductImageDrafts._(box, clock ?? _utcNow);

  @override
  Uint8List? bytesFor({required String tenantId, required String productId}) {
    final String key;
    try {
      key = tenantProductImageDraftKey(
        tenantId: tenantId,
        productId: productId,
      );
    } on ArgumentError {
      return null;
    }
    return _parse(_box.get(key))?.bytes;
  }

  /// Holds [candidate] for [productId] and tells every surface drawing it.
  Future<TenantProductImageDraft> stage({
    required String tenantId,
    required String productId,
    required TenantProductImageCandidate candidate,
  }) async {
    final key = tenantProductImageDraftKey(
      tenantId: tenantId,
      productId: productId,
    );
    final draft = TenantProductImageDraft(
      tenantId: validateTenantId(tenantId),
      productId: productId,
      bytes: candidate.bytes,
      fileName: candidate.fileName,
      createdAt: _clock().toUtc(),
    );
    await _box.put(key, draft.toStorage());
    notifyListeners();
    return draft;
  }

  /// Forgets one photograph, whether it landed or was refused for good.
  Future<void> discard({
    required String tenantId,
    required String productId,
  }) async {
    final key = tenantProductImageDraftKey(
      tenantId: tenantId,
      productId: productId,
    );
    if (!_box.containsKey(key)) return;
    await _box.delete(key);
    notifyListeners();
  }

  /// Every photograph still waiting, oldest first.
  ///
  /// A record this device cannot read is dropped rather than raised: an
  /// unreadable draft is a photograph that is already lost, and letting it
  /// throw here would stop every *other* photograph uploading behind it.
  List<TenantProductImageDraft> pending() {
    final drafts = <TenantProductImageDraft>[];
    for (final key in _box.keys) {
      if (key is! String) continue;
      final draft = _parse(_box.get(key));
      if (draft != null) drafts.add(draft);
    }
    drafts.sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return List<TenantProductImageDraft>.unmodifiable(drafts);
  }

  Future<void> close() => _box.close();

  TenantProductImageDraft? _parse(Object? raw) {
    // No record is the ordinary answer for nearly every product drawn, not a
    // failure. Only a record that exists and cannot be read is reported.
    if (raw == null) return null;
    try {
      final map = Map<Object?, Object?>.from(raw as Map);
      if (map['schemaVersion'] != TenantProductImageDraft.schemaVersion) {
        return null;
      }
      return TenantProductImageDraft(
        tenantId: validateTenantId(map['tenantId']! as String),
        productId: validateTenantDocumentId(
          map['productId']! as String,
          fieldName: 'productId',
        ),
        bytes: Uint8List.fromList((map['bytes']! as List).cast<int>()),
        fileName: map['fileName']! as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          map['createdAtMs']! as int,
          isUtc: true,
        ),
      );
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'inventory.image_draft_decode',
      );
      return null;
    }
  }
}

/// Makes staged photographs reachable from anywhere a product is drawn.
///
/// An [InheritedNotifier] rather than a plain scope, so staging or discarding
/// one repaints the surfaces showing that product without any of them holding
/// a subscription of their own.
final class TenantProductImageDraftScope
    extends InheritedNotifier<TenantProductImageDraftSource> {
  const TenantProductImageDraftScope({
    super.key,
    required TenantProductImageDraftSource super.notifier,
    required super.child,
  });

  /// The staged bytes for one product, or null - including where no scope is
  /// installed at all, which is every test that does not care about drafts.
  static Uint8List? bytesOf(
    BuildContext context, {
    required String tenantId,
    required String productId,
  }) => context
      .dependOnInheritedWidgetOfExactType<TenantProductImageDraftScope>()
      ?.notifier
      ?.bytesFor(tenantId: tenantId, productId: productId);
}

DateTime _utcNow() => DateTime.now().toUtc();
