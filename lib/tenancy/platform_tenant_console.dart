import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'tenant_bootstrap.dart';
import 'tenant_id.dart';

/// The substrate every platform-administration screen shares.
///
/// **This was the top of `platform_tenant_review.dart` until the approval queue
/// went.** Businesses are active from the moment they are created, so there is
/// nothing left to approve or reject - but the identity check, the tenant
/// document envelope, the owner summary and the `setTenantLifecycle` boundary
/// were never about approval. They are what any console that acts on a business
/// needs, and the lifecycle and global-user-status screens still need them.
typedef PlatformTenantRequestIdFactory = String Function();
typedef PlatformTenantCurrentCheck = bool Function();

final class PlatformAdminIdentity {
  factory PlatformAdminIdentity({
    required String uid,
    required RootRoutingProfile profile,
    required bool hasSuperAdminClaim,
  }) => PlatformAdminIdentity._(
    uid: validateTenantDocumentId(uid.trim(), fieldName: 'uid'),
    accountType: profile.accountType,
    globallyActive: profile.isActive,
    hasSuperAdminClaim: hasSuperAdminClaim,
  );

  const PlatformAdminIdentity._({
    required this.uid,
    required this.accountType,
    required this.globallyActive,
    required this.hasSuperAdminClaim,
  });

  final String uid;
  final RootAccountType accountType;
  final bool globallyActive;
  final bool hasSuperAdminClaim;

  bool get canAdminister =>
      globallyActive &&
      hasSuperAdminClaim &&
      accountType == RootAccountType.platformAdmin;
}

final class PlatformTenantDocument {
  const PlatformTenantDocument({required this.id, required this.data});

  final String id;
  final Map<String, Object?> data;
}

final class PlatformTenantOwnerSummary {
  const PlatformTenantOwnerSummary._({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.globallyActive,
  });

  factory PlatformTenantOwnerSummary.fromDocument(
    PlatformTenantDocument document, {
    required String expectedUid,
  }) {
    late final String uid;
    try {
      uid = validateTenantDocumentId(document.id, fieldName: 'ownerUid');
    } on ArgumentError {
      throw const FormatException('Tenant owner is invalid.');
    }
    final email = document.data['email'];
    final displayName = document.data['displayName'];
    final globalStatus = document.data['globalStatus'];
    if (uid != expectedUid ||
        document.data['accountType'] != 'tenant_user' ||
        (globalStatus != 'active' && globalStatus != 'disabled') ||
        email is! String ||
        email.trim().isEmpty ||
        (displayName != null && displayName is! String)) {
      throw const FormatException('Tenant owner is invalid.');
    }
    return PlatformTenantOwnerSummary._(
      uid: uid,
      email: email.trim(),
      displayName: displayName is String && displayName.trim().isNotEmpty
          ? displayName.trim()
          : null,
      globallyActive: globalStatus == 'active',
    );
  }

  final String uid;
  final String email;
  final String? displayName;
  final bool globallyActive;
}

abstract interface class SetTenantLifecycleCallable {
  Future<Object?> call(Map<String, Object?> payload);
}

final class PlatformTenantCallableException implements Exception {
  const PlatformTenantCallableException(this.code);

  final String code;
}

final class FirebaseSetTenantLifecycleCallable
    implements SetTenantLifecycleCallable {
  FirebaseSetTenantLifecycleCallable({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    try {
      final result = await _functions
          .httpsCallable('setTenantLifecycle')
          .call<Object?>(payload);
      return result.data;
    } on FirebaseFunctionsException catch (error) {
      throw PlatformTenantCallableException(error.code);
    }
  }
}

Timestamp decodePlatformTimestamp(Object? value) {
  if (value is Timestamp) return value;
  if (value is DateTime) return Timestamp.fromDate(value.toUtc());
  throw const FormatException('Tenant timestamp is invalid.');
}

bool platformTextHasControl(String value) =>
    value.runes.any((rune) => rune <= 0x1f || (rune >= 0x7f && rune <= 0x9f));

String securePlatformRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'platform-${base64Url.encode(bytes).replaceAll('=', '')}';
}

final platformRequestIdPattern = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$',
);
