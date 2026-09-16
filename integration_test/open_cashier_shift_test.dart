/// Opens one shift as a real cashier, so the abandoned-shift path has a subject.
///
/// **A fixture, not a test of anything.** Proving that an owner is offered a
/// colleague's unclosable shift needs a colleague with an open shift, and the
/// only honest way to get one is for that cashier to open it. This signs in as
/// them and creates the shift through the same Rules a till does - same shape,
/// same server timestamp, same `activeStaff` check - so what it leaves behind is
/// a shift the cashier really opened.
///
/// Deactivating them afterwards is done from the owner's Staff screen, because
/// that is the act being tested.
///
/// ```
/// flutter test integration_test/open_cashier_shift_test.dart \
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

const String _email = String.fromEnvironment('H2_PROBE_EMAIL');
const String _password = String.fromEnvironment('H2_PROBE_PASSWORD');
const String _tenantId = String.fromEnvironment('H2_PROBE_TENANT');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('opens a shift as this cashier', (tester) async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    if (_email.isEmpty || _password.isEmpty || _tenantId.isEmpty) {
      fail('Pass H2_PROBE_EMAIL, H2_PROBE_PASSWORD and H2_PROBE_TENANT.');
    }
    // Signed out first: the emulator is signed in as the owner, and this shift
    // has to belong to the cashier or it proves nothing.
    await FirebaseAuth.instance.signOut();
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: _email,
      password: _password,
    );
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final now = DateTime.now();
    final businessDate =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final shiftId = 'sh-${now.millisecondsSinceEpoch}-abcd1234abcd1234';

    await FirebaseFirestore.instance
        .doc('tenants/$_tenantId/shifts/$shiftId')
        .set(<String, Object?>{
          'shiftId': shiftId,
          'tenantId': _tenantId,
          'staffId': uid,
          'deviceId': 'dev-00000000000000000000000000000001',
          'businessDate': businessDate,
          'status': 'open',
          // The Rules require the server's own clock here, exactly as the till
          // does: no device may decide when a shift began.
          'startTime': FieldValue.serverTimestamp(),
        });

    // ignore: avoid_print
    print('PROBE opened shift=$shiftId staff=$uid on $businessDate');

    final written = await FirebaseFirestore.instance
        .doc('tenants/$_tenantId/shifts/$shiftId')
        .get(const GetOptions(source: Source.server));
    expect(written.exists, isTrue);
    expect(written.get('status'), 'open');

    // Left signed in as nobody, so the app comes back to its own sign-in rather
    // than to a session this fixture chose.
    await FirebaseAuth.instance.signOut();
  });
}
