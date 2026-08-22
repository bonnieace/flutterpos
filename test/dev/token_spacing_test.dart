/// Hard rule 2, for spacing, as a tripwire rather than a coincidence.
///
/// **Every colour, size, radius, spacing, duration and spring comes from the
/// token layer**, and `CLAUDE.md` says a magic number in a widget is a defect
/// whether or not it looks right. Spacing was the last of those still written as
/// literals: 97 sites in `lib/inventory/`, 39 across the staff surfaces, and 92
/// more everywhere else. They are all gone, and this is what stops them coming
/// back one convenient `SizedBox(height: 12)` at a time.
///
/// It scans source rather than rendering, for the reason
/// `product_vocabulary_test.dart` and `reachable_lib_test.dart` do: what is being
/// asserted is a property of the code, and no picture of a correct layout can
/// tell you whether the number behind it came from a role or from a keystroke.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A literal spacing in a widget: `SizedBox(height: 12)`, `EdgeInsets.all(20)`.
///
/// Deliberately narrow. It matches the two constructors that carry essentially
/// all of this app's spacing and nothing else, because a scan that also flagged
/// `Size(48, 48)`, `width: 420` and every `elevation: 0` would be a scan people
/// silence rather than obey.
final RegExp _literalSpacing = RegExp(
  r'\bSizedBox\((?:width|height): \d'
  r'|\bEdgeInsets\.(?:all|symmetric|only|fromLTRB)\((?:[a-z]+: )?\d',
);

/// A line that is only a comment, which is exempt.
///
/// Several files *document* a spacing that used to be there - the pill the
/// product owner asked for, the `SizedBox(width: 440)` a dialog no longer has -
/// and that prose is history rather than a defect.
final RegExp _commentLine = RegExp(r'^\s*(//|\*|/\*)');

/// The parts of `lib/` this rule does not reach, and why each is out.
const Map<String, String> _exempt = <String, String>{
  // `test/dev/reachable_lib_test.dart` holds the full list and the argument.
  // Nothing imports these, so nothing renders them.
  'lib/pos/': 'legacy, unreachable, read-only',
  'lib/screens/': 'legacy, unreachable, read-only',
  'lib/widgets/': 'the unreachable pill component set',
  'lib/constants/': 'unreachable constants',
  'lib/component/': 'a rival colour system, unreachable',
  'lib/model/': 'unreachable models',
  'lib/api/': 'unreachable',
  'lib/services/': 'unreachable',
  'lib/config.dart': '1,178 lines of which zero are live code',
  'lib/main copy.dart': 'what its name says',
  'lib/pdf_preview_screen.dart': 'unreachable',
  // **The one genuine exemption, and it is the point rather than a hole.**
  // `AppSpacing` *is* the scale, and `AppDensity`'s two `rowPadding` values are
  // the token layer stating its own numbers. A layer that had to read itself
  // from somewhere else would have nowhere to bottom out.
  'lib/ui/tokens.dart': 'the token layer defines the scale',
};

void main() {
  test('no widget in the reachable tree writes a spacing as a number', () {
    final offenders = <String>[];

    for (final entry in Directory('lib').listSync(recursive: true)) {
      if (entry is! File || !entry.path.endsWith('.dart')) continue;
      final path = entry.path.replaceAll(r'\', '/');
      if (_exempt.keys.any(path.startsWith)) continue;

      final lines = entry.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (_commentLine.hasMatch(line)) continue;
        if (!_literalSpacing.hasMatch(line)) continue;
        offenders.add('$path:${i + 1}  ${line.trim()}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Hard rule 2: every spacing comes from the token layer. Each line '
          'below writes one as a number.\n\n'
          '${offenders.join('\n')}\n\n'
          'Use `tokens.spacing.sN` - the scale is 4, 8, 12, 16, 20, 24, 32, '
          '40, 48, 64 and `AppSpacing.all` is the whole of it. A value not on '
          'that list is not a spacing: pick the neighbour the same gap already '
          'uses elsewhere and say so in the commit, which is what the three '
          'off-scale values found so far each got. Two mechanical notes, both '
          'paid for: an expression-bodied `build` has no `tokens` in scope and '
          'needs a block body, and `const Padding(padding: '
          'EdgeInsets.all(token))` does not compile because a token is not a '
          'compile-time constant - move the `const` to the child.',
    );
  });

  test('the exemptions are all real paths, so the list cannot rot', () {
    // An exemption naming a file that no longer exists is a hole nobody can
    // see. This is the same guard `reachable_lib_test.dart` keeps on its own
    // list.
    for (final path in _exempt.keys) {
      final exists = path.endsWith('/')
          ? Directory(path).existsSync()
          : File(path).existsSync();
      expect(
        exists,
        isTrue,
        reason: '$path is exempt from the spacing rule and does not exist',
      );
    }
  });
}
