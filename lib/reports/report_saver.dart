/// Putting a finished report where the person can find it.
///
/// **Neither route needs a storage permission**, which is why both are
/// available and why the manifest still declares only `INTERNET`. `share_plus`
/// merges its own `FileProvider` for the chooser, and saving a copy goes
/// through `ACTION_CREATE_DOCUMENT`, where the person grants access to the one
/// file they named and nothing else.
///
/// **The share sheet is no longer the only way out.** It is still what reaches
/// mail, Drive, WhatsApp and the printer from one control - the argument
/// `SharedFileTenantProductSheetSaver` makes, and it still holds. But its
/// ranking belongs to Android, so the destination people reach for most had no
/// fixed position in it. See [TenantReportDestination].
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../platform/browser_file.dart';
import 'report_file.dart';

/// Saves the report to a folder the person picks, or offers it to the share
/// sheet.
final class SharedFileTenantReportSaver implements TenantReportSaver {
  const SharedFileTenantReportSaver();

  @override
  Future<TenantReportSaveOutcome> save(
    TenantReportFile file, {
    required TenantReportDestination destination,
  }) => switch (destination) {
    TenantReportDestination.device => _toDevice(file),
    TenantReportDestination.share => _toChooser(file),
  };

  /// `ACTION_CREATE_DOCUMENT`, which writes the bytes itself.
  ///
  /// **Nothing is written to temporary storage on this path.** The picker is
  /// handed the bytes and copies them into the document the person created, so
  /// a cancelled save leaves no file behind anywhere - which a save that staged
  /// a copy first would.
  static Future<TenantReportSaveOutcome> _toDevice(
    TenantReportFile file,
  ) async {
    // **A browser downloads it, and `saveFile` returns null either way.** On a
    // phone null is the person backing out of the picker; read that way here,
    // every report a browser downloaded was announced as saved nowhere.
    if (kIsWeb) {
      await downloadFromBrowser(bytes: file.bytes, filename: file.filename);
      return TenantReportSaveOutcome.saved;
    }
    try {
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: file.subject,
        // Carries the extension, which is what the picker reads to decide the
        // document's type - so a report saved as `.xlsx` opens in a
        // spreadsheet rather than as an unrecognised blob.
        fileName: file.filename,
        bytes: file.bytes,
      );
      return saved == null
          ? TenantReportSaveOutcome.dismissed
          : TenantReportSaveOutcome.saved;
    } on Object {
      // **A device with no file manager at all.** The plugin refuses rather
      // than returning, and that is `unavailable` in this vocabulary: nothing
      // went wrong with the report, there is simply nowhere on this phone to
      // put it. The person is told that, and the share sheet is still there.
      return TenantReportSaveOutcome.unavailable;
    }
  }

  static Future<TenantReportSaveOutcome> _toChooser(
    TenantReportFile file,
  ) async {
    if (kIsWeb) {
      return switch (await shareFromBrowser(
        bytes: file.bytes,
        filename: file.filename,
        mimeType: file.mimeType,
        subject: file.subject,
        text: file.text,
      )) {
        BrowserFileOutcome.delivered => TenantReportSaveOutcome.saved,
        BrowserFileOutcome.dismissed => TenantReportSaveOutcome.dismissed,
      };
    }
    final directory = await getTemporaryDirectory();
    final path = '${directory.path}${Platform.pathSeparator}${file.filename}';
    // **Bytes, and no byte-order mark.** The CSV saver this is modelled on
    // writes a BOM so Excel does not read a UTF-8 template as the system code
    // page. A PDF and a zip are binary: a BOM in front of either is three
    // bytes of corruption, and the file will not open.
    await File(path).writeAsBytes(file.bytes, flush: true);

    final result = await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(path, mimeType: file.mimeType)],
        subject: file.subject,
        text: file.text,
      ),
    );
    return switch (result.status) {
      ShareResultStatus.success => TenantReportSaveOutcome.saved,
      ShareResultStatus.dismissed => TenantReportSaveOutcome.dismissed,
      ShareResultStatus.unavailable => TenantReportSaveOutcome.unavailable,
    };
  }
}
