import assert from "node:assert/strict";
import test from "node:test";
import {DocumentData, Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {FakeFirestore} from "../testing/fakeFirestore";
import {ensureSweep, processTenantDiscoveryPage} from "./jobs";
import {
  isoWeekKey,
  monthlyShardDay,
  reconciliationJobId,
  ReconciliationSweepKind,
  reconciliationTaskId,
  requireDiscoveryPayload,
  sweepRunId,
  TenantDiscoveryTaskPayload,
} from "./model";

/**
 * How a scheduled sweep decides which tenants are reconciled tonight, against an
 * in-memory Firestore.
 *
 * `ensureSweep` is what the three schedulers in `handlers.ts` call, and
 * `processTenantDiscoveryPage` is the paginator that turns one sweep into one
 * deterministic reconciliation task per active tenant. Between them they are the
 * only route by which a tenant nobody touched today is reconciled at all, and
 * neither had a unit assertion anywhere: the integration suite drives one tenant
 * through one page, which is the case where every boundary here is invisible.
 *
 * Four things are pinned, because each of them is silent when it breaks:
 *
 * - **The page boundary.** `TENANT_DISCOVERY_PAGE_SIZE` is 50 and the continuation
 *   is decided by it. A page that ends exactly on it and returns nothing strands
 *   every tenant after the fiftieth, unreconciled, with a sweep marked completed.
 * - **The monthly shard filter.** It is the one branch that keeps the staggered
 *   monthly run - which fires *daily* at 04:45 - from becoming a second nightly
 *   run over every tenant at once.
 * - **Page idempotency.** The queue delivers at least once, so a page arrives
 *   twice, and `pages/{page}` is the only thing that stops the second delivery
 *   counting its tenants into the sweep's totals again.
 * - **Sweep identity.** `sweepRunId` is a digest of kind and date, so two
 *   schedulers firing for one date land on one document rather than two half-swept
 *   ones.
 *
 * The double is the one in `../testing/fakeFirestore`. It orders by document ID
 * exactly as Firestore does, refuses a `create` over an existing document, and
 * stages a transaction's writes so a refused one lands nothing.
 */

const LOCAL_DATE = "2026-08-06";
const PAGE_SIZE = 50;

function sweepPath(kind: ReconciliationSweepKind, localDate = LOCAL_DATE): string {
  return `platform_reconciliation_sweeps/${sweepRunId(kind, localDate)}`;
}

function pagePath(
  kind: ReconciliationSweepKind,
  page: number,
  localDate = LOCAL_DATE
): string {
  return `${sweepPath(kind, localDate)}/pages/${`${page}`.padStart(8, "0")}`;
}

function jobPath(tenantId: string, kind: ReconciliationSweepKind, localDate = LOCAL_DATE): string {
  const jobId = reconciliationJobId(kind, `${kind}:${localDate}`);
  return `tenants/${tenantId}/reconciliation_jobs/${jobId}`;
}

/** The document at `path`, refusing to assert about one that was never written. */
function stored(db: FakeFirestore, path: string): DocumentData {
  const document = db.read(path);
  assert.ok(document !== undefined, `Nothing was written at ${path}.`);
  return document;
}

/** `count` tenants named `tenant-00`.., every one of them active. */
function seedActiveTenants(db: FakeFirestore, count: number): string[] {
  const ids = Array.from(
    {length: count},
    (_, index) => `tenant-${`${index}`.padStart(2, "0")}`
  );
  for (const id of ids) db.seed(`tenants/${id}`, {status: "active", name: id});
  return ids;
}

/** The page payload a scheduler's `ensureSweep` hands to the first discovery task. */
async function startedSweep(
  db: FakeFirestore,
  kind: ReconciliationSweepKind = "nightly",
  localDate = LOCAL_DATE
): Promise<TenantDiscoveryTaskPayload> {
  const payload = await ensureSweep(db.asFirestore(), kind, localDate);
  db.clearWrites();
  return payload;
}

// ---------------------------------------------------------------------------
// ensureSweep: one document per kind and date, and no second one
// ---------------------------------------------------------------------------

test("a scheduler's first firing opens the sweep and asks for its first page", async () => {
  const db = new FakeFirestore();

  const payload = await ensureSweep(db.asFirestore(), "nightly", LOCAL_DATE);

  // The payload is the discovery task's whole input, and `enqueueDiscoveryTask`
  // validates it before the queue ever sees it - including that the run ID is the
  // digest of this exact kind and date. A payload that failed here would throw
  // inside the scheduler, after the sweep document was already committed.
  assert.deepEqual(payload, {
    runId: sweepRunId("nightly", LOCAL_DATE),
    kind: "nightly",
    localDate: LOCAL_DATE,
    page: 0,
  });
  requireDiscoveryPayload(payload);

  const sweep = stored(db, sweepPath("nightly"));
  assert.equal(sweep.runId, payload.runId);
  assert.equal(sweep.kind, "nightly");
  assert.equal(sweep.localDate, LOCAL_DATE);
  assert.equal(sweep.status, "running");
  // Nothing has been scanned yet, and the page transaction increments these. A
  // sweep that opened with them absent would still count correctly - Firestore's
  // increment treats a missing field as the operand - but a sweep read before its
  // first page landed would report nothing rather than zero.
  assert.equal(sweep.pagesProcessed, 0);
  assert.equal(sweep.tenantsScanned, 0);
  assert.equal(sweep.tenantJobsCreated, 0);
  assert.deepEqual(db.writtenPaths(), [sweepPath("nightly")]);
});

test("a second firing for the same date re-enters the sweep instead of restarting it", async () => {
  // `onSchedule` carries `retryCount: 3`, so the same nightly schedule can invoke
  // `beginSweep` more than once for one date. The second one must not reopen a
  // sweep whose pages are already counted, or the totals an operator reads are the
  // last firing's rather than the day's.
  const db = new FakeFirestore();
  const first = await startedSweep(db);
  db.seed(sweepPath("nightly"), {
    ...stored(db, sweepPath("nightly")),
    status: "completed",
    pagesProcessed: 3,
    tenantsScanned: 140,
    tenantJobsCreated: 140,
  });

  const second = await ensureSweep(db.asFirestore(), "nightly", LOCAL_DATE);

  assert.deepEqual(second, first);
  // Not one write. Re-entering is a read, so a completed sweep is not dragged back
  // to `running` and no counter is reset.
  assert.deepEqual(db.writtenPaths(), []);
  const sweep = stored(db, sweepPath("nightly"));
  assert.equal(sweep.status, "completed");
  assert.equal(sweep.pagesProcessed, 3);
  assert.equal(sweep.tenantsScanned, 140);
});

test("the three sweeps of one day are three documents, and one kind's two days are two", async () => {
  const db = new FakeFirestore();

  const kinds: ReconciliationSweepKind[] = ["nightly", "weekly", "monthly"];
  for (const kind of kinds) await ensureSweep(db.asFirestore(), kind, LOCAL_DATE);
  await ensureSweep(db.asFirestore(), "nightly", "2026-08-07");

  // Sunday 04:30 weekly, 04:45 monthly, and 05:30 nightly all fall on one local
  // date, and they create different jobs with different modes. Sharing a run ID
  // would make the second of them adopt the first's pages and stop.
  assert.deepEqual(
    db.ids("platform_reconciliation_sweeps").sort(),
    [
      sweepRunId("nightly", "2026-08-07"),
      sweepRunId("nightly", LOCAL_DATE),
      sweepRunId("weekly", LOCAL_DATE),
      sweepRunId("monthly", LOCAL_DATE),
    ].sort()
  );
  for (const kind of kinds) {
    assert.match(sweepRunId(kind, LOCAL_DATE), /^rs_[a-f0-9]{40}$/, kind);
  }
});

test("a document sitting at the sweep's ID that disagrees is refused, not adopted", async () => {
  // The run ID is predictable, which is what makes two schedulers agree - and it
  // is also what would let anything else occupy it. A sweep that adopted a
  // disagreeing document would page one date's tenants into another date's totals.
  for (const occupant of [
    {kind: "weekly", localDate: LOCAL_DATE},
    {kind: "nightly", localDate: "2026-08-05"},
  ]) {
    const db = new FakeFirestore();
    db.seed(sweepPath("nightly"), {
      runId: sweepRunId("nightly", LOCAL_DATE),
      ...occupant,
      status: "running",
      pagesProcessed: 0,
      tenantsScanned: 0,
      tenantJobsCreated: 0,
    });
    db.clearWrites();

    await assert.rejects(
      ensureSweep(db.asFirestore(), "nightly", LOCAL_DATE),
      (error: unknown) => error instanceof HttpsError &&
        error.code === "already-exists" &&
        /sweep identity collision/.test(error.message),
      JSON.stringify(occupant)
    );

    assert.deepEqual(db.writtenPaths(), []);
    assert.equal(stored(db, sweepPath("nightly")).kind, occupant.kind);
  }
});

// ---------------------------------------------------------------------------
// processTenantDiscoveryPage: who is scanned, and who is skipped
// ---------------------------------------------------------------------------

test("only an active tenant is scanned, and only it gets a job", async () => {
  const db = new FakeFirestore();
  for (const [id, status] of [
    ["tenant-active-1", "active"],
    ["tenant-active-2", "active"],
    ["tenant-pending", "pending"],
    ["tenant-suspended", "suspended"],
    ["tenant-rejected", "rejected"],
    ["tenant-archived", "archived"],
  ]) db.seed(`tenants/${id}`, {status, name: id});
  const payload = await startedSweep(db);

  const result = await processTenantDiscoveryPage(db.asFirestore(), payload);

  assert.deepEqual(
    result.tenantTasks.map((task) => task.tenantId),
    ["tenant-active-1", "tenant-active-2"]
  );
  assert.equal(result.continuation, undefined);
  for (const id of ["tenant-pending", "tenant-suspended", "tenant-rejected", "tenant-archived"]) {
    assert.equal(db.read(jobPath(id, "nightly")), undefined, id);
  }
  // `tenantsScanned` is the count the query returned, so it is active tenants and
  // not tenants. A suspended business is not behind on reconciliation; it is not
  // trading.
  const sweep = stored(db, sweepPath("nightly"));
  assert.equal(sweep.tenantsScanned, 2);
  assert.equal(sweep.tenantsEligible, 2);
  assert.equal(sweep.tenantJobsCreated, 2);
});

test("a tenant's scheduled job carries the shape its checkpoint needs", async () => {
  // `scheduledJobDefinition` is private and reached only from here, and the three
  // kinds are not interchangeable: monthly is the only full pass, and the two
  // checkpoint kinds are what a chain verification is keyed by. A monthly job
  // written as incremental would verify nothing and still report success.
  const tenantId = "tenant-shape";
  // Its own shard day, so the monthly filter admits it too.
  const localDate = `2026-08-${`${monthlyShardDay(tenantId)}`.padStart(2, "0")}`;

  for (const kind of ["nightly", "weekly", "monthly"] as const) {
    const db = new FakeFirestore();
    db.seed(`tenants/${tenantId}`, {status: "active"});
    const payload = await startedSweep(db, kind, localDate);

    const result = await processTenantDiscoveryPage(db.asFirestore(), payload);

    const effective = kind === "nightly" ? "monthly" : kind;
    assert.deepEqual(result.tenantTasks, [{
      tenantId,
      jobId: reconciliationJobId(effective, `${effective}:${localDate}`),
      generation: 0,
      revision: 0,
    }], kind);
    const job = stored(db, jobPath(tenantId, effective, localDate));
    assert.equal(job.source, effective, kind);
    assert.equal(job.sourceKey, `${effective}:${localDate}`, kind);
    assert.equal(job.requestedBy, `system:${effective}`, kind);
    assert.equal(job.status, "queued", kind);
    assert.equal(job.localDate, localDate, kind);
    assert.equal(job.mode, effective === "monthly" ? "full" : "incremental", kind);
    assert.equal(
      job.checkpointKind,
      effective,
      kind
    );
    // Weekly checkpoints chain by ISO week and monthly ones by calendar month, so
    // seven nightly-shaped keys would each start their own chain and verify none.
    assert.equal(
      job.checkpointKey,
      effective === "weekly" ? isoWeekKey(localDate) :
        effective === "monthly" ? localDate.slice(0, 7) : localDate,
      kind
    );
    // A full pass has a window to build before it may compare anything, and
    // `fullInitialized` is the flag the metrics phase reads to decide that.
    assert.equal(job.fullInitialized, effective !== "monthly", kind);
  }
});

test("a tenant already running, completed, or quarantined today is not redispatched", async () => {
  // Two routes reach one scheduled job: this paginator and the ten-minute retry
  // sweep. A dispatch built here for a job somebody is already running is two
  // workers on one tenant's ledger, so the create-or-resume read is what refuses
  // it - and it refuses on status alone, without touching the document.
  const db = new FakeFirestore();
  const ids = seedActiveTenants(db, 4);
  const payload = await startedSweep(db);
  await processTenantDiscoveryPage(db.asFirestore(), payload);
  for (const [index, status] of ["running", "completed", "quarantined", "failed"].entries()) {
    const path = jobPath(ids[index], "nightly");
    db.seed(path, {...stored(db, path), status, generation: 1, revision: 4});
  }
  // A fresh sweep for the next day's page would collide on the job ID, so the
  // redelivery is of this same page - the counters are what page idempotency
  // protects, and the tasks are computed before that guard.
  db.clearWrites();

  const result = await processTenantDiscoveryPage(db.asFirestore(), payload);

  // Only the failed one is resumed, and it is resumed at the generation and
  // revision the document actually holds rather than at zero.
  assert.deepEqual(result.tenantTasks, [{
    tenantId: ids[3],
    jobId: reconciliationJobId("nightly", `nightly:${LOCAL_DATE}`),
    generation: 1,
    revision: 4,
  }]);
  assert.deepEqual(db.writtenPaths(), []);
});

// ---------------------------------------------------------------------------
// The page boundary
// ---------------------------------------------------------------------------

test("a page that fills exactly asks for the next one, and the short page ends the sweep", async () => {
  // The boundary in both directions, in one chain, because getting either half
  // wrong is silent: a full page that returns no continuation strands every tenant
  // after the fiftieth, and a short page that returns one enqueues a task that
  // scans nothing forever.
  const db = new FakeFirestore();
  const ids = seedActiveTenants(db, PAGE_SIZE + 3);
  const first = await startedSweep(db);

  const firstPage = await processTenantDiscoveryPage(db.asFirestore(), first);

  assert.equal(firstPage.tenantTasks.length, PAGE_SIZE);
  assert.deepEqual(
    firstPage.tenantTasks.map((task) => task.tenantId),
    ids.slice(0, PAGE_SIZE)
  );
  const continuation = firstPage.continuation;
  assert.ok(continuation, "a page that ended exactly on the page size must continue");
  assert.deepEqual(continuation, {
    ...first,
    page: 1,
    cursor: ids[PAGE_SIZE - 1],
  });
  requireDiscoveryPayload(continuation);
  const openSweep = stored(db, sweepPath("nightly"));
  assert.equal(openSweep.status, "running");
  assert.equal("completedAt" in openSweep, false);
  assert.equal(openSweep.cursor, ids[PAGE_SIZE - 1]);
  // Pages are numbered so they sort in the order they ran, which is the only way
  // to read a sweep's history back.
  const firstRecord = stored(db, pagePath("nightly", 0));
  assert.deepEqual(db.ids(`${sweepPath("nightly")}/pages`), ["00000000"]);
  assert.equal(firstRecord.inputCursor, null);
  assert.equal(firstRecord.outputCursor, continuation.cursor);
  assert.equal(firstRecord.hasMore, true);
  assert.equal(firstRecord.tenantsScanned, PAGE_SIZE);

  const secondPage = await processTenantDiscoveryPage(db.asFirestore(), continuation);

  assert.deepEqual(
    secondPage.tenantTasks.map((task) => task.tenantId),
    ids.slice(PAGE_SIZE)
  );
  assert.equal(secondPage.continuation, undefined);
  const closedSweep = stored(db, sweepPath("nightly"));
  assert.equal(closedSweep.status, "completed");
  assert.ok(closedSweep.completedAt instanceof Timestamp);
  assert.equal(closedSweep.pagesProcessed, 2);
  assert.equal(closedSweep.tenantsScanned, PAGE_SIZE + 3);
  assert.equal(closedSweep.tenantJobsCreated, PAGE_SIZE + 3);
  assert.deepEqual(db.ids(`${sweepPath("nightly")}/pages`), ["00000000", "00000001"]);
  assert.equal(stored(db, pagePath("nightly", 1)).inputCursor, ids[PAGE_SIZE - 1]);
  for (const id of ids) assert.ok(db.read(jobPath(id, "nightly")), id);
});

test("a page holding no tenants at all closes the sweep and keeps the cursor it was given", async () => {
  // The last page of a sweep whose tenant count is an exact multiple of fifty:
  // every tenant is already done, the query returns nothing, and there is no last
  // document to take a cursor from. Overwriting the sweep's cursor with null here
  // would make the completed record claim it never got past the first tenant.
  const db = new FakeFirestore();
  seedActiveTenants(db, 1);
  const opened = await startedSweep(db);
  const payload = {...opened, page: 4, cursor: "tenant-99"};

  const result = await processTenantDiscoveryPage(db.asFirestore(), payload);

  assert.deepEqual(result, {tenantTasks: []});
  const sweep = stored(db, sweepPath("nightly"));
  assert.equal(sweep.status, "completed");
  assert.equal(sweep.cursor, "tenant-99");
  assert.equal(sweep.tenantsScanned, 0);
  const page = stored(db, pagePath("nightly", 4));
  assert.equal(page.inputCursor, "tenant-99");
  assert.equal(page.outputCursor, "tenant-99");
  assert.equal(page.hasMore, false);
});

// ---------------------------------------------------------------------------
// The monthly shard filter
// ---------------------------------------------------------------------------

/**
 * Tenant IDs split by whether `monthlyShardDay` puts them on `day`.
 *
 * The split is computed from `monthlyShardDay` rather than hard-coded, because a
 * frozen digest in a fixture is unreadable and would only re-assert the hash.
 * `monthlyShardDay` is pinned separately in `model.test.ts`; here it is the oracle
 * the filter is checked against, and both halves are asserted non-empty so a
 * change to it cannot leave this test passing vacuously.
 */
function shardSplit(ids: readonly string[], day: number): {today: string[]; other: string[]} {
  const today = ids.filter((id) => monthlyShardDay(id) === day);
  const other = ids.filter((id) => monthlyShardDay(id) !== day);
  assert.ok(today.length > 0, `no seeded tenant shards onto day ${day}`);
  assert.ok(other.length > 0, `every seeded tenant shards onto day ${day}`);
  return {today, other};
}

test("a staggered monthly page takes today's shard and leaves the rest of the month alone", async () => {
  // The monthly schedule fires at 04:45 *every* day and reconciles a twenty-eighth
  // of the estate each time. Without this filter it is a second nightly sweep in
  // full mode over every tenant at once, which is the most expensive thing this
  // pipeline can do.
  const db = new FakeFirestore();
  const ids = seedActiveTenants(db, 40);
  const day = monthlyShardDay(ids[0]);
  const localDate = `2026-08-${`${day}`.padStart(2, "0")}`;
  const {today, other} = shardSplit(ids, day);
  const payload = await startedSweep(db, "monthly", localDate);

  const result = await processTenantDiscoveryPage(db.asFirestore(), payload);

  assert.deepEqual(result.tenantTasks.map((task) => task.tenantId), today);
  for (const id of today) assert.ok(db.read(jobPath(id, "monthly", localDate)), id);
  for (const id of other) assert.equal(db.read(jobPath(id, "monthly", localDate)), undefined, id);
  // Scanned and eligible are separate counters for exactly this reason: the page
  // read forty tenants and reconciled a handful, and a sweep reporting only one of
  // those numbers cannot be read as either.
  const sweep = stored(db, sweepPath("monthly", localDate));
  assert.equal(sweep.tenantsScanned, 40);
  assert.equal(sweep.tenantsEligible, today.length);
  assert.equal(sweep.tenantJobsCreated, today.length);
});

test("the same tenants on a nightly sweep are all eligible, so the filter is monthly's alone", async () => {
  // The contrast that makes the test above mean something. Same fixture, same
  // date, different kind: nightly reconciles the estate.
  const db = new FakeFirestore();
  const ids = seedActiveTenants(db, 40);
  const localDate = `2026-08-${`${monthlyShardDay(ids[0])}`.padStart(2, "0")}`;
  const payload = await startedSweep(db, "nightly", localDate);

  const result = await processTenantDiscoveryPage(db.asFirestore(), payload);

  assert.deepEqual(result.tenantTasks.map((task) => task.tenantId), ids);
  assert.equal(stored(db, sweepPath("nightly", localDate)).tenantsEligible, 40);
});

test("a full page holding one eligible tenant still continues", async () => {
  // `hasMore` is decided by what the query returned, not by what the shard filter
  // kept. Deciding it on the eligible count instead would end a monthly sweep at
  // the first page whose fifty tenants all belong to other days - which, on a
  // twenty-eight-way split, is most of them.
  const db = new FakeFirestore();
  const ids = seedActiveTenants(db, PAGE_SIZE);
  const day = monthlyShardDay(ids[0]);
  const localDate = `2026-08-${`${day}`.padStart(2, "0")}`;
  const {today} = shardSplit(ids, day);
  const payload = await startedSweep(db, "monthly", localDate);

  const result = await processTenantDiscoveryPage(db.asFirestore(), payload);

  assert.ok(result.tenantTasks.length < PAGE_SIZE, "the fixture must exclude someone");
  assert.equal(result.tenantTasks.length, today.length);
  assert.deepEqual(result.continuation, {...payload, page: 1, cursor: ids[PAGE_SIZE - 1]});
  // The cursor is the last document *scanned*, not the last one kept, or the next
  // page would re-scan everyone the filter skipped.
  assert.equal(stored(db, pagePath("monthly", 0, localDate)).outputCursor, ids[PAGE_SIZE - 1]);
});

// ---------------------------------------------------------------------------
// Page idempotency, and the sweep that disappeared
// ---------------------------------------------------------------------------

test("a redelivered page is not counted twice and returns the same task identities", async () => {
  // Cloud Tasks guarantees at-least-once, and `enqueueDiscoveryTask` swallows
  // `already-exists`, so one page runs twice as a matter of course. The counters
  // are what must not move; the tasks are re-returned and re-enqueued, which is
  // free only because their IDs are a digest of tenant, job, generation, and
  // revision - and the queue refuses a duplicate of that.
  const db = new FakeFirestore();
  seedActiveTenants(db, 3);
  const payload = await startedSweep(db);
  const first = await processTenantDiscoveryPage(db.asFirestore(), payload);
  const firstSweep = stored(db, sweepPath("nightly"));
  const firstPage = stored(db, pagePath("nightly", 0));
  db.clearWrites();

  const second = await processTenantDiscoveryPage(db.asFirestore(), payload);

  assert.deepEqual(second, first);
  assert.deepEqual(
    second.tenantTasks.map(reconciliationTaskId),
    first.tenantTasks.map(reconciliationTaskId)
  );
  // Not one write on the way through: the tenant jobs already exist and are read
  // rather than rewritten, and the page guard returns before the sweep update.
  assert.deepEqual(db.writtenPaths(), []);
  assert.deepEqual(stored(db, sweepPath("nightly")), firstSweep);
  assert.deepEqual(stored(db, pagePath("nightly", 0)), firstPage);
});

test("a page whose sweep has disappeared throws rather than recording itself", async () => {
  // A sweep removed by hand, or a page delivered against a run ID that never
  // opened. The page must not create the counters it is trying to increment,
  // because a sweep document invented by its own third page has no start, no kind,
  // and a pages-processed count of one.
  const db = new FakeFirestore();
  seedActiveTenants(db, 2);
  const payload: TenantDiscoveryTaskPayload = {
    runId: sweepRunId("nightly", LOCAL_DATE),
    kind: "nightly",
    localDate: LOCAL_DATE,
    page: 0,
  };

  await assert.rejects(
    processTenantDiscoveryPage(db.asFirestore(), payload),
    (error: unknown) => error instanceof HttpsError &&
      error.code === "not-found" &&
      /sweep disappeared/.test(error.message)
  );

  assert.equal(db.read(sweepPath("nightly")), undefined);
  assert.deepEqual(db.ids("platform_reconciliation_sweeps"), []);
  // The tenant jobs are created before that transaction and survive it, which is
  // the honest outcome rather than a tidy one: the throw is what the queue retries
  // on, and the retry finds those jobs already queued and resumes them at the
  // generation they hold. Nothing is duplicated, because the job ID is a digest of
  // kind and date.
  assert.deepEqual(
    db.writtenPaths(),
    ["tenant-00", "tenant-01"].map((id) => jobPath(id, "nightly"))
  );
});
