import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

/// Telemetry is observational: no caller waits for its transport or retries it.
abstract interface class AppTelemetry {
  static final Object _zoneKey = Object();
  static final Object _operationKey = Object();
  static AppTelemetry _installed = RecordingAppTelemetry();
  static AppTelemetry get current =>
      Zone.current[_zoneKey] as AppTelemetry? ?? _installed;
  static void install(AppTelemetry telemetry) => _installed = telemetry;
  static T withInstance<T>(AppTelemetry telemetry, T Function() action) =>
      runZoned(action, zoneValues: {_zoneKey: telemetry});

  /// The operation whose `trace` is running the current code, if any. A server
  /// call made from inside a traced flow becomes a span of that flow rather
  /// than a transaction of its own.
  static TelemetryOperation? get activeOperation =>
      Zone.current[_operationKey] as TelemetryOperation?;
  static Future<T> runInOperation<T>(
    TelemetryOperation operation,
    Future<T> Function() action,
  ) => runZoned(action, zoneValues: {_operationKey: operation});

  /// Reports a failure an enclosing `catch` is about to absorb. With neither an
  /// [operation] nor a [boundary] it joins the [activeOperation]; a named
  /// [boundary] is its own event, linked to the active operation as a parent.
  static void captureHandled(
    Object error,
    StackTrace stackTrace, {
    TelemetryOperation? operation,
    String? boundary,
    String stage = 'failed',
    String? code,
    Map<String, Object?> data = const {},
  }) => RecordingAppTelemetry.safely(
    () => current.reportFailure(
      error,
      stackTrace,
      operation: operation,
      boundary: boundary,
      stage: stage,
      code: code,
      data: data,
    ),
  );

  TelemetryOperation start(
    String operation, {
    String? screen,
    Map<String, Object?> context = const {},
  });
  void recordStep(
    TelemetryOperation operation,
    String stage, {
    Map<String, Object?> data = const {},
  });
  void reportFailure(
    Object error,
    StackTrace stackTrace, {
    TelemetryOperation? operation,
    String? boundary,
    String stage = 'failed',
    String? code,
    Map<String, Object?> data = const {},
  });
  void updateIdentity(Map<String, Object?> identity);
  void updateDevice(Map<String, Object?> device);
  Future<T> trace<T>(
    TelemetryOperation operation,
    String stage,
    Future<T> Function() action,
  );
  void finishOperation(TelemetryOperation operation, {bool cancelled = false});
}

final class TelemetryOperation {
  TelemetryOperation(
    this.name,
    this.screen,
    this.startedAt,
    this.attemptId,
    Map<String, Object?> context,
  ) : context = Map.unmodifiable(context);
  final String name;
  final String screen;
  final DateTime startedAt;
  final String attemptId;
  final Map<String, Object?> context;
  final List<Map<String, Object?>> _history = [];
  final Set<Object> _reported = HashSet.identity();

  /// One failure event per attempt. A later failure in the same attempt is
  /// almost always the first one rewrapped by an outer `catch`.
  bool _failed = false;
  List<Map<String, Object?>> get history => List.unmodifiable(_history);
}

final class AppFailure {
  AppFailure({
    required this.operation,
    required this.errorType,
    required this.message,
    required this.stackTrace,
    required this.code,
    required this.kind,
    required this.at,
    required this.stage,
    required this.snapshot,
    required this.history,
  });
  final TelemetryOperation operation;
  final String errorType, message, code, kind, stage;
  final StackTrace stackTrace;
  final DateTime at;
  final Map<String, Object?> snapshot;
  final List<Map<String, Object?>> history;
  bool get isExpected => const {
    'validation',
    'authentication',
    'permission',
    'connectivity',
    'conflict',
  }.contains(kind);
}

/// Shared implementation, injectable sinks, and a deterministic test recorder.
/// The production adapter disables recording; memory never grows with traffic.
class RecordingAppTelemetry implements AppTelemetry {
  RecordingAppTelemetry({DateTime Function()? clock, this.retain = false})
    : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;
  final bool retain;
  final List<AppFailure> failures = [];
  final List<Map<String, Object?>> steps = [];
  Map<String, Object?> _identity = {};
  Map<String, Object?> _device = {};
  final Map<String, int> _attemptCounts = {};
  static int _sequence = 0;
  static final _processId = Random.secure().nextInt(1 << 32).toRadixString(16);

  @override
  TelemetryOperation start(
    String operation, {
    String? screen,
    Map<String, Object?> context = const {},
  }) {
    final now = _clock().toUtc();
    final attemptKey =
        '$operation:${_identity['user_id'] ?? context['attempted_email'] ?? 'anonymous'}:${_identity['tenant_id'] ?? 'none'}';
    final attemptNumber = (_attemptCounts[attemptKey] ?? 0) + 1;
    _attemptCounts[attemptKey] = attemptNumber;
    final op = TelemetryOperation(
      operation,
      screen ?? operation.split('.').first,
      now,
      '$_processId-${now.microsecondsSinceEpoch}-${_sequence++}',
      sanitizeTelemetryMap({
        ..._device,
        ..._identity,
        ...context,
        'attempt_number': context['attempt_number'] ?? attemptNumber,
      }),
    );
    recordStep(op, 'started');
    return op;
  }

  @override
  void updateIdentity(Map<String, Object?> identity) {
    final next = sanitizeTelemetryMap(identity);
    final changed =
        next['user_id'] != _identity['user_id'] ||
        next['tenant_id'] != _identity['tenant_id'];
    _identity = next;
    if (changed) {
      steps.clear();
      _attemptCounts.clear();
      safely(() => identityChanged(next));
    } else {
      safely(() => identityChanged(next, clearBreadcrumbs: false));
    }
  }

  @override
  void updateDevice(Map<String, Object?> device) {
    _device = {..._device, ...sanitizeTelemetryMap(device)};
  }

  @override
  Future<T> trace<T>(
    TelemetryOperation operation,
    String stage,
    Future<T> Function() action,
  ) => AppTelemetry.runInOperation(operation, action);

  @override
  void finishOperation(
    TelemetryOperation operation, {
    bool cancelled = false,
  }) {}

  @override
  void recordStep(
    TelemetryOperation operation,
    String stage, {
    Map<String, Object?> data = const {},
  }) {
    final step = <String, Object?>{
      'operation': operation.name,
      'stage': stage,
      'attempt_id': operation.attemptId,
      'at': _clock().toUtc().toIso8601String(),
      ...sanitizeTelemetryMap(data),
    };
    operation._history.add(step);
    if (operation._history.length > 100) operation._history.removeAt(0);
    if (retain) {
      steps.add(step);
      if (steps.length > 100) steps.removeAt(0);
    }
    safely(() => emitStep(operation, step));
  }

  @override
  void reportFailure(
    Object error,
    StackTrace stackTrace, {
    TelemetryOperation? operation,
    String? boundary,
    String stage = 'failed',
    String? code,
    Map<String, Object?> data = const {},
  }) {
    final resolvedCode = code ?? telemetryErrorCode(error);
    final kind = classifyTelemetryFailure(resolvedCode, error);
    final active = AppTelemetry.activeOperation;
    final TelemetryOperation op;
    if (operation != null) {
      op = operation;
    } else if (boundary == null && active != null) {
      op = active;
    } else {
      // A till spends much of its life offline. A dropped connection caught
      // by a fallback is the expected path, so it becomes a breadcrumb on the
      // next real event rather than an event of its own.
      if (kind == 'connectivity') {
        safely(() => emitBreadcrumb(boundary ?? 'app.failure', resolvedCode));
        return;
      }
      op = start(
        boundary ?? 'app.failure',
        context: {
          if (active != null) 'parent_operation': active.name,
          if (active != null) 'parent_attempt_id': active.attemptId,
        },
      );
    }
    if (!op._reported.add(error)) return;
    recordStep(op, stage, data: {'error_code': resolvedCode});
    if (op._failed || !_claimFirstReport(error)) {
      op._failed = true;
      safely(() => emitSuppressedFailure(op));
      return;
    }
    op._failed = true;
    final failure = AppFailure(
      operation: op,
      errorType: error.runtimeType.toString(),
      message: scrubTelemetryText(error.toString()),
      stackTrace: stackTrace,
      code: resolvedCode,
      kind: kind,
      at: _clock().toUtc(),
      stage: stage,
      snapshot: boundedTelemetrySnapshot(data),
      history: op.history,
    );
    if (retain) failures.add(failure);
    safely(() => emitFailure(failure));
  }

  static final Expando<DateTime> _reportedAt = Expando<DateTime>();

  /// The same error object reaching a second operation within two seconds is
  /// one fault passing through two `catch` blocks, not two faults. The window
  /// is short because many domain exceptions are `const` and therefore the
  /// same object every time they are thrown, including on a person's retry.
  bool _claimFirstReport(Object error) {
    try {
      final now = _clock().toUtc();
      final previous = _reportedAt[error];
      _reportedAt[error] = now;
      return previous == null ||
          now.difference(previous) > const Duration(seconds: 2);
    } catch (_) {
      // Strings, numbers and records cannot carry an Expando.
      return true;
    }
  }

  FutureOr<void> emitFailure(AppFailure failure) {}

  /// The attempt failed, but its failure was already reported.
  FutureOr<void> emitSuppressedFailure(TelemetryOperation operation) {}

  FutureOr<void> emitBreadcrumb(String boundary, String code) {}
  FutureOr<void> emitStep(
    TelemetryOperation operation,
    Map<String, Object?> step,
  ) {}
  FutureOr<void> identityChanged(
    Map<String, Object?> identity, {
    bool clearBreadcrumbs = true,
  }) {}

  static void safely(FutureOr<void> Function() action) {
    try {
      final result = action();
      if (result is Future<void>) unawaited(result.catchError((Object _) {}));
    } catch (_) {
      // A telemetry transport must never become a business-operation failure.
    }
  }
}

/// Runs one Cloud Functions call under telemetry.
///
/// Inside a traced flow the call is a span of that flow, and the flow reports
/// its own failure. Anywhere else it is a `server.<function>` transaction of its
/// own, carrying the signed-in identity, and a failure is reported before it is
/// rethrown to the caller unchanged.
Future<T> traceServerCall<T>(String function, Future<T> Function() call) {
  final telemetry = AppTelemetry.current;
  final active = AppTelemetry.activeOperation;
  if (active != null) {
    return telemetry.trace(active, 'server.$function', call);
  }
  final TelemetryOperation operation;
  try {
    operation = telemetry.start('server.$function', screen: 'server');
    telemetry.recordStep(operation, 'submitted');
  } catch (_) {
    // Telemetry that cannot start must not stop the call it would observe.
    return call();
  }
  return _standaloneServerCall(telemetry, operation, call);
}

Future<T> _standaloneServerCall<T>(
  AppTelemetry telemetry,
  TelemetryOperation operation,
  Future<T> Function() call,
) async {
  try {
    final result = await telemetry.trace(operation, 'call_function', call);
    RecordingAppTelemetry.safely(
      () => telemetry.recordStep(operation, 'confirmed_on_server'),
    );
    return result;
  } catch (error, stackTrace) {
    AppTelemetry.captureHandled(error, stackTrace, operation: operation);
    rethrow;
  }
}

String telemetryErrorCode(Object error) {
  try {
    final value = (error as dynamic).code;
    if (value is String && RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(value)) {
      return value;
    }
  } catch (_) {
    // Most Dart exceptions do not expose a code.
  }
  return error.runtimeType.toString();
}

String classifyTelemetryFailure(String code, Object error) {
  final value = code.toLowerCase().replaceAll('_', '-');
  if (RegExp(r'storage|corrupt|malformed|hive|format').hasMatch(value)) {
    return 'storage';
  }
  if (RegExp(
    r'offline|unavailable|network|timeout|timed-out|deadline|socket|unreachable|uncertain',
  ).hasMatch(value)) {
    return 'connectivity';
  }
  if (RegExp(r'permission|forbidden|unauthoriz').hasMatch(value)) {
    return 'permission';
  }
  if (RegExp(
    r'credential|password|unauthenticated|user-not-found|user-disabled|email-already',
  ).hasMatch(value)) {
    return 'authentication';
  }
  if (RegExp(r'conflict|already-exists').hasMatch(value)) return 'conflict';
  if (value == 'not-found') return 'validation';
  if (error is ArgumentError ||
      RegExp(
        r'invalid|required|validation|refused|blocked|out-of-range|failed-precondition|no-selected-session|session-ended',
      ).hasMatch(value)) {
    return 'validation';
  }
  return 'unexpected';
}

final _secretKey = RegExp(
  r'password|passwd|secret|token|authorization|cookie|apikey|credential|privatekey|cardnumber|cvv|pin|rawbody|requestbody',
  caseSensitive: false,
);

String scrubTelemetryText(String text) {
  var value = text.replaceAll(
    RegExp(r'https?://[^\s<>"\x27]+'),
    '[redacted URL]',
  );
  value = value.replaceAllMapped(
    RegExp(
      r'''["'](password|passwd|secret|token|apiKey|authorization|credential)["']\s*:\s*["'][^"']*["']''',
      caseSensitive: false,
    ),
    (match) => '${match[1]}=[redacted]',
  );
  value = value.replaceAll(
    RegExp(r'Bearer\s+[^\s,;]+', caseSensitive: false),
    'Bearer [redacted]',
  );
  value = value.replaceAll(
    RegExp(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'),
    '[redacted token]',
  );
  value = value.replaceAllMapped(
    RegExp(
      r'(password|passwd|secret|token|api[_-]?key|authorization|credential)\s*[=:]\s*[^\s,;}]+',
      caseSensitive: false,
    ),
    (match) => '${match[1]}=[redacted]',
  );
  return value.length > 2048
      ? '${value.substring(0, 2048)} [truncated]'
      : value;
}

Map<String, Object?> sanitizeTelemetryMap(Map input, {int depth = 0}) {
  if (depth > 8) return {'truncated': true};
  final result = <String, Object?>{};
  for (final entry in input.entries.take(100)) {
    final key = entry.key.toString();
    final normalized = key.replaceAll(RegExp(r'[^a-zA-Z]'), '');
    if (_secretKey.hasMatch(normalized) ||
        const {
          'body',
          'headers',
          'vars',
          'customer',
          'customers',
          'request',
        }.contains(normalized.toLowerCase())) {
      continue;
    }
    final value = entry.value;
    if (value == null || value is num || value is bool) {
      result[key] = value;
    } else if (value is String) {
      result[key] = scrubTelemetryText(value);
    } else if (value is DateTime) {
      result[key] = value.toUtc().toIso8601String();
    } else if (value is Map) {
      result[key] = sanitizeTelemetryMap(value, depth: depth + 1);
    } else if (value is Iterable) {
      final list = value.toList();
      result[key] = list
          .take(50)
          .map(
            (item) => item is Map
                ? sanitizeTelemetryMap(item, depth: depth + 1)
                : item is String
                ? scrubTelemetryText(item)
                : item is num || item is bool || item == null
                ? item
                : '[unavailable]',
          )
          .toList();
      if (list.length > 50) {
        result['${key}_total_count'] = list.length;
        result['${key}_truncated'] = true;
      }
    }
    // Arbitrary objects are not serialized; their toString can contain secrets.
  }
  return result;
}

Map<String, Object?> boundedTelemetrySnapshot(Map<String, Object?> data) {
  final safe = sanitizeTelemetryMap(data);
  if (utf8.encode(jsonEncode(safe)).length <= 32768) return safe;
  final result = <String, Object?>{'truncated': true};
  for (final entry in safe.entries) {
    result[entry.key] = entry.value;
    if (utf8.encode(jsonEncode(result)).length > 32768) {
      result.remove(entry.key);
    }
  }
  return result;
}
