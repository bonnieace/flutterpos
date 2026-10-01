/// A customer's account: what they owe, what they paid back, and the entries
/// that moved it.
///
/// **The balance is the server's.** A credit sale moves it when the sale
/// reaches the server (`processCustomerSale`), a repayment when its request
/// does (`recordCustomerPayment`), a return when it is verified. This device
/// reads the balance and asks for repayments; it never writes a figure.
///
/// **A repayment is money into a drawer.** It is taken into the cashier's own
/// open shift, the same shift a sale would be, so the close expects it and
/// reconciliation adds it to that drawer.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../checkout/checkout_draft.dart';
import '../checkout/checkout_tender.dart';
import '../tenancy/tenancy.dart';
import 'customer.dart';

/// Raised when a repayment cannot be asked for.
final class TenantCustomerPaymentException implements Exception {
  const TenantCustomerPaymentException(this.code);

  final String code;

  @override
  String toString() => 'TenantCustomerPaymentException($code)';
}

/// The most one repayment may be: a hundred million of the major unit, as the
/// server bounds it.
const int maximumCustomerPaymentMinor = 10000000000;

/// A validated request to record one repayment.
final class TenantCustomerPaymentIntent {
  const TenantCustomerPaymentIntent._({
    required this.path,
    required this.tenantId,
    required this.paymentId,
    required this.customerId,
    required this.customerName,
    required this.amountMinor,
    required this.tender,
    required this.shiftId,
    required this.businessDate,
    required this.recordedBy,
  });

  /// Builds the request, or refuses one the server would refuse.
  ///
  /// [shift] is the cashier's own open shift, bound the way a sale binds it,
  /// so a repayment can never be taken into nobody's drawer.
  factory TenantCustomerPaymentIntent.build({
    required TenantSession session,
    required TenantCustomer customer,
    required int amountMinor,
    required CheckoutTender tender,
    required CheckoutShiftAttribution shift,
    String? requestId,
  }) {
    if (!session.canAccess()) {
      throw const TenantCustomerPaymentException('payment_forbidden');
    }
    if (customer.tenantId != session.tenantId ||
        shift.tenantId != session.tenantId ||
        shift.uid != session.uid) {
      throw const TenantCustomerPaymentException('payment_forbidden');
    }
    if (amountMinor <= 0 || amountMinor > maximumCustomerPaymentMinor) {
      throw const TenantCustomerPaymentException('invalid_payment_amount');
    }
    final request = requestId ?? secureCustomerPaymentRequestId();
    final paymentId = customerPaymentId(
      tenantId: session.tenantId,
      recordedBy: session.uid,
      requestId: request,
    );
    return TenantCustomerPaymentIntent._(
      path: TenantPaths(session.tenantId).customerPayment(paymentId),
      tenantId: session.tenantId,
      paymentId: paymentId,
      customerId: customer.id,
      customerName: customer.name,
      amountMinor: amountMinor,
      tender: tender,
      shiftId: shift.shiftId,
      businessDate: shift.businessDate,
      recordedBy: session.uid,
    );
  }

  final String path;
  final String tenantId;
  final String paymentId;
  final String customerId;
  final String customerName;
  final int amountMinor;
  final CheckoutTender tender;
  final String shiftId;
  final String businessDate;
  final String recordedBy;

  /// The callable's request itself, which is what the queue replays.
  Map<String, Object?> callablePayload() => <String, Object?>{
    'tenantId': tenantId,
    'paymentId': paymentId,
    'customerId': customerId,
    'amountMinor': amountMinor,
    'tender': tender.wireValue,
    'shiftId': shiftId,
  };

  /// What the queue keeps: the request, and the two fields the server writes
  /// that this device already knows - the shift's day and who took it - so
  /// the overlay can draw the payment and reading it back confirms it. Not
  /// the name, which the server copies from the customer as it stands then.
  Map<String, Object?> queuedData() => <String, Object?>{
    ...callablePayload(),
    'businessDate': businessDate,
    'recordedBy': recordedBy,
  };
}

/// Where a request to record a repayment is queued.
abstract interface class TenantCustomerPaymentWriter {
  Future<void> recordPayment(TenantCustomerPaymentIntent intent);
}

/// The server's payment ID for one request: `cp_` and forty hex digits.
String customerPaymentId({
  required String tenantId,
  required String recordedBy,
  required String requestId,
}) {
  final digest = sha256.convert(
    utf8.encode(
      <String>['customer-payment', tenantId, recordedBy, requestId].join(' '),
    ),
  );
  return 'cp_${digest.toString().substring(0, 40)}';
}

/// A fresh request ID for one repayment.
String secureCustomerPaymentRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'payment-${base64Url.encode(bytes).replaceAll('=', '')}';
}

/// What moved a customer's balance.
enum TenantCustomerLedgerKind {
  sale('sale', 'Bought on credit'),
  payment('payment', 'Paid back'),
  saleReturn('return', 'Returned goods');

  const TenantCustomerLedgerKind(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static TenantCustomerLedgerKind? tryParse(Object? value) {
    for (final kind in values) {
      if (kind.wireValue == value) return kind;
    }
    return null;
  }
}

/// One entry on a customer's statement.
final class TenantCustomerLedgerEntry {
  const TenantCustomerLedgerEntry._({
    required this.id,
    required this.kind,
    required this.changeMinor,
    required this.balanceAfterMinor,
    required this.receiptNumber,
    required this.tender,
    required this.overLimit,
    required this.at,
  });

  /// The entry [snapshot] holds, or null when it moved no balance - a cash
  /// sale's points entry lives in the same ledger and is not on a statement.
  static TenantCustomerLedgerEntry? fromSnapshot(
    TenantQueryDocumentSnapshot snapshot,
  ) {
    final data = snapshot.data;
    if (data['credit'] != true) return null;
    final kind = TenantCustomerLedgerKind.tryParse(data['kind']);
    final change = data['balanceChangeMinor'];
    final after = data['balanceAfterMinor'];
    if (kind == null || change is! int || after is! int) return null;
    final receipt = data['receiptNumber'];
    return TenantCustomerLedgerEntry._(
      id: snapshot.path.split('/').last,
      kind: kind,
      changeMinor: change,
      balanceAfterMinor: after,
      receiptNumber: receipt is String && receipt.isNotEmpty ? receipt : null,
      tender: CheckoutTender.tryParse(
        kind == TenantCustomerLedgerKind.sale
            ? data['creditPaidTender']
            : data['tender'],
      ),
      overLimit: data['overLimit'] == true,
      at: tenantStoredInstant(data['saleCreatedAt']) ??
          tenantStoredInstant(data['createdAt']),
    );
  }

  final String id;
  final TenantCustomerLedgerKind kind;

  /// What it did to the balance: positive when the customer owes more.
  final int changeMinor;

  /// What they owed straight after it, as the server computed it.
  final int balanceAfterMinor;
  final String? receiptNumber;

  /// How a repayment was paid, or how a credit sale's paid part was.
  final CheckoutTender? tender;

  /// Whether this sale took the customer past their limit.
  final bool overLimit;
  final DateTime? at;
}

/// One page of a statement, newest first.
final class TenantCustomerStatementPage {
  const TenantCustomerStatementPage({
    required this.entries,
    required this.nextCursor,
  });

  final List<TenantCustomerLedgerEntry> entries;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

/// Reads statements and who owes, for management, and builds repayments for
/// anyone who sells.
final class TenantCustomerCreditRepository extends TenantReadRepository {
  TenantCustomerCreditRepository({
    required super.session,
    required TenantDataReader reader,
  }) : _collectionReader = reader,
       super(reader: reader);

  final TenantCollectionReader _collectionReader;

  /// The roles a customer's statement is readable by - the ledger's rule.
  static const List<TenantRole> statementRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
    TenantRole.manager,
  ];

  /// Whether [session] may take a repayment: anyone who sells.
  static bool canTakePaymentInSession(TenantSession session) =>
      session.canAccess(allowedRoles: TenantCustomerRepository.createRoles);

  /// Whether [session] may read statements and who owes.
  static bool canReadStatementInSession(TenantSession session) =>
      session.canAccess(allowedRoles: statementRoles);

  /// One page of [customerId]'s statement, newest first.
  Future<TenantCustomerStatementPage> loadStatement(
    String customerId, {
    int pageSize = 20,
    String? cursor,
  }) async {
    if (!canReadStatementInSession(session)) {
      throw const TenantCustomerPaymentException('statement_forbidden');
    }
    final page = await readCustomerSubcollectionPage(
      TenantCustomerSubcollection.activity,
      customerId: customerId,
      collectionReader: _collectionReader,
      pageSize: pageSize,
      cursor: cursor,
      descending: true,
      order: TenantCollectionOrder.createdAt,
      equalityFilters: const <String, Object?>{'credit': true},
    );
    return TenantCustomerStatementPage(
      entries: <TenantCustomerLedgerEntry>[
        for (final snapshot in page.items)
          ?TenantCustomerLedgerEntry.fromSnapshot(snapshot),
      ],
      nextCursor: page.hasMore ? page.nextCursor : null,
    );
  }

  /// Everyone who owes, biggest debt first.
  ///
  /// **Sorted here, from every page.** A device query cannot both ask for a
  /// balance above zero and order by it, so the server marks each customer
  /// `owing` and this reads every one of them - a shop's debtors are a short
  /// list - then sorts. [maximumPages] bounds a book that is not short.
  Future<List<TenantCustomer>> loadOwing({int maximumPages = 10}) async {
    if (!canReadStatementInSession(session)) {
      throw const TenantCustomerPaymentException('statement_forbidden');
    }
    final owing = <TenantCustomer>[];
    String? cursor;
    for (var page = 0; page < maximumPages; page += 1) {
      final result = await readCollectionPage(
        TenantCollection.customers,
        collectionReader: _collectionReader,
        pageSize: 50,
        cursor: cursor,
        equalityFilters: const <String, Object?>{'owing': true},
      );
      for (final snapshot in result.items) {
        final TenantCustomer customer;
        try {
          customer = TenantCustomer.fromSnapshot(snapshot);
        } on FormatException {
          continue;
        }
        if (customer.owedMinor > 0) owing.add(customer);
      }
      if (!result.hasMore) break;
      cursor = result.nextCursor;
    }
    owing.sort((a, b) {
      final byDebt = b.owedMinor.compareTo(a.owedMinor);
      return byDebt != 0 ? byDebt : a.name.compareTo(b.name);
    });
    return owing;
  }
}
