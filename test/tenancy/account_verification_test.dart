import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/buttons.dart';
import '../support/notices.dart';

void main() {
  group('account verification gateway', () {
    test('sends exactly the payload the server contract requires', () async {
      final callable = _Callable();

      final gateway = _gateway(callable, requestIdFactory: () => 'verify-abcd');
      await gateway.send(gateway.createIntent());

      // `requestId` is the whole contract; anything else would be a field the
      // server neither reads nor validates.
      expect(callable.payloads.single, <String, Object?>{
        'requestId': 'verify-abcd',
      });
    });

    test('the generated request ID satisfies the server pattern', () {
      final pattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$');

      for (var attempt = 0; attempt < 50; attempt++) {
        final intent = _gateway(_Callable()).createIntent();
        expect(pattern.hasMatch(intent.requestId), isTrue,
            reason: intent.requestId);
      }
    });

    test('a generator that breaks the contract is refused before any call', () {
      final callable = _Callable();

      expect(
        () => _gateway(callable, requestIdFactory: () => 'short').createIntent(),
        throwsStateError,
      );
      expect(
        () => _gateway(callable, requestIdFactory: () => '-leading').createIntent(),
        throwsStateError,
      );
      expect(callable.payloads, isEmpty);
    });

    test('a verified or disabled identity cannot ask at all', () {
      final callable = _Callable();

      expect(
        () => _gateway(callable, emailVerified: true).createIntent(),
        throwsStateError,
      );
      expect(
        () => _gateway(callable, globallyActive: false).createIntent(),
        throwsStateError,
      );
      expect(callable.payloads, isEmpty);
    });

    test('an intent belonging to another identity is refused', () async {
      final callable = _Callable();
      final other = _gateway(callable, uid: 'user-b').createIntent();

      await expectLater(
        _gateway(callable).send(other),
        throwsStateError,
      );
      expect(callable.payloads, isEmpty);
    });

    test('acceptance is proved, never assumed', () async {
      for (final response in <Object?>[
        null,
        'accepted',
        <String, Object?>{},
        <String, Object?>{'accepted': false},
        <String, Object?>{'accepted': 'true'},
        // An unexpected extra field means the contract moved; the client must
        // not quietly treat it as the response it knows.
        <String, Object?>{'accepted': true, 'deliveryId': 'd1'},
      ]) {
        final callable = _Callable(response: response);
        final gateway = _gateway(callable);

        await expectLater(
          gateway.send(gateway.createIntent()),
          throwsA(isA<FormatException>()),
          reason: '$response',
        );
      }

      final accepted = _Callable(response: <String, Object?>{'accepted': true});
      final gateway = _gateway(accepted);
      await gateway.send(gateway.createIntent());
    });

    test('every failure maps to a message that discloses nothing', () {
      expect(
        accountVerificationSafeError(
          const AccountVerificationCallableException('failed-precondition'),
        ),
        contains('sign in again'),
      );
      expect(
        accountVerificationSafeError(
          const AccountVerificationCallableException('unauthenticated'),
        ),
        'Sign in again to request a verification email.',
      );
      expect(
        accountVerificationSafeError(
          const AccountVerificationCallableException('permission-denied'),
        ),
        'This account is not active. Contact support.',
      );
      expect(
        accountVerificationSafeError(
          const AccountVerificationCallableException('resource-exhausted'),
        ),
        contains('Too many requests'),
      );
      for (final error in <Object>[
        const AccountVerificationCallableException('internal'),
        StateError('boom'),
        const FormatException('bad'),
      ]) {
        expect(
          accountVerificationSafeError(error),
          'The verification email could not be requested. Please try again.',
        );
      }
    });
  });

  group('account verification panel', () {
    testWidgets('acceptance never claims an email was delivered', (
      tester,
    ) async {
      final callable = _Callable();

      await _pump(tester, callable);
      await tester.tap(find.byKey(const ValueKey('account-verification-send')));
      await tester.pump();
      await tester.pump();

      final accepted = noticeMessage(
        tester,
        'account-verification-accepted',
      );
      // **This card told its three answers apart by hue alone until the step-4
      // sweep**, which is the case §9 rules out: `colorScheme.primary` here and
      // `colorScheme.error` on the other two, with no container, glyph or word
      // between them. A test that read only the sentence would have passed just
      // as happily with all three painted as failures.
      expect(
        noticeStatus(tester, 'account-verification-accepted'),
        AppStatus.ok,
      );
      // An already-verified or suppressed address is accepted and sends
      // nothing, so the copy must stay conditional.
      expect(accepted, contains('If this address can receive mail'));
      expect(accepted, isNot(contains('We sent')));
      expect(accepted, isNot(contains('has been sent')));
      expect(callable.payloads, hasLength(1));
    });

    testWidgets('a retry after failure reuses the same request ID', (
      tester,
    ) async {
      final callable = _Callable(failWith: 'unavailable');

      await _pump(tester, callable);
      await tester.tap(find.byKey(const ValueKey('account-verification-send')));
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('account-verification-error')),
        findsOne,
      );

      callable.failWith = null;
      await tester.tap(find.byKey(const ValueKey('account-verification-send')));
      await tester.pump();
      await tester.pump();

      // The retry must address the same delivery rather than queue a second
      // email for one user intent.
      expect(callable.payloads, hasLength(2));
      expect(callable.payloads[0], callable.payloads[1]);
    });

    testWidgets('a second tap while sending issues no second call', (
      tester,
    ) async {
      final callable = _Callable(defer: true);

      await _pump(tester, callable);
      await tester.tap(find.byKey(const ValueKey('account-verification-send')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('account-verification-send')));
      await tester.pump();

      expect(callable.payloads, hasLength(1));
      callable.completeFirst();
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('account-verification-accepted')),
        findsOne,
      );
    });

    testWidgets('a stale session is told to sign in again', (tester) async {
      final callable = _Callable(failWith: 'failed-precondition');

      await _pump(tester, callable);
      await tester.tap(find.byKey(const ValueKey('account-verification-send')));
      await tester.pump();
      await tester.pump();

      expect(
        noticeMessage(tester, 'account-verification-error'),
        contains('within five minutes'),
      );
      expect(
        find.byKey(const ValueKey('account-verification-accepted')),
        findsNothing,
      );
    });

    testWidgets('checking again re-reads the identity from the server', (
      tester,
    ) async {
      var reloads = 0;

      await _pump(tester, _Callable(), onReload: () async => reloads++);
      await tester.tap(
        find.byKey(const ValueKey('account-verification-recheck')),
      );
      await tester.pump();
      await tester.pump();

      // Without this the cached ID token would report the old claim forever.
      expect(reloads, 1);
      expect(
        find.byKey(const ValueKey('account-verification-error')),
        findsNothing,
      );
    });

    testWidgets('a failed recheck reports safely and stays usable', (
      tester,
    ) async {
      await _pump(
        tester,
        _Callable(),
        onReload: () async => throw StateError('offline'),
      );
      await tester.tap(
        find.byKey(const ValueKey('account-verification-recheck')),
      );
      await tester.pump();
      await tester.pump();

      expect(
        noticeMessage(tester, 'account-verification-error'),
        'The verification email could not be requested. Please try again.',
      );
      expect(pressable(tester, 'account-verification-recheck'), isTrue);
    });

    testWidgets('an undeliverable address is stated instead of retried', (
      tester,
    ) async {
      final status = _StatusCallable(
        answer: emailDeliveryUnavailableSentinel,
      );

      await _pump(tester, _Callable(), deliveryStatus: status);
      await tester.tap(find.byKey(const ValueKey('account-verification-send')));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // The address is only asked about once a request has been accepted,
      // which is exactly when the user starts waiting for a message.
      expect(status.calls, 1);
      expect(
        noticeMessage(tester, 'account-verification-undeliverable'),
        'This address cannot receive mail from us, so sending again will not '
        'help. Check the address or contact support.',
      );
    });

    testWidgets('a deliverable address adds no warning at all', (tester) async {
      final status = _StatusCallable();

      await _pump(tester, _Callable(), deliveryStatus: status);
      await tester.tap(find.byKey(const ValueKey('account-verification-send')));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(status.calls, 1);
      expect(
        find.byKey(const ValueKey('account-verification-undeliverable')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('account-verification-accepted')),
        findsOne,
      );
    });

    testWidgets('the status is never checked before a request is accepted', (
      tester,
    ) async {
      final status = _StatusCallable();

      await _pump(
        tester,
        _Callable(failWith: 'unavailable'),
        deliveryStatus: status,
      );
      await tester.tap(find.byKey(const ValueKey('account-verification-send')));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // The send failed, so there is nothing to explain the absence of.
      expect(status.calls, 0);
      expect(
        find.byKey(const ValueKey('account-verification-undeliverable')),
        findsNothing,
      );
    });

    testWidgets('a failed or unrecognised status stays silent', (tester) async {
      for (final broken in <_StatusCallable>[
        _StatusCallable(failWith: 'unavailable'),
        // A wording change server-side must never be read as "available", and
        // must never be shown to the user verbatim either.
        _StatusCallable(answer: 'who knows'),
      ]) {
        await _pump(tester, _Callable(), deliveryStatus: broken);
        await tester.tap(
          find.byKey(const ValueKey('account-verification-send')),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump();

        // The send itself succeeded, so a failed diagnostic about it must not
        // be reported as an error on the action the user took.
        expect(
          find.byKey(const ValueKey('account-verification-undeliverable')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('account-verification-error')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('account-verification-accepted')),
          findsOne,
        );
      }
    });

    testWidgets('an identity change discards an outstanding status read', (
      tester,
    ) async {
      final status = _StatusCallable(
        answer: emailDeliveryUnavailableSentinel,
        defer: true,
      );

      await _pump(tester, _Callable(), deliveryStatus: status);
      await tester.tap(find.byKey(const ValueKey('account-verification-send')));
      await tester.pump();
      await tester.pump();
      expect(status.calls, 1);

      await _pump(tester, _Callable(), deliveryStatus: status, uid: 'user-b');
      status.completeFirst();
      await tester.pump();
      await tester.pump();

      // Deliverability belongs to the address it was asked about, so the first
      // identity's answer must never label the second one's.
      expect(
        find.byKey(const ValueKey('account-verification-undeliverable')),
        findsNothing,
      );
    });

    testWidgets('another identity never inherits the previous request ID', (
      tester,
    ) async {
      final callable = _Callable();

      await _pump(tester, callable);
      await tester.tap(find.byKey(const ValueKey('account-verification-send')));
      await tester.pump();
      await tester.pump();

      await _pump(tester, callable, uid: 'user-b');
      await tester.tap(find.byKey(const ValueKey('account-verification-send')));
      await tester.pump();
      await tester.pump();

      expect(callable.payloads, hasLength(2));
      expect(callable.payloads[0], isNot(callable.payloads[1]));
      // The success state belongs to the previous identity and must not carry
      // over to the new one.
      expect(
        find.byKey(const ValueKey('account-verification-accepted')),
        findsOne,
      );
    });
  });
}

Future<void> _pump(
  WidgetTester tester,
  _Callable callable, {
  String uid = 'user-a',
  Future<void> Function()? onReload,
  _StatusCallable? deliveryStatus,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AccountVerificationPanel(
          identity: _identity(uid: uid),
          callable: callable,
          onReload: onReload ?? () async {},
          deliveryStatusCallable: deliveryStatus,
        ),
      ),
    ),
  );
  await tester.pump();
}

AccountVerificationGateway _gateway(
  _Callable callable, {
  String uid = 'user-a',
  bool emailVerified = false,
  bool globallyActive = true,
  String Function()? requestIdFactory,
}) => AccountVerificationGateway(
  identity: _identity(
    uid: uid,
    emailVerified: emailVerified,
    globallyActive: globallyActive,
  ),
  callable: callable,
  requestIdFactory: requestIdFactory,
);

AccountVerificationIdentity _identity({
  String uid = 'user-a',
  bool emailVerified = false,
  bool globallyActive = true,
}) => AccountVerificationIdentity(
  uid: uid,
  emailVerified: emailVerified,
  profile: RootRoutingProfile(
    accountType: RootAccountType.tenantUser,
    globalStatus: globallyActive ? 'active' : 'disabled',
  ),
);

final class _StatusCallable implements EmailDeliveryStatusCallable {
  _StatusCallable({
    this.answer = emailDeliveryAvailableSentinel,
    this.failWith,
    this.defer = false,
  });

  final Object? answer;
  final String? failWith;
  final bool defer;
  int calls = 0;
  final List<Completer<Object?>> _pending = <Completer<Object?>>[];

  void completeFirst() {
    if (_pending.isEmpty) return;
    _pending.removeAt(0).complete(answer);
  }

  @override
  Future<Object?> call() {
    calls++;
    final code = failWith;
    if (code != null) {
      return Future<Object?>.error(EmailDeliveryStatusCallableException(code));
    }
    if (!defer) return Future<Object?>.value(answer);
    final completer = Completer<Object?>();
    _pending.add(completer);
    return completer.future;
  }
}

final class _Callable implements SendAccountVerificationCallable {
  _Callable({
    this.response = const <String, Object?>{'accepted': true},
    this.failWith,
    this.defer = false,
  });

  final Object? response;
  String? failWith;
  final bool defer;
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];
  final List<Completer<Object?>> _pending = <Completer<Object?>>[];

  void completeFirst() {
    if (_pending.isEmpty) return;
    _pending.removeAt(0).complete(response);
  }

  @override
  Future<Object?> call(Map<String, Object?> payload) {
    payloads.add(Map<String, Object?>.of(payload));
    final code = failWith;
    if (code != null) {
      return Future<Object?>.error(AccountVerificationCallableException(code));
    }
    if (!defer) return Future<Object?>.value(response);
    final completer = Completer<Object?>();
    _pending.add(completer);
    return completer.future;
  }
}
