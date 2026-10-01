/// What one business has chosen for its WhatsApp receipts.
///
/// **Off until somebody turns it on.** A business that never opened the
/// WhatsApp tile sends no receipts, and the server reads an absent or
/// unreadable document the same way (`functions/src/whatsapp/
/// eReceiptSettings.ts`), so the till and the server can never disagree about
/// whether a receipt is going.
library;

import '../tenancy/tenancy.dart';

/// The receipt attached as a PDF, or its totals in the message.
enum EReceiptFormat {
  pdf('pdf'),
  summary('summary');

  const EReceiptFormat(this.wireValue);

  final String wireValue;

  static EReceiptFormat parse(Object? value) =>
      value == 'summary' ? EReceiptFormat.summary : EReceiptFormat.pdf;
}

/// Sent on its own to customers who agreed, or only when a cashier sends one.
enum EReceiptMode {
  automatic('automatic'),
  manual('manual');

  const EReceiptMode(this.wireValue);

  final String wireValue;

  static EReceiptMode parse(Object? value) =>
      value == 'automatic' ? EReceiptMode.automatic : EReceiptMode.manual;
}

/// Strict read model for `tenants/{tenantId}/configuration/e_receipts`.
final class TenantEReceiptSettings {
  const TenantEReceiptSettings({
    required this.whatsappEnabled,
    required this.mode,
    required this.format,
  });

  /// What a business that has configured nothing behaves like: nothing sent.
  static const TenantEReceiptSettings off = TenantEReceiptSettings(
    whatsappEnabled: false,
    mode: EReceiptMode.manual,
    format: EReceiptFormat.pdf,
  );

  factory TenantEReceiptSettings.fromMap(Map<String, Object?> map) {
    final enabled = map['whatsappEnabled'];
    if (enabled is! bool) {
      throw const FormatException('whatsappEnabled must be true or false.');
    }
    return TenantEReceiptSettings(
      whatsappEnabled: enabled,
      mode: EReceiptMode.parse(map['mode']),
      format: EReceiptFormat.parse(map['format']),
    );
  }

  final bool whatsappEnabled;
  final EReceiptMode mode;
  final EReceiptFormat format;

  /// Whether a receipt goes to a customer on its own when their sale arrives.
  bool get sendsAutomatically =>
      whatsappEnabled && mode == EReceiptMode.automatic;

  /// Whether a cashier is offered *Send on WhatsApp* after a sale.
  ///
  /// **In both modes.** Automatic sends to customers who agreed; a walk-in, or
  /// a customer who asks for it at the counter, is still sent one by hand.
  bool get offersManualSend => whatsappEnabled;

  Map<String, Object?> documentData({required String updatedBy}) =>
      <String, Object?>{
        'whatsappEnabled': whatsappEnabled,
        'mode': mode.wireValue,
        'format': format.wireValue,
        'updatedBy': updatedBy,
      };

  @override
  bool operator ==(Object other) =>
      other is TenantEReceiptSettings &&
      other.whatsappEnabled == whatsappEnabled &&
      other.mode == mode &&
      other.format == format;

  @override
  int get hashCode => Object.hash(whatsappEnabled, mode, format);
}

/// Whether this business has a setting, and whether it could be read.
enum TenantEReceiptState { published, absent, malformed }

final class TenantPublishedEReceipts {
  const TenantPublishedEReceipts._(this.state, this._settings);

  const TenantPublishedEReceipts.published(TenantEReceiptSettings settings)
    : this._(TenantEReceiptState.published, settings);

  const TenantPublishedEReceipts.absent()
    : this._(TenantEReceiptState.absent, null);

  const TenantPublishedEReceipts.malformed()
    : this._(TenantEReceiptState.malformed, null);

  final TenantEReceiptState state;
  final TenantEReceiptSettings? _settings;

  /// The published settings, or off - which is what the server does too.
  TenantEReceiptSettings get settings =>
      _settings ?? TenantEReceiptSettings.off;

  TenantEReceiptSettings? get published => _settings;
}

/// Reads one business's WhatsApp receipt settings.
final class TenantEReceiptRepository extends TenantReadRepository {
  TenantEReceiptRepository({required super.session, required super.reader});

  static const documentId = 'e_receipts';

  /// Owner and administrator publish it, which the `configuration/{documentId}`
  /// rule already allows; every member reads it, because the till does.
  static const List<TenantRole> writeRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
  ];

  Future<TenantPublishedEReceipts> load() async {
    final data = await readDocument(TenantCollection.configuration, documentId);
    if (data == null) return const TenantPublishedEReceipts.absent();
    try {
      return TenantPublishedEReceipts.published(
        TenantEReceiptSettings.fromMap(data),
      );
    } on FormatException {
      return const TenantPublishedEReceipts.malformed();
    }
  }
}

/// Raised when a change is refused before anything is written.
final class TenantEReceiptException implements Exception {
  const TenantEReceiptException(this.code);

  final String code;

  @override
  String toString() => 'TenantEReceiptException($code)';
}

/// One settings change, ready to be written.
final class TenantEReceiptIntent {
  const TenantEReceiptIntent._({
    required this.path,
    required this.settings,
    required this.updatedBy,
  });

  final String path;
  final TenantEReceiptSettings settings;
  final String updatedBy;

  Map<String, Object?> documentData() =>
      settings.documentData(updatedBy: updatedBy);
}

final class TenantEReceiptPublisher extends TenantReadRepository {
  TenantEReceiptPublisher({required super.session, required super.reader});

  static const List<TenantRole> allowedRoles =
      TenantEReceiptRepository.writeRoles;

  TenantEReceiptIntent buildIntent({
    required TenantEReceiptSettings settings,
    required TenantPublishedEReceipts published,
  }) {
    if (!session.canAccess(allowedRoles: allowedRoles)) {
      throw const TenantEReceiptException('e_receipts_forbidden');
    }
    if (published.published == settings) {
      throw const TenantEReceiptException('e_receipts_unchanged');
    }
    return TenantEReceiptIntent._(
      path: paths.configurationDocument(TenantEReceiptRepository.documentId),
      settings: settings,
      updatedBy: session.uid,
    );
  }
}
