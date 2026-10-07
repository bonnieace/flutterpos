/// Receipts sent by email: what became of each, and a cashier's request to
/// send one.
///
/// **The server sends; the device only asks and reads**, as with WhatsApp
/// (`lib/whatsapp/receipt_delivery.dart`). A delivery record is written by
/// `functions/src/emailReceipts/deliveries.ts` and moved on by Brevo's webhook,
/// and a device that asks for a receipt queues the request.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../tenancy/tenancy.dart';

/// Where one email receipt has got to, in words a shopkeeper uses.
///
/// No *Read*: UzaPay's emails carry no tracking pixel, so nobody knows.
enum EmailReceiptDeliveryStatus {
  queued('queued', 'Waiting to send'),
  sending('sending', 'Sending'),
  sent('sent', 'Sent'),
  delivered('delivered', 'Delivered'),
  failed('failed', 'Not delivered'),
  skipped('skipped', 'Not sent');

  const EmailReceiptDeliveryStatus(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static EmailReceiptDeliveryStatus parse(Object? value) =>
      EmailReceiptDeliveryStatus.values.firstWhere(
        (status) => status.wireValue == value,
        orElse: () => EmailReceiptDeliveryStatus.queued,
      );
}

/// Read model for `tenants/{tenantId}/email_receipt_deliveries/{deliveryId}`.
final class TenantEmailReceiptDelivery {
  TenantEmailReceiptDelivery.fromSnapshot(TenantQueryDocumentSnapshot snapshot)
    : id = snapshot.path.split('/').last,
      saleId = _text(snapshot.data['saleId']) ?? '',
      receiptNumber = _text(snapshot.data['receiptNumber']),
      customerName = _text(snapshot.data['customerName']),
      emailMasked = _text(snapshot.data['emailMasked']) ?? '',
      automatic = snapshot.data['trigger'] == 'automatic',
      status = EmailReceiptDeliveryStatus.parse(snapshot.data['status']),
      reason = _text(snapshot.data['reason']),
      createdAt = tenantStoredInstant(snapshot.data['createdAt']);

  final String id;
  final String saleId;
  final String? receiptNumber;
  final String? customerName;
  final String emailMasked;
  final bool automatic;
  final EmailReceiptDeliveryStatus status;
  final String? reason;
  final DateTime? createdAt;

  /// Why a receipt did not go, in the words the screen shows.
  String? get reasonText => switch (reason) {
    null => null,
    'not_configured' => 'Email receipts are not available yet.',
    'turned_off' => 'Email receipts were switched off.',
    'no_consent' => 'The customer has not agreed to email receipts.',
    'opted_out' => 'The customer stopped email receipts.',
    'undeliverable' =>
      'Mail to this address bounced before, so it was not tried again.',
    'waiting_for_sale' => 'Waiting for the sale to reach the server.',
    'retrying' => 'The mail service did not answer; trying again.',
    'no_address' => 'No email address was given.',
    'refused' => 'The mail service refused it.',
    'provider_unavailable' => 'The mail service could not be reached.',
    'hard_bounce' => 'The address does not accept mail.',
    'invalid_recipient' => 'That email address does not exist.',
    'spam_complaint' => 'The customer reported it as spam.',
    _ => 'Not delivered.',
  };

  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value : null;
}

/// Reads recent email receipts, for management.
final class TenantEmailReceiptDeliveryRepository extends TenantReadRepository {
  TenantEmailReceiptDeliveryRepository({
    required super.session,
    required TenantDataReader reader,
  }) : _collectionReader = reader,
       super(reader: reader);

  final TenantCollectionReader _collectionReader;

  /// The roles `email_receipt_deliveries` is readable by.
  static const List<TenantRole> readRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
    TenantRole.manager,
  ];

  /// How many [loadRecent] reads: the screen says so at the foot of its list.
  static const int recentPageSize = 20;

  /// The most recent deliveries, newest first.
  Future<List<TenantEmailReceiptDelivery>> loadRecent({
    int pageSize = recentPageSize,
  }) async {
    final page = await readCollectionPage(
      TenantCollection.emailReceiptDeliveries,
      collectionReader: _collectionReader,
      pageSize: pageSize,
      order: TenantCollectionOrder.createdAt,
      descending: true,
    );
    return <TenantEmailReceiptDelivery>[
      for (final snapshot in page.items)
        TenantEmailReceiptDelivery.fromSnapshot(snapshot),
    ];
  }
}

/// An address as the server stores and sends to it, or null where it is not
/// one mail can reach.
///
/// `normalizeEmail` in `functions/src/email/recipientHash.ts`, rule for rule,
/// so the delivery ID this device derives is the one the server writes.
String? normalizeReceiptEmail(String typed) {
  final email = typed.trim().toLowerCase();
  if (email.length < 3 || email.length > 320 || !_emailShape.hasMatch(email)) {
    return null;
  }
  return email;
}

/// A validated request to send one sale's receipt to one address.
final class TenantEmailReceiptIntent {
  const TenantEmailReceiptIntent._({
    required this.path,
    required this.tenantId,
    required this.deliveryId,
    required this.saleId,
    required this.email,
    required this.requestId,
    required this.customerName,
  });

  /// Builds a request, or refuses one that is not an address.
  factory TenantEmailReceiptIntent.build({
    required TenantSession session,
    required String saleId,
    required String email,
    String? customerName,
    String? requestId,
  }) {
    if (!session.canAccess()) {
      throw const TenantEmailReceiptException('receipt_forbidden');
    }
    final address = normalizeReceiptEmail(email);
    if (address == null) {
      throw const TenantEmailReceiptException('invalid_email');
    }
    final String safeSaleId;
    try {
      safeSaleId = validateTenantDocumentId(saleId, fieldName: 'saleId');
    } on ArgumentError {
      throw const TenantEmailReceiptException('invalid_sale');
    }
    final request = requestId ?? secureEmailReceiptRequestId();
    final deliveryId = emailReceiptDeliveryId(
      tenantId: session.tenantId,
      saleId: safeSaleId,
      email: address,
      requestId: request,
    );
    final name = customerName?.trim();
    return TenantEmailReceiptIntent._(
      path: TenantPaths(session.tenantId).emailReceiptDelivery(deliveryId),
      tenantId: session.tenantId,
      deliveryId: deliveryId,
      saleId: safeSaleId,
      email: address,
      requestId: request,
      customerName: name == null || name.isEmpty ? null : name,
    );
  }

  final String path;
  final String tenantId;
  final String deliveryId;
  final String saleId;
  final String email;
  final String requestId;
  final String? customerName;

  /// The callable's request itself, which is what the queue replays.
  Map<String, Object?> callablePayload() => <String, Object?>{
    'tenantId': tenantId,
    'saleId': saleId,
    'email': email,
    'requestId': requestId,
    if (customerName != null) 'customerName': customerName,
  };
}

final class TenantEmailReceiptException implements Exception {
  const TenantEmailReceiptException(this.code);

  final String code;

  @override
  String toString() => 'TenantEmailReceiptException($code)';
}

/// Where a request to email a receipt is queued.
abstract interface class TenantEmailReceiptWriter {
  Future<void> send(TenantEmailReceiptIntent intent);
}

/// The server's `emailReceiptDeliveryId`, character for character.
String emailReceiptDeliveryId({
  required String tenantId,
  required String saleId,
  required String email,
  required String requestId,
}) {
  final digest = sha256.convert(
    utf8.encode(
      <String>['email-receipt', tenantId, saleId, email, requestId].join(' '),
    ),
  );
  return 'ed_${digest.toString().substring(0, 40)}';
}

/// A fresh request ID for one manual send.
String secureEmailReceiptRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'email-receipt-${base64Url.encode(bytes).replaceAll('=', '')}';
}

final RegExp _emailShape = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
