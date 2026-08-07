import assert from "node:assert/strict";
import test from "node:test";
import {DocumentData, Timestamp, Transaction} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {FakeFirestore} from "../testing/fakeFirestore";
import {deleteSentinelPaths} from "../testing/writeSentinels";
import {
  advanceReconciliationJob,
  ClaimedReconciliationJob,
  claimReconciliationJob,
  createManualJobInTransaction,
  finalizeReconciliationJob,
  recordReconciliationFailure,
  registerSaleReceipt,
  saleTriggerJobFields,
} from "./jobs";
import {DirtyJobDecision, mergeDirtyJob, ReconciliationTaskPayload} from "./model";

const BUCKET = 1785842700000;

function fields(decision: DirtyJobDecision) {
  return saleTriggerJobFields({
    tenantId: "tenant-a",
    bucket: BUCKET,
    businessDate: "2026-08-04",
    decision,
  });
}

test("a new bucket's job is created without any delete sentinel", () => {
  // The regression. `mergeDirtyJob(undefined)` returns `queued`, which is the
  // decision every first sale of a five-minute bucket produces, and the create
  // payload is the one Firestore rejects a sentinel in. Before the fix this
  // carried `productCursor` and `pendingProductId`, so `mergeSaleReconciliationJob`
  // threw for every first sale and no reconciliation job was ever recorded.
  const decision = mergeDirtyJob();
  assert.equal(decision.status, "queued");

  const {create} = fields(decision);

  assert.deepEqual(deleteSentinelPaths(create), []);
  assert.equal(create.status, "queued");
  assert.equal(create.phase, "metrics");
  assert.equal(create.source, "sale_trigger");
  assert.equal(create.sourceKey, `${BUCKET}`);
  assert.equal(create.localDate, "2026-08-04");
  // A new job has run nothing, so every counter starts at zero and no cursor
  // field exists to be cleared.
  for (const counter of [
    "attemptCount",
    "consecutiveFailureCount",
    "metricsProcessed",
    "productsProcessed",
    "stockVarianceCount",
    "shiftsProcessed",
    "shiftVarianceCount",
  ]) {
    assert.equal(create[counter], 0, counter);
  }
  assert.equal("productCursor" in create, false);
  assert.equal("pendingProductId" in create, false);
});

test("no decision status can put a delete sentinel in the create payload", () => {
  // The create branch is reachable for any decision - a job document can be
  // absent while a prior one was running, if it was removed - so the property is
  // asserted over every status rather than only the common one.
  for (const status of [
    "queued",
    "running",
    "failed",
    "completed",
    "quarantined",
  ] as const) {
    const {create} = fields({
      status,
      phase: "stock",
      generation: 3,
      revision: 7,
      rerunRequested: true,
      enqueue: false,
    });
    assert.deepEqual(deleteSentinelPaths(create), [], status);
  }
});

test("an existing job returning to queued clears the cursors it left behind", () => {
  // The update branch is where a sentinel belongs and must keep working: a job
  // going back to `queued` starts its phases again, so a cursor from a previous
  // pass describes work this pass has not done.
  const {update} = fields(mergeDirtyJob({
    status: "completed",
    phase: "finalize",
    generation: 2,
    revision: 9,
    rerunRequested: false,
  }));

  assert.deepEqual(
    deleteSentinelPaths(update),
    ["pendingProductId", "productCursor"],
  );
  assert.equal(update.status, "queued");
  assert.equal(update.consecutiveFailureCount, 0);
  // A completed job re-queued by a new sale advances both counters, which is
  // what makes its next task ID distinct from the finished one's.
  assert.equal(update.generation, 3);
  assert.equal(update.revision, 10);
});

test("an existing job that stays running keeps its cursors", () => {
  // A running job's cursor describes the page it is in the middle of, so clearing
  // it would restart that phase and re-verify products already verified.
  const {update} = fields(mergeDirtyJob({
    status: "running",
    phase: "stock",
    generation: 1,
    revision: 4,
    rerunRequested: false,
  }));

  assert.deepEqual(deleteSentinelPaths(update), []);
  assert.equal(update.status, "running");
  assert.equal(update.rerunRequested, true);
});

test("both payloads describe the same bucket and business date", () => {
  const {create, update} = fields(mergeDirtyJob());

  for (const payload of [create, update]) {
    assert.equal(payload.tenantId, "tenant-a");
    assert.equal(payload.checkpointKind, "none");
    assert.equal(payload.checkpointKey, `${BUCKET}`);
    assert.equal(payload.requestedBy, "system:sale_trigger");
    assert.equal(payload.mutatesStock, false);
    assert.equal(payload.fullInitialized, true);
  }
});

/**
 * When a job's next page runs, over an in-memory Firestore.
 *
 * `advanceReconciliationJob` writes the one field that decides it, and it used to
 * take a `retryDelayMilliseconds` from the phase that had just finished. Nothing
 * in the pipeline ever produced a value for it: the only page that stops short is
 * a stock page holding a product with a movement backlog, and a backlog means the
 * next two hundred movements are already written and waiting. The one branch with
 * any claim to asking for a delay - a product written inside the last five minutes
 * - does not hold the page at all. It records the deferral, steps past, and leaves
 * the product's ledger position untouched so the next run reads it again; holding
 * it would block every product after it in document-ID order, and because every
 * sale stamps `updatedAt` on every product it decrements, a product that sells
 * more often than once every five minutes never leaves its own window.
 *
 * So the schedule is unconditional, and these are the two things that makes it:
 * every continuation is due now, and a backoff a failed attempt left behind does
 * not outlive the attempt that succeeded.
 */

const TENANT = "tenant-a";
const JOB = "rj_manual_advance";
const LOCAL_DATE = "2026-08-06";

/** The dispatch a freshly created job's first task carries. */
const FIRST_TASK: ReconciliationTaskPayload = {
  tenantId: TENANT,
  jobId: JOB,
  generation: 0,
  revision: 0,
};

function jobPath(): string {
  return `tenants/${TENANT}/reconciliation_jobs/${JOB}`;
}

/**
 * A Firestore holding one queued job, created by the production creator.
 *
 * The fixture is what `createManualJobInTransaction` writes rather than a
 * hand-built imitation of it, because the field under test is one the creator also
 * sets: a fixture that omitted `nextAttemptAt` would let a claim succeed for a
 * reason production never offers.
 */
async function firestoreWithQueuedJob(): Promise<FakeFirestore> {
  const db = new FakeFirestore();
  await db.runTransaction(async (transaction) => createManualJobInTransaction(
    db.asFirestore(),
    transaction as unknown as Transaction,
    {
      tenantId: TENANT,
      jobId: JOB,
      actorUid: "uid-owner",
      requestId: "req-1",
      mode: "incremental",
      localDate: LOCAL_DATE,
    }
  ));
  db.clearWrites();
  return db;
}

/** The job document, refusing to assert about one that was never written. */
function storedJob(db: FakeFirestore): DocumentData {
  const document = db.read(jobPath());
  assert.ok(document !== undefined, `Nothing was written at ${jobPath()}.`);
  return document;
}

/** The job, claimed, refusing to continue against a claim that was refused. */
async function claimJob(
  db: FakeFirestore,
  payload: ReconciliationTaskPayload = FIRST_TASK,
  now?: Timestamp
): Promise<ClaimedReconciliationJob> {
  const claimed = now === undefined ?
    await claimReconciliationJob(db.asFirestore(), payload) :
    await claimReconciliationJob(db.asFirestore(), payload, now);
  assert.ok(claimed, `Nothing claimable at generation ${payload.generation}/${payload.revision}.`);
  return claimed;
}

/** The instant `path`'s document is next due, as milliseconds. */
function dueAtMilliseconds(document: DocumentData): number {
  const dueAt = document.nextAttemptAt;
  assert.ok(
    dueAt instanceof Timestamp,
    "A queued job with no `nextAttemptAt` is invisible to listRetryableReconciliationTasks."
  );
  return dueAt.toMillis();
}

test("a finished page schedules its continuation for now and nothing later", async () => {
  const db = await firestoreWithQueuedJob();
  const claimed = await claimReconciliationJob(
    db.asFirestore(),
    {tenantId: TENANT, jobId: JOB, generation: 0, revision: 0}
  );
  assert.ok(claimed);

  const before = Date.now();
  const continuation = await advanceReconciliationJob(db.asFirestore(), claimed, {
    phase: "stock",
    metricsProcessedDelta: 5,
    productCursor: null,
    pendingProductId: null,
  });
  const after = Date.now();

  assert.deepEqual(continuation, {tenantId: TENANT, jobId: JOB, generation: 0, revision: 1});
  const advanced = storedJob(db);
  assert.equal(advanced.status, "queued");
  assert.equal(advanced.phase, "stock");
  assert.equal(advanced.revision, 1);
  assert.equal(advanced.metricsProcessed, 5);
  // The whole of the schedule. A delay would have to come from somewhere, and the
  // parameter it used to come from had no producer in three modules.
  const dueAt = dueAtMilliseconds(advanced);
  assert.ok(dueAt >= before && dueAt <= after, `${dueAt} is not between ${before} and ${after}`);
  // The lease is surrendered, so a worker that comes back late cannot commit.
  assert.equal("leaseToken" in advanced, false);
  assert.equal("leaseExpiresAt" in advanced, false);
  // One document. A continuation is a job-state change and nothing else.
  assert.deepEqual(db.writtenPaths(), [jobPath()]);

  // And "now" means the very next dispatch is accepted rather than refused for
  // being early, which is the only observable difference a delay would make.
  assert.ok(await claimReconciliationJob(db.asFirestore(), continuation));
  assert.equal(storedJob(db).attemptCount, 2);
});

test("a page that stopped on a pending product is continued immediately too", async () => {
  // The movement-backlog continuation: the one page shape that ever carried a
  // retry delay, built here exactly as the stock branch of `executeReconciliationTask`
  // builds it from a `StockPageResult` that stopped short.
  const db = await firestoreWithQueuedJob();
  const claimed = await claimReconciliationJob(
    db.asFirestore(),
    {tenantId: TENANT, jobId: JOB, generation: 0, revision: 0}
  );
  assert.ok(claimed);

  const before = Date.now();
  await advanceReconciliationJob(db.asFirestore(), claimed, {
    phase: "stock",
    productCursor: "product-01",
    pendingProductId: "product-02",
    productsProcessedDelta: 1,
    stockVarianceDelta: 0,
  });
  const after = Date.now();

  const advanced = storedJob(db);
  const dueAt = dueAtMilliseconds(advanced);
  assert.ok(dueAt >= before && dueAt <= after, `${dueAt} is not between ${before} and ${after}`);
  // Held for the next dispatch, not for a later one: the backlog's next page of
  // movements is already committed, so waiting would only delay reading it.
  assert.equal(advanced.pendingProductId, "product-02");
  assert.equal(advanced.productCursor, "product-01");
  assert.equal(advanced.productsProcessed, 1);
});

test("a page that succeeds after a failure does not inherit the failure's backoff", async () => {
  const db = await firestoreWithQueuedJob();
  const payload = {tenantId: TENANT, jobId: JOB, generation: 0, revision: 0};
  const failing = await claimReconciliationJob(db.asFirestore(), payload);
  assert.ok(failing);

  await recordReconciliationFailure(
    db.asFirestore(),
    failing,
    new HttpsError("unavailable", "Firestore was unreachable.")
  );

  const failed = storedJob(db);
  assert.equal(failed.status, "failed");
  assert.equal(failed.consecutiveFailureCount, 1);
  const backoffMilliseconds = dueAtMilliseconds(failed);
  assert.ok(
    backoffMilliseconds > Date.now(),
    "the failure must leave a live backoff or this test proves nothing"
  );
  // While it is live the backoff is enforced, which is what the field is for.
  await assert.rejects(
    claimReconciliationJob(db.asFirestore(), payload),
    /retry backoff is still active/
  );

  const retried = await claimReconciliationJob(
    db.asFirestore(),
    payload,
    Timestamp.fromMillis(backoffMilliseconds)
  );
  assert.ok(retried);
  const continuation = await advanceReconciliationJob(
    db.asFirestore(),
    retried,
    {phase: "stock"}
  );

  const advanced = storedJob(db);
  // Fifteen seconds of backoff belonged to the attempt that failed, not to every
  // page after it. If a successful page left the stale instant in place, a job
  // that failed once would have every remaining page refused for being early -
  // and at the last rung before quarantine it would be refused for sixteen
  // minutes per page. (Earlier notes said an hour. The hour is the cap in the
  // formula, and "the whole reachable ladder" below shows it is never reached.)
  assert.ok(
    dueAtMilliseconds(advanced) < backoffMilliseconds,
    "the successful page kept the failed attempt's backoff"
  );
  assert.equal(advanced.consecutiveFailureCount, 0);
  assert.equal("lastErrorCode" in advanced, false);
  assert.ok(await claimReconciliationJob(db.asFirestore(), continuation));
});

/**
 * Who is allowed to run a job's next page, over the same in-memory Firestore.
 *
 * A reconciliation job is driven by a Cloud Tasks queue, and a queue guarantees
 * at-least-once delivery of every task it accepts. So the same dispatch arrives
 * twice, a dispatch the job has already moved past arrives late, and a worker
 * killed at its deadline leaves a job that looks running and is not. Three
 * fields decide all of it - `generation`, `revision`, and `leaseToken` - and
 * `claimReconciliationJob` is where they are read.
 *
 * None of it had unit coverage. The suite below is the refusals, because a claim
 * that is granted when it should not be is two workers writing one tenant's
 * stock verifications from two different ledger positions.
 */

test("a job that no longer exists is not claimed", async () => {
  // The task outlives its job: a tenant deleted, or a job removed by hand. The
  // dispatch has to end quietly, because the queue will not stop delivering it
  // for anything short of a success.
  const db = new FakeFirestore();

  assert.equal(await claimReconciliationJob(db.asFirestore(), FIRST_TASK), undefined);
  assert.deepEqual(db.writtenPaths(), []);
});

test("a task naming a superseded generation or revision is not claimed", async () => {
  // Every page the job finishes bumps `revision`, and every rerun bumps
  // `generation`. A dispatch built from either of the old values describes work
  // that has already been done, so re-running it would re-verify products
  // against a ledger position the job has passed.
  for (const stale of [
    {...FIRST_TASK, generation: 1},
    {...FIRST_TASK, revision: 1},
  ]) {
    const db = await firestoreWithQueuedJob();

    assert.equal(
      await claimReconciliationJob(db.asFirestore(), stale),
      undefined,
      `generation ${stale.generation}, revision ${stale.revision}`
    );
    assert.deepEqual(db.writtenPaths(), []);
    assert.equal(storedJob(db).attemptCount, 0);
  }
});

test("a live lease is not stolen by a duplicate dispatch", async () => {
  const db = await firestoreWithQueuedJob();
  const owner = await claimJob(db);
  db.clearWrites();

  // The same task, delivered twice. It is not an error and nothing is recorded
  // against the job - the second worker simply has no work.
  assert.equal(await claimReconciliationJob(db.asFirestore(), FIRST_TASK), undefined);

  assert.deepEqual(db.writtenPaths(), []);
  const stored = storedJob(db);
  assert.equal(stored.attemptCount, 1);
  assert.equal(stored.leaseToken, owner.leaseToken);
});

test("the lease outlives the deadline of the worker holding it", async () => {
  const db = await firestoreWithQueuedJob();
  const now = Timestamp.now();

  const claimed = await claimJob(db, FIRST_TASK, now);

  const leaseExpiresAt = claimed.leaseExpiresAt;
  assert.ok(leaseExpiresAt, "a granted claim must return the lease it took");
  // `handlers.ts` enqueues with `dispatchDeadlineSeconds: 420` and runs the
  // worker with `timeoutSeconds: 420`, so a worker is gone by seven minutes. Ten
  // minutes of lease is the margin: a worker still inside its own deadline never
  // has its lease expire underneath it, which is the only way two workers reach
  // one job's processors at the same time.
  assert.equal(leaseExpiresAt.toMillis() - now.toMillis(), 10 * 60 * 1000);
  assert.ok(leaseExpiresAt.toMillis() - now.toMillis() > 420 * 1000);
  const stored = storedJob(db);
  assert.equal(stored.status, "running");
  assert.equal(stored.attemptCount, 1);
  assert.ok((stored.lastAttemptAt as Timestamp).isEqual(now));
  assert.deepEqual(db.writtenPaths(), [jobPath()]);
});

test("an expired lease is recovered, and the worker that lost it cannot commit", async () => {
  const db = await firestoreWithQueuedJob();
  const start = Timestamp.now();
  const abandoned = await claimJob(db, FIRST_TASK, start);
  const expiry = abandoned.leaseExpiresAt;
  assert.ok(expiry);

  // The boundary, both sides. One millisecond early the job is still owned.
  assert.equal(
    await claimReconciliationJob(
      db.asFirestore(),
      FIRST_TASK,
      Timestamp.fromMillis(expiry.toMillis() - 1)
    ),
    undefined
  );
  const recovered = await claimJob(db, FIRST_TASK, expiry);

  assert.notEqual(recovered.leaseToken, abandoned.leaseToken);
  assert.equal(storedJob(db).attemptCount, 2);

  // The fence, and the reason the lease is a token rather than a timestamp. A
  // worker whose lease lapsed may still be alive and still holding a
  // half-finished page; its writes have to be refused outright rather than
  // interleaved with the worker that now owns the job.
  db.clearWrites();
  await assert.rejects(
    advanceReconciliationJob(db.asFirestore(), abandoned, {phase: "stock"}),
    /lease changed/
  );
  await assert.rejects(
    finalizeReconciliationJob(db.asFirestore(), abandoned),
    /lease changed/
  );

  assert.deepEqual(db.writtenPaths(), []);
  const stored = storedJob(db);
  assert.equal(stored.status, "running");
  assert.equal(stored.leaseToken, recovered.leaseToken);
});

test("a finished job is unqueued from both routes that could redispatch it", async () => {
  const db = await firestoreWithQueuedJob();
  const claimed = await claimJob(db);
  db.clearWrites();

  assert.equal(await finalizeReconciliationJob(db.asFirestore(), claimed), undefined);

  const completed = storedJob(db);
  assert.equal(completed.status, "completed");
  assert.equal(completed.phase, "finalize");
  assert.ok(completed.completedAt instanceof Timestamp);
  assert.equal("leaseToken" in completed, false);
  assert.equal("leaseExpiresAt" in completed, false);
  // The exact mirror of what a continuation does, and the reason both are worth
  // one assertion each. `advance` writes `nextAttemptAt` so a job whose dispatch
  // was lost stays findable by `listRetryableReconciliationTasks`; `finalize`
  // removes it so the same sweep can never find this one again.
  assert.equal("nextAttemptAt" in completed, false);
  // The other route is the queue itself redelivering the task that finished it.
  assert.equal(await claimReconciliationJob(db.asFirestore(), FIRST_TASK), undefined);
  assert.equal(storedJob(db).attemptCount, 1);
  // Finishing a job is a job-state change and nothing else.
  assert.deepEqual(db.writtenPaths(), [jobPath()]);
});

/**
 * The sale-trigger fixture, for the one branch a manual job cannot reach.
 *
 * `rerunRequested` is only ever set by a sale arriving while its bucket's job is
 * already running, so the fixture is built by running that sale through
 * `registerSaleReceipt` rather than by seeding the flag. Seeding it would prove
 * that `finalize` reads a field; this proves the sale is not lost.
 */
const SALE_JOB = `dirty_${BUCKET}`;

function saleJobPath(): string {
  return `tenants/${TENANT}/reconciliation_jobs/${SALE_JOB}`;
}

function registerSale(db: FakeFirestore, saleId: string) {
  return registerSaleReceipt(db.asFirestore(), {
    tenantId: TENANT,
    saleId,
    businessDate: "2026-08-04",
    receivedAt: Timestamp.fromMillis(BUCKET + 1_000),
    saleData: {items: [{productId: "product-01", quantity: 2}]},
  });
}

test("a sale that lands mid-run reruns the job instead of completing it", async () => {
  const db = new FakeFirestore();
  const first = await registerSale(db, "sale-1");
  assert.ok(first.task, "the first sale of a bucket must enqueue its job");

  // One page done, so the job has a cursor to lose and a revision to be behind.
  const firstPage = await claimJob(db, first.task);
  const secondPage = await advanceReconciliationJob(db.asFirestore(), firstPage, {
    phase: "stock",
    productCursor: "product-05",
    productsProcessedDelta: 5,
  });
  const running = await claimJob(db, secondPage);

  // The second sale cannot enqueue a task of its own - the pass already running
  // would race it - so the only way it is not lost is the flag it leaves behind.
  const second = await registerSale(db, "sale-2");
  assert.equal(second.task, undefined);
  assert.equal(db.read(saleJobPath())?.rerunRequested, true);

  const rerun = await finalizeReconciliationJob(db.asFirestore(), running);

  assert.deepEqual(rerun, {
    tenantId: TENANT,
    jobId: SALE_JOB,
    generation: 1,
    revision: 2,
  });
  const requeued = db.read(saleJobPath());
  assert.ok(requeued);
  assert.equal(requeued.status, "queued");
  assert.equal(requeued.phase, "metrics");
  assert.equal(requeued.rerunRequested, false);
  assert.equal("leaseToken" in requeued, false);
  // A rerun is a fresh pass over the whole tenant from the metrics phase, so
  // every cursor the finished pass left behind describes work this one has not
  // done. Keeping `productCursor` would skip the first five products.
  assert.equal("productCursor" in requeued, false);
  assert.equal("pendingProductId" in requeued, false);
  // `generation`, not `revision`, is what the rerun bumps, and that is what makes
  // the new pass's task ID distinct from every dispatch of the old one.
  assert.ok(await claimReconciliationJob(db.asFirestore(), rerun));
  assert.equal(await claimReconciliationJob(db.asFirestore(), first.task), undefined);
});

/**
 * What a failed page costs the job, over the same in-memory Firestore.
 *
 * There are two retry schedules here and they are not the same thing. Cloud
 * Tasks retries the *dispatch* on the `retryConfig` in `handlers.ts`; the job
 * document carries its own `nextAttemptAt`, and `claimReconciliationJob` refuses
 * a dispatch that arrives before it. The tests below are the second one: how deep
 * it goes, where it stops, and what it refuses to touch.
 */

test("the whole reachable backoff ladder is fifteen seconds to sixteen minutes", async () => {
  const db = await firestoreWithQueuedJob();
  // Doubling from fifteen seconds. Seven rungs, because the eighth consecutive
  // failure quarantines instead of scheduling - so the one-hour cap in the
  // formula is unreachable, and the longest wait a job is ever given is 960s.
  const ladder = [15_000, 30_000, 60_000, 120_000, 240_000, 480_000, 960_000];
  let dueAt = Timestamp.now();

  for (const [index, delay] of ladder.entries()) {
    const attempt = index + 1;
    const claimed = await claimJob(db, FIRST_TASK, dueAt);

    const before = Date.now();
    await recordReconciliationFailure(
      db.asFirestore(),
      claimed,
      new HttpsError("internal", "The stock page threw.")
    );
    const after = Date.now();

    const failed = storedJob(db);
    assert.equal(failed.status, "failed", `attempt ${attempt}`);
    assert.equal(failed.consecutiveFailureCount, attempt, `attempt ${attempt}`);
    assert.equal(failed.lastErrorCode, "internal", `attempt ${attempt}`);
    assert.equal("leaseToken" in failed, false, `attempt ${attempt}`);
    const scheduled = dueAtMilliseconds(failed);
    assert.ok(
      scheduled >= before + delay && scheduled <= after + delay,
      `attempt ${attempt}: scheduled ${scheduled - before}ms out, not ${delay}ms`
    );
    dueAt = Timestamp.fromMillis(scheduled);
  }
});

test("a dispatch refused for being early is not a failure", async () => {
  const db = await firestoreWithQueuedJob();
  const claimed = await claimJob(db);
  await recordReconciliationFailure(
    db.asFirestore(),
    claimed,
    new HttpsError("internal", "The stock page threw.")
  );
  const failed = storedJob(db);
  const backoff = dueAtMilliseconds(failed);

  // The queue retries on its own schedule and knows nothing about the job's, so
  // a task arrives early and is refused. The refusal is thrown by the claim,
  // which is above the `try` in `executeReconciliationTask` that records
  // failures - and it has to stay there. If an early dispatch counted, a job
  // would quarantine itself out of retry noise alone, without ever having run a
  // page a second time.
  for (let early = 0; early < 3; early += 1) {
    await assert.rejects(
      claimReconciliationJob(db.asFirestore(), FIRST_TASK),
      /retry backoff is still active/
    );
  }

  const unchanged = storedJob(db);
  assert.equal(unchanged.status, "failed");
  assert.equal(unchanged.consecutiveFailureCount, 1);
  assert.equal(unchanged.attemptCount, failed.attemptCount);
  assert.equal(dueAtMilliseconds(unchanged), backoff);
});

test("the eighth consecutive failure quarantines the job and raises one alert", async () => {
  const db = await firestoreWithQueuedJob();
  let dueAt = Timestamp.now();

  for (let attempt = 1; attempt <= 8; attempt += 1) {
    const claimed = await claimJob(db, FIRST_TASK, dueAt);
    await recordReconciliationFailure(
      db.asFirestore(),
      claimed,
      new HttpsError("data-loss", "The job document is unreadable.")
    );
    const stored = storedJob(db);
    assert.equal(stored.consecutiveFailureCount, attempt, `attempt ${attempt}`);
    assert.equal(
      stored.status,
      attempt < 8 ? "failed" : "quarantined",
      `attempt ${attempt}`
    );
    if (attempt < 8) dueAt = Timestamp.fromMillis(dueAtMilliseconds(stored));
  }

  // Two independent locks, because there are two independent routes to a
  // dispatch. The status refuses the queue's own redelivery, and without
  // `nextAttemptAt` the retry sweep cannot see the job at all.
  const quarantined = storedJob(db);
  assert.equal("nextAttemptAt" in quarantined, false);
  assert.equal(await claimReconciliationJob(db.asFirestore(), FIRST_TASK), undefined);

  // A job that stops retrying silently is a tenant whose figures quietly stop
  // being verified, so the last failure is also the one that tells somebody.
  const alert = db.read(`platform_alerts/reconciliation_${TENANT}_${JOB}`);
  assert.ok(alert, "a quarantined job that raises no alert is one nobody is told about");
  assert.equal(alert.type, "tenant_reconciliation_quarantined");
  assert.equal(alert.severity, "critical");
  assert.equal(alert.notificationStatus, "pending");
  assert.equal(alert.errorCode, "data-loss");
  assert.equal(alert.consecutiveFailureCount, 8);
  assert.equal(alert.tenantId, TENANT);
  assert.equal(alert.jobId, JOB);
});

test("a failure from a worker that has lost the job writes nothing", async () => {
  const db = await firestoreWithQueuedJob();
  const abandoned = await claimJob(db, FIRST_TASK, Timestamp.now());
  const expiry = abandoned.leaseExpiresAt;
  assert.ok(expiry);
  const owner = await claimJob(db, FIRST_TASK, expiry);
  db.clearWrites();

  // The lost worker's own error still arrives - `executeReconciliationTask`
  // records it in a `catch` on the way out - and it must not fail a job somebody
  // else is now running, or put a backoff on it, or spend one of its eight lives.
  // It returns rather than throwing, because a failure handler that throws
  // replaces the error the caller was already reporting.
  await recordReconciliationFailure(
    db.asFirestore(),
    abandoned,
    new HttpsError("internal", "The page this worker was on threw, late.")
  );

  assert.deepEqual(db.writtenPaths(), []);
  const stored = storedJob(db);
  assert.equal(stored.status, "running");
  assert.equal(stored.consecutiveFailureCount, 0);
  assert.equal(stored.leaseToken, owner.leaseToken);
});
