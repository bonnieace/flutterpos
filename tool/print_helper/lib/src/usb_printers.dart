/// USB printers, through the driver Windows itself gives them.
///
/// **Nothing is installed and nothing is swapped.** When a USB printer is
/// plugged in, Windows binds its built-in USB printer driver (`usbprint`) and
/// exposes the printer as a device interface - the same one Windows' own USB
/// port monitor writes to when it prints. A program may open that interface
/// and write to it as an ordinary user, so the receipt's ESC/POS bytes reach
/// the printer exactly as they would from the Android app: no print queue, no
/// maker's driver, no WinUSB.
///
/// **Every call here blocks**, so the backend runs them on another isolate and
/// the helper keeps answering while a slow printer takes its bytes.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'protocol.dart';

/// `GUID_DEVINTERFACE_USBPRINT`: the interface `usbprint` exposes.
const String _usbPrintInterface = '{28D78FAD-5A12-11D1-AE5B-0000F803A8C2}';

/// A USB printer Windows has, and where to write to it.
final class UsbPrinterInfo {
  const UsbPrinterInfo({
    required this.key,
    required this.name,
    required this.path,
  });

  /// The app's key for it: `1FC9:2016:06C6ACA91073`.
  final String key;

  /// What Windows calls it, from what the printer says about itself.
  final String name;

  /// The device path written to. Never leaves this computer.
  final String path;

  Map<String, Object?> toJson() => <String, Object?>{'key': key, 'name': name};
}

/// Every USB printer `usbprint` has on this computer, plugged in now.
List<UsbPrinterInfo> listUsbPrinters() {
  final guid = GUIDFromString(_usbPrintInterface);
  final set = SetupDiGetClassDevs(
    guid,
    nullptr,
    NULL,
    DIGCF_PRESENT | DIGCF_DEVICEINTERFACE,
  );
  if (set == INVALID_HANDLE_VALUE) {
    free(guid);
    return const <UsbPrinterInfo>[];
  }
  final printers = <UsbPrinterInfo>[];
  final interface = calloc<SP_DEVICE_INTERFACE_DATA>()
    ..ref.cbSize = sizeOf<SP_DEVICE_INTERFACE_DATA>();
  final required = calloc<Uint32>();
  try {
    for (
      var index = 0;
      SetupDiEnumDeviceInterfaces(set, nullptr, guid, index, interface) != 0;
      index++
    ) {
      required.value = 0;
      SetupDiGetDeviceInterfaceDetail(
        set,
        interface,
        nullptr,
        0,
        required,
        nullptr,
      );
      final size = required.value;
      if (size == 0) continue;
      final detail = calloc<Uint8>(size);
      final device = calloc<SP_DEVINFO_DATA>()
        ..ref.cbSize = sizeOf<SP_DEVINFO_DATA>();
      try {
        // The structure's fixed part: a DWORD and the first character of the
        // path, padded to 8 bytes on 64-bit and 6 on 32-bit.
        detail.cast<Uint32>().value = sizeOf<IntPtr>() == 8 ? 8 : 6;
        if (SetupDiGetDeviceInterfaceDetail(
              set,
              interface,
              detail.cast<SP_DEVICE_INTERFACE_DETAIL_DATA_>(),
              size,
              required,
              device,
            ) ==
            0) {
          continue;
        }
        // The path starts straight after the DWORD.
        final path = Pointer<Utf16>.fromAddress(
          detail.address + 4,
        ).toDartString();
        final key = usbKeyFromDevicePath(path);
        if (key == null) continue;
        printers.add(
          UsbPrinterInfo(
            key: key,
            name: _name(set, device) ?? 'USB printer $key',
            path: path,
          ),
        );
      } finally {
        free(detail);
        free(device);
      }
    }
  } finally {
    free(interface);
    free(required);
    free(guid);
    SetupDiDestroyDeviceInfoList(set);
  }
  return printers;
}

/// What Windows calls the device: the name it built from the printer's own
/// description, when it has one.
String? _name(int set, Pointer<SP_DEVINFO_DATA> device) {
  const bytes = 512;
  final buffer = calloc<Uint8>(bytes);
  try {
    if (SetupDiGetDeviceRegistryProperty(
          set,
          device,
          SPDRP_FRIENDLYNAME,
          nullptr,
          buffer,
          bytes,
          nullptr,
        ) ==
        0) {
      return null;
    }
    final name = buffer.cast<Utf16>().toDartString().trim();
    return name.isEmpty ? null : name;
  } finally {
    free(buffer);
  }
}

/// What a write came to. A null [code] is every byte handed to the driver;
/// [detail] is what Windows answered, for the helper's log.
typedef UsbWriteResult = ({String? code, String detail});

/// Opens [path] for writing and lets it go: whether the printer is there and
/// free, without printing.
String? openUsbPrinter(String path) {
  final handle = _open(path, overlapped: false);
  if (handle.code != null) return handle.code;
  CloseHandle(handle.value);
  return null;
}

/// Writes [bytes] to the printer at [path], giving up after [timeoutMs].
///
/// **A null code is every byte handed to the driver** - not proof that paper
/// moved, which nothing here can see.
///
/// **The write is overlapped so it can be abandoned.** A printer out of paper
/// or with its cover open takes no bytes, and a plain write would wait for it
/// forever; this cancels it after [timeoutMs] and says so.
///
/// **It never asks `GetLastError`**, and that is 1.0.3's fix. Between a call
/// and the next one, the Dart runtime may itself call Windows and reset the
/// last error - so 1.0.2 read a write still in progress as a failure with
/// "error 0", gave up on it mid-flight and freed its buffer. Whether a write
/// is still going is instead read from the status Windows keeps on the
/// write's own `OVERLAPPED` record, which nothing else touches; the count
/// comes from `GetOverlappedResult`, because the one `WriteFile` reports is not
/// promised on an overlapped handle.
UsbWriteResult writeUsbPrinter(String path, Uint8List bytes, int timeoutMs) {
  final handle = _open(path, overlapped: true);
  if (handle.code != null) {
    return (code: handle.code, detail: 'open failed');
  }
  final event = CreateEvent(nullptr, TRUE, FALSE, nullptr);
  final overlapped = calloc<OVERLAPPED>()..ref.hEvent = event;
  final buffer = calloc<Uint8>(bytes.length);
  final written = calloc<Uint32>();
  try {
    buffer.asTypedList(bytes.length).setAll(0, bytes);
    WriteFile(handle.value, buffer, bytes.length, nullptr, overlapped);
    if (overlapped.ref.Internal == _statusPending &&
        WaitForSingleObject(event, timeoutMs) == WAIT_TIMEOUT) {
      CancelIoEx(handle.value, overlapped);
      // Wait for the cancel to land before the buffer is freed.
      GetOverlappedResult(handle.value, overlapped, written, TRUE);
      return (
        code: HelperCode.writeTimeout,
        detail: '${written.value} of ${bytes.length} bytes in ${timeoutMs}ms',
      );
    }
    final status = overlapped.ref.Internal;
    if (GetOverlappedResult(handle.value, overlapped, written, TRUE) == 0 ||
        written.value != bytes.length) {
      return (
        code: HelperCode.usbFailed,
        detail:
            '${written.value} of ${bytes.length} bytes, status '
            '0x${status.toRadixString(16)}',
      );
    }
    return (code: null, detail: '${written.value} bytes');
  } finally {
    free(buffer);
    free(written);
    free(overlapped);
    CloseHandle(event);
    CloseHandle(handle.value);
  }
}

/// `STATUS_PENDING`: what Windows writes on an `OVERLAPPED` record while the
/// operation it describes is still going.
const int _statusPending = 0x103;

/// Opens the printer.
///
/// **A failure here is the printer being held**, not missing: every caller
/// has just found it among the printers Windows has, and the error number
/// that would say more cannot be read reliably from Dart - see
/// [writeUsbPrinter].
({int value, String? code}) _open(String path, {required bool overlapped}) {
  final name = path.toNativeUtf16();
  try {
    final handle = CreateFile(
      name,
      GENERIC_WRITE,
      FILE_SHARE_READ | FILE_SHARE_WRITE,
      nullptr,
      OPEN_EXISTING,
      overlapped ? FILE_FLAG_OVERLAPPED : 0,
      NULL,
    );
    if (handle != INVALID_HANDLE_VALUE) return (value: handle, code: null);
    return (value: 0, code: HelperCode.usbBusy);
  } finally {
    free(name);
  }
}
