/// The request id one unfinished staff mutation was asked under, kept on the
/// device rather than in a mounted form.
///
/// **The server's idempotency is durable and the client's was not.** Every
/// staff callable keys an idempotency record on the actor, the tenant and a
/// request id, so re-sending the same id returns what the first attempt did
/// instead of doing it twice. While a form stays mounted it holds its id and a
/// retry is exactly that replay. The id died with the form.
///
/// So an invitation whose answer went missing - sent, committed, the reply lost
/// on a bad connection, the app closed - came back as a *new* logical
/// operation: a fresh id, a fresh idempotency record, and a server that
/// correctly refuses to create a membership that already exists. The operator
/// is told the invitation failed, and it did not.
///
/// This is that id, written before the call and cleared after the answer, so a
/// second press after a restart is the same request rather than another one.
///
/// **Deliberately not the mutation outbox.** `TenantPendingMutationStore` defers
/// execution, which is right for stock moved in a back room with no signal and
/// wrong here: `inviteStaff` mints a Firebase identity and the directory is
/// keyed on the uid only the server can answer with, so a queued invitation
/// could show the operator nothing at all until it drained, and a mistyped
/// address would provision a real account for it an hour after the person who
/// typed it walked away. What was missing was never deferral. It was memory.
///
/// **One ticket per person, per business, per operation, per target.** The
/// server keys its record on the actor too, so somebody else's id answers
/// nothing, and two administrators editing two members hold two tickets.
///
/// The box is encrypted with the same key every other durable store here uses.
library;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../checkout/checkout_outbox.dart';
import 'tenant_id.dart';

/// Thrown when a ticket cannot be read or written.
final class TenantStaffRequestTicketException implements Exception {
  const TenantStaffRequestTicketException(this.code);

  final String code;

  @override
  String toString() => 'TenantStaffRequestTicketException($code)';
}

/// One staff mutation's durable request id, and what it was minted for.
@immutable
final class TenantStaffRequestTicket {
  const TenantStaffRequestTicket({
    required this.tenantId,
    required this.operation,
    required this.target,
    required this.fingerprint,
    required this.requestId,
  });

  factory TenantStaffRequestTicket.fromStorage(Map<Object?, Object?> raw) {
    final tenantId = raw['tenantId'];
    final operation = raw['operation'];
    final target = raw['target'];
    final fingerprint = raw['fingerprint'];
    final requestId = raw['requestId'];
    if (tenantId is! String ||
        operation is! String ||
        target is! String ||
        fingerprint is! String ||
        requestId is! String ||
        operation.isEmpty ||
        fingerprint.isEmpty ||
        requestId.isEmpty) {
      throw const TenantStaffRequestTicketException('ticket_unreadable');
    }
    try {
      validateTenantId(tenantId);
    } on ArgumentError {
      throw const TenantStaffRequestTicketException('ticket_unreadable');
    }
    return TenantStaffRequestTicket(
      tenantId: tenantId,
      operation: operation,
      target: target,
      fingerprint: fingerprint,
      requestId: requestId,
    );
  }

  final String tenantId;

  /// The callable this id was minted for, spelled as the callable is.
  final String operation;

  /// The staff member it acts on, or the empty string where the operation has
  /// no target yet - an invitation names an address, not a uid.
  final String target;

  /// What the operator asked for, reduced to one value.
  ///
  /// **The whole safety of reusing an id.** Replaying an id against a *changed*
  /// payload is the one genuinely dangerous move here: the server would answer
  /// from its record of the first attempt and the new values would never be
  /// written, while the form said it had saved them. So a ticket is only ever
  /// reused for the request it was minted for, and anything else mints a fresh
  /// id.
  final String fingerprint;

  final String requestId;

  Map<String, Object?> toStorage() => <String, Object?>{
    'tenantId': tenantId,
    'operation': operation,
    'target': target,
    'fingerprint': fingerprint,
    'requestId': requestId,
  };
}

/// Reduces one request's normalized fields to a single comparable value.
///
/// Takes the values the gateway will actually send, after its own
/// normalization, so that whitespace an operator cannot see does not read as a
/// different request.
String tenantStaffRequestFingerprint(Map<String, Object?> payload) {
  final keys = payload.keys.toList()..sort();
  final canonical = <String, Object?>{
    for (final key in keys) key: payload[key],
  };
  return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
}

/// Where unfinished staff mutations keep their request ids.
abstract interface class TenantStaffRequestTicketSource {
  /// The id to ask [operation] under, minting and storing one when this is a
  /// request the device has not already asked.
  ///
  /// Returns the stored id when [fingerprint] matches the ticket held for this
  /// session, operation and target - which is what makes a retry after a
  /// restart a replay rather than a second operation.
  Future<String> resolve({
    required String uid,
    required String tenantId,
    required String operation,
    required String target,
    required String fingerprint,
    required String Function() mint,
  });

  /// Discards the ticket once its answer has arrived.
  ///
  /// **Called on a refusal as well as a success.** Both are answers: the server
  /// has stated what happened, so there is nothing left to replay. Only a
  /// *missing* answer leaves a ticket behind, which is the case this exists for.
  Future<void> clear({
    required String uid,
    required String tenantId,
    required String operation,
    required String target,
  });
}

/// The storage key one unfinished staff mutation is held under.
String tenantStaffRequestTicketKey({
  required String uid,
  required String tenantId,
  required String operation,
  required String target,
}) {
  if (uid.isEmpty || uid.contains('::')) {
    throw ArgumentError.value(uid, 'uid', 'must be a plain identifier');
  }
  if (operation.isEmpty || operation.contains('::')) {
    throw ArgumentError.value(operation, 'operation', 'must be a plain name');
  }
  if (target.contains('::')) {
    throw ArgumentError.value(target, 'target', 'must be a plain identifier');
  }
  return 'staff-request::$uid::${validateTenantId(tenantId)}'
      '::$operation::$target';
}

final class HiveTenantStaffRequestTickets extends ChangeNotifier
    implements TenantStaffRequestTicketSource {
  HiveTenantStaffRequestTickets._(this._box);

  static const String boxName = 'tenant-staff-request-tickets-v1';

  final Box<dynamic> _box;

  static Future<HiveTenantStaffRequestTickets> open({
    required CheckoutOutboxEncryptionKeyProvider keyProvider,
    HiveInterface? hive,
  }) async {
    final key = await keyProvider.loadOrCreateKey();
    if (key.length != HiveCheckoutOutbox.encryptionKeyBytes) {
      throw const TenantStaffRequestTicketException('ticket_unreadable');
    }
    final box = await (hive ?? Hive).openBox<dynamic>(
      boxName,
      encryptionCipher: HiveAesCipher(List<int>.from(key)),
      crashRecovery: false,
    );
    return HiveTenantStaffRequestTickets._(box);
  }

  factory HiveTenantStaffRequestTickets.fromBox(Box<dynamic> box) =>
      HiveTenantStaffRequestTickets._(box);

  @override
  Future<String> resolve({
    required String uid,
    required String tenantId,
    required String operation,
    required String target,
    required String fingerprint,
    required String Function() mint,
  }) async {
    final String key;
    try {
      key = tenantStaffRequestTicketKey(
        uid: uid,
        tenantId: tenantId,
        operation: operation,
        target: target,
      );
    } on ArgumentError {
      // **A key this device cannot form is not a reason to refuse the write.**
      // The id is a recovery aid; minting a fresh one costs an operator nothing
      // they would notice, and failing the mutation outright would cost them
      // the thing they were actually trying to do.
      return mint();
    }
    final held = _read(key);
    if (held != null &&
        held.operation == operation &&
        held.target == target &&
        held.tenantId == tenantId &&
        held.fingerprint == fingerprint) {
      return held.requestId;
    }
    final requestId = mint();
    try {
      await _box.put(
        key,
        TenantStaffRequestTicket(
          tenantId: tenantId,
          operation: operation,
          target: target,
          fingerprint: fingerprint,
          requestId: requestId,
        ).toStorage(),
      );
      notifyListeners();
    } catch (_) {
      // Same reasoning: a device that cannot write its own ticket can still
      // perform the mutation, it just cannot recover it deterministically.
    }
    return requestId;
  }

  @override
  Future<void> clear({
    required String uid,
    required String tenantId,
    required String operation,
    required String target,
  }) async {
    try {
      await _box.delete(
        tenantStaffRequestTicketKey(
          uid: uid,
          tenantId: tenantId,
          operation: operation,
          target: target,
        ),
      );
      notifyListeners();
    } catch (_) {
      // A ticket that cannot be deleted is re-sent once more and answered from
      // the server's record, which is the safe direction.
    }
  }

  TenantStaffRequestTicket? _read(String key) {
    final raw = _box.get(key);
    if (raw is! Map) return null;
    try {
      return TenantStaffRequestTicket.fromStorage(
        Map<Object?, Object?>.from(raw),
      );
    } on TenantStaffRequestTicketException {
      // Unreadable is indistinguishable from absent for every purpose this
      // serves, and keeping it would pin a stale id to this operation for ever.
      unawaited(_box.delete(key));
      return null;
    }
  }
}
