import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {requireTenantMember} from "../core/authorization";
import {requireDeviceInstant} from "../core/deviceTime";
import {
  buildIdempotencyIdentity,
  runIdempotentFirestoreTransaction,
} from "../core/idempotency";
import {
  requireDocumentId,
  requireObject,
  requireRequestId,
} from "../core/validation";
import {
  addStockQuantity,
  assertAdjustmentDirection,
  normalizeReason,
  requireQuantityDelta,
  requireStockAdjustmentType,
  requireStoredQuantity,
} from "./domain";

interface AdjustStockRequest {
  tenantId?: unknown;
  productId?: unknown;
  quantityDelta?: unknown;
  type?: unknown;
  reason?: unknown;
  requestId?: unknown;
  occurredAtMs?: unknown;
}

export interface AdjustStockResponse {
  adjustmentId: string;
  productId: string;
  previousQuantity: number;
  quantity: number;
  quantityDelta: number;
}

const STOCK_MANAGEMENT_ROLES = ["owner", "admin", "manager"] as const;

export const adjustStock = onCall<AdjustStockRequest, Promise<AdjustStockResponse>>(
  async (request: CallableRequest<AdjustStockRequest>): Promise<AdjustStockResponse> => {
    const data = requireObject(request.data);
    const tenantId = requireDocumentId(data.tenantId, "tenantId");
    const productId = requireDocumentId(data.productId, "productId");
    const quantityDelta = requireQuantityDelta(data.quantityDelta);
    const type = requireStockAdjustmentType(data.type);
    assertAdjustmentDirection(type, quantityDelta);
    const reason = normalizeReason(data.reason);
    const requestId = requireRequestId(data.requestId);
    // When the adjustment was made on the device, which may be long before it
    // arrived. Not part of the fingerprint: a replay of one request carries the
    // same time, and a retry that somehow did not must still settle off the record.
    const occurredAt = requireDeviceInstant(data.occurredAtMs, "occurredAtMs");
    const db = getFirestore();

    // Authorize before consulting the idempotency cache, then repeat inside the
    // transaction so a lifecycle change cannot race the inventory mutation.
    const actor = await requireTenantMember(db, request, tenantId, STOCK_MANAGEMENT_ROLES);
    const identity = buildIdempotencyIdentity(
      actor.uid,
      "adjustStock",
      tenantId,
      requestId
    );
    const adjustmentId = `sa_${identity.documentId.slice(0, 40)}`;

    return runIdempotentFirestoreTransaction(db, {
      actorUid: actor.uid,
      operation: "adjustStock",
      tenantId,
      requestId,
      input: {productId, quantityDelta, type, reason},
    }, async (transaction) => {
      const currentActor = await requireTenantMember(
        db,
        request,
        tenantId,
        STOCK_MANAGEMENT_ROLES,
        transaction
      );
      const tenantRef = db.collection("tenants").doc(tenantId);
      const productRef = tenantRef.collection("products").doc(productId);
      const productSnapshot = await transaction.get(productRef);
      if (!productSnapshot.exists) {
        throw new HttpsError("not-found", "The product does not exist in this tenant.");
      }
      const previousQuantity = requireStoredQuantity(productSnapshot.get("quantity"));
      const quantity = addStockQuantity(previousQuantity, quantityDelta);
      const adjustmentRef = tenantRef.collection("stock_adjustments").doc(adjustmentId);
      const movementRef = productRef.collection("stock_movements").doc(adjustmentId);
      const auditRef = tenantRef.collection("audit_logs").doc(adjustmentId);
      const immutableRecord = {
        tenantId,
        productId,
        sourceType: "manual_adjustment",
        adjustmentType: type,
        quantityDelta,
        previousQuantity,
        quantityAfter: quantity,
        reason,
        actorUid: currentActor.uid,
        requestId,
        occurredAt,
        createdAt: FieldValue.serverTimestamp(),
      };

      transaction.update(productRef, {
        quantity,
        updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.create(adjustmentRef, immutableRecord);
      transaction.create(movementRef, {
        ...immutableRecord,
        movementId: adjustmentId,
        recordedAt: FieldValue.serverTimestamp(),
      });
      transaction.create(auditRef, {
        eventType: "stock_adjusted",
        tenantId,
        productId,
        adjustmentId,
        quantityDelta,
        adjustmentType: type,
        actorUid: currentActor.uid,
        requestId,
        createdAt: FieldValue.serverTimestamp(),
      });
      return {adjustmentId, productId, previousQuantity, quantity, quantityDelta};
    });
  }
);
