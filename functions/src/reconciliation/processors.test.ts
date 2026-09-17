import assert from "node:assert/strict";
import test from "node:test";
import {DocumentData, Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {FakeFirestore, FakeTransaction} from "../testing/fakeFirestore";
import {ClaimedReconciliationJob} from "./jobs";
import {
  digest,
  shiftAnomalyId,
  shiftExpectationId,
  shiftTenderAnomalyId,
  trailingIsoDates,
  TENDER_DECLARATION_REQUIRED_FROM,
} from "./model";
import {
  initializeFullReconciliationWindow,
  processMetricsPage,
  processShiftPage,
  processStockPage,
} from "./processors";

/**
 * The four exported reconciliation processors, against an in-memory Firestore.
 *
 * The integration suite proves what these do end to end and is the only coverage
 * they have ever had. What it cannot reach is the shape of a page: the products
 * page is 25 wide, the movements page 200, the shifts page 50, and the metrics
 * page 5, so every boundary assertion there would mean seeding tens or hundreds of
 * documents per run against a real emulator. The behaviour under test here is
 * therefore the paging itself - the cursor a partial page resumes from, a page
 * that ends exactly on its own boundary, a lease revoked between two products of
 * one page, and a phase that finds nothing - plus the atomicity each of those
 * depends on.
 *
 * Every fixture is settled in the past on purpose. `reconcileProduct` defers a
 * product written inside the last five minutes and records
 * `recent_write_deferred` instead of comparing it, so a fixture stamped `now`
 * tests the deferral and asserts nothing about stock. That mistake has been made
 * once in this repository already.
 */

const TENANT = "tenant-a";
const JOB = "rj_page_test";
const LEASE = "lease-token-1";
const LOCAL_DATE = "2026-08-05";
const GENERATION = 3;
const REVISION = 7;

/** Comfortably outside `reconcileProduct`'s five-minute deferral window. */
const SETTLED = Timestamp.fromMillis(Date.now() - 10 * 60 * 1000);

function jobPath(jobId = JOB): string {
  return `tenants/${TENANT}/reconciliation_jobs/${jobId}`;
}

function claimedJob(
  overrides: Partial<ClaimedReconciliationJob> = {}
): ClaimedReconciliationJob {
  return {
    tenantId: TENANT,
    jobId: JOB,
    source: "manual",
    sourceKey: "manual-1",
    mode: "incremental",
    checkpointKind: "none",
    checkpointKey: "manual-1",
    localDate: LOCAL_DATE,
    status: "running",
    phase: "metrics",
    generation: GENERATION,
    revision: REVISION,
    attemptCount: 1,
    consecutiveFailureCount: 0,
    rerunRequested: false,
    fullInitialized: true,
    metricsProcessed: 0,
    productsProcessed: 0,
    stockVarianceCount: 0,
    shiftsProcessed: 0,
    shiftVarianceCount: 0,
    tenderVarianceCount: 0,
    leaseToken: LEASE,
    ...overrides,
  };
}

/**
 * A Firestore holding the `reconciliation_jobs` document every processor
 * transaction re-reads. Without it `assertCurrentLease` throws before any phase
 * does anything, so this is the minimum any of these tests can start from.
 */
function firestoreWithClaimedJob(job = claimedJob()): FakeFirestore {
  const db = new FakeFirestore();
  db.seed(jobPath(job.jobId), {
    tenantId: job.tenantId,
    jobId: job.jobId,
    status: "running",
    generation: job.generation,
    revision: job.revision,
    leaseToken: job.leaseToken,
    leaseExpiresAt: Timestamp.fromMillis(Date.now() + 10 * 60 * 1000),
  });
  db.clearWrites();
  return db;
}

/** The document at `path`, refusing to assert about one that was never written. */
function stored(db: FakeFirestore, path: string): DocumentData {
  const document = db.read(path);
  assert.ok(document !== undefined, `Nothing was written at ${path}.`);
  return document;
}

/**
 * Runs `mutate` around the `nth` transaction a processor opens.
 *
 * Two of the behaviours worth pinning are only reachable from something changing
 * while a phase is part-way through: a dirty day re-marked at a higher revision
 * between the query and the transaction that would mark it clean, and a lease
 * revoked after one product of a page has already committed. Both are ordinary
 * concurrency against a real server and neither is schedulable from a test, so
 * they are staged here instead - at the transaction boundary, which is exactly
 * where the processors' own guards sit.
 */
function aroundTransaction(
  db: FakeFirestore,
  nth: number,
  when: "before" | "after",
  mutate: () => void
): void {
  type Body = (transaction: FakeTransaction) => Promise<unknown>;
  const target = db as unknown as {runTransaction(body: Body): Promise<unknown>};
  const original = target.runTransaction.bind(target);
  let seen = 0;
  target.runTransaction = async (body: Body): Promise<unknown> => {
    seen += 1;
    const staged = seen === nth;
    if (staged && when === "before") mutate();
    const result = await original(body);
    if (staged && when === "after") mutate();
    return result;
  };
}

/** Asserts `work` was refused because the processor no longer holds the lease. */
async function assertLeaseRefused(work: Promise<unknown>): Promise<void> {
  await assert.rejects(work, (error: unknown) =>
    error instanceof HttpsError && error.code === "aborted");
}

// ---------------------------------------------------------------------------
// initializeFullReconciliationWindow
// ---------------------------------------------------------------------------

test("a full run marks its whole trailing window dirty", async () => {
  const db = firestoreWithClaimedJob();
  const job = claimedJob();

  await initializeFullReconciliationWindow(db.asFirestore(), job);

  const dates = trailingIsoDates(LOCAL_DATE, 35);
  assert.deepEqual(db.ids(`tenants/${TENANT}/reconciliation_dirty_days`), [...dates].sort());
  for (const businessDate of dates) {
    const day = stored(db, `tenants/${TENANT}/reconciliation_dirty_days/${businessDate}`);
    assert.equal(day.status, "dirty");
    assert.equal(day.businessDate, businessDate);
    assert.equal(day.tenantId, TENANT);
    assert.equal(day.dirtyReason, "manual_full");
    // The window is written with `FieldValue.increment(1)`, so a day nothing had
    // marked before starts at one - which is what makes it a readable revision.
    assert.equal(day.revision, 1);
    assert.ok(day.updatedAt instanceof Timestamp);
  }
  // Every day is one merge. A replace would erase the `processedRevision` the
  // metrics phase compares a re-marked day against.
  assert.deepEqual([...new Set(db.writes.map((write) => write.kind))], ["merge"]);
  assert.equal(db.writes.length, 35);
});

test("an already-processed day is re-marked without losing what processed it", async () => {
  const db = firestoreWithClaimedJob();
  const settledDay = `tenants/${TENANT}/reconciliation_dirty_days/${LOCAL_DATE}`;
  db.seed(settledDay, {
    tenantId: TENANT,
    businessDate: LOCAL_DATE,
    status: "clean",
    revision: 4,
    processedRevision: 4,
    metricGeneration: "generation-of-the-last-pass",
  });

  await initializeFullReconciliationWindow(db.asFirestore(), claimedJob());

  const day = stored(db, settledDay);
  assert.equal(day.status, "dirty");
  assert.equal(day.revision, 5);
  // The pair that tells the metrics phase this day is behind rather than fresh.
  assert.equal(day.processedRevision, 4);
  assert.equal(day.metricGeneration, "generation-of-the-last-pass");
});

test("a monthly sweep names its own reason for the window", async () => {
  const db = firestoreWithClaimedJob();

  await initializeFullReconciliationWindow(
    db.asFirestore(),
    claimedJob({source: "monthly", sourceKey: "2026-08"})
  );

  assert.equal(
    stored(db, `tenants/${TENANT}/reconciliation_dirty_days/${LOCAL_DATE}`).dirtyReason,
    "monthly_full"
  );
});

test("a lease that is not current writes no part of the window", async () => {
  // Thirty-five sets are buffered before the lease is checked, so this is also
  // the assertion that a refused transaction commits nothing at all.
  const currentLease = {
    status: "running",
    generation: GENERATION,
    revision: REVISION,
    leaseToken: LEASE,
    leaseExpiresAt: Timestamp.fromMillis(Date.now() + 10 * 60 * 1000),
  };
  const notCurrent: Record<string, DocumentData | undefined> = {
    "no job document at all": undefined,
    "a job that is no longer running": {...currentLease, status: "failed"},
    "a later generation": {...currentLease, generation: GENERATION + 1},
    "a later revision": {...currentLease, revision: REVISION + 1},
    "another worker's lease": {...currentLease, leaseToken: "lease-token-2"},
    "an expired lease": {
      ...currentLease,
      leaseExpiresAt: Timestamp.fromMillis(Date.now() - 1000),
    },
    "no lease expiry": {...currentLease, leaseExpiresAt: undefined},
  };

  for (const [reason, document] of Object.entries(notCurrent)) {
    const db = new FakeFirestore();
    if (document !== undefined) {
      db.seed(jobPath(), Object.fromEntries(
        Object.entries(document).filter(([, value]) => value !== undefined)
      ));
    }
    db.clearWrites();

    await assertLeaseRefused(
      initializeFullReconciliationWindow(db.asFirestore(), claimedJob())
    );

    assert.deepEqual(db.ids(`tenants/${TENANT}/reconciliation_dirty_days`), [], reason);
    assert.deepEqual(db.writes, [], reason);
  }
});

// ---------------------------------------------------------------------------
// processMetricsPage
// ---------------------------------------------------------------------------

/** A day awaiting regeneration at `revision`. */
function seedDirtyDay(db: FakeFirestore, businessDate: string, revision = 1): void {
  db.seed(`tenants/${TENANT}/reconciliation_dirty_days/${businessDate}`, {
    tenantId: TENANT,
    businessDate,
    status: "dirty",
    revision,
  });
}

function seedSale(
  db: FakeFirestore,
  saleId: string,
  businessDate: string,
  shiftId: string,
  total: number,
  cost: number
): void {
  db.seed(`tenants/${TENANT}/sales/${saleId}`, {
    tenantId: TENANT,
    businessDate,
    shiftId,
    total,
    items: [{quantity: 1, unitPrice: total, unitCost: cost}],
  });
}

test("a metrics phase with nothing dirty writes nothing", async () => {
  const db = firestoreWithClaimedJob();

  assert.deepEqual(
    await processMetricsPage(db.asFirestore(), claimedJob()),
    {processed: 0, hasMore: false}
  );
  assert.deepEqual(db.writes, []);
});

test("the metrics page is bounded at five days and reports the remainder", async () => {
  const db = firestoreWithClaimedJob();
  const dates = trailingIsoDates(LOCAL_DATE, 7);
  for (const businessDate of dates) seedDirtyDay(db, businessDate);
  db.clearWrites();

  const first = await processMetricsPage(db.asFirestore(), claimedJob());

  assert.deepEqual(first, {processed: 5, hasMore: true});
  // Ordered by document ID, which for ISO dates is chronological.
  for (const businessDate of dates.slice(0, 5)) {
    assert.equal(
      stored(db, `tenants/${TENANT}/reconciliation_dirty_days/${businessDate}`).status,
      "clean",
      businessDate
    );
  }
  for (const businessDate of dates.slice(5)) {
    assert.equal(
      stored(db, `tenants/${TENANT}/reconciliation_dirty_days/${businessDate}`).status,
      "dirty",
      businessDate
    );
  }

  assert.deepEqual(
    await processMetricsPage(db.asFirestore(), claimedJob()),
    {processed: 2, hasMore: false}
  );
});

test("a full metrics page with nothing behind it does not claim more work", async () => {
  // The distinction from the stock phase, which is worth having both halves of in
  // one file: this phase probes for a remainder, so a page that ends exactly on
  // its own boundary reports `hasMore: false`. The stock phase infers it from the
  // page size instead and therefore over-reports on the same boundary.
  const db = firestoreWithClaimedJob();
  for (const businessDate of trailingIsoDates(LOCAL_DATE, 5)) seedDirtyDay(db, businessDate);
  db.clearWrites();

  assert.deepEqual(
    await processMetricsPage(db.asFirestore(), claimedJob()),
    {processed: 5, hasMore: false}
  );
});

test("regenerated metrics replace the day and derive one expectation per shift", async () => {
  const db = firestoreWithClaimedJob();
  const other = "2026-08-04";
  seedDirtyDay(db, LOCAL_DATE);
  seedSale(db, "sale-1", LOCAL_DATE, "shift-a", 20, 6);
  seedSale(db, "sale-2", LOCAL_DATE, "shift-b", 5, 2);
  seedSale(db, "sale-3", other, "shift-c", 99, 1);
  // A field from an earlier shape of the metric, and an expectation for a shift
  // this day no longer has. Both must be gone; the other day's must not be.
  db.seed(`tenants/${TENANT}/daily_metrics/${LOCAL_DATE}`, {
    tenantId: TENANT,
    businessDate: LOCAL_DATE,
    sales: 999,
    fieldFromAnEarlierShape: true,
  });
  db.seed(`tenants/${TENANT}/shift_expectations/stale_for_this_day`, {
    tenantId: TENANT,
    businessDate: LOCAL_DATE,
    shiftId: "shift-that-was-voided",
    generation: "generation-zero",
    needsVerification: true,
  });
  db.seed(`tenants/${TENANT}/shift_expectations/kept_for_another_day`, {
    tenantId: TENANT,
    businessDate: other,
    shiftId: "shift-c",
    generation: "generation-zero",
    needsVerification: true,
  });
  db.clearWrites();

  assert.deepEqual(
    await processMetricsPage(db.asFirestore(), claimedJob()),
    {processed: 1, hasMore: false}
  );

  const metric = stored(db, `tenants/${TENANT}/daily_metrics/${LOCAL_DATE}`);
  assert.equal(metric.sales, 25);
  assert.equal(metric.profit, 17);
  assert.equal(metric.transactionCount, 2);
  assert.equal(metric.shiftCount, 2);
  assert.equal(metric.sourceDirtyRevision, 1);
  // The write is unmerged, so a field the previous shape carried is gone rather
  // than left behind to be read as current.
  assert.equal("fieldFromAnEarlierShape" in metric, false);

  const expectationIds = [
    shiftExpectationId(LOCAL_DATE, "shift-a"),
    shiftExpectationId(LOCAL_DATE, "shift-b"),
  ];
  assert.deepEqual(
    db.ids(`tenants/${TENANT}/shift_expectations`),
    [...expectationIds, "kept_for_another_day"].sort()
  );
  for (const [id, shiftId, sales] of [
    [expectationIds[0], "shift-a", 20],
    [expectationIds[1], "shift-b", 5],
  ] as const) {
    const expectation = stored(db, `tenants/${TENANT}/shift_expectations/${id}`);
    assert.equal(expectation.shiftId, shiftId);
    assert.equal(expectation.sales, sales);
    assert.equal(expectation.transactions, 1);
    assert.equal(expectation.needsVerification, true);
    assert.equal(expectation.businessDate, LOCAL_DATE);
    // One regeneration is one generation, and the expectations it derived have to
    // agree with the metric they came from or nothing can tell which pass settled
    // a shift.
    assert.equal(expectation.metricGeneration, metric.metricGeneration);
  }

  const day = stored(db, `tenants/${TENANT}/reconciliation_dirty_days/${LOCAL_DATE}`);
  assert.equal(day.status, "clean");
  assert.equal(day.processedRevision, 1);
  assert.equal(day.metricGeneration, metric.metricGeneration);
  assert.match(`${metric.metricGeneration}`, /^[0-9a-f]{40}$/);
});

test("a dirty day with an unusable revision is quarantined and still counts", async () => {
  // Counting it is what stops the phase from meeting the same poisoned day on
  // every pass forever, and quarantining it is what takes it out of the query.
  for (const revision of [undefined, 0, -1, 1.5, "1"]) {
    const db = firestoreWithClaimedJob();
    db.seed(`tenants/${TENANT}/reconciliation_dirty_days/${LOCAL_DATE}`, {
      tenantId: TENANT,
      businessDate: LOCAL_DATE,
      status: "dirty",
      ...(revision === undefined ? {} : {revision}),
    });
    db.clearWrites();

    assert.deepEqual(
      await processMetricsPage(db.asFirestore(), claimedJob()),
      {processed: 1, hasMore: false},
      `${revision}`
    );

    const day = stored(db, `tenants/${TENANT}/reconciliation_dirty_days/${LOCAL_DATE}`);
    assert.equal(day.status, "quarantined", `${revision}`);
    assert.equal(day.lastErrorCode, "invalid_dirty_revision", `${revision}`);
    assert.deepEqual(db.ids(`tenants/${TENANT}/daily_metrics`), [], `${revision}`);
  }
});

test("a day re-marked while it was being regenerated is left for the next pass", async () => {
  const db = firestoreWithClaimedJob();
  const dayPath = `tenants/${TENANT}/reconciliation_dirty_days/${LOCAL_DATE}`;
  seedDirtyDay(db, LOCAL_DATE);
  seedSale(db, "sale-1", LOCAL_DATE, "shift-a", 20, 6);
  db.clearWrites();
  // A sale landing after the aggregation read but before the transaction that
  // would mark the day clean. Marking it clean here would lose that sale until
  // something else marked the day again.
  aroundTransaction(db, 1, "before", () => {
    db.seed(dayPath, {...stored(db, dayPath), revision: 2});
  });

  assert.deepEqual(
    await processMetricsPage(db.asFirestore(), claimedJob()),
    {processed: 0, hasMore: true}
  );

  const day = stored(db, dayPath);
  assert.equal(day.status, "dirty");
  assert.equal(day.revision, 2);
  assert.equal("processedRevision" in day, false);
  assert.deepEqual(db.ids(`tenants/${TENANT}/daily_metrics`), []);
  assert.deepEqual(db.ids(`tenants/${TENANT}/shift_expectations`), []);
});

/**
 * The two bounds `regenerateDailyMetric` refuses a business date over.
 *
 * Neither had ever been asserted anywhere, and the reason was the emulator: five
 * thousand sales or two hundred expectations per assertion is not a fixture a real
 * Firestore run can afford, so the standing suggestion was to make the page sizes
 * injectable and prove the bounds at a smaller number. That is not needed - these
 * seed the real figures in memory, which is exactly the trade this double exists
 * for, and the production constants stay private.
 *
 * What matters about both is not that they throw but *when*: the refusal is raised
 * before the transaction opens, so a date over either bound keeps its old daily
 * metric and stays dirty rather than being republished from a truncated read. A
 * bound checked one line later would publish an aggregate over the first 5,000
 * sales of the day and mark the day clean, and nothing downstream could tell that
 * figure from a complete one.
 */

const DAILY_SALES_LIMIT = 5_000;
const SHIFT_EXPECTATION_LIMIT = 200;

/** Asserts `work` was refused for exceeding a bound rather than for anything else. */
async function assertBoundExceeded(work: Promise<unknown>, expected: RegExp): Promise<void> {
  await assert.rejects(work, (error: unknown) => {
    assert.ok(error instanceof HttpsError);
    assert.equal(error.code, "resource-exhausted");
    assert.match(error.message, expected);
    return true;
  });
}

test("a business date one sale over the aggregation bound is refused, not truncated", async () => {
  const db = firestoreWithClaimedJob();
  seedDirtyDay(db, LOCAL_DATE);
  // One shift for all of them, so this test meets the sales bound and not
  // `aggregateDailySales`'s separate 200-shift bound.
  for (let index = 1; index <= DAILY_SALES_LIMIT + 1; index += 1) {
    seedSale(db, `sale-${`${index}`.padStart(5, "0")}`, LOCAL_DATE, "shift-a", 1, 0);
  }
  db.clearWrites();

  await assertBoundExceeded(
    processMetricsPage(db.asFirestore(), claimedJob()),
    /bounded daily aggregation limit/
  );

  // Nothing at all. The day is still owed a regeneration, which is the only
  // honest state for a date whose sales cannot be read in one bounded pass.
  assert.deepEqual(db.writes, []);
  assert.equal(
    stored(db, `tenants/${TENANT}/reconciliation_dirty_days/${LOCAL_DATE}`).status,
    "dirty"
  );
  assert.deepEqual(db.ids(`tenants/${TENANT}/daily_metrics`), []);
});

test("a business date exactly on the aggregation bound is regenerated", async () => {
  // The other side of the same comparison, and the reason it is `>` rather than
  // `>=`: the query reads one more than the bound precisely so that a date sitting
  // exactly on it is still a complete read.
  const db = firestoreWithClaimedJob();
  seedDirtyDay(db, LOCAL_DATE);
  for (let index = 1; index <= DAILY_SALES_LIMIT; index += 1) {
    seedSale(db, `sale-${`${index}`.padStart(5, "0")}`, LOCAL_DATE, "shift-a", 1, 0);
  }
  db.clearWrites();

  assert.deepEqual(
    await processMetricsPage(db.asFirestore(), claimedJob()),
    {processed: 1, hasMore: false}
  );

  const metric = stored(db, `tenants/${TENANT}/daily_metrics/${LOCAL_DATE}`);
  // Every one of them counted, so the pass that succeeded read the whole day.
  assert.equal(metric.transactionCount, DAILY_SALES_LIMIT);
  assert.equal(metric.sales, DAILY_SALES_LIMIT);
  assert.equal(metric.shiftCount, 1);
  assert.equal(
    stored(db, `tenants/${TENANT}/reconciliation_dirty_days/${LOCAL_DATE}`).status,
    "clean"
  );
});

test("a business date one expectation over the stale bound is refused, not truncated", async () => {
  // The bound on what is *already* stored for the date, which is the half of the
  // transaction that deletes. A date holding more stale expectations than one
  // transaction may delete cannot be republished at all, and saying so is better
  // than leaving some of them behind pointing at a metric generation that is gone.
  const db = firestoreWithClaimedJob();
  seedDirtyDay(db, LOCAL_DATE);
  seedSale(db, "sale-1", LOCAL_DATE, "shift-a", 20, 6);
  for (let index = 1; index <= SHIFT_EXPECTATION_LIMIT + 1; index += 1) {
    seedExpectation(db, `stale-${`${index}`.padStart(4, "0")}`, {
      shiftId: `shift-old-${index}`,
      sales: 1,
      transactions: 1,
    });
  }
  db.clearWrites();

  await assertBoundExceeded(
    processMetricsPage(db.asFirestore(), claimedJob()),
    /bounded shift expectation limit/
  );

  assert.deepEqual(db.writes, []);
  assert.equal(
    stored(db, `tenants/${TENANT}/reconciliation_dirty_days/${LOCAL_DATE}`).status,
    "dirty"
  );
  assert.deepEqual(db.ids(`tenants/${TENANT}/daily_metrics`), []);
  // And the stale ones are all still there, rather than partly deleted.
  assert.equal(
    db.ids(`tenants/${TENANT}/shift_expectations`).length,
    SHIFT_EXPECTATION_LIMIT + 1
  );
});

test("a business date exactly on the stale bound is regenerated and swept clean", async () => {
  const db = firestoreWithClaimedJob();
  seedDirtyDay(db, LOCAL_DATE);
  seedSale(db, "sale-1", LOCAL_DATE, "shift-a", 20, 6);
  for (let index = 1; index <= SHIFT_EXPECTATION_LIMIT; index += 1) {
    seedExpectation(db, `stale-${`${index}`.padStart(4, "0")}`, {
      shiftId: `shift-old-${index}`,
      sales: 1,
      transactions: 1,
    });
  }
  db.clearWrites();

  assert.deepEqual(
    await processMetricsPage(db.asFirestore(), claimedJob()),
    {processed: 1, hasMore: false}
  );

  // Two hundred deletions and one write, in the transaction that also marks the
  // day clean: this is the widest this phase's write set is allowed to get, and it
  // is why the bound is where it is rather than higher.
  assert.deepEqual(
    db.ids(`tenants/${TENANT}/shift_expectations`),
    [shiftExpectationId(LOCAL_DATE, "shift-a")]
  );
  assert.equal(
    stored(db, `tenants/${TENANT}/reconciliation_dirty_days/${LOCAL_DATE}`).status,
    "clean"
  );
});

// ---------------------------------------------------------------------------
// processStockPage
// ---------------------------------------------------------------------------

/**
 * A product settled outside the deferral window, so it is compared rather than
 * deferred.
 *
 * **It gets an opening-balance movement matching its quantity**, because that is
 * what a real product has - `createProduct` writes one, `importProducts` writes
 * one - and reconciliation now adds a ledger up from nothing rather than
 * accepting the figure it finds. A product seeded without one holds stock that
 * nothing accounts for, and a variance is the correct answer for it, so the
 * tests that want that case ask for it with `opening: false`.
 */
function seedProduct(
  db: FakeFirestore,
  productId: string,
  quantity: number,
  options: {opening?: boolean} = {}
): void {
  db.seed(`tenants/${TENANT}/products/${productId}`, {
    tenantId: TENANT,
    name: productId,
    quantity,
    updatedAt: SETTLED,
  });
  if (options.opening === false) return;
  db.seed(`tenants/${TENANT}/products/${productId}/stock_movements/mv_000`, {
    tenantId: TENANT,
    productId,
    sourceType: "product_created",
    quantityDelta: quantity,
    // Before any movement a test seeds by hand, so a replay reaches it first.
    recordedAt: Timestamp.fromMillis(SETTLED.toMillis() - 60 * 1000),
  });
}

function productIds(count: number): string[] {
  return Array.from(
    {length: count},
    (_, index) => `product-${`${index + 1}`.padStart(2, "0")}`
  );
}

test("a stock phase with no products writes nothing", async () => {
  const db = firestoreWithClaimedJob();

  assert.deepEqual(
    await processStockPage(db.asFirestore(), claimedJob({phase: "stock"})),
    {processed: 0, varianceCount: 0, hasMore: false, productCursor: undefined}
  );
  assert.deepEqual(db.writes, []);
});

test("a stock page that ends exactly on its own boundary claims work it has not got", async () => {
  // `hasMore` is inferred from the page being full rather than probed for, so a
  // catalog of exactly twenty-five products costs one extra empty page. Recorded
  // as the behaviour it is: the phase is correct - it never stops early - and the
  // page after it settles the question.
  const db = firestoreWithClaimedJob();
  for (const productId of productIds(25)) seedProduct(db, productId, 10);
  db.clearWrites();
  const job = claimedJob({phase: "stock"});

  const full = await processStockPage(db.asFirestore(), job);

  assert.deepEqual(full, {
    processed: 25,
    varianceCount: 0,
    hasMore: true,
    productCursor: "product-25",
  });
  assert.deepEqual(
    db.ids(`tenants/${TENANT}/stock_reconciliation_state`),
    productIds(25)
  );
  // **Compared on its first run, not baselined.** A product no run has carried
  // state for used to have its current figure accepted as the expectation; it is
  // now added up from its ledger, which for these is one opening balance of ten
  // against ten held. They agree, so the page reports no difference - but it is
  // a comparison that reached that answer, not an assumption.
  assert.equal(
    stored(db, `tenants/${TENANT}/stock_reconciliation_state/product-01`).status,
    "matched"
  );

  assert.deepEqual(
    await processStockPage(db.asFirestore(), {...job, productCursor: "product-25"}),
    {processed: 0, varianceCount: 0, hasMore: false, productCursor: "product-25"}
  );
});

test("a stock page one short of its boundary reports no more work", async () => {
  const db = firestoreWithClaimedJob();
  for (const productId of productIds(24)) seedProduct(db, productId, 10);
  db.clearWrites();

  assert.deepEqual(
    await processStockPage(db.asFirestore(), claimedJob({phase: "stock"})),
    {processed: 24, varianceCount: 0, hasMore: false, productCursor: "product-24"},
  );
});

test("stock no movement accounts for is a variance on the very first check", async () => {
  // **The defect this closes, stated as the case that used to pass silently.**
  // A product's first reconciliation read whatever quantity it found and made
  // that the expectation, so the first thing the system ever did to a product
  // was agree with it. A shop already seventeen units adrift stayed adrift
  // forever: every checkpoint after the baseline was sound, and all of them
  // rested on a number nobody had ever checked.
  //
  // Seventeen on the books and an empty ledger is now what it looks like -
  // seventeen units the product claims that no movement ever put there, which
  // is `stock_over_ledger`: the books are over what the ledger accounts for.
  const db = firestoreWithClaimedJob();
  seedProduct(db, "product-01", 17, {opening: false});
  db.clearWrites();

  assert.deepEqual(
    await processStockPage(db.asFirestore(), claimedJob({phase: "stock"})),
    {processed: 1, varianceCount: 1, hasMore: false, productCursor: "product-01"}
  );

  const state = stored(db, `tenants/${TENANT}/stock_reconciliation_state/product-01`);
  assert.equal(state.status, "variance");
  assert.equal(state.expectedQuantity, 0);
  assert.equal(state.observedQuantity, 17);
  assert.equal(state.lastVariance, 17);
  assert.equal(
    stored(
      db,
      `tenants/${TENANT}/reconciliation_anomalies/stock_${digest(["product-01", JOB])}`
    ).anomalyType,
    "stock_over_ledger"
  );
});

test("a product whose ledger accounts for it matches on its first check", async () => {
  // The other half of the same change, and the one that says it is not a way of
  // manufacturing variances. Ten opened, three sold, seven held: the ledger
  // reaches the shelf, so the run reports agreement having actually added it up.
  const db = firestoreWithClaimedJob();
  seedProduct(db, "product-01", 7, {opening: false});
  db.seed(`tenants/${TENANT}/products/product-01/stock_movements/mv_000`, {
    tenantId: TENANT,
    productId: "product-01",
    sourceType: "product_created",
    quantityDelta: 10,
    recordedAt: Timestamp.fromMillis(SETTLED.toMillis() - 60 * 1000),
  });
  db.seed(`tenants/${TENANT}/products/product-01/stock_movements/mv_001`, {
    tenantId: TENANT,
    productId: "product-01",
    sourceType: "sale",
    quantityDelta: -3,
    recordedAt: SETTLED,
  });
  db.clearWrites();

  assert.deepEqual(
    await processStockPage(db.asFirestore(), claimedJob({phase: "stock"})),
    {processed: 1, varianceCount: 0, hasMore: false, productCursor: "product-01"}
  );

  const state = stored(db, `tenants/${TENANT}/stock_reconciliation_state/product-01`);
  assert.equal(state.status, "matched");
  assert.equal(state.expectedQuantity, 7);
  assert.equal(state.lastVariance, 0);
  // The cursor sits at the end of the ledger it read, so the next run continues
  // from there rather than replaying the whole history again.
  assert.equal(state.lastMovementId, "mv_001");
});

test("a movement backlog resumes from its cursor rather than re-reading the ledger", async () => {
  // The ledger page is two hundred movements wide. A product with more than that
  // to catch up on is left pending, and the next page has to continue from the
  // movement the last one stopped at: re-reading from the beginning would apply
  // every movement twice and report a variance of two hundred.
  const db = firestoreWithClaimedJob();
  const job = claimedJob({phase: "stock"});
  for (const productId of ["product-01", "product-02", "product-03"]) {
    // product-02 carries its own state and its own two hundred and one
    // movements, so it gets no opening balance: this test is about where the
    // second page resumes, and an extra movement would only move the arithmetic.
    seedProduct(db, productId, productId === "product-02" ? 299 : 10, {
      opening: productId !== "product-02",
    });
  }
  db.seed(`tenants/${TENANT}/stock_reconciliation_state/product-02`, {
    tenantId: TENANT,
    productId: "product-02",
    expectedQuantity: 500,
    observedQuantity: 500,
    status: "matched",
    lastVerificationJobId: "rj_a_previous_run",
    lastVerificationGeneration: 1,
    lastVerificationCompleted: true,
    activeVerificationJobId: "rj_a_previous_run",
    activeVerificationGeneration: 1,
  });
  for (let index = 1; index <= 201; index += 1) {
    db.seed(
      `tenants/${TENANT}/products/product-02/stock_movements/mv_${`${index}`.padStart(3, "0")}`,
      {
        tenantId: TENANT,
        productId: "product-02",
        quantityDelta: -1,
        recordedAt: Timestamp.fromMillis(SETTLED.toMillis() + index * 1000),
      }
    );
  }
  db.clearWrites();

  const first = await processStockPage(db.asFirestore(), job);

  assert.deepEqual(first, {
    processed: 1,
    varianceCount: 0,
    hasMore: true,
    // The cursor names the last product that *finished*, so a retry re-reads the
    // pending one and no completed product is verified twice.
    productCursor: "product-01",
    pendingProductId: "product-02",
    // Nothing else. This result once carried a `retryDelayMilliseconds` that no
    // branch ever set, and this is the only page shape that could have carried
    // one: a backlog has its next two hundred movements already written, so the
    // continuation belongs now. `jobs.test.ts` pins what "now" means on the job
    // document.
  });
  const backlog = stored(db, `tenants/${TENANT}/stock_reconciliation_state/product-02`);
  assert.equal(backlog.status, "movement_backlog");
  assert.equal(backlog.expectedQuantity, 300);
  assert.equal(backlog.lastVerificationCompleted, false);
  assert.equal(backlog.lastMovementId, "mv_200");
  assert.equal(backlog.activeVerificationJobId, JOB);
  assert.equal(
    stored(db, `tenants/${TENANT}/stock_verifications/${JOB}/products/product-02`).status,
    "movement_backlog"
  );
  // The page stopped at the pending product. Nothing beyond it was looked at.
  assert.deepEqual(
    db.ids(`tenants/${TENANT}/stock_reconciliation_state`),
    ["product-01", "product-02"]
  );

  const resumed = await processStockPage(db.asFirestore(), {
    ...job,
    productCursor: first.productCursor,
    pendingProductId: first.pendingProductId,
  });

  assert.deepEqual(resumed, {
    processed: 1,
    varianceCount: 0,
    // The pending branch never claims the page is finished: the products after
    // the one it resumed have still not been read.
    hasMore: true,
    productCursor: "product-02",
  });
  const settled = stored(db, `tenants/${TENANT}/stock_reconciliation_state/product-02`);
  assert.equal(settled.expectedQuantity, 299);
  assert.equal(settled.lastMovementId, "mv_201");
  assert.equal(settled.lastVerificationCompleted, true);
  // Observed minus expected, and the whole point of the cursor. A pass that
  // re-read the ledger from the start would report -200 here.
  assert.equal(settled.lastVariance, 0);
  assert.equal(settled.status, "matched");
  assert.equal(settled.lastVerificationHadVariance, false);
  assert.deepEqual(db.ids(`tenants/${TENANT}/reconciliation_anomalies`), []);

  assert.deepEqual(
    await processStockPage(db.asFirestore(), {...job, productCursor: "product-02"}),
    {processed: 1, varianceCount: 0, hasMore: false, productCursor: "product-03"}
  );
});

test("a lease lost mid-page keeps the products already verified and reads no more", async () => {
  const db = firestoreWithClaimedJob();
  for (const productId of ["product-01", "product-02", "product-03"]) {
    seedProduct(db, productId, 10);
  }
  db.clearWrites();
  // Another worker claims the job after the first product has committed. Every
  // later transaction re-reads the lease, so the page must stop there.
  aroundTransaction(db, 1, "after", () => {
    db.seed(jobPath(), {...stored(db, jobPath()), leaseToken: "lease-token-2"});
  });

  await assertLeaseRefused(
    processStockPage(db.asFirestore(), claimedJob({phase: "stock"}))
  );

  // The verified product keeps its verification: this phase mutates no stock and
  // re-verifying it would be work, not correctness.
  assert.deepEqual(
    db.ids(`tenants/${TENANT}/stock_reconciliation_state`),
    ["product-01"]
  );
  assert.deepEqual(
    db.ids(`tenants/${TENANT}/stock_verifications/${JOB}/products`),
    ["product-01"]
  );
});

test("a product deleted between two pages does not stall the phase", async () => {
  // Reachable only through `pendingProductId`, because the page itself lists the
  // products it processes. A pending product an owner deleted meanwhile has to be
  // counted and left behind, or the job asks for it forever.
  const db = firestoreWithClaimedJob();
  seedProduct(db, "product-02", 10);
  db.clearWrites();

  assert.deepEqual(
    await processStockPage(db.asFirestore(), claimedJob({
      phase: "stock",
      productCursor: "product-01",
      pendingProductId: "product-gone",
    })),
    {processed: 1, varianceCount: 0, hasMore: true, productCursor: "product-gone"}
  );
  assert.deepEqual(db.writes, []);
});

test("a product this job already finished is counted again but not verified again", async () => {
  // A task queue retries a page, not the product it stopped at, so a second
  // attempt meets products this job's own generation has already settled. The
  // carried state is what says so. Re-verifying would write a second verification
  // of one comparison - and if anything moved in between, one that disagrees with
  // the first while both name the same job.
  const settled = {
    tenantId: TENANT,
    productId: "product-01",
    expectedQuantity: 7,
    observedQuantity: 10,
    status: "variance",
    lastVerificationJobId: JOB,
    lastVerificationGeneration: GENERATION,
    lastVerificationCompleted: true,
    lastVerificationHadVariance: true,
  };
  const statePath = `tenants/${TENANT}/stock_reconciliation_state/product-01`;

  const db = firestoreWithClaimedJob();
  // No opening balance: the carried state's expectation of seven already stands
  // for everything the ledger would have said, and this test is about the guard
  // that stops a settled product being verified twice, not about arithmetic.
  seedProduct(db, "product-01", 10, {opening: false});
  db.seed(statePath, settled);
  db.clearWrites();

  assert.deepEqual(
    await processStockPage(db.asFirestore(), claimedJob({phase: "stock"})),
    {processed: 1, varianceCount: 1, hasMore: false, productCursor: "product-01"}
  );
  // The difference is re-counted from what the earlier attempt concluded, because
  // dropping it would leave the job's own `stockVarianceCount` short of the
  // records it wrote - and nothing at all is written a second time.
  assert.deepEqual(db.writes, []);

  // The guard names this job at this generation and nothing wider. A rerun bumps
  // the generation, and the same product is compared again from the expectation
  // the earlier pass carried. That is also the only route that reads a ledger from
  // the beginning: a valid state with no movement cursor has no position to
  // resume from.
  const rerun = firestoreWithClaimedJob(claimedJob({generation: GENERATION + 1}));
  seedProduct(rerun, "product-01", 10, {opening: false});
  rerun.seed(statePath, settled);
  rerun.clearWrites();

  assert.deepEqual(
    await processStockPage(
      rerun.asFirestore(),
      claimedJob({phase: "stock", generation: GENERATION + 1})
    ),
    {processed: 1, varianceCount: 1, hasMore: false, productCursor: "product-01"}
  );
  const compared = stored(rerun, statePath);
  assert.equal(compared.status, "variance");
  assert.equal(compared.expectedQuantity, 7);
  assert.equal(compared.lastVariance, 3);
  assert.equal(compared.lastVerificationGeneration, GENERATION + 1);
  assert.equal(
    stored(
      rerun,
      `tenants/${TENANT}/reconciliation_anomalies/stock_${digest(["product-01", JOB])}`
    ).anomalyType,
    // Ten held against seven the ledger accounts for: the books are over.
    "stock_over_ledger"
  );
});

test("a product written moments ago is deferred rather than compared", async () => {
  // The trap every fixture in this file is settled to avoid, pinned where pinning
  // it is cheap. A sale decrements the product before its trigger files the
  // movement, so a product touched inside the last five minutes is declined
  // rather than read as three units short. An integration fixture seeded at `now`
  // once left a whole stock test asserting nothing at all.
  const db = firestoreWithClaimedJob();
  const writtenAt = Timestamp.fromMillis(Date.now() - 60 * 1000);
  db.seed(`tenants/${TENANT}/products/product-01`, {
    tenantId: TENANT,
    name: "product-01",
    quantity: 10,
    updatedAt: writtenAt,
  });
  db.seed(`tenants/${TENANT}/products/product-01/stock_movements/mv_001`, {
    tenantId: TENANT,
    productId: "product-01",
    quantityDelta: -3,
    recordedAt: SETTLED,
  });
  db.clearWrites();

  // Counted and stepped past. A deferred product that held the cursor would stall
  // the phase on every run until the window closed.
  assert.deepEqual(
    await processStockPage(db.asFirestore(), claimedJob({phase: "stock"})),
    {processed: 1, varianceCount: 0, hasMore: false, productCursor: "product-01"}
  );

  const verification = stored(
    db,
    `tenants/${TENANT}/stock_verifications/${JOB}/products/product-01`
  );
  assert.equal(verification.status, "recent_write_deferred");
  assert.equal(verification.mutatesStock, false);
  // The instant the comparison becomes safe is named rather than left to be
  // inferred from the product's own `updatedAt`.
  assert.ok(verification.safeAfter instanceof Timestamp);
  assert.equal(verification.safeAfter.toMillis(), writtenAt.toMillis() + 5 * 60 * 1000);
  // Nothing was concluded, so nothing is carried: no expectation for the next run
  // to measure against, no difference, and the movement above was never read.
  assert.deepEqual(db.ids(`tenants/${TENANT}/stock_reconciliation_state`), []);
  assert.deepEqual(db.ids(`tenants/${TENANT}/reconciliation_anomalies`), []);
});

test("carried state that names no ledger position is re-baselined and reported", async () => {
  // The one stock status nothing has ever covered, and the one that forgives a
  // difference: a state that cannot say where in the ledger it stopped cannot be
  // resumed from, so the run takes the product's own quantity as the new
  // expectation. Replaying `mv_001` would have made that expectation 7 and
  // reported a variance of three. The point of this test is that it is not
  // replayed, and that the run says the chain does not join up rather than
  // reporting agreement it did not establish.
  const broken: Record<string, DocumentData> = {
    "no expectation at all": {lastMovementAt: SETTLED, lastMovementId: "mv_001"},
    "an expectation that is not a whole number": {
      expectedQuantity: 7.5,
      lastMovementAt: SETTLED,
      lastMovementId: "mv_001",
    },
    "an instant with no movement named": {expectedQuantity: 7, lastMovementAt: SETTLED},
    "a movement named with no instant": {expectedQuantity: 7, lastMovementId: "mv_001"},
    "an instant that is not one": {
      expectedQuantity: 7,
      lastMovementAt: "yesterday",
      lastMovementId: "mv_001",
    },
  };

  for (const [reason, state] of Object.entries(broken)) {
    const db = firestoreWithClaimedJob();
    seedProduct(db, "product-01", 10);
    db.seed(`tenants/${TENANT}/products/product-01/stock_movements/mv_001`, {
      tenantId: TENANT,
      productId: "product-01",
      quantityDelta: -3,
      recordedAt: SETTLED,
    });
    db.seed(`tenants/${TENANT}/stock_reconciliation_state/product-01`, {
      tenantId: TENANT,
      productId: "product-01",
      ...state,
    });
    db.clearWrites();

    assert.deepEqual(
      await processStockPage(db.asFirestore(), claimedJob({phase: "stock"})),
      {processed: 1, varianceCount: 1, hasMore: false, productCursor: "product-01"},
      reason
    );

    const carried = stored(db, `tenants/${TENANT}/stock_reconciliation_state/product-01`);
    assert.equal(carried.status, "baseline_reestablished_invalid_state", reason);
    // **Rebuilt from the ledger, and the rebuild finds the discrepancy.** State
    // that cannot be trusted used to be replaced by trusting the product's own
    // figure, which made the comparison agree with itself by construction and
    // report a variance of zero - so a corrupt state laundered whatever it was
    // hiding into an accepted number.
    //
    // The ledger says ten opened and three left, so seven is accounted for. The
    // product holds ten. That is a variance of three, and it is a true one:
    // three units are there that nothing explains.
    assert.equal(carried.expectedQuantity, 7, reason);
    assert.equal(carried.lastVariance, 3, reason);
    assert.equal(carried.checkpointChainValid, false, reason);
    // It resumed through the ledger rather than past it, so the cursor sits on
    // the last movement it actually read.
    assert.equal(carried.lastMovementId, "mv_001", reason);

    const anomaly = stored(
      db,
      `tenants/${TENANT}/reconciliation_anomalies/stock_${digest(["product-01", JOB])}`
    );
    // **The chain is what is reported, even though the quantity disagrees too.**
    // State that cannot be trusted is the more fundamental thing wrong with this
    // product, and it is the one to put in front of somebody: a variance read off
    // a rebuilt expectation is only as good as the rebuild. The disagreement is
    // still recorded on the anomaly rather than flattened to zero, so whoever
    // acts on it can see both facts at once.
    assert.equal(anomaly.anomalyType, "checkpoint_chain_invalid", reason);
    assert.equal(anomaly.variance, 3, reason);
  }
});

// ---------------------------------------------------------------------------
// processShiftPage
// ---------------------------------------------------------------------------

function seedExpectation(
  db: FakeFirestore,
  expectationId: string,
  fields: DocumentData
): void {
  db.seed(`tenants/${TENANT}/shift_expectations/${expectationId}`, {
    tenantId: TENANT,
    businessDate: LOCAL_DATE,
    generation: "generation-one",
    needsVerification: true,
    ...fields,
  });
}

function seedClosedShift(
  db: FakeFirestore,
  shiftId: string,
  totalSales: number,
  transactionCount: number,
  extra: DocumentData = {}
): void {
  db.seed(`tenants/${TENANT}/shifts/${shiftId}`, {
    tenantId: TENANT,
    shiftId,
    status: "closed",
    businessDate: LOCAL_DATE,
    totalSales,
    transactionCount,
    ...extra,
  });
}

/** The four expected-tender fields, which an expectation carries all or none of. */
function tenderExpectation(
  cashMinor: number,
  mpesaMinor = 0,
  cardMinor = 0,
  unattributedMinor = 0
): DocumentData {
  return {
    expectedCashMinor: cashMinor,
    expectedMpesaMinor: mpesaMinor,
    expectedCardMinor: cardMinor,
    expectedUnattributedMinor: unattributedMinor,
    tenderExpectationVersion: 1,
  };
}

/** A close made after the rollout, so an absent declaration is itself a fault. */
function declaredAt(millis: number): DocumentData {
  return {endTime: Timestamp.fromMillis(millis)};
}

const AFTER_CUTOFF = TENDER_DECLARATION_REQUIRED_FROM + 86_400_000;
const BEFORE_CUTOFF = TENDER_DECLARATION_REQUIRED_FROM - 86_400_000;

function tenderAnomalyPath(shiftId: string): string {
  return `tenants/${TENANT}/reconciliation_anomalies/${shiftTenderAnomalyId(shiftId)}`;
}

function verificationPath(expectationId: string): string {
  return `tenants/${TENANT}/shift_verifications/${JOB}_${digest([expectationId])}`;
}

test("a shift phase with nothing awaiting verification writes nothing", async () => {
  const db = firestoreWithClaimedJob();
  // An expectation already settled is not awaiting anything, so it must not be
  // re-verified: the query is what enforces that and this is the assertion of it.
  seedExpectation(db, "exp_settled", {
    shiftId: "shift-01",
    sales: 10,
    transactions: 1,
    needsVerification: false,
  });
  db.clearWrites();

  assert.deepEqual(
    await processShiftPage(db.asFirestore(), claimedJob({phase: "shifts"})),
    {processed: 0, varianceCount: 0, tenderVarianceCount: 0, hasMore: false}
  );
  assert.deepEqual(db.writes, []);
});

test("the shift page is bounded at fifty expectations and reports the remainder", async () => {
  const db = firestoreWithClaimedJob();
  const ids = Array.from({length: 52}, (_, index) => `exp_${`${index + 1}`.padStart(3, "0")}`);
  ids.forEach((expectationId, index) => {
    const shiftId = `shift-${`${index + 1}`.padStart(3, "0")}`;
    seedExpectation(db, expectationId, {shiftId, sales: 10, transactions: 1});
    seedClosedShift(db, shiftId, 10, 1);
  });
  db.clearWrites();
  const job = claimedJob({phase: "shifts"});

  assert.deepEqual(
    await processShiftPage(db.asFirestore(), job),
    {processed: 50, varianceCount: 0, tenderVarianceCount: 0, hasMore: true}
  );
  assert.equal(
    stored(db, `tenants/${TENANT}/shift_expectations/${ids[49]}`).needsVerification,
    false
  );
  assert.equal(
    stored(db, `tenants/${TENANT}/shift_expectations/${ids[50]}`).needsVerification,
    true
  );

  assert.deepEqual(
    await processShiftPage(db.asFirestore(), job),
    {processed: 2, varianceCount: 0, tenderVarianceCount: 0, hasMore: false}
  );
});

test("a variance and an unreadable shift are both counted and both recorded", async () => {
  const db = firestoreWithClaimedJob();
  seedExpectation(db, "exp_matched", {shiftId: "shift-01", sales: 10, transactions: 1});
  seedClosedShift(db, "shift-01", 10, 1);
  seedExpectation(db, "exp_variance", {shiftId: "shift-02", sales: 10, transactions: 2});
  seedClosedShift(db, "shift-02", 7.5, 1);
  // No shift document at all: nothing was compared, so there is no variance to
  // report and the record says exactly that instead of inventing a figure.
  seedExpectation(db, "exp_missing", {shiftId: "shift-03", sales: 10, transactions: 1});
  db.clearWrites();

  assert.deepEqual(
    await processShiftPage(db.asFirestore(), claimedJob({phase: "shifts"})),
    {processed: 3, varianceCount: 2, tenderVarianceCount: 0, hasMore: false}
  );

  assert.equal(stored(db, verificationPath("exp_matched")).status, "matched");
  const variance = stored(db, verificationPath("exp_variance"));
  assert.equal(variance.status, "variance");
  assert.equal(variance.salesVarianceMinor, -250);
  assert.equal(variance.transactionVariance, -1);
  assert.equal(variance.mutatesShift, false);
  const missing = stored(db, verificationPath("exp_missing"));
  assert.equal(missing.status, "invalid_or_missing_shift");
  assert.equal(missing.observedSales, null);
  assert.equal(missing.salesVarianceMinor, null);

  assert.deepEqual(
    db.ids(`tenants/${TENANT}/reconciliation_anomalies`),
    [
      shiftAnomalyId("shift-02", "generation-one"),
      shiftAnomalyId("shift-03", "generation-one"),
    ].sort()
  );
  assert.equal(
    stored(
      db,
      `tenants/${TENANT}/reconciliation_anomalies/${shiftAnomalyId("shift-02", "generation-one")}`
    ).anomalyType,
    "shift_variance"
  );
  assert.equal(
    stored(
      db,
      `tenants/${TENANT}/reconciliation_anomalies/${shiftAnomalyId("shift-03", "generation-one")}`
    ).anomalyType,
    "invalid_or_missing_shift"
  );
  assert.equal(
    stored(db, `tenants/${TENANT}/shift_expectations/exp_matched`).verificationStatus,
    "matched"
  );
});


// ---------------------------------------------------------------------------
// The blind tender declaration
// ---------------------------------------------------------------------------

test("a declaration that disagrees with the sales is recorded once, with both sides", async () => {
  const db = firestoreWithClaimedJob();
  seedExpectation(db, "exp_tender", {
    shiftId: "shift-01",
    sales: 300,
    transactions: 3,
    ...tenderExpectation(25000, 5000, 0),
  });
  // The drawer is 50.00 short on cash and 9.00 over on card. Sales and count
  // agree, so this is a difference the sales check could never have found.
  seedClosedShift(db, "shift-01", 300, 3, {
    ...declaredAt(AFTER_CUTOFF),
    declaredCashMinor: 20000,
    declaredMpesaMinor: 5000,
    declaredCardMinor: 900,
  });
  db.clearWrites();

  assert.deepEqual(
    await processShiftPage(db.asFirestore(), claimedJob({phase: "shifts"})),
    {processed: 1, varianceCount: 0, tenderVarianceCount: 1, hasMore: false}
  );

  const verification = stored(db, verificationPath("exp_tender"));
  assert.equal(verification.status, "matched");
  assert.equal(verification.tenderStatus, "variance");

  const anomaly = stored(db, tenderAnomalyPath("shift-01"));
  assert.equal(anomaly.anomalyType, "shift_tender_variance");
  assert.equal(anomaly.cashVarianceMinor, -5000);
  assert.equal(anomaly.mpesaVarianceMinor, 0);
  assert.equal(anomaly.cardVarianceMinor, 900);
  assert.equal(anomaly.resolution, "open");
  assert.equal(anomaly.mutatesShift, false);
  // Which day and whose shift, which this collection could not say before.
  assert.equal(anomaly.businessDate, LOCAL_DATE);
});

test("a miscategorised tender balances out rather than raising a difference", async () => {
  const db = firestoreWithClaimedJob();
  seedExpectation(db, "exp_tender", {
    shiftId: "shift-01",
    sales: 500,
    transactions: 4,
    ...tenderExpectation(25000, 25000, 0),
  });
  // **One sale rung as cash that was actually M-Pesa.** Cash is 250.00 over and
  // M-Pesa 250.00 short, the drawer holds exactly what it should, and nothing
  // is missing. The sale's tender is whatever was tapped at payment and is
  // never edited afterwards; the cashier counting the drawer is the better
  // witness to the split, so their answer is taken rather than marked.
  seedClosedShift(db, "shift-01", 500, 4, {
    ...declaredAt(AFTER_CUTOFF),
    declaredCashMinor: 50000,
    declaredMpesaMinor: 0,
    declaredCardMinor: 0,
  });
  db.clearWrites();

  assert.deepEqual(
    await processShiftPage(db.asFirestore(), claimedJob({phase: "shifts"})),
    {processed: 1, varianceCount: 0, tenderVarianceCount: 0, hasMore: false}
  );

  const verification = stored(db, verificationPath("exp_tender"));
  assert.equal(verification.tenderStatus, "matched");
  // Recorded even though nothing was raised: the split is what reporting reads.
  assert.equal(verification.cashVarianceMinor, 25000);
  assert.equal(verification.mpesaVarianceMinor, -25000);
  assert.equal(verification.totalVarianceMinor, 0);
  assert.deepEqual(db.ids(`tenants/${TENANT}/reconciliation_anomalies`), []);
});

test("a floated drawer counts its change back rather than declaring a surplus", async () => {
  const db = firestoreWithClaimedJob();
  seedExpectation(db, "exp_tender", {
    shiftId: "shift-01",
    sales: 500,
    transactions: 4,
    ...tenderExpectation(50000, 0, 0),
  });
  // **The till was given 2,000.00 in change before it sold anything.** At close
  // the cashier counts the whole drawer - 500.00 of sales sitting on top of the
  // float - and declares 2,500.00. Nothing is missing and nothing is over.
  // Without the float term this shift reported a 2,000.00 surplus every day it
  // traded, against a drawer that balanced to the shilling.
  seedClosedShift(db, "shift-01", 500, 4, {
    ...declaredAt(AFTER_CUTOFF),
    openingFloatMinor: 200000,
    declaredCashMinor: 250000,
    declaredMpesaMinor: 0,
    declaredCardMinor: 0,
  });
  db.clearWrites();

  assert.deepEqual(
    await processShiftPage(db.asFirestore(), claimedJob({phase: "shifts"})),
    {processed: 1, varianceCount: 0, tenderVarianceCount: 0, hasMore: false}
  );

  const verification = stored(db, verificationPath("exp_tender"));
  assert.equal(verification.tenderStatus, "matched");
  assert.equal(verification.totalVarianceMinor, 0);
  assert.equal(verification.cashVarianceMinor, 0);
  // **The float is recorded beside the figures, not folded into them.**
  // `expectedCashMinor` stays what the shift sold for cash, because that is
  // what every report of the split reads; the drawer figure is the one the
  // count was marked against, and both are kept so the answer can be explained.
  assert.equal(verification.openingFloatMinor, 200000);
  assert.equal(verification.expectedCashMinor, 50000);
  assert.equal(verification.expectedDrawerCashMinor, 250000);
});

test("a float does not hide money missing from the drawer it floated", async () => {
  const db = firestoreWithClaimedJob();
  seedExpectation(db, "exp_tender", {
    shiftId: "shift-01",
    sales: 500,
    transactions: 4,
    ...tenderExpectation(50000, 0, 0),
  });
  // The same float, and 100.00 of the drawer genuinely absent.
  seedClosedShift(db, "shift-01", 500, 4, {
    ...declaredAt(AFTER_CUTOFF),
    openingFloatMinor: 200000,
    declaredCashMinor: 240000,
    declaredMpesaMinor: 0,
    declaredCardMinor: 0,
  });
  db.clearWrites();

  assert.deepEqual(
    await processShiftPage(db.asFirestore(), claimedJob({phase: "shifts"})),
    {processed: 1, varianceCount: 0, tenderVarianceCount: 1, hasMore: false}
  );

  const anomaly = stored(db, tenderAnomalyPath("shift-01"));
  assert.equal(anomaly.anomalyType, "shift_tender_variance");
  assert.equal(anomaly.totalVarianceMinor, -10000);
});

test("a negative float is not believed, because it would lower the count", async () => {
  const db = firestoreWithClaimedJob();
  seedExpectation(db, "exp_tender", {
    shiftId: "shift-01",
    sales: 500,
    transactions: 4,
    ...tenderExpectation(50000, 0, 0),
  });
  // Rules refuse this on write. Were it ever to reach the server it would
  // reduce the cash the drawer has to account for, which is the one direction
  // a dishonest figure is worth writing in - so it reads as no float, and the
  // 100.00 short stays short.
  seedClosedShift(db, "shift-01", 500, 4, {
    ...declaredAt(AFTER_CUTOFF),
    openingFloatMinor: -10000,
    declaredCashMinor: 40000,
    declaredMpesaMinor: 0,
    declaredCardMinor: 0,
  });
  db.clearWrites();

  assert.deepEqual(
    await processShiftPage(db.asFirestore(), claimedJob({phase: "shifts"})),
    {processed: 1, varianceCount: 0, tenderVarianceCount: 1, hasMore: false}
  );

  const anomaly = stored(db, tenderAnomalyPath("shift-01"));
  assert.equal(anomaly.totalVarianceMinor, -10000);
  // Recorded as no float at all rather than as a zero, which is what keeps a
  // shop that never floats a till from having every dismissed difference
  // reopened by this change - see the acknowledgement test below.
  assert.equal(anomaly.openingFloatMinor, undefined);
});

test("a total that disagrees still raises, whatever the split does", async () => {
  const db = firestoreWithClaimedJob();
  seedExpectation(db, "exp_tender", {
    shiftId: "shift-01",
    sales: 500,
    transactions: 4,
    ...tenderExpectation(25000, 25000, 0),
  });
  // The same miscategorisation, and 100.00 of the drawer genuinely absent.
  seedClosedShift(db, "shift-01", 500, 4, {
    ...declaredAt(AFTER_CUTOFF),
    declaredCashMinor: 40000,
    declaredMpesaMinor: 0,
    declaredCardMinor: 0,
  });
  db.clearWrites();

  assert.deepEqual(
    await processShiftPage(db.asFirestore(), claimedJob({phase: "shifts"})),
    {processed: 1, varianceCount: 0, tenderVarianceCount: 1, hasMore: false}
  );

  const anomaly = stored(db, tenderAnomalyPath("shift-01"));
  assert.equal(anomaly.anomalyType, "shift_tender_variance");
  assert.equal(anomaly.totalVarianceMinor, -10000);
});

test("a declaration that agrees deletes a difference that no longer holds", async () => {
  const db = firestoreWithClaimedJob();
  db.seed(tenderAnomalyPath("shift-01"), {
    tenantId: TENANT,
    shiftId: "shift-01",
    anomalyType: "shift_tender_variance",
    cashVarianceMinor: -5000,
  });
  seedExpectation(db, "exp_tender", {
    shiftId: "shift-01",
    sales: 200,
    transactions: 2,
    ...tenderExpectation(20000),
  });
  seedClosedShift(db, "shift-01", 200, 2, {
    ...declaredAt(AFTER_CUTOFF),
    declaredCashMinor: 20000,
    declaredMpesaMinor: 0,
    declaredCardMinor: 0,
  });
  db.clearWrites();

  // **Self-healing.** A shift whose late sales arrive and reconcile the
  // difference away stops being one, and nobody should have to dismiss a record
  // that is no longer true.
  await processShiftPage(db.asFirestore(), claimedJob({phase: "shifts"}));

  assert.equal(stored(db, verificationPath("exp_tender")).tenderStatus, "matched");
  assert.deepEqual(db.ids(`tenants/${TENANT}/reconciliation_anomalies`), []);
});

test("an acknowledged difference survives a re-verify that changes nothing", async () => {
  const db = firestoreWithClaimedJob();
  db.seed(tenderAnomalyPath("shift-01"), {
    tenantId: TENANT,
    shiftId: "shift-01",
    anomalyType: "shift_tender_variance",
    declaredCashMinor: 20000,
    declaredMpesaMinor: 0,
    declaredCardMinor: 0,
    expectedCashMinor: 25000,
    expectedMpesaMinor: 0,
    expectedCardMinor: 0,
    expectedUnattributedMinor: 0,
    cashVarianceMinor: -5000,
    mpesaVarianceMinor: 0,
    cardVarianceMinor: 0,
    declaredTotalMinor: 20000,
    expectedTotalMinor: 25000,
    totalVarianceMinor: -5000,
    resolution: "acknowledged",
  });
  seedExpectation(db, "exp_tender", {
    shiftId: "shift-01",
    sales: 250,
    transactions: 2,
    ...tenderExpectation(25000),
  });
  seedClosedShift(db, "shift-01", 250, 2, {
    ...declaredAt(AFTER_CUTOFF),
    declaredCashMinor: 20000,
    declaredMpesaMinor: 0,
    declaredCardMinor: 0,
  });
  db.clearWrites();

  await processShiftPage(db.asFirestore(), claimedJob({phase: "shifts"}));

  // An owner accepted this difference; the nightly sweep must not reopen it
  // just for running again. A figure that actually moves is a new fact and does.
  assert.equal(stored(db, tenderAnomalyPath("shift-01")).resolution, "acknowledged");
});

test("adding the opening float does not reopen differences already accepted", async () => {
  // **The migration guarantee, pinned.** This anomaly was written before the
  // float existed and carries none of its fields. A shop that does not float a
  // till must read exactly as it did before the field shipped, because the
  // comparison reopens a dismissed difference whose figures move - and an owner
  // who comes in to find every difference they ever settled waiting for them
  // again will stop settling them.
  const db = firestoreWithClaimedJob();
  db.seed(tenderAnomalyPath("shift-01"), {
    tenantId: TENANT,
    shiftId: "shift-01",
    anomalyType: "shift_tender_variance",
    declaredCashMinor: 20000,
    declaredMpesaMinor: 0,
    declaredCardMinor: 0,
    expectedCashMinor: 25000,
    expectedMpesaMinor: 0,
    expectedCardMinor: 0,
    expectedUnattributedMinor: 0,
    cashVarianceMinor: -5000,
    mpesaVarianceMinor: 0,
    cardVarianceMinor: 0,
    declaredTotalMinor: 20000,
    expectedTotalMinor: 25000,
    totalVarianceMinor: -5000,
    resolution: "acknowledged",
  });
  seedExpectation(db, "exp_tender", {
    shiftId: "shift-01",
    sales: 250,
    transactions: 2,
    ...tenderExpectation(25000),
  });
  // No `openingFloatMinor` anywhere on the shift, which is every shift closed
  // before this release and every shift of every shop that keeps no change.
  seedClosedShift(db, "shift-01", 250, 2, {
    ...declaredAt(AFTER_CUTOFF),
    declaredCashMinor: 20000,
    declaredMpesaMinor: 0,
    declaredCardMinor: 0,
  });
  db.clearWrites();

  await processShiftPage(db.asFirestore(), claimedJob({phase: "shifts"}));

  const anomaly = stored(db, tenderAnomalyPath("shift-01"));
  assert.equal(anomaly.resolution, "acknowledged");
  assert.equal(anomaly.totalVarianceMinor, -5000);
});

test("a difference whose figures move is reopened", async () => {
  const db = firestoreWithClaimedJob();
  db.seed(tenderAnomalyPath("shift-01"), {
    tenantId: TENANT,
    shiftId: "shift-01",
    anomalyType: "shift_tender_variance",
    cashVarianceMinor: -5000,
    resolution: "acknowledged",
  });
  seedExpectation(db, "exp_tender", {
    shiftId: "shift-01",
    sales: 400,
    transactions: 3,
    ...tenderExpectation(40000),
  });
  seedClosedShift(db, "shift-01", 400, 3, {
    ...declaredAt(AFTER_CUTOFF),
    declaredCashMinor: 20000,
    declaredMpesaMinor: 0,
    declaredCardMinor: 0,
  });
  db.clearWrites();

  await processShiftPage(db.asFirestore(), claimedJob({phase: "shifts"}));

  assert.equal(stored(db, tenderAnomalyPath("shift-01")).resolution, "open");
  assert.equal(stored(db, tenderAnomalyPath("shift-01")).cashVarianceMinor, -20000);
});

test("a shift closed before the rollout is never asked for a declaration", async () => {
  const db = firestoreWithClaimedJob();
  seedExpectation(db, "exp_legacy", {
    shiftId: "shift-01",
    sales: 100,
    transactions: 1,
    ...tenderExpectation(10000),
  });
  seedClosedShift(db, "shift-01", 100, 1, declaredAt(BEFORE_CUTOFF));
  db.clearWrites();

  // **The migration guarantee, proved rather than argued.** The build that
  // closed this shift had nowhere to type a declaration, so its absence says
  // nothing about the shop and must raise nothing.
  assert.deepEqual(
    await processShiftPage(db.asFirestore(), claimedJob({phase: "shifts"})),
    {processed: 1, varianceCount: 0, tenderVarianceCount: 0, hasMore: false}
  );
  assert.equal(
    stored(db, verificationPath("exp_legacy")).tenderStatus,
    "not_declared_legacy"
  );
  assert.deepEqual(db.ids(`tenants/${TENANT}/reconciliation_anomalies`), []);
});

test("a shift closed after the rollout with no declaration is itself a difference", async () => {
  const db = firestoreWithClaimedJob();
  seedExpectation(db, "exp_missing_declaration", {
    shiftId: "shift-01",
    sales: 100,
    transactions: 1,
    ...tenderExpectation(10000),
  });
  seedClosedShift(db, "shift-01", 100, 1, declaredAt(AFTER_CUTOFF));
  db.clearWrites();

  assert.deepEqual(
    await processShiftPage(db.asFirestore(), claimedJob({phase: "shifts"})),
    {processed: 1, varianceCount: 0, tenderVarianceCount: 1, hasMore: false}
  );

  const anomaly = stored(db, tenderAnomalyPath("shift-01"));
  assert.equal(anomaly.anomalyType, "missing_tender_declaration");
  // Nothing was declared, so there is nothing to state. Figures here would be a
  // comparison this writer could not have made.
  assert.equal(anomaly.declaredCashMinor, undefined);
  assert.equal(anomaly.cashVarianceMinor, undefined);
  assert.equal(anomaly.expectedCashMinor, 10000);
});

test("an expectation written before the split compares nothing", async () => {
  const db = firestoreWithClaimedJob();
  seedExpectation(db, "exp_pre_deploy", {shiftId: "shift-01", sales: 100, transactions: 1});
  seedClosedShift(db, "shift-01", 100, 1, {
    ...declaredAt(AFTER_CUTOFF),
    declaredCashMinor: 1,
    declaredMpesaMinor: 0,
    declaredCardMinor: 0,
  });
  db.clearWrites();

  // A day is only ever compared once it has been regenerated, and regeneration
  // always produces the expected figures. Nothing historical is retro-flagged.
  await processShiftPage(db.asFirestore(), claimedJob({phase: "shifts"}));

  assert.equal(
    stored(db, verificationPath("exp_pre_deploy")).tenderStatus,
    "no_expectation"
  );
  assert.deepEqual(db.ids(`tenants/${TENANT}/reconciliation_anomalies`), []);
});

test("a recovery close still has its drawer marked", async () => {
  const db = firestoreWithClaimedJob();
  seedExpectation(db, "exp_recovery", {
    shiftId: "shift-01",
    sales: 100,
    transactions: 1,
    ...tenderExpectation(10000),
  });
  // Closed by a device holding none of the shift's sales: the zero summary
  // describes what that device could prove, not what the shift took.
  seedClosedShift(db, "shift-01", 0, 0, {
    ...declaredAt(AFTER_CUTOFF),
    closedWithoutEvidence: true,
    declaredCashMinor: 9900,
    declaredMpesaMinor: 0,
    declaredCardMinor: 0,
  });
  db.clearWrites();

  await processShiftPage(db.asFirestore(), claimedJob({phase: "shifts"}));

  // **The two halves answer separately, because they know different things.**
  //
  // *The sales half cannot answer.* The zero summary says the closing device
  // could prove nothing, so there is no observation to compare - and reading it
  // as one reported a 100.00 shift as a 100.00 shortfall, every night, against
  // a shift nobody could have closed better.
  const verification = stored(db, verificationPath("exp_recovery"));
  assert.equal(verification.status, "invalid_or_missing_shift");
  assert.equal(verification.observedSales, null);
  assert.equal(verification.salesVariance, null);

  // *The cash half can, and used to refuse to.* The cashier counted the drawer
  // and it is 1.00 light. That figure was being thrown away because the same
  // flag was read as covering both halves - so a till that came up short after
  // a reinstall raised nothing at all, and the only record left said the sales
  // total could not be checked. A reinstall is not a way to quieten a short
  // drawer.
  assert.equal(verification.tenderStatus, "variance");
  assert.equal(verification.totalVarianceMinor, -100);
  assert.equal(verification.cashVarianceMinor, -100);

  const anomalyTypes = db
    .ids(`tenants/${TENANT}/reconciliation_anomalies`)
    .map((id: string) =>
      stored(db, `tenants/${TENANT}/reconciliation_anomalies/${id}`).anomalyType
    )
    .sort();
  assert.deepEqual(anomalyTypes, [
    "invalid_or_missing_shift",
    "shift_tender_variance",
  ]);
});

test("a recovery close whose drawer balances raises no difference for it", async () => {
  const db = firestoreWithClaimedJob();
  seedExpectation(db, "exp_recovery", {
    shiftId: "shift-01",
    sales: 100,
    transactions: 1,
    ...tenderExpectation(10000),
  });
  // The ordinary case after a reinstall: the cashier still has the drawer and
  // it is right. The sales figure remains uncheckable, which is honest, but
  // nobody is asked to look into money that is all there.
  seedClosedShift(db, "shift-01", 0, 0, {
    ...declaredAt(AFTER_CUTOFF),
    closedWithoutEvidence: true,
    declaredCashMinor: 10000,
    declaredMpesaMinor: 0,
    declaredCardMinor: 0,
  });
  db.clearWrites();

  await processShiftPage(db.asFirestore(), claimedJob({phase: "shifts"}));

  const verification = stored(db, verificationPath("exp_recovery"));
  assert.equal(verification.status, "invalid_or_missing_shift");
  assert.equal(verification.tenderStatus, "matched");
  assert.equal(verification.totalVarianceMinor, 0);
  const anomalyTypes = db
    .ids(`tenants/${TENANT}/reconciliation_anomalies`)
    .map((id: string) =>
      stored(db, `tenants/${TENANT}/reconciliation_anomalies/${id}`).anomalyType
    );
  assert.deepEqual(anomalyTypes, ["invalid_or_missing_shift"]);
});

test("a recovery close with nothing declared is still only unverifiable", async () => {
  const db = firestoreWithClaimedJob();
  seedExpectation(db, "exp_recovery", {
    shiftId: "shift-01",
    sales: 100,
    transactions: 1,
    ...tenderExpectation(10000),
  });
  // **One drawer counted once.** Where a cashier closes two shifts for one
  // till, the count belongs to whichever shift can carry it and the other
  // declares nothing rather than repeating a figure. The absence must not read
  // as a missing declaration a current build should have recorded.
  seedClosedShift(db, "shift-01", 0, 0, {
    ...declaredAt(AFTER_CUTOFF),
    closedWithoutEvidence: true,
  });
  db.clearWrites();

  assert.deepEqual(
    await processShiftPage(db.asFirestore(), claimedJob({phase: "shifts"})),
    {processed: 1, varianceCount: 1, tenderVarianceCount: 0, hasMore: false}
  );

  const verification = stored(db, verificationPath("exp_recovery"));
  assert.equal(verification.status, "invalid_or_missing_shift");
  assert.equal(verification.tenderStatus, "unverifiable");
  assert.equal(db.ids(`tenants/${TENANT}/reconciliation_anomalies`).length, 1);
});

test("an expectation that does not name a shift is quarantined, not verified", async () => {
  // It cannot address a shift document, so there is nothing to compare it with
  // and no anomaly that could name what went wrong with a shift.
  for (const shiftId of [undefined, "", "with/slash", 7]) {
    const db = firestoreWithClaimedJob();
    seedExpectation(db, "exp_broken", {
      sales: 10,
      transactions: 1,
      ...(shiftId === undefined ? {} : {shiftId}),
    });
    db.clearWrites();

    assert.deepEqual(
      await processShiftPage(db.asFirestore(), claimedJob({phase: "shifts"})),
      {processed: 1, varianceCount: 1, tenderVarianceCount: 0, hasMore: false},
      `${shiftId}`
    );

    const expectation = stored(db, `tenants/${TENANT}/shift_expectations/exp_broken`);
    assert.equal(expectation.needsVerification, false, `${shiftId}`);
    assert.equal(expectation.verificationStatus, "quarantined", `${shiftId}`);
    assert.equal(expectation.lastErrorCode, "invalid_shift_expectation", `${shiftId}`);
    assert.deepEqual(db.ids(`tenants/${TENANT}/shift_verifications`), [], `${shiftId}`);
    assert.deepEqual(db.ids(`tenants/${TENANT}/reconciliation_anomalies`), [], `${shiftId}`);
  }
});

test("an expectation whose generation moved is left alone rather than settled", async () => {
  // The generation is read from the query snapshot and re-read in the
  // transaction. A metrics pass that regenerated the day in between produced a
  // new expectation, and settling the old one would record a verification of
  // figures nothing holds any more.
  const db = firestoreWithClaimedJob();
  const path = `tenants/${TENANT}/shift_expectations/exp_regenerated`;
  seedExpectation(db, "exp_regenerated", {shiftId: "shift-01", sales: 10, transactions: 1});
  seedClosedShift(db, "shift-01", 10, 1);
  db.clearWrites();
  aroundTransaction(db, 1, "before", () => {
    db.seed(path, {...stored(db, path), generation: "generation-two"});
  });

  assert.deepEqual(
    await processShiftPage(db.asFirestore(), claimedJob({phase: "shifts"})),
    {processed: 1, varianceCount: 0, tenderVarianceCount: 0, hasMore: true}
  );

  const expectation = stored(db, path);
  assert.equal(expectation.needsVerification, true);
  assert.equal("verificationStatus" in expectation, false);
  assert.deepEqual(db.ids(`tenants/${TENANT}/shift_verifications`), []);
});
