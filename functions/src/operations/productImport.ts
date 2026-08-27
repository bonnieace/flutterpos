import {createHash} from "node:crypto";
import {HttpsError} from "firebase-functions/v2/https";
import {TenantRole} from "../core/model";
import {requireDocumentId, requireObject, requireString} from "../core/validation";
import {ProductBatchMode, describeRows, readProductBatchMode} from "./productBatch";
import {
  ProductUpdateInput,
  StoredProductFields,
  assertProductUpdateAuthorized,
  readProductUpdateInput,
  readSellableProduct,
  productSearchFields,
} from "./productUpdate";

/**
 * Creating many products from a spreadsheet, and saying exactly what that would
 * do before it does it.
 *
 * This is the second half of the bulk catalog rewrite. The first half,
 * `updateProducts`, corrects products that already exist; this one brings them
 * into existence. It reuses that module's envelope - the required mode, the
 * bounded row list, the per-row outcome, the preview that writes nothing - and
 * it is a genuinely different program underneath, because a create raises three
 * problems a correction never does:
 *
 * - **A spreadsheet names "Bakery", not `ct_7f3a`.** The previous app wrote the
 *   display name straight into `category`, which passes document-ID validation,
 *   matches no category document, and leaves the product invisible to every
 *   grouped surface without being unreadable - the hardest kind of wrong to
 *   notice. So a row may name a category by ID or by name, and a name is
 *   resolved against this business's own categories rather than trusted.
 * - **A deterministic ID has to be per row.** The client's create scheme is
 *   `pd_<40 hex of sha256("createTenantProduct tenantId createdBy requestId")>`,
 *   scoped by request - exactly right for one product and wrong for four
 *   hundred, which would all collide on it. So the row's position joins the
 *   digest, and order therefore becomes part of what a retry is recognised by.
 * - **A product is created holding nothing**, and an import is the one place
 *   that rule is inconvenient rather than merely strict. Stock that appears with
 *   no `stock_movements` entry has no recorded origin, so an opening quantity is
 *   written together with the ledger entry that says where those units came
 *   from - which is why this is the only payload in this codebase that may name
 *   a quantity at all.
 *
 * What carries over unchanged from the correction path is every rule about what
 * a product may hold: the same name and SKU normalization, the same price
 * arithmetic the till uses, the same monetary tier for `cost`, and the same
 * strict read of the resulting document through [readSellableProduct]. A row is
 * validated by the code that validates a correction, so the two cannot drift.
 */

/**
 * The most products one request may create.
 *
 * The write budget is bigger per row than a bulk correction's: a product, its
 * audit entry, and - when the row carries opening stock - a `stock_adjustments`
 * record and a `stock_movements` entry. Four documents, so fifty rows is at most
 * 200 writes plus the one idempotency record, against Firestore's limit of 500
 * in a transaction. That leaves the bound where `MAXIMUM_PRODUCT_BATCH_ROWS`
 * puts it and for the same reason: not the write limit, which is nowhere near
 * reached, but wanting a transaction that fails on contention to be cheap to
 * retry. It is also the figure a caller already chains against for the other
 * half of this feature, and two different bounds for one screen would be a trap.
 */
export const MAXIMUM_PRODUCT_IMPORT_ROWS = 50;

/**
 * The most categories this callable will read while resolving names.
 *
 * Resolving "Bakery" means holding this business's categories in memory, and
 * that read is unbounded unless something bounds it. A business with more
 * categories than this is refused **as a request** rather than row by row,
 * because the defect belongs to the business rather than to any row, and the
 * refusal says what to do instead: name `categoryId`, which needs no scan.
 *
 * Five hundred is far past plausible for a till - the catalog surface offers one
 * page of categories and a shop that used them all would be unable to file a
 * product by hand either.
 */
export const MAXIMUM_IMPORT_CATEGORY_SCAN = 500;

/**
 * The largest opening balance one imported row may carry.
 *
 * The same bound `adjustStock` puts on a single adjustment, deliberately: an
 * imported unit and an adjusted unit are the same unit, recorded through the
 * same ledger, and a bound one path enforces and the other does not would be a
 * way in rather than a rule.
 */
export const MAXIMUM_IMPORT_OPENING_STOCK = 1_000_000;

/** Why the opening ledger entry exists, in the words the stock ledger records. */
export const IMPORT_OPENING_STOCK_REASON =
  "Opening balance recorded by a catalog import.";

/** Every key one import request may carry. */
const ACCEPTED_IMPORT_KEYS = new Set<string>([
  "tenantId",
  "mode",
  "rows",
  "requestId",
]);

/**
 * Every key one imported row may carry.
 *
 * `categoryName` rather than `category`, and that is not a cosmetic choice. A
 * stored product's `category` is the **legacy alias for `categoryId`** and holds
 * an ID; the previous app's uploader wrote a display name into a field of that
 * name, which is the exact drift this rewrite exists to avoid repeating. A key
 * that means a name is therefore called one.
 */
const ACCEPTED_IMPORT_ROW_KEYS = new Set<string>([
  "name",
  "sku",
  "price",
  "cost",
  "quantity",
  "categoryId",
  "categoryName",
]);

/** What a row must name, because a product cannot be created without it. */
const REQUIRED_IMPORT_ROW_FIELDS = ["name", "sku", "price"] as const;

/** The keys a row hands to the correction path's own reader, unchanged. */
const DESCRIBED_IMPORT_ROW_KEYS = new Set<string>(["name", "sku", "price", "cost"]);

/** One row that parsed, ready to be planned against this business's categories. */
export interface ProductImportRow {
  /** Where the row sat in the request. It is also part of the product's ID. */
  index: number;

  /**
   * The descriptive fields, read and normalized by the correction path's own
   * reader so an imported product and a corrected one cannot differ in what
   * they are allowed to hold.
   */
  requested: ProductUpdateInput;

  /** The opening balance, zero when the row named none. */
  quantity: number;

  /** The category named by ID. Exactly one of this and [categoryName] is set. */
  categoryId?: string;

  /** The category named by name, to be resolved against this business. */
  categoryName?: string;
}

/** One row that could not be parsed, and why. */
export interface ProductImportRowRefusal {
  index: number;
  code: string;
  message: string;
}

/** Every row of one request, parsed: the plannable ones and the refused ones. */
export interface ProductImportInput {
  /**
   * Preview or commit, and the same type the bulk correction uses. Shared rather
   * than redeclared because it is one concept: a caller previews a spreadsheet
   * and commits it through whichever callable the rows turned out to need, and
   * two independently-defined modes would be two things to keep in step.
   */
  mode: ProductBatchMode;
  rows: readonly ProductImportRow[];
  refusals: readonly ProductImportRowRefusal[];

  /** How many rows the request carried, refusals included. */
  rowCount: number;
}

/**
 * What happened to one row.
 *
 * There is no `unchanged` here, unlike a bulk correction. A create either
 * happened or it did not: nothing about an import can be a no-op, because the
 * row describes a product that does not exist yet.
 */
export type ProductImportRowStatus = "created" | "failed";

/** What a row's product holds, in the shape the till reads it. */
export interface ProductImportRowProduct {
  name: string;
  sku: string;
  price: number;
  priceMinor: number;

  /** Null when the row recorded no cost, which is not the same as zero. */
  cost: number | null;
  costMinor: number | null;
  categoryId: string;

  /** The opening balance this product is created holding. */
  quantity: number;
}

/**
 * One row's result, carried back whether it worked or not.
 *
 * Every field is a value or null, never absent: the whole response is stored in
 * the idempotency record so a retry answers identically, and Firestore refuses
 * an `undefined`.
 */
export interface ProductImportRowOutcome {
  index: number;
  status: ProductImportRowStatus;

  /**
   * The product this row created.
   *
   * Null in a preview even for a row that would be created, for the reason
   * `updateProducts` keeps its `updateId` null there: an outcome from a preview
   * must never be mistakable for a record of something that exists. The ID is
   * derivable before the write - it is a digest of the request and the row's
   * position - and reporting it anyway would be reporting a document that is not
   * there.
   */
  productId: string | null;

  /**
   * The stock adjustment recording where this product's opening units came from.
   * Null in a preview, and null for a row that opened holding nothing.
   */
  adjustmentId: string | null;

  /** The refusal code and message, both null unless the status is `failed`. */
  code: string | null;
  message: string | null;

  /**
   * What the product holds, or - in a preview - what it would hold. Null for a
   * failed row, which is the one case where there is no answer to give.
   */
  product: ProductImportRowProduct | null;
}

/** One product's creation, as the writer applies it. */
export interface ProductImportRowWrite {
  rowIndex: number;
  productId: string;

  /** Null when the row opens holding nothing, and no ledger entry is written. */
  adjustmentId: string | null;
  auditId: string;

  /**
   * The product document's own keys, `createdBy` and the server timestamps
   * excluded because the writer owns those.
   */
  documentData: Record<string, string | number | readonly string[]>;
  product: ProductImportRowProduct;
}

/** Everything one request decided: what to report, and what to write. */
export interface ProductImportPlan {
  outcomes: ProductImportRowOutcome[];

  /** Empty in a preview, because a preview writes nothing. */
  writes: ProductImportRowWrite[];
  createdCount: number;
  failedCount: number;
}

/**
 * This business's categories, as name resolution needs them.
 *
 * A map from folded name to IDs rather than to one ID, because nothing in this
 * app makes a category name unique - `allow create` on `categories` checks
 * nothing at all, and the catalog surface offers no rename and no delete. Two
 * categories called "Bakery" are therefore a state a business can reach, and a
 * row naming that name has no honest answer.
 */
export interface ProductImportCategories {
  ids: ReadonlySet<string>;
  byFoldedName: ReadonlyMap<string, readonly string[]>;
}

/**
 * How two category names are compared.
 *
 * Case-insensitively, over collapsed whitespace. A spreadsheet's "bakery" and a
 * catalog's "Bakery" are one category to everybody who is not a computer, and
 * treating them as two would create a second grouping this app has no way to
 * merge, rename, or delete.
 */
export function foldCategoryName(value: string): string {
  return value.trim().replace(/\s+/g, " ").toLowerCase();
}

/**
 * The opening balance one row carries.
 *
 * `updateProduct` refuses a payload that so much as mentions a quantity, and
 * this is the one path that accepts one. The difference is not a relaxation: the
 * refusal exists because a quantity written with no `stock_movements` entry has
 * no recorded origin, and this path writes that entry in the same transaction.
 * A row that opens holding nothing is the ordinary case and writes no ledger
 * entry, exactly as the catalog's own create form behaves.
 */
function readOpeningQuantity(value: unknown): number {
  if (value === undefined || value === null) return 0;
  if (
    !Number.isSafeInteger(value) ||
    (value as number) < 0 ||
    (value as number) > MAXIMUM_IMPORT_OPENING_STOCK
  ) {
    throw new HttpsError(
      "invalid-argument",
      "quantity must be a whole number of units between 0 and " +
      `${MAXIMUM_IMPORT_OPENING_STOCK}.`
    );
  }
  return value as number;
}

function readImportRow(value: unknown, index: number): ProductImportRow {
  const row = requireObject(value, `rows[${index}]`);
  for (const key of Object.keys(row)) {
    if (!ACCEPTED_IMPORT_ROW_KEYS.has(key)) {
      throw new HttpsError(
        "invalid-argument",
        `${key} is not part of an imported product.`
      );
    }
  }
  for (const field of REQUIRED_IMPORT_ROW_FIELDS) {
    if (row[field] === undefined || row[field] === null) {
      throw new HttpsError(
        "invalid-argument",
        `${field} is required to create a product.`
      );
    }
  }

  const hasId = row.categoryId !== undefined && row.categoryId !== null;
  const hasName = row.categoryName !== undefined && row.categoryName !== null;
  if (hasId === hasName) {
    throw new HttpsError(
      "invalid-argument",
      hasId ?
        "Name the category by categoryId or by categoryName, not both - if the " +
        "two disagree there is no honest way to decide which was meant." :
        "A product must be filed under a category, named by categoryId or by " +
        "categoryName."
    );
  }

  const described: Record<string, unknown> = {};
  for (const key of DESCRIBED_IMPORT_ROW_KEYS) {
    // An absent cost and an explicit null both mean "not recorded" here, so the
    // null is dropped at the door rather than carried through. This is the one
    // field where that differs from `updateProduct`, and it differs because
    // there is nothing to clear on a product that does not exist yet: a blank
    // spreadsheet cell means the business did not say, either way.
    if (row[key] !== undefined && row[key] !== null) described[key] = row[key];
  }

  return {
    index,
    requested: readProductUpdateInput(described, DESCRIBED_IMPORT_ROW_KEYS),
    quantity: readOpeningQuantity(row.quantity),
    categoryId: hasId ? requireDocumentId(row.categoryId, "categoryId") : undefined,
    categoryName: hasName ?
      requireString(row.categoryName, "categoryName", {maxLength: 120}) :
      undefined,
  };
}

/**
 * Reads one import request, keeping a row's own defect as that row's problem.
 *
 * Two things are refused for the whole request rather than reported per row, for
 * the reasons `readProductBatchInput` already records: an unknown top-level key,
 * and more rows than the bound.
 *
 * What is deliberately **not** refused here is a repeated product. A bulk
 * correction refuses a product named twice, because two rows addressing one
 * document are two conflicting intents with no honest outcome to report for
 * either. Two import rows describing the same thing are not that: each creates
 * its own document, under its own ID, and a shop legitimately stocking two
 * products with one name and one code is a state this app already permits and
 * the till already refuses to resolve by scan. SKU uniqueness is stated rather
 * than enforced everywhere else in this system, and an import is not the place
 * to invent it - a check against fifty rows would not see the four hundred
 * already in the catalog, which is a guarantee the next request breaks.
 */
export function readProductImportInput(
  data: Record<string, unknown>
): ProductImportInput {
  for (const key of Object.keys(data)) {
    if (!ACCEPTED_IMPORT_KEYS.has(key)) {
      throw new HttpsError(
        "invalid-argument",
        `${key} is not part of a product import.`
      );
    }
  }
  const mode = readProductBatchMode(data.mode);
  const rawRows = data.rows;
  if (!Array.isArray(rawRows)) {
    throw new HttpsError(
      "invalid-argument",
      "rows must be an array of products to create."
    );
  }
  if (rawRows.length === 0) {
    throw new HttpsError("invalid-argument", "rows must describe at least one product.");
  }
  if (rawRows.length > MAXIMUM_PRODUCT_IMPORT_ROWS) {
    throw new HttpsError(
      "invalid-argument",
      `rows carries ${rawRows.length} products and at most ` +
      `${MAXIMUM_PRODUCT_IMPORT_ROWS} are accepted. Send the rest as a further ` +
      "request with its own requestId."
    );
  }

  const rows: ProductImportRow[] = [];
  const refusals: ProductImportRowRefusal[] = [];
  for (let index = 0; index < rawRows.length; index += 1) {
    try {
      rows.push(readImportRow(rawRows[index], index));
    } catch (error) {
      if (!(error instanceof HttpsError)) throw error;
      refusals.push({index, code: error.code, message: error.message});
    }
  }
  return {mode, rows, refusals, rowCount: rawRows.length};
}

/**
 * Refuses an import that records what the business paid when the caller may not.
 *
 * **A price is not gated here, and that is a decision rather than an oversight.**
 * `updateProduct` puts a price behind owner or administrator because *changing*
 * one silently alters what every subsequent sale records for a business that
 * will not notice until reconciliation. Setting the first price is a different
 * act: it is creation, `allow create` on `products` already names the
 * operational three, and the catalog's own add-product form already lets a
 * manager type a price. An import that refused what the form beside it accepts
 * would be a rule nobody could explain.
 *
 * A cost is gated, for the reason it is gated everywhere: it is the business's
 * margin written down, and the create form refuses one from a manager too. The
 * tier is delegated to [assertProductUpdateAuthorized] so it cannot drift, and
 * the decision is made over every row before anything is read - a manager who
 * previewed green and then met a commit-time refusal would learn only that the
 * app guesses.
 */
export function assertProductImportAuthorized(
  role: TenantRole,
  rows: readonly ProductImportRow[]
): void {
  const costRows = rows.filter((row) => row.requested.costMinor !== undefined);
  if (costRows.length === 0) return;
  try {
    assertProductUpdateAuthorized(role, {requestedFields: ["cost"]});
  } catch (error) {
    if (!(error instanceof HttpsError)) throw error;
    throw new HttpsError(
      "permission-denied",
      `${error.message} ${describeRows(costRows.map((row) => row.index))} do so.`
    );
  }
}

/** The identity every audit entry of one import is correlated by. */
export function productImportId(identityDocumentId: string): string {
  return `im_${identityDocumentId.slice(0, 40)}`;
}

/**
 * The three documents one imported row is written at.
 *
 * All three come from one digest of the request identity and the row's
 * **position**, which is the part that differs from every other deterministic ID
 * in this codebase. A bulk correction derives a row's audit entry from the
 * product it corrects, so re-sending the rows in a different order lands on the
 * same documents. An import has no product to derive from - that is the whole
 * point of it - so position is the only identity a row has, and order therefore
 * becomes part of what a retry is recognised by. See
 * [productImportFingerprintInput], which is what stops a reordered retry
 * creating a second catalog rather than answering off the first.
 *
 * A replay never reaches these IDs - the idempotency record answers it - and
 * when one does, `create` refuses it, which is what makes reusing them safe.
 */
export function productImportRowIds(
  identityDocumentId: string,
  rowIndex: number
): {productId: string; adjustmentId: string; auditId: string} {
  // NUL-separated, matching `productBatchRowUpdateId` and
  // `buildIdempotencyIdentity`, and written as an escape rather than typed - see
  // the note beside the former for what typing it costs and why it must stay a
  // NUL. One convention across the three, so nobody comparing them has to wonder
  // which separator was deliberate.
  const digest = createHash("sha256")
    .update(`${identityDocumentId}\u0000${rowIndex}`)
    .digest("hex")
    .slice(0, 40);
  return {
    productId: `pd_${digest}`,
    adjustmentId: `sa_${digest}`,
    auditId: `pi_${digest}`,
  };
}

/**
 * What one import request is fingerprinted by, so a retry is recognised.
 *
 * The rows are hashed by their normalized values rather than by what was typed,
 * so a retry that re-serializes the same price a different way hashes the same.
 * An absent cost and an explicit null hash alike, because here they mean the
 * same thing - the opposite of `updateProduct`, where null clears a recorded
 * cost and absence leaves it alone.
 *
 * Order is part of the fingerprint and it matters more here than anywhere else:
 * a row's product ID is derived from where it sat, so a reordered retry answered
 * off the stored record would report IDs belonging to different products, and a
 * reordered retry *not* answered off it would create the whole catalog a second
 * time. Refusing it as `already-exists` is the only honest outcome.
 */
export function productImportFingerprintInput(
  input: ProductImportInput
): {rows: readonly unknown[]} {
  return {
    rows: input.rows.map((row) => ({
      name: row.requested.name,
      sku: row.requested.sku,
      priceMinor: row.requested.priceMinor,
      costMinor: row.requested.costMinor ?? null,
      quantity: row.quantity,
      categoryId: row.categoryId ?? null,
      categoryName: row.categoryName ?? null,
    })),
  };
}

/**
 * The category a row is filed under, or the reason it cannot be.
 *
 * An unmatched name refuses the row; it does **not** create the category. That
 * is the decision this chunk had to make, and it was made this way because a
 * category, once created, is permanent: the rules permit rename and delete and
 * this app offers neither, for the orphaning reason recorded in the catalog
 * decision. So "Bakry" typed once in a spreadsheet would become a grouping
 * nobody can rename, nobody can remove, and every product filed under it would
 * sit outside the "Bakery" every report groups by. The preview is what makes
 * refusing tolerable: a caller sees every unmatched name at once, before
 * anything is written, and the catalog surface already creates categories.
 */
function resolveImportCategory(
  row: ProductImportRow,
  categories: ProductImportCategories
): string {
  if (row.categoryId !== undefined) {
    if (!categories.ids.has(row.categoryId)) {
      throw new HttpsError(
        "failed-precondition",
        "The category does not exist in this business."
      );
    }
    return row.categoryId;
  }
  const name = row.categoryName as string;
  const matches = categories.byFoldedName.get(foldCategoryName(name)) ?? [];
  if (matches.length === 0) {
    throw new HttpsError(
      "failed-precondition",
      `No category in this business is named "${name}". Add it to the catalog ` +
      "first, then import."
    );
  }
  if (matches.length > 1) {
    throw new HttpsError(
      "failed-precondition",
      `${matches.length} categories in this business are named "${name}", so ` +
      "this row cannot say which one it means. Name the category by categoryId."
    );
  }
  return matches[0];
}

function failedOutcome(
  index: number,
  code: string,
  message: string
): ProductImportRowOutcome {
  return {
    index,
    status: "failed",
    productId: null,
    adjustmentId: null,
    code,
    message,
    product: null,
  };
}

/**
 * Decides every row of one import against this business's categories.
 *
 * The product each row describes is built as the document it will be and then
 * read back through [readSellableProduct] - the server-side twin of
 * `TenantProduct.fromDocument` - before anything is written. That is the same
 * guard the correction path applies to the *resulting* document, and it matters
 * more here: an import is the one operation that can add four hundred products
 * at once, and one product the till cannot parse makes the **whole** cached
 * catalog a miss, which stops the business selling everything.
 *
 * Outcomes come back in request order regardless of which pass produced them, so
 * a caller can line them up against its own rows by position as well as by
 * index.
 */
export function planProductImport(options: {
  input: ProductImportInput;
  identityDocumentId: string;
  categories: ProductImportCategories;
}): ProductImportPlan {
  const commits = options.input.mode === "commit";
  const outcomes: ProductImportRowOutcome[] = options.input.refusals.map(
    (refusal) => failedOutcome(refusal.index, refusal.code, refusal.message)
  );
  const writes: ProductImportRowWrite[] = [];

  for (const row of options.input.rows) {
    try {
      const categoryId = resolveImportCategory(row, options.categories);
      const requested = row.requested;
      const fields: StoredProductFields = {
        name: requested.name,
        SKU: requested.sku,
        // Derived from the minor units rather than from what was sent, so the
        // stored figure is exactly the one the till will convert back.
        price: (requested.priceMinor as number) / 100,
        quantity: row.quantity,
        categoryId,
      };
      if (requested.costMinor !== undefined && requested.costMinor !== null) {
        fields.cost = requested.costMinor / 100;
      }
      // The document as it will exist, read by the code every device reads it
      // with. Nothing below this line can produce a product the till refuses.
      const sellable = readSellableProduct(fields);
      const product: ProductImportRowProduct = {
        name: sellable.name,
        sku: sellable.sku,
        price: sellable.price,
        priceMinor: sellable.priceMinor,
        cost: sellable.cost,
        costMinor: sellable.costMinor,
        categoryId: sellable.categoryId,
        quantity: sellable.quantity,
      };
      const ids = productImportRowIds(options.identityDocumentId, row.index);
      outcomes.push({
        index: row.index,
        status: "created",
        productId: commits ? ids.productId : null,
        adjustmentId: commits && row.quantity > 0 ? ids.adjustmentId : null,
        code: null,
        message: null,
        product,
      });
      if (commits) {
        const search = productSearchFields(product.name, product.sku);
        writes.push({
          rowIndex: row.index,
          productId: ids.productId,
          adjustmentId: row.quantity > 0 ? ids.adjustmentId : null,
          auditId: ids.auditId,
          // Exactly the keys `TenantProductCreateIntent` writes, and no others.
          // A cost is omitted rather than written as null when none was
          // recorded, so "never recorded" and "recorded as nothing" stay
          // distinguishable in the document itself.
          documentData: {
            name: product.name,
            SKU: product.sku,
            price: product.price,
            ...(product.cost === null ? {} : {cost: product.cost}),
            quantity: product.quantity,
            categoryId: product.categoryId,
            searchName: search.searchName,
            searchPrefixes: search.searchPrefixes,
          },
          product,
        });
      }
    } catch (error) {
      if (!(error instanceof HttpsError)) throw error;
      outcomes.push(failedOutcome(row.index, error.code, error.message));
    }
  }

  outcomes.sort((left, right) => left.index - right.index);
  return {
    outcomes,
    writes,
    createdCount: outcomes.filter((row) => row.status === "created").length,
    failedCount: outcomes.filter((row) => row.status === "failed").length,
  };
}
