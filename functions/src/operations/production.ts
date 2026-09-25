import {FieldValue, getFirestore} from "firebase-admin/firestore";
import type {DocumentData, DocumentSnapshot, Firestore, Transaction} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {requireTenantMember} from "../core/authorization";
import {runIdempotentFirestoreTransaction} from "../core/idempotency";
import {requireDocumentId, requireObject, requireRequestId} from "../core/validation";
import {addStockQuantity, immutableLedgerId, normalizeReason, requireStoredQuantity} from "./domain";
import {MAXIMUM_IMPORT_OPENING_STOCK} from "./productImport";
import {
  MAXIMUM_PRODUCT_NAME_LENGTH,
  MAXIMUM_PRODUCT_PRICE_MINOR_UNITS,
  productPriceMinorUnits,
} from "./productUpdate";

/**
 * Completing one production batch: what was made, what it cost to make, and the
 * stock and cost that follow from both.
 *
 * **One step, and all of it or none of it.** The batch is saved, the product's
 * stock goes up by what was made, its cost becomes what one unit took to make,
 * and the ledger records the units - in one transaction. There is no draft: a
 * batch that exists without its stock, or stock that arrived without its batch,
 * is the state this function exists to make impossible.
 *
 * **The cost is recomputed here, never taken from the device.** A device sends
 * its own total and cost per unit so its overlay can draw the batch while it
 * waits; the server ignores both and works them out again from the expense
 * rows, so the figure every later sale is costed at is the server's arithmetic.
 *
 * **A batch that costs nothing cannot be made.** Every row must be above zero,
 * and a cost per unit that rounds to nothing is refused: a product costed at
 * zero reports its whole price as profit on every sale after it.
 *
 * **The server refuses only what a form could have caught**, for the reason a
 * delivery does. Whether a product is made here, or has been retired, can
 * change while a batch waits on a device with no connection; both are checked
 * on the form and never here.
 */

interface ProductionExpenseRequest {
  description?: unknown;
  amount?: unknown;
}

interface CompleteProductionRequest {
  tenantId?: unknown;
  batchId?: unknown;
  batchNumber?: unknown;
  productId?: unknown;
  productName?: unknown;
  quantity?: unknown;
  expenses?: unknown;
  totalCostMinor?: unknown;
  unitCostMinor?: unknown;
}

/** Who may complete a batch: the roles that receive stock. */
export const PRODUCTION_ROLES = ["owner", "admin", "manager"] as const;

/** The most expense rows one batch carries. */
export const MAXIMUM_PRODUCTION_EXPENSES = 20;

/** `PB-20260924-7F3A2C`: the business date, and six characters of the batch. */
export const PRODUCTION_BATCH_NUMBER = /^PB-\d{8}-[0-9A-F]{6}$/;

/**
 * `productName`, `totalCostMinor` and `unitCostMinor` are accepted and
 * ignored: the device carries them for its own overlay, and the server names
 * the product from the product and works the cost out itself.
 */
const ACCEPTED_REQUEST_KEYS = new Set<string>([
  "tenantId",
  "batchId",
  "batchNumber",
  "productId",
  "productName",
  "quantity",
  "expenses",
  "totalCostMinor",
  "unitCostMinor",
]);

const ACCEPTED_EXPENSE_KEYS = new Set<string>(["description", "amount"]);

export interface ProductionExpense {
  description: string;
  amountMinor: number;
}

/** One batch, read and bounded. */
export interface ProductionInput {
  tenantId: string;
  batchId: string;
  batchNumber: string;
  productId: string;
  quantity: number;
  expenses: ProductionExpense[];
  totalCostMinor: number;
  unitCostMinor: number;
}

/** The ledger ID one batch's units are written at. */
export function productionAdjustmentId(batchId: string): string {
  return `sa_pb_${immutableLedgerId([batchId])}`;
}

/**
 * What one unit cost to make, in minor units, rounded half up.
 *
 * Whole minor units in, whole minor units out, so the rounding is exact rather
 * than whatever binary floating point makes of a division: `floor((2t + q) /
 * 2q)` is `t / q` rounded half up for positive integers.
 */
export function productionUnitCostMinor(totalCostMinor: number, quantity: number): number {
  return Math.floor((2 * totalCostMinor + quantity) / (2 * quantity));
}

function readExpense(value: unknown, index: number): ProductionExpense {
  const row = requireObject(value, `expenses[${index}]`) as ProductionExpenseRequest &
    Record<string, unknown>;
  for (const key of Object.keys(row)) {
    if (!ACCEPTED_EXPENSE_KEYS.has(key)) {
      throw new HttpsError("invalid-argument", `${key} is not part of a production cost.`);
    }
  }
  if (typeof row.description !== "string") {
    throw new HttpsError("invalid-argument", "Every production cost needs a description.");
  }
  const description = row.description.trim().replace(/\s+/g, " ");
  if (
    description.length === 0 ||
    description.length > MAXIMUM_PRODUCT_NAME_LENGTH ||
    /\p{Cc}/u.test(description)
  ) {
    throw new HttpsError(
      "invalid-argument",
      `A production cost's description must be 1 to ${MAXIMUM_PRODUCT_NAME_LENGTH} ` +
      "ordinary characters."
    );
  }
  const amountMinor = productPriceMinorUnits(row.amount);
  if (amountMinor === undefined || amountMinor <= 0) {
    throw new HttpsError(
      "invalid-argument",
      "Every production cost must be an amount above zero with at most two " +
      "decimal places."
    );
  }
  return {description, amountMinor};
}

/** Reads one batch. Every refusal is something the form could have caught. */
export function readProductionRequest(value: unknown): ProductionInput {
  const data = requireObject(value);
  for (const key of Object.keys(data)) {
    if (!ACCEPTED_REQUEST_KEYS.has(key)) {
      throw new HttpsError("invalid-argument", `${key} is not part of a production batch.`);
    }
  }
  const tenantId = requireDocumentId(data.tenantId, "tenantId");
  const batchId = requireDocumentId(data.batchId, "batchId");
  requireRequestId(batchId);
  if (typeof data.batchNumber !== "string" || !PRODUCTION_BATCH_NUMBER.test(data.batchNumber)) {
    throw new HttpsError("invalid-argument", "batchNumber is not a production batch number.");
  }
  const productId = requireDocumentId(data.productId, "productId");
  const quantity = data.quantity;
  if (
    !Number.isSafeInteger(quantity) ||
    (quantity as number) < 1 ||
    (quantity as number) > MAXIMUM_IMPORT_OPENING_STOCK
  ) {
    throw new HttpsError(
      "invalid-argument",
      `quantity must be a whole number from 1 to ${MAXIMUM_IMPORT_OPENING_STOCK}.`
    );
  }
  if (!Array.isArray(data.expenses) || data.expenses.length === 0) {
    throw new HttpsError(
      "invalid-argument",
      "A production batch needs at least one cost. A batch with no cost cannot be made."
    );
  }
  if (data.expenses.length > MAXIMUM_PRODUCTION_EXPENSES) {
    throw new HttpsError(
      "invalid-argument",
      `A production batch carries at most ${MAXIMUM_PRODUCTION_EXPENSES} costs.`
    );
  }
  const expenses = data.expenses.map((row, index) => readExpense(row, index));
  const totalCostMinor = expenses.reduce((sum, row) => sum + row.amountMinor, 0);
  const unitCostMinor = productionUnitCostMinor(totalCostMinor, quantity as number);
  if (unitCostMinor < 1) {
    throw new HttpsError(
      "invalid-argument",
      "The cost per unit rounds to nothing. Record what the batch really cost, " +
      "or fewer units."
    );
  }
  if (unitCostMinor > MAXIMUM_PRODUCT_PRICE_MINOR_UNITS) {
    throw new HttpsError(
      "invalid-argument",
      "The cost per unit is larger than any figure a sale can record."
    );
  }
  return {
    tenantId,
    batchId,
    batchNumber: data.batchNumber,
    productId,
    quantity: quantity as number,
    expenses,
    totalCostMinor,
    unitCostMinor,
  };
}

/** Every document one batch writes, from what the transaction read. */
export interface ProductionPlan {
  adjustmentId: string;
  batch: Record<string, unknown>;
  productUpdate: Record<string, unknown>;
  ledger: Record<string, unknown>;
  audit: Record<string, unknown>;
}

function storedCostMinor(value: unknown): number | null {
  if (value === undefined || value === null) return null;
  return productPriceMinorUnits(value) ?? null;
}

/** Decides one batch against the product it makes. */
export function planProduction(options: {
  input: ProductionInput;
  product: DocumentData | undefined;
  actorUid: string;
}): ProductionPlan {
  const {input, product, actorUid} = options;
  if (product === undefined) {
    throw new HttpsError(
      "failed-precondition",
      `Product ${input.productId} does not exist in this business.`
    );
  }
  const previousQuantity = requireStoredQuantity(product.quantity);
  const quantityAfter = addStockQuantity(previousQuantity, input.quantity);
  const previousCostMinor = storedCostMinor(product.cost);
  const adjustmentId = productionAdjustmentId(input.batchId);
  const productName = typeof product.name === "string" ? product.name : input.productId;
  const reason = normalizeReason(`Production batch ${input.batchNumber}`);
  return {
    adjustmentId,
    productUpdate: {quantity: quantityAfter, cost: input.unitCostMinor / 100},
    batch: {
      tenantId: input.tenantId,
      batchId: input.batchId,
      batchNumber: input.batchNumber,
      productId: input.productId,
      productName,
      quantity: input.quantity,
      expenses: input.expenses,
      totalCostMinor: input.totalCostMinor,
      unitCostMinor: input.unitCostMinor,
      previousCostMinor,
      previousQuantity,
      quantityAfter,
      adjustmentId,
      actorUid,
    },
    // `adjustStock`'s shape, plus what makes it production: reconciliation
    // reads one ledger, and a unit made is a unit.
    ledger: {
      tenantId: input.tenantId,
      productId: input.productId,
      sourceType: "production",
      adjustmentType: "restock",
      quantityDelta: input.quantity,
      previousQuantity,
      quantityAfter,
      reason,
      actorUid,
      requestId: input.batchId,
      batchId: input.batchId,
      batchNumber: input.batchNumber,
      unitCostMinor: input.unitCostMinor,
      previousCostMinor,
    },
    audit: {
      eventType: "production_completed",
      tenantId: input.tenantId,
      productId: input.productId,
      batchId: input.batchId,
      batchNumber: input.batchNumber,
      quantity: input.quantity,
      totalCostMinor: input.totalCostMinor,
      // The cost that moved, before and after, so the trail states money.
      previousCostMinor,
      unitCostMinor: input.unitCostMinor,
      mutatesQuantity: true,
      actorUid,
      requestId: input.batchId,
    },
  };
}

/** What `completeProduction` answers. */
export interface CompleteProductionResponse {
  batchId: string;
  batchNumber: string;
  productId: string;
  previousQuantity: number;
  quantity: number;
  previousCostMinor: number | null;
  unitCostMinor: number;
  totalCostMinor: number;
}

/** Reads, decides and writes one batch inside [transaction]. */
export async function applyProduction(
  db: Firestore,
  transaction: Transaction,
  options: {input: ProductionInput; actorUid: string}
): Promise<CompleteProductionResponse> {
  const {input, actorUid} = options;
  const tenantRef = db.collection("tenants").doc(input.tenantId);
  const productRef = tenantRef.collection("products").doc(input.productId);
  const batchRef = tenantRef.collection("production_batches").doc(input.batchId);
  const [productSnapshot, batchSnapshot] =
    (await transaction.getAll(productRef, batchRef)) as DocumentSnapshot[];
  if (batchSnapshot.exists) {
    throw new HttpsError("already-exists", "This production batch is already recorded.");
  }
  const plan = planProduction({
    input,
    product: productSnapshot.exists ? productSnapshot.data() : undefined,
    actorUid,
  });

  transaction.update(productRef, {
    ...plan.productUpdate,
    // The nightly stock verification defers a product written in the last few
    // minutes by reading this.
    updatedAt: FieldValue.serverTimestamp(),
  });
  transaction.create(batchRef, {...plan.batch, createdAt: FieldValue.serverTimestamp()});
  const record = {...plan.ledger, createdAt: FieldValue.serverTimestamp()};
  transaction.create(tenantRef.collection("stock_adjustments").doc(plan.adjustmentId), record);
  transaction.create(productRef.collection("stock_movements").doc(plan.adjustmentId), {
    ...record,
    movementId: plan.adjustmentId,
    occurredAt: FieldValue.serverTimestamp(),
    recordedAt: FieldValue.serverTimestamp(),
  });
  transaction.create(tenantRef.collection("audit_logs").doc(input.batchId), {
    ...plan.audit,
    createdAt: FieldValue.serverTimestamp(),
  });

  return {
    batchId: input.batchId,
    batchNumber: input.batchNumber,
    productId: input.productId,
    previousQuantity: plan.batch.previousQuantity as number,
    quantity: plan.batch.quantityAfter as number,
    previousCostMinor: plan.batch.previousCostMinor as number | null,
    unitCostMinor: input.unitCostMinor,
    totalCostMinor: input.totalCostMinor,
  };
}

/** Completes one production batch. See the module note. */
export const completeProduction = onCall<
  CompleteProductionRequest,
  Promise<CompleteProductionResponse>
>(async (
  request: CallableRequest<CompleteProductionRequest>
): Promise<CompleteProductionResponse> => {
  const input = readProductionRequest(request.data);
  const db = getFirestore();
  const actor = await requireTenantMember(db, request, input.tenantId, PRODUCTION_ROLES);

  // **The batch ID is the idempotency key**, as a category's or a product's
  // is: it is a digest of the request that minted it, so a replay answers off
  // the stored record rather than stocking the shelf twice.
  return runIdempotentFirestoreTransaction(db, {
    actorUid: actor.uid,
    operation: "completeProduction",
    tenantId: input.tenantId,
    requestId: input.batchId,
    input: {
      batchId: input.batchId,
      batchNumber: input.batchNumber,
      productId: input.productId,
      quantity: input.quantity,
      expenses: input.expenses,
    },
  }, async (transaction) => {
    const currentActor = await requireTenantMember(
      db,
      request,
      input.tenantId,
      PRODUCTION_ROLES,
      transaction
    );
    return applyProduction(db, transaction, {input, actorUid: currentActor.uid});
  });
});
