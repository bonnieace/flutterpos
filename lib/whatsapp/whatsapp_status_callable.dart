/// Asks the server whether this deployment can send WhatsApp receipts at all.
library;

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';

import '../tenancy/tenant_session.dart';

/// `getWhatsappReceiptStatus`, answering null where it could not be asked.
///
/// **Null is "could not tell", never "no".** A shop offline when it opens the
/// WhatsApp tile is told to connect to find out, rather than that receipts are
/// unavailable - which would be a claim about the server this device did not
/// hear.
Future<bool?> firebaseWhatsappReceiptStatus(
  TenantSession session, {
  FirebaseFunctions? functions,
  Duration deadline = const Duration(seconds: 8),
}) async {
  try {
    final result = await (functions ?? FirebaseFunctions.instance)
        .httpsCallable('getWhatsappReceiptStatus')
        .call<Object?>(<String, Object?>{'tenantId': session.tenantId})
        .timeout(deadline);
    final data = result.data;
    return data is Map && data['configured'] is bool
        ? data['configured'] as bool
        : null;
  } on TimeoutException {
    return null;
  } on FirebaseFunctionsException {
    return null;
  }
}
