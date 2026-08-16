/// The tenant printer document: `docs/printer_transport.md` §6.
///
/// **It follows `checkout_configuration.dart` exactly rather than inventing a
/// second pattern.** Canonical document at
/// `tenants/{tenantId}/configuration/printer`, read through
/// `TenantReadRepository` and never as a raw Firestore read from a composition
/// root; a strict `fromMap` that throws `FormatException` on anything
/// malformed; unknown fields ignored so a later setting cannot break this
/// slice; a minimal projection for the encrypted offline cache.
///
/// **Missing or malformed fails closed, and this is the rule the whole document
/// is written around.** There is **no default printer address, ever**. A
/// checkout completes and the receipt stays queued with a clear reason; it does
/// not get dialled at a guessed IP. `docs/printer_transport.md` §2 records what
/// the alternative looks like in the repository this design borrows from: a
/// `catch (_)` around the config load that falls back to a built-in
/// `192.168.100.100`, which on a customer's LAN is **someone else's device**.
///
/// **The rules need no change and that was checked rather than assumed.**
/// `firestore.rules` already carries `match /configuration/{documentId}` with
/// read for active staff and write for owner and admin, so `printer` is covered
/// by the same wildcard `checkout` is.
library;

import '../tenancy/tenant_paths.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_types.dart';
import 'checkout_print_transport_base.dart';

/// Paper widths a thermal roll comes in, as a column count.
///
/// **A count of columns rather than millimetres**, because it is a formatting
/// input rather than a physical fact: `docs/printer_transport.md` §2 ends its
/// list with "a 32-column roll and a 48-column roll are different layouts".
/// The two values are the two rolls that exist in this market; a third is an
/// amendment here rather than a free integer, because a receipt formatter has
/// to be written against each one.
enum PrinterPaperWidth {
  /// 58mm roll.
  columns32('columns_32', 32),

  /// 80mm roll.
  columns48('columns_48', 48);

  const PrinterPaperWidth(this.wireValue, this.columns);

  final String wireValue;
  final int columns;

  static PrinterPaperWidth? tryParse(Object? value) {
    if (value is! String) return null;
    for (final width in PrinterPaperWidth.values) {
      if (width.wireValue == value) return width;
    }
    return null;
  }
}

/// Strict read model for `tenants/{tenantId}/configuration/printer`.
final class TenantPrinterConfiguration {
  TenantPrinterConfiguration({
    required this.transport,
    required this.endpoint,
    required this.paperWidth,
    required this.hasCutter,
    this.bridgeToken,
  }) {
    if (transport == PrinterTransportKind.none) {
      throw const FormatException('transport must name a real transport.');
    }
    if (transport == PrinterTransportKind.httpBridge &&
        (bridgeToken != null && bridgeToken!.trim().isEmpty)) {
      throw const FormatException('bridgeToken must not be blank when set.');
    }
  }

  /// Parses the canonical document. Throws [FormatException] on anything this
  /// slice depends on being wrong.
  ///
  /// **Every field is required to be exactly valid and unknown fields are
  /// ignored**, which is the same asymmetry `TenantCheckoutConfiguration` uses
  /// and for the same reason: a setting a later build adds must not make this
  /// one refuse to print.
  factory TenantPrinterConfiguration.fromMap(Map<String, Object?> map) {
    final transport = _transportFromWire(map['transport']);
    final host = map['host'];
    final port = map['port'];
    if (host is! String) {
      throw const FormatException('host must be a string.');
    }
    if (port is! int) {
      throw const FormatException('port must be an integer.');
    }
    final PrinterEndpoint endpoint;
    try {
      endpoint = PrinterEndpoint(host: host, port: port);
    } on ArgumentError catch (error) {
      // The endpoint's own refusals become this document's refusals, so a
      // config carrying `http://printer/` fails closed here rather than at the
      // socket. `docs/printer_transport.md` §9 asks for exactly this.
      throw FormatException('${error.name}: ${error.message}');
    }
    final paperWidth = PrinterPaperWidth.tryParse(map['paperWidth']);
    if (paperWidth == null) {
      throw const FormatException('paperWidth must be a known roll width.');
    }
    final hasCutter = map['hasCutter'];
    if (hasCutter is! bool) {
      throw const FormatException('hasCutter must be a boolean.');
    }
    final bridgeToken = map['bridgeToken'];
    if (bridgeToken != null && bridgeToken is! String) {
      throw const FormatException('bridgeToken must be a string when present.');
    }
    return TenantPrinterConfiguration(
      transport: transport,
      endpoint: endpoint,
      paperWidth: paperWidth,
      hasCutter: hasCutter,
      bridgeToken: bridgeToken as String?,
    );
  }

  static PrinterTransportKind _transportFromWire(Object? value) {
    switch (value) {
      case 'direct_tcp':
        return PrinterTransportKind.directTcp;
      case 'http_bridge':
        return PrinterTransportKind.httpBridge;
      default:
        throw const FormatException(
          'transport must be direct_tcp or http_bridge.',
        );
    }
  }

  static String transportToWire(PrinterTransportKind kind) => switch (kind) {
    PrinterTransportKind.directTcp => 'direct_tcp',
    PrinterTransportKind.httpBridge => 'http_bridge',
    PrinterTransportKind.none => throw ArgumentError.value(kind, 'kind'),
  };

  final PrinterTransportKind transport;

  /// Where the bytes go. On [PrinterTransportKind.directTcp] this is the
  /// printer; on the Phase 2 bridge it is the bridge, and the printer is
  /// decided server-side.
  final PrinterEndpoint endpoint;

  final PrinterPaperWidth paperWidth;

  /// Whether the printer has a cutter. A formatting input: without one the
  /// receipt ends in feed lines instead of a cut command.
  final bool hasCutter;

  /// Phase 2's shared token, carried from day one.
  ///
  /// **The transport must be built to send it even though nothing checks it
  /// yet**, so enabling authentication on the Flask endpoint is a config change
  /// rather than a code change. `docs/printer_transport.md` §5 is explicit that
  /// the endpoint currently accepts anything on the LAN.
  final String? bridgeToken;

  /// The minimal projection persisted in the encrypted offline cache, exactly
  /// as `TenantCheckoutConfiguration.toCacheEntry` does it.
  Map<String, Object?> toCacheEntry() => <String, Object?>{
    'transport': transportToWire(transport),
    'host': endpoint.host,
    'port': endpoint.port,
    'paperWidth': paperWidth.wireValue,
    'hasCutter': hasCutter,
    if (bridgeToken != null) 'bridgeToken': bridgeToken,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TenantPrinterConfiguration &&
          other.transport == transport &&
          other.endpoint == endpoint &&
          other.paperWidth == paperWidth &&
          other.hasCutter == hasCutter &&
          other.bridgeToken == bridgeToken;

  @override
  int get hashCode =>
      Object.hash(transport, endpoint, paperWidth, hasCutter, bridgeToken);
}

/// What one business has configured, as the surface that may replace it sees
/// it.
///
/// **`malformed` is a state rather than a failure**, for the reason
/// `TenantPublishedConfigurationState` already records: the strict read model
/// refuses a bad document and printing therefore refuses to run, so the one
/// person who can correct it must be able to *see* it and overwrite it, not be
/// shown the same refusal the cashier is.
enum TenantPrinterConfigurationState { configured, absent, malformed }

final class TenantConfiguredPrinter {
  const TenantConfiguredPrinter._(this.state, this.configuration);

  const TenantConfiguredPrinter.configured(
    TenantPrinterConfiguration configuration,
  ) : this._(TenantPrinterConfigurationState.configured, configuration);

  const TenantConfiguredPrinter.absent()
    : this._(TenantPrinterConfigurationState.absent, null);

  const TenantConfiguredPrinter.malformed()
    : this._(TenantPrinterConfigurationState.malformed, null);

  final TenantPrinterConfigurationState state;
  final TenantPrinterConfiguration? configuration;

  /// Whether a device in this business can send a receipt at all.
  bool get canPrint => state == TenantPrinterConfigurationState.configured;

  /// The configuration, or a refusal. **Never a default.**
  TenantPrinterConfiguration require() {
    final resolved = configuration;
    if (resolved == null) {
      throw const PrinterTransportException(
        PrinterTransportCode.notConfigured,
      );
    }
    return resolved;
  }
}

/// Guarded read-only repository for one tenant's printer configuration.
final class TenantPrinterConfigurationRepository extends TenantReadRepository {
  TenantPrinterConfigurationRepository({
    required super.session,
    required super.reader,
  });

  static const documentId = 'printer';

  /// Owner and administrator only may write it, which is what the existing
  /// `configuration/{documentId}` rule already allows. Every active member
  /// *reads* it, because a till cannot print without it.
  static const List<TenantRole> writeRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
  ];

  /// Reads what this business has configured, degrading a malformed document
  /// into a state rather than a failure.
  ///
  /// A [TenantScopeViolation] is deliberately **not** caught: a reader
  /// answering outside this tenant is a broken boundary, not a missing setting,
  /// and reporting it as "no printer is configured" would hide it.
  Future<TenantConfiguredPrinter> load() async {
    final data = await readDocument(TenantCollection.configuration, documentId);
    if (data == null) return const TenantConfiguredPrinter.absent();
    try {
      return TenantConfiguredPrinter.configured(
        TenantPrinterConfiguration.fromMap(data),
      );
    } on FormatException {
      return const TenantConfiguredPrinter.malformed();
    }
  }
}
