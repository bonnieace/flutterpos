/// No App Check provider is installed until something enforces App Check.
///
/// **Found on a phone on 2026-09-28.** The release build activated App Check
/// with Play Integrity, for an app nobody had registered with App Check. Every
/// Firebase SDK then waits for a token before it sends anything: Play
/// Integrity took 10-15 seconds, the exchange came back `400 App not
/// registered`, and by then the launch's `users` read had run out its 8-second
/// deadline. So every cold start, on Wi-Fi or 4G, told the person they were
/// offline. Debug builds did the same with an unregistered debug secret.
///
/// **Nothing consumes a token.** No function sets `enforceAppCheck`, and
/// neither set of rules can ask for one. A token nobody checks cannot protect
/// anything, and waiting for one cost every launch its first read.
///
/// **App Check's component is still in the build, and that is fine.** The
/// native Storage SDK (`firebase-storage`) depends on `firebase-appcheck`
/// itself, so every Android build registers App Check whatever this app does.
/// What the app controls is the provider. With none installed, a token request
/// fails at once (*No AppCheckProvider installed*) and Firestore, Auth and the
/// callables send without one: on the same phone, after this change, cold
/// starts on Wi-Fi and on 4G reached the server with no banner and no Play
/// Integrity call. (An older callable SDK did stop every call in that state;
/// the one this app resolves today does not.)
///
/// **So this guards the thing that installs a provider**: the
/// `firebase_app_check` plugin, which is the only way a provider reaches this
/// app. Bringing it back is one decision, not several: the plugin and a
/// provider, the app registered in the console with its signing certificate,
/// and enforcement switched on, together.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _package = 'firebase_app_check';

void main() {
  test('pubspec.yaml does not depend on the App Check plugin', () {
    final pubspec = File('pubspec.yaml').readAsLinesSync();
    expect(
      pubspec.where((line) => line.trimLeft().startsWith('$_package:')),
      isEmpty,
    );
  });

  test('no Dart package in the build brings the App Check plugin in', () {
    // The lock lists every Dart package the build resolves, direct or not, so
    // this also catches a plugin that depends on the App Check plugin. It says
    // nothing about native libraries - see above for `firebase-storage`.
    final lock = File('pubspec.lock').readAsLinesSync();
    expect(lock.where((line) => line.trim() == '$_package:'), isEmpty);
  });

  test('nothing in lib/ imports the App Check plugin', () {
    final importers = <String>[
      for (final entity in Directory('lib').listSync(recursive: true))
        if (entity is File &&
            entity.path.endsWith('.dart') &&
            entity.readAsStringSync().contains('package:$_package/'))
          entity.path.replaceAll(r'\', '/'),
    ];
    expect(importers, isEmpty);
  });
}
