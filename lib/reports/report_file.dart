/// A rendered report, and the seam that hands it to the person.
///
/// **The shape `product_sheet.dart` already proved**, widened from a string to
/// bytes. The import template is generated in pure Dart, handed to an injected
/// `TenantProductSheetSaver`, and the panel gates its button on that saver
/// being non-null so a widget test can pass a fake and assert what was handed
/// over without a filesystem. All three of those properties are worth keeping,
/// and the only thing that changes here is that a PDF and a workbook are binary
/// where a CSV was text.
library;

import 'dart:typed_data';

/// What became of a report the person asked for.
///
/// The same three outcomes `TenantSheetSaveOutcome` carries, and they are three
/// rather than a bool because *the person changed their mind* and *this device
/// offered nowhere to put it* want different things said back to them.
enum TenantReportSaveOutcome {
  /// It reached somewhere - a mail draft, Drive, the downloads folder.
  saved,

  /// The person dismissed the share sheet without sending it anywhere.
  dismissed,

  /// The device offered nowhere to send it.
  unavailable,
}

/// Where a finished report is headed.
///
/// **Two destinations rather than one, because the share sheet cannot be
/// reordered.** Android ranks the chooser itself, from how the person has used
/// it before; an app may not promote a target in it, and `share_plus` exposes
/// no lever that would let it try. So the destination people reach for most —
/// a copy of the file, kept on the phone — is lifted out of the chooser and
/// made a control of our own, where its position is ours to decide. Everything
/// else, WhatsApp and mail and Drive and print, still lives behind [share].
enum TenantReportDestination {
  /// Written wherever the person picks, through the system's own file picker.
  ///
  /// This is `ACTION_CREATE_DOCUMENT`: it needs no storage permission, it hands
  /// back a real file the person chose the name and the folder for, and it does
  /// not involve another app at all.
  device('Save a copy', 'Choose a folder on this phone and keep the file.'),

  /// Handed to the system chooser.
  share('Share', 'Send it to WhatsApp, mail, Drive, or a printer.');

  const TenantReportDestination(this.label, this.description);

  final String label;

  final String description;
}

/// A finished document, ready to hand over.
final class TenantReportFile {
  const TenantReportFile({
    required this.filename,
    required this.bytes,
    required this.mimeType,
    required this.subject,
    required this.text,
  });

  final String filename;

  final Uint8List bytes;

  final String mimeType;

  /// What the share sheet offers it as.
  final String subject;

  /// The line that accompanies it.
  final String text;

  int get sizeInBytes => bytes.length;
}

/// Handing a generated report to wherever the person keeps files.
///
/// **Injected, and nullable at the call site.** A build with no saver wired
/// renders no download control at all, which is the `canDownloadTemplate:
/// widget.sheetSaver != null` gate generalised: a control that cannot deliver a
/// file is worse than no control, because the person presses it and nothing
/// happens.
abstract interface class TenantReportSaver {
  Future<TenantReportSaveOutcome> save(
    TenantReportFile file, {
    required TenantReportDestination destination,
  });
}
