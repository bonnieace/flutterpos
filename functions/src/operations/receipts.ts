import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {requireTenantMember} from "../core/authorization";
import {
  buildIdempotencyIdentity,
  runIdempotentFirestoreTransaction,
} from "../core/idempotency";
import {
  requireDocumentId,
  requireObject,
  requireRequestId,
  requireString,
} from "../core/validation";

interface RecordReceiptReprintRequest {
  tenantId?: unknown;
  saleId?: unknown;
  receiptNumber?: unknown;
  requestId?: unknown;
}

export interface RecordReceiptReprintResponse {
  auditId: string;
  saleId: string;
  receiptNumber: string;
}

/**
 * Who may put a second copy of a receipt on paper.
 *
 * The same three roles that verify a return and adjust stock, and for the same
 * reason `checkout_print_jobs.dart` gives for making a reprint a separate act
 * at all: a duplicate receipt is a cash-handling problem rather than a
 * convenience. A cashier can ring a sale up and print its one receipt; asking
 * for another one is a supervisor's decision.
 */
const RECEIPT_REPRINT_ROLES = ["owner", "admin", "manager"] as const;

/**
 * `CT-1E6-20260905-0004`, and it is `checkoutReceiptNumberPattern` verbatim.
 *
 * **Copied rather than invented, because inventing it broke every reprint.**
 * The first version of this guessed a hyphenated date - `-2026-09-05-` - where
 * the format packs it as `20260905`, so no real receipt ever matched and the
 * callable answered `invalid-argument` to all of them. The client turned that
 * into "that sale is not in this business", about a sale the person was looking
 * at. If `checkout_receipt.dart` ever changes this shape, this line changes
 * with it.
 */
export const RECEIPT_NUMBER = /^CT-[0-9A-F]{3}-\d{8}-\d{4,6}$/;

/**
 * Records that a receipt was reprinted, and refuses if it cannot.
 *
 * **The audit line is the whole function.** `docs/printer_transport.md` §7 puts
 * `receipt_reprinted` beside `stock_adjusted` and
 * `return_verified_stock_restored`, and `audit_log.dart` states that server code
 * is the only writer of `audit_logs` - the Rules deny the collection to every
 * client - so a reprint could not be audited from the device at all. The client
 * awaits this before it queues a single byte: an audit that fails is a reprint
 * that does not happen.
 *
 * **It prints nothing and cannot.** The printer is on the shop's own network and
 * the paper comes out of the device that asked; this is the record that it did.
 *
 * The sale must exist and must belong to this business, and the receipt number
 * must be the one that sale carries. A reprint recorded against a receipt that
 * was never issued would be worse than no record at all.
 */
export const recordReceiptReprint = onCall<
  RecordReceiptReprintRequest,
  Promise<RecordReceiptReprintResponse>
>(async (
  request: CallableRequest<RecordReceiptReprintRequest>
): Promise<RecordReceiptReprintResponse> => {
  const data = requireObject(request.data);
  const tenantId = requireDocumentId(data.tenantId, "tenantId");
  const saleId = requireDocumentId(data.saleId, "saleId");
  const receiptNumber = requireString(data.receiptNumber, "receiptNumber", {
    maxLength: 128,
  });
  if (!RECEIPT_NUMBER.test(receiptNumber)) {
    throw new HttpsError("invalid-argument", "receiptNumber is not a receipt number.");
  }
  const requestId = requireRequestId(data.requestId);
  const db = getFirestore();

  const actor = await requireTenantMember(db, request, tenantId, RECEIPT_REPRINT_ROLES);
  const identity = buildIdempotencyIdentity(
    actor.uid,
    "recordReceiptReprint",
    tenantId,
    requestId
  );
  const auditId = `rp_${identity.documentId.slice(0, 40)}`;

  return runIdempotentFirestoreTransaction(db, {
    actorUid: actor.uid,
    operation: "recordReceiptReprint",
    tenantId,
    requestId,
    input: {saleId, receiptNumber},
  }, async (transaction) => {
    const currentActor = await requireTenantMember(
      db,
      request,
      tenantId,
      RECEIPT_REPRINT_ROLES,
      transaction
    );
    const tenantRef = db.collection("tenants").doc(tenantId);
    const saleRef = tenantRef.collection("sales").doc(saleId);
    const saleSnapshot = await transaction.get(saleRef);
    if (!saleSnapshot.exists) {
      // **`failed-precondition`, deliberately not `not-found`.** A callable
      // that has never been deployed answers 404, and the client cannot tell
      // that apart from this branch - so on a device with an older backend a
      // reprint reported "that sale is not in this business" about a sale the
      // person was looking at. `not-found` is left to mean exactly one thing:
      // there is no reprint service on the other end.
      throw new HttpsError("failed-precondition", "The sale does not exist in this tenant.");
    }
    if (
      saleSnapshot.get("tenantId") !== undefined &&
      saleSnapshot.get("tenantId") !== tenantId
    ) {
      throw new HttpsError("failed-precondition", "The sale tenant identity is invalid.");
    }
    if (saleSnapshot.get("receiptNumber") !== receiptNumber) {
      throw new HttpsError(
        "failed-precondition",
        "The receipt number does not belong to that sale."
      );
    }

    transaction.create(tenantRef.collection("audit_logs").doc(auditId), {
      eventType: "receipt_reprinted",
      tenantId,
      saleId,
      receiptNumber,
      businessDate: saleSnapshot.get("businessDate") ?? null,
      actorUid: currentActor.uid,
      requestId,
      createdAt: FieldValue.serverTimestamp(),
    });
    return {auditId, saleId, receiptNumber};
  });
});
