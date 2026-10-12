/// UzaPay's print helper.
///
/// - Run as downloaded: installs itself for this Windows user, starts, and
///   says so.
/// - `--serve`: prints for UzaPay's web till. This is what starts with
///   Windows.
/// - `--uninstall`: stops, stops starting with Windows, and removes itself.
/// - `--quiet`, with either of the first or the last: says nothing - for
///   whoever installs it on many computers at once.
library;

import 'dart:async';
import 'dart:io';

import 'package:uzapay_print_helper/print_helper.dart';

Future<void> main(List<String> args) async {
  final log = HelperLog.open();
  await runZonedGuarded(
    () async {
      final quiet = args.contains('--quiet');
      if (args.contains('--uninstall')) {
        await uninstallHelper(log.line, quiet: quiet);
        exit(0);
      }
      if (args.contains('--serve') || isInstalledCopy()) {
        await _serve(log);
        return;
      }
      await installHelper(log.line, quiet: quiet);
      exit(0);
    },
    (error, stackTrace) {
      log.line('stopped by an error: $error\n$stackTrace');
      exit(1);
    },
  );
}

Future<void> _serve(HelperLog log) async {
  final server = HelperServer(
    backend: WindowsPrinterBackend(log: log.line),
    log: log.line,
    onQuit: () {
      log.line('asked to stop');
      exit(0);
    },
    // The folder goes a moment after this exits, as `--uninstall`'s does.
    onUninstall: () async {
      log.line('asked to remove itself');
      await removeHelper(log.line);
      exit(0);
    },
  );
  try {
    await server.bind();
    log.line('serving version $helperVersion on 127.0.0.1:$helperPort');
  } on SocketException catch (error) {
    // Another copy has the port: this one is not needed.
    log.line('not serving, port taken: ${error.message}');
    exit(0);
  }
}
