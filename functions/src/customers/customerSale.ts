import {createHash} from "node:crypto";
import {
  FieldValue,
  getFirestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";
import type {
  DocumentReference,
  DocumentSnapshot,
  Firestore,
} from "firebase-admin/firestore";
import {getFunctions} from "firebase-admin/functions";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onTaskDispatched} from "firebase-functions/v2/tasks";
import {queueAutomaticEmailReceipt} from "../emailReceipts/deliveries";
import {
  customerSearchFields,
  readCustomerKraPin,
  readCustomerName,
} from "../operations/customers";
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
 *
 * **A credit sale does not give up on its debt.** Points that never land are
 * points; an owed amount that never lands is money that left the drawer
 * expectation and sits on no balance. On the last attempt a credit sale whose
 * customer still has not arrived - its create was refused, or its till never
 * came back - adds that customer itself, from the name the sale froze, so the
 * debt is on the "who owes" list where someone will see it. A create that
 * arrives later adopts that record rather than failing on it.
 *
 * **A return verified first is not lost either.** A manager can verify a
 * return before the sale is counted; the count then applies what every
 * verified return already took back, so the customer is never charged for
 * goods that came back.
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

/**
 * The customer a sale's [named] customer is counted against.
 *
 * Themselves where they exist; otherwise, where their create was refused for
 * a number another customer holds, that customer - see `recordCustomerAlias`.
 * Otherwise still themselves, not there yet.
 */
async function resolveSaleCustomer(
  transaction: Transaction,
  tenantRef: DocumentReference,
  named: string
): Promise<{customerId: string; customerRef: DocumentReference; customer: DocumentSnapshot}> {
  const customers = tenantRef.collection("customers");
  const namedRef = customers.doc(named);
  const [customer, alias] = await transaction.getAll(
    namedRef,
    tenantRef.collection("customer_aliases").doc(named)
  );
  const holder = alias.get("customerId");
  if (customer.exists || typeof holder !== "string" ||
    !CUSTOMER_ID_SHAPE.test(holder) || holder === named) {
    return {customerId: named, customerRef: namedRef, customer};
  }
  const holderRef = customers.doc(holder);
  return {customerId: holder, customerRef: holderRef, customer: await transaction.get(holderRef)};
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
 * [CustomerNotYetArrived], which is the retry - except on the [lastAttempt]
 * of a credit sale, which adds the customer from the sale instead.
 */
export async function applyCustomerSale(
  db: Firestore,
  task: CustomerSaleTask,
  options: {lastAttempt?: boolean} = {}
): Promise<CustomerSaleOutcome> {
  const tenantRef = db.collection("tenants").doc(task.tenantId);
  const saleRef = tenantRef.collection("sales").doc(task.saleId);
  return db.runTransaction(async (transaction): Promise<CustomerSaleOutcome> => {
    const saleSnapshot = await transaction.get(saleRef);
    if (!saleSnapshot.exists) return {outcome: "no_sale"};
    const sale = saleSnapshot.data() ?? {};
    const named = saleCustomerId(sale);
    if (named === null) return {outcome: "walk_in"};
    const {customerId, customerRef, customer} =
      await resolveSaleCustomer(transaction, tenantRef, named);
    const activityRef = customerRef.collection("activity").doc(task.saleId);
    const loyaltyRef = tenantRef.collection("configuration").doc("loyalty");
    const [activity, loyalty] = await transaction.getAll(activityRef, loyaltyRef);
    if (activity.exists) return {outcome: "already_counted", customerId};
    // See `credit.ts` for why over the limit is recorded, not refused.
    const credit = readSaleCredit(sale);
    if (!customer.exists && !(options.lastAttempt === true && credit !== null)) {
      throw new CustomerNotYetArrived(customerId);
    }
    // Every return verified against this sale before it was counted. They
    // took nothing back then - there was no entry to take it from - so the
    // count applies them, and writes their ledger entries, here.
    const verifications = await transaction.get(
      tenantRef.collection("return_verifications")
        .where("saleId", "==", task.saleId)
        .limit(101)
    );

    const totalMinor = wholeMinor(sale.totalMinor);
    const policy = readLoyaltyPolicy(loyalty.data());
    const points = pointsFor(policy, totalMinor);
    const soldAt = sale.createdAt instanceof Timestamp ? sale.createdAt : null;
    const lastSaleAt = customer.get("lastSaleAt");
    const isLatest = soldAt !== null && (
      !(lastSaleAt instanceof Timestamp) || soldAt.toMillis() > lastSaleAt.toMillis()
    );
    const before = storedBalance(customer);
    const limit = storedCreditLimit(customer);
    const after = before + (credit?.owedMinor ?? 0);

    // Each earlier return in the order it was verified, against what the sale
    // has not given back yet - as each would have applied had the sale been
    // counted first. Which return takes which part of the debt depends on it.
    const verified = [...verifications.docs].sort((a, b) => {
      const at = (snapshot: typeof a) => {
        const value = snapshot.get("createdAt");
        return value instanceof Timestamp ? value.toMillis() : 0;
      };
      return at(a) - at(b) || a.id.localeCompare(b.id);
    });
    const counted: CountedSale = {
      points,
      pointsReturned: 0,
      owedMinor: credit?.owedMinor ?? 0,
      creditReturnedMinor: 0,
    };
    const returns: AppliedReturn[] = [];
    let balance = after;
    for (const verification of verified) {
      const returnId = verification.get("returnId");
      if (typeof returnId !== "string" || returnId.length === 0) continue;
      const share = returnedShare(
        sale,
        counted,
        restoredLines(verification.get("restoredProducts"))
      );
      if (share.take <= 0 && share.cancel <= 0) continue;
      counted.pointsReturned += share.take;
      counted.creditReturnedMinor += share.cancel;
      balance -= share.cancel;
      returns.push({returnId, ...share, balanceAfterMinor: balance});
    }

    // **Stamped in order where returns follow it.** The statement lists by
    // `createdAt`, and entries written in one commit would share its server
    // timestamp and read in any order; the sale first, then each return a
    // millisecond after the last. Alone, the sale keeps the server's time.
    const countedAt = Timestamp.now();
    const stamp = (index: number) => returns.length === 0 ?
      FieldValue.serverTimestamp() :
      Timestamp.fromMillis(countedAt.toMillis() + index);

    // **On the same ledger entry, so it is counted exactly as often as the
    // points are**: once. A credit sale adds what it left owing to the
    // balance.
    transaction.create(activityRef, {
      kind: "sale",
      tenantId: task.tenantId,
      customerId,
      saleId: task.saleId,
      receiptNumber: typeof sale.receiptNumber === "string" ? sale.receiptNumber : null,
      totalMinor,
      points,
      pointsReturned: counted.pointsReturned,
      minorUnitsPerPoint: policy.enabled ? policy.minorUnitsPerPoint : null,
      saleCreatedAt: soldAt,
      ...(credit === null ? {} : {
        credit: true,
        creditOwedMinor: credit.owedMinor,
        creditPaidMinor: credit.paidMinor,
        creditPaidTender: credit.paidTender,
        creditReturnedMinor: counted.creditReturnedMinor,
        balanceChangeMinor: credit.owedMinor,
        balanceAfterMinor: after,
        creditLimitMinor: limit,
        overLimit: limit !== null && after > limit,
        whileBlocked: customer.get("creditBlocked") === true,
      }),
      createdAt: stamp(0),
    });
    for (const [index, returned] of returns.entries()) {
      transaction.create(
        customerRef.collection("activity").doc(`return-${returned.returnId}`),
        returnEntry(tenantRef.id, customerId, task.saleId, sale, returned, stamp(index + 1))
      );
    }
    const pointsChange = points - counted.pointsReturned;
    const tally = {
      saleCount: FieldValue.increment(1),
      ...(pointsChange > 0 ? {points: FieldValue.increment(pointsChange)} : {}),
      ...(isLatest ? {lastSaleAt: soldAt} : {}),
      ...(credit === null ? {} : balanceFields(
        before,
        credit.owedMinor - counted.creditReturnedMinor,
        soldAt ?? FieldValue.serverTimestamp()
      )),
    };
    if (customer.exists) {
      transaction.update(customerRef, tally);
    } else {
      transaction.create(customerRef, {...customerFromSale(sale, task.saleId), ...tally});
    }
    return {outcome: "counted", customerId, points, owedMinor: credit?.owedMinor ?? 0};
  });
}

/**
 * The customer a credit sale names, from what the sale froze onto itself, for
 * a sale whose own customer never reached the server.
 *
 * **Marked `createdFromSaleId`**, so a create that does arrive later adopts it
 * (`applyCustomerCreate`) and anyone reading it can tell it was not entered.
 * No phone: the sale does not carry one, and the commonest reason the real
 * create never landed is a number another customer already holds.
 */
function customerFromSale(
  sale: Record<string, unknown>,
  saleId: string
): Record<string, unknown> {
  let name: string;
  try {
    name = readCustomerName(sale.customerName);
  } catch {
    name = typeof sale.receiptNumber === "string" ?
      `Customer on ${sale.receiptNumber}` :
      "Customer on a credit sale";
  }
  let kraPin: string | null;
  try {
    kraPin = readCustomerKraPin(sale.customerKraPin ?? null);
  } catch {
    kraPin = null;
  }
  const search = customerSearchFields(name, null);
  return {
    name,
    ...(kraPin === null ? {} : {kraPin}),
    searchName: search.searchName,
    searchPrefixes: search.searchPrefixes,
    active: true,
    createdBy: typeof sale.soldById === "string" ? sale.soldById : "system",
    createdFromSaleId: saleId,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
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
 * Null where there is nothing to do: a walk-in, a sale that earned no points
 * and owes nothing - or a sale not counted yet, whose count applies this
 * return itself from the verification the caller writes.
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
  const named = saleCustomerId(options.sale);
  if (named === null) return null;
  const {customerId, customerRef, customer} =
    await resolveSaleCustomer(transaction, tenantRef, named);
  const saleActivityRef = customerRef.collection("activity").doc(options.saleId);
  const saleActivity = await transaction.get(saleActivityRef);
  if (!customer.exists || !saleActivity.exists) return null;

  const {take, cancel} = returnedShare(options.sale, {
    points: wholeMinor(saleActivity.get("points")),
    pointsReturned: wholeMinor(saleActivity.get("pointsReturned")),
    owedMinor: saleActivity.get("credit") === true ?
      wholeMinor(saleActivity.get("creditOwedMinor")) : 0,
    creditReturnedMinor: wholeMinor(saleActivity.get("creditReturnedMinor")),
  }, options.lines);
  if (take <= 0 && cancel <= 0) return null;

  const before = storedBalance(customer);
  return (write: Transaction) => {
    write.update(saleActivityRef, {
      ...(take > 0 ? {pointsReturned: FieldValue.increment(take)} : {}),
      ...(cancel > 0 ? {creditReturnedMinor: FieldValue.increment(cancel)} : {}),
    });
    write.create(
      customerRef.collection("activity").doc(`return-${options.returnId}`),
      returnEntry(tenantRef.id, customerId, options.saleId, options.sale, {
        returnId: options.returnId,
        take,
        cancel,
        balanceAfterMinor: before - cancel,
      })
    );
    write.update(customerRef, {
      ...(take > 0 ? {points: FieldValue.increment(-take)} : {}),
      ...(cancel > 0 ? balanceFields(before, -cancel, FieldValue.serverTimestamp()) : {}),
    });
  };
}

/** What a counted sale earned and owes, and what returns have taken back. */
interface CountedSale {
  points: number;
  pointsReturned: number;
  owedMinor: number;
  creditReturnedMinor: number;
}

/** One return applied to a counted sale, as its ledger entry records it. */
interface AppliedReturn {
  returnId: string;
  take: number;
  cancel: number;
  balanceAfterMinor: number;
}

/**
 * What one return takes back from [counted]: points in proportion to the
 * listed value returned, debt first up to the value returned at the price
 * charged, and neither beyond what is still outstanding.
 */
function returnedShare(
  sale: Record<string, unknown>,
  counted: CountedSale,
  lines: readonly ReturnedLine[]
): {take: number; cancel: number} {
  const subtotal = wholeMinor(sale.subtotalMinor);
  if (subtotal === 0) return {take: 0, cancel: 0};
  const priceOf = new Map<string, number>();
  const items = Array.isArray(sale.items) ? sale.items : [];
  for (const item of items) {
    if (!item || typeof item !== "object") continue;
    const record = item as Record<string, unknown>;
    if (typeof record.productId === "string") {
      priceOf.set(record.productId, wholeMinor(record.unitPriceMinor));
    }
  }
  const returnedListed = Math.min(
    subtotal,
    lines.reduce(
      (sum, line) => sum + line.quantity * (priceOf.get(line.productId) ?? 0),
      0
    )
  );

  const outstandingPoints = counted.points - counted.pointsReturned;
  const take = outstandingPoints <= 0 ? 0 : Math.min(
    outstandingPoints,
    Math.floor(counted.points * returnedListed / subtotal)
  );
  const outstandingOwed = counted.owedMinor - counted.creditReturnedMinor;
  const returnedCharged = Math.floor(
    wholeMinor(sale.totalMinor) * returnedListed / subtotal
  );
  const cancel = outstandingOwed <= 0 ? 0 : Math.min(outstandingOwed, returnedCharged);
  return {take, cancel};
}

/** The lines a stored return verification restored, as returned lines. */
function restoredLines(value: unknown): ReturnedLine[] {
  if (!Array.isArray(value)) return [];
  const lines: ReturnedLine[] = [];
  for (const item of value) {
    if (!item || typeof item !== "object") continue;
    const record = item as Record<string, unknown>;
    const quantity = wholeMinor(record.quantityRestored);
    if (typeof record.productId === "string" && quantity > 0) {
      lines.push({productId: record.productId, quantity});
    }
  }
  return lines;
}

/** One return's entry in the customer's ledger. */
function returnEntry(
  tenantId: string,
  customerId: string,
  saleId: string,
  sale: Record<string, unknown>,
  returned: AppliedReturn,
  createdAt: Timestamp | FieldValue = FieldValue.serverTimestamp()
): Record<string, unknown> {
  return {
    kind: "return",
    tenantId,
    customerId,
    saleId,
    returnId: returned.returnId,
    points: -returned.take,
    ...(returned.cancel > 0 ? {
      credit: true,
      balanceChangeMinor: -returned.cancel,
      balanceAfterMinor: returned.balanceAfterMinor,
      receiptNumber: typeof sale.receiptNumber === "string" ? sale.receiptNumber : null,
    } : {}),
    createdAt,
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

const CUSTOMER_SALE_MAX_ATTEMPTS = 30;

export const processCustomerSale = onTaskDispatched<CustomerSaleTask>(
  {
    invoker: "private",
    retryConfig: {
      // About a day of backoff, for a customer still on an offline till.
      maxAttempts: CUSTOMER_SALE_MAX_ATTEMPTS,
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
    // The last attempt Cloud Tasks will make: a credit sale's debt is placed
    // on a customer then, rather than dropped with the task.
    const lastAttempt = request.retryCount >= CUSTOMER_SALE_MAX_ATTEMPTS - 1;
    const outcome = await applyCustomerSale(db, data, {lastAttempt});
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
