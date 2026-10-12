import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uzapay_pos/platform/browser_file.dart';

final Uint8List _bytes = Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46]);

void main() {
  late _DownloadingPicker picker;

  setUp(() => FilePicker.platform = picker = _DownloadingPicker());

  Future<BrowserFileOutcome> share(
    Future<ShareResult> Function(ShareParams params) answer,
  ) => shareFromBrowser(
    bytes: _bytes,
    filename: 'sales-report.pdf',
    mimeType: 'application/pdf',
    subject: 'Sales report',
    text: 'October',
    share: answer,
  );

  test('a download hands the browser the bytes under their name', () async {
    await downloadFromBrowser(bytes: _bytes, filename: 'template.csv');

    expect(picker.downloads, <(String, Uint8List)>[('template.csv', _bytes)]);
  });

  test(
    'the share sheet gets the file itself, and no fallback of its own',
    () async {
      ShareParams? asked;
      final outcome = await share((params) async {
        asked = params;
        return const ShareResult('', ShareResultStatus.unavailable);
      });

      // A browser answers `unavailable` after a share that went through.
      expect(outcome, BrowserFileOutcome.delivered);
      // The override, not the file's own name: a `dart:io` XFile drops the
      // name `fromData` was given, and the override is what `share_plus`'s web
      // half names the file and its download by.
      expect(asked!.fileNameOverrides, <String>['sales-report.pdf']);
      expect(asked!.files!.single.mimeType, 'application/pdf');
      expect(await asked!.files!.single.readAsBytes(), _bytes);
      expect(asked!.subject, 'Sales report');
      expect(asked!.downloadFallbackEnabled, isFalse);
      expect(asked!.mailToFallbackEnabled, isFalse);
      expect(picker.downloads, isEmpty);
    },
  );

  test('closing the sheet is a dismissal, and downloads nothing', () async {
    final outcome = await share(
      (params) async => const ShareResult('', ShareResultStatus.dismissed),
    );

    expect(outcome, BrowserFileOutcome.dismissed);
    expect(picker.downloads, isEmpty);
  });

  test('a browser that refuses the sheet downloads the file instead', () async {
    // Firefox has no sheet, Chrome on a desktop refuses a spreadsheet, and
    // every browser refuses a sheet opened long after the tap.
    final outcome = await share(
      (params) async => throw Exception('Navigator.canShare() is false'),
    );

    expect(outcome, BrowserFileOutcome.delivered);
    expect(picker.downloads, <(String, Uint8List)>[
      ('sales-report.pdf', _bytes),
    ]);
  });
}

final class _DownloadingPicker extends FilePicker {
  final List<(String, Uint8List)> downloads = <(String, Uint8List)>[];

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    downloads.add((fileName!, bytes!));
    // What the web picker answers after starting a download.
    return null;
  }
}
