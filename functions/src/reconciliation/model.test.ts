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
  shiftTenderAnomalyId,
  stockCheckpointHash,
  stockComparisonOutcome,
  sweepRunId,
  trailingIsoDates,
} from "./model";
import {moneyToMinorUnits} from "../operations/domain";

/** A comparison with nothing wrong with it, for one fact at a time to be varied. */
const CLEAN_COMPARISON = {
  baselineStatus: "verified",
  chainValid: true,
  invalidMovementCount: 0,
  variance: 0,
};

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
    total: 5,
    shiftId: "shift-a",
    items: [{quantity: 1, unitPrice: 5, unitCost: 2}],
  }]);
  assert.equal(result.metrics.sales, 25);
  assert.equal(result.metrics.profit, 17);
  assert.equal(result.metrics.transactionCount, 2);
  assert.deepEqual(result.shifts.map((shift) => shift.shiftId), ["shift-a", "shift-b"]);
});

test("a sale and its shift are counted from the one total field", () => {
  // #106: `totalAmount` was the name `total` had before it, and is no longer
  // read. `finiteNonNegative` answers 0 rather than undefined, so the `??`
  // chain this was once written as could never reach its second arm - a sale
  // under the old name counted in full towards the day and contributed
  // *nothing* to its shift. One field cannot disagree with itself.
  const result = aggregateDailySales("2026-07-29", [{
    total: 5,
    shiftId: "shift-a",
    tender: "cash",
    items: [{quantity: 1, unitPrice: 5, unitCost: 2}],
  }]);
  assert.equal(result.metrics.sales, 5);
  assert.equal(result.shifts.length, 1);
  assert.equal(result.shifts[0].shiftId, "shift-a");
  assert.equal(result.shifts[0].sales, 5);
});

test("a shift's tender buckets sum to exactly what the shift took", () => {
  const result = aggregateDailySales("2026-07-29", [
    {total: 20, shiftId: "shift-a", tender: "cash", items: []},
    {total: 5, shiftId: "shift-a", tender: "mpesa", items: []},
    {total: 2.5, shiftId: "shift-a", tender: "card", items: []},
    // No tender at all: a sale written before the field existed.
    {total: 1, shiftId: "shift-a", items: []},
    // A method this system does not model, which is a data problem rather than
    // history - but a drawer declaration has no box for either, so to this
    // comparison the two are one figure.
    {total: 1.5, shiftId: "shift-a", tender: "barter", items: []},
  ]);

  const [shift] = result.shifts;
  assert.deepEqual(shift.tenders, {
    cashMinor: 2000,
    mpesaMinor: 500,
    cardMinor: 250,
    unattributedMinor: 250,
  });
  // Summing to the total is the property that lets a declaration be compared
  // method by method - it is arithmetic rather than coincidence, because the
  // buckets are filled from the same validated figure in the same pass.
  const bucketTotal = shift.tenders.cashMinor + shift.tenders.mpesaMinor +
    shift.tenders.cardMinor + shift.tenders.unattributedMinor;
  assert.equal(bucketTotal, moneyToMinorUnits(shift.sales));
});

test("a shift's generation moves when only its split moves", () => {
  // The fence the verifier is refused by. Two days with the same total and the
  // same count but a different split are different expectations, and an
  // in-flight verifier holding the older generation must not settle the newer.
  const split = (tenders: readonly string[]) => aggregateDailySales(
    "2026-07-29",
    tenders.map((tender) => ({total: 5, shiftId: "shift-a", tender, items: []}))
  ).shifts[0];

  const cash = split(["cash", "cash"]);
  const mixed = split(["cash", "mpesa"]);

  assert.equal(cash.sales, mixed.sales);
  assert.equal(cash.transactions, mixed.transactions);
  assert.notDeepEqual(cash.tenders, mixed.tenders);
});

test("the tender anomaly id is about the shift, never the aggregation pass", () => {
  // Unlike `shiftAnomalyId`, which folds a generation in. A declaration
  // difference is a fact about one shift and one drawer, so re-verifying the
  // same unresolved difference must update the record rather than mint a second
  // one an owner would have to dismiss twice - and it is what lets the verifier
  // delete the record outright once late sales bring the sides into agreement.
  assert.equal(shiftTenderAnomalyId("shift-a"), shiftTenderAnomalyId("shift-a"));
  assert.notEqual(shiftTenderAnomalyId("shift-a"), shiftTenderAnomalyId("shift-b"));
  assert.notEqual(shiftAnomalyId("shift-a", "gen-1"), shiftAnomalyId("shift-a", "gen-2"));
});

test("daily aggregation refuses a date with more shifts than one transaction may write", () => {
  // The third of the metrics phase's three bounds, and the only one that decides
  // how many documents `regenerateDailyMetric`'s transaction *writes*: every shift
  // this returns becomes one `shift_expectations` set in that transaction, beside
  // up to 200 deletions of the ones it replaces. Two hundred is therefore not a
  // preference - at 250 the widest regeneration would ask for 502 writes and
  // Firestore would refuse the whole thing.
  const sales = (count: number, from = 1) => Array.from({length: count}, (_, index) => ({
    total: 1,
    shiftId: `shift-${`${index + from}`.padStart(4, "0")}`,
    items: [{quantity: 1, unitPrice: 1, unitCost: 0}],
  }));

  // The bound is on distinct shifts, not on sales: two thousand sales across two
  // hundred shifts is inside it.
  const wide = aggregateDailySales("2026-07-29", [...sales(200), ...sales(200)]);
  assert.equal(wide.shifts.length, 200);
  assert.equal(wide.metrics.transactionCount, 400);

  assert.throws(() => aggregateDailySales("2026-07-29", sales(201)), (error: unknown) => {
    assert.ok(error instanceof HttpsError);
    assert.equal(error.code, "resource-exhausted");
    assert.match(error.message, /bounded shift aggregation limit/);
    return true;
  });

  // A sale that names no usable shift is skipped rather than counted against the
  // bound, so a date full of them cannot be refused for a reason it does not have.
  const unshifted = Array.from({length: 50}, () => ({
    total: 1,
    shiftId: "not/a/document/id",
    items: [{quantity: 1, unitPrice: 1, unitCost: 0}],
  }));
  const mixed = aggregateDailySales("2026-07-29", [...sales(200), ...unshifted]);
  assert.equal(mixed.shifts.length, 200);
  // Skipped for the expectation, still counted for the day's takings.
  assert.equal(mixed.metrics.transactionCount, 250);
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

test("a stock comparison with nothing wrong records no difference", () => {
  assert.deepEqual(stockComparisonOutcome(CLEAN_COMPARISON), {status: "matched"});
});

test("a quantity that disagrees with its ledger is named by its direction", () => {
  // **Which way it goes is the whole of what makes one worth chasing.** Short
  // means units left with nothing saying why - a sale whose ledger entry never
  // landed, or a quantity lowered outside the app, neither visible any other
  // way. Over means the books claim units no movement put there, which no client
  // write can do. Reporting both as one kind put them in front of a shopkeeper
  // as the same fact, and they are not.
  assert.deepEqual(
    stockComparisonOutcome({...CLEAN_COMPARISON, variance: -3}),
    {status: "variance", anomalyType: "stock_short_of_ledger"}
  );
  assert.deepEqual(
    stockComparisonOutcome({...CLEAN_COMPARISON, variance: 3}),
    {status: "variance", anomalyType: "stock_over_ledger"}
  );
  // Zero is neither, and writes no anomaly at all.
  assert.deepEqual(
    stockComparisonOutcome({...CLEAN_COMPARISON, variance: 0}),
    {status: "matched"}
  );
});

test("an unreadable movement names itself, not the chain it breaks", () => {
  // The regression. An unreadable movement always invalidates the chain, so a
  // decision that tested the chain first could never record this kind at all and
  // reported every unreadable ledger row as a broken checkpoint chain.
  assert.deepEqual(
    stockComparisonOutcome({
      ...CLEAN_COMPARISON,
      chainValid: false,
      invalidMovementCount: 1,
    }),
    {status: "invalid_movements", anomalyType: "invalid_stock_movement"}
  );

  // It outranks a quantity disagreement too: the figure it would be compared
  // against does not account for everything that moved.
  assert.equal(
    stockComparisonOutcome({
      ...CLEAN_COMPARISON,
      chainValid: false,
      invalidMovementCount: 2,
      variance: -5,
    }).anomalyType,
    "invalid_stock_movement"
  );
});

test("a quantity that agrees with untrustworthy evidence is not matched", () => {
  // Nothing else in this codebase records a check as passed while recording that
  // its own evidence could not be trusted.
  assert.deepEqual(
    stockComparisonOutcome({...CLEAN_COMPARISON, chainValid: false}),
    {status: "checkpoint_chain_invalid", anomalyType: "checkpoint_chain_invalid"}
  );
  assert.equal(
    stockComparisonOutcome({
      ...CLEAN_COMPARISON,
      chainValid: false,
      variance: 4,
    }).status,
    "checkpoint_chain_invalid"
  );
});

test("a rebuilt baseline names itself, and still reports a broken chain", () => {
  // **There is one baseline status left, and it is this one.**
  // `baseline_established` used to be the other: a product's first run accepted
  // its current quantity and recorded that it had established rather than
  // compared. Nothing establishes now - a first run adds the ledger up from
  // nothing like any other - so the only run that still names a baseline is one
  // that had to throw carried state away and rebuild.
  //
  // It rebuilds from the ledger too, so the variance it reports is a real
  // comparison. What the status carries is that the state was unusable, and a
  // chain that did not verify is still a difference somebody has to be told
  // about.
  assert.deepEqual(
    stockComparisonOutcome({
      ...CLEAN_COMPARISON,
      baselineStatus: "baseline_reestablished_invalid_state",
      chainValid: false,
    }),
    {
      status: "baseline_reestablished_invalid_state",
      anomalyType: "checkpoint_chain_invalid",
    }
  );
});
