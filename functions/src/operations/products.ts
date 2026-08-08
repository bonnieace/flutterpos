import {
  DocumentReference,
  DocumentSnapshot,
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
  ProductBatchInput,
  ProductBatchMode,
  ProductBatchRowOutcome,
  assertProductBatchAuthorized,
  planProductBatch,
  productBatchFingerprintInput,
  productBatchId,
  readProductBatchInput,
} from "./productBatch";
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

  /**
   * Declared for the same reason every other field is, and it was missing until
   * 2026-08-08.
   *
   * The handler reads a `Record<string, unknown>`, so its absence changed no
   * behaviour and refused nothing - but a type that does not mention the one
   * field where `null` means something is a type that misleads the next reader.
   */
  cost?: unknown;

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

  /** Which of name, sku, price, cost, and categoryId actually moved. */
  changedFields: EditableProductField[];

  /** What the product holds now, in the shape the till reads it. */
  name: string;
  sku: string;
  price: number;
  priceMinor: number;

  /**
   * What one unit cost the business, or null when none is recorded.
   *
   * Echoed since 2026-08-08. Before that a cost that moved appeared in
   * `changedFields` with no value beside it, so four of the five fields could be
   * reconciled against the request and the fifth could not - a client had to
   * re-read the catalog to confirm the one field it had just been told changed.
   */
  cost: number | null;
  costMinor: number | null;

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
    cost: plan.product.cost,
    costMinor: plan.product.costMinor,
    categoryId: plan.product.categoryId,
  };
}

/**
 * What one correction is fingerprinted by, so a genuine retry is recognised.
 *
 * `costMinor` belongs here and was missing until 2026-08-08. Without it two
 * payloads under one request ID differing *only* in cost hashed the same, so the
 * second was answered off the stored record and the new cost was silently not
 * applied - where a difference in any other field would have been refused as
 * `already-exists`. A silent wrong answer rather than a refusal, and the one
 * shape of that defect this operation had.
 *
 * Absent and null hash differently, which is the property that matters: omitting
 * `cost` leaves a recorded cost alone and sending `cost: null` clears it, and a
 * fingerprint that could not tell them apart would answer one off a record made
 * for the other.
 *
 * Nothing is deployed anywhere, so changing what an existing request ID hashes
 * to strands no in-flight retry.
 */
export function productUpdateFingerprintInput(
  productId: string,
  requested: ProductUpdateInput
): Record<string, unknown> {
  return {
    productId,
    name: requested.name,
    sku: requested.sku,
    priceMinor: requested.priceMinor,
    costMinor: requested.costMinor,
    categoryId: requested.categoryId,
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
    input: productUpdateFingerprintInput(productId, requested),
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

interface UpdateProductsRequest {
  tenantId?: unknown;
  mode?: unknown;
  rows?: unknown;
  requestId?: unknown;
}

export interface UpdateProductsResponse {
  /**
   * The identity every audit entry of this change carries, so "what did that
   * bulk change do" is answerable without inventing a new kind of record.
   *
   * Reported by a preview too, naming the batch the matching commit *would*
   * write. A preview's per-row `updateId` stays null, which is where the
   * did-it-happen question is answered.
   */
  batchId: string;

  /** The business the change was planned or applied in. */
  tenantId: string;

  /** What this request did: `preview` wrote nothing, `commit` wrote. */
  mode: ProductBatchMode;

  /** How many rows the request carried. */
  rowCount: number;
  updatedCount: number;
  unchangedCount: number;
  failedCount: number;

  /** Every row, in the order it was sent. */
  rows: ProductBatchRowOutcome[];
}

/**
 * Reads every product and category one bulk change names, plans it, and - in
 * commit mode - writes it.
 *
 * The read is one `getAll` over every document the request could possibly need,
 * for a reason Firestore imposes rather than one chosen here: a transaction may
 * not read after its first write, so a per-row read-then-write loop is not a
 * slower version of this, it is a transaction that throws on its second row.
 *
 * Preview and commit read exactly the same documents through exactly the same
 * code, differing only in whether that read is transactional and whether the
 * plan's writes are applied. Anything else would make a preview a description of
 * a different operation.
 */
export async function applyProductBatchUpdate(
  db: Firestore,
  options: {
    tenantId: string;
    identityDocumentId: string;
    requestId: string;
    actorUid: string;
    input: ProductBatchInput;

    /** Absent in a preview, which reads the same documents and writes none. */
    transaction?: Transaction;
  }
): Promise<UpdateProductsResponse> {
  const tenantRef = db.collection("tenants").doc(options.tenantId);
  const productIds = options.input.rows.map((row) => row.productId);
  const categoryIds = [...new Set(options.input.rows.flatMap(
    (row) => row.requested.categoryId === undefined ? [] : [row.requested.categoryId]
  ))].sort();
  const refs: DocumentReference[] = [
    ...productIds.map((id) => tenantRef.collection("products").doc(id)),
    ...categoryIds.map((id) => tenantRef.collection("categories").doc(id)),
  ];
  // Reachable when every row of the request was refused before anything could be
  // read. `getAll()` with no references is an error, not an empty answer.
  const snapshots: DocumentSnapshot[] = refs.length === 0 ?
    [] :
    options.transaction ?
      await options.transaction.getAll(...refs) :
      await db.getAll(...refs);

  const storedProducts = new Map<string, StoredProductFields | undefined>();
  productIds.forEach((productId, position) => {
    const snapshot = snapshots[position];
    storedProducts.set(
      productId,
      snapshot.exists ? snapshot.data() as StoredProductFields : undefined
    );
  });
  const existingCategoryIds = new Set<string>();
  categoryIds.forEach((categoryId, position) => {
    if (snapshots[productIds.length + position].exists) {
      existingCategoryIds.add(categoryId);
    }
  });

  const plan = planProductBatch({
    input: options.input,
    identityDocumentId: options.identityDocumentId,
    storedProducts,
    existingCategoryIds,
  });

  const batchId = productBatchId(options.identityDocumentId);
  const transaction = options.transaction;
  if (transaction) {
    for (const write of plan.writes) {
      // Only the fields that moved, plus the server's own timestamp - the same
      // patch the single-product path applies. `quantity` is absent by
      // construction: no plan can name it.
      transaction.update(
        tenantRef.collection("products").doc(write.productId),
        {...write.documentUpdate, updatedAt: FieldValue.serverTimestamp()}
      );
      transaction.create(
        tenantRef.collection("audit_logs").doc(write.updateId),
        {
          eventType: "product_updated",
          tenantId: options.tenantId,
          productId: write.productId,
          updateId: write.updateId,
          // What makes one bulk change answerable as one thing. A single-product
          // correction carries neither field, so a query by batch matches only
          // the rows of a bulk change.
          batchId,
          rowIndex: write.rowIndex,
          changedFields: write.changedFields,
          changes: write.changes,
          mutatesQuantity: false,
          actorUid: options.actorUid,
          requestId: options.requestId,
          createdAt: FieldValue.serverTimestamp(),
        }
      );
    }
  }

  return {
    batchId,
    tenantId: options.tenantId,
    mode: options.input.mode,
    rowCount: options.input.rowCount,
    updatedCount: plan.updatedCount,
    unchangedCount: plan.unchangedCount,
    failedCount: plan.failedCount,
    rows: plan.outcomes,
  };
}

/**
 * Corrects many products at once, or reports what doing so would change.
 *
 * This is N applications of `updateProduct`'s own decision, executed on the
 * server. It could not be a client-side `WriteBatch` even if that were cheaper:
 * `allow update` on `products` permits the checkout decrement and nothing else,
 * so a device cannot write a name, a price, or a category - and widening that
 * clause is the thing "how a price is corrected" was decided against, because a
 * rule-based edit records no actor, no previous value, and no reason.
 *
 * A `preview` writes nothing at all - not the corrections, not the audit
 * entries, and deliberately not an idempotency record. The last of those is what
 * lets a client preview and then commit under one request ID, which is the flow
 * worth having: the commit's fingerprint covers the rows, so a change edited
 * between the preview and the commit is refused as `already-exists` rather than
 * quietly applied as something other than what was shown.
 *
 * A `commit` is one transaction. Rows that could not be applied are reported
 * beside the ones that were rather than taking the request down with them, which
 * is what makes a half-applied change re-runnable - and is safe to offer only
 * because the preview exists to find those rows first.
 */
export const updateProducts = onCall<
  UpdateProductsRequest,
  Promise<UpdateProductsResponse>
>(async (
  request: CallableRequest<UpdateProductsRequest>
): Promise<UpdateProductsResponse> => {
  const data = requireObject(request.data);
  const tenantId = requireDocumentId(data.tenantId, "tenantId");
  const requestId = requireRequestId(data.requestId);
  const input = readProductBatchInput(data);
  const db = getFirestore();

  // Authorize before consulting the idempotency cache, then again inside the
  // transaction so a role or membership change cannot race the change.
  const actor = await requireTenantMember(db, request, tenantId, PRODUCT_UPDATE_ROLES);
  assertProductBatchAuthorized(actor.staff.role, input.rows);
  const identity = buildIdempotencyIdentity(
    actor.uid,
    "updateProducts",
    tenantId,
    requestId
  );

  if (input.mode === "preview") {
    return applyProductBatchUpdate(db, {
      tenantId,
      identityDocumentId: identity.documentId,
      requestId,
      actorUid: actor.uid,
      input,
    });
  }

  return runIdempotentFirestoreTransaction(db, {
    actorUid: actor.uid,
    operation: "updateProducts",
    tenantId,
    requestId,
    // Only a commit ever records one, so the mode is not part of the
    // fingerprint: every stored record of this operation is a commit.
    input: productBatchFingerprintInput(input),
  }, async (transaction) => {
    const currentActor = await requireTenantMember(
      db,
      request,
      tenantId,
      PRODUCT_UPDATE_ROLES,
      transaction
    );
    assertProductBatchAuthorized(currentActor.staff.role, input.rows);
    return applyProductBatchUpdate(db, {
      tenantId,
      identityDocumentId: identity.documentId,
      requestId,
      actorUid: currentActor.uid,
      input,
      transaction,
    });
  });
});
