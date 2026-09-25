import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';

import '../checkout/checkout_outbox.dart';
import 'tenant_id.dart';
import 'tenant_paths.dart';
import 'tenant_repository.dart';
import 'tenant_session.dart';
import 'tenant_switch.dart';

enum TenantPendingMutationKind {
  expenseCreate,
  expenseVoid,
  pendingReturnCreate,
  brandingMerge,
  printerConfigurationMerge,

  /// Bringing a product into the catalog. **A callable since 2026-09-13**, and
  /// `allow create` on `products` is now `if false`. It had to become one: a
  /// create may carry an opening quantity, and the `stock_adjustments` record
  /// and `stock_movements` entry saying where those units came from cannot be
  /// written by any client. The queued payload is the document a device
  /// composed; the drain builds the callable's envelope from `targetPath`.
  productCreate,

  /// Taking a product out of it. **Also a callable, and no longer a delete.**
  /// Retiring clears the stock the product held, and whoever writes a quantity
  /// writes the movement that accounts for it.
  productRetire,

  categoryCreate,
  categoryRename,

  /// Correcting a product's descriptive fields. **Not a Firestore write**, and
  /// it never can be: `allow update` on `products` permits a strictly
  /// decreasing quantity and nothing else, so a price edit goes through
  /// `updateProduct` and the Admin SDK. The queue carries it as a callable
  /// payload, which is safe to replay because the payload names a `requestId`
  /// the server keeps an idempotency record against.
  productCorrect,

  /// Moving stock. A callable for the same reason - `stock_adjustments` and
  /// `stock_movements` are server-write-only, so a device cannot give an
  /// adjustment its ledger entry. Replay-safe on its own `requestId`.
  stockAdjust,

  /// One page of a stock take: what somebody counted, and what their device
  /// believed at the time.
  ///
  /// **Every page of one take carries the same `targetPath`**, which is the
  /// take itself rather than any product. That is deliberate twice over: the
  /// drain keeps one path's records in order, so the pages of a count go up in
  /// order, while two people's counts drain independently of one another.
  ///
  /// Replay-safe without a `requestId` in the payload. The server keys its
  /// idempotency record on the take and the page number, both of which are
  /// already here, so a page may be re-sent at any time and land on the same
  /// documents with the same values.
  stockTakePage,

  /// Adding a supplier. **A callable for the reason categories are**: two
  /// suppliers folding to one name would split one supplier's deliveries in
  /// two, and only the server can read every other name inside the transaction
  /// that writes. The payload is the document a device composed.
  supplierCreate,

  /// Correcting one supplier - its name, its contact details, or whether it is
  /// still offered. Replay-safe by construction: setting a field to the value
  /// it holds leaves the same document.
  supplierUpdate,

  /// One page of one supplier delivery: up to sixteen product lines, each
  /// restocked and, where it names a unit cost, re-costed.
  ///
  /// **Every page of one delivery carries the same `targetPath`**, which is the
  /// delivery rather than any product - so the pages drain in order, and a
  /// refusal strands that one delivery rather than every later stock change to
  /// the products in it. It is the first kind that **touches more than the
  /// document it names**: see [tenantMutationTouchedPaths].
  supplierDeliveryPage,

  /// One completed production batch: the product's stock goes up by what was
  /// made and its cost becomes what one unit cost to make.
  ///
  /// **Addressed to the batch, not the product**, for the reason a delivery
  /// page is: a batch that is refused must not hold every later adjustment to
  /// the product behind it.
  productionComplete,
}

/// Whether the queue reaches this kind through the Admin SDK rather than
/// through a document write.
///
/// It is the one distinction that changes what a queued record means offline: a
/// document write is applied by Firestore's own cache the moment it is
/// submitted, whereas a callable does nothing at all until the device can reach
/// the server. Both are durable here; only the second is invisible to Firestore.
bool tenantMutationIsCallable(TenantPendingMutationKind kind) => switch (kind) {
  // Everything that writes a quantity, or a document only the Admin SDK may
  // write. A `switch` rather than a chain of comparisons so that adding a kind
  // and forgetting to classify it stops compiling - which is how the two
  // product kinds below came to be listed on the wrong side of this for a
  // commit after they became callables.
  TenantPendingMutationKind.productCreate ||
  TenantPendingMutationKind.productRetire ||
  TenantPendingMutationKind.productCorrect ||
  TenantPendingMutationKind.stockAdjust ||
  TenantPendingMutationKind.stockTakePage ||
  // A supplier's name must be unique, and a delivery and a batch each move
  // stock and set a cost in one transaction with the ledger entry that
  // accounts for it.
  TenantPendingMutationKind.supplierCreate ||
  TenantPendingMutationKind.supplierUpdate ||
  TenantPendingMutationKind.supplierDeliveryPage ||
  TenantPendingMutationKind.productionComplete ||
  // **Neither of these writes a quantity.** They are here for the other half of
  // the rule - a document only the Admin SDK may write - and the reason is
  // uniqueness: two categories folding to one name make every spreadsheet that
  // names that category ambiguous, and refusing the second one means reading
  // every other category in the collection inside the transaction that writes.
  // A rule cannot query, and a device cannot see what it has not read.
  TenantPendingMutationKind.categoryCreate ||
  TenantPendingMutationKind.categoryRename => true,
  TenantPendingMutationKind.expenseCreate ||
  TenantPendingMutationKind.expenseVoid ||
  TenantPendingMutationKind.pendingReturnCreate ||
  TenantPendingMutationKind.brandingMerge ||
  TenantPendingMutationKind.printerConfigurationMerge => false,
};

enum TenantPendingMutationState {
  queued,
  submitting,
  awaitingConfirmation,
  confirmed,
  rejected,
  needsAttention,
}

final class TenantPendingMutationException implements Exception {
  const TenantPendingMutationException(this.code);

  final String code;

  @override
  String toString() => 'TenantPendingMutationException($code)';
}

final class TenantPendingMutationRecord {
  TenantPendingMutationRecord._({
    required this.uid,
    required this.tenantId,
    required this.operationId,
    required this.kind,
    required this.targetPath,
    required Map<String, Object?> payload,
    required this.payloadHash,
    required this.replacedValueFingerprint,
    required this.state,
    required this.attemptCount,
    required this.retryAt,
    required this.leaseOwner,
    required this.leaseExpiresAt,
    required this.createdAt,
    required this.updatedAt,
    required this.reasonCode,
  }) : payload = _freezeMap(payload);

  static const int schemaVersion = 1;

  final String uid;
  final String tenantId;
  final String operationId;
  final TenantPendingMutationKind kind;
  final String targetPath;
  final Map<String, Object?> payload;
  final String payloadHash;
  final String? replacedValueFingerprint;
  final TenantPendingMutationState state;
  final int attemptCount;
  final DateTime? retryAt;
  final String? leaseOwner;
  final DateTime? leaseExpiresAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? reasonCode;

  String get storageKey => tenantPendingMutationStorageKey(
    uid: uid,
    tenantId: tenantId,
    operationId: operationId,
  );

  bool get isUnresolved =>
      state != TenantPendingMutationState.confirmed &&
      state != TenantPendingMutationState.rejected;

  Map<String, Object?> toStorage() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'uid': uid,
    'tenantId': tenantId,
    'operationId': operationId,
    'kind': kind.name,
    'targetPath': targetPath,
    'payload': _mutableJson(payload),
    'payloadHash': payloadHash,
    'replacedValueFingerprint': replacedValueFingerprint,
    'state': state.name,
    'attemptCount': attemptCount,
    'retryAtMs': retryAt?.millisecondsSinceEpoch,
    'leaseOwner': leaseOwner,
    'leaseExpiresAtMs': leaseExpiresAt?.millisecondsSinceEpoch,
    'createdAtMs': createdAt.millisecondsSinceEpoch,
    'updatedAtMs': updatedAt.millisecondsSinceEpoch,
    'reasonCode': reasonCode,
  };

  TenantPendingMutationRecord copyWith({
    required TenantPendingMutationState state,
    required DateTime updatedAt,
    int? attemptCount,
    DateTime? retryAt,
    String? leaseOwner,
    DateTime? leaseExpiresAt,
    String? reasonCode,
  }) => TenantPendingMutationRecord._(
    uid: uid,
    tenantId: tenantId,
    operationId: operationId,
    kind: kind,
    targetPath: targetPath,
    payload: payload,
    payloadHash: payloadHash,
    replacedValueFingerprint: replacedValueFingerprint,
    state: state,
    attemptCount: attemptCount ?? this.attemptCount,
    retryAt: retryAt,
    leaseOwner: leaseOwner,
    leaseExpiresAt: leaseExpiresAt,
    createdAt: createdAt,
    updatedAt: updatedAt,
    reasonCode: reasonCode,
  );
}

String tenantPendingMutationStorageKey({
  required String uid,
  required String tenantId,
  required String operationId,
}) {
  final safeUid = _keySegment(uid, 'uid');
  final safeTenant = validateTenantId(tenantId);
  final safeOperation = validateTenantDocumentId(
    operationId,
    fieldName: 'operationId',
  );
  if (safeOperation.contains(':')) {
    throw ArgumentError('operationId must not contain a colon.');
  }
  return '$safeUid:$safeTenant:$safeOperation';
}

String tenantMutationFingerprint(Map<String, Object?> value) =>
    sha256.convert(utf8.encode(jsonEncode(_canonicalJson(value)))).toString();

/// Stable comparison value for configuration conflict detection.
///
/// Server timestamps are transport metadata rather than configuration, and
/// Firestore timestamp values cannot be encoded as canonical JSON.
String tenantConfigurationMutationFingerprint(Map<String, Object?> value) =>
    tenantMutationFingerprint(<String, Object?>{
      for (final entry in value.entries)
        if (entry.key != 'updatedAt' && _isJsonValue(entry.value))
          entry.key: entry.value,
    });

final class TenantPendingMutationStore {
  TenantPendingMutationStore._(this._box, this._clock);

  static const String boxName = 'tenant-mutation-outbox-v1';
  static const Duration leaseDuration = Duration(minutes: 2);
  static const Duration confirmedRetention = Duration(days: 7);
  static const Duration initialBackoff = Duration(seconds: 30);
  static const Duration maximumBackoff = Duration(minutes: 30);
  static final Map<String, Future<void>> _tails = <String, Future<void>>{};

  final Box<dynamic> _box;
  final DateTime Function() _clock;
  final StreamController<void> _changes = StreamController<void>.broadcast(
    sync: true,
  );

  /// Fires after durable local evidence changes. The landing page combines
  /// this with checkout-outbox signals so queued non-sale work is visible
  /// immediately, not only after the next reconnect.
  Stream<void> get changes => _changes.stream;

  bool isDue(TenantPendingMutationRecord record) =>
      record.retryAt?.isAfter(_clock().toUtc()) != true;

  bool hasActiveLease(TenantPendingMutationRecord record) =>
      record.state == TenantPendingMutationState.submitting &&
      record.leaseExpiresAt?.isAfter(_clock().toUtc()) == true;

  static Future<TenantPendingMutationStore> open({
    required CheckoutOutboxEncryptionKeyProvider keyProvider,
    HiveInterface? hive,
    DateTime Function()? clock,
  }) async {
    final key = await keyProvider.loadOrCreateKey();
    if (key.length != HiveCheckoutOutbox.encryptionKeyBytes) {
      throw const TenantPendingMutationException('invalid_encryption_key');
    }
    final box = await (hive ?? Hive).openBox<dynamic>(
      boxName,
      encryptionCipher: HiveAesCipher(List<int>.from(key)),
      crashRecovery: false,
    );
    return TenantPendingMutationStore._(box, clock ?? _utcNow);
  }

  factory TenantPendingMutationStore.fromBox(
    Box<dynamic> box, {
    DateTime Function()? clock,
  }) => TenantPendingMutationStore._(box, clock ?? _utcNow);

  Future<TenantPendingMutationRecord> enqueue({
    required String uid,
    required String tenantId,
    required String operationId,
    required TenantPendingMutationKind kind,
    required String targetPath,
    required Map<String, Object?> payload,
    String? replacedValueFingerprint,
  }) async {
    final key = tenantPendingMutationStorageKey(
      uid: uid,
      tenantId: tenantId,
      operationId: operationId,
    );
    _requireTarget(tenantId, targetPath, kind);
    final frozen = _freezeMap(payload);
    final hash = tenantMutationFingerprint(frozen);
    return _serialized(key, () async {
      final raw = _box.get(key);
      if (raw != null) {
        final existing = _parseRecord(key, raw);
        if (existing.payloadHash == hash &&
            existing.targetPath == targetPath &&
            existing.kind == kind) {
          return existing;
        }
        throw const TenantPendingMutationException('operation_id_conflict');
      }
      final now = _clock().toUtc();
      final record = TenantPendingMutationRecord._(
        uid: uid,
        tenantId: tenantId,
        operationId: operationId,
        kind: kind,
        targetPath: targetPath,
        payload: frozen,
        payloadHash: hash,
        replacedValueFingerprint: replacedValueFingerprint,
        state: TenantPendingMutationState.queued,
        attemptCount: 0,
        retryAt: now,
        leaseOwner: null,
        leaseExpiresAt: null,
        createdAt: now,
        updatedAt: now,
        reasonCode: null,
      );
      await _box.put(key, record.toStorage());
      _changes.add(null);
      return record;
    });
  }

  Future<List<TenantPendingMutationRecord>> recordsForSession({
    required String uid,
    required String tenantId,
  }) async {
    final prefix = '${_keySegment(uid, 'uid')}:${validateTenantId(tenantId)}:';
    final records = <TenantPendingMutationRecord>[];
    for (final rawKey in _box.keys) {
      if (rawKey is! String || !rawKey.startsWith(prefix)) continue;
      records.add(_parseRecord(rawKey, _box.get(rawKey)));
    }
    records.sort((a, b) {
      final time = a.createdAt.compareTo(b.createdAt);
      return time != 0 ? time : a.operationId.compareTo(b.operationId);
    });
    return List<TenantPendingMutationRecord>.unmodifiable(records);
  }

  Future<TenantPendingMutationRecord> acquire(
    TenantPendingMutationRecord record, {
    required String leaseOwner,
  }) => _change(record, (current, now) {
    final expired = current.leaseExpiresAt?.isAfter(now) != true;
    if (current.state == TenantPendingMutationState.submitting && !expired) {
      throw const TenantPendingMutationException('lease_held');
    }
    if (current.state != TenantPendingMutationState.queued &&
        current.state != TenantPendingMutationState.submitting) {
      throw const TenantPendingMutationException('invalid_transition');
    }
    if (current.retryAt?.isAfter(now) == true) {
      throw const TenantPendingMutationException('retry_not_due');
    }
    return current.copyWith(
      state: TenantPendingMutationState.submitting,
      updatedAt: now,
      attemptCount: current.attemptCount + 1,
      leaseOwner: _keySegment(leaseOwner, 'leaseOwner'),
      leaseExpiresAt: now.add(leaseDuration),
    );
  });

  Future<TenantPendingMutationRecord> markAwaiting(
    TenantPendingMutationRecord record,
  ) => _transition(record, TenantPendingMutationState.awaitingConfirmation);

  Future<TenantPendingMutationRecord> markConfirmed(
    TenantPendingMutationRecord record,
  ) => _transition(record, TenantPendingMutationState.confirmed);

  Future<TenantPendingMutationRecord> markRejected(
    TenantPendingMutationRecord record,
    String reasonCode,
  ) => _transition(
    record,
    TenantPendingMutationState.rejected,
    reasonCode: reasonCode,
  );

  Future<TenantPendingMutationRecord> markNeedsAttention(
    TenantPendingMutationRecord record,
    String reasonCode,
  ) => _transition(
    record,
    TenantPendingMutationState.needsAttention,
    reasonCode: reasonCode,
  );

  Future<TenantPendingMutationRecord> retryLater(
    TenantPendingMutationRecord record,
  ) => _change(record, (current, now) {
    final exponent = current.attemptCount.clamp(1, 7) - 1;
    final seconds = initialBackoff.inSeconds * (1 << exponent);
    final delay = Duration(
      seconds: seconds.clamp(
        initialBackoff.inSeconds,
        maximumBackoff.inSeconds,
      ),
    );
    return current.copyWith(
      state: TenantPendingMutationState.queued,
      updatedAt: now,
      attemptCount: current.attemptCount,
      retryAt: now.add(delay),
    );
  });

  Future<void> purgeConfirmed() async {
    final before = _clock().toUtc().subtract(confirmedRetention);
    for (final key in _box.keys.toList(growable: false)) {
      if (key is! String) continue;
      final record = _parseRecord(key, _box.get(key));
      if (record.state == TenantPendingMutationState.confirmed &&
          record.updatedAt.isBefore(before)) {
        await _box.delete(key);
        _changes.add(null);
      }
    }
  }

  /// Withdraws a mutation that has not been sent.
  ///
  /// **This is what an *Undo* is made of, and why the offer has to expire.** A
  /// record still in [TenantPendingMutationState.queued] exists only on this
  /// device; deleting it un-does the change completely, with nothing to
  /// reconcile. One that has reached `submitting` may already be on the server,
  /// and a device that cannot tell has no business claiming it took the change
  /// back — so this refuses rather than guesses, and the caller withdraws the
  /// offer instead of showing one that would lie.
  ///
  /// Returns whether anything was withdrawn. A record that has already been
  /// confirmed, rejected, or purged is not an error: the answer to "is this
  /// still undoable" is simply no.
  Future<bool> cancel({
    required String uid,
    required String tenantId,
    required String operationId,
  }) async {
    final key = tenantPendingMutationStorageKey(
      uid: uid,
      tenantId: tenantId,
      operationId: operationId,
    );
    return _serialized(key, () async {
      final raw = _box.get(key);
      if (raw == null) return false;
      final record = _parseRecord(key, raw);
      if (record.state != TenantPendingMutationState.queued) return false;
      // A lease outlives the state it was taken under only if a worker died
      // mid-submission, and that submission may have landed. Treat any lease
      // still in the record as a submission that happened.
      if (record.leaseOwner != null) return false;
      await _box.delete(key);
      _changes.add(null);
      return true;
    });
  }

  /// Removes retained failure evidence only after a person has reviewed it.
  Future<void> acknowledge({
    required String uid,
    required String tenantId,
    required String operationId,
  }) async {
    final key = tenantPendingMutationStorageKey(
      uid: uid,
      tenantId: tenantId,
      operationId: operationId,
    );
    await _serialized(key, () async {
      final raw = _box.get(key);
      if (raw == null) return;
      final record = _parseRecord(key, raw);
      if (record.state != TenantPendingMutationState.rejected &&
          record.state != TenantPendingMutationState.needsAttention) {
        throw const TenantPendingMutationException('not_reviewable');
      }
      await _box.delete(key);
      _changes.add(null);
    });
  }

  Future<TenantPendingMutationRecord> _transition(
    TenantPendingMutationRecord record,
    TenantPendingMutationState state, {
    String? reasonCode,
  }) => _change(
    record,
    (current, now) => current.copyWith(
      state: state,
      updatedAt: now,
      attemptCount: current.attemptCount,
      reasonCode: reasonCode,
    ),
  );

  Future<TenantPendingMutationRecord> _change(
    TenantPendingMutationRecord record,
    TenantPendingMutationRecord Function(
      TenantPendingMutationRecord current,
      DateTime now,
    )
    update,
  ) => _serialized(record.storageKey, () async {
    final raw = _box.get(record.storageKey);
    if (raw == null) {
      throw const TenantPendingMutationException('operation_not_found');
    }
    final current = _parseRecord(record.storageKey, raw);
    final changed = update(current, _clock().toUtc());
    await _box.put(record.storageKey, changed.toStorage());
    _changes.add(null);
    return changed;
  });

  Future<T> _serialized<T>(String key, Future<T> Function() action) async {
    final lock = '${_box.name}:$key';
    final previous = _tails[lock] ?? Future<void>.value();
    final release = Completer<void>();
    _tails[lock] = release.future;
    try {
      await previous;
      return await action();
    } finally {
      release.complete();
      if (identical(_tails[lock], release.future)) _tails.remove(lock);
    }
  }
}

enum TenantMutationSubmissionOutcome { committed, uncertain, rejected }

final class TenantMutationSubmissionResult {
  const TenantMutationSubmissionResult(this.outcome, [this.reasonCode]);

  final TenantMutationSubmissionOutcome outcome;
  final String? reasonCode;
}

abstract interface class TenantMutationSubmissionGateway {
  Future<TenantMutationSubmissionResult> submit(
    TenantPendingMutationRecord record,
  );
}

abstract interface class TenantMutationConfirmationGateway {
  Future<Map<String, Object?>?> read(String targetPath);
}

final class TenantPendingMutationWorker {
  TenantPendingMutationWorker({
    required TenantPendingMutationStore store,
    required TenantMutationSubmissionGateway submission,
    required TenantMutationConfirmationGateway confirmation,
    required String workerId,
  }) : _store = store,
       _submission = submission,
       _confirmation = confirmation,
       _workerId = _keySegment(workerId, 'workerId');

  final TenantPendingMutationStore _store;
  final TenantMutationSubmissionGateway _submission;
  final TenantMutationConfirmationGateway _confirmation;
  final String _workerId;
  Future<void>? _running;

  Future<void> run(TenantSession session) =>
      _running ??= _run(session).whenComplete(() => _running = null);

  Future<void> _run(TenantSession session) async {
    final records = await _store.recordsForSession(
      uid: session.uid,
      tenantId: session.tenantId,
    );
    final byTarget = <String, List<TenantPendingMutationRecord>>{};
    for (var record in records) {
      byTarget.putIfAbsent(record.targetPath, () => []).add(record);
    }
    // Path order is strict (create before void); different documents do not
    // hold one another behind an unreachable request.
    //
    // **With one exception, and it is the reason this set exists.** Groups
    // drain concurrently, so a record naming a document this same device queued
    // the create of a moment ago can reach the server first - and the server
    // refuses a category, a product or a supplier the business does not hold.
    // The record waits for what it depends on rather than racing it.
    final queuedCreates = _queuedCreatePaths(records);
    await Future.wait<void>(
      byTarget.values.map((group) => _runTarget(group, queuedCreates)),
    );
    await _store.purgeConfirmed();
  }

  /// The documents this device has queued the creation of and not yet seen
  /// settle.
  ///
  /// **Unresolved, so a rejected create stops holding anything.** A category
  /// refused for its name is never coming, and a record waiting on one would
  /// wait for ever; letting it through means the server refuses it too, in the
  /// same words and where somebody can see them.
  static Set<String> _queuedCreatePaths(
    List<TenantPendingMutationRecord> records,
  ) => <String>{
    for (final record in records)
      if ((record.kind == TenantPendingMutationKind.categoryCreate ||
              record.kind == TenantPendingMutationKind.productCreate ||
              record.kind == TenantPendingMutationKind.supplierCreate) &&
          record.isUnresolved)
        record.targetPath,
  };

  /// Whether this record names a document whose own create is still in flight.
  ///
  /// The deferral `TenantProductImageUploadWorker` performs for a photograph
  /// whose product is still queued, generalised: a product waits for its
  /// category, a delivery page for its supplier and every product it restocks,
  /// and a production batch for the product it makes.
  static bool _awaitsQueuedCreate(
    TenantPendingMutationRecord record,
    Set<String> queuedCreates,
  ) => tenantMutationDependencies(record).any(queuedCreates.contains);

  Future<void> _runTarget(
    List<TenantPendingMutationRecord> records,
    Set<String> queuedCreates,
  ) async {
    for (var record in records) {
      if (record.state == TenantPendingMutationState.rejected ||
          record.state == TenantPendingMutationState.needsAttention) {
        break;
      }
      if (record.state == TenantPendingMutationState.confirmed) continue;
      // **Left exactly as it is, for the next pass.** Not a failure and not an
      // attempt: nothing is sent, no attempt is counted, and no backoff is
      // started, because there is nothing wrong with this record - the one it
      // depends on has simply not landed yet. The whole group returns, since a
      // correction to a product that does not exist yet cannot go either.
      if (_awaitsQueuedCreate(record, queuedCreates)) return;
      try {
        if (_store.hasActiveLease(record)) continue;
        if (record.state == TenantPendingMutationState.awaitingConfirmation ||
            record.state == TenantPendingMutationState.submitting) {
          final canonical = await _confirmation.read(record.targetPath);
          if (_containsPayload(canonical, record.payload)) {
            await _store.markConfirmed(record);
            continue;
          }
          if (_isConfiguration(record) && canonical != null) {
            final expected = record.replacedValueFingerprint;
            final actual = tenantConfigurationMutationFingerprint(canonical);
            if (expected != null && actual != expected) {
              await _store.markNeedsAttention(
                record,
                'configuration_changed_before_confirmation',
              );
              break;
            }
          }
          record = await _store.retryLater(record);
        }
        if (!_store.isDue(record)) continue;
        // An earlier attempt had an uncertain outcome. Confirm the exact
        // target again at retry time; the first confirmation may have raced a
        // write that reached Firestore just after its deadline.
        if (record.attemptCount > 0) {
          final canonical = await _confirmation.read(record.targetPath);
          if (_containsPayload(canonical, record.payload)) {
            await _store.markConfirmed(record);
            continue;
          }
        }
        final expected = record.replacedValueFingerprint;
        if (_isConfiguration(record) && expected != null) {
          final canonical = await _confirmation.read(record.targetPath);
          final actual = tenantConfigurationMutationFingerprint(
            canonical ?? const {},
          );
          if (actual != expected) {
            await _store.markNeedsAttention(
              record,
              'configuration_changed_before_sync',
            );
            break;
          }
        }
        record = await _store.acquire(record, leaseOwner: _workerId);
        final result = await _submission.submit(record);
        switch (result.outcome) {
          case TenantMutationSubmissionOutcome.committed:
            await _store.markConfirmed(record);
          case TenantMutationSubmissionOutcome.uncertain:
            await _store.markAwaiting(record);
          case TenantMutationSubmissionOutcome.rejected:
            await _store.markRejected(record, result.reasonCode ?? 'rejected');
            return;
        }
      } catch (_) {
        try {
          await _store.retryLater(record);
        } catch (_) {}
        return;
      }
    }
  }
}

final class TenantPendingMutationSwitchStateSource
    implements TenantSwitchStateSource {
  const TenantPendingMutationSwitchStateSource(this._store);

  final TenantPendingMutationStore _store;

  @override
  TenantSwitchStateArea get area => TenantSwitchStateArea.pendingWrites;

  @override
  Future<TenantSwitchInspection?> inspect(TenantSession session) async {
    final records = await _store.recordsForSession(
      uid: session.uid,
      tenantId: session.tenantId,
    );
    return records.any((record) => record.isUnresolved)
        ? TenantSwitchInspection.blocked(
            area: area,
            session: session,
            blocker: TenantSwitchBlocker.pendingWrites,
          )
        : TenantSwitchInspection.clean(area: area, session: session);
  }
}

typedef TenantPendingMutationUidProvider = String? Function();

/// Applies unresolved local evidence over a cache or live tenant reader.
/// Rejected, conflicting and confirmed records are deliberately absent.
final class TenantPendingMutationOverlayReader
    implements
        TenantCacheReadable,
        TenantSalesHistoryQueryReader,
        TenantStaffDirectoryQueryReader,
        TenantProductSearchReader,
        TenantCollectionGroupReader,
        TenantReportRangeReader {
  const TenantPendingMutationOverlayReader({
    required TenantDataReader base,
    required TenantPendingMutationStore store,
    required TenantPendingMutationUidProvider currentUid,
  }) : _base = base,
       _store = store,
       _currentUid = currentUid;

  final TenantDataReader _base;
  final TenantPendingMutationStore _store;
  final TenantPendingMutationUidProvider _currentUid;

  @override
  TenantDataReader get cacheOnly {
    final base = _base;
    final cached = base is TenantCacheReadable ? base.cacheOnly : base;
    return TenantPendingMutationOverlayReader(
      base: cached,
      store: _store,
      currentUid: _currentUid,
    );
  }

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    final canonical = await _base.getDocument(path);
    final identity = _tenantFromPath(path);
    final uid = _currentUid();
    if (identity == null || uid == null) return canonical;
    final records = await _active(uid, identity);
    Map<String, Object?>? data = canonical?.data;
    var touched = false;
    for (final record in records) {
      if (!tenantMutationTouchedPaths(record).contains(path)) continue;
      data = _projected(record, path, data);
      touched = true;
    }
    if (!touched) return canonical;
    return data == null ? null : TenantDocumentSnapshot(path: path, data: data);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    final canonical = await _base.getCollectionPage(query);
    final identity = _tenantFromPath(query.collectionPath);
    final uid = _currentUid();
    if (identity == null || uid == null) return canonical;
    final records = await _active(uid, identity);
    final byPath = <String, Map<String, Object?>?>{
      for (final item in canonical) item.path: <String, Object?>{...item.data},
    };
    for (final record in records) {
      for (final path in _pathsUnder(record, query.collectionPath)) {
        // A retire of a product this page never held is not an entry to add
        // and then hide; `containsKey` keeps a tombstone from inventing one.
        final present = byPath.containsKey(path);
        final projected = _projected(record, path, byPath[path]);
        if (projected == null && !present) continue;
        byPath[path] = projected;
      }
    }
    final items = <TenantQueryDocumentSnapshot>[];
    for (final entry in byPath.entries) {
      final data = entry.value;
      if (data == null) continue;
      final id = entry.key.split('/').last;
      final cursor = query.startAfterDocumentId;
      if (cursor != null) {
        // The same pair the transport resumes on: the ordering field first when
        // there is one, then the document ID. Comparing IDs alone on a
        // time-ordered page would drop records the server would have returned.
        final comparison = _comparePageKeys(
          _orderValue(data, query.order),
          id,
          query.startAfterOrderValue,
          cursor,
        );
        if (query.descending ? comparison >= 0 : comparison <= 0) continue;
      }
      if (!query.equalityFilters.entries.every(
        (filter) => data[filter.key] == filter.value,
      )) {
        continue;
      }
      items.add(TenantQueryDocumentSnapshot(path: entry.key, data: data));
    }
    // The same ordering the transport applies, so a queued record does not sit
    // where the server would not have put it.
    items.sort((left, right) {
      final order = _comparePageKeys(
        _orderValue(left.data, query.order),
        left.path.split('/').last,
        _orderValue(right.data, query.order),
        right.path.split('/').last,
      );
      return query.descending ? -order : order;
    });
    return items.take(query.limit).toList(growable: false);
  }

  /// One document's ordering value, or null for a page ordered by document ID.
  ///
  /// Lenient where [TenantReadRepository] is strict, and deliberately: this is
  /// sorting a *local* projection, where a record queued a moment ago may not
  /// carry a server timestamp yet. A document with nothing to sort on falls
  /// back to its ID, which is the order it would have had anyway. The proof
  /// above still refuses a page the transport ordered wrongly.
  static DateTime? _orderValue(
    Map<String, Object?> data,
    TenantCollectionOrder order,
  ) {
    final field = order.field;
    if (field == null) return null;
    return tenantStoredInstant(data[field]);
  }

  /// Orders two page keys the way Firestore orders a field then `__name__`.
  static int _comparePageKeys(
    DateTime? leftValue,
    String leftDocument,
    DateTime? rightValue,
    String rightDocument,
  ) {
    if (leftValue != null && rightValue != null) {
      final byValue = leftValue.compareTo(rightValue);
      if (byValue != 0) return byValue;
    }
    return leftDocument.compareTo(rightDocument);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> queryTenantSalesHistory(
    TenantSalesHistoryQuery query,
  ) {
    final Object base = _base;
    if (base is! TenantSalesHistoryQueryReader) {
      throw StateError('Sales history query is unavailable.');
    }
    return base.queryTenantSalesHistory(query);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> queryTenantStaff(
    TenantStaffDirectoryQuery query,
  ) {
    final Object base = _base;
    if (base is! TenantStaffDirectoryQueryReader) {
      throw StateError('Staff directory query is unavailable.');
    }
    return base.queryTenantStaff(query);
  }

  /// The three period reads a report can need, forwarded unchanged.
  ///
  /// **Forwarded rather than overlaid, deliberately.** The overlay above exists
  /// so a record this device has just written is visible on the screen that
  /// wrote it; a report is a statement about what the *server* holds for a
  /// named period, and folding an unsent local write into one would produce a
  /// document that disagrees with the business's own records the moment it is
  /// mailed to anybody.
  ///
  /// **They have to be here at all because this class is what the routes
  /// hold.** Every route is handed this overlay, not the Firestore reader
  /// under it, so a reader capability this class does not declare is a
  /// capability no screen can reach - which is exactly how five reports came
  /// to refuse on a device while every test passed. See the doc on
  /// [TenantReportRangeReader].
  @override
  Future<List<TenantQueryDocumentSnapshot>> queryTenantBusinessDateRange(
    TenantBusinessDateRangeQuery query,
  ) {
    final Object base = _base;
    if (base is! TenantReportRangeReader) {
      throw StateError('Period reads are unavailable.');
    }
    return base.queryTenantBusinessDateRange(query);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> queryTenantDocumentIdRange(
    TenantDocumentIdRangeQuery query,
  ) {
    final Object base = _base;
    if (base is! TenantReportRangeReader) {
      throw StateError('Period reads are unavailable.');
    }
    return base.queryTenantDocumentIdRange(query);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> queryTenantInstantRange(
    TenantInstantRangeQuery query,
  ) {
    final Object base = _base;
    if (base is! TenantReportRangeReader) {
      throw StateError('Period reads are unavailable.');
    }
    return base.queryTenantInstantRange(query);
  }

  /// **The catalog is read through here, not through [getCollectionPage].**
  /// `TenantCatalogRepository` prefers a search reader whenever one exists and
  /// this class is one, so a product added a second ago would be invisible on
  /// the very screen that added it if this method only forwarded.
  @override
  Future<List<TenantQueryDocumentSnapshot>> searchTenantProducts(
    TenantProductSearchQuery query,
  ) async {
    final Object base = _base;
    if (base is! TenantProductSearchReader) {
      throw StateError('Product search is unavailable.');
    }
    final canonical = await base.searchTenantProducts(query);
    final identity = _tenantFromPath(query.collectionPath);
    final uid = _currentUid();
    if (identity == null || uid == null) return canonical;
    final records = <TenantPendingMutationRecord>[
      for (final record in await _active(uid, identity))
        if (_pathsUnder(record, query.collectionPath).isNotEmpty) record,
    ];
    if (records.isEmpty) return canonical;

    final byPath = <String, Map<String, Object?>?>{
      for (final item in canonical) item.path: <String, Object?>{...item.data},
    };
    for (final record in records) {
      for (final path in _pathsUnder(record, query.collectionPath)) {
        final present = byPath.containsKey(path);
        final projected = _projected(record, path, byPath[path]);
        if (projected == null && !present) continue;
        byPath[path] = projected;
      }
    }

    final items = <TenantQueryDocumentSnapshot>[];
    for (final entry in byPath.entries) {
      final data = entry.value;
      if (data == null) continue;
      if (query.searchPrefix case final prefix?) {
        final prefixes = data['searchPrefixes'];
        if (prefixes is! List || !prefixes.contains(prefix)) continue;
      }
      if (query.categoryId case final categoryId?) {
        if (data['categoryId'] != categoryId) continue;
      }
      final quantity = data['quantity'];
      switch (query.stock) {
        case TenantProductStockFilter.all:
          break;
        case TenantProductStockFilter.aboveZero:
          if (quantity is! num || quantity <= 0) continue;
        case TenantProductStockFilter.atOrBelowZero:
          if (quantity is! num || quantity > 0) continue;
      }
      items.add(TenantQueryDocumentSnapshot(path: entry.key, data: data));
    }

    // The same ordering the transport applies, so a locally added product does
    // not jump to the top of a page it does not belong at the top of: by stock
    // first when the page is filtered by it, then by search name, then by ID.
    final ordered = query.stock == TenantProductStockFilter.all;
    items.sort((left, right) {
      if (!ordered) {
        final quantity = _compareValues(
          left.data['quantity'],
          right.data['quantity'],
        );
        if (quantity != 0) return quantity;
      }
      final name = _compareValues(
        left.data['searchName'],
        right.data['searchName'],
      );
      if (name != 0) return name;
      return left.path.split('/').last.compareTo(right.path.split('/').last);
    });

    if (query.startAfter case final cursor?) {
      final at = items.indexWhere(
        (item) => item.path.split('/').last == cursor.documentId,
      );
      if (at >= 0) items.removeRange(0, at + 1);
    }
    return items.take(query.limit).toList(growable: false);
  }

  /// What one queued record does to the document it names.
  ///
  /// A null return is a tombstone — the document is gone as far as this device
  /// is concerned — and a null argument means it was never there.
  ///
  /// **Two kinds do not overlay their own payload.** A callable's payload is
  /// addressed to the server's vocabulary rather than to the document's, so
  /// `productCorrect` is translated field by field and `stockAdjust` is applied
  /// as an increment against whatever the document currently holds. Everything
  /// else writes the document directly and can be merged as it stands.
  Map<String, Object?>? _projected(
    TenantPendingMutationRecord record,
    String path,
    Map<String, Object?>? canonical,
  ) {
    switch (record.kind) {
      // **No longer a tombstone.** Retiring used to delete the document, so the
      // overlay hid the row; it is a flag now, and the product stays in the
      // catalog marked as retired. Drawing it that way offline is what makes the
      // queued state and the settled state look the same.
      //
      // The quantity is cleared alongside it because the server clears it in the
      // same transaction. Showing the old figure against a retired row would
      // state stock that is already accounted for as gone.
      case TenantPendingMutationKind.productRetire:
        if (canonical == null) return null;
        final retiring = record.payload['retired'] != false;
        return <String, Object?>{
          ...canonical,
          'retired': retiring,
          if (retiring) 'quantity': 0,
        };
      case TenantPendingMutationKind.productCorrect:
        if (canonical == null) return null;
        return _correctedProduct(canonical, record.payload);
      case TenantPendingMutationKind.stockAdjust:
        if (canonical == null) return null;
        final held = canonical['quantity'];
        final delta = record.payload['quantityDelta'];
        if (held is! num || delta is! num) return canonical;
        return <String, Object?>{...canonical, 'quantity': held + delta};
      case TenantPendingMutationKind.expenseCreate:
        return <String, Object?>{
          if (canonical != null) ...canonical,
          ...record.payload,
          'createdAt': canonical?['createdAt'] ?? record.createdAt,
        };
      // The time it was taken is the one the gateway will send, so the row a
      // queued return draws is the row the server will hold.
      case TenantPendingMutationKind.pendingReturnCreate:
        return <String, Object?>{
          if (canonical != null) ...canonical,
          ...record.payload,
          'occurredAt': canonical?['occurredAt'] ?? record.createdAt,
          'createdAt': canonical?['createdAt'] ?? record.createdAt,
        };
      case TenantPendingMutationKind.expenseVoid:
        return <String, Object?>{
          if (canonical != null) ...canonical,
          ...record.payload,
          'voidedAt': canonical?['voidedAt'] ?? record.createdAt,
        };
      // **A queued count, drawn as the server will hold it.** Every page of
      // one take shares this path and merges the same header, so the pages
      // project onto one another harmlessly and the take appears as soon as the
      // first of them is queued.
      //
      // The lines are not projected. They live under this document and the only
      // surface that reads them is management's review, which is a surface for
      // counts that have arrived.
      case TenantPendingMutationKind.stockTakePage:
        return <String, Object?>{
          if (canonical != null) ...canonical,
          'tenantId': record.tenantId,
          // The counter is whoever queued it, never anything in the payload.
          'counterUid': record.uid,
          'businessDate': record.payload['businessDate'],
          'scope': record.payload['scope'],
          'productsInScope': record.payload['productsInScope'],
          // A take already on the server keeps the standing it reached there;
          // one that exists only here is still on its way.
          'status': canonical?['status'] ?? 'submitting',
          'createdAt': canonical?['createdAt'] ?? record.createdAt,
        };
      case TenantPendingMutationKind.productCreate:
      case TenantPendingMutationKind.categoryCreate:
      case TenantPendingMutationKind.supplierCreate:
        return <String, Object?>{
          if (canonical != null) ...canonical,
          ...record.payload,
          'createdAt': canonical?['createdAt'] ?? record.createdAt,
        };
      case TenantPendingMutationKind.categoryRename:
      case TenantPendingMutationKind.supplierUpdate:
      case TenantPendingMutationKind.brandingMerge:
      case TenantPendingMutationKind.printerConfigurationMerge:
        return <String, Object?>{
          if (canonical != null) ...canonical,
          ...record.payload,
        };
      case TenantPendingMutationKind.supplierDeliveryPage:
        if (path == record.targetPath) {
          return _deliveryHeader(record, canonical);
        }
        return path.split('/')[2] == TenantCollection.suppliers.segment
            ? _deliveringSupplier(record, canonical)
            : _deliveredProduct(record, path, canonical);
      case TenantPendingMutationKind.productionComplete:
        return path == record.targetPath
            ? _producedBatch(record, canonical)
            : _producedProduct(record, canonical);
    }
  }

  /// The touched paths of [record] that sit directly under [collectionPath].
  static List<String> _pathsUnder(
    TenantPendingMutationRecord record,
    String collectionPath,
  ) {
    final depth = collectionPath.split('/').length + 1;
    return <String>[
      for (final path in tenantMutationTouchedPaths(record))
        if (path.startsWith('$collectionPath/') &&
            path.split('/').length == depth)
          path,
    ];
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionGroupPage(
    TenantCollectionGroupQuery query,
  ) {
    final Object base = _base;
    if (base is! TenantCollectionGroupReader) {
      throw StateError('Collection group query is unavailable.');
    }
    return base.getCollectionGroupPage(query);
  }

  Future<List<TenantPendingMutationRecord>> _active(
    String uid,
    String tenantId,
  ) async => <TenantPendingMutationRecord>[
    for (final record in await _store.recordsForSession(
      uid: uid,
      tenantId: tenantId,
    ))
      if (record.state == TenantPendingMutationState.queued ||
          record.state == TenantPendingMutationState.submitting ||
          record.state == TenantPendingMutationState.awaitingConfirmation)
        record,
  ];
}

/// One correction, translated from what `updateProduct` reads into what the
/// product document holds.
///
/// **The two vocabularies differ in three places**, and each is a decision:
/// the callable takes `sku` where the document stores `SKU`; `cost` and `image`
/// carry an explicit null to mean *remove this*, which here has to be an absent
/// key rather than a null value, because a stored null is a value the strict
/// read model would have to have an opinion about; and `tenantId`, `productId`
/// and `requestId` address the call rather than the product, so they are
/// dropped.
///
/// **The search index is deliberately not recomputed.** A corrected name shows
/// immediately everywhere the product is drawn, but stays findable under its
/// old spelling until the server answers. Rebuilding `searchPrefixes` here
/// would mean keeping a second copy of the server's tokenizer in step with it
/// forever, and being wrong about that is worse than a name that is briefly
/// searchable both ways.
Map<String, Object?> _correctedProduct(
  Map<String, Object?> canonical,
  Map<String, Object?> payload,
) {
  final result = <String, Object?>{...canonical};
  for (final entry in payload.entries) {
    switch (entry.key) {
      case 'tenantId':
      case 'productId':
      case 'requestId':
        continue;
      case 'sku':
        if (entry.value != null) result['SKU'] = entry.value;
      case 'cost':
      case 'image':
        if (entry.value == null) {
          result.remove(entry.key);
        } else {
          result[entry.key] = entry.value;
        }
      default:
        if (entry.value != null) result[entry.key] = entry.value;
    }
  }
  return result;
}

/// The product lines one queued delivery page carries, as its payload states
/// them. A malformed line is skipped rather than thrown on: this draws a local
/// projection, and the server is what refuses a malformed page.
List<Map<String, Object?>> _deliveryLines(TenantPendingMutationRecord record) {
  final lines = record.payload['lines'];
  if (lines is! List) return const <Map<String, Object?>>[];
  return <Map<String, Object?>>[
    for (final line in lines)
      if (line is Map && line['productId'] is String)
        <String, Object?>{
          for (final entry in line.entries) entry.key as String: entry.value,
        },
  ];
}

int? _minorOf(Object? major) => major is num ? (major * 100).round() : null;

/// A queued delivery drawn as the server will hold it, page by page.
///
/// Lines a page already landed are replaced rather than repeated, so a page
/// that reached the server but has not been confirmed here yet is not counted
/// twice on the supplier's history.
Map<String, Object?> _deliveryHeader(
  TenantPendingMutationRecord record,
  Map<String, Object?>? canonical,
) {
  final page = record.payload['page'];
  final stored = canonical?['lines'];
  final lines = <Map<String, Object?>>[
    if (stored is List)
      for (final line in stored)
        if (line is Map && line['page'] != page)
          <String, Object?>{
            for (final entry in line.entries) entry.key as String: entry.value,
          },
    for (final line in _deliveryLines(record))
      <String, Object?>{
        'productId': line['productId'],
        'productName': line['productName'],
        'quantity': line['quantity'],
        'unitCostMinor': _minorOf(line['unitCost']),
        'page': page,
      },
  ];
  var units = 0;
  var valueMinor = 0;
  var costless = 0;
  for (final line in lines) {
    final quantity = line['quantity'];
    final unitCostMinor = line['unitCostMinor'];
    if (quantity is int) units += quantity;
    if (quantity is int && unitCostMinor is int) {
      valueMinor += quantity * unitCostMinor;
    } else {
      costless += 1;
    }
  }
  return <String, Object?>{
    if (canonical != null) ...canonical,
    'tenantId': record.tenantId,
    'deliveryId': record.payload['deliveryId'],
    'supplierId': record.payload['supplierId'],
    'reference': record.payload['reference'],
    'actorUid': canonical?['actorUid'] ?? record.uid,
    'lines': lines,
    'lineCount': lines.length,
    'unitCount': units,
    'valueMinor': valueMinor,
    'costlessLineCount': costless,
    'complete': canonical?['complete'] ?? false,
    // The first page's time dates the delivery, on the server and here.
    'occurredAt': canonical?['occurredAt'] ?? record.createdAt,
    'createdAt': canonical?['createdAt'] ?? record.createdAt,
  };
}

/// One product a queued delivery page restocks, drawn as it will stand.
///
/// **Never invents a product**: a product this device holds no copy of stays
/// absent, exactly as a queued adjustment leaves it.
Map<String, Object?>? _deliveredProduct(
  TenantPendingMutationRecord record,
  String path,
  Map<String, Object?>? canonical,
) {
  if (canonical == null) return null;
  final productId = path.split('/').last;
  final result = <String, Object?>{...canonical};
  for (final line in _deliveryLines(record)) {
    if (line['productId'] != productId) continue;
    final held = result['quantity'];
    final quantity = line['quantity'];
    if (held is num && quantity is num) result['quantity'] = held + quantity;
    final unitCost = line['unitCost'];
    if (unitCost is num) result['cost'] = unitCost;
  }
  return result;
}

/// The supplier of a queued delivery, with the delivery as its latest.
///
/// A supplier this device has never read is left alone rather than drawn from
/// one field, the way [_deliveredProduct] leaves a product alone.
Map<String, Object?>? _deliveringSupplier(
  TenantPendingMutationRecord record,
  Map<String, Object?>? canonical,
) {
  if (canonical == null) return null;
  final held = tenantStoredInstant(canonical['lastDeliveryAt']);
  return <String, Object?>{
    ...canonical,
    if (held == null || held.isBefore(record.createdAt))
      'lastDeliveryAt': record.createdAt,
  };
}

/// A queued production batch drawn as the server will hold it.
Map<String, Object?> _producedBatch(
  TenantPendingMutationRecord record,
  Map<String, Object?>? canonical,
) {
  final expenses = record.payload['expenses'];
  return <String, Object?>{
    if (canonical != null) ...canonical,
    'tenantId': record.tenantId,
    'batchId': record.payload['batchId'],
    'batchNumber': record.payload['batchNumber'],
    'productId': record.payload['productId'],
    'productName': record.payload['productName'],
    'quantity': record.payload['quantity'],
    'expenses': <Map<String, Object?>>[
      if (expenses is List)
        for (final row in expenses)
          if (row is Map)
            <String, Object?>{
              'description': row['description'],
              'amountMinor': _minorOf(row['amount']),
            },
    ],
    'totalCostMinor': record.payload['totalCostMinor'],
    'unitCostMinor': record.payload['unitCostMinor'],
    'actorUid': canonical?['actorUid'] ?? record.uid,
    'occurredAt': canonical?['occurredAt'] ?? record.createdAt,
    'createdAt': canonical?['createdAt'] ?? record.createdAt,
  };
}

/// The product a queued batch makes, drawn as it will stand: more stock, and
/// the cost one unit took to make.
Map<String, Object?>? _producedProduct(
  TenantPendingMutationRecord record,
  Map<String, Object?>? canonical,
) {
  if (canonical == null) return null;
  final result = <String, Object?>{...canonical};
  final held = result['quantity'];
  final quantity = record.payload['quantity'];
  if (held is num && quantity is num) result['quantity'] = held + quantity;
  final unitCostMinor = record.payload['unitCostMinor'];
  if (unitCostMinor is int) result['cost'] = unitCostMinor / 100;
  return result;
}

/// Every document [record] changes when it lands, its own path first.
///
/// **One for every kind but two**, and those two are why this exists. A
/// delivery page restocks each product it names and a production batch
/// restocks the product it makes, while both are addressed to their own record
/// so a refusal strands only that record. The overlay draws a queued record
/// over every path here, so the stock a delivery brought in shows on the
/// catalog the moment it is queued.
///
/// A delivery page also touches its supplier, whose last delivery the server
/// stamps in the same transaction. Without it the directory went on saying
/// *None yet* for a delivery the device had just received, until the server
/// had it and the screen was opened again.
List<String> tenantMutationTouchedPaths(TenantPendingMutationRecord record) {
  final paths = TenantPaths(record.tenantId);
  return switch (record.kind) {
    TenantPendingMutationKind.supplierDeliveryPage => <String>[
      record.targetPath,
      ..._deliveredProductPaths(record),
      if (_documentIdOrNull(record.payload['supplierId']) case final id?)
        paths.supplier(id),
    ],
    TenantPendingMutationKind.productionComplete => <String>[
      record.targetPath,
      if (_documentIdOrNull(record.payload['productId']) case final productId?)
        paths.product(productId),
    ],
    _ => <String>[record.targetPath],
  };
}

/// The documents [record] names that must exist on the server before it is
/// sent, other than its own.
///
/// A product names its category; a delivery page its supplier and every
/// product it restocks; a production batch the product it makes. The worker
/// holds a record back while one of these is still an unsent create on this
/// device, rather than letting the server refuse it for a race.
List<String> tenantMutationDependencies(TenantPendingMutationRecord record) {
  final paths = TenantPaths(record.tenantId);
  return switch (record.kind) {
    TenantPendingMutationKind.productCreate => <String>[
      if (_documentIdOrNull(record.payload['categoryId']) case final id?)
        paths.category(id),
    ],
    TenantPendingMutationKind.supplierDeliveryPage => <String>[
      if (_documentIdOrNull(record.payload['supplierId']) case final id?)
        paths.supplier(id),
      ..._deliveredProductPaths(record),
    ],
    TenantPendingMutationKind.productionComplete => tenantMutationTouchedPaths(
      record,
    ).skip(1).toList(),
    _ => const <String>[],
  };
}

/// The products a delivery page restocks, one path each.
List<String> _deliveredProductPaths(TenantPendingMutationRecord record) {
  final paths = TenantPaths(record.tenantId);
  return <String>[
    for (final line in _deliveryLines(record))
      if (_documentIdOrNull(line['productId']) case final productId?)
        paths.product(productId),
  ];
}

String? _documentIdOrNull(Object? value) {
  if (value is! String) return null;
  try {
    return validateTenantDocumentId(value);
  } on ArgumentError {
    return null;
  }
}

/// Orders two stored values the way the transport's `orderBy` would.
///
/// Only the two types the product ordering actually uses are compared; anything
/// else sorts equal rather than throwing, because a document this device cannot
/// order is still a document it must not drop from the page.
int _compareValues(Object? left, Object? right) {
  if (left == null && right == null) return 0;
  if (left == null) return 1;
  if (right == null) return -1;
  if (left is num && right is num) return left.compareTo(right);
  if (left is String && right is String) return left.compareTo(right);
  return 0;
}

bool _isConfiguration(TenantPendingMutationRecord record) =>
    record.kind == TenantPendingMutationKind.brandingMerge ||
    record.kind == TenantPendingMutationKind.printerConfigurationMerge;

bool _containsPayload(
  Map<String, Object?>? canonical,
  Map<String, Object?> expected,
) {
  if (canonical == null) return false;
  for (final entry in expected.entries) {
    if (jsonEncode(_canonicalJson(canonical[entry.key])) !=
        jsonEncode(_canonicalJson(entry.value))) {
      return false;
    }
  }
  return true;
}

void _requireTarget(
  String tenantId,
  String path,
  TenantPendingMutationKind kind,
) {
  final prefix = 'tenants/${validateTenantId(tenantId)}/';
  if (!path.startsWith(prefix) || path.split('/').length != 4) {
    throw const TenantPendingMutationException('target_escaped_tenant');
  }
  final collection = path.split('/')[2];
  final expected = switch (kind) {
    TenantPendingMutationKind.expenseCreate ||
    TenantPendingMutationKind.expenseVoid => 'expenses',
    TenantPendingMutationKind.pendingReturnCreate => 'returns',
    TenantPendingMutationKind.brandingMerge ||
    TenantPendingMutationKind.printerConfigurationMerge => 'configuration',
    // A correction and an adjustment both name the product they are about,
    // even though neither reaches it as a document write. The path is what the
    // overlay draws against and what confirmation reads back, so it is held to
    // the same tenant scoping as everything else here.
    TenantPendingMutationKind.productCreate ||
    TenantPendingMutationKind.productRetire ||
    TenantPendingMutationKind.productCorrect ||
    TenantPendingMutationKind.stockAdjust => 'products',
    TenantPendingMutationKind.categoryCreate ||
    TenantPendingMutationKind.categoryRename => 'categories',
    // The take, not the products counted in it. See the kind's own note: one
    // path per count is what keeps a count's pages ordered without serialising
    // one person's count behind another's.
    TenantPendingMutationKind.stockTakePage => 'stock_takes',
    TenantPendingMutationKind.supplierCreate ||
    TenantPendingMutationKind.supplierUpdate => 'suppliers',
    // The delivery and the batch, not the products they restock - see the
    // kinds' own notes and [tenantMutationTouchedPaths].
    TenantPendingMutationKind.supplierDeliveryPage => 'supplier_deliveries',
    TenantPendingMutationKind.productionComplete => 'production_batches',
  };
  if (collection != expected) {
    throw const TenantPendingMutationException('invalid_target');
  }
}

TenantPendingMutationRecord _parseRecord(String key, Object? raw) {
  try {
    final map = Map<Object?, Object?>.from(raw! as Map);
    if (map['schemaVersion'] != TenantPendingMutationRecord.schemaVersion) {
      throw const FormatException();
    }
    final uid = map['uid']! as String;
    final tenantId = map['tenantId']! as String;
    final operationId = map['operationId']! as String;
    if (tenantPendingMutationStorageKey(
          uid: uid,
          tenantId: tenantId,
          operationId: operationId,
        ) !=
        key) {
      throw const FormatException();
    }
    final payload = <String, Object?>{
      for (final entry in (map['payload']! as Map).entries)
        entry.key! as String: entry.value,
    };
    final hash = map['payloadHash']! as String;
    if (tenantMutationFingerprint(payload) != hash) {
      throw const FormatException();
    }
    return TenantPendingMutationRecord._(
      uid: uid,
      tenantId: validateTenantId(tenantId),
      operationId: operationId,
      kind: TenantPendingMutationKind.values.byName(map['kind']! as String),
      targetPath: map['targetPath']! as String,
      payload: payload,
      payloadHash: hash,
      replacedValueFingerprint: map['replacedValueFingerprint'] as String?,
      state: TenantPendingMutationState.values.byName(map['state']! as String),
      attemptCount: map['attemptCount']! as int,
      retryAt: _instant(map['retryAtMs']),
      leaseOwner: map['leaseOwner'] as String?,
      leaseExpiresAt: _instant(map['leaseExpiresAtMs']),
      createdAt: _instant(map['createdAtMs'])!,
      updatedAt: _instant(map['updatedAtMs'])!,
      reasonCode: map['reasonCode'] as String?,
    );
  } catch (_) {
    throw const TenantPendingMutationException('unreadable_record');
  }
}

DateTime? _instant(Object? value) => value == null
    ? null
    : DateTime.fromMillisecondsSinceEpoch(value as int, isUtc: true);

String _keySegment(String value, String field) {
  if (value.isEmpty || value != value.trim() || value.contains(':')) {
    throw ArgumentError.value(value, field);
  }
  return value;
}

Map<String, Object?> _freezeMap(Map<String, Object?> source) =>
    Map<String, Object?>.unmodifiable(<String, Object?>{
      for (final entry in source.entries) entry.key: _freeze(entry.value),
    });

Object? _freeze(Object? value) => switch (value) {
  Map() => _freezeMap(<String, Object?>{
    for (final entry in value.entries) entry.key as String: entry.value,
  }),
  List() => List<Object?>.unmodifiable(value.map(_freeze)),
  String() || num() || bool() || null => value,
  _ => throw const TenantPendingMutationException('non_json_payload'),
};

Object? _mutableJson(Object? value) => switch (value) {
  Map() => <String, Object?>{
    for (final entry in value.entries)
      entry.key as String: _mutableJson(entry.value),
  },
  List() => <Object?>[for (final item in value) _mutableJson(item)],
  _ => value,
};

Object? _canonicalJson(Object? value) => switch (value) {
  Map() => <String, Object?>{
    for (final key in (value.keys.cast<String>().toList()..sort()))
      key: _canonicalJson(value[key]),
  },
  List() => <Object?>[for (final item in value) _canonicalJson(item)],
  _ => value,
};

bool _isJsonValue(Object? value) => switch (value) {
  null || String() || num() || bool() => true,
  List() => value.every(_isJsonValue),
  Map() =>
    value.keys.every((key) => key is String) &&
        value.values.every(_isJsonValue),
  _ => false,
};

DateTime _utcNow() => DateTime.now().toUtc();

String? _tenantFromPath(String path) {
  final parts = path.split('/');
  if (parts.length < 2 || parts[0] != 'tenants') return null;
  try {
    return validateTenantId(parts[1]);
  } on ArgumentError {
    return null;
  }
}
