/// A disposable diagnostic: measure the generator's primitives, one at a time.
///
/// **Parsing a whole ESC/POS stream to count columns does not work** — the skip
/// length of a control sequence varies per command, and a parser that guesses
/// wrong reports an off-by-one that belongs to the parser. So this measures each
/// primitive on its own, where the printable bytes are unambiguous: emit exactly
/// one call, count the bytes at or above 0x20, and print the count.
///
///   flutter test tool/printer_row_probe.dart
///
/// What it answers: is `hr()` the roll's width, and is a `row()` of label plus
/// right-aligned value the roll's width — or one more than it?
///
/// Nothing is sent anywhere.
library;

import 'dart:io';

import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';
import 'package:flutter_test/flutter_test.dart';

int printable(List<int> bytes) => bytes.where((b) => b >= 0x20).length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('measures hr and row against the roll width', () async {
    final profile = await CapabilityProfile.load();
    for (final entry in <String, PaperSize>{
      'mm58 (32 columns)': PaperSize.mm58,
      'mm80 (48 columns)': PaperSize.mm80,
    }.entries) {
      final generator = Generator(entry.value, profile);
      stdout.writeln('');
      stdout.writeln('=== ${entry.key} ===');

      stdout.writeln('hr()                       ${printable(generator.hr())}');
      stdout.writeln(
        'text("A")                  ${printable(generator.text("A"))}',
      );
      stdout.writeln(
        'text right-aligned         '
        '${printable(generator.text("KES 271.00", styles: const PosStyles(align: PosAlign.right)))}',
      );

      final labelled = generator.row(<PosColumn>[
        PosColumn(text: 'Receipt', width: 4),
        PosColumn(
          text: 'CT-8F8-20260818-0042',
          width: 8,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
      stdout.writeln('row(4 + 8)                 ${printable(labelled)}');

      final amount = generator.row(<PosColumn>[
        PosColumn(text: 'Subtotal', width: 5),
        PosColumn(
          text: 'KES 406.00',
          width: 7,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
      stdout.writeln('row(5 + 7)                 ${printable(amount)}');
    }
  });
}
