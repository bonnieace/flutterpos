/// A disposable diagnostic: print the receipt's own line widths, on screen.
///
/// **The paper was the wrong instrument.** A ruler measures what the printer can
/// draw; it cannot say how wide the bytes we sent actually are. If a receipt
/// loses its last character on a printer that demonstrably prints 48 columns,
/// the line is 49 columns and the overflow wraps - so the thing to measure is
/// the payload.
///
///   flutter test tool/printer_payload_dump.dart
///
/// Prints one row per printed line: the visible text and its length in
/// characters, for both roll widths. Anything longer than its roll's column
/// count is a defect, and the number tells you by how much.
///
/// Nothing is sent anywhere. This opens no socket.
library;

import 'dart:io';

import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/tenancy/tenant_session.dart';
import 'package:flutter_application_1/tenancy/tenant_types.dart';
import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart'
    show CapabilityProfile;
import 'package:flutter_test/flutter_test.dart';

/// Splits ESC/POS bytes into the lines a printer would draw.
///
/// **Control sequences are skipped by their own length, not guessed at.** Only
/// the commands `CheckoutReceiptBody` actually emits are handled; anything else
/// is reported rather than silently dropped, because a diagnostic that quietly
/// mis-parses is worse than none.
/// The exact byte length of each control sequence this library emits.
///
/// Read off `flutter_esc_pos_utils/src/commands.dart` rather than guessed:
/// `ESC @` is two, `ESC $ nL nH` is four, and the rest are three. A parser that
/// guesses reports an off-by-one that belongs to the parser, which is how the
/// first version of this tool sent me looking for a right margin that was not
/// there.
int _sequenceLength(int lead, int command) {
  if (lead == 0x1B) {
    if (command == 0x40) return 2; // ESC @   initialise
    if (command == 0x24) return 4; // ESC $   absolute position, nL nH
    if (command == 0x32) return 2; // ESC 2   default line spacing
    return 3; //                      ESC a/E/M/d/t/!/-/3 + one parameter
  }
  if (lead == 0x1D) return 3; //      GS !/V/B + one parameter
  if (lead == 0x1C) return 2; //      FS &/.   Kanji on/off
  return 1;
}

/// Splits ESC/POS bytes into the lines a printer would draw, and reports the
/// absolute position each line was told to start at.
List<String> printableLines(List<int> bytes) {
  final lines = <String>[];
  final current = StringBuffer();
  var i = 0;
  while (i < bytes.length) {
    final byte = bytes[i];
    if (byte == 0x0A) {
      lines.add(current.toString());
      current.clear();
      i++;
      continue;
    }
    if (byte == 0x1B || byte == 0x1D || byte == 0x1C) {
      final command = i + 1 < bytes.length ? bytes[i + 1] : 0;
      // An absolute position is layout, so it is shown rather than dropped.
      if (byte == 0x1B && command == 0x24 && i + 3 < bytes.length) {
        final dots = bytes[i + 2] + (bytes[i + 3] << 8);
        current.write('<@$dots>');
      }
      i += _sequenceLength(byte, command);
      continue;
    }
    if (byte < 0x20) {
      i++;
      continue;
    }
    current.writeCharCode(byte);
    i++;
  }
  if (current.isNotEmpty) lines.add(current.toString());
  return lines;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reports every printed line width for both rolls', () async {
    final profile = await CapabilityProfile.load();
    for (final width in PrinterPaperWidth.values) {
      final body = CheckoutReceiptBody(
        profile: profile,
        configuration: TenantPrinterConfiguration(
          transport: PrinterTransportKind.directTcp,
          endpoint: PrinterEndpoint(host: '192.168.100.20', port: 9100),
          paperWidth: width,
          hasCutter: false,
        ),
      );
      final bytes = body.build(
        _sale(),
        businessName: 'Mugumo Stores',
        servedBy: 'Wanjiku',
      );
      stdout.writeln('');
      stdout.writeln('=== ${width.columns} columns ===');
      var over = 0;
      for (final line in printableLines(bytes)) {
        // The `<@N>` markers are this tool's own annotation and are not printed,
        // so they must not count towards the width being judged.
        final length = line.replaceAll(RegExp(r'<@\d+>'), '').length;
        final flag = length > width.columns
            ? '  <-- OVER by ${length - width.columns}'
            : '';
        if (length > width.columns) over++;
        stdout.writeln('${length.toString().padLeft(3)} |$line|$flag');
      }
      stdout.writeln('lines wider than the roll: $over');
    }
  });
}

/// The same fixture `printer_receipt_smoke.dart` prints.
CheckoutSalePayload _sale() {
  const deviceId = 'dev-0123456789abcdef0123456789abcdef';
  final lines = <Object?>[
    <String, Object?>{
      'productId': 'product-a',
      'name': 'Maize flour 2kg',
      'quantity': 2,
      'unitPriceMinor': 13550,
    },
    <String, Object?>{
      'productId': 'product-b',
      'name': 'Sugar 1kg',
      'quantity': 1,
      'unitPriceMinor': 13500,
    },
  ];
  const subtotalMinor = 2 * 13550 + 13500;
  const discountMinor = 2000;
  final payload = <String, Object?>{
    'schemaVersion': checkoutSalePayloadSchemaVersion,
    'checkoutId': 'checkout-dump',
    'tenantId': 'tenant-a',
    'soldById': 'user-a',
    'currency': 'KES',
    'businessDate': '2026-08-18',
    'createdAtMs': DateTime.utc(2026, 8, 18, 8).millisecondsSinceEpoch,
    'shiftId': 'shift-a',
    'deviceId': deviceId,
    'receiptNumber': formatCheckoutReceiptNumber(
      deviceId: deviceId,
      businessDate: '2026-08-18',
      sequence: 42,
    ),
    'receiptSequence': 42,
    'tender': 'cash',
    'items': lines,
    'subtotalMinor': subtotalMinor,
    'discountMinor': discountMinor,
    'totalMinor': subtotalMinor - discountMinor,
  };
  return CheckoutSalePayload.fromLocalPayload(
    session: TenantSession.active(
      uid: 'user-a',
      tenantId: 'tenant-a',
      role: TenantRole.cashier,
    ),
    checkoutId: 'checkout-dump',
    payload: payload,
    payloadHash: checkoutPayloadHash(payload),
  );
}
