/// The App Link that brings somebody back from their mailbox, and the five
/// files that have to agree before it works.
///
/// **Every way this breaks is silent.** An App Link is not a feature the app can
/// test at runtime: Android decides at *install* time whether to hand the URL to
/// the app or to a browser, by fetching `/.well-known/assetlinks.json` from each
/// declared host and looking for the signing key the APK was signed with. When
/// that fetch 404s, or the fingerprint does not match, nothing fails. The link
/// simply opens a browser, the person has to find their way back to the app by
/// hand, and no log line anywhere says why. `firebase.json` already carries a
/// comment about one instance of this - `**/.*` in `ignore` kept `.well-known/`
/// out of every deploy - which is the evidence that it is worth a test.
///
/// The debug fingerprint is tracked here for local installs. Play re-signs
/// distributed installs; its app-signing SHA-256 must be added after the first
/// upload key and Play app-signing certificate exist.
///
/// **What this cannot check.** Whether Android actually verified the link on a
/// given device, and whether a host outside this repo serves the file at all.
/// [_hostOrigins] is the stand-in: every auto-verified host has to be listed
/// with where its copy comes from, so a new host is a decision somebody took.
library;

import 'dart:convert' show jsonDecode;
import 'dart:io' show File, Platform, Process, ProcessException;

import 'package:flutter_test/flutter_test.dart';

const String _manifestPath = 'android/app/src/main/AndroidManifest.xml';
const String _gradlePath = 'android/app/build.gradle.kts';
const String _assetlinksPath = 'public/.well-known/assetlinks.json';
const String _hostingPath = 'firebase.json';
const String _deployedEnvPath = 'functions/.env.multitenant-pos-b8326';

/// Where each auto-verified host's `/.well-known/assetlinks.json` comes from.
///
/// Adding a host to the manifest without adding it here fails the set test,
/// because an auto-verified host with no served assetlinks file is the exact
/// shape of the silent failure this file exists for.
const Map<String, String> _hostOrigins = <String, String>{
  'multitenant-pos-b8326.web.app':
      'public/.well-known/assetlinks.json, deployed with `firebase deploy '
      '--only hosting` - the default Hosting domain for the dev project.',
  'auth.uzapay.co.ke':
      'the same Hosting site once the custom domain is attached to it. Served '
      'from anywhere else, this host never verifies and its links open a '
      'browser.',
};

/// Emails whose link is meant to land back in the app.
///
/// `PASSWORD_RESET_CONTINUE_URL` is deliberately absent: a reset finishes on the
/// web page and the person then signs in, so there is no in-app step for the
/// link to shorten.
const List<String> _appBoundContinueUrls = <String>[
  'EMAIL_VERIFICATION_CONTINUE_URL',
  'STAFF_INVITATION_ACTION_BASE_URL',
];

String _read(String path) => File(path).readAsStringSync();

/// XML with its comments gone.
///
/// The manifest documents both filters at length and names every host it
/// declares in prose. A scan that read the comments would find hosts that are
/// not declared and paths that were removed long ago.
String _withoutComments(String xml) =>
    xml.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

final class _LinkFilter {
  const _LinkFilter(this.hosts, this.paths);
  final Set<String> hosts;
  final Set<String> paths;

  bool covers(Uri url) => hosts.contains(url.host) && paths.contains(url.path);
}

Set<String> _attribute(String block, String name) => <String>{
  for (final match in RegExp('android:$name="([^"]+)"').allMatches(block))
    match.group(1)!,
};

List<_LinkFilter> _autoVerifyFilters() {
  final manifest = _withoutComments(_read(_manifestPath));
  final blocks = RegExp(
    r'<intent-filter[^>]*android:autoVerify="true"[^>]*>(.*?)</intent-filter>',
    dotAll: true,
  );
  return <_LinkFilter>[
    for (final block in blocks.allMatches(manifest))
      _LinkFilter(
        _attribute(block.group(1)!, 'host'),
        _attribute(block.group(1)!, 'path'),
      ),
  ];
}

/// The `release` build type's body.
///
/// Stops at the first `}`, which the current block reaches. A release block that
/// grows a nested brace truncates here and fails the signing test rather than
/// passing it - which is the direction a parser this crude should fail in.
String _releaseBuildType() {
  final gradle = _read(_gradlePath);
  final start = gradle.indexOf(RegExp(r'\brelease\s*\{'));
  expect(
    start,
    isNonNegative,
    reason: '$_gradlePath declares no release build type.',
  );
  return gradle.substring(start, gradle.indexOf('}', start));
}

Map<String, Object?> _assetlinkStatement() {
  final statements = jsonDecode(_read(_assetlinksPath)) as List<Object?>;
  expect(
    statements,
    hasLength(1),
    reason:
        '$_assetlinksPath should hold one statement for this app. More than '
        'one is either a second app or a stale entry, and Android accepts '
        'whichever matches - so a wrong one is not visible in the result.',
  );
  return statements.single! as Map<String, Object?>;
}

Map<String, Object?> _assetlinkTarget() =>
    _assetlinkStatement()['target']! as Map<String, Object?>;

List<String> _declaredFingerprints() => <String>[
  for (final value
      in _assetlinkTarget()['sha256_cert_fingerprints']! as List<Object?>)
    value! as String,
];

/// The debug keystore's SHA-256, or null where it cannot be read.
///
/// Null is a skip rather than a failure: a machine with no Android SDK on it
/// still runs the manifest and hosted-file checks.
String? _debugKeystoreFingerprint() {
  final home =
      Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
  if (home == null) return null;
  final keystore = File('$home/.android/debug.keystore');
  if (!keystore.existsSync()) return null;
  try {
    final result = Process.runSync('keytool', <String>[
      '-list',
      '-v',
      '-keystore',
      keystore.path,
      '-alias',
      'androiddebugkey',
      '-storepass',
      'android',
      '-keypass',
      'android',
    ]);
    if (result.exitCode != 0) return null;
    return RegExp(
      r'SHA256:\s*([0-9A-Fa-f:]{95})',
    ).firstMatch('${result.stdout}')?.group(1)?.toUpperCase();
  } on ProcessException {
    return null;
  }
}

Map<String, String> _deployedParameters() {
  final values = <String, String>{};
  for (final line in _read(_deployedEnvPath).split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final split = trimmed.indexOf('=');
    if (split > 0) {
      values[trimmed.substring(0, split)] = trimmed.substring(split + 1);
    }
  }
  return values;
}

void main() {
  test('the scan finds the filters it is written about', () {
    final filters = _autoVerifyFilters();

    expect(
      filters,
      hasLength(2),
      reason:
          'Expected the verification filter and the staff invitation filter. '
          'A filter added or removed changes what this whole file asserts '
          'about, so it is a deliberate edit rather than a passing detail.',
    );
    expect(
      filters.expand((_LinkFilter filter) => filter.paths),
      containsAll(<String>['/auth/verified', '/staff/invitation']),
    );
  });

  test('every auto-verified host has a recorded assetlinks origin', () {
    final declared = <String>{
      for (final filter in _autoVerifyFilters()) ...filter.hosts,
    };

    expect(
      declared.difference(_hostOrigins.keys.toSet()),
      isEmpty,
      reason:
          'An autoVerify host in $_manifestPath that _hostOrigins does not '
          'name. Android fetches /.well-known/assetlinks.json from it on '
          'install and opens a browser for every link if that 404s - with no '
          'error anywhere. Record where the file is served from.',
    );
    expect(
      _hostOrigins.keys.toSet().difference(declared),
      isEmpty,
      reason: '_hostOrigins names a host the manifest no longer declares.',
    );
  });

  test('assetlinks.json describes the application this repo builds', () {
    final statement = _assetlinkStatement();
    final target = _assetlinkTarget();
    final applicationId = RegExp(
      r'applicationId\s*=\s*"([^"]+)"',
    ).firstMatch(_read(_gradlePath))?.group(1);

    expect(
      statement['relation'],
      contains('delegate_permission/common.handle_all_urls'),
      reason:
          'Without this relation the statement grants nothing and every link '
          'opens a browser.',
    );
    expect(target['namespace'], 'android_app');
    expect(
      target['package_name'],
      applicationId,
      reason:
          'assetlinks.json names a package this repo does not build. Android '
          'matches on package AND fingerprint, so a stale package name fails '
          'verification as completely as a stale key.',
    );
    expect(_declaredFingerprints(), isNotEmpty);
    for (final fingerprint in _declaredFingerprints()) {
      expect(
        fingerprint,
        matches(RegExp(r'^(?:[0-9A-F]{2}:){31}[0-9A-F]{2}$')),
        reason:
            'A SHA-256 here is 32 colon-separated uppercase hex bytes. '
            'keytool prints exactly that; anything else was retyped.',
      );
    }
  });

  test('release does not use the debug signing key', () {
    expect(
      _releaseBuildType(),
      contains('signingConfigs.getByName("release")'),
      reason:
          'Google Play uploads must use the private upload key configured in '
          'android/key.properties, never the public debug key.',
    );
  });

  test(
    'the declared fingerprint is the key builds are actually signed with',
    () {
      final actual = _debugKeystoreFingerprint();
      if (actual == null) {
        // No Android SDK on this machine. The remaining checks still run.
        return;
      }

      expect(
        _declaredFingerprints(),
        contains(actual),
        reason:
            'The debug keystore on this machine signs with $actual, which '
            '$_assetlinksPath does not declare. Every App Link opens a browser '
            'on debug builds. A regenerated debug.keystore is the usual cause, '
            'and it is per-machine - so this can be true for one developer and '
            'false for everyone else.',
      );
    },
  );

  test('the hosting deploy cannot exclude the .well-known directory', () {
    final hosting =
        (jsonDecode(_read(_hostingPath)) as Map<String, Object?>)['hosting']!
            as Map<String, Object?>;
    final ignored = <String>[
      for (final value in hosting['ignore']! as List<Object?>) value! as String,
    ];

    for (final glob in ignored) {
      expect(
        glob,
        isNot(matches(RegExp(r'(^|/)\*{0,2}\.\*?$|\.well-known'))),
        reason:
            'The ignore glob "$glob" would keep .well-known/ out of the '
            'deploy. This exact regression is already recorded in '
            "$_hostingPath's own comment: the file 404s, Android silently "
            'declines to verify, and every emailed link opens a browser.',
      );
    }
    expect(
      hosting['public'],
      'public',
      reason: '$_assetlinksPath is only deployed if public/ is the root.',
    );
    expect(
      hosting['cleanUrls'],
      isTrue,
      reason:
          'The filter paths carry no .html, so /auth/verified only resolves '
          'to auth/verified.html with cleanUrls on. Without it the redirect '
          '404s before the App Link is ever reached.',
    );
  });

  test('every emailed link lands on a path a filter claims', () {
    final parameters = _deployedParameters();
    final filters = _autoVerifyFilters();

    for (final name in _appBoundContinueUrls) {
      final value = parameters[name];
      expect(
        value,
        isNotNull,
        reason: '$_deployedEnvPath does not set $name, so the deploy prompts.',
      );
      final url = Uri.parse(value!);
      expect(
        url.scheme,
        'https',
        reason: 'Firebase Auth refuses a non-HTTPS continue URL outright.',
      );
      expect(
        filters.any((_LinkFilter filter) => filter.covers(url)),
        isTrue,
        reason:
            '$name is $value, which no autoVerify filter in $_manifestPath '
            'claims. The email is delivered and the link works - in a '
            'browser. Nothing reports that the app was skipped.',
      );
    }
  });

  test('a device without the app installed still has a page to read', () {
    for (final filter in _autoVerifyFilters()) {
      for (final path in filter.paths) {
        expect(
          File('public$path.html').existsSync(),
          isTrue,
          reason:
              'public$path.html is missing. An App Link is a shortcut, not the '
              'mechanism: the same URL is followed on a laptop, on a phone '
              'without the app, and whenever Android declines to verify - and '
              'every one of those reads this page instead.',
        );
      }
    }
  });
}
