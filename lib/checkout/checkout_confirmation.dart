import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'checkout_outbox.dart';

enum CheckoutConfirmationKind {
  matching,
  missing,
  mismatching,
  pendingWrites,
  unavailable,
  malformed,
}

final class CheckoutConfirmationResult {
  const CheckoutConfirmationResult._(
    this.kind, {
    this.observedPayloadHash,
    this.missingSaleProof,
  });

  const CheckoutConfirmationResult.matching(String observedPayloadHash)
    : this._(
        CheckoutConfirmationKind.matching,
        observedPayloadHash: observedPayloadHash,
      );

  CheckoutConfirmationResult.missing(CheckoutOutboxRecord record, DateTime at)
    : this._(
        CheckoutConfirmationKind.missing,
        missingSaleProof: CheckoutMissingSaleProof.confirmed(
          uid: record.uid,
          tenantId: record.tenantId,
          checkoutId: record.checkoutId,
          expectedPayloadHash: record.payloadHash,
          checkedAt: at,
        ),
      );

  const CheckoutConfirmationResult.mismatching(String observedPayloadHash)
    : this._(
        CheckoutConfirmationKind.mismatching,
        observedPayloadHash: observedPayloadHash,
      );

  const CheckoutConfirmationResult.pendingWrites()
    : this._(CheckoutConfirmationKind.pendingWrites);

  const CheckoutConfirmationResult.unavailable()
    : this._(CheckoutConfirmationKind.unavailable);

  const CheckoutConfirmationResult.malformed()
    : this._(CheckoutConfirmationKind.malformed);

  final CheckoutConfirmationKind kind;
  final String? observedPayloadHash;
  final CheckoutMissingSaleProof? missingSaleProof;
}

abstract interface class CheckoutConfirmationGateway {
  Future<CheckoutConfirmationResult> check(CheckoutOutboxRecord record);
}

final class CheckoutServerSaleSnapshot {
  const CheckoutServerSaleSnapshot.missing() : exists = false, data = null;

  CheckoutServerSaleSnapshot.found(Map<String, Object?> data)
    : exists = true,
      data = Map<String, Object?>.unmodifiable(data);

  final bool exists;
  final Map<String, Object?>? data;
}

typedef CheckoutPendingWritesWaiter = Future<void> Function();
typedef CheckoutServerSaleReader =
    Future<CheckoutServerSaleSnapshot> Function(
      String tenantId,
      String checkoutId,
    );
typedef CheckoutConfirmationOnlineCheck = Future<bool> Function();
typedef CheckoutConfirmationClock = DateTime Function();

/// Reads only the deterministic canonical sale path from the server cache
/// boundary after this client's pending Firestore writes have drained.
final class FirebaseCheckoutConfirmationGateway
    implements CheckoutConfirmationGateway {
  FirebaseCheckoutConfirmationGateway({
    FirebaseFirestore? firestore,
    required CheckoutConfirmationOnlineCheck isOnline,
    Duration pendingWritesTimeout = const Duration(seconds: 15),
    Duration serverReadTimeout = const Duration(seconds: 15),
    CheckoutConfirmationClock? clock,
  }) : this._(
         waitForPendingWrites:
             (firestore ?? FirebaseFirestore.instance).waitForPendingWrites,
         readServerSale: (tenantId, checkoutId) async {
           final snapshot = await (firestore ?? FirebaseFirestore.instance)
               .collection('tenants')
               .doc(tenantId)
               .collection('sales')
               .doc(checkoutId)
               .get(const GetOptions(source: Source.server));
           final data = snapshot.data();
           if (!snapshot.exists) {
             return const CheckoutServerSaleSnapshot.missing();
           }
           return data == null
               ? CheckoutServerSaleSnapshot.found(const <String, Object?>{})
               : CheckoutServerSaleSnapshot.found(data);
         },
         isOnline: isOnline,
         pendingWritesTimeout: pendingWritesTimeout,
         serverReadTimeout: serverReadTimeout,
         clock: clock,
       );

  FirebaseCheckoutConfirmationGateway.forTesting({
    required CheckoutPendingWritesWaiter waitForPendingWrites,
    required CheckoutServerSaleReader readServerSale,
    required CheckoutConfirmationOnlineCheck isOnline,
    Duration pendingWritesTimeout = const Duration(seconds: 15),
    Duration serverReadTimeout = const Duration(seconds: 15),
    CheckoutConfirmationClock? clock,
  }) : this._(
         waitForPendingWrites: waitForPendingWrites,
         readServerSale: readServerSale,
         isOnline: isOnline,
         pendingWritesTimeout: pendingWritesTimeout,
         serverReadTimeout: serverReadTimeout,
         clock: clock,
       );

  FirebaseCheckoutConfirmationGateway._({
    required CheckoutPendingWritesWaiter waitForPendingWrites,
    required CheckoutServerSaleReader readServerSale,
    required CheckoutConfirmationOnlineCheck isOnline,
    required Duration pendingWritesTimeout,
    required Duration serverReadTimeout,
    CheckoutConfirmationClock? clock,
  }) : _waitForPendingWrites = waitForPendingWrites,
       _readServerSale = readServerSale,
       _isOnline = isOnline,
       _pendingWritesTimeout = pendingWritesTimeout,
       _serverReadTimeout = serverReadTimeout,
       _clock = clock ?? _utcNow {
    if (pendingWritesTimeout <= Duration.zero) {
      throw ArgumentError.value(pendingWritesTimeout, 'pendingWritesTimeout');
    }
    if (serverReadTimeout <= Duration.zero) {
      throw ArgumentError.value(serverReadTimeout, 'serverReadTimeout');
    }
  }

  final CheckoutPendingWritesWaiter _waitForPendingWrites;
  final CheckoutServerSaleReader _readServerSale;
  final CheckoutConfirmationOnlineCheck _isOnline;
  final Duration _pendingWritesTimeout;
  final Duration _serverReadTimeout;
  final CheckoutConfirmationClock _clock;

  @override
  Future<CheckoutConfirmationResult> check(CheckoutOutboxRecord record) async {
    if (!await _online()) {
      return const CheckoutConfirmationResult.unavailable();
    }
    try {
      await _waitForPendingWrites().timeout(_pendingWritesTimeout);
    } on TimeoutException {
      return const CheckoutConfirmationResult.pendingWrites();
    } catch (_) {
      return const CheckoutConfirmationResult.unavailable();
    }
    if (!await _online()) {
      return const CheckoutConfirmationResult.unavailable();
    }

    CheckoutServerSaleSnapshot snapshot;
    try {
      snapshot = await _readServerSale(
        record.tenantId,
        record.checkoutId,
      ).timeout(_serverReadTimeout);
    } catch (_) {
      return const CheckoutConfirmationResult.unavailable();
    }
    if (!snapshot.exists) {
      return CheckoutConfirmationResult.missing(record, _clock().toUtc());
    }
    final data = snapshot.data;
    final checkoutId = data?['checkoutId'];
    final tenantId = data?['tenantId'];
    final payloadHash = data?['payloadHash'];
    if (checkoutId != record.checkoutId ||
        tenantId != record.tenantId ||
        payloadHash is! String ||
        !_sha256Pattern.hasMatch(payloadHash)) {
      return const CheckoutConfirmationResult.malformed();
    }
    return payloadHash == record.payloadHash
        ? CheckoutConfirmationResult.matching(payloadHash)
        : CheckoutConfirmationResult.mismatching(payloadHash);
  }

  Future<bool> _online() async {
    try {
      return await _isOnline();
    } catch (_) {
      return false;
    }
  }
}

final RegExp _sha256Pattern = RegExp(r'^[a-f0-9]{64}$');

DateTime _utcNow() => DateTime.now().toUtc();
