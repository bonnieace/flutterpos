import 'dart:io';

import 'package:uzapay_pos/checkout/checkout_outbox.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  group('staff request tickets', () {
    late Directory directory;
    late Box<dynamic> box;
    late HiveTenantStaffRequestTickets tickets;
    final key = List<int>.generate(
      HiveCheckoutOutbox.encryptionKeyBytes,
      (index) => index,
    );

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('staff-ticket-test-');
      Hive.init(directory.path);
      box = await Hive.openBox<dynamic>(
        HiveTenantStaffRequestTickets.boxName,
        encryptionCipher: HiveAesCipher(key),
        crashRecovery: false,
      );
      tickets = HiveTenantStaffRequestTickets.fromBox(box);
    });

    tearDown(() async {
      await Hive.close();
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test('mints once and replays the same id for the same request', () async {
      var minted = 0;
      String mint() => 'invite-${++minted}';

      final first = await tickets.resolve(
        uid: 'admin-a',
        tenantId: 'tenant-a',
        operation: 'inviteStaff',
        target: '',
        fingerprint: 'fp-1',
        mint: mint,
      );
      // The restart: nothing in memory survives, and the store is re-opened
      // over the same box.
      final resumed = HiveTenantStaffRequestTickets.fromBox(box);
      final second = await resumed.resolve(
        uid: 'admin-a',
        tenantId: 'tenant-a',
        operation: 'inviteStaff',
        target: '',
        fingerprint: 'fp-1',
        mint: mint,
      );

      expect(first, 'invite-1');
      expect(second, 'invite-1');
      expect(minted, 1);
    });

    test('mints a fresh id when the operator changed what they asked', () async {
      // **The one genuinely dangerous reuse.** Replaying an id against changed
      // values would have the server answer from its record of the first
      // attempt, so the new values would never be written while the form said
      // they had been.
      var minted = 0;
      String mint() => 'invite-${++minted}';

      final first = await tickets.resolve(
        uid: 'admin-a',
        tenantId: 'tenant-a',
        operation: 'inviteStaff',
        target: '',
        fingerprint: 'fp-1',
        mint: mint,
      );
      final afterEdit = await tickets.resolve(
        uid: 'admin-a',
        tenantId: 'tenant-a',
        operation: 'inviteStaff',
        target: '',
        fingerprint: 'fp-2',
        mint: mint,
      );

      expect(first, 'invite-1');
      expect(afterEdit, 'invite-2');
    });

    test('separates people, businesses, operations and targets', () async {
      var minted = 0;
      String mint() => 'id-${++minted}';
      const base = (
        uid: 'admin-a',
        tenantId: 'tenant-a',
        operation: 'updateStaffUser',
        target: 'staff-a',
      );

      await tickets.resolve(
        uid: base.uid,
        tenantId: base.tenantId,
        operation: base.operation,
        target: base.target,
        fingerprint: 'fp',
        mint: mint,
      );
      // Each of these differs from the first in exactly one dimension, and none
      // of them may inherit its id: the server keys its idempotency record on
      // the actor and the tenant, so another person's id answers nothing, and
      // another target is simply another operation.
      for (final variant in <Map<String, String>>[
        {'uid': 'admin-b'},
        {'tenantId': 'tenant-b'},
        {'operation': 'setStaffStatus'},
        {'target': 'staff-b'},
      ]) {
        final id = await tickets.resolve(
          uid: variant['uid'] ?? base.uid,
          tenantId: variant['tenantId'] ?? base.tenantId,
          operation: variant['operation'] ?? base.operation,
          target: variant['target'] ?? base.target,
          fingerprint: 'fp',
          mint: mint,
        );
        expect(id, isNot('id-1'));
      }
      expect(minted, 5);
    });

    test(
      'clearing ends the replay, so the next press is a new request',
      () async {
        var minted = 0;
        String mint() => 'id-${++minted}';

        final first = await tickets.resolve(
          uid: 'admin-a',
          tenantId: 'tenant-a',
          operation: 'inviteStaff',
          target: '',
          fingerprint: 'fp-1',
          mint: mint,
        );
        await tickets.clear(
          uid: 'admin-a',
          tenantId: 'tenant-a',
          operation: 'inviteStaff',
          target: '',
        );
        final afterAnswer = await tickets.resolve(
          uid: 'admin-a',
          tenantId: 'tenant-a',
          operation: 'inviteStaff',
          target: '',
          fingerprint: 'fp-1',
          mint: mint,
        );

        expect(first, 'id-1');
        expect(afterAnswer, 'id-2');
      },
    );

    test('an unreadable ticket is discarded rather than pinned', () async {
      await box.put(
        tenantStaffRequestTicketKey(
          uid: 'admin-a',
          tenantId: 'tenant-a',
          operation: 'inviteStaff',
          target: '',
        ),
        <String, Object?>{'tenantId': 'tenant-a', 'requestId': 42},
      );

      final id = await tickets.resolve(
        uid: 'admin-a',
        tenantId: 'tenant-a',
        operation: 'inviteStaff',
        target: '',
        fingerprint: 'fp-1',
        mint: () => 'fresh',
      );

      expect(id, 'fresh');
    });

    test('a fingerprint ignores field order but not field values', () {
      expect(
        tenantStaffRequestFingerprint(<String, Object?>{
          'email': 'a@example.test',
          'role': 'cashier',
        }),
        tenantStaffRequestFingerprint(<String, Object?>{
          'role': 'cashier',
          'email': 'a@example.test',
        }),
      );
      expect(
        tenantStaffRequestFingerprint(<String, Object?>{'role': 'cashier'}),
        isNot(
          tenantStaffRequestFingerprint(<String, Object?>{'role': 'manager'}),
        ),
      );
    });

    test(
      'a uid or operation that could forge a key mints without storing',
      () async {
        expect(
          () => tenantStaffRequestTicketKey(
            uid: 'admin::a',
            tenantId: 'tenant-a',
            operation: 'inviteStaff',
            target: '',
          ),
          throwsArgumentError,
        );

        // The gateway still gets an id; only the recovery is given up.
        final id = await tickets.resolve(
          uid: 'admin::a',
          tenantId: 'tenant-a',
          operation: 'inviteStaff',
          target: '',
          fingerprint: 'fp-1',
          mint: () => 'fresh',
        );
        expect(id, 'fresh');
      },
    );
  });
}
