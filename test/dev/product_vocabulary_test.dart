/// Words the app must not say, because the product cannot do the thing they name.
///
/// **This exists because the designs about to be implemented carry some of
/// them.** `LIVE_PHASE_HANDOFF.md` records that ST-048 shows a `Ceramic Mug`,
/// a `Tax (16%)` line and refund figures; ST-039 shows a `Before/After` column.
/// `prompt.md` is explicit that those are *"corrections, not fidelity targets"* —
/// but Wave 1 and Wave 2 are the waves that compose those exact screens, and the
/// most ordinary way an invented fact enters an app is a fixture copied out of a
/// mockup while somebody is concentrating on the layout.
///
/// So this is a scan of the app's own copy and of every fixture behind it. It is
/// the counterpart to `DESIGN_RULES.md`'s truthfulness section, which states the
/// rule and can only be obeyed by remembering it.
///
/// **The list is deliberately short, and each entry has to be unambiguous.**
/// Half the obvious candidates cannot be scanned for at all, because the app
/// already uses them *correctly, as negations*:
/// `checkout_tender.dart` says "the payment itself is not verified",
/// `sales_totals_panel.dart` says "the payment is unverified", and
/// `shift_panel.dart` calls *Cancel cash count* a reversal. A scan for
/// `verified payment` or `reversal` would flag four sentences that are right, and
/// a tripwire that cries wolf is worse than none — it teaches the next person to
/// pass `--plain-name` around it. Those rules stay prose in `DESIGN_RULES.md`,
/// enforced by review, and this file only holds what a machine can be sure about.
///
/// **Comments are stripped before scanning**, so a file can explain why a word is
/// forbidden — as this one does, and as `RBAC_MATRIX.md`'s quotation of the
/// invented role names does inside `rbac_matrix_test.dart`.
///
/// **Scope: the app the composition root actually reaches, plus every fixture.**
/// The ten unreachable locations are excluded, and that is not a loophole — it is
/// the point. `lib/services/fraud_detection_service.dart` genuinely says `refund`
/// and `Ksh`, `lib/model/supplier.dart` genuinely models suppliers, and none of
/// it runs. `test/dev/reachable_lib_test.dart` is what keeps that set from
/// growing quietly; this file only asks that nothing live joins it.
library;

import 'dart:io' show Directory, File;

import 'package:flutter_test/flutter_test.dart';

/// One forbidden token, and the document that forbids it.
typedef _Forbidden = ({String token, bool wholeWord, String because});

const List<_Forbidden> _forbidden = <_Forbidden>[
  (
    token: 'Kijani',
    wholeWord: false,
    because:
        'DESIGN_RULES.md: "Product name is Chilltent POS. Do not use Kijani '
        'POS or generic Operational Hub branding."',
  ),
  (
    token: 'Operational Hub',
    wholeWord: false,
    because: 'DESIGN_RULES.md forbids the generic branding by name.',
  ),
  (
    token: 'Senior Cashier',
    wholeWord: false,
    because:
        'RBAC_MATRIX.md: "Do not invent roles such as Senior Cashier or '
        'Inventory Clerk." There are four tenant roles and this is not one.',
  ),
  (
    token: 'Inventory Clerk',
    wholeWord: false,
    because: 'RBAC_MATRIX.md names this as the other invented role.',
  ),
  (
    token: 'VAT',
    wholeWord: true,
    because:
        'DESIGN_RULES.md: "The current product does not verify payment and does '
        'not collect VAT." A line item for it would be a figure no sale carries.',
  ),
  (
    token: 'Tax (',
    wholeWord: false,
    because:
        'The exact shape ST-048 shows - "Tax (16%)". LIVE_PHASE_HANDOFF.md '
        'records it as a design defect to correct, not a target to hit.',
  ),
  (
    token: 'Ceramic Mug',
    wholeWord: false,
    because:
        'ST-048 invents this product. The seeded catalog is in '
        'rules-tests/scripts/seed-dev-emulator.js and a fixture wanting a '
        'product should take one from there.',
  ),
  (
    token: 'Before/After',
    wholeWord: false,
    because:
        'ST-039 invents this column. LIVE_PHASE_HANDOFF.md lists it among the '
        'screens whose facts the code contradicts.',
  ),
];

/// The ten locations `test/dev/reachable_lib_test.dart` records as reachable from
/// nothing.
const List<String> _unreachable = <String>[
  'lib/pos/',
  'lib/screens/',
  'lib/api/',
  'lib/component/',
  'lib/constants/',
  'lib/model/',
  'lib/services/',
  'lib/widgets/',
  'lib/config.dart',
  'lib/main copy.dart',
  'lib/pdf_preview_screen.dart',
  'lib/utils.dart',
];

/// This file, which is the one place the forbidden words are allowed to appear.
///
/// **Not a loophole and not vanity: the table above holds them as string
/// literals**, and a literal is not a comment, so the first run of this scan
/// reported eight offences and every one of them was itself. A scan that cannot
/// name what it forbids would have to spell the words in fragments, which is
/// worse - the next reader could not grep for the rule that stopped them.
const String _thisFile = 'test/dev/product_vocabulary_test.dart';

/// Every Dart file whose words are the product's own.
Iterable<File> _filesUnderReview() {
  final files = <File>[];
  for (final root in const <String>['lib', 'test', 'tool']) {
    for (final entry in Directory(root).listSync(recursive: true)) {
      if (entry is! File || !entry.path.endsWith('.dart')) continue;
      final path = entry.path.replaceAll(r'\', '/');
      if (path == _thisFile) continue;
      if (_unreachable.any(path.startsWith)) continue;
      files.add(entry);
    }
  }
  return files;
}

/// [source] with `//` comments and `///` doc comments removed.
///
/// Line comments only. A `/* */` block would need real lexing to strip safely,
/// and this repository does not use them — `flutter analyze` is clean and the
/// style throughout is `///` and `//`.
String _withoutComments(String source) => source
    .split(RegExp(r'\r?\n'))
    .map((line) {
      final at = line.indexOf('//');
      return at < 0 ? line : line.substring(0, at);
    })
    .join('\n');

void main() {
  test('the scan reads real files, so a green run means something', () {
    final files = _filesUnderReview().toList();
    expect(
      files.length,
      greaterThan(200),
      reason:
          'Only ${files.length} files were opened. Either the exclusions have '
          'swallowed the app, or listSync stopped recursing.',
    );
    // Two files that must always be in scope, one app and one fixture.
    final paths = files.map((f) => f.path.replaceAll(r'\', '/')).toSet();
    expect(paths, contains('lib/ui/states.dart'));
    expect(paths, contains('tool/screenshots/fakes.dart'));
  });

  for (final entry in _forbidden) {
    test('nothing live says "${entry.token}"', () {
      final pattern = entry.wholeWord
          ? RegExp('\\b${RegExp.escape(entry.token)}\\b')
          : RegExp(RegExp.escape(entry.token));

      final offenders = <String>[];
      for (final file in _filesUnderReview()) {
        final path = file.path.replaceAll(r'\', '/');
        final lines = _withoutComments(
          file.readAsStringSync(),
        ).split(RegExp(r'\r?\n'));
        for (var index = 0; index < lines.length; index++) {
          if (pattern.hasMatch(lines[index])) {
            offenders.add('$path:${index + 1}');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            '"${entry.token}" appears at ${offenders.join(', ')}.\n'
            '${entry.because}\n'
            'If the product genuinely gained this capability, the rule moves '
            'first: DESIGN_RULES.md and RBAC_MATRIX.md are the documents to '
            'change, and this entry comes out with them.',
      );
    });
  }
}
