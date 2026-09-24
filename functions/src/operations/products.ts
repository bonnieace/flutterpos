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
  IMPORT_OPENING_STOCK_REASON,
  MAXIMUM_IMPORT_CATEGORY_SCAN,
  ProductImportCategories,
  ProductImportInput,
  ProductImportRowOutcome,
  assertProductImportAuthorized,
  foldCategoryName,
  planProductImport,
  productImportFingerprintInput,
  productImportId,
  readProductImportInput,
} from "./productImport";
import {
  EditableProductField,
  PRODUCT_UPDATE_ROLES,
  ProductUpdateInput,
  StoredProductFields,
  assertProductUpdateAuthorized,
  planProductUpdate,
  readProductUpdateInput,
} from "./productUpdate";
import type {ProductCostType} from "./productUpdate";

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
  image?: unknown;
  costType?: unknown;
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
  image: string | null;

  /** Bought in or made here, as the product now holds it. */
  costType: ProductCostType;
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
    image: plan.product.image,
    costType: plan.product.costType,
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
    image: requested.image,
    costType: requested.costType,
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

interface ImportProductsRequest {
  tenantId?: unknown;
  mode?: unknown;
  rows?: unknown;
  requestId?: unknown;
}

export interface ImportProductsResponse {
  /**
   * The identity every audit entry of this import carries, so "what did that
   * import do" is answerable without inventing a new kind of record.
   *
   * Reported by a preview too, naming the import the matching commit *would*
   * write. A preview's per-row `productId` stays null, which is where the
   * did-it-happen question is answered.
   */
  importId: string;

  /** The business the products were planned or created in. */
  tenantId: string;

  /** What this request did: `preview` wrote nothing, `commit` wrote. */
  mode: ProductBatchMode;

  /** How many rows the request carried. */
  rowCount: number;
  createdCount: number;
  failedCount: number;

  /** Every row, in the order it was sent. */
  rows: ProductImportRowOutcome[];
}

/**
 * Reads the categories one import needs, by ID or by name.
 *
 * Two shapes, and which one runs is decided by the rows rather than by a flag.
 * A request that names every category by ID needs only those documents, so it
 * reads exactly them. A request that names any category by *name* has to hold
 * this business's categories to resolve against, so it scans them - bounded, and
 * refusing the whole request rather than guessing if the business holds more
 * than the bound. That scan then answers the ID rows too, which is why the two
 * are alternatives rather than both.
 *
 * A category whose stored `name` is unusable is skipped for name resolution and
 * still reachable by ID: it is a broken document, and refusing every import in
 * the business over one would be a worse answer than the one row that names it
 * failing.
 */
async function readProductImportCategories(
  db: Firestore,
  tenantRef: DocumentReference,
  input: ProductImportInput,
  transaction?: Transaction
): Promise<ProductImportCategories> {
  const ids = new Set<string>();
  const byFoldedName = new Map<string, string[]>();
  const categories = tenantRef.collection("categories");

  if (input.rows.some((row) => row.categoryName !== undefined)) {
    // One more than the bound, so "there are too many" is answered by the read
    // itself rather than by a count query nobody else in this codebase runs.
    const query = categories.limit(MAXIMUM_IMPORT_CATEGORY_SCAN + 1);
    const snapshot = transaction ? await transaction.get(query) : await query.get();
    if (snapshot.size > MAXIMUM_IMPORT_CATEGORY_SCAN) {
      throw new HttpsError(
        "failed-precondition",
        `This business holds more than ${MAXIMUM_IMPORT_CATEGORY_SCAN} ` +
        "categories, which is more than an import will resolve names against. " +
        "Name each row's category by categoryId instead."
      );
    }
    for (const document of snapshot.docs) {
      ids.add(document.id);
      const name = document.get("name");
      if (typeof name !== "string" || name.trim().length === 0) continue;
      const folded = foldCategoryName(name);
      byFoldedName.set(folded, [...(byFoldedName.get(folded) ?? []), document.id]);
    }
    return {ids, byFoldedName};
  }

  const namedIds = [...new Set(input.rows.flatMap(
    (row) => row.categoryId === undefined ? [] : [row.categoryId]
  ))].sort();
  // Reachable when every row of the request was refused before anything could be
  // read. `getAll()` with no references is an error, not an empty answer.
  if (namedIds.length === 0) return {ids, byFoldedName};
  const refs = namedIds.map((id) => categories.doc(id));
  const snapshots: DocumentSnapshot[] = transaction ?
    await transaction.getAll(...refs) :
    await db.getAll(...refs);
  for (const snapshot of snapshots) {
    if (snapshot.exists) ids.add(snapshot.id);
  }
  return {ids, byFoldedName};
}

/**
 * Creates every product one import names, and records where its stock came from.
 *
 * Up to four documents per row, and the last two are the reason this is not a
 * client-side batch even though `allow create` on `products` is client-reachable:
 * a device can create a product, but it cannot write the `stock_adjustments`
 * record or the `stock_movements` entry that give the opening units a recorded
 * origin, because both collections are server-write-only. A device import would
 * therefore either leave stock with no ledger entry - the defect the previous
 * app's uploader shipped - or leave the ledger to a second, unrelated call that
 * can fail on its own.
 *
 * Preview and commit read exactly the same documents through exactly the same
 * code, differing only in whether that read is transactional and whether the
 * plan's writes are applied.
 */
export async function applyProductImport(
  db: Firestore,
  options: {
    tenantId: string;
    identityDocumentId: string;
    requestId: string;
    actorUid: string;
    input: ProductImportInput;

    /** Absent in a preview, which reads the same documents and writes none. */
    transaction?: Transaction;
  }
): Promise<ImportProductsResponse> {
  const tenantRef = db.collection("tenants").doc(options.tenantId);
  const categories = await readProductImportCategories(
    db,
    tenantRef,
    options.input,
    options.transaction
  );
  const plan = planProductImport({
    input: options.input,
    identityDocumentId: options.identityDocumentId,
    categories,
  });

  const importId = productImportId(options.identityDocumentId);
  const transaction = options.transaction;
  if (transaction) {
    for (const write of plan.writes) {
      const productRef = tenantRef.collection("products").doc(write.productId);
      transaction.create(productRef, {
        ...write.documentData,
        createdBy: options.actorUid,
        createdAt: FieldValue.serverTimestamp(),
        // Written beside `createdAt`, which the catalog's own create form does
        // not do, because this path can create a product already holding stock:
        // the nightly stock verification defers a product written in the last
        // five minutes by reading `updatedAt`, and without one an imported
        // product would be compared against a ledger entry Firestore may not
        // have made visible to the query yet.
        updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.create(tenantRef.collection("audit_logs").doc(write.auditId), {
        eventType: "product_imported",
        tenantId: options.tenantId,
        productId: write.productId,
        // What makes one import answerable as one thing. A product created
        // through the catalog form carries neither field, so a query by import
        // matches only imported rows.
        importId,
        rowIndex: write.rowIndex,
        // What the product was created holding. There is no before-and-after to
        // record as a correction has, so the audit records the after - which is
        // the only account of an imported price that survives a later change.
        created: {
          name: write.product.name,
          sku: write.product.sku,
          price: write.product.price,
          cost: write.product.cost,
          categoryId: write.product.categoryId,
          quantity: write.product.quantity,
        },
        openingQuantity: write.product.quantity,
        // The ledger entry those units came in through, and null when the row
        // opened holding nothing. Whenever `mutatesQuantity` is true this names
        // the record that says where the stock came from, which is the property
        // that makes a quantity acceptable in this payload at all.
        adjustmentId: write.adjustmentId,
        mutatesQuantity: write.adjustmentId !== null,
        actorUid: options.actorUid,
        requestId: options.requestId,
        createdAt: FieldValue.serverTimestamp(),
      });
      if (write.adjustmentId === null) continue;
      // The shape `adjustStock` writes, field for field, because an imported
      // unit and an adjusted unit are the same unit and reconciliation reads
      // one ledger. `previousQuantity` is zero rather than "unknown": the
      // product is being created in this transaction, so it held nothing.
      const immutableRecord = {
        tenantId: options.tenantId,
        productId: write.productId,
        sourceType: "product_import",
        adjustmentType: "opening_balance",
        quantityDelta: write.product.quantity,
        previousQuantity: 0,
        quantityAfter: write.product.quantity,
        reason: IMPORT_OPENING_STOCK_REASON,
        importId,
        rowIndex: write.rowIndex,
        actorUid: options.actorUid,
        requestId: options.requestId,
        createdAt: FieldValue.serverTimestamp(),
      };
      transaction.create(
        tenantRef.collection("stock_adjustments").doc(write.adjustmentId),
        immutableRecord
      );
      transaction.create(
        productRef.collection("stock_movements").doc(write.adjustmentId),
        {
          ...immutableRecord,
          movementId: write.adjustmentId,
          occurredAt: FieldValue.serverTimestamp(),
          recordedAt: FieldValue.serverTimestamp(),
        }
      );
    }
  }

  return {
    importId,
    tenantId: options.tenantId,
    mode: options.input.mode,
    rowCount: options.input.rowCount,
    createdCount: plan.createdCount,
    failedCount: plan.failedCount,
    rows: plan.outcomes,
  };
}

/**
 * Creates many products from a spreadsheet, or reports what doing so would
 * create.
 *
 * The other half of the bulk catalog rewrite, and the larger one. It solves
 * everything `updateProducts` solved - a required mode, a bounded row list,
 * every broken row named at once, partial success stated rather than implied -
 * plus the three problems only a create raises: resolving a category named
 * "Bakery" against this business, deriving a permanent document ID for a product
 * that does not exist yet, and giving opening stock a recorded origin. Those are
 * argued in `productImport.ts`.
 *
 * A `preview` writes nothing at all - not the products, not the audit entries,
 * not the stock ledger, and deliberately not an idempotency record, so a client
 * may preview and then commit under one request ID. That flow is worth more here
 * than anywhere else in this codebase: a spreadsheet is the one input nobody
 * proofreads, and four hundred wrong products are far harder to undo than one,
 * because retiring a product is not an undo and every ID stays in the ledger.
 *
 * A `commit` is one transaction. Rows that could not be created are reported
 * beside the ones that were, and re-running a failed import needs a **new**
 * request ID - which will create the rows that already landed a second time,
 * since nothing in this system makes a SKU or a name unique. The preview is the
 * answer to that, not a duplicate check this app has never been able to make.
 */
export const importProducts = onCall<
  ImportProductsRequest,
  Promise<ImportProductsResponse>
>(async (
  request: CallableRequest<ImportProductsRequest>
): Promise<ImportProductsResponse> => {
  const data = requireObject(request.data);
  const tenantId = requireDocumentId(data.tenantId, "tenantId");
  const requestId = requireRequestId(data.requestId);
  const input = readProductImportInput(data);
  const db = getFirestore();

  // Creating a product is an operational act and `PRODUCT_UPDATE_ROLES` is
  // exactly the trio `allow create` on `products` already names, so an import
  // admits whoever the catalog's own add-product form admits. Cost is narrower
  // and is decided over every row before anything is read.
  const actor = await requireTenantMember(db, request, tenantId, PRODUCT_UPDATE_ROLES);
  assertProductImportAuthorized(actor.staff.role, input.rows);
  const identity = buildIdempotencyIdentity(
    actor.uid,
    "importProducts",
    tenantId,
    requestId
  );

  if (input.mode === "preview") {
    return applyProductImport(db, {
      tenantId,
      identityDocumentId: identity.documentId,
      requestId,
      actorUid: actor.uid,
      input,
    });
  }

  return runIdempotentFirestoreTransaction(db, {
    actorUid: actor.uid,
    operation: "importProducts",
    tenantId,
    requestId,
    // Only a commit ever records one, so the mode is not part of the
    // fingerprint: every stored record of this operation is a commit.
    input: productImportFingerprintInput(input),
  }, async (transaction) => {
    const currentActor = await requireTenantMember(
      db,
      request,
      tenantId,
      PRODUCT_UPDATE_ROLES,
      transaction
    );
    assertProductImportAuthorized(currentActor.staff.role, input.rows);
    return applyProductImport(db, {
      tenantId,
      identityDocumentId: identity.documentId,
      requestId,
      actorUid: currentActor.uid,
      input,
      transaction,
    });
  });
});
