import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {CallableRequest, onCall} from "firebase-functions/v2/https";
import {HttpsError} from "firebase-functions/v2/https";
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

interface AcknowledgeAnomalyRequest {
  tenantId?: unknown;
  anomalyId?: unknown;
  reason?: unknown;
  requestId?: unknown;
}

export interface AcknowledgeAnomalyResponse {
  /** Echoed so a client can prove the server acted on the business it asked
   *  about before it labels that business's screen with the answer. */
  tenantId: string;
  anomalyId: string;
  anomalyType: string;

  /** Whether this call was the one that acknowledged it, or it already was. */
  alreadyAcknowledged: boolean;
}

/**
 * Owner and administrator only, deliberately narrower than the
 * owner/admin/manager set that *reads* the difference this settles.
 *
 * Accepting a difference is governance rather than reporting: it is a person
 * putting their name to the statement that the shop looked at a discrepancy and
 * is content with it. It matches the set `amendShiftSummary` requires for the
 * same reason.
 */
const ANOMALY_ACKNOWLEDGEMENT_ROLES = ["owner", "admin"] as const;

/**
 * Records that an owner has seen a difference and accepts it.
 *
 * **It never deletes and never writes a figure.** A tender variance is a real
 * difference between money a person says they hold and money the sales say they
 * took; there is no figure to correct it to, and a path that made it disappear
 * would be the hole in the control this whole surface exists to be. So the
 * record stays, with its numbers untouched, and gains only who accepted it,
 * when, and why.
 *
 * Distinct from `amendShiftSummary`, which corrects a bookkeeping total to the
 * one the immutable sales prove. That is a wrong figure being fixed. This is a
 * right figure being accepted.
 *
 * Acknowledging twice is not an error. It reports `alreadyAcknowledged` and
 * changes nothing, so a retry after an ambiguous outcome is safe.
 */
export const acknowledgeReconciliationAnomaly = onCall<
  AcknowledgeAnomalyRequest,
  Promise<AcknowledgeAnomalyResponse>
>(async (
  request: CallableRequest<AcknowledgeAnomalyRequest>
): Promise<AcknowledgeAnomalyResponse> => {
  const data = requireObject(request.data);
  const tenantId = requireDocumentId(data.tenantId, "tenantId");
  const anomalyId = requireDocumentId(data.anomalyId, "anomalyId");
  const reason = normalizeReason(data.reason);
  const requestId = requireRequestId(data.requestId);
  const db = getFirestore();

  // Authorized before the idempotency cache is consulted and again inside the
  // transaction, so a role change cannot race the acknowledgement.
  const actor = await requireTenantMember(
    db,
    request,
    tenantId,
    ANOMALY_ACKNOWLEDGEMENT_ROLES
  );
  const identity = buildIdempotencyIdentity(
    actor.uid,
    "acknowledgeReconciliationAnomaly",
    tenantId,
    requestId
  );
  const acknowledgementId = `ra_${identity.documentId.slice(0, 40)}`;

  return runIdempotentFirestoreTransaction(db, {
    actorUid: actor.uid,
    operation: "acknowledgeReconciliationAnomaly",
    tenantId,
    requestId,
    input: {anomalyId, reason},
  }, async (transaction) => {
    const currentActor = await requireTenantMember(
      db,
      request,
      tenantId,
      ANOMALY_ACKNOWLEDGEMENT_ROLES,
      transaction
    );
    const tenantRef = db.collection("tenants").doc(tenantId);
    const anomalyRef = tenantRef.collection("reconciliation_anomalies")
      .doc(anomalyId);
    const summaryRef = tenantRef.collection("reconciliation_summary")
      .doc("open_differences");
    const [anomalySnapshot, summarySnapshot] = await transaction.getAll(
      anomalyRef,
      summaryRef
    );
    if (!anomalySnapshot.exists) {
      throw new HttpsError(
        "not-found",
        "That difference is no longer recorded, so there is nothing to accept."
      );
    }
    // The document carries its own tenant, and it is checked rather than
    // trusted: an id is a caller-supplied string, and a path built from one
    // must still prove it landed where the caller was authorized.
    if (anomalySnapshot.get("tenantId") !== tenantId) {
      throw new HttpsError(
        "permission-denied",
        "That difference belongs to another business."
      );
    }
    const anomalyType = anomalySnapshot.get("anomalyType");
    if (typeof anomalyType !== "string") {
      throw new HttpsError(
        "failed-precondition",
        "That difference does not say what kind it is and cannot be accepted."
      );
    }
    if (anomalySnapshot.get("resolution") === "acknowledged") {
      return {tenantId, anomalyId, anomalyType, alreadyAcknowledged: true};
    }

    transaction.set(anomalyRef, {
      resolution: "acknowledged",
      resolutionNote: reason,
      resolutionRequestId: requestId,
      resolvedBy: currentActor.uid,
      resolvedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});

    // **Adjusted rather than recomputed.** The authority is the recount every
    // completed run does; this is so the badge moves when the person acts
    // rather than at the next nightly sweep. It is clamped on read, and a run
    // repairs any drift.
    if (summarySnapshot.exists) {
      transaction.update(summaryRef, {
        openCount: FieldValue.increment(-1),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    transaction.create(tenantRef.collection("audit_logs").doc(acknowledgementId), {
      eventType: "reconciliation_anomaly_acknowledged",
      tenantId,
      anomalyId,
      anomalyType,
      shiftId: anomalySnapshot.get("shiftId") ?? null,
      businessDate: anomalySnapshot.get("businessDate") ?? null,
      reason,
      // Stated on the record so nothing has to be inferred from its absence:
      // accepting a difference moves no money and rewrites no shift.
      mutatesShift: false,
      mutatesCountedCash: false,
      actorUid: currentActor.uid,
      requestId,
      createdAt: FieldValue.serverTimestamp(),
    });

    return {tenantId, anomalyId, anomalyType, alreadyAcknowledged: false};
  });
});
