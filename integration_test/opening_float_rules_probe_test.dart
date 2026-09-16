/// The deployed Rules' opinion of an opening float, asked directly.
///
/// **This exists because the float's last line of defence is a Rules clause,
/// and a clause is only real once it is deployed.** The intent refuses a bad
/// float and `compareShiftTenders` declines to believe one, so nothing is
/// currently mis-reported either way - but a figure the server will *store* is
/// a figure some future reader may trust, and the write is the only place that
/// can be refused outright.
///
/// **Every case here is a refusal, so the probe writes nothing.** It creates no
/// shift, leaves no open till behind, and needs no cleanup - which is what lets
/// it run against a real business rather than a scratch one. The accepting case
/// is covered by the emulator suite and by opening a shift through the app;
/// proving it here would mean leaving a real open shift on a real shop.
///
/// ```
/// flutter test integration_test/opening_float_rules_probe_test.dart \
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

import 'package:flutter_application_1/firebase_options.dart';

const String _email = String.fromEnvironment('H2_PROBE_EMAIL');
const String _password = String.fromEnvironment('H2_PROBE_PASSWORD');
const String _tenantId = String.fromEnvironment('H2_PROBE_TENANT');

void _say(Object? line) {
  // ignore: avoid_print
  print('PROBE $line');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the deployed rules refuse a float they must not store', (
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

    // **Discovered rather than passed in**, so the probe cannot be pointed at a
    // business this account is not a member of and read the resulting denial as
    // the float clause doing its job. It asks the same callable the app asks.
    final tenantId = _tenantId.isNotEmpty
        ? _tenantId
        : await _firstTenantOf(uid);
    _say('tenant=$tenantId');

    final staff = await db.doc('tenants/$tenantId/staff/$uid').get();
    _say('actor role=${staff.get('role')} status=${staff.get('status')}');
    // The float clause only decides for a writer the rest of the rule already
    // accepts. An inactive or absent member is denied before it is consulted,
    // which would make every case below pass for the wrong reason.
    expect(
      staff.exists && staff.get('status') == 'active',
      isTrue,
      reason:
          'This account must be active staff for the probe to mean '
          'anything: a non-member is denied whatever the float says.',
    );

    // A distinct id per case, so a write that is wrongly allowed is visible as
    // a document rather than colliding with an earlier one and looking denied.
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final today = DateTime.now();
    final businessDate =
        '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';

    Future<String> attempt(String name, Object? float) async {
      final shiftId = 'float-probe-$stamp-$name';
      try {
        await db.doc('tenants/$tenantId/shifts/$shiftId').set(<String, Object?>{
          'shiftId': shiftId,
          'tenantId': tenantId,
          'staffId': uid,
          'deviceId': 'float-probe-device',
          'businessDate': businessDate,
          'status': 'open',
          'startTime': FieldValue.serverTimestamp(),
          'openingFloatMinor': float,
        });
        return 'ALLOWED';
      } on FirebaseException catch (error) {
        return error.code;
      }
    }

    // **The one that matters is the negative.** It is the only direction worth
    // writing a dishonest float in: it lowers the cash the drawer has to
    // account for, so a shortfall could be settled by claiming the till began
    // fuller than it did.
    final cases = <String, Object?>{
      'negative': -1,
      'fractional': 1500.5,
      'text': '2000',
      'absurd': 1000000000001,
    };

    final results = <String, String>{};
    for (final entry in cases.entries) {
      results[entry.key] = await attempt(entry.key, entry.value);
      _say('${entry.key} -> ${results[entry.key]}');
    }

    for (final entry in results.entries) {
      expect(
        entry.value,
        'permission-denied',
        reason:
            'The deployed rules accepted a ${entry.key} opening float. '
            'Either firestore.rules is not deployed or the clause is wrong.',
      );
    }

    // Nothing was written, and the probe says so rather than assuming it.
    for (final name in cases.keys) {
      final left = await db
          .doc('tenants/$tenantId/shifts/float-probe-$stamp-$name')
          .get();
      expect(left.exists, isFalse, reason: 'A refused $name float persisted.');
    }
    _say('no probe shift persisted');
  });
}

/// The first business this account belongs to, by the app's own callable.
Future<String> _firstTenantOf(String uid) async {
  final response = await FirebaseFunctions.instanceFor(region: 'us-central1')
      .httpsCallable('listMyTenants')
      .call<Object?>(<String, Object?>{'pageSize': 10});
  final data = response.data;
  if (data is! Map) fail('listMyTenants returned a non-object.');
  final items = data['items'];
  if (items is! List || items.isEmpty) fail('This account has no business.');
  final first = items.first;
  if (first is! Map) fail('A tenant item must be an object.');
  return (first['tenantId'] ?? first['id']).toString();
}
