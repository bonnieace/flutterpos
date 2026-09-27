import 'package:sentry_flutter/sentry_flutter.dart';

import 'app_telemetry.dart';

final class GlitchTipTelemetry extends RecordingAppTelemetry {
  final Expando<ISentrySpan> _transactions = Expando<ISentrySpan>();

  @override
  TelemetryOperation start(
    String operation, {
    String? screen,
    Map<String, Object?> context = const {},
  }) {
    final attempt = super.start(operation, screen: screen, context: context);
    try {
      final transaction = Sentry.startTransaction(
        'txn.uzapay.$operation',
        'business.flow',
        startTimestamp: attempt.startedAt,
        bindToScope: false,
        // No autoFinishAfter: the SDK silently drops an auto-finishing
        // transaction that has no child spans, which is every attempt that
        // fails or saves before its first trace().
      );
      transaction.setTag('attempt_id', attempt.attemptId);
      transaction.setData('app_origin', attempt.context);
      transaction.setTag('screen', attempt.screen);
      transaction.setTag(
        'tenant_id',
        '${attempt.context['tenant_id'] ?? 'unavailable'}',
      );
      _transactions[attempt] = transaction;
    } catch (_) {
      // Tracing must never stop the action that is being observed.
    }
    return attempt;
  }

  @override
  Future<T> trace<T>(
    TelemetryOperation operation,
    String stage,
    Future<T> Function() action,
  ) async {
    ISentrySpan? child;
    try {
      child = _transactions[operation]?.startChild('business.$stage');
    } catch (_) {
      // Continue the action even if creating a span fails.
    }
    try {
      final result = await AppTelemetry.runInOperation(operation, action);
      if (child != null) {
        RecordingAppTelemetry.safely(
          () => child!.finish(status: const SpanStatus.ok()),
        );
      }
      return result;
    } catch (_) {
      if (child != null) {
        RecordingAppTelemetry.safely(
          () => child!.finish(status: const SpanStatus.internalError()),
        );
      }
      rethrow;
    }
  }

  @override
  void finishOperation(TelemetryOperation operation, {bool cancelled = false}) {
    final transaction = _transactions[operation];
    if (transaction == null || transaction.finished) return;
    RecordingAppTelemetry.safely(
      () => transaction.finish(
        status: cancelled
            ? const SpanStatus.cancelled()
            : const SpanStatus.ok(),
      ),
    );
  }

  @override
  Future<void> emitFailure(AppFailure failure) async {
    final op = failure.operation;
    final identity = op.context;
    try {
      await Sentry.captureEvent(
        SentryEvent(
          timestamp: failure.at,
          throwable: _ReportedFailure(failure.message),
          level: failure.isExpected ? SentryLevel.warning : SentryLevel.error,
          fingerprint: [
            op.name,
            failure.stage,
            failure.errorType,
            failure.code,
          ],
          tags: {
            'operation': op.name,
            'stage': failure.stage,
            'failure_kind': failure.kind,
            'error_code': failure.code,
            'attempt_id': op.attemptId,
            'screen': op.screen,
            'tenant_id': '${identity['tenant_id'] ?? 'unavailable'}',
            if (identity['parent_attempt_id'] != null)
              'parent_attempt_id': '${identity['parent_attempt_id']}',
          },
          user: SentryUser(
            id: '${identity['user_id'] ?? 'unavailable'}',
            username: identity['user_name'] as String?,
            email: identity['user_email'] as String?,
          ),
          contexts: Contexts.fromJson({
            'app_operation': {
              ...identity,
              'name': op.name,
              'screen': op.screen,
              'attempt_id': op.attemptId,
              'started_at': op.startedAt.toIso8601String(),
              'failed_at': failure.at.toIso8601String(),
              'duration_ms': failure.at.difference(op.startedAt).inMilliseconds,
              'error_type': failure.errorType,
              'snapshot': failure.snapshot,
              'history': failure.history,
            },
          }),
        ),
        stackTrace: failure.stackTrace,
        withScope: (scope) {
          scope.span = _transactions[op];
        },
      );
    } finally {
      final transaction = _transactions[op];
      if (transaction != null && !transaction.finished) {
        await transaction.finish(status: const SpanStatus.internalError());
      }
    }
  }

  @override
  void emitSuppressedFailure(TelemetryOperation operation) {
    final transaction = _transactions[operation];
    if (transaction == null || transaction.finished) return;
    RecordingAppTelemetry.safely(
      () => transaction.finish(status: const SpanStatus.internalError()),
    );
  }

  @override
  void emitBreadcrumb(String boundary, String code) {
    RecordingAppTelemetry.safely(
      () => Sentry.addBreadcrumb(
        Breadcrumb(
          category: 'boundary.$boundary',
          message: code,
          level: SentryLevel.warning,
        ),
      ),
    );
  }

  @override
  void emitStep(TelemetryOperation operation, Map<String, Object?> step) {
    RecordingAppTelemetry.safely(
      () => Sentry.addBreadcrumb(
        Breadcrumb(
          category: 'journey.${operation.name}',
          message: step['stage'] as String,
          data: step,
        ),
      ),
    );
    final stage = step['stage'];
    if (stage == 'cancelled') {
      finishOperation(operation, cancelled: true);
    } else if (stage == 'saved_locally' || stage == 'confirmed_on_server') {
      finishOperation(operation);
    }
  }

  @override
  Future<void> identityChanged(
    Map<String, Object?> identity, {
    bool clearBreadcrumbs = true,
  }) async => Sentry.configureScope((scope) {
    if (clearBreadcrumbs) scope.clearBreadcrumbs();
    scope.setUser(
      identity['user_id'] == null
          ? null
          : SentryUser(
              id: identity['user_id'] as String?,
              username: identity['user_name'] as String?,
              email: identity['user_email'] as String?,
            ),
    );
    scope.setContexts('business', identity);
    scope.setTag('tenant_id', '${identity['tenant_id'] ?? 'unavailable'}');
  });
}

final class _ReportedFailure implements Exception {
  const _ReportedFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Final scrub also covers errors and breadcrumbs produced by SDK integrations.
SentryEvent scrubGlitchTipEvent(SentryEvent event, Hint hint) {
  hint.attachments.clear();
  hint.screenshot = null;
  hint.viewHierarchy = null;
  final json = event.toJson();
  json.remove('request');
  final operation = event.contexts['app_operation'];
  if (operation is Map) {
    final contexts = json['contexts'];
    if (contexts is Map) {
      contexts['business'] = {
        'user_id': operation['user_id'],
        'tenant_id': operation['tenant_id'],
        'business_name': operation['business_name'],
        'tenant_role': operation['tenant_role'],
      };
    }
    // SDK scope breadcrumbs may belong to a newer tenant by the time an old
    // operation finishes. Use the immutable attempt's own timeline instead.
    json['breadcrumbs'] = (operation['history'] as List)
        .map(
          (step) => {
            'timestamp': step['at'],
            'category': 'journey.${operation['name']}',
            'message': step['stage'],
            'data': step,
          },
        )
        .toList();
    final exception = json['exception'];
    if (exception is Map && exception['values'] is List) {
      for (final value in exception['values']) {
        if (value is Map) value['type'] = operation['error_type'];
      }
    }
  } else {
    // SDK-generated breadcrumbs can include raw URLs or widget text.
    json['breadcrumbs'] = <Object>[];
  }
  return SentryEvent.fromJson(sanitizeTelemetryMap(json));
}

/// Transactions are processed separately from error events by the SDK.
SentryTransaction scrubGlitchTipTransaction(
  SentryTransaction event,
  Hint hint,
) {
  hint.attachments.clear();
  hint.screenshot = null;
  hint.viewHierarchy = null;
  final origin = event.contexts.trace?.data?['app_origin'];
  final safe = scrubGlitchTipEvent(event, hint);
  event.request = null;
  event.breadcrumbs = [];
  event.contexts = safe.contexts;
  event.tags = safe.tags;
  event.transaction = safe.transaction;
  // ignore: deprecated_member_use
  event.extra = null;
  if (origin is Map) {
    final identity = sanitizeTelemetryMap(origin);
    event.user = SentryUser(
      id: '${identity['user_id'] ?? 'unavailable'}',
      username: identity['user_name'] as String?,
      email: identity['user_email'] as String?,
    );
    event.contexts['business'] = identity;
  } else {
    event.user = safe.user;
  }
  for (final span in event.spans) {
    final data = boundedTelemetrySnapshot(Map<String, Object?>.from(span.data));
    span.data
      ..clear()
      ..addAll(data);
    final tags = sanitizeTelemetryMap(span.tags);
    span.tags
      ..clear()
      ..addAll(tags.map((key, value) => MapEntry(key, '$value')));
    final description = span.context.description;
    if (description != null) {
      span.context.description = scrubTelemetryText(description);
    }
  }
  return event;
}
