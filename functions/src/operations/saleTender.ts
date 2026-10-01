import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {requireTenantMember} from "../core/authorization";
import {runIdempotentFirestoreTransaction} from "../core/idempotency";
import {
  requireDocumentId,
  requireObject,
  requireRequestId,
} from "../core/validation";
import {SALE_TENDERS, SaleTender} from "./domain";

/**
 * Records how a customer paid, on a sale that did not say.
 *
 * **A sale is immutable, and this is the one exception, in one direction.** The
 * till no longer preselects a payment method, so a cashier who was never told
 * how the customer paid saves a sale that names none - which is honest, and
 * useless unless somebody can answer the question afterwards. This is that
 * answer: absent becomes recorded, once.
 *
 * **It never changes a tender that is already there.** Everything downstream of
 * a sale leans on the record not moving under it - `payloadHash` attests to the
 * payload the till committed, confirmation matches against that hash, and the
 * nightly reconciliation compares a shift's sales against a drawer counted
 * once. Completing a blank is not the same act as editing money after the fact,
 * and only the first is allowed here.
 *
 * **Only the cashier who sold it.** They are the one person who was at the
 * counter, and the only one who knows the answer rather than guessing it. A
 * manager correcting somebody else's sale would be exactly the after-the-fact
 * edit the paragraph above refuses.
 *
 * **The tender it writes is not covered by `payloadHash`**, deliberately: the
 * hash attests to what the till committed and nothing else, and rewriting it
 * would break the confirmation the outbox is waiting on. `tenderSetBy` and
 * `tenderSetAt` are what keep an answer given later distinguishable from one the
 * till recorded at the counter, so no reader has to guess which it is holding.
 */
interface SetSaleTenderRequest {
  tenantId?: unknown;
  saleId?: unknown;
  requestId?: unknown;
  tender?: unknown;
}

export interface SetSaleTenderResponse {
  saleId: string;
  tender: SaleTender;
  businessDate: string;

  /** Whether this replaced a method already on the sale. */
  replaced: boolean;
}

/** The `audit_logs` ID one completed tender writes at. */
export function saleTenderAuditId(requestId: string): string {
  return `st_${requestId}`;
}

/** Every document one completed tender writes, without its timestamps. */
export interface SaleTenderPlan {
  auditId: string;
  businessDate: string;

  /** Whether this replaces a method already on the sale. */
  replaces: boolean;
  saleData: Record<string, unknown>;
  auditData: Record<string, unknown>;
  dirtyData: Record<string, unknown>;
}

/**
 * Decides what recording one tender writes, and refuses what it may not.
 *
 * Split out for the reason `planProductRetire` is: everything that decides is a
 * pure function, and the callable is the authorization and the transaction
 * around it. Timestamps are the one thing a plan cannot hold.
 */
export function planSaleTenderRecord(options: {
  tenantId: string;
  saleId: string;
  actorUid: string;
  requestId: string;
  tender: SaleTender;
  sale: {soldById?: unknown; tender?: unknown; businessDate?: unknown};

  /** Whether the shift this sale belongs to has been counted off. */
  shiftClosed: boolean;
}): SaleTenderPlan {
  const {tenantId, saleId, actorUid, requestId, tender, sale, shiftClosed} =
    options;
  if (sale.soldById !== actorUid) {
    throw new HttpsError(
      "permission-denied",
      "Only the cashier who recorded this sale can say how it was paid for."
    );
  }
  // **A credit sale's payment was decided with the sale.** What was paid and
  // what was left owing moved the customer's balance when it arrived;
  // relabelling it cash afterwards would put the debt in the drawer and leave
  // it on the customer too. Money paid later is a repayment, not a new tender.
  if (sale.tender === "credit") {
    throw new HttpsError(
      "failed-precondition",
      "This sale was on credit. Record what the customer pays back as a payment " +
      "on their account instead."
    );
  }
  // **A stored null is the same silence a missing key is** -
  // `saleTenderBucket` reads both as `unrecorded` - so both are a blank to be
  // filled rather than an answer to be changed.
  const recorded = sale.tender !== undefined && sale.tender !== null;
  // **A recorded method may be corrected, but only while its shift is open.**
  // A mis-tap is noticed at the counter, inside the shift the drawer is still
  // being filled for. Once that drawer is counted off, the split has been
  // reconciled against and changing it reaches back into settled books -
  // `tenderFiguresMoved` would reopen a difference the owner already dismissed.
  // Filling a blank is not bounded this way: it adds a figure where there was
  // none, which is what the count was already missing.
  if (recorded && shiftClosed) {
    throw new HttpsError(
      "failed-precondition",
      "This shift has been counted off, so the payment method recorded on its " +
      "sales can no longer be changed."
    );
  }
  if (recorded && sale.tender === tender) {
    throw new HttpsError(
      "failed-precondition",
      "This sale already names that payment method."
    );
  }
  // The day the sale was filed under, which is its shift's day rather than the
  // calendar's - see `CheckoutDraftService`. Reconciliation is keyed by it, so
  // a sale whose date is unreadable has nothing to re-run.
  const businessDate = sale.businessDate;
  if (typeof businessDate !== "string" || businessDate.length === 0) {
    throw new HttpsError(
      "failed-precondition",
      "This sale names no business date, so its figures cannot be rebuilt."
    );
  }
  return {
    auditId: saleTenderAuditId(requestId),
    businessDate,
    replaces: recorded,
    saleData: {tender, tenderSetBy: actorUid},
    auditData: {
      eventType: recorded ? "sale_tender_changed" : "sale_tender_recorded",
      tenantId,
      saleId,
      tender,
      // **What it was**, so the audit answers the only question anybody asks
      // of a corrected figure: what did this say before, and who changed it.
      ...(recorded ? {previousTender: sale.tender} : {}),
      businessDate,
      actorUid,
      requestId,
    },
    // **The sale trigger does not fire for this.** `mergeSaleReconciliationJob`
    // is `onDocumentCreated`, so an update reaches nothing, and
    // `registerSaleReceipt` is idempotent per sale - calling it again would do
    // nothing at all. Marking the day is what puts the corrected split in front
    // of the owner, on the next sweep.
    dirtyData: {
      tenantId,
      businessDate,
      status: "dirty",
      revision: 1,
      dirtyReason: "tender_recorded",
    },
  };
}

export const setSaleTender = onCall<
  SetSaleTenderRequest,
  Promise<SetSaleTenderResponse>
>(async (
  request: CallableRequest<SetSaleTenderRequest>
): Promise<SetSaleTenderResponse> => {
  const data = requireObject(request.data);
  const tenantId = requireDocumentId(data.tenantId, "tenantId");
  const saleId = requireDocumentId(data.saleId, "saleId");
  const requestId = requireRequestId(data.requestId);
  if (
    typeof data.tender !== "string" ||
    !(SALE_TENDERS as readonly string[]).includes(data.tender)
  ) {
    throw new HttpsError(
      "invalid-argument",
      "tender must name one of the recorded payment methods."
    );
  }
  const tender = data.tender as SaleTender;
  const db = getFirestore();

  // No role list: every active member passes here, and the sale itself decides
  // whether this caller is the one who may answer for it.
  const actor = await requireTenantMember(db, request, tenantId);

  return runIdempotentFirestoreTransaction(db, {
    actorUid: actor.uid,
    operation: "setSaleTender",
    tenantId,
    requestId,
    input: {saleId, tender},
  }, async (transaction) => {
    const currentActor = await requireTenantMember(
      db,
      request,
      tenantId,
      undefined,
      transaction
    );
    const tenantRef = db.collection("tenants").doc(tenantId);
    const saleRef = tenantRef.collection("sales").doc(saleId);
    const snapshot = await transaction.get(saleRef);
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "The sale does not exist in this tenant.");
    }
    // **The shift decides whether a recorded method may still be corrected.**
    // Read rather than trusted from the client, and read inside the
    // transaction so a close landing mid-correction cannot be raced.
    const shiftId = snapshot.get("shiftId");
    let shiftClosed = true;
    if (typeof shiftId === "string" && shiftId.length > 0) {
      const shift = await transaction.get(
        tenantRef.collection("shifts").doc(shiftId)
      );
      // An unreadable or absent shift is treated as closed: it cannot be shown
      // to be open, and the safe direction is to refuse the correction rather
      // than to allow one against a drawer that may already be counted.
      shiftClosed = !shift.exists || shift.get("endTime") !== undefined;
    }
    const plan = planSaleTenderRecord({
      tenantId,
      saleId,
      actorUid: currentActor.uid,
      requestId,
      tender,
      sale: {
        soldById: snapshot.get("soldById"),
        tender: snapshot.get("tender"),
        businessDate: snapshot.get("businessDate"),
      },
      shiftClosed,
    });

    transaction.update(saleRef, {
      ...plan.saleData,
      tenderSetAt: FieldValue.serverTimestamp(),
    });

    transaction.create(tenantRef.collection("audit_logs").doc(plan.auditId), {
      ...plan.auditData,
      createdAt: FieldValue.serverTimestamp(),
    });

    transaction.set(
      tenantRef.collection("reconciliation_dirty_days").doc(plan.businessDate),
      {
        ...plan.dirtyData,
        revision: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    return {
      saleId,
      tender,
      businessDate: plan.businessDate,
      replaced: plan.replaces,
    };
  });
});
