/// Builds `build/UzaPayPrintHelper.exe`, and the download site's copy under
/// `build/site/`.
///
/// Run from `tool/print_helper`: `dart run tool/build.dart`.
///
/// **Compiled, then marked a windowed program.** `dart compile exe` makes a
/// console program, which opens a black window that stays for as long as the
/// helper runs - all day, from the moment Windows starts. The PE header's
/// subsystem field says which kind a program is, and setting it to *windows
/// GUI* is the whole difference; the helper writes nothing to a console, so
/// it loses nothing by not having one.
library;

import 'dart:io';
import 'dart:typed_data';

Future<void> main() async {
  final out = File('build/UzaPayPrintHelper.exe');
  out.parent.createSync(recursive: true);
  final compiled = await Process.run(Platform.resolvedExecutable, <String>[
    'compile',
    'exe',
    'bin/uzapay_print_helper.dart',
    '-o',
    out.path,
  ]);
  stdout.write(compiled.stdout);
  stderr.write(compiled.stderr);
  if (compiled.exitCode != 0) exit(compiled.exitCode);
  // The compiler writes the name lower-cased; Windows keeps whatever case a
  // rename gives it, and the file is downloaded under this name.
  final staged = File('build/helper-staged.exe');
  if (staged.existsSync()) staged.deleteSync();
  out.renameSync(staged.path);
  staged.renameSync(out.path);
  markWindowed(out);
  stdout.writeln('Built ${out.path} (${out.lengthSync()} bytes), windowed.');
  // The download site's copy: `firebase.json` here serves `build/site`.
  final site = File('build/site/print-helper/UzaPayPrintHelper.exe');
  site.parent.createSync(recursive: true);
  out.copySync(site.path);
  stdout.writeln('Copied to ${site.path} for the download site.');
}

/// Sets [exe]'s subsystem to `IMAGE_SUBSYSTEM_WINDOWS_GUI`.
void markWindowed(File exe) {
  final bytes = exe.readAsBytesSync();
  final view = ByteData.sublistView(bytes);
  final header = view.getUint32(0x3C, Endian.little);
  if (view.getUint32(header, Endian.little) != 0x00004550) {
    throw StateError('${exe.path} is not a PE file.');
  }
  // After the 4-byte signature and the 20-byte file header, the optional
  // header; its subsystem field is at offset 68 in both PE32 and PE32+.
  final subsystem = header + 4 + 20 + 68;
  const console = 3;
  const windowed = 2;
  final current = view.getUint16(subsystem, Endian.little);
  if (current != console && current != windowed) {
    throw StateError('Unexpected subsystem $current in ${exe.path}.');
  }
  view.setUint16(subsystem, windowed, Endian.little);
  exe.writeAsBytesSync(bytes);
}
