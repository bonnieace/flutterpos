/// What the *deployed* backend does, asked from a device rather than inferred.
///
/// **The CLI cannot answer this and a device can.** `firebase functions:list`
/// reports no deploy time, and there is no command that fetches the live
/// security rules at all - so the only honest way to know what a deployed
/// backend is running is to make it run.
///
/// Signed in as an administrator it goes further than the rules: it asks the
/// live reconciliation to run, then reads what that run wrote. N2's whole
/// change is which verdict an evidence-free close receives, so the verdict on
/// such a shift is the deployed code identifying itself -
/// `invalid_or_missing_shift` is the fixed build and `variance` is the old one.
///
/// ```
/// flutter test integration_test/deploy_probe_test.dart \
///   --dart-define=H2_PROBE_EMAIL=... --dart-define=H2_PROBE_PASSWORD=... \
///   --dart-define=H2_PROBE_TENANT=...
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
const String _tenantId = String.fromEnvironment('H2_PROBE_TENANT');

void _say(Object? line) {
  // ignore: avoid_print
  print('PROBE $line');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reports what the deployed backend actually does', (
    tester,
  ) async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    if (_email.isEmpty || _password.isEmpty) {
      fail('Pass --dart-define=H2_PROBE_EMAIL and H2_PROBE_PASSWORD.');
    }
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email,
        password: _password,
      );
    }
    _say('uid=${FirebaseAuth.instance.currentUser!.uid}');

    // ---- Are the deployed rules enforcing? ----
    String rulesVerdict;
    try {
      await FirebaseFirestore.instance
          .doc('tenants/deploy-probe-absent/shifts/sh-probe')
          .set(<String, Object?>{'shiftId': 'sh-probe'});
      rulesVerdict = 'PERMITTED - live rules are NOT this repository\'s';
    } on FirebaseException catch (error) {
      rulesVerdict = 'refused with ${error.code}';
    }
    _say('firestore_rules=$rulesVerdict');
    expect(rulesVerdict, contains('permission-denied'));

    final functions = FirebaseFunctions.instanceFor(region: 'us-central1');

    // ---- What does this account reach? ----
    final tenants = await functions
        .httpsCallable('listMyTenants')
        .call<Object?>(<String, Object?>{});
    _say('listMyTenants=${tenants.data}');

    if (_tenantId.isEmpty) {
      _say('no H2_PROBE_TENANT given; stopping after the rules and callable.');
      return;
    }

    // ---- Make the live reconciliation run. ----
    //
    // Administrators only, which is why this half needs the second account. A
    // successful queue is already proof that `requestTenantReconciliation` is
    // deployed and that this actor passes its role check on the server.
    try {
      final queued = await functions
          .httpsCallable('requestTenantReconciliation')
          .call<Object?>(<String, Object?>{
            'tenantId': _tenantId,
            'mode': 'incremental',
            'requestId': 'probe-${DateTime.now().millisecondsSinceEpoch}',
          });
      _say('requestTenantReconciliation=${queued.data}');
    } on FirebaseFunctionsException catch (error) {
      _say('requestTenantReconciliation=${error.code} ${error.message}');
      // **`resource-exhausted` is a pass, not a failure.** It is the server's
      // own throttle on manual runs, so receiving it proves the deployed
      // callable accepted and recorded an earlier request - which is the thing
      // being established. Anything else is a real refusal.
      expect(
        error.code,
        'resource-exhausted',
        reason: 'The reconciliation callable refused for an unexpected reason.',
      );
    }

    // Give the queued task time to claim and run.
    await Future<void>.delayed(const Duration(seconds: 45));

    // ---- Read what that run wrote. ----
    final db = FirebaseFirestore.instance;

    // Any shift closed without evidence is the one N2 changed the verdict for.
    final evidenceFree = await db
        .collection('tenants/$_tenantId/shifts')
        .where('closedWithoutEvidence', isEqualTo: true)
        .limit(5)
        .get();
    _say('shifts_closed_without_evidence=${evidenceFree.docs.length}');
    for (final doc in evidenceFree.docs) {
      _say('  evidence_free_shift=${doc.id}');
    }

    // `shift_verifications` is deliberately not read: the rules give it no
    // client access at all, which is correct - it is reconciliation's own
    // working record. The anomalies are the surface the product exposes, and
    // they carry the verdict N1 and N2 changed.
    final anomalies = await db
        .collection('tenants/$_tenantId/reconciliation_anomalies')
        .limit(20)
        .get();
    _say('reconciliation_anomalies=${anomalies.docs.length}');
    for (final doc in anomalies.docs) {
      final data = doc.data();
      _say(
        '  anomaly=${doc.id} type=${data['anomalyType']} '
        'resolution=${data['resolution']} '
        'cashVariance=${data['cashVarianceMinor']} '
        'totalVariance=${data['totalVarianceMinor']}',
      );
    }
  });
}
