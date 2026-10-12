/// Putting the helper where it starts with Windows, without an administrator.
///
/// **Everything is the signed-in person's own**: the program goes into their
/// `%LOCALAPPDATA%\UzaPay\PrintHelper`, and it starts with Windows from their
/// own `Run` key. Nothing asks for an administrator, so a cashier can install
/// it, and nothing outside their account is touched.
///
/// **Running the downloaded file again is how it is updated**: the new copy
/// asks the running one to stop, takes its place, and starts.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'protocol.dart';

/// The file name the download and the installed copy share.
const String helperExeName = 'UzaPayPrintHelper.exe';

const String _runKey = r'Software\Microsoft\Windows\CurrentVersion\Run';
const String _runValue = 'UzaPay Print Helper';

/// The helper's entry in Windows' *Apps* list, so it is removed the way any
/// program is. A per-user entry, like everything else here.
const String _appsKey =
    r'Software\Microsoft\Windows\CurrentVersion\Uninstall\UzaPayPrintHelper';
const String _caption = 'UzaPay print helper';
const int _iconInformation = 0x40;
const int _iconWarning = 0x30;

/// `%LOCALAPPDATA%\UzaPay\PrintHelper`.
Directory helperDirectory() => Directory(
  '${Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path}'
  r'\UzaPay\PrintHelper',
);

File installedHelper() => File('${helperDirectory().path}\\$helperExeName');

/// Whether this process is the installed copy, rather than a download.
bool isInstalledCopy() =>
    File(Platform.resolvedExecutable).absolute.path.toLowerCase() ==
    installedHelper().absolute.path.toLowerCase();

/// The version of the helper answering on this computer, or null.
Future<String?> runningHelperVersion() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:$helperPort/status'),
    );
    final response = await request.close().timeout(const Duration(seconds: 3));
    final body = jsonDecode(await utf8.decodeStream(response));
    if (body is Map && body['app'] == helperApp) {
      return body['version'] as String?;
    }
    return null;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Asks a running helper to stop, and waits until it has.
Future<void> stopRunningHelper() async {
  if (await runningHelperVersion() == null) return;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    // No `Origin`: this is a program on this computer, not a page.
    final request = await client.postUrl(
      Uri.parse('http://127.0.0.1:$helperPort/quit'),
    );
    await (await request.close()).drain<void>();
  } catch (_) {
    // It may have gone already.
  } finally {
    client.close(force: true);
  }
  for (var attempt = 0; attempt < 20; attempt++) {
    if (await runningHelperVersion() == null) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
}

/// Copies this program into place, makes it start with Windows, starts it,
/// and says how that went.
Future<void> installHelper(
  void Function(String line) log, {
  bool quiet = false,
}) async {
  await stopRunningHelper();
  helperDirectory().createSync(recursive: true);
  final target = installedHelper();
  // The old copy can hold its file for a moment after it stops.
  for (var attempt = 0; ; attempt++) {
    try {
      File(Platform.resolvedExecutable).copySync(target.path);
      break;
    } on FileSystemException {
      if (attempt >= 20) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }
  _setString(_runKey, _runValue, '"${target.path}" --serve');
  _listInApps(target);
  await Process.start(target.path, const <String>[
    '--serve',
  ], mode: ProcessStartMode.detached);
  String? version;
  for (var attempt = 0; attempt < 20 && version == null; attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    version = await runningHelperVersion();
  }
  log('installed to ${target.path}; running: ${version ?? 'no'}');
  if (quiet) return;
  _tell(
    version != null
        ? 'The UzaPay print helper is installed and running, and it starts '
              'with Windows from now on.\n\nGo back to UzaPay and press '
              '"Check again" on the Printer page.'
        : 'The UzaPay print helper is installed but did not start. Restart '
              'this computer, or run the downloaded file again.',
    ok: version != null,
  );
}

/// Stops the helper, stops it starting with Windows, and removes it.
Future<void> uninstallHelper(
  void Function(String line) log, {
  bool quiet = false,
}) async {
  await stopRunningHelper();
  await removeHelper(log);
  if (quiet) return;
  _tell('The UzaPay print helper is removed from this computer.', ok: true);
}

/// Stops it starting with Windows and removes its files, without stopping a
/// running copy - which is how the running copy removes itself, when the
/// Printer page asks, and then exits.
Future<void> removeHelper(void Function(String line) log) async {
  _deleteValue(_runKey, _runValue);
  _deleteKey(_appsKey);
  // The whole folder, log included - and a moment after this program exits,
  // because a running program cannot delete itself.
  //
  // **By relative names from `%LOCALAPPDATA%`, with no quotes at all.** Dart
  // escapes a quote inside an argument with a backslash, which `cmd` does not
  // understand, so a quoted path reached `rmdir` mangled and nothing was
  // removed. `UzaPay` goes too when nothing else of ours is in it.
  final folder = helperDirectory();
  await Process.start(
    'cmd',
    <String>[
      '/c',
      'ping 127.0.0.1 -n 3 > nul & rmdir /s /q UzaPay\\PrintHelper '
          '& rmdir UzaPay',
    ],
    workingDirectory: folder.parent.parent.path,
    mode: ProcessStartMode.detached,
  );
  log('uninstalled');
}

void _listInApps(File target) {
  _setString(_appsKey, 'DisplayName', _caption);
  _setString(_appsKey, 'DisplayVersion', helperVersion);
  _setString(_appsKey, 'Publisher', 'UzaPay');
  _setString(_appsKey, 'DisplayIcon', target.path);
  _setString(_appsKey, 'InstallLocation', helperDirectory().path);
  _setString(_appsKey, 'UninstallString', '"${target.path}" --uninstall');
  _setDword(_appsKey, 'NoModify', 1);
  _setDword(_appsKey, 'NoRepair', 1);
  _setDword(_appsKey, 'EstimatedSize', (target.lengthSync() / 1024).ceil());
}

/// Writes a string value under the signed-in person's own registry, creating
/// [subKey] when it is missing.
void _setString(String subKey, String name, String value) {
  final data = value.toNativeUtf16();
  try {
    _set(subKey, name, REG_SZ, data, (value.length + 1) * 2);
  } finally {
    free(data);
  }
}

void _setDword(String subKey, String name, int value) {
  final data = calloc<Uint32>()..value = value;
  try {
    _set(subKey, name, REG_DWORD, data, 4);
  } finally {
    free(data);
  }
}

void _set(String subKey, String name, int type, Pointer data, int bytes) {
  final key = subKey.toNativeUtf16();
  final value = name.toNativeUtf16();
  try {
    final status = RegSetKeyValue(
      HKEY_CURRENT_USER,
      key,
      value,
      type,
      data,
      bytes,
    );
    if (status != ERROR_SUCCESS) throw WindowsException(status);
  } finally {
    free(key);
    free(value);
  }
}

void _deleteValue(String subKey, String name) {
  final key = subKey.toNativeUtf16();
  final value = name.toNativeUtf16();
  try {
    RegDeleteKeyValue(HKEY_CURRENT_USER, key, value);
  } finally {
    free(key);
    free(value);
  }
}

void _deleteKey(String subKey) {
  final key = subKey.toNativeUtf16();
  try {
    RegDeleteKey(HKEY_CURRENT_USER, key);
  } finally {
    free(key);
  }
}

/// A plain Windows message: this program has no window of its own.
void _tell(String message, {required bool ok}) {
  final text = message.toNativeUtf16();
  final caption = _caption.toNativeUtf16();
  try {
    MessageBox(
      NULL,
      text,
      caption,
      MB_OK | (ok ? _iconInformation : _iconWarning) | MB_SETFOREGROUND,
    );
  } finally {
    free(text);
    free(caption);
  }
}
