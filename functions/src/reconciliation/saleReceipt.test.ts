import assert from "node:assert/strict";
import test from "node:test";
import {DocumentData, Timestamp, Transaction} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {FakeFirestore} from "../testing/fakeFirestore";
import {
  createManualJobInTransaction,
  registerSaleReceipt,
  saleTriggerJobFields,
} from "./jobs";
import {mergeDirtyJob} from "./model";

/**
 * `registerSaleReceipt`, the whole of what one committed sale does to
 * reconciliation, against an in-memory Firestore.
 *
 * It is the entry point every reconciliation job comes from: `onDocumentCreated`
 * on `tenants/{tenantId}/sales/{saleId}`, declared `retry: true`, so a redelivery
 * is not a hypothetical - it is the documented behaviour of the trigger. One
 * transaction writes four kinds of document from a payload written by a till that
 * may have been offline for a day, and none of the branches that make that safe
 * had an assertion anywhere. `jobs.test.ts` beside this file drives it twice, but
 * only down its simplest path: one sale, one valid line, one new bucket.
 *
 * What is pinned here is the rest of it - the receipt that makes a redelivery
 * free, the line validation that keeps a malformed sale out of the stock ledger,
 * the anomaly record that is the only place an operator ever sees one, the refusal
 * to adopt a job document that a predictable ID let something else create, and the
 * movement ID that stops being the sale ID before a Firestore path stops being
 * legal.
 *
 * The double is the one in `../testing/fakeFirestore`. It refuses a `create` over
 * an existing document and stages a transaction's writes so a refused one lands
 * nothing, which is what most of the "and wrote nothing" assertions below rest on.
 */

const TENANT = "tenant-a";
/** A five-minute boundary, so `fiveMinuteBucket` returns it unchanged. */
const BUCKET = 1785842700000;
const JOB = `dirty_${BUCKET}`;
const BUSINESS_DATE = "2026-08-04";
const RECEIVED_AT = Timestamp.fromMillis(BUCKET + 1_000);

interface SaleOptions {
  saleId?: string;
  items?: unknown;
  businessDate?: string;
  receivedAt?: Timestamp;
  saleData?: DocumentData;
}

function register(db: FakeFirestore, options: SaleOptions = {}) {
  return registerSaleReceipt(db.asFirestore(), {
    tenantId: TENANT,
    saleId: options.saleId ?? "sale-1",
    businessDate: options.businessDate ?? BUSINESS_DATE,
    receivedAt: options.receivedAt ?? RECEIVED_AT,
    saleData: options.saleData ?? {items: "items" in options ? options.items : []},
  });
}

function jobPath(): string {
  return `tenants/${TENANT}/reconciliation_jobs/${JOB}`;
}

function dirtyPath(businessDate = BUSINESS_DATE): string {
  return `tenants/${TENANT}/reconciliation_dirty_days/${businessDate}`;
}

function receiptPath(saleId: string): string {
  return `tenants/${TENANT}/reconciliation_sale_receipts/${saleId}`;
}

function movementPath(productId: string, movementId: string): string {
  return `tenants/${TENANT}/products/${productId}/stock_movements/${movementId}`;
}

function anomalyCollection(): string {
  return `tenants/${TENANT}/reconciliation_anomalies`;
}

/** The document at `path`, refusing to assert about one that was never written. */
function stored(db: FakeFirestore, path: string): DocumentData {
  const document = db.read(path);
  assert.ok(document !== undefined, `Nothing was written at ${path}.`);
  return document;
}

/** Every path written so far that is a stock ledger entry. */
function movementPaths(db: FakeFirestore): string[] {
  return db.writtenPaths().filter((path) => path.includes("/stock_movements/"));
}

/** How `path` was last written - `create`, `set`, `merge`, `update`, `delete`. */
function writeKind(db: FakeFirestore, path: string): string | undefined {
  return [...db.writes].reverse().find((write) => write.path === path)?.kind;
}

async function assertRefused(work: Promise<unknown>, message: RegExp): Promise<void> {
  await assert.rejects(work, (error: unknown) =>
    error instanceof HttpsError &&
    error.code === "already-exists" &&
    message.test(error.message));
}

// ---------------------------------------------------------------------------
// The receipt, and what a redelivery costs
// ---------------------------------------------------------------------------

test("one sale writes its movement, its dirty day, its job, and its receipt", async () => {
  const db = new FakeFirestore();

  const registration = await register(db, {
    saleId: "sale-1",
    items: [{productId: "product-01", quantity: 2}],
  });

  assert.deepEqual(registration, {
    task: {tenantId: TENANT, jobId: JOB, generation: 0, revision: 0},
    invalidLineCount: 0,
  });
  // Four documents and no more. The trigger is the lightweight half of
  // reconciliation - it records what arrived and enqueues the pass that verifies
  // it - so anything else appearing here would be work done twice.
  assert.deepEqual(db.writtenPaths(), [
    dirtyPath(),
    jobPath(),
    movementPath("product-01", "sale_sale-1"),
    receiptPath("sale-1"),
  ].sort());
  assert.deepEqual(db.ids(anomalyCollection()), []);

  const movement = stored(db, movementPath("product-01", "sale_sale-1"));
  assert.equal(movement.movementId, "sale_sale-1");
  assert.equal(movement.sourceType, "sale");
  assert.equal(movement.sourceId, "sale-1");
  assert.equal(movement.productId, "product-01");
  // A sale takes stock out, so the ledger entry is negative. The sale line's own
  // quantity is positive; the sign is applied here and nowhere else.
  assert.equal(movement.quantityDelta, -2);
  assert.equal(movement.lineCount, 1);
  assert.ok((movement.occurredAt as Timestamp).isEqual(RECEIVED_AT));
  // Replayed as a replacement rather than merged. The document ID is derived from
  // the sale, so a second delivery addresses the same document, and a merge would
  // leave a field from a payload this delivery no longer carries.
  assert.equal(writeKind(db, movementPath("product-01", "sale_sale-1")), "set");

  const dirty = stored(db, dirtyPath());
  assert.equal(dirty.status, "dirty");
  assert.equal(dirty.businessDate, BUSINESS_DATE);
  assert.equal(dirty.revision, 1);
  assert.equal(dirty.saleReceiptCount, 1);
  assert.equal(dirty.invalidLineCount, 0);
  assert.equal(dirty.lastSaleId, "sale-1");
  assert.equal(writeKind(db, dirtyPath()), "merge");

  const receipt = stored(db, receiptPath("sale-1"));
  assert.equal(receipt.jobId, JOB);
  assert.equal(receipt.tenantId, TENANT);
  assert.equal(receipt.businessDate, BUSINESS_DATE);
  assert.equal(receipt.invalidLineCount, 0);
  // `create`, not `set`. It is the only write in the transaction that can refuse,
  // which is what makes two deliveries racing each other end with one of them
  // landing nothing at all.
  assert.equal(writeKind(db, receiptPath("sale-1")), "create");
});

test("a redelivered sale writes nothing and answers exactly as the first did", async () => {
  const db = new FakeFirestore();
  const sale: SaleOptions = {
    saleId: "sale-1",
    items: [{productId: "product-01", quantity: 2}, {productId: "product-01", quantity: "x"}],
  };
  const first = await register(db, sale);
  db.clearWrites();

  const second = await register(db, sale);

  // The queue redelivers on its own schedule and cannot be told not to, so the
  // second delivery has to be free rather than merely harmless. Both halves of
  // the answer come back off the receipt: the task the caller enqueues, and the
  // invalid-line count the trigger reports.
  assert.deepEqual(second, first);
  assert.deepEqual(db.writtenPaths(), []);
  // The counters are the ones that would show a double count, and both are
  // written with `FieldValue.increment` - the sentinel that has no idea a
  // delivery is a repeat.
  const dirty = stored(db, dirtyPath());
  assert.equal(dirty.saleReceiptCount, 1);
  assert.equal(dirty.invalidLineCount, 1);
  assert.equal(dirty.revision, 1);
  // And one movement, still carrying the first delivery's figures.
  assert.deepEqual(movementPaths(db), []);
  assert.equal(stored(db, movementPath("product-01", "sale_sale-1")).quantityDelta, -2);
  assert.equal(db.ids(anomalyCollection()).length, 1);
});

test("two deliveries that both read no receipt cannot both commit", async () => {
  // Started together and deliberately not awaited in turn, so both transactions
  // read the absent receipt before either writes. Against a real Firestore the
  // loser is aborted and retried, and the retry takes the free path above; the
  // double does not retry, so what is asserted here is the half that matters
  // either way - the loser is refused, and nothing it staged reaches the store.
  const db = new FakeFirestore();
  const items = [{productId: "product-01", quantity: 2}];

  const results = await Promise.allSettled([
    register(db, {saleId: "sale-1", items}),
    register(db, {saleId: "sale-1", items}),
  ]);

  assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
  const rejected = results.find((result) => result.status === "rejected");
  assert.ok(rejected?.status === "rejected");
  assert.match(String(rejected.reason), /ALREADY_EXISTS/);
  const dirty = stored(db, dirtyPath());
  assert.equal(dirty.saleReceiptCount, 1);
  assert.equal(dirty.revision, 1);
  assert.equal(stored(db, movementPath("product-01", "sale_sale-1")).quantityDelta, -2);
});

test("a receipt that disagrees with the delivery replaying it is refused", async () => {
  const db = new FakeFirestore();
  await register(db, {saleId: "sale-1", items: [{productId: "product-01", quantity: 2}]});
  db.clearWrites();

  // The sale ID is the receipt's identity, and everything else recorded on it is
  // what that sale was reconciled as. A redelivery disagreeing about any of it is
  // not the same sale, so returning the first delivery's task would enqueue a pass
  // over the wrong day or the wrong bucket - and writing would count it twice.
  await assertRefused(
    register(db, {saleId: "sale-1", businessDate: "2026-08-05"}),
    /receipt identity is inconsistent/
  );
  await assertRefused(
    register(db, {saleId: "sale-1", receivedAt: Timestamp.fromMillis(BUCKET + 300_000)}),
    /receipt identity is inconsistent/
  );

  assert.deepEqual(db.writtenPaths(), []);
  assert.equal(stored(db, dirtyPath()).saleReceiptCount, 1);
});

// ---------------------------------------------------------------------------
// What the sale's lines are allowed to be
// ---------------------------------------------------------------------------

test("lines of one product combine into a single movement", async () => {
  const db = new FakeFirestore();

  const registration = await register(db, {
    saleId: "sale-1",
    items: [
      {productId: "product-01", quantity: 2},
      {productId: "product-02", quantity: 1},
      {productId: "product-01", quantity: 3},
    ],
  });

  assert.equal(registration.invalidLineCount, 0);
  // Two lines of one product are one ledger entry, not two. The alternative is
  // two documents at one deterministic ID, where the second silently replaces the
  // first and the sale is recorded as having sold three of five.
  const combined = stored(db, movementPath("product-01", "sale_sale-1"));
  assert.equal(combined.quantityDelta, -5);
  assert.equal(combined.lineCount, 2);
  const single = stored(db, movementPath("product-02", "sale_sale-1"));
  assert.equal(single.quantityDelta, -1);
  assert.equal(single.lineCount, 1);
  // One ID per sale, shared across the products it touched: the movements of one
  // sale live under different products, so they cannot collide, and a replay
  // addresses every one of them again.
  assert.deepEqual(movementPaths(db), [
    movementPath("product-01", "sale_sale-1"),
    movementPath("product-02", "sale_sale-1"),
  ].sort());
  assert.deepEqual(db.ids(anomalyCollection()), []);
});

test("every rejected line shape is counted and none of them reaches the ledger", async () => {
  // A sale payload is written by a till, and the till is the offline half of this
  // system: a client three versions old, a partial write, an imported record. The
  // trigger cannot refuse the sale - it is already committed - so each of these
  // has to be counted and dropped rather than thrown on, which would leave the
  // day permanently unreconciled behind a poison trigger delivery.
  const cases: {name: string; line: unknown}[] = [
    {name: "null", line: null},
    {name: "a string", line: "product-01"},
    {name: "a number", line: 2},
    {name: "an array", line: [{productId: "product-01", quantity: 1}]},
    {name: "no productId", line: {quantity: 1}},
    {name: "an empty productId", line: {productId: "", quantity: 1}},
    {name: "a non-string productId", line: {productId: 17, quantity: 1}},
    {name: "an over-long productId", line: {productId: "p".repeat(129), quantity: 1}},
    {name: "a path in productId", line: {productId: "products/product-01", quantity: 1}},
    {name: "no quantity", line: {productId: "product-01"}},
    {name: "a fractional quantity", line: {productId: "product-01", quantity: 1.5}},
    {name: "a string quantity", line: {productId: "product-01", quantity: "2"}},
    {name: "a zero quantity", line: {productId: "product-01", quantity: 0}},
    {name: "a negative quantity", line: {productId: "product-01", quantity: -1}},
    {name: "an unsafe quantity", line: {productId: "product-01", quantity: 2 ** 53}},
  ];

  for (const {name, line} of cases) {
    // A fresh store per case, so `writtenPaths()` is everything this sale wrote.
    const db = new FakeFirestore();

    const registration = await register(db, {saleId: "sale-1", items: [line]});

    assert.equal(registration.invalidLineCount, 1, name);
    assert.deepEqual(movementPaths(db), [], name);
    // Counted, and still a sale: the day is marked dirty and the pass is enqueued
    // whatever the lines were, because the metrics and shift phases read the sale
    // document itself rather than this validation's opinion of it.
    assert.ok(registration.task, name);
    assert.equal(stored(db, dirtyPath()).invalidLineCount, 1, name);
  }
});

test("a productId of exactly the maximum length is a legal line", async () => {
  // 128 characters is Firestore's own document-ID limit, so the boundary belongs
  // to the ledger path this line becomes and not to a rule invented here.
  const db = new FakeFirestore();
  const productId = "p".repeat(128);

  const registration = await register(db, {
    saleId: "sale-1",
    items: [{productId, quantity: 4}],
  });

  assert.equal(registration.invalidLineCount, 0);
  assert.equal(stored(db, movementPath(productId, "sale_sale-1")).quantityDelta, -4);
});

test("a combined quantity past the safe integer range rejects only the line that breaks it", async () => {
  const db = new FakeFirestore();

  const registration = await register(db, {
    saleId: "sale-1",
    items: [
      {productId: "product-01", quantity: Number.MAX_SAFE_INTEGER},
      {productId: "product-01", quantity: 1},
    ],
  });

  // Each line is a safe integer and their sum is not. Past that point arithmetic
  // stops being exact, so a movement carrying the sum would be a figure the
  // reconciliation comparison could never match - and it is checked on the
  // running total rather than on the line, which is the only place it is visible.
  assert.equal(registration.invalidLineCount, 1);
  const movement = stored(db, movementPath("product-01", "sale_sale-1"));
  assert.equal(movement.quantityDelta, -Number.MAX_SAFE_INTEGER);
  assert.equal(movement.lineCount, 1);
});

test("a sale with no readable lines at all is one invalid line", async () => {
  // `items` is whatever the sale document holds. A sale written without it, or
  // with something that is not a list, is not zero invalid lines - it is a sale
  // whose stock effect is unknown, and the anomaly is the only trace of it.
  for (const saleData of [{}, {items: null}, {items: {productId: "product-01", quantity: 1}}, {
    items: "product-01 x2",
  }]) {
    const db = new FakeFirestore();

    const registration = await register(db, {saleId: "sale-1", saleData});

    assert.equal(registration.invalidLineCount, 1, JSON.stringify(saleData));
    assert.deepEqual(movementPaths(db), [], JSON.stringify(saleData));
    assert.equal(db.ids(anomalyCollection()).length, 1, JSON.stringify(saleData));
  }
});

test("anything past the hundredth line is counted and dropped", async () => {
  const db = new FakeFirestore();
  const items = [
    ...Array.from({length: 100}, () => ({productId: "product-01", quantity: 1})),
    ...Array.from({length: 5}, () => ({productId: "product-02", quantity: 1})),
  ];

  const registration = await register(db, {saleId: "sale-1", items});

  // The bound is on the transaction, not on the sale: a hundred products is a
  // hundred movement documents in one transaction, and Firestore's limit is 500
  // writes. Past it the lines are counted as invalid rather than ignored, which
  // is what makes an over-long sale visible to an operator instead of quietly
  // reconciling short.
  assert.equal(registration.invalidLineCount, 5);
  assert.deepEqual(movementPaths(db), [movementPath("product-01", "sale_sale-1")]);
  const movement = stored(db, movementPath("product-01", "sale_sale-1"));
  assert.equal(movement.quantityDelta, -100);
  assert.equal(movement.lineCount, 100);
});

// ---------------------------------------------------------------------------
// The anomaly record, which is where an operator sees any of this
// ---------------------------------------------------------------------------

test("invalid lines write one anomaly and the dirty day counts the same number", async () => {
  const db = new FakeFirestore();

  const registration = await register(db, {
    saleId: "sale-1",
    items: [{productId: "product-01", quantity: 2}, null, {productId: "product-01", quantity: "x"}],
  });

  assert.equal(registration.invalidLineCount, 2);
  const anomalyIds = db.ids(anomalyCollection());
  assert.equal(anomalyIds.length, 1, "one sale writes at most one anomaly, however many lines fail");
  // Deterministic and derived from the sale, so a redelivery that got past the
  // receipt would address this document again rather than accumulate a second.
  assert.match(anomalyIds[0], /^sale_[0-9a-f]{40}$/);
  const anomaly = stored(db, `${anomalyCollection()}/${anomalyIds[0]}`);
  assert.equal(anomaly.anomalyType, "invalid_sale_lines");
  assert.equal(anomaly.sourceType, "sale");
  assert.equal(anomaly.sourceId, "sale-1");
  assert.equal(anomaly.invalidLineCount, 2);
  assert.ok((anomaly.observedAt as Timestamp).isEqual(RECEIVED_AT));
  // The counter and the record are written from one figure in one transaction. If
  // they could disagree, the dirty day would report a number of malformed lines
  // that no anomaly document accounts for.
  assert.equal(stored(db, dirtyPath()).invalidLineCount, 2);

  // A second sale, its own anomaly, and one running total for the day.
  const second = await register(db, {saleId: "sale-2", items: [{quantity: 1}]});

  assert.equal(second.invalidLineCount, 1);
  assert.equal(db.ids(anomalyCollection()).length, 2);
  const dirty = stored(db, dirtyPath());
  assert.equal(dirty.invalidLineCount, 3);
  assert.equal(dirty.saleReceiptCount, 2);
  // `revision` is read and incremented rather than counted with a sentinel: it is
  // the value the reconciliation pass compares against to decide whether the day
  // went dirty again while it was running.
  assert.equal(dirty.revision, 2);
  assert.equal(dirty.lastSaleId, "sale-2");
});

test("a sale whose lines are all valid writes no anomaly at all", async () => {
  const db = new FakeFirestore();

  await register(db, {saleId: "sale-1", items: [{productId: "product-01", quantity: 1}]});

  // The collection is read by the differences surface, so an empty anomaly record
  // written for every clean sale would bury the ones that mean something.
  assert.deepEqual(db.ids(anomalyCollection()), []);
  assert.equal(stored(db, dirtyPath()).invalidLineCount, 0);
});

// ---------------------------------------------------------------------------
// The bucket, whose document ID anything could guess
// ---------------------------------------------------------------------------

test("a dirty bucket created by another source is refused, and the sale writes nothing", async () => {
  // `dirty_<bucket>` is derived from the clock alone, so unlike every other job ID
  // in this pipeline it is predictable. A manual job created at that ID - by a
  // caller passing a crafted job ID, or by a future writer choosing the same
  // scheme - must not be adopted by the sale trigger, because the trigger would
  // then drive a job whose mode, checkpoint, and requester belong to somebody else.
  const db = new FakeFirestore();
  await db.runTransaction(async (transaction) => createManualJobInTransaction(
    db.asFirestore(),
    transaction as unknown as Transaction,
    {
      tenantId: TENANT,
      jobId: JOB,
      actorUid: "uid-owner",
      requestId: "req-1",
      mode: "full",
      localDate: BUSINESS_DATE,
    }
  ));
  db.clearWrites();

  await assertRefused(
    register(db, {saleId: "sale-1", items: [{productId: "product-01", quantity: 2}]}),
    /belongs to another source/
  );

  // Refused as a whole. The movement, the dirty day, and the receipt are staged
  // in the same transaction as the job write, so a sale that cannot claim its
  // bucket leaves no half-recorded ledger entry and no receipt that would make a
  // later redelivery think the work was done.
  assert.deepEqual(db.writtenPaths(), []);
  assert.equal(db.read(dirtyPath()), undefined);
  assert.equal(db.read(receiptPath("sale-1")), undefined);
  assert.equal(stored(db, jobPath()).mode, "full");
});

test("a sale-trigger job holding another bucket's key is refused too", async () => {
  // The same defence one step in: the source is right and the bucket is not. The
  // job document's `sourceKey` is the bucket it was created for, so a document
  // sitting at this ID with another bucket's key is not this bucket's job, and
  // merging into it would reconcile the wrong five minutes.
  const db = new FakeFirestore();
  db.seed(jobPath(), saleTriggerJobFields({
    tenantId: TENANT,
    bucket: BUCKET - 300_000,
    businessDate: BUSINESS_DATE,
    decision: mergeDirtyJob(),
  }).create);
  db.clearWrites();

  await assertRefused(
    register(db, {saleId: "sale-1", items: [{productId: "product-01", quantity: 2}]}),
    /belongs to another source/
  );

  assert.deepEqual(db.writtenPaths(), []);
});

// ---------------------------------------------------------------------------
// The movement ID, and the path it has to stay inside
// ---------------------------------------------------------------------------

test("past 120 characters of sale ID the movement ID becomes a hash", async () => {
  const boundary = "s".repeat(120);
  const beyond = "s".repeat(121);
  const alsoBeyond = `${"s".repeat(120)}t`;

  const atBoundary = new FakeFirestore();
  await register(atBoundary, {saleId: boundary, items: [{productId: "product-01", quantity: 1}]});
  // Up to the boundary the movement is addressed by the sale itself, which is what
  // makes a ledger entry traceable by reading its ID.
  assert.deepEqual(movementPaths(atBoundary), [movementPath("product-01", `sale_${boundary}`)]);

  const db = new FakeFirestore();
  await register(db, {saleId: beyond, items: [{productId: "product-01", quantity: 1}]});
  await register(db, {saleId: alsoBeyond, items: [{productId: "product-01", quantity: 1}]});

  const hashed = movementPaths(db).map((path) => path.split("/").slice(-1)[0]);
  assert.equal(hashed.length, 2);
  for (const movementId of hashed) {
    // Firestore's document-ID limit is 1500 bytes and a sale ID is not bounded by
    // anything the till promises, so past the point where `sale_<saleId>` could
    // stop being a legal path it becomes a digest of exactly the same length.
    assert.match(movementId, /^sale_[0-9a-f]{40}$/);
  }
  // Two sale IDs differing in one character, so the digest has to separate them.
  // Sharing a movement ID would mean the second sale replacing the first's ledger
  // entry, at a document nothing else would ever look at again.
  assert.notEqual(hashed[0], hashed[1]);
  // And the sale is still findable: the ID stopped naming it, so the document has
  // to. `sourceId` is what the stock verification reads the movement back by.
  for (const path of movementPaths(db)) {
    assert.match(String(stored(db, path).sourceId), /^s{120}[st]$/);
  }
});

// ---------------------------------------------------------------------------
// When the stock left the shelf
// ---------------------------------------------------------------------------

test("a sale rung up offline moves its stock when it was rung up", async () => {
  const db = new FakeFirestore();
  const rungUp = RECEIVED_AT.toMillis() - 3 * 60 * 60 * 1000;

  await register(db, {
    saleData: {items: [{productId: "product-01", quantity: 1}], clientCreatedAtMs: rungUp},
  });

  const movement = stored(db, movementPath("product-01", "sale_sale-1"));
  assert.equal((movement.occurredAt as Timestamp).toMillis(), rungUp);
});

test("a till whose clock runs ahead cannot date a sale after it arrived", async () => {
  const db = new FakeFirestore();

  await register(db, {
    saleData: {
      items: [{productId: "product-01", quantity: 1}],
      clientCreatedAtMs: RECEIVED_AT.toMillis() + 10 * 60 * 1000,
    },
  });

  const movement = stored(db, movementPath("product-01", "sale_sale-1"));
  assert.ok((movement.occurredAt as Timestamp).isEqual(RECEIVED_AT));
});
