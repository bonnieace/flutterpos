import assert from "node:assert/strict";
import test from "node:test";
import {DocumentData, Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {FakeFirestore, FakeTransaction} from "../testing/fakeFirestore";
import {ClaimedReconciliationJob} from "./jobs";
import {digest, shiftAnomalyId, shiftExpectationId, trailingIsoDates} from "./model";
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

// ---------------------------------------------------------------------------
// processStockPage
// ---------------------------------------------------------------------------

/** A product settled outside the deferral window, so it is compared rather than deferred. */
function seedProduct(db: FakeFirestore, productId: string, quantity: number): void {
  db.seed(`tenants/${TENANT}/products/${productId}`, {
    tenantId: TENANT,
    name: productId,
    quantity,
    updatedAt: SETTLED,
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
  // A product no run has carried state for is baselined, not compared, so a
  // twenty-five product page reports no difference by construction.
  assert.equal(
    stored(db, `tenants/${TENANT}/stock_reconciliation_state/product-01`).status,
    "baseline_established"
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

test("a movement backlog resumes from its cursor rather than re-reading the ledger", async () => {
  // The ledger page is two hundred movements wide. A product with more than that
  // to catch up on is left pending, and the next page has to continue from the
  // movement the last one stopped at: re-reading from the beginning would apply
  // every movement twice and report a variance of two hundred.
  const db = firestoreWithClaimedJob();
  const job = claimedJob({phase: "stock"});
  for (const productId of ["product-01", "product-02", "product-03"]) {
    seedProduct(db, productId, productId === "product-02" ? 299 : 10);
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
    // Always undefined, and asserted so on purpose. `ProductResult` declares this
    // field, `processStockPage` forwards it, `handlers.ts` passes it into
    // `JobAdvance`, and `advanceReconciliationJob` turns it into `nextAttemptAt` -
    // but nothing in the pipeline ever assigns it a value, so every continuation
    // is scheduled for now. The default is the right one for a backlog, which has
    // more work waiting; whether anything should ever ask for a delay is a
    // question this test pins rather than answers.
    retryDelayMilliseconds: undefined,
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
  seedProduct(db, "product-01", 10);
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
  seedProduct(rerun, "product-01", 10);
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
    "stock_variance"
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
    // The product's own figure became the expectation, so the comparison agrees
    // with itself by construction and the variance is zero.
    assert.equal(carried.expectedQuantity, 10, reason);
    assert.equal(carried.lastVariance, 0, reason);
    assert.equal(carried.checkpointChainValid, false, reason);
    // It resumed past the ledger rather than through it.
    assert.equal(carried.lastMovementId, "mv_001", reason);

    const anomaly = stored(
      db,
      `tenants/${TENANT}/reconciliation_anomalies/stock_${digest(["product-01", JOB])}`
    );
    // Not a quantity disagreement, because nothing disagreed. What is wrong is
    // that the figures could not be trusted, which is the distinction the product
    // stock surface already words differently for this kind.
    assert.equal(anomaly.anomalyType, "checkpoint_chain_invalid", reason);
    assert.equal(anomaly.variance, 0, reason);
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
  transactionCount: number
): void {
  db.seed(`tenants/${TENANT}/shifts/${shiftId}`, {
    tenantId: TENANT,
    shiftId,
    status: "closed",
    businessDate: LOCAL_DATE,
    totalSales,
    transactionCount,
  });
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
    {processed: 0, varianceCount: 0, hasMore: false}
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
    {processed: 50, varianceCount: 0, hasMore: true}
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
    {processed: 2, varianceCount: 0, hasMore: false}
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
    {processed: 3, varianceCount: 2, hasMore: false}
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
      {processed: 1, varianceCount: 1, hasMore: false},
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
    {processed: 1, varianceCount: 0, hasMore: true}
  );

  const expectation = stored(db, path);
  assert.equal(expectation.needsVerification, true);
  assert.equal("verificationStatus" in expectation, false);
  assert.deepEqual(db.ids(`tenants/${TENANT}/shift_verifications`), []);
});
