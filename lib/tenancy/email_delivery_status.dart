import 'package:cloud_functions/cloud_functions.dart';

import '../ui/status.dart';
import '../observability/app_telemetry.dart';

/// Narrow callable boundary for `getMyEmailDeliveryStatus`.
///
/// It takes no input at all: the server answers about the caller's own address,
/// derived from the authenticated token, and there is no parameter a caller
/// could use to ask about anybody else.
abstract interface class EmailDeliveryStatusCallable {
  Future<Object?> call();
}

final class EmailDeliveryStatusCallableException implements Exception {
  const EmailDeliveryStatusCallableException(this.code);

  final String code;

  @override
  String toString() => 'EmailDeliveryStatusCallableException($code)';
}

/// Firebase adapter for `getMyEmailDeliveryStatus`; answer validation remains
/// above it.
final class FirebaseEmailDeliveryStatusCallable
    implements EmailDeliveryStatusCallable {
  FirebaseEmailDeliveryStatusCallable({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<Object?> call() async {
    try {
      final result = await traceServerCall(
        'getMyEmailDeliveryStatus',
        () => _functions
            .httpsCallable('getMyEmailDeliveryStatus')
            .call<Object?>(),
      );
      return result.data;
    } on FirebaseFunctionsException catch (error) {
      throw EmailDeliveryStatusCallableException(error.code);
    }
  }
}

/// Whether mail this app asks the server to send can reach the caller.
enum EmailDeliveryStatus {
  /// Nothing is known to be blocking delivery to this address.
  available,

  /// The server will not deliver to this address.
  ///
  /// It deliberately does not say why. Four different causes - the account
  /// carries no address, the root record is not eligible, an active suppression
  /// exists, or the recorded delivery status is unavailable - all answer with
  /// the same sentence. That collapsing is the server's enumeration boundary,
  /// and this client must not try to infer which one it was.
  unavailable,
}

/// The exact sentence the server returns for every unavailable case.
///
/// It is matched as a **sentinel**, not displayed. It carries no per-cause
/// information, and a surface that has just asked for a specific email can say
/// something far more useful than a generic support line. Matching it exactly
/// is the unavoidable coupling; re-displaying it would be an avoidable one.
const String emailDeliveryUnavailableSentinel =
    'Email delivery unavailable. Check the address or contact support.';

/// The exact sentence the server returns when nothing is blocking delivery.
const String emailDeliveryAvailableSentinel = 'available';

/// Classifies the server's answer, refusing anything it does not recognise.
///
/// An unrecognised answer is **never** read as [EmailDeliveryStatus.available].
/// If the server's wording changes, this fails closed and the surface simply
/// says nothing, which is correct: telling a user their address works when this
/// client can no longer tell would be worse than staying silent.
EmailDeliveryStatus parseEmailDeliveryStatus(Object? value) {
  if (value == emailDeliveryAvailableSentinel) {
    return EmailDeliveryStatus.available;
  }
  if (value == emailDeliveryUnavailableSentinel) {
    return EmailDeliveryStatus.unavailable;
  }
  throw const FormatException(
    'getMyEmailDeliveryStatus returned an unrecognised answer.',
  );
}

/// What every surface says about an address the server will not deliver to.
///
/// **One sentence, defined once.** Two surfaces wait on the same email - the
/// signup wizard's verify step and the account verification panel - and a user
/// who is told different things by them is being told the app does not know.
/// It names no cause because the server reports none: four causes collapse to
/// one answer at its boundary, and [emailDeliveryUnavailableSentinel] says why.
///
/// It leads with the fact that retrying cannot help, because retrying forever
/// is precisely the behaviour it exists to stop.
const AppNotice emailUndeliverableNotice = AppNotice.refused(
  'This address cannot receive mail from us, so sending again will not help. '
  'Check the address or contact support.',
);

/// Guarded client boundary over `getMyEmailDeliveryStatus`.
final class EmailDeliveryStatusReader {
  const EmailDeliveryStatusReader({required this.callable});

  final EmailDeliveryStatusCallable callable;

  /// Reads whether the signed-in caller's own address can receive mail.
  Future<EmailDeliveryStatus> read() async =>
      parseEmailDeliveryStatus(await callable.call());
}
