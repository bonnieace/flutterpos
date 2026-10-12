/// A small log beside the helper, because it has no window to show errors in.
library;

import 'dart:io';

import 'install.dart';

final class HelperLog {
  HelperLog._(this._file);

  /// `helper.log` in the helper's folder, started afresh past 256 KB.
  factory HelperLog.open() {
    final directory = helperDirectory();
    try {
      directory.createSync(recursive: true);
    } on FileSystemException {
      // Logging is best-effort; a helper that cannot log still prints.
    }
    final file = File('${directory.path}\\helper.log');
    try {
      if (file.existsSync() && file.lengthSync() > 256 * 1024) {
        file.renameSync('${directory.path}\\helper.old.log');
      }
    } on FileSystemException {
      // As above.
    }
    return HelperLog._(file);
  }

  final File _file;

  void line(String text) {
    try {
      _file.writeAsStringSync(
        '${DateTime.now().toIso8601String()} $text\n',
        mode: FileMode.append,
        flush: true,
      );
    } on FileSystemException {
      // As above.
    }
  }
}
