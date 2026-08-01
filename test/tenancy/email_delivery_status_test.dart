import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('email delivery status', () {
    test('classifies exactly the two answers the server can give', () {
      expect(
        parseEmailDeliveryStatus('available'),
        EmailDeliveryStatus.available,
      );
      expect(
        parseEmailDeliveryStatus(
          'Email delivery unavailable. Check the address or contact support.',
        ),
        EmailDeliveryStatus.unavailable,
      );
      // The constants must stay byte-identical to the server's, because they
      // are matched rather than compared loosely.
      expect(emailDeliveryAvailableSentinel, 'available');
      expect(
        emailDeliveryUnavailableSentinel,
        'Email delivery unavailable. Check the address or contact support.',
      );
    });

    test('an unrecognised answer is never read as available', () {
      for (final answer in <Object?>[
        null,
        '',
        'Available',
        'AVAILABLE',
        ' available',
        'unavailable',
        'Email delivery unavailable.',
        true,
        1,
        <String, Object?>{'status': 'available'},
        <Object?>['available'],
      ]) {
        expect(
          () => parseEmailDeliveryStatus(answer),
          throwsA(isA<FormatException>()),
          reason: '$answer',
        );
      }
    });

    test('the reader asks for the caller and nobody else', () async {
      final callable = _Callable();

      final status = await EmailDeliveryStatusReader(callable: callable).read();

      // The callable takes no argument at all, so there is no parameter a
      // caller could use to ask about another address.
      expect(status, EmailDeliveryStatus.available);
      expect(callable.calls, 1);
    });

    test('a suppressed address is reported as unavailable', () async {
      final callable = _Callable(answer: emailDeliveryUnavailableSentinel);

      expect(
        await EmailDeliveryStatusReader(callable: callable).read(),
        EmailDeliveryStatus.unavailable,
      );
    });

    test('a signed-out caller and a transport failure both propagate', () async {
      for (final code in <String>['unauthenticated', 'unavailable', 'internal']) {
        final reader = EmailDeliveryStatusReader(
          callable: _Callable(failWith: code),
        );

        await expectLater(
          reader.read(),
          throwsA(
            isA<EmailDeliveryStatusCallableException>().having(
              (error) => error.code,
              'code',
              code,
            ),
          ),
        );
      }
    });

    test('an unrecognised answer surfaces as a refusal, not a status', () async {
      final reader = EmailDeliveryStatusReader(
        callable: _Callable(answer: 'maybe'),
      );

      await expectLater(reader.read(), throwsA(isA<FormatException>()));
    });
  });
}

final class _Callable implements EmailDeliveryStatusCallable {
  _Callable({this.answer = 'available', this.failWith});

  final Object? answer;
  final String? failWith;
  int calls = 0;

  @override
  Future<Object?> call() {
    calls++;
    final code = failWith;
    if (code != null) {
      return Future<Object?>.error(EmailDeliveryStatusCallableException(code));
    }
    return Future<Object?>.value(answer);
  }
}
