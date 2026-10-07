import {DocumentData, Firestore, getFirestore, Query} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {requireTenantMember} from "../core/authorization";
import {
  optionalString,
  requireDocumentId,
  requireObject,
} from "../core/validation";
import {
  aggregateSales,
  aggregateSalesByTender,
  assertDateRange,
  PeriodMetrics,
  requireIsoDate,
  SaleLike,
  TenderBreakdown,
} from "./domain";
import {readSalesSummaries} from "./salesSummaries";
import {readPeriodReturns} from "./returnOffsets";

interface SalesComparisonRequest {
  tenantId?: unknown;
  previousStartDate?: unknown;
  previousEndDate?: unknown;
  soldById?: unknown;
  categoryId?: unknown;
}

export interface SalesComparisonResponse {
  previous: PeriodMetrics;
  scannedTransactions: number;
  /**
   * The same takings split by how each sale was paid for. Additive: a client
   * that does not read it is unaffected, and one that does can check the split
   * against `previous` rather than trust it.
   */
  byTender: TenderBreakdown;
  /**
   * The same period with its returns taken back out of it.
   *
   * **Additive, and `previous` stays gross - which is a compatibility
   * requirement, not a preference.** `TenantSalesTotals.fromCallable` refuses
   * any answer whose `previous.transactions` disagrees with
   * `scannedTransactions` on an unfiltered read. Netting a fully returned sale
   * out of `previous` in place would break that identity on every installed
   * client, and the report would render blank rather than merely stale.
   *
   * A client that does not read these is unaffected and reports gross, which
   * is what it did before. A new client against an old server sees them absent
   * and does the same. So there is no deploy ordering to get right.
   */
  net: PeriodMetrics;
  /** [net] split the same way [byTender] splits `previous`. */
  netByTender: TenderBreakdown;
  /** How many return documents the period held. */
  returnsScanned: number;
}

/** Everything the comparison is asked for, already validated. */
export interface SalesComparisonQuery {
  tenantId: string;
  previousStartDate: string;
  previousEndDate: string;
  soldById?: string;
  categoryId?: string;
}

const SALES_QUERY_LIMIT = 5_000;
// Cashier requests are forced to self and have profit redacted below.
const REPORTING_ROLES = ["owner", "admin", "manager", "cashier"] as const;

function optionalDocumentId(value: unknown, field: string): string | undefined {
  const parsed = optionalString(value, field, {maxLength: 128});
  return parsed === undefined ? undefined : requireDocumentId(parsed, field);
}

/** Enforced after canonical membership authorization, before any report read. */
export function resolveSalesReportStaff(role: string, uid: string, requested?: string): string | undefined {
  if (role !== "cashier") return requested;
  if (requested !== undefined && requested !== uid) {
    throw new HttpsError("permission-denied", "Cashiers may only read their own totals.");
  }
  return uid;
}

export const getTenantSalesComparison = onCall<
  SalesComparisonRequest,
  Promise<SalesComparisonResponse>
>(async (request: CallableRequest<SalesComparisonRequest>): Promise<SalesComparisonResponse> => {
  const data = requireObject(request.data);
  const tenantId = requireDocumentId(data.tenantId, "tenantId");
  const previousStartDate = requireIsoDate(data.previousStartDate, "previousStartDate");
  const previousEndDate = requireIsoDate(data.previousEndDate, "previousEndDate");
  assertDateRange(previousStartDate, previousEndDate);
  let soldById = optionalDocumentId(data.soldById, "soldById");
  const categoryId = optionalDocumentId(data.categoryId, "categoryId");
  const db = getFirestore();
  const actor = await requireTenantMember(db, request, tenantId, REPORTING_ROLES);
  soldById = resolveSalesReportStaff(actor.staff.role, actor.uid, soldById);
  const answer = await readSalesSummaries(db, {
    tenantId,
    previousStartDate,
    previousEndDate,
    soldById,
    categoryId,
  });
  if (actor.staff.role === "cashier") {
    answer.previous.profit = 0;
    answer.net.profit = 0;
    answer.previous.incompleteCostLineCount = 1;
    answer.net.incompleteCostLineCount = 1;
  }
  return answer;
});

/**
 * The comparison itself, with the authorization and request parsing lifted off
 * it.
 *
 * Split out for the reason `planSaleTenderRecord` is: an `onCall` cannot be
 * called from a test, so everything worth asserting would otherwise only be
 * reachable through the emulator.
 */
export async function buildSalesComparison(
  db: Firestore,
  query: SalesComparisonQuery
): Promise<SalesComparisonResponse> {
  const {tenantId, previousStartDate, previousEndDate, soldById, categoryId} = query;
  let sales: Query<DocumentData> = db.collection("tenants").doc(tenantId)
    .collection("sales")
    .where("businessDate", ">=", previousStartDate)
    .where("businessDate", "<=", previousEndDate);
  if (soldById) sales = sales.where("soldById", "==", soldById);
  const snapshot = await sales.limit(SALES_QUERY_LIMIT + 1).get();
  if (snapshot.size > SALES_QUERY_LIMIT) {
    throw new HttpsError(
      "resource-exhausted",
      "The comparison contains too many transactions; use a shorter date range or daily metrics."
    );
  }
  // **The document id is carried through**, because it is what a return names
  // and there is nothing else on a sale that always identifies it.
  const documents = snapshot.docs.map(
    (document) => ({...document.data(), saleId: document.id} as SaleLike)
  );
  const {returns, scanned} = await readPeriodReturns(
    db,
    tenantId,
    previousStartDate,
    previousEndDate
  );
  // Two passes over the same array rather than one emitting both shapes: each
  // is O(lines), only the second reads `returns`, and the gross figures stay
  // exactly the expression they have always been.
  return {
    previous: aggregateSales(documents, categoryId),
    scannedTransactions: snapshot.size,
    byTender: aggregateSalesByTender(documents, categoryId),
    net: aggregateSales(documents, categoryId, returns),
    netByTender: aggregateSalesByTender(documents, categoryId, returns),
    returnsScanned: scanned,
  };
}

// Public export name replaces the unsafe legacy root callable once index.ts is rewired.
export {getTenantSalesComparison as getSalesComparison};
