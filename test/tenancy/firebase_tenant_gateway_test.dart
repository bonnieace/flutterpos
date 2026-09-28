import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uzapay_pos/tenancy/firebase_tenant_gateway.dart';
import 'package:uzapay_pos/tenancy/tenant_bootstrap.dart';

/// The deadline on the read the whole launch depends on.
///
/// **The deadline is wall-clock from the moment the read is asked for**, so
/// it counts whatever the SDK does before the request leaves the device as
/// well as the network. On 2026-09-28 that was an App Check token: Firestore
/// held the `users` read back while Play Integrity took 10-15 seconds to
/// answer, and the gateway reported `deadline-exceeded` from a phone whose
/// network was fine. These tests hold the read back the same way.
void main() {
  testWidgets(
    'a users read that has not answered in 8 seconds is deadline-exceeded',
    (tester) async {
      final firestore = _HeldFirestore();
      final gateway = FirebaseTenantGateway(
        firestore: firestore,
        functions: _UnusedFunctions(),
      );

      Object? failure;
      var settled = false;
      unawaited(
        gateway
            .getRootRoutingProfile('user-a')
            .then<void>((_) {}, onError: (Object error) => failure = error)
            .whenComplete(() => settled = true),
      );

      await tester.pump(const Duration(seconds: 7));
      expect(settled, isFalse, reason: 'still inside the deadline');

      await tester.pump(const Duration(seconds: 1));
      expect(settled, isTrue);
      expect(
        failure,
        isA<TenantBootstrapUnavailable>().having(
          (error) => error.code,
          'code',
          'deadline-exceeded',
        ),
      );
      // It asked the server, not the device's copy - the cache is the
      // fallback this failure hands the launch to, not something it read.
      expect(firestore.requestedPath, 'users/user-a');
      expect(firestore.requestedSource, Source.server);
    },
  );

  test('the deadline is 8 seconds', () {
    // The figure the phone's App Check wait was measured against. Changing it
    // moves the line between "slow" and "offline" on every launch.
    expect(FirebaseTenantGateway.deadline, const Duration(seconds: 8));
  });
}

/// A Firestore whose server reads never answer, the way the SDK behaves while
/// it waits for something it needs before sending.
final class _HeldFirestore extends Fake implements FirebaseFirestore {
  String? requestedPath;
  Source? requestedSource;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _HeldCollection(this, collectionPath);
}

// ignore: subtype_of_sealed_class
final class _HeldCollection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _HeldCollection(this._firestore, this._path);

  final _HeldFirestore _firestore;
  final String _path;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _HeldDocument(_firestore, '$_path/$path');
}

// The SDK's reference types are marked sealed. A fake of them is the only way
// to hold a read back without a device, and nothing in `lib/` subclasses them.
// ignore: subtype_of_sealed_class
final class _HeldDocument extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  _HeldDocument(this._firestore, this._path);

  final _HeldFirestore _firestore;
  final String _path;

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) {
    _firestore
      ..requestedPath = _path
      ..requestedSource = options?.source;
    return Completer<DocumentSnapshot<Map<String, dynamic>>>().future;
  }
}

/// The gateway takes a Functions instance; the users read never touches it.
final class _UnusedFunctions extends Fake implements FirebaseFunctions {}
