/// `TenantAbandonedShiftRepository` against the deployed backend.
///
/// **The finding half, proved where it will actually run.** The repository asks
/// for every open shift in the business and then which of their cashiers can no
/// longer act - two reads the Rules only allow a manager or above, so a unit
/// test with a fake reader proves the logic and proves nothing about whether
/// the server will answer. This runs it as a real owner, against real documents.
///
/// It reports what it found rather than asserting a particular shop's state:
/// whether any shift is abandoned depends on who has been deactivated, which is
/// not this test's business to arrange.
///
/// ```
/// flutter test integration_test/abandoned_shift_probe_test.dart \
///   --dart-define=H2_PROBE_EMAIL=... --dart-define=H2_PROBE_PASSWORD=... \
///   --dart-define=H2_PROBE_TENANT=...
/// ```
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_application_1/firebase_options.dart';
import 'package:flutter_application_1/shift/abandoned_shift.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';

const String _email = String.fromEnvironment('H2_PROBE_EMAIL');
const String _password = String.fromEnvironment('H2_PROBE_PASSWORD');
const String _tenantId = String.fromEnvironment('H2_PROBE_TENANT');

void _say(Object? line) {
  // ignore: avoid_print
  print('PROBE $line');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('finds this business shifts that nobody can close', (
    tester,
  ) async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    if (_email.isEmpty || _password.isEmpty || _tenantId.isEmpty) {
      fail('Pass H2_PROBE_EMAIL, H2_PROBE_PASSWORD and H2_PROBE_TENANT.');
    }
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email,
        password: _password,
      );
    }
    final uid = FirebaseAuth.instance.currentUser!.uid;

    // The session the repository is built against. Read straight from the
    // canonical staff record rather than through the bootstrap, so this probe
    // depends on as little of the app as it can.
    final db = FirebaseFirestore.instance;
    final staff = await db.doc('tenants/$_tenantId/staff/$uid').get();
    _say('actor role=${staff.get('role')} status=${staff.get('status')}');

    final reader = FirebaseTenantDocumentReader(db);

    // Every open shift first, so the probe can say whether the repository
    // found none because there are none, or none because none are abandoned.
    final open = await db
        .collection('tenants/$_tenantId/shifts')
        .where('status', isEqualTo: 'open')
        .limit(10)
        .get();
    _say('open_shifts=${open.docs.length}');
    for (final doc in open.docs) {
      final staffId = doc.get('staffId');
      final member = await db.doc('tenants/$_tenantId/staff/$staffId').get();
      _say(
        '  shift=${doc.id} staff=$staffId '
        'staffStatus=${member.exists ? member.get('status') : 'absent'} '
        'businessDate=${doc.get('businessDate')}',
      );
    }

    final session = TenantSession.active(
      uid: uid,
      tenantId: _tenantId,
      role: TenantRole.owner,
    );
    final found = await TenantAbandonedShiftRepository(
      session: session,
      reader: reader,
    ).find(collectionReader: reader);

    _say('abandoned=${found.length}');
    for (final shift in found) {
      _say(
        '  abandoned shift=${shift.shiftId} staff=${shift.staffName} '
        '(${shift.staffId}) on ${shift.businessDate}',
      );
    }

    // The one thing that must hold whatever the shop's state is: every shift
    // this reports is one whose cashier really cannot act.
    for (final shift in found) {
      final member = await db
          .doc('tenants/$_tenantId/staff/${shift.staffId}')
          .get();
      expect(
        member.exists ? member.get('status') : 'absent',
        isNot('active'),
        reason:
            'An active cashier own open shift must never be offered to an '
            'owner to end.',
      );
    }
  });
}
