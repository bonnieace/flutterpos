import 'dart:io' show Directory, File;

import 'package:flutter_test/flutter_test.dart';

final RegExp _directive = RegExp(
  r'^\s*(?:import|export|part)\s+[^;]*;',
  multiLine: true,
);
final RegExp _uri = RegExp(r"'([^']+\.dart)'");

/// A `key:` argument on a `TenantRouteGuard`, past any comment explaining it.
final RegExp _keyedGuard = RegExp(
  r'TenantRouteGuard<[^\n]*\(\s*\n(?:\s*//[^\n]*\n)*\s*key:\s*ValueKey',
  multiLine: true,
);

Set<String> _libraries() => <String>{
  for (final entry in Directory('lib').listSync(recursive: true))
    if (entry is File && entry.path.endsWith('.dart'))
      entry.path.replaceAll(r'\', '/'),
};

String? _resolve(String from, String uri) {
  const packagePrefix = 'package:flutter_application_1/';
  if (uri.startsWith(packagePrefix)) {
    return 'lib/${uri.substring(packagePrefix.length)}';
  }
  if (uri.startsWith('package:') || uri.startsWith('dart:')) return null;
  final parts = <String>[...from.split('/')..removeLast(), ...uri.split('/')];
  final resolved = <String>[];
  for (final part in parts) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (resolved.isNotEmpty) resolved.removeLast();
    } else {
      resolved.add(part);
    }
  }
  return resolved.join('/');
}

Set<String> _reachable(Set<String> libraries) {
  final found = <String>{};
  final pending = <String>['lib/main.dart'];
  while (pending.isNotEmpty) {
    final file = pending.removeLast();
    if (!libraries.contains(file) || !found.add(file)) continue;
    final source = File(file).readAsStringSync();
    for (final directive in _directive.allMatches(source)) {
      for (final uri in _uri.allMatches(directive.group(0)!)) {
        final target = _resolve(file, uri.group(1)!);
        if (target != null) pending.add(target);
      }
    }
  }
  return found;
}

void main() {
  test('no reachable guarded route re-keys its guard on a filter', () {
    final reachable = _reachable(_libraries());

    // **The two record lookups, and only those.** A guard whose *subject*
    // changes within one instance has to be re-keyed: showing the previous
    // receipt while the next one is looked up states the wrong sale, which is
    // a different thing from being a moment behind. Every other guard is a
    // list, a report or a form whose subject is fixed for the life of the
    // route, and re-keying one of those throws away data the device is holding
    // to run a read that usually takes a few hundred milliseconds.
    //
    // Adding a name here needs the same argument made about it, in writing, at
    // the call site. It is not a way to opt out of the retention.
    const subjectChangesInPlace = <String>{
      'lib/sales/receipt_lookup_panel.dart',
      'lib/sales/sales_report_panel.dart',
    };

    final keyed = <String>[];
    for (final file in reachable) {
      if (file == 'lib/tenancy/tenant_route_guard.dart') continue;
      final source = File(file).readAsStringSync();
      if (!_keyedGuard.hasMatch(source)) continue;
      keyed.add(file);
    }

    expect(
      keyed.toSet().difference(subjectChangesInPlace),
      isEmpty,
      reason:
          'A reachable guarded route puts its filter, page or generation in a '
          'ValueKey on the guard. That destroys the guard State and blanks the '
          'page for the length of the read. Memoise the loader instead - see '
          '`_composeLoaders` in lib/inventory/catalog_management_panel.dart - '
          'and let the guard notice the changed `load`.',
    );
    expect(
      subjectChangesInPlace.difference(keyed.toSet()),
      isEmpty,
      reason:
          'A named exception no longer keys its guard. Remove it from this '
          'list rather than leaving a stale exemption behind.',
    );
  });
}
