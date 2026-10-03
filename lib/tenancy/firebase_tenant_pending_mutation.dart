import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../observability/app_telemetry.dart';
import 'tenant_paths.dart';
import 'tenant_pending_mutation.dart';

/// When the change one queued record carries was made on this device, as the
/// callables that record stock moving read it.
///
/// **The moment it was queued, which is the moment somebody saved it**, and
/// frozen in the record: every replay of it says the same thing. Until
/// 2026-09-25 nothing carried it, and the server dated a delivery received
/// offline on the 24th by the morning of the 25th it was sent in. The server
/// keeps its own time beside this one - it is when the change arrived - and
/// never takes a time from here that is later than that.
int tenantMutationOccurredAtMs(TenantPendingMutationRecord record) =>
    record.createdAt.toUtc().millisecondsSinceEpoch;

/// [record]'s payload with [tenantMutationOccurredAtMs] beside it: the whole
/// request, for a callable whose payload already is one.
Map<String, Object?> tenantTimedCallablePayload(
  TenantPendingMutationRecord record,
) => <String, Object?>{
  ...record.payload,
  'occurredAtMs': tenantMutationOccurredAtMs(record),
};

/// The `createProduct` request one queued create describes.
///
/// **Derived from the record rather than stored in it**, which is what let the
/// create rule close in the same release the callable shipped. The payload is
/// the document a device composed - unchanged from when this kind was a
/// Firestore `set` - and the business and the product come from the path the
/// record already targets. So a create queued by a build that wrote the document
/// The product ID is also the idempotency key. It is already a digest of the
/// request ID that minted it, so a replay answers off the server's own record
/// instead of stocking the shelf twice.
Map<String, Object?> tenantProductCreateCallablePayload(
  TenantPendingMutationRecord record,
) => <String, Object?>{
  'tenantId': record.tenantId,
  'productId': record.targetPath.split('/').last,
  'document': record.payload,
  // Dates the opening stock, when the product is created holding some.
  'occurredAtMs': tenantMutationOccurredAtMs(record),
};

/// The `createCategory` or `renameCategory` request one queued write describes.
///
/// Derived from the record rather than stored in it, exactly as
/// [tenantProductCreateCallablePayload] is and for the same reason: the queued
/// payload is the document a device composed, which is also what the local
/// overlay merges into the cache, and the business and the category come from
/// the path the record already targets. Storing the envelope instead would mean
/// keeping two shapes of the same write in the queue.
///
/// For a create the category ID is also the idempotency key. It is already a
/// digest of the request ID that minted it, so a replay answers off the server's
/// own record rather than being refused as a duplicate of itself.
Map<String, Object?> tenantCategoryCallablePayload(
  TenantPendingMutationRecord record,
) => <String, Object?>{
  'tenantId': record.tenantId,
  'categoryId': record.targetPath.split('/').last,
  'document': record.payload,
};

/// The `createSupplier` or `updateSupplier` request one queued write describes.
///
/// Derived from the record for the reason [tenantCategoryCallablePayload] is:
/// the queued payload is the document a device composed, which is what the
/// overlay draws, and the business and the supplier come from the path. For a
/// create the supplier ID is also the idempotency key.
Map<String, Object?> tenantSupplierCallablePayload(
  TenantPendingMutationRecord record,
) => <String, Object?>{
  'tenantId': record.tenantId,
  'supplierId': record.targetPath.split('/').last,
  'document': record.payload,
};

/// The `createCustomer` or `updateCustomer` request one queued write describes.
///
/// Derived from the record for the supplier reason. For a create the customer
/// ID is also the idempotency key, so a till that sends one twice is not told
/// the customer is a duplicate of themselves.
Map<String, Object?> tenantCustomerCallablePayload(
  TenantPendingMutationRecord record,
) => <String, Object?>{
  'tenantId': record.tenantId,
  'customerId': record.targetPath.split('/').last,
  'document': record.payload,
};

/// Carries one queued mutation to the server, by whichever route its kind uses.
///
/// **Two transports, one queue.** Most kinds are document writes the rules
/// already admit, and replaying one is replaying the same `set` or `delete`.
/// Three are callables, and each for the same underlying reason: the write
/// cannot be split from the ledger entry that accounts for it. `allow update` on
/// `products` cannot be widened without giving up the guarantee that no client
/// inflates stock, so a correction and an adjustment go through the Admin SDK -
/// and since 2026-09-13 a create does too, because a created product may carry
/// an opening quantity whose `stock_movements` entry is server-written.
///
/// **Replaying a callable is safe, and that is a server property rather than a
/// hope.** `runIdempotentFirestoreTransaction` in `functions/src/core/`
/// stores each result against `actorUid + operation + scope + requestId`; a
/// repeat with the same input returns the stored result rather than acting
/// twice, and only a repeat with *different* input under the same request ID is
/// refused as `already-exists`. The queue keeps one request ID per operation
/// for its whole life, so a retry always takes the first branch.
final class FirebaseTenantMutationGateway
    implements
        TenantMutationSubmissionGateway,
        TenantMutationConfirmationGateway {
  FirebaseTenantMutationGateway({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    this.deadline = const Duration(seconds: 8),
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final Duration deadline;

  static const Set<String> _rejectedCodes = <String>{
    'permission-denied',
    'unauthenticated',
    'invalid-argument',
    'not-found',
    'already-exists',
    'failed-precondition',
    'out-of-range',
  };

  @override
  Future<Map<String, Object?>?> read(String targetPath) async {
    // **A WhatsApp receipt request is never confirmed by reading.** Its target
    // is a delivery record a cashier may not read, so the read could only
    // fail - and a failing read is retried for ever rather than ever sending
    // again. Answering "nothing there" lets the worker do what settles it:
    // send again, which the server answers from its idempotency record.
    // An email receipt request is the same, for the same reason.
    final segments = targetPath.split('/');
    if (segments.length == 4 &&
        (segments[2] == TenantCollection.receiptDeliveries.segment ||
            segments[2] == TenantCollection.emailReceiptDeliveries.segment)) {
      return null;
    }
    final snapshot = await _firestore
        .doc(targetPath)
        .get(const GetOptions(source: Source.server))
        .timeout(deadline);
    return snapshot.data();
  }

  @override
  Future<TenantMutationSubmissionResult> submit(
    TenantPendingMutationRecord record,
  ) async {
    try {
      final document = _firestore.doc(record.targetPath);
      switch (record.kind) {
        case TenantPendingMutationKind.expenseCreate:
          await document
              .set(<String, Object?>{
                ...record.payload,
                'createdAt': FieldValue.serverTimestamp(),
              })
              .timeout(deadline);
        // **When it was taken, beside when it arrived.** An expense needs no
        // such field - its business date is its own, and nothing shows the
        // time of one - but a return is listed at the time it was taken.
        case TenantPendingMutationKind.pendingReturnCreate:
          await document
              .set(<String, Object?>{
                ...record.payload,
                'occurredAt': Timestamp.fromDate(record.createdAt.toUtc()),
                'createdAt': FieldValue.serverTimestamp(),
              })
              .timeout(deadline);
        case TenantPendingMutationKind.expenseVoid:
          await document
              .update(<String, Object?>{
                ...record.payload,
                'voidedAt': FieldValue.serverTimestamp(),
              })
              .timeout(deadline);
        case TenantPendingMutationKind.brandingMerge:
        case TenantPendingMutationKind.printerConfigurationMerge:
          await document
              .set(<String, Object?>{
                ...record.payload,
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true))
              .timeout(deadline);
        // **A callable, because a created product may hold stock.** The
        // `stock_adjustments` record and `stock_movements` entry that account for
        // an opening balance are server-write-only, so the product and its ledger
        // entry must be written by one principal inside one transaction. That is
        // the whole reason this stopped being a `set`.
        //
        // **The envelope is rebuilt from the record, not stored in it.** The
        // queued payload is the document a device composed, which is also what
        // `_projected` merges into the cache while the record is in flight, and
        // the tenant and product come from `targetPath`. Storing the envelope
        // as well would put two shapes of one write in the queue and give the
        // overlay a second thing to read.
        //
        // The product ID is the idempotency key. It is already a digest of the
        // request ID that minted it, so a replay answers off the server's record
        // rather than stocking the shelf twice.
        case TenantPendingMutationKind.productCreate:
          await _call(
            'createProduct',
            tenantProductCreateCallablePayload(record),
          );
        // **A callable since 2026-09-14, and not because of a ledger.** A
        // category holds no quantity; what it holds is a name, and two
        // categories folding to one name make every spreadsheet naming that
        // category ambiguous - `importProducts` refuses the row rather than
        // guessing, and the only thing it can then be asked by is the document
        // ID nothing in this product shows anybody. Refusing the second one
        // means reading every other category in the collection, which a
        // Firestore rule cannot do: it may read the document being written and
        // named documents, never a query. So the check moved into the
        // transaction that writes, and `allow create, update` on `categories`
        // closed.
        //
        // The envelope is rebuilt from the record, so a category queued by the
        // build before this one drains through here unchanged.
        case TenantPendingMutationKind.categoryCreate:
          await _call('createCategory', tenantCategoryCallablePayload(record));
        case TenantPendingMutationKind.categoryRename:
          await _call('renameCategory', tenantCategoryCallablePayload(record));
        // **A callable, because retiring clears stock.** The units a retired
        // product was holding leave through a `stock_movements` entry written in
        // the same transaction as the flag, and no device may write that
        // collection - the same reason creating a product stopped being a `set`.
        // The payload is the whole request, with when it was made beside it.
        case TenantPendingMutationKind.productRetire:
          await _call('setProductRetired', tenantTimedCallablePayload(record));
        // No time: a correction moves no stock, and the audit entry it writes
        // is dated by the server, as every audit entry is.
        case TenantPendingMutationKind.productCorrect:
          await _call('updateProduct', record.payload);
        case TenantPendingMutationKind.stockAdjust:
          await _call('adjustStock', tenantTimedCallablePayload(record));
        // **A callable, and the one here a cashier may reach.** A count writes
        // nothing a client could write for itself - `stock_takes` is server-only
        // like the ledger it will be read against - and it moves no stock, which
        // is what makes opening it to every active member safe.
        //
        // The payload is the whole request, page included, so nothing is derived
        // here. The server keys its idempotency record on the take and the page
        // number, both already in it, so re-sending a page is free.
        case TenantPendingMutationKind.stockTakePage:
          await _call('submitStockTake', record.payload);
        // **Callables for the category reason**: a supplier's name is unique
        // across the business, which only the server can check.
        case TenantPendingMutationKind.supplierCreate:
          await _call('createSupplier', tenantSupplierCallablePayload(record));
        case TenantPendingMutationKind.supplierUpdate:
          await _call('updateSupplier', tenantSupplierCallablePayload(record));
        // **Callables because each moves stock and sets a cost** in one
        // transaction with the ledger entries that account for it. The payload
        // is the whole request, with when it was made beside it; the server
        // keys a delivery page's idempotency record on the delivery and the
        // page, and a batch's on the batch.
        case TenantPendingMutationKind.supplierDeliveryPage:
          await _call(
            'receiveSupplierDelivery',
            tenantTimedCallablePayload(record),
          );
        case TenantPendingMutationKind.productionComplete:
          await _call('completeProduction', tenantTimedCallablePayload(record));
        // **Callables because one number is one customer**, which only the
        // server can check across the business.
        case TenantPendingMutationKind.customerCreate:
          await _call('createCustomer', tenantCustomerCallablePayload(record));
        case TenantPendingMutationKind.customerUpdate:
          await _call('updateCustomer', tenantCustomerCallablePayload(record));
        // The payload is the whole request. The server keys its idempotency
        // record on the request ID inside it, so a replay sends one receipt.
        case TenantPendingMutationKind.whatsappReceiptRequest:
          await _call('sendWhatsappReceipt', record.payload);
        case TenantPendingMutationKind.emailReceiptRequest:
          await _call('sendEmailReceipt', record.payload);
        // The request without what the queue keeps to confirm it by: the
        // server reads the day from the shift and the cashier from the call.
        case TenantPendingMutationKind.customerPayment:
          await _call('recordCustomerPayment', <String, Object?>{
            for (final key in const <String>[
              'tenantId',
              'paymentId',
              'customerId',
              'amountMinor',
              'tender',
              'shiftId',
            ])
              key: record.payload[key],
          });
      }
      return const TenantMutationSubmissionResult(
        TenantMutationSubmissionOutcome.committed,
      );
    } on TimeoutException {
      return const TenantMutationSubmissionResult(
        TenantMutationSubmissionOutcome.uncertain,
        'write_timeout',
      );
    } on FirebaseException catch (error) {
      if (_settledAnyway(record, error)) {
        return const TenantMutationSubmissionResult(
          TenantMutationSubmissionOutcome.committed,
        );
      }
      return TenantMutationSubmissionResult(
        _rejectedCodes.contains(error.code)
            ? TenantMutationSubmissionOutcome.rejected
            : TenantMutationSubmissionOutcome.uncertain,
        error.code,
      );
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'sync.mutation_submit',
      );
      return const TenantMutationSubmissionResult(
        TenantMutationSubmissionOutcome.uncertain,
        'unknown_error',
      );
    }
  }

  Future<void> _call(String name, Map<String, Object?> payload) =>
      traceServerCall(
        name,
        () => _functions
            .httpsCallable(name)
            .call<Object?>(payload)
            .timeout(deadline),
      );

  /// Whether a refusal means the change is in place regardless.
  ///
  /// **`updateProduct` refuses a request that changes nothing**, and a queued
  /// correction can reach that state honestly: the same edit may have been made
  /// from another till while this one was offline. The device asked for a
  /// product to hold certain values and it holds them. Reporting that as a
  /// rejection would take a correct value off the screen and tell a shopkeeper
  /// their edit failed, which is false twice over.
  ///
  /// Deliberately narrow. `already-exists` is *not* here: that one means this
  /// request ID settled a **different** payload, which is a real conflict and
  /// has to be seen.
  bool _settledAnyway(
    TenantPendingMutationRecord record,
    FirebaseException error,
  ) =>
      record.kind == TenantPendingMutationKind.productCorrect &&
      error.code == 'failed-precondition' &&
      (error.message ?? '').contains('already holds every value');
}
