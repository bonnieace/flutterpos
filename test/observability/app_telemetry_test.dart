import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:uzapay_pos/observability/app_telemetry.dart';
import 'package:uzapay_pos/observability/glitchtip_telemetry.dart';

void main() {
  test('classifies expected refusals and unexpected failures', () {
    final telemetry = RecordingAppTelemetry(retain: true);
    final cases = <(String, String)>[
      ('validation_missing_email', 'validation'),
      ('wrong-password', 'authentication'),
      ('permission-denied', 'permission'),
      ('unavailable', 'connectivity'),
      ('unexpected_crash', 'unexpected'),
    ];
    for (final (code, kind) in cases) {
      telemetry.reportFailure(
        StateError(code),
        StackTrace.current,
        operation: telemetry.start('test.submit'),
        code: code,
      );
      expect(telemetry.failures.last.kind, kind);
      expect(telemetry.failures.last.isExpected, kind != 'unexpected');
    }
  });

  test(
    'one exception is reported once in an attempt, retries are distinct',
    () {
      final telemetry = RecordingAppTelemetry(retain: true);
      final error = StateError('failure');
      final first = telemetry.start('checkout.submit');
      telemetry.reportFailure(error, StackTrace.current, operation: first);
      telemetry.reportFailure(error, StackTrace.current, operation: first);
      final second = telemetry.start('checkout.submit');
      telemetry.reportFailure(
        StateError('failure'),
        StackTrace.current,
        operation: second,
      );
      expect(telemetry.failures, hasLength(2));
      expect(first.attemptId, isNot(second.attemptId));
    },
  );

  test('a rewrapped failure in the same attempt is not a second event', () {
    final telemetry = RecordingAppTelemetry(retain: true);
    final operation = telemetry.start('staff.invite');
    telemetry.reportFailure(
      StateError('raw'),
      StackTrace.current,
      operation: operation,
    );
    telemetry.reportFailure(
      StateError('wrapped'),
      StackTrace.current,
      operation: operation,
    );
    expect(telemetry.failures, hasLength(1));
    expect(
      operation.history.where((step) => step['stage'] == 'failed'),
      hasLength(2),
    );
  });

  test('one error passing through two operations is reported once', () {
    final telemetry = RecordingAppTelemetry(retain: true);
    final error = StateError('shared');
    telemetry.reportFailure(
      error,
      StackTrace.current,
      operation: telemetry.start('server.inviteStaff'),
    );
    telemetry.reportFailure(error, StackTrace.current, boundary: 'staff.form');
    expect(telemetry.failures, hasLength(1));
    expect(telemetry.failures.single.operation.name, 'server.inviteStaff');
  });

  test('a failure inside a trace joins the traced operation', () async {
    final telemetry = RecordingAppTelemetry(retain: true);
    final operation = telemetry.start('returns.record');
    await AppTelemetry.withInstance(
      telemetry,
      () => telemetry.trace(operation, 'persist', () async {
        AppTelemetry.captureHandled(StateError('inner'), StackTrace.current);
        AppTelemetry.captureHandled(
          StateError('cache'),
          StackTrace.current,
          boundary: 'returns.cache_write',
        );
      }),
    );
    expect(telemetry.failures.map((failure) => failure.operation.name), [
      'returns.record',
      'returns.cache_write',
    ]);
    expect(
      telemetry.failures.last.operation.context['parent_attempt_id'],
      operation.attemptId,
    );
  });

  test('a connectivity fallback outside any operation is not an event', () {
    final telemetry = RecordingAppTelemetry(retain: true);
    telemetry.reportFailure(
      StateError('offline'),
      StackTrace.current,
      boundary: 'checkout.catalog_refresh',
      code: 'unavailable',
    );
    expect(telemetry.failures, isEmpty);
  });

  test('a standalone server call is its own attempt and rethrows', () async {
    final telemetry = RecordingAppTelemetry(retain: true);
    final error = StateError('permission-denied');
    await AppTelemetry.withInstance(telemetry, () async {
      expect(await traceServerCall('setStaffStatus', () async => 7), 7);
      await expectLater(
        traceServerCall<void>('inviteStaff', () async => throw error),
        throwsA(same(error)),
      );
    });
    expect(telemetry.failures.single.operation.name, 'server.inviteStaff');
    final stages = telemetry.steps.map(
      (step) =>
          '${step['operation']}:'
          '${step['stage']}',
    );
    expect(
      stages,
      containsAllInOrder([
        'server.setStaffStatus:submitted',
        'server.setStaffStatus:confirmed_on_server',
        'server.inviteStaff:submitted',
        'server.inviteStaff:failed',
      ]),
    );
  });

  test(
    'a server call inside a traced flow is not a transaction of its own',
    () async {
      final telemetry = RecordingAppTelemetry(retain: true);
      final operation = telemetry.start('auth.signup');
      await AppTelemetry.withInstance(
        telemetry,
        () => telemetry.trace(
          operation,
          'create_profile',
          () => traceServerCall('completeSelfSignup', () async => null),
        ),
      );
      expect(telemetry.steps.map((step) => step['operation']).toSet(), {
        'auth.signup',
      });
    },
  );

  test('local save, submission, and confirmation retain their order', () {
    final telemetry = RecordingAppTelemetry(retain: true);
    final operation = telemetry.start('checkout.save');
    telemetry.recordStep(operation, 'validated');
    telemetry.recordStep(operation, 'saved_locally');
    telemetry.recordStep(operation, 'submitted');
    telemetry.recordStep(operation, 'confirmed_on_server');
    expect(operation.history.map((step) => step['stage']), [
      'started',
      'validated',
      'saved_locally',
      'submitted',
      'confirmed_on_server',
    ]);
  });

  test('old attempts retain the original identity after a tenant switch', () {
    final telemetry = RecordingAppTelemetry(retain: true);
    telemetry.updateIdentity({'user_id': 'one', 'tenant_id': 'first'});
    final previous = telemetry.start('production.save');
    telemetry.updateIdentity({'user_id': 'two', 'tenant_id': 'second'});
    telemetry.reportFailure(
      StateError('late'),
      StackTrace.current,
      operation: previous,
    );
    expect(telemetry.failures.single.operation.context['tenant_id'], 'first');
    expect(telemetry.failures.single.operation.context['user_id'], 'one');
    expect(telemetry.steps.map((step) => step['stage']), ['failed']);
  });

  test(
    'snapshots are bounded and omit secrets, URLs and unrelated customers',
    () {
      final snapshot = boundedTelemetrySnapshot({
        'operation_id': 'op-1',
        'password': 'hidden',
        'customers': [
          {'name': 'unrelated'},
        ],
        'url': 'https://user:pass@example.com/action?token=hidden',
        'records': List.generate(60, (index) => {'product_id': '$index'}),
        'description': 'x' * 40000,
      });
      expect(snapshot['operation_id'], 'op-1');
      expect(snapshot.containsKey('password'), isFalse);
      expect(snapshot.containsKey('customers'), isFalse);
      expect('${snapshot['url']}', isNot(contains('hidden')));
      expect(snapshot['records_total_count'], 60);
      expect(snapshot['records_truncated'], true);
      expect('${snapshot['description']}'.length, lessThanOrEqualTo(2048 + 12));
    },
  );

  test('a failed telemetry sink does not replace the business failure', () {
    final telemetry = _FailingSink();
    final error = StateError('business');
    final operation = telemetry.start('business.save');
    AppTelemetry.withInstance(telemetry, () {
      AppTelemetry.captureHandled(
        error,
        StackTrace.current,
        operation: operation,
      );
    });
    expect(telemetry.failures, hasLength(1));
    expect(telemetry.failures.single.message, contains('business'));
  });

  test('final SDK scrub removes URL-bearing breadcrumbs and request data', () {
    final event = SentryEvent(
      message: SentryMessage('Could not open https://host/reset?token=secret'),
      breadcrumbs: [Breadcrumb(message: 'https://host/reset?token=secret')],
    );
    final scrubbed = scrubGlitchTipEvent(event, Hint());
    expect(scrubbed.breadcrumbs, isEmpty);
    expect('${scrubbed.toJson()}', isNot(contains('secret')));
  });
}

final class _FailingSink extends RecordingAppTelemetry {
  _FailingSink() : super(retain: true);
  @override
  void emitFailure(AppFailure failure) => throw StateError('transport');
}
