import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// The compile-time switch that redirects Firebase traffic at the emulators.
///
/// It is deliberately a `--dart-define` rather than a runtime setting: a
/// runtime toggle would be reachable from a shipped binary, and the whole
/// safety argument for this file is that it cannot be.
const String useFirebaseEmulatorsDefine = 'USE_FIREBASE_EMULATORS';

/// Overrides the derived host, for a physical device on the same network.
const String firebaseEmulatorHostDefine = 'FIREBASE_EMULATOR_HOST';

const String firebaseEmulatorAuthPortDefine = 'FIREBASE_EMULATOR_AUTH_PORT';
const String firebaseEmulatorFirestorePortDefine =
    'FIREBASE_EMULATOR_FIRESTORE_PORT';
const String firebaseEmulatorFunctionsPortDefine =
    'FIREBASE_EMULATOR_FUNCTIONS_PORT';

/// These must stay identical to the `emulators` block in `firebase.json`.
///
/// They are duplicated rather than read, because the app has no access to that
/// file at runtime; the seed script reads the same block, so a port changed in
/// one place and not the other fails loudly at connect time rather than
/// silently writing to a different service.
const int defaultAuthEmulatorPort = 9099;
const int defaultFirestoreEmulatorPort = 8080;
const int defaultFunctionsEmulatorPort = 5001;

/// The address an Android emulator reaches its host machine on. `localhost`
/// inside that virtual machine is the virtual machine itself.
const String androidEmulatorHostAddress = '10.0.2.2';

/// Every other target - desktop, web, iOS simulator - reaches it on loopback.
const String loopbackHostAddress = '127.0.0.1';

const int _maximumPort = 65535;

final RegExp _hostPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9.\-]{0,254}$');

/// Raised when the emulator switch is asked for something it must never do.
///
/// Every case here is refused loudly instead of degraded. A switch that
/// silently fails to redirect writes test data into a real project; one that
/// silently redirects makes a real user's data vanish. Neither may happen
/// quietly, so there is no fallback path in this file.
final class FirebaseEmulatorMisconfiguration implements Exception {
  const FirebaseEmulatorMisconfiguration(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'FirebaseEmulatorMisconfiguration($code): $message';
}

/// One resolved local emulator suite address.
@immutable
final class FirebaseEmulatorTarget {
  const FirebaseEmulatorTarget._({
    required this.host,
    required this.authPort,
    required this.firestorePort,
    required this.functionsPort,
  });

  final String host;
  final int authPort;
  final int firestorePort;
  final int functionsPort;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FirebaseEmulatorTarget &&
          host == other.host &&
          authPort == other.authPort &&
          firestorePort == other.firestorePort &&
          functionsPort == other.functionsPort;

  @override
  int get hashCode => Object.hash(host, authPort, firestorePort, functionsPort);

  @override
  String toString() =>
      'FirebaseEmulatorTarget($host, auth $authPort, firestore $firestorePort, '
      'functions $functionsPort)';
}

/// Decides where Firebase traffic should go, or that it should not be moved.
///
/// This is the whole of the switch's logic and takes no Firebase types, so the
/// host derivation and every refusal below are provable without a device.
FirebaseEmulatorTarget? resolveFirebaseEmulatorTarget({
  required bool requested,
  required bool debugBuild,
  required bool isWeb,
  required TargetPlatform platform,
  String hostOverride = '',
  int authPort = defaultAuthEmulatorPort,
  int firestorePort = defaultFirestoreEmulatorPort,
  int functionsPort = defaultFunctionsEmulatorPort,
}) {
  if (!requested) return null;
  if (!debugBuild) {
    throw const FirebaseEmulatorMisconfiguration(
      'not_a_debug_build',
      'The Firebase emulator switch is only available in a debug build. '
          'Rebuild without the define, or run in debug mode.',
    );
  }
  return FirebaseEmulatorTarget._(
    host: hostOverride.isEmpty
        ? derivedEmulatorHost(isWeb: isWeb, platform: platform)
        : _validatedHost(hostOverride),
    authPort: _validatedPort(authPort, 'auth'),
    firestorePort: _validatedPort(firestorePort, 'firestore'),
    functionsPort: _validatedPort(functionsPort, 'functions'),
  );
}

/// The host this target reaches the developer machine on.
///
/// A web build served from a browser on Android still runs on the developer
/// machine's network stack, so it is the combination that decides rather than
/// the reported platform alone.
String derivedEmulatorHost({
  required bool isWeb,
  required TargetPlatform platform,
}) => !isWeb && platform == TargetPlatform.android
    ? androidEmulatorHostAddress
    : loopbackHostAddress;

/// Reads the compile-time switch, returning `null` when it was never asked for.
FirebaseEmulatorTarget? firebaseEmulatorTargetFromEnvironment() =>
    resolveFirebaseEmulatorTarget(
      requested: const bool.fromEnvironment(useFirebaseEmulatorsDefine),
      debugBuild: kDebugMode,
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
      hostOverride: const String.fromEnvironment(firebaseEmulatorHostDefine),
      authPort: const int.fromEnvironment(
        firebaseEmulatorAuthPortDefine,
        defaultValue: defaultAuthEmulatorPort,
      ),
      firestorePort: const int.fromEnvironment(
        firebaseEmulatorFirestorePortDefine,
        defaultValue: defaultFirestoreEmulatorPort,
      ),
      functionsPort: const int.fromEnvironment(
        firebaseEmulatorFunctionsPortDefine,
        defaultValue: defaultFunctionsEmulatorPort,
      ),
    );

bool _connected = false;

/// Whether this process has already redirected Firebase at an emulator.
@visibleForTesting
bool get firebaseEmulatorsConnected => _connected;

/// Redirects Auth, Firestore, and Functions at [target], exactly once.
///
/// The flag is raised before the first call rather than after the last, so a
/// partially applied redirect can never be retried into a mixed state where
/// some services are local and others are the real project.
Future<void> connectFirebaseEmulators(FirebaseEmulatorTarget target) async {
  if (_connected) {
    throw const FirebaseEmulatorMisconfiguration(
      'already_connected',
      'The Firebase emulators were already connected in this process.',
    );
  }
  _connected = true;
  // Host mapping is refused because this file already derived the host and a
  // second, hidden mapping would make the derivation unprovable.
  await FirebaseAuth.instance.useAuthEmulator(
    target.host,
    target.authPort,
    automaticHostMapping: false,
  );
  FirebaseFirestore.instance.useFirestoreEmulator(
    target.host,
    target.firestorePort,
    automaticHostMapping: false,
  );
  FirebaseFunctions.instance.useFunctionsEmulator(
    target.host,
    target.functionsPort,
    automaticHostMapping: false,
  );
}

/// Connects when the switch asks for it. Returns the target, or `null`.
///
/// Call it once, after `Firebase.initializeApp` and after any assignment to
/// `FirebaseFirestore.instance.settings`: `useFirestoreEmulator` records the
/// host inside those same settings, so a later whole-object assignment would
/// discard it and send writes to the real project.
Future<FirebaseEmulatorTarget?> connectFirebaseEmulatorsFromEnvironment() async {
  final target = firebaseEmulatorTargetFromEnvironment();
  if (target == null) return null;
  await connectFirebaseEmulators(target);
  return target;
}

@visibleForTesting
void resetFirebaseEmulatorConnectionForTesting() {
  _connected = false;
}

String _validatedHost(String host) {
  if (host != host.trim() || !_hostPattern.hasMatch(host)) {
    throw FirebaseEmulatorMisconfiguration(
      'invalid_host',
      'The emulator host must be a bare hostname or IPv4 address with no '
          'scheme, port, or path. Received: $host',
    );
  }
  return host;
}

int _validatedPort(int port, String service) {
  if (port < 1 || port > _maximumPort) {
    throw FirebaseEmulatorMisconfiguration(
      'invalid_port',
      'The $service emulator port must be between 1 and $_maximumPort. '
          'Received: $port',
    );
  }
  return port;
}
