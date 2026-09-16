/// H2 on a real Firestore SDK: can this device mistake its own unsent write for
/// the server's confirmation?
///
/// **The audit says it can and the code says it can; this says whether the SDK
/// does.** `TenantShiftController._settle` re-reads the canonical shift after a
/// write whose outcome was unknown, and concludes `serverConfirmedOpen` from
/// whatever comes back. The read goes through `FirebaseTenantDocumentReader`,
/// which asks for `Source.serverAndCache` and discards `snapshot.metadata`. If a
/// `set` that has not reached the server is visible to that read, the controller
/// has no way to tell a confirmed shift from one still sitting in the local
/// mutation queue - and a later rejection of that queued write then makes it
/// delete the record, stranding every sale stamped with the shift's id.
///
/// Everything above was proved by reading. The one link that cannot be read is
/// **what the SDK actually returns**, which is what this runs on a device to
/// find out.
///
/// `disableNetwork` is the faithful model of the timeout this describes, not a
/// stand-in for being offline: the app's own offline branch is taken earlier and
/// separately, by `TenantShiftWriter._write` checking connectivity *before* it
/// writes. Reaching `_settle` with an ambiguous result means the app believed it
/// was online and the write did not land - which is exactly a `set` left pending
/// in the queue while a read is asked to describe the world.
///
/// Runs against SIT - the backend `CLAUDE.md` names, reached by the absence of
/// any emulator switch. The two defines it does take are a sign-in, because the
/// rejection in step 4 has to be the one a real member meets:
///
/// ```
/// flutter test integration_test/shift_pending_write_test.dart \
///   --dart-define=H2_PROBE_EMAIL=... --dart-define=H2_PROBE_PASSWORD=...
/// ```
///
/// **It touches no real business.** Every write is to
/// `tenants/h2-probe-<timestamp>/`, a tenant that does not exist, and the rules
/// refuse it - which is the point of step 4 rather than an accident. Nothing is
/// left behind on the server, because nothing of this ever reaches it.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_application_1/firebase_options.dart';
import 'package:flutter_application_1/shift/tenant_shift.dart';
import 'package:flutter_application_1/tenancy/tenant_repository.dart';

/// Passed at the command line so no credential is written into this file.
const String _email = String.fromEnvironment('H2_PROBE_EMAIL');
const String _password = String.fromEnvironment('H2_PROBE_PASSWORD');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a pending shift create reads back as a confirmed open shift', (
    tester,
  ) async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final firestore = FirebaseFirestore.instance;
    firestore.settings = const Settings(persistenceEnabled: true);

    // **Signed in, because the rejection has to be a real one.** An
    // unauthenticated write is refused by `tenantIdentity()` before the rules
    // ever look at standing, which is not the refusal a deactivated cashier
    // meets. Authenticated and not a member of the tenant is: `staffStanding`
    // is false for a staff document that does not exist and for one whose
    // `status` is not `active`, by the same two clauses of the same function -
    // so the write below is rejected by the identical evaluation.
    if (_email.isEmpty || _password.isEmpty) {
      fail('Pass --dart-define=H2_PROBE_EMAIL and H2_PROBE_PASSWORD.');
    }
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email,
        password: _password,
      );
    }
    expect(FirebaseAuth.instance.currentUser, isNotNull);

    // A tenant that does not exist, so a write that somehow did escape would be
    // refused by the rules rather than landing on a real business.
    final tenantId = 'h2-probe-${DateTime.now().millisecondsSinceEpoch}';
    const shiftId = 'sh-h2-probe';
    final path = 'tenants/$tenantId/shifts/$shiftId';

    await firestore.disableNetwork();
    addTearDown(() async {
      // Left disabled would leak into any test after this one.
      await firestore.enableNetwork();
    });

    // **Held, not discarded.** While the network is down this future does not
    // complete - which is what the controller meets as a 20-second
    // `TimeoutException` and records as `ambiguous('write_timeout')`. When the
    // network returns it completes with the server's refusal, and that refusal
    // is the thing step 4 is about, so it is captured rather than allowed to
    // surface as an unhandled error.
    Object? writeError;
    final pending = firestore
        .doc(path)
        .set(<String, Object?>{
          'shiftId': shiftId,
          'tenantId': tenantId,
          'staffId': 'user-h2-probe',
          // `dev-` and 32 hex, which is what `validateCheckoutDeviceId` accepts.
          // The shape has to be real or the strict read model refuses the document
          // for its own reasons and proves nothing about H2.
          'deviceId': 'dev-0123456789abcdef0123456789abcdef',
          'businessDate': '2026-09-15',
          'status': 'open',
          'startTime': FieldValue.serverTimestamp(),
        })
        .then<void>((_) {}, onError: (Object error) => writeError = error);
    // Let the SDK apply the write to its local queue.
    await Future<void>.delayed(const Duration(milliseconds: 500));

    // ---- 1. The signal exists on the raw snapshot. ----
    final raw = await firestore
        .doc(path)
        .get(const GetOptions(source: Source.serverAndCache));
    expect(
      raw.exists,
      isTrue,
      reason:
          'If the pending write is not visible here, H2 has no mechanism and '
          'the finding is wrong.',
    );
    expect(
      raw.metadata.hasPendingWrites,
      isTrue,
      reason: 'The SDK knows this write has not reached the server.',
    );
    expect(
      raw.metadata.isFromCache,
      isTrue,
      reason: 'And it knows the answer did not come from the server.',
    );

    // ---- 2. The app's own reader discards it. ----
    final reader = FirebaseTenantDocumentReader(firestore);
    final snapshot = await reader.getDocument(path);
    expect(
      snapshot,
      isNotNull,
      reason:
          'The reader `_settle` uses returns the unsent write as a document, '
          'carrying nothing that says so - `TenantDocumentSnapshot` has a path '
          'and data and no metadata at all.',
    );

    // ---- 3. It parses as a canonical open shift. ----
    final shift = TenantShift.fromDocument(
      path: snapshot!.path,
      data: snapshot.data,
    );
    expect(
      shift.isOpen,
      isTrue,
      reason:
          'This is the value `_settle` branches on. An open shift here with a '
          'record that is not yet `serverConfirmedOpen` is the branch that '
          'writes `serverConfirmedOpen: true` - on the strength of a write the '
          'server has never seen.',
    );
    expect(
      shift.startedAt,
      isNull,
      reason:
          'The server timestamp is unresolved locally, and the strict read '
          'model accepts that rather than refusing the document - which is why '
          'the parse does not catch this.',
    );

    // ---- 3b. The fix: a server-backed read refuses to be fooled. ----
    //
    // **The whole of H2's fix rests on this and nothing else.**
    // `_settle` now proves a confirmation with `TenantDataReader.serverBacked`
    // before promoting a record to `serverConfirmedOpen`, which is only sound
    // if `Source.server` genuinely will not answer out of local storage. If it
    // fell back the way `serverAndCache` does, the fix would be decoration.
    final serverReader = reader.serverBacked;
    expect(
      serverReader,
      isNotNull,
      reason: 'The Firestore reader must offer the mode the fix depends on.',
    );
    Object? serverReadError;
    TenantDocumentSnapshot? serverAnswer;
    try {
      serverAnswer = await serverReader!.getDocument(path);
    } catch (error) {
      serverReadError = error;
    }
    expect(
      serverAnswer,
      isNull,
      reason:
          'A server-only read must never hand back this device own unsent '
          'write. Returning it here would mean the fix confirms exactly the '
          'shifts it was written to refuse.',
    );
    expect(
      serverReadError,
      isNotNull,
      reason:
          'And it fails rather than answering empty, which is the distinction '
          '`TenantServerReadable` documents: unreachable is not the same '
          'answer as absent, and only a failure keeps the record unconfirmed '
          'instead of clearing it.',
    );

    // ---- 4. The tail: the queued write is rejected, and the shift vanishes. ----
    //
    // **This is the half that costs a shop money.** By now the controller has
    // written `serverConfirmedOpen: true` on the strength of what was read
    // above, and the till has been selling against the shift all day. When the
    // network returns, the queued create is refused - `staffStanding` is false -
    // and Firestore reverts the local mutation. `_settle` then finds no shift
    // with a record that claims the server confirmed one, which sends it down
    // the *server is authoritative* branch: it clears the record, and every
    // outbox sale stamped with this shift id is left pointing at a shift that
    // will never exist.
    await firestore.enableNetwork();
    await pending;

    // The refusal itself, by the exact code `TenantShiftWriter` classifies as
    // `rejected` - and by the exact rule a deactivated cashier trips.
    expect(writeError, isA<FirebaseException>());
    expect(
      (writeError! as FirebaseException).code,
      'permission-denied',
      reason:
          '`staffStanding` is false for a staff document that does not exist '
          'and for one whose status is not active. This is that denial.',
    );

    final gone = await _pollUntilAbsent(firestore, path);
    expect(
      gone,
      isTrue,
      reason:
          'The rejected write must disappear from the cache for the rest of '
          'H2 to follow. If the document survives here, `_settle` would keep '
          'reading an open shift and the record would never be cleared.',
    );

    // **Deliberately not asserted here: what `reader.getDocument` returns now.**
    // In the real case the cashier is a member of the tenant, so the canonical
    // re-read succeeds and answers *absent* - which is the `shift == null` that
    // sends `_settle` down the clearing branch. Against this probe's
    // non-existent tenant the same read is refused outright, because the read
    // rule wants standing too. That refusal is an artefact of the probe rather
    // than a fact about H2, so the local revert above is where this stops: it
    // is the part that could only be learned from a device.
  });
}

/// Waits for a locally-pending document to be reverted by a server rejection.
///
/// Polls rather than listens: the point is what a later `_settle` would read,
/// and `_settle` reads with a `get`.
Future<bool> _pollUntilAbsent(
  FirebaseFirestore firestore,
  String path, {
  Duration timeout = const Duration(seconds: 45),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(seconds: 1));
    try {
      final snapshot = await firestore
          .doc(path)
          .get(const GetOptions(source: Source.cache));
      if (!snapshot.exists) return true;
    } on FirebaseException {
      // `Source.cache` throws for a path it holds nothing for, which is the
      // same answer as an absent document by a louder route.
      return true;
    }
  }
  return false;
}
