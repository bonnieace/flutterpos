/**
 * What a sale actually causes on a real server.
 *
 * Every other reconciliation test in this repository is pure, and that is
 * precisely how `mergeSaleReconciliationJob` came to throw on every single sale
 * without anybody noticing: a `FieldValue.delete()` is an ordinary object until
 * Firestore serializes it, so the create payload that carried one compiled,
 * type-checked, and passed 185 unit tests before failing forever against the real
 * thing. Nothing reconciled anything for as long as that lasted.
 *
 * So these tests assert only things a real Firestore has to agree to, and they
 * exercise **both** halves of `saleTriggerJobFields` in one run: the first sale
 * of a five-minute bucket takes the `create` branch that was broken, and a later
 * sale takes the `update` branch whose sentinels really do have to clear a cursor.
 *
 * A note on what may and may not be asserted here. The task queue **is** emulated,
 * so writing a sale starts the real job pipeline, and it runs while the test is
 * still making assertions. Anything the pipeline also writes - a job's `status`,
 * `generation`, `revision`, or a dirty day's `status` - is therefore a race and is
 * deliberately not asserted *while it is still moving*. What is asserted is either
 * trigger-owned and never rewritten (`revision`, `saleReceiptCount`, `lastSaleId`,
 * the stock movement), or waited for until it reaches a state nothing rewrites
 * (`daily_metrics`, a settled `shift_expectations` record, a completed job).
 *
 * The last two tests carry the chain past the metrics phase into the half that
 * produces the differences a business is asked to correct: a closed shift whose
 * recorded summary disagrees with the immutable sales filed against it, the
 * `shift_variance` the verifier records for it, and the four writes
 * `amendShiftSummary` makes to resolve it. Every link - sale, dirty day, job,
 * metric, shift expectation, verification, difference, correction - is then proved
 * by a test rather than by one manual run.
 */
import assert from "node:assert/strict";
import { after, before, test } from "node:test";

import { deleteApp, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";

const PROJECT_ID = "demo-multitenant-reconciliation-integration";

/** `fiveMinuteBucket` in `functions/src/reconciliation/model.ts`. */
const BUCKET_MILLISECONDS = 300_000;

/**
 * How much of a bucket must remain for a two-sale test to mean anything.
 *
 * Both sales have to land in the same bucket or the second one takes the create
 * branch again and proves nothing about the update branch. The bucket comes from
 * wall-clock time, so the only honest way to make that deterministic is to wait
 * out a bucket that is nearly over.
 */
const BUCKET_HEADROOM_MILLISECONDS = 60_000;

/**
 * How long a trigger-owned document may take to appear.
 *
 * Wide enough for the **first** delivery of a cold run, which is the only one
 * that pays for the Functions emulator starting a Node worker: measured at 25.4
 * seconds on this host against the previous 30-second bound, while every later
 * delivery in the same run appeared in about 310ms. That margin was thin enough
 * that adding one more function to the fixture was sometimes enough to take the
 * first test over it - a failure that says nothing about the trigger.
 *
 * Raising it costs nothing that matters. The bound exists so a trigger that
 * never runs fails with a description of what was being waited for instead of
 * hanging, and the diagnostic line reports the time actually taken, so a run
 * that slows down is still visible.
 */
const TRIGGER_TIMEOUT_MILLISECONDS = 60_000;
const PIPELINE_TIMEOUT_MILLISECONDS = 90_000;
const POLL_INTERVAL_MILLISECONDS = 250;

/**
 * Long enough for a repeated trigger delivery to have been handled.
 *
 * Only used where the assertion is that nothing further happened, which is the
 * one thing that cannot be waited for. Observed trigger latency in this harness
 * is well under a second.
 */
const REPLAY_SETTLE_MILLISECONDS = 8_000;

/**
 * The single sale the two shift tests file against their closed shift.
 *
 * Two units at 150.00, so the sales prove 300.00 over one transaction. Both
 * tests name the figure rather than recomputing it, because the whole point of
 * the assertions is that the server derived it from the sale and not from
 * anything the test told it.
 */
const SHIFT_SALE_QUANTITY = 2;
const SHIFT_SALE_TOTAL = 300;
const SHIFT_SALE_TOTAL_MINOR = 30_000;

/**
 * The drawer count on a seeded closed shift.
 *
 * Asserted unchanged after an amendment. `closingCashMinor` is a physical count
 * of a drawer, and the single property that makes the correction path safe to
 * expose is that it can never rewrite one, so the figure has to be one a test
 * would notice moving.
 */
const CLOSED_SHIFT_CASH_MINOR = 12_000;

const PASSWORD = "Local-emulator-password-123!";

let app;
let auth;
let firestore;

before(async () => {
  requireEmulator("FIREBASE_AUTH_EMULATOR_HOST");
  requireEmulator("FIRESTORE_EMULATOR_HOST");
  requireEmulator("FUNCTIONS_EMULATOR_HOST");
  assert.equal(process.env.GCLOUD_PROJECT, PROJECT_ID);
  app = initializeApp({ projectId: PROJECT_ID }, "reconciliation-integration");
  auth = getAuth(app);
  firestore = getFirestore(app);
});

after(async () => {
  if (app) await deleteApp(app);
});

test("a sale creates the dirty day and the bucket job the trigger owns", async (t) => {
  // The regression for the defect that started this harness. Before the fix,
  // `transaction.create` was handed a payload holding two `FieldValue.delete()`
  // sentinels, Firestore rejected the entire write, and the trigger - which has
  // `retry: true` - failed forever. Not one of these four documents existed.
  const fixture = await seedTenant("first-sale");
  const sale = saleFields(fixture, { checkoutId: "sale-first", quantity: 2 });

  await firestore.doc(`tenants/${fixture.tenantId}/sales/sale-first`).create(sale);

  const receipt = await waitForDocument(
    `tenants/${fixture.tenantId}/reconciliation_sale_receipts/sale-first`,
    "the sale receipt the trigger writes",
    t,
  );
  assert.equal(receipt.get("tenantId"), fixture.tenantId);
  assert.equal(receipt.get("saleId"), "sale-first");
  assert.equal(receipt.get("businessDate"), fixture.businessDate);
  assert.equal(receipt.get("invalidLineCount"), 0);

  const jobId = receipt.get("jobId");
  assert.match(jobId, /^dirty_\d+$/, "the receipt must name its bucket job");

  const dirtyDay = await firestore
    .doc(`tenants/${fixture.tenantId}/reconciliation_dirty_days/${fixture.businessDate}`)
    .get();
  assert.equal(dirtyDay.exists, true, "the business date must be marked dirty");
  assert.equal(dirtyDay.get("tenantId"), fixture.tenantId);
  assert.equal(dirtyDay.get("businessDate"), fixture.businessDate);
  assert.equal(dirtyDay.get("revision"), 1);
  assert.equal(dirtyDay.get("saleReceiptCount"), 1);
  assert.equal(dirtyDay.get("lastSaleId"), "sale-first");
  assert.equal(dirtyDay.get("invalidLineCount"), 0);

  // Only the immutable identity the trigger stamps on the job is asserted. Both
  // branches write these identically and no processor rewrites them, so they hold
  // whether or not a pass has already claimed the job by the time this reads it.
  const job = await firestore
    .doc(`tenants/${fixture.tenantId}/reconciliation_jobs/${jobId}`)
    .get();
  assert.equal(job.exists, true, "the bucket job must have been created");
  assert.equal(job.get("tenantId"), fixture.tenantId);
  assert.equal(job.get("source"), "sale_trigger");
  assert.equal(job.get("sourceKey"), jobId.slice("dirty_".length));
  assert.equal(job.get("mode"), "incremental");
  assert.equal(job.get("localDate"), fixture.businessDate);
  assert.equal(job.get("requestedBy"), "system:sale_trigger");
  assert.equal(job.get("authority"), "canonical_tenant_data");
  assert.equal(job.get("mutatesStock"), false);
  assert.equal(job.get("checkpointKind"), "none");
  assert.equal(job.get("checkpointKey"), jobId.slice("dirty_".length));

  // The trigger owns the stock movement, and the deterministic ID is what makes a
  // replay overwrite it rather than double-count.
  const movement = await firestore
    .doc(`tenants/${fixture.tenantId}/products/${fixture.productId}` +
      "/stock_movements/sale_sale-first")
    .get();
  assert.equal(movement.exists, true, "the sale's stock movement must exist");
  assert.equal(movement.get("sourceType"), "sale");
  assert.equal(movement.get("sourceId"), "sale-first");
  assert.equal(movement.get("quantityDelta"), -2);
  assert.equal(movement.get("lineCount"), 1);
});

test("the job a sale enqueues regenerates the day's metric", async (t) => {
  // The consequence the defect actually had, asserted directly. No dirty day and
  // no job meant `processMetricsPage` never ran, so **no daily metric was ever
  // regenerated from sale activity** - on this project the nightly sweep is a
  // pub/sub schedule the emulator does not run, so nothing else would have.
  //
  // This is the one test here that waits on the whole pipeline: trigger, task
  // enqueue, claim, metrics phase.
  const fixture = await seedTenant("daily-metric");
  await firestore.doc(`tenants/${fixture.tenantId}/sales/sale-metric`)
    .create(saleFields(fixture, { checkoutId: "sale-metric", quantity: 2 }));

  const metric = await waitForDocument(
    `tenants/${fixture.tenantId}/daily_metrics/${fixture.businessDate}`,
    "the daily metric the reconciliation job regenerates",
    t,
    PIPELINE_TIMEOUT_MILLISECONDS,
  );

  assert.equal(metric.get("tenantId"), fixture.tenantId);
  assert.equal(metric.get("businessDate"), fixture.businessDate);
  // Two units at 150.00 each, which is what the sale says it sold.
  assert.equal(metric.get("sales"), 300);
  assert.equal(metric.get("transactions"), 1);
  assert.equal(metric.get("transactionCount"), 1);
  assert.equal(metric.get("shiftCount"), 1);
  assert.equal(metric.get("sourceDirtyRevision"), 1);
  assert.equal(typeof metric.get("metricGeneration"), "string");

  // The day is settled in the same transaction that wrote the metric, so by now
  // it must say so rather than still being dirty.
  const dirtyDay = await firestore
    .doc(`tenants/${fixture.tenantId}/reconciliation_dirty_days/${fixture.businessDate}`)
    .get();
  assert.equal(dirtyDay.get("status"), "clean");
  assert.equal(dirtyDay.get("processedRevision"), 1);

  // And the shift the sale belonged to now has something to be verified against.
  const expectations = await firestore
    .collection(`tenants/${fixture.tenantId}/shift_expectations`)
    .where("businessDate", "==", fixture.businessDate)
    .get();
  assert.equal(expectations.size, 1);
  assert.equal(expectations.docs[0].get("shiftId"), fixture.shiftId);
  assert.equal(expectations.docs[0].get("sales"), 300);
  assert.equal(expectations.docs[0].get("transactions"), 1);
});

test("a second sale in the same bucket clears the cursor the last pass left", async (t) => {
  // The other half of `saleTriggerJobFields`, and the half where a sentinel is
  // correct: a job returning to `queued` starts its phases again, so a cursor
  // left by a previous pass describes work this pass has not done and must go.
  //
  // The job is put into a settled state by hand rather than by waiting for a real
  // pass, for two reasons. It makes `mergeDirtyJob` return `queued` - and so the
  // sentinel-bearing update branch - deterministically; and a real pass would make
  // this test depend on the entire task pipeline to assert one field.
  const fixture = await seedTenant("second-sale");
  await waitForBucketHeadroom(t);

  await firestore.doc(`tenants/${fixture.tenantId}/sales/sale-one`)
    .create(saleFields(fixture, { checkoutId: "sale-one", quantity: 1 }));
  const firstReceipt = await waitForDocument(
    `tenants/${fixture.tenantId}/reconciliation_sale_receipts/sale-one`,
    "the first sale's receipt",
    t,
  );
  const jobId = firstReceipt.get("jobId");
  const jobRef = firestore.doc(`tenants/${fixture.tenantId}/reconciliation_jobs/${jobId}`);

  await jobRef.update({
    status: "completed",
    phase: "finalize",
    productCursor: "product-halfway",
    pendingProductId: fixture.productId,
    consecutiveFailureCount: 4,
  });
  assert.equal((await jobRef.get()).get("productCursor"), "product-halfway");

  await firestore.doc(`tenants/${fixture.tenantId}/sales/sale-two`)
    .create(saleFields(fixture, { checkoutId: "sale-two", quantity: 3 }));
  const secondReceipt = await waitForDocument(
    `tenants/${fixture.tenantId}/reconciliation_sale_receipts/sale-two`,
    "the second sale's receipt",
    t,
  );

  assert.equal(
    secondReceipt.get("jobId"),
    jobId,
    "both sales must share a bucket or this proves nothing about the update branch",
  );

  // A sale-trigger job goes metrics then shifts and never enters the stock phase,
  // so nothing downstream can put a cursor back. Absence here is stable.
  const job = await jobRef.get();
  assert.equal(
    job.get("productCursor"),
    undefined,
    "the requeue must clear the cursor a previous pass left",
  );
  assert.equal(job.get("pendingProductId"), undefined);
  assert.equal(job.get("consecutiveFailureCount"), 0);

  const dirtyDay = await firestore
    .doc(`tenants/${fixture.tenantId}/reconciliation_dirty_days/${fixture.businessDate}`)
    .get();
  assert.equal(dirtyDay.get("revision"), 2);
  assert.equal(dirtyDay.get("saleReceiptCount"), 2);
  assert.equal(dirtyDay.get("lastSaleId"), "sale-two");
});

test("a replayed sale is registered once, not twice", async (t) => {
  // The trigger has `retry: true`, so a delivery may repeat. The receipt document
  // is what makes that idempotent, and the dirty day's counters are where a double
  // count would show.
  const fixture = await seedTenant("replayed-sale");
  const path = `tenants/${fixture.tenantId}/sales/sale-replay`;
  const fields = saleFields(fixture, { checkoutId: "sale-replay", quantity: 4 });

  await firestore.doc(path).create(fields);
  await waitForDocument(
    `tenants/${fixture.tenantId}/reconciliation_sale_receipts/sale-replay`,
    "the replayed sale's receipt",
    t,
  );

  // Re-creating the sale is the closest a test can get to a repeated delivery.
  // The receipt is deliberately left in place - it is the idempotency record, and
  // deleting it would be testing a state the trigger never sees.
  await firestore.doc(path).delete();
  await firestore.doc(path).create(fields);
  await settle(REPLAY_SETTLE_MILLISECONDS);

  const dirtyDay = await firestore
    .doc(`tenants/${fixture.tenantId}/reconciliation_dirty_days/${fixture.businessDate}`)
    .get();
  assert.equal(dirtyDay.get("saleReceiptCount"), 1, "a replay must not count twice");
  assert.equal(dirtyDay.get("revision"), 1);
  assert.equal(dirtyDay.get("lastSaleId"), "sale-replay");
});

test("a sale with an unusable line is recorded as an anomaly, not dropped", async (t) => {
  // The one path that writes a `reconciliation_anomalies` document from the
  // trigger itself. A malformed line must not take the good lines down with it.
  const fixture = await seedTenant("invalid-line");
  const sale = saleFields(fixture, { checkoutId: "sale-invalid", quantity: 1 });
  sale.items = [
    ...sale.items,
    { productId: "", name: "Nameless", quantity: 0, unitPriceMinor: 0, lineTotalMinor: 0 },
  ];

  await firestore.doc(`tenants/${fixture.tenantId}/sales/sale-invalid`).create(sale);
  const receipt = await waitForDocument(
    `tenants/${fixture.tenantId}/reconciliation_sale_receipts/sale-invalid`,
    "the receipt for a sale with a bad line",
    t,
  );

  assert.equal(receipt.get("invalidLineCount"), 1);
  const anomalies = await firestore
    .collection(`tenants/${fixture.tenantId}/reconciliation_anomalies`)
    .where("sourceId", "==", "sale-invalid")
    .get();
  assert.equal(anomalies.size, 1);
  assert.equal(anomalies.docs[0].get("anomalyType"), "invalid_sale_lines");
  assert.equal(anomalies.docs[0].get("invalidLineCount"), 1);
  assert.equal(anomalies.docs[0].get("sourceType"), "sale");

  // The good line still moved stock, which is the point of counting the bad one
  // rather than refusing the whole sale.
  const movement = await firestore
    .doc(`tenants/${fixture.tenantId}/products/${fixture.productId}` +
      "/stock_movements/sale_sale-invalid")
    .get();
  assert.equal(movement.get("quantityDelta"), -1);
  assert.equal(movement.get("lineCount"), 1);

  const dirtyDay = await firestore
    .doc(`tenants/${fixture.tenantId}/reconciliation_dirty_days/${fixture.businessDate}`)
    .get();
  assert.equal(dirtyDay.get("invalidLineCount"), 1);
});

test("the shifts phase reports a closed shift that its sales disagree with", async (t) => {
  // The half of the pipeline the five tests above stop short of. A sale-trigger
  // job runs metrics then shifts, and until this test the fixture seeded no
  // `shifts` document at all - so every run reached the shifts phase, found the
  // shift its expectation named missing, and recorded `invalid_or_missing_shift`
  // without anything noticing. The variance path had never run against a real
  // server.
  //
  // The seeded shift records 0.00 over 0 transactions: the state a shift is left
  // in when it closes before the sale filed against it reaches the server, which
  // is exactly what `scripts/plant-late-sale.js` engineers by hand. Both recorded
  // figures are then wrong, so the verifier's two comparisons and the two figures
  // it records are individually observable rather than one of them being zero by
  // accident.
  const fixture = await seedTenant("shift-variance", {
    closedShift: { totalSalesMinor: 0, transactionCount: 0 },
  });
  await firestore.doc(`tenants/${fixture.tenantId}/sales/sale-variance`).create(
    saleFields(fixture, {
      checkoutId: "sale-variance",
      quantity: SHIFT_SALE_QUANTITY,
    }),
  );

  const receipt = await waitForDocument(
    `tenants/${fixture.tenantId}/reconciliation_sale_receipts/sale-variance`,
    "the sale receipt the trigger writes",
    t,
  );
  const expectation = await waitForVerifiedExpectation(fixture, t);
  const generation = expectation.get("generation");

  // What the sales prove, and that verification settled against that exact
  // generation rather than an older one.
  assert.equal(expectation.get("sales"), SHIFT_SALE_TOTAL);
  assert.equal(expectation.get("transactions"), 1);
  assert.equal(expectation.get("verificationStatus"), "variance");
  assert.equal(expectation.get("verifiedGeneration"), generation);

  // The verification record is the evidence the difference was measured, kept
  // whatever is later done about it.
  const verifications = await firestore
    .collection(`tenants/${fixture.tenantId}/shift_verifications`)
    .where("shiftId", "==", fixture.shiftId)
    .get();
  assert.equal(verifications.size, 1);
  const verification = verifications.docs[0];
  assert.equal(verification.get("status"), "variance");
  assert.equal(verification.get("generation"), generation);
  assert.equal(verification.get("businessDate"), fixture.businessDate);
  assert.equal(verification.get("expectedSalesMinor"), SHIFT_SALE_TOTAL_MINOR);
  assert.equal(verification.get("observedSalesMinor"), 0);
  assert.equal(verification.get("salesVarianceMinor"), -SHIFT_SALE_TOTAL_MINOR);
  assert.equal(verification.get("salesVariance"), -SHIFT_SALE_TOTAL);
  assert.equal(verification.get("expectedTransactions"), 1);
  assert.equal(verification.get("observedTransactions"), 0);
  assert.equal(verification.get("transactionVariance"), -1);
  // Reconciliation reports; it never rewrites the shift on its own.
  assert.equal(verification.get("mutatesShift"), false);

  // And the difference is listed where the app reads unresolved ones from.
  const anomalies = await listShiftAnomalies(fixture);
  assert.equal(anomalies.length, 1);
  assert.equal(anomalies[0].get("anomalyType"), "shift_variance");
  assert.equal(anomalies[0].get("salesVariance"), -SHIFT_SALE_TOTAL);
  assert.equal(anomalies[0].get("transactionVariance"), -1);
  assert.equal(anomalies[0].get("mutatesShift"), false);
  assert.equal(anomalies[0].get("jobId"), receipt.get("jobId"));

  // Waited for rather than raced: once the job is `completed` nothing rewrites
  // its counters, and this tenant holds exactly one expectation, so the phase
  // having run once with one difference is a stable fact rather than a snapshot.
  const job = await waitForCompletedJob(fixture, receipt.get("jobId"), t);
  assert.equal(job.get("phase"), "finalize");
  assert.equal(job.get("shiftsProcessed"), 1);
  assert.equal(job.get("shiftVarianceCount"), 1);
});

test("an administrator amends the shift to the total its sales prove", async (t) => {
  // The correction the difference above exists to be resolved by, against a real
  // server: one transaction that rewrites the shift, settles the expectation,
  // removes the listed difference, and files the immutable record of what it did.
  const fixture = await seedTenant("shift-amendment", {
    closedShift: { totalSalesMinor: 0, transactionCount: 0 },
  });
  await firestore.doc(`tenants/${fixture.tenantId}/sales/sale-amendment`).create(
    saleFields(fixture, {
      checkoutId: "sale-amendment",
      quantity: SHIFT_SALE_QUANTITY,
    }),
  );

  const expectation = await waitForVerifiedExpectation(fixture, t);
  assert.equal(expectation.get("verificationStatus"), "variance");
  const generation = expectation.get("generation");
  const listed = await listShiftAnomalies(fixture);
  assert.equal(listed.length, 1);
  const anomalyId = listed[0].id;

  const actor = await seedAmendmentActor(fixture);
  const idToken = await signIn(actor.email);
  const request = {
    tenantId: fixture.tenantId,
    shiftId: fixture.shiftId,
    reason: "A sale reached the server after this shift closed.",
    requestId: "shift-amendment-emulator-1",
  };
  const response = await callFunction("amendShiftSummary", idToken, request);

  assert.equal(response.tenantId, fixture.tenantId);
  assert.equal(response.shiftId, fixture.shiftId);
  assert.equal(response.businessDate, fixture.businessDate);
  assert.equal(response.previousTotalSalesMinor, 0);
  assert.equal(response.previousTransactionCount, 0);
  assert.equal(response.totalSalesMinor, SHIFT_SALE_TOTAL_MINOR);
  assert.equal(response.transactionCount, 1);
  assert.equal(response.salesVarianceMinor, -SHIFT_SALE_TOTAL_MINOR);
  assert.equal(response.transactionVariance, -1);
  // The verifier and the amendment callable derive this ID from the same shift
  // and generation in two different modules. If they ever disagreed, the listed
  // difference would survive its own correction and this would be null.
  assert.equal(response.clearedAnomalyId, anomalyId);

  // First write: the shift now holds what its sales prove - and still holds the
  // cash somebody counted, which this path must never be able to move.
  const shift = await firestore
    .doc(`tenants/${fixture.tenantId}/shifts/${fixture.shiftId}`)
    .get();
  assert.equal(shift.get("totalSalesMinor"), SHIFT_SALE_TOTAL_MINOR);
  assert.equal(shift.get("totalSales"), SHIFT_SALE_TOTAL);
  assert.equal(shift.get("transactionCount"), 1);
  assert.equal(shift.get("summaryAmendmentId"), response.amendmentId);
  assert.equal(shift.get("summaryAmendedGeneration"), generation);
  assert.equal(shift.get("summaryAmendmentCount"), 1);
  assert.equal(shift.get("closingCashMinor"), CLOSED_SHIFT_CASH_MINOR);
  assert.equal(shift.get("closingCash"), CLOSED_SHIFT_CASH_MINOR / 100);
  assert.equal(shift.get("status"), "closed");

  // Second write: the expectation is settled as amended rather than left pending,
  // because verification happened inside that same transaction.
  const settled = await expectation.ref.get();
  assert.equal(settled.get("needsVerification"), false);
  assert.equal(settled.get("verificationStatus"), "amended");
  assert.equal(settled.get("amendmentId"), response.amendmentId);
  assert.equal(settled.get("generation"), generation);

  // Third write: the resolved difference leaves the list of open ones.
  assert.equal((await listShiftAnomalies(fixture)).length, 0);
  assert.equal(
    (await firestore
      .doc(`tenants/${fixture.tenantId}/reconciliation_anomalies/${anomalyId}`)
      .get()).exists,
    false,
  );

  // Fourth write: the record that keeps the difference after the list drops it.
  const amendment = await firestore
    .doc(`tenants/${fixture.tenantId}/shift_amendments/${response.amendmentId}`)
    .get();
  assert.equal(amendment.exists, true, "the amendment must be recorded");
  assert.equal(amendment.get("tenantId"), fixture.tenantId);
  assert.equal(amendment.get("shiftId"), fixture.shiftId);
  assert.equal(amendment.get("staffId"), `cashier-${fixture.tenantId}`);
  assert.equal(amendment.get("businessDate"), fixture.businessDate);
  assert.equal(amendment.get("sourceType"), "reconciliation_shift_variance");
  assert.equal(amendment.get("expectationId"), expectation.id);
  assert.equal(amendment.get("expectationGeneration"), generation);
  assert.equal(amendment.get("previousTotalSalesMinor"), 0);
  assert.equal(amendment.get("previousTotalSales"), 0);
  assert.equal(amendment.get("previousTransactionCount"), 0);
  assert.equal(amendment.get("previousRepresentationsAgreed"), true);
  assert.equal(amendment.get("totalSalesMinor"), SHIFT_SALE_TOTAL_MINOR);
  assert.equal(amendment.get("transactionCount"), 1);
  assert.equal(amendment.get("salesVarianceMinor"), -SHIFT_SALE_TOTAL_MINOR);
  assert.equal(amendment.get("transactionVariance"), -1);
  assert.equal(amendment.get("clearedAnomalyId"), anomalyId);
  assert.equal(amendment.get("mutatesCountedCash"), false);
  assert.equal(amendment.get("reason"), request.reason);
  assert.equal(amendment.get("actorUid"), actor.uid);

  const audit = await firestore
    .doc(`tenants/${fixture.tenantId}/audit_logs/${response.amendmentId}`)
    .get();
  assert.equal(audit.get("eventType"), "shift_summary_amended");
  assert.equal(audit.get("actorUid"), actor.uid);
  assert.equal(audit.get("mutatesCountedCash"), false);

  // A repeated delivery of the same request returns the stored answer and does
  // not amend anything a second time. The shift's amendment count is where a
  // second application would show.
  const replay = await callFunction("amendShiftSummary", idToken, request);
  assert.deepEqual(replay, response);
  assert.equal(
    (await firestore
      .doc(`tenants/${fixture.tenantId}/shifts/${fixture.shiftId}`)
      .get()).get("summaryAmendmentCount"),
    1,
  );

  // And a *fresh* request is refused, because settling the expectation as
  // `amended` in the same transaction makes a second correction of this
  // generation impossible rather than merely pointless.
  await assertCallableError("amendShiftSummary", idToken, {
    ...request,
    requestId: "shift-amendment-emulator-2",
  }, "FAILED_PRECONDITION");
});

function requireEmulator(name) {
  const value = process.env[name];
  if (!value || !/^127\.0\.0\.1:\d+$/.test(value)) {
    throw new Error(`${name} must target a local emulator, received ${value}`);
  }
}

/** Nairobi's calendar date, matching `nairobiDate` in the Functions model. */
function businessDateFor(instant) {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-GB", {
      timeZone: "Africa/Nairobi",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    })
      .formatToParts(instant)
      .map((part) => [part.type, part.value]),
  );
  return `${parts.year}-${parts.month}-${parts.day}`;
}

/**
 * One tenant with one product, each test in its own tenant.
 *
 * Per-tenant isolation is what lets these run in any order against a shared
 * emulator: the dirty-day counters are per business, and a shared tenant would
 * make every assertion about `saleReceiptCount` depend on what ran before it.
 */
async function seedTenant(suffix, options = {}) {
  const tenantId = `tenant-${suffix}`;
  const productId = `product-${suffix}`;
  const shiftId = `shift-${suffix}`;
  const now = Timestamp.now();
  const businessDate = businessDateFor(now.toDate());
  const batch = firestore.batch();
  batch.set(firestore.doc(`tenants/${tenantId}`), {
    tenantId,
    name: `Reconciliation ${suffix}`,
    slug: `reconciliation-${suffix}`,
    status: "active",
    ownerUid: `owner-${suffix}`,
    currency: "KES",
    createdAt: now,
    updatedAt: now,
  });
  batch.set(firestore.doc(`tenants/${tenantId}/products/${productId}`), {
    productId,
    tenantId,
    name: `Product ${suffix}`,
    priceMinor: 15_000,
    price: 150,
    quantity: 100,
    createdAt: now,
    updatedAt: now,
  });
  if (options.closedShift) {
    batch.set(firestore.doc(`tenants/${tenantId}/shifts/${shiftId}`), {
      shiftId,
      tenantId,
      // The cashier `saleFields` names, so the amendment record's `staffId` is
      // the person the corrected shift actually belongs to.
      staffId: `cashier-${tenantId}`,
      deviceId: `device-${tenantId}`,
      businessDate,
      status: "closed",
      // Both instants are server-owned in `firestore.rules`; the fixture writes
      // them through the Admin SDK, which is the only writer that may.
      startTime: now,
      endTime: now,
      closingCashMinor: CLOSED_SHIFT_CASH_MINOR,
      closingCash: CLOSED_SHIFT_CASH_MINOR / 100,
      ...closedShiftSummary(options.closedShift),
    });
  }
  await batch.commit();
  return { tenantId, productId, shiftId, businessDate };
}

/**
 * The three summary fields a close writes, from one figure.
 *
 * `TenantShiftCloseIntent.updateData` in `lib/shift/tenant_shift.dart` derives
 * `totalSales` from `totalSalesMinor`, and the shift verifier compares the
 * major-unit figure, so a fixture that let the two disagree would be testing an
 * internally inconsistent shift rather than a reconciliation variance.
 */
function closedShiftSummary({ totalSalesMinor, transactionCount }) {
  return {
    totalSalesMinor,
    totalSales: totalSalesMinor / 100,
    transactionCount,
  };
}

/**
 * An administrator of the seeded business, able to sign in and be authorized.
 *
 * `amendShiftSummary` admits owners and administrators only - deliberately
 * narrower than the owner/admin/manager set that *reads* the difference it
 * resolves. The seeded role is `admin` because an `owner` staff record must also
 * be named by the tenant's `ownerUid`, and these fixtures are owned by a uid
 * with no Auth account; the authorization path is otherwise identical.
 */
async function seedAmendmentActor(fixture) {
  const uid = `admin-${fixture.tenantId}`;
  const email = `${uid}@integration.example.test`;
  const now = Timestamp.now();
  await auth.createUser({ uid, email, password: PASSWORD, emailVerified: true });
  await Promise.all([
    firestore.doc(`users/${uid}`).set({
      email,
      accountType: "tenant_user",
      identityOrigin: "tenant_signup",
      globalStatus: "active",
      createdAt: now,
      updatedAt: now,
    }),
    firestore.doc(`tenants/${fixture.tenantId}/staff/${uid}`).set({
      uid,
      tenantId: fixture.tenantId,
      email,
      role: "admin",
      status: "active",
      createdAt: now,
      updatedAt: now,
    }),
  ]);
  return { uid, email };
}

async function signIn(email) {
  const host = process.env.FIREBASE_AUTH_EMULATOR_HOST;
  const response = await fetch(
    `http://${host}/identitytoolkit.googleapis.com/v1/` +
      "accounts:signInWithPassword?key=fake-api-key",
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email, password: PASSWORD, returnSecureToken: true }),
    },
  );
  const body = await response.json();
  assert.equal(response.ok, true, JSON.stringify(body));
  assert.equal(typeof body.idToken, "string");
  return body.idToken;
}

async function callFunction(functionName, idToken, data) {
  const host = process.env.FUNCTIONS_EMULATOR_HOST;
  const response = await fetch(
    `http://${host}/${PROJECT_ID}/us-central1/${functionName}`,
    {
      method: "POST",
      headers: {
        authorization: `Bearer ${idToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ data }),
    },
  );
  const body = await response.json();
  assert.equal(response.ok, true, JSON.stringify(body));
  assert.equal(body.error, undefined, JSON.stringify(body));
  assert.equal(typeof body.result, "object", JSON.stringify(body));
  return body.result;
}

async function assertCallableError(functionName, idToken, data, expectedStatus) {
  const host = process.env.FUNCTIONS_EMULATOR_HOST;
  const response = await fetch(
    `http://${host}/${PROJECT_ID}/us-central1/${functionName}`,
    {
      method: "POST",
      headers: {
        authorization: `Bearer ${idToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ data }),
    },
  );
  const body = await response.json();
  assert.equal(response.ok, false, JSON.stringify(body));
  assert.equal(body.error?.status, expectedStatus, JSON.stringify(body));
}

/**
 * A sale in the shape `_saleFields` produces in `lib/checkout/checkout_sale.dart`.
 *
 * Only the fields the trigger reads have to be right - `businessDate` and `items` -
 * but the rest are carried so that an assertion about what reconciliation computes
 * from a sale is not quietly measuring a fixture that never looked like a real one.
 */
function saleFields(
  { tenantId, productId, shiftId, businessDate },
  { checkoutId, quantity },
) {
  const unitPriceMinor = 15_000;
  const lineTotalMinor = unitPriceMinor * quantity;
  return {
    checkoutId,
    tenantId,
    soldById: `cashier-${tenantId}`,
    payloadHash: `hash-${checkoutId}`,
    payloadSchemaVersion: 2,
    tender: "cash",
    currency: "KES",
    businessDate,
    clientCreatedAtMs: Timestamp.now().toMillis(),
    shiftId,
    deviceId: `device-${tenantId}`,
    receiptNumber: `CT-ABC-${businessDate.split("-").join("")}-0001`,
    receiptSequence: 1,
    items: [
      {
        productId,
        name: `Product ${productId}`,
        quantity,
        unitPriceMinor,
        unitPrice: unitPriceMinor / 100,
        lineTotalMinor,
        lineTotal: lineTotalMinor / 100,
      },
    ],
    subtotalMinor: lineTotalMinor,
    subtotal: lineTotalMinor / 100,
    discountMinor: 0,
    discount: 0,
    totalMinor: lineTotalMinor,
    total: lineTotalMinor / 100,
    createdAt: FieldValue.serverTimestamp(),
  };
}

/** Waits until the current five-minute bucket has room for two sales. */
async function waitForBucketHeadroom(t) {
  const remaining = BUCKET_MILLISECONDS - (Timestamp.now().toMillis() % BUCKET_MILLISECONDS);
  if (remaining >= BUCKET_HEADROOM_MILLISECONDS) return;
  t.diagnostic(`waiting ${remaining}ms for the next five-minute bucket`);
  await settle(remaining + 500);
}

/**
 * Polls for a document a background trigger or task is expected to write.
 *
 * A trigger is asynchronous, so there is no write to await. The failure names what
 * was being waited for, because a bare timeout in an emulator run is otherwise
 * indistinguishable from the emulator never having started.
 */
async function waitForDocument(
  path,
  description,
  t,
  timeoutMilliseconds = TRIGGER_TIMEOUT_MILLISECONDS,
) {
  return waitFor(async () => {
    const snapshot = await firestore.doc(path).get();
    return snapshot.exists ? snapshot : undefined;
  }, `${description} at ${path}`, t, timeoutMilliseconds);
}

/**
 * Polls `read` until it answers with something rather than `undefined`.
 *
 * The predicate lives in the caller because "has this appeared" and "has this
 * stopped moving" are different questions and the phases past the trigger need
 * the second one: a `shift_expectations` record exists from the moment the
 * metrics phase writes it, and only says what verification concluded once the
 * shifts phase has settled it.
 */
async function waitFor(read, description, t, timeoutMilliseconds) {
  const startedAt = Timestamp.now().toMillis();
  const deadline = startedAt + timeoutMilliseconds;
  for (;;) {
    const answer = await read();
    if (answer !== undefined) {
      const waited = Timestamp.now().toMillis() - startedAt;
      if (waited > POLL_INTERVAL_MILLISECONDS) {
        t.diagnostic(`${description} after ${waited}ms`);
      }
      return answer;
    }
    if (Timestamp.now().toMillis() >= deadline) {
      throw new Error(
        `Timed out after ${timeoutMilliseconds}ms waiting for ${description}. ` +
          "If the trigger or the task worker threw, the Functions emulator log says so.",
      );
    }
    await settle(POLL_INTERVAL_MILLISECONDS);
  }
}

/**
 * The tenant's one shift expectation, once the shifts phase has verified it.
 *
 * Queried by `shiftId` rather than addressed by the digest `shiftExpectationId`
 * produces, so that the verifier and the amendment callable agreeing on that
 * digest stays something these tests can observe rather than something they
 * assume. Each test has its own tenant and one shift, so a size other than one
 * means the metrics phase has not written it yet.
 */
async function waitForVerifiedExpectation(fixture, t) {
  return waitFor(async () => {
    const snapshot = await firestore
      .collection(`tenants/${fixture.tenantId}/shift_expectations`)
      .where("shiftId", "==", fixture.shiftId)
      .get();
    if (snapshot.size !== 1) return undefined;
    const expectation = snapshot.docs[0];
    return expectation.get("needsVerification") === false ? expectation : undefined;
  }, `the verified expectation for ${fixture.shiftId}`, t, PIPELINE_TIMEOUT_MILLISECONDS);
}

/** The job the sale enqueued, once nothing further will rewrite its counters. */
async function waitForCompletedJob(fixture, jobId, t) {
  return waitFor(async () => {
    const job = await firestore
      .doc(`tenants/${fixture.tenantId}/reconciliation_jobs/${jobId}`)
      .get();
    return job.get("status") === "completed" ? job : undefined;
  }, `reconciliation job ${jobId} to complete`, t, PIPELINE_TIMEOUT_MILLISECONDS);
}

/** Every difference currently listed against one shift. */
async function listShiftAnomalies(fixture) {
  const snapshot = await firestore
    .collection(`tenants/${fixture.tenantId}/reconciliation_anomalies`)
    .where("shiftId", "==", fixture.shiftId)
    .get();
  return snapshot.docs;
}

async function settle(milliseconds) {
  await new Promise((resolve) => setTimeout(resolve, milliseconds));
}
