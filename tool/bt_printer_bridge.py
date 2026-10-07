"""Makes this PC look like a Bluetooth receipt printer, and prints on a network one.

A phone pairs with this PC and connects to it over Bluetooth Classic SPP - the
serial profile that the 58mm and 80mm thermal printers sold here speak - and
every byte it sends is piped to a raw ESC/POS network printer on port 9100.
Whatever the printer answers (status queries: `DLE EOT n`, `GS r n`) is piped
back, so a client that asks "is there paper?" gets the real printer's answer.

    py -3 tool/bt_printer_bridge.py --printer 192.168.100.20
    py -3 tool/bt_printer_bridge.py --capture-only     # no printer, bytes to disk

Windows only, standard library only: Python's own RFCOMM sockets, plus one
`WSASetService` call through ctypes to publish the SPP record (UUID 0x1101) in
SDP. **Without that record a phone cannot connect** - Android's
`createRfcommSocketToServiceRecord(SPP)` looks the channel up by UUID, and a
listening socket nobody has advertised does not exist to it.

**There is no default printer address**, for the reason
`lib/checkout/checkout_print_configuration.dart` gives: a guessed IP on a shop's
LAN is somebody else's device.

What this does not emulate, so a result here is not mistaken for one on real
hardware:

- **The phone sees a computer, not a printer.** The device name is this PC's
  Bluetooth name and its class of device is *Computer*. A client that filters
  the paired list by name or by the Imaging device class will hide it.
- **The channel is not fixed.** Windows assigns one on bind and SDP publishes
  it. A client that skips SDP and dials channel 1 (the reflection
  `createRfcommSocket(1)` fallback some plugins carry) can miss.
- **Bluetooth throughput is not the printer's.** The bytes queue at network
  speed, so a payload too big for a real printer's buffer will not stall here.

Each job - the bytes between a burst starting and `--idle` seconds of silence,
or the phone disconnecting - is saved as a `.bin` under `--capture-dir`, so what
the phone sent can be inspected after the paper is gone.
"""

from __future__ import annotations

import argparse
import ctypes
import socket
import sys
import threading
import time
import uuid
from ctypes import wintypes
from datetime import datetime
from pathlib import Path

SPP_UUID = uuid.UUID("00001101-0000-1000-8000-00805F9B34FB")

# ws2def.h / ws2bth.h
_NS_BTH = 16
_RNRSERVICE_REGISTER = 0
_RNRSERVICE_DELETE = 2
_BTHPROTO_RFCOMM = 3
_BT_PORT_ANY = -1

_REPO_ROOT = Path(__file__).resolve().parent.parent


class _GUID(ctypes.Structure):
    _fields_ = [
        ("Data1", wintypes.DWORD),
        ("Data2", wintypes.WORD),
        ("Data3", wintypes.WORD),
        ("Data4", ctypes.c_ubyte * 8),
    ]

    @classmethod
    def of(cls, value: uuid.UUID) -> "_GUID":
        guid = cls()
        ctypes.memmove(ctypes.byref(guid), value.bytes_le, ctypes.sizeof(guid))
        return guid


class _SOCKADDR_BTH(ctypes.Structure):
    # ws2bth.h wraps this in pshpack1.h: 2 + 8 + 16 + 4 = 30 bytes.
    _pack_ = 1
    _fields_ = [
        ("addressFamily", wintypes.USHORT),
        ("btAddr", ctypes.c_ulonglong),
        ("serviceClassId", _GUID),
        ("port", wintypes.ULONG),
    ]


class _SOCKET_ADDRESS(ctypes.Structure):
    _fields_ = [("lpSockaddr", ctypes.c_void_p), ("iSockaddrLength", ctypes.c_int)]


class _CSADDR_INFO(ctypes.Structure):
    _fields_ = [
        ("LocalAddr", _SOCKET_ADDRESS),
        ("RemoteAddr", _SOCKET_ADDRESS),
        ("iSocketType", ctypes.c_int),
        ("iProtocol", ctypes.c_int),
    ]


class _WSAQUERYSETW(ctypes.Structure):
    _fields_ = [
        ("dwSize", wintypes.DWORD),
        ("lpszServiceInstanceName", wintypes.LPWSTR),
        ("lpServiceClassId", ctypes.POINTER(_GUID)),
        ("lpVersion", ctypes.c_void_p),
        ("lpszComment", wintypes.LPWSTR),
        ("dwNameSpace", wintypes.DWORD),
        ("lpNSProviderId", ctypes.c_void_p),
        ("lpszContext", wintypes.LPWSTR),
        ("dwNumberOfProtocols", wintypes.DWORD),
        ("lpafpProtocols", ctypes.c_void_p),
        ("lpszQueryString", wintypes.LPWSTR),
        ("dwNumberOfCsAddrs", wintypes.DWORD),
        ("lpcsaBuffer", ctypes.POINTER(_CSADDR_INFO)),
        ("dwOutputFlags", wintypes.DWORD),
        ("lpBlob", ctypes.c_void_p),
    ]


class SdpRecord:
    """The SPP service record for one listening socket, published until [close].

    Every ctypes object the query set points into is held on `self`: Winsock
    reads them again on delete, and a collected buffer there is a crash rather
    than an error.
    """

    def __init__(self, listener: socket.socket, name: str) -> None:
        address, channel = listener.getsockname()
        self._sockaddr = _SOCKADDR_BTH(
            addressFamily=socket.AF_BLUETOOTH,
            btAddr=int(address.replace(":", ""), 16),
            port=channel,
        )
        self._csaddr = _CSADDR_INFO(
            LocalAddr=_SOCKET_ADDRESS(
                ctypes.cast(ctypes.byref(self._sockaddr), ctypes.c_void_p),
                ctypes.sizeof(self._sockaddr),
            ),
            iSocketType=socket.SOCK_STREAM,
            iProtocol=_BTHPROTO_RFCOMM,
        )
        self._service_class = _GUID.of(SPP_UUID)
        self._query = _WSAQUERYSETW(
            dwSize=ctypes.sizeof(_WSAQUERYSETW),
            lpszServiceInstanceName=name,
            lpServiceClassId=ctypes.pointer(self._service_class),
            lpszComment="ESC/POS receipt printer (bridged to the network)",
            dwNameSpace=_NS_BTH,
            dwNumberOfCsAddrs=1,
            lpcsaBuffer=ctypes.pointer(self._csaddr),
        )
        self._ws2 = ctypes.WinDLL("ws2_32")
        self._set(_RNRSERVICE_REGISTER)
        self.address = address
        self.channel = channel

    def _set(self, operation: int) -> None:
        if self._ws2.WSASetServiceW(ctypes.byref(self._query), operation, 0) != 0:
            raise OSError(
                self._ws2.WSAGetLastError(), "WSASetService refused the SPP record"
            )

    def close(self) -> None:
        try:
            self._set(_RNRSERVICE_DELETE)
        except OSError as error:
            log(f"could not withdraw the SDP record: {error}")


class Discoverable:
    """Keeps this PC visible to a phone's Bluetooth search while the bridge runs.

    **Without it the PC does not appear in any search.** Windows 11 is
    connectable but not discoverable unless its Bluetooth settings page is in
    front, and `BluetoothEnableDiscovery` lasts only as long as the process that
    asked - so the bridge asks, and asks again if anything turns it off.
    """

    def __init__(self) -> None:
        self._bt = ctypes.WinDLL("bthprops.cpl")
        for name in ("BluetoothIsDiscoverable", "BluetoothIsConnectable"):
            getattr(self._bt, name).argtypes = [ctypes.c_void_p]
        for name in ("BluetoothEnableDiscovery", "BluetoothEnableIncomingConnections"):
            getattr(self._bt, name).argtypes = [ctypes.c_void_p, ctypes.c_int]

    def ensure(self) -> bool:
        if self._bt.BluetoothIsDiscoverable(None):
            return True
        # A radio must accept connections before it may be discoverable.
        self._bt.BluetoothEnableIncomingConnections(None, 1)
        return bool(self._bt.BluetoothEnableDiscovery(None, 1))

    def release(self) -> None:
        self._bt.BluetoothEnableDiscovery(None, 0)


def log(message: str) -> None:
    print(f"{datetime.now():%H:%M:%S}  {message}", flush=True)


def text_seen(payload: bytes, limit: int = 160) -> str:
    """Printable runs of three or more characters - enough to recognise a
    receipt, not a decoder. `tool/printer_payload_dump.dart` is the decoder."""
    runs, current = [], []
    for byte in payload:
        if 0x20 <= byte < 0x7F:
            current.append(chr(byte))
            continue
        if len(current) >= 3:
            runs.append("".join(current).strip())
        current = []
    if len(current) >= 3:
        runs.append("".join(current).strip())
    joined = " | ".join(run for run in runs if run)
    return joined if len(joined) <= limit else joined[: limit - 1] + "…"


class PrinterLeg:
    """One TCP connection to the network printer, for the length of one job.

    **Opened on the first byte and closed on the job's end, not held for the
    phone's whole session.** A phone that stays connected all day would
    otherwise hold port 9100 all day, and every other client of that printer -
    including this app's own direct-TCP path - would queue behind it.
    """

    def __init__(self, endpoint: tuple[str, int], phone: socket.socket) -> None:
        self._phone = phone
        self._socket = socket.create_connection(endpoint, timeout=4)
        # Bounds a stalled write - a jam or an open cover - and nothing else:
        # the reader's own wait ends when [close] closes the socket under it.
        self._socket.settimeout(10)
        self._open = True
        self._reader = threading.Thread(target=self._pipe_back, daemon=True)
        self._reader.start()

    def send(self, data: bytes) -> None:
        self._socket.sendall(data)

    def _pipe_back(self) -> None:
        while self._open:
            try:
                reply = self._socket.recv(1024)
            except TimeoutError:
                continue
            except OSError:
                return
            if not reply:
                return
            log(f"printer -> phone  {reply.hex(' ')}")
            try:
                self._phone.sendall(reply)
            except OSError:
                return

    def close(self) -> None:
        try:
            self._socket.shutdown(socket.SHUT_WR)
        except OSError:
            pass
        # Long enough for a status reply already in flight to reach the phone.
        self._reader.join(timeout=1.0)
        self._open = False
        self._socket.close()


class Job:
    def __init__(self, number: int) -> None:
        self.number = number
        self.started = datetime.now()
        self.payload = bytearray()
        self.leg: PrinterLeg | None = None
        self.failure: str | None = None


def serve(phone: socket.socket, peer: str, args: argparse.Namespace, counter: list[int]) -> None:
    endpoint = None if args.capture_only else (args.printer, args.port)
    phone.settimeout(0.2)
    job: Job | None = None
    last_byte = 0.0

    def finish() -> None:
        nonlocal job
        if job is None:
            return
        if job.leg is not None:
            job.leg.close()
        path = args.capture_dir / f"job-{job.started:%Y%m%d-%H%M%S}-{job.number:03d}.bin"
        path.write_bytes(job.payload)
        if endpoint is None:
            outcome = "captured only"
        elif job.failure:
            outcome = f"NOT PRINTED - {job.failure}"
        else:
            outcome = f"sent to {endpoint[0]}:{endpoint[1]}"
        log(f"job {job.number}  {len(job.payload):,} bytes  {outcome}")
        log(f"        saved {path}")
        preview = text_seen(bytes(job.payload))
        if preview:
            log(f"        text  {preview}")
        job = None

    while True:
        try:
            data = phone.recv(4096)
            if not data:
                break
        except TimeoutError:
            data = b""
        except OSError as error:
            log(f"phone link dropped: {error}")
            break

        now = time.monotonic()
        if data:
            last_byte = now
            if job is None:
                counter[0] += 1
                job = Job(counter[0])
                if endpoint is not None:
                    try:
                        job.leg = PrinterLeg(endpoint, phone)
                    except OSError as error:
                        # A real printer with no paper still takes the bytes, so
                        # the phone is drained either way; the log is the only
                        # place this failure can be seen.
                        job.failure = f"printer unreachable ({error})"
            job.payload += data
            if job.leg is not None:
                try:
                    job.leg.send(data)
                except OSError as error:
                    job.failure = f"printer stopped mid-job ({error})"
                    job.leg.close()
                    job.leg = None
        elif job is not None and now - last_byte >= args.idle:
            finish()

    finish()
    log(f"phone {peer} disconnected")


def main() -> int:
    if sys.platform != "win32":
        print("This bridge drives the Windows Bluetooth stack and runs on Windows only.")
        return 2

    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument("--printer", help="network printer host or IPv4 address")
    target.add_argument(
        "--capture-only",
        action="store_true",
        help="accept and save jobs without printing them",
    )
    parser.add_argument("--port", type=int, default=9100, help="raw ESC/POS port (9100)")
    parser.add_argument(
        "--name",
        default="UzaPay Test Printer",
        help="SPP service name published in SDP",
    )
    parser.add_argument(
        "--idle",
        type=float,
        default=1.5,
        help="seconds of silence that end a job and release the printer (1.5)",
    )
    parser.add_argument(
        "--capture-dir",
        type=Path,
        default=_REPO_ROOT / "build" / "bt_printer_bridge",
        help="where each job's bytes are saved",
    )
    args = parser.parse_args()
    args.capture_dir.mkdir(parents=True, exist_ok=True)

    if args.printer:
        try:
            socket.create_connection((args.printer, args.port), timeout=3).close()
        except OSError as error:
            log(f"printer {args.printer}:{args.port} did not answer ({error})")
            return 1
        log(f"printer {args.printer}:{args.port} answers")

    listener = socket.socket(socket.AF_BLUETOOTH, socket.SOCK_STREAM, socket.BTPROTO_RFCOMM)
    try:
        listener.bind(("00:00:00:00:00:00", _BT_PORT_ANY))
    except OSError as error:
        log(f"no Bluetooth radio to bind ({error}) - is Bluetooth switched on?")
        return 1
    listener.listen(1)
    # A blocking accept() swallows Ctrl+C on Windows; a short timeout lets it in.
    listener.settimeout(1.0)
    record = SdpRecord(listener, args.name)
    discoverable = Discoverable()
    log(f"'{args.name}' advertised: SPP on RFCOMM channel {record.channel}, radio {record.address}")
    if discoverable.ensure():
        log(f"discoverable as '{socket.gethostname()}' while this runs - search from the app")
    else:
        log("Windows refused to make this PC discoverable; open Settings > Bluetooth & devices")
    log(f"jobs saved under {args.capture_dir}")

    counter = [0]
    last_check = time.monotonic()
    try:
        while True:
            try:
                phone, (peer, _) = listener.accept()
            except TimeoutError:
                # Settings, or a timeout of Windows' own, can switch it off.
                if time.monotonic() - last_check >= 5:
                    last_check = time.monotonic()
                    discoverable.ensure()
                continue
            log(f"phone {peer} connected")
            try:
                serve(phone, peer, args, counter)
            finally:
                phone.close()
    except KeyboardInterrupt:
        log("stopping")
    finally:
        discoverable.release()
        record.close()
        listener.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
