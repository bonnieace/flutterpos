import {FieldValue, Timestamp} from "firebase-admin/firestore";
import type {DocumentSnapshot} from "firebase-admin/firestore";
import {CUSTOMER_ID_SHAPE} from "./customerId";

/**
 * What a sale on credit is, and what one does to a customer's balance.
 *
 * **A credit sale is a sale with `tender: "credit"`, a customer, and an amount
 * owed.** `creditOwedMinor` is the part the customer took home without paying,
 * more than nothing and at most the sale's total; the rest was paid at the
 * counter, by `creditPaidTender` - cash, M-Pesa or card - and counts in the
 * cashier's drawer like any other sale's money. A sale owed in full names no
 * paid tender at all.
 *
 * **The balance is the server's.** A till that sold on credit offline knows
 * the balance it last saw and nothing since, so the figure it prints is an
 * estimate (`creditBalanceAfterMinor`) and the customer's `balanceMinor` is
 * moved here, once per sale, in the transaction that counts the sale.
 *
 * **Blocked is recorded, not refused.** Any named customer may buy on credit
 * unless a manager has blocked them (`creditBlocked`). The till refuses a
 * blocked customer it knows about; a sale from a till that had not heard yet
 * has already happened by the time it reaches the server, and the goods have
 * gone, so its ledger entry says `whileBlocked: true` instead. A limit set
 * before limits were withdrawn is still compared, as `overLimit`.
 */

export const CREDIT_TENDER = "credit";

/** The tenders the paid part of a credit sale, or a repayment, may be made in. */
export const MONEY_TENDERS = ["cash", "mpesa", "card"] as const;
export type MoneyTender = (typeof MONEY_TENDERS)[number];

export function isMoneyTender(value: unknown): value is MoneyTender {
  return typeof value === "string" && (MONEY_TENDERS as readonly string[]).includes(value);
}

export interface SaleCredit {
  /** What the customer owes for this sale. */
  owedMinor: number;

  /** What was paid at the counter, which is the sale's total less the owed part. */
  paidMinor: number;

  /** How the paid part was paid, or null when nothing was. */
  paidTender: MoneyTender | null;
}

function safeInteger(value: unknown): number | null {
  return Number.isSafeInteger(value) ? value as number : null;
}

/**
 * The credit a stored sale records, or null when it is not a credit sale.
 *
 * A sale that says `credit` but does not add up - nothing owed, more owed than
 * it cost, a paid part with no tender - is read as null too: it is not
 * evidence of a debt, and nothing should be charged to a customer from it.
 *
 * **So is one that names nobody the server can charge.** `processCustomerSale`
 * acts only on an ID shaped [CUSTOMER_ID_SHAPE], so a credit sale naming
 * anything else would leave the owed part out of the drawer and on no
 * customer's balance. Read as null, its whole total is expected of the shift
 * as unattributed takings, and money missing from the drawer shows in the
 * total variance rather than vanishing.
 */
export function readSaleCredit(sale: Record<string, unknown> | undefined): SaleCredit | null {
  if (sale?.tender !== CREDIT_TENDER) return null;
  if (typeof sale.customerId !== "string" || !CUSTOMER_ID_SHAPE.test(sale.customerId)) {
    return null;
  }
  const owed = safeInteger(sale.creditOwedMinor);
  const total = safeInteger(sale.totalMinor);
  if (owed === null || total === null || owed <= 0 || owed > total) return null;
  const paid = total - owed;
  const paidTender = sale.creditPaidTender;
  if (paid > 0 && !isMoneyTender(paidTender)) return null;
  if (paid === 0 && paidTender !== undefined && paidTender !== null) return null;
  return {owedMinor: owed, paidMinor: paid, paidTender: paid > 0 ? paidTender as MoneyTender : null};
}

/** A customer's stored balance; anything unreadable is nothing owed. */
export function storedBalance(customer: DocumentSnapshot): number {
  return safeInteger(customer.get("balanceMinor")) ?? 0;
}

/** A customer's stored credit limit, or null for no credit. */
export function storedCreditLimit(customer: DocumentSnapshot): number | null {
  const limit = safeInteger(customer.get("creditLimitMinor"));
  return limit !== null && limit > 0 ? limit : null;
}

/**
 * The fields that move a customer's balance by [changeMinor].
 *
 * **Written as the absolute balance the transaction computed**, not as an
 * increment, because `owingSince` depends on where the balance was and where
 * it lands: set when a customer who owed nothing starts to owe, cleared when
 * they owe nothing again - and `owing`, which a list can filter on. [at] is
 * when the debt began - the sale's own time,
 * so an offline sale that arrives a day late still says how long it has been
 * owed.
 */
export function balanceFields(
  before: number,
  changeMinor: number,
  at: Timestamp | FieldValue
): Record<string, unknown> {
  const after = before + changeMinor;
  return {
    balanceMinor: after,
    // An equality the "who owes" list filters on, since a device query cannot
    // ask for a balance above zero and sort by it in the same breath.
    owing: after > 0,
    ...(before <= 0 && after > 0 ? {owingSince: at} : {}),
    ...(after <= 0 && before > 0 ? {owingSince: FieldValue.delete()} : {}),
  };
}
