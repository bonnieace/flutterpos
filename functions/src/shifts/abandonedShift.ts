import {FieldValue, getFirestore, Transaction} from "firebase-admin/firestore";
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
} from "../core/validation";
import {normalizeReason} from "../operations/domain";

/**
 * Closing a shift whose own cashier no longer can.
 *
 * **The gap this fills was total.** `firestore.rules` lets a staff member close
 * only their own shift, and only while `activeStaff` holds. Deactivate someone
 * mid-shift and both halves fail at once: they cannot close it because they are
 * no longer active, and nobody else can close it because it is not theirs. The
 * shift stayed `open` for ever, its business date never reconciled cleanly, and
 * the only remedy was an edit to the database.
 *
 * **Deliberately narrow: only a shift nobody can close.** The actor must be an
 * owner or administrator, and the shift's own cashier must *not* be an active
 * member of the business. An active cashier's open shift is still theirs -
 * closing it from here would take a live till away mid-sale, and the device
 * recovery path already covers the case where they have lost the installation
 * that opened it.
 *
 * **It declares nothing and claims nothing.** The closing summary is written as
 * `closedWithoutEvidence`, exactly as the device's own recovery close is,
 * because an administrator at a keyboard has not counted the drawer and no
 * amount of server access can tell them what was in it. Reconciliation reads
 * that marker and reports the shift as unverifiable rather than inventing a
 * variance against zeros - see `compareShiftTenders` and `verifyShiftExpectation`.
 *
 * Late sales are unaffected: the sale rule deliberately accepts a sale filed
 * against a closed shift, so a deactivated cashier's unsynced sales still land.
 */

/** Who may close a shift that is not theirs. */
export const ABANDONED_SHIFT_CLOSE_ROLES = ["owner", "admin"] as const;

interface CloseAbandonedShiftRequest {
  tenantId?: unknown;
  shiftId?: unknown;
  reason?: unknown;
  requestId?: unknown;
}

export interface CloseAbandonedShiftResponse {
  tenantId: string;
  shiftId: string;
  staffId: string;
  businessDate: string;
  closureId: string;
}

/** The fields this path reads from `tenants/{tenantId}/shifts/{shiftId}`. */
interface OpenShiftFields {
  shiftId?: unknown;
  tenantId?: unknown;
  staffId?: unknown;
  businessDate?: unknown;
  status?: unknown;
}

/**
 * Proves the shift is this tenant's, open, and describes itself coherently.
 *
 * A document that disagrees with its own path is refused rather than closed:
 * the closure record names a staff member and a business date, and both have to
 * be the shift's own or the record is a fiction.
 */
export function readOpenShift(
  tenantId: string,
  shiftId: string,
  shift: OpenShiftFields | undefined
): {staffId: string; businessDate: string} {
  if (shift === undefined) {
    throw new HttpsError("not-found", "That shift does not exist.");
  }
  if (shift.shiftId !== shiftId || shift.tenantId !== tenantId) {
    throw new HttpsError("failed-precondition", "The shift does not match its own path.");
  }
  if (shift.status !== "open") {
    throw new HttpsError("failed-precondition", "That shift is not open.");
  }
  const staffId = shift.staffId;
  const businessDate = shift.businessDate;
  if (typeof staffId !== "string" || staffId.length === 0) {
    throw new HttpsError("failed-precondition", "The shift names no cashier.");
  }
  if (typeof businessDate !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(businessDate)) {
    throw new HttpsError("failed-precondition", "The shift names no business date.");
  }
  return {staffId, businessDate};
}

/**
 * Whether the shift's own cashier could still close it themselves.
 *
 * **This is the whole authorization argument.** An active member's open shift
 * is not abandoned, whatever an administrator believes about it, and the answer
 * has to come from the canonical staff record inside the same transaction so a
 * reactivation cannot race the closure.
 */
export function cashierCanStillClose(
  exists: boolean,
  status: unknown
): boolean {
  // **An absent staff record cannot close anything**, so it counts as
  // abandoned - that is the deleted-membership case, not a reason to refuse
  // the only recovery there is. Any status but `active` is the same answer,
  // rather than an allowlist of the ones that are not: a status this build has
  // never heard of must not be read as permission to keep trading.
  return exists && status === "active";
}

async function cashierCanStillCloseIn(
  transaction: Transaction,
  tenantRef: FirebaseFirestore.DocumentReference,
  staffId: string
): Promise<boolean> {
  const snapshot = await transaction.get(tenantRef.collection("staff").doc(staffId));
  return cashierCanStillClose(snapshot.exists, snapshot.get("status"));
}

export const closeAbandonedShift = onCall<
  CloseAbandonedShiftRequest,
  Promise<CloseAbandonedShiftResponse>
>(async (
  request: CallableRequest<CloseAbandonedShiftRequest>
): Promise<CloseAbandonedShiftResponse> => {
  const data = requireObject(request.data);
  const tenantId = requireDocumentId(data.tenantId, "tenantId");
  const shiftId = requireDocumentId(data.shiftId, "shiftId");
  const reason = normalizeReason(data.reason);
  const requestId = requireRequestId(data.requestId);
  const db = getFirestore();

  // Authorize before consulting the idempotency cache, then again inside the
  // transaction so a role change cannot race the closure.
  const actor = await requireTenantMember(
    db,
    request,
    tenantId,
    ABANDONED_SHIFT_CLOSE_ROLES
  );
  const identity = buildIdempotencyIdentity(
    actor.uid,
    "closeAbandonedShift",
    tenantId,
    requestId
  );
  const closureId = `as_${identity.documentId.slice(0, 40)}`;

  return runIdempotentFirestoreTransaction(db, {
    actorUid: actor.uid,
    operation: "closeAbandonedShift",
    tenantId,
    requestId,
    input: {shiftId, reason},
  }, async (transaction) => {
    const currentActor = await requireTenantMember(
      db,
      request,
      tenantId,
      ABANDONED_SHIFT_CLOSE_ROLES,
      transaction
    );
    const tenantRef = db.collection("tenants").doc(tenantId);
    const shiftRef = tenantRef.collection("shifts").doc(shiftId);
    const shiftSnapshot = await transaction.get(shiftRef);
    const shift = shiftSnapshot.exists ?
      shiftSnapshot.data() as OpenShiftFields : undefined;
    const {staffId, businessDate} = readOpenShift(tenantId, shiftId, shift);

    if (await cashierCanStillCloseIn(transaction, tenantRef, staffId)) {
      throw new HttpsError(
        "failed-precondition",
        "That cashier is still active and can close their own shift."
      );
    }

    // **Zero under the marker, and the marker is the point.** Nobody here
    // counted the drawer, so no figure may be claimed; `closedWithoutEvidence`
    // is what stops reconciliation reading the zeros as a shift that took
    // nothing. `closingCashMinor` is written because the shape requires a
    // number, not because it asserts one.
    transaction.update(shiftRef, {
      status: "closed",
      endTime: FieldValue.serverTimestamp(),
      closingCashMinor: 0,
      closingCash: 0,
      totalSalesMinor: 0,
      totalSales: 0,
      transactionCount: 0,
      closedWithoutEvidence: true,
      abandonedClosureId: closureId,
    });

    transaction.create(tenantRef.collection("audit_logs").doc(closureId), {
      eventType: "abandoned_shift_closed",
      tenantId,
      shiftId,
      staffId,
      businessDate,
      closureId,
      // The one property that makes this path safe to expose: it can end a
      // shift and it can never state what the drawer held.
      declaresCountedCash: false,
      reason,
      actorUid: currentActor.uid,
      requestId,
      createdAt: FieldValue.serverTimestamp(),
    });

    return {tenantId, shiftId, staffId, businessDate, closureId};
  });
});
