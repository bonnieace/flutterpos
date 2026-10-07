import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {requireTenantMember} from "../core/authorization";
import {planReturnedPoints} from "../customers/customerSale";
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
  assertReturnWithinSale,
  MAX_RETURN_LINES,
  normalizeReturnStockLines,
  requireStoredQuantity,
} from "./domain";

interface VerifyReturnRequest {
  tenantId?: unknown;
  returnId?: unknown;
  requestId?: unknown;
}

interface RestoredProduct {
  productId: string;
  quantityRestored: number;
  previousQuantity: number;
  quantity: number;
}

export interface VerifyReturnResponse {
  returnId: string;
  verificationId: string;
  restoredProducts: RestoredProduct[];
}

const RETURN_VERIFICATION_ROLES = ["owner", "admin", "manager"] as const;

export const verifyReturnAndRestoreStock = onCall<
  VerifyReturnRequest,
  Promise<VerifyReturnResponse>
>(async (request: CallableRequest<VerifyReturnRequest>): Promise<VerifyReturnResponse> => {
  const data = requireObject(request.data);
  const tenantId = requireDocumentId(data.tenantId, "tenantId");
  const returnId = requireDocumentId(data.returnId, "returnId");
  const requestId = requireRequestId(data.requestId);
  const db = getFirestore();
  const actor = await requireTenantMember(db, request, tenantId, RETURN_VERIFICATION_ROLES);
  const identity = buildIdempotencyIdentity(
    actor.uid,
    "verifyReturnAndRestoreStock",
    tenantId,
    requestId
  );
  const verificationId = `rv_${identity.documentId.slice(0, 40)}`;

  return runIdempotentFirestoreTransaction(db, {
    actorUid: actor.uid,
    operation: "verifyReturnAndRestoreStock",
    tenantId,
    requestId,
    input: {returnId},
  }, async (transaction) => {
    const currentActor = await requireTenantMember(
      db,
      request,
      tenantId,
      RETURN_VERIFICATION_ROLES,
      transaction
    );
    const tenantRef = db.collection("tenants").doc(tenantId);
    const returnRef = tenantRef.collection("returns").doc(returnId);
    const returnSnapshot = await transaction.get(returnRef);
    if (!returnSnapshot.exists) {
      throw new HttpsError("not-found", "The return does not exist in this tenant.");
    }
    const returnData = returnSnapshot.data() ?? {};
    if (returnData.tenantId !== undefined && returnData.tenantId !== tenantId) {
      throw new HttpsError("failed-precondition", "The return tenant identity is invalid.");
    }
    if (
      returnData.verified === true ||
      returnData.stockRestored === true ||
      returnData.status === "verified"
    ) {
      throw new HttpsError("failed-precondition", "This return has already been verified.");
    }
    if (returnData.status !== undefined && returnData.status !== "pending") {
      throw new HttpsError("failed-precondition", "Only a pending return can be verified.");
    }
    const lines = normalizeReturnStockLines(returnData.itemsReturned);
    const saleId = requireDocumentId(returnData.saleId, "return.saleId");
    const saleRef = tenantRef.collection("sales").doc(saleId);
    const priorVerificationsQuery = tenantRef.collection("return_verifications")
      .where("saleId", "==", saleId)
      .limit(101);
    const [saleSnapshot, priorVerifications] = await Promise.all([
      transaction.get(saleRef),
      transaction.get(priorVerificationsQuery),
    ]);
    if (!saleSnapshot.exists) {
      throw new HttpsError(
        "failed-precondition",
        "The immutable source sale for this return does not exist."
      );
    }
    if (
      saleSnapshot.get("tenantId") !== undefined &&
      saleSnapshot.get("tenantId") !== tenantId
    ) {
      throw new HttpsError("failed-precondition", "The source sale tenant identity is invalid.");
    }
    if (priorVerifications.size > 100) {
      throw new HttpsError(
        "resource-exhausted",
        "This sale has too many prior return verifications for automatic restoration."
      );
    }
    const soldLines = normalizeReturnStockLines(saleSnapshot.get("items"));
    const previousByProduct = new Map<string, number>();
    for (const document of priorVerifications.docs) {
      const products = document.get("restoredProducts");
      if (!Array.isArray(products) || products.length > MAX_RETURN_LINES) {
        throw new HttpsError("data-loss", "A prior return verification is malformed.");
      }
      products.forEach((item, index) => {
        if (!item || typeof item !== "object" || Array.isArray(item)) {
          throw new HttpsError("data-loss", "A prior restored product is malformed.");
        }
        const record = item as Record<string, unknown>;
        const productId = requireDocumentId(
          record.productId,
          `priorVerification[${index}].productId`
        );
        if (!Number.isSafeInteger(record.quantityRestored) ||
          (record.quantityRestored as number) <= 0) {
          throw new HttpsError("data-loss", "A prior restored quantity is malformed.");
        }
        const quantity = (previousByProduct.get(productId) ?? 0) +
          (record.quantityRestored as number);
        if (!Number.isSafeInteger(quantity)) {
          throw new HttpsError("data-loss", "Prior restored quantities are too large.");
        }
        previousByProduct.set(productId, quantity);
      });
    }
    const normalizedPrevious = [...previousByProduct.entries()].map(
      ([productId, quantity]) => ({productId, quantity})
    );
    assertReturnWithinSale(soldLines, lines, normalizedPrevious);
    const productRefs = lines.map((line) => tenantRef.collection("products").doc(line.productId));
    const productSnapshots = await transaction.getAll(...productRefs);
    // **Read now, written last.** A sale to a named customer earned points, and
    // a verified return gives back its share of them - planned inside this
    // read phase because no transaction may read after its first write.
    const givePointsBack = await planReturnedPoints(transaction, tenantRef, {
      saleId,
      sale: saleSnapshot.data() ?? {},
      returnId,
      lines,
    });
    const restoredProducts: RestoredProduct[] = [];
    for (let index = 0; index < lines.length; index += 1) {
      const line = lines[index];
      const snapshot = productSnapshots[index];
      if (!snapshot.exists) {
        throw new HttpsError(
          "failed-precondition",
          `Returned product ${line.productId} no longer exists.`
        );
      }
      const previousQuantity = requireStoredQuantity(snapshot.get("quantity"));
      restoredProducts.push({
        productId: line.productId,
        quantityRestored: line.quantity,
        previousQuantity,
        quantity: addStockQuantity(previousQuantity, line.quantity),
      });
    }

    for (const restored of restoredProducts) {
      const productRef = tenantRef.collection("products").doc(restored.productId);
      const movementId = `${verificationId}_${restored.productId}`;
      transaction.update(productRef, {
        quantity: restored.quantity,
        updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.create(productRef.collection("stock_movements").doc(movementId), {
        movementId,
        tenantId,
        productId: restored.productId,
        sourceType: "verified_return",
        sourceId: returnId,
        verificationId,
        quantityDelta: restored.quantityRestored,
        previousQuantity: restored.previousQuantity,
        quantityAfter: restored.quantity,
        actorUid: currentActor.uid,
        requestId,
        occurredAt: FieldValue.serverTimestamp(),
        recordedAt: FieldValue.serverTimestamp(),
        createdAt: FieldValue.serverTimestamp(),
      });
    }

    const verificationRef = tenantRef.collection("return_verifications").doc(verificationId);
    transaction.update(returnRef, {
      status: "verified",
      verified: true,
      verifiedBy: currentActor.uid,
      verifiedAt: FieldValue.serverTimestamp(),
      stockRestored: true,
      stockRestoredAt: FieldValue.serverTimestamp(),
      stockRestorationId: verificationId,
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.create(verificationRef, {
      tenantId,
      returnId,
      saleId,
      verificationId,
      restoredProducts,
      actorUid: currentActor.uid,
      requestId,
      createdAt: FieldValue.serverTimestamp(),
    });
    transaction.create(tenantRef.collection("audit_logs").doc(verificationId), {
      eventType: "return_verified_stock_restored",
      tenantId,
      returnId,
      saleId,
      verificationId,
      restoredProductCount: restoredProducts.length,
      restoredUnitCount: restoredProducts.reduce(
        (sum, item) => sum + item.quantityRestored,
        0
      ),
      actorUid: currentActor.uid,
      requestId,
      createdAt: FieldValue.serverTimestamp(),
    });
    givePointsBack?.(transaction);
    // **Deliberately does not dirty the day, and that is not an omission.**
    // Returns count against takings from the moment they are filed, and the
    // netting arithmetic is status-agnostic - so `pending` to `verified`
    // moves no financial figure at all. `mergeReturnReconciliationJob`
    // already dirtied this day when the return was created.
    //
    // Dirtying again here would regenerate the day's metrics to the identical
    // numbers, and because a revision bump changes every
    // `shift_expectations.generation`, it would re-arm verification for every
    // shift on the day and re-mint generation-keyed anomaly documents without
    // deleting the old ones. That is real churn bought for no change.
    //
    // What verification *does* change is stock, and stock is reconciled by
    // the scheduled and manual full runs rather than by a sale-trigger dirty
    // job - which skips the stock phase outright. So nothing is missed.
    //
    // **A reject or cancel transition would be different**: a return that
    // stops counting changes the net figures, and whatever implements that
    // must dirty the day.
    return {returnId, verificationId, restoredProducts};
  });
});
