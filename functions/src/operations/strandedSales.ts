import {CREDIT_TENDER, readSaleCredit} from "../customers/credit";
import {FieldValue, getFirestore, Timestamp} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {requireAuthenticatedUser} from "../core/authorization";
import {
  requireDocumentId,
  requireObject,
  requireRequestId,
} from "../core/validation";
import {SALE_TENDERS} from "./domain";

/**
 * Hands over sales a cashier rang up before their access ended.
 *
 * **The case this exists for.** A sale becomes durable in the device's own
 * encrypted outbox before it reaches the server, which is what lets the till
 * trade with no connection. If the cashier's membership is deactivated while
 * sales are still sitting there, both the submission worker and the recovery
 * worker stop - they require a session that can access the business - and
 * `allow create` on `sales` requires `activeStaff` in any case, so the writes
 * would be refused even if they were attempted. The money was taken, a receipt
 * may have printed, and the only record is on a phone nobody can act through.
 *
 * **Why a callable and not a grace period in Rules.** A time-boxed
 * `activeStaff` would widen what a deactivation means for every collection at
 * once, to buy one narrow path. This grants exactly one: a sale, attributed to
 * the caller, dated before the caller's own deactivation. Everything else about
 * that account stays shut.
 *
 * **What it does not do.** It cannot prove the sale happened - nothing here
 * ever could, since the till records what the cashier rang up and no provider
 * confirms it. What it proves is that the sale is attributed to this caller and
 * predates the moment their access ended, which is the same standing the sale
 * would have had if the device had been online that day. A drained sale is
 * marked so an owner reading the books can tell it arrived this way.
 *
 * Authentication still applies: a deactivated membership is a tenant fact, not
 * an Auth one, so the account can still sign in. That is what makes this
 * reachable at all.
 */
interface DrainStrandedSalesRequest {
  tenantId?: unknown;
  requestId?: unknown;
  sales?: unknown;
}

export interface DrainStrandedSalesResponse {
  /** Sales written by this call. */
  drained: string[];

  /** Sales already on the server, which this call left alone. */
  alreadyPresent: string[];
}

/** How long after a deactivation a stranded sale may still be handed over. */
export const STRANDED_SALE_WINDOW_MS = 30 * 24 * 60 * 60 * 1000;

/** The most sales one call may carry, matching the checkout line bound. */
export const MAXIMUM_STRANDED_SALES = 50;

/** The `audit_logs` ID one drain writes at. */
export function strandedDrainAuditId(requestId: string): string {
  return `sd_${requestId}`;
}

function integerField(value: unknown, field: string): number {
  if (!Number.isSafeInteger(value)) {
    throw new HttpsError("invalid-argument", `${field} must be a whole number.`);
  }
  return value as number;
}

function stringField(value: unknown, field: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new HttpsError("invalid-argument", `${field} must be a non-empty string.`);
  }
  return value;
}

/** One sale line, reduced to what a stock decrement needs. */
export interface StrandedSaleLine {
  productId: string;
  quantity: number;
}

/**
 * Proves one handed-over sale describes this caller and predates their exit.
 *
 * Pure, for the reason `planSaleTenderRecord` is: the callable is the
 * authorization and the transaction around it, and every decision it makes is
 * testable without one.
 */
export function validateStrandedSale(options: {
  sale: Record<string, unknown>;
  tenantId: string;
  actorUid: string;
  deactivatedAtMs: number;
  nowMs: number;
}): {checkoutId: string; lines: StrandedSaleLine[]} {
  const {sale, tenantId, actorUid, deactivatedAtMs, nowMs} = options;
  const checkoutId = requireDocumentId(sale.checkoutId, "checkoutId");
  if (sale.tenantId !== tenantId) {
    throw new HttpsError(
      "permission-denied",
      "That sale does not belong to this business."
    );
  }
  // **Own sales only.** A deactivated member can hand over what they rang up
  // and nothing else; this is the whole of what the grant widens.
  if (sale.soldById !== actorUid) {
    throw new HttpsError(
      "permission-denied",
      "Only the cashier who recorded a sale can hand it over."
    );
  }
  stringField(sale.payloadHash, "payloadHash");
  const schemaVersion = integerField(sale.payloadSchemaVersion, "payloadSchemaVersion");
  if (schemaVersion !== 1 && schemaVersion !== 2) {
    throw new HttpsError("invalid-argument", "payloadSchemaVersion must be 1 or 2.");
  }
  // The same tender contract Rules apply on an ordinary create: absent is an
  // answer at v2, a present value must name a modelled method, and v1 carries
  // none at all.
  const hasTender = sale.tender !== undefined && sale.tender !== null;
  if (schemaVersion === 1 && hasTender) {
    throw new HttpsError(
      "invalid-argument",
      "A schema v1 sale cannot record a payment method."
    );
  }
  if (
    hasTender &&
    !(SALE_TENDERS as readonly unknown[]).includes(sale.tender) &&
    // A credit sale is the one tender outside the money methods, and only
    // with a customer and an owed part that adds up - as Rules require.
    !(sale.tender === CREDIT_TENDER && readSaleCredit(sale) !== null &&
      typeof sale.customerId === "string")
  ) {
    throw new HttpsError(
      "invalid-argument",
      "tender must name one of the recorded payment methods."
    );
  }
  stringField(sale.currency, "currency");
  stringField(sale.businessDate, "businessDate");
  stringField(sale.receiptNumber, "receiptNumber");
  integerField(sale.receiptSequence, "receiptSequence");
  stringField(sale.deviceId, "deviceId");
  requireDocumentId(sale.shiftId, "shiftId");
  integerField(sale.subtotalMinor, "subtotalMinor");
  integerField(sale.discountMinor, "discountMinor");
  integerField(sale.totalMinor, "totalMinor");

  // **Dated before the door closed.** This is the bound that makes the grant
  // narrow: a sale rung up after the deactivation was never this cashier's to
  // record, and the device's own clock is the only thing that could claim
  // otherwise - so it is checked rather than trusted.
  const clientCreatedAtMs = integerField(sale.clientCreatedAtMs, "clientCreatedAtMs");
  if (clientCreatedAtMs >= deactivatedAtMs) {
    throw new HttpsError(
      "failed-precondition",
      "That sale is dated after this membership ended, so it cannot be handed " +
      "over."
    );
  }
  if (nowMs > deactivatedAtMs + STRANDED_SALE_WINDOW_MS) {
    throw new HttpsError(
      "failed-precondition",
      "This membership ended too long ago for its sales to be handed over. " +
      "Ask the business owner to restore access instead."
    );
  }

  const items = sale.items;
  if (!Array.isArray(items) || items.length === 0 || items.length > 16) {
    throw new HttpsError("invalid-argument", "items must hold 1 to 16 lines.");
  }
  const lines: StrandedSaleLine[] = [];
  for (const line of items) {
    if (typeof line !== "object" || line === null) {
      throw new HttpsError("invalid-argument", "Every sale line must be a map.");
    }
    const record = line as Record<string, unknown>;
    const productId = requireDocumentId(record.productId, "productId");
    const quantity = integerField(record.quantity, "quantity");
    if (quantity <= 0) {
      throw new HttpsError("invalid-argument", "quantity must be above zero.");
    }
    lines.push({productId, quantity});
  }
  return {checkoutId, lines};
}

export const drainStrandedSales = onCall<
  DrainStrandedSalesRequest,
  Promise<DrainStrandedSalesResponse>
>(async (
  request: CallableRequest<DrainStrandedSalesRequest>
): Promise<DrainStrandedSalesResponse> => {
  const auth = requireAuthenticatedUser(request, {allowUnverified: true});
  const data = requireObject(request.data);
  const tenantId = requireDocumentId(data.tenantId, "tenantId");
  const requestId = requireRequestId(data.requestId);
  const sales = data.sales;
  if (!Array.isArray(sales) || sales.length === 0) {
    throw new HttpsError("invalid-argument", "sales must hold at least one sale.");
  }
  if (sales.length > MAXIMUM_STRANDED_SALES) {
    throw new HttpsError(
      "invalid-argument",
      `At most ${MAXIMUM_STRANDED_SALES} sales can be handed over at once.`
    );
  }
  const db = getFirestore();
  const tenantRef = db.collection("tenants").doc(tenantId);
  const staffSnapshot = await tenantRef.collection("staff").doc(auth.uid).get();
  if (!staffSnapshot.exists) {
    throw new HttpsError(
      "permission-denied",
      "You have no membership of this business."
    );
  }
  // **Deliberately the deactivated path and only that.** A member who can still
  // reach the business has the ordinary submission path, which writes under
  // Rules with every check they carry. Sending them here instead would be a
  // way around those checks.
  if (staffSnapshot.get("status") !== "inactive") {
    throw new HttpsError(
      "failed-precondition",
      "This membership is not deactivated, so its sales send the ordinary way."
    );
  }
  const deactivatedAt = staffSnapshot.get("deactivatedAt");
  if (!(deactivatedAt instanceof Timestamp)) {
    throw new HttpsError(
      "failed-precondition",
      "This membership does not record when it ended, so a sale cannot be " +
      "measured against it."
    );
  }
  const deactivatedAtMs = deactivatedAt.toMillis();
  const nowMs = Date.now();

  const drained: string[] = [];
  const alreadyPresent: string[] = [];
  for (const entry of sales) {
    const sale = requireObject(entry) as Record<string, unknown>;
    const {checkoutId, lines} = validateStrandedSale({
      sale,
      tenantId,
      actorUid: auth.uid,
      deactivatedAtMs,
      nowMs,
    });
    const saleRef = tenantRef.collection("sales").doc(checkoutId);
    // **One transaction per sale, not one for all of them.** A sale and the
    // stock it moves have to land together or not at all, and that is the whole
    // of the atomicity this needs: two stranded sales are two separate facts,
    // and failing the second is no reason to withhold the first.
    const written = await db.runTransaction(async (transaction) => {
      const existing = await transaction.get(saleRef);
      if (existing.exists) return false;
      transaction.create(saleRef, {
        ...sale,
        // **Marked, so the books can tell.** A sale that arrived this way was
        // written after its seller's access ended, and an owner reading a day
        // that does not look right is entitled to see which records came in
        // through this door rather than through a till.
        drainedAt: FieldValue.serverTimestamp(),
        drainedAfterDeactivation: true,
        createdAt: FieldValue.serverTimestamp(),
      });
      for (const line of lines) {
        transaction.update(tenantRef.collection("products").doc(line.productId), {
          quantity: FieldValue.increment(-line.quantity),
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
      return true;
    });
    if (written) {
      drained.push(checkoutId);
    } else {
      alreadyPresent.push(checkoutId);
    }
  }

  await tenantRef.collection("audit_logs").doc(strandedDrainAuditId(requestId)).create({
    eventType: "stranded_sales_drained",
    tenantId,
    actorUid: auth.uid,
    requestId,
    drained,
    alreadyPresent,
    createdAt: FieldValue.serverTimestamp(),
  });

  return {drained, alreadyPresent};
});
