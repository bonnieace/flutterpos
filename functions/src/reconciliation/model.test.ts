import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {
  aggregateDailySales,
  digest,
  fiveMinuteBucket,
  isoWeekKey,
  mergeDirtyJob,
  monthlyShardDay,
  reconciliationTaskId,
  requireDiscoveryPayload,
  shiftAnomalyId,
  shiftExpectationId,
  stockCheckpointHash,
  sweepRunId,
  trailingIsoDates,
} from "./model";

test("sale receipt buckets are stable five-minute windows", () => {
  assert.equal(
    fiveMinuteBucket(new Date("2026-07-29T08:07:59.999Z")),
    Date.parse("2026-07-29T08:05:00.000Z")
  );
});

test("dirty jobs merge while queued and request one rerun while running", () => {
  assert.deepEqual(mergeDirtyJob(), {
    status: "queued",
    phase: "metrics",
    generation: 0,
    revision: 0,
    rerunRequested: false,
    enqueue: true,
  });
  const running = mergeDirtyJob({
    status: "running",
    phase: "stock",
    generation: 2,
    revision: 7,
    rerunRequested: false,
  });
  assert.equal(running.rerunRequested, true);
  assert.equal(running.enqueue, false);
  const completed = mergeDirtyJob({...running, status: "completed"});
  assert.equal(completed.generation, 3);
  assert.equal(completed.status, "queued");
  const quarantined = mergeDirtyJob({...running, status: "quarantined"});
  assert.equal(quarantined.status, "quarantined");
  assert.equal(quarantined.enqueue, false);
});

test("shift expectation and anomaly IDs are addressed by what they are about", () => {
  // The metrics writer creates the expectation, the verifier settles it, and the
  // amendment callable reads it; the verifier records the anomaly and the
  // amendment clears it. All of them must agree, so both IDs live here.
  assert.equal(
    shiftExpectationId("2026-07-31", "shift-1"),
    `se_${digest(["2026-07-31", "shift-1"])}`
  );
  assert.equal(
    shiftAnomalyId("shift-1", "generation-one"),
    `shift_${digest(["shift-1", "generation-one"])}`
  );
  // A different day, shift, or generation is a different record.
  assert.notEqual(
    shiftExpectationId("2026-07-31", "shift-1"),
    shiftExpectationId("2026-07-30", "shift-1")
  );
  assert.notEqual(
    shiftAnomalyId("shift-1", "generation-one"),
    shiftAnomalyId("shift-1", "generation-two")
  );
});

test("task IDs include generation and revision", () => {
  const base = {tenantId: "tenant-a", jobId: "dirty_123", generation: 0, revision: 0};
  assert.notEqual(reconciliationTaskId(base), reconciliationTaskId({...base, revision: 1}));
  assert.notEqual(reconciliationTaskId(base), reconciliationTaskId({...base, generation: 1}));
});

test("discovery payloads bind the deterministic run to kind and date", () => {
  const localDate = "2026-07-29";
  assert.doesNotThrow(() => requireDiscoveryPayload({
    runId: sweepRunId("nightly", localDate),
    kind: "nightly",
    localDate,
    page: 0,
  }));
  assert.throws(() => requireDiscoveryPayload({
    runId: sweepRunId("weekly", localDate),
    kind: "nightly",
    localDate,
    page: 0,
  }), HttpsError);
});

test("monthly shards cover only safe calendar days and are stable", () => {
  const first = monthlyShardDay("tenant-a");
  assert.ok(first >= 1 && first <= 28);
  assert.equal(monthlyShardDay("tenant-a"), first);
});

test("date helpers produce bounded chronological windows and ISO weeks", () => {
  assert.deepEqual(trailingIsoDates("2026-03-02", 3), [
    "2026-02-28",
    "2026-03-01",
    "2026-03-02",
  ]);
  assert.equal(isoWeekKey("2026-01-01"), "2026-W01");
});

test("daily aggregation retains transaction and shift expectations", () => {
  const result = aggregateDailySales("2026-07-29", [{
    total: 20,
    shiftId: "shift-b",
    items: [{quantity: 2, unitPrice: 10, unitCost: 3}],
  }, {
    totalAmount: 5,
    shiftId: "shift-a",
    items: [{quantity: 1, price: 5, buyingPrice: 2}],
  }]);
  assert.equal(result.metrics.sales, 25);
  assert.equal(result.metrics.profit, 17);
  assert.equal(result.metrics.transactionCount, 2);
  assert.deepEqual(result.shifts.map((shift) => shift.shiftId), ["shift-a", "shift-b"]);
});

test("checkpoint hashes chain expected and observed values separately", () => {
  const input = {
    tenantId: "tenant-a",
    productId: "product-a",
    checkpointKey: "2026-W31",
    expectedQuantity: 10,
    observedQuantity: 9,
    movementCursor: "cursor-a",
  };
  const first = stockCheckpointHash(input);
  assert.notEqual(first, stockCheckpointHash({...input, observedQuantity: 10}));
  assert.notEqual(first, stockCheckpointHash({...input, previousCheckpointHash: first}));
});
