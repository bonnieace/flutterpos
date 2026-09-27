import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:uzapay_pos/observability/glitchtip_telemetry.dart';

void main() {
  late Completer<SentryTransaction> transaction;
  late Completer<SentryEvent> failure;

  setUp(() async {
    transaction = Completer<SentryTransaction>();
    failure = Completer<SentryEvent>();
    await Sentry.init((options) {
      options.dsn = 'https://public@example.com/1';
      options.debug = true;
      options.tracesSampleRate = 1;
      options.beforeSend = (event, hint) {
        if (!failure.isCompleted)
          failure.complete(scrubGlitchTipEvent(event, hint));
        return null; // No test event is sent to a collector.
      };
      options.beforeSendTransaction = (event, hint) {
        if (!transaction.isCompleted) {
          try {
            transaction.complete(scrubGlitchTipTransaction(event, hint));
          } catch (error, stack) {
            transaction.completeError(error, stack);
          }
        }
        return null;
      };
    });
  });

  tearDown(() => Sentry.close());

  test('finished transactions retain origin and actual child spans', () async {
    final telemetry = GlitchTipTelemetry();
    telemetry.updateIdentity({'user_id': 'cashier-a', 'tenant_id': 'shop-a'});
    final operation = telemetry.start('checkout.save');
    final answer = await telemetry.trace(
      operation,
      'persist_checkout',
      () async => 42,
    );
    telemetry.updateIdentity({'user_id': 'cashier-b', 'tenant_id': 'shop-b'});
    telemetry.recordStep(operation, 'saved_locally');
    final event = await transaction.future.timeout(const Duration(seconds: 5));
    expect(answer, 42);
    expect(event.transaction, 'txn.uzapay.checkout.save');
    expect(event.user?.id, 'cashier-a');
    expect(event.contexts['business']['tenant_id'], 'shop-a');
    expect(event.spans.map((span) => span.context.operation), [
      'business.persist_checkout',
    ]);
    expect(event.contexts.trace?.status?.toString(), 'ok');
  });

  test(
    'failures link to the transaction and preserve original business',
    () async {
      final telemetry = GlitchTipTelemetry();
      telemetry.updateIdentity({'user_id': 'cashier-a', 'tenant_id': 'shop-a'});
      final operation = telemetry.start('production.complete');
      telemetry.updateIdentity({'user_id': 'cashier-b', 'tenant_id': 'shop-b'});
      telemetry.reportFailure(
        StateError('storage failed'),
        StackTrace.current,
        operation: operation,
        code: 'storage_failure',
        data: {'password': 'secret', 'quantity': 3},
      );
      final event = await failure.future.timeout(const Duration(seconds: 5));
      final trace = await transaction.future.timeout(
        const Duration(seconds: 5),
      );
      expect(event.user?.id, 'cashier-a');
      expect(event.contexts['business']['tenant_id'], 'shop-a');
      expect(event.contexts.trace?.traceId, trace.contexts.trace?.traceId);
      expect(
        trace.contexts.trace?.status?.toString(),
        const SpanStatus.internalError().toString(),
      );
      expect('${event.toJson()}', isNot(contains('secret')));
      expect(event.contexts['app_operation']['snapshot']['quantity'], 3);
    },
  );
}
