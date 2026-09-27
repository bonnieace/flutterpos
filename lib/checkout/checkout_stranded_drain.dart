import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';

import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_types.dart';
import 'checkout_outbox.dart';
import 'checkout_sale.dart';
import '../observability/app_telemetry.dart';

/// Narrow callable boundary for `drainStrandedSales`.
abstract interface class DrainStrandedSalesCallable {
  Future<Object?> call(Map<String, Object?> payload);
}

/// Firebase adapter for `drainStrandedSales`.
final class FirebaseDrainStrandedSalesCallable
    implements DrainStrandedSalesCallable {
  FirebaseDrainStrandedSalesCallable({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    final result = await traceServerCall(
      'drainStrandedSales',
      () =>
          _functions.httpsCallable('drainStrandedSales').call<Object?>(payload),
    );
    return result.data;
  }
}

/// What one drain attempt did.
final class CheckoutStrandedDrainResult {
  const CheckoutStrandedDrainResult({
    this.handedOver = 0,
    this.alreadyPresent = 0,
    this.unreadable = 0,
    this.attempted = false,
  });

  /// Sales this call wrote to the server.
  final int handedOver;

  /// Sales the server already held, which it left alone.
  final int alreadyPresent;

  /// Records whose payload could not be read, and which were left untouched.
  final int unreadable;

  /// Whether the callable was reached at all. False when there was nothing to
  /// hand over, which is the ordinary case.
  final bool attempted;

  /// Whether anything reached the server because of this.
  bool get settledAnything => handedOver > 0;
}

/// Hands over sales a cashier rang up before their access to a business ended.
///
/// **The moment this runs is the whole point.** A deactivation reaches this
/// device through no channel of its own - the canonical staff record stops
/// being readable at the instant it happens - so the app finds out by asking
/// again, which it does when somebody picks their phone back up. That ask is
/// online by construction: a refresh that cannot reach the server leaves the
/// session exactly as it was. So at the instant the device learns its access
/// has ended, it has a connection, and the sales sitting in its outbox are
/// reachable for as long as that connection lasts.
///
/// **What it cannot do is send them the ordinary way.** `allow create` on
/// `sales` requires `activeStaff`, and by the time the device knows, the server
/// already says otherwise - the write would come back `permission-denied` and
/// the sale would settle into `needsAttention` with the money still unrecorded.
/// `drainStrandedSales` is the one door left open, and it is open only for a
/// sale attributed to this caller and dated before their own deactivation.
///
/// **Records are not deleted here.** A handed-over sale stays in the outbox as
/// the device's own evidence; the server's answer is what settles it, and the
/// ordinary confirmation pass is what records that. Deleting on a bare "the
/// server says it has it" would throw away the only copy of a sale on the word
/// of one call.
final class CheckoutStrandedSalesDrainer {
  CheckoutStrandedSalesDrainer({
    required HiveCheckoutOutbox outbox,
    required DrainStrandedSalesCallable callable,
    CheckoutStrandedRequestIdFactory? requestIdFactory,
  }) : _outbox = outbox,
       _callable = callable,
       _requestIdFactory = requestIdFactory ?? _secureDrainRequestId;

  /// The server refuses more than this in one call, so the device sends no more.
  static const int maximumSalesPerCall = 50;

  final HiveCheckoutOutbox _outbox;
  final DrainStrandedSalesCallable _callable;
  final CheckoutStrandedRequestIdFactory _requestIdFactory;

  /// Hands over whatever [uid] still holds for [tenantId].
  ///
  /// Only records that never reached the server are offered. A sale that is
  /// `submitting` or `awaitingConfirmation` may already be on the server, and
  /// handing it over again would be claiming to know something this device
  /// cannot: the ordinary confirmation pass settles those.
  Future<CheckoutStrandedDrainResult> drain({
    required String uid,
    required String tenantId,
  }) async {
    final records = await _outbox.recordsForSession(
      uid: uid,
      tenantId: tenantId,
    );
    final stranded = <CheckoutOutboxRecord>[
      for (final record in records)
        if (record.state == CheckoutOutboxState.savedOffline) record,
    ];
    if (stranded.isEmpty) return const CheckoutStrandedDrainResult();

    final sales = <Map<String, Object?>>[];
    var unreadable = 0;
    for (final record in stranded.take(maximumSalesPerCall)) {
      try {
        sales.add(
          CheckoutSalePayload.fromOutboxRecord(
            record,
            // **Read without the access check, which is the situation.** The
            // session that owns this evidence is precisely the one that can no
            // longer reach the business; every other check still holds, so the
            // payload must still hash to its own hash and name this uid and
            // tenant. See [CheckoutSalePayload.fromLocalPayload].
            session: TenantSession.active(
              uid: uid,
              tenantId: tenantId,
              role: TenantRole.cashier,
            ),
            requireAccess: false,
          ).toSubmission().saleFields,
        );
      } catch (error, stackTrace) {
        AppTelemetry.captureHandled(
          error,
          stackTrace,
          boundary: 'checkout.stranded_record_decode',
        );
        // **A record this device cannot read is left exactly where it is.** It
        // is still the only copy of that sale, and a payload that will not
        // parse is a question for somebody looking at the device rather than
        // something to push at the server.
        unreadable += 1;
      }
    }
    if (sales.isEmpty) {
      return CheckoutStrandedDrainResult(unreadable: unreadable);
    }

    final Object? response;
    try {
      response = await _callable.call(<String, Object?>{
        'tenantId': tenantId,
        'requestId': _requestIdFactory(),
        'sales': sales,
      });
    } on FirebaseFunctionsException {
      return CheckoutStrandedDrainResult(
        unreadable: unreadable,
        attempted: true,
      );
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'checkout.stranded_drain',
      );
      return CheckoutStrandedDrainResult(
        unreadable: unreadable,
        attempted: true,
      );
    }
    return CheckoutStrandedDrainResult(
      handedOver: _count(response, 'drained'),
      alreadyPresent: _count(response, 'alreadyPresent'),
      unreadable: unreadable,
      attempted: true,
    );
  }

  int _count(Object? response, String field) {
    if (response is! Map) return 0;
    final value = response[field];
    return value is List ? value.length : 0;
  }
}

typedef CheckoutStrandedRequestIdFactory = String Function();

String _secureDrainRequestId() =>
    'drain-stranded-${DateTime.now().toUtc().millisecondsSinceEpoch}';
