import assert from "node:assert/strict";
import test from "node:test";
import {DocumentData, Timestamp, Transaction} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {FakeFirestore} from "../testing/fakeFirestore";
import {deleteSentinelPaths} from "../testing/writeSentinels";
import {
  advanceReconciliationJob,
  claimReconciliationJob,
  createManualJobInTransaction,
  recordReconciliationFailure,
  saleTriggerJobFields,
} from "./jobs";
import {DirtyJobDecision, mergeDirtyJob} from "./model";

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
  // and after the last quarantine threshold it would be refused for an hour.
  assert.ok(
    dueAtMilliseconds(advanced) < backoffMilliseconds,
    "the successful page kept the failed attempt's backoff"
  );
  assert.equal(advanced.consecutiveFailureCount, 0);
  assert.equal("lastErrorCode" in advanced, false);
  assert.ok(await claimReconciliationJob(db.asFirestore(), continuation));
});
