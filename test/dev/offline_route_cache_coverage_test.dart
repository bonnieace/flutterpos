import 'dart:io' show Directory, File;

import 'package:flutter_test/flutter_test.dart';

final RegExp _directive = RegExp(
  r'^\s*(?:import|export|part)\s+[^;]*;',
  multiLine: true,
);
final RegExp _uri = RegExp(r"'([^']+\.dart)'");

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
  test('reachable guarded read surfaces declare a cached loader', () {
    final reachable = _reachable(_libraries());

    // These guards already load exclusively from durable device state; they do
    // not own a live/cache reader pair. Adding a new exception here requires an
    // explicit review instead of silently permitting another network gate.
    const deviceOnlyGuards = <String>{
      'lib/checkout/checkout_cart_panel.dart',
      'lib/checkout/checkout_evidence.dart',
    };

    final guarded = <String>[];
    for (final file in reachable) {
      if (file == 'lib/tenancy/tenant_route_guard.dart') continue;
      final source = File(file).readAsStringSync();
      if (!source.contains('TenantRouteGuard<')) continue;
      guarded.add(file);
      if (deviceOnlyGuards.contains(file)) continue;
      expect(
        source,
        contains(RegExp(r'loadCached\s*:')),
        reason:
            '$file is a reachable guarded read surface but has no cached '
            'loader. Its live read must not block data already on the device.',
      );
    }

    expect(
      guarded,
      isNotEmpty,
      reason: 'The reachability scan matched nothing.',
    );
    expect(
      deviceOnlyGuards.difference(guarded.toSet()),
      isEmpty,
      reason: 'A device-only exception is no longer a reachable guarded route.',
    );
  });
}
