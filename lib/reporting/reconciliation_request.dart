import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';

import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_types.dart';

/// Narrow callable boundary for `requestTenantReconciliation`.
///
/// It is the only path in the app that can ask the server to reconcile, and it
/// can ask for nothing else: the reconciliation workers own queueing, retrying,
/// cancelling, and quarantining, and none of those is reachable from here.
abstract interface class RequestReconciliationCallable {
  Future<Object?> call(Map<String, Object?> payload);
}

/// Firebase adapter for `requestTenantReconciliation`.
final class FirebaseRequestReconciliationCallable
    implements RequestReconciliationCallable {
  FirebaseRequestReconciliationCallable({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    final result = await _functions
        .httpsCallable('requestTenantReconciliation')
        .call<Object?>(payload);
    return result.data;
  }
}

/// The two modes `requireMode` accepts, with the cooldown each one carries.
///
/// The cooldowns are the server's own, from
/// `functions/src/reconciliation/handlers.ts`. They are stated to the person
/// asking because a full check spends a whole day's allowance: nothing in the
/// app can shorten it, and a second request inside the window is refused rather
/// than queued.
enum TenantReconciliationMode {
  incremental('incremental', Duration(minutes: 5)),
  full('full', Duration(hours: 24));

  const TenantReconciliationMode(this.wireValue, this.cooldown);

  final String wireValue;

  /// How long the server refuses another manual request of this mode.
  final Duration cooldown;

  String get label => switch (this) {
    incremental => 'Catch up',
    full => 'Full check',
  };

  /// What the mode does, and what asking for it costs.
  String get description => switch (this) {
    incremental =>
      'Works through the days that are already waiting. One can be asked for '
          'every 5 minutes.',
    full =>
      'Re-examines the whole recent window, including stock and shifts. Only '
          'one can be asked for every 24 hours.',
  };
}

/// Why the server did not queue a reconciliation.
///
/// Each case is a distinct outcome an owner can act on. Only [ambiguous] leaves
/// the question open; every other case is proof that nothing was queued.
enum TenantReconciliationRequestFailure {
  /// The session may not request reconciliation, or its membership ended.
  forbidden,

  /// The mode's cooldown has not elapsed since the last manual request.
  requestedTooRecently,

  /// This request ID already settled a different request.
  duplicateRequest,

  /// The server rejected the request as malformed.
  invalidRequest,

  /// Refused for a reason this client does not model. Nothing was queued.
  refused,

  /// The outcome is unknown; a run may or may not have been queued.
  ambiguous,
}

/// Raised when a reconciliation request did not complete.
final class TenantReconciliationRequestException implements Exception {
  const TenantReconciliationRequestException(this.failure);

  final TenantReconciliationRequestFailure failure;

  /// Whether a run may have been queued despite the failure.
  ///
  /// The handler enqueues the task *after* its transaction commits, so a
  /// transport failure can leave a real job document behind with no task. Only
  /// an unknown outcome carries that risk, and it is the one case where the
  /// page must be re-read before anything is asked for again.
  bool get mayHaveQueued =>
      failure == TenantReconciliationRequestFailure.ambiguous;

  @override
  String toString() => 'TenantReconciliationRequestException(${failure.name})';
}

/// One validated request intent and its stable idempotency key.
final class TenantReconciliationRequestIntent {
  const TenantReconciliationRequestIntent._({
    required this.tenantId,
    required this.mode,
    required this.requestId,
  });

  /// The business the intent was created against. A gateway refuses an intent
  /// that names another, so a session change cannot resend it elsewhere.
  final String tenantId;

  final TenantReconciliationMode mode;
  final String requestId;
}

/// Strictly decoded result from `requestTenantReconciliation`.
///
/// The response is reconciled against the intent it was requested for: it must
/// name this business, the mode that was asked for, and the queued status the
/// handler is the only writer of. Anything else is refused rather than shown,
/// because this is the surface that tells an owner their business is being
/// re-checked.
final class TenantReconciliationRequestResult {
  const TenantReconciliationRequestResult._({
    required this.jobId,
    required this.tenantId,
    required this.mode,
  });

  factory TenantReconciliationRequestResult.fromCallable(
    Object? value, {
    required TenantReconciliationRequestIntent intent,
  }) {
    final data = _strictMap(value);
    if (data['tenantId'] != intent.tenantId) {
      throw const FormatException(
        'requestTenantReconciliation returned another business.',
      );
    }
    if (data['mode'] != intent.mode.wireValue) {
      throw const FormatException(
        'requestTenantReconciliation returned another mode.',
      );
    }
    // `queued` is the only status the handler ever returns. Accepting anything
    // else would let a future server state be reported as a queued run.
    if (data['status'] != 'queued') {
      throw const FormatException(
        'requestTenantReconciliation returned an unexpected status.',
      );
    }
    return TenantReconciliationRequestResult._(
      jobId: _requiredDocumentId(data, 'jobId'),
      tenantId: intent.tenantId,
      mode: intent.mode,
    );
  }

  /// The `reconciliation_jobs` document the server created.
  final String jobId;
  final String tenantId;
  final TenantReconciliationMode mode;
}

typedef TenantReconciliationRequestIdFactory = String Function();

/// Session-bound gateway with no business input surface.
///
/// The business comes from one captured live session, so no caller can name
/// another one, and the only thing a caller chooses is the mode.
final class TenantReconciliationRequestGateway {
  TenantReconciliationRequestGateway({
    required TenantSession session,
    required RequestReconciliationCallable callable,
    TenantReconciliationRequestIdFactory? requestIdFactory,
  }) : _session = session,
       _callable = callable,
       _requestIdFactory = requestIdFactory ?? secureReconciliationRequestId;

  /// `RECONCILIATION_REQUEST_ROLES` on the server is owner and administrator
  /// only, which is deliberately narrower than the roles that *read* this
  /// surface. A manager may see why a day is still waiting without being able
  /// to spend the business's manual reconciliation allowance on it.
  static const List<TenantRole> allowedRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
  ];

  final TenantSession _session;
  final RequestReconciliationCallable _callable;
  final TenantReconciliationRequestIdFactory _requestIdFactory;

  static bool canRequestInSession(TenantSession session) =>
      session.canAccess(allowedRoles: allowedRoles);

  /// Validates one intent locally before anything is sent, so a refusal the
  /// person can act on costs no round trip and no idempotency record.
  TenantReconciliationRequestIntent createIntent({
    required TenantReconciliationMode mode,
  }) {
    _requireAuthorizedSession();
    final requestId = _requestIdFactory();
    if (!_requestIdPattern.hasMatch(requestId)) {
      throw StateError('The reconciliation request ID generator is invalid.');
    }
    return TenantReconciliationRequestIntent._(
      tenantId: _session.tenantId,
      mode: mode,
      requestId: requestId,
    );
  }

  /// Submits [intent]; one intent keeps one request ID across a retry, so the
  /// server's own idempotency record settles a repeated attempt rather than
  /// queueing a second run against the same allowance.
  Future<TenantReconciliationRequestResult> submit(
    TenantReconciliationRequestIntent intent,
  ) async {
    _requireAuthorizedSession();
    if (intent.tenantId != _session.tenantId) {
      throw StateError('The reconciliation intent belongs to another tenant.');
    }
    final Object? response;
    try {
      response = await _callable.call(<String, Object?>{
        'tenantId': _session.tenantId,
        'mode': intent.mode.wireValue,
        'requestId': intent.requestId,
      });
    } on FirebaseFunctionsException catch (error) {
      throw TenantReconciliationRequestException(_classify(error));
    } on TimeoutException {
      throw const TenantReconciliationRequestException(
        TenantReconciliationRequestFailure.ambiguous,
      );
    } catch (_) {
      throw const TenantReconciliationRequestException(
        TenantReconciliationRequestFailure.ambiguous,
      );
    }
    return TenantReconciliationRequestResult.fromCallable(
      response,
      intent: intent,
    );
  }

  void _requireAuthorizedSession() {
    if (!canRequestInSession(_session)) {
      throw const TenantReconciliationRequestException(
        TenantReconciliationRequestFailure.forbidden,
      );
    }
  }
}

/// Classifies a refusal from the callable.
///
/// The code alone decides the outcome; unlike the stock gateway there is no
/// message matching here, because every distinct condition the handler raises
/// already carries its own code. An unmodelled code degrades to [refused],
/// which still reports truthfully that nothing was queued - and the codes that
/// leave the question genuinely open are listed explicitly as [ambiguous]
/// rather than being the fallback.
TenantReconciliationRequestFailure _classify(
  FirebaseFunctionsException error,
) => switch (error.code) {
  'permission-denied' ||
  'unauthenticated' => TenantReconciliationRequestFailure.forbidden,
  'resource-exhausted' =>
    TenantReconciliationRequestFailure.requestedTooRecently,
  'already-exists' => TenantReconciliationRequestFailure.duplicateRequest,
  'invalid-argument' => TenantReconciliationRequestFailure.invalidRequest,
  // `aborted` is the idempotency helper reporting that this exact request is
  // still running, so a job may already exist for it.
  'unavailable' ||
  'deadline-exceeded' ||
  'internal' ||
  'aborted' ||
  'unknown' => TenantReconciliationRequestFailure.ambiguous,
  _ => TenantReconciliationRequestFailure.refused,
};

Map<String, Object?> _strictMap(Object? value) {
  if (value is! Map) {
    throw const FormatException(
      'requestTenantReconciliation returned an invalid response.',
    );
  }
  return <String, Object?>{
    for (final key in value.keys)
      if (key is String) key: value[key],
  };
}

String _requiredDocumentId(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! String) {
    throw FormatException(
      'requestTenantReconciliation returned an invalid $field.',
    );
  }
  try {
    return validateTenantDocumentId(value, fieldName: field);
  } on ArgumentError {
    throw FormatException(
      'requestTenantReconciliation returned an invalid $field.',
    );
  }
}

String secureReconciliationRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'reconcile-${base64Url.encode(bytes).replaceAll('=', '')}';
}

/// The server's `REQUEST_ID_PATTERN`.
final RegExp _requestIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$');
