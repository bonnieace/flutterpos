/// Builds the debug APK against this machine's current LAN address, in one step.
///
/// **It exists because a DHCP lease broke the same build twice in one day.**
/// Android has refused cleartext since API 28, the Firebase emulators serve
/// plain HTTP, and `android/app/src/debug/res/xml/network_security_config.xml`
/// names the exact hosts a debug build may talk to. That list cannot hold a
/// subnet — `<domain>` takes hostnames and addresses and nothing else — so every
/// time the machine's address changes, the list is wrong.
///
/// **The failure is silent on the wire**, which is what makes it worth
/// automating rather than remembering. Android drops the socket before it
/// leaves the device: nothing reaches the emulator, nothing appears in its log,
/// and the app reports whatever its SDK says about a connection that never
/// happened — *"We could not open your business account"*, or a sign-in that
/// fails with no reason. Two hours went into diagnosing exactly that.
///
/// It does four things, in order, and stops at the first that fails:
///
///  1. reads this machine's current IPv4 address;
///  2. rewrites the one managed `<domain>` entry to match;
///  3. runs the drift test that guards the file;
///  4. builds the debug APK with the matching `--dart-define`.
///
/// ```
/// dart run tool/lan_debug_build.dart
/// dart run tool/lan_debug_build.dart --host 10.0.0.7   # say it yourself
/// dart run tool/lan_debug_build.dart --no-build        # sync and test only
/// ```
///
/// **Only the entry under the managed marker is touched.** The loopback hosts
/// above it are what `derivedEmulatorHost` returns and the drift test asserts
/// each one; the home-LAN line is a different network's lease and is nobody's
/// business but the person who added it. This rewrites one line and leaves the
/// file otherwise exactly as it was.
library;

import 'dart:io';

/// The comment that marks which `<domain>` this script owns.
///
/// A marker rather than a line number or a regex over addresses: the file is
/// edited by hand as well, and a script that guessed which entry was "the LAN
/// one" would eventually guess wrong and overwrite somebody's working host.
const String managedMarker = 'MANAGED BY tool/lan_debug_build.dart';

const String configPath =
    'android/app/src/debug/res/xml/network_security_config.xml';

Future<int> main(List<String> args) async {
  final explicit = _valueOf(args, '--host');
  final build = !args.contains('--no-build');

  final host = explicit ?? await _currentIpv4();
  if (host == null) {
    stderr.writeln(
      'Could not read an IPv4 address for this machine. Pass one yourself:\n'
      '  dart run tool/lan_debug_build.dart --host 10.0.0.7',
    );
    return 1;
  }
  stdout.writeln('Emulator host: $host');

  final changed = _syncConfig(host);
  stdout.writeln(
    changed
        ? 'Updated the managed cleartext entry in $configPath.'
        : 'The managed cleartext entry already names $host.',
  );

  // **The drift test runs before the build, not after, and that ordering is
  // the point.** `mergeDebugResources` is minutes into an Android build, and a
  // malformed comment or a host the config no longer covers fails there with a
  // message about XML rather than about this file. The test says it in seconds.
  stdout.writeln('Checking the cleartext config...');
  final test = await _run('flutter', <String>[
    'test',
    'test/dev/firebase_emulators_test.dart',
  ]);
  if (test != 0) {
    stderr.writeln('The cleartext drift test failed. Not building.');
    return test;
  }

  if (!build) {
    stdout.writeln('Config synced and checked. Skipping the build.');
    return 0;
  }

  stdout.writeln('Building the debug APK...');
  final apk = await _run('flutter', <String>[
    'build',
    'apk',
    '--debug',
    '--dart-define=USE_FIREBASE_EMULATORS=true',
    '--dart-define=FIREBASE_EMULATOR_HOST=$host',
  ], environment: <String, String>{
    // `C:` fills to zero and hangs the build in a Jetifier transform; the
    // Gradle home lives on `D:` on this machine and has to be said explicitly,
    // because Gradle recreates `~/.gradle` on `C:` when it is not.
    if (Platform.isWindows && Directory(r'D:\gradle-home').existsSync())
      'GRADLE_USER_HOME': r'D:\gradle-home',
  });
  if (apk != 0) return apk;

  const output = 'build/app/outputs/flutter-apk/app-debug.apk';
  stdout.writeln(
    '\nBuilt $output against $host.\n'
    'Install it with:\n'
    '  adb install -r --no-streaming $output\n\n'
    'A reinstall is not optional after a host change: the whitelist is aapt2'
    '-compiled binary XML inside the APK and the host is a compile-time\n'
    '`--dart-define`. Neither can be patched on the device.',
  );
  return 0;
}

/// Rewrites the managed `<domain>` entry to [host]. Returns whether it changed.
bool _syncConfig(String host) {
  final file = File(configPath);
  if (!file.existsSync()) {
    throw StateError('$configPath is missing.');
  }
  final lines = file.readAsLinesSync();
  final marker = lines.indexWhere((line) => line.contains(managedMarker));
  if (marker < 0) {
    throw StateError(
      'No line in $configPath contains "$managedMarker". Add it to the comment '
      'above whichever <domain> this script should own.',
    );
  }
  final target = lines.indexWhere(
    (line) => line.contains('<domain'),
    marker,
  );
  if (target < 0) {
    throw StateError('No <domain> follows the managed marker in $configPath.');
  }
  final replacement = lines[target].replaceFirst(
    RegExp(r'>[^<]*<'),
    '>$host<',
  );
  if (replacement == lines[target]) return false;
  lines[target] = replacement;
  // The file is CRLF in this repository and Git is configured to convert it;
  // writing LF here would show every line as changed in the next diff.
  file.writeAsStringSync('${lines.join('\r\n')}\r\n');
  return true;
}

/// This machine's IPv4 address on its active adapter, or null.
///
/// **The first non-loopback IPv4 on an up interface, and nothing cleverer.** A
/// machine on a phone hotspot has exactly one, and asking `NetworkInterface`
/// rather than parsing `ipconfig` means the same code answers on every
/// platform. Where the answer is wrong — a VPN, two adapters — `--host` is the
/// override, which is why it exists.
Future<String?> _currentIpv4() async {
  try {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (!address.isLoopback && !address.address.startsWith('169.254.')) {
          return address.address;
        }
      }
    }
  } on OSError {
    return null;
  }
  return null;
}

Future<int> _run(
  String executable,
  List<String> args, {
  Map<String, String> environment = const <String, String>{},
}) async {
  final process = await Process.start(
    executable,
    args,
    // Inherited rather than piped, and that is not laziness: piping this build
    // through a reader once buffered its whole output and left it apparently
    // hung for hours. Gradle's progress goes straight to the terminal.
    mode: ProcessStartMode.inheritStdio,
    runInShell: true,
    environment: environment,
  );
  return process.exitCode;
}

String? _valueOf(List<String> args, String flag) {
  final index = args.indexOf(flag);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}
