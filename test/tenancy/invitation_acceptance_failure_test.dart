import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every code the two acceptance callables can answer with, plus a few they
/// cannot, so the mapping is exercised past the cases it models.
const _codes = [
  'permission-denied',
  'failed-precondition',
  'unauthenticated',
  'resource-exhausted',
  'unavailable',
  'deadline-exceeded',
  'not-found',
  'invalid-argument',
  'already-exists',
  'aborted',
  'internal',
  'unknown',
  'cancelled',
  'data-loss',
  'out-of-range',
  'unimplemented',
  '',
];

/// The codes for which a retry is the honest advice, and the only ones.
const _transientCodes = {'resource-exhausted', 'unavailable', 'deadline-exceeded'};

void main() {
  group('invitation acceptance violations', () {
    test('mirror the server policy tokens exactly', () {
      // The wire values are the server's `InvitationAcceptanceViolation` union
      // in `functions/src/staff/acceptancePolicy.ts`. A token drifting here
      // makes a refusal fall silently through to the fallback sentence.
      //
      // `versioned_proof_required` is the one entry the server no longer
      // declares. It is kept because functions and installed apps are deployed
      // on different days, and an app talking to the previous deployment must
      // still render the refusal it gets.
      expect(
        InvitationAcceptanceViolation.values.map((v) => v.wireValue).toSet(),
        {
          'caller_mismatch',
          'tenant_inactive',
          'membership_not_pending',
          'invitation_not_pending',
          'email_mismatch',
          'invitation_consumed',
          'invitation_expired',
          'email_unverified',
          'versioned_proof_required',
        },
      );
    });

    test('read only a known token, and never throw on anything else', () {
      for (final violation in InvitationAcceptanceViolation.values) {
        expect(
          InvitationAcceptanceViolation.fromWireOrNull(violation.wireValue),
          violation,
        );
      }
      // An older client meeting a violation a later server adds must degrade to
      // the code-level sentence rather than turn a refusal into a crash.
      for (final unknown in <Object?>[
        null,
        '',
        'invented_violation',
        'VERSIONED_PROOF_REQUIRED',
        7,
        true,
        <String>['versioned_proof_required'],
      ]) {
        expect(InvitationAcceptanceViolation.fromWireOrNull(unknown), isNull);
      }
    });
  });

  group('invitation acceptance failure details', () {
    test('reads the server violation out of a callable details map', () {
      expect(
        invitationAcceptanceViolationFromDetails(<String, Object?>{
          'violation': 'versioned_proof_required',
        }),
        InvitationAcceptanceViolation.versionedProofRequired,
      );
      expect(
        invitationAcceptanceViolationFromDetails(<Object?, Object?>{
          'violation': 'tenant_inactive',
          'unrelated': 'ignored',
        }),
        InvitationAcceptanceViolation.tenantInactive,
      );
    });

    test('discards every shape that is not a known violation token', () {
      // `details` is `dynamic` on the wire. Anything arbitrary reaching a
      // widget is the defect this boundary exists to prevent, so shape is
      // judged before content.
      for (final details in <Object?>[
        null,
        'versioned_proof_required',
        <Object?>['versioned_proof_required'],
        <String, Object?>{},
        <String, Object?>{'violation': null},
        <String, Object?>{'violation': 42},
        <String, Object?>{'violation': 'not_a_violation'},
        <String, Object?>{'Violation': 'versioned_proof_required'},
        42,
      ]) {
        expect(invitationAcceptanceViolationFromDetails(details), isNull);
      }
    });
  });

  group('invitation acceptance safe error', () {
    test('sends a permanently refused acceptance to the emailed link', () {
      // Only a server deployed before 2026-09-08 answers this way. The advice
      // is now true where it was not: the emailed link opens the app on the
      // invitation, so a reader sent to it arrives somewhere.
      for (final mode in InvitationAcceptanceMode.values) {
        final message = invitationAcceptanceSafeError(
          const InvitationAcceptanceException(
            'permission-denied',
            violation: InvitationAcceptanceViolation.versionedProofRequired,
          ),
          mode: mode,
        );

        expect(message, contains('invitation email'));
        expect(message, isNot(contains('try again')));
      }
    });

    test('never invites a retry it cannot promise', () {
      // The organising rule, asserted rather than described. Every violation
      // the server names is permanent for the invitation it refused.
      for (final violation in InvitationAcceptanceViolation.values) {
        for (final mode in InvitationAcceptanceMode.values) {
          final message = invitationAcceptanceSafeError(
            InvitationAcceptanceException(
              'permission-denied',
              violation: violation,
            ),
            mode: mode,
          );

          expect(
            message,
            isNot(contains('try again')),
            reason: '${violation.wireValue} is permanent for this invitation',
          );
          expect(message, isNot(isEmpty));
        }
      }
    });

    test('offers a retry for transient codes only', () {
      for (final code in _codes) {
        for (final mode in InvitationAcceptanceMode.values) {
          final message = invitationAcceptanceSafeError(
            InvitationAcceptanceException(code),
            mode: mode,
          );

          expect(
            message.contains('try again'),
            _transientCodes.contains(code),
            reason: 'code "$code" must offer a retry only when one can work',
          );
        }
      }
    });

    test('answers every code with a sentence and never with a code', () {
      for (final code in _codes) {
        for (final mode in InvitationAcceptanceMode.values) {
          final message = invitationAcceptanceSafeError(
            InvitationAcceptanceException(code),
            mode: mode,
          );

          expect(message, isNot(isEmpty));
          expect(message, endsWith('.'));
          // The reported defect was a machine string reaching a person. No
          // rendered sentence may contain the code that produced it.
          if (code.isNotEmpty) expect(message, isNot(contains(code)));
        }
      }
    });

    test('splits an unexplained refusal by the path it came back from', () {
      // The server refuses without naming a violation for different reasons on
      // each path: a rejected HMAC proof on the token path, and an ineligible
      // signed-in identity on the visible one.
      const refusal = InvitationAcceptanceException('permission-denied');
      final token = invitationAcceptanceSafeError(
        refusal,
        mode: InvitationAcceptanceMode.token,
      );
      final visible = invitationAcceptanceSafeError(
        refusal,
        mode: InvitationAcceptanceMode.visible,
      );

      expect(token, isNot(visible));
      expect(token, contains('link'));
      expect(visible, contains('verified'));
    });

    test('names the five-minute window a stale session actually hit', () {
      // Acceptance requires an authentication under five minutes old, so this
      // is the ordinary cause of `failed-precondition` and the one a user can
      // act on.
      final message = invitationAcceptanceSafeError(
        const InvitationAcceptanceException('failed-precondition'),
        mode: InvitationAcceptanceMode.visible,
      );

      expect(message, contains('sign in again'));
      expect(message, contains('five minutes'));
    });

    test('reads a code and never a message', () {
      // Anything that is not this boundary's own exception — a raw plugin
      // failure, a malformed response, a programming mistake — answers one
      // sentence that names no cause and leaks nothing.
      for (final error in <Object>[
        StateError('raw backend secret detail'),
        const FormatException('acceptTenantInvitation returned nonsense'),
        ArgumentError.value('user-b', 'uid'),
        Exception('dev.flutter.pigeon.channel.failure'),
        'a bare string',
      ]) {
        for (final mode in InvitationAcceptanceMode.values) {
          final message = invitationAcceptanceSafeError(error, mode: mode);

          expect(message, isNot(contains('raw backend')));
          expect(message, isNot(contains('dev.flutter.pigeon')));
          expect(message, isNot(contains('nonsense')));
          expect(message, isNot(contains('try again')));
          expect(message, contains('administrator'));
        }
      }
    });

    test('gives an unmodelled code the same sentence as an unknown failure', () {
      expect(
        invitationAcceptanceSafeError(
          const InvitationAcceptanceException('teapot'),
          mode: InvitationAcceptanceMode.token,
        ),
        invitationAcceptanceSafeError(
          StateError('anything'),
          mode: InvitationAcceptanceMode.token,
        ),
      );
    });

    test('carries its code and violation for a log, not for a screen', () {
      const error = InvitationAcceptanceException(
        'permission-denied',
        violation: InvitationAcceptanceViolation.invitationConsumed,
      );

      expect(error.code, 'permission-denied');
      expect(error.violation, InvitationAcceptanceViolation.invitationConsumed);
      expect(error.toString(), contains('invitation_consumed'));
    });
  });
}
