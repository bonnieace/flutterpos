import {createHash} from "node:crypto";
import {HttpsError} from "firebase-functions/v2/https";
import {TenantRole} from "../core/model";
import {requireDocumentId, requireObject} from "../core/validation";
import {
  ACCEPTED_PRODUCT_ROW_KEYS,
  EditableProductField,
  MONETARY_PRODUCT_FIELDS,
  ProductFieldChange,
  ProductUpdateInput,
  SellableProduct,
  StoredProductFields,
  assertProductUpdateAuthorized,
  planProductUpdate,
  readProductUpdateInput,
} from "./productUpdate";

/**
 * Correcting many products in one request, and saying exactly what that did.
 *
 * The previous app changed products in bulk with `batch.update(docRef, fields)`
 * from a device. That shape is structurally impossible here and always will be:
 * `allow update` on `products/{productId}` permits `['quantity', 'updatedAt']`
 * with a strictly decreasing quantity - the checkout decrement - and widening it
 * is exactly what "how a price is corrected" rejected, because a rule-based edit
 * records no actor, no previous value, and no reason. So a bulk change is N
 * corrections executed on the server, each one identical to what `updateProduct`
 * does to a single product, and this module is the part that decides which rows
 * those are.
 *
 * Four properties follow from that, and each of them is a decision rather than a
 * consequence:
 *
 * - **A preview is a first-class mode, not a dry-run flag.** A spreadsheet is
 *   the one input nobody proofreads, and the first time a person should see what
 *   four hundred rows are about to do is before they do it. A preview reads
 *   exactly what a commit reads, plans exactly what a commit plans, and writes
 *   nothing whatsoever - deliberately including no idempotency record, so the
 *   commit that follows may carry the same request ID.
 * - **Every broken row is named at once**, the contract `updateProduct` already
 *   keeps for fields. A row-at-a-time refusal turns a four-hundred-row change
 *   into four hundred round trips of discovery, so a row that cannot be parsed,
 *   a product that does not exist, and a document too malformed to correct are
 *   all *outcomes* carried back beside the rows that worked.
 * - **Partial success is stated, never implied.** Every row comes back with what
 *   happened to it, and a row that changed nothing is `unchanged` rather than
 *   silently absent - which is also what lets a half-applied change be re-run to
 *   completion instead of being refused by the rows that already landed.
 * - **The request is bounded and the caller chains it.** There is no server-side
 *   cursor because there is no server-side collection to walk: the caller holds
 *   the rows. What the server owes is a bound it will not exceed and a request
 *   that is independently idempotent, so a chain of them can be retried at any
 *   point.
 *
 * What it deliberately does not do is touch `quantity` in any form. That belongs
 * to `adjustStock`, which writes a `stock_movements` entry, and a bulk path that
 * could move stock without one would undo the single guarantee every stock
 * figure in this system rests on.
 */

/**
 * The most products one request may correct.
 *
 * Each corrected row writes two documents - the product and its audit entry -
 * and the request adds one idempotency record, so fifty rows is 101 writes
 * against Firestore's limit of 500 in a transaction. The bound is not set by
 * that limit, which is nowhere near reached; it is set by wanting a transaction
 * that fails on contention to be cheap to retry, and by matching
 * `TENANT_DISCOVERY_PAGE_SIZE`, the other bounded-and-chained page in this
 * codebase. Raising it costs retry latency long before it costs write budget.
 */
export const MAXIMUM_PRODUCT_BATCH_ROWS = 50;

/** How many offending rows a refusal names before it summarizes the rest. */
const MAXIMUM_NAMED_ROWS = 10;

/**
 * Whether the request is asking what would happen or asking for it to happen.
 *
 * There is no default. A payload that omits the mode is refused rather than
 * treated as a preview, because the failure modes are not symmetric: a preview
 * mistaken for a commit is a report nobody acts on, and a commit mistaken for a
 * preview changes four hundred products nobody agreed to.
 *
 * Shared with `productImport.ts`, which asks the same question of the same
 * caller about the same spreadsheet.
 */
export type ProductBatchMode = "preview" | "commit";

const PRODUCT_BATCH_MODES: readonly string[] = ["preview", "commit"];

/** Every key one bulk request may carry. */
const ACCEPTED_BATCH_KEYS = new Set<string>([
  "tenantId",
  "mode",
  "rows",
  "requestId",
]);

/** One row that parsed, ready to be planned against what is stored. */
export interface ProductBatchRow {
  /** Where the row sat in the request, so an outcome can be matched back to it. */
  index: number;
  productId: string;
  requested: ProductUpdateInput;
}

/** One row that could not be parsed, and why. */
export interface ProductBatchRowRefusal {
  index: number;

  /** Null when the row did not even name a readable product. */
  productId: string | null;
  code: string;
  message: string;
}

/** Every row of one request, parsed: the plannable ones and the refused ones. */
export interface ProductBatchInput {
  mode: ProductBatchMode;
  rows: readonly ProductBatchRow[];
  refusals: readonly ProductBatchRowRefusal[];

  /** How many rows the request carried, refusals included. */
  rowCount: number;
}

/** What happened to one row. */
export type ProductBatchRowStatus = "updated" | "unchanged" | "failed";

/** What a row's product holds, in the shape the till reads it. */
export interface ProductBatchRowProduct {
  name: string;
  sku: string;
  price: number;
  priceMinor: number;

  /** Null when this business has not recorded what the product cost. */
  cost: number | null;
  costMinor: number | null;
  categoryId: string;
}

/**
 * One row's result, carried back whether it worked or not.
 *
 * Every field is a value or null, never absent: the whole response is stored in
 * the idempotency record so a retry answers identically, and Firestore refuses
 * an `undefined`.
 */
export interface ProductBatchRowOutcome {
  index: number;
  productId: string | null;
  status: ProductBatchRowStatus;

  /** Which fields moved. Empty unless the status is `updated`. */
  changedFields: EditableProductField[];

  /**
   * The audit entry this row wrote.
   *
   * Null in a preview even for a row that would be updated, so an outcome from a
   * preview can never be mistaken for a record of something that happened.
   */
  updateId: string | null;

  /** The refusal code and message, both null unless the status is `failed`. */
  code: string | null;
  message: string | null;

  /**
   * What the product holds, or - in a preview - what it would hold. Null for a
   * failed row, which is the one case where there is no answer to give.
   */
  product: ProductBatchRowProduct | null;
}

/** One product's correction, as the writer applies it. */
export interface ProductBatchRowWrite {
  productId: string;
  updateId: string;
  rowIndex: number;
  documentUpdate: Record<string, string | number | null>;
  changes: readonly ProductFieldChange[];
  changedFields: readonly EditableProductField[];
}

/** Everything one request decided: what to report, and what to write. */
export interface ProductBatchPlan {
  outcomes: ProductBatchRowOutcome[];

  /** Empty in a preview, because a preview writes nothing. */
  writes: ProductBatchRowWrite[];
  updatedCount: number;
  unchangedCount: number;
  failedCount: number;
}

export function readProductBatchMode(value: unknown): ProductBatchMode {
  if (typeof value !== "string" || !PRODUCT_BATCH_MODES.includes(value)) {
    throw new HttpsError(
      "invalid-argument",
      "mode must be \"preview\" or \"commit\"."
    );
  }
  return value as ProductBatchMode;
}

/**
 * "rows[3], rows[7]", or "rows[3], rows[7], and 40 more".
 *
 * Written as payload paths rather than as ordinals because the indexes are the
 * zero-based ones every outcome carries, and "row 3" beside an outcome indexed 3
 * is the kind of off-by-one nobody notices until they correct the wrong product.
 *
 * Shared with `productImport.ts` so one refusal is worded one way, whichever
 * half of a bulk catalog change raised it.
 */
export function describeRows(indexes: readonly number[]): string {
  const named = indexes.slice(0, MAXIMUM_NAMED_ROWS)
    .map((index) => `rows[${index}]`)
    .join(", ");
  return indexes.length > MAXIMUM_NAMED_ROWS ?
    `${named}, and ${indexes.length - MAXIMUM_NAMED_ROWS} more` :
    named;
}

/**
 * Reads one bulk request, keeping a row's own defect as that row's problem.
 *
 * Three things are refused for the whole request rather than reported per row,
 * and each of them is refused because reporting it per row would make the report
 * itself wrong or the request meaningless:
 *
 * - **An unknown top-level key**, for the same reason `updateProduct` refuses
 *   one: dropping it silently would make "this callable never writes `quantity`"
 *   something a caller has to take on trust.
 * - **More rows than the bound.** Applying the first fifty and reporting the
 *   rest as failed would look like partial success rather than a caller that
 *   needs to chain.
 * - **A product named twice.** Two rows for one product are two conflicting
 *   intents, and there is no honest way to report the outcome of either: the
 *   second is planned against a document the first has already changed, so both
 *   rows would describe a before-and-after that never existed.
 */
export function readProductBatchInput(
  data: Record<string, unknown>
): ProductBatchInput {
  for (const key of Object.keys(data)) {
    if (!ACCEPTED_BATCH_KEYS.has(key)) {
      throw new HttpsError(
        "invalid-argument",
        `${key} is not part of a bulk product change.`
      );
    }
  }
  const mode = readProductBatchMode(data.mode);
  const rawRows = data.rows;
  if (!Array.isArray(rawRows)) {
    throw new HttpsError(
      "invalid-argument",
      "rows must be an array of product corrections."
    );
  }
  if (rawRows.length === 0) {
    throw new HttpsError("invalid-argument", "rows must name at least one product.");
  }
  if (rawRows.length > MAXIMUM_PRODUCT_BATCH_ROWS) {
    throw new HttpsError(
      "invalid-argument",
      `rows carries ${rawRows.length} products and at most ` +
      `${MAXIMUM_PRODUCT_BATCH_ROWS} are accepted. Send the rest as a further ` +
      "request with its own requestId."
    );
  }

  const rows: ProductBatchRow[] = [];
  const refusals: ProductBatchRowRefusal[] = [];
  const identified = new Map<string, number[]>();
  for (let index = 0; index < rawRows.length; index += 1) {
    let productId: string | null = null;
    try {
      const row = requireObject(rawRows[index], `rows[${index}]`);
      productId = requireDocumentId(row.productId, "productId");
      // Recorded before the rest of the row is read, so a product named by both
      // a valid row and a broken one is still seen as named twice.
      identified.set(productId, [...(identified.get(productId) ?? []), index]);
      rows.push({
        index,
        productId,
        requested: readProductUpdateInput(row, ACCEPTED_PRODUCT_ROW_KEYS),
      });
    } catch (error) {
      if (!(error instanceof HttpsError)) throw error;
      refusals.push({index, productId, code: error.code, message: error.message});
    }
  }

  const duplicated = [...identified.entries()]
    .filter(([, indexes]) => indexes.length > 1)
    .flatMap(([, indexes]) => indexes)
    .sort((left, right) => left - right);
  if (duplicated.length > 0) {
    throw new HttpsError(
      "invalid-argument",
      "A product may appear at most once in a bulk change; " +
      `${describeRows(duplicated)} name one more than once.`
    );
  }

  return {mode, rows, refusals, rowCount: rawRows.length};
}

/**
 * Refuses a bulk change that moves money when the caller may not.
 *
 * The decision is delegated to [assertProductUpdateAuthorized] over the union of
 * every row's requested fields, so the tier can never drift from the one
 * `updateProduct` enforces. What is added here is the message: a manager whose
 * four-hundred-row rename carries three stray price columns has to be told which
 * three, or the refusal is not actionable.
 *
 * It is decided over the *requested* fields rather than the resulting diff, and
 * before any product is read, for the reason `updateProduct` already records -
 * permission that depended on what a document happens to hold would be a rule
 * nobody could explain.
 */
export function assertProductBatchAuthorized(
  role: TenantRole,
  rows: readonly ProductBatchRow[]
): void {
  const monetaryRows = rows.filter((row) => row.requested.requestedFields.some(
    (field) => MONETARY_PRODUCT_FIELDS.includes(field)
  ));
  if (monetaryRows.length === 0) return;
  const requestedFields = [...new Set(
    monetaryRows.flatMap((row) => row.requested.requestedFields)
  )];
  try {
    assertProductUpdateAuthorized(role, {requestedFields});
  } catch (error) {
    if (!(error instanceof HttpsError)) throw error;
    throw new HttpsError(
      "permission-denied",
      `${error.message} ${describeRows(monetaryRows.map((row) => row.index))} ` +
      "do so."
    );
  }
}

/** The identity every audit entry of one bulk change is correlated by. */
export function productBatchId(identityDocumentId: string): string {
  return `pb_${identityDocumentId.slice(0, 40)}`;
}

/**
 * The audit entry one row of one bulk change writes.
 *
 * Derived from the product rather than from the row's position, so re-sending a
 * request with its rows in a different order lands on the same documents. A
 * replay never reaches here - the idempotency record answers it - and when one
 * does, the audit entry's `create` refuses it, which is what makes reusing a
 * deterministic ID safe.
 */
export function productBatchRowUpdateId(
  identityDocumentId: string,
  productId: string
): string {
  // The separator is a NUL, matching `buildIdempotencyIdentity`, so no pair of
  // fields can be re-split into a different pair. It is written as an escape
  // because it reached this file as a literal NUL byte on 2026-08-08, which made
  // `grep` report the whole module as binary and find nothing in it. It must stay
  // a NUL rather than become a space: this digest is what every audit entry of
  // every bulk change is addressed by.
  const digest = createHash("sha256")
    .update(`${identityDocumentId}\u0000${productId}`)
    .digest("hex");
  return `pu_${digest.slice(0, 40)}`;
}

/**
 * What one bulk request is fingerprinted by, so a retry is recognised.
 *
 * The rows are hashed by their normalized values rather than by what was typed,
 * so a retry that re-serializes the same price a different way hashes the same.
 * `cost` is included, and its absence is distinct from an explicit null - the two
 * mean different things, and a fingerprint that could not tell them apart would
 * answer a clear-the-cost request off a record made for a leave-it-alone one.
 *
 * Order is part of the fingerprint, deliberately. Every outcome is indexed by
 * where its row sat, so a retry that sends the same corrections in a different
 * order would be answered off a stored record whose indexes name different rows.
 * Refusing it as `already-exists` is the honest answer; the corrections
 * themselves are unaffected, because a row's audit entry is identified by its
 * product rather than by its position.
 */
export function productBatchFingerprintInput(
  input: ProductBatchInput
): {rows: readonly unknown[]} {
  return {
    rows: input.rows.map((row) => ({
      productId: row.productId,
      name: row.requested.name,
      sku: row.requested.sku,
      priceMinor: row.requested.priceMinor,
      costMinor: row.requested.costMinor,
      categoryId: row.requested.categoryId,
    })),
  };
}

function describeProduct(product: SellableProduct): ProductBatchRowProduct {
  return {
    name: product.name,
    sku: product.sku,
    price: product.price,
    priceMinor: product.priceMinor,
    cost: product.cost,
    costMinor: product.costMinor,
    categoryId: product.categoryId,
  };
}

function failedOutcome(
  index: number,
  productId: string | null,
  code: string,
  message: string
): ProductBatchRowOutcome {
  return {
    index,
    productId,
    status: "failed",
    changedFields: [],
    updateId: null,
    code,
    message,
    product: null,
  };
}

/**
 * Decides every row of one bulk change against what is stored.
 *
 * A row is planned by exactly the function `updateProduct` plans one product
 * with, so the two paths cannot validate differently: the same price arithmetic,
 * the same strict read of the *resulting* document, the same refusal to write a
 * product no device could parse. The only difference is what an unchanged row
 * means, and that difference is argued in [planProductUpdate].
 *
 * Outcomes come back in request order regardless of which pass produced them, so
 * a caller can line them up against its own rows by position as well as by
 * index.
 */
export function planProductBatch(options: {
  input: ProductBatchInput;
  identityDocumentId: string;
  storedProducts: ReadonlyMap<string, StoredProductFields | undefined>;
  existingCategoryIds: ReadonlySet<string>;
}): ProductBatchPlan {
  const commits = options.input.mode === "commit";
  const outcomes: ProductBatchRowOutcome[] = options.input.refusals.map(
    (refusal) => failedOutcome(
      refusal.index,
      refusal.productId,
      refusal.code,
      refusal.message
    )
  );
  const writes: ProductBatchRowWrite[] = [];

  for (const row of options.input.rows) {
    try {
      // A category is checked whenever one is named, not only when it moves -
      // the same rule the single-product path keeps, and for the same reason: a
      // product filed under a category that does not exist is invisible to every
      // grouped catalog surface without being unreadable.
      if (
        row.requested.categoryId !== undefined &&
        !options.existingCategoryIds.has(row.requested.categoryId)
      ) {
        throw new HttpsError(
          "failed-precondition",
          "The category does not exist in this business."
        );
      }
      const plan = planProductUpdate({
        product: options.storedProducts.get(row.productId),
        requested: row.requested,
        allowUnchanged: true,
      });
      if (plan.changes.length === 0) {
        outcomes.push({
          index: row.index,
          productId: row.productId,
          status: "unchanged",
          changedFields: [],
          updateId: null,
          code: null,
          message: null,
          product: describeProduct(plan.product),
        });
        continue;
      }
      const updateId = productBatchRowUpdateId(
        options.identityDocumentId,
        row.productId
      );
      outcomes.push({
        index: row.index,
        productId: row.productId,
        status: "updated",
        changedFields: [...plan.changedFields],
        updateId: commits ? updateId : null,
        code: null,
        message: null,
        product: describeProduct(plan.product),
      });
      if (commits) {
        writes.push({
          productId: row.productId,
          updateId,
          rowIndex: row.index,
          documentUpdate: plan.documentUpdate,
          changes: plan.changes,
          changedFields: plan.changedFields,
        });
      }
    } catch (error) {
      if (!(error instanceof HttpsError)) throw error;
      outcomes.push(
        failedOutcome(row.index, row.productId, error.code, error.message)
      );
    }
  }

  outcomes.sort((left, right) => left.index - right.index);
  return {
    outcomes,
    writes,
    updatedCount: outcomes.filter((row) => row.status === "updated").length,
    unchangedCount: outcomes.filter((row) => row.status === "unchanged").length,
    failedCount: outcomes.filter((row) => row.status === "failed").length,
  };
}
