import assert from "node:assert/strict";
import test from "node:test";
import {DocumentData, FieldValue} from "firebase-admin/firestore";
import {saleTriggerJobFields} from "./jobs";
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

/**
 * Whether a payload carries a `FieldValue.delete()` sentinel anywhere.
 *
 * `isEqual` is the public way to ask: a sentinel is an ordinary object until the
 * write is serialized, which is exactly why the original defect compiled, passed
 * every unit test, and then failed against a real Firestore.
 */
function deletedKeys(payload: DocumentData): string[] {
  const sentinel = FieldValue.delete();
  return Object.entries(payload)
    .filter(([, value]) => value instanceof FieldValue && value.isEqual(sentinel))
    .map(([key]) => key);
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

  assert.deepEqual(deletedKeys(create), []);
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
    assert.deepEqual(deletedKeys(create), [], status);
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
    deletedKeys(update).sort(),
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

  assert.deepEqual(deletedKeys(update), []);
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
