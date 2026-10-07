/// The printer transport seam: `docs/printer_transport.md` §3, verbatim.
///
/// **This file is the contract and nothing else.** It holds no `dart:io`, no
/// `dart:html`, no Flutter, and no state - so both platform implementations and
/// every test fake can depend on it without dragging a platform in.
///
/// **`send` returning normally means *delivered*, not *printed*.** No ESC/POS
/// network transport can prove the second without reading printer status back,
/// which Phase 1 does not do. Every operator-facing string built on this must
/// be honest about the distinction — *"Receipt sent to the printer"*, never
/// *"Receipt printed"*.
///
/// **The transport never touches UI, never holds mutable state, and never
/// decides whether to retry.** Retry belongs to the job queue; a sentence
/// belongs to the UI edge. What it does is throw a code. That is the opposite
/// of the legacy path in `lib/pos/pos.dart`, where the HTTP call, the retry
/// decision and `ScaffoldMessenger.showSnackBar` are interleaved in one method
/// inside a 3,000-line widget.
library;

/// How a [PrinterEndpoint] is reached.
enum PrinterEndpointKind {
  /// A raw ESC/POS socket, `host:port`.
  network,

  /// A Bluetooth Classic serial (SPP) link to a paired device.
  bluetooth,
}

/// A printer address. Immutable, and validated at construction.
///
/// **There is no way to hold an instance describing an address we would refuse
/// to dial**, which is the property the whole class exists for: every caller
/// below this point can treat `host` and `port` as already safe.
///
/// **A Bluetooth printer is the same class rather than a second one**, so the
/// durable queue, its per-printer mutex and every transport keep the one type
/// they already pass around. Its [host] is the device address and its [port]
/// is 0: SPP finds its channel by service record, never by a number.
final class PrinterEndpoint {
  const PrinterEndpoint._(this.host, this.port, this.kind);

  /// Throws [ArgumentError] for anything this app will not dial.
  ///
  /// `docs/printer_transport.md` §9 asks for "hosts we must refuse" as
  /// non-negotiable coverage, and the refusals are these: a host carrying a
  /// scheme or a path, because that is a URL and this is a socket; a host
  /// carrying credentials or a port, because the port is a separate field and
  /// two sources for one number is how they disagree; whitespace anywhere,
  /// because a trailing space in a config field is invisible; the unspecified
  /// address `0.0.0.0`, which means *listen on everything* and never means a
  /// printer; and anything longer than DNS permits.
  factory PrinterEndpoint({required String host, required int port}) {
    final trimmed = host.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(host, 'host', 'Must not be empty.');
    }
    if (trimmed != host) {
      throw ArgumentError.value(host, 'host', 'Must not be padded.');
    }
    if (trimmed.length > _maximumHostLength) {
      throw ArgumentError.value(host, 'host', 'Longer than DNS permits.');
    }
    if (!_hostPattern.hasMatch(trimmed)) {
      throw ArgumentError.value(
        host,
        'host',
        'Must be a bare host or IPv4 address, with no scheme, path, '
            'credentials, port or whitespace.',
      );
    }
    if (_unroutableHosts.contains(trimmed)) {
      throw ArgumentError.value(host, 'host', 'Not an address of a printer.');
    }
    if (port < _minimumPort || port > _maximumPort) {
      throw ArgumentError.value(port, 'port', 'Outside 1-65535.');
    }
    return PrinterEndpoint._(trimmed, port, PrinterEndpointKind.network);
  }

  /// A paired Bluetooth printer, by its device address.
  ///
  /// Accepts either case and stores upper case, which is how Android reports
  /// an address - so one printer is one endpoint, and one mutex, however the
  /// address arrived. Throws [ArgumentError] for anything that is not six
  /// colon-separated hex pairs.
  factory PrinterEndpoint.bluetooth(String address) {
    if (!_bluetoothAddressPattern.hasMatch(address)) {
      throw ArgumentError.value(
        address,
        'address',
        'Must be a Bluetooth address such as 00:11:22:AA:BB:CC.',
      );
    }
    return PrinterEndpoint._(
      address.toUpperCase(),
      bluetoothPort,
      PrinterEndpointKind.bluetooth,
    );
  }

  /// The [port] every Bluetooth endpoint carries. See the class note.
  static const int bluetoothPort = 0;

  static final RegExp _bluetoothAddressPattern = RegExp(
    r'^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$',
  );

  /// The port every ESC/POS network printer this app has met listens on.
  ///
  /// A default rather than a constant in a widget: `docs/printer_transport.md`
  /// §2 records that a config which falls back to *built-in defaults* fails
  /// open and can redirect printing to somebody else's device. This defaults
  /// the **port** and never the host, which is the half that is safe to guess.
  static const int rawEscPosPort = 9100;

  static const int _minimumPort = 1;
  static const int _maximumPort = 65535;
  static const int _maximumHostLength = 253;

  /// Bare hostnames and IPv4 literals. Deliberately no IPv6: a bracketed
  /// literal is a different parse and no printer this app targets needs one.
  static final RegExp _hostPattern = RegExp(
    r'^[A-Za-z0-9]([A-Za-z0-9\-]{0,61}[A-Za-z0-9])?'
    r'(\.[A-Za-z0-9]([A-Za-z0-9\-]{0,61}[A-Za-z0-9])?)*$',
  );

  static const Set<String> _unroutableHosts = <String>{'0.0.0.0'};

  final String host;
  final int port;
  final PrinterEndpointKind kind;

  bool get isBluetooth => kind == PrinterEndpointKind.bluetooth;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrinterEndpoint &&
          other.host == host &&
          other.port == port &&
          other.kind == kind;

  @override
  int get hashCode => Object.hash(host, port, kind);

  /// `192.168.1.50:9100`, or the bare Bluetooth address. Never ambiguous: a
  /// network host cannot contain a colon, and a Bluetooth address has five.
  @override
  String toString() => isBluetooth ? host : '$host:$port';
}

/// Which implementation answered.
enum PrinterTransportKind {
  /// `dart:io` `Socket` — Android, iOS, Windows, macOS, Linux. Phase 1.
  directTcp,

  /// The Flask endpoint — web. Phase 2, and unbuilt.
  httpBridge,

  /// No transport on this platform. Phase 1's answer on web.
  none,

  /// A Bluetooth Classic serial link from this device. Android only, and
  /// **never a business setting**: a Bluetooth printer is paired with one
  /// phone, so it is chosen on that phone and stored there.
  bluetooth,
}

/// What the setup screen needs to explain which path is active.
///
/// **A typed value rather than two loose booleans**, because an operator
/// debugging "it doesn't print" needs to know whether the tablet is talking to
/// the printer or to a bridge, and that changes which field the setup form must
/// even show.
final class PrinterTransportCapability {
  const PrinterTransportCapability({
    required this.kind,
    required this.endpointIsPrinter,
    required this.label,
  });

  final PrinterTransportKind kind;

  /// True when the endpoint the operator configures is the printer itself,
  /// false when it is a bridge that decides the printer server-side.
  ///
  /// On the web bridge this is **false**, and the consequence is a UI rule
  /// rather than a note: the printer address field must be *hidden*, not shown
  /// and ignored.
  final bool endpointIsPrinter;

  /// Operator-facing mode name, e.g. 'Direct network printing'.
  final String label;
}

/// Raised for every transport failure.
///
/// **The code is stable and enumerable**, so it can be persisted as a print
/// job's attention reason, asserted in tests by code rather than by message,
/// and mapped to operator-facing text at the UI edge. None of that works with
/// the free-text `'Could not reach $host:$port. $detail'` the borrowed repo
/// throws.
final class PrinterTransportException implements Exception {
  const PrinterTransportException(this.code);

  final String code;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrinterTransportException && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'PrinterTransportException($code)';
}

/// Every code this app's printing path can produce.
///
/// `docs/printer_transport.md` §8. **This is the only vocabulary the UI maps to
/// text**, and the transport never builds a sentence.
abstract final class PrinterTransportCode {
  /// TCP connect refused or unroutable.
  static const String unreachable = 'printer_unreachable';

  /// Connect timed out. A different fault from [unreachable]: the printer may
  /// be off, or the address may be right and the network wrong.
  static const String connectTimeout = 'printer_connect_timeout';

  /// Connected, then stalled mid-payload — a paper jam or an open cover.
  static const String writeTimeout = 'printer_write_timeout';

  /// No valid tenant printer configuration. Never a guessed address.
  static const String notConfigured = 'printer_not_configured';

  /// The platform has no transport. Phase 1's answer on a web build.
  static const String unsupported = 'transport_unsupported';

  /// Phase 2. The Flask host did not answer.
  static const String bridgeUnreachable = 'bridge_unreachable';

  /// Phase 2. `success: false`, or a non-200.
  static const String bridgeRejected = 'bridge_rejected';

  /// Phase 2. Token missing or wrong.
  static const String bridgeUnauthorized = 'bridge_unauthorized';

  /// Bluetooth is switched off on this device.
  static const String bluetoothOff = 'bluetooth_off';

  /// This app may not use Bluetooth: Android's *Nearby devices* permission was
  /// refused.
  static const String bluetoothPermissionDenied = 'bluetooth_permission_denied';

  /// The Bluetooth printer did not accept a connection - off, out of range,
  /// or connected to another phone. **One code for refused and timed out
  /// alike**, unlike TCP: Android reports both as the same failed `connect`,
  /// and the advice to the operator is the same.
  static const String bluetoothUnreachable = 'bluetooth_printer_unreachable';

  /// Every code: §8's eight, then the three Bluetooth added.
  static const List<String> all = <String>[
    unreachable,
    connectTimeout,
    writeTimeout,
    notConfigured,
    unsupported,
    bridgeUnreachable,
    bridgeRejected,
    bridgeUnauthorized,
    bluetoothOff,
    bluetoothPermissionDenied,
    bluetoothUnreachable,
  ];
}

/// Moves bytes to a printer.
///
/// Never touches UI, never holds mutable state, and never decides whether to
/// retry — that belongs to the job queue.
abstract interface class PrinterTransport {
  PrinterTransportCapability get capability;

  /// Confirms reachability without printing. Throws on failure.
  ///
  /// **A first-class operation rather than a print of nothing.** Onboarding
  /// needs "is this printer reachable?" without wasting paper, and the answer
  /// is the first thing worth knowing when a shop phones in.
  Future<void> probe(PrinterEndpoint endpoint);

  /// Sends one complete payload. Throws on failure.
  ///
  /// Returning normally means the transport handed every byte off. It does not
  /// prove paper moved. See the library note.
  Future<void> send(PrinterEndpoint endpoint, List<int> bytes);

  Future<void> dispose();
}

/// One transport that sends each endpoint down the link it names.
///
/// **This is what lets a Bluetooth receipt print "the normal way".** The queue
/// and the dispatcher hold one [PrinterTransport] and never ask what kind of
/// printer a job is for; the job's own endpoint says, so a receipt queued for a
/// Bluetooth printer is retried and reprinted over Bluetooth by the same code
/// that retries a network one.
final class RoutedPrinterTransport implements PrinterTransport {
  const RoutedPrinterTransport({
    required PrinterTransport network,
    required PrinterTransport bluetooth,
  }) : _network = network,
       _bluetooth = bluetooth;

  final PrinterTransport _network;
  final PrinterTransport _bluetooth;

  /// The network transport's, because that is what the setup form's address
  /// fields describe. The Bluetooth tab asks its own questions.
  @override
  PrinterTransportCapability get capability => _network.capability;

  PrinterTransport _for(PrinterEndpoint endpoint) =>
      endpoint.isBluetooth ? _bluetooth : _network;

  @override
  Future<void> probe(PrinterEndpoint endpoint) => _for(endpoint).probe(endpoint);

  @override
  Future<void> send(PrinterEndpoint endpoint, List<int> bytes) =>
      _for(endpoint).send(endpoint, bytes);

  @override
  Future<void> dispose() async {
    await _network.dispose();
    await _bluetooth.dispose();
  }
}
