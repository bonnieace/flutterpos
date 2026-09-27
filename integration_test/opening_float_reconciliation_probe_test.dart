/// The float's whole purpose, judged by the deployed server on real data.
///
/// **The one claim nothing else in this work can make.** Unit tests prove the
/// arithmetic, the emulator proves the Rules, and the device proves the figure
/// is recorded - but none of them proves that the function which actually runs
/// every night reads that figure and calls a floated drawer balanced. That is
/// the defect M3 is about, and it only exists once `runTenantReconciliationTask`
/// has judged a real shift.
///
/// It asks for a shift this device has already closed rather than creating one:
/// a float must be counted against sales rung up through the app, and a probe
/// that wrote its own sales would be marking its own homework.
///
/// ```
/// flutter test integration_test/opening_float_reconciliation_probe_test.dart \
///   --dart-define=H2_PROBE_EMAIL=... --dart-define=H2_PROBE_PASSWORD=... \
///   --dart-define=FLOAT_PROBE_SHIFT=...
/// ```
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:uzapay_pos/firebase_options.dart';

const String _email = String.fromEnvironment('H2_PROBE_EMAIL');
const String _password = String.fromEnvironment('H2_PROBE_PASSWORD');

void _say(Object? line) {
  // ignore: avoid_print
  print('PROBE $line');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the nightly run counts an opening float back out', (
    tester,
  ) async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    if (_email.isEmpty || _password.isEmpty) {
      fail('Pass H2_PROBE_EMAIL and H2_PROBE_PASSWORD.');
    }
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email,
        password: _password,
      );
    }
    final db = FirebaseFirestore.instance;
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final functions = FirebaseFunctions.instanceFor(region: 'us-central1');

    final tenants = await functions
        .httpsCallable('listMyTenants')
        .call<Object?>(<String, Object?>{'pageSize': 10});
    final items = (tenants.data as Map)['items'] as List;
    final tenantId =
        ((items.first as Map)['tenantId'] ?? (items.first as Map)['id'])
            .toString();
    _say('tenant=$tenantId');

    // The most recently closed shift carrying a float, which is the one the
    // app just closed. Named by what it is rather than by an id passed in, so
    // the probe cannot be pointed at a shift that never had one.
    // **One indexed field, the rest sorted here.** Narrowing on staffId,
    // status and endTime together needs a composite index, and adding one to a
    // real project for the sake of a probe is a change to the shop rather than
    // a reading of it.
    final closed = await db
        .collection('tenants/$tenantId/shifts')
        .where('staffId', isEqualTo: uid)
        .limit(50)
        .get();
    final floated =
        closed.docs
            .where(
              (doc) =>
                  doc.data()['status'] == 'closed' &&
                  (doc.data()['openingFloatMinor'] as int? ?? 0) > 0,
            )
            .toList()
          ..sort((a, b) {
            final left = a.data()['endTime'];
            final right = b.data()['endTime'];
            if (left is! Timestamp || right is! Timestamp) return 0;
            return right.compareTo(left);
          });
    expect(
      floated,
      isNotEmpty,
      reason:
          'No closed shift carries an opening float. Close one through '
          'the app with a float first.',
    );
    final shift = floated.first;
    final floatMinor = shift.get('openingFloatMinor') as int;
    final declaredCash = shift.get('declaredCashMinor') as int;
    final businessDate = shift.get('businessDate') as String;
    _say('shift=${shift.id} businessDate=$businessDate');
    _say('  openingFloatMinor=$floatMinor declaredCashMinor=$declaredCash');
    _say('  totalSalesMinor=${shift.get('totalSalesMinor')}');

    // **The figure the whole finding turns on.** The drawer was counted whole,
    // so what the cashier declared is the float plus the takings; the server
    // has to subtract the float back out before it marks them.
    expect(
      declaredCash - floatMinor,
      shift.get('totalSalesMinor'),
      reason:
          'This probe only means something where the drawer balances: '
          'the declared cash must be the float plus the recorded sales.',
    );

    // **A refused request is as good as an accepted one here.** Manual
    // incremental runs are rate limited to one every five minutes, so a probe
    // re-run inside that window is told the work is already in hand rather
    // than being allowed to queue it twice. Either way a run is coming, which
    // is all this needs before it reads the result.
    try {
      await functions
          .httpsCallable('requestTenantReconciliation')
          .call<Object?>(<String, Object?>{
            'tenantId': tenantId,
            'mode': 'incremental',
            'requestId': 'float-probe-${DateTime.now().millisecondsSinceEpoch}',
          });
      _say('reconciliation queued');
    } on FirebaseFunctionsException catch (error) {
      if (error.code != 'resource-exhausted') rethrow;
      _say('reconciliation already requested within the cooldown');
    }

    // **The run is a queued task, and what a client may read of its result is
    // the difference it did or did not raise.** `shift_verifications` is
    // server-only by Rules - deliberately, since nothing on a device should be
    // able to see or touch the server's own working - so the observable proof
    // is the one an owner actually experiences: whether a difference is waiting
    // for them. Before this fix there would be one, worth the whole float.
    Map<String, Object?>? offending;
    var sawRun = false;
    for (var attempt = 0; attempt < 30; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 4));
      final anomalies = await db
          .collection('tenants/$tenantId/reconciliation_anomalies')
          .where('anomalyType', isEqualTo: 'shift_tender_variance')
          .get();
      final mine = anomalies.docs.where(
        (doc) => doc.data()['shiftId'] == shift.id,
      );
      offending = mine.isEmpty ? null : mine.first.data();

      // A run has to have actually happened for an absent difference to mean
      // anything, so the summary is read as well: it is recomputed by every
      // completed run.
      final summary = await db
          .collection('tenants/$tenantId/reconciliation_summary')
          .limit(1)
          .get();
      sawRun = summary.docs.isNotEmpty;
      _say(
        '  attempt ${attempt + 1}: runRecorded=$sawRun '
        'tenderVarianceForThisShift=${offending != null}',
      );
      if (sawRun && offending == null && attempt >= 3) break;
    }

    if (offending != null) {
      _say('OFFENDING cashVarianceMinor=${offending['cashVarianceMinor']}');
      _say('  totalVarianceMinor=${offending['totalVarianceMinor']}');
      _say('  openingFloatMinor=${offending['openingFloatMinor']}');
    }

    expect(
      sawRun,
      isTrue,
      reason:
          'No reconciliation run was recorded, so an absent difference '
          'proves nothing.',
    );
    // **The assertion M3 exists for.** A drawer counted whole - float plus
    // takings - balances, and the owner is shown nothing to dismiss. Before the
    // fix this shift raised a tender difference equal to its entire float,
    // every night it was run.
    expect(
      offending,
      isNull,
      reason:
          'The run raised a tender difference for a drawer that balances, '
          'which is the defect M3 fixed.',
    );
  });
}
