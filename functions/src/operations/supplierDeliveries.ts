import {FieldValue, getFirestore} from "firebase-admin/firestore";
import type {
  DocumentData,
  DocumentSnapshot,
  Firestore,
  Transaction,
} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {requireTenantMember} from "../core/authorization";
import {runIdempotentFirestoreTransaction} from "../core/idempotency";
import {requireDocumentId, requireObject, requireRequestId} from "../core/validation";
import {
  addStockQuantity,
  immutableLedgerId,
  normalizeReason,
  requireStoredQuantity,
} from "./domain";
import {MAXIMUM_IMPORT_OPENING_STOCK} from "./productImport";
import {productPriceMinorUnits} from "./productUpdate";
import {SUPPLIER_WRITE_ROLES} from "./suppliers";

/**
 * Receiving one supplier delivery: one supplier, one reference, many products.
 *
 * **One record per delivery, sent in pages.** A delivery is written as one
 * `supplier_deliveries` document whose lines are merged in page by page, because
 * a transaction here is kept to about fifty document writes - the bound every
 * other bulk operation in this codebase keeps - and each line writes three: the
 * product, its `stock_adjustments` record and its `stock_movements` entry. So a
 * page carries at most [MAXIMUM_DELIVERY_PAGE_LINES] lines, the figure
 * `applyStockTake` pages at for the same arithmetic. Each page is all or none;
 * the header says which pages have landed and whether the delivery is whole.
 *
 * **A unit cost, when a line names one, becomes the product's cost.** That is the
 * rule a production batch follows too: the latest event that states a cost sets
 * it, and a manager may state one this way because the delivery is a permanent
 * record of where the figure came from. A line that names no cost leaves the
 * product's cost exactly as it was.
 *
 * **The server refuses only what a form could have caught.** Anything that can
 * change while a page waits on a device with no connection - a product retired,
 * a supplier marked inactive - is checked on the form and never here, because a
 * refused page strands every later page of the same delivery on that device.
 */

interface DeliveryLineRequest {
  productId?: unknown;
  quantity?: unknown;
  unitCost?: unknown;
  productName?: unknown;
}

interface ReceiveSupplierDeliveryRequest {
  tenantId?: unknown;
  deliveryId?: unknown;
  supplierId?: unknown;
  reference?: unknown;
  page?: unknown;
  isFinalPage?: unknown;
  lines?: unknown;
}

/** The most product lines one page restocks: three writes each, fifty in all. */
export const MAXIMUM_DELIVERY_PAGE_LINES = Math.floor(50 / 3);

/** The most pages one delivery may be sent in, and so the most lines it holds. */
export const MAXIMUM_DELIVERY_PAGES = 13;

export const MAXIMUM_DELIVERY_REFERENCE_LENGTH = 64;

const ACCEPTED_REQUEST_KEYS = new Set<string>([
  "tenantId",
  "deliveryId",
  "supplierId",
  "reference",
  "page",
  "isFinalPage",
  "lines",
]);

/**
 * `productName` is accepted and ignored: the device carries it so its own
 * overlay can draw the line, and the server names the product from the product.
 */
const ACCEPTED_LINE_KEYS = new Set<string>([
  "productId",
  "quantity",
  "unitCost",
  "productName",
]);

export interface DeliveryPageLine {
  productId: string;
  quantity: number;

  /** Null when the line names no cost, which leaves the product's cost alone. */
  unitCostMinor: number | null;
}

/** One page of one delivery, read and bounded. */
export interface DeliveryPageInput {
  tenantId: string;
  deliveryId: string;
  supplierId: string;
  reference: string | null;
  page: number;
  isFinalPage: boolean;
  lines: DeliveryPageLine[];
}

/** The line as the delivery record stores it, once the product has been read. */
export interface DeliveryRecordLine {
  productId: string;
  productName: string;
  quantity: number;
  unitCostMinor: number | null;
  previousCostMinor: number | null;
  previousQuantity: number;
  quantityAfter: number;
  adjustmentId: string;
  page: number;
}

/** The idempotency key one page is settled under. */
export function deliveryPageRequestId(deliveryId: string, page: number): string {
  return `${deliveryId}:${page}`;
}

/** The ledger ID one product line of one delivery is written at. */
export function deliveryLineAdjustmentId(deliveryId: string, productId: string): string {
  return `sa_sd_${immutableLedgerId([deliveryId, productId])}`;
}

/** The audit ID one page is recorded at. */
export function deliveryPageAuditId(deliveryId: string, page: number): string {
  return `sd_${immutableLedgerId([deliveryId, String(page)])}`;
}

function readReference(value: unknown): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", "reference must be a string or null.");
  }
  const reference = value.trim().replace(/\s+/g, " ");
  if (reference.length === 0) return null;
  if (reference.length > MAXIMUM_DELIVERY_REFERENCE_LENGTH || /\p{Cc}/u.test(reference)) {
    throw new HttpsError(
      "invalid-argument",
      `reference must be at most ${MAXIMUM_DELIVERY_REFERENCE_LENGTH} ordinary characters.`
    );
  }
  return reference;
}

function readLine(value: unknown, index: number): DeliveryPageLine {
  const line = requireObject(value, `lines[${index}]`) as DeliveryLineRequest &
    Record<string, unknown>;
  for (const key of Object.keys(line)) {
    if (!ACCEPTED_LINE_KEYS.has(key)) {
      throw new HttpsError("invalid-argument", `${key} is not part of a delivery line.`);
    }
  }
  const productId = requireDocumentId(line.productId, `lines[${index}].productId`);
  const quantity = line.quantity;
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
  let unitCostMinor: number | null = null;
  if (line.unitCost !== undefined && line.unitCost !== null) {
    const minor = productPriceMinorUnits(line.unitCost);
    // **Zero is refused rather than recorded.** It would set the product's cost
    // to nothing and report its whole price as profit on every sale after it;
    // a line whose cost is not known leaves the cost field blank instead.
    if (minor === undefined || minor <= 0) {
      throw new HttpsError(
        "invalid-argument",
        "unitCost must be an amount above zero with at most two decimal places, " +
        "or left out."
      );
    }
    unitCostMinor = minor;
  }
  return {productId, quantity: quantity as number, unitCostMinor};
}

/** Reads one page of one delivery. Every refusal is a caller defect. */
export function readDeliveryPageRequest(value: unknown): DeliveryPageInput {
  const data = requireObject(value);
  for (const key of Object.keys(data)) {
    if (!ACCEPTED_REQUEST_KEYS.has(key)) {
      throw new HttpsError("invalid-argument", `${key} is not part of a delivery.`);
    }
  }
  const tenantId = requireDocumentId(data.tenantId, "tenantId");
  const deliveryId = requireDocumentId(data.deliveryId, "deliveryId");
  const supplierId = requireDocumentId(data.supplierId, "supplierId");
  const page = data.page;
  if (
    !Number.isSafeInteger(page) ||
    (page as number) < 0 ||
    (page as number) >= MAXIMUM_DELIVERY_PAGES
  ) {
    throw new HttpsError(
      "invalid-argument",
      `page must be a whole number from 0 to ${MAXIMUM_DELIVERY_PAGES - 1}.`
    );
  }
  // Proved usable as an idempotency key before it is used as one.
  requireRequestId(deliveryPageRequestId(deliveryId, page as number));
  if (typeof data.isFinalPage !== "boolean") {
    throw new HttpsError("invalid-argument", "isFinalPage must be true or false.");
  }
  if (!Array.isArray(data.lines) || data.lines.length === 0) {
    throw new HttpsError("invalid-argument", "A delivery page must name at least one product.");
  }
  if (data.lines.length > MAXIMUM_DELIVERY_PAGE_LINES) {
    throw new HttpsError(
      "invalid-argument",
      `A page carries at most ${MAXIMUM_DELIVERY_PAGE_LINES} lines. Send the rest ` +
      "as further pages of the same delivery."
    );
  }
  const lines = data.lines.map((line, index) => readLine(line, index));
  const seen = new Set<string>();
  for (const line of lines) {
    if (seen.has(line.productId)) {
      throw new HttpsError("invalid-argument", "A delivery page names the same product twice.");
    }
    seen.add(line.productId);
  }
  return {
    tenantId,
    deliveryId,
    supplierId,
    reference: readReference(data.reference),
    page: page as number,
    isFinalPage: data.isFinalPage,
    lines,
  };
}

/** What one page decides, before a single document is written. */
export interface DeliveryPagePlan {
  recordLines: DeliveryRecordLine[];
  header: Record<string, unknown>;
  ledger: Array<{adjustmentId: string; productId: string; data: Record<string, unknown>}>;
  productUpdates: Array<{productId: string; data: Record<string, unknown>}>;
  reason: string;
}

function storedLines(header: DocumentData | undefined): DeliveryRecordLine[] {
  const lines = header?.lines;
  if (!Array.isArray(lines)) return [];
  return lines.filter(
    (line): line is DeliveryRecordLine =>
      typeof line === "object" && line !== null && typeof line.productId === "string"
  );
}

function storedCostMinor(value: unknown): number | null {
  if (value === undefined || value === null) return null;
  return productPriceMinorUnits(value) ?? null;
}

/**
 * Decides every document one page writes from what the transaction read.
 *
 * [header] is the delivery as it stands, undefined for a first page. Lines
 * another page already recorded are kept; a product this page names that
 * another page already received is refused, because one product at two unit
 * costs on one delivery leaves no answer to which cost wins.
 */
export function planDeliveryPage(options: {
  input: DeliveryPageInput;
  actorUid: string;
  supplierName: string;
  header: DocumentData | undefined;
  products: Array<DocumentData | undefined>;
}): DeliveryPagePlan {
  const {input, header} = options;
  if (header !== undefined) {
    if (header.supplierId !== input.supplierId) {
      throw new HttpsError(
        "failed-precondition",
        "This delivery was recorded against another supplier."
      );
    }
    if ((header.reference ?? null) !== input.reference) {
      throw new HttpsError(
        "failed-precondition",
        "This delivery was recorded under another reference."
      );
    }
  }
  const earlier = storedLines(header).filter((line) => line.page !== input.page);
  const alreadyReceived = new Set(earlier.map((line) => line.productId));

  const reason = normalizeReason(
    input.reference === null ?
      `Delivery from ${options.supplierName}` :
      `Delivery from ${options.supplierName} · ${input.reference}`
  );
  const requestId = deliveryPageRequestId(input.deliveryId, input.page);
  const recordLines: DeliveryRecordLine[] = [];
  const ledger: DeliveryPagePlan["ledger"] = [];
  const productUpdates: DeliveryPagePlan["productUpdates"] = [];
  input.lines.forEach((line, index) => {
    if (alreadyReceived.has(line.productId)) {
      throw new HttpsError(
        "failed-precondition",
        `Product ${line.productId} was already received on another page of this delivery.`
      );
    }
    const product = options.products[index];
    if (product === undefined) {
      throw new HttpsError(
        "failed-precondition",
        `Product ${line.productId} does not exist in this business.`
      );
    }
    const previousQuantity = requireStoredQuantity(product.quantity);
    const quantityAfter = addStockQuantity(previousQuantity, line.quantity);
    const previousCostMinor = storedCostMinor(product.cost);
    const adjustmentId = deliveryLineAdjustmentId(input.deliveryId, line.productId);
    const productName = typeof product.name === "string" ? product.name : line.productId;
    recordLines.push({
      productId: line.productId,
      productName,
      quantity: line.quantity,
      unitCostMinor: line.unitCostMinor,
      previousCostMinor,
      previousQuantity,
      quantityAfter,
      adjustmentId,
      page: input.page,
    });
    productUpdates.push({
      productId: line.productId,
      data: {
        quantity: quantityAfter,
        ...(line.unitCostMinor === null ? {} : {cost: line.unitCostMinor / 100}),
      },
    });
    ledger.push({
      adjustmentId,
      productId: line.productId,
      // `adjustStock`'s shape, field for field, plus what makes it a delivery:
      // reconciliation reads one ledger, and a unit received is a unit.
      data: {
        tenantId: input.tenantId,
        productId: line.productId,
        sourceType: "supplier_delivery",
        adjustmentType: "restock",
        quantityDelta: line.quantity,
        previousQuantity,
        quantityAfter,
        reason,
        actorUid: options.actorUid,
        requestId,
        deliveryId: input.deliveryId,
        supplierId: input.supplierId,
        reference: input.reference,
        unitCostMinor: line.unitCostMinor,
        previousCostMinor,
      },
    });
  });

  const lines = [...earlier, ...recordLines].sort(
    (left, right) => left.page - right.page
  );
  let unitCount = 0;
  let valueMinor = 0;
  let costlessLineCount = 0;
  for (const line of lines) {
    unitCount += line.quantity;
    if (line.unitCostMinor === null) costlessLineCount += 1;
    else valueMinor += line.quantity * line.unitCostMinor;
  }
  const pagesRecorded = [...new Set<number>([
    ...(Array.isArray(header?.pagesRecorded) ? header.pagesRecorded : []),
    input.page,
  ])].sort((left, right) => left - right);
  const storedPageCount = typeof header?.pageCount === "number" ? header.pageCount : null;
  const pageCount = input.isFinalPage ? input.page + 1 : storedPageCount;

  return {
    recordLines,
    ledger,
    productUpdates,
    reason,
    header: {
      tenantId: input.tenantId,
      deliveryId: input.deliveryId,
      supplierId: input.supplierId,
      // The name as it stood when the stock arrived, so a supplier renamed
      // later still reads as who it was on the day.
      supplierName: header?.supplierName ?? options.supplierName,
      reference: input.reference,
      actorUid: header?.actorUid ?? options.actorUid,
      lines,
      lineCount: lines.length,
      unitCount,
      valueMinor,
      costlessLineCount,
      pagesRecorded,
      pageCount,
      complete: pageCount !== null && pagesRecorded.length === pageCount,
    },
  };
}

/** What `receiveSupplierDelivery` answers, per line of the page it settled. */
export interface ReceiveSupplierDeliveryResponse {
  deliveryId: string;
  page: number;
  complete: boolean;
  lines: Array<{
    productId: string;
    previousQuantity: number;
    quantity: number;
    previousCostMinor: number | null;
    costMinor: number | null;
  }>;
}

/**
 * Reads, decides and writes one page inside [transaction].
 *
 * Split from the callable so it runs against an in-memory Firestore: every read
 * happens before the first write, which Firestore requires and the double
 * enforces.
 */
export async function applyDeliveryPage(
  db: Firestore,
  transaction: Transaction,
  options: {input: DeliveryPageInput; actorUid: string}
): Promise<ReceiveSupplierDeliveryResponse> {
  const {input, actorUid} = options;
  const tenantRef = db.collection("tenants").doc(input.tenantId);
  const headerRef = tenantRef.collection("supplier_deliveries").doc(input.deliveryId);
  const supplierRef = tenantRef.collection("suppliers").doc(input.supplierId);
  const productRefs = input.lines.map((line) =>
    tenantRef.collection("products").doc(line.productId)
  );
  const [headerSnapshot, supplierSnapshot, ...productSnapshots] =
    (await transaction.getAll(headerRef, supplierRef, ...productRefs)) as DocumentSnapshot[];
  if (!supplierSnapshot.exists) {
    throw new HttpsError("not-found", "The supplier does not exist in this business.");
  }
  const supplierName = supplierSnapshot.get("name");
  const plan = planDeliveryPage({
    input,
    actorUid,
    supplierName: typeof supplierName === "string" ? supplierName : input.supplierId,
    header: headerSnapshot.exists ? headerSnapshot.data() : undefined,
    products: productSnapshots.map((snapshot) =>
      snapshot.exists ? snapshot.data() : undefined
    ),
  });

  for (const update of plan.productUpdates) {
    transaction.update(tenantRef.collection("products").doc(update.productId), {
      ...update.data,
      // The nightly stock verification defers a product written in the last
      // few minutes by reading this, so a delivery is never compared against a
      // ledger entry the query cannot see yet.
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  for (const entry of plan.ledger) {
    const record = {...entry.data, createdAt: FieldValue.serverTimestamp()};
    transaction.create(tenantRef.collection("stock_adjustments").doc(entry.adjustmentId), record);
    transaction.create(
      tenantRef
        .collection("products")
        .doc(entry.productId)
        .collection("stock_movements")
        .doc(entry.adjustmentId),
      {
        ...record,
        movementId: entry.adjustmentId,
        occurredAt: FieldValue.serverTimestamp(),
        recordedAt: FieldValue.serverTimestamp(),
      }
    );
  }
  transaction.set(headerRef, {
    ...plan.header,
    createdAt: headerSnapshot.exists ?
      headerSnapshot.get("createdAt") ?? FieldValue.serverTimestamp() :
      FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  transaction.update(supplierRef, {lastDeliveryAt: FieldValue.serverTimestamp()});
  transaction.create(
    tenantRef.collection("audit_logs").doc(deliveryPageAuditId(input.deliveryId, input.page)),
    {
      eventType: "supplier_delivery_received",
      tenantId: input.tenantId,
      deliveryId: input.deliveryId,
      supplierId: input.supplierId,
      reference: input.reference,
      page: input.page,
      lineCount: plan.recordLines.length,
      unitCount: plan.recordLines.reduce((sum, line) => sum + line.quantity, 0),
      // Each cost a line changed, before and after, so the audit trail states
      // money that moved rather than only that it moved.
      costChanges: plan.recordLines
        .filter((line) => line.unitCostMinor !== null)
        .map((line) => ({
          productId: line.productId,
          previousCostMinor: line.previousCostMinor,
          costMinor: line.unitCostMinor,
        })),
      mutatesQuantity: true,
      actorUid,
      requestId: deliveryPageRequestId(input.deliveryId, input.page),
      createdAt: FieldValue.serverTimestamp(),
    }
  );

  return {
    deliveryId: input.deliveryId,
    page: input.page,
    complete: plan.header.complete as boolean,
    lines: plan.recordLines.map((line) => ({
      productId: line.productId,
      previousQuantity: line.previousQuantity,
      quantity: line.quantityAfter,
      previousCostMinor: line.previousCostMinor,
      costMinor: line.unitCostMinor ?? line.previousCostMinor,
    })),
  };
}

/** Receives one page of one supplier delivery. See the module note. */
export const receiveSupplierDelivery = onCall<
  ReceiveSupplierDeliveryRequest,
  Promise<ReceiveSupplierDeliveryResponse>
>(async (
  request: CallableRequest<ReceiveSupplierDeliveryRequest>
): Promise<ReceiveSupplierDeliveryResponse> => {
  const input = readDeliveryPageRequest(request.data);
  const db = getFirestore();
  const actor = await requireTenantMember(db, request, input.tenantId, SUPPLIER_WRITE_ROLES);

  return runIdempotentFirestoreTransaction(db, {
    actorUid: actor.uid,
    operation: "receiveSupplierDelivery",
    tenantId: input.tenantId,
    requestId: deliveryPageRequestId(input.deliveryId, input.page),
    input: {
      deliveryId: input.deliveryId,
      supplierId: input.supplierId,
      reference: input.reference,
      page: input.page,
      isFinalPage: input.isFinalPage,
      lines: input.lines,
    },
  }, async (transaction) => {
    const currentActor = await requireTenantMember(
      db,
      request,
      input.tenantId,
      SUPPLIER_WRITE_ROLES,
      transaction
    );
    return applyDeliveryPage(db, transaction, {input, actorUid: currentActor.uid});
  });
});
