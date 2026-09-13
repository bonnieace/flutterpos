import 'dart:typed_data';

import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/tenancy/tenant_session.dart';
import 'package:flutter_application_1/tenancy/tenant_types.dart';
import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// `GS v 0` — the raster bit-image command every printed mark begins with.
const List<int> _rasterHeader = <int>[29, 118, 48];

bool _contains(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var matched = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        matched = false;
        break;
      }
    }
    if (matched) return true;
  }
  return false;
}

Uint8List _png({
  required int width,
  required int height,
  int alpha = 255,
  int shade = 0,
}) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(shade, shade, shade, alpha));
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _gif({required int width, required int height}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(20, 20, 20));
  return Uint8List.fromList(img.encodeGif(image));
}

String printable(List<int> bytes) =>
    String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127));

/// How many line feeds separate the end of [from] from the start of [to].
///
/// **Counted in the bytes rather than read off a rendered string**, because
/// spacing on a roll *is* line feeds: one ends the line that was just printed,
/// and every one after it is a blank line the customer can see.
int feedsBetween(List<int> bytes, String from, String to) {
  final text = String.fromCharCodes(bytes);
  final start = text.indexOf(from);
  expect(start, isNonNegative, reason: 'never printed: $from');
  return _feedsFrom(bytes, start + from.length, to);
}

/// The same count, measured from the end of the raster image's payload.
///
/// **The payload is binary and has to be stepped over rather than searched
/// through**: it can hold any byte, `\n` among them, and a text search for the
/// name would otherwise start inside the picture. `GS v 0` carries its own
/// dimensions, which is exactly enough to know where it ends.
int feedsAfterImage(List<int> bytes, String to) {
  final header = bytes.indexOf(0x1D);
  var start = -1;
  for (var i = header; i >= 0 && i + 7 < bytes.length; i++) {
    if (bytes[i] == 29 && bytes[i + 1] == 118 && bytes[i + 2] == 48) {
      final widthBytes = bytes[i + 4] + (bytes[i + 5] << 8);
      final height = bytes[i + 6] + (bytes[i + 7] << 8);
      start = i + 8 + widthBytes * height;
      break;
    }
  }
  expect(start, isNonNegative, reason: 'no raster image was printed');
  return _feedsFrom(bytes, start, to);
}

int _feedsFrom(List<int> bytes, int start, String to) {
  final end = String.fromCharCodes(bytes).indexOf(to, start);
  expect(end, isNonNegative, reason: 'never printed: $to');
  return bytes.sublist(start, end).where((b) => b == 0x0A).length;
}

void main() {
  late CapabilityProfile profile;

  final printer = TenantPrinterConfiguration(
    transport: PrinterTransportKind.directTcp,
    endpoint: PrinterEndpoint(host: '192.168.1.50', port: 9100),
    paperWidth: PrinterPaperWidth.columns32,
    hasCutter: true,
  );

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    profile = await CapabilityProfile.load();
  });

  List<int> proof({Uint8List? logo}) =>
      CheckoutBrandingProofPage(profile: profile, configuration: printer).build(
        at: DateTime.utc(2026, 9, 5, 15, 51),
        companyName: 'Mama Ndege Stores',
        slogan: 'Fresh every morning',
        logo: logo,
      );

  test('a published logo reaches the payload as a raster image', () {
    final withLogo = proof(logo: _png(width: 400, height: 400));
    final without = proof();

    expect(_contains(withLogo, _rasterHeader), isTrue);
    expect(_contains(without, _rasterHeader), isFalse);
    expect(withLogo.length, greaterThan(without.length));
  });

  test('a logo far taller than it is wide still prints', () {
    // The bounded-height branch, which re-resizes and pads the width back out
    // to a multiple of eight. A width that is not is what smears a mark.
    final mark = receiptLogoMark(_png(width: 100, height: 900));

    expect(mark, isNotNull);
    expect(mark!.width % 8, 0);
    expect(mark.height, lessThanOrEqualTo(receiptLogoMaximumHeightDots));
  });

  test('the dots fired follow the ink, not the paper', () {
    // **The fault a shopkeeper reported off a real roll on 2026-09-05:** a
    // black silhouette on a transparent ground printed as a white silhouette
    // inside a black block. `img.ditherImage` answers with a palette image and
    // `Generator._toRasterFormat` cannot read one - see `receiptLogoMark`.
    // This asserts the bits, because that is the only place the fault was
    // visible short of paper.
    final rows = _dotsPerRow(receiptLogoMark(_disc(ink: true))!);

    expect(rows[1], 0, reason: 'the ground must fire no dots');
    expect(rows[rows.length ~/ 2], greaterThan(0), reason: 'the mark must');
  });

  test('a light subject on a transparent ground prints its shape', () {
    // Nothing in it is dark enough to print, so a faithful rendering is a blank
    // strip of paper. The shape is what the picture means, and the alpha
    // channel is where the shape is.
    final rows = _dotsPerRow(receiptLogoMark(_disc(ink: false))!);

    expect(rows[1], 0);
    expect(rows[rows.length ~/ 2], greaterThan(0));
  });

  group('the heading is spaced', () {
    // `GS v 0` advances the paper by the height of the image and stops, so
    // without a feed the name's first row of dots sits against the logo's last.
    test('a blank line separates the logo from the name', () {
      final withLogo = proof(logo: _disc(ink: true));

      // **One feed, not two, and the difference is real.** `GS v 0` leaves the
      // head at the start of the next line without printing a line of its own,
      // so a single feed here is a blank line - where after a *text* line the
      // first feed is what ends that line and only the second is blank space.
      expect(feedsAfterImage(withLogo, 'Mama'), 1);
    });

    test('a blank line separates the heading from the rule under it', () {
      expect(feedsBetween(proof(), 'Fresh every morning', '-' * 32), 2);
    });

    test('a receipt is spaced the same, which is what this page claims', () {
      final receipt =
          CheckoutReceiptBody(profile: profile, configuration: printer).build(
            _sale(),
            businessName: 'Ndege',
            slogan: 'Fresh every morning',
            logo: _disc(ink: true),
          );

      expect(feedsAfterImage(receipt, 'Ndege'), 1);
      expect(feedsBetween(receipt, 'Fresh every morning', '-' * 32), 2);
    });

    test('the slogan prints under the name on a receipt', () {
      // The business details screen has said *one line under the name on a
      // receipt* since it was written, and no receipt carried one until now.
      final receipt = CheckoutReceiptBody(
        profile: profile,
        configuration: printer,
      ).build(_sale(), businessName: 'Ndege', slogan: 'Fresh every morning');

      expect(printable(receipt), contains('Fresh every morning'));
      expect(feedsBetween(receipt, 'Ndege', 'Fresh every morning'), 1);
    });

    test('a business with neither logo nor slogan still prints its name', () {
      final receipt = CheckoutReceiptBody(
        profile: profile,
        configuration: printer,
      ).build(_sale(), businessName: 'Ndege');

      expect(printable(receipt), contains('Ndege'));
      expect(feedsBetween(receipt, 'Ndege', '-' * 32), 2);
    });
  });

  test('a cut-out logo prints its subject, not a black rectangle', () {
    // A fully transparent PNG is what *Remove background* produces around the
    // subject. Unflattened, `Generator._toRasterFormat` inverts transparent
    // black into solid black and the whole square prints.
    final mark = receiptLogoMark(_png(width: 200, height: 200, alpha: 0));

    expect(mark, isNotNull);
    final pixel = mark!.getPixel(mark.width ~/ 2, mark.height ~/ 2);
    expect(pixel.r, 255, reason: 'transparency must composite onto paper');
  });

  test('a GIF logo is printable, though it may never be uploaded', () {
    // `TenantProductImageCandidate` admits three formats because those are what
    // may be *stored*. Rendering is a wider question - see `loadTenantImageBytes`.
    expect(receiptLogoMark(_gif(width: 200, height: 200)), isNotNull);
  });

  test('bytes that are not an image at all print no mark and do not throw', () {
    expect(receiptLogoMark(Uint8List.fromList(<int>[1, 2, 3, 4])), isNull);
    expect(receiptLogoMark(Uint8List(0)), isNull);
    expect(receiptLogoMark(null), isNull);
  });

  test('the page still carries no total and says nothing was sold', () {
    final text = printable(proof(logo: _png(width: 120, height: 120)));

    expect(text, contains('Fresh every morning'));
    expect(text, contains('RECEIPT HEADING'));
    expect(text, contains('Nothing was sold'));
    expect(text, isNot(contains('TOTAL')));
  });

  test('a name too long for the roll is cut here exactly as it is cut on a '
      'receipt', () {
    // **The whole reason this page is worth the paper.** A 58mm roll is 32
    // columns and the heading prints at double width, so sixteen characters is
    // all there is - while the field on the business details screen accepts
    // sixty. `CheckoutReceiptBody._heading` cuts at the same place, so what a
    // shopkeeper reads here is what their customers will get.
    expect(printable(proof()), contains('Mama Ndege Store'));
    expect(printable(proof()), isNot(contains('Mama Ndege Stores')));

    final receipt = printable(
      CheckoutReceiptBody(
        profile: profile,
        configuration: printer,
      ).build(_sale(), businessName: 'Mama Ndege Stores'),
    );
    expect(receipt, contains('Mama Ndege Store'));
    expect(receipt, isNot(contains('Mama Ndege Stores')));
  });
}

/// One committed sale, minimal: this file is about the heading above it.
CheckoutSalePayload _sale() {
  const deviceId = 'dev-0123456789abcdef0123456789abcdef';
  final payload = <String, Object?>{
    'schemaVersion': checkoutSalePayloadSchemaVersion,
    'checkoutId': 'checkout-a',
    'tenantId': 'tenant-a',
    'soldById': 'user-a',
    'currency': 'KES',
    'businessDate': '2026-07-29',
    'createdAtMs': DateTime.utc(2026, 7, 29, 8).millisecondsSinceEpoch,
    'shiftId': 'shift-a',
    'deviceId': deviceId,
    'receiptNumber': formatCheckoutReceiptNumber(
      deviceId: deviceId,
      businessDate: '2026-07-29',
      sequence: 42,
    ),
    'receiptSequence': 42,
    'tender': 'cash',
    'items': <Object?>[
      <String, Object?>{
        'productId': 'product-a',
        'name': 'Maize flour 2kg',
        'quantity': 2,
        'unitPriceMinor': 13550,
      },
    ],
    'subtotalMinor': 27100,
    'discountMinor': 0,
    'totalMinor': 27100,
  };
  return CheckoutSalePayload.fromLocalPayload(
    session: TenantSession.active(
      uid: 'user-a',
      tenantId: 'tenant-a',
      role: TenantRole.cashier,
    ),
    checkoutId: 'checkout-a',
    payload: payload,
    payloadHash: checkoutPayloadHash(payload),
  );
}

/// A disc on a transparent ground. [ink] dark - an ordinary silhouette - or
/// light, which has no ink in it at all.
Uint8List _disc({required bool ink, int side = 384}) {
  final image = img.Image(width: side, height: side, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));
  final shade = ink ? 0 : 255;
  final centre = side / 2;
  final radius = side * 0.3;
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      final dx = x + 0.5 - centre;
      final dy = y + 0.5 - centre;
      if (dx * dx + dy * dy <= radius * radius) {
        image.setPixel(x, y, img.ColorRgba8(shade, shade, shade, 255));
      }
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

/// What `Generator._toRasterFormat` will fire, per row: it greyscales, inverts,
/// reads the red channel and sets a bit above 127. Replicated rather than
/// reached into, because it is private to the package.
List<int> _dotsPerRow(img.Image mark) {
  final image = img.Image.from(mark);
  img.grayscale(image);
  img.invert(image);
  final buffer = image.getBytes(order: img.ChannelOrder.rgba);
  return <int>[
    for (var y = 0; y < image.height; y++)
      [
        for (var x = 0; x < image.width; x++)
          if (buffer[(y * image.width + x) * 4] > 127) 1,
      ].length,
  ];
}
