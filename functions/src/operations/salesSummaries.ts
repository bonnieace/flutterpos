import {createHash} from "node:crypto";
import {FieldValue, Firestore, FieldPath, getFirestore} from "firebase-admin/firestore";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  aggregateSales, aggregateSalesByTender, normalizeReturnStockLines,
  PeriodMetrics, SaleLike, TenderBreakdown, TENDER_BUCKETS, requireIsoDate,
} from "./domain";

// Private, server-owned projections. Clients always go through the authorized
// reporting callable. Amounts are stored in minor units to make deltas exact.
type Values = Record<string, number>;
interface Contribution {id: string; businessDate: string; values: Values}
const idFor = (day: string, staff?: string, category?: string): string =>
  createHash("sha256").update(JSON.stringify([day, staff ?? null, category ?? null])).digest("hex");

function valuesFor(sale: SaleLike, category: string | undefined,
  returns: ReadonlyMap<string, ReadonlyMap<string, number>>): Values {
  const result: Values = {};
  for (const [prefix, offsets] of [["gross", undefined], ["net", returns]] as const) {
    const metrics = aggregateSales([sale], category, offsets);
    result[`${prefix}_sales`] = Math.round(metrics.sales * 100);
    result[`${prefix}_profit`] = Math.round(metrics.profit * 100);
    result[`${prefix}_transactions`] = metrics.transactions;
    result[`${prefix}_incompleteCostLineCount`] = metrics.incompleteCostLineCount;
    const tenders = aggregateSalesByTender([sale], category, offsets);
    for (const tender of TENDER_BUCKETS) {
      result[`${prefix}_${tender}_sales`] = Math.round(tenders[tender].sales * 100);
      result[`${prefix}_${tender}_transactions`] = tenders[tender].transactions;
    }
  }
  result.scannedTransactions = 1;
  return result;
}

/** Read current source records, not the event payload: retries and events
 * delivered out of order apply only the difference from the last projection. */
export async function projectSaleTotals(db: Firestore, tenantId: string, saleId: string): Promise<void> {
  const tenant = db.collection("tenants").doc(tenantId);
  const contributionRef = tenant.collection("sales_total_contributions").doc(saleId);
  await db.runTransaction(async (tx) => {
    const [saleDoc, previousDoc] = await tx.getAll(tenant.collection("sales").doc(saleId), contributionRef);
    const returned = await tx.get(tenant.collection("returns").where("saleId", "==", saleId).limit(1001));
    if (returned.size > 1000) throw new HttpsError("resource-exhausted", "Too many returns for one sale.");
    const units = new Map<string, number>();
    for (const document of returned.docs) {
      for (const line of normalizeReturnStockLines(document.get("itemsReturned"))) {
        units.set(line.productId, (units.get(line.productId) ?? 0) + line.quantity);
      }
    }
    const next: Contribution[] = [];
    if (saleDoc.exists) {
      const businessDate = requireIsoDate(saleDoc.get("businessDate"), "businessDate");
      const sale = {...saleDoc.data(), saleId} as SaleLike;
      const categories = new Set<string>();
      if (Array.isArray(sale.items)) for (const item of sale.items) {
        if (typeof item?.categoryId === "string") categories.add(item.categoryId);
      }
      const staff = typeof sale.soldById === "string" ? [undefined, sale.soldById] : [undefined];
      for (const member of staff) for (const category of [undefined, ...categories]) {
        next.push({id: idFor(businessDate, member, category), businessDate,
          values: {...valuesFor(sale, category, new Map([[saleId, units]])), returnsScanned: returned.size}});
      }
    }
    const previous = (previousDoc.get("contributions") ?? []) as Contribution[];
    if (JSON.stringify(previous) === JSON.stringify(next)) return;
    const days = [...new Set([...previous, ...next].map((entry) => entry.businessDate))];
    const dayRefs = days.map((day) => tenant.collection("sales_totals_days").doc(day));
    // The day revision also serializes a nightly repair against live deltas.
    if (dayRefs.length) await tx.getAll(...dayRefs);
    const changes = new Map<string, {businessDate: string; values: Values}>();
    for (const [entries, sign] of [[previous, -1], [next, 1]] as const) {
      for (const entry of entries) {
        const change = changes.get(entry.id) ?? {businessDate: entry.businessDate, values: {}};
        for (const [key, value] of Object.entries(entry.values)) {
          change.values[key] = (change.values[key] ?? 0) + sign * value;
        }
        changes.set(entry.id, change);
      }
    }
    // Bound the write fanout, rather than publishing a partial category set.
    if (changes.size > 450) throw new HttpsError("resource-exhausted", "Too many categories in one sale.");
    for (const [id, change] of changes) {
      const increments: Record<string, unknown> = {};
      for (const [key, delta] of Object.entries(change.values)) increments[key] = FieldValue.increment(delta);
      tx.set(tenant.collection("sales_daily_totals").doc(id), {
        businessDate: change.businessDate, values: increments, updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
    for (const ref of dayRefs) tx.set(ref, {revision: FieldValue.increment(1)}, {merge: true});
    // Tender corrections and changed returns also need a later audit. Creating
    // a sale is already marked by its receipt hook; duplicate projections do
    // not get here and therefore cannot keep a day perpetually dirty.
    if (previous.length > 0) for (const day of days) {
      tx.set(tenant.collection("reconciliation_dirty_days").doc(day), {
        tenantId, businessDate: day, status: "dirty", revision: FieldValue.increment(1),
        dirtyReason: "sales_totals_changed", updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
    tx.set(contributionRef, {businessDate: next[0]?.businessDate ?? previous[0]?.businessDate ?? null,
      contributions: next, updatedAt: FieldValue.serverTimestamp()});
  });
}

/** One-time migration of an existing day. Idempotent projection writes allow
 * interrupted initialization and concurrent live events to resume safely. */
export async function initializeTotalsDay(db: Firestore, tenantId: string, day: string): Promise<void> {
  const tenant = db.collection("tenants").doc(tenantId);
  const ready = tenant.collection("sales_totals_days").doc(day);
  const state = await ready.get();
  if (state.get("ready") === true) return;
  let cursor: string | undefined = typeof state.get("cursor") === "string" ? state.get("cursor") : undefined;
  for (;;) {
    let query = tenant.collection("sales").where("businessDate", "==", day)
      .orderBy(FieldPath.documentId()).limit(100);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    // Avoid contention on the business summary during initial backfill.
    for (const sale of page.docs) await projectSaleTotals(db, tenantId, sale.id);
    if (page.size < 100) break;
    cursor = page.docs[page.docs.length - 1].id;
    await ready.set({cursor}, {merge: true});
  }
  await ready.set({ready: true, initializedAt: FieldValue.serverTimestamp()}, {merge: true});
}

/** Recheck source contributions, then repair totals in revision-guarded batches.
 * Live projections invalidate the remaining batches instead of being overwritten. */
export async function repairTotalsDay(db: Firestore, tenantId: string, day: string,
  saleIds: readonly string[]): Promise<void> {
  for (let offset = 0; offset < saleIds.length; offset += 10) {
    await Promise.all(saleIds.slice(offset, offset + 10).map((id) => projectSaleTotals(db, tenantId, id)));
  }
  const tenant = db.collection("tenants").doc(tenantId);
  const dayRef = tenant.collection("sales_totals_days").doc(day);
  const audit = await db.runTransaction(async (tx) => {
    const state = await tx.get(dayRef);
    const contributions = await tx.get(tenant.collection("sales_total_contributions")
      .where("businessDate", "==", day).limit(5001));
    const existing = await tx.get(tenant.collection("sales_daily_totals")
      .where("businessDate", "==", day).limit(10001));
    if (contributions.size > 5000 || existing.size > 10000) {
      throw new HttpsError("resource-exhausted", "Daily summary repair exceeds its bounded window.");
    }
    const sums = new Map<string, Values>(existing.docs.map((doc) => [doc.id, {}]));
    for (const doc of contributions.docs) for (const contribution of doc.get("contributions") as Contribution[]) {
      if (contribution.businessDate !== day) continue;
      const values = sums.get(contribution.id) ?? {};
      for (const [key, value] of Object.entries(contribution.values)) values[key] = (values[key] ?? 0) + value;
      sums.set(contribution.id, values);
    }
    return {revision: state.get("revision") ?? 0, sums: [...sums.entries()]};
  });
  // Each batch checks the source revision. Live deltas after an earlier batch
  // remain valid; if activity resumes, leave the other scopes for the next audit.
  for (let offset = 0; offset < audit.sums.length; offset += 400) {
    const applied = await db.runTransaction(async (tx) => {
      const state = await tx.get(dayRef);
      if ((state.get("revision") ?? 0) !== audit.revision) return false;
      for (const [id, values] of audit.sums.slice(offset, offset + 400)) {
        tx.set(tenant.collection("sales_daily_totals").doc(id), {
          businessDate: day, values, updatedAt: FieldValue.serverTimestamp(),
        });
      }
      return true;
    });
    if (!applied) return;
  }
}

export async function readSalesSummaries(db: Firestore, query: {
  tenantId: string; previousStartDate: string; previousEndDate: string; soldById?: string; categoryId?: string;
}): Promise<{previous: PeriodMetrics; net: PeriodMetrics; byTender: TenderBreakdown;
  netByTender: TenderBreakdown; summaryVersion: number; scannedTransactions: number; returnsScanned: number}> {
  const values: Values = {};
  for (let day = query.previousStartDate; day <= query.previousEndDate;) {
    await initializeTotalsDay(db, query.tenantId, day);
    const doc = await db.collection("tenants").doc(query.tenantId).collection("sales_daily_totals")
      .doc(idFor(day, query.soldById, query.categoryId)).get();
    for (const [key, value] of Object.entries(doc.get("values") ?? {})) {
      values[key] = (values[key] ?? 0) + Number(value);
    }
    const next = new Date(`${day}T00:00:00Z`);
    next.setUTCDate(next.getUTCDate() + 1);
    day = next.toISOString().slice(0, 10);
  }
  const metrics = (prefix: string): PeriodMetrics => ({
    sales: (values[`${prefix}_sales`] ?? 0) / 100,
    profit: (values[`${prefix}_profit`] ?? 0) / 100,
    transactions: values[`${prefix}_transactions`] ?? 0,
    incompleteCostLineCount: values[`${prefix}_incompleteCostLineCount`] ?? 0,
  });
  const tenders = (prefix: string): TenderBreakdown => Object.fromEntries(TENDER_BUCKETS.map((bucket) =>
    [bucket, {sales: (values[`${prefix}_${bucket}_sales`] ?? 0) / 100,
      transactions: values[`${prefix}_${bucket}_transactions`] ?? 0}])) as TenderBreakdown;
  return {summaryVersion: 1, previous: metrics("gross"), net: metrics("net"), byTender: tenders("gross"),
    netByTender: tenders("net"), scannedTransactions: values.scannedTransactions ?? 0, returnsScanned: values.returnsScanned ?? 0};
}

export const updateSaleDailyTotals = onDocumentWritten({
  document: "tenants/{tenantId}/sales/{saleId}", retry: true,
}, async (event) => projectSaleTotals(getFirestore(), event.params.tenantId, event.params.saleId));

export const updateReturnDailyTotals = onDocumentWritten({
  document: "tenants/{tenantId}/returns/{returnId}", retry: true,
}, async (event) => {
  const ids = new Set([event.data?.before.get("saleId"), event.data?.after.get("saleId")]);
  for (const id of ids) if (typeof id === "string" && id.length > 0 && !id.includes("/")) {
    await projectSaleTotals(getFirestore(), event.params.tenantId, id);
  }
});
