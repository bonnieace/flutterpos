/// Rewrites the navigation index in `PLAN.md` and `HISTORY.md`.
///
/// Run after editing either file:
///
/// ```
/// dart run tool/doc_index.dart
/// ```
///
/// Each index carries a **line number** per heading, because that is what makes
/// it cheap to use: a reader opens the one section it needs rather than the
/// whole file. `HISTORY.md` is 20,000-plus lines and is append-only, so its
/// line numbers are stable once written — which is the property this index
/// depends on and the reason regenerating it after an append is not optional.
///
/// It only ever rewrites the region between the two markers, so where an index
/// sits in its file is authored once, by hand, and never by this script. A file
/// with no markers is left untouched and reported.
///
/// Inserting the index shifts every line below it, so the numbers are solved
/// rather than measured: build, place, re-measure, repeat until nothing moves.
library;

import 'dart:io';

const String _start = '<!-- index:start -->';
const String _end = '<!-- index:end -->';

/// How deep each file's index goes, and what it calls itself.
const Map<String, ({int depth, String caption})> _indexes =
    <String, ({int depth, String caption})>{
      'PLAN.md': (
        depth: 3,
        caption:
            'Every section of this file, with the line it starts on. '
            'Read the one you need.',
      ),
      'HISTORY.md': (
        depth: 2,
        caption:
            'Every session, newest last, with the line it starts on. '
            'Read the one a standing decision points at; never the file.',
      ),
    };

void main() {
  for (final MapEntry<String, ({int depth, String caption})> entry
      in _indexes.entries) {
    final File file = File(entry.key);
    if (!file.existsSync()) {
      stderr.writeln('${entry.key}: not found, skipped.');
      continue;
    }

    // Accept both repository LF files and Windows CRLF working copies. A
    // literal `split('\n')` leaves `\r` on every marker line and makes an
    // existing index look absent on Windows.
    final List<String> lines = file.readAsStringSync().split(RegExp(r'\r?\n'));
    final int startAt = lines.indexOf(_start);
    final int endAt = lines.indexOf(_end);
    if (startAt < 0 || endAt < 0 || endAt < startAt) {
      stderr.writeln(
        '${entry.key}: no index markers, skipped. Add $_start and $_end '
        'where the index belongs.',
      );
      continue;
    }

    final List<String> rewritten = _solve(
      lines,
      startAt: startAt,
      endAt: endAt,
      depth: entry.value.depth,
      caption: entry.value.caption,
    );
    file.writeAsStringSync(rewritten.join('\n'));
    stdout.writeln(
      '${entry.key}: ${_headings(rewritten, entry.value.depth).length} '
      'headings indexed.',
    );
  }
}

/// The index shifts the lines it names, so build it against its own output
/// until the numbers stop moving. Two passes are enough in practice; the bound
/// is here so a file that somehow oscillates fails loudly rather than hanging.
List<String> _solve(
  List<String> lines, {
  required int startAt,
  required int endAt,
  required int depth,
  required String caption,
}) {
  List<String> current = <String>[
    ...lines.sublist(0, startAt + 1),
    ...lines.sublist(endAt),
  ];
  int markerAt = startAt;

  for (int pass = 0; pass < 8; pass++) {
    final List<String> block = _render(_headings(current, depth), caption);
    final List<String> next = <String>[
      ...current.sublist(0, markerAt + 1),
      ...block,
      ...current.sublist(current.indexOf(_end)),
    ];
    if (_sameIndex(current, next)) return next;
    current = next;
  }
  throw StateError('The index did not settle in 8 passes.');
}

bool _sameIndex(List<String> a, List<String> b) {
  final int aStart = a.indexOf(_start);
  final int bStart = b.indexOf(_start);
  return a.sublist(aStart, a.indexOf(_end) + 1).join('\n') ==
      b.sublist(bStart, b.indexOf(_end) + 1).join('\n');
}

/// Every heading at or above [depth], with the 1-based line it sits on.
/// Fenced code is skipped, because a `#` inside a block is not a heading.
List<({int level, String text, int line})> _headings(
  List<String> lines,
  int depth,
) {
  final List<({int level, String text, int line})> found =
      <({int level, String text, int line})>[];
  bool fenced = false;

  for (int i = 0; i < lines.length; i++) {
    final String line = lines[i];
    if (line.startsWith('```')) {
      fenced = !fenced;
      continue;
    }
    if (fenced) continue;

    final Match? match = RegExp(r'^(#{2,6}) +(.+?) *$').firstMatch(line);
    if (match == null) continue;
    final int level = match.group(1)!.length;
    if (level > depth) continue;
    found.add((level: level, text: match.group(2)!, line: i + 1));
  }
  return found;
}

List<String> _render(
  List<({int level, String text, int line})> headings,
  String caption,
) {
  final List<String> block = <String>['', caption, ''];
  for (final ({int level, String text, int line}) heading in headings) {
    final String indent = '  ' * (heading.level - 2);
    block.add('$indent- **${heading.line}** — ${heading.text}');
  }
  block.add('');
  return block;
}
