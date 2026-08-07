import {
  DocumentReference,
  FieldValue,
  Firestore,
  Transaction,
  getFirestore,
} from "firebase-admin/firestore";
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
import {
  EditableProductField,
  PRODUCT_UPDATE_ROLES,
  ProductUpdateInput,
  StoredProductFields,
  assertProductUpdateAuthorized,
  planProductUpdate,
  readProductUpdateInput,
} from "./productUpdate";

interface UpdateProductRequest {
  tenantId?: unknown;
  productId?: unknown;
  name?: unknown;
  sku?: unknown;
  price?: unknown;
  categoryId?: unknown;
  requestId?: unknown;
}

export interface UpdateProductResponse {
  updateId: string;

  /**
   * The business the correction was applied in.
   *
   * Echoed so a client can prove the server acted on the business it asked about
   * before it labels that business's catalog with the answer.
   */
  tenantId: string;

  productId: string;

  /** Which of name, sku, price, and categoryId actually moved. */
  changedFields: EditableProductField[];

  /** What the product holds now, in the shape the till reads it. */
  name: string;
  sku: string;
  price: number;
  priceMinor: number;
  categoryId: string;
}

/**
 * Applies one planned correction and records it.
 *
 * Split out from the callable so it can be exercised against an in-memory
 * Firestore: the two writes and their ordering are the whole of what this
 * operation does to a business's data, and the callable around them is
 * validation, authorization, and the shared idempotency wrapper, each of which
 * already has its own coverage.
 *
 * Both reads happen before either write, which Firestore requires of a
 * transaction and the double enforces.
 */
export async function applyProductUpdate(
  db: Firestore,
  transaction: Transaction,
  options: {
    tenantId: string;
    productId: string;
    updateId: string;
    requestId: string;
    actorUid: string;
    requested: ProductUpdateInput;
  }
): Promise<UpdateProductResponse> {
  const tenantRef = db.collection("tenants").doc(options.tenantId);
  const productRef = tenantRef.collection("products").doc(options.productId);
  const categoryRef = options.requested.categoryId === undefined ?
    undefined :
    tenantRef.collection("categories").doc(options.requested.categoryId);

  const refs: DocumentReference[] = categoryRef ?
    [productRef, categoryRef] : [productRef];
  const [productSnapshot, categorySnapshot] = await transaction.getAll(...refs);

  // A category is checked whenever one is named, not only when it changes. The
  // client's create surface can only file a product under a category it read
  // from this same business; nothing on the server enforced that, and a product
  // filed under a category that does not exist is invisible to every grouped
  // catalog surface without being unreadable, which is the worst kind of wrong.
  if (categoryRef && !categorySnapshot.exists) {
    throw new HttpsError(
      "failed-precondition",
      "The category does not exist in this business."
    );
  }

  const plan = planProductUpdate({
    product: productSnapshot.exists ?
      productSnapshot.data() as StoredProductFields : undefined,
    requested: options.requested,
  });

  // Only the fields that moved, plus the server's own timestamp. `quantity` is
  // absent by construction: the plan can never name it.
  transaction.update(productRef, {
    ...plan.documentUpdate,
    updatedAt: FieldValue.serverTimestamp(),
  });

  transaction.create(tenantRef.collection("audit_logs").doc(options.updateId), {
    eventType: "product_updated",
    tenantId: options.tenantId,
    productId: options.productId,
    updateId: options.updateId,
    changedFields: plan.changedFields,
    // The before and after of every field that moved. Without this a price
    // correction would be the one money-changing operation in this system that
    // leaves no record of what it replaced.
    changes: plan.changes,
    // The property that makes this path safe to expose at all.
    mutatesQuantity: false,
    actorUid: options.actorUid,
    requestId: options.requestId,
    createdAt: FieldValue.serverTimestamp(),
  });

  return {
    updateId: options.updateId,
    tenantId: options.tenantId,
    productId: options.productId,
    changedFields: [...plan.changedFields],
    name: plan.product.name,
    sku: plan.product.sku,
    price: plan.product.price,
    priceMinor: plan.product.priceMinor,
    categoryId: plan.product.categoryId,
  };
}

/**
 * Corrects one product's name, code, price, or category.
 *
 * This is the only way a descriptive field on a product ever changes. It exists
 * as a callable rather than as a wider Firestore rule for three reasons, all of
 * which live in `productUpdate.ts`: the Admin SDK bypasses rules so the tight
 * `allow update` clause protecting stock stays untouched, a price change is
 * money and is therefore recorded with its before and after, and only the server
 * can prove a price survives the till's minor-unit conversion.
 *
 * It writes no `stock_movements` entry and no `stock_adjustments` record because
 * it moves no stock. `quantity` is never named, never written, and refused if a
 * payload so much as mentions it.
 */
export const updateProduct = onCall<
  UpdateProductRequest,
  Promise<UpdateProductResponse>
>(async (
  request: CallableRequest<UpdateProductRequest>
): Promise<UpdateProductResponse> => {
  const data = requireObject(request.data);
  const tenantId = requireDocumentId(data.tenantId, "tenantId");
  const productId = requireDocumentId(data.productId, "productId");
  const requested = readProductUpdateInput(data);
  const requestId = requireRequestId(data.requestId);
  const db = getFirestore();

  // Authorize before consulting the idempotency cache, then again inside the
  // transaction so a role or membership change cannot race the correction.
  const actor = await requireTenantMember(db, request, tenantId, PRODUCT_UPDATE_ROLES);
  assertProductUpdateAuthorized(actor.staff.role, requested);
  const identity = buildIdempotencyIdentity(
    actor.uid,
    "updateProduct",
    tenantId,
    requestId
  );
  const updateId = `pu_${identity.documentId.slice(0, 40)}`;

  return runIdempotentFirestoreTransaction(db, {
    actorUid: actor.uid,
    operation: "updateProduct",
    tenantId,
    requestId,
    input: {
      productId,
      name: requested.name,
      sku: requested.sku,
      priceMinor: requested.priceMinor,
      categoryId: requested.categoryId,
    },
  }, async (transaction) => {
    const currentActor = await requireTenantMember(
      db,
      request,
      tenantId,
      PRODUCT_UPDATE_ROLES,
      transaction
    );
    assertProductUpdateAuthorized(currentActor.staff.role, requested);
    return applyProductUpdate(db, transaction, {
      tenantId,
      productId,
      updateId,
      requestId,
      actorUid: currentActor.uid,
      requested,
    });
  });
});
