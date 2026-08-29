import {DocumentData, getFirestore, Query} from "firebase-admin/firestore";
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
}

const SALES_QUERY_LIMIT = 5_000;
// Tenant-wide revenue and profit are management data. Cashier reporting needs
// a separate self-scoped contract that cannot be widened by the client.
const REPORTING_ROLES = ["owner", "admin", "manager"] as const;

function optionalDocumentId(value: unknown, field: string): string | undefined {
  const parsed = optionalString(value, field, {maxLength: 128});
  return parsed === undefined ? undefined : requireDocumentId(parsed, field);
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
  const soldById = optionalDocumentId(data.soldById, "soldById");
  const categoryId = optionalDocumentId(data.categoryId, "categoryId");
  const db = getFirestore();
  // **"reading", not "trading".** This is the one callable that only reads, and
  // a business whose provisional window has shut keeps sight of the week it
  // traded - the same allowance `readableTenant` makes in the rules.
  await requireTenantMember(
    db, request, tenantId, REPORTING_ROLES, undefined, {mode: "reading"}
  );

  let query: Query<DocumentData> = db.collection("tenants").doc(tenantId)
    .collection("sales")
    .where("businessDate", ">=", previousStartDate)
    .where("businessDate", "<=", previousEndDate);
  if (soldById) query = query.where("soldById", "==", soldById);
  const snapshot = await query.limit(SALES_QUERY_LIMIT + 1).get();
  if (snapshot.size > SALES_QUERY_LIMIT) {
    throw new HttpsError(
      "resource-exhausted",
      "The comparison contains too many transactions; use a shorter date range or daily metrics."
    );
  }
  const sales = snapshot.docs.map((document) => document.data() as SaleLike);
  return {
    previous: aggregateSales(sales, categoryId),
    scannedTransactions: snapshot.size,
    byTender: aggregateSalesByTender(sales, categoryId),
  };
});

// Public export name replaces the unsafe legacy root callable once index.ts is rewired.
export {getTenantSalesComparison as getSalesComparison};
