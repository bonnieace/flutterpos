import 'dart:convert';
import 'dart:typed_data';

import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// `ESC t` — the code-page selector. Present here for the same reason it is on
/// a receipt: a shop's own name is on this page too.
const List<int> _escT = <int>[0x1B, 0x74];

/// `GS v 0` — the raster image command. The mark is the one thing this page
/// prints that a receipt never does.
const List<int> _gsV0 = <int>[0x1D, 0x76, 0x30];

/// `GS V` — the cutter.
const List<int> _gsV = <int>[0x1D, 0x56];

void main() {
  // `CapabilityProfile.load` reads a package asset through `rootBundle`.
  TestWidgetsFlutterBinding.ensureInitialized();

  late CapabilityProfile profile;

  setUpAll(() async {
    profile = await CapabilityProfile.load();
  });

  CheckoutPrinterTestPage page({
    PrinterPaperWidth width = PrinterPaperWidth.columns32,
    bool hasCutter = true,
    String host = '192.168.1.50',
  }) => CheckoutPrinterTestPage(
    profile: profile,
    configuration: TenantPrinterConfiguration(
      transport: PrinterTransportKind.directTcp,
      endpoint: PrinterEndpoint(host: host, port: 9100),
      paperWidth: width,
      hasCutter: hasCutter,
    ),
  );

  final at = DateTime(2026, 9, 3, 15, 51);

  /// Every printed line, as the paper reads it.
  ///
  /// **Two things have to come off first, and neither can be filtered by
  /// character class.** The mark is raster data - arbitrary bytes, line feeds
  /// and printable codes among them - so it is stepped over by the dimensions
  /// `GS v 0` states rather than by guessing where it ends. And every line the
  /// generator writes is *commands then text*: `ESC $`, `ESC !`, `ESC t` and
  /// their parameters, whose command letters are printable and would otherwise
  /// be counted as part of a row. The text is whatever follows the last
  /// control byte on the line.
  List<String> lines(List<int> bytes) {
    final rows = <String>[];
    for (final row in _split(_afterTheMark(bytes), 0x0A)) {
      var start = 0;
      for (var i = 0; i < row.length; i++) {
        if (row[i] < 0x20) start = i + 1;
      }
      rows.add(latin1.decode(row.sublist(start), allowInvalid: true));
    }
    return rows;
  }

  group('what proves the printer works', () {
    test('draws its mark as a raster image', () {
      // The one capability a receipt never exercises, and the first that a
      // printer with the wrong density setting gets wrong.
      expect(_contains(page().build(at: at), _gsV0), isTrue);
    });

    test('selects the code page before a character is printed', () {
      final bytes = page().build(at: at);
      final escT = _indexOf(bytes, _escT);
      final text = latin1.decode(bytes, allowInvalid: true).indexOf('PRINTER');
      expect(escT, isNonNegative);
      expect(escT, lessThan(text));
    });

    test('rules one whole row of the roll, and says which roll', () {
      for (final width in PrinterPaperWidth.values) {
        final ruler = lines(
          page(width: width).build(at: at),
        ).firstWhere((line) => line.startsWith('....'));
        expect(
          ruler.length,
          width.columns,
          reason: 'the ruler is the width claim; it must be exactly one row',
        );
        expect(ruler, endsWith('${width.columns}'));
      }
    });

    test('never writes a line longer than the roll', () {
      for (final width in PrinterPaperWidth.values) {
        for (final line in lines(page(width: width).build(at: at))) {
          expect(line.length, lessThanOrEqualTo(width.columns), reason: line);
        }
      }
    });
  });

  group('what it says', () {
    test('prints the settings it was given, so the paper carries them', () {
      final printed = lines(
        page(
          width: PrinterPaperWidth.columns48,
          host: '10.0.0.7',
        ).build(at: at),
      ).join('\n');
      expect(printed, contains('10.0.0.7:9100'));
      expect(printed, contains('80mm'));
      expect(printed, contains('Fitted'));
      expect(printed, contains('3 Sep 2026 15:51'));
    });

    test('says the cutter is absent rather than saying nothing', () {
      final printed = lines(page(hasCutter: false).build(at: at)).join('\n');
      expect(printed, contains('None'));
    });

    test('states that nothing was sold, because this is not a receipt', () {
      final printed = lines(page().build(at: at)).join('\n');
      expect(printed, contains('Nothing was sold'));
      expect(printed, isNot(contains('TOTAL')));
    });

    test('prints a name the printer cannot draw as one it can', () {
      // `ReceiptText.forPrinter`'s rule, and the same reason: the generator
      // throws on a character its codec cannot encode, so an unsubstituted
      // macron would fail the page rather than mis-print it.
      final printed = lines(
        page().build(at: at, businessName: 'Mũgumo Stores'),
      ).join('\n');
      expect(printed, contains('Mugumo Stores'));
    });

    test('leaves the name out entirely when there is none', () {
      final printed = lines(page().build(at: at, businessName: '   ')).join();
      expect(printed, isNot(contains('  \n')));
      expect(printed, contains('PRINTER TEST'));
    });
  });

  // **Headed as a receipt is, since 2026-09-23**: the published logo in place
  // of the test mark, then the brand name and the slogan.
  group('with the receipt branding', () {
    test('prints the published logo instead of the test mark', () {
      final logo = _png(width: 400, height: 400);
      final mark = receiptLogoMark(logo)!;
      final bytes = page().build(
        at: at,
        businessName: 'Chill Tent',
        logo: logo,
      );
      expect(_rasterWidthBytes(bytes), (mark.width + 7) ~/ 8);
    });

    test('falls back to the test mark when the logo does not decode', () {
      final plain = page().build(at: at);
      final broken = page().build(
        at: at,
        logo: Uint8List.fromList(<int>[1, 2, 3, 4]),
      );
      expect(_rasterWidthBytes(broken), _rasterWidthBytes(plain));
    });

    test('prints the slogan under the brand name', () {
      final printed = lines(
        page().build(
          at: at,
          businessName: 'Chill Tent',
          slogan: 'Cold drinks, warm welcome',
        ),
      );
      final name = printed.indexWhere((line) => line.contains('Chill Tent'));
      final slogan = printed.indexWhere(
        (line) => line.contains('Cold drinks, warm welcome'),
      );
      expect(name, isNonNegative);
      expect(slogan, greaterThan(name));
      expect(
        printed.indexWhere((line) => line.contains('PRINTER TEST')),
        greaterThan(slogan),
      );
    });
  });

  group('the end of the page', () {
    test('cuts where there is a cutter', () {
      expect(_contains(page().build(at: at), _gsV), isTrue);
    });

    test('feeds instead where there is not', () {
      expect(_contains(page(hasCutter: false).build(at: at), _gsV), isFalse);
    });
  });
}

/// [bytes] cut at every [separator].
List<List<int>> _split(List<int> bytes, int separator) {
  final out = <List<int>>[];
  var start = 0;
  for (var i = 0; i < bytes.length; i++) {
    if (bytes[i] != separator) continue;
    out.add(bytes.sublist(start, i));
    start = i + 1;
  }
  if (start < bytes.length) out.add(bytes.sublist(start));
  return out;
}

/// [bytes] from the end of the raster mark onwards.
List<int> _afterTheMark(List<int> bytes) {
  final start = _indexOf(bytes, _gsV0);
  if (start < 0) return bytes;
  // GS v 0 m xL xH yL yH, then xL/xH bytes for each of yL/yH rows.
  final header = start + _gsV0.length + 1;
  final widthBytes = bytes[header] + (bytes[header + 1] << 8);
  final height = bytes[header + 2] + (bytes[header + 3] << 8);
  return bytes.sublist(header + 4 + widthBytes * height);
}

int _indexOf(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var matched = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        matched = false;
        break;
      }
    }
    if (matched) return i;
  }
  return -1;
}

bool _contains(List<int> haystack, List<int> needle) =>
    _indexOf(haystack, needle) >= 0;

/// The width, in bytes, of the first raster image in [bytes].
int _rasterWidthBytes(List<int> bytes) {
  final start = _indexOf(bytes, _gsV0);
  final header = start + _gsV0.length + 1;
  return bytes[header] + (bytes[header + 1] << 8);
}

Uint8List _png({required int width, required int height}) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(0, 0, 0, 255));
  return Uint8List.fromList(img.encodePng(image));
}
