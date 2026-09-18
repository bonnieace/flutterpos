import {Firestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  normalizeReturnStockLines,
  PeriodReturns,
  requireIsoDate,
} from "./domain";

/**
 * Reading a period's returns, so reports can net them out of its sales.
 *
 * **The Firestore half only.** The arithmetic lives in `domain.ts` beside
 * `saleContribution`, because an aggregate and any split of the same sales
 * have to agree by construction - the `planSaleTenderRecord` split, applied
 * here.
 *
 * **No `status` filter, and that is a decision rather than an omission.**
 * Pending returns count against takings: the standing product decision is that
 * a report agrees with what the cashier just did rather than with what a
 * manager has not got to yet, which is what `lib/returns/return_offsets.dart`
 * already does on the device. Staying status-agnostic is also what keeps the
 * index bill at zero - `returns` is indexed on `businessDate` alone, and any
 * query combining it with `status` would need a new composite.
 */

/** The most return documents one period read will take before failing. */
export const RETURNS_QUERY_LIMIT = 5_000;

/**
 * Every return filed against one span of business dates, grouped by sale.
 *
 * **Bound to the sale's own day, not the day it was handed back.**
 * `firestore.rules` pins a return's `businessDate` to the `businessDate` of
 * the sale it reverses, so every return inside a date window has its sale
 * inside the same window. That invariant is what lets the caller scope this by
 * simply skipping a return whose sale is not in the sales it already read - a
 * miss is another cashier's, or another category's, and needs no second query
 * and no `soldById` on the return document.
 */
export interface PeriodReturnsRead {
  /** Units returned, grouped by the sale each return reverses. */
  returns: PeriodReturns;
  /**
   * How many return *documents* were read.
   *
   * Deliberately not the size of [returns], which counts the sales touched:
   * two returns against one sale are two documents and one entry, and a
   * client reporting "how much came back" needs the former.
   */
  scanned: number;
}

export async function readPeriodReturns(
  db: Firestore,
  tenantId: string,
  startDate: string,
  endDate: string,
  limit: number = RETURNS_QUERY_LIMIT
): Promise<PeriodReturnsRead> {
  requireIsoDate(startDate, "startDate");
  requireIsoDate(endDate, "endDate");
  const snapshot = await db.collection("tenants").doc(tenantId)
    .collection("returns")
    .where("businessDate", ">=", startDate)
    .where("businessDate", "<=", endDate)
    .limit(limit + 1)
    .get();
  if (snapshot.size > limit) {
    throw new HttpsError(
      "resource-exhausted",
      "The period holds more returns than can be read at once; use a shorter date range."
    );
  }

  const bySale = new Map<string, Map<string, number>>();
  for (const document of snapshot.docs) {
    const saleId = document.get("saleId");
    if (typeof saleId !== "string" || saleId.length === 0) {
      throw new HttpsError(
        "failed-precondition",
        `Return ${document.id} does not name the sale it reverses.`
      );
    }
    // The same normaliser the verification path uses, so a malformed return is
    // refused identically wherever it is read rather than quietly contributing
    // nothing to a total it claims to reduce.
    const lines = normalizeReturnStockLines(document.get("itemsReturned"));
    const units = bySale.get(saleId) ?? new Map<string, number>();
    for (const line of lines) {
      units.set(line.productId, (units.get(line.productId) ?? 0) + line.quantity);
    }
    bySale.set(saleId, units);
  }
  return {returns: bySale, scanned: snapshot.size};
}
