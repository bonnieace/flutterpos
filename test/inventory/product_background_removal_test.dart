import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_application_1/inventory/inventory.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 1x1 PNG - a real one, because the candidate sniffs the magic number.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+'
  'A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

/// A different real PNG, standing in for the cut-out that comes back.
final Uint8List _cutOut = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAE0lEQVR4nGP4z8DwnwGM'
  '/zMwAAAf7gP9NRsAMwAAAABJRU5ErkJggg==',
);

void main() {
  group('background remover', () {
    test('sends the session tenant and the chosen bytes, and nothing else', () {
      // **No key, no endpoint, no vendor name on this side.** The old app put
      // all three in the APK; everything this client knows is which business is
      // asking and what it is asking about.
      final callable = _Callable(_answer());

      return _remover(callable)
          .remove(session: _session(), candidate: _candidate())
          .then((_) {
            expect(callable.payloads.single, <String, Object?>{
              'tenantId': 'tenant-a',
              'imageBase64': base64Encode(_png),
            });
          });
    });

    test('returns the cut-out as a candidate the form can save', () async {
      final result = await _remover(
        _Callable(_answer()),
      ).remove(session: _session(), candidate: _candidate());

      expect(result.bytes, _cutOut);
      expect(result.type, TenantProductImageType.png);
      // The name says what it is. A `.jpg` over PNG bytes is the kind of small
      // lie only ever found by somebody debugging something else.
      expect(result.fileName, 'shelf-cutout.png');
    });

    test('a session that may not correct products sends nothing at all', () {
      final callable = _Callable(_answer());

      expect(
        () => _remover(callable).remove(
          session: _session(role: TenantRole.cashier),
          candidate: _candidate(),
        ),
        throwsA(
          isA<TenantBackgroundRemovalException>().having(
            (error) => error.failure,
            'failure',
            TenantBackgroundRemovalFailure.forbidden,
          ),
        ),
      );
      expect(callable.payloads, isEmpty);
    });

    test('a cashier is never offered the action in the first place', () {
      final remover = _remover(_Callable(_answer()));

      expect(remover.canRemoveInSession(_session()), isTrue);
      expect(
        remover.canRemoveInSession(_session(role: TenantRole.cashier)),
        isFalse,
      );
    });

    test('an answer that is not an image is a refusal, not a broken picture', () async {
      // The bytes go straight to `Image.memory` and then to Storage, so an
      // answer that got past here would surface as a broken photograph in the
      // catalog rather than as a failure anybody could act on.
      for (final answer in <Object?>[
        null,
        'not a map',
        <String, Object?>{},
        <String, Object?>{'imageBase64': ''},
        <String, Object?>{'imageBase64': base64Encode(<int>[1, 2, 3, 4])},
      ]) {
        await expectLater(
          _remover(
            _Callable(answer),
          ).remove(session: _session(), candidate: _candidate()),
          throwsA(
            isA<TenantBackgroundRemovalException>().having(
              (error) => error.failure,
              'failure',
              TenantBackgroundRemovalFailure.unavailable,
            ),
          ),
        );
      }
    });

    test('every refusal the server can raise has its own outcome', () async {
      const cases = <String, TenantBackgroundRemovalFailure>{
        'permission-denied': TenantBackgroundRemovalFailure.forbidden,
        'unauthenticated': TenantBackgroundRemovalFailure.forbidden,
        'failed-precondition': TenantBackgroundRemovalFailure.unconfigured,
        'resource-exhausted': TenantBackgroundRemovalFailure.allowanceSpent,
        'out-of-range': TenantBackgroundRemovalFailure.tooLarge,
        'invalid-argument': TenantBackgroundRemovalFailure.unusableImage,
        'unavailable': TenantBackgroundRemovalFailure.unavailable,
        // An outcome nobody wrote a case for still reports truthfully that
        // nothing changed, which is the only thing the classification is for.
        'something-new': TenantBackgroundRemovalFailure.unavailable,
      };
      for (final entry in cases.entries) {
        await expectLater(
          _remover(_Callable.failing(entry.key)).remove(
            session: _session(),
            candidate: _candidate(),
          ),
          throwsA(
            isA<TenantBackgroundRemovalException>().having(
              (error) => error.failure,
              'failure',
              entry.value,
            ),
          ),
          reason: entry.key,
        );
      }
    });

    test('an oversized answer is told apart from an unreadable one', () async {
      await expectLater(
        _remover(
          _Callable.failing(
            'invalid-argument',
            message: 'imageBase64 exceeds the maximum product image size.',
          ),
        ).remove(session: _session(), candidate: _candidate()),
        throwsA(
          isA<TenantBackgroundRemovalException>().having(
            (error) => error.failure,
            'failure',
            TenantBackgroundRemovalFailure.tooLarge,
          ),
        ),
      );
    });

    test('every message says the chosen photograph is unchanged', () {
      // The one thing an operator needs to know after a failed cut-out.
      for (final failure in TenantBackgroundRemovalFailure.values) {
        expect(
          backgroundRemovalMessage(failure),
          contains('unchanged'),
          reason: failure.name,
        );
      }
    });
  });

  group('cut-out naming', () {
    test('keeps the stem and states the new type', () {
      expect(cutOutFileName('shelf.jpg'), 'shelf-cutout.png');
      expect(cutOutFileName('shelf.tall.webp'), 'shelf.tall-cutout.png');
      expect(cutOutFileName('shelf'), 'shelf-cutout.png');
      // A dotfile has no stem to keep, so the whole name is one.
      expect(cutOutFileName('.hidden'), '.hidden-cutout.png');
      expect(cutOutFileName('   '), 'cutout.png');
    });
  });
}

TenantSession _session({TenantRole role = TenantRole.manager}) =>
    TenantSession.active(uid: 'manager-a', tenantId: 'tenant-a', role: role);

TenantProductImageCandidate _candidate() =>
    TenantProductImageCandidate(bytes: _png, fileName: 'shelf.jpg');

CallableTenantProductBackgroundRemover _remover(_Callable callable) =>
    CallableTenantProductBackgroundRemover(callable: callable);

Map<String, Object?> _answer() => <String, Object?>{
  'imageBase64': base64Encode(_cutOut),
  'contentType': 'image/png',
};

final class _Callable implements RemoveProductBackgroundCallable {
  _Callable(this._answer) : _code = null, _message = null;

  _Callable.failing(String code, {String message = 'refused'})
    : _answer = null,
      _code = code,
      _message = message;

  final Object? _answer;
  final String? _code;
  final String? _message;
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(payload);
    final code = _code;
    if (code != null) {
      throw FirebaseFunctionsException(code: code, message: _message ?? '');
    }
    return _answer;
  }
}
