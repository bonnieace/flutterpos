/// Handing a finished file to a browser, which has no folder the app may write
/// to.
///
/// **This is the web's half of the report and template savers.** On a phone
/// they stage the file in the app's temporary folder and give that path to the
/// share sheet; a browser has no temporary folder and no `dart:io` file, so
/// that route throws before any sheet opens. Here the bytes go straight to the
/// browser instead.
///
/// **A download is `file_picker`'s, not `share_plus`'s.** `share_plus` can fall
/// back to a download of its own, but it writes the whole file into a `data:`
/// link first. `file_picker` hands the browser a `Blob`, which is the form a
/// browser expects a file of any size to arrive in.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

/// What became of a file a browser was handed.
///
/// Two outcomes rather than the savers' three, because a browser never says
/// "there is nowhere to put this": where it has no share sheet, it downloads.
enum BrowserFileOutcome {
  /// Shared, or downloaded.
  ///
  /// **A browser is never told which app a shared file reached**, and a
  /// download is never confirmed either - the browser may yet ask where to
  /// save it and be told no. This is as far as the page can see.
  delivered,

  /// The person closed the share sheet without choosing anything.
  dismissed,
}

/// Downloads [bytes] as [filename], into the browser's downloads folder.
Future<void> downloadFromBrowser({
  required Uint8List bytes,
  required String filename,
}) async {
  // Returns null on the web whatever happens; it throws only when the name
  // carries no extension, which every caller's does.
  await FilePicker.platform.saveFile(fileName: filename, bytes: bytes);
}

/// Offers [bytes] to the browser's share sheet, and downloads them where there
/// is none.
///
/// **Every refusal ends in the download.** Firefox has no share sheet; Chrome
/// on a desktop has one that takes a PDF and refuses a spreadsheet; and every
/// browser refuses a sheet that was not opened within a few seconds of a tap,
/// which a report that took longer to build has lost. None of those is a
/// reason to leave the person without their file.
Future<BrowserFileOutcome> shareFromBrowser({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
  String? subject,
  String? text,
  @visibleForTesting Future<ShareResult> Function(ShareParams params)? share,
}) async {
  final ShareResult result;
  try {
    result = await (share ?? SharePlus.instance.share)(
      ShareParams(
        files: <XFile>[
          XFile.fromData(bytes, name: filename, mimeType: mimeType),
        ],
        fileNameOverrides: <String>[filename],
        subject: subject,
        text: text,
        downloadFallbackEnabled: false,
        mailToFallbackEnabled: false,
      ),
    );
  } on Object {
    await downloadFromBrowser(bytes: bytes, filename: filename);
    return BrowserFileOutcome.delivered;
  }
  // A browser answers `unavailable` after a share that went through, because
  // it is not told where to; only a dismissal is distinguishable.
  return result.status == ShareResultStatus.dismissed
      ? BrowserFileOutcome.dismissed
      : BrowserFileOutcome.delivered;
}
