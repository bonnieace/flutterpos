import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('building a reset request', () {
    test('the address is normalized before it is sent', () {
      // The server normalizes too. Doing it here as well keeps one address from
      // becoming two different request subjects on a retry, which would defeat
      // the task-ID deduplication the server relies on.
      final intent = _gateway().createIntent(email: '  Owner@Example.COM  ');

      expect(intent.email, 'owner@example.com');
      expect(intent.toPayload()['email'], 'owner@example.com');
    });

    test('every request carries an id the server will accept', () {
      final intent = _gateway().createIntent(email: 'owner@example.com');

      expect(intent.requestId, matches(r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$'));
      expect(intent.toPayload()['requestId'], intent.requestId);
    });

    test('two requests are two subjects', () {
      final gateway = _gateway();

      expect(
        gateway.createIntent(email: 'a@b.co').requestId,
        isNot(gateway.createIntent(email: 'a@b.co').requestId),
      );
    });

    test('an empty address is refused before the server is asked', () {
      expect(
        () => _gateway().createIntent(email: '   '),
        throwsA(isA<StateError>()),
      );
      expect(
        passwordResetInputDefect(email: '   '),
        PasswordResetInputDefect.missingEmail,
      );
      expect(passwordResetInputDefect(email: 'a@b.co'), isNull);
    });

    test('a generator that produces an unusable id is a defect, not a send', () {
      final gateway = PasswordResetGateway(
        callable: _Callable(),
        requestIdFactory: () => 'no',
      );

      expect(
        () => gateway.createIntent(email: 'a@b.co'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('sending it', () {
    test('the payload is exactly the two fields the server reads', () async {
      final callable = _Callable();
      final gateway = PasswordResetGateway(callable: callable);
      final intent = gateway.createIntent(email: 'owner@example.com');

      await gateway.submit(intent);

      expect(callable.payloads.single.keys.toSet(), <String>{
        'email',
        'requestId',
      });
    });

    test('an accepted request is not inspected for whether an account exists', () async {
      // The server answers `{accepted: true}` for an address it knows and one
      // it does not, deliberately, so that this endpoint cannot be used to
      // discover who has an account. Parsing the response could only ever
      // reintroduce the distinction the server refused to draw - so submitting
      // succeeds whatever comes back.
      for (final response in <Object?>[
        <String, Object?>{'accepted': true},
        <String, Object?>{},
        null,
        'anything',
      ]) {
        final gateway = PasswordResetGateway(callable: _Callable(response));
        await gateway.submit(gateway.createIntent(email: 'a@b.co'));
      }
    });

    test('the accepted sentence promises nothing about an account', () {
      expect(passwordResetAcceptedMessage, contains('If that address'));
      // It must not assert that an email was sent to this person.
      expect(passwordResetAcceptedMessage, isNot(contains('We have sent')));
    });
  });

  group('what the server refused', () {
    test('an unreachable server is not a refusal', () {
      for (final code in <String>['unavailable', 'deadline-exceeded']) {
        expect(
          passwordResetFailure(PasswordResetCallableException(code)).kind,
          PasswordResetFailureKind.unreachable,
        );
      }
    });

    test('a failed App Check blames the app, not the person', () {
      // The expected answer in a release build with no attestation configured.
      // It is nobody's fault and no address's, so the sentence names neither.
      final failure = passwordResetFailure(
        const PasswordResetCallableException('unauthenticated'),
      );

      expect(failure.kind, PasswordResetFailureKind.refused);
      expect(failure.message, contains('could not prove itself'));
    });

    test('no failure sentence ever says whether an account exists', () {
      for (final code in <String>[
        'unavailable',
        'resource-exhausted',
        'unauthenticated',
        'permission-denied',
        'invalid-argument',
        'not-found',
        'anything-else',
      ]) {
        final message = passwordResetFailure(
          PasswordResetCallableException(code),
        ).message.toLowerCase();
        expect(message, isNot(contains('no account')));
        expect(message, isNot(contains('not registered')));
        expect(message, isNot(contains('does not exist')));
      }
    });

    test('nothing this app did not write can reach a person', () {
      for (final error in <Object>[StateError('raw'), 'a bare string']) {
        expect(
          passwordResetFailure(error).message,
          contains('could not be sent'),
        );
      }
    });
  });
}

PasswordResetGateway _gateway() =>
    PasswordResetGateway(callable: _Callable());

final class _Callable implements RequestPasswordResetCallable {
  _Callable([this._response = const <String, Object?>{'accepted': true}]);

  final Object? _response;
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(payload);
    return _response;
  }
}
