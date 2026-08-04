import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {CallableRequest, onCall} from "firebase-functions/v2/https";
import {requireTenantMember} from "../core/authorization";
import {
  buildIdempotencyIdentity,
  runIdempotentFirestoreTransaction,
} from "../core/idempotency";
import {
  requireDocumentId,
  requireObject,
  requireRequestId,
} from "../core/validation";
import {normalizeReason} from "../operations/domain";
import {
  AMENDED_VERIFICATION_STATUS,
  ClosedShiftFields,
  ShiftExpectationFields,
  clearsRecordedAnomaly,
  planShiftSummaryAmendment,
  readClosedShiftSummary,
} from "./amendment";

interface AmendShiftSummaryRequest {
  tenantId?: unknown;
  shiftId?: unknown;
  reason?: unknown;
  requestId?: unknown;
}

export interface AmendShiftSummaryResponse {
  amendmentId: string;
  shiftId: string;
  businessDate: string;
  previousTotalSalesMinor: number;
  previousTransactionCount: number;
  totalSalesMinor: number;
  transactionCount: number;
  salesVarianceMinor: number;
  transactionVariance: number;

  /** The listed difference this amendment removed, or null if none was listed. */
  clearedAnomalyId: string | null;
}

/**
 * Owner and administrator only, deliberately narrower than the
 * owner/admin/manager set that *reads* the difference this resolves.
 *
 * Amending a terminal record of what a cashier is accountable for is governance
 * rather than reporting, so it matches the set that may spend the business's
 * manual reconciliation allowance and that reads `audit_logs`. A manager may see
 * that a shift disagrees with its sales without being able to rewrite the shift.
 */
const SHIFT_AMENDMENT_ROLES = ["owner", "admin"] as const;

/**
 * Corrects one closed shift's summary to the total its own sales prove.
 *
 * The caller chooses the shift and states a reason; it cannot choose a figure.
 * The amended total is read from the settled `shift_expectations` record the
 * metrics writer derived from the immutable sales, so the only reachable outcome
 * is a shift that agrees with them.
 *
 * `closingCashMinor` and `closingCash` are never written. The counted cash is a
 * physical count of a drawer, and the record says so in `mutatesCountedCash`, so
 * this path can correct a bookkeeping figure but can never erase a cash
 * discrepancy.
 */
export const amendShiftSummary = onCall<
  AmendShiftSummaryRequest,
  Promise<AmendShiftSummaryResponse>
>(async (
  request: CallableRequest<AmendShiftSummaryRequest>
): Promise<AmendShiftSummaryResponse> => {
  const data = requireObject(request.data);
  const tenantId = requireDocumentId(data.tenantId, "tenantId");
  const shiftId = requireDocumentId(data.shiftId, "shiftId");
  const reason = normalizeReason(data.reason);
  const requestId = requireRequestId(data.requestId);
  const db = getFirestore();

  // Authorize before consulting the idempotency cache, then again inside the
  // transaction so a role or membership change cannot race the amendment.
  const actor = await requireTenantMember(db, request, tenantId, SHIFT_AMENDMENT_ROLES);
  const identity = buildIdempotencyIdentity(
    actor.uid,
    "amendShiftSummary",
    tenantId,
    requestId
  );
  const amendmentId = `sm_${identity.documentId.slice(0, 40)}`;

  return runIdempotentFirestoreTransaction(db, {
    actorUid: actor.uid,
    operation: "amendShiftSummary",
    tenantId,
    requestId,
    input: {shiftId, reason},
  }, async (transaction) => {
    const currentActor = await requireTenantMember(
      db,
      request,
      tenantId,
      SHIFT_AMENDMENT_ROLES,
      transaction
    );
    const tenantRef = db.collection("tenants").doc(tenantId);
    const shiftRef = tenantRef.collection("shifts").doc(shiftId);
    const shiftSnapshot = await transaction.get(shiftRef);
    const shift = shiftSnapshot.exists ?
      shiftSnapshot.data() as ClosedShiftFields : undefined;

    // The expectation is addressed by the shift's *own* business date, so no
    // caller can point the amendment at another day's aggregate. Reading the
    // shift first is what makes that possible.
    const observed = readClosedShiftSummary(tenantId, shiftId, shift);
    const expectationRef = tenantRef.collection("shift_expectations")
      .doc(observed.expectationId);
    const expectationSnapshot = await transaction.get(expectationRef);
    const amendment = planShiftSummaryAmendment({
      tenantId,
      shiftId,
      shift,
      expectation: expectationSnapshot.exists ?
        expectationSnapshot.data() as ShiftExpectationFields : undefined,
    });

    const anomalyRef = tenantRef.collection("reconciliation_anomalies")
      .doc(amendment.anomalyId);
    const anomalySnapshot = await transaction.get(anomalyRef);
    const clearsAnomaly = clearsRecordedAnomaly(
      amendment,
      anomalySnapshot.exists ? anomalySnapshot.data() : undefined,
      tenantId
    );

    // The two representations of the same money are written together from one
    // figure, so a shift can never be left half-amended. The counted cash is
    // absent on purpose and must stay absent.
    transaction.update(shiftRef, {
      totalSales: amendment.totalSales,
      totalSalesMinor: amendment.totalSalesMinor,
      transactionCount: amendment.transactionCount,
      summaryAmendmentId: amendmentId,
      summaryAmendedGeneration: amendment.generation,
      summaryAmendedAt: FieldValue.serverTimestamp(),
      summaryAmendmentCount: FieldValue.increment(1),
    });

    // Verification already happened in this transaction: both figures were read
    // and the shift now holds the expected one by construction. Settling the
    // record here rather than marking it pending keeps it truthful, and makes a
    // second amendment of the same generation impossible instead of merely
    // pointless.
    transaction.update(expectationRef, {
      needsVerification: false,
      verificationStatus: AMENDED_VERIFICATION_STATUS,
      amendmentId,
      amendedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    if (clearsAnomaly) {
      // The list is named for the differences that are still open, so a resolved
      // one is removed from it. Nothing is lost: the immutable record below and
      // the audit entry beside it both carry the difference, its direction, and
      // the figures on either side of it.
      transaction.delete(anomalyRef);
    }

    transaction.create(tenantRef.collection("shift_amendments").doc(amendmentId), {
      amendmentId,
      tenantId,
      shiftId,
      staffId: amendment.staffId,
      businessDate: amendment.businessDate,
      sourceType: "reconciliation_shift_variance",
      expectationId: amendment.expectationId,
      expectationGeneration: amendment.generation,
      previousTotalSales: amendment.previousTotalSales,
      previousTotalSalesMinor: amendment.previousTotalSalesMinor,
      previousTransactionCount: amendment.previousTransactionCount,
      previousRepresentationsAgreed: amendment.previousRepresentationsAgreed,
      totalSales: amendment.totalSales,
      totalSalesMinor: amendment.totalSalesMinor,
      transactionCount: amendment.transactionCount,
      salesVarianceMinor: amendment.salesVarianceMinor,
      transactionVariance: amendment.transactionVariance,
      clearedAnomalyId: clearsAnomaly ? amendment.anomalyId : null,
      // The one property that makes this path safe to expose at all.
      mutatesCountedCash: false,
      reason,
      actorUid: currentActor.uid,
      requestId,
      createdAt: FieldValue.serverTimestamp(),
    });

    transaction.create(tenantRef.collection("audit_logs").doc(amendmentId), {
      eventType: "shift_summary_amended",
      tenantId,
      shiftId,
      staffId: amendment.staffId,
      businessDate: amendment.businessDate,
      amendmentId,
      salesVarianceMinor: amendment.salesVarianceMinor,
      transactionVariance: amendment.transactionVariance,
      mutatesCountedCash: false,
      actorUid: currentActor.uid,
      requestId,
      createdAt: FieldValue.serverTimestamp(),
    });

    return {
      amendmentId,
      shiftId,
      businessDate: amendment.businessDate,
      previousTotalSalesMinor: amendment.previousTotalSalesMinor,
      previousTransactionCount: amendment.previousTransactionCount,
      totalSalesMinor: amendment.totalSalesMinor,
      transactionCount: amendment.transactionCount,
      salesVarianceMinor: amendment.salesVarianceMinor,
      transactionVariance: amendment.transactionVariance,
      clearedAnomalyId: clearsAnomaly ? amendment.anomalyId : null,
    };
  });
});
