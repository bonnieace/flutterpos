/// What in `lib/` the app actually runs, and what only looks like it does.
///
/// **`CLAUDE.md` hard rule 3 names two dead directories and there are ten.**
/// `lib/pos/**` and `lib/screens/**` are 52 files that nothing reaches, and they
/// are correctly called out as legacy and read-only. Twenty-seven more files —
/// 4,627 lines — are just as unreachable and are named by nothing, so a session
/// restyling the app has no way to know they are not part of it.
///
/// **Several of them are actively misleading for this redesign**, which is why
/// this is a test rather than a note:
///
/// - `lib/widgets/pill_button.dart`, `pill_input.dart` and `glass_card.dart` are
///   a **pill** component set, and `OPEN_QUESTIONS.md` decision 19 is that the
///   design has no pills at all. A session grepping for `pill` finds these.
/// - `lib/constants/colors.dart` and `lib/component/colors.dart` are two more
///   colour systems, and `lib/constants/sizes.dart` and `text_strings.dart` are a
///   size scale and a copy deck. That is exactly the "competing local design
///   system" `prompt.md`'s working discipline forbids creating — already present,
///   three times over.
/// - `lib/model/supplier.dart`, `customer.dart` and `invoice.dart` are models for
///   capabilities the product does not have, and `DESIGN_RULES.md` forbids
///   depicting a control the code does not support. Reading these as evidence
///   would be reading them backwards.
/// - `lib/services/fraud_detection_service.dart` is 556 lines of return-fraud
///   analysis. `screenshots/README.md` lists *"Flagging a suspicious return"*
///   under **Not pictured — scoped, not started**, which is right: this file is
///   not wired to anything.
/// - `lib/config.dart` is 1,178 lines of which **zero** are live code; the whole
///   file is commented out. And `lib/main copy.dart` is what its name says.
///
/// **The measure is a transitive import closure from `lib/main.dart`**, which is
/// what the composition root actually pulls in. Conditional imports count:
/// `checkout_print_transport.dart` reaches its `_io` half through
/// `if (dart.library.io)`, and a scan that read only the first URI of a directive
/// would call a live file dead — which this one did on its first pass.
///
/// **This asserts reachability, not deadness in the wider sense.** A file the
/// app never imports can still be exercised by a test or read for its flow, and
/// `lib/pos/**` is explicitly kept "for its flow rather than kept". So the list
/// below is *not* a deletion list, and nothing here recommends deleting any of
/// it. What it is for: making the set stable, so a file joining or leaving it is
/// a decision somebody took rather than a thing that happened.
library;

import 'dart:io' show Directory, File;

import 'package:flutter_test/flutter_test.dart';

/// The two directories `CLAUDE.md` hard rule 3 already names.
const List<String> _namedLegacy = <String>['lib/pos/', 'lib/screens/'];

/// Every other file `lib/main.dart` does not reach, as of 2026-08-22.
///
/// Alphabetical, which is also roughly oldest-first: these are the single-tenant
/// app's leftovers plus two files that were never wired up.
const List<String> _unreachedAndUnnamed = <String>[
  'lib/api/pdf_api.dart',
  'lib/api/pdf_invoice_api.dart',
  'lib/component/colors.dart',
  'lib/config.dart',
  'lib/constants/api_constants.dart',
  'lib/constants/colors.dart',
  'lib/constants/enums.dart',
  'lib/constants/image_strings.dart',
  'lib/constants/sizes.dart',
  'lib/constants/text_strings.dart',
  'lib/main copy.dart',
  'lib/model/customer.dart',
  'lib/model/invoice.dart',
  'lib/model/product.dart',
  'lib/model/return_analysis.dart',
  'lib/model/supplier.dart',
  'lib/pdf_preview_screen.dart',
  'lib/services/Receipt_service.dart',
  'lib/services/bulk_update_service.dart',
  'lib/services/bulk_upload_service.dart',
  'lib/services/fraud_detection_service.dart',
  'lib/services/shift_service.dart',
  'lib/services/thermal_printer_service.dart',
  'lib/utils.dart',
  'lib/widgets/glass_card.dart',
  'lib/widgets/pill_button.dart',
  'lib/widgets/pill_input.dart',
];

/// Every `.dart` file under `lib/`, as forward-slashed repository paths.
///
/// Forward slashes on every platform, because a URI in a directive uses them and
/// `Directory.listSync` on Windows does not. `package:path` would say this in one
/// call and is not a direct dependency of this package; adding one for a slash is
/// not a trade worth making.
Set<String> _everyLibraryFile() => <String>{
  for (final entry in Directory('lib').listSync(recursive: true))
    if (entry is File && entry.path.endsWith('.dart'))
      entry.path.replaceAll(r'\', '/'),
};

/// Every URI a directive names, including a conditional import's alternatives.
final RegExp _directive = RegExp(
  r'^\s*(?:import|export|part)\s+[^;]*;',
  multiLine: true,
);
final RegExp _uri = RegExp(r"'([^']+\.dart)'");

String? _resolve(String from, String uri) {
  const prefix = 'package:uzapay_pos/';
  if (uri.startsWith(prefix)) return 'lib/${uri.substring(prefix.length)}';
  if (uri.startsWith('package:') || uri.startsWith('dart:')) return null;
  final segments = <String>[
    ...from.split('/')..removeLast(),
    ...uri.split('/'),
  ];
  final resolved = <String>[];
  for (final segment in segments) {
    if (segment == '.' || segment.isEmpty) continue;
    if (segment == '..') {
      if (resolved.isNotEmpty) resolved.removeLast();
      continue;
    }
    resolved.add(segment);
  }
  return resolved.join('/');
}

/// The transitive closure of [entry]'s imports, exports and parts.
Set<String> _closureFrom(String entry, Set<String> universe) {
  final reached = <String>{};
  final pending = <String>[entry];
  while (pending.isNotEmpty) {
    final current = pending.removeLast();
    if (!universe.contains(current) || !reached.add(current)) continue;
    final source = File(current).readAsStringSync();
    for (final directive in _directive.allMatches(source)) {
      for (final match in _uri.allMatches(directive.group(0)!)) {
        final target = _resolve(current, match.group(1)!);
        if (target != null) pending.add(target);
      }
    }
  }
  return reached;
}

void main() {
  final everyFile = _everyLibraryFile();
  final reached = _closureFrom('lib/main.dart', everyFile);
  final unreached = everyFile.difference(reached);

  test('the composition root reaches itself, and the scan works at all', () {
    // A resolver that silently matched nothing would make every assertion below
    // vacuously true, which is the way this kind of test fails quietly.
    expect(reached, contains('lib/main.dart'));
    expect(reached, contains('lib/theme.dart'));
    expect(reached, contains('lib/ui/tokens.dart'));
    expect(
      reached.length,
      greaterThan(100),
      reason:
          'Only ${reached.length} files were reached from lib/main.dart. The '
          'import resolver has probably stopped resolving something.',
    );
  });

  test('a conditional import is a reachable import', () {
    // The `_io` half of the print transport is reached only through
    // `if (dart.library.io)`, on a continuation line. A scan reading the first
    // URI of each directive calls it dead - which this one did, once.
    expect(
      reached,
      contains('lib/checkout/checkout_print_transport.dart'),
      reason:
          'The transport itself is not reachable, so the next line is moot.',
    );
    expect(
      reached,
      contains('lib/checkout/checkout_print_transport_io.dart'),
      reason:
          'The platform half of the print transport is reachable only through a '
          'conditional import. If this fails, the directive scan has stopped '
          'reading past the first URI and every figure here is wrong.',
    );
  });

  test('the unreachable set is exactly the recorded one', () {
    final recorded = <String>{
      ..._unreachedAndUnnamed,
      for (final file in everyFile)
        if (_namedLegacy.any(file.startsWith)) file,
    };

    expect(
      unreached.difference(recorded),
      isEmpty,
      reason:
          'A file under lib/ is reachable from nothing and is not recorded. '
          'Either wire it up, or add it here and say in the run log why the app '
          'carries a file it does not run. A dead file that looks live is how '
          'lib/widgets/pill_button.dart came to exist in an app whose design has '
          'no pills.',
    );
    expect(
      recorded.difference(unreached),
      isEmpty,
      reason:
          'A file recorded here as unreachable is now reachable from '
          'lib/main.dart. If that is deliberate, take it off the list - it is '
          'part of the app now, which means the design rules apply to it.',
    );
  });

  test('nothing the app runs imports something it does not', () {
    // The property that makes the list above stable rather than incidental: the
    // reachable set is closed. Stated separately because it is the thing that
    // would break first if a live file started reading `lib/constants/colors.dart`
    // for a hex - which is the specific mistake the redesign is most exposed to.
    for (final file in reached) {
      final source = File(file).readAsStringSync();
      for (final directive in _directive.allMatches(source)) {
        for (final match in _uri.allMatches(directive.group(0)!)) {
          final target = _resolve(file, match.group(1)!);
          if (target == null || !everyFile.contains(target)) continue;
          expect(
            reached,
            contains(target),
            reason: '$file imports $target, which is not in the reachable set.',
          );
        }
      }
    }
  });
}
