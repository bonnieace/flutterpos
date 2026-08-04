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
 * deliberately not asserted. What is asserted is either trigger-owned and never
 * rewritten (`revision`, `saleReceiptCount`, `lastSaleId`, the stock movement) or
 * waited for properly (`daily_metrics`).
 */
import assert from "node:assert/strict";
import { after, before, test } from "node:test";

import { deleteApp, initializeApp } from "firebase-admin/app";
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

const TRIGGER_TIMEOUT_MILLISECONDS = 30_000;
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

let app;
let firestore;

before(async () => {
  requireEmulator("FIREBASE_AUTH_EMULATOR_HOST");
  requireEmulator("FIRESTORE_EMULATOR_HOST");
  requireEmulator("FUNCTIONS_EMULATOR_HOST");
  assert.equal(process.env.GCLOUD_PROJECT, PROJECT_ID);
  app = initializeApp({ projectId: PROJECT_ID }, "reconciliation-integration");
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
async function seedTenant(suffix) {
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
  await batch.commit();
  return { tenantId, productId, shiftId, businessDate };
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
  const startedAt = Timestamp.now().toMillis();
  const deadline = startedAt + timeoutMilliseconds;
  for (;;) {
    const snapshot = await firestore.doc(path).get();
    if (snapshot.exists) {
      const waited = Timestamp.now().toMillis() - startedAt;
      if (waited > POLL_INTERVAL_MILLISECONDS) {
        t.diagnostic(`${description} appeared after ${waited}ms`);
      }
      return snapshot;
    }
    if (Timestamp.now().toMillis() >= deadline) {
      throw new Error(
        `Timed out after ${timeoutMilliseconds}ms waiting for ${description} at ` +
          `${path}. If the trigger threw, the Functions emulator log says so.`,
      );
    }
    await settle(POLL_INTERVAL_MILLISECONDS);
  }
}

async function settle(milliseconds) {
  await new Promise((resolve) => setTimeout(resolve, milliseconds));
}
