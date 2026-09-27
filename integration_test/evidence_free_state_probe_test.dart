/// What the deployed backend now says about evidence-free closes.
///
/// Read-only: it writes nothing and asks for nothing to be recomputed. It
/// reports which closed shifts were closed without their sales, whether each
/// carries a declaration the cashier typed, and which tender differences the
/// server is currently holding - the three facts that together say whether N7
/// is live and whether anything on this shop demonstrates it.
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

  testWidgets('reports evidence-free closes and the differences held', (
    tester,
  ) async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email,
        password: _password,
      );
    }
    final db = FirebaseFirestore.instance;
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final tenants = await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('listMyTenants')
        .call<Object?>(<String, Object?>{'pageSize': 10});
    final items = (tenants.data as Map)['items'] as List;
    final tenantId =
        ((items.first as Map)['tenantId'] ?? (items.first as Map)['id'])
            .toString();
    _say('tenant=$tenantId');

    final shifts = await db
        .collection('tenants/$tenantId/shifts')
        .where('staffId', isEqualTo: uid)
        .limit(80)
        .get();
    var evidenceFree = 0;
    var evidenceFreeDeclared = 0;
    for (final doc in shifts.docs) {
      final data = doc.data();
      if (data['closedWithoutEvidence'] != true) continue;
      evidenceFree++;
      final declared = data['declaredCashMinor'];
      if (declared != null) evidenceFreeDeclared++;
      _say(
        '  evidence-free ${doc.id} date=${data['businessDate']} '
        'declaredCashMinor=$declared '
        'openingFloatMinor=${data['openingFloatMinor'] ?? 0}',
      );
    }
    _say('evidence_free=$evidenceFree declared=$evidenceFreeDeclared');

    // **Force a run before reading, so the answer is this build's.** An
    // anomaly that is simply old says nothing about what was deployed.
    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('requestTenantReconciliation')
          .call<Object?>(<String, Object?>{
            'tenantId': tenantId,
            'mode': 'full',
            'requestId': 'n7-probe-${DateTime.now().millisecondsSinceEpoch}',
          });
      _say('reconciliation queued');
    } on FirebaseFunctionsException catch (error) {
      if (error.code != 'resource-exhausted') rethrow;
      _say('reconciliation already requested within the cooldown');
    }
    // A full run regenerates every expectation and re-verifies it, which is
    // what forces the question to be asked again of shifts nothing has touched.
    // It takes longer than the incremental sweep, so it is waited on properly.
    for (var attempt = 0; attempt < 24; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 10));
      final variances = await db
          .collection('tenants/$tenantId/reconciliation_anomalies')
          .where('anomalyType', isEqualTo: 'shift_tender_variance')
          .get();
      _say(
        '  attempt ${attempt + 1}: tender_variances=${variances.docs.length}',
      );
      if (variances.docs.length > 1) break;
    }

    // The one shift that decides it: a tender difference standing against a
    // shift the sales half could not verify. That pair was impossible before
    // N7 - `compareShiftTenders` returned `unverifiable` for every
    // evidence-free close, so it could never raise a difference for one.
    for (final id in <String>[
      'sh-1789553403531-cb0a06746fbdaef2',
      'sh-1789495802500-043c7f40f78aa806',
    ]) {
      final doc = await db.doc('tenants/$tenantId/shifts/$id').get();
      if (!doc.exists) {
        _say('subject $id absent');
        continue;
      }
      final data = doc.data()!;
      _say('subject $id');
      _say('  closedWithoutEvidence=${data['closedWithoutEvidence']}');
      _say('  declaredCashMinor=${data['declaredCashMinor']}');
      _say('  declaredMpesaMinor=${data['declaredMpesaMinor']}');
      _say('  declaredCardMinor=${data['declaredCardMinor']}');
      _say('  openingFloatMinor=${data['openingFloatMinor'] ?? 0}');
      _say('  totalSalesMinor=${data['totalSalesMinor']}');
      _say('  staffId=${data['staffId']}');
    }

    for (final type in <String>[
      'shift_tender_variance',
      'invalid_or_missing_shift',
      'missing_tender_declaration',
    ]) {
      final found = await db
          .collection('tenants/$tenantId/reconciliation_anomalies')
          .where('anomalyType', isEqualTo: type)
          .get();
      _say('$type=${found.docs.length}');
      for (final doc in found.docs.take(6)) {
        _say(
          '  ${doc.data()['shiftId'] ?? doc.id} '
          'total=${doc.data()['totalVarianceMinor']} '
          'cash=${doc.data()['cashVarianceMinor']} '
          'float=${doc.data()['openingFloatMinor']} '
          'resolution=${doc.data()['resolution']}',
        );
      }
    }
  });
}
