@TestOn('windows')
library;

import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:uzapay_print_helper/print_helper.dart';

void main() {
  // **All the way to the write, on another isolate**, which a fake backend
  // never reaches - the path 1.0.0 failed on, for every USB print.
  test('a USB print reaches the write and answers with a code', () async {
    final backend = WindowsPrinterBackend(
      listUsb: () async => const <UsbPrinterInfo>[
        UsbPrinterInfo(
          key: '1FC9:2016:NOTPLUGGEDIN',
          name: 'A printer that is not here',
          path:
              r'\\?\usb#vid_1fc9&pid_2016#notpluggedin#'
              '{28d78fad-5a12-11d1-ae5b-0000f803a8c2}',
        ),
      ],
    );

    final printed = await backend.print(
      const UsbTarget('1FC9:2016:NOTPLUGGEDIN'),
      Uint8List.fromList(<int>[0x1B, 0x40]),
    );
    final probed = await backend.probe(
      const UsbTarget('1FC9:2016:NOTPLUGGEDIN'),
    );

    // A code, not a crash. A path that will not open, for a printer that was
    // listed a moment ago, is read as held by something else.
    const codes = <String>[
      HelperCode.usbBusy,
      HelperCode.usbNotFound,
      HelperCode.usbFailed,
    ];
    expect(printed, isIn(codes));
    expect(probed, isIn(codes));
  });

  test('a printer it cannot find is not found, without a write', () async {
    final backend = WindowsPrinterBackend(
      listUsb: () async => const <UsbPrinterInfo>[],
    );

    expect(
      await backend.print(
        const UsbTarget('04B8:0E15'),
        Uint8List.fromList(<int>[1]),
      ),
      HelperCode.usbNotFound,
    );
  });
}
