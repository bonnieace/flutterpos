/// What one business has chosen for its email receipts.
///
/// **Off until somebody turns it on**, and read the same way by the till and
/// the server (`functions/src/emailReceipts/emailReceiptSettings.ts`), so the
/// two can never disagree about whether a receipt is going.
///
/// **Its own document, `configuration/email_receipts`**, not fields on the
/// WhatsApp one: the WhatsApp screen writes `e_receipts` whole, and a till on a
/// build from before email receipts would write it without them.
library;

import '../tenancy/tenancy.dart';
import '../whatsapp/e_receipt_settings.dart';

/// Strict read model for `tenants/{tenantId}/configuration/email_receipts`.
final class TenantEmailReceiptSettings {
  const TenantEmailReceiptSettings({
    required this.emailEnabled,
    required this.mode,
  });

  /// What a business that has configured nothing behaves like: nothing sent.
  static const TenantEmailReceiptSettings off = TenantEmailReceiptSettings(
    emailEnabled: false,
    mode: EReceiptMode.manual,
  );

  factory TenantEmailReceiptSettings.fromMap(Map<String, Object?> map) {
    final enabled = map['emailEnabled'];
    if (enabled is! bool) {
      throw const FormatException('emailEnabled must be true or false.');
    }
    return TenantEmailReceiptSettings(
      emailEnabled: enabled,
      mode: EReceiptMode.parse(map['mode']),
    );
  }

  final bool emailEnabled;

  /// Sent on its own to customers who agreed, or only when a cashier sends.
  final EReceiptMode mode;

  /// Whether a receipt goes to a customer on its own when their sale arrives.
  bool get sendsAutomatically => emailEnabled && mode == EReceiptMode.automatic;

  /// Whether a cashier is offered *Send by email* after a sale - in both modes,
  /// for the reason WhatsApp's is.
  bool get offersManualSend => emailEnabled;

  Map<String, Object?> documentData({required String updatedBy}) =>
      <String, Object?>{
        'emailEnabled': emailEnabled,
        'mode': mode.wireValue,
        'updatedBy': updatedBy,
      };

  @override
  bool operator ==(Object other) =>
      other is TenantEmailReceiptSettings &&
      other.emailEnabled == emailEnabled &&
      other.mode == mode;

  @override
  int get hashCode => Object.hash(emailEnabled, mode);
}

/// This business's email receipt setting, and whether it could be read.
final class TenantPublishedEmailReceipts {
  const TenantPublishedEmailReceipts._(this.state, this._settings);

  const TenantPublishedEmailReceipts.published(
    TenantEmailReceiptSettings settings,
  ) : this._(TenantEReceiptState.published, settings);

  const TenantPublishedEmailReceipts.absent()
    : this._(TenantEReceiptState.absent, null);

  const TenantPublishedEmailReceipts.malformed()
    : this._(TenantEReceiptState.malformed, null);

  final TenantEReceiptState state;
  final TenantEmailReceiptSettings? _settings;

  /// The published settings, or off - which is what the server does too.
  TenantEmailReceiptSettings get settings =>
      _settings ?? TenantEmailReceiptSettings.off;

  TenantEmailReceiptSettings? get published => _settings;
}

/// Reads one business's email receipt settings.
final class TenantEmailReceiptRepository extends TenantReadRepository {
  TenantEmailReceiptRepository({required super.session, required super.reader});

  static const documentId = 'email_receipts';

  /// Owner and administrator publish it, as they do WhatsApp's; every member
  /// reads it, because the till does.
  static const List<TenantRole> writeRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
  ];

  Future<TenantPublishedEmailReceipts> load() async {
    final data = await readDocument(TenantCollection.configuration, documentId);
    if (data == null) return const TenantPublishedEmailReceipts.absent();
    try {
      return TenantPublishedEmailReceipts.published(
        TenantEmailReceiptSettings.fromMap(data),
      );
    } on FormatException {
      return const TenantPublishedEmailReceipts.malformed();
    }
  }
}

/// One settings change, ready to be written.
final class TenantEmailReceiptSettingsIntent {
  const TenantEmailReceiptSettingsIntent._({
    required this.path,
    required this.settings,
    required this.updatedBy,
  });

  final String path;
  final TenantEmailReceiptSettings settings;
  final String updatedBy;

  Map<String, Object?> documentData() =>
      settings.documentData(updatedBy: updatedBy);
}

final class TenantEmailReceiptPublisher extends TenantReadRepository {
  TenantEmailReceiptPublisher({required super.session, required super.reader});

  static const List<TenantRole> allowedRoles =
      TenantEmailReceiptRepository.writeRoles;

  /// Refuses with the WhatsApp screen's codes, which the screen already words.
  TenantEmailReceiptSettingsIntent buildIntent({
    required TenantEmailReceiptSettings settings,
    required TenantPublishedEmailReceipts published,
  }) {
    if (!session.canAccess(allowedRoles: allowedRoles)) {
      throw const TenantEReceiptException('e_receipts_forbidden');
    }
    if (published.published == settings) {
      throw const TenantEReceiptException('e_receipts_unchanged');
    }
    return TenantEmailReceiptSettingsIntent._(
      path: paths.configurationDocument(
        TenantEmailReceiptRepository.documentId,
      ),
      settings: settings,
      updatedBy: session.uid,
    );
  }
}
