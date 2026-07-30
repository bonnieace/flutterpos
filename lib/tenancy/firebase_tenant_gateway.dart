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

  @override
  Future<TenantListPage> listMyTenants({
    required int pageSize,
    String? cursor,
  }) async {
    final result = await _functions
        .httpsCallable('listMyTenants')
        .call<Object?>(<String, Object?>{
          'pageSize': pageSize,
          if (cursor != null) 'cursor': cursor,
        });
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
