import 'dart:io' show SocketException;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'tenant_bootstrap.dart';
import 'tenant_directory.dart';

final class FirebaseTenantGateway
    implements TenantDirectoryGateway, RootRoutingGateway {
  FirebaseTenantGateway({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  @override
  Future<RootRoutingProfile> getRootRoutingProfile(String uid) async {
    final snapshot = await _firestore.collection('users').doc(uid).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      throw StateError('The signed-in account has no root profile.');
    }
    return RootRoutingProfile.fromJson(data);
  }

  /// Callable failures that mean *we could not ask*, rather than *the answer
  /// was no*.
  ///
  /// **This set is the offline fallback's entire safety boundary.** Anything
  /// listed here lets a device fall back to the businesses it last knew;
  /// anything absent - `permission-denied` and `unauthenticated` above all -
  /// keeps propagating, so an account that has been revoked can never be
  /// rescued by its own cache.
  static const _transportFailures = <String>{
    'unavailable',
    'deadline-exceeded',
    'internal',
  };

  @override
  Future<TenantListPage> listMyTenants({
    required int pageSize,
    String? cursor,
  }) async {
    final HttpsCallableResult<Object?> result;
    try {
      result = await _functions.httpsCallable('listMyTenants').call<Object?>(
        <String, Object?>{
          'pageSize': pageSize,
          if (cursor != null) 'cursor': cursor,
        },
      );
    } on FirebaseFunctionsException catch (error) {
      if (_transportFailures.contains(error.code)) {
        throw TenantDirectoryUnavailable(error.code);
      }
      rethrow;
    } on SocketException {
      // A handset with no route to the internet at all, which the Functions
      // SDK does not always wrap for us.
      throw const TenantDirectoryUnavailable('unavailable');
    }
    final data = result.data;
    if (data is! Map) {
      throw const FormatException('listMyTenants returned a non-object.');
    }
    return TenantListPage.fromJson(
      data.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      ),
    );
  }
}
