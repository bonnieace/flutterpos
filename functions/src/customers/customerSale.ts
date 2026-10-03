import {createHash} from "node:crypto";
import {
  FieldValue,
  getFirestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";
import type {DocumentReference, Firestore} from "firebase-admin/firestore";
import {getFunctions} from "firebase-admin/functions";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onTaskDispatched} from "firebase-functions/v2/tasks";
import {queueAutomaticEmailReceipt} from "../emailReceipts/deliveries";
import {queueAutomaticReceipt} from "../whatsapp/deliveries";
import {CUSTOMER_ID_SHAPE} from "./customerId";
import {
  balanceFields,
  readSaleCredit,
  storedBalance,
  storedCreditLimit,
} from "./credit";

/**
 * What a sale to a named customer does to that customer, once it arrives.
 *
 * **Counted here and nowhere else.** A sale reaches the server through the
 * checkout outbox, written by a till that may have been offline for hours, so
 * the till cannot be trusted to say how many points it earned or when the
 * customer last bought. This task reads the sale, awards its points at the
 * rate `configuration/loyalty` holds now, and moves the customer's sale count
 * and last purchase - in one transaction, once.
 *
 * **Once, whatever retries.** The sale's own entry in the customer's points
 * ledger (`customers/{id}/activity/{saleId}`) is created in the same
 * transaction that counts it, and a sale whose entry exists is already
 * counted. A task that runs twice, or a trigger that fires twice, counts
 * nothing the second time.
 *
 * **It waits for the customer.** A cashier can add a customer with no signal
 * and sell to them in the same breath; the customer travels the callable queue
 * and the sale the outbox, in whichever order the network allows. A sale whose
 * customer is not there yet throws, and Cloud Tasks retries it with backoff for
 * about a day - long enough for any till that comes back online at all.
 */

export const CUSTOMER_SALE_TASK_FUNCTION = "processCustomerSale";

export {CUSTOMER_ID_SHAPE};

export interface CustomerSaleTask {
  tenantId: string;
  saleId: string;
}

export interface LoyaltyPolicy {
  enabled: boolean;
  minorUnitsPerPoint: number;
}

export const LOYALTY_OFF: LoyaltyPolicy = {enabled: false, minorUnitsPerPoint: 10000};

/** The largest spend one point may be set to: a million of the major unit. */
const MAXIMUM_MINOR_UNITS_PER_POINT = 100_000_000;

/**
 * Reads `configuration/loyalty`, or no points where it is absent or cannot be
 * read - which is what the device's own read model answers too.
 */
export function readLoyaltyPolicy(data: unknown): LoyaltyPolicy {
  if (!data || typeof data !== "object") return LOYALTY_OFF;
  const record = data as Record<string, unknown>;
  const rate = record.minorUnitsPerPoint;
  if (
    typeof record.enabled !== "boolean" ||
    !Number.isSafeInteger(rate) ||
    (rate as number) < 1 ||
    (rate as number) > MAXIMUM_MINOR_UNITS_PER_POINT
  ) {
    return LOYALTY_OFF;
  }
  return {enabled: record.enabled, minorUnitsPerPoint: rate as number};
}

/** Whole points only, rounded down: a customer is never told of a fraction. */
export function pointsFor(policy: LoyaltyPolicy, totalMinor: number): number {
  if (!policy.enabled || !Number.isSafeInteger(totalMinor) || totalMinor <= 0) {
    return 0;
  }
  return Math.floor(totalMinor / policy.minorUnitsPerPoint);
}

/** The customer a stored sale names, or null for a walk-in or anything else. */
export function saleCustomerId(data: Record<string, unknown> | undefined): string | null {
  const id = data?.customerId;
  return typeof id === "string" && CUSTOMER_ID_SHAPE.test(id) ? id : null;
}

/** Thrown when a sale names a customer the server does not hold yet. */
export class CustomerNotYetArrived extends Error {
  constructor(readonly customerId: string) {
    super(`Customer ${customerId} has not reached the server yet.`);
  }
}

export type CustomerSaleOutcome =
  | {outcome: "no_sale"}
  | {outcome: "walk_in"}
  | {outcome: "already_counted"; customerId: string}
  | {outcome: "counted"; customerId: string; points: number; owedMinor: number};

function wholeMinor(value: unknown): number {
  return Number.isSafeInteger(value) && (value as number) > 0 ? value as number : 0;
}

/**
 * Counts one sale against the customer it names, once.
 *
 * **Never throws for a sale that cannot be counted**, only for one that cannot
 * be counted *yet*: a sale that is missing, or that names nobody, answers so
 * and the task ends. A customer who has not arrived throws
 * [CustomerNotYetArrived], which is the retry.
 */
export async function applyCustomerSale(
  db: Firestore,
  task: CustomerSaleTask
): Promise<CustomerSaleOutcome> {
  const tenantRef = db.collection("tenants").doc(task.tenantId);
  const saleRef = tenantRef.collection("sales").doc(task.saleId);
  return db.runTransaction(async (transaction): Promise<CustomerSaleOutcome> => {
    const saleSnapshot = await transaction.get(saleRef);
    if (!saleSnapshot.exists) return {outcome: "no_sale"};
    const sale = saleSnapshot.data() ?? {};
    const customerId = saleCustomerId(sale);
    if (customerId === null) return {outcome: "walk_in"};
    const customerRef = tenantRef.collection("customers").doc(customerId);
    const activityRef = customerRef.collection("activity").doc(task.saleId);
    const loyaltyRef = tenantRef.collection("configuration").doc("loyalty");
    const [customer, activity, loyalty] = await transaction.getAll(
      customerRef,
      activityRef,
      loyaltyRef
    );
    if (activity.exists) return {outcome: "already_counted", customerId};
    if (!customer.exists) throw new CustomerNotYetArrived(customerId);

    const totalMinor = wholeMinor(sale.totalMinor);
    const policy = readLoyaltyPolicy(loyalty.data());
    const points = pointsFor(policy, totalMinor);
    const soldAt = sale.createdAt instanceof Timestamp ? sale.createdAt : null;
    const lastSaleAt = customer.get("lastSaleAt");
    const isLatest = soldAt !== null && (
      !(lastSaleAt instanceof Timestamp) || soldAt.toMillis() > lastSaleAt.toMillis()
    );
    // **On the same ledger entry, so it is counted exactly as often as the
    // points are**: once. A credit sale adds what it left owing to the
    // balance; see `credit.ts` for why over the limit is recorded, not refused.
    const credit = readSaleCredit(sale);
    const before = storedBalance(customer);
    const limit = storedCreditLimit(customer);
    const after = before + (credit?.owedMinor ?? 0);

    transaction.create(activityRef, {
      kind: "sale",
      tenantId: task.tenantId,
      customerId,
      saleId: task.saleId,
      receiptNumber: typeof sale.receiptNumber === "string" ? sale.receiptNumber : null,
      totalMinor,
      points,
      pointsReturned: 0,
      minorUnitsPerPoint: policy.enabled ? policy.minorUnitsPerPoint : null,
      saleCreatedAt: soldAt,
      ...(credit === null ? {} : {
        credit: true,
        creditOwedMinor: credit.owedMinor,
        creditPaidMinor: credit.paidMinor,
        creditPaidTender: credit.paidTender,
        creditReturnedMinor: 0,
        balanceChangeMinor: credit.owedMinor,
        balanceAfterMinor: after,
        creditLimitMinor: limit,
        overLimit: limit !== null && after > limit,
        whileBlocked: customer.get("creditBlocked") === true,
      }),
      createdAt: FieldValue.serverTimestamp(),
    });
    transaction.update(customerRef, {
      saleCount: FieldValue.increment(1),
      ...(points > 0 ? {points: FieldValue.increment(points)} : {}),
      ...(isLatest ? {lastSaleAt: soldAt} : {}),
      ...(credit === null ? {} : balanceFields(
        before,
        credit.owedMinor,
        soldAt ?? FieldValue.serverTimestamp()
      )),
    });
    return {outcome: "counted", customerId, points, owedMinor: credit?.owedMinor ?? 0};
  });
}

/** One returned line: what came back and how many. */
export interface ReturnedLine {
  productId: string;
  quantity: number;
}

/**
 * Plans what a return takes back from the customer the sale was for, inside
 * the transaction that verifies the return: the points the sale earned, and,
 * for a credit sale, what is still owed on it.
 *
 * **Reads only; the caller applies the answer after its own reads are done**,
 * because a Firestore transaction may not read after its first write and the
 * return's verification writes several documents of its own.
 *
 * **Points in proportion to the listed value returned, never more than the
 * sale earned and has not already given back.** A customer who returns half of
 * what they bought gives back half the points it earned; two partial returns
 * can between them give back the whole and no more. A sale counted before
 * loyalty was on earned nothing, so there is nothing to take.
 *
 * **A credit sale's return cancels debt first.** Goods that come back on a
 * sale the customer has not paid for are paid for by coming back: the value
 * returned, at the price actually charged, comes off what that sale still owes
 * and never more. Anything left over is money the shop hands back, which no
 * return records today and this does not either.
 *
 * Null where there is nothing to do: a walk-in, a sale not counted yet, a sale
 * that earned no points and owes nothing.
 */
export async function planReturnedPoints(
  transaction: Transaction,
  tenantRef: DocumentReference,
  options: {
    saleId: string;
    sale: Record<string, unknown>;
    returnId: string;
    lines: readonly ReturnedLine[];
  }
): Promise<((transaction: Transaction) => void) | null> {
  const customerId = saleCustomerId(options.sale);
  if (customerId === null) return null;
  const customerRef = tenantRef.collection("customers").doc(customerId);
  const saleActivityRef = customerRef.collection("activity").doc(options.saleId);
  const [customer, saleActivity] = await transaction.getAll(customerRef, saleActivityRef);
  if (!customer.exists || !saleActivity.exists) return null;

  const subtotal = wholeMinor(options.sale.subtotalMinor);
  if (subtotal === 0) return null;
  const priceOf = new Map<string, number>();
  const items = Array.isArray(options.sale.items) ? options.sale.items : [];
  for (const item of items) {
    if (!item || typeof item !== "object") continue;
    const record = item as Record<string, unknown>;
    if (typeof record.productId === "string") {
      priceOf.set(record.productId, wholeMinor(record.unitPriceMinor));
    }
  }
  const returnedListed = Math.min(
    subtotal,
    options.lines.reduce(
      (sum, line) => sum + line.quantity * (priceOf.get(line.productId) ?? 0),
      0
    )
  );

  const earned = wholeMinor(saleActivity.get("points"));
  const outstandingPoints = earned - wholeMinor(saleActivity.get("pointsReturned"));
  const take = outstandingPoints <= 0 ? 0 : Math.min(
    outstandingPoints,
    Math.floor(earned * returnedListed / subtotal)
  );

  const owed = wholeMinor(saleActivity.get("creditOwedMinor"));
  const outstandingOwed = saleActivity.get("credit") === true ?
    owed - wholeMinor(saleActivity.get("creditReturnedMinor")) : 0;
  const returnedCharged = Math.floor(
    wholeMinor(options.sale.totalMinor) * returnedListed / subtotal
  );
  const cancel = outstandingOwed <= 0 ? 0 : Math.min(outstandingOwed, returnedCharged);
  if (take <= 0 && cancel <= 0) return null;

  const before = storedBalance(customer);
  return (write: Transaction) => {
    write.update(saleActivityRef, {
      ...(take > 0 ? {pointsReturned: FieldValue.increment(take)} : {}),
      ...(cancel > 0 ? {creditReturnedMinor: FieldValue.increment(cancel)} : {}),
    });
    write.create(customerRef.collection("activity").doc(`return-${options.returnId}`), {
      kind: "return",
      tenantId: tenantRef.id,
      customerId,
      saleId: options.saleId,
      returnId: options.returnId,
      points: -take,
      ...(cancel > 0 ? {
        credit: true,
        balanceChangeMinor: -cancel,
        balanceAfterMinor: before - cancel,
        receiptNumber: typeof options.sale.receiptNumber === "string" ?
          options.sale.receiptNumber : null,
      } : {}),
      createdAt: FieldValue.serverTimestamp(),
    });
    write.update(customerRef, {
      ...(take > 0 ? {points: FieldValue.increment(-take)} : {}),
      ...(cancel > 0 ? balanceFields(before, -cancel, FieldValue.serverTimestamp()) : {}),
    });
  };
}

function taskAlreadyExists(error: unknown): boolean {
  const code = error && typeof error === "object" && "code" in error ?
    String((error as {code?: unknown}).code) : undefined;
  return code === "functions/task-already-exists" ||
    code === "already-exists" || code === "6";
}

/** A task ID Cloud Tasks accepts, the same for the same sale every time. */
export function customerSaleTaskId(task: CustomerSaleTask): string {
  const digest = createHash("sha256")
    .update(`customer-sale ${task.tenantId} ${task.saleId}`)
    .digest("hex");
  return `customer-sale-${digest.slice(0, 48)}`;
}

/** Queues the count for one sale; a second queue for the same sale is a no-op. */
export async function enqueueCustomerSale(task: CustomerSaleTask): Promise<void> {
  try {
    await getFunctions().taskQueue<CustomerSaleTask>(
      CUSTOMER_SALE_TASK_FUNCTION
    ).enqueue(task, {id: customerSaleTaskId(task), dispatchDeadlineSeconds: 120});
  } catch (error) {
    if (!taskAlreadyExists(error)) throw error;
  }
}

/**
 * A sale arrived. If it names a customer, queue its count.
 *
 * **Separate from `mergeSaleReconciliationJob`**, which also fires on every
 * sale: reconciliation is the money's ledger and must not wait on, or fail
 * for, a customer's points.
 */
export const onCustomerSale = onDocumentCreated(
  {document: "tenants/{tenantId}/sales/{saleId}", retry: true},
  async (event) => {
    const data = event.data?.data();
    if (saleCustomerId(data) === null) return;
    await enqueueCustomerSale({
      tenantId: event.params.tenantId,
      saleId: event.params.saleId,
    });
  }
);

export const processCustomerSale = onTaskDispatched<CustomerSaleTask>(
  {
    invoker: "private",
    retryConfig: {
      // About a day of backoff, for a customer still on an offline till.
      maxAttempts: 30,
      minBackoffSeconds: 60,
      maxBackoffSeconds: 3600,
      maxDoublings: 6,
    },
    rateLimits: {maxConcurrentDispatches: 10, maxDispatchesPerSecond: 20},
    timeoutSeconds: 120,
  },
  async (request) => {
    const data = request.data;
    if (
      !data ||
      typeof data.tenantId !== "string" ||
      typeof data.saleId !== "string"
    ) {
      return;
    }
    const db = getFirestore();
    const outcome = await applyCustomerSale(db, data);
    // **After the count, and on a recount too.** A task that counted the sale
    // and then failed before queueing the receipt is retried, finds the sale
    // already counted, and must still queue it - the delivery's ID is the sale
    // and the number, so queueing it twice sends it once.
    if (outcome.outcome === "counted" || outcome.outcome === "already_counted") {
      await queueAutomaticReceipt(db, data);
      await queueAutomaticEmailReceipt(db, data);
    }
  }
);
