/// Receipts sent on WhatsApp: what became of each, and a cashier's request to
/// send one.
///
/// **The server sends; the device only asks and reads.** A delivery record is
/// written by `functions/src/whatsapp/deliveries.ts` and moved on by Meta's
/// webhook, and a device that asks for a receipt queues the request - so a
/// till with no signal can still promise a customer their receipt, and keep
/// that promise when it reconnects.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../tenancy/tenancy.dart';

/// Where one receipt has got to, in words a shopkeeper uses.
enum ReceiptDeliveryStatus {
  queued('queued', 'Waiting to send'),
  sending('sending', 'Sending'),
  sent('sent', 'Sent'),
  delivered('delivered', 'Delivered'),
  read('read', 'Read'),
  failed('failed', 'Not delivered'),
  skipped('skipped', 'Not sent');

  const ReceiptDeliveryStatus(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static ReceiptDeliveryStatus parse(Object? value) =>
      ReceiptDeliveryStatus.values.firstWhere(
        (status) => status.wireValue == value,
        orElse: () => ReceiptDeliveryStatus.queued,
      );
}

/// Read model for `tenants/{tenantId}/receipt_deliveries/{deliveryId}`.
final class TenantReceiptDelivery {
  TenantReceiptDelivery.fromSnapshot(TenantQueryDocumentSnapshot snapshot)
    : id = snapshot.path.split('/').last,
      saleId = _text(snapshot.data['saleId']) ?? '',
      receiptNumber = _text(snapshot.data['receiptNumber']),
      customerName = _text(snapshot.data['customerName']),
      phoneMasked = _text(snapshot.data['phoneMasked']) ?? '',
      automatic = snapshot.data['trigger'] == 'automatic',
      status = ReceiptDeliveryStatus.parse(snapshot.data['status']),
      reason = _text(snapshot.data['reason']),
      createdAt = tenantStoredInstant(snapshot.data['createdAt']);

  final String id;
  final String saleId;
  final String? receiptNumber;
  final String? customerName;
  final String phoneMasked;
  final bool automatic;
  final ReceiptDeliveryStatus status;
  final String? reason;
  final DateTime? createdAt;

  /// Why a receipt did not go, in the words the screen shows.
  String? get reasonText => switch (reason) {
    null => null,
    'not_configured' => 'WhatsApp receipts are not available yet.',
    'turned_off' => 'WhatsApp receipts were switched off.',
    'no_consent' => 'The customer has not agreed to WhatsApp receipts.',
    'opted_out' => 'The customer replied STOP.',
    'waiting_for_sale' => 'Waiting for the sale to reach the server.',
    'retrying' => 'WhatsApp did not answer; trying again.',
    'no_number' => 'No number was given.',
    // Meta's own code says whose problem it was. Only 131026 is about the
    // number; the 132xxx family is about UzaPay's receipt template - unknown,
    // still in review, paused - and blaming the number for that sends a shop
    // to check the wrong thing.
    'refused_131026' =>
      'WhatsApp could not deliver it - the number may not be on WhatsApp.',
    final code when code.startsWith('refused_132') =>
      "WhatsApp would not use UzaPay's receipt message - it may not be "
          'approved yet.',
    final code when code.startsWith('refused') => 'WhatsApp refused it.',
    _ => 'Not delivered.',
  };

  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value : null;
}

/// Reads recent deliveries, for management.
final class TenantReceiptDeliveryRepository extends TenantReadRepository {
  TenantReceiptDeliveryRepository({
    required super.session,
    required TenantDataReader reader,
  }) : _collectionReader = reader,
       super(reader: reader);

  final TenantCollectionReader _collectionReader;

  /// The roles `receipt_deliveries` is readable by.
  static const List<TenantRole> readRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
    TenantRole.manager,
  ];

  /// The most recent deliveries, newest first.
  Future<List<TenantReceiptDelivery>> loadRecent({int pageSize = 20}) async {
    final page = await readCollectionPage(
      TenantCollection.receiptDeliveries,
      collectionReader: _collectionReader,
      pageSize: pageSize,
      order: TenantCollectionOrder.createdAt,
      descending: true,
    );
    return <TenantReceiptDelivery>[
      for (final snapshot in page.items) TenantReceiptDelivery.fromSnapshot(snapshot),
    ];
  }
}

/// A validated request to send one sale's receipt to one number.
final class TenantWhatsappReceiptIntent {
  const TenantWhatsappReceiptIntent._({
    required this.path,
    required this.tenantId,
    required this.deliveryId,
    required this.saleId,
    required this.phone,
    required this.requestId,
    required this.customerName,
  });

  /// Builds a request, or refuses one that is not a number.
  factory TenantWhatsappReceiptIntent.build({
    required TenantSession session,
    required String saleId,
    required String phone,
    String? customerName,
    String? requestId,
  }) {
    if (!session.canAccess()) {
      throw const TenantWhatsappReceiptException('receipt_forbidden');
    }
    if (!_e164.hasMatch(phone)) {
      throw const TenantWhatsappReceiptException('invalid_phone');
    }
    final String safeSaleId;
    try {
      safeSaleId = validateTenantDocumentId(saleId, fieldName: 'saleId');
    } on ArgumentError {
      throw const TenantWhatsappReceiptException('invalid_sale');
    }
    final request = requestId ?? secureWhatsappReceiptRequestId();
    final deliveryId = whatsappReceiptDeliveryId(
      tenantId: session.tenantId,
      saleId: safeSaleId,
      phone: phone,
      requestId: request,
    );
    final name = customerName?.trim();
    return TenantWhatsappReceiptIntent._(
      path: TenantPaths(session.tenantId).receiptDelivery(deliveryId),
      tenantId: session.tenantId,
      deliveryId: deliveryId,
      saleId: safeSaleId,
      phone: phone,
      requestId: request,
      customerName: name == null || name.isEmpty ? null : name,
    );
  }

  final String path;
  final String tenantId;
  final String deliveryId;
  final String saleId;
  final String phone;
  final String requestId;
  final String? customerName;

  /// The callable's request itself, which is what the queue replays.
  Map<String, Object?> callablePayload() => <String, Object?>{
    'tenantId': tenantId,
    'saleId': saleId,
    'phone': phone,
    'requestId': requestId,
    if (customerName != null) 'customerName': customerName,
  };
}

final class TenantWhatsappReceiptException implements Exception {
  const TenantWhatsappReceiptException(this.code);

  final String code;

  @override
  String toString() => 'TenantWhatsappReceiptException($code)';
}

/// Where a request to send a receipt is queued.
abstract interface class TenantWhatsappReceiptWriter {
  Future<void> send(TenantWhatsappReceiptIntent intent);
}

/// The server's `receiptDeliveryId`, character for character, so a queued
/// request is addressed to the record the server will write.
String whatsappReceiptDeliveryId({
  required String tenantId,
  required String saleId,
  required String phone,
  required String requestId,
}) {
  final digest = sha256.convert(
    utf8.encode(
      <String>['whatsapp-receipt', tenantId, saleId, phone, requestId].join(' '),
    ),
  );
  return 'rd_${digest.toString().substring(0, 40)}';
}

/// A fresh request ID for one manual send.
String secureWhatsappReceiptRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'receipt-${base64Url.encode(bytes).replaceAll('=', '')}';
}

final RegExp _e164 = RegExp(r'^\+[1-9]\d{7,14}$');
