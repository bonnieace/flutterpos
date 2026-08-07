import {HttpsError} from "firebase-functions/v2/https";
import {TenantRole} from "../core/model";
import {requireDocumentId} from "../core/validation";

/**
 * What may be corrected about a product, and what the correction must satisfy.
 *
 * A product's name, code, and price were permanent until this module existed.
 * `allow update` on `products/{productId}` permits a strictly decreasing
 * `quantity` and nothing else - the checkout decrement - so no client could ever
 * fix a mistyped price, and the only remedy was an operator with the Admin SDK.
 *
 * The way out was decided as a callable rather than a wider rule, and the three
 * reasons are the three things this module is responsible for:
 *
 * - **`firestore.rules` does not change at all.** The Admin SDK bypasses rules,
 *   so the single tight `allow update` clause that is the whole guarantee no
 *   client can inflate stock stays byte-identical. Which makes this module the
 *   only thing standing between a correction and that guarantee: it never names
 *   `quantity`, and [readProductUpdateInput] refuses a payload that mentions it.
 * - **A price is money, so a change to one is recorded.** A rule-based edit
 *   would write `updatedAt` and nothing else - no actor, no previous value, no
 *   reason - and "this was 450 last week, who made it 45?" would be
 *   unanswerable. The plan therefore carries the before and after of every field
 *   it changes, for the audit entry the caller writes.
 * - **Validation becomes a guarantee only on the server.** A rule can check
 *   `price is number && price >= 0`; it cannot check that the amount survives
 *   the till's own minor-unit conversion, so `19.999` would pass the rule and
 *   then fail at the till with a customer standing there. Nor can it check that
 *   `name` and `SKU` stay in the shape the strict read model demands, and one
 *   unparseable product makes the *whole* cached catalog a miss.
 *
 * The last of those is why [readSellableProduct] checks the **resulting**
 * document rather than only the fields being written. A product that is already
 * broken in a field this request does not name is a worse problem than the typo
 * being fixed, and quietly making it less broken would report success while the
 * catalog stayed unreadable. The contract is instead: name every broken field in
 * one request, or none of them.
 */

/**
 * The longest name this callable will write, matching the client's
 * `maximumCatalogNameLength`.
 *
 * Nothing on the server bounded it before: `allow create` checks only that
 * `quantity is int`. The bound exists so a name cannot be pasted long enough to
 * make every catalog and receipt surface unreadable.
 */
export const MAXIMUM_PRODUCT_NAME_LENGTH = 120;

/** The longest SKU this callable will write, bounded for the same reason. */
export const MAXIMUM_PRODUCT_SKU_LENGTH = 64;

/**
 * The largest price in minor units, matching the client's
 * `maximumCheckoutMinorAmount`.
 *
 * A price above it is one the till refuses to put in a cart, so writing it would
 * create a product that cannot be sold.
 */
export const MAXIMUM_PRODUCT_PRICE_MINOR_UNITS = 100_000_000_000;

/**
 * The tolerance the till uses when deciding a major-unit price is exactly
 * representable in minor units, copied from `checkoutMinorUnitsFromMajor`.
 *
 * It exists because `19.99 * 100` is `1998.9999999999998` in binary floating
 * point, not `1999`. The same constant on both sides is what makes a price this
 * callable accepts a price the till can always convert back.
 */
const PRICE_REPRESENTATION_TOLERANCE = 1e-6;

/** The fields a caller may correct. `quantity` is deliberately not among them. */
export const EDITABLE_PRODUCT_FIELDS = [
  "name",
  "sku",
  "price",
  "cost",
  "categoryId",
] as const;

export type EditableProductField = (typeof EDITABLE_PRODUCT_FIELDS)[number];

/**
 * Every key this callable's payload may carry.
 *
 * An unknown key is refused rather than ignored. Silently dropping one would
 * make "this callable never writes `quantity`" an implementation detail a caller
 * has to take on trust; refusing makes it observable from outside.
 */
const ACCEPTED_REQUEST_KEYS = new Set<string>([
  "tenantId",
  "productId",
  "requestId",
  ...EDITABLE_PRODUCT_FIELDS,
]);

/**
 * Correcting a product's description is an operational act, and these are the
 * roles the `products` create rule already names.
 */
export const PRODUCT_UPDATE_ROLES = ["owner", "admin", "manager"] as const;

/**
 * Changing a price is narrower, and this is a decision rather than an inherited
 * split.
 *
 * Creating a product is owner/admin/manager and retiring one is owner/admin. A
 * price edit is closer in consequence to retiring than to creating: it changes
 * what every subsequent sale records, silently, for a business that will not
 * notice until reconciliation. So a manager may fix a name, a code, or a
 * misfiled category, and only an owner or an administrator may change money.
 */
export const PRODUCT_PRICE_ROLES = ["owner", "admin"] as const;

/**
 * The fields that are money, and therefore sit behind {@link PRODUCT_PRICE_ROLES}.
 *
 * `cost` is here for a second reason on top of the one above: it is the
 * business's margin written down. Every active member can already *read* a
 * product document - the till cannot price a sale otherwise - so this is a
 * boundary on who may state a cost, not a guarantee that nobody else can see
 * one. That limit is deliberate and recorded rather than implied.
 */
export const MONETARY_PRODUCT_FIELDS: readonly EditableProductField[] = [
  "price",
  "cost",
];

/** The fields this module reads from `tenants/{tenantId}/products/{productId}`. */
export interface StoredProductFields {
  name?: unknown;
  SKU?: unknown;
  price?: unknown;

  /**
   * What one unit cost the business, when it has recorded one.
   *
   * Optional at every layer. No product created before this field existed
   * carries one, and the client's read model refuses a *present* but unusable
   * cost while accepting an absent one - so requiring it here would make this
   * callable unable to correct the very products most likely to need it.
   */
  cost?: unknown;

  quantity?: unknown;
  categoryId?: unknown;

  /**
   * The legacy alias for `categoryId`, still accepted by the client's read model
   * while migration is in progress. When both are present they must name the
   * same category, which is why a plan that changes one changes both.
   */
  category?: unknown;

  image?: unknown;
}

/** A product every client can parse and the till can sell. */
export interface SellableProduct {
  name: string;
  sku: string;
  price: number;
  priceMinor: number;

  /** Null when this business has not recorded what the product cost. */
  cost: number | null;
  costMinor: number | null;

  quantity: number;
  categoryId: string;
}

/** One field's correction, as the audit entry records it. */
export interface ProductFieldChange {
  field: EditableProductField;

  /**
   * What the document held, or null when it held nothing usable.
   *
   * A field being corrected is exactly the field most likely to have been
   * unreadable, so this cannot promise a string or a number. Null is recorded
   * rather than the raw value: Firestore has no `undefined`, and an audit entry
   * carrying an arbitrary stored object would be a second place a malformed
   * product could hide.
   */
  previous: string | number | null;

  /** Null only for a cleared cost - the one field whose absence is meaningful. */
  next: string | number | null;
}

/** Exactly what one accepted correction writes, and what it replaces. */
export interface ProductUpdatePlan {
  changes: readonly ProductFieldChange[];
  changedFields: readonly EditableProductField[];

  /**
   * The keys written to the product document, `updatedAt` excluded because the
   * writer owns the server timestamp.
   *
   * Only changed fields appear. A request naming a field that already holds the
   * requested value writes nothing for it, so an audit entry never claims a
   * change that did not happen.
   */
  documentUpdate: Record<string, string | number | null>;

  /** What the product holds once the plan is applied. */
  product: SellableProduct;
}

/** The corrections one payload asked for, normalized and bounded. */
export interface ProductUpdateInput {
  name?: string;
  sku?: string;

  /** The requested price in exact minor units, as a sale line records it. */
  priceMinor?: number;

  /**
   * The requested cost in exact minor units, as a sale line records it.
   *
   * `null` is a request to *clear* a recorded cost, which is distinct from
   * omitting the key. Clearing is offered because a cost entered by mistake
   * would otherwise be uncorrectable, and reporting a wrong margin as fact is
   * worse than reporting none.
   */
  costMinor?: number | null;

  categoryId?: string;

  /**
   * The editable keys the payload named, before anything is compared with what
   * is stored.
   *
   * Authorization reads this rather than the resulting diff, so "a request that
   * names a price needs an owner or an administrator" holds whether or not the
   * price turns out to differ. A manager whose permission depended on the value
   * already in the document would be a rule nobody could explain.
   */
  requestedFields: readonly EditableProductField[];
}

/**
 * Collapses whitespace and bounds a value the strict read model must accept.
 *
 * `TenantProduct` requires a non-empty string equal to its own trim and free of
 * control characters, so the value is normalized into that shape rather than
 * refused for a stray space - the same treatment the catalog create surface
 * gives it.
 */
function normalizeProductName(value: unknown): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", "name must be a string.");
  }
  const name = value.trim().replace(/\s+/g, " ");
  if (name.length === 0 || name.length > MAXIMUM_PRODUCT_NAME_LENGTH) {
    throw new HttpsError(
      "invalid-argument",
      `name must be between 1 and ${MAXIMUM_PRODUCT_NAME_LENGTH} characters.`
    );
  }
  if (/\p{Cc}/u.test(name)) {
    throw new HttpsError("invalid-argument", "name contains unsupported characters.");
  }
  return name;
}

/**
 * Bounds a stock-keeping unit and refuses whitespace anywhere inside it.
 *
 * A SKU is what the till matches a scan against, exactly and case-folded. A
 * scanner cannot emit a space, so a code containing one could be typed but never
 * scanned, which is the one job the field has.
 */
function normalizeProductSku(value: unknown): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", "sku must be a string.");
  }
  const sku = value.trim();
  if (sku.length === 0 || sku.length > MAXIMUM_PRODUCT_SKU_LENGTH) {
    throw new HttpsError(
      "invalid-argument",
      `sku must be between 1 and ${MAXIMUM_PRODUCT_SKU_LENGTH} characters.`
    );
  }
  if (/\s/.test(sku) || /\p{Cc}/u.test(sku)) {
    throw new HttpsError("invalid-argument", "sku cannot contain whitespace.");
  }
  return sku;
}

/**
 * The exact minor units a major-unit price is worth, or nothing.
 *
 * This is `checkoutMinorUnitsFromMajor` from `lib/checkout/checkout_draft.dart`,
 * arithmetic for arithmetic. Both sides must agree or the guarantee is empty:
 * the point of validating here is that the till can never meet a catalog price
 * it refuses as `price_not_representable` with a customer waiting.
 */
export function productPriceMinorUnits(value: unknown): number | undefined {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
    return undefined;
  }
  const scaled = value * 100;
  if (scaled > MAXIMUM_PRODUCT_PRICE_MINOR_UNITS) return undefined;
  const rounded = Math.round(scaled);
  if (Math.abs(scaled - rounded) > PRICE_REPRESENTATION_TOLERANCE) return undefined;
  return rounded < 0 || rounded > MAXIMUM_PRODUCT_PRICE_MINOR_UNITS ?
    undefined : rounded;
}

function requireProductCostMinorUnits(value: unknown): number {
  if (typeof value !== "number") {
    throw new HttpsError("invalid-argument", "cost must be a number or null.");
  }
  const minorUnits = productPriceMinorUnits(value);
  if (minorUnits === undefined) {
    throw new HttpsError(
      "invalid-argument",
      "cost must be a non-negative amount with at most two decimal places."
    );
  }
  return minorUnits;
}

function requireProductPriceMinorUnits(value: unknown): number {
  if (typeof value !== "number") {
    throw new HttpsError("invalid-argument", "price must be a number.");
  }
  const minorUnits = productPriceMinorUnits(value);
  if (minorUnits === undefined) {
    throw new HttpsError(
      "invalid-argument",
      "price must be a non-negative amount with at most two decimal places."
    );
  }
  return minorUnits;
}

/**
 * Reads the corrections one payload asks for.
 *
 * Absent and null both mean "leave this field alone", matching every other
 * optional argument in this codebase. Naming no editable field at all is refused
 * rather than treated as a successful no-op, because it can only be a caller
 * defect and answering `ok` to it would put an idempotency record and an audit
 * entry behind a request that did nothing.
 */
export function readProductUpdateInput(
  data: Record<string, unknown>
): ProductUpdateInput {
  if ("quantity" in data) {
    // The single most important refusal in this module. A callable that could
    // write both a price and a quantity would be a second way to move stock
    // without a `stock_movements` entry, which is the property `adjustStock`
    // exists to guarantee.
    throw new HttpsError(
      "invalid-argument",
      "quantity is not editable here. Use adjustStock, which records a stock movement."
    );
  }
  for (const key of Object.keys(data)) {
    if (!ACCEPTED_REQUEST_KEYS.has(key)) {
      throw new HttpsError(
        "invalid-argument",
        `${key} is not an editable product field.`
      );
    }
  }

  const requestedFields: EditableProductField[] = [];
  const input: ProductUpdateInput = {requestedFields};
  if (data.name !== undefined && data.name !== null) {
    input.name = normalizeProductName(data.name);
    requestedFields.push("name");
  }
  if (data.sku !== undefined && data.sku !== null) {
    input.sku = normalizeProductSku(data.sku);
    requestedFields.push("sku");
  }
  if (data.price !== undefined && data.price !== null) {
    input.priceMinor = requireProductPriceMinorUnits(data.price);
    requestedFields.push("price");
  }
  if ("cost" in data && data.cost !== undefined) {
    // Unlike every other field here, an explicit null is meaningful rather than
    // "leave it alone": it clears a cost that was recorded by mistake.
    input.costMinor = data.cost === null ?
      null :
      requireProductCostMinorUnits(data.cost);
    requestedFields.push("cost");
  }
  if (data.categoryId !== undefined && data.categoryId !== null) {
    input.categoryId = requireDocumentId(data.categoryId, "categoryId");
    requestedFields.push("categoryId");
  }
  if (requestedFields.length === 0) {
    throw new HttpsError(
      "invalid-argument",
      "Name at least one of name, sku, price, cost, or categoryId to change."
    );
  }
  return input;
}

/**
 * Refuses a price change by a principal who may correct everything else.
 *
 * Read from the requested fields rather than from the resulting diff on purpose
 * - see [ProductUpdateInput.requestedFields].
 */
export function assertProductUpdateAuthorized(
  role: TenantRole,
  requested: ProductUpdateInput
): void {
  const monetary = requested.requestedFields.filter(
    (field) => MONETARY_PRODUCT_FIELDS.includes(field)
  );
  if (monetary.length === 0) return;
  if (!(PRODUCT_PRICE_ROLES as readonly string[]).includes(role)) {
    throw new HttpsError(
      "permission-denied",
      monetary.includes("price") ?
        "Only an owner or an administrator may change a product's price." :
        "Only an owner or an administrator may change what a product costs."
    );
  }
}

/** A stored value repeated into an audit entry, or null when it is unusable. */
function describePrevious(value: unknown): string | number | null {
  if (typeof value === "string") return value;
  if (typeof value === "number" && Number.isFinite(value)) return value;
  return null;
}

/** Raised where the stored document, not the request, is what refuses. */
function unusableProduct(message: string): HttpsError {
  return new HttpsError("failed-precondition", message);
}

function requireReadableString(value: unknown, field: string): string {
  if (
    typeof value !== "string" || value.length === 0 || value !== value.trim() ||
    /\p{Cc}/u.test(value)
  ) {
    throw unusableProduct(
      `This product's ${field} is unreadable. Correct it in the same request.`
    );
  }
  return value;
}

/**
 * Reads a product only if it would parse and the till could sell it.
 *
 * This is the server-side twin of `TenantProduct.fromDocument` plus the till's
 * own price conversion, and the caller runs it against the document as it will
 * exist once the plan is applied. Both halves matter and they fail for different
 * reasons: an unparseable field makes the whole cached catalog a miss, so the
 * business stops selling everything; an unrepresentable price only makes this
 * one product unsellable. Neither is an acceptable state to write, and neither
 * is an acceptable state to leave behind while reporting success.
 *
 * `quantity` is read here and written nowhere. A product whose stored quantity
 * is not an integer cannot be corrected by this callable or by `adjustStock`, so
 * saying so plainly is more useful than a green result that changes nothing the
 * till can observe.
 */
export function readSellableProduct(fields: StoredProductFields): SellableProduct {
  const name = requireReadableString(fields.name, "name");
  const sku = requireReadableString(fields.SKU, "SKU");
  if (
    typeof fields.price !== "number" || !Number.isFinite(fields.price) ||
    fields.price < 0
  ) {
    throw unusableProduct(
      "This product's price is unreadable. Correct it in the same request."
    );
  }
  const priceMinor = productPriceMinorUnits(fields.price);
  if (priceMinor === undefined) {
    throw unusableProduct(
      "This product's price cannot be represented in minor units, so the till " +
      "refuses to sell it. Correct it in the same request."
    );
  }
  // A cost is optional, so absent is not a fault. A *present* cost that cannot
  // be read is refused for the same reason a price is: a sale line copies this
  // figure, and a cost the till cannot convert would silently record no cost at
  // all and report the product's whole revenue as profit.
  let cost: number | null = null;
  let costMinor: number | null = null;
  if (fields.cost !== undefined && fields.cost !== null) {
    if (
      typeof fields.cost !== "number" || !Number.isFinite(fields.cost) ||
      fields.cost < 0
    ) {
      throw unusableProduct(
        "This product's cost is unreadable. Correct it in the same request, or " +
        "clear it by sending cost: null."
      );
    }
    const converted = productPriceMinorUnits(fields.cost);
    if (converted === undefined) {
      throw unusableProduct(
        "This product's cost cannot be represented in minor units, so a sale " +
        "could not record it. Correct it in the same request, or clear it by " +
        "sending cost: null."
      );
    }
    cost = fields.cost;
    costMinor = converted;
  }
  if (!Number.isSafeInteger(fields.quantity)) {
    throw unusableProduct(
      "This product's stock quantity is not an integer, which no callable can " +
      "correct. It needs an operator."
    );
  }
  const hasCurrent = fields.categoryId !== undefined && fields.categoryId !== null;
  const hasLegacy = fields.category !== undefined && fields.category !== null;
  if (!hasCurrent && !hasLegacy) {
    throw unusableProduct(
      "This product's categoryId is unreadable. Correct it in the same request."
    );
  }
  const categoryId = requireReadableString(
    hasCurrent ? fields.categoryId : fields.category,
    "categoryId"
  );
  if (categoryId.includes("/") || categoryId === "." || categoryId === "..") {
    throw unusableProduct(
      "This product's categoryId is unreadable. Correct it in the same request."
    );
  }
  if (hasCurrent && hasLegacy && fields.category !== fields.categoryId) {
    throw unusableProduct(
      "This product's categoryId and its legacy category alias name different " +
      "categories, so no device can read it."
    );
  }
  if (fields.image !== undefined && fields.image !== null && fields.image !== "") {
    const image = fields.image;
    if (
      typeof image !== "string" || image !== image.trim() ||
      !/^https:\/\/[^/\s]+/.test(image)
    ) {
      throw unusableProduct(
        "This product's image is not an HTTPS URL, which this callable cannot " +
        "correct. It needs an operator."
      );
    }
  }
  return {
    name,
    sku,
    price: fields.price,
    priceMinor,
    cost,
    costMinor,
    quantity: fields.quantity as number,
    categoryId,
  };
}

/**
 * Decides the one correction a payload and a stored product permit.
 *
 * Nothing is written for a field that already holds the requested value, and a
 * request that changes nothing at all is refused. That refusal is reachable only
 * with a fresh request ID: a genuine retry answers off the idempotency record
 * and never arrives here.
 */
export function planProductUpdate(input: {
  product: StoredProductFields | undefined;
  requested: ProductUpdateInput;
}): ProductUpdatePlan {
  const stored = input.product;
  if (!stored) {
    throw new HttpsError("not-found", "The product does not exist in this business.");
  }
  const requested = input.requested;

  // The document as it will exist, checked before anything is compared, so a
  // refusal names the state rather than the diff.
  const resulting: StoredProductFields = {...stored};
  if (requested.name !== undefined) resulting.name = requested.name;
  if (requested.sku !== undefined) resulting.SKU = requested.sku;
  if (requested.priceMinor !== undefined) {
    // Derived from the minor units rather than from what was sent, so the stored
    // figure is exactly the one the till will convert back.
    resulting.price = requested.priceMinor / 100;
  }
  if (requested.costMinor !== undefined) {
    // Null clears. Assigning null rather than deleting the key is deliberate:
    // the client's read model treats a stored null and an absent key the same
    // way, and null is the one value that reliably overwrites a stored figure
    // through a merge. It is also what makes clearing the escape hatch for a
    // cost too malformed to correct - `readSellableProduct` below sees the
    // cleared value, not the stored garbage.
    resulting.cost = requested.costMinor === null ?
      null :
      requested.costMinor / 100;
  }
  if (requested.categoryId !== undefined) {
    resulting.categoryId = requested.categoryId;
    // A stored legacy alias moves with it. Leaving it behind would make the two
    // disagree, and the client's read model refuses a product whose `category`
    // and `categoryId` name different categories - which would take the whole
    // cached catalog down with it.
    if (stored.category !== undefined && stored.category !== null) {
      resulting.category = requested.categoryId;
    }
  }
  const product = readSellableProduct(resulting);

  const changes: ProductFieldChange[] = [];
  const documentUpdate: Record<string, string | number | null> = {};
  if (requested.name !== undefined && stored.name !== product.name) {
    changes.push({
      field: "name",
      previous: describePrevious(stored.name),
      next: product.name,
    });
    documentUpdate.name = product.name;
  }
  if (requested.sku !== undefined && stored.SKU !== product.sku) {
    changes.push({
      field: "sku",
      previous: describePrevious(stored.SKU),
      next: product.sku,
    });
    documentUpdate.SKU = product.sku;
  }
  if (requested.priceMinor !== undefined && stored.price !== product.price) {
    changes.push({
      field: "price",
      previous: describePrevious(stored.price),
      next: product.price,
    });
    documentUpdate.price = product.price;
  }
  if (requested.costMinor !== undefined) {
    // "Was a cost recorded at all" is asked separately from "what was it",
    // because both transitions are real changes and one of them - clearing a
    // stored value this module cannot even read - would otherwise compare equal
    // to null and be refused as a no-op.
    const storedHasCost = stored.cost !== undefined && stored.cost !== null;
    const storedCost = typeof stored.cost === "number" ? stored.cost : null;
    const changed = product.cost === null ?
      storedHasCost :
      !storedHasCost || storedCost !== product.cost;
    if (changed) {
      changes.push({
        field: "cost",
        previous: describePrevious(stored.cost),
        next: product.cost,
      });
      documentUpdate.cost = product.cost;
    }
  }
  // Compared against the effective category rather than against `categoryId`
  // alone, so a legacy-only document asked for the category it already holds
  // records no change instead of an audit row whose before and after are equal.
  const storedCategoryId = stored.categoryId ?? stored.category;
  if (requested.categoryId !== undefined && storedCategoryId !== product.categoryId) {
    changes.push({
      field: "categoryId",
      previous: describePrevious(storedCategoryId),
      next: product.categoryId,
    });
    documentUpdate.categoryId = product.categoryId;
    if (stored.category !== undefined && stored.category !== null) {
      documentUpdate.category = product.categoryId;
    }
  }
  if (changes.length === 0) {
    throw unusableProduct("This product already holds every value in the request.");
  }

  return {
    changes,
    changedFields: changes.map((change) => change.field),
    documentUpdate,
    product,
  };
}
