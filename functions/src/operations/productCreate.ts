import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {requireTenantMember} from "../core/authorization";
import {TenantRole} from "../core/model";
import {runIdempotentFirestoreTransaction} from "../core/idempotency";
import {
  requireDocumentId,
  requireObject,
  requireRequestId,
} from "../core/validation";
import {readOpeningQuantity} from "./productImport";
import {
  PRODUCT_UPDATE_ROLES,
  StoredProductFields,
  assertProductUpdateAuthorized,
  productSearchFields,
  readSellableProduct,
} from "./productUpdate";

/**
 * Brings one product into the catalog, with the stock it already holds.
 *
 * **Why this is a callable at all.** Creating a product used to be a client
 * Firestore `set`, and that is exactly what made a new product start empty:
 * `stock_adjustments` and `stock_movements` are `allow write: if false` for every
 * client, so a device that wrote `quantity: 24` could not write the ledger entry
 * saying where those units came from. The rule was never "a product starts at
 * zero" - it was "whoever writes the quantity writes the movement", and a device
 * cannot. `importProducts` has always been allowed to name a quantity for this
 * reason and this reason only. This is that same permission, offered one product
 * at a time, which is what collapses adding stocked goods from two journeys into
 * one.
 *
 * **It is not a retreat from offline.** The mutation outbox replays this exactly
 * as it replays `updateProduct` and `adjustStock`, both of which are callables
 * and both of which work with no connection: the intent is durable before
 * anything is sent, and `TenantPendingMutationOverlayReader` draws the product
 * over the catalog the moment it is queued. What changed is where the write is
 * made, not when the operator is told it happened.
 *
 * **The client's document ID is the idempotency key.** A product ID is already
 * `pd_` plus a digest of the operation, business, actor and request ID, so it is
 * unguessable, stable across the retries of one confirmation, and unique to it -
 * which is the whole specification of an idempotency key. Taking a second one
 * would let the two disagree.
 *
 * The split below is `productImport.ts`'s: everything that decides is a pure
 * function this file exports, and the callable is the authorization and the
 * transaction around it. Timestamps are the one thing the plan cannot hold, so
 * they are added at write time.
 */
interface CreateProductRequest {
  tenantId?: unknown;
  productId?: unknown;
  document?: unknown;
}

export interface CreateProductResponse {
  productId: string;

  /** The opening ledger entry, or null when the product opened holding nothing. */
  adjustmentId: string | null;
  quantity: number;
}

/** Why the opening ledger entry exists, in the words the stock ledger records. */
export const CREATE_OPENING_STOCK_REASON =
  "Opening balance recorded when the product was added.";

/**
 * Every key the document a client sends may carry.
 *
 * The last three are **accepted and ignored**, not refused. They are written by
 * this server from the actor and the normalized name, and a client has no say in
 * any of them - but the queued document a device composed carries them, and a
 * record queued before this callable existed carries them too. Refusing a field
 * that is merely redundant would reject work that is already durable on somebody's
 * phone.
 */
const ACCEPTED_PRODUCT_DOCUMENT_KEYS = new Set<string>([
  "name",
  "SKU",
  "price",
  "cost",
  "quantity",
  "categoryId",
  "image",
  "searchName",
  "searchPrefixes",
  "createdBy",
]);

/** What a document must name, because a product cannot exist without it. */
const REQUIRED_PRODUCT_DOCUMENT_FIELDS = [
  "name",
  "SKU",
  "price",
  "categoryId",
] as const;

/** One create, read and normalized, before anybody is authorized for it. */
export interface ProductCreateInput {
  fields: StoredProductFields;
  quantity: number;

  /** Whether the caller asked to record a cost, which not every role may. */
  requestedCost: boolean;
}

/** The `stock_adjustments` and `stock_movements` ID one opening balance is written at. */
export function productCreateAdjustmentId(productId: string): string {
  // The product ID is already a digest; the ledger entry reuses it under the
  // `sa_` prefix every other adjustment carries, exactly as
  // `productImportRowIds` derives all three of its IDs from one digest. So an
  // opening balance is findable from the product and from nothing else, which is
  // what makes reusing it across a replay safe.
  return `sa_${productCreateDigest(productId)}`;
}

/** The `audit_logs` ID one create is recorded at. */
export function productCreateAuditId(productId: string): string {
  return `pc_${productCreateDigest(productId)}`;
}

function productCreateDigest(productId: string): string {
  return productId.startsWith("pd_") ? productId.slice(3) : productId;
}

/**
 * Reads the document a device composed, keeping what only the server may decide.
 *
 * `quantity` is absent or zero for an ordinary create and positive for a product
 * that is already on the shelf. It is the one field here that no other
 * single-product path may name, and it is accepted because the transaction below
 * writes the ledger entry that accounts for it.
 */
export function readProductCreateInput(value: unknown): ProductCreateInput {
  const document = requireObject(value, "document");
  for (const key of Object.keys(document)) {
    if (!ACCEPTED_PRODUCT_DOCUMENT_KEYS.has(key)) {
      throw new HttpsError("invalid-argument", `${key} is not part of a product.`);
    }
  }
  for (const field of REQUIRED_PRODUCT_DOCUMENT_FIELDS) {
    if (document[field] === undefined || document[field] === null) {
      throw new HttpsError(
        "invalid-argument",
        `${field} is required to create a product.`
      );
    }
  }
  // Absent and explicitly null both mean "not recorded" on a product that does
  // not exist yet, so the null is dropped at the door - the same reading
  // `readImportRow` gives a blank spreadsheet cell, and deliberately not
  // `updateProduct`'s, where null clears a cost that was already there.
  const requestedCost = document.cost !== undefined && document.cost !== null;
  const quantity = readOpeningQuantity(document.quantity);
  return {
    fields: {
      name: document.name,
      SKU: document.SKU,
      price: document.price,
      quantity,
      categoryId: document.categoryId,
      ...(requestedCost ? {cost: document.cost} : {}),
      ...(document.image === undefined || document.image === null ?
        {} :
        {image: document.image}),
    },
    quantity,
    requestedCost,
  };
}

/**
 * Refuses a cost recorded by a principal who may create everything else.
 *
 * **A price is not gated and a cost is.** Setting a first price *is* creation,
 * and the add-product form already accepts one from a manager; what one unit cost
 * the business is owner and administrator information on every other surface, so
 * it is here too. This is the rule `assertProductImportAuthorized` applies row by
 * row, applied to the one row this request is.
 */
export function assertProductCreateAuthorized(
  role: TenantRole,
  input: ProductCreateInput
): void {
  if (!input.requestedCost) return;
  assertProductUpdateAuthorized(role, {requestedFields: ["cost"]});
}

/** Every document one create writes, without the timestamps only a write has. */
export interface ProductCreatePlan {
  productId: string;
  adjustmentId: string | null;
  auditId: string;
  quantity: number;
  documentData: Record<string, unknown>;
  auditData: Record<string, unknown>;

  /** The `stock_adjustments` record and `stock_movements` entry, or null. */
  ledgerData: Record<string, unknown> | null;
}

/**
 * Decides every document one create writes.
 *
 * The product is built as the document it will be and then read back through
 * [readSellableProduct] - the server-side twin of `TenantProduct.fromDocument` -
 * before anything is written, which is the same guard `planProductImport`
 * applies and it matters for the same reason: one product the till cannot parse
 * makes the *whole* cached catalog a miss and stops the business selling
 * everything. It is also the only validation the `image` field gets anywhere.
 */
export function planProductCreate(options: {
  tenantId: string;
  productId: string;
  actorUid: string;
  input: ProductCreateInput;
}): ProductCreatePlan {
  const sellable = readSellableProduct(options.input.fields);
  const search = productSearchFields(sellable.name, sellable.sku);
  const adjustmentId = sellable.quantity > 0 ?
    productCreateAdjustmentId(options.productId) :
    null;

  return {
    productId: options.productId,
    adjustmentId,
    auditId: productCreateAuditId(options.productId),
    quantity: sellable.quantity,
    documentData: {
      name: sellable.name,
      SKU: sellable.sku,
      price: sellable.price,
      // Omitted rather than written as null when none was recorded, so "never
      // recorded" and "recorded as nothing" stay distinguishable in the document.
      ...(sellable.cost === null ? {} : {cost: sellable.cost}),
      quantity: sellable.quantity,
      categoryId: sellable.categoryId,
      searchName: search.searchName,
      searchPrefixes: search.searchPrefixes,
      ...(sellable.image === null ? {} : {image: sellable.image}),
      // From the actor, never from the payload. A device composes this document
      // and could name anybody; who created a product is the server's to say.
      createdBy: options.actorUid,
    },
    auditData: {
      eventType: "product_created",
      tenantId: options.tenantId,
      productId: options.productId,
      // What the product was created holding. There is no before-and-after to
      // record as a correction has, so the audit records the after - which is the
      // only account of the price a product was added at that survives a later
      // change.
      created: {
        name: sellable.name,
        sku: sellable.sku,
        price: sellable.price,
        cost: sellable.cost,
        categoryId: sellable.categoryId,
        quantity: sellable.quantity,
      },
      openingQuantity: sellable.quantity,
      // The ledger entry those units came in through, and null when the product
      // opened holding nothing. Whenever `mutatesQuantity` is true this names the
      // record that says where the stock came from, which is the property that
      // makes a quantity acceptable in this payload at all.
      adjustmentId,
      mutatesQuantity: adjustmentId !== null,
      actorUid: options.actorUid,
      requestId: options.productId,
    },
    // The shape `adjustStock` writes, field for field, because a unit opened with
    // and a unit adjusted in are the same unit and reconciliation reads one
    // ledger. `previousQuantity` is zero rather than "unknown": the product is
    // being created in this transaction, so it held nothing.
    ledgerData: adjustmentId === null ? null : {
      tenantId: options.tenantId,
      productId: options.productId,
      sourceType: "product_created",
      adjustmentType: "opening_balance",
      quantityDelta: sellable.quantity,
      previousQuantity: 0,
      quantityAfter: sellable.quantity,
      reason: CREATE_OPENING_STOCK_REASON,
      actorUid: options.actorUid,
      requestId: options.productId,
    },
  };
}

/**
 * What one create is fingerprinted by, so a retry is recognised as one.
 *
 * The normalized values rather than what was sent, so a retry that re-serializes
 * the same price a different way hashes the same. The server-derived fields are
 * absent: `createdBy` and the search index are decided here, so including them
 * would make the fingerprint depend on this function rather than on the request.
 */
export function productCreateFingerprintInput(
  plan: ProductCreatePlan
): Record<string, unknown> {
  const document = plan.documentData;
  return {
    productId: plan.productId,
    name: document.name,
    sku: document.SKU,
    price: document.price,
    cost: document.cost ?? null,
    categoryId: document.categoryId,
    quantity: plan.quantity,
    image: document.image ?? null,
  };
}

export const createProduct = onCall<
  CreateProductRequest,
  Promise<CreateProductResponse>
>(async (
  request: CallableRequest<CreateProductRequest>
): Promise<CreateProductResponse> => {
  const data = requireObject(request.data);
  const tenantId = requireDocumentId(data.tenantId, "tenantId");
  const productId = requireDocumentId(data.productId, "productId");
  // Proved usable as an idempotency key before it is used as one, so a caller
  // that derived the ID some other way is refused here rather than silently given
  // a key the record cannot be found under again.
  requireRequestId(productId);
  const input = readProductCreateInput(data.document);
  const db = getFirestore();

  const actor = await requireTenantMember(db, request, tenantId, PRODUCT_UPDATE_ROLES);
  assertProductCreateAuthorized(actor.staff.role, input);
  const plan = planProductCreate({tenantId, productId, actorUid: actor.uid, input});

  // The category is deliberately **not** checked for existence, which differs
  // from `updateProduct` and from `importProducts`. Both of those answer a
  // request whose category must already be on the server; this one routinely does
  // not. A device offline can add a category and then file a product under it,
  // and the outbox drains one document path concurrently with another - so the
  // product can reach here before the category's own write lands. A refusal would
  // be permanent (`failed-precondition` is a rejected code) and the product would
  // be lost, and a retryable refusal would retry for ever on a category that
  // genuinely is not coming. Closing this needs the deferral
  // `TenantProductImageUploadWorker` already does for a photograph whose product
  // is still queued; until then the client's own guard - a product may only name
  // a category this session read from this business - is what stands, exactly as
  // it stood when this was a document write.
  return runIdempotentFirestoreTransaction(db, {
    actorUid: actor.uid,
    operation: "createProduct",
    tenantId,
    requestId: productId,
    input: productCreateFingerprintInput(plan),
  }, async (transaction) => {
    const currentActor = await requireTenantMember(
      db,
      request,
      tenantId,
      PRODUCT_UPDATE_ROLES,
      transaction
    );
    assertProductCreateAuthorized(currentActor.staff.role, input);
    const tenantRef = db.collection("tenants").doc(tenantId);
    const productRef = tenantRef.collection("products").doc(plan.productId);

    transaction.create(productRef, {
      ...plan.documentData,
      createdAt: FieldValue.serverTimestamp(),
      // Written beside `createdAt` for the reason the import path records: the
      // nightly stock verification defers a product written in the last five
      // minutes by reading `updatedAt`, and without one a product created holding
      // stock would be compared against a ledger entry Firestore may not have
      // made visible to the query yet.
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.create(tenantRef.collection("audit_logs").doc(plan.auditId), {
      ...plan.auditData,
      createdAt: FieldValue.serverTimestamp(),
    });

    if (plan.ledgerData !== null && plan.adjustmentId !== null) {
      const immutableRecord = {
        ...plan.ledgerData,
        createdAt: FieldValue.serverTimestamp(),
      };
      transaction.create(
        tenantRef.collection("stock_adjustments").doc(plan.adjustmentId),
        immutableRecord
      );
      transaction.create(
        productRef.collection("stock_movements").doc(plan.adjustmentId),
        {
          ...immutableRecord,
          movementId: plan.adjustmentId,
          occurredAt: FieldValue.serverTimestamp(),
          recordedAt: FieldValue.serverTimestamp(),
        }
      );
    }

    return {
      productId: plan.productId,
      adjustmentId: plan.adjustmentId,
      quantity: plan.quantity,
    };
  });
});
