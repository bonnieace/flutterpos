import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:uzapay_print_helper/print_helper.dart';

void main() {
  test('the version is the package’s', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    // Either line ending: git stores \n, a Windows checkout may hold \r\n.
    final line = RegExp(
      '^version: ${RegExp.escape(helperVersion)}\r?\$',
      multiLine: true,
    );
    expect(line.hasMatch(pubspec), isTrue);
  });

  group('which pages may use it', () {
    test('UzaPay’s own, over https', () {
      expect(isAllowedOrigin('https://uzapay.co.ke'), isTrue);
      expect(isAllowedOrigin('https://app.uzapay.co.ke'), isTrue);
      expect(isAllowedOrigin('https://multitenant-pos-b8326.web.app'), isTrue);
      expect(
        isAllowedOrigin('https://multitenant-pos-b8326.firebaseapp.com'),
        isTrue,
      );
    });

    test('this computer’s own pages, on any port', () {
      expect(isAllowedOrigin('http://127.0.0.1:8765'), isTrue);
      expect(isAllowedOrigin('http://localhost:3000'), isTrue);
    });

    test('nobody else', () {
      for (final origin in <String>[
        'https://evil.example',
        'https://uzapay.co.ke.evil.example',
        'https://notuzapay.co.ke',
        'http://uzapay.co.ke', // not https
        'http://app.uzapay.co.ke',
        'null', // a sandboxed frame or a file
        '',
        'https://192.168.1.10',
      ]) {
        expect(isAllowedOrigin(origin), isFalse, reason: origin);
      }
    });
  });

  group('where it will send a receipt', () {
    test('this shop’s own network, and this computer', () {
      for (final address in <String>[
        '192.168.1.50',
        '10.0.0.9',
        '172.16.4.2',
        '172.31.255.1',
        '169.254.10.10',
        '127.0.0.1',
        'fe80::1',
        'fd12:3456::1',
        '::1',
      ]) {
        expect(
          isLocalAddress(InternetAddress(address)),
          isTrue,
          reason: address,
        );
      }
    });

    test('nowhere public', () {
      for (final address in <String>[
        '8.8.8.8',
        '172.32.0.1',
        '192.169.1.1',
        '2001:4860:4860::8888',
      ]) {
        expect(
          isLocalAddress(InternetAddress(address)),
          isFalse,
          reason: address,
        );
      }
    });
  });

  group('a USB printer’s key', () {
    test('from the path Windows’ own driver writes to', () {
      expect(
        usbKeyFromDevicePath(
          r'\\?\usb#vid_1fc9&pid_2016#06c6aca91073#'
          '{28d78fad-5a12-11d1-ae5b-0000f803a8c2}',
        ),
        '1FC9:2016:06C6ACA91073',
      );
      // No serial number: Windows' instance name has `&` in it.
      expect(
        usbKeyFromDevicePath(
          r'\\?\usb#vid_0416&pid_5011#5&2b3c4d&0&1#'
          '{28d78fad-5a12-11d1-ae5b-0000f803a8c2}',
        ),
        '0416:5011',
      );
      expect(usbKeyFromDevicePath(r'\\?\hid#something'), isNull);
    });

    test('matches whatever case the serial was reported in', () {
      expect(
        usbKeyMatches('1fc9:2016:06c6aca91073', '1FC9:2016:06C6ACA91073'),
        isTrue,
      );
      expect(usbKeyMatches('1FC9:2016', '1FC9:2016:06C6ACA91073'), isTrue);
      expect(
        usbKeyMatches('1FC9:2016:OTHER', '1FC9:2016:06C6ACA91073'),
        isFalse,
      );
      expect(usbKeyMatches('04B8:0E15', '1FC9:2016'), isFalse);
    });
  });

  group('a print request', () {
    test('reads a USB and a network target, and the bytes', () {
      final usb = parsePrint(<String, Object?>{
        'target': <String, Object?>{'kind': 'usb', 'key': '1FC9:2016'},
        'data': base64Encode(<int>[0x1B, 0x40]),
      });
      expect((usb.target as UsbTarget).key, '1FC9:2016');
      expect(usb.bytes, <int>[0x1B, 0x40]);

      final network = parseTarget(<String, Object?>{
        'kind': 'network',
        'host': '192.168.1.50',
        'port': 9100,
      });
      expect((network as NetworkTarget).port, 9100);
    });

    test('refuses what the app would never send', () {
      for (final target in <Object?>[
        null,
        <String, Object?>{'kind': 'serial'},
        <String, Object?>{'kind': 'usb', 'key': 'not a key'},
        <String, Object?>{'kind': 'network', 'host': 'http://x', 'port': 9100},
        <String, Object?>{'kind': 'network', 'host': '0.0.0.0', 'port': 9100},
        <String, Object?>{'kind': 'network', 'host': 'printer', 'port': 0},
      ]) {
        expect(
          () => parseTarget(target),
          throwsFormatException,
          reason: '$target',
        );
      }
      expect(
        () => parsePrint(<String, Object?>{
          'target': <String, Object?>{'kind': 'usb', 'key': '1FC9:2016'},
          'data': 'not base64!',
        }),
        throwsFormatException,
      );
    });
  });
}
