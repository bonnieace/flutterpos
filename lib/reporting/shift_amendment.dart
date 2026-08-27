import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';

import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_types.dart';

/// Narrow callable boundary for `amendShiftSummary`.
///
/// It is the only path in the app that can change a closed shift, and it can
/// change nothing else about one: the server reads the corrected total from its
/// own sale-derived expectation, so no payload from here can name a figure.
abstract interface class AmendShiftSummaryCallable {
  Future<Object?> call(Map<String, Object?> payload);
}

/// Firebase adapter for `amendShiftSummary`.
final class FirebaseAmendShiftSummaryCallable
    implements AmendShiftSummaryCallable {
  FirebaseAmendShiftSummaryCallable({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    final result = await _functions
        .httpsCallable('amendShiftSummary')
        .call<Object?>(payload);
    return result.data;
  }
}

/// Why a shift summary was not amended.
///
/// Each case is a distinct outcome the person can act on. Only [ambiguous]
/// leaves the question open, and even that one is answerable: the whole
/// amendment is a single Firestore transaction, so re-reading the shift settles
/// whether it committed.
enum TenantShiftAmendmentFailure {
  /// The session may not amend a shift, or its membership ended.
  forbidden,

  /// The reason was empty, too short, too long, or unusable. This is the one
  /// case decided locally, before anything is sent.
  invalidReason,

  /// The shift no longer permits an amendment: it is open, already matches its
  /// sales, has no settled variance, or recorded no readable summary at all.
  notAmendable,

  /// No shift with that ID exists in this business.
  shiftNotFound,

  /// This request ID already settled a different request.
  duplicateRequest,

  /// The server rejected the request as malformed.
  invalidRequest,

  /// Refused for a reason this client does not model. Nothing was amended.
  refused,

  /// The outcome is unknown; the shift may or may not have been amended.
  ambiguous,
}

/// Raised when a shift summary amendment did not complete.
final class TenantShiftAmendmentException implements Exception {
  const TenantShiftAmendmentException(this.failure);

  final TenantShiftAmendmentFailure failure;

  /// Whether the shift may have been amended despite the failure.
  ///
  /// Only an unknown outcome carries that risk. Every other case is proof that
  /// the shift is exactly as it was, which matters because the surface that
  /// offers this also lists the difference it resolves: showing a difference as
  /// resolved when it is not would be worse than showing it unresolved.
  bool get mayHaveAmended => failure == TenantShiftAmendmentFailure.ambiguous;

  @override
  String toString() => 'TenantShiftAmendmentException(${failure.name})';
}

/// One validated amendment intent and its stable idempotency key.
final class TenantShiftAmendmentIntent {
  const TenantShiftAmendmentIntent._({
    required this.tenantId,
    required this.shiftId,
    required this.reason,
    required this.requestId,
  });

  /// The business the intent was created against. A gateway refuses an intent
  /// that names another, so a session change cannot resend it elsewhere.
  final String tenantId;

  final String shiftId;

  /// Normalized exactly as the server's `normalizeReason` will normalize it, so
  /// a retry hashes to the same idempotency record rather than being refused as
  /// the same request with different input.
  final String reason;

  final String requestId;
}

/// Strictly decoded result from `amendShiftSummary`.
///
/// The response is reconciled against the intent it was sent for: it must name
/// this business and this shift. Anything else is refused rather than shown,
/// because this is the surface that tells an owner a closed shift was rewritten.
final class TenantShiftAmendmentResult {
  const TenantShiftAmendmentResult._({
    required this.amendmentId,
    required this.tenantId,
    required this.shiftId,
    required this.businessDate,
    required this.previousTotalSalesMinor,
    required this.previousTransactionCount,
    required this.totalSalesMinor,
    required this.transactionCount,
    required this.salesVarianceMinor,
    required this.transactionVariance,
    required this.clearedAnomalyId,
  });

  factory TenantShiftAmendmentResult.fromCallable(
    Object? value, {
    required TenantShiftAmendmentIntent intent,
  }) {
    final data = _strictMap(value);
    if (data['tenantId'] != intent.tenantId) {
      throw const FormatException(
        'amendShiftSummary returned another business.',
      );
    }
    if (data['shiftId'] != intent.shiftId) {
      throw const FormatException('amendShiftSummary returned another shift.');
    }
    final previousTotalSalesMinor = _requiredMinorUnits(
      data,
      'previousTotalSalesMinor',
    );
    final previousTransactionCount = _requiredCount(
      data,
      'previousTransactionCount',
    );
    final totalSalesMinor = _requiredMinorUnits(data, 'totalSalesMinor');
    final transactionCount = _requiredCount(data, 'transactionCount');
    final transactionVariance = _requiredDifference(
      data,
      'transactionVariance',
    );
    // The transaction figures are whole counts from one comparison, so this
    // identity is exact and a response that breaks it did not come from the
    // handler. The money figures are deliberately not cross-checked the same
    // way: the recorded variance is measured from the shift's major-unit total,
    // which may legitimately disagree with its stored minor units, and asserting
    // an identity that can fail honestly would refuse a real amendment.
    if (transactionVariance != previousTransactionCount - transactionCount) {
      throw const FormatException(
        'amendShiftSummary returned a transaction difference that does not '
        'match the counts it reports.',
      );
    }
    return TenantShiftAmendmentResult._(
      amendmentId: _requiredDocumentId(data, 'amendmentId'),
      tenantId: intent.tenantId,
      shiftId: intent.shiftId,
      businessDate: _requiredBusinessDate(data),
      previousTotalSalesMinor: previousTotalSalesMinor,
      previousTransactionCount: previousTransactionCount,
      totalSalesMinor: totalSalesMinor,
      transactionCount: transactionCount,
      salesVarianceMinor: _requiredDifference(data, 'salesVarianceMinor'),
      transactionVariance: transactionVariance,
      // Null is a real answer: no difference was listed under this shift's
      // generation, or the record at that ID described something else and was
      // deliberately left alone.
      clearedAnomalyId: data['clearedAnomalyId'] == null
          ? null
          : _requiredDocumentId(data, 'clearedAnomalyId'),
    );
  }

  /// The `shift_amendments` record the server wrote.
  final String amendmentId;
  final String tenantId;
  final String shiftId;
  final String businessDate;

  /// What the shift recorded before, and what it records now.
  final int previousTotalSalesMinor;
  final int previousTransactionCount;
  final int totalSalesMinor;
  final int transactionCount;

  /// The difference that was resolved, observed minus expected.
  final int salesVarianceMinor;
  final int transactionVariance;

  /// The listed difference this amendment removed, if one was listed.
  final String? clearedAnomalyId;
}

typedef TenantShiftAmendmentRequestIdFactory = String Function();

/// Session-bound gateway with no business input surface.
///
/// The business comes from one captured live session, so no caller can amend a
/// shift in another one, and the only things a caller chooses are which shift
/// and why. The corrected figure is never an input: the server reads it from the
/// sale-derived expectation it verified, and the counted cash is not written at
/// all.
final class TenantShiftAmendmentGateway {
  TenantShiftAmendmentGateway({
    required TenantSession session,
    required AmendShiftSummaryCallable callable,
    TenantShiftAmendmentRequestIdFactory? requestIdFactory,
  }) : _session = session,
       _callable = callable,
       _requestIdFactory = requestIdFactory ?? secureShiftAmendmentRequestId;

  /// The server's `SHIFT_AMENDMENT_ROLES` is owner and administrator only,
  /// deliberately narrower than the roles that *read* the difference this
  /// resolves. Rewriting a record every client treats as terminal is governance;
  /// a manager may see that a shift disagrees with its sales without being able
  /// to rewrite the shift.
  static const List<TenantRole> allowedRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
  ];

  final TenantSession _session;
  final AmendShiftSummaryCallable _callable;
  final TenantShiftAmendmentRequestIdFactory _requestIdFactory;

  static bool canAmendInSession(TenantSession session) =>
      session.canAccess(allowedRoles: allowedRoles);

  /// Validates one intent locally before anything is sent, so a refusal the
  /// person can act on - an unusable reason above all - costs no round trip and
  /// no idempotency record.
  TenantShiftAmendmentIntent createIntent({
    required String shiftId,
    required String reason,
  }) {
    _requireAuthorizedSession();
    final String safeShiftId;
    try {
      safeShiftId = validateTenantDocumentId(shiftId, fieldName: 'shiftId');
    } on ArgumentError {
      throw const TenantShiftAmendmentException(
        TenantShiftAmendmentFailure.invalidRequest,
      );
    }
    final requestId = _requestIdFactory();
    if (!_requestIdPattern.hasMatch(requestId)) {
      throw StateError('The shift amendment request ID generator is invalid.');
    }
    return TenantShiftAmendmentIntent._(
      tenantId: _session.tenantId,
      shiftId: safeShiftId,
      reason: normalizeShiftAmendmentReason(reason),
      requestId: requestId,
    );
  }

  /// Submits [intent]; one intent keeps one request ID across a retry, so the
  /// server's own idempotency record settles a repeated attempt rather than
  /// writing a second amendment of the same shift.
  Future<TenantShiftAmendmentResult> submit(
    TenantShiftAmendmentIntent intent,
  ) async {
    _requireAuthorizedSession();
    if (intent.tenantId != _session.tenantId) {
      throw StateError('The shift amendment intent belongs to another tenant.');
    }
    final Object? response;
    try {
      response = await _callable.call(<String, Object?>{
        'tenantId': _session.tenantId,
        'shiftId': intent.shiftId,
        'reason': intent.reason,
        'requestId': intent.requestId,
      });
    } on FirebaseFunctionsException catch (error) {
      throw TenantShiftAmendmentException(_classify(error));
    } on TimeoutException {
      throw const TenantShiftAmendmentException(
        TenantShiftAmendmentFailure.ambiguous,
      );
    } catch (_) {
      throw const TenantShiftAmendmentException(
        TenantShiftAmendmentFailure.ambiguous,
      );
    }
    return TenantShiftAmendmentResult.fromCallable(response, intent: intent);
  }

  void _requireAuthorizedSession() {
    if (!canAmendInSession(_session)) {
      throw const TenantShiftAmendmentException(
        TenantShiftAmendmentFailure.forbidden,
      );
    }
  }
}

/// Normalizes a reason exactly as the server's `normalizeReason` does.
///
/// The order matters and mirrors the server: trim, check the trimmed length,
/// collapse whitespace runs, then refuse remaining control characters. Sending
/// the already-normalized value is what makes a retry hash to the same
/// idempotency record instead of being refused as one request with two inputs.
String normalizeShiftAmendmentReason(String value) {
  final trimmed = value.trim();
  if (trimmed.length < 3 || trimmed.length > 500) {
    throw const TenantShiftAmendmentException(
      TenantShiftAmendmentFailure.invalidReason,
    );
  }
  final collapsed = trimmed.replaceAll(RegExp(r'\s+'), ' ');
  if (_controlCharacters.hasMatch(collapsed)) {
    throw const TenantShiftAmendmentException(
      TenantShiftAmendmentFailure.invalidReason,
    );
  }
  return collapsed;
}

/// Classifies a refusal from the callable.
///
/// The code alone decides the outcome. `failed-precondition` is the interesting
/// one and is deliberately not folded into a generic refusal: it is the server
/// saying this shift cannot be amended - it is open, it already agrees with its
/// sales, its variance is not settled, or it never recorded a summary - which is
/// the most likely refusal in practice and the one a person can act on.
///
/// `aborted` is the idempotency helper reporting that this exact request is
/// still running, so the amendment may already have committed.
TenantShiftAmendmentFailure _classify(FirebaseFunctionsException error) =>
    switch (error.code) {
      'permission-denied' ||
      'unauthenticated' => TenantShiftAmendmentFailure.forbidden,
      'failed-precondition' => TenantShiftAmendmentFailure.notAmendable,
      'not-found' => TenantShiftAmendmentFailure.shiftNotFound,
      'already-exists' => TenantShiftAmendmentFailure.duplicateRequest,
      'invalid-argument' => TenantShiftAmendmentFailure.invalidRequest,
      'unavailable' ||
      'deadline-exceeded' ||
      'internal' ||
      'aborted' ||
      'unknown' => TenantShiftAmendmentFailure.ambiguous,
      _ => TenantShiftAmendmentFailure.refused,
    };

Map<String, Object?> _strictMap(Object? value) {
  if (value is! Map) {
    throw const FormatException(
      'amendShiftSummary returned an invalid response.',
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
    throw FormatException('amendShiftSummary returned an invalid $field.');
  }
  try {
    return validateTenantDocumentId(value, fieldName: field);
  } on ArgumentError {
    throw FormatException('amendShiftSummary returned an invalid $field.');
  }
}

String _requiredBusinessDate(Map<String, Object?> data) {
  final value = data['businessDate'];
  if (value is! String || !_businessDatePattern.hasMatch(value)) {
    throw const FormatException(
      'amendShiftSummary returned an invalid businessDate.',
    );
  }
  return value;
}

/// A stored shift total is never negative, and is bounded by the same
/// `maximumShiftSalesMinor` the shift history read model enforces.
int _requiredMinorUnits(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! int || value < 0 || value > _maximumShiftSalesMinor) {
    throw FormatException('amendShiftSummary returned an invalid $field.');
  }
  return value;
}

int _requiredCount(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! int || value < 0 || value > _maximumShiftSalesMinor) {
    throw FormatException('amendShiftSummary returned an invalid $field.');
  }
  return value;
}

/// A difference is signed: a shift may have recorded more or less than its
/// sales, and reporting the direction is the point.
int _requiredDifference(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! int || value.abs() > _maximumShiftSalesMinor) {
    throw FormatException('amendShiftSummary returned an invalid $field.');
  }
  return value;
}

String secureShiftAmendmentRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'amend-shift-${base64Url.encode(bytes).replaceAll('=', '')}';
}

/// The server's `REQUEST_ID_PATTERN`.
final RegExp _requestIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$');

final RegExp _businessDatePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

final RegExp _controlCharacters = RegExp(r'[\u0000-\u001f\u007f-\u009f]');

/// `maximumShiftSalesMinor` from `lib/shift/shift_sales_ledger.dart`, repeated
/// rather than imported so the reporting domain does not depend on the shift
/// domain for one bound.
const int _maximumShiftSalesMinor = 1000000000000;
